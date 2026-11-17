use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::time::{Duration, Instant};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct HealthStatus {
    pub status: ServiceStatus,
    pub components: HashMap<String, ComponentHealth>,
    pub timestamp: i64,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub enum ServiceStatus {
    Healthy,
    Degraded,
    Unhealthy,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ComponentHealth {
    pub status: ServiceStatus,
    pub message: String,
    pub last_check: i64,
    pub latency_ms: Option<u64>,
}

pub struct HealthChecker {
    components: RwLock<HashMap<String, ComponentHealth>>,
    global_status: RwLock<ServiceStatus>,
}

impl HealthChecker {
    pub fn new() -> Self {
        Self {
            components: RwLock::new(HashMap::new()),
            global_status: RwLock::new(ServiceStatus::Healthy),
        }
    }
    
    pub fn register_component(&self, name: String) {
        let mut components = self.components.write();
        components.insert(name.clone(), ComponentHealth {
            status: ServiceStatus::Healthy,
            message: "Registered".to_string(),
            last_check: chrono::Utc::now().timestamp(),
            latency_ms: None,
        });
    }
    
    pub fn update_component(&self, name: &str, status: ServiceStatus, message: String, latency_ms: Option<u64>) {
        {
            let mut components = self.components.write();
            if let Some(component) = components.get_mut(name) {
                component.status = status.clone();
                component.message = message;
                component.last_check = chrono::Utc::now().timestamp();
                component.latency_ms = latency_ms;
            }
        }
        
        self.update_global_status();
    }
    
    pub fn check_component<F, R>(&self, name: &str, check: F) -> R
    where
        F: FnOnce() -> Result<R, Box<dyn std::error::Error>>,
    {
        let start = Instant::now();
        let result = check();
        let latency = start.elapsed();
        
        match result {
            Ok(r) => {
                self.update_component(name, ServiceStatus::Healthy, "OK".to_string(), Some(latency.as_millis() as u64));
                r
            }
            Err(e) => {
                self.update_component(name, ServiceStatus::Unhealthy, e.to_string(), Some(latency.as_millis() as u64));
                panic!("Component check failed: {}", e);
            }
        }
    }
    
    pub fn get_status(&self) -> HealthStatus {
        let components = self.components.read();
        let global_status = self.global_status.read();
        
        HealthStatus {
            status: global_status.clone(),
            components: components.clone(),
            timestamp: chrono::Utc::now().timestamp(),
        }
    }
    
    fn update_global_status(&self) {
        let components = self.components.read();
        let mut has_unhealthy = false;
        let mut has_degraded = false;
        
        for component in components.values() {
            match component.status {
                ServiceStatus::Unhealthy => has_unhealthy = true,
                ServiceStatus::Degraded => has_degraded = true,
                ServiceStatus::Healthy => {}
            }
        }
        
        let mut global_status = self.global_status.write();
        *global_status = if has_unhealthy {
            ServiceStatus::Unhealthy
        } else if has_degraded {
            ServiceStatus::Degraded
        } else {
            ServiceStatus::Healthy
        };
    }
}

impl Default for HealthChecker {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_health_checker() {
        let checker = HealthChecker::new();
        checker.register_component("test".to_string());
        
        checker.update_component("test", ServiceStatus::Healthy, "OK".to_string(), Some(10));
        let status = checker.get_status();
        
        assert_eq!(status.status, ServiceStatus::Healthy);
        assert!(status.components.contains_key("test"));
    }
    
    #[test]
    fn test_unhealthy_component() {
        let checker = HealthChecker::new();
        checker.register_component("test".to_string());
        
        checker.update_component("test", ServiceStatus::Unhealthy, "Failed".to_string(), None);
        let status = checker.get_status();
        
        assert_eq!(status.status, ServiceStatus::Unhealthy);
    }
}
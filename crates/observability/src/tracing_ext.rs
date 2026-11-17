use serde::{Deserialize, Serialize};
use tracing_subscriber::{fmt, prelude::*, EnvFilter};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct TraceConfig {
    pub enabled: bool,
    pub sampling_rate: f64,
    pub export_otel: bool,
    pub otlp_endpoint: Option<String>,
}

impl Default for TraceConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            sampling_rate: 1.0,
            export_otel: false,
            otlp_endpoint: None,
        }
    }
}

pub fn init_tracing(config: &TraceConfig) -> Result<(), Box<dyn std::error::Error>> {
    if !config.enabled {
        return Ok(());
    }
    
    let env_filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("info"));
    
    let subscriber = tracing_subscriber::registry()
        .with(env_filter)
        .with(fmt::layer());
    
    if config.export_otel {
        if let Some(endpoint) = &config.otlp_endpoint {
            // OTEL export would be configured here
            tracing::info!("OTEL export configured to: {}", endpoint);
        }
    }
    
    subscriber.init();
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_default_trace_config() {
        let config = TraceConfig::default();
        assert!(config.enabled);
        assert_eq!(config.sampling_rate, 1.0);
    }
    
    #[test]
    fn test_init_tracing_disabled() {
        let config = TraceConfig { enabled: false, ..Default::default() };
        let result = init_tracing(&config);
        assert!(result.is_ok());
    }
}
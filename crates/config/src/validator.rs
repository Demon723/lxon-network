use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum ValidationError {
    #[error("required field missing: {0}")] RequiredMissing(String),
    #[error("invalid type for {0}: expected {1}")] InvalidType(String, String),
    #[error("value out of range for {0}")] OutOfRange(String),
    #[error("custom validation failed: {0}")] Custom(String),
}

#[derive(Clone, Serialize, Deserialize)]
pub struct ValidationRule {
    pub field: String,
    pub required: bool,
    pub field_type: String,
    pub min: Option<f64>,
    pub max: Option<f64>,
}

pub struct ConfigValidator {
    rules: Vec<ValidationRule>,
}

impl ConfigValidator {
    pub fn new() -> Self {
        Self { rules: Vec::new() }
    }
    
    pub fn add_rule(&mut self, rule: ValidationRule) {
        self.rules.push(rule);
    }
    
    pub fn validate(&self, config: &serde_json::Value) -> Result<(), ValidationError> {
        for rule in &self.rules {
            self.validate_rule(config, rule)?;
        }
        Ok(())
    }
    
    fn validate_rule(&self, config: &serde_json::Value, rule: &ValidationRule) -> Result<(), ValidationError> {
        let parts: Vec<&str> = rule.field.split('.').collect();
        let mut current = config;
        
        for part in &parts {
            match current {
                serde_json::Value::Object(map) => {
                    current = map.get(*part).ok_or_else(|| {
                        ValidationError::RequiredMissing(rule.field.clone())
                    })?;
                }
                _ => return Err(ValidationError::InvalidType(rule.field.clone(), "object".to_string())),
            }
        }
        
        // Type validation
        match rule.field_type.as_str() {
            "string" => {
                if !current.is_string() {
                    return Err(ValidationError::InvalidType(rule.field.clone(), "string".to_string()));
                }
            }
            "number" => {
                if !current.is_number() {
                    return Err(ValidationError::InvalidType(rule.field.clone(), "number".to_string()));
                }
            }
            "boolean" => {
                if !current.is_boolean() {
                    return Err(ValidationError::InvalidType(rule.field.clone(), "boolean".to_string()));
                }
            }
            _ => {}
        }
        
        // Range validation
        if let Some(min) = rule.min {
            if let Some(num) = current.as_f64() {
                if num < min {
                    return Err(ValidationError::OutOfRange(rule.field.clone()));
                }
            }
        }
        
        if let Some(max) = rule.max {
            if let Some(num) = current.as_f64() {
                if num > max {
                    return Err(ValidationError::OutOfRange(rule.field.clone()));
                }
            }
        }
        
        Ok(())
    }
}

impl Default for ConfigValidator {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_validator() {
        let mut validator = ConfigValidator::new();
        validator.add_rule(ValidationRule {
            field: "test.field".to_string(),
            required: true,
            field_type: "string".to_string(),
            min: None,
            max: None,
        });
        
        let config = serde_json::json!({"test": {"field": "value"}});
        assert!(validator.validate(&config).is_ok());
    }
}
use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum ParseError {
    #[error("TOML parse error: {0}")] Toml(String),
    #[error("YAML parse error: {0}")] Yaml(String),
    #[error("JSON parse error: {0}")] Json(String),
    #[error("unknown format")] UnknownFormat,
}

#[derive(Clone, Copy, Debug, Serialize, Deserialize)]
pub enum ConfigFormat {
    Toml,
    Yaml,
    Json,
}

impl ConfigFormat {
    pub fn from_path(path: &std::path::Path) -> Self {
        match path.extension().and_then(|e| e.to_str()) {
            Some("toml") => ConfigFormat::Toml,
            Some("yaml") | Some("yml") => ConfigFormat::Yaml,
            Some("json") => ConfigFormat::Json,
            _ => ConfigFormat::Toml, // Default to TOML
        }
    }
}

pub struct ConfigParser {
    format: ConfigFormat,
}

impl ConfigParser {
    pub fn new(format: ConfigFormat) -> Self {
        Self { format }
    }
    
    pub fn parse(&self, content: &str) -> Result<serde_json::Value, ParseError> {
        match self.format {
            ConfigFormat::Toml => {
                let value: toml::Value = toml::from_str(content)
                    .map_err(|e| ParseError::Toml(e.to_string()))?;
                serde_json::to_value(value).map_err(|e| ParseError::Json(e.to_string()))
            }
            ConfigFormat::Yaml => {
                let value: serde_yaml::Value = serde_yaml::from_str(content)
                    .map_err(|e| ParseError::Yaml(e.to_string()))?;
                serde_json::to_value(value).map_err(|e| ParseError::Json(e.to_string()))
            }
            ConfigFormat::Json => {
                serde_json::from_str(content)
                    .map_err(|e| ParseError::Json(e.to_string()))
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_json_parser() {
        let parser = ConfigParser::new(ConfigFormat::Json);
        let result = parser.parse(r#"{"test":"value"}"#);
        assert!(result.is_ok());
    }
    
    #[test]
    fn test_toml_parser() {
        let parser = ConfigParser::new(ConfigFormat::Toml);
        let result = parser.parse(r#"test = "value""#);
        assert!(result.is_ok());
    }
}
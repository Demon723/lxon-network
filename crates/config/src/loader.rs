use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;
use super::parser::ConfigFormat;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum ConfigSource {
    File(PathBuf),
    Environment,
    String(String),
    Memory(HashMap<String, String>),
}

pub struct ConfigLoader {
    sources: Vec<ConfigSource>,
    cache: RwLock<HashMap<String, serde_json::Value>>,
}

impl ConfigLoader {
    pub fn new() -> Self {
        Self {
            sources: Vec::new(),
            cache: RwLock::new(HashMap::new()),
        }
    }
    
    pub fn add_source(&mut self, source: ConfigSource) {
        self.sources.push(source);
    }
    
    pub fn load(&self) -> Result<serde_json::Value, Box<dyn std::error::Error>> {
        let mut merged = serde_json::Value::Object(serde_json::Map::new());
        
        for source in &self.sources {
            let value = self.load_source(source)?;
            self.merge_values(&mut merged, value);
        }
        
        Ok(merged)
    }
    
    fn load_source(&self, source: &ConfigSource) -> Result<serde_json::Value, Box<dyn std::error::Error>> {
        match source {
            ConfigSource::File(path) => {
                let content = std::fs::read_to_string(path)?;
                let format = ConfigFormat::from_path(path);
                let parser = super::parser::ConfigParser::new(format);
                parser.parse(&content)
            }
            ConfigSource::Environment => {
                let mut map = serde_json::Map::new();
                for (key, value) in std::env::vars() {
                    let config_key = key.to_lowercase().replace('_', ".");
                    self.set_nested_value(&mut map, &config_key, &value);
                }
                Ok(serde_json::Value::Object(map))
            }
            ConfigSource::String(content) => {
                let parser = super::parser::ConfigParser::new(ConfigFormat::Json);
                parser.parse(content)
            }
            ConfigSource::Memory(map) => {
                let mut json_map = serde_json::Map::new();
                for (key, value) in map {
                    self.set_nested_value(&mut json_map, key, value);
                }
                Ok(serde_json::Value::Object(json_map))
            }
        }
    }
    
    fn merge_values(&self, target: &mut serde_json::Value, source: serde_json::Value) {
        match (target, source) {
            (serde_json::Value::Object(t), serde_json::Value::Object(s)) => {
                for (key, value) in s {
                    if t.contains_key(&key) {
                        self.merge_values(t.get_mut(&key).unwrap(), value);
                    } else {
                        t.insert(key, value);
                    }
                }
            }
            (_, s) => {
                *target = s;
            }
        }
    }
    
    fn set_nested_value(&self, map: &mut serde_json::Map, key: &str, value: &str) {
        let parts: Vec<&str> = key.split('.').collect();
        let mut current = map;
        
        for (i, part) in parts.iter().enumerate() {
            if i == parts.len() - 1 {
                current.insert(part.to_string(), serde_json::Value::String(value.to_string()));
            } else {
                if !current.contains_key(*part) {
                    current.insert(part.to_string(), serde_json::Value::Object(serde_json::Map::new()));
                }
                current = current.get_mut(*part).unwrap().as_object_mut().unwrap();
            }
        }
    }
}

impl Default for ConfigLoader {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_config_loader() {
        let mut loader = ConfigLoader::new();
        loader.add_source(ConfigSource::String(r#"{"test":"value"}"#.to_string()));
        
        let config = loader.load().unwrap();
        assert_eq!(config["test"], "value");
    }
}
use serde::{Deserialize, Serialize};
use tracing_subscriber::{fmt, prelude::*, EnvFilter};
use tracing_subscriber::Layer;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct LogConfig {
    pub level: String,
    pub format: LogFormat,
    pub targets: Vec<String>,
    pub json_output: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum LogFormat {
    Pretty,
    Json,
    Compact,
}

impl Default for LogConfig {
    fn default() -> Self {
        Self {
            level: "info".to_string(),
            format: LogFormat::Pretty,
            targets: vec![],
            json_output: false,
        }
    }
}

pub fn init_logging(config: &LogConfig) -> Result<(), Box<dyn std::error::Error>> {
    let env_filter = if config.targets.is_empty() {
        EnvFilter::try_from_default_env()
            .unwrap_or_else(|_| EnvFilter::new(&config.level))
    } else {
        let filter = config.targets.iter()
            .map(|t| format!("{}={}", t, config.level))
            .collect::<Vec<_>>()
            .join(",");
        EnvFilter::new(&filter)
    };
    
    let subscriber = tracing_subscriber::registry()
        .with(env_filter);
    
    match config.format {
        LogFormat::Pretty => {
            subscriber.with(fmt::layer().pretty()).init();
        }
        LogFormat::Json => {
            subscriber.with(fmt::layer().json()).init();
        }
        LogFormat::Compact => {
            subscriber.with(fmt::layer().compact()).init();
        }
    }
    
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_default_config() {
        let config = LogConfig::default();
        assert_eq!(config.level, "info");
    }
    
    #[test]
    fn test_init_logging() {
        let config = LogConfig::default();
        let result = init_logging(&config);
        assert!(result.is_ok());
    }
}
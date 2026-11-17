use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum StoreError {
    #[error("key not found")] KeyNotFound,
    #[error("io error: {0}")] Io(String),
    #[error("serialization error: {0}")] Serialization(String),
    #[error("database error: {0}")] Database(String),
}

pub trait Store: Send + Sync {
    fn get(&self, key: &[u8]) -> Result<Option<Vec<u8>>, StoreError>;
    fn put(&self, key: &[u8], value: &[u8]) -> Result<(), StoreError>;
    fn delete(&self, key: &[u8]) -> Result<(), StoreError>;
    fn exists(&self, key: &[u8]) -> Result<bool, StoreError>;
    fn batch(&self) -> Result<Box<dyn WriteBatch>, StoreError>;
    fn iterator(&self) -> Result<Box<dyn Iterator<Item = (Vec<u8>, Vec<u8>)>>, StoreError>;
}

pub trait WriteBatch {
    fn put(&mut self, key: &[u8], value: &[u8]) -> Result<(), StoreError>;
    fn delete(&mut self, key: &[u8]) -> Result<(), StoreError>;
    fn commit(self: Box<Self>) -> Result<(), StoreError>;
}

#[derive(Clone, Serialize, Deserialize)]
pub struct StoreConfig {
    pub path: String,
    pub create_if_missing: bool,
    pub cache_size_mb: usize,
}

impl Default for StoreConfig {
    fn default() -> Self {
        Self {
            path: "./data".to_string(),
            create_if_missing: true,
            cache_size_mb: 256,
        }
    }
}
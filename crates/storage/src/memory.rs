use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use super::interface::{Store, StoreError, WriteBatch};

#[derive(Clone, Serialize, Deserialize)]
pub struct MemoryConfig {
    pub max_size: usize,
}

impl Default for MemoryConfig {
    fn default() -> Self {
        Self { max_size: 1_000_000 }
    }
}

pub struct MemoryStore {
    data: RwLock<HashMap<Vec<u8>, Vec<u8>>>,
    config: MemoryConfig,
}

impl MemoryStore {
    pub fn new(config: MemoryConfig) -> Self {
        Self {
            data: RwLock::new(HashMap::new()),
            config,
        }
    }
    
    pub fn clear(&self) {
        self.data.write().clear();
    }
    
    pub fn size(&self) -> usize {
        self.data.read().len()
    }
}

impl Default for MemoryStore {
    fn default() -> Self {
        Self::new(MemoryConfig::default())
    }
}

impl Store for MemoryStore {
    fn get(&self, key: &[u8]) -> Result<Option<Vec<u8>>, StoreError> {
        Ok(self.data.read().get(key).cloned())
    }
    
    fn put(&self, key: &[u8], value: &[u8]) -> Result<(), StoreError> {
        let mut data = self.data.write();
        
        if data.len() >= self.config.max_size {
            return Err(StoreError::Database("Memory store full".to_string()));
        }
        
        data.insert(key.to_vec(), value.to_vec());
        Ok(())
    }
    
    fn delete(&self, key: &[u8]) -> Result<(), StoreError> {
        self.data.write().remove(key);
        Ok(())
    }
    
    fn exists(&self, key: &[u8]) -> Result<bool, StoreError> {
        Ok(self.data.read().contains_key(key))
    }
    
    fn batch(&self) -> Result<Box<dyn WriteBatch>, StoreError> {
        Ok(Box::new(MemoryBatch {
            data: self.data.clone(),
            operations: Vec::new(),
        }))
    }
    
    fn iterator(&self) -> Result<Box<dyn Iterator<Item = (Vec<u8>, Vec<u8>)>>, StoreError> {
        let data = self.data.read();
        let items: Vec<(Vec<u8>, Vec<u8>)> = data.iter().map(|(k, v)| (k.clone(), v.clone())).collect();
        Ok(Box::new(items.into_iter()))
    }
}

struct MemoryBatch {
    data: parking_lot::RwLock<HashMap<Vec<u8>, Vec<u8>>>,
    operations: Vec<(Vec<u8>, Option<Vec<u8>>)>,
}

impl WriteBatch for MemoryBatch {
    fn put(&mut self, key: &[u8], value: &[u8]) -> Result<(), StoreError> {
        self.operations.push((key.to_vec(), Some(value.to_vec())));
        Ok(())
    }
    
    fn delete(&mut self, key: &[u8]) -> Result<(), StoreError> {
        self.operations.push((key.to_vec(), None));
        Ok(())
    }
    
    fn commit(self: Box<Self>) -> Result<(), StoreError> {
        let mut data = self.data.write();
        
        for (key, value) in self.operations {
            match value {
                Some(v) => { data.insert(key, v); }
                None => { data.remove(&key); }
            }
        }
        
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_memory_store() {
        let store = MemoryStore::default();
        
        store.put(b"key1", b"value1").unwrap();
        assert_eq!(store.get(b"key1").unwrap(), Some(b"value1".to_vec()));
        assert!(store.exists(b"key1").unwrap());
        
        store.delete(b"key1").unwrap();
        assert!(!store.exists(b"key1").unwrap());
    }
    
    #[test]
    fn test_memory_batch() {
        let store = MemoryStore::default();
        
        let mut batch = store.batch().unwrap();
        batch.put(b"key1", b"value1").unwrap();
        batch.put(b"key2", b"value2").unwrap();
        batch.commit().unwrap();
        
        assert_eq!(store.size(), 2);
    }
}
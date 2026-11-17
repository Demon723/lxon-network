use rocksdb::{DB, Options, WriteBatch as RocksWriteBatch};
use serde::{Deserialize, Serialize};
use std::path::Path;
use super::interface::{Store, StoreError, WriteBatch, StoreConfig};

#[derive(Clone, Serialize, Deserialize)]
pub struct RocksDBConfig {
    pub path: String,
    pub create_if_missing: bool,
    pub cache_size_mb: usize,
    pub max_open_files: usize,
}

impl Default for RocksDBConfig {
    fn default() -> Self {
        Self {
            path: "./data/rocksdb".to_string(),
            create_if_missing: true,
            cache_size_mb: 256,
            max_open_files: 1000,
        }
    }
}

impl From<StoreConfig> for RocksDBConfig {
    fn from(config: StoreConfig) -> Self {
        Self {
            path: config.path,
            create_if_missing: config.create_if_missing,
            cache_size_mb: config.cache_size_mb,
            max_open_files: 1000,
        }
    }
}

pub struct RocksDB {
    db: DB,
}

impl RocksDB {
    pub fn new(config: RocksDBConfig) -> Result<Self, StoreError> {
        let path = Path::new(&config.path);
        
        if config.create_if_missing {
            std::fs::create_dir_all(path).map_err(|e| StoreError::Io(e.to_string()))?;
        }
        
        let mut opts = Options::default();
        opts.create_if_missing(config.create_if_missing);
        opts.set_max_open_files(config.max_open_files);
        
        let db = DB::open(&opts, path).map_err(|e| StoreError::Database(e.to_string()))?;
        
        Ok(Self { db })
    }
    
    pub fn flush(&self) -> Result<(), StoreError> {
        self.db.flush().map_err(|e| StoreError::Database(e.to_string()))
    }
}

impl Store for RocksDB {
    fn get(&self, key: &[u8]) -> Result<Option<Vec<u8>>, StoreError> {
        match self.db.get(key) {
            Ok(Some(value)) => Ok(Some(value)),
            Ok(None) => Ok(None),
            Err(e) => Err(StoreError::Database(e.to_string())),
        }
    }
    
    fn put(&self, key: &[u8], value: &[u8]) -> Result<(), StoreError> {
        self.db.put(key, value).map_err(|e| StoreError::Database(e.to_string()))
    }
    
    fn delete(&self, key: &[u8]) -> Result<(), StoreError> {
        self.db.delete(key).map_err(|e| StoreError::Database(e.to_string()))
    }
    
    fn exists(&self, key: &[u8]) -> Result<bool, StoreError> {
        match self.db.get(key) {
            Ok(_) => Ok(true),
            Err(ref e) if e.to_string().contains("not found") => Ok(false),
            Err(e) => Err(StoreError::Database(e.to_string())),
        }
    }
    
    fn batch(&self) -> Result<Box<dyn WriteBatch>, StoreError> {
        Ok(Box::new(RocksBatch {
            batch: RocksWriteBatch::default(),
        }))
    }
    
    fn iterator(&self) -> Result<Box<dyn Iterator<Item = (Vec<u8>, Vec<u8>)>>, StoreError> {
        let iter = self.db.iterator(rocksdb::IteratorMode::Start);
        let items: Vec<(Vec<u8>, Vec<u8>)> = iter
            .map(|r| r.map_err(|e| StoreError::Database(e.to_string())))
            .collect::<Result<_, _>>()?;
        
        Ok(Box::new(items.into_iter()))
    }
}

struct RocksBatch {
    batch: RocksWriteBatch,
}

impl WriteBatch for RocksBatch {
    fn put(&mut self, key: &[u8], value: &[u8]) -> Result<(), StoreError> {
        self.batch.put(key, value);
        Ok(())
    }
    
    fn delete(&mut self, key: &[u8]) -> Result<(), StoreError> {
        self.batch.delete(key);
        Ok(++)
    }
    
    fn commit(self: Box<Self>) -> Result<(), StoreError> {
        // This would need access to the DB instance to commit
        // For now, we'll return an error
        Err(StoreError::Database("Batch commit not implemented".to_string()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;
    
    #[test]
    fn test_rocksdb_creation() {
        let dir = tempdir().unwrap();
        let config = RocksDBConfig {
            path: dir.path().to_str().unwrap().to_string(),
            ..Default::default()
        };
        
        let db = RocksDB::new(config);
        assert!(db.is_ok());
    }
}
//! Storage layer for LXON with RocksDB and in-memory implementations.
pub mod rocks;
pub mod memory;
pub mod interface;

pub use rocks::{RocksDB, RocksDBConfig};
pub use memory::{MemoryStore, MemoryConfig};
pub use interface::{Store, StoreError, WriteBatch};
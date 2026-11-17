use crypto_pqc::Hash256;
use dashmap::DashMap;

pub struct L2State {
    accounts: DashMap<Hash256, Hash256>,
    nullifiers: DashMap<Hash256, bool>,
}

impl L2State {
    pub fn new() -> Self { Self { accounts: DashMap::new(), nullifiers: DashMap::new() } }
    pub fn get(&self, a: &Hash256) -> Option<Hash256> { self.accounts.get(a).map(|v| *v) }
    pub fn set(&self, a: Hash256, c: Hash256) { self.accounts.insert(a, c); }
    pub fn is_spent(&self, n: &Hash256) -> bool { self.nullifiers.contains_key(n) }
    pub fn mark_spent(&self, n: Hash256) -> Result<(), StateError> {
        if self.nullifiers.insert(n, true).is_some() { return Err(StateError::DoubleSpend); }
        Ok(())
    }
    pub fn root(&self) -> Hash256 {
        let mut leaves: Vec<Hash256> = self.accounts.iter().map(|kv| {
            let mut buf = [0u8; 64];
            buf[..32].copy_from_slice(kv.key());
            buf[32..].copy_from_slice(kv.value());
            crypto_pqc::hash_256(b"lxon/l2/account", &buf)
        }).collect();
        leaves.sort();
        crypto_pqc::merkle_root(b"lxon/l2/state", &leaves)
    }
}
impl Default for L2State { fn default() -> Self { Self::new() } }

#[derive(Debug, thiserror::Error)]
pub enum StateError { #[error("double spend")] DoubleSpend }
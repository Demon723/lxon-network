use serde::{Deserialize, Serialize};
use crate::domain;

#[derive(Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Debug)]
pub struct Nullifier(pub [u8; 32]);

impl Nullifier {
    pub fn derive(nk: &[u8; 32], rho: &[u8; 32]) -> Self {
        let mut h = blake3::Hasher::new();
        h.update(domain::NULLIFIER); h.update(nk); h.update(rho);
        Nullifier(h.finalize().as_bytes()[..32].try_into().unwrap())
    }
}

pub struct NullifierSet { inner: std::sync::RwLock<std::collections::HashSet<Nullifier>> }

impl NullifierSet {
    pub fn new() -> Self { Self { inner: std::sync::RwLock::new(std::collections::HashSet::new()) } }
    pub fn contains(&self, n: &Nullifier) -> bool { self.inner.read().unwrap().contains(n) }
    pub fn insert(&self, n: Nullifier) -> Result<(), NullifierError> {
        if !self.inner.write().unwrap().insert(n) { return Err(NullifierError::AlreadySpent); }
        Ok(())
    }
    pub fn len(&self) -> usize { self.inner.read().unwrap().len() }
    pub fn is_empty(&self) -> bool { self.inner.read().unwrap().is_empty() }
}
impl Default for NullifierSet { fn default() -> Self { Self::new() } }

#[derive(Debug, thiserror::Error)]
pub enum NullifierError { 
    #[error("already spent")] AlreadySpent,
    #[error("invalid nullifier format")] InvalidFormat,
    #[error("nullifier derivation failed")] DerivationFailed,
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test] fn double_spend() {
        let s = NullifierSet::new();
        let n = Nullifier::derive(&[1u8; 32], &[2u8; 32]);
        s.insert(n).unwrap();
        assert!(s.insert(n).is_err());
    }
}
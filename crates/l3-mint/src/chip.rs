use crypto_pqc::{hash_256, Hash256, HybridPublicKey};
use dashmap::DashMap;
use serde::{Deserialize, Serialize};
use crate::MintError;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum ChipStatus { Active, Revoked, Retired }

#[derive(Clone, Serialize, Deserialize)]
pub struct ChipRecord {
    pub chip_id: Hash256,
    pub pubkey: HybridPublicKey,
    pub batch: Hash256,
    pub firmware_hash: Hash256,
    pub attestation: Vec<u8>,
    pub status: ChipStatus,
    pub bound_token: Option<u64>,
    pub registered_at_ms: u64,
}

impl ChipRecord {
    pub fn compute_id(pk: &HybridPublicKey, batch: &Hash256) -> Hash256 {
        let mut b = Vec::new();
        b.extend_from_slice(&pk.ed); b.extend_from_slice(&pk.ml); b.extend_from_slice(batch);
        hash_256(b"lxon/chip/id", &b)
    }
}

pub struct ChipRegistry { chips: DashMap<Hash256, ChipRecord> }

impl ChipRegistry {
    pub fn new() -> Self { Self { chips: DashMap::new() } }
    pub fn register(&self, r: ChipRecord) -> Result<(), MintError> {
        if self.chips.contains_key(&r.chip_id) { return Err(MintError::ChipAlreadyBound); }
        if r.status != ChipStatus::Active { return Err(MintError::ChipRevoked); }
        self.chips.insert(r.chip_id, r); Ok(())
    }
    pub fn get(&self, id: &Hash256) -> Option<ChipRecord> { self.chips.get(id).map(|r| r.clone()) }
    pub fn revoke(&self, id: &Hash256) -> Result<(), MintError> {
        let mut r = self.chips.get_mut(id).ok_or(MintError::ChipNotRegistered)?;
        r.status = ChipStatus::Revoked; Ok(())
    }
    pub fn bind_token(&self, id: &Hash256, t: u64) -> Result<(), MintError> {
        let mut r = self.chips.get_mut(id).ok_or(MintError::ChipNotRegistered)?;
        if r.status != ChipStatus::Active { return Err(MintError::ChipRevoked); }
        if r.bound_token.is_some() { return Err(MintError::ChipAlreadyBound); }
        r.bound_token = Some(t); Ok(())
    }
    pub fn root(&self) -> Hash256 {
        let mut leaves: Vec<Hash256> = self.chips.iter().filter(|r| r.status == ChipStatus::Active).map(|r| r.chip_id).collect();
        leaves.sort();
        crypto_pqc::merkle_root(b"lxon/chip/root", &leaves)
    }
}
impl Default for ChipRegistry { fn default() -> Self { Self::new() } }
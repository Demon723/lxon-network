use crypto_pqc::{hash_256, merkle_root, Hash256, HybridSignature};
use serde::{Deserialize, Serialize};
use crate::PaymentIntent;

#[derive(Clone, Serialize, Deserialize)]
pub struct Batch {
    pub index: u64,
    pub intents: Vec<PaymentIntent>,
    pub root: Hash256,
    pub state_root_after: Hash256,
    pub created_at_ms: u64,
    pub sequencer_sig: Option<HybridSignature>,
}

impl Batch {
    pub fn compute_root(intents: &[PaymentIntent]) -> Hash256 {
        let leaves: Vec<Hash256> = intents.iter().map(|i| i.id).collect();
        merkle_root(b"lxon/l2/batch", &leaves)
    }
    pub fn new(index: u64, intents: Vec<PaymentIntent>, state_root_after: Hash256, now_ms: u64) -> Self {
        let root = Self::compute_root(&intents);
        Self { index, intents, root, state_root_after, created_at_ms: now_ms, sequencer_sig: None }
    }
}

#[derive(Clone, Serialize, Deserialize)]
pub struct BatchCommitment {
    pub index: u64,
    pub batch_root: Hash256,
    pub state_root: Hash256,
    pub da_hash: Hash256,
    pub timestamp_ms: u64,
    pub signature: HybridSignature,
}

impl BatchCommitment {
    pub fn from_batch(batch: &Batch, da_blob: &[u8], sig: HybridSignature) -> Self {
        Self {
            index: batch.index, batch_root: batch.root, state_root: batch.state_root_after,
            da_hash: hash_256(b"lxon/l2/da", da_blob), timestamp_ms: batch.created_at_ms, signature: sig,
        }
    }
}
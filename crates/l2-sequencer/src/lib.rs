//! LXON Pay — L2 payment rollup.
pub mod batch;
pub mod mempool;
pub mod sequencer;
pub mod state;

pub use batch::{Batch, BatchCommitment};
pub use mempool::{Mempool, MempoolError};
pub use sequencer::{BatchSink, InMemorySink, Sequencer, SequencerConfig, SequencerError};
pub use state::{L2State, StateError};

use crypto_pqc::{hash_256, Hash256};
use serde::{Deserialize, Serialize};

#[derive(Clone, Serialize, Deserialize)]
pub struct PaymentIntent {
    pub id: Hash256,
    pub from: crypto_pqc::HybridPublicKey,
    pub ciphertext: Vec<u8>,
    pub pqc_signature: crypto_pqc::HybridSignature,
    pub submitted_at_ms: u64,
    pub fee_units: u64,
}

impl PaymentIntent {
    pub fn compute_id(&self) -> Hash256 {
        let mut buf = Vec::new();
        buf.extend_from_slice(&self.from.ed);
        buf.extend_from_slice(&self.ciphertext);
        buf.extend_from_slice(&self.submitted_at_ms.to_le_bytes());
        hash_256(crypto_pqc::domain::TX_SIGN, &buf)
    }
    pub fn verify(&self) -> Result<(), IntentError> {
        let vk = crypto_pqc::HybridVerifier::new(&self.from).map_err(|_| IntentError::BadKey)?;
        vk.verify_tx(&self.ciphertext, &self.pqc_signature).map_err(|_| IntentError::BadSig)?;
        if self.id != self.compute_id() { return Err(IntentError::BadId); }
        Ok(())
    }
}

#[derive(Debug, thiserror::Error)]
pub enum IntentError {
    #[error("bad public key")] BadKey,
    #[error("bad signature")] BadSig,
    #[error("id mismatch")] BadId,
    #[error("invalid timestamp")] InvalidTimestamp,
    #[error("fee too low")] FeeTooLow,
    #[error("invalid ciphertext")] InvalidCiphertext,
}
use serde::{Deserialize, Serialize};
use crate::address::SpendingKey;
use crate::commitment::NoteCommitment;
use crate::note::Note;
use crate::nullifier::Nullifier;

#[derive(Clone, Serialize, Deserialize)]
pub struct ShieldedTx {
    pub anchor: [u8; 32],
    pub nullifiers: Vec<Nullifier>,
    pub commitments: Vec<NoteCommitment>,
    pub encrypted_notes: Vec<Vec<u8>>,
    pub proof: Vec<u8>,
    pub fee: u64,
    pub memo: Option<Vec<u8>>,
}

pub struct ShieldedTxBuilder {
    inputs: Vec<Note>, outputs: Vec<Note>, fee: u64, memo: Option<Vec<u8>>,
}

impl ShieldedTxBuilder {
    pub fn new() -> Self { Self { inputs: Vec::new(), outputs: Vec::new(), fee: 0, memo: None } }
    pub fn add_input(mut self, n: Note) -> Self { self.inputs.push(n); self }
    pub fn add_output(mut self, n: Note) -> Self { self.outputs.push(n); self }
    pub fn fee(mut self, f: u64) -> Self { self.fee = f; self }
    pub fn build(self, sk: &SpendingKey, anchor: [u8; 32], _rng: &mut impl rand_core::CryptoRngCore) -> Result<ShieldedTx, TxError> {
        let ti: u128 = self.inputs.iter().map(|n| n.amount as u128).sum();
        let to: u128 = self.outputs.iter().map(|n| n.amount as u128).sum();
        if ti != to + self.fee as u128 { return Err(TxError::Unbalanced); }
        let nfs = self.inputs.iter().map(|n| n.nullifier(sk)).collect();
        let cs = self.outputs.iter().map(|n| n.commitment()).collect();
        let enc = self.outputs.iter().map(|n| n.to_plaintext().amount.to_le_bytes().to_vec()).collect();
        Ok(ShieldedTx { anchor, nullifiers: nfs, commitments: cs, encrypted_notes: enc, proof: vec![0u8; 192], fee: self.fee, memo: self.memo })
    }
}
impl Default for ShieldedTxBuilder { fn default() -> Self { Self::new() } }

#[derive(Debug, thiserror::Error)]
pub enum TxError {
    #[error("unbalanced")] Unbalanced,
    #[error("note not found")] NoteNotFound,
    #[error("double spend")] DoubleSpend,
    #[error("proof failed")] ProofFailed,
    #[error("invalid anchor")] InvalidAnchor,
    #[error("fee too high")] FeeTooHigh,
    #[error("invalid inputs")] InvalidInputs,
    #[error("invalid outputs")] InvalidOutputs,
    #[error("nullifier already spent")] NullifierAlreadySpent,
}
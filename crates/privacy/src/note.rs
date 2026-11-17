use rand_core::CryptoRngCore;
use serde::{Deserialize, Serialize};
use zeroize::{Zeroize, ZeroizeOnDrop};
use crate::address::ShieldedAddress;
use crate::commitment::{commit_note, NoteCommitment};
use crate::nullifier::Nullifier;

#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct Note {
    pub address: ShieldedAddress,
    pub amount: u64,
    pub asset_id: [u8; 32],
    pub rho: [u8; 32],
    pub rcm: [u8; 32],
}

#[derive(Clone, Serialize, Deserialize)]
pub struct NotePlaintext {
    pub address: ShieldedAddress,
    pub amount: u64,
    pub asset_id: [u8; 32],
    pub rho: [u8; 32],
    pub rcm: [u8; 32],
}

impl Note {
    pub fn new(a: ShieldedAddress, amount: u64, asset_id: [u8; 32], rng: &mut impl CryptoRngCore) -> Self {
        let mut rho = [0u8; 32]; let mut rcm = [0u8; 32];
        rng.fill_bytes(&mut rho); rng.fill_bytes(&mut rcm);
        Self { address: a, amount, asset_id, rho, rcm }
    }
    pub fn commitment(&self) -> NoteCommitment {
        commit_note(&self.address.pk_d, self.amount, &self.asset_id, &self.rho, &self.rcm)
    }
    pub fn nullifier(&self, sk: &crate::address::SpendingKey) -> Nullifier {
        Nullifier::derive(&sk.nullifier_key(), &self.rho)
    }
    pub fn to_plaintext(&self) -> NotePlaintext {
        NotePlaintext { address: self.address.clone(), amount: self.amount, asset_id: self.asset_id, rho: self.rho, rcm: self.rcm }
    }
}
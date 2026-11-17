use serde::{Deserialize, Serialize};
use crate::domain;
pub const COMMITMENT_TREE_DEPTH: usize = 32;

#[derive(Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Debug)]
pub struct NoteCommitment(pub [u8; 32]);

pub fn commit_note(pk_d: &[u8; 32], amount: u64, asset_id: &[u8; 32], rho: &[u8; 32], rcm: &[u8; 32]) -> NoteCommitment {
    let mut h = blake3::Hasher::new();
    h.update(domain::NOTE_COMMIT); h.update(pk_d);
    h.update(&amount.to_le_bytes()); h.update(asset_id); h.update(rho); h.update(rcm);
    NoteCommitment(h.finalize().as_bytes()[..32].try_into().unwrap())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test] fn det() {
        let a = commit_note(&[1u8; 32], 1, &[2u8; 32], &[3u8; 32], &[4u8; 32]);
        let b = commit_note(&[1u8; 32], 1, &[2u8; 32], &[3u8; 32], &[4u8; 32]);
        assert_eq!(a, b);
    }
}
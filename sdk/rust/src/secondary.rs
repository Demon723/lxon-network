//! Secondary PQ signature helpers.

use sha2::{Digest, Sha256};

#[derive(Debug, Clone, Copy)]
pub enum MayoParams {
    Mayo1, Mayo2, Mayo3, Mayo5,
}

impl MayoParams {
    pub fn sig_size(&self) -> usize {
        match self { MayoParams::Mayo1 => 454, MayoParams::Mayo2 => 216, MayoParams::Mayo3 => 681, MayoParams::Mayo5 => 964 }
    }
    pub fn pk_size(&self) -> usize {
        match self { MayoParams::Mayo1 => 1420, MayoParams::Mayo2 => 4368, MayoParams::Mayo3 => 2986, MayoParams::Mayo5 => 5554 }
    }
}

pub fn compute_commitment(message: &[u8], public_key: &[u8], signature: &[u8]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(message);
    hasher.update(public_key);
    hasher.update(signature);
    hasher.finalize().into()
}

//! Hybrid post-quantum cryptography for LXON.
pub mod hash;
pub mod hybrid;
pub mod kem;
pub mod qkd;

pub use hash::{hash_256, hash_512, merkle_root, Hash256, Hash512};
pub use hybrid::{CryptoError, HybridPublicKey, HybridSignature, HybridSigner, HybridVerifier};
pub use kem::{HybridCiphertext, HybridKem, HybridSharedSecret, KemError};
pub use qkd::{QkdChannel, QkdError, QkdKey};

pub mod domain {
    pub const TX_SIGN: &[u8] = b"lxon/v1/tx-sign";
    pub const BLOCK_SIGN: &[u8] = b"lxon/v1/block-sign";
    pub const CHIP_SIGN: &[u8] = b"lxon/v1/chip-sign";
    pub const TRANSFER: &[u8] = b"lxon/v1/transfer";
    pub const QKD_DERIVE: &[u8] = b"lxon/v1/qkd-derive";
    pub const BRIDGE_MSG: &[u8] = b"lxon/v1/bridge-msg";
}
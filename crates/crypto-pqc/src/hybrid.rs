use ed25519_dalek::{Signature as EdSig, Signer as _, SigningKey as EdSk, Verifier as _, VerifyingKey as EdVk};
use ml_dsa::{KeyGen as _, MlDsa65, Signature as MlSig, SigningKey as MlSk, VerifyingKey as MlVk, Signer as _, Verifier as _};
use rand_core::CryptoRngCore;
use serde::{Deserialize, Serialize};
use crate::domain;

pub struct HybridSigner { ed: EdSk, ml: MlSk<MlDsa65> }
pub struct HybridVerifier { ed: EdVk, ml: MlVk<MlDsa65> }

#[derive(Clone, Serialize, Deserialize)]
pub struct HybridPublicKey { pub ed: [u8; 32], pub ml: Vec<u8> }

#[derive(Clone, Serialize, Deserialize)]
pub struct HybridSignature { pub ed: [u8; 64], pub ml: Vec<u8> }

impl HybridSigner {
    pub fn generate(rng: &mut impl CryptoRngCore) -> Self {
        Self { ed: EdSk::generate(rng), ml: MlSk::<MlDsa65>::generate(rng) }
    }
    pub fn public_key(&self) -> HybridPublicKey {
        HybridPublicKey { ed: self.ed.verifying_key().to_bytes(), ml: self.ml.verifying_key().encode().to_vec() }
    }
    pub fn sign(&self, tag: &[u8], msg: &[u8]) -> HybridSignature {
        let mut p = Vec::with_capacity(tag.len() + 1 + msg.len());
        p.extend_from_slice(tag); p.push(0); p.extend_from_slice(msg);
        HybridSignature { ed: self.ed.sign(&p).to_bytes(), ml: self.ml.sign(&p).encode().to_vec() }
    }
    pub fn sign_tx(&self, m: &[u8]) -> HybridSignature { self.sign(domain::TX_SIGN, m) }
    pub fn sign_block(&self, m: &[u8]) -> HybridSignature { self.sign(domain::BLOCK_SIGN, m) }
    pub fn sign_chip(&self, m: &[u8]) -> HybridSignature { self.sign(domain::CHIP_SIGN, m) }
}

impl HybridVerifier {
    pub fn new(pk: &HybridPublicKey) -> Result<Self, CryptoError> {
        let ed = EdVk::from_bytes(&pk.ed).map_err(|_| CryptoError::BadEdKey)?;
        let ml = MlVk::<MlDsa65>::decode(pk.ml.as_slice().into()).ok_or(CryptoError::BadMlKey)?;
        Ok(Self { ed, ml })
    }
    pub fn verify(&self, tag: &[u8], msg: &[u8], sig: &HybridSignature) -> Result<(), CryptoError> {
        let mut p = Vec::with_capacity(tag.len() + 1 + msg.len());
        p.extend_from_slice(tag); p.push(0); p.extend_from_slice(msg);
        let ed_sig = EdSig::from_bytes(&sig.ed).map_err(|_| CryptoError::BadEdSig)?;
        self.ed.verify(&p, &ed_sig).map_err(|_| CryptoError::EdVerifyFail)?;
        let ml_sig = MlSig::<MlDsa65>::decode(sig.ml.as_slice().into()).ok_or(CryptoError::BadMlSig)?;
        self.ml.verify(&p, &ml_sig).map_err(|_| CryptoError::MlVerifyFail)?;
        Ok(())
    }
    pub fn verify_tx(&self, m: &[u8], s: &HybridSignature) -> Result<(), CryptoError> { self.verify(domain::TX_SIGN, m, s) }
}

#[derive(Debug, thiserror::Error)]
pub enum CryptoError {
    #[error("invalid ed25519 public key")] BadEdKey,
    #[error("invalid ml-dsa public key")] BadMlKey,
    #[error("invalid ed25519 signature")] BadEdSig,
    #[error("invalid ml-dsa signature")] BadMlSig,
    #[error("ed25519 verification failed")] EdVerifyFail,
    #[error("ml-dsa verification failed")] MlVerifyFail,
    #[error("invalid key size: expected {expected}, got {got}")] InvalidKeySize { expected: usize, got: usize },
    #[error("invalid signature size: expected {expected}, got {got}")] InvalidSignatureSize { expected: usize, got: usize },
    #[error("invalid domain separator")] InvalidDomain,
    #[error("key generation failed")] KeyGenerationFailed,
}

#[cfg(test)]
mod tests {
    use super::*;
    use rand::rngs::OsRng;
    #[test] fn roundtrip() {
        let mut rng = OsRng;
        let sk = HybridSigner::generate(&mut rng);
        let vk = HybridVerifier::new(&sk.public_key()).unwrap();
        let sig = sk.sign_tx(b"hello");
        vk.verify_tx(b"hello", &sig).unwrap();
    }
    #[test] fn tampered_fails() {
        let mut rng = OsRng;
        let sk = HybridSigner::generate(&mut rng);
        let vk = HybridVerifier::new(&sk.public_key()).unwrap();
        let sig = sk.sign_tx(b"original");
        assert!(vk.verify_tx(b"tampered", &sig).is_err());
    }
    #[test] fn signature_serialization() {
        let mut rng = OsRng;
        let sk = HybridSigner::generate(&mut rng);
        let sig = sk.sign_tx(b"test");
        let serialized = bincode::serialize(&sig).unwrap();
        let deserialized: HybridSignature = bincode::deserialize(&serialized).unwrap();
        assert_eq!(sig.ed, deserialized.ed);
        assert_eq!(sig.ml, deserialized.ml);
    }
    #[test] fn wrong_domain_fails() {
        let mut rng = OsRng;
        let sk = HybridSigner::generate(&mut rng);
        let vk = HybridVerifier::new(&sk.public_key()).unwrap();
        let sig = sk.sign_block(b"x");
        assert!(vk.verify_tx(b"x", &sig).is_err());
    }
    #[test] fn invalid_key_size_fails() {
        let bad_key = HybridPublicKey { ed: [0u8; 16], ml: vec![0u8; 16] };
        assert!(HybridVerifier::new(&bad_key).is_err());
    }
}
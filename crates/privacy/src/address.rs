use curve25519_dalek::{constants::ED25519_BASEPOINT_POINT, scalar::Scalar};
use rand_core::CryptoRngCore;
use serde::{Deserialize, Serialize};
use zeroize::{Zeroize, ZeroizeOnDrop};
use crate::domain;

#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct SpendingKey(pub(crate) [u8; 32]);

impl SpendingKey {
    pub fn generate(rng: &mut impl CryptoRngCore) -> Self {
        let mut sk = [0u8; 32]; rng.fill_bytes(&mut sk);
        sk[0] &= 248; sk[31] &= 127; sk[31] |= 64;
        Self(sk)
    }
    pub fn to_scalar(&self) -> Scalar { Scalar::from_bytes_mod_order(self.0) }
    pub fn viewing_key(&self) -> ViewingKey {
        let mut h = blake3::Hasher::new();
        h.update(domain::VIEWING_TAG); h.update(&self.0);
        ViewingKey(h.finalize().as_bytes()[..32].try_into().unwrap())
    }
    pub fn nullifier_key(&self) -> [u8; 32] {
        let mut h = blake3::Hasher::new();
        h.update(b"lxon/privacy/v1/nf-key"); h.update(&self.0);
        h.finalize().as_bytes()[..32].try_into().unwrap()
    }
}

#[derive(Clone, Serialize, Deserialize)]
pub struct SpendingPublicKey(pub [u8; 32]);

#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct ViewingKey(pub(crate) [u8; 32]);

#[derive(Clone, Serialize, Deserialize)]
pub struct ShieldedAddress { pub pk_d: [u8; 32], pub pk_enc: [u8; 32] }

impl ShieldedAddress {
    pub fn derive(sk: &SpendingKey, d: u32) -> Self {
        let mut h = blake3::Hasher::new();
        h.update(domain::ADDRESS); h.update(&sk.0); h.update(&d.to_le_bytes());
        let dd = h.finalize();
        let d_scalar = Scalar::from_bytes_mod_order(dd.as_bytes()[..32].try_into().unwrap());
        let pk_d = (d_scalar * ED25519_BASEPOINT_POINT).compress().to_bytes();
        let mut h2 = blake3::Hasher::new();
        h2.update(b"lxon/privacy/v1/enc"); h2.update(&sk.0); h2.update(&d.to_le_bytes());
        let pk_enc: [u8; 32] = h2.finalize().as_bytes()[..32].try_into().unwrap();
        Self { pk_d, pk_enc }
    }
    pub fn encode(&self) -> String { format!("lxon1{}", hex::encode([self.pk_d, self.pk_enc].concat())) }
    pub fn decode(s: &str) -> Result<Self, AddressError> {
        let h = s.strip_prefix("lxon1").ok_or(AddressError::BadPrefix)?;
        let b = hex::decode(h).map_err(|_| AddressError::BadHex)?;
        if b.len() != 64 { return Err(AddressError::BadLength); }
        let mut pk_d = [0u8; 32]; let mut pk_enc = [0u8; 32];
        pk_d.copy_from_slice(&b[..32]); pk_enc.copy_from_slice(&b[32..]);
        Ok(Self { pk_d, pk_enc })
    }
}

#[derive(Debug, thiserror::Error)]
pub enum AddressError {
    #[error("must start with lxon1")] BadPrefix,
    #[error("bad hex")] BadHex,
    #[error("wrong length")] BadLength,
}

#[cfg(test)]
mod tests {
    use super::*;
    use rand::rngs::OsRng;
    #[test] fn roundtrip() {
        let sk = SpendingKey::generate(&mut OsRng);
        let a = ShieldedAddress::derive(&sk, 0);
        assert_eq!(ShieldedAddress::decode(&a.encode()).unwrap().pk_d, a.pk_d);
    }
    #[test] fn unlinkable() {
        let sk = SpendingKey::generate(&mut OsRng);
        assert_ne!(ShieldedAddress::derive(&sk, 0).pk_d, ShieldedAddress::derive(&sk, 1).pk_d);
    }
}
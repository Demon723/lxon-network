use ml_kem::{MlKem768, KemCore, Encapsulate, Decapsulate, EncodedSizeUser};
use x25519_dalek::{PublicKey as XPublic, StaticSecret as XSecret, SharedSecret as XShared};
use rand_core::CryptoRngCore;
use serde::{Deserialize, Serialize};

pub struct HybridKem { x_sk: XSecret, ml_sk: <MlKem768 as KemCore>::DecapsulationKey }

#[derive(Clone, Serialize, Deserialize)]
pub struct HybridKemPublic { pub x: [u8; 32], pub ml: Vec<u8> }

#[derive(Clone, Serialize, Deserialize)]
pub struct HybridCiphertext { pub x_eph: [u8; 32], pub ml: Vec<u8> }

#[derive(Clone)]
pub struct HybridSharedSecret(pub [u8; 32]);

impl HybridKem {
    pub fn generate(rng: &mut impl CryptoRngCore) -> Self {
        let x_sk = XSecret::random_from_rng(rng);
        let (ml_dk, _) = MlKem768::generate(rng);
        Self { x_sk, ml_sk: ml_dk }
    }
    pub fn public_key(&self) -> HybridKemPublic {
        HybridKemPublic { x: XPublic::from(&self.x_sk).to_bytes(), ml: self.ml_sk.as_bytes().to_vec() }
    }
    pub fn decapsulate(&self, ct: &HybridCiphertext) -> Result<HybridSharedSecret, KemError> {
        let peer = XPublic::from(ct.x_eph);
        let x_ss = self.x_sk.diffie_hellman(&peer);
        let ml_ct = ml_kem::Ciphertext::<MlKem768>::try_from(ct.ml.as_slice()).map_err(|_| KemError::BadMlCt)?;
        let ml_ss = self.ml_sk.decapsulate(&ml_ct).map_err(|_| KemError::DecapFail)?;
        Ok(HybridSharedSecret(combine(x_ss.as_bytes(), ml_ss.as_slice())))
    }
}

impl HybridKemPublic {
    pub fn encapsulate(&self, rng: &mut impl CryptoRngCore) -> Result<(HybridCiphertext, HybridSharedSecret), KemError> {
        let x_eph = XSecret::random_from_rng(rng);
        let x_eph_pub = XPublic::from(&x_eph).to_bytes();
        let peer_x = XPublic::from(self.x);
        let x_ss: XShared = x_eph.diffie_hellman(&peer_x);
        let ml_ek = ml_kem::Encoded::<ml_kem::kem::EncapsulationKey<MlKem768>>::try_from(self.ml.as_slice()).map_err(|_| KemError::BadMlKey)?;
        let ek = ml_kem::kem::EncapsulationKey::<MlKem768>::from_bytes(&ml_ek);
        let (ml_ct, ml_ss) = ek.encapsulate(rng).map_err(|_| KemError::EncapFail)?;
        Ok((HybridCiphertext { x_eph: x_eph_pub, ml: ml_ct.as_slice().to_vec() },
            HybridSharedSecret(combine(x_ss.as_bytes(), ml_ss.as_slice()))))
    }
}

fn combine(a: &[u8; 32], b: &[u8]) -> [u8; 32] {
    use sha3::{Digest, Sha3_256};
    let mut h = Sha3_256::new(); h.update(a); h.update(b); h.finalize().into()
}

#[derive(Debug, thiserror::Error)]
pub enum KemError {
    #[error("bad ml-kem public key")] BadMlKey,
    #[error("encapsulation failed")] EncapFail,
    #[error("bad ml-kem ciphertext")] BadMlCt,
    #[error("decapsulation failed")] DecapFail,
    #[error("invalid shared secret size")] InvalidSharedSecret,
    #[error("key exchange failed")] KeyExchangeFailed,
    #[error("invalid ephemeral key")] InvalidEphemeralKey,
}

#[cfg(test)]
mod tests {
    use super::*;
    use rand::rngs::OsRng;
    #[test] fn roundtrip() {
        let mut rng = OsRng;
        let a = HybridKem::generate(&mut rng);
        let pk = a.public_key();
        let (ct, ss1) = pk.encapsulate(&mut rng).unwrap();
        let ss2 = a.decapsulate(&ct).unwrap();
        assert_eq!(ss1.0, ss2.0);
    }
}
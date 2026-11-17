//! MAYO signature verification and key generation using pq-mayo

use crate::{MayoError, MayoResult, MayoScheme};
use pq_mayo::{KeyPair, Mayo1, Mayo2, Mayo3, Mayo5, Signature, SigningKey, VerifyingKey};
use signature::{Signer, Verifier};

/// MAYO key pair wrapper
#[derive(Debug, Clone)]
pub struct MayoKeyPair {
    pub scheme: MayoScheme,
    pub public_key: Vec<u8>,
    pub secret_key: Vec<u8>,
}

impl MayoKeyPair {
    /// Generate a new MAYO key pair
    ///
    /// # Errors
    ///
    /// Returns an error if the cryptographic operation fails
    pub fn generate(scheme: MayoScheme) -> MayoResult<Self> {
        let mut rng = rand::rng();
        
        let (public_key, secret_key) = match scheme {
            MayoScheme::Mayo1 => {
                let keypair: KeyPair<Mayo1> = KeyPair::generate(&mut rng)
                    .map_err(|e| MayoError::CryptoError(format!("Key generation failed: {}", e)))?;
                (keypair.verifying_key().as_ref().to_vec(), 
                 keypair.signing_key().as_ref().to_vec())
            }
            MayoScheme::Mayo2 => {
                let keypair: KeyPair<Mayo2> = KeyPair::generate(&mut rng)
                    .map_err(|e| MayoError::CryptoError(format!("Key generation failed: {}", e)))?;
                (keypair.verifying_key().as_ref().to_vec(),
                 keypair.signing_key().as_ref().to_vec())
            }
            MayoScheme::Mayo3 => {
                let keypair: KeyPair<Mayo3> = KeyPair::generate(&mut rng)
                    .map_err(|e| MayoError::CryptoError(format!("Key generation failed: {}", e)))?;
                (keypair.verifying_key().as_ref().to_vec(),
                 keypair.signing_key().as_ref().to_vec())
            }
            MayoScheme::Mayo5 => {
                let keypair: KeyPair<Mayo5> = KeyPair::generate(&mut rng)
                    .map_err(|e| MayoError::CryptoError(format!("Key generation failed: {}", e)))?;
                (keypair.verifying_key().as_ref().to_vec(),
                 keypair.signing_key().as_ref().to_vec())
            }
        };

        Ok(MayoKeyPair {
            scheme,
            public_key,
            secret_key,
        })
    }

    /// Sign a message with the secret key
    ///
    /// # Errors
    ///
    /// Returns an error if the signing operation fails
    pub fn sign(&self, message: &[u8]) -> MayoResult<Vec<u8>> {
        match self.scheme {
            MayoScheme::Mayo1 => {
                let signing_key = SigningKey::<Mayo1>::try_from(self.secret_key.as_slice())
                    .map_err(|e| MayoError::InvalidKeySize(format!("Invalid signing key: {}", e)))?;
                let signature = signing_key.sign(message);
                Ok(signature.as_ref().to_vec())
            }
            MayoScheme::Mayo2 => {
                let signing_key = SigningKey::<Mayo2>::try_from(self.secret_key.as_slice())
                    .map_err(|e| MayoError::InvalidKeySize(format!("Invalid signing key: {}", e)))?;
                let signature = signing_key.sign(message);
                Ok(signature.as_ref().to_vec())
            }
            MayoScheme::Mayo3 => {
                let signing_key = SigningKey::<Mayo3>::try_from(self.secret_key.as_slice())
                    .map_err(|e| MayoError::InvalidKeySize(format!("Invalid signing key: {}", e)))?;
                let signature = signing_key.sign(message);
                Ok(signature.as_ref().to_vec())
            }
            MayoScheme::Mayo5 => {
                let signing_key = SigningKey::<Mayo5>::try_from(self.secret_key.as_slice())
                    .map_err(|e| MayoError::InvalidKeySize(format!("Invalid signing key: {}", e)))?;
                let signature = signing_key.sign(message);
                Ok(signature.as_ref().to_vec())
            }
        }
    }
}

/// MAYO signature verifier
pub struct MayoVerifier {
    scheme: MayoScheme,
}

impl MayoVerifier {
    /// Create a new verifier for the specified scheme
    pub fn new(scheme: MayoScheme) -> Self {
        Self { scheme }
    }

    /// Verify a MAYO signature
    ///
    /// # Errors
    ///
    /// Returns an error if verification fails or the operation is not implemented
    pub fn verify(
        &self,
        public_key: &[u8],
        message: &[u8],
        signature: &[u8],
    ) -> MayoResult<bool> {
        match self.scheme {
            MayoScheme::Mayo1 => {
                let verifying_key = VerifyingKey::<Mayo1>::try_from(public_key)
                    .map_err(|e| MayoError::InvalidKeySize(format!("Invalid verifying key: {}", e)))?;
                let sig = Signature::<Mayo1>::try_from(signature)
                    .map_err(|e| MayoError::InvalidSignatureSize(format!("Invalid signature: {}", e)))?;
                verifying_key.verify(message, &sig)
                    .map_err(|e| MayoError::CryptoError(format!("Verification failed: {}", e)))?;
                Ok(true)
            }
            MayoScheme::Mayo2 => {
                let verifying_key = VerifyingKey::<Mayo2>::try_from(public_key)
                    .map_err(|e| MayoError::InvalidKeySize(format!("Invalid verifying key: {}", e)))?;
                let sig = Signature::<Mayo2>::try_from(signature)
                    .map_err(|e| MayoError::InvalidSignatureSize(format!("Invalid signature: {}", e)))?;
                verifying_key.verify(message, &sig)
                    .map_err(|e| MayoError::CryptoError(format!("Verification failed: {}", e)))?;
                Ok(true)
            }
            MayoScheme::Mayo3 => {
                let verifying_key = VerifyingKey::<Mayo3>::try_from(public_key)
                    .map_err(|e| MayoError::InvalidKeySize(format!("Invalid verifying key: {}", e)))?;
                let sig = Signature::<Mayo3>::try_from(signature)
                    .map_err(|e| MayoError::InvalidSignatureSize(format!("Invalid signature: {}", e)))?;
                verifying_key.verify(message, &sig)
                    .map_err(|e| MayoError::CryptoError(format!("Verification failed: {}", e)))?;
                Ok(true)
            }
            MayoScheme::Mayo5 => {
                let verifying_key = VerifyingKey::<Mayo5>::try_from(public_key)
                    .map_err(|e| MayoError::InvalidKeySize(format!("Invalid verifying key: {}", e)))?;
                let sig = Signature::<Mayo5>::try_from(signature)
                    .map_err(|e| MayoError::InvalidSignatureSize(format!("Invalid signature: {}", e)))?;
                verifying_key.verify(message, &sig)
                    .map_err(|e| MayoError::CryptoError(format!("Verification failed: {}", e)))?;
                Ok(true)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_real_keypair_generation() {
        let keypair = MayoKeyPair::generate(MayoScheme::Mayo1).unwrap();
        assert_eq!(keypair.scheme, MayoScheme::Mayo1);
        assert!(!keypair.public_key.is_empty());
        assert!(!keypair.secret_key.is_empty());
    }

    #[test]
    fn test_real_signing() {
        let keypair = MayoKeyPair::generate(MayoScheme::Mayo1).unwrap();
        let message = b"test message";
        let signature = keypair.sign(message).unwrap();
        assert!(!signature.is_empty());
    }

    #[test]
    fn test_real_verification() {
        let keypair = MayoKeyPair::generate(MayoScheme::Mayo1).unwrap();
        let message = b"test message";
        let signature = keypair.sign(message).unwrap();
        
        let verifier = MayoVerifier::new(MayoScheme::Mayo1);
        let verified = verifier.verify(&keypair.public_key, message, &signature).unwrap();
        assert!(verified);
    }

    #[test]
    fn test_invalid_signature() {
        let keypair = MayoKeyPair::generate(MayoScheme::Mayo1).unwrap();
        let message = b"test message";
        let verifier = MayoVerifier::new(MayoScheme::Mayo1);
        
        // Try to verify with wrong signature
        let invalid_signature = vec![0u8; 454];
        let result = verifier.verify(&keypair.public_key, message, &invalid_signature);
        assert!(result.is_err());
    }

    #[test]
    fn test_all_schemes() {
        for scheme in [MayoScheme::Mayo1, MayoScheme::Mayo2, MayoScheme::Mayo3, MayoScheme::Mayo5] {
            let keypair = MayoKeyPair::generate(scheme).unwrap();
            let message = b"test message";
            let signature = keypair.sign(message).unwrap();
            
            let verifier = MayoVerifier::new(scheme);
            let verified = verifier.verify(&keypair.public_key, message, &signature).unwrap();
            assert!(verified, "Verification failed for scheme {:?}", scheme);
        }
    }
}
//! MAYO Post-Quantum Cryptography Bindings
//!
//! This crate provides Rust bindings for MAYO multivariate cryptography,
//! which serves as the secondary signature scheme in LXON's defense-in-depth
//! post-quantum security architecture.
//!
//! # Implementation
//!
//! Uses the `pq-mayo` crate for actual MAYO cryptographic operations.
//! The pq-mayo crate implements the MAYO signature scheme submitted to the
//! NIST PQC standardization process.
//!
//! # Usage
//!
//! ```rust,no_run
//! use lxon_mayo_binding::{MayoVerifier, MayoKeyPair, MayoScheme};
//!
//! // Key generation
//! let keypair = MayoKeyPair::generate(MayoScheme::Mayo1)?;
//!
//! // Signing
//! let signature = keypair.sign(message)?;
//!
//! // Verification
//! let verified = MayoVerifier::verify(&keypair.public_key, message, &signature)?;
//! ```

pub mod error;
pub mod scheme;
pub mod verifier;

pub use error::{MayoError, MayoResult};
pub use scheme::MayoParams;
pub use verifier::{MayoVerifier, MayoKeyPair};

/// Re-export pq-mayo types for direct access
pub use pq_mayo::{Mayo1, Mayo2, Mayo3, Mayo5};

/// MAYO scheme parameters
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MayoScheme {
    /// MAYO-1: 454 B signature, 1420 B public key
    Mayo1,
    /// MAYO-2: 216 B signature, 4368 B public key
    Mayo2,
    /// MAYO-3: 681 B signature, 2986 B public key
    Mayo3,
    /// MAYO-5: 964 B signature, 5554 B public key
    Mayo5,
}

impl MayoScheme {
    /// Get signature size in bytes
    pub fn signature_size(&self) -> usize {
        match self {
            MayoScheme::Mayo1 => 454,
            MayoScheme::Mayo2 => 216,
            MayoScheme::Mayo3 => 681,
            MayoScheme::Mayo5 => 964,
        }
    }

    /// Get public key size in bytes
    pub fn public_key_size(&self) -> usize {
        match self {
            MayoScheme::Mayo1 => 1420,
            MayoScheme::Mayo2 => 4368,
            MayoScheme::Mayo3 => 2986,
            MayoScheme::Mayo5 => 5554,
        }
    }

    /// Get secret key size in bytes
    pub fn secret_key_size(&self) -> usize {
        match self {
            MayoScheme::Mayo1 => 24,
            MayoScheme::Mayo2 => 24,
            MayoScheme::Mayo3 => 32,
            MayoScheme::Mayo5 => 40,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_scheme_sizes() {
        assert_eq!(MayoScheme::Mayo1.signature_size(), 454);
        assert_eq!(MayoScheme::Mayo1.public_key_size(), 1420);
        assert_eq!(MayoScheme::Mayo2.signature_size(), 216);
        assert_eq!(MayoScheme::Mayo2.public_key_size(), 4368);
    }

    #[test]
    fn test_verifier_creation() {
        let verifier = MayoVerifier::new(MayoScheme::Mayo1);
        // Can't access private field, just test creation works
        let _ = verifier;
    }
}
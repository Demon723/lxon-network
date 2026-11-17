//! Error types for MAYO cryptographic operations

use std::fmt;

/// MAYO-specific error types
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MayoError {
    /// Invalid key size
    InvalidKeySize(String),
    /// Invalid signature size
    InvalidSignatureSize(String),
    /// Cryptographic operation failed
    CryptoError(String),
    /// Invalid input parameters
    InvalidInput(String),
}

impl fmt::Display for MayoError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            MayoError::InvalidKeySize(msg) => write!(f, "Invalid key size: {}", msg),
            MayoError::InvalidSignatureSize(msg) => write!(f, "Invalid signature size: {}", msg),
            MayoError::CryptoError(msg) => write!(f, "Cryptographic error: {}", msg),
            MayoError::InvalidInput(msg) => write!(f, "Invalid input: {}", msg),
        }
    }
}

impl std::error::Error for MayoError {}

/// Result type for MAYO operations
pub type MayoResult<T> = Result<T, MayoError>;
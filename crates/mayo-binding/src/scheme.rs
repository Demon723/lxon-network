//! MAYO scheme parameters and configuration

use crate::MayoScheme;

/// Detailed parameters for MAYO schemes
#[derive(Debug, Clone, Copy)]
pub struct MayoParams {
    pub scheme: MayoScheme,
    pub n: usize,  // Number of variables
    pub m: usize,  // Number of equations
    pub q: usize,  // Field size
}

impl MayoParams {
    /// Get parameters for a specific MAYO scheme
    pub fn for_scheme(scheme: MayoScheme) -> Self {
        // Parameters from pq-mayo specification
        match scheme {
            MayoScheme::Mayo1 => MayoParams {
                scheme,
                n: 64,
                m: 48,
                q: 16,
            },
            MayoScheme::Mayo2 => MayoParams {
                scheme,
                n: 96,
                m: 64,
                q: 16,
            },
            MayoScheme::Mayo3 => MayoParams {
                scheme,
                n: 128,
                m: 96,
                q: 16,
            },
            MayoScheme::Mayo5 => MayoParams {
                scheme,
                n: 160,
                m: 128,
                q: 16,
            },
        }
    }

    /// Calculate expected signature size
    pub fn signature_size(&self) -> usize {
        self.scheme.signature_size()
    }

    /// Calculate expected public key size
    pub fn public_key_size(&self) -> usize {
        self.scheme.public_key_size()
    }

    /// Calculate expected secret key size
    pub fn secret_key_size(&self) -> usize {
        match self.scheme {
            MayoScheme::Mayo1 => 24,
            MayoScheme::Mayo2 => 24,
            MayoScheme::Mayo3 => 32,
            MayoScheme::Mayo5 => 40,
        }
    }
}
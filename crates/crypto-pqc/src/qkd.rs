//! Simulated Quantum Key Distribution channel.
use crate::hash::hash_256;
use rand::RngCore;
use rand_core::CryptoRngCore;
use serde::{Deserialize, Serialize};

pub const DEFAULT_QBER_THRESHOLD: f64 = 0.11;

#[derive(Clone, Serialize, Deserialize)]
pub struct QkdKey { pub key_id: [u8; 16], pub material: [u8; 32], pub qber: f64, pub generated_at_ms: u64 }

#[derive(Debug, thiserror::Error)]
pub enum QkdError {
    #[error("QBER {0} exceeds threshold {1}")] QberTooHigh(f64, f64),
    #[error("channel down")] ChannelDown,
    #[error("key rate too low")] KeyRateTooLow,
    #[error("invalid key material")] InvalidKeyMaterial,
    #[error("synchronization failed")] SynchronizationFailed,
    #[error("timeout while waiting for key")] Timeout,
}

pub struct QkdChannel { pub rate_bps: u64, pub base_qber: f64, pub distance_km: f64, pub online: bool }

impl QkdChannel {
    pub fn leo_downlink() -> Self { Self { rate_bps: 10_000, base_qber: 0.03, distance_km: 600.0, online: true } }
    pub fn generate_key(&self, rng: &mut impl CryptoRngCore, now_ms: u64) -> Result<QkdKey, QkdError> {
        if !self.online { return Err(QkdError::ChannelDown); }
        if self.rate_bps < 100 { return Err(QkdError::KeyRateTooLow); }
        let qber = (self.base_qber + (self.distance_km / 1000.0) * 0.01 + rng.gen::<f64>() * 0.01).clamp(0.0, 0.5);
        if qber > DEFAULT_QBER_THRESHOLD { return Err(QkdError::QberTooHigh(qber, DEFAULT_QBER_THRESHOLD)); }
        let mut key_id = [0u8; 16]; rng.fill_bytes(&mut key_id);
        let mut raw = [0u8; 64]; rng.fill_bytes(&mut raw);
        Ok(QkdKey { key_id, material: hash_256(b"lxon/qkd/v1", &raw), qber, generated_at_ms: now_ms })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rand::rngs::OsRng;
    #[test] fn leo_ok() {
        let ch = QkdChannel::leo_downlink();
        let k = ch.generate_key(&mut OsRng, 1_700_000_000_000).unwrap();
        assert!(k.qber < DEFAULT_QBER_THRESHOLD);
    }
}
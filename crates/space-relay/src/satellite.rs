use crypto_pqc::{hash_256, Hash256};
use serde::{Deserialize, Serialize};
pub type SatelliteId = Hash256;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum LinkKind { Optical, Radio, Qkd, Terrestrial }

#[derive(Clone, Serialize, Deserialize)]
pub struct Satellite {
    pub id: SatelliteId, pub name: String,
    pub altitude_km: f64, pub inclination_deg: f64, pub raan_deg: f64, pub mean_anomaly_deg: f64,
    pub optical_bps: u64, pub radio_bps: u64, pub qkd_bps: u64, pub radiation_seu_per_day: f64,
}

impl Satellite {
    pub fn new(name: &str, alt: f64, inc: f64, raan: f64) -> Self {
        Self {
            id: hash_256(b"lxon/sat/id", name.as_bytes()),
            name: name.into(), altitude_km: alt, inclination_deg: inc, raan_deg: raan, mean_anomaly_deg: 0.0,
            optical_bps: 1_000_000_000, radio_bps: 50_000_000, qkd_bps: 10_000, radiation_seu_per_day: 0.1,
        }
    }
    pub fn link_rate(&self, k: LinkKind) -> u64 {
        match k {
            LinkKind::Optical => self.optical_bps,
            LinkKind::Radio => self.radio_bps,
            LinkKind::Qkd => self.qkd_bps,
            LinkKind::Terrestrial => 10_000_000_000,
        }
    }
}
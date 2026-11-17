//! Shared types for the LXON Rust SDK.

use serde::{Deserialize, Serialize};

/// A 0x-prefixed hex address.
pub type Address = String;

/// A wrapped post-quantum asset (qBTC, qETH, qUSDC, ...).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WrappedAsset {
    pub name: String,
    pub symbol: String,
    pub address: Address,
    pub underlying: Address,
    #[serde(rename = "assetClass")]
    pub asset_class: String,
    #[serde(rename = "totalMinted")]
    pub total_minted: u64,
    #[serde(rename = "totalRedeemed")]
    pub total_redeemed: u64,
}

/// A custodian attestation for a deposit.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Attestation {
    pub ref_: String,
    pub to: Address,
    pub amount: u64,
    #[serde(rename = "assetId")]
    pub asset_id: String,
    pub custodian: String,
    #[serde(rename = "submittedAt")]
    pub submitted_at: u64,
}

/// A satellite bandwidth session.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    pub id: String,
    pub client: Address,
    #[serde(rename = "satelliteId")]
    pub satellite_id: String,
    #[serde(rename = "stationId")]
    pub station_id: String,
    #[serde(rename = "bytesUsed")]
    pub bytes_used: u64,
    #[serde(rename = "openedAtMs")]
    pub opened_at_ms: u64,
}

/// A satellite pass (window for uplink/downlink).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Pass {
    #[serde(rename = "satelliteId")]
    pub satellite_id: String,
    #[serde(rename = "startMs")]
    pub start_ms: u64,
    #[serde(rename = "endMs")]
    pub end_ms: u64,
    #[serde(rename = "maxElevationDeg")]
    pub max_elevation_deg: f64,
}
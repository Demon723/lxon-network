use crypto_pqc::Hash256;
use serde::{Deserialize, Serialize};
use crate::MintError;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum TokenState { Minted, Active, Frozen, Redeemed, Destroyed }

#[derive(Clone, Serialize, Deserialize)]
pub struct PhysicalNft {
    pub token_id: u64,
    pub chip_id: Hash256,
    pub holder: Hash256,
    pub state: TokenState,
    pub bound_at_ms: u64,
    pub last_tap_ms: u64,
    pub possession_window_ms: u64,
    pub metadata_hash: Hash256,
}

impl PhysicalNft {
    pub fn new(t: u64, c: Hash256, h: Hash256, m: Hash256, now: u64) -> Self {
        Self {
            token_id: t, chip_id: c, holder: h, state: TokenState::Minted,
            bound_at_ms: now, last_tap_ms: now,
            possession_window_ms: 30 * 24 * 3600 * 1000,
            metadata_hash: m,
        }
    }
    pub fn activate(&mut self) -> Result<(), MintError> {
        if self.state != TokenState::Minted { return Err(MintError::InvalidTransition(format!("{:?}→Active", self.state))); }
        self.state = TokenState::Active; Ok(())
    }
    pub fn freeze(&mut self) -> Result<(), MintError> {
        match self.state {
            TokenState::Active => { self.state = TokenState::Frozen; Ok(()) }
            _ => Err(MintError::InvalidTransition(format!("{:?}→Frozen", self.state))),
        }
    }
    pub fn record_tap(&mut self, now: u64) { self.last_tap_ms = now; }
    pub fn possession_valid(&self, now: u64) -> bool { now.saturating_sub(self.last_tap_ms) <= self.possession_window_ms }
    pub fn check_possession(&self, now: u64) -> Result<(), MintError> {
        if !self.possession_valid(now) {
            return Err(MintError::PossessionWindowExpired);
        }
        Ok(())
    }
}
use crypto_pqc::Hash256;
use serde::{Deserialize, Serialize};
use crate::token::{PhysicalNft, TokenState};
use crate::MintError;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum RedemptionDirection { DigitalToPhysical, PhysicalToDigital }

#[derive(Clone, Serialize, Deserialize)]
pub struct RedemptionRequest {
    pub token_id: u64,
    pub direction: RedemptionDirection,
    pub holder: Hash256,
    pub vault_id: Hash256,
    pub shipping_hash: Hash256,
    pub requested_at_ms: u64,
}

pub struct RedemptionEngine;

impl RedemptionEngine {
    pub fn initiate(nft: &mut PhysicalNft, req: RedemptionRequest) -> Result<(), MintError> {
        if nft.state != TokenState::Active && nft.state != TokenState::Frozen {
            return Err(MintError::InvalidTransition(format!("{:?}", nft.state)));
        }
        if nft.token_id != req.token_id { return Err(MintError::TokenNotFound); }
        if nft.holder != req.holder { return Err(MintError::InvalidTransition("not holder".into())); }
        nft.state = TokenState::Redeemed; Ok(())
    }
    pub fn finalize(nft: &mut PhysicalNft) -> Result<(), MintError> {
        if nft.state != TokenState::Redeemed { return Err(MintError::InvalidTransition("not redeemed".into())); }
        nft.state = TokenState::Destroyed; Ok(())
    }
}
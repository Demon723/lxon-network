use crypto_pqc::{domain, Hash256, HybridSignature, HybridVerifier};
use serde::{Deserialize, Serialize};
use crate::chip::ChipRegistry;
use crate::token::{PhysicalNft, TokenState};
use crate::MintError;

#[derive(Clone, Serialize, Deserialize)]
pub struct ChipTransferConsent {
    pub chip_id: Hash256,
    pub token_id: u64,
    pub new_holder: Hash256,
    pub nonce: u64,
    pub timestamp_ms: u64,
    pub signature: HybridSignature,
}

impl ChipTransferConsent {
    pub fn message_bytes(&self) -> Vec<u8> {
        let mut b = Vec::new();
        b.extend_from_slice(&self.chip_id);
        b.extend_from_slice(&self.token_id.to_le_bytes());
        b.extend_from_slice(&self.new_holder);
        b.extend_from_slice(&self.nonce.to_le_bytes());
        b.extend_from_slice(&self.timestamp_ms.to_le_bytes());
        b
    }
}

pub struct TransferProtocol;

impl TransferProtocol {
    pub fn physical_transfer(
        registry: &ChipRegistry,
        nft: &mut PhysicalNft,
        consent: ChipTransferConsent,
        now: u64,
    ) -> Result<(), MintError> {
        if nft.state != TokenState::Active { return Err(MintError::InvalidTransition(format!("{:?}", nft.state))); }
        nft.check_possession(now)?;
        if consent.chip_id != nft.chip_id || consent.token_id != nft.token_id { return Err(MintError::BadSignature); }
        let chip = registry.get(&nft.chip_id).ok_or(MintError::ChipNotRegistered)?;
        let vk = HybridVerifier::new(&chip.pubkey).map_err(|_| MintError::BadSignature)?;
        vk.verify(domain::TRANSFER, &consent.message_bytes(), &consent.signature).map_err(|_| MintError::BadSignature)?;
        if now.saturating_sub(consent.timestamp_ms) > 5 * 60 * 1000 { return Err(MintError::BadSignature); }
        nft.holder = consent.new_holder;
        nft.record_tap(now);
        Ok(())
    }

    pub fn digital_transfer_pending(nft: &PhysicalNft, new_holder: Hash256, now: u64) -> Result<PendingTransfer, MintError> {
        if nft.state != TokenState::Active { return Err(MintError::InvalidTransition(format!("{:?}", nft.state))); }
        Ok(PendingTransfer {
            token_id: nft.token_id, new_holder,
            initiated_at_ms: now,
            confirmation_deadline_ms: now + 7 * 24 * 3600 * 1000,
            cancelled: false,
        })
    }
}

#[derive(Clone, Serialize, Deserialize)]
pub struct PendingTransfer {
    pub token_id: u64,
    pub new_holder: Hash256,
    pub initiated_at_ms: u64,
    pub confirmation_deadline_ms: u64,
    pub cancelled: bool,
}

#[derive(Debug, thiserror::Error)]
pub enum TransferError { #[error("mint: {0}")] Mint(#[from] MintError) }
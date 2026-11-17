pub mod chip;
pub mod redemption;
pub mod token;
pub mod transfer;

pub use chip::{ChipRecord, ChipRegistry, ChipStatus};
pub use redemption::{RedemptionDirection, RedemptionEngine, RedemptionRequest};
pub use token::{PhysicalNft, TokenState};
pub use transfer::{ChipTransferConsent, PendingTransfer, TransferError, TransferProtocol};

use crypto_pqc::Hash256;
pub type TokenId = u64;

#[derive(Debug, thiserror::Error)]
pub enum MintError {
    #[error("chip not registered")] ChipNotRegistered,
    #[error("chip revoked")] ChipRevoked,
    #[error("chip already bound")] ChipAlreadyBound,
    #[error("token not found")] TokenNotFound,
    #[error("invalid transition: {0}")] InvalidTransition(String),
    #[error("signature invalid")] BadSignature,
    #[error("no possession proof")] NoPossessionProof,
    #[error("possession window expired")] PossessionWindowExpired,
    #[error("invalid nonce")] InvalidNonce,
    #[error("transfer already pending")] TransferAlreadyPending,
    #[error("redemption not eligible")] RedemptionNotEligible,
    #[error("vault not found")] VaultNotFound,
}
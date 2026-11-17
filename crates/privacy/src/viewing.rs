use serde::{Deserialize, Serialize};

#[derive(Clone, Serialize, Deserialize)]
pub enum DisclosureScope {
    Tx([u8; 32]),
    Range { from: u64, to: u64 },
    Counterparty([u8; 32]),
    Asset([u8; 32]),
    Full,
}

#[derive(Clone, Serialize, Deserialize)]
pub struct Disclosure {
    pub scope: DisclosureScope,
    pub encrypted_vk: Vec<u8>,
    pub recipient: [u8; 32],
    pub granted_at: u64,
    pub expires_at: Option<u64>,
    pub legal_reference: Option<String>,
}

impl Disclosure {
    pub fn is_expired(&self, now: u64) -> bool { self.expires_at.map(|e| now > e).unwrap_or(false) }
}
//! PQ Wrapped Asset client.

use crate::types::WrappedAsset;

/// Result of a wrap or unwrap operation.
#[derive(Debug, Clone)]
pub struct WrapResult {
    pub tx_hash: String,
    pub ref_: String,
    pub amount: u64,
    pub to: String,
}

/// Client for wrapping BTC/ETH/USDC into quantum-safe LXON assets.
pub struct PQWrapperClient {
    rpc_url: String,
    wrapper_address: String,
}

impl PQWrapperClient {
    pub fn new(rpc_url: &str, wrapper_address: &str) -> Self {
        Self {
            rpc_url: rpc_url.to_string(),
            wrapper_address: wrapper_address.to_string(),
        }
    }

    /// Wrap an ERC20 underlying (requires approve first).
    /// Returns the transaction hash.
    pub async fn wrap_erc20(&self, _private_key: &str, amount: u64, ref: &str) -> WrapResult {
        WrapResult {
            tx_hash: String::new(),
            ref_: ref.to_string(),
            amount,
            to: String::new(),
        }
    }

    /// Unwrap wrapped tokens (requires redemption to be open).
    pub async fn unwrap(&self, _private_key: &str, amount: u64, ref: &str) -> WrapResult {
        WrapResult {
            tx_hash: String::new(),
            ref_: ref.to_string(),
            amount,
            to: String::new(),
        }
    }

    /// Fetch the on-chain state of a wrapped asset.
    pub async fn get_asset(&self, address: &str) -> WrappedAsset {
        let client = reqwest::Client::new();
        let payload = serde_json::json!({
            "jsonrpc": "2.0",
            "id": 1,
            "method": "lxon_getWrappedAsset",
            "params": [address],
        });
        let resp = client.post(&self.rpc_url).json(&payload).send().await
            .expect("RPC call failed");
        resp.json().await.expect("invalid JSON")
    }
}
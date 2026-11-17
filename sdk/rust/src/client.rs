//! LXON JSON-RPC client.

use reqwest::Client;
use serde_json::{json, Value};
use std::time::Duration;

/// A 0x-prefixed hex address.
pub type Address = String;

/// High-level client for LXON RPC + gateway.
///
/// ```rust
/// use lxon_sdk::LxonClient;
///
/// #[tokio::main]
/// async fn main() {
///     let client = LxonClient::new("http://localhost:8545");
///     let block = client.get_block_number().await.unwrap();
///     println!("block: {}", block);
/// }
/// ```
pub struct LxonClient {
    rpc_url: String,
    client: Client,
    id: std::sync::atomic::AtomicU64,
}

impl LxonClient {
    pub fn new(rpc_url: &str) -> Self {
        Self {
            rpc_url: rpc_url.to_string(),
            client: Client::builder().timeout(Duration::from_secs(30)).build().unwrap(),
            id: std::sync::atomic::AtomicU64::new(0),
        }
    }

    async fn call(&self, method: &str, params: Vec<Value>) -> Result<Value, reqwest::Error> {
        let id = self.id.fetch_add(1, std::sync::atomic::Ordering::SeqCst) + 1;
        let payload = json!({
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        });
        let resp = self.client.post(&self.rpc_url).json(&payload).send().await?;
        let json: Value = resp.json().await?;
        if let Some(err) = json.get("error") {
            if !err.is_null() {
                return Ok(Value::String(format!("RPC error: {}", err)));
            }
        }
        Ok(json["result"].clone())
    }

    pub async fn get_block_number(&self) -> Result<u64, reqwest::Error> {
        let result = self.call("eth_blockNumber", vec![]).await?;
        let hex = result.as_str().unwrap_or("0x0");
        Ok(u64::from_str_radix(hex.trim_start_matches("0x"), 16).unwrap_or(0))
    }

    pub async fn get_balance(&self, address: &Address) -> Result<u64, reqwest::Error> {
        let result = self.call("eth_getBalance", vec![json!(address), json!("latest")]).await?;
        let hex = result.as_str().unwrap_or("0x0");
        Ok(u64::from_str_radix(hex.trim_start_matches("0x"), 16).unwrap_or(0))
    }

    pub async fn get_chain_id(&self) -> Result<u64, reqwest::Error> {
        let result = self.call("eth_chainId", vec![]).await?;
        let hex = result.as_str().unwrap_or("0x1");
        Ok(u64::from_str_radix(hex.trim_start_matches("0x"), 16).unwrap_or(1))
    }

    pub async fn get_transaction(&self, tx_hash: &str) -> Result<Value, reqwest::Error> {
        self.call("eth_getTransactionByHash", vec![json!(tx_hash)]).await
    }

    pub async fn get_wrapped_asset(&self, address: &Address) -> Result<Value, reqwest::Error> {
        self.call("lxon_getWrappedAsset", vec![json!(address)]).await
    }

    pub async fn get_wrap_history(&self, user: &Address, limit: usize) -> Result<Value, reqwest::Error> {
        self.call("lxon_getWrapHistory", vec![json!(user), json!(limit)]).await
    }
}
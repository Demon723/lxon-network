//! Custodian attestation client.

use crate::types::Attestation;
use reqwest::Client;
use serde_json::json;
use std::time::Duration;

/// Client for submitting custodian attestations to the LXON vault.
pub struct CustodyClient {
    rpc_url: String,
    client: Client,
    id: std::sync::atomic::AtomicU64,
}

impl CustodyClient {
    pub fn new(rpc_url: &str) -> Self {
        Self {
            rpc_url: rpc_url.to_string(),
            client: Client::builder().timeout(Duration::from_secs(30)).build().unwrap(),
            id: std::sync::atomic::AtomicU64::new(0),
        }
    }

    async fn call(&self, method: &str, params: Vec<serde_json::Value>) -> serde_json::Value {
        let id = self.id.fetch_add(1, std::sync::atomic::Ordering::SeqCst) + 1;
        let payload = json!({
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        });
        let resp = self.client.post(&self.rpc_url).json(&payload).send().await
            .expect("RPC call failed");
        resp.json().await.expect("invalid JSON")
    }

    /// Submit a custodian attestation.
    pub async fn submit_attestation(
        &self,
        ref: &str,
        asset_id: &str,
        custodian: &str,
        to: &str,
        amount: u64,
        proof: &str,
    ) -> serde_json::Value {
        self.call("lxon_submitAttestation", vec![
            json!(ref), json!(asset_id), json!(custodian), json!(to), json!(amount.to_string()), json!(proof),
        ]).await
    }

    /// Fetch a previously submitted attestation.
    pub async fn get_attestation(&self, ref: &str) -> Option<Attestation> {
        let result = self.call("lxon_getAttestation", vec![json!(ref)]).await;
        result.get("result").and_then(|v| {
            if v.is_null() { None } else { serde_json::from_value(v.clone()).ok() }
        })
    }
}
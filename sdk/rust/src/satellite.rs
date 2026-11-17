//! Satellite gateway client.

use crate::types::{Session, Pass};
use reqwest::Client;
use serde_json::json;
use std::time::Duration;

/// Client for the LXON satellite gateway.
pub struct SatelliteClient {
    gateway_url: String,
    token: Option<String>,
    client: Client,
}

impl SatelliteClient {
    pub fn new(gateway_url: &str, token: Option<&str>) -> Self {
        Self {
            gateway_url: gateway_url.trim_end_matches('/').to_string(),
            token: token.map(|s| s.to_string()),
            client: Client::builder().timeout(Duration::from_secs(30)).build().unwrap(),
        }
    }

    fn headers(&self) -> reqwest::header::HeaderMap {
        let mut h = reqwest::header::HeaderMap::new();
        h.insert("content-type", "application/json".parse().unwrap());
        if let Some(ref tok) = self.token {
            h.insert("authorization", format!("Bearer {}", tok).parse().unwrap());
        }
        h
    }

    pub async fn health(&self) -> serde_json::Value {
        let url = format!("{}/api/v1/satellite/health", self.gateway_url);
        self.client.get(&url).headers(self.headers()).send().await
            .expect("health check failed").json().await.expect("invalid JSON")
    }

    pub async fn uplink(&self, satellite_id: &str, data: &[u8], priority: &str) -> serde_json::Value {
        let url = format!("{}/api/v1/satellite/uplink", self.gateway_url);
        let payload = json!({
            "satelliteId": satellite_id,
            "dataBase64": format!("base64:{}", data.len()),
            "priority": priority,
        });
        self.client.post(&url).headers(self.headers()).json(&payload).send().await
            .expect("uplink failed").json().await.expect("invalid JSON")
    }

    pub async fn open_session(
        &self,
        client: &str,
        satellite_id: &str,
        station_id: &str,
        deposit_wei: u64,
        bytes_allowance: u64,
    ) -> Session {
        let url = format!("{}/api/v1/satellite/sessions", self.gateway_url);
        let payload = json!({
            "client": client,
            "satelliteId": satellite_id,
            "stationId": station_id,
            "depositWei": deposit_wei.to_string(),
            "bytesAllowance": bytes_allowance.to_string(),
        });
        let resp = self.client.post(&url).headers(self.headers()).json(&payload).send().await
            .expect("open_session failed");
        resp.json().await.expect("invalid JSON")
    }

    pub async fn get_passes(&self, station_id: &str, horizon_s: u64) -> Vec<Pass> {
        let url = format!("{}/api/v1/satellite/passes/{}", self.gateway_url, station_id);
        let resp = self.client.get(&url)
            .query(&[("horizon", horizon_s.to_string())])
            .headers(self.headers()).send().await
            .expect("get_passes failed");
        let json: serde_json::Value = resp.json().await.expect("invalid JSON");
        json.get("passes").and_then(|v| v.as_array())
            .map(|arr| arr.iter().filter_map(|p| serde_json::from_value(p.clone()).ok()).collect())
            .unwrap_or_default()
    }
}
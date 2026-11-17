use crate::evidence::Evidence;
use serde::Serialize;

#[derive(Debug, Serialize)]
pub struct Alert { pub severity: &'static str, pub title: String, pub evidence: Evidence }

pub trait AlertSink: Send + Sync { fn fire(&self, e: &Evidence); }

pub struct TracingAlert;
impl AlertSink for TracingAlert {
    fn fire(&self, e: &Evidence) {
        tracing::warn!(kind=?e.kind, ip=?e.source_ip, ua=?e.user_agent, payload=%e.payload, id=%hex::encode(e.id), "HONEYPOT");
    }
}

pub struct WebhookAlert { pub url: String, pub client: reqwest::Client }
impl WebhookAlert {
    pub fn new(url: impl Into<String>) -> Self {
        Self { url: url.into(), client: reqwest::Client::builder().timeout(std::time::Duration::from_secs(5)).build().unwrap_or_default() }
    }
}
impl AlertSink for WebhookAlert {
    fn fire(&self, e: &Evidence) {
        let msg = format!("LXON HONEYPOT\nkind: {:?}\nip: {:?}\npayload: {}", e.kind, e.source_ip, e.payload);
        let url = self.url.clone(); let c = self.client.clone();
        let p = serde_json::json!({ "text": msg, "content": msg });
        tokio::spawn(async move { let _ = c.post(&url).json(&p).send().await; });
    }
}

pub struct MultiSink(pub Vec<Box<dyn AlertSink + Send + Sync>>);
impl AlertSink for MultiSink {
    fn fire(&self, e: &Evidence) { for s in &self.0 { s.fire(e); } }
}
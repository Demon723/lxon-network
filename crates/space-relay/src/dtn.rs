use std::collections::VecDeque;
use crypto_pqc::{hash_256, Hash256};
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use crate::orbit::PassWindow;
use crate::satellite::SatelliteId;

pub type BundleId = Hash256;

#[derive(Clone, Serialize, Deserialize)]
pub struct Bundle {
    pub id: BundleId, pub src: String, pub dst: String,
    pub created_at_s: f64, pub expires_at_s: f64,
    pub payload: Vec<u8>, pub hop_count: u32,
}

impl Bundle {
    pub fn new(src: &str, dst: &str, p: Vec<u8>, now: f64, ttl: f64) -> Self {
        let mut h = Vec::new();
        h.extend_from_slice(src.as_bytes()); h.extend_from_slice(dst.as_bytes());
        h.extend_from_slice(&p); h.extend_from_slice(&now.to_le_bytes());
        Self { id: hash_256(b"lxon/dtn/bundle", &h), src: src.into(), dst: dst.into(), created_at_s: now, expires_at_s: now + ttl, payload: p, hop_count: 0 }
    }
    pub fn is_expired(&self, n: f64) -> bool { n > self.expires_at_s }
}

pub struct DtnNode {
    pub name: String,
    queue: Mutex<VecDeque<Bundle>>,
    passes: Mutex<Vec<PassWindow>>,
    pub satellite: Option<SatelliteId>,
}

impl DtnNode {
    pub fn new(name: &str) -> Self {
        Self { name: name.into(), queue: Mutex::new(VecDeque::new()), passes: Mutex::new(Vec::new()), satellite: None }
    }
    pub fn enqueue(&self, b: Bundle) -> Result<(), DtnError> {
        let mut q = self.queue.lock();
        if q.len() >= 100_000 { return Err(DtnError::QueueFull); }
        q.push_back(b); Ok(())
    }
    pub fn register_pass(&self, p: PassWindow) { self.passes.lock().push(p); }
    pub fn drain_ready(&self, now: f64) -> Vec<Bundle> {
        let mut q = self.queue.lock();
        let mut keep = VecDeque::new(); let mut r = Vec::new();
        while let Some(b) = q.pop_front() {
            if b.is_expired(now) { continue; }
            let p = self.passes.lock();
            let ok = p.iter().any(|w| now >= w.start_s && now <= w.end_s);
            drop(p);
            if ok { r.push(b); } else { keep.push_back(b); }
        }
        *q = keep; r
    }
    pub fn queue_len(&self) -> usize { self.queue.lock().len() }
}

#[derive(Debug, thiserror::Error)]
pub enum DtnError { #[error("queue full")] QueueFull, #[error("no route")] NoRoute, #[error("link down")] LinkDown }

pub type BundleStore = Vec<Bundle>;

#[cfg(test)]
mod tests {
    use super::*;
    use crate::satellite::LinkKind;
    #[test] fn expiry() {
        let b = Bundle::new("a", "b", vec![1], 0.0, 60.0);
        assert!(!b.is_expired(30.0));
        assert!(b.is_expired(120.0));
    }
    #[test] fn forward_on_pass() {
        let n = DtnNode::new("g");
        n.register_pass(PassWindow { satellite: [0u8;32], station: "g".into(), start_s: 10.0, end_s: 20.0, max_elevation_deg: 80.0, kind: LinkKind::Optical });
        n.enqueue(Bundle::new("a", "b", vec![1], 0.0, 100.0)).unwrap();
        assert_eq!(n.drain_ready(5.0).len(), 0);
        assert_eq!(n.drain_ready(15.0).len(), 1);
    }
}
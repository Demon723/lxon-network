use chrono::{DateTime, Utc};
use ed25519_dalek::{Signature, Signer, SigningKey, Verifier, VerifyingKey};
use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use sha3::{Digest, Sha3_256};
use std::io::Write;
use std::net::IpAddr;
use std::path::PathBuf;
use std::sync::Arc;
use thiserror::Error;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum EvidenceKind {
    FakeAdminAccess, FakeAdminLogin, FakeRpcCall, FakeKeyUse,
    FakeTreasuryTouch, FakeDeployFile, SuspiciousProbe,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Evidence {
    pub id: [u8; 32],
    pub kind: EvidenceKind,
    pub timestamp: DateTime<Utc>,
    pub source_ip: Option<IpAddr>,
    pub user_agent: Option<String>,
    pub headers: Vec<(String, String)>,
    pub payload: String,
    pub request_hash: [u8; 32],
    pub server_signature: Vec<u8>,
}

impl Evidence {
    pub fn new(kind: EvidenceKind, ip: Option<IpAddr>, ua: Option<String>, headers: Vec<(String, String)>, payload: String, sk: &SigningKey) -> Self {
        let now = Utc::now();
        let mut h1 = Sha3_256::new();
        h1.update(now.timestamp_nanos_opt().unwrap_or(0).to_le_bytes());
        h1.update(payload.as_bytes());
        if let Some(i) = ip { h1.update(i.to_string().as_bytes()); }
        let id: [u8; 32] = h1.finalize().into();
        let mut h2 = Sha3_256::new();
        h2.update(kind_tag(&kind)); h2.update(payload.as_bytes());
        let rh: [u8; 32] = h2.finalize().into();
        let mut e = Evidence { id, kind, timestamp: now, source_ip: ip, user_agent: ua, headers, payload, request_hash: rh, server_signature: vec![] };
        let sig = sk.sign(&e.canonical_bytes());
        e.server_signature = sig.to_bytes().to_vec();
        e
    }
    pub fn canonical_bytes(&self) -> Vec<u8> {
        let mut b = Vec::new();
        b.extend_from_slice(&self.id); b.extend_from_slice(&self.request_hash);
        b.extend_from_slice(&self.timestamp.timestamp_millis().to_le_bytes());
        b.extend_from_slice(self.payload.as_bytes());
        b
    }
    pub fn verify(&self, vk: &VerifyingKey) -> bool {
        let Ok(sb) = <[u8; 64]>::try_from(self.server_signature.as_slice()) else { return false; };
        let sig = Signature::from_bytes(&sb);
        vk.verify(&self.canonical_bytes(), &sig).is_ok()
    }
}

fn kind_tag(k: &EvidenceKind) -> &'static [u8] {
    match k {
        EvidenceKind::FakeAdminAccess => b"admin_access",
        EvidenceKind::FakeAdminLogin => b"admin_login",
        EvidenceKind::FakeRpcCall => b"rpc_call",
        EvidenceKind::FakeKeyUse => b"key_use",
        EvidenceKind::FakeTreasuryTouch => b"treasury",
        EvidenceKind::FakeDeployFile => b"deploy",
        EvidenceKind::SuspiciousProbe => b"suspicious",
    }
}

#[derive(Debug, Error)]
pub enum EvidenceError {
    #[error("io: {0}")] Io(#[from] std::io::Error),
    #[error("serialize: {0}")] Serialize(String),
}

pub struct EvidenceStore {
    inner: Arc<RwLock<Vec<Evidence>>>,
    signing_key: SigningKey,
    file_path: PathBuf,
}

impl EvidenceStore {
    pub fn new(sk: SigningKey, path: impl Into<PathBuf>) -> Self {
        let p: PathBuf = path.into();
        if let Some(parent) = p.parent() { let _ = std::fs::create_dir_all(parent); }
        Self { inner: Arc::new(RwLock::new(Vec::new())), signing_key: sk, file_path: p }
    }
    pub fn signing_key(&self) -> &SigningKey { &self.signing_key }
    pub fn verifying_key(&self) -> VerifyingKey { self.signing_key.verifying_key() }
    pub fn record(&self, e: Evidence) -> Result<(), EvidenceError> {
        let mut f = std::fs::OpenOptions::new().create(true).append(true).open(&self.file_path)?;
        let line = serde_json::to_string(&e).map_err(|x| EvidenceError::Serialize(x.to_string()))?;
        writeln!(f, "{line}")?; f.sync_all()?;
        self.inner.write().push(e); Ok(())
    }
    pub fn count(&self) -> usize { self.inner.read().len() }
    pub fn recent(&self, n: usize) -> Vec<Evidence> { self.inner.read().iter().rev().take(n).cloned().collect() }
    pub fn by_ip(&self, ip: IpAddr) -> Vec<Evidence> {
        self.inner.read().iter().filter(|e| e.source_ip == Some(ip)).cloned().collect()
    }
    pub fn all(&self) -> Vec<Evidence> { self.inner.read().clone() }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rand::rngs::OsRng;
    use tempfile::tempdir;
    #[test] fn sign_verify() {
        let sk = SigningKey::generate(&mut OsRng);
        let vk = sk.verifying_key();
        let e = Evidence::new(EvidenceKind::FakeAdminAccess, None, None, vec![], "t".into(), &sk);
        assert!(e.verify(&vk));
    }
    #[test] fn tamper_fails() {
        let sk = SigningKey::generate(&mut OsRng);
        let vk = sk.verifying_key();
        let mut e = Evidence::new(EvidenceKind::FakeAdminAccess, None, None, vec![], "t".into(), &sk);
        e.payload = "x".into();
        assert!(!e.verify(&vk));
    }
    #[test] fn persists() {
        let dir = tempdir().unwrap();
        let p = dir.path().join("e.log");
        let sk = SigningKey::generate(&mut OsRng);
        let s = EvidenceStore::new(sk.clone(), &p);
        s.record(Evidence::new(EvidenceKind::FakeRpcCall, None, None, vec![], "x".into(), &sk)).unwrap();
        assert_eq!(s.count(), 1);
    }
}
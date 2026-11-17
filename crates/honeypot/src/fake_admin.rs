use axum::{extract::{ConnectInfo, State}, http::{HeaderMap, StatusCode}, response::IntoResponse, routing::{get, post}, Json, Router};
use serde::{Deserialize, Serialize};
use sha3::{Digest, Sha3_256};
use std::net::SocketAddr;
use std::sync::Arc;
use crate::alert::AlertSink;
use crate::evidence::{Evidence, EvidenceKind, EvidenceStore};

#[derive(Clone)]
pub struct HoneypotState { pub store: Arc<EvidenceStore>, pub alert: Arc<dyn AlertSink> }

pub fn router(s: HoneypotState) -> Router {
    Router::new()
        .route("/", get(|| async { axum::response::Html("<h1>LXON Admin</h1>") }))
        .route("/admin", get(page))
        .route("/admin/login", post(login))
        .route("/admin/treasury/drain", post(drain))
        .route("/admin/keys/export", post(export))
        .with_state(s)
}

async fn page() -> impl IntoResponse {
    axum::response::Html(r#"<form method="POST" action="/admin/login"><input name="user"><input name="pass" type="password"><button>Sign in</button></form>"#)
}

#[derive(Deserialize, Serialize)]
struct Login { user: String, #[serde(default)] pass: String }

async fn login(ConnectInfo(a): ConnectInfo<SocketAddr>, State(s): State<HoneypotState>, h: HeaderMap, Json(b): Json<Login>) -> impl IntoResponse {
    let mut hh = Sha3_256::new(); hh.update(b.pass.as_bytes());
    let p = serde_json::json!({ "user": b.user, "pass_hash": hex::encode(hh.finalize()), "canary": crate::CANARY }).to_string();
    let e = Evidence::new(EvidenceKind::FakeAdminLogin, Some(a.ip()),
        h.get("user-agent").and_then(|v| v.to_str().ok()).map(String::from),
        h.iter().map(|(k, v)| (k.to_string(), v.to_str().unwrap_or("").to_string())).collect(),
        p, s.store.signing_key());
    let _ = s.store.record(e.clone()); s.alert.fire(&e);
    tokio::time::sleep(std::time::Duration::from_millis(250)).await;
    (StatusCode::UNAUTHORIZED, Json(serde_json::json!({"error":"invalid credentials"})))
}

async fn drain(State(s): State<HoneypotState>, h: HeaderMap) -> impl IntoResponse {
    let e = Evidence::new(EvidenceKind::FakeTreasuryTouch, None,
        h.get("user-agent").and_then(|v| v.to_str().ok()).map(String::from), vec![], "drain".into(), s.store.signing_key());
    let _ = s.store.record(e.clone()); s.alert.fire(&e);
    (StatusCode::OK, Json(serde_json::json!({"status":"queued","tx_hash":"0x0"})))
}

async fn export(State(s): State<HoneypotState>, h: HeaderMap) -> impl IntoResponse {
    let e = Evidence::new(EvidenceKind::FakeKeyUse, None,
        h.get("user-agent").and_then(|v| v.to_str().ok()).map(String::from), vec![], "export".into(), s.store.signing_key());
    let _ = s.store.record(e.clone()); s.alert.fire(&e);
    (StatusCode::OK, Json(serde_json::json!({"private_key": crate::CANARY})))
}
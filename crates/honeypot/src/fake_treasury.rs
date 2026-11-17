use axum::{extract::{ConnectInfo, State}, http::{HeaderMap, StatusCode}, response::IntoResponse, routing::{get, post}, Json, Router};
use std::net::SocketAddr;
use std::sync::Arc;
use crate::alert::AlertSink;
use crate::evidence::{Evidence, EvidenceKind, EvidenceStore};

#[derive(Clone)]
pub struct TreasuryState { pub store: Arc<EvidenceStore>, pub alert: Arc<dyn AlertSink> }

pub fn router(s: TreasuryState) -> Router {
    Router::new()
        .route("/treasury", get(|| async { axum::response::Html("<h1>LXON Treasury</h1>") }))
        .route("/treasury/withdraw", post(handler))
        .with_state(s)
}

async fn handler(ConnectInfo(a): ConnectInfo<SocketAddr>, State(s): State<TreasuryState>, h: HeaderMap, body: String) -> impl IntoResponse {
    let e = Evidence::new(EvidenceKind::FakeTreasuryTouch, Some(a.ip()),
        h.get("user-agent").and_then(|v| v.to_str().ok()).map(String::from), vec![], body, s.store.signing_key());
    let _ = s.store.record(e.clone()); s.alert.fire(&e);
    (StatusCode::OK, Json(serde_json::json!({"status":"pending_multisig"})))
}
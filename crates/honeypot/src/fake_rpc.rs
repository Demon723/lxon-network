use axum::{extract::{ConnectInfo, State}, http::HeaderMap, response::IntoResponse, routing::post, Json, Router};
use std::net::SocketAddr;
use std::sync::Arc;
use crate::alert::AlertSink;
use crate::evidence::{Evidence, EvidenceKind, EvidenceStore};

#[derive(Clone)]
pub struct RpcHoneypotState { pub store: Arc<EvidenceStore>, pub alert: Arc<dyn AlertSink> }

pub fn router(s: RpcHoneypotState) -> Router {
    Router::new().route("/", post(handler)).route("/rpc", post(handler)).with_state(s)
}

async fn handler(ConnectInfo(a): ConnectInfo<SocketAddr>, State(s): State<RpcHoneypotState>, h: HeaderMap, body: String) -> impl IntoResponse {
    let e = Evidence::new(EvidenceKind::FakeRpcCall, Some(a.ip()),
        h.get("user-agent").and_then(|v| v.to_str().ok()).map(String::from),
        h.iter().map(|(k, v)| (k.to_string(), v.to_str().unwrap_or("").to_string())).collect(),
        body, s.store.signing_key());
    let _ = s.store.record(e.clone()); s.alert.fire(&e);
    Json(serde_json::json!({"jsonrpc":"2.0","id":1,"result":"0x1"}))
}
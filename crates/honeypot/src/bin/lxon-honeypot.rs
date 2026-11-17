use clap::Parser;
use ed25519_dalek::SigningKey;
use honeypot::alert::{AlertSink, MultiSink, TracingAlert, WebhookAlert};
use honeypot::evidence::EvidenceStore;
use honeypot::{fake_admin, fake_rpc, fake_treasury};
use rand::rngs::OsRng;
use std::sync::Arc;

#[derive(Parser, Debug)]
#[command(name = "lxon-honeypot", version)]
struct Args {
    #[arg(long, default_value = "admin")] mode: String,
    #[arg(long, default_value_t = 8081)] port: u16,
    #[arg(long, default_value = "/evidence/honeypot.log")] evidence: String,
    #[arg(long, env = "ALERT_WEBHOOK")] webhook: Option<String>,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt().json().with_env_filter(
        tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into())
    ).init();
    let a = Args::parse();
    let sk = SigningKey::generate(&mut OsRng);
    tracing::info!(vk = %hex::encode(sk.verifying_key().to_bytes()), "honeypot start");
    let store = Arc::new(EvidenceStore::new(sk, &a.evidence));
    let mut sinks: Vec<Box<dyn AlertSink + Send + Sync>> = vec![Box::new(TracingAlert)];
    if let Some(u) = &a.webhook { sinks.push(Box::new(WebhookAlert::new(u.clone()))); }
    let alert: Arc<dyn AlertSink> = Arc::new(MultiSink(sinks));
    let app = match a.mode.as_str() {
        "admin" => fake_admin::router(fake_admin::HoneypotState { store: store.clone(), alert: alert.clone() }),
        "rpc" => fake_rpc::router(fake_rpc::RpcHoneypotState { store: store.clone(), alert: alert.clone() }),
        "treasury" => fake_treasury::router(fake_treasury::TreasuryState { store: store.clone(), alert: alert.clone() }),
        o => anyhow::bail!("unknown mode: {o}"),
    };
    let addr = format!("0.0.0.0:{}", a.port);
    let l = tokio::net::TcpListener::bind(&addr).await?;
    tracing::info!(mode=%a.mode, addr=%addr, "listening");
    axum::serve(l, app.into_make_service_with_connect_info::<std::net::SocketAddr>()).await?;
    Ok(())
}
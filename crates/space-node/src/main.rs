use std::sync::Arc;
use crypto_pqc::HybridSigner;
use l2_sequencer::sequencer::{BatchSink, SinkError, Sequencer, SequencerConfig};
use l2_sequencer::{BatchCommitment, PaymentIntent};
use rand::rngs::OsRng;
use space_relay::dtn::{Bundle, DtnNode};
use space_relay::orbit::{Constellation, GroundStation};
use space_relay::satellite::Satellite;
use tracing::info;

struct DtnSink(Arc<DtnNode>);

#[async_trait::async_trait]
impl BatchSink for DtnSink {
    async fn commit(&self, c: BatchCommitment) -> Result<(), SinkError> {
        let p = bincode::serialize(&c).map_err(|e| SinkError::Unavailable(e.to_string()))?;
        self.0.enqueue(Bundle::new("seq", "l1-gw", p, 0.0, 600.0)).map_err(|e| SinkError::Unavailable(e.to_string()))
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt().json().with_env_filter(
        tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into())
    ).init();
    let mut rng = OsRng;
    let mut c = Constellation::new();
    for i in 0..3 {
        c.add_satellite(Satellite::new(&format!("lxon-sat-{i}"), 550.0, 53.0, i as f64 * 120.0));
    }
    for (n, la, lo) in [("gs-blr", 12.97, 77.59), ("gs-sg", 1.35, 103.82)] {
        c.add_station(GroundStation { id: n.into(), lat_deg: la, lon_deg: lo, min_elevation_deg: 10.0 });
    }
    let ps = c.passes(0.0, 3600.0);
    info!(count = ps.len(), "passes computed");
    let dtn = Arc::new(DtnNode::new("seq"));
    for p in ps.iter().take(5) { dtn.register_pass(p.clone()); }
    let sk = HybridSigner::generate(&mut rng);
    let seq = Arc::new(Sequencer::new(SequencerConfig::default(), sk, Box::new(DtnSink(dtn.clone()))));
    let u = HybridSigner::generate(&mut rng);
    for i in 0..5u64 {
        let p = format!("p-{i}").into_bytes();
        let sig = u.sign_tx(&p);
        let mut intent = PaymentIntent { id: [0u8;32], from: u.public_key(), ciphertext: p, pqc_signature: sig, submitted_at_ms: i, fee_units: 1 };
        intent.id = intent.compute_id();
        seq.submit(intent).map_err(|e| anyhow::anyhow!("submit: {e}"))?;
    }
    for _ in 0..3 { let _ = seq.tick().await?; }
    info!(queue = dtn.queue_len(), "space node running");
    Ok(())
}
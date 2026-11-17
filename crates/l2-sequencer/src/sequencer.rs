use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use crypto_pqc::HybridSigner;
use tokio::sync::Mutex;
use tokio::time::{interval, Duration};
use tracing::{info, warn};
use crate::batch::{Batch, BatchCommitment};
use crate::mempool::Mempool;
use crate::state::L2State;
use crate::PaymentIntent;

pub struct SequencerConfig {
    pub batch_size: usize,
    pub batch_interval_ms: u64,
    pub max_mempool: usize,
}

impl Default for SequencerConfig {
    fn default() -> Self { Self { batch_size: 1_000, batch_interval_ms: 400, max_mempool: 1_000_000 } }
}

pub struct Sequencer {
    cfg: SequencerConfig,
    mempool: Arc<Mempool>,
    state: Arc<L2State>,
    signer: Arc<HybridSigner>,
    next_index: Arc<Mutex<u64>>,
    commit_sink: Box<dyn BatchSink + Send + Sync>,
}

#[async_trait::async_trait]
pub trait BatchSink {
    async fn commit(&self, c: BatchCommitment) -> Result<(), SinkError>;
}

#[derive(Debug, thiserror::Error)]
pub enum SinkError { #[error("sink: {0}")] Unavailable(String) }

impl Sequencer {
    pub fn new(cfg: SequencerConfig, signer: HybridSigner, commit_sink: Box<dyn BatchSink + Send + Sync>) -> Self {
        Self {
            cfg,
            mempool: Arc::new(Mempool::new(cfg.max_mempool)),
            state: Arc::new(L2State::new()),
            signer: Arc::new(signer),
            next_index: Arc::new(Mutex::new(0)),
            commit_sink,
        }
    }
    pub fn submit(&self, i: PaymentIntent) -> Result<(), crate::mempool::MempoolError> { self.mempool.insert(i) }
    pub async fn tick(&self) -> Result<Option<BatchCommitment>, SequencerError> {
        let intents = self.mempool.drain_batch(self.cfg.batch_size);
        if intents.is_empty() { return Ok(None); }
        let state_root = self.state.root();
        let mut idx = self.next_index.lock().await;
        let index = *idx; *idx += 1; drop(idx);
        let now = now_ms();
        let batch = Batch::new(index, intents, state_root, now);
        let da_blob = bincode::serialize(&batch).map_err(|e| SequencerError::Serialize(e.to_string()))?;
        let sig = self.signer.sign_block(&batch.root);
        let c = BatchCommitment::from_batch(&batch, &da_blob, sig);
        self.commit_sink.commit(c.clone()).await.map_err(|e| SequencerError::Sink(e.to_string()))?;
        info!(index, root = %hex::encode(batch.root), "committed L2 batch");
        Ok(Some(c))
    }
    pub async fn run(self: Arc<Self>) {
        let mut t = interval(Duration::from_millis(self.cfg.batch_interval_ms));
        loop {
            t.tick().await;
            if let Err(e) = self.tick().await { warn!(error = %e, "tick failed"); }
        }
    }
}

#[derive(Debug, thiserror::Error)]
pub enum SequencerError {
    #[error("serialize: {0}")] Serialize(String),
    #[error("sink: {0}")] Sink(String),
}

fn now_ms() -> u64 { SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis() as u64 }

pub struct InMemorySink { pub committed: parking_lot::Mutex<Vec<BatchCommitment>> }
impl InMemorySink { pub fn new() -> Self { Self { committed: parking_lot::Mutex::new(Vec::new()) } } }
#[async_trait::async_trait]
impl BatchSink for InMemorySink {
    async fn commit(&self, c: BatchCommitment) -> Result<(), SinkError> { self.committed.lock().push(c); Ok(()) }
}
impl Default for InMemorySink { fn default() -> Self { Self::new() } }

#[cfg(test)]
mod tests {
    use super::*;
    use crate::PaymentIntent;
    use crypto_pqc::HybridSigner;
    use rand::rngs::OsRng;
    #[tokio::test] async fn commits() {
        let mut rng = OsRng;
        let user = HybridSigner::generate(&mut rng);
        let seq = HybridSigner::generate(&mut rng);
        let s = Sequencer::new(SequencerConfig::default(), seq, Box::new(InMemorySink::new()));
        for i in 0..3u64 {
            let p = i.to_le_bytes().to_vec();
            let sig = user.sign_tx(&p);
            let mut intent = PaymentIntent { id: [0u8; 32], from: user.public_key(), ciphertext: p, pqc_signature: sig, submitted_at_ms: i, fee_units: 1 };
            intent.id = intent.compute_id();
            s.submit(intent).unwrap();
        }
        assert!(s.tick().await.unwrap().is_some());
    }
}
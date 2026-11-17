use dashmap::DashMap;
use parking_lot::RwLock;
use crate::{IntentError, PaymentIntent};
use crypto_pqc::Hash256;

pub struct Mempool {
    by_id: DashMap<Hash256, PaymentIntent>,
    order: RwLock<Vec<Hash256>>,
    max_size: usize,
}

impl Mempool {
    pub fn new(max_size: usize) -> Self {
        Self { by_id: DashMap::new(), order: RwLock::new(Vec::new()), max_size }
    }
    pub fn insert(&self, intent: PaymentIntent) -> Result<(), MempoolError> {
        intent.verify().map_err(MempoolError::Invalid)?;
        if self.by_id.len() >= self.max_size { return Err(MempoolError::Full); }
        if self.by_id.contains_key(&intent.id) { return Err(MempoolError::Duplicate); }
        let id = intent.id;
        self.by_id.insert(id, intent);
        self.order.write().push(id);
        Ok(())
    }
    pub fn drain_batch(&self, n: usize) -> Vec<PaymentIntent> {
        let mut order = self.order.write();
        let take = n.min(order.len());
        let ids: Vec<_> = order.drain(..take).collect();
        drop(order);
        ids.into_iter().filter_map(|id| self.by_id.remove(&id).map(|(_, v)| v)).collect()
    }
    pub fn len(&self) -> usize { self.by_id.len() }
    pub fn is_empty(&self) -> bool { self.by_id.is_empty() }
}

#[derive(Debug, thiserror::Error)]
pub enum MempoolError {
    #[error("mempool full")] Full,
    #[error("duplicate intent")] Duplicate,
    #[error("invalid intent: {0}")] Invalid(IntentError),
    #[error("eviction failed")] EvictionFailed,
    #[error("batch limit exceeded")] BatchLimitExceeded,
    #[error("priority queue error")] PriorityQueueError,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crypto_pqc::HybridSigner;
    use rand::rngs::OsRng;

    fn mk(sk: &HybridSigner, p: &[u8], ts: u64) -> PaymentIntent {
        let sig = sk.sign_tx(p);
        let mut i = PaymentIntent {
            id: [0u8; 32], from: sk.public_key(), ciphertext: p.to_vec(),
            pqc_signature: sig, submitted_at_ms: ts, fee_units: 1,
        };
        i.id = i.compute_id();
        i
    }

    #[test] fn insert_and_drain() {
        let mut rng = OsRng;
        let sk = HybridSigner::generate(&mut rng);
        let mp = Mempool::new(10);
        for i in 0..5 { mp.insert(mk(&sk, b"p", i)).unwrap(); }
        assert_eq!(mp.len(), 5);
        assert_eq!(mp.drain_batch(3).len(), 3);
        assert_eq!(mp.len(), 2);
    }
    #[test] fn replay_rejected() {
        let mut rng = OsRng;
        let sk = HybridSigner::generate(&mut rng);
        let mp = Mempool::new(10);
        let i = mk(&sk, b"x", 1);
        mp.insert(i.clone()).unwrap();
        assert!(matches!(mp.insert(i), Err(MempoolError::Duplicate)));
    }
    #[test] fn mempool_full() {
        let mut rng = OsRng;
        let sk = HybridSigner::generate(&mut rng);
        let mp = Mempool::new(2);
        mp.insert(mk(&sk, b"a", 1)).unwrap();
        mp.insert(mk(&sk, b"b", 2)).unwrap();
        assert!(matches!(mp.insert(mk(&sk, b"c", 3)), Err(MempoolError::Full)));
    }
}
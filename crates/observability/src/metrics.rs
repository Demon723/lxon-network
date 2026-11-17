use parking_lot::Mutex;
use prometheus::{Counter, CounterVec, Gauge, GaugeVec, Histogram, HistogramOpts, HistogramVec, Registry, TextEncoder, Encoder};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::time::{Duration, Instant};

#[derive(Clone, Serialize, Deserialize)]
pub struct MetricSnapshot {
    pub name: String,
    pub value: f64,
    pub labels: Vec<(String, String)>,
    pub timestamp: i64,
}

pub struct LxonMetrics {
    registry: Registry,
    tx_processed: CounterVec,
    tx_failed: CounterVec,
    block_height: Gauge,
    mempool_size: Gauge,
    peer_count: Gauge,
    sequencer_latency: Histogram,
    validation_latency: Histogram,
    network_latency: Histogram,
}

impl LxonMetrics {
    pub fn new() -> Self {
        let registry = Registry::new();
        
        let tx_processed = CounterVec::new(
            prometheus::opts!("tx_processed_total", "Total transactions processed"),
            &["type", "status"]
        ).expect("metric creation");
        
        let tx_failed = CounterVec::new(
            prometheus::opts!("tx_failed_total", "Total transactions failed"),
            &["type", "error"]
        ).expect("metric creation");
        
        let block_height = Gauge::new(
            "block_height", "Current block height"
        ).expect("metric creation");
        
        let mempool_size = Gauge::new(
            "mempool_size", "Current mempool size"
        ).expect("metric creation");
        
        let peer_count = Gauge::new(
            "peer_count", "Current peer count"
        ).expect("metric creation");
        
        let sequencer_latency = Histogram::with_opts(
            HistogramOpts::new("sequencer_latency_seconds", "Sequencer operation latency")
                .buckets(vec![0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0])
        ).expect("metric creation");
        
        let validation_latency = Histogram::with_opts(
            HistogramOpts::new("validation_latency_seconds", "Transaction validation latency")
                .buckets(vec![0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0])
        ).expect("metric creation");
        
        let network_latency = Histogram::with_opts(
            HistogramOpts::new("network_latency_seconds", "Network operation latency")
                .buckets(vec![0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5])
        ).expect("metric creation");
        
        registry.register(Box::new(tx_processed.clone())).expect("metric registration");
        registry.register(Box::new(tx_failed.clone())).expect("metric registration");
        registry.register(Box::new(block_height.clone())).expect("metric registration");
        registry.register(Box::new(mempool_size.clone())).expect("metric registration");
        registry.register(Box::new(peer_count.clone())).expect("metric registration");
        registry.register(Box::new(sequencer_latency.clone())).expect("metric registration");
        registry.register(Box::new(validation_latency.clone())).expect("metric registration");
        registry.register(Box::new(network_latency.clone())).expect("metric registration");
        
        Self {
            registry,
            tx_processed,
            tx_failed,
            block_height,
            mempool_size,
            peer_count,
            sequencer_latency,
            validation_latency,
            network_latency,
        }
    }
    
    pub fn inc_tx_processed(&self, tx_type: &str, status: &str) {
        self.tx_processed.with_label_values(&[tx_type, status]).inc();
    }
    
    pub fn inc_tx_failed(&self, tx_type: &str, error: &str) {
        self.tx_failed.with_label_values(&[tx_type, error]).inc();
    }
    
    pub fn set_block_height(&self, height: u64) {
        self.block_height.set(height as f64);
    }
    
    pub fn set_mempool_size(&self, size: usize) {
        self.mempool_size.set(size as f64);
    }
    
    pub fn set_peer_count(&self, count: usize) {
        self.peer_count.set(count as f64);
    }
    
    pub fn observe_sequencer_latency<F, R>(&self, f: F) -> R
    where
        F: FnOnce() -> R,
    {
        self.sequencer_latency.observe_closure_duration(f)
    }
    
    pub fn observe_validation_latency<F, R>(&self, f: F) -> R
    where
        F: FnOnce() -> R,
    {
        self.validation_latency.observe_closure_duration(f)
    }
    
    pub fn observe_network_latency<F, R>(&self, f: F) -> R
    where
        F: FnOnce() -> R,
    {
        self.network_latency.observe_closure_duration(f)
    }
    
    pub fn export(&self) -> Result<String, Box<dyn std::error::Error>> {
        let encoder = TextEncoder::new();
        let metric_families = self.registry.gather();
        let mut buffer = Vec::new();
        encoder.encode(&metric_families, &mut buffer)?;
        Ok(String::from_utf8(buffer)?)
    }
    
    pub fn snapshot(&self) -> Vec<MetricSnapshot> {
        let mut snapshots = Vec::new();
        let now = chrono::Utc::now().timestamp();
        
        for metric_family in self.registry.gather() {
            for metric in &metric_family.get_metric() {
                let value = match metric_family.get_name() {
                    "tx_processed_total" => metric.get_counter().get_value(),
                    "tx_failed_total" => metric.get_counter().get_value(),
                    "block_height" => metric.get_gauge().get_value(),
                    "mempool_size" => metric.get_gauge().get_value(),
                    "peer_count" => metric.get_gauge().get_value(),
                    _ => continue,
                };
                
                let labels: Vec<(String, String)> = metric.get_label()
                    .iter()
                    .map(|l| (l.get_name().to_string(), l.get_value().to_string()))
                    .collect();
                
                snapshots.push(MetricSnapshot {
                    name: metric_family.get_name().to_string(),
                    value,
                    labels,
                    timestamp: now,
                });
            }
        }
        
        snapshots
    }
}

impl Default for LxonMetrics {
    fn default() -> Self {
        Self::new()
    }
}

pub struct MetricsCollector {
    metrics: Arc<Mutex<LxonMetrics>>,
    history: Arc<Mutex<Vec<MetricSnapshot>>>,
    max_history: usize,
}

impl MetricsCollector {
    pub fn new(metrics: LxonMetrics, max_history: usize) -> Self {
        Self {
            metrics: Arc::new(Mutex::new(metrics)),
            history: Arc::new(Mutex::new(Vec::new())),
            max_history,
        }
    }
    
    pub fn metrics(&self) -> Arc<Mutex<LxonMetrics>> {
        Arc::clone(&self.metrics)
    }
    
    pub fn collect_snapshot(&self) {
        let snapshot = self.metrics.lock().snapshot();
        let mut history = self.history.lock();
        history.extend(snapshot);
        
        if history.len() > self.max_history {
            let drain = history.len() - self.max_history;
            history.drain(0..drain);
        }
    }
    
    pub fn get_history(&self) -> Vec<MetricSnapshot> {
        self.history.lock().clone()
    }
    
    pub fn get_metric_history(&self, name: &str) -> Vec<MetricSnapshot> {
        self.history.lock()
            .iter()
            .filter(|s| s.name == name)
            .cloned()
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_metrics_creation() {
        let metrics = LxonMetrics::new();
        metrics.inc_tx_processed("payment", "success");
        metrics.set_block_height(100);
        
        let export = metrics.export().unwrap();
        assert!(export.contains("tx_processed_total"));
        assert!(export.contains("block_height"));
    }
    
    #[test]
    fn test_metrics_snapshot() {
        let metrics = LxonMetrics::new();
        metrics.inc_tx_processed("payment", "success");
        metrics.set_block_height(100);
        
        let snapshot = metrics.snapshot();
        assert!(!snapshot.is_empty());
    }
    
    #[test]
    fn test_metrics_collector() {
        let metrics = LxonMetrics::new();
        let collector = MetricsCollector::new(metrics, 100);
        
        collector.collect_snapshot();
        let history = collector.get_history();
        assert!(!history.is_empty());
    }
}
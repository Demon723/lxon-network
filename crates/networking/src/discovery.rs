use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::net::SocketAddr;
use std::time::Duration;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct DiscoveryConfig {
    pub enable_mdns: bool,
    pub enable_kademlia: bool,
    pub bootstrap_peers: Vec<SocketAddr>,
    pub discovery_interval: Duration,
}

impl Default for DiscoveryConfig {
    fn default() -> Self {
        Self {
            enable_mdns: true,
            enable_kademlia: false,
            bootstrap_peers: vec![],
            discovery_interval: Duration::from_secs(30),
        }
    }
}

pub struct PeerDiscovery {
    config: DiscoveryConfig,
    known_peers: RwLock<HashSet<SocketAddr>>,
}

impl PeerDiscovery {
    pub fn new(config: DiscoveryConfig) -> Self {
        Self {
            config,
            known_peers: RwLock::new(HashSet::new()),
        }
    }
    
    pub async fn start(&self) {
        tracing::info!("Starting peer discovery");
        
        // Add bootstrap peers
        for peer in &self.config.bootstrap_peers {
            self.known_peers.write().insert(*peer);
        }
        
        if self.config.enable_mdns {
            self.start_mdns_discovery().await;
        }
    }
    
    async fn start_mdns_discovery(&self) {
        tracing::info!("Starting mDNS discovery");
        // In a real implementation, this would use libp2p's mdns
    }
    
    pub fn add_peer(&self, addr: SocketAddr) {
        self.known_peers.write().insert(addr);
    }
    
    pub fn remove_peer(&self, addr: SocketAddr) {
        self.known_peers.write().remove(&addr);
    }
    
    pub fn get_peers(&self) -> Vec<SocketAddr> {
        self.known_peers.read().iter().cloned().collect()
    }
    
    pub fn peer_count(&self) -> usize {
        self.known_peers.read().len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[tokio::test]
    async fn test_peer_discovery() {
        let config = DiscoveryConfig::default();
        let discovery = PeerDiscovery::new(config);
        
        discovery.add_peer("127.0.0.1:8080".parse().unwrap());
        assert_eq!(discovery.peer_count(), 1);
    }
}
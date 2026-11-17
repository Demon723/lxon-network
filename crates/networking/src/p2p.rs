use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Arc;
use thiserror::Error;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct PeerInfo {
    pub id: String,
    pub address: SocketAddr,
    pub version: String,
    pub capabilities: Vec<String>,
    pub last_seen: i64,
    pub latency_ms: Option<u64>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct P2PConfig {
    pub listen_address: SocketAddr,
    pub max_peers: usize,
    pub bootstrap_peers: Vec<SocketAddr>,
    pub enable_mdns: bool,
    pub enable_relay: bool,
}

impl Default for P2PConfig {
    fn default() -> Self {
        Self {
            listen_address: "0.0.0.0:0".parse().unwrap(),
            max_peers: 50,
            bootstrap_peers: vec![],
            enable_mdns: true,
            enable_relay: false,
        }
    }
}

#[derive(Debug, Error)]
pub enum P2PError {
    #[error("peer not found: {0}")] PeerNotFound(String),
    #[error("max peers reached")] MaxPeersReached,
    #[error("connection failed: {0}")] ConnectionFailed(String),
    #[error("invalid message")] InvalidMessage,
}

pub struct P2PNetwork {
    config: P2PConfig,
    peers: Arc<RwLock<HashMap<String, PeerInfo>>>,
    local_peer_id: String,
}

impl P2PNetwork {
    pub fn new(config: P2PConfig) -> Self {
        let local_peer_id = Self::generate_peer_id();
        
        Self {
            config,
            peers: Arc::new(RwLock::new(HashMap::new())),
            local_peer_id,
        }
    }
    
    fn generate_peer_id() -> String {
        use rand::Rng;
        let mut rng = rand::thread_rng();
        format!("lxon-peer-{:x}", rng.gen::<u64>())
    }
    
    pub fn local_peer_id(&self) -> &str {
        &self.local_peer_id
    }
    
    pub async fn start(&self) -> Result<(), P2PError> {
        tracing::info!("Starting P2P network on {}", self.config.listen_address);
        
        // In a real implementation, this would start libp2p
        // For now, we'll simulate the network structure
        
        for peer_addr in &self.config.bootstrap_peers {
            self.connect_to_peer(*peer_addr).await?;
        }
        
        Ok(())
    }
    
    async fn connect_to_peer(&self, addr: SocketAddr) -> Result<(), P2PError> {
        let peers = self.peers.read();
        if peers.len() >= self.config.max_peers {
            return Err(P2PError::MaxPeersReached);
        }
        drop(peers);
        
        // Simulate peer connection
        let peer_info = PeerInfo {
            id: Self::generate_peer_id(),
            address: addr,
            version: "0.1.0".to_string(),
            capabilities: vec!["block-sync".to_string(), "tx-relay".to_string()],
            last_seen: chrono::Utc::now().timestamp(),
            latency_ms: None,
        };
        
        let mut peers = self.peers.write();
        peers.insert(peer_info.id.clone(), peer_info);
        
        tracing::info!("Connected to peer {} at {}", peer_info.id, addr);
        Ok(())
    }
    
    pub fn add_peer(&self, peer: PeerInfo) -> Result<(), P2PError> {
        let mut peers = self.peers.write();
        
        if peers.len() >= self.config.max_peers {
            return Err(P2PError::MaxPeersReached);
        }
        
        peers.insert(peer.id.clone(), peer);
        Ok(())
    }
    
    pub fn remove_peer(&self, peer_id: &str) -> Result<(), P2PError> {
        let mut peers = self.peers.write();
        
        if peers.remove(peer_id).is_none() {
            return Err(P2PError::PeerNotFound(peer_id.to_string()));
        }
        
        Ok(())
    }
    
    pub fn get_peer(&self, peer_id: &str) -> Option<PeerInfo> {
        self.peers.read().get(peer_id).cloned()
    }
    
    pub fn get_all_peers(&self) -> Vec<PeerInfo> {
        self.peers.read().values().cloned().collect()
    }
    
    pub fn peer_count(&self) -> usize {
        self.peers.read().len()
    }
    
    pub async fn broadcast_message(&self, message: Vec<u8>) -> Result<(), P2PError> {
        let peers = self.peers.read();
        
        tracing::debug!("Broadcasting message to {} peers", peers.len());
        
        // In a real implementation, this would use gossipsub
        for peer in peers.values() {
            tracing::trace!("Sending message to peer {}", peer.id);
        }
        
        Ok(())
    }
    
    pub async fn send_message(&self, peer_id: &str, message: Vec<u8>) -> Result<(), P2PError> {
        let peers = self.peers.read();
        
        if !peers.contains_key(peer_id) {
            return Err(P2PError::PeerNotFound(peer_id.to_string()));
        }
        
        tracing::debug!("Sending message to peer {}", peer_id);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[tokio::test]
    async fn test_p2p_network() {
        let config = P2PConfig::default();
        let network = P2PNetwork::new(config);
        
        assert!(!network.local_peer_id().is_empty());
        assert_eq!(network.peer_count(), 0);
    }
    
    #[tokio::test]
    async fn test_add_peer() {
        let config = P2PConfig::default();
        let network = P2PNetwork::new(config);
        
        let peer = PeerInfo {
            id: "test-peer".to_string(),
            address: "127.0.0.1:8080".parse().unwrap(),
            version: "0.1.0".to_string(),
            capabilities: vec![],
            last_seen: chrono::Utc::now().timestamp(),
            latency_ms: None,
        };
        
        network.add_peer(peer).unwrap();
        assert_eq!(network.peer_count(), 1);
    }
    
    #[tokio::test]
    async fn test_max_peers() {
        let config = P2PConfig {
            max_peers: 1,
            ..Default::default()
        };
        let network = P2PNetwork::new(config);
        
        let peer = PeerInfo {
            id: "test-peer".to_string(),
            address: "127.0.0.1:8080".parse().unwrap(),
            version: "0.1.0".to_string(),
            capabilities: vec![],
            last_seen: chrono::Utc::now().timestamp(),
            latency_ms: None,
        };
        
        network.add_peer(peer.clone()).unwrap();
        assert!(network.add_peer(peer).is_err());
    }
}
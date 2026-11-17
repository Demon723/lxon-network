use libp2p::{swarm::derive_prelude::*, gossipsub, mdns, kad};
use serde::{Deserialize, Serialize};

#[derive(Clone, Serialize, Deserialize)]
pub struct BehaviourConfig {
    pub enable_gossipsub: bool,
    pub enable_kademlia: bool,
    pub enable_mdns: bool,
}

impl Default for BehaviourConfig {
    fn default() -> Self {
        Self {
            enable_gossipsub: true,
            enable_kademlia: true,
            enable_mdns: true,
        }
    }
}

#[derive(NetworkBehaviour)]
pub struct LxonBehaviour {
    gossipsub: gossipsub::Behaviour,
    kademlia: kad::Behaviour<kad::store::MemoryStore>,
    mdns: mdns::tokio::Behaviour,
}

impl LxonBehaviour {
    pub fn new(_config: BehaviourConfig) -> Self {
        let gossipsub_config = gossipsub::ConfigBuilder::default()
            .build()
            .expect("Valid config");
        
        let local_key = libp2p::identity::Keypair::generate_ed25519();
        let local_peer_id = local_key.public().to_peer_id();
        let gossipsub = gossipsub::Behaviour::new(
            gossipsub::MessageAuthenticity::Signed(local_key.clone()),
            gossipsub_config,
        ).expect("Correct configuration");
        
        let kademlia = kad::Behaviour::new(
            local_peer_id,
            kad::store::MemoryStore::new(local_peer_id),
        );
        
        let mdns = mdns::tokio::Behaviour::new(
            mdns::Config::default(),
            local_peer_id,
        ).expect("Valid configuration");
        
        Self {
            gossipsub,
            kademlia,
            mdns,
        }
    }
}
use libp2p::{swarm::Swarm, SwarmBuilder, identity, noise, tcp, yamux};
use serde::{Deserialize, Serialize};
use super::behaviour::{LxonBehaviour, BehaviourConfig};

#[derive(Clone, Serialize, Deserialize)]
pub struct SwarmConfig {
    pub listen_address: String,
    pub behaviour_config: BehaviourConfig,
}

impl Default for SwarmConfig {
    fn default() -> Self {
        Self {
            listen_address: "/ip4/0.0.0.0/tcp/0".to_string(),
            behaviour_config: BehaviourConfig::default(),
        }
    }
}

pub struct LxonSwarm {
    swarm: Swarm<LxonBehaviour>,
}

impl LxonSwarm {
    pub fn new(config: SwarmConfig) -> Result<Self, Box<dyn std::error::Error>> {
        let local_key = identity::Keypair::generate_ed25519();
        let behaviour = LxonBehaviour::new(config.behaviour_config);
        
        let swarm = SwarmBuilder::with_existing_identity(local_key)
            .with_tokio()
            .with_tcp(
                tcp::Config::default(),
                noise::Config::new,
                yamux::Config::default,
            )?
            .with_behaviour(|_| behaviour)?
            .build();
        
        Ok(Self { swarm })
    }
    
    pub async fn start(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        // In a real implementation, this would start the swarm event loop
        Ok(())
    }
    
    pub fn peer_id(&self) -> libp2p::PeerId {
        *self.swarm.local_peer_id()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[tokio::test]
    async fn test_swarm_creation() {
        let config = SwarmConfig::default();
        let swarm = LxonSwarm::new(config);
        assert!(swarm.is_ok());
    }
}
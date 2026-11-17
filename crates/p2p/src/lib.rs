//! P2P networking layer for LXON using libp2p.
pub mod swarm;
pub mod behaviour;
pub mod protocol;

pub use swarm::{LxonSwarm, SwarmConfig};
pub use behaviour::{LxonBehaviour, BehaviourConfig};
pub use protocol::{LxonProtocol, Message};
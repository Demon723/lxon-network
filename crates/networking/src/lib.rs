//! Networking layer for LXON with P2P, RPC, and HTTP server capabilities.
pub mod p2p;
pub mod rpc;
pub mod http;
pub mod discovery;

pub use p2p::{P2PNetwork, P2PConfig, PeerInfo};
pub use rpc::{RpcServer, RpcHandler};
pub use http::{HttpServer, HttpConfig};
pub use discovery::{PeerDiscovery, DiscoveryConfig};
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum Message {
    Block(BlockMessage),
    Transaction(TransactionMessage),
    Ping(PingMessage),
    Pong(PongMessage),
    PeerList(PeerListMessage),
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct BlockMessage {
    pub height: u64,
    pub hash: [u8; 32],
    pub data: Vec<u8>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct TransactionMessage {
    pub tx_id: [u8; 32],
    pub data: Vec<u8>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct PingMessage {
    pub nonce: u64,
    pub timestamp: u64,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct PongMessage {
    pub nonce: u64,
    pub timestamp: u64,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct PeerListMessage {
    pub peers: Vec<PeerInfo>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct PeerInfo {
    pub id: String,
    pub address: String,
    pub version: String,
}

pub struct LxonProtocol;

impl LxonProtocol {
    pub fn serialize(message: &Message) -> Result<Vec<u8>, Box<dyn std::error::Error>> {
        bincode::serialize(message).map_err(|e| e.into())
    }
    
    pub fn deserialize(data: &[u8]) -> Result<Message, Box<dyn std::error::Error>> {
        bincode::deserialize(data).map_err(|e| e.into())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_message_serialization() {
        let msg = Message::Ping(PingMessage {
            nonce: 42,
            timestamp: 1234567890,
        });
        
        let serialized = LxonProtocol::serialize(&msg).unwrap();
        let deserialized = LxonProtocol::deserialize(&serialized).unwrap();
        
        match deserialized {
            Message::Ping(ping) => {
                assert_eq!(ping.nonce, 42);
            }
            _ => panic!("Wrong message type"),
        }
    }
}
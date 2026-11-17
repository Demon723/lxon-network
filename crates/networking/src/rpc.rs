use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper::{Request, Response, StatusCode};
use hyper_util::rt::TokioIo;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Arc;
use thiserror::Error;
use tokio::net::TcpListener;

#[derive(Debug, Error)]
pub enum RpcError {
    #[error("method not found: {0}")] MethodNotFound(String),
    #[error("invalid params")] InvalidParams,
    #[error("internal error: {0}")] Internal(String),
    #[error("parse error")] ParseError,
}

#[derive(Clone, Serialize, Deserialize)]
pub struct RpcRequest {
    pub jsonrpc: String,
    pub id: serde_json::Value,
    pub method: String,
    pub params: serde_json::Value,
}

#[derive(Clone, Serialize, Deserialize)]
pub struct RpcResponse {
    pub jsonrpc: String,
    pub id: serde_json::Value,
    pub result: Option<serde_json::Value>,
    pub error: Option<RpcErrorInfo>,
}

#[derive(Clone, Serialize, Deserialize)]
pub struct RpcErrorInfo {
    pub code: i32,
    pub message: String,
    pub data: Option<serde_json::Value>,
}

pub type RpcHandler = Arc<dyn Fn(serde_json::Value) -> Result<serde_json::Value, RpcError> + Send + Sync>;

pub struct RpcServer {
    address: SocketAddr,
    handlers: Arc<parking_lot::RwLock<HashMap<String, RpcHandler>>>,
}

impl RpcServer {
    pub fn new(address: SocketAddr) -> Self {
        Self {
            address,
            handlers: Arc::new(parking_lot::RwLock::new(HashMap::new())),
        }
    }
    
    pub fn register_method(&self, name: String, handler: RpcHandler) {
        let mut handlers = self.handlers.write();
        handlers.insert(name, handler);
    }
    
    pub async fn start(&self) -> Result<(), Box<dyn std::error::Error>> {
        let listener = TcpListener::bind(self.address).await?;
        tracing::info!("RPC server listening on {}", self.address);
        
        let handlers = Arc::clone(&self.handlers);
        
        loop {
            let (stream, addr) = listener.accept().await?;
            let handlers = Arc::clone(&handlers);
            
            tokio::spawn(async move {
                let io = TokioIo::new(stream);
                
                if let Err(err) = http1::Builder::new()
                    .serve_connection(io, service_fn(move |req| {
                        let handlers = Arc::clone(&handlers);
                        async move { handle_request(req, handlers, addr).await }
                    }))
                    .await
                {
                    tracing::error!("Error serving connection: {}", err);
                }
            });
        }
    }
}

async fn handle_request(
    req: Request<hyper::body::Incoming>,
    handlers: Arc<parking_lot::RwLock<HashMap<String, RpcHandler>>>,
    addr: SocketAddr,
) -> Result<Response<hyper::body::Body>, hyper::Error> {
    let handlers = handlers.read();
    
    // Only handle POST requests
    if req.method() != hyper::Method::POST {
        return Ok(Response::builder()
            .status(StatusCode::METHOD_NOT_ALLOWED)
            .body(hyper::body::Body::from("Method not allowed"))?);
    }
    
    let body = match hyper::body::Bytes::from(req.into_body()).try_into() {
        Ok(bytes) => bytes,
        Err(_) => {
            return Ok(Response::builder()
                .status(StatusCode::BAD_REQUEST)
                .body(hyper::body::Body::from("Invalid request body"))?);
        }
    };
    
    let rpc_req: RpcRequest = match serde_json::from_slice(&body) {
        Ok(req) => req,
        Err(_) => {
            let response = RpcResponse {
                jsonrpc: "2.0".to_string(),
                id: serde_json::Value::Null,
                result: None,
                error: Some(RpcErrorInfo {
                    code: -32700,
                    message: "Parse error".to_string(),
                    data: None,
                }),
            };
            return Ok(Response::builder()
                .header("content-type", "application/json")
                .body(hyper::body::Body::from(serde_json::to_string(&response).unwrap()))?);
        }
    };
    
    let handlers = handlers.clone();
    let handler = handlers.get(&rpc_req.method);
    
    let response = match handler {
        Some(handler) => {
            match handler(rpc_req.params) {
                Ok(result) => RpcResponse {
                    jsonrpc: "2.0".to_string(),
                    id: rpc_req.id,
                    result: Some(result),
                    error: None,
                },
                Err(err) => RpcResponse {
                    jsonrpc: "2.0".to_string(),
                    id: rpc_req.id,
                    result: None,
                    error: Some(RpcErrorInfo {
                        code: -32603,
                        message: err.to_string(),
                        data: None,
                    }),
                },
            }
        }
        None => RpcResponse {
            jsonrpc: "2.0".to_string(),
            id: rpc_req.id,
            result: None,
            error: Some(RpcErrorInfo {
                code: -32601,
                message: format!("Method not found: {}", rpc_req.method),
                data: None,
            }),
        },
    };
    
    tracing::debug!("RPC request from {}: {} = {:?}", addr, rpc_req.method, response.error.is_none());
    
    Ok(Response::builder()
        .header("content-type", "application/json")
        .body(hyper::body::Body::from(serde_json::to_string(&response).unwrap()))?)
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[tokio::test]
    async fn test_rpc_server_creation() {
        let server = RpcServer::new("127.0.0.1:0".parse().unwrap());
        assert_eq!(server.address.port(), 0);
    }
    
    #[test]
    fn test_rpc_request_parsing() {
        let json = r#"{"jsonrpc":"2.0","method":"test","params":[],"id":1}"#;
        let req: RpcRequest = serde_json::from_str(json).unwrap();
        assert_eq!(req.method, "test");
    }
}
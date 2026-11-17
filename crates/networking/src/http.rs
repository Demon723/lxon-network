use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper::{Request, Response, StatusCode};
use hyper_util::rt::TokioIo;
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::net::TcpListener;

#[derive(Clone, Serialize, Deserialize)]
pub struct HttpConfig {
    pub address: SocketAddr,
    pub max_connections: usize,
    pub enable_cors: bool,
}

impl Default for HttpConfig {
    fn default() -> Self {
        Self {
            address: "0.0.0.0:8080".parse().unwrap(),
            max_connections: 1000,
            enable_cors: true,
        }
    }
}

pub type HttpHandler = Arc<dyn Fn(Request<hyper::body::Incoming>) -> Response<hyper::body::Body> + Send + Sync>;

pub struct HttpServer {
    config: HttpConfig,
    handler: Option<HttpHandler>,
}

impl HttpServer {
    pub fn new(config: HttpConfig) -> Self {
        Self {
            config,
            handler: None,
        }
    }
    
    pub fn with_handler(mut self, handler: HttpHandler) -> Self {
        self.handler = Some(handler);
        self
    }
    
    pub async fn start(self) -> Result<(), Box<dyn std::error::Error>> {
        let listener = TcpListener::bind(self.config.address).await?;
        tracing::info!("HTTP server listening on {}", self.config.address);
        
        let handler = self.handler.unwrap_or_else(|| {
            Arc::new(|_req| {
                Response::builder()
                    .status(StatusCode::OK)
                    .body(hyper::body::Body::from("LXON HTTP Server"))
                    .unwrap()
            })
        });
        
        loop {
            let (stream, addr) = listener.accept().await?;
            let handler = handler.clone();
            
            tokio::spawn(async move {
                let io = TokioIo::new(stream);
                
                if let Err(err) = http1::Builder::new()
                    .serve_connection(io, service_fn(move |req| {
                        let handler = handler.clone();
                        async move {
                            Ok::<_, hyper::Error>(handler(req))
                        }
                    }))
                    .await
                {
                    tracing::error!("Error serving HTTP connection from {}: {}", addr, err);
                }
            });
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_http_config_default() {
        let config = HttpConfig::default();
        assert_eq!(config.address.port(), 8080);
    }
    
    #[test]
    fn test_http_server_creation() {
        let server = HttpServer::new(HttpConfig::default());
        assert_eq!(server.config.address.port(), 8080);
    }
}
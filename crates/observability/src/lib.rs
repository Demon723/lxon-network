//! Observability stack for LXON with metrics, logging, and tracing.
pub mod metrics;
pub mod logging;
pub mod tracing_ext;
pub mod health;

pub use metrics::{LxonMetrics, MetricsCollector};
pub use logging::{init_logging, LogConfig};
pub use tracing_ext::{init_tracing, TraceConfig};
pub use health::{HealthChecker, HealthStatus};
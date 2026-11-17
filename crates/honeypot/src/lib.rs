pub mod alert;
pub mod evidence;
pub mod fake_admin;
pub mod fake_rpc;
pub mod fake_treasury;

pub use alert::{Alert, AlertSink, MultiSink, TracingAlert, WebhookAlert};
pub use evidence::{Evidence, EvidenceError, EvidenceKind, EvidenceStore};

pub const CANARY: &str = "lxon-canary-7f3a9b2c-do-not-use-real-key";
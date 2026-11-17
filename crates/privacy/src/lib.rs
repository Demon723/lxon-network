pub mod address;
pub mod commitment;
pub mod note;
pub mod nullifier;
pub mod tree;
pub mod tx;
pub mod viewing;

pub use address::{ShieldedAddress, SpendingKey, ViewingKey};
pub use commitment::{NoteCommitment, COMMITMENT_TREE_DEPTH};
pub use note::{Note, NotePlaintext};
pub use nullifier::{Nullifier, NullifierSet};
pub use tree::CommitmentTree;
pub use tx::{ShieldedTx, ShieldedTxBuilder};
pub use viewing::{Disclosure, DisclosureScope};

pub mod domain {
    pub const NOTE_COMMIT: &[u8] = b"lxon/privacy/v1/note-commit";
    pub const NULLIFIER: &[u8] = b"lxon/privacy/v1/nullifier";
    pub const ADDRESS: &[u8] = b"lxon/privacy/v1/address";
    pub const NOTE_ENCRYPT: &[u8] = b"lxon/privacy/v1/note-encrypt";
    pub const VIEWING_TAG: &[u8] = b"lxon/privacy/v1/viewing-tag";
    pub const MERKLE_NODE: &[u8] = b"lxon/privacy/v1/merkle";
}
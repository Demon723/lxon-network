use crypto_pqc::{Hash256, HybridSigner};
use l3_mint::chip::{ChipRecord, ChipRegistry, ChipStatus};
use l3_mint::token::{PhysicalNft, TokenState};
use l3_mint::transfer::{ChipTransferConsent, TransferProtocol};
use rand::rngs::OsRng;

fn h(b: &[u8]) -> Hash256 { crypto_pqc::hash_256(b"test", b) }

#[test]
fn full_lifecycle() {
    let mut rng = OsRng;
    let chip_sk = HybridSigner::generate(&mut rng);
    let chip_pk = chip_sk.public_key();
    let batch = h(b"b1");
    let chip_id = ChipRecord::compute_id(&chip_pk, &batch);
    let reg = ChipRegistry::new();
    reg.register(ChipRecord {
        chip_id, pubkey: chip_pk, batch,
        firmware_hash: h(b"fw"), attestation: vec![1, 2, 3],
        status: ChipStatus::Active, bound_token: None, registered_at_ms: 0,
    }).unwrap();
    let mut nft = PhysicalNft::new(1, chip_id, h(b"alice"), h(b"meta"), 0);
    nft.activate().unwrap();
    reg.bind_token(&chip_id, 1).unwrap();
    assert_eq!(nft.state, TokenState::Active);
    let cb = {
        let mut b = Vec::new();
        b.extend_from_slice(&chip_id);
        b.extend_from_slice(&1u64.to_le_bytes());
        b.extend_from_slice(&h(b"bob"));
        b.extend_from_slice(&1u64.to_le_bytes());
        b.extend_from_slice(&1_000u64.to_le_bytes());
        b
    };
    let consent = ChipTransferConsent {
        chip_id, token_id: 1, new_holder: h(b"bob"), nonce: 1, timestamp_ms: 1_000,
        signature: chip_sk.sign(crypto_pqc::domain::TRANSFER, &cb),
    };
    TransferProtocol::physical_transfer(&reg, &mut nft, consent, 1_500).unwrap();
    assert_eq!(nft.holder, h(b"bob"));
}
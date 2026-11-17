use sha3::{Digest, Sha3_256, Sha3_512};
pub type Hash256 = [u8; 32];
pub type Hash512 = [u8; 64];

pub fn hash_256(domain: &[u8], data: &[u8]) -> Hash256 {
    let mut h = Sha3_256::new(); h.update(domain); h.update(b"\x00"); h.update(data);
    h.finalize().into()
}
pub fn hash_512(domain: &[u8], data: &[u8]) -> Hash512 {
    let mut h = Sha3_512::new(); h.update(domain); h.update(b"\x00"); h.update(data);
    h.finalize().into()
}
pub fn merkle_root(domain: &[u8], leaves: &[Hash256]) -> Hash256 {
    if leaves.is_empty() { return [0u8; 32]; }
    let mut level: Vec<Hash256> = leaves.to_vec();
    while level.len() > 1 {
        if level.len() % 2 == 1 { level.push(*level.last().unwrap()); }
        level = level.chunks(2).map(|p| {
            let mut buf = [0u8; 64];
            buf[..32].copy_from_slice(&p[0]);
            buf[32..].copy_from_slice(&p[1]);
            hash_256(domain, &buf)
        }).collect();
    }
    level[0]
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test] fn merkle_ok() {
        let a = hash_256(b"l", b"a"); let b = hash_256(b"l", b"b");
        let mut buf = [0u8; 64];
        buf[..32].copy_from_slice(&a); buf[32..].copy_from_slice(&b);
        assert_eq!(merkle_root(b"l", &[a, b]), hash_256(b"l", &buf));
    }
}
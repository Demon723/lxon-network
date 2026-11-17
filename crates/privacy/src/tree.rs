use serde::{Deserialize, Serialize};
use crate::commitment::{NoteCommitment, COMMITMENT_TREE_DEPTH};
use crate::domain;

pub struct CommitmentTree { levels: Vec<Vec<[u8; 32]>>, next_index: u64 }

impl CommitmentTree {
    pub fn new() -> Self {
        let mut levels = Vec::with_capacity(COMMITMENT_TREE_DEPTH + 1);
        for _ in 0..=COMMITMENT_TREE_DEPTH { levels.push(Vec::new()); }
        Self { levels, next_index: 0 }
    }
    pub fn append(&mut self, c: NoteCommitment) -> u64 {
        let index = self.next_index; self.next_index += 1;
        let mut current = c.0;
        self.levels[0].push(current);
        let mut idx = index;
        for level in 0..COMMITMENT_TREE_DEPTH {
            let sib_idx = idx ^ 1;
            let sib = if (sib_idx as usize) < self.levels[level].len() { self.levels[level][sib_idx as usize] } else { [0u8; 32] };
            current = if idx % 2 == 0 { hash_pair(&current, &sib) } else { hash_pair(&sib, &current) };
            let p = idx / 2;
            if (p as usize) < self.levels[level + 1].len() { self.levels[level + 1][p as usize] = current; }
            else { self.levels[level + 1].push(current); }
            idx = p;
        }
        index
    }
    pub fn root(&self) -> [u8; 32] {
        if self.levels[COMMITMENT_TREE_DEPTH].is_empty() { [0u8; 32] } else { self.levels[COMMITMENT_TREE_DEPTH][0] }
    }
    pub fn len(&self) -> u64 { self.next_index }
    pub fn is_empty(&self) -> bool { self.next_index == 0 }
    pub fn path(&self, index: u64) -> Option<MerklePath> {
        if index >= self.next_index { return None; }
        let mut siblings = Vec::with_capacity(COMMITMENT_TREE_DEPTH);
        let mut idx = index;
        for level in 0..COMMITMENT_TREE_DEPTH {
            let sib_idx = idx ^ 1;
            let sib = if (sib_idx as usize) < self.levels[level].len() { self.levels[level][sib_idx as usize] } else { [0u8; 32] };
            siblings.push(sib); idx /= 2;
        }
        Some(MerklePath { index, siblings })
    }
}
impl Default for CommitmentTree { fn default() -> Self { Self::new() } }

#[derive(Clone, Serialize, Deserialize)]
pub struct MerklePath { pub index: u64, pub siblings: Vec<[u8; 32]> }

impl MerklePath {
    pub fn verify(&self, leaf: &NoteCommitment, root: &[u8; 32]) -> bool {
        let mut c = leaf.0; let mut idx = self.index;
        for s in &self.siblings {
            c = if idx % 2 == 0 { hash_pair(&c, s) } else { hash_pair(s, &c) };
            idx /= 2;
        }
        c == *root
    }
}

fn hash_pair(a: &[u8; 32], b: &[u8; 32]) -> [u8; 32] {
    let mut h = blake3::Hasher::new();
    h.update(domain::MERKLE_NODE); h.update(a); h.update(b);
    h.finalize().as_bytes()[..32].try_into().unwrap()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test] fn path_verifies() {
        let mut t = CommitmentTree::new();
        let c = NoteCommitment([42u8; 32]);
        let i = t.append(c);
        assert!(t.path(i).unwrap().verify(&c, &t.root()));
    }
}
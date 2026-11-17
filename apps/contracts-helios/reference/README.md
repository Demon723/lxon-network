# `reference/LXONAttestedBridgeV41.sol`

Read-only reference copy of the v4.1 attested bridge, landed by **PQC Plan 2, Task 1**
(`docs/superpowers/plans/2026-11-06-lxon-pqc-plan2-default-profile.md`).

| fact | value | how to re-take it |
|---|---|---|
| blob | `e305af5744340c51245351bd19cb28a5a12f7179` | `git rev-parse attested-bridge:apps/contracts/contracts/LXONAttestedBridgeV41.sol` |
| size | 28,426 bytes | `git cat-file -s <blob>` |
| lines | 603 | `wc -l reference/LXONAttestedBridgeV41.sol` |
| source ref | branch `attested-bridge`, path `apps/contracts/contracts/LXONAttestedBridgeV41.sol` | `git cat-file blob <blob>` |
| this copy's own hash | `e305af5744340c51245351bd19cb28a5a12f7179` | `git hash-object reference/LXONAttestedBridgeV41.sol` |

The copy's `git hash-object` **equals** the branch blob, which is the whole proof that it is
unaltered; the comparison was made between two non-empty outputs, not against a missing file.
`docs/runbooks/v41-citation-form-2026-11-12.md` records the same blob as the citation authority for
every `V41:NNN` reference in this repository, and `docs/tools/check-v41-citations.sh` re-counts it
(rule R1) and re-counts this directory's existence (rule R5) on every run.

This file is a read-only reference copy. It is not in `src/`, `script/` or `test/`, so `forge` never
compiles it, and it must never be deployed or broadcast from. Every `V41:NNN` citation in the PQC
plans and the spec resolves against this copy; the authoritative original is
`attested-bridge:apps/contracts/contracts/LXONAttestedBridgeV41.sol` at the blob hash above.

**What this copy is *not*.** Since 2026-11-12 the canonical citation form for documents on `main` is
`attested-bridge:apps/contracts/contracts/LXONAttestedBridgeV41.sol:NNN` (ruling 16), not this path.
This file exists so that Plan 2's executors and Task 4's structural copy have a local,
byte-pinned artifact to read and diff against, and so a `V41:NNN` line number can be opened without a
worktree. It is a build-time reading anchor, not a new citation authority, and runbooks must still
cite the branch.

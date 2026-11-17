# Chain 724 is a settlement layer, not a user surface

**Ruling recorded:** 2026-10-31, owner's choice from three options.
**Scope of this file:** what was decided, what was measured to justify it, what changed as a
result, and what did *not* change. It does not restate the bridge mechanics — see
`docs/runbooks/bridge-panel-724-to-137-2026-10-30.md` for the crossing panel and
`docs/runbooks/first-live-crossing-1000-724-to-137.md` for the first paid crossings.

---

## 1. The ruling

LXON chain 724 is the **settlement and custody** layer: it holds the canonical LXON, the
v4.1 bridge escrow, and the 724 wrapper. **Polygon 137 is the user-facing layer** for
wrapped LXON (`wLXON 0x7A3c0C34…`) and for anything that needs a market, a wallet with gas,
or an external counterparty.

The chain is not being changed, paused, migrated or re-adopted by this ruling. It is a
statement about who is expected to transact on it.

## 2. Why the two alternatives on the table were not available

The request was framed as: fix a Geth Clique miner being debugged, migrate to a
Clique-capable client such as Nethermind, or pivot. Neither of the first two exists.

| Claim to check | Measured 2026-10-31 |
| --- | --- |
| A Geth Clique miner is being debugged | No. `web3_clientVersion` = `besu/v26.10.0/linux-x86_64/openjdk-java-25` on `https://rpc.lxon.in`, `eth_chainId` = `0x2d4` (724) |
| The chain is stuck | No. Tip advanced `205,326 → 205,335 → 205,346` over 24 s (~5.00 s blocks), QBFT |
| A geth node is part of the deployment | No. `lxon-evm-node/docker-compose.yml` defines `besu-perms`, `besu-sealer`, `blockscout-db`, `blockscout-redis` — no geth service |
| Nethermind would add Clique support | Wrong direction. Nethermind has no QBFT engine; adopting it would mean replacing QBFT with Clique, i.e. undoing the migration that already happened. The compose file records why geth was abandoned: it gates Shanghai/Cancun EVM rules behind the merge, which a self-sealing Clique chain can never reach |

## 3. What the "orphan Clique directory" actually was

`lxon-evm-node/geth/` held a Clique genesis for chainId 724 (`period 5, epoch 30000`, one
alloc account), an 18-day-old `chaindata`, `run-geth.sh`, and `privatekey.txt`.

Two things were learned by looking rather than assuming:

1. `privatekey.txt` was a **bare 64-hex private key for `0xFaE699d2…419cAda`** — derived
   without printing it. That account is the deployer, the QBFT sealer identity, and one of the
   two signers on both chains.
2. `besu/privatekey.txt` is **byte-identical** to it (compared in memory with
   `crypto.timingSafeEqual`). So the geth copy was a duplicate of a live consensus-critical
   key, not a separate test key — and `aws/push-secrets.sh` was still reading the *geth* copy
   as the validator key it scp's to the node.

That second point is why the directory could not simply be deleted, and why deleting it was
also not necessary: the canonical copy is `lxon-evm-node/besu/privatekey.txt`.

## 4. Evidence for the ruling

### 4a. Nobody is transacting on 724

| Measure | Value | Source |
| --- | --- | --- |
| Transactions in the tip block | 0 | `eth_getBlockByNumber("latest", true)` |
| Blocks sealed with no transaction since the last one | ~7,500 (≈10.5 h at 5.00 s) | last tx `0xf2a3ff92…` at 2026-10-30T13:15Z; tip 205,346 at 2026-10-30T20:49Z (explorer index agrees with the RPC at the same height) |
| Senders across the 50 most recent transactions (28 h window) | 2 — `0xFaE699d2…` (42, mostly the wrap fixes) and `0x7F715B7F…` (8) | `explorer.lxon.in/api/v2/transactions` |
| Distinct accounts ever seen in any LXON `Transfer` | 14; 12 hold a balance | log census, below |
| Of those 12, externally-owned accounts | 4, and 3 of them are founder / deployer / `attestor-mac` | `eth_getCode` at the same tag, with the LXON token itself as a control row |

### 4b. The holder census, and its completeness proof

`tools`/`/tmp/lxontest/holder_census.py` walks every `Transfer` event for
`LXON 0x99801A78…` from block 0 to the tip in 5,000-block windows (this RPC refuses spans of
10,000 — `Requested range exceeds maximum RPC range limit`).

```
Transfer logs over the whole chain : 43
failed log ranges                  : 0      (every window answered)
minted from 0x0                    : 42,700,020,000.0000 LXON
burned to 0x0                      : 0.0000 LXON
totalSupply at block 205,497       : 42,700,020,000.0000 LXON   -> PASS (minted - burned == supply)
sum of positive balances           : 42,700,020,000.0000 LXON   -> PASS (every token attributed)
earliest Transfer                  : block 44, from 0x0         -> PASS (census starts at the mint)
```

Balances are computed **from the logs only**, never by reading back a chain state that the
same RPC prunes — `eth_getCode(…, "0x1000")` returns `null` here, so a historical-state census
would have been silently wrong.

Top of that table, in LXON: founder `0x7F715B7F…` 42,599,998,900 (EOA) · deployer
`0xFaE699d2…` 89,746,654.61 (EOA) · AMM pair `0x272a3ed4…` 10,001,000 (contract) ·
`0x24ad1de7…` 100,000 · v4.1 bridge `0x9B15fEe9…` 61,152 · 724 wrapper `0xC0CF6B0E…`
49,193.39 · legacy bridge `0x28C93c2a…` 30,000 · peg pool `0x8e90675e…` 22,000 ·
`attestor-mac 0x28369733…` 10,000 (EOA) · `0x37e1c5ec…` 1,000 · `0x…dead` 100.

**Founder concentration is 99.7658% of 724 supply**, measured from `balanceOf` over
`totalSupply` at 724 block 205,560. This is the number task #40 is still propagating through
the listing documents.

### 4c. The settlement side is sound

`/tmp/lxontest/settlement_v2.py`, one tag per chain (724 = 205,560, 137 = 96,459,312):

```
724  escrowed(LXON)                       31,152.0000
724  totalSentFor(137, LXON)              31,152.0000
724  laneNonce(137, LXON)                          3
724  totalReceivedFrom(137, wLXON)             0.0000    (return leg never used)
137  wLXON.totalSupply()                  31,152.0000
137  totalReceivedFrom(724, LXON-on-724)  31,152.0000
137  totalSentFor(724, wLXON)                  0.0000
724  wrapper collateral == wrapper supply 49,193.3891   (1:1)
both bridges: paused false, configSealed true, everUsed true

  escrowed == totalSentFor                 PASS
  escrowed == 137 wLXON supply             PASS
  137 received == escrowed                 PASS
  wrapper collateral == wrapper supply     PASS
```

Every bridged wLXON on Polygon is backed, one-for-one, by LXON sitting in the 724 bridge.
That is the job the ruling assigns to 724, and it is demonstrably being done.

### 4d. The thing that actually gates the user-facing layer: gas

Re-measured at 137 block 96,458,453, cross-checked on `polygon.drpc.org` for the key wallet:

| Wallet | POL on 137 | Key reachable from this machine |
| --- | --- | --- |
| `0x704af422b5db639185b779aa3a3cff6e48ba5521` | **1,946.7619342667** | no — EOA, target of the founder contract's auto-forward |
| `0x43410e73d2ef4b2638be10265e8be3d2fdffdc27` | 0.0062621188 | yes (leaked developer key) — **not authorised** |
| `0x2a8Ca01C53cecF360b181a0B7D49a71565684665` | 0.0018204306 | yes — the 137 ceremony keystore, the wallet a claim pays gas from |
| founder `0x7F715B7F…` on 137 | 0.000000 | it is a 23-byte contract there, not an EOA — hence the auto-forward |

`eth_gasPrice` on 137 is 268.5 Gwei; the largest claim run so far cost 0.065445 POL.
**No wallet this machine can sign for has usable POL.** That is the real constraint on
growing the user-facing side, and it is an owner-side action: send ~0.5 POL to
`0x2a8Ca01C53cecF360b181a0B7D49a71565684665`, or have the recipient claim with their own gas.

## 5. What changed as a result of the ruling

1. `lxon-evm-node/geth/` moved to `~/.lxon/archive/geth-clique-2026-10-31/`, mode `0700`,
   contents `0600`, outside any repo tree. Nothing was deleted — the key file, the Clique
   genesis and the old `chaindata` are all recoverable from there, and the same three tracked
   files are also recoverable from git history at HEAD~ (`git status` shows them as unstaged
   deletions).
2. `lxon-evm-node/aws/push-secrets.sh` now reads the sealer key from `besu/privatekey.txt`
   via an overridable `SEALER_KEY=` variable. Before this change it read the geth duplicate,
   so the archive would have silently broken the one script that re-provisions the live node.
3. `scripts/release-verify.sh` had **two** references to the removed geth genesis, and both now
   point at `lxon-evm-node/besu/genesis.qbft.json` — the chainId source list at line 60 and the
   `GENESIS_PATH` at line 124. Verified against the QBFT file: it declares `chainId: 724`, has
   `qbft` and no `clique`, and its `extraData` (122 hex chars) begins `0xf83a` and contains
   `fae699d2…cada`, the validator in live block 0. Note this file is **untracked**
   (`git status` reports `?? scripts/release-verify.sh`), so neither edit appears in a diff of
   tracked paths.

Neither edit is committed, and nothing is staged — this worktree is shared with other running
sessions, so commit these two paths explicitly when you choose to.

## 6. What did **not** change

- **The chain.** Same Besu 26.10 QBFT sealer, same genesis, same validator set. No config was
  touched on the EC2 instance; the only thing that changed there is what the script would do
  the next time it runs.
- **The published UI.** Nothing was pushed to the host's web directories *by the ruling itself*.
  Verifying that sentence is what surfaced §8 — a live routing defect that predates the ruling — and
  §8 records the publish that followed, once it was authorised.
- **The 724 wrapper (`0xC0CF6B0E…`) and the 724 DEX.** Both still live and still funded. The
  ruling does not retire them; it just stops presenting them as the place a normal holder
  obtains wLXON.
- **No token moved, no transaction was sent, no attestation was signed.** Everything in §4 is
  read-only measurement.

## 7. Caveats on this document

- The "no external users" finding rests on two windows that are shorter than the chain: the
  50-transaction explorer page (28 h) and the fact that only 43 `Transfer` logs exist in all
  of 724's history. The log census is complete for **LXON token holders**; it says nothing
  about accounts holding only XON, only wLXON-724, or only LP shares.
- `scripts/release-verify.sh` cannot currently run its genesis-hash step at all: it shells out
  to `node` requiring `ethers`, and the pnpm store behind `apps/contracts/node_modules/ethers`
  (`../../../node_modules/.pnpm/ethers@6.17.0`) no longer exists, so the symlink is dangling.
  Separately, that step builds an RLP list of only the first 10 header fields — a block-0 hash
  needs the full header including `extraData` — so even with ethers restored it cannot equal
  the live block-0 hash `0x6c931dff…cc588`. Both defects predate this ruling and neither was
  fixed here; the path change in §5 was the minimum needed to avoid adding a *new* failure.
- `lxon-evm-node/besu/make-operator-config.py:12` and `besu/run-besu.sh:30` hardcode
  `/Users/adikamble/lxon/LXON/lxon-evm-node/geth/privatekey.txt` — a lowercase `lxon` path that
  never contained that file. They were already dead before the move; they now point at a path
  that is dead twice over. If either script is still wanted, it should take
  `besu/privatekey.txt`.
- The duplicate validator key still exists, now at
  `~/.lxon/archive/geth-clique-2026-10-31/privatekey.txt`, and the original is still in git
  history. Removing the archive copy is a one-line owner decision; it was left in place because
  deleting the only thing between this machine and a redeploy was not this ruling's call.

## 8. Separate finding, and it is live: `/swap/` is not the page that was published

Found while trying to prove §6's "the UI did not change" claim. It turned out the claim could
not be checked from the URL everyone is given, because that URL does not serve that file.

`explorer.lxon.in` is fronted by the same `lxon-caddy` container as `www.lxon.in`, and the
Caddyfile defines **two independent static roots**:

```
handle_path /swap/*  ->  root * /data/swap     # "Public LXON/WETH swap UI + price JSON"
handle_path /ui/*    ->  root * /data/ui       # "LXON web UI — landing, app view"
```

Measured on the host (sha prefixes are sha256, first 16 hex):

| What | Path | sha / size | mtime | carries |
| --- | --- | --- | --- | --- |
| The URL in the listing docs and every share link | `explorer.lxon.in/swap/` → `/data/swap/index.html` | `eab705fbb606f5f6` / 26,764 B | 2026-10-28 19:19 | wrap selectors fixed (`0xea598cb0` ×1, `0xde0e9a3e` ×1); **no** bridge panel (`encodeClaimTransfer` 0), **no** canonical wLXON (`0x7A3c0C34…` 0), old wrapper address ×2 |
| The 2026-10-30 publish | `/data/ui/swap.html` | `1319fb6f9f41ae76` / 71,633 B | 2026-10-30 12:44 | both of the above: panel, canonical address ×2, `lxon.v41.lock.v1` ×1 |
| Reachable as | `explorer.lxon.in/ui/swap.html` | 200, 71,633 B, `1319fb6f…` | — | this is the only address the good build is served from |

Three consequences, in order of how much they matter:

1. **Users of the advertised link get the pre-panel build.** The work of 2026-10-29/30 — the
   canonical-wLXON identity change and the 724→137 crossing panel — is deployed to a path no
   one is sent to. Anyone following `explorer.lxon.in/swap/` still sees the old wrapper
   presented as the wLXON, which is precisely the confusion this ruling is meant to end.
2. **`/ui/price.json` is a 404.** The cron writes `price.json` into `/data/swap` (mtime
   2026-10-30 21:10, `root:root`), so the feed is only reachable at `/swap/price.json`.
   `/data/ui` has no `price.json` at all. The stale page fetches it as a *relative* path
   (`fetch("price.json", {cache:"no-store"})`), so it resolves correctly on `/swap/` and would
   not on `/ui/`. Any future publish into `/data/ui` must either copy the feed too or switch to
   an absolute `/swap/price.json`.
3. **`www.lxon.in/swap/` is a 308 to `explorer.lxon.in/swap/`** — it does not serve `/data/ui`.
   The `03-www.caddy` comments describe `/ui/` as the shared prefix, but the `/swap/` path is
   not in that site's static matcher, so the www host passes this defect straight through to
   the explorer host.

This was **not** caused by anything in this ruling. It was repaired later the same day, and the
repair turned out to be more involved than a copy: **neither** build was publishable as-is. The
`/data/ui` build used `0x7A3c0C34…` as a chain-724 **swap path leg**, and that address measures
**0 bytes of code on 724** — pair `0x8e90675e…` reports `token0() = 0xC0CF6B0E…`, the wrapper — so
publishing it whole would have made every LXON⇄wLXON swap revert. The local build had fixed that and
instead read the canonical Polygon balance through the 724 wrapper, which measures 0 bytes on 137.
One line was corrected, 31 assertions were run against the served bytes, and both routes now serve
`6d1cfe02d5274541`. Full record, including the two backups and the `enable-ui.sh` gap that let the
routes diverge again: **`docs/runbooks/swap-public-route-2026-10-31.md`**.

Note also that the earlier verification records for 2026-10-30 report "routes 200" for `/swap/`.
That was true of the HTTP status and false of the content: 200 came from the stale
`/data/swap/index.html`, and the assertions that mattered were run against the local file and
against `/ui/swap.html`. A publish check must hash the bytes served at the advertised URL.

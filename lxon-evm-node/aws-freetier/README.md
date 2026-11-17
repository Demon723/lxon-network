# LXON chain 724 — free-tier rebuild kit

Account `044409363656`, region `eu-north-1`, one Graviton micro node. This directory is the
replacement path for `../aws/`, which provisions a `t3.large` with 150 GB and the whole
Blockscout stack — that shape cannot fit a free-tier budget.

## STATUS: live and sealing since 2026-11-03

| | |
|---|---|
| instance | `i-0e2618e0fe9d0cfde` — `t4g.micro`, eu-north-1a, arm64, Ubuntu 24.04 `ami-0335270b14f48b820` |
| EIP | `13.61.55.231` (`eipalloc-0a80f30afbde8fe51`), tagged `Name=lxon-node-eip` |
| security group | `sg-0ba62daf88dae7df6` — 22 from one operator /16 (`49.15.0.0/16` now), 30303, 80 and 443 for the two public fronts, **no** 8545/8546/3000/4000 |
| DNS | `rpc`, `www` and `explorer`.lxon.in all resolve to `13.61.55.231` as of 2026-11-03 (moved off the dead `13.62.37.246`). `lxon.in` itself has **no A record** and is not served. Zone is parked at Hostinger (`byte`/`pixel.dns-parking.com`); the IAM user has no Route 53 permissions, so records are owner-only |
| public RPC | `https://rpc.lxon.in` — TLS issued by Let's Encrypt, 30-method allow-list, writes 403, per-client token bucket, `eth_getLogs` range bound (see "Public fronts") |
| website | `https://www.lxon.in` (landing + `/app`) and `https://explorer.lxon.in` (an honest offline notice, not a 404 and not a TLS error) |
| backup | **first snapshot taken 2026-11-03**: `snap-0ae79628e682755df` of `vol-033fc54ed46e0793a` (20 GB, 5.8 GB used). `ec2:CreateSnapshot` is permitted by the boundary (proved with `--dry-run`); Data Lifecycle Manager automation was **not** verified, so rotation is manual: `./snapshot.sh --rotate 7` |
| key pair | `lxon-eu-north-1`; the pre-existing `~/.ssh/lxon-eu-north-1.pem` (19 Oct) was **preserved**, not overwritten, at `~/.ssh/lxon-eu-north-1.pem.old-20261102T214315Z` |
| AWS credentials | **open exposure.** The access key pasted into a chat transcript (`AKIA…M3RF`) is the key profile `lxon-remote` uses, and `./rotate-aws-key.sh --check` confirms on 2026-11-04 that it still authenticates as `arn:aws:iam::044409363656:user/lxon_developer`. It cannot be rotated from this machine: the user's permissions boundary denies `iam:CreateAccessKey`, `iam:ListAccessKeys`, `iam:ListUsers` and `cloudtrail:LookupEvents`, so rotation and the usage audit are admin-only. See "Rotating the leaked AWS key". |
| consensus | QBFT n=1, validator `0xFaE699d2…`, block period 5 s |
| `verify.sh` | 7 passed / 0 failed — chain-id `0x2d4`, **block 0 `0x6c931dff…` confirmed on the real node**, head `0xb → 0xf`, `-Xmx512m` present, 0 OOM events, RSS 681/904 MB with 25 MB swap, disk 31 % of 19 G |

The block-0 hash matching on live hardware is the point: it is the same value proven offline in
`ProveGenesisLocally.sh`, so this really is chain 724's identity and not a look-alike.

**What this does NOT restore.** The chain restarts from an empty data volume, so everything created
in blocks 1–242,493 is gone: the v4.1 bridge at `0x9B15fEe9…`, the LXON/Wrapped contracts, the DEX
and peg pools, all escrow. Consequences that still hold:

- 31,052 wLXON on Polygon 137 remains backed by nothing. 137's bridge is `configSealed` and pinned
  to peer `0x9B15fEe9…`, which does not exist on this chain, so no crossing can resume against it.
- The Polygon migration window (to 2026-11-26) is still open over a **zero** reserve.
- The public endpoint is read-only. `rpc.lxon.in -> Caddy -> rpc-gateway.py -> Besu` serves a
  30-method allow-list; writes, `admin_`, `qbft_`, `debug_`, `personal_` and anything unlisted are
  refused with 403 before Besu is contacted. **`eth_sendRawTransaction` is not reachable**, which
  reverses the old runbooks' claim that a public broadcast path existed. Anything designed against
  one needs an explicit decision. See "Public fronts" below.
- There is **no block explorer on this host.** `explorer.lxon.in` answers with a page saying so. The
  explorer is a database plus several application containers and does not fit a `t4g.micro`, so the
  landing page's explorer-derived figures render as "not read" and its explorer links lead to that
  notice.

Operator access note: the egress IP was seen at `42.108.237.11` and then `49.15.91.16` inside one
session, i.e. across different provider blocks, so a fixed `SSH_CIDR` will go stale mid-work. The
first launch did exactly that — the node came up healthy and `deploy.sh` timed out on SSH. If SSH
stops working, re-check `preflight.sh`'s egress line and add the current /16; the two stale rules
found this way were revoked on 2026-11-03.

Both `us-east-1` instances (`i-09ea5a833cbf52360`, `i-0c0426d9265615719`) are terminated, with no
orphaned volumes or snapshots left behind in that region.

## Where we actually are

The old node (`i-0be453b2850bd6eae`, EIP `13.62.37.246`, account 404268099234) is unreachable on
22/80/443/8545 and the migration bundle taken at `2026-11-02T00:25Z` says in terms:

```
"with_db": false,  "bundle_contains": "config + served UI bytes"
skipped:  besu-data 379 MB · besu-rpc-data 378 MB · bs-db-data 469 MB
```

So 242,493 blocks of chain state, the 31,152 LXON of bridge escrow, the 30,000 LXON validator
stake, the LXONWrapper's 30,000 LXON collateral and the DEX/peg pools are **not in the bundle and
not on this laptop** (local `besu/data` is 1 MB; `besu/testnet` is chain 725; the 2026-10-28 public
export is scripts only).

What *did* survive, and what this kit uses:

| thing | status | source |
|---|---|---|
| production genesis | **intact**, `sha256 a779acef…ca20` matches the bundle manifest | `genesis/genesis.qbft.json` (copied out of `config.tar.gz`) |
| block-0 hash | known: `0x6c931dff…cc588` | bundle `MANIFEST.json` + `inventory.txt` |
| chain identity | chainId 724, QBFT **n=1**, single validator `0xFaE699d2…`, timestamp `0x655c0000` | the genesis itself |
| genesis alloc | one account: `0xFaE699d2…`, no contract code | so nothing user-facing was genesis-seeded |
| validator key | on this laptop at `../besu/privatekey.txt` (0600), never in this dir | delivered by `../aws/push-secrets.sh` |
| contracts | **gone.** Every 724 address must be redeployed from `apps/contracts` — and a redeploy lands at *new* addresses, so 137's sealed lane has to be re-pointed through its 48 h timelock first. See `docs/runbooks/redeploy-724-what-it-costs-the-bridge.md`; the sequenced version with the generated batch payloads and a green fork rehearsal is `docs/runbooks/repoint-137-to-rebuilt-724-plan.md` | history is unrecoverable; the only funded 724 sender is the live validator key |

Restarting with this genesis reproduces block 0 exactly. It does **not** restore the chain: from
block 1 onward this is a new history, and `0xFaE699d2…` starts at nonce 0, so every contract lands
at a different address than the one the docs list.

## The one consequence to sit with

Polygon 137 is public and permanent, and its v4.1 bridge is `configSealed = true` with its 724 peer
pinned to `0x9B15fEe9…`. A rebuilt 724 cannot present that address or those old block hashes, so
**the 31,052 wLXON live on 137 can never be re-backed or redeemed by this node.** If you want the
wLXON story to continue on Polygon, it is a *new* bridge + *new* token with a fresh supply decision —
not a recovery. Say which one you want and I will plan it; nothing in this kit depends on that answer.

## Free tier is now a credit plan, not 750 hours

Accounts opened after 2025-07-15 (this one) get **$100 of credit immediately, up to $200 total** by
completing onboarding tasks, and **the account closes 6 months after opening** or when credits run
out, whichever comes first. There is no perpetual t2/t3 micro allowance to lean on.

Measured prices (`eu-north-1`, on-demand, from Vantage on 2026-11-02) and what one always-on node costs:

| line | rate | per month (730 h) |
|---|---|---|
| `t4g.micro` — 2 vCPU, 1 GiB, free-tier eligible | $0.0089/h | $6.50 |
| `t4g.small` — 2 vCPU, 2 GiB | $0.0178/h | $13.00 |
| public IPv4 (applies to an EIP on a running instance, no double charge) | $0.005/h | $3.65 |
| 20 GB gp3 root, encrypted | ~$0.075/GB-mo * | ~$1.50 |
| **one micro node, all in** | | **≈ $11.7/mo ≈ $70 over 6 months** |

\* EBS per-GB rate is an estimate — confirm in Cost Explorer before trusting the total. The instance
and IPv4 numbers are sourced; the EBS line is the one I did not verify.

That fits inside the first $100 tranche with room for a couple of test spikes, which is why the
default is `t4g.micro`. Two nodes would be ≈$23/mo and burn the whole plan; an always-on Blockscout
instance on top of that is not free-tier-shaped.

## Run order

**Decision (owner, 2026-11-03): deploy with the RECOVERED PRODUCTION genesis.** That is
`genesis/genesis.qbft.json`, sha256 `a779acef…`, validator `0xFaE699d2…`, block 0 `0x6c931dff…`.
No rotation first — so the run order is the plain one below, with no `GENESIS_FILE` and no
`EXPECTED_BLOCK0` override. Rotation remains available later (next section) but is not part of
this deploy.

Proven locally before any credit is spent (`./ProveGenesisLocally.sh`, 2026-11-03): the recovered
genesis boots `hyperledger/besu:26.10.0` on arm64 and block 0 comes back
`0x6c931dffbac6d832d33efb81d31880391cb637eed456cc838bf9689595ecc588` — identical to the value the
lost live node reported in the migration manifest — with chainId `0x2d4`, gasLimit `0x1c9c380`,
timestamp `0x655c0000`, stateRoot `0xca659fd5…`. A negative control with a wrong expected hash
fails and exits 1, so the gate can actually fail. Block 0's `miner` is the zero address: no sealer
produces a genesis block, and the header hash already covers every field.

```
cd lxon-evm-node/aws-freetier
./ProveGenesisLocally.sh            # local docker; no AWS, no credits, no key material
./ProveSealingLocally.sh            # local docker; uses the sealer key, proves blocks advance
./preflight.sh                      # read-only; hard-gates on account id + genesis checksum
./deploy.sh                         # first AWS write: provisions and starts Besu (no key yet)
cd ../aws && ./push-secrets.sh      # delivers the QBFT validator key; sealing begins
cd ../aws-freetier && ./verify.sh   # block 0 == 0x6c931dff…, head advancing, no OOM events

# then, once the hostnames resolve here (all re-runnable, each measures DNS as it goes):
./test-rpc-gateway-limits.py        # 38 control checks on the gateway; no AWS, no docker
./expose-rpc.sh                     # read-only RPC front + its systemd unit
./expose-www.sh                     # the site, and the explorer offline notice
./expose-rpc.sh --revoke            # take either front back down independently
```

### Proven locally 2026-11-03, arm64, `hyperledger/besu:26.10.0`

The same image and architecture the AWS node uses. Everything except the AWS calls themselves has
now actually run.

| what was proved | measured result |
|---|---|
| genesis boots Besu and yields the recorded block 0 | `0x6c931dff…ecc588`, chainId `0x2d4`, gasLimit `0x1c9c380`, timestamp `0x655c0000`, stateRoot `0xca659fd5…` |
| `ProveGenesisLocally.sh` can fail | wrong expected hash → FAIL, exit 1 |
| **the local key IS the genesis validator** | `besu/privatekey.txt` (65 B, `0600`, gitignored at `.gitignore:66`, never committed) derives `0xfae699d2848957c7c3be67d8c90f0e456419cada` via @noble, control vector privkey=1 → `0x7E5F4552…` OK |
| **that key seals this genesis** | head 1 → 5 in 20 s (+4 blocks at `blockperiodseconds: 5`), block 1 `miner` == the validator, `net_peerCount` `0x0` |
| `ProveSealingLocally.sh` can fail | `SEALER_KEY=validator-1.hex` → block 0 still matches, head stays **0 → 0**, exit 1. Empty key → refused before docker starts, exit 1 |
| `deploy.sh`'s exact `docker compose pull && up -d` | `besu-perms` exits 0 (`besu-data ownership set for uid 1000`), `besu-sealer` starts and *waits* for the key instead of crashing |
| `push-secrets.sh`'s in-place overwrite through a bind mount | inode **48966240 → 48966240** preserved, RPC up 14 s later, head 0 → 4, `Produced #1..#4` in the QBFT log |

The negative control on row 5 is the reason these scripts exist: a **matching genesis sha256
cannot tell you the node will seal.** With the wrong key, block 0 is byte-identical and the node
looks healthy — it just never produces block 1, while the instance bills. `deploy.sh` only ever
checked the sha256.

Two of my own assertion bugs were caught building these and are fixed: `cast rpc` returns the
JSON-encoded `"0x2d4"` with quotes, so a raw compare fails on a healthy node; and a QBFT genesis
block's `miner` is the zero address (no sealer produces it), not the validator. A fixed host port
also made back-to-back runs fail — the teardown removes the container but `docker-proxy` holds the
port briefly, so the next run's own stale-listener guard fired on a listener already going away.
Both scripts now take an ephemeral port.

Neither local proof leaves anything behind: containers, the named volume that held a sealed chain,
and the throwaway data dirs are all removed on exit, and the source key file is untouched. State
lives under `~/.lxon/runs/`, never `/tmp` — a startup sweep deletes `/tmp/lxon-*` and has already
eaten a live run directory once. `ProveSealingLocally.sh` is isolated by measurement, not
assumption: no bootnodes in the genesis, the old chain-724 network is gone, and it asserts
`net_peerCount == 0x0` before proceeding.

`deploy.sh` refuses to run if the credentials resolve to any account other than `044409363656`, or
if the genesis hash is not the recovered production one. Both gates are checked before the first
`create-key-pair`.

`ProveGenesisLocally.sh` needs a docker daemon and ~907 MB of image (already cached here). It uses
no key material at all: Besu generates its own throwaway p2p node key, and the chain never seals
because that key is not the genesis validator. It takes an ephemeral host port by default; set
`HOST_PORT=` only if you need a fixed one. Throwaway chain data is deleted on exit (`KEEP_WORK=1`
to keep it) — this disk runs near full.

## Public fronts (`expose-rpc.sh`, `expose-www.sh`)

Three hostnames, one Caddy, two owners of that file. Each front installs **its own fragment** into
`/etc/caddy/sites-enabled/` from `caddy-sites/`, plus a shared `Caddyfile.master` that imports them.
The first `expose-rpc.sh` wrote the whole Caddyfile from one template, so the moment a second site
existed, publishing it would have silently deleted `rpc.lxon.in`. `install-caddy-sites.sh` refuses
unless exactly one fragment owns the `:80` catch-all (`catchall.caddy`), and `expose-www.sh` asserts
afterwards that the RPC front still answers — the regression the redesign exists to prevent.

| name | what it is | how it is chosen |
|---|---|---|
| `https://rpc.lxon.in` | Caddy → `rpc-gateway.py` on `127.0.0.1:9545` → Besu on `127.0.0.1:8545` | `expose-rpc.sh` |
| `https://www.lxon.in` | the landing page at `/`, the app at `/app`, an offline notice at `/swap` | `expose-www.sh` |
| `https://explorer.lxon.in` | the offline notice, with `/assets/*` still served so it renders | `expose-www.sh` |

Both scripts **measure the A record on every run** and install the TLS fragment when the name
resolves to this instance and the plain-HTTP one when it does not. Nothing remembers the mode, which
is the failure mode that matters: a note saying "DNS still points at the old EIP" rots silently the
moment the owner moves it, and a rehearsal comparing live state to a remembered value can no longer
fail. The first run of `expose-rpc.sh` on 2026-11-03 correctly switched to TLS mid-session without
being told DNS had moved.

The gateway is an **allow-list** (30 methods), not a deny-list, and it now has three gates:

- **what**: unlisted or named-forbidden methods → 403 before Besu is contacted; a batch containing
  one blocked element is refused whole, so a blocked call cannot ride inside a permitted batch.
- **how much**: a per-client token bucket (burst 60, 8/s sustained) charged only on the forwarded
  path, so flooding refused methods cannot spend a budget. Concurrency alone was not a limit — one
  client could hold all 16 slots indefinitely on a box whose only job is producing blocks.
- **how wide**: `eth_getLogs` is the one allow-listed method whose cost the caller chooses, so its
  block span is bounded to 5,000 against the **real head** (`eth_blockNumber`, cached 5 s). If the
  head cannot be read the request is refused rather than waved through. An absent `toBlock` defaults
  to `latest`, so `{"fromBlock":"0x0"}` alone is caught; both absent is a one-block read and is
  correctly served.

### Measured on the live node, 2026-11-03

| check | result |
|---|---|
| read through the front | `eth_chainId` `0x2d4`; head advanced `0x354 → 0x357` in 12 s and `0x581 → 0x582` in 7 s (5 s blocks) |
| client behind it | `besu/v26.10.0/linux-aarch_64/openjdk-java-25`; block `0x357` `mixHash` decodes to `…tical byzantine tolerance` — the QBFT seal |
| TLS | Let's Encrypt issued for both names: `issuer=…/O=Let's Encrypt/CN=YE2`, `subject=CN=rpc.lxon.in`; `/var/lib/caddy/…/acme-v02…/` holds `rpc.lxon.in` **and** `www.lxon.in` |
| writes refused | `eth_sendRawTransaction`, `personal_newAccount`, `admin_peers`, `qbft_proposeValidatorVote`, `debug_traceTransaction`, `eth_subscribe` → 403; unlisted `personal_importRawKey` → 403 (default-deny, not just the named list) |
| range bound, both directions | 1M-block `eth_getLogs` → 400; a 100-block range → 200 (so the cap is not simply blocking the method) |
| per-IP limit, live | 80 parallel reads from one IP → **9×429**; `lxon-besu-sealer` stayed `Up (healthy)`, 0 OOM, 251 MB swap; the chain kept sealing |
| Besu still private | `nc 8545` from outside → closed; `ss` on the box: 8545, 8546 and 9545 bound to `127.0.0.1` only |
| hostname isolation | unmatched Host → 404 for the RPC, and the site is not served to it either |
| **browser path** | `OPTIONS https://rpc.lxon.in/` → 204 with `Allow-Origin *`; then the page's own `eth_getBlockByNumber` reads **block 1,392** in Chrome. Before the fix the preflight was 501 and every figure said "not read" |
| published bytes | all 11 site files (`find /opt/lxon/www -type f` = 11, zero `._*` sidecars) sha256-identical between the build dir and what the node serves; `/swap.html`, `/ui/swap.html`, `/swap/swap.html` all 404 |
| boot resilience | gateway unit `enabled`, `DynamicUser`, `ProtectSystem=strict`, `MemoryMax=160M`, `RestrictAddressFamilies` |
| offline notice | `explorer.lxon.in/` → 200 with the notice, not a TLS alert and not a 404 (the name resolves here whether or not an explorer does) |

Bugs found building this, in the order they bit:

1. **A heredoc nested inside a single-quoted `ssh` argument silently did not run.** The systemd unit
   write was lost, so nothing listened on 9545, Caddy's health-checked upstream was down and 443
   never bound — while the script printed "Front deployed… installed and running". Verification was
   decorative text with no effect on the exit code. Everything now arrives by `scp` under fixed names
   and a remote script's status decides the outcome.
2. **Verification that cannot fail.** The first `eth_getLogs` check asked for `0x0..latest` against a
   5,000-block cap on a ~1,200-block chain — it could only ever pass. Replaced with a 1M-block range
   (refused) *and* a 100-block range (served), which is chain-length independent and tests both
   directions.
3. **Forwarding the caller's `Host` upstream.** Besu enforces `--host-allowlist` (default
   `localhost`) as a DNS-rebinding guard, so every public request got
   `403 {"message":"Host not authorized."}` **from Besu**, while all loopback tests passed because
   *their* Host was a localhost one. The proxy path with the public hostname is now a check.
4. **A helper that echoed into its own return value.** `fl_mode_for` printed commentary to stdout, so
   `DNS_MODE=$(fl_mode_for …)` captured the whole message and built a filename like
   `rpc.==> DNS: …\nhttps.caddy`. Commentary now goes to stderr and the mode is the only thing on
   stdout, control-tested against a deliberately non-matching EIP.
5. **My own `:80` invariant was wrong for TLS mode.** The catch-all lived inside `rpc.http.caddy`, so
   installing the TLS front left zero claimers and the install aborted. Catch-all moved to
   `catchall.caddy`, installed with every front in both modes.
6. **macOS `tar` leaked AppleDouble sidecars.** The first site publish put nine `._index.html`-style
   163-byte files in a public web root, which then resolved as real URLs. `COPYFILE_DISABLE=1` plus
   excludes and a remote `find -name '._*' -delete`.
7. **A 404 that was really a permission problem.** `fl_publish_dir` left the tree `drwx------ ubuntu`,
   and Caddy serves as the `caddy` user, so every path returned 404 with a perfectly valid
   certificate. The publish step now sets `root:root` `0755`/`0644` and reports the file count.
8. **A `# comment` inside a double-quoted `ssh` string swallowed the next command.** With trailing
   backslashes, line continuation is joined *before* parsing, so `# … \` turned `chown; chmod` into
   part of a comment — a silent no-op that still reported success. No prose inside remote command
   strings.
9. **The check that passes for the wrong reason.** "unmatched Host must 404" was sending `http://` to
   port 443 and accepting Caddy's `Client sent an HTTP request to an HTTPS server` as the expected
   rejection. Same for the loopback TLS probe, which sent SNI `127.0.0.1` and reported an SSL alert
   as a gateway failure. Both now use `--resolve` so scheme, port and SNI agree.
10. **The one that would have shipped a silently useless site: no `OPTIONS` handler.** Every curl
    check passed while a browser got 501 on the preflight and the landing page's RPC figures rendered
    as "not read". Fixed and verified in a real browser, not by inference.
11. **Loading states that could never settle -- found by counting attributes, not reading text.** This
    file used to claim "the pages already label any figure they cannot read as *not read*, and that
    behaviour is relied on, not rewritten." It was false, and nothing in the pages looked wrong: each
    affected read sat *after an early `return`* in the same function, so whenever the explorer failed --
    which is every visit since the restart -- the later cells kept `data-read="wait"` forever. Measured
    on the published site: **7 stuck cells on `/app`, 6 on `/`** ("reading chain stats…", "Gas used —",
    "Txns in tip —", four chain-stats slots, the pool reserves). Now `/` reads gas and tip tx count from
    the RPC tip that `tick()` already holds, `loadChainStats()` is its own function so a dead tx list
    cannot suppress it, and the pool cells get terminal states on the early return. Verified with
    `~/.lxon/runs/www-stats-probe/server.py` in three modes (real explorer failing / stub answering /
    stub answering only stats) and re-checked against `https://www.lxon.in` after publishing: **0 visible
    stuck cells on either page**, and the stub numbers (987,654 / 1,234,567 / 77 / 4,242) render exactly
    when a working explorer is simulated -- so this is not an always-fail label. The one remaining
    `wait` is a placeholder inside the `hidden` sign-in dialog and settles when it is opened.

Still true and deliberately not hidden: the gateway has no *fairness* guarantee across a long window
(burst then sustain, not a per-minute quota), the site publishes no `price.json` so the USD feed reads
"unavailable" on both pages, and the Google sign-in shows "not configured" because `lxon-auth.json`
ships an empty client ID — that needs a real OAuth origin, which is yours.

## Backup, and what it is worth

`./snapshot.sh` takes a tagged snapshot of the root volume and waits for `completed` rather than
reporting a pending one as a backup; `--rotate N` deletes only `lxon-724`-described snapshots beyond
the newest N and refuses any a volume was built from. The first one is `snap-0ae79628e682755df`.
A snapshot is a block image, not a logical dump: it restores the box including a corrupt leveldb or an
already-overwritten key file, so the durable-copy answer is still an offline export plus a separate
copy of the validator key. Cost is billed on changed blocks (~$0.09/GB-month in eu-north-1), not on the
nominal 20 GB.

## What the published documents now assert wrongly

`docs/724-claim-ledger-2026-11-03.md`, produced by `./audit-724-claims.py` and corrected 2026-11-04 by
the re-measurement in `./annotate-dead-724-docs.py`. Of the 13 full addresses quoted by the docs,
**9 are documentation defects** -- a document presents them as chain-724 contracts and 724 answers
0 bytes of code, with the 137 controls non-empty in the same read. That includes the chain's own token
`0x99801a78…`, and it includes `0xc0177883…` / `0x86a7da57…`, which the first pass excused because the
same hex has code on 137; on 137 they are not even tokens (`name`, `symbol`, `decimals` and
`totalSupply` all revert), so they were never the LXON and WETH the guides say they are. 2 are wallets,
1 is the legacy Polygon wLXON, and 1 is the founder account, whose 23 bytes turned out to be an
EIP-7702 delegation designator pointing at `0xC50b038D…` -- a delegated EOA, not a half-dead contract.

**Done:** 66 of the 67 markdown files that quote one of the nine now carry a dated notice, inserted
between markers by `./annotate-dead-724-docs.py`, naming the addresses in that file and the control
reads that make the claim checkable. The script measures before it writes and refuses if a control is
empty -- it refused for real on this run when `polygon.drpc.org` stalled mid-read. Re-running it is a
no-op. `docs/724-claim-ledger-2026-11-03.md` is excluded because it quotes the addresses as its
subject.

**Not done, deliberately:** the other **228** files that quote the same literals -- 128 `.ts`/`.js`,
53 `.json` (38 of them foundry `broadcast/` run records), 15 `.sh`, 13 `.sol`, 19 in
`.html`/`.txt`/`.csv`/`.py`/backups. Reproduce the split with `./annotate-dead-724-docs.py --census`.
Commenting those out changes what a script deploys, and there is nothing on 724 to point them at until
the contracts are redeployed -- they are a redeploy inventory, not a typo list. The `broadcast/` records
are the only surviving proof that those deploys ever happened, so rewriting them would cost evidence.
Two deserve a decision before anyone runs them:
`deploy/complete-cross-chain-transfer.sh:11` (`TOKEN_ADDRESS` = a 0-code address, with a wrong
"6 decimals" comment) and the token lists `apps/contracts/lxon.tokenlist.json` /
`docs/listing/lxon-token-list.json`, which must not be submitted to any listing service as they stand.

**Update 2026-11-04:** that decision is now a tool, not a paragraph. `./check-dead-724-addr.py`
re-measures the dead set against chain 724 (refusing to answer if its 137 control or the genesis hash
fail), classifies every non-markdown file that still names one, and `--strict` gates anything
publishable. It found that the "must not be submitted" pile was seven files, not two — including three
CoinMarketCap description drafts and a second token list under `lxon-evm-node/aws/ui/`. All seven now
carry a dated withdrawal banner that states the measurement; none was rewritten into a submittable
state, because the replacement figures cannot exist until the redeploy produces them. Full triage and
the classifier bugs that hid them: `docs/724-dead-address-triage-2026-11-04.md`.

The 137 side of the same question -- the mint path is still open, `pause()` is a single
directly-authorized transaction, and what the revert strings prove -- is in
`docs/runbooks/pause-137-bridge-mint-path.md`.

## Rotating the leaked AWS key (`rotate-aws-key.sh`)

An AWS access key and secret were pasted into a chat transcript during this work
(`access key ID ending M3RF (full ID kept in `~/.lxon/secrets/aws-leaked-access-key-id`, deliberately not in this repo)`, account `044409363656`, IAM user `lxon_developer`). Measured with
`./rotate-aws-key.sh --check` on 2026-11-04:

- the leaked pair is **live** — it is what profile `lxon-remote` authenticates with, i.e. what
  `deploy.sh`, `expose-rpc.sh`, `expose-www.sh` and `snapshot.sh` use;
- the same identity **cannot rotate itself**: its permissions boundary denies `iam:CreateAccessKey`,
  `iam:ListAccessKeys`, `iam:ListUsers` and `cloudtrail:LookupEvents`. The `ec2:DescribeInstances`
  control in that report answers, so the denials are real and not a broken probe — an earlier draft of
  the report claimed "ANSWERED" for all three because it grepped a lowercase phrase the CLI never
  prints;
- it is **not** in the repository: no working-tree match, and `git log --all -S` finds zero commits
  (control: the same scan finds the `deploy-amm-gce.sh` key that was removed in `1facec8`). The leak is
  the transcript, not the tree;
- `scripts/check-secrets.sh` prints clean, but it scans HEAD + disk only, so it was never going to see
  history — use the `--refs` / `--history` modes it names before believing a "clean".

**What only you can do**, from an admin identity in `044409363656` (console path: IAM → Users →
`lxon_developer` → Security credentials):

```bash
./rotate-aws-key.sh --selftest                       # proves the guards can fail; no AWS calls
ADMIN_AWS_PROFILE=<your-admin> ./rotate-aws-key.sh --phase create
./expose-www.sh --check                              # run the kit on the new key
ADMIN_AWS_PROFILE=<your-admin> ./rotate-aws-key.sh --phase finish          # deactivate + verify
ADMIN_AWS_PROFILE=<your-admin> ./rotate-aws-key.sh --phase finish --confirm # delete, when nothing complains
```

The script never prints the new secret and never passes it through argv — it streams it from the
`CreateAccessKey` response straight into `[lxon-remote]` in `~/.aws/credentials`, leaves every other
profile and key untouched, verifies the new pair with `sts` and a read-only EC2 call before touching
anything, backs the credentials file up mode `0600`, deletes the response file, and stops between
*deactivate* and *delete* so a forgotten cron or another session fails loudly while
`update-access-key --status Active` can still undo it. `--phase finish` re-reads the key list rather
than trusting a remembered value, and asserts the old pair is actually refused by STS before it will
delete anything.

Then do the audit that was denied here: CloudTrail event history filtered by that access key id, for
the whole window since it was pasted. Look for API calls from IP addresses that are not yours. If the
key ever had broader rights than this boundary shows, treat the account as needing more than rotation.

## Deliberate differences from ../aws/deploy.sh

- `t4g.micro` + arm64 AMI, and the Compose plugin URL is derived from `uname -m`. The old
  `user-data.sh` hardcodes `docker-compose-linux-x86_64`, which installs "successfully" on
  Graviton and then fails every `docker compose` call with exec format error.
- 20 GB gp3 root, encrypted, `DeleteOnTermination=false`. The database is the thing we just lost;
  an accidental terminate should not also delete the volume.
- 2 GiB swap + `vm.swappiness=10`, `JAVA_OPTS=-Xmx512m`, container `mem_limit: 896m`. Besu's JVM
  default sizing on a 1 GiB host gets you the OOM killer instead of a chain.
- RPC API set trimmed to `ETH,NET,WEB3,TXPOOL` (Blockscout was the reason DEBUG and TRACE were on).
  Still loopback-only, still no SG rule for 8545/8546: with QBFT n=1/f=0 an exposed QBFT/ADMIN API
  is a chain takeover.
- No Blockscout and no sc-verifier: the stack those belong to is the `t3.large` shape this directory
  replaces. Caddy, in contrast, is now installed as a **system package** and serves the two fronts
  above from `/etc/caddy/sites-enabled/` — not as a container with bind-mounted config, which is the
  arrangement that hid the old node's broken `import /etc/caddy/sites-enabled/*.caddy` for a day.

## Rotating the sealer identity (the key ceremony)

If the new chain should NOT be sealed by `0xFaE699d2…` — the key that is simultaneously deployer,
bridge admin and the signer of the 2026-10-29 unbacked 10,000 wLXON mint — these three scripts do
it. The key is generated **on the instance** and never leaves it in any form; the ceremony returns
the public point and derives the validator address locally.

```
./NewSealerKeyOnInstance.sh <EIP>       # generates on the box, prints the new validator address
./RotateSealerGenesis.sh <that address> # rebuilds extraData, prints the NEW block-0 hash
GENESIS_FILE=<genesis.sealer-*.json> EXPECTED_BLOCK0=<new hash> ./deploy.sh
EXPECTED_BLOCK0=<new hash> ./verify.sh
./BackupSealerKeySecurely.sh <EIP>      # encrypts on the box; only ciphertext comes down
./BackupSealerKeySecurely.sh --show     # the raw commands, to run by hand instead
```

`EXPECTED_BLOCK0` is required on **both** the deploy and verify lines: deploy.sh refuses a rotated
genesis without it (exit 1) because verify.sh cannot otherwise tell a rotated chain from a broken
one. `GENESIS=` is accepted as an alias for `GENESIS_FILE=`; setting both to different values is a
hard error rather than a silent pick.

Rehearsed 2026-11-02 on throwaway keys, without an instance (the scripts are the same ones):

| check | result |
|---|---|
| key file shape | 65 bytes = 64 hex + newline, mode 0600 — matches the live production file's format |
| address from the public point (@noble keccak) vs from the private file (Foundry) | **agree** (`0x5ad445ec…`) |
| PEM in `/tmp/lxon-keygen` after run | gone (shred, with a python overwrite+unlink fallback because macOS has no `shred`) |
| re-running against an existing key | refuses, exit 1 |
| malformed public point | refuses, exit 2 |
| extraData rebuilder idempotence | caught a real bug — it originally dropped the `0x94` length byte and produced 58 bytes instead of 60 |
| header encoder | reproduces **Polygon block 0 as its own RPC reports it** and `0x6c931dff…` as the 724 node reported it |

Also worth recording: my recalled `keccak256("")` constant was wrong (`…a456`; the real value ends
`…a470`), and `cast keccak 0x` hashes the empty string rather than erroring. Two independent
implementations (noble + cast) were compared before any of this was believed.

## Not decided here, and it needs you

1. **Rotate the consensus identity? — DECIDED 2026-11-03: no, keep the recovered production
   genesis.** The chain restarts under validator `0xFaE699d2…` with block 0 `0x6c931dff…`, so it
   shares an identity with the chain the docs and runbooks quote. Recorded here because the
   opposite choice would have silently produced a different block 0 and invalidated every quoted
   hash. The trade-off that was accepted: `0xFaE699d2…` is simultaneously deployer, bridge admin
   and the signer of the 2026-10-29 unbacked 10,000 wLXON mint, so the consensus identity carries
   that history. Rotation stays available later via the three-command ceremony above — it needs a
   running instance to generate the key on, so it could never have come first anyway. Nothing on
   Polygon 137 can reach either variant: that lane is sealed against `0x9B15fEe9…`, which no longer
   exists.
2. **Explorer or not — PARTLY ANSWERED 2026-11-03.** Blockscout needs ~2-3 GiB, so it does not fit a
   `t4g.micro`. The free-tier-shaped alternative was built: a read-only JSON-RPC plus a status page,
   and `explorer.lxon.in` serves a notice saying what is and is not true rather than a 404 or a TLS
   error. Deciding to bring the explorer back is a **size decision with a price attached** — it means
   `t4g.small`+ and it breaks the free-tier plan this node was built to fit.
3. **DNS — DONE 2026-11-03.** `rpc`, `www` and `explorer` now resolve to `13.61.55.231` and
   Let's Encrypt issued real certificates for both served names. `lxon.in` (apex) has no A record and
   is not served; add it only if you also want a redirect, which needs a record first.

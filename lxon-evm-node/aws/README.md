# LXON Single-EC2 Deployment

Deploys the LXON stack (**Hyperledger Besu QBFT sealer** + Blockscout) to one
EC2 instance in `eu-north-1` using the AWS CLI — no CloudFormation (the deployer
IAM user lacks CFN/SSM/SecretsManager permissions; EC2 API only).

### Why Besu and not Geth

Geth cannot run this chain at a usable EVM level, and that is structural, not a
config mistake:

- `params/config.go` `Rules()` computes `IsShanghai: isMerge && IsShanghai(...)`
  (same for Cancun/Prague). A pre-merge chain therefore never gets PUSH0, no
  matter what `shanghaiTime` says in the genesis.
- Marking the chain merged (`terminalTotalDifficulty: 0`) flips geth into
  "Chain post-merge, sync via beacon client" and it stops sealing outright
  unless a consensus-layer client drives it over the engine API.
- Even then Clique cannot reach Cancun: the miner panics with
  `unexpected excess blob gas value in clique`. That guard is still present in
  v1.13.15, v1.14.13, v1.15.11 and v1.16.5, and >= v1.16 drops `--mine` anyway.
- Besu refuses Clique sealing too ("Clique Block Production (mining) is no
  longer supported"), which is why the answer is **Besu + QBFT**, not Besu + Clique.

Net effect: geth + self-sealing Clique is hard-capped at the London EVM, which
cannot run solc 0.8.26 output (PUSH0) or OpenZeppelin 5.7 (mcopy). Besu QBFT
seals solo at Cancun; PUSH0, MCOPY, TSTORE and TLOAD have each been executed
on-chain here and verified.

## Layout

| File | Purpose |
|------|---------|
| `deploy.sh` | Provisions key pair, security group, Elastic IP, instance; pushes config; starts stack |
| `push-secrets.sh` | Delivers the QBFT validator key (required before Besu seals) |
| `teardown.sh` | Destroys everything `deploy.sh` created |
| `user-data.sh` | Instance bootstrap: installs Docker Engine + Compose plugin |
| `docker-compose.aws.yml` | The remote compose file (gets copied to the instance as `docker-compose.yml`): Besu sealer + Blockscout (db/redis/backend/frontend) + `sc-verifier` |
| `docker-compose.https.yml` | Overlay that adds Caddy on 443/80 and moves 3000/4000 to loopback. Applied by `enable-https.sh`, never on its own |
| `enable-https.sh` | `EXPLORER_DOMAIN=... ./enable-https.sh [--dry-run]` — TLS via Let's Encrypt; refuses to run unless the domain already resolves to the EIP |
| `caddy/Caddyfile` | Explorer site + a top-level `import /etc/caddy/sites-enabled/*.caddy` for optional extra sites |
| `caddy/rpc-site.caddy` | The public JSON-RPC site block; copied into `caddy/sites-enabled/02-rpc.caddy` by `enable-public-rpc.sh` |
| `docker-compose.rpc.yml` | Read-only Besu full node (ETH/NET/WEB3, no validator key, no host port) + `besu-rpc-perms` + the Caddy/backend wiring |
| `enable-public-rpc.sh` | `RPC_DOMAIN=... ./enable-public-rpc.sh [--check|--dry-run]` — starts the node, waits for it to sync, validates the proxy config, then publishes |
| `rpcq.sh` | Runs on the node so a JSON-RPC call can be made from inside the compose network without nesting quotes through ssh |
| `caddy/www-site.caddy` | `www.` → explorer 308 redirect site; `enable-www.sh` copies it to `caddy/sites-enabled/03-www.caddy` |
| `docker-compose.www.yml` | Overlay that mounts that one file into the existing `caddy` service. Applied by `enable-www.sh`, never on its own |
| `enable-www.sh` | `./enable-www.sh [--check|--dry-run]` — gated on DNS, validates the combined config in a throwaway container, then recreates caddy |

## Usage

```bash
./deploy.sh          # provision + configure + start (idempotent-ish; aborts if instance exists)
./push-secrets.sh    # delivers besu/privatekey.txt; waits for the first block + validator set
./teardown.sh        # destroys instance, EIP, SG, key pair
```

Environment knobs: `REGION` (default `eu-north-1`), `INSTANCE_TYPE`
(default `t3.large`), `ROOT_GB` (default 150), `SSH_CIDR` (see warning below).

## Important: SSH_CIDR

Do **not** trust `checkip.amazonaws.com` for the SSH ingress rule. This
network NATs TCP/22 egress through a different address than TCP/443, so the
checkip IP does not match real SSH connections. Observed on 2026-10-19: HTTPS
egress `49.15.90.153`, real SSH source `49.15.86.16` — different /24s, so no
single narrow rule covers both. The security group currently allows `42.104.0.0/16`
(the original ISP range) **and** `49.15.0.0/16`.

To find your real SSH source IP if it changes: temporarily open 22 to the
world, SSH in, `sudo grep 'Accepted publickey' /var/log/auth.log` (or
`journalctl -u ssh -n 6`), then revoke the world rule and add the discovered
/16:

```bash
aws ec2 authorize-security-group-ingress --region eu-north-1 --group-id <sg> \
  --protocol tcp --port 22 --cidr 49.15.0.0/16
aws ec2 revoke-security-group-ingress --region eu-north-1 --group-id <sg> \
  --security-group-rule-ids <the 0.0.0.0/0 rule id>
```

## Endpoints after deploy

- RPC: **not published.** Besu binds `127.0.0.1:8545` inside the container's port map and
  the security group has no rule for 8545/8546. Reach it through a tunnel:

  ```bash
  ssh -i ~/.ssh/lxon-eu-north-1.pem -N -L 8545:127.0.0.1:8545 ubuntu@<EIP> &
  curl -X POST -H 'content-type: application/json' \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' http://127.0.0.1:8545
  ```

  Then point MetaMask/Foundry at `http://127.0.0.1:8545` (chainId 724) while the tunnel is
  up. WS is the same on 8546.
- Blockscout API: `http://<EIP>:4000/api/v2`
- Explorer UI: `http://<EIP>:3000`
- SSH: `ssh -i ~/.ssh/lxon-eu-north-1.pem ubuntu@<EIP>`

The source verifier (`sc-verifier`, port 8050) is deliberately **not** published
on the host and the security group has no rule for it — only the Blockscout
backend reaches it over the docker network.

**That list is the raw-deploy state and is superseded for every hardened name.** Since 2026-10-20
`http://<EIP>:3000` and `:4000` no longer answer at all (loopback-only, world rules revoked) and
since 2026-10-22 the public surface is `https://explorer.lxon.in`, `https://rpc.lxon.in`
(`wss://…/ws`), and `https://www.lxon.in` → 308 → the explorer. Use those sections below.

### Why the RPC is closed (do not re-open it)

QBFT here is a single validator: n=1, f=0, so the quorum for a validator vote is **one
vote**. With the RPC world-reachable and `QBFT` in `--rpc-http-api`, any anonymous client
could POST `qbft_proposeValidatorVote`, the sealer would carry the vote, and the caller
would become a consensus validator able to sign blocks and rewrite state — including
reversing what this project deployed. As of 2026-10-20 the standing API set is
`ETH,NET,WEB3,DEBUG,TXPOOL,TRACE` (`ADMIN`, `QBFT`, `MINER` removed), `--host-allowlist` is
pinned to `localhost,127.0.0.1,besu-sealer`, the wildcard CORS setting is gone, and the two
security-group rules are revoked. Verified: `qbft_*`/`admin_*` answer `Method not enabled`
even through the tunnel, a foreign `Host:` header gets `Host not authorized.`, Blockscout
keeps indexing over `http://besu-sealer:8545`, and ports 8545/8546 time out from the
internet.

To run a validator vote anyway, restart Besu once with the namespace added and keep the
tunnel as the only path in:

```bash
# on the instance, temporary only
cd /opt/lxon && BESU_RPC_API=ETH,NET,WEB3,DEBUG,TXPOOL,TRACE,QBFT docker compose up -d --force-recreate besu-sealer
```

`besu/entrypoint-besu.sh` reads `BESU_RPC_API` and `BESU_RPC_HOST_ALLOWLIST` precisely so
this can be temporary. Remove the override afterwards — the defaults in the script are the
safe set.

If you need a public RPC for real users later, do not re-open the port: Besu 26.10.0
supports `--rpc-http-authentication-enabled` with `--rpc-http-api-method-no-auth=ETH,NET,WEB3`
(RS256 tokens), and Blockscout must keep pointing at the docker-network URL because it
cannot attach a bearer token. TLS needs Caddy/nginx in front; Besu's own
`--rpc-http-tls-enabled` takes a PKCS#12 keystore and cannot do Let's Encrypt.

Note that `JSON_RPC` / `NEXT_PUBLIC_NETWORK_RPC_URL` are intentionally empty in the compose
file: the explorer used to advertise `http://<EIP>:8545` to browsers for wallet reads, and
that endpoint is now closed. Wallet-based reads in the UI are disabled until an
authenticated public endpoint exists.

## Contract source verification

`sc-verifier` is Blockscout's `smart-contract-verifier` microservice; the backend
runs it with `MICROSERVICE_SC_VERIFIER_TYPE=sc_verifier`. Check it is wired up:

```bash
curl -s http://<EIP>:4000/api/v2/smart-contracts/verification/config \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['is_rust_verifier_microservice_enabled'], len(d['solidity_compiler_versions']))"
```

Verify a deployed contract from `apps/contracts` (needs the standard JSON,
because the project builds with `via_ir = true`):

```bash
A=0xbc18d2886ebefee91f6e820114b1d976f1be8330
forge verify-contract --show-standard-json-input $A contracts/LXONBridgeEnhanced.sol:LXONBridgeEnhanced > /tmp/std.json
curl -s -X POST "http://<EIP>:4000/api/v2/smart-contracts/$A/verification/via/standard-input" \
  -F "files[input]=@/tmp/std.json;type=application/json" \
  -F "compiler_version=v0.8.26+commit.8a97fa7a" \
  -F "contract_name=contracts/LXONBridgeEnhanced.sol:LXONBridgeEnhanced" \
  -F "autodetect_constructor_args=false" \
  -F "constructor_args=0x<32-byte-hex-per-arg>" \
  -F "license_type=none"
```

Four things about that request are not obvious and each one fails silently or
with a misleading error:

- The path is `/verification/via/standard-input`, not `via-standard-json-input`
  (the latter is the frontend's label; the v2 router nests `via/<method>`).
- The file field must be `files[input]`. `files[]=` makes Plug build a list,
  `PublishHelper.prepare_files_array/1` only handles maps, and the API replies
  `JSON files not found`. The upload also needs `;type=application/json` — the
  helper selects by content type.
- **`license_type` must be `none`.** Sending `MIT` compiles and matches fine, the
  microservice returns success, and then the publish worker dies with
  `failed to publish: #Ecto.Changeset<action: :insert, …>` — and the useful part
  of that changeset (`errors: [...]`) sits past the logger's truncation point, so
  the log tells you nothing. Confirmed by bisecting the only field that differed
  from a known-good submission: the same `LXONTOTPAuth` standard JSON failed with
  `MIT` and verified within seconds with `none`. The source file's
  `SPDX-License-Identifier` header does not have to agree; it is metadata.
- Constructor arguments come from the creation transaction, not the deploy
  script: take `eth_getTransactionByHash` input and strip the artifact's
  `bytecode.object` prefix; what remains (32-byte words) is `constructor_args`.
  Use `autodetect_constructor_args=false` so Blockscout uses those exact bytes.
  For a multi-arg constructor `cast abi-encode 'constructor(address,string)' …`
  produces the same padding.

Verification is asynchronous — the API answers `Smart-contract verification
started`; poll `/api/v2/smart-contracts/<address>` until `compiler_version` is
non-null. Contracts verified this way are stored with `partially_verified = true`
because the standard-json route compares *deployed* bytecode. The flattened-code
route would set it false, but its controller accepts no `viaIR` flag, so a
via-ir build can never match there; expect the partial badge and ignore it.

If the verifier logs `fetching evm compiler: Permission denied`, the
`sc-compilers` volume lost its uid-1001 ownership (the image runs as `app`,
uid 1001, while a new named volume is root-owned). Re-run
`docker compose up -d --force-recreate sc-verifier` so `sc-verifier-perms`
chowns it again.

## Security model (RPC closed since 2026-10-20)

- SSH: key-only, restricted to `SSH_CIDR` (currently `42.104.0.0/16` + `49.15.0.0/16`).
- Besu RPC/WS: loopback-published, no security-group rule, no wildcard CORS, host
  allowlist pinned, and `ADMIN`/`QBFT`/`MINER` removed from the API set. `DEBUG`/`TRACE`
  stay because Blockscout needs them; they are read-only. See "Why the RPC is closed"
  above for the takeover rationale and the temporary-override procedure.
- Explorer API/UI (4000/3000) and devp2p (30303 tcp+udp) are still open to the world.
  4000/3000 are read-only public by design; with no TLS anyone observing can read chain
  data, and the explorer has no auth, so treat it as a public block explorer. 30303 must
  stay open if a second validator or RPC peer is ever added.
- Besu has no keystore/password here: the QBFT validator signs with
  `--node-private-key-file`, so `/opt/lxon/besu/privatekey.txt` (chmod 600) is
  both the devp2p identity and the signing key. It must stay owned by uid 1000
  (the container user; `ubuntu` on this AMI). No Secrets Manager integration is
  possible (IAM boundary), so anyone with SSH + sudo can read it.
- Fresh `DB_PASSWORD` and `SECRET_KEY_BASE` are generated per deploy into the
  instance's `/opt/lxon/.env`.

## HTTPS for the explorer — LIVE since 2026-10-20 01:22 UTC

`https://explorer.lxon.in` is serving with a Let's Encrypt certificate (issued 2026-10-20, valid
to 2027-01-18, auto-renewed by Caddy). Ports 3000 and 4000 are loopback-only on the instance and
their world rules are revoked, so `http://13.62.37.246:3000` no longer answers. Plain HTTP on port
80 returns 308 to the https origin.

**`lxon.in` is on Hostinger parking nameservers, not Route 53.** Its nameservers are
`byte.dns-parking.com` / `pixel.dns-parking.com`, and the `devin-blockchain-deployer` IAM user has
no `route53:*` permission, so every record below had to be typed into the Hostinger control panel by
a human — nobody can create them from this repo. As of 2026-10-22 three of them are done:

| Host | 2026-10-19 (found) | Now |
|------|--------------------|-----|
| `explorer.lxon.in` | `13.53.138.132` — **not this account**, all ports closed | `13.62.37.246`, live since 2026-10-20 |
| `rpc.lxon.in` | `13.53.138.132` — same orphan | `13.62.37.246`, live since 2026-10-20 — see "Public read-only RPC" |
| `www.lxon.in` | `52.3.226.228` — not in this account (checked eu-north-1, eu-west-1, us-east-1, us-west-2, ap-south-1) | `13.62.37.246`, 308 to the explorer — see "www.lxon.in" |
| `lxon.in` (apex) | no A record | still none — nothing points the apex anywhere |
| `api.lxon.in` | no A record | still none; the API is `/api/v2` on the explorer origin |

What the two orphan IPs were: Amazon-owned addresses *not* attached to any instance in account
404268099234 — a reverse lookup gives the generic
`ec2-13-53-138-132.eu-north-1.compute.amazonaws.com` and 80/3000/4000 all time out. They were
dangling records aimed at a recycled or freed address, not at anything of ours, which means anything
already published with those URLs (chain lists, docs, MetaMask RPC entries) had been pointing
at a dead host.

**Do not repoint `rpc.lxon.in` at `13.62.37.246` yet.** Today Besu listens on `127.0.0.1:8545`
inside the instance and the security group has no 8545/8546 rule, on purpose — see "Why the RPC is
closed" — so an `rpc.` record created now would resolve to a host that refuses the connection,
which is worse than no record because it looks like a working endpoint. The record belongs to the
"Public read-only RPC" step below, which serves it from a separate non-sealing node over 443
rather than from Besu's own port.

To finish it:

```bash
# 1. In the Hostinger panel: A record explorer.lxon.in -> 13.62.37.246, TTL 300.
#    Then confirm it actually moved (a stale answer from your resolver is the usual trap):
dig +short A explorer.lxon.in @1.1.1.1        # must print 13.62.37.246
EXPLORER_DOMAIN=explorer.lxon.in ./enable-https.sh --check

# 2. see what it would do, then do it
EXPLORER_DOMAIN=explorer.lxon.in ./enable-https.sh --dry-run
EXPLORER_DOMAIN=explorer.lxon.in ./enable-https.sh
```

The script opens 80/443, pushes `caddy/Caddyfile` + `docker-compose.https.yml`, starts
Caddy alone, waits for a real certificate, and only then applies the overlay — which is
what moves 3000/4000 to loopback and rewrites the frontend to the https origin — and
finally revokes the 3000/4000 world rules. If ACME fails, nothing else was changed and the
explorer is still reachable the old way; the rollback lines are printed at the end.

Design notes: one origin, path-routed (`/api` and `/socket` to the backend, everything
else to the frontend), so there is no mixed-content or CORS surface. Caddy handles renewal
itself (~60-day cycle against Let's Encrypt). The RPC stays loopback-only — this proxies
the explorer, not Besu; see "Why the RPC is closed".

When linting `caddy/Caddyfile` by hand, export the variable first. Without it `{$EXPLORER_DOMAIN}`
expands to nothing, the site address vanishes, and the Caddyfile adapter reports
`unrecognized global option: encode` at line 16 — a confusing error about a file that is fine:

```bash
docker run --rm -e EXPLORER_DOMAIN=explorer.lxon.in -v "$PWD/caddy:/cfg" caddy:2 \
  caddy validate --config /cfg/Caddyfile --adapter caddyfile   # -> Valid configuration
```

**Domain facts worth knowing before you pick a name** (checked 2026-10-20): `lxon.network`,
which the repo's docs and chain-listing drafts use as `https://lxon.network/rpc`, is not
registered at all — no nameservers — so nothing published to chainlist or MetaMask under
that name works today. `lxon.io` and `lxon.dev` are **someone else's**: both resolve to
54.149.79.189 / 34.216.117.25 on Spaceship DNS. Pointing either at this node would mean
you do not own them, and any doc already citing those URLs is describing a site you do not
control. `lxon.in` is the one domain actually owned here, which is why the table above uses it.

## Public read-only RPC — LIVE since 2026-10-20 18:15 UTC

`https://rpc.lxon.in` (ETH, NET, WEB3 only) and `wss://rpc.lxon.in/ws` are served by the read-only
`besu-rpc` node. Before this, chain 724 had **no working public RPC anywhere**: `chainlist.json` published
`https://www.lxon.in/rpc`, `http://13.51.158.120:8546` and `http://16.170.246.246:8546`; none of
those three addresses is attached to account 404268099234 and every port probe returns nothing,
so the draft would fail at add-time in MetaMask, and the only live RPC was the SSH tunnel. The
draft now lists the working endpoints.

Why not just re-open the sealer's 8545: Besu 26.10.0 has **one** HTTP RPC listener, and
`--rpc-http-authentication-enabled` applies to that listener as a whole with only
`--rpc-http-api-method-no-auth` as a per-namespace escape. Blockscout needs TRACE/DEBUG on it
and cannot attach a bearer JWT, so the sealer's port cannot be simultaneously public-and-safe
and internal-and-complete. Instead a second container faces the internet:

```
internet ──TCP 443──▶ caddy ──▶ besu-rpc (ETH,NET,WEB3, no validator key, no host port)
                                   │ devp2p 30303 over lxon-evm_default
                                   ▼
                        besu-sealer (QBFT, 127.0.0.1:8545 only, unchanged)
```

`docker-compose.rpc.yml` + `caddy/rpc-site.caddy` + `enable-public-rpc.sh`. The node is already
**running and fully synced** on the instance — verified 2026-10-20 00:18 UTC:

```
eth_syncing     false        head 0x45d2 == sealer head 0x45d2
net_peerCount   0x1          eth_chainId 0x2d4
web3_clientVersion  besu/v26.10.0/linux-x86_64/openjdk-java-25
qbft_getValidatorsByBlockNumber / admin_nodeInfo / debug_* / trace_* / txpool_*  ->  Method not enabled
curl -H 'Host: evil.example.com' http://besu-rpc:8545                              ->  rejected
```

Externally it is reachable **only** through Caddy on 443: still no host port, still no 8545/8546
security-group rule, and `13.62.37.246:8545` still times out from the internet. The sealer keeps its
full loopback listener for Blockscout and the tunnel. Verified on the live endpoint:

```
eth_chainId 0x2d4 · eth_blockNumber answers · POST /rpc works (alias) · wss /ws -> 101
qbft_getValidatorsByBlockNumber  Method not enabled   admin_nodeInfo   Method not enabled
debug_traceBlockByNumber         Method not enabled   trace_block      Method not enabled
txpool_content                   Method not enabled   miner_start      Method not found
eth_sendRawTransaction           present (Invalid params for a dummy) -> wallets can send
```

```bash
# 1. Hostinger: rpc.lxon.in  A  13.62.37.246  (TTL 300)
RPC_DOMAIN=rpc.lxon.in ./enable-public-rpc.sh --check
RPC_DOMAIN=rpc.lxon.in ./enable-public-rpc.sh --dry-run
RPC_DOMAIN=rpc.lxon.in ./enable-public-rpc.sh
```

Endpoints it will serve: `https://rpc.lxon.in` (also `/rpc`, which the chain-list draft uses) and
`wss://rpc.lxon.in/ws`. Prerequisites are enforced, not assumed — `enable-https.sh` must have run
first, because this overlay extends the `caddy` service defined by `docker-compose.https.yml` and
compose refuses to resolve the project without `EXPLORER_DOMAIN`.

Three things this design does **not** do, so do not claim them later: there is no rate limiting
(the official `caddy:2` image has no `rate_limit` module — `caddy list-modules | grep -ic
rate_limit` returns 0, so it would need a custom `xcaddy` build); `eth_sendRawTransaction` is on
the ETH namespace, which is what makes wallets work, so spam lands on besu-rpc's 50-peer limit
rather than on the sealer; and one full node is one full node — it is not redundancy, and a
second validator still has to exist before this is a production chain.

Gotchas found while bringing it up, each of which cost a restart loop:

- The image entrypoint is `besu-entry.sh`, which already execs `besu "$@"`. Putting `- besu`
  first in `command:` gives `Unmatched argument at index 0: 'besu'`.
- `besu-rpc-data` is created root-owned by compose, and Besu drops to uid 1000, so it dies with
  `Failed to start Besu: Data directory is not writable: /var/lib/besu` — the same class of bug
  as `besu-perms` and `sc-verifier-perms`. Hence the `besu-rpc-perms` one-shot, which must be
  started explicitly because `up --no-deps` skips `depends_on`.
- `--sync-min-peers` is **ignored in FULL sync-mode** (Besu logs the warning). One peer against
  the sealer is enough; `--poa-discovery-retry-bootnodes=true` is what keeps discovery honest on
  a QBFT chain.
- `docker compose ... up besu-rpc` without `--no-deps` will recreate the sealer if compose
  thinks its config drifted. On a 1-validator chain that is a block-production gap for nothing.
- **Compose merges sequences by appending.** `docker-compose.https.yml` adding
  `ports: ["127.0.0.1:4000:4000"]` on top of a base `ports: ["4000:4000"]` produced BOTH bindings,
  and the recreate died with `failed to bind host port 127.0.0.1:4000/tcp: address already in use`
  with the explorer left in `Created` state — i.e. a real outage, twice, until the overlay used
  `ports: !override`. Maps (`environment`) merge; lists only replace when you say so. Anything that
  re-publishes a port in an overlay needs `!override`.
- **Besu's HTTP-RPC and WS listeners serve only the root path.** `POST http://besu-rpc:8545/rpc`
  answers 404 from Besu itself, so the `/rpc` alias needs Caddy's `handle_path` (strips the
  prefix) rather than `handle` (forwards it). Same for `/ws` -> `besu-rpc:8546`.
- **WebSocket testing needs HTTP/1.1 and an `Origin` header.** Over ALPN-negotiated h2, Besu
  returns 400 for an upgrade it cannot perform; with `--http1.1 -H 'Origin: https://rpc.lxon.in'`
  it returns `101 Switching Protocols`, and curl then appears to "time out" because the socket is
  genuinely open. Do not read either symptom as a broken endpoint.
- The DNS gate queries several resolvers (`DNS_RESOLVERS="system 1.1.1.1 8.8.8.8 9.9.9.9"`) and
  requires agreement. Pinning one resolver produced a false "does not point at this node" while the
  zone was already correct, purely because that network could not reach 1.1.1.1.
- Nested quotes through ssh are a trap: `grep -q \'^VAR=.\'` delivers literal apostrophes into the
  remote regex and fails even when the variable is set. Use `grep -qE ^VAR=.`.

## www.lxon.in — LIVE since 2026-10-21 18:37 UTC (308 redirect to the explorer)

`https://www.lxon.in` returns `HTTP/2 308` with `location: https://explorer.lxon.in/<same path and
query>`, on a real Let's Encrypt certificate (`CN=www.lxon.in`, issuer `YE1`, notBefore 21 Oct 2026
18:37:20 GMT → notAfter 19 Jan 2027, `SSL certificate verify ok`). The cert's own `notBefore` is the
timestamp to quote here: it is the moment ACME completed, and it reads 2026-10-21 UTC even though the
same minute was already 2026-10-22 locally — an easy off-by-one-day to write into a "LIVE since" line.
Getting there needed two independent halves, and
only one of them was in this repo.

What was wrong when this was opened: the zone's `www` A record pointed at `52.3.226.228` — an AWS
`us-east-1` address that is **not in this account** (absent from `describe-instances` in five regions)
and answered on no port (80/443/3000/4000/8545 all filtered), an orphan from an earlier deployment —
and Caddy had no site block for the name, so SNI `www.lxon.in` against `13.62.37.246` died with
`tlsv1 alert internal error` (alert 80) while `explorer.lxon.in` on the *same IP* answered 200. The
record is a human's two-minute job in the Hostinger panel (`lxon.in` is served by
`byte.dns-parking.com` / `pixel.dns-parking.com`, and the deployer IAM user has no `route53:*`):

    www.lxon.in   A   13.62.37.246   TTL 300      (replaced 52.3.226.228)

The bare apex `lxon.in` and `api.lxon.in` still have **no** A record, so `https://lxon.in` is not
"broken" in the same sense — it has never been addressed anywhere. If the apex should also redirect,
that is the same two-step with a record plus `WWW_DOMAIN=lxon.in`, and it needs its own site filename
(`SITE_FILE` is hardcoded to `03-www.caddy`, so a second run would overwrite the first).

`./enable-www.sh` installs `caddy/sites-enabled/03-www.caddy` and recreates the proxy. It is gated in
the order that matters: DNS must already point here, the `.env` must already carry `EXPLORER_DOMAIN`,
the site file is written **before** the recreate, and the combined config is linted in a throwaway
container that is thrown away on failure (which also deletes the site file, so a rejected config
leaves the explorer exactly as it was). `--check` is what the refusal looked like before the record
moved, and is what any future name change will show again:

```bash
./enable-www.sh --check    # before: ERROR, www resolves to 52.3.226.228, not the EIP
                           # after:  OK: www.lxon.in -> 13.62.37.246. Safe to run without --check.
./enable-www.sh --dry-run  # prints the exact chain, env vars and ordering
./enable-www.sh
```

Why a TLS site and not a bare `:80` redirect: the explorer sends
`Strict-Transport-Security: max-age=31536000; includeSubDomains`, so any browser that has already
visited `explorer.lxon.in` rewrites `http://www.lxon.in` to `https` **before it resolves it**. An
HTTP-only redirect would be unreachable for exactly the audience that matters. `www` needs its own
certificate, and that is why the DNS gate is the whole design — a site block for a hostname that
resolves elsewhere is a failing ACME order, not a redirect.

What made that gate earn its keep: the config was fully built and proven **before** the record moved,
and none of it touched production. With `03-www.caddy` added to a copy of the real config,
`caddy validate` returned `Valid configuration` and `caddy adapt` yielded three routes on `srv0`
(`explorer.lxon.in`, `rpc.lxon.in`, `www.lxon.in`) with the existing two unchanged; running that
config under `local_certs` in a container bound to `127.0.0.1:18443` (internal CA, so zero ACME
traffic) returned `HTTP/2 308` with `location: https://explorer.lxon.in/tx/0x1234?tab=events` for
`/tx/…`, `/address/…`, and `/`. Only after the human record change did the script recreate the real
`lxon-caddy` — and ACME then succeeded on the first order (`validations succeeded; finalizing order`,
`certificate obtained successfully`, identifier `www.lxon.in`), which is the whole point of waiting:
the same install against the orphan address would have been five failing validations instead.

The fourth file was also rendered through the real merge chain (`config --format json`, in a `/tmp`
project, printing only caddy's mounts) before being trusted: caddy ends up with the base Caddyfile,
`caddy-data`, `caddy-config`, `02-rpc.caddy` **and** `03-www.caddy` — sequences append, so the overlay
adds a mount instead of replacing the list — and `blockscout-frontend`/`blockscout-backend` are still
`127.0.0.1:3000`/`127.0.0.1:4000`, i.e. adding the www overlay did not re-widen the explorer ports.
`up -d` therefore runs with `--no-deps`: caddy `depends_on` blockscout, and compose recreates a
dependency it believes drifted, which is how this stack lost the explorer before.

Two traps found while building this, both of which would have produced a fake green:

- **`import` is an absolute path.** `caddy validate` on a copy mounted at `/cfg` silently emitted
  `No files matching import glob pattern` and returned `Valid configuration` — it had linted the
  Caddyfile with **no** site files at all. A lint harness must reproduce the container mount points
  (`/etc/caddy/Caddyfile`, `/etc/caddy/sites-enabled`) or it proves nothing.
- **A verification step can be broken instead of failing.** The first version of the redirect check
  piped `curl -I` through an awk one-liner with an unterminated string in `print`, which is a hard
  awk syntax error — the script would have printed an empty result rather than a failure. It now
  parses status and `Location` separately and asserts each.

## Chain state

The AWS node starts from genesis with an empty `besu-data` volume. Genesis:
`../besu/genesis.qbft.json`, hash
`0x6c931dffbac6d832d33efb81d31880391cb637eed456cc838bf9689595ecc588`, chainId 724,
sole validator `0xFaE699d2848957c7c3bE67D8c90f0E456419cAdA`.

Changing anything in the genesis requires wiping the volume (`RESET=1`, or
`docker compose down -v`) — Besu refuses to start on a database that disagrees
with the genesis file. Never run two sealers for this chain with the same key
(e.g. `../besu/run-besu.sh` locally plus this node): they will produce divergent
forks. Backing up chain state:
`docker run --rm -v lxon-evm_besu-data:/data -v $(pwd):/backup alpine tar czf /backup/besu-data.tgz -C /data .`

## Production path

This is a **single-validator QBFT** node — a devnet/stand-in. QBFT quorum math
is 2f+1, so n=1 needs only 1 signer and sealing works with zero peers; going to
4 validators needs `qbft_proposeValidatorVote` (or a genesis epoch change), and
each validator needs its own `--node-private-key-file` plus the identical
genesis file. See `../BLOCKCHAIN_CLIENT_RECOMMENDATION.md`.

The `besu/` directory holds the source genesis and entrypoint; `deploy.sh`
copies them to `/opt/lxon/besu/`. Besu needs ~4 GB heap headroom, so
`blockperiodseconds` tuning and `--max-peers` changes should be tested on the
instance (t3.large), not just locally.

## Cost (eu-north-1, approximate)

- t3.large: ~$70/mo
- 150 GB gp3: ~$12/mo
- EIP: free while associated with a running instance

# Deployment records — which of these files you can believe

<!-- lxon-724-restart-notice:begin -->
> ⚠️ **Chain 724 addresses quoted in this file no longer exist.** Measured 2026-11-04 against `https://rpc.lxon.in`. Chain 724 restarted from an empty volume on 2026-11-03 under its original genesis (block 0 `0x6c931dff...`), so blocks 1-242,493 -- and every contract created in them -- are gone. Each address below returns **0 bytes of code** on 724 today:
>
> - `0x99801a78639975d448eeb2f8a807738dc8df67dc` - LXON (LxonTokenEnhanced)
>
> The control that makes those empty reads evidence, measured by the same script: the v4.1 bridge on Polygon 137 is 19,105 bytes and wLXON is 2,106 bytes, so a working reader does return bytes when something is there. Read everything below as history or as a redeploy target, not as live state. Per-address ledger and method: `docs/724-claim-ledger-2026-11-03.md`.
<!-- lxon-724-restart-notice:end -->
**Date convention:** the "measured 2026-10-22" stamps in this directory and in the corrected documents are
the operator's **local** date (UTC+5:30). In UTC those same measurements are 2026-10-21, roughly 22:00, and
the chain heads quoted beside them are the unambiguous evidence. This is the same off-by-one-day trap that
the `www.lxon.in` cert date was written up for in `../../../lxon-evm-node/aws/README.md`: quote the timezone
or you will later doubt your own measurement.

`git ls-files` shows **3** tracked records here; there are **37** `.json` files on disk. The rest are
ignored by the repo-root rule `apps/contracts/deployments/*` (`.gitignore:55`), which is why annotating
one of them changes nothing for anybody else: an ignored file never reaches a clone, a review, or a
CI run, and `git clean -fdx` deletes it. This README is the tracked place for the conclusions, and it
is negation-included (`!apps/contracts/deployments/README.md`) so it actually ships.

## Measured 2026-10-21 (counts corrected 2026-10-22), not inherited from an earlier doc

Across the 37 files there are **98 distinct 40-hex address references**. Checking each with
`eth_getCode` on both chains that LXON has ever touched:

| Result | Count |
|--------|-------|
| has code on chain 724 | 21 |
| has code on Polygon 137 | 18 |
| has code on **neither** chain | **59 (60%)** |

An earlier revision of this file said "170 references, 131 dead (77%)". Both numbers were wrong in the same
direction, and the cause is the regex: `0x[0-9a-fA-F]{40}` with no right-hand boundary matches the first 40
hex characters of any 64-character **transaction hash**, so 72 of those "addresses" were never addresses at
all — and since a hash prefix has no code, every one of them landed in the dead bucket. The alive counts
(21 / 18) were unaffected; only the denominator and the failure rate were inflated. Anchor it:
`0x[0-9a-fA-F]{40}(?![0-9a-fA-F])`.

Two cautions about the "has code" rows, because they overstate reality in opposite directions:

- **724's 21 include deliberately dead contracts.** `0xbc18d288…` and `0xb4927aBef…` are bridge v1/v2
  with no token roles, kept on chain and named in records; `0x76EF2514…` is the unbacked `LXONWrapper`.
  Code existing is not the same as an asset working. See `knownIssues` in `lxon-chain-724.json`.
- **Polygon's 18 include other people's protocols.** `0xc35DADB6…` is the SushiSwap V2 factory,
  `0xe592427a…` the Uniswap V3 factory, and `0x1f98401a…`/`0x7e5f4552…`/`0xf39fd6e5…` are the test
  fixture addresses that Uniswap's own docs copy-paste. Scripts that merely *referenced* infrastructure
  make it look deployed "by us". The genuinely ours on 137 are wLXON `0xB2CfeCb2…`, `0x8E7BE3BC…`,
  `0xf6B053bE…`, the bridge `0x2e622d39…`, the empty pair `0x64113415…`, and three identical
  admin-gated contracts whose purpose is unknown.

Reproduce it (this is the command that works — see the trap below):

```bash
cd apps/contracts && python3 - <<'PY' > /tmp/batches.txt
import json,re,glob
addrs=set()
for f in sorted(glob.glob('deployments/*.json')):
    addrs |= set(x.lower() for x in re.findall(r'0x[0-9a-fA-F]{40}(?![0-9a-fA-F])', open(f).read()))
addrs=sorted(addrs)
for i in range(0,len(addrs),50):
    c=addrs[i:i+50]
    print(json.dumps({"chunk":c,"req":json.dumps([{"jsonrpc":"2.0","id":n,"method":"eth_getCode","params":[a,"latest"]} for n,a in enumerate(c)])}))
print(json.dumps({"total":len(addrs)}))
PY
# then POST each batch with curl to https://rpc.lxon.in and https://polygon-bor-rpc.publicnode.com
```

## `active-contracts-report.json` is discredited, and here is the proof

It claims `"network": {"chainId": 724, "rpc": "https://rpc.lxon.in"}` and `"deployed": true` for four
contracts. **All four have 0 bytes of code on 724 and real code on Polygon 137** — the file was generated
against one chain and stamped with the other. Its `codeLength` figures (4794 / 9146 / 11002 / 12750) match
neither chain's actual runtime sizes (6087 / 5431 / 6087 / 6087 bytes), and the metadata it prints for them
is unreadable at those addresses: `symbol()`, `name()`, `decimals()` and `totalSupply()` **revert on all
four**, so the `"symbol": "WETH" / "LXON" / "LP"` and `"decimals": 6 / 18` fields were not read from the
chain at all.

The labels are wrong too. `0x86a7da57…` ("Wrapped Ether"), `0x3aD52bD5…` ("LP Token") and `0x643a62a5…`
("router") are **byte-identical to each other** — 6,087 runtime bytes each, `cast code 0xADDR | md5` =
`fc8802ab9ec32b84ddcd4bb5b33c5e01` on all three — each exposes `admin()` = `0x43410E73…` in storage slot 0,
has no EIP-1967 implementation slot, and reverts on `symbol`, `name`, `decimals`, `totalSupply`, `token0`,
`token1` and `getReserves`. So none of
them is a token, a pair, a router, or a standard proxy. The real wLXON pair is `0x6411341503ba6C1fEE4eafE1483Eea8831704F62`
and is not in that file at all. What these three *are* is unresolved — do not invent a purpose for them.

A note on how that was checked, because the shortcut fails: matching on the leading bytes
(`0x608060405260043610…`) against local artifacts looks like it identifies a contract but hits eight
unrelated ones, since that is Solidity's generic constructor preamble. Byte-for-byte runtime md5 is the
comparison that actually discriminates.

## wLXON on Polygon has no price, and there is no number to quote for it

Measured at head 95,940,837:

```
0xB2CfeCb2aa1c53e8c4406146368222b6b3BbBbb6  "LXON Wrapped" / wLXON / 18 decimals
  totalSupply()      4,010,000.000001   — and balanceOf(0x43410E73…) == totalSupply exactly
  originalLXON()     0x0a26E5CC91C167B38633b28013AD8d5EF1F6904E → 0 bytes on Polygon, 0 bytes on 724
  DEFAULT_ADMIN_ROLE → held by 0x43410E73… (an account whose key sat in tracked source)
  pool             0x64113415… (Sushi V2, wLXON/WMATIC): getReserves 0/0, holds 0 of both, LP totalSupply 0
  DexScreener      0 pairs for this address      CoinGecko: no listing
```

Zero reserves, zero LP supply, no listing, no bids — so there is no market price. It is also not
redeemable: this is the pre-fix `LXONWrapper`, whose `wrap()` minted without pulling anything in and
whose `unwrap()` burned without paying, against an underlying that exists on no chain. **Do not multiply
4,010,000 by an assumed price** — that is the exact move behind the deleted `1000M_LXON_MINTED_SUCCESS.md`
and `2DOLLAR_DEX_LAUNCH.md` documents, and it is how a self-issued asset gets a fictional market cap.
Funding the empty pool would not fix this either; it would produce a price the project quoted to itself,
paid for with a compromised key, in front of real buyers.

The Polygon estate is unrelated to chain 724: on the live bridge `0x28C93C2af6B1d5349ba356A8735b343B2CAa4379`,
`peerBridges(137)` is `0x0`. Nothing bridges between them. Full detail, including the abandoned
bridge that likely cannot be handed over, is in `lxon-chain-724.json` under `polygonMainnet137`.

## "wLXON" is three different contracts, and none of them has a price

Someone asking "what is wLXON worth" gets a different answer depending on which of the three they mean.
All measurements below were taken 2026-10-22 at 724 head 50,653 and Polygon head 95,942,816.

| | Polygon `0xB2CfeCb2…` | 724 `0x76EF2514…` (v1) | 724 `0xC0CF6B0E…` (v2) |
|---|---|---|---|
| `name()` / `symbol()` | LXON Wrapped / wLXON | LXON Wrapped / wLXON | LXON Wrapped / wLXON |
| `decimals()` | 18 | 18 | 18 |
| `totalSupply()` | **4,010,000.000001** | 0 | 0 |
| `originalLXON()` | `0x0a26E5CC…` — **0 bytes on both chains** | `0x99801A78…` (the live LXON) | `0x99801A78…` (the live LXON) |
| LXON custody (`balanceOf`) | n/a | 0 | 0 |
| runtime bytes | 3,343 (measured 2026-10-22 on publicnode; `polygon-rpc.com` answers `API key disabled … 403`, so it reports every contract as 0 bytes — never use it as a control) | 3,391 | 3,885 |
| who controls minting | `0x43410E73…` — the leaked key | deployer | deployer (`MINTER_ROLE`) |
| backed? | **no** — `wrap()` minted without pulling anything in | **no** — same bug, abandoned | wrap/unwrap custody is real, but nothing has been wrapped |
| price | none (0 pairs, pool reserves 0/0) | none (no pool exists) | none (no pool exists) |

The distinction matters in both directions. The Polygon one is the dangerous asset: 4.01M tokens exist,
all of them in the hand of a key that sat in tracked source, redeemable for nothing. The 724 v2 is the
opposite failure — correctly wired to the live LXON token, and therefore worth exactly zero because its
supply is zero and no LXON has ever been deposited into it. Recording only the Polygon address, as the
older documents in this repo do, makes the healthy contract invisible and the broken one look like the
project's token.

Chain-724 custody is `0` and was read both ways (`wLXON.originalLXON().balanceOf(wrapper)` and
`LXON.balanceOf(wrapper)`), so this is not one failing getter being read as a zero.

## Nine "success" documents name 36 addresses; not one of them exists on chain 724

Measured 2026-10-22 the same way as the 98-address sweep above — `eth_getCode` on `https://rpc.lxon.in`
and `https://polygon-bor-rpc.publicnode.com`, with three live controls (`0x9980…` 8,378 B, `0xC0CF…` 3,885 B,
`0xe801…` 2,524 B) in the same batch so that a null means "no code" and not "no TLS". Only the addresses
in the **claims** are counted: every correction banner is fenced with `<!-- END CORRECTION -->` and the
script below reads the text after that fence, because the banners themselves quote live addresses.
"Never used anywhere" means 0 code, 0 nonce and 0 balance on both chains — the address has never been part
of any transaction on either network LXON has touched.

| Document | addresses claimed | contracts on 724 | contracts on 137 | EOAs | never used anywhere |
|---|---|---|---|---|---|
| `1000M_LXON_MINTED_SUCCESS.md` | 2 | **0** | 1 | 0 | 1 |
| `2DOLLAR_DEX_LAUNCH.md` | 6 | **0** | 3 | 0 | 3 |
| `DEX_LIQUIDITY_SUCCESS.md` | 6 | **0** | 4 | 1 | 1 |
| `ALL_7_CONTRACTS_DEPLOYED_SUCCESS.md` | 12 | **0** | 6 | 1 | 5 |
| `DEFI_IMPLEMENTATION_SUMMARY.md` | 8 | **0** | 1 | 0 | 7 |
| `COMPLETION_SUMMARY.md` | 9 | **0** | 0 | 1 | 8 |
| `PROJECT_COMPLETION_SUMMARY.md` | 9 | **0** | 0 | 1 | 8 |
| `GITHUB_PR_COMMENT.md` | 4 | **0** | 0 | 4 | 0 |
| `lxon.tokenlist.json` | 4 | **0** | 0 | 4 | 0 |
| **distinct** | **36** | **0** | **7** | **5** | **24** |

Every one of these files asserts chain 724 or "LXON Mainnet". Each now carries a correction banner at the
top quoting its own claim against the measurement, with its body left unedited so the record of what was
claimed survives. `HARDHAT_NETWORK_DEPLOYMENT_SUCCESS.md` was deliberately **not** banner-ed: it says
Hardhat Network in its title and its addresses really are local-VM artifacts, so it is accurate about which
chain it belongs to — the defect is only in files that move those addresses onto 724.
move those addresses onto 724.

Three other files in that directory were left alone on purpose, because they do not assert an achieved
fact: `DEX_ARCHITECTURE.md` describes how a router-and-pair design would work, `POLYGON_EVALUATION.md`
and `OWN_MAINNET_REEXAMINATION.md` are option lists: their status lines read "⏳ Evaluation Required",
"⏳ Re-examining Own Mainnet Options", and "Status: Not yet attempted", and they recommend rather than report. A banner on a document that claims nothing would only teach the next
reader to distrust banners. The test used was: does this sentence assert something is true on chain now?

The four `GITHUB_PR_COMMENT.md` / token-list addresses are the deterministic CREATE addresses of Hardhat and
Anvil account #0 (`0xf39Fd6e5…`): `cast compute-address 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
--nonce 0..3` returns `0x5FbDB231…`, `0xe7f1725E…`, `0x9fE46736…`, `0xCf7Ed3ac…` in that order. They are the
slots where a fresh local chain's first four contracts would land, and they have never held code on a real
chain — though on Polygon they sit at nonce 0 holding 177.86, 29.67, 172.04 and 3.50 POL, because those keys
are public and strangers fund them.

The token list deserves naming separately, because it is a distribution artifact rather than prose: it
declares `"chainId": 724` for those four codeless addresses, its four logos share one string that is not a
valid IPFS CIDv0 (44 chars, base58-decodes to a 33-byte `0161`-prefixed value, where a real v0 is 46 chars /
34 bytes / `1220`), the `logos/` directory its upload script `ipfs add`s does not exist, and the file
begins with a block comment so it is not parseable JSON and cannot pass the `@uniswap/token-lists validate`
command quoted in `GITHUB_PR_COMMENT.md`. Gateway resolution was inconclusive (HTTP 429 for the fake CID
and for a known-good control), so the invalidity claim above rests on the multihash structure, not on a
failed fetch.

Reproduce the table:

```bash
cd apps/contracts && python3 - <<'PY' > /tmp/todo.json
import re,json
docs=["1000M_LXON_MINTED_SUCCESS.md","2DOLLAR_DEX_LAUNCH.md","DEX_LIQUIDITY_SUCCESS.md",
      "ALL_7_CONTRACTS_DEPLOYED_SUCCESS.md","DEFI_IMPLEMENTATION_SUMMARY.md","COMPLETION_SUMMARY.md",
      "PROJECT_COMPLETION_SUMMARY.md","GITHUB_PR_COMMENT.md","lxon.tokenlist.json"]
a=set()
for d in docs:
    s=open(d).read()
    fence=' * END DO NOT PUBLISH' if d.endswith('.json') else '<!-- END CORRECTION -->'
    a|=set(x.lower() for x in re.findall(r'0x[0-9a-fA-F]{40}(?![0-9a-fA-F])',s.split(fence,1)[1]))
a=sorted(a)+["0x99801A78639975D448EEb2f8a807738DC8Df67Dc","0xC0CF6B0E6C5a0705F319BA5c629a6Bc7E82FEf00",
             "0xe801e058b4c9f77dd60980a80f7607a50afe1799"]   # positive controls
print(json.dumps([{"jsonrpc":"2.0","id":i,"method":"eth_getCode","params":[x,"latest"]} for i,x in enumerate(a)]))
PY
curl -s https://rpc.lxon.in -H 'content-type: application/json' --data @/tmp/todo.json
```

## Where the fake "724 deployments" came from: a forge dry run, filed under `/724/`

`GITHUB_PR_COMMENT.md` cites its source precisely, and the source is the mechanism:

> **Addresses Verified From** `broadcast/DeployPairAndRouter.s.sol/724/run-latest.json`

Open that file. It holds 19 transactions, **every one with `hash: null`, `from: null`, `nonce: null`, no
`gasPrice`, and `receipts: []` is empty**. Nothing in it was ever sent to a node — it is what `forge script`
writes when the run is simulated. The `724` in the path is only the chain id the script was *told* to expect;
it is not evidence that a chain answered.

Reading `contractAddress` out of that file produces addresses that look exactly like deployments, because
CREATE addresses are `keccak(rlp([sender, nonce]))[12:]` — a prediction, not an event. Three of the addresses
in these dry-run records (`0x2e622d39…`, `0x8E7BE3BC…`, `0xf6B053bE…`) equal `cast compute-address
0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27 --nonce 0 / 1 / 7`, and all three are real Polygon 137 contracts.
So the same script sequence was later run for real, from the leaked-key account, **on Polygon** — and the
documentation had already stamped its addresses onto chain 724. The pair/router/WETH trio
(`0x86a7da57…`, `0x3aD52bD5…`, `0x643a62a5…`) is not explained by that sender's nonces 0-24 and its creator
cannot be recovered from the record, because the record has no sender; it stays unresolved.

Three of the 21 broadcast records under `broadcast/*/724/` have zero hashed transactions
(`DeployPairAndRouter`, `DeployBridgeWithTimelock`, `DeployLxonProduction`). Of the 18 that do have hashes,
**only 25 of their 83 transactions exist on the live chain 724** (`eth_getTransactionByHash` returns null for
the other 58) — the ones that exist sit at blocks 0x2c-0x2d, the real early deployments. Whatever node the
other runs were broadcast to, it was not this chain.

Be careful not to over-credit this explanation. The dry-run records account for the markdown docs above,
which cite them by name, but only **3 of the 59 dead addresses in `deployments/*.json` appear as a
`contractAddress` in any broadcast record** — 56 of them have no artifact behind them at all. The dry run is
a proven mechanism for one family of claims, not a theory of the whole pile.

Reproduce:

```bash
cd apps/contracts && python3 - <<'PY'
import json,glob
for f in sorted(glob.glob('broadcast/*/724/run-latest.json')):
    d=json.load(open(f)); txs=d.get('transactions',[])
    print(f"{f:58s} chain={d.get('chain')} txs={len(txs):3d} "
          f"hashed={sum(1 for t in txs if t.get('hash')):3d} receipts={len(d.get('receipts') or []):3d}")
PY
```

## Keyless dry run of the Polygon handover — what would actually succeed

`scripts/rotate-off-leaked-account.js` needs the leaked key in its environment, and running it that way is
blocked by the permission layer here. It does not need the key to *predict* the outcome: every step it
simulates is an `eth_call` with `from` set to the leaked account's **public** address
(`0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27`). Replaying that sequence read-only at Polygon head 95,944,732:

| Step | Result |
|---|---|
| `wLXON.hasRole(DEFAULT_ADMIN_ROLE, signer)` | `true` |
| `wLXON.grantRole(DEFAULT_ADMIN_ROLE, NEW)` | would succeed |
| `wLXON.grantRole(MINTER_ROLE, NEW)` | would succeed |
| `wLXON.renounceRole(DEFAULT_ADMIN_ROLE, signer)` | would succeed (and only runs after a grant — the script's guard) |
| `LXON Test.transferOwnership(NEW)` | would succeed; owner today = the signer |
| `LXON Settlement Asset.transferOwnership(NEW)` | would succeed; owner today = the signer |
| `bridge.updateAdmin` / `setAdmin` / `changeAdmin` | **all revert**; `admin()` = the signer |
| sweep POL to the destination | 20.5896 POL held, 21,000 gas per transfer |

Neither token exposes `pendingOwner()` or `acceptOwnership()`, so `transferOwnership` is one-step: the
destination owns the contract the moment the transaction lands, with nothing to claim. That makes the
destination choice unforgiving — an `eth_call` with `from = signer` to `transferOwnership(0x1111…1111)` also
succeeds, so **a mistyped destination is a permanent loss, with no way to recall it**. Grant to an address
that holds no Polygon gas and the admin role is real but unactionable; grant to the LXON validator account
(`0xFaE699d2…`, the address this dry run used because it is already recorded as `deployer` on 724) and you
have pointed a chain-critical signing key at Polygon. Pick a purpose-built account, generated in your own
terminal (`cast wallet new`), and keep its key out of this repo and out of any agent's environment.

The bridge is the part with no answer: `admin()` is the leaked account and there is no setter for it, so the
only options are to leave it as it is and never wire it to anything, or replace it. It holds 0 POL and no
token balance, and `peerBridges(137)` is 0 on the live chain-724 bridge, so abandoning it traps nothing.

### The Polygon estate, re-read with each token's own decimals

| Contract | Symbol | `decimals()` | `totalSupply()` | Held by the leaked account |
|---|---|---|---|---|
| `0x8E7BE3BC…` LXON Test | LXON | 6 | 1,000,000 | 100.0% |
| `0xf6B053bE…` LXON Settlement Asset | LXON | 6 | 100,000 | 100.0% |
| `0xB2CfeCb2…` wLXON | wLXON | 18 | 4,010,000.000001 | 100.0% |

An earlier revision of this table used `formatUnits(supply, 18)` for all three and therefore reported the
6-decimal tokens as `0.000001` and `0.0000001`. Always read `decimals()` first — the same supply is six
orders of magnitude different depending on which number you divide by, which is exactly the 6-vs-18 bug
already recorded in `lxon-chain-724.json`.

The raw numbers are reproducible without any key:

```bash
curl -s https://polygon-bor-rpc.publicnode.com -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"eth_call","params":[{"to":"0x8E7BE3BC21F8eDa71d192ECa502705c10274a813","data":"0x18160ddd"},"latest"]}'
# 0x18160ddd totalSupply · 0x313ce567 decimals · 0x70a08231+<padded addr> balanceOf
```

## Two tests that need no source-reading, and one bridge inventory

**Proving the Polygon wrapper is unbacked, without reading any code.** Both halves of its promise return
empty success from an account that has nothing to give:

```
wrap(1)   from 0x43410E73…   → 0x  (success)   — it holds 0 of the underlying and granted 0 allowance
unwrap(1) from 0x43410E73…   → 0x  (success)   — it holds all 4,010,000.000001 wLXON
originalLXON() = 0x0a26E5CC…                    — 0 bytes of code on 137 and on 724
```

Any wrapper that actually moved collateral would have to revert on one of those two calls: pulling LXON from
a zero balance fails, and paying LXON out of an address with no code fails. Neither reverts, so neither path
touches the underlying. That is a chain-level proof, available even if the source had been deleted.

**Chain 724's "fixed" wrapper still lets its admin repeat the same mistake.** `wrap()`/`unwrap()` on
`0xC0CF6B0E…` are correct, but the `MINTER_ROLE` path is not collateralised and the deployer holds it:

```
hasRole(MINTER_ROLE, 0xFaE699d2…) → true
mint(0xFaE699d2…, 1e24)           → 0x (success)   — 1,000,000 unbacked wLXON, printable right now
```

So "supply is 0, therefore honest" is only true until someone uses the admin path. Closing it costs nothing
while supply is still 0 — revoke or re-gate `MINTER_ROLE` before any activation, not after.

**The live bridge has no destination-side entry point at all.** Every external function of
`0x28C93C2a…4379` (from its verified source) is outbound or administrative: `initiateTransfer`,
`initiateTransferWithPermit`, `initiateBatchTransfer`, `signTransfer` (`onlyValidator`), `sendMessage`,
`deliverMessage` (`onlyValidator`), the `onlyRole(DEFAULT_ADMIN_ROLE)` validator setters, the `onlyTimelock`
setters, and view getters. There is no `completeTransfer`, `claimTransfer`, `release`, `verifyAndRelease` or
`executeTransfer` — probed against the deployed bytecode, each reverts, while `getTransfer(bytes32)` returns
a struct as the positive control. `peerBridges(137)` is the zero word, and so is **`peerBridges(724)`** — the
bridge does not even register itself. Consequence: calling `setPeerBridge(137, …)` would not create a bridge,
because the receiving half of the mechanism does not exist; `deliverMessage` pays out of *this* chain's own
balance. One number people misread here: `LXON.balanceOf(bridge)` is **30,000 LXON** (`3e22` wei at 18
decimals) — that is the three registered validators' 10,000-each stake, not user escrow, so "no funds are
trapped" is about users and is still true.

## Making the 724 wrapper real: the three-transaction sequence

`scripts/prepare-724-wrapper-backing.js` prints the plan without a key and refuses to broadcast unless both
`DEPLOYER_PRIVATE_KEY` and `--i-verified-preconditions` are supplied. Order matters and is explained in its
header: **revoke `MINTER_ROLE` first** (while supply is 0, so it strands nothing), then `approve`, then
`wrap`. Measured preconditions at head 51,543: wrapper 3,885 bytes, `totalSupply()` 0, custody 0, signer
holds MINTER_ROLE and 99,968,900 LXON, nonce 58, gasPrice 7 wei, estimated gas 34,839 + 48,555 + wrap.
Two limits worth knowing before you call this "secure":

- `getRoleMember` / `getRoleMemberCount` do not exist in this ABI (OZ v5 `AccessControl` without
  enumerably-access), so after the revoke you can only prove `hasRole(...) == false` for each address you
  think of. The sweep at the time of writing found MINTER held by the deployer and by nobody else among the
  nine addresses this project tracks — which is not the same as proving nobody anywhere holds it.
- `DEFAULT_ADMIN_ROLE` stays with the deployer, so the deployer can `grantRole(MINTER_ROLE, …)` again.
  Renouncing it as well makes the wrapper permanently collateral-only, and is irreversible. Both are
  defensible; decide on purpose. The future bridge-custody design is the reason not to renounce yet.

The third transaction cannot be estimated against `latest` because its precondition (the approve) has not
landed — the script says `not estimable yet` rather than substituting a guessed number.

## The bridge's 30,000 LXON is staked in three wallets that have never signed anything

`docs/lxon-production-hardening-roadmap.md` states that "the bridge's own LXON balance is 0 wei, so nothing
is trapped". Measured at 724 head 51,543, that read is of the wrong token: there are two LXON-family tokens
and the bridge holds **30,000 of `LxonTokenEnhanced` `0x99801A78…`** (`3e22` wei at 18 decimals) while
holding 0 of `LXONNativeToken 0xe801e058…` (symbol XON). The conclusion survives; the evidence does not, and
the number is not cosmetic — it is the validator set's stake.

`eth_getLogs` over blocks 44520-44522 recovers exactly where it went. Three `ValidatorAdded` events, each
carrying `1e22` (10,000 LXON), all emitted by the deployer:

```
0xc9eac7783e9f4df23f592c13065d03f8a0ed0ef5   validators=true  stake=10000  VALIDATOR_ROLE=true
0x5ad73f86cad3d0074a86cf276a67b119a4f4a628   validators=true  stake=10000  VALIDATOR_ROLE=true
0xF2b1a38A53DAF4a40fAa9E956887Ac94297588a0   validators=true  stake=10000  VALIDATOR_ROLE=true
```

3 × 10,000 = the 30,000 balance, so the accounting closes. What is not comfortable: **all three have nonce 0
and a balance of exactly 1 native** — they were registered for the multi-sig release proof and have never
signed a transaction on this chain. Their addresses are recorded in `lxon-chain-724.json`. Four private-key
files exist in the repository (`lxon-evm-node/geth/privatekey.txt`, `lxon-evm-node/besu/privatekey.txt`,
`lxon-evm-node/geth/nodekey`, `apps/contracts/verification_service_private_key.hex`) and none of them is
named for these wallets — but that is not proof they are unrelated, because confirming it means deriving
addresses from those keys, which is credential use the standing rules forbid and which an agent should not
do. **Check it locally**: `cast wallet address` takes the key as a positional argument, so run
`cast wallet address "0x$(cat apps/contracts/verification_service_private_key.hex)"` (that file is raw hex,
no `0x`) and the same for the two `privatekey.txt` files (drop the `0x` in front of any file that already
carries one), then see whether any of the three addresses appears.
If one does, its stake is recoverable and the quorum is reachable.
Consequences worth deciding on purpose:

- The attestation quorum of the live bridge is held by wallets nobody can operate here, so
  `minConfirmations = 2` is currently a quorum of unreachable signers. That is a stronger reason than the
  missing inbound path why the bridge cannot be wired up by configuration.
- `removeValidator(v)` returns the stake by `safeTransfer(v, stake)` — **to the validator address**, not to
  the admin. Unwinding the three would move 30,000 LXON into accounts whose keys may no longer exist. The
  LXON is the deployer's to release, but not to reclaim. If those keys are gone, treat 30,000 of the 100M
  supply as lost, and say so in any figure that quotes circulating supply.
- Anyone re-checking "is anything stuck in the bridge" must read both tokens; one `balanceOf` is how you get
  a confident 0.

## How to check anything in this directory

```bash
export ETH_RPC_URL=https://rpc.lxon.in      # or https://polygon-bor-rpc.publicnode.com
cast codesize 0xADDR                        # 0 means no contract
cast call 0xADDR 'symbol()(string)'         # interface probes; a revert means "not what it claims"
cast code   0xADDR | md5                    # runtime code identity — `cast codes` is not a command
```

Three failure modes hit during this measurement, all of which produce a confident wrong answer:

- **Python cannot reach these RPCs.** `urllib` on this machine's python 3.14 has no CA bundle, so every
  request raises `SSLCertVerificationFailed`; the loop reported "0 addresses with code on either chain",
  which was a story about TLS, not about the chain. Use `curl`, or `cast`.
- **An empty result is not a clean result.** `cast codes` (wrong name) printed nothing for every address
  including WMATIC, and the md5 of nothing is `d41d8cd98f00b204e9800998ecf8427e` — print a known-good
  control before trusting a null.
- **A zero can also be your own read failing.** `getReserves` on the wLXON pair returned all zeros, which
  would have been a fabrication if the same code path hadn't read 76,641 USDC / ~31.0 WETH on a real pool
  on the same factory.
- **A hash depends on the exact byte stream, so quoting one without its command is quoting nothing.** An
  earlier revision of this file gave the trio's md5 as `a86e712435a7213de7a36e4e67877b2a`. That value is
  real — it is `cast code 0xADDR | tr -d '\n' | md5` — but the command printed above
  (`cast code 0xADDR | md5`) yields `fc8802ab9ec32b84ddcd4bb5b33c5e01` because `cast` ends its output with a
  newline. Anyone re-checking with the documented command got a different answer and would have concluded
  the contracts had changed. Quote the pipeline, or the hash is not evidence.

#!/usr/bin/env bash
# Where is the pool's USDC? A read-only sweep of every chain this project can reach.
#
#   bash script/polygon137/FindUsdcShortfall137.sh
#   TARGET=2356 CHAINS="137 1" MAX_CHUNKS=4 bash script/polygon137/FindUsdcShortfall137.sh
#
# The ruling is 10,000 wLXON + 2,356 native USDC. The wLXON side exists and was crossed on 2026-10-29.
# The USDC side has never measured above zero in a project wallet. "It isn't here" is only half an
# answer, because USDC normally reaches Polygon by CCTP, and a CCTP transfer is TWO transactions on TWO
# chains: `depositForBurn` burns on the source and emits `MessageSent`, and the Polygon mint only exists
# once somebody calls `receiveMessage` with an attestation. In between, the money is legitimately
# nowhere -- and that is the only shortfall shape recoverable by calling a function. So the question is
# not "how much do we have" but "which of these four is true":
#
#   1. the funds are in a project wallet on some chain, in a token nobody looked at;
#   2. they were burned on a source chain and never minted on Polygon  -> recoverable: the burn tx hash
#      turns into an attestation at Circle's endpoint, then one receiveMessage call pays the recipient;
#   3. they were minted on Polygon into an address that is not the pool provider;
#   4. no `depositForBurn` was ever broadcast -> the shortfall is upstream (an off-ramp order that was
#      never placed, never signed, or is still pending) and only the owner can read that page.
#
# Measurement rules this script holds itself to. Each of them exists because the first revision of this
# file broke it and produced a confident wrong answer:
#   * a token counts as USDC only after `symbol()` and `decimals()` are read back FROM THE ENDPOINT IN
#     USE. Balances are scaled by the decimals that read returned: 137/1/42161/8453/10/43114 are 6, BSC's
#     Binance-Peg USDC is 18, and adding their raw wei together is a 1e12 error waiting to be printed.
#   * every topic and selector is derived at run time with `cast sig` / `cast sig-event`. The previous
#     revision hard-coded a MessageSent topic that was simply wrong, and five CCTP messenger addresses
#     whose on-chain code size is zero bytes -- both mistakes silently manufacture "nothing happened".
#   * USDC addresses are treated as hypotheses: the Base and Arbitrum constants carried in were replaced
#     after `eth_getCode` returned 0 bytes for them on two independent endpoints each, with a known-good
#     control (Base WETH = 2041 bytes) on the same endpoint. Where the address still fails, the chain is
#     reported NOT MEASURED, never zero.
#   * "no rows" and "the endpoint refused" are different sentences and are printed differently.
#   * MessageSent payloads are searched for project addresses, NOT field-decoded: the live payloads are
#     Circle's V2 hook format (384-1600 bytes, variable), so any fixed offset table prints garbage.
#   * a USDC transfer row is evidence only with its counterparty attached, which is why section 4 writes
#     a ledger and section 7 reads it back classified.
set -uo pipefail
export PATH="$HOME/.foundry/bin:$PATH"

TARGET="${TARGET:-2356}"
CHAINS="${CHAINS:-137 1 42161 8453 10 43114 56}"

RPC_137="${RPC_137:-https://polygon-bor-rpc.publicnode.com}"
RPC_1="${RPC_1:-https://ethereum-rpc.publicnode.com}"
RPC_42161="${RPC_42161:-https://arb1.arbitrum.io/rpc}"
RPC_8453="${RPC_8453:-https://base-rpc.publicnode.com}"
RPC_10="${RPC_10:-https://optimism-rpc.publicnode.com}"
RPC_43114="${RPC_43114:-https://avalanche-c-chain-rpc.publicnode.com}"
RPC_56="${RPC_56:-https://bsc-rpc.publicnode.com}"

# USDC per chain, re-identified on-chain below before any balance is believed
USDC_137="0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174"
USDC_1="0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
USDC_42161="0xaf88d065e77c8cC2239327C5EDb3A432268e5831 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8"
USDC_8453="0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
USDC_10="0x0b2C639c533813f4Aa9D7837CAf62653b09Aa0e6"
USDC_43114="0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E"
USDC_56="0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d"

# project wallets (EOAs) and project contracts
W_deployer=0x2a8Ca01C53cecF360b181a0B7D49a71565684665   # Polygon launch key, and the pool provider
W_founder=0x7F715B7F78a7d1D63455F3e2Ec1fa31D516f9Ef3
W_developer=0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27 # leaked dev key, holds 100% of legacy wLXON
W_validator=0xFaE699d2848957c7c3bE67D8c90f0E456419cAdA # 724 deployer / validator / minter
W_attestor=0x283697339fC32e286951D9F94Fa64082142cBC37
EOAS="${EOAS:-$W_deployer $W_founder $W_developer $W_validator $W_attestor}"
# 137 contract addresses taken from deployments/wlxonsecure-chain-137.json, not from memory
C_BRIDGE137=0xbDC32d8ca8CE805E0654E7A7D0dd1EE0a21D4A95
C_MIGRATION137=0x642Af10C04a796aFc79BD3fC39c2336add2d957B
C_TIMELOCK137=0xe56553Ed9E9BF52DA79EfAa15e8Ce5a1F000b9c5
C_TIMELOCK137_ALT=0x5Bfc2fD89396BD053F32dFb915B00fd8F8E56054
C_WLXON137=0x7A3c0C34f157EfDD3E4913c5224C15E645469093
C_OLDWLXON137=0xB2CfeCb2aa1c53e8c4406146368222b6b3BbBbb6
# the wLXON/USDC.e pair that went live 2026-10-29T23:20Z; confirmed here by factory.getPair in section 5
C_PAIR137=0x8bFB69eD898654D49cCBB59B7E594280dF4CB8fd
FACTORY_137=0x5757371414417b8C6CAad45bAeF941aBc7d3Ab32   # QuickSwap V2 factory
ROUTER_137=0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff    # QuickSwap V2 router
PAIR_USDCE_WMATIC=0x6e7a5FAFcec6BB1e78bAE2A1F0B612012BF14827  # factory.getPair(WMATIC, USDC.e)
PAIR_USDC_WMATIC=0x6D9e8dbB2779853db00418D4DcF96F3987CFC9D2   # the deeper native-USDC reference pair
# addresses whose presence on the far side of a transfer makes it OUR OWN bookkeeping, not a payout
KNOWN_VENUES="${KNOWN_VENUES:-$C_PAIR137 $ROUTER_137 $FACTORY_137 $PAIR_USDCE_WMATIC $PAIR_USDC_WMATIC}"
# Circle's V2 proxies are byte-identical addresses across EVM chains. Treated as a HYPOTHESIS: each
# candidate is kept only if it has code AND actually emitted a MessageSent in the scanned window.
TM2=0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d
MT2=0x81D40F21F12A8F0E3252Bccb954D722d4c464B64

INDEXER_137="${INDEXER_137:-https://polygon.blockscout.com}"
INDEXER_1="${INDEXER_1:-https://eth.blockscout.com}"
INDEXER_8453="${INDEXER_8453:-https://base.blockscout.com}"
INDEXER_42161="${INDEXER_42161:-https://arbitrum.blockscout.com}"

SLEEP=${SLEEP:-0.4}
MAX_CHUNKS=${MAX_CHUNKS:-4}
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
: > "$TMP/ledger.txt"

say(){ printf '\n\033[1m== %s\033[0m\n' "$*"; }
note(){ printf '  ·    %s\n' "$*"; }

rpc(){ curl -s --max-time ${RPC_TIMEOUT:-25} -X POST -H 'content-type: application/json' \
       --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$2\",\"params\":$3}" "$1" 2>/dev/null; }
res(){ rpc "$1" "$2" "$3" | python3 "$TMP/res.py"; }
callhex(){ printf '[{"to":"%s","data":"%s"},"latest"]' "$1" "$2"; }
decint(){ python3 "$TMP/decint.py"; }
decstr(){ python3 "$TMP/decstr.py"; }
padword(){ python3 "$TMP/padword.py" "$1"; }
addn(){ python3 "$TMP/addn.py" "$1" "$2"; }                     # integer add, non-numbers treated as 0

ep_for(){ case "$1" in 137) printf '%s' "$RPC_137";; 1) printf '%s' "$RPC_1";; 42161) printf '%s' "$RPC_42161";;
  8453) printf '%s' "$RPC_8453";; 10) printf '%s' "$RPC_10";; 43114) printf '%s' "$RPC_43114";;
  56) printf '%s' "$RPC_56";; *) printf '';; esac; }
usdc_for(){ case "$1" in 137) printf '%s' "$USDC_137";; 1) printf '%s' "$USDC_1";; 42161) printf '%s' "$USDC_42161";;
  8453) printf '%s' "$USDC_8453";; 10) printf '%s' "$USDC_10";; 43114) printf '%s' "$USDC_43114";;
  56) printf '%s' "$USDC_56";; *) printf '';; esac; }
idx_for(){ case "$1" in 137) printf '%s' "$INDEXER_137";; 1) printf '%s' "$INDEXER_1";;
  8453) printf '%s' "$INDEXER_8453";; 42161) printf '%s' "$INDEXER_42161";; *) printf '';; esac; }
sym_for(){ case "$1" in 137) printf 'POL';; 1|42161|8453|10) printf 'ETH';; 43114) printf 'AVAX';;
  56) printf 'BNB';; *) printf '?';; esac; }
# log-window chunk sizes measured against these free endpoints in the same session that wrote this file:
# publicnode caps Ethereum at 10000 blocks and refuses older state, arb1 times out past 50000,
# Base/Avalanche/BNB serve 50000, Polygon serves 9000. drpc refused EVERY getLogs range tried, even 500
# blocks, while still answering eth_call and eth_getCode -- which is why 137's default is publicnode.
chunk_for(){ case "$1" in 1) printf 9000;; 137) printf 9000;; 42161|8453|10|43114|56) printf 40000;;
  *) printf 9000;; esac; }

# ---------------------------------------------------------------- python helpers, written to files once.
# They are NOT embedded in $( ) substitutions: bash 3.2 mis-parses a multi-line python body inside a
# command substitution and reports the failure many lines away from the cause.
cat > "$TMP/res.py" <<'PY'
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    print(""); raise SystemExit
r = d.get("result")
if r is None:
    e = d.get("error")
    print("" if e is None else "ERR:" + str(e.get("message") if isinstance(e, dict) else e)[:120])
else:
    print(r if isinstance(r, str) else json.dumps(r))
PY

cat > "$TMP/decint.py" <<'PY'
import sys
s = sys.stdin.read().strip()
print(int(s, 16) if s.startswith("0x") and len(s) > 2 else "")
PY

# ABI string return: word 0 is the offset, word 1 the LENGTH, and the bytes start at char 130. Reading
# the body from char 66 decodes the length word as text and yields "" -- the bug that made the previous
# revision report symbol=[] for every USDC contract and therefore count nothing as USDC at all.
cat > "$TMP/decstr.py" <<'PY'
import sys
h = sys.stdin.read().strip()
if not h.startswith("0x") or len(h) < 130:
    print(""); raise SystemExit
try:
    n = int(h[66:130], 16)
except Exception:
    print(""); raise SystemExit
raw = h[130:130 + 2 * n]
raw = raw[:len(raw) // 2 * 2]
try:
    print(bytes.fromhex(raw).decode("utf8", "replace").strip("\x00 "))
except Exception:
    print("")
PY

cat > "$TMP/padword.py" <<'PY'
import sys
print(sys.argv[1].lower().replace("0x", "").rjust(64, "0"))
PY

cat > "$TMP/addn.py" <<'PY'
import sys
def i(x):
    try:
        return int(str(x).strip())
    except Exception:
        return 0
print(i(sys.argv[1]) + i(sys.argv[2]))
PY

cat > "$TMP/hexint.py" <<'PY'
import sys
s = sys.argv[1].strip()
try:
    print(int(s, 16) if s.startswith("0x") else int(s))
except Exception:
    print("")
PY

cat > "$TMP/subhex.py" <<'PY'
import sys
head = int(sys.argv[1], 16)
n = int(sys.argv[2])
k = int(sys.argv[3]) if len(sys.argv) > 3 else 0
print(hex(max(0, head - n * (k + 1))))
PY

cat > "$TMP/blkts.py" <<'PY'
# block timestamp out of a RAW eth_getBlockByNumber response. Raw, because res() unwraps "result" and
# re-serialises it -- pulling .result out of res()'s output silently gave "" and every window printed
# "0.00 hours".
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    print(""); raise SystemExit
r = d.get("result")
print(r.get("timestamp", "") if isinstance(r, dict) else "")
PY

cat > "$TMP/hrs.py" <<'PY'
import sys
def i(x):
    x = x.strip()
    try:
        return int(x, 16) if x.startswith("0x") else int(x)
    except Exception:
        return None
a, b = i(sys.argv[1]), i(sys.argv[2])
print("%.1f hours" % ((b - a) / 3600.0) if (a is not None and b is not None and b >= a) else "hours unknown")
PY

cat > "$TMP/logclass.py" <<'PY'
import sys, json
s = sys.stdin.read().strip()
if not s:
    print("silent (an address-less filter refused with an empty body)"); raise SystemExit
try:
    d = json.loads(s)
except Exception:
    print("not-json: " + s[:60]); raise SystemExit
if "result" in d:
    print("serves logs (n=%d in this probe range)" % len(d["result"]))
else:
    e = d.get("error") or {}
    print("refused: " + str(e.get("message") if isinstance(e, dict) else e)[:70])
PY

cat > "$TMP/scale.py" <<'PY'
import sys
n = int(sys.argv[1])
d = int(sys.argv[2]) if str(sys.argv[2]).isdigit() else 6
print("%.*f" % (max(d, 6), n / 10 ** d))
PY

cat > "$TMP/pairline.py" <<'PY'
import sys
kind, raw, addr = sys.argv[1], sys.argv[2], sys.argv[3]
s = raw.strip()
if not s.startswith("0x") or len(s) < 42:
    print("     getPair(wLXON, USDC %s) unreadable (%s) -> NOT MEASURED" % (addr, s or "empty"))
    raise SystemExit
body = s[-40:].lower()
if set(body) == {"0"}:
    print("     getPair(wLXON, USDC %s) = 0x0 -> no such pool exists" % addr)
else:
    print("     getPair(wLXON, USDC %s) = 0x%s -> a pool EXISTS" % (addr, body))
PY

cat > "$TMP/reserves.py" <<'PY'
import sys
h = sys.argv[1].strip()
if not h.startswith("0x") or len(h) < 2 + 96:
    print("     getReserves() unreadable (%s)" % (h[:60] or "empty")); raise SystemExit
r0 = int(h[2:66], 16) & ((1 << 112) - 1)
r1 = int(h[66:130], 16) & ((1 << 112) - 1)
if r1 == 0 or r0 == 0:
    print("     reserves are (%.6f, %.6f) -- an empty or drained venue" % (r0 / 1e6, r1 / 1e18))
else:
    print("     reserve0 = %.6f (6-dp USDC side) and reserve1 = %.6f (18-dp wLXON side)" % (r0 / 1e6, r1 / 1e18))
    print("     spot price 1 wLXON = %.6f USDC ; total depth ~$%.2f ; a $1 swap moves the price a lot"
          % ((r0 / 1e6) / (r1 / 1e18), 2 * (r0 / 1e6)))
PY

cat > "$TMP/tf.py" <<'PY'
# USDC transfer rows from a Blockscout /token-transfers page, appended to a ledger WITH counterparties.
# A count is not evidence: "2 USDC rows" reads as a breach until the counterparty is attached and you
# see they are a swap output plus the addLiquidity that moved it into our own pair. Classes:
#   MINT-FROM-NOTHING  from == 0x0 -- what a CCTP receiveMessage payout looks like
#   VENUE              the far side is a pool / router / factory this project created or used
#   FROM-OTHER         anything else, which is the row worth reading closely
import sys, json
want = {w.upper() for w in (sys.argv[1] if len(sys.argv) > 1 else "USDC USDC.E").split()}
chain, owa, direction, ledger, known = sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]
known = {a.lower() for a in known.split() if a}
ZERO = "0x0000000000000000000000000000000000000000"
raw = sys.stdin.read()
try:
    d = json.loads(raw)
except Exception:
    print("CHALLENGED (Cloudflare or a non-JSON answer -- this is a refusal, not an empty history)")
    raise SystemExit
if not isinstance(d, dict) or "items" not in d:
    print("ERR " + str(d)[:70]); raise SystemExit
items = d["items"] or []
hits = []
for it in items:
    tk = it.get("token") or {}
    sym = (tk.get("symbol") or "").upper()
    if sym not in want:
        continue
    frm = ((it.get("from") or {}).get("hash")) or "?"
    to = ((it.get("to") or {}).get("hash")) or "?"
    dec = int(tk.get("decimals") or 0)
    try:
        amt = int((it.get("total") or {}).get("value") or "0") / (10 ** dec if dec else 1)
    except Exception:
        amt = -1
    if frm.lower() == ZERO:
        cls = "MINT-FROM-NOTHING"
    elif frm.lower() in known or to.lower() in known:
        cls = "VENUE"
    else:
        cls = "FROM-OTHER"
    hits.append("blk=%s %s -> %s %.6f (%s @ %s) %s" % (it.get("block_number"), frm, to, amt,
                  sym, tk.get("address") or "?", cls))
    try:
        with open(ledger, "a") as fh:
            fh.write("%s|%s|%s|%s|%s|%.6f|%s\n" % (chain, owa, direction, frm, to, amt, cls))
    except Exception:
        pass
print("PAGE n=%d USDC=%d %s" % (len(items), len(hits), "more pages exist" if d.get("next_page_params") else "end"))
for h in hits[:12]:
    print("      " + h)
PY

cat > "$TMP/msg.py" <<'PY'
# Look for project addresses anywhere inside a MessageSent payload. Deliberately NOT field-decoded:
# the first attempt assumed Circle's V1 198-byte packed body and printed garbage (destDomain 908172090,
# amounts of 1e38) because the live payloads are the V2 hook format -- 384 to 1600 bytes, variable --
# whose field order is not verified here. A substring test needs no layout assumption: if a project
# address appears anywhere in the payload the message is ours, and the raw bytes are dumped so the
# fields can be read by hand afterwards.
import sys, json
chain, addr = sys.argv[1], sys.argv[2]
ours = [a.lower().replace("0x", "") for a in sys.argv[3].split()]
raw = sys.stdin.read()
try:
    d = json.loads(raw)
except Exception:
    print("%s %s no-json (transport hiccup, not a zero)" % (chain, addr[:10])); raise SystemExit
if "error" in d:
    e = d.get("error") or {}
    print("%s %s refused: %s" % (chain, addr[:10],
          str(e.get("message") if isinstance(e, dict) else e)[:70])); raise SystemExit
logs = d.get("result") or []
hits = 0
sizes = set()
for L in logs:
    body = ((L.get("data") or "0x")[2:]).lower()
    sizes.add(len(body) // 2 - 64)          # minus the offset word and the length word
    found = [a for a in ours if a in body]
    if found:
        hits += 1
        print("HIT blk %s tx %s emitter %s matched %s payload %d bytes" % (
            L.get("blockNumber"), L.get("transactionHash"), (L.get("address") or "")[:10],
            ",".join("0x" + f for f in found), len(body) // 2 - 64))
        print("    data: 0x%s" % body[:700])
print("TOTAL %d OURS %d SIZES %s" % (len(logs), hits, sorted(sizes) if sizes else "n/a"))
PY

cat > "$TMP/sum6.py" <<'PY'
import sys
wal, con, pair = (int(sys.argv[i] or 0) for i in (1, 2, 3))
t = float(sys.argv[4]) * 10 ** 6
print("  USDC (6-decimal) split three ways, because the three buckets mean different things:")
print("     project wallets (EOAs)      %.6f" % (wal / 1e6))
print("     project contracts           %.6f" % (con / 1e6))
print("     the wLXON/USDC pool itself  %.6f   <- venue liquidity, not money waiting to be moved" % (pair / 1e6))
print("  against a ruling of %.2f USDC: %.4f%% of it is in a project wallet or contract."
      % (t / 1e6, 100.0 * (wal + con) / t if t else 0))
print("  (18-decimal USDC, if any, is listed per row above and deliberately NOT added into these sums:"
      " mixing the two raw wei figures is a 1e12 error.)")
PY

cat > "$TMP/verdict.py" <<'PY'
import sys, os
target = int(float(sys.argv[1]) * 10 ** 6)
wallet_wei = int(sys.argv[2] or 0)
contract_wei = int(sys.argv[3] or 0)
pair_wei = int(sys.argv[4] or 0)
held = sys.argv[5]
sends = sys.argv[6]
msgs = int(sys.argv[7] or 0)
ledger = sys.argv[8]
mism = sys.argv[9]

seen, mints, others = [], [], []
if os.path.exists(ledger):
    for line in open(ledger):
        parts = line.rstrip("\n").split("|")
        if len(parts) < 7:
            continue
        chain, owa, direction, frm, to, amt, cls = parts
        seen.append((chain, owa, direction, frm, to, float(amt), cls))
        if cls == "MINT-FROM-NOTHING":
            mints.append(seen[-1])
        elif cls == "FROM-OTHER":
            others.append(seen[-1])

print("  shape 1  funds sit in a project wallet on some chain")
print("           " + ("REFUTED: every project EOA and every project contract read 0.000000 USDC on every"
                       " chain that answered" if (wallet_wei + contract_wei) == 0
                       else "SUPPORTED, holdings = " + held))
if pair_wei:
    print("           note: the wLXON/USDC pool itself holds %.6f USDC. That is venue liquidity produced by"
          " swapping POL, not the ruling's USDC turning up -- section 4 shows those two rows explicitly."
          % (pair_wei / 1e6))
print("  shape 2  burned on a source chain, never minted on Polygon")
print("           " + ("REFUTED for the project wallets: on every chain except Polygon none of them has"
                       " ever signed a transaction, and depositForBurn IS a transaction"
                       if sends == "none" else
                       "CANNOT BE EXCLUDED: " + sends + " has signed transactions on a source chain"))
print("  shape 3  minted on Polygon into an address that is not the provider")
if mints:
    print("           SUPPORTED -- %d transfer(s) FROM THE ZERO ADDRESS, which is what a mint looks like:"
          % len(mints))
    for r in mints[:8]:
        print("             chain %s  %s -> %s  %.6f  (seen by %s)" % (r[0], r[3], r[4], r[5], r[1]))
elif others:
    print("           CANNOT BE EXCLUDED -- %d row(s) whose far side is not a venue we know:" % len(others))
    for r in others[:8]:
        print("             chain %s  %s -> %s  %.6f  (seen by %s)" % (r[0], r[3], r[4], r[5], r[1]))
else:
    print("           REFUTED -- %d USDC row(s) in the indexers, every one of them between a project"
          " address and a venue this project created; none came from 0x0, so nothing was minted" % len(seen))
print("  shape 4  no depositForBurn was ever broadcast")
print("           " + ("SUPPORTED. Nothing in any wallet or contract, nothing minted from the zero address,"
                       " no project wallet has ever signed on a chain that could burn toward Polygon, and no"
                       " MessageSent in the scanned windows names a project address. So the ruling's USDC"
                       " never moved: the shortfall sits upstream of every RPC -- an off-ramp order that was"
                       " never placed, never signed, or is still pending in the owner's account. The pool"
                       " that exists today was filled from POL instead, which is a different decision."
                       if ((wallet_wei + contract_wei) == 0 and sends == "none" and not mints and not others)
                       else "not established -- read the shapes above"))
print("  CCTP messages naming a project address, across every window scanned: %d" % msgs)
if mism != "none":
    print("  chains where USDC could NOT be verified on-chain (address had no code there): " + mism
          + " -> those chains are NOT MEASURED for shape 1, not zero")
print("  gap between the ruling and what project addresses hold: %.6f USDC (%.4f%% funded)"
      % ((target - wallet_wei - contract_wei) / 1e6,
         100.0 * (wallet_wei + contract_wei) / target if target else 0))
PY

# ---------------------------------------------------------------- 0
say "0. the number being chased"
python3 -c 'import sys
t = float(sys.argv[1])
print("  target %.2f USDC = %d wei at 6 decimals. Against the ruled 10,000 wLXON that is %.4f USDC per wLXON."
      % (t, int(t * 10 ** 6), t / 10000))' "$TARGET"

# ---------------------------------------------------------------- 1
say "1. RPC capability: which chain answered, as which chain, and whether it will serve logs at all"
for c in $CHAINS; do
  E=$(ep_for "$c"); [ -n "$E" ] || { note "chain $c: no endpoint configured -> NOT MEASURED"; continue; }
  CID=$(res "$E" eth_chainId '[]')
  case "$CID" in
    ERR:*) note "chain $c ($E): refused -> NOT MEASURED ($CID)"; continue;;
    "") note "chain $c ($E): did not answer eth_chainId -> NOT MEASURED"; continue;;
  esac
  GOT=$(printf '%s' "$CID" | decint)
  [ "$GOT" = "$c" ] || note "chain $c ($E): answered chainId $GOT, NOT $c -> the numbers below are for $GOT"
  HEAD=$(res "$E" eth_blockNumber '[]'); HN=$(printf '%s' "$HEAD" | decint)
  [ -n "$HN" ] || { note "chain $c: head unknown -> logs NOT MEASURED"; continue; }
  LOW=$(python3 "$TMP/subhex.py" "$HEAD" 60)
  LC=$(rpc "$E" eth_getLogs "[{\"fromBlock\":\"$LOW\",\"toBlock\":\"$HEAD\"}]" | python3 "$TMP/logclass.py")
  printf '  chain %-6s head=%-12s address-less probe: %s\n' "$c" "$HN" "$LC"
done

# ---------------------------------------------------------------- 2
say "2. USDC balances: every chain, every wallet and project contract, symbol verified first"
TOTAL_SIX=0
WALLET_SIX=0
CONTRACT_SIX=0
PAIR_SIX=0
HELD=""
MISMATCH=""
for c in $CHAINS; do
  E=$(ep_for "$c"); [ -n "$E" ] || continue
  TOKS=$(usdc_for "$c"); [ -n "$TOKS" ] || { note "chain $c: no USDC address on file -> NOT MEASURED"; continue; }
  for T in $TOKS; do
    SYM=$(res "$E" eth_call "$(callhex "$T" "$(cast sig "symbol()")")" | decstr)
    DEC=$(res "$E" eth_call "$(callhex "$T" "$(cast sig "decimals()")")" | decint)
    if [ -z "$SYM" ]; then
      note "chain $c $T: symbol() unreadable -> NOT MEASURED (its USDC address may be wrong; a balance here would be a guess)"
      MISMATCH="$MISMATCH $c:$T"; continue
    fi
    if [ "$SYM" != "USDC" ]; then note "chain $c $T reports symbol=$SYM -> not USDC, skipped"; continue; fi
    printf '  chain %s  %s  %s  (decimals=%s)\n' "$c" "$SYM" "$T" "${DEC:-?}"
    for A in $EOAS $C_BRIDGE137 $C_MIGRATION137 $C_TIMELOCK137 $C_TIMELOCK137_ALT $C_PAIR137; do
      [ "$c" = 137 ] || case " $C_BRIDGE137 $C_MIGRATION137 $C_TIMELOCK137 $C_TIMELOCK137_ALT $C_PAIR137 " in
        *" $A "*) continue;;
      esac
      N=$(res "$E" eth_call "$(callhex "$T" "0x70a08231$(padword "$A")")" | decint)
      case "$N" in
        ""|ERR:*) printf '     %-42s unreadable (%s)\n' "$A" "${N:-empty}"; continue;;
      esac
      printf '     %-42s %18s%s\n' "$A" "$(python3 "$TMP/scale.py" "$N" "${DEC:-6}")" \
        "$( [ "$A" = "$C_PAIR137" ] && printf '   <- the venue itself, not a project wallet' )"
      if [ "$N" != "0" ]; then
        HELD="$HELD $c:$T:$A:$(python3 "$TMP/scale.py" "$N" "${DEC:-6}")"
        # three different things, kept apart on purpose: what a project WALLET holds, what a project
        # CONTRACT holds, and what the POOL holds. The pool's 1.224879 USDC is venue liquidity produced by
        # swapping POL (section 4 shows those exact two rows); counting it as "the missing funds turned up"
        # would be the same category error as counting a wallet's own LP as free money.
        if [ "${DEC:-6}" = "6" ]; then
          case "$A" in
            "$C_PAIR137") PAIR_SIX=$(addn "$PAIR_SIX" "$N");;
            "$W_deployer"|"$W_founder"|"$W_developer"|"$W_validator"|"$W_attestor") WALLET_SIX=$(addn "$WALLET_SIX" "$N");;
            *) CONTRACT_SIX=$(addn "$CONTRACT_SIX" "$N");;
          esac
          TOTAL_SIX=$(addn "$TOTAL_SIX" "$N")
        fi
      fi
    done
  done
done
python3 "$TMP/sum6.py" "$WALLET_SIX" "$CONTRACT_SIX" "$PAIR_SIX" "$TARGET"

# ---------------------------------------------------------------- 3
say "3. could a burn even have happened here? depositForBurn is an OUTBOUND tx from a USDC holder"
SOURCE_SENDS=""
for c in $CHAINS; do
  E=$(ep_for "$c"); [ -n "$E" ] || continue
  printf '  chain %s (%s)\n' "$c" "$(sym_for "$c")"
  for A in $EOAS; do
    NC=$(res "$E" eth_getTransactionCount "[\"$A\",\"latest\"]" | decint)
    BN=$(res "$E" eth_getBalance "[\"$A\",\"latest\"]" | decint)
    case "$NC" in ""|ERR:*) printf '     %-42s txcount unreadable\n' "$A"; continue;; esac
    printf '     %-42s txcount=%-5s native=%s\n' "$A" "$NC" \
      "$(python3 -c 'import sys;print("%.6f"%(int(sys.argv[1] or 0)/1e18))' "${BN:-0}")"
    if [ "$NC" = "0" ]; then
      printf '       -> has never signed a transaction on %s, so it cannot have burned or sent USDC there\n' "$c"
    elif [ "$c" != "137" ]; then
      SOURCE_SENDS="$SOURCE_SENDS $c:$A(txcount $NC)"
    fi
  done
done

# ---------------------------------------------------------------- 4
say "4. indexer: has any USDC ever moved in or out of a project address, and with whom"
for c in $CHAINS; do
  IX=$(idx_for "$c"); [ -n "$IX" ] || { note "chain $c: no indexer configured -> transfer history NOT MEASURED"; continue; }
  printf '  chain %s via %s\n' "$c" "${IX#https://}"
  for A in $EOAS; do
    for f in to from; do
      out=$(curl -s --max-time 25 -A 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36' \
            "$IX/api/v2/addresses/$A/token-transfers?filter=$f" | python3 "$TMP/tf.py" "USDC USDC.E" "$c" "$A" "$f" "$TMP/ledger.txt" "$KNOWN_VENUES")
      printf '     %-42s %-5s %s\n' "$A" "$f" "$(printf '%s' "$out" | head -1)"
      printf '%s\n' "$out" | sed -n '2,13p'
      sleep "$SLEEP"
    done
  done
done

# ---------------------------------------------------------------- 5
say "5. the Polygon pool side: does a wLXON/USDC pool exist, and does the migration reserve anything"
E=$(ep_for 137)
if [ -n "$E" ]; then
  for U in $USDC_137; do
    SEL=$(cast sig "getPair(address,address)")
    P=$(res "$E" eth_call "$(callhex "$FACTORY_137" "$SEL$(padword "$C_WLXON137")$(padword "$U")")")
    python3 "$TMP/pairline.py" getpair "$P" "$U"
  done
  GR=$(res "$E" eth_call "$(callhex "$C_PAIR137" "$(cast sig "getReserves()")")")
  python3 "$TMP/reserves.py" "$GR"
  RS=$(res "$E" eth_call "$(callhex "$C_MIGRATION137" "$(cast sig "reserveBalance()")")" | decint)
  printf '     migration.reserveBalance() = %s\n' "$(python3 -c 'import sys
s = sys.argv[1]
print("unreadable" if not s.lstrip("-").isdigit() else "%.6f (a wallet balance, and the window is open)" % (int(s)/10**6))' "${RS:-}")"
  SUP=$(res "$E" eth_call "$(callhex "$C_WLXON137" "$(cast sig "totalSupply()")")" | decint)
  printf '     new wLXON totalSupply = %s\n' "$(python3 -c 'import sys;print("%.6f"%(int(sys.argv[1] or 0)/1e18))' "${SUP:-0}")"
  note "reserve 0 with the migration window open means every migrate() reverts InsufficientReserve -- the"
  note "same missing money seen from the other side, and a second reason the USDC leg matters."
fi

# ---------------------------------------------------------------- 6
say "6. the recoverable shape: a MessageSent naming a project address, with no mint on Polygon"
MSGTOP=$(cast sig-event "MessageSent(bytes)")
note "topic derived at run time, not copied: MessageSent(bytes) = $MSGTOP"
note "the previous revision pinned a different topic AND five messenger addresses whose code size is 0"
note "bytes, so its 'no burns' was a measurement of my notes rather than of the chains."
OUR_MSG=0
for c in $CHAINS; do
  [ "$c" = 137 ] && continue           # Polygon is the destination; a burn there would be outbound
  E=$(ep_for "$c"); [ -n "$E" ] || continue
  HEAD=$(res "$E" eth_blockNumber '[]'); HN=$(printf '%s' "$HEAD" | decint)
  [ -n "$HN" ] || { note "chain $c: no head -> MessageSent NOT MEASURED"; continue; }
  CH=$(chunk_for "$c")
  SPAN=$(addn 0 "$((CH * MAX_CHUNKS))")
  LOW=$(python3 "$TMP/subhex.py" "$HEAD" "$CH" "$MAX_CHUNKS")
  T0=$(rpc "$E" eth_getBlockByNumber "[\"$LOW\",false]" | python3 "$TMP/blkts.py")
  T1=$(rpc "$E" eth_getBlockByNumber "[\"$HEAD\",false]" | python3 "$TMP/blkts.py")
  printf '  chain %-6s head=%-11s %s blocks back = %s\n' "$c" "$HN" "$SPAN" \
    "$(python3 "$TMP/hrs.py" "$T0" "$T1")"
  for A in "$TM2" "$MT2"; do
    CB=$(res "$E" eth_getCode "[\"$A\",\"latest\"]")
    CBN=$(printf '%s' "$CB" | python3 -c 'import sys
s = sys.stdin.read().strip()
print(max(0, len(s)//2 - 1) if s.startswith("0x") else "")')
    if [ -z "$CBN" ] || [ "$CBN" = "0" ]; then
      printf '     %s no code on %s (%s bytes) -> candidate rejected, this chain is NOT covered\n' "${A:0:10}" "${E#https://}" "${CBN:-?}"
      continue
    fi
    total=0; ours=0; stopped=""
    k=0
    while [ "$k" -lt "$MAX_CHUNKS" ]; do
      hi=$(python3 "$TMP/subhex.py" "$HEAD" "$CH" "$k")
      lo=$(python3 "$TMP/subhex.py" "$HEAD" "$CH" "$((k + 1))")
      d=$(rpc "$E" eth_getLogs "[{\"address\":\"$A\",\"topics\":[\"$MSGTOP\"],\"fromBlock\":\"$lo\",\"toBlock\":\"$hi\"}]")
      printf '%s' "$d" | python3 "$TMP/msg.py" "$c" "$A" "$EOAS" > "$TMP/msg.out"
      line=$(grep '^TOTAL ' "$TMP/msg.out" | tail -1)
      case "$line" in
        TOTAL*) : ;;
        *) stopped=$(grep -v '^TOTAL ' "$TMP/msg.out" | grep -v '^    data:' | grep -v '^HIT ' | tail -1)
           stopped="${stopped:-the scan returned nothing this parser recognised}"; break;;
      esac
      sed -n '/^HIT /,/    data:/p' "$TMP/msg.out" | sed 's/^/     /'
      t=$(printf '%s' "$line" | awk '{print $2}')
      o=$(printf '%s' "$line" | awk '{print $4}')
      total=$(addn "$total" "$t"); ours=$(addn "$ours" "$o")
      k=$((k + 1))
    done
    [ -n "$stopped" ] && printf '     %s ...scan stopped early: %s\n' "${A:0:10}" "$stopped"
    OUR_MSG=$(addn "$OUR_MSG" "$ours")
    printf '     %s (%s bytes of code) MessageSent scanned: %s, of which %s name a project address\n' \
      "${A:0:10}" "$CBN" "$total" "$ours"
  done
  sleep "$SLEEP"
done
note "Recovery path, if a burn tx hash ever turns up: GET"
note "  https://iris-api.circle.com/v2/attestations/<destinationDomain>/<txHash>"
note "then one receiveMessage call on Polygon pays the recipient in the message. Both URLs were probed"
note "in the session that wrote this file and answer (404 for a hash with no message), so the route is"
note "live -- but the hash has to come from an account view this repo does not have."

# ---------------------------------------------------------------- 7
say "7. which of the four shapes the measurements support"
python3 "$TMP/verdict.py" "$TARGET" "$WALLET_SIX" "$CONTRACT_SIX" "$PAIR_SIX" "${HELD:-none}" "${SOURCE_SENDS:-none}" "$OUR_MSG" "$TMP/ledger.txt" "${MISMATCH:-none}"

# ---------------------------------------------------------------- 8
say "8. what this run cannot see"
note "an exchange's withdrawal queue, an unfilled on/off-ramp order, or a wire in flight. That is a login"
note "page, not a chain, and it is the only place the answer for shape 4 can still be found."
note "chains whose transfer history came back CHALLENGED or refused above: there, 'no USDC seen' is NOT"
note "established -- only 'this endpoint would not say'. Free indexers gate history behind Cloudflare and"
note "free RPCs charge for archive: publicnode refused state older than ~10000 blocks outright."
note "addresses that are not in this script. Every conclusion in section 7 is about the five project"
note "wallets and the six project contracts; a burn from an address the repo never recorded would show up"
note "as a mint here, and as nothing at all in section 3."
note "MessageSent scanning covers MAX_CHUNKS chunks of chunk_for(chain) blocks behind the head -- see the"
note "hours each chain printed. A burn older than that window is NOT excluded by section 6."
note "chain 724 has no USDC contract at all, so it is out of scope by construction, not by omission."

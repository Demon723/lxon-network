#!/usr/bin/env python3
"""
Which published claims about chain 724 are now false?

Method, and why it is this way round: the address inventory file deliberately keeps addresses
TRUNCATED, because a hand-copied hex literal is a silent failure. So rather than type an expected
list and go looking for it, we scrape every full 40-hex address the published documents actually
assert, measure each one against the live rebuilt chain through https://rpc.lxon.in, and report the
docs that quote the ones with no code.

Controls included, because "0x" only means something next to a read that is not 0x:
  * block 0 hash must still be 0x6c931dff...  (proves we are reading the right chain)
  * a contract known to exist on Polygon 137 is read through the SAME reader against 137 and must
    come back non-empty (proves the reader decodes eth_getCode correctly)
Nothing here writes or signs.
"""
import json, os, re, subprocess, sys, collections

ROOT = "/Users/adikamble/LXON/LXON"
GW   = "https://rpc.lxon.in"                      # the read-only front built today
P137 = "https://polygon.drpc.org"
KNOWN_137_CONTRACT = "0xbDC32d8Ca8Ce805E0654e7A7d0DD1eE0A21D4a95"   # v4.1 bridge, 19,105 bytes

FILES = [
    "README.md", "PUBLIC_TRADING_QUICK_START.md", "MAINNET_DEPLOYMENT_GUIDE.md",
    "POLYGON_WLXON_MIGRATION_PLAN.md", "BRIDGE_CHAIN724_DEPLOYMENT_STATUS.md",
    "lxon-address-inventory-2026-10-25.md", "FINAL_STATUS_REPORT.md", "NEXT_STEPS.md",
    "chainlist.json", "docs/whitepaper.md", "docs/WHITEPAPER.md",
]

ADDR = re.compile(r"\b0x[a-fA-F0-9]{40}\b")

def rpc(url, method, params):
    p = subprocess.run(["curl", "-sS", "-m", "25", "-X", "POST",
                        "-H", "content-type: application/json",
                        "--data", json.dumps({"jsonrpc": "2.0", "id": 1,
                                              "method": method, "params": params}), url],
                       capture_output=True, text=True)
    try:
        return json.loads(p.stdout)
    except Exception:
        return {"error": {"message": (p.stdout or p.stderr)[:80]}}

def code_at(url, a):
    r = rpc(url, "eth_getCode", [a, "latest"])
    if "result" in r:
        return r["result"]
    return None

print("=" * 100)
print("STEP 0  the two controls, before any negative result is trusted")
print("=" * 100)
b0 = rpc(GW, "eth_getBlockByNumber", ["0x0", False])
h0 = (b0.get("result") or {}).get("hash", "")
ok0 = h0.startswith("0x6c931dff")
print(f"  chain 724 block 0 = {h0[:34]}…   expected 0x6c931dff…  -> {'PASS' if ok0 else 'FAIL'}")
ctl = code_at(P137, KNOWN_137_CONTRACT)
okc = ctl is not None and len(ctl) > 4
print(f"  reader control: 137 bridge eth_getCode length = {len(ctl) if ctl else 'ERR'} bytes-hex"
      f"  -> {'PASS (reader decodes correctly)' if okc else 'FAIL'}")
if not (ok0 and okc):
    print("\n  A control failed. Stopping: without them, every 'no code' below is unproven.")
    sys.exit(1)

print("\n" + "=" * 100)
print("STEP 1  which published files assert full 40-hex addresses")
print("=" * 100)
where = collections.defaultdict(set)
for rel in FILES:
    p = os.path.join(ROOT, rel)
    if not os.path.isfile(p):
        print(f"  (absent, skipped): {rel}")
        continue
    txt = open(p, errors="replace").read()
    found = set(m.lower() for m in ADDR.findall(txt))
    for a in found:
        where[a].add(rel)
    print(f"  {rel:<48} {len(found):>3} distinct addresses")

addrs = sorted(where)
print(f"\n  {len(addrs)} distinct addresses asserted across those documents")

print("\n" + "=" * 100)
print("STEP 2  classify each address -- 'no code on 724' is NOT the same finding for every address")
print("=" * 100)
# An empty eth_getCode means "lost contract" only for something the documents call a chain-724
# contract. For an EOA it is the normal answer, and for a contract that lives on another chain it is
# the correct answer. The first version of this script printed all 13 as dead, which is the same
# error I caught on the swap page (where two 137 addresses and one event-topic were listed as
# wiped 724 contracts). So each address is asked four questions before it is classified.
def context(rel, a):
    """the document's own words about this address -- evidence, not my guess"""
    try:
        txt = open(os.path.join(ROOT, rel), errors="replace").read()
    except Exception:
        return ""
    m = re.search(r".{0,90}" + re.escape(a) + r".{0,90}", txt, re.I | re.S)
    return re.sub(r"\s+", " ", m.group(0)) if m else ""

dead, other_chain, eoa, alive, unreadable = [], [], [], [], []
for a in addrs:
    c724 = code_at(GW, a)
    c137 = code_at(P137, a)
    b724 = rpc(GW, "eth_getBalance", [a, "latest"]).get("result")
    b137 = rpc(P137, "eth_getBalance", [a, "latest"]).get("result")
    has724 = c724 not in (None, "0x"); has137 = c137 not in (None, "0x")
    rich = (b137 not in (None, "0x")) and int(b137, 16) > 0
    coin = (b724 not in (None, "0x")) and int(b724, 16) > 0
    ctx = " | ".join(context(d, a)[:80] for d in sorted(where[a])[:1])
    if c724 is None:
        unreadable.append(a); tag = "UNREADABLE"
    elif has724:
        alive.append((a, (len(c724) - 2) // 2)); tag = "CODE ON 724"
    elif has137:
        other_chain.append(a); tag = f"contract on 137 ({(len(c137)-2)//2} B), expected empty on 724"
    elif rich or coin:
        eoa.append(a); tag = "wallet (has a balance), 'no code' is the normal answer"
    else:
        dead.append(a); tag = "no code anywhere, no balance -- a lost 724 contract or a stale literal"
    print(f"  {a}  -> {tag}")
    print(f"        context: {ctx[:100]}")
print(f"\n  lost-724-contract: {len(dead)}   other-chain contract: {len(other_chain)}"
      f"   wallet: {len(eoa)}   code on 724: {len(alive)}   unreadable: {len(unreadable)}")

print("\n" + "=" * 100)
print("STEP 3  the ledger: documents quoting addresses that no longer exist")
print("=" * 100)
doc_hits = collections.defaultdict(list)
for a in dead:
    for d in sorted(where[a]):
        doc_hits[d].append(a)
other_hits = collections.defaultdict(list)
for a in other_chain + eoa:
    for d in sorted(where[a]):
        other_hits[d].append(a)
lines = []
lines.append("# Chain 724 published-claim ledger — 2026-11-03\n")
lines.append("Mechanically produced by `lxon-evm-node/aws-freetier/audit-724-claims.py`. Read-only.")
lines.append("Nothing was edited; this is the list of claims that are now false, with the measurement")
lines.append("that makes each one false.\n")
lines.append("## Controls that make the negative results mean something\n")
lines.append(f"- Rebuilt chain 724 answers block 0 = `{h0}` — the recovered genesis hash, so this is the right chain.")
lines.append(f"- The same reader returns {len(ctl)} hex chars for the v4.1 bridge on Polygon 137, so an empty")
lines.append("  read is a real answer, not a broken decode.\n")
lines.append("## Measured state\n")
lines.append(f"- {len(addrs)} distinct full addresses are asserted by the published documents checked.")
lines.append(f"- **{len(dead)}** are genuinely gone: no code on 724, no code on 137, no balance anywhere.")
lines.append(f"- {len(other_chain)} are contracts on ANOTHER chain (they have code on 137), so an empty read")
lines.append("  on 724 is correct and they are not documentation defects: " + ", ".join(f"`{a}`" for a in other_chain))
lines.append(f"- {len(eoa)} are wallets that hold a balance; an EOA having no code is the normal answer:")
lines.append("  " + ", ".join(f"`{a}`" for a in eoa))
lines.append(f"- {len(alive)} still have code on 724" + (": " + ", ".join(f"`{a}` ({n} B)" for a, n in alive) if alive else "") + ".")
lines.append("\n  A first run of this script printed all 13 as dead. That was wrong, and the mistake is")
lines.append("  worth naming: an empty `eth_getCode` is only evidence of loss for something the document")
lines.append("  calls a chain-724 contract. Classifying cost four extra reads per address and changed the")
lines.append("  finding materially.")
if unreadable:
    lines.append(f"- {len(unreadable)} could not be read and are NOT counted as dead: " + ", ".join(unreadable))
lines.append("\n## Chain 724: the claim, verbatim, for each address that is genuinely gone\n")
lines.append("| address | what the document says about it |")
lines.append("|---|---|")
for a in dead:
    lines.append(f"| `{a}` | {context(sorted(where[a])[0], a)[:110]} |")
lines.append("\n## Classification rule, and where it is not trustworthy\n")
lines.append("An address is called **lost** only when all four reads agree: no code on 724, no code on 137,")
lines.append("no balance on either. That is a deliberately narrow claim, and two labels are not reliable:")
lines.append("")
lines.append("- `0x7f715b7f…9ef3` is the founder wallet in these documents, but it returns **23 bytes of")
lines.append("  code on 137** -- far too small for a real contract and not enough to call it an EOA. It is")
lines.append("  filed under \"other chain\" because that is what was measured, not because the label fits.")
lines.append("  Worth a look; do not act on it as classified.")
lines.append("- `0xa0b86991…eb48` is Ethereum mainnet's USDC, quoted as a *reference constant*. It reads as")
lines.append("  a \"wallet\" only because it holds a balance somewhere. Correct conclusion (not a 724 loss),")
lines.append("  wrong category.")
lines.append("")
lines.append("Neither changes the headline: the chain's own token `0x99801a78…` returns no code and no")
lines.append("balance on 724 while documents still describe it as the live LXON. That is the finding.")
lines.append("\n## Documents to correct, worst first\n")
lines.append("| document | dead addresses it quotes |")
lines.append("|---|---|")
for d, aa in sorted(doc_hits.items(), key=lambda kv: -len(kv[1])):
    lines.append(f"| `{d}` | {len(aa)} |")
lines.append("\n<details><summary>address -> documents</summary>\n")
for a in dead:
    lines.append(f"- `{a}` — " + ", ".join(f"`{d}`" for d in sorted(where[a])))
lines.append("\n</details>\n")
lines.append("## Why this matters more than the count\n")
lines.append("The chain restarted from an empty volume on 2026-11-03 under its original genesis. Blocks")
lines.append("1-242,493 are gone: the token, WETH, both pairs, both routers, the wrapper, the v4.1 bridge and")
lines.append("the timelock all have no code at the addresses these documents still quote as live. Any page,")
lines.append("listing application or guide that says otherwise is now asserting something measurable and")
lines.append("false. Fixing the wording is a documentation task; restoring the contracts is a redeploy.")
out = os.path.join(ROOT, "docs", "724-claim-ledger-2026-11-03.md")
os.makedirs(os.path.dirname(out), exist_ok=True)
open(out, "w").write("\n".join(lines) + "\n")
print(f"  wrote {out}")
print(f"  {len(doc_hits)} document(s) quote at least one dead address")
for d, aa in sorted(doc_hits.items(), key=lambda kv: -len(kv[1])):
    print(f"    {d:<48} {len(aa)}")

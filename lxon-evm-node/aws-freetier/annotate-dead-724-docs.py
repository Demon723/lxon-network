#!/usr/bin/env python3
"""Annotate markdown that quotes chain-724 addresses destroyed by the 2026-11-03 restart.

Why a script and not hand edits: 67 markdown files quote at least one of the nine literals, and a
hand pass would fix the three I happened to open and leave the rest asserting a live token.

It MEASURES before it writes. The control rows are what make an empty eth_getCode mean anything --
without them a broken reader would produce the same answer as a destroyed contract, and this script
would then annotate 67 files with a lie. If a control comes back empty the script refuses.

Read-only toward the chain; writes only .md files under the repo, only between its own markers, and
never touches .json / .js / .ts / .sh (see the ledger -- those are executable and need a decision,
not a comment).

usage:
  annotate-dead-724-docs.py --check     # report what would change (no writes)
  annotate-dead-724-docs.py --apply     # write the notices
  annotate-dead-724-docs.py --control   # prove a clean file is left alone
"""
import json, os, re, subprocess, sys, datetime

RPC_724 = "https://rpc.lxon.in"
RPC_137 = ["https://polygon-bor-rpc.publicnode.com", "https://polygon.drpc.org"]
MARK = "lxon-724-restart-notice"
GENESIS_724 = "0x6c931dffbac6d832d33efb81d31880391cb637eed456cc838bf9689595ecc588"

# The date the notice blocks print. It was hardcoded to the day this was first run, which meant every
# file annotated after that carried a measurement date that had not happened yet -- a block whose own
# header calls itself a measurement cannot carry a remembered date.
TODAY = datetime.date.today().isoformat()

# what the documents call each one, so a reader can tell which row the notice applies to.
#
# This set used to be the nine literals I happened to grep for first, and it is a SUPERSET of nothing:
# check-dead-724-addr.py measures ten more (the bridge, both wrappers, WETH9, the two pairs, the two
# routers, XON). The result was two tools disagreeing about the same corpus while both looked healthy --
# this script printed "68 markdown files ... 0 to change, 68 already carried the notice" and the gate
# printed 26 markdown files with no notice, because 26 of them name one of the eight addresses this
# script had never heard of. Every address here is re-MEASURED against 724 before a word is written
# (measure() refuses if any control fails), so the list can be long without any of it being assumed.
DEAD = {
    "0x99801a78639975d448eeb2f8a807738dc8df67dc": "LXON (LxonTokenEnhanced)",
    "0xc0177883c0c662870855660495c697385fe040f5": "LXON, native (per the bridge docs)",
    "0x86a7da576852126c8421f7a25f8de7cedf9553c4": "WETH",
    "0x14711906a15be7cd861f0378d26b65d37bc5a9df": "USDC",
    "0x692d0047323034514686ef57edfc26dbba53f87b": "LxonBridgeMultiSig",
    "0x8e5d97d117cada19c695cd529b79d8229637dfbd": "MultiSigAttester",
    "0x2f2671b38c0291873a6fc5f9bf013a36137332d9": "TimelockController (724)",
    "0x7999b8c0662fe6ae3d82ac6988718189e66f9b4b": "Validator / attester",
    "0x283697339fc32e286951d9f94fa64082142cbc37": "attestor key #1",
    # the eight the gate measures and this script did not, added 2026-11-05 after the two tools'
    # counts disagreed; labels matched to check-dead-724-addr.py CANDIDATES
    "0x9b15fee95995a15da2d64d8e2958f9792d5d6a25": "v4.1 attested bridge on 724",
    "0xc0cf6b0e6c5a0705f319ba5c629a6bc7e82fef00": "LXONWrapper / wLXON on 724",
    "0xcb742c31f0815648e13ff24d8131b89075ff32e2": "WETH9 on 724",
    "0x272a3ed4b91112005ade5b4161af1adc856ab3f4": "LXON/WETH pair on 724",
    "0xd969211d7efb154e86d41a80ff0fd3cc0eb70468": "V2 router on 724",
    "0x8e90675e054826f61745c0016b895cdc4f220ebc": "wLXON/LXON peg pair on 724",
    "0xaa0e4bb075f108b34dc0e279a7747980c76b8d75": "second router on 724",
    "0xe801e058b4c9f77dd60980a80f7607a50afe1799": "XON, the second 724 token the old list recommended",
}
BRIDGE_137 = "0xbDC32d8Ca8Ce805E0654e7A7d0DD1eE0A21D4a95"   # expected ~19,105 bytes
WLXON_137 = "0x7A3c0C34f157EfDD3E4913c5224C15E645469093"    # expected ~2,106 bytes

# The ledger quotes these literals as the thing under audit; wrapping it in its own notice would
# make the evidence file look like another victim.
EXCLUDE = {"docs/724-claim-ledger-2026-11-03.md"}


def rpc(url, method, params):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params})
    p = subprocess.run(["curl", "-sS", "-m", "25", "-X", "POST",
                        "-H", "content-type: application/json", "-d", body, url],
                       capture_output=True, text=True)
    if p.returncode != 0:
        return None, "curl: %s" % (p.stderr.strip()[:120] or "rc=%d" % p.returncode)
    try:
        got = json.loads(p.stdout)
    except Exception:
        return None, "not JSON: %r" % p.stdout[:120]
    if "error" in got:
        return None, "rpc error: %s" % json.dumps(got["error"])[:120]
    return got.get("result"), None


def rpc_any(urls, method, params):
    """Try each endpoint in order. drpc and publicnode both serve eth_getCode, and either one
    occasionally stalls -- a single hard-coded control RPC turns an upstream hiccup into a refusal,
    which is the right failure mode but the wrong reason to be unable to check the docs."""
    errs = []
    for u in urls:
        res, err = rpc(u, method, params)
        if err:
            errs.append("%s: %s" % (u.split("//")[1][:28], err))
            continue
        return res, u, errs
    return None, None, errs


def die(msg):
    print("REFUSING TO WRITE: " + msg)
    sys.exit(1)


def code_bytes(urls, addr):
    raw, used, errs = rpc_any(urls, "eth_getCode", [addr, "latest"])
    if raw is None:
        die("no control RPC answered eth_getCode for %s (%s)" % (addr, "; ".join(errs)))
    if not isinstance(raw, str) or not raw.startswith("0x"):
        die("unexpected eth_getCode payload for %s at %s: %r" % (addr, used, raw))
    return (len(raw) - 2) // 2


def measure():
    """Return (addresses proven empty on 724, (bridge_bytes, wlxon_bytes)), or refuse.

    The control sizes travel with them because the notice block QUOTES those numbers. Hard-coding
    "19,105 bytes" in the prose is the mirror-image of a self-validating check: it stays true for a
    while, then it silently describes a chain nobody re-read, and the next reader trusts it because
    it looks like a measurement.
    """
    cid, used, errs = rpc_any([RPC_724], "eth_chainId", [])
    if cid is None:
        die("724 RPC did not answer eth_chainId (%s)" % "; ".join(errs))
    if cid != "0x2d4":
        die("%s answers chainId %s, not 0x2d4 -- wrong node, not the rebuilt 724" % (used, cid))
    blk, used, errs = rpc_any([RPC_724], "eth_getBlockByNumber", ["0x0", False])
    if blk is None:
        die("724 RPC did not answer eth_getBlockByNumber(0) (%s)" % "; ".join(errs))
    if not isinstance(blk, dict) or blk.get("hash") != GENESIS_724:
        die("block 0 is not the recovered genesis hash -- the reads below would be meaningless")

    b1 = code_bytes(RPC_137, BRIDGE_137)
    b2 = code_bytes(RPC_137, WLXON_137)
    if b1 < 19000 or b2 < 2000:
        die("controls came back small (bridge %d B, wLXON %d B) -- the reader is not trustworthy "
            "today, so an empty read on 724 proves nothing" % (b1, b2))
    print("controls: 724 block 0 OK, v4.1 bridge on 137 = %d bytes, wLXON on 137 = %d bytes"
          % (b1, b2))

    gone = []
    for addr, label in DEAD.items():
        n = code_bytes([RPC_724], addr)
        if n != 0:
            print("  still live on 724, skipping: %s (%s) = %d bytes" % (addr, label, n))
        else:
            gone.append(addr)
    if not gone:
        die("no address in the list reads empty on 724 -- nothing to annotate; check the RPC")
    print("proven empty on 724: %d of %d" % (len(gone), len(DEAD)))
    return set(gone), (b1, b2)


def notice_ranges(lines):
    """Closed begin/end pairs, same rule check-dead-724-addr.py uses: returns (ranges, dangling),
    where dangling is the line index of a :begin that never met its :end.

    Duplicated rather than imported on purpose. Importing the gate's function would make the gate
    grade the annotator's own output, and the pair would agree with each other while both drifted from
    the files on disk -- the failure this whole toolset exists to avoid. What is NOT duplicated is the
    behaviour: if either rule changes, the two tools disagree out loud as a non-zero markdown residual.
    """
    ranges, open_at = [], None
    for i, l in enumerate(lines):
        if MARK + ":begin" in l and open_at is None:
            open_at = i
        if MARK + ":end" in l and open_at is not None:
            ranges.append((open_at, i))
            open_at = None
    return ranges, open_at


def notice(addrs, controls):
    b1, b2 = controls
    lines = [
        "<!-- %s:begin -->" % MARK,
        "> ⚠️ **Chain 724 addresses quoted in this file no longer exist.** Measured "
        "%s against `https://rpc.lxon.in`. Chain 724 restarted from an empty volume on "
        "2026-11-03 under its original genesis (block 0 `0x6c931dff...`), so blocks 1-242,493 -- "
        "and every contract created in them -- are gone. Each address below returns **0 bytes of "
        "code** on 724 today:" % (TODAY,),
        ">",
    ]
    for a in sorted(addrs):
        lines.append("> - `%s` - %s" % (a, DEAD[a]))
    lines += [
        ">",
        "> The control that makes those empty reads evidence, measured by the same script on the "
        "same day: the v4.1 bridge on Polygon 137 reads %d bytes and wLXON reads %d bytes, so a "
        "working reader does return bytes when something is there. Read everything below as history "
        "or as a redeploy target, not as live state. Per-address ledger and method: "
        "`docs/724-claim-ledger-2026-11-03.md`." % (b1, b2),
        "<!-- %s:end -->" % MARK,
    ]
    return "\n".join(lines)


def targets(root, gone):
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in
                       ("node_modules", ".git", "dist", "build", "cache", "artifacts")]
        for fn in filenames:
            if not fn.endswith(".md"):
                continue
            p = os.path.join(dirpath, fn)
            if os.path.relpath(p, root) in EXCLUDE:
                continue
            try:
                text = open(p, encoding="utf-8").read()
            except Exception:
                continue
            low = text.lower()
            hits = {a for a in gone if a in low}
            if hits:
                out.append((p, text, hits))
    return out


def insert(text, block):
    """Put the block after the first H1, or at the top when the file has no leading heading."""
    lines = text.split("\n")
    for i, l in enumerate(lines[:12]):
        if l.startswith("# "):
            head = "\n".join(lines[:i + 1])
            rest = "\n".join(lines[i + 1:])
            return head + "\n\n" + block + "\n" + rest.lstrip("\n")
    return block + "\n" + text


def census(root):
    """Print the inventory the ledger quotes. Counts every file kind, not just markdown, because the
    executables are the redeploy backlog and the reader needs to know they were left alone on purpose.
    Uses the same control gate as the write path: an inventory is only worth printing if the reads
    behind it are trustworthy today."""
    gone, _ctrl = measure()
    only_md_free = {".git", "node_modules"}
    by_ext, md_total, md_marked, md_marker = {}, 0, 0, 0
    json_total, json_broadcast = 0, 0
    total = 0
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in only_md_free]
        for fn in filenames:
            p = os.path.join(dirpath, fn)
            try:
                text = open(p, encoding="utf-8", errors="ignore").read()
            except Exception:
                continue
            if not any(a in text.lower() for a in gone):
                continue
            total += 1
            ext = os.path.splitext(fn)[1] or "(no ext)"
            by_ext[ext] = by_ext.get(ext, 0) + 1
            if ext == ".md":
                md_total += 1
                # Counted on a CLOSED pair, the way the gate counts it. The marker-string count is
                # printed alongside when the two differ, because the ledger quotes the old figure and
                # a silently redefined column would make this run contradict the archived one.
                if notice_ranges(text.split("\n"))[0]:
                    md_marked += 1
                if MARK + ":begin" in text:
                    md_marker += 1
            if ext == ".json":
                json_total += 1
                if os.sep + "broadcast" + os.sep in p:
                    json_broadcast += 1
    print("files quoting a proven-dead 724 address: %d (.git and node_modules skipped)" % total)
    for k, v in sorted(by_ext.items(), key=lambda x: -x[1]):
        print("  %-10s %d" % (k, v))
    print("markdown: %d, carrying a CLOSED notice block: %d%s"
          % (md_total, md_marked,
             "" if md_marker == md_marked else
             " (marker string present in %d -- %d file(s) whose :begin never met its :end)"
             % (md_marker, md_marker - md_marked)))
    print(".json: %d, of which foundry broadcast records: %d" % (json_total, json_broadcast))
    print("non-markdown left untouched on purpose: %d" % (total - md_total))


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "--check"
    if mode not in ("--check", "--apply", "--control", "--census"):
        die("usage: --check | --apply | --census | --control")
    # ANNOTATE_ROOT is the worktree override, matching REPO_ROOT in scripts/check-listing-truth.sh.
    # The gate scans two roots (the repo and the attested-bridge worktree) and this script walked one,
    # so every count the two printed was measured over a different corpus.
    default_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    root = os.path.abspath(os.environ.get("ANNOTATE_ROOT", default_root))
    if not os.path.isdir(root):
        die("ANNOTATE_ROOT=%r is not a directory -- refusing to walk a path that does not exist" % root)
    if mode == "--census":
        census(root)
        return
    gone, ctrl = measure()
    files = targets(root, gone)

    if mode == "--control":
        # Control: a file that quotes none of them must survive a byte for byte.
        probe = os.path.join(root, "lxon-evm-node", "aws-freetier", "README.md")
        before = open(probe, encoding="utf-8").read()
        hits = {a for a in gone if a in before.lower()}
        print("control file %s quotes %d of the dead literals" % (probe, len(hits)))
        if hits:
            print("  (it is a legitimate target: %s)" % ", ".join(sorted(hits)))
        print("control ran; nothing written")
        return

    changed = skipped = 0
    for path, text, hits in sorted(files):
        # Idempotent against a properly CLOSED pair only. The previous guard was `MARK+":begin" in
        # text`, which is exactly the hole check-dead-724-addr.py closed on 2026-11-05: a file whose
        # begin marker lost its end (hand-edited, or an interrupted write) reads as "noticed" to this
        # script, so re-running it silently leaves a dangling block that excuses every line under it
        # at the gate. Checking the closed pair makes that file a target again instead of a pass.
        rng, _dangling = notice_ranges(text.split("\n"))
        if rng:
            skipped += 1
            continue
        new = insert(text, notice(hits, ctrl))
        if mode == "--apply":
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(new)
        changed += 1
        print("  %-6s %s  (%d dead)" % ("would" if mode == "--check" else "wrote",
                                        os.path.relpath(path, root), len(hits)))
    print("\n%d markdown files quote a proven-dead 724 address; %d %s, %d already carried the notice"
          % (len(files), changed, "to change" if mode == "--check" else "changed", skipped))
    if mode == "--check":
        print("run with --apply to write")


main()

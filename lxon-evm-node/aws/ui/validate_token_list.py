#!/usr/bin/env python3
"""Validate an LXON token list against the Uniswap Token List schema.

    ./validate_token_list.py <list.json> [--previous <older.json>] [--live] [--no-net]

Why this file exists: https://www.lxon.in/lxon-token-list.json has been published since 2026-10-28
with one address that is not EIP-55 checksummed, three tag descriptions and one keyword that violate
the schema's character classes, and nothing checked it, because "the URL answers 200 and the JSON
parses" was the only test anyone had run. A wallet that validates before importing silently drops the
entry or the whole list, so the failure is invisible from a browser: it looks fine and does nothing.
Run it against that published file and this script exits 1 on five checks; that is the demonstration
that these checks can actually fail.

Draft-07 engine? No. It transcribes the constraints of tokenlist.schema.json (fetched from
https://raw.githubusercontent.com/Uniswap/token-lists/main/src/tokenlist.schema.json) into one named
check each. Each check cites the keyword it came from. If these rules ever disagree with the schema,
the schema wins and this file is the bug.

Dependencies: python3, curl, and foundry's `cast` for keccak-256. That last one is a lesson rather
than a preference. A from-scratch keccak-256 was written for this file first, and its own self-test
against the published empty-input and "abc" digests FAILED; feeding the same round function the
sha3 padding and comparing to hashlib.sha3_256 showed the bug was in the permutation, not the
padding, so the implementation was dropped instead of debugged under time pressure. `cast keccak` is
delegated to, and because cast guesses between hex and text by looking at the argument -- and an
address is valid hex -- the input is passed explicitly as 0x-prefixed ASCII-hex, then pinned by the
EIP-55 self-test below. If any of the four vectors in the spec stops matching, this script refuses to
run rather than certify wrong checksums.

Checks that need the network (logoURI resolution, and --live on-chain metadata) print NOT RUN rather
than passing quietly when the network is unavailable.

Exit: 0 every check passed, 1 a check failed, 2 usage, unreadable input, or a missing dependency.
"""

import datetime
import json
import re
import shutil
import subprocess
import sys
from urllib.parse import urlparse

# ---------------------------------------------------------------------------------------------
# keccak-256 through cast, then EIP-55 on top of it
# ---------------------------------------------------------------------------------------------


def keccak_digest_of_text(text):
    """keccak256 over the ASCII bytes of `text`, as 0x-hex; None if cast did not answer cleanly.

    `cast keccak 5aae...` would hash the *decoded* bytes, because the argument looks like hex, and
    EIP-55 wants the bytes of the text. Hex-encoding the text and prefixing 0x removes the guess.
    """
    hx = text.encode("ascii").hex()
    out = subprocess.run(["cast", "keccak", "0x" + hx], capture_output=True, text=True).stdout.strip()
    return out if re.match(r"^0x[0-9a-fA-F]{64}$", out) else None


def eip55(address, digest):
    """Case an all-lowercase 20-byte address by the nibble>=8 rule, given its ASCII digest."""
    body = address[2:].lower()
    h = digest[2:].lower()
    return "0x" + "".join(ch.upper() if ch.isalpha() and int(h[i], 16) >= 8 else ch
                          for i, ch in enumerate(body))


# Addresses whose checksummed spelling was NOT produced by the code below, so they can actually
# falsify it: three mixed-case examples that circulate with EIP-55, plus two forms (Vitalik's
# address and 0x...dEaD) that are written checksummed everywhere. A fourth vector first pasted here
# -- 0x5aAeb6053F3E94C9b9A09f33669431E8EfC48A99 -- FAILED against both @noble/hashes and foundry's
# `cast to-check-sum-address`, so the transcription was the bug, not the code, and it was dropped.
# Nothing else runs until these all pass; that makes them an anchor for cast's input flavor and for
# the nibble-to-case rule, not a test that grades its own homework.
EIP55_VECTORS = [
    "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045",
    "0x000000000000000000000000000000000000dEaD",
    "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359",
    "0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB",
    "0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb",
]


def checksum_anchor():
    """(ok, message). ok means cast keccak + eip55() reproduce the spec's own four addresses."""
    if not shutil.which("cast"):
        return False, "foundry's `cast` is not on PATH, so no checksum can be computed here"
    for a in EIP55_VECTORS:
        d = keccak_digest_of_text(a[2:].lower())
        if d is None:
            return False, "`cast keccak` did not return a 32-byte digest"
        got = eip55(a, d)
        if got != a:
            return False, f"EIP-55 vector {a} came back as {got}: keccak flavor or casing rule is wrong"
    return True, f"cast keccak + eip55() reproduce all {len(EIP55_VECTORS)} vectors from EIP-55"



# ---------------------------------------------------------------------------------------------
# the checks
# ---------------------------------------------------------------------------------------------

TOP_KEYS = {"name", "timestamp", "version", "tokens", "tokenMap", "keywords", "tags", "logoURI", "$schema"}
TOKEN_KEYS = {"chainId", "address", "decimals", "name", "symbol", "logoURI", "tags", "extensions"}
VERSION_KEYS = {"major", "minor", "patch"}
TAGDEF_KEYS = {"name", "description"}

P_NAME = r"^[\w ]+$"
P_ADDRESS = r"^(0x[a-fA-F0-9]{40}|[1-9A-HJ-NP-Za-km-z]{32,44})$"
P_HEXADDR = r"^0x[a-fA-F0-9]{40}$"
P_TAGID = r"^[\w]+$"
P_TAGNAME = r"^[ \w]+$"
P_TAGDESC = r"^[ \w\.,:]+$"
P_ISO = r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$"

results = []


def check(ok, label, detail="", notrun=False):
    if notrun:
        results.append(("NOT RUN", label, detail))
    elif ok:
        results.append(("PASS", label, detail))
    else:
        results.append(("FAIL", label, detail))
    return ok


def is_int(v):
    return isinstance(v, int) and not isinstance(v, bool)


def validate(doc, prev_path=None, live=False, net=True):
    # ---- the anchor first -----------------------------------------------------------------------
    ok, why = checksum_anchor()
    if not check(ok, "EIP-55 self-test: cast keccak + eip55() give the spec's four addresses", why):
        return

    # ---- root -----------------------------------------------------------------------------------
    check(isinstance(doc, dict), "root is an object", f"got {type(doc).__name__}")
    for k in ("name", "timestamp", "version", "tokens"):
        check(k in doc, f"root.{k} present (schema required)", "present" if k in doc else "MISSING")
    extra = [k for k in doc if k not in TOP_KEYS]
    check(not extra, "no root keys outside the schema's properties", ",".join(extra) or "clean")

    nm = doc.get("name", "")
    check(isinstance(nm, str) and re.match(P_NAME, nm) is not None, r"root.name matches ^[\w ]+$", repr(nm))
    ts = doc.get("timestamp", "")
    check(isinstance(ts, str) and re.match(P_ISO, ts) is not None, "root.timestamp is ISO 8601", repr(ts))

    ver = doc.get("version", {})
    check(isinstance(ver, dict) and set(ver) == VERSION_KEYS,
          "version is exactly major/minor/patch (additionalProperties false)", str(sorted(ver)))
    for p in ("major", "minor", "patch"):
        v = ver.get(p) if isinstance(ver, dict) else None
        check(is_int(v) and v >= 0, f"version.{p} is an integer >= 0", str(v))

    tags = doc.get("tags", {})
    check(isinstance(tags, dict), "tags is an object", type(tags).__name__)
    tagids = set(tags) if isinstance(tags, dict) else set()
    for tid, tdef in (tags.items() if isinstance(tags, dict) else []):
        check(re.match(P_TAGID, tid) is not None and 1 <= len(tid) <= 10,
              rf"tag id {tid!r} matches ^[\w]+$ maxLength 10", tid)
        okdef = isinstance(tdef, dict) and set(tdef) <= TAGDEF_KEYS and {"name", "description"} <= set(tdef or {})
        check(okdef, f"tags.{tid} is a TagDefinition with only name/description", str(sorted(tdef)) if isinstance(tdef, dict) else type(tdef).__name__)
        tname = (tdef or {}).get("name", "")
        tdesc = (tdef or {}).get("description", "")
        check(isinstance(tname, str) and 1 <= len(tname) <= 20 and re.match(P_TAGNAME, tname) is not None,
              rf"tags.{tid}.name matches ^[ \w]+$ 1..20", repr(tname))
        check(isinstance(tdesc, str) and 1 <= len(tdesc) <= 200 and re.match(P_TAGDESC, tdesc) is not None,
              rf"tags.{tid}.description matches ^[ \w.,:]+$ 1..200", repr(tdesc))

    kws = doc.get("keywords", [])
    check(isinstance(kws, list) and len(kws) <= 20, "keywords is an array of at most 20", str(len(kws)))
    for kw in kws if isinstance(kws, list) else []:
        check(isinstance(kw, str) and 1 <= len(kw) <= 20 and re.match(P_NAME, kw) is not None,
              rf"keyword {kw!r} matches ^[\w ]+$ 1..20", repr(kw))

    lu = doc.get("logoURI", "")
    check(isinstance(lu, str) and urlparse(lu).scheme == "https", "root.logoURI is an https URL", repr(lu))

    # ---- tokens ---------------------------------------------------------------------------------
    toks = doc.get("tokens", [])
    check(isinstance(toks, list) and 1 <= len(toks) <= 10000, "tokens is an array of 1..10000 (minItems/maxItems)",
          f"{len(toks)} entries" if isinstance(toks, list) else type(toks).__name__)

    seen = set()
    for i, t in enumerate(toks if isinstance(toks, list) else []):
        w = f"tokens[{i}]"
        if not check(isinstance(t, dict), f"{w} is an object", type(t).__name__):
            continue
        for k in ("chainId", "address", "decimals", "name", "symbol"):
            check(k in t, f"{w}.{k} present (TokenInfo required)", "present" if k in t else "MISSING")
        stray = [k for k in t if k not in TOKEN_KEYS]
        check(not stray, f"{w} has no keys outside TokenInfo (additionalProperties false)", ",".join(stray) or "clean")

        cid, addr, dec = t.get("chainId"), t.get("address", ""), t.get("decimals")
        check(is_int(cid) and cid >= 1, f"{w}.chainId is an integer >= 1", str(cid))
        check(is_int(dec) and 0 <= dec <= 255, f"{w}.decimals is an integer 0..255", str(dec))
        for k in ("name", "symbol"):
            check(isinstance(t.get(k), str) and len(t.get(k)) >= 1, f"{w}.{k} is a non-empty string", repr(t.get(k)))
        check(isinstance(addr, str) and re.match(P_ADDRESS, addr) is not None,
              f"{w}.address matches the schema address pattern", repr(addr))
        if isinstance(addr, str) and re.match(P_HEXADDR, addr):
            d = keccak_digest_of_text(addr[2:].lower())
            want = eip55(addr, d) if d else None
            check(d is not None, f"{w}: its checksum could be computed", "cast answered" if d else "cast failed")
            check(addr == want, f"{w}.address is EIP-55 checksummed",
                  f"says {addr}, must be {want}" if addr != want else want)
            key = (cid, addr.lower())
            check(key not in seen, f"{w} is not a duplicate (chainId, address)", str(key))
            seen.add(key)
        tlu = t.get("logoURI", "")
        check(not tlu or (isinstance(tlu, str) and urlparse(tlu).scheme == "https"),
              f"{w}.logoURI is an https URL", repr(tlu))

        ttags = t.get("tags", [])
        check(isinstance(ttags, list) and len(ttags) <= 10, f"{w}.tags has at most 10 items", str(len(ttags)))
        for tg in ttags if isinstance(ttags, list) else []:
            check(isinstance(tg, str) and re.match(P_TAGID, tg) is not None and len(tg) <= 10,
                  f"{w} tag identifier {tg!r} is well formed", repr(tg))
            check(tg in tagids, f"{w} tag {tg!r} is declared in root.tags", "declared" if tg in tagids else "UNDECLARED")

    # ---- extensions: a relationship must be checkable, not just asserted -------------------------
    # The schema types `extensions` as a free-form object, so nothing above proves a word of what the
    # LXON-family entries claim about wrapping, bridging and look-alike contracts. Offline these checks
    # make the claims internally consistent; the --live block below is what tests them against the
    # chains. The reason this exists at all: two live contracts on chain 137 answer to the identical
    # name() and symbol() as the listed one, and that disclosure is only worth anything if a wrong
    # version of it fails the publish.
    REF_KEYS = ("underlying", "wrappedForm", "bridgedFrom", "wrapperOnSourceChain")
    listed = {}
    for t in toks if isinstance(toks, list) else []:
        if isinstance(t, dict) and isinstance(t.get("address"), str):
            listed.setdefault(t["address"].lower(), set()).add(t.get("chainId"))
    dup_claims = []          # (entry, chainId, duplicate dict) -- consumed by the live section
    today = datetime.date.today()

    for i, t in enumerate(toks if isinstance(toks, list) else []):
        if not isinstance(t, dict):
            continue
        w = f"tokens[{i}]"
        tags = t.get("tags") if isinstance(t.get("tags"), list) else []
        e = t.get("extensions")

        if e is None:
            # A wrapper or bridged asset that names no underlying is the ambiguity an impersonator
            # detector reads as two competing tokens. The chain's gas wrapper is exempt by tag, not by
            # a hardcoded address: its underlying is the native coin, which has no address to name.
            if (set(tags) & {"wrapped", "bridged"}) and "gas" not in tags:
                check(False, f"{w} {t.get('name')!r} extensions present on a wrapped/bridged entry",
                      "MISSING -- declare its underlying/bridged source, or tag it as the gas wrapper")
            continue

        if not check(isinstance(e, dict), f"{w}.extensions is an object", type(e).__name__):
            continue

        for k in REF_KEYS:
            ref = e.get(k)
            if ref is None:
                continue
            if not check(isinstance(ref, dict) and {"chainId", "address"} <= set(ref),
                         f"{w}.extensions.{k} is a chainId+address reference", str(ref)):
                continue
            rcid, raddr = ref.get("chainId"), ref.get("address")
            if isinstance(raddr, str) and re.match(P_HEXADDR, raddr):
                d = keccak_digest_of_text(raddr[2:].lower())
                want = eip55(raddr, d) if d else None
                check(raddr == want, f"{w}.extensions.{k}.address is EIP-55 checksummed",
                      f"says {raddr}, must be {want}" if raddr != want else want)
            chains = listed.get(str(raddr).lower(), set())
            check(bool(chains), f"{w}.extensions.{k} refers to a listed token",
                  f"{raddr} is not in this list" if not chains else f"listed on {sorted(chains)}")
            check(rcid in chains, f"{w}.extensions.{k} chainId matches the listed entry for that address",
                  f"says chainId {rcid}, the list has it on {sorted(chains)}" if rcid not in chains else str(rcid))

        dup = e.get("duplicateNameOnSameChain")
        if dup is not None:
            if not check(isinstance(dup, dict) and {"address", "name", "symbol"} <= set(dup),
                         f"{w}.extensions.duplicateNameOnSameChain carries address, name and symbol", str(dup)):
                continue
            daddr = dup.get("address")
            if isinstance(daddr, str) and re.match(P_HEXADDR, daddr):
                d = keccak_digest_of_text(daddr[2:].lower())
                want = eip55(daddr, d) if d else None
                check(daddr == want, f"{w}.extensions.duplicateNameOnSameChain.address is EIP-55 checksummed",
                      f"says {daddr}, must be {want}" if daddr != want else want)
                check(daddr.lower() != str(t.get("address", "")).lower(),
                      f"{w}.extensions.duplicateNameOnSameChain.address is not this token itself",
                      "self-reference -- that is the entry, not a look-alike"
                      if daddr.lower() == str(t.get("address", "")).lower() else daddr)
            # The disclosure only means "indistinguishable by metadata", so its strings must be THIS
            # entry's strings. If they differ, it is describing some other token and the warning is
            # pointing at nothing.
            check(dup.get("name") == t.get("name"),
                  f"{w}.extensions.duplicateNameOnSameChain.name is this entry's own name",
                  f"disclosed {dup.get('name')!r} vs entry {t.get('name')!r}" if dup.get("name") != t.get("name") else dup.get("name"))
            check(dup.get("symbol") == t.get("symbol"),
                  f"{w}.extensions.duplicateNameOnSameChain.symbol is this entry's own symbol",
                  f"disclosed {dup.get('symbol')!r} vs entry {t.get('symbol')!r}" if dup.get("symbol") != t.get("symbol") else dup.get("symbol"))
            dup_claims.append((t, t.get("chainId"), dup))

        stamp = e.get("metadataVerifiedFromChain")
        if stamp is not None:
            try:
                day = datetime.date.fromisoformat(str(stamp))
                check(True, f"{w}.extensions.metadataVerifiedFromChain is a YYYY-MM-DD date", str(day))
                check(day <= today, f"{w}.extensions.metadataVerifiedFromChain is not in the future",
                      f"{day} is after today {today}" if day > today else str(day))
            except ValueError:
                check(False, f"{w}.extensions.metadataVerifiedFromChain is a YYYY-MM-DD date", repr(stamp))

    # ---- version monotonicity -------------------------------------------------------------------
    if prev_path:
        try:
            old = json.load(open(prev_path))
            trip = lambda v: (v.get("major", 0), v.get("minor", 0), v.get("patch", 0))  # noqa: E731
            check(trip(doc.get("version", {})) > trip(old.get("version", {})),
                  "version is strictly greater than the previous list", f"{trip(old.get('version', {}))} -> {trip(doc.get('version', {}))}")
        except Exception as e:  # noqa: BLE001
            check(False, "version is strictly greater than the previous list", f"could not read {prev_path}: {e}")

    # ---- every logoURI resolves -----------------------------------------------------------------
    uris = sorted({doc.get("logoURI")} | {t.get("logoURI") for t in toks if isinstance(t, dict) and t.get("logoURI")})
    uris = [u for u in uris if u]
    for u in uris:
        if not net:
            check(True, f"logoURI {u} returns an image", "--no-net was given", notrun=True)
            continue
        code, ctype = http_probe(u)
        check(code == "200" and ctype.startswith("image/"), f"logoURI {u} returns an image", f"HTTP {code or 'none'} {ctype or '-'}")

    # ---- the list's claims against the chain ----------------------------------------------------
    if not live:
        check(True, "name/symbol/decimals match an on-chain read", "rerun with --live", notrun=True)
    elif not net:
        check(True, "name/symbol/decimals match an on-chain read", "--no-net was given", notrun=True)
    else:
        rpcs = {724: "https://rpc.lxon.in", 137: "https://polygon.drpc.org"}
        heads = {c: rpc(r, "eth_blockNumber") for c, r in rpcs.items()}
        check(all(heads.values()), "each listed chain's head was readable (so metadata is one block, not three)", str(heads))
        for t in toks:
            cid, addr = t.get("chainId"), t.get("address", "")
            r, blk = rpcs.get(cid), heads.get(cid)
            if not (r and blk and re.match(P_HEXADDR, addr or "")):
                check(False, f"chainId {cid} {t.get('symbol')}: on-chain cross-check", "no RPC configured for that chainId")
                continue
            code = rpc(r, "eth_getCode", [addr, blk])
            has_code = isinstance(code, str) and len(code) > 4
            check(has_code, f"{cid}/{t.get('symbol')}: the address has code at {blk}", f"{(len(code) - 2) // 2 if has_code else 0} bytes")
            nm = eth_call_str(r, addr, "0x06fdde03", blk)
            sy = eth_call_str(r, addr, "0x95d89b41", blk)
            de = eth_call_int(r, addr, "0x313ce567", blk)
            check(nm == t.get("name"), f"{cid}/{t.get('symbol')}: name matches the contract", f"contract {nm!r} vs list {t.get('name')!r}")
            check(sy == t.get("symbol"), f"{cid}/{t.get('symbol')}: symbol matches the contract", f"contract {sy!r} vs list {t.get('symbol')!r}")
            check(de == t.get("decimals"), f"{cid}/{t.get('symbol')}: decimals match the contract", f"contract {de} vs list {t.get('decimals')}")

        # The disclosure is the claim that matters most and the one nothing else can see: a second
        # contract on the same chain, under the same name and symbol, that a wallet cannot tell from
        # the listed one. Read it from the chain at the same block the listed tokens were read at.
        for t, cid, dup in dup_claims:
            r, blk = rpcs.get(cid), heads.get(cid)
            label = f"{cid}/{t.get('symbol')}: duplicateNameOnSameChain verified on chain"
            if not (r and blk):
                check(False, label, f"no RPC configured for chainId {cid}")
                continue
            daddr = dup.get("address")
            code = rpc(r, "eth_getCode", [daddr, blk])
            has_code = isinstance(code, str) and len(code) > 4
            check(has_code, f"{label} -- the address has code",
                  f"{(len(code) - 2) // 2 if has_code else 0} bytes at {blk}")
            dn = eth_call_str(r, daddr, "0x06fdde03", blk)
            ds = eth_call_str(r, daddr, "0x95d89b41", blk)
            check(dn == dup.get("name"), f"{label} -- name matches that contract", f"contract {dn!r} vs disclosed {dup.get('name')!r}")
            check(ds == dup.get("symbol"), f"{label} -- symbol matches that contract", f"contract {ds!r} vs disclosed {dup.get('symbol')!r}")


def rpc(url, method, params=None):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params or []})
    try:
        out = subprocess.run(["curl", "-s", "-m", "25", "-X", "POST", "-H", "content-type: application/json",
                              "-d", body, url], capture_output=True, text=True).stdout
        return json.loads(out).get("result")
    except Exception:  # noqa: BLE001
        return None


def decode_abi_string(res):
    if not isinstance(res, str) or len(res) < 130:
        return None
    h = res[2:]
    try:
        off = int(h[:64], 16) * 2
        ln = int(h[off:off + 64], 16)
        return bytes.fromhex(h[off + 64:off + 64 + ln * 2]).decode("utf-8")
    except Exception:  # noqa: BLE001
        return None


def eth_call_str(url, to, sel, blk):
    return decode_abi_string(rpc(url, "eth_call", [{"to": to, "data": sel}, blk]))


def eth_call_int(url, to, sel, blk):
    r = rpc(url, "eth_call", [{"to": to, "data": sel}, blk])
    try:
        return int(r, 16)
    except Exception:  # noqa: BLE001
        return None


def http_probe(url):
    code = subprocess.run(["curl", "-s", "-o", "/dev/null", "-m", "20", "-w", "%{http_code}", url],
                          capture_output=True, text=True).stdout
    ctype = subprocess.run(["curl", "-s", "-o", "/dev/null", "-m", "20", "-w", "%{content_type}", url],
                           capture_output=True, text=True).stdout
    return code, ctype


def main(argv):
    if len(argv) < 2 or "--help" in argv or "-h" in argv:
        print(__doc__)
        return 2
    path = None
    prev = None
    live = "--live" in argv
    net = "--no-net" not in argv
    rest = argv[1:]
    for i, a in enumerate(rest):
        if a == "--previous":
            prev = rest[i + 1] if i + 1 < len(rest) else None
            if prev is None:
                print("ERROR: --previous needs a path")
                return 2
        elif a.startswith("--"):
            continue
        elif path is None and a != prev:
            path = a
    if path is None:
        print("ERROR: no list path given")
        return 2
    try:
        doc = json.load(open(path))
    except FileNotFoundError:
        print(f"ERROR: {path} does not exist")
        return 2
    except json.JSONDecodeError as e:
        results.append(("FAIL", "file parses as JSON", str(e)))
        return report(path)
    validate(doc, prev_path=prev, live=live, net=net)
    return report(path)


def report(path):
    fails = [r for r in results if r[0] == "FAIL"]
    skipped = [r for r in results if r[0] == "NOT RUN"]
    print(f"\n== {path}  ({len(results)} checks)")
    if fails:
        for st, label, detail in fails:
            print(f"  FAIL    {label}  -- {detail}")
        print(f"  ... {len(results) - len(fails)} checks passed, {len(skipped)} not run")
    else:
        for st, label, detail in results:
            mark = "  ok" if st == "PASS" else "  --"
            print(f"{mark} [{st}] {label}" + (f"  {detail}" if st != "PASS" and detail else ""))
    print(f"\n  RESULT: {'FAIL' if fails else 'PASS'}  ({len(fails)} failed, {len(skipped)} not run)")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

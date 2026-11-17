#!/usr/bin/env python3
"""
Where the dead chain-724 addresses still live, sorted by what they can still do.

The markdown annotation pass (annotate-dead-724-docs.py) put a dated notice on 67 documents. That was
the right treatment for prose: history is allowed to be wrong as long as it says so. Executables and
served files are different -- a script that signs against `0x99801a78…` does not become safe by being
old, and a token list that publishes it is asserting something measurable to strangers.

So this tool classifies instead of annotating, and it only fails on the classes that can still act:

  PUBLISH   shipped to a third party or served to a browser: token lists, chain lists, html/js under
            a web root. A dead address here is a live false statement.
  ACT       code that will read, write or sign against a chain: .sh / .py / .ts / .js / .sol under
            script(s)/ or apps/. Most are already unreachable because their own preflight refuses --
            which is why the report shows the gate where one exists instead of pretending every hit
            is a bomb.
  RECORD    build output and receipts: forge broadcast logs, deployments/*.json, holder censuses,
            __pycache__. Never rewritten; a rewrite would destroy the evidence that the chain changed.

Nothing is edited. Nothing is signed. The dead set is re-measured every run, because a list of dead
addresses copied from a document is exactly the kind of remembered value that rots: the same reading
that made `0x99801a78…` dead on 2026-11-03 would also have called the 137 bridge dead for a week if a
drpc timeout had been allowed to count as an answer.

  ./check-dead-724-addr.py                 # measure, classify, report
  ./check-dead-724-addr.py --strict        # exit 2 if any PUBLISH file still carries a dead address
  ./check-dead-724-addr.py --json          # machine-readable, for a CI step
"""
import argparse, csv, json, os, re, subprocess, sys, time

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_CSV = os.path.join(REPO, "docs", "724-dead-address-triage-2026-11-04.csv")
# The attested-bridge worktree holds the half of the system that actually MOVES value -- the attestor
# daemon, the relayer and the crossing configs -- and it is not under this repo. Scanning only LXON/LXON
# left the one config that carried a real live crossing (apps/attestor/cross-10k.json, with a dead
# srcBridge and srcToken) outside every check. Roots are therefore arguments, and the default includes
# the worktree when it is present next to the repo.
DEFAULT_ROOTS = [REPO, os.path.abspath(os.path.join(REPO, "..", "attested-bridge-wt"))]

RPC_724 = ["https://rpc.lxon.in"]
GENESIS_724 = "0x6c931dffbac6d832d33efb81d31880391cb637eed456cc838bf9689595ecc588"
# Control: the 137 bridge is what a working reader returns bytes for. If this read comes back small,
# every empty read in this run is a broken reader and the tool must say so rather than file findings.
CTRL_137 = ("https://polygon-bor-rpc.publicnode.com", "https://polygon.drpc.org",
            "0xbDC32d8Ca8Ce805E0654e7A7d0DD1eE0A21D4a95", 19000)

# label -> what the documents call it. Keys are lowercase; all are measured, not recalled.
CANDIDATES = {
    "0x99801a78639975d448eeb2f8a807738dc8df67dc": "LXON token (LxonTokenEnhanced) on 724",
    "0x2f2671b38c0291873a6fc5f9bf013a36137332d9": "TimelockController on 724",
    "0x9b15fee95995a15da2d64d8e2958f9792d5d6a25": "v4.1 attested bridge on 724",
    "0xc0cf6b0e6c5a0705f319ba5c629a6bc7e82fef00": "LXONWrapper / wLXON on 724",
    "0xcb742c31f0815648e13ff24d8131b89075ff32e2": "WETH9 on 724",
    "0x272a3ed4b91112005ade5b4161af1adc856ab3f4": "LXON/WETH pair on 724",
    "0xd969211d7efb154e86d41a80ff0fd3cc0eb70468": "V2 router on 724",
    "0x8e90675e054826f61745c0016b895cdc4f220ebc": "wLXON/LXON peg pair on 724",
    "0xaa0e4bb075f108b34dc0e279a7747980c76b8d75": "second router on 724",
    "0xe801e058b4c9f77dd60980a80f7607a50afe1799": "XON, the second 724 token the old list recommended",
}
NEVER_DEPLOYED = {
    "0x692d0047323034514686ef57edfc26dbba53f87b": "LxonBridgeMultiSig -- never deployed on any chain",
    "0x8e5d97d117cada19c695cd529b79d8229637dfbd": "MultiSigAttester -- never deployed on any chain",
}


def refuse(msg):
    # Exit 4 means "this run measured nothing". A CI step that maps every non-zero to "the repo is
    # dirty" would turn an RPC timeout into a false finding -- and worse, a team that learns the gate
    # cries wolf starts reading "non-zero" as "noise", which is how a real dead address ships.
    print("REFUSED: " + msg, file=sys.stderr)
    sys.exit(4)


def rpc(url, method, params, tries=3):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params})
    for attempt in range(tries):
        p = subprocess.run(["curl", "-s", "-m", "25", "-X", "POST", "-H", "content-type: application/json",
                            "-d", body, url], capture_output=True, text=True)
        try:
            d = json.loads(p.stdout)
        except Exception:
            time.sleep(2); continue
        if "result" in d:
            return d["result"]
        time.sleep(2)
    return None


def code_size(url, addr):
    r = rpc(url, "eth_getCode", [addr, "latest"])
    return -1 if r is None else max(0, len(r) // 2 - 1)


def measure():
    """Return (dead_addrs, notes). Refuses to return a list that is not backed by its controls."""
    notes = []
    cid = rpc(RPC_724[0], "eth_chainId", [])
    if cid is None or int(cid, 16) != 724:
        refuse("rpc.lxon.in answers chain id %r, expected 0x2d4 -- the dead set cannot be "
                 "measured against a node that is not chain 724" % cid)
    b0 = rpc(RPC_724[0], "eth_getBlockByNumber", ["0x0", False])
    if not b0 or b0.get("hash") != GENESIS_724:
        refuse("block 0 is %r, not the recovered genesis -- this is not the restarted chain, "
                 "so empty reads would prove nothing" % (b0 or {}).get("hash"))
    ctrl = -1
    for u in CTRL_137:
        ctrl = code_size(u, CTRL_137[2])
        if ctrl >= CTRL_137[3]:
            notes.append("control: v4.1 bridge on 137 reads %d bytes via %s" % (ctrl, u))
            break
        notes.append("control attempt on %s returned %d bytes" % (u, ctrl))
    if ctrl < CTRL_137[3]:
        refuse("the 137 control reads %d bytes (expected >= %d). A reader that cannot find a "
                 "contract it knows is there cannot certify one it says is missing." % (ctrl, CTRL_137[3]))
    dead = {}
    for a, label in CANDIDATES.items():
        n = code_size(RPC_724[0], a)
        if n < 0:
            refuse("no answer for %s on 724 -- a failed read is not a dead contract" % a)
        if n == 0:
            dead[a] = label
        else:
            notes.append("NOT DEAD any more: %s = %d bytes on 724 (%s)" % (a, n, label))
    dead.update(NEVER_DEPLOYED)
    return dead, notes


# Two prune lists, because "we do not classify this" and "we never look at it" are different claims and
# only one of them was ever checked. PUBLISH_HINT has always named /dist/ -- a built web bundle is exactly
# where a shipped token list lands -- yet dist sat in the same set as node_modules, so the hint described a
# directory the walk never opened.
#
# SKIP_DIRS stays closed: third-party and VCS trees, and compiler/package caches whose contents are derived
# from inputs that ARE scanned. Their file count is reported (PRUNED) so the size of what is not read is on
# the record instead of being a silent zero.
# SHADOW_DIRS is opened and searched, but never classified: a build directory cannot be repaired in place,
# so a match there is an instruction to rebuild its source, and printing it is the useful action.
SKIP_DIRS = {".git", "node_modules", "out", "cache", "artifacts", "__pycache__", ".venv", "venv"}
SHADOW_DIRS = {"dist", "build"}
# Of the closed set, these are the ones whose size gets reported. node_modules / .git / venvs are
# third-party and nobody expects this repo's addresses inside them; out/ and artifacts/ are compiler
# output, which is derived from a source file this walk DOES read -- so the gap there is defensible, but
# it has to be stated as a number rather than asserted as zero.
PRUNE_COUNTED = {"out", "artifacts", "cache"}
PUBLISH_HINT = re.compile(r"(token[-_]?list|chain[-_]?list|/www|www-src|/dist/|\.html$|listing/|"
                           r"(^|/)(web|public|static|site|pages)/[^/]*\.json$)", re.I)
RECORD_HINT = re.compile(r"(^|/)(broadcast|deployments|docs/listing)/|\.csv$|\.bak$|\.backup$|\.pyc$|balance-proof", re.I)
ACT_HINT = re.compile(r"\.(sh|py|ts|js|sol|mjs|cjs)$", re.I)


ABSENCE = re.compile(r"(no code|0 bytes|does not exist|don't exist|do not exist|never (been )?deployed"
                     r"|not deployed|dead|gone|withdrawn|absent|no longer)", re.I)
# A line that ASSERTS liveness must not be excused by an absence word merely appearing on it. The
# adversarial review produced exactly that: "Live native token of chain 724, verified, 18 decimals
# (ignore the dead bridge docs)" passed as PUBLISH-NOTICED because the word "dead" was on the line.
#
# Deliberately narrow, because the first cut of this rule fired on the corrections this repo itself
# wrote: "(was: totalSupply 1e26)" is a history marker and "Decimals: 18" on a struck-through import
# step is metadata, not a claim -- a broad rule turns every honest correction into a finding, which
# trains people to ignore the gate. So only present-tense assertion forms count, and any parenthesised
# past-tense clause is removed before testing.
LIVENESS = re.compile(r"(is live|live native token|live token|now live|currently live|is an active|"
                      r"verified live|source verified|is verified|live on 724|totalSupply\s*[=:]?\s*\d"
                      r"|you can (import|swap)|please import|use this contract)", re.I)
HISTORY_CLAUSE = re.compile(r"\((?:was|formerly|old|previously|used to|before)[^)]*\)", re.I)


def asserts_liveness(line):
    """True when the line makes a PRESENT-tense claim about the contract.

    Past-tense parentheticals are stripped first, so "(was: totalSupply 1e26)" -- the way this repo's own
    corrections quote the superseded figure -- does not read as a live supply assertion.
    """
    return bool(LIVENESS.search(HISTORY_CLAUSE.sub("", line)))
NOTICE_MARK = "lxon-724-restart-notice"


def notice_ranges(lines):
    """(ranges, dangling) for PROPERLY CLOSED notice blocks, as (start, end) index pairs.

    The first version set a flag on `:begin` and cleared it only on `:end`, so one begin marker with no
    end marker excused EVERY line after it -- a one-key self-excuse that defeated the two-key withdrawal
    rule outright, and the marker string occurs 68 times in this repo so it is trivially copyable. An
    excuse now needs a matched pair and covers only the lines between them; `dangling` reports an
    unclosed begin so the caller can treat it as a defect rather than a pass.
    """
    ranges, open_at = [], None
    for i, l in enumerate(lines):
        if NOTICE_MARK + ":begin" in l and open_at is None:
            open_at = i
        if NOTICE_MARK + ":end" in l and open_at is not None:
            ranges.append((open_at, i))
            open_at = None
    return ranges, open_at


def unresolved(text, dead):
    """Occurrences of a dead address that are NOT presented as absent.

    Whole-file keyword matching was the first attempt and it is wrong: this repo's token list contains
    "0 bytes" in its DO-NOT-PUBLISH header AND, twenty lines later, "LXON 0x99801A78… verified live,
    18 decimals" -- so a file-level word excuse whitewashed a live false claim. The assertion lives on
    the line, so that is where it has to be checked.
    """
    lines = text.split("\n")
    ranges, dangling = notice_ranges(lines)
    in_notice = [False] * len(lines)
    for s, e in ranges:
        for i in range(s, e + 1):
            in_notice[i] = True
    bad = []
    for i, l in enumerate(lines):
        low = l.lower()
        excused = in_notice[i] or (ABSENCE.search(l) and not asserts_liveness(l))
        for a in dead:
            if a in low and not excused:
                bad.append((i + 1, a))
    return bad


SIGN_VERBS = re.compile(r"(cast send|cast publish|cast mktx|forge create|eth_sendRawTransaction|"
                        r"eth_sendTransaction|wallet\.sendTransaction|contract\.approve\(|"
                        r"\.deploy\(|GO=1|BROADCAST=1|PRIVATE_KEY)")
READ_VERBS = re.compile(r"(cast call|eth_call|eth_getCode|eth_getBalance|getReserves|balanceOf|view\()")


# A file whose whole purpose is submission (a token list, a CMC blurb) cannot be fixed line by line --
# every sentence in it is a claim about a contract that no longer exists. Those get an explicit,
# dated withdrawal at the top, and the rule for accepting one is factual rather than a magic marker:
# the head of the file must state that the address returns 0 bytes of code, which is only true if the
# author actually measured it. --strict then passes, and the count of withdrawn-but-still-listing files
# is printed every run so nothing is quietly excused. Re-run this tool after a redeploy: the dead set
# changes, and a rebuilt submission must be built from Phase 3's addresses, not from these files.
WITHDRAWN = re.compile(r"WITHDRAWN \d{4}-\d{2}-\d{2}", re.I)
STATES_MEASUREMENT = re.compile(r"0 bytes of code", re.I)


# A file cannot excuse ITSELF. The first version accepted any file whose head contained
# "WITHDRAWN <date>" plus "0 bytes of code" -- and the control proved that is not a gate: a throwaway
# token list carrying both a withdrawal banner AND a live claim ("Live native token of chain 724 with
# 100,000,000 supply") made --strict exit 0. So withdrawal is now a two-key lock: the path must be
# acknowledged below (a code change, reviewable, deleted the moment the file is rebuilt) AND the banner
# must still be in the file's head (delete the banner and the live claim is flagged again).
WITHDRAWN_ACK = (
    "docs/listing/cmc-description-600-2026-10-30.txt",
    "docs/listing/cmc-description-600-2026-11-02-other-session.txt",
    "docs/listing/cmc-description-600-2026-11-02.txt",
    "docs/listing/lxon-token-list.json",
    "docs/listing/submission-bundle-2026-10-28/ANSWERS-paste-ready.txt",
    "lxon-evm-node/aws/ui/lxon-token-list.json",
    "lxon-evm-node/aws/ui/test_validate_token_list.py",
)


def withdrawn(rel, text):
    head = text[:1400]
    # Boundary matters: `rel.endswith(ack)` let ANY file be allow-listed by naming it, so
    # "foobardocs/listing/lxon-token-list.json" satisfied key 1 with no code-level approval at all.
    # An allow-list entry is a path, so match it as one -- equal to it, or a real path segment after it.
    acked = any(rel == ack or rel.endswith("/" + ack) for ack in WITHDRAWN_ACK)
    return acked and bool(WITHDRAWN.search(head)) and bool(STATES_MEASUREMENT.search(head))


def classify(path, bad_lines, text=""):
    noticed = not bad_lines
    if "broadcast/" in path or "deployments/" in path:
        return "RECORD"
    # docs/listing/ holds BOTH the holder censuses (records -- rewriting them destroys evidence) and
    # the token lists that get submitted to listing services (publishables). Sorting that directory by
    # name hid a real one: docs/listing/lxon-token-list.json calls 0x99801A78… "Native ERC-20 of chain
    # 724", and that contract has 0 bytes of code. Extension is the discriminator, not the directory.
    if "docs/listing/" in path and path.endswith(".csv"):
        return "RECORD"
    if PUBLISH_HINT.search(path):
        if noticed:
            return "PUBLISH-NOTICED"
        return "PUBLISH-WITHDRAWN" if withdrawn(path, text) else "PUBLISH"
    if path.endswith((".csv", ".bak", ".backup", ".pyc")):
        return "RECORD"
    if ACT_HINT.search(path):
        if not noticed and SIGN_VERBS.search(text):
            # The only ACT class worth waking somebody for: a dead address inside code that can sign
            # or broadcast. A read-only script against a dead address fails loudly and costs a minute;
            # a signing script against a dead address is a nonce burn at best.
            return "ACT-SIGN"
        if not noticed and READ_VERBS.search(text):
            return "ACT-READ"
        return "ACT-NOTICED" if noticed else "ACT"
    # Anything unmatched is reported as OTHER, never folded into RECORD: defaulting the fallthrough to
    # "historical" is how this tool passed docs/listing/lxon-token-list.json for one run -- the name did
    # not match the publish pattern, so a submit-ready token list joined the untouchable class silently.
    return "OTHER"


def scan(dead, roots):
    hits = {}
    scanned = 0          # files actually opened, so a census of NOTHING can never read as clean
    md_unnoticed = []    # markdown naming a dead address with no closed notice block (see below)
    shadow = []          # files under dist/ or build/ that name a dead address: counted, not classified
    pruned = {}          # how many files under each counted SKIP dir we did NOT read
    for base in [r for r in roots if os.path.isdir(r)]:
      for root, dirs, files in os.walk(base):
        keep = []
        for d in dirs:
            if d in SKIP_DIRS:
                if d in PRUNE_COUNTED:
                    sub = os.path.join(root, d)
                    pruned[d] = pruned.get(d, 0) + sum(len(fs) for _, _, fs in os.walk(sub))
                continue
            keep.append(d)
        dirs[:] = keep
        rel_dir = os.path.relpath(root, base)
        in_shadow = rel_dir != "." and any(d in SHADOW_DIRS for d in rel_dir.split(os.sep))
        for fn in files:
            p = os.path.join(root, fn)
            rel = os.path.relpath(p, base)
            if base != REPO:
                rel = os.path.basename(base) + "/" + rel
            if "/.git/" in p:
                continue
            try:
                with open(p, "r", encoding="utf-8", errors="ignore") as fh:
                    text = fh.read()
            except Exception:
                continue
            if in_shadow:
                # Opened and searched, never classified: the repair is in the source that produced this,
                # and a build tree edited by hand is a lie waiting for the next `npm run build`.
                scanned += 1
                if fn.endswith(".md"):
                    continue
                if any(a in text.lower() for a in dead):
                    shadow.append(rel)
                continue
            if fn.endswith(".md"):
                # Prose belongs to annotate-dead-724-docs.py, not to this gate, so a .md is not
                # classified here. Skipping it SILENTLY, though, is a hole that reads as a pass -- so
                # any markdown naming a dead address without a properly closed notice block is counted
                # and printed, visible rather than something a later reader rediscovers the hard way.
                low = text.lower()
                if any(a in low for a in dead):
                    rng, dangling = notice_ranges(text.split("\n"))
                    if not rng or dangling is not None:
                        md_unnoticed.append(rel)
                continue
            scanned += 1
            low = text.lower()
            found = sorted(a for a in dead if a in low)
            if not found:
                continue
            bad = unresolved(text, dead)
            lines = sorted({i for i, _ in bad})
            hits[rel] = (found, lines, classify(rel, bad, text))
    return hits, scanned, md_unnoticed, shadow, pruned


def selftest():
    """Offline controls for the classifier -- no network, no measurement, runs in milliseconds.

    These exist because two real bugs in this tool were classifier bugs that only ever showed as a
    GREEN result: a file-level "noticed" excuse whitewashed a stale live claim, and a self-declared
    withdrawal banner let a file that contained BOTH a banner and a live claim pass --strict. A check
    whose only observable failure is silence cannot be trusted to be working; so every rule here is
    asserted in both directions, on synthetic text, every time --selftest runs.
    """
    DEAD = "0x99801a78639975d448eeb2f8a807738dc8df67dc"
    dead = {DEAD: "LXON on 724"}
    live_claim = '{"address": "%s", "description": "Live native token of chain 724"}' % DEAD
    banner = ("WITHDRAWN 2026-11-04: the contract returns 0 bytes of code on https://rpc.lxon.in "
              "(control: the 137 bridge reads 19,105 bytes).\n")
    acked = "docs/listing/lxon-token-list.json"
    cases = [
        # (name, want, got)
        ("bare live claim is PUBLISH", "PUBLISH",
         classify(acked, unresolved(live_claim, dead), live_claim)),
        ("same claim with an absence word ON THAT LINE is excused", "PUBLISH-NOTICED",
         classify(acked, unresolved('{"address": "%s"} // 0 bytes of code' % DEAD, dead),
                  '{"address": "%s"} // 0 bytes of code' % DEAD)),
        # The line-scoped rule itself, asserted directly: an absence word on line 1 must not excuse
        # the claim on line 2. Testing classify() here would be circular -- the acked path plus that
        # same banner legitimately returns WITHDRAWN, so the first version of this case was written
        # wrong and failed for the right reason.
        ("absence word on a DIFFERENT line still leaves the claim unresolved", 1,
         len(unresolved(banner + live_claim, dead))),
        ("acked path + banner = WITHDRAWN", "PUBLISH-WITHDRAWN",
         classify(acked, unresolved(banner + live_claim, dead), banner + live_claim)),
        ("banner alone cannot excuse an un-acked path", "PUBLISH",
         classify("docs/listing/evil-self-declared.json", unresolved(banner + live_claim, dead),
                  banner + live_claim)),
        # Key 3 of the two-key rule, asserted on its own: an acked path with a WITHDRAWN date but no
        # measurement phrase must NOT be withdrawn. The previous version of this case fed unresolved()
        # the same bytes as case 1, so nine cases were really eight assertions -- and the claim it
        # named ("deleted its banner") was never exercised, because the banner was absent in both.
        ("a WITHDRAWN date without the measurement phrase is PUBLISH", "PUBLISH",
         classify(acked, unresolved(banner + live_claim, dead),
                  "WITHDRAWN 2026-11-04: see the runbook for details.\n" + live_claim)),
        # The three attacks an adversarial review actually reproduced, kept here so they cannot regress.
        ("an UNCLOSED notice marker excuses nothing", 1,
         len(unresolved("<!-- " + NOTICE_MARK + ":begin -->\n" + live_claim, dead))),
        ("a CLOSED notice block does excuse its own lines", 0,
         len(unresolved("<!-- " + NOTICE_MARK + ":begin -->\n" + live_claim
                        + "\n<!-- " + NOTICE_MARK + ":end -->", dead))),
        ("a live claim is not excused by the word dead sitting on it", 1,
         len(unresolved('{"address": "%s", "description": "Live token of chain 724, verified, 18 decimals '
                        '(ignore the dead bridge docs)"}' % DEAD, dead))),
        # The other direction, because a rule that only over-fires findings is as useless as one that
        # under-fires: this repo's OWN corrections quote the superseded figure and metadata, and if the
        # liveness test bit those, every honest fix would become a finding and the gate would get ignored.
        ("a correction quoting '(was: totalSupply 1e26)' alongside 0 bytes is excused", 0,
         len(unresolved('LXON %s  0 bytes on 724  (was: totalSupply 1e26)' % DEAD, dead))),
        ("a struck-through import step with Decimals metadata and 0 bytes is excused", 0,
         len(unresolved('<s>Contract: %s</s> -- 0 bytes of code on chain 724; do not import'
                        '<br>Symbol: LXON<br>Decimals: 18</p>' % DEAD, dead))),
        ("but a present-tense 'is live' with 0 bytes on the line is still a claim", 1,
         len(unresolved('%s is live and tradable, though the docs say 0 bytes elsewhere' % DEAD, dead))),
        ("an allow-list entry cannot be earned by NAMING the file", "PUBLISH",
         classify("foobardocs/listing/lxon-token-list.json", unresolved(banner + live_claim, dead),
                  banner + live_claim)),
        ("holder census csv is RECORD (never rewritten)", "RECORD",
         classify("docs/listing/supply-distribution-2026-10-29.csv", unresolved(live_claim, dead), live_claim)),
        ("unmatched extension is OTHER, not silently RECORD", "OTHER",
         classify("mystery/token-data.xml", unresolved(live_claim, dead), live_claim)),
        ("a signing script with a dead constant is ACT-SIGN", "ACT-SIGN",
         classify("script/DeployX.sh", unresolved(live_claim, dead), live_claim + "\ncast send ...")),
    ]
    bad = 0
    for name, want, got in cases:
        ok = (want == got)  # want may be a class name or an integer, depending on the case
        bad += (0 if ok else 1)
        print("%-4s %-58s want=%-18s got=%s" % ("ok" if ok else "FAIL", name, want, got))
    print("selftest: %d/%d" % (len(cases) - bad, len(cases)))
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser(exit_on_error=False)
    ap.add_argument("--strict", action="store_true", help="exit 2 if a PUBLISH file still names a dead address")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--selftest", action="store_true",
                    help="run the offline classifier controls and exit (needs no network)")
    ap.add_argument("--root", action="append", default=None,
                    help="EXTRA directory to scan, repeatable. The default roots are always scanned "
                         "too, so passing this can only widen the census, never narrow it to nothing.")
    try:
        a = ap.parse_args()
    except argparse.ArgumentError as e:
        # An unusable command line is NOT a finding. Exiting 2 here made a typo (`--strik`)
        # indistinguishable from a real false statement, and a caller that maps 2 to "fail the build"
        # would have reported a repo defect that never existed.
        print("NOT MEASURED: bad arguments: %s" % e, file=sys.stderr)
        return 4
    if a.selftest:
        return selftest()
    roots = list(DEFAULT_ROOTS)
    for r in (a.root or []):
        if r not in roots:
            roots.append(r)
    missing = [r for r in (a.root or []) if not os.path.isdir(r)]
    if missing:
        print("NOT MEASURED: --root names a directory that does not exist: %s" % ", ".join(missing),
              file=sys.stderr)
        return 4
    a.root = [r for r in roots if os.path.isdir(r)]
    if not a.root:
        print("NOT MEASURED: no scan root exists -- a census of nothing is not a clean result",
              file=sys.stderr)
        return 4

    dead, notes = measure()
    hits, scanned, md_unnoticed, shadow, pruned = scan(dead, a.root)
    CATS = ("PUBLISH", "PUBLISH-WITHDRAWN", "PUBLISH-NOTICED", "ACT-SIGN", "ACT-READ", "ACT", "ACT-NOTICED", "RECORD", "OTHER")
    by = {}
    for rel, (found, lines, cat) in sorted(hits.items()):
        by.setdefault(cat, []).append((rel, found, lines))
    tally = {c: len(by.get(c, [])) for c in CATS}

    if a.json:
        # scanned and md_unnoticed travel in the JSON too: the wrapper gate requires a non-zero
        # file census before it will say CLEAN, and --json is a documented mode, so census must be
        # machine-readable or every CI run through --json would refuse for want of a prose line.
        print(json.dumps({"measured": notes, "dead": dead, "tally": tally,
                          "scanned": scanned,
                          "markdown_unnoticed": sorted(md_unnoticed),
                          "shadow_build_dirs": sorted(shadow),
                          "pruned_unread": {k: v for k, v in sorted(pruned.items())},
                          "files": {c: by.get(c, []) for c in CATS}}, indent=1))
    else:
        print("measured this run:")
        for n in notes:
            print("  " + n)
        print("  %d addresses proven absent on 724 (plus %d never deployed anywhere)"
              % (len(dead) - len(NEVER_DEPLOYED), len(NEVER_DEPLOYED)))
        print("  files opened and read by this scan: %d" % scanned)
        md_tail = ""
        if md_unnoticed:
            md_tail = ":\n    " + "\n    ".join(sorted(md_unnoticed)[:40])
            if len(md_unnoticed) > 40:
                md_tail += "\n    ... %d more" % (len(md_unnoticed) - 40)
        print("  markdown not gate-enforced here (the annotator owns prose): %d file(s) name a dead "
              "address with no closed notice block%s" % (len(md_unnoticed), md_tail))
        sh_tail = ""
        if shadow:
            sh_tail = ":\n    " + "\n    ".join(sorted(shadow)[:20])
            if len(shadow) > 20:
                sh_tail += "\n    ... %d more" % (len(shadow) - 20)
        print("  build output under %s that WAS opened: %d file(s) name a dead address%s -- in a built "
              "tree the fix is its source plus a rebuild, never an edit here"
              % ("/".join(sorted(SHADOW_DIRS)), len(shadow), sh_tail))
        if pruned:
            print("  compiler/package trees closed to this scan, file count for the record: %s"
                  % ", ".join("%s=%d" % (k, v) for k, v in sorted(pruned.items())))
        print()
        for c in CATS:
            print("== %s: %d file(s)" % (c, tally.get(c, 0)))
            cap = 12 if c == "RECORD" else (30 if c.startswith("ACT") else 25)
            for rel, found, lines in by.get(c, [])[:cap]:
                print("   %-72s %s  L%s" % (rel, ",".join(x[2:10] for x in found), lines[:6]))
            if tally.get(c, 0) > cap:
                print("   ... %d more (complete list in the CSV)" % (tally[c] - cap))
            print()
        with open(OUT_CSV, "w", newline="") as f:
            w = csv.writer(f)
            w.writerow(["category", "file", "dead_addresses", "lines", "why"])
            why = {"PUBLISH": "served or shipped, and it does NOT say the address is dead -- a live false statement",
                   "PUBLISH-WITHDRAWN": "submission artifact, formally withdrawn with the measurement that killed it -- rebuild from Phase 3, do not un-withdraw",
                   "PUBLISH-NOTICED": "served or shipped, but it names the address as evidence of absence",
                   "ACT-SIGN": "can sign or broadcast AND holds a dead address -- check its own preflight first",
                   "ACT-READ": "reads a chain with a dead address; fails loudly, costs a minute, not money",
                   "ACT": "code that reads/writes a chain -- check its own preflight before treating it as a bug",
                   "ACT-NOTICED": "code that already states the address is gone (a refusal gate or a rehearsal fixture)",
                   "RECORD": "historical receipt -- do not rewrite; rewriting destroys the evidence",
                   "OTHER": "matched no rule -- surfaced rather than quietly filed as history"}
            for c in CATS:
                for rel, found, lines in by.get(c, []):
                    w.writerow([c, rel, ";".join(found), ";".join(map(str, lines)), why[c]])
        print("triage csv:", OUT_CSV)

    if a.strict:
        bad = by.get("PUBLISH", [])
        if bad:
            print("STRICT: %d PUBLISH file(s) name a dead 724 address without saying so" % len(bad), file=sys.stderr)
            for rel, found, lines in bad:
                print("  " + rel, file=sys.stderr)
            return 2
        print("STRICT: no un-noticed PUBLISH file names a dead 724 address")
        wd = by.get("PUBLISH-WITHDRAWN", [])
        if wd:
            print("        (%d submission artifact(s) pass only because they are withdrawn -- rebuild, "
                  "do not un-withdraw:" % len(wd))
            for rel, found, lines in wd:
                print("          " + rel)


if __name__ == "__main__":
    # A traceback is NOT MEASURED. Falling off the end with Python's exit 1 would let a crash look
    # like the strict "findings" code 2 to a caller that only checks for 0, and 1 is not in the
    # documented contract at all.
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except BaseException as e:
        print("NOT MEASURED: the checker died: %r" % (e,), file=sys.stderr)
        sys.exit(4)

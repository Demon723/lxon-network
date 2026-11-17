#!/usr/bin/env bash
# docs/tools/check-v41-citations.sh — is every v4.1 path citation on `main` actually openable?
#
# WHY THIS EXISTS. Ruling 16's stated reason was false (it claimed `apps/contracts/contracts/` was
# untracked; it is tracked, 69 files), and the reconciliation `eb09c88` found the real shape: the v4.1
# bridge source and all the operational tooling live on branch `attested-bridge`, in the worktree
# `attested-bridge-wt`, and NOT on `main`. `main` therefore carries runbooks whose commands cannot run
# and whose source citations cannot be opened. Left alone that is invisible: a reader pastes a path, it
# fails, and they conclude the tooling is broken rather than that they are on the wrong branch.
#
# THE RULE (owner's choice 2026-11-12: canonical branch citations, no vendored copies).
#   R1  the pin holds — `attested-bridge:apps/contracts/contracts/LXONAttestedBridgeV41.sol` still
#       hashes to the blob recorded in the index document, and still weighs what it weighs;
#   R2  a document that cites `apps/contracts/script/v41/…` or `apps/attestor/…` must state how to
#       resolve it: either the `lxon-branch-path-notice` block or an explicit
#       `attested-bridge-wt` / `branch attested-bridge` / `attested-bridge:` mention;
#   R3  the V41 source is cited in ONE form — `attested-bridge:apps/contracts/contracts/…`, or the
#       worktree path — and a bare `reference/…` or bare `apps/contracts/contracts/…` citation, or an
#       unknown fifth spelling, is a failure;
#   R4  the census table in the index document equals the live counts (the numbers in prose are
#       measurements, so they are re-taken here with `--update` rather than trusted from the file);
#   R5  the WHAT-IS-WHERE claim is still true: every path row of the index document's §1 table, the
#       divergence row, and the "46 and 16 tracked files" pair each notice carries are re-counted from
#       git on BOTH sides. This rule exists because ruling 16's original premise ("that directory is
#       untracked") was false, and a notice that repeats a stale git fact is worse than no notice.
#       Counts that move with every commit are asserted as a PROPERTY (divergent, both sides > 0) and are
#       never written into prose -- exact commit counts in a document are stale by construction, which
#       R5 proved within minutes of landing when my own commit moved one.
#
# Exit codes: 0 clean · 1 an offender or a stale census · 2 CANNOT CLASSIFY (no git, branch/ref
# missing, the index document absent) — a check that did not run is never reported as a pass.
#
# The two sides are both overridable so the controls in the test suite can be planted with real refs:
# GIT_REF is the branch the notices send readers to (default attested-bridge), MAIN_REF is the tree
# they claim is missing it (default HEAD).
#
# Tests: bash docs/tools/Test-check-v41-citations.sh   (planted offenders and a planted good tree)
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

DOCS_DIR="${DOCS_DIR:-docs}"
REF="${GIT_REF:-attested-bridge}"
MAIN_REF="${MAIN_REF:-HEAD}"
V41_REL="apps/contracts/contracts/LXONAttestedBridgeV41.sol"
INDEX="$DOCS_DIR/runbooks/v41-citation-form-2026-11-12.md"
MODE="${1:-check}"

fail_n=0; note() { echo "$*"; }
bad() { echo "  FAIL $*"; fail_n=$((fail_n + 1)); }
ok()  { echo "  ok   $*"; }
cfail() { echo "CANNOT-CLASSIFY: $*" >&2; exit 2; }

command -v git >/dev/null || cfail "git is not on PATH, so no rule can be evaluated"
[ -s "$INDEX" ] || cfail "no index document at $INDEX"

# ------------------------------------------------------------------ R1 the pin
blob=$(git rev-parse --verify "${REF}:${V41_REL}" 2>/dev/null) || cfail "ref ${REF}:${V41_REL} is not resolvable in this repository (branch renamed, deleted, or this is a different clone) -- R1 cannot be evaluated"
size=$(git cat-file -s "$blob" 2>/dev/null) || cfail "blob $blob does not unpack"
case "$size" in ''|*[!0-9]*) cfail "blob size came back as '$size', not a number" ;; esac
pinned=$(grep -oE '[0-9a-f]{40}' "$INDEX" | head -1)
[ -n "$pinned" ] || cfail "the index document carries no 40-hex blob pin to check against"
if [ "$blob" = "$pinned" ]; then ok "R1 the pinned blob matches $REF ($blob, $size bytes)"; else
  bad "R1 the V41 blob on $REF is $blob ($size B); the index document pins $pinned -- the citation authority moved, or this pin rotted"
fi
linecheck=$(git cat-file -p "$blob" | grep -c "function claimTransfer" 2>/dev/null) || cfail "could not read the blob's text"
# 1 is not "several": a second definition would make every :480 citation ambiguous
if [ "$linecheck" = 1 ]; then ok "R1 the blob defines claimTransfer exactly once, so :480 is unambiguous"; else
  bad "R1 claimTransfer appears $linecheck times in the blob -- a line-number citation into it is now ambiguous"
fi

# ------------------------------------------------------------------ R2 + R3 + R5 + census, one pass
census() { python3 - "$DOCS_DIR" "$REF" "$V41_REL" "$MAIN_REF" "$INDEX" <<'PY'
import os, re, subprocess, sys
docs_dir, ref, v41rel, main_ref, index = sys.argv[1:6]
TOOL = re.compile(r"apps/contracts/script/v41|apps/attestor")
MARK = "lxon-branch-path-notice:begin"
MENTION = re.compile(r"attested-bridge-wt|branch `attested-bridge`|branch attested-bridge|attested-bridge:")
QUAL = re.compile(r"[\w/:.\-]*LXONAttestedBridgeV41\.sol")
TOKEN = re.compile(r"[\w/:.\-]*LXONAttestedBridgeV41\.sol")
HELIOS_P = re.compile(r"apps/contracts-helios/(reference|src)/")
# The two files whose PURPOSE is to name these dialects, plus Plan 2, whose `reference/` path is the copy
# that plan creates. Excluding them is a decision, not an oversight: a rule document that quotes the
# forbidden spelling would otherwise fail its own check forever, and a silent exemption is worse than a
# listed one. The list is printed in the census so a reader can see what was not judged.
# Matched RELATIVE TO DOCS_DIR, not by a literal "docs/…" string: an exemption keyed to the invocation
# path would quietly stop applying the moment the checker runs against another docs root (which is exactly
# what the test suite does), and a quietly-vacuous rule is the defect this suite exists to catch.
ALLOW = ("runbooks/v41-citation-form-2026-11-12.md",
         "runbooks/contracts-tree-reconciliation-2026-11-06.md",
         "superpowers/plans/2026-11-06-lxon-pqc-plan2-default-profile.md")
def norm(tok):
    t = tok
    for pre in (ref + ":",):
        if t.startswith(pre): t = t[len(pre):]
    m = re.search(r"attested-bridge-wt/(.+)$", t)
    if m: t = m.group(1)
    return t

# ---- R5: the git facts the documents assert about. Counted from git, never from the document.
WATCH = ["apps/contracts/contracts/",
         "apps/contracts/contracts/LXONAttestedBridgeV41.sol",
         "apps/contracts/script/v41/",
         "apps/attestor/",
         "apps/contracts-helios/",
         "apps/contracts-helios/reference/"]
def nfiles(what, path):
    p = subprocess.run(["git", "ls-tree", "-r", "--name-only", what, "--", path],
                       capture_output=True, text=True, timeout=60)
    if p.returncode != 0:
        return None
    return len([l for l in p.stdout.splitlines() if l.strip()])
def ncommits(a, b):
    p = subprocess.run(["git", "rev-list", "--count", "%s..%s" % (a, b)],
                       capture_output=True, text=True, timeout=60)
    if p.returncode != 0:
        return None
    s = p.stdout.strip()
    return int(s) if s.isdigit() else None
cnt = {}
for side, what in (("main", main_ref), ("ref", ref)):
    for w in WATCH:
        n = nfiles(what, w)
        if n is None:
            sys.exit("R5: git could not count %s at %s -- the what-is-where claims cannot be evaluated" % (w, what))
        cnt[(side, w)] = n
ahead = ncommits(ref, main_ref)          # in main, not on the branch
behind = ncommits(main_ref, ref)         # on the branch, not in main
if ahead is None or behind is None:
    sys.exit("R5: git rev-list refused %s..%s -- the divergence claim cannot be evaluated" % (ref, main_ref))
V41D, ATTD = "apps/contracts/script/v41/", "apps/attestor/"
# Paths PQC Plan 2 fills as it works. A count in one of these rows is stale by design -- Task 1 alone
# moved apps/contracts-helios/ from 122 tracked files to 126, and Tasks 2-10 add more -- so these rows
# assert PRESENCE, and R5 refuses a count there. Same rule the divergence row follows, for the same
# reason: a number that changes on every commit is a scheduled failure, not a measurement.
PROPERTY_PATHS = ("apps/contracts-helios/", "apps/contracts-helios/reference/")
r5 = []
PAIR = re.compile(r"(\d+)\s+and\s+(\d+)\s+tracked files")
def claim(cell):
    m = re.search(r"(\d[\d,]*)\s+tracked files", cell)
    if m: return ("n", int(m.group(1).replace(",", "")))
    low = cell.lower()
    if "absent" in low or "does not exist" in low: return ("zero", 0)
    if "present" in low: return ("nonzero", None)
    return (None, None)
def splitrow(line):
    if not line.strip().startswith("|"): return None
    parts = re.split(r"(?<!\\)\|", line.strip())
    cells = [c.strip() for c in parts[1:-1]]
    return cells if len(cells) >= 3 else None
bare_ref = bare_abs = canon = helios = unk = 0
r2, r3 = [], []
n_docs = n_tool = 0
for root, dirs, fs in os.walk(docs_dir):
    dirs[:] = [d for d in dirs if d not in ("node_modules", ".git", "__pycache__")]
    for f in sorted(fs):
        if not f.endswith(".md"):
            continue
        path = os.path.join(root, f)
        try:
            s = open(path, encoding="utf-8", errors="replace").read()
        except Exception:
            continue
        n_docs += 1
        for m in PAIR.finditer(s):                       # the notice's own git claim, checked against git
            want = (cnt[("ref", V41D)], cnt[("ref", ATTD)])
            if (int(m.group(1)), int(m.group(2))) != want:
                r5.append("%s: states %s and %s tracked files; %s tracks %d under %s and %d under %s"
                          % (path, m.group(1), m.group(2), ref, want[0], V41D, want[1], ATTD))
        t = len(TOOL.findall(s))
        if t:
            n_tool += 1
            if MARK not in s and not MENTION.search(s):
                r2.append("%s (%d branch-only path citations, no resolution stated)" % (path, t))
        allowed = os.path.relpath(path, docs_dir) in ALLOW
        if allowed:
            continue                      # an exempt document DESCRIBES spellings; counting them would make
                                          # the census describe the rule text rather than the citations
        for line in s.splitlines():
            canon += len(QUAL.findall(line))
            for full in TOKEN.findall(line):
                nt = norm(full)
                if "attested-bridge" in full or "attested-bridge" in line:
                    continue                  # qualified: the token or its own sentence names the branch/worktree
                if nt == "reference/LXONAttestedBridgeV41.sol":
                    bare_ref += 1
                    r3.append("%s: bare `reference/…` -- the copy exists but is a build anchor, not the citation authority: %s" % (path, line.strip()[:100]))
                elif nt == v41rel:
                    bare_abs += 1
                    r3.append("%s: branch path with no qualifier -- a reader on main has no such file: %s" % (path, line.strip()[:100]))
                elif HELIOS_P.match(nt):
                    helios += 1
                    r3.append("%s: cites the Plan 2 reference copy, which is not on main: %s" % (path, line.strip()[:100]))
                elif "/" in nt:
                    unk += 1
                    r3.append("%s: unrecognised spelling %s" % (path, nt))
                # else: a bare filename mention, which the document's own rule line makes unambiguous

# ---- R5b: the index document's what-is-where table, cell by cell
try:
    itext = open(index, encoding="utf-8", errors="replace").read()
except Exception:
    sys.exit("R5: the index document %s could not be read" % index)
rows = 0
for line in itext.splitlines():
    cells = splitrow(line)
    if not cells:
        continue
    if "divergence" in cells[0].lower():
        # The EXACT divergence counts are re-taken every commit -- a main-side count in prose is stale
        # the moment anyone commits anything, and R5 caught precisely that within minutes of landing.
        # What the row actually asserts is that neither side is a fast-forward, so that is what is judged.
        nums = [int(x.replace(",", "")) for x in re.findall(r"(\d[\d,]*)\s+commits in", line)]
        if nums:
            r5.append("index divergence row carries the counts %s, which move with every commit -- "
                      "assert the property instead (R5 checks `not a fast-forward` and both sides > 0)" % nums)
        if "not a fast-forward" not in line:
            r5.append("index divergence row does not state the divergence property 'not a fast-forward', "
                      "so there is nothing for R5 to check there")
        if not (ahead > 0 and behind > 0):
            r5.append("main and %s are no longer divergent (%d / %d commits apart) -- one side may now "
                      "fast-forward onto the other, which re-opens the decision this document records as declined"
                      % (ref, ahead, behind))
        rows += 1
        continue
    m = re.search(r"`([^`]+)`", cells[0])
    path = m.group(1) if m else ""
    if path not in WATCH or len(cells) < 3:
        continue
    rows += 1
    for side, cell in (("main", cells[1]), ("ref", cells[2])):
        kind, want = claim(cell)
        live = cnt[(side, path)]
        if kind is None:
            continue
        if kind == "n" and any(path.startswith(pp) for pp in PROPERTY_PATHS):
            r5.append("index row %s / %s stores the count %d, but Plan 2 fills that tree -- assert "
                      "presence, not a number (R5 will fail it on the next task otherwise)"
                      % (path, side, want))
            continue
        if kind == "n" and want != live:
            r5.append("index row %s / %s says %d tracked files; git counts %d at %s"
                      % (path, side, want, live, main_ref if side == "main" else ref))
        elif kind == "zero" and live != 0:
            r5.append("index row %s / %s says absent; git counts %d file(s) at %s -- the premise of every notice is gone"
                      % (path, side, live, main_ref if side == "main" else ref))
        elif kind == "nonzero" and live == 0:
            r5.append("index row %s / %s says present; git counts nothing at %s"
                      % (path, side, main_ref if side == "main" else ref))
if rows == 0:
    # a table that was never read would make R5 decoration, and decoration is the failure mode here
    sys.exit("R5 judged 0 rows of %s -- no what-is-where table was found, so nothing was checked" % index)
print("DOCS %d" % n_docs); print("TOOLDOCS %d" % n_tool)
print("CANON %d" % canon); print("BARE_REF %d" % bare_ref); print("BARE_ABS %d" % bare_abs); print("HELIOS %d" % helios)
print("EXCLUDED %d" % len(ALLOW))
print("UNK %d" % unk)
print("REF_V41 %d" % cnt[("ref", V41D)]); print("REF_ATT %d" % cnt[("ref", ATTD)])
print("MAIN_V41 %d" % cnt[("main", V41D)]); print("MAIN_ATT %d" % cnt[("main", ATTD)])
print("DIVERGENT %d" % (1 if ahead > 0 and behind > 0 else 0))   # the property asserted; the counts are display-only
print("TABLE_ROWS %d" % rows)
print("R2 %d" % len(r2)); [print("  r2| " + x) for x in r2]
print("R3 %d" % len(r3)); [print("  r3| " + x) for x in r3[:12]]
print("R5 %d" % len(r5)); [print("  r5| " + x) for x in r5[:12]]
PY
}
out=$(census) || cfail "the census pass died; its output cannot be trusted as a pass"
get() { printf '%s\n' "$out" | awk -v k="$1" '$1==k{print $2}'; }
n_docs=$(get DOCS); n_tool=$(get TOOLDOCS); n_canon=$(get CANON)
n_bref=$(get BARE_REF); n_babs=$(get BARE_ABS); n_hel=$(get HELIOS)
r2=$(get R2); r3=$(get R3); r5=$(get R5)
[ -n "$n_docs" ] && [ -n "$r2" ] && [ -n "$n_hel" ] && [ -n "$r5" ] || cfail "the census pass printed no counters, so R2/R3/R5 never ran"
allowed=$(printf '%s\n' "$out" | awk '/^EXCLUDED/{print $2}'); unk=$(get UNK)

if [ "$MODE" = "--update" ]; then
  python3 - "$INDEX" "$out" <<'PY' || cfail "could not rewrite the census block"
import datetime, sys
idx, block = sys.argv[1], sys.argv[2]
s = open(idx, encoding="utf-8").read()
b, e = "<!-- census:begin -->", "<!-- census:end -->"
if b not in s or e not in s:
    sys.exit("the index document has no census markers")
body = "\n%s\n" % "\n".join("> %s" % l for l in block.splitlines() if l.strip() and "|" not in l)
new = "%s\n%s\n<!-- generated %s UTC by docs/tools/check-v41-citations.sh --update; the numbers are measurements, not prose -->%s" % (
    b, body, datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), e)
open(idx, "w", encoding="utf-8").write(s.replace(s[s.index(b):s.index(e) + len(e)], new))
print("  census rewritten in %s" % idx)
PY
  exit $?
fi

echo "== v4.1 citation check: $n_docs markdown under $DOCS_DIR, $n_tool citing branch-only tooling; $allowed document(s) exempt from R3 by name (rule-definition docs + Plan 2's own copy)"
if [ "$r2" = 0 ]; then ok "R2 every tooling-citing document states how to resolve it"; else
  bad "R2 $r2 document(s) cite branch-only paths with no resolution:"
  printf '%s\n' "$out" | sed -n 's/^  r2| /      /p'
fi
if [ "$r3" = 0 ]; then ok "R3 no bare and no unknown V41 source citation outside the canonical form"; else
  bad "R3 $r3 citation(s) that a reader on main cannot open, or an unrecognised spelling:"
  printf '%s\n' "$out" | sed -n 's/^  r3| /      /p'
fi
# R5: the git facts the documents assert about, re-counted from git on both sides
ref_v41=$(get REF_V41); ref_att=$(get REF_ATT); main_v41=$(get MAIN_V41); main_att=$(get MAIN_ATT)
rows=$(get TABLE_ROWS); divergent=$(get DIVERGENT)
for v in ref_v41 ref_att main_v41 main_att rows divergent; do
  case "${!v}" in ''|*[!0-9]*) cfail "R5 counter $v came back as '${!v}', not a number" ;; esac
done
# display-only: the exact divergence moves with every commit, so it is never written into a document
div_note=$(git rev-list --count "${REF}..${MAIN_REF}" 2>/dev/null)/$(git rev-list --count "${MAIN_REF}..${REF}" 2>/dev/null)
[ -n "${div_note#/}" ] || div_note="unmeasured"
if [ "$r5" = 0 ]; then
  ok "R5 what-is-where holds: $rows table row(s) judged -- $REF tracks $ref_v41 script/v41 + $ref_att attestor files, $MAIN_REF tracks $main_v41 + $main_att, divergent=$divergent (main-only/branch-only $div_note as of this run)"
else
  bad "R5 $r5 what-is-where claim(s) no longer match git -- the notices or the index table must be re-taken:"
  printf '%s\n' "$out" | sed -n 's/^  r5| /      /p'
fi
# R4: the document must carry the numbers this run measured, not the numbers 2026-11-06 measured.
# Every generated counter is compared, including R5's git counts -- the census is the machine-readable
# copy of the same facts the prose asserts, so a census that no longer matches this run is drift.
live="DOCS $n_docs TOOLDOCS $n_tool CANON $n_canon BARE_REF $n_bref BARE_ABS $n_babs HELIOS $n_hel EXCLUDED $allowed UNK $unk REF_V41 $ref_v41 REF_ATT $ref_att MAIN_V41 $main_v41 MAIN_ATT $main_att DIVERGENT $divergent TABLE_ROWS $rows"
CENGRE='DOCS [0-9]+ TOOLDOCS [0-9]+ CANON [0-9]+ BARE_REF [0-9]+ BARE_ABS [0-9]+ HELIOS [0-9]+ EXCLUDED [0-9]+ UNK [0-9]+ REF_V41 [0-9]+ REF_ATT [0-9]+ MAIN_V41 [0-9]+ MAIN_ATT [0-9]+ DIVERGENT [0-9]+ TABLE_ROWS [0-9]+'
docline=$(printf '%s' "$(sed -n '/census:begin/,/census:end/p' "$INDEX" | tr '\n' ' ' | sed -e 's/> //g' -e 's/  */ /g')" | grep -oE "$CENGRE")
if [ -z "$docline" ]; then
  bad "R4 the index document records no census line; run with --update"
elif [ "$docline" = "$live" ]; then
  ok "R4 the index census equals this run: $live"
else
  bad "R4 stale census: document says [$docline], this run measured [$live]. Run: bash docs/tools/check-v41-citations.sh --update"
fi

echo
if [ "$fail_n" = 0 ]; then echo "== clean: $n_canon canonical citations, pin $blob"; exit 0; fi
echo "== $fail_n rule(s) failed"; exit 1

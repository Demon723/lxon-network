#!/usr/bin/env bash
# docs/tools/Test-check-v41-citations.sh — does the citation checker actually distinguish?
#
# A checker that only ever prints ok is the failure family this repo has been burned by repeatedly
# (2026-11-12 runbook §7: a green integration probe on known-bad payloads). So every rule in
# check-v41-citations.sh is planted with its opposite: a good fixture tree must exit 0, and each
# single defect must exit nonzero for the RIGHT reason — the reason is matched against the emitted
# message, not only the exit code, because a tree can fail for something that has nothing to do with
# the fault you planted.
#
# Three controls come with the defects, because a one-sided suite is how the last checker went rotten:
#   - `--update` must be what makes the fixture clean (otherwise R4 could be decoration),
#   - a document that resolves branch paths by MENTION alone, with no notice block, must still pass R2,
#   - and the same branch path QUALIFIED by `branch attested-bridge` must still pass R3.
#
# R1 is evaluated against the real repository even under fixtures (the pin is a git fact, not a text
# fact), which is why the pin-mismatch case corrupts the DOCUMENT side rather than the branch.
#
# Every text edit is done in python and every planting asserts it changed something: macOS sed and
# GNU sed disagree about -i, and an in-place edit that silently fails here plants no fault at all and
# reports a clean tree — the exact false green this suite exists to prevent.
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHK=docs/tools/check-v41-citations.sh
[ -s "$CHK" ] || { echo "FATAL no $CHK"; exit 2; }

T="$(mktemp -d "${TMPDIR:-/tmp}/lxon-citchk.XXXXXX")" || exit 2
trap 'rm -rf "$T"' EXIT

PIN=$(git rev-parse --verify attested-bridge:apps/contracts/contracts/LXONAttestedBridgeV41.sol 2>/dev/null) \
  || { echo "FATAL cannot resolve the V41 blob on attested-bridge; nothing here can be judged"; exit 2; }
[ -n "$PIN" ] || { echo "FATAL empty pin"; exit 2; }

# R5's fixture table must carry the SAME numbers the checker is about to re-count from git, so the
# clean tree exercises "prose matches git" and every R5 fault is a one-character edit, not a guess.
cnt() { git ls-tree -r --name-only "$1" -- "$2" 2>/dev/null | wc -l | tr -d ' '; }
R_V41=$(cnt attested-bridge apps/contracts/script/v41/)
R_ATT=$(cnt attested-bridge apps/attestor/)
M_CC=$(cnt HEAD apps/contracts/contracts/)
M_HELIOS=$(cnt HEAD apps/contracts-helios/)
AHEAD=$(git rev-list --count attested-bridge..HEAD)
BEHIND=$(git rev-list --count HEAD..attested-bridge)
[ -n "$R_V41" ] && [ -n "$M_CC" ] && [ -n "$AHEAD" ] || { echo "FATAL git could not count the what-is-where inputs"; exit 2; }
[ "$R_V41" != 0 ] || { echo "FATAL the branch has no script/v41 to point readers at; R5 cannot be exercised"; exit 2; }

mk_tree() { # a minimal good tree: index doc (pin + table + markers) + one marked runbook + exempt docs
  local d="$1"
  mkdir -p "$d/runbooks" "$d/tools" "$d/superpowers/plans"
  { echo "# index"
    echo
    echo "The pin below is the authority for every line-number citation in these docs:"
    echo
    echo "\`blob\`"
    echo "    $PIN"
    echo
    echo "## 1. What is where"
    echo
    echo "| path | \`main\` | branch \`attested-bridge\` |"
    echo "|---|---|---|"
    echo "| \`apps/contracts/contracts/\` | $M_CC tracked files | same directory |"
    echo "| \`apps/contracts/contracts/LXONAttestedBridgeV41.sol\` | absent | present |"
    echo "| \`apps/contracts/script/v41/\` | absent | $R_V41 tracked files |"
    echo "| \`apps/attestor/\` | absent | $R_ATT tracked files |"
    echo "| \`apps/contracts-helios/\` | present -- Plan 2 fills this tree, so no count is asserted | present |"
    echo "| \`apps/contracts-helios/reference/\` | present -- pinned by blob, not by count | does not exist |"
    echo "| divergence | **not a fast-forward**: main has commits the branch lacks | **not a fast-forward**: the branch has commits main lacks |"
    echo
    echo "<!-- census:begin -->"
    echo "> PLACEHOLDER"
    echo "<!-- census:end -->"; } > "$d/runbooks/v41-citation-form-2026-11-12.md"
  { echo "# good runbook"
    echo
    echo "<!-- lxon-branch-path-notice:begin -->"
    echo "> tooling lives on branch attested-bridge (worktree /Users/adikamble/LXON/attested-bridge-wt) --"
    echo "> $R_V41 and $R_ATT tracked files there, both directories absent from \`main\`;"
    echo "> resolve it with: git worktree add ../attested-bridge-wt attested-bridge"
    echo "<!-- lxon-branch-path-notice:end -->"
    echo
    echo "run \`bash apps/contracts/script/v41/Broadcast724Signed.sh\` from the worktree"
    echo
    echo "the claim entry point is \`attested-bridge:apps/contracts/contracts/LXONAttestedBridgeV41.sol:480\`"; } > "$d/runbooks/good.md"
  echo "# exempt: this document DESCRIBES the forbidden spellings" > "$d/runbooks/contracts-tree-reconciliation-2026-11-06.md"
  echo "# exempt plan: this plan CREATES the reference/ copy" > "$d/superpowers/plans/2026-11-06-lxon-pqc-plan2-default-profile.md"
}

pass=0; fail=0
run() { # run <dir> -> sets RC, LOG
  local d="$1"
  DOCS_DIR="$d" bash "$CHK" >"$d.out" 2>&1; RC=$?; LOG=$(cat "$d.out")
}
upd() { DOCS_DIR="$1" bash "$CHK" --update >/dev/null 2>&1; }   # re-measure so only the planted fault is live

expect() { # expect <name> <want rc | nonzero> <substring the message must contain>
  local name="$1" want="$2" pat="$3" good=0
  if [ "$want" = "nonzero" ]; then
    [ "$RC" != 0 ] && good=1
  else
    [ "$RC" = "$want" ] && good=1
  fi
  if [ "$good" = 1 ] && { [ -z "$pat" ] || printf '%s\n' "$LOG" | grep -q -- "$pat"; }; then
    echo "  ok   $name (exit $RC)"; pass=$((pass + 1))
  else
    echo "  BAD  $name: exit $RC want $want${pat:+, message must contain [$pat]}"
    printf '%s\n' "$LOG" | tail -5
    fail=$((fail + 1))
  fi
}

echo "== 1. the control: --update is what makes the fixture clean, and clean must exit 0"
mk_tree "$T/good"
DOCS_DIR="$T/good" bash "$CHK" >"$T/pre.log" 2>&1; RC=$?; LOG=$(cat "$T/pre.log")
expect "PLACEHOLDER census is rejected before --update (R4 is live)" nonzero "R4"
upd "$T/good"
run "$T/good"
expect "clean fixture tree" 0 "== clean"

echo
echo "== 2. R2 — a document citing branch-only tooling without saying how to resolve it"
mk_tree "$T/r2"
python3 - "$T/r2/runbooks/unresolved.md" <<'PY'
import sys
open(sys.argv[1], "w", encoding="utf-8").write(
    "# a runbook added later\n\n"
    "step 1: `bash apps/contracts/script/v41/Broadcast724Signed.sh`\n"
    "step 2: `python3 apps/attestor/relayer.py --claim`\n")
PY
[ "$?" = 0 ] && [ -s "$T/r2/runbooks/unresolved.md" ] || { echo "FATAL the R2 fixture document was not planted"; exit 2; }
upd "$T/r2"
run "$T/r2"
expect "a new unmarked tooling document -> R2 fails" 1 "R2"

echo
echo "== 2b. control — a MENTION with no notice block is the same rule, satisfied another way"
mk_tree "$T/r2ok"
python3 - "$T/r2ok/runbooks/mentioned.md" <<'PY'
import sys
open(sys.argv[1], "w", encoding="utf-8").write(
    "# resolved by prose, not by a marker\n\n"
    "everything below runs from the `attested-bridge-wt` worktree:\n"
    "`bash apps/contracts/script/v41/Broadcast724Signed.sh`\n")
PY
[ "$?" = 0 ] && [ -s "$T/r2ok/runbooks/mentioned.md" ] || { echo "FATAL the R2 control document was not planted"; exit 2; }
upd "$T/r2ok"
run "$T/r2ok"
expect "worktree mention alone -> R2 still passes" 0 "== clean"

echo
echo "== 3. R3 — the citation forms a reader on main cannot open"
while IFS='|' read -r lbl ins pat; do
  [ -n "$lbl" ] || continue
  mk_tree "$T/r3-$lbl"
  printf '\ncites `%s` with nothing around it\n' "$ins" >> "$T/r3-$lbl/runbooks/good.md"
  grep -qF "cites \`$ins\`" "$T/r3-$lbl/runbooks/good.md" || { echo "FATAL R3 case $lbl was not planted"; exit 2; }
  upd "$T/r3-$lbl"
  run "$T/r3-$lbl"
  expect "R3 catches $lbl" 1 "$pat"
done <<'CASES'
bare-ref|reference/LXONAttestedBridgeV41.sol:480|bare `reference/
bare-branch-path|apps/contracts/contracts/LXONAttestedBridgeV41.sol:480|branch path with no qualifier
fifth-spelling|apps/contracts-helios/vendor/LXONAttestedBridgeV41.sol:480|unrecognised spelling
CASES

echo
echo "== 3b. control — the same path, qualified, must be accepted"
mk_tree "$T/r3ok"
printf '\nsee `apps/contracts/contracts/LXONAttestedBridgeV41.sol:480` on branch attested-bridge\n' >> "$T/r3ok/runbooks/good.md"
grep -q 'on branch attested-bridge' "$T/r3ok/runbooks/good.md" || { echo "FATAL the R3 control was not planted"; exit 2; }
upd "$T/r3ok"
run "$T/r3ok"
expect "qualified branch-path citation -> R3 still passes" 0 "== clean"

echo
echo "== 4. R1 — the pin is a measurement, so a document that pins a moved blob is a failure"
mk_tree "$T/pin"
python3 - "$T/pin/runbooks/v41-citation-form-2026-11-12.md" "$PIN" <<'PY'
import sys
p, pin = sys.argv[1:3]
s = open(p, encoding="utf-8").read()
if pin not in s:
    sys.exit("the fixture index doc does not carry the real pin; nothing was planted")
other = ("f" * 40) if pin[0] != "f" else ("0" * 40)
open(p, "w", encoding="utf-8").write(s.replace(pin, other))
PY
[ "$?" = 0 ] || { echo "FATAL could not plant the pin fault"; exit 2; }
upd "$T/pin"
run "$T/pin"
expect "R1 catches a wrong pin" 1 "the index document pins"

echo
echo "== 5. R4 — prose numbers must match this run"
mk_tree "$T/r4"
upd "$T/r4"
python3 - "$T/r4/runbooks/v41-citation-form-2026-11-12.md" <<'PY'
import re, sys
p = sys.argv[1]
lines = open(p, encoding="utf-8").read().splitlines(True)
for i, l in enumerate(lines):
    m = re.match(r"^> DOCS (\d+)\s*$", l)
    if m:
        lines[i] = "> DOCS %d\n" % (int(m.group(1)) + 1)   # one counter, one line: the block is per-line, not inline
        break
else:
    sys.exit("the fixture has no '> DOCS <n>' census line, so --update never populated it")
open(p, "w", encoding="utf-8").write("".join(lines))
PY
[ "$?" = 0 ] || { echo "FATAL could not plant the census fault"; exit 2; }
run "$T/r4"
expect "R4 catches a stale census" 1 "stale census"

echo
echo "== 6. R5 — the git facts the documents assert about, re-counted from git"
mk_tree "$T/r5pair"
python3 - "$T/r5pair/runbooks/good.md" "$R_V41" "$R_ATT" <<'PY'
import sys
p, v41, att = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
old = "%s and %s tracked files" % (v41, att)
if old not in s:
    sys.exit("the fixture notice does not carry the live pair; nothing was planted")
open(p, "w", encoding="utf-8").write(s.replace(old, "%d and %s tracked files" % (int(v41) + 1, att), 1))
PY
[ "$?" = 0 ] || { echo "FATAL could not plant the notice-pair fault"; exit 2; }
upd "$T/r5pair"
run "$T/r5pair"
expect "a notice that states the wrong file counts -> R5 fails" 1 "tracked files; "

mk_tree "$T/r5table"
python3 - "$T/r5table/runbooks/v41-citation-form-2026-11-12.md" "$R_ATT" <<'PY'
import sys
p, att = sys.argv[1:3]
s = open(p, encoding="utf-8").read()
old = "%s tracked files" % att
if old not in s:
    sys.exit("the fixture table has no attestor count; nothing was planted")
open(p, "w", encoding="utf-8").write(s.replace(old, "9999 tracked files", 1))
PY
[ "$?" = 0 ] || { echo "FATAL could not plant the table fault"; exit 2; }
upd "$T/r5table"
run "$T/r5table"
expect "an index table with a wrong count -> R5 fails" 1 "index row"

DOCS_DIR="$T/good" MAIN_REF=attested-bridge bash "$CHK" --update >/dev/null 2>&1
DOCS_DIR="$T/good" MAIN_REF=attested-bridge bash "$CHK" >"$T/m.log" 2>&1; RC=$?; LOG=$(cat "$T/m.log")
expect "the dirs are not absent when main is taken to be the branch -> R5 fails" 1 "says absent"
upd "$T/good"

echo
echo "== 6d. R5 — a divergence row that stores commit counts is refused, not compared"
mk_tree "$T/r5count"
python3 - "$T/r5count/runbooks/v41-citation-form-2026-11-12.md" "$AHEAD" "$BEHIND" <<'PY'
import sys
p, ahead, behind = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
old = "| divergence | **not a fast-forward**: main has commits the branch lacks | **not a fast-forward**: the branch has commits main lacks |"
if old not in s:
    sys.exit("the fixture divergence row is not what mk_tree writes; nothing was planted")
new = "| divergence | %s commits in `main` not in `attested-bridge` | %s commits in `attested-bridge` not in `main` |" % (ahead, behind)
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
[ "$?" = 0 ] || { echo "FATAL could not plant the counted divergence row"; exit 2; }
upd "$T/r5count"
run "$T/r5count"
expect "commit counts in prose -> R5 refuses them (they are stale by construction)" 1 "carries the counts"

echo
echo "== 6e. R5 — a count in a row Plan 2 fills is refused before it can go stale"
mk_tree "$T/r5prop"
python3 - "$T/r5prop/runbooks/v41-citation-form-2026-11-12.md" <<'PYIN'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = "| `apps/contracts-helios/` | present -- Plan 2 fills this tree, so no count is asserted | present |"
if old not in s:
    sys.exit("the helios property row is not what mk_tree writes; nothing was planted")
open(p, "w", encoding="utf-8").write(s.replace(old, "| `apps/contracts-helios/` | 122 tracked files | present |", 1))
PYIN
[ "$?" = 0 ] || { echo "FATAL could not plant the property-row count"; exit 2; }
upd "$T/r5prop"
run "$T/r5prop"
expect "a stored count in a tree the plan fills -> R5 refuses it" 1 "stores the count"

echo
echo "== 6b. control — R5 with no table to judge is cannot-classify, not a pass"
mk_tree "$T/r5none"
python3 - "$T/r5none/runbooks/v41-citation-form-2026-11-12.md" <<'PY'
import sys
p = sys.argv[1]
keep, dropped = [], 0
for l in open(p, encoding="utf-8").read().splitlines(True):
    if l.startswith("| `apps/") or l.startswith("| divergence"):
        dropped += 1
        continue
    keep.append(l)
if dropped < 7:
    sys.exit("only %d judged rows removed; the fixture table is not what mk_tree writes" % dropped)
open(p, "w", encoding="utf-8").write("".join(keep))
PY
[ "$?" = 0 ] || { echo "FATAL could not strip the fixture table"; exit 2; }
DOCS_DIR="$T/r5none" bash "$CHK" >"$T/nolog3" 2>&1; RC=$?; LOG=$(cat "$T/nolog3")
expect "no what-is-where table -> cannot classify" 2 "CANNOT-CLASSIFY"

echo
echo "== 7. a check that cannot run is never reported as a pass"
DOCS_DIR="$T/does-not-exist" bash "$CHK" >"$T/nolog" 2>&1; RC=$?; LOG=$(cat "$T/nolog")
expect "no index document -> cannot classify" 2 "CANNOT-CLASSIFY"
GIT_REF=no-such-branch-here DOCS_DIR="$T/good" bash "$CHK" >"$T/nolog2" 2>&1; RC=$?; LOG=$(cat "$T/nolog2")
expect "branch ref unresolvable -> cannot classify" 2 "R1 cannot be evaluated"

echo
echo "== $pass ok, $fail BAD"
[ "$fail" = 0 ] || exit 1
exit 0

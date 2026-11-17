#!/usr/bin/env bash
# Listing-truth gate: does anything in this repo still tell a stranger that a dead 724 contract is live?
#
# It wraps lxon-evm-node/aws-freetier/check-dead-724-addr.py, which re-MEASURES the dead set against
# rpc.lxon.in on every run (chain id, block 0, and a positive control on Polygon 137) and classifies
# every non-markdown file that names one. The prose pass is a different tool: annotate-dead-724-docs.py.
#
#   ./scripts/check-listing-truth.sh                  # gate anything publishable; scan repo + worktree
#   ./scripts/check-listing-truth.sh --json           # machine-readable, for CI
#   ./scripts/check-listing-truth.sh --root <dir>     # EXTRA root (repeatable; additive by design)
#
# --strict is always on. It used to be the default only when no arguments were given, so
# `check-listing-truth.sh --root <somewhere>` quietly lost the strict tally check as well as narrowing
# the scan -- an argument that widened the search also disabled the thing the gate exists to do.
#
# Exit codes, deliberately not all "1":
#   0  clean -- the dead set was measured and no publishable file asserts one as live
#   2  findings -- see the list it prints; withdraw it or rebuild it, do not silence it
#   4  NOT MEASURED -- the RPC was unreachable, block 0 was not the recovered genesis, or the 137
#      control read too small. This is not a pass and not a repo defect: it means the check did not
#      happen. Mapping it to "2" is how a gate gets ignored on a flaky network and then trusted on a
#      real one.
set -uo pipefail

# REPO_ROOT is overridable so the test suite can point this wrapper at a throwaway tree holding a stub
# checker. Without it the wrapper always resolves against its own repository, and every "test" would
# silently run the real checker over the real network -- green, and proving nothing about the wrapper.
# Split across three lines on purpose: bash 3.2 (the /bin/bash on this Mac) mis-parses a command
# substitution whose quoted body contains another substitution, nested inside ${...:-...} inside quotes.
HERE_DIR="$(dirname "${BASH_SOURCE[0]}")"
REPO_DEFAULT="$(cd "$HERE_DIR/.." && pwd)"
REPO="${REPO_ROOT:-$REPO_DEFAULT}"
cd "$REPO" 2>/dev/null || { echo "NOT MEASURED: cannot enter $REPO" >&2; exit 4; }
CHECKER="${CHECKER:-$REPO/lxon-evm-node/aws-freetier/check-dead-724-addr.py}"
[ -f "$CHECKER" ] || { echo "NOT MEASURED: no checker at $CHECKER (set CHECKER=...)" >&2; exit 4; }

# The classifier's own controls run first, offline. If a rule in the checker is broken, every verdict
# it prints is worthless -- and a broken rule shows up as silence (a green gate), not as an error.
st="$("${PYTHON_BIN:-python3}" "$CHECKER" --selftest 2>&1)"; stc=$?
if [ "$stc" != "0" ]; then
  printf '%s\n' "$st" >&2
  echo "NOT MEASURED: the checker's classifier selftest failed (exit $stc) -- its verdicts cannot be trusted" >&2
  exit 4
fi
printf '%s\n' "$st" | tail -1

ARGS=(--strict "$@")
out="$("${PYTHON_BIN:-python3}" "$CHECKER" "${ARGS[@]}" 2>&1)"; rc=$?
echo "$out"

case "$rc" in
  0)
    # Prove the pass is a pass and not an accident of parsing: the checker must have reported a
    # measured control, a PUBLISH tally of zero, AND a non-zero file census. The adversarial review
    # found that `--root /no/such/dir` printed "CLEAN (measured)" with exit 0 after opening zero
    # files -- the control line is a chain read, so it passes whether or not any file was scanned.
    # "A run that measured nothing can never print CLEAN" has to be enforced on the CENSUS, not on
    # prose that a scan can produce without looking at a single file.
    printf '%s' "$out" | grep -q "control: v4.1 bridge on 137 reads" \
      || { echo "NOT MEASURED: exit 0 without the 137 control line -- refusing to call this clean" >&2; exit 4; }
    pb=$(printf '%s' "$out" | sed -n 's/^== PUBLISH: \([0-9]*\) file.*/\1/p')
    if [ -z "$pb" ]; then
      # --json mode carries the same tally as a field, not a prose line. Before this the documented
      # CI mode could never pass the gate at all: it always exited 4 for want of a line it never prints.
      pb=$(printf '%s' "$out" | sed -n 's/^[[:space:]]*"PUBLISH": *\([0-9]*\),*$/\1/p' | head -1)
    fi
    [ -n "$pb" ] || { echo "NOT MEASURED: exit 0 but no PUBLISH tally was reported in any shape" >&2; exit 4; }
    [ "$pb" -eq 0 ] || { echo "NOT MEASURED: exit 0 with PUBLISH=$pb -- the strict tally did not agree with the pass" >&2; exit 4; }
    # both shapes: the prose census line, and the "scanned" field --json mode prints instead
    scanned=$(printf '%s' "$out" | sed -n 's/^  files opened and read by this scan: \([0-9]*\)$/\1/p')
    if [ -z "$scanned" ]; then
      scanned=$(printf '%s' "$out" | sed -n 's/^[[:space:]]*"scanned": *\([0-9]*\),*$/\1/p' | head -1)
    fi
    [ -n "$scanned" ] || { echo "NOT MEASURED: exit 0 but no file census was reported in any shape -- cannot confirm anything was scanned" >&2; exit 4; }
    [ "$scanned" -gt 0 ] || { echo "NOT MEASURED: the scan opened 0 files. A census of nothing is not a clean result." >&2; exit 4; }
    # The two advisory counts, in whichever shape this run printed. Reading them only from the prose
    # lines made --json report "0 submission artifact(s) WITHDRAWN" when the tally said 7 -- a summary
    # line that contradicts the data it is summarising is worse than no summary.
    tally_of() {
      local k="$1" v script
      v=$(printf '%s' "$out" | sed -n "s/^== ${k}: \\([0-9]*\\) file.*/\\1/p")
      if [ -z "$v" ]; then
        # Built by concatenating around single quotes so the JSON quote character needs no shell
        # escaping at all. A previous version escaped it inside a double-quoted string, the backslash
        # got dropped, and the pattern lost its opening quote -- so it matched nothing and the summary
        # printed "0 submission artifact(s) WITHDRAWN" over a tally that said 7.
        script='s/^[[:space:]]*"'$k'": *\([0-9]*\),*$/\1/p'
        v=$(printf '%s' "$out" | sed -n "$script" | head -1)
      fi
      printf '%s' "${v:-0}"
    }
    wd=$(tally_of PUBLISH-WITHDRAWN)
    other=$(tally_of OTHER)
    echo "CLEAN (measured): no publishable file asserts a dead 724 address as live."
    echo "  it scanned ${scanned} file(s) and passes with ${wd:-0} submission artifact(s) WITHDRAWN and ${other:-0} file(s) in OTHER --"
    echo "  withdrawn is not repaired, and OTHER is unmatched, not benign. Rebuild both after the redeploy."
    exit 0 ;;
  2) echo "FINDINGS: a publishable file names a dead 724 contract without saying it is dead." >&2
     exit 2 ;;
  4) echo "NOT MEASURED: the dead set could not be established this run. Fix reachability, do not skip." >&2
     exit 4 ;;
  *) echo "NOT MEASURED: the checker died with exit $rc -- that is not a pass." >&2; exit 4 ;;
esac

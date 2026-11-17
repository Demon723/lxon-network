#!/usr/bin/env bash
# Tests for scripts/check-listing-truth.sh, written the same way as test-check-secrets.sh: every case
# is built in a throwaway directory against a stub checker, so nothing here needs an RPC and nothing
# here touches the real repo. The point of the tests is not "the wrapper runs python" -- it is that a
# run which MEASURED NOTHING can never be reported as a pass, because the failure mode of a truth gate
# is not a false alarm, it is a green light nobody earned.
#
#   ./scripts/test-check-listing-truth.sh
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
WRAP_ABS="$PWD/scripts/check-listing-truth.sh"
[ -f "$WRAP_ABS" ] || { echo "no wrapper at $WRAP_ABS" >&2; exit 1; }

pass=0; fail=0; TEMPS=()
cleanup() { local d; for d in "${TEMPS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

t() { # t <name> <want-exit> <got-exit> <output> [must-contain]
  local name="$1" want="$2" got="$3" out="$4" needle="${5:-}"
  if [ "$want" != "$got" ]; then
    echo "FAIL $name: want exit $want, got $got"; fail=$((fail+1)); return
  fi
  if [ -n "$needle" ] && ! printf '%s' "$out" | grep -qF -- "$needle"; then
    echo "FAIL $name: exit $want but the output does not contain '$needle'"; fail=$((fail+1)); return
  fi
  echo "ok   $name"; pass=$((pass+1))
}

stub_repo() { # stub_repo <body-of-stub> -> prints the dir to use as CHECKER parent
  local d; d="$(mktemp -d)"; TEMPS+=("$d")
  mkdir -p "$d/lxon-evm-node/aws-freetier" "$d/scripts"
  cat > "$d/lxon-evm-node/aws-freetier/check-dead-724-addr.py"
  chmod +x "$d/lxon-evm-node/aws-freetier/check-dead-724-addr.py"
  printf '%s\n' "$d"
}

run() { # run <dir> [extra wrapper args...] -> echoes "<exit>\n<output>", with REPO_ROOT pointed at the
        # throwaway tree so the wrapper resolves the stub checker there instead of running the real one
        # over the network. Extra args are needed to test the argument-handling bugs specifically.
  local d="$1"; shift
  local out rc
  out="$(REPO_ROOT="$d" bash "$WRAP_ABS" "$@" 2>&1)"; rc=$?
  printf '%s\n%s\n' "$rc" "$out"
}

GOOD_BODY='#!/usr/bin/env python3
import sys
print("measured this run:")
print("  control: v4.1 bridge on 137 reads 19105 bytes via https://polygon-bor-rpc.publicnode.com")
print("  files opened and read by this scan: 1234")
print("== PUBLISH: 0 file(s)")
print("== PUBLISH-WITHDRAWN: 7 file(s)")
print("== OTHER: 2 file(s)")
sys.exit(0)'

# T1 -- a genuinely measured pass
d="$(stub_repo <<< "$GOOD_BODY")"
r="$(run "$d")"
t "T1 measured pass reports CLEAN and says it measured" 0 "$(printf '%s' "$r" | sed -n 1p)" "$r" "CLEAN (measured)"

# T2 -- withdrawn files are named in the summary, not silently excused
printf '%s' "$r" | grep -q "7 submission artifact(s) WITHDRAWN" \
  && { echo "ok   T2 withdrawn count is printed on every pass"; pass=$((pass+1)); } \
  || { echo "FAIL T2 withdrawn count missing"; fail=$((fail+1)); }

# T3 -- findings
d="$(stub_repo <<<'#!/usr/bin/env python3
import sys
if "--selftest" in sys.argv:
    print("selftest: 9/9"); sys.exit(0)
print("  control: v4.1 bridge on 137 reads 19105 bytes via x")
print("== PUBLISH: 1 file(s)")
sys.exit(2)')"
r="$(run "$d")"
t "T3 findings exit 2 is reported as findings" 2 "$(printf '%s' "$r" | sed -n 1p)" "$r" "FINDINGS"

# T4 -- refusal is NOT a repo defect
d="$(stub_repo <<<'#!/usr/bin/env python3
import sys
if "--selftest" in sys.argv:
    print("selftest: 9/9"); sys.exit(0)
print("REFUSED: rpc unreachable", file=sys.stderr); sys.exit(4)')"
r="$(run "$d")"
t "T4 a refused measurement reports NOT MEASURED" 4 "$(printf '%s' "$r" | sed -n 1p)" "$r" "NOT MEASURED"

# T5 -- the trap: exit 0 with no control line. This is the run that must not look like a pass.
d="$(stub_repo <<<'#!/usr/bin/env python3
import sys
if "--selftest" in sys.argv:
    print("selftest: 9/9"); sys.exit(0)
print("== PUBLISH: 0 file(s)")
sys.exit(0)')"
r="$(run "$d")"
t "T5 exit 0 without the control line is refused" 4 "$(printf '%s' "$r" | sed -n 1p)" "$r" "without the 137 control"

# T6 -- exit 0 with the control but PUBLISH not zero (a checker that forgot to fail)
d="$(stub_repo <<<'#!/usr/bin/env python3
import sys
if "--selftest" in sys.argv:
    print("selftest: 9/9"); sys.exit(0)
print("  control: v4.1 bridge on 137 reads 19105 bytes via x")
print("== PUBLISH: 3 file(s)")
sys.exit(0)')"
r="$(run "$d")"
t "T6 exit 0 while PUBLISH is non-zero is refused" 4 "$(printf '%s' "$r" | sed -n 1p)" "$r" "PUBLISH=3"

# T7 -- a checker that dies on a traceback. It answers --selftest fine so that this case still tests
# the wrapper's mapping of a crashed scan; a stub that fails --selftest belongs to T9, not here.
d="$(stub_repo <<'STUB7EOF'
#!/usr/bin/env python3
import sys
if "--selftest" in sys.argv:
    print("selftest: 9/9"); sys.exit(0)
raise RuntimeError("boom")
STUB7EOF
)"
r="$(run "$d")"
t "T7 a checker that crashes is NOT MEASURED, never a pass" 4 "$(printf '%s' "$r" | sed -n 1p)" "$r" "not a pass"

# T8 -- no checker at all
d="$(stub_repo <<< "$GOOD_BODY")"
rm -f "$d/lxon-evm-node/aws-freetier/check-dead-724-addr.py"
r="$(run "$d")"
t "T8 a missing checker refuses instead of passing" 4 "$(printf '%s' "$r" | sed -n 1p)" "$r" "NOT MEASURED: no checker"

# T9 -- a checker whose own classifier controls fail must not be able to print a pass. The stub below
# exits 0 on the real scan (a green verdict) but 1 on --selftest, which is exactly what a silently
# broken rule looks like from the wrapper's side.
d="$(stub_repo <<'STUBEOF'
#!/usr/bin/env python3
import sys
if "--selftest" in sys.argv:
    print("FAIL bare live claim is PUBLISH  want=PUBLISH got=RECORD")
    print("selftest: 8/9")
    sys.exit(1)
print("  control: v4.1 bridge on 137 reads 19105 bytes via x")
print("== PUBLISH: 0 file(s)")
sys.exit(0)
STUBEOF
)"
r="$(run "$d")"
r_first="$(printf '%s' "$r" | sed -n 1p)"
t "T9 a broken classifier selftest blocks a green verdict" 4 "$r_first" "$r" "selftest failed"

# T10 -- the census gate. An adversarial review produced "CLEAN (measured)", exit 0, from
# `check-listing-truth.sh --root /no/such/dir`: the control line is a CHAIN read, so it prints even when
# zero files were opened. A green gate that scanned nothing is the exact failure this suite exists for.
d="$(stub_repo <<'STUB10EOF'
#!/usr/bin/env python3
import sys
if "--selftest" in sys.argv:
    print("selftest: 13/13"); sys.exit(0)
print("  control: v4.1 bridge on 137 reads 19105 bytes via x")
print("  files opened and read by this scan: 0")
print("== PUBLISH: 0 file(s)")
sys.exit(0)
STUB10EOF
)"
r="$(run "$d")"
t "T10 a scan that opened zero files cannot print CLEAN" 4 "$(printf '%s' "$r" | sed -n 1p)" "$r" "0 files"

# T11 -- --strict must survive being given an argument. It used to be the default only when argv was
# empty, so `--root <dir>` silently switched the strict tally check off as well as widening the scan.
d="$(stub_repo <<'STUB11EOF'
#!/usr/bin/env python3
import sys
if "--selftest" in sys.argv:
    print("selftest: 13/13"); sys.exit(0)
if "--strict" not in sys.argv:
    # behaves like a checker whose strict gate was dropped: everything green, nothing enforced
    print("  control: v4.1 bridge on 137 reads 19105 bytes via x")
    print("  files opened and read by this scan: 99")
    print("== PUBLISH: 3 file(s)")
    sys.exit(0)
print("  control: v4.1 bridge on 137 reads 19105 bytes via x")
print("  files opened and read by this scan: 99")
print("== PUBLISH: 3 file(s)")
sys.exit(2)
STUB11EOF
)"
r="$(run "$d" --root /somewhere/else)"
t "T11 --strict is forwarded even when the caller passes other arguments" 2 "$(printf '%s' "$r" | sed -n 1p)" "$r" "FINDINGS"


# T12 -- the tally must be readable from --json too, and must still refuse when it is not zero.
# Before this, --json was a documented mode that could never pass the gate: the wrapper grepped for a
# prose line that json does not print, so every CI invocation exited 4 on a green repo -- and a gate
# that always fails gets switched off, which is how a gate dies.
d="$(stub_repo <<'STUB12EOF'
#!/usr/bin/env python3
import sys
if "--selftest" in sys.argv:
    print("selftest: 16/16"); sys.exit(0)
print("{")
print('  "measured": [')
print('    "control: v4.1 bridge on 137 reads 19105 bytes via x"')
print('  ],')
print('  "tally": {')
print('    "PUBLISH": 3,')
print('    "PUBLISH-WITHDRAWN": 0,')
print('    "OTHER": 0')
print('  },')
print('  "scanned": 99')
print("}")
sys.exit(0)
STUB12EOF
)"
r="$(run "$d" --json)"
t "T12 a json PUBLISH tally above zero is still refused" 4 "$(printf '%s' "$r" | sed -n 1p)" "$r" "PUBLISH=3"

echo; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1

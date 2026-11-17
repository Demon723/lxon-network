#!/usr/bin/env bash
# Tests for scripts/check-secrets.sh -- the gate that is supposed to stand between a private key and
# a push. Written red-first against the 2026-10-22 gate, which had one hole I proved on the real
# repository: it enumerated `git ls-files` and then required `[ -f "$f" ]`, so a secret that sits at
# HEAD but is deleted in the working tree is invisible to it. deploy-amm-gce.sh was exactly that
# case on 2026-11-02: tracked key at HEAD, absent from disk, gate printed "clean".
#
#   ./scripts/test-check-secrets.sh
#
# Each test builds its own throwaway git repository, so nothing here touches the real one, and the
# "keys" are random or obviously synthetic -- they control nothing on any chain.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
GATE=./scripts/check-secrets.sh
GATE_ABS="$PWD/$GATE"
[ -x "$GATE" ] || { echo "no gate at $GATE" >&2; exit 1; }

pass=0; fail=0; TEMPS=(); NEWREPO=""
cleanup() { local d; for d in "${TEMPS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT
t() { # t <name> <want-exit> <got-exit> <output> [must-contain]
  local name="$1" want="$2" got="$3" out="$4" needle="${5:-}"
  if [ "$want" = "$got" ] && { [ -z "$needle" ] || printf '%s' "$out" | grep -qF "$needle"; }; then
    pass=$((pass+1)); printf '  PASS  %s\n' "$name"
  else
    fail=$((fail+1)); printf '  FAIL  %s\n          exit got=%s want=%s; needle=%s\n          %s\n' \
      "$name" "$got" "$want" "${needle:-<none>}" "$(printf '%s' "$out" | head -3 | tr '\n' ' ')"
  fi
}

# NOT `$(newrepo)`: command substitution runs in a subshell, so the TEMPS append is lost and the repo
# leaks. Call it, then read $NEWREPO.
newrepo() {
  local d; d=$(mktemp -d)
  TEMPS+=("$d")
  git -C "$d" init -q
  git -C "$d" -c user.email=t@t -c user.name=t config commit.gpgsign false
  NEWREPO="$d"
}

FAKE="0x$(openssl rand -hex 32)"                 # random: controls nothing anywhere
SYNTH='0x0000000000000000000000000000000000000000000000000000000000000001'

# ---- T1: a key committed at HEAD but DELETED from the worktree must still be a finding ----
newrepo; R="$NEWREPO"
mkdir -p "$R/scripts" && cp "$GATE" "$R/scripts/check-secrets.sh"
echo "PRIVATE_KEY=$FAKE" > "$R/deploy.sh"
git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -qm one
rm "$R/deploy.sh"                                 # the 2026-11-02 shape: gone from disk, still at HEAD
out=$(cd "$R" && ./scripts/check-secrets.sh 2>&1); rc=$?
t "T1 key at HEAD but absent from disk is detected" 3 "$rc" "$out" "deploy.sh"

# ---- T2: and it must be reported by --head explicitly too (the mode CI will call) ----
out=$(cd "$R" && ./scripts/check-secrets.sh --head 2>&1); rc=$?
t "T2 --head names the deleted path" 3 "$rc" "$out" "deploy.sh"

# ---- T3: an obviously synthetic value (scalar 1) is NOT a finding ----
newrepo; R2="$NEWREPO"; mkdir -p "$R2/scripts" && cp "$GATE" "$R2/scripts/check-secrets.sh"
echo "out=\$(PLAN_DIR=x PRIVATE_KEY=$SYNTH bash signer.sh)" > "$R2/rehearse.sh"
git -C "$R2" add -A && git -C "$R2" -c user.email=t@t -c user.name=t commit -qm one
out=$(cd "$R2" && ./scripts/check-secrets.sh 2>&1); rc=$?
t "T3 synthetic all-zero-leading key does not make the gate red" 0 "$rc" "$out" "clean"

# ---- T4: a key whose variable name the old narrow pattern missed must still fire ----
# The 2026-10-22 gate only matched private|secret|signing|wallet|mnemonic, so `DEPLOY_KEY=0x<64>` --
# the shape a deploy script actually uses -- was invisible even on disk.
echo "DEPLOY_KEY=$FAKE" >> "$R2/rehearse.sh"
out=$(cd "$R2" && ./scripts/check-secrets.sh 2>&1); rc=$?
t "T4 any *_KEY=0x<64> assignment fires, not just PRIVATE_KEY" 3 "$rc" "$out" "DEPLOY_KEY"

# ---- T5: generated trees at HEAD stay pruned (no bytecode false positive) ----
newrepo; R3="$NEWREPO"; mkdir -p "$R3/scripts" "$R3/out" && cp "$GATE" "$R3/scripts/check-secrets.sh"
printf 'const x = "%s";\n' "$FAKE" > "$R3/out/bytecode.json"
git -C "$R3" add -A && git -C "$R3" -c user.email=t@t -c user.name=t commit -qm one
out=$(cd "$R3" && ./scripts/check-secrets.sh 2>&1); rc=$?
t "T5 pruned trees are pruned in HEAD mode as well" 0 "$rc" "$out" "clean"

# ---- T6: a HEAD with nothing scannable left is an error, never a pass ----
newrepo; R4="$NEWREPO"; mkdir -p "$R4/out"
echo readme > "$R4/README.md"
printf 'PRIVATE_KEY=%s\n' "$FAKE" > "$R4/deploy.sh"
git -C "$R4" add -A && git -C "$R4" -c user.email=t@t -c user.name=t commit -qm one
# Now leave only a pruned tree in HEAD, and delete the on-disk files the old gate would have found.
git -C "$R4" rm -q README.md deploy.sh
printf 'const x = 1;\n' > "$R4/out/keep.json"
git -C "$R4" add -A && git -C "$R4" -c user.email=t@t -c user.name=t commit -qm only-pruned
out=$(cd "$R4" && "$GATE_ABS" 2>&1); rc=$?
t "T6 a HEAD with zero scannable paths reports SCANNED NOTHING, not clean" 2 "$rc" "$out" "SCANNED NOTHING"

# ---- T7: the gate's own selftest must still pass ----
out=$("$GATE" --selftest 2>&1); rc=$?
t "T7 existing selftest still passes" 0 "$rc" "$out" "checks passed"

# ---- T8: --head must not report disk paths it never opened ----
# Written after seeing `--head` print "clean — 1313 disk paths + 1313 HEAD paths scanned" on a repo
# where the disk arm is switched off. A count of work that did not happen is the same class of lie as
# the "clean — 0 files" that decision 1 in the gate's header exists to prevent, so the honest line for
# HEAD-only mode is zero disk paths.
newrepo; R5="$NEWREPO"; mkdir -p "$R5/scripts" "$R5/out" && cp "$GATE" "$R5/scripts/check-secrets.sh"
echo "# docs, no secrets" > "$R5/README.md"
echo "const x = 1;" > "$R5/out/generated.json"
git -C "$R5" add -A && git -C "$R5" -c user.email=t@t -c user.name=t commit -qm clean
out=$(cd "$R5" && ./scripts/check-secrets.sh --head 2>&1); rc=$?
t "T8 --head reports 0 disk paths" 0 "$rc" "$out" "0 disk paths"
t "T9 --head reports HEAD's own pruned count" 0 "$rc" "$out" ", 1 generated"

echo; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1

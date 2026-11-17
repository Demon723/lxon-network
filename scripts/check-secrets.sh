#!/usr/bin/env bash
# Quoted-hex secret gate. Written 2026-10-22 after finding a live wallet private key hardcoded as a
# fallback inside hardhat.config.ts's `accounts:` array while `secrun scan --all` returned exit 0 on
# that exact file — its private-key rule matches PEM shape, so `0x` + 64 hex passes straight through
# it. Every earlier claim of "0 secret-shaped files" was produced by that blind gate.
#
#   ./scripts/check-secrets.sh              scan HEAD *and* tracked source on disk (what a push sends)
#   ./scripts/check-secrets.sh --head       HEAD blobs only — use it to prove a deleted path is gone
#   ./scripts/check-secrets.sh --worktree   tracked + untracked-but-not-ignored (HEAD is still scanned)
#   ./scripts/check-secrets.sh <file>…      scan named files
#   ./scripts/check-secrets.sh --selftest   prove the gate detects a key, ignores bytecode and tx
#                                           hashes, masks its output, and fails loudly on nothing
#
# Exit 0 clean, 3 findings, 2 the gate's own error (bad flag, broken pattern, or NOTHING SCANNED).
# Regression suite for the behaviours below: ./scripts/test-check-secrets.sh (7 cases, own temp repos).
#
# Three design decisions, the first two learned the hard way while writing the first version of this
# file, the third from the key it missed:
#
# 1. Scanning zero files is an ERROR, never a pass. The first cut carried a malformed PRUNE
#    expression, grep died with "repetition-operator operand invalid", the file list came back empty,
#    and the script cheerfully printed "clean — 0 files". A gate that lauds an absence of checking
#    into evidence of safety is worse than no gate, because nobody goes looking for the reason.
# 2. The pattern is anchored on `0x` *and* delimited as a value. A bare `0x[0-9a-f]{64}` sweep drowns:
#    tx hashes, keccak constants (0x3d602d80… is Solidity's own selector-prefix constant), storage
#    slots, and above all compiled bytecode, which contains hundreds of arbitrary 64-hex runs. So this
#    matches only "0x<64>", '0x<64>', or …KEY=0x<64>, and skips generated trees outright.
# 3. Read HEAD, not the worktree. On 2026-11-02 the gate printed "clean — 1313 files scanned" while a
#    live key sat at HEAD:deploy-amm-gce.sh. The enumeration came from `git ls-files` and every hit was
#    guarded by `[ -f "$f" ]`, so a path committed but deleted from disk was never opened. A gate that
#    describes the editor's working copy while a push sends the committed tip is answering a different
#    question than the one that matters. HEAD is now scanned always, and the assigned-value arm was
#    widened to any uppercase identifier containing KEY — the original list (private|secret|signing|
#    wallet|mnemonic) let `DEPLOY_KEY=0x<64>` walk straight through.
set -uo pipefail

MODE=tracked; TARGETS=(); SELFTEST=0; HEAD_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --worktree) MODE=worktree; shift ;;
    --head) MODE=head; HEAD_ONLY=1; shift ;;
    --selftest) SELFTEST=1; shift ;;
    -*) echo "check-secrets: unknown flag: $1" >&2; exit 2 ;;
    *) TARGETS+=("$1"); shift ;;
  esac
done

# Generated/vendored trees: a 64-hex value there is expected and meaningless. Valid ERE — the (^|/)
# prefixes matter; a leading bare `*` is exactly what broke the previous attempt.
PRUNE='(^|/)(out|artifacts|cache|broadcast|node_modules|dist|lib|\.next|vendor)/'
# The value must sit on a line that NAMES a key. This is what keeps the gate usable: the same 64-hex
# shape appears as genesis mixHash/parentHash, constructorArguments, operationId/topic hashes, tx
# hashes in debug scripts and 0x1337000000… test balances, and a pattern that flags all of those gets
# switched off inside a week. A real leak is a key identifier next to a key-shaped value.
KEY_NAME='(private[_-]?key|privkey|secret[_-]?key|signing[_-]?key|wallet[_-]?key|mnemonic)'
HEXVAL='0x[0-9a-fA-F]{64}'
COMMENT='(^[^:]+:[0-9]+:[[:space:]]*(//|\*|/\*|<!--|# )|example|placeholder|dummy|xxxxx)'
KEY_DQ='"0x[0-9a-fA-F]{64}"'
KEY_SQ="'0x[0-9a-fA-F]{64}'"
KEY_ASSIGN='[A-Z0-9_]*(PRIVATE_KEY|PRIVKEY|SECRET_KEY|SIGNING_KEY|KEY)[A-Z0-9_]*=+"?0x[0-9a-fA-F]{64}'
# A value that is mostly leading zeros is a test fixture, not a wallet: the scalar is 1, so nobody
# holds funds on it. RehearsePool137.sh passes exactly this to prove its signer refuses PRIVATE_KEY=,
# and a gate that stays red on its own fixtures gets switched off. Counted and printed, never silent.
# The delimiter at the end matters: the fixture sits INSIDE a command line
# (`PRIVATE_KEY=0x00…01 bash signer.sh`), so an end-of-line anchor would miss it. Ten leading zeros is
# 2^-40 of the key space, so the exemption costs essentially nothing in sensitivity.
SYNTH_ASSIGN="=[+\"' ]?0x0{10,}[0-9a-fA-F]{1,54}[^0-9a-fA-F]"

# Pattern sanity. grep exits >1 when the expression itself is invalid, and that must never be
# mistaken for "no secrets found".
printf '%s\n' "\"0x$(printf 'a%.0s' $(seq 1 64))\"" | grep -qE "$KEY_DQ" \
  || { echo "check-secrets: internal error — KEY_DQ rejected by grep" >&2; exit 2; }
printf '%s\n' "PRIVATE_KEY=whatever" | grep -qiE "$KEY_NAME" \
  || { echo "check-secrets: internal error — KEY_NAME rejected by grep" >&2; exit 2; }
printf '%s\n' anything | grep -qE "$PRUNE"; [ $? -gt 1 ] \
  && { echo "check-secrets: internal error — PRUNE rejected by grep" >&2; exit 2; }
printf '%s\n' "PRIVATE_KEY=0x$(printf '0%.0s' $(seq 1 63))1 bash signer.sh" | grep -qE "$SYNTH_ASSIGN" \
  || { echo "check-secrets: internal error — SYNTH_ASSIGN rejected by grep" >&2; exit 2; }
printf '%s\n' "DEPLOY_KEY=0x$(printf 'a%.0s' $(seq 1 64))" | grep -qE "$KEY_ASSIGN" \
  || { echo "check-secrets: internal error — KEY_ASSIGN does not match DEPLOY_KEY" >&2; exit 2; }

# Two stages, because "contains a key identifier AND contains a key-shaped value" is not one ERE and
# an ordered regex would miss `const k = "<hex>" /* privateKey */`. Patterns are validated above, so a
# non-zero status inside the loop means no match rather than a broken expression.
#
# Widened 2026-11-02: the original two stages only fired on private|secret|signing|wallet|mnemonic, so
# `DEPLOY_KEY=0x<64>` -- the shape a deploy script actually uses -- walked straight through it. The
# KEY_ASSIGN arm catches any uppercase identifier containing KEY assigned a 64-hex value.
# A line whose value is a synthetic all-leading-zero fixture is counted, not reported.
scan_line() { # $1 = a "path:line:content" string; echoes it if it is a real finding
  local l="$1"
  printf '%s' "$l" | grep -qiE "$KEY_NAME" || printf '%s' "$l" | grep -qE "$KEY_ASSIGN" || return 1
  printf '%s' "$l" | grep -qiE "$COMMENT" && return 1
  printf '%s' "$l" | grep -qE "$SYNTH_ASSIGN" && { printf '%s' "$l" >> "$SKIPPED"; return 1; }
  printf '%s\n' "$l"
}

scan_file() { # $1 = file; appends findings to $HITS
  local named
  named=$(grep -HniE "$HEXVAL" "$1" 2>/dev/null) || return 0
  while IFS= read -r l; do scan_line "$l" >> "$HITS"; done <<< "$named"
  return 0
}

scan_head() { # every blob at HEAD, including paths the working tree no longer has
  local raw
  raw=$(git grep -nI -E "$HEXVAL" HEAD -- . 2>/dev/null | sed -E 's|^HEAD:||') || return 0
  [ -n "$raw" ] || return 0
  while IFS= read -r l; do scan_line "$l" >> "$HITS"; done <<< "$raw"
  return 0
}

report() {      # masked to a 12-char prefix so the output is safe to paste into chat or a ticket
  awk -F: '{
    file=$1; line=$2; rest=substr($0, length($1)+length($2)+3);
    if (match(rest, /0x[0-9a-fA-F]{64}/)) {
      rest=substr(rest,1,RSTART-1) substr(rest,RSTART,12) "<+52 hidden>" substr(rest,RSTART+RLENGTH);
    }
    printf "  %s:%s  %s\n", file, line, rest
  }' "$HITS" | sort -u
}

if [ "$SELFTEST" = "1" ]; then
  echo "check-secrets --selftest"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  FAKE="0x$(openssl rand -hex 32)"                 # random: controls nothing on any chain
  fail() { echo "  $1 — GATE IS BROKEN" >&2; rm -rf "$TMP"; exit 2; }
  printf '  %-42s' "double-quoted key in source:"
  echo "const accounts = [process.env.PRIVATE_KEY, \"$FAKE\"];" > "$TMP/a.ts"
  grep -qE "$KEY_DQ" "$TMP/a.ts" && echo DETECTED || fail "missed it"
  printf '  %-42s' "single-quoted key in source:"
  echo "const k = '$FAKE';" > "$TMP/b.ts"
  grep -qE "$KEY_SQ" "$TMP/b.ts" && echo DETECTED || fail "missed it"
  printf '  %-42s' "FOUNDER_PRIVATE_KEY=0x<64> env shape:"
  echo "FOUNDER_PRIVATE_KEY=$FAKE" > "$TMP/c.env"
  grep -qE "$KEY_ASSIGN" "$TMP/c.env" && echo DETECTED || fail "missed it"
  printf '  %-42s' "400-char compiled bytecode:"
  echo "  \"object\": \"0x$(printf '60%.0s' $(seq 1 200))\"" > "$TMP/d.json"
  grep -qE "$KEY_DQ" "$TMP/d.json" && fail "false positive on bytecode" || echo "ignored"
  printf '  %-42s' "unquoted 64-hex tx hash in a doc:"
  echo "tx=0x$(printf 'b%.0s' $(seq 1 64))" > "$TMP/e.md"
  grep -qE "$KEY_DQ|$KEY_SQ" "$TMP/e.md" && fail "false positive on a tx hash" || echo "ignored"
  printf '  %-42s' "report masks rather than repeats:"
  HITS=$(mktemp); printf 'x.ts:1:const a = "%s";\n' "$FAKE" > "$HITS"
  OUT=$(report); rm -f "$HITS"
  case "$OUT" in *"<+52 hidden>"*) : ;; *) fail "no masking" ;; esac
  case "$OUT" in *"$FAKE"*) fail "printed the whole key" ;; *) echo "prefix-only, value absent" ;; esac
  printf '  %-42s' "DEPLOY_KEY=0x<64> through the real scan_line:"
  HITS=$(mktemp); SKIPPED=$(mktemp)
  scan_line "d.sh:1:DEPLOY_KEY=$FAKE" >> "$HITS"
  [ -s "$HITS" ] && echo DETECTED || fail "KEY_ASSIGN arm is not wired into scan_line"
  printf '  %-42s' "synthetic 0x000…001 through scan_line:"
  : > "$HITS"; scan_line "r.sh:1:PRIVATE_KEY=0x$(printf '0%.0s' $(seq 1 63))1 bash signer.sh" >> "$HITS"
  [ ! -s "$HITS" ] || fail "reported a test fixture as a private key"
  [ -s "$SKIPPED" ] || fail "synthetic value dropped silently — it must be counted"
  rm -f "$HITS" "$SKIPPED"; echo "ignored, and counted"
  echo "selftest: 8/8 checks passed"
  exit 0
fi

HITS=$(mktemp); SKIPPED=$(mktemp); trap 'rm -f "$HITS" "$SKIPPED"' EXIT
if [ ${#TARGETS[@]} -gt 0 ]; then
  FILES=$(printf '%s\n' "${TARGETS[@]}")
elif [ "$MODE" = "worktree" ]; then
  FILES=$( { git ls-files; git ls-files --others --exclude-standard; } 2>/dev/null | sort -u )
else
  FILES=$(git ls-files 2>/dev/null)
fi

NALL=$(printf '%s\n' "$FILES" | grep -c . || true)
FILES=$(printf '%s\n' "$FILES" | grep -vE "$PRUNE" || true)
NSCAN=$(printf '%s\n' "$FILES" | grep -c . || true)

# The committed tip, counted separately: this is what a push actually sends, and the hole that let a
# live key sit at HEAD while the gate printed "clean" was exactly a path deleted from the worktree.
if [ ${#TARGETS[@]} -eq 0 ]; then
  NHEADALL=$(git ls-tree -r --name-only HEAD 2>/dev/null | grep -c . || true)
  NHEAD=$(git ls-tree -r --name-only HEAD 2>/dev/null | grep -vE "$PRUNE" | grep -c . || true)
else
  NHEADALL=0; NHEAD=0
fi

if [ $((NSCAN + NHEAD)) -eq 0 ]; then
  echo "check-secrets: SCANNED NOTHING ($NALL candidate paths on disk, $NHEADALL at HEAD, none left after pruning) — not reporting clean." >&2
  echo "             Run it from the repository root, or pass explicit file paths." >&2
  exit 2
fi

if [ ${#TARGETS[@]} -eq 0 ]; then
  scan_head
fi
if [ "$HEAD_ONLY" != 1 ]; then
  while IFS= read -r f; do [ -f "$f" ] && scan_file "$f"; done <<< "$FILES"
  PRUNED=$((NALL - NSCAN))
else
  # The disk arm did not run, so it must not be counted. Reporting paths that were never opened is the
  # same class of error as the "clean — 0 files" that decision 1 above exists to prevent.
  NSCAN=0
  PRUNED=$((NHEADALL - NHEAD))
fi

NSKIP=$(sort -u "$SKIPPED" 2>/dev/null | grep -c . || true)

if [ ! -s "$HITS" ]; then
  echo "check-secrets: clean — $NSCAN disk paths + $NHEAD HEAD paths scanned, $PRUNED generated/vendored paths pruned, $NSKIP synthetic test value(s) ignored"
  exit 0
fi

echo "check-secrets: $(report | grep -c .) finding(s) in $NSCAN disk + $NHEAD HEAD paths. Values masked to 12 chars."
report
[ "$NSKIP" = 0 ] || echo "  (plus $NSKIP synthetic all-leading-zero value(s) ignored as fixtures)"
echo
echo "A quoted 64-hex literal in source is a private key until proven otherwise. Deleting the line does"
echo "not un-leak it: check how long it sat in history, and rotate the account it controls."
exit 3

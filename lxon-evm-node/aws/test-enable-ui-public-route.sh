#!/usr/bin/env bash
# Tests for enable-ui.sh's handling of the PUBLIC swap route.
#
# Why these exist: explorer.lxon.in serves /swap/* from /data/swap and /ui/* from /data/ui, two
# independent Caddy static roots, and enable-ui.sh only ever published to /data/ui. On 2026-10-30
# the publish was declared verified on a "routes 200" table that did not include /swap/ at all --
# so the URL in the listing docs kept serving a 2026-10-28 build for a day. These tests pin the two
# behaviours that would have caught it, and each one is written to fail before the change.
#
# Read-only by construction: it never invokes a publish, never writes to the host, and proves the
# byte check can fail by asking for a SHA that is known-stale (the pre-publish backup) rather than
# by corrupting a live file.
#
#   ./test-enable-ui-public-route.sh            # run all
#   ./test-enable-ui-public-route.sh --static   # skip the live --check run (no network/SSH)

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

SCRIPT=enable-ui.sh
CHECK=0
pass=0; fail=0
t() { # t <name> <want: 0=must-succeed> <got-status> <detail>
  local name="$1" want="$2" got="$3" detail="${4:-}"
  if [ "$want" = "$got" ]; then pass=$((pass+1)); printf '  PASS  %s\n' "$name";
  else fail=$((fail+1)); printf '  FAIL  %s\n          %s\n' "$name" "${detail:-got $got, wanted $want}"; fi
}

# The output shape this test pins: --check must print a line carrying the literal phrase
# "page sha" for the public route, with the digest it fetched. Matching on "swap/" alone was
# vacuous -- the existing list already prints /swap/price.json and the old --check exited 0
# unconditionally, so a first draft of T4 passed before any code existed. It is kept here because
# that is the lesson worth recording, not because it still passes.
PAGE_MARK='page sha'

# ---- T1: --check must report a byte-level verdict for the public /swap/ route ----
if grep -qE "check_bytes|UI_EXPECT_SWAP_SHA|${PAGE_MARK}" "$SCRIPT"; then
  t "T1 --check knows about the public /swap/ route" 0 0
else
  t "T1 --check knows about the public /swap/ route" 0 1 \
    "no /swap/ HTML probe and no byte comparison anywhere in $SCRIPT"
fi

# ---- T2: a publish must carry swap.html into /data/swap/index.html ----
# The remote half copies the bundle into /data/ui only. Grep the REMOTE heredoc for a step that
# installs the swap page at the public route's filename.
# Extract the REMOTE heredoc body: it starts at the line declaring `read ... REMOTE <<'REMOTE_EOF'`
# and ends at the lone REMOTE_EOF. (An earlier draft matched /^read -r -d .REMOTE.,/, which is the
# wrong word order -- `read -r -d '' REMOTE` -- so T2 stayed red even after the code landed, and a
# test that cannot pass is as useless as one that cannot fail.)
remote_body=$(sed -n '/REMOTE <</,/^REMOTE_EOF$/p' "$SCRIPT")
if printf '%s' "$remote_body" | grep -qE '/data/swap/index\.html'; then
  t "T2 publish installs swap.html at the public route" 0 0
else
  t "T2 publish installs swap.html at the public route" 0 1 \
    "the remote half writes /data/ui only -- /data/swap/index.html is never touched"
fi

# ---- T3: --check must be able to FAIL (non-zero exit) on a stale public page ----
# Fault injection without touching production: ask the check to expect the pre-2026-10-31 SHA,
# which is a real, different artifact (26,764 bytes, no bridge panel). A check that cannot fail is
# worthless, so this is the test that separates a byte-check from a status-code print.
STALE_SHA="eab705fbb606f5f6000000000000000000000000000000000000000000000000"
if [ "${1:-}" = "--static" ]; then
  echo "  SKIP  T3/T4 live run requested --static"
else
  out=$(UI_EXPECT_SWAP_SHA="$STALE_SHA" ./"$SCRIPT" --check 2>&1); rc=$?
  if printf '%s' "$out" | grep -q "${PAGE_MARK}" && [ "$rc" -ne 0 ]; then
    t "T3 --check reports /swap/ and exits non-zero when it is stale" 0 0
  else
    t "T3 --check reports /swap/ and exits non-zero when it is stale" 0 1 \
      "rc=$rc; /swap/ lines: $(printf '%s' "$out" | grep -c 'swap/')"
  fi

  # ---- T4: and PASS (exit 0) against the artifact that is genuinely live ----
  live_sha=$(curl -sL -m 30 https://explorer.lxon.in/swap/ | shasum -a 256 | awk '{print $1}')
  out=$(UI_EXPECT_SWAP_SHA="$live_sha" ./"$SCRIPT" --check 2>&1); rc=$?
  if printf '%s' "$out" | grep -q "${PAGE_MARK}" && [ "$rc" -eq 0 ]; then
    t "T4 --check exits 0 when the public route matches the expected artifact" 0 0
  else
    t "T4 --check exits 0 when the public route matches the expected artifact" 0 1 \
      "rc=$rc against live sha ${live_sha:0:16}... -- a check that fails on a good publish is as useless as one that never fails"
  fi
fi

# ---- T5/T6/T7: the token list, same defect class ----
# --check already runs the schema validator over the PUBLISHED list and printed
# "RESULT: FAIL (5 failed, 2 not run)" -- while exiting 0. A check that reports a failure and then
# reports success is not a check. These three tests pin: a digest verdict is printed, divergence
# from the repo file is a non-zero exit, and a good state is zero (guarded on the verdict line, so
# it cannot pass vacuously the way the first T4 did).
LIST_MARK='list sha'
repo_sha=$(shasum -a 256 ui/lxon-token-list.json | awk '{print $1}')

if grep -qE "${LIST_MARK}|UI_EXPECT_LIST_SHA" "$SCRIPT"; then
  t "T5 --check compares the published token list by digest" 0 0
else
  t "T5 --check compares the published token list by digest" 0 1 \
    "the published list failed its own schema gate and --check still exited 0"
fi

if [ "${1:-}" != "--static" ]; then
  # ---- T6: and it must be able to FAIL on the list (fault injection, like T3) ----
  # The first draft of this test asserted "no UI_EXPECT_LIST_SHA => non-zero exit", i.e. it asserted
  # the then-current BUG (published v2.0.0 != repo v3.0.0). It passed while the site was broken and
  # went red the moment the corrected list was published -- a test that encodes live state rots
  # silently. The durable property is "a divergent list is a non-zero exit", and it is proved with a
  # real, different artifact rather than by corrupting production: the sha of the v2.0.0 list that
  # was live until 2026-10-31 (backed up on the node as caddy/lxon-token-list.json.bak-20261031T113342Z).
  STALE_LIST_SHA="a3290328055e3854deeebe925cf3f18e140d7b477aeae0c3c7402ae71161db69"
  out=$(UI_EXPECT_LIST_SHA="$STALE_LIST_SHA" ./"$SCRIPT" --check 2>&1); rc=$?
  if printf '%s' "$out" | grep -q "${LIST_MARK}" && [ "$rc" -ne 0 ]; then
    t "T6 --check exits non-zero when the published list is not the expected artifact" 0 0
  else
    t "T6 --check exits non-zero when the published list is not the expected artifact" 0 1 \
      "rc=$rc; '${LIST_MARK}' lines: $(printf '%s' "$out" | grep -c "${LIST_MARK}") -- expecting the stale v2.0.0 digest to be refused"
  fi

  out=$(UI_EXPECT_LIST_SHA="$repo_sha" ./"$SCRIPT" --check 2>&1); rc=$?
  if printf '%s' "$out" | grep -q "${LIST_MARK}" && [ "$rc" -eq 0 ]; then
    t "T7 --check exits 0 when the published list matches the validated repo file" 0 0
  else
    t "T7 --check exits 0 when the published list matches the validated repo file" 0 1 \
      "rc=$rc expecting ${repo_sha:0:16}... -- green only once the corrected list is actually published"
  fi
else
  echo "  SKIP  T6/T7 live run requested --static"
fi

# ---- T8/T9: the list's CORS header must be a verdict, not a print ----
# The list has been valid and byte-correct since the 2026-10-31 publish, and --check still could not
# tell you that a browser cannot read it: it printed `access-control-allow-origin` with an empty
# value and exited 0. tokenlists.org and the wallet UIs that import by URL fetch the list from the
# visitor's browser, so a missing header means the published list does nothing for them while every
# server-side probe says 200.
#
# Fault injection, because a header cannot be removed from production to prove the check notices:
# UI_CORS_URL points the assertion at any served URL. /landing-light.html is a real file on the same
# origin that carries no ACAO, so asking the gate about it must be a refusal. Without that override
# the gate runs against the list itself.
CORS_MARK='cors verdict'
NO_ACAO_URL="https://www.lxon.in/landing-light.html"

if grep -qE "${CORS_MARK}|UI_CORS_URL" "$SCRIPT"; then
  t "T8 --check renders a verdict on the list's CORS header" 0 0
else
  t "T8 --check renders a verdict on the list's CORS header" 0 1 \
    "--check prints the header value and ignores it"
fi

if [ "${1:-}" != "--static" ]; then
  out=$(UI_CORS_URL="$NO_ACAO_URL" ./"$SCRIPT" --check 2>&1); rc=$?
  if printf '%s' "$out" | grep -q "${CORS_MARK}" && [ "$rc" -ne 0 ]; then
    t "T9 --check exits non-zero when the URL under test sends no ACAO header" 0 0
  else
    t "T9 --check exits non-zero when the URL under test sends no ACAO header" 0 1 \
      "rc=$rc; '${CORS_MARK}' lines: $(printf '%s' "$out" | grep -c "${CORS_MARK}") -- $NO_ACAO_URL measurably sends no Access-Control-Allow-Origin"
  fi
else
  echo "  SKIP  T9 live run requested --static"
fi

# ---- T10: the gate has to cover BOTH URLs the list is published at ----
# One origin being readable is not enough: the list is served at explorer.lxon.in/ui/… and at
# www.lxon.in/…, a submission can name either, and until 2026-10-31 the explorer route carried no
# ACAO at all while the check that was supposed to notice only ever looked at www. So the default
# --check must render a verdict per published URL and be zero only when all of them pass.
if [ "${1:-}" != "--static" ]; then
  out=$(./"$SCRIPT" --check 2>&1); rc=$?
  n=$(printf '%s' "$out" | grep -c "${CORS_MARK}")
  if [ "$n" -ge 2 ] && [ "$rc" -eq 0 ]; then
    t "T10 --check gates the ACAO on every published list URL" 0 0
  else
    t "T10 --check gates the ACAO on every published list URL" 0 1 \
      "rc=$rc with $n '${CORS_MARK}' line(s), want >= 2 and rc=0 (explorer /ui/… and www /…)"
  fi
else
  echo "  SKIP  T10 live run requested --static"
fi

# ---- T11: the price feed is machine-read too, so it needs the same verdict ----
# /swap/price.json is the other endpoint a front-end on another origin fetches from a browser, and it
# had the identical gap: 200, correct bytes, no Access-Control-Allow-Origin. --check's CORS gate only
# ever named the token list, which is how "the CORS check passed" coexisted with an unreadable feed.
# Note the scope: the gate covers the JSON endpoints, NOT /swap/ or /ui/ HTML -- those are deliberately
# left without a wildcard, so `UI_CORS_URL=https://explorer.lxon.in/swap/` must still refuse.
PRICE_MARK='swap/price.json'

# The guard is the LIVE output, not a grep: 'swap/price.json' already appears in enable-ui.sh twice
# (the probe list and the recreate wait loop), so a grep-based assertion would pass before the gate
# existed -- the exact vacuity that caught the first T4. What has to be true is that a line carrying
# 'cors verdict' names the feed.
if [ "${1:-}" != "--static" ]; then
  out=$(./"$SCRIPT" --check 2>&1); rc=$?
  if printf '%s' "$out" | grep "${CORS_MARK}" | grep -q "${PRICE_MARK}"; then
    t "T11 --check renders a CORS verdict for the price feed" 0 0
  else
    t "T11 --check renders a CORS verdict for the price feed" 0 1 \
      "no 'cors verdict' line names ${PRICE_MARK}; --check rc=$rc (the feed answers 200 with no ACAO and --check does not know it exists)"
  fi
else
  echo "  SKIP  T11 live run requested --static"
fi

echo; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1

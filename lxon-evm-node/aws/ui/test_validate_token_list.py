#!/usr/bin/env python3
# WITHDRAWN 2026-11-04 -- DO NOT SUBMIT, DO NOT PASTE. Chain 724 restarted from an empty volume on
# 2026-11-03, so every on-chain fact in this file is now false: the token contract 0x99801A78...67Dc
# returns 0 bytes of code on https://rpc.lxon.in (measured today; the positive control is that the v4.1
# bridge on Polygon 137 still reads 19,105 bytes to the same reader), so do total supply, the mint-role
# holder, the explorer's verified-contract count and the pause flag. A listing filed with these numbers
# would be a false statement under someone else's name, not an outdated draft. What a corrected
# submission needs is the NEW addresses from the redeploy, which are unknown until those deploys mine:
# docs/runbooks/repoint-137-to-rebuilt-724-plan.md Phases 2-3. Proof of the current dead set and the
# rule that keeps finding these: lxon-evm-node/aws-freetier/check-dead-724-addr.py
# --- end of withdrawal notice; everything below is kept unedited as history ------------------------
"""Tests for the extensions cross-checks in validate_token_list.py.

Run:  python3 test_validate_token_list.py            (offline, fast)
      LXON_TEST_LIVE=1 python3 test_validate_token_list.py    (adds the on-chain cases)

Every case starts from the REAL published list, which is known-good, and mutates exactly one thing.
A test that passes against an unmutated list proves nothing, so each case also asserts the specific
label that must fail -- not merely "something failed".
"""
import copy
import datetime
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import validate_token_list as V  # noqa: E402

REAL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "lxon-token-list.json")
BASE = V.json.load(open(REAL))

# Which entry carries which extension, so a fixture change breaks loudly rather than silently.
LXON724 = "0x99801A78639975D448EEb2f8a807738DC8Df67Dc"
WLXON724 = "0xC0CF6B0E6C5a0705F319BA5c629a6Bc7E82FEf00"
WLXON137 = "0x7A3c0C34f157EfDD3E4913c5224C15E645469093"
DUP137 = "0xD69fB341F35cadE285331797D7d35c5613D7Dfbe"


def entry(doc, chain, addr):
    for t in doc["tokens"]:
        if t["chainId"] == chain and t["address"].lower() == addr.lower():
            return t
    raise AssertionError(f"fixture lost {chain}/{addr[:10]}")


def failures(doc):
    """Return the FAIL labels validate() produced for this document, offline."""
    V.results[:] = []
    V.validate(doc, prev_path=None, live=False, net=False)
    return [label for status, label, _ in V.results if status == "FAIL"]


def passed_labels(doc):
    V.results[:] = []
    V.validate(doc, prev_path=None, live=False, net=False)
    return [label for status, label, _ in V.results if status == "PASS"]


def live_results(doc):
    V.results[:] = []
    V.validate(doc, prev_path=None, live=True, net=True)
    return V.results


# ── the baseline: the published list must be clean, or every test below is meaningless ─────────
def test_published_list_has_no_failures():
    fails = failures(copy.deepcopy(BASE))
    assert not fails, f"the real list itself fails: {fails}"


# ── A1: a reference must point at a token this list actually contains ─────────────────────────
def test_underlying_must_reference_a_listed_token():
    doc = copy.deepcopy(BASE)
    e = entry(doc, 724, WLXON724)
    e["extensions"]["underlying"] = {"chainId": 724, "address": "0x1111111111111111111111111111111111111111"}
    fails = failures(doc)
    hits = [f for f in fails if "underlying" in f and "listed" in f]
    assert hits, f"expected a refusal naming the unlisted underlying; got {fails}"


def test_reference_must_name_the_chain_that_entry_is_on():
    doc = copy.deepcopy(BASE)
    e = entry(doc, 724, WLXON724)
    e["extensions"]["underlying"] = {"chainId": 137, "address": LXON724}   # right token, wrong chain
    fails = failures(doc)
    hits = [f for f in fails if "underlying" in f and "chainId" in f]
    assert hits, f"expected a refusal naming the chain mismatch; got {fails}"


# ── A2: every address inside extensions must be EIP-55 checksummed ────────────────────────────
def test_extension_address_must_be_checksummed():
    doc = copy.deepcopy(BASE)
    e = entry(doc, 137, WLXON137)
    e["extensions"]["duplicateNameOnSameChain"]["address"] = DUP137.lower()
    fails = failures(doc)
    hits = [f for f in fails if "duplicateNameOnSameChain" in f and "checksum" in f]
    assert hits, f"expected a checksum refusal; got {fails}"


# ── A3: the duplicate disclosure is only meaningful if it mirrors THIS entry's own metadata ────
def test_duplicate_disclosure_must_match_the_entries_own_name():
    doc = copy.deepcopy(BASE)
    e = entry(doc, 137, WLXON137)
    e["extensions"]["duplicateNameOnSameChain"]["name"] = "LXON Secure"   # then it is not a duplicate
    fails = failures(doc)
    hits = [f for f in fails if "duplicateNameOnSameChain" in f and "name" in f]
    assert hits, f"expected a refusal that the disclosed name is not this entry's name; got {fails}"


def test_duplicate_disclosure_must_not_point_at_itself():
    doc = copy.deepcopy(BASE)
    e = entry(doc, 137, WLXON137)
    e["extensions"]["duplicateNameOnSameChain"]["address"] = WLXON137      # self-reference
    fails = failures(doc)
    hits = [f for f in fails if "duplicateNameOnSameChain" in f and "itself" in f]
    assert hits, f"expected a refusal of a self-reference; got {fails}"


# ── A4: the date is a claim with a shelf life, not a permanent fact ───────────────────────────
def test_metadata_date_must_be_a_real_date():
    doc = copy.deepcopy(BASE)
    entry(doc, 724, WLXON724)["extensions"]["metadataVerifiedFromChain"] = "sometime in 2026"
    fails = failures(doc)
    hits = [f for f in fails if "metadataVerifiedFromChain" in f and "date" in f]
    assert hits, f"expected a refusal of a non-date; got {fails}"


def test_metadata_date_must_not_be_in_the_future():
    doc = copy.deepcopy(BASE)
    future = (datetime.date.today() + datetime.timedelta(days=30)).isoformat()
    entry(doc, 724, WLXON724)["extensions"]["metadataVerifiedFromChain"] = future
    fails = failures(doc)
    hits = [f for f in fails if "metadataVerifiedFromChain" in f and "future" in f]
    assert hits, f"expected a refusal of a future date; got {fails}"


# ── A5: a wrapper or bridge entry may not be listed with no relationship declared at all ──────
def test_wrapped_entry_must_declare_its_relationship():
    doc = copy.deepcopy(BASE)
    del entry(doc, 724, WLXON724)["extensions"]
    fails = failures(doc)
    hits = [f for f in fails if "extensions" in f and "LXON Wrapped" in f]
    assert hits, f"expected a refusal of a wrapper with no extensions; got {fails}"


def test_gas_wrapper_is_exempt_because_it_wraps_the_native_asset():
    """WETH on 724 wraps chain 724's native coin, which has no address to reference."""
    doc = copy.deepcopy(BASE)
    e = entry(doc, 724, "0xcB742c31f0815648E13fF24D8131B89075FF32e2")
    assert "extensions" not in e, "fixture changed: WETH now has extensions"
    assert not failures(doc), "the exempt entry must not cause a failure"


# ── B: live mode must actually read the disclosed duplicate from the chain ────────────────────
def test_live_mode_checks_the_disclosed_duplicate_on_chain():
    res = live_results(copy.deepcopy(BASE))
    labels = [label for _s, label, _d in res]
    hits = [l for l in labels if "duplicateNameOnSameChain" in l and "on chain" in l]
    assert hits, f"no live check for the disclosed duplicate among {len(labels)} labels"
    bad = [f"{s} {l} {d}" for s, l, d in res if s == "FAIL" and "duplicateNameOnSameChain" in l]
    assert not bad, f"the live duplicate check failed: {bad}"


def test_live_mode_refuses_a_duplicate_that_no_longer_matches():
    """The whole point: if that contract stops answering to these strings, the disclosure is a lie.

    Asserted on the LIVE label specifically ("verified on chain"), because the offline rule rejects the
    same mutation too -- a test that only checks "something failed" would pass with the chain read
    removed entirely.
    """
    doc = copy.deepcopy(BASE)
    entry(doc, 137, WLXON137)["extensions"]["duplicateNameOnSameChain"]["symbol"] = "wLXON2"
    res = live_results(doc)
    live_fails = [f"{l} -- {d}" for s, l, d in res
                  if s == "FAIL" and "verified on chain" in l and "symbol" in l]
    assert live_fails, (
        "the chain read did not reject a disclosed symbol that differs from the contract's; "
        f"FAILs seen: {[l for s, l, _ in res if s == 'FAIL']}")
    assert any("wLXON" in line for line in live_fails), f"the failure should quote the contract's real symbol: {live_fails}"


def main():
    live = os.environ.get("LXON_TEST_LIVE") == "1"
    tests = [g for _n, g in sorted(globals().items()) if _n.startswith("test_") and callable(g)]
    if not live:
        tests = [t for t in tests if "live_mode" not in t.__name__]
    failed = 0
    for t in tests:
        try:
            t()
            print(f"  ok    {t.__name__}")
        except AssertionError as e:
            failed += 1
            print(f"  FAIL  {t.__name__}\n        {e}")
    print(f"\n{len(tests) - failed}/{len(tests)} passed"
          + ("" if live else "  (2 live cases skipped; set LXON_TEST_LIVE=1 to run them)"))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

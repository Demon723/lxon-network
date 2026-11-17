#!/usr/bin/env python3
"""
Vote a QBFT validator in or out, the way measurement says it must be done.

Why this script exists instead of one curl:

  * A vote applies only once a QUORUM of validators holds it. Casting it on one node is a no-op
    (measured on chain 725: one validator's vote never applied through six epoch boundaries; the
    same vote held by three of four applied two blocks later). So this casts on every live
    validator and refuses if that set is smaller than the quorum it must reach.
  * A vote is NOT epoch-gated, but the roster change lands on a chain that immediately needs the
    new validator's signatures. Voting in a node that is not already peered and synced halted an
    n=1 chain, and that halt survived withdrawing the vote and restarting the sealer (measured on
    two throwaway probe chains). So the candidate readiness gate below runs BEFORE any vote and
    aborts rather than proceeding.
  * Quorum is ceil(2n/3) of the CURRENT roster, and it changes mid-operation: adding to a roster of 4
    needs 3 votes, but removing from a roster of 5 needs 4, and at roster 3 a removal applied on TWO
    votes while one vote of three did nothing. `--action out` therefore usually includes the candidate's
    own port, because by then it is a validator whose vote counts.

Safety: the chainId you name must match what the RPC actually reports, and anything that is not the local
725/726 testbed additionally requires --i-own-this-chain --snapshot-confirmed. Production votes go over an
SSH tunnel with the QBFT namespace temporarily enabled, and only after
docs/runbooks/lxon-724-validator-expansion.md step 1 (volume snapshot) is done.
"""
import argparse
import json
import sys
import time
import urllib.request


def call(url, method, params=None):
    req = urllib.request.Request(
        url,
        data=json.dumps({"jsonrpc": "2.0", "id": 1, "method": method,
                         "params": params or []}).encode(),
        headers={"content-type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=8) as resp:
        body = json.loads(resp.read())
    if "error" in body:
        raise RuntimeError(f"{method} -> {body['error']}")
    return body.get("result")


def num(url):
    return int(call(url, "eth_blockNumber"), 16)


def chain_id(url):
    return int(call(url, "eth_chainId"), 16)


def peers(url):
    return len(call(url, "admin_peers"))


def roster(url):
    return [a.lower() for a in call(url, "qbft_getValidatorsByBlockNumber", ["latest"])]


def vote(url, address, add):
    return call(url, "qbft_proposeValidatorVote", [address, add])


def quorum(n):
    # ceil(2n/3), measured on a scratch chain at production's exact qbft block: at roster 3 a
    # removal applied with votes from two validators, and one validator alone (two of three down)
    # sealed nothing for 75 s. floor(2n/3)+1 is the same for n=1,2,4,5 and one too strict at n=3,
    # where it would refuse a vote that Besu actually accepts.
    return -(-2 * n // 3)


LOCAL_TESTBEDS = {725, 726}


def live(urls):
    """(url, height) for every RPC that answers."""
    out = []
    for u in urls:
        try:
            out.append((u, num(u)))
        except Exception:
            pass
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--validator", required=True,
                    help="http://host:port of an EXISTING validator (reads the roster and head)")
    ap.add_argument("--candidate", required=True,
                    help="http://host:port of the validator being added or removed")
    ap.add_argument("--address", required=True, help="candidate validator address to vote in/out")
    ap.add_argument("--ports", nargs="+", required=True,
                    help="every live validator RPC to cast the vote on, as port numbers or full URLs; "
                         "the candidate's port belongs in here too when it is already a validator")
    ap.add_argument("--action", choices=["in", "out"], required=True)
    ap.add_argument("--allow-chainid", type=int, required=True,
                    help="chainId this run is allowed to write to (e.g. 725)")
    ap.add_argument("--ready-budget", type=int, default=240,
                    help="seconds to wait for the candidate to sync and peer")
    ap.add_argument("--check-only", action="store_true",
                    help="run the candidate readiness gate and report it, cast nothing")
    ap.add_argument("--i-own-this-chain", action="store_true",
                    help="required, with --snapshot-confirmed, to target a chain that is not the "
                         "local 725/726 testbed")
    ap.add_argument("--snapshot-confirmed", action="store_true",
                    help="asserts runbook step 1 (volume snapshot + recorded height) is already done")
    args = ap.parse_args()

    # Accept either bare ports (8645) or full URLs (http://127.0.0.1:8645). Bare ports are the
    # testbed shape; a URL is what an SSH-tunnelled production vote needs.
    args.ports = [p if p.startswith("http") else f"http://127.0.0.1:{p}" for p in args.ports]

    if args.allow_chainid not in LOCAL_TESTBEDS and not (
            args.i_own_this_chain and args.snapshot_confirmed):
        print(f"REFUSING: chainId {args.allow_chainid} is not the local testbed "
              f"{sorted(LOCAL_TESTBEDS)} and the two production flags were not both passed. "
              f"Consensus votes on a real chain are an owner action, taken after the volume "
              f"snapshot in runbook step 1, over an SSH tunnel. Pass --i-own-this-chain "
              f"--snapshot-confirmed when that is genuinely true.")
        return 1
    observed = chain_id(args.validator)
    if observed != args.allow_chainid:
        print(f"ABORT: {args.validator} reports chainId {observed}, expected {args.allow_chainid}")
        return 1

    address = args.address.lower()
    before = roster(args.validator)
    n_before = len(before)
    already = address in before
    print(f"chain {observed} | roster {n_before} | {address} "
          f"{'IS' if already else 'is NOT'} a validator")
    if args.action == "in" and already:
        print("nothing to do: candidate already in the roster")
        return 0
    if args.action == "out" and not already:
        print("nothing to do: candidate not in the roster")
        return 0

    # --- candidate readiness gate (the step the halted probes skipped) ---
    deadline = time.time() + args.ready_budget
    gate = {"answers": False, "peered": False, "synced": False}
    while time.time() < deadline:
        try:
            ch = num(args.candidate)
            gate["answers"] = True
            gate["peered"] = peers(args.candidate) >= 1
            head = max((h for _, h in live(args.ports)), default=-1)
            gate["synced"] = ch >= head - 1
            if all(gate.values()):
                break
        except Exception as exc:
            print(f"  candidate not answering yet: {exc}")
        print(f"  gate {gate} — waiting")
        time.sleep(10)
    if not all(gate.values()):
        print(f"NOT READY: candidate gate {gate}. Refusing to vote; an out-of-order vote is the "
              f"halt this runbook exists to prevent.")
        return 2
    head = max((h for _, h in live(args.ports)), default=-1)
    print(f"candidate ready: height {num(args.candidate)} at head {head}, peers "
          f"{peers(args.candidate)}")
    if args.check_only:
        print("CHECK ONLY: gate passed, no vote cast")
        return 0

    # --- cast the vote on a quorum ---
    need = quorum(n_before)
    cast = []
    for port in args.ports:
        try:
            ok = vote(port, address, args.action == "in")
            cast.append((port, ok))
        except Exception as exc:
            cast.append((port, f"unreachable: {exc}"))
    trues = sum(1 for _, v in cast if v is True)
    for port, v in cast:
        print(f"  vote on {port}: {v}")
    if trues < need:
        print(f"FAIL: only {trues} validators hold the vote, quorum of a {n_before}-validator "
              f"roster is {need}. It will not apply.")
        return 1

    # --- wait for the transition, and prove sealing continued through it ---
    target = n_before + 1 if args.action == "in" else n_before - 1
    h0 = num(args.validator)
    t0 = time.time()
    applied = None
    samples = []
    while time.time() - t0 < 300:
        time.sleep(5)
        try:
            now = roster(args.validator)
            samples.append((num(args.validator), len(now)))
        except Exception:
            continue
        if len(now) == target:
            applied = (num(args.validator), time.time() - t0)
            break
    if applied is None:
        print(f"FAIL: roster never reached {target}; samples {samples}")
        return 1
    h1, dt = applied
    print(f"APPLIED: roster {n_before} -> {target} after {dt:.0f} s "
          f"({h1 - h0} blocks, chain {h0} -> {h1})")

    # A roster that moved is not the whole success condition: sealing has to keep moving at the
    # new quorum. Measure a fresh window rather than reusing the polling loop's timestamps.
    time.sleep(5)
    wa, a0 = time.time(), num(args.validator)
    time.sleep(30)
    wb, b0 = time.time(), num(args.validator)
    blocks = b0 - a0
    secs = wb - wa
    if blocks <= 0:
        print(f"FAIL: roster is {target} but no block sealed in {secs:.0f} s "
              f"(height frozen at {b0}) — this is the halt shape")
        return 1
    running = len(live(args.ports) + ([ (args.candidate, 0) ] if gate["answers"] else []))
    print(f"sealing after the change: {a0} -> {b0} ({blocks} blocks in {secs:.0f} s, "
          f"~{secs / blocks:.1f} s/block) with {target} validators in the roster")
    print("CONSENSUS VOTE OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())

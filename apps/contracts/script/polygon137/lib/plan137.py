#!/usr/bin/env python3
"""Planning primitives for the Polygon-137 wLXONSecure/migration ceremony.

Stdin, argv and files only: no network, no keys, no chain. PlanWlxon137.sh owns the RPC calls,
because a plan is only worth the facts it was measured against, and those facts (nonce, base fee,
whether the predicted address is still empty) come from a node. What lives here is the part that
must be *reproducible without a node*: reading bytecode out of a compiled artifact, encoding the
constructor arguments, holding the transaction lines, and serialising the plan that
SignWlxon137Plan.sh and BroadcastWlxon137Signed.sh both check their work against.

The transaction shape -- label/nonce/to/value/data/gas/maxFeePerGas/maxPriorityFeePerGas/chainId/
from/note -- is deliberately the same one `lib/offline_plan1559.py` decodes and compares. That file
is the authority; this one only writes what it can read.

`gas_source` and `note` exist because a launch record nobody can re-derive is a rumour: which calls
were priced by the node and which by a measured cap has to survive in the plan itself.
"""
import json
import os
import sys

# lib/ -> polygon137/ -> script/ -> apps/contracts. Three levels, not two: this file sits inside a lib/
# directory, so an app-root computed from its parent's parent lands in script/ and the artifact lookup
# then fails with "no such file" on a machine where the artifacts are plainly present.
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
ARTIFACTS = os.path.join(ROOT, "artifacts")

# Gas caps for calls aimed at an address that has no code yet at planning time. eth_estimateGas
# against an empty account answers ~21000 whatever the payload is, so signing an estimate here would
# under-price the step that must not fail. These are the gas the steps actually used when the whole
# batch was mined on a chain-137 node and read back by receipt hash (RehearseWlxon137.sh, 2026-10-27:
# setOldToken 47,486, setNewToken 47,548, fundReserve 53,896, startMigration 96,127 gasUsed). Each cap
# is that measurement with headroom, so an out-of-gas on a Polygon fee spike costs the unused gas, never
# the ceremony. startMigration's 96,127 came in above the 80,000 first written here -- the chain's
# number corrected the guess, which is the only reason this table is worth keeping. Override
# deliberately, not by silence: CAP_<LABEL>=... in the plan's env replaces the value, and only upward.
CAPS = {
    "setOldToken": 60000,
    "setNewToken": 60000,
    "fundReserve": 80000,
    # startMigration re-measured 2026-10-27 against the REPOINTED destination (newWLXON = the v4.1 bridge
    # token 0x7A3c0C34, not wLXONSecure): 96,139 gasUsed on a chain-137 fork, against the 96,127 the original
    # pairing spent. Two different destination tokens, the same number to five significant figures -- which is
    # the reason the cap stayed at 120,000 instead of being re-guessed.
    "startMigration": 120000,
    # The two timelock legs of an admin ceremony (script/polygon137/PlanAttestor137.sh). Both legs are
    # normally priced by eth_estimateGas, which succeeds here because the timelock is live code; these caps
    # exist for the case where it is refused. Measured twice, and the two measurements disagreed, which is
    # the reason the cap tracks the bigger one: on a chain-137 fork (block 96,230,9xx) schedule used
    # 55,030 and execute 69,259; on MAINNET the real schedule tx
    # 0x60d8f9d6771ff974652449a9db479517b167bb382d390ff7d8a18ae9ad2f0591 (block 96,231,298) used 65,110.
    # The fork was the cheaper of the two -- a forked trie can answer warmer than a live one -- so a cap
    # taken from the fork alone would have been 10,000 gas under what the chain actually spends.
    "schedule": 70000,
    "execute": 90000,
}


def die(msg):
    sys.stderr.write("FATAL: %s\n" % msg)
    sys.exit(1)


def artifact_path(name):
    """artifacts/**/<File>.sol/<File>.json, matched on the .sol directory hardhat writes.

    Walking from `artifacts/contracts` alone would not find OZ's `TimelockController`, which lives under
    `artifacts/@openzeppelin/...` and is now part of the deploy batch. Matching the `<Name>.sol`
    directory rather than any file with the right basename is what keeps this a real build. Two matches
    is a stop, not a coin flip: silently taking one is how a ceremony plans against bytecode it no
    longer compiles.
    """
    hits = []
    for dirpath, dirnames, filenames in os.walk(ARTIFACTS):
        dirnames[:] = [d for d in dirnames if d not in ("build-info", "cache")]
        if os.path.basename(dirpath) == name + ".sol" and name + ".json" in filenames:
            hits.append(os.path.join(dirpath, name + ".json"))
    if not hits:
        die("no artifact directory named %s.sol under %s. Run `npx hardhat compile` first -- "
            "a plan built on a guessed bytecode hash is a signed transaction that buys nothing."
            % (name, ARTIFACTS))
    if len(hits) > 1:
        die("%d artifacts named %s.sol: %s. Which one the ceremony deploys must not be a directory-walk "
            "accident; delete the stale build or rename one contract." % (len(hits), name, hits))
    return hits[0]


def load(name):
    p = artifact_path(name)
    with open(p) as fh:
        return p, json.load(fh)


def ctor_types(abi_json):
    ctors = [e for e in abi_json if e.get("type") == "constructor"]
    if not ctors:
        return ""
    if len(ctors) > 1:
        die("artifact declares %d constructors; the encoder cannot pick one" % len(ctors))
    return ",".join(i["type"] for i in ctors[0]["inputs"])


def cmd_bytecode(name):
    p, a = load(name)
    code = (a.get("bytecode") or "").replace("0x", "")
    if not code:
        die("%s has empty bytecode in %s -- it did not compile" % (name, p))
    if "__" in code:
        die("%s has an unlinked library placeholder in %s. Signing it deploys a contract whose "
            "library calls revert; link the library first." % (name, p))
    sys.stderr.write("  artifact: %s\n" % p)
    print("0x" + code)
    return 0


def cmd_ctorsig(name):
    _, a = load(name)
    print(ctor_types(a["abi"]))
    return 0


def cmd_calltypes(name, sig):
    """Print the input types of a function by its selector text, or die if the artifact lacks it.

    This is what keeps the plan honest about a signature the operator typed: `setOldToken(address)`
    against the migration artifact either exists there or the planner stops. Encoding against a
    signature the contract does not have produces calldata that falls into the fallback and spends
    the whole gas limit saying nothing.
    """
    _, a = load(name)
    want = sig.replace(" ", "")
    for e in a["abi"]:
        if e.get("type") != "function":
            continue
        text = "%s(%s)" % (e["name"], ",".join(i["type"] for i in e.get("inputs", [])))
        if text == want:
            print(",".join(i["type"] for i in e["inputs"]))
            return 0
    die("%s is not a function of %s. Refusing to encode calldata for a signature the contract "
        "does not expose." % (want, name))


def tx_file():
    d = os.environ.get("PLAN_DIR") or die("PLAN_DIR is not set")
    return os.path.join(d, "txs.jsonl")


def cmd_add(argv):
    """add <label> <nonce> <to> <value> <data> <gas> <maxFee> <priority> <chainId> <from> <gas_source> <note>

    One jsonl line per planned transaction, in the field names offline_plan1559.py decodes.
    """
    # argv[0] is this file and argv[1] is the word "add", so the operands start at argv[2]. Reading
    # them from argv[1] shifted every column one place left and the plan was refused for having
    # 1 character of calldata -- which is the value column. An off-by-one that dies loudly in a
    # rehearsal is fine; one that quietly names the wrong column at a launch is a signed wrong tx.
    (label, nonce, to, value, data, gas, maxfee, priority, chain, frm, gas_source, note) = argv[2:14]
    if not data.startswith("0x") or len(data) % 2:        die("%s: calldata is not even-length hex (got %d chars)" % (label, len(data)))
    if to not in ("0x",) and not (to.startswith("0x") and len(to) == 42):
        die("%s: destination %s is neither a CREATE marker nor a 20-byte address" % (label, to))
    line = {"label": label, "nonce": int(nonce), "to": to, "value": int(value), "data": data,
            "gas": int(gas), "maxFeePerGas": int(maxfee), "maxPriorityFeePerGas": int(priority),
            "chainId": int(chain), "from": frm, "gasSource": gas_source, "note": note}
    with open(tx_file(), "a") as fh:
        fh.write(json.dumps(line) + "\n")
    return 0


def read_txs():
    p = tx_file()
    if not os.path.isfile(p):
        return []
    with open(p) as fh:
        return [json.loads(l) for l in fh if l.strip()]


def cmd_cap(key):
    """Print the gas cap for a step, or refuse to invent one.

    An estimate against an address with no code is not a small number, it is a wrong number, and the
    step that silently gets 21000 is the one that runs out of gas in the middle of a launch.
    """
    if key in CAPS:
        want = os.environ.get("CAP_" + key.upper())
        if want is not None:
            if not want.isdigit() or int(want) < CAPS[key]:
                die("CAP_%s=%s is not an integer at or above the measured cap %s for %s. Raising a "
                    "cap is a deliberate act; lowering one below what the rehearsal measured is how a "
                    "launch runs out of gas." % (key.upper(), want, CAPS[key], key))
            print(want)
            return 0
        print(CAPS[key])
        return 0
    die("no gas cap is defined for %r. Set CAPS in %s (or CAP_%s=... in the environment) with the "
        "measured number from the rehearsal -- do not let a planner guess a cap."
        % (key, os.path.basename(__file__), key.upper()))


def cmd_reserve_gas():
    """Print the total gas the batch has accumulated so far, so the planner can cost it before it finishes."""
    txs = read_txs()
    print("%d %d" % (sum(t["gas"] for t in txs), sum(t["gas"] * t["maxFeePerGas"] for t in txs)))
    return 0


def cmd_finish(argv):
    """Write plan.json + MANIFEST.txt from txs.jsonl and the PLAN_* environment.

    The nonce run must be contiguous, one transaction per nonce: a gap means a step was planned twice
    or dropped, and a repeat means two of the signed lines can never both land.
    """
    d = os.environ.get("PLAN_DIR") or die("PLAN_DIR is not set")
    txs = read_txs()
    if not txs:
        die("txs.jsonl is empty -- nothing was planned")
    n0 = int(os.environ["PLAN_START_NONCE"])
    want = list(range(n0, n0 + len(txs)))
    got = [t["nonce"] for t in txs]
    if got != want:
        die("the nonces in this plan are %s, expected the contiguous run %s. A gapped or repeated "
            "nonce is a planner bug, not a launch detail." % (got, want))
    labels = [t["label"] for t in txs]
    if len(set(labels)) != len(labels):
        die("two planned transactions share a label: %s. The broadcaster pairs a signed file to a "
            "step by that label, so a duplicate makes the pairing meaningless." % labels)

    env = os.environ.get
    plan = {
        "kind": "lxon-wlxonsecure-137-offline-plan",
        "chainId": int(env("PLAN_CHAIN_ID")),
        "from": env("PLAN_DEPLOYER"),
        "rpc": env("PLAN_RPC"),
        "feeMode": "eip1559",
        "maxFeePerGasWei": int(env("PLAN_MAX_FEE")),
        "maxPriorityFeePerGasWei": int(env("PLAN_PRIORITY_FEE")),
        "startNonce": n0,
        "txCount": len(txs),
        "phase": env("PLAN_PHASE", "deploy"),
        "predictedTimelock": env("PLAN_PREDICTED_TIMELOCK") or None,
        "timelockMode": env("PLAN_TIMELOCK_MODE") or None,
        "timelockMinDelay": int(env("PLAN_TIMELOCK_MIN_DELAY")) if env("PLAN_TIMELOCK_MIN_DELAY") else None,
        "predictedWlxon": env("PLAN_PREDICTED_WLXON") or None,
        "predictedMigration": env("PLAN_PREDICTED_MIGRATION") or None,
        "legacyWlxon": env("PLAN_LEGACY") or None,
        "timelock": env("PLAN_TIMELOCK") or None,
        "quorum": int(env("PLAN_QUORUM")) if env("PLAN_QUORUM") else None,
        "nativeLXON": env("PLAN_NATIVE_LXON") or None,
        "reserveWei": int(env("PLAN_RESERVE")) if env("PLAN_RESERVE") else 0,
        # The legacy-retirement gate, in the plan rather than only in the planner's stdout: a fund batch
        # that was signed with the gate overridden has to say so where the signatures live, or the next
        # reader sees a plan that opened a window over 4.01M unbacked legacy tokens and has no way to know
        # that anyone decided that.
        "legacyToken": env("PLAN_LEGACY_ADDR") or None,
        "legacySupply": int(env("PLAN_LEGACY_SUPPLY")) if env("PLAN_LEGACY_SUPPLY") else None,
        "legacyRetirementGate": env("PLAN_LEGACY_GATE", "not-checked"),
        "migrationDays": int(os.environ["PLAN_MIGRATION_DAYS"]) if env("PLAN_MIGRATION_DAYS") else None,
        "opensMigrationWindow": env("PLAN_OPENS_WINDOW", "0") == "1",
        "sealsOnBroadcast": False,
        "feeSource": env("PLAN_FEE_SOURCE", "default"),
        "capsSource": env("PLAN_CAPS_SOURCE", "script/polygon137/lib/plan137.py CAPS"),
        # Admin-ceremony facts (PHASE=schedule|execute). They live in the plan so the broadcaster's
        # read-back and the launch record can name the proposal rather than re-derive it from a shell
        # variable that only existed during planning.
        "adminTarget": env("PLAN_ADMIN_TARGET") or None,
        "adminSig": env("PLAN_ADMIN_SIG") or None,
        "adminArgs": env("PLAN_ADMIN_ARGS") or None,
        "attestor": env("PLAN_ATTESTOR") or None,
        "proposalId": env("PLAN_PROPOSAL_ID") or None,
        "proposalEta": int(env("PLAN_ETA")) if env("PLAN_ETA") else None,
        "generatedAt": env("PLAN_STAMP"),
        "txs": txs,
        "readBeforeSigning": "the deployer nonce on chain %s must still be %d, and the node must "
                             "still report chain id %s" % (env("PLAN_CHAIN_ID"), n0, env("PLAN_CHAIN_ID")),
    }
    with open(os.path.join(d, "plan.json"), "w") as fh:
        json.dump(plan, fh, indent=1)

    total_gas = sum(t["gas"] for t in txs)
    worst_wei = sum(t["gas"] * t["maxFeePerGas"] for t in txs)
    lines = []
    lines.append("Offline signing plan -- %s -- Polygon %s (EIP-1559) -- phase %s -- %s"
                 % (plan["rpc"], plan["chainId"], plan["phase"], plan["generatedAt"]))
    lines.append("signer        : %s (maxFee %s wei, tip %s wei)"
                 % (plan["from"], plan["maxFeePerGasWei"], plan["maxPriorityFeePerGasWei"]))
    lines.append("nonce run     : %d..%d, one transaction each, broadcast in this order"
                 % (n0, n0 + len(txs) - 1))
    if plan["timelockMode"] == "create":
        lines.append("custody       : this batch CREATES a TimelockController (minDelay %s s = %s h) at %s"
                     % (plan["timelockMinDelay"], plan["timelockMinDelay"] // 3600, plan["predictedTimelock"]))
        lines.append("                ADMIN_ROLE on wLXONSecure belongs to it, so addAttestor, setQuorum,")
        lines.append("                pauseBridge and emergencyWithdraw each wait %s hours and each need a"
                     % (plan["timelockMinDelay"] // 3600))
        lines.append("                queue+execute through that timelock by an account holding PROPOSER_ROLE.")
    elif plan["predictedTimelock"]:
        lines.append("custody       : ADMIN_ROLE -> existing address %s (mode %s)"
                     % (plan["predictedTimelock"], plan["timelockMode"]))
    if plan["predictedWlxon"]:
        lines.append("predicted     : wLXONSecure %s" % plan["predictedWlxon"])
    if plan["predictedMigration"]:
        lines.append("                migration   %s" % plan["predictedMigration"])
    if plan["proposalId"]:
        import datetime
        eta = plan["proposalEta"] or 0
        lines.append("admin call    : %s %s on %s" % (plan["adminSig"], plan["adminArgs"], plan["adminTarget"]))
        lines.append("proposal id   : %s" % plan["proposalId"])
        lines.append("                hashOperation(target,value,data,0x0,salt 0x0) -- the contract's own")
        lines.append("                pure function, asked of the node at planning time, not computed here.")
        if plan["phase"] == "schedule":
            lines.append("                executes no sooner than minDelay (%s s) after the block that mines THIS"
                         % plan["timelockMinDelay"])
            lines.append("                transaction. This plan cannot know that timestamp -- the scheduling tx has")
            lines.append("                not mined yet. Read getTimestamp(id) from the chain after broadcasting and")
            lines.append("                wait for that, not for a clock guessed here.")
        else:
            lines.append("                scheduled with eta %s (unix %s); this leg executes it"
                         % (datetime.datetime.fromtimestamp(eta, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), eta))
    lines.append("total gas cap : %d gas = %d wei of POL at this maxFee (worst case, unused gas is refunded)"
                 % (total_gas, worst_wei))
    lines.append("")
    for i, t in enumerate(txs):
        where = "CREATE" if t["to"] == "0x" else "-> %s" % t["to"]
        lines.append("  %02d nonce %-5d %-14s %-46s gas %-8d [%s]"
                     % (i, t["nonce"], t["label"], where, t["gas"], t["note"]))
        lines.append("       %d hex of calldata, priced by %s" % (len(t["data"]), t["gasSource"]))
    lines.append("")
    if plan.get("legacyRetirementGate") == "overridden":
        lines.append("THE LEGACY-RETIREMENT GATE WAS OVERRIDDEN (WLXON_I_ACCEPT_LEGACY_UNRETIRED=1).")
        lines.append("This batch opens a 1:1 window over %s wLXON of legacy supply at %s -- supply that is"
                     % ("%.6f" % ((plan["legacySupply"] or 0) / 10**18), plan["legacyToken"]))
        lines.append("not backed on chain, held entirely by a key that is reachable in this repo's git"
                     " history, and that key can mint more of it."
                     if plan["legacySupply"] else "not backed on chain.")
        lines.append("startMigration() on the migration contract is ADMIN_ROLE of the DEPLOYER (no timelock),")
        lines.append("so nothing on the chain stops this -- only this line and the decision behind it do.")
        lines.append("")
    if plan["phase"] in ("schedule", "execute"):
        lines.append("THIS BATCH MOVES NO VALUE AND OPENS NOTHING. It is the %s leg of one ADMIN_ROLE call,"
                     % plan["phase"])
        lines.append("held behind a %s h timelock. Registering an attestor changes nothing about supply: a mint"
                     % (plan["timelockMinDelay"] // 3600 if plan["timelockMinDelay"] else 0))
        lines.append("needs quorum (%s) DISTINCT ATTESTOR_ROLE signatures over the same claim, and one is not %s."
                     % (plan["quorum"], plan["quorum"]))
        lines.append("")
    elif plan["opensMigrationWindow"]:
        lines.append("THIS BATCH OPENS THE MIGRATION WINDOW. startMigration() plus the published window is the\n"
                     "part users act on: from the moment it lands, holders can surrender legacy wLXON at 1:1\n"
                     "against the reserve this contract holds. If the reserve line is absent or under-sized,\n"
                     "every migration after the reserve runs out reverts with InsufficientReserve -- the users\n"
                     "who were fastest are the ones paid. Confirm the reserve on chain before signing.\n")
    else:
        lines.append("THIS BATCH DOES NOT OPEN THE WINDOW. Nothing becomes claimable until a later single\n"
                     "transaction calls startMigration(duration), which is only correct once the reserve has\n"
                     "actually arrived at the migration contract.\n")
    lines.append("Treat the signed batch as you would cash: anyone holding it can broadcast it once, and the\n"
                 "nonce pinning makes it single-use -- as soon as nonce %d is on chain, every other line is\n"
                 "dead. This plan moves no value of its own; it %s.\n"
                 % (n0, {"deploy": "deploys and configures", "fund": "pays the reserve and opens the window",
                         "schedule": "only queues an operation for the timelock",
                         "execute": "only runs the one operation the timelock already approved"}.get(plan["phase"],
                                                                                                        "configures")))
    with open(os.path.join(d, "MANIFEST.txt"), "w") as fh:
        fh.write("\n".join(lines) + "\n")

    print(json.dumps({"plan": os.path.join(d, "plan.json"), "transactions": len(txs),
                      "startNonce": n0, "totalGas": total_gas, "worstCaseGasWei": worst_wei,
                      "predictedWlxon": plan["predictedWlxon"],
                      "predictedMigration": plan["predictedMigration"]}))
    return 0


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd == "bytecode":
        return cmd_bytecode(argv[2])
    if cmd == "ctorsig":
        return cmd_ctorsig(argv[2])
    if cmd == "calltypes":
        return cmd_calltypes(argv[2], argv[3])
    if cmd == "add":
        return cmd_add(argv)
    if cmd == "cap":
        return cmd_cap(argv[2])
    if cmd == "reserve-gas":
        return cmd_reserve_gas()
    if cmd == "finish":
        return cmd_finish(argv)
    sys.stderr.write(__doc__ + "\ncommands: bytecode | ctorsig | calltypes | cap | add | reserve-gas | finish\n")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))

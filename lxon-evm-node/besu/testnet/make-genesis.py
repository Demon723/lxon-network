#!/usr/bin/env python3
"""Generate 725/genesis.json (4 validators) and 726/genesis.json (1 validator) using Besu's own
RLP encoder, then prove -- here, before this script exits -- that the validator lists came out right.

The config file for `besu operator generate-blockchain-config` MUST have
  blockchain.nodes.generate = false
  blockchain.nodes.keys     = [uncompressed public keys]
and genesis.extraData = "0x". `nodeCount` is silently ignored by Besu 26.10: passing
generate:true logs "Generating 0 nodes keys", emits an EMPTY validator list and a chain that
never seals. That string is a fatal error here, and the extraData that comes back is RLP-decoded
and compared to the addresses we asked for, so a broken genesis can never be written out and
committed by a script that returned 0.

Besu writes a directory per node under `--to` (measured with this very command: `keys/<addr>/key.pub`,
and `key` holding the node private key when it generates them itself). `--to` therefore points at a
temporary directory OUTSIDE the repository, and only genesis.json and the operator config are copied
back -- and only after every check below has passed -- so no key material and no rejected config can
ever be left in the tree by a run that exited non-zero. The */raw/ ignore rule stays as defence in
depth. Public key material is the only thing read from keys/ here.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

# How old a `besu-operator-*` directory has to look before the startup sweep is allowed to remove it.
# See _sweep_stale_workdirs: the gate exists so this cleanup can never eat a run that is still going.
STALE_AFTER_SECONDS = 30 * 60

from assert_genesis import BALANCE, EVM_GATES, address_from_pub, pub_key_bytes, validator_addresses

BASE = os.path.dirname(os.path.abspath(__file__))
IMAGE = os.environ.get("BESU_IMAGE", "hyperledger/besu:26.10.0")
# Besu log lines that mean the run produced an unsealable chain. Reported by name only -- the
# raw log is never printed, because a generating run's log can carry key material.
FATAL_LOG_MARKERS = ("Generating 0 nodes keys",)


def read(*parts):
    with open(os.path.join(BASE, *parts)) as fh:
        return fh.read().strip()


def read_pub(number):
    """keys/pub-N.hex, shape-checked: `0x` + 128 hex, 64 raw bytes, no 04 prefix. Guards against
    a 64-hex private key being pasted into a public file and copied into the committed config."""
    name = f"pub-{number}.hex"
    text = read("keys", name)
    pub_key_bytes(name, text)
    return text


def config(chain_id, pubs, alloc_addresses):
    cfg = {
        "blockchain": {"nodes": {"generate": False, "keys": pubs}, "genesisVersion": 1},
        "genesis": {
            "alloc": {a.lower().removeprefix("0x"): {"balance": BALANCE} for a in alloc_addresses},
            "coinbase": "0x0000000000000000000000000000000000000000",
            "config": {
                "chainId": chain_id,
                **EVM_GATES,
                # 3s blocks so tests do not sleep 5s each, epoch 30 so a QBFT validator vote
                # lands in ~90s instead of production's ~41 hours at epochlength 30000.
                "qbft": {"blockperiodseconds": 3, "epochlength": 30, "requesttimeoutseconds": 10},
            },
            "difficulty": "0x1",
            "extraData": "0x",
            "gasLimit": "0x1c9c380",
            "gasUsed": "0x0",
            "mixHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
            "nonce": "0x0",
            "number": "0x0",
            "parentHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
            "timestamp": "0x655c0000",
        },
    }
    return cfg


def fatal_markers(text):
    return [m for m in FATAL_LOG_MARKERS if m in text]


def _sweep_stale_workdirs():
    """Remove leftover `besu-operator-*` directories before any key material is produced (N2).

    `finally` is not a guarantee: SIGKILL -- the container runtime restarting, the OOM killer, an
    agent hitting its tool timeout -- leaves the directory exactly as Besu left it, holding
    `gen/keys/<addr>/key` for every node, mode 0777 because uid 1000 has to be able to write through
    it. The survivor is then invisible to the next run, which simply makes a new one. Sweeping both
    the temp root and the repository at startup bounds how long that can sit around.
    """
    # gettempdir() is whatever TMPDIR said for THIS process, so a survivor from a run that had a
    # different TMPDIR -- which is exactly what an agent-timeout kill produces -- sits somewhere
    # else. Sweep the usual roots rather than only the current one, and de-duplicate through
    # realpath because /tmp is a symlink to /private/tmp on macOS and reported the same survivor
    # twice before this was resolved.
    roots, seen = [], set()
    for root in (tempfile.gettempdir(), "/tmp", BASE):
        real = os.path.realpath(root)
        if real not in seen:
            seen.add(real)
            roots.append(real)
    swept, refused = [], []
    for root in roots:
        try:
            names = sorted(os.listdir(root))
        except OSError:
            continue
        for name in names:
            if not name.startswith("besu-operator-"):
                continue
            path = os.path.join(root, name)
            if os.path.islink(path):
                refused.append(f"{path} (symlink -- not following it)")
                continue
            if not os.path.isdir(path):
                refused.append(f"{path} (not a directory -- leaving it alone)")
                continue
            # An age gate, and it is the important part: without it this sweep would delete the
            # working directory of a make-genesis.py run that is still in flight -- another session,
            # or this script re-run while a first one waits on docker. A live directory is young; a
            # SIGKILL survivor is not. 30 minutes is far longer than one `besu operator` call takes
            # and far shorter than "left there since the last crash".
            try:
                age = time.time() - os.stat(path).st_mtime
            except OSError as exc:
                refused.append(f"{path} (cannot stat it: {exc})")
                continue
            if age < STALE_AFTER_SECONDS:
                refused.append(f"{path} (only {int(age)}s old -- a run may be using it, not touching it)")
                continue
            try:
                shutil.rmtree(path)
                swept.append(path)
            except OSError as exc:
                refused.append(f"{path} ({type(exc).__name__}: {exc})")
    for path in swept:
        print(f"swept a stale Besu temporary directory: {path}", file=sys.stderr)
    for path in refused:
        print(f"WARNING: refusing to remove {path}; if it holds node keys, delete it by hand",
              file=sys.stderr)
    return swept, refused


def generate(chain_id, out_dir, pubs, expected_addresses, alloc_addresses):
    """Ask Besu to encode one genesis, verify what it encoded, keep only genesis.json.

    Raises SystemExit (non-zero exit) on any mismatch; the temporary Besu directory is
    removed even when the verification or the container fails. The operator config is written
    INTO that temporary directory and only copied into the repository -- next to the genesis --
    once every check below has passed, so a rejected run leaves `725/operator-config.json`
    exactly as it was instead of committing a config Besu refused.
    """
    if len(pubs) != len(expected_addresses):
        raise SystemExit(f"{out_dir}: {len(pubs)} public keys but {len(expected_addresses)} addresses")
    os.makedirs(out_dir, exist_ok=True)
    work = tempfile.mkdtemp(prefix=f"besu-operator-{chain_id}-")   # outside the repository
    # "outside the repository" has to be checked, not assumed: mkdtemp honours TMPDIR, so an
    # environment that points TMPDIR at this very directory would otherwise put Besu's node private
    # keys inside the tree, and the ignore rules do not cover that shape. Refusing before the config
    # is written means nothing secret is ever created there.
    real_work = os.path.realpath(work)
    if real_work == BASE or real_work.startswith(BASE + os.sep):
        shutil.rmtree(work, ignore_errors=True)
        raise SystemExit(
            f"refusing to build Besu operator output inside the repository: TMPDIR resolves to "
            f"{real_work}, which is under {BASE}. Set TMPDIR outside the tree and re-run.")
    os.chmod(work, 0o777)                    # Besu runs as uid 1000 inside the image
    cfg_path = os.path.join(work, "operator-config.json")
    with open(cfg_path, "w") as fh:
        json.dump(config(chain_id, pubs, alloc_addresses), fh, indent=1)
        fh.write("\n")
    try:
        proc = subprocess.run(
            ["docker", "run", "--rm", "-u", "1000:1000",
             "-v", f"{BASE}:/work", "-v", f"{work}:/out",
             "--entrypoint", "/opt/besu/bin/besu", IMAGE,
             "operator", "generate-blockchain-config",
             # /out is the temporary directory, so the config never exists in the repository
             # while Besu is running.
             f"--config-file=/out/{os.path.basename(cfg_path)}",
             # Besu refuses an output directory that already exists ("Output directory already
             # exists.", exit 1) and Docker always creates the source of a bind mount, so `--to`
             # has to name a path *inside* the mount that does not exist yet. Measured on
             # hyperledger/besu:26.10.0: /out fails, /out/gen succeeds. Besu creates gen/ itself
             # and drops `keys/` -- real node key material -- next to the genesis inside it, which
             # is precisely why the mount is a temporary directory outside the repository and why
             # only genesis.json is ever copied back.
             "--to=/out/gen"],
            capture_output=True, text=True,
        )
        log = (proc.stdout or "") + (proc.stderr or "")
        markers = fatal_markers(log)
        if proc.returncode != 0:
            raise SystemExit(
                f"besu operator generate-blockchain-config for {chain_id} exited "
                f"{proc.returncode}"
                + (f" and matched fatal log marker(s) {markers}" if markers else "")
                + "; re-run the command by hand to read its log")
        if markers:
            raise SystemExit(
                f"{out_dir}: Besu reported {markers} -- the config fell back to generate:true / "
                "nodeCount, which Besu 26.10 ignores. The genesis it emits has no validators and "
                "the chain could never seal.")
        with open(os.path.join(work, "gen", "genesis.json")) as fh:
            genesis = json.load(fh)

        # -- verify the encoder's own output before trusting it -------------------
        extra_data = genesis.get("extraData")
        if not isinstance(extra_data, str) or extra_data in ("", "0x"):
            raise SystemExit(f"{out_dir}: Besu returned extraData {extra_data!r}; no validators")
        got = validator_addresses(extra_data)
        want = [a.lower().removeprefix("0x") for a in expected_addresses]
        if got != want:
            raise SystemExit(
                f"{out_dir}: extraData encodes {len(got)} validator(s) {got}, "
                f"asked for {len(want)} {want}. Nothing was written.")
        if genesis["config"]["chainId"] != chain_id:
            raise SystemExit(f"{out_dir}: chainId {genesis['config']['chainId']} != {chain_id}")

        # Everything passed: only now does anything enter the repository.
        with open(os.path.join(out_dir, "genesis.json"), "w") as fh:
            json.dump(genesis, fh, indent=2)
            fh.write("\n")
        shutil.copyfile(cfg_path, os.path.join(out_dir, "operator-config.json"))
        print(f"{out_dir}: chainId {genesis['config']['chainId']}, "
              f"{len(got)} validator(s), extraData {len(bytes.fromhex(extra_data[2:]))} bytes")
    finally:
        shutil.rmtree(work, ignore_errors=True)
        if os.path.exists(work):
            print(f"WARNING: temporary Besu directory {work} survived; it can hold node private "
                  f"keys -- delete it with:  rm -rf {work!r}", file=sys.stderr)


def main():
    _sweep_stale_workdirs()      # N2: a previous run killed mid-Besu may have left keys behind
    pubs = [read_pub(i) for i in range(1, 7)]
    # Every address used here is derived from the public key file it stands for, so the
    # generator asks Besu for the validators the keys on disk actually are -- not for whatever
    # keys/address-N.txt happens to say.
    addrs = [address_from_pub(f"pub-{i}.hex", pubs[i - 1]) for i in range(1, 7)]
    stored = [read("keys", f"address-{i}.txt").lower() for i in range(1, 7)]
    for i, (a, s) in enumerate(zip(addrs, stored), 1):
        if a != s:
            raise SystemExit(f"keys/address-{i}.txt says {s} but pub-{i}.hex derives to {a}")
    deployer = read("keys", "deployer-address.txt")
    everyone = addrs + [deployer]
    # 725: nodes 1-4 seal; node 5 does not, but is funded so Task 3 can vote it in and run it.
    generate(725, os.path.join(BASE, "725"), pubs[:4], addrs[:4], everyone)
    # 726: node 6 alone -- its own key, so no two running nodes ever share a node ID.
    generate(726, os.path.join(BASE, "726"), pubs[5:6], addrs[5:6], everyone)
    with open(os.path.join(BASE, "validators-725.txt"), "w") as fh:
        fh.write("\n".join(addrs[:4]) + "\n")
    with open(os.path.join(BASE, "validator-addresses.txt"), "w") as fh:
        fh.write("\n".join(addrs) + "\n")
    print("spare validator (not in 725 genesis, line 5):", addrs[4])
    print("726 validator (line 6):", addrs[5])
    print("deployer:", deployer)
    print("only genesis.json was copied back out of the temporary Besu output directory; "
          "it lives outside the repository and is removed on success and on failure")


if __name__ == "__main__":
    sys.exit(main())

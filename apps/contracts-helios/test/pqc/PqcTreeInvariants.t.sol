// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Test} from "forge-std/Test.sol";

/// Plan 2 Task 1. These are not contract tests; they are the assertions the
/// tree question in docs/runbooks/contracts-tree-reconciliation-2026-11-06.md
/// §3 asks for, written down so they cannot rot into prose. They read files,
/// which is why vm.ffi is used rather than vm.readFile: fs_permissions is
/// deliberately not granted to any profile in this tree, and the exception is
/// made per-invocation with `--ffi` rather than in the shared foundry.toml that
/// other sessions compile against.
contract PqcTreeInvariantsTest is Test {
    /// vm.ffi takes an ARGV, not a shell string. ["bash", "echo OK"] hands bash a
    /// *filename* and exits 127 ("bash: echo OK: No such file or directory") --
    /// measured. The three-element form below is what interprets redirections.
    /// Every command is prefixed with a cd to the repository top level because
    /// ffi's cwd is the project root the test was invoked from, and these
    /// assertions are written relative to the repo root on purpose.
    function _ffi(string memory cmd) internal returns (bytes memory) {
        string[] memory parts = new string[](3);
        parts[0] = "bash";
        parts[1] = "-c";
        parts[2] = string.concat('cd "$(git rev-parse --show-toplevel)" || exit 78; ', cmd);
        return vm.ffi(parts);
    }

    function _out(string memory cmd) internal returns (bytes memory) {
        return _ffi(cmd);
    }

    /// An empty ffi read is a harness failure, not a value. Without this guard a missing file or a
    /// command that writes nothing compares keccak256("") against the expected hash: loud enough to
    /// fail, but the report shows a hash difference instead of the reason, which is how a version
    /// assertion stops asserting anything and nobody notices for a month.
    function _must(string memory cmd) internal returns (bytes memory) {
        bytes memory out = _out(cmd);
        require(out.length > 0, "ffi read returned nothing -- the path or the command is wrong");
        return out;
    }

    // Requirement 5: AccessControl semantics are shared between V41 and C4, and the
    /// "roles carry over unchanged" argument holds only while the two FORGE trees resolve the same
    // OpenZeppelin. Nothing asserted it before this plan, and the repo has THREE copies, not two --
    /// measured 2026-11-12:
    //   apps/contracts-helios/lib/openzeppelin-contracts      package.json 5.7.0 (git checkout; describe works)
    //   apps/contracts/lib/openzeppelin-contracts             package.json 5.7.0 (VENDORED, not a git repo:
    //                                                          `describe --tags` prints "fatal: not a git
    //                                                          repository" to stdout and exits 0 through a pipe,
    //                                                          so the obvious command returns an empty value)
    //   apps/contracts/node_modules/@openzeppelin/contracts   5.6.1 (pnpm symlink into the store; the
    ///                                                          Hardhat/typechain side, not what V41 compiles)
    // The pair that matters for shared role semantics is the two libs, and both read package.json
    // because that is the one source present in every case. An earlier draft of this test asserted
    /// 5.7.0 against the 5.6.1 pnpm copy -- it could only ever have failed -- and its successor used
    // `describe --tags` on the vendored lib, which returned nothing. Both were caught by running it.
    function test_oz_versions_are_the_recorded_ones() public {
        assertEq(keccak256(_must(_pkg("apps/contracts-helios/lib/openzeppelin-contracts"))), keccak256("5.7.0"), "helios forge lib");
        assertEq(keccak256(_must(_pkg("apps/contracts/lib/openzeppelin-contracts"))), keccak256("5.7.0"), "apps/contracts forge lib -- the copy V41 compiles against");
        assertEq(keccak256(_must(_pkg("apps/contracts/node_modules/@openzeppelin/contracts"))), keccak256("5.6.1"), "apps/contracts pnpm copy -- Hardhat/typechain side");
    }

    function _pkg(string memory dir) internal pure returns (string memory) {
        return string(abi.encodePacked(
            "python3 -c \"import json,sys;print(json.load(open(sys.argv[1]))['version'])\" ",
            dir, "/package.json | tr -d '\\n'"));
    }

    // Requirement 1: one source root, and the PQC surface is inside it.
    function test_src_pqc_and_test_pqc_exist() public {
        assertEq(keccak256(_must("test -d apps/contracts-helios/src/pqc -a -d apps/contracts-helios/test/pqc && echo OK || echo MISSING")), keccak256("OK"), "src/pqc and test/pqc must exist");
    }

    // Requirement 3, in the direction this plan chose: the reference copy is
    // vendored, byte-identical to the pinned blob, and outside the compiled roots.
    //
    // The `v=` marker is load-bearing, not decoration. forge-std's vm.ffi HEX-DECODES stdout that is
    // entirely hex characters: measured 2026-11-12, the command below returned 5 bytes
    // (0xe305af5744) for a 10-character hash prefix, so keccak256 of it is keccak of the decoded
    // bytes and can never equal keccak256("e305af5744"). Any hex-shaped value crossing ffi must be
    // tagged first; "OK", "ABSENT" and "5.7.0" are unaffected because they are not valid hex.
    function test_v41_reference_copy_is_unchanged() public {
        string memory want = "v=e305af5744"; // measured: git hash-object reference/LXONAttestedBridgeV41.sol | cut -c1-10
        assertEq(keccak256(_must("git hash-object apps/contracts-helios/reference/LXONAttestedBridgeV41.sol | cut -c1-10 | sed 's/^/v=/'")), keccak256(bytes(want)), "reference copy drifted from the pinned blob");
    }

    // The reference must not become a build input. If someone moves it into
    // src/, this test is the minute notice.
    function test_reference_copy_is_not_a_compiled_source() public {
        assertEq(keccak256(_must("test ! -e apps/contracts-helios/src/LXONAttestedBridgeV41.sol && echo ABSENT || echo PRESENT")), keccak256("ABSENT"), "V41 must not sit in src/");
    }
}
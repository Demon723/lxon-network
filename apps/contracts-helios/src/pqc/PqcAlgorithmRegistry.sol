// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {PqcSchemeWord} from "./PqcSchemeWord.sol";

/**
 * PqcAlgorithmRegistry (C4).
 *
 * Rows mutable, code not. This contract exists as a SEPARATE contract for exactly
 * one reason, and spec §6.4 owns the argument: `setThreshold` and every other
 * v4.1 setter is timelocked, so scheme rows living in bridge storage would inherit
 * a 48-hour minimum for the emergency abandonment of a broken scheme. Splitting it
 * makes `disable` immediate and keeps `adopt` at 48 hours. It buys nothing else,
 * and the price is one EXTSTATICCALL per claim, which is why the read interface
 * below is a packed word rather than the struct.
 *
 * Two roles, because one cannot give both speed and safety:
 *   SCHEME_DISABLE_ROLE  set enabled=false, immediately. Never true, never a
 *                        paramHash, never a row.
 *   SCHEME_ADMIN_ROLE    enable, add, repoint paramHash, and set the mode.
 *
 * `authorising` is not stored. It is `verifyMode == Strong && this row is the one
 * Strong consults`, evaluated at read time, because a stored flag that the mode
 * does not consult is a claim about capability written down that nothing checks —
 * which is the same defect class as `secondary-attestor.ts`'s hardcoded
 * `mayoAvailable = true` (spec §7).
 */
contract PqcAlgorithmRegistry is AccessControl {
    enum Venue { None, Offchain, Onchain }
    enum Mode { Default, Strong }

    struct SchemeRow {
        bytes32 id;           // keccak256("mayo2") etc.
        Venue   venue;
        bool    enabled;
        uint8   minSecurityLevel;
        bytes32 paramHash;    // commitment to pk/sig/sk lengths and parameterisation
        address verifier;     // zero for Offchain rows
        bool    present;
    }

    bytes32 public constant SCHEME_DISABLE_ROLE = keccak256("LXON_PQC_SCHEME_DISABLE_ROLE");
    bytes32 public constant SCHEME_ADMIN_ROLE   = keccak256("LXON_PQC_SCHEME_ADMIN_ROLE");

    bytes32 public constant MAYO2_ID   = keccak256("mayo2");
    bytes32 public constant MLDSA44_ID = keccak256("mldsa44");
    bytes32 public constant FNDSA512_ID = keccak256("fn_dsa512");

    /// The only row Strong consults. Keeping it a constant rather than a field is
    /// deliberate: a mutable "authorising row" pointer would be a second way for
    /// the mode and the rows to disagree.
    bytes32 public constant STRONG_VERIFIED_ID = MLDSA44_ID;

    mapping(bytes32 => SchemeRow) private _rows;
    bytes32[] private _ids;
    Mode private _mode = Mode.Default;

    error NotAdmin();
    error Unparameterized(bytes32 id);
    error AlreadyPresent(bytes32 id);
    error WouldSkipVerification(bytes32 id);
    error SchemeUnavailable(bytes32 id);

    event SchemeRowAdded(bytes32 indexed id, uint8 venue, bytes32 paramHash, address verifier, uint8 level);
    event EnabledSet(bytes32 indexed id, bool enabled);
    event ParamHashSet(bytes32 indexed id, bytes32 paramHash);
    event VerifierSet(bytes32 indexed id, address verifier);
    event ModeSet(uint8 mode);

    modifier onlyAdmin() {
        if (!hasRole(SCHEME_ADMIN_ROLE, msg.sender)) revert NotAdmin();
        _;
    }

    constructor(address adminHolder, address disableHolder) {
        _grantRole(SCHEME_ADMIN_ROLE, adminHolder);
        _grantRole(SCHEME_DISABLE_ROLE, disableHolder);
        // Seed rows. mayo2 is enabled and, under decision 13, permanently
        // non-authorising: the contract cannot verify MAYO at any affordable gas
        // (938,752,492, spec §1.3), so this row records a transport, not a check.
        _add(MAYO2_ID, Venue.Offchain, bytes32(uint256(keccak256("mayo2/24/4912/186"))), address(0), 2, true);
        _add(MLDSA44_ID, Venue.Onchain, bytes32(uint256(keccak256("mldsa44/1312/2560/2420"))), address(0), 3, true);
        // FIPS 206 is not final; disabled at birth, and no verifier wired yet.
        _add(FNDSA512_ID, Venue.Offchain, bytes32(0), address(0), 5, false);
    }

    function _add(bytes32 id, Venue venue, bytes32 paramHash, address verifier, uint8 level, bool enabled) private {
        if (_rows[id].present) revert AlreadyPresent(id);
        _rows[id] = SchemeRow({
            id: id, venue: venue, enabled: enabled, minSecurityLevel: level,
            paramHash: paramHash, verifier: verifier, present: true
        });
        _ids.push(id);
        emit SchemeRowAdded(id, uint8(venue), paramHash, verifier, level);
    }

    // ------------------------------------------------------------------ reads

    /// One EXTSTATICCALL per claim. Bit layout (see `unpack`):
    ///   [0]      present
    ///   [1]      enabled
    ///   [2..3]   venue (uint8)
    ///   [4]      authorising, DERIVED from _mode at this very call
    ///   [5..12]  minSecurityLevel
    function readScheme(bytes32 id) external view returns (uint256 packed) {
        SchemeRow storage r = _rows[id];
        bool authorising = _mode == Mode.Strong && id == STRONG_VERIFIED_ID;
        packed = PqcSchemeWord.pack(r.present, r.enabled, uint8(r.venue), authorising, r.minSecurityLevel);
    }

    function readEnabled(bytes32 id) external view returns (bool) {
        return _rows[id].enabled;
    }

    function readVerifier(bytes32 id) external view returns (address) {
        return _rows[id].verifier;
    }

    function readParamHash(bytes32 id) external view returns (bytes32) {
        return _rows[id].paramHash;
    }

    function verifyMode() external view returns (Mode) {
        return _mode;
    }

    function isVerifiedNow(bytes32 id) public view returns (bool) {
        return _mode == Mode.Strong && id == STRONG_VERIFIED_ID;
    }

    function schemeCount() external view returns (uint256) {
        return _ids.length;
    }

    function schemeIdAt(uint256 i) external view returns (bytes32) {
        return _ids[i];
    }

    // ----------------------------------------------------------------- writes

    /// Immediate, and the whole point of the split. Turning the row the active
    /// mode verifies off while that mode is active would be the §7 mirror-image
    /// bug — a scheme configured off and claims still settling without it — so
    /// it is refused rather than honoured. Leave Strong first; that costs 48 h.
    function disable(bytes32 id) external {
        if (!hasRole(SCHEME_DISABLE_ROLE, msg.sender)) revert NotAdmin();
        if (_isLiveAuthorising(_rows[id])) revert WouldSkipVerification(id);
        _rows[id].enabled = false;
        emit EnabledSet(id, false);
    }

    function enable(bytes32 id) external onlyAdmin {
        if (_rows[id].paramHash == bytes32(0)) revert Unparameterized(id);
        _rows[id].enabled = true;
        emit EnabledSet(id, true);
    }

    function addRow(bytes32 id, uint8 venue, bytes32 paramHash, address verifier, uint8 level) external onlyAdmin {
        _add(id, Venue(venue), paramHash, verifier, level, false); // new rows are born disabled
    }

    function setParamHash(bytes32 id, bytes32 paramHash) external onlyAdmin {
        _rows[id].paramHash = paramHash;
        emit ParamHashSet(id, paramHash);
    }

    function setVerifier(bytes32 id, address verifier) external onlyAdmin {
        _rows[id].verifier = verifier;
        emit VerifierSet(id, verifier);
    }

    /// Writable only by SCHEME_ADMIN_ROLE in BOTH directions (§0 item 14): entering
    /// Strong is a decision and leaving it is also one. A deployment that made only
    /// the upward direction timelocked could downgrade inside one block, which is
    /// the quiet version of the downgrade this guard exists to make loud.
    function setMode(Mode m) external onlyAdmin {
        _mode = m;
        emit ModeSet(uint8(m));
    }

    /// The row is live AND the active mode consults it. This is the state
    /// `disable` must refuse to leave behind: an authorising scheme switched off
    /// while claims still settle without it is §7's fail-closed-skeleton bug
    /// wearing the opposite face — it does not look broken, it looks normal.
    function _isLiveAuthorising(SchemeRow storage r) private view returns (bool) {
        return _mode == Mode.Strong && r.id == STRONG_VERIFIED_ID && r.enabled;
    }

    // -------------------------------------------------------------- attestor roster
    //
    // Two directions, because C6's cross-family binding check needs them:
    // index -> validator address (what the claim compares against the recovered
    // signers) and address -> index (what the collector declares). A roster that
    // held only public keys would make the equality uncheckable, so the address
    // pairing is not a convenience — it IS the same-party property (spec C4).
    //
    // Entries are epoch-versioned. keyAt(index, block) exists because C8 verifies
    // historical bundles: one current key per index means every past bundle becomes
    // unverifiable after any routine rotation, and the watcher then raises a forgery
    // alert on honest data. Retired keys are never deleted.

    uint256 public constant MAYO_PK_BYTES = 4912; // ruled revision, from the compiled artifact (T2 row 23)
    uint256 public constant MAX_ROSTER = 16;      // matches v4.1's MAX_VALIDATORS

    struct RosterKey {
        bytes pubkey;
        uint256 activeFromBlock;
        uint256 activeToBlock; // type(uint256).max while current
    }

    struct RosterEntry {
        address validator;
        RosterKey[] history;   // append-only, ascending by activeFromBlock
    }

    mapping(uint256 => RosterEntry) private _roster;      // index => entry
    // validator => index + 1, so that the mapping's zero default means "absent"
    // and index 0 is representable. Reading this as `int256` directly, or writing
    // -1 into a storage slot and expecting Solidity to default it, is the bug: a
    // mapping of address => int256 defaults to 0, which would look like "index 0"
    // for every validator that was never rostered.
    mapping(address => uint256) private _rosterSlot;
    uint256 private _rosterCount;

    error RosterGap(uint8 index, uint256 blockNumber);
    error RosterTooLarge(uint8 index);
    error RosterAddressTaken(address validator);
    error BadKeyLength(uint256 got);
    error UnknownRosterIndex(uint8 index);

    event RosterKeySet(uint8 indexed index, address indexed validator, bytes32 keyHash, uint256 fromBlock);
    event RosterKeyRetired(uint8 indexed index, uint256 toBlock);

    function setRosterKey(uint8 index, address validator, bytes calldata pubkey, uint256 fromBlock)
        external onlyAdmin
    {
        if (index >= MAX_ROSTER) revert RosterTooLarge(index);
        if (pubkey.length != MAYO_PK_BYTES) revert BadKeyLength(pubkey.length);
        if (validator == address(0)) revert RosterAddressTaken(validator);
        RosterEntry storage e = _roster[index];
        if (e.validator == address(0)) {
            if (_rosterSlot[validator] != 0) revert RosterAddressTaken(validator);
            e.validator = validator;
            _rosterSlot[validator] = uint256(index) + 1;
            if (uint256(index) + 1 > _rosterCount) _rosterCount = uint256(index) + 1;
        } else if (e.validator != validator) {
            // One index, one validator identity, forever. Re-pointing an index at a
            // different validator would let a rotation silently move who a past
            // bundle is attributed to — the exact property the binding exists for.
            revert RosterAddressTaken(validator);
        } else if (e.history.length != 0) {
            uint256 last = e.history.length - 1;
            if (e.history[last].activeToBlock == type(uint256).max) revert RosterGap(index, fromBlock);
            if (fromBlock <= e.history[last].activeFromBlock) revert RosterGap(index, fromBlock);
        }
        e.history.push(RosterKey({pubkey: pubkey, activeFromBlock: fromBlock, activeToBlock: type(uint256).max}));
        emit RosterKeySet(index, validator, keccak256(pubkey), fromBlock);
    }

    function retireRosterKey(uint8 index, uint256 toBlock) external onlyAdmin {
        RosterEntry storage e = _roster[index];
        if (e.validator == address(0)) revert UnknownRosterIndex(index);
        uint256 last = e.history.length - 1;
        require(toBlock > e.history[last].activeFromBlock, "to block before key start");
        e.history[last].activeToBlock = toBlock;
        emit RosterKeyRetired(index, toBlock);
    }

    function rosterValidator(uint8 index) external view returns (address) {
        return _roster[index].validator;
    }

    function rosterIndexOf(address validator) external view returns (int256) {
        uint256 slot = _rosterSlot[validator];
        return slot == 0 ? int256(-1) : int256(uint256(slot - 1));
    }

    function rosterCount() external view returns (uint256) {
        return _rosterCount;
    }

    function rosterKeyHistoryLength(uint8 index) external view returns (uint256) {
        return _roster[index].history.length;
    }

    function keyAt(uint8 index, uint256 blockNumber) external view returns (bytes memory) {
        RosterEntry storage e = _roster[index];
        for (uint256 i = 0; i < e.history.length; ++i) {
            RosterKey storage k = e.history[i];
            if (blockNumber >= k.activeFromBlock && blockNumber <= k.activeToBlock) return k.pubkey;
        }
        revert RosterGap(index, blockNumber);
    }

    // The ML-DSA key/blob handle the Strong path reads per signer. Plan 5 owns registering real
    // blobs; this plan owns that the bridge asks for one and refuses when it is absent. A getter
    // rather than a field on the roster entry so the claim-time interface stays single-address.
    mapping(uint256 => address) private _mldsaBlob;

    function setMldsaBlob(uint8 index, address blob) external onlyAdmin {
        _mldsaBlob[index] = blob;
        emit MldsaBlobSet(index, blob);
    }

    function mldsaBlobFor(uint8 index) external view returns (address) {
        return _mldsaBlob[index];
    }

    event MldsaBlobSet(uint8 indexed index, address blob);

    function keyHashAt(uint8 index, uint256 blockNumber) external view returns (bytes32) {
        // The cheap claim-time / log-time form: C6 and C8 need to identify a key,
        // not copy 4,912 bytes around.
        RosterEntry storage e = _roster[index];
        for (uint256 i = 0; i < e.history.length; ++i) {
            RosterKey storage k = e.history[i];
            if (blockNumber >= k.activeFromBlock && blockNumber <= k.activeToBlock) return keccak256(k.pubkey);
        }
        revert RosterGap(index, blockNumber);
    }
}

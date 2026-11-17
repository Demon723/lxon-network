// SPDX-License-Identifier: MIT
// PROVENANCE: copied from reference/LXONAttestedBridgeV41.sol at blob
//   e305af5744340c51245351bd19cb28a5a12f7179 (28,426 bytes, 603 lines; the authority for every
//   V41:NNN citation is attested-bridge:apps/contracts/contracts/LXONAttestedBridgeV41.sol, and
//   test/pqc/PqcTreeInvariants.t.sol fails this file if the copy drifts from that blob).
//   Deltas are Tasks 5, 6, 7 and each is annotated DELTA-C6-n in place.
//   At the end of Task 4 the whole delta is ONE line: the header sentence at :20 reads
//   "LXON PQC bridge v1 (C6) — structural copy of v4.1." where v4.1 said "LXONAttestedBridge v4.1.",
//   and the contract identifier is renamed. Verify with
//   diff <(sed 's/LXONAttestedBridgeV41/LXONPqcBridgeV1/' reference/LXONAttestedBridgeV41.sol) src/pqc/LXONPqcBridgeV1.sol
//   Anything in this file that is not a DELTA-C6-n block is a defect: the point of the copy is that
//   v4.1's own functions are not modified (spec C6), so a reviewer's diff IS the review.
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {PqcSchemeWord} from "./PqcSchemeWord.sol";

// ============================================================ DELTA-C6-4 (Task 7): the registry
// surfaces the claim path uses. Declared here rather than importing the concrete registry, for the
// reason IRoster was declared here in Task 6: the bridge must not acquire a dependency it has not
// agreed to, and a mock must be able to answer exactly these shapes.
//
// This REPLACES Task 6's IRoster, whose single rosterValidator() is one of these five — the same
// handle cannot be two interfaces, and a second immutable pointing at the same contract would be
// a second thing to keep in sync.

interface IPqcRegistry {
    function readScheme(bytes32 id) external view returns (uint256);
    // verifyMode() is `returns (Mode)` on the registry itself (Task 2) and widened to uint256
    // here on purpose: the enum's ABI word IS a uint256, and the alternative is the bridge
    // importing the registry's enum type for one read. Keep the widening, and keep it commented —
    // an unexplained type mismatch between an interface and its implementation is the kind of
    // thing a later reader "fixes" by making the registry return uint256, which then makes every
    // registry-side `Mode` comparison stringly-typed.
    function verifyMode() external view returns (uint256);
    function rosterValidator(uint8 index) external view returns (address);
    function readVerifier(bytes32 id) external view returns (address);
    function rosterIndexOf(address validator) external view returns (int256);
}

/// The ML-DSA public-key blob store. Split from IPqcRegistry because it is a different question
/// — "whose key is this" rather than "is this scheme live" — and because Plan 5 owns registering
/// the blobs; this plan only owns asking, and refusing when the answer is zero.
interface IMldsaKeyStore {
    function mldsaBlobFor(uint8 index) external view returns (address);
}

interface IMldsaVerifier {
    // Fireblocks' own signature: pkBlob is a CONTRACT, not a key — its code must be exactly
    // 20,545 bytes, the output of prepare/prepare.py including the leading 0x00. Plan 1's T1
    // round trip measured that a 20,544-byte payload deployed without that prefix returns false
    // rather than reverting (spec §10 item 28.4), which is why registration is a Plan 5 concern
    // and this task only refuses a missing verifier.
    function verify(address pkBlob, bytes calldata message, bytes calldata signature)
        external view returns (bool accepted);
}

interface IBridgedToken {
    function bridge() external view returns (address);
    function totalSupply() external view returns (uint256);
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
}

/**
 * LXON PQC bridge v1 (C6) — structural copy of v4.1.
 *
 * Fixes the seven Critical/Major items the 2026-10-23 independent review raised against v4
 * (C1 bundle portability, C2 head-of-line brick with no escape, C3 front-runnable initialize,
 * M4 requested-vs-received accounting, M5 unbound mint branch, M7 lane keying, M8 unhashed
 * source block, M9 quorum floor counting inadmissible signers, M10 unverified CEI/reentrancy,
 * M12 no recovery path), plus the minors m13-m17.
 *
 * Two ledgers, never one balance: `escrowed[token]` backs outbound locks and is what a release
 * payout may pay from; `validatorStake[v]` (and `totalStaked()`) is collateral. Stake is topped
 * up after deployment with `depositStake`, because the deployer cannot approve a contract that
 * does not exist yet -- v4 recorded a requested stake as an actual one, and the shortfall was
 * then silently filled from user deposits (M4's second half).
 */
contract LXONPqcBridgeV1 is AccessControl, Pausable, ReentrancyGuard {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;
    using SafeERC20 for IERC20;

    bytes32 public constant PAUSER_ROLE = keccak256("LXON_BRIDGE_PAUSER_ROLE_V41");
    bytes32 public constant CLAIM_DOMAIN_V41 = keccak256("LXON_ATTESTED_BRIDGE_CLAIM_V4.1");
    bytes32 public constant FORFEIT_DOMAIN_V41 = keccak256("LXON_ATTESTED_BRIDGE_FORFEIT_V4.1");

    uint256 public constant MAX_VALIDATORS = 16;
    uint256 public constant MIN_VALIDATORS = 3;
    uint256 public constant FORFEIT_DELAY = 72 hours;
    uint256 public constant MAX_TRANSFER_CEILING = type(uint256).max >> 128;

    enum Mode { None, Escrow, Burn }          // what lockTransfer does with the source token
    enum Payout { None, Release, Mint }       // what claimTransfer does with the payout token
    enum ClaimStatus { None, Completed, Failed }
    enum LockStatus { None, Escrowed, Burned, Refunded }

    struct Request {
        uint256 srcChainId;
        address srcBridge;
        address destBridge;
        uint256 destChainId;
        uint256 laneNonce;
        uint256 srcTotalSent;
        address srcToken;
        uint256 amount;
        address sender;
        address recipient;
        uint256 srcBlock;
    }

    struct Outbound {
        Mode mode;
        bool live;
    }

    struct Inbound {
        address payToken;
        Payout payout;
        uint256 cap;      // outstanding ceiling for Mint payouts; 0 = deny every claim
        bool live;
    }

    IERC20 public immutable stakeToken;       // address(0) when minStake == 0 (Polygon side)
    uint256 public immutable minStake;
    address public immutable timelock;
    address public immutable deployer;
    // DELTA-C6-3 (Task 6) introduced this handle as `rosterRef`; DELTA-C6-4 (Task 7) renamed it to
    // `registry`, because it is now read for more than the roster and one name for one dependency
    // is what keeps a reviewer from guessing which call goes where. Immutable, because a swappable
    // registry is a mode and a roster the quorum can be re-pointed at after the fact.
    address public immutable registry;

    uint256 public threshold = 2;
    uint256 public minTransferAmount;
    uint256 public maxTransferAmount;
    bool public configSealed;
    bool public everUsed;

    address[] private _validators;
    mapping(address => uint256) public validatorStake;
    mapping(uint256 => address) public peerBridges;
    mapping(uint256 => mapping(address => Outbound)) public outbound;
    mapping(uint256 => mapping(address => Inbound)) public inbound;
    mapping(uint256 => mapping(address => uint256)) public totalSentFor;
    mapping(uint256 => mapping(address => uint256)) public laneNonce;
    mapping(uint256 => mapping(address => uint256)) public totalReceivedFrom;
    mapping(address => uint256) public escrowed;
    mapping(bytes32 => ClaimStatus) public claimStatus;
    mapping(bytes32 => uint256) public stuckSince;
    mapping(bytes32 => bytes32) public blockHashAttested;
    mapping(bytes32 => LockStatus) public lockStatus;

    event ValidatorAdded(address indexed validator);
    event StakeDeposited(address indexed validator, uint256 amount, uint256 total);
    event ValidatorRemoved(address indexed validator, uint256 returnedStake);
    event ValidatorSlashed(address indexed validator, uint256 amount, string reason);
    event ThresholdSet(uint256 threshold);
    event LimitsSet(uint256 minTransferAmount, uint256 maxTransferAmount);
    event PeerSet(uint256 indexed chainId, address bridge);
    event OutboundSet(uint256 indexed destChainId, address indexed token, Mode mode, bool live);
    event InboundSet(uint256 indexed srcChainId, address indexed srcToken, address payToken, Payout payout, uint256 cap, bool live);
    event Sealed();
    event TransferLocked(bytes32 indexed claimId, Request request, uint256 received);
    event ClaimCompleted(bytes32 indexed claimId, address indexed recipient, address indexed token, uint256 amount);
    event ClaimFlaggedStuck(bytes32 indexed claimId, address indexed flagger, uint256 at);
    event ClaimForfeited(bytes32 indexed claimId, uint256 amount, uint256 at);
    event LockRefunded(bytes32 indexed claimId, address indexed sender, address token, uint256 amount);
    event TokenRescued(address indexed token, address indexed to, uint256 amount);

    modifier onlyTimelock() {
        require(msg.sender == timelock, "not timelock");
        _;
    }

    /// The 48h gate before launch, and the only gate after it. `seal()` closes the fast path.
    modifier onlyConfigurer() {
        require(msg.sender == timelock || (hasRole(DEFAULT_ADMIN_ROLE, msg.sender) && !configSealed), "not configured yet");
        _;
    }

    constructor(
        address _stakeToken,
        uint256 _minStake,
        address _timelock,
        address[] memory _validatorSet,
        uint256 _threshold,
        uint256 _minTransferAmount,
        uint256 _maxTransferAmount,
        // DELTA-C6-3 (Task 6) added this eighth argument; DELTA-C6-4 (Task 7) renamed it in place.
        address _registryRef
    ) {
        require(_registryRef != address(0), "registry is zero");
        require(_timelock != address(0), "timelock is zero");
        require(_minStake == 0 ? true : _stakeToken != address(0), "stake token is zero");
        require(_validatorSet.length >= MIN_VALIDATORS, "need at least 3 validators");
        require(_validatorSet.length <= MAX_VALIDATORS, "too many validators");
        require(_threshold >= 2, "threshold below 2");
        require(_threshold <= _validatorSet.length, "threshold above validator count");
        require(_minTransferAmount > 0, "min transfer is zero");
        require(_maxTransferAmount >= _minTransferAmount, "max below min");
        require(_maxTransferAmount <= MAX_TRANSFER_CEILING, "max above ceiling");
        for (uint256 i = 0; i < _validatorSet.length; ++i) {
            _addValidator(_validatorSet[i]);
        }
        stakeToken = IERC20(_stakeToken);
        minStake = _minStake;
        timelock = _timelock;
        deployer = msg.sender;
        registry = _registryRef;
        threshold = _threshold;
        minTransferAmount = _minTransferAmount;
        maxTransferAmount = _maxTransferAmount;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(DEFAULT_ADMIN_ROLE, _timelock);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    // ---------------------------------------------------------------- validators

    function _addValidator(address _v) private {
        require(_v != address(0), "zero validator");
        require(!isValidValidator(_v), "already a validator");
        require(_validators.length < MAX_VALIDATORS, "validator cap");
        _validators.push(_v);
        emit ValidatorAdded(_v);
    }

    function addValidator(address _v) external onlyTimelock {
        _addValidator(_v);
    }

    function isValidValidator(address _v) public view returns (bool) {
        for (uint256 i = 0; i < _validators.length; ++i) {
            if (_validators[i] == _v) return true;
        }
        return false;
    }

    /// Role AND collateral. This is the set `quorumFloor()` is computed from (review M9: v4
    /// counted validators that had been slashed below minStake and therefore cannot sign).
    function isAdmissible(address _v) public view returns (bool) {
        return isValidValidator(_v) && validatorStake[_v] >= minStake;
    }

    function admissibleCount() public view returns (uint256 c) {
        for (uint256 i = 0; i < _validators.length; ++i) {
            if (isAdmissible(_validators[i])) ++c;
        }
    }

    function quorumFloor() public view returns (uint256) {
        return admissibleCount() / 2 + 1;
    }

    function totalStaked() public view returns (uint256 s) {
        for (uint256 i = 0; i < _validators.length; ++i) {
            s += validatorStake[_validators[i]];
        }
    }

    function validatorAt(uint256 _i) external view returns (address) {
        return _validators[_i];
    }

    function validatorCount() external view returns (uint256) {
        return _validators.length;
    }

    /// Anyone may fund a validator's collateral; the credit is the DELTA that arrived, so a
    /// fee-on-transfer token cannot make the contract promise collateral it does not hold (M4).
    function depositStake(address _v, uint256 _amount) external nonReentrant {
        require(_amount > 0, "zero deposit");
        require(address(stakeToken) != address(0), "no stake token");
        require(isValidValidator(_v), "not a validator");
        uint256 before = stakeToken.balanceOf(address(this));
        stakeToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 received = stakeToken.balanceOf(address(this)) - before;
        require(received > 0, "stake did not arrive");
        validatorStake[_v] += received;
        emit StakeDeposited(_v, received, validatorStake[_v]);
    }

    function removeValidator(address _v) external onlyTimelock {
        require(isValidValidator(_v), "not a validator");
        uint256 remaining = _validators.length - 1;
        // v4 compared `remaining` against a floor derived from the FULL set, so it could not
        // see that a slashed validator had already stopped counting (M9). The rule that
        // matters is the one the claim path enforces: after removal there must still be at
        // least `threshold` validators who can sign.
        uint256 admissibleAfter = admissibleCount() - (isAdmissible(_v) ? 1 : 0);
        require(remaining >= threshold && admissibleAfter >= threshold, "would brick the quorum");
        for (uint256 i = 0; i < _validators.length; ++i) {
            if (_validators[i] == _v) {
                _validators[i] = _validators[_validators.length - 1];
                _validators.pop();
                break;
            }
        }
        uint256 stake = validatorStake[_v];
        validatorStake[_v] = 0;
        if (address(stakeToken) != address(0)) {
            if (stake > 0) stakeToken.safeTransfer(timelock, stake);
        }
        emit ValidatorRemoved(_v, stake);
    }

    function slashValidator(address _v, uint256 _amount, string calldata _reason) external onlyTimelock {
        require(isValidValidator(_v), "not a validator");
        require(validatorStake[_v] >= _amount, "insufficient stake");
        validatorStake[_v] -= _amount;
        // Proceeds go to the timelock so they are recoverable, never to an arbitrary caller.
        if (_amount > 0 && address(stakeToken) != address(0)) stakeToken.safeTransfer(timelock, _amount);
        emit ValidatorSlashed(_v, _amount, _reason);
    }

    function setThreshold(uint256 _t) external onlyTimelock {
        require(_t >= 2, "threshold below 2");
        uint256 n = _validators.length;
        require(_t <= n, "threshold above validator count");
        require(_t >= quorumFloor(), "threshold below quorum floor");
        threshold = _t;
        emit ThresholdSet(_t);
    }

    function setLimits(uint256 _min, uint256 _max) external onlyConfigurer {
        require(_min > 0, "min is zero");
        require(_max >= _min, "max below min");
        require(_max <= MAX_TRANSFER_CEILING, "max above ceiling");
        minTransferAmount = _min;
        maxTransferAmount = _max;
        emit LimitsSet(_min, _max);
    }

    // ---------------------------------------------------------------- routing

    function setPeer(uint256 _chainId, address _bridge) external onlyConfigurer {
        require(_chainId != block.chainid, "self chain");
        require(_bridge != address(0), "zero bridge");
        peerBridges[_chainId] = _bridge;
        emit PeerSet(_chainId, _bridge);
    }

    function setOutbound(uint256 _destChainId, address _token, Mode _mode, bool _live) external onlyConfigurer {
        require(_token != address(0), "zero token");
        require(_mode != Mode.None, "no mode");
        require(peerBridges[_destChainId] != address(0), "chain not registered");
        if (_mode == Mode.Burn) {
            // Binding check: only the token whose immutable bridge is THIS contract may be
            // burned by a lock here (M5). Mode.Escrow needs no such binding; it just holds.
            require(IBridgedToken(_token).bridge() == address(this), "token not bound to this bridge");
        }
        outbound[_destChainId][_token] = Outbound({mode: _mode, live: _live});
        emit OutboundSet(_destChainId, _token, _mode, _live);
    }

    function setInbound(uint256 _srcChainId, address _srcToken, address _payToken, Payout _payout, uint256 _cap, bool _live)
        external
        onlyConfigurer
    {
        require(_srcToken != address(0), "zero token");
        require(_payToken != address(0), "zero payout token");
        require(peerBridges[_srcChainId] != address(0), "chain not registered");
        if (_payout == Payout.Mint) {
            require(IBridgedToken(_payToken).bridge() == address(this), "token not bound to this bridge");
        }
        inbound[_srcChainId][_srcToken] = Inbound({payToken: _payToken, payout: _payout, cap: _cap, live: _live});
        emit InboundSet(_srcChainId, _srcToken, _payToken, _payout, _cap, _live);
    }

    /// Closes the pre-launch admin window for good. Idempotent and irrevocable.
    function seal() external onlyConfigurer {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "only admin");
        require(msg.sender != timelock, "timelock cannot seal");
        if (!configSealed) {
            configSealed = true;
            emit Sealed();
        }
        _revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function _markUsed() private {
        if (!everUsed) everUsed = true;
        if (!configSealed) {
            configSealed = true;
            emit Sealed();
        }
    }

    // ---------------------------------------------------------------- hash domain

    function computeClaimId(Request memory _r) public pure returns (bytes32) {
        // Every field of the Request is hashed (review M8: v4 emitted srcBlock but did not hash
        // it, so the attestation committed to no inclusion height).
        return keccak256(abi.encode(_r));
    }

    /// `address(this)` is what makes a bundle non-portable between two bridges on one chain
    /// (C1). `srcBlockHash` is what lets a recipient prove WHICH source block a quorum
    /// committed to. It is a claim argument, not a claimId field: the destination chain cannot
    /// read a source block hash, and the source cannot know its own hash at lock time.
    function claimDigest(bytes32 _claimId, bytes32 _srcBlockHash) public view returns (bytes32) {
        return keccak256(abi.encode(CLAIM_DOMAIN_V41, block.chainid, address(this), _claimId, _srcBlockHash))
            .toEthSignedMessageHash();
    }

    /// A forfeit receipt is signed on the SOURCE chain and bound to the source bridge, because
    /// it authorises paying out of that bridge's escrow.
    function forfeitDigest(bytes32 _claimId) public view returns (bytes32) {
        return keccak256(abi.encode(FORFEIT_DOMAIN_V41, block.chainid, address(this), _claimId))
            .toEthSignedMessageHash();
    }

    /// Two on-chain oracles for the attestor and the collector: they recompute the digest and
    /// recover the signer, so a locally-computed digest that disagrees with the contract is
    /// detected before a signature is published rather than after a claim fails.
    function recoverSigner(bytes32 _digest, bytes calldata _sig) public pure returns (address) {
        return _digest.recover(_sig);
    }

    function attestorOf(bytes32 _claimId, bytes32 _srcBlockHash, bytes calldata _sig)
        public
        view
        returns (address signer, bool admissible)
    {
        signer = claimDigest(_claimId, _srcBlockHash).recover(_sig);
        admissible = isAdmissible(signer);
    }

    function forfeitAttestorOf(bytes32 _claimId, bytes calldata _sig)
        public
        view
        returns (address signer, bool admissible)
    {
        signer = forfeitDigest(_claimId).recover(_sig);
        admissible = isAdmissible(signer);
    }

    function verifyBundle(bytes32 _claimId, bytes32 _srcBlockHash, bytes[] calldata _sigs) public view {
        bytes32 digest = claimDigest(_claimId, _srcBlockHash);
        uint256 len = _sigs.length;
        require(len >= threshold, "below threshold");
        require(len >= quorumFloor(), "below quorum floor");
        address previous = address(0);
        for (uint256 i = 0; i < len; ++i) {
            (address signer, ECDSA.RecoverError err,) = digest.tryRecover(_sigs[i]);
            require(err == ECDSA.RecoverError.NoError && signer != address(0), "invalid signature");
            // Strictly ascending: two slots can never be occupied by the same validator, and
            // the ordering is what lets the collector and the attestor produce a canonical bundle.
            require(signer > previous, "signers not ascending");
            require(isAdmissible(signer), "signer not an admissible validator");
            previous = signer;
        }
    }

    // ---------------------------------------------------------------- lock

    function lockTransfer(
        address _token,
        uint256 _amount,
        uint256 _destChainId,
        address _recipient
    ) external nonReentrant whenNotPaused returns (bytes32) {
        require(_token != address(0), "token is zero");
        require(_recipient != address(0), "recipient is zero");
        require(_recipient != address(this), "recipient is bridge");
        require(_amount > 0, "amount must be > 0");
        address peer = peerBridges[_destChainId];
        require(peer != address(0), "chain not registered");
        Outbound memory route = outbound[_destChainId][_token];
        require(route.live, "no outbound route");   // C2/M12: an unroutable lock cannot be made
        require(_amount <= maxTransferAmount, "amount exceeds bridge limit");
        require(_amount >= minTransferAmount, "amount below bridge minimum");

        uint256 received = _amount;
        if (route.mode == Mode.Burn) {
            IBridgedToken(_token).burn(msg.sender, _amount);
        } else {
            uint256 before = IERC20(_token).balanceOf(address(this));
            IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
            // The ledger records what ARRIVED, not what was asked for (M4): a taxed token can
            // never make escrow understate the amount the destination is told to credit.
            received = IERC20(_token).balanceOf(address(this)) - before;
            require(received >= minTransferAmount, "received below bridge minimum");
            escrowed[_token] += received;
        }
        require(received > 0, "nothing arrived");

        _markUsed();
        uint256 nonce = laneNonce[_destChainId][_token] + 1;
        uint256 total = totalSentFor[_destChainId][_token] + received;
        laneNonce[_destChainId][_token] = nonce;
        totalSentFor[_destChainId][_token] = total;

        Request memory r = Request({
            srcChainId: block.chainid,
            srcBridge: address(this),
            destBridge: peer,
            destChainId: _destChainId,
            laneNonce: nonce,
            srcTotalSent: total,
            srcToken: _token,
            amount: received,
            sender: msg.sender,
            recipient: _recipient,
            srcBlock: block.number
        });
        bytes32 id = computeClaimId(r);
        lockStatus[id] = LockStatus.Escrowed;
        if (route.mode == Mode.Burn) lockStatus[id] = LockStatus.Burned;
        emit TransferLocked(id, r, received);
        return id;
    }

    // ---------------------------------------------------------------- claim

    function _validatedInbound(Request calldata _r) private view returns (bytes32 id, Inbound memory route) {
        require(_r.destChainId == block.chainid, "wrong destination chain");
        require(_r.destBridge == address(this), "wrong destination bridge");
        require(_r.srcChainId != block.chainid, "self claim");
        require(_r.srcBridge == peerBridges[_r.srcChainId], "chain not registered");
        require(_r.srcBridge != address(0), "chain not registered");
        require(_r.amount > 0, "amount must be > 0");
        require(_r.recipient != address(0), "recipient is zero");
        require(_r.recipient != address(this), "recipient is bridge");
        require(_r.sender != address(0), "sender is zero");
        require(_r.laneNonce > 0, "bad lane nonce");
        route = inbound[_r.srcChainId][_r.srcToken];
        require(route.live && route.payout != Payout.None, "no inbound route");
        id = computeClaimId(_r);
        require(claimStatus[id] == ClaimStatus.None, "already claimed");
    }

    // ============================================================ DELTA-C6-3: the binding
    //
    // v4.1's verifyBundle (reference:385-400) checks each recovered signer in
    // isolation and returns nothing. C6 needs the SET, because the property the
    // recorded bundle buys is that the MAYO layer comes from the same threshold
    // validators whose secp256k1 signatures recovered in this same call. Nothing
    // here does post-quantum math: it is a handful of SLOADs and calldata reads.
    // v4.1's own function is not modified -- this is a new internal that returns,
    // and the two share the guard text deliberately (the public one is what the
    // stuck-lane path calls; divergence between them is Task 10's problem).

    function _verifyBundleReturning(bytes32 _claimId, bytes32 _srcBlockHash, bytes[] calldata _sigs)
        internal view returns (address[] memory recovered)
    {
        bytes32 digest = claimDigest(_claimId, _srcBlockHash);
        uint256 len = _sigs.length;
        require(len >= threshold, "below threshold");
        require(len >= quorumFloor(), "below quorum floor");
        recovered = new address[](len);
        address previous = address(0);
        for (uint256 i = 0; i < len; ++i) {
            (address signer, ECDSA.RecoverError err,) = digest.tryRecover(_sigs[i]);
            require(err == ECDSA.RecoverError.NoError && signer != address(0), "invalid signature");
            // Strictly ascending: two slots can never be occupied by the same validator.
            require(signer > previous, "signers not ascending");
            require(isAdmissible(signer), "signer not an admissible validator");
            recovered[i] = signer;
            previous = signer;
        }
    }

    /// Same parties: every declared roster index must resolve, through the registry's
    /// index->validator direction, to one of the signers that just recovered. A bundle
    /// attesting a DIFFERENT validator set is refused here -- and under the 32-byte
    /// commitment design there was nothing to look at, so it was not merely uncheckable
    /// but invisible. Memory, not calldata: the indices arrive from a decoded struct, and
    /// there is exactly one implementation of this check (two copies is how one stops
    /// being called).
    function _requireBundleBoundToSigners(uint8[] memory _indices, address[] memory _recovered)
        internal view
    {
        require(_indices.length == threshold, "bundle index count below threshold");
        // Discovered while writing Task 6's own case for duplicates: resolving each index to
        // "is this address among the recovered signers" PASSES on {0,0} when index 0 signed --
        // one validator credited for the whole quorum, which is the property inverted by a
        // different hole than §10 item 21. So the set must match the recovered set exactly.
        require(_recovered.length == _indices.length, "bundle must attest every recovered signer");
        for (uint256 i = 0; i < _indices.length; ++i) {
            for (uint256 k = 0; k < i; ++k) {
                require(_indices[k] != _indices[i], "bundle indices contain a duplicate");
            }
            address v = IPqcRegistry(registry).rosterValidator(_indices[i]);
            require(v != address(0), "bundle index not a roster entry");
            bool found = false;
            for (uint256 j = 0; j < _recovered.length && !found; ++j) {
                found = _recovered[j] == v;
            }
            require(found, "bundle indices not the recovered signers");
        }
    }

    // ============================================================ DELTA-C6-1: the bundle
    //
    // v4.1's claimTransfer(_r, srcBlockHash, sigs) becomes
    // claimTransfer(_r, srcBlockHash, sigs, mldsaSigs, bundle). The MAYO bundle is
    // RECORDED rather than hashed-and-dropped, which is what makes §6.1's two
    // properties stand: anyone can read the bytes and run verifyBatch against the
    // registered keys, and the contract can check that the bundle is about THIS
    // claim and attributed to THESE validators — both equality checks against values
    // it already holds, so neither costs a signature operation. It never checks that
    // a MAYO signature is valid, and cannot (938,752,492 gas, spec §1.2/§6.2).
    //
    // The three-argument form is DELETED, not kept alongside: this is a copy of the
    // implementation, not a fork of the interface, and two entry points with different
    // security properties is how a runbook sends a claim that records nothing.

    struct Bundle {
        bytes32 claimId;
        bytes32 srcBlockHash;
        uint8[] rosterIndices;   // length == threshold, i.e. 2 on the live bridge
        bytes[] mayoSigs;        // 186 B each at MAYO-C commit 4108b71d (T2 row 23), never 239
    }

    bytes32 public constant MAYO_CLAIM_DOMAIN_V1  = keccak256("LXON_PQC_MAYO_CLAIM_V1");
    bytes32 public constant MLDSA_CLAIM_DOMAIN_V1 = keccak256("LXON_PQC_MLDSA_CLAIM_V1");

    mapping(bytes32 => bytes32) public pqcCommitment;

    event PqcBundleRecorded(bytes32 indexed claimId, bytes32 bundleHash, uint8 verifyMode);
    event BundleBindingChecked(bytes32 indexed claimId, uint8[] indices);

    // ============================================================ DELTA-C6-4: the mode
    //
    // One source of truth, read once, at the top of the claim. Task 5 left a `pqcMode` field and a
    // `setPqcMode` setter here with a comment saying they had to go when the registry read landed;
    // they are deleted, not kept as a cache, because a mode the claim path does not consult is the
    // same defect class as a stored authorising bit (spec C4) — it looks like state, it drifts, and
    // a runbook that sets it believes it changed something.

    /// The row Strong consults, mirrored from the registry's constant of the same name.
    /// PqcBridgeModeTest asserts the two are equal; a divergent mirror would read a row nobody
    /// registered, which makes Strong unfalsifiable rather than strong.
    bytes32 public constant MLDSA44_ID = keccak256("mldsa44");

    /// THE registry read. Public so a watcher (and the test) can ask the same question the claim
    /// asked, in the same block.
    function readMode() public view returns (uint256) {
        return IPqcRegistry(registry).verifyMode();
    }

    /// One guarded call. address.call returns (bool, bytes) and a `false` there is silent by
    /// default, so the success bit alone is not enough: empty or unparsable return data is FALSE,
    /// not success. Spec §7 calls this the single most likely way to turn a mis-wired verifier
    /// into an accept-everything verifier, and it is the reason this is a helper rather than three
    /// inline calls. staticcall, not call: a verifier that could write storage could also arrange
    /// to be called again.
    function _guardedVerify(address verifier, address pkBlob, bytes memory message, bytes calldata signature)
        private view returns (bool)
    {
        (bool ok, bytes memory data) =
            verifier.staticcall(abi.encodeCall(IMldsaVerifier.verify, (pkBlob, message, signature)));
        if (!ok) return false;
        if (data.length < 32) return false;
        return abi.decode(data, (bool));
    }

    /// Strong profile only. Each lattice signature is checked against the blob registered for the
    /// validator whose ECDSA signature also recovered in THIS call — so the lattice set and the
    /// secp256k1 set are the same parties by construction, and a claim cannot be authorised by a
    /// set that did not sign. Any failure reverts the whole claim; there is no path in which an
    /// authorising scheme is skipped and the money still moves.
    function _verifyLattice(bytes32 id, bytes32 bh, bytes[] calldata _mldsaSigs, address[] memory _recovered)
        private view
    {
        uint256 packed = IPqcRegistry(registry).readScheme(MLDSA44_ID);
        (bool present, bool enabled,, bool authorising,) = PqcSchemeWord.unpack(packed);
        require(present && enabled, "mldsa44 row unavailable");
        require(authorising, "registry mode says this row is not authorising");
        address verifier = IPqcRegistry(registry).readVerifier(MLDSA44_ID);
        require(verifier != address(0), "strong mode without a verifier");   // never settle instead
        bytes memory message = abi.encodePacked(mldsaDigest(id, bh));
        for (uint256 i = 0; i < _recovered.length; ++i) {
            int256 idx = IPqcRegistry(registry).rosterIndexOf(_recovered[i]);
            require(idx >= 0, "signer not rostered");
            address blob = IMldsaKeyStore(registry).mldsaBlobFor(uint8(uint256(idx)));
            // A zero blob is not "a key nobody registered" but "the verifier will be handed
            // address(0)": empty code, an empty return, and with a weaker guard than this one a
            // claim that paid. Refused by name, at the signer it applies to.
            require(blob != address(0), "lattice blob not registered for signer");
            require(_guardedVerify(verifier, blob, message, _mldsaSigs[i]), "lattice verification failed");
        }
    }

    /// The one form this contract accepts, and the one a watcher can recompute.
    /// The four fields flat — NOT the struct wrapped — because a dynamic
    /// top-level argument adds an offset head and gives one bundle two hashes
    /// (spec §10 item 21), and a commitment with two values is a commitment to
    /// neither.
    function canonicalBundle(Bundle calldata b) public pure returns (bytes memory) {
        return abi.encode(b.claimId, b.srcBlockHash, b.rosterIndices, b.mayoSigs);
    }

    error BundleNotCanonical();

    /// The only encoding claimTransfer will read a Bundle from: the four fields flat.
    /// External because abi.decode cannot be caught any other way, and so the caller sees a
    /// named refusal instead of the decoder's bare revert. One extra dispatcher entry buys
    /// that; measured at 21,753 B of runtime with 2,823 B of EIP-170 headroom before this
    /// wrapper was folded back in, which is why there is exactly one such function here.
    function decodeBundleFlat(bytes calldata _bundle)
        external pure
        returns (bytes32 claimId, bytes32 srcBlockHash, uint8[] memory rosterIndices, bytes[] memory mayoSigs)
    {
        (claimId, srcBlockHash, rosterIndices, mayoSigs) =
            abi.decode(_bundle, (bytes32, bytes32, uint8[], bytes[]));
    }

    /// The MAYO digest. Deliberately WITHOUT toEthSignedMessageHash(): that EIP-191
    /// prefix exists for ecrecover compatibility and means nothing to a multivariate
    /// scheme. Distinct from CLAIM_DOMAIN_V41 and from MLDSA_CLAIM_DOMAIN_V1 so no
    /// signature is ever interchangeable between the three families (T3's negatives).
    function mayoDigest(bytes32 _claimId, bytes32 _srcBlockHash) public view returns (bytes32) {
        return keccak256(abi.encode(MAYO_CLAIM_DOMAIN_V1, block.chainid, address(this), _claimId, _srcBlockHash));
    }

    function mldsaDigest(bytes32 _claimId, bytes32 _srcBlockHash) public view returns (bytes32) {
        return keccak256(abi.encode(MLDSA_CLAIM_DOMAIN_V1, block.chainid, address(this), _claimId, _srcBlockHash));
    }

    function claimTransfer(
        Request calldata _r,
        bytes32 _srcBlockHash,
        bytes[] calldata _sigs,
        bytes[] calldata _mldsaSigs,
        bytes calldata _bundle
    ) external nonReentrant whenNotPaused {
        (bytes32 id, Inbound memory route) = _validatedInbound(_r);

        // DELTA-C6-4 (Task 7): THE one registry read, at the top, replacing Task 5's field read.
        uint256 mode = readMode();
        // An unrecognised word is not "the other branch". Refusing it here costs nothing and is the
        // only thing standing between a registry upgrade and a claim settled under a guessed
        // profile; PqcBridgeRegistryLieTest feeds it, because the real registry cannot.
        require(mode <= 1, "unknown verify mode");

        address[] memory recovered = _verifyBundleReturning(id, _srcBlockHash, _sigs);

        if (mode == 0) {
            require(_mldsaSigs.length == 0, "default profile takes no lattice signatures");
        } else {
            require(_mldsaSigs.length == threshold, "strong profile needs one per quorum member");
            _verifyLattice(id, _srcBlockHash, _mldsaSigs, recovered);
        }

        // DELTA-C6-1: decode, canonicalize, pin, bind, record.
        //
        // The decode target is the four fields FLAT, not `(Bundle)`. A struct that holds
        // dynamic members is itself a dynamic type, so `(Bundle)` expects the offset-head
        // form -- the 800-byte one §10 item 21 exists to refuse. Measured 2026-11-13: with
        // `(Bundle)` as the target, the canonical 768-byte bundle died inside the decoder
        // with a bare revert (no data, no message), and the struct-wrapped bundle was the
        // only input that decoded at all. In other words the delta as drafted accepted the
        // malleable form and rejected the canonical one, and nothing noticed until a claim
        // actually tried to settle.
        bytes32 bid_; bytes32 bhash_; uint8[] memory idx_; bytes[] memory msigs_;
        try this.decodeBundleFlat(_bundle) returns (
            bytes32 a, bytes32 b2, uint8[] memory c, bytes[] memory d)
        {
            (bid_, bhash_, idx_, msigs_) = (a, b2, c, d);
        } catch {
            revert BundleNotCanonical();
        }
        Bundle memory b = Bundle({
            claimId: bid_, srcBlockHash: bhash_, rosterIndices: idx_, mayoSigs: msigs_
        });
        bytes memory canonical = abi.encode(b.claimId, b.srcBlockHash, b.rosterIndices, b.mayoSigs);
        require(canonical.length == _bundle.length && keccak256(canonical) == keccak256(_bundle),
            "bundle not canonical");
        require(b.claimId == id, "bundle is not this claim");
        require(b.srcBlockHash == _srcBlockHash, "bundle is not this block");
        require(b.rosterIndices.length == threshold, "bundle size does not match threshold");
        require(b.mayoSigs.length == threshold, "bundle signatures do not match threshold");

        // DELTA-C6-3: the recorded bundle must attest THIS quorum, and it is checked
        // before any state write so a refused bundle leaves nothing behind.
        _requireBundleBoundToSigners(b.rosterIndices, recovered);
        emit BundleBindingChecked(id, b.rosterIndices);

        // Gapless and EXACT (M11/M17: `==` mutated to `>=` survived every v4 test, and `>=`
        // lets a quorum mint against a total below the credit). PqcBridgeBase's over-pay case
        // is what makes that comment true here rather than inherited.
        require(totalReceivedFrom[_r.srcChainId][_r.srcToken] + _r.amount == _r.srcTotalSent, "total mismatch");

        _markUsed();
        claimStatus[id] = ClaimStatus.Completed;
        blockHashAttested[id] = _srcBlockHash;
        totalReceivedFrom[_r.srcChainId][_r.srcToken] += _r.amount;
        // One hash, used twice. The canonical require above already proved this equals
        // keccak256(_bundle), which is the whole point of that check: the value stored here is the
        // value a watcher recomputes from the calldata they already have.
        bytes32 bundleHash = keccak256(canonical);
        pqcCommitment[id] = bundleHash;
        // mode is uint256 because that is what the registry's ABI word is; the event carries the
        // profile it authorises, and the require(mode <= 1) at the top is what makes this safe
        // downcast a narrowing that cannot lose information rather than a hope.
        emit PqcBundleRecorded(id, bundleHash, uint8(mode));

        if (route.payout == Payout.Mint) {
            require(
                IBridgedToken(route.payToken).totalSupply() + _r.amount <= route.cap,
                "mint cap exceeded"
            );
            IBridgedToken(route.payToken).mint(_r.recipient, _r.amount);
        } else {
            uint256 inEscrow = escrowed[route.payToken];
            require(inEscrow >= _r.amount, "escrow short");
            escrowed[route.payToken] = inEscrow - _r.amount;
            uint256 before = IERC20(route.payToken).balanceOf(_r.recipient);
            IERC20(route.payToken).safeTransfer(_r.recipient, _r.amount);
            // A payout that silently delivers less would leave the ledger ahead of reality --
            // exactly `testPoC_PayoutFeeUnderDeliversButCountsInFull`. It reverts instead, and
            // the claim then goes through the flagStuck/forfeit/refund path.
            require(IERC20(route.payToken).balanceOf(_r.recipient) - before == _r.amount, "payout short");
        }
        emit ClaimCompleted(id, _r.recipient, route.payToken, _r.amount);
    }

    // ---------------------------------------------------------------- stuck claims

    /// Anyone can mark the HEAD of a lane as stuck -- the person who is blocked is the person
    /// who knows. Signatures are checked here so a forged request cannot occupy the queue; the
    /// 72h window is what stops a griefer from pushing a legitimate claim into the slow path,
    /// because the recipient can still `claimTransfer` during it.
    function flagStuck(Request calldata _r, bytes32 _srcBlockHash, bytes[] calldata _sigs) external {
        (bytes32 id,) = _validatedInbound(_r);
        require(totalReceivedFrom[_r.srcChainId][_r.srcToken] + _r.amount == _r.srcTotalSent, "not queue head");
        verifyBundle(id, _srcBlockHash, _sigs);
        require(stuckSince[id] == 0, "already flagged");
        stuckSince[id] = block.timestamp;
        emit ClaimFlaggedStuck(id, msg.sender, block.timestamp);
    }

    function forfeitClaim(Request calldata _r) external whenNotPaused {
        (bytes32 id,) = _validatedInbound(_r);
        uint256 at = stuckSince[id];
        require(at != 0, "not flagged");
        require(block.timestamp >= at + FORFEIT_DELAY, "forfeit window open");
        require(totalReceivedFrom[_r.srcChainId][_r.srcToken] + _r.amount == _r.srcTotalSent, "not queue head");
        claimStatus[id] = ClaimStatus.Failed;
        totalReceivedFrom[_r.srcChainId][_r.srcToken] += _r.amount;
        emit ClaimForfeited(id, _r.amount, block.timestamp);
    }

    /// The source side of a forfeited claim: the escrow (or the representation that was burned)
    /// is returned to the original sender, but only with a fresh quorum attesting the
    /// destination's `Failed` status, and only through the 48h timelock -- two independent gates
    /// in front of money leaving escrow (C2/M12). The 72h window itself lives on the destination
    /// (`stuckSince` there); this chain's evidence is the bundle, which is bound to
    /// `block.chainid` and `address(this)` so it cannot be lifted from a claim bundle.
    function refundForfeited(Request calldata _r, bytes[] calldata _sigs) external onlyTimelock nonReentrant {
        require(_r.srcChainId == block.chainid, "wrong source chain");
        require(_r.srcBridge == address(this), "wrong source bridge");
        bytes32 id = computeClaimId(_r);
        LockStatus ls = lockStatus[id];
        require(ls == LockStatus.Escrowed || ls == LockStatus.Burned, "not locked here");
        verifyForfeitBundle(id, _sigs);
        lockStatus[id] = LockStatus.Refunded;
        if (ls == LockStatus.Escrowed) {
            require(escrowed[_r.srcToken] >= _r.amount, "escrow short");
            escrowed[_r.srcToken] -= _r.amount;
            IERC20(_r.srcToken).safeTransfer(_r.sender, _r.amount);
        } else {
            IBridgedToken(_r.srcToken).mint(_r.sender, _r.amount);
        }
        emit LockRefunded(id, _r.sender, _r.srcToken, _r.amount);
    }

    function verifyForfeitBundle(bytes32 _claimId, bytes[] calldata _sigs) public view {
        bytes32 digest = forfeitDigest(_claimId);
        uint256 len = _sigs.length;
        require(len >= threshold, "below threshold");
        require(len >= quorumFloor(), "below quorum floor");
        address previous = address(0);
        for (uint256 i = 0; i < len; ++i) {
            (address signer, ECDSA.RecoverError err,) = digest.tryRecover(_sigs[i]);
            require(err == ECDSA.RecoverError.NoError && signer != address(0), "invalid signature");
            require(signer > previous, "signers not ascending");
            require(isAdmissible(signer), "signer not an admissible validator");
            previous = signer;
        }
    }

    // ---------------------------------------------------------------- recovery

    /// Anything that is not backing an outstanding lock or a validator's collateral is
    /// reachable again -- v4 had no recovery path at all (M12).
    function rescueToken(address _token, address _to, uint256 _amount) external onlyTimelock nonReentrant {
        require(_token != address(0) && _to != address(0), "zero address");
        uint256 reserve = escrowed[_token];
        if (_token == address(stakeToken)) reserve += totalStaked();
        uint256 held = IERC20(_token).balanceOf(address(this));
        require(held >= reserve + _amount, "would dip below escrow or stake");
        IERC20(_token).safeTransfer(_to, _amount);
        emit TokenRescued(_token, _to, _amount);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
}

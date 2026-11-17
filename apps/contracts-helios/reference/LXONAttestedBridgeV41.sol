// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

interface IBridgedToken {
    function bridge() external view returns (address);
    function totalSupply() external view returns (uint256);
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
}

/**
 * LXONAttestedBridge v4.1.
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
contract LXONAttestedBridgeV41 is AccessControl, Pausable, ReentrancyGuard {
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
        uint256 _maxTransferAmount
    ) {
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

    function claimTransfer(Request calldata _r, bytes32 _srcBlockHash, bytes[] calldata _sigs)
        external
        nonReentrant
        whenNotPaused
    {
        (bytes32 id, Inbound memory route) = _validatedInbound(_r);
        verifyBundle(id, _srcBlockHash, _sigs);

        // Gapless and EXACT (M11/M17: `==` mutated to `>=` survived every v4 test, and `>=`
        // lets a quorum mint against a total below the credit).
        require(totalReceivedFrom[_r.srcChainId][_r.srcToken] + _r.amount == _r.srcTotalSent, "total mismatch");

        _markUsed();
        claimStatus[id] = ClaimStatus.Completed;
        blockHashAttested[id] = _srcBlockHash;
        totalReceivedFrom[_r.srcChainId][_r.srcToken] += _r.amount;

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

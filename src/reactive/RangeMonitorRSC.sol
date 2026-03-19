// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "reactive-lib/interfaces/IReactive.sol";
import "reactive-lib/abstract-base/AbstractPausableReactive.sol";

/// @title RangeMonitorRSC
/// @notice Reactive Smart Contract deployed on the Reactive Network (Lasna testnet).
///         Monitors StableStreamHook events on Unichain Sepolia and autonomously
///         triggers yield routing / JIT recall callbacks.
///
/// @dev    Deployment chain: Reactive Network Lasna (chain ID 5318007)
///         Origin chain:     Unichain Sepolia (chain ID 1301)
///         Destination:      Unichain Sepolia (chain ID 1301)
///
///         Subscribed events
///         ─────────────────
///         1. PositionLeftRange(bytes32 positionId, int24 newTick)
///            → Calls routeToYield(positionId) on StableStreamHook
///
///         2. PositionEnteredRange(bytes32 positionId, int24 currentTick)
///            → Calls recallFromYield(positionId) on StableStreamHook
///
///         3. CapitalRouted(bytes32 positionId, address yieldSource, uint256 amount)
///            → Observational only — no callback
///
///         Gas safety
///         ──────────
///         routeToYield callbacks are rate-limited per position (POSITION_COOLDOWN_BLOCKS)
///         and capped per block (MAX_CALLBACKS_PER_BLOCK). Overflow is queued for later
///         processing via flushQueue(). recallFromYield (JIT recall) bypasses the cap
///         because capital must be back in the pool before the next swap.
///
/// @custom:integration Reactive Network — https://dev.reactive.network/
contract RangeMonitorRSC is IReactive, AbstractPausableReactive {

    // -------------------------------------------------------------------------
    // Event topic hashes
    // -------------------------------------------------------------------------

    /// @dev keccak256("PositionLeftRange(bytes32,int24)")
    uint256 private constant TOPIC_POSITION_LEFT_RANGE =
        uint256(keccak256("PositionLeftRange(bytes32,int24)"));

    /// @dev keccak256("PositionEnteredRange(bytes32,int24)")
    uint256 private constant TOPIC_POSITION_ENTERED_RANGE =
        uint256(keccak256("PositionEnteredRange(bytes32,int24)"));

    /// @dev keccak256("CapitalRouted(bytes32,address,uint256)")
    uint256 private constant TOPIC_CAPITAL_ROUTED =
        uint256(keccak256("CapitalRouted(bytes32,address,uint256)"));

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @notice Gas limit forwarded to StableStreamHook callbacks on Unichain Sepolia.
    uint64 public constant CALLBACK_GAS_LIMIT = 300_000;

    // -------------------------------------------------------------------------
    // Configurable rate limits (owner-settable via the Reactive Network)
    // -------------------------------------------------------------------------

    /// @notice Maximum routing callbacks emitted per origin-chain block.
    ///         Default: 5. Increase to handle higher throughput; decrease to protect
    ///         destination-chain gas budget during congestion.
    uint256 public maxCallbacksPerBlock = 5;

    /// @notice Minimum blocks between routing the same position.
    ///         Unichain Sepolia has ~1-second blocks, so 60 blocks ≈ 60 seconds.
    ///         Set lower for faster re-routing; higher to reduce callback frequency.
    uint256 public positionCooldownBlocks = 60;

    // -------------------------------------------------------------------------
    // Immutables
    // -------------------------------------------------------------------------

    /// @notice Chain ID to monitor (Unichain Sepolia = 1301)
    uint256 public immutable ORIGIN_CHAIN_ID;

    /// @notice StableStreamHook address on the origin chain
    address public immutable HOOK_ADDRESS;

    /// @notice Destination chain for callbacks (Unichain Sepolia = 1301)
    uint256 public immutable DESTINATION_CHAIN_ID;

    // -------------------------------------------------------------------------
    // Mutable state
    // -------------------------------------------------------------------------

    /// @dev Origin-chain block in which the last routing callback was emitted
    uint256 private _lastCallbackBlock;

    /// @dev Number of routing callbacks emitted in _lastCallbackBlock
    uint256 private _callbacksThisBlock;

    /// @dev Per-position last-routed block (for per-position cooldown)
    mapping(bytes32 => uint256) private _lastRouted;

    /// @dev Overflow queue — positions awaiting routing after a full block
    bytes32[] private _pendingQueue;

    // -------------------------------------------------------------------------
    // Events (emitted on Reactive Chain)
    // -------------------------------------------------------------------------

    event ReactTriggered(bytes32 indexed positionId, string action, uint256 originBlock);
    event PositionQueued(bytes32 indexed positionId, uint256 queueLength);
    event QueueFlushed(uint256 processed);
    event MaxCallbacksPerBlockUpdated(uint256 oldValue, uint256 newValue);
    event PositionCooldownBlocksUpdated(uint256 oldValue, uint256 newValue);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @notice Deploy RSC and subscribe to StableStreamHook events.
    /// @param  hookAddress   StableStreamHook on Unichain Sepolia
    /// @param  originChainId Chain ID to monitor (1301 for Unichain Sepolia)
    /// @param  destChainId   Destination chain ID for callbacks (1301)
    constructor(
        address hookAddress,
        uint256 originChainId,
        uint256 destChainId
    ) payable {
        HOOK_ADDRESS = hookAddress;
        ORIGIN_CHAIN_ID = originChainId;
        DESTINATION_CHAIN_ID = destChainId;

        // Subscribe only when deployed to the Reactive Network (not in simulation)
        if (!vm) {
            service.subscribe(originChainId, hookAddress, TOPIC_POSITION_LEFT_RANGE,   REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
            service.subscribe(originChainId, hookAddress, TOPIC_POSITION_ENTERED_RANGE, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
            service.subscribe(originChainId, hookAddress, TOPIC_CAPITAL_ROUTED,         REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
        }
    }

    // -------------------------------------------------------------------------
    // IReactive — main entrypoint
    // -------------------------------------------------------------------------

    /// @notice Called by Reactive Network nodes when a subscribed event fires.
    /// @dev    MUST NOT revert — a revert causes the node to retry indefinitely.
    function react(LogRecord calldata log) external vmOnly {
        if (log.chain_id != ORIGIN_CHAIN_ID) return;
        if (log._contract != HOOK_ADDRESS) return;
        if (paused) return;

        uint256 eventSig = log.topic_0;

        if (eventSig == TOPIC_POSITION_LEFT_RANGE) {
            _handlePositionLeftRange(log.topic_1, log.block_number);
        } else if (eventSig == TOPIC_POSITION_ENTERED_RANGE) {
            _handlePositionEnteredRange(log.topic_1, log.block_number);
        }
        // CapitalRouted is observational — no callback
    }

    // -------------------------------------------------------------------------
    // AbstractPausableReactive — pause/resume subscription list
    // -------------------------------------------------------------------------

    function getPausableSubscriptions()
        internal
        view
        override
        returns (Subscription[] memory)
    {
        Subscription[] memory subs = new Subscription[](3);
        subs[0] = Subscription(ORIGIN_CHAIN_ID, HOOK_ADDRESS, TOPIC_POSITION_LEFT_RANGE,    REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
        subs[1] = Subscription(ORIGIN_CHAIN_ID, HOOK_ADDRESS, TOPIC_POSITION_ENTERED_RANGE, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
        subs[2] = Subscription(ORIGIN_CHAIN_ID, HOOK_ADDRESS, TOPIC_CAPITAL_ROUTED,          REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
        return subs;
    }

    // -------------------------------------------------------------------------
    // Internal react handlers
    // -------------------------------------------------------------------------

    /// @dev Handle PositionLeftRange — emit routeToYield callback with rate-limiting.
    function _handlePositionLeftRange(uint256 topic1, uint256 blockNumber) internal {
        bytes32 positionId = bytes32(topic1);
        emit ReactTriggered(positionId, "routeToYield", blockNumber);

        // Per-position cooldown
        if (blockNumber < _lastRouted[positionId] + positionCooldownBlocks) return;

        // Block-level counter reset
        if (blockNumber > _lastCallbackBlock) {
            _lastCallbackBlock = blockNumber;
            _callbacksThisBlock = 0;
        }

        if (_callbacksThisBlock >= maxCallbacksPerBlock) {
            _pendingQueue.push(positionId);
            emit PositionQueued(positionId, _pendingQueue.length);
            return;
        }

        _emitRouteToYield(positionId);
        _lastRouted[positionId] = blockNumber;
        _callbacksThisBlock++;
    }

    /// @dev Handle PositionEnteredRange — JIT recall, bypasses rate limits.
    function _handlePositionEnteredRange(uint256 topic1, uint256 blockNumber) internal {
        bytes32 positionId = bytes32(topic1);
        emit ReactTriggered(positionId, "recallFromYield", blockNumber);
        _emitRecallFromYield(positionId);
        _lastRouted[positionId] = blockNumber;
    }

    // -------------------------------------------------------------------------
    // Callback helpers — emit Reactive Network Callback events
    // -------------------------------------------------------------------------

    function _emitRouteToYield(bytes32 positionId) internal {
        bytes memory payload = abi.encodeWithSignature("routeToYield(bytes32)", positionId);
        emit Callback(DESTINATION_CHAIN_ID, HOOK_ADDRESS, CALLBACK_GAS_LIMIT, payload);
    }

    function _emitRecallFromYield(bytes32 positionId) internal {
        bytes memory payload = abi.encodeWithSignature("recallFromYield(bytes32)", positionId);
        emit Callback(DESTINATION_CHAIN_ID, HOOK_ADDRESS, CALLBACK_GAS_LIMIT, payload);
    }

    // -------------------------------------------------------------------------
    // Queue management — permissionless maintenance
    // -------------------------------------------------------------------------

    /// @notice Flush up to `maxCount` queued positions by emitting their routing callbacks.
    ///         Anyone can call this to drain the overflow queue after a congested block.
    function flushQueue(uint256 maxCount) external {
        require(!paused, "Paused");
        uint256 len = _pendingQueue.length;
        if (len == 0) return;

        uint256 toProcess = maxCount < len ? maxCount : len;
        for (uint256 i = 0; i < toProcess; ) {
            _emitRouteToYield(_pendingQueue[len - 1 - i]);
            unchecked { ++i; }
        }

        uint256 remaining = len - toProcess;
        assembly { sstore(_pendingQueue.slot, remaining) }

        emit QueueFlushed(toProcess);
    }

    /// @notice Returns all positions currently in the overflow queue.
    function pendingQueue() external view returns (bytes32[] memory) {
        return _pendingQueue;
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    /// @notice Set the maximum number of routing callbacks emitted per origin-chain block.
    /// @dev    Callable only on the Reactive Network (not inside the RVM).
    ///         Use to tune throughput vs destination-chain gas budget.
    function setMaxCallbacksPerBlock(uint256 newMax) external rnOnly onlyOwner {
        require(newMax > 0, "Must be > 0");
        emit MaxCallbacksPerBlockUpdated(maxCallbacksPerBlock, newMax);
        maxCallbacksPerBlock = newMax;
    }

    /// @notice Set the minimum blocks between routing the same position.
    /// @dev    Callable only on the Reactive Network (not inside the RVM).
    ///         Set lower for faster re-routing; higher to reduce callback frequency.
    function setPositionCooldownBlocks(uint256 newCooldown) external rnOnly onlyOwner {
        emit PositionCooldownBlocksUpdated(positionCooldownBlocks, newCooldown);
        positionCooldownBlocks = newCooldown;
    }

    /// @notice Transfer RSC ownership to a new address.
    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    /// @notice Withdraw any ETH balance (e.g. leftover from payable constructor).
    function withdrawEth() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }
}

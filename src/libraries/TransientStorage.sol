// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title TransientStorage
/// @notice Gas-efficient transient storage helpers using EIP-1153 TSTORE/TLOAD.
///
/// @dev    Transient storage is cleared at the end of every transaction, making it
///         ideal for within-transaction flags (e.g., reentrancy guards, JIT recall
///         deduplication within a single block of hook callbacks).
///
///         Gas savings vs. cold SSTORE/SLOAD:
///           SSTORE (cold) ≈ 22,100 gas  →  TSTORE ≈ 100 gas  (−22,000 gas per write)
///           SLOAD  (cold) ≈  2,100 gas  →  TLOAD  ≈ 100 gas  (− 2,000 gas per read)
///
///         Requires `evm_version = "cancun"` in foundry.toml (EIP-1153 activated on
///         Cancun / Dencun hardfork, January 2024).
///
/// @custom:eip EIP-1153 https://eips.ethereum.org/EIPS/eip-1153
library TransientStorage {
    // -------------------------------------------------------------------------
    // Bool helpers
    // -------------------------------------------------------------------------

    /// @notice Write a bool to transient storage at the given slot.
    /// @param slot   32-byte storage slot key
    /// @param value  Value to write (true = 1, false = 0)
    function tstore(bytes32 slot, bool value) internal {
        assembly {
            tstore(slot, value)
        }
    }

    /// @notice Read a bool from transient storage.
    /// @param slot   32-byte storage slot key
    /// @return value  Stored value (false if slot was never written in this tx)
    function tload(bytes32 slot) internal view returns (bool value) {
        assembly {
            value := tload(slot)
        }
    }

    // -------------------------------------------------------------------------
    // Uint256 helpers
    // -------------------------------------------------------------------------

    /// @notice Write a uint256 to transient storage at the given slot.
    function tstoreUint(bytes32 slot, uint256 value) internal {
        assembly {
            tstore(slot, value)
        }
    }

    /// @notice Read a uint256 from transient storage.
    function tloadUint(bytes32 slot) internal view returns (uint256 value) {
        assembly {
            value := tload(slot)
        }
    }

    // -------------------------------------------------------------------------
    // Slot derivation
    // -------------------------------------------------------------------------

    /// @notice Compute a unique, collision-resistant slot for a (prefix, key) pair.
    ///         Uses keccak256 so that different prefixes and keys always produce
    ///         distinct slots — preventing cross-feature storage collisions.
    ///
    /// @param prefix  A constant identifier for the feature using this slot
    ///                (e.g. keccak256("StableStream.pendingRecall"))
    /// @param key     Per-instance key (e.g. positionId cast to bytes32)
    /// @return slot   Derived storage slot
    function slotFor(bytes32 prefix, bytes32 key) internal pure returns (bytes32 slot) {
        slot = keccak256(abi.encode(prefix, key));
    }
}

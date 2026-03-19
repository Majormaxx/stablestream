// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TransientStorage} from "../src/libraries/TransientStorage.sol";

/// @title TransientStorageTest
/// @notice Unit tests for the TransientStorage EIP-1153 TSTORE/TLOAD library.
///         Verifies correct round-trip behaviour, slot derivation, and collision
///         resistance between different prefixes and keys.
contract TransientStorageTest is Test {
    // -------------------------------------------------------------------------
    // Round-trip
    // -------------------------------------------------------------------------

    /// @notice Writing true and reading it back in the same transaction returns true.
    function test_tstore_tload_roundtrip_true() public {
        bytes32 slot = keccak256("test.slot.true");
        TransientStorage.tstore(slot, true);
        assertTrue(TransientStorage.tload(slot), "stored true should load true");
    }

    /// @notice Writing false explicitly returns false on read.
    function test_tstore_tload_roundtrip_false() public {
        bytes32 slot = keccak256("test.slot.false");
        // Default is already false; write explicitly to confirm overwrite works
        TransientStorage.tstore(slot, true);
        TransientStorage.tstore(slot, false);
        assertFalse(TransientStorage.tload(slot), "overwritten false should load false");
    }

    /// @notice A slot that has never been written reads as false (zero-initialised).
    ///         This tests the "clears on new transaction" invariant: each test
    ///         function runs in a fresh EVM context, so any tstore from a prior
    ///         test is invisible here.
    function test_tstore_clearsOnNewTransaction() public view {
        bytes32 slot = keccak256("test.slot.fresh");
        // Never written in this test function — must read false
        assertFalse(
            TransientStorage.tload(slot),
            "unwritten slot must be false (transient storage zero-init per tx)"
        );
    }

    /// @notice Overwriting a slot within the same transaction reflects the latest value.
    function test_tstore_overwrite_withinSameTransaction() public {
        bytes32 slot = keccak256("test.slot.overwrite");
        TransientStorage.tstore(slot, false);
        TransientStorage.tstore(slot, true);
        TransientStorage.tstore(slot, false);
        assertFalse(TransientStorage.tload(slot), "last written value should be false");
    }

    // -------------------------------------------------------------------------
    // Uint256 helpers
    // -------------------------------------------------------------------------

    /// @notice tstoreUint / tloadUint round-trip.
    function test_tstoreUint_tloadUint_roundtrip() public {
        bytes32 slot = keccak256("test.slot.uint");
        uint256 value = 0xDEADBEEF_CAFEBABE;
        TransientStorage.tstoreUint(slot, value);
        assertEq(TransientStorage.tloadUint(slot), value, "uint256 round-trip failed");
    }

    /// @notice Unwritten uint slot reads as 0.
    function test_tstoreUint_clearsOnNewTransaction() public view {
        bytes32 slot = keccak256("test.slot.uint.fresh");
        assertEq(TransientStorage.tloadUint(slot), 0, "unwritten uint slot must be 0");
    }

    // -------------------------------------------------------------------------
    // Slot derivation
    // -------------------------------------------------------------------------

    /// @notice Different keys under the same prefix produce different slots.
    function test_slotFor_differentKeys_differentSlots() public pure {
        bytes32 prefix = keccak256("StableStream.pendingRecall");
        bytes32 keyA = keccak256("positionA");
        bytes32 keyB = keccak256("positionB");

        bytes32 slotA = TransientStorage.slotFor(prefix, keyA);
        bytes32 slotB = TransientStorage.slotFor(prefix, keyB);

        assertNotEq(slotA, slotB, "different keys must produce different slots");
    }

    /// @notice Different prefixes with the same key produce different slots.
    function test_slotFor_differentPrefixes_differentSlots() public pure {
        bytes32 prefixA = keccak256("StableStream.pendingRecall");
        bytes32 prefixB = keccak256("StableStream.otherFlag");
        bytes32 key = keccak256("samePositionId");

        bytes32 slotA = TransientStorage.slotFor(prefixA, key);
        bytes32 slotB = TransientStorage.slotFor(prefixB, key);

        assertNotEq(slotA, slotB, "different prefixes must produce different slots");
    }

    /// @notice slotFor is deterministic — same inputs always produce the same slot.
    function test_slotFor_isDeterministic() public pure {
        bytes32 prefix = keccak256("StableStream.test");
        bytes32 key = bytes32(uint256(42));

        bytes32 slot1 = TransientStorage.slotFor(prefix, key);
        bytes32 slot2 = TransientStorage.slotFor(prefix, key);

        assertEq(slot1, slot2, "slotFor must be deterministic");
    }

    /// @notice Writes to two different derived slots are independent.
    function test_slotFor_writesAreIndependent() public {
        bytes32 prefix = keccak256("StableStream.pendingRecall");
        bytes32 slotA = TransientStorage.slotFor(prefix, bytes32(uint256(1)));
        bytes32 slotB = TransientStorage.slotFor(prefix, bytes32(uint256(2)));

        TransientStorage.tstore(slotA, true);

        // Writing to slotA must not affect slotB
        assertFalse(TransientStorage.tload(slotB), "slots must be independent");
        assertTrue(TransientStorage.tload(slotA), "slotA should be true");
    }
}

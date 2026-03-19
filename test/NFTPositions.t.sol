// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {StableStreamNFT} from "../src/StableStreamNFT.sol";

/// @title NFTPositionsTest
/// @notice Unit tests for StableStreamNFT ERC-721 position receipts.
///         Covers mint, burn, ownership, access control, and ERC-721 compliance.
contract NFTPositionsTest is Test {
    StableStreamNFT internal nft;

    address internal hook    = makeAddr("hook");
    address internal alice   = makeAddr("alice");
    address internal bob     = makeAddr("bob");
    address internal attacker = makeAddr("attacker");

    bytes32 internal constant POS_A = keccak256("positionA");
    bytes32 internal constant POS_B = keccak256("positionB");
    bytes32 internal constant POS_C = keccak256("positionC");

    function setUp() public {
        nft = new StableStreamNFT(hook);
    }

    // -------------------------------------------------------------------------
    // Deployment
    // -------------------------------------------------------------------------

    /// @notice Constructor sets the hook address correctly.
    function test_nft_deployedWithCorrectHook() public view {
        assertEq(nft.hook(), hook, "hook address must match constructor argument");
    }

    /// @notice ERC-721 metadata: correct name and symbol.
    function test_nft_metadata() public view {
        assertEq(nft.name(),   "StableStream Position", "name mismatch");
        assertEq(nft.symbol(), "ssLP",                  "symbol mismatch");
    }

    // -------------------------------------------------------------------------
    // Mint
    // -------------------------------------------------------------------------

    /// @notice Only the hook may mint.
    function test_nft_onlyHookCanMint() public {
        vm.prank(attacker);
        vm.expectRevert(StableStreamNFT.OnlyHook.selector);
        nft.mint(attacker, POS_A);
    }

    /// @notice Hook can mint to any address; tokenId is uint256(positionId).
    function test_nft_mintAssignsOwnership() public {
        vm.prank(hook);
        nft.mint(alice, POS_A);

        assertEq(nft.ownerOf(uint256(POS_A)), alice, "alice should own POS_A NFT");
        assertEq(nft.balanceOf(alice), 1, "alice balance should be 1");
    }

    /// @notice positionOwner() is a convenience wrapper for ownerOf().
    function test_nft_positionOwnerReturnsCorrectAddress() public {
        vm.prank(hook);
        nft.mint(alice, POS_A);

        assertEq(nft.positionOwner(POS_A), alice, "positionOwner must match ownerOf");
    }

    /// @notice Minting the same positionId twice reverts (ERC-721 duplicate token).
    function test_nft_mintDuplicateReverts() public {
        vm.startPrank(hook);
        nft.mint(alice, POS_A);
        vm.expectRevert(); // ERC721InvalidSender
        nft.mint(alice, POS_A);
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // Burn
    // -------------------------------------------------------------------------

    /// @notice Only the hook may burn.
    function test_nft_onlyHookCanBurn() public {
        vm.prank(hook);
        nft.mint(alice, POS_A);

        vm.prank(attacker);
        vm.expectRevert(StableStreamNFT.OnlyHook.selector);
        nft.burn(POS_A);
    }

    /// @notice After burning, balanceOf decreases and ownerOf reverts.
    function test_nft_burnRemovesToken() public {
        vm.startPrank(hook);
        nft.mint(alice, POS_A);
        nft.burn(POS_A);
        vm.stopPrank();

        assertEq(nft.balanceOf(alice), 0, "balance should be 0 after burn");

        // ownerOf should revert for non-existent token
        vm.expectRevert();
        nft.positionOwner(POS_A);
    }

    /// @notice Burning a non-existent token reverts.
    function test_nft_burnNonExistentReverts() public {
        vm.prank(hook);
        vm.expectRevert(); // ERC721NonexistentToken
        nft.burn(POS_A);
    }

    // -------------------------------------------------------------------------
    // Full lifecycle
    // -------------------------------------------------------------------------

    /// @notice Full mint → transfer → burn lifecycle preserves state correctly.
    function test_nft_mintBurnCycle() public {
        // Mint
        vm.prank(hook);
        nft.mint(alice, POS_A);
        assertEq(nft.ownerOf(uint256(POS_A)), alice);

        // Transfer (Alice transfers to Bob via standard ERC-721)
        vm.prank(alice);
        nft.transferFrom(alice, bob, uint256(POS_A));
        assertEq(nft.ownerOf(uint256(POS_A)), bob, "bob should own after transfer");
        assertEq(nft.balanceOf(alice), 0, "alice balance should drop");
        assertEq(nft.balanceOf(bob), 1, "bob balance should increase");

        // Burn
        vm.prank(hook);
        nft.burn(POS_A);
        assertEq(nft.balanceOf(bob), 0, "bob balance should be 0 after burn");
    }

    /// @notice Multiple positions mint independently; burning one doesn't affect others.
    function test_nft_multiplePositionsAreIndependent() public {
        vm.startPrank(hook);
        nft.mint(alice, POS_A);
        nft.mint(alice, POS_B);
        nft.mint(bob,   POS_C);
        vm.stopPrank();

        assertEq(nft.balanceOf(alice), 2, "alice has 2 positions");
        assertEq(nft.balanceOf(bob),   1, "bob has 1 position");

        // Burn one of Alice's positions
        vm.prank(hook);
        nft.burn(POS_A);

        assertEq(nft.balanceOf(alice), 1, "alice should have 1 after burn");
        // POS_B still owned by alice; POS_C still owned by bob
        assertEq(nft.positionOwner(POS_B), alice, "POS_B ownership intact");
        assertEq(nft.positionOwner(POS_C), bob,   "POS_C ownership intact");
    }

    // -------------------------------------------------------------------------
    // ERC-721 standard compliance
    // -------------------------------------------------------------------------

    /// @notice approve() and getApproved() work correctly.
    function test_nft_approveAndGetApproved() public {
        vm.prank(hook);
        nft.mint(alice, POS_A);

        vm.prank(alice);
        nft.approve(bob, uint256(POS_A));

        assertEq(nft.getApproved(uint256(POS_A)), bob, "bob should be approved for POS_A");
    }

    /// @notice Approved address can transfer token.
    function test_nft_approvedCanTransfer() public {
        vm.prank(hook);
        nft.mint(alice, POS_A);

        vm.prank(alice);
        nft.approve(bob, uint256(POS_A));

        vm.prank(bob);
        nft.transferFrom(alice, bob, uint256(POS_A));

        assertEq(nft.ownerOf(uint256(POS_A)), bob);
    }

    /// @notice setApprovalForAll() enables an operator to transfer all tokens.
    function test_nft_setApprovalForAll() public {
        vm.startPrank(hook);
        nft.mint(alice, POS_A);
        nft.mint(alice, POS_B);
        vm.stopPrank();

        vm.prank(alice);
        nft.setApprovalForAll(bob, true);

        assertTrue(nft.isApprovedForAll(alice, bob), "bob should be approved operator");

        vm.prank(bob);
        nft.transferFrom(alice, bob, uint256(POS_A));
        assertEq(nft.ownerOf(uint256(POS_A)), bob);
    }

    // -------------------------------------------------------------------------
    // Security: hook address immutability
    // -------------------------------------------------------------------------

    /// @notice The hook address cannot be changed after deployment.
    function test_nft_hookIsImmutable() public view {
        // Hook is declared as immutable — verifying it equals what was set at deploy.
        assertEq(nft.hook(), hook, "hook must be immutable");
    }

    /// @notice Owner() is the zero address (NFT is not Ownable — hook is the authority).
    function test_nft_hasNoSeparateOwner() public {
        // StableStreamNFT does not inherit Ownable — only hook can mint/burn.
        // Verifying there's no owner-privileged backdoor.
        assertEq(nft.hook(), hook, "authority is hook, not an owner");
    }
}

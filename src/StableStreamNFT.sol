// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/// @title StableStreamNFT
/// @notice ERC-721 receipt token representing a managed StableStream LP position.
///
/// @dev    Each tokenId is the uint256 cast of the corresponding bytes32 positionId
///         used by StableStreamHook. This 1:1 mapping ensures:
///           - Off-chain tooling can derive the NFT tokenId from any positionId.
///           - On-chain ownership checks can call positionOwner(positionId) directly.
///
///         Transferability: because each NFT maps to a position tracked on-chain,
///         transferring the NFT does NOT automatically re-assign the position's
///         owner in StableStreamHook.  This is intentional — it enables secondary
///         markets for positions (e.g. selling the right to future yield) while
///         keeping the hook's accounting immutable.  The hook owner can add a
///         syncOwner() function in a future upgrade to reconcile ownership.
///
///         Mint / Burn lifecycle:
///           deposit()  → mint (called by StableStreamHook)
///           withdraw() → burn (called by StableStreamHook)
///
/// @custom:security  Only the registered hook contract may mint or burn tokens.
///                   This prevents griefing and ensures NFT supply always matches
///                   the set of open positions in the hook.
contract StableStreamNFT is ERC721 {
    // -------------------------------------------------------------------------
    // Immutable state
    // -------------------------------------------------------------------------

    /// @notice The StableStreamHook contract authorised to mint and burn tokens.
    address public immutable hook;

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error OnlyHook();

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    modifier onlyHook() {
        if (msg.sender != hook) revert OnlyHook();
        _;
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @param _hook  Address of the StableStreamHook contract (immutable after deploy)
    constructor(address _hook) ERC721("StableStream Position", "ssLP") {
        hook = _hook;
    }

    // -------------------------------------------------------------------------
    // Mint / Burn (hook-only)
    // -------------------------------------------------------------------------

    /// @notice Mint a new position receipt NFT to `to`.
    ///         Called by StableStreamHook.deposit() after the position is registered.
    ///
    /// @param to          LP who opened the position (initial NFT holder)
    /// @param positionId  Unique bytes32 position identifier from the hook
    function mint(address to, bytes32 positionId) external onlyHook {
        _mint(to, uint256(positionId));
    }

    /// @notice Burn the position receipt NFT.
    ///         Called by StableStreamHook.withdraw() after the position is closed.
    ///
    /// @param positionId  bytes32 position identifier to burn
    function burn(bytes32 positionId) external onlyHook {
        _burn(uint256(positionId));
    }

    // -------------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------------

    /// @notice Returns the current owner of the NFT associated with `positionId`.
    ///         Reverts with ERC721NonexistentToken if the position has been closed.
    ///
    /// @param positionId  bytes32 position identifier
    /// @return            Current holder of the NFT
    function positionOwner(bytes32 positionId) external view returns (address) {
        return ownerOf(uint256(positionId));
    }
}

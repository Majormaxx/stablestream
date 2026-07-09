// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

import {IdleCapitalYieldModule} from "../src/core/IdleCapitalYieldModule.sol";
import {YieldRouter} from "../src/core/YieldRouter.sol";
import {StableStreamNFT} from "./StableStreamNFT.sol";

/// @title StableStreamHook
/// @notice StableStream-specific deployment of IdleCapitalYieldModule.
///         Adds ERC-721 position receipts, multi-token whitelisting, and
///         product-specific admin surfaces on top of the generic yield module.
///
/// @dev    This contract is the "reference implementation" of the module —
///         a production-grade example of how to integrate IdleCapitalYieldModule
///         into a real Uniswap v4 hook deployment.
///
///         For a minimal integration see test/core/MinimalHook.sol.
contract StableStreamHook is IdleCapitalYieldModule {
    // -------------------------------------------------------------------------
    // StableStream-specific state
    // -------------------------------------------------------------------------

    mapping(address token => bool) public whitelistedStables;
    mapping(address token => address) public tokenRouters;
    StableStreamNFT public nft;

    // -------------------------------------------------------------------------
    // StableStream-specific events
    // -------------------------------------------------------------------------

    event StablecoinWhitelisted(address indexed token, address indexed router);
    event NFTContractSet(address indexed nftContract);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(
        IPoolManager _poolManager,
        YieldRouter _yieldRouter,
        address _usdc,
        address _owner
    ) IdleCapitalYieldModule(_poolManager, _yieldRouter, _usdc, _owner) {
        whitelistedStables[_usdc] = true;
        tokenRouters[_usdc] = address(_yieldRouter);
    }

    // -------------------------------------------------------------------------
    // Virtual lifecycle hook overrides
    // -------------------------------------------------------------------------

    function _onPositionOpened(bytes32 positionId, address owner) internal override {
        if (address(nft) != address(0)) {
            nft.mint(owner, positionId);
        }
    }

    function _onPositionClosed(bytes32 positionId) internal override {
        if (address(nft) != address(0)) {
            nft.burn(positionId);
        }
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    function setNFT(StableStreamNFT _nft) external onlyOwner {
        nft = _nft;
        emit NFTContractSet(address(_nft));
    }

    function whitelistStablecoin(address token, address router) external onlyOwner {
        whitelistedStables[token] = true;
        tokenRouters[token] = router;
        emit StablecoinWhitelisted(token, router);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IUniswapV3AndMeteora
 * @notice Interfaces for ERC20, Rome's ERC20SPLFactory, Uniswap V3 SwapRouter, and Meteora DAMM CPI helpers.
 * @dev Always resolve live contract addresses at runtime via `@rome-protocol/registry` or `rome facts contracts <chain>`.
 */

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
}

/**
 * @notice Rome's ERC20-SPL Unified Token Factory (`ERC20SPLFactory`).
 * @dev An SPL token and its ERC-20 wrapper point at ONE shared token account in Rome's Single State.
 */
interface IERC20SPLFactory {
    function getErc20BySplMint(bytes32 splMint) external view returns (address erc20Token);
    function getSplMintByErc20(address erc20Token) external view returns (bytes32 splMint);
}

/**
 * @notice Uniswap V3 SwapRouter interface deployed on Rome EVM (Hadrian Testnet & Rubicon Mainnet).
 */
interface IUniswapV3SwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut);
}

/**
 * @notice Meteora Dynamic AMM (DAMM v1) Factory / Pool interface on Rome & Solana.
 * @dev Supports both direct EVM factory inspection on Hadrian (`0xd68b355f...a3c4`)
 *      and Borsh-encoded Solana CPI instruction building for native Solana DAMM pools.
 */
interface IMeteoraDAMMPool {
    function getQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 expectedOut, uint256 feeAmount);

    function executeSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external returns (uint256 amountOut);
}

/**
 * @title BorshSolanaSwapCodec
 * @notice Helper library to encode Borsh instruction payloads for Solana AMM CPI (Meteora DAMM / Jupiter).
 * @dev Prefer `rome cookbook cpi-recipe` for production discriminators; this library packs the canonical
 *      8-byte Anchor instruction discriminator + little-endian uint64 `in_amount` + little-endian uint64 `minimum_out_amount`.
 */
library BorshSolanaSwapCodec {
    // Anchor sighash discriminator for Meteora DAMM `swap(uint64 in_amount, uint64 minimum_out_amount)`
    // sha256("global:swap")[0..8] = 0xf8c69e91e17587c8
    bytes8 internal constant METEORA_SWAP_DISCRIMINATOR = 0xf8c69e91e17587c8;

    /**
     * @notice Encodes a uint64 in Little-Endian format as required by Solana Borsh serialization.
     */
    function toLittleEndian64(uint64 value) internal pure returns (bytes8) {
        uint64 reversed = 0;
        unchecked {
            reversed |= (value & 0x00000000000000FF) << 56;
            reversed |= (value & 0x000000000000FF00) << 40;
            reversed |= (value & 0x0000000000FF0000) << 24;
            reversed |= (value & 0x00000000FF000000) << 8;
            reversed |= (value & 0x000000FF00000000) >> 8;
            reversed |= (value & 0x0000FF0000000000) >> 24;
            reversed |= (value & 0x00FF000000000000) >> 40;
            reversed |= (value & 0xFF00000000000000) >> 56;
        }
        return bytes8(reversed);
    }

    /**
     * @notice Builds the 24-byte Borsh instruction data for a Solana Meteora DAMM swap CPI.
     * @param amountIn Input token amount (uint64 SPL native units).
     * @param minAmountOut Minimum output amount (uint64 SPL native units).
     */
    function encodeMeteoraSwapIx(
        uint64 amountIn,
        uint64 minAmountOut
    ) internal pure returns (bytes memory ixData) {
        return abi.encodePacked(
            METEORA_SWAP_DISCRIMINATOR,
            toLittleEndian64(amountIn),
            toLittleEndian64(minAmountOut)
        );
    }
}

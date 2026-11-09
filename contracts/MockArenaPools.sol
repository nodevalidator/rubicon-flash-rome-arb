// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {
    IERC20,
    IERC20SPLFactory,
    IUniswapV3SwapRouter,
    IMeteoraDAMMPool
} from "./interfaces/IUniswapV3AndMeteora.sol";

/**
 * @title MockSPLTokenERC20
 * @notice Represents a Rome Unified Single-State Token (ERC-20 wrapper + SPL Mint pointer).
 */
contract MockSPLTokenERC20 is IERC20 {
    string public name;
    string public override symbol;
    uint8 public immutable override decimals;
    bytes32 public immutable splMintPubkey;

    uint256 public override totalSupply;
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        bytes32 _splMintPubkey
    ) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        splMintPubkey = _splMintPubkey;
    }

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 value) external override returns (bool) {
        require(balanceOf[msg.sender] >= value, "Insufficient balance");
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external override returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external override returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= value, "Insufficient allowance");
        require(balanceOf[from] >= value, "Insufficient balance");
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - value;
        }
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
        return true;
    }
}

/**
 * @title MockRomeERC20SPLFactory
 * @notice Maps Solana SPL Mint pubkeys (`bytes32`) to their shared-state ERC-20 addresses on Rome.
 */
contract MockRomeERC20SPLFactory is IERC20SPLFactory {
    mapping(bytes32 => address) public override getErc20BySplMint;
    mapping(address => bytes32) public override getSplMintByErc20;

    function registerPair(bytes32 splMint, address erc20Token) external {
        getErc20BySplMint[splMint] = erc20Token;
        getSplMintByErc20[erc20Token] = splMint;
    }
}

/**
 * @title MockRomeUniswapV3Router
 * @notice Configurable Uniswap V3 SwapRouter on Rome EVM for deterministic spread & arbitrage testing.
 * @dev Price is expressed as `solPriceUsdcE6` (e.g., 180_000_000 = 180.00 USDC per 1 SOL).
 */
contract MockRomeUniswapV3Router is IUniswapV3SwapRouter {
    address public immutable wUsdc;
    address public immutable wSol;
    uint256 public solPriceUsdcE6; // e.g., 180_000_000 (180 USDC per SOL)

    event RomeEvmUniswapSwap(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 effectiveSolPriceE6
    );

    constructor(address _wUsdc, address _wSol, uint256 _initialSolPriceUsdcE6) {
        wUsdc = _wUsdc;
        wSol = _wSol;
        solPriceUsdcE6 = _initialSolPriceUsdcE6;
    }

    function setSolPriceUsdcE6(uint256 _newPriceE6) external {
        solPriceUsdcE6 = _newPriceE6;
    }

    function exactInputSingle(
        ExactInputSingleParams calldata params
    ) external payable override returns (uint256 amountOut) {
        require(
            IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn),
            "UniswapV3 pull failed"
        );

        // Calculate output based on configurable SOL/USDC price (both 6 decimals in test/mock or scaled)
        if (params.tokenIn == wUsdc && params.tokenOut == wSol) {
            // Buying wSOL with wUSDC: amountOut (in 1e6 units) = (amountIn * 1e6) / solPriceUsdcE6
            amountOut = (params.amountIn * 1_000_000) / solPriceUsdcE6;
        } else if (params.tokenIn == wSol && params.tokenOut == wUsdc) {
            // Selling wSOL for wUSDC: amountOut (in 1e6 units) = (amountIn * solPriceUsdcE6) / 1e6
            amountOut = (params.amountIn * solPriceUsdcE6) / 1_000_000;
        } else {
            revert("Unsupported pair");
        }

        require(amountOut >= params.amountOutMinimum, "UniswapV3: Slippage exceeded");
        require(IERC20(params.tokenOut).transfer(params.recipient, amountOut), "UniswapV3 payout failed");

        emit RomeEvmUniswapSwap(params.tokenIn, params.tokenOut, params.amountIn, amountOut, solPriceUsdcE6);
    }
}

/**
 * @title MockSolanaMeteoraDAMMPool
 * @notice Simulates the Solana Meteora DAMM Pool settled via Rome's `ICrossProgramInvocation` (`0xFF...08`).
 * @dev Allows configuring live price spreads between Solana liquidity and Rome EVM liquidity.
 */
contract MockSolanaMeteoraDAMMPool is IMeteoraDAMMPool {
    address public immutable wUsdc;
    address public immutable wSol;
    uint256 public solPriceUsdcE6; // e.g., 184_500_000 (184.50 USDC per SOL -> +2.5% spread!)
    uint256 public swapFeeBps = 15; // 0.15% Meteora dynamic fee

    event SolanaMeteoraCpiSwap(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 effectiveSolPriceE6
    );

    constructor(address _wUsdc, address _wSol, uint256 _initialSolPriceUsdcE6) {
        wUsdc = _wUsdc;
        wSol = _wSol;
        solPriceUsdcE6 = _initialSolPriceUsdcE6;
    }

    function setSolPriceUsdcE6(uint256 _newPriceE6) external {
        solPriceUsdcE6 = _newPriceE6;
    }

    function getQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) public view override returns (uint256 expectedOut, uint256 feeAmount) {
        uint256 grossOut;
        if (tokenIn == wUsdc && tokenOut == wSol) {
            grossOut = (amountIn * 1_000_000) / solPriceUsdcE6;
        } else if (tokenIn == wSol && tokenOut == wUsdc) {
            grossOut = (amountIn * solPriceUsdcE6) / 1_000_000;
        } else {
            revert("Unsupported pair");
        }
        feeAmount = (grossOut * swapFeeBps) / 10000;
        expectedOut = grossOut - feeAmount;
    }

    function executeSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external override returns (uint256 amountOut) {
        require(
            IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn),
            "Meteora pull failed"
        );

        (amountOut, ) = getQuote(tokenIn, tokenOut, amountIn);
        require(amountOut >= minAmountOut, "Meteora: Slippage exceeded");
        require(IERC20(tokenOut).transfer(recipient, amountOut), "Meteora payout failed");

        emit SolanaMeteoraCpiSwap(tokenIn, tokenOut, amountIn, amountOut, solPriceUsdcE6);
    }
}

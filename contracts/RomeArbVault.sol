// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "./interfaces/IUniswapV3AndMeteora.sol";

/**
 * @title IFlashArbReceiver
 * @notice Callback interface for AtomicArbRouter to execute atomic arbitrage with Vault liquidity.
 */
interface IFlashArbReceiver {
    function onVaultFlashArbitrage(
        address initiator,
        bytes32 solanaWalletPubkey,
        uint256 principalAmount,
        bytes calldata arbData
    ) external returns (uint256 grossReturnAmount);
}

/**
 * @title RomeArbVault
 * @notice Shared Dual-Lane Liquidity Vault (ERC-4626 style) for Atomic Arbitrage on Rome Protocol.
 * @dev Designed to maximize all 3 Rome Builder Arena tier metrics:
 *      1. Value Locked (TVL): LPs deposit `wUSDC` (from either MetaMask or Phantom Dual-Lane) to earn arbitrage yield.
 *      2. Transaction Volume: Provides zero-upfront-capital Flash Arbitrage liquidity to `AtomicArbRouter`.
 *      3. User Acquisition: Rewards Keepers/Users 20% of arbitrage profit immediately while compounding 80% into LP shares.
 */
contract RomeArbVault {
    string public constant name = "Rubicon Flash Shared Arbitrage Vault";
    string public constant symbol = "rvUSDC";
    uint8 public immutable decimals;

    IERC20 public immutable asset; // Base asset (e.g., wUSDC on Hadrian/Rubicon)
    address public owner;
    address public authorizedRouter;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // Dual-Lane identity linking: EVM address => optional Solana Wallet pubkey (bytes32)
    mapping(address => bytes32) public linkedSolanaWallet;
    mapping(address => bool) public isRegisteredArenaUser;

    // Arena Leaderboard & Traction Telemetry
    uint256 public totalUniqueUsers;
    uint256 public totalArbitrageVolume;
    uint256 public totalCumulativeYield;
    uint256 public totalKeeperBountiesPaid;
    uint256 public totalArbTradesCount;

    // Profit split in basis points (80% to Vault LPs, 20% to Keeper/User trigger)
    uint256 public constant LP_PROFIT_SHARE_BPS = 8000;
    uint256 public constant KEEPER_BOUNTY_SHARE_BPS = 2000;
    uint256 public constant BPS_DENOMINATOR = 10000;

    bool private _locked;

    event DepositDualLane(
        address indexed evmUser,
        bytes32 indexed solanaPubkey,
        uint256 assetsDeposited,
        uint256 sharesMinted
    );
    event WithdrawDualLane(
        address indexed evmUser,
        bytes32 indexed solanaPubkey,
        uint256 sharesBurned,
        uint256 assetsReturned
    );
    event DualIdentityLinked(address indexed evmUser, bytes32 indexed solanaPubkey);
    event FlashArbFunded(
        address indexed keeper,
        bytes32 indexed solanaPubkey,
        uint256 principalUsed,
        uint256 totalProfit,
        uint256 lpYieldAdded,
        uint256 keeperBounty
    );
    event RouterUpdated(address indexed oldRouter, address indexed newRouter);

    error ReentrancyGuard();
    error Unauthorized();
    error ZeroAmount();
    error InsufficientShares();
    error FlashLoanNotRepaidWithProfit(uint256 expectedMinimum, uint256 actualReturned);

    modifier nonReentrant() {
        if (_locked) revert ReentrancyGuard();
        _locked = true;
        _;
        _locked = false;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    constructor(address _asset) {
        asset = IERC20(_asset);
        decimals = IERC20(_asset).decimals();
        owner = msg.sender;
    }

    function setAuthorizedRouter(address _router) external onlyOwner {
        emit RouterUpdated(authorizedRouter, _router);
        authorizedRouter = _router;
    }

    /**
     * @notice Total underlying `wUSDC` controlled by the Vault.
     */
    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /**
     * @notice Converts an asset amount (`wUSDC`) to Vault shares (`rvUSDC`).
     */
    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply;
        uint256 currentAssets = totalAssets();
        if (supply == 0 || currentAssets == 0) {
            return assets;
        }
        return (assets * supply) / currentAssets;
    }

    /**
     * @notice Converts Vault shares (`rvUSDC`) to underlying `wUSDC` assets (including compounded arb yield).
     */
    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply;
        if (supply == 0) {
            return shares;
        }
        return (shares * totalAssets()) / supply;
    }

    /**
     * @notice Current share price scaled by 1e6 (1.000000 = 1_000_000).
     */
    function sharePriceE6() external view returns (uint256) {
        if (totalSupply == 0) return 1_000_000;
        return (totalAssets() * 1_000_000) / totalSupply;
    }

    /**
     * @notice Links a user's EVM address with their Solana wallet pubkey (`bytes32`) for Dual-Lane tracking.
     */
    function linkSolanaWallet(bytes32 solanaPubkey) external {
        _registerArenaUser(msg.sender, solanaPubkey);
        emit DualIdentityLinked(msg.sender, solanaPubkey);
    }

    /**
     * @notice Deposits `wUSDC` into the Shared Vault from either EVM Lane (MetaMask) or Solana Lane (Phantom).
     * @param assets Amount of `wUSDC` to deposit.
     * @param solanaPubkey Optional 32-byte Solana wallet public key (pass `bytes32(0)` if EVM-only).
     */
    function deposit(uint256 assets, bytes32 solanaPubkey) external nonReentrant returns (uint256 shares) {
        if (assets == 0) revert ZeroAmount();
        _registerArenaUser(msg.sender, solanaPubkey);

        shares = convertToShares(assets);
        if (shares == 0) revert ZeroAmount();

        bool ok = asset.transferFrom(msg.sender, address(this), assets);
        require(ok, "TransferFrom failed");

        totalSupply += shares;
        balanceOf[msg.sender] += shares;

        emit DepositDualLane(msg.sender, linkedSolanaWallet[msg.sender], assets, shares);
    }

    /**
     * @notice Withdraws `wUSDC` principal + accumulated arbitrage yield by burning `rvUSDC` shares.
     * @param shares Amount of `rvUSDC` shares to redeem.
     */
    function withdraw(uint256 shares) external nonReentrant returns (uint256 assetsOut) {
        if (shares == 0) revert ZeroAmount();
        if (balanceOf[msg.sender] < shares) revert InsufficientShares();

        assetsOut = convertToAssets(shares);
        balanceOf[msg.sender] -= shares;
        totalSupply -= shares;

        bool ok = asset.transfer(msg.sender, assetsOut);
        require(ok, "Transfer failed");

        emit WithdrawDualLane(msg.sender, linkedSolanaWallet[msg.sender], shares, assetsOut);
    }

    /**
     * @notice Executes an atomic flash-funded arbitrage via `AtomicArbRouter`.
     * @dev Only callable by `authorizedRouter`. Splits net profit: 80% stays in Vault (raising share price),
     *      20% is transferred directly to `keeper` as an instant 1-Click Arbitrage Bounty.
     */
    function executeVaultFundedArb(
        address keeper,
        bytes32 solanaPubkey,
        uint256 principalAmount,
        uint256 minTotalProfit,
        bytes calldata arbData
    ) external nonReentrant returns (uint256 netProfit, uint256 keeperBounty, uint256 lpYield) {
        if (msg.sender != authorizedRouter) revert Unauthorized();
        if (principalAmount == 0 || principalAmount > totalAssets()) revert ZeroAmount();

        _registerArenaUser(keeper, solanaPubkey);

        uint256 balanceBefore = totalAssets();

        // Send principal to AtomicArbRouter
        require(asset.transfer(authorizedRouter, principalAmount), "Vault fund transfer failed");

        // Trigger atomic EVM <-> Solana CPI arbitrage callback
        IFlashArbReceiver(authorizedRouter).onVaultFlashArbitrage(
            keeper,
            solanaPubkey,
            principalAmount,
            arbData
        );

        // Verify Router returned principal + profit
        uint256 balanceAfterCallback = totalAssets();
        if (balanceAfterCallback < balanceBefore + minTotalProfit) {
            revert FlashLoanNotRepaidWithProfit(balanceBefore + minTotalProfit, balanceAfterCallback);
        }

        netProfit = balanceAfterCallback - balanceBefore;
        keeperBounty = (netProfit * KEEPER_BOUNTY_SHARE_BPS) / BPS_DENOMINATOR;
        lpYield = netProfit - keeperBounty;

        if (keeperBounty > 0) {
            require(asset.transfer(keeper, keeperBounty), "Keeper bounty transfer failed");
        }

        // Update Rome Arena traction metrics
        totalArbitrageVolume += principalAmount;
        totalCumulativeYield += lpYield;
        totalKeeperBountiesPaid += keeperBounty;
        totalArbTradesCount += 1;

        emit FlashArbFunded(
            keeper,
            linkedSolanaWallet[keeper],
            principalAmount,
            netProfit,
            lpYield,
            keeperBounty
        );
    }

    function _registerArenaUser(address evmUser, bytes32 solanaPubkey) internal {
        if (!isRegisteredArenaUser[evmUser]) {
            isRegisteredArenaUser[evmUser] = true;
            totalUniqueUsers += 1;
        }
        if (solanaPubkey != bytes32(0)) {
            linkedSolanaWallet[evmUser] = solanaPubkey;
        }
    }
}

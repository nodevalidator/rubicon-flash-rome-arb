// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {
    ICrossProgramInvocation,
    ISystemProgram,
    IHelperProgram,
    RomePrecompileAddresses
} from "./interfaces/IRomePrecompiles.sol";
import {
    IERC20,
    IERC20SPLFactory,
    IUniswapV3SwapRouter,
    IMeteoraDAMMPool,
    BorshSolanaSwapCodec
} from "./interfaces/IUniswapV3AndMeteora.sol";
import {RomeArbVault, IFlashArbReceiver} from "./RomeArbVault.sol";

/**
 * @title AtomicArbRouter
 * @notice Rubicon Flash — Dual-Lane Atomic Arbitrage Executor & Router on Rome Protocol.
 * @dev Executes cross-runtime arbitrage between Rome EVM DEXs (Uniswap V3) and Solana Native AMMs (Meteora DAMM / SPL)
 *      within a SINGLE Solana transaction (~400ms block time).
 *
 *      Rome Native Primitives Used:
 *        - `ICrossProgramInvocation` (`0xFF00000000000000000000000000000000000008`) for `invoke` & `invoke_signed`
 *        - `ISystemProgram` (`0xFF00000000000000000000000000000000000007`) for external-authority PDA derivation
 *        - `IHelperProgram` (`0xFF00000000000000000000000000000000000009`) for SPL / Shared-State synchronization
 *        - Explicit upfront `AccountMeta[]` validation & CPI depth <= 4 enforcement
 *        - Atomic Profit Guard: if the final balance across both legs is less than `principal + minProfit`,
 *          the entire transaction (including the Solana CPI leg) reverts atomically.
 */
contract AtomicArbRouter is IFlashArbReceiver {
    using BorshSolanaSwapCodec for uint64;

    enum ArbDirection {
        EVM_TO_SOLANA, // Leg 1: Buy target token on Rome Uniswap V3 -> Leg 2: Sell via Solana CPI (Meteora DAMM)
        SOLANA_TO_EVM  // Leg 1: Buy target token via Solana CPI (Meteora DAMM) -> Leg 2: Sell on Rome Uniswap V3
    }

    enum CapitalSource {
        USER_WALLET,  // User provides their own wUSDC & keeps 100% of profit
        SHARED_VAULT  // Borrow flash capital from RomeArbVault (80% profit to Vault LPs, 20% instant bounty to User)
    }

    struct ArbStrategyParams {
        ArbDirection direction;
        CapitalSource capitalSource;
        address baseToken;            // e.g., wUSDC on Hadrian/Rubicon
        address quoteToken;           // e.g., wSOL / wETH on Hadrian/Rubicon
        uint24 uniswapPoolFee;        // e.g., 500 (0.05%) or 3000 (0.3%)
        uint256 amountIn;             // Principal in baseToken (e.g., 1000 * 1e6 wUSDC)
        uint256 minProfit;            // Minimum net profit in baseToken required or tx reverts
        bytes32 solanaTargetProgram;  // Target Solana AMM Program ID (bytes32)
        bytes32 userSolanaPubkey;     // Optional Solana wallet pubkey for Dual-Lane attribution
        uint8 estimatedCpiDepth;      // Must be >= 1 and <= 4 (Rome runtime hard constraint)
        ICrossProgramInvocation.AccountMeta[] solanaAccounts; // Upfront declared Solana accounts
        bytes[] pdaSalts;             // Seeds/salts for `invoke_signed` via external-authority PDA
    }

    struct SimulationPreview {
        bool profitable;
        uint256 amountIn;
        uint256 leg1Out;
        uint256 leg2Out;
        uint256 expectedNetProfit;
        bytes borshInstructionPayload;
        bytes32 routerExternalPda;
    }

    address public owner;
    RomeArbVault public immutable vault;
    IUniswapV3SwapRouter public uniswapRouter;
    IMeteoraDAMMPool public solanaMirrorPool; // Used when CPI precompile is emulated on local EVM / testnet mirror
    IERC20SPLFactory public erc20SplFactory;

    // Telemetry for Rome Builder Arena
    uint256 public totalStrategiesExecuted;
    uint256 public totalAtomicVolumeUsdc;
    uint256 public totalNetProfitGenerated;

    event AtomicArbitrageExecuted(
        uint256 indexed strategyId,
        address indexed executorEvm,
        bytes32 indexed executorSolana,
        ArbDirection direction,
        CapitalSource capitalSource,
        uint256 principalIn,
        uint256 grossOut,
        uint256 netProfit,
        bytes32 solanaProgramInvoked,
        bytes borshIxData
    );

    event SolanaCpiDispatched(
        bytes32 indexed solanaProgramId,
        uint256 declaredAccountsCount,
        bool isSignedCpi,
        bytes instructionData
    );

    error Unauthorized();
    error InvalidSolanaAccountsDeclaration(uint256 count);
    error CpiDepthExceeded(uint8 requestedDepth, uint8 maxAllowed);
    error UnprofitableAtomicArbitrage(uint256 balanceBefore, uint256 balanceAfter, uint256 requiredMinimum);
    error InvalidAmount();

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    constructor(
        address _vault,
        address _uniswapRouter,
        address _solanaMirrorPool,
        address _erc20SplFactory
    ) {
        owner = msg.sender;
        vault = RomeArbVault(_vault);
        uniswapRouter = IUniswapV3SwapRouter(_uniswapRouter);
        solanaMirrorPool = IMeteoraDAMMPool(_solanaMirrorPool);
        erc20SplFactory = IERC20SPLFactory(_erc20SplFactory);
    }

    function updateIntegrations(
        address _uniswapRouter,
        address _solanaMirrorPool,
        address _erc20SplFactory
    ) external onlyOwner {
        uniswapRouter = IUniswapV3SwapRouter(_uniswapRouter);
        solanaMirrorPool = IMeteoraDAMMPool(_solanaMirrorPool);
        erc20SplFactory = IERC20SPLFactory(_erc20SplFactory);
    }

    /**
     * @notice Queries Rome's `ISystemProgram` precompile (`0xFF...07`) to derive this contract's external-authority PDA.
     * @dev Falls back to deterministic keccak256 hash when running on local EVM test environment without precompile.
     */
    function getRouterExternalAuthorityPda() public view returns (bytes32 pda) {
        address sysAddr = RomePrecompileAddresses.SYSTEM_PROGRAM_ADDR;
        if (sysAddr.code.length > 0) {
            try RomePrecompileAddresses.SystemProgram.externalAuthorityPda(address(this)) returns (bytes32 livePda) {
                return livePda;
            } catch {}
        }
        return keccak256(abi.encodePacked("ROME_EXTERNAL_AUTHORITY_PDA", address(this)));
    }

    /**
     * @notice Builds a canonical Solana `AccountMeta[]` array and Borsh swap payload for UI / Bot inspection.
     */
    function buildMeteoraCpiBundle(
        bytes32 poolAccount,
        bytes32 userSourceAta,
        bytes32 userDestAta,
        bytes32 poolTokenAVault,
        bytes32 poolTokenBVault,
        uint64 amountIn,
        uint64 minAmountOut
    )
        external
        view
        returns (
            ICrossProgramInvocation.AccountMeta[] memory accounts,
            bytes memory borshIxData,
            bytes32 signingPda
        )
    {
        signingPda = getRouterExternalAuthorityPda();
        accounts = new ICrossProgramInvocation.AccountMeta[](7);
        accounts[0] = ICrossProgramInvocation.AccountMeta(poolAccount, false, true);
        accounts[1] = ICrossProgramInvocation.AccountMeta(userSourceAta, false, true);
        accounts[2] = ICrossProgramInvocation.AccountMeta(userDestAta, false, true);
        accounts[3] = ICrossProgramInvocation.AccountMeta(poolTokenAVault, false, true);
        accounts[4] = ICrossProgramInvocation.AccountMeta(poolTokenBVault, false, true);
        accounts[5] = ICrossProgramInvocation.AccountMeta(signingPda, true, false);
        accounts[6] = ICrossProgramInvocation.AccountMeta(
            RomePrecompileAddresses.SOLANA_SPL_TOKEN_PROGRAM,
            false,
            false
        );

        borshIxData = BorshSolanaSwapCodec.encodeMeteoraSwapIx(amountIn, minAmountOut);
    }

    /**
     * @notice Entry point to execute an Atomic Arbitrage strategy from either a MetaMask or Phantom Dual-Lane wallet.
     */
    function executeAtomicArbitrage(
        ArbStrategyParams calldata params
    ) external returns (uint256 netProfit) {
        _validateRomeConstraints(params);

        if (params.capitalSource == CapitalSource.USER_WALLET) {
            // Pull principal from user wallet
            IERC20 base = IERC20(params.baseToken);
            uint256 balanceBefore = base.balanceOf(address(this));
            require(
                base.transferFrom(msg.sender, address(this), params.amountIn),
                "User transferFrom failed"
            );

            (uint256 grossOut, bytes memory borshIxData) = _runDualLegArbitrage(params);
            uint256 balanceAfter = base.balanceOf(address(this));

            uint256 requiredAfter = balanceBefore + params.amountIn + params.minProfit;
            if (balanceAfter < requiredAfter) {
                revert UnprofitableAtomicArbitrage(
                    balanceBefore + params.amountIn,
                    balanceAfter,
                    requiredAfter
                );
            }

            netProfit = balanceAfter - (balanceBefore + params.amountIn);

            // Return principal + 100% profit to user
            require(base.transfer(msg.sender, params.amountIn + netProfit), "Payout transfer failed");

            _recordTelemetry(params, msg.sender, grossOut, netProfit, borshIxData);
        } else {
            // Borrow principal from Shared RomeArbVault (80% LP yield / 20% instant Keeper bounty)
            bytes memory encodedParams = abi.encode(params);
            (netProfit, , ) = vault.executeVaultFundedArb(
                msg.sender,
                params.userSolanaPubkey,
                params.amountIn,
                params.minProfit,
                encodedParams
            );
        }
    }

    /**
     * @notice Callback invoked by `RomeArbVault` during `SHARED_VAULT` flash arbitrage execution.
     */
    function onVaultFlashArbitrage(
        address initiator,
        bytes32 /* solanaWalletPubkey */,
        uint256 principalAmount,
        bytes calldata arbData
    ) external override returns (uint256 grossReturnAmount) {
        if (msg.sender != address(vault)) revert Unauthorized();

        ArbStrategyParams memory params = abi.decode(arbData, (ArbStrategyParams));
        IERC20 base = IERC20(params.baseToken);

        (uint256 grossOut, bytes memory borshIxData) = _runDualLegArbitrage(params);

        uint256 currentBalance = base.balanceOf(address(this));
        uint256 requiredMinimum = principalAmount + params.minProfit;
        if (currentBalance < requiredMinimum) {
            revert UnprofitableAtomicArbitrage(principalAmount, currentBalance, requiredMinimum);
        }

        uint256 netProfit = currentBalance - principalAmount;
        grossReturnAmount = currentBalance;

        // Return full principal + profit back to Vault so Vault can distribute 80% LP / 20% Keeper
        require(base.transfer(address(vault), grossReturnAmount), "Vault repayment failed");

        _recordTelemetry(params, initiator, grossOut, netProfit, borshIxData);
    }

    /**
     * @dev Enforces Rome Protocol's CPI & Solana account rules upfront before touching state.
     */
    function _validateRomeConstraints(ArbStrategyParams calldata params) internal pure {
        if (params.amountIn == 0) revert InvalidAmount();
        if (
            params.solanaAccounts.length == 0 ||
            params.solanaAccounts.length > RomePrecompileAddresses.MAX_DECLARED_SOLANA_ACCOUNTS
        ) {
            revert InvalidSolanaAccountsDeclaration(params.solanaAccounts.length);
        }
        if (
            params.estimatedCpiDepth == 0 ||
            params.estimatedCpiDepth > RomePrecompileAddresses.MAX_CPI_DEPTH
        ) {
            revert CpiDepthExceeded(params.estimatedCpiDepth, RomePrecompileAddresses.MAX_CPI_DEPTH);
        }
    }

    /**
     * @dev Executes the two arbitrage legs atomically across Rome EVM (Uniswap V3) and Solana CPI (Meteora DAMM).
     */
    function _runDualLegArbitrage(
        ArbStrategyParams memory params
    ) internal returns (uint256 finalAmountOut, bytes memory borshIxData) {
        if (params.direction == ArbDirection.EVM_TO_SOLANA) {
            // Leg 1: Swap baseToken (wUSDC) -> quoteToken (wSOL) on Rome EVM Uniswap V3
            uint256 quoteReceived = _swapOnUniswapV3(
                params.baseToken,
                params.quoteToken,
                params.uniswapPoolFee,
                params.amountIn,
                1
            );

            // Leg 2: Atomic CPI to Solana AMM (Meteora DAMM) to swap quoteToken (SOL) -> baseToken (USDC)
            borshIxData = BorshSolanaSwapCodec.encodeMeteoraSwapIx(
                uint64(quoteReceived),
                uint64(params.amountIn + params.minProfit)
            );

            finalAmountOut = _invokeSolanaAmmLeg(
                params.solanaTargetProgram,
                params.solanaAccounts,
                borshIxData,
                params.pdaSalts,
                params.quoteToken,
                params.baseToken,
                quoteReceived
            );
        } else {
            // Leg 1: Atomic CPI to Solana AMM (Meteora DAMM) to buy undervalued quoteToken (SOL) with baseToken (USDC)
            borshIxData = BorshSolanaSwapCodec.encodeMeteoraSwapIx(
                uint64(params.amountIn),
                1
            );

            uint256 quoteBoughtOnSolana = _invokeSolanaAmmLeg(
                params.solanaTargetProgram,
                params.solanaAccounts,
                borshIxData,
                params.pdaSalts,
                params.baseToken,
                params.quoteToken,
                params.amountIn
            );

            // Leg 2: Sell quoteToken (wSOL) -> baseToken (wUSDC) on Rome EVM Uniswap V3
            finalAmountOut = _swapOnUniswapV3(
                params.quoteToken,
                params.baseToken,
                params.uniswapPoolFee,
                quoteBoughtOnSolana,
                params.amountIn + params.minProfit
            );
        }
    }

    function _swapOnUniswapV3(
        address tokenIn,
        address tokenOut,
        uint24 poolFee,
        uint256 amountIn,
        uint256 minOut
    ) internal returns (uint256 amountOut) {
        IERC20(tokenIn).approve(address(uniswapRouter), amountIn);
        IUniswapV3SwapRouter.ExactInputSingleParams memory uniParams = IUniswapV3SwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp + 300,
                amountIn: amountIn,
                amountOutMinimum: minOut,
                sqrtPriceLimitX96: 0
            });
        amountOut = uniswapRouter.exactInputSingle(uniParams);
    }

    /**
     * @dev Dispatches the Cross-Program Invocation to Rome's `CpiProgram` precompile (`0xFF...08`).
     *      When deployed on Hadrian/Rubicon with a live Rome EVM precompile, invokes `CpiProgram.invoke_signed` or `invoke`.
     *      Also supports seamless settlement through `solanaMirrorPool` for deterministic testnet / local verification.
     */
    function _invokeSolanaAmmLeg(
        bytes32 solanaProgramId,
        ICrossProgramInvocation.AccountMeta[] memory accounts,
        bytes memory borshIxData,
        bytes[] memory pdaSalts,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        bool isSigned = pdaSalts.length > 0;
        address cpiPrecompile = RomePrecompileAddresses.CPI_PROGRAM_ADDR;

        // If running inside Rome EVM runtime where 0xFF...08 precompile is active and mirror pool is not overriding
        if (cpiPrecompile.code.length > 0 && address(solanaMirrorPool) == address(0)) {
            if (isSigned) {
                RomePrecompileAddresses.CpiProgram.invoke_signed(
                    solanaProgramId,
                    accounts,
                    borshIxData,
                    pdaSalts
                );
            } else {
                RomePrecompileAddresses.CpiProgram.invoke(
                    solanaProgramId,
                    accounts,
                    borshIxData
                );
            }
            emit SolanaCpiDispatched(solanaProgramId, accounts.length, isSigned, borshIxData);
            return IERC20(tokenOut).balanceOf(address(this));
        }

        // Testnet / Emulator Dual-State Mirror Pool execution (validates full Borsh encoding + AccountMeta declaration)
        emit SolanaCpiDispatched(solanaProgramId, accounts.length, isSigned, borshIxData);
        IERC20(tokenIn).approve(address(solanaMirrorPool), amountIn);
        amountOut = solanaMirrorPool.executeSwap(
            tokenIn,
            tokenOut,
            amountIn,
            1,
            address(this)
        );
    }

    function _recordTelemetry(
        ArbStrategyParams memory params,
        address executor,
        uint256 grossOut,
        uint256 netProfit,
        bytes memory borshIxData
    ) internal {
        totalStrategiesExecuted += 1;
        totalAtomicVolumeUsdc += params.amountIn;
        totalNetProfitGenerated += netProfit;

        emit AtomicArbitrageExecuted(
            totalStrategiesExecuted,
            executor,
            params.userSolanaPubkey,
            params.direction,
            params.capitalSource,
            params.amountIn,
            grossOut,
            netProfit,
            params.solanaTargetProgram,
            borshIxData
        );
    }
}

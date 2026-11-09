// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IRomePrecompiles
 * @notice Canonical Rome Protocol Precompile Interfaces (compatible with `@rome-protocol/rome-solidity/contracts/interface.sol`)
 * @dev Rome runs real EVM chains natively inside the Solana runtime.
 *      Precompiles allow Solidity contracts to invoke Solana programs atomically in a single Solana transaction (~400ms).
 *      Hard constraints:
 *        1. All Solana accounts must be declared upfront in `AccountMeta[]`.
 *        2. CPI depth is limited to <= 4 levels.
 *        3. Solana pubkeys are represented as `bytes32` in Solidity.
 *        4. Instruction data is raw bytes (typically Borsh-encoded).
 */

interface ICrossProgramInvocation {
    struct AccountMeta {
        bytes32 pubkey;
        bool isSigner;
        bool isWritable;
    }

    /**
     * @notice Unsigned Cross-Program Invocation into a Solana program.
     * @param programId The target Solana program's 32-byte public key.
     * @param accounts Full list of Solana AccountMeta required by the instruction.
     * @param instructionData Raw Borsh-encoded instruction payload.
     * @return returnData Optional data returned from the Solana CPI call.
     */
    function invoke(
        bytes32 programId,
        AccountMeta[] memory accounts,
        bytes memory instructionData
    ) external returns (bytes memory returnData);

    /**
     * @notice Signed Cross-Program Invocation where this contract's external-authority PDA signs.
     * @dev Ensure the external-authority PDA is funded via `rome activate <chain>` before mainnet/testnet signed CPI.
     * @param programId The target Solana program's 32-byte public key.
     * @param accounts Full list of Solana AccountMeta required by the instruction.
     * @param instructionData Raw Borsh-encoded instruction payload.
     * @param salts Seeds/salts used to derive the signing PDA.
     * @return returnData Optional data returned from the Solana CPI call.
     */
    function invoke_signed(
        bytes32 programId,
        AccountMeta[] memory accounts,
        bytes memory instructionData,
        bytes[] memory salts
    ) external returns (bytes memory returnData);
}

interface ISystemProgram {
    /**
     * @notice Derives a Program Derived Address (PDA) on Solana.
     * @param seeds Array of byte seeds.
     * @param programId Solana program ID (`bytes32`).
     * @return pda The derived 32-byte public key.
     * @return bump The canonical bump seed.
     */
    function findProgramAddress(
        bytes[] memory seeds,
        bytes32 programId
    ) external view returns (bytes32 pda, uint8 bump);

    /**
     * @notice Derives the external-authority PDA for an EVM contract on Rome.
     * @param evmContract Address of the EVM contract.
     * @return pda The 32-byte Solana PDA corresponding to `evmContract`.
     */
    function externalAuthorityPda(address evmContract) external view returns (bytes32 pda);

    /**
     * @notice Converts a Base58 string to a 32-byte Solana pubkey.
     */
    function base58ToPubkey(string memory base58Str) external pure returns (bytes32 pubkey);
}

interface IHelperProgram {
    /**
     * @notice Transfers native Lamports from the contract's PDA to a Solana recipient.
     */
    function transferLamports(bytes32 fromPda, bytes32 toPubkey, uint64 lamports) external returns (bool);

    /**
     * @notice Transfers SPL tokens atomically across the Shared State token account.
     * @param splTokenProgram The SPL Token Program ID (`TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA`).
     * @param sourceAta Source Associated Token Account (`bytes32`).
     * @param destinationAta Destination Associated Token Account (`bytes32`).
     * @param authorityPda Signing PDA authority (`bytes32`).
     * @param amount Token amount in native SPL decimals.
     */
    function transferSplToken(
        bytes32 splTokenProgram,
        bytes32 sourceAta,
        bytes32 destinationAta,
        bytes32 authorityPda,
        uint64 amount
    ) external returns (bool);
}

/**
 * @title RomePrecompileAddresses
 * @notice Fixed precompile constants for Rome EVM runtime.
 */
library RomePrecompileAddresses {
    address internal constant SYSTEM_PROGRAM_ADDR = 0xFF00000000000000000000000000000000000007;
    address internal constant CPI_PROGRAM_ADDR    = 0xFF00000000000000000000000000000000000008;
    address internal constant HELPER_PROGRAM_ADDR = 0xFF00000000000000000000000000000000000009;

    ICrossProgramInvocation internal constant CpiProgram =
        ICrossProgramInvocation(CPI_PROGRAM_ADDR);
    ISystemProgram internal constant SystemProgram =
        ISystemProgram(SYSTEM_PROGRAM_ADDR);
    IHelperProgram internal constant Helper =
        IHelperProgram(HELPER_PROGRAM_ADDR);

    // Well-known Solana Program Pubkeys (bytes32 representation)
    // TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA (SPL Token Program)
    bytes32 internal constant SOLANA_SPL_TOKEN_PROGRAM =
        0x06ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a9;

    // 11111111111111111111111111111111 (Solana System Program)
    bytes32 internal constant SOLANA_SYSTEM_PROGRAM =
        0x0000000000000000000000000000000000000000000000000000000000000000;

    // ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL (Associated Token Program)
    bytes32 internal constant SOLANA_ATA_PROGRAM =
        0x8c97258f4e2489f1bb3d1029148e0d830b5a1399daff1084048e7bd8dbe9f859;

    uint8 internal constant MAX_CPI_DEPTH = 4;
    uint256 internal constant MAX_DECLARED_SOLANA_ACCOUNTS = 32;
}

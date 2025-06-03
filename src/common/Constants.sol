// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title Constants
 * @dev Defines shared constants used throughout the OnGrid Finance protocol.
 * @notice This contract is intended to be inherited or its values imported directly.
 */
library Constants {
    // --- Time ---
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    // --- Financial ---
    uint8 public constant USDC_DECIMALS = 6;
    uint256 public constant USDC_UNIT = 10 ** USDC_DECIMALS; // 1 USDC

    // Represents 100% in basis points (BPS)
    uint16 public constant BASIS_POINTS_DENOMINATOR = 10000; // 100% = 10,000 BPS

    // Project Value Threshold
    uint256 public constant HIGH_VALUE_THRESHOLD = 50_000 * USDC_UNIT; // $50,000 USDC

    // Developer Deposit
    uint16 public constant DEVELOPER_DEPOSIT_BPS = 2000; // 20%

    // --- Fees ---

    // Capital Raising Fee (Applied once at funding)
    // Note: Tier based on developer's funding history (checked in FeeRouter)
    uint16 public constant CAPITAL_RAISING_FEE_FIRST_TIME_BPS = 200; // 2.0%
    uint16 public constant CAPITAL_RAISING_FEE_REPEAT_BPS = 150; // 1.5%

    // Management Fee (AUM - Annualized, calculated pro-rata)
    // Tiers based on total loan amount outstanding (AUM)
    // Tier 1: <= $1M
    uint256 public constant MGMT_FEE_AUM_TIER1_THRESHOLD = 1_000_000 * USDC_UNIT;
    uint16 public constant MGMT_FEE_AUM_TIER1_BPS = 100; // 1.0% Annually
    // Tier 2: > $1M
    uint16 public constant MGMT_FEE_AUM_TIER2_BPS = 75; // 0.75% Annually

    // Transaction Fee (Applied on Repayments & Drawdowns - TBD if on drawdowns)
    // Tiers based on the transaction amount. No Cap.
    // Tier 1: <= $10k
    uint256 public constant TX_FEE_TIER1_THRESHOLD = 10_000 * USDC_UNIT;
    uint16 public constant TX_FEE_TIER1_BPS = 50; // 0.50%
    // Tier 2: > $10k and <= $100k
    uint256 public constant TX_FEE_TIER2_THRESHOLD = 100_000 * USDC_UNIT;
    uint16 public constant TX_FEE_TIER2_BPS = 35; // 0.35%
    // Tier 3: > $100k
    uint16 public constant TX_FEE_TIER3_BPS = 20; // 0.20%
    // NOTE: TX_FEE_HARD_CAP is intentionally removed as per instructions.

    // Fee Distribution (Percentage of total collected fee)
    uint16 public constant PROTOCOL_TREASURY_SHARE_BPS = 8000; // 80%
    uint16 public constant CARBON_TREASURY_SHARE_BPS = 2000; // 20% (Must sum to BASIS_POINTS_DENOMINATOR)

    // --- Roles (Bytes32 Hashes) ---
    // General Roles (used across multiple contracts)
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // Specific Contract Roles
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE"); // MockUSDC
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE"); // MockUSDC
    bytes32 public constant KYC_ADMIN_ROLE = keccak256("KYC_ADMIN_ROLE"); // DeveloperRegistry
    bytes32 public constant RELEASER_ROLE = keccak256("RELEASER_ROLE"); // DeveloperDepositEscrow
    bytes32 public constant SLASHER_ROLE = keccak256("SLASHER_ROLE"); // DeveloperDepositEscrow
    bytes32 public constant DEPOSIT_FUNDER_ROLE = keccak256("DEPOSIT_FUNDER_ROLE"); // DeveloperDepositEscrow (for ProjectFactory/LPM to fund deposits)
    bytes32 public constant PROJECT_HANDLER_ROLE = keccak256("PROJECT_HANDLER_ROLE"); // LiquidityPoolManager, FeeRouter
    bytes32 public constant REPAYMENT_HANDLER_ROLE = keccak256("REPAYMENT_HANDLER_ROLE"); // DirectProjectVault, LiquidityPoolManager
    bytes32 public constant DEV_ESCROW_ROLE = keccak256("DEV_ESCROW_ROLE"); // DirectProjectVault (Authorised to call triggerDrawdown)
    bytes32 public constant RISK_ORACLE_ROLE = keccak256("RISK_ORACLE_ROLE"); // DirectProjectVault, LiquidityPoolManager, RiskRateOracleAdapter
    bytes32 public constant REPAYMENT_ROUTER_ROLE = keccak256("REPAYMENT_ROUTER_ROLE"); // FeeRouter

    // --- Project States ---
    uint8 public constant PROJECT_STATE_PENDING_DEPOSIT = 0;
    uint8 public constant PROJECT_STATE_FUNDING_OPEN = 1;
    uint8 public constant PROJECT_STATE_FUNDED = 2;
    uint8 public constant PROJECT_STATE_ACTIVE = 3;
    uint8 public constant PROJECT_STATE_COMPLETED = 4;
    uint8 public constant PROJECT_STATE_DEFAULTED = 5;
    uint8 public constant PROJECT_STATE_CANCELLED = 6;

    // --- Funding Deadlines ---
    uint32 public constant FUNDING_DEADLINE_30_DAYS = 30 days;
    uint32 public constant FUNDING_DEADLINE_2_MONTHS = 60 days;
    uint32 public constant FUNDING_DEADLINE_3_MONTHS = 90 days;
    uint32 public constant FUNDING_DEADLINE_6_MONTHS = 180 days;
}

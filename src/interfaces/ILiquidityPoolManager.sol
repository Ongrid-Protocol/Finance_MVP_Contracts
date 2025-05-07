// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "./IERC20.sol";

/**
 * @title ILiquidityPoolManager Interface
 * @dev Interface for the LiquidityPoolManager, which handles pools for funding low-value projects.
 */
interface ILiquidityPoolManager {
    // --- Structs ---
    // (Structs defined here for interface clarity, implementation might import)
    struct PoolInfo {
        bool exists;
        string name;
        uint256 totalAssets; // Total USDC held by the pool (invested + available)
        uint256 totalShares; // Total LP shares issued for the pool
            // Potentially add risk parameters, admin settings etc.
    }

    struct LoanRecord {
        bool exists;
        address developer;
        address devEscrow; // Address of the deployed DevEscrow for this loan
        uint256 principal; // Original principal amount funded
        uint16 aprBps; // Annual Percentage Rate at the time of funding
        uint48 loanTenor; // Loan duration in days
        uint256 principalRepaid; // Principal repaid so far
        uint256 interestAccrued; // Interest accrued/repaid so far (Simplified tracking for MVP)
        uint64 startTime; // Timestamp when the loan was funded
        bool isActive; // Flag if the loan is ongoing
            // Maybe add metadataCID if needed here
    }

    // Project parameters passed from ProjectFactory
    struct ProjectParams {
        uint256 loanAmountRequested; // Now only the 80% financed portion
        uint256 totalProjectCost; // Total cost including deposit (100%)
        uint48 requestedTenor; // in days
        string metadataCID;
    }
    // Add other relevant fields from ProjectFactory if needed

    // --- Events ---
    event PoolCreated(uint256 indexed poolId, string name, address indexed creator);
    event PoolDeposit(uint256 indexed poolId, address indexed investor, uint256 assetsDeposited, uint256 sharesMinted);
    event PoolRedeem(uint256 indexed poolId, address indexed redeemer, uint256 sharesBurned, uint256 assetsWithdrawn);
    event PoolProjectFunded(
        uint256 indexed poolId,
        uint256 indexed projectId,
        address indexed developer,
        address devEscrow,
        uint256 amountFunded,
        uint16 aprBps
    );
    event PoolRepaymentReceived(
        uint256 indexed poolId,
        uint256 indexed projectId,
        address indexed payer,
        uint256 principalReceived,
        uint256 interestReceived
    );

    // --- Pool Management Functions ---

    /**
     * @notice Creates a new liquidity pool.
     * @dev Typically an admin function.
     * @param poolId A unique identifier for the new pool.
     * @param name A descriptive name for the pool.
     */
    function createPool(uint256 poolId, string calldata name) external;

    /**
     * @notice Allows investors to deposit USDC into a specific pool and receive LP shares.
     * @param poolId The ID of the pool to deposit into.
     * @param amount The amount of USDC to deposit.
     * @return shares The amount of LP shares minted to the investor.
     */
    function depositToPool(uint256 poolId, uint256 amount) external returns (uint256 shares);

    /**
     * @notice Allows investors to redeem (burn) their LP shares in exchange for underlying USDC.
     * @param poolId The ID of the pool to redeem from.
     * @param shares The amount of LP shares to burn.
     * @return assets The amount of USDC returned to the investor.
     */
    function redeem(uint256 poolId, uint256 shares) external returns (uint256 assets);

    // --- Project Funding & Repayment ---

    /**
     * @notice Registers a low-value project and attempts to fund it from a suitable pool.
     * @dev Called by the PROJECT_HANDLER_ROLE (ProjectFactory).
     * @param projectId The unique identifier for the project.
     * @param developer The address of the project developer.
     * @param params The parameters of the project (loan amount, tenor, metadata).
     * @return success Boolean indicating if funding was successful.
     * @return poolId The ID of the pool that funded the project (if successful).
     */
    function registerAndFundProject(uint256 projectId, address developer, ProjectParams calldata params)
        external
        returns (bool success, uint256 poolId);

    /**
     * @notice Handles repayments received from the RepaymentRouter for a pool-funded loan.
     * @dev Only callable by the REPAYMENT_HANDLER_ROLE (RepaymentRouter).
     *      Updates the corresponding LoanRecord and the assets within the pool.
     * @param poolId The ID of the pool associated with the loan.
     * @param projectId The ID of the project being repaid.
     * @param netAmountReceived The net amount received after fees.
     * @return principalPaid The portion of the repayment allocated to principal.
     * @return interestPaid The portion of the repayment allocated to interest.
     */
    function handleRepayment(uint256 poolId, uint256 projectId, uint256 netAmountReceived)
        external
        returns (uint256 principalPaid, uint256 interestPaid);

    /**
     * @notice Updates the Annual Percentage Rate (APR) for a specific loan (if needed - might be fixed at funding).
     * @dev Only callable by the RISK_ORACLE_ROLE.
     * @param poolId The ID of the pool managing the loan.
     * @param projectId The ID of the project whose APR is being updated.
     * @param newAprBps The new APR in basis points.
     */
    function updateRiskParams(uint256 poolId, uint256 projectId, uint16 newAprBps) external;

    // --- View Functions ---

    /**
     * @notice Gets the information for a specific liquidity pool.
     * @param poolId The ID of the pool.
     * @return PoolInfo memory The pool's information.
     */
    function getPoolInfo(uint256 poolId) external view returns (PoolInfo memory);

    /**
     * @notice Gets the loan record for a specific project funded by a specific pool.
     * @param poolId The ID of the pool.
     * @param projectId The ID of the project.
     * @return LoanRecord memory The loan's record.
     */
    function getPoolLoanRecord(uint256 poolId, uint256 projectId) external view returns (LoanRecord memory);

    /**
     * @notice Gets the number of LP shares owned by a user in a specific pool.
     * @param poolId The ID of the pool.
     * @param user The address of the user.
     * @return uint256 The number of shares.
     */
    function getUserShares(uint256 poolId, address user) external view returns (uint256);

    /**
     * @notice Calculates the amount of USDC that would be received for redeeming a given number of shares from a pool.
     * @dev Preview function, does not execute redemption.
     * @param poolId The ID of the pool.
     * @param shares The amount of shares to hypothetically redeem.
     * @return uint256 The corresponding amount of USDC.
     */
    function previewRedeem(uint256 poolId, uint256 shares) external view returns (uint256);

    /**
     * @notice Calculates the number of LP shares that would be minted for depositing a given amount of USDC into a pool.
     * @dev Preview function, does not execute deposit.
     * @param poolId The ID of the pool.
     * @param amount The amount of USDC to hypothetically deposit.
     * @return uint256 The corresponding number of LP shares.
     */
    function previewDeposit(uint256 poolId, uint256 amount) external view returns (uint256);
}

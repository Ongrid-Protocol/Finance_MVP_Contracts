// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "./IERC20.sol";

/**
 * @title IProjectVault Interface
 * @dev Interface for the DirectProjectVault contract, managing a single high-value project loan.
 */
interface IProjectVault {
    // --- Structs ---
    struct InitParams {
        address admin;
        address usdcToken;
        address developer;
        address devEscrow;
        address repaymentRouter;
        uint256 projectId;
        uint256 financedAmount;
        uint256 developerDeposit;
        uint48 loanTenor;
        uint16 initialAprBps;
        address depositEscrowAddress;
        address riskOracleAdapter;
    }

    // --- Events ---
    event Invested(address indexed investor, uint256 amountInvested, uint256 totalAssetsInvested);
    event FundingClosed(uint256 projectId, uint256 totalAssetsInvested);
    event RepaymentReceived(uint256 projectId, address indexed payer, uint256 principalAmount, uint256 interestAmount);
    event YieldClaimed(address indexed investor, uint256 amountClaimed);
    event PrincipalClaimed(address indexed investor, uint256 amountClaimed);
    event RiskParamsUpdated(uint256 projectId, uint16 newAprBps);
    event LoanClosed(uint256 projectId, uint256 finalPrincipalRepaid, uint256 finalInterestAccrued);

    // --- Initialization & Configuration ---

    /**
     * @notice Initializes the DirectProjectVault contract.
     * @dev Called once after deployment (UUPS proxy pattern).
     * @param params Struct containing all initialization parameters.
     */
    function initialize(InitParams calldata params) external;

    // --- Core Loan Lifecycle Functions ---

    /**
     * @notice Allows investors to deposit USDC into the vault to fund the project.
     * @dev Reverts if the funding cap (`loanAmount`) is reached or if funding is closed.
     * @param amount The amount of USDC the investor wishes to deposit.
     */
    function invest(uint256 amount) external;

    /**
     * @notice Handles repayments received from the RepaymentRouter.
     * @dev Only callable by the REPAYMENT_HANDLER_ROLE (RepaymentRouter).
     *      Updates the vault's state regarding principal and interest repaid.
     * @param poolId The ID of the pool (unused for Vault, expected 0).
     * @param projectId The ID of the project being repaid.
     * @param netAmountReceived The net amount received after fees.
     * @return principalPaid The portion of the repayment allocated to principal.
     * @return interestPaid The portion of the repayment allocated to interest.
     */
    function handleRepayment(uint256 poolId, uint256 projectId, uint256 netAmountReceived)
        external
        returns (uint256 principalPaid, uint256 interestPaid);

    /**
     * @notice Allows investors to claim their share of the repaid interest.
     * @dev Calculates the claimable interest based on the investor's contribution and repaid interest.
     */
    function claimYield() external;

    /**
     * @notice Allows investors to claim their share of the repaid principal.
     * @dev Calculates the claimable principal based on the investor's contribution and repaid principal.
     */
    function claimPrincipal() external;

    /**
     * @notice Updates the Annual Percentage Rate (APR) for the loan.
     * @dev Only callable by the RISK_ORACLE_ROLE.
     *      Accrues interest up to the current block before applying the new rate.
     * @param newAprBps The new APR in basis points.
     */
    function updateRiskParams(uint16 newAprBps) external;

    /**
     * @notice Marks the loan as closed when it is fully repaid.
     * @dev Can potentially be called internally by handleRepayment or externally by an admin/handler role
     *      once repayment conditions are met.
     */
    function closeLoan() external;

    /**
     * @notice Allows investors to claim both their principal and yield in a single transaction.
     * @dev Calculates and transfers both claimable principal and yield.
     * @return principalAmount The amount of principal claimed.
     * @return yieldAmount The amount of yield claimed.
     */
    function redeem() external returns (uint256 principalAmount, uint256 yieldAmount);

    // --- View Functions ---

    /**
     * @notice Gets the total amount of principal repaid so far.
     */
    function getPrincipalRepaid() external view returns (uint256);

    /**
     * @notice Gets the total amount of assets (USDC) currently invested in the vault.
     */
    function getTotalAssetsInvested() external view returns (uint256);

    /**
     * @notice Gets the total loan amount targeted by this vault.
     */
    function getLoanAmount() external view returns (uint256);

    /**
     * @notice Gets the current Annual Percentage Rate (APR) in Basis Points.
     */
    function getCurrentAprBps() external view returns (uint16);

    /**
     * @notice Calculates the current total outstanding debt (principal + accrued interest).
     * @dev Accrues interest up to the current block time for an accurate reading.
     */
    function totalDebt() external view returns (uint256);

    /**
     * @notice Calculates the amount of claimable interest for a specific investor.
     * @param investor The address of the investor.
     */
    function claimableYield(address investor) external view returns (uint256);

    /**
     * @notice Calculates the amount of claimable principal for a specific investor.
     * @param investor The address of the investor.
     */
    function claimablePrincipal(address investor) external view returns (uint256);

    /**
     * @notice Checks if the loan associated with this vault is closed (fully repaid).
     */
    function isLoanClosed() external view returns (bool);

    /**
     * @notice Checks if the funding period for this vault is closed.
     */
    function isFundingClosed() external view returns (bool);

    // Potentially add other view functions for state variables like developer, projectId, etc.
}

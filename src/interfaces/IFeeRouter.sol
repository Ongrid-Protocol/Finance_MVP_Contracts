// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title IFeeRouter Interface
 * @dev Interface for the FeeRouter contract, responsible for calculating and routing protocol fees.
 */
interface IFeeRouter {
    /**
     * @dev Emitted when calculated fees are routed to their respective treasuries.
     * @param repaymentRouter The address initiating the fee routing (RepaymentRouter).
     * @param totalFeeAmount The total amount of fee collected before distribution.
     * @param protocolTreasuryAmount The amount sent to the protocol treasury.
     * @param carbonTreasuryAmount The amount sent to the carbon treasury.
     */
    event FeeRouted(
        address indexed repaymentRouter,
        uint256 totalFeeAmount,
        uint256 protocolTreasuryAmount,
        uint256 carbonTreasuryAmount
    );

    /**
     * @notice Stores project details necessary for fee calculations.
     * @dev Called by authorized contracts (PROJECT_HANDLER_ROLE: ProjectFactory, Vault, PoolManager)
     *      when a project is created or funded.
     * @param projectId The unique identifier of the project.
     * @param loanAmount The total loan amount for the project.
     * @param developer The address of the project developer.
     * @param creationTime The timestamp when the project funding started (or was created).
     */
    function setProjectDetails(uint256 projectId, uint256 loanAmount, address developer, uint64 creationTime)
        external;

    /**
     * @notice Calculates the Capital Raising Fee for a project.
     * @dev This fee is typically applied once when the project is funded.
     *      The calculation depends on whether the developer is a first-time borrower.
     * @param projectId The unique identifier of the project.
     * @param developer The address of the project developer.
     * @return uint256 The calculated capital raising fee amount in USDC.
     */
    function calculateCapitalRaisingFee(uint256 projectId, address developer) external view returns (uint256);

    /**
     * @notice Calculates the Management Fee (AUM Fee) accrued for a project since the last calculation.
     * @dev This fee is based on the outstanding principal, tiered APR based on total AUM,
     *      and the time elapsed since the last fee calculation or project start.
     * @param projectId The unique identifier of the project.
     * @param outstandingPrincipal The current outstanding principal balance of the loan.
     * @return uint256 The calculated management fee amount accrued in USDC.
     */
    function calculateManagementFee(uint256 projectId, uint256 outstandingPrincipal) external view returns (uint256);

    /**
     * @notice Calculates the Transaction Fee for a given transaction amount (e.g., repayment, drawdown).
     * @dev Applies tiered BPS based on the transaction amount, with no hard cap.
     * @param transactionAmount The amount of the transaction subject to the fee.
     * @return uint256 The calculated transaction fee amount in USDC.
     */
    function calculateTransactionFee(uint256 transactionAmount) external view returns (uint256);

    /**
     * @notice Routes a calculated fee amount to the protocol and carbon treasuries.
     * @dev Called by the REPAYMENT_ROUTER_ROLE (RepaymentRouter) after calculating the total fee.
     *      Internally splits the `feeAmount` based on predefined percentages.
     * @param feeAmount The total fee amount to be split and transferred.
     */
    function routeFees(uint256 feeAmount) external;

    /**
     * @notice Updates the timestamp for the last management fee calculation for a project.
     * @dev Called internally or by an authorized role after management fees are processed.
     * @param projectId The unique identifier of the project.
     */
    function updateLastMgmtFeeTimestamp(uint256 projectId) external;

    /**
     * @notice Gets the address of the designated protocol treasury.
     * @return address The protocol treasury address.
     */
    function getProtocolTreasury() external view returns (address);

    /**
     * @notice Gets the address of the designated carbon treasury.
     * @return address The carbon treasury address.
     */
    function getCarbonTreasury() external view returns (address);
}

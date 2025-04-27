// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title IRiskRateOracleAdapter Interface
 * @dev Interface for the RiskRateOracleAdapter contract.
 */
interface IRiskRateOracleAdapter {
    /**
     * @notice Sets or updates the target contract address for a given project ID.
     * @param projectId The unique identifier of the project.
     * @param targetContract The address of the DirectProjectVault or LiquidityPoolManager.
     * @param poolId The ID of the pool managing the project (only relevant if targetContract is a PoolManager, otherwise use 0).
     */
    function setTargetContract(uint256 projectId, address targetContract, uint256 poolId) external;

    /**
     * @notice Pushes risk parameters (APR, optional Tenor) to the target contract associated with the project ID.
     * @param projectId The unique identifier of the project receiving the update.
     * @param aprBps The new Annual Percentage Rate in basis points (1% = 100 BPS).
     * @param tenor The new loan tenor in days (optional, may not be applicable post-funding, use 0 if unchanged).
     */
    function pushRiskParams(uint256 projectId, uint16 aprBps, uint48 tenor) external;

    /**
     * @notice Gets the target contract address registered for a specific project ID.
     * @param projectId The project ID.
     * @return address The target contract address (Vault or PoolManager).
     */
    function getTargetContract(uint256 projectId) external view returns (address);

    /**
     * @notice Gets the pool ID registered for a specific project ID (if applicable).
     * @param projectId The project ID.
     * @return uint256 The pool ID, or 0 if not a pool-managed project or not set.
     */
    function getPoolId(uint256 projectId) external view returns (uint256);
} 
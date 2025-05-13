// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title IRepaymentRouter Interface
 * @dev Interface for the RepaymentRouter contract, defining functions callable by other contracts.
 */
interface IRepaymentRouter {
    /**
     * @notice Sets or updates the funding source contract (Vault/Pool) for a given project ID.
     * @dev Typically called by ProjectFactory or LiquidityPoolManager.
     * @param projectId The unique identifier of the project.
     * @param fundingSource The address of the `DirectProjectVault` or `LiquidityPoolManager`.
     * @param poolId The ID of the pool if `fundingSource` is a PoolManager, otherwise 0.
     */
    function setFundingSource(uint256 projectId, address fundingSource, uint256 poolId) external;

    // Add other functions from RepaymentRouter that ProjectFactory or LiquidityPoolManager might need to call
    // For now, only setFundingSource is explicitly cast to and called.
    // View functions like getFundingSource and getPoolId could also be added if needed.
}

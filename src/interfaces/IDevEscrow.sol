// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "./IERC20.sol";

/**
 * @title IDevEscrow Interface
 * @dev Interface for the DevEscrow contract, which now primarily tracks funding events.
 *      No longer manages milestone-based fund releases.
 */
interface IDevEscrow {
    /**
     * @dev Emitted when the escrow contract logs a funding event.
     * @param fundingSource The address that funded the project.
     * @param amount The amount of USDC allocated.
     */
    event EscrowFunded(address indexed fundingSource, uint256 amount);

    /**
     * @dev Emitted when funding is complete and sent directly to developer.
     * @param developer The address of the developer who received funds.
     * @param amount The amount of USDC sent to developer.
     */
    event FundingComplete(address indexed developer, uint256 amount);

    /**
     * @notice Records a funding event in the escrow.
     * @dev Should only be callable by the designated funding source.
     * @param amount The amount of USDC allocated for the project.
     */
    function fundEscrow(uint256 amount) external;

    /**
     * @notice Notifies that funding has been completed and sent to developer.
     * @dev Called by funding source after transferring funds to developer.
     * @param amount The amount that was sent to the developer.
     */
    function notifyFundingComplete(uint256 amount) external;

    /**
     * @notice Gets the total amount allocated to this project.
     * @return uint256 The total USDC amount allocated.
     */
    function getTotalAllocated() external view returns (uint256);

    /**
     * @notice Gets the total amount withdrawn by the developer.
     * @return uint256 The total USDC amount withdrawn (always 0 in new model).
     */
    function getTotalWithdrawn() external view returns (uint256);

    /**
     * @notice Gets the developer address associated with this project.
     * @return address The developer's address.
     */
    function getDeveloper() external view returns (address);

    /**
     * @notice Gets the funding source address associated with this project.
     * @return address The funding source's address.
     */
    function getFundingSource() external view returns (address);
}

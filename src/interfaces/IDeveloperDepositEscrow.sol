// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "./IERC20.sol";

/**
 * @title IDeveloperDepositEscrow Interface
 * @dev Interface for the DeveloperDepositEscrow contract, which handles the 20% upfront deposit.
 */
interface IDeveloperDepositEscrow {
    /**
     * @dev Emitted when a developer's deposit is successfully funded for a project.
     * @param projectId The unique identifier of the project.
     * @param developer The address of the developer providing the deposit.
     * @param amount The amount of USDC deposited.
     */
    event DepositFunded(uint256 indexed projectId, address indexed developer, uint256 amount);

    /**
     * @dev Emitted when a developer's deposit is released back upon successful loan completion.
     * @param projectId The unique identifier of the project.
     * @param developer The address of the developer receiving the deposit back.
     * @param amount The amount of USDC released.
     */
    event DepositReleased(uint256 indexed projectId, address indexed developer, uint256 amount);

    /**
     * @dev Emitted when a developer's deposit is slashed due to default or other reasons.
     * @param projectId The unique identifier of the project.
     * @param developer The address of the developer whose deposit was slashed.
     * @param amount The amount of USDC slashed.
     * @param recipient The address receiving the slashed funds (e.g., fee recipient or treasury).
     */
    event DepositSlashed(uint256 indexed projectId, address indexed developer, uint256 amount, address recipient);

    /**
     * @notice Funds the deposit escrow for a specific project.
     * @dev Called by an authorized contract (e.g., ProjectFactory) after verifying the developer.
     *      The escrow contract pulls the required deposit amount from the developer's address.
     * @param projectId The unique identifier for the project.
     * @param developer The address of the project developer providing the deposit.
     * @param amount The required deposit amount (e.g., 20% of the loan amount).
     */
    function fundDeposit(uint256 projectId, address developer, uint256 amount) external;

    /**
     * @notice Releases the deposit back to the developer.
     * @dev Called by an authorized role (RELEASER_ROLE) upon successful project completion.
     * @param projectId The unique identifier for the project whose deposit is to be released.
     */
    function releaseDeposit(uint256 projectId) external;

    /**
     * @notice Slashes the deposit and sends it to a designated recipient.
     * @dev Called by an authorized role (SLASHER_ROLE) in case of project default.
     * @param projectId The unique identifier for the project whose deposit is to be slashed.
     * @param feeRecipient The address to receive the slashed funds.
     */
    function slashDeposit(uint256 projectId, address feeRecipient) external;

    /**
     * @notice Gets the amount deposited for a specific project.
     * @param projectId The unique identifier for the project.
     * @return uint256 The amount deposited.
     */
    function getDepositAmount(uint256 projectId) external view returns (uint256);

    /**
     * @notice Gets the developer associated with a specific project's deposit.
     * @param projectId The unique identifier for the project.
     * @return address The developer's address.
     */
    function getProjectDeveloper(uint256 projectId) external view returns (address);

    /**
     * @notice Checks if the deposit for a specific project has been released.
     * @param projectId The unique identifier for the project.
     * @return bool True if the deposit has been released, false otherwise.
     */
    function isDepositSettled(uint256 projectId) external view returns (bool);
} 
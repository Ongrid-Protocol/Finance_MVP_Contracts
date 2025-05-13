// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title IPausableGovernor Interface
 * @dev Interface for the PausableGovernor contract, providing centralized pausing control.
 */
interface IPausableGovernor {
    /**
     * @dev Emitted when a contract is added to the list of pausable contracts.
     * @param target The address of the contract added.
     * @param admin The address that performed the action.
     */
    event PausableContractAdded(address indexed target, address indexed admin);

    /**
     * @dev Emitted when a contract is removed from the list of pausable contracts.
     * @param target The address of the contract removed.
     * @param admin The address that performed the action.
     */
    event PausableContractRemoved(address indexed target, address indexed admin);

    /**
     * @dev Emitted when a target contract is paused via the governor.
     * @param target The address of the contract paused.
     * @param pauser The address that initiated the pause.
     */
    event Paused(address indexed target, address indexed pauser);

    /**
     * @dev Emitted when a target contract is unpaused via the governor.
     * @param target The address of the contract unpaused.
     * @param unpauser The address that initiated the unpause.
     */
    event Unpaused(address indexed target, address indexed unpauser);

    /**
     * @dev Emitted when a warning occurs during pause/unpause operations.
     * @param target The address of the target contract.
     * @param warning The warning message.
     */
    event PauseWarning(address indexed target, string warning);

    /**
     * @notice Adds a contract address to the list of contracts managed by this governor.
     * @dev Only callable by the DEFAULT_ADMIN_ROLE.
     * @param target The address of the pausable contract to add.
     */
    function addPausableContract(address target) external;

    /**
     * @notice Removes a contract address from the list of contracts managed by this governor.
     * @dev Only callable by the DEFAULT_ADMIN_ROLE.
     * @param target The address of the pausable contract to remove.
     */
    function removePausableContract(address target) external;

    /**
     * @notice Pauses a specific target contract.
     * @dev Only callable by the PAUSER_ROLE.
     *      Requires the target contract to be registered with the governor.
     *      Calls the `pause()` function on the target contract.
     * @param target The address of the contract to pause.
     */
    function pause(address target) external;

    /**
     * @notice Unpauses a specific target contract.
     * @dev Only callable by the PAUSER_ROLE.
     *      Requires the target contract to be registered with the governor.
     *      Calls the `unpause()` function on the target contract.
     * @param target The address of the contract to unpause.
     */
    function unpause(address target) external;

    /**
     * @notice Checks if a contract address is registered as pausable by this governor.
     * @param target The address to check.
     * @return bool True if the contract is managed by the governor, false otherwise.
     */
    function isPausableContract(address target) external view returns (bool);
}

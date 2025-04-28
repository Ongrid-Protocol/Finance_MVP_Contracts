// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol"; // Needed for target interface
import {Constants} from "../common/Constants.sol";
import {Errors} from "../common/Errors.sol";
import {IPausableGovernor} from "../interfaces/IPausableGovernor.sol";

/**
 * @title PausableGovernor
 * @dev Centralized admin control for pausing/unpausing registered pausable contracts.
 *      Relies on target contracts inheriting OpenZeppelin's Pausable.
 */
contract PausableGovernor is AccessControlEnumerable, IPausableGovernor {
    // --- State Variables ---

    /**
     * @dev Mapping storing the addresses of contracts that can be paused/unpaused by this governor.
     *      address => isPausable
     */
    mapping(address => bool) public pausableContracts;

    // --- Constructor ---
    /**
     * @notice Initializes the governor and grants initial roles.
     * @param _admin The address to grant initial admin and pauser roles.
     */
    constructor(address _admin) {
        if (_admin == address(0)) revert Errors.ZeroAddressNotAllowed();

        _grantRole(Constants.DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(Constants.PAUSER_ROLE, _admin); // Admin can also pause/unpause
    }

    // --- Contract Management ---

    /**
     * @inheritdoc IPausableGovernor
     */
    function addPausableContract(address target) external override onlyRole(Constants.DEFAULT_ADMIN_ROLE) {
        if (target == address(0)) revert Errors.ZeroAddressNotAllowed();
        if (pausableContracts[target]) revert Errors.InvalidValue("Contract already added"); // Consider specific error

        pausableContracts[target] = true;
        emit PausableContractAdded(target, msg.sender);
    }

    /**
     * @inheritdoc IPausableGovernor
     */
    function removePausableContract(address target) external override onlyRole(Constants.DEFAULT_ADMIN_ROLE) {
        if (!pausableContracts[target]) revert Errors.InvalidValue("Contract not found"); // Consider specific error

        delete pausableContracts[target];
        emit PausableContractRemoved(target, msg.sender);
    }

    // --- Pausing Control ---

    /**
     * @inheritdoc IPausableGovernor
     */
    function pause(address target) external override onlyRole(Constants.PAUSER_ROLE) {
        _checkPausable(target);
        // Use low-level call with signature
        (bool success, bytes memory returnData) = target.call(abi.encodeWithSignature("pause()"));
        if (!success) {
            // Try to decode the revert reason
            if (returnData.length > 0) {
                string memory reason = abi.decode(returnData, (string));
                revert(string(abi.encodePacked("Target pause failed: ", reason)));
            } else {
                revert Errors.InvalidState("Target pause failed (low level)");
            }
        }
        emit Paused(target, msg.sender);
    }

    /**
     * @inheritdoc IPausableGovernor
     */
    function unpause(address target) external override onlyRole(Constants.PAUSER_ROLE) {
        _checkPausable(target);
        // Use low-level call with signature
        (bool success, bytes memory returnData) = target.call(abi.encodeWithSignature("unpause()"));
        if (!success) {
            // Try to decode the revert reason
            if (returnData.length > 0) {
                string memory reason = abi.decode(returnData, (string));
                revert(string(abi.encodePacked("Target unpause failed: ", reason)));
            } else {
                revert Errors.InvalidState("Target unpause failed (low level)");
            }
        }
        emit Unpaused(target, msg.sender);
    }

    // --- Internal Helpers ---

    /**
     * @dev Internal function to check if a target address is registered as pausable.
     */
    function _checkPausable(address target) internal view {
        if (!pausableContracts[target]) revert Errors.InvalidValue("Target contract not pausable via governor");
    }

    // --- View Functions ---

    /**
     * @inheritdoc IPausableGovernor
     */
    function isPausableContract(address target) external view override returns (bool) {
        return pausableContracts[target];
    }

    // --- Access Control Overrides ---

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControlEnumerable)
        returns (bool)
    {
        return type(IPausableGovernor).interfaceId == interfaceId || super.supportsInterface(interfaceId);
    }
}

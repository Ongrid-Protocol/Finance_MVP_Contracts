// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol"; // Needed for target interface
import {Constants} from "../common/Constants.sol";
import {Errors} from "../common/Errors.sol";
import {IPausableGovernor} from "../interfaces/IPausableGovernor.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

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

    // For interface detection
    bytes4 private constant PAUSE_SELECTOR = bytes4(keccak256("pause()"));
    bytes4 private constant UNPAUSE_SELECTOR = bytes4(keccak256("unpause()"));

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
        if (pausableContracts[target]) revert Errors.InvalidValue("Contract already added");

        // Verify the target contract implements the required pause/unpause functions
        if (!_supportsPauseInterface(target)) {
            revert Errors.InvalidValue("Target contract does not support pause/unpause interface");
        }

        pausableContracts[target] = true;
        emit PausableContractAdded(target, msg.sender);
    }

    /**
     * @inheritdoc IPausableGovernor
     */
    function removePausableContract(address target) external override onlyRole(Constants.DEFAULT_ADMIN_ROLE) {
        if (!pausableContracts[target]) revert Errors.InvalidValue("Contract not found");

        delete pausableContracts[target];
        emit PausableContractRemoved(target, msg.sender);
    }

    /**
     * @dev Checks if a contract supports the pause/unpause interface using both ERC165 checking
     * and direct function existence checking to support non-ERC165 compliant contracts.
     * @param target The address of the contract to check
     * @return bool True if the contract supports pause/unpause, false otherwise
     */
    function _supportsPauseInterface(address target) internal view returns (bool) {
        // First try using ERC165 interface detection (OZ Pausable doesn't declare ERC165 though)
        try IERC165(target).supportsInterface(bytes4(keccak256("pause()")) ^ bytes4(keccak256("unpause()"))) returns (
            bool support
        ) {
            if (support) return true;
        } catch {
            // ERC165 check failed, try direct function calls
        }

        // Check if pause function exists
        (bool pauseSuccess,) = target.staticcall(abi.encodeWithSelector(PAUSE_SELECTOR));

        // Check if unpause function exists
        (bool unpauseSuccess,) = target.staticcall(abi.encodeWithSelector(UNPAUSE_SELECTOR));

        // The calls might revert due to access control, but that means the functions exist
        return pauseSuccess || unpauseSuccess;
    }

    // --- Pausing Control ---

    /**
     * @inheritdoc IPausableGovernor
     */
    function pause(address target) external override onlyRole(Constants.PAUSER_ROLE) {
        _checkPausable(target);

        // Use low-level call with signature but now with better error handling and checks
        // First try to check if target implements AccessControl and has granted PAUSER_ROLE
        (bool hasRoleSuccess, bytes memory hasRoleData) =
            target.staticcall(abi.encodeWithSignature("hasRole(bytes32,address)", Constants.PAUSER_ROLE, address(this)));

        // If target has AccessControl but we don't have PAUSER_ROLE, this is a warning situation
        // We'll allow the call to proceed, but it might fail if target enforces role checks
        if (hasRoleSuccess && !abi.decode(hasRoleData, (bool))) {
            // Don't revert, but log a warning via event
            emit PauseWarning(target, "Target might not have granted PAUSER_ROLE to this governor");
        }

        // Now make the actual pause call
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

        // Similar check for unpause as for pause
        (bool hasRoleSuccess, bytes memory hasRoleData) =
            target.staticcall(abi.encodeWithSignature("hasRole(bytes32,address)", Constants.PAUSER_ROLE, address(this)));

        if (hasRoleSuccess && !abi.decode(hasRoleData, (bool))) {
            emit PauseWarning(target, "Target might not have granted PAUSER_ROLE to this governor");
        }

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

    /**
     * @notice Checks if a contract supports the pause/unpause interface without adding it
     * @param target The address of the contract to check
     * @return bool True if the contract supports pause/unpause, false otherwise
     */
    function checkPauseInterfaceSupport(address target) external view returns (bool) {
        return _supportsPauseInterface(target);
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

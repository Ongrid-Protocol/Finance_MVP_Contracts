// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Constants} from "../common/Constants.sol";
import {Errors} from "../common/Errors.sol";
import {IDeveloperDepositEscrow} from "../interfaces/IDeveloperDepositEscrow.sol"; // Import interface
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/**
 * @title DeveloperDepositEscrow
 * @dev Holds the 20% upfront deposit from developers for their projects.
 *      Funds are locked until the loan is completed (released) or defaulted (slashed).
 *      Access is controlled via roles.
 */
contract DeveloperDepositEscrow is
    AccessControlEnumerable,
    Pausable,
    ReentrancyGuard,
    IDeveloperDepositEscrow // Implement the interface
{
    using SafeERC20 for IERC20;

    // --- State Variables ---
    /**
     * @dev The USDC token contract address.
     */
    IERC20 public immutable usdcToken;

    /**
     * @dev Mapping from project ID to the amount of USDC deposited.
     */
    mapping(uint256 => uint256) public depositAmount;

    /**
     * @dev Mapping from project ID to the developer who made the deposit.
     */
    mapping(uint256 => address) public projectDeveloper;

    /**
     * @dev Mapping from project ID to a flag indicating if the deposit has been released or slashed.
     */
    mapping(uint256 => bool) public depositSettled; // Renamed from depositReleased for clarity (covers release/slash)

    // --- Constructor ---
    /**
     * @notice Sets the USDC token address and grants initial roles to the deployer.
     * @param _usdcToken The address of the USDC token contract.
     */
    constructor(address _usdcToken) {
        if (_usdcToken == address(0)) revert Errors.ZeroAddressNotAllowed();
        usdcToken = IERC20(_usdcToken);

        // Grant deployer admin, pauser, releaser, and slasher roles initially
        // These roles might be transferred or granted to other contracts/admins later.
        address deployer = msg.sender;
        _grantRole(Constants.DEFAULT_ADMIN_ROLE, deployer);
        _grantRole(Constants.PAUSER_ROLE, deployer);
        _grantRole(Constants.RELEASER_ROLE, deployer); // ProjectFactory likely needs this role
        _grantRole(Constants.SLASHER_ROLE, deployer); // Admin likely needs this role
    }

    // --- Core Functions ---

    /**
     * @notice Funds the deposit for a specific project by transferring USDC from the developer.
     * @dev Requires caller to have `DEPOSIT_FUNDER_ROLE` (intended to be ProjectFactory).
     *      Checks that the deposit hasn't already been funded for the given project ID.
     * @param projectId The unique identifier for the project.
     * @param developer The address of the project developer providing the deposit.
     * @param amount The required deposit amount (e.g., 20% of loan amount).
     */
    function fundDeposit(uint256 projectId, address developer, uint256 amount)
        external
        override // from IDeveloperDepositEscrow
        nonReentrant
        whenNotPaused
        onlyRole(Constants.DEPOSIT_FUNDER_ROLE)
    {
        if (developer == address(0)) revert Errors.ZeroAddressNotAllowed();
        if (amount == 0) revert Errors.AmountCannotBeZero();
        if (depositAmount[projectId] != 0) revert Errors.DepositAlreadyExists(projectId);
        if (depositSettled[projectId]) revert Errors.DepositAlreadyReleased(projectId); // Or slashed

        // Store deposit details
        depositAmount[projectId] = amount;
        projectDeveloper[projectId] = developer;
        // depositSettled remains false

        // Pull the deposit amount from the developer
        // Requires the developer to have approved this contract to spend their USDC.
        usdcToken.safeTransferFrom(developer, address(this), amount);

        emit DepositFunded(projectId, developer, amount);
    }

    /**
     * @notice Releases the deposit back to the developer upon successful project completion.
     * @dev Requires caller to have `RELEASER_ROLE`.
     *      Checks that the deposit exists and hasn't already been settled.
     * @param projectId The unique identifier for the project whose deposit is to be released.
     */
    function releaseDeposit(uint256 projectId)
        external
        override // from IDeveloperDepositEscrow
        nonReentrant
        whenNotPaused
        onlyRole(Constants.RELEASER_ROLE)
    {
        uint256 amount = depositAmount[projectId];
        address developer = projectDeveloper[projectId];

        if (amount == 0) revert Errors.DepositNotFound(projectId);
        if (depositSettled[projectId]) revert Errors.DepositAlreadyReleased(projectId);

        // Mark as settled
        depositSettled[projectId] = true;

        // Transfer the deposit back to the developer
        usdcToken.safeTransfer(developer, amount);

        emit DepositReleased(projectId, developer, amount);
    }

    /**
     * @notice Slashes the deposit and transfers it to a designated fee recipient (e.g., treasury) on default.
     * @dev Requires caller to have `SLASHER_ROLE`.
     *      Checks that the deposit exists and hasn't already been settled.
     * @param projectId The unique identifier for the project whose deposit is to be slashed.
     * @param feeRecipient The address to receive the slashed funds.
     */
    function slashDeposit(uint256 projectId, address feeRecipient)
        external
        override // from IDeveloperDepositEscrow
        nonReentrant
        whenNotPaused
        onlyRole(Constants.SLASHER_ROLE)
    {
        if (feeRecipient == address(0)) revert Errors.ZeroAddressNotAllowed();

        uint256 amount = depositAmount[projectId];
        address developer = projectDeveloper[projectId]; // Get developer for event emission

        if (amount == 0) revert Errors.DepositNotFound(projectId);
        if (depositSettled[projectId]) revert Errors.DepositAlreadyReleased(projectId);

        // Mark as settled
        depositSettled[projectId] = true;

        // Transfer the deposit to the fee recipient
        usdcToken.safeTransfer(feeRecipient, amount);

        emit DepositSlashed(projectId, developer, amount, feeRecipient);
    }

    /**
     * @notice Transfers the deposit to the project upon funding.
     * @dev Requires caller to have `RELEASER_ROLE`.
     *      Checks that the deposit exists and hasn't already been settled.
     * @param projectId The unique identifier for the project whose deposit is to be transferred.
     * @return uint256 The amount transferred.
     */
    function transferDepositToProject(uint256 projectId)
        external
        nonReentrant
        whenNotPaused
        onlyRole(Constants.RELEASER_ROLE)
        returns (uint256)
    {
        uint256 amount = depositAmount[projectId];
        address developer = projectDeveloper[projectId];

        if (amount == 0) revert Errors.DepositNotFound(projectId);
        if (depositSettled[projectId]) revert Errors.DepositAlreadyReleased(projectId);

        // Mark as settled
        depositSettled[projectId] = true;

        // Transfer the deposit back to the developer
        usdcToken.safeTransfer(developer, amount);

        emit DepositReleased(projectId, developer, amount);
        return amount;
    }

    // --- View Functions ---

    /**
     * @notice Gets the amount deposited for a specific project.
     * @param projectId The unique identifier for the project.
     * @return uint256 The amount deposited.
     */
    function getDepositAmount(uint256 projectId) external view override returns (uint256) {
        return depositAmount[projectId];
    }

    /**
     * @notice Gets the developer associated with a specific project's deposit.
     * @param projectId The unique identifier for the project.
     * @return address The developer's address.
     */
    function getProjectDeveloper(uint256 projectId) external view override returns (address) {
        return projectDeveloper[projectId];
    }

    /**
     * @notice Checks if the deposit for a specific project has been settled (released or slashed).
     * @param projectId The unique identifier for the project.
     * @return bool True if the deposit has been settled, false otherwise.
     */
    function isDepositSettled(uint256 projectId) external view returns (bool) {
        // Renamed view function
        return depositSettled[projectId];
    }

    // --- Pausable Functions ---

    /**
     * @notice Pauses the contract.
     * @dev Requires caller to have `PAUSER_ROLE`.
     */
    function pause() external onlyRole(Constants.PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses the contract.
     * @dev Requires caller to have `PAUSER_ROLE`.
     */
    function unpause() external onlyRole(Constants.PAUSER_ROLE) {
        _unpause();
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
        return super.supportsInterface(interfaceId);
    }

    // --- Admin Functions ---

    /**
     * @notice Explicitly override grantRole to resolve multiple inheritance.
     * @dev Required because the contract inherits the same function signature
     *      from both AccessControlEnumerable and IDeveloperDepositEscrow.
     * @param role The role to grant.
     * @param account The address to grant the role to.
     */
    function grantRole(bytes32 role, address account)
        public
        virtual
        override(AccessControl, IAccessControl, IDeveloperDepositEscrow)
        onlyRole(getRoleAdmin(role))
    {
        super.grantRole(role, account);
    }

    /**
     * @notice Allows the DEFAULT_ADMIN_ROLE to set the admin for any role.
     * @dev This is a privileged function for setup and emergency adjustments.
     * @param role The role whose admin is to be changed.
     * @param adminRole The role that will become the new admin of `role`.
     */
    function setRoleAdminExternally(bytes32 role, bytes32 adminRole) external onlyRole(Constants.DEFAULT_ADMIN_ROLE) {
        _setRoleAdmin(role, adminRole);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Constants} from "../common/Constants.sol";
import {Errors} from "../common/Errors.sol";
import {IDevEscrow} from "../interfaces/IDevEscrow.sol"; // Import interface
import {IProjectVault} from "../interfaces/IProjectVault.sol"; // Interface for callback
// Note: ILiquidityPoolManager interface might also be needed if pools require a callback.
// For now, assuming only Vault needs a callback (`triggerDrawdown`).

/**
 * @title DevEscrow
 * @dev Holds funds for a specific project and releases tranches to the developer upon milestone authorization.
 *      Instantiated per project by ProjectFactory (for Vaults) or LiquidityPoolManager (for Pools).
 *      Access controlled by roles.
 */
contract DevEscrow is
    Initializable,
    AccessControlEnumerable,
    Pausable,
    ReentrancyGuard,
    IDevEscrow // Implement the interface
{
    using SafeERC20 for IERC20;

    // --- State Variables ---

    /**
     * @dev Basic details about a milestone.
     */
    struct Milestone {
        uint256 amount; // Amount allocated to this milestone
        bool authorized; // Whether the milestone is authorized for withdrawal
        bool withdrawn; // Whether the funds for this milestone have been withdrawn
    }

    // Changed from immutable to support initializer pattern
    IERC20 public usdcToken;
    address public developer;
    address public fundingSource; // Address of the Vault or PoolManager that funded this escrow
    uint256 public totalAllocated; // Total amount expected/received from the funding source
    uint256 public totalWithdrawn; // Total amount withdrawn by the developer across all milestones
    uint256 public totalMilestoneAmountSet; // Sum of amounts defined in set milestones

    /**
     * @dev Mapping from milestone index (uint8) to milestone details.
     *      Using uint8 limits to 256 milestones per project.
     */
    mapping(uint8 => Milestone) public milestones;
    uint8 public milestoneCount; // Number of milestones set

    // --- Constructor ---
    /**
     * @notice Initializes the DevEscrow for a specific project.
     * @dev To be called once after cloning.
     * @param _usdcToken Address of the USDC token contract.
     * @param _developer Address of the project developer who can withdraw funds.
     * @param _fundingSource Address of the contract funding this escrow (Vault or PoolManager).
     * @param _totalAllocated The total amount of USDC this escrow expects to manage for the project.
     * @param _milestoneAuthorizer Address granted the role to authorize milestones.
     * @param _pauser Address granted the pauser role (can be the admin/funding source).
     */
    function initialize(
        address _usdcToken,
        address _developer,
        address _fundingSource,
        uint256 _totalAllocated,
        address _milestoneAuthorizer,
        address _pauser
    ) public initializer {
        if (
            _usdcToken == address(0) || _developer == address(0) || _fundingSource == address(0)
                || _milestoneAuthorizer == address(0) || _pauser == address(0)
        ) {
            revert Errors.ZeroAddressNotAllowed();
        }
        if (_totalAllocated == 0) revert Errors.AmountCannotBeZero();

        // Assign to state variables
        usdcToken = IERC20(_usdcToken);
        developer = _developer;
        fundingSource = _fundingSource;
        totalAllocated = _totalAllocated;

        // Grant roles:
        // - Funding source gets DEFAULT_ADMIN_ROLE (can fund, set milestones)
        _grantRole(Constants.DEFAULT_ADMIN_ROLE, _fundingSource);
        // - Designated authorizer gets MILESTONE_AUTHORIZER_ROLE
        _grantRole(Constants.MILESTONE_AUTHORIZER_ROLE, _milestoneAuthorizer);
        // - Designated pauser gets PAUSER_ROLE
        _grantRole(Constants.PAUSER_ROLE, _pauser);
        // - Grant admin role to funding source as well for general admin tasks if needed
        // _grantRole(Constants.DEFAULT_ADMIN_ROLE, _fundingSource); // Already granted
    }

    // --- Funding & Milestone Setup ---

    /**
     * @notice Receives funds from the designated funding source.
     * @dev Can only be called by the `DEFAULT_ADMIN_ROLE` (which is the `fundingSource`).
     *      Uses `transferFrom` assuming the funding source approved the escrow.
     *      This function might not be strictly necessary if funds are sent upon construction or via direct transfer,
     *      but provides a clear entry point.
     *      We'll assume funds are transferred directly upon deployment by Factory/PoolManager,
     *      so this function mainly serves as an explicit interface point and event emitter.
     *      The actual transfer logic resides in the caller (Factory/PoolManager).
     * @param amount The amount being funded (should match `totalAllocated` eventually).
     */
    function fundEscrow(uint256 amount)
        external
        override // from IDevEscrow
        nonReentrant
        whenNotPaused
        onlyRole(Constants.DEFAULT_ADMIN_ROLE) // Only fundingSource can call
    {
        // Check if caller is the designated funding source (redundant with onlyRole but explicit)
        if (msg.sender != fundingSource) revert Errors.CallerNotFundingSource(msg.sender, fundingSource);
        if (amount == 0) revert Errors.AmountCannotBeZero();

        // Check if funding exceeds total allocated (optional, might receive in tranches)
        // uint256 currentBalance = usdcToken.balanceOf(address(this));
        // if (currentBalance + amount > totalAllocated) revert Errors.ExceedsTotalAllocation(currentBalance + amount, totalAllocated);

        // The actual USDC transfer should happen *before* this call, initiated by the fundingSource.
        // This function primarily acknowledges the funding for event emission.
        // Alternatively, could perform the safeTransferFrom here if fundingSource approves this contract.
        // For simplicity, let's assume transfer happens outside and this just logs the event.

        emit EscrowFunded(fundingSource, amount);
    }

    /**
     * @notice Defines a funding milestone.
     * @dev Can only be called by the `DEFAULT_ADMIN_ROLE` (the `fundingSource`).
     *      The sum of all milestone amounts must eventually equal `totalAllocated`.
     * @param index The index of the milestone (0, 1, 2...). Must be sequential.
     * @param amount The USDC amount allocated to this milestone.
     */
    function setMilestone(uint8 index, uint256 amount)
        external
        override // from IDevEscrow
        whenNotPaused
        onlyRole(Constants.DEFAULT_ADMIN_ROLE)
    {
        if (msg.sender != fundingSource) revert Errors.CallerNotFundingSource(msg.sender, fundingSource);
        if (amount == 0) revert Errors.AmountCannotBeZero();
        if (index != milestoneCount) revert Errors.MilestoneIndexOutOfBounds(index, milestoneCount); // Ensure sequential setting
        if (milestones[index].amount > 0) revert Errors.MilestoneAlreadySet(index);

        uint256 newTotalMilestoneAmount = totalMilestoneAmountSet + amount;
        if (newTotalMilestoneAmount > totalAllocated) {
            revert Errors.MilestoneAmountExceedsAllocation(amount, totalAllocated - totalMilestoneAmountSet);
        }

        milestones[index] = Milestone({amount: amount, authorized: false, withdrawn: false});
        totalMilestoneAmountSet = newTotalMilestoneAmount;
        milestoneCount++;

        emit MilestoneSet(index, amount);
    }

    /**
     * @notice Authorizes a milestone for withdrawal.
     * @dev Can only be called by the `MILESTONE_AUTHORIZER_ROLE`.
     * @param index The index of the milestone to authorize.
     */
    function authorizeMilestone(uint8 index)
        external
        override // from IDevEscrow
        whenNotPaused
        onlyRole(Constants.MILESTONE_AUTHORIZER_ROLE)
    {
        if (index >= milestoneCount) revert Errors.MilestoneIndexOutOfBounds(index, milestoneCount);
        Milestone storage milestone = milestones[index];
        if (milestone.amount == 0) revert Errors.InvalidValue("Milestone not set"); // Should not happen if index < milestoneCount
        if (milestone.authorized) revert Errors.MilestoneAlreadySet(index); // Re-use error? Or new one? Let's use InvalidState
        // if (milestone.authorized) revert Errors.InvalidState("Milestone already authorized");

        milestone.authorized = true;
        emit MilestoneAuthorised(index, msg.sender);
    }

    // --- Withdrawal ---
    /**
     * @notice Allows the developer to withdraw funds for an authorized milestone.
     * @dev Can only be called by the designated `developer`.
     *      Requires the milestone to be set and authorized, and not already withdrawn.
     *      Transfers the milestone amount to the developer.
     *      Notifies the funding source (Vault) via callback `triggerDrawdown`.
     * @param index The index of the milestone to withdraw.
     */
    function withdraw(uint8 index)
        external
        override // from IDevEscrow
        nonReentrant
        whenNotPaused
    {
        if (msg.sender != developer) revert Errors.CallerNotDeveloper(msg.sender, 0); // Project ID not stored here
        if (index >= milestoneCount) revert Errors.MilestoneIndexOutOfBounds(index, milestoneCount);

        Milestone storage milestone = milestones[index];
        if (!milestone.authorized) revert Errors.MilestoneNotAuthorized(index);
        if (milestone.withdrawn) revert Errors.MilestoneAlreadyWithdrawn(index);

        uint256 amount = milestone.amount;
        if (usdcToken.balanceOf(address(this)) < amount) {
            revert Errors.EscrowNotFundedSufficiently(amount, usdcToken.balanceOf(address(this)));
        }

        milestone.withdrawn = true;
        totalWithdrawn += amount;

        // Transfer funds to developer
        usdcToken.safeTransfer(developer, amount);

        // Notify funding source (if it implements the expected interface)
        // Use a low-level call with function selector to avoid strict interface dependency
        // bytes4 selector = IProjectVault.triggerDrawdown.selector;
        // (bool success, ) = fundingSource.call(abi.encodeWithSelector(selector, amount));
        // Consider potential outcomes of failed callback - should withdrawal revert?
        // For MVP, maybe just emit event and don't revert on callback failure.
        // Let's try the interface call directly for now, assuming fundingSource is Vault-like.
        // Add check if fundingSource implements the required function?
        // Simplified: Assume funding source handles callbacks if needed, just emit event here.

        emit DeveloperDrawdown(index, developer, amount);

        // --- Callback to Vault (Example) ---
        // This is optional based on DirectProjectVault needing the callback.
        // Wrap in try/catch or check interface support if needed.
        try IProjectVault(fundingSource).triggerDrawdown(amount) {
            // Callback succeeded (or fundingSource is not a Vault/doesn't implement)
        } catch {
            // Callback failed - decide if this should revert the withdrawal.
            // For MVP, we might log this off-chain or ignore.
            // Reverting here could lock funds if Vault is broken/unreachable.
            // Let's not revert for now.
        }
    }

    // --- View Functions ---
    function getTotalAllocated() external view override returns (uint256) {
        return totalAllocated;
    }

    function getTotalWithdrawn() external view override returns (uint256) {
        return totalWithdrawn;
    }

    function getMilestone(uint8 index)
        external
        view
        override
        returns (uint256 amount, bool authorized, bool withdrawn)
    {
        if (index >= milestoneCount) return (0, false, false);
        Milestone storage m = milestones[index];
        return (m.amount, m.authorized, m.withdrawn);
    }

    function getDeveloper() external view override returns (address) {
        return developer;
    }

    function getFundingSource() external view override returns (address) {
        return fundingSource;
    }

    // --- Pausable Functions ---
    function pause() external onlyRole(Constants.PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(Constants.PAUSER_ROLE) {
        _unpause();
    }

    // --- Finalization Check ---
    /**
     * @notice Checks if the sum of all set milestone amounts equals the total allocated amount.
     * @dev Useful validation before considering the escrow fully configured.
     * @return bool True if the amounts match, false otherwise.
     */
    function checkMilestoneTotalMatchesAllocation() external view returns (bool) {
        return totalMilestoneAmountSet == totalAllocated;
    }

    // --- Access Control Overrides ---
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControlEnumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

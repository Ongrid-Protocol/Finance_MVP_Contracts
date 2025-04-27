// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Constants} from "../common/Constants.sol";
import {Errors} from "../common/Errors.sol";
import {IFeeRouter} from "../interfaces/IFeeRouter.sol";
import {IProjectVault} from "../interfaces/IProjectVault.sol";
import {ILiquidityPoolManager} from "../interfaces/ILiquidityPoolManager.sol";
// Note: No direct IRepaymentRouter interface defined as this is the implementation.

/**
 * @title RepaymentRouter
 * @dev Central point for handling developer loan repayments.
 *      It pulls funds from the developer, interacts with the FeeRouter to calculate
 *      and handle fees, determines the principal/interest split (by querying the funding source),
 *      and routes the net repayment (principal + interest) to the appropriate funding source
 *      (DirectProjectVault or LiquidityPoolManager).
 */
contract RepaymentRouter is
    AccessControlEnumerable,
    Pausable,
    ReentrancyGuard
    // No UUPSUpgradeable needed as per spec
{
    using SafeERC20 for IERC20;

    // --- Events ---
    /**
     * @dev Emitted when a funding source is set or updated for a project ID.
     * @param projectId The unique identifier of the project.
     * @param fundingSource The address of the Vault or PoolManager handling the project.
     * @param poolId The associated poolId if the funding source is a PoolManager (otherwise 0).
     * @param setter The admin address performing the action.
     */
    event FundingSourceSet(uint256 indexed projectId, address indexed fundingSource, uint256 poolId, address indexed setter);

    /**
     * @dev Emitted when a repayment is successfully processed and routed.
     * @param projectId The unique identifier of the project being repaid.
     * @param payer The address that made the repayment (should be the developer).
     * @param totalAmountRepaid The gross amount pulled from the payer.
     * @param feeAmount The portion of the repayment allocated to fees.
     * @param principalAmount The portion routed to the funding source as principal.
     * @param interestAmount The portion routed to the funding source as interest.
     * @param fundingSource The address of the Vault or PoolManager that received the net repayment.
     */
    event RepaymentRouted(
        uint256 indexed projectId,
        address indexed payer,
        uint256 totalAmountRepaid,
        uint256 feeAmount,
        uint256 principalAmount,
        uint256 interestAmount,
        address indexed fundingSource
    );

    // --- State Variables ---
    IERC20 public immutable usdcToken;
    IFeeRouter public immutable feeRouter;

    /**
     * @dev Stores the address of the funding source (Vault or PoolManager) for each project.
     */
    mapping(uint256 => address) public projectFundingSource;

     /**
     * @dev Stores the pool ID if the funding source is a LiquidityPoolManager.
     */
    mapping(uint256 => uint256) public projectPoolId; // Only relevant if funding source is PoolManager

    // --- Constructor ---
    /**
     * @notice Initializes the RepaymentRouter.
     * @param _admin Address to grant initial admin and pauser roles.
     * @param _usdcToken Address of the USDC token contract.
     * @param _feeRouter Address of the FeeRouter contract.
     */
    constructor(address _admin, address _usdcToken, address _feeRouter) {
        if (_admin == address(0) || _usdcToken == address(0) || _feeRouter == address(0)) {
            revert Errors.ZeroAddressNotAllowed();
        }

        usdcToken = IERC20(_usdcToken);
        feeRouter = IFeeRouter(_feeRouter);

        // Grant initial roles
        _grantRole(Constants.DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(Constants.PAUSER_ROLE, _admin);

        // Ensure FeeRouter has REPAYMENT_ROUTER_ROLE granted to this contract's address
        // This needs to be done externally after deployment.
    }

    // --- Configuration ---

    /**
     * @notice Sets or updates the funding source contract (Vault/Pool) for a given project ID.
     * @dev Requires caller to have `DEFAULT_ADMIN_ROLE`.
     * @param projectId The unique identifier of the project.
     * @param fundingSource The address of the `DirectProjectVault` or `LiquidityPoolManager`.
     * @param poolId The ID of the pool if `fundingSource` is a PoolManager, otherwise 0.
     */
    function setFundingSource(uint256 projectId, address fundingSource, uint256 poolId) external onlyRole(Constants.DEFAULT_ADMIN_ROLE) {
        if (fundingSource == address(0)) revert Errors.ZeroAddressNotAllowed();
        // Optional: Check if projectId exists? Depends on workflow.

        projectFundingSource[projectId] = fundingSource;
         if (poolId != 0) {
             projectPoolId[projectId] = poolId;
         } else {
             // Clear poolId if setting a non-pool source (e.g., a Vault)
             delete projectPoolId[projectId];
         }

        emit FundingSourceSet(projectId, fundingSource, poolId, msg.sender);
    }

    // --- Repayment Handling ---

    /**
     * @notice Processes a repayment from a developer for a specific project.
     * @dev 1. Pulls the specified `amount` of USDC from `msg.sender` (developer).
     *      2. Calculates the transaction fee via `feeRouter`.
     *      3. Transfers the fee amount to the `feeRouter`.
     *      4. Calls `feeRouter.routeFees()` to distribute the fee.
     *      5. Determines the principal/interest split of the remaining amount (net repayment).
     *         - This requires querying the `fundingSource` (Vault/Pool) for outstanding debt details.
     *      6. Calls `handleRepayment()` on the `fundingSource` with the principal/interest split.
     *      7. Updates the `lastMgmtFeeTimestamp` in the `feeRouter`.
     * @param projectId The unique identifier of the project being repaid.
     * @param amount The total amount the developer intends to repay in this transaction.
     */
    function repay(uint256 projectId, uint256 amount)
        external
        nonReentrant
        whenNotPaused
    {
        if (amount == 0) revert Errors.AmountCannotBeZero();
        address fundingSource = projectFundingSource[projectId];
        if (fundingSource == address(0)) revert Errors.InvalidValue("Funding source not set for project");

        address payer = msg.sender; // Assume developer calls this directly

        // --- 1. Pull Funds ---
        usdcToken.safeTransferFrom(payer, address(this), amount);

        // --- 2. Calculate Transaction Fee ---
        uint256 txFee = feeRouter.calculateTransactionFee(amount);

        uint256 netRepaymentAmount = amount - txFee;
        if (netRepaymentAmount == 0 && txFee > 0) { 
             // Edge case: Repayment only covers fee? Let it proceed but principal/interest will be 0.
        } else if (txFee >= amount) { 
             revert Errors.InvalidAmount(amount); // Amount must be greater than fee
        }

        // --- 3. Transfer Fee to FeeRouter ---
        usdcToken.safeTransfer(address(feeRouter), txFee);

        // --- 4. Trigger Fee Routing ---
        feeRouter.routeFees(txFee);

        // --- 5. Determine Principal/Interest Split ---
        uint256 principalToRepay;
        uint256 interestToRepay;

        // --- 6. Call handleRepayment on Funding Source ---
        uint256 poolId = projectPoolId[projectId];
        bool isPool = poolId != 0;

        // Call target and get split back
        try IFundingSource(fundingSource).handleRepayment(isPool ? poolId : 0, projectId, netRepaymentAmount)
            returns (uint256 principalPaid, uint256 interestPaid)
        {
            principalToRepay = principalPaid;
            interestToRepay = interestPaid;

            // Sanity check: returned split should match net amount
            if (principalPaid + interestPaid > netRepaymentAmount) {
                // This indicates an issue in the target contract's calculation
                 revert Errors.InvalidValue("Target contract repayment split exceeds net amount");
            }
             // Allow principalPaid + interestPaid < netRepaymentAmount if target handles rounding/dust?

        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Target handleRepayment failed: ", reason)));
        } catch (bytes memory lowLevelData) {
            revert(string(abi.encodePacked("Target handleRepayment failed: ", string(lowLevelData))));
        }

        // --- 7. Update Fee Router Timestamp ---
        feeRouter.updateLastMgmtFeeTimestamp(projectId);

        // --- Emit Event ---
        emit RepaymentRouted(
            projectId,
            payer,
            amount, // Gross amount
            txFee,
            principalToRepay,
            interestToRepay,
            fundingSource
        );
    }

    // --- Pausable Functions ---

    function pause() external onlyRole(Constants.PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(Constants.PAUSER_ROLE) {
        _unpause();
    }

    // --- View Functions ---

     function getFundingSource(uint256 projectId) external view returns (address) {
        return projectFundingSource[projectId];
    }

    function getPoolId(uint256 projectId) external view returns (uint256) {
        return projectPoolId[projectId];
    }

    // --- Access Control Overrides ---
    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControlEnumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}

// --- Internal Interface for Unified Call ---
// This allows calling handleRepayment on both Vault and PoolManager via a single type.
// Requires both target contracts to implement this signature pattern.
interface IFundingSource {
    // For Vaults: poolId would be 0, projectId is the vault's ID.
    // For Pools: poolId and projectId are used.
    function handleRepayment(uint256 poolId, uint256 projectId, uint256 netAmount)
        external
        returns (uint256 principalPaid, uint256 interestPaid);
} 
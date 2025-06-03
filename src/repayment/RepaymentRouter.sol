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
contract RepaymentRouter is AccessControlEnumerable, Pausable, ReentrancyGuard {
    // No UUPSUpgradeable needed as per spec

    using SafeERC20 for IERC20;

    // --- Events ---
    /**
     * @dev Emitted when a funding source is set or updated for a project ID.
     * @param projectId The unique identifier of the project.
     * @param fundingSource The address of the Vault or PoolManager handling the project.
     * @param poolId The associated poolId if the funding source is a PoolManager (otherwise 0).
     * @param setter The admin address performing the action.
     */
    event FundingSourceSet(
        uint256 indexed projectId, address indexed fundingSource, uint256 poolId, address indexed setter
    );

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

    // Payment tracking
    mapping(uint256 => uint256) public totalRepaidByProject; // projectId => total repaid
    mapping(uint256 => uint256) public lastPaymentTimestamp; // projectId => timestamp
    mapping(uint256 => uint256[]) public projectPaymentHistory; // projectId => payment amounts

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
     * @dev Requires caller to have `PROJECT_HANDLER_ROLE`.
     * @param projectId The unique identifier of the project.
     * @param fundingSource The address of the `DirectProjectVault` or `LiquidityPoolManager`.
     * @param poolId The ID of the pool if `fundingSource` is a PoolManager, otherwise 0.
     */
    function setFundingSource(uint256 projectId, address fundingSource, uint256 poolId)
        external
        onlyRole(Constants.PROJECT_HANDLER_ROLE)
    {
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
     *      3. Calculates the management fee based on outstanding principal.
     *      4. Sum the transaction fee and management fee to get total fees.
     *      5. Calls `feeRouter.routeFees()` to distribute the total fees.
     *      6. Determines the principal/interest split of the remaining amount (net repayment).
     *         - This requires querying the `fundingSource` (Vault/Pool) for outstanding debt details.
     *      7. Calls `handleRepayment()` on the `fundingSource` with the principal/interest split.
     *      8. Updates the `lastMgmtFeeTimestamp` in the `feeRouter`.
     * @param projectId The unique identifier of the project being repaid.
     * @param amount The total amount the developer intends to repay in this transaction.
     */
    function repay(uint256 projectId, uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert Errors.AmountCannotBeZero();
        address fundingSourceAddress = projectFundingSource[projectId];
        if (fundingSourceAddress == address(0)) revert Errors.InvalidValue("Funding source not set for project");

        IFundingSource fundingSource = IFundingSource(fundingSourceAddress);
        address payer = msg.sender; // Assume developer calls this directly

        // --- 1. Pull Funds ---
        usdcToken.safeTransferFrom(payer, address(this), amount);

        // --- Fee Calculation ---
        uint256 txFee = feeRouter.calculateTransactionFee(amount);

        // Calculate Management Fee
        uint256 outstandingPrincipal = fundingSource.getOutstandingPrincipal(projectPoolId[projectId], projectId);
        uint256 mgmtFee = 0;
        if (outstandingPrincipal > 0) {
            // Only calculate mgmt fee if there's outstanding principal
            mgmtFee = feeRouter.calculateManagementFee(projectId, outstandingPrincipal);
        }

        uint256 totalFeeCollected = txFee + mgmtFee;

        if (totalFeeCollected >= amount) {
            // If fees are greater than or equal to repayment, all of it goes to fees.
            // Transfer entire amount to fee router, net repayment will be 0.
            usdcToken.safeTransfer(address(feeRouter), amount);
            feeRouter.routeFees(amount);

            // Always update management fee timestamp to keep timestamps in sync
            feeRouter.updateLastMgmtFeeTimestamp(projectId);

            // Track payment
            totalRepaidByProject[projectId] += amount;
            lastPaymentTimestamp[projectId] = block.timestamp;
            projectPaymentHistory[projectId].push(amount);

            emit RepaymentRouted(projectId, payer, amount, amount, 0, 0, fundingSourceAddress);
            return; // Exit early
        }

        uint256 netRepaymentAmount = amount - totalFeeCollected;

        // --- Transfer Total Fee to FeeRouter ---
        usdcToken.safeTransfer(address(feeRouter), totalFeeCollected);

        // --- Trigger Fee Routing in FeeRouter ---
        feeRouter.routeFees(totalFeeCollected);

        // --- Update Management Fee Timestamp in FeeRouter ---
        // Always update the mgmt fee timestamp, even if no management fee was applicable
        // This ensures consistent timestamp tracking across all repayments
        feeRouter.updateLastMgmtFeeTimestamp(projectId);

        // --- Determine Principal/Interest Split & Call handleRepayment on Funding Source ---
        uint256 principalToRepay;
        uint256 interestToRepay;
        uint256 poolIdForCall = projectPoolId[projectId]; // Use stored poolId

        try fundingSource.handleRepayment(poolIdForCall, projectId, netRepaymentAmount) returns (
            uint256 principalPaid, uint256 interestPaid
        ) {
            principalToRepay = principalPaid;
            interestToRepay = interestPaid;

            if (principalPaid + interestPaid > netRepaymentAmount) {
                revert Errors.InvalidValue("Target contract repayment split exceeds net amount");
            }
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Target handleRepayment failed: ", reason)));
        } catch (bytes memory lowLevelData) {
            revert(string(abi.encodePacked("Target handleRepayment failed (low level): ", string(lowLevelData))));
        }

        // --- Emit Event ---
        emit RepaymentRouted(
            projectId,
            payer,
            amount, // Gross amount
            totalFeeCollected,
            principalToRepay,
            interestToRepay,
            fundingSourceAddress
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

    /**
     * @notice Gets payment history for a project
     * @param projectId The project ID
     * @return totalRepaid Total amount repaid
     * @return lastPayment Timestamp of last payment
     * @return paymentCount Number of payments made
     */
    function getProjectPaymentSummary(uint256 projectId)
        external
        view
        returns (uint256 totalRepaid, uint256 lastPayment, uint256 paymentCount)
    {
        totalRepaid = totalRepaidByProject[projectId];
        lastPayment = lastPaymentTimestamp[projectId];
        paymentCount = projectPaymentHistory[projectId].length;
    }

    // --- Access Control Overrides ---
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControlEnumerable)
        returns (bool)
    {
        // Add support for pause/unpause interface by checking for the selectors
        bytes4 pauseSelector = bytes4(keccak256("pause()"));
        bytes4 unpauseSelector = bytes4(keccak256("unpause()"));
        bytes4 pauseInterface = pauseSelector ^ unpauseSelector;

        if (interfaceId == pauseInterface) {
            return true;
        }

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

    function getOutstandingPrincipal(uint256 poolId, uint256 projectId) external view returns (uint256);
}

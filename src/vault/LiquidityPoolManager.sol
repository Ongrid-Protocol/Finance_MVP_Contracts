// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// OZ Imports
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

// Local Imports
import {Constants} from "../common/Constants.sol";
import {Errors} from "../common/Errors.sol";
import {ILiquidityPoolManager} from "../interfaces/ILiquidityPoolManager.sol";
import {IDevEscrow} from "../interfaces/IDevEscrow.sol";
import {IFeeRouter} from "../interfaces/IFeeRouter.sol"; // Needed to set project details for fees
import {IDeveloperRegistry} from "../interfaces/IDeveloperRegistry.sol"; // Needed to set project details for fees
import {IRiskRateOracleAdapter} from "../interfaces/IRiskRateOracleAdapter.sol"; // Interface needed if calling oracle

// Forward declaration or import of DevEscrow if needed for deployment arguments
import {DevEscrow} from "../escrow/DevEscrow.sol";

/**
 * @title LiquidityPoolManager
 * @dev Manages multiple liquidity pools where investors deposit USDC.
 *      Automatically allocates funds from pools to registered low-value (<$50k) projects.
 *      Handles LP share minting/burning upon deposit/redemption.
 *      Interacts with various system components like ProjectFactory, Oracle, DevEscrow, RepaymentRouter.
 *      Uses UUPS for upgradeability.
 */
contract LiquidityPoolManager is
    Initializable,
    AccessControlEnumerable,
    Pausable,
    ReentrancyGuard,
    UUPSUpgradeable,
    ILiquidityPoolManager // Implement the interface
{
    using SafeERC20 for IERC20;

    // --- State Variables ---
    IERC20 public usdcToken;
    IFeeRouter public feeRouter; // Needed for fee calculations on pool loans
    IDeveloperRegistry public developerRegistry; // Needed for fee calculations
    IRiskRateOracleAdapter public riskOracleAdapter; // To fetch APR for loans
    address public devEscrowImplementation; // Implementation address for cloning DevEscrow
    address public repaymentRouter; // Needed for handleRepayment role check
    address public milestoneAuthorizer; // Single authorizer for all pool-funded escrows

    /**
     * @dev Information about each liquidity pool.
     */
    mapping(uint256 => PoolInfo) public pools;
    uint256 public poolCount;

    /**
     * @dev Tracks loans funded by specific pools.
     *      poolId => projectId => LoanRecord
     */
    mapping(uint256 => mapping(uint256 => LoanRecord)) public poolLoans;

    /**
     * @dev Tracks LP shares held by users per pool.
     *      userAddress => poolId => shareAmount
     */
    mapping(address => mapping(uint256 => uint256)) public userShares;

    // Update the funding context to match the interface's ProjectParams
    struct ProjectFundingContext {
        uint256 projectId;
        uint256 poolId;
        address developer;
        address escrowAddress;
        uint256 loanAmount; // 80% financed amount
        uint256 totalCost; // 100% total cost
        uint16 aprBps;
        uint48 requestedTenor;
        uint16 riskLevel;
    }

    // Storage mapping to hold temporary context
    mapping(uint256 => ProjectFundingContext) private fundingContexts;
    uint256 private nextFundingContextId;

    // Get a new context ID
    function _getNextContextId() internal returns (uint256) {
        return ++nextFundingContextId;
    }

    // --- Initializer ---
    /**
     * @notice Initializes the LiquidityPoolManager contract.
     * @param _admin Address for initial admin roles.
     * @param _usdcToken Address of the USDC token.
     * @param _feeRouter Address of the FeeRouter contract.
     * @param _developerRegistry Address of the DeveloperRegistry contract.
     * @param _riskRateOracleAdapter Address of the RiskRateOracleAdapter contract.
     * @param _devEscrowImplementation Address of the DevEscrow implementation contract.
     * @param _repaymentRouter Address of the RepaymentRouter contract.
     * @param _milestoneAuthorizer Address authorized to approve milestones for pool-funded escrows.
     */
    function initialize(
        address _admin,
        address _usdcToken,
        address _feeRouter,
        address _developerRegistry,
        address _riskRateOracleAdapter,
        address _devEscrowImplementation,
        address _repaymentRouter,
        address _milestoneAuthorizer
    ) public initializer {
        if (
            _admin == address(0) || _usdcToken == address(0) || _feeRouter == address(0)
                || _developerRegistry == address(0) || _devEscrowImplementation == address(0)
                || _repaymentRouter == address(0) || _milestoneAuthorizer == address(0)
        ) {
            revert Errors.ZeroAddressNotAllowed();
        }

        usdcToken = IERC20(_usdcToken);
        feeRouter = IFeeRouter(_feeRouter);
        developerRegistry = IDeveloperRegistry(_developerRegistry);
        riskOracleAdapter = IRiskRateOracleAdapter(_riskRateOracleAdapter);
        devEscrowImplementation = _devEscrowImplementation;
        repaymentRouter = _repaymentRouter; // Store for role check
        milestoneAuthorizer = _milestoneAuthorizer;

        // Grant roles
        _grantRole(Constants.DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(Constants.PAUSER_ROLE, _admin);
        _grantRole(Constants.UPGRADER_ROLE, _admin);
        // Role for ProjectFactory to call registerAndFundProject
        _grantRole(Constants.PROJECT_HANDLER_ROLE, _admin); // Grant to admin initially
        // Role for RepaymentRouter to call handleRepayment
        _grantRole(Constants.REPAYMENT_HANDLER_ROLE, _repaymentRouter);
        // Role for Oracle Adapter - initially grant to admin
        _grantRole(Constants.RISK_ORACLE_ROLE, _admin);
    }

    // --- Pool Management ---    /**
    /* @inheritdoc ILiquidityPoolManager
     * @dev Pool ID should be unique and managed off-chain or via internal counter.
     *      Using internal counter `poolCount` for simplicity.
     */
    function createPool(uint256, /* poolId */ string calldata name)
        external
        override
        onlyRole(Constants.DEFAULT_ADMIN_ROLE)
        whenNotPaused
    {
        // Use internal counter for poolId
        uint256 newPoolId = ++poolCount;
        if (pools[newPoolId].exists) revert Errors.PoolAlreadyExists(newPoolId);
        if (bytes(name).length == 0) revert Errors.StringCannotBeEmpty();

        pools[newPoolId] = PoolInfo({exists: true, name: name, totalAssets: 0, totalShares: 0});
        // Initialize other fields if added

        emit PoolCreated(newPoolId, name, msg.sender);
    }

    /**
     * @inheritdoc ILiquidityPoolManager
     * @dev Mints LP shares proportional to the deposit amount relative to the pool's total assets.
     *      Follows a simplified ERC4626-like share calculation.
     */
    function depositToPool(uint256 poolId, uint256 amount)
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        if (amount == 0) revert Errors.CannotInvestZero();
        if (amount < 1 * Constants.USDC_UNIT) revert Errors.InvestmentBelowMinimum(1 * Constants.USDC_UNIT);

        PoolInfo storage pool = pools[poolId];
        if (!pool.exists) revert Errors.PoolDoesNotExist(poolId);

        // --- Calculate Shares to Mint ---        // Simplified calculation: shares = amount * totalShares / totalAssets (or 1:1 if pool empty)
        uint256 currentTotalAssets = pool.totalAssets;
        uint256 currentTotalShares = pool.totalShares;

        if (currentTotalAssets == 0 || currentTotalShares == 0) {
            // First deposit, shares = amount (1:1 ratio)
            shares = amount;
        } else {
            // shares = amount * totalShares / totalAssets
            shares = (amount * currentTotalShares) / currentTotalAssets;
        }
        if (shares == 0) revert Errors.InvalidValue("Deposit too small for shares"); // Prevent minting 0 shares

        // --- Update State ---        pool.totalAssets = currentTotalAssets + amount;
        pool.totalShares = currentTotalShares + shares;
        userShares[msg.sender][poolId] += shares;

        // --- Transfer Funds ---        usdcToken.safeTransferFrom(msg.sender, address(this), amount);

        emit PoolDeposit(poolId, msg.sender, amount, shares);
        return shares;
    }

    /**
     * @inheritdoc ILiquidityPoolManager
     * @dev Burns LP shares and returns a proportional amount of the underlying USDC.
     */
    function redeem(uint256 poolId, uint256 shares)
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256 assets)
    {
        if (shares == 0) revert Errors.CannotRedeemZeroShares();
        PoolInfo storage pool = pools[poolId];
        if (!pool.exists) revert Errors.PoolDoesNotExist(poolId);

        uint256 currentUserShares = userShares[msg.sender][poolId];
        if (currentUserShares < shares) revert Errors.InsufficientShares(shares, currentUserShares);

        // --- Calculate Assets to Return ---        // assets = shares * totalAssets / totalShares
        uint256 currentTotalAssets = pool.totalAssets;
        uint256 currentTotalShares = pool.totalShares;
        if (currentTotalShares == 0) revert Errors.InvalidState("Cannot redeem from empty pool shares"); // Should not happen if shares > 0

        assets = (shares * currentTotalAssets) / currentTotalShares;
        if (assets == 0) revert Errors.InvalidValue("Shares too small for assets"); // Prevent withdrawing 0 assets
        if (assets > currentTotalAssets) revert Errors.InvalidState("Redemption calculation error"); // Sanity check

        // --- Update State ---        pool.totalAssets = currentTotalAssets - assets;
        pool.totalShares = currentTotalShares - shares;
        userShares[msg.sender][poolId] = currentUserShares - shares;

        // --- Transfer Funds ---        usdcToken.safeTransfer(msg.sender, assets);

        emit PoolRedeem(poolId, msg.sender, shares, assets);
        return assets;
    }

    // --- Project Funding & Repayment ---
    /**
     * @inheritdoc ILiquidityPoolManager
     */
    function registerAndFundProject(uint256 projectId, address developer, ProjectParams calldata params)
        external
        override
        nonReentrant
        whenNotPaused
        onlyRole(Constants.PROJECT_HANDLER_ROLE)
        returns (bool success, uint256 poolId)
    {
        // Input validation
        if (developer == address(0)) revert Errors.ZeroAddressNotAllowed();
        if (params.loanAmountRequested == 0) revert Errors.AmountCannotBeZero();

        // Create context to reduce stack usage
        uint256 contextId = _getNextContextId();
        ProjectFundingContext storage context = fundingContexts[contextId];

        // Initialize context
        context.projectId = projectId;
        context.developer = developer;
        context.loanAmount = params.loanAmountRequested; // The 80% financed amount
        context.totalCost = params.totalProjectCost; // The total project cost (100%)
        context.requestedTenor = params.requestedTenor;

        // Get risk level
        try riskOracleAdapter.getProjectRiskLevel(projectId) returns (uint16 level) {
            context.riskLevel = level;
        } catch {
            context.riskLevel = 2; // Default to medium risk
        }

        // Find matching pool
        if (!_findBestMatchingPool(contextId, context.riskLevel, context.loanAmount)) {
            emit PoolProjectFunded(0, projectId, developer, address(0), 0, 0);
            return (false, 0);
        }

        // Deploy escrow
        if (!_deployAndInitializeEscrow(contextId)) {
            emit PoolProjectFunded(0, projectId, developer, address(0), 0, 0);
            return (false, 0);
        }

        // Create loan record - note we store only the financed amount as principal
        _createLoanRecord(
            context.poolId,
            context.projectId,
            context.developer,
            context.escrowAddress,
            context.loanAmount, // Store only the 80% financed amount as the principal
            context.aprBps,
            context.requestedTenor
        );

        // Transfer funds - only the financed portion from the pool
        _transferFundsToProject(contextId);

        // Post-funding setup (split into two steps)
        _notifyEscrowAndSetDetails(contextId);
        _setupRepaymentAndTarget(contextId);

        // Store return values before cleanup
        bool result = true;
        uint256 resultPoolId = context.poolId;

        // Clean up the context
        _cleanupContext(contextId);

        // Emit event - note we're only emitting the financed amount
        emit PoolProjectFunded(
            context.poolId,
            context.projectId,
            context.developer,
            context.escrowAddress,
            context.loanAmount,
            context.aprBps
        );

        return (result, resultPoolId);
    }

    /**
     * @inheritdoc ILiquidityPoolManager
     * @notice Handles repayments received from the RepaymentRouter.
     * @dev Updates the LoanRecord and increases the pool's totalAssets.
     *      Requires caller to have `REPAYMENT_HANDLER_ROLE`.
     *      Calculates the principal/interest split internally (simplified for pools).
     * @param poolId The ID of the pool that funded the loan.
     * @param projectId The ID of the project being repaid.
     * @param netAmountReceived Amount received after fees.
     * @return principalPaid Amount allocated to principal.
     * @return interestPaid Amount allocated to interest.
     */
    function handleRepayment(uint256 poolId, uint256 projectId, uint256 netAmountReceived)
        external
        nonReentrant
        whenNotPaused
        onlyRole(Constants.REPAYMENT_HANDLER_ROLE)
        returns (uint256 principalPaid, uint256 interestPaid)
    {
        PoolInfo storage pool = pools[poolId];
        if (!pool.exists) revert Errors.PoolDoesNotExist(poolId);
        LoanRecord storage loan = poolLoans[poolId][projectId];
        if (!loan.exists || !loan.isActive) revert Errors.InvalidValue("Loan not active or not found");

        // Simplified split for pools MVP: Assume all repayment goes to principal first,
        // then interest, up to the original principal amount.
        // TODO: Implement proper interest accrual for pool loans if needed.
        uint256 outstandingPrincipal = loan.principal - loan.principalRepaid;

        if (netAmountReceived >= outstandingPrincipal) {
            principalPaid = outstandingPrincipal;
            interestPaid = netAmountReceived - outstandingPrincipal;
        } else {
            principalPaid = netAmountReceived;
            interestPaid = 0;
        }

        // Update LoanRecord
        loan.principalRepaid += principalPaid;
        loan.interestAccrued += interestPaid; // Track received interest

        // Update Pool Assets (Principal + Interest increase pool value)
        pool.totalAssets += netAmountReceived;

        // Check if loan is fully repaid
        if (loan.principalRepaid >= loan.principal) {
            loan.principalRepaid = loan.principal; // Cap at original principal
            loan.isActive = false;
            // Optionally: Clean up loan record? Might impact history.
        }

        emit PoolRepaymentReceived(poolId, projectId, msg.sender, principalPaid, interestPaid);
        return (principalPaid, interestPaid);
    }

    /**
     * @inheritdoc ILiquidityPoolManager
     * @notice Updates risk parameters (e.g., APR) for an active pool loan.
     * @dev Requires caller to have `RISK_ORACLE_ROLE`.
     *      Currently only updates APR in the stored LoanRecord.
     */
    function updateRiskParams(uint256 poolId, uint256 projectId, uint16 newAprBps)
        external
        override
        onlyRole(Constants.RISK_ORACLE_ROLE)
        whenNotPaused
    {
        // Note: PoolInfo needed? No, it's per loan.
        // if (!pools[poolId].exists) revert Errors.PoolDoesNotExist(poolId);
        LoanRecord storage loan = poolLoans[poolId][projectId];
        if (!loan.exists || !loan.isActive) revert Errors.InvalidValue("Loan not active or not found");

        loan.aprBps = newAprBps;
        // Emit event?
        // emit PoolLoanRiskParamsUpdated(poolId, projectId, newAprBps);
    }

    // --- View Functions ---
    function getPoolInfo(uint256 poolId) external view override returns (PoolInfo memory) {
        if (!pools[poolId].exists) revert Errors.PoolDoesNotExist(poolId);
        return pools[poolId];
    }

    function getPoolLoanRecord(uint256 poolId, uint256 projectId) external view override returns (LoanRecord memory) {
        // No check needed? Returns empty struct if not found.
        return poolLoans[poolId][projectId];
    }

    function getUserShares(uint256 poolId, address user) external view override returns (uint256) {
        // No check needed? Returns 0 if not found.
        return userShares[user][poolId];
    }

    /**
     * @inheritdoc ILiquidityPoolManager
     */
    function previewDeposit(uint256 poolId, uint256 amount) external view override returns (uint256 shares) {
        PoolInfo storage pool = pools[poolId];
        if (!pool.exists) revert Errors.PoolDoesNotExist(poolId);
        if (amount == 0) return 0;

        uint256 currentTotalAssets = pool.totalAssets;
        uint256 currentTotalShares = pool.totalShares;
        if (currentTotalAssets == 0 || currentTotalShares == 0) {
            return amount;
        } else {
            return (amount * currentTotalShares) / currentTotalAssets;
        }
    }

    /**
     * @inheritdoc ILiquidityPoolManager
     */
    function previewRedeem(uint256 poolId, uint256 shares) external view override returns (uint256 assets) {
        PoolInfo storage pool = pools[poolId];
        if (!pool.exists) revert Errors.PoolDoesNotExist(poolId);
        if (shares == 0) return 0;

        uint256 currentTotalAssets = pool.totalAssets;
        uint256 currentTotalShares = pool.totalShares;
        if (currentTotalShares == 0) return 0;

        return (shares * currentTotalAssets) / currentTotalShares;
    }

    // --- Pausable Functions ---
    function pause() external onlyRole(Constants.PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(Constants.PAUSER_ROLE) {
        _unpause();
    }

    // --- UUPS Upgradeability ---
    function _authorizeUpgrade(address newImplementation) internal view override onlyRole(Constants.UPGRADER_ROLE) {
        if (newImplementation == address(0)) revert Errors.ZeroAddressNotAllowed();
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

    // Add function to calculate payment amount
    function calculateWeeklyPayment(uint256 loanAmount, uint16 aprBps, uint48 tenor) internal pure returns (uint256) {
        // Simple calculation for weekly payment (principal + interest)
        // Full principal divided by number of weeks plus weekly interest
        uint256 weeklyPrincipal = loanAmount / (tenor * 7 / 365);
        uint256 weeklyInterest = (loanAmount * uint256(aprBps)) / Constants.BASIS_POINTS_DENOMINATOR / 52;
        return weeklyPrincipal + weeklyInterest;
    }

    // Add state variables for risk tracking
    mapping(uint256 => uint16) public poolRiskLevels; // poolId => risk level (1=low, 2=medium, 3=high)
    mapping(uint256 => uint16) public poolAprRates; // poolId => APR in basis points

    // Add function to set pool risk level
    function setPoolRiskLevel(uint256 poolId, uint16 riskLevel, uint16 baseAprBps)
        external
        onlyRole(Constants.DEFAULT_ADMIN_ROLE)
    {
        if (!pools[poolId].exists) revert Errors.PoolDoesNotExist(poolId);
        if (riskLevel < 1 || riskLevel > 3) revert Errors.InvalidValue("Risk level must be 1-3");

        poolRiskLevels[poolId] = riskLevel;
        poolAprRates[poolId] = baseAprBps;
    }

    // Create a helper function to create loan record
    function _createLoanRecord(
        uint256 poolId,
        uint256 projectId,
        address developer,
        address escrowAddress,
        uint256 loanAmount,
        uint16 aprBps,
        uint48 requestedTenor
    ) internal {
        poolLoans[poolId][projectId] = LoanRecord({
            exists: true,
            developer: developer,
            devEscrow: escrowAddress,
            principal: loanAmount,
            aprBps: aprBps,
            loanTenor: requestedTenor,
            principalRepaid: 0,
            interestAccrued: 0,
            startTime: uint64(block.timestamp),
            isActive: true
        });
    }

    // Find the best matching pool for a project
    function _findBestMatchingPool(uint256 contextId, uint16 riskLevel, uint256 loanAmount)
        internal
        returns (bool success)
    {
        ProjectFundingContext storage context = fundingContexts[contextId];
        uint256 selectedPoolId = 0;
        uint16 bestAprBps = type(uint16).max;

        for (uint256 i = 1; i <= poolCount; i++) {
            if (pools[i].exists && pools[i].totalAssets >= loanAmount) {
                uint16 poolRiskLevel = poolRiskLevels[i];

                // Match project risk with pool risk - exact match preferred
                if (poolRiskLevel == riskLevel) {
                    uint16 poolAprBps = poolAprRates[i];
                    if (poolAprBps < bestAprBps) {
                        selectedPoolId = i;
                        bestAprBps = poolAprBps;
                    }
                }
                // If no exact match found yet, consider pools that accept higher risk
                else if (selectedPoolId == 0 && poolRiskLevel > riskLevel) {
                    uint16 poolAprBps = poolAprRates[i];
                    if (poolAprBps < bestAprBps) {
                        selectedPoolId = i;
                        bestAprBps = poolAprBps;
                    }
                }
            }
        }

        if (selectedPoolId == 0) {
            return false;
        }

        context.poolId = selectedPoolId;
        context.aprBps = bestAprBps;
        return true;
    }

    // Deploy and initialize the DevEscrow contract
    function _deployAndInitializeEscrow(uint256 contextId) internal returns (bool success) {
        ProjectFundingContext storage context = fundingContexts[contextId];

        address escrowAddress = Clones.clone(devEscrowImplementation);
        if (escrowAddress == address(0)) revert Errors.InvalidState("DevEscrow clone failed");

        bool successEscrow;
        (successEscrow,) = escrowAddress.call(
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,address,address)",
                address(usdcToken),
                context.developer,
                address(this),
                context.loanAmount,
                address(0),
                address(this)
            )
        );

        if (!successEscrow) {
            return false;
        }

        context.escrowAddress = escrowAddress;
        return true;
    }

    // Transfer funds to the developer
    function _transferFundsToProject(uint256 contextId) internal returns (bool success) {
        ProjectFundingContext storage context = fundingContexts[contextId];

        PoolInfo storage poolInfo = pools[context.poolId];
        if (poolInfo.totalAssets < context.loanAmount) revert Errors.InsufficientLiquidity();

        poolInfo.totalAssets -= context.loanAmount;
        usdcToken.safeTransfer(context.developer, context.loanAmount);

        return true;
    }

    // Notify escrow and set project details
    function _notifyEscrowAndSetDetails(uint256 contextId) internal {
        ProjectFundingContext storage context = fundingContexts[contextId];

        // Notify escrow of total funding (including deposit)
        try IDevEscrow(context.escrowAddress).notifyFundingComplete(context.totalCost) {} catch {}

        // Set project details in FeeRouter with total cost for proper fee calculation
        try feeRouter.setProjectDetails(
            context.projectId, context.totalCost, context.developer, uint64(block.timestamp)
        ) {} catch {}
    }

    // Setup repayment schedule and oracle target
    function _setupRepaymentAndTarget(uint256 contextId) internal {
        ProjectFundingContext storage context = fundingContexts[contextId];

        // Calculate and set repayment schedule
        uint256 weeklyPayment = calculateWeeklyPayment(context.loanAmount, context.aprBps, context.requestedTenor);
        try feeRouter.setRepaymentSchedule(context.projectId, 1, weeklyPayment) {} catch {}

        // Set oracle target
        try riskOracleAdapter.setTargetContract(context.projectId, address(this), context.poolId) {} catch {}
    }

    // Add this function to clean up contexts after use
    function _cleanupContext(uint256 contextId) internal {
        delete fundingContexts[contextId];
    }
}

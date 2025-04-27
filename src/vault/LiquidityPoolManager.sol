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
        if (_admin == address(0) || _usdcToken == address(0) || _feeRouter == address(0) || _developerRegistry == address(0) || _devEscrowImplementation == address(0) || _repaymentRouter == address(0) || _milestoneAuthorizer == address(0)) {
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
    function createPool(uint256 /* poolId */, string calldata name) external override onlyRole(Constants.DEFAULT_ADMIN_ROLE) whenNotPaused {
        // Use internal counter for poolId
        uint256 newPoolId = ++poolCount;
        if (pools[newPoolId].exists) revert Errors.PoolAlreadyExists(newPoolId);
        if (bytes(name).length == 0) revert Errors.StringCannotBeEmpty();

        pools[newPoolId] = PoolInfo({
            exists: true,
            name: name,
            totalAssets: 0,
            totalShares: 0
            // Initialize other fields if added
        });

        emit PoolCreated(newPoolId, name, msg.sender);
    }

    /**
     * @inheritdoc ILiquidityPoolManager
     * @dev Mints LP shares proportional to the deposit amount relative to the pool's total assets.
     *      Follows a simplified ERC4626-like share calculation.
     */
    function depositToPool(uint256 poolId, uint256 amount) external override nonReentrant whenNotPaused returns (uint256 shares) {
        if (amount == 0) revert Errors.CannotInvestZero();
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
    function redeem(uint256 poolId, uint256 shares) external override nonReentrant whenNotPaused returns (uint256 assets) {
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
     /* @inheritdoc ILiquidityPoolManager
     * @dev Selects pool (simple first-fit for MVP), fetches APR, deploys DevEscrow, stores record, funds escrow.
     */
    function registerAndFundProject(
        uint256 projectId, 
        address developer, 
        ProjectParams calldata params
    ) external override nonReentrant whenNotPaused onlyRole(Constants.PROJECT_HANDLER_ROLE) returns (bool success, uint256 poolId) {
        // Validate inputs
        if (developer == address(0)) revert Errors.ZeroAddressNotAllowed();
        if (params.loanAmountRequested == 0) revert Errors.AmountCannotBeZero();

        // Declare ALL variables at the beginning of the function to ensure proper scope
        uint256 loanAmount = params.loanAmountRequested;
        uint256 selectedPoolId = 0;
        address escrowAddress;
        uint16 aprBps = 1000; // Placeholder: 10% APR
        
        // Find a pool with sufficient liquidity
        for (uint256 i = 1; i <= poolCount; i++) {
            if (pools[i].exists && pools[i].totalAssets >= loanAmount) {
                selectedPoolId = i;
                break;
            }
        }

        if (selectedPoolId == 0) {
            emit PoolProjectFunded(0, projectId, developer, address(0), 0, 0);
            return (false, 0);
        }

        poolId = selectedPoolId;

        // Deploy DevEscrow
        escrowAddress = Clones.clone(devEscrowImplementation);
        if (escrowAddress == address(0)) revert Errors.InvalidState("DevEscrow clone failed");
        
        // Initialize the cloned DevEscrow
        try DevEscrow(payable(escrowAddress)).initialize(
            address(usdcToken),
            developer,
            address(this),
            loanAmount,
            milestoneAuthorizer,
            address(this)
        ) {
            // Initialization potentially needed if constructor logic moved
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("DevEscrow init failed: ", reason)));
        } catch { 
            revert Errors.InvalidState("DevEscrow init failed (low level)");
        }

        // Create LoanRecord
        if (poolLoans[poolId][projectId].exists) revert Errors.InvalidState("Loan record already exists");
        poolLoans[poolId][projectId] = LoanRecord({
            exists: true,
            developer: developer,
            devEscrow: escrowAddress,
            principal: loanAmount,
            aprBps: aprBps,
            loanTenor: params.requestedTenor,
            principalRepaid: 0,
            interestAccrued: 0,
            startTime: uint64(block.timestamp),
            isActive: true
        });

        // Transfer Principal from Pool to DevEscrow
        PoolInfo storage poolInfo = pools[poolId]; // Explicitly declare storage reference
        if (poolInfo.totalAssets < loanAmount) revert Errors.InsufficientLiquidity();
        poolInfo.totalAssets -= loanAmount;

        usdcToken.safeTransfer(escrowAddress, loanAmount);

        // Set Project Details in FeeRouter
        try feeRouter.setProjectDetails(projectId, loanAmount, developer, uint64(block.timestamp)) {}
        catch Error(string memory reason) {
            revert(string(abi.encodePacked("FeeRouter setDetails failed: ", reason)));
        } catch {}

        // Set Target in Oracle Adapter
        try riskOracleAdapter.setTargetContract(projectId, address(this), poolId) {}
        catch Error(string memory reason) {
            revert(string(abi.encodePacked("Oracle setTarget failed: ", reason)));
        } catch {}

        emit PoolProjectFunded(poolId, projectId, developer, escrowAddress, loanAmount, aprBps);
        return (true, poolId);
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
     function updateRiskParams(uint256 poolId, uint256 projectId, uint16 newAprBps) external override onlyRole(Constants.RISK_ORACLE_ROLE) whenNotPaused {
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
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(Constants.UPGRADER_ROLE) {
        if (newImplementation == address(0)) revert Errors.ZeroAddressNotAllowed();
    }

    // --- Access Control Overrides ---
    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControlEnumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
} 
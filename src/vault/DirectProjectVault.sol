// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// OZ Imports
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol"; // Optional, not used in base MVP

// PRB Math Imports
import {UD60x18, ud} from "@prb-math/UD60x18.sol";
import {SD59x18, sd} from "@prb-math/SD59x18.sol";
import {exp2, mulDivSigned} from "@prb-math/Common.sol";

// Local Imports
import {Constants} from "../common/Constants.sol";
import {Errors} from "../common/Errors.sol";
import {IProjectVault} from "../interfaces/IProjectVault.sol";
import {IDevEscrow} from "../interfaces/IDevEscrow.sol";
// RepaymentRouter role needs to call handleRepayment
// DevEscrow role needs to call triggerDrawdown
// RiskOracle role needs to call updateRiskParams

/**
 * @title DirectProjectVault
 * @dev Manages the lifecycle of a single, high-value (>=$50k) solar project loan.
 *      Handles investor deposits (acting like a simplified ERC4626 vault),
 *      accrues continuously compounded interest using PRBMath,
 *      interacts with DevEscrow for drawdowns, handles repayments via RepaymentRouter,
 *      and allows investors to claim principal and yield.
 *      Uses UUPS for upgradeability.
 * @notice This contract is deployed as a minimal proxy (clone) by the ProjectFactory.
 */
contract DirectProjectVault is
    Initializable,
    AccessControlEnumerable,
    Pausable,
    ReentrancyGuard,
    UUPSUpgradeable,
    IProjectVault // Implement the interface
{
    using SafeERC20 for IERC20;

    // --- Constants ---    // Using PRBMath UD60x18 scale (1e18)
    uint256 private constant PRB_MATH_SCALE = 1e18; // This might need review if PRBMath.SCALE is available
    // Define RAY constant directly as 1e27
    uint256 private constant RAY = 1e27;

    // --- State Variables ---    // Config - Set during initialization
    IERC20 public usdcToken;
    address public developer;
    IDevEscrow public devEscrow;
    // RepaymentRouter address needed for role check, but not stored if only role used
    uint256 public projectId;
    uint256 public loanAmount; // Target funding amount (USDC wei)
    uint48 public loanTenor; // Duration in days
    uint64 public loanStartTime; // Timestamp when funding closes and loan officially starts

    // Funding State
    uint256 public totalAssetsInvested; // Total USDC deposited by investors
    bool public fundingClosed; // Flag indicating if investment phase is over

    // Interest Rate State
    uint16 public currentAprBps; // Current Annual Percentage Rate (Basis Points)
    uint256 public accruedInterestPerShare_RAY; // Interest accrued per unit of share (RAY precision: 1e27)
    uint256 public lastInterestAccrualTimestamp; // Timestamp of last interest accrual

    // Loan State
    uint256 public principalRepaid; // Total principal repaid so far
    uint256 public interestRepaid; // Total interest repaid so far (tracks amounts received)
    bool public loanClosed; // Flag indicating if loan is fully repaid

    // Investor State
    mapping(address => uint256) public investorShares; // Amount invested by each investor (acts as shares)
    uint256 public totalShares; // Total shares issued (should equal totalAssetsInvested)
    mapping(address => uint256) public principalClaimedByInvestor; // Tracks principal claimed by each investor
    mapping(address => uint256) public interestClaimedByInvestor; // Tracks interest claimed by each investor

    // --- Initializer ---
    /**
     * @inheritdoc IProjectVault
     */
    function initialize(
        address _admin,
        address _usdcToken,
        address _developer,
        address _devEscrow,
        address _repaymentRouter,
        uint256 _projectId,
        uint256 _loanAmount,
        uint48 _loanTenor, // Duration in days
        uint16 _initialAprBps
    ) public initializer {
        if (
            _admin == address(0) || _usdcToken == address(0) || _developer == address(0) || _devEscrow == address(0)
                || _repaymentRouter == address(0)
        ) {
            revert Errors.ZeroAddressNotAllowed();
        }
        if (_loanAmount == 0) revert Errors.AmountCannotBeZero();

        // Set immutable/config state
        usdcToken = IERC20(_usdcToken);
        developer = _developer;
        devEscrow = IDevEscrow(_devEscrow);
        projectId = _projectId;
        loanAmount = _loanAmount;
        loanTenor = _loanTenor;
        currentAprBps = _initialAprBps;

        // Grant roles
        _grantRole(Constants.DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(Constants.PAUSER_ROLE, _admin);
        _grantRole(Constants.UPGRADER_ROLE, _admin);
        // Role for RepaymentRouter to call handleRepayment
        _grantRole(Constants.REPAYMENT_HANDLER_ROLE, _repaymentRouter);
        // Role for DevEscrow to call triggerDrawdown
        _grantRole(Constants.DEV_ESCROW_ROLE, _devEscrow);
        // Role for Oracle Adapter - initially grant to admin, should be transferred
        _grantRole(Constants.RISK_ORACLE_ROLE, _admin);

        // Initial state values
        totalAssetsInvested = 0;
        totalShares = 0;
        fundingClosed = false;
        loanClosed = false;
        principalRepaid = 0;
        interestRepaid = 0;
        accruedInterestPerShare_RAY = 0; // Starts at zero
            // lastInterestAccrualTimestamp will be set when funding closes
    }

    // --- Investment Phase ---    /**
    /* @inheritdoc IProjectVault
     * @dev Uses investor deposit amount directly as shares for simplicity (1 share = 1 wei USDC).
     */
    function invest(uint256 amount) external override nonReentrant whenNotPaused {
        if (fundingClosed) revert Errors.FundingClosed();
        if (amount == 0) revert Errors.CannotInvestZero();
        if (amount < 10 * Constants.USDC_UNIT) revert Errors.InvestmentBelowMinimum(10 * Constants.USDC_UNIT);

        uint256 currentTotal = totalAssetsInvested;
        uint256 potentialTotal = currentTotal + amount;
        if (potentialTotal > loanAmount) {
            revert Errors.FundingCapReached(loanAmount);
        }

        // Update state before transfer
        totalAssetsInvested = potentialTotal;
        investorShares[msg.sender] += amount; // Share = amount for simplicity
        totalShares += amount;

        // Pull funds from investor
        usdcToken.safeTransferFrom(msg.sender, address(this), amount);

        // Check if funding is now complete
        if (potentialTotal == loanAmount) {
            _closeFunding();
        }

        emit Invested(msg.sender, amount, totalAssetsInvested);
    }

    /**
     * @notice Closes the funding period, sets the loan start time, and transfers funds to DevEscrow.
     * @dev Can be called internally when cap is reached, or potentially by admin if needed before cap.
     *      Should only execute once.
     */
    function closeFundingManually() external onlyRole(Constants.DEFAULT_ADMIN_ROLE) whenNotPaused {
        if (fundingClosed) revert Errors.FundingClosed();
        // Allow closing even if not fully funded?
        // if (totalAssetsInvested == 0) revert Errors.InvalidState("Cannot close funding with zero investment");
        _closeFunding();
    }

    /**
     * @dev Internal logic to close funding, start the loan timer, and fund the escrow.
     */
    function _closeFunding() internal {
        if (fundingClosed) return; // Already closed

        fundingClosed = true;
        loanStartTime = uint64(block.timestamp);
        lastInterestAccrualTimestamp = loanStartTime; // Interest starts accruing now

        emit FundingClosed(projectId, totalAssetsInvested);

        // Transfer funds directly to developer instead of escrow
        if (totalAssetsInvested > 0) {
            usdcToken.safeTransfer(developer, totalAssetsInvested);

            // Notify escrow that funds have been transferred
            try devEscrow.notifyFundingComplete(totalAssetsInvested) {} catch { /* Notification failed - ignore */ }
        }
    }

    // --- Interest Accrual ---    /**
    /* @notice Accrues continuously compounded interest from the last accrual timestamp up to the current block time.
     * @dev Updates `accruedInterestPerShare_RAY` and `lastInterestAccrualTimestamp`.
     *      Uses PRBMath `rpow` for exponentiation.
     *      Interest accrues on the outstanding principal.
     * @return currentAccruedInterestPerShare_RAY The updated value after accrual.
     */
    function _accrueInterest() internal returns (uint256 currentAccruedInterestPerShare_RAY) {
        uint64 lastTimestamp = uint64(lastInterestAccrualTimestamp);
        uint64 currentTimestamp = uint64(block.timestamp);

        if (currentTimestamp <= lastTimestamp || loanClosed || !fundingClosed || totalShares == 0) {
            // No time elapsed, loan is closed, not started, or no shares
            return accruedInterestPerShare_RAY;
        }

        // --- Calculate Annual Rate (UD60x18) ---        // rate = aprBps / 10000
        UD60x18 annualRate_ud = ud(uint256(currentAprBps)).div(ud(Constants.BASIS_POINTS_DENOMINATOR));

        // --- Calculate Time Delta (UD60x18) ---
        // UD60x18 timeDelta_ud = ud(currentTimestamp - lastTimestamp);

        // --- Calculate Compounded Rate Multiplier ---
        // Exponent = rate * timeDelta / secondsPerYear
        // Use SD59x18 for signed intermediate value for mulDivSigned
        int256 timeElapsed_sd = sd(int256(uint256(currentTimestamp - lastTimestamp))).unwrap();
        int256 secondsPerYear_sd = sd(int256(Constants.SECONDS_PER_YEAR)).unwrap();

        // Use mulDivSigned directly imported from Common
        int256 exponent_sd =
            mulDivSigned(sd(int256(annualRate_ud.unwrap())).unwrap(), timeElapsed_sd, secondsPerYear_sd);

        // Use exp2 function directly imported from Common
        uint256 rateMultiplier_ud = exp2(uint256(exponent_sd));

        // --- Update Accrued Interest Per Share ---
        // Convert UD60x18 (1e18) multiplier to RAY (1e27) scale:
        uint256 rateMultiplier_RAY_scaled = rateMultiplier_ud * 1e9; // Scale up by 1e9 (RAY/UD)

        uint256 currentAccrual_RAY = accruedInterestPerShare_RAY;
        // Apply multiplier: newAccrued = oldAccrued * multiplier + (multiplier - 1) [scaled to RAY]
        currentAccrual_RAY = (currentAccrual_RAY * rateMultiplier_RAY_scaled / RAY) + (rateMultiplier_RAY_scaled - RAY); // Updated formula

        accruedInterestPerShare_RAY = currentAccrual_RAY;
        lastInterestAccrualTimestamp = currentTimestamp;

        return currentAccrual_RAY;
    }

    // --- Repayment Handling ---    /**
    /* @inheritdoc IProjectVault
     * @notice Handles repayments received from the RepaymentRouter.
     * @dev Calculates the principal and interest split based on the `netAmountReceived`.
     *      Updates the vault state and returns the calculated split.
     *      Requires caller to have `REPAYMENT_HANDLER_ROLE`.
     * @param poolId Pool ID (unused for Vault, expected to be 0).
     * @param _projectId Project ID (should match this vault's ID).
     * @param netAmountReceived The amount received after fees, to be split between principal and interest.
     * @return principalPaid The amount allocated to principal repayment.
     * @return interestPaid The amount allocated to interest repayment.
     */
    function handleRepayment(uint256, /* poolId */ uint256 _projectId, uint256 netAmountReceived)
        external
        nonReentrant
        whenNotPaused
        onlyRole(Constants.REPAYMENT_HANDLER_ROLE)
        returns (uint256 principalPaid, uint256 interestPaid)
    {
        // poolId is ignored here
        if (_projectId != projectId) revert Errors.InvalidValue("Project ID mismatch");
        if (loanClosed) revert Errors.LoanAlreadyClosed();
        if (netAmountReceived == 0) return (0, 0);

        // Accrue interest up to this point
        _accrueInterest();

        // Calculate total outstanding principal and interest
        uint256 outstandingPrincipal = totalAssetsInvested - principalRepaid;
        // Calculate total accrued interest based on per-share value
        uint256 totalAccruedInterest_RAY = (accruedInterestPerShare_RAY * totalShares) / RAY;
        // Convert RAY (1e27) to wei (1e6 for USDC)
        uint256 totalAccruedInterest_USDC = totalAccruedInterest_RAY; // Division by RAY already scaled it to USDC wei

        uint256 outstandingInterest =
            totalAccruedInterest_USDC > interestRepaid ? totalAccruedInterest_USDC - interestRepaid : 0;

        // Determine split: Prioritize interest repayment
        if (netAmountReceived >= outstandingInterest) {
            interestPaid = outstandingInterest;
            principalPaid = netAmountReceived - outstandingInterest;
            // Cap principal paid at outstanding principal
            if (principalPaid > outstandingPrincipal) {
                principalPaid = outstandingPrincipal;
                // Any excess is overpayment - potentially refund or handle as needed. For now, ignore excess.
            }
        } else {
            interestPaid = netAmountReceived;
            principalPaid = 0;
        }

        // Update state
        interestRepaid += interestPaid;
        principalRepaid += principalPaid;

        // Check if loan is now fully repaid
        if (principalRepaid >= totalAssetsInvested) {
            // Ensure all principal is marked as repaid, handle potential rounding differences
            principalRepaid = totalAssetsInvested;
            _closeLoan();
        }

        emit RepaymentReceived(projectId, msg.sender, principalPaid, interestPaid);

        // Return the split to the RepaymentRouter
        return (principalPaid, interestPaid);
    }

    // --- Claiming Functions ---    /**
    /* @inheritdoc IProjectVault
     * @dev Calculates claimable interest for the caller based on their shares and global repayment state.
     */
    function redeem() external nonReentrant whenNotPaused returns (uint256 principalAmount, uint256 yieldAmount) {
        // Ensure interest is up-to-date before calculating claimable
        _accrueInterest();

        // Calculate claimable amounts
        principalAmount = claimablePrincipal(msg.sender);
        yieldAmount = claimableYield(msg.sender);

        uint256 totalClaimable = principalAmount + yieldAmount;
        if (totalClaimable == 0) revert Errors.NothingToClaim();

        // Update claimed amounts
        if (principalAmount > 0) {
            principalClaimedByInvestor[msg.sender] += principalAmount;
        }

        if (yieldAmount > 0) {
            interestClaimedByInvestor[msg.sender] += yieldAmount;
        }

        // Transfer combined amount
        usdcToken.safeTransfer(msg.sender, totalClaimable);

        // Emit separate events for tracking
        if (principalAmount > 0) {
            emit PrincipalClaimed(msg.sender, principalAmount);
        }

        if (yieldAmount > 0) {
            emit YieldClaimed(msg.sender, yieldAmount);
        }

        return (principalAmount, yieldAmount);
    }

    /**
     * @inheritdoc IProjectVault
     * @dev Calculates claimable principal for the caller based on their shares and global repayment state.
     */
    function claimPrincipal() external override nonReentrant whenNotPaused {
        // Keep original implementation instead of calling redeem()
        uint256 claimable = claimablePrincipal(msg.sender);
        if (claimable == 0) revert Errors.NothingToClaim();

        principalClaimedByInvestor[msg.sender] += claimable;
        usdcToken.safeTransfer(msg.sender, claimable);

        emit PrincipalClaimed(msg.sender, claimable);
    }

    /**
     * @inheritdoc IProjectVault
     * @dev Calculates claimable yield for the caller based on their shares and global repayment state.
     */
    function claimYield() external override nonReentrant whenNotPaused {
        // Keep original implementation instead of calling redeem()
        _accrueInterest(); // Ensure interest is up-to-date before calculating claimable
        uint256 claimable = claimableYield(msg.sender);
        if (claimable == 0) revert Errors.NothingToClaim();

        interestClaimedByInvestor[msg.sender] += claimable;
        usdcToken.safeTransfer(msg.sender, claimable);

        emit YieldClaimed(msg.sender, claimable);
    }

    // --- Oracle & Admin Functions ---    /**
    /* @inheritdoc IProjectVault
     */
    function updateRiskParams(uint16 newAprBps) external override onlyRole(Constants.RISK_ORACLE_ROLE) whenNotPaused {
        if (loanClosed) revert Errors.LoanAlreadyClosed();

        // Accrue interest with the old rate before updating
        _accrueInterest();

        currentAprBps = newAprBps;
        emit RiskParamsUpdated(projectId, newAprBps);
    }

    /**
     * @inheritdoc IProjectVault
     * @dev This function is called by the associated DevEscrow contract.
     */
    function triggerDrawdown(uint256 amount) external override onlyRole(Constants.DEV_ESCROW_ROLE) whenNotPaused {
        // This function mainly serves as an acknowledgement and event trigger.
        // The actual funds are transferred directly from DevEscrow to the developer.
        // No state change needed here unless tracking total drawdowns in the vault is desired.
        emit DrawdownExecuted(projectId, developer, amount);
    }

    /**
     * @dev Internal function called when principalRepaid meets totalAssetsInvested.
     */
    function _closeLoan() internal {
        if (loanClosed) return;
        loanClosed = true;
        // Accrue final interest to capture any remaining amount
        _accrueInterest();
        uint256 finalInterestAccrued_RAY = (accruedInterestPerShare_RAY * totalShares) / RAY;
        uint256 finalInterestAccrued_USDC = finalInterestAccrued_RAY; // Division by RAY already scaled it to USDC wei

        emit LoanClosed(projectId, principalRepaid, finalInterestAccrued_USDC);
    }

    /**
     * @inheritdoc IProjectVault
     */
    function closeLoan() external override {
        // Allow admin or repayment handler to trigger close if conditions met?
        if (
            !hasRole(Constants.DEFAULT_ADMIN_ROLE, msg.sender) && !hasRole(Constants.REPAYMENT_HANDLER_ROLE, msg.sender)
        ) {
            revert Errors.NotAuthorized(msg.sender, Constants.DEFAULT_ADMIN_ROLE); // Or REPAYMENT_HANDLER_ROLE
        }
        if (loanClosed) revert Errors.LoanAlreadyClosed();
        // Require principal to be fully repaid before allowing manual close?
        if (principalRepaid < totalAssetsInvested) revert Errors.LoanNotClosed(); // Cannot close manually unless fully repaid
        _closeLoan();
    }

    // --- View Functions ---
    function getPrincipalRepaid() external view override returns (uint256) {
        return principalRepaid;
    }

    function getTotalAssetsInvested() external view override returns (uint256) {
        return totalAssetsInvested;
    }

    function getLoanAmount() external view override returns (uint256) {
        return loanAmount;
    }

    function getCurrentAprBps() external view override returns (uint16) {
        return currentAprBps;
    }

    /**
     * @notice Calculates the current total outstanding debt (principal + accrued interest).
     * @dev This is a view function but simulates accrual to the current time.
     */
    function totalDebt() external view override returns (uint256) {
        if (loanClosed) return 0;
        if (!fundingClosed) return 0; // No debt until loan starts

        uint64 lastTimestamp = uint64(lastInterestAccrualTimestamp);
        uint64 currentTimestamp = uint64(block.timestamp);
        uint256 currentAccrual_RAY = accruedInterestPerShare_RAY;

        if (currentTimestamp > lastTimestamp && totalShares > 0) {
            // Simulate accrual without modifying state
            UD60x18 annualRate_ud = ud(uint256(currentAprBps)).div(ud(Constants.BASIS_POINTS_DENOMINATOR));
            // UD60x18 timeDelta_ud = ud(currentTimestamp - lastTimestamp);

            // Convert to SD59x18 for calculation
            int256 timeElapsed_sd = sd(int256(uint256(currentTimestamp - lastTimestamp))).unwrap();
            int256 secondsPerYear_sd = sd(int256(Constants.SECONDS_PER_YEAR)).unwrap();

            // Use mulDivSigned directly imported from Common
            int256 exponent_sd =
                mulDivSigned(sd(int256(annualRate_ud.unwrap())).unwrap(), timeElapsed_sd, secondsPerYear_sd);

            // Use exp2 function directly imported from Common
            uint256 rateMultiplier_ud = exp2(uint256(exponent_sd));
            uint256 rateMultiplier_RAY_scaled = rateMultiplier_ud * 1e9;
            currentAccrual_RAY =
                (currentAccrual_RAY * rateMultiplier_RAY_scaled / RAY) + (rateMultiplier_RAY_scaled - RAY);
        }

        uint256 outstandingPrincipal = totalAssetsInvested - principalRepaid;
        uint256 totalAccruedInterest_RAY = (currentAccrual_RAY * totalShares) / RAY;
        uint256 totalAccruedInterest_USDC = totalAccruedInterest_RAY; // Division by RAY already scaled it to USDC wei
        uint256 outstandingInterest =
            totalAccruedInterest_USDC > interestRepaid ? totalAccruedInterest_USDC - interestRepaid : 0;

        return outstandingPrincipal + outstandingInterest;
    }

    /**
     * @inheritdoc IProjectVault
     * @dev Calculates based on investor shares and the difference between total interest available for claim and already claimed.
     */
    function claimableYield(address investor) public view override returns (uint256) {
        if (totalShares == 0) return 0;
        uint256 shares = investorShares[investor];
        if (shares == 0) return 0;

        // Total interest available for claim = interestRepaid
        // Investor's share of interest = interestRepaid * userShares / totalShares
        uint256 totalClaimableInterest = (interestRepaid * shares) / totalShares;
        uint256 alreadyClaimed = interestClaimedByInvestor[investor];

        return totalClaimableInterest > alreadyClaimed ? totalClaimableInterest - alreadyClaimed : 0;
    }

    /**
     * @inheritdoc IProjectVault
     * @dev Calculates based on investor shares and the difference between total principal available for claim and already claimed.
     */
    function claimablePrincipal(address investor) public view override returns (uint256) {
        if (totalShares == 0) return 0;
        uint256 shares = investorShares[investor];
        if (shares == 0) return 0;

        // Total principal available for claim = principalRepaid
        // Investor's share of principal = principalRepaid * userShares / totalShares
        uint256 totalClaimablePrincipal = (principalRepaid * shares) / totalShares;
        uint256 alreadyClaimed = principalClaimedByInvestor[investor];

        return totalClaimablePrincipal > alreadyClaimed ? totalClaimablePrincipal - alreadyClaimed : 0;
    }

    function isLoanClosed() external view override returns (bool) {
        return loanClosed;
    }

    function isFundingClosed() external view override returns (bool) {
        return fundingClosed;
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
}

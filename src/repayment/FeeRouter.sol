// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Constants} from "../common/Constants.sol";
import {Errors} from "../common/Errors.sol";
import {IDeveloperRegistry} from "../interfaces/IDeveloperRegistry.sol";
import {IFeeRouter} from "../interfaces/IFeeRouter.sol"; // Implement interface
// Import PRBMath for fee calculations involving time
import {UD60x18, ud} from "@prb-math/UD60x18.sol";

/**
 * @title FeeRouter
 * @dev Calculates protocol fees (Capital Raising, Management/AUM, Transaction)
 *      and routes them to designated treasury addresses.
 *      Uses UUPS for upgradeability and PRBMath for precision.
 */
contract FeeRouter is
    Initializable,
    AccessControlEnumerable,
    UUPSUpgradeable,
    IFeeRouter // Implement the interface
{
    using SafeERC20 for IERC20;

    // --- Structs ---
    /**
     * @dev Stores details relevant for fee calculations per project.
     */
    struct ProjectFeeDetails {
        uint64 creationTime; // Timestamp when the project funding started / loan began
        uint64 lastMgmtFeeTimestamp; // Timestamp when management fee was last calculated/charged
        uint256 loanAmount; // Original loan amount for Capital Raising Fee calc & AUM context
        address developer; // Developer address for checking funding history
        RepaymentSchedule repaymentSchedule; // Added repayment schedule
    }

    // Add repayment schedule tracking
    struct RepaymentSchedule {
        uint8 scheduleType; // 1 = weekly, 2 = monthly
        uint64 nextPaymentDue; // Timestamp when next payment is due
        uint256 paymentAmount; // Fixed payment amount per period
    }

    // --- State Variables ---
    IERC20 public usdcToken;
    IDeveloperRegistry public developerRegistry;
    address public protocolTreasury;
    address public carbonTreasury;

    /**
     * @dev Mapping from project ID to its fee calculation details.
     */
    mapping(uint256 => ProjectFeeDetails) public projectFeeInfo;

    // --- Initializer ---
    /**
     * @notice Initializes the FeeRouter contract.
     * @param _admin The address to grant initial administrative privileges.
     * @param _usdcToken Address of the USDC token.
     * @param _developerRegistry Address of the DeveloperRegistry contract.
     * @param _protocolTreasury Address of the protocol's main treasury.
     * @param _carbonTreasury Address of the treasury designated for carbon initiatives.
     */
    function initialize(
        address _admin,
        address _usdcToken,
        address _developerRegistry,
        address _protocolTreasury,
        address _carbonTreasury
    ) public initializer {
        if (
            _admin == address(0) || _usdcToken == address(0) || _developerRegistry == address(0)
                || _protocolTreasury == address(0) || _carbonTreasury == address(0)
        ) {
            revert Errors.ZeroAddressNotAllowed();
        }

        usdcToken = IERC20(_usdcToken);
        developerRegistry = IDeveloperRegistry(_developerRegistry);
        protocolTreasury = _protocolTreasury;
        carbonTreasury = _carbonTreasury;

        // Grant roles
        _grantRole(Constants.DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(Constants.UPGRADER_ROLE, _admin); // Admin can upgrade
        // Roles allowed to call functions like setProjectDetails, routeFees
        _grantRole(Constants.REPAYMENT_ROUTER_ROLE, _admin); // Grant to admin initially
        _grantRole(Constants.PROJECT_HANDLER_ROLE, _admin); // Grant to admin initially

        // Check if treasury shares sum to 100%
        if (
            Constants.PROTOCOL_TREASURY_SHARE_BPS + Constants.CARBON_TREASURY_SHARE_BPS
                != Constants.BASIS_POINTS_DENOMINATOR
        ) {
            revert Errors.InvalidValue("Treasury shares do not sum to 10000 BPS");
        }
    }

    // --- Configuration ---

    /**
     * @notice Updates the protocol treasury address.
     * @dev Requires caller to have `DEFAULT_ADMIN_ROLE`.
     * @param _newTreasury The new protocol treasury address.
     */
    function setProtocolTreasury(address _newTreasury) external onlyRole(Constants.DEFAULT_ADMIN_ROLE) {
        if (_newTreasury == address(0)) revert Errors.ZeroAddressNotAllowed();
        protocolTreasury = _newTreasury;
    }

    /**
     * @notice Updates the carbon treasury address.
     * @dev Requires caller to have `DEFAULT_ADMIN_ROLE`.
     * @param _newTreasury The new carbon treasury address.
     */
    function setCarbonTreasury(address _newTreasury) external onlyRole(Constants.DEFAULT_ADMIN_ROLE) {
        if (_newTreasury == address(0)) revert Errors.ZeroAddressNotAllowed();
        carbonTreasury = _newTreasury;
    }

    /**
     * @notice Stores project details needed for fee calculations.
     * @dev Called by authorized contracts (PROJECT_HANDLER_ROLE: ProjectFactory, Vault, PoolManager).
     * @param projectId The unique identifier of the project.
     * @param loanAmount The total loan amount.
     * @param developer The address of the project developer.
     * @param creationTime Timestamp when funding/loan started.
     */
    function setProjectDetails(uint256 projectId, uint256 loanAmount, address developer, uint64 creationTime)
        external
        override // from IFeeRouter
        onlyRole(Constants.PROJECT_HANDLER_ROLE)
    {
        if (developer == address(0)) revert Errors.ZeroAddressNotAllowed();
        // Add checks for projectId > 0, loanAmount > 0, creationTime > 0 ?

        projectFeeInfo[projectId] = ProjectFeeDetails({
            creationTime: creationTime,
            lastMgmtFeeTimestamp: creationTime,
            loanAmount: loanAmount,
            developer: developer,
            repaymentSchedule: RepaymentSchedule({scheduleType: 0, nextPaymentDue: 0, paymentAmount: 0})
        });
    }

    // --- Fee Calculation Functions ---

    /**
     * @notice Calculates the Capital Raising Fee based on the loan amount and developer history.
     * @dev Uses `developerRegistry` to check `timesFunded`.
     * @param projectId The project ID (used to fetch details).
     * @param developer The developer address (passed explicitly for verification against stored data).
     * @return feeAmount The calculated fee in USDC units.
     */
    function calculateCapitalRaisingFee(uint256 projectId, address developer)
        public
        view
        override
        returns (uint256 feeAmount)
    {
        ProjectFeeDetails storage details = projectFeeInfo[projectId];
        if (details.developer == address(0)) revert Errors.InvalidValue("Project details not set");
        if (details.developer != developer) revert Errors.InvalidValue("Developer mismatch");

        uint32 timesFunded = developerRegistry.getTimesFunded(developer);

        uint16 feeBps = (timesFunded <= 1) // If timesFunded is 0 (first project before increment) or 1 (first project after increment)
            ? Constants.CAPITAL_RAISING_FEE_FIRST_TIME_BPS
            : Constants.CAPITAL_RAISING_FEE_REPEAT_BPS;

        // fee = loanAmount * feeBps / 10000
        feeAmount = (details.loanAmount * feeBps) / Constants.BASIS_POINTS_DENOMINATOR;
    }

    /**
     * @notice Calculates the Management Fee (AUM) accrued since the last calculation.
     * @dev Uses PRBMath for time difference and applies tiered annual BPS rate pro-rata.
     * @param projectId The project ID.
     * @param outstandingPrincipal The current outstanding principal of the loan.
     * @return feeAmount The accrued management fee in USDC units for the period.
     */
    function calculateManagementFee(uint256 projectId, uint256 outstandingPrincipal)
        public
        view
        override
        returns (uint256 feeAmount)
    {
        ProjectFeeDetails storage details = projectFeeInfo[projectId];
        if (details.developer == address(0)) revert Errors.InvalidValue("Project details not set");

        uint64 lastTimestamp = details.lastMgmtFeeTimestamp;
        uint64 currentTimestamp = uint64(block.timestamp);

        if (currentTimestamp <= lastTimestamp) return 0; // No time elapsed

        uint256 timeElapsed = currentTimestamp - lastTimestamp;

        // Determine applicable annual fee rate based on original loan amount tier
        uint16 annualFeeBps = (details.loanAmount <= Constants.MGMT_FEE_AUM_TIER1_THRESHOLD)
            ? Constants.MGMT_FEE_AUM_TIER1_BPS
            : Constants.MGMT_FEE_AUM_TIER2_BPS;

        // Convert BPS to UD60x18 for precision with PRBMath
        UD60x18 annualRate_ud = ud(uint256(annualFeeBps)).div(ud(Constants.BASIS_POINTS_DENOMINATOR)); // e.g., 0.01 for 100 BPS

        // Calculate fee for the period: fee = principal * annualRate * (timeElapsed / secondsPerYear)
        // Use PRBMath: fee = outstandingPrincipal_ud.mul(annualRate_ud).mul(timeElapsed_ud).div(secondsPerYear_ud)
        UD60x18 feeAmount_ud =
            ud(outstandingPrincipal).mul(annualRate_ud).mul(ud(timeElapsed)).div(ud(Constants.SECONDS_PER_YEAR));

        // Convert back from UD60x18 to standard uint256 (assuming USDC decimals handled correctly)
        // PRBMath handles the decimal placement internally.
        // The result should be in the same units as outstandingPrincipal (USDC wei)
        feeAmount = uint256(feeAmount_ud.unwrap());
    }

    /**
     * @notice Calculates the Transaction Fee based on the transaction amount using tiers.
     * @dev No hard cap is applied.
     * @param transactionAmount The amount of the transaction (e.g., repayment amount).
     * @return feeAmount The calculated transaction fee in USDC units.
     */
    function calculateTransactionFee(uint256 transactionAmount) public pure override returns (uint256 feeAmount) {
        if (transactionAmount == 0) return 0;

        uint16 feeBps;
        if (transactionAmount <= Constants.TX_FEE_TIER1_THRESHOLD) {
            feeBps = Constants.TX_FEE_TIER1_BPS;
        } else if (transactionAmount <= Constants.TX_FEE_TIER2_THRESHOLD) {
            feeBps = Constants.TX_FEE_TIER2_BPS;
        } else {
            feeBps = Constants.TX_FEE_TIER3_BPS;
        }

        // fee = transactionAmount * feeBps / 10000
        feeAmount = (transactionAmount * feeBps) / Constants.BASIS_POINTS_DENOMINATOR;
    }

    // --- Fee Processing & Routing ---

    /**
     * @notice Updates the last management fee calculation timestamp for a project.
     * @dev Should be called after management fees for a period are successfully processed/deducted.
     *      Requires caller to have REPAYMENT_ROUTER_ROLE or PROJECT_HANDLER_ROLE (needs refinement).
     *      Let's restrict to REPAYMENT_ROUTER_ROLE for now, assuming it triggers this post-calculation.
     * @param projectId The project ID.
     */
    function updateLastMgmtFeeTimestamp(uint256 projectId)
        external
        override
        onlyRole(Constants.REPAYMENT_ROUTER_ROLE)
    {
        ProjectFeeDetails storage details = projectFeeInfo[projectId];
        if (details.developer == address(0)) revert Errors.InvalidValue("Project details not set");
        // Update timestamp only if current time is later
        if (block.timestamp > details.lastMgmtFeeTimestamp) {
            details.lastMgmtFeeTimestamp = uint64(block.timestamp);
        }
    }

    /**
     * @notice Splits the total calculated fee amount and transfers funds to treasuries.
     * @dev Requires caller to have `REPAYMENT_ROUTER_ROLE`.
     *      Assumes the `feeAmount` is already held by this contract (transferred by RepaymentRouter).
     * @param feeAmount The total fee amount (already calculated) to be distributed.
     */
    function routeFees(uint256 feeAmount) external override onlyRole(Constants.REPAYMENT_ROUTER_ROLE) {
        if (feeAmount == 0) return; // Nothing to route

        // Ensure this contract holds the fee amount
        if (usdcToken.balanceOf(address(this)) < feeAmount) {
            revert Errors.InvalidAmount(usdcToken.balanceOf(address(this))); // Or specific error
        }

        uint256 protocolAmount =
            (feeAmount * Constants.PROTOCOL_TREASURY_SHARE_BPS) / Constants.BASIS_POINTS_DENOMINATOR;
        uint256 carbonAmount = feeAmount - protocolAmount; // Remainder goes to carbon treasury

        // Transfer funds
        usdcToken.safeTransfer(protocolTreasury, protocolAmount);
        usdcToken.safeTransfer(carbonTreasury, carbonAmount);

        emit FeeRouted(msg.sender, feeAmount, protocolAmount, carbonAmount);
    }

    // --- View Functions ---

    function getProtocolTreasury() external view override returns (address) {
        return protocolTreasury;
    }

    function getCarbonTreasury() external view override returns (address) {
        return carbonTreasury;
    }

    function getProjectFeeDetails(uint256 projectId) external view returns (ProjectFeeDetails memory) {
        return projectFeeInfo[projectId];
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
        // Add support for pause/unpause interface by checking for the selectors
        bytes4 pauseSelector = bytes4(keccak256("pause()"));
        bytes4 unpauseSelector = bytes4(keccak256("unpause()"));
        bytes4 pauseInterface = pauseSelector ^ unpauseSelector;
        
        if (interfaceId == pauseInterface) {
            return true;
        }
        
        return super.supportsInterface(interfaceId);
    }

    // Add function to set repayment schedule
    function setRepaymentSchedule(uint256 projectId, uint8 scheduleType, uint256 paymentAmount)
        external
        onlyRole(Constants.PROJECT_HANDLER_ROLE)
    {
        if (scheduleType != 1 && scheduleType != 2) revert Errors.InvalidValue("Invalid schedule type");
        if (paymentAmount == 0) revert Errors.AmountCannotBeZero();

        ProjectFeeDetails storage details = projectFeeInfo[projectId];
        if (details.developer == address(0)) revert Errors.InvalidValue("Project details not set");

        uint64 nextPaymentDue;
        if (scheduleType == 1) {
            // weekly
            nextPaymentDue = uint64(details.creationTime + 7 days);
        } else {
            // monthly
            nextPaymentDue = uint64(details.creationTime + 30 days);
        }

        details.repaymentSchedule = RepaymentSchedule({
            scheduleType: scheduleType,
            nextPaymentDue: nextPaymentDue,
            paymentAmount: paymentAmount
        });
    }

    // Add function to get next payment info
    function getNextPaymentInfo(uint256 projectId) external view returns (uint64 dueDate, uint256 amount) {
        ProjectFeeDetails storage details = projectFeeInfo[projectId];
        if (details.developer == address(0)) revert Errors.InvalidValue("Project details not set");

        return (details.repaymentSchedule.nextPaymentDue, details.repaymentSchedule.paymentAmount);
    }

    // Add function to update payment schedule after payment
    function updatePaymentSchedule(uint256 projectId) external onlyRole(Constants.REPAYMENT_ROUTER_ROLE) {
        ProjectFeeDetails storage details = projectFeeInfo[projectId];
        if (details.developer == address(0)) revert Errors.InvalidValue("Project details not set");

        RepaymentSchedule storage schedule = details.repaymentSchedule;
        if (schedule.scheduleType == 1) {
            // weekly
            schedule.nextPaymentDue += 7 days;
        } else if (schedule.scheduleType == 2) {
            // monthly
            schedule.nextPaymentDue += 30 days;
        }
    }
}

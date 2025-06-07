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
import {IFeeRouter} from "../interfaces/IFeeRouter.sol";
import {IDeveloperRegistry} from "../interfaces/IDeveloperRegistry.sol";
import {IRiskRateOracleAdapter} from "../interfaces/IRiskRateOracleAdapter.sol";
import {IRepaymentRouter} from "../interfaces/IRepaymentRouter.sol";
import {IDeveloperDepositEscrow} from "../interfaces/IDeveloperDepositEscrow.sol";

/**
 * @title LiquidityPoolManager
 * @dev Manages multiple liquidity pools where investors deposit USDC.
 *      Automatically allocates funds from pools to registered low-value (<$50k) projects.
 *      Handles LP share minting/burning upon deposit/redemption.
 *      Uses UUPS for upgradeability.
 */
contract LiquidityPoolManager is
    Initializable,
    AccessControlEnumerable,
    Pausable,
    ReentrancyGuard,
    UUPSUpgradeable,
    ILiquidityPoolManager
{
    using SafeERC20 for IERC20;

    // --- State Variables ---
    IERC20 public usdcToken;
    IFeeRouter public feeRouter;
    IDeveloperRegistry public developerRegistry;
    IRiskRateOracleAdapter public riskOracleAdapter;
    address public devEscrowImplementation;
    address public repaymentRouter;
    IDeveloperDepositEscrow public depositEscrow;
    address public protocolTreasuryAdmin;

    mapping(uint256 => PoolInfo) public pools;
    uint256 public poolCount;
    uint256[] public allPoolIds;

    // Enhanced tracking
    mapping(address => uint256[]) public userPoolIds;
    mapping(uint256 => address[]) public poolInvestors;
    mapping(uint256 => uint8) public poolProjectStates;
    mapping(uint256 => mapping(uint256 => LoanRecord)) public poolLoans;
    mapping(uint256 => uint256[]) public projectsByPool;
    mapping(address => mapping(uint256 => uint256)) public userShares;

    // Risk tracking
    mapping(uint256 => uint16) public poolRiskLevels;
    mapping(uint256 => uint16) public poolAprRates;

    // --- Events ---
    event LoanDefaulted(
        uint256 indexed poolId,
        uint256 indexed projectId,
        address indexed developer,
        uint256 writeOffAmount,
        uint256 totalOutstandingAtDefault
    );

    // --- Initializer ---
    function initialize(
        address _admin,
        address _usdcToken,
        address _feeRouter,
        address _developerRegistry,
        address _riskRateOracleAdapter,
        address _devEscrowImplementation,
        address _repaymentRouter,
        address _depositEscrow,
        address _protocolTreasuryAdmin
    ) public initializer {
        if (
            _admin == address(0) || _usdcToken == address(0) || _feeRouter == address(0)
                || _developerRegistry == address(0) || _riskRateOracleAdapter == address(0)
                || _devEscrowImplementation == address(0) || _repaymentRouter == address(0) || _depositEscrow == address(0)
                || _protocolTreasuryAdmin == address(0)
        ) {
            revert Errors.ZeroAddressNotAllowed();
        }

        usdcToken = IERC20(_usdcToken);
        feeRouter = IFeeRouter(_feeRouter);
        developerRegistry = IDeveloperRegistry(_developerRegistry);
        riskOracleAdapter = IRiskRateOracleAdapter(_riskRateOracleAdapter);
        devEscrowImplementation = _devEscrowImplementation;
        repaymentRouter = _repaymentRouter;
        depositEscrow = IDeveloperDepositEscrow(_depositEscrow);
        protocolTreasuryAdmin = _protocolTreasuryAdmin;

        _grantRole(Constants.DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(Constants.PAUSER_ROLE, _admin);
        _grantRole(Constants.UPGRADER_ROLE, _admin);
        _grantRole(Constants.PROJECT_HANDLER_ROLE, _admin);
        _grantRole(Constants.REPAYMENT_HANDLER_ROLE, _repaymentRouter);
        _grantRole(Constants.RISK_ORACLE_ROLE, _admin);
    }

    // --- Pool Management ---
    function createPool(uint256, string calldata name)
        external
        override
        onlyRole(Constants.DEFAULT_ADMIN_ROLE)
        whenNotPaused
    {
        uint256 newPoolId = ++poolCount;
        if (pools[newPoolId].exists) revert Errors.PoolAlreadyExists(newPoolId);
        if (bytes(name).length == 0) revert Errors.StringCannotBeEmpty();

        pools[newPoolId] = PoolInfo({exists: true, name: name, totalAssets: 0, totalShares: 0});
        allPoolIds.push(newPoolId);

        emit PoolCreated(newPoolId, name, msg.sender);
    }

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

        uint256 currentTotalAssets = pool.totalAssets;
        uint256 currentTotalShares = pool.totalShares;

        if (currentTotalAssets == 0 || currentTotalShares == 0) {
            shares = amount;
        } else {
            shares = (amount * currentTotalShares) / currentTotalAssets;
        }
        if (shares == 0) revert Errors.InvalidValue("Deposit too small");

        pool.totalAssets = currentTotalAssets + amount;
        pool.totalShares = currentTotalShares + shares;
        userShares[msg.sender][poolId] += shares;

        bool alreadyInvested = userShares[msg.sender][poolId] > shares;
        if (!alreadyInvested) {
            userPoolIds[msg.sender].push(poolId);
            poolInvestors[poolId].push(msg.sender);
        }

        usdcToken.safeTransferFrom(msg.sender, address(this), amount);

        emit PoolDeposit(poolId, msg.sender, amount, shares);
        return shares;
    }

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

        uint256 currentTotalAssets = pool.totalAssets;
        uint256 currentTotalShares = pool.totalShares;
        if (currentTotalShares == 0) revert Errors.InvalidState("Empty pool");

        assets = (shares * currentTotalAssets) / currentTotalShares;
        if (assets == 0) revert Errors.InvalidValue("Shares too small");
        if (assets > currentTotalAssets) revert Errors.InvalidState("Calc error");

        pool.totalAssets = currentTotalAssets - assets;
        pool.totalShares = currentTotalShares - shares;
        userShares[msg.sender][poolId] = currentUserShares - shares;

        usdcToken.safeTransfer(msg.sender, assets);

        emit PoolRedeem(poolId, msg.sender, shares, assets);
        return assets;
    }

    // --- Project Funding ---
    function registerAndFundProject(uint256 projectId, address developer, ProjectParams calldata params)
        external
        override
        nonReentrant
        whenNotPaused
        onlyRole(Constants.PROJECT_HANDLER_ROLE)
        returns (bool success, uint256 poolId)
    {
        if (developer == address(0)) revert Errors.ZeroAddressNotAllowed();
        if (params.loanAmountRequested == 0) revert Errors.AmountCannotBeZero();

        return _processProjectFunding(projectId, developer, params);
    }

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
        if (!loan.exists || !loan.isActive) revert Errors.InvalidValue("Loan inactive");

        uint256 outstandingPrincipal = loan.principal - loan.principalRepaid;

        if (netAmountReceived >= outstandingPrincipal) {
            principalPaid = outstandingPrincipal;
            interestPaid = netAmountReceived - outstandingPrincipal;
        } else {
            principalPaid = netAmountReceived;
            interestPaid = 0;
        }

        loan.principalRepaid += principalPaid;
        loan.interestAccrued += interestPaid;
        pool.totalAssets += netAmountReceived;

        if (loan.principalRepaid >= loan.principal) {
            loan.principalRepaid = loan.principal;
            loan.isActive = false;
        }

        emit PoolRepaymentReceived(poolId, projectId, msg.sender, principalPaid, interestPaid);
        return (principalPaid, interestPaid);
    }

    function updateRiskParams(uint256 poolId, uint256 projectId, uint16 newAprBps)
        external
        override
        onlyRole(Constants.RISK_ORACLE_ROLE)
        whenNotPaused
    {
        LoanRecord storage loan = poolLoans[poolId][projectId];
        if (!loan.exists || !loan.isActive) revert Errors.InvalidValue("Loan inactive");
        loan.aprBps = newAprBps;
    }

    // --- View Functions ---
    function getPoolInfo(uint256 poolId) external view override returns (PoolInfo memory) {
        if (!pools[poolId].exists) revert Errors.PoolDoesNotExist(poolId);
        return pools[poolId];
    }

    function getPoolLoanRecord(uint256 poolId, uint256 projectId) external view override returns (LoanRecord memory) {
        return poolLoans[poolId][projectId];
    }

    function getUserShares(uint256 poolId, address user) external view override returns (uint256) {
        return userShares[user][poolId];
    }

    function getUserPoolInvestments(address user)
        external
        view
        returns (uint256[] memory poolIds, uint256[] memory shares, uint256[] memory values)
    {
        poolIds = userPoolIds[user];
        uint256 length = poolIds.length;
        shares = new uint256[](length);
        values = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            uint256 poolId = poolIds[i];
            shares[i] = userShares[user][poolId];

            PoolInfo storage pool = pools[poolId];
            if (pool.totalShares > 0) {
                values[i] = (shares[i] * pool.totalAssets) / pool.totalShares;
            }
        }
    }

    function getPoolLoans(uint256 poolId)
        external
        view
        override
        returns (
            uint256[] memory projectIds,
            uint256[] memory loanAmounts,
            uint256[] memory outstandingAmounts,
            uint8[] memory states
        )
    {
        projectIds = projectsByPool[poolId];
        uint256 count = projectIds.length;
        loanAmounts = new uint256[](count);
        outstandingAmounts = new uint256[](count);
        states = new uint8[](count);

        for (uint256 i = 0; i < count; i++) {
            LoanRecord storage loan = poolLoans[poolId][projectIds[i]];
            loanAmounts[i] = loan.principal;
            outstandingAmounts[i] = loan.principal - loan.principalRepaid;
            states[i] = loan.isActive ? Constants.PROJECT_STATE_ACTIVE : Constants.PROJECT_STATE_COMPLETED;
        }
    }

    function getAllPools() external view returns (PoolInfo[] memory) {
        uint256 count = allPoolIds.length;
        PoolInfo[] memory allPoolsInfo = new PoolInfo[](count);
        for (uint256 i = 0; i < count; i++) {
            allPoolsInfo[i] = pools[allPoolIds[i]];
        }
        return allPoolsInfo;
    }

    function getOutstandingPrincipal(uint256 poolId, uint256 projectId) external view returns (uint256) {
        LoanRecord storage loan = poolLoans[poolId][projectId];
        if (!loan.exists) return 0;
        return loan.principal - loan.principalRepaid;
    }

    // --- Admin Functions ---
    function setPoolRiskLevel(uint256 poolId, uint16 riskLevel, uint16 baseAprBps)
        external
        onlyRole(Constants.DEFAULT_ADMIN_ROLE)
    {
        if (!pools[poolId].exists) revert Errors.PoolDoesNotExist(poolId);
        if (riskLevel < 1 || riskLevel > 3) revert Errors.InvalidValue("Risk 1-3");

        poolRiskLevels[poolId] = riskLevel;
        poolAprRates[poolId] = baseAprBps;
    }

    function handleLoanDefault(uint256 poolId, uint256 projectId, uint256 writeOffAmount, bool slashDeposit)
        external
        onlyRole(Constants.DEFAULT_ADMIN_ROLE)
        whenNotPaused
    {
        PoolInfo storage pool = pools[poolId];
        if (!pool.exists) revert Errors.PoolDoesNotExist(poolId);

        LoanRecord storage loan = poolLoans[poolId][projectId];
        if (!loan.exists || !loan.isActive) revert Errors.InvalidValue("Loan inactive");

        uint256 outstandingPrincipal = loan.principal - loan.principalRepaid;
        if (outstandingPrincipal == 0) revert Errors.InvalidValue("No outstanding");

        uint256 actualWriteOffAmount = writeOffAmount == 0 ? outstandingPrincipal : writeOffAmount;
        if (actualWriteOffAmount > outstandingPrincipal) {
            actualWriteOffAmount = outstandingPrincipal;
        }

        loan.isActive = false;

        if (pool.totalAssets >= actualWriteOffAmount) {
            pool.totalAssets -= actualWriteOffAmount;
        } else {
            pool.totalAssets = 0;
        }

        if (slashDeposit) {
            try depositEscrow.slashDeposit(projectId, protocolTreasuryAdmin) {} catch {}
        }

        emit LoanDefaulted(poolId, projectId, loan.developer, actualWriteOffAmount, outstandingPrincipal);
    }

    // --- Pausable & UUPS ---
    function pause() external onlyRole(Constants.PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(Constants.PAUSER_ROLE) {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyRole(Constants.UPGRADER_ROLE) {
        if (newImplementation == address(0)) revert Errors.ZeroAddressNotAllowed();
    }

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

    // --- Internal Functions ---
    function _processProjectFunding(uint256 projectId, address developer, ProjectParams calldata params)
        internal
        returns (bool, uint256)
    {
        uint16 riskLevel = _getRiskLevel(projectId);
        uint256 selectedPoolId = _findMatchingPool(riskLevel, params.loanAmountRequested);

        if (selectedPoolId == 0) {
            emit PoolProjectFunded(0, projectId, developer, address(0), 0, 0, address(this));
            return (false, 0);
        }

        address escrowAddress = _deployEscrow(developer, params.loanAmountRequested);
        if (escrowAddress == address(0)) {
            emit PoolProjectFunded(0, projectId, developer, address(0), 0, 0, address(this));
            return (false, 0);
        }

        uint16 aprBps = poolAprRates[selectedPoolId];

        _createLoanRecord(
            selectedPoolId,
            projectId,
            developer,
            escrowAddress,
            params.loanAmountRequested,
            aprBps,
            params.requestedTenor
        );
        projectsByPool[selectedPoolId].push(projectId);

        _transferFunds(selectedPoolId, developer, params.loanAmountRequested);
        _setupProjectIntegrations(
            projectId,
            developer,
            params.totalProjectCost,
            params.loanAmountRequested,
            params.requestedTenor,
            selectedPoolId
        );

        try depositEscrow.transferDepositToProject(projectId) {} catch {}

        emit PoolProjectFunded(
            selectedPoolId, projectId, developer, escrowAddress, params.loanAmountRequested, aprBps, address(this)
        );
        return (true, selectedPoolId);
    }

    function _getRiskLevel(uint256 projectId) internal view returns (uint16) {
        try riskOracleAdapter.getProjectRiskLevel(projectId) returns (uint16 level) {
            return (level >= 1 && level <= 3) ? level : 2;
        } catch {
            return 2;
        }
    }

    function _findMatchingPool(uint16 riskLevel, uint256 loanAmount) internal view returns (uint256) {
        uint256 selectedPoolId = 0;
        uint16 bestAprBps = type(uint16).max;

        for (uint256 i = 1; i <= poolCount; i++) {
            if (pools[i].exists && pools[i].totalAssets >= loanAmount) {
                uint16 poolRiskLevel = poolRiskLevels[i];
                if (poolRiskLevel == riskLevel || (selectedPoolId == 0 && poolRiskLevel > riskLevel)) {
                    uint16 poolAprBps = poolAprRates[i];
                    if (poolAprBps < bestAprBps) {
                        selectedPoolId = i;
                        bestAprBps = poolAprBps;
                    }
                }
            }
        }
        return selectedPoolId;
    }

    function _deployEscrow(address developer, uint256 loanAmount) internal returns (address) {
        address escrowAddress = Clones.clone(devEscrowImplementation);
        if (escrowAddress == address(0)) return address(0);

        (bool success,) = escrowAddress.call(
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,address)",
                address(usdcToken),
                developer,
                address(this),
                loanAmount,
                address(this)
            )
        );

        return success ? escrowAddress : address(0);
    }

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

    function _transferFunds(uint256 poolId, address developer, uint256 loanAmount) internal {
        PoolInfo storage poolInfo = pools[poolId];
        if (poolInfo.totalAssets < loanAmount) revert Errors.InsufficientLiquidity();

        poolInfo.totalAssets -= loanAmount;
        usdcToken.safeTransfer(developer, loanAmount);
    }

    function _setupProjectIntegrations(
        uint256 projectId,
        address developer,
        uint256 totalCost,
        uint256 loanAmount,
        uint48 requestedTenor,
        uint256 poolId
    ) internal {
        try feeRouter.setProjectDetails(projectId, totalCost, developer, uint64(block.timestamp)) {} catch {}
        try developerRegistry.incrementFundedCounter(developer) {} catch {}

        uint256 weeklyPayment = _calculateWeeklyPayment(loanAmount, poolAprRates[poolId], requestedTenor);
        if (weeklyPayment > 0) {
            try feeRouter.setRepaymentSchedule(projectId, 1, weeklyPayment) {} catch {}
        }

        try IRepaymentRouter(repaymentRouter).setFundingSource(projectId, address(this), poolId) {} catch {}
        try riskOracleAdapter.setTargetContract(projectId, address(this), poolId) {} catch {}
    }

    function _calculateWeeklyPayment(uint256 loanAmount, uint16 aprBps, uint48 tenor) internal pure returns (uint256) {
        uint256 weeklyPrincipal = loanAmount / (tenor * 7 / 365);
        uint256 weeklyInterest = (loanAmount * uint256(aprBps)) / Constants.BASIS_POINTS_DENOMINATOR / 52;
        return weeklyPrincipal + weeklyInterest;
    }
}

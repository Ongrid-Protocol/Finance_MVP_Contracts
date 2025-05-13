// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// OZ Imports
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Local Imports
import {Constants} from "../common/Constants.sol";
import {Errors} from "../common/Errors.sol";
import {IDeveloperRegistry} from "../interfaces/IDeveloperRegistry.sol";
import {IDeveloperDepositEscrow} from "../interfaces/IDeveloperDepositEscrow.sol";
import {ILiquidityPoolManager} from "../interfaces/ILiquidityPoolManager.sol";
import {IProjectVault} from "../interfaces/IProjectVault.sol";
import {IDevEscrow} from "../interfaces/IDevEscrow.sol";
import {IRiskRateOracleAdapter} from "../interfaces/IRiskRateOracleAdapter.sol";
import {IFeeRouter} from "../interfaces/IFeeRouter.sol";
import {IRepaymentRouter} from "../interfaces/IRepaymentRouter.sol";

import "forge-std/console.sol";
// No IFeeRouter needed directly, but its roles are relevant
// Need DevEscrow implementation for init call signature check
// import {DevEscrow} from "../escrow/DevEscrow.sol";
// Need DirectProjectVault implementation for init call signature check
// import {DirectProjectVault} from "../vault/DirectProjectVault.sol";

/**
 * @title ProjectFactory
 * @dev Developer entry point for listing projects. Verifies KYC & 20% deposit,
 *      deploys DirectProjectVault for high-value projects or triggers LiquidityPoolManager for low-value ones.
 *      Uses UUPS for upgradeability.
 */
contract ProjectFactory is Initializable, AccessControlEnumerable, Pausable, ReentrancyGuard, UUPSUpgradeable {
    // --- Structs ---
    /**
     * @dev Parameters provided by the developer when creating a project.
     */
    struct ProjectParams {
        uint256 loanAmountRequested; // In USDC smallest unit (wei)
        uint48 requestedTenor; // Duration in days
        string metadataCID; // IPFS CID or similar for project details
    }

    /**
     * @dev Project context for high-value projects to reduce stack usage
     */
    struct HighValueProjectContext {
        address developer;
        uint256 projectId;
        uint256 financedAmount;
        uint256 depositAmount;
        uint48 requestedTenor;
        address vaultAddress;
        address devEscrowAddress;
    }

    // --- State Variables ---

    // Immutable Dependencies (set in initializer)
    IDeveloperRegistry public developerRegistry;
    IDeveloperDepositEscrow public depositEscrow;
    IERC20 public usdcToken;

    // Settable Dependencies & Configuration (set via setAddresses)
    ILiquidityPoolManager public liquidityPoolManager;
    IFeeRouter public feeRouter;
    address public vaultImplementation; // Implementation for DirectProjectVault
    address public devEscrowImplementation; // Implementation for DevEscrow
    address public repaymentRouterAddress; // Address of the RepaymentRouter contract
    address public pauserAddress; // Address granted pauser role on deployed DevEscrows
    address public adminAddress; // Address granted admin role on deployed Vaults
    address public riskOracleAdapterAddress; // Address of the RiskRateOracleAdapter contract

    // Counter
    uint256 public projectCounter;

    // --- Events ---
    /**
     * @dev Emitted when a high-value project is created and a DirectProjectVault is deployed.
     * @param projectId The unique identifier of the project.
     * @param developer The address of the developer.
     * @param vaultAddress The address of the deployed DirectProjectVault clone.
     * @param devEscrowAddress The address of the deployed DevEscrow clone for this project.
     * @param loanAmount The requested loan amount.
     */
    event ProjectCreated(
        uint256 indexed projectId,
        address indexed developer,
        address vaultAddress,
        address devEscrowAddress,
        uint256 loanAmount
    );

    /**
     * @dev Emitted when a low-value project is submitted to the LiquidityPoolManager.
     * @param projectId The unique identifier of the project.
     * @param developer The address of the developer.
     * @param poolId The ID of the pool that funded the project (if successful).
     * @param loanAmount The requested loan amount.
     * @param success Whether the pool manager successfully funded the project.
     */
    event LowValueProjectSubmitted(
        uint256 indexed projectId, address indexed developer, uint256 poolId, uint256 loanAmount, bool success
    );

    /**
     * @dev Emitted when critical contract addresses are set or updated.
     */
    event AddressesSet(
        address poolManager,
        address vaultImpl,
        address escrowImpl,
        address repaymentRouter,
        address pauser,
        address admin,
        address riskOracleAdapter,
        address feeRouter
    );

    // --- Initializer ---
    /**
     * @notice Initializes the ProjectFactory contract.
     * @param _registry Address of the DeveloperRegistry contract.
     * @param _depositEscrow Address of the DeveloperDepositEscrow contract.
     * @param _usdc Address of the USDC token contract.
     * @param _initialAdmin Address to grant initial DEFAULT_ADMIN_ROLE, PAUSER_ROLE, UPGRADER_ROLE.
     */
    function initialize(address _registry, address _depositEscrow, address _usdc, address _initialAdmin)
        public
        initializer
    {
        if (
            _registry == address(0) || _depositEscrow == address(0) || _usdc == address(0)
                || _initialAdmin == address(0)
        ) {
            revert Errors.ZeroAddressNotAllowed();
        }

        developerRegistry = IDeveloperRegistry(_registry);
        depositEscrow = IDeveloperDepositEscrow(_depositEscrow);
        usdcToken = IERC20(_usdc);

        // Grant roles
        _grantRole(Constants.DEFAULT_ADMIN_ROLE, _initialAdmin);
        _grantRole(Constants.PAUSER_ROLE, _initialAdmin);
        _grantRole(Constants.UPGRADER_ROLE, _initialAdmin);

        // Grant necessary roles *to this factory* on other contracts (must be done externally by admin):
        // - Grant RELEASER_ROLE on DeveloperDepositEscrow to this contract.
        // - Grant PROJECT_HANDLER_ROLE on DeveloperRegistry to this contract.
        // - Grant PROJECT_HANDLER_ROLE on LiquidityPoolManager to this contract.
        // - Grant DEFAULT_ADMIN_ROLE on FeeRouter (to call setProjectDetails)? No, FeeRouter uses PROJECT_HANDLER_ROLE.
    }

    // --- Configuration ---

    /**
     * @notice Sets the addresses of dependent contracts and configuration parameters.
     * @dev Can only be called by an address with the DEFAULT_ADMIN_ROLE.
     * @param _poolManager Address of the LiquidityPoolManager contract.
     * @param _vaultImpl Implementation address for DirectProjectVault clones.
     * @param _escrowImpl Implementation address for DevEscrow clones.
     * @param _repaymentRouter Address of the RepaymentRouter contract.
     * @param _pauser Address authorized to pause deployed DevEscrows.
     * @param _admin Address to be set as admin for deployed DirectProjectVaults.
     * @param _riskOracleAdapter Address of the RiskRateOracleAdapter contract.
     * @param _feeRouter Address of the FeeRouter contract.
     */
    function setAddresses(
        address _poolManager,
        address _vaultImpl,
        address _escrowImpl,
        address _repaymentRouter,
        address _pauser,
        address _admin,
        address _riskOracleAdapter,
        address _feeRouter
    ) external onlyRole(Constants.DEFAULT_ADMIN_ROLE) {
        // Add zero address checks for mandatory addresses
        if (
            _poolManager == address(0) || _vaultImpl == address(0) || _escrowImpl == address(0)
                || _repaymentRouter == address(0) || _pauser == address(0) || _admin == address(0)
                || _feeRouter == address(0)
        ) {
            revert Errors.ZeroAddressNotAllowed();
        }

        liquidityPoolManager = ILiquidityPoolManager(_poolManager);
        vaultImplementation = _vaultImpl;
        devEscrowImplementation = _escrowImpl;
        repaymentRouterAddress = _repaymentRouter;
        pauserAddress = _pauser;
        adminAddress = _admin;
        riskOracleAdapterAddress = _riskOracleAdapter; // Store the risk oracle adapter address
        feeRouter = IFeeRouter(_feeRouter); // Set feeRouter

        emit AddressesSet(
            _poolManager, _vaultImpl, _escrowImpl, _repaymentRouter, _pauser, _admin, _riskOracleAdapter, _feeRouter
        );
    }

    // --- Project Creation ---

    /**
     * @notice Allows a verified developer to create a new project.
     * @dev Checks KYC, triggers the 20% deposit, then either deploys a DirectProjectVault
     *      (and associated DevEscrow) or submits the project to the LiquidityPoolManager.
     *      Increments the developer's funded counter in the registry.
     *      Requires the developer (msg.sender) to have approved the DeveloperDepositEscrow
     *      contract to spend the required deposit amount of USDC.
     * @param params Struct containing project details (loan amount, tenor, metadata CID).
     * @return projectId The unique identifier assigned to the newly created project.
     */
    function createProject(ProjectParams calldata params)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 projectId)
    {
        // --- Input Validation ---
        if (params.loanAmountRequested == 0) revert Errors.AmountCannotBeZero();
        if (params.requestedTenor == 0) revert Errors.InvalidValue("Tenor cannot be zero");
        if (bytes(params.metadataCID).length == 0) revert Errors.StringCannotBeEmpty();

        // Ensure dependent addresses are set
        if (address(developerRegistry) == address(0) || address(depositEscrow) == address(0)) {
            revert Errors.NotInitialized();
        }

        address developer = msg.sender;

        // --- KYC Check ---
        if (!developerRegistry.isVerified(developer)) {
            revert Errors.NotVerified(developer);
        }

        // --- Project ID ---
        projectCounter++;
        projectId = projectCounter;

        // --- Deposit Handling ---
        uint256 totalProjectCost = params.loanAmountRequested;
        uint256 depositAmount =
            (totalProjectCost * Constants.DEVELOPER_DEPOSIT_BPS) / Constants.BASIS_POINTS_DENOMINATOR;
        uint256 financedAmount = totalProjectCost - depositAmount;

        if (depositAmount == 0) revert Errors.InvalidAmount(0);

        depositEscrow.fundDeposit(projectId, developer, depositAmount);

        // --- Project is now active for funding ---
        // The deposit is proof that the project can now seek funding

        // --- Routing Logic (Vault vs. Pool) ---
        if (totalProjectCost >= Constants.HIGH_VALUE_THRESHOLD) {
            // --- High-Value Project: Call internal helper with adjusted values ---
            _deployAndInitializeHighValueProject(developer, projectId, params, depositAmount, financedAmount);
        } else {
            // --- Low-Value Project: Submit to LiquidityPoolManager with adjusted values ---
            if (address(liquidityPoolManager) == address(0)) {
                revert Errors.NotInitialized(); // Need Pool Manager address
            }

            // Convert ProjectParams to ILiquidityPoolManager.ProjectParams with adjusted amount
            ILiquidityPoolManager.ProjectParams memory poolParams = ILiquidityPoolManager.ProjectParams({
                loanAmountRequested: financedAmount, // Only the 80% financed portion
                totalProjectCost: totalProjectCost, // Total cost including deposit
                requestedTenor: params.requestedTenor,
                metadataCID: params.metadataCID
            });

            (bool success, uint256 poolId) =
                liquidityPoolManager.registerAndFundProject(projectId, developer, poolParams);

            // If funding successful, release deposit to developer
            if (success) {
                depositEscrow.transferDepositToProject(projectId);
            }

            emit LowValueProjectSubmitted(projectId, developer, poolId, financedAmount, success);
        }

        // --- Update Developer Funding History ---
        developerRegistry.incrementFundedCounter(developer);

        return projectId;
    }

    // --- Internal Helper for High-Value Projects ---

    /**
     * @dev Helper to deploy DevEscrow clone
     * @param _developer The developer's address.
     * @param _fundingSource The funding source for the DevEscrow (Vault address or this contract).
     * @param _loanAmount The requested loan amount.
     * @return escrowAddress The address of the deployed DevEscrow clone.
     */
    function _deployDevEscrow(
        address _developer,
        address _fundingSource, // Vault address or this contract
        uint256 _loanAmount
    ) internal returns (address) {
        address escrowAddress = Clones.clone(devEscrowImplementation);
        if (escrowAddress == address(0)) revert Errors.InvalidState("DevEscrow clone failed");

        (bool success,) = escrowAddress.call(
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,address)",
                address(usdcToken),
                _developer,
                _fundingSource,
                _loanAmount,
                pauserAddress
            )
        );

        if (!success) revert Errors.InvalidState("DevEscrow init failed");
        return escrowAddress;
    }

    /**
     * @dev Main function split into smaller functions to avoid "stack too deep" errors
     * @param _developer The developer's address.
     * @param _projectId The project ID.
     * @param _params The project parameters.
     * @param _depositAmount The deposit amount
     * @param _financedAmount The financed amount
     */
    function _deployAndInitializeHighValueProject(
        address _developer,
        uint256 _projectId,
        ProjectParams calldata _params,
        uint256 _depositAmount,
        uint256 _financedAmount
    ) internal {
        _checkDependenciesInitialized();

        // Create project context to reduce stack variables
        HighValueProjectContext memory context = HighValueProjectContext({
            developer: _developer,
            projectId: _projectId,
            financedAmount: _financedAmount,
            depositAmount: _depositAmount,
            requestedTenor: _params.requestedTenor,
            vaultAddress: address(0),
            devEscrowAddress: address(0)
        });

        // Step 1: Deploy vault and escrow
        (context.vaultAddress, context.devEscrowAddress) = _deployVaultAndEscrow(context);

        // Step 2: Setup vault permissions
        _setupVaultPermissions(context);

        // Step 3: Configure repayment settings
        _configureRepaymentSettings(context, _params.loanAmountRequested);

        // Emit creation event
        emit ProjectCreated(
            context.projectId, context.developer, context.vaultAddress, context.devEscrowAddress, context.financedAmount
        );
    }

    /**
     * @dev Validates that all required dependencies are initialized
     */
    function _checkDependenciesInitialized() internal view {
        if (
            vaultImplementation == address(0) || devEscrowImplementation == address(0)
                || repaymentRouterAddress == address(0) || pauserAddress == address(0) || adminAddress == address(0)
                || address(feeRouter) == address(0)
        ) {
            revert Errors.NotInitialized();
        }
    }

    /**
     * @dev Deploys and initializes vault and escrow contracts
     * @param context The project context
     * @return vaultAddress The deployed vault address
     * @return devEscrowAddress The deployed escrow address
     */
    function _deployVaultAndEscrow(HighValueProjectContext memory context)
        internal
        returns (address vaultAddress, address devEscrowAddress)
    {
        // Clone the vault
        vaultAddress = Clones.clone(vaultImplementation);
        if (vaultAddress == address(0)) revert Errors.InvalidState("Vault clone failed");

        // Deploy escrow with vault as funding source
        devEscrowAddress = _deployDevEscrow(context.developer, vaultAddress, context.financedAmount);

        // Initialize the vault
        IProjectVault.InitParams memory initParams = IProjectVault.InitParams({
            admin: adminAddress,
            usdcToken: address(usdcToken),
            developer: context.developer,
            devEscrow: devEscrowAddress,
            repaymentRouter: repaymentRouterAddress,
            projectId: context.projectId,
            financedAmount: context.financedAmount,
            developerDeposit: context.depositAmount,
            loanTenor: context.requestedTenor,
            initialAprBps: 0, // Initial APR set to 0, can be updated by oracle
            depositEscrowAddress: address(depositEscrow),
            riskOracleAdapter: riskOracleAdapterAddress
        });

        try IProjectVault(vaultAddress).initialize(initParams) {}
        catch Error(string memory reason) {
            revert(string(abi.encodePacked("Vault init failed: ", reason)));
        } catch {
            revert Errors.InvalidState("Vault init failed");
        }

        return (vaultAddress, devEscrowAddress);
    }

    /**
     * @dev Sets up vault permissions and registers with oracle
     * @param context The project context
     */
    function _setupVaultPermissions(HighValueProjectContext memory context) internal {
        // Grant RELEASER_ROLE to vault on DeveloperDepositEscrow
        bool releaseRoleSuccess = false;
        try depositEscrow.grantRole(Constants.RELEASER_ROLE, context.vaultAddress) {
            console.log("RELEASER_ROLE granted to vault:", context.vaultAddress);
            releaseRoleSuccess = true;
        } catch Error(string memory reason) {
            console.log("Failed to grant RELEASER_ROLE to vault:", reason);
        }

        if (!releaseRoleSuccess) {
            revert Errors.InvalidState("Failed to grant RELEASER_ROLE to vault");
        }

        // Register vault with RiskRateOracleAdapter if available
        if (riskOracleAdapterAddress != address(0)) {
            try IRiskRateOracleAdapter(riskOracleAdapterAddress).setTargetContract(
                context.projectId, context.vaultAddress, 0
            ) {
                console.log("Vault registered with RiskRateOracleAdapter");
            } catch Error(string memory reason) {
                console.log("Failed to register vault with RiskRateOracleAdapter:", reason);
                // Not a critical error
            }
        }
    }

    /**
     * @dev Configures repayment settings in FeeRouter and RepaymentRouter
     * @param context The project context
     * @param totalLoanAmount The total loan amount (100%)
     */
    function _configureRepaymentSettings(HighValueProjectContext memory context, uint256 totalLoanAmount) internal {
        // Set project details in FeeRouter
        bool feeRouterDetailsSuccess = false;
        try feeRouter.setProjectDetails(context.projectId, totalLoanAmount, context.developer, uint64(block.timestamp))
        {
            console.log("Project details set in FeeRouter for projectId:", context.projectId);
            feeRouterDetailsSuccess = true;
        } catch Error(string memory reason) {
            console.log("Failed to set project details in FeeRouter:", reason);
        }

        if (!feeRouterDetailsSuccess) {
            revert Errors.InvalidState("Failed to set project details in FeeRouter");
        }

        // Set repayment schedule
        _setRepaymentSchedule(context);

        // Set funding source in RepaymentRouter
        _setFundingSource(context);
    }

    /**
     * @dev Sets repayment schedule in FeeRouter
     * @param context The project context
     */
    function _setRepaymentSchedule(HighValueProjectContext memory context) internal {
        uint256 numberOfWeeks = context.requestedTenor / 7;
        uint256 weeklyPaymentAmount = 0;

        if (numberOfWeeks > 0) {
            weeklyPaymentAmount = context.financedAmount / numberOfWeeks;
        }

        if (weeklyPaymentAmount > 0) {
            try feeRouter.setRepaymentSchedule(context.projectId, 1, weeklyPaymentAmount) {
                console.log("Repayment schedule set in FeeRouter for projectId:", context.projectId);
            } catch Error(string memory reason) {
                console.log("Failed to set repayment schedule in FeeRouter:", reason);
                // Not a critical error
            }
        } else {
            console.log("Skipping repayment schedule due to zero payment amount for projectId:", context.projectId);
        }
    }

    /**
     * @dev Sets funding source in RepaymentRouter
     * @param context The project context
     */
    function _setFundingSource(HighValueProjectContext memory context) internal {
        bool repaymentRouterSuccess = false;

        try IRepaymentRouter(repaymentRouterAddress).setFundingSource(context.projectId, context.vaultAddress, 0) {
            console.log("Funding source set in RepaymentRouter for projectId:", context.projectId);
            repaymentRouterSuccess = true;
        } catch Error(string memory reason) {
            console.log("Failed to set funding source in RepaymentRouter:", reason);
        }

        if (!repaymentRouterSuccess) {
            revert Errors.InvalidState("Failed to set funding source in RepaymentRouter");
        }
    }

    // --- Pausable Functions ---

    /**
     * @notice Pauses the factory, preventing new project creation.
     * @dev Requires caller to have `PAUSER_ROLE`.
     */
    function pause() external onlyRole(Constants.PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses the factory, resuming normal operations.
     * @dev Requires caller to have `PAUSER_ROLE`.
     */
    function unpause() external onlyRole(Constants.PAUSER_ROLE) {
        _unpause();
    }

    // --- UUPS Upgradeability ---

    /**
     * @dev Authorizes an upgrade to a new implementation contract.
     *      Requires caller to have `UPGRADER_ROLE`.
     * @param newImplementation The address of the new implementation contract.
     */
    function _authorizeUpgrade(address newImplementation) internal view override onlyRole(Constants.UPGRADER_ROLE) {
        if (newImplementation == address(0)) revert Errors.ZeroAddressNotAllowed();
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
}

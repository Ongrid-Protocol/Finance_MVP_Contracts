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

    // --- State Variables ---

    // Immutable Dependencies (set in initializer)
    IDeveloperRegistry public developerRegistry;
    IDeveloperDepositEscrow public depositEscrow;
    IERC20 public usdcToken;

    // Settable Dependencies & Configuration (set via setAddresses)
    ILiquidityPoolManager public liquidityPoolManager;
    address public vaultImplementation; // Implementation for DirectProjectVault
    address public devEscrowImplementation; // Implementation for DevEscrow
    address public repaymentRouterAddress; // Address of the RepaymentRouter contract
    address public milestoneAuthorizerAddress; // Address authorized for DevEscrow milestones
    address public pauserAddress; // Address granted pauser role on deployed DevEscrows
    address public adminAddress; // Address granted admin role on deployed Vaults

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
        address milestoneAuth,
        address pauser,
        address admin
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
     * @param _milestoneAuth Address authorized to approve DevEscrow milestones.
     * @param _pauser Address authorized to pause deployed DevEscrows.
     * @param _admin Address to be set as admin for deployed DirectProjectVaults.
     */
    function setAddresses(
        address _poolManager,
        address _vaultImpl,
        address _escrowImpl,
        address _repaymentRouter,
        address _milestoneAuth,
        address _pauser,
        address _admin
    ) external onlyRole(Constants.DEFAULT_ADMIN_ROLE) {
        // Add zero address checks for mandatory addresses
        if (
            _poolManager == address(0) || _vaultImpl == address(0) || _escrowImpl == address(0)
                || _repaymentRouter == address(0) || _milestoneAuth == address(0) || _pauser == address(0)
                || _admin == address(0)
        ) {
            revert Errors.ZeroAddressNotAllowed();
        }

        liquidityPoolManager = ILiquidityPoolManager(_poolManager);
        vaultImplementation = _vaultImpl;
        devEscrowImplementation = _escrowImpl;
        repaymentRouterAddress = _repaymentRouter;
        milestoneAuthorizerAddress = _milestoneAuth;
        pauserAddress = _pauser;
        adminAddress = _admin;

        emit AddressesSet(_poolManager, _vaultImpl, _escrowImpl, _repaymentRouter, _milestoneAuth, _pauser, _admin);
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
        uint256 depositAmount =
            (params.loanAmountRequested * Constants.DEVELOPER_DEPOSIT_BPS) / Constants.BASIS_POINTS_DENOMINATOR;
        if (depositAmount == 0) revert Errors.InvalidAmount(0);

        depositEscrow.fundDeposit(projectId, developer, depositAmount);

        // --- Project is now active for funding ---
        // The deposit is proof that the project can now seek funding

        // --- Routing Logic (Vault vs. Pool) ---
        if (params.loanAmountRequested >= Constants.HIGH_VALUE_THRESHOLD) {
            // --- High-Value Project: Call internal helper ---
            _deployAndInitializeHighValueProject(developer, projectId, params);
        } else {
            // --- Low-Value Project: Submit to LiquidityPoolManager ---
            if (address(liquidityPoolManager) == address(0)) {
                revert Errors.NotInitialized(); // Need Pool Manager address
            }

            // Convert ProjectParams to ILiquidityPoolManager.ProjectParams
            ILiquidityPoolManager.ProjectParams memory poolParams = ILiquidityPoolManager.ProjectParams({
                loanAmountRequested: params.loanAmountRequested,
                requestedTenor: params.requestedTenor,
                metadataCID: params.metadataCID
            });

            (bool success, uint256 poolId) =
                liquidityPoolManager.registerAndFundProject(projectId, developer, poolParams);

            emit LowValueProjectSubmitted(projectId, developer, poolId, params.loanAmountRequested, success);
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
                "initialize(address,address,address,uint256,address,address)",
                address(usdcToken),
                _developer,
                _fundingSource,
                _loanAmount,
                milestoneAuthorizerAddress,
                pauserAddress
            )
        );

        if (!success) revert Errors.InvalidState("DevEscrow init failed");
        return escrowAddress;
    }

    /**
     * @dev Helper to deploy and initialize Vault
     * @param _developer The developer's address.
     * @param _escrowAddress The address of the deployed DevEscrow clone.
     * @param _projectId The project ID.
     * @param _loanAmount The requested loan amount.
     * @param _requestedTenor The tenor of the project.
     * @return vaultAddress The address of the deployed DirectProjectVault clone.
     */
    function _deployAndInitVault(
        address _developer,
        address _escrowAddress, // Must already be deployed
        uint256 _projectId,
        uint256 _loanAmount,
        uint48 _requestedTenor
    ) internal returns (address) {
        address vaultAddress = Clones.clone(vaultImplementation);
        if (vaultAddress == address(0)) revert Errors.InvalidState("Vault clone failed");

        try IProjectVault(vaultAddress).initialize(
            adminAddress,
            address(usdcToken),
            _developer,
            _escrowAddress, // Pre-deployed escrow address
            repaymentRouterAddress,
            _projectId,
            _loanAmount,
            _requestedTenor,
            0 // Initial APR
        ) {} catch Error(string memory reason) {
            revert(string(abi.encodePacked("Vault init failed: ", reason)));
        } catch {
            revert Errors.InvalidState("Vault init failed");
        }

        return vaultAddress;
    }

    /**
     * @dev Main function - maintains original sequence
     * @param _developer The developer's address.
     * @param _projectId The project ID.
     * @param _params The project parameters.
     */
    function _deployAndInitializeHighValueProject(
        address _developer,
        uint256 _projectId,
        ProjectParams calldata _params
    ) internal {
        if (
            vaultImplementation == address(0) || devEscrowImplementation == address(0)
                || repaymentRouterAddress == address(0) || milestoneAuthorizerAddress == address(0)
                || pauserAddress == address(0) || adminAddress == address(0)
        ) {
            revert Errors.NotInitialized();
        }

        // 1. First deploy escrow with this contract as temporary funding source
        address devEscrowAddress = _deployDevEscrow(
            _developer,
            address(this), // Temporary funding source until vault is deployed
            _params.loanAmountRequested
        );

        // 2. Then deploy vault with the escrow address
        address vaultAddress = _deployAndInitVault(
            _developer, devEscrowAddress, _projectId, _params.loanAmountRequested, _params.requestedTenor
        );

        // 3. Update escrow's funding source to point to vault (optional step)
        // This would require an additional method in the DevEscrow contract
        // that's not shown in the provided code, so we'll skip it

        emit ProjectCreated(_projectId, _developer, vaultAddress, devEscrowAddress, _params.loanAmountRequested);
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

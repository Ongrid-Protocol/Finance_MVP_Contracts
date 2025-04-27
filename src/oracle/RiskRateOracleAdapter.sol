// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Constants} from "../common/Constants.sol";
import {Errors} from "../common/Errors.sol";
import {IProjectVault} from "../interfaces/IProjectVault.sol";
import {ILiquidityPoolManager} from "../interfaces/ILiquidityPoolManager.sol";

/**
 * @title RiskRateOracleAdapter
 * @dev Provides an on-chain interface for a trusted off-chain oracle service
 *      to push risk parameters (like APR) for specific projects to their
 *      respective funding contracts (DirectProjectVault or LiquidityPoolManager).
 *      Uses UUPS for upgradeability.
 */
contract RiskRateOracleAdapter is Initializable, AccessControlEnumerable, UUPSUpgradeable {
    // --- Events ---
    /**
     * @dev Emitted when a target contract is set or updated for a project ID.
     * @param projectId The unique identifier of the project.
     * @param targetContract The address of the contract (Vault or PoolManager) that manages the project's loan.
     * @param setter The admin address that set the target contract.
     */
    event TargetContractSet(uint256 indexed projectId, address indexed targetContract, address indexed setter);

    /**
     * @dev Emitted when risk parameters are successfully pushed to a target contract.
     * @param projectId The unique identifier of the project.
     * @param targetContract The address of the contract the parameters were pushed to.
     * @param oracle The address of the oracle that pushed the parameters.
     * @param aprBps The Annual Percentage Rate in basis points pushed to the target.
     * @param tenor The loan tenor in days pushed to the target (optional, may not be updated post-funding).
     */
    event RiskParamsPushed(
        uint256 indexed projectId, address indexed targetContract, address indexed oracle, uint16 aprBps, uint48 tenor
    );

    // --- State Variables ---
    /**
     * @dev Mapping from project ID to the address of the target contract (Vault or PoolManager)
     *      that should receive risk parameter updates for that project.
     */
    mapping(uint256 => address) public projectTargetContract;

    /**
     * @dev Mapping from project ID (specifically for pool-funded loans) to the pool ID within the PoolManager.
     *      Needed because PoolManager functions often require both poolId and projectId.
     *      Only set for projects handled by LiquidityPoolManager.
     */
    mapping(uint256 => uint256) public projectPoolId; // projectId => poolId

    // --- Initializer ---
    /**
     * @notice Initializes the contract, setting the initial admin and roles.
     * @dev Uses `initializer` modifier for upgradeable contracts.
     * @param _admin The address to grant initial administrative privileges (DEFAULT_ADMIN, UPGRADER, ORACLE).
     */
    function initialize(address _admin) public initializer {
        if (_admin == address(0)) revert Errors.ZeroAddressNotAllowed();

        // Grant roles to the initial admin
        _grantRole(Constants.DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(Constants.UPGRADER_ROLE, _admin); // Admin can upgrade
        _grantRole(Constants.RISK_ORACLE_ROLE, _admin); // Admin acts as the oracle initially

        // __AccessControl_init(); // Implicitly called?
        // __UUPSUpgradeable_init(); // Implicitly called?
    }

    // --- Configuration ---

    /**
     * @notice Sets or updates the target contract address for a given project ID.
     * @dev Requires caller to have `DEFAULT_ADMIN_ROLE`.
     *      This maps a project to its managing contract (Vault or PoolManager).
     *      For pool-managed projects, also sets the `poolId`.
     * @param projectId The unique identifier of the project.
     * @param targetContract The address of the `DirectProjectVault` or `LiquidityPoolManager`.
     * @param poolId The ID of the pool managing the project (only relevant if `targetContract` is a PoolManager, otherwise use 0).
     */
    function setTargetContract(uint256 projectId, address targetContract, uint256 poolId)
        external
        onlyRole(Constants.DEFAULT_ADMIN_ROLE)
    {
        if (targetContract == address(0)) revert Errors.ZeroAddressNotAllowed();
        // Optional: Add check if projectId already has a target, depending on policy

        projectTargetContract[projectId] = targetContract;
        // Only store poolId if it's non-zero (indicating it's a pool-managed project)
        if (poolId != 0) {
            projectPoolId[projectId] = poolId;
        }
        // Ensure poolId is cleared if target is potentially changed from pool to vault later?
        // else { delete projectPoolId[projectId]; } // Add if necessary

        emit TargetContractSet(projectId, targetContract, msg.sender);
    }

    // --- Oracle Function ---

    /**
     * @notice Pushes risk parameters (APR, optional Tenor) to the target contract associated with the project ID.
     * @dev Requires caller to have `RISK_ORACLE_ROLE`.
     *      Looks up the `targetContract` and calls the appropriate update function
     *      (`updateRiskParams`) on either the Vault or the PoolManager.
     * @param projectId The unique identifier of the project receiving the update.
     * @param aprBps The new Annual Percentage Rate in basis points (1% = 100 BPS).
     * @param tenor The new loan tenor in days (optional, may not be applicable post-funding, use 0 if unchanged).
     */
    function pushRiskParams(uint256 projectId, uint16 aprBps, uint48 tenor)
        external
        onlyRole(Constants.RISK_ORACLE_ROLE)
    {
        address target = projectTargetContract[projectId];
        if (target == address(0)) revert Errors.TargetContractNotSet(projectId);

        // --- Call Target Contract --- //
        // We need to determine if the target is a Vault or PoolManager to call correctly.
        // Approach 1: Try-Catch (calls vault first, if fails assumes pool manager)
        // Approach 2: Check interface support (safer)
        // Approach 3: Store target type (adds storage cost)

        // Let's use Try-Catch for simplicity in MVP, assuming distinct function signatures or roles prevent ambiguity.
        // Vaults have updateRiskParams(uint16 newAprBps)
        // Pools have updateRiskParams(uint256 poolId, uint256 projectId, uint16 newAprBps)
        // Tenor update might not be supported post-launch, primarily pushing APR.

        bool success = false;
        bytes memory errorData;

        // Attempt to call DirectProjectVault's updateRiskParams(uint16)
        try IProjectVault(target).updateRiskParams(aprBps) {
            success = true;
        } catch (bytes memory lowLevelData) {
            errorData = lowLevelData;
            // Vault call failed, try PoolManager
            uint256 poolId = projectPoolId[projectId];
            if (poolId == 0) {
                // If poolId is 0, it should have been a Vault or target wasn't set correctly for a pool.
                // Revert based on the original Vault call failure data, or a generic error.
                revert(string(abi.encodePacked("Vault call failed and no poolId set: ", string(errorData))));
            }
            try ILiquidityPoolManager(target).updateRiskParams(poolId, projectId, aprBps) {
                success = true;
            } catch Error(string memory reason) {
                revert(string(abi.encodePacked("PoolManager call failed: ", reason)));
            } catch (bytes memory lowLevelData2) {
                revert(string(abi.encodePacked("PoolManager call failed: ", string(lowLevelData2))));
            }
        }

        if (!success) {
            // Should be unreachable due to reverts in catch blocks, but defensive check.
            revert Errors.InvalidOracleData("Failed to call updateRiskParams on target contract");
        }

        emit RiskParamsPushed(projectId, target, msg.sender, aprBps, tenor);
    }

    // --- View Functions ---
    /**
     * @notice Gets the target contract address registered for a specific project ID.
     * @param projectId The project ID.
     * @return address The target contract address (Vault or PoolManager).
     */
    function getTargetContract(uint256 projectId) external view returns (address) {
        return projectTargetContract[projectId];
    }

    /**
     * @notice Gets the pool ID registered for a specific project ID (if applicable).
     * @param projectId The project ID.
     * @return uint256 The pool ID, or 0 if not a pool-managed project or not set.
     */
    function getPoolId(uint256 projectId) external view returns (uint256) {
        return projectPoolId[projectId];
    }

    // --- UUPS Upgradeability ---
    /**
     * @dev Authorizes an upgrade to a new implementation contract.
     *      Requires caller to have `UPGRADER_ROLE`.
     * @param newImplementation The address of the new implementation contract.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(Constants.UPGRADER_ROLE) {
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

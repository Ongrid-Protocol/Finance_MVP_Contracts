// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Constants} from "../common/Constants.sol";
import {Errors} from "../common/Errors.sol";
import {IDevEscrow} from "../interfaces/IDevEscrow.sol"; // Import interface
import {IProjectVault} from "../interfaces/IProjectVault.sol"; // Interface for callback

/**
 * @title DevEscrow
 * @dev Simplified contract that serves as a record-keeper for project funding.
 *      No longer holds funds or manages milestones - funds are sent directly to developers.
 *      Instantiated per project by ProjectFactory (for Vaults) or LiquidityPoolManager (for Pools).
 */
contract DevEscrow is Initializable, AccessControlEnumerable, Pausable, ReentrancyGuard, IDevEscrow {
    using SafeERC20 for IERC20;

    // --- State Variables ---
    IERC20 public usdcToken;
    address public developer;
    address public fundingSource; // Address of the Vault or PoolManager that funded this escrow
    uint256 public totalAllocated; // Total amount expected/allocated for the project
    uint256 public totalWithdrawn; // For backward compatibility - always 0 in new model

    // --- Constructor ---
    /**
     * @notice Initializes the DevEscrow for a specific project.
     * @dev To be called once after cloning.
     * @param _usdcToken Address of the USDC token contract.
     * @param _developer Address of the project developer who can withdraw funds.
     * @param _fundingSource Address of the contract funding this project (Vault or PoolManager).
     * @param _totalAllocated The total amount of USDC allocated for this project.
     * @param _pauser Address granted the pauser role.
     */
    function initialize(
        address _usdcToken,
        address _developer,
        address _fundingSource,
        uint256 _totalAllocated,
        address, // unused _milestoneAuthorizer parameter (kept for backward compatibility)
        address _pauser
    ) public initializer {
        if (
            _usdcToken == address(0) || _developer == address(0) || _fundingSource == address(0)
                || _pauser == address(0)
        ) {
            revert Errors.ZeroAddressNotAllowed();
        }
        if (_totalAllocated == 0) revert Errors.AmountCannotBeZero();

        // Assign to state variables
        usdcToken = IERC20(_usdcToken);
        developer = _developer;
        fundingSource = _fundingSource;
        totalAllocated = _totalAllocated;
        totalWithdrawn = 0;

        // Grant roles:
        _grantRole(Constants.DEFAULT_ADMIN_ROLE, _fundingSource);
        _grantRole(Constants.PAUSER_ROLE, _pauser);
    }

    /**
     * @notice Logs a funding event but doesn't actually receive funds.
     * @dev For backward compatibility - now just emits an event.
     * @param amount The amount that was funded directly to developer.
     */
    function fundEscrow(uint256 amount)
        external
        override
        nonReentrant
        whenNotPaused
        onlyRole(Constants.DEFAULT_ADMIN_ROLE)
    {
        if (msg.sender != fundingSource) revert Errors.CallerNotFundingSource(msg.sender, fundingSource);
        if (amount == 0) revert Errors.AmountCannotBeZero();

        emit EscrowFunded(fundingSource, amount);
    }

    /**
     * @notice Notifies that funding has been completed and sent directly to developer.
     * @dev Called by funding source after transferring funds to developer.
     * @param amount The amount that was sent to the developer.
     */
    function notifyFundingComplete(uint256 amount) external {
        if (msg.sender != fundingSource) revert Errors.CallerNotFundingSource(msg.sender, fundingSource);
        if (amount == 0) revert Errors.AmountCannotBeZero();

        emit FundingComplete(developer, amount);
    }

    // --- View Functions ---
    function getTotalAllocated() external view override returns (uint256) {
        return totalAllocated;
    }

    function getTotalWithdrawn() external view override returns (uint256) {
        return totalWithdrawn; // Always 0 in new model
    }

    function getDeveloper() external view override returns (address) {
        return developer;
    }

    function getFundingSource() external view override returns (address) {
        return fundingSource;
    }

    // --- Pausable Functions ---
    function pause() external onlyRole(Constants.PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(Constants.PAUSER_ROLE) {
        _unpause();
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

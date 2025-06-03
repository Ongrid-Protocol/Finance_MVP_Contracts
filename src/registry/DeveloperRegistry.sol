// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Constants} from "../common/Constants.sol";
import {Errors} from "../common/Errors.sol";
import {IDeveloperRegistry} from "../interfaces/IDeveloperRegistry.sol"; // Import interface

/**
 * @title DeveloperRegistry
 * @dev Manages developer identity, KYC status (attested via off-chain verification),
 *      and funding history. Utilizes UUPS for upgradeability.
 * @notice Stores a hash of KYC data and its off-chain location, along with verification status.
 */
contract DeveloperRegistry is
    Initializable,
    AccessControlEnumerable,
    Pausable,
    UUPSUpgradeable,
    IDeveloperRegistry // Implement the interface
{
    // --- State Variables ---
    /**
     * @dev Mapping from developer address to their information (KYC hash, verification status, times funded).
     */
    mapping(address => DevInfo) public developerInfo;

    /**
     * @dev Mapping to store the off-chain location (e.g., IPFS CID) of the full KYC data, linked by developer address.
     *      Kept separate from DevInfo to potentially save gas if only info is needed frequently.
     */
    mapping(address => string) internal kycDataLocations;

    // --- Initializer ---
    /**
     * @notice Initializes the contract, setting the initial admin and roles.
     * @dev Uses `initializer` modifier for upgradeable contracts.
     * @param _admin The address to grant initial administrative privileges (DEFAULT_ADMIN, PAUSER, UPGRADER, KYC_ADMIN).
     */
    function initialize(address _admin) public initializer {
        if (_admin == address(0)) revert Errors.ZeroAddressNotAllowed();

        // Grant roles to the initial admin
        _grantRole(Constants.DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(Constants.PAUSER_ROLE, _admin); // Admin can pause
        _grantRole(Constants.UPGRADER_ROLE, _admin); // Admin can upgrade
        _grantRole(Constants.KYC_ADMIN_ROLE, _admin); // Admin can manage KYC initially

        // Initialize Pausable state (inherited)
        // __Pausable_init(); // Implicitly called by inheriting Pausable? Check OZ docs for 5.x
        // Initializing AccessControl (inherited)
        // __AccessControl_init(); // Implicitly called by inheriting AccessControl? Check OZ docs for 5.x
        // Initializing UUPS (inherited)
        // __UUPSUpgradeable_init(); // Implicitly called?

        // Note: OZ Initializable pattern handles preventing re-initialization.
    }

    // --- KYC Management Functions ---

    /**
     * @notice Submits the hash and location of KYC data for a developer.
     * @dev Requires caller to have `KYC_ADMIN_ROLE`.
     *      Stores the hash in `developerInfo` and the location string separately.
     *      Does not verify the developer automatically; `setVerifiedStatus` must be called.
     * @param developer The address of the developer.
     * @param kycHash The hash of the KYC data (e.g., keccak256 of concatenated document hashes).
     * @param kycDataLocation A string identifier for the off-chain storage location (e.g., "ipfs://Qm...").
     */
    function submitKYC(address developer, bytes32 kycHash, string calldata kycDataLocation)
        external
        override // from IDeveloperRegistry
        onlyRole(Constants.KYC_ADMIN_ROLE)
        whenNotPaused
    {
        if (developer == address(0)) revert Errors.ZeroAddressNotAllowed();
        // Optional: Check if hash already exists for this developer if overwriting is not desired.
        // if (developerInfo[developer].kycDataHash != bytes32(0)) revert Errors.KYCHashAlreadyExists(developer, kycHash);
        if (bytes(kycDataLocation).length == 0) revert Errors.StringCannotBeEmpty();

        developerInfo[developer].kycDataHash = kycHash;
        kycDataLocations[developer] = kycDataLocation;

        emit KYCSubmitted(developer, kycHash);
    }

    /**
     * @notice Sets the KYC verification status for a developer.
     * @dev Requires caller to have `KYC_ADMIN_ROLE`.
     * @param developer The address of the developer.
     * @param verified The verification status (`true` for verified, `false` for not verified).
     */
    function setVerifiedStatus(address developer, bool verified)
        external
        override // from IDeveloperRegistry
        onlyRole(Constants.KYC_ADMIN_ROLE)
        whenNotPaused
    {
        if (developer == address(0)) revert Errors.ZeroAddressNotAllowed();
        // Optional: Prevent setting the same status again
        // if (developerInfo[developer].isVerified == verified) {
        //     if(verified) revert Errors.AlreadyVerified(developer);
        //     // else: already not verified, do nothing or revert depending on desired behavior
        // }

        developerInfo[developer].isVerified = verified;
        emit KYCStatusChanged(developer, verified);
    }

    // --- Funding History ---

    /**
     * @notice Increments the funded project counter for a developer.
     * @dev Can only be called internally or by specifically authorized contracts (e.g., ProjectFactory).
     *      Marked `external` to fulfill the interface requirement, but access should be controlled.
     *      Requires a role or other mechanism if intended to be called externally beyond initial design.
     *      *** IMPORTANT: Add access control if this needs to be callable externally by other contracts ***
     *      For now, assuming it's called by ProjectFactory which should have appropriate permissions if needed.
     *      Let's add a temporary check that msg.sender should be an admin for now.
     *      TODO: Refine access control based on final interaction patterns (e.g., grant role to ProjectFactory).
     * @param developer The address of the developer whose counter is incremented.
     */
    function incrementFundedCounter(address developer)
        external
        override // from IDeveloperRegistry
        whenNotPaused
        onlyRole(Constants.PROJECT_HANDLER_ROLE)
    {
        // TEMPORARY Access Control - Replace with appropriate role/check
        // if (!hasRole(Constants.DEFAULT_ADMIN_ROLE, msg.sender)) {
        //     revert Errors.NotAuthorized(msg.sender, Constants.DEFAULT_ADMIN_ROLE); // Or a more specific role
        // }
        if (developer == address(0)) revert Errors.ZeroAddressNotAllowed();

        uint32 currentCount = developerInfo[developer].timesFunded;
        // Potential overflow check if count could exceed uint32 max, though unlikely
        uint32 newCount = currentCount + 1;
        developerInfo[developer].timesFunded = newCount;

        emit DeveloperFundedCounterIncremented(developer, newCount);
    }

    // --- View Functions ---

    /**
     * @notice Checks if a developer is KYC verified.
     * @param developer The address of the developer to check.
     * @return bool True if the developer is verified, false otherwise.
     */
    function isVerified(address developer) external view override returns (bool) {
        return developerInfo[developer].isVerified;
    }

    /**
     * @notice Retrieves the stored KYC hash and verification status for a specific developer.
     * @param developer The address of the developer.
     * @return DevInfo memory The developer's information struct.
     */
    function getDeveloperInfo(address developer) external view override returns (DevInfo memory) {
        return developerInfo[developer];
    }

    /**
     * @notice Retrieves the off-chain location of the developer's KYC data.
     * @param developer The address of the developer.
     * @return string memory The stored location string (e.g., IPFS CID).
     */
    function getKycDataLocation(address developer) external view returns (string memory) {
        return kycDataLocations[developer];
    }

    /**
     * @notice Retrieves the number of times a developer has had a project funded.
     * @param developer The address of the developer.
     * @return uint32 The number of funded projects.
     */
    function getTimesFunded(address developer) external view override returns (uint32) {
        return developerInfo[developer].timesFunded;
    }

    // --- Pausable Functions ---

    /**
     * @notice Pauses the contract, preventing state-changing operations.
     * @dev Requires caller to have `PAUSER_ROLE`.
     */
    function pause() external onlyRole(Constants.PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses the contract, resuming normal operations.
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
        // Optional: Add validation for the new implementation address
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

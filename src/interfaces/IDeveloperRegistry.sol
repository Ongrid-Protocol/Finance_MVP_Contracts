// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title IDeveloperRegistry Interface
 * @dev Interface for the DeveloperRegistry contract.
 */
interface IDeveloperRegistry {
    /**
     * @dev Represents the information stored for each developer.
     */
    struct DevInfo {
        bytes32 kycDataHash; // Hash of the KYC data stored off-chain
        bool isVerified; // KYC verification status
        uint32 timesFunded; // Counter for how many projects the developer has had funded
    }

    /**
     * @dev Emitted when KYC data is submitted for a developer.
     * @param developer The address of the developer.
     * @param kycHash The hash of the submitted KYC data.
     */
    event KYCSubmitted(address indexed developer, bytes32 kycHash);

    /**
     * @dev Emitted when a developer's KYC verification status changes.
     * @param developer The address of the developer.
     * @param isVerified The new verification status.
     */
    event KYCStatusChanged(address indexed developer, bool isVerified);

    /**
     * @dev Emitted when a developer's funded project counter is incremented.
     * @param developer The address of the developer.
     * @param newCount The updated count of funded projects.
     */
    event DeveloperFundedCounterIncremented(address indexed developer, uint32 newCount);

    /**
     * @notice Submits KYC information hash for a developer.
     * @dev Typically called by a KYC Admin role after off-chain verification.
     * @param developer The address of the developer.
     * @param kycHash The hash of the KYC data (e.g., IPFS hash of documents).
     * @param kycDataLocation A string indicating where the full KYC data is stored off-chain (e.g., IPFS CID).
     */
    function submitKYC(address developer, bytes32 kycHash, string calldata kycDataLocation) external;

    /**
     * @notice Sets the KYC verification status for a developer.
     * @dev Typically called by a KYC Admin role.
     * @param developer The address of the developer.
     * @param verified The new verification status (`true` for verified, `false` otherwise).
     */
    function setVerifiedStatus(address developer, bool verified) external;

    /**
     * @notice Increments the funded project counter for a developer.
     * @dev This function is typically marked internal in the implementation but exposed here
     *      if needed for external interaction patterns (e.g., testing) or specific architectures.
     *      In the reference implementation, it's called internally by ProjectFactory.
     * @param developer The address of the developer whose counter is incremented.
     */
    function incrementFundedCounter(address developer) external;

    /**
     * @notice Checks if a developer is KYC verified.
     * @param developer The address of the developer to check.
     * @return bool True if the developer is verified, false otherwise.
     */
    function isVerified(address developer) external view returns (bool);

    /**
     * @notice Retrieves the stored information for a specific developer.
     * @param developer The address of the developer.
     * @return DevInfo memory The developer's information.
     */
    function getDeveloperInfo(address developer) external view returns (DevInfo memory);

    /**
     * @notice Retrieves the number of times a developer has had a project funded.
     * @param developer The address of the developer.
     * @return uint32 The number of funded projects.
     */
    function getTimesFunded(address developer) external view returns (uint32);
} 
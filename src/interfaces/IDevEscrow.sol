// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "./IERC20.sol";

/**
 * @title IDevEscrow Interface
 * @dev Interface for the DevEscrow contract, which manages milestone-based fund releases to developers.
 */
interface IDevEscrow {
    /**
     * @dev Emitted when the escrow contract receives funds from its funding source (Vault or Pool Manager).
     * @param fundingSource The address that funded the escrow.
     * @param amount The amount of USDC received.
     */
    event EscrowFunded(address indexed fundingSource, uint256 amount);

    /**
     * @dev Emitted when a funding milestone is defined.
     * @param index The index of the milestone (e.g., 0, 1, 2...).
     * @param amount The USDC amount associated with this milestone.
     */
    event MilestoneSet(uint8 index, uint256 amount);

    /**
     * @dev Emitted when a milestone is authorized for withdrawal by the MILESTONE_AUTHORIZER_ROLE.
     * @param index The index of the authorized milestone.
     * @param authorizer The address that authorized the milestone.
     */
    event MilestoneAuthorised(uint8 indexed index, address indexed authorizer);

    /**
     * @dev Emitted when a developer successfully withdraws funds for an authorized milestone.
     * @param index The index of the withdrawn milestone.
     * @param developer The address of the developer who withdrew the funds.
     * @param amount The amount of USDC withdrawn.
     */
    event DeveloperDrawdown(uint8 indexed index, address indexed developer, uint256 amount);

    /**
     * @notice Allows the funding source (Vault or Pool Manager) to send funds to the escrow.
     * @dev Should only be callable by the designated funding source (DEFAULT_ADMIN_ROLE in implementation).
     * @param amount The amount of USDC to fund the escrow with.
     */
    function fundEscrow(uint256 amount) external;

    /**
     * @notice Defines a milestone for fund withdrawal.
     * @dev Should only be callable by the funding source (DEFAULT_ADMIN_ROLE in implementation).
     *      The sum of all milestone amounts should equal the total allocated project funds.
     * @param index The sequential index of the milestone (starting from 0).
     * @param amount The amount of USDC associated with this milestone.
     */
    function setMilestone(uint8 index, uint256 amount) external;

    /**
     * @notice Authorizes a specific milestone for withdrawal.
     * @dev Should only be callable by the MILESTONE_AUTHORIZER_ROLE (trusted off-chain admin).
     * @param index The index of the milestone to authorize.
     */
    function authorizeMilestone(uint8 index) external;

    /**
     * @notice Allows the developer to withdraw funds for an authorized milestone.
     * @dev Only callable by the designated project developer.
     *      Requires the milestone to be previously authorized.
     * @param index The index of the milestone to withdraw funds for.
     */
    function withdraw(uint8 index) external;

    /**
     * @notice Gets the total amount allocated to this escrow.
     * @return uint256 The total USDC amount funded.
     */
    function getTotalAllocated() external view returns (uint256);

    /**
     * @notice Gets the total amount withdrawn by the developer so far.
     * @return uint256 The total USDC amount withdrawn.
     */
    function getTotalWithdrawn() external view returns (uint256);

    /**
     * @notice Gets the details of a specific milestone.
     * @param index The index of the milestone.
     * @return amount The amount allocated to the milestone.
     * @return authorized Whether the milestone has been authorized for withdrawal.
     * @return withdrawn Whether the milestone funds have been withdrawn.
     */
    function getMilestone(uint8 index) external view returns (uint256 amount, bool authorized, bool withdrawn);

    /**
     * @notice Gets the developer address associated with this escrow.
     * @return address The developer's address.
     */
    function getDeveloper() external view returns (address);

    /**
     * @notice Gets the funding source address associated with this escrow (Vault or PoolManager).
     * @return address The funding source's address.
     */
    function getFundingSource() external view returns (address);
}

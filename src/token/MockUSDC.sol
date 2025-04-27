// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {Constants} from "../common/Constants.sol";
import {Errors} from "../common/Errors.sol";

/**
 * @title MockUSDC
 * @dev Mock USDC token for testing and development environments (Anvil, Base Sepolia).
 *      Mimics mainnet USDC properties (6 decimals) but includes minting and controlled burning.
 *      Inherits ERC20Permit for gasless transaction approvals.
 *      Uses AccessControl for role-based minting/burning.
 */
contract MockUSDC is ERC20, ERC20Burnable, ERC20Permit, AccessControlEnumerable {
    // --- Events ---
    /**
     * @dev Emitted when tokens are minted.
     * @param minter The address performing the mint operation (must have MINTER_ROLE).
     * @param to The address receiving the minted tokens.
     * @param amount The amount of tokens minted.
     */
    event Minted(address indexed minter, address indexed to, uint256 amount);

    /**
     * @dev Emitted when tokens are burned using the controlled burnFrom function.
     * @param burner The address performing the burn operation (must have BURNER_ROLE).
     * @param from The address whose tokens are being burned.
     * @param amount The amount of tokens burned.
     */
    event BurnedFrom(address indexed burner, address indexed from, uint256 amount);

    // --- Constructor ---
    /**
     * @dev Sets token name, symbol, decimals, grants roles, and enables permit functionality.
     */
    constructor() ERC20("Mock USD Coin", "USDC") ERC20Permit("Mock USD Coin") {
        // Grant deployer all roles initially
        _grantRole(Constants.DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(Constants.MINTER_ROLE, msg.sender);
        _grantRole(Constants.BURNER_ROLE, msg.sender);
    }

    /**
     * @notice Returns the number of decimals used to get its user representation.
     */
    function decimals() public view virtual override returns (uint8) {
        return Constants.USDC_DECIMALS;
    }

    // --- Minting ---
    /**
     * @notice Mints new tokens to a specified address.
     * @dev Requires the caller to have the `MINTER_ROLE`.
     * @param to The address to receive the minted tokens.
     * @param amount The amount of tokens to mint (in the smallest unit, e.g., 1 USDC = 1 * 10^6).
     */
    function mint(address to, uint256 amount) external onlyRole(Constants.MINTER_ROLE) {
        if (to == address(0)) revert Errors.ZeroAddressNotAllowed();
        if (amount == 0) revert Errors.AmountCannotBeZero();

        _mint(to, amount);
        emit Minted(msg.sender, to, amount);
    }

    // --- Burning ---    // Inherits `burn(uint256 amount)` from ERC20Burnable, allowing holders to burn their own tokens.

    /**
     * @notice Burns tokens from a specified address.
     * @dev Requires the caller to have the `BURNER_ROLE` and sufficient allowance from the `from` address.
     *      Provides an alternative, role-controlled burn mechanism compared to the standard `burnFrom`
     *      which relies solely on allowance.
     * @param from The address whose tokens will be burned.
     * @param amount The amount of tokens to burn.
     */
    function burnFrom(address from, uint256 amount) public override onlyRole(Constants.BURNER_ROLE) {
        if (from == address(0)) revert Errors.ZeroAddressNotAllowed();
        if (amount == 0) revert Errors.AmountCannotBeZero();

        // Check allowance - standard ERC20 requirement for burnFrom
        // _spendAllowance is internal in OZ 5.x, so we call the public view function
        uint256 currentAllowance = allowance(from, msg.sender);
        if (currentAllowance < amount) {
            revert Errors.InvalidAmount(currentAllowance); // Reusing error, could define specific ERC20Error.InsufficientAllowance
        }
        _spendAllowance(from, msg.sender, amount);

        // Perform the burn
        _burn(from, amount);
        emit BurnedFrom(msg.sender, from, amount);
    }

    // --- Access Control Overrides ---
    // The following functions are overrides required by AccessControlEnumerable.

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

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "forge-std/console.sol"; // ← gives us console.log(...)
import {MockUSDC} from "../src/token/MockUSDC.sol"; // ← adjust path if needed

/// @notice Deploys MockUSDC and logs its address
contract DeployMockUSDC is Script {
    function run() external returns (address deployedAddress) {
        vm.startBroadcast();

        MockUSDC mockUSDC = new MockUSDC();
        deployedAddress = address(mockUSDC);

        // Print the address to the console
        console.log("MockUSDC deployed at:", deployedAddress);

        vm.stopBroadcast();
    }
}

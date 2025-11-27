// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../contracts/mocks/MockERC20.sol";

contract MintTokens is Script {
    function run() external {
        // Load deployment addresses
        string memory json = vm.readFile("./deployments/sepolia-latest.json");
        
        address mockUSDC = vm.parseJsonAddress(json, ".MockUSDC");
        address mockWstETH = vm.parseJsonAddress(json, ".MockWstETH");
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("\n=== Minting Test Tokens ===");
        console.log("User:", deployer);
        console.log("MockUSDC:", mockUSDC);
        console.log("MockWstETH:", mockWstETH);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Mint USDC
        MockERC20(mockUSDC).mint(deployer, 10_000 * 10**6); // 10,000 USDC
        console.log("Minted 10,000 USDC");
        
        // Mint wstETH
        MockERC20(mockWstETH).mint(deployer, 10 ether); // 10 wstETH
        console.log("Minted 10 wstETH");
        
        // Check balances
        console.log("\nBalances:");
        console.log("USDC:", MockERC20(mockUSDC).balanceOf(deployer));
        console.log("wstETH:", MockERC20(mockWstETH).balanceOf(deployer));
        
        vm.stopBroadcast();
        
        console.log("\n=== Minting Completed! ===");
    }
}

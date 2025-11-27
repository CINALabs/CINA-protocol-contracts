// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../contracts/mocks/MockERC20.sol";

/**
 * @title MintMoreTokens
 * @notice Mint more tokens to specified address
 */
contract MintMoreTokens is Script {
    function run() external {
        // Load deployment addresses
        string memory json = vm.readFile("./deployments/sepolia-real-tokens.json");
        
        address mintableUSDC = vm.parseJsonAddress(json, ".MintableUSDC");
        address mintableWstETH = vm.parseJsonAddress(json, ".MintableWstETH");
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // You can modify these amounts
        uint256 usdcAmount = 1_000_000_000_000_000 * 10**6; // 10^15 USDC
        uint256 wstETHAmount = 1_000_000_000_000_000 ether; // 10^15 wstETH
        
        console.log("\n==============================================");
        console.log("Minting More Tokens");
        console.log("==============================================");
        console.log("Recipient:", deployer);
        console.log("Mintable USDC:", mintableUSDC);
        console.log("Mintable wstETH:", mintableWstETH);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Check balances before
        console.log("\n--- Balances Before Minting ---");
        uint256 usdcBefore = MockERC20(mintableUSDC).balanceOf(deployer);
        uint256 wstETHBefore = MockERC20(mintableWstETH).balanceOf(deployer);
        console.log("USDC:", usdcBefore);
        console.log("  = ", usdcBefore / 1e6, "USDC");
        console.log("wstETH:", wstETHBefore);
        console.log("  = ", wstETHBefore / 1e18, "wstETH");
        
        // Mint USDC
        console.log("\n--- Minting Tokens ---");
        MockERC20(mintableUSDC).mint(deployer, usdcAmount);
        console.log("Minted USDC:", usdcAmount);
        console.log("  = 1,000,000,000,000,000 USDC");
        
        // Mint wstETH
        MockERC20(mintableWstETH).mint(deployer, wstETHAmount);
        console.log("Minted wstETH:", wstETHAmount);
        console.log("  = 1,000,000,000,000,000 wstETH");
        
        // Check balances after
        console.log("\n--- Balances After Minting ---");
        uint256 usdcAfter = MockERC20(mintableUSDC).balanceOf(deployer);
        uint256 wstETHAfter = MockERC20(mintableWstETH).balanceOf(deployer);
        console.log("USDC:", usdcAfter);
        console.log("  = ", usdcAfter / 1e6, "USDC");
        console.log("wstETH:", wstETHAfter);
        console.log("  = ", wstETHAfter / 1e18, "wstETH");
        
        vm.stopBroadcast();
        
        console.log("\n==============================================");
        console.log("Minting Completed!");
        console.log("==============================================");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../contracts/core/PoolManager.sol";
import "../contracts/core/FxUSDRegeneracy.sol";
import "../contracts/core/pool/AaveFundingPool.sol";
import "../contracts/mocks/MockERC20.sol";

contract TestOpenPosition is Script {
    function run() external {
        // Load deployment addresses
        string memory json = vm.readFile("./deployments/sepolia-latest.json");
        
        address poolManager = vm.parseJsonAddress(json, ".PoolManager");
        address fxUSD = vm.parseJsonAddress(json, ".FxUSD");
        address wstETHPool = vm.parseJsonAddress(json, ".WstETHPool");
        address mockWstETH = vm.parseJsonAddress(json, ".MockWstETH");
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("\n=== Testing Open Position ===");
        console.log("User:", deployer);
        console.log("PoolManager:", poolManager);
        console.log("WstETH Pool:", wstETHPool);
        console.log("MockWstETH:", mockWstETH);
        console.log("FxUSD:", fxUSD);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Mint test tokens
        console.log("\n--- Step 1: Minting test tokens ---");
        MockERC20 wstETH = MockERC20(mockWstETH);
        wstETH.mint(deployer, 10 ether);
        console.log("Minted 10 wstETH to", deployer);
        console.log("wstETH balance:", wstETH.balanceOf(deployer));
        
        // Step 2: Approve tokens
        console.log("\n--- Step 2: Approving tokens ---");
        wstETH.approve(poolManager, type(uint256).max);
        console.log("Approved wstETH to PoolManager");
        
        // Step 3: Open position
        console.log("\n--- Step 3: Opening position ---");
        uint256 collateralAmount = 1 ether; // 1 wstETH
        uint256 debtAmount = 1000 ether; // 1000 fxUSD
        
        console.log("Collateral amount:", collateralAmount);
        console.log("Debt amount:", debtAmount);
        
        PoolManager(poolManager).operate(
            wstETHPool,
            0, // new position
            collateralAmount,
            debtAmount,
            false
        );
        console.log("Position opened successfully!");
        
        // Step 4: Query position
        console.log("\n--- Step 4: Querying position ---");
        uint256 positionId = 1;
        (uint256 colls, uint256 debts) = AaveFundingPool(wstETHPool).getPosition(positionId);
        console.log("Position ID:", positionId);
        console.log("Collateral:", colls);
        console.log("Debt:", debts);
        
        // Step 5: Check balances
        console.log("\n--- Step 5: Checking balances ---");
        uint256 fxUSDBalance = FxUSDRegeneracy(fxUSD).balanceOf(deployer);
        uint256 wstETHBalance = wstETH.balanceOf(deployer);
        console.log("fxUSD balance:", fxUSDBalance);
        console.log("wstETH balance:", wstETHBalance);
        
        // Step 6: Check pool stats
        console.log("\n--- Step 6: Checking pool stats ---");
        console.log("Total collateral in pool:", AaveFundingPool(wstETHPool).totalCollateral());
        console.log("Total debt in pool:", AaveFundingPool(wstETHPool).totalDebt());
        
        vm.stopBroadcast();
        
        console.log("\n=== Test Completed Successfully! ===");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../contracts/core/PoolManager.sol";
import "../contracts/core/FxUSDRegeneracy.sol";
import "../contracts/core/pool/AaveFundingPool.sol";
import "../contracts/mocks/MockERC20.sol";

contract TestOpenPositionRealTokens is Script {
    function run() external {
        // Load deployment addresses
        string memory json = vm.readFile("./deployments/sepolia-real-tokens.json");
        
        address poolManager = vm.parseJsonAddress(json, ".PoolManager");
        address fxUSD = vm.parseJsonAddress(json, ".FxUSD");
        address wstETHPool = vm.parseJsonAddress(json, ".WstETHPool");
        address mintableWstETH = vm.parseJsonAddress(json, ".MintableWstETH");
        address mintableUSDC = vm.parseJsonAddress(json, ".MintableUSDC");
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("\n==============================================");
        console.log("Testing Open Position with Real Tokens");
        console.log("==============================================");
        console.log("User:", deployer);
        console.log("PoolManager:", poolManager);
        console.log("WstETH Pool:", wstETHPool);
        console.log("Mintable wstETH:", mintableWstETH);
        console.log("Mintable USDC:", mintableUSDC);
        console.log("FxUSD:", fxUSD);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Check initial balances
        console.log("\n--- Step 1: Checking Initial Balances ---");
        MockERC20 wstETH = MockERC20(mintableWstETH);
        MockERC20 usdc = MockERC20(mintableUSDC);
        
        uint256 wstETHBalance = wstETH.balanceOf(deployer);
        uint256 usdcBalance = usdc.balanceOf(deployer);
        
        console.log("wstETH balance:", wstETHBalance);
        console.log("  = ", wstETHBalance / 1e18, "wstETH");
        console.log("USDC balance:", usdcBalance);
        console.log("  = ", usdcBalance / 1e6, "USDC");
        
        // Step 2: Approve tokens
        console.log("\n--- Step 2: Approving Tokens ---");
        wstETH.approve(poolManager, type(uint256).max);
        console.log("Approved wstETH to PoolManager");
        
        // Step 3: Open position
        console.log("\n--- Step 3: Opening Position ---");
        uint256 collateralAmount = 1000 ether; // 1000 wstETH
        uint256 debtAmount = 1_000_000 ether; // 1,000,000 fxUSD
        
        console.log("Collateral amount:", collateralAmount);
        console.log("  = 1,000 wstETH");
        console.log("Debt amount:", debtAmount);
        console.log("  = 1,000,000 fxUSD");
        
        PoolManager(poolManager).operate(
            wstETHPool,
            0, // new position
            collateralAmount,
            debtAmount,
            false
        );
        console.log("Position opened successfully!");
        
        // Step 4: Query position
        console.log("\n--- Step 4: Querying Position ---");
        uint256 positionId = 1;
        (uint256 colls, uint256 debts) = AaveFundingPool(wstETHPool).getPosition(positionId);
        console.log("Position ID:", positionId);
        console.log("Collateral:", colls);
        console.log("  = ", colls / 1e18, "wstETH");
        console.log("Debt:", debts);
        console.log("  = ", debts / 1e18, "fxUSD");
        
        // Calculate debt ratio (assuming ETH = $3000)
        uint256 collateralValue = colls * 3000; // in USD (with 18 decimals)
        uint256 debtRatio = (debts * 1e18) / collateralValue;
        console.log("Debt Ratio:", debtRatio);
        console.log("  = ", (debtRatio * 100) / 1e18, "%");
        
        // Step 5: Check balances after opening
        console.log("\n--- Step 5: Checking Balances After Opening ---");
        uint256 fxUSDBalance = FxUSDRegeneracy(fxUSD).balanceOf(deployer);
        uint256 wstETHBalanceAfter = wstETH.balanceOf(deployer);
        
        console.log("fxUSD balance:", fxUSDBalance);
        console.log("  = ", fxUSDBalance / 1e18, "fxUSD");
        console.log("wstETH balance:", wstETHBalanceAfter);
        console.log("  = ", wstETHBalanceAfter / 1e18, "wstETH");
        
        // Step 6: Check pool stats
        console.log("\n--- Step 6: Checking Pool Stats ---");
        uint256 totalCollateral = AaveFundingPool(wstETHPool).totalCollateral();
        uint256 totalDebt = AaveFundingPool(wstETHPool).totalDebt();
        
        console.log("Total collateral in pool:", totalCollateral);
        console.log("  = ", totalCollateral / 1e18, "wstETH");
        console.log("Total debt in pool:", totalDebt);
        console.log("  = ", totalDebt / 1e18, "fxUSD");
        
        vm.stopBroadcast();
        
        console.log("\n==============================================");
        console.log("Test Completed Successfully!");
        console.log("==============================================");
    }
}

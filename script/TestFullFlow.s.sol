// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../contracts/core/PoolManager.sol";
import "../contracts/core/FxUSDRegeneracy.sol";
import "../contracts/core/pool/AaveFundingPool.sol";
import "../contracts/mocks/MockERC20.sol";

/**
 * @title TestFullFlow
 * @notice Complete flow test: open, add collateral, borrow more, repay, reduce collateral, close
 */
contract TestFullFlow is Script {
    PoolManager poolManager;
    FxUSDRegeneracy fxUSD;
    AaveFundingPool wstETHPool;
    MockERC20 mockWstETH;
    
    address user;
    uint256 positionId;
    
    function run() external {
        // Load deployment addresses
        string memory json = vm.readFile("./deployments/sepolia-latest.json");
        
        poolManager = PoolManager(vm.parseJsonAddress(json, ".PoolManager"));
        fxUSD = FxUSDRegeneracy(vm.parseJsonAddress(json, ".FxUSD"));
        wstETHPool = AaveFundingPool(vm.parseJsonAddress(json, ".WstETHPool"));
        mockWstETH = MockERC20(vm.parseJsonAddress(json, ".MockWstETH"));
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        user = vm.addr(deployerPrivateKey);
        
        console.log("\n========================================");
        console.log("f(x) Protocol Full Flow Test");
        console.log("========================================");
        console.log("User:", user);
        console.log("PoolManager:", address(poolManager));
        console.log("WstETH Pool:", address(wstETHPool));
        console.log("FxUSD:", address(fxUSD));
        console.log("MockWstETH:", address(mockWstETH));
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Prepare test tokens
        prepareTokens();
        
        // Test 1: Open position
        testOpenPosition();
        
        // Test 2: Add collateral
        testAddCollateral();
        
        // Test 3: Borrow more
        testBorrowMore();
        
        // Test 4: Repay debt
        testRepayDebt();
        
        // Test 5: Reduce collateral
        testReduceCollateral();
        
        // Test 6: Close position
        testClosePosition();
        
        vm.stopBroadcast();
        
        console.log("\n========================================");
        console.log("All tests completed!");
        console.log("========================================");
    }
    
    function prepareTokens() internal {
        console.log("\n--- Preparing Test Tokens ---");
        
        // Mint 20 wstETH
        mockWstETH.mint(user, 20 ether);
        console.log("Minted 20 wstETH");
        
        // Approve PoolManager
        mockWstETH.approve(address(poolManager), type(uint256).max);
        console.log("Approved wstETH to PoolManager");
        
        // Approve fxUSD (for repaying debt)
        fxUSD.approve(address(poolManager), type(uint256).max);
        console.log("Approved fxUSD to PoolManager");
        
        console.log("wstETH balance:", mockWstETH.balanceOf(user));
    }
    
    function testOpenPosition() internal {
        console.log("\n========================================");
        console.log("Test 1: Open Position");
        console.log("========================================");
        
        uint256 collateralAmount = 2 ether; // 2 wstETH
        uint256 debtAmount = 3000 ether; // 3000 fxUSD
        
        console.log("Deposit collateral:", collateralAmount);
        console.log("Borrow debt:", debtAmount);
        
        // Open position
        poolManager.operate(
            address(wstETHPool),
            0, // new position
            collateralAmount,
            debtAmount,
            false
        );
        
        positionId = 1;
        console.log("Position created, ID:", positionId);
        
        // Query position
        (uint256 colls, uint256 debts) = wstETHPool.getPosition(positionId);
        console.log("Current collateral:", colls);
        console.log("Current debt:", debts);
        console.log("Debt ratio:", (debts * 1e18) / (colls * 3000)); // Assuming ETH = $3000
        
        // Query balances
        console.log("fxUSD balance:", fxUSD.balanceOf(user));
        console.log("wstETH balance:", mockWstETH.balanceOf(user));
    }
    
    function testAddCollateral() internal {
        console.log("\n========================================");
        console.log("Test 2: Add Collateral");
        console.log("========================================");
        
        uint256 addCollateral = 1 ether; // Add 1 wstETH
        
        console.log("Adding collateral:", addCollateral);
        
        // Query state before
        (uint256 collsBefore, uint256 debtsBefore) = wstETHPool.getPosition(positionId);
        console.log("Before - Collateral:", collsBefore, "Debt:", debtsBefore);
        
        // Add collateral (no debt change)
        poolManager.operate(
            address(wstETHPool),
            positionId,
            addCollateral,
            0, // no debt change
            false
        );
        
        // Query state after
        (uint256 collsAfter, uint256 debtsAfter) = wstETHPool.getPosition(positionId);
        console.log("After - Collateral:", collsAfter, "Debt:", debtsAfter);
        console.log("New debt ratio:", (debtsAfter * 1e18) / (collsAfter * 3000));
    }
    
    function testBorrowMore() internal {
        console.log("\n========================================");
        console.log("Test 3: Borrow More");
        console.log("========================================");
        
        uint256 borrowMore = 1000 ether; // Borrow 1000 more fxUSD
        
        console.log("Borrowing more:", borrowMore);
        
        // Query state before
        (uint256 collsBefore, uint256 debtsBefore) = wstETHPool.getPosition(positionId);
        uint256 fxUSDBefore = fxUSD.balanceOf(user);
        console.log("Before - Collateral:", collsBefore, "Debt:", debtsBefore);
        console.log("Before - fxUSD balance:", fxUSDBefore);
        
        // Borrow more (no collateral change)
        poolManager.operate(
            address(wstETHPool),
            positionId,
            0, // no collateral change
            borrowMore,
            false
        );
        
        // Query state after
        (uint256 collsAfter, uint256 debtsAfter) = wstETHPool.getPosition(positionId);
        uint256 fxUSDAfter = fxUSD.balanceOf(user);
        console.log("After - Collateral:", collsAfter, "Debt:", debtsAfter);
        console.log("After - fxUSD balance:", fxUSDAfter);
        console.log("New debt ratio:", (debtsAfter * 1e18) / (collsAfter * 3000));
    }
    
    function testRepayDebt() internal {
        console.log("\n========================================");
        console.log("Test 4: Repay Debt");
        console.log("========================================");
        
        uint256 repayAmount = 500 ether; // Repay 500 fxUSD
        
        console.log("Repaying debt:", repayAmount);
        
        // Query state before
        (uint256 collsBefore, uint256 debtsBefore) = wstETHPool.getPosition(positionId);
        uint256 fxUSDBefore = fxUSD.balanceOf(user);
        console.log("Before - Collateral:", collsBefore, "Debt:", debtsBefore);
        console.log("Before - fxUSD balance:", fxUSDBefore);
        
        // Repay debt (negative means reduce)
        poolManager.operate(
            address(wstETHPool),
            positionId,
            0, // no collateral change
            -int256(repayAmount), // negative means repay
            false
        );
        
        // Query state after
        (uint256 collsAfter, uint256 debtsAfter) = wstETHPool.getPosition(positionId);
        uint256 fxUSDAfter = fxUSD.balanceOf(user);
        console.log("After - Collateral:", collsAfter, "Debt:", debtsAfter);
        console.log("After - fxUSD balance:", fxUSDAfter);
        console.log("New debt ratio:", (debtsAfter * 1e18) / (collsAfter * 3000));
    }
    
    function testReduceCollateral() internal {
        console.log("\n========================================");
        console.log("Test 5: Reduce Collateral");
        console.log("========================================");
        
        uint256 reduceAmount = 0.5 ether; // Withdraw 0.5 wstETH
        
        console.log("Reducing collateral:", reduceAmount);
        
        // Query state before
        (uint256 collsBefore, uint256 debtsBefore) = wstETHPool.getPosition(positionId);
        uint256 wstETHBefore = mockWstETH.balanceOf(user);
        console.log("Before - Collateral:", collsBefore, "Debt:", debtsBefore);
        console.log("Before - wstETH balance:", wstETHBefore);
        
        // Reduce collateral (negative means withdraw)
        poolManager.operate(
            address(wstETHPool),
            positionId,
            -int256(reduceAmount), // negative means withdraw
            0, // no debt change
            false
        );
        
        // Query state after
        (uint256 collsAfter, uint256 debtsAfter) = wstETHPool.getPosition(positionId);
        uint256 wstETHAfter = mockWstETH.balanceOf(user);
        console.log("After - Collateral:", collsAfter, "Debt:", debtsAfter);
        console.log("After - wstETH balance:", wstETHAfter);
        console.log("New debt ratio:", (debtsAfter * 1e18) / (collsAfter * 3000));
    }
    
    function testClosePosition() internal {
        console.log("\n========================================");
        console.log("Test 6: Close Position");
        console.log("========================================");
        
        // Query current position
        (uint256 colls, uint256 debts) = wstETHPool.getPosition(positionId);
        console.log("Current collateral:", colls);
        console.log("Current debt:", debts);
        
        uint256 wstETHBefore = mockWstETH.balanceOf(user);
        uint256 fxUSDBefore = fxUSD.balanceOf(user);
        console.log("Before - wstETH balance:", wstETHBefore);
        console.log("Before - fxUSD balance:", fxUSDBefore);
        
        // Close position (withdraw all collateral, repay all debt)
        poolManager.operate(
            address(wstETHPool),
            positionId,
            -int256(colls), // withdraw all collateral
            -int256(debts), // repay all debt
            false
        );
        
        console.log("Position closed");
        
        // Query state after
        (uint256 collsAfter, uint256 debtsAfter) = wstETHPool.getPosition(positionId);
        uint256 wstETHAfter = mockWstETH.balanceOf(user);
        uint256 fxUSDAfter = fxUSD.balanceOf(user);
        console.log("After - Collateral:", collsAfter, "Debt:", debtsAfter);
        console.log("After - wstETH balance:", wstETHAfter);
        console.log("After - fxUSD balance:", fxUSDAfter);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../contracts/core/PoolManager.sol";
import "../contracts/core/FxUSDRegeneracy.sol";
import "../contracts/core/FxUSDBasePool.sol";
import "../contracts/core/pool/AaveFundingPool.sol";
import "../contracts/mocks/MockERC20.sol";

contract CheckDeployment is Script {
    function run() external view {
        // Load deployment addresses
        string memory json = vm.readFile("./deployments/sepolia-latest.json");
        
        address poolManager = vm.parseJsonAddress(json, ".PoolManager");
        address fxUSD = vm.parseJsonAddress(json, ".FxUSD");
        address fxUSDBasePool = vm.parseJsonAddress(json, ".FxUSDBasePool");
        address wstETHPool = vm.parseJsonAddress(json, ".WstETHPool");
        address mockUSDC = vm.parseJsonAddress(json, ".MockUSDC");
        address mockWstETH = vm.parseJsonAddress(json, ".MockWstETH");
        
        console.log("\n=== Deployment Verification ===");
        
        // Check PoolManager
        console.log("\n--- PoolManager ---");
        console.log("Address:", poolManager);
        try PoolManager(poolManager).fxUSD() returns (address _fxUSD) {
            console.log("fxUSD:", _fxUSD);
            console.log("Status: OK");
        } catch {
            console.log("Status: FAILED - Cannot read fxUSD");
        }
        
        // Check FxUSD
        console.log("\n--- FxUSD ---");
        console.log("Address:", fxUSD);
        try FxUSDRegeneracy(fxUSD).name() returns (string memory name) {
            console.log("Name:", name);
            try FxUSDRegeneracy(fxUSD).symbol() returns (string memory symbol) {
                console.log("Symbol:", symbol);
            } catch {}
            try FxUSDRegeneracy(fxUSD).totalSupply() returns (uint256 supply) {
                console.log("Total Supply:", supply);
            } catch {}
            console.log("Status: OK");
        } catch {
            console.log("Status: FAILED - Cannot read name");
        }
        
        // Check FxUSDBasePool
        console.log("\n--- FxUSDBasePool ---");
        console.log("Address:", fxUSDBasePool);
        try FxUSDBasePool(fxUSDBasePool).name() returns (string memory name) {
            console.log("Name:", name);
            console.log("Status: OK");
        } catch {
            console.log("Status: FAILED - Cannot read name");
        }
        
        // Check wstETH Pool
        console.log("\n--- wstETH Pool ---");
        console.log("Address:", wstETHPool);
        try AaveFundingPool(wstETHPool).name() returns (string memory name) {
            console.log("Name:", name);
            try AaveFundingPool(wstETHPool).symbol() returns (string memory symbol) {
                console.log("Symbol:", symbol);
            } catch {}
            try AaveFundingPool(wstETHPool).totalCollateral() returns (uint256 collateral) {
                console.log("Total Collateral:", collateral);
            } catch {}
            try AaveFundingPool(wstETHPool).totalDebt() returns (uint256 debt) {
                console.log("Total Debt:", debt);
            } catch {}
            console.log("Status: OK");
        } catch {
            console.log("Status: FAILED - Cannot read name");
        }
        
        // Check Mock Tokens
        console.log("\n--- Mock Tokens ---");
        console.log("MockUSDC:", mockUSDC);
        try MockERC20(mockUSDC).symbol() returns (string memory symbol) {
            console.log("  Symbol:", symbol);
        } catch {}
        
        console.log("MockWstETH:", mockWstETH);
        try MockERC20(mockWstETH).symbol() returns (string memory symbol) {
            console.log("  Symbol:", symbol);
        } catch {}
        
        console.log("\n=== Verification Complete ===");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../contracts/core/pool/AaveFundingPool.sol";

contract DebugPool is Script {
    function run() external {
        string memory json = vm.readFile("./deployments/sepolia-latest.json");
        address wstETHPool = vm.parseJsonAddress(json, ".WstETHPool");
        
        // We can call internal functions if we inherit? No, wstETHPool is external.
        // We can call public view functions.
        
        (uint256 minRatio, uint256 maxRatio) = AaveFundingPool(wstETHPool).getDebtRatioRange();
        console.log("Min Ratio:", minRatio);
        console.log("Max Ratio:", maxRatio);
        
        (uint256 debtIndex, uint256 collIndex) = AaveFundingPool(wstETHPool).getDebtAndCollateralIndex();
        console.log("Debt Index:", debtIndex);
        console.log("Coll Index:", collIndex);
        
        // We cannot check price directly from pool as priceOracle is public but returns address.
        // But we can check the oracle address.
        // address oracle = AaveFundingPool(wstETHPool).priceOracle();
        // console.log("Price Oracle:", oracle);
    }
}

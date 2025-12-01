// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../contracts/core/PoolConfiguration.sol";

contract SetFeeRatio is Script {
    function run() external {
        string memory json = vm.readFile("./deployments/sepolia-latest.json");
        address wstETHPool = vm.parseJsonAddress(json, ".WstETHPool");
        
        // From previous deployment logs
        address poolConfiguration = 0x6A89b52c02273560970bc932260947389d2082F6;

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);

        // Set fee ratio for WstETHPool
        // supplyRatioStep = 1 (non-zero to avoid ErrorInvalidPool)
        PoolConfiguration(poolConfiguration).updatePoolFeeRatio(
            wstETHPool,
            address(0), // default
            0, // supplyRatio
            1, // supplyRatioStep
            0, // withdrawFeeRatio
            0, // borrowFeeRatio
            0  // repayFeeRatio
        );
        
        console.log("Pool fee ratio updated");

        vm.stopBroadcast();
    }
}

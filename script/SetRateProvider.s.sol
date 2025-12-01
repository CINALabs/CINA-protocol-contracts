// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../contracts/core/PoolManager.sol";

contract SetRateProvider is Script {
    function run() external {
        string memory json = vm.readFile("./deployments/sepolia-latest.json");
        address poolManagerProxy = vm.parseJsonAddress(json, ".PoolManager");
        address mockWstETH = vm.parseJsonAddress(json, ".MockWstETH");
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);

        // Set rate provider for mockWstETH
        // provider = address(0) means standard ERC20 scaling
        PoolManager(poolManagerProxy).updateRateProvider(
            mockWstETH,
            address(0)
        );
        
        console.log("Rate provider updated for wstETH");

        vm.stopBroadcast();
    }
}

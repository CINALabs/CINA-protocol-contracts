// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../contracts/helpers/ProxyAdmin.sol";
import "../contracts/core/pool/AaveFundingPool.sol";

contract FixPool is Script {
    function run() external {
        string memory json = vm.readFile("./deployments/sepolia-latest.json");
        address poolManagerProxy = vm.parseJsonAddress(json, ".PoolManager");
        address wstETHPool = vm.parseJsonAddress(json, ".WstETHPool");
        address proxyAdmin = vm.parseJsonAddress(json, ".ProxyAdmin");
        
        // From previous deployment logs
        address poolConfiguration = 0x6A89b52c02273560970bc932260947389d2082F6;

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);

        // Deploy new AaveFundingPool Implementation
        // constructor(poolManager, configuration)
        address newPoolImpl = address(new AaveFundingPool(
            poolManagerProxy,
            poolConfiguration
        ));
        console.log("New AaveFundingPool Implementation:", newPoolImpl);

        // Upgrade WstETHPool
        // Use name() as harmless view function call
        bytes memory upgradeData = abi.encodeWithSignature("name()");
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(wstETHPool),
            newPoolImpl,
            upgradeData
        );
        console.log("WstETHPool Upgraded");

        vm.stopBroadcast();
    }
}

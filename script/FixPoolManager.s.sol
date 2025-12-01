// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../contracts/helpers/ProxyAdmin.sol";
import "../contracts/core/PoolManager.sol";

contract FixPoolManager is Script {
    function run() external {
        string memory json = vm.readFile("./deployments/sepolia-latest.json");
        address poolManagerProxy = vm.parseJsonAddress(json, ".PoolManager");
        address fxUSDProxy = vm.parseJsonAddress(json, ".FxUSD");
        address fxUSDBasePoolProxy = vm.parseJsonAddress(json, ".FxUSDBasePool");
        address pegKeeperProxy = vm.parseJsonAddress(json, ".PegKeeper");
        address proxyAdmin = vm.parseJsonAddress(json, ".ProxyAdmin");
        
        // From previous fix script logs
        address poolConfiguration = 0x6A89b52c02273560970bc932260947389d2082F6;

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);

        // Deploy new PoolManager Implementation
        address newPoolManagerImpl = address(new PoolManager(
            fxUSDProxy,
            fxUSDBasePoolProxy,
            pegKeeperProxy,
            poolConfiguration,
            address(0)
        ));
        console.log("New PoolManager Implementation:", newPoolManagerImpl);

        // Upgrade PoolManager
        // Use harmless view call
        bytes memory upgradeData = abi.encodeWithSignature("getTokenScalingFactor(address)", address(0));
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(poolManagerProxy),
            newPoolManagerImpl,
            upgradeData
        );
        console.log("PoolManager Upgraded");

        vm.stopBroadcast();
    }
}

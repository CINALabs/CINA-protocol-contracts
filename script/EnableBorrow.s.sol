// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract EnableBorrow is Script {
    function run() external {
        string memory json = vm.readFile("./deployments/sepolia-latest.json");
        address wstETHPool = vm.parseJsonAddress(json, ".WstETHPool");
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("Updating borrow and redeem status for pool:", wstETHPool);
        
        // false = unpaused (enabled)
        (bool success, ) = wstETHPool.call(
            abi.encodeWithSignature("updateBorrowAndRedeemStatus(bool,bool)", false, false)
        );
        require(success, "Failed to update borrow and redeem status");
        
        console.log("Borrow and redeem enabled (unpaused)");
        
        vm.stopBroadcast();
    }
}

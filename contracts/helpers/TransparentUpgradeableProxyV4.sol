// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TransparentUpgradeableProxy as OZTransparentUpgradeableProxyV4} from "@openzeppelin/contracts-v4/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title TransparentUpgradeableProxyV4
 * @dev Wrapper for OpenZeppelin v4's TransparentUpgradeableProxy
 * In v4, the second parameter is the admin address (not initialOwner)
 */
contract TransparentUpgradeableProxyV4 is OZTransparentUpgradeableProxyV4 {
    constructor(
        address _logic,
        address admin_,
        bytes memory _data
    ) OZTransparentUpgradeableProxyV4(_logic, admin_, _data) {}
}

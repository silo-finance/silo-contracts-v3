// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {TransparentUpgradeableProxy} from "openzeppelin5/proxy/transparent/TransparentUpgradeableProxy.sol";

contract TransparentProxy is TransparentUpgradeableProxy {
    constructor(address _implementation, address _proxyAdminOwner, bytes memory _initData)
        TransparentUpgradeableProxy(_implementation, _proxyAdminOwner, _initData)
    {}

    receive() external payable {}

    function getAdmin() public view returns (address) {
        return _proxyAdmin();
    }
}

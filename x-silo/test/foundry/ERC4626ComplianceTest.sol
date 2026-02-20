// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {ERC4626Test} from "a16z-erc4626-tests/ERC4626.test.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {ERC20Mock} from "openzeppelin5/mocks/token/ERC20Mock.sol";

import {XSilo} from "../../contracts/XSilo.sol";
import {XSiloAndStreamDeploy} from "x-silo/deploy/XSiloAndStreamDeploy.s.sol";
import {AddrKey} from "common/addresses/AddrKey.sol";

/*
 FOUNDRY_PROFILE=x_silo forge test --ffi --mc ERC4626ComplianceTest -vvv
*/
contract ERC4626ComplianceTest is ERC4626Test {
    function setUp() public override {
        AddrLib.init();

        ERC20Mock asset = new ERC20Mock();
        AddrLib.setAddress(AddrKey.SILO_TOKEN_V2, address(asset));
        AddrLib.setAddress(AddrKey.DAO, address(this));

        XSiloAndStreamDeploy deploy = new XSiloAndStreamDeploy();
        deploy.disableDeploymentsSync();
        (XSilo vault,) = deploy.run();

        _underlying_ = address(asset);
        _vault_ = address(vault);
        _delta_ = 0;
        _vaultMayBeEmpty = true;
        _unlimitedAmount = true;
    }
}

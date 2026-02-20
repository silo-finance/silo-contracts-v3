// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";

import {CAP} from "../../helpers/BaseTest.sol";
import {IntegrationTest} from "../../helpers/IntegrationTest.sol";

abstract contract VaultsLittleHelper is IntegrationTest {
    function setUp() public override {
        super.setUp();

        _setCap(allMarkets[0], CAP);
        _sortSupplyQueueIdleLast();

        // to not set "trap" in tests, silos are resseted to 0
        // if you need silo use allMarkets array
        silo0 = ISilo(address(0));
        silo1 = ISilo(address(0));
    }

    function _silo0() internal view returns (ISilo) {
        return ISilo(address(collateralMarkets[IERC4626(address(_silo1()))]));
    }

    function _silo1() internal view returns (ISilo) {
        return ISilo(address(allMarkets[0]));
    }

    function _deposit(uint256 _assets, address _depositor) internal override returns (uint256 shares) {
        return _makeDeposit(_assets, _depositor);
    }

    function _mint(uint256 _shares, address _depositor) internal returns (uint256 assets) {
        return _makeMint(_shares, _depositor);
    }

    function _redeem(uint256 _amount, address _depositor) internal override returns (uint256 assets) {
        vm.prank(_depositor);
        return vault.redeem(_amount, _depositor, _depositor);
    }

    function _withdraw(uint256 _amount, address _depositor) internal override returns (uint256 shares) {
        vm.prank(_depositor);
        return vault.withdraw(_amount, _depositor, _depositor);
    }

    function _makeDeposit(uint256 _assets, address _depositor) internal returns (uint256 shares) {
        vm.prank(_depositor);
        shares = vault.deposit(_assets, _depositor);
    }

    function _makeDeposit(uint256 _assets, address _depositor, bytes4 _error) internal returns (uint256 shares) {
        vm.prank(_depositor);
        vm.expectRevert(_error);
        shares = vault.deposit(_assets, _depositor);
    }

    function _makeMint(uint256 _shares, address _depositor) internal returns (uint256 assets) {
        vm.prank(_depositor);
        assets = vault.mint(_shares, _depositor);
    }
}

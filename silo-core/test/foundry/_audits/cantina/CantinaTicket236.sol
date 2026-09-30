// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {SiloIncentivesControllerCompatible} from "silo-core/contracts/incentives/SiloIncentivesControllerCompatible.sol";

import {SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";

import {SiloConfigOverride} from "../../_common/fixtures/SiloFixture.sol";
import {SiloFixture} from "../../_common/fixtures/SiloFixture.sol";
import {DummyOracle} from "../../_common/DummyOracle.sol";
import {MintableToken} from "../../_common/MintableToken.sol";
import {CantinaTicket} from "./CantinaTicket.sol";

/*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc CantinaTicket236
*/
contract CantinaTicket236 is CantinaTicket {
    SiloIncentivesControllerCompatible internal _controller;

    address internal _owner = makeAddr("Owner");
    address internal _notifier;
    MintableToken internal _rewardToken;

    uint256 internal constant _PRECISION = 10 ** 18;
    uint256 internal constant _TOTAL_SUPPLY = 1000e18;
    string internal constant _PROGRAM_NAME = "Test";
    string internal constant _PROGRAM_NAME_2 = "Test2";

    DummyOracle solvencyOracle0;
    DummyOracle maxLtvOracle0;

    function setUp() public override {
        token0 = new MintableToken(18);
        token1 = new MintableToken(18);
        solvencyOracle0 = new DummyOracle(1e18, address(token1));
        maxLtvOracle0 = new DummyOracle(1e18, address(token1));

        SiloConfigOverride memory overrides;
        overrides.token0 = address(token0);
        overrides.token1 = address(token1);
        overrides.solvencyOracle0 = address(solvencyOracle0);
        overrides.maxLtvOracle0 = address(maxLtvOracle0);
        overrides.configName = SiloConfigsNames.SILO_LOCAL_BEFORE_CALL;

        SiloFixture siloFixture = new SiloFixture();

        (, silo0, silo1,,,) = siloFixture.deploy_local(overrides);

        solvencyOracle0.setExpectBeforeQuote(true);
        maxLtvOracle0.setExpectBeforeQuote(true);
    }

    function test_double_claim_rewards() public {
        address user1 = address(1);
        uint256 collateralAmount = 1e18;

        _depositForBorrow(1e18, user1);
        _deposit(collateralAmount, address(this));

        uint256 quoteAmount = 3;

        vm.mockCall(
            address(maxLtvOracle0),
            abi.encodeWithSelector(DummyOracle.quote.selector, collateralAmount, address(token0)),
            ""
        );

        // emit log_named_decimal_uint("quote(token0)", maxLtvOracle0.quote(quoteAmount, address(token0)), 18);

        vm.expectRevert();
        _borrow(quoteAmount, address(this));
    }
}

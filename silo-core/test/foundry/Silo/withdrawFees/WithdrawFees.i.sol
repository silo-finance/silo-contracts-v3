// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {Strings} from "openzeppelin5/utils/Strings.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

import {MintableToken} from "../../_common/MintableToken.sol";
import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";
import {SiloConfigOverride} from "../../_common/fixtures/SiloFixture.sol";
import {SiloFixture} from "../../_common/fixtures/SiloFixture.sol";

/*
    forge test -vv --ffi --mc WithdrawFeesIntegrationTest
*/
contract WithdrawFeesIntegrationTest is SiloLittleHelper, Test {
    uint256 constant INTEREST_TO_COMPARE = 103;
    uint256 constant INTEREST_TIME = 1 days;

    address user = makeAddr("user");
    address borrower = makeAddr("borrower");

    function _setUp(uint256 _amount, uint8 _decimals) public {
        SiloFixture siloFixture = new SiloFixture();

        SiloConfigOverride memory configOverride;

        token0 = new MintableToken(_decimals);
        token1 = new MintableToken(_decimals);

        token0.setOnDemand(true);
        token1.setOnDemand(true);

        configOverride.token0 = address(token0);
        configOverride.token1 = address(token1);

        (, silo0, silo1,,,) = siloFixture.deploy_local(configOverride);

        uint256 one = 10 ** _decimals;

        _depositForBorrow(_amount * one, user);
        _deposit(_amount * one, borrower);
        _borrow(_fragmentedAmount(_amount * one / 2, _decimals - 1), borrower);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_fee_priority
    */
    function test_fee_priority() public {
        uint8 _decimals = 18;

        _setUp(1e18, _decimals);

        vm.startPrank(address(silo1));
        // mock attack, leave just 1 wei of liquidity
        token1.transfer(address(1), token1.balanceOf(address(silo1)) - 1);
        vm.stopPrank();

        vm.warp(block.timestamp + 1);
        silo1.accrueInterest();

        vm.expectEmit(address(silo1));
        uint256 daoFees = 1; // DAO have higher priority
        uint256 deployerFees = 0;
        emit ISilo.WithdrawnFees(daoFees, deployerFees, false);
        silo1.withdrawFees();
    }

    /*
    forge test -vv --ffi --mt test_fee_oneToken_18
    */
    function test_fee_oneToken_18() public {
        uint8 _decimals = 18;

        _setUp(1, _decimals);

        vm.warp(block.timestamp + 1);
        uint256 interest = silo1.accrueInterest();

        (uint192 daoAndDeployerRevenue,,,,) = silo1.getSiloStorage();
        ISilo.Fractions memory fractions = silo1.getFractionsStorage();

        emit log_named_uint("interest", interest);
        emit log_named_uint("fractions.interest", fractions.interest);
        emit log_named_uint("fractions.revenue", fractions.revenue);
        emit log_named_uint("daoAndDeployerRevenue", daoAndDeployerRevenue);

        assertEq(interest, 1159717550, "interest");
        assertEq(fractions.interest, 0, "expect NO fractions because of threshold");

        assertEq(fractions.revenue, 0, "expect NO fractions because of threshold");
        assertEq(daoAndDeployerRevenue, 289929387, "expect daoAndDeployerRevenue");

        vm.expectEmit(address(silo1));
        uint256 daoFees = 173957633;
        uint256 deployerFees = 115971754;
        emit ISilo.WithdrawnFees(daoFees, deployerFees, false);
        silo1.withdrawFees();
    }

    /*
    forge test -vv --ffi --mt test_fee_oneToken_8
    */
    function test_fee_oneToken_8() public {
        uint8 _decimals = 8;

        // we have 8 decimals, so with higher amount, we should get similar results as for 18
        _setUp(1, _decimals);

        vm.warp(block.timestamp + 1);
        uint256 interest = silo1.accrueInterest();

        (uint192 daoAndDeployerRevenue,,,,) = silo1.getSiloStorage();
        ISilo.Fractions memory fractions = silo1.getFractionsStorage();

        emit log_named_uint("interest", interest);
        emit log_named_uint("fractions.interest", fractions.interest);
        emit log_named_uint("fractions.revenue", fractions.revenue);
        emit log_named_uint("daoAndDeployerRevenue", daoAndDeployerRevenue);

        assertEq(interest, 0, "interest");
        assertEq(fractions.interest, 115971754552331934, "expect fractions.interest");

        assertEq(daoAndDeployerRevenue, 0, "expect daoAndDeployerRevenue");
        assertEq(fractions.revenue, 0, "expect NO fractions.revenue (this is delayed)");

        vm.expectRevert();
        silo1.withdrawFees();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_fee_oneToken_6
    */
    function test_fee_oneToken_6() public {
        uint8 _decimals = 6;

        _setUp(1, _decimals);

        uint192 prevDaoAndDeployerRevenue;
        uint256 prevInterest;
        uint64 prevInterestFraction;
        uint64 prevRevenueFraction;
        uint256 interest;

        for (uint256 t = 1; t < 24 hours; t++) {
            vm.warp(block.timestamp + 1);
            interest = silo1.accrueInterest();

            if (interest != 0) {
                emit log_named_uint("we got interest after s", t);
                emit log_named_uint("interest", interest);
                break;
            }

            (ISilo.Fractions memory fractions, uint192 daoAndDeployerRevenue) = _printFractions(interest);

            assertEq(
                interest,
                0,
                string.concat("#", Strings.toString(t), " interest zero, decimals too small to generate it")
            );

            assertEq(
                daoAndDeployerRevenue,
                prevDaoAndDeployerRevenue,
                string.concat("#", Strings.toString(t), " revenue stay zero until we got interest")
            );

            assertGt(
                fractions.interest,
                prevInterestFraction,
                string.concat("#", Strings.toString(t), "prevInterestFraction incrementing")
            );

            if (prevInterest == interest) {
                assertEq(
                    fractions.revenue,
                    prevRevenueFraction,
                    string.concat(
                        "#", Strings.toString(t), "revenueFraction not changed, because interest did not increased"
                    )
                );
            } else {
                assertGt(
                    daoAndDeployerRevenue * 1e18 + fractions.revenue,
                    prevDaoAndDeployerRevenue * 1e18 + prevRevenueFraction,
                    string.concat("#", Strings.toString(t), "Revenue incrementing")
                );
            }

            prevDaoAndDeployerRevenue = daoAndDeployerRevenue;
            prevInterest = interest;
            prevInterestFraction = fractions.interest;
            prevRevenueFraction = fractions.revenue;

            vm.expectRevert();
            silo1.withdrawFees();
        }

        assertGt(interest, 0, "expect some interest at this point");

        (ISilo.Fractions memory fractions_,) = _printFractions(interest);

        assertLt(
            fractions_.interest,
            prevInterestFraction,
            "prevInterestFraction is result of modulo, so once we got interest it should circle-drop"
        );

        vm.warp(block.timestamp + 6050);
        emit log("warp... 6050");
        (, prevDaoAndDeployerRevenue) = _printFractions(silo1.accrueInterest());

        vm.expectEmit(address(silo1));
        emit ISilo.WithdrawnFees(2, 0, false);

        silo1.withdrawFees();

        assertGe(
            prevDaoAndDeployerRevenue,
            2,
            "expect revenue to be at lest 2 wei, because it has to be split by 2 to be ready to withdraw"
        );

        emit log_named_decimal_uint("# daoAndDeployerRevenue", prevDaoAndDeployerRevenue, 18);

        (uint256 daoAndDeployerRevenue_,,,,) = silo1.getSiloStorage();
        assertLt(daoAndDeployerRevenue_, 10 ** _decimals, "[daoAndDeployerRevenue] only fraction left < 1e18");
    }

    /*
    forge test -vv --ffi --mt test_fee_compare_days
    */
    function test_fee_compare_days() public {
        uint8 _decimals = 6;

        _setUp(1, _decimals);

        vm.warp(block.timestamp + INTEREST_TIME);

        uint256 interest = silo1.accrueInterest();

        assertEq(interest, INTEREST_TO_COMPARE, "compare: days at once");
    }

    /*
    forge test -vv --ffi --mt test_fee_compare_second
    */
    function test_fee_compare_second() public {
        uint8 _decimals = 6;

        _setUp(1, _decimals);

        uint256 sum;

        for (uint256 i; i < INTEREST_TIME; i++) {
            vm.warp(block.timestamp + 1);
            sum += silo1.accrueInterest();
        }

        assertEq(sum, INTEREST_TO_COMPARE, "compare: per second, it should be equal");
    }

    function _fragmentedAmount(uint256 _amount, uint8 _decimals) internal pure returns (uint256) {
        for (uint256 i; i < _decimals; i++) {
            _amount += 10 ** i;
        }

        return _amount;
    }

    function _printFractions(uint256 interest)
        internal
        returns (ISilo.Fractions memory fractions, uint192 daoAndDeployerRevenue)
    {
        (daoAndDeployerRevenue,,,,) = silo1.getSiloStorage();
        fractions = silo1.getFractionsStorage();

        emit log_named_uint("interest", interest);
        emit log_named_uint("fractions.interest", fractions.interest);
        emit log_named_uint("fractions.revenue", fractions.revenue);
        emit log_named_uint("daoAndDeployerRevenue", daoAndDeployerRevenue);
    }

    /*
    forge test -vv --ffi --mt test_plus_minus
    */
    function test_plus_minus() public {
        uint256 integralInterest = 0;
        uint256 integralRevenue = 1;
        uint256 variable = 1; // must be at least one

        vm.expectRevert();
        variable += integralInterest - integralRevenue;

        variable = variable + integralInterest - integralRevenue;
    }
}

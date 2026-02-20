// // SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";

import {TestERC20} from "silo-core/test/invariants/utils/mocks/TestERC20.sol";
import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";
import {OracleScaler} from "silo-oracles/contracts/scaler/OracleScaler.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {OracleScalerFactory} from "silo-oracles/contracts/scaler/OracleScalerFactory.sol";
import {OracleScalerDeploy} from "silo-oracles/deploy/oracle-scaler/OracleScalerDeploy.s.sol";
import {OracleScalerFactoryDeploy} from "silo-oracles/deploy/oracle-scaler/OracleScalerFactoryDeploy.s.sol";

/*
    FOUNDRY_PROFILE=oracles forge test -vv --match-contract OracleScalerTest --ffi
*/
contract OracleScalerTest is Test {
    OracleScalerDeploy oracleDeployer;
    OracleScalerFactory factory;

    address USDC = address(new TestERC20("", "", 6));

    event OracleScalerCreated(ISiloOracle indexed oracleScaler);

    function setUp() public {
        AddrLib.init();
        AddrLib.setAddress("USDC.e", USDC);

        OracleScalerFactoryDeploy oracleFactoryDeploy = new OracleScalerFactoryDeploy();
        oracleFactoryDeploy.disableDeploymentsSync();

        factory = OracleScalerFactory(oracleFactoryDeploy.run());

        oracleDeployer = new OracleScalerDeploy();
        oracleDeployer.setQuoteTokenKey("USDC.e");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test -vvv --mt test_OracleScalerFactory_createOracleScaler --ffi
    */
    function test_OracleScalerFactory_createOracleScaler() public {
        vm.expectEmit(false, false, false, false);
        emit OracleScalerCreated(ISiloOracle(address(0)));

        ISiloOracle scaler = ISiloOracle(oracleDeployer.run());

        assertTrue(factory.createdInFactory(scaler));
    }

    function test_OracleScaler_constructorVars() public {
        OracleScaler scaler = OracleScaler(address(oracleDeployer.run()));

        assertEq(scaler.DECIMALS_TO_SCALE(), 18, "18 decimals are set right as constant");
        assertEq(scaler.QUOTE_TOKEN(), USDC, "quote token is set correctly");
        assertEq(IERC20Metadata(USDC).decimals(), uint8(6), "usdc has 6 decimals");
        assertEq(scaler.SCALE_FACTOR(), 10 ** uint256(18 - 6), "scale factor is correct");
    }

    function test_OracleScaler_constructorReverts() public {
        TestERC20 tokenTooManyDecimals = new TestERC20("", "", 18);

        vm.expectRevert(OracleScaler.TokenDecimalsTooLarge.selector);
        factory.createOracleScaler(address(tokenTooManyDecimals), bytes32(0));
    }

    function test_OracleScaler_constructorScaleFactor() public {
        for (uint8 decimals; decimals < 18; decimals++) {
            TestERC20 token = new TestERC20("", "", decimals);
            OracleScaler scaler = OracleScaler(address(factory.createOracleScaler(address(token), bytes32(0))));

            assertEq(scaler.SCALE_FACTOR(), 10 ** uint256(18 - decimals), "scale factor is correct for all cases");
        }
    }

    function test_OracleScaler_quoteToken() public {
        ISiloOracle scaler = factory.createOracleScaler(USDC, bytes32(0));

        scaler.beforeQuote(address(0)); // does not revert
        assertEq(scaler.quoteToken(), USDC, "quote token is right");
    }

    function test_OracleScaler_quote() public {
        ISiloOracle scaler = factory.createOracleScaler(USDC, bytes32(0));

        assertEq(scaler.quote(10 ** 6, USDC), 10 ** 18, "scaling works as expected for one USDC");
        assertEq(scaler.quote(1, USDC), 10 ** 12, "scaling works as expected for one wei");

        uint256 bigAmountToScale = 12345 * 10 ** 6;
        assertEq(OracleScaler(address(scaler)).SCALE_FACTOR(), 10 ** 12, "scale factor is expected");
        assertEq(scaler.quote(bigAmountToScale, USDC) / bigAmountToScale, 10 ** 12, "scaling multiplies by factor");
    }

    function test_OracleScaler_quote_reverts_ZeroPrice() public {
        ISiloOracle scaler = factory.createOracleScaler(USDC, bytes32(0));

        vm.expectRevert(OracleScaler.ZeroPrice.selector);
        scaler.quote(0, USDC);
    }

    function test_OracleScaler_quoteReverts() public {
        ISiloOracle scaler = factory.createOracleScaler(USDC, bytes32(0));

        vm.expectRevert(OracleScaler.AssetNotSupported.selector);
        scaler.quote(0, address(0));
    }

    function test_OracleScaler_reorg() public {
        address eoa1 = makeAddr("eoa1");
        address eoa2 = makeAddr("eoa2");

        uint256 snapshot = vm.snapshotState();

        vm.prank(eoa1);
        ISiloOracle scaler1 = factory.createOracleScaler(USDC, bytes32(0));

        vm.revertToState(snapshot);

        vm.prank(eoa2);
        ISiloOracle scaler2 = factory.createOracleScaler(USDC, bytes32(0));

        assertNotEq(address(scaler1), address(scaler2), "scaler1 == scaler2");
    }
}

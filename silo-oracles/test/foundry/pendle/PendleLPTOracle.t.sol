// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {IPendleOracleHelper} from "silo-oracles/contracts/pendle/interfaces/IPendleOracleHelper.sol";
import {PendleLPTOracle} from "silo-oracles/contracts/pendle/lp-tokens/PendleLPTOracle.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {PendleLPTToSyOracleFactory} from "silo-oracles/contracts/pendle/lp-tokens/PendleLPTToSyOracleFactory.sol";
import {PendleLPTToAssetOracleFactory} from
    "silo-oracles/contracts/pendle/lp-tokens/PendleLPTToAssetOracleFactory.sol";
import {PendleLPTToSyOracleDeploy} from "silo-oracles/deploy/pendle/PendleLPTToSyOracleDeploy.s.sol";
import {PendleLPTToAssetOracleDeploy} from "silo-oracles/deploy/pendle/PendleLPTToAssetOracleDeploy.s.sol";
import {PendleLPTToSyOracleFactoryDeploy} from "silo-oracles/deploy/pendle/PendleLPTToSyOracleFactoryDeploy.s.sol";
import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";
import {PendleLPTToAssetOracle} from "silo-oracles/contracts/pendle/lp-tokens/PendleLPTToAssetOracle.sol";
import {PendleLPTToAssetOracleFactoryDeploy} from
    "silo-oracles/deploy/pendle/PendleLPTToAssetOracleFactoryDeploy.s.sol";

/*
    FOUNDRY_PROFILE=oracles forge test --mc PendleLPTOracleTest --ffi -vv
*/
contract PendleLPTOracleTest is Test {
    uint32 public constant TWAP_DURATION = 30 minutes;
    IPendleOracleHelper public constant PENDLE_ORACLE =
        IPendleOracleHelper(0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2);

    PendleLPTToSyOracleFactory factoryToSy;
    PendleLPTToAssetOracleFactory factoryToAsset;
    PendleLPTOracle oracleSy;
    PendleLPTOracle oracleAsset;

    event PendleLPTOracleCreated(ISiloOracle indexed pendleLPTOracle);

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_SONIC"), 29883290); // forking block may 27 2025

        PendleLPTToSyOracleFactoryDeploy factorySyDeploy = new PendleLPTToSyOracleFactoryDeploy();
        factorySyDeploy.disableDeploymentsSync();
        factoryToSy = PendleLPTToSyOracleFactory(factorySyDeploy.run());

        PendleLPTToAssetOracleFactoryDeploy factoryAssetDeploy = new PendleLPTToAssetOracleFactoryDeploy();
        factoryToAsset = PendleLPTToAssetOracleFactory(factoryAssetDeploy.run());
    }

    /*
    FOUNDRY_PROFILE=oracles forge test --mt test_LPTToAssetOracle_deploy --ffi -vv
     */
    function test_LPTToAssetOracle_deploy() public {
        ISiloOracle underlyingOracle = ISiloOracle(0x8c5bb146f416De3fbcD8168cC844aCf4Aa2098c5); // USDC/USD
        address market = 0x3F5EA53d1160177445B1898afbB16da111182418; // AUSDC (14 Aug 2025)

        vm.mockCall(
            address(PENDLE_ORACLE),
            abi.encodeWithSelector(IPendleOracleHelper.getOracleState.selector, address(market), TWAP_DURATION),
            abi.encode(true, 0, true)
        );

        vm.expectRevert(PendleLPTOracle.IncreaseCardinalityRequired.selector);
        new PendleLPTToAssetOracle(underlyingOracle, market);

        vm.mockCall(
            address(PENDLE_ORACLE),
            abi.encodeWithSelector(IPendleOracleHelper.getOracleState.selector, address(market), TWAP_DURATION),
            abi.encode(false, 0, false)
        );

        vm.expectRevert(PendleLPTOracle.OldestObservationSatisfied.selector);
        new PendleLPTToAssetOracle(underlyingOracle, market);

        vm.mockCall(
            address(PENDLE_ORACLE),
            abi.encodeWithSelector(IPendleOracleHelper.getOracleState.selector, address(market), TWAP_DURATION),
            abi.encode(false, 0, true)
        );

        vm.mockCall(
            address(PENDLE_ORACLE),
            abi.encodeWithSelector(IPendleOracleHelper.getLpToAssetRate.selector, address(market), TWAP_DURATION),
            abi.encode(0)
        );

        vm.expectRevert(PendleLPTOracle.PendleRateIsZero.selector);
        new PendleLPTToAssetOracle(underlyingOracle, market);
    }

    /*
    FOUNDRY_PROFILE=oracles forge test --mt test_LPTToAssetOracle_getPrice --ffi -vv
    */
    function test_LPTToAssetOracle_getPrice() public {
        ISiloOracle underlyingOracle = ISiloOracle(0x8c5bb146f416De3fbcD8168cC844aCf4Aa2098c5); // USDC/USD
        address market = 0x3F5EA53d1160177445B1898afbB16da111182418; // AUSDC (14 Aug 2025)

        PendleLPTToAssetOracleDeploy oracleAssetDeploy = new PendleLPTToAssetOracleDeploy();
        oracleAssetDeploy.setParams(market, underlyingOracle);

        oracleAsset = PendleLPTOracle(address(oracleAssetDeploy.run()));

        uint256 price = oracleAsset.quote(1e18, market);
        assertEq(price, 2049835019614218201342436720000);
        assertEq(price, oracleAsset.quote(1e18, oracleAsset.baseToken()), "quote with baseToken");

        assertEq(oracleAsset.VERSION(), "PendleLPTToAssetOracle 4.0.0", "VERSION");
    }

    /*
    FOUNDRY_PROFILE=oracles forge test --mt test_LPTToSyOracle_getPrice --ffi -vv
    */
    function test_LPTToSyOracle_getPrice() public {
        ISiloOracle underlyingOracle = ISiloOracle(0x4D7262786976917f0d7a83d6Ef3089273e117cF7); // stS/USD
        address market = 0x3aeF1d372d0a7a7E482F465Bc14A42D78f920392; // stS (may 29 2025)

        PendleLPTToSyOracleDeploy oracleSyDeploy = new PendleLPTToSyOracleDeploy();
        oracleSyDeploy.setParams(market, underlyingOracle);

        oracleSy = PendleLPTOracle(address(oracleSyDeploy.run()));

        uint256 price = oracleSy.quote(1e18, market);
        assertEq(price, 1115338829967733590);
        assertEq(price, oracleSy.quote(1e18, oracleSy.baseToken()), "quote with baseToken");

        assertEq(oracleSy.VERSION(), "PendleLPTToSyOracle 4.0.0", "VERSION");
    }
}

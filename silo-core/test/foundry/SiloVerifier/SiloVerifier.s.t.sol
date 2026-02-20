// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";

import {SiloVerifier} from "silo-core/deploy/silo/verifier/SiloVerifier.sol";
import {
    InterestRateModelV2, IInterestRateModelV2
} from "silo-core/contracts/interestRateModel/InterestRateModelV2.sol";
import {IInterestRateModelV2Config} from "silo-core/contracts/interfaces/IInterestRateModelV2Config.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IGaugeHookReceiver} from "silo-core/contracts/hooks/gauge/GaugeHookReceiver.sol";
import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";
import {Ownable} from "openzeppelin5/access/Ownable2Step.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloFactory} from "silo-core/contracts/interfaces/ISiloFactory.sol";
import {CheckNonBorrowableAsset} from "silo-core/deploy/silo/verifier/checks/silo/CheckNonBorrowableAsset.sol";
import {SiloCoreContracts} from "silo-core/common/SiloCoreContracts.sol";

/*
    FOUNDRY_PROFILE=core_test forge test -vvv --match-contract SiloVerifierScriptTest --ffi \
    --mt test_CheckDaoFee
*/
contract SiloVerifierScriptTest is Test {
    ISiloConfig constant WS_USDC_CONFIG = ISiloConfig(0x062A36Bbe0306c2Fd7aecdf25843291fBAB96AD2);
    address constant USDC = 0x29219dd400f2Bf60E5a23d13Be72B486D4038894;
    address constant EXAMPLE_HOOK_RECEIVER = 0x2D3d269334485d2D876df7363e1A50b13220a7D8;

    uint256 constant EXTERNAL_PRICE_0 = 0.07561e6; // price of wS @ 51321936 block
    uint256 constant EXTERNAL_PRICE_1 = 1e6;

    address public constant SILO_FACTORY = 0xa42001D6d2237d2c74108FE360403C4b796B7170;
    address public constant DKINK_IRM_FACTORY = 0xfdC13d2Aa0b8eA820b26003139f31AeFCA65Ab47;

    function setUp() public {
        vm.createSelectFork(string(abi.encodePacked(vm.envString("RPC_SONIC"))), 58293738);
        AddrLib.init();

        AddrLib.setAddress(SiloCoreContracts.SILO_FACTORY, SILO_FACTORY);
        AddrLib.setAddress(SiloCoreContracts.DYNAMIC_KINK_MODEL_FACTORY, DKINK_IRM_FACTORY);
    }

    function test_CheckDaoFee() public {
        SiloVerifier verifier = new SiloVerifier(WS_USDC_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 0, "no errors before mock");

        (address silo0, address silo1) = WS_USDC_CONFIG.getSilos();
        ISiloConfig.ConfigData memory configData0 = WS_USDC_CONFIG.getConfig(silo0);
        ISiloConfig.ConfigData memory configData1 = WS_USDC_CONFIG.getConfig(silo1);

        configData0.daoFee = 1;
        configData1.daoFee = 10 ** 18;

        vm.mockCall(
            address(WS_USDC_CONFIG),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo0),
            abi.encode(configData0)
        );

        vm.mockCall(
            address(WS_USDC_CONFIG),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo1),
            abi.encode(configData1)
        );

        verifier = new SiloVerifier(WS_USDC_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 2, "2 errors after breaking dao fee in both Silos");
    }

    function test_CheckDeployerFee() public {
        SiloVerifier verifier = new SiloVerifier(WS_USDC_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 0, "no errors before mock");

        (address silo0, address silo1) = WS_USDC_CONFIG.getSilos();
        ISiloConfig.ConfigData memory configData0 = WS_USDC_CONFIG.getConfig(silo0);
        ISiloConfig.ConfigData memory configData1 = WS_USDC_CONFIG.getConfig(silo1);

        configData0.deployerFee = 12;
        configData1.deployerFee = 22;

        vm.mockCall(
            address(WS_USDC_CONFIG),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo0),
            abi.encode(configData0)
        );

        vm.mockCall(
            address(WS_USDC_CONFIG),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo1),
            abi.encode(configData1)
        );

        verifier = new SiloVerifier(WS_USDC_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 2, "2 errors after breaking deployer fee in both Silos");
    }

    function test_CheckLiquidationFee() public {
        SiloVerifier verifier = new SiloVerifier(WS_USDC_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 0, "no errors before mock");

        (address silo0, address silo1) = WS_USDC_CONFIG.getSilos();
        ISiloConfig.ConfigData memory configData0 = WS_USDC_CONFIG.getConfig(silo0);
        ISiloConfig.ConfigData memory configData1 = WS_USDC_CONFIG.getConfig(silo1);

        configData0.liquidationFee = 10 ** 18;
        configData1.liquidationFee = 10 ** 18 / 2;

        vm.mockCall(
            address(WS_USDC_CONFIG),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo0),
            abi.encode(configData0)
        );

        vm.mockCall(
            address(WS_USDC_CONFIG),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo1),
            abi.encode(configData1)
        );

        verifier = new SiloVerifier(WS_USDC_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 2, "2 errors after breaking liquidation fee in both Silos");
    }

    function test_CheckFlashloanFee() public {
        SiloVerifier verifier = new SiloVerifier(WS_USDC_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 0, "no errors before mock");

        (address silo0, address silo1) = WS_USDC_CONFIG.getSilos();
        ISiloConfig.ConfigData memory configData0 = WS_USDC_CONFIG.getConfig(silo0);
        ISiloConfig.ConfigData memory configData1 = WS_USDC_CONFIG.getConfig(silo1);

        configData0.flashloanFee = 10 ** 18;
        configData1.flashloanFee = 10 ** 18 / 2;

        vm.mockCall(
            address(WS_USDC_CONFIG),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo0),
            abi.encode(configData0)
        );

        vm.mockCall(
            address(WS_USDC_CONFIG),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo1),
            abi.encode(configData1)
        );

        verifier = new SiloVerifier(WS_USDC_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 2, "2 errors after breaking flashloan fee in both Silos");
    }

    function test_CheckSiloImplementation() public {
        SiloVerifier verifier = new SiloVerifier(WS_USDC_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 0, "no errors before mock");

        (address silo0, address silo1) = WS_USDC_CONFIG.getSilos();
        ISiloConfig.ConfigData memory configData0 = WS_USDC_CONFIG.getConfig(silo0);
        ISiloConfig.ConfigData memory configData1 = WS_USDC_CONFIG.getConfig(silo1);

        configData0.silo = USDC;
        configData1.silo = USDC;

        vm.mockCall(
            address(WS_USDC_CONFIG),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo0),
            abi.encode(configData0)
        );

        vm.mockCall(
            address(WS_USDC_CONFIG),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo1),
            abi.encode(configData1)
        );

        vm.mockCall(address(USDC), abi.encodeWithSelector(ISilo.factory.selector), abi.encode(SILO_FACTORY));

        vm.mockCall(
            address(SILO_FACTORY), abi.encodeWithSelector(ISiloFactory.isSilo.selector, USDC), abi.encode(true)
        );

        verifier = new SiloVerifier(WS_USDC_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 2, "2 errors after breaking Silo implementation in both Silos");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_CheckMaxLtvLtLiquidationFee -vv
    */
    function test_CheckMaxLtvLtLiquidationFee() public {
        SiloVerifier verifier = new SiloVerifier(WS_USDC_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 0, "no errors before mock");

        (address silo0, address silo1) = WS_USDC_CONFIG.getSilos();
        ISiloConfig.ConfigData memory configData0 = WS_USDC_CONFIG.getConfig(silo0);
        ISiloConfig.ConfigData memory configData1 = WS_USDC_CONFIG.getConfig(silo1);

        configData0.maxLtv = 0;
        configData0.lt = 0;
        configData0.liquidationFee = 0;

        configData1.maxLtv = 0;
        configData1.lt = 0;
        configData1.liquidationFee = 0;

        vm.mockCall(
            address(WS_USDC_CONFIG),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo0),
            abi.encode(configData0)
        );

        vm.mockCall(
            address(WS_USDC_CONFIG),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo1),
            abi.encode(configData1)
        );

        verifier = new SiloVerifier(WS_USDC_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 0, "0 errors when maxLTV, LT and liquidation fee are zeros");

        configData0.maxLtv = 0;
        configData0.lt = 10 ** 18 / 2;
        configData0.liquidationFee = 10 ** 18 / 100;

        configData1.maxLtv = 10 ** 18 * 75 / 100;
        configData1.lt = 0;
        configData1.liquidationFee = 10 ** 18 / 100;

        vm.mockCall(
            address(WS_USDC_CONFIG),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo0),
            abi.encode(configData0)
        );

        vm.mockCall(
            address(WS_USDC_CONFIG),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo1),
            abi.encode(configData1)
        );

        verifier = new SiloVerifier(WS_USDC_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 2, "2 errors when one of the maxLTV, LT and liquidation fee is zero");
    }

    function test_CheckHookOwner() public {
        SiloVerifier verifier = new SiloVerifier(WS_USDC_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 0, "no errors before mock");

        (address silo0, address silo1) = WS_USDC_CONFIG.getSilos();
        ISiloConfig.ConfigData memory configData0 = WS_USDC_CONFIG.getConfig(silo0);
        ISiloConfig.ConfigData memory configData1 = WS_USDC_CONFIG.getConfig(silo1);

        vm.mockCall(
            address(configData0.hookReceiver), abi.encodeWithSelector(Ownable.owner.selector), abi.encode(address(1))
        );

        vm.mockCall(
            address(configData1.hookReceiver), abi.encodeWithSelector(Ownable.owner.selector), abi.encode(address(2))
        );

        verifier = new SiloVerifier(WS_USDC_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 2, "2 errors after breaking hook receiver owner in both Silos");
    }

    function test_CheckIncentivesOwner() public {
        SiloVerifier verifier = new SiloVerifier(WS_USDC_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 0, "no errors before mock");

        (, address silo1) = WS_USDC_CONFIG.getSilos();
        ISiloConfig.ConfigData memory configData1 = WS_USDC_CONFIG.getConfig(silo1);

        ISiloIncentivesController incentives1 = IGaugeHookReceiver(configData1.hookReceiver).configuredGauges(
            IShareToken(configData1.collateralShareToken)
        );

        vm.mockCall(address(incentives1), abi.encodeWithSelector(Ownable.owner.selector), abi.encode(address(2)));

        verifier = new SiloVerifier(WS_USDC_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 1, "1 error after breaking incentives owner in Silo1 with incentives");
    }

    function test_CheckShareTokensInGauge() public {
        SiloVerifier verifier = new SiloVerifier(WS_USDC_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 0, "no errors before mock");

        (, address silo1) = WS_USDC_CONFIG.getSilos();
        ISiloConfig.ConfigData memory configData1 = WS_USDC_CONFIG.getConfig(silo1);

        ISiloIncentivesController incentives1 = IGaugeHookReceiver(configData1.hookReceiver).configuredGauges(
            IShareToken(configData1.collateralShareToken)
        );

        vm.mockCall(
            address(incentives1),
            abi.encodeWithSelector(ISiloIncentivesController.SHARE_TOKEN.selector),
            abi.encode(address(2))
        );

        verifier = new SiloVerifier(WS_USDC_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 1, "1 error after breaking share_token in Silo1 gauge with incentives");
    }

    function test_CheckIrmConfig() public {
        SiloVerifier verifier = new SiloVerifier(WS_USDC_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 0, "no errors before mock");

        (address silo0, address silo1) = WS_USDC_CONFIG.getSilos();
        ISiloConfig.ConfigData memory configData0 = WS_USDC_CONFIG.getConfig(silo0);
        ISiloConfig.ConfigData memory configData1 = WS_USDC_CONFIG.getConfig(silo1);

        IInterestRateModelV2Config irmV2Config0 = InterestRateModelV2(configData0.interestRateModel).irmConfig();

        IInterestRateModelV2.Config memory irmConfig0 = irmV2Config0.getConfig();

        IInterestRateModelV2Config irmV2Config1 = InterestRateModelV2(configData1.interestRateModel).irmConfig();

        IInterestRateModelV2.Config memory irmConfig1 = irmV2Config1.getConfig();

        irmConfig0.uopt = 11;
        irmConfig1.ucrit = 22;

        vm.mockCall(
            address(irmV2Config0),
            abi.encodeWithSelector(IInterestRateModelV2Config.getConfig.selector),
            abi.encode(irmConfig0)
        );

        vm.mockCall(
            address(irmV2Config1),
            abi.encodeWithSelector(IInterestRateModelV2Config.getConfig.selector),
            abi.encode(irmConfig1)
        );

        verifier = new SiloVerifier(WS_USDC_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 2, "2 errors after breaking IRM config in both Silos");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_CheckPriceDoesNotReturnZero -vv 
    */
    function test_CheckPriceDoesNotReturnZero() public {
        SiloVerifier verifier = new SiloVerifier(WS_USDC_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 0, "no errors before mock");

        (address silo0,) = WS_USDC_CONFIG.getSilos();
        ISiloConfig.ConfigData memory configData0 = WS_USDC_CONFIG.getConfig(silo0);

        vm.mockCall(
            address(configData0.solvencyOracle),
            abi.encodeWithSelector(ISiloOracle.quote.selector),
            abi.encode(uint256(0))
        );

        verifier = new SiloVerifier(WS_USDC_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);

        assertEq(
            verifier.verify(),
            2,
            "2 errors after breaking oracle to return zeros. 1 for price does not return zero, 1 for external prices"
        );
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_CheckExternalPrices -vv
    */
    function test_CheckExternalPrices() public {
        SiloVerifier verifier = new SiloVerifier(WS_USDC_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 0, "no errors for original prices");

        verifier = new SiloVerifier(ISiloConfig(0xefA367570B11f8745B403c0D458b9D2EAf424686), false, 1010, 1000);
        assertEq(verifier.verify(), 0, "no errors for single oracle case");

        verifier = new SiloVerifier(WS_USDC_CONFIG, false, EXTERNAL_PRICE_0 * 102 / 100, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 1, "1 error for 2% price deviation");

        verifier = new SiloVerifier(WS_USDC_CONFIG, false, 0, 0);
        assertEq(verifier.verify(), 1, "1 error when no prices provided");
    }

    function test_CheckQuoteIsLinearFunction() public {
        SiloVerifier verifier = new SiloVerifier(WS_USDC_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 0, "no errors before mock");

        (address silo0, address silo1) = WS_USDC_CONFIG.getSilos();
        ISiloConfig.ConfigData memory configData0 = WS_USDC_CONFIG.getConfig(silo0);
        ISiloConfig.ConfigData memory configData1 = WS_USDC_CONFIG.getConfig(silo1);

        vm.mockCall(
            address(configData0.solvencyOracle),
            abi.encodeWithSelector(ISiloOracle.quote.selector),
            abi.encode(EXTERNAL_PRICE_0)
        );

        vm.mockCall(
            address(configData1.solvencyOracle),
            abi.encodeWithSelector(ISiloOracle.quote.selector),
            abi.encode(EXTERNAL_PRICE_1)
        );

        verifier = new SiloVerifier(WS_USDC_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 2, "2 errors after breaking linear property in oracles for both Silos");
    }

    function test_CheckQuoteLargeAmounts() public {
        SiloVerifier verifier = new SiloVerifier(WS_USDC_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 0, "no errors before mock");

        (address silo0, address silo1) = WS_USDC_CONFIG.getSilos();
        ISiloConfig.ConfigData memory configData0 = WS_USDC_CONFIG.getConfig(silo0);
        ISiloConfig.ConfigData memory configData1 = WS_USDC_CONFIG.getConfig(silo1);

        configData0.solvencyOracle = USDC;
        configData1.solvencyOracle = USDC;

        vm.mockCall(
            address(WS_USDC_CONFIG),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo0),
            abi.encode(configData0)
        );

        vm.mockCall(
            address(WS_USDC_CONFIG),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo1),
            abi.encode(configData1)
        );

        verifier = new SiloVerifier(WS_USDC_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);

        assertEq(
            verifier.verify(),
            3,
            "3 errors after making oracles revert for large amounts. 2 for quote large amounts, 1 for external price check"
        );
    }

    function test_CheckNonBorrowableAsset_nonBorrowableSiloConfigs() public {
        vm.createSelectFork(string(abi.encodePacked(vm.envString("RPC_MAINNET"))), 22875029);

        ISiloConfig lptConfig = ISiloConfig(0xAA5ED72b3Ca4aE7dA178e7BEff838F31e5c63342);
        ISiloConfig ptConfig = ISiloConfig(0x8332F03C0EcFB5b6BcF50484A2e9C048b79aC352);
        ISiloConfig erc4626Config = ISiloConfig(0x88A79276734EeEA55831d03730e71023d6891b09);

        ISiloConfig[] memory nonBorrowableSiloConfigs = new ISiloConfig[](3);
        nonBorrowableSiloConfigs[0] = lptConfig;
        nonBorrowableSiloConfigs[1] = ptConfig;
        nonBorrowableSiloConfigs[2] = erc4626Config;

        for (uint256 i; i < nonBorrowableSiloConfigs.length; i++) {
            ISiloConfig nonBorrowableSiloConfig = nonBorrowableSiloConfigs[i];
            (address silo0, address silo1) = nonBorrowableSiloConfig.getSilos();
            ISiloConfig.ConfigData memory configData1 = nonBorrowableSiloConfig.getConfig(silo1);
            address token0 = nonBorrowableSiloConfig.getConfig(silo0).token;

            CheckNonBorrowableAsset check = new CheckNonBorrowableAsset(token0, configData1);
            assertEq(configData1.maxLtv, 0, "max ltv is 0");
            assertEq(configData1.lt, 0, "lt is 0");
            assertTrue(check.execute(), "check passes for existing PT/LPT/ERC4626 silos");

            configData1.maxLtv = 1;
            check = new CheckNonBorrowableAsset(token0, configData1);
            assertFalse(check.execute(), "check must fail if max ltv is not zero for other asset");

            configData1.maxLtv = 0;
            configData1.lt = 1;
            check = new CheckNonBorrowableAsset(token0, configData1);
            assertFalse(check.execute(), "check must fail if lt is not zero for other asset");
        }
    }

    function test_CheckNonBorrowableAsset_regularSiloConfig() public {
        vm.createSelectFork(string(abi.encodePacked(vm.envString("RPC_MAINNET"))), 22875029);

        ISiloConfig regularConfig = ISiloConfig(0x8689611D9A74BCc9837261872262009F89965ECc);
        (address silo0, address silo1) = regularConfig.getSilos();
        ISiloConfig.ConfigData memory configData1 = regularConfig.getConfig(silo1);
        address token0 = regularConfig.getConfig(silo0).token;

        CheckNonBorrowableAsset check = new CheckNonBorrowableAsset(token0, configData1);
        assertTrue(configData1.maxLtv != 0, "max ltv!=0");
        assertTrue(configData1.lt != 0, "max ltv!=0");
        assertTrue(check.execute(), "check passes for regular config, maxLTV!=0 and LT!=0");

        configData1.maxLtv = 0;
        configData1.lt = 0;
        check = new CheckNonBorrowableAsset(token0, configData1);
        assertTrue(check.execute(), "check passes for regular config, maxLTV=0 and LT=0");
    }
}

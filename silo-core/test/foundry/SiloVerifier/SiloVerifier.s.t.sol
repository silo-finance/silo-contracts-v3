// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";

import {SiloVerifier} from "silo-core/deploy/silo/verifier/SiloVerifier.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IGaugeHookReceiver} from "silo-core/contracts/hooks/gauge/GaugeHookReceiver.sol";
import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";
import {Ownable} from "openzeppelin5/access/Ownable2Step.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloFactory} from "silo-core/contracts/interfaces/ISiloFactory.sol";
import {CheckNonBorrowableAsset} from "silo-core/deploy/silo/verifier/checks/silo/CheckNonBorrowableAsset.sol";
import {SiloCoreContracts} from "silo-core/common/SiloCoreContracts.sol";
import {IDynamicKinkModel} from "silo-core/contracts/interfaces/IDynamicKinkModel.sol";
import {IDynamicKinkModelConfig} from "silo-core/contracts/interfaces/IDynamicKinkModelConfig.sol";

/*
    FOUNDRY_PROFILE=core_test forge test --match-contract SiloVerifierScriptTest --ffi -vvv  \
    --mt test_CheckIrmConfig

*/
contract SiloVerifierScriptTest is Test {
    ISiloConfig constant GM_WETH_CONFIG = ISiloConfig(0xB4b4d23F4D7FFd04deABfCdCf8fDdeD0Ed3ae1C8);
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant EXAMPLE_HOOK_RECEIVER = 0xAf45c4F4B0239a20157eda4069c283cb8c7D6aF2;

    uint256 constant EXTERNAL_PRICE_0 = 0.68e18; // price of GM
    uint256 constant EXTERNAL_PRICE_1 = 1987e18;

    address public constant SILO_FACTORY = 0xAFd8F792cb025A76C4916652CfC8e20eee3b6fe2;
    address public constant DKINK_IRM_FACTORY = 0xCA1658fe7c04E7CF739c3072A1f60948506Efd83;

    function setUp() public {
        vm.createSelectFork(string(abi.encodePacked(vm.envString("RPC_ARBITRUM"))), 437839306);
        AddrLib.init();

        AddrLib.setAddress(SiloCoreContracts.SILO_FACTORY, SILO_FACTORY);
        AddrLib.setAddress(SiloCoreContracts.DYNAMIC_KINK_MODEL_FACTORY, DKINK_IRM_FACTORY);
    }

    function test_CheckDaoFee() public {
        SiloVerifier verifier = new SiloVerifier(GM_WETH_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 0, "no errors before mock");

        (address silo0, address silo1) = GM_WETH_CONFIG.getSilos();
        ISiloConfig.ConfigData memory configData0 = GM_WETH_CONFIG.getConfig(silo0);
        ISiloConfig.ConfigData memory configData1 = GM_WETH_CONFIG.getConfig(silo1);

        configData0.daoFee = 1;
        configData1.daoFee = 10 ** 18;

        vm.mockCall(
            address(GM_WETH_CONFIG),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo0),
            abi.encode(configData0)
        );

        vm.mockCall(
            address(GM_WETH_CONFIG),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo1),
            abi.encode(configData1)
        );

        verifier = new SiloVerifier(GM_WETH_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 2, "2 errors after breaking dao fee in both Silos");
    }

    function test_CheckDeployerFee() public {
        SiloVerifier verifier = new SiloVerifier(GM_WETH_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 0, "no errors before mock");

        (address silo0, address silo1) = GM_WETH_CONFIG.getSilos();
        ISiloConfig.ConfigData memory configData0 = GM_WETH_CONFIG.getConfig(silo0);
        ISiloConfig.ConfigData memory configData1 = GM_WETH_CONFIG.getConfig(silo1);

        configData0.deployerFee = 12;
        configData1.deployerFee = 22;

        vm.mockCall(
            address(GM_WETH_CONFIG),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo0),
            abi.encode(configData0)
        );

        vm.mockCall(
            address(GM_WETH_CONFIG),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo1),
            abi.encode(configData1)
        );

        verifier = new SiloVerifier(GM_WETH_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 2, "2 errors after breaking deployer fee in both Silos");
    }

    function test_CheckLiquidationFee() public {
        SiloVerifier verifier = new SiloVerifier(GM_WETH_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 0, "no errors before mock");

        (address silo0, address silo1) = GM_WETH_CONFIG.getSilos();
        ISiloConfig.ConfigData memory configData0 = GM_WETH_CONFIG.getConfig(silo0);
        ISiloConfig.ConfigData memory configData1 = GM_WETH_CONFIG.getConfig(silo1);

        configData0.liquidationFee = 10 ** 18;
        configData1.liquidationFee = 10 ** 18 / 2;

        vm.mockCall(
            address(GM_WETH_CONFIG),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo0),
            abi.encode(configData0)
        );

        vm.mockCall(
            address(GM_WETH_CONFIG),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo1),
            abi.encode(configData1)
        );

        verifier = new SiloVerifier(GM_WETH_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 3, "3 errors after breaking liquidation fee in both Silos");
    }

    function test_CheckFlashloanFee() public {
        SiloVerifier verifier = new SiloVerifier(GM_WETH_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 0, "no errors before mock");

        (address silo0, address silo1) = GM_WETH_CONFIG.getSilos();
        ISiloConfig.ConfigData memory configData0 = GM_WETH_CONFIG.getConfig(silo0);
        ISiloConfig.ConfigData memory configData1 = GM_WETH_CONFIG.getConfig(silo1);

        configData0.flashloanFee = 10 ** 18;
        configData1.flashloanFee = 10 ** 18 / 2;

        vm.mockCall(
            address(GM_WETH_CONFIG),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo0),
            abi.encode(configData0)
        );

        vm.mockCall(
            address(GM_WETH_CONFIG),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo1),
            abi.encode(configData1)
        );

        verifier = new SiloVerifier(GM_WETH_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 2, "2 errors after breaking flashloan fee in both Silos");
    }

    function test_CheckSiloImplementation() public {
        SiloVerifier verifier = new SiloVerifier(GM_WETH_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 0, "no errors before mock");

        (address silo0, address silo1) = GM_WETH_CONFIG.getSilos();
        ISiloConfig.ConfigData memory configData0 = GM_WETH_CONFIG.getConfig(silo0);
        ISiloConfig.ConfigData memory configData1 = GM_WETH_CONFIG.getConfig(silo1);

        configData0.silo = WETH;
        configData1.silo = WETH;

        vm.mockCall(
            address(GM_WETH_CONFIG),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo0),
            abi.encode(configData0)
        );

        vm.mockCall(
            address(GM_WETH_CONFIG),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo1),
            abi.encode(configData1)
        );

        vm.mockCall(address(WETH), abi.encodeWithSelector(ISilo.factory.selector), abi.encode(SILO_FACTORY));

        vm.mockCall(
            address(SILO_FACTORY), abi.encodeWithSelector(ISiloFactory.isSilo.selector, WETH), abi.encode(true)
        );

        verifier = new SiloVerifier(GM_WETH_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 2, "2 errors after breaking Silo implementation in both Silos");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_CheckMaxLtvLtLiquidationFee -vv
    */
    function test_CheckMaxLtvLtLiquidationFee() public {
        SiloVerifier verifier = new SiloVerifier(GM_WETH_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 0, "no errors before mock");

        (address silo0, address silo1) = GM_WETH_CONFIG.getSilos();
        ISiloConfig.ConfigData memory configData0 = GM_WETH_CONFIG.getConfig(silo0);
        ISiloConfig.ConfigData memory configData1 = GM_WETH_CONFIG.getConfig(silo1);

        configData0.maxLtv = 0;
        configData0.lt = 0;
        configData0.liquidationFee = 0;

        configData1.maxLtv = 0;
        configData1.lt = 0;
        configData1.liquidationFee = 0;

        vm.mockCall(
            address(GM_WETH_CONFIG),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo0),
            abi.encode(configData0)
        );

        vm.mockCall(
            address(GM_WETH_CONFIG),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo1),
            abi.encode(configData1)
        );

        verifier = new SiloVerifier(GM_WETH_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 1, "1 error (for defaulting) when maxLTV, LT and liquidation fee are zeros");

        configData0.maxLtv = 0;
        configData0.lt = 10 ** 18 / 2;
        configData0.liquidationFee = 10 ** 18 / 100;

        configData1.maxLtv = 10 ** 18 * 75 / 100;
        configData1.lt = 0;
        configData1.liquidationFee = 10 ** 18 / 100;

        vm.mockCall(
            address(GM_WETH_CONFIG),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo0),
            abi.encode(configData0)
        );

        vm.mockCall(
            address(GM_WETH_CONFIG),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo1),
            abi.encode(configData1)
        );

        verifier = new SiloVerifier(GM_WETH_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 2, "2 errors when one of the maxLTV, LT and liquidation fee is zero");
    }

    function test_CheckHookOwner() public {
        SiloVerifier verifier = new SiloVerifier(GM_WETH_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 0, "no errors before mock");

        (address silo0, address silo1) = GM_WETH_CONFIG.getSilos();
        ISiloConfig.ConfigData memory configData0 = GM_WETH_CONFIG.getConfig(silo0);
        ISiloConfig.ConfigData memory configData1 = GM_WETH_CONFIG.getConfig(silo1);

        vm.mockCall(
            address(configData0.hookReceiver), abi.encodeWithSelector(Ownable.owner.selector), abi.encode(address(1))
        );

        vm.mockCall(
            address(configData1.hookReceiver), abi.encodeWithSelector(Ownable.owner.selector), abi.encode(address(2))
        );

        verifier = new SiloVerifier(GM_WETH_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 2, "2 errors after breaking hook receiver owner in both Silos");
    }

    function test_CheckIncentivesOwner() public {
        SiloVerifier verifier = new SiloVerifier(GM_WETH_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 0, "no errors before mock");

        (, address silo1) = GM_WETH_CONFIG.getSilos();
        ISiloConfig.ConfigData memory configData1 = GM_WETH_CONFIG.getConfig(silo1);

        ISiloIncentivesController incentives1 = IGaugeHookReceiver(configData1.hookReceiver).configuredGauges(
            IShareToken(configData1.collateralShareToken)
        );

        vm.mockCall(address(incentives1), abi.encodeWithSelector(Ownable.owner.selector), abi.encode(address(2)));

        verifier = new SiloVerifier(GM_WETH_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 1, "1 error after breaking incentives owner in Silo1 with incentives");
    }

    function test_CheckShareTokensInGauge() public {
        SiloVerifier verifier = new SiloVerifier(GM_WETH_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 0, "no errors before mock");

        (, address silo1) = GM_WETH_CONFIG.getSilos();
        ISiloConfig.ConfigData memory configData1 = GM_WETH_CONFIG.getConfig(silo1);

        ISiloIncentivesController incentives1 = IGaugeHookReceiver(configData1.hookReceiver).configuredGauges(
            IShareToken(configData1.collateralShareToken)
        );

        vm.mockCall(
            address(incentives1),
            abi.encodeWithSelector(ISiloIncentivesController.SHARE_TOKEN.selector),
            abi.encode(address(2))
        );

        verifier = new SiloVerifier(GM_WETH_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 1, "1 error after breaking share_token in Silo1 gauge with incentives");
    }

    function test_CheckIrmConfig() public {
        SiloVerifier verifier = new SiloVerifier(GM_WETH_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 0, "no errors before mock");

        (address silo0, address silo1) = GM_WETH_CONFIG.getSilos();
        ISiloConfig.ConfigData memory configData0 = GM_WETH_CONFIG.getConfig(silo0);
        ISiloConfig.ConfigData memory configData1 = GM_WETH_CONFIG.getConfig(silo1);

        IDynamicKinkModel irm0 = IDynamicKinkModel(configData0.interestRateModel);
        IDynamicKinkModel irm1 = IDynamicKinkModel(configData1.interestRateModel);

        IDynamicKinkModelConfig irmConfigContract0 = irm0.irmConfig();
        IDynamicKinkModelConfig irmConfigContract1 = irm1.irmConfig();

        (
            IDynamicKinkModel.Config memory irmConfig0,
            IDynamicKinkModel.ImmutableConfig memory immutableConfig0
        ) = irmConfigContract0.getConfig();

        (
            IDynamicKinkModel.Config memory irmConfig1,
            IDynamicKinkModel.ImmutableConfig memory immutableConfig1
        ) = irmConfigContract1.getConfig();

        // mutate both standard config and immutable config so that Kink model config
        // no longer matches any known JSON config used by Utils.findKinkIrmName
        irmConfig0.ulow = irmConfig0.ulow + 1;
        immutableConfig1.timelock = immutableConfig1.timelock + 1;

        vm.mockCall(
            address(irmConfigContract0),
            abi.encodeWithSelector(IDynamicKinkModelConfig.getConfig.selector),
            abi.encode(irmConfig0, immutableConfig0)
        );

        vm.mockCall(
            address(irmConfigContract1),
            abi.encodeWithSelector(IDynamicKinkModelConfig.getConfig.selector),
            abi.encode(irmConfig1, immutableConfig1)
        );

        verifier = new SiloVerifier(GM_WETH_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 2, "2 errors after breaking Dynamic Kink IRM config in both Silos");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_CheckPriceDoesNotReturnZero -vv 
    */
    function test_CheckPriceDoesNotReturnZero() public {
        SiloVerifier verifier = new SiloVerifier(GM_WETH_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 0, "no errors before mock");

        (address silo0,) = GM_WETH_CONFIG.getSilos();
        ISiloConfig.ConfigData memory configData0 = GM_WETH_CONFIG.getConfig(silo0);

        vm.mockCall(
            address(configData0.solvencyOracle),
            abi.encodeWithSelector(ISiloOracle.quote.selector),
            abi.encode(uint256(0))
        );

        verifier = new SiloVerifier(GM_WETH_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);

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
        SiloVerifier verifier = new SiloVerifier(GM_WETH_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 0, "no errors for original prices");

        verifier = new SiloVerifier(GM_WETH_CONFIG, false, EXTERNAL_PRICE_0 * 102 / 100, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 1, "1 error for 2% price deviation");

        verifier = new SiloVerifier(GM_WETH_CONFIG, false, 0, 0);
        assertEq(verifier.verify(), 1, "1 error when no prices provided");
    }

    function test_CheckQuoteIsLinearFunction() public {
        SiloVerifier verifier = new SiloVerifier(GM_WETH_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 0, "no errors before mock");

        (address silo0, address silo1) = GM_WETH_CONFIG.getSilos();
        ISiloConfig.ConfigData memory configData0 = GM_WETH_CONFIG.getConfig(silo0);
        ISiloConfig.ConfigData memory configData1 = GM_WETH_CONFIG.getConfig(silo1);

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

        verifier = new SiloVerifier(GM_WETH_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 2, "2 errors after breaking linear property in oracles for both Silos");
    }

    function test_CheckQuoteLargeAmounts() public {
        SiloVerifier verifier = new SiloVerifier(GM_WETH_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);
        assertEq(verifier.verify(), 0, "no errors before mock");

        (address silo0, address silo1) = GM_WETH_CONFIG.getSilos();
        ISiloConfig.ConfigData memory configData0 = GM_WETH_CONFIG.getConfig(silo0);
        ISiloConfig.ConfigData memory configData1 = GM_WETH_CONFIG.getConfig(silo1);

        configData0.solvencyOracle = WETH;
        configData1.solvencyOracle = WETH;

        vm.mockCall(
            address(GM_WETH_CONFIG),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo0),
            abi.encode(configData0)
        );

        vm.mockCall(
            address(GM_WETH_CONFIG),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo1),
            abi.encode(configData1)
        );

        verifier = new SiloVerifier(GM_WETH_CONFIG, false, EXTERNAL_PRICE_0, EXTERNAL_PRICE_1);

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

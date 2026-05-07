// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";
import {SiloIncentivesControllerDeployments} from "./SiloIncentivesControllerDeployments.sol";

import {Ownable} from "openzeppelin5/access/Ownable.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";
import {console2} from "forge-std/console2.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

import {CommonDeploy} from "../_CommonDeploy.sol";
import {SiloCoreContracts, SiloCoreDeployments} from "silo-core/common/SiloCoreContracts.sol";
import {IGaugeHookReceiver} from "silo-core/contracts/interfaces/IGaugeHookReceiver.sol";
import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {
    IPermissionedLiquidationControllerFactory
} from "silo-core/contracts/interfaces/IPermissionedLiquidationControllerFactory.sol";

/*
    SILO=0xe394050D179b72197A458Fdfb962Ae69908Aa5A0 \
    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/incentives-controller/PermissionedLiquidationControllerDeploy.s.sol \
        --ffi --rpc-url $RPC_MAINNET --broadcast --verify
 */
contract PermissionedLiquidationControllerDeploy is CommonDeploy, StdCheats {
    error FactoryNotFound();

    function run() public {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        ISilo silo = ISilo(vm.envAddress("SILO"));

        address notifier = IShareToken(address(silo)).hookReceiver();
        address owner = Ownable(notifier).owner();

        address factory = SiloCoreDeployments.get(
            SiloCoreContracts.PERMISSIONED_LIQUIDATION_CONTROLLER_FACTORY, ChainsLib.chainAlias()
        );

        require(factory != address(0), string.concat(SiloCoreContracts.PERMISSIONED_LIQUIDATION_CONTROLLER_FACTORY, " not found"));

        ISiloConfig cfg = silo.config();

        console2.log("SILO ID:", cfg.SILO_ID());

        ISiloConfig.ConfigData memory config = cfg.getConfig(address(silo));
        address collateralShareTokenAddress = config.collateralShareToken;
        address protectedShareTokenAddress = config.protectedShareToken;
        address debtShareTokenAddress = config.debtShareToken;

        ISiloIncentivesController debtGauge = IGaugeHookReceiver(notifier).configuredGauges(IShareToken(debtShareTokenAddress));
        bool deployForDebt = address(debtGauge) == address(0);

        vm.startBroadcast(deployerPrivateKey);

        address incentivesControllerC =
            IPermissionedLiquidationControllerFactory(factory).create(IShareToken(collateralShareTokenAddress));
        
        address incentivesControllerP =
            IPermissionedLiquidationControllerFactory(factory).create(IShareToken(protectedShareTokenAddress));

        address incentivesControllerD;
        if (deployForDebt) {
            incentivesControllerD =
                IPermissionedLiquidationControllerFactory(factory).create(IShareToken(debtShareTokenAddress));
        }

        vm.stopBroadcast();

        // hook receiver ownership acceptance data
        console2.log(
            "\nHook(%s).setGauge(ic: %s, shareToken: %s)",
            notifier,
            incentivesControllerC,
            collateralShareTokenAddress
        );
        
        console2.log(
            "\nHook(%s).setGauge(ic: %s, shareToken: %s)", notifier, incentivesControllerP, protectedShareTokenAddress
        );

        if (deployForDebt) {
            console2.log(
                "\nHook(%s).setGauge(ic: %s, shareToken: %s)", notifier, incentivesControllerD, debtShareTokenAddress
            );
        }

        console2.log("QA ---");

        vm.startPrank(owner);
        IGaugeHookReceiver(notifier)
            .setGauge(
                ISiloIncentivesController(address(incentivesControllerC)), IShareToken(collateralShareTokenAddress)
            );

        IGaugeHookReceiver(notifier)
            .setGauge(
                ISiloIncentivesController(address(incentivesControllerP)), IShareToken(protectedShareTokenAddress)
            );

        if (deployForDebt) {
            IGaugeHookReceiver(notifier).setGauge(
                ISiloIncentivesController(address(incentivesControllerD)), IShareToken(debtShareTokenAddress)
            );
        }

        IGaugeHookReceiver(notifier).removeGauge(IShareToken(collateralShareTokenAddress));
        IGaugeHookReceiver(notifier).removeGauge(IShareToken(protectedShareTokenAddress));

        if (deployForDebt) {
            IGaugeHookReceiver(notifier).removeGauge(IShareToken(debtShareTokenAddress));
        }

        vm.stopPrank();

        // Cheat-only smoke test (fake user + `deal`); does not use PRIVATE_KEY and is not broadcast.
        _qaSiloSmoke(cfg);

        SiloIncentivesControllerDeployments.save({
            _chain: ChainsLib.chainAlias(), _shareToken: collateralShareTokenAddress, _deployed: incentivesControllerC
        });

        SiloIncentivesControllerDeployments.save({
            _chain: ChainsLib.chainAlias(), _shareToken: protectedShareTokenAddress, _deployed: incentivesControllerP
        });
    }

    function _qaSiloSmoke(ISiloConfig siloConfig) private {
        address depositor = makeAddr("depositor");
        (address silo0Addr, address silo1Addr) = siloConfig.getSilos();
        ISilo silo0 = ISilo(silo0Addr);
        ISilo silo1 = ISilo(silo1Addr);

        (uint256 unit0, uint256 unit1) = _qaDealForSilos(silo0, silo1, depositor);

        vm.startPrank(depositor);

        _qaDepositOnSilo(silo0, depositor, unit0 * 100);
        _qaDepositOnSilo(silo1, depositor, unit1 * 100);

        vm.warp(block.timestamp + 1 days);

        require(_qaBorrow(silo0, depositor) || _qaBorrow(silo1, depositor), "QA: borrow failed");
    }

    function _qaDealForSilos(ISilo silo0, ISilo silo1, address depositor) private returns (uint256 unit0, uint256 unit1) {
        address asset0 = silo0.asset();
        address asset1 = silo1.asset();
        unit0 = 10 ** uint256(IERC20Metadata(asset0).decimals());
        unit1 = 10 ** uint256(IERC20Metadata(asset1).decimals());
        deal(asset0, depositor, unit0 * 2_000);
        deal(asset1, depositor, unit1 * 2_000);
    }

    function _qaDepositOnSilo(
        ISilo _silo,
        address _depositor,
        uint256 _amount
    ) private {
        address asset = _silo.asset();
        IERC20(asset).approve(address(_silo), type(uint256).max);
        _silo.deposit(_amount, _depositor, ISilo.CollateralType.Protected);
        _silo.deposit(_amount, _depositor, ISilo.CollateralType.Collateral);
    }

    function _qaBorrow(ISilo _silo, address _depositor) internal returns (bool success) {
        uint256 maxBorrow0 = _silo.maxBorrow(_depositor);

        if (maxBorrow0 == 0) return false;

        uint256 shares = _silo.borrow(maxBorrow0, _depositor, _depositor);
        
        vm.warp(block.timestamp + 1 days);

        _silo.repayShares(shares, _depositor);
        success = true;
    }
}

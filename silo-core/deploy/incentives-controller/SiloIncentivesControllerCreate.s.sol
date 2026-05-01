// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";
import {Strings} from "openzeppelin5/utils/Strings.sol";

import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";

import {CommonDeploy} from "../_CommonDeploy.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {SiloCoreContracts, SiloCoreDeployments} from "silo-core/common/SiloCoreContracts.sol";

import {SiloIncentivesControllerFactory} from "silo-core/contracts/incentives/SiloIncentivesControllerFactory.sol";

import {SiloDeployments} from "silo-core/deploy/silo/SiloDeployments.sol";
import {SiloIncentivesControllerDeployments} from "./SiloIncentivesControllerDeployments.sol";

/*
    INCENTIVES_OWNER=DAO SILO=Silo_woS_wS_borrowable INCENTIVIZED_ASSET=wS \
    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/incentives-controller/SiloIncentivesControllerCreate.s.sol \
        --ffi --rpc-url $RPC_SONIC --broadcast --verify
    
    It is possible to define an optional parameter for share token type:
    SHARE_TOKEN_TYPE=COLLATERAL (borrowable collateral, default value)
    SHARE_TOKEN_TYPE=COLLATERAL_ONLY (protected deposits)
    SHARE_TOKEN_TYPE=DEBT (debt share token)

 */
contract SiloIncentivesControllerCreate is CommonDeploy {
    string public constant SHARE_TOKEN_TYPE_KEY = "SHARE_TOKEN_TYPE";
    string public constant SHARE_TOKEN_TYPE_COLLATERAL = "COLLATERAL";
    string public constant SHARE_TOKEN_TYPE_COLLATERAL_ONLY = "COLLATERAL_ONLY";
    string public constant SHARE_TOKEN_TYPE_DEBT = "DEBT";

    error OwnerNotFound();
    error SiloNotFound();
    error IncentivizedAssetNotFound();
    error IncentivizedAssetMismatch();

    address public incentivesOwner;
    address public incentivizedAsset;
    address public siloConfig;
    address public hookReceiver;
    string public shareTokenType;
    address public shareToken;

    function setIncentivesOwner(address _incentivesOwner) public {
        incentivesOwner = _incentivesOwner;
    }

    function setIncentivizedAsset(address _incentivizedAsset) public {
        incentivizedAsset = _incentivizedAsset;
    }

    function setSiloConfig(address _siloConfig) public {
        siloConfig = _siloConfig;
    }

    function run() public returns (address incentivesController) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        shareTokenType = vm.envOr(SHARE_TOKEN_TYPE_KEY, SHARE_TOKEN_TYPE_COLLATERAL);

        if (incentivesOwner == address(0)) {
            string memory incentivesOwnerKey = vm.envString("INCENTIVES_OWNER");
            incentivesOwner = AddrLib.getAddress(incentivesOwnerKey);
            require(incentivesOwner != address(0), OwnerNotFound());
        }

        if (incentivizedAsset == address(0)) {
            string memory incentivizedAssetKey = vm.envString("INCENTIVIZED_ASSET");
            incentivizedAsset = AddrLib.getAddress(incentivizedAssetKey);
            require(incentivizedAsset != address(0), IncentivizedAssetNotFound());
        }

        if (siloConfig == address(0)) {
            string memory siloKey = vm.envString("SILO");
            siloConfig = SiloDeployments.get(ChainsLib.chainAlias(), siloKey);
            require(siloConfig != address(0), SiloNotFound());
        }

        address factory = SiloCoreDeployments.get(
            SiloCoreContracts.PERMISSIONED_LIQUIDATION_INCENTIVE_CONTROLLER_FACTORY,
            ChainsLib.chainAlias()
        );

        (address incentivizedSilo, address silo1) = ISiloConfig(siloConfig).getSilos();

        ISiloConfig.ConfigData memory config = ISiloConfig(siloConfig).getConfig(incentivizedSilo);

        if (config.token != incentivizedAsset) {
            incentivizedSilo = silo1;
            config = ISiloConfig(siloConfig).getConfig(incentivizedSilo);

            require(config.token == incentivizedAsset, IncentivizedAssetMismatch());
        }

        (
            address protectedShareToken,
            address collateralShareToken,
            address debtShareToken
        ) = ISiloConfig(siloConfig).getShareTokens(incentivizedSilo);

        if (Strings.equal(shareTokenType, SHARE_TOKEN_TYPE_DEBT)) {
            shareToken = debtShareToken;
        } else if (Strings.equal(shareTokenType, SHARE_TOKEN_TYPE_COLLATERAL_ONLY)) {
            shareToken = protectedShareToken;
        } else if (Strings.equal(shareTokenType, SHARE_TOKEN_TYPE_COLLATERAL)) {
            shareToken = collateralShareToken;
        } else {
            revert(string.concat("Unknown type of share token ", shareTokenType));
        }

        hookReceiver = config.hookReceiver;

        console2.log("\n--------------------------------");
        console2.log("Incentives controller created for:");
        console2.log("silo", incentivizedSilo);
        console2.log("hookReceiver", hookReceiver);
        console2.log("shareToken", shareToken);

        vm.startBroadcast(deployerPrivateKey);

        incentivesController = IPermissionedLiquidationIncentiveControllerFactory(factory).create({
            _shareToken: IShareToken(shareToken),
            _liquidationEnabled: false
        });

        vm.stopBroadcast();

        SiloIncentivesControllerDeployments.save({
            _chain: ChainsLib.chainAlias(),
            _shareToken: shareToken,
            _deployed: incentivesController
        });
    }
}

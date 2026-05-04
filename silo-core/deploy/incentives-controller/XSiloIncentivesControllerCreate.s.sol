// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";
import {Strings} from "openzeppelin5/utils/Strings.sol";
import {Ownable} from "openzeppelin5/access/Ownable.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {KeyValueStorage} from "silo-foundry-utils/key-value/KeyValueStorage.sol";

import {AddrKey} from "common/addresses/AddrKey.sol";

import {CommonDeploy} from "../_CommonDeploy.sol";
import {SiloCoreContracts, SiloCoreDeployments} from "silo-core/common/SiloCoreContracts.sol";

import {SiloIncentivesControllerFactory} from "silo-core/contracts/incentives/SiloIncentivesControllerFactory.sol";

import {SiloDeployments} from "silo-core/deploy/silo/SiloDeployments.sol";

import {XSilo} from "x-silo/contracts/XSilo.sol";

import {SiloIncentivesControllerDeployments} from "./SiloIncentivesControllerDeployments.sol";
import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";
import {INotificationReceiver} from "silo-vaults/contracts/interfaces/INotificationReceiver.sol";
import {DistributionTypes} from "silo-core/contracts/incentives/lib/DistributionTypes.sol";

import {MintableToken} from "silo-core/test/foundry/_common/MintableToken.sol";

/*
    INCENTIVES_OWNER=GROWTH_MULTISIG FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/incentives-controller/XSiloIncentivesControllerCreate.s.sol \
        --ffi --rpc-url $RPC_SONIC --broadcast --verify

 */
contract XSiloIncentivesControllerCreate is CommonDeploy {
    error OwnerNotFound();
    error XSiloNotFound();

    address public incentivesOwner;
    XSilo public xSilo;

    address qaUser = address(0xabc);

    MintableToken rewardToken = new MintableToken(18);

    function setIncentivesOwner(address _incentivesOwner) public {
        incentivesOwner = _incentivesOwner;
    }

    function setXSilo(XSilo _xSilo) public {
        xSilo = _xSilo;
    }

    function run() public returns (address incentivesController) {
        AddrLib.init();
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        if (incentivesOwner == address(0)) {
            string memory incentivesOwnerKey = vm.envString("INCENTIVES_OWNER");
            incentivesOwner = AddrLib.getAddress(incentivesOwnerKey);
            require(incentivesOwner != address(0), OwnerNotFound());
        }

        if (address(xSilo) == address(0)) {
            xSilo = XSilo(AddrLib.getAddress(ChainsLib.chainAlias(), AddrKey.XSilo));
            console2.log("XSilo deployed at address:", address(xSilo));
            require(address(xSilo) != address(0), XSiloNotFound());
        }

        address factory = SiloCoreDeployments.get(
            SiloCoreContracts.PERMISSIONED_LIQUIDATION_INCENTIVE_CONTROLLER_FACTORY,
            ChainsLib.chainAlias()
        );

        console2.log("\n--------------------------------");
        console2.log("Incentives controller created for:");
        console2.log("xSilo", address(xSilo));

        vm.startBroadcast(deployerPrivateKey);

        incentivesController = IPermissionedLiquidationIncentiveControllerFactory(factory).create(IShareToken(address(xSilo)));

        vm.stopBroadcast();

        KeyValueStorage.setAddress({
            _file: SiloIncentivesControllerDeployments.DEPLOYMENTS_FILE,
            _key1: ChainsLib.chainAlias(),
            _key2: "SIC XSilo",
            _value: incentivesController
        });

        _qa(ISiloIncentivesController(incentivesController));
    }

    function _qa(ISiloIncentivesController _incentivesController) internal {
        console2.log("--------------------------------");
        console2.log("ISiloIncentivesController QA ", address(_incentivesController));
        console2.log("block %s, timestamp %s", block.number, block.timestamp);
        console2.log("--------------------------------");

        address owner = Ownable(address(_incentivesController)).owner();
        console2.log("owner", owner);
        console2.log("SHARE_TOKEN", _incentivesController.SHARE_TOKEN());

        vm.prank(xSilo.owner());
        xSilo.setNotificationReceiver(INotificationReceiver(address(_incentivesController)), true);

        address xSiloHolder = 0xe153437bC974cfE3E06C21c08AeBbf30abaefa2E;
        _usexSiloMethodsToMakeSureAreWorking(_incentivesController, xSiloHolder);

        console2.log("setting notification receiver to 0");
        vm.prank(xSilo.owner());
        xSilo.setNotificationReceiver(INotificationReceiver(address(0)), true);

        _makeXSiloMoves();
    }

    function _usexSiloMethodsToMakeSureAreWorking(ISiloIncentivesController _incentivesController, address _holder)
        internal
    {
        _getTokensFromWhale(_holder);

        _makeXSiloMoves();

        string[] memory programNames = new string[](1);
        programNames[0] = "USDC-for-xSilo";

        // address usdc = AddrLib.getAddress(ChainsLib.chainAlias(), "USDC.e");
        vm.deal(address(_incentivesController), 1 ether);

        address owner = Ownable(address(_incentivesController)).owner();

        vm.prank(owner);
        _incentivesController.createIncentivesProgram(
            DistributionTypes.IncentivesProgramCreationInput({
                name: programNames[0],
                rewardToken: address(rewardToken),
                distributionEnd: uint40(block.timestamp + 1 days),
                emissionPerSecond: 0.0001e18
            })
        );

        uint256 claimable = _printClaimable(_incentivesController);
        require(claimable == 0, "expect no claimable rewards yet");

        _makeXSiloMoves();

        claimable = _printClaimable(_incentivesController);
        require(claimable > 0, "expect something to claim");

        vm.warp(block.timestamp + 1 days);

        claimable = _printClaimable(_incentivesController);

        rewardToken.mint(address(_incentivesController), 100e18);

        vm.prank(qaUser);
        ISiloIncentivesController.AccruedRewards[] memory accruedRewards =
            _incentivesController.claimRewards(qaUser, programNames);
        console2.log("rewards", accruedRewards[0].amount);
    }

    function _printClaimable(ISiloIncentivesController _incentivesController)
        internal
        view
        returns (uint256 claimable)
    {
        string[] memory programNames = new string[](1);
        programNames[0] = "USDC-for-xSilo";

        claimable = _incentivesController.getRewardsBalance(qaUser, programNames);
        console2.log("claimable", claimable);
    }

    function _makeXSiloMoves() internal {
        console2.log("-------------------------------- xSilo moves");

        IERC20 siloToken = IERC20(xSilo.asset());

        vm.warp(block.timestamp + 1 hours);
        vm.startPrank(qaUser);

        uint256 xSiloBalance = xSilo.balanceOf(qaUser);
        console2.log("xSiloBalance", xSiloBalance);
        require(xSiloBalance > 0, "qaUser xBalance is 0");

        uint256 siloBalance = siloToken.balanceOf(qaUser);
        console2.log("siloBalance", siloBalance);
        require(siloBalance > 0, "for QA we require qaUser to have silo tokens");

        xSilo.transfer(address(1), 1);

        vm.warp(block.timestamp + 1 hours);

        siloToken.approve(address(xSilo), siloBalance);
        uint256 shares = xSilo.deposit(siloBalance / 2, qaUser);
        console2.log("shares after deposit", shares);
        require(shares > 0, "failed to deposit silo tokens");

        vm.warp(block.timestamp + 1 hours);

        uint256 assets = xSilo.redeem(shares, qaUser, qaUser);
        console2.log("assets after redeem", assets);
        require(assets > 0, "failed to redeem xSilo tokens");

        console2.log("--------------------------------");

        vm.stopPrank();
    }

    function _getTokensFromWhale(address _whale) internal {
        IERC20 siloToken = IERC20(xSilo.asset());

        vm.startPrank(_whale);
        xSilo.transfer(qaUser, xSilo.balanceOf(_whale));
        siloToken.transfer(qaUser, siloToken.balanceOf(_whale));
        vm.stopPrank();

        uint256 xBalance = xSilo.balanceOf(qaUser);
        uint256 siloBalance = siloToken.balanceOf(qaUser);

        console2.log("qaUser xSilo balance", xBalance);
        console2.log("qaUser silo balance", siloBalance);

        require(xBalance > 0, "qaUser xBalance is 0");
        require(siloBalance > 0, "qaUser siloBalance is 0");
    }
}

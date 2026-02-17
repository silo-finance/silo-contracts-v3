// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Math} from "openzeppelin5/utils/math/Math.sol";
import {Strings} from "openzeppelin5/utils/Strings.sol";

import {console2} from "forge-std/console2.sol";

import {StdAssertions} from "forge-std/StdAssertions.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {CommonDeploy} from "silo-core/deploy/_CommonDeploy.sol";
import {SiloCoreContracts} from "silo-core/common/SiloCoreContracts.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISiloFactory} from "silo-core/contracts/interfaces/ISiloFactory.sol";
import {ISiloLens} from "silo-core/contracts/interfaces/ISiloLens.sol";
import {IMulticall3} from "silo-core/scripts/interfaces/IMulticall3.sol";
import {TokenHelper} from "silo-core/contracts/lib/TokenHelper.sol";
import {Rounding} from "silo-core/contracts/lib/Rounding.sol";
import {PriceFormatter} from "silo-core/deploy/lib/PriceFormatter.sol";

/*
you can run it via:
./silo-core/scripts/withdrawRevenue.sh

# arbitrum

FOUNDRY_PROFILE=core FACTORY=0x384DC7759d35313F0b567D42bf2f611B285B657C\
  forge script silo-core/scripts/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_ARBITRUM --broadcast

FOUNDRY_PROFILE=core FACTORY=0x621Eacb756c7fa8bC0EA33059B881055d1693a33\
  forge script silo-core/scripts/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_ARBITRUM --broadcast

FOUNDRY_PROFILE=core FACTORY=0x44347A91Cf3E9B30F80e2161438E0f10fCeDA0a0\
  forge script silo-core/scripts/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_ARBITRUM --broadcast

  
FOUNDRY_PROFILE=core FACTORY=0x92cECB67Ed267FF98026F814D813fDF3054C6Ff9 \
    forge script silo-core/scripts/WithdrawFees.s.sol \
    --ffi --rpc-url $RPC_AVALANCHE --broadcast

FOUNDRY_PROFILE=core FACTORY=0x22a3cF6149bFa611bAFc89Fd721918EC3Cf7b581\
    forge script silo-core/scripts/WithdrawFees.s.sol \
    --ffi --rpc-url $RPC_MAINNET --broadcast

FOUNDRY_PROFILE=core FACTORY=0xFa773e2c7df79B43dc4BCdAe398c5DCA94236BC5\
    forge script silo-core/scripts/WithdrawFees.s.sol \
    --ffi --rpc-url $RPC_OPTIMISM --broadcast

# sonic 

FOUNDRY_PROFILE=core FACTORY=0x4e9dE3a64c911A37f7EB2fCb06D1e68c3cBe9203\
    forge script silo-core/scripts/WithdrawFees.s.sol \
    --ffi --rpc-url $RPC_SONIC --broadcast


FOUNDRY_PROFILE=core FACTORY=0xa42001D6d2237d2c74108FE360403C4b796B7170\
    forge script silo-core/scripts/WithdrawFees.s.sol \
    --ffi --rpc-url $RPC_SONIC --broadcast
*/
contract WithdrawFees is CommonDeploy, StdAssertions {
    IMulticall3 multicall3 = IMulticall3(0xcA11bde05977b3631167028862bE2a173976CA11);
    IMulticall3.Call3[] calls;

    function run() public {
        ISiloFactory factory = ISiloFactory(vm.envAddress("FACTORY"));
        ISiloLens lens = ISiloLens(getDeployedAddress(SiloCoreContracts.SILO_LENS));

        uint256 startingSiloId;
        uint256 nextSiloId = factory.getNextSiloId();

        if (_startingIdIsOne(factory)) {
            startingSiloId = 1;
        } else if (_startingIdIsHundredOne(factory)) {
            startingSiloId = 101;
        } else if (nextSiloId == 101 || nextSiloId == 1) {
            console2.log("No silos exist");
            return;
        } else {
            revert("Starting Silo id is not 1 or 101");
        }

        console2.log("Starting silo id for a SiloFactory is", startingSiloId);
        uint256 amountOfMarkets = nextSiloId - startingSiloId;
        console2.log("Total markets exist", amountOfMarkets);

        for (uint256 i = 0; i < amountOfMarkets; i++) {
            uint256 siloId = startingSiloId + i;
            ISiloConfig config = ISiloConfig(factory.idToSiloConfig(siloId));

            (address silo0, address silo1) = config.getSilos();
            _pushWithdrawFeesCall(lens, silo0, siloId);
            _pushWithdrawFeesCall(lens, silo1, siloId);
        }

        console2.log("Total amount of silos to call", calls.length);
        if (calls.length == 0) return;

        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        vm.startBroadcast(deployerPrivateKey);
        multicall3.aggregate3(calls);
        vm.stopBroadcast();
    }

    function _pushWithdrawFeesCall(ISiloLens _lens, address _silo, uint256 _siloId) internal {
        ISilo(_silo).accrueInterest();
        uint256 daoAndDeployerRevenue = _lens.protocolFees(ISilo(_silo));
        if (daoAndDeployerRevenue == 0) return;

        (, address deployerFeeReceiver, uint256 daoFee, uint256 deployerFee) =
            _lens.getFeesAndFeeReceivers(ISilo(_silo));

        (uint256 daoRevenue, uint256 deployerRevenue) =
            _withdrawFeesPreview(ISilo(_silo), daoAndDeployerRevenue, daoFee, deployerFee, deployerFeeReceiver);

        if (daoRevenue == 0 && deployerRevenue == 0) return;

        address asset = ISilo(_silo).asset();
        string memory symbol = TokenHelper.symbol(asset);

        uint256 underlyingAssetDecimals = TokenHelper.assertAndGetDecimals(asset);
        uint256 withdrawLimit = 10 ** underlyingAssetDecimals / 100;

        // skip markets with < 0.01 token fees
        if (daoRevenue < withdrawLimit && deployerRevenue < withdrawLimit) {
            console2.log(
                string.concat(
                    "[ID#",
                    Strings.toString(_siloId),
                    "] Skipping silo: ",
                    Strings.toHexString(_silo),
                    " ",
                    symbol,
                    " with daoRevenue: ",
                    PriceFormatter.formatPriceInE(daoRevenue, underlyingAssetDecimals),
                    " and deployerRevenue: ",
                    PriceFormatter.formatPriceInE(deployerRevenue, underlyingAssetDecimals)
                )
            );

            return;
        }

        calls.push(
            IMulticall3.Call3({
                target: _silo,
                callData: abi.encodeWithSelector(ISilo.withdrawFees.selector),
                allowFailure: false
            })
        );

        string memory messageToLog = string.concat(
            Strings.toString(_siloId),
            " id daoAndDeployerRevenue in token ",
            TokenHelper.symbol(ISilo(_silo).asset()),
            " amount (in asset decimals)"
        );

        emit log_named_decimal_uint(messageToLog, daoRevenue + deployerRevenue, underlyingAssetDecimals);
    }

    function _startingIdIsOne(ISiloFactory _factory) internal view returns (bool) {
        return _factory.idToSiloConfig(1) != address(0);
    }

    function _startingIdIsHundredOne(ISiloFactory _factory) internal view returns (bool) {
        return _factory.idToSiloConfig(101) != address(0);
    }

    // copied logic from Silo.sol
    function _withdrawFeesPreview(
        ISilo _silo,
        uint256 earnedFees,
        uint256 daoFee,
        uint256 deployerFee,
        address deployerFeeReceiver
    ) internal view returns (uint256 daoRevenue, uint256 deployerRevenue) {
        uint256 availableLiquidity = _silo.getLiquidity();
        if (earnedFees > availableLiquidity) earnedFees = availableLiquidity;
        if (earnedFees == 0) return (0, 0);

        daoRevenue = earnedFees;

        if (deployerFeeReceiver != address(0)) {
            // split fees proportionally
            daoRevenue = Math.mulDiv(daoRevenue, daoFee, daoFee + deployerFee, Rounding.DAO_REVENUE);
            // `daoRevenue` is chunk of `earnedFees`, so safe to uncheck
            deployerRevenue = earnedFees - daoRevenue;
        }
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
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

interface IOldSiloFactory {
    function idToSilos(uint256 _id) external view returns (address silo0, address silo1);
}

/*
Legacy Forge-based withdraw fees script. The current solution is the Python pipeline in
silo-core/scripts/withdrawFees/ (run via withdrawRevenue.sh there). Kept for reference
and as a fallback.

Run all configured factories via:
./silo-core/scripts/withdrawFeesForge/withdrawRevenue.sh

Or run one factory directly:
FOUNDRY_PROFILE=core \
  FACTORY=0x384DC7759d35313F0b567D42bf2f611B285B657C \
  START_SILO_ID=100 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_ARBITRUM --broadcast
*/
contract WithdrawFees is CommonDeploy, StdAssertions {
    IMulticall3 multicall3 = IMulticall3(0xcA11bde05977b3631167028862bE2a173976CA11);
    IMulticall3.Call3[] calls;
    mapping(uint256 chainId => mapping(address silo => bool excluded)) internal _excludedFromRevenue;

    function run() public {
        ISiloFactory factory = ISiloFactory(vm.envAddress("FACTORY"));
        // ISiloLens lens = ISiloLens(getDeployedAddress(SiloCoreContracts.SILO_LENS));

        _configureRevenueExclusions();

        uint256 startingSiloId = vm.envUint("START_SILO_ID");
        uint256 nextSiloId = factory.getNextSiloId();

        require(startingSiloId <= nextSiloId, "START_SILO_ID out of range");

        console2.log("Starting silo id for a SiloFactory is", startingSiloId);
        uint256 amountOfMarkets = nextSiloId - startingSiloId;
        console2.log("Total markets exist", amountOfMarkets, "\n");

        // Preview phase executes withdrawFees on-chain; revert before broadcast so multicall
        // sees fresh daoAndDeployerRevenue (otherwise EarnedZero on the second call).
        uint256 snap = vm.snapshotState();

        for (uint256 i = 0; i < amountOfMarkets; i++) {
            uint256 siloId = startingSiloId + i;
            address silo0;
            address silo1;
            bool legacy;

            try factory.idToSiloConfig(siloId) returns (address config) {
                if (config == address(0)) continue;

                try ISiloConfig(config).getSilos() returns (address _silo0, address _silo1) {
                    silo0 = _silo0;
                    silo1 = _silo1;
                } catch {
                    legacy = true;
                    (silo0, silo1) = IOldSiloFactory(address(factory)).idToSilos(siloId);
                }
            } catch {
                legacy = true;
                (silo0, silo1) = IOldSiloFactory(address(factory)).idToSilos(siloId);
            }

            if (silo0 == address(0)) continue;

            _pushWithdrawFeesCall({_silo: silo0, _siloId: siloId});
            _pushWithdrawFeesCall({_silo: silo1, _siloId: siloId});
        }

        console2.log("Total amount of silos to call", calls.length);
        if (calls.length == 0) return;

        IMulticall3.Call3[] memory callsToBroadcast = calls;
        vm.revertToState(snap);

        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        vm.startBroadcast(deployerPrivateKey);
        multicall3.aggregate3(callsToBroadcast);
        vm.stopBroadcast();
    }

    function _pushWithdrawFeesCall(address _silo, uint256 _siloId) internal {
        console2.log("\tchecking silo ", _silo, " on chain ", uint256(block.chainid));

        if (_excludedFromRevenue[block.chainid][_silo]) return;

        // ISilo(_silo).accrueInterest();

        // uint256 daoAndDeployerRevenue = _lens.protocolFees(ISilo(_silo));

        // if (daoAndDeployerRevenue == 0) {
        //     console2.log("daoAndDeployerRevenue == 0 in silo", _silo, " #", _siloId);
        //     return;
        // }

        (uint256 revenueToWithdraw, address asset) = _withdrawFeesPreview(ISilo(_silo));

        if (revenueToWithdraw == 0) {
            console2.log("no fees to withdraw in silo", _silo, " #", _siloId);
            return;
        }

        string memory symbol = TokenHelper.symbol(asset);

        uint256 underlyingAssetDecimals = TokenHelper.assertAndGetDecimals(asset);
        uint256 withdrawLimit = 10 ** underlyingAssetDecimals / 100;

        // skip markets with not enough fees to withdraw
        if (revenueToWithdraw < withdrawLimit) {
            console2.log(
                string.concat(
                    "[ID#",
                    Strings.toString(_siloId),
                    "] skipping ",
                    Strings.toHexString(_silo),
                    " with ",
                    PriceFormatter.formatPriceInE(revenueToWithdraw, underlyingAssetDecimals),
                    " ",
                    symbol
                )
            );

            return;
        }

        calls.push(
            IMulticall3.Call3({
                target: _silo, callData: abi.encodeWithSelector(ISilo.withdrawFees.selector), allowFailure: false
            })
        );

        console2.log(
            string.concat(
                "[ID#",
                Strings.toString(_siloId),
                "] WITHDRAWING from ",
                Strings.toHexString(_silo),
                " ",
                PriceFormatter.formatPriceInE(revenueToWithdraw, underlyingAssetDecimals),
                " ",
                symbol
            )
        );
    }

    function _configureRevenueExclusions() internal {
        _excludedFromRevenue[42161][0xeD9F6d6B4889424173E582f2c12C41791ddFdaCA] = true; // blacklisted on token
        _excludedFromRevenue[42161][0x0c12cB6146358AC771Aa0d72bc37F2f0a991e4A7] = true; // undefined issue
    }

    // copied liquidity cap from Actions.withdrawFees (not getLiquidity())
    function _withdrawFeesPreview(ISilo _silo)
        internal
        returns (uint256 revenueToWithdraw, address _asset)
    {
        _asset = _silo.asset();
        uint256 balanceBefore = IERC20(_asset).balanceOf(address(_silo));

        try _silo.withdrawFees() {
            uint256 balanceAfter = IERC20(_asset).balanceOf(address(_silo));
            revenueToWithdraw = balanceBefore - balanceAfter;
        } catch {
            revenueToWithdraw = 0;
        }
    }
}

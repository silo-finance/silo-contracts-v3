// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Math} from "openzeppelin5/utils/math/Math.sol";
import {Strings} from "openzeppelin5/utils/Strings.sol";

import {console2} from "forge-std/console2.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";

import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {CommonDeploy} from "silo-core/deploy/_CommonDeploy.sol";
import {SiloCoreContracts} from "silo-core/common/SiloCoreContracts.sol";
import {ISiloLens} from "silo-core/contracts/interfaces/ISiloLens.sol";
import {IMulticall3} from "silo-core/scripts/interfaces/IMulticall3.sol";
import {Rounding} from "silo-core/contracts/lib/Rounding.sol";
import {PriceFormatter} from "silo-core/deploy/lib/PriceFormatter.sol";

/*
Reads the per-chain silo list discovered by the Python stages and withdraws fees for
every silo with withdrawable revenue, packed into a single Multicall3 transaction.

The whole pipeline is run via:
    silo-core/scripts/withdrawFees/withdrawRevenue.sh

To run this stage alone for a single chain:
    FOUNDRY_PROFILE=core forge script silo-core/scripts/withdrawFees/WithdrawFees.s.sol \
        --ffi --rpc-url $RPC_ARBITRUM --broadcast
*/
contract WithdrawFees is CommonDeploy, StdAssertions {
    IMulticall3 multicall3 = IMulticall3(0xcA11bde05977b3631167028862bE2a173976CA11);
    IMulticall3.Call3[] calls;

    mapping (uint256 chainId => mapping(address silo => bool blacklisted)) public blacklistedSilos;

    constructor() {
        // arbitrum
        blacklistedSilos[42161][0xeD9F6d6B4889424173E582f2c12C41791ddFdaCA] = true;
    }

    function run() public {
        ISiloLens lens = ISiloLens(getDeployedAddress(SiloCoreContracts.SILO_LENS));

        string memory dataPath =
            string.concat("silo-core/scripts/withdrawFees/data/", ChainsLib.chainAlias(), ".json");

        string memory json = vm.readFile(dataPath);
        address[] memory silos = vm.parseJsonAddressArray(json, ".silos");
        // asset symbol/decimals are immutable, precomputed by 2_discover_silos.py (index-aligned)
        string[] memory symbols = vm.parseJsonStringArray(json, ".siloSymbols");
        uint256[] memory decimals = vm.parseJsonUintArray(json, ".siloDecimals");

        console2.log("Loaded silos from", dataPath);
        console2.log("Total discovered silos", silos.length);

        for (uint256 i = 0; i < silos.length; i++) {
            _pushWithdrawFeesCall({_lens: lens, _silo: silos[i], _symbol: symbols[i], _decimals: decimals[i]});
        }

        console2.log("Total amount of silos to call", calls.length);
        if (calls.length == 0) return;

        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        vm.startBroadcast(deployerPrivateKey);
        multicall3.aggregate3(calls);
        vm.stopBroadcast();
    }

    function _pushWithdrawFeesCall(
        ISiloLens _lens,
        address _silo,
        string memory _symbol,
        uint256 _decimals
    ) internal {
        if (blacklistedSilos[block.chainid][_silo]) return;

        ISilo(_silo).accrueInterest();
        uint256 daoAndDeployerRevenue = _lens.protocolFees(ISilo(_silo));
        if (daoAndDeployerRevenue == 0) {
            console2.log("Skipping silo: ", _silo, " with no daoAndDeployerRevenue");
            return;
        }

        (, address deployerFeeReceiver, uint256 daoFee, uint256 deployerFee) =
            _lens.getFeesAndFeeReceivers(ISilo(_silo));

        (uint256 daoRevenue, uint256 deployerRevenue) =
            _withdrawFeesPreview(ISilo(_silo), daoAndDeployerRevenue, daoFee, deployerFee, deployerFeeReceiver);

        if (daoRevenue == 0 && deployerRevenue == 0) {
            console2.log("Skipping silo: ", _silo, " with no daoRevenue and no deployerRevenue");
            return;
        }

        uint256 withdrawLimit = 10 ** _decimals / 100;

        // skip markets with < 0.01 token fees
        if (daoRevenue < withdrawLimit && deployerRevenue < withdrawLimit) {
            console2.log(
                string.concat(
                    "Skipping silo: ",
                    Strings.toHexString(_silo),
                    " ",
                    _symbol,
                    " with daoRevenue: ",
                    PriceFormatter.formatPriceInE(daoRevenue, _decimals),
                    " and deployerRevenue: ",
                    PriceFormatter.formatPriceInE(deployerRevenue, _decimals)
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
            Strings.toHexString(_silo),
            " daoAndDeployerRevenue in token ",
            _symbol,
            " amount (in asset decimals)"
        );

        emit log_named_decimal_uint(messageToLog, daoRevenue + deployerRevenue, _decimals);
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

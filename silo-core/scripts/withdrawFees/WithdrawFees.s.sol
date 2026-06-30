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

All on-chain reads (protocolFees, getFeesAndFeeReceivers, getLiquidity) are batched into a
single Multicall3.aggregate3 staticcall, so the cost is ~1 read multicall + 1 withdraw
multicall regardless of how many silos there are (instead of a few calls per silo).

The whole pipeline is run via:
    silo-core/scripts/withdrawFees/withdrawRevenue.sh

To run this stage alone for a single chain:
    FOUNDRY_PROFILE=core forge script silo-core/scripts/withdrawFees/WithdrawFees.s.sol \
        --ffi --rpc-url $RPC_ARBITRUM --broadcast
*/
contract WithdrawFees is CommonDeploy, StdAssertions {
    // matches one object in the per-chain data file `silos` array.
    // NOTE: fields MUST stay in alphabetical order so `vm.parseJson` can decode the
    // JSON objects (keys are sorted alphabetically) straight into this struct.
    struct SiloData {
        address asset;
        uint256 decimals;
        address silo;
        string symbol;
    }

    // read calls batched per silo: accrueInterest, protocolFees, getFeesAndFeeReceivers, getLiquidity.
    // accrueInterest runs first so protocolFees/getLiquidity reflect pending interest. It is part of
    // the (non-broadcast) aggregate3 read, so it only mutates the simulated state, never on-chain.
    uint256 internal constant READS_PER_SILO = 4;

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
        // each silo carries its (immutable) asset symbol/decimals, precomputed by 2_discover_silos.py
        bytes memory raw = vm.parseJson(json, ".silos");
        SiloData[] memory silos = abi.decode(raw, (SiloData[]));

        console2.log("Loaded silos from", dataPath);
        console2.log("Total discovered silos", silos.length);

        // 1) one multicall to read everything we need for every silo
        IMulticall3.Result[] memory reads = _batchReads(lens, silos);

        // 2) decide per silo (pure local processing of the batched results)
        for (uint256 i = 0; i < silos.length; i++) {
            // reads[i * READS_PER_SILO] is accrueInterest (state-priming only, result ignored)
            _pushWithdrawFeesCall({
                _silo: silos[i],
                _protocolFeesResult: reads[i * READS_PER_SILO + 1],
                _feeReceiversResult: reads[i * READS_PER_SILO + 2],
                _liquidityResult: reads[i * READS_PER_SILO + 3]
            });
        }

        console2.log("Total amount of silos to call", calls.length);
        if (calls.length == 0) return;

        // 3) one multicall to withdraw from every eligible silo
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        vm.startBroadcast(deployerPrivateKey);
        multicall3.aggregate3(calls);
        vm.stopBroadcast();
    }

    /// @dev Batches protocolFees + getFeesAndFeeReceivers + getLiquidity for every silo into a
    /// single aggregate3 read. Result layout is [silo0.protocolFees, silo0.fees, silo0.liquidity, silo1...].
    function _batchReads(ISiloLens _lens, SiloData[] memory _silos)
        internal
        returns (IMulticall3.Result[] memory results)
    {
        IMulticall3.Call3[] memory reads = new IMulticall3.Call3[](_silos.length * READS_PER_SILO);

        for (uint256 i = 0; i < _silos.length; i++) {
            ISilo silo = ISilo(_silos[i].silo);

            reads[i * READS_PER_SILO] = IMulticall3.Call3({
                target: address(silo),
                allowFailure: true,
                callData: abi.encodeCall(ISilo.accrueInterest, ())
            });
            reads[i * READS_PER_SILO + 1] = IMulticall3.Call3({
                target: address(_lens),
                allowFailure: true,
                callData: abi.encodeCall(ISiloLens.protocolFees, (silo))
            });
            reads[i * READS_PER_SILO + 2] = IMulticall3.Call3({
                target: address(_lens),
                allowFailure: true,
                callData: abi.encodeCall(ISiloLens.getFeesAndFeeReceivers, (silo))
            });
            reads[i * READS_PER_SILO + 3] = IMulticall3.Call3({
                target: address(silo),
                allowFailure: true,
                callData: abi.encodeCall(ISilo.getLiquidity, ())
            });
        }

        results = multicall3.aggregate3(reads);
    }

    function _pushWithdrawFeesCall(
        SiloData memory _silo,
        IMulticall3.Result memory _protocolFeesResult,
        IMulticall3.Result memory _feeReceiversResult,
        IMulticall3.Result memory _liquidityResult
    ) internal {
        if (blacklistedSilos[block.chainid][_silo.silo]) return;

        if (!_protocolFeesResult.success || !_feeReceiversResult.success || !_liquidityResult.success) {
            console2.log("Skipping silo: ", _silo.silo, " - a read call reverted");
            return;
        }

        uint256 daoAndDeployerRevenue = abi.decode(_protocolFeesResult.returnData, (uint256));
        if (daoAndDeployerRevenue == 0) {
            console2.log("Skipping silo: ", _silo.silo, " with no daoAndDeployerRevenue");
            return;
        }

        (uint256 daoRevenue, uint256 deployerRevenue) = _withdrawFeesPreview(
            daoAndDeployerRevenue, _liquidityResult.returnData, _feeReceiversResult.returnData
        );

        if (daoRevenue == 0 && deployerRevenue == 0) {
            console2.log("Skipping silo: ", _silo.silo, " with no daoRevenue and no deployerRevenue");
            return;
        }

        _queueOrSkip(_silo, daoRevenue, deployerRevenue);
    }

    function _queueOrSkip(SiloData memory _silo, uint256 _daoRevenue, uint256 _deployerRevenue) internal {
        // skip markets with < 0.01 token fees
        if (_daoRevenue < 10 ** _silo.decimals / 100 && _deployerRevenue < 10 ** _silo.decimals / 100) {
            console2.log(
                string.concat(
                    "Skipping silo: ",
                    Strings.toHexString(_silo.silo),
                    " ",
                    _silo.symbol,
                    " with daoRevenue: ",
                    PriceFormatter.formatPriceInE(_daoRevenue, _silo.decimals),
                    " and deployerRevenue: ",
                    PriceFormatter.formatPriceInE(_deployerRevenue, _silo.decimals)
                )
            );

            return;
        }

        calls.push(
            IMulticall3.Call3({
                target: _silo.silo,
                callData: abi.encodeWithSelector(ISilo.withdrawFees.selector),
                allowFailure: false
            })
        );

        string memory messageToLog = string.concat(
            Strings.toHexString(_silo.silo),
            " daoAndDeployerRevenue in token ",
            _silo.symbol,
            " amount (in asset decimals)"
        );

        emit log_named_decimal_uint(messageToLog, _daoRevenue + _deployerRevenue, _silo.decimals);
    }

    // copied logic from Silo.sol; reads decoded from the batched aggregate3 results
    function _withdrawFeesPreview(uint256 _earnedFees, bytes memory _liquidityData, bytes memory _feeReceiversData)
        internal
        pure
        returns (uint256 daoRevenue, uint256 deployerRevenue)
    {
        uint256 availableLiquidity = abi.decode(_liquidityData, (uint256));
        if (_earnedFees > availableLiquidity) _earnedFees = availableLiquidity;
        if (_earnedFees == 0) return (0, 0);

        (, address deployerFeeReceiver, uint256 daoFee, uint256 deployerFee) =
            abi.decode(_feeReceiversData, (address, address, uint256, uint256));

        daoRevenue = _earnedFees;

        if (deployerFeeReceiver != address(0)) {
            // split fees proportionally
            daoRevenue = Math.mulDiv(daoRevenue, daoFee, daoFee + deployerFee, Rounding.DAO_REVENUE);
            // `daoRevenue` is chunk of `_earnedFees`, so safe to uncheck
            deployerRevenue = _earnedFees - daoRevenue;
        }
    }
}

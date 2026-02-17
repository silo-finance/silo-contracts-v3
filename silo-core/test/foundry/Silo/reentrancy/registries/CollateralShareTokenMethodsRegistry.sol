// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ShareTokenMethodsRegistry} from "./ShareTokenMethodsRegistry.sol";

import {TransferReentrancyTest} from "../methods/collateral-share-token/TransferReentrancyTest.sol";
import {TransferFromReentrancyTest} from "../methods/collateral-share-token/TransferFromReentrancyTest.sol";

contract CollateralShareTokenMethodsRegistry is ShareTokenMethodsRegistry {
    constructor() {
        _registerMethod(new TransferReentrancyTest());
        _registerMethod(new TransferFromReentrancyTest());
    }

    function abiFile() external pure override returns (string memory) {
        return "/cache/foundry/out/silo-core/ShareCollateralToken.sol/ShareCollateralToken.json";
    }
}

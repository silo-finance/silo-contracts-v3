// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import {IGaugeHookReceiver} from "./IGaugeHookReceiver.sol";
import {IPartialLiquidation} from "./IPartialLiquidation.sol";
import {IPartialLiquidationByDefaulting} from "./IPartialLiquidationByDefaulting.sol";

interface ISiloHookV2 is IGaugeHookReceiver, IPartialLiquidation, IPartialLiquidationByDefaulting {}

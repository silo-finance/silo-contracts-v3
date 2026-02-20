// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {
    DynamicKinkModel, IDynamicKinkModel
} from "../../../../contracts/interestRateModel/kink/DynamicKinkModel.sol";
import {DynamicKinkModelConfig} from "../../../../contracts/interestRateModel/kink/DynamicKinkModelConfig.sol";
import {SafeCast} from "openzeppelin5/utils/math/SafeCast.sol";

contract DynamicKinkModelMock is DynamicKinkModel {
    using SafeCast for int256;

    function mockState(IDynamicKinkModel.Config memory _c, int96 _k) external {
        IDynamicKinkModel.ImmutableConfig memory immutableConfig =
            IDynamicKinkModel.ImmutableConfig({timelock: 0 days, rcompCapPerSecond: RCOMP_CAP_PER_SECOND.toInt96()});

        _irmConfig = new DynamicKinkModelConfig(_c, immutableConfig);
        _modelState.k = _k;
    }

    function mockStateK(int96 _k) external {
        _modelState.k = _k;
    }

    function mockHistoryK(int96 _k) external {
        configsHistory[_irmConfig].k = _k;
    }
}

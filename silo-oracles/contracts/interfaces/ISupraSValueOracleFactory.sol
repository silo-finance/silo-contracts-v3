// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ISupraSValueOracle} from "./ISupraSValueOracle.sol";
import {ISupraSValueFeed} from "./ISupraSValueFeed.sol";

interface ISupraSValueOracleFactory {
    error DeployerCannotBeZero();

    function create(ISupraSValueOracle.DeploymentConfig memory _config, bytes32 _externalSalt)
        external
        returns (ISupraSValueOracle oracle);

    function verifyConfig(ISupraSValueOracle.DeploymentConfig memory _config)
        external
        view
        returns (
            uint256 normalizationDivider,
            uint256 normalizationMultiplier,
            uint8 priceDecimals,
            ISupraSValueFeed supraFeed
        );

    function predictAddress(address _deployer, bytes32 _externalSalt) external view returns (address predictedAddress);
}

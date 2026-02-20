// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {DIA_ORACLE_V2} from "../../../constants/Arbitrum.sol";

import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";
import {IDIAOracle, IDIAOracleV2} from "../../../contracts/dia/DIAOracle.sol";
import {TokensGenerator} from "./TokensGenerator.sol";

abstract contract DIAConfigDefault is TokensGenerator {
    function _defaultDIAConfig() internal view returns (IDIAOracle.DIADeploymentConfig memory) {
        return IDIAOracle.DIADeploymentConfig(
            IDIAOracleV2(DIA_ORACLE_V2),
            IERC20Metadata(address(tokens["RDPX"])),
            IERC20Metadata(address(tokens["USDT"])),
            1 days,
            "RDPX/USD",
            "",
            1,
            0,
            false
        );
    }

    function _defaultDIAConfig(uint256 _divider, uint256 _multiplier)
        internal
        view
        returns (IDIAOracle.DIADeploymentConfig memory)
    {
        return IDIAOracle.DIADeploymentConfig(
            IDIAOracleV2(DIA_ORACLE_V2),
            IERC20Metadata(address(tokens["RDPX"])),
            IERC20Metadata(address(tokens["USDT"])),
            1 days,
            "RDPX/USD",
            "",
            _divider,
            _multiplier,
            false
        );
    }

    function _defaultDIAConfigTwoFeeds(
        string memory _firstFeed,
        string memory _secondFeed,
        uint256 _divider,
        uint256 _multiplier,
        bool _invert
    ) internal view returns (IDIAOracle.DIADeploymentConfig memory) {
        return IDIAOracle.DIADeploymentConfig(
            IDIAOracleV2(DIA_ORACLE_V2),
            IERC20Metadata(address(tokens["RDPX"])),
            IERC20Metadata(address(tokens["USDT"])),
            1 days,
            _firstFeed,
            _secondFeed,
            _divider,
            _multiplier,
            _invert
        );
    }

    function _printDIADeployemntConfig(IDIAOracle.DIADeploymentConfig memory _config) internal {
        emit log_named_address("quote token", address(_config.quoteToken));
        emit log_named_address("base token", address(_config.baseToken));
        emit log_named_address("diaOracle", address(_config.diaOracle));
        emit log_named_uint("heartbeat", _config.heartbeat);
        emit log_named_string("primaryKey", _config.primaryKey);
        emit log_named_string("secondaryKey", _config.secondaryKey);
        emit log_named_uint("normalizationDivider", _config.normalizationDivider);
        emit log_named_uint("normalizationMultiplier", _config.normalizationMultiplier);
    }

    function _printDIAConfig(IDIAOracle.DIAConfig memory _data) internal {
        emit log_named_address("diaOracle", address(_data.diaOracle));
        emit log_named_address("base token", _data.baseToken);
        emit log_named_address("quote token", _data.quoteToken);
        emit log_named_uint("heartbeat", _data.heartbeat);
        emit log_named_uint("normalizationDivider", _data.normalizationDivider);
        emit log_named_uint("normalizationMultiplier", _data.normalizationMultiplier);
        emit log_named_string("convertToQuote", _data.convertToQuote ? "yes" : "no");
    }
}

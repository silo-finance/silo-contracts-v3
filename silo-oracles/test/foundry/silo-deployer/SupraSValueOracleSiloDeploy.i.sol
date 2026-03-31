// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";

import {ISiloDeployer} from "silo-core/contracts/interfaces/ISiloDeployer.sol";

import {ISupraOraclePull_V2} from "silo-oracles/contracts/interfaces/ISupraOraclePull_V2.sol";
import {ISupraSValueFeed} from "silo-oracles/contracts/interfaces/ISupraSValueFeed.sol";
import {ISupraSValueOracle} from "silo-oracles/contracts/interfaces/ISupraSValueOracle.sol";
import {ISupraSValueOracleFactory} from "silo-oracles/contracts/interfaces/ISupraSValueOracleFactory.sol";
import {SupraSValueOracleFactory} from "silo-oracles/contracts/supra/SupraSValueOracleFactory.sol";

import {SiloDeployerWithOracle} from "./SiloDeployerWithOracle.sol";

contract _SupraFeedMock is ISupraSValueFeed {
    PriceFeed internal _data;

    constructor(uint256 _price, uint256 _decimals) {
        _data = PriceFeed({round: 1, decimals: _decimals, time: block.timestamp, price: _price});
    }

    function getSvalue(uint256) external view returns (PriceFeed memory) {
        return _data;
    }
}

contract _SupraOraclePullV2Mock is ISupraOraclePull_V2 {
    address internal _feed;

    constructor(address _feedAddress) {
        _feed = _feedAddress;
    }

    function setFeed(address _feedAddress) external {
        _feed = _feedAddress;
    }

    function checkSupraSValueFeed() external view returns (address) {
        return _feed;
    }
}

/*
    FOUNDRY_PROFILE=oracles forge test --mc SupraSValueOracleSiloDeployIntegrationTest --ffi -vv
*/
contract SupraSValueOracleSiloDeployIntegrationTest is SiloDeployerWithOracle {
    uint256 internal constant SUPRA_XDC_PAIR_ID = 150;
    ISupraSValueOracleFactory internal supraOracleFactory;
    _SupraOraclePullV2Mock internal oraclePullMock;

    function test_siloDeployer_SupraSValueOracle() public {
        _deployMarket();

        ISupraSValueOracle oracle = ISupraSValueOracle(address(siloOracle));
        ISupraSValueOracle.OracleConfig memory cfg = oracle.getConfig();

        console2.log("oracle", address(oracle));
        console2.log("pairId", cfg.pairId);

        assertEq(cfg.baseToken, address(token0), "base token mismatch");
        assertEq(cfg.quoteToken, address(token1), "quote token mismatch");
        assertEq(cfg.pairId, SUPRA_XDC_PAIR_ID, "pair id mismatch");
    }

    function _deployOracleFactory() internal override {
        oraclePullMock = new _SupraOraclePullV2Mock(address(0));
        supraOracleFactory = ISupraSValueOracleFactory(address(new SupraSValueOracleFactory(oraclePullMock)));
    }

    function _oracleTxData() internal override returns (ISiloDeployer.OracleCreationTxData memory txData) {
        _SupraFeedMock feed = new _SupraFeedMock(2e8, 8);
        oraclePullMock.setFeed(address(feed));

        ISupraSValueOracle.DeploymentConfig memory cfg = ISupraSValueOracle.DeploymentConfig({
            baseToken: token0,
            quoteToken: token1,
            pairId: SUPRA_XDC_PAIR_ID
        });

        txData = ISiloDeployer.OracleCreationTxData({
            deployed: address(0),
            factory: address(supraOracleFactory),
            txInput: abi.encodeCall(ISupraSValueOracleFactory.create, (cfg, bytes32(0)))
        });
    }
}

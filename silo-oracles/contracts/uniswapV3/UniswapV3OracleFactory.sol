// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import {IUniswapV3Factory} from  "uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from  "uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {Clones} from "../lib/Clones.sol";

import {Create2Factory} from "../_common/Create2Factory.sol";
import {OracleFactory} from "../_common/OracleFactory.sol";
import {IUniswapV3Oracle} from "../interfaces/IUniswapV3Oracle.sol";
import {UniswapV3OracleConfig} from "../uniswapV3/UniswapV3OracleConfig.sol";
import {UniswapV3Oracle} from "../uniswapV3/UniswapV3Oracle.sol";
import {IERC20BalanceOf} from "../interfaces/IERC20BalanceOf.sol";

contract UniswapV3OracleFactory is OracleFactory, Create2Factory {
    /// @dev UniswapV3 factory contract
    IUniswapV3Factory public immutable UNISWAPV3_FACTORY; // solhint-disable-line var-name-mixedcase

    constructor(IUniswapV3Factory _factory) OracleFactory(address(new UniswapV3Oracle())) {
        // sanity check, this is stronger than just checking if address is 0
        _factory.feeAmountTickSpacing(1000);
        UNISWAPV3_FACTORY = _factory;
    }

    /// @dev you need to make sure, that pool you are using is valid and can provide a TWAP price
    /// this method does no verify it, you can verify by calling `verifyPool`
    /// @param _config UniswapV3DeploymentConfig configuration data
    function create(
        IUniswapV3Oracle.UniswapV3DeploymentConfig memory _config,
        bytes32 _externalSalt
    ) external virtual returns (UniswapV3Oracle oracle)
    {
        bytes32 id = hashConfig(_config);
        address oracleConfig = getConfigAddress[id];

        if (oracleConfig != address(0)) {
            // config already exists, so oracle exists as well
            return UniswapV3Oracle(getOracleAddress[oracleConfig]);
        }

        uint16 requiredCardinality = verifyConfig(_config);

        oracleConfig = address(new UniswapV3OracleConfig(_config, requiredCardinality));
        oracle = UniswapV3Oracle(Clones.cloneDeterministic(ORACLE_IMPLEMENTATION, _salt(_externalSalt)));

        _saveOracle(address(oracle), oracleConfig, id);

        oracle.initialize(UniswapV3OracleConfig(oracleConfig));
    }

    /// @notice Check if UniV3 pool has enough cardinality to meet Silo's requirements
    /// If it does not have, please execute `adjustOracleCardinality`.
    /// @param _pool UniV3 pool address
    /// @return bufferFull TRUE if buffer is ready to provide TWAP price rof required period
    /// @return enoughObservations TRUE if buffer has enough observations spots (they don't have to be filled up yet)
    function observationsStatus(IUniswapV3Pool _pool, uint16 _requiredCardinality)
        external
        view
        virtual
        returns (bool bufferFull, bool enoughObservations, uint16 currentCardinality)
    {
        return _observationsStatus(_pool, _requiredCardinality);
    }

    /// @dev It's run few checks on `_pool`, making sure we can use it for providing price
    /// Throws when there is no pool or pool is empty (zero liquidity) or not ready for price
    /// @param _pool UniV3 pool addresses that will be verified
    /// @param _quoteToken asset in which oracle denominates its price
    function verifyPool(
        IUniswapV3Pool _pool,
        address _quoteToken,
        uint16 _requiredCardinality
    )
        external
        view
        virtual
    {
        address token0 = _pool.token0();
        address token1 = _pool.token1();

        if (token0 != _quoteToken && token1 != _quoteToken) {
            revert("InvalidPoolForQuoteToken");
        }

        address otherToken = _quoteToken == token0 ? token1 : token0;

        if (UNISWAPV3_FACTORY.getPool(_quoteToken, otherToken, _pool.fee()) != address(_pool)) {
            revert("InvalidPool");
        }

        uint256 liquidity = IERC20BalanceOf(token0).balanceOf(address(_pool));
        if (liquidity == 0) revert("EmptyPool0");

        liquidity = IERC20BalanceOf(token1).balanceOf(address(_pool));
        if (liquidity == 0) revert("EmptyPool1");

        (bool bufferFull,,) = _observationsStatus(_pool, _requiredCardinality);
        if (!bufferFull) revert("BufferNotFull");
    }

    function hashConfig(IUniswapV3Oracle.UniswapV3DeploymentConfig memory _config)
        public
        virtual
        view
        returns (bytes32 configId)
    {
        configId = keccak256(abi.encode(_config));
    }

    /// @dev It verifies config, throws when invalid
    /// @param _config UniswapV3DeploymentConfig struct
    /// @return requiredCardinality when config is valid, returns required Cardinality value
    function verifyConfig(IUniswapV3Oracle.UniswapV3DeploymentConfig memory _config)
        public
        pure
        virtual
        returns (uint16 requiredCardinality)
    {
        if (_config.blockTime == 0) revert("InvalidBlockTime");
        if (_config.periodForAvgPrice == 0) revert("InvalidPeriodForAvgPrice");

        // ideally we want to have data at every block during periodForAvgPrice
        // If we want to get TWAP for 5 minutes and assuming we have tx in every block, and block time is 15 sec,
        // then for 5 minutes we will have 20 blocks, that means our requiredCardinality is 20.
        // safe match is not needed, *10 is safe on uint32, / is also safe
        uint256 cardinality = uint256(_config.periodForAvgPrice) * 10 / _config.blockTime;

        if (cardinality > type(uint16).max) revert("InvalidRequiredCardinality");
        if (address(_config.pool) == address(0)) revert("EmptyPool");
        if (_config.quoteToken == address(0)) revert("EmptyQuoteToken");

        // Safe: guarded above by `cardinality <= type(uint16).max`.
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint16(cardinality);
    }

    function _observationsStatus(IUniswapV3Pool _pool, uint16 _requiredCardinality)
        internal
        view
        virtual
        returns (
            bool bufferFull,
            bool enoughObservations,
            uint16 currentCardinality
        )
    {
        (,,, uint16 currentObservationCardinality, uint16 observationCardinalityNext,,) = _pool.slot0();

        bufferFull = currentObservationCardinality >= _requiredCardinality;
        enoughObservations = observationCardinalityNext >= _requiredCardinality;
        currentCardinality = currentObservationCardinality;
    }
}

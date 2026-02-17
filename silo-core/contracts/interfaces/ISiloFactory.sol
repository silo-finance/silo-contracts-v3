// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import {IERC721} from "openzeppelin5/interfaces/IERC721.sol";
import {ISiloConfig} from "./ISiloConfig.sol";

interface ISiloFactory is IERC721 {
    struct Range {
        uint128 min;
        uint128 max;
    }

    /// @notice Emitted on the creation of a Silo.
    /// @param implementation Address of the Silo implementation.
    /// @param token0 Address of the first Silo token.
    /// @param token1 Address of the second Silo token.
    /// @param silo0 Address of the first Silo.
    /// @param silo1 Address of the second Silo.
    /// @param siloConfig Address of the SiloConfig.
    event NewSilo(
        address indexed implementation,
        address indexed token0,
        address indexed token1,
        address silo0,
        address silo1,
        address siloConfig
    );

    /// @notice Emitted on the creation of a Silo, note that collateral share token == silo
    event NewSiloShareTokens(
        address indexed protectedShareToken, 
        address indexed collateralShareToken,
        address indexed debtShareToken
    );

    event NewSiloHook(address indexed silo, address indexed hook);

    event BaseURI(string newBaseURI);

    /// @notice Emitted on the update of DAO fee.
    /// @param minDaoFee Value of the new minimal DAO fee.
    /// @param maxDaoFee Value of the new maximal DAO fee.
    event DaoFeeChanged(uint128 minDaoFee, uint128 maxDaoFee);

    /// @notice Emitted on the update of max deployer fee.
    /// @param maxDeployerFee Value of the new max deployer fee.
    event MaxDeployerFeeChanged(uint256 maxDeployerFee);

    /// @notice Emitted on the update of max flashloan fee.
    /// @param maxFlashloanFee Value of the new max flashloan fee.
    event MaxFlashloanFeeChanged(uint256 maxFlashloanFee);

    /// @notice Emitted on the update of max liquidation fee.
    /// @param maxLiquidationFee Value of the new max liquidation fee.
    event MaxLiquidationFeeChanged(uint256 maxLiquidationFee);

    /// @notice Emitted on the change of DAO fee receiver.
    /// @param daoFeeReceiver Address of the new DAO fee receiver.
    event DaoFeeReceiverChanged(address daoFeeReceiver);

    /// @notice Emitted on the change of DAO fee receiver for particular silo
    /// @param silo Address for which new DAO fee receiver is set.
    /// @param daoFeeReceiver Address of the new DAO fee receiver.
    event DaoFeeReceiverChangedForSilo(address silo, address daoFeeReceiver);

    /// @notice Emitted on the change of DAO fee receiver for particular asset
    /// @param asset Address for which new DAO fee receiver is set.
    /// @param daoFeeReceiver Address of the new DAO fee receiver.
    event DaoFeeReceiverChangedForAsset(address asset, address daoFeeReceiver);

    error MissingHookReceiver();
    error ZeroAddress();
    error DaoFeeReceiverZeroAddress();
    error SameDaoFeeReceiver();
    error EmptyToken0();
    error EmptyToken1();
    error MaxFeeExceeded();
    error InvalidFeeRange();
    error SameAsset();
    error SameRange();
    error InvalidIrm();
    error InvalidMaxLtv();
    error InvalidLt();
    error InvalidDeployer();
    error DaoMinRangeExceeded();
    error DaoMaxRangeExceeded();
    error MaxDeployerFeeExceeded();
    error MaxFlashloanFeeExceeded();
    error MaxLiquidationFeeExceeded();
    error InvalidCallBeforeQuote();
    error OracleMisconfiguration();
    error InvalidQuoteToken();
    error HookIsZeroAddress();
    error LiquidationTargetLtvTooHigh();
    error NotYourSilo();
    error ConfigMismatchSilo();
    error ConfigMismatchShareProtectedToken();
    error ConfigMismatchShareDebtToken();
    error ConfigMismatchShareCollateralToken();

    /// @notice Create a new Silo.
    /// @param _siloConfig Silo configuration.
    /// @param _siloImpl Address of the `Silo` implementation.
    /// @param _shareProtectedCollateralTokenImpl Address of the `ShareProtectedCollateralToken` implementation.
    /// @param _shareDebtTokenImpl Address of the `ShareDebtToken` implementation.
    /// @param _deployer Address of the deployer.
    /// @param _creator Address of the creator.
    function createSilo(
        ISiloConfig _siloConfig,
        address _siloImpl,
        address _shareProtectedCollateralTokenImpl,
        address _shareDebtTokenImpl,
        address _deployer,
        address _creator
    )
        external;

    /// @notice NFT ownership represents the deployer fee receiver for the each Silo ID.  After burning, 
    /// the deployer fee is sent to the DAO. Burning doesn't affect Silo's behavior. It is only about fee distribution.
    /// @param _siloIdToBurn silo ID to burn.
    function burn(uint256 _siloIdToBurn) external;

    /// @notice Update the value of DAO fee. Updated value will be used only for a new Silos.
    /// Previously deployed SiloConfigs are immutable.
    /// @param _minFee Value of the new DAO minimal fee.
    /// @param _maxFee Value of the new DAO maximal fee.
    function setDaoFee(uint128 _minFee, uint128 _maxFee) external;

    /// @notice Set the default DAO fee receiver.
    /// @param _newDaoFeeReceiver Address of the new DAO fee receiver.
    function setDaoFeeReceiver(address _newDaoFeeReceiver) external;

    /// @notice Set the new DAO fee receiver for asset, this setup will be used when fee receiver for silo is empty.
    /// @param _asset Address for which new DAO fee receiver is set.
    /// @param _newDaoFeeReceiver Address of the new DAO fee receiver.
    function setDaoFeeReceiverForAsset(address _asset, address _newDaoFeeReceiver) external;

    /// @notice Set the new DAO fee receiver for silo. This setup has highest priority.
    /// @param _silo Address for which new DAO fee receiver is set.
    /// @param _newDaoFeeReceiver Address of the new DAO fee receiver.
    function setDaoFeeReceiverForSilo(address _silo, address _newDaoFeeReceiver) external;

    /// @notice Update the value of max deployer fee. Updated value will be used only for a new Silos max deployer
    /// fee validation. Previously deployed SiloConfigs are immutable.
    /// @param _newMaxDeployerFee Value of the new max deployer fee.
    function setMaxDeployerFee(uint256 _newMaxDeployerFee) external;

    /// @notice Update the value of max flashloan fee. Updated value will be used only for a new Silos max flashloan
    /// fee validation. Previously deployed SiloConfigs are immutable.
    /// @param _newMaxFlashloanFee Value of the new max flashloan fee.
    function setMaxFlashloanFee(uint256 _newMaxFlashloanFee) external;

    /// @notice Update the value of max liquidation fee. Updated value will be used only for a new Silos max
    /// liquidation fee validation. Previously deployed SiloConfigs are immutable.
    /// @param _newMaxLiquidationFee Value of the new max liquidation fee.
    function setMaxLiquidationFee(uint256 _newMaxLiquidationFee) external;
   
    /// @notice Update the base URI.
    /// @param _newBaseURI Value of the new base URI.
    function setBaseURI(string calldata _newBaseURI) external;

    /// @notice Acceptable DAO fee range for new Silos. Denominated in 18 decimals points. 1e18 == 100%.
    function daoFeeRange() external view returns (Range memory);

    /// @notice Max deployer fee for a new Silos. Denominated in 18 decimals points. 1e18 == 100%.
    function maxDeployerFee() external view returns (uint256);

    /// @notice Max flashloan fee for a new Silos. Denominated in 18 decimals points. 1e18 == 100%.
    function maxFlashloanFee() external view returns (uint256);

    /// @notice Max liquidation fee for a new Silos. Denominated in 18 decimals points. 1e18 == 100%.
    function maxLiquidationFee() external view returns (uint256);

    /// @notice The recipient of DAO fees.
    function daoFeeReceiver() external view returns (address);

    /// @notice Get SiloConfig address by Silo id.
    function idToSiloConfig(uint256 _id) external view returns (address);

    /// @notice Get the counter of silos created by the wallet.
    function creatorSiloCounter(address _creator) external view returns (uint256);

    /// @notice Do not use this method to check if silo is secure. Anyone can deploy silo with any configuration
    /// and implementation. Most critical part of verification would be to check who deployed it.
    /// @dev True if the address was deployed using SiloFactory.
    function isSilo(address _silo) external view returns (bool);

    /// @notice Id of a next Silo to be deployed. This is an ID of non-existing Silo outside of createSilo
    /// function call. ID of a first Silo is 1.
    function getNextSiloId() external view returns (uint256);

    /// @notice Get the DAO and deployer fee receivers for a particular Silo address.
    /// @param _silo Silo address.
    /// @return dao DAO fee receiver.
    /// @return deployer Deployer fee receiver.
    function getFeeReceivers(address _silo) external view returns (address dao, address deployer);

    /// @notice Validate InitData for a new Silo. Config will be checked for the fee limits, missing parameters.
    /// @param _initData Silo init data.
    function validateSiloInitData(ISiloConfig.InitData memory _initData) external view returns (bool);
}

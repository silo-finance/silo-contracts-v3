// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Clones} from "openzeppelin5/proxy/Clones.sol";

import {Create2Factory} from "common/utils/Create2Factory.sol";
import {InterestRateModelV2} from "./InterestRateModelV2.sol";
import {IInterestRateModel} from "../interfaces/IInterestRateModel.sol";
import {IInterestRateModelV2} from "../interfaces/IInterestRateModelV2.sol";
import {IInterestRateModelV2Factory} from "../interfaces/IInterestRateModelV2Factory.sol";
import {InterestRateModelV2Config} from "./InterestRateModelV2Config.sol";

/// @title InterestRateModelV2Factory
/// @dev It creates InterestRateModelV2Config.
contract InterestRateModelV2Factory is Create2Factory, IInterestRateModelV2Factory {
    /// @dev DP is 18 decimal points used for integer calculations
    uint256 public constant DP = 1e18;

    /// @dev IRM contract implementation address to clone
    address public immutable IRM;

    /// Config hash is determine by initial configuration, the logic is the same, so config is the only difference
    /// that's why we can use it as ID, at the same time we can detect duplicated and save gas by reusing same config
    /// multiple times
    mapping(bytes32 configHash => IInterestRateModelV2) public irmByConfigHash;

    constructor() {
        IRM = address(new InterestRateModelV2());
    }

    /// @inheritdoc IInterestRateModelV2Factory
    function create(IInterestRateModelV2.Config calldata _config, bytes32 _externalSalt)
        external
        virtual
        returns (bytes32 configHash, IInterestRateModelV2 irm)
    {
        configHash = hashConfig(_config);

        irm = irmByConfigHash[configHash];

        if (address(irm) != address(0)) {
            return (configHash, irm);
        }

        verifyConfig(_config);

        bytes32 salt = _salt(_externalSalt);

        address configContract = address(new InterestRateModelV2Config{salt: salt}(_config));

        irm = IInterestRateModelV2(Clones.cloneDeterministic(IRM, salt));
        IInterestRateModel(address(irm)).initialize(configContract);

        irmByConfigHash[configHash] = irm;

        emit NewInterestRateModelV2(configHash, irm);
    }

    /// @inheritdoc IInterestRateModelV2Factory
    // solhint-disable-next-line code-complexity
    function verifyConfig(IInterestRateModelV2.Config calldata _config) public view virtual {
        // Safe: `DP` is 1e18 and always fits in int256.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 dp = int256(DP);

        require(_config.uopt > 0 && _config.uopt < dp, IInterestRateModelV2.InvalidUopt());
        require(_config.ucrit > _config.uopt && _config.ucrit < dp, IInterestRateModelV2.InvalidUcrit());
        require(_config.ulow > 0 && _config.ulow < _config.uopt, IInterestRateModelV2.InvalidUlow());
        require(_config.ki >= 0, IInterestRateModelV2.InvalidKi());
        require(_config.kcrit >= 0, IInterestRateModelV2.InvalidKcrit());
        require(_config.klow >= 0, IInterestRateModelV2.InvalidKlow());
        require(_config.klin >= 0, IInterestRateModelV2.InvalidKlin());
        require(_config.beta >= 0, IInterestRateModelV2.InvalidBeta());

        require(_config.ri >= 0, IInterestRateModelV2.InvalidRi());
        require(_config.Tcrit >= 0, IInterestRateModelV2.InvalidTcrit());

        // overflow check
        InterestRateModelV2(IRM).configOverflowCheck(_config);
    }

    /// @inheritdoc IInterestRateModelV2Factory
    function hashConfig(IInterestRateModelV2.Config calldata _config)
        public
        pure
        virtual
        returns (bytes32 configId)
    {
        configId = keccak256(abi.encode(_config));
    }
}

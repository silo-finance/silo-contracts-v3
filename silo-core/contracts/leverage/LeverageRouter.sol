// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {SafeERC20} from "openzeppelin5/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {Clones} from "openzeppelin5/proxy/Clones.sol";
import {Math} from "openzeppelin5/utils/math/Math.sol";

import {ILeverageRouter} from "silo-core/contracts/interfaces/ILeverageRouter.sol";
import {ILeverageUsingSiloFlashloan} from "silo-core/contracts/interfaces/ILeverageUsingSiloFlashloan.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {RevenueModule} from "silo-core/contracts/leverage/modules/RevenueModule.sol";

import {
    LeverageUsingSiloFlashloanWithGeneralSwap
} from "silo-core/contracts/leverage/LeverageUsingSiloFlashloanWithGeneralSwap.sol";

/// @notice This contract is used to route leverage operations to the appropriate leverage contract.
contract LeverageRouter is RevenueModule {
    using SafeERC20 for IERC20;

    /// @notice The implementation of the leverage contract
    address public immutable LEVERAGE_IMPLEMENTATION;

    /// @notice Mapping of user to their leverage contract
    mapping(address user => ILeverageUsingSiloFlashloan leverageContract) public userLeverageContract;

    /// @param _initialOwner The initial owner of the contract
    /// @param _initialPauser The initial pauser of the contract
    /// @param _native The native token address
    constructor(address _initialOwner, address _initialPauser, address _native) {
        _grantRole(OWNER_ROLE, _initialOwner);
        _grantRole(PAUSER_ROLE, _initialPauser);
        _grantRole(PAUSER_ADMIN_ROLE, _initialOwner);

        LEVERAGE_IMPLEMENTATION = address(new LeverageUsingSiloFlashloanWithGeneralSwap({
            _router: address(this),
            _native: _native
        }));
    }

    /// @inheritdoc ILeverageRouter
    function openLeveragePosition(
        ILeverageUsingSiloFlashloan.FlashArgs calldata _flashArgs,
        bytes calldata _swapArgs,
        ILeverageUsingSiloFlashloan.DepositArgs calldata _depositArgs
    ) external whenNotPaused payable {
        ILeverageUsingSiloFlashloan leverageContract = _resolveLeverageContract();

        leverageContract.openLeveragePosition{value: msg.value}({
            _msgSender: msg.sender,
            _flashArgs: _flashArgs,
            _swapArgs: _swapArgs,
            _depositArgs: _depositArgs
        });
    }

    /// @inheritdoc ILeverageRouter
    function openLeveragePositionPermit(
        ILeverageUsingSiloFlashloan.FlashArgs calldata _flashArgs,
        bytes calldata _swapArgs,
        ILeverageUsingSiloFlashloan.DepositArgs calldata _depositArgs,
        ILeverageUsingSiloFlashloan.Permit calldata _depositAllowance
    ) external whenNotPaused {
        ILeverageUsingSiloFlashloan leverageContract = _resolveLeverageContract();

        leverageContract.openLeveragePositionPermit({
            _msgSender: msg.sender,
            _flashArgs: _flashArgs,
            _swapArgs: _swapArgs,
            _depositArgs: _depositArgs,
            _depositAllowance: _depositAllowance
        });
    }

    /// @inheritdoc ILeverageRouter
    function closeLeveragePosition(
        bytes calldata _swapArgs,
        ILeverageUsingSiloFlashloan.CloseLeverageArgs calldata _closeLeverageArgs
    ) external whenNotPaused {
        ILeverageUsingSiloFlashloan leverageContract = _resolveLeverageContract();

        leverageContract.closeLeveragePosition({
            _msgSender: msg.sender,
            _swapArgs: _swapArgs,
            _closeLeverageArgs: _closeLeverageArgs
        });
    }

    /// @inheritdoc ILeverageRouter
    function closeLeveragePositionPermit(
        bytes calldata _swapArgs,
        ILeverageUsingSiloFlashloan.CloseLeverageArgs calldata _closeLeverageArgs,
        ILeverageUsingSiloFlashloan.Permit calldata _withdrawAllowance
    ) external whenNotPaused {
        ILeverageUsingSiloFlashloan leverageContract = _resolveLeverageContract();

        leverageContract.closeLeveragePositionPermit({
            _msgSender: msg.sender,
            _swapArgs: _swapArgs,
            _closeLeverageArgs: _closeLeverageArgs,
            _withdrawAllowance: _withdrawAllowance
        });
    }

    /// @inheritdoc ILeverageRouter
    function predictUserLeverageContract(address _user) external view returns (address leverageContract) {
        leverageContract = Clones.predictDeterministicAddress({
            implementation: LEVERAGE_IMPLEMENTATION,
            salt: _getSalt(_user),
            deployer: address(this)
        });
    }

    /// @inheritdoc ILeverageRouter
    function calculateDebtReceiveApproval(ISilo _flashFrom, uint256 _flashAmount)
        external
        view
        returns (uint256 debtReceiveApproval)
    {
        address token = _flashFrom.asset();
        uint256 borrowAssets = _flashAmount + _flashFrom.flashFee(token, _flashAmount);
        debtReceiveApproval = _flashFrom.convertToShares(borrowAssets, ISilo.AssetType.Debt);
    }

    /// @inheritdoc ILeverageRouter
    function calculateLeverageFee(uint256 _amount) external view returns (uint256 leverageFeeAmount) {
        uint256 fee = leverageFee;
        if (fee == 0) return 0;

        leverageFeeAmount = Math.mulDiv(_amount, fee, FEE_PRECISION, Math.Rounding.Ceil);
        if (leverageFeeAmount == 0) leverageFeeAmount = 1;
    }

    /// @dev This function is used to get the leverage contract for a user.
    /// If the leverage contract does not exist, it will be created.
    /// @return leverageContract
    function _resolveLeverageContract() internal returns (ILeverageUsingSiloFlashloan leverageContract) {
        leverageContract = userLeverageContract[msg.sender];

        if (address(leverageContract) != address(0)) {
            return leverageContract;
        }

        leverageContract = ILeverageUsingSiloFlashloan(Clones.cloneDeterministic({
            implementation: LEVERAGE_IMPLEMENTATION,
            salt: _getSalt(msg.sender)
        }));

        userLeverageContract[msg.sender] = leverageContract;

        emit LeverageContractCreated(msg.sender, address(leverageContract));
    }

    /// @dev This function is used to get the salt for a user.
    function _getSalt(address _user) internal pure returns (bytes32) {
        return bytes32(bytes20(_user));
    }
}

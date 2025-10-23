// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Strings} from "openzeppelin5/utils/Strings.sol";

import {ISilo} from "../interfaces/ISilo.sol";
import {IShareToken} from "../interfaces/IShareToken.sol";
import {ISiloConfig} from "../interfaces/ISiloConfig.sol";

import {TokenHelper} from "../lib/TokenHelper.sol";
import {CallBeforeQuoteLib} from "../lib/CallBeforeQuoteLib.sol";
import {Hook} from "../lib/Hook.sol";

// solhint-disable ordering

library ShareTokenLib {
    using Hook for uint24;
    using CallBeforeQuoteLib for ISiloConfig.ConfigData;

    // keccak256(abi.encode(uint256(keccak256("silo.storage.ShareToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _STORAGE_LOCATION = 0x01b0b3f9d6e360167e522fa2b18ba597ad7b2b35841fec7e1ca4dbb0adea1200;

    function getShareTokenStorage() internal pure returns (IShareToken.ShareTokenStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := _STORAGE_LOCATION
        }
    }

    // solhint-disable-next-line func-name-mixedcase, private-vars-leading-underscore
    function __ShareToken_init(ISilo _silo, address _hookReceiver, uint24 _tokenType) external {
        IShareToken.ShareTokenStorage storage $ = ShareTokenLib.getShareTokenStorage();

        $.silo = _silo;
        $.siloConfig = _silo.config();

        $.hookSetup.hookReceiver = _hookReceiver;
        $.hookSetup.tokenType = _tokenType;
        $.transferWithChecks = true;
    }

    /// @dev decimals of share token
    function decimals() external view returns (uint8) {
        IShareToken.ShareTokenStorage storage $ = getShareTokenStorage();

        ISiloConfig.ConfigData memory configData = $.siloConfig.getConfig(address($.silo));
        return uint8(TokenHelper.assertAndGetDecimals(configData.token));
    }

    /// @dev Name convention:
    ///      NAME - asset name
    ///      SILO_ID - unique silo id
    ///
    ///      Protected deposit: "Silo Finance Non-borrowable NAME Deposit, SiloId: SILO_ID"
    ///      Borrowable deposit: "Silo Finance Borrowable NAME Deposit, SiloId: SILO_ID"
    ///      Debt: "Silo Finance NAME Debt, SiloId: SILO_ID"
    function name() external view returns (string memory) {
        IShareToken.ShareTokenStorage storage $ = getShareTokenStorage();

        ISiloConfig.ConfigData memory configData = $.siloConfig.getConfig(address($.silo));
        string memory siloIdAscii = Strings.toString($.siloConfig.SILO_ID());

        string memory pre = "";
        string memory post = " Deposit";

        if (address(this) == configData.protectedShareToken) {
            pre = "Non-borrowable ";
        } else if (address(this) == configData.collateralShareToken) {
            pre = "Borrowable ";
        } else if (address(this) == configData.debtShareToken) {
            post = " Debt";
        }

        string memory tokenSymbol = TokenHelper.symbol(configData.token);
        return string.concat("Silo Finance ", pre, tokenSymbol, post, ", SiloId: ", siloIdAscii);
    }

    /// @dev Symbol convention:
    ///      SYMBOL - asset symbol
    ///      SILO_ID - unique silo id
    ///
    ///      Protected deposit: "nbSYMBOL-SILO_ID"
    ///      Borrowable deposit: "bSYMBOL-SILO_ID"
    ///      Debt: "dSYMBOL-SILO_ID"
    function symbol() external view returns (string memory) {
        IShareToken.ShareTokenStorage storage $ = getShareTokenStorage();

        ISiloConfig.ConfigData memory configData = $.siloConfig.getConfig(address($.silo));
        string memory siloIdAscii = Strings.toString($.siloConfig.SILO_ID());

        string memory pre;

        if (address(this) == configData.protectedShareToken) {
            pre = "nb";
        } else if (address(this) == configData.collateralShareToken) {
            pre = "b";
        } else if (address(this) == configData.debtShareToken) {
            pre = "d";
        }

        string memory tokenSymbol = TokenHelper.symbol(configData.token);
        return string.concat(pre, tokenSymbol, "-", siloIdAscii);
    }

    /// @notice Call beforeQuote on solvency oracles
    /// @param _user user address for which the solvent check is performed
    function callOracleBeforeQuote(ISiloConfig _siloConfig, address _user) internal {
        (
            ISiloConfig.ConfigData memory collateralConfig,
            ISiloConfig.ConfigData memory debtConfig
        ) = _siloConfig.getConfigsForSolvency(_user);

        collateralConfig.callSolvencyOracleBeforeQuote();
        debtConfig.callSolvencyOracleBeforeQuote();
    }

    /// @dev Call on behalf of share token
    /// @param _target target address to call
    /// @param _value value to send
    /// @param _callType call type
    /// @param _input input data
    /// @return success true if the call was successful, false otherwise
    /// @return result bytes returned by the call
    function callOnBehalfOfShareToken(address _target, uint256 _value, ISilo.CallType _callType, bytes calldata _input)
        internal
        returns (bool success, bytes memory result)
    {
        // Share token will not send back any ether leftovers after the call.
        // The hook receiver should request the ether if needed in a separate call.
        if (_callType == ISilo.CallType.Delegatecall) {
            (success, result) = _target.delegatecall(_input); // solhint-disable-line avoid-low-level-calls
        } else {
            (success, result) = _target.call{value: _value}(_input); // solhint-disable-line avoid-low-level-calls
        }
    }

    /// @dev checks if operation is "real" transfer
    /// @param _sender sender address
    /// @param _recipient recipient address
    /// @return bool true if operation is real transfer, false if it is mint or burn
    function isTransfer(address _sender, address _recipient) internal pure returns (bool) {
        // in order this check to be true, it is required to have:
        // require(sender != address(0), "ERC20: transfer from the zero address");
        // require(recipient != address(0), "ERC20: transfer to the zero address");
        // on transfer. ERC20 has them, so we good.
        return _sender != address(0) && _recipient != address(0);
    }

    function siloConfig() internal view returns (ISiloConfig thisSiloConfig) {
        return ShareTokenLib.getShareTokenStorage().siloConfig;
    }

    function getConfig() internal view returns (ISiloConfig.ConfigData memory thisSiloConfigData) {
        thisSiloConfigData = ShareTokenLib.getShareTokenStorage().siloConfig.getConfig(address(this));
    }
}

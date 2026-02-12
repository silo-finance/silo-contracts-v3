// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6 <0.9.0;

import {Deployments} from "silo-foundry-utils/lib/Deployments.sol";
import {Strings} from "openzeppelin5/utils/Strings.sol";

library SiloCoreContracts {
    // smart contracts list
    string public constant SILO_FACTORY = "SiloFactory.sol";
    string public constant INTEREST_RATE_MODEL_V2_FACTORY = "InterestRateModelV2Factory.sol";
    string public constant INTEREST_RATE_MODEL_V2 = "InterestRateModelV2.sol";
    string public constant DYNAMIC_KINK_MODEL_FACTORY = "DynamicKinkModelFactory.sol";
    string public constant DYNAMIC_KINK_MODEL = "DynamicKinkModel.sol";
    string public constant SILO_HOOK_V1 = "SiloHookV1.sol";
    string public constant SILO_HOOK_V2 = "SiloHookV2.sol";
    string public constant SILO_HOOK_V3 = "SiloHookV3.sol";
    string public constant SILO_DEPLOYER = "SiloDeployer.sol";
    string public constant SILO = "Silo.sol";
    string public constant PARTIAL_LIQUIDATION = "PartialLiquidation.sol";
    string public constant PENDLE_REWARDS_CLAIMER = "PendleRewardsClaimer.sol";
    string public constant LIQUIDATION_HELPER = "LiquidationHelper.sol";
    string public constant MANUAL_LIQUIDATION_HELPER = "ManualLiquidationHelper.sol";
    string public constant TOWER = "Tower.sol";
    string public constant SHARE_PROTECTED_COLLATERAL_TOKEN = "ShareProtectedCollateralToken.sol";
    string public constant SHARE_DEBT_TOKEN = "ShareDebtToken.sol";
    string public constant SILO_LENS = "SiloLens.sol";
    string public constant LEVERAGE_ROUTER = "LeverageRouter.sol";
    string public constant SILO_ROUTER_V2 = "SiloRouterV2.sol";
    string public constant INCENTIVES_CONTROLLER_FACTORY = "SiloIncentivesControllerFactory.sol";
    string public constant GLOBAL_PAUSE = "GlobalPause.sol";
}

/// @notice SiloCoreDeployments library
/// @dev This library is used to get the deployed via deployment scripts address of the contracts.
/// Supported deployment scripts are in the `silo-core/deploy` directory except for the `silo`,
/// as it has a separate deployment script. Also, this library will not resolve the address of the
/// smart contract that was cloned during the `silo` deployment.
library SiloCoreDeployments {
    string public constant DEPLOYMENTS_DIR = "silo-core";

    function get(string memory _contract, string memory _network) internal returns (address) {
        return Deployments.getAddress(DEPLOYMENTS_DIR, _network, _contract);
    }

    function parseAddress(string memory _string) internal pure returns (address fixedAddress) {
        if (bytes(_string).length != 42) return address(0);

        bytes32 ox = keccak256(bytes("0x"));
        bytes32 twoChars = keccak256(abi.encodePacked(bytes(_string)[0], bytes(_string)[1]));

        if (ox != twoChars) return address(0);

        (bool success, uint256 value) = _tryParseHexUintUncheckedBounds(_string, 0, 42);
        if (!success) return address(0);

        return address(uint160(value));
    }

    /**
     * @dev Implementation of {tryParseHexUint} that does not check bounds. Caller should make sure that
     * `begin <= end <= input.length`. Other inputs would result in undefined behavior.
     */
    function _tryParseHexUintUncheckedBounds(string memory input, uint256 begin, uint256 end)
        private
        pure
        returns (bool success, uint256 value)
    {
        bytes memory buffer = bytes(input);

        // skip 0x prefix if present
        // don't do out-of-bound (possibly unsafe) read if sub-string is empty
        bool hasPrefix = (end > begin + 1) && bytes2(_unsafeReadBytesOffset(buffer, begin)) == bytes2("0x");
        uint256 offset = hasPrefix ? 2 : 0;

        uint256 result = 0;
        for (uint256 i = begin + offset; i < end; ++i) {
            uint8 chr = _tryParseChr(bytes1(_unsafeReadBytesOffset(buffer, i)));
            if (chr > 15) return (false, 0);
            result *= 16;
            unchecked {
                // Multiplying by 16 is equivalent to a shift of 4 bits (with additional overflow check).
                // This guaratees that adding a value < 16 will not cause an overflow, hence the unchecked.
                result += chr;
            }
        }
        return (true, result);
    }

    function _tryParseChr(bytes1 chr) private pure returns (uint8) {
        uint8 value = uint8(chr);

        // Try to parse `chr`:
        // - Case 1: [0-9]
        // - Case 2: [a-f]
        // - Case 3: [A-F]
        // - otherwise not supported
        unchecked {
            if (value > 47 && value < 58) value -= 48;
            else if (value > 96 && value < 103) value -= 87;
            else if (value > 64 && value < 71) value -= 55;
            else return type(uint8).max;
        }

        return value;
    }

    /**
     * @dev Reads a bytes32 from a bytes array without bounds checking.
     *
     * NOTE: making this function internal would mean it could be used with memory unsafe offset, and marking the
     * assembly block as such would prevent some optimizations.
     */
    function _unsafeReadBytesOffset(bytes memory buffer, uint256 offset) private pure returns (bytes32 value) {
        // This is not memory safe in the general case, but all calls to this private function are within bounds.
        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            value := mload(add(buffer, add(0x20, offset)))
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {ISilo} from "silo-core/contracts/Silo.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IERC721Receiver} from "openzeppelin5/token/ERC721/IERC721Receiver.sol";

// Libraries
import {Vm} from "forge-std/Base.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {console} from "forge-std/console.sol";
import {Strings} from "openzeppelin5/utils/Strings.sol";

// Utils
import {Actor} from "../utils/Actor.sol";
import {PropertiesConstants} from "../utils/PropertiesConstants.sol";
import {StdAsserts} from "../utils/StdAsserts.sol";

// Base
import {BaseStorage} from "./BaseStorage.t.sol";

/// @notice Base contract for all test contracts extends BaseStorage
/// @dev Provides setup modifier and cheat code setup
/// @dev inherits Storage, Testing constants assertions and utils needed for testing
abstract contract BaseTest is BaseStorage, PropertiesConstants, StdAsserts, StdUtils {
    bool internal IS_TEST = true;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   ACTOR PROXY MECHANISM                                   //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @dev Actor proxy mechanism
    modifier setupRandomActor(uint8 _i) virtual {
        targetActor = actorAddresses[_i % actorAddresses.length];
        actor = Actor(payable(targetActor));

        assertTrue(targetActor != address(0), "setupActor fail: targetActor zero");
        assertTrue(address(actor) != address(0), "setupActor fail: actor zero");

        require(targetActor != address(0), "setupActor fail: targetActor zero");
        require(address(actor) != address(0), "setupActor fail: actor zero");

        _;

        actor = Actor(payable(address(0)));
        targetActor = address(0);
    }

    /// @dev Solves medusa backward time warp issue
    modifier monotonicTimestamp() virtual {
        // Implement monotonic timestamp if needed
        _;
    }

    /// @dev Makes this Tester contract able to receive ERC721 using safeTransfer
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                     CHEAT CODE SETUP                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @dev Cheat code address, 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D.
    address internal constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));

    /// @dev Virtual machine instance
    Vm internal constant vm = Vm(VM_ADDRESS);

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          HELPERS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _maxRedeem(address silo, address user) internal view returns (uint256) {
        try ISilo(silo).maxRedeem(user) returns (uint256 maxRedeem) {
            return maxRedeem;
        } catch {
            return 0;
        }
    }

    function _maxWithdraw(address silo, address user) internal view returns (uint256) {
        try ISilo(silo).maxWithdraw(user) returns (uint256 maxWithdraw) {
            return maxWithdraw;
        } catch {
            return 0;
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          HELPERS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _hasDebt(address user) internal view returns (bool userHasDebt) {
        for (uint256 i; i < debtTokens.length; i++) {
            if (IERC20(debtTokens[i]).balanceOf(user) > 0) return true;
        }

        return false;
    }

    function _getUserAssets(address silo, address user) internal view returns (uint256) {
        (address protectedShareToken,) =
            siloConfig.getCollateralShareTokenAndAsset(silo, ISilo.CollateralType.Protected);
        (address collateralShareToken,) =
            siloConfig.getCollateralShareTokenAndAsset(silo, ISilo.CollateralType.Collateral);
        uint256 protectedShares = IERC20(protectedShareToken).balanceOf(user);
        uint256 collateralShares = IERC20(collateralShareToken).balanceOf(user);
        return ISilo(silo).convertToAssets(protectedShares, ISilo.AssetType.Protected)
            + ISilo(silo).convertToAssets(collateralShares, ISilo.AssetType.Collateral);
    }

    function _getUserProtectedAssets(address silo, address user) internal view returns (uint256) {
        (address protectedShareToken,) =
            siloConfig.getCollateralShareTokenAndAsset(silo, ISilo.CollateralType.Protected);
        uint256 protectedShares = IERC20(protectedShareToken).balanceOf(user);
        return ISilo(silo).convertToAssets(protectedShares, ISilo.AssetType.Protected);
    }

    function _setTargetActor(address user) internal {
        targetActor = user;
    }

    /// @notice Get DAO and Deployer fees
    function _getDaoAndDeployerFees(address silo) internal view returns (uint192 daoAndDeployerFees) {
        (daoAndDeployerFees,,,,) = ISilo(silo).getSiloStorage();
    }

    /// @notice Get a random address
    function _makeAddr(string memory name) internal pure returns (address addr) {
        uint256 privateKey = uint256(keccak256(abi.encodePacked(name)));
        addr = vm.addr(privateKey);
    }

    /// @notice Get a random actor proxy address
    function _getRandomActor(uint256 _i) internal view returns (address) {
        uint256 _actorIndex = _i % NUMBER_OF_ACTORS;
        return actorAddresses[_actorIndex];
    }

    function _isCustomError(bytes memory returnData, bytes4 expectedSelector) internal pure returns (bool) {
        if (returnData.length >= 4) {
            bytes4 errorSelector;
            assembly {
                errorSelector := mload(add(returnData, 32))
            }
            return errorSelector == expectedSelector;
        }
        return false;
    }

    /// @dev we assuming collateral silo is silo0
    function _getImmediateProgramNames() internal view returns (string[] memory names) {
        names = new string[](2);
        names[1] = Strings.toHexString(address(vault0));

        (address protectedShareToken,,) = siloConfig.getShareTokens(address(vault0));
        names[0] = Strings.toHexString(protectedShareToken);
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {IERC20R} from "silo-core/contracts/interfaces/IERC20R.sol";
import {SiloStorageLib} from "silo-core/contracts/lib/SiloStorageLib.sol";
import {ShareTokenLib} from "silo-core/contracts/lib/ShareTokenLib.sol";
import {ERC20RStorageLib} from "silo-core/contracts/lib/ERC20RStorageLib.sol";

interface ISomeSilo {
    function accrueInterest() external;
}

contract ConfigContract {
    function callContract(ISomeSilo _contractToCall) external {
        _contractToCall.accrueInterest();
    }
}

/*
    forge test -vv --ffi --mc StorageUpdateTest

    this test is to test obvious, that storage accessed by pointer can return modified value
*/
contract StorageUpdateTest is ISomeSilo, Test {
    uint256 internal constant _INDEX = 1;

    mapping(uint256 => uint256) internal _total;
    ConfigContract internal _config;

    function setUp() external {
        _config = new ConfigContract();
    }

    // this is
    function accrueInterest() external {
        _total[_INDEX]++;
    }

    /*
    forge test -vv --ffi --mt test_siloStoragePointer
    */
    function test_siloStoragePointer() public {
        string memory pointerSalt = "silo.storage.SiloVault";

        ISilo.SiloStorage storage siloStorage = SiloStorageLib.getSiloStorage();

        bytes32 currentPointer;

        assembly {
            currentPointer := siloStorage.slot
        }

        bytes32 expectedPointer = _getStoragePointerHash(pointerSalt);

        assertEq(currentPointer, expectedPointer, "siloStorage pointer is correct");

        emit log_named_bytes32(pointerSalt, expectedPointer);
    }

    /*
    forge test -vv --ffi --mt test_shareTokenStoragePointer
    */
    function test_shareTokenStoragePointer() public {
        string memory pointerSalt = "silo.storage.ShareToken";

        IShareToken.ShareTokenStorage storage siloStorage = ShareTokenLib.getShareTokenStorage();

        bytes32 currentPointer;

        assembly {
            currentPointer := siloStorage.slot
        }

        bytes32 expectedPointer = _getStoragePointerHash(pointerSalt);

        assertEq(currentPointer, expectedPointer, "shareToken pointer is correct");

        emit log_named_bytes32(pointerSalt, expectedPointer);
    }

    /*
    forge test -vv --ffi --mt test_ERC20RStoragePointer
    */
    function test_ERC20RStoragePointer() public {
        string memory pointerSalt = "silo.storage.ERC20R";

        IERC20R.Storage storage debtTokenStorage = ERC20RStorageLib.getIERC20RStorage();

        bytes32 currentPointer;

        assembly {
            currentPointer := debtTokenStorage.slot
        }

        bytes32 expectedPointer = _getStoragePointerHash(pointerSalt);

        assertEq(currentPointer, expectedPointer, "shareDebtToken pointer is correct");

        emit log_named_bytes32(pointerSalt, expectedPointer);
    }

    function _getStoragePointerHash(string memory _salt) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(keccak256(bytes(_salt))) - 1)) & ~bytes32(uint256(0xff));
    }
}

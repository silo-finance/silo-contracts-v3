// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Ownable} from "openzeppelin5/access/Ownable.sol";

import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";

import {AddrKey} from "common/addresses/AddrKey.sol";
import {CommonDeploy} from "./_CommonDeploy.sol";
import {SiloCoreContracts} from "silo-core/common/SiloCoreContracts.sol";
import {ISiloFactory} from "silo-core/contracts/interfaces/ISiloFactory.sol";
import {SiloFactory} from "silo-core/contracts/SiloFactory.sol";

/*
    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/SiloFactoryDeploy.s.sol \
        --ffi --rpc-url $RPC_INJECTIVE --broadcast --slow --verify 

    Resume verification:
    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/SiloFactoryDeploy.s.sol \
        --ffi --rpc-url $RPC_INJECTIVE \
        --verify \
        --verifier blockscout \
        --verifier-url $VERIFIER_URL_INJECTIVE \
        --private-key $PRIVATE_KEY \
        --resume
 */
contract SiloFactoryDeploy is CommonDeploy {
    function run() public returns (ISiloFactory siloFactory) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        address daoFeeReceiver = _getFeeReceiver();
        address owner = _getOwner();

        vm.startBroadcast(deployerPrivateKey);

        siloFactory = ISiloFactory(address(new SiloFactory(daoFeeReceiver)));
        Ownable(address(siloFactory)).transferOwnership(owner);

        vm.stopBroadcast();

        _registerDeployment(address(siloFactory), SiloCoreContracts.SILO_FACTORY);
    }

    function _getOwner() internal virtual returns (address owner) {
        owner = _isAnvil() ? _getDeployerAddress() : AddrLib.getAddressSafe(ChainsLib.chainAlias(), AddrKey.DAO);
    }

    function _getFeeReceiver() internal virtual returns (address feeReceiver) {
        feeReceiver = _isAnvil() ? _getDeployerAddress() : AddrLib.getAddressSafe(ChainsLib.chainAlias(), AddrKey.DAO);
    }

    function _isAnvil() internal virtual returns (bool isAnvil) {
        string memory chainAlias = ChainsLib.chainAlias();
        isAnvil = keccak256(abi.encodePacked(chainAlias)) == keccak256(abi.encodePacked(ChainsLib.ANVIL_ALIAS));
    }

    function _getDeployerAddress() internal virtual returns (address deployer) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        deployer = vm.addr(deployerPrivateKey);
    }
}

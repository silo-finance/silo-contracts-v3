// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";
import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";
import {VmLib} from "silo-foundry-utils/lib/VmLib.sol";

import {IDynamicKinkModel} from "silo-core/contracts/interfaces/IDynamicKinkModel.sol";

contract InterestRateModelKinkConfigData {
    // must be in alphabetic order
    struct KinkJsonConfig {
        int256 alpha;
        int256 c1;
        int256 c2;
        int256 cminus;
        int256 cplus;
        int256 dmax;
        int256 kmax;
        int256 kmin;
        int256 rmin;
        int256 u1;
        int256 u2;
        int256 ucrit;
        int256 ulow;
    }

    struct KinkConfigData {
        KinkJsonConfig config;
        string name;
    }

    function getAllConfigs() public view virtual returns (KinkConfigData[] memory) {
        return _readDataFromJson();
    }

    function getConfigData(string memory _name) 
        external 
        view 
        virtual 
        returns (IDynamicKinkModel.Config memory modelConfig) 
    {
        KinkConfigData[] memory configs = _readDataFromJson();

        for (uint256 index = 0; index < configs.length; index++) {
            if (keccak256(bytes(configs[index].name)) == keccak256(bytes(_name))) {
                modelConfig = IDynamicKinkModel.Config({
                    ulow: configs[index].config.u1,
                    u1: configs[index].config.u1,
                    u2: configs[index].config.u2,
                    ucrit: configs[index].config.ucrit,
                    rmin: configs[index].config.rmin,
                    kmin: configs[index].config.kmin,
                    kmax: configs[index].config.kmax,
                    alpha: configs[index].config.alpha,
                    cminus: configs[index].config.cminus,
                    cplus: configs[index].config.cplus,
                    c1: configs[index].config.c1,
                    c2: configs[index].config.c2,
                    dmax: configs[index].config.dmax
                });

                print(modelConfig, _name);

                return modelConfig;
            }
        }

        revert(string.concat("IRM Kink Config with name `", _name, "` not found"));
    }

    function print(IDynamicKinkModel.Config memory _configData, string memory _name) public pure virtual {
        console2.log("DynamicKinkModel.Config:", _name);
        console2.log("ulow: ", _configData.ulow);
        console2.log("u1: ", _configData.u1);
        console2.log("u2: ", _configData.u2);
        console2.log("ucrit: ", _configData.ucrit);
        console2.log("rmin: ", _configData.rmin);
        console2.log("kmin: ", _configData.kmin);
        console2.log("kmax: ", _configData.kmax);
        console2.log("alpha: ", _configData.alpha);
        console2.log("cminus: ", _configData.cminus);
        console2.log("cplus: ", _configData.cplus);
        console2.log("c1: ", _configData.c1);
        console2.log("c2: ", _configData.c2);
        console2.log("dmax: ", _configData.dmax);
    }

    function _readInput(string memory input) internal view virtual returns (string memory fileData) {
        string memory inputDir = string.concat(VmLib.vm().projectRoot(), "/silo-core/deploy/input/");
        string memory file = string.concat(input, ".json");
        fileData = VmLib.vm().readFile(string.concat(inputDir, file));
        console2.log("%s: %s bytes", file, bytes(fileData).length);
    }

    function _readDataFromJson() internal view virtual returns (KinkConfigData[] memory) {
        return abi.decode(
            VmLib.vm().parseJson(_readInput("InterestRateModelKinkConfigs"), string(abi.encodePacked("."))),
            (KinkConfigData[])
        );
    }
}

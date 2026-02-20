// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {Forking} from "./Forking.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IERC20Metadata} from "../interfaces/IERC20Metadata.sol"; // interfaces included BECAUSE OF 0.7.6

contract TokensGenerator is Forking {
    // token symbol => address
    mapping(string => IERC20) public tokens;

    // token => balance slot
    mapping(address => uint256) public balanceMappingPosition;

    constructor(BlockChain _chain) Forking(_chain) {
        if (isEthereum(_chain)) {
            tokens["WETH"] = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
            tokens["1INCH"] = IERC20(0x111111111117dC0aa78b770fA6A738034120C302);
            tokens["BAL"] = IERC20(0xba100000625a3754423978a60c9317c58a424e3D);
            tokens["cbETH"] = IERC20(0xBe9895146f7AF43049ca1c1AE358B0541Ea49704);
            tokens["gOHM"] = IERC20(0x0ab87046fBb341D058F17CBC4c1133F25a20a52f);
            tokens["OHM"] = IERC20(0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5);
            tokens["USDC"] = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
            tokens["USDT"] = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
            tokens["stETH"] = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
            tokens["wstETH"] = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
            tokens["GNO"] = IERC20(0x6810e776880C02933D47DB1b9fc05908e5386b96);
            tokens["UKY"] = IERC20(0x6f448d8687Dd8004fD73da5A938FfF57339BA8bE);
            tokens["CRV"] = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
            tokens["SP500"] = IERC20(0xd73f0826f4115E4572dbA46b3311EE13029F5D22);
            tokens["SPELL"] = IERC20(0x090185f2135308BaD17527004364eBcC2D37e5F6);
            tokens["DYDX"] = IERC20(0x92D6C1e31e14520e676a687F0a93788B716BEff5);
        } else if (isArbitrum(_chain)) {
            tokens["WETH"] = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
            tokens["UMAMI"] = IERC20(0x1622bF67e6e5747b81866fE0b85178a93C7F86e3);
            tokens["USDC"] = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
            tokens["USDT"] = IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
            tokens["TUSD"] = IERC20(0x4D15a3A2286D883AF0AA1B3f21367843FAc63E07);
            tokens["PLS"] = IERC20(0x51318B7D00db7ACc4026C88c3952B66278B6A67F);
            tokens["GRAIL"] = IERC20(0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8);
            tokens["RDPX"] = IERC20(0x32Eb7902D4134bf98A28b963D26de779AF92A212);

            balanceMappingPosition[address(tokens["USDC"])] = 51;
        }
    }

    function giveMeTokens(string calldata _tokenName, uint256 _amount) external returns (IERC20 token) {
        return giveMeTokens(_tokenName, _amount, msg.sender);
    }

    function giveMeTokens(string calldata _tokenName, uint256 _amount, address _recipient)
        public
        returns (IERC20 token)
    {
        return giveMeTokens(address(tokens[_tokenName]), _amount, _recipient);
    }

    /// @param _amount Amount without decimals
    function giveMeTokens(address _asset, uint256 _amount, address _recipient) public returns (IERC20 token) {
        token = IERC20(_asset);
        uint256 decimals = IERC20Metadata(_asset).decimals();

        giveMeExactTokens(_asset, _amount * 10 ** decimals, _recipient);
    }

    function giveMeExactTokens(address _asset, uint256 _amount, address _recipient) public returns (IERC20 token) {
        token = IERC20(_asset);
        uint256 decimals = IERC20Metadata(_asset).decimals();

        emit log_named_address("[giveMeExactTokens]", _asset);
        emit log_named_decimal_uint("balance before =>", token.balanceOf(_recipient), decimals);

        _doTokens(_asset, _amount, _recipient);

        emit log_named_decimal_uint("balance after =>", token.balanceOf(_recipient), decimals);
    }

    function _doTokens(address _asset, uint256 _amount, address _recipient) internal virtual {
        emit log_named_uint("balanceMappingPosition", balanceMappingPosition[_asset]);
        vm.store(_asset, balanceSlot(_recipient, balanceMappingPosition[_asset]), bytes32(_amount));
    }

    function balanceSlot(address _holder, uint256 _mappingPosition) internal pure returns (bytes32) {
        // mapping (address => uint256)
        return keccak256(abi.encode(_holder, _mappingPosition));
    }
}

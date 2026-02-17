// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ILiquidationHandler {
    function liquidationCall(uint256 _debtToCover, bool _receiveSToken, RandomGenerator memory _random) external;

    function liquidationCallByDefaulting(RandomGenerator memory _random)
        external
        returns (uint256 withdrawCollateral, uint256 repayDebtAssets);

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice RandomGenerator number struct to help with stack too deep errors
    struct RandomGenerator {
        uint8 i;
        uint8 j;
        uint8 k;
    }
}

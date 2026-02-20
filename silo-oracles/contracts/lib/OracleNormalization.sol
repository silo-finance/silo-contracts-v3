// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

/// @notice please read carefully unchecked comments, there are some requirements tht must be met in order to not
/// over/under flow
/// @dev Rounding error policy.
/// We're always rounding down by using build-in solidity way for division.
///
/// During normalization we're executing division by `_normalizationDivider` (unless there is multiplicator)
/// and `_secondPrice` (in case second price exist). You can expect rounding errors to be in exclusive range of (0, 1)
/// when doing division. What does it means? This means, that you can be short by up to 1 wei on result.
/// eg. when normalising 12_345 (value with 3 decimals) to 2 decimals representation you lose last digit and end result
/// will be 12_34.
/// What are consequences for protocol?
/// Eg. if 987 of tokens A is worth 12.34 tokens B (after normalization), by losing 0.005 we made tokens A worth a bit
/// more than they really are. If we would round up, then tokens A would be a bit less expensive.
/// Keep in mind we are talking tiny values. There is no argument that can tell which approach is correct.
/// Considering that prices themselves are changing constantly (if you think about it, they are just random numbers
/// close to previous value) and even TWAP price can be manipulated up to some level, if we compare this to rounding
/// error, the rounding error has no meaning at all.
/// Most important part is: how are we using prices in Silo and how rounding error affects the system?
/// We're using prices to calculate LTV. We're deciding how much of token you can borrow but once you borrow you need to
/// repay that amount (plus interest). Price of the token has no influence on how much you repay.
/// Price change by 1 wei can also trigger liquidation, but it will be like switching from eg. 9,99999999999% => 10%.
/// Summing up, rounding error can affect:
/// - max amount of tokens one can borrow
/// - when liquidation happen
/// nn both cases we are talking about 1 wei of difference and this really does not matter to the protocol.
/// It cannot make user to repay less than he borrow and it cannot affect any other operations like deposit,
/// withdraw in a way, that you get less/more tokens.
/// That said, choosing rounding policy is arbitrary decision and our decision is to use default rounding down.
library OracleNormalization {
    error Overflow();

    /// @notice if you call normalizePrice directly you can create overflow
    /// @param _baseAmount amount of base token (can not be higher than uint128!)
    /// @param _assetPrice price returned by oracle (can not be higher than uint128!)
    /// @param _normalizationDivider constant that allows to translate output price to expected decimals
    /// @param _normalizationMultiplier constant that allows to translate output price to expected decimals
    /// @return assetPrice uint256 18 decimals price
    function normalizePrice(
        uint256 _baseAmount,
        uint256 _assetPrice,
        uint256 _normalizationDivider,
        uint256 _normalizationMultiplier
    )
        internal
        pure
        returns (uint256 assetPrice)
    {
        if (_normalizationMultiplier == 0) {
            // `_baseAmount * _assetPrice` is safe because we multiply uint128 * uint128
            // - _baseAmount is checked in `_quote`
            // - _assetPrice is uint128
            // div is safe
            unchecked { return _baseAmount * _assetPrice / _normalizationDivider; }
        }

        uint256 mul;
        // this is save, check explanation above
        unchecked { mul = _baseAmount * _assetPrice; }

        return mul * _normalizationMultiplier;
    }

    /// @notice if you call normalizePrice directly you can create overflow
    /// @param _baseAmount amount of base token (can not be higher than uint128!)
    /// @param _assetPrice price returned by oracle (can not be higher than uint128!)
    /// @param _secondPrice price of quote token denominated in same token as _assetPrice
    /// (can not be higher than uint128!)
    /// @param _normalizationDivider constant that allows to translate output price to expected decimals
    /// @param _normalizationMultiplier constant that allows to translate output price to expected decimals
    /// @param _invertSecondPrice if TRUE we have to 1/secondPrice
    /// @return assetPrice uint256 18 decimals price
    function normalizePrices(
        uint256 _baseAmount,
        uint256 _assetPrice,
        uint256 _secondPrice,
        uint256 _normalizationDivider,
        uint256 _normalizationMultiplier,
        bool _invertSecondPrice
    )
        internal
        pure
        returns (uint256 assetPrice)
    {
        // `_baseAmount * _assetPrice` is safe because we multiply uint128 * uint128
        // - _baseAmount is checked in `_quote`, that checks covers `*1e8`, so we sure it is up to uint128
        // - _assetPrice is uint128
        // however if you call normalizePrice directly (because it is open method) you can create overflow
        unchecked { assetPrice = _baseAmount * _assetPrice; }

        if (_normalizationMultiplier == 0) {
            assetPrice = _invertSecondPrice ? assetPrice / _secondPrice : assetPrice * _secondPrice;
            // div is safe
            unchecked {    assetPrice = assetPrice / _normalizationDivider; }
            return assetPrice;
        }

        assetPrice = assetPrice * _normalizationMultiplier;
        return _invertSecondPrice ? assetPrice / _secondPrice : assetPrice * _secondPrice;
    }
}

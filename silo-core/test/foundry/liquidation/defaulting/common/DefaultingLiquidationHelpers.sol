// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {Ownable} from "openzeppelin5/access/Ownable.sol";
import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";
import {Strings} from "openzeppelin5/utils/Strings.sol";
import {SafeCast} from "openzeppelin5/utils/math/SafeCast.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {IPartialLiquidationByDefaulting} from "silo-core/contracts/interfaces/IPartialLiquidationByDefaulting.sol";
import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";
import {IGaugeHookReceiver} from "silo-core/contracts/interfaces/IGaugeHookReceiver.sol";
import {IDistributionManager} from "silo-core/contracts/incentives/interfaces/IDistributionManager.sol";

import {SiloLensLib} from "silo-core/contracts/lib/SiloLensLib.sol";
import {SiloIncentivesControllerCompatible} from
    "silo-core/contracts/incentives/SiloIncentivesControllerCompatible.sol";
import {RevertLib} from "silo-core/contracts/lib/RevertLib.sol";

import {DummyOracle} from "silo-core/test/foundry/_common/DummyOracle.sol";

import {SiloLittleHelper} from "../../../_common/SiloLittleHelper.sol";

abstract contract DefaultingLiquidationHelpers is SiloLittleHelper, Test {
    using SiloLensLib for ISilo;
    using SafeCast for uint256;
    using SafeCast for int256;

    struct UserState {
        uint256 colalteralShares;
        uint256 collateralAssets;
        uint256 protectedShares;
        uint256 protectedAssets;
        uint256 debtShares;
        uint256 debtAssets;
    }

    struct SiloState {
        uint256 totalCollateral;
        uint256 totalProtected;
        uint256 totalDebt;
        uint256 totalCollateralShares;
        uint256 totalProtectedShares;
        uint256 totalDebtShares;
    }

    ISiloConfig siloConfig;

    address borrower = makeAddr("borrower");
    address depositor = makeAddr("depositor");

    address[] internal depositors;

    DummyOracle oracle0;

    IPartialLiquidationByDefaulting defaulting;
    ISiloIncentivesController gauge;

    function _mockQuote(uint256 _amountIn, uint256 _price) public {
        vm.mockCall(
            address(oracle0),
            abi.encodeWithSelector(ISiloOracle.quote.selector, _amountIn, address(token0)),
            abi.encode(_price)
        );
    }

    function _removeLiquidity() internal {
        console2.log("\tremoving liquidity");
        address lpProvider = makeAddr("lpProvider");

        vm.startPrank(lpProvider);

        _tryWithdrawAll(silo0, lpProvider);

        _tryWithdrawAll(silo1, lpProvider);

        vm.stopPrank();

        (, ISilo debtSilo) = _getSilos();
        assertLe(debtSilo.getLiquidity(), 1, "[_removeLiquidity] liquidity should be ~0");
    }

    function _tryWithdrawAll(ISilo _silo, address _user) internal {
        _tryWithdrawAll(_silo, _user, ISilo.CollateralType.Collateral);
        _tryWithdrawAll(_silo, _user, ISilo.CollateralType.Protected);
    }

    function _tryWithdrawAll(ISilo _silo, address _user, ISilo.CollateralType _collateralType) internal {
        uint256 amount;

        try _silo.maxRedeem(_user, _collateralType) returns (uint256 _amount) {
            amount = _amount;
        } catch {
            console2.log("\t[_tryWithdrawAll] maxRedeem failed");
        }

        try _silo.redeem(amount, _user, _user, _collateralType) {
            // nothing to do
        } catch {
            console2.log("\t[_tryWithdrawAll] redeem failed");
        }

        // try dust
        try _silo.withdraw(1, _user, _user, _collateralType) {
            // nothing to do
        } catch {
            // nothing to do
        }
    }

    function _addLiquidity(uint256 _amount) internal {
        if (_amount == 0) return;
        console2.log("\tadding liquidity", _amount);

        address lpProvider = makeAddr("lpProvider");
        (, ISilo debtSilo) = _getSilos();
        vm.prank(lpProvider);
        debtSilo.deposit(_amount, lpProvider);

        depositors.push(lpProvider);
    }

    function _createPosition(address _borrower, uint256 _collateral, uint256 _protected, bool _maxOut)
        internal
        returns (bool success)
    {
        console2.log("\tcreating position");
        (ISilo collateralSilo,) = _getSilos();

        vm.startPrank(_borrower);
        if (_collateral != 0) collateralSilo.deposit(_collateral, _borrower);
        if (_protected != 0) collateralSilo.deposit(_protected, _borrower, ISilo.CollateralType.Protected);
        vm.stopPrank();

        depositors.push(_borrower);

        uint256 maxBorrow = _maxBorrow(_borrower);
        if (maxBorrow == 0) return false;

        success = _executeBorrow(_borrower, maxBorrow);
        if (!success) return false;

        console2.log("borrowing", maxBorrow);

        if (!_maxOut) return success;

        _tryWithdrawAll(collateralSilo, _borrower);
    }

    function _wipeOutCollateralShares(IShareToken _token, address _borrower) internal {
        uint256 balance = _token.balanceOf(_borrower);
        if (balance == 0) return;

        vm.startPrank(address(_token));
        _token.burn(_borrower, _borrower, balance);
        // _token.forwardTransferFromNoChecks(_borrower, receiver, balance);
        assertEq(_token.balanceOf(_borrower), 0, "shares must be 0 after wiping out");
        vm.stopPrank();
    }

    function _tryWithdrawMax(address _user, ISilo _silo, ISilo.CollateralType _collateralType) internal {
        uint256 amount;

        try _silo.maxRedeem(_user, _collateralType) returns (uint256 _maxWithdraw) {
            amount = _maxWithdraw;
        } catch {
            // this can happen when price change and we will get ZeroQuote
            console2.log("\tmmaxRedeem failed", vm.getLabel(address(_silo)));
        }

        if (amount == 0) return;

        vm.startPrank(_user);

        try _silo.redeem(amount, _user, _user, _collateralType) {
            // nothing to do
        } catch {
            // this can happen when price change and we will get ZeroQuote
            console2.log("\tredeem failed", vm.getLabel(address(_silo)));
        }

        vm.stopPrank();
    }

    function _printBalances(ISilo _silo, address _user) internal view {
        (address protectedShareToken, address collateralShareToken, address debtShareToken) =
            _silo.config().getShareTokens(address(_silo));

        string memory userLabel = vm.getLabel(_user);

        uint256 balance = IShareToken(collateralShareToken).balanceOf(_user);
        console2.log("%s.balanceOf(%s)", vm.getLabel(collateralShareToken), userLabel, balance);
        uint256 assets = _silo.previewRedeem(balance);
        console2.log("\tbalance to assets", assets);
        console2.log("\tback to shares", _silo.convertToShares(assets));

        balance = IShareToken(protectedShareToken).balanceOf(_user);
        console2.log("%s.balanceOf(%s)", vm.getLabel(protectedShareToken), userLabel, balance);
        assets = _silo.previewRedeem(balance, ISilo.CollateralType.Protected);
        console2.log("\tbalance to assets", assets);
        console2.log("\tback to shares", _silo.convertToShares(assets, ISilo.AssetType.Protected));

        balance = IShareToken(debtShareToken).balanceOf(_user);
        console2.log("%s.balanceOf(%s)", vm.getLabel(debtShareToken), userLabel, balance);
        console2.log("\tbalance to assets", _silo.convertToAssets(balance, ISilo.AssetType.Debt));
    }

    function _printOraclePrice(ISilo _silo) internal view {
        (ISiloConfig.ConfigData memory config) = siloConfig.getConfig(address(_silo));
        _printOraclePrice(_silo, 10 ** IERC20Metadata(config.token).decimals());
    }

    function _printOraclePrice(ISilo _silo, uint256 _amount) internal view {
        (ISiloConfig.ConfigData memory config) = siloConfig.getConfig(address(_silo));
        ISiloOracle oracle = ISiloOracle(config.solvencyOracle);

        if (address(oracle) == address(0)) {
            console2.log("no oracle configured, price is 1:1 for ", vm.getLabel(address(_silo)));
            return;
        }

        uint256 quote = oracle.quote(_amount, config.token);
        console2.log("quote(%s) = %s", _amount, quote);
    }

    function _isOracleThrowing(address _borrower) internal view returns (bool throwing, uint256 ltv) {
        try SILO_LENS.getLtv(silo0, _borrower) returns (uint256 _ltv) {
            throwing = false;
            ltv = _ltv;
        } catch {
            throwing = true;
        }
    }

    function _printLtv(address _user) internal returns (uint256 ltv) {
        try SILO_LENS.getLtv(silo0, _user) returns (uint256 _ltv) {
            ltv = _ltv;
            emit log_named_decimal_uint(string.concat(vm.getLabel(_user), " LTV [%]"), ltv, 16);
            (ISilo collateralSilo,) = _getSilos();
            uint256 lt = collateralSilo.config().getConfig(address(collateralSilo)).lt;
            emit log_named_decimal_uint(" LT [%]", lt, 16);
        } catch {
            console2.log("\t[_printLtv] getLtv failed");
        }
    }

    function _printMaxLiquidation(address _user) internal view {
        (uint256 collateralToLiquidate, uint256 debtToRepay,) = partialLiquidation.maxLiquidation(_user);
        console2.log("maxLiquidation: collateralToLiquidate", collateralToLiquidate);
        console2.log("maxLiquidation: debtToRepay", debtToRepay);
    }

    function _defaultingPossible(address _user) internal view returns (bool possible) {
        (ISilo collateralSilo,) = _getSilos();
        uint256 ltv = collateralSilo.getLtv(_user);

        return _defaultingPossible(ltv);
    }

    function _defaultingPossible(uint256 _ltv) internal view returns (bool possible) {
        uint256 margin = defaulting.LT_MARGIN_FOR_DEFAULTING();
        (ISilo collateralSilo,) = _getSilos();
        uint256 lt = collateralSilo.config().getConfig(address(collateralSilo)).lt;

        possible = _ltv > lt + margin;
    }

    function _createIncentiveController() internal returns (ISiloIncentivesController newGauge) {
        (, ISilo debtSilo) = _getSilos();
        gauge = new SiloIncentivesControllerCompatible(address(this), address(partialLiquidation), address(debtSilo));

        address owner = Ownable(address(defaulting)).owner();
        vm.prank(owner);
        IGaugeHookReceiver(address(defaulting)).setGauge(gauge, IShareToken(address(debtSilo)));
        console2.log("gauge configured");
        return gauge;
    }

    function _removeIncentiveController() internal {
        (, ISilo debtSilo) = _getSilos();

        address owner = Ownable(address(defaulting)).owner();
        vm.prank(owner);
        IGaugeHookReceiver(address(defaulting)).removeGauge(IShareToken(address(debtSilo)));
        console2.log("gauge removed");
    }

    function _getProgramIdForAddress(address _addressAsName) internal pure virtual returns (bytes32) {
        return bytes32(uint256(uint160(_addressAsName)));
    }

    function _getProgramNameForAddress(address _address) internal pure virtual returns (string memory) {
        return Strings.toHexString(_address);
    }

    function _setCollateralPrice(uint256 _price) internal {
        _setCollateralPrice(_price, true);
    }

    /// @param _price 1e18 will make collateral:debt 1:1, 2e18 will make collateral to be 2x more valuable than debt
    function _setCollateralPrice(uint256 _price, bool _printLogs) internal {
        if (_printLogs) emit log_named_decimal_uint("\t[_setCollateralPrice] setting price to", _price, 18);

        (ISilo collateralSilo,) = _getSilos();

        if (address(collateralSilo) == address(silo0)) oracle0.setPrice(_price);
        else oracle0.setPrice(_price == 0 ? 0 : 1e36 / _price);

        try oracle0.quote(10 ** token0.decimals(), address(token0)) returns (uint256 _quote) {
            if (_printLogs) emit log_named_decimal_uint("token 0 value", _quote, token1.decimals());
        } catch {
            console2.log("\t[_setCollateralPrice] quote failed");
        }
    }

    function _siloLp() internal view returns (string memory lp) {
        (ISilo collateralSilo,) = _getSilos();
        lp = address(collateralSilo) == address(silo0) ? "0" : "1";
    }

    function _printFractions(ISilo _silo) internal {
        (ISilo.Fractions memory fractions) = _silo.getFractionsStorage();

        emit log_named_decimal_uint(
            string.concat(vm.getLabel(address(_silo)), " fractions.interest"), fractions.interest, 18
        );
        emit log_named_decimal_uint(
            string.concat(vm.getLabel(address(_silo)), " fractions.revenue"), fractions.revenue, 18
        );
    }

    function _printRevenue(ISilo _silo) internal view returns (uint256 revenue, uint256 revenueFractions) {
        (revenue,,,,) = _silo.getSiloStorage();
        console2.log(vm.getLabel(address(_silo)), "revenue", revenue);

        revenueFractions = _silo.getFractionsStorage().revenue;
        console2.log(vm.getLabel(address(_silo)), "fractions.revenue", revenueFractions);
    }

    function _getBorrowerShareTokens(address _borrower)
        internal
        view
        virtual
        returns (IShareToken collateralShareToken, IShareToken protectedShareToken, IShareToken debtShareToken)
    {
        (ISiloConfig.ConfigData memory collateralConfig, ISiloConfig.ConfigData memory debtConfig) =
            siloConfig.getConfigsForSolvency(_borrower);

        require(debtConfig.silo != address(0), "NOT A BORROWER");

        protectedShareToken = IShareToken(collateralConfig.protectedShareToken);
        collateralShareToken = IShareToken(collateralConfig.collateralShareToken);
        debtShareToken = IShareToken(debtConfig.debtShareToken);
    }

    function _executeDefaulting(address _borrower) internal returns (bool success) {
        try defaulting.liquidationCallByDefaulting(_borrower) {
            success = true;
        } catch (bytes memory e) {
            if (_isControllerOverflowing(e)) {
                console2.log("immediate distribution ovverflow");
                vm.assume(false);
            }

            RevertLib.revertBytes(e, "executeDefaulting failed");
        }
    }

    function _isControllerOverflowing(bytes memory _err) internal pure returns (bool overflowing) {
        bytes4 newIndexOverflowSelector = IDistributionManager.NewIndexOverflow.selector;
        bytes4 indexOverflowSelector = IDistributionManager.IndexOverflow.selector;
        bytes4 emissionForTimeDeltaOverflowSelector = IDistributionManager.EmissionForTimeDeltaOverflow.selector;

        // Safe: extracting first 4 bytes from error bytes to compare with error selectors.
        // Error selectors are always 4 bytes, so casting is safe.
        // forge-lint: disable-next-line(unsafe-typecast)
        if (
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes4(_err) == newIndexOverflowSelector || bytes4(_err) == indexOverflowSelector
                // forge-lint: disable-next-line(unsafe-typecast)
                || bytes4(_err) == emissionForTimeDeltaOverflowSelector
        ) {
            overflowing = true;
        }
    }

    function _tryDefaulting(address _borrower) internal returns (bool success) {
        try defaulting.liquidationCallByDefaulting(_borrower) {
            success = true;
        } catch {
            success = false;
        }
    }

    function _executeMaxLiquidation(address _borrower) internal returns (bool success) {
        (address collateralAsset, address debtAsset) = _getTokens();

        try partialLiquidation.liquidationCall(collateralAsset, debtAsset, _borrower, type(uint256).max, true) {
            success = true;
        } catch {
            success = false;
        }
    }

    function _getSiloState(ISilo _silo) internal view returns (SiloState memory siloState) {
        siloState.totalCollateral = _silo.getTotalAssetsStorage(ISilo.AssetType.Collateral);
        siloState.totalProtected = _silo.getTotalAssetsStorage(ISilo.AssetType.Protected);
        siloState.totalDebt = _silo.getTotalAssetsStorage(ISilo.AssetType.Debt);

        (address protectedShareToken, address collateralShareToken, address debtShareToken) =
            siloConfig.getShareTokens(address(_silo));

        siloState.totalCollateralShares = IShareToken(collateralShareToken).totalSupply();
        siloState.totalProtectedShares = IShareToken(protectedShareToken).totalSupply();
        siloState.totalDebtShares = IShareToken(debtShareToken).totalSupply();
    }

    function _printSiloState(ISilo _silo) internal view {
        SiloState memory siloState = _getSiloState(_silo);
        console2.log("-------- %s silo state --------", vm.getLabel(address(_silo)));
        console2.log("total collateral", siloState.totalCollateral);
        console2.log("total protected", siloState.totalProtected);
        console2.log("total debt", siloState.totalDebt);
        console2.log("total collateral shares", siloState.totalCollateralShares);
        console2.log("total protected shares", siloState.totalProtectedShares);
        console2.log("total debt shares", siloState.totalDebtShares);
        console2.log("-------- end --------");
    }

    function _getUserState(ISilo _silo, address _user) internal view returns (UserState memory userState) {
        (address protectedShareToken, address collateralShareToken, address debtShareToken) =
            siloConfig.getShareTokens(address(_silo));

        userState.debtShares = IShareToken(debtShareToken).balanceOf(_user);
        userState.protectedShares = IShareToken(protectedShareToken).balanceOf(_user);
        userState.colalteralShares = IShareToken(collateralShareToken).balanceOf(_user);

        userState.collateralAssets = _silo.previewRedeem(userState.colalteralShares);
        userState.protectedAssets = _silo.previewRedeem(userState.protectedShares, ISilo.CollateralType.Protected);
        userState.debtAssets = _silo.maxRepay(_user);
    }

    function _calculateNewPrice(uint64 _initialPrice, int64 _changePricePercentage)
        internal
        pure
        returns (uint64 newPrice)
    {
        _changePricePercentage %= 1e18;

        int256 diff = uint256(_initialPrice).toInt256() * _changePricePercentage / 1e18;
        int256 sum = uint256(_initialPrice).toInt256() + diff;
        newPrice = sum.toUint256().toUint64();
    }

    /// @dev make sure it does not throw!
    function _maxBorrow(address _borrower) internal view returns (uint256) {
        (, ISilo debtSilo) = _getSilos();

        try debtSilo.maxBorrow(_borrower) returns (uint256 _max) {
            return _max;
        } catch {
            return 0;
        }
    }

    function _moveUntillDefaultingPossible(address _borrower, uint64 _priceDrop, uint64 _warp) internal {
        uint256 price = oracle0.price();
        (bool throwing, uint256 ltv) = _isOracleThrowing(_borrower);

        while (!_defaultingPossible(ltv)) {
            vm.assume(price > _priceDrop);

            price -= _priceDrop;
            _setCollateralPrice(price, false);
            vm.warp(block.timestamp + _warp);

            (throwing, ltv) = _isOracleThrowing(_borrower);
            vm.assume(!throwing);
        }

        _printLtv(_borrower);
        emit log_named_decimal_uint("price", oracle0.price(), 18);
    }

    function _moveUntillBadDebt(address _borrower, uint64 _priceDrop, uint64 _warp) internal {
        console2.log("\t[_moveUntillBadDebt] moving until bad debt");
        uint256 price = oracle0.price();
        (bool throwing, uint256 ltv) = _isOracleThrowing(_borrower);

        while (ltv < 1e18) {
            vm.assume(price > _priceDrop);
            price -= _priceDrop;
            _setCollateralPrice(price, false);
            vm.warp(block.timestamp + _warp);

            (throwing, ltv) = _isOracleThrowing(_borrower);
            vm.assume(!throwing);
        }

        _printLtv(_borrower);
        emit log_named_decimal_uint("price", oracle0.price(), 18);
    }

    function _printDepositors() internal view {
        for (uint256 i; i < depositors.length; i++) {
            console2.log("depositor", i, ":", vm.getLabel(depositors[i]));
        }
    }

    // CONFIGURATION

    function _useConfigName() internal view virtual returns (string memory);

    function _getSilos() internal view virtual returns (ISilo collateralSilo, ISilo debtSilo);

    function _getTokens() internal view virtual returns (address collateralAsset, address debtAsset);

    function _executeBorrow(address _borrower, uint256 _amount) internal virtual returns (bool success);
}

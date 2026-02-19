// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

contract LiquidationPreviewTestData {
    struct Input {
        uint256 lt;
        uint256 liquidationTargetLtv;
        uint256 maxDebtToCover;
        uint256 totalBorrowerDebtValue;
        uint256 totalBorrowerDebtAssets;
        uint256 totalBorrowerCollateralValue;
        uint256 totalBorrowerCollateralAssets;
        uint256 liquidationFee;
    }

    struct Output {
        uint256 collateralAssetsToLiquidate;
        uint256 debtAssetsToRepay;
        uint256 ltvAfterLiquidation;
    }

    struct CelaData {
        Input input;
        Output output;
    }

    function readDataFromJson() external pure returns (CelaData[] memory data) {
        data = new CelaData[](13 + 80);
        uint256 i;

        data[i++] = CelaData({ // #0
            input: Input({
                lt: 1,
                liquidationTargetLtv: 0,
                maxDebtToCover: 0,
                totalBorrowerDebtValue: 1,
                totalBorrowerDebtAssets: 1,
                totalBorrowerCollateralValue: 1,
                totalBorrowerCollateralAssets: 1,
                liquidationFee: 0
            }),
            output: Output({ // FULL liquidation forced
                collateralAssetsToLiquidate: 0,
                debtAssetsToRepay: 0,
                ltvAfterLiquidation: 1e18
            })
        });

        data[i++] = CelaData({ // #1
            input: Input({
                lt: 1,
                liquidationTargetLtv: 0,
                maxDebtToCover: 0,
                totalBorrowerDebtValue: 1,
                totalBorrowerDebtAssets: 1,
                totalBorrowerCollateralValue: 1,
                totalBorrowerCollateralAssets: 1,
                liquidationFee: 0.1e18
            }),
            output: Output({collateralAssetsToLiquidate: 0, debtAssetsToRepay: 0, ltvAfterLiquidation: 1e18})
        });

        data[i++] = CelaData({ // #2
            input: Input({
                lt: 0.79e18,
                liquidationTargetLtv: 0.79e18 * 0.9e18 / 1e18,
                maxDebtToCover: 0,
                totalBorrowerDebtValue: 1e18,
                totalBorrowerDebtAssets: 1e18,
                totalBorrowerCollateralValue: 100e18,
                totalBorrowerCollateralAssets: 100e18,
                liquidationFee: 0.1e18
            }),
            output: Output({collateralAssetsToLiquidate: 0, debtAssetsToRepay: 0, ltvAfterLiquidation: 0.01e18})
        });

        data[i++] = CelaData({ // #3
            input: Input({
                lt: 0.0099e18,
                liquidationTargetLtv: 0.0099e18 * 0.9e18 / 1e18,
                maxDebtToCover: 1,
                totalBorrowerDebtValue: 1e18,
                totalBorrowerDebtAssets: 1e18,
                totalBorrowerCollateralValue: 100e18,
                totalBorrowerCollateralAssets: 100e18,
                liquidationFee: 0.1e18
            }),
            output: Output({
                collateralAssetsToLiquidate: 1,
                debtAssetsToRepay: 1,
                ltvAfterLiquidation: 0.01e18 // (1e18 - 1) / (100e18 - 1)
            })
        });

        data[i++] = CelaData({ // #4
            input: Input({
                lt: 0.01e18,
                liquidationTargetLtv: 0.01e18 * 0.9e18 / 1e18,
                maxDebtToCover: 100,
                totalBorrowerDebtValue: 1e18,
                totalBorrowerDebtAssets: 1e18,
                totalBorrowerCollateralValue: 100e18,
                totalBorrowerCollateralAssets: 100e18,
                liquidationFee: 0.01e18 // 1%
            }),
            output: Output({
                collateralAssetsToLiquidate: 101, // 100 debt to cover produces 1 fee
                debtAssetsToRepay: 100,
                // (one - 100n) * one / (100n * one - 101n) => +1 round up
                ltvAfterLiquidation: 0.009999999999999999e18 + 1
            })
        });

        data[i++] = CelaData({ // #5
            input: Input({
                lt: 0.8e18,
                liquidationTargetLtv: 0.8e18 * 0.9e18 / 1e18,
                maxDebtToCover: 0.5e18, // the value is 40e18 + fee => 44e18 in value
                totalBorrowerDebtValue: 80e18,
                totalBorrowerDebtAssets: 1e18,
                totalBorrowerCollateralValue: 100e18,
                totalBorrowerCollateralAssets: 10e18,
                liquidationFee: 0.1e18
            }),
            output: Output({
                collateralAssetsToLiquidate: 4230769230769230767,
                debtAssetsToRepay: 480769230769230769,
                // (one - 480769230769230769n) * 80n * one / ((10n * one - 4230769230769230767n) * 10n)
                ltvAfterLiquidation: 720000000000000000 + 1 // this is minimal acceptable LTV
            })
        });

        // this is just before full liquidation because of "dust"
        data[i++] = CelaData({ // #6
            input: Input({
                lt: 0.001e18,
                liquidationTargetLtv: 0.001e18 * 0.9e18 / 1e18,
                maxDebtToCover: 0.9e18, // the value is 72e18 + fee => 79.2e18 in value
                totalBorrowerDebtValue: 80e18,
                totalBorrowerDebtAssets: 1e18,
                totalBorrowerCollateralValue: 9_000e18,
                totalBorrowerCollateralAssets: 10e18,
                liquidationFee: 0.1e18
            }),
            output: Output({
                collateralAssetsToLiquidate: 87964862992139996, // 79.2e18 / 900 => 0.88,
                debtAssetsToRepay: 0.899640644237795417e18,
                // (one - 899640644237795417n) * 80n * one / ((10n * one - 87964862992139996n) * 900n) = 900000000000000n
                ltvAfterLiquidation: 0.0009e18 + 1
            })
        });

        // this will do full liquidation because of dust
        // input values are made up and looks like we have huge collateral
        data[i++] = CelaData({ // #7
            input: Input({
                lt: 0.0088e18,
                liquidationTargetLtv: 0.0088e18 * 0.9e18 / 1e18,
                maxDebtToCover: 0.91e18, // the value is 72.8e18, but this is too much anyway, it will be lowered by math
                totalBorrowerDebtValue: 80e18,
                totalBorrowerDebtAssets: 1e18, // 1debt token == 80 in value
                totalBorrowerCollateralValue: 9_000e18,
                totalBorrowerCollateralAssets: 10e18, // 1token == 900 in value
                liquidationFee: 0.01e18
            }),
            output: Output({
                collateralAssetsToLiquidate: 9864687385108739,
                debtAssetsToRepay: 109878943646013188,
                ltvAfterLiquidation: 7920000000000000 + 1 // +1 rounding up
            })
        });

        // this will do full liquidation because of dust
        // input values are made up and looks like we have huge collateral
        data[i++] = CelaData({ // #8
            input: Input({
                lt: 0.08e18,
                liquidationTargetLtv: 0.08e18 * 0.9e18 / 1e18,
                maxDebtToCover: 0.91e18, // the value is 72.8e18, but this is over "dust" margin, so it will be full
                totalBorrowerDebtValue: 80e18,
                totalBorrowerDebtAssets: 1e18, // 1debt token == 80 in value
                totalBorrowerCollateralValue: 90e18,
                totalBorrowerCollateralAssets: 10e18, // 1token == 9 in value
                liquidationFee: 0.01e18
            }),
            output: Output({
                collateralAssetsToLiquidate: uint256(80e18 + 80e18 * 0.01e18 / 1e18) / 9,
                debtAssetsToRepay: 1e18,
                ltvAfterLiquidation: 0
            })
        });

        // if we expect ltv to be 0, we need full liquidation
        data[i++] = CelaData({ // #9
            input: Input({
                lt: 0.08e18,
                liquidationTargetLtv: 0.08e18 * 0.9e18 / 1e18,
                maxDebtToCover: 160e18,
                totalBorrowerDebtValue: 80e18,
                totalBorrowerDebtAssets: 160e18,
                totalBorrowerCollateralValue: 100e18,
                totalBorrowerCollateralAssets: 300e18,
                liquidationFee: 0.05e18
            }),
            output: Output({
                collateralAssetsToLiquidate: (80e18 + 80e18 * 0.05e18 / 1e18) * 3, // 252...
                debtAssetsToRepay: 160e18,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #10
            input: Input({
                lt: 0.08e18,
                liquidationTargetLtv: 0.08e18 * 0.9e18 / 1e18,
                maxDebtToCover: 10e18,
                totalBorrowerDebtValue: 180e18,
                totalBorrowerDebtAssets: 180e18,
                totalBorrowerCollateralValue: 100e18,
                totalBorrowerCollateralAssets: 100e18,
                liquidationFee: 0.1e18
            }),
            output: Output({
                collateralAssetsToLiquidate: (10e18 + 10e18 * 0.1e18 / 1e18),
                debtAssetsToRepay: 10e18,
                ltvAfterLiquidation: 1_9101_12359550561797 + 1 // +1 rounding up
            })
        });

        // we have bad debt and we will cover everything
        data[i++] = CelaData({ // #11
            input: Input({
                lt: 0.99e18,
                liquidationTargetLtv: 0.99e18 * 0.9e18 / 1e18,
                maxDebtToCover: 100e18,
                totalBorrowerDebtValue: 12e18,
                totalBorrowerDebtAssets: 12e18,
                totalBorrowerCollateralValue: 10e18,
                totalBorrowerCollateralAssets: 10e18,
                liquidationFee: 0.1e18
            }),
            output: Output({collateralAssetsToLiquidate: 10e18, debtAssetsToRepay: 12e18, ltvAfterLiquidation: 0})
        });

        // we have bad debt and we will cover everything #2
        data[i++] = CelaData({ // #12
            input: Input({
                lt: 0.99e18,
                liquidationTargetLtv: 0.99e18 * 0.9e18 / 1e18,
                maxDebtToCover: 1000000e18,
                totalBorrowerDebtValue: 12e18,
                totalBorrowerDebtAssets: 18e18,
                totalBorrowerCollateralValue: 10e18,
                totalBorrowerCollateralAssets: 30e18,
                liquidationFee: 0.1e18
            }),
            output: Output({collateralAssetsToLiquidate: 30e18, debtAssetsToRepay: 18e18, ltvAfterLiquidation: 0})
        });

        data[i++] = CelaData({ // #13
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 4185933374737666667897428,
                totalBorrowerDebtValue: 98470419191262037461598,
                totalBorrowerDebtAssets: 4121906141171121978010239,
                totalBorrowerCollateralValue: 89719182306882854269146,
                totalBorrowerCollateralAssets: 4434679989760590172656519,
                liquidationFee: 50000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 4434679989760590172656519,
                debtAssetsToRepay: 4121906141171121978010239,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #14
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 15136995372322309094670345,
                totalBorrowerDebtValue: 93891752638554688559224,
                totalBorrowerDebtAssets: 14212390251890332752798319,
                totalBorrowerCollateralValue: 104675808475317926140869,
                totalBorrowerCollateralAssets: 3667047907474247305336338,
                liquidationFee: 50000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 2792749271687079546301119,
                debtAssetsToRepay: 11492435273764137171865237,
                ltvAfterLiquidation: 720000000000000000
            })
        });

        data[i++] = CelaData({ // #15
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 8203005421702417265805706,
                totalBorrowerDebtValue: 109939283508532559263670,
                totalBorrowerDebtAssets: 9018325386785717343215963,
                totalBorrowerCollateralValue: 117402156303999529983246,
                totalBorrowerCollateralAssets: 14607236495680146347716196,
                liquidationFee: 50000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 14362637136981253300362874,
                debtAssetsToRepay: 9018325386785717343215963,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #16
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 396367617728182963787730,
                totalBorrowerDebtValue: 99076083386778603934175,
                totalBorrowerDebtAssets: 392705511458562405890406,
                totalBorrowerCollateralValue: 116962049842580274798296,
                totalBorrowerCollateralAssets: 33782676126579387026193071,
                liquidationFee: 50000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 18474255093756855404628954,
                debtAssetsToRepay: 241449730415823411607967,
                ltvAfterLiquidation: 720000000000000000
            })
        });

        data[i++] = CelaData({ // #17
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 3891190661660105831742839,
                totalBorrowerDebtValue: 100632444742786639757525,
                totalBorrowerDebtAssets: 3915800292431579833773081,
                totalBorrowerCollateralValue: 125734663188080803566575,
                totalBorrowerCollateralAssets: 29709855228855023121911127,
                liquidationFee: 50000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 10273449327492703514847604,
                debtAssetsToRepay: 1611253902752546059828057,
                ltvAfterLiquidation: 720000000000000000
            })
        });

        data[i++] = CelaData({ // #18
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 70042348699871581629849,
                totalBorrowerDebtValue: 101570817467000922285080,
                totalBorrowerDebtAssets: 71142586147546857830793,
                totalBorrowerCollateralValue: 93684558953014734352121,
                totalBorrowerCollateralAssets: 23627107864032942440296054,
                liquidationFee: 50000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 23627107864032942440296054,
                debtAssetsToRepay: 70042348699871581629849,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #19
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 5427015907056814114639564,
                totalBorrowerDebtValue: 95192134557187675358846,
                totalBorrowerDebtAssets: 5166092284685501722023312,
                totalBorrowerCollateralValue: 95032136977325206130897,
                totalBorrowerCollateralAssets: 20794615933760135161451533,
                liquidationFee: 50000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 20794615933760135161451533,
                debtAssetsToRepay: 5166092284685501722023312,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #20
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 142613006097347394529606,
                totalBorrowerDebtValue: 97215385566907985825935,
                totalBorrowerDebtAssets: 138641783746094264771715,
                totalBorrowerCollateralValue: 114888605310591338680764,
                totalBorrowerCollateralAssets: 439671675432065603185000,
                liquidationFee: 50000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 238718948463517172820532,
                debtAssetsToRepay: 84723755264071880164120,
                ltvAfterLiquidation: 720000000000000000
            })
        });

        data[i++] = CelaData({ // #21
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 5294849541834204842416511,
                totalBorrowerDebtValue: 107739492052498573304575,
                totalBorrowerDebtAssets: 5704644001316220247545749,
                totalBorrowerCollateralValue: 117050382090863690211212,
                totalBorrowerCollateralAssets: 33102782004864500785680605,
                liquidationFee: 50000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 28554771372480184033083279,
                debtAssetsToRepay: 5091565717302692707653874,
                ltvAfterLiquidation: 720000000000000000
            })
        });

        data[i++] = CelaData({ // #22
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 1815341461263484390542544,
                totalBorrowerDebtValue: 99751622913476938325771,
                totalBorrowerDebtAssets: 1810832569031552973791008,
                totalBorrowerCollateralValue: 108539587868285257983189,
                totalBorrowerCollateralAssets: 20042373733942654037141115,
                liquidationFee: 50000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 17166309238095333629222610,
                debtAssetsToRepay: 1607255688123597739928315,
                ltvAfterLiquidation: 720000000000000000
            })
        });

        data[i++] = CelaData({ // #23
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 4080998175340533862254233,
                totalBorrowerDebtValue: 105903462601967803813352,
                totalBorrowerDebtAssets: 4321918376408750739169924,
                totalBorrowerCollateralValue: 118284945656865795716327,
                totalBorrowerCollateralAssets: 16799289344132673806241712,
                liquidationFee: 50000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 12674595183626450396174949,
                debtAssetsToRepay: 3468564406385661516716527,
                ltvAfterLiquidation: 720000000000000001
            })
        });

        data[i++] = CelaData({ // #24
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 9111251064757253459447383,
                totalBorrowerDebtValue: 109265205955114801383842,
                totalBorrowerDebtAssets: 9955427240994603255574284,
                totalBorrowerCollateralValue: 112393469206256181230875,
                totalBorrowerCollateralAssets: 5485444991783190680618326,
                liquidationFee: 50000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 5485444991783190680618326,
                debtAssetsToRepay: 9955427240994603255574284,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #25
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 507789778793133805834258,
                totalBorrowerDebtValue: 103829061300628620045927,
                totalBorrowerDebtAssets: 527233360701449367791338,
                totalBorrowerCollateralValue: 102079216735432025032898,
                totalBorrowerCollateralAssets: 26619632581653035882865567,
                liquidationFee: 50000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 26619632581653035882865567,
                debtAssetsToRepay: 507789778793133805834258,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #26
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 8554201407720600514039688,
                totalBorrowerDebtValue: 100515136517980461228205,
                totalBorrowerDebtAssets: 8598267222993368012804507,
                totalBorrowerCollateralValue: 122767846937508994413025,
                totalBorrowerCollateralAssets: 13406385352727811734986438,
                liquidationFee: 50000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 5696539116320879174943871,
                debtAssetsToRepay: 4249855825838393848398907,
                ltvAfterLiquidation: 720000000000000001
            })
        });

        data[i++] = CelaData({ // #27
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 10394412948740608726438949,
                totalBorrowerDebtValue: 96765876452064343293812,
                totalBorrowerDebtAssets: 10058244791895715637842384,
                totalBorrowerCollateralValue: 95111509633203898444529,
                totalBorrowerCollateralAssets: 27865179407636837214031853,
                liquidationFee: 50000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 27865179407636837214031853,
                debtAssetsToRepay: 10058244791895715637842384,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #28
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 6806564344654185561012127,
                totalBorrowerDebtValue: 102794293327104047097719,
                totalBorrowerDebtAssets: 6996759717941900782024729,
                totalBorrowerCollateralValue: 94030342760705544884383,
                totalBorrowerCollateralAssets: 1634140677332202109462743,
                liquidationFee: 50000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 1634140677332202109462743,
                debtAssetsToRepay: 6806564344654185561012127,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #29
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 587825869069646955722419,
                totalBorrowerDebtValue: 109117355002517895101732,
                totalBorrowerDebtAssets: 641420040349362704686345,
                totalBorrowerCollateralValue: 115276637548635499832647,
                totalBorrowerCollateralAssets: 19760337903417219712147278,
                liquidationFee: 50000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 19639760878005673042696267,
                debtAssetsToRepay: 641420040349362704686345,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #30
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 8335224951030141937735606,
                totalBorrowerDebtValue: 96739667903972552664981,
                totalBorrowerDebtAssets: 8063468936675618140388424,
                totalBorrowerCollateralValue: 92213659938481397884165,
                totalBorrowerCollateralAssets: 8592242605859240271846193,
                liquidationFee: 50000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 8592242605859240271846193,
                debtAssetsToRepay: 8063468936675618140388424,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #31
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 380813424122191435117201,
                totalBorrowerDebtValue: 102819773569249688360827,
                totalBorrowerDebtAssets: 391551500403743706264718,
                totalBorrowerCollateralValue: 104884795992161021166905,
                totalBorrowerCollateralAssets: 17389695005329493820181613,
                liquidationFee: 50000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 17389695005329493820181613,
                debtAssetsToRepay: 391551500403743706264718,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #32
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 10347987967793677910322003,
                totalBorrowerDebtValue: 94417193323453028064307,
                totalBorrowerDebtAssets: 9770279804639415139945898,
                totalBorrowerCollateralValue: 100924378752437340485397,
                totalBorrowerCollateralAssets: 20985149809692535842274339,
                liquidationFee: 50000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 20613720089689323026511389,
                debtAssetsToRepay: 9770279804639415139945898,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #33
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 2494451606075465000000000000000000000000000,
                totalBorrowerDebtValue: 10777542949187085552509302033,
                totalBorrowerDebtAssets: 2688405931914702922957662919808963231105281,
                totalBorrowerCollateralValue: 11588929393892305231123928288,
                totalBorrowerCollateralAssets: 66607019326270063298725056527436778169,
                liquidationFee: 190000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 66607019326270063298725056527436778169,
                debtAssetsToRepay: 2688405931914702922957662919808963231105281,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #34
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 4080617115696630625000000000000000000000000,
                totalBorrowerDebtValue: 9801469373958160202775502511,
                totalBorrowerDebtAssets: 3999604368635000755325641791885923903571153,
                totalBorrowerCollateralValue: 10471605951978711023425816083,
                totalBorrowerCollateralAssets: 51753504094026402459720861430511861172,
                liquidationFee: 190000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 51753504094026402459720861430511861172,
                debtAssetsToRepay: 3999604368635000755325641791885923903571153,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #35
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 3834725228379809375000000000000000000000000,
                totalBorrowerDebtValue: 10817623799524070049571378149,
                totalBorrowerDebtAssets: 4148261489515680074661293671870535004764235,
                totalBorrowerCollateralValue: 10138346971099997633776177158,
                totalBorrowerCollateralAssets: 68549736976435311575835376296134982143,
                liquidationFee: 190000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 68549736976435311575835376296134982143,
                debtAssetsToRepay: 3834725228379809375000000000000000000000000,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #36
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 1453788720771260625000000000000000000000000,
                totalBorrowerDebtValue: 9355835619319498697166181955,
                totalBorrowerDebtAssets: 1360140829675668890914850993187845684673220,
                totalBorrowerCollateralValue: 8741925449271605031388951295,
                totalBorrowerCollateralAssets: 9223123477157569041524975439001828781,
                liquidationFee: 190000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 9223123477157569041524975439001828781,
                debtAssetsToRepay: 1360140829675668890914850993187845684673220,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #37
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 2371095715255704375000000000000000000000000,
                totalBorrowerDebtValue: 10632316262532036432730819797,
                totalBorrowerDebtAssets: 2521023953333325642058502286295240679692142,
                totalBorrowerCollateralValue: 11790575389463036979401301650,
                totalBorrowerCollateralAssets: 77872520427184919000970567225026396098,
                liquidationFee: 190000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 77872520427184919000970567225026396098,
                debtAssetsToRepay: 2521023953333325642058502286295240679692142,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #38
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 1569472744380517812500000000000000000000000,
                totalBorrowerDebtValue: 10532452835729102513795396589,
                totalBorrowerDebtAssets: 1653039765715012167629481887111894677921952,
                totalBorrowerCollateralValue: 10341242564080690324900439972,
                totalBorrowerCollateralAssets: 55578270070862625598133033952563803614,
                liquidationFee: 190000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 55578270070862625598133033952563803614,
                debtAssetsToRepay: 1569472744380517812500000000000000000000000,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #39
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 9702659829150145000000000000000000000000000,
                totalBorrowerDebtValue: 9385988626087641062412103565,
                totalBorrowerDebtAssets: 9106905479920071563190072797367546897362444,
                totalBorrowerCollateralValue: 10744870070677152449726642983,
                totalBorrowerCollateralAssets: 83700059957719875167609564126434202426,
                liquidationFee: 190000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 83700059957719875167609564126434202426,
                debtAssetsToRepay: 9106905479920071563190072797367546897362444,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #40
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 8150722248587482500000000000000000000000000,
                totalBorrowerDebtValue: 10747478431808425769489190315,
                totalBorrowerDebtAssets: 8759971157035504229104695659342383340373316,
                totalBorrowerCollateralValue: 11795198288027029149710665188,
                totalBorrowerCollateralAssets: 18647349792078964104048684690592994977,
                liquidationFee: 190000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 18647349792078964104048684690592994977,
                debtAssetsToRepay: 8759971157035504229104695659342383340373316,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #41
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 6755730445470797500000000000000000000000000,
                totalBorrowerDebtValue: 9103578872845471181562970741,
                totalBorrowerDebtAssets: 6150132495402687561604354984262421623952832,
                totalBorrowerCollateralValue: 10235181330661614461311200033,
                totalBorrowerCollateralAssets: 19280929449578435157186340434812521694,
                liquidationFee: 190000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 19280929449578435157186340434812521694,
                debtAssetsToRepay: 6150132495402687561604354984262421623952832,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #42
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 6907793548175125000000000000000000000000000,
                totalBorrowerDebtValue: 10164231652281544793225975809,
                totalBorrowerDebtAssets: 7021241382978784567022519533158186888499585,
                totalBorrowerCollateralValue: 10074454173477097700278197173,
                totalBorrowerCollateralAssets: 13358839305368785489402715513483834255,
                liquidationFee: 190000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 13358839305368785489402715513483834255,
                debtAssetsToRepay: 6907793548175125000000000000000000000000000,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #43
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 2555578177655312187500000000000000000000000,
                totalBorrowerDebtValue: 9223531545277442234009868116,
                totalBorrowerDebtAssets: 2357145593802641141702476212497319174588028,
                totalBorrowerCollateralValue: 11445424941421886786778484422,
                totalBorrowerCollateralAssets: 108789028978610801783527210704660711387,
                liquidationFee: 190000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 77630713327855247962426662945558607094,
                debtAssetsToRepay: 1753971804286240760538306164372228708654753,
                ltvAfterLiquidation: 720000000000000001
            })
        });

        data[i++] = CelaData({ // #44
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 2465235498585760625000000000000000000000000,
                totalBorrowerDebtValue: 10014943206123178232047621349,
                totalBorrowerDebtAssets: 2468919350805514932998289408647735188040428,
                totalBorrowerCollateralValue: 9141535520755619477865975264,
                totalBorrowerCollateralAssets: 40072706346584673831917373300232732537,
                liquidationFee: 190000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 40072706346584673831917373300232732537,
                debtAssetsToRepay: 2465235498585760625000000000000000000000000,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #45
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 3313838733226953750000000000000000000000000,
                totalBorrowerDebtValue: 9778687623596406863768493167,
                totalBorrowerDebtAssets: 3240499380720080765103688002710030646724703,
                totalBorrowerCollateralValue: 9148110857987873873864565537,
                totalBorrowerCollateralAssets: 8303709643573853098356542485428584330,
                liquidationFee: 190000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 8303709643573853098356542485428584330,
                debtAssetsToRepay: 3240499380720080765103688002710030646724703,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #46
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 3057500499808436250000000000000000000000000,
                totalBorrowerDebtValue: 10655659835279061908863695862,
                totalBorrowerDebtAssets: 3257968527215441126911126513489458389472019,
                totalBorrowerCollateralValue: 10239427149181309250279137519,
                totalBorrowerCollateralAssets: 5731561783481081236895056453139855514,
                liquidationFee: 190000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 5731561783481081236895056453139855514,
                debtAssetsToRepay: 3057500499808436250000000000000000000000000,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #47
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 4144814816329114375000000000000000000000000,
                totalBorrowerDebtValue: 10040509557812011598443291404,
                totalBorrowerDebtAssets: 4161605277871331024379242331468722881915311,
                totalBorrowerCollateralValue: 9520097437644565567920791916,
                totalBorrowerCollateralAssets: 70062528955888583881595207227908668694,
                liquidationFee: 190000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 70062528955888583881595207227908668694,
                debtAssetsToRepay: 4144814816329114375000000000000000000000000,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #48
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 2813621130807759687500000000000000000000000,
                totalBorrowerDebtValue: 9290155256537773853509065702,
                totalBorrowerDebtAssets: 2613897713827946406424206644663908727377332,
                totalBorrowerCollateralValue: 10649411692115654426546523349,
                totalBorrowerCollateralAssets: 29650879736599592995102207896295930049,
                liquidationFee: 190000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 29650879736599592995102207896295930049,
                debtAssetsToRepay: 2613897713827946406424206644663908727377332,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #49
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 534539576480178593750000000000000000000000,
                totalBorrowerDebtValue: 9063428520286519685100756760,
                totalBorrowerDebtAssets: 484476124269232799241423640536102768194837,
                totalBorrowerCollateralValue: 9748873585468944999856290730,
                totalBorrowerCollateralAssets: 41617088336868895801214546135476462430,
                liquidationFee: 190000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 41617088336868895801214546135476462430,
                debtAssetsToRepay: 484476124269232799241423640536102768194837,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #50
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 7705304720825547500000000000000000000000000,
                totalBorrowerDebtValue: 10887216180596171577477093705,
                totalBorrowerDebtAssets: 8388931823299596736971481377981685323419469,
                totalBorrowerCollateralValue: 9982292228605336398124470991,
                totalBorrowerCollateralAssets: 57050392392918900105988220476686491132,
                liquidationFee: 190000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 57050392392918900105988220476686491132,
                debtAssetsToRepay: 7705304720825547500000000000000000000000000,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #51
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 3497951059007123750000000000000000000000000,
                totalBorrowerDebtValue: 9186634990590203386773282545,
                totalBorrowerDebtAssets: 3213439959404690026280320723472971877754389,
                totalBorrowerCollateralValue: 10319988874060337112370638164,
                totalBorrowerCollateralAssets: 89933445200170648853010377374266787402,
                liquidationFee: 190000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 89933445200170648853010377374266787402,
                debtAssetsToRepay: 3213439959404690026280320723472971877754389,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #52
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 6128665301081128750000000000000000000000000,
                totalBorrowerDebtValue: 9718510336048075126669232304,
                totalBorrowerDebtAssets: 5956149707473613809208456400239722894340843,
                totalBorrowerCollateralValue: 9667801762421292456145631964,
                totalBorrowerCollateralAssets: 15951474830685384655641411588275370168,
                liquidationFee: 190000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 15951474830685384655641411588275370168,
                debtAssetsToRepay: 5956149707473613809208456400239722894340843,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #53
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 279573873090605426114052534103393554687,
                totalBorrowerDebtValue: 1089569031478772176413372108072508,
                totalBorrowerDebtAssets: 304615034130100121022335361365620542867,
                totalBorrowerCollateralValue: 1320393251645970948046801268255085,
                totalBorrowerCollateralAssets: 8257820045885547427903986781642274,
                liquidationFee: 10000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 3215860885291074451890710361491649,
                debtAssetsToRepay: 142334553764806119891300444859811494330,
                ltvAfterLiquidation: 720000000000000001
            })
        });

        data[i++] = CelaData({ // #54
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 510442581506483023986220359802246093750,
                totalBorrowerDebtValue: 1039859421657737659216991232824511,
                totalBorrowerDebtAssets: 530788527594814053793392617889530837588,
                totalBorrowerCollateralValue: 1089021304980277139878061361867295,
                totalBorrowerCollateralAssets: 8640824908838966815195848536249717,
                liquidationFee: 10000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 8333258112373594073700010292873236,
                debtAssetsToRepay: 530788527594814053793392617889530837588,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #55
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 951319718286744551733136177062988281250,
                totalBorrowerDebtValue: 1034304252136983048870888524106703,
                totalBorrowerDebtAssets: 983954029765736720557329749337420431205,
                totalBorrowerCollateralValue: 1250966187771726712775745432193905,
                totalBorrowerCollateralAssets: 3810213281253687311547442986616805,
                liquidationFee: 10000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 1506659541728438492698905093874550,
                debtAssetsToRepay: 465925560128015371060232631372082384470,
                ltvAfterLiquidation: 720000000000000000
            })
        });

        data[i++] = CelaData({ // #56
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 57241293753934383857995271682739257812,
                totalBorrowerDebtValue: 928105135355469457181243342347443,
                totalBorrowerDebtAssets: 53125938687417459730729672898356426521,
                totalBorrowerCollateralValue: 958994155224137654862602833616385,
                totalBorrowerCollateralAssets: 8760859398482107081120379307989501,
                liquidationFee: 10000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 8563460516521775351143723211516173,
                debtAssetsToRepay: 53125938687417459730729672898356426521,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #57
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 871223459174907067790627479553222656250,
                totalBorrowerDebtValue: 945658241702339208423211402987362,
                totalBorrowerDebtAssets: 823879644533172323741988804539151449008,
                totalBorrowerCollateralValue: 1054225725214509452511049174072504,
                totalBorrowerCollateralAssets: 9134075743375854948255507178320216,
                liquidationFee: 10000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 5986269027222440691415133463695333,
                debtAssetsToRepay: 595982378009271053797814950923029284013,
                ltvAfterLiquidation: 720000000000000001
            })
        });

        data[i++] = CelaData({ // #58
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 501451123886543558910489082336425781250,
                totalBorrowerDebtValue: 946978034706635485306946975470054,
                totalBorrowerDebtAssets: 474863199799512616757699831716786481040,
                totalBorrowerCollateralValue: 887286803098554309283578562629104,
                totalBorrowerCollateralAssets: 3186032102103659789036694787979018,
                liquidationFee: 10000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 3186032102103659789036694787979018,
                debtAssetsToRepay: 474863199799512616757699831716786481040,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #59
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 198142588942655915161594748497009277343,
                totalBorrowerDebtValue: 996015543599338104563400975166587,
                totalBorrowerDebtAssets: 197353098435899630892014214919856752097,
                totalBorrowerCollateralValue: 1027015269790836555695605746383371,
                totalBorrowerCollateralAssets: 8587060466995695019237949715885400,
                liquidationFee: 10000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 8411144809661844997897827429540722,
                debtAssetsToRepay: 197353098435899630892014214919856752097,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #60
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 793878398014678386971354484558105468750,
                totalBorrowerDebtValue: 906695479539957793768678584456210,
                totalBorrowerDebtAssets: 719805954784332297418558260305349479624,
                totalBorrowerCollateralValue: 1076500485986709169933809872585839,
                totalBorrowerCollateralAssets: 8437899828663958256614423206018524,
                liquidationFee: 10000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 3819468729351619263467411139801782,
                debtAssetsToRepay: 383014693052724626184116357720764995489,
                ltvAfterLiquidation: 720000000000000000
            })
        });

        data[i++] = CelaData({ // #61
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 934631476227770093828439712524414062500,
                totalBorrowerDebtValue: 1038403764057058875636130323982797,
                totalBorrowerDebtAssets: 970524842921122007925778196822216465964,
                totalBorrowerCollateralValue: 1035788333273446543117322970111321,
                totalBorrowerCollateralAssets: 436557012710597986223397250917805,
                liquidationFee: 10000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 425687921628000298657212852049268,
                debtAssetsToRepay: 934631476227770093828439712524414062500,
                ltvAfterLiquidation: 1489191397126934729
            })
        });

        data[i++] = CelaData({ // #62
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 615913091475046938285231590270996093750,
                totalBorrowerDebtValue: 927883610602578356996161801362177,
                totalBorrowerDebtAssets: 571495663135262676729008391447771324771,
                totalBorrowerCollateralValue: 941426991579056170662731443535398,
                totalBorrowerCollateralAssets: 7221567885005133977756258486489582,
                liquidationFee: 10000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 7188855098399170585409175070189336,
                debtAssetsToRepay: 571495663135262676729008391447771324771,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #63
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 342232502205007360316812992095947265625,
                totalBorrowerDebtValue: 1001397106629259114995988966256845,
                totalBorrowerDebtAssets: 342710637502585910790341547435177930783,
                totalBorrowerCollateralValue: 1022887027185081796562862559846056,
                totalBorrowerCollateralAssets: 8503914766843924548741412980492011,
                liquidationFee: 10000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 8408507851188602770534883804586367,
                debtAssetsToRepay: 342710637502585910790341547435177930783,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #64
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 4965603211663616093574091792106628417,
                totalBorrowerDebtValue: 962021021763670991511219199310289,
                totalBorrowerDebtAssets: 4777014675357598190994627483772690609,
                totalBorrowerCollateralValue: 897125842464042397669044237105619,
                totalBorrowerCollateralAssets: 6125735157270788293341169123710907,
                liquidationFee: 10000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 6125735157270788293341169123710907,
                debtAssetsToRepay: 4777014675357598190994627483772690609,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #65
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 769016600911738583818078041076660156250,
                totalBorrowerDebtValue: 991477286350903286304969697084743,
                totalBorrowerDebtAssets: 762462492630766149108437958770825561181,
                totalBorrowerCollateralValue: 1096183152616369369813738937536730,
                totalBorrowerCollateralAssets: 3173332302065816978695305213110719,
                liquidationFee: 10000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 2167430476553243907434848274584372,
                debtAssetsToRepay: 570068557146273106523628933553188754655,
                ltvAfterLiquidation: 720000000000000000
            })
        });

        data[i++] = CelaData({ // #66
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 681968090479807695373892784118652343750,
                totalBorrowerDebtValue: 1070407814435454030288497051515150,
                totalBorrowerDebtAssets: 729983973245210919873129165625236654478,
                totalBorrowerCollateralValue: 1271477591280266900355156355310278,
                totalBorrowerCollateralAssets: 10024003793387093723921542779881288,
                liquidationFee: 10000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 4522557938380823853155485189119456,
                debtAssetsToRepay: 387341747931294853008703385877570112154,
                ltvAfterLiquidation: 720000000000000000
            })
        });

        data[i++] = CelaData({ // #67
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 212536907004779786802828311920166015625,
                totalBorrowerDebtValue: 1073441094434442977245680594933219,
                totalBorrowerDebtAssets: 228145850062922244228459663008002884991,
                totalBorrowerCollateralValue: 1166180531951811106048000674052877,
                totalBorrowerCollateralAssets: 2114989868355924526889816142740914,
                liquidationFee: 10000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 1569811504587904063703992159787982,
                debtAssetsToRepay: 182145306848823388345888319965605412825,
                ltvAfterLiquidation: 720000000000000000
            })
        });

        data[i++] = CelaData({ // #68
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 754548099181833909824490547180175781250,
                totalBorrowerDebtValue: 986755626566341481620270315033849,
                totalBorrowerDebtAssets: 744554582382612495961291211987587622574,
                totalBorrowerCollateralValue: 898401517244961412672795325613419,
                totalBorrowerCollateralAssets: 5350507330866688016369361398949832,
                liquidationFee: 10000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 5350507330866688016369361398949832,
                debtAssetsToRepay: 744554582382612495961291211987587622574,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #69
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 167200086198254430200904607772827148437,
                totalBorrowerDebtValue: 988785181316116346117439661611570,
                totalBorrowerDebtAssets: 165324967547611288969766472558359252726,
                totalBorrowerCollateralValue: 974544128822371249607688348331767,
                totalBorrowerCollateralAssets: 6000757871522542718897023853188175,
                liquidationFee: 10000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 6000757871522542718897023853188175,
                debtAssetsToRepay: 165324967547611288969766472558359252726,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #70
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 566327100450971047393977642059326171875,
                totalBorrowerDebtValue: 949568884640250221451651668758131,
                totalBorrowerDebtAssets: 537766593116775525668016450631456550201,
                totalBorrowerCollateralValue: 948506452784272473966901294376334,
                totalBorrowerCollateralAssets: 4891142039257789176438630914244519,
                liquidationFee: 10000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 4891142039257789176438630914244519,
                debtAssetsToRepay: 537766593116775525668016450631456550201,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #71
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 318555163614989724010229110717773437500,
                totalBorrowerDebtValue: 966247137290911428664230697904713,
                totalBorrowerDebtAssets: 307803014912221728864908458411381041914,
                totalBorrowerCollateralValue: 943868259769691981564176331968841,
                totalBorrowerCollateralAssets: 9349875183608314358709525934049394,
                liquidationFee: 10000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 9349875183608314358709525934049394,
                debtAssetsToRepay: 307803014912221728864908458411381041914,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #72
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 791902375337027478963136672973632812500,
                totalBorrowerDebtValue: 1058390193907695042696559539763256,
                totalBorrowerDebtAssets: 838141708588920813899147738968729363548,
                totalBorrowerCollateralValue: 1240550934314163685124403354629266,
                totalBorrowerCollateralAssets: 644523602570475416232533360477665,
                liquidationFee: 10000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 317756354314645990608472187614782,
                debtAssetsToRepay: 479534977381793379174499982449298890333,
                ltvAfterLiquidation: 720000000000000001
            })
        });

        data[i++] = CelaData({ // #73
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 14834853126431735859114,
                totalBorrowerDebtValue: 92128528844437782563,
                totalBorrowerDebtAssets: 13667131941614641959228,
                totalBorrowerCollateralValue: 86334808052335996614,
                totalBorrowerCollateralAssets: 150109527716557053,
                liquidationFee: 140000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 150109527716557053,
                debtAssetsToRepay: 13667131941614641959228,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #74
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 879926209433167423412669,
                totalBorrowerDebtValue: 90147359508400446426,
                totalBorrowerDebtAssets: 793230243426358079234051,
                totalBorrowerCollateralValue: 101454551141966761557,
                totalBorrowerCollateralAssets: 773094934069194629,
                liquidationFee: 140000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 773094934069194629,
                debtAssetsToRepay: 793230243426358079234051,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #75
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 52677413820544245481869,
                totalBorrowerDebtValue: 95313022399736129219,
                totalBorrowerDebtAssets: 50208435234377032195239,
                totalBorrowerCollateralValue: 91071125871654620025,
                totalBorrowerCollateralAssets: 567724718969197049,
                liquidationFee: 140000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 567724718969197049,
                debtAssetsToRepay: 50208435234377032195239,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #76
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 321989505752632840085425,
                totalBorrowerDebtValue: 96751210898855259934,
                totalBorrowerDebtAssets: 311528745782911488533806,
                totalBorrowerCollateralValue: 94068777151026563426,
                totalBorrowerCollateralAssets: 641401707115864686,
                liquidationFee: 140000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 641401707115864686,
                debtAssetsToRepay: 311528745782911488533806,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #77
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 751713170837503639631904,
                totalBorrowerDebtValue: 103253023488991122480,
                totalBorrowerDebtAssets: 776166576854687597566921,
                totalBorrowerCollateralValue: 119194501671990740674,
                totalBorrowerCollateralAssets: 1393188805976797,
                liquidationFee: 140000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 1375819254402692,
                debtAssetsToRepay: 776166576854687597566921,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #78
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 381783080322965588493389,
                totalBorrowerDebtValue: 101091173468659061285,
                totalBorrowerDebtAssets: 385948996003279102181955,
                totalBorrowerCollateralValue: 98287914404797610005,
                totalBorrowerCollateralAssets: 979026178019132898,
                liquidationFee: 140000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 979026178019132898,
                debtAssetsToRepay: 381783080322965588493389,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #79
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 277026373911454993503866,
                totalBorrowerDebtValue: 109127005501854468239,
                totalBorrowerDebtAssets: 302310586299941422008917,
                totalBorrowerCollateralValue: 102563697817735109083,
                totalBorrowerCollateralAssets: 188889249724528386,
                liquidationFee: 140000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 188889249724528386,
                debtAssetsToRepay: 277026373911454993503866,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #80
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 343854388469113200699212,
                totalBorrowerDebtValue: 108713164882169133207,
                totalBorrowerDebtAssets: 373814988291001401475408,
                totalBorrowerCollateralValue: 126961175095552082903,
                totalBorrowerCollateralAssets: 862457026580439460,
                liquidationFee: 140000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 747665887074833600,
                debtAssetsToRepay: 331979108783670339381218,
                ltvAfterLiquidation: 720000000000000000
            })
        });

        data[i++] = CelaData({ // #81
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 433355293019971577450633,
                totalBorrowerDebtValue: 99886823711466297126,
                totalBorrowerDebtAssets: 432864837583167220869519,
                totalBorrowerCollateralValue: 105250738113585666280,
                totalBorrowerCollateralAssets: 397957628424601930,
                liquidationFee: 140000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 397957628424601930,
                debtAssetsToRepay: 432864837583167220869519,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #82
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 798310232848248870141105,
                totalBorrowerDebtValue: 96328396470913137950,
                totalBorrowerDebtAssets: 768999446165931018776855,
                totalBorrowerCollateralValue: 89335625012520370861,
                totalBorrowerCollateralAssets: 634109007637438676,
                liquidationFee: 140000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 634109007637438676,
                debtAssetsToRepay: 768999446165931018776855,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #83
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 840666113934746499580796,
                totalBorrowerDebtValue: 100637551090645753770,
                totalBorrowerDebtAssets: 846025789912826750907830,
                totalBorrowerCollateralValue: 91427520201833308413,
                totalBorrowerCollateralAssets: 366666905525343220,
                liquidationFee: 140000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 366666905525343220,
                debtAssetsToRepay: 840666113934746499580796,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #84
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 213586561318683243371197,
                totalBorrowerDebtValue: 99485118609393237143,
                totalBorrowerDebtAssets: 212486843861616440837427,
                totalBorrowerCollateralValue: 116829905267468728399,
                totalBorrowerCollateralAssets: 196218014449316031,
                liquidationFee: 140000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 164194034197117102,
                debtAssetsToRepay: 183164621873326227593964,
                ltvAfterLiquidation: 720000000000000000
            })
        });

        data[i++] = CelaData({ // #85
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 646336637483921367675065,
                totalBorrowerDebtValue: 99789063255138037433,
                totalBorrowerDebtAssets: 644973276019962520551610,
                totalBorrowerCollateralValue: 106381740699460022920,
                totalBorrowerCollateralAssets: 1034892792154867889,
                liquidationFee: 140000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 1034892792154867889,
                debtAssetsToRepay: 644973276019962520551610,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #86
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 24717340855393231890957,
                totalBorrowerDebtValue: 105443285689611290223,
                totalBorrowerDebtAssets: 26062776333027296555288,
                totalBorrowerCollateralValue: 96001246987603925726,
                totalBorrowerCollateralAssets: 868740195219240044,
                liquidationFee: 140000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 868740195219240044,
                debtAssetsToRepay: 24717340855393231890957,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #87
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 961316114047732116887345,
                totalBorrowerDebtValue: 94808133801630687376,
                totalBorrowerDebtAssets: 911405867663010521760902,
                totalBorrowerCollateralValue: 87074436861762777063,
                totalBorrowerCollateralAssets: 140421074501317854,
                liquidationFee: 140000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 140421074501317854,
                debtAssetsToRepay: 911405867663010521760902,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #88
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 26331688926717890808504,
                totalBorrowerDebtValue: 91628452062114600362,
                totalBorrowerDebtAssets: 24127318965362841100467,
                totalBorrowerCollateralValue: 97087866645569148486,
                totalBorrowerCollateralAssets: 837139854358062041,
                liquidationFee: 140000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 837139854358062041,
                debtAssetsToRepay: 24127318965362841100467,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #89
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 656803266358695691451430,
                totalBorrowerDebtValue: 106119250346515017202,
                totalBorrowerDebtAssets: 696994702511272128960775,
                totalBorrowerCollateralValue: 98633148628714284343,
                totalBorrowerCollateralAssets: 381201772171263192,
                liquidationFee: 140000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 381201772171263192,
                debtAssetsToRepay: 656803266358695691451430,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #90
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 86126935654450949186866,
                totalBorrowerDebtValue: 94351535865861719809,
                totalBorrowerDebtAssets: 81262086584176932656767,
                totalBorrowerCollateralValue: 104140077201377995568,
                totalBorrowerCollateralAssets: 883589552218993679,
                liquidationFee: 140000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 883589552218993679,
                debtAssetsToRepay: 81262086584176932656767,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #91
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 611483902399487396905897,
                totalBorrowerDebtValue: 103333075996076191316,
                totalBorrowerDebtAssets: 631865125570234676993533,
                totalBorrowerCollateralValue: 95692302550949029312,
                totalBorrowerCollateralAssets: 168835357057229554,
                liquidationFee: 140000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 168835357057229554,
                debtAssetsToRepay: 611483902399487396905897,
                ltvAfterLiquidation: 0
            })
        });

        data[i++] = CelaData({ // #92
            input: Input({
                lt: 800000000000000000,
                liquidationTargetLtv: 720000000000000000,
                maxDebtToCover: 503301233760391914984211,
                totalBorrowerDebtValue: 96668942180385259987,
                totalBorrowerDebtAssets: 486535978656998918309914,
                totalBorrowerCollateralValue: 87232635836387066352,
                totalBorrowerCollateralAssets: 390914581943762207,
                liquidationFee: 140000000000000000
            }),
            output: Output({
                collateralAssetsToLiquidate: 390914581943762207,
                debtAssetsToRepay: 486535978656998918309914,
                ltvAfterLiquidation: 0
            })
        });
    }
}

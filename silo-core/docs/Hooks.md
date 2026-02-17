
# Silo Protocol Hooks System

The **Silo Protocol Hooks System** provides an extensible mechanism for interacting with core actions like deposits, withdrawals, borrowing, repayments, leverage operations, collateral transitions, switching collateral, flash loans, and liquidations. Hooks allow external systems to execute custom logic **before** or **after** protocol actions, offering flexibility for validation, logging, or integration with external contracts. While the protocol is fully functional without hooks, they enhance its modularity and allow for seamless interaction with other decentralized systems.

- [Overview](#overview)
- [Call On Behalf Of](#call-on-behalf-of-the-silo-or-share-token)
- [Deposit function hook actions](#deposit-function-hook-actions)
- [Withdraw function hook actions](#withdraw-function-hook-actions)
- [Borrow function hook actions](#borrow-function-hook-actions)
- [Repay function hook actions](#repay-function-hook-actions)
- [Transition Collateral function hook actions](#transition-collateral-function-hook-actions)
- [Switch Collateral To This Silo function hook actions](#switch-collateral-to-this-silo-function-hook-actions)
- [Flash Loan function hook actions](#flash-loan-function-hook-actions)
- [Liquidation Call function hook actions](#liquidation-call-function-hook-actions)
- [Share Token Transfer hook](#share-token-transfer-hook-afteraction)
- [Share Debt Token Transfer hook](#share-debt-token-transfer-hook-afteraction)

## Overview

The **Silo Protocol** is a decentralized lending protocol. It allows users to deposit assets, borrow funds, and manage collateral securely. One of the key features of the protocol is its **Hooks System**, which provides an extensible mechanism for interacting with protocol actions such as deposits, withdrawals, borrowing, repayments, liquidations, and other advanced actions like flash loans and leverage operations.

The hooks system allows external contracts or modules to execute additional logic at two key points: **before** and **after** the core logic of each protocol action. While the protocol is fully functional without hooks, the system provides an extension point for developers and users who wish to enforce additional checks, perform external calls, or execute custom business logic surrounding core operations.

Each action within the protocol (except for the share tokens transfer) is associated with two types of hooks:
- **Before Action Hook**: Invoked **before** any logic of the action is executed. This can be used to perform validation checks, eligibility assessments, or custom logic before the main action takes place.
- **After Action Hook**: Invoked **after** all logic of the action is completed. This allows developers to perform follow-up tasks such as logging, notifications, or additional off-chain and on-chain integrations.

Share tokens transfer only has an **After Action Hook**.

### Some concepts

1. **Collaterals**: 
   - The protocol supports two types of collateral: **Hook.COLLATERAL_TOKEN** (borrowable collateral) and **Hook.PROTECTED_TOKEN** (non-borrowable collateral). Borrowable collateral earns interest as it is available for lending, while protected collateral provides security for the user, ensuring liquidity and immediate access to their funds.
   - Transitions between these collateral types (e.g., transitioning from **Hook.PROTECTED_TOKEN** to **Hook.COLLATERAL_TOKEN**).

2. **Token Transfers**:
   - The hooks system notifies also about the share token transfers that occur during key actions like deposits, withdrawals, and borrow operations or when share tokens are transferred via ERC-20 transfer or transferFrom function directly.
   - For instance, **Hook.SHARE_TOKEN_TRANSFER** is invoked during deposit and withdrawal actions to handle share tokens, and during borrow and repay actions to manage debt tokens.

3. **Transitioning Between Collateral Types**:
   - Users can transition their assets between **Hook.PROTECTED_TOKEN** and **Hook.COLLATERAL_TOKEN** and vice verse without transferring the underlying assets. This transition is crucial for users who want to switch between protected and borrowable collateral, enabling interest generation or enhanced security.

## Call on behalf of the Silo or Share token

Hooks developers can call any function on behalf of the Silo or Share token. Which opens a possibility to use a silo or share token as a proxy for any other contract.

If developer need this functionality, they can use `callOnBehalfOfSilo` function to call on behalf of the silo or collateral share token.

```solidity
function callOnBehalfOfSilo(address _target, uint256 _value, ISilo.CallType _callType, bytes calldata _input)
    external
    payable
    onlyHookReceiver()
    returns (bool success, bytes memory result)
{
    ...
}
```

Or if it is needed to call on behalf of the protected share token or debt token, they can use `callOnBehalfOfShareToken` function.

```solidity
function callOnBehalfOfShareToken(address _target, uint256 _value, ISilo.CallType _callType, bytes calldata _input)
    external
    payable
    onlyHookReceiver()
    returns (bool success, bytes memory result)
{
    ...
}
```

See this function implementation in the
- [Silo](https://github.com/silo-finance/silo-contracts-v3/blob/1.3.2/silo-core/contracts/Silo.sol#L55) contract.
- [ShareDebtToken](https://github.com/silo-finance/silo-contracts-v3/blob/1.3.2/silo-core/contracts/utils/ShareDebtToken.sol#L22) contract.
- [ShareProtectedCollateralToken](https://github.com/silo-finance/silo-contracts-v3/blob/1.3.2/silo-core/contracts/utils/ShareProtectedCollateralToken.sol#L11) contract.

# Deposit function hook actions

- **Action**: `Hook.depositAction(depositType)`
  - **Context**: This hook is invoked during deposit operations, allowing for actions to be taken before and after the deposit logic is executed. Depositors receive shares representing their stake in the vault, and this process can trigger other hook actions such as token transfers when these shares are minted. The protocol supports different types of deposits that determine liquidity and risk preferences.
  - **Parameters**:
    - `depositType`: This refers to the type of deposit being made, which can either be a **borrowable** or **non-borrowable** deposit, defined by **Hook.COLLATERAL_TOKEN** and **Hook.PROTECTED_TOKEN** respectively.

  - **Deposit Types**:
    - **Hook.COLLATERAL_TOKEN**:
      - This represents a **borrowable deposit**. When a user deposits assets under this type, the assets can be borrowed by other users within the protocol.
    - **Hook.PROTECTED_TOKEN**:
      - This represents a **non-borrowable deposit**. Deposits of this type are protected from being borrowed by other participants, providing a higher level of security for the depositor.

  - **Before Deposit Data**:
    - **Structure**: The data processed before the deposit is encoded as `abi.encodePacked(assets, shares, receiver)`.
    - **Fields**:
      - `assets`: The assets (tokens) being deposited into the protocol.
      - `shares`: The shares generated from the deposit, representing the depositor’s ownership or claim within the protocol.
      - `receiver`: The address of the recipient (typically the depositor) who will receive the shares generated from the deposit.
    - **Purpose**: The `beforeAction` hook is called **before** any logic of the deposit action is executed. It allows external systems to perform additional checks or actions before the main deposit logic runs. For example, this hook could be used to check whether a wallet is on a restricted list (e.g., OFAC sanctions) and block the deposit if necessary. The core deposit logic (including input validation and collateral checks) does not rely on this hook.

    - **Decoding Hook Input Example**:
      ```solidity
      Hook.BeforeDepositInput memory input = Hook.beforeDepositDecode(_inputAndOutput);
      ```
      - **Explanation**: This code demonstrates how developers can decode the data sent to the `beforeAction` hook using the `Hook` library. The `beforeDepositDecode` function helps access fields like `assets`, `shares`, and `receiver`, allowing developers to apply pre-deposit checks.

  - **After Deposit Data**:
    - **Structure**: The data processed after the deposit is encoded as `abi.encodePacked(assets, shares, receiver, receivedAssets, mintedShares)`.
    - **Fields**:
      - `assets`: The tokens deposited into the protocol.
      - `shares`: The shares generated from the deposit.
      - `receiver`: The address where the shares will be sent (typically the depositor).
      - `receivedAssets`: The actual assets received by the protocol after the deposit.
      - `mintedShares`: The number of shares minted as a result of the deposit, reflecting the depositor’s claim in the protocol.
    - **Purpose**: The `afterAction` hook is called **after** all logic of the deposit action is completed. It allows external systems to perform follow-up tasks or adjustments after the deposit is processed. For instance, this hook can be used to trigger notifications or other logic once the deposit is finalized.

    - **Decoding Hook Input Example**:
      ```solidity
      Hook.AfterDepositInput memory input = Hook.afterDepositDecode(_inputAndOutput);
      ```
      - **Explanation**: This code example shows how developers can decode the data sent to the `afterAction` hook using the `Hook` library. The `afterDepositDecode` function allows easy access to fields like `receivedAssets` and `mintedShares`, simplifying post-deposit logic.

### Share Token Transfer Hook (During Deposit)

- During the deposit, share tokens are minted to the depositor. This action triggers a **Share Token Transfer Hook**, which manages the token transfer logic. For more details, refer to the [Share Token Transfer Hook](#share-token-transfer-hook-afteraction) section.

---

# Withdraw function hook actions

- **Action**: `Hook.withdrawAction(collateralType)`
  - **Context**: This hook is invoked during withdrawal operations, allowing for actions to be taken before and after the withdrawal logic is executed. Different types of collateral influence the conditions under which withdrawals occur.
  - **Parameters**:
    - `collateralType`: This refers to the type of collateral being withdrawn, which can either be a **borrowable** or **non-borrowable** collateral, defined by **Hook.COLLATERAL_TOKEN** and **Hook.PROTECTED_TOKEN** respectively.

  - **Before Withdraw Data**:
    - **Structure**: The data processed before the withdrawal is encoded as `abi.encodePacked(assets, shares, receiver, owner, spender)`.
    - **Fields**:
      - `assets`: The assets (tokens) being withdrawn from the protocol.
      - `shares`: The shares that are being burned or redeemed in exchange for the withdrawal of the corresponding assets.
      - `receiver`: The address of the recipient (typically the depositor) who will receive the withdrawn assets.
      - `owner`: The owner of the assets (typically the depositor).
      - `spender`: The entity authorized to initiate the withdrawal.
    - **Purpose**: The `beforeAction` hook is called **before** any logic of the withdrawal action is executed. It allows external systems to perform additional checks or actions before the main withdrawal logic runs. For instance, this could be used to restrict withdrawals from a certain wallet that has violated protocol rules. The core withdrawal logic (including eligibility checks and asset transfers) does not depend on this hook.

    - **Decoding Hook Input Example**:
      ```solidity
      Hook.BeforeWithdrawInput memory input = Hook.beforeWithdrawDecode(_inputAndOutput);
      ```
      - **Explanation**: This code shows how developers can easily decode the data sent to the `beforeAction` hook using the `Hook` library. The `beforeWithdrawDecode` function simplifies access to the relevant data, such as `assets`, `shares`, `receiver`, `owner`, and `spender`, allowing the developer to apply pre-withdrawal logic as needed.

  - **After Withdraw Data**:
    - **Structure**: The data processed after the withdrawal is encoded as `abi.encodePacked(assets, shares, receiver, owner, spender, withdrawnAssets, withdrawnShares)`.
    - **Fields**:
      - `assets`: The tokens/assets withdrawn from the protocol.
      - `shares`: The shares that were redeemed in exchange for the withdrawn assets.
      - `receiver`: The address where the assets will be sent (typically the depositor).
      - `owner`: The owner of the assets.
      - `spender`: The entity that initiated the withdrawal.
      - `withdrawnAssets`: The actual assets withdrawn from the protocol (may differ slightly from the input amount due to factors such as fees or slippage).
      - `withdrawnShares`: The number of shares burned as a result of the withdrawal.
    - **Purpose**: The `afterAction` hook is called **after** all logic of the withdrawal action is completed. It allows external systems to perform follow-up tasks or adjustments after the withdrawal has been processed. For example, this hook could be used to trigger on-chain or off-chain events such as notifications or accounting updates. The core withdrawal logic (e.g., asset transfers and share adjustments) is fully executed before this hook is invoked.

    - **Decoding Hook Input Example**:
      ```solidity
      Hook.AfterWithdrawInput memory input = Hook.afterWithdrawDecode(_inputAndOutput);
      ```
      - **Explanation**: This code example shows how developers can decode the data sent to the `afterAction` hook using the `Hook` library. The `afterWithdrawDecode` function allows developers to easily access data such as `withdrawnAssets` and `withdrawnShares` for post-withdrawal logic.

### Share Token Transfer Hook (During Withdraw)

- During the withdrawal process, share tokens are burned to release the depositor's stake in the protocol. This action triggers a **Share Token Transfer Hook**, which manages the token transfer logic. For more details, refer to the [Share Token Transfer Hook](#share-token-transfer-hook-afteraction) section.
---


# Borrow function hook actions

- **Action**: `Hook.BORROW`
  - **Context**: This hook is invoked during borrowing operations, allowing for actions to be taken before and after the borrow logic is executed. Borrowing operations in the protocol result in the minting of a debt token to represent the borrower’s debt position.
  
  - **Before Borrow Data**:
    - **Structure**: The data processed before the borrow action is encoded as `abi.encodePacked(assets, shares, receiver, borrower)`.
    - **Fields**:
      - `assets`: The assets (tokens) being borrowed from the protocol.
      - `shares`: The shares representing the borrower’s debt or stake in the system.
      - `receiver`: The address of the entity receiving the borrowed assets.
      - `borrower`: The address of the borrower.
    - **Purpose**: The `beforeAction` hook is called **before** any logic of the borrow action is executed. It allows external systems to perform additional checks or actions before the borrow logic runs. For example, this could be used to check the borrower’s status or eligibility. The core borrowing logic (e.g., collateral checks and interest calculations) does not depend on this hook.

    - **Decoding Hook Input Example**:
      ```solidity
      Hook.BeforeBorrowInput memory input = Hook.beforeBorrowDecode(_inputAndOutput);
      ```
      - **Explanation**: This code demonstrates how developers can decode the data sent to the `beforeAction` hook using the `Hook` library. The `beforeBorrowDecode` function allows easy access to fields like `assets`, `shares`, `receiver`, and `borrower`, enabling developers to apply pre-borrow logic as needed.

  - **After Borrow Data**:
    - **Structure**: The data processed after the borrow action is encoded as `abi.encodePacked(assets, shares, receiver, borrower, borrowedAssets, borrowedShares)`.
    - **Fields**:
      - `assets`: The assets (tokens) borrowed from the protocol.
      - `shares`: The shares representing the borrower’s debt or stake in the system.
      - `receiver`: The address where the borrowed assets are sent.
      - `borrower`: The address of the borrower.
      - `borrowedAssets`: The actual assets borrowed from the protocol.
      - `borrowedShares`: The debt shares representing the borrowed amount.
    - **Purpose**: The `afterAction` hook is called **after** all logic of the borrow action is completed. It allows external systems to perform follow-up tasks or adjustments after the borrowing process has finished. For example, this hook could trigger updates to the borrower’s debt position. The core borrow logic (e.g., interest rate application and debt accounting) is fully executed before this hook is called.

    - **Decoding Hook Input Example**:
      ```solidity
      Hook.AfterBorrowInput memory input = Hook.afterBorrowDecode(_inputAndOutput);
      ```
      - **Explanation**: This code example shows how developers can decode the data sent to the `afterAction` hook using the `Hook` library. The `afterBorrowDecode` function allows easy access to fields like `borrowedAssets` and `borrowedShares`, simplifying post-borrow logic.

### Share Token Transfer Hook (During Borrow)

- During the borrowing process, debt tokens are minted to represent the borrower's liability in the protocol. This action triggers a **Share Token Transfer Hook** for the **DEBT_TOKEN** type, which manages the token transfer logic for debt tokens. For more details, refer to the [Share Debt Token Transfer hook](#share-debt-token-transfer-hook-afteraction) section.
---

# Repay function hook actions

- **Action**: `Hook.REPAY` (beforeAction and afterAction)
  - **Context**: This hook is invoked during the repayment of borrowed assets, allowing for actions to be taken before and after the repayment logic is executed. When a user repays their debt, their debt position is adjusted accordingly, and the corresponding debt tokens are updated.
  
  - **Before Repay Data**:
    - **Structure**: The data processed before the repayment is encoded as `abi.encodePacked(assets, shares, borrower, repayer)`.
    - **Fields**:
      - `assets`: The assets (tokens) being repaid to the protocol.
      - `shares`: The shares representing the borrower’s debt or stake in the system.
      - `borrower`: The address of the borrower whose debt is being repaid.
      - `repayer`: The address of the entity making the repayment (can be the borrower or a third party).
    - **Purpose**: The `beforeAction` hook is called **before** any logic of the repayment action is executed. It allows external systems to perform additional checks or actions before the repayment logic runs. For example, this could be used to verify the borrower’s debt position or enforce rules around who can repay the debt. The core repayment logic (e.g., debt adjustment and token transfers) does not depend on this hook.

    - **Decoding Hook Input Example**:
      ```solidity
      Hook.BeforeRepayInput memory input = Hook.beforeRepayDecode(_inputAndOutput);
      ```
      - **Explanation**: This code demonstrates how developers can decode the data sent to the `beforeAction` hook using the `Hook` library. The `beforeRepayDecode` function simplifies access to fields like `assets`, `shares`, `borrower`, and `repayer`, enabling developers to apply pre-repayment logic as needed.

  - **After Repay Data**:
    - **Structure**: The data processed after the repayment is encoded as `abi.encodePacked(assets, shares, borrower, repayer, repaidAssets, repaidShares)`.
    - **Fields**:
      - `assets`: The assets (tokens) repaid to the protocol.
      - `shares`: The shares representing the borrower’s debt or stake in the system.
      - `borrower`: The address of the borrower whose debt is being repaid.
      - `repayer`: The address of the entity making the repayment.
      - `repaidAssets`: The actual assets repaid to the protocol.
      - `repaidShares`: The shares representing the amount of debt repaid.
    - **Purpose**: The `afterAction` hook is called **after** all logic of the repayment action is completed. It allows external systems to perform follow-up tasks or adjustments after the repayment process has finished. For example, this hook could be used to update the borrower’s debt position or trigger notifications. The core repayment logic (e.g., debt reduction and share adjustments) is fully executed before this hook is invoked.

    - **Decoding Hook Input Example**:
      ```solidity
      Hook.AfterRepayInput memory input = Hook.afterRepayDecode(_inputAndOutput);
      ```
      - **Explanation**: This code example shows how developers can decode the data sent to the `afterAction` hook using the `Hook` library. The `afterRepayDecode` function allows developers to easily access data such as `repaidAssets` and `repaidShares` for post-repayment logic.

### Share Debt Token Transfer Hook (During Repay)

- During the repayment process, debt tokens are burned to adjust the borrower’s debt position. This action triggers a **Share Token Transfer Hook** for the **DEBT_TOKEN** type, which manages the token transfer logic for debt tokens. For more details, refer to the [Share Debt Token Transfer hook](#share-debt-token-transfer-hook-afteraction) section.
---

# Transition Collateral function hook actions

- **Action**: `Hook.transitionCollateralAction(withdrawType)` (beforeAction and afterAction)
  - **Context**: The **transitionCollateral** function allows users to transition from one type of collateral to another (e.g., from **Hook.PROTECTED_TOKEN** to **Hook.COLLATERAL_TOKEN**) without transferring underlying assets. This transition enables users to adjust their collateral based on their preference to either protect their assets or make them borrowable to earn interest. The transition involves a combination of both a withdraw and deposit action, representing the change in collateral type.
  - **Parameters**:
    - `withdrawType`: This refers to the type of collateral being transitioned **from**, which can either be **Hook.COLLATERAL_TOKEN** or **Hook.PROTECTED_TOKEN**.

  - **Possible Actions**:
    - `Hook.TRANSITION_COLLATERAL | Hook.COLLATERAL_TOKEN`: Represents transitioning **from** a **borrowable** collateral type to a protected one.
    - `Hook.TRANSITION_COLLATERAL | Hook.PROTECTED_TOKEN`: Represents transitioning **from** a **protected** collateral type to a borrowable one.

  - **Process**: 
    - The transition involves first **withdrawing** the collateral from the current collateral type and then **depositing** it into the new collateral type. For example, if a user transitions from **Hook.PROTECTED_TOKEN** to **Hook.COLLATERAL_TOKEN**, the protocol first withdraws the protected deposit and then deposits it as borrowable collateral, enabling the user to earn interest. This operation happens without transferring the underlying assets.

  - **Before Transition Collateral Data**:
    - **Structure**: The data processed before the transition of collateral is encoded as `abi.encodePacked(shares, owner, assets)`.
    - **Fields**:
      - `shares`: The shares representing the collateral being transitioned.
      - `owner`: The address of the entity that owns the collateral.
      - `assets`: The assets (tokens) being transitioned between collateral types.
    - **Purpose**: The `beforeAction` hook is called **before** any logic of the transition collateral action is executed. It allows external systems to perform checks or actions before the transition logic runs. For example, this could include verifying the user’s collateral state or eligibility for the transition. The core transition logic, which includes the virtual withdrawal and deposit, does not rely on this hook.

    - **Decoding Hook Input Example**:
      ```solidity
      Hook.BeforeTransitionCollateralInput memory input = Hook.beforeTransitionCollateralDecode(_inputAndOutput);
      ```
      - **Explanation**: This code demonstrates how developers can decode the data sent to the `beforeAction` hook using the `Hook` library. The `beforeTransitionCollateralDecode` function simplifies access to fields like `shares`, `owner`, and `assets`, allowing developers to apply pre-transition logic as needed.

  - **After Transition Collateral Data**:
    - **Structure**: The data processed after the transition of collateral is encoded as `abi.encodePacked(shares, owner, assets)`.
    - **Fields**:
      - `shares`: The shares representing the collateral that has been transitioned.
      - `owner`: The address of the entity that owns the collateral.
      - `assets`: The assets (tokens) transitioned between collateral types.
    - **Purpose**: The `afterAction` hook is called **after** all logic of the transition collateral action is completed. It allows external systems to perform follow-up tasks or adjustments after the transition is processed. For instance, external systems could update the user’s collateral type or adjust accounting based on the newly deposited and withdrawn collateral. The core transition logic is fully executed before this hook is invoked.

    - **Decoding Hook Input Example**:
      ```solidity
      Hook.AfterTransitionCollateralInput memory input = Hook.afterTransitionCollateralDecode(_inputAndOutput);
      ```
      - **Explanation**: This code example shows how developers can decode the data sent to the `afterAction` hook using the `Hook` library. The `afterTransitionCollateralDecode` function allows developers to easily access data like `shares`, `owner`, and `assets`, simplifying post-transition logic.

### Share Token Transfer Hooks (During Transition Collateral)

- **Collateral Token Transfer**:
  - During the transition, collateral tokens are transferred to reflect the user's updated collateral position. This action triggers a **Share Token Transfer Hook** both **Hook.COLLATERAL_TOKEN** and **Hook.PROTECTED_TOKEN** types. These hooks manage the token transfer logic to reflect the change in collateral type during the transition. For more details, refer to the [Share Token Transfer Hook](#share-token-transfer-hook-afteraction) section.
---

# Switch Collateral to This Silo function hook actions

- **Action**: `Hook.SWITCH_COLLATERAL` (beforeAction and afterAction)
  - **Context**: This hook is invoked when collateral is switched to the current silo. The function allows for actions to be taken before and after the collateral switch is executed.
  
  - **Before and After Switch Collateral Data**:
    - **Structure**: The data processed for the switch collateral action is encoded as `abi.encodePacked(msg.sender)`.
    - **Fields**:
      - `msg.sender`: The address of the user switching their collateral to this silo.
    - **Purpose**: The `beforeAction` and `afterAction` hooks allow external systems to perform additional checks or tasks before and after the collateral switch process. This might include verifying if the user is eligible to switch their collateral or handling post-switch operations such as updating the user’s collateral information.

    - **Decoding Hook Input Example**:
      ```solidity
      Hook.SwitchCollateralInput memory input = Hook.switchCollateralDecode(_inputAndOutput);
      ```
      - **Explanation**: This code demonstrates how developers can decode the data sent to the `beforeAction` or `afterAction` hook using the `Hook` library. The `switchCollateralDecode` function simplifies access to the `msg.sender` field, enabling developers to apply pre- and post-collateral switch logic as needed.
---

# Flash Loan function hook actions

- **Action**: `Hook.FLASH_LOAN` (beforeAction and afterAction)
  - **Context**: This hook is invoked during flash loan operations, allowing actions to be taken before and after the flash loan logic is executed. Flash loans involve borrowing assets without collateral and without changing the Silo state, provided that the loan is repaid within the same transaction, along with a fee.

  - **Before Flash Loan Data**:
    - **Structure**: The data processed before the flash loan is encoded as `abi.encodePacked(receiver, token, amount)`.
    - **Fields**:
      - `receiver`: The address receiving the flash loan.
      - `token`: The asset (token) being borrowed.
      - `amount`: The amount of the token being borrowed.
    - **Purpose**: The `beforeAction` hook is called **before** any logic of the flash loan is executed. It allows external systems to perform checks or tasks before the loan is issued. For example, the hook could verify the receiver's eligibility to take the flash loan or ensure that the request complies with external conditions.

    - **Decoding Hook Input Example**:
      ```solidity
      Hook.BeforeFlashLoanInput memory input = Hook.beforeFlashLoanDecode(_inputAndOutput);
      ```
      - **Explanation**: This code shows how developers can decode the data sent to the `beforeAction` hook using the `Hook` library. The `beforeFlashLoanDecode` function provides access to fields like `receiver`, `token`, and `amount`, allowing developers to apply pre-flash loan logic as needed.

  - **After Flash Loan Data**:
    - **Structure**: The data processed after the flash loan is encoded as `abi.encodePacked(receiver, token, amount, fee)`.
    - **Fields**:
      - `receiver`: The address that received the flash loan.
      - `token`: The asset (token) that was borrowed.
      - `amount`: The amount of the token borrowed.
      - `fee`: The fee associated with the flash loan.
    - **Purpose**: The `afterAction` hook is called **after** all logic of the flash loan is executed, including the repayment of the loan and fee. It allows external systems to handle follow-up tasks, such as logging the loan details, tracking the fee paid, or adjusting balances after the transaction completes.

    - **Decoding Hook Input Example**:
      ```solidity
      Hook.AfterFlashLoanInput memory input = Hook.afterFlashLoanDecode(_inputAndOutput);
      ```
      - **Explanation**: This code demonstrates how developers can decode the data sent to the `afterAction` hook using the `Hook` library. The `afterFlashLoanDecode` function provides access to fields such as `receiver`, `token`, `amount`, and `fee`, enabling post-flash loan logic.
---

## Share Token Transfer Hook (AfterAction)

- **Action**: `Hook.shareTokenTransfer(tokenType)` (afterAction)
  - **Context**: During the deposit process, shares are minted for the depositor to represent their stake in the protocol. This triggers a token transfer action where share tokens are transferred. The `Hook.shareTokenTransfer` hook is invoked after the shares are minted.
  - **Parameters**:
    - `tokenType`: This refers to the type of share token being transferred, defined by **Hook.COLLATERAL_TOKEN** and **Hook.PROTECTED_TOKEN**.

  - **Share Token Types**:
    - **Hook.COLLATERAL_TOKEN**:
      - These are share tokens minted for **borrowable deposits**, representing the depositor's stake in the vault.
    - **Hook.PROTECTED_TOKEN**:
      - These are share tokens minted for **non-borrowable deposits**, representing a protected stake in the vault that cannot be borrowed.

  - **After Token Transfer Data**:
    - **Structure**: The data processed after the token transfer is encoded as `abi.encodePacked(sender, recipient, amount, balanceOfSender, balanceOfRecipient, totalSupply)`.
    - **Fields**:
      - `sender`: The address sending the share tokens.
      - `recipient`: The address receiving the share tokens.
      - `amount`: The amount of share tokens being transferred.
      - `balanceOfSender`: The balance of share tokens remaining with the sender.
      - `balanceOfRecipient`: The balance of share tokens now held by the recipient.
      - `totalSupply`: The total supply of the share tokens in the protocol.
    - **Purpose**: The `afterAction` hook is called **after** the share tokens are transferred. It allows external systems to monitor or act upon token transfers. For instance, this could be used to trigger accounting or balance updates after the token transfer is complete.

    - **Decoding Hook Input Example**:
      ```solidity
      Hook.AfterTokenTransfer memory input = Hook.afterTokenTransferDecode(_inputAndOutput);
      ```
      - **Explanation**: This code demonstrates how developers can decode the data sent to the `afterAction` hook for token transfers using the `Hook` library. The `afterTokenTransferDecode` function provides access to data like `sender`, `recipient`, and `amount`, which can be used in post-transfer logic.

## Share Debt Token Transfer Hook (AfterAction)

- **Action**: `Hook.shareTokenTransfer(tokenType)` (afterAction)
  - **Context**: This hook is invoked during the transfer of debt tokens that represent a borrower’s liability in the protocol. It is triggered after the debt tokens are transferred or minted in response to borrowing operations.
  - **Parameters**:
    - `tokenType`: The type of token being transferred, which in this case is **Hook.DEBT_TOKEN**.
  
  - **Possible Actions**:
    - `Hook.SHARE_TOKEN_TRANSFER | Hook.DEBT_TOKEN`: This action represents the transfer of debt tokens minted during borrowing activities. The debt tokens are used to track the borrower’s debt position within the protocol.

  - **After Token Transfer Data**:
    - **Structure**: The data processed after the token transfer is encoded as `abi.encodePacked(sender, recipient, amount, balanceOfSender, balanceOfRecipient, totalSupply)`.
    - **Fields**:
      - `sender`: The address of the entity transferring the debt tokens (typically the borrower).
      - `recipient`: The address of the entity receiving the debt tokens (typically the protocol or null if the tokens are being minted).
      - `amount`: The amount of debt tokens being transferred.
      - `balanceOfSender`: The remaining balance of debt tokens held by the sender after the transfer.
      - `balanceOfRecipient`: The balance of debt tokens held by the recipient after the transfer.
      - `totalSupply`: The total supply of the debt tokens in the protocol after the transfer.
    - **Purpose**: This hook allows external systems to monitor or react to debt token transfers after borrowing actions. It can be used to log or update a borrower’s debt position, track debt token balances, or trigger off-chain or on-chain notifications based on the transfer of debt tokens.

    - **Decoding Hook Input Example**:
      ```solidity
      Hook.AfterTokenTransfer memory input = Hook.afterTokenTransferDecode(_inputAndOutput);
      ```
      - **Explanation**: This code demonstrates how developers can decode the data sent to the `afterAction` hook using the `Hook` library. The `afterTokenTransferDecode` function simplifies access to the transfer data, such as `sender`, `recipient`, `amount`, and token balances.

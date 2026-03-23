# Off-Balance Sheet Accounts

> **Module:** `account` | **Path:** [`addons/account/`](../addons/account/)
> **Odoo Apps category:** Accounting

## What It Does

Off-Balance Sheet is a special account type in Odoo for tracking financial commitments that are **real but not yet actual assets or liabilities**. Think of it as a "memo pad" inside your accounting system -- it records things your company is responsible for, but that haven't turned into real money movement yet.

These accounts live completely **outside** your normal financial statements. They don't affect your Balance Sheet totals, don't appear on your Profit & Loss, and can't interact with taxes or reconciliation.

---

## The Simple Explanation

Imagine your company guarantees a $100,000 bank loan for a friend's business. Right now, you don't owe anything -- your friend is paying. But if they stop paying, you're on the hook. This is not a real liability yet, but it's important enough to track. That's what off-balance sheet accounts are for.

**Normal accounts** = money you actually have or owe right now
**Off-balance accounts** = money you *might* have to deal with, or commitments you need to remember

---

## When to Use Off-Balance Sheet

### Best For
- **Guarantees given** -- you guaranteed someone else's loan or lease
- **Contingent liabilities** -- potential future obligations (lawsuits pending, warranty reserves not yet triggered)
- **Operating lease commitments** -- future lease payments you're committed to but haven't incurred yet
- **Letters of credit** -- bank guarantees issued on your behalf for international trade
- **Pledged assets** -- assets used as collateral that you still own but can't freely dispose of
- **Commitments to purchase** -- signed contracts to buy goods/services at a future date

### Not For
- **Actual debts you owe** -- use Liability accounts (Current or Non-current)
- **Revenue or expenses** -- use Income/Expense accounts
- **Assets you own** -- use Asset accounts
- **Anything involving taxes** -- off-balance accounts cannot have taxes

---

## Real-World Use Cases

### Use Case 1: Bank Guarantee for a Subsidiary
**Situation:** A parent company guarantees a 500,000 EUR bank loan taken by its subsidiary. The parent doesn't owe the bank anything directly -- the subsidiary is paying. But auditors and regulators need to see this commitment.

**In Odoo:**
1. Create two off-balance accounts (e.g., "Guarantees Given" and "Guarantees Given - Counterpart")
2. Create a journal entry: Debit "Guarantees Given" 500,000 / Credit "Guarantees Given - Counterpart" 500,000
3. The Balance Sheet report shows this under a separate "OFF BALANCE SHEET ACCOUNTS" section at the bottom

**Result:** Auditors can see the guarantee commitment. It doesn't inflate your liabilities. If the subsidiary defaults, you'd create a real liability entry and reverse the off-balance entry.

### Use Case 2: Operating Lease Commitment
**Situation:** A retail company signs a 5-year office lease at 2,000 EUR/month. The total future commitment is 120,000 EUR. Each month's rent is a real expense, but the remaining future payments are just commitments.

**In Odoo:**
1. Create off-balance accounts for "Lease Commitments" and "Lease Commitments - Counterpart"
2. Record the full 120,000 EUR commitment as an off-balance entry
3. Each month, reduce the off-balance amount by 2,000 (and record the actual rent as a normal expense)

**Result:** The financial statements show the remaining lease obligation without overstating liabilities. Stakeholders know the company's future cash commitments.

### Use Case 3: Pending Lawsuit
**Situation:** A construction company is being sued for 200,000 EUR over a contract dispute. The lawyers say the outcome is uncertain. It's not a definite liability, but it's material enough to disclose.

**In Odoo:**
1. Record 200,000 EUR in off-balance accounts ("Contingent Liabilities - Litigation")
2. If the lawsuit is lost, reverse the off-balance entry and create a real liability
3. If dismissed, simply reverse the off-balance entry

**Result:** The potential obligation is visible in reports without distorting the actual financial position.

### Use Case 4: Pledged Inventory as Collateral
**Situation:** A manufacturer pledges 300,000 EUR of inventory as collateral for a credit line. The inventory is still on the balance sheet as a real asset, but the pledge needs to be disclosed.

**In Odoo:**
1. Create off-balance entry recording the pledged value
2. The inventory stays in normal asset accounts (it's still yours)
3. The off-balance entry flags the restriction on those assets

**Result:** Anyone reviewing the books sees that 300,000 of inventory is encumbered and can't be freely sold.

---

## How Off-Balance Differs from Every Other Account Type

| Feature | Off-Balance Sheet | All Other Types |
|---|---|---|
| Appears in Balance Sheet totals | No -- separate section at bottom | Asset/Liability/Equity: Yes. Income/Expense: No (they go to P&L) |
| Appears in Profit & Loss | No | Income/Expense: Yes. Asset/Liability/Equity: No |
| Can have taxes | No (hard block) | Yes (no restriction at account level, except off-balance) |
| Can be reconciled | No (hard block) | Receivable/Payable: auto-set to reconcilable. Equity/Income/Expense: No |
| Can mix with other types in one journal entry | No -- all lines must be off-balance | Yes -- you can mix assets, expenses, etc. |
| Carries balance forward across fiscal years | Yes | Assets/Liabilities: Yes. Income/Expense: No |
| Used in product accounts | No | Income/Expense types only |
| Used in payment methods | No | Cash/Credit Card types for bank journals |

---

## The Isolation Rule (Most Important Technical Detail)

Off-balance accounts are **completely isolated** from the rest of your accounting. Odoo enforces this strictly:

**Rule 1 -- All or nothing.** If one line in a journal entry uses an off-balance account, ALL lines must use off-balance accounts. You cannot mix off-balance with regular accounts in the same entry.

**Rule 2 -- No taxes.** You cannot attach any tax to an off-balance line. These are memo entries, not taxable transactions.

**Rule 3 -- No reconciliation.** Off-balance lines cannot be reconciled against anything.

Source: [`account_move_line.py:1359-1368`](../addons/account/models/account_move_line.py#L1359)

This means off-balance entries always balance **within their own world**. They debit one off-balance account and credit another off-balance account. They never touch your real accounts.

---

## How It Appears in Reports

### Balance Sheet
Off-balance amounts appear in a dedicated **"OFF BALANCE SHEET ACCOUNTS"** section at the very bottom of the Balance Sheet, below the "Liabilities + Equity" total. This section:
- Is grouped by account
- Is foldable (can be collapsed)
- Is hidden automatically if all off-balance accounts have zero balance

Source: [`balance_sheet.xml:276-284`](../enterprise/account_reports/data/balance_sheet.xml#L276)

### Profit & Loss
Not included. Off-balance accounts never appear here.

### Trial Balance
Off-balance accounts **do appear** in the Trial Balance if they have balances. The trial balance handler has no explicit exclusion for off-balance accounts -- it shows all accounts with activity.

---

## How-To Scenarios

### How to Set Up Off-Balance Sheet Accounts
1. Go to **Accounting --> Configuration --> Chart of Accounts**
2. Click **New**
3. Set the **Type** to "Off-Balance Sheet"
4. Name it descriptively (e.g., "9100 - Guarantees Given")
5. Create at least two accounts -- you need a debit side and a credit side since entries must balance within off-balance accounts
6. Save

**Why two accounts:** Every journal entry needs at least two lines that balance. Since off-balance entries can only use off-balance accounts, you need at least two such accounts (e.g., "Guarantees Given" and "Guarantees Given - Counterpart").

### How to Record an Off-Balance Sheet Entry
1. Go to **Accounting --> Accounting --> Transactions --> Journal Entries --> New** (use a miscellaneous journal -- invoices/bills exclude off-balance accounts from their line dropdowns)
2. Add a line: select your off-balance debit account, enter the amount
3. Add a second line: select your off-balance credit account (the counterpart)
4. Both accounts MUST be "Off-Balance Sheet" type -- Odoo will reject the entry otherwise
5. Do NOT add taxes to any line
6. Post the entry

### How to Reverse an Off-Balance Entry (When Commitment Ends)
1. Open the original journal entry
2. Click **Reverse Entry** (creates a mirror entry with opposite debits/credits)
3. Post the reversal
4. If the commitment became a real liability, create a separate normal journal entry in your regular liability accounts

---

## Key Technical Details

### Account Type Definition
> [`account_account.py:64`](../addons/account/models/account_account.py#L64)

```
("off_balance", "Off-Balance Sheet")
```

The `off_balance` type maps to internal group `'off'` (derived by splitting on `_` and taking the first part). This internal group is unique -- no other account type shares it.

### Constraint Enforcement
> [`account_move_line.py:1359-1368`](../addons/account/models/account_move_line.py#L1359)

The `_check_off_balance()` constraint runs on every journal entry line and enforces all three isolation rules (all-or-nothing, no taxes, no reconciliation).

### Account-Level Constraints
> [`account_account.py:187-194`](../addons/account/models/account_account.py#L187)

At the account level, Odoo prevents setting `reconcile = True` or adding `tax_ids` on off-balance accounts. If you change an account's type to off-balance, taxes are automatically cleared.

### Domain Exclusions
Off-balance accounts are excluded from many selection dropdowns:
- **Invoice/bill line account selector** -- excluded via view domain at [`account_move_views.xml:1186`](../addons/account/views/account_move_views.xml#L1186)
- **Product income/expense account fields** -- excluded via [`product.py:8`](../addons/account/models/product.py#L8)
- **Tax posting accounts** -- excluded via [`account_tax.py:4942`](../addons/account/models/account_tax.py#L4942)
- **Reconciliation model accounts** -- excluded via [`account_reconcile_model.py:19`](../addons/account/models/account_reconcile_model.py#L19)
- **Accrual wizard accounts** -- excluded via [`account_automatic_entry_wizard.py:40`](../addons/account/wizard/account_automatic_entry_wizard.py#L40)
However, the **Journal Items tab** (the raw debit/credit entry lines) does NOT exclude off-balance accounts -- this is the intended way to create off-balance entries. The account selector there uses a company-only domain ([`account_move_views.xml:1379`](../addons/account/views/account_move_views.xml#L1379)), allowing selection of any account type including off-balance.

---

## Edge Cases and Gotchas

- **You need at least 2 off-balance accounts.** A single account is useless because entries must balance, and you can't mix with regular accounts. Always create accounts in pairs.
- **Initial balance carries forward.** Off-balance accounts behave like assets/liabilities for year-end: their balance carries into the next fiscal year. This is correct -- a guarantee doesn't disappear on January 1st.
- **No automation.** Unlike receivables/payables, off-balance accounts have no automatic matching, no payment integration, no bank reconciliation. They are purely manual.
- **Chart of accounts templates.** Many country localizations include pre-defined off-balance accounts (often in the 9xxx range). Check your localization before creating custom ones.
- **Reversal is manual.** When a commitment ends (guarantee released, lawsuit settled), you must manually create a reversal entry. Odoo won't do this automatically.

---

## Quick Reference: When Something Changes

| Event | What to Do in Off-Balance | What to Do in Regular Accounts |
|---|---|---|
| Guarantee given | Create off-balance entry | Nothing yet |
| Guarantee called (you must pay) | Reverse off-balance entry | Create real liability + payment |
| Guarantee released (no longer needed) | Reverse off-balance entry | Nothing |
| Lawsuit filed against you | Create off-balance entry for potential amount | Nothing yet |
| Lawsuit lost | Reverse off-balance entry | Create real expense + liability |
| Lawsuit won/dismissed | Reverse off-balance entry | Nothing |
| Lease signed | Create off-balance for total future payments | Nothing yet |
| Monthly rent paid | Reduce off-balance amount | Record rent expense |

---

## Related Docs

- [`INDEX.md`](INDEX.md)
- [`accounting_coa.md`](accounting_coa.md) -- account types overview, includes off-balance in the full type table
- [`accounting_fixed_costs_guide.md`](accounting_fixed_costs_guide.md) -- all 18 account types explained

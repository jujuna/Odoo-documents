# Currency Exchange & Transit Accounts

> **Module:** `account` | **Path:** [`addons/account/`](../addons/account/)
> **Odoo Apps category:** Accounting / Invoicing

## What It Does

Handles multi-currency transactions: exchange rate differences on invoice payments, and internal transfers between bank accounts in different currencies. Odoo uses a **transit account** as an intermediary for bank-to-bank transfers, and **exchange gain/loss accounts** to record currency rate differences automatically during reconciliation.

---

## Prerequisites

Before you can use multi-currency features:

1. **Enable Multi-Currencies:** General Settings > scroll to "Multi-Currencies" toggle. (This is NOT in Accounting settings -- it lives in `base_setup` as `group_multi_currency`.)
2. **Activate currencies:** Accounting > Configuration > Currencies > toggle the currencies you need (USD, EUR, etc.)
3. **Set exchange rates:** On each currency record, add the rate for today. Or enable "Automatic Currency Rates" in Accounting > Configuration > Settings > Currencies to auto-fetch from central banks.
4. **Create bank journals for each currency:** Each bank account needs its own journal with the correct currency set (e.g., "USD Bank" journal with currency = USD).

---

## Concept: Why a Transit Account?

**The problem:** You want to move $10,000 from your USD bank to your EUR bank. In Odoo, each bank has its own journal. A journal entry can only belong to ONE journal. So you cannot make a single entry that debits EUR Bank and credits USD Bank -- they are in different journals.

**The solution:** Use a middleman account (the **transit account**) that appears in BOTH journal entries:

| Step | Journal | What Happens |
|---|---|---|
| 1 | USD Bank Journal | Money leaves USD bank, goes to transit account |
| 2 | EUR Bank Journal | Money leaves transit account, enters EUR bank |

After both entries are posted, the transit account has one debit and one credit that cancel out. If exchange rates created a difference, Odoo books it to an exchange gain/loss account automatically.

---

## Configuration (One-Time Setup)

### 1. Transit Account

**Where:** Accounting > Configuration > Settings > Default Accounts > "Internal Transfer"

This is the intermediary account for bank-to-bank transfers. It is auto-created when you install your Chart of Accounts (named "Liquidity Transfer", code from `transfer_account_code_prefix`).

| Property | Value |
|---|---|
| Settings field | `transfer_account_id` on `res.config.settings` ([res_config_settings.py:71](../addons/account/models/res_config_settings.py#L71)) |
| Stored on | `res.company` ([company.py:114](../addons/account/models/company.py#L114)) |
| Account type | `asset_current` (Current Assets) |
| Must be reconcilable | Yes (`reconcile = True`) |
| Domain filter | `[('reconcile', '=', True), ('account_type', '=', 'asset_current')]` |

You usually do not need to change this. It is auto-created and assigned during Chart of Accounts installation ([chart_template.py:880-908](../addons/account/models/chart_template.py#L880-L908)).

### 2. Exchange Rate Accounts

**Where:** Accounting > Configuration > Settings > Default Accounts > "Exchange difference entries"
(Visible only when multi-currency is enabled)

| Setting | UI Label | What It Does |
|---|---|---|
| `currency_exchange_journal_id` | "Exchange Gain or Loss Journal" | Miscellaneous journal for exchange entries |
| `income_currency_exchange_account_id` | "Gain Exchange Rate Account" | Income account -- credited when rate moves in your favor |
| `expense_currency_exchange_account_id` | "Loss Exchange Rate Account" | Expense account -- debited when rate moves against you |

Source: [`company.py:134-144`](../addons/account/models/company.py#L134-L144)

If any of these is missing when Odoo tries to create an exchange difference entry, you get a `UserError` ([account_move_line.py:2960-2980](../addons/account/models/account_move_line.py#L2960-L2980)).

### 3. Outstanding Payment Accounts

Each bank journal has **Outstanding Receipts** and **Outstanding Payments** accounts on its payment method lines.

**Where to check:** Accounting > Configuration > Journals > open a bank journal > "Incoming Payments" / "Outgoing Payments" tabs > the `payment_account_id` column on each payment method line.

The chart template creates these accounts during installation ([chart_template.py:914-928](../addons/account/models/chart_template.py#L914-L928)):
- **101403 Outstanding Receipts** (for inbound payments)
- **101404 Outstanding Payments** (for outbound payments)

**But the accounts are NOT auto-assigned to payment method lines.** The `payment_account_id` field on `account.payment.method.line` is left **empty by default** in enterprise. This is intentional -- see the next section.

If `payment_account_id` is empty on a payment method line, Odoo falls back to the transit account (`company.transfer_account_id`) via [`_get_outstanding_account()`](../addons/account/models/account_payment.py#L881-L890). But this fallback only triggers in community edition or when `force_payment_move` context is set.

### 4. Community vs Enterprise: Payment Journal Entry Behavior

This is a critical difference that affects how payments, transfers, and reconciliation work.

**The code** ([account_payment.py:853-860](../addons/account/models/account_payment.py#L853-L860)):
```python
accounting_installed = self.env['account.move']._get_invoice_in_payment_state() == 'in_payment'

if (not accounting_installed and not pay.outstanding_account_id):
    outstanding_account = pay._get_outstanding_account(pay.payment_type)
    pay.outstanding_account_id = outstanding_account.id
```

| | Community (`account` only) | Enterprise (`account_accountant` installed) |
|---|---|---|
| `accounting_installed` | `False` | `True` |
| `payment_account_id` on method line | Empty (default) | Empty (default) |
| Auto-sets `outstanding_account_id`? | **Yes** -- forces it to Outstanding Receipts/Payments account | **No** -- leaves it empty |
| Payment creates journal entry? | **Yes** -- immediately on confirm | **No** -- payment is just a record, no journal entry |
| When does the journal entry get created? | On payment confirmation | During **bank statement reconciliation** (the bank reconciliation widget creates the entry) |
| Has bank reconciliation widget? | **No** | **Yes** |

**Why enterprise leaves it empty:** Enterprise has the bank reconciliation widget. The design is: register the payment first (as a record), then import bank statements, then match the statement line with the payment in the reconciliation widget. The journal entry is created at that point, giving the user full control over amounts and matching.

**If you want enterprise to behave like community** (payments create journal entries immediately): manually set `payment_account_id` on your bank journal's payment method lines:
1. Accounting > Configuration > Journals > open "BANK EUR"
2. "Incoming Payments" tab > "Manual Payment" line > set account to **Outstanding Receipts** (101403)
3. "Outgoing Payments" tab > "Manual Payment" line > set account to **Outstanding Payments** (101404)
4. Repeat for all bank journals

---

## Real-World Example 1: Paying a USD Invoice (Company Currency = GEL)

**Scenario:** Your company reports in GEL. You receive a vendor bill for $5,000 on January 15 (rate: 1 USD = 2.70 GEL). You pay on February 10 (rate: 1 USD = 2.75 GEL).

### Step 1: Record the Bill (Jan 15)

Go to Accounting > Vendors > Bills > Create.

| Field | Value |
|---|---|
| Vendor | Supplier X |
| Bill Date | January 15 |
| Currency | USD |
| Line: Product/Label | "Consulting Services" |
| Line: Price | $5,000 |

Click **Confirm**. Odoo creates this journal entry:

| Account | Debit (GEL) | Credit (GEL) | Currency | Amount |
|---|---|---|---|---|
| Expenses | 13,500 | | USD | $5,000 |
| Accounts Payable | | 13,500 | USD | -$5,000 |

Why 13,500 GEL? Because $5,000 x 2.70 = 13,500 GEL.

### Step 2: Pay the Bill (Feb 10)

Open the bill > click **Register Payment**.

| Field | Value |
|---|---|
| Amount | $5,000 |
| Date | February 10 |
| Journal | USD Bank |

Click **Create Payment**.

**In community edition**, Odoo immediately creates a journal entry:

| Account | Debit (GEL) | Credit (GEL) | Currency | Amount |
|---|---|---|---|---|
| Accounts Payable | 13,750 | | USD | $5,000 |
| Outstanding Payments | | 13,750 | USD | -$5,000 |

Why 13,750 GEL? Because $5,000 x 2.75 = 13,750 GEL (rate changed).

**In enterprise edition**, the payment is created as a record (no journal entry). The journal entry is created when you match the bank statement line with the payment in the bank reconciliation widget. The accounting result is the same -- the entry is just created at a different point in the workflow.

### Step 3: Reconciliation (Automatic)

Odoo reconciles the Accounts Payable lines from Step 1 and Step 2:

- Bill payable line: 13,500 GEL credit
- Payment payable line: 13,750 GEL debit
- **Difference: 250 GEL** (the company-currency amounts don't match because the rate changed)

Odoo auto-creates an exchange difference entry:

| Account | Debit (GEL) | Credit (GEL) |
|---|---|---|
| Exchange Loss Account | 250 | |
| Accounts Payable | | 250 |

**Result:** Payable is fully reconciled. The 250 GEL loss is in your P&L under the exchange loss account.

### How Odoo Decides Gain vs Loss

From [`_get_exchange_account()`](../addons/account/models/account_move_line.py#L2849-L2852):
- `amount_residual_to_fix > 0` --> **Loss** (uses `expense_currency_exchange_account_id`)
- `amount_residual_to_fix < 0` --> **Gain** (uses `income_currency_exchange_account_id`)

---

## Real-World Example 2: Internal Transfer USD to EUR (Company Currency = USD)

**Scenario:** Your company (USD) needs to move $138.66 from the USD bank to the EUR bank. The bank gives you EUR 120. Today's rate: 1 EUR = 1.1555 USD.

### Important: Odoo 19 Changes

Two key differences from v17/v18:

1. **No auto-paired transfers.** In v17/v18, clicking "Internal Transfer" auto-created a paired payment on the destination journal. In v19, the `is_internal_transfer` field, `destination_journal_id` field, and `_create_paired_internal_transfer_payment()` method are all removed. The `paired_internal_transfer_payment_id` field still exists ([account_payment.py:67](../addons/account/models/account_payment.py#L67)) but no code auto-populates it.

2. **Enterprise payments don't create journal entries.** With `account_accountant` installed, `payment_account_id` is empty on payment method lines by default. Payments are just records -- the journal entry is created during bank statement reconciliation (see Section 4 above).

**Result:** You must create both sides manually via bank statement lines.

### Method A: Bank Statement Reconciliation (Enterprise Flow)

This is what you'll actually do in enterprise v19. Tested and verified.

#### Step 1: Create Bank Statement Line on EUR Bank (Money Arrives)

Go to Accounting > Dashboard > **BANK EUR** card > click to open > **New Transaction**.

| Field | Value |
|---|---|
| Date | March 23, 2026 |
| Label | "Internal transfer from USD Bank" |
| Amount | **120.00** (positive = money coming in) |

When Odoo opens the **reconciliation widget**, choose the transit account (101701 Liquidity Transfer) as the counterpart. Validate.

Odoo creates journal entry (e.g., BNK2/2026/00002):

| Account | Debit (USD) | Credit (USD) | Currency | Amount |
|---|---|---|---|---|
| Bank EUR (101405) | 138.66 | | EUR | 120.00 |
| Liquidity Transfer (101701) | | 138.66 | EUR | -120.00 |

EUR 120 x 1.1555 = $138.66.

#### Step 2: Create Bank Statement Line on USD Bank (Money Leaves)

Go to Accounting > Dashboard > **Bank** (USD) card > click to open > **New Transaction**.

| Field | Value |
|---|---|
| Date | March 23, 2026 |
| Label | "Internal transfer to EUR Bank" |
| Amount | **-138.66** (negative = money going out) |

In the reconciliation widget, match with the transit account (101701). Odoo will suggest the open transit line from Step 1. Validate.

Odoo creates journal entry (e.g., BNK1/2026/00011):

| Account | Debit (USD) | Credit (USD) | Currency | Amount |
|---|---|---|---|---|
| Liquidity Transfer (101701) | 138.66 | | EUR | 120.00 |
| Bank USD (101401) | | 138.66 | USD | -138.66 |

#### Step 3: Transit Account Auto-Reconciles

After Step 2, the transit account has two lines that Odoo reconciles:

| Entry | Account | Debit | Credit | Reconciled |
|---|---|---|---|---|
| BNK2/2026/00002 (EUR Bank) | Liquidity Transfer (101701) | | $138.66 | Yes |
| BNK1/2026/00011 (USD Bank) | Liquidity Transfer (101701) | $138.66 | | Yes |

Transit balance = $138.66 - $138.66 = **$0**. Fully reconciled.

**No exchange difference** in this case because both entries used the same date = same rate. If the dates differed and the EUR/USD rate changed, Odoo would auto-create an exchange gain/loss entry for the difference.

#### What It Looks Like End-to-End

```
USD Bank (101401)  ──$138.66──>  Transit (101701)  ──$138.66──>  EUR Bank (101405)
  Credit $138.66                  Debit + Credit                  Debit $138.66
  (money left)                    = $0 (reconciled)               (money arrived)
```

### Method B: Manual Journal Entries (More Control)

If you want to skip bank statements and create the accounting entries directly:

#### Step 1: Journal Entry on USD Bank Journal

Go to Accounting > Accounting > Journal Entries > Create.

| Field | Value |
|---|---|
| Journal | Bank (USD) |
| Date | March 23, 2026 |

Lines:

| Account | Debit | Credit | Currency | Amount |
|---|---|---|---|---|
| Liquidity Transfer (101701) | 138.66 | | EUR | 120.00 |
| Bank USD (101401) | | 138.66 | USD | -138.66 |

#### Step 2: Journal Entry on EUR Bank Journal

Create another journal entry:

| Field | Value |
|---|---|
| Journal | BANK EUR |
| Date | March 23, 2026 |

Lines:

| Account | Debit | Credit | Currency | Amount |
|---|---|---|---|---|
| Bank EUR (101405) | 138.66 | | EUR | 120.00 |
| Liquidity Transfer (101701) | | 138.66 | EUR | -120.00 |

#### Step 3: Reconcile the Transit Account

Go to Accounting > Accounting > Reconciliation. Filter for the transit account (101701). Match the two lines:

- Transit debit: $138.66 (from USD bank entry)
- Transit credit: $138.66 (from EUR bank entry)

If dates differ and rate changed, Odoo auto-books the difference to exchange gain/loss.

**Result:** Transit account fully reconciled (balance = 0).

### Method C: "Internal Transfer" Button + Bank Statements

The dashboard "Internal Transfer" button ([account_journal_dashboard.py:1082-1086](../addons/account/models/account_journal_dashboard.py#L1082-L1086)) creates a payment record (no journal entry in enterprise). You still need to:
1. Import or create bank statement lines for both banks
2. Match each statement line in the reconciliation widget

This method adds a payment record for tracking but does not save any steps compared to Method A.

---

## Real-World Example 3: Customer Pays in EUR for a USD Invoice

**Scenario:** You invoice a customer $3,000 on March 1 (rate: 1 USD = 2.70 GEL). Customer pays EUR 2,760 on March 15 (rate: 1 EUR = 2.94 GEL, 1 USD = 2.75 GEL).

### What Happens

1. **Invoice posted (March 1):** Debit Receivable $3,000 = 8,100 GEL / Credit Revenue 8,100 GEL
2. **Payment received (March 15):** Debit Bank EUR 2,760 = 8,114 GEL / Credit Receivable 8,114 GEL
3. **Reconciliation:** Receivable has 8,100 GEL debit and 8,114 GEL credit -> 14 GEL difference
4. **Exchange entry auto-created:** Debit Receivable 14 GEL / Credit Exchange Gain 14 GEL

---

## Exchange Gain/Loss -- Deep Dive

### What Is It?

Exchange gain/loss is an accounting adjustment that Odoo creates **automatically** when the exchange rate changes between two dates: the date you recorded a transaction and the date you settled it.

There are two types:

| Type | When Created | Permanent? | Who Creates It |
|---|---|---|---|
| **Realized** | When reconciling (payment matches invoice) | Yes -- stays forever | Automatic during reconciliation ([account_move_line.py:2295-2365](../addons/account/models/account_move_line.py#L2295)) |
| **Unrealized** | At period-end (month/quarter close) | No -- reversed next day | Manual via Multicurrency Revaluation Report (enterprise only) ([multicurrency_revaluation.py:169-179](../enterprise/account_reports/wizard/multicurrency_revaluation.py#L169)) |

---

### Why Does It Exist?

Every foreign-currency transaction in Odoo is stored in **two amounts**:

1. `amount_currency` -- the original foreign currency amount (e.g., $5,000)
2. `balance` (debit/credit) -- the company-currency equivalent at the transaction date (e.g., 13,500 GEL)

When you pay that $5,000 invoice later, the rate may have changed. The payment is $5,000 in foreign currency (same), but 13,750 GEL in company currency (different). The Receivable/Payable account now has:

- 13,500 GEL from the invoice
- 13,750 GEL from the payment

These don't cancel out. The 250 GEL difference must go somewhere. That is the exchange gain or loss.

---

### Realized Gain/Loss (Automatic on Reconciliation)

#### When It Triggers

Every time Odoo reconciles two journal item lines (matching a payment to an invoice, matching transit account lines, etc.), it checks: **is there a company-currency mismatch after the foreign currency amounts are fully matched?**

This check happens inside [`_prepare_reconciliation_single_partial()`](../addons/account/models/account_move_line.py#L2295). It can be skipped with context flags `no_exchange_difference` or `no_exchange_difference_no_recursive`.

#### Two Scenarios

**Scenario 1: Reconciliation currency = Company currency** ([lines 2300-2312](../addons/account/models/account_move_line.py#L2300))

Both lines are denominated in company currency for the reconciliation. The exchange difference is on the **foreign currency side** (`amount_residual_currency`). This happens when one of the lines is in company currency and the other in a foreign currency.

**Scenario 2: Reconciliation currency != Company currency** ([lines 2314-2355](../addons/account/models/account_move_line.py#L2314))

Both lines share a foreign reconciliation currency. The exchange difference is on the **company currency side** (`amount_residual`). This is the most common case -- e.g., a USD invoice reconciled with a USD payment when the company currency is GEL.

Two sub-cases:
- **Fully matched line:** Exchange amount = remaining company-currency balance after subtracting what was reconciled
- **Partially matched line:** Exchange amount = difference between what was actually debited/credited in company currency vs. what the reconciliation "consumed" -- ensures the rate between `amount_currency` and `balance` stays consistent on the remaining residual

#### What Odoo Creates

A journal entry with exactly **two lines per exchange difference** ([`_prepare_exchange_difference_move_vals()`](../addons/account/models/account_move_line.py#L2854)):

| Line | Account | Purpose |
|---|---|---|
| 1. Adjustment | Same as original line (e.g., Accounts Payable) | Fixes the company-currency balance so it reconciles to zero |
| 2. Counterpart | Exchange Gain or Exchange Loss account | Records the impact on P&L |

The entry is posted to the **Exchange Gain or Loss Journal** (`currency_exchange_journal_id`).

#### How Odoo Decides Gain vs Loss

From [`_get_exchange_account()`](../addons/account/models/account_move_line.py#L2849):

```python
def _get_exchange_account(self, company, amount):
    if amount > 0.0:
        return company.expense_currency_exchange_account_id   # Loss
    return company.income_currency_exchange_account_id         # Gain
```

| `amount_residual_to_fix` | Meaning | Account Used |
|---|---|---|
| > 0 (positive) | You owe more in company currency than expected | **Loss** (`expense_currency_exchange_account_id`) |
| < 0 (negative) | You owe less in company currency than expected | **Gain** (`income_currency_exchange_account_id`) |

#### Concrete Example: Loss

Invoice: $5,000 at rate 2.70 = 13,500 GEL (Payable credit).
Payment: $5,000 at rate 2.75 = 13,750 GEL (Payable debit).

Payable has: 13,750 debit - 13,500 credit = **250 GEL residual** (positive).
Positive residual = **Loss**. Odoo creates:

| Account | Debit (GEL) | Credit (GEL) |
|---|---|---|
| Exchange Loss | 250 | |
| Accounts Payable | | 250 |

Now Payable: 13,750 debit - 13,500 credit - 250 credit = **0**. Fully reconciled.
The 250 GEL shows as an expense in your Profit & Loss.

#### Concrete Example: Gain

Invoice: $5,000 at rate 2.75 = 13,750 GEL (Payable credit).
Payment: $5,000 at rate 2.70 = 13,500 GEL (Payable debit).

Payable has: 13,500 debit - 13,750 credit = **-250 GEL residual** (negative).
Negative residual = **Gain**. Odoo creates:

| Account | Debit (GEL) | Credit (GEL) |
|---|---|---|
| Accounts Payable | 250 | |
| Exchange Gain | | 250 |

Now Payable: 13,500 debit + 250 debit - 13,750 credit = **0**. Fully reconciled.
The 250 GEL shows as income in your Profit & Loss.

#### When NO Exchange Difference Occurs

- Invoice and payment on the **same date** (same rate)
- Both lines in **company currency** (no foreign currency involved)
- The company-currency amounts happen to **match exactly** despite different dates (rare but possible)

---

### Unrealized Gain/Loss (Period-End Revaluation -- Enterprise Only)

#### What Problem It Solves

At month-end, you have open invoices in foreign currencies. The rates have changed since you recorded them. Your balance sheet shows these receivables/payables at the **old rate**, which no longer reflects reality.

Accounting standards (IAS 21, ASC 830) often require you to **revalue** these open balances at the current rate and show the difference as a provisional gain or loss.

#### Where to Find It

Accounting > Reporting > Multicurrency Revaluation

Module: `account_reports` (enterprise). Model: [`account.multicurrency.revaluation.report.handler`](../enterprise/account_reports/models/account_multicurrency_revaluation_report.py#L11)

#### What It Shows

For each account + currency combination with an open balance:

| Column | Meaning |
|---|---|
| Balance in Foreign Currency | Open amount in the foreign currency (e.g., $5,000) |
| Balance at Operation Rate | Company-currency value at the rate when the transaction was recorded |
| Balance at Current Rate | Company-currency value at today's rate |
| Adjustment | Difference = Balance at Current Rate - Balance at Operation Rate |

The adjustment formula ([line 248-252](../enterprise/account_reports/models/account_multicurrency_revaluation_report.py#L248)):
```
adjustment = (amount_currency / current_rate) - (amount_currency / operation_rate)
```

#### Which Accounts Are Included

The report includes accounts where ([lines 305-312](../enterprise/account_reports/models/account_multicurrency_revaluation_report.py#L305)):
- Account has a **non-company currency** set, OR
- Account is **Receivable/Payable** and the journal item has a foreign currency

It excludes:
- Income, expense, and off-balance accounts
- Accounts the user has manually excluded via the "Excluded Accounts" toggle
- Lines from exchange difference moves themselves (prevents double-counting)

#### How to Create Revaluation Entries

1. Open the Multicurrency Revaluation report
2. Review adjustments per account + currency
3. Click **Adjustment Entry** button
4. Fill the wizard:

| Field | Purpose |
|---|---|
| `journal_id` | Journal for the revaluation entry (stored on `res.company` as `account_revaluation_journal_id`, [res_company.py:35](../enterprise/account_reports/models/res_company.py#L35)) |
| `expense_provision_account_id` | Where negative adjustments go ("Expense Provision Account", [res_company.py:36](../enterprise/account_reports/models/res_company.py#L36)) |
| `income_provision_account_id` | Where positive adjustments go ("Income Provision Account", [res_company.py:37](../enterprise/account_reports/models/res_company.py#L37)) |
| `date` | Revaluation date (typically month-end) |
| `reversal_date` | Auto-reversal date (typically next day) |

5. Click **Create Entry**

#### What It Creates

The wizard ([`create_entries()`](../enterprise/account_reports/wizard/multicurrency_revaluation.py#L169)) does two things:

1. **Posts the revaluation entry** with lines for each account + currency:

| Line | Account | Amount |
|---|---|---|
| Adjustment | Original account (e.g., Receivable) | The adjustment amount |
| Provision | Expense/Income Provision account | Opposite of adjustment |

2. **Immediately creates and posts a reversal** dated `reversal_date` (typically the next day)

This is the key difference from realized gain/loss: **the revaluation is temporary**. It appears in reports for the period-end, then reverses itself. When the invoice is actually paid, the realized gain/loss takes over.

#### Realized vs Unrealized -- Side by Side

| Aspect | Realized | Unrealized |
|---|---|---|
| **Trigger** | Payment reconciled with invoice | Manual period-end action |
| **Automatic?** | Yes -- happens during reconciliation | No -- user must run the report and click |
| **Permanent?** | Yes | No -- auto-reversed next period |
| **Accounts** | Exchange Gain/Loss (P&L) | Provision accounts (can be P&L or Balance Sheet) |
| **When rate changes after?** | No further effect -- settled | Next period-end creates new revaluation |
| **Open invoices affected?** | Only the one being paid | All open balances in that currency |

#### Example: Unrealized Loss

March 1: Invoice $10,000 at rate 2.70 = 27,000 GEL.
March 31 (month-end): Rate is now 2.80. At current rate, $10,000 = 28,000 GEL.
Adjustment = 28,000 - 27,000 = **1,000 GEL** (you'd need to pay more GEL now).

Revaluation entry (March 31):

| Account | Debit (GEL) | Credit (GEL) |
|---|---|---|
| Accounts Payable | 1,000 | |
| Expense Provision | | 1,000 |

Reversal entry (April 1):

| Account | Debit (GEL) | Credit (GEL) |
|---|---|---|
| Expense Provision | 1,000 | |
| Accounts Payable | | 1,000 |

When the invoice is actually paid in April, the real exchange difference is captured as a realized gain/loss through normal reconciliation.

---

### Exchange Gain/Loss on Internal Transfers

When you transfer money between banks in different currencies via the transit account:

- **Same date, same rate:** Transit lines match exactly. No exchange difference. This is the typical case.
- **Different dates:** If you record the outgoing side on Monday and the incoming side on Wednesday, and the rate changed, the transit account lines will have different company-currency amounts. Odoo creates an exchange gain/loss entry when reconciling the transit lines.
- **Bank rate differs from Odoo rate:** If your bank gave you EUR 73.50 for $80, but Odoo's rate would have given EUR 73.48, the difference is captured through the transit account reconciliation as an exchange gain/loss.

---

### How Exchange Differences Are Created (Technical Flow)

```
reconcile() called on two journal items
    |
    v
_prepare_reconciliation_single_partial()
    |-- Computes partial amounts in both currencies
    |-- Checks: is there a company-currency mismatch?
    |-- If yes: prepares exchange_values via
    |       _prepare_exchange_difference_move_vals()
    |           |-- Determines gain vs loss (_get_exchange_account())
    |           |-- Builds 2-line journal entry values
    |           |-- Returns {move_values, to_reconcile}
    v
_reconcile_plan_with_sync()
    |-- Collects all exchange_values from all partials
    |-- Calls _create_exchange_difference_moves()
    |       |-- Validates: journal + accounts configured? (UserError if not)
    |       |-- Creates moves with context(no_exchange_difference=True)
    |       |-- Posts the moves
    |       |-- Returns exchange_moves recordset
    |-- Links each exchange_move to its partial via exchange_move_id
    v
Done. Exchange entries posted and linked.
```

#### Unlinking / Unreconciling

When a partial reconciliation is deleted ([`account_partial_reconcile.py:104-146`](../addons/account/models/account_partial_reconcile.py#L104)):

1. Collects `exchange_move_id` from each partial being deleted
2. If exchange move is **posted**: creates a reversal entry (cancellation)
3. If exchange move is **draft**: deletes it directly
4. Removes the `full_reconcile_id` link
5. Updates matching numbers

This ensures exchange entries are always cleaned up when you undo a reconciliation.

#### Context Flags

| Flag | Where Set | Purpose |
|---|---|---|
| `no_exchange_difference` | [`account_move_line.py:2983`](../addons/account/models/account_move_line.py#L2983) | Prevents recursive exchange difference when creating/posting exchange moves |
| `no_exchange_difference_no_recursive` | [`account_move_line.py:2297`](../addons/account/models/account_move_line.py#L2297) | Controls whether cash basis tax moves also get exchange differences |

---

## Configuration Reference

| Setting | UI Path | Field | Effect |
|---|---|---|---|
| Multi-Currencies | General Settings > Multi-Currencies | `group_multi_currency` | Enables currency features globally |
| Transit Account | Accounting Settings > Default Accounts > "Internal Transfer" | `transfer_account_id` | Intermediary for bank-to-bank transfers |
| Exchange Journal | Accounting Settings > Default Accounts > Exchange difference entries | `currency_exchange_journal_id` | Journal for exchange entries |
| Exchange Gain | Accounting Settings > Default Accounts > Exchange difference entries | `income_currency_exchange_account_id` | Where favorable rate differences go |
| Exchange Loss | Accounting Settings > Default Accounts > Exchange difference entries | `expense_currency_exchange_account_id` | Where unfavorable rate differences go |
| Auto Currency Rates | Accounting Settings > Currencies | `module_currency_rate_live` | Auto-fetch rates from central banks |
| Revaluation Journal | (stored on company) | `account_revaluation_journal_id` | Journal for unrealized gain/loss entries (enterprise) |
| Expense Provision Account | Multicurrency Revaluation wizard | `account_revaluation_expense_provision_account_id` | Where unrealized losses go (enterprise) |
| Income Provision Account | Multicurrency Revaluation wizard | `account_revaluation_income_provision_account_id` | Where unrealized gains go (enterprise) |

**Visibility:** The "Default Accounts" block requires `account.group_account_user` group ([view line 255](../addons/account/views/res_config_settings_views.xml#L255)). The "Exchange difference entries" section is hidden unless multi-currency is enabled ([view line 257](../addons/account/views/res_config_settings_views.xml#L257)). The Multicurrency Revaluation report requires `account_reports` (enterprise).

---

## Key Models & Methods

### Models

| Model | Field | Purpose |
|---|---|---|
| `res.company` | `transfer_account_id` | Transit account for internal transfers ([company.py:114](../addons/account/models/company.py#L114)) |
| `res.company` | `currency_exchange_journal_id` | Exchange difference journal ([company.py:134](../addons/account/models/company.py#L134)) |
| `res.company` | `income_currency_exchange_account_id` | Exchange gain account ([company.py:135](../addons/account/models/company.py#L135)) |
| `res.company` | `expense_currency_exchange_account_id` | Exchange loss account ([company.py:140](../addons/account/models/company.py#L140)) |
| `account.payment` | `paired_internal_transfer_payment_id` | Legacy field for paired transfers -- not auto-populated in v19 ([account_payment.py:67](../addons/account/models/account_payment.py#L67)) |
| `account.payment` | `outstanding_account_id` | Computed from payment method line, used as liquidity account in the journal entry ([account_payment.py:122](../addons/account/models/account_payment.py#L122)) |
| `account.payment` | `destination_account_id` | Receivable/Payable based on partner type ([account_payment.py:129](../addons/account/models/account_payment.py#L129)) |
| `account.partial.reconcile` | `exchange_move_id` | Links a partial reconciliation to its exchange difference entry ([account_partial_reconcile.py:23](../addons/account/models/account_partial_reconcile.py#L23)) |
| `account.move` | `exchange_diff_partial_ids` | Inverse: partials that created this exchange move ([account_move.py:197](../addons/account/models/account_move.py#L197)) |
| `res.company` | `account_revaluation_journal_id` | Journal for unrealized revaluation entries ([res_company.py:35](../enterprise/account_reports/models/res_company.py#L35)) |
| `res.company` | `account_revaluation_expense_provision_account_id` | Provision account for unrealized losses ([res_company.py:36](../enterprise/account_reports/models/res_company.py#L36)) |
| `res.company` | `account_revaluation_income_provision_account_id` | Provision account for unrealized gains ([res_company.py:37](../enterprise/account_reports/models/res_company.py#L37)) |
| `account.account` | `exclude_provision_currency_ids` | Currencies excluded from revaluation for this account ([account.py:13](../enterprise/account_reports/models/account.py#L13)) |

### Methods

| Method | Location | What It Does |
|---|---|---|
| `_prepare_move_line_default_vals()` | [account_payment.py:280](../addons/account/models/account_payment.py#L280) | Builds the 2 journal lines for a payment (outstanding + destination) |
| `_get_outstanding_account()` | [account_payment.py:881](../addons/account/models/account_payment.py#L881) | Gets outstanding account from chart template, falls back to `transfer_account_id` |
| `_get_exchange_journal()` | [account_move_line.py:2846](../addons/account/models/account_move_line.py#L2846) | Returns `company.currency_exchange_journal_id` |
| `_get_exchange_account()` | [account_move_line.py:2849](../addons/account/models/account_move_line.py#L2849) | Returns gain or loss account based on residual sign |
| `_prepare_exchange_difference_move_vals()` | [account_move_line.py:2854](../addons/account/models/account_move_line.py#L2854) | Builds the exchange difference journal entry (2 lines per difference) |
| `_create_exchange_difference_moves()` | [account_move_line.py:2943](../addons/account/models/account_move_line.py#L2943) | Validates config, creates and posts exchange difference entries |
| `_prepare_reconciliation_single_partial()` | [account_move_line.py:2295](../addons/account/models/account_move_line.py#L2295) | Computes exchange difference amounts during reconciliation |
| `_reconcile_plan_with_sync()` | [account_move_line.py:2735](../addons/account/models/account_move_line.py#L2735) | Links exchange moves to partials via `exchange_move_id` |
| `_get_move_vals()` (revaluation) | [multicurrency_revaluation.py:108](../enterprise/account_reports/wizard/multicurrency_revaluation.py#L108) | Builds unrealized gain/loss journal entry from report data |
| `create_entries()` (revaluation) | [multicurrency_revaluation.py:169](../enterprise/account_reports/wizard/multicurrency_revaluation.py#L169) | Creates revaluation entry + auto-reversal |

---

## Edge Cases & Gotchas

- **Missing exchange accounts:** If `currency_exchange_journal_id`, `income_currency_exchange_account_id`, or `expense_currency_exchange_account_id` is not set, reconciling multi-currency lines raises a `UserError`.

- **Transit account must be reconcilable:** The `transfer_account_id` domain enforces `reconcile=True` and `account_type='asset_current'`. If you pick a non-reconcilable account, the transit balance will never zero out.

- **"Allow Reconciliation" is list-view only:** The `reconcile` toggle is NOT in the account form view. It only appears in the Chart of Accounts **list view** as a column ([view_account_list:106](../addons/account/views/account_account_views.xml#L106)). Hidden for `asset_cash`, `liability_credit_card`, and `off_balance` types.

- **v19 removed auto-paired transfers:** The `is_internal_transfer` field, `destination_journal_id` field, and `_create_paired_internal_transfer_payment()` method from v17/v18 do not exist in v19. You must create both sides of an internal transfer manually.

- **Enterprise payments have no journal entry by default:** With `account_accountant` installed, `payment_account_id` is empty on payment method lines. Payments are records only -- journal entries are created during bank statement reconciliation. This is by design. To change this, manually set outstanding accounts on the journal's payment method lines (see Section 4 in Configuration).

- **Outstanding account fallback (community only):** If no `payment_account_id` is set on the payment method line, `_get_outstanding_account()` falls back to `company.transfer_account_id` ([line 886](../addons/account/models/account_payment.py#L886)). This fallback only triggers in community edition (`accounting_installed = False`) or with `force_payment_move` context.

- **`no_exchange_difference` context flag:** Odoo creates exchange moves with `context(no_exchange_difference=True)` to prevent infinite recursion ([line 2983](../addons/account/models/account_move_line.py#L2983)).

- **Reversal cascades:** When a partial reconciliation is unreconciled, its linked `exchange_move_id` is automatically reversed ([account_partial_reconcile.py:118](../addons/account/models/account_partial_reconcile.py#L118)).

- **Exchange difference is per-line:** Each reconciled line gets its own exchange difference entry lines. A single exchange move can contain lines for multiple reconciled items ([loop at line 2885](../addons/account/models/account_move_line.py#L2885)).

---

## Related Docs

- [`INDEX.md`](INDEX.md)
- [`accounting_coa.md`](accounting_coa.md) -- account types referenced by exchange accounts
- [`accounting_fixed_costs_guide.md`](accounting_fixed_costs_guide.md) -- reconciliation mechanics
- [`accounting_migration.md`](accounting_migration.md) -- opening balances in multi-currency setups

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

Each bank journal has **Outstanding Receipts** and **Outstanding Payments** accounts on its payment method lines. These are auto-created by the chart template ([chart_template.py:914-928](../addons/account/models/chart_template.py#L914-L928)).

**Where to check:** Open a bank journal > "Incoming Payments" / "Outgoing Payments" tabs > the `payment_account_id` column on each payment method line.

If `payment_account_id` is empty on a payment method line, Odoo falls back to the transit account (`company.transfer_account_id`) via [`_get_outstanding_account()`](../addons/account/models/account_payment.py#L881-L890).

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

Click **Create Payment**. Odoo creates:

| Account | Debit (GEL) | Credit (GEL) | Currency | Amount |
|---|---|---|---|---|
| Accounts Payable | 13,750 | | USD | $5,000 |
| Outstanding Payments | | 13,750 | USD | -$5,000 |

Why 13,750 GEL? Because $5,000 x 2.75 = 13,750 GEL (rate changed).

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

## Real-World Example 2: Internal Transfer USD to EUR (Company Currency = GEL)

**Scenario:** Your company (GEL) needs to move $10,000 from the USD bank account to the EUR bank account. The bank gives you EUR 9,200. Today's rates: 1 USD = 2.70 GEL, 1 EUR = 2.94 GEL.

### Important: Odoo 19 Change

In Odoo 17/18, clicking "Internal Transfer" auto-created a paired payment on the destination journal. **In Odoo 19, this auto-pairing was removed.** The `is_internal_transfer` field and `destination_journal_id` field no longer exist on `account.payment`. You create each side manually or through bank statement reconciliation.

The `paired_internal_transfer_payment_id` field still exists ([account_payment.py:67](../addons/account/models/account_payment.py#L67)) but no code in v19 auto-populates it.

### Method A: Two Payments (Simplest)

#### Step 1: Create the Outbound Payment (USD Side)

Go to Accounting > Dashboard > USD Bank card > click the vertical dots menu > **Internal Transfer**.

This opens a payment form with partner pre-set to your own company ([account_journal_dashboard.py:1082-1086](../addons/account/models/account_journal_dashboard.py#L1082-L1086)).

| Field | Value |
|---|---|
| Payment Type | Send Money |
| Partner | Your Company (auto-filled) |
| Amount | 10,000 |
| Currency | USD |
| Date | March 23, 2026 |
| Journal | USD Bank |

Click **Confirm**. Journal entry created:

| Account | Debit (GEL) | Credit (GEL) | Currency | Amount |
|---|---|---|---|---|
| Outstanding Payments | | 27,000 | USD | -$10,000 |
| Destination Account (*) | 27,000 | | USD | $10,000 |

(*) The destination account depends on `partner_type`: if `customer` it's the company's Receivable; if `supplier` it's the company's Payable.

$10,000 x 2.70 = 27,000 GEL.

#### Step 2: Create the Inbound Payment (EUR Side)

Go to Accounting > Dashboard > EUR Bank card > create a new payment (or use "Internal Transfer" and switch to "Receive Money").

| Field | Value |
|---|---|
| Payment Type | Receive Money |
| Partner | Your Company |
| Amount | 9,200 |
| Currency | EUR |
| Date | March 23, 2026 |
| Journal | EUR Bank |

Click **Confirm**. Journal entry created:

| Account | Debit (GEL) | Credit (GEL) | Currency | Amount |
|---|---|---|---|---|
| Outstanding Receipts | 27,048 | | EUR | EUR 9,200 |
| Destination Account (*) | | 27,048 | EUR | -EUR 9,200 |

EUR 9,200 x 2.94 = 27,048 GEL.

#### Step 3: Reconcile the Destination Account Lines

Both payments posted to the same destination account (the company's Receivable or Payable). Go to Accounting > Accounting > Reconciliation, or use the "Payment Matching" button on the payment form (enterprise).

Match the two destination account lines:
- Line 1: 27,000 GEL debit (from USD payment)
- Line 2: 27,048 GEL credit (from EUR payment)
- **Difference: 48 GEL**

Odoo auto-creates an exchange difference entry:

| Account | Debit (GEL) | Credit (GEL) |
|---|---|---|
| Destination Account | 48 | |
| Exchange Gain Account | | 48 |

(It's a gain because converting $10,000 -> EUR 9,200 at today's rates results in more GEL on the EUR side.)

#### Step 4: Match with Bank Statements

When you import bank statements:
- USD bank statement shows -$10,000 outflow -> match with Payment 1's Outstanding Payments line
- EUR bank statement shows +EUR 9,200 inflow -> match with Payment 2's Outstanding Receipts line

### Method B: Manual Journal Entry (More Control)

If you want to use the transit account directly:

#### Step 1: Journal Entry on USD Bank Journal

Go to Accounting > Accounting > Journal Entries > Create.

| Field | Value |
|---|---|
| Journal | USD Bank |
| Date | March 23, 2026 |

Lines:

| Account | Debit | Credit | Currency | Amount |
|---|---|---|---|---|
| Transit Account (1017) | 27,000 | | USD | $10,000 |
| USD Bank Account | | 27,000 | USD | -$10,000 |

#### Step 2: Journal Entry on EUR Bank Journal

Create another journal entry:

| Field | Value |
|---|---|
| Journal | EUR Bank |
| Date | March 23, 2026 |

Lines:

| Account | Debit | Credit | Currency | Amount |
|---|---|---|---|---|
| EUR Bank Account | 27,048 | | EUR | EUR 9,200 |
| Transit Account (1017) | | 27,048 | EUR | -EUR 9,200 |

#### Step 3: Reconcile the Transit Account

Go to Accounting > Accounting > Reconciliation. Filter for the transit account. Match the two lines:

- Transit debit: 27,000 GEL (USD side)
- Transit credit: 27,048 GEL (EUR side)
- Difference: 48 GEL -> auto-booked to exchange gain/loss

**Result:** Transit account is fully reconciled (balance = 0). The 48 GEL exchange gain appears in P&L.

### Method C: Bank Statement Reconciliation

If you import bank statements for both banks, Odoo can help you match the lines during reconciliation. Create the payments first (or let the bank statement wizard create them), then match the transit/destination lines.

---

## Real-World Example 3: Customer Pays in EUR for a USD Invoice

**Scenario:** You invoice a customer $3,000 on March 1 (rate: 1 USD = 2.70 GEL). Customer pays EUR 2,760 on March 15 (rate: 1 EUR = 2.94 GEL, 1 USD = 2.75 GEL).

### What Happens

1. **Invoice posted (March 1):** Debit Receivable $3,000 = 8,100 GEL / Credit Revenue 8,100 GEL
2. **Payment received (March 15):** Debit Bank EUR 2,760 = 8,114 GEL / Credit Receivable 8,114 GEL
3. **Reconciliation:** Receivable has 8,100 GEL debit and 8,114 GEL credit -> 14 GEL difference
4. **Exchange entry auto-created:** Debit Receivable 14 GEL / Credit Exchange Gain 14 GEL

---

## How Exchange Differences Are Created (Technical)

When Odoo reconciles journal item lines, it calls [`_prepare_exchange_difference_move_vals()`](../addons/account/models/account_move_line.py#L2854-L2940). This method:

1. Checks if there's a residual `amount_residual` (company currency difference) after matching
2. If the residual is zero -> no exchange entry needed
3. If non-zero -> creates a 2-line journal entry:

| Line | Account | Amount |
|---|---|---|
| Counterpart | Same account as the original line (e.g., Receivable) | The residual difference |
| Exchange | Exchange Gain or Loss account | Opposite of the residual |

The entry is posted to the **Exchange Gain or Loss Journal** (`currency_exchange_journal_id`). Created and posted via [`_create_exchange_difference_moves()`](../addons/account/models/account_move_line.py#L2942).

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

**Visibility:** The "Default Accounts" block requires `account.group_account_user` group ([view line 255](../addons/account/views/res_config_settings_views.xml#L255)). The "Exchange difference entries" section is hidden unless multi-currency is enabled ([view line 257](../addons/account/views/res_config_settings_views.xml#L257)).

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

### Methods

| Method | Location | What It Does |
|---|---|---|
| `_prepare_move_line_default_vals()` | [account_payment.py:280](../addons/account/models/account_payment.py#L280) | Builds the 2 journal lines for a payment (outstanding + destination) |
| `_get_outstanding_account()` | [account_payment.py:881](../addons/account/models/account_payment.py#L881) | Gets outstanding account from chart template, falls back to `transfer_account_id` |
| `_get_exchange_account()` | [account_move_line.py:2849](../addons/account/models/account_move_line.py#L2849) | Returns gain or loss account based on residual sign |
| `_prepare_exchange_difference_move_vals()` | [account_move_line.py:2854](../addons/account/models/account_move_line.py#L2854) | Builds the exchange difference journal entry |
| `_create_exchange_difference_moves()` | [account_move_line.py:2942](../addons/account/models/account_move_line.py#L2942) | Creates and posts exchange difference entries |

---

## Edge Cases & Gotchas

- **Missing exchange accounts:** If `currency_exchange_journal_id`, `income_currency_exchange_account_id`, or `expense_currency_exchange_account_id` is not set, reconciling multi-currency lines raises a `UserError`.

- **Transit account must be reconcilable:** The `transfer_account_id` domain enforces `reconcile=True` and `account_type='asset_current'`. If you pick a non-reconcilable account, the transit balance will never zero out.

- **"Allow Reconciliation" is list-view only:** The `reconcile` toggle is NOT in the account form view. It only appears in the Chart of Accounts **list view** as a column ([view_account_list:106](../addons/account/views/account_account_views.xml#L106)). Hidden for `asset_cash`, `liability_credit_card`, and `off_balance` types.

- **v19 removed auto-paired transfers:** The `is_internal_transfer` field, `destination_journal_id` field, and `_create_paired_internal_transfer_payment()` method from v17/v18 do not exist in v19. You must create both sides of an internal transfer manually.

- **Outstanding account fallback:** If no `payment_account_id` is set on the payment method line, `_get_outstanding_account()` falls back to `company.transfer_account_id` ([line 886](../addons/account/models/account_payment.py#L886)).

- **`no_exchange_difference` context flag:** Odoo creates exchange moves with `context(no_exchange_difference=True)` to prevent infinite recursion ([line 2983](../addons/account/models/account_move_line.py#L2983)).

- **Reversal cascades:** When a partial reconciliation is unreconciled, its linked `exchange_move_id` is automatically reversed ([account_partial_reconcile.py:118](../addons/account/models/account_partial_reconcile.py#L118)).

- **Exchange difference is per-line:** Each reconciled line gets its own exchange difference entry lines. A single exchange move can contain lines for multiple reconciled items ([loop at line 2885](../addons/account/models/account_move_line.py#L2885)).

---

## Related Docs

- [`INDEX.md`](INDEX.md)
- [`accounting_coa.md`](accounting_coa.md) -- account types referenced by exchange accounts
- [`accounting_fixed_costs_guide.md`](accounting_fixed_costs_guide.md) -- reconciliation mechanics
- [`accounting_migration.md`](accounting_migration.md) -- opening balances in multi-currency setups

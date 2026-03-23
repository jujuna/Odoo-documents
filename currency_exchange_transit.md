# Currency Exchange & Transit Accounts

> **Module:** `account` | **Path:** [`addons/account/`](../addons/account/)
> **Odoo Apps category:** Accounting / Invoicing

## What It Does

Handles multi-currency transactions and the accounting entries that arise when exchange rates change between the date a transaction is recorded and the date it is paid/reconciled. Odoo uses a **transit account** (called "Inter-Banks Transfer Account") as an intermediary when moving money between liquidity accounts (bank-to-bank), and separate **exchange gain/loss accounts** to record currency rate differences automatically during reconciliation.

---

## When to Use This Module

### Best For
- Companies that transact in multiple currencies (buy in USD, sell in EUR, report in GEL)
- Moving money between bank accounts denominated in different currencies
- Receiving/paying invoices in a foreign currency where the rate changes between invoice date and payment date
- End-of-period unrealized exchange difference adjustments

### Not For
- Single-currency companies with no foreign transactions
- If you only need to track exchange rates for informational purposes without journal entries

---

## Core Concepts

### 1. Transit Account (`transfer_account_id`) -- Deep Dive

The **transit account** (internally called "Inter-Banks Transfer Account", UI label "Internal Transfer") is an intermediary reconcilable account used when transferring money between two liquidity accounts (e.g., Bank A -> Bank B, or USD Bank -> EUR Bank).

#### Why It Exists

When you move money between two bank accounts, Odoo cannot create a single journal entry spanning two journals (each bank has its own journal). The transit account solves this by being the counterpart on both sides:

- **Payment 1** (source bank journal): Credit Bank A / Debit Transit Account
- **Payment 2** (destination bank journal): Debit Bank B / Credit Transit Account

When both entries are posted, the transit account lines are reconciled against each other, zeroing out. If exchange rates changed, the residual goes to exchange gain/loss.

#### Field Definition

#### Where to Find It in the UI

**Accounting > Configuration > Settings > scroll down to "Default Accounts" section > "Bank transactions and payments" > "Internal Transfer"**

| Property | Detail |
|---|---|
| **Settings path** | Accounting > Configuration > Settings > Default Accounts > Bank transactions and payments > **Internal Transfer** |
| **View file** | [`res_config_settings_views.xml:280-281`](../addons/account/views/res_config_settings_views.xml#L280-L281) |
| **Settings model field** | `transfer_account_id` on `res.config.settings` -- `related='company_id.transfer_account_id'` ([res_config_settings.py:71-72](../addons/account/models/res_config_settings.py#L71-L72)) |
| **Stored on** | `transfer_account_id` on `res.company` ([company.py:114](../addons/account/models/company.py#L114)) |
| **Type** | `Many2one('account.account')` |
| **Domain** | `[('reconcile', '=', True), ('account_type', '=', 'asset_current')]` |
| **UI label in Settings** | "Internal Transfer" (`string=` on res.config.settings, [line 71](../addons/account/models/res_config_settings.py#L71)) |
| **Python string on company** | "Inter-Banks Transfer Account" (`string=` on res.company, [line 116](../addons/account/models/company.py#L116)) |
| **Help text** | "Intermediary account used when moving from a liquidity account to another." |

**This field is NOT visible on:**
- The `res.company` form view -- the field exists on the Python model but no company view XML renders it
- The `account.account` form view -- this is a company-level setting, not an account-level one
- The Chart of Accounts list view

**Visibility requirement:** The "Default Accounts" block in Settings requires `account.group_account_user` group ([view line 255](../addons/account/views/res_config_settings_views.xml#L255)). If your user does not have this group, the entire section (including Internal Transfer) is hidden.

#### How It Is Created Automatically

You do **not** need to create this account manually. When a Chart of Accounts is installed, Odoo auto-creates it via [`_setup_utility_bank_accounts()`](../addons/account/models/chart_template.py#L880):

```
Account created:
  name:         "Liquidity Transfer"
  prefix:       company.transfer_account_code_prefix (e.g., "1017" for generic CoA)
  account_type: asset_current
  reconcile:    True
```

Source: [`_get_accounts_data_values()`](../addons/account/models/chart_template.py#L871-L877). The code prefix comes from the localization template (e.g., `1017` for US/generic, `1360` for German SKR03, `103` for Turkey). After creation, the account is automatically assigned to `company.transfer_account_id` ([line 907-908](../addons/account/models/chart_template.py#L907-L908)).

Additionally, a **reconciliation model** named "Internal Transfers" is created and linked to this account ([`internal_transfer_reco`](../addons/account/models/chart_template.py#L1185-L1193)), so bank statement lines matching internal transfers can auto-reconcile against the transit account ([line 779](../addons/account/models/chart_template.py#L779)).

#### Where It Is Used in Code

The transit account serves three distinct purposes:

| Purpose | Where | Code Reference |
|---|---|---|
| **1. Internal transfer counterpart** | When `is_internal_transfer=True`, the transit account is the counterpart for both paired payments | Context set at [`account_journal_dashboard.py:1085`](../addons/account/models/account_journal_dashboard.py#L1085) |
| **2. Outstanding account fallback** | If no `payment_account_id` is set on the payment method line, Odoo falls back to `transfer_account_id` | [`_get_outstanding_account():886`](../addons/account/models/account_payment.py#L886) |
| **3. Counterpart line detection** | When parsing a payment's journal entry lines, lines hitting `transfer_account_id` are treated as counterpart lines (not write-off) | [`account_payment.py:227`](../addons/account/models/account_payment.py#L227) |

#### Why You Cannot Find the "Reconcile" Toggle in the Account Form

This is a common source of confusion. The `reconcile` field ("Allow Reconciliation") is **not visible in the account form view** -- it only appears in the **Chart of Accounts list view** as a toggle column.

| View | Shows `reconcile`? | Source |
|---|---|---|
| Account **form** view | **No** -- not included at all | [`view_account_form`](../addons/account/views/account_account_views.xml#L4-L92) -- field is absent |
| Account **list** view | **Yes** -- toggle column | [`view_account_list:106`](../addons/account/views/account_account_views.xml#L106) -- `invisible="account_type in ('asset_cash', 'liability_credit_card', 'off_balance')"` |

So to set `reconcile=True` on an `asset_current` account:
1. Go to **Accounting > Configuration > Chart of Accounts** (list view)
2. Find the account
3. Toggle the **"Allow Reconciliation"** column to ON
4. The toggle is hidden for `asset_cash`, `liability_credit_card`, and `off_balance` types -- but visible for `asset_current`

The `_compute_reconcile()` method at [`account_account.py:665`](../addons/account/models/account_account.py#L665) does NOT force any value for `asset_current` -- it falls into the "other asset/liability" case where "don't do any change" applies ([line 673](../addons/account/models/account_account.py#L673)). This means you can freely toggle it on or off for current-asset accounts.

#### Practical Tip: You Usually Do Not Need to Manually Set This

The transit account is auto-created with `reconcile=True` during CoA installation. If you are selecting a different account to use as the transit, go to Settings > Accounting > Default Accounts > "Internal Transfer" and pick an existing `asset_current` account that already has reconciliation enabled. If you need to enable reconciliation on an account, do it from the list view, not the form view.

#### How It Works in Multi-Currency Transfers

```
USD Bank Account (Journal A)          Transit Account           EUR Bank Account (Journal B)
──────────────────────────           ────────────────           ──────────────────────────
Credit $10,000                        Debit $10,000
(money leaves USD bank)               (at transfer-date rate)
                                      Credit EUR 9,200          Debit EUR 9,200
                                      (at transfer-date rate)   (money enters EUR bank)
```

The transit account acts as a temporary holding account. Both sides post their entry, then the transit account lines are reconciled. If the company-currency equivalent differs between the two sides due to rate changes, an **exchange difference entry** is automatically created.

### 2. Exchange Gain/Loss Accounts

When lines denominated in different currencies (or at different rates) are reconciled, Odoo detects any residual balance caused by rate fluctuation and books it automatically.

| Field | UI Label | Domain | Purpose |
|---|---|---|---|
| [`income_currency_exchange_account_id`](../addons/account/models/company.py#L135) | "Gain Exchange Rate Account" | `internal_group = 'income'` | Credited when the company gains from rate changes |
| [`expense_currency_exchange_account_id`](../addons/account/models/company.py#L140) | "Loss Exchange Rate Account" | `account_type = 'expense'` | Debited when the company loses from rate changes |
| [`currency_exchange_journal_id`](../addons/account/models/company.py#L134) | "Exchange Gain or Loss Journal" | `type = 'general'` | The miscellaneous journal where exchange entries are posted |

### 3. Outstanding Accounts (Payment Transit)

Payments use an **outstanding account** as a transit between the payment and the invoice. This is separate from the inter-bank transfer account but serves a similar intermediary role.

| Field | Purpose |
|---|---|
| [`outstanding_account_id`](../addons/account/models/account_payment.py#L122) | Per-payment outstanding account, computed from payment method line |
| `payment_method_line_id.payment_account_id` | The actual source of the outstanding account ([line 568](../addons/account/models/account_payment.py#L568)) |

When a payment is registered:
1. **Line 1 (Liquidity):** Debit/Credit the outstanding account
2. **Line 2 (Counterpart):** Credit/Debit the destination account (receivable/payable)

When the bank statement is reconciled with this payment, the outstanding account zeroes out.

---

## Real-World Use Cases

### Use Case 1: Paying a USD Vendor Invoice When Company Currency Is GEL

**Situation:** A Georgian company (reporting in GEL) receives a vendor bill for $5,000 on Jan 15 when the rate is 1 USD = 2.70 GEL. They pay on Feb 10 when the rate is 1 USD = 2.75 GEL.

**In Odoo:**
1. Bill is recorded on Jan 15: Debit Expense 13,500 GEL / Credit Payable $5,000 (= 13,500 GEL at 2.70)
2. Payment is registered on Feb 10: Debit Payable $5,000 / Credit Bank $5,000 (= 13,750 GEL at 2.75)
3. On reconciliation, Odoo detects: payable was 13,500 GEL but payment was 13,750 GEL -- a 250 GEL loss
4. Exchange difference entry is auto-created: Debit Exchange Loss 250 GEL / Credit Payable 250 GEL

**Result:** The payable is fully reconciled. The 250 GEL loss is booked to the configured Loss Exchange Rate Account.

### Use Case 2: Transferring Money Between USD and EUR Bank Accounts

**Situation:** A company needs to convert $10,000 from their USD bank account to their EUR bank account. The current rate gives them EUR 9,200.

**In Odoo:**
1. Accounting > Dashboard > USD Bank Journal > "Internal Transfer" button
2. Enter amount: $10,000, partner is set to the company itself
3. The payment creates: Credit USD Bank $10,000 / Debit Transit Account $10,000
4. A paired payment is created on the EUR bank: Debit EUR Bank EUR 9,200 / Credit Transit Account EUR 9,200
5. The transit account lines are reconciled against each other
6. If rates differ, an exchange difference entry is auto-created

**Result:** Money moved between banks. Transit account is zero. Any rate difference is in the exchange gain/loss account.

### Use Case 3: Receiving Customer Payment in EUR for a USD Invoice

**Situation:** A customer was invoiced $3,000 but pays in EUR. The invoice date rate and payment date rate differ.

**In Odoo:**
1. Invoice is posted at invoice-date rate
2. Payment is received at payment-date rate
3. During reconciliation, the system detects the company-currency (GEL) equivalent differs
4. An exchange difference journal entry is automatically created

**Result:** The receivable is fully matched. The gain or loss appears in the P&L under the configured exchange rate accounts.

---

## How-To Scenarios

### How to Configure Exchange Rate Accounts

1. Ensure **Multi-Currencies** is enabled (this is in **General Settings**, not Accounting settings -- it is the `group_multi_currency` field defined in `base_setup` with implied group `base.group_multi_currency`). It is typically auto-enabled when you activate a second currency.
2. Go to **Accounting > Configuration > Settings**
3. Scroll down to the **Default Accounts** section (requires `account.group_account_user` group), then find **Exchange difference entries** (visible only when multi-currency is enabled, [`invisible="not group_multi_currency"`](../addons/account/views/res_config_settings_views.xml#L257))
4. Set:
   - **Journal** (`currency_exchange_journal_id`) -- a miscellaneous-type journal
   - **Gain** (`income_currency_exchange_account_id`) -- an income-type account
   - **Loss** (`expense_currency_exchange_account_id`) -- an expense-type account
5. Save

**Why this works:** When [`_create_exchange_difference_moves()`](../addons/account/models/account_move_line.py#L2942) runs during reconciliation, it reads these three fields from the company. If any is missing, it raises a `UserError` ([lines 2960-2980](../addons/account/models/account_move_line.py#L2960-L2980)).

### How to Configure the Transit Account for Internal Transfers

Usually this is already set. To verify or change it:

1. Go to **Accounting > Configuration > Settings**
2. Scroll to **Default Accounts > Bank transactions and payments** ([view line 273](../addons/account/views/res_config_settings_views.xml#L273))
3. Find **Internal Transfer** (`transfer_account_id`) ([view line 280](../addons/account/views/res_config_settings_views.xml#L280))
4. The dropdown only shows accounts matching domain: `account_type = 'asset_current'` AND `reconcile = True` ([res_config_settings.py:74-77](../addons/account/models/res_config_settings.py#L74-L77))
5. If you do not see your desired account in the dropdown, it means `reconcile` is not enabled on that account -- enable it from the Chart of Accounts **list view** (not the form view, which does not show the toggle)
6. Save

**Why this works:** When internal transfers are created, both the source and destination payments use this account as their counterpart. It also serves as a fallback outstanding account when no `payment_account_id` is set on the payment method line ([`_get_outstanding_account():886`](../addons/account/models/account_payment.py#L886)).

### How to Enable Reconciliation on an Account (for Transit Use)

The "Allow Reconciliation" toggle is **only in the list view**, not the form view:

1. Go to **Accounting > Configuration > Chart of Accounts**
2. You are now in the **list view** -- find your `asset_current` account
3. Look for the **"Allow Reconciliation"** column (it is a toggle, always shown -- not behind optional columns) ([view_account_list:106](../addons/account/views/account_account_views.xml#L106))
4. Toggle it ON for the desired account
5. Note: the toggle is invisible (blank) for `asset_cash`, `liability_credit_card`, and `off_balance` types -- but visible and editable for `asset_current`
6. Now this account will appear in the `transfer_account_id` dropdown in Settings

**Why the form view does not show it:** The [`view_account_form`](../addons/account/views/account_account_views.xml#L4-L92) simply does not include the `reconcile` field in its XML. This is by design -- Odoo considers it a list-level toggle, not a form-level setting. The `_compute_reconcile()` method at [`account_account.py:665-673`](../addons/account/models/account_account.py#L665-L673) auto-sets reconcile for receivable/payable (always True) and cash/credit-card/off-balance (always False), but leaves `asset_current` and other types untouched -- meaning you control it manually from the list view.

### How to Make an Internal Transfer Between Currency-Different Banks

1. Go to **Accounting > Dashboard**
2. On the source bank journal, click the **vertical dots menu** > **Internal Transfer**
3. Fill in the amount in the source currency
4. The partner is automatically set to the company partner, `is_internal_transfer = True` is set in context ([line 1085](../addons/account/models/account_journal_dashboard.py#L1085))
5. Confirm the payment
6. A **paired payment** is auto-created on the destination journal ([`paired_internal_transfer_payment_id`](../addons/account/models/account_payment.py#L67))
7. Both payments create entries through the transit account
8. Reconcile the transit account lines

---

## Business Flow

### Internal Transfer (Bank-to-Bank)

```
Source Bank Journal              Transit Account              Destination Bank Journal
─────────────────               ───────────────              ────────────────────────
Payment 1 posted:                                            Payment 2 (paired) posted:
  Credit Bank A                   Debit (from Pay 1)           Debit Bank B
                                  Credit (from Pay 2)
                                       ↓
                                  Reconcile lines
                                       ↓
                              Exchange diff entry
                              (if rate mismatch)
```

### Invoice Payment with Exchange Difference

```
Invoice posted         Payment registered       Reconciliation           Exchange diff
(date 1, rate R1)      (date 2, rate R2)        (match receivable)       (auto-created)
─────────────         ──────────────────        ──────────────          ────────────────
Debit Receivable       Debit Bank               Lines matched            Debit/Credit
  at R1 rate             at R2 rate              Residual detected:       Receivable
Credit Revenue         Credit Receivable           R2-R1 difference     Credit/Debit
                         at R2 rate                                       Exchange Gain/Loss
```

---

## Key Models

### `res.company` -- Exchange Rate Configuration
> [`company.py`](../addons/account/models/company.py)

| Field | Type | UI Label | Purpose |
|---|---|---|---|
| `transfer_account_id` | `Many2one(account.account)` | "Internal Transfer" (Settings UI) / `string="Inter-Banks Transfer Account"` (Python) | Intermediary for bank-to-bank transfers. Only editable via Settings, not on any company or account form. ([line 114](../addons/account/models/company.py#L114)) |
| `currency_exchange_journal_id` | `Many2one(account.journal)` | "Exchange Gain or Loss Journal" | Journal for exchange diff entries ([line 134](../addons/account/models/company.py#L134)) |
| `income_currency_exchange_account_id` | `Many2one(account.account)` | "Gain Exchange Rate Account" | Income account for favorable rate changes ([line 135](../addons/account/models/company.py#L135)) |
| `expense_currency_exchange_account_id` | `Many2one(account.account)` | "Loss Exchange Rate Account" | Expense account for unfavorable rate changes ([line 140](../addons/account/models/company.py#L140)) |

### `account.payment` -- Payment with Transit Logic
> [`account_payment.py`](../addons/account/models/account_payment.py)

| Field | Type | Purpose |
|---|---|---|
| `outstanding_account_id` | `Many2one(account.account)` | Outstanding account from payment method ([line 122](../addons/account/models/account_payment.py#L122)) |
| `destination_account_id` | `Many2one(account.account)` | Receivable/payable counterpart ([line 129](../addons/account/models/account_payment.py#L129)) |
| `paired_internal_transfer_payment_id` | `Many2one(account.payment)` | Links two sides of an internal transfer ([line 67](../addons/account/models/account_payment.py#L67)) |

### `account.partial.reconcile` -- Exchange Move Link
> [`account_partial_reconcile.py`](../addons/account/models/account_partial_reconcile.py)

| Field | Type | Purpose |
|---|---|---|
| `exchange_move_id` | `Many2one(account.move)` | Links partial reconciliation to its exchange difference entry ([line 23](../addons/account/models/account_partial_reconcile.py#L23)) |

---

## Key Methods

| Method | File:Line | Purpose |
|---|---|---|
| `_get_exchange_journal()` | [`account_move_line.py:2846`](../addons/account/models/account_move_line.py#L2846) | Returns the configured exchange journal from company |
| `_get_exchange_account()` | [`account_move_line.py:2849`](../addons/account/models/account_move_line.py#L2849) | Returns gain account (negative amount) or loss account (positive amount) |
| `_prepare_exchange_difference_move_vals()` | [`account_move_line.py:2854`](../addons/account/models/account_move_line.py#L2854) | Builds the journal entry dict for exchange differences |
| `_create_exchange_difference_moves()` | [`account_move_line.py:2942`](../addons/account/models/account_move_line.py#L2942) | Creates and posts exchange difference entries |
| `_prepare_move_line_default_vals()` | [`account_payment.py:280`](../addons/account/models/account_payment.py#L280) | Builds liquidity + counterpart lines for a payment |
| `_get_outstanding_account()` | [`account_payment.py:881`](../addons/account/models/account_payment.py#L881) | Gets outstanding account, falls back to `transfer_account_id` |

### _prepare_exchange_difference_move_vals() -- detailed
> [`account_move_line.py:2854-2940`](../addons/account/models/account_move_line.py#L2854-L2940)

Creates a two-line journal entry for each exchange difference:

**Line 1 (Counterpart):**
- Account: the original transaction's account (e.g., receivable)
- Debit/Credit: the exchange difference amount ([lines 2912-2913](../addons/account/models/account_move_line.py#L2912-L2913))
- `amount_currency`: negative of the currency difference
- Links to original line via `reconciled_lines_ids`

**Line 2 (Gain/Loss):**
- Account: exchange gain or loss account ([line 2927](../addons/account/models/account_move_line.py#L2927))
- Debit/Credit: opposite of Line 1 ([lines 2924-2925](../addons/account/models/account_move_line.py#L2924-L2925))

**Gain vs Loss determination** ([`_get_exchange_account()`](../addons/account/models/account_move_line.py#L2849)):
- `amount_residual_to_fix > 0` --> Loss (expense account)
- `amount_residual_to_fix < 0` --> Gain (income account)

### _prepare_move_line_default_vals() -- detailed
> [`account_payment.py:280-353`](../addons/account/models/account_payment.py#L280-L353)

Creates two journal item lines per payment:

1. **Liquidity line** -- hits the `outstanding_account_id`, amount in payment currency converted to company currency at payment date rate ([line 315](../addons/account/models/account_payment.py#L315))
2. **Counterpart line** -- hits the `destination_account_id` (receivable/payable), exact negative of liquidity line

The currency conversion uses `currency_id._convert()` at the payment date, which may differ from the invoice date rate -- this is what creates exchange differences later during reconciliation.

---

## Configuration

| Setting | Location | Field | Effect |
|---|---|---|---|
| Multi-Currencies | Settings > General Settings (defined in `base_setup`, not `account`) | `group_multi_currency` (implied_group: `base.group_multi_currency`) | Enables multi-currency features; exchange difference settings become visible. Auto-enabled when a second currency is activated. In account settings it is loaded as `invisible="1"` ([view line 102](../addons/account/views/res_config_settings_views.xml#L102)) -- it is read for visibility conditions but not toggled from the Accounting settings page. |
| Internal Transfer Account | Settings > Accounting > Default Accounts > Bank transactions and payments | `transfer_account_id` | Sets the transit account for bank-to-bank transfers. Requires `account.group_account_user` to see. |
| Exchange Journal | Settings > Accounting > Default Accounts > Exchange difference entries | `currency_exchange_journal_id` | Journal for auto-created exchange entries |
| Exchange Gain Account | Settings > Accounting > Default Accounts > Exchange difference entries | `income_currency_exchange_account_id` | Where favorable rate differences are booked |
| Exchange Loss Account | Settings > Accounting > Default Accounts > Exchange difference entries | `expense_currency_exchange_account_id` | Where unfavorable rate differences are booked |
| Automatic Currency Rates | Settings > Accounting > Currencies | `module_currency_rate_live` | Auto-fetches rates from central banks ([line 92](../addons/account/models/res_config_settings.py#L92)) |

**Visibility:** The "Default Accounts" block (containing both exchange difference and transit account settings) requires `account.group_account_user` group ([view line 255](../addons/account/views/res_config_settings_views.xml#L255)). Within it, the "Exchange difference entries" setting is additionally hidden unless `group_multi_currency` is enabled ([view line 257](../addons/account/views/res_config_settings_views.xml#L257)). The "Bank transactions and payments" setting (containing the transit account) is always visible within the block -- no multi-currency requirement.

---

## Edge Cases & Gotchas

- **Missing configuration:** If `currency_exchange_journal_id`, `income_currency_exchange_account_id`, or `expense_currency_exchange_account_id` is not set, reconciliation of multi-currency lines raises a `UserError` -- you cannot proceed until configured ([lines 2960-2980](../addons/account/models/account_move_line.py#L2960-L2980)).

- **Transit account must be reconcilable:** The `transfer_account_id` domain enforces `reconcile=True` and `account_type='asset_current'` ([res_config_settings.py:74-77](../addons/account/models/res_config_settings.py#L74-L77)). If you pick a non-reconcilable account, the internal transfer lines cannot be matched and the transit balance will never zero out. If you cannot find your account in the dropdown, enable "Allow Reconciliation" from the Chart of Accounts **list view** -- the toggle does not exist in the form view.

- **"Allow Reconciliation" is list-view only:** The `reconcile` field is not in the account form view ([`view_account_form`](../addons/account/views/account_account_views.xml#L4-L92)) -- it only appears as a toggle column in the Chart of Accounts list view ([`view_account_list:106`](../addons/account/views/account_account_views.xml#L106)). This confuses users who open an account form, set type to `asset_current`, but cannot find the reconcile checkbox. The toggle is also hidden for `asset_cash`, `liability_credit_card`, and `off_balance` types.

- **Transit account is auto-created during CoA installation:** You rarely need to create it manually. The chart template creates an account named "Liquidity Transfer" with code prefix from `transfer_account_code_prefix` (e.g., `1017` for generic CoA), sets `reconcile=True`, and assigns it to `company.transfer_account_id` ([chart_template.py:871-877](../addons/account/models/chart_template.py#L871-L877)). A reconciliation model "Internal Transfers" is also auto-created and linked to this account ([chart_template.py:1185](../addons/account/models/chart_template.py#L1185)).

- **`no_exchange_difference` context flag:** Odoo creates exchange moves with `context(no_exchange_difference=True)` to prevent infinite recursion -- the exchange move itself must not trigger another exchange move ([line 2983](../addons/account/models/account_move_line.py#L2983)).

- **Rate priority during reconciliation:** When reconciling, Odoo picks the rate with this priority: forced rate from context > payment method rate > invoice date rate > reconciliation date rate > accounting rate (balance/amount_currency). See [`_prepare_reconciliation_amls()`](../addons/account/models/account_move_line.py#L2029).

- **Paired internal transfers:** When an internal transfer is posted, a paired payment is created and cross-referenced via `paired_internal_transfer_payment_id` ([line 67](../addons/account/models/account_payment.py#L67)). If only one side is posted, the transit account will show an open balance.

- **Outstanding account fallback:** If no `payment_account_id` is set on the payment method line, `_get_outstanding_account()` falls back to `company.transfer_account_id` ([line 886](../addons/account/models/account_payment.py#L886)).

- **Exchange difference is per-line:** Each reconciled line gets its own exchange difference entry lines. A single exchange move can contain lines for multiple reconciled items ([loop at line 2885](../addons/account/models/account_move_line.py#L2885)).

- **Reversal cascades:** When a partial reconciliation is unreconciled, its linked `exchange_move_id` is automatically reversed ([line 118](../addons/account/models/account_partial_reconcile.py#L118)).

---

## Accountant's Perspective: Why Transit Accounts for Currency Exchange

Your accountant's advice about using transit accounts for money exchange is standard practice. Here is why:

### The Problem Without a Transit Account
If you directly transfer from USD Bank to EUR Bank, you need a single journal entry debiting one bank and crediting another. But:
- The two banks may be in different journals (Odoo requires one journal per bank)
- Each journal can only post entries to its own accounts
- You cannot create a single entry spanning two journals

### The Solution: Transit Account as Bridge
The transit account solves this by splitting one logical transfer into two journal entries:

| Step | Journal | Debit | Credit |
|---|---|---|---|
| 1. Money leaves USD bank | USD Bank Journal | Transit Account (in USD) | USD Bank Account |
| 2. Money enters EUR bank | EUR Bank Journal | EUR Bank Account | Transit Account (in EUR) |

After both entries are posted, the transit account has a debit and a credit that should net to zero. If exchange rates changed between the two entries, the difference is automatically booked as an exchange gain or loss.

### Why This Is Correct Accounting
- **Audit trail:** Each bank has its own clean journal entry
- **Reconciliation:** The transit account can be reconciled, proving both sides of the transfer are complete
- **Rate transparency:** Exchange differences are isolated in their own P&L accounts, not buried in bank entries
- **Regulatory compliance:** Many jurisdictions require exchange gains/losses to be separately reported

---

## Related Docs

- [`INDEX.md`](INDEX.md)
- [`accounting_coa.md`](accounting_coa.md) -- account types and groups referenced by exchange accounts
- [`accounting_fixed_costs_guide.md`](accounting_fixed_costs_guide.md) -- reconciliation mechanics (partial/full/multi-currency)
- [`accounting_migration.md`](accounting_migration.md) -- opening balances in multi-currency setups

# Chart of Accounts (COA)

> **Module:** `account` | **Path:** [`addons/account/`](../addons/account/)
> **Odoo Apps category:** Accounting / Invoicing

---

## Glossary for Beginners

Before diving in, here are the key terms you will see throughout this document.

| Term | Simple Definition | Real-World Analogy |
|---|---|---|
| Chart of Accounts (COA) | The complete list of all accounts your company uses to record money movements | Like a table of contents for your financial books |
| Account | A category bucket where money is recorded as coming in or going out | "Bank Account", "Sales Revenue", "Office Expenses" |
| Journal Entry | A record of a single financial transaction, always balanced (debits = credits) | When you send an invoice, Odoo creates: Debit Receivable + Credit Revenue |
| Debit | Left side of an accounting entry — increases assets, decreases liabilities | Money a customer owes you (Receivable) is a debit |
| Credit | Right side of an accounting entry — decreases assets, increases liabilities | Revenue you earned is a credit |
| Reconciliation | Matching two journal entry lines that cancel each other out | Matching a $500 customer payment against their $500 invoice |
| Fiscal Position | Rules that swap accounts and taxes based on where the customer is located | EU customer gets a different tax account than a domestic customer |
| Opening Balance | The starting balance of an account when you first begin using Odoo | If you had $10,000 in the bank before Odoo, you set opening balance = 10,000 |
| Account Type | A classification that tells Odoo how the account behaves automatically | "Receivable" type means Odoo forces reconciliation on and tracks customer debts |
| Account Group | A folder that organizes accounts by code prefix range | All accounts starting with 15xx go into the "Fixed Assets" group |
| Balance Sheet | Financial report showing what the company owns (assets), owes (liabilities), and is worth (equity) at a point in time | A snapshot of the company's financial position on Dec 31 |
| Profit & Loss (P&L) | Financial report showing income minus expenses over a period | How much the company earned/lost during the year |
| Stock Variation | The difference between physical inventory value and what the accounting ledger shows | You have $10,000 of goods in the warehouse but the books say $9,500 — the $500 gap is stock variation |

---

## What It Does

The Chart of Accounts is the master list of all ledger accounts a company uses to record financial transactions.
Every journal entry line (`account.move.line`) must be posted to an account from the COA.
Accounts are organized by type, grouped by prefix range, and tagged for reporting.
The COA is per-company but accounts can be shared across a parent-child company hierarchy.
Odoo installs a COA automatically by loading a localized chart template when a company is first set up.

---

## How Everything Connects — Visual Overview

This diagram shows how the COA fits into the full accounting lifecycle, from initial setup to financial reporting.

```
STEP 1: COMPANY SETUP
  Company created with: Country + Fiscal Country + Currency
                              |
                              v
STEP 2: CHART TEMPLATE LOADING
  Odoo picks a template based on company country (e.g. l10n_us, l10n_de)
  Creates records in dependency order:
    1. Account Groups (prefix ranges like 10-19, 20-29)
    2. Accounts (100-500+ accounts depending on country)
    3. Taxes (VAT, sales tax, etc.)
    4. Journals (Sales, Purchase, Bank, Cash, Miscellaneous)
                              |
                              v
STEP 3: DEFAULT ACCOUNTS SET
  ir.default stores company-wide defaults:
    - All partners get a default Receivable account (e.g. 1100)
    - All partners get a default Payable account (e.g. 2000)
    - All product categories get default Income/Expense accounts
                              |
                              v
STEP 4: DAILY USE — INVOICE CREATED
  User creates an invoice line
    Product selected?
      YES -> Get account from: Product > Category > Company default
      NO  -> Use partner's most frequently used account (last 2 years)
      Still nothing? -> Use journal's default account
    Apply fiscal position substitution (if set)
                              |
                              v
STEP 5: JOURNAL ENTRY POSTED
  account.move.line created with:
    - account_id (resolved from step above)
    - debit / credit amounts
    - amount_currency (if account has a foreign currency set)
                              |
                              v
STEP 6: FINANCIAL REPORTS
  Balance Sheet: Shows accounts where balance carries forward year-to-year
                 (assets, liabilities, equity)
  Profit & Loss: Shows accounts that reset to zero each fiscal year
                 (income, expenses)
  Grouped by: account.root (first 2 digits) -> account.group (prefix ranges)
```

---

## Prerequisites Before Using the COA

Before any account exists, three things must be configured on the company:

### 1. Company Country + Fiscal Country

| Field (Python) | UI Label | Model | Purpose |
|---|---|---|---|
| `country_id` | "Country" | `res.company` | Determines which localized chart template is available |
| `account_fiscal_country_id` | "Fiscal Country" | `res.company` | The country whose tax rules apply; computed from `country_id` but can differ (e.g., foreign branch) |

`account_fiscal_country_id` is stored on `res.company`, computed by
[`compute_account_tax_fiscal_country()`](../addons/account/models/company.py).

### 2. Chart Template

A chart template is the blueprint that creates accounts, groups, taxes, and journals for a company.
It is loaded by [`AccountChartTemplate.try_loading()`](../addons/account/models/chart_template.py#L139).

**How templates are discovered:**

The abstract model `account.chart.template` scans all installed modules for methods decorated with
`@template(code)` via [`_template_register`](../addons/account/models/chart_template.py#L77).
Each localization module (e.g., `l10n_us`, `l10n_de`) registers its own template code.
The generic fallback is `generic_coa` (US-style, no country lock).

**Key template method decorators:**
- `@template('generic_coa')` — registers template metadata (name, country, property_ keys)
- `@template('generic_coa', 'account.account')` — registers accounts to create
- `@template('generic_coa', 'res.company')` — registers company fields to set (prefixes, special accounts)

Source: [`template_generic_coa.py`](../addons/account/models/template_generic_coa.py)

**What `generic_coa` sets on the company:**

| Company field | Value set | Purpose |
|---|---|---|
| `bank_account_code_prefix` | `'1014'` | Auto-prefix for new bank accounts |
| `cash_account_code_prefix` | `'1015'` | Auto-prefix for new cash accounts |
| `transfer_account_code_prefix` | `'1017'` | Internal transfer intermediary |
| `account_fiscal_country_id` | `base.us` | US tax rules |
| `anglo_saxon_accounting` | `True` | COGS posted at delivery, not invoicing |

#### Chart Template Loading — Step by Step

When you select a chart template (or Odoo auto-selects one for your country), this is the exact sequence:

```
1. AccountChartTemplate.try_loading('generic_coa', company)
   Validates the company, resolves template code.
   Source: chart_template.py:139

2. Is the template already loaded? (reload scenario)
   If yes: _pre_reload_data() runs first (line 264)
     - Preserves existing journals (does not overwrite)
     - Prefixes old tax names with "[old]" to avoid name conflicts
     - Strips reconcile model links
     - Does NOT delete accounts

3. _get_chart_template_data('generic_coa')  (line 808)
   Scans all @template('generic_coa', model) decorated methods.
   Collects creation data for:
     - account.group (prefix ranges)
     - account.account (the actual accounts)
     - account.tax (tax definitions)
     - account.journal (journals to create)
     - res.company (company settings to write)

4. _pre_load_data()  (line 484)
   Preprocessing before any records are created:
     - Sets company.fiscal_country_id BEFORE creating taxes
       (taxes depend on country for tax tags)
     - Applies code_digits padding to all account codes
     - Creates utility accounts (suspense, transfer, etc.)

5. _load_data()  (line 562)
   Creates records in strict dependency order:
     a. account.group     (must exist before accounts)
     b. account.account   (references groups via code prefix)
     c. account.tax       (repartition lines reference accounts)
     d. account.journal   (references accounts as defaults)
     e. account.reconcile.model (references accounts)

   Why order matters: accounts reference groups through prefix matching.
   Taxes reference accounts in their repartition lines. Journals reference
   accounts as defaults. Creating them out of order would fail.

6. Set ir.default values for property accounts
     - res.partner.property_account_receivable_id
     - res.partner.property_account_payable_id
     - product.category.property_account_income_categ_id
     - product.category.property_account_expense_categ_id

7. _adapt_parent_account_group()  (line 1587)
   Auto-resolves group hierarchy (parent_id) by prefix nesting.
```

### 3. Currency

| Field | Model | UI Label |
|---|---|---|
| `currency_id` | `res.company` | "Currency" |

All `Monetary` fields on accounts use `company_currency_id`.
If an account has its own `currency_id` set, every journal line on that account is forced to use that currency
(used for foreign currency bank accounts).

---

## Dependencies

### Requires (must be installed)

| Module | Why |
|---|---|
| `base_setup` | Company setup wizard, country/currency data |
| `onboarding` | Onboarding panel and setup steps |
| `product` | Product accounts (`account_id`, `property_account_income_id`) |
| `analytic` | Analytic account field on journal lines |
| `portal` | Customer portal access to invoices |
| `digest` | KPI digest emails |

### Provides To

| Consumer module | What it uses |
|---|---|
| `account_payment` | `account.account` for payment journals |
| `stock_account` | COGS, stock valuation accounts |
| `hr_payroll_account` | Salary journal accounts |
| `account_reports` | Account tags + account types for P&L, Balance Sheet |
| All `l10n_*` modules | Extend `account.chart.template` with country COA |

---

## Core Model: `account.account`

> [`models/account_account.py`](../addons/account/models/account_account.py)

This is the central record — one row per ledger account.

### Key Fields

| Field | Type | UI Label | Purpose |
|---|---|---|---|
| `code` | `Char` (computed) | "Code" | Account code; company-dependent via `code_store` |
| `code_store` | `Char` (company_dependent) | — | Raw storage of code per company root |
| `name` | `Char` | "Account Name" | Human-readable account name |
| `account_type` | `Selection` | "Type" | Controls behavior, reporting, and balance logic (see below) |
| `internal_group` | `Selection` (computed) | "Internal Group" | Derived from `account_type` prefix (e.g. `asset_*` -> `asset`) |
| `reconcile` | `Boolean` | "Allow Reconciliation" | Whether journal lines on this account can be matched/reconciled |
| `currency_id` | `Many2one` `res.currency` | "Account Currency" | If set, forces all lines to use this currency |
| `company_ids` | `Many2many` `res.company` | "Companies" | Companies that share this account |
| `tax_ids` | `Many2many` `account.tax` | "Default Taxes" | Taxes auto-applied when this account is selected on a line |
| `tag_ids` | `Many2many` `account.account.tag` | "Tags" | Custom tags for reporting |
| `group_id` | `Many2one` `account.group` (computed) | — | Auto-resolved from code prefix match against `account.group` |
| `root_id` | `Many2one` `account.root` (computed) | — | Virtual node: first 2 chars of code |
| `active` | `Boolean` | "Active" | Inactive accounts are hidden but preserved |
| `non_trade` | `Boolean` | "Non Trade" | Marks receivable/payable as non-trade for report filters |
| `opening_debit` | `Monetary` (computed/inverse) | "Opening Debit" | Balance from the company opening journal entry |
| `opening_credit` | `Monetary` (computed/inverse) | "Opening Credit" | Balance from the company opening journal entry |
| `current_balance` | `Float` (computed) | — | Sum of posted `account.move.line.balance` for the active company |

---

## Account Types — Complete Reference

`account_type` is a `Selection` field. It is the "brain" of an account — it automatically controls three critical behaviors:

1. **Which financial statement** the account appears in (Balance Sheet vs P&L)
2. **Whether the balance carries forward** year-to-year (`include_initial_balance`)
3. **Whether reconciliation is allowed** (matching payments against invoices)

Source: [`account_account.py:44`](../addons/account/models/account_account.py#L44)

### How Account Types Control Behavior Automatically

When you set an account type, Odoo enforces several behaviors behind the scenes. Understanding these prevents confusion when fields appear locked or values change unexpectedly.

#### A. Reconciliation — Enforced by Type

Source: [`_check_reconcile()`](../addons/account/models/account_account.py#L27)

```python
@api.constrains('account_type', 'reconcile')
def _check_reconcile(self):
    for account in self:
        if account.account_type in ('asset_receivable', 'liability_payable') and not account.reconcile:
            raise ValidationError(...)
```

**What this means in practice:**

| If you set type to... | Reconciliation becomes... | Why |
|---|---|---|
| Receivable | Forced ON (cannot uncheck) | You must match customer payments against their invoices |
| Payable | Forced ON (cannot uncheck) | You must match your payments against vendor bills |
| Income, Expense, Equity | Defaults to OFF | You don't match individual payments against revenue/expense lines |
| Current Assets, etc. | Optional (your choice) | Some asset accounts benefit from reconciliation (e.g., intercompany) |

#### B. Balance Carry-Forward — Determined by Type

Source: [`_compute_include_initial_balance()`](../addons/account/models/account_account.py#L638)

```python
@api.depends('account_type')
def _compute_include_initial_balance(self):
    for account in self:
        account.include_initial_balance = (
            account.internal_group not in ['income', 'expense']
            and account.account_type != 'equity_unaffected'
        )
```

**What this means in practice:**

| Account category | Balance at year-end | What happens Jan 1 | Why |
|---|---|---|---|
| Balance Sheet (Assets, Liabilities, Equity) | Carries forward | Same balance continues | The bank still has $50,000; the loan is still $30,000 |
| P&L (Income, Expense) | Resets to zero | Starts fresh | Last year's revenue is done; new year starts from zero |
| `equity_unaffected` (Current Year Earnings) | Does NOT carry forward | Computed fresh | It's always "this year's net P&L" — Odoo calculates it on the fly |

#### C. Internal Group — Auto-Derived from Type

Source: [`_get_internal_group()`](../addons/account/models/account_account.py#L648)

```python
def _get_internal_group(self, account_type):
    return account_type.split('_', maxsplit=1)[0]
```

| `account_type` | `internal_group` | Used for |
|---|---|---|
| `asset_cash` | `asset` | Report grouping, filters |
| `asset_receivable` | `asset` | Report grouping, filters |
| `liability_payable` | `liability` | Report grouping, filters |
| `income` | `income` | Report grouping, filters |
| `income_other` | `income` | Report grouping, filters |
| `expense_direct_cost` | `expense` | Report grouping, filters |

When you filter reports by "Asset", Odoo matches all `asset_*` types. You never set `internal_group` manually.

### Balance Sheet Accounts (`include_initial_balance = True`)

These accounts **carry their balance forward** every fiscal year — they represent what the company owns, owes, or has invested.

#### Assets

| `account_type` value | UI label | `reconcile` default | When to use | Real example |
|---|---|---|---|---|
| `asset_receivable` | "Receivable" | **True** (enforced) | Money customers owe you. Every customer invoice posts a debit here. Must be reconcilable — payments match against these lines. | "Accounts Receivable 1100" |
| `asset_cash` | "Bank and Cash" | False | Bank and cash accounts linked to a journal. Cannot be shared across companies. | "Checking Account 1010" |
| `asset_current` | "Current Assets" | Optional | Assets expected to be converted to cash within 1 year: inventory prepayments, VAT receivable. | "VAT Receivable 1410" |
| `asset_non_current` | "Non-current Assets" | Optional | Assets held >1 year, excluding fixed assets. | "Long-term deposits 1600" |
| `asset_prepayments` | "Prepayments" | Optional | Costs paid in advance for future periods (prepaid insurance, prepaid rent). | "Prepaid Expenses 1300" |
| `asset_fixed` | "Fixed Assets" | Optional | Property, plant, equipment. Used by `account_asset` module for depreciation. | "Equipment 1500" |

> **Beginner note — Current vs Non-current vs Fixed Assets**
>
> | Category | Rule of thumb | Examples | Odoo account type |
> |---|---|---|---|
> | **Current Assets** | Can be converted to cash **within 1 year** | Cash, inventory, customer invoices (receivables), VAT refunds, prepaid rent | `asset_cash`, `asset_receivable`, `asset_current`, `asset_prepayments` |
> | **Non-current Assets** | Kept **longer than 1 year**, not physical equipment | Long-term deposits, goodwill, deferred tax assets, long-term investments | `asset_non_current` |
> | **Fixed Assets** | **Physical things** you use in operations (not sell), that **depreciate** over time | Trucks, machines, office furniture, computers, buildings | `asset_fixed` |
>
> The hierarchy: Non-current Assets is the broad parent category for anything held >1 year.
> Fixed Assets is a **subset** of non-current — specifically the tangible, depreciable items.
> Odoo's `account_asset` module only auto-creates depreciation boards for accounts typed `asset_fixed`.
>
> ```
> All Assets
> ├── Current Assets        (cash, inventory, receivables — < 1 year)
> └── Non-Current Assets    (everything long-term — > 1 year)
>     ├── Fixed Assets      (physical: trucks, machines — depreciated)
>     ├── Intangible Assets (patents, software — amortized, use asset_non_current)
>     └── Financial Assets  (long-term investments — use asset_non_current)
> ```

#### Liabilities

| `account_type` value | UI label | `reconcile` default | When to use | Real example |
|---|---|---|---|---|
| `liability_payable` | "Payable" | **True** (enforced) | Money you owe vendors. Every vendor bill posts a credit here. Must be reconcilable. | "Accounts Payable 2000" |
| `liability_credit_card` | "Credit Card" | False | Credit card bank journals. Treated like a bank account but on the liability side. | "Visa Card 2010" |
| `liability_current` | "Current Liabilities" | Optional | Short-term obligations due within 1 year: VAT payable, accrued expenses. | "VAT Payable 2200" |
| `liability_non_current` | "Non-current Liabilities" | Optional | Long-term debt (>1 year): bonds, long-term loans. | "Bank Loan 2500" |

#### Equity

| `account_type` value | UI label | `include_initial_balance` | When to use | Real example |
|---|---|---|---|---|
| `equity` | "Equity" | True | Shareholder capital, retained earnings from previous years | "Share Capital 3000" |
| `equity_unaffected` | "Current Year Earnings" | **False** | Special account: Odoo writes the net P&L of the current fiscal year here. Excluded from initial balance logic — it's always computed. | "Retained Earnings 3100" |

> **Important:** `equity_unaffected` is the one account with `internal_group = equity` but `include_initial_balance = False`.
> Source: [`_compute_include_initial_balance()`](../addons/account/models/account_account.py#L638)

### P&L Accounts (`include_initial_balance = False`)

These accounts **reset to zero** at the start of each fiscal year. Their year-end balance is transferred to the equity account.

| `account_type` value | UI label | When to use | Real example |
|---|---|---|---|
| `income` | "Income" | Primary revenue from sales of goods/services. Odoo auto-suggests these for customer invoice lines. | "Sales Revenue 4000" |
| `income_other` | "Other Income" | Non-operating income: interest earned, asset disposal gains. | "Interest Income 4900" |
| `expense` | "Expenses" | Primary operating costs: purchases, services consumed. Odoo auto-suggests for vendor bill lines. | "Operating Expenses 6000" |
| `expense_other` | "Other Expenses" | Non-operating losses: bank charges, fines. | "Bank Fees 6900" |
| `expense_depreciation` | "Depreciation" | Depreciation charges posted by `account_asset`. | "Depreciation 6600" |
| `expense_direct_cost` | "Cost of Revenue" | COGS — direct cost of goods sold. Odoo posts COGS here on delivery (Anglo-Saxon). | "Cost of Goods Sold 5000" |

### Special

| `account_type` value | UI label | Notes |
|---|---|---|
| `off_balance` | "Off-Balance Sheet" | Not on Balance Sheet or P&L. Cannot be reconcilable. Cannot have taxes. Used for contingent liabilities, guarantees. |

### Computed fields derived from `account_type`

| Computed field | Logic | Source |
|---|---|---|
| `internal_group` | `account_type.split('_')[0]` — e.g. `asset_cash` -> `asset` | [`_compute_internal_group()`](../addons/account/models/account_account.py#L652) |
| `include_initial_balance` | `True` if not income/expense and not `equity_unaffected` | [`_compute_include_initial_balance()`](../addons/account/models/account_account.py#L638) |
| `reconcile` | Auto-set True for receivable/payable; False for income/expense/equity/cash/credit card/off-balance; unchanged for other asset/liability types | [`_compute_reconcile()`](../addons/account/models/account_account.py#L665) |

---

## Account Code — Technical Details

Account codes are stored as a **company-dependent JSON field** (`code_store`), not a plain char.

### Why company-dependent?

In a multi-company hierarchy, multiple subsidiaries can share the same `account.account` record
(e.g., a shared "Sales Revenue" account). Each company can have its own code for the same account.

`code_store` is a JSONB column: `{"<root_company_id>": "4000"}`.

**`code` field** (what you see and edit) is computed from `code_store` for the active company root:

```python
# _compute_code: reads code_store for self.env.company.root_id
record.code = record_root.code_store
```

Source: [`_compute_code()`](../addons/account/models/account_account.py#L336)

### Real-World Multi-Company Example

Imagine your company has two subsidiaries:

| Company | Country | Wants code for "Sales Revenue" |
|---|---|---|
| Parent (US) | United States | `4000` |
| Subsidiary (UK) | United Kingdom | `4100` |

**Without** company-dependent codes, you would need two separate `account.account` records. This breaks consolidated reporting because the two records have no link to each other.

**With** company-dependent codes, there is ONE `account.account` record for "Sales Revenue". The database stores:

```json
code_store = {
    "1": "4000",
    "2": "4100"
}
```

At runtime:
- When logged into US company: `account.code` reads `code_store["1"]` and returns `"4000"`
- When logged into UK company: `account.code` reads `code_store["2"]` and returns `"4100"`

**Key constraint:** Both companies must share the same `root_id` (parent company). Companies in completely separate hierarchies cannot share account records.

### Code format constraints

- Only alphanumeric characters and dots: validated by `ACCOUNT_CODE_REGEX = r'^[A-Za-z0-9.]+$'`
- Source: [`_check_account_code()`](../addons/account/models/account_account.py#L311)

### Auto-incrementing new codes

[`_search_new_account_code(start_code)`](../addons/account/models/account_account.py#L466) finds the next available code:

| Input code | Codes checked |
|---|---|
| `102100` | `102101`, `102102`, `102103`, ... |
| `1598` | `1599`, `1600`, `1601`, ... |
| `10.01.08` | `10.01.09`, `10.01.10`, ... |
| `hello` | `hello.copy`, `hello.copy2`, ... |

### `placeholder_code`

When an account has no code in the **current** company but exists in another company,
the display shows `<code> (<company_name>)` as a read-only placeholder.
Source: [`_compute_placeholder_code()`](../addons/account/models/account_account.py#L357)

---

## Account Hierarchy — Three Layers

Odoo's Chart of Accounts uses three distinct layers to organize accounts into a hierarchy. All three are **code-driven and automatic** — you never manually set parent-child links.

```
LAYER 1: account.root (virtual, no DB table)
  Purpose: search panel filter in COA list view
  How: first 2 chars of account code
  Parent logic: "12" -> parent "1" (trim last char)

LAYER 2: account.group (real DB model)
  Purpose: hierarchical grouping for reports & UI
  How: code prefix range (code_prefix_start / code_prefix_end)
  Parent logic: auto-resolved — shortest enclosing prefix range

LAYER 3: account.account -> group_id (computed link)
  Purpose: assign each account to its most specific group
  How: longest matching prefix range wins
```

### Full hierarchy example

```
account.root "1"                         (virtual: code[:2])
  account.root "10"                      (virtual: code[:2], parent = "1")
    account.group "Assets" (1-1)         (real: prefix range)
      account.group "Current Assets" (10-10)
        account.group "Cash" (101-101)
          account.account 101000 "Cash"  (group_id -> "Cash 101-101")
          account.account 101001 "Petty" (group_id -> "Cash 101-101")
```

Each layer serves a different purpose. `account.root` is the quick search filter. `account.group` is the reporting hierarchy. `group_id` on the account is the leaf-to-group link.

---

## Account Groups (`account.group`)

> [`models/account_account.py:1484`](../addons/account/models/account_account.py#L1484)

Account groups organize accounts into a hierarchical tree for financial reporting.
A group matches accounts by **code prefix range**, not by direct linkage.

**For managers:** Think of groups as folders in a filing cabinet. You label each folder with a range (e.g., "accounts 1500 through 1599 go in the Fixed Assets folder"). Odoo automatically sorts accounts into the right folder based on their code.

### Fields

| Field | Type | Purpose |
|---|---|---|
| `name` | `Char` | Group label (e.g., "Fixed Assets") |
| `code_prefix_start` | `Char` | Lowest account code prefix in this group (e.g., `15`) |
| `code_prefix_end` | `Char` | Highest account code prefix in this group (e.g., `19`) |
| `parent_id` | `Many2one` `account.group` | Parent group (auto-resolved, not manually set) |
| `company_id` | `Many2one` `res.company` | Root company that owns this group |

### How account-to-group assignment works

When `account.account._compute_account_group()` runs, it executes a SQL query that finds
the group whose `code_prefix_start..code_prefix_end` range contains the account's code,
preferring the group with the **longest** matching prefix (most specific):

```sql
SELECT DISTINCT ON (account_code.code)
    account_code.code,
    agroup.id AS group_id
FROM (VALUES ...) AS account_code(code)
LEFT JOIN account_group agroup
    ON agroup.code_prefix_start <= LEFT(account_code.code, char_length(agroup.code_prefix_start))
   AND agroup.code_prefix_end   >= LEFT(account_code.code, char_length(agroup.code_prefix_end))
   AND agroup.company_id = <root_company_id>
ORDER BY account_code.code, char_length(agroup.code_prefix_start) DESC, agroup.id
```

Source: [`_compute_account_group()`](../addons/account/models/account_account.py#L418)

### How the "most specific wins" rule works — with example

Given these groups:

| Group name | Prefix start | Prefix end | Prefix length |
|---|---|---|---|
| Non-current Assets | `15` | `19` | 2 digits |
| Fixed Assets | `150` | `159` | 3 digits |
| Equipment | `1501` | `1501` | 4 digits |

For account code `1501`:

| Step | Group checked | Does `1501` match? | Prefix length |
|---|---|---|---|
| 1 | Non-current Assets (15-19) | Yes, `15` <= `15` and `19` >= `15` | 2 |
| 2 | Fixed Assets (150-159) | Yes, `150` <= `150` and `159` >= `150` | 3 |
| 3 | Equipment (1501-1501) | Yes, `1501` <= `1501` and `1501` >= `1501` | 4 |

**Winner:** Equipment (longest prefix = most specific match). The `ORDER BY char_length(agroup.code_prefix_start) DESC` ensures the most specific group always wins.

### Hierarchy auto-resolution

[`_adapt_parent_account_group()`](../addons/account/models/account_account.py#L1587) runs on every group create/write.
It automatically assigns `parent_id` by finding the group with the **next-shorter** matching prefix.

In the example above, the auto-resolved hierarchy would be:
```
Non-current Assets (15-19)
  └── Fixed Assets (150-159)
       └── Equipment (1501-1501)
```

This is why you never manually set `parent_id` — Odoo computes it from prefix nesting.

### Deleting a group

When a group is deleted, its children are **re-parented** to the deleted group's parent ([`unlink()`](../addons/account/models/account_account.py#L1581)):

```
Before delete:  Assets (1-1) -> Current (10-10) -> Cash (101-101)
Delete "Current (10-10)":
After:          Assets (1-1) -> Cash (101-101)
```

The hierarchy is never left with orphaned children.

### Constraints

- Groups at the same **prefix length** cannot have overlapping ranges. For example, you cannot have Group A = `150-159` and Group B = `155-164` because account `1550` would match both.
- Source: [`_constraint_prefix_overlap()`](../addons/account/models/account_account.py#L1536)
- `code_prefix_start` and `code_prefix_end` must have the same length.
- Source: `_check_length_prefix` constraint on the model.
- `parent_id` cannot be circular — [`_check_parent_not_circular()`](../addons/account/models/account_account.py#L1564) uses `_has_cycle()` check.

---

## Account Root (`account.root`)

> [`models/account_root.py`](../addons/account/models/account_root.py)

`account.root` is a **virtual model** (`_auto = False`, `_table_query = '0'`).
It has no database table — it is entirely computed in Python.

An account root is simply the **first 2 characters of an account code**.
For code `4100`, the root is `41`. For code `41`, the root is still `41`.

**Purpose:** provides a grouping node for the left-side search panel in the COA list view.
Users can click `41` to filter all 41xx accounts.

### Fields

| Field | Type | How it's computed |
|---|---|---|
| `id` | `Char` (string-based) | First 2 chars of account code — e.g. `"41"` |
| `name` | `Char` (computed) | Same as `id` — [`account_root.py:38`](../addons/account/models/account_root.py#L38) |
| `parent_id` | `Many2one` `account.root` (computed) | `id[:-1]` — trim last character. `"41"` -> parent `"4"`, `"4"` -> `False` (no parent) — [`account_root.py:39`](../addons/account/models/account_root.py#L39) |

### Parent-child logic

The parent chain is built by progressively trimming the last character of the root ID:

```
"41" -> parent "4" -> parent False (top level)
"10" -> parent "1" -> parent False (top level)
```

This creates a virtual 2-level tree (single digit -> two digits) used solely for the search panel `child_of` filtering.

### Search restrictions

`_search()` only supports two domain forms ([`account_root.py:24-30`](../addons/account/models/account_root.py#L24-L30)):
- `('id', 'in', ids)` — exact match
- `('id', 'parent_of', ids)` — returns all prefixes of the given IDs using `accumulate()`. E.g., `parent_of ['41']` returns `{'4', '41'}`.

Any other domain raises `UserError`.

### How accounts link to roots

`account.root._from_account_code(code)` returns `self.browse(code[:2])`.
Source: [`account_root.py:33`](../addons/account/models/account_root.py#L33)

Each `account.account` has a computed `root_id` field that calls this method on its `placeholder_code`.
Source: [`_compute_account_root()`](../addons/account/models/account_account.py#L380)

---

## Account Tags (`account.account.tag`)

> [`models/account_account_tag.py`](../addons/account/models/account_account_tag.py)

Tags are free-form labels attached to accounts (or taxes, or products).

### Fields

| Field | Type | Purpose |
|---|---|---|
| `name` | `Char` | Tag label |
| `applicability` | `Selection` | `accounts` / `taxes` / `products` — controls where tag is usable |
| `country_id` | `Many2one` `res.country` | Limits tag to one country (mainly for tax tags) |
| `report_expression_id` | `Many2one` (computed) | If generated by a report line (`tax_tags` engine), links back to it |
| `balance_negate` | `Boolean` (computed) | If True, the report uses `-balance` for this tag |

**Unique constraint:** `(name, applicability, country_id)` — no duplicate tag per scope.

**How tags auto-propagate to new accounts:**

When creating a new account with a code that has no explicit tags, Odoo uses
[`_get_closest_parent_account()`](../addons/account/models/account_account.py#L613)
to find the nearest account (by code, sorted alphabetically) and copies its `tag_ids`.
This means new accounts automatically inherit tags from nearby-coded accounts.

**Account tags vs tax tags:**
- `applicability = 'accounts'` — used for custom reporting groupings on the COA.
- `applicability = 'taxes'` — generated by report engine; linked to `account.report.expression` records; used in tax declarations.

---

## Opening Balances

When migrating from another system, you set the starting balance for each account. This is how Odoo knows what your financial position was before you started using it.

### How it works — the hidden journal entry

Behind the scenes, Odoo does not store opening balances as a simple number on the account. Instead, it creates a real journal entry (a proper accounting transaction) that represents your starting position.

The company has a special journal entry: `company.account_opening_move_id`. This is a single journal entry that holds ALL opening balance lines for every account.

Fields `opening_debit` / `opening_credit` / `opening_balance` on `account.account` are computed
by reading lines from this single move.

**Example:** You had $50,000 in the bank and $20,000 in customer receivables before Odoo:

```
Opening Journal Entry (account_opening_move_id):
  Line 1: Debit  Bank Account (1010)         $50,000
  Line 2: Debit  Accounts Receivable (1100)   $20,000
  Line 3: Credit Opening Balance Equity       $70,000  (balancing entry)
```

### What happens when you set an opening balance

Source: [`_set_opening_balance()`](../addons/account/models/account_account.py#L683)

```python
def _set_opening_balance(self):
    for account in self:
        balance = account.opening_balance
        # Positive balance -> Debit line
        # Negative balance -> Credit line
        account._set_opening_debit_credit(abs(balance) if balance > 0.0 else 0.0, 'debit')
        account._set_opening_debit_credit(abs(balance) if balance < 0.0 else 0.0, 'credit')
```

### Performance optimization — batch writing

If you import 500 accounts with opening balances, Odoo does NOT update the opening journal entry 500 separate times. Instead:

Source: [`_set_opening_debit_credit()`](../addons/account/models/account_account.py#L690)

```python
# Odoo batches all opening balance writes using a precommit hook
if 'import_account_opening_balance' not in self.env.cr.precommit.data:
    data = self.env.cr.precommit.data['import_account_opening_balance'] = {}
    self.env.cr.precommit.add(self._load_precommit_update_opening_move)
```

It collects all changes, then writes them to the opening move in a single operation just before the database transaction commits. This is critical for import performance.

### Company fields involved

| Field | UI Label | Purpose |
|---|---|---|
| `account_opening_move_id` | "Opening Journal Entry" | The move that holds all opening balances |
| `account_opening_journal_id` | "Opening Journal" | Related via `account_opening_move_id.journal_id` |
| `account_opening_date` | "Opening Entry" | Date of the opening entry |

Source: [`company.py:176`](../addons/account/models/company.py#L176)

---

## How Odoo Picks Accounts Automatically

This is the core COA automation: when a user creates an invoice line, Odoo resolves the correct account without manual selection. The logic is in [`_compute_account_id()`](../addons/account/models/account_move_line.py#L573).

**For managers:** You do not need to pick an account every time you create an invoice. Odoo figures out which account to use based on the product, the customer, and company defaults. Here is the exact decision process.

### Complete Invoice Line Account Resolution Flow

```
User creates a Customer Invoice line
                |
                v
+--------- What type of line is this? ---------+
|                                               |
v                                               v
PAYMENT TERM LINE                          PRODUCT LINE
(the "total amount due" line               (a line with a product or
 that tracks what customer owes)            amount to invoice)
        |                                       |
        v                                       v
  1. Was an account previously           Is a product selected?
     set on this invoice?                    |           |
     (SQL lookup on same move)              YES          NO
        |                                   |            |
     YES -> use it                          v            v
     NO  -> continue                  Product has     Partner set?
        |                             accounts?        |        |
        v                                |            YES       NO
  2. Partner's receivable account       YES            |         |
     partner.commercial_partner_id       |             v         v
     .property_account_receivable_id     v        Use partner's  Fall
     (or _payable_id for vendor bills)  Get it:   most frequent  through
        |                               1. Product-level account       |
     Found -> use it                       property_account_income_id  |
     Empty -> continue                  2. Category-level              |
        |                                  categ_id.property_          |
        v                                  account_income_categ_id     |
  3. Company partner's account          3. Company default             |
     company.partner_id.property_          company.income_account_id   |
     account_receivable_id                    |                        |
        |                                     v                        |
        v                              Apply fiscal position           |
  4. First active receivable/payable
     account in the company (SQL fallback)               map_account() if set            |
        |                                                              |
        v                              <-------------------------------+
  Apply fiscal position                         |
  map_account() if set                          v
                                    FALLBACK (still no account):
                                      1. Do previous 2 lines on this
                                         invoice use the same account?
                                         YES -> use it
                                      2. journal.default_account_id
```

Source: [`account_move_line.py:573`](../addons/account/models/account_move_line.py#L573) and [`product.py:65`](../addons/account/models/product.py#L65)

### Key points

- Fiscal position is **always applied last** — it substitutes the resolved account with a mapped one. It never picks the account from scratch; it only replaces it.
- The "most frequent account for partner" lookup searches the last 2 years of invoice lines for that partner, filtered by `internal_group` (`income` for sales, `expense` for purchases).
  Source: [`_get_most_frequent_accounts_for_partner()`](../addons/account/models/account_account.py#L730)

---

## Property Account System — How Defaults Cascade

This is the mechanism that makes the account resolution flow above work — where the "default" accounts for partners and products come from.

### What it is

Odoo uses `ir.default` records to store company-specific default field values. `property_account_*` fields on `res.partner` and `product.template` are `company_dependent=True` fields backed by `ir.default`.

When you install a chart template, `_load_data()` in [`chart_template.py:562`](../addons/account/models/chart_template.py#L562) sets these defaults:

| `ir.default` model | Field | What it sets |
|---|---|---|
| `res.partner` | `property_account_receivable_id` | Default receivable account for all partners |
| `res.partner` | `property_account_payable_id` | Default payable account for all partners |
| `product.category` | `property_account_income_categ_id` | Default income account for product categories |
| `product.category` | `property_account_expense_categ_id` | Default expense account for product categories |

These defaults are per-company (`company_id=company.id` in `ir.default.set()`).

### Concrete Example — Which Expense Account Gets Used?

You create a vendor bill for an "Office Supplies" product. Which expense account does Odoo use?

```
Product: "Office Supplies"
  property_account_expense_id = ? (empty — not set on this product)
    |
    v  Falls back to...
Category: "Supplies"
  property_account_expense_categ_id = ? (empty — not set on this category)
    |
    v  Falls back to...
Company Settings
  expense_account_id = "6000 - Operating Expenses"   <-- USED
```

The code that implements this cascade:

Source: [`product.py:65`](../addons/account/models/product.py#L65)
```python
def _get_product_accounts(self):
    return {
        'income': (
            self.property_account_income_id
            or self.categ_id.property_account_income_categ_id
            or (self.company_id or self.env.company).income_account_id
        ),
        'expense': (
            self.property_account_expense_id
            or self.categ_id.property_account_expense_categ_id
            or (self.company_id or self.env.company).expense_account_id
        ),
    }
```

### Override hierarchy — when to use each level

| Level | Where to Set | When to Use | Example |
|---|---|---|---|
| Product | Product form > Accounting tab > "Expense Account" | When THIS specific product needs a different account | "Hardware Purchases" product posts to 5100 instead of 6000 |
| Category | Product Category form > Accounting Properties | When all products in this category share the same account | All "Software" products post to 5200 |
| Company | Settings > Accounting > "Expense Account" | Default for all products without overrides | Everything else posts to 6000 |

**Important:** These are `company_dependent=True` fields — you can set different defaults per company in a multi-company setup.

**In practice:** most companies never touch partner-level overrides. The category-level override is used when different product lines (e.g., software vs. hardware) post to different revenue accounts.

---

## Fiscal Position (Account Mapping)

A fiscal position overrides which account (and taxes) are used when invoicing a partner in a specific country or VAT regime.

**For managers:** If you sell to customers in different countries, a fiscal position automatically swaps the account and tax used on their invoices. For example, a domestic sale might use "Sales Revenue (Domestic)" with 20% VAT, while an EU sale uses "Sales Revenue (EU)" with 0% VAT — and this swap happens automatically.

### How it works

`map_account(account)` at [`partner.py:165`](../addons/account/models/partner.py#L165):

```python
def map_account(self, account):
    return self.env['account.account'].browse(
        (self.account_map or {}).get(account.id, account.id)
    )
```

`account_map` is a `{src_id: dest_id}` dict computed from `account.fiscal.position.account` lines.
If the account has no mapping, it passes through unchanged.

### Which fiscal position is used

[`_get_fiscal_position()`](../addons/account/models/partner.py#L247) resolution order:

1. `delivery.property_account_position_id` — manually set on the delivery address
2. `partner.property_account_position_id` — manually set on the partner
3. Auto-apply: searches all `AccountFiscalPosition` with `auto_apply = True`, picks the first matching one

### Auto-apply matching criteria

| Field | Matches when |
|---|---|
| `country_id` | Partner's delivery country equals this |
| `country_group_id` | Partner's delivery country is in this group (e.g., EU) |
| `state_ids` | Partner's delivery state is in this list |
| `zip_from` / `zip_to` | Partner's zip code is in this range |
| `vat_required = True` | Only apply if partner has a VAT number set |

All set criteria must match. Positions are evaluated in `sequence` order.

### `foreign_vat` — your company in another country

If your company registers for VAT in another country (e.g., you're a UK company registered for French VAT), set `foreign_vat` on the fiscal position. This links the position to a second tax registration. Odoo can then load that country's taxes via `action_create_foreign_taxes()`.

Source: [`partner.py:66`](../addons/account/models/partner.py#L66)

### Where to configure

Accounting > Configuration > Fiscal Positions

---

## Account Suggestions on Invoice Lines

When a user picks an account on a journal line, Odoo suggests accounts ordered by frequency of use for that partner.

**Logic:**
1. Look up `account.move.line` for the same partner, last 2 years.
2. Order by count of usage (most used first).
3. Filter by `internal_group`: `income` for customer invoices, `expense` for vendor bills.

Source: [`_get_most_frequent_accounts_for_partner()`](../addons/account/models/account_account.py#L730)
Suggested accounts are marked `Suggested` in the dropdown.
Source: [`_compute_display_name()`](../addons/account/models/account_account.py#L868)

---

## Configuration — Company Settings

Settings are in `res.config.settings` (transient), mostly relayed to `res.company`.

Source: [`models/res_config_settings.py`](../addons/account/models/res_config_settings.py)

| Setting field | UI Label | Where stored | Effect |
|---|---|---|---|
| `currency_id` | "Currency" | `company_id.currency_id` | Company's primary currency |
| `chart_template` | (COA picker) | `company_id.chart_template` | Which chart of accounts is loaded |
| `account_fiscal_country_id` | "Fiscal Country Code" | `company_id.account_fiscal_country_id` | Country for tax reporting |
| `tax_calculation_rounding_method` | "Tax Calculation Rounding Method" | `company_id.tax_calculation_rounding_method` | `round_globally` (per tax) vs `round_per_line` |
| `currency_exchange_journal_id` | "Exchange Gain or Loss Journal" | `company_id.currency_exchange_journal_id` | Journal for FX gain/loss entries |
| `income_currency_exchange_account_id` | "Gain Exchange Rate Account" | `company_id.income_currency_exchange_account_id` | Account for FX gains (`internal_group = income`) |
| `expense_currency_exchange_account_id` | "Loss Exchange Rate Account" | `company_id.expense_currency_exchange_account_id` | Account for FX losses (`account_type = expense`) |
| `account_journal_suspense_account_id` | "Bank Suspense" | `company_id.account_journal_suspense_account_id` | Temporary account for unreconciled bank imports |
| `transfer_account_id` | "Internal Transfer" | `company_id.transfer_account_id` | Intermediary account between two bank journals |
| `group_cash_rounding` | "Cash Rounding" | `implied_group = account.group_cash_rounding` | Enables cash rounding on invoices |
| `tax_exigibility` | "Cash Basis" | `company_id.tax_exigibility` | Enables cash basis tax computation |

---

## Security Groups

Source: [`security/account_security.xml`](../addons/account/security/account_security.xml)

| Group | XML ID | Who it gives | Implied by |
|---|---|---|---|
| Billing (Invoice) | `group_account_invoice` | Create/edit invoices, payments | `group_account_basic`, `group_account_manager` |
| Basic Accounting | `group_account_basic` | Invoice + basic bank reconciliation | `group_account_user` |
| Read-only Accounting | `group_account_readonly` | See everything (entries, reports, advanced config) | `group_account_user` |
| Accountant (User) | `group_account_user` | Full accounting except advanced config | — |
| Accounting Manager | `group_account_manager` | Everything including lock dates, COA setup | — |
| Secured Entries | `group_account_secured` | Hash-locked entry integrity | — |
| Cash Rounding | `group_cash_rounding` | Enabled by "Cash Rounding" setting | — |

**Who can see account codes in dropdowns:**
`group_account_readonly` — the `display_name` of an account only shows its code
to users in this group. Others see only the name.
Source: [`_compute_display_name()`](../addons/account/models/account_account.py#L868)

---

## Multi-Company Account Sharing

An `account.account` belongs to `company_ids` (Many2many).
Two companies in the same root hierarchy can share the same account record while each having a different code stored in `code_store`.

**Constraints:**
- `asset_cash` accounts **cannot** be shared — they are per-company (bank accounts).
  Source: [`_check_company_consistency()`](../addons/account/models/account_account.py#L269)
- You cannot remove a company from an account if that company has posted journal lines on it.
- `asset_receivable` and `liability_payable` accounts must always have `reconcile = True`.
  Source: [`_check_reconcile()`](../addons/account/models/account_account.py#L27)

---

## Common Mistakes and How Odoo Prevents Them

These are the most frequent errors users encounter when working with the COA. Odoo blocks all of them with validation errors, but understanding WHY they are blocked helps avoid confusion.

### Mistake 1: Making a Receivable/Payable Account Non-Reconcilable

**What you tried:** Unchecked "Allow Reconciliation" on a Receivable account.

**Why Odoo blocks it:** Receivable and Payable accounts MUST be reconcilable. Reconciliation is how Odoo matches a customer's $500 payment against their $500 invoice. Without it, you could never close out invoices.

Source: [`_check_reconcile()`](../addons/account/models/account_account.py#L27)

### Mistake 2: Setting a Receivable/Payable Account as a Journal Default

**What you tried:** Changed a Sales journal's default account to a Receivable-type account.

**Why Odoo blocks it:** Sales/Purchase journals expect income/expense accounts as their default. The receivable/payable line is auto-generated separately by the payment term logic. If the default account were Receivable, every invoice line would post to Receivable — making it impossible to track revenue.

Source: [`_check_account_type_sales_purchase_journal()`](../addons/account/models/account_account.py#L291)

### Mistake 3: Currency Mismatch Between Account and Journal

**What you tried:** Set a EUR currency on an account, but the journal using it is set to USD.

**Why Odoo blocks it:** If a journal forces a currency (e.g., a EUR bank journal), every account it uses must either have no currency set (flexible) or match the journal's currency exactly. A mismatch would produce journal entries with conflicting currency amounts.

Source: [`_check_journal_consistency()`](../addons/account/models/account_account.py#L197)

### Mistake 4: Creating Overlapping Account Groups

**What you tried:** Created Group A covering codes 150-159 and Group B covering 155-164.

**Why Odoo blocks it:** Account code `1550` would match BOTH groups. Odoo needs exactly one group per account for unambiguous financial reporting. Groups at the same prefix length cannot overlap.

Source: [`_constraint_prefix_overlap()`](../addons/account/models/account_account.py#L1536)

---

## UI Entry Points

| Entry Point | Path in UI | What It Does |
|---|---|---|
| Chart of Accounts list | Accounting > Accounting > Chart of Accounts | List all accounts; filter by root/group; edit codes, types, tags |
| Account form | Click any account in COA list | Edit account details; set opening balance; view related taxes |
| Account Groups | Accounting > Configuration > Account Groups | Define prefix ranges and group hierarchy |
| Account Tags | Accounting > Configuration > Account Tags | Create/edit tags (applicability: accounts/taxes/products) |
| Settings > Accounting | Settings > Accounting | Chart template, currency, fiscal country, special accounts |
| Setup Wizard | First access to Accounting app | Walks through chart template selection + opening date |

---

## Business Flow — First-Time Setup

```
New company created
    |
    v
Odoo shows Setup Wizard (onboarding)
    |
    v
User picks chart template (or country auto-selects one)
    |
    v
AccountChartTemplate.try_loading() runs
    |
    v
account.group records created (prefix ranges)
account.account records created (100-500+ accounts depending on localization)
account.tax records created
account.journal records created (Sales, Purchase, Bank, Cash, Misc)
    |
    v
Company fields set: bank_account_code_prefix, special account IDs, etc.
    |
    v
User sets Opening Date (account_opening_date)
    |
    v
User enters opening balances on each account (writes to account_opening_move_id)
    |
    v
User posts opening entry -> accounting is live
```

---

## Stock Variation Account (`account_stock_variation_id`)

> Added by **`stock_account`** module
> Field defined at: [`stock_account/models/account_account.py:7`](../addons/stock_account/models/account_account.py#L7)

### What it is

A field on `account.account` that points to another account used as the counterpart when recording inventory value adjustments at period close.

```python
account_stock_variation_id = fields.Many2one(
    'account.account', string='Variation Account',
    help="At closing, register the inventory variation of the period into a specific account")
```

There is also a companion field on the same model:

| Field | Type | Purpose |
|---|---|---|
| `account_stock_variation_id` | `Many2one` `account.account` | Counterpart for inventory value adjustments (stock variation) |
| `account_stock_expense_id` | `Many2one` `account.account` | Counterpart for continental perpetual accounting adjustments |

Source: [`stock_account/models/account_account.py:7-12`](../addons/stock_account/models/account_account.py#L7-L12)

### The problem it solves

During a fiscal period, stock moves create journal entries hitting the **Stock Valuation Account** (e.g., `1400 - Stock Valuation`). At period close, there can be a gap between:

- **Inventory system value** — what the WMS/stock module says the inventory is worth (based on `product.total_value`)
- **Accounting ledger value** — sum of all posted `account.move.line.balance` on the stock valuation account

This gap is the **stock variation**. Causes include: timing differences (goods received but not yet invoiced), rounding, manual adjustments, inventory adjustments (shrinkage, damage), or cost method differences. The variation account is where Odoo records the adjustment entry to bring the books in line with actual inventory.

### Where it's configured

The variation account is set **on the stock valuation account itself**, not on the product or category. The chain:

```
Product Category (product.category)
  -> property_stock_valuation_account_id  (e.g. "1400 Stock Valuation")
       -> account_stock_variation_id      (e.g. "6100 Stock Variation")
```

The product category also exposes it as a related field for convenience:
Source: [`stock_account/models/product.py:521-523`](../addons/stock_account/models/product.py#L521-L523)

```python
# on product.category
account_stock_variation_id = fields.Many2one(
    'account.account', string="Stock Variation Account",
    related="property_stock_valuation_account_id.account_stock_variation_id")
```

### Company-level settings involved

These are on `res.company`, added by `stock_account`:

| Field | UI Label | Purpose |
|---|---|---|
| `account_stock_journal_id` | "Stock Journal" | The journal where closing entries are posted |
| `account_stock_valuation_id` | "Stock Valuation Account" | Company-level fallback valuation account |
| `inventory_period` | "Inventory Period" | `manual` / `daily` / `monthly` — controls auto-close cron |
| `inventory_valuation` | "Valuation" | `periodic` (at closing) / `real_time` (at invoicing) |
| `cost_method` | "Cost Method" | `standard` / `fifo` / `average` |

Source: [`stock_account/models/res_company.py:12-47`](../addons/stock_account/models/res_company.py#L12-L47)

### The full closing flow — step by step

When you click **"Close Inventory Valuation"** (or the cron runs), the method `action_close_stock_valuation()` executes:

Source: [`stock_account/models/res_company.py:49`](../addons/stock_account/models/res_company.py#L49)

```
1. _get_accounts_by_product()
   Loads all storable products, gets each product's:
     - valuation account (from product category -> property_stock_valuation_account_id)
     - variation account (from valuation account -> account_stock_variation_id)
     - expense account  (from product -> _get_product_accounts()['expense'])

2. _get_location_valuation_vals()           [STEP A: Location reclassification]
   For products with PERIODIC valuation only.
   Reads stock.move records since last closing.
   If stock locations have their own valuation_account_id,
   moves value from that location account to the product's stock valuation account.
   This handles multi-warehouse scenarios where goods move between locations
   that use different valuation accounts.

3. _get_stock_valuation_account_vals()      [STEP B: Global stock variation]
   Compares:
     inventory_value = sum of product.total_value per valuation account
     accounting_value = sum of posted journal lines on the valuation account
   Difference goes to the variation account.
   Fallback: company.expense_account_id if no variation account set.

4. _get_continental_realtime_variation_vals() [STEP C: Continental perpetual]
   Only applies when inventory_valuation = 'real_time' (perpetual).
   Computes the accounting value change over the fiscal period
   (today vs fiscal year start date).
   Posts variation between account_stock_variation_id and account_stock_expense_id.

5. Creates a single account.move in the Stock Journal with all lines.
   If triggered by cron (auto_post=True), posts automatically.
```

### Real-world example — periodic valuation (standard cost)

**Setup:**
- Company uses periodic valuation with standard costing
- Product "Laptop" — standard price $500, category "Electronics"
- Electronics category: `property_stock_valuation_account_id` = `1400 Stock Valuation`
- Account `1400` has: `account_stock_variation_id` = `6100 Stock Variation`

**During the month:**
1. Receive 100 laptops from vendor (PO receipt) — stock module records 100 units
2. Ship 20 laptops to customers (delivery orders) — stock module records 80 units remaining
3. Inventory adjustment: 2 laptops damaged — stock module records 78 units remaining

**At month-end closing:**

| Source | Value |
|---|---|
| Inventory system (`product.total_value`) | 78 units x $500 = **$39,000** |
| Accounting ledger (sum of posted lines on `1400`) | Maybe **$38,500** (due to timing of invoice postings) |
| **Gap** | **$500** |

Odoo creates:

```
Stock Closing Journal Entry (in Stock Journal):
  Debit   1400 Stock Valuation     $500
  Credit  6100 Stock Variation     $500
  Ref: "Closing: Stock Variation Global for company [My Company]"
```

After posting, the ledger on `1400` now shows $39,000 — matching inventory.

### Real-world example — continental perpetual (real-time)

**Setup:**
- Company uses perpetual/real-time valuation (European/Continental style)
- Same product category, but `inventory_valuation = 'real_time'`
- Account `1400` also has: `account_stock_expense_id` = `6000 Operating Expenses`

**During the month:**
- Every stock move (receipt, delivery, adjustment) already creates journal entries in real-time
- But the **variation** (difference between expenses recognized and inventory movement) is NOT posted during the period

**At month-end closing:**

Odoo computes:
```
accounting_value_today       = sum of posted lines on 1400 as of today
accounting_value_fiscal_start = sum of posted lines on 1400 as of Jan 1
variation_over_period        = today - fiscal_start + existing_variation_balance
```

If variation is non-zero:

```
Stock Closing Journal Entry:
  Debit   6000 Operating Expenses    $300
  Credit  6100 Stock Variation       $300
  Ref: "Closing: Stock Variation Over Period"
```

Note: in continental mode, both `account_stock_variation_id` AND `account_stock_expense_id` must be set on the valuation account. If either is missing, the account is silently skipped.
Source: [`stock_account/models/res_company.py:276`](../addons/stock_account/models/res_company.py#L276)

### Automatic closing via cron

Source: [`stock_account/models/res_company.py:136`](../addons/stock_account/models/res_company.py#L136)

The cron `_cron_post_stock_valuation()` runs for companies where:
- `inventory_period = 'daily'` and `inventory_valuation != 'real_time'` — runs every day
- `inventory_period = 'monthly'` — runs only on the last day of the month

It calls `action_close_stock_valuation(auto_post=True)`, which creates AND posts the closing entry automatically.

### In the generic COA

| What | Value | Source |
|---|---|---|
| Account record | `6100 - Stock Variation`, type `expense` | [`generic_coa.csv:34`](../addons/account/data/template/account.account-generic_coa.csv#L34) |
| Company field | `account_stock_variation_id` -> `stock_variation` | [`template_generic_coa.py:60`](../addons/account/models/template_generic_coa.py#L60) |

### How the balance calculation works in code

Source: [`stock_account/models/res_company.py:85-115`](../addons/stock_account/models/res_company.py#L85-L115)

```python
# Inventory value: from stock module (product quantities x cost)
def stock_value(self, accounts_by_product, at_date):
    for product, accounts in accounts_by_product.items():
        account = accounts['valuation']
        product_value = product.with_context(to_date=at_date).total_value
        value_by_account[account] += product_value

# Accounting value: from posted journal entries
def stock_accounting_value(self, accounts_by_product, at_date):
    # SELECT account_id, SUM(balance)
    # FROM account_move_line
    # WHERE account_id IN (valuation_accounts) AND state = 'posted'
    amls_group = self.env['account.move.line']._read_group(
        domain, ['account_id'], ['balance:sum']
    )
```

The variation = `stock_value() - stock_accounting_value()`. If positive, inventory is worth more than the books show (increase valuation). If negative, inventory is worth less (shrinkage/loss).

### Summary table — which accounts are involved

| Account | Role | Example code | Where configured |
|---|---|---|---|
| Stock Valuation | Holds inventory value on balance sheet | `1400` | Product Category > `property_stock_valuation_account_id` |
| Stock Variation | Receives the closing adjustment (counterpart) | `6100` | On the valuation account > `account_stock_variation_id` |
| Stock Expense | Continental perpetual expense counterpart | `6000` | On the valuation account > `account_stock_expense_id` |
| Stock Journal | Journal where closing entries are posted | `STJ` | Settings > `account_stock_journal_id` |

---

## Edge Cases & Gotchas

- **`equity_unaffected` is special:** It is the only equity account where `include_initial_balance = False`. Odoo uses it to show "current year earnings" on the balance sheet. If you use a wrong account type here, your balance sheet will not balance.

- **Changing `account_type` is blocked when used as a journal default:** If a **sale or purchase** journal has `default_account_id` pointing to an account, changing its type to `asset_receivable` or `liability_payable` raises a `ValidationError`. General/bank/cash journals are not affected. Source: [`_check_account_type_sales_purchase_journal()`](../addons/account/models/account_account.py#L291).

- **Changing currency on account checks journal consistency:** If a journal uses this account and has a currency set, both must match. Source: [`_check_journal_consistency()`](../addons/account/models/account_account.py#L197).

- **Account codes are per company root, not per company:** In a branch setup, `company_id = branch` and `company_id.root_id = parent`. The branch's accounts share codes with the parent via `code_store[root_id]`. Changing a code in one company changes it for all companies sharing the same root.

- **`account.root` is not a real DB model:** It has `_auto = False` and `_table_query = '0'`. Searching it with any domain other than `('id', 'in', ...)` or `('id', 'parent_of', ...)` raises `UserError`. Source: [`account_root.py:24`](../addons/account/models/account_root.py#L24).

- **`off_balance` accounts:** Cannot have `reconcile = True` and cannot have `tax_ids`. Odoo enforces both. Source: [`_constrains_reconcile()`](../addons/account/models/account_account.py#L188).

- **Reloading a chart template** (when the same template is already installed): `_pre_reload_data()` runs first. It strips reconcile models, skips existing journals, and preserves tax names by prefixing old ones with `[old]`. It does NOT delete accounts. Source: [`chart_template.py:264`](../addons/account/models/chart_template.py#L264).

- **New account type auto-inference:** When you create an account with a code but no type, Odoo calls `_get_closest_parent_account()` to find the nearest account by code (binary search on sorted codes) and copies its `account_type`. Default if nothing matches: `asset_current`. Source: [`_compute_account_type()`](../addons/account/models/account_account.py#L604).

---

## Related Docs

- [`INDEX.md`](INDEX.md)

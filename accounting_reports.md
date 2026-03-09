# Accounting Reports Engine

> **Module:** `account_reports` (enterprise) | **Path:** [`enterprise/account_reports/`](../enterprise/account_reports/)
> **Odoo Apps category:** Accounting / Accounting
> **Depends on:** `account_accountant`

## What It Does

The reporting engine is a **configurable, data-driven framework** for financial statements.
Every report (Balance Sheet, P&L, Tax Return, General Ledger, etc.) is a set of database records —
`account.report`, `account.report.line`, `account.report.expression` — not hardcoded code.
The engine computes values by dispatching each expression to one of 6 **engines** that run SQL against `account.move.line`.
The result is an interactive on-screen view with drill-down, filtering, PDF/XLSX export, and period comparison.

---

## Dependencies

| Module | Why |
|---|---|
| `account_accountant` | Provides full accounting with posted entries |
| `account` | Core `account.report` base model defined here |

### Provides To

| Consumer | What it uses |
|---|---|
| `l10n_*` modules | Extend `account.report` with localized tax reports using `root_report_id` + `country_id` |
| `account_reports_cash_basis` | `only_tax_exigible` filter on tax reports |
| `account_budget` | `filter_budgets` option on P&L |

---

## Architecture: Three-Layer Model

```
account.report          ← one report (e.g. "Balance Sheet")
    └── account.report.line       ← one row (e.g. "Current Assets")
            └── account.report.expression  ← one cell computation per column
                    engine = domain | tax_tags | aggregation | account_codes | external | custom
                    formula = the computation rule
                    subformula = modifier on the result
                    date_scope = time window for the query
```

Every number on a financial report comes from an `account.report.expression` evaluated by its engine.

---

## Core Models

### `account.report` — The Report Definition

> [`addons/account/models/account_report.py`](../addons/account/models/account_report.py)
> Extended by [`enterprise/account_reports/models/account_report.py`](../enterprise/account_reports/models/account_report.py)

| Field | Type | Purpose |
|---|---|---|
| `name` | `Char` | Report name shown in UI and menus |
| `line_ids` | `One2many` `account.report.line` | All rows of this report |
| `column_ids` | `One2many` `account.report.column` | Column headers; each matches an expression `label` |
| `root_report_id` | `Many2one` `account.report` | Points to the generic root; this report is a **variant** |
| `variant_report_ids` | `One2many` | All country/COA-specific variants of this report |
| `section_report_ids` | `Many2many` | Sub-reports for **composite** reports |
| `use_sections` | `Boolean` (computed) | True if this is a composite report |
| `country_id` | `Many2one` `res.country` | Restricts report to one country |
| `chart_template` | `Selection` | Restricts report to one COA |
| `availability_condition` | `Selection` | When to show this report: `always`, `country`, `coa` |
| `custom_handler_model_id` | `Many2one` `ir.model` | A model inheriting `account.report.custom.handler` for special computation logic |
| `default_opening_date_filter` | `Selection` | Default date range when report opens |

**Filter fields** (each adds a filter widget in the UI):
`filter_date_range`, `filter_journals`, `filter_analytic`, `filter_partner`, `filter_hierarchy`,
`filter_period_comparison`, `filter_growth_comparison`, `filter_hide_0_lines`, `filter_multi_company`, etc.

---

### `account.report.line` — A Report Row

> [`addons/account/models/account_report.py:349`](../addons/account/models/account_report.py#L349)

| Field | Type | Purpose |
|---|---|---|
| `name` | `Char` | Row label (e.g., "Current Assets") |
| `code` | `Char` | Unique identifier used by aggregation formulas (e.g., `CA`, `REV`) |
| `parent_id` | `Many2one` | Parent line for hierarchy indentation |
| `children_ids` | `One2many` | Child lines |
| `expression_ids` | `One2many` | One expression per column/computation |
| `groupby` | `Char` | Comma-separated `account.move.line` fields; when set, expands the row into sublines |
| `hierarchy_level` | `Integer` (computed) | Indentation depth; root = 1, each level adds 3 then 2 |
| `foldable` | `Boolean` | If True, line starts folded; user must click to expand |
| `hide_if_zero` | `Boolean` | Line and children hidden when all columns are 0 |
| `horizontal_split_side` | `Selection` | `left`/`right` — for side-by-side Balance Sheet layout |
| `sequence` | `Integer` | Display order |

**Shortcut fields** (write-only, create `expression_ids` automatically):
- `domain_formula` — creates a `domain` engine expression
- `account_codes_formula` — creates an `account_codes` engine expression
- `aggregation_formula` — creates an `aggregation` engine expression
- `tax_tags_formula` — creates a `tax_tags` engine expression

---

### `account.report.expression` — One Cell Value

> [`addons/account/models/account_report.py:579`](../addons/account/models/account_report.py#L579)

| Field | Type | Purpose |
|---|---|---|
| `label` | `Char` | Matches a `account.report.column.expression_label` (e.g., `balance`, `debit`) |
| `engine` | `Selection` | Which computation engine to use (see below) |
| `formula` | `Char` | The computation rule; syntax depends on engine |
| `subformula` | `Char` | Modifier on the result (e.g., `sum`, `-sum`, `sum_if_pos`) |
| `date_scope` | `Selection` | Time window for the SQL query |
| `figure_type` | `Selection` | Number format: `monetary`, `percentage`, `integer`, `float`, `date`, `string` |
| `green_on_positive` | `Boolean` | Color coding: True = green when positive |
| `blank_if_zero` | `Boolean` | Show nothing instead of 0 |
| `auditable` | `Boolean` (computed) | Whether clicking the value opens a drill-down to journal lines |
| `carryover_target` | `Char` | For tax return carryover logic |

---

## The 6 Computation Engines

Each engine runs SQL against `account.move.line` and returns a numeric value (or group of values) for the expression.

---

### Engine 1: `domain` — Odoo Domain Filter

> [`_compute_formula_batch_with_engine_domain()`](../enterprise/account_reports/models/account_report.py#L3934)

**What it does:** Filters `account.move.line` by an Odoo domain, then aggregates the `balance` column.

**Formula syntax:** A Python list — a valid Odoo domain on `account.move.line`.

**Subformulas:**

| Subformula | Result |
|---|---|
| `sum` | Sum of all matching line balances |
| `-sum` | Negated sum (used for income accounts — credits are negative, negating gives positive revenue) |
| `sum_if_pos` | The sum, but only if it's positive; else 0 |
| `sum_if_neg` | The sum, but only if it's negative; else 0 |
| `count_rows` | Count of matching lines (or distinct groupby keys) |

**Real examples from standard reports:**

```xml
<!-- P&L: Revenue line — domain filters income accounts; -sum negates (income is credit = negative balance) -->
<field name="formula" eval="[('account_id.account_type', '=', 'income')]"/>
<field name="subformula">-sum</field>

<!-- Balance Sheet: Receivables — filters by type AND non_trade flag -->
<field name="formula" eval="[('account_id.account_type', '=', 'asset_receivable'), ('account_id.non_trade', '=', False)]"/>
<field name="subformula">sum</field>
```

**SQL generated (simplified):**

```sql
SELECT COALESCE(SUM(balance * currency_rate), 0.0) AS sum,
       COUNT(DISTINCT next_groupby_field) AS count_rows
FROM account_move_line
JOIN currency_table ON ...
WHERE <date_scope_filter> AND <company_filter> AND <journal_filter> AND <domain_filter>
GROUP BY <current_groupby_field>  -- only if the line has groupby
```

---

### Engine 2: `tax_tags` — Tax Tag Matching

> [`_compute_formula_batch_with_engine_tax_tags()`](../enterprise/account_reports/models/account_report.py#L3858)

**What it does:** Matches `account.move.line` records that carry a specific `account.account.tag`.
The tag is created automatically when the expression is created; its name equals the formula.

**Formula syntax:** A tag name string, optionally prefixed with `-` to negate.

**No subformulas supported** for this engine.

**Real use:** Tax returns and VAT reports.
Each box on a tax declaration maps to a tax tag. When you configure a tax's repartition lines with a tag,
every journal line from that tax carries that tag. The report sums those balances.

```xml
<!-- Example: a VAT report line for "VAT on sales" -->
<field name="engine">tax_tags</field>
<field name="formula">base_20</field>
```

**How tags are created:**
When `account.report.expression` with `engine = 'tax_tags'` is saved, the `_create_tax_tags()` method
creates an `account.account.tag` with `applicability = 'taxes'` for the report's country.
Source: [`account_report.py:695`](../addons/account/models/account_report.py#L695)

---

### Engine 3: `aggregation` — Formula Over Other Lines

> Handled inline in the expression-evaluation loop.
> Source: [`_compute_formula_batch`](../enterprise/account_reports/models/account_report.py#L3821) + aggregation path

**What it does:** Combines values of **other report lines** using arithmetic expressions.
The formula references other lines by their `code` field.

**Formula syntax:** Arithmetic expression using line codes + `.balance`:

```
CA.balance + FA.balance + PNCA.balance
REV.balance - COS.balance
sum_children   ← special: sum all direct child lines
```

**Subformulas for aggregation:**

| Subformula | Effect |
|---|---|
| `if_above(CUR 0)` | Show value only if above 0 |
| `if_below(CUR 0)` | Show value only if below 0 |
| `force_between(CUR -X, CUR X)` | Clamp to range |
| `cross_report(xml.id)` | Reference a line from a different report |

**Real example — Balance Sheet ASSETS total:**

```xml
<field name="code">TA</field>
<field name="aggregation_formula">CA.balance + FA.balance + PNCA.balance</field>
```

Where `CA`, `FA`, `PNCA` are codes of other lines on the same report.

**Important:** Aggregation lines do NOT run SQL themselves. They wait for all referenced lines to be computed first, then do arithmetic. This means they are always computed last in the dependency chain.

---

### Engine 4: `account_codes` — Account Code Prefix Matching

> [`_compute_formula_batch_with_engine_account_codes()`](../enterprise/account_reports/models/account_report.py#L4111)

**What it does:** Sums balances of all accounts whose **code starts with** a given prefix.
More powerful than `domain` when reports are organized by account code ranges.

**Formula syntax:** Prefix expressions with arithmetic:

```
400         ← all accounts starting with 400
400 - 500   ← 400-range minus 500-range
104\(1041)  ← all 104* accounts except 1041*
123D        ← balance of 123* accounts, only if positive (debit)
416C        ← balance of 416* accounts, only if negative (credit)
tag(ref)    ← all accounts carrying a specific tag
```

**Syntax details:**

| Syntax | Meaning |
|---|---|
| `NNN` | Sum of accounts starting with `NNN` |
| `NNN\(excl1,excl2)` | Sum excluding accounts starting with `excl1` or `excl2` |
| `NNND` | Sum only if total is positive (Debit), else 0 |
| `NNNC` | Sum only if total is negative (Credit), else 0 |
| `tag(xmlid)` | Accounts tagged with that `account.account.tag` |
| `+` / `-` | Add / subtract prefix ranges |

**How it works internally:**
1. Loads all accounts for the company, sorted by code.
2. Uses `bisect_left` to find which accounts match each prefix (fast binary search).
3. Runs one aggregated SQL query to sum their balances.

---

### Engine 5: `external` — Manually Entered Value

> [`_compute_formula_batch_with_engine_external()`](../enterprise/account_reports/models/account_report.py#L4289)

**What it does:** The value is not computed from journal lines — it is either entered by the user directly in the report, or it is the most recent previously entered value carried forward.

**Formula values:**

| Formula | Meaning |
|---|---|
| `most_recent` | Display the most recently saved value for this expression |
| `sum` | Sum all saved values in the date range |

**Subformula `editable`:** Marks the cell as user-editable in the UI.

**When to use:**
- Opening balance overrides
- External data inputs in custom reports (e.g., statistical data)
- Carryover amounts in tax returns (amounts carried from previous period)

---

### Engine 6: `custom` — Python Function

> [`_compute_formula_batch_with_engine_custom()`](../enterprise/account_reports/models/account_report.py#L4401)

**What it does:** Calls a Python method on the report's `custom_handler_model`.
The formula is the method name. The report must have `custom_handler_model_id` set to a model
that inherits `account.report.custom.handler`.

**Real examples:**

- **General Ledger**: formula = `_report_custom_engine_general_ledger`
  Computes running balance (each line's balance = previous line balance + current debit - current credit).
  Source: [`enterprise/account_reports/models/account_general_ledger.py`](../enterprise/account_reports/models/account_general_ledger.py)

- **Trial Balance**: formula = `_report_custom_engine_trial_balance`
  Shows debit/credit totals per account including opening balance.
  Source: [`enterprise/account_reports/models/account_trial_balance_report.py`](../enterprise/account_reports/models/account_trial_balance_report.py)

**Use when:** Standard engines can't express the computation — e.g., running totals, special period logic, opening balance accumulation.

---

## Date Scope

Each expression has a `date_scope` that controls which journal lines are included.

| `date_scope` value | Meaning | Used for |
|---|---|---|
| `strict_range` | Only lines within `date_from`..`date_to` | P&L, Tax Report lines |
| `from_beginning` | All lines from the beginning of time up to `date_to` | Balance Sheet — balances carry forever |
| `from_fiscalyear` | Lines from start of fiscal year to `date_to` | YTD reports |
| `to_beginning_of_fiscalyear` | Lines before fiscal year start | Opening balance at year start |
| `to_beginning_of_period` | Lines before `date_from` | Running balance / opening balance of period |
| `previous_return_period` | Lines from the previous tax return period | Carryover values in tax reports |

**Real logic:** `_get_options_date_domain()` translates `date_scope` + current options into a WHERE clause.
Source: [`account_report.py:915`](../enterprise/account_reports/models/account_report.py#L915)

---

## Options System

`get_options(previous_options)` builds the complete options dict for a report rendering.

### What `options` contains (key keys):

```python
options = {
    'report_id': 42,
    'date': {'date_from': '2025-01-01', 'date_to': '2025-12-31', 'filter': 'this_year'},
    'comparison': {'periods': [...], 'number_period': 1, 'filter': 'previous_year'},
    'journals': [{'id': 1, 'name': 'Sales', 'selected': True}, ...],
    'companies': [{'id': 1, 'name': 'My Company'}],
    'column_groups': {'column_group_0': {...}, ...},  # one per comparison period
    'hierarchy': True,
    'show_all': False,
    'unfold_all': False,
    'unfolded_lines': [...],
    'buttons': [...],
    ...
}
```

### How options are initialized:

`get_options()` calls `_get_options_initializers_in_sequence()` which returns all `_init_options_*` methods in dependency order.
Each initializer reads `previous_options` (user's previous state) and writes its section into `options`.

Key initializers:
- `_init_options_date` — sets date range from filter selection
- `_init_options_comparison` — builds comparison columns
- `_init_options_columns` — builds final column group structure
- `_init_options_companies` — resolves active companies for multi-company
- `_init_options_currency_table` — builds JOIN for currency conversion

---

## Column Groups and Comparison

The `column_groups` key in options drives multi-period comparison.
Each column group has `forced_options.date` that overrides the main date for that column.

Example (P&L with last-year comparison):

```
| Revenue | FY 2025 | FY 2024 | Change % |
|---------|---------|---------|----------|
| Sales   | 500,000 | 420,000 | +19%     |
```

Each column is one entry in `column_groups`. The engine computes each expression once per column group.

---

## Standard Reports — What Engine Each Uses

### Balance Sheet

> [`enterprise/account_reports/data/balance_sheet.xml`](../enterprise/account_reports/data/balance_sheet.xml)

- **Engine:** `domain` for leaf lines, `aggregation` for totals
- **date_scope:** `from_beginning` on leaf lines — assets/liabilities carry their entire history
- **Default date filter:** `today` (point-in-time snapshot, not a range)
- `filter_date_range = False` — only one date, not a range
- Layout: horizontal split (Assets left, Liabilities+Equity right)

```
ASSETS (aggregation: CA + FA + PNCA)
  ├── Current Assets (aggregation: BA + REC + CAS + PRE)
  │     ├── Bank and Cash Accounts → domain: account_type = asset_cash
  │     ├── Receivables → domain: account_type = asset_receivable AND non_trade = False
  │     ├── Current Assets → domain: asset_current OR (asset_receivable AND non_trade = True)
  │     └── Prepayments → domain: account_type = asset_prepayments
  ├── Plus Fixed Assets → domain: account_type = asset_fixed
  └── Plus Non-current Assets → domain: account_type = asset_non_current

LIABILITIES (aggregation: CL + NL)
  ├── Current Liabilities (aggregation: CL1 + CL2)
  └── Non-current Liabilities
EQUITY ...
```

### Profit and Loss (P&L)

> [`enterprise/account_reports/data/profit_and_loss.xml`](../enterprise/account_reports/data/profit_and_loss.xml)

- **Engine:** `domain` for leaf lines, `aggregation` for subtotals
- **date_scope:** `strict_range` — only the selected period
- **Default date filter:** `this_year`
- `filter_date_range = True`
- `filter_budgets = True` — budget comparison available

Key subformula detail: Revenue uses `-sum` because income accounts have **negative balance** by convention (credit-normal). Negating gives the positive revenue number.

```
Revenue → domain: account_type = income, subformula: -sum
Less Costs of Revenue → domain: account_type = expense_direct_cost, subformula: sum
Gross Profit → aggregation: REV.balance - COS.balance
  Operating Expenses → domain: account_type = expense, subformula: sum
Operating Income → aggregation: GRP.balance - OP.balance
  Other Income → domain: account_type = income_other, subformula: -sum
  Other Expenses → domain: account_type = expense_other, subformula: sum
Net Profit → aggregation: OI.balance + OTI.balance - OTE.balance
```

### Trial Balance

> [`enterprise/account_reports/data/trial_balance.xml`](../enterprise/account_reports/data/trial_balance.xml)
> Engine: [`account_trial_balance_report.py`](../enterprise/account_reports/models/account_trial_balance_report.py)

**Purpose:** Verify mathematical integrity of the ledger. One row per account. No individual transactions.

**What it shows:**

| Column | What it contains | Date scope |
|---|---|---|
| Initial Balance | Net balance of all lines **before** the period start | `to_beginning_of_period` — from beginning of time to day before `date_from` |
| Debit / Credit | All debits and credits **within** the period | `strict_range` — only `date_from` to `date_to` |
| End Balance | Initial Balance + period debit − period credit | Computed in postprocessor, no separate SQL |

**Key behavior for income/expense accounts:**

Balance sheet accounts (`include_initial_balance = True`) include all history in Initial Balance.
P&L accounts (`include_initial_balance = False`) only include lines **from fiscal year start** onward — they reset each year.

This is enforced by extra domain in `_report_custom_engine_trial_balance()`:

```python
extra_domain = [
    '|',
    ('account_id.include_initial_balance', '=', True),
    ('date', '>=', fiscalyear_start),
]
```

Source: [`account_trial_balance_report.py:231`](../enterprise/account_reports/models/account_trial_balance_report.py#L231)

**Undistributed Profits/Losses row:**

The Trial Balance inserts a special row for `equity_unaffected` that represents the net of all P&L lines not yet closed. This is computed separately in `_custom_line_postprocessor()` and injected into the total.
Source: [`account_trial_balance_report.py:333`](../enterprise/account_reports/models/account_trial_balance_report.py#L333)

**Drill-down from Trial Balance → General Ledger:**

Each account row has a caret menu: "General Ledger" opens the GL filtered to that account.
Source: [`_caret_options_initializer()`](../enterprise/account_reports/models/account_trial_balance_report.py#L188)

**`filter_hierarchy = by_default`:** Account groups shown by default — accounts roll up into groups.

---

### General Ledger

> [`enterprise/account_reports/data/general_ledger.xml`](../enterprise/account_reports/data/general_ledger.xml)
> Engine: [`account_general_ledger.py`](../enterprise/account_reports/models/account_general_ledger.py)

**Purpose:** Full transaction history for every account. Every posted journal line is shown individually with a running balance.

**What it shows:**

| Column | Content |
|---|---|
| Date | Journal entry date |
| Partner | Partner on the line (if any) |
| Currency | Foreign currency (if enabled) |
| Debit | Debit amount |
| Credit | Credit amount |
| Balance | **Running balance** = previous balance + debit − credit |

**Groups by:** `account_id` → `id_with_accumulated_balance`

- Top level: one row per account (folded by default)
- Expand account: every `account.move.line` for that account in date order
- Each individual line shows the cumulative balance up to that point

**How the running balance works:**

The engine uses `progress` (a dict passed between line batches) to carry the accumulated balance forward:

```python
accumulated_balance_by_colgroup[col_group_key] += line_balance
```

Source: [`account_general_ledger.py:316`](../enterprise/account_reports/models/account_general_ledger.py#L316)

`load_more_limit = 80` — pagination. If an account has >80 lines, a "Load More" button appears.

**Opening balance line:**

The first row under each account is an "Initial Balance" computed with `to_beginning_of_period` date scope. This is the balance before `date_from`. All subsequent lines count from there.

**Difference from Trial Balance at a glance:**

| | Trial Balance | General Ledger |
|---|---|---|
| Granularity | One row per account | One row per journal line |
| Shows transactions? | No — only totals | Yes — every individual line |
| Balance column | Initial/End balance | Running (cumulative) balance |
| Use case | Verify totals, period-end close | Investigate what happened to an account |
| Performance | Fast — aggregate SQL | Slow on large datasets — paginated |

---

### Aged Receivable / Aged Payable

> [`enterprise/account_reports/data/aged_partner_balance.xml`](../enterprise/account_reports/data/aged_partner_balance.xml)
> Engine: [`account_aged_partner_balance.py`](../enterprise/account_reports/models/account_aged_partner_balance.py)

**Purpose:** Show which customer invoices (AR) or vendor bills (AP) are still outstanding, and how long they have been overdue. Used for collections and cash flow planning.

**What makes it different from other reports:**

It only shows **open items** — lines that are partially or fully unreconciled. Fully paid invoices do not appear.

**How "open" is determined:**

The SQL uses a `LEFT JOIN LATERAL` on `account_partial_reconcile` to subtract already-matched amounts:

```sql
balance - COALESCE(part_debit.amount, 0) + COALESCE(part_credit.amount, 0)
```

The HAVING clause removes lines where the residual rounds to zero:

```sql
HAVING
    ROUND(SUM(residual_debit), precision) != 0
    OR ROUND(SUM(residual_credit), precision) != 0
```

Source: [`account_aged_partner_balance.py:155`](../enterprise/account_reports/models/account_aged_partner_balance.py#L155)

**Important:** Partial reconciliations are only counted if `part.max_date <= date_to`. This means the report is historically accurate — you can set `date_to` to any past date and see aging as it was on that day.

**The aging buckets:**

Default: 6 buckets, 30-day interval, based on `date_maturity`.

| Column label | What it contains |
|---|---|
| `period0` | Not yet due — `date_maturity >= date_to` |
| `period1` | 1–30 days overdue |
| `period2` | 31–60 days overdue |
| `period3` | 61–90 days overdue |
| `period4` | 91–120 days overdue |
| `period5` | 121+ days overdue ("Older") |

The interval is user-configurable (`aging_interval` option, default 30). Column labels update dynamically.
Source: [`account_aged_partner_balance.py:45`](../enterprise/account_reports/models/account_aged_partner_balance.py#L45)

**Aging date options:**

| `aging_based_on` | What date is used for bucket assignment |
|---|---|
| `base_on_maturity_date` (default) | `date_maturity` — the payment due date |
| `base_on_invoice_date` | `invoice_date` — the original invoice date |

Use `base_on_invoice_date` when you care about how old the document is, not when it was due.

**Structure in UI:**

```
Partner A                 0–30   31–60   61–90   91–120   Older   Total
  └── INV/2025/0001             1,500                             1,500
  └── INV/2025/0002                             800               800
Partner B                ...
```

- Top level rows: one per partner (foldable)
- Expand partner: one row per open `account.move.line`
- Each line shows its amount in exactly one bucket; all other buckets are 0

**Trust indicator:**

Each partner row gets the `trust` field added (`good`/`normal`/`bad`) from `res.partner`.
Shown as a colored dot in the UI to flag risky customers.
Source: [`_custom_line_postprocessor()`](../enterprise/account_reports/models/account_aged_partner_balance.py#L65)

**Aged Receivable vs Aged Payable — the only difference:**

| | Aged Receivable | Aged Payable |
|---|---|---|
| Account type filter | `asset_receivable` | `liability_payable` |
| Sign multiplicator | `+1` (debit-normal) | `−1` (credit-normal, negated to show positive) |
| Handler | `account.aged.receivable.report.handler` | `account.aged.payable.report.handler` |
| Audit journal filter | Excludes `purchase` journals | Excludes `sale` journals |

Both inherit from the same base handler `AccountAgedPartnerBalanceReportHandler` and call the same `_aged_partner_report_custom_engine_common()`.
Source: [`account_aged_partner_balance.py:83`](../enterprise/account_reports/models/account_aged_partner_balance.py#L83)

### Tax Report (Generic)

> [`enterprise/account_reports/data/generic_tax_report.xml`](../enterprise/account_reports/data/generic_tax_report.xml)

- **Engine:** `tax_tags` for country-specific localized tax reports
- Root report: `account.generic_tax_report`
- Each country's `l10n_*` module creates a **variant** pointing to this root report
- Variant's lines use `tax_tags` engine with country-specific tag names

The generic tax report you see in Settings (before a localization is installed) shows all taxes by type.
After installing `l10n_xx`, a localized variant appears with the actual tax return boxes.

### Partner Ledger

> [`enterprise/account_reports/data/partner_ledger.xml`](../enterprise/account_reports/data/partner_ledger.xml)

- Similar to General Ledger but grouped by partner
- Shows receivable/payable lines per partner
- Supports `filter_account_type` to switch between customers/vendors

---

## Report Variants and Localization

The `root_report_id` field connects generic reports to localized versions.

```
account.report (root)
    name = "Generic Tax Report"
    root_report_id = None
    country_id = None

account.report (variant — France)
    name = "Déclaration TVA CA3"
    root_report_id → "Generic Tax Report"
    country_id = France
    availability_condition = 'country'
```

When a French company opens the Tax Report, Odoo automatically redirects to the French variant.
The redirect happens in `get_options()`:
Source: [`account_report.py:2078`](../enterprise/account_reports/models/account_report.py#L2078)

---

## Composite Reports (Sections)

A composite report contains multiple sub-reports as sections, all accessible from one menu.

```
Annual Statements (composite)
    section_report_ids:
        → Balance Sheet
        → Profit and Loss
        → Trial Balance
```

Created automatically for localized reports that set `use_sections = True`.
Source: [`account_report.py:157`](../enterprise/account_reports/models/account_report.py#L157)

---

## Groupby: Expanding Lines to Sublines

When `account.report.line.groupby` is set, the engine splits results by the given field(s).

**How it works:**

1. Engine receives `current_groupby = 'account_id'`
2. SQL adds `GROUP BY account_move_line.account_id`
3. Returns a list of `(grouping_key, {result_dict})` instead of a single dict
4. Each grouping key becomes a new UI row (child line)

**Multi-level groupby:** `groupby = 'partner_id, account_id'`
First render: grouped by `partner_id` (collapsed). Expanding a partner loads `account_id` level.

**Foldable lines:** If `foldable = True`, the initial render shows the line collapsed.
The user clicks to expand, triggering a new API call with `current_groupby` set.

---

## Hierarchy Filter (Account Groups)

When `filter_hierarchy = 'by_default'` or `'optional'` and the user enables it:
- Account-level lines are re-aggregated into their `account.group` structure
- Uses `account.group.code_prefix_start/end` ranges to group accounts
- Each group row shows the sum of accounts within its range

---

## Audit Drill-Down

`auditable = True` on an expression means clicking the cell value opens a list of the underlying `account.move.line` records.

The system collects `account_ids` (for `account_codes` engine) or uses the domain (for `domain` engine) to build a filtered list view of journal items.

All standard engines are auditable. `aggregation` and `external` are auditable too (they trace back to their source lines).

---

## Currency Handling in Reports

Reports convert all balances to the **company currency** using a currency rate table.

`_init_options_currency_table()` builds a JOIN that applies the exchange rate at the time of the transaction (or the report date for balance sheet items).
Source: [`account_report.py:1389`](../enterprise/account_reports/models/account_report.py#L1389)

The `balance_select` in SQL is:
```sql
account_move_line.balance * currency_table.rate
```

---

## Export

Reports can export to:
- **PDF** — rendered via QWeb/Chromium headless
- **XLSX** — via xlsxwriter
- **Various EDI formats** — tax returns can be exported as XML (XBRL, SAFT, etc.) via `account.return.type`

Export buttons appear based on `filter_*` settings and the `buttons` list in options.

---

## UI Entry Points

| Entry Point | Path in UI | What It Does |
|---|---|---|
| Balance Sheet | Accounting → Reporting → Balance Sheet | Point-in-time assets/liabilities snapshot |
| Profit and Loss | Accounting → Reporting → Profit and Loss | Revenue and expense for a period |
| Trial Balance | Accounting → Reporting → Trial Balance | Debit/credit totals per account with opening balance |
| General Ledger | Accounting → Reporting → General Ledger | Every journal line with running balance |
| Partner Ledger | Accounting → Reporting → Partner Ledger | Receivable/payable lines grouped by partner |
| Aged Receivable | Accounting → Reporting → Aged Receivable | Overdue customer invoices in age buckets |
| Aged Payable | Accounting → Reporting → Aged Payable | Overdue vendor bills in age buckets |
| Tax Report | Accounting → Reporting → Tax Report | Tax return boxes (localized or generic) |
| Cash Flow | Accounting → Reporting → Cash Flow Statement | Operating/investing/financing cash flows |
| Executive Summary | Accounting → Reporting → Executive Summary | KPI overview with key ratios |
| Custom Reports | Accounting → Reporting → (any custom) | Reports created manually via Accounting → Configuration → Financial Reports |

---

## Edge Cases & Gotchas

- **`-sum` on income:** Income accounts have credit-normal balances (negative numbers). `subformula = '-sum'` negates them so they display as positive revenue. Never use `sum` on income — the number will show negative. Source: [`profit_and_loss.xml:32`](../enterprise/account_reports/data/profit_and_loss.xml#L32)

- **Balance Sheet uses `from_beginning`:** The `date_scope` on Balance Sheet leaf expressions is NOT `strict_range`. It reads the entire history. Changing it to `strict_range` would make assets show only the period's movement, not the cumulative balance.

- **Aggregation runs last:** An `aggregation` expression cannot reference a line whose expression hasn't been computed yet. The framework computes all non-aggregation lines first, then evaluates aggregation expressions. Circular references raise a computation error.

- **`account.root` search panel:** The COA list view left panel uses `account.root` (virtual model, no DB table). The report's left panel uses `filter_hierarchy` with `account.group`. These are different grouping mechanisms.

- **Variant reroute:** If a report has a variant matching the current company's country, `get_options()` silently redirects to the variant. The UI shows the variant, not the root. Source: [`account_report.py:2078`](../enterprise/account_reports/models/account_report.py#L2078)

- **`equity_unaffected` on Balance Sheet:** The standard Balance Sheet does NOT have a `domain` line for `equity_unaffected`. Instead, Odoo computes "Undistributed Profits/Losses" as a residual (Assets − Liabilities − explicit Equity). This is handled by `AccountBalanceSheetReportHandler`. If your `equity_unaffected` account has the wrong type, the balance sheet won't balance.

- **`custom` engine = custom handler required:** If `engine = 'custom'`, the report MUST have `custom_handler_model_id` set. Without it, calling the report raises `AttributeError` — the framework tries `getattr(self, formula_name)` which doesn't exist on the base model.

- **`count_rows` can't be batched:** The `count_rows` subformula on the `domain` engine is always non-batchable and runs a separate SQL query per formula. Don't use it on reports with many lines — it will be slow.

---

## Related Docs

- [`INDEX.md`](INDEX.md)
- [`accounting_coa.md`](accounting_coa.md) — account types determine which domain expressions match

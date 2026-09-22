# account.analytic.account — Analytic Account Model

## Overview

An analytic account is a **cost/revenue container that sits outside the general ledger**, allowing users to track financial activity by dimensions other than accounts. Common uses:

- **Project**: accumulate costs/revenues by project code
- **Department**: track spending by cost center or organizational unit
- **Vehicle/Equipment**: accumulate fuel, maintenance, depreciation
- **Job/Task**: group time/materials/expenses to a work order
- **Customer/Contract**: slice revenue or costs by customer or contract

The model is **decoupled from the GL** — a single `account.move.line` can reference one or more analytic accounts via [account.analytic.line](../addons/analytic/models/analytic_line.py) without changing the posting account. Balances (`debit`/`credit`/`balance`) aggregate all lines tied to that account, optionally filtered by date range and company.

---

## Core Fields

### Identity & Organization

| Field | Type | Details | Citation |
|---|---|---|---|
| `name` | Char | Required, user-visible label. Indexed trigram for fuzzy search. Tracked for changes. Translatable. | [analytic_account.py:20-26](../addons/analytic/models/analytic_account.py#L20) |
| `code` | Char | Optional reference code — often a project/cost-center code (e.g., "CC-2024-001"). BTree indexed for fast lookup. Tracked. Part of display name via `_compute_display_name`. | [analytic_account.py:27-31](../addons/analytic/models/analytic_account.py#L27) |
| `active` | Boolean | Soft-delete flag. Default `True`. Deactivated accounts remain queryable but hidden from dropdowns. Tracked. | [analytic_account.py:32-37](../addons/analytic/models/analytic_account.py#L32) |

### Plan & Hierarchy

| Field | Type | Details | Citation |
|---|---|---|---|
| `plan_id` | Many2one → `account.analytic.plan` | **Required**. Each account belongs to exactly one plan (e.g., "Projects", "Cost Centers", "Vehicles"). The plan defines which documents can reference this account; see [plan._column_name()](../addons/analytic/models/analytic_plan.py) for the dynamic column name (e.g., `project_id`, `department_id`). Indexed. | [analytic_account.py:38-43](../addons/analytic/models/analytic_account.py#L38) |
| `root_plan_id` | Many2one → `account.analytic.plan` | Derived. The root parent of `plan_id` (via [plan.root_id](../addons/analytic/models/analytic_plan.py#L39)). Plans are hierarchical; this field stores the top-level plan for quick filtering. Computed and stored. | [analytic_account.py:44-49](../addons/analytic/models/analytic_account.py#L44) |

### Company & Partner

| Field | Type | Details | Citation |
|---|---|---|---|
| `company_id` | Many2one → `res.company` | Defaults to the current user's company. Multi-company support is enforced: a constraint blocks changing the company of an account that already has analytic lines (to prevent orphaning data). See [_check_company_consistency](../addons/analytic/models/analytic_account.py#L95). | [analytic_account.py:61-65](../addons/analytic/models/analytic_account.py#L61) |
| `partner_id` | Many2one → `res.partner` | Optional. Often used to link an account to a customer, vendor, or project stakeholder. Indexed BTree (non-null). Tracked. Uses `bypass_search_access=True` for performance. | [analytic_account.py:67-75](../addons/analytic/models/analytic_account.py#L67) |

---

## Balance Computation

### Balance Fields (Computed)

| Field | Type | Computed By | Details | Citation |
|---|---|---|---|---|
| `debit` | Monetary | `_compute_debit_credit_balance` | Sum of positive amounts from all `account.analytic.line` records linked to this account. Currency-converted to company currency at today's rate. | [analytic_account.py:81-84](../addons/analytic/models/analytic_account.py#L81) |
| `credit` | Monetary | `_compute_debit_credit_balance` | Sum of negative amounts (made positive) from all linked lines. Currency-converted. | [analytic_account.py:85-88](../addons/analytic/models/analytic_account.py#L85) |
| `balance` | Monetary | `_compute_debit_credit_balance` | `credit - debit`. The net accumulated flow through the account. | [analytic_account.py:77-80](../addons/analytic/models/analytic_account.py#L77) |
| `currency_id` | Many2one → `res.currency` | Related field | Derived from `company_id.currency_id` — the reporting currency for balance display. | [analytic_account.py:90-93](../addons/analytic/models/analytic_account.py#L90) |

### How Balance Is Computed: `_compute_debit_credit_balance`

The computation aggregates **all** `account.analytic.line` records matching the account, applying optional **date filtering** and **multi-currency conversion**.

**Flow** [analytic_account.py:162-203](../addons/analytic/models/analytic_account.py#L162):

1. **Build domain**:
   - Include lines from this account's company AND parent companies (via `company_id in [False] + self.env.companies.ids`).
   - If `from_date` in context → filter `date >= from_date`.
   - If `to_date` in context → filter `date <= to_date`.

2. **Group by plan and currency**:
   - For each plan (accounts grouped by `plan_id`), separate queries for:
     - **Debit**: `_read_group` with `amount < 0.0` (negative).
     - **Credit**: `_read_group` with `amount >= 0.0` (positive).
   - Group by the **plan's column** (e.g., `project_id`) and `currency_id` to aggregate amounts per currency.

3. **Convert all to company currency**:
   - For each currency, use [`_convert(from_amount, to_currency=company_currency, date=today())`](../addons/analytic/models/analytic_account.py#L164).
   - Accumulate into `data_debit` / `data_credit` dicts keyed by account ID.

4. **Assign per account**:
   ```
   debit = -data_debit[account.id]  # negate to make debit positive
   credit = data_credit[account.id]
   balance = credit - debit
   ```

**Example**: An account with lines in EUR (100) and USD (50 = 45 EUR at today's rate):
- `credit = 100 + 45 = 145 EUR`
- `debit = 0`
- `balance = 145 EUR`

---

## Display & Search

### `_compute_display_name` (Name-Get)

[analytic_account.py:104-112](../addons/analytic/models/analytic_account.py#L104)

The displayed name includes optional code and partner (commercial partner, if set):

```
[CODE] Name - Partner Name
```

Example: `[CC-2024-001] IT Department - ACME Inc.`

### Multi-Field Search

The model defines [`_rec_names_search = ['name', 'code']`](../addons/analytic/models/analytic_account.py#L18), enabling search on both name and code. The code field has a BTree index for fast lookups by code alone.

---

## Multi-Company Behavior

### Consistency Check: `_check_company_consistency`

[analytic_account.py:95-102](../addons/analytic/models/analytic_account.py#L95)

When attempting to **change the company** of an account, Odoo checks if any linked analytic lines belong to a **different company** (not a child of the new company). If found, the change is **rejected** with an error message. This prevents orphaning data in a multi-company tree.

**Why?** Analytic lines are company-specific; moving an account to a different company (without reassigning its lines) breaks the company hierarchy assumption.

---

## Line Linking & Plan Migration

### One2many Relationship

[analytic_account.py:55-59](../addons/analytic/models/analytic_account.py#L55)

```python
line_ids = fields.One2many(
    'account.analytic.line',
    'auto_account_id',  # magic link
    string="Analytic Lines",
)
```

The `auto_account_id` is a **computed field** in `account.analytic.line` that provides a **context-aware** link to the "current" plan's account column. This allows a single one2many view to work with different plan columns (project, department, etc.) depending on which plan is active in the context.

### Plan Migration: `_update_accounts_in_analytic_lines`

[analytic_account.py:205-235](../addons/analytic/models/analytic_account.py#L205)

When an account is **moved to a different plan** (via `write({'plan_id': new_plan_id})`), the method:

1. **Checks for blocking lines**: If the new plan's column already has a value in any line (and the old plan column is set), raise a `RedirectWarning` showing the conflicting lines.

2. **Migrates lines** (if no conflict):
   ```sql
   UPDATE account_analytic_line
      SET new_fname = old_fname,
          old_fname = NULL
    WHERE old_fname IN (account_ids)
   ```
   Moves the account reference from the old plan column to the new plan column.

3. **Invalidates cache**: Notifies Odoo to refresh the line cache.

**Why?** Analytic lines are stored with separate columns per plan (e.g., `project_id`, `department_id`). Moving an account to a different plan requires migrating the column reference atomically.

---

## Read Group & Aggregation

### Custom Aggregation: `_read_group_select` / `_read_group_postprocess_aggregate`

[analytic_account.py:128-160](../addons/analytic/models/analytic_account.py#L128)

When a list view tries to **group and aggregate** `balance`, `debit`, or `credit` (e.g., sum by plan), Odoo can't aggregate computed fields directly from the database. Instead:

1. `_read_group_select` intercepts the aggregation request and returns the **full record set** (`id:recordset`).

2. `_read_group_postprocess_aggregate` computes the field on the Python side and sums the results per group.

3. **Multi-currency handling**: If aggregating `balance:sum_currency`, convert each record's balance to company currency before summing (respecting each record's own currency).

This ensures that grouping analytic accounts by plan, cost center, etc., always shows correct rolled-up balances even when lines use different currencies.

---

## Data Lifecycle

### Copying

[analytic_account.py:114-120](../addons/analytic/models/analytic_account.py#L114)

When duplicating an account, the name is automatically appended with " (copy)". Analytic lines are **not** copied (one2many fields are not copied by default), so the duplicate starts with a zero balance.

### Web Read Context

[analytic_account.py:122-126](../addons/analytic/models/analytic_account.py#L122)

When reading a **single** analytic account via the web API, the `analytic_plan_id` context is set to the account's plan ID. This ensures that the one2many `line_ids` and `auto_account_id` compute correctly in views.

---

## Integration Points

### Who References Analytic Accounts?

- **[account.analytic.line](../addons/analytic/models/analytic_line.py)**: Every cost/revenue line; linked via the plan's dynamic column.
- **[account.analytic.plan](../addons/analytic/models/analytic_plan.py)**: Parent hierarchy; each account has one plan.
- **[account.move.line](../addons/account/models/move.py)** (via mixin): Sales orders, purchase orders, invoices, etc., set analytic distribution on move lines; the distribution maps to one or more analytic accounts.
- **[analytic_budget](../addons/analytic_budget/models/analytic_budget.py)**: Budgets compare planned amounts vs. actual achieved balances from analytic accounts.

### Analytic Distribution (JSON)

In modern Odoo, analytic assignment is flexible — a move line can reference **multiple analytic accounts** with a percentage split via an `analytic_distribution` JSON field. The `account.analytic.line` cron then creates child lines to distribute the move line's amount across the accounts. See [account.analytic.line](../addons/analytic/models/analytic_line.py) for details.

---

## Edge Cases & Gotchas

### 1. Context-Dependent `auto_account_id`

The one2many `line_ids` uses a **magic computed field** `auto_account_id` that depends on context. If you access `line_ids` without setting `analytic_plan_id` in the context, the relation may not work correctly. Always use `with_context(analytic_plan_id=self.plan_id.id)` when loading lines in custom code.

### 2. Date-Filtered Balance

The `debit`/`credit`/`balance` fields respect `from_date` and `to_date` in context. A view that forgets to pass these will show **total** balance (all time), not the period balance. This is useful but easy to miss in custom reports.

### 3. Company-Only Migration, Not Multi-Company Reparenting

Changing `company_id` is rejected if lines exist; there is **no automatic migration** of lines to a parent/child company. If you need to move lines to a different company, write them explicitly first, then change the account's company.

### 4. Plan is Immutable in Most Flows

Once an account is created, its `plan_id` is rarely changed (the migration is expensive). In practice, accounts are deactivated rather than reparented to a different plan.

### 5. Code-Based Search Performance

The `code` field is indexed with BTree. If you're searching analytic accounts by code (e.g., project ID from an external system), use `name_search()` or `_name_search()` with the code — it will hit the index.

### 6. Display Name Includes Partner

The display name shows the **commercial partner**, not the partner itself. If `partner_id` is a contact, the display will show the contact's parent company. This can be confusing if you expect the contact name.

---

## Usage Pattern

### Typical Workflow

1. **Create a plan** (e.g., "Projects") via the UI.
2. **Create accounts** under the plan (e.g., project "Customer ABC - Q3 2024").
3. **Link the account** in documents:
   - Sales order → project account (accumulates sales cost).
   - Invoice line → project account (accumulates revenue).
   - Expense → project account (accumulates costs).
4. **View the account** → see debit/credit/balance aggregated from all linked analytic lines.
5. **Filter by date** (context) → see period-specific balance (e.g., "Q3 only").
6. **Create a budget** → compare planned amount vs. achieved balance from the account.

### Programmatic Access

```python
# Get an account
account = self.env['account.analytic.account'].search([('code', '=', 'CC-2024-001')], limit=1)

# Check its balance for a specific period
account_period = account.with_context(
    from_date='2024-01-01',
    to_date='2024-03-31'
)
print(f"Q1 2024 balance: {account_period.balance}")

# Get all lines
lines = account.line_ids
for line in lines:
    print(f"{line.date}: {line.amount}")

# Create a line manually (rare)
self.env['account.analytic.line'].create({
    'account_id': account.id,
    'date': date.today(),
    'amount': 100.0,
    'name': 'Manual entry',
    'company_id': account.company_id.id,
})
```

---

## Performance Notes

- **Balance computation** is **not cached** — every access recalculates via `_read_group` on `account.analytic.line`. For high-volume use (1000s of accounts with 100k+ lines), filter by date or plan to reduce the query scope.
- **Plan migration** runs raw SQL (`UPDATE account_analytic_line`) but is rare; only use when consolidating accounts or restructuring the plan.
- **Trigram index on `name`** ensures fuzzy search is fast. BTree on `code` ensures exact-code lookup is instant.

---

## Related Models

- **[account.analytic.line](../addons/analytic/models/analytic_line.py)**: The actual transaction records; balances roll up from here.
- **[account.analytic.plan](../addons/analytic/models/analytic_plan.py)**: Parent plan; defines hierarchy and column naming.
- **[account.analytic.applicability](../addons/analytic/models/analytic_applicability.py)**: Marks which plans apply to which document types (Invoices, Sales Orders, Expenses, etc.).
- **[analytic.budget](../addons/analytic_budget/models/analytic_budget.py)**: Budget records; compare `planned_amount` vs. account's `balance`.


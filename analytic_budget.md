# Analytic Budget — Odoo 20

> Reviewed against this checkout on 2026-09-22. [`odoo/release.py`](../odoo/release.py) identifies it as 20.0; this document describes the local source, including Enterprise modules, rather than assuming the inherited Odoo 19 behavior.
> **Modules:** [`account_budget`](../enterprise/account_budget/), [`account_budget_purchase`](../enterprise/account_budget_purchase/), [`project_account_budget`](../enterprise/project_account_budget/).

## What It Does

An analytic budget compares planned amounts with analytic entries over a date range. Each budget line can constrain one or several analytic dimensions. Actuals come from `account.analytic.line`, including journal-linked entries, timesheets and manual entries. They are not limited to invoices.

The base Enterprise module depends on `accountant`. Purchase commitment tracking requires `account_budget_purchase`; project integration requires `project_account_budget`. Timesheet costs come from `hr_timesheet`.

## Models and Amounts

Sources: [`budget_analytic.py`](../enterprise/account_budget/models/budget_analytic.py), [`budget_line.py`](../enterprise/account_budget/models/budget_line.py), [`purchase budget_line.py`](../enterprise/account_budget_purchase/models/budget_line.py).

| Model / field | Meaning in this checkout |
|---|---|
| `budget.analytic` | Header: name, responsible user, company, dates, type, state and revision links |
| `budget_type` | `expense` (default), `revenue`, or `both` |
| `budget.line` | Analytic plan columns and amounts; dates and company are stored related fields from the header |
| `budget_amount` | Planned amount, labeled **Commitment** |
| `liquidation_amount` | **Liquidation**; stored, editable computed amount, initially equal to commitment and recomputed when commitment changes |
| `achieved_amount` | Sum of matching report actuals |
| `achieved_percentage` | Achieved / **liquidation**, or zero when liquidation is zero |
| `theoritical_amount` / `theoritical_percentage` | Date-based planned progress; these are the actual, misspelled field names |
| `is_above_budget` | Simple `achieved_amount > budget_amount` comparison, without budget-type adjustment |
| `committed_amount` | Purchase integration only: achieved plus outstanding purchase commitments |
| `committed_percentage` | Committed / commitment (`budget_amount`), or zero for a zero denominator |

**Commitment** (`budget_amount`, a plan) and **Committed** (`committed_amount`, actuals plus outstanding purchases) are distinct. Liquidation is another planned amount; it is not computed from payments.

## Business Flow and States

1. Create a budget with a period and budget type.
2. Add lines with analytic accounts, commitment and liquidation amounts.
3. Open the budget (`confirmed`).
4. Matching analytic entries contribute to achieved amounts; qualifying purchase orders also contribute to committed amounts when the purchase extension is installed.
5. Inspect the report or project budget panel.

The states are `draft`, `confirmed` (UI label **Open**), `revised`, `done`, and `canceled`. In the standard form, Open and Cancel Budget are available in draft, Done in confirmed, and Reset to Draft outside draft. These button conditions are not a strict server-side transition matrix: the action methods mostly assign the state directly.

Creating a revision copies the budget into a new draft and sets `parent_id`; it does **not** immediately mark the parent revised. Confirming the child marks a confirmed parent revised. Confirming a budget that already has children sets that budget to revised. Deletion is restricted to draft/canceled budgets. See [`budget_analytic.py`](../enterprise/account_budget/models/budget_analytic.py) and [`budget_analytic_views.xml`](../enterprise/account_budget/views/budget_analytic_views.xml).

Budget actual calculations do not inherently exclude draft, revised or canceled budgets. The project panel and project aggregate fields explicitly select confirmed/done budgets.

## How Report Matching Works

[`budget.report`](../enterprise/account_budget/reports/budget_report.py) is an `_auto = False` model with a dynamic `_table_sql` query, not a stored total or a materialized PostgreSQL view. It combines planned budget rows and analytic actual rows; the purchase extension adds commitment rows.

For an analytic entry to contribute to a particular budget line:

- Its date must be inside the header's inclusive date range.
- Its company must equal the budget company, unless the budget company is empty.
- Every populated plan column on the budget line must match the entry. Empty plan columns impose no restriction.
- Its financial account must pass the report's eligibility domain.
- Its `analytic_profitability` must match the budget type as described below.

The query groups budget lines by which plan columns are populated and builds joins for those shapes. It separately handles company-specific and company-empty budgets. A single analytic entry can match multiple overlapping budget lines, so adding overlapping budgets together can count the same entry more than once. Unfiltered reports also have a branch for entries without a matching budget line. See [`_shape_join()`](../enterprise/account_budget/models/analytic_plan_fields_mixin.py).

## Odoo 20 Eligibility and Profitability

The report first accepts lines with **no financial account**, accounts with `internal_group` income/expense, and the explicit asset types **`asset_current`, `asset_non_current`, `asset_fixed`**. Cash, receivable, liability and equity accounts are not accepted by that domain.

It then selects expense-budget entries where `analytic_profitability = 'loss'`, revenue-budget entries where it is `'revenue'`, and all eligible entries for `both`. Classification is defined in [`account_analytic_line.py`](../addons/account/models/account_analytic_line.py), with both Python and SQL implementations.

| Analytic entry | Profitability | Expense budget | Revenue budget | Both budget |
|---|---|---|---|---|
| Expense financial account (`expense`, `expense_*`) | loss | Included | Excluded | Included |
| Income financial account (`income`, `income_*`) | revenue | Excluded | Included | Included |
| `asset_current`, `asset_non_current`, `asset_fixed` | loss | Included | Excluded | Included |
| No financial account, category `other`, negative amount | loss | Included | Excluded | Included |
| No financial account, category `other`, positive amount | revenue | Excluded | Included | Included |
| No financial account, category other than `invoice`/`other` | loss | Included | Excluded | Included |
| No financial account, category `invoice`; or `other` with zero amount | uncategorized | Excluded | Excluded | Included |
| Cash, receivable, liability or equity financial account | Excluded by report domain | Excluded | Excluded | Excluded |

Classification for expense, income and qualifying asset accounts follows the account type, even when the amount reverses sign. Budget report amounts use:

```python
achieved = analytic_line.amount * (-1 if budget_type == 'expense' else 1)
```

Therefore an expense debit creates a negative analytic amount and a positive expense-budget actual. An income credit creates a positive analytic amount and a positive revenue-budget actual. `both` keeps signed net amounts, including eligible asset movements; it is not necessarily an income-statement profit measure.

A vendor credit note on an expense account has a **negative GL balance**, hence a positive analytic amount and a negative expense-budget contribution. A customer credit note reduces revenue achieved. For `both`, vendor refunds increase the net amount and customer refunds decrease it.

## Transaction Scenarios

### Vendor bills and customer invoices

[`account.move._post()`](../addons/account/models/account_move.py) calls [`_create_analytic_lines()`](../addons/account/models/account_move_line.py). A distributed vendor-bill expense debit contributes positive expense achieved. A distributed customer-invoice income credit contributes positive revenue achieved. The analytic amount is `-balance × percentage / 100`, subject to currency rounding.

Draft journal entries do not generate these postings. Resetting a posted entry to draft deletes its analytic lines and removes their achieved contribution. Canceling a posted entry first calls `button_draft()`, so the same removal applies. Independent manual analytic lines and timesheets do not require posting a journal entry.

### Timesheets

[`hr_timesheet` postprocessing](../addons/hr_timesheet/models/account_analytic_line.py) computes `amount = -unit_amount * hourly_cost`, with currency conversion. With a positive hourly cost, **positive hours produce a negative cost** and count toward expense budgets. Negative hours produce a positive amount. For a no-financial-account line with category `other`, that positive correction is classified as revenue, so it contributes to revenue/`both`, rather than reducing an expense budget's actuals. Zero-cost timesheets have no monetary effect.

### Miscellaneous journal entries

The entry must be posted and the relevant line must have analytic distribution. A debit to an expense account or an eligible asset account can consume an expense budget; its balancing line contributes separately only if it also has distribution and passes the filters.

The previous example involving `asset_cash` and `asset_current` cannot be explained by saying all assets are excluded: **cash is excluded, current assets are included** in this source. Diagnosing an actual record still requires checking its distribution, posting state, date, company and plan matches.

### Asset purchase and depreciation

A bill for a $1,400 fixed asset with 100% distribution creates a -$1,400 analytic amount on `asset_fixed`. It can immediately contribute **+$1,400** to an expense budget.

The asset module's [`_prepare_move_for_asset_depreciation()`](../enterprise/account_asset/models/account_move.py) copies a nonempty asset-variant distribution onto both depreciation move lines. If a $100 depreciation credits a qualifying asset account and debits an expense account, with the same budget matches:

| Line | Analytic amount | Expense-budget achieved |
|---|---|---|
| Credit accumulated depreciation / eligible asset | +100 | -100 |
| Debit depreciation expense | -100 | +100 |
| Net contribution | 0 | 0 |

This depends on configured accounts, distributions and matching dates. The credit account is the variant's depreciation account, not necessarily the original asset account. The old claim that asset costs only reach the budget as depreciation posts does not match this Odoo 20 implementation.

### Manual analytic entries

Manual entries can contribute without a journal item. Use the profitability table above: account type, or category and monetary sign when no financial account exists, determines eligibility. Quantity alone does not determine budget behavior.

## Purchase Commitments

Sources: [`purchase budget report`](../enterprise/account_budget_purchase/reports/budget_report.py), [`purchase budget line`](../enterprise/account_budget_purchase/models/budget_line.py).

The extension includes purchase lines whose order state is `purchase`, whose order date is inside the budget period, whose company and analytic dimensions match, and whose ordered quantity exceeds the quantity billed on **posted** vendor bills net of posted refunds. Draft bills do not reduce the outstanding quantity. Bill quantities are converted to the purchase line's unit when needed.

The outstanding amount is approximately:

```text
(subtotal + non-deductible tax) / ordered quantity
    × (ordered quantity − posted net billed quantity)
    / order currency rate
    × analytic allocation rate
```

The implementation has fallbacks for missing subtotal and zero quantity. It expands `analytic_json` into plan columns and allocation rates. Outstanding purchases contribute positively to expense budgets and negatively to `both`; they are excluded from revenue budgets. Achieved rows also populate the committed column, so **committed = achieved + outstanding purchase commitments**. For revenue budgets, committed can still equal achieved even though purchases add nothing.

Example: a matching expense purchase of 1,000 with a posted matching bill of 400 normally yields achieved 400, outstanding commitment 600, total committed 1,000, assuming the same valuation, dates and allocations.

## Theoretical Amount and Percentage

The Python `budget.line` calculation uses inclusive days, clamps today between the start/end dates, and multiplies the elapsed fraction by `budget_amount`. This means **before the start date it already returns one day's allocation**. The report SQL's `theoretical` expression instead returns **zero before the start date**. Both reach the full planned amount at/after the end date. This source discrepancy matters when comparing the budget-line field with the report measure.

Theoretical percentage uses commitment as its denominator. Achieved percentage uses liquidation. Neither measures cash payments, and neither models uneven spending schedules. Sources: [`budget_line.py`](../enterprise/account_budget/models/budget_line.py), [`budget_report.py`](../enterprise/account_budget/reports/budget_report.py).

## Project Integration

Sources: [`project_project.py`](../enterprise/project_account_budget/models/project_project.py), [`project views`](../enterprise/project_account_budget/views/project_project_views.xml).

Projects select matching budget lines through their analytic account. Both `_compute_budget()` and `_get_budget_items()` restrict budgets to **confirmed/done**. The aggregate fields include `total_budget_amount`, `total_budget_achieved_amount`, `total_budget_progress`, `total_budget_achieved_progress`, and `budget_count`.

For an individual budget:

```python
progress = (spent - allocated) / abs(allocated) * type_factor if allocated else 0
# type_factor = -1 for expense, +1 for revenue/both
```

For a positive allocation of 500:

| Achieved | Expense progress | Revenue / both progress |
|---|---|---|
| 0 | 1.0 | -1.0 |
| 375 | 0.25 | -0.25 |
| 500 | 0 | 0 |
| 625 | -0.25 | 0.25 |

The kanban icon uses exact `-1.0` → muted, otherwise `>= 0.25` → green, `>= 0` → warning, and lower values → danger. The exact `-1.0` special case is numerical, not a reliable universal test for no spending. Mixed-budget totals sign-adjust both allocated and achieved amounts before computing progress; offsetting allocations can make that denominator zero and return zero progress. A zero target can still show achieved amounts, but its individual progress is zero.

The Add Budget flow uses `project_update` context. [`budget.line.default_get()`](../enterprise/project_account_budget/models/budget_line.py) fills the project's plan column. [`budget.analytic.create()`](../enterprise/project_account_budget/models/budget_analytic.py) auto-confirms when exactly one budget is created with that context. Detail actions require allowed-company access and the accounting-readonly or analytic group; adding requires `account.group_account_user`.

## UI and Operational Notes

- The budget menu is attached to Accounting's Transactions menu in [`budget_analytic_views.xml`](../enterprise/account_budget/views/budget_analytic_views.xml). It provides the budget form, Budget Report, Budget Lines and per-line Audit actions.
- Actuals are non-stored ORM computed fields backed by report queries. Normal ORM caching still applies; “live SQL” does not mean every field access bypasses cache.
- Budget matching uses all populated dimensions. A department-only budget can span many projects; a project-and-department budget requires both to match.
- The journal-entry Budgets smart link uses a plan-column join in [`account_move.py`](../enterprise/account_budget/models/account_move.py). That link alone does not prove the entry contributes to achieved: the report additionally applies date, company and eligibility filters.
- These are standard-source behaviors. Installed custom overrides and actual database configuration may change results.

## Related Docs

- [Analytic accounting](analytic_accounting.md)
- [Documentation index](INDEX.md)

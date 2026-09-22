# Analytic Accounting — Odoo 20

> Reviewed against this checkout on 2026-09-22. [`odoo/release.py`](../odoo/release.py) identifies it as 20.0. This document describes the local implementation, rather than assuming behavior from the original Odoo 19 checkout.
> **Core:** [`addons/analytic/`](../addons/analytic/). **General-ledger integration:** [`addons/account/`](../addons/account/).

## What It Does

Analytic accounting classifies costs and revenues by business dimension—project, department, cost center—independently of the general ledger (GL). One journal item can allocate its amount across multiple analytic accounts and dimensions. Analytic entries can also exist without a journal entry, notably timesheets and manually entered analytic items.

A **plan** defines a dimension; an **analytic account** is a value within that dimension. Each root plan has its own account column on models inheriting `analytic.plan.fields.mixin`, allowing one analytic line to carry a project and a department together.

Use this for project costs, departmental allocations and budget comparisons. Financial accounts still determine statutory bookkeeping and contribute to analytic profitability classification. Analytic accounts do not replace the chart of accounts or stock valuation records.

## Core Models

| Concept | Model / field | Purpose |
|---|---|---|
| Plan | `account.analytic.plan` | Dimension, hierarchy and applicability rules |
| Account | `account.analytic.account` | Value within a plan; computed debit, credit and balance |
| Source distribution | `analytic.mixin.analytic_distribution` | Stored percentage JSON on journal items and other consuming models |
| Analytic entry | `account.analytic.line` | Monetary amount, quantity, date, company and plan account columns |
| Distribution rule | `account.analytic.distribution.model` | Prefills distributions from matching business criteria |
| Applicability rule | `account.analytic.applicability` | Determines whether a plan is optional, mandatory or unavailable |

The core module depends on `base`, `mail` and `uom`; `account` supplies journal linkage, profitability classification and extra matching criteria. See [`__manifest__.py`](../addons/analytic/__manifest__.py).

## From Distribution to Analytic Entries

```text
Create plans and accounts
    → set or auto-fill a source line's analytic distribution
    → post the journal entry
    → account.move._post() calls line_ids._create_analytic_lines()
    → reporting reads account.analytic.line
```

For the standard journal-entry flow, draft distributions do not create analytic postings. Posting creates records with amounts based on **company-currency balance**, not the invoice's foreign-currency amount:

```python
amount = -balance * percentage / 100
```

Costs normally produce negative analytic amounts and revenues positive amounts. A distribution on a sale or purchase line is not itself a posted GL analytic entry: each integration controls propagation and any independent cost entries. Timesheets and manual analytic entries follow their own creation paths and do not wait for invoice posting.

Sources: [`account_move.py`, `_post()`](../addons/account/models/account_move.py), [`account_move_line.py`, `_create_analytic_lines()` and `_prepare_analytic_lines()`](../addons/account/models/account_move_line.py).

### Examples

| Scenario | Distribution | Result for a GL debit balance of 100 |
|---|---|---|
| One department | `{"12": 100}` | One analytic entry, amount -100 |
| Two projects in the same plan | `{"12": 60, "13": 40}` | Two entries, amounts -60 and -40 |
| Project and department together | `{"12,7": 100}` | One entry, amount -100, with both plan columns populated |

IDs in examples are placeholders. In the combined key, accounts 12 and 7 must represent different root plans. A comma-joined key is one multidimensional allocation. Separate keys are separate allocations, and validation totals percentages separately for each root plan.

The preparation code adjusts a slice when a plan's cumulative percentage reaches 100%. It skips amounts that are zero at company-currency precision, then `_round_analytic_distribution_line()` rounds the generated amounts and distributes the rounding error. It is inaccurate to describe all rounding as a residual placed only on the final line. Optional partial distributions are not automatically expanded to 100%.

## Plans and Dynamic Fields

[`analytic_plan.py`](../addons/analytic/models/analytic_plan.py) defines `_strict_column_name()`, `_column_name()` and `_sync_all_plan_column()`:

- The configured project plan uses `account_id`.
- Other root plans use `x_plan{id}_id`.
- Subplans share their root plan's account column. Non-stored related fields expose plan hierarchy levels for grouping; they do not add another independently entered dimension.
- Synchronization applies to descendants of `analytic.plan.fields.mixin`, not every model that merely stores a distribution JSON.

The project plan is resolved through `analytic.project_plan`, not a hardcoded database ID. It must exist and cannot be given a parent. Changing that parameter invokes validation and dynamic-field handling in [`ir_config_parameter.py`](../addons/analytic/models/ir_config_parameter.py); use the ORM rather than direct SQL.

The mixin's `auto_account_id` has distinct read, write and search behavior:

- Reading uses `context['analytic_plan_id']`; without a plan it computes false.
- Writing selects the column from the assigned account's plan.
- Supported positive searches OR together the root-plan columns.

Every analytic line must have at least one plan account. See [`analytic_line.py`, `AnalyticPlanFieldsMixin`](../addons/analytic/models/analytic_line.py).

## Distribution JSON and Editing

[`analytic.mixin`](../addons/analytic/models/analytic_mixin.py) supplies a stored, editable computed `analytic_distribution` field. Numeric values are percentages rounded to the **Percentage Analytic** precision (default 2 digits, defined in [`analytic_data.xml`](../addons/analytic/data/analytic_data.xml)). A GIN index on IDs extracted from the JSON keys supports account-based searches using PostgreSQL array overlap. `_search_analytic_distribution()` supplies specialized search behavior; it is not arbitrary JSON matching.

The mixin also exposes `distribution_analytic_account_ids`. `_merge_distribution()` supports updates limited to selected plan columns through the internal `__update__` key, combining them with preserved dimensions. That marker is an update mechanism, not an analytic-account ID.

**Odoo 20 also exposes `analytic_distribution` directly on analytic lines.** This is a separate computed/inverse field: it normally represents the line's existing plan combination at 100%. Editing it can split the original analytic record into several records. The base inverse splits monetary `amount`; `hr_timesheet` overrides `_split_amount_fname()` to split `unit_amount` for project timesheets, after which cost is recalculated. Do not treat this field as the same stored source JSON provided by `analytic.mixin`. See [`analytic_line.py`, `_inverse_analytic_distribution()`](../addons/analytic/models/analytic_line.py) and [`timesheet extension`](../addons/hr_timesheet/models/account_analytic_line.py).

## Automatic Distribution Models

Sources: [`analytic_distribution_model.py`](../addons/analytic/models/analytic_distribution_model.py), [`account extension`](../addons/account/models/account_analytic_distribution_model.py).

Base criteria are partner, partner category and company. `account` adds product, product category and financial-account prefixes. Empty rule criteria act as wildcards. Account prefixes are checked after the search and can be separated with commas or semicolons.

Rules are processed by **sequence ascending, then ID descending**. They are not ranked by specificity. A broadly matching rule can win over a more specific rule if it comes first.

`_get_distribution()` tracks covered root plans, including any supplied `related_root_plan_ids`. If a rule covers **any** root plan already covered, the entire rule is skipped—even if it also contains a new dimension. Otherwise its distribution is merged into the result. This is different from taking whichever uncovered pieces remain in every rule.

For example, a rule can assign every matching vendor line to one department. Separate compatible rules can contribute other dimensions, provided their plan sets do not overlap. A constraint rejects company-specific analytic accounts in a rule shared between companies or assigned to a different company.

## Mandatory Plans and Applicability

A plan's default applicability is optional, mandatory or unavailable. `_get_applicability()` selects the highest-scoring qualifying applicability rule above its baseline, otherwise retains the default. Unlike distribution models, these rules do use scores. Company filtering, business domain, account prefixes and product category can affect applicability. See [`analytic_plan.py`](../addons/analytic/models/analytic_plan.py) and [`account_analytic_plan.py`](../addons/account/models/account_analytic_plan.py).

At posting, `_validate_analytic_distribution()` checks journal items with `display_type == 'product'`, passing invoice, bill or general business context. `_validate_distribution()` requires each relevant mandatory root plan to total 100%, using the configured percentage precision. It is gated by `context['validate_analytic']`; the standard posting buttons supply that context in [`account_move_views.xml`](../addons/account/views/account_move_views.xml). A direct programmatic post without it does not guarantee mandatory-plan enforcement. This is not an unconditional validation on every draft edit. A single-move failure raises `ValidationError`; a multi-move failure can raise a `RedirectWarning` leading to the affected items.

Sources: [`account_move_line.py`](../addons/account/models/account_move_line.py), [`analytic_mixin.py`](../addons/analytic/models/analytic_mixin.py).

## Journal Linkage and Synchronization

[`account_analytic_line.py`](../addons/account/models/account_analytic_line.py) adds:

| Field | Behavior |
|---|---|
| `move_line_id` | Journal item; cascade deletion removes linked analytic entries |
| `general_account_id` | Stored editable compute from the journal item; a constraint requires equality when linked; restricts account deletion |
| `journal_id` | Stored related financial journal |
| `category` | Adds `invoice` and `vendor_bill` to base `other` |
| `analytic_profitability` | Computed revenue/loss/uncategorized classification, with SQL support |

Creating, changing or deleting linked analytic entries updates the journal item's distribution through `account.move.line._update_analytic_distribution()`. Conversely, changing a posted journal item's distribution removes and recreates its analytic lines. `skip_analytic_sync` prevents recursion during these operations.

Resetting a move to draft deletes its analytic entries with synchronization skipped, retaining the source distribution for reposting. Canceling a posted move first resets it to draft. See [`account_move.py`, `button_draft()` / `button_cancel()`](../addons/account/models/account_move.py) and [`account_move_line.py`, `_inverse_analytic_distribution()`](../addons/account/models/account_move_line.py).

## Profitability and Budgets

Odoo 20 classification in [`_compute_analytic_profitability()`](../addons/account/models/account_analytic_line.py) is significant for budgets:

| Entry | Classification |
|---|---|
| Expense financial account | loss |
| `asset_current`, `asset_non_current`, `asset_fixed` | loss |
| Income financial account | revenue |
| No financial account, category `other`, negative amount | loss |
| No financial account, category `other`, positive amount | revenue |
| No financial account, category neither `invoice` nor `other` | loss |
| Remaining cases | uncategorized |

For normal positive timesheet hours and a positive employee hourly cost, `amount = -hours × hourly_cost`, so they are costs. The sign of hours and the sign of monetary amount are opposite in that case.

The budget report first limits eligible financial-account types, then filters profitability according to budget type. Eligible asset purchases can contribute immediately to expense budgets. Analytic account balances, in contrast, aggregate analytic amounts without that budget eligibility filter. See [analytic_budget.md](analytic_budget.md) for matching, purchase commitments, liquidation and depreciation examples.

## Account Balances and Company Rules

[`analytic_account.py`, `_compute_debit_credit_balance()`](../addons/analytic/models/analytic_account.py) aggregates analytic amounts by plan column and currency:

- Debit is the absolute total of negative amounts; credit is the total of nonnegative amounts.
- Balance is credit minus debit.
- The computation limits companies to enabled companies and respects optional `from_date` / `to_date` context.
- Aggregated foreign-currency amounts are converted to the environment company's currency using the conversion default date, rather than each original transaction date.

These fields are non-stored computed values. Normal ORM caching applies; “computed” does not mean a fresh SQL aggregation on every repeated access.

The company constraint is not a blanket ban on any account that already has lines. For a nonempty assigned company, it rejects existing analytic items outside that company's descendant-company hierarchy. Branch/company relationships therefore matter.

## Configuration and Integrations

The **Analytic Accounting** setting enables the implied group `analytic.group_analytic_accounting`; it controls group-gated UI access, rather than being a universal switch that stops all analytic processing. See [`res_config_settings.py`](../addons/analytic/models/res_config_settings.py).

Accounting exposes analytic accounts, plans and distribution models through its configuration menus, and Analytic Items through Transactions, subject to installed modules and permissions.

| Integration | Contribution |
|---|---|
| `account` | Journal distribution, posting, reverse synchronization and profitability classification |
| `sale`, `purchase`, `hr_expense` | Source distributions and propagation through their business flows |
| `hr_timesheet` | Extends analytic lines directly with time and employee-cost behavior |
| `account_budget`, `account_budget_purchase` | Budget actuals and purchase commitments |
| `project_account_budget` | Project budget totals and panel actions |
| `account_asset` | Analytic distribution on asset depreciation entries |

## Gotchas

- A draft journal distribution is not an actual, but independently created analytic lines can already exist.
- Account IDs in a combined distribution key must correspond to the intended dimensions. Validation totals percentages per root plan.
- Distribution-rule priority comes from sequence/ID, not specificity; overlapping rules can be skipped wholesale.
- Asset analytic entries can affect Odoo 20 expense budgets. Do not reuse an Odoo 19 explanation that excludes all balance-sheet accounts.
- Editing a posted distribution recreates linked analytic records, so consumers should not assume their IDs remain stable.
- An analytic account balance and a budget achieved amount can differ because they use different date, company and eligibility rules.
- These descriptions cover standard source in this checkout. Custom overrides and database configuration need separate review for a specific observed result.

## Related Docs

- [Documentation index](INDEX.md)
- [Analytic budget](analytic_budget.md)
- [Fixed costs guide](accounting_fixed_costs_guide.md)
- [Multi-company and branches](accounting_multicompany_branches.md)

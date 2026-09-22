# Analytic Accounting

> **Module:** `analytic` | **Path:** [`addons/analytic/`](../addons/analytic/)
> Consumption logic (move-line → analytic lines, applicability domains) lives in [`addons/account/`](../addons/account/).

## What It Does & Why It Exists

Analytic accounting is a **parallel bookkeeping layer that classifies money by business dimension** — by project, department, cost center, vehicle, customer — independently of the general ledger (GL). The GL answers "which account, which period, debit or credit"; analytic answers "which project ate this cost" and "which department earned this revenue". The two are decoupled: one GL line (`account.move.line`) can feed several analytic accounts at once, and the analytic chart never has to mirror the chart of accounts.

The key v19 idea is **plans as dimensions**. A *plan* is a dimension (Projects, Departments, Cost Centers); an *account* is one value inside that dimension (Project A, Finance dept). Because each root plan gets its own column, one transaction can carry one value from every dimension simultaneously — enabling matrix reporting like "margin by Project AND Department". It's used by anyone doing cost-center accounting, project profitability, or budget-vs-actual. The end result is a set of `account.analytic.line` postings you can pivot, filter, and compare to budgets.

---

## The Big Picture — How It Works

```
Admin enables "Analytic Accounting"  (Settings group)
        │
        ▼
Create PLANS (dimensions)  ──spawns a column on every analytic-aware model──►  account_id, x_plan{N}_id …
        │
        ▼
Create ACCOUNTS under each plan (the dimension values)
        │
        ▼
User fills analytic_distribution {JSON} on an invoice / SO / PO / expense line
   (optionally auto-filled by a Distribution Model)
        │
        ▼
account.move is POSTED  ──► _create_analytic_lines() materializes account.analytic.line records
        │
        ▼
Reports / budgets read the analytic lines → balance per dimension
```

The distribution is **declared as a percentage JSON on the source line** but only **materialized into real postings at move-post time** ([account_move.py:5586](../addons/account/models/account_move.py#L5586) inside `_post`). Until the move is posted, no analytic line exists. Posting calls [`_create_analytic_lines()`](../addons/account/models/account_move_line.py#L3076), which validates mandatory plans, then turns each distribution entry into one `account.analytic.line` whose amount = `-balance × percentage / 100`.

### Key Decision Points
- **How many dimensions?** Each root plan = one dimension = one extra column everywhere. Most installs have 1–3 (Projects + Cost Centers).
- **Is a plan mandatory?** A plan's `default_applicability` (or a matching applicability rule) decides whether a line *must* carry a 100% distribution for that plan before the move can post.
- **Manual or automatic distribution?** Users can type the distribution by hand, or define Distribution Models that auto-fill it from partner / product / account prefix.

---

## Core Concepts (read this first)

| Concept | Model | What it is |
|---|---|---|
| **Plan** | `account.analytic.plan` | A *dimension*. Root plans create columns; sub-plans are hierarchy levels for drill-down. |
| **Account** | `account.analytic.account` | A *value* inside one plan (Project A, Finance dept). Carries the accumulated balance. |
| **Distribution** | `analytic_distribution` JSON | On a source line — splits that line's amount, by percentage, across accounts. |
| **Line** | `account.analytic.line` | The actual posting: one row, an amount, and one account per plan column. |
| **Distribution Model** | `account.analytic.distribution.model` | Rule that auto-fills the distribution JSON from context. |

The non-obvious relationship: **distribution (percentages, on the source) → lines (amounts, materialized at post)**. They are not the same field on the same record.

---

## When to Use It (and When Not To)

### This module is for:
- Tracking **cost/revenue by project, department, or cost center** without bloating the chart of accounts.
- **Project profitability** and **budget-vs-actual** (paired with `account_budget`).
- Allocating a single expense across several dimensions (e.g. an invoice 60% Project A / 40% Project B).

### Use something else when:
- You only need a **different GL account** per case — just use the chart of accounts; analytic adds nothing.
- You need **stock valuation by location/lot** — that's `stock_account`, not analytic.
- You need **statutory/tax segmentation** — that belongs in GL accounts, tags, and fiscal positions, not analytic.

---

## Real-World Scenarios

### Scenario 1: Cost center accounting on a vendor bill
**Situation:** A controller wants every vendor bill line tagged to a department so they can report spend per department.
**What they do:** Enable Analytic Accounting, create a "Departments" plan with accounts (Admin, Sales, R&D). On a bill line for office supplies they set the distribution to 100% R&D. They post the bill.
**What happens:** Posting creates one `account.analytic.line` with `amount = -balance` (a cost, negative), `x_plan{N}_id = R&D`, `general_account_id = 6130`, and `move_line_id` pointing back to the GL line. The R&D account's balance now reflects the cost.

### Scenario 2: Splitting one invoice across two projects
**Situation:** A consulting invoice covers work on two projects, 60/40.
**What they do:** On the invoice line they enter distribution `{"<ProjectA_id>": 60, "<ProjectB_id>": 40}`.
**What happens:** At post, two analytic lines are created — 60% of the line balance to Project A, 40% to Project B. The final piece absorbs any rounding residual so the two lines sum exactly to the line balance ([account_move_line.py:3115](../addons/account/models/account_move_line.py#L3115)).

### Scenario 3: Matrix tagging (Project AND Department on one line)
**Situation:** A cost belongs to Project A *and* the R&D department at once.
**What they do:** Distribution `{"<ProjectA_id>,<RnD_id>": 100}` — a **single comma-joined key**.
**What happens:** **One** analytic line is created with *both* plan columns set (`account_id = Project A`, `x_plan{N}_id = R&D`). Reports can then group by either dimension. This is the multi-plan mechanism — a comma key is one combination, not two separate allocations.

### Scenario 4: Auto-filling distribution by rule
**Situation:** All bills from a specific vendor should always go to one cost center.
**What they do:** Create a Distribution Model: condition `partner_id = ThatVendor`, distribution → that cost center. (Account-level rules can also key off product, product category, or GL account prefix.)
**What happens:** When a matching bill line is created, the model pre-fills `analytic_distribution`. One rule applies per root plan — the most specific / lowest-sequence rule wins, and once a plan is covered, later rules for that plan are skipped ([analytic_distribution_model.py:61](../addons/analytic/models/analytic_distribution_model.py#L61)).

---

## How Things Work Under the Hood

### 1. Plans create columns dynamically
Models that track analytic data inherit `analytic.plan.fields.mixin` ([analytic_line.py:11](../addons/analytic/models/analytic_line.py#L11)). When a **root plan** is created or renamed, [`_sync_all_plan_column()`](../addons/analytic/models/analytic_plan.py#L306) adds a stored `Many2one → account.analytic.account` column to every such model:

- The one plan designated **"Project"** uses the column name `account_id`; every other root plan gets `x_plan{id}_id` ([`_strict_column_name`, analytic_plan.py:116](../addons/analytic/models/analytic_plan.py#L116)).
- The "Project" plan is not hardcoded by ID — it is whichever plan id is stored in the `analytic.project_plan` system parameter. If that parameter is unset, the system raises *"A 'Project' plan needs to exist…"* ([analytic_plan.py:107](../addons/analytic/models/analytic_plan.py#L107)). You cannot give the base Project plan a parent ([analytic_plan.py:187](../addons/analytic/models/analytic_plan.py#L187)).
- **Sub-plans** (with a parent) do *not* get their own stored column. They create a non-stored related field for hierarchy-level grouping only — they're for drill-down, not data entry.

### 2. The `analytic_distribution` JSON field
Provided by `analytic.mixin` ([analytic_mixin.py:16](../addons/analytic/models/analytic_mixin.py#L16)) to every analytic-aware source model (`account.move.line`, `sale.order.line`, `purchase.order.line`, `hr.expense`, assets…). Shape:

```json
{ "12": 50.0, "7": 30.0, "12,7": 20.0 }
```
- **Keys** = analytic account ids. A **comma-joined key** ("12,7") is one combination spanning multiple plans → one analytic line with multiple plan columns set.
- **Values** = percentages, rounded to the "Percentage Analytic" decimal precision (default 2 places).
- Stored as **JSONB**. A **GIN index** is built on the account ids extracted from the keys ([analytic_mixin.py:32](../addons/analytic/models/analytic_mixin.py#L32)), so you can filter records by analytic account fast. The custom [`_search_analytic_distribution`](../addons/analytic/models/analytic_mixin.py#L72) resolves an account name/id to a Postgres array-overlap (`&&`) query against that index.

### 3. Materialization at post time
- **Trigger:** `account.move._post()` calls `line_ids._create_analytic_lines()` ([account_move.py:5586](../addons/account/models/account_move.py#L5586)). Analytic lines are **real records created on post**, not live-computed — drafts have none.
- **[`_create_analytic_lines()`](../addons/account/models/account_move_line.py#L3076)** validates, then batch-creates the lines with `skip_analytic_sync=True` (to avoid bouncing the change back into the distribution JSON).
- **[`_prepare_analytic_distribution_line()`](../addons/account/models/account_move_line.py#L3104)** builds one line per distribution key: amount = `-self.balance × pct / 100`, with the final slice of each root plan computed as `-balance × (100 − already_allocated)/100` so the per-plan total reconciles exactly to the GL balance ([account_move_line.py:3115](../addons/account/models/account_move_line.py#L3115)). Each account in the key sets its own plan column via `account.plan_id._column_name()` ([account_move_line.py:3119](../addons/account/models/account_move_line.py#L3119)).

### 4. Mandatory-plan enforcement (applicability)
- `account.analytic.applicability` ([defined analytic_plan.py:394](../addons/analytic/models/analytic_plan.py#L394); **extended** in [account_analytic_plan.py:7](../addons/account/models/account_analytic_plan.py#L7) to add `business_domain` invoice/bill, `account_prefix`, `product_categ_id`).
- A plan's effective applicability is the best-scoring matching rule, else its `default_applicability` ([`_get_applicability`, analytic_plan.py:242](../addons/analytic/models/analytic_plan.py#L242); scoring in [`_get_score`, analytic_plan.py:421](../addons/analytic/models/analytic_plan.py#L421)). Levels: **optional** (free), **mandatory** (must total 100%), **unavailable** (hidden).
- At post, [`_validate_distribution`](../addons/analytic/models/analytic_mixin.py#L174) sums the distribution per root plan and raises *"One or more lines require a 100% analytic distribution"* if any **mandatory** plan isn't exactly 100%.

### 5. The analytic line ↔ GL line link
On `account.analytic.line` ([account_analytic_line.py](../addons/account/models/account_analytic_line.py)):
- `move_line_id` → the GL line, `ondelete='cascade'` ([line 36](../addons/account/models/account_analytic_line.py#L36)): delete the GL line and its analytic lines vanish.
- `general_account_id` → the GL account, `ondelete='restrict'`, and a constraint forces it to equal `move_line_id.account_id` ([`_check_general_account_id`, :53](../addons/account/models/account_analytic_line.py#L53)).
- **Sign:** analytic amount mirrors GL semantics (`* -1` on the computed cost, [:77](../addons/account/models/account_analytic_line.py#L77)) — costs negative, revenue positive relative to the GL line.
- Editing analytic lines syncs the distribution back to the GL line via `_update_analytic_distribution()` ([:94](../addons/account/models/account_analytic_line.py#L94)).
- **Base constraint:** every analytic line must reference at least one plan account — all plan columns empty raises *"At least one analytic account must be set"* ([analytic_line.py:93](../addons/analytic/models/analytic_line.py#L93)).

### 6. Account balances
`debit`/`credit`/`balance` on `account.analytic.account` are **computed, not stored** ([`_compute_debit_credit_balance`, analytic_account.py:163](../addons/analytic/models/analytic_account.py#L163)). Each read aggregates `account.analytic.line` via `_read_group`, converts foreign currencies to the company currency at *today's* rate, and respects `from_date`/`to_date` in context (omit them → all-time balance). Changing an account's `company_id` is blocked if it already has lines ([`_check_company_consistency`, :96](../addons/analytic/models/analytic_account.py#L96)).

### Distribution Models — the matching algorithm
[`_get_distribution(vals)`](../addons/analytic/models/analytic_distribution_model.py#L61) finds applicable rules (ordered by `sequence`, then newest id), and merges their distributions **one rule per root plan** — once a plan is covered it won't be overwritten by a later rule. Match criteria: `partner_id`, `partner_category_id`, `company_id` (base) plus `product_id`, `product_categ_id`, and `account_prefix` (added in [account_analytic_distribution_model.py](../addons/account/models/account_analytic_distribution_model.py)). A rule with no value for a criterion matches anything; `account_prefix` is matched post-search as a string prefix on the GL account code. A constraint blocks a company-agnostic rule from using company-specific accounts ([`_check_company_accounts`, :40](../addons/analytic/models/analytic_distribution_model.py#L40)).

---

## Configuration & Settings

- **Analytic Accounting** (Settings → Accounting → *Analytic Accounting* checkbox) — the master switch. It's a `group_analytic_accounting` implied group ([res_config_settings.py:10](../addons/analytic/models/res_config_settings.py#L10)). Off by default; until enabled, all analytic fields and menus are hidden everywhere (Sales, Purchase, Expenses, Accounting).
- **`analytic.project_plan`** system parameter — names which plan owns the `account_id` column. Validated on change (must be an existing root plan, never a sub-plan); changing it re-syncs DB columns, so only change it through the ORM/UI, never raw SQL ([ir_config_parameter.py](../addons/analytic/models/ir_config_parameter.py)).
- **"Percentage Analytic" decimal precision** — controls rounding of distribution percentages (default 2 digits), shipped in [analytic_data.xml](../addons/analytic/data/analytic_data.xml).

### Where to find things in the UI (once enabled)
- **Accounting → Configuration → Analytic Accounting:** Distribution Models, Analytic Accounts (the analytic chart), Analytic Plans.
- **Accounting → Transactions → Analytic Items:** every `account.analytic.line` (list / pivot / graph).

---

## Dependencies

| Requires | Why |
|---|---|
| `base`, `mail`, `uom` | Core ORM, tracking/chatter on accounts, units of measure on lines ([__manifest__.py](../addons/analytic/__manifest__.py)). |

| Works With | What It Adds |
|---|---|
| `account` | The whole GL bridge: move-line distribution → analytic lines at post, applicability `business_domain`/`account_prefix`/`product_categ_id`, distribution-model product criteria. |
| `account_budget` / `project_account_budget` | Budget-vs-actual against analytic balances — see [analytic_budget.md](analytic_budget.md). |
| `sale`, `purchase`, `hr_expense`, `hr_timesheet` | Add the `analytic_distribution` field (via the mixin) to their lines, so SO/PO/expense/timesheet rows feed analytic accounts. |

---

## Gotchas & Non-Obvious Behavior

- **No lines until posted.** Setting a distribution on a draft does nothing visible in analytic reports; `account.analytic.line` records only appear when the move is posted. Reset-to-draft/repost re-runs the materialization.
- **Comma key = one combination, not two allocations.** `{"12,7": 100}` is a single line spanning two plans, not two lines. `{"12": 50, "7": 50}` is two separate allocations.
- **Distribution stores percentages; lines store amounts.** They are different fields on different records. Don't expect to read amounts off the distribution JSON.
- **Mandatory means exactly 100% per root plan.** 99% or 101% (after rounding) blocks the post with a ValidationError — and the validation is gated on `context['validate_analytic']`, so it fires on real posting, not on every draft write.
- **Balances are recomputed on every read** (no stored balance) and converted at *today's* FX rate. On large datasets, scope by date or plan; don't assume a cached figure.
- **Project plan is identified by config parameter, not by id=1.** Code that assumes a fixed id will break; resolve via `analytic.project_plan` / `_get_all_plans()`.
- **`auto_account_id` is context-dependent.** It reads/writes whichever plan column matches `context['analytic_plan_id']`; accessing it without that context can mislead. Use the explicit plan column or set the context.
- **Changing an account's company is refused once it has lines** — write/migrate the lines first.

---

## Related Docs

- [`INDEX.md`](INDEX.md)
- [`analytic_budget.md`](analytic_budget.md) — budgets read these analytic balances (achieved vs planned).
- [`accounting_fixed_costs_guide.md`](accounting_fixed_costs_guide.md) — covers analytic distribution JSON + multi-plan from the GL/fixed-cost angle.
- [`accounting_multicompany_branches.md`](accounting_multicompany_branches.md) — analytic accounting in a multi-company/branch context.

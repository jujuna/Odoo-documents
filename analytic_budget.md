# Analytic Budget

> **Modules:** `account_budget` (enterprise) + `project_account_budget` (enterprise)
> **Paths:** [`enterprise/account_budget/`](../enterprise/account_budget/) | [`enterprise/project_account_budget/`](../enterprise/project_account_budget/)
> **Odoo Apps category:** Accounting / Project

## What It Does

Analytic budget lets you set a planned spending (or revenue) ceiling on an analytic account and track how much has actually been spent against it in real time. Each budget is divided into lines, each line pointing at one or more analytic accounts for a date range. "Achieved" amount is computed live from posted journal entries that carry an analytic distribution matching that line. Projects linked to analytic accounts get a budget panel showing allocated vs. spent vs. progress.

---

## Dependencies

### Requires
| Module | Why |
|---|---|
| `analytic` | provides `account.analytic.account`, `account.analytic.plan`, `account.analytic.line` |
| `account` | journal entries post analytic lines; `account.move.line` is the source of achieved amounts |
| `project` | `project_account_budget` links projects to budgets via `project.project.account_id` |

### Optional Integrations
| Module | What it enables |
|---|---|
| `account_budget_purchase` | adds "committed" amount from purchase orders (not yet posted) |
| `hr_timesheet` | timesheet hours create analytic lines that count towards expense budgets |

---

## Business Flow

```
Create Budget (draft)
      ↓
Add Budget Lines (each line = analytic account + date range + budget amount)
      ↓
Confirm Budget → state = 'confirmed'
      ↓
Real transactions posted (vendor bills, invoices, timesheets) → analytic lines created
      ↓
budget.report SQL view joins analytic lines → achieved_amount computed live
      ↓
Project panel shows allocated / spent / progress %
```

### Budget States
| State | Meaning | Can Transition To |
|---|---|---|
| `draft` | created, not active | `confirmed`, `canceled` |
| `confirmed` | active, being tracked | `done`, `canceled`, `revised` (if a child revision is confirmed) |
| `revised` | superseded by a child revision | `done`, `canceled` |
| `done` | closed manually | — |
| `canceled` | discarded | — |

Source: [`enterprise/account_budget/models/budget_analytic.py:29-42`](../enterprise/account_budget/models/budget_analytic.py#L29)

### State Transitions
- **Confirm** → [`action_budget_confirm()`](../enterprise/account_budget/models/budget_analytic.py#L73) — sets this budget to `confirmed`; if parent exists and is confirmed, parent becomes `revised`
- **Create Revision** → [`create_revised_budget()`](../enterprise/account_budget/models/budget_analytic.py#L87) — copies the budget, links it as child, parent becomes `revised`
- **Done / Cancel** → [`action_budget_done()`](../enterprise/account_budget/models/budget_analytic.py#L84) / [`action_budget_cancel()`](../enterprise/account_budget/models/budget_analytic.py#L81)

---

## Key Models

### `budget.analytic` — The budget header
> [`enterprise/account_budget/models/budget_analytic.py`](../enterprise/account_budget/models/budget_analytic.py)

| Field | Type | Purpose |
|---|---|---|
| `name` | `Char` | Budget name |
| `state` | `Selection` | draft / confirmed / revised / done / canceled |
| `budget_type` | `Selection` | `expense`, `revenue`, or `both` — controls which analytic lines count |
| `date_from` / `date_to` | `Date` | Budget period; analytic lines outside this range are ignored |
| `budget_line_ids` | `One2many → budget.line` | The line items |
| `parent_id` / `children_ids` | `Many2one / One2many` | Revision chain |

---

### `budget.line` — One budget line item
> [`enterprise/account_budget/models/budget_line.py`](../enterprise/account_budget/models/budget_line.py)

| Field | Type | Purpose |
|---|---|---|
| `budget_analytic_id` | `Many2one → budget.analytic` | Parent budget |
| `account_id` | `Many2one → account.analytic.account` | Project-plan analytic account (dynamic via `analytic.plan.fields.mixin`) |
| `x_plan2_id`, `x_plan3_id` | `Many2one` | Additional plan columns (auto-generated per plan) |
| `budget_amount` | `Monetary` | The planned amount |
| `achieved_amount` | `Monetary` (computed) | Actual amount from posted transactions — see below |
| `theoritical_amount` | `Monetary` (computed) | `budget_amount × (elapsed_days / total_days)` — what should have been spent by today |
| `achieved_percentage` | `Float` (computed) | `achieved / budget` |
| `is_above_budget` | `Boolean` (computed) | `achieved > budget` |

**Computed fields:**
- `achieved_amount` — [`_compute_all()`](../enterprise/account_budget/models/budget_line.py#L59) — queries `budget.report` view, sums `achieved` per budget line
- `theoritical_amount` — [`_compute_theoritical_amount()`](../enterprise/account_budget/models/budget_line.py#L71) — linear interpolation over the budget date range

---

### `budget.report` — SQL view (no real table)
> [`enterprise/account_budget/reports/budget_report.py`](../enterprise/account_budget/reports/budget_report.py)

This is the **core engine**. It is `_auto = False` — a read-only SQL view built fresh each query. It is a `UNION ALL` of two subqueries:

**Part 1 — `_get_bl_query()`**: Budget lines themselves (`line_type = 'budget'`).

**Part 2 — `_get_aal_query()`**: `account.analytic.line` records (`line_type = 'achieved'`).

The JOIN condition matching analytic lines to budget lines:
```sql
aal.date >= bl.date_from AND aal.date <= bl.date_to
AND aal.[plan_column] = bl.[plan_column]   -- e.g. aal.account_id = bl.account_id
AND aal.company_id = bl.company_id         -- or bl.company_id IS NULL
```

The filter determining which analytic lines count, based on `budget_type`:
```sql
WHEN ba.budget_type = 'expense' THEN (
    SPLIT_PART(aa.account_type, '_', 1) = 'expense'          -- expense GL account
    OR (aa.account_type IS NULL AND aal.category NOT IN ('invoice', 'other'))  -- e.g. vendor_bill (no GL)
    OR (aa.account_type IS NULL AND aal.category = 'other' AND aal.amount < 0) -- negative timesheets
)
WHEN ba.budget_type = 'revenue' THEN (
    SPLIT_PART(aa.account_type, '_', 1) = 'income'            -- income GL account
    OR (aa.account_type IS NULL AND aal.category = 'other' AND aal.amount > 0) -- positive timesheets
)
ELSE TRUE   -- 'both': income + expense + NULL account types; asset/liability/equity always excluded
```

Global additional filter (applies to all budget types):
```sql
AND (SPLIT_PART(aa.account_type, '_', 1) IN ('income', 'expense') OR aa.account_type IS NULL)
```
Asset, liability, equity, payable, receivable GL accounts are **always excluded** regardless of budget type.

The `achieved` value formula:
```sql
aal.amount * CASE WHEN ba.budget_type = 'expense' THEN -1 ELSE 1 END AS achieved
```
Expense negation: analytic lines for expenses store **negative** amounts (debit to expense account → `amount = -balance`). The `-1` factor makes them positive for display against `budget_amount`.
For `revenue` and `both`: no negation — amounts are used as-is.

Source: [`enterprise/account_budget/reports/budget_report.py:59-119`](../enterprise/account_budget/reports/budget_report.py#L59)

---

## Budget Types — Full Comparison

Source: [`budget_report.py:94-106`](../enterprise/account_budget/reports/budget_report.py#L94), [`test_commited_achieved_amount.py`](../enterprise/account_budget_purchase/tests/test_commited_achieved_amount.py), [`test_project.py`](../enterprise/project_account_budget/tests/test_project.py)

### `expense` — Cost Ceiling

**Business use:** "We have $10,000 to spend on this project. Alert when approaching the limit."

**What analytic lines are counted:**
| Source | GL Account Type | Category | Counted? | Achieved sign |
|---|---|---|---|---|
| Vendor bill posted | `expense_*` | `vendor_bill` | YES | `amount * -1` → positive |
| Vendor bill posted | `expense_*` | `vendor_bill` | partial bills also YES | positive |
| Customer invoice posted | `income_*` | `invoice` | NO | — |
| Manual journal entry | `expense_*` | `other` | YES | `amount * -1` → positive |
| Manual journal entry | `asset_*` / `liability_*` | any | NO | — |
| Timesheet (positive hours) | NULL | `other`, amount > 0 | NO | — |
| Timesheet (negative hours) | NULL | `other`, amount < 0 | YES | `amount * -1` → positive |
| Manual AAL, no GL, `vendor_bill` | NULL | NOT 'invoice'/'other' | YES | `amount * -1` |

**Progress direction:** Starts at 1.0 (full budget remaining), drops to 0 as spending hits 100%, goes negative when over budget.

**Progress formula** (from `_get_budget_items`, `project_project.py:132`):
```python
progress = (spent - allocated) / abs(allocated) * -1
# spent=0, allocated=500 → (0-500)/500 * -1 = 1.0   → green
# spent=375, allocated=500 → (375-500)/500 * -1 = 0.25 → green boundary
# spent=500, allocated=500 → (500-500)/500 * -1 = 0.0  → orange (warning)
# spent=600, allocated=500 → (600-500)/500 * -1 = -0.2  → red (danger)
```

**Credit notes reduce the achieved amount** — a credit note posted against a vendor bill creates a positive analytic line on the expense account (positive balance → `amount = -balance < 0`), which after `* -1` becomes negative, reducing total achieved. Proven in `test_budget_analytic_expense_with_credit_note`.

---

### `revenue` — Revenue Target

**Business use:** "We need to invoice $50,000 this quarter. Show how close we are."

**What analytic lines are counted:**
| Source | GL Account Type | Category | Counted? | Achieved sign |
|---|---|---|---|---|
| Customer invoice posted | `income_*` | `invoice` | YES | `amount * 1` → positive |
| Vendor bill posted | `expense_*` | `vendor_bill` | NO | — |
| Manual journal entry | `income_*` | `other` | YES | `amount * 1` → positive |
| Timesheet (positive hours) | NULL | `other`, amount > 0 | YES | positive |
| Timesheet (negative hours) | NULL | `other`, amount < 0 | NO | — |
| Purchase order (committed) | — | — | NO effect on revenue budget | — |

**Progress direction:** Starts at -1.0 (nothing achieved), rises toward 0 as invoices are posted, goes positive when over target.

**Progress formula:**
```python
progress = (spent - allocated) / abs(allocated) * 1
# spent=0, allocated=500 → (0-500)/500 = -1.0    → gray "Budget allocated" (special case)
# spent=375, allocated=500 → (375-500)/500 = -0.25 → still tracking
# spent=500, allocated=500 → (500-500)/500 = 0.0   → orange (barely met, on boundary)
# spent=625, allocated=500 → (625-500)/500 = 0.25  → green (target exceeded by 25%)
```

Note: "progress >= 0.25" = green for revenue means **exceeded the target by 25%**. For revenue budgets, going "over" is good.

---

### `both` — Net Position

**Business use:** "Track both revenues and costs on the same budget. Show net profitability."

**What analytic lines are counted:**
| Source | GL Account Type | Category | Counted? | Achieved sign |
|---|---|---|---|---|
| Customer invoice posted | `income_*` | `invoice` | YES | `amount * 1` → positive |
| Vendor bill posted | `expense_*` | `vendor_bill` | YES | `amount * 1` → **negative** (expenses stored negative) |
| Manual journal entry | `income_*` OR `expense_*` | `other` | YES | `amount * 1` |
| Timesheet | NULL | `other` | YES | `amount * 1` |
| Asset/liability GL accounts | `asset_*` / `liability_*` | any | NO | — |

**Key difference from `expense`:** The sign is **not negated** (`* 1`). Expense analytic lines are already negative in storage, so they reduce the achieved total. Revenue lines are positive, they increase it.

**From test `test_budget_analytic_both_committed_achieved_amount`:**
- Bill lines: -100, -300 (expenses) → achieved contribution: -100, -300
- Invoice lines: 200, 400 (revenues) → achieved contribution: +200, +400
- Manual AALs: +200, -100
- Total achieved = -100 + (-300) + 200 + 400 + 200 + (-100) = **+300**

**From test `test_budget_analytic_misc_entry` (misc journal entry on expense account):**
- Entry: debit expense 100, credit asset 70 (asset excluded by global filter)
- `both` budget: `achieved = -100 * 1 = -100` (net negative — cash out)
- `expense` budget: `achieved = -100 * -1 = 100` (positive — cost consumed)

**Progress formula:** Same as revenue (`type_factor = 1`).

**Budget amount meaning for `both`:** The `budget_amount` is the target net position (revenues minus expenses). Setting `budget_amount = 0` and watching achieved go positive means profitable; negative means loss.

---

### Quick Reference

| | `expense` | `revenue` | `both` |
|---|---|---|---|
| **Purpose** | Cost ceiling | Revenue target | Net position |
| **Expense GL lines** | YES (positive) | NO | YES (negative) |
| **Revenue GL lines** | NO | YES (positive) | YES (positive) |
| **No-GL lines (timesheets)** | negative only | positive only | all |
| **Amount sign in achieved** | `* -1` (flipped) | `* 1` (as-is) | `* 1` (as-is) |
| **Starting progress (empty)** | 1.0 (green) | -1.0 (gray) | -1.0 (gray) |
| **"On track" means** | budget not overspent | revenue target exceeded | net positive |
| **Credit note effect** | reduces achieved | reduces achieved | increases achieved |
| **Default** | YES (default value) | — | — |

---

### `account.analytic.line` — The source of "achieved"
> [`addons/analytic/models/analytic_line.py:154`](../addons/analytic/models/analytic_line.py#L154)

| Field | Purpose |
|---|---|
| `amount` | Monetary amount — negative for expenses (follows accounting balance sign) |
| `date` | Must fall within `budget.line.date_from` → `date_to` to be counted |
| `account_id` / `x_plan*_id` | Must match the analytic account on the budget line |
| `general_account_id` | The GL account — determines account_type for expense/revenue filtering |
| `category` | `invoice`, `vendor_bill`, `other` — affects filtering when no GL account |
| `move_line_id` | FK back to the journal entry line that created it |

---

## When Does the Budget "Decrease" (Achieved Amount Increases)?

"Achieved" increasing means you are consuming the budget. It happens when an `account.analytic.line` is created that matches a budget line.

### Trigger 1: Posting a Vendor Bill / Expense
- User posts a vendor bill (or expense report) with analytic distribution pointing to the project's analytic account
- [`account_move.action_post()`](../addons/account/models/account_move.py#L5586) calls `line_ids._create_analytic_lines()`
- [`_create_analytic_lines()`](../addons/account/models/account_move_line.py#L3076) loops over move lines that have `analytic_distribution`, creates `account.analytic.line` records
- For a vendor bill: `category = 'vendor_bill'`, `general_account_id` = expense GL account (account_type starts with `expense_`)
- The analytic line `amount = -balance` where balance > 0 (debit on expense) → amount is **negative**
- In `budget.report`, expense budget: `achieved = amount * -1` → **positive**, consumed from budget

### Trigger 2: Posting a Customer Invoice (revenue budget)
- User posts an invoice with analytic distribution on a revenue/income account
- `category = 'invoice'`, `general_account_id` = income GL account (account_type starts with `income_`)
- `amount = -balance` where balance < 0 (credit on income account) → amount is **positive**
- Revenue budget: `achieved = amount * 1` → positive, counted as revenue achieved

### Trigger 3: Timesheets (if hr_timesheet installed)
- Timesheet entries create `account.analytic.line` with `category = 'other'`, no `general_account_id`
- For expense budget: only counted if `amount < 0` (negative time cost entries)
- For revenue budget: counted if `amount > 0`
- Normal positive timesheet hours: counted towards revenue budgets, NOT expense budgets

### Trigger 4: Manual Journal Entry (Misc Entry)
A manual `entry` type journal entry counts **only if at least one line meets all conditions:**

**Conditions for a journal entry line to register on the budget:**

| Condition | Requirement |
|---|---|
| Entry state | Must be **posted** (`state = 'posted'`) — draft entries create no analytic lines |
| Line has analytic distribution | `analytic_distribution` field must be set on the move line |
| GL account type | Must be `expense_*` or `income_*` — **asset, liability, equity, payable, receivable are all excluded** |
| Budget type match | `expense` budget → line must be on an `expense_*` account; `revenue` → `income_*`; `both` → either |
| Date in range | `move.date` must fall within `budget.line.date_from` → `budget.line.date_to` |
| Analytic account match | The analytic account in `analytic_distribution` must match the plan column on the budget line |
| Company | `move.company_id` must match `budget.analytic.company_id` (or budget company = NULL) |

**Correct structure for a misc entry targeting an expense budget:**
```
DEBIT  → expense account (e.g. "Expenses", "Rent", "Office Supplies")
           + analytic_distribution = {"<analytic_account_id>": 100}
CREDIT → any account (asset, payable, etc.) — no analytic required
```

**Why `MISC/2026/02/0003` did NOT count:**
- Both lines used `asset_cash` and `asset_current` accounts
- `SPLIT_PART('asset_cash', '_', 1) = 'asset'` → not in `('income', 'expense')` → global filter excludes it
- The analytic distribution on asset lines is stored but never read by the budget engine

**Correct structure for a misc entry targeting a revenue budget:**
```
DEBIT  → any account (asset, receivable, etc.) — no analytic required
CREDIT → income account (e.g. "Product Sales", "Other Income")
           + analytic_distribution = {"<analytic_account_id>": 100}
```

**Accounts that NEVER count regardless of budget type:**

| account_type | Examples | Budget visible? |
|---|---|---|
| `asset_cash` | Bank, Cash | NO |
| `asset_current` | Outstanding Payments, Prepaid Expenses | NO |
| `asset_fixed` | Buildings, Computers | NO |
| `asset_non_current` | Long-term investments | NO |
| `liability_payable` | Accounts Payable | NO |
| `liability_current` | Current liabilities | NO |
| `equity` | Share capital | NO |
| `expense` | Expenses, Rent, Salary | YES (expense/both budgets) |
| `expense_direct_cost` | Cost of Goods Sold | YES (expense/both budgets) |
| `expense_other` | Foreign Exchange Loss, Taxes | YES (expense/both budgets) |
| `income` | Product Sales, FX Gain | YES (revenue/both budgets) |
| `income_other` | Other Income | YES (revenue/both budgets) |

### Trigger 5: Direct Analytic Lines
- A user manually creates an `account.analytic.line` via Accounting → Analytic → Analytic Items
- No GL account → `general_account_id = NULL` → filtered by category and amount sign instead (see budget type tables above)
- Same date range and analytic account matching applies

### NOT counted:
- Draft or cancelled journal entries (not yet posted)
- Journal entry lines on asset / liability / equity accounts — even with analytic distribution set
- Analytic lines outside the budget date range
- Analytic lines pointing to a different analytic account than the budget line
- Analytic lines from a different company (unless budget line has `company_id = NULL`)

---

## Project Integration

> [`enterprise/project_account_budget/models/project_project.py`](../enterprise/project_account_budget/models/project_project.py)

A project is linked to a budget via `project.project.account_id` (the project's analytic account).

The budget panel shows data from budget lines where the plan column matches `project.account_id`.

Only budgets in `confirmed` or `done` state are shown in the project panel.

| Field | Computed by | Logic |
|---|---|---|
| `total_budget_amount` | [`_compute_budget()`](../enterprise/project_account_budget/models/project_project.py#L21) | Sum of `budget_amount` from ALL matching `budget.line` records (any state) |
| `total_budget_progress` | [`_compute_budget()`](../enterprise/project_account_budget/models/project_project.py#L21) | `(achieved_fp - allocated_fp) / abs(allocated_fp)` adjusted for budget type |

For **expense** budgets: `type_factor = -1` is applied to both amounts so spending = positive progress.

Progress interpretation (used for kanban icon color):
- `>= 0.25` → green (on track)
- `0` to `0.25` → orange (soon overspent)
- `< 0` → red (over budget)
- `== -1.0` → gray (no spending yet)

**Add Budget flow from project panel:**
1. User clicks **Add Budget** in the right side panel
2. OWL opens `FormViewDialog` for `budget.analytic` with `context = {project_update: True, ...}`
3. `budget_line.default_get()` detects `project_update` → pre-fills plan column with `project.account_id` — [`budget_line.py:9`](../enterprise/project_account_budget/models/budget_line.py#L9)
4. On save, `budget_analytic.create()` detects `project_update` → auto-calls `action_budget_confirm()` — [`budget_analytic.py:10`](../enterprise/project_account_budget/models/budget_analytic.py#L10)
5. Budget is auto-confirmed immediately — no manual confirm needed from project panel
6. Panel reloads via `loadBudgets()` RPC call to `get_budget_items()`

**Project Update report** injects budget data via `project_update._get_template_values()` — requires `account.group_account_readonly`. Shows `percentage` spent and `remaining_budget_percentage`.

---

## UI Entry Points

| Entry Point | Path in UI | What It Does |
|---|---|---|
| Budget list | Accounting → Management → Budgets | Create/view budgets, see achieved vs planned |
| Budget form | Budget form → Budget Lines | Add lines with analytic accounts and amounts |
| Confirm button | Budget form | Sets state to `confirmed`, makes it active |
| Project budget panel | Project → Update → Budget section | Shows per-budget allocated/spent/progress |
| Add Budget (project) | Project Update panel | Creates and auto-confirms a budget linked to project's analytic account |
| Budget Report | Budget form → Budget Report button | Opens `budget.report` pivot/list showing each analytic line |

---

## Edge Cases & Gotchas

- **Budget must be `confirmed` or `done` to appear in the project panel.** Draft budgets are invisible there. Source: [`project_project.py:85`](../enterprise/project_account_budget/models/project_project.py#L85)

- **Achieved amount does NOT decrease when a posted invoice is reset to draft.** Cancelling a posted entry deletes the analytic lines — achieved drops. But resetting to draft also removes analytic lines, so the achieved goes back down.

- **Expense amounts are stored as negative in analytic lines.** The budget report negates them for display. If you query `account_analytic_line` directly, expense entries show negative `amount`.

- **The budget type determines which GL accounts count.** If `budget_type = 'expense'` and an analytic line has a revenue GL account — it is excluded. The filter is strict: `SPLIT_PART(account_type, '_', 1)` must match the budget type.

- **`budget.report` is a live SQL view.** There is no caching. Every time `achieved_amount` is computed on a budget line, a query runs against the view which joins `budget_line` and `account_analytic_line`. On large datasets this can be slow.

- **Analytic account must be in the correct plan.** The budget line uses plan-specific columns (e.g., `account_id` for the project plan). If you assign a non-project analytic account to a project's budget line, the join won't match the project's `account_id`.

- **`theoritical_amount` is date-based only, not transaction-based.** It is a simple linear interpolation. It does not know if spending is front-loaded or back-loaded.

- **Deleting a budget only allowed in draft or canceled state.** See [`_unlink_except_draft_or_cancel()`](../enterprise/account_budget/models/budget_analytic.py#L68).

---

## Related Docs

- [`INDEX.md`](INDEX.md)

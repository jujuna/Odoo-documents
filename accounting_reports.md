# Accounting Reports Engine

> **Module:** `account_reports` (enterprise) | **Path:** [enterprise/account_reports/](../enterprise/account_reports/)
> **Depends on:** `account_accountant`
> **Base models:** `account` module ([addons/account/models/account_report.py](../addons/account/models/account_report.py))

---

## What It Does

The reporting engine is a **data-driven framework** for financial statements. Every report — Balance Sheet, P&L, Trial Balance, Tax Return, General Ledger, etc. — is a set of database records, not hardcoded Python. You define what lines to show and how to compute each value; the engine runs SQL and assembles the result.

**Core idea:**
- A report is `account.report` + its `account.report.line` rows
- Each row has `account.report.expression` records — one per column
- Each expression has an `engine` field that determines how its value is computed
- 6 engines exist, each running against `account.move.line`
- The result is an interactive screen view with drill-down, filters, PDF/XLSX export, comparison columns

---

## Dependencies

| Module | Why |
|---|---|
| `account_accountant` | Full accounting — posted entries, fiscal years |
| `account` | Base models: `account.report`, `account.report.line`, `account.report.expression` |

**Consumers:**

| Consumer | What it uses |
|---|---|
| `l10n_*` | Localized tax report variants via `root_report_id` + `country_id` |
| `account_reports_cash_basis` | `only_tax_exigible` filter |
| `account_budget` | `filter_budgets` on P&L |

---

## Architecture: Three-Layer Model

```
account.report
    └── account.report.line          (one row, e.g. "Current Assets")
            └── account.report.expression   (one cell value per column)
                    engine     = domain | tax_tags | aggregation | account_codes | external | custom
                    formula    = what to compute (syntax depends on engine)
                    subformula = modifier on the result
                    date_scope = time window for the SQL
```

Every number on a financial report comes from an `account.report.expression` evaluated by its engine against `account.move.line`.

---

## Core Models

### `account.report` — The Report Definition

> [addons/account/models/account_report.py](../addons/account/models/account_report.py)
> Extended by [enterprise/account_reports/models/account_report.py](../enterprise/account_reports/models/account_report.py)

| Field | Type | Purpose |
|---|---|---|
| `name` | `Char` | Report name in UI and menus |
| `line_ids` | `One2many → account.report.line` | All rows of this report |
| `column_ids` | `One2many → account.report.column` | Column headers — each must match an expression `label` |
| `root_report_id` | `Many2one → account.report` | Points to the generic root; this record is a **variant** |
| `variant_report_ids` | `One2many` | All country/COA-specific variants of this report |
| `section_report_ids` | `Many2many` | Sub-reports for **composite** reports |
| `use_sections` | `Boolean` (computed) | True if this is a composite report |
| `country_id` | `Many2one → res.country` | Restricts report to one country |
| `chart_template` | `Selection` | Restricts report to one Chart of Accounts |
| `availability_condition` | `Selection` | When this report appears: `always`, `country`, `coa` |
| `custom_handler_model_id` | `Many2one → ir.model` | Model inheriting `account.report.custom.handler` |
| `default_opening_date_filter` | `Selection` | Default date range when report opens |

**Filter fields** — each adds a filter widget in the UI:
`filter_date_range`, `filter_journals`, `filter_analytic`, `filter_partner`, `filter_hierarchy`,
`filter_period_comparison`, `filter_growth_comparison`, `filter_hide_0_lines`, `filter_multi_company`, etc.

---

### `account.report.line` — A Report Row

> [addons/account/models/account_report.py:349](../addons/account/models/account_report.py#L349)

| Field | Type | Purpose |
|---|---|---|
| `name` | `Char` | Row label |
| `code` | `Char` | Unique ID used in aggregation formulas (e.g., `CA`, `REV`) |
| `parent_id` | `Many2one` | Parent line for hierarchy |
| `children_ids` | `One2many` | Child lines |
| `expression_ids` | `One2many` | One expression per column |
| `groupby` | `Char` | Comma-separated `account.move.line` fields — expands row into sublines |
| `hierarchy_level` | `Integer` (computed) | Indentation depth; root = 1 |
| `foldable` | `Boolean` | If True, line starts collapsed |
| `hide_if_zero` | `Boolean` | Hidden when all columns are 0 |
| `horizontal_split_side` | `Selection` | `left`/`right` — side-by-side Balance Sheet layout |
| `sequence` | `Integer` | Display order |

**Shortcut write-only fields** (auto-create `expression_ids`):
- `domain_formula` → creates a `domain` engine expression
- `account_codes_formula` → creates an `account_codes` engine expression
- `aggregation_formula` → creates an `aggregation` engine expression
- `tax_tags_formula` → creates a `tax_tags` engine expression

---

### `account.report.expression` — One Cell Value

> [addons/account/models/account_report.py:579](../addons/account/models/account_report.py#L579)

| Field | Type | Purpose |
|---|---|---|
| `label` | `Char` | Matches `account.report.column.expression_label` (e.g., `balance`) |
| `engine` | `Selection` | Which computation engine (see below) |
| `formula` | `Char` | What to compute — syntax depends on engine |
| `subformula` | `Char` | Modifier on the result (e.g., `sum`, `-sum`) |
| `date_scope` | `Selection` | Time window for the SQL query |
| `figure_type` | `Selection` | `monetary`, `percentage`, `integer`, `float`, `date`, `string` |
| `green_on_positive` | `Boolean` | Color: green when positive |
| `blank_if_zero` | `Boolean` | Show blank instead of 0 |
| `auditable` | `Boolean` (computed) | Clicking opens journal line drill-down |
| `carryover_target` | `Char` | `line_code.expr_label` — where to carry this value in next period |

---

### `account.report.external.value` — Stored Manual Values

> [addons/account/models/account_report.py:947](../addons/account/models/account_report.py#L947)

Used by the `external` engine. Each record is one manually entered (or carried-over) value for one expression.

| Field | Type | Purpose |
|---|---|---|
| `value` | `Float` | Numeric value |
| `text_value` | `Char` | Text value (for `string` figure types) |
| `date` | `Date` | Date of this value |
| `target_report_expression_id` | `Many2one → account.report.expression` | Which expression receives this |
| `company_id` | `Many2one → res.company` | Company context |
| `carryover_origin_expression_label` | `Char` | Source expression label (carryover only) |
| `carryover_origin_report_line_id` | `Many2one → account.report.line` | Source line (carryover only) |

---

## The 6 Computation Engines

All engines are dispatched dynamically:

```python
# enterprise/account_reports/models/account_report.py:3852
engine_function_name = f'_compute_formula_batch_with_engine_{formula_engine}'
return getattr(self, engine_function_name)(column_group_options, date_scope, formulas_dict, ...)
```

---

### Engine 1: `domain` — Odoo Domain Filter

> [_compute_formula_batch_with_engine_domain()](../enterprise/account_reports/models/account_report.py#L3934)

Filters `account.move.line` by an Odoo domain, then aggregates the `balance` column.

**Formula:** A Python list — a valid Odoo domain on `account.move.line`.

**Subformulas:**

| Subformula | Result |
|---|---|
| `sum` | Sum of all matching line balances |
| `-sum` | Negated sum — income accounts have credit-normal (negative) balances; negate to show positive revenue |
| `sum_if_pos` | Result only if positive, else 0 |
| `sum_if_neg` | Result only if negative, else 0 |
| `count_rows` | Count of distinct groupby keys — **non-batchable, runs one SQL per formula, avoid on large reports** |

**SQL generated (simplified):**
```sql
SELECT COALESCE(SUM(balance * currency_rate), 0.0) AS sum,
       COUNT(DISTINCT next_groupby_field)           AS count_rows
FROM   account_move_line
JOIN   currency_table ON ...
WHERE  <date_scope_filter>
  AND  <company_filter>
  AND  <journal_filter>
  AND  <domain_filter>
GROUP BY <current_groupby_field>   -- only when line has groupby
```

**Real examples:**
```xml
<!-- P&L Revenue: income accounts have negative balance, negate to show positive -->
<field name="formula" eval="[('account_id.account_type', '=', 'income')]"/>
<field name="subformula">-sum</field>

<!-- Balance Sheet Receivables: filter by type AND exclude non-trade -->
<field name="formula" eval="[('account_id.account_type', '=', 'asset_receivable'), ('account_id.non_trade', '=', False)]"/>
<field name="subformula">sum</field>
```

---

### Engine 2: `tax_tags` — Tax Tag Matching

> [_compute_formula_batch_with_engine_tax_tags()](../enterprise/account_reports/models/account_report.py#L3858)

Matches `account.move.line` records carrying a specific `account.account.tag`. The tag is **auto-created** when the expression is saved — its name equals the formula string.

**Formula:** A tag name string, optionally prefixed with `-` to negate.

**No subformulas** for this engine.

**When to use:** Tax returns. Each box on a VAT declaration maps to a tag. Configure a tax's repartition lines with that tag → every journal entry from that tax carries the tag → the report sums those balances.

```xml
<field name="engine">tax_tags</field>
<field name="formula">base_20</field>
```

**Tag creation:** When `engine = 'tax_tags'` is saved, `_create_tax_tags()` creates an `account.account.tag` with `applicability = 'taxes'` scoped to the report's country.
Source: [account_report.py:695](../addons/account/models/account_report.py#L695)

---

### Engine 3: `aggregation` — Formula Over Other Lines

> Handled in [_compute_expression_totals_for_single_column_group()](../enterprise/account_reports/models/account_report.py#L3378)

Combines values of other report lines using arithmetic. References lines by their `code` field. **Runs last** — after all other engines.

**Formula syntax:**
```
CA.balance + FA.balance + PNCA.balance    ← sum line codes
REV.balance - COS.balance                 ← subtraction
sum_children                              ← sum all direct child lines
```

**Subformulas for aggregation:**

| Subformula | Effect |
|---|---|
| `if_above(CUR 0)` | Show only if above 0 |
| `if_below(CUR 0)` | Show only if below 0 |
| `force_between(CUR -X, CUR X)` | Clamp to range |
| `cross_report(xml.id)` | Reference a line from a **different** report |

`cross_report` is used extensively in the Executive Summary to pull values from P&L without duplicating logic.

**Real example — Balance Sheet total assets:**
```xml
<field name="code">TA</field>
<field name="aggregation_formula">CA.balance + FA.balance + PNCA.balance</field>
```

**Key rule:** Aggregation lines do NOT run SQL. They wait for all referenced lines to complete. Circular references raise a computation error.

---

### Engine 4: `account_codes` — Account Code Prefix Matching

> [_compute_formula_batch_with_engine_account_codes()](../enterprise/account_reports/models/account_report.py#L4111)

Sums balances of all accounts whose **code starts with** a given prefix. Useful for COA-based reports organized by code ranges (common in European localizations).

**Formula syntax:**

| Syntax | Meaning |
|---|---|
| `400` | Sum all accounts starting with `400` |
| `400 - 500` | 400-range minus 500-range |
| `104\(1041)` | All 104* accounts except those starting with 1041 |
| `123D` | Balance of 123* accounts, **only if positive** (Debit side) |
| `416C` | Balance of 416* accounts, **only if negative** (Credit side) |
| `tag(xmlid)` | Accounts carrying that `account.account.tag` |
| `+` / `-` | Add or subtract prefix ranges |

**How it works internally:**
1. Loads all accounts for the company sorted by code
2. Uses `bisect_left` for fast binary prefix matching
3. Runs one aggregated SQL query to sum balances

---

### Engine 5: `external` — Manually Entered Value

> [_compute_formula_batch_with_engine_external()](../enterprise/account_reports/models/account_report.py#L4289)

The value is NOT computed from journal lines. It is either entered by the user directly in the report cell, or it is a value carried forward from a previous period.

**Formula values:**

| Formula | Meaning |
|---|---|
| `most_recent` | The most recently saved `account.report.external.value` for this expression |
| `sum` | Sum of all saved values within the date range |

**Subformula `editable`:** Marks the cell as user-editable in the UI (pencil icon appears).

**When to use:**
- Opening balance overrides
- Statistical data inputs
- Tax return carryover amounts (amounts from previous period)

---

### Engine 6: `custom` — Python Method

> [_compute_formula_batch_with_engine_custom()](../enterprise/account_reports/models/account_report.py#L4401)

Calls a Python method on the report's `custom_handler_model`. The formula IS the method name. The report must have `custom_handler_model_id` pointing to a model that inherits `account.report.custom.handler`.

**Formula:** Method name on the handler model.

**Real examples:**

| Report | Formula | What it does |
|---|---|---|
| General Ledger | `_report_custom_engine_general_ledger` | Running balance — each line = previous balance + debit − credit |
| Trial Balance | `_report_custom_engine_trial_balance` | Debit/credit totals per account + opening balance |
| Executive Summary | `_report_custom_engine_executive_summary_ndays` | Number of days in selected period |

**Use when:** Standard engines can't express the computation — running totals, special period logic, opening balance accumulation.

> If `engine = 'custom'` but `custom_handler_model_id` is not set, Odoo raises `AttributeError` — it calls `getattr(self, formula_name)` on the base model which doesn't have that method.

---

## Date Scope

Every expression has a `date_scope` controlling which `account.move.line` records are included.

| `date_scope` | Meaning | Used for |
|---|---|---|
| `strict_range` | Only lines within `date_from`..`date_to` | P&L, Tax Report — period-specific |
| `from_beginning` | All lines from beginning of time up to `date_to` | Balance Sheet — balances carry forever |
| `from_fiscalyear` | Lines from fiscal year start to `date_to` | YTD reports |
| `to_beginning_of_fiscalyear` | Lines before fiscal year start | Opening balance at year start |
| `to_beginning_of_period` | Lines before `date_from` | Running/opening balance of the current period |
| `previous_return_period` | Lines from the previous tax return period | Carryover in tax reports |

`_get_options_date_domain()` translates `date_scope` + current options into a SQL WHERE clause.
Source: [account_report.py:915](../enterprise/account_reports/models/account_report.py#L915)

---

## Rendering Pipeline: `_get_lines()` to Screen

Full call chain for one report render:

> Entry: [account_report.py:2662](../enterprise/account_reports/models/account_report.py#L2662)

| Step | Method | What it does |
|---|---|---|
| 1 | `_get_lines()` | Entry point — flush DB, init currency table, call compute |
| 2 | `_compute_expression_totals_for_each_column_group()` | For each column group (comparison period), compute all expression values |
| 3 | `_compute_expression_totals_for_single_column_group()` | Groups expressions by engine + date_scope, batch-computes, resolves aggregations last |
| 4 | `_compute_formula_batch()` | Dispatches to the correct engine method (dynamic `getattr`) |
| 5 | `_get_dynamic_lines()` | Calls `_dynamic_lines_generator()` on the custom handler (for dynamic-only reports like Cash Flow) |
| 6 | `_get_static_line_dict()` | Builds the line dict for each static line |
| 7 | `_build_static_line_columns()` | For each column, looks up computed expression value from step 3 |
| 8 | `_build_column_dict()` | Formats one column value — handles carryover, info popup, edit popup |
| 9 | `_create_hierarchy()` | Re-aggregates account lines into `account.group` structure (if hierarchy enabled) |
| 10 | `_add_totals_below_sections()` | Inserts section total rows |
| 11 | `_fully_unfold_lines_if_needed()` | Expands groupby lines recursively (for "unfold all") |
| 12 | `_custom_line_postprocessor()` | Custom handler hook — last chance to modify the line list |
| 13 | `_customize_warnings()` | Custom handler hook — add report-specific warnings |
| 14 | `_format_column_values()` | Format all numeric values for display (monetary, percentage, etc.) |

**Expression batching:**

All expressions with the same `(engine, date_scope, current_groupby, next_groupby)` are computed in a single SQL call. This is the primary performance optimization — one call per engine/scope combination per column group, not one call per expression.

---

## Options System

`get_options(previous_options)` builds the complete options dict used for every render, export, and drill-down.

Source: [account_report.py:2056](../enterprise/account_reports/models/account_report.py#L2056)

### Rerouting to Variants

The initialization sequence is split at `_init_options_report_id` (sequence 17). After that initializer runs, if the resolved `report_id` differs from `self.id` (because a localized variant was found), `get_options` is called again on the variant report. This is how French companies automatically see the French TVA report instead of the generic tax report.

### `_init_options_*` Execution Order

| Sequence | Method | Purpose |
|---|---|---|
| 10 | `_init_options_companies` | Select companies to report on |
| 15 | `_init_options_variants` | Select report variant |
| 16 | `_init_options_sections` | Select report sections (composite reports) |
| 17 | `_init_options_report_id` | Set the actual report — variant reroute happens here |
| 29 | `_init_options_return_periodicity` | Tax return period (monthly / quarterly) |
| 30 | `_init_options_date` | Date range from filter selection |
| 40 | `_init_options_horizontal_groups` | Horizontal groupby columns |
| 50 | `_init_options_comparison` | Build comparison columns |
| 60 | `_init_options_export_mode` | Export mode flag |
| 70 | `_init_options_integer_rounding` | Rounding method |
| 80 | `_init_options_journals` | Journal filter |
| 200 | (all others) | Analytic, partner, budgets, buttons, hide_0, etc. |
| 990 | `_init_options_column_headers` | Column header labels |
| 1000 | `_init_options_columns` | Column structure — depends on dates and comparison |
| 1010 | `_init_options_column_percent_comparison` | Growth/budget comparison columns |
| 1020 | `_init_options_order_column` | Sort column |
| 1030 | `_init_options_hierarchy` | Hierarchy expand/collapse state |
| 1050 | `_init_options_custom` | Custom handler options |
| 1055 | `_init_options_currency_table` | Currency conversion JOIN — must be after columns |
| 1500 | `_init_options_filters` | Final filter aggregation |

### Key `options` keys

```python
options = {
    'report_id': 42,
    'date': {'date_from': '2025-01-01', 'date_to': '2025-12-31', 'filter': 'this_year'},
    'comparison': {'periods': [...], 'number_period': 1, 'filter': 'previous_year'},
    'column_groups': {
        'column_group_0': {'forced_options': {'date': {...}}, 'forced_domain': [], ...},
        'column_group_1': {'forced_options': {'date': {...}}, ...},
    },
    'journals': [{'id': 1, 'name': 'Sales', 'selected': True}, ...],
    'companies': [{'id': 1, 'name': 'My Company'}],
    'hierarchy': True,
    'unfold_all': False,
    'unfolded_lines': [...],
    'buttons': [...],
}
```

Each entry in `column_groups` represents one column in the report (main period + each comparison period). The engine computes each expression once per column group.

---

## Custom Handler Interface

A custom handler is an `AbstractModel` inheriting `account.report.custom.handler` linked to a report via `custom_handler_model_id`.

Source: [account_report.py:7857](../enterprise/account_reports/models/account_report.py#L7857)

### All Overridable Methods

| Method | Signature | When to use |
|---|---|---|
| `_dynamic_lines_generator()` | `(report, options, all_column_groups_expression_totals, warnings=None)` | Generate dynamic lines not defined in the report's `line_ids` (e.g., one line per journal entry) |
| `_caret_options_initializer()` | `()` | Define right-click context menu items per model type |
| `_custom_options_initializer()` | `(report, options, previous_options)` | Add report-specific filters or option sections |
| `_custom_line_postprocessor()` | `(report, options, lines)` | Modify the rendered line list before display — inject rows, rename, reorder |
| `_custom_groupby_line_completer()` | `(report, options, line_dict, current_groupby)` | Customize a groupby-expanded line's data |
| `_custom_unfold_all_batch_data_generator()` | `(report, options, lines_to_expand_by_function)` | Precompute data for "unfold all" to avoid N+1 queries |
| `_get_custom_groupby_map()` | `()` | Define custom groupby fields beyond `account.move.line` fields |
| `_customize_warnings()` | `(report, options, all_column_groups_expression_totals, warnings)` | Add report-specific warning messages |

**`_dynamic_lines_generator()` return format:**
```python
return [(sequence, line_dict), ...]
# sequence: integer for ordering relative to static lines
# line_dict: same structure as lines returned by _get_lines()
```

**`_caret_options_initializer()` return format:**
```python
return {
    'account.account': [
        {'name': _("General Ledger"), 'action': 'caret_option_open_general_ledger'},
    ],
    'account.move.line': [
        {'name': _("View Journal Entry"), 'action': 'caret_option_open_record_form', 'action_param': 'move_id'},
    ],
}
# key: model name on the line's 'caret_options' key
# action: method name to call on the report/handler when clicked
```

---

## Caret Options (Right-Click Menu)

Caret options are context menu items that appear when clicking the arrow next to a line value.

**Default options** (all reports unless overridden):
Source: [account_report.py:2493](../enterprise/account_reports/models/account_report.py#L2493)

```python
{
    'account.account':      [{'name': "General Ledger", 'action': 'caret_option_open_general_ledger'}],
    'account.move':         [{'name': "View Journal Entry", 'action': 'caret_option_open_record_form'}],
    'account.move.line':    [{'name': "View Journal Entry", 'action': 'caret_option_open_record_form', 'action_param': 'move_id'}],
    'account.payment':      [{'name': "View Payment", 'action': 'caret_option_open_record_form', 'action_param': 'payment_id'}],
    'res.partner':          [{'name': "View Partner", 'action': 'caret_option_open_record_form'}],
}
```

**Trial Balance** adds "Journal Items" alongside "General Ledger":
Source: [account_trial_balance_report.py:188](../enterprise/account_reports/models/account_trial_balance_report.py#L188)

**General Ledger** overrides for its custom `id_with_accumulated_balance` groupby key:
Source: [account_general_ledger.py:35](../enterprise/account_reports/models/account_general_ledger.py#L35)

**How dispatch works:**
1. Each rendered line carries a `caret_options` key identifying which model it represents
2. `_caret_options_initializer()` maps model → actions
3. When user clicks, `dispatch_report_action()` calls the action method on the handler

---

## Carryover Logic (Tax Reports)

Carryover allows an expression value from one period to be automatically applied to a target expression in the next period (e.g., tax credit from Q3 carried to Q4).

**Naming convention:**
- Source expression label must start with `_carryover_` (e.g., `_carryover_credit`)
- Target expression label must start with `_applied_carryover_` (e.g., `_applied_carryover_credit`)

**`carryover_target` field:**
```python
# addons/account/models/account_report.py:620
carryover_target = fields.Char(
    string="Carry Over To",
    help="Formula in form line_code.expression_label. Target of carryover if different from parent line."
)
```

If `carryover_target` is not set, the framework auto-resolves the target by stripping the `_carryover_` prefix and finding a matching `_applied_carryover_*` expression on the same line.
Source: [account_report.py:911](../addons/account/models/account_report.py#L911)

**Storage:** Carryover values are written as `account.report.external.value` records with `carryover_origin_expression_label` and `carryover_origin_report_line_id` set.

**Generation:** `_generate_carryover_external_values()` is called when a tax period is closed. It computes `_carryover_*` expressions and creates the corresponding `account.report.external.value` records targeting `_applied_carryover_*` expressions on the next period.

---

## Groupby: Expanding Lines to Sublines

When `account.report.line.groupby` is set, the engine splits results by that field.

**How it works:**
1. Engine receives `current_groupby = 'account_id'`
2. SQL adds `GROUP BY account_move_line.account_id`
3. Returns `[(grouping_key, {result_dict}), ...]` instead of a single dict
4. Each grouping key becomes a new child row in the UI

**Multi-level groupby:** `groupby = 'partner_id, account_id'`
- First render: grouped by `partner_id` (collapsed rows)
- Expand a partner: triggers new API call with `current_groupby = 'account_id'`

**`foldable = True`:** Line starts collapsed. User click triggers new API call with `current_groupby` set.

---

## Hierarchy Filter (Account Groups)

When `filter_hierarchy = 'by_default'` or `'optional'` and enabled:
- Account-level lines are re-aggregated into `account.group` structure
- Uses `account.group.code_prefix_start/end` ranges
- Each group row shows sum of accounts within its range

Distinct from the `account.root` virtual model used in the COA list view — those are different grouping mechanisms.

---

## Report Variants and Localization

`root_report_id` connects generic reports to localized versions.

```
account.report (root)
    name                = "Generic Tax Report"
    root_report_id      = None
    country_id          = None

account.report (variant — France)
    name                = "Déclaration TVA CA3"
    root_report_id      → "Generic Tax Report"
    country_id          = France
    availability_condition = 'country'
```

When a French company opens the Tax Report, `get_options()` auto-redirects to the French variant.
Source: [account_report.py:2078](../enterprise/account_reports/models/account_report.py#L2078)

---

## Composite Reports (Sections)

A composite report contains multiple sub-reports accessible from one menu entry.

```
Annual Statements (composite)
    section_report_ids:
        → Balance Sheet
        → Profit and Loss
        → Trial Balance
```

Composite reports are auto-generated for localized report sets that set `use_sections = True`.
Source: [account_report.py:157](../addons/account/models/account_report.py#L157)

---

## Standard Reports — Deep Dive

### Balance Sheet

> [enterprise/account_reports/data/balance_sheet.xml](../enterprise/account_reports/data/balance_sheet.xml)
> Handler: `account.balance.sheet.report.handler`

- **Engine:** `domain` for leaf lines, `aggregation` for totals
- **`date_scope`:** `from_beginning` — assets/liabilities accumulate their full history
- **Default date filter:** `today` — point-in-time snapshot, not a range
- `filter_date_range = False` — single date only, no from/to
- Layout: horizontal split — Assets left, Liabilities + Equity right

**Structure:**
```
ASSETS  (TA = aggregation: CA + FA + PNCA)
  ├── Current Assets  (CA = aggregation: BA + REC + CAS + PRE)
  │     ├── Bank and Cash Accounts  → domain: account_type = asset_cash
  │     ├── Receivables             → domain: account_type = asset_receivable AND non_trade = False
  │     ├── Current Assets          → domain: asset_current OR (asset_receivable AND non_trade)
  │     └── Prepayments             → domain: account_type = asset_prepayments
  ├── Plus Fixed Assets             → domain: account_type = asset_fixed
  └── Plus Non-current Assets       → domain: account_type = asset_non_current

LIABILITIES  (L = aggregation: CL + NL)
  ├── Current Liabilities
  └── Non-current Liabilities

EQUITY  (includes "Undistributed Profits/Losses" — see gotchas)
```

**`equity_unaffected` gotcha:** The Balance Sheet does NOT have a `domain` line for `equity_unaffected`. Instead, `AccountBalanceSheetReportHandler` computes "Undistributed Profits/Losses" as the residual: `Assets − Liabilities − explicit Equity`. If the `equity_unaffected` account type is wrong, the Balance Sheet won't balance.

---

### Profit and Loss (P&L)

> [enterprise/account_reports/data/profit_and_loss.xml](../enterprise/account_reports/data/profit_and_loss.xml)

- **Engine:** `domain` for leaf lines, `aggregation` for subtotals
- **`date_scope`:** `strict_range` — only the selected period
- **Default date filter:** `this_year`
- `filter_date_range = True`
- `filter_budgets = True` — budget comparison available

**`-sum` on income:** Income accounts have **credit-normal balances** (negative by convention). `subformula = '-sum'` negates them so revenue displays as a positive number. Using `sum` on income would show negative revenue.

**Structure:**
```
Revenue              → domain: account_type = income,              subformula: -sum
Cost of Revenue      → domain: account_type = expense_direct_cost, subformula: sum
Gross Profit         → aggregation: REV.balance - COS.balance
  Operating Expenses → domain: account_type = expense,             subformula: sum
Operating Income     → aggregation: GRP.balance - OP.balance
  Other Income       → domain: account_type = income_other,        subformula: -sum
  Other Expenses     → domain: account_type = expense_other,       subformula: sum
Net Profit           → aggregation: OI.balance + OTI.balance - OTE.balance
```

---

### Trial Balance

> [enterprise/account_reports/data/trial_balance.xml](../enterprise/account_reports/data/trial_balance.xml)
> Handler: [account_trial_balance_report.py](../enterprise/account_reports/models/account_trial_balance_report.py)

**Purpose:** Verify mathematical integrity of the ledger. One row per account. No individual transactions.

**Columns:**

| Column | Content | `date_scope` |
|---|---|---|
| Initial Balance | Net balance of all lines **before** `date_from` | `to_beginning_of_period` |
| Debit | All debits **within** the period | `strict_range` |
| Credit | All credits **within** the period | `strict_range` |
| End Balance | Initial Balance + period debit − period credit | Computed in postprocessor, no SQL |

**Balance sheet vs P&L accounts (income/expense reset):**

Balance sheet accounts (`include_initial_balance = True`) show all history in Initial Balance.
P&L accounts (`include_initial_balance = False`) only include lines from **fiscal year start** — they reset each year.

Enforced by extra domain in `_report_custom_engine_trial_balance()`:
```python
# account_trial_balance_report.py:231
extra_domain = [
    '|',
    ('account_id.include_initial_balance', '=', True),
    ('date', '>=', fiscalyear_start),
]
```

**Undistributed Profits/Losses row:**
A special row for `equity_unaffected` representing the net of all un-closed P&L lines. Computed in `_custom_line_postprocessor()` and injected as a total.
Source: [account_trial_balance_report.py:333](../enterprise/account_reports/models/account_trial_balance_report.py#L333)

**Caret drill-down:** Each account row has "General Ledger" and "Journal Items" in the caret menu.
Source: [account_trial_balance_report.py:188](../enterprise/account_reports/models/account_trial_balance_report.py#L188)

`filter_hierarchy = by_default` — accounts roll up into `account.group` by default.

---

### General Ledger

> [enterprise/account_reports/data/general_ledger.xml](../enterprise/account_reports/data/general_ledger.xml)
> Handler: [account_general_ledger.py](../enterprise/account_reports/models/account_general_ledger.py)

**Purpose:** Full transaction history for every account. Every posted journal line shown individually with a running balance.

**Columns:**

| Column | Content |
|---|---|
| Date | Journal entry date |
| Partner | Partner on the line |
| Currency | Foreign currency amount (if multi-currency) |
| Debit | Debit amount |
| Credit | Credit amount |
| Balance | **Running balance** = previous balance + debit − credit |

**Groups by:** `account_id` → `id_with_accumulated_balance`

- Top level: one collapsed row per account
- Expand: every `account.move.line` for that account in date order
- Each individual line carries the cumulative balance to that point

**Running balance mechanism:**
```python
# account_general_ledger.py:316
accumulated_balance_by_colgroup[col_group_key] += line_balance
```
The `progress` dict is threaded between line batches to carry the running total.

**Opening balance line:**
First row under each account is "Initial Balance" — `to_beginning_of_period` scope. All subsequent lines count from there.

**Pagination:** `load_more_limit = 80` — accounts with >80 lines show a "Load More" button.

**Trial Balance vs General Ledger:**

| | Trial Balance | General Ledger |
|---|---|---|
| Granularity | One row per account | One row per journal line |
| Shows transactions | No — totals only | Yes — every line |
| Balance column | Initial/End balance | Running (cumulative) balance |
| Use case | Verify totals, period-end close | Investigate what happened |
| Performance | Fast — aggregate SQL | Slow on large datasets — paginated |

---

### Aged Receivable / Aged Payable

> [enterprise/account_reports/data/aged_partner_balance.xml](../enterprise/account_reports/data/aged_partner_balance.xml)
> Handler: [account_aged_partner_balance.py](../enterprise/account_reports/models/account_aged_partner_balance.py)

**Purpose:** Show which invoices (AR) or bills (AP) are still outstanding and how long they have been overdue.

**Key difference from other reports:** Only **open items** appear. Fully reconciled invoices are excluded.

**How "open" is determined:**
```sql
-- Residual = original balance minus already-matched amounts
balance - COALESCE(part_debit.amount, 0) + COALESCE(part_credit.amount, 0) AS residual

HAVING
    ROUND(SUM(residual_debit), precision) != 0
    OR ROUND(SUM(residual_credit), precision) != 0
```
Partial reconciliations are only counted if `part.max_date <= date_to` — this makes the report historically accurate for any past date.
Source: [account_aged_partner_balance.py:155](../enterprise/account_reports/models/account_aged_partner_balance.py#L155)

**Aging buckets** (default: 6 buckets, 30-day interval, based on `date_maturity`):

| Column | What it contains |
|---|---|
| `period0` | Not yet due — `date_maturity >= date_to` |
| `period1` | 1–30 days overdue |
| `period2` | 31–60 days overdue |
| `period3` | 61–90 days overdue |
| `period4` | 91–120 days overdue |
| `period5` | 121+ days overdue ("Older") |

Interval is user-configurable (`aging_interval`, default 30).
Source: [account_aged_partner_balance.py:45](../enterprise/account_reports/models/account_aged_partner_balance.py#L45)

**Aging date basis:**

| `aging_based_on` | Date used for bucket assignment |
|---|---|
| `base_on_maturity_date` (default) | `date_maturity` — payment due date |
| `base_on_invoice_date` | `invoice_date` — original invoice date |

**UI structure:**
```
Partner A             0–30   31–60   61–90   91–120   Older   Total
  INV/2025/0001               1,500                           1,500
  INV/2025/0002                               800               800
```

**Trust indicator:** Each partner row gets `trust` field (`good`/`normal`/`bad`) shown as a colored dot.
Source: [account_aged_partner_balance.py:65](../enterprise/account_reports/models/account_aged_partner_balance.py#L65)

**AR vs AP — the only differences:**

| | Aged Receivable | Aged Payable |
|---|---|---|
| Account type | `asset_receivable` | `liability_payable` |
| Sign | `+1` (debit-normal) | `−1` (credit-normal, negated for positive display) |
| Audit journal filter | Excludes `purchase` journals | Excludes `sale` journals |

Both inherit `AccountAgedPartnerBalanceReportHandler` and share `_aged_partner_report_custom_engine_common()`.
Source: [account_aged_partner_balance.py:83](../enterprise/account_reports/models/account_aged_partner_balance.py#L83)

---

### Cash Flow Statement

> [enterprise/account_reports/data/cash_flow_report.xml](../enterprise/account_reports/data/cash_flow_report.xml)
> Handler: [account_cash_flow_report.py](../enterprise/account_reports/models/account_cash_flow_report.py)

**Purpose:** Show how cash moved through the business — operating, investing, and financing activities.

**Method:** Direct method (tracks actual cash movements through bank/cash accounts).

**Sections:**

| Section | Account tags used |
|---|---|
| Operating activities | `account.account_tag_operating` |
| Investing activities | `account.account_tag_investing` |
| Financing activities | `account.account_tag_financing` |

Account tags are pulled via `_get_tags_ids()`:
```python
# account_cash_flow_report.py:131
'operating': self.env.ref('account.account_tag_operating').id,
'investing':  self.env.ref('account.account_tag_investing').id,
'financing':  self.env.ref('account.account_tag_financing').id,
```

**Computation flow** (in `_dynamic_lines_generator()`):
1. **Opening Balance** — `_compute_liquidity_balance(report, options, payment_account_ids, 'to_beginning_of_period')`
2. **Closing Balance** — same method with `'strict_range'` scope
3. **Liquidity Moves** — `_get_liquidity_moves()` — moves where at least one line touches a bank/cash account
4. **Reconciled Moves** — `_get_reconciled_moves()` — moves reconciled against bank/cash lines
5. **Dispatch** — `_dispatch_aml_data()` categorizes each move by account type and tag into the three sections
6. **Parent totals** — maintained recursively by `_report_update_parent()`

Because all lines are generated dynamically, this report uses `_dynamic_lines_generator()` exclusively — there are no static `account.report.line` rows with expressions.

---

### Tax Report (Generic)

> [enterprise/account_reports/data/generic_tax_report.xml](../enterprise/account_reports/data/generic_tax_report.xml)

- **Engine:** `tax_tags` for localized lines
- Root report: `account.generic_tax_report`
- Each `l10n_*` module creates a **variant** pointing to this root with country-specific tag names
- Before a localization is installed: shows all taxes by type
- After `l10n_xx` install: localized variant appears with actual tax return boxes

---

### Partner Ledger

> [enterprise/account_reports/data/partner_ledger.xml](../enterprise/account_reports/data/partner_ledger.xml)

- Similar to General Ledger but grouped by partner
- Shows receivable/payable lines per partner
- `filter_account_type` switches between customer (AR) / vendor (AP) view

---

### Executive Summary

> [enterprise/account_reports/data/executive_summary.xml](../enterprise/account_reports/data/executive_summary.xml)
> Handler: [executive_summary_report.py](../enterprise/account_reports/models/executive_summary_report.py)

**Purpose:** KPI overview for management — key ratios and financial health at a glance.

**Five sections:**

| Section | KPIs | Engine used |
|---|---|---|
| Cash | Cash received, Cash spent, Cash surplus, Closing bank balance | `domain`, `aggregation` |
| Profitability | Revenue, Cost of Revenue, Gross Profit, Expenses, Net Profit | `aggregation` with `cross_report` from P&L |
| Balance Sheet | Receivables, Payables, Net assets | `domain`, `aggregation` |
| Performance | Gross profit margin %, Net profit margin %, Return on investment % | `aggregation` (arithmetic on other expressions) |
| Position | Average debtors days, Average creditors days, Short-term cash forecast, Current assets/liabilities ratio | `aggregation`, `custom` |

**Notable pattern — `cross_report`:**
Profitability section pulls values directly from P&L without redefining the domain queries:
```
REV.balance → aggregation with cross_report(account.profit_and_loss_xml_id)
```

**Custom engine for NDays:**
```python
# executive_summary_report.py:11
# _report_custom_engine_executive_summary_ndays()
# Returns the number of days in the selected period — used for "average days" ratio denominators
```

---

## Currency Handling

Reports convert all balances to **company currency** via a currency rate table.

`_init_options_currency_table()` builds a JOIN applying the exchange rate from the transaction date (or report date for balance sheet items).
Source: [account_report.py:1389](../enterprise/account_reports/models/account_report.py#L1389)

SQL balance computation:
```sql
account_move_line.balance * currency_table.rate
```

---

## Audit Drill-Down

`auditable = True` on an expression means clicking the cell value opens a filtered list of `account.move.line` records.

- `account_codes` engine: collects `account_ids` for the matched accounts
- `domain` engine: uses the domain directly
- `aggregation` engine: traces back to source lines
- `external` engine: shows the `account.report.external.value` records

All standard engines are auditable.

---

## Export

| Format | How |
|---|---|
| PDF | QWeb template → Chromium headless render |
| XLSX | `xlsxwriter` library |
| EDI (XML, XBRL, SAFT) | Tax returns exported via `account.return.type` — localization-specific |

Export buttons are added to `options['buttons']` in `_init_options_buttons`.

---

## UI Entry Points

| Report | Menu path | Purpose |
|---|---|---|
| Balance Sheet | Accounting → Reporting → Balance Sheet | Point-in-time assets/liabilities |
| Profit and Loss | Accounting → Reporting → Profit and Loss | Revenue/expense for a period |
| Trial Balance | Accounting → Reporting → Trial Balance | Debit/credit totals per account |
| General Ledger | Accounting → Reporting → General Ledger | Every journal line with running balance |
| Partner Ledger | Accounting → Reporting → Partner Ledger | AR/AP lines by partner |
| Aged Receivable | Accounting → Reporting → Aged Receivable | Overdue customer invoices in buckets |
| Aged Payable | Accounting → Reporting → Aged Payable | Overdue vendor bills in buckets |
| Tax Report | Accounting → Reporting → Tax Report | VAT/tax return boxes |
| Cash Flow | Accounting → Reporting → Cash Flow Statement | Operating/investing/financing cash |
| Executive Summary | Accounting → Reporting → Executive Summary | KPI overview with key ratios |
| Custom | Accounting → Reporting → (any custom) | Reports created via Accounting → Configuration → Financial Reports |

---

## Edge Cases and Gotchas

**`-sum` on income accounts**
Income accounts have credit-normal balances (negative by convention). `subformula = '-sum'` negates them for positive display. Using `sum` on income shows a negative number.
Source: [profit_and_loss.xml:32](../enterprise/account_reports/data/profit_and_loss.xml#L32)

**Balance Sheet uses `from_beginning`**
`date_scope` on Balance Sheet leaf expressions is `from_beginning`, not `strict_range`. It reads the full account history. Changing to `strict_range` would show only the period's movement, not the cumulative balance — Balance Sheet would be wrong.

**Aggregation runs last**
An `aggregation` expression cannot reference a line whose expression is still pending. The framework computes all non-aggregation lines first. Circular references raise a computation error.

**`count_rows` non-batchable**
`count_rows` subformula on `domain` engine is never batched — one SQL call per formula per line. Avoid on reports with many lines.

**Variant reroute is silent**
If a variant matches the current company's country, `get_options()` redirects without any visible indication. The UI shows the variant, not the root. Debugging: check `options['report_id']` vs `self.id`.
Source: [account_report.py:2078](../enterprise/account_reports/models/account_report.py#L2078)

**`equity_unaffected` on Balance Sheet**
Balance Sheet does NOT have a `domain` line for `equity_unaffected`. It's computed as the residual by `AccountBalanceSheetReportHandler`. Wrong account type on `equity_unaffected` breaks balance sheet equality.

**`custom` engine without handler**
If `engine = 'custom'` but `custom_handler_model_id` is not set, Odoo raises `AttributeError` — `getattr(self, formula_name)` fails on the base model.

**Carryover label convention**
`carryover_target` only works if the source expression label starts with `_carryover_` and the target label starts with `_applied_carryover_`. Naming mismatch raises an error silently during period close.

**Cash Flow is fully dynamic**
The Cash Flow Statement has no static `account.report.line` rows with expressions. All lines come from `_dynamic_lines_generator()`. You cannot add a line by adding an `account.report.line` record — you must modify the handler.

---

## Related Docs

- [INDEX.md](INDEX.md)
- [accounting_coa.md](accounting_coa.md) — account types determine which domain expressions match

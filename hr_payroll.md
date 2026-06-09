# Payroll

> **Module:** `hr_payroll` | **Path:** [`enterprise/hr_payroll/`](../enterprise/hr_payroll/)
> **Odoo Apps category:** HR / Payroll

## What It Does

Computes employee payslips by running salary rules against an employee's contract (version), worked days, and ad-hoc input values. Salary rules are organized into structures; each rule is a formula that outputs an amount → the sum of all rule amounts becomes the payslip lines (BASIC, GROSS, NET, deductions, etc.).

---

## Dependencies

### Requires (must be installed)
| Module | Why |
|---|---|
| `hr_work_entry` | provides work entry types / worked day records used in rule computations |
| `hr_contract` | provides `hr.version` (employee record / contract) with wage, job, schedule |

### Optional Integrations
| Module | What it enables |
|---|---|
| `hr_payroll_account` | posts payslip lines as journal entries |
| `hr_payroll_holidays` | bridges time-off to work entries on payslips |
| `hr_payroll_attendance` | uses attendance records as worked days input |
| `hr_payroll_sale_commission` | auto-creates commission inputs from sales |

---

## Business Flow

```
Draft payslip created  →  Worked days computed  →  Salary rules evaluated  →  Validated  →  Paid
        ↓                         ↓                          ↓
   Employee + period       one line per work-entry     one payslip line
   version resolved        type (WORK100, LEAVE…)      per salary rule
                                                        using inputs[]
                                                        and worked_days[]
```

### States
| State | Meaning | Can Transition To |
|---|---|---|
| `draft` | editable, not confirmed | `validated`, `cancel` |
| `validated` | rules computed, locked | `paid`, `cancel` |
| `paid` | marked paid (status flag — see below, not necessarily a registered payment) | — |
| `cancel` | voided | — |

---

## Getting to "Paid" — does confirming a payslip create a payment?

**No.** Confirmation, accounting, and "paid" are three separate steps, and `paid` is a status flag — not proof that money moved.

| Step | Method | What it does | Money moved? |
|---|---|---|---|
| Confirm / validate | `action_validate` → `action_payslip_done` ([hr_payslip.py:586](../enterprise/hr_payroll/models/hr_payslip.py#L586)) | `draft → validated`, sets `done_date` | No |
| Post accounting entry (only with `hr_payroll_account`) | `_action_create_account_move` ([hr_payslip.py:54](../enterprise/hr_payroll_account/models/hr_payslip.py#L54)) | Creates the salary **journal entry** `account.move` (Dr expense / Cr salary payable), stored on `move_id` | No — journal entry only |
| Register payment | `action_register_payment` ([hr_payslip.py:277](../enterprise/hr_payroll_account/models/hr_payslip.py#L277)) | Opens the standard `account.payment.register` wizard on the payable line → creates the real `account.payment` and reconciles | **Yes** |
| Mark as paid | `action_payslip_paid` ([hr_payslip.py:632](../enterprise/hr_payroll/models/hr_payslip.py#L632)) | `→ paid`, sets `paid_date`, reconciles salary attachments | No — status flag |

- The `paid` boolean is labelled **"Made Payment Order?"** ([hr_payslip.py:108](../enterprise/hr_payroll/models/hr_payslip.py#L108)) — independent of `state`.
- Out of the box the two are decoupled: you can flag a payslip paid with no payment, or register a payment without flagging it. **No automatic bank payment is created on confirmation.**
- Actual money out is plain accounting — an `account.payment` against the salary journal entry, the same mechanism used to pay a vendor bill.

### Relation to the Basis Bank salary integration
The `gec_basis_bank_integration` module does **not** create salary payments. Salaries are paid the standard way described above — Register Payment on the Basis Bank journal, which reconciles the payable and marks the payslip `paid`. The module's only job is to **send** those resulting `account.payment` records to the bank and confirm them from the statement. So all payroll accounting and `paid` status stay 100% Odoo-standard; the bank module is a pure sender/confirmer.

> Earlier versions of the module had a wizard that created its own payments directly from payslip data (bypassing reconciliation). That path was removed because it duplicated payments and left the salary payable unreconciled. The module's salary XLSX wizard remains, but only for ad-hoc non-payroll IBAN lists (it creates standalone payments, not tied to payslips).

---

## Key Models

### `hr.payslip` — the payslip record
> [`models/hr_payslip.py`](../enterprise/hr_payroll/models/hr_payslip.py)

| Field | Type | Purpose |
|---|---|---|
| `struct_id` | Many2one → `hr.payroll.structure` | which salary structure (= set of rules) applies |
| `version_id` | Many2one → `hr.version` | the employee's contract/record for this period |
| `worked_days_line_ids` | One2many → `hr.payslip.worked_days` | one line per work-entry type (e.g. WORK100, LEAVE, SICK) |
| `input_line_ids` | One2many → `hr.payslip.input` | Other Inputs tab — ad-hoc amounts passed to rule formulas |
| `line_ids` | One2many → `hr.payslip.line` | computed output lines (BASIC, GROSS, NET, deductions…) |
| `basic_wage` | Monetary | computed from lines with category BASIC |
| `gross_wage` | Monetary | computed from lines with category GROSS |
| `net_wage` | Monetary | computed from lines with category NET |

---

## Salary Inputs — Complete Reference

### What is a Salary Input?

A salary input is a named numeric value you attach to a specific payslip so that salary rule Python formulas can read it. It lives in the **Other Inputs** tab of the payslip form.

Model: [`hr.payslip.input`](../enterprise/hr_payroll/models/hr_payslip_input.py)

| Field | Purpose |
|---|---|
| `input_type_id` | references `hr.payslip.input.type` — gives the code and a human label |
| `code` | shortcut from the type; used as the dict key in salary rule formulas (`inputs['CODE']`) |
| `amount` | the numeric value (money, count, or rate) — this is what rules read |
| `name` | optional description shown on the payslip line when the rule uses `amount_select = 'input'` |

### Input Type (`hr.payslip.input.type`)

Defined once globally (or per-country). Controls availability and semantics.
Source: [`models/hr_payslip_input_type.py`](../enterprise/hr_payroll/models/hr_payslip_input_type.py)

| Field | Purpose |
|---|---|
| `code` | unique identifier used in rule Python code |
| `struct_ids` | restricts availability to specific structures (empty = all structures) |
| `is_quantity` | if True, the input value is a plain count (units, days, meals…), not money — hides currency in UI, blocked from "Other Input" dropdown on rules, payment recording uses payslip line `quantity` instead of `total`. See details below. |
| `available_in_attachments` | if True, this type can be used for Salary Adjustments (recurring deductions) |
| `default_no_end_date` | used when creating Salary Adjustments |

### `is_quantity` — detailed

When `is_quantity = True` on an input type, the value entered is a plain count (units, hours, meals, days) — not a currency amount. This has three concrete effects:

1. **UI hides currency symbol** on the Salary Adjustment form — the field renders as a plain float with no `€`/`$`. Source: [`hr_salary_attachment_views.xml:106`](../enterprise/hr_payroll/views/hr_salary_attachment_views.xml#L106)

2. **Blocked from "Other Input" and condition dropdowns on salary rules** — `condition_other_input_id` and `amount_other_input_id` both have `domain=[('is_quantity', '=', False)]`. You must use Python Code to multiply the count by a price yourself. Source: [`hr_salary_rule.py:45,60`](../enterprise/hr_payroll/models/hr_salary_rule.py#L45)

3. **Payment recording uses `quantity` not `total`** — when the payslip is marked paid and salary attachments are reconciled, for quantity types the engine sums `sl.quantity` from payslip lines instead of `sl.total`. Source: [`hr_payslip.py:473`](../enterprise/hr_payroll/models/hr_payslip.py#L473)

**Example:** Input type `MEAL_VOUCHERS`, `is_quantity=True`. Officer enters `20` (vouchers this month). A Python Code rule computes `result = inputs['MEAL_VOUCHERS'].amount * 8.50` → payslip line `170.00`. The `20` is a count, not money — that's why the "Other Input" dropdown can't use it directly (it has no unit price built in).

---

### Which input types are selectable on a payslip?

The `_allowed_input_type_ids` computed field on `hr.payslip.input` is filtered by `payslip_id.struct_id.input_line_type_ids` — so only types registered on the structure appear in the dropdown.
Source: [`models/hr_payslip_input.py:18`](../enterprise/hr_payroll/models/hr_payslip_input.py#L18)

---

## How Inputs Flow into the Payslip Computation

### Step 1 — `_get_localdict()` builds the computation environment

Called once per payslip when computing lines.
Source: [`models/hr_payslip.py:1010`](../enterprise/hr_payroll/models/hr_payslip.py#L1010)

```python
localdict = {
    'inputs': {line.code: line for line in self.input_line_ids if line.code},
    'worked_days': {line.code: line for line in self.worked_days_line_ids if line.code},
    'version': self.version_id,   # contract / employee record
    'employee': self.employee_id,
    'payslip': self,
    'categories': DefaultDictPayroll(lambda: 0),   # running category totals
    'result_rules': ...,                            # running rule totals
    ...
}
```

`inputs` is a plain Python dict: `{'COMMISSION': <hr.payslip.input record>, 'LOAN': <...>}`.

### Step 2 — salary rules read from `localdict['inputs']`

Each rule has **two independent settings** that work together: the **Condition** (does the rule run?) and the **Amount** (what does it produce?). For input-driven rules both must be set.

The Odoo default pattern for every input-based rule ([hr_salary_rule_data.xml:42–48](../enterprise/hr_payroll/data/hr_salary_rule_data.xml#L42)):

```
Condition (Python):  result = 'DEDUCTION' in inputs       ← skip the rule if input absent
Amount (Python):     result = -inputs['DEDUCTION'].amount  ← use the input's amount
                     result_name = inputs['DEDUCTION'].name ← copy name onto payslip line
```

**Without the condition check**, `inputs['DEDUCTION']` raises `KeyError` when no input is present. Both halves are required.

#### Amount options

| Amount Type | What you configure | How it reads inputs |
|---|---|---|
| **Other Input** | pick input type from dropdown | Odoo auto-wires `inputs['CODE'].amount` — no Python needed. If absent → 0. Source: [`hr_salary_rule.py:182`](../enterprise/hr_payroll/models/hr_salary_rule.py#L182) |
| **Python Code** | write `result = ...` expression | you write `inputs['CODE'].amount` yourself — full control (negation, arithmetic, etc.) Source: [`hr_salary_rule.py:186`](../enterprise/hr_payroll/models/hr_salary_rule.py#L186) |
| **Fixed / Percentage** | static number or % of base | no relation to inputs |

#### "Absent" means the input line does not exist on this payslip

`inputs` is built from `self.input_line_ids` — the rows in the Other Inputs tab. If no line with code `DEDUCTION` was added, the key `'DEDUCTION'` simply does not exist in the dict. `'DEDUCTION' in inputs` returns `False`, `_satisfy_condition()` returns `False`, and the rule is completely skipped — it produces no payslip line at all (not zero, nothing).

| Situation | `'CODE' in inputs` | Payslip line created? |
|---|---|---|
| Input line added to payslip | `True` | Yes, rule runs and produces a line |
| No input line on payslip | `False` | No — rule skipped entirely |

#### Condition options that involve inputs

| Condition Type | What it checks | When to use |
|---|---|---|
| `Other Input` (dropdown) | `condition_other_input_id.code in inputs` | rule has a single designated input that gates it. Source: [`hr_salary_rule.py:198`](../enterprise/hr_payroll/models/hr_salary_rule.py#L198) |
| `Python Expression` | you write `result = 'CODE' in inputs` | used when you need more logic (check multiple codes, combine with other conditions) |

#### Real example — Deduction rule

Input on payslip: type = `Deduction`, amount = `200` → `inputs = {'DEDUCTION': <record, amount=200>}`

1. Condition: `'DEDUCTION' in inputs` → `True` → rule runs
2. Amount: `result = -inputs['DEDUCTION'].amount` → `-200`
3. Payslip line created: `Deduction | -200.00` (in category DED, reduces NET)

No input line on payslip → `inputs = {}` → condition is `False` → rule skipped → no line.

### Multiple input lines with the same code

If two `hr.payslip.input` lines share the same code (e.g. two separate commissions both coded `COMM`), the engine creates one payslip line per input line and aggregates them.
The `same_type_input_lines` dict tracks this; the rule is evaluated once per line, then `inputs[code]` is reset to the aggregator.
Source: [`models/hr_payslip.py:1013–1043`](../enterprise/hr_payroll/models/hr_payslip.py#L1013)

---

## Three Ways Inputs Are Populated

### 1. Manual entry by payroll officer
Open the payslip → Other Inputs tab → add a line → pick type → enter amount.
Used for: one-off bonuses, expense reimbursements, ad-hoc deductions.

### 2. Auto-populated from Salary Adjustments (`hr.salary.attachment`)
`_compute_input_line_ids` runs when the payslip is created or recomputed.
Source: [`models/hr_payslip.py:285`](../enterprise/hr_payroll/models/hr_payslip.py#L285)

Logic:
1. Finds all `hr.salary.attachment` records for the employee where:
   - `state = 'open'`
   - `date_start <= payslip.date_to`
   - `date_end >= payslip.date_from` (or no end date)
   - input type's `struct_ids` includes this payslip's structure (or is empty)
2. Groups by input type, sums amounts via `_get_active_amount()`.
3. Creates one `hr.payslip.input` line per type automatically.

Used for: recurring garnishments (child support, loan repayments), court-ordered deductions.
The input type must have `available_in_attachments = True`.

### 3. Property Inputs (structure-defined inputs on contract or payslip)
A newer mechanism where salary rules use `condition_select = 'property_input'`.
Values come from `version_id.payroll_properties` or `payslip.payslip_properties` (JSON fields).
These are NOT the same as `hr.payslip.input` — they are stored on the contract/payslip JSON properties.
Source: [`models/hr_payslip.py:1020–1031`](../enterprise/hr_payroll/models/hr_payslip.py#L1020)

---

## Salary Adjustments (`hr.salary.attachment`)

Model: [`models/hr_salary_attachment.py`](../enterprise/hr_payroll/models/hr_salary_attachment.py)

These are standing orders that automatically inject an input line into every payslip during their active period.

| Field | Purpose |
|---|---|
| `employee_ids` | one or more employees to deduct from |
| `other_input_type_id` | which input type code the deduction appears as (must have `available_in_attachments=True`) |
| `monthly_amount` | amount injected per payslip |
| `total_amount` | total to recover (for `limited` duration type) |
| `remaining_amount` | decremented each payslip; hits 0 → state becomes `close` |
| `duration_type` | `one` (single payslip), `limited` (until total recovered), `unlimited` (ongoing) |
| `state` | `open` → active, `close` → fully recovered, `cancel` → stopped |

---

## Key Methods

| Method | File:Line | Purpose |
|---|---|---|
| `_get_localdict()` | [`hr_payslip.py:1010`](../enterprise/hr_payroll/models/hr_payslip.py#L1010) | builds the Python dict passed to every salary rule formula |
| `_get_payslip_lines()` | [`hr_payslip.py:1088`](../enterprise/hr_payroll/models/hr_payslip.py#L1088) | iterates rules in sequence, evaluates each, builds `line_ids` |
| `_compute_rule()` | [`hr_salary_rule.py:156`](../enterprise/hr_payroll/models/hr_salary_rule.py#L156) | returns `(amount, qty, rate)` for one rule using localdict |
| `_satisfy_condition()` | [`hr_salary_rule.py:193`](../enterprise/hr_payroll/models/hr_salary_rule.py#L193) | checks if rule should run (Always / Input exists / Python / Domain) |
| `_compute_input_line_ids()` | [`hr_payslip.py:285`](../enterprise/hr_payroll/models/hr_payslip.py#L285) | auto-syncs salary attachment lines onto payslip inputs |

---

## UI Entry Points

| Entry Point | Path in UI | What It Does |
|---|---|---|
| Payslip form → Other Inputs tab | Payroll → Payslips → open one | manually add/edit input lines |
| Salary Adjustments | Payroll → Salary Adjustments | create recurring deductions that auto-appear on payslips |
| Salary Structure → Other Input Types | Payroll → Configuration → Structures → structure → Other Input Types tab | controls which input types are selectable for this structure |
| Input Types config | Payroll → Configuration → Other Input Types | define new codes available across structures |

---

## Edge Cases & Gotchas

- **Input not showing in dropdown**: The input type must be listed in the salary structure's `input_line_type_ids` field. If it's not there it won't appear even if globally active. Source: [`hr_payslip_input.py:18`](../enterprise/hr_payroll/models/hr_payslip_input.py#L18)

- **Amount = 0 does NOT skip the rule**: `amount_select = 'input'` returns 0 if the code is absent, but if the line exists with `amount = 0`, the payslip line is still created with total 0. Use `condition_select = 'input'` to skip the rule entirely when no input is present.

- **Multiple lines same code → multiple payslip lines**: If you manually add two input lines both coded `COMM`, the rule fires once per input line and creates two separate payslip lines summing to the total. Source: [`hr_payslip.py:1134`](../enterprise/hr_payroll/models/hr_payslip.py#L1134)

- **Credit note payslips negate amounts**: When `credit_note = True`, salary attachment amounts are negated automatically in `_compute_input_line_ids`. Source: [`hr_payslip.py:307`](../enterprise/hr_payroll/models/hr_payslip.py#L307)

- **Archiving an input type with open attachments is blocked**: `_check_salary_attachment_type_active` raises `UserError` if you try to archive a type that has running salary adjustments. Source: [`hr_payslip_input_type.py:36`](../enterprise/hr_payroll/models/hr_payslip_input_type.py#L36)

- **Property inputs vs. Other inputs**: `property_inputs` in localdict (from JSON on contract/payslip) are completely separate from `inputs` (from `hr.payslip.input` lines). Rules using `condition_select = 'property_input'` do NOT read from the Other Inputs tab.

---

## Changing Salary — How Version Effective Dates Affect the Payslip

In Odoo 19 the old `hr.contract` is replaced by **`hr.version`**: an employee record that is time-sliced by `date_version` (its effective date). The `wage` lives on each version. Source: [`hr_version.py:53`](../addons/hr/models/hr_version.py#L53), [`hr_version.py:167`](../addons/hr/models/hr_version.py#L167).

### The one rule that decides the wage

The wage at any date = the version with the **greatest `date_version` that is `<= date`** — `_get_version`. Source: [`hr_employee.py:547`](../addons/hr/models/hr_employee.py#L547).

A monthly payslip resolves its version from the **period start (`date_from`, usually the 1st)**, not mid-period. The `is_wrong_version` flag literally compares `version_id` to `_get_version(date_from)`. Source: [`hr_payslip.py:113`](../enterprise/hr_payroll/models/hr_payslip.py#L113), [`hr_payslip.py:398`](../enterprise/hr_payroll/models/hr_payslip.py#L398).

A pay run picks **one version per contract** — the one active at the period start — and only produces **multiple payslips when `contract_date_start` differs** (a genuinely new contract). The selection loop adds the first version with `date_version <= date_start` and breaks. Source: [`hr_payslip_run.py:120`](../enterprise/hr_payroll/models/hr_payslip_run.py#L120) (break at [`:159`](../enterprise/hr_payroll/models/hr_payslip_run.py#L159)).

Version date span: `date_start = max(date_version, contract_date_start)`, `date_end = min(next_version.date_version − 1, contract_date_end)`. Source: [`hr_version.py:552`](../addons/hr/models/hr_version.py#L552).

### Effect of each way to change the wage (monthly schedule)

| How you change it | Effect on the current month |
|---|---|
| Edit **Wage** on the current version and Save (in-place `write`). Same for the **Salary Indexation** wizard, which writes the new wage onto existing versions. | New wage applies to the **whole current month** (retroactive to period start). No proration. If the payslip is already confirmed, `has_wrong_data` flags it → recompute. Source: [`hr_payroll_index_wizard.py:77`](../enterprise/hr_payroll/wizard/hr_payroll_index_wizard.py#L77), [`hr_payslip.py:403`](../enterprise/hr_payroll/models/hr_payslip.py#L403) |
| **New version dated the 1st** of the month | New wage for the whole month; earlier months keep the old wage (history preserved). Cleanest. |
| **New version dated mid-month** (e.g. 15th), **same contract** | Current month still uses the version active on the 1st → **old wage all month**; new wage takes effect **next period**. No mid-month split or proration. |
| **New contract mid-month** (new `contract_date_start`; old contract ended on the 14th) | Pay run creates **two payslips**: 1st–14th at old wage, 15th–end at new wage, each **pro-rated by worked days** in its own span. Only true mid-month split. |

### Recommended workflow

- For a normal raise: make it **effective the 1st of a pay period** (edit the wage, run Indexation, or create a new version dated the 1st). Each month then sits at a single clean wage.
- For a genuine **mid-month** change with split pay: model it as a **new contract** (end the old one on the prior day, start a new one) — that is the only path that pro-rates within the month.
- New versions are created via `create_version` / the **New Contract** button / the **Salary Configurator** ([`hr_contract_salary`](../enterprise/hr_contract_salary/controllers/main.py#L620)), never automatically when you just edit and save. Source: [`hr_employee.py:556`](../addons/hr/models/hr_employee.py#L556).

---

## Payslip Period Range — How `date_from` / `date_to` Are Determined

Two layers set the period, both driven by the **pay schedule** (`schedule_pay`).

**1. Pay run (`hr.payslip.run`)** — the batch you create first. You set **From** (`date_start`) and **To** (`date_end`) directly; defaults are the 1st and last day of the current month. Changing the run's **Pay Schedule** recomputes them via `_compute_date_start` → `_schedule_period_start` and `_compute_date_end` → `date_start + _schedule_timedelta`. Source: [`hr_payslip_run.py:44`](../enterprise/hr_payroll/models/hr_payslip_run.py#L44), [`hr_payslip_run.py:203`](../enterprise/hr_payroll/models/hr_payslip_run.py#L203).

**2. Individual payslip (`hr.payslip`)** — `date_from` defaults to the 1st of the current month and is editable; **`date_to` is computed**, never typed: `date_to = date_from + _get_schedule_timedelta()`. Source: [`hr_payslip.py:62`](../enterprise/hr_payroll/models/hr_payslip.py#L62), [`hr_payslip.py:277`](../enterprise/hr_payroll/models/hr_payslip.py#L277).

The schedule used = `version_id.schedule_pay or version_id.structure_type_id.default_schedule_pay`. Source: [`hr_payslip.py:273`](../enterprise/hr_payroll/models/hr_payslip.py#L273).

### Period start and length per schedule

`_schedule_period_start` ([`hr_payslip.py:187`](../enterprise/hr_payroll/models/hr_payslip.py#L187)) sets the start; `_schedule_timedelta` ([`hr_payslip.py:250`](../enterprise/hr_payroll/models/hr_payslip.py#L250)) sets the length:

| `schedule_pay` | Start | `date_to` = start + |
|---|---|---|
| **monthly** (default) | 1st of month | +1 month −1 day → last day of month |
| semi-monthly | 1st or 15th | to the 15th or 31st |
| bi-monthly | 1st of the 2-month slice | +2 months −1 day |
| quarterly | 1st of quarter | +3 months −1 day |
| semi-annually | Jan 1 / Jul 1 | +6 months −1 day |
| annually | Jan 1 | +1 year −1 day |
| weekly | Monday | +6 days |
| bi-weekly | Monday, 2-week cycle | +13 days |
| daily | today | same day |

A normal **month range** is the monthly schedule: 1st → last day of the month.

### Where to configure it

| Level | Field / place | Effect |
|---|---|---|
| **Structure Type** (Payroll ▸ Configuration ▸ Structure Types) | `default_schedule_pay` ("Scheduled Pay") | Default schedule for any version using that type. Source: [`hr_payroll_structure_type.py:28`](../enterprise/hr_payroll/models/hr_payroll_structure_type.py#L28) |
| **Version / contract** (employee record, Payroll section) | `schedule_pay` ("Pay Schedule") | Per-employee override; inherits the structure-type default. Hidden when only one option exists (`show_schedule_pay`). Source: [`hr_version.py:14`](../enterprise/hr_payroll/models/hr_version.py#L14) |
| **Contract template** | `schedule_pay` | Pre-fills the schedule when the template is loaded onto a version. Source: [`hr_contract_template_views.xml:32`](../enterprise/hr_payroll/views/hr_contract_template_views.xml#L32) |
| **Pay run** | From / To (`date_start` / `date_end`) | Directly edit the actual dates for one batch, overriding the schedule-derived default. |
| **Payslip** | `date_from` editable; `date_to` auto | Adjust the start; end recomputes from the schedule (unless a `default_date_to` context is set). |

Schedule options come from `_get_selection_schedule_pay` ([`hr_payroll_structure_type.py:13`](../enterprise/hr_payroll/models/hr_payroll_structure_type.py#L13)). There is **no company-level period setting** — it lives on the structure type and the version.

---

## Related Docs

- [`INDEX.md`](INDEX.md)

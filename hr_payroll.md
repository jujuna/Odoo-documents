# Payroll

> **Core module:** `hr_payroll` | **Path:** [`enterprise/hr_payroll/`](../enterprise/hr_payroll/)
> **Accounting bridge:** `hr_payroll_account` | **Path:** [`enterprise/hr_payroll_account/`](../enterprise/hr_payroll_account/)
> **Odoo Apps category:** HR / Payroll
> **Updated by Codex and verified from source:** 2026-07-12 (all 26 `hr_payroll` model files, 4 wizards, payroll data/security files, and all 5 `hr_payroll_expense` files re-read end-to-end). Public-holiday lifecycle: [`public_holidays_flow.md`](public_holidays_flow.md).

## What It Does

Payroll computes employee payslips by running salary rules against an employee record (`hr.version`), worked days, and salary inputs. The result is a set of payslip lines such as `BASIC`, `GROSS`, `NET`, deductions, reimbursements, and country-specific payroll lines.

Two things gate every payslip and are the source of most real-world blockers:

1. **Work entries** — pay-run generation blocks conflict/gap errors, but an individually handled payslip can silently exclude conflict hours and confirmation ignores `action_validate()` returning false. Custom payroll needs its own fresh blocker before compute and confirmation.
2. **Time off** — a leave overlapping the period that is not approved (or that must be deferred) leaves a work entry in `conflict` or raises a danger error, which blocks the run.

The base payroll module does **not** create accounting entries by itself. Journal entries are added by `hr_payroll_account`, and actual bank/payment records are still handled by Accounting's normal payment flow.

---

## Executive Summary

### Main objects

| Object | Model | Role |
|---|---|---|
| Pay Run | `hr.payslip.run` | Batch/container for many payslips in one period. State is computed from its slips. |
| Payslip | `hr.payslip` | Real payroll document for one employee/version/period. |
| Payslip line | `hr.payslip.line` | One computed result of a salary rule (`BASIC`, `NET`, …); source of journal items. |
| Employee Record / Contract Version | `hr.version` | Odoo 19 replacement for the old contract object. Holds wage, structure type, schedule, calendar, contract dates, `work_entry_source`. |
| Work Entry | `hr.work.entry` | One block of time (attendance or leave) for one employee/day. Has its own state machine and gates payroll. |
| Worked Days | `hr.payslip.worked_days` | Work entries aggregated by work entry type for the payslip period. |
| Structure Type | `hr.payroll.structure.type` | Defines wage type, default schedule, default work entry type, and default structure. |
| Salary Structure | `hr.payroll.structure` | The salary rules + allowed inputs + unpaid types + report. With accounting, also the Salary Journal. |
| Salary Rule | `hr.salary.rule` | One computation step. With accounting, can also define debit/credit accounts. |
| Other Inputs | `hr.payslip.input` | Manual/automatic numeric values used by rules, keyed by input type code. |
| Salary Adjustment | `hr.salary.attachment` | Recurring/limited deduction that auto-injects input lines (garnishments, child support, loans). |
| Time Off | `hr.leave` | A leave; with `hr_payroll_holidays` carries a `payslip_state` (normal/done/blocked). |
| Journal Entry | `account.move` | Created only by `hr_payroll_account` during confirmation when a Salary Journal exists. Always **draft**. |

### End-to-end flow

```text
Configure structure type / structure / salary rules (+ accounts if accounting)
    |
Generate work entries for the period (cron / pay run / on-demand)   <-- gated by time off
    |
Create pay run or off-cycle payslip
    |
Generate payslips  -->  compute worked-day lines  -->  build input lines  -->  compute salary rules
    |                       (blocked by undefined slots / work-entry conflicts / errors)
Confirm payslip/pay run (action_payslip_done)
    |   - state = validated
    |   - validates the period's work entries (regular payslips only)
    |   - accounting bridge: create DRAFT account.move if the structure has a Salary Journal
    |
Post journal entry  (manual, in Accounting)
    |
Register payment (account.payment.register)  -->  reconcile
    |
state = paid  (only if all move-line residuals are zero)
```

### State vs money — what each step actually does

| Step | Payslip state | Accounting state | Money moved? |
|---|---|---|---|
| Compute sheet | `draft` | none | No |
| Confirm / Create Draft Entry | `validated` | optional **draft** `account.move` | No |
| Post journal entry | `validated` | **posted** `account.move` | No |
| Register payment + full reconciliation | `paid` | `account.payment` reconciled | Yes |
| Manual Mark as Paid (no accounting) | `paid` | may be none | No |
| Payment Report (CSV/SEPA file) | stays `validated`, `paid_date` set | none | bank file only |

> **Important:** the stored `state` is not the whole story. A payslip also has a computed `state_display` that overrides the badge with **Error** or **Warning** when it has unresolved issues, and an `error_count` that hard-blocks compute/confirm/pay. See [Statuses, Errors & Warnings](#statuses-errors--warnings).

---

## Module Map

Payroll is built from many small, mostly `auto_install` bridge modules. Knowing which layer a feature lives in is essential for tracing behaviour. **Community (`addons/`)** provides the work-entry engine; **Enterprise (`enterprise/`)** provides payroll itself and all bridges.

### Core / required

| Module | Layer | Why |
|---|---|---|
| `hr_work_entry` | community | The work-entry model, state machine, conflict checks, generation, and the daily generation cron. Payroll's worked days come from here. |
| `hr_work_entry_holidays` | community | Maps `hr.leave` → leave work entries; refuse/cancel regeneration. |
| `hr_payroll` | enterprise | The payslip/pay-run/structure/rule engine, salary attachments, dashboard, declarations, PDF cron. |
| `hr_contract` / HR versioning | community/enterprise | Provides `hr.version`, the employee record used by payroll. |

### Work-entry source modules (decide where worked days come from)

`hr.version.work_entry_source` is `calendar` by default ([hr_version.py:27](../addons/hr_work_entry/models/hr_version.py#L27)). Bridges add the other sources:

| Module | Adds source | Effect |
|---|---|---|
| `hr_work_entry_enterprise` | — | Gantt UI / enterprise work-entry views. |
| `hr_work_entry_attendance` | `attendance` | Attendances + approved overtime become work entries. |
| `hr_work_entry_planning` | `planning` | Published planning shifts become work entries. |
| `hr_work_entry_holidays_enterprise` | — | Approve/Refuse-Time-Off buttons on conflicting leave work entries. |

> **Dead stubs in this checkout:** `hr_work_entry_contract_enterprise` and `hr_work_entry_contract_attendance` contain only stale `.pyc` artifacts (no `__manifest__.py`, no live source). The live code is in `hr_work_entry_enterprise`, `hr_work_entry_attendance`, and `hr_work_entry_planning`.

### Accounting & payment modules

| Module | What it enables |
|---|---|
| `hr_payroll_account` | Salary journals, salary-rule debit/credit accounts, draft journal-entry creation, batching, register-payment integration. |
| `hr_payroll_account_iso20022` | SEPA / Swiss ISO20022 bank-file export (`batch_booking`), IBAN validation. |
| `project_hr_payroll_account` | A project smart button counting contracts by analytic account. Does **not** change move generation. |

### Input / enrichment integrations

| Module | Injects | Via |
|---|---|---|
| `hr_payroll_attendance` (+`hr_work_entry_attendance`) | worked-days from attendances/overtime | work-entry generation |
| `hr_payroll_planning` (+`hr_work_entry_planning`) | worked-days from published shifts | work-entry generation |
| `hr_payroll_expense` | one `EXPENSES` input line + reconciled move | `_compute_input_line_ids` override |
| `hr_payroll_sale_commission` | one input line per commission plan | `_compute_input_line_ids` override |
| `hr_payroll_fleet` | **nothing** to payslips — two dashboard warnings only | dashboard |

### Configurator & documents

| Module | Role |
|---|---|
| `hr_contract_salary` | Salary-package offer + web configurator that produces the `hr.version` payroll computes against. |
| `hr_contract_salary_payroll` | Bridges configurator benefits to payslip inputs; runs a simulation payslip for the preview. |
| `hr_contract_salary_holidays` | Turns the "extra holidays" choice into an `hr.leave.allocation`. |
| `documents_hr_payroll` | Files payslip/declaration PDFs into Documents; `Send By Email` action. |
| Localization payroll modules (`l10n_*_hr_payroll[_account]`) | Country structures, rules, rate tables (`hr.rule.parameter`), declarations, payment formats. |

---

## Pay Run (`hr.payslip.run`)

Source: [`models/hr_payslip_run.py`](../enterprise/hr_payroll/models/hr_payslip_run.py)

A pay run is a batch wrapper around payslips. It does not compute salaries itself. It selects employee versions, creates linked payslips, and delegates computation/confirmation/payment to those payslips. **Its state is computed from the slips — you never write it directly.**

### Core fields

| Field | Purpose |
|---|---|
| `name` | Generated from period and structure when absent. See `_get_name_for_period()` at [`hr_payslip_run.py:77`](../enterprise/hr_payroll/models/hr_payslip_run.py#L77). |
| `slip_ids` | One2many to `hr.payslip`; the actual payroll documents. |
| `state` | `store=True compute='_compute_state'` from `slip_ids.state`. See [`hr_payslip_run.py:183`](../enterprise/hr_payroll/models/hr_payslip_run.py#L183). |
| `date_start`, `date_end` | Period covered. Editable only while `01_ready` ([`hr_payslip_run_views.xml:160`](../enterprise/hr_payroll/views/hr_payslip_run_views.xml#L160)). |
| `structure_id` | Optional salary structure filter for the batch. |
| `schedule_pay` | Pay schedule used to compute default period and filter versions. |
| `move_id` | (accounting) Set **only in batched mode** — one move per (journal, month) for the whole run. |
| `payment_report*` | Generated bank-file metadata (CSV/SEPA). Not an accounting payment. The run also carries `payment_report_format`. |

### Pay run states

Source: [`_compute_state()`](../enterprise/hr_payroll/models/hr_payslip_run.py#L183)

| State | Label | Computed when (priority order) |
|---|---|---|
| `01_ready` | Ready | Any payslip is still `draft`, **or there are no payslips at all**. |
| `02_close` | Done | No draft slips and at least one slip is `validated`. |
| `03_paid` | Paid | No draft/validated slips and at least one slip is `paid`. |
| `04_cancel` | Cancelled | **All** linked payslips are `cancel`. |

> The priority matters: **one remaining draft slip keeps the whole run at `01_ready`**, even if every other slip is validated. A run reaches `04_cancel` only when every slip is cancelled. The status bubble hides `04_cancel` ([`hr_payslip_run_views.xml:95`](../enterprise/hr_payroll/views/hr_payslip_run_views.xml#L95)).

### Run-level diagnostic counters

These drive the kanban and the "review issues" workflow:

| Field | Meaning | Source |
|---|---|---|
| `payslips_with_issues` | count of slips with any error or warning | [`hr_payslip_run.py:230`](../enterprise/hr_payroll/models/hr_payslip_run.py#L230) |
| `has_error` | any slip with `error_count` (gates the kanban) | [`hr_payslip_run.py:235`](../enterprise/hr_payroll/models/hr_payslip_run.py#L235) |
| `empty_payslips` | count of slips with no `line_ids`; drives Compute-vs-Confirm | [`hr_payslip_run.py:240`](../enterprise/hr_payroll/models/hr_payslip_run.py#L240) |
| `action_review_issues` | opens the run's slips pre-filtered to **Has Issues** | [`hr_payslip_run.py:330`](../enterprise/hr_payroll/models/hr_payslip_run.py#L330) |

### Pay run actions

| UI / method | Effect | Blocking condition |
|---|---|---|
| Generate Payslips | `generate_payslips()` — selects versions, creates + computes slips | no version → UserError; **work-entry conflict** → UserError listing intervals; **calendar gap** → UserError. See [Work Entries](#work-entries--worked-days). |
| Compute | `action_confirm()` → `compute_sheet()` on draft slips | inherits compute error guard |
| Confirm / Create Draft Entry | `action_validate()` — confirms non-cancel slips that have lines | inherits confirm guards; skips empty slips |
| Mark as Paid | `action_paid()` | inherits paid guards |
| Revert / Unpaid | `action_unpaid()` | inherits unpaid guards |
| Set to Draft | `action_draft()` — re-drafts slips, clears payment report | any slip `paid` → ValidationError ([`hr_payslip_run.py:251`](../enterprise/hr_payroll/models/hr_payslip_run.py#L251)) |
| Payment Report | `action_payment_report()` | builds a bank file (see [Payment](#payment-paths-report-and-iso20022)) |

`_are_payslips_ready()` returns True if any slip is `validated`/`cancel` ([`hr_payslip_run.py:419`](../enterprise/hr_payroll/models/hr_payslip_run.py#L419)); the accounting bridge uses it to decide whether to sweep all of a run's slips into one batched move.

### How Generate Payslips picks employee versions

`generate_payslips(version_ids, employee_ids)` ([`hr_payslip_run.py:344`](../enterprise/hr_payroll/models/hr_payslip_run.py#L344)) accepts explicit versions, or resolves employees through `_get_valid_version_ids()` ([`:120`](../enterprise/hr_payroll/models/hr_payslip_run.py#L120)):

- Candidate domain: company match, contract dates overlap the run period, `date_version <= date_end`, a structure type set; filtered by the run's `structure_id.type_id` and `schedule_pay` when set.
- Per employee, versions are walked newest-first: it keeps the version active at run start, plus the **first version of each newer contract** that starts inside the period — so a mid-period contract change yields **two versions → two payslips** for the same employee.
- Slips are created with `tracking_disable`, named, then `compute_sheet()` runs on the whole batch; the run is forced back to `01_ready` ([`:407-410`](../enterprise/hr_payroll/models/hr_payslip_run.py#L407)).

Other run facts verified from source: the run `name` is auto-generated from period + structure on create when absent ([`create`, :222](../enterprise/hr_payroll/models/hr_payslip_run.py#L222)); the run is archivable (`active` field, [`:28`](../enterprise/hr_payroll/models/hr_payslip_run.py#L28)); `gross_sum`/`net_sum` are stored sums over non-cancelled slips ([`:216-220`](../enterprise/hr_payroll/models/hr_payslip_run.py#L216)); deleting a run is blocked while any slip is not draft/cancel ([`:414-417`](../enterprise/hr_payroll/models/hr_payslip_run.py#L414)).

With `hr_payroll_account` installed, the kanban Confirm button becomes **Create Draft Entry**, visible only when `state == '01_ready' and not empty_payslips and payslip_count` ([`hr_payroll_account/views/hr_payslip_run_views.xml:23`](../enterprise/hr_payroll_account/views/hr_payslip_run_views.xml#L23)).

### Pay run vs off-cycle

A payslip belongs to a pay run if `payslip_run_id` is set; if empty, it is an off-cycle payslip using the same computation/confirmation/accounting/payment logic, simply not grouped. Button [`action_move_to_off_cycle()`](../enterprise/hr_payroll/models/hr_payslip.py#L816) sets `payslip_run_id = False`.

---

## Payslip (`hr.payslip`)

Source: [`models/hr_payslip.py`](../enterprise/hr_payroll/models/hr_payslip.py)

A payslip is the real payroll computation document for one employee/version/period/structure, plus worked-day lines, input lines, computed salary lines, an optional accounting move, and state + PDF/payment metadata.

### Core fields (selected)

| Field | Purpose |
|---|---|
| `employee_id` | Employee being paid. |
| `version_id` | Employee record/version used for wage/calendar/structure type. Computed from employee + `date_from`. See [`hr_payslip.py:1219`](../enterprise/hr_payroll/models/hr_payslip.py#L1219). |
| `struct_id` | Salary structure whose rules are evaluated. |
| `date_from`, `date_to` | Payroll period. `date_to` computed from schedule unless forced by context. |
| `worked_days_line_ids` / `input_line_ids` / `line_ids` | Worked days, Other Inputs, computed salary lines. |
| `state` | `draft`, `validated`, `paid`, `cancel`. |
| `state_display` | Computed badge: `error` / `warning` / the real state. See [Statuses](#statuses-errors--warnings). |
| `error_count`, `warning_count`, `issues` | The blocking framework — `error_count > 0` hard-blocks. |
| `is_regular` | True when `struct_id == struct_id.type_id.default_struct_id` (the normal monthly run vs an off-cycle structure like a bonus). Gates work-entry validation on confirm. [`_compute_is_regular`](../enterprise/hr_payroll/models/hr_payslip.py#L394) |
| `credit_note` / `is_refund_payslip` / `is_refunded` / `is_corrected` | Refund/correction sub-lifecycle. See [Refund / Correction](#refund-correction--recompute). |
| `origin_payslip_id` / `related_payslip_ids` | Links a refund/correction chain. |
| `edited` | Manual edits made — freezes worked-day amounts and is skipped by full refresh. |
| `queued_for_pdf` | Confirmed but PDF not yet rendered (awaiting the hourly cron). |
| `has_negative_net_to_report` | This slip had NET < 0 at confirm; flagged for carry-forward. |
| `paid` / `paid_date` | "Made Payment Order?" flag + date; independent of `state`, not proof money moved. |
| `move_id` / `move_state` / `journal_id` / `date` | (accounting) generated entry + its state + salary journal + accounting date. |

### Period logic

Schedule = `version_id.schedule_pay or version_id.structure_type_id.default_schedule_pay` ([`hr_payslip.py:271`](../enterprise/hr_payroll/models/hr_payslip.py#L271)); `date_to = date_from + _get_schedule_timedelta()` ([`hr_payslip.py:276`](../enterprise/hr_payroll/models/hr_payslip.py#L276)). Helpers `_schedule_period_start()` ([`:187`](../enterprise/hr_payroll/models/hr_payslip.py#L187)) and `_schedule_timedelta()` ([`:250`](../enterprise/hr_payroll/models/hr_payslip.py#L250)).

| Schedule | Typical period |
|---|---|
| `monthly` | First-to-last day of month |
| `semi-monthly` | 1st–15th or 15th–end |
| `quarterly` / `semi-annually` / `annually` | Quarter / half-year / year |
| `bi-monthly` | Two calendar months |
| `weekly` / `bi-weekly` / `daily` | Week / two weeks / one day |

The full selection lives on the structure type ([`_get_selection_schedule_pay`, hr_payroll_structure_type.py:13](../enterprise/hr_payroll/models/hr_payroll_structure_type.py#L13)); `hr.version.schedule_pay` and `hr.payslip.run.schedule_pay` reuse it.

### Computing the sheet

[`compute_sheet()`](../enterprise/hr_payroll/models/hr_payslip.py#L785): keeps only draft slips, **blocks if `error_count`** ([`:787`](../enterprise/hr_payroll/models/hr_payslip.py#L787)), deletes old `line_ids`, flushes, sets `compute_date`, calls `_get_payslip_lines()`, creates `hr.payslip.line`, computes YTD worked days if enabled.

> **Compute Sheet recomputes salary lines only**, not worked days/input lines. To fully rebuild from changed work entries use **Recompute Whole Sheet** ([`action_refresh_from_work_entries()`](../enterprise/hr_payroll/models/hr_payslip.py#L804)) — which skips slips with `edited=True`.

### `paid_amount` in formulas

Do not confuse `payslip.paid_amount` (the wage fed into BASIC) with `state = paid`. `paid_amount` returns the contract wage under `salary_simulation` or when worked-day lines are disabled, otherwise the sum of `worked_days_line_ids.amount` ([`hr_payslip.py:912`](../enterprise/hr_payroll/models/hr_payslip.py#L912), [`:1647`](../enterprise/hr_payroll/models/hr_payslip.py#L1647)). Default BASIC rule: `result = payslip.paid_amount` ([`hr_salary_rule_data.xml:17`](../enterprise/hr_payroll/data/hr_salary_rule_data.xml#L17)).

### Plain-English salary calculation

The payslip amount is driven by **hours**, while **days** are mostly the human-readable rollup shown on the payslip:

1. The employee version/contract has a **Working Hours** calendar, a **Schedule Pay**, and a **Wage Type**.
2. The calendar creates work entries for the payslip period. Example: Standard 40h/week in June can create 22 attendance days x 8h = 176h.
3. Worked-day lines group those work entries by type, then show `days = hours / hours_per_day` ([`_get_worked_day_lines_values`, hr_payslip.py:845](../enterprise/hr_payroll/models/hr_payslip.py#L845)).
4. Money is computed from hours in `_compute_amount` ([`hr_payslip_worked_days.py:39`](../enterprise/hr_payroll/models/hr_payslip_worked_days.py#L39)).

For **Fixed Wage** (`wage_type='monthly'`), Odoo prorates the fixed contract wage over the period's non-extra hours:

```text
hourly rate = contract wage / non-extra worked hours
worked amount = hourly rate * line hours * work entry type rate
```

So a full fixed-wage month stays at the contract wage even if one month has 176 hours and another has 184 hours: Odoo divides by that month's normal hours, then multiplies back by the paid hours. Unpaid or out-of-contract hours reduce the amount because they contribute `amount=0`.

For **Hourly Wage** (`wage_type='hourly'`), Odoo uses `version.hourly_wage` directly:

```text
worked amount = hourly wage * line hours * work entry type rate
```

`Schedule Pay` only chooses the payslip period (monthly, weekly, etc.). `Working Hours` creates the hour quantity. `Wage Type` decides how those hours become money.

State transitions, every blocker, and the badge framework are documented in [Statuses, Errors & Warnings](#statuses-errors--warnings).

---

## Work Entries & Worked Days

Work entries are the bridge between an employee's time (attendance or leave) and the payslip's worked-day lines. **They are the single biggest source of "I can't generate/confirm the payslip" problems.** The engine lives in community `hr_work_entry`; `hr_payroll` adds the payroll-specific rollup.

### Work entry state machine (`hr.work.entry`)

Four states ([`hr_work_entry.py:39`](../addons/hr_work_entry/models/hr_work_entry.py#L39)). **UI labels differ from the technical values** — `validated` shows as **In Payslip**:

| Value | UI label | Meaning |
|---|---|---|
| `draft` | New | Generated/created, editable, **counted** in worked hours. |
| `conflict` | In Conflict | Failed a check; **excluded** from worked hours; blocks clean validation. |
| `validated` | In Payslip | Locked into a confirmed payslip — immutable, cannot be edited or deleted. |
| `cancelled` | Cancelled | `active=False` (archived); ignored everywhere. |

`state` and `active` are kept in lockstep by the `write()` override ([`hr_work_entry.py:261`](../addons/hr_work_entry/models/hr_work_entry.py#L261)): `state='draft'`→`active=True`, `state='cancelled'`→`active=False`, and writing `active` flips state to `draft`/`cancelled`. The boolean `conflict` field is just a stored mirror of `state=='conflict'` used to sort conflicting rows to the top ([`:75`](../addons/hr_work_entry/models/hr_work_entry.py#L75)).

| Transition | Trigger | Source |
|---|---|---|
| draft/conflict → validated | `action_validate()` succeeds (no errors) | [`hr_work_entry.py:109`](../addons/hr_work_entry/models/hr_work_entry.py#L109) |
| draft → conflict | any failed check in create/write/validate | [`hr_work_entry.py:138`](../addons/hr_work_entry/models/hr_work_entry.py#L138) |
| conflict → draft | `_reset_conflicting_state()` runs automatically before re-checking (self-heals) | [`hr_work_entry.py:289`](../addons/hr_work_entry/models/hr_work_entry.py#L289) |
| validated → draft | `action_set_to_draft()` server action ("Set to Draft") | [`hr_work_entry.py:53` (enterprise)](../enterprise/hr_payroll/models/hr_work_entry.py#L53) |
| any → cancelled | write `active=False` / `state='cancelled'` | [`hr_work_entry.py:261`](../addons/hr_work_entry/models/hr_work_entry.py#L261) |

**Validated entries are immutable (blocker):** writing any data field (other than a state change / `active=False`) to a `validated` entry raises **UserError** "This work entry cannot be modified because it is already associated with a generated payslip" ([`hr_work_entry.py:56` enterprise](../enterprise/hr_payroll/models/hr_work_entry.py#L56)); deletion is blocked by the ondelete guard "This work entry is validated. You can't delete it." ([`hr_work_entry.py:279`](../addons/hr_work_entry/models/hr_work_entry.py#L279)). To edit, first reset the entry to draft or cancel the payslip that locked it.

UI: the list view decorates `conflict`=warning, `validated`=success, `draft`=info ([`hr_work_entry_views.xml:152`](../addons/hr_work_entry/views/hr_work_entry_views.xml#L152)); the enterprise Gantt decorates only `conflict`=warning ([`hr_work_entry_views.xml:38`](../enterprise/hr_work_entry_enterprise/views/hr_work_entry_views.xml#L38)). The search view exposes a **Conflicting** filter ([`:185`](../addons/hr_work_entry/views/hr_work_entry_views.xml#L185)).

### How conflicts are detected (4 checks)

`_check_if_error()` ([`hr_work_entry.py:138`](../addons/hr_work_entry/models/hr_work_entry.py#L138)) runs on every create and (via the `_error_checking` context manager) on writes/unlinks. Any hit sets `conflict` and makes `action_validate()` return False:

| Check | Flags | Source |
|---|---|---|
| Undefined type | entry with no `work_entry_type_id` | [`:141`](../addons/hr_work_entry/models/hr_work_entry.py#L141) |
| Overlap / >24h | per `(employee, day)`, `SUM(duration)` ≤0 or **>24h** (raw SQL) | `_mark_conflicting_work_entries` [`:148`](../addons/hr_work_entry/models/hr_work_entry.py#L148) |
| Leave outside schedule | a leave entry wholly outside the calendar's theoretical intervals (flexible calendars exempt) | `_mark_leaves_outside_schedule` [`:184`](../addons/hr_work_entry/models/hr_work_entry.py#L184) |
| Already-validated day | a draft entry on the same `(employee, date)` as a `validated` entry | `_mark_already_validated_days` [`:213`](../addons/hr_work_entry/models/hr_work_entry.py#L213) |

Nuances:
- The overlap check is **not** literal time-interval overlap — it is `SUM(duration) > 24` per employee-day ([`:155`](../addons/hr_work_entry/models/hr_work_entry.py#L155)). Two 13h entries on one day conflict; two non-overlapping 4h entries do not.
- A hard `@api.constrains` on `duration` raises **ValidationError** "Duration must be positive and cannot exceed 24 hours" on a *single* entry — distinct from the per-day SUM conflict ([`:55`](../addons/hr_work_entry/models/hr_work_entry.py#L55)).
- Conflicts self-heal: `_error_checking` resets stale conflicts to draft then re-checks ([`:317`](../addons/hr_work_entry/models/hr_work_entry.py#L317)). Context `hr_work_entry_no_check=True` skips the pass.

**How a conflict gates payroll:** worked hours are read only from entries in state `validated` **or** `draft` ([`get_work_hours` domain, hr_version.py:216](../enterprise/hr_payroll/models/hr_version.py#L216)), so a `conflict` entry **silently drops its hours** from the payslip rather than raising. The hard stop comes at **pay-run generation**, which re-runs `_check_if_error` and raises **UserError "Some work entries could not be validated. Time intervals to look for: …"** ([`hr_payslip_run.py:386`](../enterprise/hr_payroll/models/hr_payslip_run.py#L386)). Conflicts are **not** part of `error_count`.

### Undefined slots — a separate UserError

"Undefined slots" means part of the contract's theoretical schedule has **no work entry at all** (a gap that would understate hours). Checked by `_check_undefined_slots()` ([`hr_work_entry.py:30` enterprise](../enterprise/hr_payroll/models/hr_work_entry.py#L30)):

1. Groups the payslip's work entries by version.
2. **Skips any version whose `work_entry_source != 'calendar'`** ([`:39`](../enterprise/hr_payroll/models/hr_work_entry.py#L39)) — attendance/planning contracts are never gap-checked (their schedule is dynamic).
3. For calendar versions, computes `calendar attendance intervals − work-entry intervals`; any remainder is an uncovered slot.
4. Raises **UserError "Watch out for gaps in <employee>'s calendar … Please complete the missing work entries"** ([`:48`](../enterprise/hr_payroll/models/hr_work_entry.py#L48)).

It runs inside `_compute_worked_days_line_ids` ([`hr_payslip.py:1464`](../enterprise/hr_payroll/models/hr_payslip.py#L1464)), so it fires whenever worked days are (re)computed — opening/creating the draft, `compute_sheet`, `action_refresh_from_work_entries`, and pay-run generation ([`hr_payslip_run.py:382`](../enterprise/hr_payroll/models/hr_payslip_run.py#L382)). **Resolution:** fill/regenerate the missing work entries.

### Generation, the cron, and regeneration

Generation lives in community `hr_work_entry`:

- `generate_work_entries(date_start, date_stop, force=False)` ([`hr_version.py:392`](../addons/hr_work_entry/models/hr_version.py#L392)) → `_generate_work_entries` ([`:418`](../addons/hr_work_entry/models/hr_version.py#L418)) only generates the open sub-intervals between a version's `date_generated_from`/`date_generated_to` and the requested range, then advances those markers. Existing entries are not re-created unless `force=True`.
- `force=True` (regeneration wizard) builds a `domain_to_nullify` that archives all **non-validated** entries in range before regenerating ([`:457`](../addons/hr_work_entry/models/hr_version.py#L457)); validated entries are always preserved.
- `_get_version_work_entries_values` ([`:172`](../addons/hr_work_entry/models/hr_version.py#L172)) turns calendar intervals + leaves into raw vals; `_generate_work_entries_postprocess` ([`:501`](../addons/hr_work_entry/models/hr_version.py#L501)) converts datetime spans to `date`+`duration`, splits at local midnight, drops zero-duration, and **merges** entries with the same `(date, type, employee, version, company)`.

**Which work entry type gets created?** For `work_entry_source='calendar'`, the employee's working calendar creates attendance intervals ([`hr_version.py:99`](../addons/hr_work_entry/models/hr_version.py#L99)). The generated work entry type comes from the calendar attendance line's `work_entry_type_id` if set; otherwise it falls back to the version/structure type default (`default_work_entry_type_id`) ([`hr_version.py:139`](../addons/hr_work_entry/models/hr_version.py#L139)). Changing the default after entries already exist does not rewrite validated work entries; regenerate/reset the entries if the payslip period must use the new type.

**The cron** `ir_cron_generate_missing_work_entries` ([`ir_cron_data.xml:4`](../addons/hr_work_entry/data/ir_cron_data.xml#L4)) runs **daily** as `base.user_root` and calls `_cron_generate_missing_work_entries()` ([`hr_version.py:694`](../addons/hr_work_entry/models/hr_version.py#L694)). It only covers **first-of-this-month to last-of-next-month**, processes one company at a time, batches 100 versions, and self-retriggers ([`:714-724`](../addons/hr_work_entry/models/hr_version.py#L714)).

> **Horizon gotcha:** a payslip period beyond next month will not have its work entries auto-generated — generate them manually (regeneration wizard) or wait for the horizon to advance. A brand-new contract added today gets entries only on the next daily run unless triggered manually.

**Regeneration wizard** `hr.work.entry.regeneration.wizard` ([`hr_work_entry_regeneration_wizard.py:10`](../addons/hr_work_entry/wizard/hr_work_entry_regeneration_wizard.py#L10)) regenerates with `force=True`. Guards (skippable via context `work_entry_skip_validation`): incomplete criteria ([`:101`](../addons/hr_work_entry/wizard/hr_work_entry_regeneration_wizard.py#L101)); range outside generated dates ([`:103`](../addons/hr_work_entry/wizard/hr_work_entry_regeneration_wizard.py#L103)); **"No work entry can be regenerated"** when every selected employee already has validated entries in range ([`:107`](../addons/hr_work_entry/wizard/hr_work_entry_regeneration_wizard.py#L107)). Editing a version's `resource_calendar_id`/`work_entry_source` ([`_get_fields_that_recompute_we`, :689](../addons/hr_work_entry/models/hr_version.py#L689)) auto-triggers `_recompute_work_entries` ([`:679`](../addons/hr_work_entry/models/hr_version.py#L679), which runs the wizard with `work_entry_skip_validation=True`); the enterprise override at [`hr_version.py:329`](../enterprise/hr_payroll/models/hr_version.py#L329) adds a `_recompute_payslips` call on top.

`has_static_work_entries()` is True only for `calendar` ([`hr_version.py:386`](../addons/hr_work_entry/models/hr_version.py#L386)); this is what makes the gap check and batching optimisations apply only to calendar contracts.

### Worked-days rollup and paid/unpaid amounts

`_compute_worked_days_line_ids` ([`hr_payslip.py:1429`](../enterprise/hr_payroll/models/hr_payslip.py#L1429)) generates entries over the period (±1 day), runs `_check_undefined_slots`, then builds lines via `_get_worked_day_lines_values` ([`:845`](../enterprise/hr_payroll/models/hr_payslip.py#L845)) from `version.get_work_hours()` ([`_get_work_hours`, hr_version.py:252](../enterprise/hr_payroll/models/hr_version.py#L252)) — a `_read_group` summing `duration` per work-entry type over `validated`/`draft` entries. Hours convert to days via `hours_per_day`, with per-type rounding (`round_days`) and a carry (`add_days_rounding`) onto the largest line. Out-of-contract days get a separate `OUT` line ([`:872`](../enterprise/hr_payroll/models/hr_payslip.py#L872)). Slips skip this entirely under `salary_simulation` or when the struct has `use_worked_day_lines=False`.

**Worked-day amount** `_compute_amount` ([`hr_payslip_worked_days.py:39`](../enterprise/hr_payroll/models/hr_payslip_worked_days.py#L39)):
- Early-returns (amount frozen) if the slip is `edited` or not `draft`; `OUT`/version-less lines are forced to 0 ([`:43-44`](../enterprise/hr_payroll/models/hr_payslip_worked_days.py#L43)).
- `is_paid` = the type is **not** in the **structure's** `unpaid_work_entry_type_ids` ([`:31`](../enterprise/hr_payroll/models/hr_payslip_worked_days.py#L31)) — so the same leave type can be paid under one structure, unpaid under another.
- Hourly contracts use `version.hourly_wage`; otherwise hourly rate = `contract_wage / sum(non-extra paid hours)` (`is_extra_hours` types excluded from the denominator so overtime doesn't dilute the base rate, [`:51-53`](../enterprise/hr_payroll/models/hr_payslip_worked_days.py#L51)).
- `amount = hourly_rate * number_of_hours * work_entry_type.amount_rate` **only if `is_paid`, else 0** ([`:56`](../enterprise/hr_payroll/models/hr_payslip_worked_days.py#L56)).

So an **unpaid leave** still shows days/hours on the payslip but contributes `amount=0`; salary rules prorate the monthly wage down because those hours add no paid amount. A **paid leave** carries its hours at the rate scaled by `amount_rate` (e.g. partial sick pay). A work entry type named "Unpaid" is not magic: it is unpaid only when that type is selected in the salary structure's **Unpaid Work Entry Types**.

Common examples:

| Work entry type | What changes salary? |
|---|---|
| Attendance | Usually paid at `amount_rate = 1.0`; full normal hours give the full fixed wage. |
| Out of Contract (`OUT`) | Always amount 0 in `_compute_amount`; used for days outside the contract/version dates. |
| Compensatory Time Off | Paid or unpaid depends on the salary structure's `unpaid_work_entry_type_ids`, not the name. |
| Double Time Hours | Uses the work entry type `amount_rate` (for example 2.0 / 200%). If marked `is_extra_hours`, those hours are excluded from the fixed-wage denominator and are added on top. |

### Validation on confirm; release on cancel/draft

Work entries do **not** need to be pre-validated to compute. Confirming validates them: `action_payslip_done()` searches the period's entries for each **regular** payslip (`is_regular`) and calls `work_entries.action_validate()` ([`hr_payslip.py:599-610`](../enterprise/hr_payroll/models/hr_payslip.py#L599)) — flipping draft→validated, or leaving conflicts unvalidated. Bonus/13th-month (non-regular) structures do **not** validate work entries.

Cancelling/re-drafting a slip calls `action_draft_linked_entries()` ([`hr_payslip.py:492`](../enterprise/hr_payroll/models/hr_payslip.py#L492)), resetting the validated entries it locked back to draft (skipping entries shared with a still-existing duplicate slip).

---

## Time Off & Payroll

How a leave reaches a payslip: a validated `hr.leave` becomes a `hr.work.entry` carrying the leave type's `work_entry_type_id`; the payslip aggregates those into worked-day lines. Conflict entries block the batch generator but can silently drop from an individual slip. Modules: [`hr_work_entry_holidays`](../addons/hr_work_entry_holidays) (community glue), [`hr_work_entry_holidays_enterprise`](../enterprise/hr_work_entry_holidays_enterprise) (UI), [`hr_payroll_holidays`](../enterprise/hr_payroll_holidays) (deferral, `auto_install`).

### Mapping: leave type → work entry type

`hr.leave.type` gains `work_entry_type_id` ([`hr_leave.py:12`](../addons/hr_work_entry_holidays/models/hr_leave.py#L12)); the reverse `leave_type_ids` is on `hr.work.entry.type` ([`hr_work_entry.py:62`](../addons/hr_work_entry_holidays/models/hr_work_entry.py#L62)). When a real employee/public leave row is selected but its configured type is empty, the holidays override returns an empty type and the generated entry becomes an undefined-type conflict. The generic leave fallback is for an unresolved leave interval, not a safe substitute for missing configuration.

### Validated leave → leave work entry

Approval funnels into base `_action_validate()` ([`hr_leave.py:1185`](../addons/hr_holidays/models/hr_leave.py#L1185)) → `_validate_leave_request()`, which `hr_work_entry_holidays` overrides to call `_cancel_work_entry_conflict()` ([`hr_leave.py:23`](../addons/hr_work_entry_holidays/models/hr_leave.py#L23)). That method:
1. For overlapping versions, **only if the period was already generated**, creates leave work entries; the leave's type is resolved by `_get_interval_leave_work_entry_type` ([`hr_version.py:29`](../addons/hr_work_entry_holidays/models/hr_version.py#L29)).
2. Archives the attendance entries **fully inside** the leave and unlinks `leave_id` from those merely overlapping at the edges — both filtered to `state != 'validated'` ([`:86-87`](../addons/hr_work_entry_holidays/models/hr_leave.py#L86)), so **a leave can never overwrite a work entry already in a confirmed payslip**.

When several leaves cover one interval, global leaves (public holidays) win over personal leaves, and `bypassing_codes` (e.g. long-term sick) outrank globals ([`hr_version.py:42-58`](../addons/hr_work_entry_holidays/models/hr_version.py#L42)). Public-holiday codes `LEAVE110/210/280` are exempt from the on-public-holiday refusal ([`hr_leave.py:123`](../addons/hr_work_entry_holidays/models/hr_leave.py#L123)).

This work-entry priority does not decide employee leave balance: `include_public_holidays_in_duration=True` can still make the personal leave consume the holiday. Public-holiday CRUD reevaluates leave immediately but does not rebuild existing holiday work entries, and auto-refusal can indirectly deactivate validated leave entries. See [`public_holidays_flow.md`](public_holidays_flow.md) before changing a holiday around payroll.

Refuse / un-validate / user-cancel all call `_regen_work_entries()` ([`hr_leave.py:151`](../addons/hr_work_entry_holidays/models/hr_leave.py#L151)): archive every entry with `leave_id in self.ids`, recreate plain attendance entries. Setting a work entry to `cancelled` cascades the other way and refuses the linked leave ([`hr_work_entry.py:15`](../addons/hr_work_entry_holidays/models/hr_work_entry.py#L15)).

### The "cannot generate payslip" chain (the classic blocker)

A leave overlapping the period that is **approved but not fully validated**, or refused/draft, leaves the leave work entry alongside the attendance entry it could not archive → the day exceeds 24h or sits outside schedule → the entry becomes `conflict`. `generate_payslips()` then:
1. generates entries;
2. runs `_check_undefined_slots()` → calendar-gap UserError if any scheduled slot is uncovered;
3. re-runs `_check_if_error()` → **UserError listing each conflicting time interval + employee** ([`hr_payslip_run.py:384-391`](../enterprise/hr_payroll/models/hr_payslip_run.py#L384)).

**Resolution:** open the conflicting work entries and **Approve Time Off / Refuse Time Off** — buttons shown only when `state=='conflict' and leave_id` (Approve hidden once `leave_state=='validate'`), with the banner *"This work entry cannot be validated. There is a leave to approve (or refuse) at the same time."* ([`hr_work_entry_views.xml:11-28`](../enterprise/hr_work_entry_holidays_enterprise/views/hr_work_entry_views.xml#L11)). They call `action_approve_leave` / `action_refuse_leave` ([`hr_work_entry.py:25-34`](../addons/hr_work_entry_holidays/models/hr_work_entry.py#L25)). Approving a leave whose work entry is already `validated` is forbidden — `_compute_can_cancel` masks it ([`hr_leave.py:167`](../addons/hr_work_entry_holidays/models/hr_leave.py#L167)).

### Deferred time off (`hr_payroll_holidays`)

Solves the case where a leave is approved **after** its payslip is already validated/paid. Adds `payslip_state` on `hr.leave` ([`hr_leave.py:16`](../enterprise/hr_payroll_holidays/models/hr_leave.py#L16)):

| `payslip_state` | Label | Meaning |
|---|---|---|
| `normal` | To compute in next payslip | Default; picked up normally. |
| `done` | Computed in current payslip | Already reflected / defer resolved. |
| `blocked` | To defer to next payslip | Period already closed by a validated/paid slip; must be carried forward. |

**When a leave becomes `blocked`:** on validation, `_action_validate` ([`hr_leave.py:31`](../enterprise/hr_payroll_holidays/models/hr_leave.py#L31)) sets `blocked` when the leave overlaps a `validated`/`paid` payslip **and** no still-draft ("waiting") regular payslip also covers it. If a draft payslip still covers the period, the leave stays `normal` and is simply recomputed. Blocked leaves are kept **out** of work-entry generation (`_get_resource_calendar_leaves` filters out `payslip_state=='blocked'`, [`hr_version.py:10`](../enterprise/hr_payroll_holidays/models/hr_version.py#L10)) so they don't corrupt the closed period; instead a **"Leave to Defer"** activity is scheduled on the company's `deferred_time_off_manager` (Payroll settings → Deferred Time Off; falls back to admin) ([`hr_leave.py:99-108`](../enterprise/hr_payroll_holidays/models/hr_leave.py#L99), [`res_company.py:10`](../enterprise/hr_payroll_holidays/models/res_company.py#L10)).

**The payslip blocker "Employee has time off to defer":** `hr_payroll_holidays` overrides `_get_errors_by_slip` to add a **danger-level** error for any draft payslip overlapping a `blocked`, non-cancelled/refused leave ([`hr_payslip.py:17-35`](../enterprise/hr_payroll_holidays/models/hr_payslip.py#L17)). Being `danger`, it increments `error_count`, which blocks `compute_sheet` ([`hr_payslip.py:787`](../enterprise/hr_payroll/models/hr_payslip.py#L787)), `action_payslip_done` ([`:589`](../enterprise/hr_payroll/models/hr_payslip.py#L589)), and `action_payslip_paid` ([`:635`](../enterprise/hr_payroll/models/hr_payslip.py#L635)).

> **Note:** the worked-days recompute itself (`_compute_worked_days_line_ids`) does **not** raise on this error — it only raises the calendar-gap UserError via `_check_undefined_slots`. The to-defer error gates the compute/confirm/pay methods listed above, not the worked-day rebuild.

**Resolution — two paths:**
- **Defer to next Payslip** (manual): `activity_feedback` / the *Mark as Reported* server action sets `payslip_state='done'` ([`hr_leave.py:110`](../enterprise/hr_payroll_holidays/models/hr_leave.py#L110)), and HR creates the work entry by hand.
- **Report to Next Month** (automatic): `action_report_to_next_month()` ([`hr_leave.py:115`](../enterprise/hr_payroll_holidays/models/hr_leave.py#L115)) converts equivalent **draft** `WORK100` entries in the following month into the leave's type, splitting for half-day/hourly leaves, then sets `done`. Guard rails (all UserError): leave not blocked / no employee ([`:117`](../enterprise/hr_payroll_holidays/models/hr_leave.py#L117)); spans **>2 months** ([`:119`](../enterprise/hr_payroll_holidays/models/hr_leave.py#L119)); next month not generated / already validated ([`:138`](../enterprise/hr_payroll_holidays/models/hr_leave.py#L138)); no work entries linked ([`:140`](../enterprise/hr_payroll_holidays/models/hr_leave.py#L140)); not enough attendance entries next month to absorb the leave ([`:163`](../enterprise/hr_payroll_holidays/models/hr_leave.py#L163)).

> **Reactivity caveat:** `hr_payroll_holidays` overrides `_error_dependencies()`, but the base hook in this version is named `_issues_dependencies()` — so the override is never invoked and the to-defer error is **not** recomputed reactively on a leave state change. It is refreshed by `_recompute_payslips()` / `action_refresh_from_work_entries` and on the next `compute_sheet`. **Practical effect:** after deferring, you may need to refresh the payslip; it does not auto-clear.

**Editing a leave already inside a validated payslip:** re-activating or deleting a leave whose day is covered by a validated/paid regular payslip raises **UserError "The pay of the month is already validated with this day included…"** ([`_check_uncovered_by_validated_payslip`, hr_leave.py:188](../enterprise/hr_payroll_holidays/models/hr_leave.py#L188)). An approved leave can be sent back-to-confirm only if not inside a done/paid payslip ([`:24`](../enterprise/hr_payroll_holidays/models/hr_leave.py#L24)).

### Time-off dashboard warnings & filters

The leave form shows `payslip_state` as a `state_selection` widget and a **Report to Next Month** button when `payslip_state=='blocked' and state=='validate'` ([`hr_leave_views.xml:33-44`](../enterprise/hr_payroll_holidays/views/hr_leave_views.xml#L33)); the search adds a **To Defer** filter. Three dashboard warnings ([`hr_payroll_dashboard_warning_data.xml`](../enterprise/hr_payroll_holidays/data/hr_payroll_dashboard_warning_data.xml)): **Time Off To Defer**, **Time Off Without Joined Document**, **Time Off Not Related To An Allocation**.

> **Absent in this version:** there is **no** "allocation generated from payslips" and no recovery/extra-hours feature inside `hr_payroll_holidays`. The only extra-hours concept is `work_entry_type.is_extra_hours`, a base mechanism that excludes those hours from the hourly-rate denominator.

---

## Statuses, Errors & Warnings

This is the framework behind "all statuses and all blockers". A payslip is gated by **`error_count`**, not by `state` alone.

### Two status fields

| Field | Values | Source |
|---|---|---|
| `state` | draft / validated / paid / cancel | [`hr_payslip.py:66`](../enterprise/hr_payroll/models/hr_payslip.py#L66) |
| `state_display` | draft / validated("Done") / paid / cancel / **warning** / **error** | [`hr_payslip.py:76`](../enterprise/hr_payroll/models/hr_payslip.py#L76) |

`_compute_state_display` precedence ([`:239`](../enterprise/hr_payroll/models/hr_payslip.py#L239)): `error_count` → 'error', else `warning_count` → 'warning', else the real `state`. So a `draft` payslip can show a red **Error** or orange **Warning** badge.

### The issues system

`_compute_issues` ([`hr_payslip.py:1392`](../enterprise/hr_payroll/models/hr_payslip.py#L1392)) merges `_get_errors_by_slip` + `_get_warnings_by_slip` into a JSON `issues` field plus `error_count` / `warning_count`. Each issue has `message`, optional `action_text`+`action` (a clickable button), and `level` (`danger`=error, `warning`=warning). The form renders `issues` with the `actionable_warnings` widget ([`hr_payslip_views.xml:104`](../enterprise/hr_payroll/views/hr_payslip_views.xml#L104)). Recompute triggers come from `_issues_dependencies` ([`:1295`](../enterprise/hr_payroll/models/hr_payslip.py#L1295)); `hr_payroll_account` extends it with `struct_id.journal_id` ([`hr_payroll_account/.../hr_payslip.py:22`](../enterprise/hr_payroll_account/models/hr_payslip.py#L22)).

**Only `danger` issues block.** `_get_error_message` ([`:1407`](../enterprise/hr_payroll/models/hr_payslip.py#L1407)) joins only `danger` issues; `error_count` is what every guard checks. Warnings only colour the badge.

### Payslip transitions and exactly what gates each

| From → To | Method / button | Blocking conditions (raise) | Source |
|---|---|---|---|
| draft → draft (recompute lines) | `compute_sheet` | any `error_count` → ValidationError | [`:785`](../enterprise/hr_payroll/models/hr_payslip.py#L785) |
| draft → draft (full refresh) | `action_refresh_from_work_entries` | any slip `state != 'draft'` → UserError; skips `edited=True` slips; re-runs undefined-slots check | [`:804`](../enterprise/hr_payroll/models/hr_payslip.py#L804) |
| draft → validated | `action_payslip_done` ("Confirm" / "Create Draft Entry") | any `state=='cancel'` → ValidationError; any `error_count` → ValidationError; (account) any `state=='paid'` → ValidationError | [`:586`](../enterprise/hr_payroll/models/hr_payslip.py#L586), [`hr_payroll_account/.../hr_payslip.py:43`](../enterprise/hr_payroll_account/models/hr_payslip.py#L43) |
| draft → validated (combined) | `action_validate` | computes then confirms draft slips (inherits done guards) | [`:621`](../enterprise/hr_payroll/models/hr_payslip.py#L621) |
| validated/paid → paid | `action_payslip_paid` ("Mark as paid") | any `state not in (validated,paid)` → UserError; any `error_count` → ValidationError | [`:632`](../enterprise/hr_payroll/models/hr_payslip.py#L632) |
| paid → validated | `action_payslip_unpaid` ("Unpaid") | any `state != 'paid'` → UserError; forces the run back to `02_close` | [`:660`](../enterprise/hr_payroll/models/hr_payslip.py#L660) |
| draft/validated → cancel | `action_payslip_cancel` ("Cancel") | non-manager cancelling a `validated` slip → UserError; reverses/unlinks the move then re-drafts work entries | [`:625`](../enterprise/hr_payroll/models/hr_payslip.py#L625), [`hr_payroll_account/.../hr_payslip.py:38`](../enterprise/hr_payroll_account/models/hr_payslip.py#L38) |
| cancel → draft | `action_payslip_draft` ("Set to Draft") | no guard; clears the three payment-report fields; **does not touch `move_id`** | [`:516`](../enterprise/hr_payroll/models/hr_payslip.py#L516) |
| (delete) | ORM unlink | any `state not in (draft,cancel)` → UserError | [`:776`](../enterprise/hr_payroll/models/hr_payslip.py#L776) |

**Side effects of `action_payslip_done`:** flags negative-net (`credit_note=False` and NET<0 → `has_negative_net_to_report=True`, [`:598`](../enterprise/hr_payroll/models/hr_payslip.py#L598)); validates work entries for **regular** payslips only; PDF queue (context `payslip_generate_pdf` → inline `_generate_pdf` if `_direct`, else `queued_for_pdf=True` + triggers the cron, [`:612`](../enterprise/hr_payroll/models/hr_payslip.py#L612)).

**The `paid` write hook:** writing `state='paid'` triggers salary-attachment payment recording, grouped by deduction code ([`:476`](../enterprise/hr_payroll/models/hr_payslip.py#L476)). This is why the **Payment Report** path (which writes only `paid_date`, not `state`) never records attachment payments.

### Buttons visible per state

**Payslip form header** ([`hr_payslip_views.xml:74`](../enterprise/hr_payroll/views/hr_payslip_views.xml#L74)):

| Button | Visible when |
|---|---|
| Confirm / Create Draft Entry | `draft` AND `line_ids` exist |
| Compute Sheet (create / recompute) | `draft`, not `credit_note` |
| Mark as paid / Create Payment Report | `state=='validated'` |
| Pay (`action_register_payment`, account) | `validated` AND `move_id` AND **not** `batch_payroll_move_lines` |
| Revert (`refund_sheet`) | `state=='paid'`, not `credit_note` |
| Unpaid | `state=='paid'` |
| Set to Draft | `state=='cancel'` |
| Cancel | `state in (draft, validated)` |
| Export Payslip | only `is_superuser` (`_is_superuser()` AND `base.group_no_one`) |

With `hr_payroll_account`, base **Mark as paid** is forced invisible; the move smart button shows (Draft)/(Posted)/(Canceled). `journal_id` becomes required on the form.

**Pay-run kanban** ([`hr_payslip_run_views.xml:42`](../enterprise/hr_payroll/views/hr_payslip_run_views.xml#L42)): Compute (`01_ready` + empty payslips); Confirm (`01_ready` + none empty); Mark as Paid / Payment Report / Set to Draft (`02_close`); Revert (`03_paid`); Generate Payslips (state not in `02_close`/`03_paid`).

### Banner catalog (form alerts)

| Banner | Shows when | Buttons | Source |
|---|---|---|---|
| "The employee's data has been updated since this payslip was created." | `has_wrong_data` and not refunded/corrected/kept/refund | Adjust payslip / Keep it as is | [`hr_payslip_views.xml:91`](../enterprise/hr_payroll/views/hr_payslip_views.xml#L91) |
| "Employee's record is not the latest version for this payslip period." | `is_wrong_version` (same exclusions) | Adjust payslip / Keep it as is | [`:97`](../enterprise/hr_payroll/views/hr_payslip_views.xml#L97) |
| "There are previous payslips with a negative amount for a total of X to report." | `negative_net_to_report_display` | Report | [`:105`](../enterprise/hr_payroll/views/hr_payslip_views.xml#L105) |
| "Account Journal not configured on Structure" | (account) draft/validated slip whose struct has no `journal_id` | open structure | [`hr_payroll_account/.../hr_payslip.py:25`](../enterprise/hr_payroll_account/models/hr_payslip.py#L25) |
| `issues` actionable-warnings widget | `issues` non-empty | per-issue actions | [`:104`](../enterprise/hr_payroll/views/hr_payslip_views.xml#L104) |

**Wrong-version / wrong-data** (`_compute_is_wrong_version`, only on validated/paid, [`:398`](../enterprise/hr_payroll/models/hr_payslip.py#L398)): `is_wrong_version` = the slip's version differs from the employee's version effective at `date_from`; `has_wrong_data` = the version's `last_modified_date` is newer than the slip's `done_date` (data changed after confirmation). `action_adjust_payslip` opens the Payslip Correction wizard; `action_keep_wrong_version` just sets `keep_wrong_version=True` to silence the banner.

**Negative-net carry-forward:** `_compute_negative_net_to_report_display` ([`:334`](../enterprise/hr_payroll/models/hr_payslip.py#L334), only on `draft` slips) sums prior slips with `has_negative_net_to_report`, shows the banner, and schedules a **"Previous Negative Payslip to Report"** activity (the activity is scheduled here at [`:355`](../enterprise/hr_payroll/models/hr_payslip.py#L355), not in `action_payslip_done`). **Report** (`action_report_negative_amount`, [`:375`](../enterprise/hr_payroll/models/hr_payslip.py#L375)) adds the absolute amount to the deduction input (`hr_payroll.input_deduction`), recomputes, and clears the flags + activity.

### Danger errors (block) vs warnings (advisory)

**Errors — `_get_errors_by_slip`** ([`:1305`](../enterprise/hr_payroll/models/hr_payslip.py#L1305)):
- "No running contract over payslip period" — version's contract dates don't cover the period (and not a refund). Action opens the version.
- "The payslip's company doesn't match the batch's" — `company_id != payslip_run_id.company_id`.
- "Employee has time off to defer" — (holidays) blocked leave overlaps a draft slip.

**Warnings — `_get_warnings_by_slip`** ([`:1329`](../enterprise/hr_payroll/models/hr_payslip.py#L1329), advisory only):
- "The duration of the payslip is not accurate according to the structure type" — `use_worked_day_lines` and slip length ≠ schedule timedelta.
- "Similar payslips found" — another validated/paid slip with same (employee, struct, from, to); refunds/corrections excluded.
- "Missing bank account on employee" / "Untrusted bank accounts" — validated slips only.
- "Account Journal not configured on Structure" — (account).

> Dashboard-level warnings are a separate mechanism: `get_dashboard_warnings` safe-evals each `hr.payroll.dashboard.warning` record's code ([`:1820`](../enterprise/hr_payroll/models/hr_payslip.py#L1820)).

---

## Refund / Correction / Recompute

The payslip has a refund/correction sub-lifecycle independent of `state`.

| Action | Creates | Origin slip effect | Source |
|---|---|---|---|
| `refund_sheet` ("Revert") | a credit-note copy (`credit_note=True`, `edited=True`, draft, `is_refund_payslip=True`, `origin_payslip_id` set) with every worked-day and line amount **negated** | `is_refunded=True` | [`:723`](../enterprise/hr_payroll/models/hr_payslip.py#L723), [`:767`](../enterprise/hr_payroll/models/hr_payslip.py#L767) |
| `correct_sheet` | the refund **plus** a fresh corrected slip using the **current** version at `date_from`, then `compute_sheet` | `is_corrected=True` | [`:748`](../enterprise/hr_payroll/models/hr_payslip.py#L748), [`:771`](../enterprise/hr_payroll/models/hr_payslip.py#L771) |
| Correction wizard | groups the above into a new pay run; single vs all-affected slips | same | [`hr_payslip_correction_wizard.py:48`](../enterprise/hr_payroll/wizard/hr_payslip_correction_wizard.py#L48) |

The refund copy negates amounts **directly** (not recomputed), so manual edits carry through inverted. `related_payslip_ids`/`origin_payslip_id` drive the **Related Payslips** stat button.

**Custom component warning:** a custom one-time claim cannot simply exclude all correction slips. The refund already reverses the original custom salary line; if the recomputed correction contributes zero, valid custom pay disappears. Use immutable settlement lineage so the correction mirrors the original valid component and only explicit audited adjustments change it. Newly approved late sources belong to the next regular slip, not the correction.

**Refunds free work entries:** `_compute_has_payslip` on work entries excludes refunded slips ([`hr_work_entry.py:24`](../enterprise/hr_payroll/models/hr_work_entry.py#L24)), so the underlying entries become re-consumable by the corrected slip.

**Compute Sheet vs Recompute Whole Sheet:** `compute_sheet` re-derives `line_ids` only (respects `error_count`); `action_refresh_from_work_entries` wipes worked days + lines and rebuilds from work entries but **skips `edited=True` slips**.

### Edit Payslip Lines wizard (`hr.payroll.edit.payslip.lines.wizard`)

Entry point `action_edit_payslip_lines` ([`hr_payslip.py:1676`](../enterprise/hr_payroll/models/hr_payslip.py#L1676)): payroll officers only, forbidden on `validated` slips; it snapshots every salary line and worked-day line into transient wizard lines.

- **Recompute from a line** (`recompute_following_lines`, [`hr_payroll_edit_payslip_lines_wizard.py:18`](../enterprise/hr_payroll/wizard/hr_payroll_edit_payslip_lines_wizard.py#L18)): walks wizard lines by sequence up to and including the edited one, injecting each line's (possibly hand-edited) total into a fresh localdict (`localdict[code]`, `result_rules`, category rollup) and blacklisting those rules; drops all following lines; then calls `payslip._get_payslip_lines()` under context `force_payslip_localdict` + `prevent_payslip_computation_line_ids` so only the **following** rules re-evaluate on top of the edited values ([`hr_payslip.py:1118-1121`](../enterprise/hr_payroll/models/hr_payslip.py#L1118)). Editing a worked-day line funnels through `recompute_worked_days_lines`, which writes the summed worked-day amounts into the **first** salary line (assumed BASIC: amount=sum, qty=1, rate=100) and recomputes everything after it ([`:52-63`](../enterprise/hr_payroll/wizard/hr_payroll_edit_payslip_lines_wizard.py#L52)).
- **Save** (`action_validate_edition`, [`:65`](../enterprise/hr_payroll/wizard/hr_payroll_edit_payslip_lines_wizard.py#L65)): unlinks the real lines, writes the wizard lines back with context `payslip_no_recompute=True` plus `edited=True` and `compute_date=today` ([`:93-98`](../enterprise/hr_payroll/wizard/hr_payroll_edit_payslip_lines_wizard.py#L93)), and posts a chatter diff "This payslip has been manually edited by …" listing every changed field per line (YTD column skipped when the structure has no YTD).

**The `edited` flag** (set by the wizard and by refund copies): freezes worked-day `_compute_amount` ([`hr_payslip_worked_days.py:41`](../enterprise/hr_payroll/models/hr_payslip_worked_days.py#L41)) and makes `action_refresh_from_work_entries` skip the slip — but **`compute_sheet` ignores it** ([`hr_payslip.py:785`](../enterprise/hr_payroll/models/hr_payslip.py#L785) has no `edited` filter): clicking Compute Sheet on an edited slip regenerates all salary lines from the rules, discarding the manual line edits (only the frozen worked-day amounts survive).

**The `payslip_no_recompute` context** is subtler than its name: `line_ids` is a stored compute (`_compute_line_ids`, [`hr_payslip.py:411-420`](../enterprise/hr_payroll/models/hr_payslip.py#L411)) whose body **early-returns unless that context key is set** — so in normal use, changing inputs/worked days/dates never silently regenerates salary lines (you must Compute Sheet); code that sets the key opts in to an automatic draft-slip line rebuild. The wizard's write assigns `line_ids` explicitly, so its values are stored as-is.

---

## Structure Type (`hr.payroll.structure.type`)

Source: [`models/hr_payroll_structure_type.py`](../enterprise/hr_payroll/models/hr_payroll_structure_type.py)

The default payroll configuration attached to an employee version.

| Field | Purpose |
|---|---|
| `default_schedule_pay` | Default payment frequency. [`:28`](../enterprise/hr_payroll/models/hr_payroll_structure_type.py#L28) |
| `default_struct_id` | Default salary structure (also defines `is_regular`). |
| `default_work_entry_type_id` | Work entry type for regular attendance. |
| `wage_type` | `monthly` fixed or `hourly`. |

`hr.version` extends employee records with `schedule_pay`, `resource_calendar_id`, `contract_date_start/end`, `wage`, `contract_wage`, `wage_type`, `structure_type_id`, `work_entry_source`, `payroll_properties` ([`hr_version.py` enterprise](../enterprise/hr_payroll/models/hr_version.py)).

---

## Salary Structure (`hr.payroll.structure`)

Source: [`models/hr_payroll_structure.py`](../enterprise/hr_payroll/models/hr_payroll_structure.py)

The set of rules and input definitions applied to a payslip.

| Field | Purpose |
|---|---|
| `type_id` | Links to a structure type. |
| `rule_ids` | Salary rules evaluated. |
| `report_id` | PDF report template (else default `hr_payroll.action_report_payslip`). |
| `unpaid_work_entry_type_ids` | Work entry types considered **unpaid** (worked-day amount = 0). |
| `use_worked_day_lines` | If false, no worked-day lines and `paid_amount` falls back to contract wage. |
| `input_line_type_ids` | Which input types can be selected on payslips for this structure. |
| `ytd_computation` | Adds year-to-date values. |
| `journal_id` | (accounting) **Salary Journal** — `company_dependent`. Required in the account view; the first accounting gate. [`hr_payroll_account/.../hr_payroll_structure.py:15`](../enterprise/hr_payroll_account/models/hr_payroll_structure.py#L15) |

> The journal is **constrained to the company currency** — `_check_journal_id` raises ValidationError if they differ ([`hr_payroll_structure.py:19-25`](../enterprise/hr_payroll_account/models/hr_payroll_structure.py#L19)). There is no foreign-currency payroll posting. You also cannot delete a journal linked to a structure ([`account_journal.py:10-14`](../enterprise/hr_payroll_account/models/account_journal.py#L10)).

### Country scoping and rule seeding

- `country_id` on the structure defaults to the company country ([`hr_payroll_structure.py:46`](../enterprise/hr_payroll/models/hr_payroll_structure.py#L46)). It is not just cosmetic: a global **record rule** hides structures whose country is not among the logged-in companies' countries ([`ir_rule_hr_payroll_structure_multi_company`, hr_payroll_security.xml:51](../enterprise/hr_payroll/security/hr_payroll_security.xml#L51)). The same country record-rule pattern applies to input types, rule parameters (+values), salary rules (via `struct_id.country_id`), and dashboard warnings ([`hr_payroll_security.xml:57-122`](../enterprise/hr_payroll/security/hr_payroll_security.xml#L57)).
- A **new structure is seeded with copies of the default structure's rules** — `rule_ids` default is `copy_data` of every rule of `hr_payroll.default_structure` ([`_get_default_rule_ids`, :14-20](../enterprise/hr_payroll/models/hr_payroll_structure.py#L14)). That default set is BASIC / GROSS / DEDUCTION / ATTACH_SALARY / ASSIG_SALARY / CHILD_SUPPORT / REIMBURSEMENT / NET ([`hr_salary_rule_data.xml`](../enterprise/hr_payroll/data/hr_salary_rule_data.xml)).
- The payslip PDF `report_id` domain prefers `l10n_<company country>` reports and falls back to generic `hr_payroll` ones ([`_get_domain_report`, :22-39](../enterprise/hr_payroll/models/hr_payroll_structure.py#L22)).
- Structure **types** have no country field of their own, but creating/writing one under context `payroll_check_country` validates the country against logged-in companies ([`hr_payroll_structure_type.py:48-63`](../enterprise/hr_payroll/models/hr_payroll_structure_type.py#L48)).

---

## Salary Rules (`hr.salary.rule`)

Source: [`models/hr_salary_rule.py`](../enterprise/hr_payroll/models/hr_salary_rule.py)

One computation step → one `hr.payslip.line`, updates category totals, and becomes available to later rules.

| Field | Purpose |
|---|---|
| `sequence` / `code` / `category_id` | Execution order / formula symbol / category for totals (BASIC/GROSS/NET/DED/ALW). |
| `condition_select` | Whether the rule runs: `none` / `input` / `property_input` / `python` / `domain` ([`_satisfy_condition`, :193](../enterprise/hr_payroll/models/hr_salary_rule.py#L193)). |
| `amount_select` | How the amount is computed: `fix` / `percentage` / `input` / `code` ([`_compute_rule`, :156](../enterprise/hr_payroll/models/hr_salary_rule.py#L156)). |
| `appears_on_employee_cost_dashboard` | Included in employer cost total. |
| `account_debit` / `account_credit` | (accounting) `company_dependent` accounts. |
| `not_computed_in_net` | (accounting) "Excluded from Net" — pulled out of the NET account line. |
| `split_move_lines` | (accounting) one move line per distinct payslip-line name. |
| `employee_move_line` | (accounting) put the employee partner/bank on the line; enables per-bank split. |
| `analytic_distribution` | (accounting) analytic for generated move lines. |

Each computed rule produces `total = amount * quantity * rate / 100.0` ([`_get_payslip_line_total`, :1046](../enterprise/hr_payroll/models/hr_payslip.py#L1046)).

### Localdict (salary-rule Python environment)

[`_get_localdict()`](../enterprise/hr_payroll/models/hr_payslip.py#L1010):

| Variable | Meaning |
|---|---|
| `payslip` / `employee` / `version` | Current records. |
| `worked_days` | Dict by work-entry-type code, e.g. `worked_days['WORK100']`. |
| `inputs` | Dict by input-type code, e.g. `inputs['DEDUCTION']`. |
| `property_inputs` | Version + payslip properties merged (payslip overrides version). |
| `categories` / `rules` / `result_rules` | Running totals; `categories['CODE']` rolls up through the `hr.salary.rule.category` parent hierarchy. |
| `same_type_input_lines` | Dict code → input recordset, only for codes with **multiple** input lines (drives the once-per-line rule evaluation). |
| `float_round`, `float_compare`, `relativedelta`, `ceil`, `floor`, `date`, `datetime`, `defaultdict`, `UserError` | Helpers ([`_get_base_local_dict`, hr_payslip.py:997](../enterprise/hr_payroll/models/hr_payslip.py#L997)). |

> There is **no** bare `rule_parameter()` function in the base localdict — rules read date-effective parameters through `payslip._rule_parameter('CODE')` ([`hr_payslip.py:924`](../enterprise/hr_payroll/models/hr_payslip.py#L924)). Localizations may inject their own shortcuts. `worked_days` is a **plain dict** keyed by work-entry-type code — `worked_days['WORK100']` raises KeyError if the line is absent; use `.get()`.

### Default rule chain

| Rule | Code | Formula |
|---|---|---|
| Basic Salary | `BASIC` | `result = payslip.paid_amount` |
| Gross/Taxable | `GROSS` | `result = categories['BASIC'] + categories['ALW']` |
| Deductions | `DEDUCTION`, `ATTACH_SALARY`, … | run only if matching input exists |
| Reimbursement | `REIMBURSEMENT` | run only if matching input exists |
| Net Salary | `NET` | `result = categories['BASIC'] + categories['ALW'] + categories['DED']` |

If a payslip has multiple input lines with the same code, the matching rule is evaluated once per input line (multiple payslip lines), then an aggregator is restored in `inputs[code]` ([`hr_payslip.py:1133`](../enterprise/hr_payroll/models/hr_payslip.py#L1133)).

### Salary rule categories

Categories are `hr.salary.rule.category` records such as `BASIC`, `ALW`, `DED`, `GROSS`, and `NET`. They do not come from work entries. They come from the **Category** field on each salary rule.

As rules run in sequence, each computed rule total is added to its category and parent categories via `_sum_salary_rule_category()` ([`hr_salary_rule_category.py:36`](../enterprise/hr_payroll/models/hr_salary_rule_category.py#L36), called from [`hr_payslip.py:1147`](../enterprise/hr_payroll/models/hr_payslip.py#L1147)). Later rules can read those totals in Python formulas through `categories['CODE']`.

Example:

```python
result = categories['BASIC'] + categories['ALW']
```

That formula means: take the already-computed Basic category total plus the already-computed Allowance category total. If an allowance rule did not run yet, or has total 0, `categories['ALW']` is 0.

---

## Salary Inputs

Two separate "input" systems, not interchangeable:
1. **Other Inputs** — `hr.payslip.input`, the Salary Inputs tab.
2. **Property Inputs** — JSON values on `hr.version.payroll_properties` / `hr.payslip.payslip_properties`, read via `property_inputs`.

### Input Type (`hr.payslip.input.type`) and Payslip Input (`hr.payslip.input`)

`hr.payslip.input` is a dumb value row: an input type + `amount` + optional `name` (Description); `code` is related from the type ([`hr_payslip_input.py:19`](../enterprise/hr_payroll/models/hr_payslip_input.py#L19)). Allowed types come from `payslip.struct_id.input_line_type_ids` (domain via the related `_allowed_input_type_ids`, [`hr_payslip_input.py:17-18`](../enterprise/hr_payroll/models/hr_payslip_input.py#L17)). Input rules read `inputs['CODE'].amount`.

Type flags that change behavior ([`hr_payslip_input_type.py`](../enterprise/hr_payroll/models/hr_payslip_input_type.py)):

| Flag | Effect |
|---|---|
| `struct_ids` | Restricts which structures may receive this input via a salary adjustment; empty = all ([`:14`](../enterprise/hr_payroll/models/hr_payslip_input_type.py#L14), enforced in `_compute_input_line_ids`, [`hr_payslip.py:299`](../enterprise/hr_payroll/models/hr_payslip.py#L299)). |
| `available_in_attachments` | "Available in adjustments" — makes the type selectable on `hr.salary.attachment` ([domain, `hr_salary_attachment.py:49`](../enterprise/hr_payroll/models/hr_salary_attachment.py#L49)) and marks its payslip input lines as attachment-managed (auto-removed and recreated on every input recompute, [`hr_payslip.py:286-293`](../enterprise/hr_payroll/models/hr_payslip.py#L286)). |
| `is_quantity` | Value is a count, not money; attachment payment recording then sums line `quantity` instead of `total` ([`hr_payslip.py:473`](../enterprise/hr_payroll/models/hr_payslip.py#L473)). |
| `default_no_end_date` | New salary adjustments of this type default to `duration_type='unlimited'` ([`hr_salary_attachment.py:136-139`](../enterprise/hr_payroll/models/hr_salary_attachment.py#L136)) — this is how Child Support behaves. |

Guards: an input type shipped by a module (with an XML id) cannot be deleted, only archived ([`:27-33`](../enterprise/hr_payroll/models/hr_payslip_input_type.py#L27)); archiving is blocked while a running salary adjustment uses the type ([`:35-38`](../enterprise/hr_payroll/models/hr_payslip_input_type.py#L35)).

Base data ships five types ([`hr_payslip_input_type_data.xml`](../enterprise/hr_payroll/data/hr_payslip_input_type_data.xml)): `DEDUCTION`, `REIMBURSEMENT`, plus three attachment-enabled ones — `ATTACH_SALARY` (Attachment of Salary), `ASSIG_SALARY` (Assignment of Salary), `CHILD_SUPPORT` (unlimited by default).

An input row does **not** change Worked Days and does **not** automatically change Net Salary. It changes the final result only if a salary rule in the structure uses the same input code. For rules with `amount_select='input'`, `_compute_rule()` returns `inputs[amount_other_input_id.code].amount`; if the code is missing, it returns 0 ([`hr_salary_rule.py:182`](../enterprise/hr_payroll/models/hr_salary_rule.py#L182)). This is why adding a `BONUS` input should create/change a `BONUS` salary computation line, not the Attendance line on the Worked Days tab.

**Line naming:** when an input-based rule produces a payslip line, the line's name is the input's Description if set (`get_rule_name`, [`hr_payslip.py:1089-1096`](../enterprise/hr_payroll/models/hr_payslip.py#L1089)); the default deduction/attachment rules also set `result_name = inputs['CODE'].name` in their Python ([`hr_salary_rule_data.xml:60`](../enterprise/hr_payroll/data/hr_salary_rule_data.xml#L60)). This is why a payslip line can show the adjustment's note instead of the rule name.

**Multiple inputs, same code:** `_get_localdict` keeps them in `same_type_input_lines`; the matching rule is evaluated once per line (one payslip line each), then `inputs[code]` is restored to an aggregator proxy whose `amount` is the sum, `name` the joined names, `sequence` the min ([`__get_aggregator_hr_payslip_input_model`, hr_payslip.py:1747](../enterprise/hr_payroll/models/hr_payslip.py#L1747)).

### Ways input lines are created

| Source | How |
|---|---|
| Manual entry | Payroll user adds rows on the Salary Inputs tab. |
| Salary Adjustments | `_compute_input_line_ids()` sums open `hr.salary.attachment` records into one line per type. |
| `hr_payroll_expense` | one `EXPENSES` line from linked employee-paid expenses. |
| `hr_payroll_sale_commission` | one line per commission plan with `commission_payroll_input` set. |
| Localization / custom | module logic adds lines before `compute_sheet()`. |

`_compute_input_line_ids` recomputes on `@api.depends('employee_id','version_id','struct_id','date_from','date_to')` ([`hr_payslip.py:284`](../enterprise/hr_payroll/models/hr_payslip.py#L284)), so editing any of those re-pulls expenses/commissions. See [Input Integrations](#input-integrations).

### Salary Adjustments (`hr.salary.attachment`)

Garnishments, child support, loan repayments: recurring/limited deductions that auto-inject input lines. Model is `hr.salary.attachment` (UI label "Salary Adjustment", `_rec_name` is the free-text `description`, [`hr_salary_attachment.py:17`](../enterprise/hr_payroll/models/hr_salary_attachment.py#L17)).

**Shape of the record:**
- `employee_ids` is a **Many2many** — one adjustment can target several employees ([`:36`](../enterprise/hr_payroll/models/hr_salary_attachment.py#L36)). Multi-employee records are entry convenience only: payment recording refuses them; `action_split` clones the record per employee (copying `paid_amount` to each!) and closes+deletes the original ([`:276-319`](../enterprise/hr_payroll/models/hr_salary_attachment.py#L276)).
- `other_input_type_id` must be an input type with `available_in_attachments` ([`:44-50`](../enterprise/hr_payroll/models/hr_salary_attachment.py#L44)) — this decides which salary rule will consume it.
- `duration_type`: `one` (one-time), `limited` (fixed total), `unlimited` (runs until closed manually). Computed to `unlimited` when the type has `default_no_end_date` ([`:136-139`](../enterprise/hr_payroll/models/hr_salary_attachment.py#L136)).
- Money fields: `monthly_amount` (amount per payslip), `total_amount` (computed default = months in range × monthly, editable, [`:146-157`](../enterprise/hr_payroll/models/hr_salary_attachment.py#L146)), `paid_amount` (running counter), `remaining_amount` = `max(0, total - paid)` — or just `monthly_amount` for unlimited ([`:212-218`](../enterprise/hr_payroll/models/hr_salary_attachment.py#L212)), `active_amount` = `min(monthly, remaining)` — the amount actually injected this period ([`:233-236`](../enterprise/hr_payroll/models/hr_salary_attachment.py#L233)). `occurrences` = ceil(total/monthly); `date_estimated_end` extrapolates from the remaining amount ([`:220-226`](../enterprise/hr_payroll/models/hr_salary_attachment.py#L220)).
- `is_refund` ("Negative Value") flips the injected sign — usable for recurring *additions* ([`_get_active_amount`, :412](../enterprise/hr_payroll/models/hr_salary_attachment.py#L412)).

**Injection into payslips** (`_compute_input_line_ids`, [`hr_payslip.py:284-310`](../enterprise/hr_payroll/models/hr_payslip.py#L284)): on any change of employee/version/struct/dates, the payslip drops every attachment-typed input line and rebuilds them from the employee's adjustments that are `open`, overlap the period (`date_start <= slip.date_to` and no `date_end` or `date_end >= slip.date_from`), and whose input type allows the slip's structure. One line **per input type** with `amount = sum of active_amount` (sign-flipped for `is_refund` and for credit notes); the line name is the joined descriptions. The reverse link `payslip.salary_attachment_ids` is recomputed from those input lines ([`:312-327`](../enterprise/hr_payroll/models/hr_payslip.py#L312)).

**Lifecycle (event-driven, no cron):** only two states — `open` (Running) and `close` (Closed) ([`:105`](../enterprise/hr_payroll/models/hr_salary_attachment.py#L105)); `action_open` reopens and clears `date_end` ([`:321`](../enterprise/hr_payroll/models/hr_salary_attachment.py#L321)). When a payslip is written to `paid`, the payslip `write` hook ([`hr_payslip.py:476-490`](../enterprise/hr_payroll/models/hr_payslip.py#L476)) groups the slip's attachments by input-type code, takes the **computed payslip line totals** (not the input amounts) and calls `record_payment` ([`:371`](../enterprise/hr_payroll/models/hr_salary_attachment.py#L371)), which distributes the paid amount (no-total/monthly ones like child support first, then fixed-total by `date_estimated_end`), increments `paid_amount`, posts chatter, and calls `action_close()` the moment `remaining_amount` hits 0 ([`:385`](../enterprise/hr_payroll/models/hr_salary_attachment.py#L385)); close stamps `date_end=today` ([`:270`](../enterprise/hr_payroll/models/hr_salary_attachment.py#L270)).

> **`unlimited` attachments never auto-close** — `remaining_amount` equals `monthly_amount` (no total to exhaust); close them manually. `record_payment` raises **UserError** on multi-employee attachments — split first via `action_split` ([`:387`](../enterprise/hr_payroll/models/hr_salary_attachment.py#L387)).

**Delete guards:** cannot delete an `open` attachment ([`:359`](../enterprise/hr_payroll/models/hr_salary_attachment.py#L359)) or one already linked to a payslip ([`:366`](../enterprise/hr_payroll/models/hr_salary_attachment.py#L366)). DB CHECK constraints enforce `monthly_amount>0`, `total_amount>0 AND >=monthly_amount` (waived for `unlimited`), `remaining_amount>=0`, `date_start<=date_end` ([`:19-34`](../enterprise/hr_payroll/models/hr_salary_attachment.py#L19)). An advisory "similar attachment found" warning exists ([`:238`](../enterprise/hr_payroll/models/hr_salary_attachment.py#L238)).

**Employee-side visibility:** the employee form exposes `salary_attachment_ids` and a computed `monthly_running_attachments` (sum of open adjustments' monthly amounts), both gated to `hr_payroll.group_hr_payroll_user` ([`hr_employee.py:17-23`](../enterprise/hr_payroll/models/hr_employee.py#L17), [`:67-70`](../enterprise/hr_payroll/models/hr_employee.py#L67)).

---

## Accounting Integration (`hr_payroll_account`)

Source: [`enterprise/hr_payroll_account/`](../enterprise/hr_payroll_account/)

This module translates computed payslip lines into account move lines at confirmation. It does not change the computation engine.

### When the journal entry is created — and why it stays draft

`action_payslip_done` (override) calls `_action_create_account_move` only for slips with a `journal_id` ([`hr_payslip.py:43`](../enterprise/hr_payroll_account/models/hr_payslip.py#L43)). **The move is created but never posted** — there is no `action_post` anywhere in this module; the final step is `self.env['account.move'].sudo().create(values)` ([`_create_account_move`, :275](../enterprise/hr_payroll_account/models/hr_payslip.py#L275), invoked by `_action_create_account_move` at [`:118`](../enterprise/hr_payroll_account/models/hr_payslip.py#L118)). The buttons are literally "Create Draft Entry". The accountant must post it; this is why `action_register_payment` re-checks `move.state == 'posted'`.

UI label note: with only payroll, the draft button is **Validate** / **Confirm**. With `hr_payroll_account`, the same confirmation action is shown as **Create Draft Entry** because it may also create a draft accounting move. The label does not prove salary-rule accounts are configured; the move can still have an empty **Journal Items** tab if the rules have no debit/credit accounts.

**Gate conditions** ([`:64`](../enterprise/hr_payroll_account/models/hr_payslip.py#L64)): a slip gets a move only if `state=='validated'`, **no existing `move_id`** (moves are never regenerated), and `struct_id.journal_id` is set. A structure with no journal silently produces no move (and raises the journal-not-configured warning). When called from a slip in a run where `_are_payslips_ready()`, the method pulls in the whole batch's slips ([`:59-61`](../enterprise/hr_payroll_account/models/hr_payslip.py#L59)).

### Batching (`company.batch_payroll_move_lines`)

| Mode | Grouping | Result |
|---|---|---|
| Batched (`True`) | `{journal_id: {date: slips}}`, slips merged per key ([`:71-74`](../enterprise/hr_payroll_account/models/hr_payslip.py#L71)) | **one move per (journal, date) group** for all slips; lines with the same name/account/analytic/tags merged; **no per-employee partner/bank** (anonymized). The **run** gets `move_id` ([`:121`](../enterprise/hr_payroll_account/models/hr_payslip.py#L121)). |
| Per-slip (`False`, default) | list of single-slip groups ([`:76-80`](../enterprise/hr_payroll_account/models/hr_payslip.py#L76)) | **one move per payslip**; employee partner/bank applied. |

The date key is `slip.date or fields.Date.end_of(slip.date_to, 'month')` ([`:73`](../enterprise/hr_payroll_account/models/hr_payslip.py#L73)). The move `ref` is the month formatted "%B %Y", `narration` accumulates "<id> - <employee>" per slip. After creation, the resolved `date` is written back onto the slips ([`:120`](../enterprise/hr_payroll_account/models/hr_payslip.py#L120)).

### Which payslip lines become journal items

`_prepare_slip_lines` ([`:166`](../enterprise/hr_payroll_account/models/hr_payslip.py#L166)) iterates lines **that have a `category_id`**:
1. `amount = line.total`.
2. **NET special-casing:** when `line.code == 'NET'`, any rule flagged `not_computed_in_net` has its total removed from NET ([`:172-178`](../enterprise/hr_payroll_account/models/hr_payslip.py#L172)). A rule marked **Excluded from Net** must carry its own debit/credit accounts to land in the move — otherwise its value disappears entirely.
3. Lines whose adjusted amount is zero (to Payroll precision) are skipped ([`:179`](../enterprise/hr_payroll_account/models/hr_payslip.py#L179)).
4. A debit item only if the rule has `account_debit`; a credit item only if it has `account_credit`. A rule with no accounts contributes nothing — hence sparse/empty moves when accounts are unset.

**Storno (credit notes):** if `company.account_storno` AND the slip is a `credit_note`, debit/credit signs are flipped (negative on the original side) instead of mirrored ([`:186`](../enterprise/hr_payroll_account/models/hr_payslip.py#L186), [`:203`](../enterprise/hr_payroll_account/models/hr_payslip.py#L203)). `account_storno` is a company field ([`company.py:242`](../addons/account/models/company.py#L242)) computed by `_compute_account_storno` ([`:460-462`](../addons/account/models/company.py#L460)) — on by default for storno-mandatory countries (BA, CN, CZ, HR, PL, RO, RS, RU, SI, SK, UA), optional for AT/CH/DE/IT ([country sets, :53-54](../addons/account/models/company.py#L53)).

### Line merging vs splitting

`merge_amounts = batch_payroll_move_lines or not rule.employee_move_line` ([`:183`](../enterprise/hr_payroll_account/models/hr_payslip.py#L183)). When merging, `_get_existing_lines` ([`:254`](../enterprise/hr_payroll_account/models/hr_payslip.py#L254)) folds the new debit/credit into an existing line **only if** same name, same account, compatible sign, **matching analytic distribution**, and matching tax tags. `split_move_lines` ("Split on names") sets the line name to `line.name` instead of `salary_rule_id.name` ([`:139`](../enterprise/hr_payroll_account/models/hr_payslip.py#L139)); since the name is part of the merge key, enabling it yields one line per distinct payslip-line name.

### Employee partner + per-bank split (`_prepare_line_values`)

[`:125`](../enterprise/hr_payroll_account/models/hr_payslip.py#L125): if **not batched** and the rule has `employee_move_line`, `partner_id = employee.work_contact_id`; otherwise `line.partner_id`. The employee appears on lines only when batching is off (the point of "anonymize" in the setting). If additionally `employee.has_multiple_bank_accounts`, the line is **exploded into one line per bank account** via `compute_salary_allocations` ([`:132-151`](../enterprise/hr_payroll_account/models/hr_payslip.py#L132)), each tagged with `employee_bank_account_id` ([`account_move_line.py:7`](../enterprise/hr_payroll_account/models/account_move_line.py#L7)) — the field the register wizard keys on for one-payment-per-bank.

### Analytic distribution

Every line sets `analytic_distribution = rule.analytic_distribution or version.analytic_distribution` ([`:147`](../enterprise/hr_payroll_account/models/hr_payslip.py#L147)) — the rule wins, else the version's. Both models mix in `analytic.mixin`. Differing analytics force separate move lines (the merge check refuses to merge them).

### Rounding adjustment line

After summing debit/credit across the group's lines, if they differ at Payroll precision a single balancing line is injected by `_prepare_adjust_line` ([`:222`](../enterprise/hr_payroll_account/models/hr_payslip.py#L222)): named "Adjustment Entry", no partner, on `journal_id.default_account_id`. **If that account is empty it raises UserError** "The Expense Journal … has not properly configured the default Account!" ([`:225`](../enterprise/hr_payroll_account/models/hr_payslip.py#L225)). This absorbs rounding drift (e.g. multi-bank percentage allocations).

### Accounting date & multi-company/currency

Date = `slip.date or end_of(date_to, 'month')`; `slip.date` ("Date Account") is read-only once the slip leaves draft. `journal_id`, `account_debit`, `account_credit` are all `company_dependent`, and grouping is by journal id, so **cross-company slips never share a move**. Move lines set only `debit`/`credit` (never `currency_id`/`amount_currency`) — always company currency.

### Move lifecycle on cancel / set-to-draft (the part users get blocked by)

`action_payslip_cancel` (override) grabs `move_id`, calls `moves.sudo()._unlink_or_reverse()` **before** super ([`:38`](../enterprise/hr_payroll_account/models/hr_payslip.py#L38)). `_unlink_or_reverse` ([`account_move.py:5458`](../addons/account/models/account_move.py#L5458)) routes each move:

| Bucket | Condition | Move outcome |
|---|---|---|
| **Unlink** | `_can_be_unlinked()` and not audit-protected | reset to draft then `unlink()` — **deleted**, `move_id` cleared |
| **Cancel** | unlinkable but audit-trail protected | `button_cancel()` — kept as cancelled for audit |
| **Reverse** | not unlinkable (hash / lock date / caba) | `_reverse_moves(cancel=True)` — reversing entry created, original kept |

`_can_be_unlinked` returns false (→ reverse) for hashed moves, moves on/before the lock date, or posted caba/exchange entries; `_is_protected_by_audit_trail` is true for `posted_before` + `company.restrictive_audit_trail`. **Net behaviour (confirmed by tests):** a draft never-posted move is deleted; a posted move on a hashed journal is reversed; a plain posted move with no hash/lock is still reset-to-draft and deleted.

> **Set-to-Draft does NOT touch the move.** There is no `action_payslip_draft` override in `hr_payroll_account` — base `action_payslip_draft` only clears payment-report fields ([`hr_payslip.py:516`](../enterprise/hr_payroll/models/hr_payslip.py#L516)). So re-drafting keeps `move_id`, and re-confirming will **not** create a second move (the create gate skips slips that already have a `move_id`). To actually drop the move, **cancel** the slip.

---

## Payment Paths, Report, and ISO20022

### Three paid-state paths — not equivalent

| Path | Writes `paid_date`? | Writes `state='paid'`? | Needs `move_id`? | Needs reconciliation? | Source |
|---|---|---|---|---|---|
| Payment Report wizard (CSV/SEPA/Swiss) | yes (`effective_date`) | **no** | no | no | [`hr_payroll_payment_report_wizard.py:90`](../enterprise/hr_payroll/wizard/hr_payroll_payment_report_wizard.py#L90) |
| Manual **Mark as Paid** | yes (`today`) | yes | **no** | no | [`hr_payslip.py:632`](../enterprise/hr_payroll/models/hr_payslip.py#L632) |
| **Register Payment** + reconcile | yes (`payment_date`) | yes, **only if residual is zero** | yes (posted) | yes | [`account_payment_register.py:36`](../enterprise/hr_payroll_account/wizard/account_payment_register.py#L36) |

- **Payment Report** writes `paid_date` to all selected slips and the bank file; it never sets `state` and never creates an `account.payment` — so a slip can show a Payment Date while still `validated`, and salary attachments are **not** recorded (no `state='paid'` write).
- **Mark as Paid** flips `validated`→`paid`, requires no move/reconciliation (why a paid slip can have no journal entry), and **does** record salary-attachment payments. With `hr_payroll_account` the button is hidden on the form; the iso20022 layer re-shows it secondary.
- **Register Payment** is the only path through Accounting; it writes `paid` only if **all** move-line residuals are zero.

### Payment report fields

Bank-file metadata on **both** payslip and run (the run additionally has `payment_report_format`):

| Field | Payslip | Run | Cleared by |
|---|---|---|---|
| `payment_report` (Binary) / `payment_report_filename` / `payment_report_date` | yes | yes | set-to-draft |
| `payment_report_format` | **no** | yes | set-to-draft |

There is no `payment_report_state`. On the payslip, `action_payslip_draft` blanks the three payslip fields + sets `state='draft'` ([`hr_payslip.py:516-527`](../enterprise/hr_payroll/models/hr_payslip.py#L516)).

### Export formats

`export_format` is extended by `selection_add`. Base ships **CSV only** (default); `hr_payroll_account_iso20022` adds **SEPA** (becomes default for EUR companies) and **Swiss ISO20022**:

| Value | Label | Added by | File |
|---|---|---|---|
| `csv` | CSV | base `hr_payroll` | `.csv` |
| `sepa` | SEPA | iso20022 | `.xml` |
| `iso20022_ch` | Swiss ISO20022 | iso20022 | `.xml` |

The SEPA default only applies when `company.currency_id.name == 'EUR'` ([`hr_payslip_run.py:7`](../enterprise/hr_payroll_account_iso20022/models/hr_payslip_run.py#L7)); non-EUR companies land on CSV. The **CSV** writer ([`:31`](../enterprise/hr_payroll/wizard/hr_payroll_payment_report_wizard.py#L31)) emits one row per (payslip, bank account) with columns *Sequence, Payment Date, Report Date, Payslip Period, Employee name (holds the employee's `legal_name`), Bank account, BIC, Amount to pay* ([header :34](../enterprise/hr_payroll/wizard/hr_payroll_payment_report_wizard.py#L34)).

### SEPA / batch_booking

`_create_sepa_binary` ([`:15`](../enterprise/hr_payroll_account_iso20022/wizard/hr_payroll_payment_report_wizard.py#L15)) builds payment dicts from `slip._get_payments_vals()` for slips that are `validated` and `net_wage > 0`, then calls `journal.create_iso20022_credit_transfer(..., batch_booking=True)`. `batch_booking=True` writes one `<BtchBookg>true</BtchBookg>` per PmtInf block ([`account_journal.py:161`](../enterprise/account_iso20022/models/account_journal.py#L161)) — the bank posts **one consolidated debit** for the batch while each employee still receives an individual credit. Payments group into PmtInf blocks by `(required_payment_date, currency, priority)`; `required_payment_date = max(payment_date, today)` (back-dates silently floored); priority is `HIGH` for BE else `NORM`. A multi-bank employee produces multiple transactions.

> This file export creates and reconciles **nothing**. A bank integration needing reconciled `account.payment` records (e.g. an API-driven bank) must use the **Register Payment** path instead.

### Register Payment grouping & reconciliation

`action_register_payment` ([`:277`](../enterprise/hr_payroll_account/models/hr_payslip.py#L277)) opens `account.payment.register` on the move lines with context `payment_consider_partner=True`. `_get_line_batch_key()` override ([`account_payment_register.py:11`](../enterprise/hr_payroll_account/wizard/account_payment_register.py#L11)): if a line carries `employee_bank_account_id` → that bank becomes `partner_bank_id` (one payment per employee bank); else, with `payment_consider_partner`, fall back to the partner's first bank by sequence. Pass `group_payment=True` to merge one employee's multiple payable lines into one payment.

`_reconcile_payments` ([`:24`](../enterprise/hr_payroll_account/wizard/account_payment_register.py#L24), only under `hr_payroll_payment_register` context) posts a chatter link, then writes `state='paid'` + `paid_date` **only if every move-line residual is zero** ([`:36`](../enterprise/hr_payroll_account/wizard/account_payment_register.py#L36)):

| Situation | Result |
|---|---|
| Partial payment (amount < net) | stays **`validated`**; payment exists, partially reconciled |
| Multi-bank, only one account paid | stays `validated` until **all** payable lines reconcile |
| Full payment | becomes `paid` |
| Currency rounding leaves a sub-cent residual | stays `validated` |

> The chatter "Payment done at …" and the origin link are posted **regardless** of the residual test — chatter saying a payment was made does not imply `state='paid'`. Undoing a Register-Payment `paid` via `action_payslip_unpaid()` flips it back to `validated` but does **not** un-reconcile the `account.payment` (do that in Accounting). Payroll widens valid payment account types to include `liability_current` under context ([`account_payment.py:14`](../enterprise/hr_payroll_account/models/account_payment.py#L14)).

**Salary allocation split** `compute_salary_allocations()` ([`hr_payslip.py:2190`](../enterprise/hr_payroll/models/hr_payslip.py#L2190)): single account → whole net to `primary_bank_account_id`; multiple → fixed amounts first, then percentages, with the **last** percentage account absorbing the rounding remainder; raises **ValidationError** "Allocated amounts surpass/are less than the net salary" if they don't reconcile ([`:2211`](../enterprise/hr_payroll/models/hr_payslip.py#L2211)). The same split feeds both move lines and the SEPA/CSV export.

> **Known stale check:** `hr_payroll_account`'s own `_perform_checks()` IBAN validation filters `state == "done"` ([`hr_payroll_payment_report_wizard.py:23`](../enterprise/hr_payroll_account/wizard/hr_payroll_payment_report_wizard.py#L23)), but the state value is `validated` (label "Done") — so this check **never fires**. The active IBAN/SEPA validation is the iso20022 wizard's `_perform_checks()` override ([`:29`](../enterprise/hr_payroll_account_iso20022/wizard/hr_payroll_payment_report_wizard.py#L29)), relying on the base validated filter at [`:86`](../enterprise/hr_payroll/wizard/hr_payroll_payment_report_wizard.py#L86).

---

## Input Integrations

Two families by where they hook: **attendance/planning feed work entries** (gate computation via the conflict state); **expense/commission feed `input_line_ids`** via `_compute_input_line_ids` overrides.

### `hr_payroll_attendance` (+ `hr_work_entry_attendance`)

For versions with `work_entry_source='attendance'`, attendances become attendance work entries and **approved** overtime becomes overtime work entries; both collapse into worked-day lines. The payslip override is purely informational (an Attendances stat button). Real injection is at generation: `hr.version._get_attendance_intervals` ([`hr_version.py:116`](../enterprise/hr_work_entry_attendance/models/hr_version.py#L116)) builds intervals (minus lunch, minus leaves) plus overtime for any version with a `ruleset_id`; work entries are created eagerly on attendance `create`/`write` if inside the generated period ([`hr_attendance.py:20`](../enterprise/hr_work_entry_attendance/models/hr_attendance.py#L20)). Dependency declared at [`__manifest__.py:12`](../enterprise/hr_payroll_attendance/__manifest__.py#L12).

Overtime combination follows the ruleset `rate_combination_mode` (`max` → one entry at the highest-rate type; `sum` → one per paid rule's type); only **paid** rules with a `work_entry_type_id` produce entries — a ruleset with no paid rules silently skips overtime ([`hr_version.py:227`](../enterprise/hr_work_entry_attendance/models/hr_version.py#L227)).

**Blockers/edge cases:** overtime counts only when `status=='approved'` (pending doesn't pay; refused is subtracted, [`hr_version.py:175`](../enterprise/hr_work_entry_attendance/models/hr_version.py#L175)); editing/deleting an attendance tied to a **validated** work entry raises UserError ([`hr_attendance.py:84-110`](../enterprise/hr_work_entry_attendance/models/hr_attendance.py#L84)) — reset the work entry to draft first; **open (no check-out) attendances are ignored** ([`:27`](../enterprise/hr_work_entry_attendance/models/hr_attendance.py#L27)); attendance outside the generated period is invisible until the contract dates cover it.

### `hr_payroll_planning` (+ `hr_work_entry_planning`)

For `work_entry_source='planning'`, **published** shifts become work entries via `planning.slot._create_work_entries` ([`planning_slot.py:17`](../enterprise/hr_work_entry_planning/models/planning_slot.py#L17)). Draft/unpublished shifts contribute nothing ([`:89`](../enterprise/hr_work_entry_planning/models/planning_slot.py#L89)). Changing `resource_id`/`start`/`end`/`allocated_hours` (or deleting) a slot tied to a validated work entry raises UserError ([`:96`](../enterprise/hr_work_entry_planning/models/planning_slot.py#L96)). Post-publish edits require a **full work-entry regeneration**, not incremental ([comment, planning_slot.py:20](../enterprise/hr_work_entry_planning/models/planning_slot.py#L20)).

### `hr_payroll_expense`

Approved/posted **employee-paid** expenses flagged "Reimburse In Next Payslip" are linked to the draft slip and summed into one `EXPENSES` input line ([`_update_expense_input_line_ids`, hr_payslip.py:158](../enterprise/hr_payroll_expense/models/hr_payslip.py#L158)); candidates are `state in (approved, posted)`, `payment_mode='own_account'`, `refund_in_payslip=True`, `payslip_id=False` ([`:103`](../enterprise/hr_payroll_expense/models/hr_payslip.py#L103)). When the payslip move posts, the expense move is posted and its payable line reconciled against the `EXPENSES` rule's payable line ([`account_move.py:10`](../enterprise/hr_payroll_expense/models/account_move.py#L10)).

**Required:** a salary rule with code **`EXPENSES`** whose `account_debit` is set and of type `liability_payable`.

**Blockers:** no rule / wrong account → danger banners "No rule to handle expenses" / "No debit account for EXPENSES rules" ([`hr_payslip.py:48`](../enterprise/hr_payroll_expense/models/hr_payslip.py#L48)); reporting a non-approved/posted or non-own-account expense → UserError ([`hr_expense.py:57`](../enterprise/hr_payroll_expense/models/hr_expense.py#L57)); no matching-country structure → RedirectWarning to create the rule ([`:62`](../enterprise/hr_payroll_expense/models/hr_expense.py#L62)); auto-reconciliation **silently skipped** (left for an accountant) when >2 accounts or a write-off is needed ([`account_move.py:92`](../enterprise/hr_payroll_expense/models/account_move.py#L92)); cannot remove an expense once the slip is validated/paid ([`hr_expense.py:44`](../enterprise/hr_payroll_expense/models/hr_expense.py#L44)); paying the expense move directly while flagged shows a non-blocking double-payment warning. (Edits to attendances linked to a validated work entry are blocked at the attendance level, but the overtime approve/refuse regeneration does not itself exclude validated-linked attendances.)

### `hr_payroll_sale_commission`

For each commission plan with `commission_payroll_input` set, the employee's commission for the period is summed into that input type ([`hr_payslip.py:14`](../enterprise/hr_payroll_sale_commission/models/hr_payslip.py#L14)). It reads `sale.commission.report` by `payment_date` within the period for `employee_id.user_id`.

**Edge cases:** commission lands in the period of its **target `payment_date`**, not when the sale closed; no-user employees get nothing (silent); multi-currency converts at `date_to`.

### `hr_payroll_fleet`

**Injects nothing into payslips** in v19 — `__init__.py` contains only the copyright comment, there is no `models/` dir. It ships two dashboard warnings only: *Vehicles With Drivers And Without Running Contract* and *Employees With Multiple Company Cars* ([`hr_payroll_dashboard_warning_data.xml:5`](../enterprise/hr_payroll_fleet/data/hr_payroll_dashboard_warning_data.xml#L5)). Company-car benefit-in-kind is implemented in **country localizations** (e.g. Belgian payroll), not this generic bridge.

---

## Contract Salary Configurator → Payroll

How an offer/salary-package produces the `hr.version` payroll consumes (the handoff only, not the recruitment funnel).

### The version, not the offer, is what payroll reads

`hr.contract.salary.offer` is a staging record; payroll never reads it. The offer becomes a version two ways:
1. **Internal simulation** (preview numbers): `_get_version` clones the template inside a savepoint that is **always rolled back** — nothing persists ([`hr_version.py:18`](../enterprise/hr_contract_salary_payroll/models/hr_version.py#L18)).
2. **Real signature**: `create_new_version` persists a version with `active=False` ([`main.py:702`](../enterprise/hr_contract_salary/controllers/main.py#L702)); `_update_version_on_signature` flips it `active=True` once the **last** signatory signs ([`main.py:87`](../enterprise/hr_contract_salary/controllers/main.py#L87)).

So a `half_signed` offer leaves an inactive version that payroll ignores; only `active=True` (driven by the sign request, not the `state` field) matters.

### The three numbers and which one payroll uses

| Field | Meaning | Defined |
|---|---|---|
| `final_yearly_costs` | total yearly employer budget (the slider) | [`hr_version.py:66`](../enterprise/hr_contract_salary/models/hr_version.py#L66) |
| `wage` | monthly gross stored on the version — **what payroll computes against** by default | base `hr.version` |
| `wage_with_holidays` | gross as if no days were sacrificed for extra holidays — the figure shown in the configurator | [`hr_version.py:55`](../enterprise/hr_contract_salary/models/hr_version.py#L55) |
| `wage_on_signature` | snapshot of the applied wage at signing | [`hr_version.py:57`](../enterprise/hr_contract_salary/models/hr_version.py#L57) |

The holidays sacrifice ratio is `1 - holidays/231` ([`:133`](../enterprise/hr_contract_salary/models/hr_version.py#L133)); when `holidays>0`, `wage_with_holidays > wage`. The simulation payslip's `struct_id = structure_type_id.default_struct_id` ([`hr_version.py:24`](../enterprise/hr_contract_salary_payroll/models/hr_version.py#L24)).

**Two divergences when a payslip total ≠ the offer screen:**
1. The configurator headline is `wage_with_holidays`; the payslip BASIC reads `wage` (lower whenever holidays were sacrificed). Intentional.
2. `_get_contract_wage_field` is country-dependent: **BE structures use `wage_on_signature`** ([`:113`](../enterprise/hr_contract_salary/models/hr_version.py#L113)), which is written only at signature time. A BE version created/edited outside the sign flow has a stale/zero `wage_on_signature` → the payslip BASIC reads a wrong wage even though `wage` looks correct. Worked-day amounts read the same `contract_wage` field, inheriting the discrepancy.

### Benefits → version fields or payslip inputs

A `hr.contract.salary.benefit` (`source`) maps a choice to either a real version field (`source='field'`) or a salary rule consuming a **payslip input** stored in `payroll_properties` (`source='rule'`, added by `hr_contract_salary_payroll`).

> **Gotcha:** `_set_property_input_value` silently no-ops if the rule code isn't already a key in `payroll_properties` ([`hr_version.py:108`](../enterprise/hr_payroll/models/hr_version.py#L108)). If a benefit value "won't stick", the structure's property input for that rule was never initialised on the version. Also: `get_values_from_contract_template` copies only a whitelist (`job, department, contract_type, structure_type, wage, resource_calendar, hr_responsible` — [`_get_whitelist_fields_from_template`, addons/hr/models/hr_version.py:430](../addons/hr/models/hr_version.py#L430); method at [`:436`](../addons/hr/models/hr_version.py#L436)); custom fields used by salary rules are **not** inherited from the template.

### Offer states (informational for payroll)

`open → half_signed → full_signed`, plus `expired`/`refused`/`cancelled` ([`hr_contract_salary_offer.py:53`](../enterprise/hr_contract_salary/models/hr_contract_salary_offer.py#L53)). `_update_version_on_signature` drives activation off the sign-request counters: employee-signed-only (`nb_closed==1, nb_wait>0`) → `half_signed`, version still inactive, `wage_on_signature` written ([`main.py:70`](../enterprise/hr_contract_salary/controllers/main.py#L70)); all signers done (`nb_wait==0`) → `full_signed`, version `active=True`, prior version archived ([`main.py:73`](../enterprise/hr_contract_salary/controllers/main.py#L73)).

### Extra holidays → leave allocation (`hr_contract_salary_holidays`)

On **full countersignature**, if the company has `hr_contract_timeoff_auto_allocation` enabled and `version.holidays > 0`, an `hr.leave.allocation` is created and approved ([`main.py:14`](../enterprise/hr_contract_salary_holidays/controllers/main.py#L14)); cancelling the version refuses it. **Gotcha:** if the setting/type is missing, `holidays` still reduces `wage` via the sacrifice math but **no allocation is created** — the employee paid for days they cannot book.

---

## Scheduled Actions, Async PDF, and Documents

### Crons

| XML id | Name | Method | Cadence | What it does |
|---|---|---|---|---|
| `hr_payroll.ir_cron_update_payroll_data` | Payroll: Update data | `_update_payroll_data()` | weekly (day 20) | Reloads static data from `_get_data_files_to_update()`. Base returns `[]` (no-op); localizations override it to reload salary rules/tables. |
| `hr_payroll.ir_cron_generate_payslip_pdfs` | Payroll: Generate pdfs | `_cron_generate_pdf()` | hourly | Renders queued payslip + declaration PDFs in batches of 30; self-retriggers. |
| `hr_work_entry.ir_cron_generate_missing_work_entries` (community) | Generate Missing Work Entries | `_cron_generate_missing_work_entries()` | daily | Generates work entries for the current-month..next-month horizon. Indirectly gates payroll. |

Sources: [`ir_cron_data.xml`](../enterprise/hr_payroll/data/ir_cron_data.xml) and [`hr_work_entry/data/ir_cron_data.xml:4`](../addons/hr_work_entry/data/ir_cron_data.xml#L4). There is **no** salary-attachment cron (auto-close is event-driven).

### Asynchronous payslip PDF generation

PDFs are **not** generated synchronously on confirm. `action_payslip_done` ([`hr_payslip.py:612`](../enterprise/hr_payroll/models/hr_payslip.py#L612)): with context `payslip_generate_pdf` + `payslip_generate_pdf_direct` → inline `_generate_pdf` (blocking); with only `payslip_generate_pdf` → set `queued_for_pdf=True` and trigger the cron (**the normal UI path**); with neither → no PDF at all. The Confirm/Create-Draft-Entry buttons inject `payslip_generate_pdf=True`.

`_cron_generate_pdf` ([`:1720`](../enterprise/hr_payroll/models/hr_payslip.py#L1720)) processes the first 30 queued `validated`/`paid` slips, generates PDFs, clears the flag, then does declarations, self-retriggering — so a large run materializes PDFs in waves. `_generate_pdf` ([`:550`](../enterprise/hr_payroll/models/hr_payslip.py#L550)) groups slips by report (`struct_id.report_id` else default), renders in the **employee's language**, stores an attachment, and **only then** sends the payslip email ([`:570`](../enterprise/hr_payroll/models/hr_payslip.py#L570)).

> `queued_for_pdf=True` means confirmed but PDF not yet rendered. A stalled/disabled cron means **no PDF and no employee email** until it runs.

### Documents bridge (`documents_hr_payroll`)

Makes `hr.payslip` a `documents.mixin`. When `_generate_pdf` creates the PDF attachment, a `documents.document` is auto-created if `_check_create_documents()` passes (built in `_get_document_vals`, gating at [`documents_mixin.py:28`](../enterprise/documents/models/documents_mixin.py#L28)) — requiring the employee has a partner **and** either a portal user **or** the company has `documents_hr_settings` enabled ([`documents_hr_payroll/models/hr_payslip.py:76`](../enterprise/documents_hr_payroll/models/hr_payslip.py#L76)). The bridge also adds a third cron stage posting declaration PDFs into Documents. Declarations advance `draft → pdf_to_generate → pdf_generated → pdf_to_post → pdf_posted`. `action_resend_payslips` refuses if any slip isn't validated/paid or an employee lacks an email.

---

## Changing Salary and Version Dates

Payroll uses `hr.version`, not the old contract object. The relevant version for a payslip is the one active at `date_from` (`slip.version_id = employee._get_version(date_from)`, [`hr_payslip.py:1219`](../enterprise/hr_payroll/models/hr_payslip.py#L1219)).

| Change | Effect |
|---|---|
| Edit wage on the current version | Recomputed draft slips use the new wage; confirmed slips show the **wrong-data** banner (`has_wrong_data`). |
| New version dated first day of the period | New wage applies cleanly. |
| New version mid-period, same contract | Monthly slip still uses the version active at period start; new wage usually affects next period. |
| New contract mid-period | Pay run can produce multiple slips for separate spans with worked-day proration. |

> When a confirmed slip's source version changed afterwards, use **Adjust payslip** (correction wizard) or **Keep it as is** (`keep_wrong_version`). For BE configurator versions, check `wage_on_signature`, not just `wage` (see [Contract Salary](#contract-salary-configurator--payroll)). Recommended practice: make raises effective on the first day of a pay period; use a new contract only for genuine split/prorated periods.

---

## Configuration & Debug Checklists

### Accounting configuration

1. Install `hr_payroll_account`.
2. Set the **Salary Journal** on the structure (`struct_id.journal_id`) — in company currency.
3. Configure rule debit/credit accounts: expense/debit for costs; payable/credit on `NET`; deduction/reimbursement as needed. Mark the `NET` credit account **reconcilable**.
4. Set the salary journal's **default account** (absorbs the rounding adjustment line).
5. Compute slips; verify `line_ids` are not empty and there is no danger issue.
6. Confirm / Create Draft Entry; open the move and verify meaningful lines; **post it** in Accounting.
7. Register payment; confirm the slip becomes `paid` only after full reconciliation — or Mark as Paid to deliberately bypass Accounting.

> **Empty journal-entry gotcha:** salary computation lines and journal items are different things. If a payslip has computed salary lines but the related salary rules have no Debit/Credit accounts, Odoo still creates the draft `account.move` header, but `_prepare_slip_lines()` creates no journal items for those rules. The result is a draft journal entry with an empty **Journal Items** tab. Configure the salary-rule accounts, then recreate the draft entry.

### Debug checklist (what to inspect, in order)

1. **Run period** — `date_start`/`date_end`/`schedule_pay`.
2. **Issues first** — `error_count`/`warning_count`/`issues`/`state_display`. A red Error badge means a danger issue is blocking; resolve it before anything else.
3. **Work entries** — are they generated? Any in **`conflict`** (drops hours silently)? Any **undefined slots** (calendar gap)? Check `work_entry_source`.
4. **Time off** — any overlapping leave not approved (→ conflict) or `payslip_state='blocked'` (→ "time off to defer" error)?
5. **Version** — `version_id` vs `employee._get_version(date_from)`; `wage_type`, `wage`, `hourly_wage`, `schedule_pay`, `resource_calendar_id`; wrong-version/wrong-data banners; for BE, `wage_on_signature`.
6. **Worked days** — types, hours, days, `amount_rate`, `is_extra_hours`, paid/unpaid (`unpaid_work_entry_type_ids`), `OUT` line, `edited` flag (frozen amounts).
7. **Inputs** — expected codes present; matching salary rules use those codes; salary attachments open and in range; expense/commission injections.
8. **Salary lines** — rule codes, sequence, categories, totals; check whether the rule ran and whether its category feeds later formulas.
9. **Accounting** — `struct_id.journal_id`; rule accounts; `move_id`/`move_state`; rounding adjustment.
10. **Payment** — move posted; `NET` credit account reconcilable; employee bank trusted; all residuals zero.

---

## Rule Parameters (`hr.rule.parameter`) — date-versioned constants

Two models: the header (`name`, globally-unique `code`, cosmetic `country_id`) and dated values ([hr_rule_parameter.py:11-68](../enterprise/hr_payroll/models/hr_rule_parameter.py#L11)). A value is any `safe_eval`-able Python literal (number, dict, table) with a `date_from`; lookup returns the latest value whose `date_from <= date`. Rules call it as `payslip._rule_parameter('CODE')` — the reference date defaults to **`payslip.date_to`** ([hr_payslip.py:924-929](../enterprise/hr_payroll/models/hr_payslip.py#L924)). This is the right home for legal constants that change per year (minimum wage, caps, tax tables) instead of hardcoding them in rule code.

Lookup mechanics ([`_get_parameter_from_code`, hr_rule_parameter.py:70-85](../enterprise/hr_payroll/models/hr_rule_parameter.py#L70)): a `search(limit=1)` on `hr.rule.parameter.value` ordered `date_from desc`, `safe_eval`'d, `@ormcache` keyed on `(code, date, allowed_company_ids)`. Values are validated as parseable Python at save time ([`:28-34`](../enterprise/hr_payroll/models/hr_rule_parameter.py#L28)); `(parameter, date_from)` is unique ([`:23`](../enterprise/hr_payroll/models/hr_rule_parameter.py#L23)).

Gotchas: no value at the date → UserError "No rule parameter with code … was found" ([`:83`](../enterprise/hr_payroll/models/hr_rule_parameter.py#L83)); the `code` is **globally unique across countries** ([`:65`](../enterprise/hr_payroll/models/hr_rule_parameter.py#L65)) and the search itself has no country clause — but a **country record rule** hides parameters/values whose country isn't among the user's companies' countries ([`hr_payroll_security.xml:63-73`](../enterprise/hr_payroll/security/hr_payroll_security.xml#L63)), so a wrong-country lookup fails with the not-found UserError rather than returning the other country's value (this is also why `allowed_company_ids` is in the cache key). Any edit of a value **clears the entire registry cache** ([hr_rule_parameter.py:36-48](../enterprise/hr_payroll/models/hr_rule_parameter.py#L36)) — don't script mass edits on a busy server. The "used in salary rules" reverse view is a SQL `LIKE` on rule source text — indirect references are invisible.

## Payroll Properties — the v19 salary-input system

A parallel input mechanism to classic `hr.payslip.input`, built on `fields.Properties`:

- The **structure** holds two Properties definitions: one for employee/version-level inputs, one for payslip-level ([hr_payroll_structure.py:69-70](../enterprise/hr_payroll/models/hr_payroll_structure.py#L69)).
- The **version** stores values in `payroll_properties` (definition follows `structure_type_id.default_struct_id` — the *default* structure), the **payslip** in `payslip_properties` (follows the slip's actual `struct_id`).
- A salary rule becomes an input by `condition_select = 'property_input'` plus input metadata (unit, default, section, employee/payslip usage flags, [hr_salary_rule.py:77-89](../enterprise/hr_payroll/models/hr_salary_rule.py#L77)). Property keys are `str(rule.id)`.
- "Configure inputs" actions (structure, employee, version) open a rule selector that rewrites the Properties definition, grouped under `hr.salary.rule.section` separators; a rule without a section can't be added.
- At payslip create/refresh, version property values copy onto the slip **only for keys present in both definitions** ([hr_payslip.py:216-237](../enterprise/hr_payroll/models/hr_payslip.py#L216)).
- In rules, values surface as `localdict['property_inputs'][rule_id]` (floats — booleans become 0.0/1.0). A `property_input` rule **bypasses `amount_select` entirely**: amount = the property value, qty 1, rate 100 ([hr_salary_rule.py:165-168](../enterprise/hr_payroll/models/hr_salary_rule.py#L165)).
- Helpers `_get_property_input_value` / `_set_property_input_value` translate rule code ↔ property key ([hr_version.py:95-114](../enterprise/hr_payroll/models/hr_version.py#L95)); the salary configurator's benefits use exactly this as their storage backend (`source='rule'` benefits in `hr_contract_salary_payroll`).

Gotchas: payslip-level edits of common keys are **overwritten by version values on refresh**; running a non-default structure means version-side and payslip-side definitions can diverge (only the intersection syncs); `hr.version.copy()` carries an upstream TODO admitting Properties don't survive copy and re-writes them manually ([hr_version.py:320-327](../enterprise/hr_payroll/models/hr_version.py#L320)).

## Headcount snapshots (`hr.payroll.headcount`)

Manual, stateless report: pick a date range → `action_populate` creates one line per employee with a contract overlapping the range (most recent in-range version), showing wage and all distinct working rates (hours/week) the employee had in range ([hr_payroll_headcount.py:57-93](../enterprise/hr_payroll/models/hr_payroll_headcount.py#L57)). Repopulating wipes lines. No cron, no lifecycle.

## Declarations framework (`hr.payroll.declaration.mixin`)

Abstract scaffolding for yearly per-employee declaration sheets (year selector, employee lines, batch PDF). Lines are generic pointers (`res_model` + `res_id`) with a PDF lifecycle driven by the **same cron as payslip PDFs**; PDFs are stored `attachment=False` (in-table) ([hr_payroll_employee_declaration.py:25](../enterprise/hr_payroll/models/hr_payroll_employee_declaration.py#L25)). In bare `hr_payroll` it's dormant — every concrete sheet is l10n (BE 281.x, IN, KE, CH, HK); `documents_hr_payroll` adds post-to-Documents states. Relevant to us only as the sanctioned pattern if we ever build Georgian yearly employee declarations.

## Dashboard warnings are configurable records

`hr.payroll.dashboard.warning` = name + `evaluation_code` Text, safe_eval'd by `get_dashboard_warnings()` with `self` (empty payslip recordset → full ORM), `last_batches`, and output vars `warning_count/warning_records/warning_action` ([hr_payslip.py:1820-1868](../enterprise/hr_payroll/models/hr_payslip.py#L1820)). Admins can add custom company checks from Configuration — useful for our own guards (e.g. "employees with wage 0", "slips whose entries changed after compute"). Gotchas: the search has **no country filter in code**, and one broken warning's exception kills the whole warnings panel.

## YTD (year-to-date) mechanics

Opt-in **per structure** (`ytd_computation`, [hr_payroll_structure.py:66-67](../enterprise/hr_payroll/models/hr_payroll_structure.py#L66)); the company only sets the reset anchor (`ytd_reset_day`/`ytd_reset_month`, Feb 29 rejected). Each payslip line's `ytd` = same-code line's ytd on the employee's last validated/paid slip of the same structure since the reset date + this line's total ([hr_payslip.py:1050-1086](../enterprise/hr_payroll/models/hr_payslip.py#L1050)); worked-days lines get the same treatment during `compute_sheet`.

## Payslip line math & styling

Lines are dumb storage: `total = amount × quantity × rate / 100` computed at generation via the overridable hook `_get_payslip_line_total` ([hr_payslip.py:1046-1048](../enterprise/hr_payroll/models/hr_payslip.py#L1046)). Per `amount_select`: fix → (amount_fix, eval(quantity), 100); percentage → (eval(base), eval(quantity), pct); input → (input.amount, 1, 100); python → (result, result_qty, result_rate); property_input → (value, 1, 100). The rule's bold/italic/indent/color flags exist purely for payslip rendering via `get_payslip_styling_dict` ([hr_payslip_line.py:54-72](../enterprise/hr_payroll/models/hr_payslip_line.py#L54)). `hr.payroll.note` is just the dashboard sticky-notes widget model.

## Wage indexation

No company config — a TransientModel wizard (`hr.payroll.index`, [hr_payroll_index_wizard.py](../enterprise/hr_payroll/wizard/hr_payroll_index_wizard.py)) multiplies selected versions' contract wage field by (1+percentage) and logs a note on each employee. Launched from employee list context action.

## Version-side payroll extension facts (beyond wage types)

- `schedule_pay` is computed from `structure_type_id.default_schedule_pay`, stored/editable — same reset-on-type-change trap as `wage_type`.
- `work_time_rate` = version hours_per_week ÷ company calendar hours_per_week ([hr_version.py:71-79](../enterprise/hr_payroll/models/hr_version.py#L71)).
- "Occupations": `_get_occupation_dates` stitches consecutive versions with same contract type + work-time rate, tolerating gaps < 4 days — the seniority primitive l10n logic builds on ([hr_version.py:131-194](../enterprise/hr_payroll/models/hr_version.py#L131)).
- **Likely upstream bug:** `_get_fields_that_recompute_payslip` returns a bound method, but `write()` compares vals keys against it as strings — so a plain wage write does **not** auto-refresh draft payslips through this path ([hr_version.py:278-280](../enterprise/hr_payroll/models/hr_version.py#L278) vs [314-317](../enterprise/hr_payroll/models/hr_version.py#L314)). Recompute draft slips manually after wage changes.
- Belgian-flavoured leftovers in core: `mobile_invoice`/`sim_card`/`internet_invoice` binaries on the employee.

## Settings reference (`res.config.settings`)

Only five: three l10n module installers, `module_hr_payroll_account_iso20022` (SEPA export), and the two YTD reset fields (with a two-fields-at-once write workaround for the company constraint) ([res_config_settings.py:10-33](../enterprise/hr_payroll/models/res_config_settings.py#L10)). `batch_payroll_move_lines` lives in `hr_payroll_account` (see Accounting Integration).

---

## Appendix A — Blockers Catalog

Every user-facing `UserError`/`ValidationError` in the payroll flow, with trigger and resolution.

### Work entries

| Exception & message | Trigger | Resolution | Source |
|---|---|---|---|
| UserError "Watch out for gaps in <employee>'s calendar…" | calendar version has scheduled time with no covering work entry (undefined slots), checked on worked-days compute / run generation | create/regenerate the missing work entries | [hr_work_entry.py:30](../enterprise/hr_payroll/models/hr_work_entry.py#L30) |
| UserError "Some work entries could not be validated. Time intervals to look for: …" | a non-validated entry is in `conflict` at pay-run generation (usually an unapproved leave overlapping attendance) | Approve/Refuse the conflicting time off, then regenerate | [hr_payslip_run.py:386](../enterprise/hr_payroll/models/hr_payslip_run.py#L386) |
| UserError "This work entry cannot be modified because it is already associated with a generated payslip" | writing a data field to a `validated` entry | reset entry to draft / cancel the payslip | [hr_work_entry.py:56](../enterprise/hr_payroll/models/hr_work_entry.py#L56) |
| UserError "This work entry is validated. You can't delete it." | unlink a `validated` entry | reset/cancel the linked payslip first | [hr_work_entry.py:279](../addons/hr_work_entry/models/hr_work_entry.py#L279) |
| ValidationError "Duration must be positive and cannot exceed 24 hours." | a single entry's duration ≤0 or >24 | set 0 < duration ≤ 24 | [hr_work_entry.py:55](../addons/hr_work_entry/models/hr_work_entry.py#L55) |
| ValidationError "No work entry can be regenerated in this range…" | every selected employee already has validated entries in range | pick a different range / employees | [hr_work_entry_regeneration_wizard.py:107](../addons/hr_work_entry/wizard/hr_work_entry_regeneration_wizard.py#L107) |

### Time off

| Exception & message | Trigger | Resolution | Source |
|---|---|---|---|
| ValidationError "Employee has time off to defer" | draft slip overlaps a `blocked` leave (danger error → `error_count`) | Report to Next Month / Defer to next Payslip, then refresh | [hr_payroll_holidays/.../hr_payslip.py:17](../enterprise/hr_payroll_holidays/models/hr_payslip.py#L17) |
| UserError "The pay of the month is already validated with this day included…" | re-activating/deleting a leave inside a validated/paid regular payslip | refund/correct the payslip; don't edit the leave | [hr_payroll_holidays/.../hr_leave.py:188](../enterprise/hr_payroll_holidays/models/hr_leave.py#L188) |
| UserError (Report to Next Month variants) | leave not blocked / spans >2 months / next month not generated or validated / no linked entries / not enough attendance next month | generate next month's draft entries first, or defer manually | [hr_payroll_holidays/.../hr_leave.py:115-164](../enterprise/hr_payroll_holidays/models/hr_leave.py#L115) |
| can_cancel False on an approved leave | the leave's work entry is `validated` | cancel/refund the payslip to release the entry | [hr_work_entry_holidays/.../hr_leave.py:167](../addons/hr_work_entry_holidays/models/hr_leave.py#L167) |

### Payslip & pay run

| Exception & message | Trigger | Source |
|---|---|---|
| ValidationError "'Date From' must be earlier than 'Date To'" | bad dates | [hr_payslip.py:465](../enterprise/hr_payroll/models/hr_payslip.py#L465) |
| ValidationError "You can't confirm cancelled payslips." | confirm a `cancel` slip | [hr_payslip.py:587](../enterprise/hr_payroll/models/hr_payslip.py#L587) |
| ValidationError = bullet list of danger issues | confirm/compute/pay/print with `error_count` (no contract over period / company mismatch / time off to defer) | [hr_payslip.py:589](../enterprise/hr_payroll/models/hr_payslip.py#L589), [:787](../enterprise/hr_payroll/models/hr_payslip.py#L787), [:635](../enterprise/hr_payroll/models/hr_payslip.py#L635) |
| UserError "Cannot mark payslip as paid if not confirmed." | mark paid when not validated/paid | [hr_payslip.py:633](../enterprise/hr_payroll/models/hr_payslip.py#L633) |
| UserError "You cannot cancel the payment if the payslip has not been paid." | unpaid when not paid | [hr_payslip.py:661](../enterprise/hr_payroll/models/hr_payslip.py#L661) |
| UserError "Cannot cancel a payslip that is validated." | non-manager cancels a validated slip | [hr_payslip.py:626](../enterprise/hr_payroll/models/hr_payslip.py#L626) |
| UserError "The payslips should be in Draft or Waiting state." | Recompute Whole Sheet on a non-draft slip | [hr_payslip.py:807](../enterprise/hr_payroll/models/hr_payslip.py#L807) |
| UserError edit payslip lines — "restricted to payroll officers only." / "forbidden on validated payslips." | no `group_hr_payroll_user`, or validated slip | [hr_payslip.py:1678](../enterprise/hr_payroll/models/hr_payslip.py#L1678), [:1681](../enterprise/hr_payroll/models/hr_payslip.py#L1681) |
| UserError "The selected payslips should be linked to the same batch" | payment report across >1 pay run | [hr_payslip.py:645](../enterprise/hr_payroll/models/hr_payslip.py#L645) |
| ValidationError "Allocated amounts surpass/are less than the net salary." | bank-split allocations ≠ net | [hr_payslip.py:2211](../enterprise/hr_payroll/models/hr_payslip.py#L2211) |
| ValidationError "…cannot reset a pay run to draft if some of the payslips have already been paid." | run set-to-draft with a paid slip | [hr_payslip_run.py:251](../enterprise/hr_payroll/models/hr_payslip_run.py#L251) |
| UserError "must select employee(s) version(s)" | generate payslips with no version | [hr_payslip_run.py:351](../enterprise/hr_payroll/models/hr_payslip_run.py#L351) |
| ValidationError "There is no valid payslip (validated and net wage > 0)…" | payment report wizard, no eligible slip | [hr_payroll_payment_report_wizard.py:88](../enterprise/hr_payroll/wizard/hr_payroll_payment_report_wizard.py#L88) |

### Accounting & payment

| Exception & message | Trigger | Source |
|---|---|---|
| ValidationError "You can't create a journal entry for a paid payslip." | confirm a slip already `paid` | [hr_payroll_account/.../hr_payslip.py:49](../enterprise/hr_payroll_account/models/hr_payslip.py#L49) |
| UserError "The Expense Journal … has not properly configured the default Account!" | rounding adjustment needed but journal has no default account | [hr_payroll_account/.../hr_payslip.py:225](../enterprise/hr_payroll_account/models/hr_payslip.py#L225) |
| UserError "You can only register payments for unpaid documents." | register payment on a `paid` slip | [hr_payroll_account/.../hr_payslip.py:281](../enterprise/hr_payroll_account/models/hr_payslip.py#L281) |
| UserError "The credit account on the NET salary rule is not reconciliable" | NET credit account `reconcile=False` | [hr_payroll_account/.../hr_payslip.py:283](../enterprise/hr_payroll_account/models/hr_payslip.py#L283) |
| UserError "An employee bank account is untrusted" | bank `allow_out_payment=False` | [hr_payroll_account/.../hr_payslip.py:286](../enterprise/hr_payroll_account/models/hr_payslip.py#L286) |
| UserError "You can only register payment for posted journal entries." | move not posted | [hr_payroll_account/.../hr_payslip.py:288](../enterprise/hr_payroll_account/models/hr_payslip.py#L288) |
| ValidationError "…journal must be in the same currency as the company" | salary journal currency ≠ company | [hr_payroll_account/.../hr_payroll_structure.py:19](../enterprise/hr_payroll_account/models/hr_payroll_structure.py#L19) |
| UserError "You cannot delete the journal linked to a Salary Structure" | delete a journal used by a structure | [hr_payroll_account/.../account_journal.py:10](../enterprise/hr_payroll_account/models/account_journal.py#L10) |
| ValidationError "The payment date cannot be in the past." | SEPA/Swiss export with past `effective_date` | [hr_payroll_account_iso20022/.../wizard:32](../enterprise/hr_payroll_account_iso20022/wizard/hr_payroll_payment_report_wizard.py#L32) |
| UserError "Some employees … don't have a work contact / valid name." | SEPA export, missing employee work contact | [iso20022 wizard:34](../enterprise/hr_payroll_account_iso20022/wizard/hr_payroll_payment_report_wizard.py#L34) |
| UserError "The journal '…' requires a proper IBAN account to pay via SEPA." | bank journal account not IBAN | [iso20022 wizard:42](../enterprise/hr_payroll_account_iso20022/wizard/hr_payroll_payment_report_wizard.py#L42) |

### Integrations

| Exception & message | Trigger | Source |
|---|---|---|
| Danger banner "No rule to handle expenses" / "No debit account for EXPENSES rules" | structure lacks an `EXPENSES` rule or its debit account is unset/not payable | [hr_payroll_expense/.../hr_payslip.py:48](../enterprise/hr_payroll_expense/models/hr_payslip.py#L48) |
| UserError "Only approved and posted expenses … can be reimbursed in a payslip." | reporting a non-eligible expense | [hr_payroll_expense/.../hr_expense.py:57](../enterprise/hr_payroll_expense/models/hr_expense.py#L57) |
| UserError "You cannot remove an expense from a payslip that has already been validated." | removing an expense from a validated/paid slip | [hr_payroll_expense/.../hr_expense.py:44](../enterprise/hr_payroll_expense/models/hr_expense.py#L44) |
| UserError "This attendance record is linked to a validated working entry. You can't modify it." | edit/delete an attendance behind a validated entry | [hr_work_entry_attendance/.../hr_attendance.py:85](../enterprise/hr_work_entry_attendance/models/hr_attendance.py#L85) |
| UserError "This shift record is linked to a validated working entry. You can't modify it." | edit/delete a planning slot behind a validated entry | [hr_work_entry_planning/.../planning_slot.py:96](../enterprise/hr_work_entry_planning/models/planning_slot.py#L96) |

---

## Appendix B — Status Reference

Every state across the payroll-relevant models.

### `hr.work.entry.state`

| State | Label | Meaning | Source |
|---|---|---|---|
| `draft` | New | editable, counted in worked hours | [hr_work_entry.py:39](../addons/hr_work_entry/models/hr_work_entry.py#L39) |
| `conflict` | In Conflict | failed a check; excluded from hours; blocks generation | [:138](../addons/hr_work_entry/models/hr_work_entry.py#L138) |
| `validated` | In Payslip | locked into a confirmed slip; immutable | [:109](../addons/hr_work_entry/models/hr_work_entry.py#L109) |
| `cancelled` | Cancelled | `active=False`; ignored | [:261](../addons/hr_work_entry/models/hr_work_entry.py#L261) |

### `hr.leave.payslip_state` (with `hr_payroll_holidays`)

| State | Label | Meaning | Source |
|---|---|---|---|
| `normal` | To compute in next payslip | default; generated normally | [hr_leave.py:16](../enterprise/hr_payroll_holidays/models/hr_leave.py#L16) |
| `blocked` | To defer to next payslip | period closed by a validated/paid slip; excluded from generation; adds the to-defer error | [:31](../enterprise/hr_payroll_holidays/models/hr_leave.py#L31) |
| `done` | Computed in current payslip | defer resolved; clears the block | [:110](../enterprise/hr_payroll_holidays/models/hr_leave.py#L110) |

### `hr.payslip.state` & `state_display`

| State | Meaning | Gated by | Source |
|---|---|---|---|
| `draft` | editable; lines/worked-days/inputs recompute | default; from cancel via Set-to-Draft | [hr_payslip.py:66](../enterprise/hr_payroll/models/hr_payslip.py#L66) |
| `validated` | confirmed; work entries validated; draft move created | `action_payslip_done`: no cancel slip, no `error_count` | [:586](../enterprise/hr_payroll/models/hr_payslip.py#L586) |
| `paid` | salary attachments recorded; `paid_date` set | `action_payslip_paid` (validated/paid, no `error_count`); or register-payment when all residuals zero | [:632](../enterprise/hr_payroll/models/hr_payslip.py#L632) |
| `cancel` | move unlinked/reversed; work entries re-drafted | `action_payslip_cancel`: managers only if validated | [:625](../enterprise/hr_payroll/models/hr_payslip.py#L625) |
| `state_display=warning` | orange badge overriding state | `warning_count>0` and `error_count==0` | [:239](../enterprise/hr_payroll/models/hr_payslip.py#L239) |
| `state_display=error` | red badge; compute/confirm/pay/print raise | `error_count>0` | [:239](../enterprise/hr_payroll/models/hr_payslip.py#L239) |

### `hr.payslip.run.state` (computed)

`01_ready` (Ready) / `02_close` (Done) / `03_paid` (Paid) / `04_cancel` (Cancelled) — see [Pay run states](#pay-run-states).

### `account.move` (payslip `move_id`)

| State | Meaning | Source |
|---|---|---|
| `draft` | created on confirm; never auto-posted | [hr_payroll_account/.../hr_payslip.py:275](../enterprise/hr_payroll_account/models/hr_payslip.py#L275) |
| `posted` | accountant posted it; required before Register Payment | register check [:288](../enterprise/hr_payroll_account/models/hr_payslip.py#L288) |
| deleted / cancel / reversed | on payslip cancel, routed by `_unlink_or_reverse` | [account_move.py:5458](../addons/account/models/account_move.py#L5458) |

### Other states

- `hr.salary.attachment`: `open` (Running) / `close` (Closed) — auto-closes on full payment; unlimited never auto-closes ([:105](../enterprise/hr_payroll/models/hr_salary_attachment.py#L105)).
- `hr.payroll.employee.declaration`: `draft → pdf_to_generate → pdf_generated → pdf_to_post → pdf_posted` (last two via the Documents bridge).
- `hr.contract.salary.offer`: `open / half_signed / full_signed / expired / refused / cancelled` — only `active=True` on the version reaches payroll.
- `hr.version.work_entry_source`: `calendar` / `attendance` / `planning` — decides where worked days come from.
- `planning.slot`: only `published` shifts generate work entries.
- `hr.expense`: only `approved`/`posted` own-account expenses with `refund_in_payslip` are eligible.

---

## Appendix C — Common Symptoms → Cause

| Symptom | Cause | Source |
|---|---|---|
| Fixed-wage salary still equals the monthly wage even when days/hours differ by month | fixed wage is prorated by that period's non-extra hours, then multiplied by the same paid hours for a full paid period | [hr_payslip_worked_days.py:48](../enterprise/hr_payroll/models/hr_payslip_worked_days.py#L48) |
| Hourly employee salary changes directly with hours | hourly wage uses `version.hourly_wage * worked hours * amount_rate` | [hr_payslip_worked_days.py:48](../enterprise/hr_payroll/models/hr_payslip_worked_days.py#L48) |
| A Bonus/Salary Input row does not change the Attendance amount | inputs affect salary computation only when a salary rule consumes the matching input code; worked days are separate | [hr_salary_rule.py:182](../enterprise/hr_payroll/models/hr_salary_rule.py#L182) |
| Hours/days silently missing for a day; entry shows a warning badge | the work entry is in `conflict`; `get_work_hours` only sums validated/draft | [hr_version.py:216](../enterprise/hr_payroll/models/hr_version.py#L216) |
| Confirm/compute raises a calendar-gap UserError | undefined slots: calendar version has scheduled time with no work entry | [hr_work_entry.py:30](../enterprise/hr_payroll/models/hr_work_entry.py#L30) |
| Confirm/compute raises "Employee has time off to defer" | a `blocked` leave overlaps the draft slip | [hr_payroll_holidays/.../hr_payslip.py:17](../enterprise/hr_payroll_holidays/models/hr_payslip.py#L17) |
| Unpaid leave shows days but contributes 0 | type is in `unpaid_work_entry_type_ids` → `is_paid=False` → amount 0 | [hr_payslip_worked_days.py:31](../enterprise/hr_payroll/models/hr_payslip_worked_days.py#L31) |
| Work entry type is named Unpaid but still pays | the name/code is not enough; the salary structure must list that type in `unpaid_work_entry_type_ids` | [hr_payslip_worked_days.py:31](../enterprise/hr_payroll/models/hr_payslip_worked_days.py#L31) |
| Create Draft Entry appears in one database, Validate appears in another | `hr_payroll_account` replaces the confirmation button label when accounting integration is installed | [hr_payroll_account/views/hr_payslip_views.xml:20](../enterprise/hr_payroll_account/views/hr_payslip_views.xml#L20) |
| Pay run stuck at 01_ready after confirming several slips | one slip still `draft`; draft has priority in `_compute_state` | [hr_payslip_run.py:183](../enterprise/hr_payroll/models/hr_payslip_run.py#L183) |
| Confirmed slip's journal entry is Draft (never posted) | no `action_post` in the confirm path; posting is manual | [hr_payroll_account/.../hr_payslip.py:118](../enterprise/hr_payroll_account/models/hr_payslip.py#L118) |
| No journal entry though accounting is installed | structure has no `journal_id` (silently skipped + warning banner) | [hr_payroll_account/.../hr_payslip.py:64](../enterprise/hr_payroll_account/models/hr_payslip.py#L64) |
| Journal entry exists but Journal Items are empty | salary computation lines exist, but their salary rules have no Debit/Credit accounts; Odoo creates the draft `account.move` header, while `_prepare_slip_lines()` adds no move lines | [hr_payroll_account/.../hr_payslip.py:181](../enterprise/hr_payroll_account/models/hr_payslip.py#L181) |
| Re-confirming a re-drafted slip makes no new move | Set-to-Draft doesn't clear `move_id`; create gate skips slips with a move | [hr_payslip.py:516](../enterprise/hr_payroll/models/hr_payslip.py#L516) |
| Cancelling a slip sometimes deletes, sometimes reverses the move | `_unlink_or_reverse` buckets by hash/lock/audit-trail | [account_move.py:5458](../addons/account/models/account_move.py#L5458) |
| Pay button missing in batch-move-line mode | no per-employee payable line; button hidden by design | [hr_payroll_account/views/hr_payslip_views.xml:31](../enterprise/hr_payroll_account/views/hr_payslip_views.xml#L31) |
| "Excluded from Net" rule's amount vanishes from the entry | removed from NET; if it has no own accounts it posts nowhere | [hr_payroll_account/.../hr_payslip.py:172](../enterprise/hr_payroll_account/models/hr_payslip.py#L172) |
| After Register Payment the slip stays Validated | a move-line residual is non-zero (partial / multi-bank / rounding) | [account_payment_register.py:36](../enterprise/hr_payroll_account/wizard/account_payment_register.py#L36) |
| Slip shows a Payment Date but state is Validated | Payment Report writes `paid_date` only, never `state` | [hr_payroll_payment_report_wizard.py:90](../enterprise/hr_payroll/wizard/hr_payroll_payment_report_wizard.py#L90) |
| Salary attachments recorded after Mark-as-Paid but not after a Payment Report | recording fires only on the `state='paid'` write | [hr_payslip.py:476](../enterprise/hr_payroll/models/hr_payslip.py#L476) |
| Confirmed slip has no PDF / employee got no email | PDF is async; `queued_for_pdf` awaits the hourly cron | [hr_payslip.py:612](../enterprise/hr_payroll/models/hr_payslip.py#L612) |
| Work entries missing beyond next month | generation cron horizon is current..next month only | [hr_version.py:694](../addons/hr_work_entry/models/hr_version.py#L694) |
| Overtime hours not paid | overtime not `approved`, or its rule isn't `paid`/has no type | [hr_work_entry_attendance/.../hr_version.py:175](../enterprise/hr_work_entry_attendance/models/hr_version.py#L175) |
| Commission lands in the wrong month | grouped by target `payment_date`, not sale date | [hr_payroll_sale_commission/.../hr_payslip.py:24](../enterprise/hr_payroll_sale_commission/models/hr_payslip.py#L24) |
| BE payslip wage wrong though `wage` looks right | BE uses `wage_on_signature`, stale outside the sign flow | [hr_contract_salary/.../hr_version.py:113](../enterprise/hr_contract_salary/models/hr_version.py#L113) |
| Extra holidays reduced wage but no leave allocation | auto-allocation setting/type missing | [hr_contract_salary_holidays/.../main.py:14](../enterprise/hr_contract_salary_holidays/controllers/main.py#L14) |

---

## Key Methods Map

### Work entries

| Method | Source |
|---|---|
| `_check_if_error()` (4 conflict checks) | [hr_work_entry.py:138](../addons/hr_work_entry/models/hr_work_entry.py#L138) |
| `action_validate()` | [hr_work_entry.py:109](../addons/hr_work_entry/models/hr_work_entry.py#L109) |
| `_check_undefined_slots()` (calendar gap) | [hr_work_entry.py:30](../enterprise/hr_payroll/models/hr_work_entry.py#L30) |
| `generate_work_entries()` / `_cron_generate_missing_work_entries()` | [hr_version.py:392](../addons/hr_work_entry/models/hr_version.py#L392) / [:694](../addons/hr_work_entry/models/hr_version.py#L694) |
| `get_work_hours()` / `_get_work_hours()` | [hr_version.py:216](../enterprise/hr_payroll/models/hr_version.py#L216) / [:252](../enterprise/hr_payroll/models/hr_version.py#L252) |

### Payslip

| Method | Source |
|---|---|
| `compute_sheet()` / `action_refresh_from_work_entries()` | [hr_payslip.py:785](../enterprise/hr_payroll/models/hr_payslip.py#L785) / [:804](../enterprise/hr_payroll/models/hr_payslip.py#L804) |
| `_compute_worked_days_line_ids()` / `_compute_input_line_ids()` | [:1429](../enterprise/hr_payroll/models/hr_payslip.py#L1429) / [:284](../enterprise/hr_payroll/models/hr_payslip.py#L284) |
| `_get_localdict()` / `_get_payslip_lines()` | [:1010](../enterprise/hr_payroll/models/hr_payslip.py#L1010) / [:1088](../enterprise/hr_payroll/models/hr_payslip.py#L1088) |
| `_compute_issues()` / `_get_errors_by_slip()` / `_get_warnings_by_slip()` | [:1392](../enterprise/hr_payroll/models/hr_payslip.py#L1392) / [:1305](../enterprise/hr_payroll/models/hr_payslip.py#L1305) / [:1329](../enterprise/hr_payroll/models/hr_payslip.py#L1329) |
| `action_payslip_done/paid/unpaid/cancel/draft` | [:586](../enterprise/hr_payroll/models/hr_payslip.py#L586) / [:632](../enterprise/hr_payroll/models/hr_payslip.py#L632) / [:660](../enterprise/hr_payroll/models/hr_payslip.py#L660) / [:625](../enterprise/hr_payroll/models/hr_payslip.py#L625) / [:516](../enterprise/hr_payroll/models/hr_payslip.py#L516) |
| `refund_sheet()` / `correct_sheet()` | [:723](../enterprise/hr_payroll/models/hr_payslip.py#L723) / [:748](../enterprise/hr_payroll/models/hr_payslip.py#L748) |
| `_cron_generate_pdf()` / `_generate_pdf()` | [:1720](../enterprise/hr_payroll/models/hr_payslip.py#L1720) / [:550](../enterprise/hr_payroll/models/hr_payslip.py#L550) |

### Pay run

| Method | Source |
|---|---|
| `_compute_state()` / `generate_payslips()` | [hr_payslip_run.py:183](../enterprise/hr_payroll/models/hr_payslip_run.py#L183) / [:344](../enterprise/hr_payroll/models/hr_payslip_run.py#L344) |
| `_are_payslips_ready()` | [hr_payslip_run.py:419](../enterprise/hr_payroll/models/hr_payslip_run.py#L419) |

### Accounting

| Method | Source |
|---|---|
| `action_payslip_done()` override / `action_payslip_cancel()` override | [hr_payroll_account/.../hr_payslip.py:43](../enterprise/hr_payroll_account/models/hr_payslip.py#L43) / [:38](../enterprise/hr_payroll_account/models/hr_payslip.py#L38) |
| `_action_create_account_move()` / `_create_account_move()` | [:54](../enterprise/hr_payroll_account/models/hr_payslip.py#L54) / [:275](../enterprise/hr_payroll_account/models/hr_payslip.py#L275) |
| `_prepare_slip_lines()` / `_prepare_line_values()` / `_prepare_adjust_line()` | [:166](../enterprise/hr_payroll_account/models/hr_payslip.py#L166) / [:125](../enterprise/hr_payroll_account/models/hr_payslip.py#L125) / [:222](../enterprise/hr_payroll_account/models/hr_payslip.py#L222) |
| `action_register_payment()` / `_get_line_batch_key()` / `_reconcile_payments()` | [:277](../enterprise/hr_payroll_account/models/hr_payslip.py#L277) / [account_payment_register.py:11](../enterprise/hr_payroll_account/wizard/account_payment_register.py#L11) / [:24](../enterprise/hr_payroll_account/wizard/account_payment_register.py#L24) |
| `_unlink_or_reverse()` (move on cancel) | [account_move.py:5458](../addons/account/models/account_move.py#L5458) |

---

## Related Docs

- [`INDEX.md`](INDEX.md)

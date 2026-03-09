# Attendance & Work Entries — `hr_attendance` + `hr_work_entry`

> Built from reading Odoo 19 source code and live DB analysis.
> Last updated: 2026-03-03

---

## 1. Overview

`hr_attendance` records raw clock-in/clock-out data per employee. `hr_work_entry` is the payroll-ready representation of time — it's what payslips actually read. The enterprise module `hr_work_entry_attendance` bridges the two: every time an attendance is checked out, it automatically converts the raw attendance into one or more work entries. The payslip never touches attendance records directly.

---

## 2. Dependencies

| Module | Role |
|---|---|
| `hr_attendance` | Clock-in/out data, overtime lines |
| `hr_work_entry` | Work entry model, work entry types |
| `hr_work_entry_attendance` (enterprise) | Converts attendance → work entries, overtime splitting |
| `hr_payroll` (enterprise) | Reads work entries to compute payslip worked days |

---

## 3. Key Models

### `hr.attendance`
Raw attendance record per employee.

| Field | Type | Description |
|---|---|---|
| `employee_id` | Many2one | Employee |
| `check_in` | Datetime | Clock-in (UTC) |
| `check_out` | Datetime | Clock-out (UTC) |
| `worked_hours` | Float | `check_out - check_in` in hours |
| `date` | Date | Date of `check_in` |

### `hr.work.entry`
One record per employee per calendar day.

| Field | Type | Description |
|---|---|---|
| `employee_id` | Many2one | Employee |
| `date` | Date | Calendar day (in employee's local timezone) |
| `duration` | Float | Hours for this entry |
| `work_entry_type_id` | Many2one | Type: Attendance, Overtime Hours, Time Off, etc. |
| `state` | Selection | `draft`, `validated`, `cancelled` |
| `active` | Boolean | False = cancelled/archived, excluded from payslip |
| `attendance_id` | Many2one → `hr.attendance` | Source attendance record (nullable) |
| `overtime_id` | Many2one → `hr.attendance.overtime.line` | Source overtime line (nullable) |
| `amount_rate` | Float | Pay multiplier (1.0 = 100%, 1.5 = 150%) |

### `hr.work.entry.type`
Defines what kind of time a work entry represents.

| Field | Description |
|---|---|
| `code` | e.g. `WORK100` (Attendance), `OVERTIME` (Overtime Hours) |
| `is_extra_hours` | True = bonus time, affects hourly rate calculation in payslip |
| `amount_rate` | Default pay multiplier for this type |
| `is_leave` | True = this type represents absence |

### `hr.attendance.overtime.line`
One record per employee per day when overtime is detected.

| Field | Description |
|---|---|
| `employee_id` | Employee |
| `date` | Date of overtime |
| `duration` | Overtime hours detected |
| `manual_duration` | Actual duration used (can be manually overridden) |
| `status` | `approved` / `refused` — **must be `approved` to generate overtime work entry** |
| `rule_ids` | M2M → `hr.attendance.overtime.rule` — which rules triggered |

### `hr.attendance.overtime.ruleset`
Container for overtime rules, assigned to a contract version.

| Field | Description |
|---|---|
| `name` | Display name |
| `rate_combination_mode` | `max` = use highest rate; `sum` = add extra percentages above 100% |
| `rule_ids` | One2many → `hr.attendance.overtime.rule` |

### `hr.attendance.overtime.rule`
Defines a single overtime threshold and how to pay it.

| Field | Description |
|---|---|
| `base_off` | `quantity` = based on total hours worked; `timing` = based on time of day / day type |
| `quantity_period` | `day` or `week` — period over which hours are counted |
| `expected_hours_from_contract` | If True, threshold = employee's scheduled hours from calendar; if False, use `expected_hours` |
| `expected_hours` | Manual threshold in hours (only if `expected_hours_from_contract = False`) |
| `paid` | True = this overtime creates a paid work entry |
| `amount_rate` | Pay multiplier for overtime hours under this rule |
| `work_entry_type_id` | Work entry type to assign (e.g. Overtime Hours) |
| `employer_tolerance` | Minimum overtime minutes before the rule triggers (buffer) |

---

## 4. Business Flow

### 4a. Attendance → Work Entry (automatic)

When an attendance record is **checked out** (check_out is set):

1. `hr_attendance.create()` / `hr_attendance.write()` triggers `_create_work_entries()`
   — [enterprise/hr_work_entry_attendance/models/hr_attendance.py:20](../enterprise/hr_work_entry_attendance/models/hr_attendance.py#L20)

2. The method finds the employee's active contract version that overlaps the attendance period.

3. `contract._get_work_entries_values(check_in, check_out)` generates raw vals with `date_start`/`date_stop`.

4. `_generate_work_entries_postprocess()` converts `date_start`/`date_stop` → `date` + `duration`:
   — [addons/hr_work_entry/models/hr_version.py:501](../addons/hr_work_entry/models/hr_version.py#L501)
   - Reads the calendar timezone (e.g. `Europe/Brussels = UTC+1`)
   - Splits multi-day attendances at **local midnight** (not UTC midnight)
   - Result: one work entry per local calendar day

5. Overlap handling via `_to_intervals()`:
   — [addons/hr_work_entry/models/hr_work_entry.py:231](../addons/hr_work_entry/models/hr_work_entry.py#L231)
   - Each work entry becomes a **full-day interval** (00:00–23:59) of its `date`
   - Any previous work entry on the same date is compared
   - If the old entry is fully covered → it is **archived** (`active=False`, `state=cancelled`)
   - **This happens even if the actual clock times don't overlap** — comparison is by date only

### 4b. Multi-Day Attendance Split (timezone example)

Attendance: `2026-02-24 20:45 UTC → 2026-02-25 07:45 UTC` (employee in `Europe/Brussels`, UTC+1)

| Step | Calculation |
|---|---|
| Local start | 20:45 UTC → **21:45 CET** on Feb 24 |
| Local end | 07:45 UTC → **08:45 CET** on Feb 25 |
| Split at local midnight | Feb 24 23:59 CET = 22:59 UTC |
| Segment 1 | 21:45→23:59 CET = **2.25h** → WE date=Feb 24 |
| Segment 2 | 00:00→08:45 CET = **8.75h** → WE date=Feb 25 |

### 4c. Same-Day Archive Problem

If two attendances both produce a work entry on the same calendar day, the **older one is archived** regardless of actual time overlap.

**Example (Abigail Peterson, Feb 25 2026):**
- Attendance A (07:58–11:28) → WE id=1, date=Feb 25, 3.03h → later **cancelled**
- Attendance B (overnight, ending 07:45) → WE id=616, date=Feb 25, 8.75h → **active**

Even though A ends at 07:58 and B ends at 07:45 (no time overlap), WE 1 is archived because both share `date=Feb 25` and the full-day interval comparison treats them as identical.

**Result: 3.03h of real work are not counted in the payslip.**

### 4d. Overtime Detection

Requires `ruleset_id` set on the contract version (`hr_version`).

1. On attendance save, `_update_overtime()` is triggered.
2. For each attendance day, actual worked hours are compared to the scheduled hours.
3. If `worked_hours > expected_hours + employer_tolerance`, an `hr.attendance.overtime.line` is created/updated.
4. The overtime line gets `status = 'approved'` automatically (can be manually refused).

### 4e. Overtime → Work Entry Split

When work entries are **regenerated** (via Reset button in Payroll → Work Entries gantt view), `_get_attendance_intervals()` is called:
— [enterprise/hr_work_entry_attendance/models/hr_version.py:116](../enterprise/hr_work_entry_attendance/models/hr_version.py#L116)

```
attendance_intervals  = actual clock times from hr.attendance
overtime_intervals    = from hr.attendance.overtime.line (approved only)
regular_intervals     = attendance_intervals - overtime_intervals
```

The condition to generate an overtime work entry (line 175):
```python
if not (overtime.rule_ids.work_entry_type_id and overtime.status == 'approved'):
    continue
```

Both conditions must be true. If the rule has `paid=True`, a separate work entry with type=OVERTIME is created for the overtime portion. The remaining hours become a regular WORK100 work entry.

---

## 5. How Payslip Uses Work Entries

Payslip computation reads **only active, non-cancelled** work entries (`state IN ('draft', 'validated')`).

`hr_version._get_work_hours()` groups work entries by type and sums duration:
— [enterprise/hr_payroll/models/hr_payslip.py](../enterprise/hr_payroll/models/hr_payslip.py)

```
{work_entry_type_id: total_hours, ...}
```

This becomes one **Worked Days** line per type on the payslip. Pay calculation:

- **Monthly wage employee**: `hourly_rate = contract_wage / total_non_extra_hours`
- **Hourly wage employee**: `hourly_rate = contract.hourly_wage`
- **Amount** = `hourly_rate × hours × amount_rate`

`amount_rate` on the work entry (not just the type) controls the multiplier. An OVERTIME work entry with `amount_rate=1.5` pays 150%.

---

## 6. UI Entry Points

| Task | Path |
|---|---|
| View attendance records | Attendances → Attendances |
| View work entries (gantt) | Payroll → Work Entries |
| Regenerate work entries | Payroll → Work Entries → **Reset** button (select period + employees first) |
| Regenerate overtime lines only | Attendances → Configuration → Overtime Rulesets → Regenerate Overtimes |
| Create overtime ruleset | Attendances → Configuration → Overtime Rulesets |
| Assign ruleset to contract | Payroll → Employees → [Employee] → Contract tab → Overtime Ruleset field |

---

## 7. Configuration — Overtime Ruleset Setup

### Step 1: Create a ruleset
`Attendances → Configuration → Overtime Rulesets → New`

| Field | Recommended |
|---|---|
| Rate Combination Mode | Maximum Rate (most common) |

### Step 2: Add rules

For daily overtime based on employee's schedule:

| Field | Value |
|---|---|
| Based Off | Quantity |
| Period | Day |
| Differs | from the amount defined on the contract *(= `expected_hours_from_contract=True`)* |
| Pay Extra Hours | Yes |
| Rate | 1.5 (for 150% pay) |
| Work Entry Type | Overtime Hours |

For weekend/non-working days:

| Field | Value |
|---|---|
| Based Off | Timing |
| Type | On any non-working day |
| From/To | 0:00 → 24:00 |
| Rate | 2.0 (double pay) |

### Step 3: Assign to contract
Employee → Contract → **Overtime Ruleset** field

### Step 4: Regenerate in correct order
1. `Attendances → Configuration → Overtime Rulesets → Regenerate Overtimes` — creates overtime lines
2. `Payroll → Work Entries → Reset` (select period) — splits work entries using those lines

**Both steps are required.** Running only step 1 creates overtime lines but leaves existing work entries unchanged.

---

## 8. Edge Cases & Gotchas

| Situation | What happens |
|---|---|
| Attendance spans midnight | Split at **local midnight** of calendar timezone, not UTC midnight |
| Two attendances on same calendar day | Older work entry archived even if times don't overlap (full-day interval comparison) |
| Overtime line created after work entry | Work entry stays as full Attendance until work entries are regenerated (Reset) |
| `ruleset_id` not set on contract | No overtime lines generated; all hours = plain Attendance |
| `expected_hours_from_contract = False` with wrong manual hours | Overtime amount calculated incorrectly (e.g. 7h manual vs 7.6h from schedule) |
| `amount_rate = 1.0` on overtime rule | Overtime is tracked separately but paid at same rate as regular hours |
| Overtime line `status = 'refused'` | Overtime work entry is NOT created even if rule is configured correctly |
| Validated work entries | Cannot be regenerated — wizard and Reset skip employees with validated entries for that period |
| `work_entry_source = 'attendance'` | Work entries come from actual clock records, not calendar schedule |
| `work_entry_source = 'calendar'` | Work entries come from the resource calendar schedule (no attendance needed) |

---

## 9. Key Method Reference

| Method | File | What it does |
|---|---|---|
| `_create_work_entries` | [enterprise/hr_work_entry_attendance/models/hr_attendance.py:20](../enterprise/hr_work_entry_attendance/models/hr_attendance.py#L20) | Triggered on attendance save; creates work entries |
| `_generate_work_entries_postprocess` | [addons/hr_work_entry/models/hr_version.py:501](../addons/hr_work_entry/models/hr_version.py#L501) | Splits multi-day spans at local midnight; converts date_start/stop → date + duration |
| `_to_intervals` | [addons/hr_work_entry/models/hr_work_entry.py:231](../addons/hr_work_entry/models/hr_work_entry.py#L231) | Converts work entry to full-day interval (00:00–23:59) for overlap detection |
| `_get_attendance_intervals` | [enterprise/hr_work_entry_attendance/models/hr_version.py:116](../enterprise/hr_work_entry_attendance/models/hr_version.py#L116) | Builds attendance + overtime intervals; subtracts overtime from attendance |
| `_get_real_attendance_work_entry_vals` | [enterprise/hr_work_entry_attendance/models/hr_version.py:199](../enterprise/hr_work_entry_attendance/models/hr_version.py#L199) | Creates work entry vals for attendance vs overtime intervals |
| `_get_work_hours` | [addons/hr_work_entry/models/hr_version.py](../addons/hr_work_entry/models/hr_version.py) | Aggregates active work entry hours by type for payslip |
| `regenerate_work_entries` | [addons/hr_work_entry/wizard/hr_work_entry_regeneration_wizard.py:97](../addons/hr_work_entry/wizard/hr_work_entry_regeneration_wizard.py#L97) | Wizard method: cancels existing draft entries, regenerates from scratch |
| `_generate_work_entries` | [addons/hr_work_entry/models/hr_version.py:418](../addons/hr_work_entry/models/hr_version.py#L418) | Core regeneration: nullifies old entries, calls `_get_work_entries_values` |

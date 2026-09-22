# Attendance & Work Entries — `hr_attendance` + `hr_work_entry_attendance` + `hr_payroll_attendance`

> **Modules:** [`addons/hr_attendance/`](../addons/hr_attendance/) (community) | [`enterprise/hr_work_entry_attendance/`](../enterprise/hr_work_entry_attendance/) | [`enterprise/hr_payroll_attendance/`](../enterprise/hr_payroll_attendance/)
> **Updated by Codex after source and test audit; verified 2026-07-12.**
> The work-entry engine is in [`work_entries.md`](work_entries.md); the complete public-holiday relation map is in [`public_holidays_flow.md`](public_holidays_flow.md).

---

## 1. Overview

`hr_attendance` records raw clock-in/clock-out data per employee and detects overtime from it via rulesets. `hr_work_entry` is the payroll-ready representation of time — it's what payslips actually read. The enterprise module `hr_work_entry_attendance` bridges the two: every time an attendance is checked out, it converts the raw attendance into one or more work entries and splits approved overtime into its own work entries. `hr_payroll_attendance` adds the payslip-side conveniences. The payslip never touches attendance records directly.

Both enterprise bridges are `auto_install` — any DB with Attendances + Payroll gets the full chain automatically ([hr_work_entry_attendance manifest:25](../enterprise/hr_work_entry_attendance/__manifest__.py#L25), [hr_payroll_attendance manifest:10](../enterprise/hr_payroll_attendance/__manifest__.py#L10)).

---

## 2. Dependencies

| Module | Role |
|---|---|
| `hr_attendance` | Clock-in/out data, overtime rulesets/rules/lines, kiosk, crons |
| `hr_work_entry` | Work entry model, work entry types, regeneration wizard — see [`work_entries.md`](work_entries.md) |
| `hr_work_entry_attendance` (enterprise, auto_install) | Attendance → work entries, overtime splitting, `work_entry_source='attendance'`, approve/refuse → regeneration |
| `hr_payroll_attendance` (enterprise, auto_install) | Payslip Attendances smart button, overtime never half-day, ruleset visible to payroll users |
| `hr_payroll` (enterprise) | Reads work entries to compute payslip worked days |

Sibling bridges (all `auto_install`) are covered in §10.

---

## 3. Key Models

### `hr.attendance`
Raw attendance record per employee ([hr_attendance.py:26](../addons/hr_attendance/models/hr_attendance.py#L26)).

| Field | Type | Description |
|---|---|---|
| `employee_id` | Many2one | Employee |
| `check_in` | Datetime | Clock-in (UTC) |
| `check_out` | Datetime | Clock-out (UTC) |
| `worked_hours` | Float | `check_out - check_in` minus schedule lunch (flexible resources: raw difference) ([hr_attendance.py:161](../addons/hr_attendance/models/hr_attendance.py#L161)) |
| `date` | Date | Date of `check_in` **in the employee's timezone** ([hr_attendance.py:83](../addons/hr_attendance/models/hr_attendance.py#L83)) |
| `overtime_hours` | Float | "Over Time" — sum of `manual_duration` of all linked overtime lines ([hr_attendance.py:116](../addons/hr_attendance/models/hr_attendance.py#L116)) |
| `validated_overtime_hours` | Float | "Extra Hours" — sum of `manual_duration` of **approved** lines only ([hr_attendance.py:121](../addons/hr_attendance/models/hr_attendance.py#L121)) |
| `overtime_status` | Selection | Aggregate of linked lines: all approved → `approved`, all refused → `refused`, mixed/none-decided → `to_approve` ([hr_attendance.py:104](../addons/hr_attendance/models/hr_attendance.py#L104)) |
| `in_mode`/`out_mode` | Selection | kiosk / systray / manual / technical / auto_check_out |

Validity constraints: no overlapping attendances, max one open (no check_out) attendance per employee — enforced in Python, not SQL ([hr_attendance.py:190](../addons/hr_attendance/models/hr_attendance.py#L190)). `copy()` is blocked outright ([hr_attendance.py:334](../addons/hr_attendance/models/hr_attendance.py#L334)).

**Attendance ↔ overtime line linking is by value match, not FK:** `linked_overtime_ids` is a computed M2M resolved by searching lines with `time_start == check_in` and same employee ([hr_attendance.py:526](../addons/hr_attendance/models/hr_attendance.py#L526)). Change a check_in and the old lines silently stop matching (they get rebuilt anyway, see §4d).

### `hr.work.entry`
Day-based: `date` + `duration`, one or more per employee per calendar day. States `draft`/`validated`/`conflict`/`cancelled`; `active=False` ⇔ cancelled. Full anatomy in [`work_entries.md`](work_entries.md). The bridge adds two FKs: `attendance_id` and `overtime_id` ([hr_work_entry.py:9](../enterprise/hr_work_entry_attendance/models/hr_work_entry.py#L9)), and `amount_rate` snapshots from the type at create ([hr_work_entry.py:245](../addons/hr_work_entry/models/hr_work_entry.py#L245)).

### `hr.work.entry.type`
Defines what kind of time a work entry represents. `code` (e.g. `WORK100`, `OVERTIME`), `amount_rate` (pay multiplier), `is_extra_hours` (excluded from the fixed-wage hourly-rate denominator), `is_leave` ([hr_work_entry_type.py:31](../addons/hr_work_entry/models/hr_work_entry_type.py#L31)). Details in [`work_entries.md`](work_entries.md).

### `hr.attendance.overtime.line`
One record per employee/day/rule-combination when overtime is detected ([hr_attendance_overtime.py:6](../addons/hr_attendance/models/hr_attendance_overtime.py#L6)).

| Field | Description |
|---|---|
| `date` | Day of the overtime (employee tz) |
| `duration` | Computed extra hours ("Extra Hours"). **Negative for undertime** (absence management) |
| `manual_duration` | "Extra Hours (encoded)" — defaults to `duration`, manually overridable ([hr_attendance_overtime.py:27](../addons/hr_attendance/models/hr_attendance_overtime.py#L27)). Attendance sums and payroll balances read this, **not** `duration` |
| `status` | `to_approve` / `approved` / `refused`. Precomputed at create: `to_approve` if the company's Extra Hours Validation is "Approved by Manager", else `approved` immediately ([hr_attendance_overtime.py:61](../addons/hr_attendance/models/hr_attendance_overtime.py#L61)) |
| `time_start`/`time_stop` | Copy of the source attendance's check_in/check_out — this is the link key |
| `amount_rate` | Combined pay rate from the triggering rules (0.0 when only unpaid rules triggered) |
| `rule_ids` | M2M → the rules that produced this line |
| `work_entry_type_overtime_id` | (enterprise) informational — WE type of the max-rate paid rule ([hr_attendance_overtime.py:10](../enterprise/hr_work_entry_attendance/models/hr_attendance_overtime.py#L10)) |

**Lifecycle:** created only by `_update_overtime` (§4d) — never manually. `action_approve`/`action_refuse` write status ([hr_attendance_overtime.py:85](../addons/hr_attendance/models/hr_attendance_overtime.py#L85)); with the enterprise bridge these also trigger work-entry regeneration for the affected days (§4f). Who approves: the attendance UI exposes approve/refuse on the attendance record (writes all its linked lines, [hr_attendance.py:532](../addons/hr_attendance/models/hr_attendance.py#L532)); `is_manager` = attendance Administrator, or Officer who is the employee's `attendance_manager_id` ([hr_attendance_overtime.py:72](../addons/hr_attendance/models/hr_attendance_overtime.py#L72)). ACL: **officer-group only** — regular employees have no access to overtime lines at all ([ir.model.access.csv:10](../addons/hr_attendance/security/ir.model.access.csv#L10)); employee-facing totals go through `compute_sudo` fields (`total_overtime`, [hr_employee.py:49](../addons/hr_attendance/models/hr_employee.py#L49)).

**"Over Time" vs "Extra Hours":** same lines, different filter — `overtime_hours` sums all lines, `validated_overtime_hours` ("Extra Hours") only approved ones. Employee `total_overtime` is the all-time approved sum and is what kiosk/systray display when the company enables "Display Extra Hours".

### `hr.attendance.overtime.ruleset`
Named container of overtime rules, assigned to a contract version via `hr.version.ruleset_id`. The field carries a `default=` pointing at the seeded "Default Ruleset" ([hr_version.py:22](../addons/hr_attendance/models/hr_version.py#L22)), but **that default only fires for versions created through the ORM after the field existed** — demo, imported, and migrated versions commonly have `ruleset_id = NULL` (verified: 45 of 51 versions blank in a demo DB). A NULL ruleset means the version is skipped by the `if ruleset:` gate in `_update_overtime` and **no overtime is ever computed for that employee** — the single most common "Extra Hours = 0" cause. Defined in [hr_attendance_overtime_ruleset.py](../addons/hr_attendance/models/hr_attendance_overtime_ruleset.py).

| Field | Description |
|---|---|
| `name` | Display name |
| `rate_combination_mode` | `max` = use highest rate of the applicable rules; `sum` = 100% + each rule's extra above 100% (150% & 120% → 170%) ([hr_attendance_overtime_ruleset.py:18](../addons/hr_attendance/models/hr_attendance_overtime_ruleset.py#L18)) |
| `country_id` | Informational/grouping, defaults to company country; `hr.version.ruleset_id` domain filters to current companies' countries or no country ([hr_version.py:11](../addons/hr_attendance/models/hr_version.py#L11)) |
| `rule_ids` | One2many → `hr.attendance.overtime.rule` |

Seed: the **"Default Ruleset"** ships with two rules ([rule_data.xml](../addons/hr_attendance/data/hr_attendance_overtime_rule_data.xml)), both `paid`: **Employee Schedule Rule** (`quantity`, hours beyond the employee schedule) and **Non Working Days Rule** (`timing` / `non_work_days`, any hours on a day off). With `hr_work_entry_attendance` installed both seeded rules get the standard OVERTIME work entry type ([rule_data.xml:4](../enterprise/hr_work_entry_attendance/data/hr_attendance_overtime_rule_data.xml#L4)) — whose stock `amount_rate` makes default overtime pay questionable (see [`payroll_wage_types.md`](payroll_wage_types.md) gotchas). `action_regenerate_overtimes` (Regenerate Overtimes button) re-runs detection for all attendances of employees on the ruleset ([hr_attendance_overtime_ruleset.py:50](../addons/hr_attendance/models/hr_attendance_overtime_ruleset.py#L50)); the enterprise bridge excludes attendances already locked by validated work entries ([hr_attendance_overtime_ruleset.py:10](../enterprise/hr_work_entry_attendance/models/hr_attendance_overtime_ruleset.py#L10)). Editing (create/write/delete) rulesets requires the Attendance Administrator group; HR managers get read-only ([ruleset security](../addons/hr_attendance/security/hr_attendance_overtime_ruleset_security.xml)).

### `hr.attendance.overtime.rule`
One overtime definition. Two fundamentally different modes via `base_off`. Defined in [hr_attendance_overtime_rule.py](../addons/hr_attendance/models/hr_attendance_overtime_rule.py).

| Field | Description |
|---|---|
| `base_off` | `quantity` = hours above a threshold; `timing` = hours worked in a specific window/day-type ([hr_attendance_overtime_rule.py:77](../addons/hr_attendance/models/hr_attendance_overtime_rule.py#L77)) |
| **Quantity mode** | |
| `quantity_period` | `day` or `week` — period the hours are summed over. Week buckets key on **Sunday** ([hr_attendance_overtime_rule.py:260](../addons/hr_attendance/models/hr_attendance_overtime_rule.py#L260)) |
| `expected_hours_from_contract` | True → threshold = employee's scheduled hours (shown as "From Employee"); False → use `expected_hours` |
| `expected_hours` | Manual threshold in hours (when not from contract); constraint: required if not from contract ([hr_attendance_overtime_rule.py:144](../addons/hr_attendance/models/hr_attendance_overtime_rule.py#L144)) |
| **Timing mode** | |
| `timing_type` | `work_days` / `non_work_days` / `leave` (employee off — marked "completely untested" upstream, [hr_attendance_overtime_rule.py:237](../addons/hr_attendance/models/hr_attendance_overtime_rule.py#L237)) / `schedule` (outside a specific calendar) |
| `timing_start` / `timing_stop` | Hour-of-day window (default 0–24). **Start > stop = night window crossing midnight** — the interval inverts inside the day (22→6 means 22:00–24:00 plus 00:00–06:00) ([hr_attendance_overtime_rule.py:521](../addons/hr_attendance/models/hr_attendance_overtime_rule.py#L521)) |
| `resource_calendar_id` | The schedule, required when `timing_type='schedule'` |
| **Pay** | |
| `paid` | True = produces a paid overtime line / work entry. False = the line is still created but with `amount_rate 0.0` — tracked, never paid ([hr_attendance_overtime_rule.py:804](../addons/hr_attendance/models/hr_attendance_overtime_rule.py#L804)) |
| `amount_rate` | Pay multiplier. **Enterprise** relabels this to **"Salary Rate"**, computes it from `work_entry_type_id.amount_rate` and makes the view readonly ([rule extension:17](../enterprise/hr_work_entry_attendance/models/hr_attendance_overtime_rule.py#L17), [view](../enterprise/hr_work_entry_attendance/views/hr_attendance_overtime_views.xml)) |
| `employer_tolerance` | Buffer — overtime under this is ignored. **Only enforced for quantity rules in the live code path**; the timing-rule tolerance check lives in a method marked "TO REMOVE IN MASTER" that v2 detection never calls ([hr_attendance_overtime_rule.py:246](../addons/hr_attendance/models/hr_attendance_overtime_rule.py#L246) vs [v2 timing path:508](../addons/hr_attendance/models/hr_attendance_overtime_rule.py#L508)) |
| `employee_tolerance` | Buffer for negative "undertime" (needs `company.absence_management`) ([hr_attendance_overtime_rule.py:346](../addons/hr_attendance/models/hr_attendance_overtime_rule.py#L346)) |
| `information_display` | Computed human-readable summary (the "Information" column) |

`work_entry_type_id` is **enterprise-only** (`hr_work_entry_attendance` adds it; required, defaults to the standard OVERTIME type, SQL-checked when `paid`) — [rule extension:16](../enterprise/hr_work_entry_attendance/models/hr_attendance_overtime_rule.py#L16). It is **not** on the community rule model.

---

## 4. Business Flow

### 4a. Attendance → Work Entry (create / check-out)

When an attendance record is **checked out** (check_out set):

1. `hr_attendance.create()` / `hr_attendance.write()` triggers `_create_work_entries()`
   — [enterprise/hr_work_entry_attendance/models/hr_attendance.py:20](../enterprise/hr_work_entry_attendance/models/hr_attendance.py#L20)

2. The method finds the employee's active contract version that overlaps the attendance period, and only acts if the attendance falls inside the version's already-generated window (`date_generated_from/to`) ([hr_attendance.py:32](../enterprise/hr_work_entry_attendance/models/hr_attendance.py#L32)).

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
   - If the old entry is fully covered → it is **archived** (`active=False`, `state=cancelled`); partially-outside entries just lose their `attendance_id` ([hr_attendance.py:66](../enterprise/hr_work_entry_attendance/models/hr_attendance.py#L66))
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

**Example (Abigail Peterson, Feb 25 2026, live-DB verified):**
- Attendance A (07:58–11:28) → WE id=1, date=Feb 25, 3.03h → later **cancelled**
- Attendance B (overnight, ending 07:45) → WE id=616, date=Feb 25, 8.75h → **active**

Even though A ends at 07:58 and B ends at 07:45 (no time overlap), WE 1 is archived because both share `date=Feb 25` and the full-day interval comparison treats them as identical.

**Result: 3.03h of real work are not counted in the payslip.**

### 4d. Overtime Detection

Requires `ruleset_id` set on the contract version (`hr.version`). On attendance create/write/unlink, `_update_overtime()` runs — [hr_attendance.py:265](../addons/hr_attendance/models/hr_attendance.py#L265): it **deletes every overtime line in the affected week range and recreates from scratch** (domain widened to full weeks, previous Monday → Sunday, [hr_attendance.py:253](../addons/hr_attendance/models/hr_attendance.py#L253)), resolves each attendance's active version → `version.ruleset_id`, and calls `ruleset.rule_ids._generate_overtime_vals_v2(...)` ([hr_attendance_overtime_rule.py:767](../addons/hr_attendance/models/hr_attendance_overtime_rule.py#L767)).

Each rule contributes overtime by its `base_off`:
- **Quantity** — sums worked hours (minus schedule lunch) over the period (day/week), subtracts the threshold (employee schedule minus leaves when `expected_hours_from_contract`, else `expected_hours`); the excess above `employer_tolerance` is overtime, placed on the **tail end** of the period's attendances ([hr_attendance_overtime_rule.py:327](../addons/hr_attendance/models/hr_attendance_overtime_rule.py#L327)). A shortfall below `-employee_tolerance` becomes one negative "undertime" line on the last attendance when `company.absence_management` is on ([hr_attendance_overtime_rule.py:346](../addons/hr_attendance/models/hr_attendance_overtime_rule.py#L346)). Fully-flexible employees (no calendar) are skipped entirely ([hr_attendance_overtime_rule.py:413](../addons/hr_attendance/models/hr_attendance_overtime_rule.py#L413)).
- **Timing** — intersects attendance intervals with the rule's window: working days / non-working days (from the company calendar's unusual-days map minus employee leaves), outside a named schedule, or during employee leave ([hr_attendance_overtime_rule.py:508](../addons/hr_attendance/models/hr_attendance_overtime_rule.py#L508)).

When multiple rules cover the same interval they collapse into one line with the combined recordset in `rule_ids` ([_record_overlap_intervals:28](../addons/hr_attendance/models/hr_attendance_overtime_rule.py#L28)); `_extra_overtime_vals()` combines their rates per the ruleset's `rate_combination_mode` (`max`/`sum`) ([hr_attendance_overtime_rule.py:804](../addons/hr_attendance/models/hr_attendance_overtime_rule.py#L804)). The line gets `status = 'approved'` automatically, or `to_approve` if the company's Extra Hours Validation is "by manager" (then manually approved/refused).

### 4e. Overtime → Work Entry Split

When work entries are **regenerated** (wizard / Reset in the Work Entries view — see [`work_entries.md`](work_entries.md)), `_get_attendance_intervals()` is called:
— [enterprise/hr_work_entry_attendance/models/hr_version.py:116](../enterprise/hr_work_entry_attendance/models/hr_version.py#L116)

```
attendance_intervals  = actual clock times from hr.attendance (source='attendance' only)
overtime_intervals    = from hr.attendance.overtime.line (any version with a ruleset OR source='attendance')
regular_intervals     = attendance_intervals - overtime_intervals
```

The condition to generate an overtime work entry ([hr_version.py:175](../enterprise/hr_work_entry_attendance/models/hr_version.py#L175)):
```python
if not (overtime.rule_ids.work_entry_type_id and overtime.status == 'approved'):
    continue
```

Both conditions must be true. The overtime work entry's type is the paid rules' `work_entry_type_id` (falls back to standard OVERTIME); lines whose rules are all unpaid are skipped ([hr_version.py:227](../enterprise/hr_work_entry_attendance/models/hr_version.py#L227)). The remaining hours become a regular WORK100 Attendance work entry ([hr_version.py:204](../enterprise/hr_work_entry_attendance/models/hr_version.py#L204)).

Two mode-dependent behaviors in `_get_real_attendance_work_entry_vals` ([hr_version.py:199](../enterprise/hr_work_entry_attendance/models/hr_version.py#L199)):
- **`max` mode** (or a single type): one WE, typed with the highest-rate type among the triggered paid rules.
- **`sum` mode with multiple paid rules of different types**: **one WE per rule type, each covering the full overtime interval** ([hr_version.py:246](../enterprise/hr_work_entry_attendance/models/hr_version.py#L246)) — the same hours appear once per type and each pays at its own type rate. This is the "sum-mode double-count" gotcha confirmed in [`payroll_wage_types.md`](payroll_wage_types.md) §8.

Placement: the overtime interval is anchored at the **end** of the attendance window (`stop = min(day end, time_stop)`, `start = stop - duration`) and then re-fitted to prefer the outside-schedule portions of the attendance ([_get_overtime_intervals:24](../enterprise/hr_work_entry_attendance/models/hr_version.py#L24), [_set_real_overtime_intervals:59](../enterprise/hr_work_entry_attendance/models/hr_version.py#L59)). Note the interval length uses `duration`, while the `manual_duration > 0` filter only gates existence ([hr_version.py:33](../enterprise/hr_work_entry_attendance/models/hr_version.py#L33), [L53](../enterprise/hr_work_entry_attendance/models/hr_version.py#L53)) — encoding a smaller non-zero `manual_duration` does **not** shrink the overtime work entry; encoding 0 removes it.

For **calendar-source** employees with a ruleset, only the overtime piece comes from attendances; the base entries stay schedule-generated ([hr_version.py:122](../enterprise/hr_work_entry_attendance/models/hr_version.py#L122), [L170](../enterprise/hr_work_entry_attendance/models/hr_version.py#L170)). For **attendance-source** employees, an attendance recorded during a leave interval wins over the leave ([_get_valid_leave_intervals:188](../enterprise/hr_work_entry_attendance/models/hr_version.py#L188)).

### 4f. Edit / Approve / Refuse → Regeneration Choreography

The bridge wires attendance mutations into the day-based regeneration wizard (`regenerate_work_entries(slots=...)`, [wizard:97](../addons/hr_work_entry/wizard/hr_work_entry_regeneration_wizard.py#L97) — mechanics in [`work_entries.md`](work_entries.md)):

| Event | What happens (in order) |
|---|---|
| Check-out (write of `check_out`) | community `write` recomputes overtime lines for the week (§4d) → enterprise `write` regenerates work entries for the touched employee/dates via wizard slots → then `_create_work_entries` for the just-closed attendance ([hr_attendance.py:82](../enterprise/hr_work_entry_attendance/models/hr_attendance.py#L82)) |
| Edit `check_in`/`check_out` of a closed attendance | overtime lines wiped+rebuilt for the week, then wizard regeneration of the affected days ([hr_attendance.py:89](../enterprise/hr_work_entry_attendance/models/hr_attendance.py#L89)) |
| Delete attendance | overtime recomputed, then wizard regeneration of the days that had linked work entries ([hr_attendance.py:112](../enterprise/hr_work_entry_attendance/models/hr_attendance.py#L112)) |
| Approve / refuse an overtime line | `action_approve`/`action_refuse` → wizard regeneration of the linked attendance days — overtime WEs appear/disappear immediately, no manual Reset needed ([hr_attendance_overtime.py:12](../enterprise/hr_work_entry_attendance/models/hr_attendance_overtime.py#L12)) |
| Ruleset "Regenerate Overtimes" button | rebuilds overtime **lines only** — work entries stay stale until a wizard regeneration or an approve/refuse action (no hook on line create/unlink) |

Guards: any write/unlink on an attendance linked to a **validated** work entry raises a UserError ([hr_attendance.py:83](../enterprise/hr_work_entry_attendance/models/hr_attendance.py#L83), [L106](../enterprise/hr_work_entry_attendance/models/hr_attendance.py#L106)); the regeneration wizard itself nullifies `attendance_id` on entries it archives ([wizard extension:9](../enterprise/hr_work_entry_attendance/wizard/hr_work_entry_regeneration_wizard.py#L9)).

---

## 5. How Payslip Uses Work Entries

Payslip computation reads **only active** work entries with `state IN ('draft', 'validated')` ([hr_version.py:216](../enterprise/hr_payroll/models/hr_version.py#L216)).

`hr_version._get_work_hours()` groups work entries by type and sums duration — [hr_version.py:252](../enterprise/hr_payroll/models/hr_version.py#L252):

```
{work_entry_type_id: total_hours, ...}
```

This becomes one **Worked Days** line per type on the payslip. Pay calculation:

- **Monthly wage employee**: `hourly_rate = contract_wage / total_non_extra_hours`
- **Hourly wage employee**: `hourly_rate = contract.hourly_wage`
- **Amount** = `hourly_rate × hours × amount_rate`

The full worked-days math (and its traps) is in [`payroll_wage_types.md`](payroll_wage_types.md). Note: the `_preprocess_work_hours_data` hook comment says "see hr_payroll_attendance" but nothing overrides it in v19 — only the Belgian module overrides the split-half variant ([hr_version.py:225](../enterprise/hr_payroll/models/hr_version.py#L225)).

### What `hr_payroll_attendance` actually adds

Small module, four models:

- **Attendances smart button on the payslip** — `attendance_count` + `action_open_attendances`, matched by employee + date window (no FK), and **only for versions with `work_entry_source = 'attendance'`** ([hr_payslip.py:29](../enterprise/hr_payroll_attendance/models/hr_payslip.py#L29)); calendar-source employees with attendance overtime show no button.
- **Overtime never counts as a half-day** in worked-days day math ([hr_payslip_worked_days.py:9](../enterprise/hr_payroll_attendance/models/hr_payslip_worked_days.py#L9)).
- **Access widening**: `ruleset_id` and `overtime_from_attendance` become visible to payroll users instead of HR managers only ([hr_employee.py:7](../enterprise/hr_payroll_attendance/models/hr_employee.py#L7), [hr_version.py:7](../enterprise/hr_payroll_attendance/models/hr_version.py#L7)).
- Attendance search filter by employee registration number ([views](../enterprise/hr_payroll_attendance/views/hr_payroll_attendance_views.xml)).

---

## 6. UI Entry Points

| Task | Path |
|---|---|
| View attendance records | Attendances → Attendances |
| Approve/refuse extra hours | Attendances → Attendances (Extra Hours column / approve buttons; needs "by manager" validation) |
| View work entries | Payroll → Work Entries |
| Regenerate work entries | Payroll → Work Entries → Regenerate wizard (see [`work_entries.md`](work_entries.md)) |
| Regenerate overtime lines only | Attendances → Configuration → Overtime Rulesets → Regenerate Overtimes |
| Create overtime ruleset | Attendances → Configuration → Overtime Rulesets (Attendance Administrator only) |
| Assign ruleset to contract | Payroll → Employees → [Employee] → Contract tab → Overtime Ruleset field |

`work_entry_source` on the employee/contract-template form is invisible until `hr_work_entry_attendance` is installed ([hr_employee_views.xml:8](../enterprise/hr_work_entry_attendance/views/hr_employee_views.xml#L8)).

---

## 7. Configuration

### 7a. Company settings (Attendances → Configuration → Settings)

All stored on `res.company` ([res_company.py:20](../addons/hr_attendance/models/res_company.py#L20), surfaced in [res_config_settings.py](../addons/hr_attendance/models/res_config_settings.py)):

| Setting | Behavior change |
|---|---|
| **Extra Hours Validation** (`attendance_overtime_validation`) | `no_validation` → overtime lines are born `approved` and (with a typed paid rule) become overtime work entries at the next regeneration; `by_manager` → lines are born `to_approve` and produce **no overtime work entry** until approved (§4f) |
| **Display Extra Hours** (`hr_attendance_display_overtime`) | Shows the approved extra-hours balance to employees in kiosk/systray and on the employee form |
| **Automatic Check Out** + tolerance (`auto_check_out`, default tolerance 2h) | Arms the auto check-out cron (§8a) |
| **Absence Management** (`absence_management`) | Arms the absence-detection cron (§8b) and enables negative "undertime" lines via `employee_tolerance` |
| **Device & Location Tracking** (`attendance_device_tracking`) | Records GPS/IP/browser on check-in/out |
| Kiosk mode / barcode source / PIN / systray | Pure capture-UX; no payroll effect. Legacy `overtime_company_threshold`/`overtime_employee_threshold` are dead ("Remove in master") — tolerances live on the rules now |

### 7b. Overtime ruleset setup

**Step 1: Create a ruleset** — `Attendances → Configuration → Overtime Rulesets → New`; Rate Combination Mode = Maximum Rate (most common; `sum` mode has the duplicate-hours behavior of §4e).

**Step 2: Add rules.** Daily overtime vs the employee's own schedule:

| Field | Value |
|---|---|
| Based Off | Quantity |
| Period | Day |
| Differs | from the amount defined on the contract *(= `expected_hours_from_contract=True`)* |
| Pay Extra Hours | Yes |
| Work Entry Type | your overtime type — **the rate comes from the type** (Salary Rate is readonly, computed from `work_entry_type_id.amount_rate`) |

Weekend/non-working days:

| Field | Value |
|---|---|
| Based Off | Timing |
| Type | On any non-working day |
| From/To | 0:00 → 24:00 |
| Work Entry Type | a type with the weekend rate (e.g. 2.0) |

**Step 3: Assign to contract** — Employee → Contract → **Overtime Ruleset** field. Verify it is actually set on every version; NULL = no overtime, silently.

**Step 4: Regenerate in correct order (when configuring after attendances already exist)**
1. `Attendances → Configuration → Overtime Rulesets → Regenerate Overtimes` — rebuilds overtime lines
2. Payroll → Work Entries → Regenerate (period + employees) — splits work entries using those lines

**Both steps are required** in this backfill scenario: the ruleset button rebuilds lines only (§4f). In day-to-day operation no manual step is needed — check-out and approve/refuse regenerate automatically.

### 7c. Recipe — Georgian client, fixed schedule + paid overtime

1. Work entry types: create/verify an overtime type per rate you pay (e.g. "Overtime 125%": `amount_rate = 1.25`, `is_extra_hours = True` so it doesn't dilute the monthly hourly rate — see [`payroll_wage_types.md`](payroll_wage_types.md)); optionally a second type for weekends.
2. Keep `work_entry_source = 'calendar'` on the versions (fixed schedule generates the base WORK100 entries; attendances then feed **only** the overtime piece). Use `'attendance'` only if pay must follow the clock exactly.
3. Build one ruleset (`max` mode): quantity/day rule from employee schedule → 125% type; timing/non_work_days rule → weekend type. Set `employer_tolerance` (e.g. 0.25h) so 5-minute overruns don't create lines.
4. Assign the ruleset on **every** `hr.version`; audit for NULLs (SQL: `SELECT id FROM hr_version WHERE ruleset_id IS NULL`).
5. Company settings: Extra Hours Validation = "Approved by Manager" (recommended — otherwise every overrun auto-pays); leave Absence Management off unless you want negative balances; Automatic Check Out optional.
6. Daily flow: employees punch (kiosk/systray/manual) → manager approves extra hours in Attendances → work entries regenerate themselves → payslip shows Attendance + overtime worked-days lines at the type rates.
7. Do not approve/pay from the attendance "Over Time" column alone — the payslip pays work entries, and only approved+typed lines become entries (§4e).

---

## 8. Crons

Both defined in [hr_attendance_data.xml](../addons/hr_attendance/data/hr_attendance_data.xml), every 4 hours.

### 8a. Automatic check-out (`_cron_auto_check_out`)

[hr_attendance.py:538](../addons/hr_attendance/models/hr_attendance.py#L538). Only companies with `auto_check_out`, only employees on non-flexible calendars. For every open attendance it computes `hours open so far + hours already worked that day`; when that exceeds `expected hours for that weekday (sum of the calendar's attendance lines, lunch included) + tolerance`, it closes the attendance. The check-out time is set so the attendance keeps exactly `expected + tolerance - previously worked` hours (clamped to ≥ check_in+1s), `out_mode = 'auto_check_out'`, and a chatter note is posted. Effect: forgotten badges can still produce up to `tolerance` hours of overtime, never an open record spanning days.

### 8b. Absence detection (`_cron_absence_detection`)

[hr_attendance.py:596](../addons/hr_attendance/models/hr_attendance.py#L596). Only companies with `absence_management`. For **yesterday**: finds employees with no overtime line that day (proxy for "didn't attend"), non-flexible calendar, contract already started — and creates a 1-second `technical` attendance at local day start. That attendance runs through normal overtime detection (§4d): a quantity rule with `expected_hours_from_contract` then yields a **negative** line ("undertime") because 0 hours were worked. Technical attendances that produced no overtime (e.g. the day was a day off or leave) are deleted again ([hr_attendance.py:626](../addons/hr_attendance/models/hr_attendance.py#L626)). Net effect: unjustified absence shows up as a negative Extra Hours balance. **It does not dock pay by itself** — for calendar-source employees the schedule still generates full paid entries; the negative line only reduces `total_overtime` (and the time-off-deductible pool, §10a).

### 8c. Capture channels (one-liners)

Kiosk (public URL `/hr_attendance/<token>`, barcode/PIN modes, [controllers/main.py](../addons/hr_attendance/controllers/main.py)), systray check-in/out with optional geolocation ([res_company.py:35](../addons/hr_attendance/models/res_company.py#L35)), and manual encode by officers are just different writers of the same `hr.attendance` record; `in_mode`/`out_mode` records the channel. Security: employees read only their own attendances (`group_hr_attendance_own_reader` on `base.group_user`); Officers manage employees where they are `attendance_manager_id`; "Manage all attendances" and Administrator widen from there ([hr_attendance_security.xml](../addons/hr_attendance/security/hr_attendance_security.xml)). Setting `attendance_manager_id` on an employee silently adds that user to the Officer group ([hr_employee.py:65](../addons/hr_attendance/models/hr_employee.py#L65)).

---

## 9. Edge Cases & Gotchas

### Public holiday × source matrix

| Employee source | Badge on public holiday |
|---|---|
| Calendar, no paid ruleset | Full scheduled holiday entry remains; badge adds no regular work entry |
| Calendar, approved paid rules | Full holiday remains and overtime work entries can be added on top; stock tests include 8h holiday + overtime |
| Attendance, fixed calendar | Closed badge overlap is subtracted from the leave interval and becomes WORK100/approved overtime; open badge is ignored |
| Attendance, flexible calendar | Special quota behavior; an upstream test keeps 8h holiday + 4 badge hours |
| Planning + attendance rules | Published shifts remain the base; approved overtime can be added, while holiday replacement uses static-calendar hours |

Odoo has no universal holiday premium, but `timing_type='leave'`, non-working-day, and quantity rules can generate one automatically. A custom payroll work log must not cover employee/date/hours already paid by native overtime. See [`public_holidays_flow.md`](public_holidays_flow.md).

| Situation | What happens |
|---|---|
| Attendance spans midnight | Split at **local midnight** of calendar timezone, not UTC midnight |
| Two attendances on same calendar day | Older work entry archived even if times don't overlap (full-day interval comparison, §4c) |
| `ruleset_id` not set on contract | No overtime lines generated; all hours = plain Attendance. #1 "Extra Hours = 0" cause |
| Any attendance touched in a week | `_update_overtime` **deletes and recreates all overtime lines of the whole week** — manual `status` and `manual_duration` edits on other days of that week are lost ([hr_attendance.py:253](../addons/hr_attendance/models/hr_attendance.py#L253)); same for the ruleset Regenerate button |
| Ruleset "Regenerate Overtimes" | Rebuilds lines only; work entries stay stale until wizard regeneration or an approve/refuse action (§4f) |
| Overtime line `status = 'to_approve'` or `'refused'` | Overtime work entry is NOT created; with `no_validation` companies lines auto-approve at creation |
| `manual_duration` edited to a smaller non-zero value | Attendance sums and time-off pool shrink, but the overtime **work entry keeps the original `duration`** ([hr_version.py:53](../enterprise/hr_work_entry_attendance/models/hr_version.py#L53)); set 0 to remove the entry |
| `sum` combination mode + several paid rules with different WE types | One work entry per type over the **same** hours — hours duplicated, each at its own type rate (§4e) |
| `employer_tolerance` on a timing rule | Ignored — only quantity rules enforce it in the v2 detection path |
| Unpaid rule (`paid=False`) | Line still created with `amount_rate 0.0` (tracking/comp-time only), never a paid work entry |
| Overtime rates | Come from `work_entry_type_id.amount_rate` (enterprise); editing the rule's rate directly is not possible in the UI |
| `expected_hours_from_contract = False` with wrong manual hours | Overtime threshold wrong (e.g. 7h manual vs 7.6h from schedule) |
| Validated work entries | Write/unlink of an attendance already linked to a validated entry is blocked. **Creation/closing of a new attendance is not protected** and can archive overlapping validated predecessors; add a validated/paid-window guard |
| Attendance ↔ line link | By `time_start == check_in` value match, not FK — external tools must keep them in sync |
| Overtime lines invisible to employees | ACL is officer-group only; employee-facing balances go through sudo computes |
| `work_entry_source = 'attendance'` | Work entries come from actual clock records; open (not checked-out) attendances are ignored; attendance during a leave overrides the leave entry |
| `work_entry_source = 'calendar'` | Work entries come from the schedule. Attendances are used **only** for overtime (and only if `ruleset_id` is set) — they are NOT converted to regular work entries in the generation path ([hr_version.py:104](../addons/hr_work_entry/models/hr_version.py#L104) + enterprise [hr_version.py:131](../enterprise/hr_work_entry_attendance/models/hr_version.py#L131)) |
| Calendar employee + save an attendance **inside** scheduled hours, after entries already generated | `_create_work_entries` runs unconditionally (no source filter) and builds a work entry from `_get_work_entries_values(check_in, check_out)` clipped to the schedule, then archives the day's full schedule entry via the full-day-interval collision → that day can collapse to just the punched duration (e.g. a 1-min punch → 1-min day) until regenerated. Punch **outside** scheduled hours → empty interval → no entry, schedule day untouched |
| Absence Management | Produces negative balance lines, not pay cuts — calendar-source employees still get full schedule entries (§8b) |
| `overtime_from_attendance` field | Legacy: hidden in the views ("to be dropped in master"), auto-computed as `bool(ruleset_id)` ([hr_version.py:283](../enterprise/hr_work_entry_attendance/models/hr_version.py#L283)); only the planning bridge still branches on it |

---

## 10. Sibling Bridges

### 10a. `hr_holidays_attendance` (community, auto_install) — overtime ↔ time off

Not covered by the holidays docs; documented here because the pool it spends is the attendance overtime balance.

- Rules gain **"Give back as time off"** (`compensable_as_leave`) — flagged rules mark their overtime lines compensable ([hr_attendance_overtime_rule.py:11](../addons/hr_holidays_attendance/models/hr_attendance_overtime_rule.py#L11)). In `sum` mode a compensable+paid rule contributes its **full** rate (not rate−1) to the combined line rate ([L22](../addons/hr_holidays_attendance/models/hr_attendance_overtime_rule.py#L22)).
- Leave types gain **"Deduct Extra Hours"** (`overtime_deductible`, [hr_leave_type.py:10](../addons/hr_holidays_attendance/models/hr_leave_type.py#L10)). For no-allocation types, requesting the leave checks the pool: `approved compensable lines − such leaves taken − deductible allocations`; negative → ValidationError at create/write/approve ([hr_leave.py:37](../addons/hr_holidays_attendance/models/hr_leave.py#L37), [L79](../addons/hr_holidays_attendance/models/hr_leave.py#L79)). Allocation-based deductible types consume the pool through allocations instead ([hr_leave_allocation.py:33](../addons/hr_holidays_attendance/models/hr_leave_allocation.py#L33)).
- Accrual plans gain a **"Per Hour Worked"** frequency whose prorata = sum of attendance `worked_hours` in the period ([hr_leave_accrual_plan_level.py:9](../addons/hr_holidays_attendance/models/hr_leave_accrual_plan_level.py#L9), [hr_leave_allocation.py:59](../addons/hr_holidays_attendance/models/hr_leave_allocation.py#L59)) — cross-ref [`hr_holidays_accrual_plans.md`](hr_holidays_accrual_plans.md).
- Dead code: `_update_leaves_overtime` filters `state == 'confirmed'` (real state is `'confirm'`) so it never matches, and it calls `hr.attendance._attendance_date` / `_update_overtimes` which **do not exist** in v19 — the leave→overtime-recompute hook is inert ([hr_leave.py:111](../addons/hr_holidays_attendance/models/hr_leave.py#L111)).

### 10b. One-liners

| Module | What it is |
|---|---|
| `hr_attendance_gantt` (enterprise) | Pure UI: gantt view for attendances, progress bar = worked vs expected hours, unavailability shading from calendars ([hr_attendance.py](../enterprise/hr_attendance_gantt/models/hr_attendance.py)) |
| `hr_work_entry_planning_attendance` (enterprise) | For `work_entry_source='planning'` + ruleset: quantity-rule threshold comes from **published planning slots** instead of the calendar, and the same overtime→WE split runs over planning-based entries ([hr_version.py:15](../enterprise/hr_work_entry_planning_attendance/models/hr_version.py#L15)) |
| `l10n_be_hr_payroll_attendance` (enterprise) | Belgian-only: folds overtime-line durations into the CP200 split-half worked-days data ([hr_version.py:12](../enterprise/l10n_be_hr_payroll_attendance/models/hr_version.py#L12)) |
| `planning_attendance` (enterprise) | Reporting only: planning vs attendance analysis view, no business logic (report/ + views/ only) |
| `hr_timesheet_attendance` (community) | Reporting only: timesheet vs attendance report + menu tweak; **no timesheet→payroll bridge** (see [`payroll_wage_types.md`](payroll_wage_types.md)) |
| `hr_work_entry_contract_attendance`, `hr_work_entry_contract_planning_attendance` (enterprise) | Dead leftover directories — no manifest, no Python files, only `__pycache__` |

---

## 11. Key Method Reference

| Method | File | What it does |
|---|---|---|
| `_update_overtime` | [addons/hr_attendance/models/hr_attendance.py:265](../addons/hr_attendance/models/hr_attendance.py#L265) | Wipes + regenerates overtime lines for the affected week range on any attendance mutation |
| `_generate_overtime_vals_v2` | [addons/hr_attendance/models/hr_attendance_overtime_rule.py:767](../addons/hr_attendance/models/hr_attendance_overtime_rule.py#L767) | Active detection pipeline: quantity + timing rules → line vals (methods without `_v2`/marked "TO REMOVE IN MASTER" are legacy) |
| `_extra_overtime_vals` | [addons/hr_attendance/models/hr_attendance_overtime_rule.py:804](../addons/hr_attendance/models/hr_attendance_overtime_rule.py#L804) | Combines rates of overlapping rules per ruleset `max`/`sum` mode |
| `_create_work_entries` | [enterprise/hr_work_entry_attendance/models/hr_attendance.py:20](../enterprise/hr_work_entry_attendance/models/hr_attendance.py#L20) | Triggered on attendance save; creates work entries, archives same-day predecessors |
| `_generate_work_entries_postprocess` | [addons/hr_work_entry/models/hr_version.py:501](../addons/hr_work_entry/models/hr_version.py#L501) | Splits multi-day spans at local midnight; converts date_start/stop → date + duration |
| `_to_intervals` | [addons/hr_work_entry/models/hr_work_entry.py:231](../addons/hr_work_entry/models/hr_work_entry.py#L231) | Converts work entry to full-day interval (00:00–23:59) for overlap detection |
| `_get_attendance_intervals` | [enterprise/hr_work_entry_attendance/models/hr_version.py:116](../enterprise/hr_work_entry_attendance/models/hr_version.py#L116) | Builds attendance + overtime intervals; subtracts overtime from attendance |
| `_get_real_attendance_work_entry_vals` | [enterprise/hr_work_entry_attendance/models/hr_version.py:199](../enterprise/hr_work_entry_attendance/models/hr_version.py#L199) | Creates work entry vals for attendance vs overtime intervals (type choice, sum-mode fan-out) |
| `_update_related_work_entries` | [enterprise/hr_work_entry_attendance/models/hr_attendance_overtime.py:20](../enterprise/hr_work_entry_attendance/models/hr_attendance_overtime.py#L20) | Approve/refuse → day-based work-entry regeneration |
| `_get_work_hours` | [enterprise/hr_payroll/models/hr_version.py:252](../enterprise/hr_payroll/models/hr_version.py#L252) | Aggregates draft+validated work entry hours by type for payslip worked days |
| `regenerate_work_entries` | [addons/hr_work_entry/wizard/hr_work_entry_regeneration_wizard.py:97](../addons/hr_work_entry/wizard/hr_work_entry_regeneration_wizard.py#L97) | Wizard: full-range mode + `slots=` day-mode used by all bridge hooks |
| `_generate_work_entries` | [addons/hr_work_entry/models/hr_version.py:418](../addons/hr_work_entry/models/hr_version.py#L418) | Core generation (delta-based) — see [`work_entries.md`](work_entries.md) |
| `_cron_auto_check_out` / `_cron_absence_detection` | [addons/hr_attendance/models/hr_attendance.py:538](../addons/hr_attendance/models/hr_attendance.py#L538) / [L596](../addons/hr_attendance/models/hr_attendance.py#L596) | §8 crons |

---

## 12. Related Docs

- [`INDEX.md`](INDEX.md)
- [`work_entries.md`](work_entries.md) — the work-entry engine this bridge feeds (states, conflicts, generation, wizard)
- [`hr_payroll.md`](hr_payroll.md) — payslip lifecycle consuming the work entries
- [`payroll_wage_types.md`](payroll_wage_types.md) — how worked-days lines become money; overtime-rate and sum-mode gotchas
- [`hr_employee_versions.md`](hr_employee_versions.md) — `hr.version` (where `ruleset_id` and `work_entry_source` live)
- [`resource_calendars.md`](resource_calendars.md) — the schedule/interval math used for thresholds and lunch
- [`hr_holidays_accrual_plans.md`](hr_holidays_accrual_plans.md) / [`hr_holidays_time_off_units.md`](hr_holidays_time_off_units.md) — time-off side of the §10a bridge

# Attendance and Work Entries — Odoo 20

> Reviewed against the local Odoo 20 source on 2026-09-22. This is a source review, not a fresh database/payroll test.
> Main modules: [`hr_attendance`](../addons/hr_attendance/), [`hr_work_entry`](../addons/hr_work_entry/), [`hr_holidays_attendance`](../addons/hr_holidays_attendance/), [`hr_payroll_attendance`](../enterprise/hr_payroll_attendance/).

## The Architecture Has Changed

This checkout no longer uses the documented Odoo 19 chain of overtime rulesets → overtime lines → stored `hr.work.entry` records. `hr_work_entry_attendance` is a leftover cache-only directory here, without an installable manifest or Python source. The former ruleset, `manual_duration`, approval-to-regeneration wizard and same-day stored-entry archiving explanations do not describe the current implementation.

The current chain is:

```text
Clock record: hr.attendance (time type, state, check-in/out, break)
    → hr.time.rule evaluates eligible validated source intervals
    → reclassifies/splits attendance records or creates deficit outputs
    → hr.version.generate_work_entries(date_from, date_to)
    → returns day/duration dictionaries built from schedules, attendance and leave
    → payroll aggregates these values into payslip worked-day lines
```

`hr_work_entry` still provides **Time Types** (`hr.work.entry.type`) and generation methods, but its model imports do not define the old persisted `hr.work.entry` model. The generation API returns a Python list, not a recordset to validate or archive. See [`hr_work_entry/models/__init__.py`](../addons/hr_work_entry/models/__init__.py), [`hr_version.py`](../addons/hr_work_entry/models/hr_version.py), and [`payroll hr_version.py`](../enterprise/hr_payroll/models/hr_version.py).

## Module Responsibilities

| Module | Responsibility |
|---|---|
| `hr_work_entry` | Time types, `hr.time.rule`, source-processing mixin, schedule/leave interval generation and daily aggregation; depends on `hr` |
| `hr_attendance` | Clock records, validation, breaks, attendance rule outputs, kiosk/systray and scheduled processing; directly depends on `hr_work_entry` |
| `hr_holidays_attendance` | Attendance/leave integration, attendance-based generation and time-rule allocation credits; depends on Attendances and Time Off, auto-install |
| `hr_payroll_attendance` | Payslip attendance links and payroll options; auto-install with dependencies `hr_attendance_gantt`, `hr_holidays_attendance`, `hr_payroll` |

Sources: the modules' [`attendance manifest`](../addons/hr_attendance/__manifest__.py), [`work-entry manifest`](../addons/hr_work_entry/__manifest__.py), [`holiday bridge manifest`](../addons/hr_holidays_attendance/__manifest__.py), and [`payroll bridge manifest`](../enterprise/hr_payroll_attendance/__manifest__.py).

## Attendance Records

Source: [`hr_attendance.py`](../addons/hr_attendance/models/hr_attendance.py).

| Field | Current behavior |
|---|---|
| `employee_id`, `check_in`, `check_out` | Employee and UTC clock timestamps; an unchecked-out record is open |
| `date` | Check-in date in the employee timezone |
| `worked_hours` | Elapsed check-in/out hours **minus explicit `break_duration`**; no automatic schedule-lunch subtraction in this compute |
| `break_duration` | Extra unpaid break hours; cannot be negative, exceed elapsed duration, or be nonzero on an open record |
| `work_entry_type_id` | Required **Time Type**, defaulting to the company's attendance type |
| `state` | `draft`, `validated`, `refused` |
| `time_rule_id` | Rule that produced/reclassified this record |
| `source_attendance_id` | Actual relation to the source attendance |
| `overtime_attendance_ids` | Reverse relation to output attendances |
| `source_stale` | Warns that a surviving rule output's source was edited/deleted |
| `in_mode`, `out_mode` | Capture origin, including kiosk, systray, manual and technical modes |

Standard validity checks prohibit overlapping employee attendance intervals and multiple open records. Internal rule processing uses `skip_time_rules`, which also bypasses the overlap check; generated data must not be interpreted as if every row were an independent raw punch. `copy()` is blocked.

Changing source times, break, employee or time type marks surviving output records stale. `action_mark_reviewed()` clears the marker; it is an acknowledgment, not a regeneration of the source. Deletion also marks surviving outputs stale.

## Validation

Company [`attendance_validation`](../addons/hr_attendance/models/res_company.py) controls ordinary creation:

- `no_validation`: ordinary attendance records are created validated.
- Manager-validation mode: records start draft and require validation.
- `tolerance_validation`: closed draft source records may be validated automatically when elapsed time is within `attendance_validation_tolerance` of expected daily attendance, or no expected time exists.

Rule-generated records carrying `time_rule_id` or `source_attendance_id` default to validated. Explicitly supplied states take precedence over those defaults. `_update_tolerance_state()` uses elapsed clock time for its comparison, not the break-adjusted `worked_hours` value.

`action_validate()` writes validated; `action_reset_to_draft()` writes draft; `action_refuse()` writes refused with rule processing skipped. Generation selects **closed, validated** attendances. Draft/refused/open records do not supply clock intervals to payroll generation.

## Time Rules Replace Overtime Rulesets

Source: [`hr.time.rule`](../addons/hr_work_entry/models/hr_time_rule.py), extended by [`hr_attendance`](../addons/hr_attendance/models/hr_time_rule.py).

| Setting | Purpose |
|---|---|
| `sequence`, `active`, company/country | Rule ordering and scope |
| `employee_domain` | Select eligible employees; no per-version `ruleset_id` assignment |
| `condition_work_entry_type_ids` | Source time types the rule considers |
| `threshold_operator` | `exceed` or `less_than` |
| `working_hours_mode` | Daily/weekly schedule or fixed daily/weekly threshold |
| `calendar_source`, `resource_calendar_id` | Employee or reference schedule baseline |
| `expected_hours` | Threshold used for fixed-hour modes |
| `quantity_period`, `week_start` | Day/week evaluation and configurable week boundary |
| Weekday flags, `apply_on_public_holidays` | Applicable days |
| `timing_start`, `timing_stop` | Time window inside a day |
| `employer_tolerance`, `employee_tolerance` | Threshold tolerances |
| `work_entry_type_id` | Type assigned to excess/missing time; may be empty for integrations that only add options/allocation effects |
| `amount_rate` | Stored editable compute from the output time type's rate |

The SQL timing constraint requires **start < stop**, with start below 24 and stop at most 24. A 22:00–06:00 overnight window cannot be entered as one rule in this implementation; use separate windows where appropriate. The former `base_off`, `timing_type`, `paid` and ruleset `max`/`sum` descriptions are obsolete here.

The rule engine evaluates interval slices and applies outputs through `_apply_output()`. Depending on coverage, it can repurpose a source record as the first output, shorten its remaining interval, and create further output/remainder records. This changes attendance records; it does not merely attach a separate numerical overtime balance. Overlapping rules can carry accumulated premium-pay/allocation effects through the pipeline. Do not reuse the old “one duplicate work entry per paid rule in sum mode” explanation.

Enterprise [`hr_payroll_attendance.hr_time_rule`](../enterprise/hr_payroll_attendance/models/hr_time_rule.py) propagates accumulated premium-pay category IDs to output `category_options_ids`. Payroll groups hours by time type **and** sorted category options.

## When Rules Run

[`hr.time.rule.source.mixin`](../addons/hr_work_entry/models/hr_time_rule_source_mixin.py) triggers processing on creation and relevant writes unless `skip_time_rules` is set. Attendance's source domain requires `state = validated` and completed start/end timestamps.

The trigger distinguishes unfinished periods:

| Period | Immediate processing |
|---|---|
| Past day | Daily excess and deficit rules |
| Current/future day | Daily excess only |
| Completed week | Weekly excess rules |
| Weekly deficit | Scheduled processing only |

The mixin collects day/week ranges, searches active company-eligible rules and combines their interval outputs. There is no current `_update_overtime()` weekly delete-and-recreate pipeline. Editing a rule is not equivalent to running the removed Odoo 19 ruleset regeneration button; inspect source records, output records and the current processing methods when backfilling.

Employee `total_overtime` now sums `worked_hours` of attendance records with a nonempty `time_rule_id`. The base compute does not filter to approved overtime lines or even add a state condition. It should not be read as the old approved, spendable time-off balance. See [`hr_employee.py`](../addons/hr_attendance/models/hr_employee.py).

## Attendance-Based Versus Schedule-Based Payroll

[`hr.version.attendance_based`](../addons/hr_attendance/models/hr_version.py) defaults from the company and is exposed on the employee. The actual attendance generation integration is in [`hr_holidays_attendance/models/hr_version.py`](../addons/hr_holidays_attendance/models/hr_version.py).

- **Attendance based:** base schedule attendance intervals start empty; closed validated clock records supply working time. Time off is still accounted for through the leave pipeline.
- **Schedule based:** the schedule supplies ordinary days, but a validated attendance touching a local day removes the schedule's regular attendance for that **whole day** and supplies its clock intervals instead. This is not “schedule plus overtime only.”

For both modes, clock intervals subtract `break_duration` by trimming the end. Overlaps between attendance and working-time leave are split and resolved by time-type sequence, with the lower sequence winning. Worked time removes overlapping absence intervals through the leave integration. Exact holiday outcomes depend on time-type classification, sequence, calendar and actual clock intervals; the previous Odoo 19 holiday/source matrix is not a current guarantee.

Generation clips to version dates, converts intervals into local dates/durations, and merges values sharing the date, time type, employee, version and company (with extension hooks for additional keys). Source relations such as `attendance_ids` are aggregated. Two non-overlapping attendances on the same day can therefore contribute to the same aggregate; the old bug narrative about archiving the earlier stored work entry does not apply to this implementation.

Example: an 08:00–12:00 attendance and a 13:00–17:00 attendance with the same type and no breaks can contribute 8 hours on the same date. An overnight attendance is divided using version timezone boundaries during postprocessing, not assumed to belong entirely to its UTC start date.

## Payroll Integration

[`hr.payslip`](../enterprise/hr_payroll/models/hr_payslip.py) calls version generation for the relevant date range and builds worked-day values. [`hr.version._get_work_hours()`](../enterprise/hr_payroll/models/hr_version.py) sums returned durations by type/options; it does not search draft/validated persisted `hr.work.entry` rows.

The payroll attendance extension adds:

- `attendance_count` for attendance-based slips, computed from validated overlapping records with additional date grouping/filtering.
- An Attendances action that opens the employee's records in gantt/list; the action domain itself is employee-wide, with the payslip start used as the initial display date.
- `payslip_id` on attendance, selecting the latest non-draft/non-canceled payslip covering the localized check-in date. This is a computed lookup, not a permanent unique payroll allocation.
- Payroll category options on attendance and wider payroll-user access to `attendance_based`.

Sources: [`payslip extension`](../enterprise/hr_payroll_attendance/models/hr_payslip.py), [`attendance extension`](../enterprise/hr_payroll_attendance/models/hr_attendance.py).

## Scheduled Jobs and Capture Settings

Source: [`hr_attendance_data.xml`](../addons/hr_attendance/data/hr_attendance_data.xml).

| Job | Shipped interval | What it calls |
|---|---|---|
| Automatic check-out | 4 hours | `_cron_auto_check_out()` |
| Absence detection | 4 hours | `_cron_absence_detection()` |
| Daily time rules | 1 day | `_cron_process_day_undertime_rules()` |
| Weekly time rules | 1 week | `_cron_process_week_time_rules()` |

Automatic checkout supports tolerance and specific-time modes. Tolerance compares open time plus earlier worked hours with expected hours plus the configured tolerance. Specific-time mode uses the configured local cutoff. These are scheduled evaluations, not a guarantee that a record closes at the exact wall-clock cutoff.

Absence detection creates a one-second validated technical attendance for eligible employees without attendance yesterday, allowing deficit rules to produce typed missing-time outputs. Technical sources without child outputs are removed. Payroll impact depends on the resulting time types and payroll rules; it is no longer correctly described as only a negative `manual_duration` balance.

**Source discrepancy:** the weekly helper describes daily evaluation of rules whose configured week ended yesterday, and filters `week_start` to today's weekday; its shipped cron runs weekly. A weekly schedule on one weekday cannot be assumed to process every possible `week_start` setting. Verify the installed cron schedule when using different week boundaries.

Other current company settings include single check-in, break entry at checkout, device/location tracking, check-in pictures, kiosk PIN/barcode and systray access. These write the same attendance model; they do not bypass its payroll eligibility requirements.

## Access and Troubleshooting

Source: [`attendance security`](../addons/hr_attendance/security/hr_attendance_security.xml) and [`access rules`](../addons/hr_attendance/security/ir.access.csv).

Own-record, officer, all-attendance and administrator privileges control different scopes. `is_manager` accepts all-attendance users or officers assigned as the employee's attendance manager; `can_edit` also considers own-attendance rights. Field visibility and computed booleans supplement model/record access; they are not a substitute for it.

| Symptom | Check in Odoo 20 |
|---|---|
| Clocked hours absent from payroll | Closed and validated attendance; version dates/timezone; `attendance_based`; installed holiday/payroll bridge |
| Overtime not classified | Active time rule, employee/company scope, condition time types, threshold, window and whether the period has finished |
| A schedule day shrinks after a punch | Schedule-based mode replaces regular schedule attendance for days touched by validated clock records |
| Hours differ from clock elapsed time | Explicit breaks, local-day splitting, overlapping time-type priorities and leave handling |
| Warning marker on rule output | Source changed/deleted; review the output before clearing `source_stale` |
| Missing weekly deficit output | Configured week boundary and actual cron weekday; weekly deficits are cron-only |
| Overtime total differs from payslip | Total sums typed rule outputs; payroll uses validated interval generation and salary rules |

## Related Docs

- [Work entries](work_entries.md)
- [Payroll](hr_payroll.md)
- [Employee versions](hr_employee_versions.md)
- [Resource calendars](resource_calendars.md)
- [Public holidays](public_holidays_flow.md)

These neighboring documents may still describe the former architecture; use the source links above for the behavior reviewed here.

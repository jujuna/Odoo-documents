# Employee & Version Engine — `hr.employee` / `hr.version`

> **Module:** `hr` (community core) + employee-side pieces of `hr_attendance` / `planning` | **Path:** [`addons/hr/`](../addons/hr/)
> Verified from source 2026-07-11. Related docs: [`hr_payroll.md`](hr_payroll.md), [`work_entries.md`](work_entries.md), [`resource_calendars.md`](resource_calendars.md).

## What It Does & Why It Exists

In Odoo 19 there is no `hr.contract` model. All contract data — wage, calendar, structure type, contract dates — lives on `hr.version`, and an employee is a **timeline of versions**: each version says "from this date, these are the employee's terms". The employee form is a window onto one version at a time. Understanding this engine is mandatory for payroll work: payslips, work entries, and calendars all resolve "which version was in force on date X".

---

## The Big Picture — How Versions Work

```
hr.employee ──_inherits──> hr.version (via version_id, COMPUTED, not stored)
    version_ids (o2m, ordered by date_version)
    current_version_id (STORED compute: latest version with date_version <= today)
```

- `hr.employee` delegates to `hr.version` with a twist: `version_id` is a **computed, non-stored** many2one ([hr_employee.py:46-54](../addons/hr/models/hr_employee.py#L46)). If the context carries `version_id` (smart buttons on the version timeline do this), the form transparently reads *and writes* that historical version; otherwise it's the current one.
- **A version is in force from its `date_version` until the day before the next version's `date_version`**, clipped by contract end: `date_start = max(date_version, contract_date_start)`, `date_end = min(next.date_version − 1, contract_date_end)` ([hr_version.py:554-568](../addons/hr/models/hr_version.py#L554)).
- `_get_version(date)`: latest version with `date_version <= date`; before the first version it returns the earliest one ([hr_employee.py:547-554](../addons/hr/models/hr_employee.py#L547)). Ties are impossible (unique index employee+date_version for active versions); gaps don't exist by construction.
- `current_version_id` is a **stored compute keyed on "today"**, refreshed by a daily cron (`_cron_update_current_version_id`) — between midnight and the cron run, the stored value can be stale ([hr_employee.py:515-533](../addons/hr/models/hr_employee.py#L515)).

### How writes are routed (employee vs version)

The split key is `field.inherited`: on employee create/write, all inherited-from-version values are peeled off and written to the resolved `version_id` in one call, stamping `last_modified_date/_uid` and posting a chatter note per employee ([hr_employee.py:1415-1435](../addons/hr/models/hr_employee.py#L1415)). Fields needing group protection are re-declared on the employee with explicit `inherited=True` (contract dates block: hr manager; payroll re-exposes wage fields to payroll users). Silent behavior: on create, version fields the user can't write are **dropped without error** ([hr_employee.py:255](../addons/hr/models/hr_employee.py#L255)).

### Creating versions

`create_version(values)` ([hr_employee.py:556-628](../addons/hr/models/hr_employee.py#L556)): finds the version in force at `date_version`, copies it, applies the diff. Two traps:

- **A version already existing at that exact date is returned as-is and your `values` are silently discarded.**
- Contract dates are inherited from the contract in force at that date; changing `contract_date_end` in the same call first syncs it onto all sibling versions.

---

## Contract Semantics

- A version **is a contract** iff `contract_date_start` is set; there is no state field — draft/open/close is gone, everything derives from dates (`is_current/is_past/is_future/is_in_contract`).
- All versions of one contract share `contract_date_start/end`; **writing contract dates on one version fans out to all siblings** of that contract ([hr_version.py:299-353](../addons/hr/models/hr_version.py#L299)); for a single-version employee, writing `contract_date_start` also moves `date_version`.
- Overlapping contract periods among active versions are forbidden (the error suggests a second employee record for concurrent contracts); sequential contracts are fine. A new contract is blocked while the current one is open-ended.
- The period tests payroll uses: `_get_versions_with_contract_overlap_with_period` (per employee) and the all-employees variant that **includes archived employees** ([hr_employee.py:1604-1611](../addons/hr/models/hr_employee.py#L1604)).
- Contract expiry notifications: daily cron matches `contract_date_end == today + company.contract_expiration_notice_period` (default 7 days) by **exact equality** — one missed cron day = permanently missed notification ([hr_employee.py:1160](../addons/hr/models/hr_employee.py#L1160)). The activity goes to `hr_responsible_id`.

## Contract Templates

A template is simply an `hr.version` with `employee_id = False`. Applying one (on version create, employee onchange, or the "Load template" wizard) passes through the whitelist `_get_whitelist_fields_from_template` — base: `job_id, department_id, contract_type_id, structure_type_id, wage, resource_calendar_id, hr_responsible_id`; payroll modules extend it (`work_entry_source`, `payroll_properties`) ([hr_version.py:430-446](../addons/hr/models/hr_version.py#L430)). **Everything not whitelisted is dropped** — the known trap for custom fields (and even `hourly_wage` in stock code): extending this whitelist is mandatory for any custom module adding version fields that hiring should carry over.

---

## Calendar, Resource, and Timezone Wiring

```
hr.version.resource_calendar_id   (STORED — the versioned truth)
    ↑ related/inherited, store=False
hr.employee.resource_calendar_id  (proxy through context/current version)
resource.resource.calendar_id     (materialized "current" calendar)
```

- Sync is **current-version-only**, three-way: version→resource only when the written version is current; employee.write→resource same guard; resource→employee writes back ([hr_version.py:586-591](../addons/hr/models/hr_version.py#L586), [hr_employee.py:1436-1442](../addons/hr/models/hr_employee.py#L1436)). Editing a past/future version's calendar never touches the resource — anything reading `resource.calendar_id` directly sees only today's calendar; historical accuracy exists only through `_get_calendars(date)` / `_get_version_periods`.
- `hr.version.resource_calendar_id` has **no Python default** ([hr_version.py:139](../addons/hr/models/hr_version.py#L139)) — empty is a deliberate, legal state meaning "fully flexible" (the *resource*, by contrast, defaults to the company calendar). Payroll consequence of empty + calendar work-entry source: silently zero payslip (see [work_entries.md](work_entries.md) gotchas).
- `_get_calendars(date)` returns the calendar of the version **in contract** on that date — if no contract covers the date it silently falls back to today's calendar, not the version in force ([hr_employee.py:1553-1563](../addons/hr/models/hr_employee.py#L1553)).
- **tz is not versioned**: `version.tz` → `employee.tz` → `resource.tz`. Resolution order for computations: calendar tz → employee tz → company calendar tz → UTC. Writing employee tz propagates to the linked user.
- Flexible flags live on the version as stored computes: `is_fully_flexible` = no calendar; `is_flexible` = that or `calendar.flexible_hours` (full math consequences in [`resource_calendars.md`](resource_calendars.md)).
- `employee.active` is a stored related to `resource_id.active` — archiving the employee archives the resource in one write. Versions have their own `active`; nothing archives them with the employee, and you can never archive/detach/delete the last one.

---

## Departure

Departure fields (`departure_reason_id/description/date`) live **on the version** with `copy=False` — they never leak into new versions. The wizard rejects departure dates before the current contract start, archives employee (and optionally the user), writes departure fields via the employee (→ current version), and sets `contract_date_end = departure_date`, which fans out to the contract's versions ([hr_departure_wizard.py:61-133](../addons/hr/wizard/hr_departure_wizard.py#L61)). Unarchiving clears departure fields.

---

## Employee-Side Attendance & Planning (what payroll touches)

**Attendance** (`hr_attendance`): status fields `attendance_state`, `hours_today`, `total_overtime` (= approved overtime only); `hours_last_month` actually computes **current month-to-date** (misnamed, admitted in the docstring). Check-in/out has a single model entry point `_attendance_action_change` used by kiosk and systray routes — there is no `attendance_manual` anymore. Overlap prevention is a **Python constraint only** (no SQL exclusion), duplication via `copy()` is blocked, and the attendance↔overtime-line link is a *value match* on `check_in == time_start`, not a FK. Two opt-in company automations, both crons on `hr.attendance`: auto check-out (closes forgotten sessions at expected hours + tolerance, skips flexible calendars) and absence detection (creates 1-second `technical` attendances at midnight so the ruleset produces *negative* overtime for no-show days) ([hr_attendance.py:538-632](../addons/hr_attendance/models/hr_attendance.py#L538)). Setting `attendance_manager_id` silently grants that user the attendance-officer group.

**Planning** (`planning`): `default_planning_role_id`/`planning_role_ids` are related to the **resource**, where roles actually live. Slot `allocated_hours` resolves through the calendar: assigned+planned slots count effective working hours over the window × `allocated_percentage`; flexible employees saturate at `hours_per_day`/day and `full_time_required_hours`/week; fully-flexible employees count raw slot time with no caps and are never "unavailable". Archiving an employee unassigns future slots. Employees without users get a token-based portal link to their schedule.

**The payroll bridges are UI shells**: `hr_payroll_attendance` and `hr_payroll_planning` only add smart buttons/counters on the payslip (attendances of the period; **published** slots of the period) plus a rounding tweak — all payslip-numeric behavior lives in the `hr_work_entry_*` layer ([`work_entries.md`](work_entries.md)).

---

## Employee Self-Service Reality (verified 2026-07-12)

A regular internal user (`base.group_user`, non-HR) **cannot open `hr.employee` at all** — there is no ACL row for it ([ir.model.access.csv:4-6](../addons/hr/security/ir.model.access.csv#L4); only `hr.employee.public` is readable). The framework enforces this actively: `get_views` raises a RedirectWarning pushing the user to the public-employee action, and reads on private fields are rerouted/blocked ([hr_employee.py:1082-1202](../addons/hr/models/hr_employee.py#L1082)). "My Profile" opens a **`res.users` preferences dialog**, not the employee form — employee data appears there only as related fields whitelisted in `SELF_READABLE_FIELDS`/`SELF_WRITEABLE_FIELDS` ([res_users.py:121-126, 249-262](../addons/hr/models/res_users.py#L249)). `hr.employee.public` is a separate `_auto=False` SQL-view model with its own views — pages inherited into `hr.view_employee_form` never appear there.

Consequence for custom development: any "employee sees/edits own records" feature must live on the custom model itself (own menu/action, default `employee_id` from `user.employee_id`, ACL for `base.group_user` + record rule on `employee_id.user_id`), like hr_expense/hr_leave — never as a page on the employee form, which only HR officers reach.

## Gotchas & Non-Obvious Behavior

- **`create_version` silently ignores `values`** when a version already exists at that exact date.
- **`current_version_id` staleness** until the daily cron; anything reading it at 00:05 may get yesterday's version.
- **Import-time `today()` defaults**: `_get_version()` and `_is_in_contract()` evaluate their default date once at class load — a worker alive across midnight resolves "today" as yesterday when the argument is omitted ([hr_employee.py:547](../addons/hr/models/hr_employee.py#L547)).
- **Search ≠ display on `date_start/date_end`**: their search methods map straight to contract dates, ignoring the `date_version` clamping — domains return different rows than displayed values imply ([hr_version.py:570-574](../addons/hr/models/hr_version.py#L570)).
- **Contract-date fan-out is silent** across sibling versions; batch-writing contract dates across different contracts raises.
- Overlap/uniqueness constraints apply to **active versions only** — archived versions may overlap or duplicate dates.
- With context `version_id`, the standard employee form edits a historical version — an automation writing "to the employee" may not be touching the current terms.
- Seniority proxy `_get_first_version_date` treats a gap ≥ 4 days between versions as an employment break; payroll's "occupations" logic uses the same 4-day tolerance.

---

## Related Docs

- [`INDEX.md`](INDEX.md)
- [`resource_calendars.md`](resource_calendars.md) — the calendar/interval math this engine delegates to
- [`payroll_wage_types.md`](payroll_wage_types.md) — wage fields on the version and how pay computes
- [`work_entries.md`](work_entries.md) — how versions drive work entry generation
- [`hr_payroll.md`](hr_payroll.md) — payslip lifecycle; version-side payroll extension facts

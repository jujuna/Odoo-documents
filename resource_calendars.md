# Resource Calendars — The Time Math Engine

> **Module:** `resource` (community core) | **Path:** [`addons/resource/models/`](../addons/resource/models/)
> **Updated by Codex and verified from source 2026-07-12.** Related docs: [`public_holidays_flow.md`](public_holidays_flow.md), [`hr_employee_versions.md`](hr_employee_versions.md), [`work_entries.md`](work_entries.md), [`payroll_wage_types.md`](payroll_wage_types.md).

## What It Does & Why It Exists

`resource.calendar` is where "8 hours a day, Monday to Friday" is defined, and its interval engine is the math foundation under payroll, work entries, time off, attendance overtime, and planning. Every "how many hours/days did X work between two dates" question in Odoo ends up here. Payroll cares because `hours_per_day` converts work-entry hours into payslip days, and the flexible/fully-flexible distinctions decide whether that math works at all. The module itself is `category: Hidden` with no business UI of its own ([__manifest__.py:7](../addons/resource/__manifest__.py#L7)) — it exists to be consumed.

## The Model Family

| Model | What it is | Key point |
|---|---|---|
| `resource.calendar` | A weekly (or two-weekly) working schedule + the interval engine | One per company minimum; every company auto-creates a "Standard 40 hours/week" at creation ([res_company.py:35-45](../addons/resource/models/res_company.py#L35), bootstrap [resource_data.xml:4-17](../addons/resource/data/resource_data.xml#L4)) |
| `resource.calendar.attendance` | One time slot: weekday + hour_from/hour_to + day_period | Carries `duration_days` — the day-weight used by all day counting |
| `resource.calendar.leaves` | A calendar exception: public holiday (global) or one resource's absence | This is where validated `hr.leave` records materialize |
| `resource.resource` | The schedulable thing (human or material) | Holds `calendar_id` (empty = fully flexible) and the mandatory `tz` |
| `resource.mixin` | Abstract glue: auto-creates one resource per record | `hr.employee` inherits it; exposes the employee-facing day-math API |
| `res.users.resource_calendar_id` | Related to the user's resources' calendar | Trap: admin's *first* login tz write also rewrites the default calendar's tz ([res_users.py:16-27](../addons/resource/models/res_users.py#L16)) |

Sibling `resource_mail` only adds `color`/`im_status` to resources for avatar cards — no business logic ([resource_resource.py:8-19](../addons/resource_mail/models/resource_resource.py#L8)).

---

## The Fields That Drive Everything

| Field | How it's computed | Why payroll cares |
|---|---|---|
| `hours_per_week` | Sum of non-lunch, non-section attendance spans, ÷2 for two-week calendars ([resource_calendar.py:691-697](../addons/resource/models/resource_calendar.py#L691)); recomputed on any attendance change, **skipped for flexible calendars** ([resource_calendar.py:217-221](../addons/resource/models/resource_calendar.py#L217)) | `work_time_rate` denominator |
| `hours_per_day` | `hours_per_week ÷ distinct weekdays with any attendance` — **a half-day counts as a full weekday** ([resource_calendar.py:680-703](../addons/resource/models/resource_calendar.py#L680)); same flexible skip ([resource_calendar.py:210-215](../addons/resource/models/resource_calendar.py#L210)) | The hours→days conversion on every payslip line ([hr_payslip.py:831-855](../enterprise/hr_payroll/models/hr_payslip.py#L831)) |
| `schedule_type` / `flexible_hours` | Selection `fully_fixed`/`flexible`; `flexible_hours` is a stored compute+inverse mirror of it ([resource_calendar.py:163-170](../addons/resource/models/resource_calendar.py#L163)) | Flips all the math below |
| `full_time_required_hours` | **Silently resets to the company calendar's hours_per_week on recompute** (triggered by own `hours_per_week` changes too), despite being user-editable; company-less calendars keep the manual value ([resource_calendar.py:158-161](../addons/resource/models/resource_calendar.py#L158)) | Weekly cap for flexible employees; `is_fulltime` denominator |
| `two_weeks_calendar` | Alternating week-0/week-1 rows; which real week is which comes from `(toordinal-1)//7 % 2` — deliberately not ISO weeks ([resource_calendar_attendance.py:67-75](../addons/resource/models/resource_calendar_attendance.py#L67)) | Alternating schedules |
| `duration_based` | "Attendance based on duration" mode: slots are entered as durations and auto-centered around 12:00 via the `duration_hours` inverse; lunch rows are forbidden ([resource_calendar_attendance.py:61-96](../addons/resource/models/resource_calendar_attendance.py#L61)) | Cosmetic hours, real durations |
| `tz` | Required on the calendar, defaults from user | All interval math is tz-localized |
| `work_time_rate` / `is_fulltime` | `hours_per_week / full_time_required_hours × 100`; fulltime = equality at 3 digits ([resource_calendar.py:250-258](../addons/resource/models/resource_calendar.py#L250)) | Part-time detection |

For **flexible** calendars, `hours_per_day`/`hours_per_week` are *not computed* — they're manually entered values that act as caps.

**Company change rewrites the calendar:** changing `company_id` on an existing calendar re-copies `attendance_ids`, `tz`, `two_weeks_calendar` **and calendar-specific `global_leave_ids`** from the new company's default calendar ([resource_calendar.py:172-181](../addons/resource/models/resource_calendar.py#L172), [202-208](../addons/resource/models/resource_calendar.py#L202)). `default_get` seeds attendance/full-time fields, while the stored `_compute_global_leave_ids` performs the leave copy on create/company change. All-Schedules (`calendar_id=False`) rows are not copied because they already apply dynamically.

## The Three Flavors of Time

Note the asymmetry that confuses everyone: the calendar's `schedule_type` selection has only **two** values (`fully_fixed` / `flexible`). "Fully flexible" is **not a calendar type** — it is the *absence* of a calendar (the employee's Working Hours field left empty; help text on `resource.resource.calendar_id` defines it, [resource_resource.py:47-51](../addons/resource/models/resource_resource.py#L47); tests: `_is_fully_flexible` = no calendar, `_is_flexible` = that or `flexible_hours` [resource_resource.py:218-231](../addons/resource/models/resource_resource.py#L218)).

| | Fixed | Flexible (`flexible_hours`) | Fully flexible (no calendar at all) |
|---|---|---|---|
| Schedule | Real weekday slots | No slots; `hours_per_day` cap + `full_time_required_hours`/week cap | None |
| Attendance intervals | The slots | Synthetic: rolling 7-day windows from the query start, `min(hours_per_day, remaining weekly cap)` per day, centered at 12:00 ([resource_calendar.py:414-478](../addons/resource/models/resource_calendar.py#L414)) | One interval spanning the whole query range, dummy attendance with `duration_days = hours/24` ([resource_calendar.py:405-413](../addons/resource/models/resource_calendar.py#L405)) |
| `_get_work_days_data_batch` | Real hours/days | Days = hours ÷ hours_per_day | **`{'days': 0, 'hours': 0}`** ([resource_mixin.py:111-113](../addons/resource/models/resource_mixin.py#L111)) |
| Leave duration | Leave ∩ schedule | Expanded/capped | The **whole period** counts as leave — `_get_leave_days_data_batch` returns calendar days × 24h ([resource_mixin.py:152-158](../addons/resource/models/resource_mixin.py#L152)) |
| Payroll consequence | Normal | Day counts approximate | Work entries get duration 0; OUT lines zero; day math collapses — the wage-types daily-rate hazard |

**Inconsistency worth knowing:** the interval engine's flexible fill uses rolling 7-day windows from the query start, while planning's flexible helpers (`_get_flexible_resource_work_hours`) cap by **locale calendar weeks** — two different week conventions for the same employee ([resource_resource.py:287-397](../addons/resource/models/resource_resource.py#L287)).

---

## Attendance Lines (`resource.calendar.attendance`)

One record per slot ("Monday Morning 8-12"). The decision-point fields:

- `day_period` — `morning` / `lunch` / `afternoon` / `full_day`. **Lunch rows exist only to model the midday gap**: `duration_hours = 0` for them ([resource_calendar_attendance.py:77-80](../addons/resource/models/resource_calendar_attendance.py#L77)), they're excluded from every hours computation and from attendance intervals unless explicitly requested with `lunch=True`.
- `duration_days` — the day weight used by all day counting: lunch = 0, full_day = 1, otherwise **0.5 if the slot's hours ≤ 75% of the calendar's `hours_per_day`, else 1** ([resource_calendar_attendance.py:98-106](../addons/resource/models/resource_calendar_attendance.py#L98)). Stored, `readonly=False` — manually overridable per slot.
- `week_type` — `'0'`(first)/`'1'`(second) for two-week calendars; parity via `get_week_type` (absolute weeks since year 1 — never resets at year end, never matches ISO numbers).
- `display_type = 'line_section'` — the "First week"/"Second week" section headers in two-week mode. Deleting them is blocked ([resource_calendar.py:183-200](../addons/resource/models/resource_calendar.py#L183)); a line's `week_type` is assigned by which section it sits under.
- Overlap constraint: slots on the same weekday (per week-type) may touch but not overlap — contiguous intervals are allowed via a 0.000001h fudge ([resource_calendar.py:605-615](../addons/resource/models/resource_calendar.py#L605)).

**Extension point:** `hr_work_entry` adds `work_entry_type_id` to each attendance line (default: Attendance) — this is how a schedule can emit custom work entry types automatically ([resource_calendar_attendance.py:9-22](../addons/hr_work_entry/models/resource_calendar_attendance.py#L9)); lines whose type `is_leave` are excluded from `hours_per_week` and `_get_global_attendances` ([resource_calendar.py:9-15](../addons/hr_work_entry/models/resource_calendar.py#L9)). Full story in [`work_entries.md`](work_entries.md).

## Calendar Exceptions (`resource.calendar.leaves`)

One record = one absence interval. Two axes decide its meaning:

| Axis | Values | Effect |
|---|---|---|
| `resource_id` | empty = **global** (public holiday) / set = one resource's absence | Global leaves hit everyone on the calendar (same company); resource leaves hit only that resource |
| `time_type` | `leave` / `other` | `_leave_intervals_batch`'s default domain only picks `leave`; `other` (e.g. training) still blocks the schedule for work-entry purposes but is bucketed as worked time ([hr_version.py:223-226](../addons/hr_work_entry/models/hr_version.py#L223)) |

`calendar_id` is computed from `resource_id.calendar_id` ([resource_calendar_leaves.py:53-56](../addons/resource/models/resource_calendar_leaves.py#L53)); a leave with **no calendar** applies to every calendar (the search domain is `calendar_id in [False] + self.ids`, [resource_calendar.py:511](../addons/resource/models/resource_calendar.py#L511)). `hr` overrides the compute to be contract-aware: the leave is stamped with the calendar of the employee's **version active at `date_from`** ([resource_calendar_leaves.py:12-33](../addons/hr/models/resource_calendar_leaves.py#L12)). `date_to` auto-fills to 23:59:59 of the start day ([resource_calendar_leaves.py:63-73](../addons/resource/models/resource_calendar_leaves.py#L63)).

### Where they come from

1. **Time-off validation:** `hr.leave._validate_leave_request` → `_create_resource_leave` creates one per leave, carrying `holiday_id`, the leave type's `time_type` and `work_entry_type_id` ([hr_leave.py:996-1013](../addons/hr_holidays/models/hr_leave.py#L996), vals at [hr_leave.py:985-994](../addons/hr_holidays/models/hr_leave.py#L985)); refusal/cancel unlinks them ([hr_leave.py:1003-1007](../addons/hr_holidays/models/hr_leave.py#L1003)).
2. **Public holidays:** created manually (Time Off ▸ Configuration) as global records; `hr_holidays` blocks overlapping same-scope holidays ([resource.py:19-37](../addons/hr_holidays/models/resource.py#L19)). Only calendar-specific **create** explicitly reinterprets user-entered wall time in the calendar timezone; All Schedules and write skip that conversion ([resource.py:124-156](../addons/hr_holidays/models/resource.py#L124)). See the timezone policy in [`public_holidays_flow.md`](public_holidays_flow.md).

### Global leave propagation

Creating, writing, or unlinking a **global** leave triggers `_reevaluate_leaves`: every non-refused `hr.leave` overlapping the company/time window gets its duration recomputed, its state bounced through `confirm` and back, employees get chat notifications, and leaves that no longer fit their allocation are **auto-refused** ([resource.py:56-93, 142-163](../addons/hr_holidays/models/resource.py#L56)). The search is broader than calendar applicability. Auto-refusal can enter the work-entry bridge and deactivate linked validated entries, while the public-holiday work entries themselves are not regenerated. Retroactive changes therefore require a payroll impact guard.

`transfer_leaves_to(other_calendar, resources, from_date)` (added by `hr`) rewrites `calendar_id` on this calendar's leaves starting after `from_date` (default today) — all of them, or only the given resources' ([resource_calendar.py:9-24](../addons/hr/models/resource_calendar.py#L9)). **Nothing in v19 production code calls it** (only tests) — switching an employee's calendar does *not* migrate their leave records automatically.

### Security

Base `resource` rules restrict ordinary users to reading global/own rows and modifying their own resource rows. After `hr_holidays` loads, it adds unrestricted read for internal users and unrestricted CRUD for Time Off Officers ([hr_holidays_security.xml:238-254](../addons/hr_holidays/security/hr_holidays_security.xml#L238)). The central menu is Administrator-only, but menu visibility is not a security boundary. Calendars and attendances remain read-only for ordinary users.

---

## Resource ↔ Employee Wiring

`resource.resource` carries the materialized current `calendar_id` (default: company calendar; **empty = fully flexible** by definition) and the required `tz` (defaulted from user, then calendar, at create — [resource_resource.py:66-77](../addons/resource/models/resource_resource.py#L66)). `resource_type` is `user`/`material`; `time_efficiency` only matters to MRP work centers.

`hr.employee` inherits `resource.mixin` ([resource_mixin.py:29-48](../addons/resource/models/resource_mixin.py#L29)): creating an employee auto-creates its resource; `company_id`, `resource_calendar_id`, `tz` on the employee are all *related* fields into the resource, and `employee.active` is stored-related to `resource.active` ([hr_employee.py:115](../addons/hr/models/hr_employee.py#L115)) — archiving one archives the other. `hr` closes the loop the other way: writing `resource.calendar_id` pushes into `employee.resource_calendar_id` ([resource.py:56-59](../addons/hr/models/resource.py#L56)).

Date-aware calendar resolution is delegated back to hr's version engine: base `_get_calendar_at` just returns `calendar_id` ([resource_resource.py:223-224](../addons/resource/models/resource_resource.py#L223)); the hr override routes through `employee._get_calendars(date)` ([resource.py:131-137](../addons/hr/models/resource.py#L131)), which picks the version in contract at that date ([hr_employee.py:1553-1563](../addons/hr/models/hr_employee.py#L1553)) — see [`hr_employee_versions.md`](hr_employee_versions.md) for the contract-gated fallback trap. Similarly, `_get_calendars_validity_within_period` (used by planning) is overridden in hr to slice the period by contract validity, with contract-less employees falling back to the plain calendar ([resource.py:92-108](../addons/hr/models/resource.py#L92)).

### The mixin's day-math API (what HR code actually calls)

| Method | Returns | Fully-flexible behavior |
|---|---|---|
| `_get_work_days_data_batch(from, to)` | `{employee_id: {'days', 'hours'}}` of work time | `{'days': 0, 'hours': 0}` ([resource_mixin.py:110-114](../addons/resource/models/resource_mixin.py#L110)) |
| `_get_leave_days_data_batch(from, to)` | Same shape, attendance ∩ leave | Whole period: `days = (to-from).days` ([resource_mixin.py:152-158](../addons/resource/models/resource_mixin.py#L152)) |
| `_list_work_time_per_day(from, to)` | `[(day, hours)]` per record; honors `compute_leaves` context ([resource_mixin.py:181-213](../addons/resource/models/resource_mixin.py#L181)) | n/a (falls back to company calendar) |
| `list_leaves(from, to)` | `[(day, hours, leave)]` from leaves ∩ attendances ([resource_mixin.py:215-241](../addons/resource/models/resource_mixin.py#L215)) | n/a |
| `_adjust_to_calendar(start, end)` | Snaps datetimes to nearest schedule boundary via `_get_closest_work_time` ([resource_resource.py:108-143](../addons/resource/models/resource_resource.py#L108)) | n/a |

All of these accept an optional `calendar` argument that bypasses the per-record calendar — `hr.leave` uses it to compute durations against a forced calendar.

---

## The Interval Engine

Three batch methods on the calendar, all returning `{resource_id: Intervals}` where each interval is `(start, stop, recordset)`. **Every call also computes a calendar-generic result under key `False`** (empty-resource entry appended to the list, [resource_calendar.py:326-329](../addons/resource/models/resource_calendar.py#L326)) — callers that pass no resources read `[False]`.

### `_attendance_intervals_batch(start_dt, end_dt, resources, domain, tz, lunch)` ([resource_calendar.py:322-481](../addons/resource/models/resource_calendar.py#L322))

Theoretical schedule. Flow: group resources by tz → search this calendar's attendance rows (`display_type = False`, lunch excluded unless `lunch=True`) → bucket them into 14 weekday slots (7 × two week types; one-week calendars fill both) → `rrule(DAILY)` over the range → per day, pick the bucket by `weekday + 7 × get_week_type(day)` and emit `(day+hour_from, day+hour_to, attendance)` → localize and clamp to the query bounds. The third tuple element is the source `resource.calendar.attendance` recordset — its `duration_days`/`duration_hours` make day-counting possible. Then per resource, `_get_calendar_at(start_dt)` decides the branch:

- **no calendar at that date** → one interval covering the whole query, dummy attendance `duration_days = hours/24` ([resource_calendar.py:405-413](../addons/resource/models/resource_calendar.py#L405));
- **flexible calendar** → synthetic fill: walk 7-day windows from the query start date, allocate `min(hours_per_day, remaining weekly quota)` per day centered at 12:00, each day's dummy attendance carrying `duration_days = 1` ([resource_calendar.py:414-478](../addons/resource/models/resource_calendar.py#L414)). A query starting mid-week assumes the *prior* days of that rolling window were fully worked ([resource_calendar.py:436-442](../addons/resource/models/resource_calendar.py#L436));
- **fixed** → the shared per-tz result.

`lunch=True` on a flexible calendar returns empty ([resource_calendar.py:331-332](../addons/resource/models/resource_calendar.py#L331)).

### `_leave_intervals_batch(start_dt, end_dt, resources, domain, tz)` ([resource_calendar.py:497-551](../addons/resource/models/resource_calendar.py#L497))

Searches `resource.calendar.leaves` with: default `time_type = 'leave'`, `calendar_id in [False] + self.ids`, `resource_id in [False] + resources`, date overlap, `company_id in [False] + resource companies`. Pairing rule per (leave, resource): a resource-specific leave applies only to its resource; a global leave applies only when `resource.company_id == leave.company_id` ([resource_calendar.py:531-532](../addons/resource/models/resource_calendar.py#L531)). This strict equality is safe **for this interval helper**. Work-entry generation uses a separate search/pairing implementation and can cross enabled companies; see below. For fully-flexible resources, each leave expands to full local days.

### `_work_intervals_batch` = attendance − leave ([resource_calendar.py:553-569](../addons/resource/models/resource_calendar.py#L553))

Note the asymmetry: the `employee_timezone` context key is forwarded only into the attendance half ([resource_calendar.py:561](../addons/resource/models/resource_calendar.py#L561)). `_unavailable_intervals_batch` is its complement (gaps between work intervals) and **silently skips fully-flexible resources** — they're absent from the result dict ([resource_calendar.py:578-599](../addons/resource/models/resource_calendar.py#L578)).

### Day counting — `_get_attendance_intervals_days_data` ([resource_calendar.py:617-643](../addons/resource/models/resource_calendar.py#L617))

`days += duration_days × interval_hours / duration_hours` — a clipped attendance yields a proportional fraction of its configured day weight (half-day rows carry `duration_days = 0.5`). For a single flexible calendar it divides hours by `hours_per_day` instead. This is the math behind payroll's OUT-of-contract lines and leave durations (`get_work_duration_data`, `_get_work_days_data_batch`, `_get_leave_days_data_batch`).

### External API built on the engine

- `get_work_hours_count(start, end)` — plain hour sum of work intervals ([resource_calendar.py:794-819](../addons/resource/models/resource_calendar.py#L794)). `hr.leave` uses it for durations without an employee ([hr_leave.py:621-626](../addons/hr_holidays/models/hr_leave.py#L621)).
- `get_work_duration_data(from, to)` — `{'days', 'hours'}` via the day-counting helper, calendar-only (no resource) ([resource_calendar.py:821-843](../addons/resource/models/resource_calendar.py#L821)).
- `plan_hours(hours, day_dt)` / `plan_days(days, day_dt)` — walk forward/backward through intervals in 14-day chunks (max 100 iterations ≈ 3.8 years) to find the datetime after scheduling that much work ([resource_calendar.py:845-932](../addons/resource/models/resource_calendar.py#L845)). Scheduling-side API (no payroll consumers).
- `_get_unusual_days(start, end)` — `{date: bool}` map of non-working days for calendar views; for flexible calendars only leave days are "unusual" ([resource_calendar.py:710-729](../addons/resource/models/resource_calendar.py#L710)).
- `_works_on_date(date)` — weekday-map lookup backed by `_get_working_hours`, which is `@ormcache('self.id')` ([resource_calendar.py:934-942, 1000-1007](../addons/resource/models/resource_calendar.py#L934)).
- `_get_hours_for_date(date, day_period)` — `(hour_from, hour_to)` bounds for a date; flexible calendars synthesize `12 ± hours_per_day/2` ([resource_calendar.py:944-998](../addons/resource/models/resource_calendar.py#L944)). Feeds `hr.leave` half-day time bounds ([hr_leave.py:1579-1580](../addons/hr_holidays/models/hr_leave.py#L1579)).

### Planning-side machinery (multi-calendar aware)

`resource.resource._get_valid_work_intervals` intersects work intervals with per-resource calendar *validity* periods ([resource_resource.py:182-216](../addons/resource/models/resource_resource.py#L182)); validity comes from `_get_calendars_validity_within_period`, which hr overrides to contract periods ([resource.py:92-108](../addons/hr/models/resource.py#L92)). The flexible twins `_get_flexible_resource_valid_work_intervals` / `_get_flexible_resource_work_hours` build full-day intervals, subtract leaves via `_format_leave` (overridden by hr_holidays for half-day and custom-hour leaves, [resource.py:193-226](../addons/hr_holidays/models/resource.py#L193)), and cap per-day/per-locale-week ([resource_resource.py:287-397](../addons/resource/models/resource_resource.py#L287)). Consumers: enterprise `planning` only.

`utils.py` holds the fallback constant `HOURS_PER_DAY = 8` and the `filter_domain_leaf` domain-rewriting helper ([utils.py:6-9](../addons/resource/models/utils.py#L6)) — no business flow of its own.

---

## Multi-Company Notes

- `resource.calendar` has **no multi-company record rule anywhere** — any user reads all companies' calendars; the `company_id` field only filters defaults and leave domains. `resource.resource` and `resource.calendar.leaves` do have company rules ([resource_security.xml:30-40](../addons/resource/security/resource_security.xml#L30)).
- A calendar's `company_id` is optional. Company-less calendars: exempt from the `full_time_required_hours` reset, usable across companies, and their global leaves get `company_id = env.company` at save ([resource_calendar_leaves.py:58-61](../addons/resource/models/resource_calendar_leaves.py#L58)) — which then only matches resources of that company in the interval engine.
- Resource-calendar interval matching is strict equality, but work-entry generation uses all enabled companies and lacks the same exact pairing check. Multi-company holidays need one row per company plus a work-entry override/regression test.

---

## Gotchas & Non-Obvious Behavior

- **`full_time_required_hours` self-resets** to the company calendar's weekly hours on recompute — a customized value doesn't survive; only company-less calendars keep it.
- **Half-day weekdays inflate nothing**: a weekday with one 4h slot still counts as a full weekday in the `hours_per_day` divisor, deflating hours_per_day for everyone on that calendar — which changes payslip day counts.
- **Changing a calendar's company silently rebuilds it** — attendance rows, tz, and global leaves are re-copied from the new company's default calendar (stored computes with `readonly=False`).
- **The 75% half-day threshold**: an attendance slot is weighted 0.5 days when its span ≤ `hours_per_day × 0.75`, else 1 ([resource_calendar_attendance.py:98-106](../addons/resource/models/resource_calendar_attendance.py#L98)). Two 4h slots on one day = 2 × 0.5 = 1 day, but one 6.5h slot on an 8h calendar = 1 full day.
- Comment/code mismatch: day rounding claims "closest 16th of a day" but rounds to 0.001 ([resource_calendar.py:640](../addons/resource/models/resource_calendar.py#L640)).
- **`transfer_leaves_to` is dead code in v19** — defined in hr, called only by tests. This matters to employee-owned resource leaves. Public holidays are not employee-owned: calendar-specific applicability changes dynamically with the employee's date-effective schedule; All Schedules continues to apply.
- Two-week calendars: week parity is absolute (weeks since year 1), so it never resets at year boundaries — but also never aligns with ISO week numbers.
- **`_get_working_hours` is `@ormcache`'d and the resource module never invalidates it** ([resource_calendar.py:1000](../addons/resource/models/resource_calendar.py#L1000)) — after editing attendance rows, `_works_on_date` (used by l10n_fr holiday extension, renting) can serve the stale weekday map until a registry cache clear.
- **Global leave edits are payroll-sensitive**: they re-open/recompute leave, notify employees, may auto-refuse it and indirectly deactivate validated leave work entries, but do not rebuild existing public-holiday entries.
- **Flexible rolling-window assumption**: querying attendance intervals for a flexible employee starting mid-week assumes all prior days of that 7-day window were worked at `hours_per_day` — short queries near week starts under-allocate.
- `_unavailable_intervals_batch` omits fully-flexible resources from its result dict entirely — callers indexing by resource id get `KeyError`, not "always available".
- Work-entry generation does **not** use `_leave_intervals_batch` — it re-implements leave pairing from a direct `resource.calendar.leaves` search with its own calendar-matching rules ([hr_version.py:178-233](../addons/hr_work_entry/models/hr_version.py#L178)); behavior differences between time-off math and work-entry math often trace to this fork.
- The `employee_timezone` context affects attendance intervals but not leave intervals inside the same `_work_intervals_batch` call ([resource_calendar.py:561](../addons/resource/models/resource_calendar.py#L561)).

---

## Consumer Map — Who Calls the Engine

| Consumer (business feature) | Calls | Where |
|---|---|---|
| Work entry generation from calendar | `_attendance_intervals_batch` (attendances, lunch, static-attendance fallbacks); fully-flexible → synthetic whole-range interval | [hr_version.py:113, 130, 246, 257](../addons/hr_work_entry/models/hr_version.py#L113); leaves via direct search [hr_version.py:96-97, 180](../addons/hr_work_entry/models/hr_version.py#L96) |
| Payslip worked-days → days conversion | `calendar.hours_per_day` | [hr_payslip.py:831-855](../enterprise/hr_payroll/models/hr_payslip.py#L831) |
| Payslip OUT-of-contract lines | `get_work_duration_data` on the reference calendar | [hr_payslip.py:886-898](../enterprise/hr_payroll/models/hr_payslip.py#L886) |
| Payroll work-entry validation (out-of-schedule check) | `_attendance_intervals_batch` | [hr_work_entry.py:44](../enterprise/hr_payroll/models/hr_work_entry.py#L44) |
| Payslip batch calendar (unusual days) | `_get_unusual_days` | [hr_payslip_run.py:424](../enterprise/hr_payroll/models/hr_payslip_run.py#L424) |
| Payroll version day/hour aggregation | `employees._get_work_days_data_batch` | [hr_version.py:587](../addons/hr_work_entry/models/hr_version.py#L587) |
| Time-off duration (`number_of_days`/`hours`) | `_list_work_time_per_day`, `_get_work_days_data_batch`, `get_work_hours_count` | [hr_leave.py:575, 579, 621-626](../addons/hr_holidays/models/hr_leave.py#L575) |
| Time-off validation → calendar exception | creates/unlinks `resource.calendar.leaves` | [hr_leave.py:996-1013](../addons/hr_holidays/models/hr_leave.py#L996) |
| Accrual/allocation math | `_get_leave_days_data_batch`, `_get_work_days_data_batch` | [hr_leave_allocation.py:385-402](../addons/hr_holidays/models/hr_leave_allocation.py#L385) |
| Leave-type "closest allocation" duration | `_work_intervals_batch` + `_get_attendance_intervals_days_data` | [hr_leave_type.py:596-597](../addons/hr_holidays/models/hr_leave_type.py#L596) |
| Employee calendar-view grey days | `employee._get_unusual_days` → per-version `calendar._get_unusual_days` | [hr_employee.py:1613-1635](../addons/hr/models/hr_employee.py#L1613) |
| Expected attendance / lunch (attendance & overtime base) | `_work_intervals_batch`, `_attendance_intervals_batch(lunch=True)`, `get_work_duration_data` | [hr_employee.py:1637-1715](../addons/hr/models/hr_employee.py#L1637) |
| Attendance overtime rules | `_leave_intervals_batch`, `_attendance_intervals_batch` (incl. lunch), `_get_unusual_days` | [hr_employee.py:279-306](../addons/hr_attendance/models/hr_employee.py#L279), [hr_attendance_overtime_rule.py:192, 227, 238, 491-492](../addons/hr_attendance/models/hr_attendance_overtime_rule.py#L192) |
| "Working now" presence check | `_work_intervals_batch` (calendar-generic key) | [hr_employee.py:844](../addons/hr/models/hr_employee.py#L844) |
| Planning slot allocation | `_get_valid_work_intervals`, `_get_flexible_resource_valid_work_intervals`, `_get_flexible_resource_work_hours`, `_adjust_to_calendar` | [planning_slot.py:254-255, 410-413, 634-672, 1239-1337](../enterprise/planning/models/planning_slot.py#L254) |
| FR/IN holiday localizations | `_works_on_date` | [l10n_fr hr_leave.py:90-167](../addons/l10n_fr_hr_holidays/models/hr_leave.py#L90), [l10n_in hr_leave.py:82](../addons/l10n_in_hr_holidays/models/hr_leave.py#L82) |
| Half-day leave hour bounds | `_get_hours_for_date` | [hr_leave.py:1579-1580](../addons/hr_holidays/models/hr_leave.py#L1579) |
| Version-aware calendar resolution (everything above) | `resource._get_calendar_at` → `employee._get_calendars(date)` | [resource.py:131-137](../addons/hr/models/resource.py#L131), [hr_employee.py:1553-1563](../addons/hr/models/hr_employee.py#L1553) |

---

## Related Docs

- [`INDEX.md`](INDEX.md)
- [`hr_employee_versions.md`](hr_employee_versions.md) — who owns the calendar per date (version/contract engine)
- [`work_entries.md`](work_entries.md) — the main consumer of attendance intervals; `work_entry_type_id` extension point
- [`payroll_wage_types.md`](payroll_wage_types.md) — hours_per_day in payslip day math (§8.2 #1)
- [`hr_payroll.md`](hr_payroll.md) — payslip flow that consumes the day counts
- [`attendance_work_entry.md`](attendance_work_entry.md) — attendance-sourced work entries vs calendar-sourced
- [`hr_holidays_time_off_units.md`](hr_holidays_time_off_units.md) — how leave days/hours units build on these durations
- [`hr_holidays_accrual_plans.md`](hr_holidays_accrual_plans.md) — accrual math over `_get_work_days_data_batch`

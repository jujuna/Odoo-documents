# Work Entries — The Core Engine

> **Module:** `hr_work_entry` (community) + payroll extensions in `hr_payroll` (enterprise) + bridges `hr_work_entry_holidays`, `hr_work_entry_attendance`, `hr_work_entry_planning`, `hr_payroll_planning`, `hr_work_entry_planning_attendance`, `hr_work_entry_enterprise`, `hr_work_entry_holidays_enterprise` | **Path:** [`addons/hr_work_entry/`](../addons/hr_work_entry/)
> **Updated by Codex and verified from source 2026-07-12.** Related docs: [`public_holidays_flow.md`](public_holidays_flow.md), [`payroll_wage_types.md`](payroll_wage_types.md), [`attendance_work_entry.md`](attendance_work_entry.md), [`hr_payroll.md`](hr_payroll.md).

## What It Does & Why It Exists

Work entries are the middle layer between "time" (schedules, attendances, planning shifts, leaves) and "money" (payslips). The payslip never reads a schedule, an attendance, or a leave directly — it only reads `hr.work.entry` records. Every time source is normalized into this one model, so payroll has a single, conflict-checked, validated representation of what an employee did in a period. HR officers see work entries in a calendar view (Payroll → Work Entries), fix conflicts there, and payslips consume them.

**Key v19 fact: work entries are day-based.** The model stores `date` (a Date) + `duration` (hours, 0 < d ≤ 24) — there are **no** `date_start`/`date_stop` datetime fields on the record anymore ([hr_work_entry.py:28-29](../addons/hr_work_entry/models/hr_work_entry.py#L28)). Generation internally computes datetime intervals but flattens them to (date, duration) before creating records. Multiple entries per employee per day are legal as long as the day's total stays within 24h.

---

## The Big Picture — How It Works

```
time source (calendar | attendance | planning | validated leaves | manual)
   → hr.work.entry records (one per employee / day / type; date + duration)
      → conflict engine (4 checks; batch payroll blocks, individual flow can silently exclude/ignore)
         → payslip pulls entries (state draft|validated) and groups per type
            → worked-days lines → amounts → BASIC
```

The employee's `work_entry_source` on `hr.version` picks the automatic source (`calendar` default; `attendance`/`planning` added by their bridge modules). Leaves overlay any source. Manual entries can always be added on top.

### Key Decision Points
- **`work_entry_source` (per employee version):** what fills the layer automatically. Changing it (or the calendar) force-regenerates the already-generated period ([hr_version.py:689-691](../addons/hr_work_entry/models/hr_version.py#L689)).
- **Work entry type per entry:** decides the payslip line the hours land on, the pay rate multiplier, and whether the hours dilute a fixed wage (see Type Anatomy).

---

## All the Ways Work Entries Get Created

| # | Trigger | Mechanism |
|---|---|---|
| 1 | **Daily cron** "Generate Missing Work Entries" | Covers 1st of current month → last day of next month, 100 versions per run, re-triggers itself until done; one company per run, calendar-source versions batch first, versions already generated today are skipped ([hr_version.py:693-724](../addons/hr_work_entry/models/hr_version.py#L693)) |
| 2 | **Creating a payslip** | `_compute_worked_days_line_ids` first calls `generate_work_entries(date_from-1, date_to+1)` — a payslip auto-fills its own period ([hr_payslip.py:1439-1441](../enterprise/hr_payroll/models/hr_payslip.py#L1439)) |
| 3 | **Version edits** | Calendar or source change → force regeneration via the wizard; contract date change → entries outside the contract are hard-deleted, **raising** if any of them is validated ([hr_version.py:660-673](../addons/hr_work_entry/models/hr_version.py#L660), [hr_version.py:621-639](../addons/hr_work_entry/models/hr_version.py#L621)); version deletion deletes its non-validated entries ([hr_version.py:641-658](../addons/hr_work_entry/models/hr_version.py#L641)) |
| 4 | **Leave validation** | `hr_work_entry_holidays` replaces the affected interval with the leave's work entry type |
| 5 | **Attendance / planning bridges** | Check-out → entries; overtime approval → OVERTIME entries; published slots → entries (see [`attendance_work_entry.md`](attendance_work_entry.md)) |
| 6 | **Manual** | Work Entries calendar → New: pick employee, date, duration, type. `create()` auto-resolves the version from the date, snapshots the type's rate, then runs the conflict check ([hr_work_entry.py:240-259](../addons/hr_work_entry/models/hr_work_entry.py#L240)) |

Custom code creating entries only needs `employee_id`, `date`, `duration`, `work_entry_type_id` — the version is resolved automatically. This makes custom bridges (e.g. timesheet → work entry) far simpler than the old datetime-interval model.

### The generation algorithm (calendar source)

Generation is **delta-based**, not idempotent-regenerate. Each version tracks `date_generated_from` / `date_generated_to`; `_generate_work_entries` only produces the missing head/tail intervals and widens the tracked window ([hr_version.py:466-478](../addons/hr_work_entry/models/hr_version.py#L466)). The middle is never re-examined — fixing the past is the regeneration wizard's job (`force=True` nullifies non-validated entries in range and rebuilds). New versions start with a **collapsed window** (both bounds = today midnight, [hr_employee.py:28-34](../addons/hr_work_entry/models/hr_employee.py#L28)); the first generation snaps a collapsed window to its requested start instead of backfilling years of history ([hr_version.py:429-435](../addons/hr_work_entry/models/hr_version.py#L429)).

For the interval, it builds theoretical attendance intervals from the calendar, subtracts `resource.calendar.leaves`, resolves each leave interval's work entry type via hooks (`_get_leave_work_entry_type`, overridden by the holidays bridge for public-holiday priority), then postprocesses: split at local midnights, convert to (date, duration), **merge everything sharing (date, type, employee, version, company) into one entry**, drop zero-duration ([hr_version.py:500-619](../addons/hr_work_entry/models/hr_version.py#L500)). Result: one entry per employee/day/type.

**Flexible-calendar trap:** an employee with no `resource_calendar_id` gets entries with `duration = 0.0` from calendar generation ([hr_version.py:576-578](../addons/hr_work_entry/models/hr_version.py#L576)) — consistent with the "flexible employees break hour math" gotcha in [`payroll_wage_types.md`](payroll_wage_types.md).

### The schedule itself chooses the type

Every working-schedule line (`resource.calendar.attendance` — "Monday morning", "Saturday shift"...) carries its own `work_entry_type_id`, defaulting to Attendance ([resource_calendar_attendance.py:9-15](../addons/hr_work_entry/models/resource_calendar_attendance.py#L9)). Generation reads the type from the interval's calendar lines ([_get_interval_work_entry_type](../addons/hr_work_entry/models/hr_version.py#L139)); fallback is the structure type's `default_work_entry_type_id`, then global Attendance ([hr_version.py:275](../enterprise/hr_payroll/models/hr_version.py#L275)). Consequence: a schedule can emit **custom types automatically** — e.g. Saturday slots configured with a "Site Day" type generate that type every week, no manual entry. Global time off records (`resource.calendar.leaves`) carry a type the same way ([resource_calendar_leaves.py:9-11](../addons/hr_work_entry/models/resource_calendar_leaves.py#L9)). Schedule lines whose type `is_leave` are excluded from `hours_per_week` and "work period" math ([resource_calendar.py:10-15](../addons/hr_work_entry/models/resource_calendar.py#L10)).

---

## The State Machine & Conflict Engine

States: `draft` → `validated` (via `action_validate`, only if error-free) | `conflict` | `cancelled` (= `active = False`, archived; excluded from pay).

Every create/write touching `date`, `duration`, `employee_id`, `work_entry_type_id`, or `active` re-runs the check over the affected date range: conflicts in range are reset to draft, then re-evaluated ([hr_work_entry.py:292-328](../addons/hr_work_entry/models/hr_work_entry.py#L292)).

The 4 checks ([_check_if_error](../addons/hr_work_entry/models/hr_work_entry.py#L138)):

| # | Check | Detail |
|---|---|---|
| 1 | Missing type | Entry without `work_entry_type_id` |
| 2 | Day overload | Per employee/day, SUM(duration) ≤ 0 or > 24h — **all** that day's entries flag. Overlap as such no longer exists; two entries same day are fine within 24h ([hr_work_entry.py:148-179](../addons/hr_work_entry/models/hr_work_entry.py#L148)) |
| 3 | Leave outside schedule | Leave-type entries entirely outside the calendar's theoretical schedule (skipped for flexible calendars) |
| 4 | Already-validated day | New entries on a day that already has validated entries |

Payroll adds a 5th, payslip-side check: for calendar-source employees, every scheduled slot must be covered by an entry, else a UserError blocks the payslip ("missing work entries", [hr_work_entry.py:30-51](../enterprise/hr_payroll/models/hr_work_entry.py#L30)).

Locks: validated entries can't be deleted ([hr_work_entry.py:279-282](../addons/hr_work_entry/models/hr_work_entry.py#L279)) and — with payroll installed — can't be modified except to conflict/archive them ([hr_work_entry.py:57-63](../enterprise/hr_payroll/models/hr_work_entry.py#L57)). Entries become validated when their payslip is validated.

---

## Work Entry Type Anatomy

`hr.work.entry.type` is small but every field is a pay-behavior switch:

| Field | What it controls |
|---|---|
| `code` | Payroll code — how salary rules reference the line (`worked_days.CODE`). Unique per country (NULL country included) ([hr_work_entry_type.py:46-59](../addons/hr_work_entry/models/hr_work_entry_type.py#L46)) |
| `display_code` | 3-char badge in calendar/payslip views. Cosmetic |
| `external_code` | Provider code consumed by the export-mixin l10n modules — irrelevant unless exporting ([hr_work_entry_type.py:14](../addons/hr_work_entry/models/hr_work_entry_type.py#L14)) |
| `is_leave` / `is_work` | Inverses of each other. `is_leave=True` makes the type linkable to time-off types and subject to conflict check #3 |
| `amount_rate` | Pay multiplier for the whole worked-days line (1.5 = 150%) — read from the **type** at pay time |
| `is_extra_hours` | Keeps the type's hours **out of the fixed-wage denominator** — the anti-dilution flag; mandatory on any paid extra type for monthly employees |
| `round_days` + `round_days_type` | Payroll ext.: how the line's day count displays/rounds (NO/HALF/FULL × closest/up/down) ([hr_work_entry_type.py:17-29](../enterprise/hr_payroll/models/hr_work_entry_type.py#L17)) |
| `unpaid_structure_ids` | Payroll ext.: structures in which this type pays 0 — same relation as `struct.unpaid_work_entry_type_ids`, seen from the type side |
| `is_unforeseen` | Payroll ext.: counts the type in the absenteeism report; SQL constraint forces it to be a leave type ([hr_work_entry_type.py:11-16](../enterprise/hr_payroll/models/hr_work_entry_type.py#L11)) |
| `country_id` | Scopes the type; can't change once entries exist. Leave empty for own types |

Types can never be deleted once payroll is installed — archive only ([hr_work_entry_type.py:39-43](../enterprise/hr_payroll/models/hr_work_entry_type.py#L39)).

**Dead field warning:** `hr.work.entry.amount_rate` (on the *entry*) is snapshotted from the type at creation ([hr_work_entry.py:246-250](../addons/hr_work_entry/models/hr_work_entry.py#L246)) but **never read by pay computation** — the worked-days line uses the type's current rate ([hr_payslip_worked_days.py:47](../enterprise/hr_payroll/models/hr_payslip_worked_days.py#L47)). Editing it on an entry changes nothing. Different rates therefore require different **types** — this is why overtime rulesets map rates to separate work entry types, and why per-type rate routing is the right extension seam.

Standard types shipped by `hr_work_entry` ([hr_work_entry_type_data.xml](../addons/hr_work_entry/data/hr_work_entry_type_data.xml)): Attendance `WORK100`, Overtime `OVERTIME` (rate 1.0, not extra — pays nothing extra by default), Out of Contract `OUT`, Generic Time Off `LEAVE100`, Unpaid `LEAVE90`, Sick `LEAVE110`, Home Working `WORK110`, and more leave variants.

---

## How the Payslip Consumes Entries

1. `_compute_worked_days_line_ids` generates missing entries, loads the period's entries per version, runs the coverage check ([hr_payslip.py:1429-1466](../enterprise/hr_payroll/models/hr_payslip.py#L1429)).
2. `get_work_hours` aggregates with one `_read_group`: entries with `state IN (draft, validated)` — conflicts and cancelled are invisible to pay — summed as `duration` per `work_entry_type_id` ([hr_version.py:216-273](../enterprise/hr_payroll/models/hr_version.py#L216)).
3. One worked-days line per type; `number_of_days = hours / calendar.hours_per_day`, per-type rounding, remainder dumped on the biggest line ([hr_payslip.py:845-870](../enterprise/hr_payroll/models/hr_payslip.py#L845)); an OUT line is appended for out-of-contract stretches.
4. `_compute_amount` prices each line (hourly vs monthly proration — full chain in [`payroll_wage_types.md`](payroll_wage_types.md) §2).

Drafts recompute from entries only when refreshed (`action_refresh_from_work_entries` / "Recompute Whole Sheet", [hr_payslip.py:804-814](../enterprise/hr_payroll/models/hr_payslip.py#L804)) — otherwise entry edits after compute leave the slip silently stale. There is **no** staleness detection for changed entries; the only "wrong data" banner tracks version (contract) changes ([hr_payslip.py:398-403](../enterprise/hr_payroll/models/hr_payslip.py#L398)).

---

## Payslip ↔ Entry State Choreography

There is **no relational link** between an entry and a payslip. The whole lifecycle is employee + date-window matching; the `validated` state's UI label "In Payslip" is wording, not a foreign key.

| Payslip event | Effect on entries |
|---|---|
| **Validate** (`action_payslip_done`) | Only for *regular* slips (`struct_id == structure type's default_struct_id`): searches all entries of the employee in the slip's date window — **no state/version filter, broader than what the slip counted** — and calls `action_validate()` ([hr_payslip.py:600-610](../enterprise/hr_payroll/models/hr_payslip.py#L600)). **The return value is ignored**: if a conflict check fails, entries stay draft/conflict while the payslip becomes validated anyway — silently |
| **Cancel / set-to-draft / unlink** | `action_draft_linked_entries`: resets validated entries in the window back to draft — but skips them entirely if a duplicate validated/paid slip exists, or if any other live (validated/paid, non-refunded) slip covers the entry's date (`has_payslip`, [hr_work_entry.py:12-28](../enterprise/hr_payroll/models/hr_work_entry.py#L12); reset logic [hr_payslip.py:492-514](../enterprise/hr_payroll/models/hr_payslip.py#L492)) |
| **Refund / credit note** | Entries untouched — they stay validated. Side effect: the origin slip's `is_refunded=True` removes it from `has_payslip`, so a later cancel elsewhere can release those entries ([hr_payslip.py:723-746](../enterprise/hr_payroll/models/hr_payslip.py#L723)) |
| **Batch reset-to-draft** (`hr.payslip.run.action_draft`) | Writes `state='draft'` on slips **directly**, never releasing entries ([hr_payslip_run.py:250-266](../enterprise/hr_payroll/models/hr_payslip_run.py#L250)) — validated locks leak, and new entries on those days auto-conflict via check #4 |
| **Batch generation** | The only path that hard-fails on conflicts: raises listing conflict intervals before creating slips ([hr_payslip_run.py:384-391](../enterprise/hr_payroll/models/hr_payslip_run.py#L384)) |

**When does a validated entry become editable again?** Three ways: the payslip releases it (above); someone writes `state='draft'` (the "Set to Draft" server action); or it's archived — `active=False` bypasses the guard and cancels the entry, even though *deleting* a validated entry is forbidden ([hr_work_entry.py:56-62](../enterprise/hr_payroll/models/hr_work_entry.py#L56)). Guard weakness: any truthy `state` key in a write smuggles other field changes past the validated lock. Note the "Set to Draft" server action ships in community views but its method exists only in enterprise `hr_payroll` — community-only installs would crash it.

---

## The Bridges in Depth

### Time off (`hr_work_entry_holidays`)

Leave type → `work_entry_type_id` on `hr.leave.type`; validation creates a `resource.calendar.leaves` carrying that type, then immediately materializes entries — but **only inside the version's already-generated window** ([hr_leave.py:45](../addons/hr_work_entry_holidays/models/hr_leave.py#L45)); outside it, nothing happens now and the entries appear later via normal generation. Existing entries fully covered by the leave are archived; partial overlaps just lose their `leave_id`. Validated entries are never touched at approve time — the new leave entries instead land in `conflict` via check #4.

| Leave event | Entries |
|---|---|
| Validate | Leave-type entries created (window-gated), covered entries archived |
| Refuse | **All** linked entries deactivated — *including validated (already-paid) ones* ([hr_leave.py:151-165](../addons/hr_work_entry_holidays/models/hr_leave.py#L151)); attendance entries re-created for those days |
| Cancel (by user) | Same regen — but blocked upfront if any validated entry links to the leave ([hr_leave.py:167-175](../addons/hr_work_entry_holidays/models/hr_leave.py#L167)). Refuse has **no such guard**: the asymmetry is the payroll-integrity hole |
| Reset to confirm | Same regen as refuse — archives all linked entries (validated included) and rebuilds attendance ([hr_leave.py:141-144](../addons/hr_work_entry_holidays/models/hr_leave.py#L141)) |
| Delete | Entries untouched, `leave_id` nulled — an admin deleting a validated leave leaves orphan leave-type entries |

The choreography also runs backwards: **cancelling a leave-linked work entry refuses the whole leave** — writing `state='cancelled'` on any entry with a `leave_id` calls `action_refuse()` on the leave ([hr_work_entry.py:15-18](../addons/hr_work_entry_holidays/models/hr_work_entry.py#L15)), which then archives *all* the leave's entries and rebuilds attendance. Conflict entries carrying a leave expose Approve/Refuse Time Off buttons directly on the work-entry form so the officer can resolve the leave from the calendar (buttons: `hr_work_entry_holidays_enterprise`, a views-only module, [hr_work_entry_views.xml:9-13](../enterprise/hr_work_entry_holidays_enterprise/views/hr_work_entry_views.xml#L9); methods live in community [hr_work_entry.py:25-34](../addons/hr_work_entry_holidays/models/hr_work_entry.py#L25)). Leave create/write themselves run inside the work-entry conflict engine over the leave span ±1 day ([hr_leave.py:89-121](../addons/hr_work_entry_holidays/models/hr_leave.py#L89)), and resetting an entry from conflict clears `leave_id` on attendance-type entries ([hr_work_entry.py:20-23](../addons/hr_work_entry_holidays/models/hr_work_entry.py#L20)).

Type resolution priority per interval ([hr_version.py:29-61](../addons/hr_work_entry_holidays/models/hr_version.py#L29)): bypass-coded leave > **global public holiday > employee leave** > generic fallback. "Bypass codes" come from `_get_bypassing_work_entry_type_codes` overrides — country lists of leave codes that beat public holidays (BE: long-term sick; base: empty).

Public-holiday balance treatment is separate: `include_public_holidays_in_duration=True` can make an employee leave consume the holiday even when work-entry priority still selects the public-holiday type. Public-holiday CRUD also reevaluates/auto-refuses employee leave without regenerating existing holiday entries; auto-refusal can deactivate validated leave entries. The complete source/company/timezone matrix is in [`public_holidays_flow.md`](public_holidays_flow.md). Work-entry generation has its own leave search using all enabled companies and lacks the resource interval engine's exact global-leave company pairing, so customization needs an exact-company filter.

Half-day/hour leaves work by interval intersection with the schedule; leave-linked entries get their duration from theoretical calendar hours, not raw clock difference. Verified test behavior: a 2h leave 10-12 → 6h attendance + 2h leave lines on the same day.

Enterprise `hr_payroll_holidays` adds the **defer flow**: a leave overlapping an already validated/paid slip gets `payslip_state='blocked'`, is excluded from work-entry generation entirely, and schedules an activity for the deferred-time-off manager; "Report to Next Month" converts next month's draft WORK100 entries into the leave's type (splitting entries for partial hours). Detail in [`hr_payroll.md`](hr_payroll.md) Time Off.

Likely bug (unverified upstream): with 2+ overlapping versions, approve-time generation produces vals per version × whole recordset, and same-day/type vals merge-sum — durations can double ([hr_leave.py:43-49](../addons/hr_work_entry_holidays/models/hr_leave.py#L43)).

### Attendance (`hr_work_entry_attendance`)

- **All presence lands on WORK100** — hardcoded `env.ref` on every `hr.attendance` interval ([hr_version.py:205](../enterprise/hr_work_entry_attendance/models/hr_version.py#L205)). No config hook exists for plain presence.
- **Open attendances (no check-out) are silently ignored** ([hr_version.py:127](../enterprise/hr_work_entry_attendance/models/hr_version.py#L127)).
- Overtime: only `approved` overtime lines whose rules are `paid` become entries; the type comes from the rule (max-rate type in `max` mode; **one full-duration entry per paid rule in `sum` mode** — duplicated hours by design). Refused/pending overtime time is **carved out of WORK100 presence and not replaced** — that time is simply unpaid ([hr_version.py:173-185](../enterprise/hr_work_entry_attendance/models/hr_version.py#L173)). Overtime lines with no paid rules skip silently.
- Calendar-source employees with a ruleset **also** get overtime entries ([hr_version.py:122](../enterprise/hr_work_entry_attendance/models/hr_version.py#L122)) — attendance source is not required for paid overtime.
- Regeneration triggers: attendance create/write/unlink regenerate affected days; overtime approve/refuse regenerates via the wizard, but direct `status` write bypasses it. The linked-entry guard does **not** protect creation of a new attendance: check-out inside an already-generated day can archive overlapping predecessors, including validated entries, because `active=False` is allowed. Add a validated/paid-window create/close guard.
- Direct entry creation from a check-out only happens inside the version's generated window ([hr_attendance.py:32](../enterprise/hr_work_entry_attendance/models/hr_attendance.py#L32)).

### Planning (`hr_work_entry_planning`)

- Only **published** slots generate entries; the slot's role is irrelevant — `planning.slot` has no `work_entry_type_id`, so **everything falls back to WORK100** ([hr_version.py:37-56](../enterprise/hr_work_entry_planning/models/hr_version.py#L37) + base fallback).
- Multi-day slots split into equal per-day durations `allocated_hours / days` — **including non-working days** ([hr_version.py:58-77](../enterprise/hr_work_entry_planning/models/hr_version.py#L58)).
- Public-holiday overlay uses the static calendar to price leave duration even though published shifts are the base source. A shift/calendar mismatch can remove a shift and produce fewer or zero holiday hours. `planning_holidays.write()` also watches `start_datetime/end_datetime` instead of the holiday's `date_from/date_to`, leaving shift allocated hours stale after a holiday move.
- Publishing creates entries only if the slot lies inside the generated window. New publication can archive all work entries touched by the slot, including validated rows. Editing a published slot's times/hours never regenerates entries—only state changes do ([planning_slot.py:97-101](../enterprise/hr_work_entry_planning/models/planning_slot.py#L97)); falsy changes (`allocated_hours=0`, clear resource) can bypass the validated guard. Regenerate old+new spans and reject every affected validated/paid window.

---

## Regeneration Wizard

The only tool that rebuilds already-generated dates (Work Entries calendar → Regenerate; also invoked internally by version edits, overtime approvals, attendance edits).

- Clamped to the union of the employees' `[date_generated_from, date_generated_to]` — you cannot regenerate outside what was ever generated ([wizard:70-85](../addons/hr_work_entry/wizard/hr_work_entry_regeneration_wizard.py#L70)).
- **An employee with any validated entry in the range is excluded entirely** — not just the validated days ([wizard:109](../addons/hr_work_entry/wizard/hr_work_entry_regeneration_wizard.py#L109)). This also applies to internally-triggered regenerations: a calendar change for a half-paid month silently regenerates nobody.
- Force regeneration **archives** old non-validated entries (`active=False` → cancelled) and nulls bridge links (`attendance_id`, `planning_slot_id`) — history stays queryable; nothing is deleted.
- A `slots` variant regenerates specific employee-days, grouped into contiguous ranges ([wizard:113-127](../addons/hr_work_entry/wizard/hr_work_entry_regeneration_wizard.py#L113)); it bypasses the normal wizard validation and calls force generation directly. Validated rows remain, replacements can become conflict. Its `record_ids` parameter is dead code.

---

## Security & UI

**ACLs:** HR Officer (`hr.group_hr_user`) can read/write/create entries but **not delete**; installing `hr_payroll` re-points the delete-capable ACL from system admins to `hr_payroll.group_hr_payroll_user` (an xmlid override, [hr_payroll ir.model.access.csv:27](../enterprise/hr_payroll/security/ir.model.access.csv)). Types: HR Officer read-only; HR/Payroll Manager full, but delete is blocked model-side (archive only). Record rules: **multi-company only — no own-employee restriction**; any HR officer sees all employees' entries in allowed companies. The type "multi-company" rule is actually country-based. `hr.user.work.entry.employee` (personal calendar filter) is vestigial in v19 — referenced nowhere outside its own definition.

**UI:** calendar view is month-scale only, quick-create disabled, with a multi-create popover, a split dialog (`action_split`: source ≥ 1h, split part strictly smaller), multi-select replace/reset/delete that filter out validated entries client-side, and the Regenerate button. List view has multi-edit. The form locks all fields when validated. Hazard: the form's clickable statusbar writes `state='validated'` **directly**, skipping `action_validate`'s conflict pass. Enterprise adds a Gantt view (`hr_work_entry_enterprise`).

**Export mixin** (`hr.work.entry.export.mixin`, [hr_work_entry_export_mixin.py](../enterprise/hr_payroll/models/hr_work_entry_export_mixin.py)): abstract base for exporting a month of entries to external payroll providers (used by the Belgian secretariat sociaux modules + Italian SD Worx). Blocks export while conflict entries exist. Relevant to us only as a pattern if rs.ge-style monthly exports of worked time are ever needed.

---

## Recipe: Custom Paid Work Entry Type (config only)

Goal: monthly employee gets extra pay for specially-marked hours (e.g. "Evening Hours" at 125%).

1. Payroll → Configuration → Work Entry Types → New: name "Evening Hours", code `EVENING`, `is_leave` off, **`is_extra_hours` on**, `amount_rate` 1.25, country empty.
2. Enter hours manually in Work Entries (or from a custom source): date, duration, type Evening Hours — coexists with the normal Attendance entry of the same day up to 24h total.
3. Payslip: the hours form their own line, paid `derived_rate × hours × 1.25` on top of the intact fixed wage — where `derived_rate = wage ÷ non-extra hours`.

Limits of config-only: the rate is always *derived from the employee's own wage* (or `hourly_wage` for hourly employees) — an independent "X GEL/hour regardless of wage" or a per-day rate needs the custom module or a salary rule ([`payroll_wage_types.md`](payroll_wage_types.md) §5-6, §8).

---

## Gotchas & Non-Obvious Behavior

- **Day-based, not interval-based (v19).** date + duration; the old overlapping-interval conflict model is gone. Consequence: a manual/custom entry does **not** collide with an attendance or calendar entry on the same day — for attendance-source employees nothing blocks double pay on a day with both a check-in and a manual paid entry. Guard by process or constraint, not by trusting a conflict.
- **Delta generation never revisits the middle.** Only the wizard (or `force=True`) rebuilds already-generated dates; version edits that matter trigger it, data fixes don't.
- **Per-entry `amount_rate` is inert.** See Type Anatomy.
- **Cron horizon** is current month + next month; payslips older than that generate on demand at payslip creation.
- **Default type fallback:** a version's default entry type is its structure type's `default_work_entry_type_id`, falling back to global Attendance ([hr_version.py:275](../enterprise/hr_payroll/models/hr_version.py#L275)).
- **Timesheet bridge is easier than previously documented.** Since a v19 work entry is (date, hours) — the same shape as a timesheet line — a timesheet→work-entry bridge no longer needs to invent clock times; it only needs type mapping, a validation gate, and dilution handling. This supersedes the "must invent datetimes" difficulty in [`payroll_wage_types.md`](payroll_wage_types.md) §7.7.
- **Payslip validation of entries can fail silently.** `action_payslip_done` ignores `action_validate()`'s failure — the slip ends validated while its entries sit in conflict. Only batch generation hard-fails on conflicts.
- **Leave refusal deactivates already-paid entries** while user-cancellation is guarded against exactly that. Refusing a leave inside a validated payslip period silently invalidates paid time.
- **Nothing splits attendance presence** — WORK100 for everything (attendance *and* planning sources). The only automatic multi-type sources are the working schedule's per-line types and overtime rulesets.
- **Normal regeneration excludes whole employees with validated entries in range** and is clamped to the generated window. Internal `slots=` regeneration bypasses that protection and can create replacements beside validated rows.
- **Statusbar direct-validation skips conflict checks** — a user clicking "In Payslip" on the form bypasses `action_validate`.
- **`hr_work_entry_no_check` context flag disables the whole conflict engine** ([hr_work_entry.py:305](../addons/hr_work_entry/models/hr_work_entry.py#L305)) — useful in migrations, dangerous anywhere else.
- **Fully flexible + calendar source = silently zero payslip.** No calendar → generation emits duration-0 vals which are dropped at merge → zero entries; the payslip additionally skips generation entirely for calendar-less versions (`filtered('resource_calendar_id')`, [hr_payslip.py:1441](../enterprise/hr_payroll/models/hr_payslip.py#L1441)); the coverage check never fires on an empty set → BASIC = 0 with no error. The only signal is the `work_entry_source_calendar_invalid` banner ([hr_version.py:34-42](../addons/hr_work_entry/models/hr_version.py#L34)) — advisory, blocks nothing. `hr.version.resource_calendar_id` has **no default**, so this state is one blank field away.
- **Custom-injected work entries are second-class citizens.** The generation engine's only sources are calendar/attendance/planning/leaves. Entries created by custom code (or manually) survive normal delta generation (the middle is never revisited) but are **archived and never recreated** by force regeneration, and leave approval archives any entry fully covered by the leave's day interval. Custom pay flows should pay via salary rules reading their own model, not by injecting entries — unless they also make themselves a real generation source.
- **The Worked Days tab is a pure projection**: `create="0" delete="0"`, all pricing columns readonly ([hr_payslip_views.xml:171-184](../enterprise/hr_payroll/views/hr_payslip_views.xml#L171)). Nothing enters it without a work entry type; manual corrections go through work entries or the `edited` flag, never the tab.

---

## Related Docs

- [`INDEX.md`](INDEX.md)
- [`payroll_wage_types.md`](payroll_wage_types.md) — how the aggregated lines become money; wage-type extension design
- [`attendance_work_entry.md`](attendance_work_entry.md) — the attendance/overtime source in depth
- [`hr_payroll.md`](hr_payroll.md) — payslip lifecycle, blockers, accounting

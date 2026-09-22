# Time Off — Core Module (hr_holidays)

> **Modules:** `hr_holidays` (community) | **Path:** [`addons/hr_holidays/`](../addons/hr_holidays/)
> Payroll deferral (`payslip_state`) now lives in `hr_payroll` (enterprise) | **Path:** [`enterprise/hr_payroll/models/hr_leave.py`](../enterprise/hr_payroll/models/hr_leave.py)
> **Verified against Odoo 20.0 source:** 2026-09-22 (previous pass: 19.0, 2026-07-12)
> Narrow sibling docs: complete public-holiday lifecycle → [`public_holidays_flow.md`](public_holidays_flow.md), accruals → [`hr_holidays_accrual_plans.md`](hr_holidays_accrual_plans.md), day/half-day/hour units → [`hr_holidays_time_off_units.md`](hr_holidays_time_off_units.md), work-entry materialization → [`work_entries.md`](work_entries.md).

## Three module merges that define 20.0

Read this first — most of the 19.0 mental model still holds, but the boundaries moved.

| 19.0 | 20.0 |
|---|---|
| `hr.leave.type` — its own model, owned by `hr_holidays` | **Gone.** Time off types are now `hr.work.entry.type` records; `hr_holidays` only *extends* that model with the time-off switches ([hr_work_entry_type.py](../addons/hr_holidays/models/hr_work_entry_type.py)). The field on `hr.leave` is `work_entry_type_id`, not `holiday_status_id` |
| `hr_work_entry_holidays` — community bridge turning validated leaves into work entries | **Gone as a module.** `hr_holidays` depends on `hr_work_entry` directly and does the work-entry mapping itself in [hr_version.py](../addons/hr_holidays/models/hr_version.py) |
| `hr_payroll_holidays` — enterprise defer module | **Merged into `hr_payroll`** (`[MOV] hr_payroll_holidays: Merge into hr_payroll`). `payslip_state` and the defer flow survive, in [enterprise/hr_payroll/models/hr_leave.py](../enterprise/hr_payroll/models/hr_leave.py) |

Two genuinely new mechanisms also arrive in 20.0: **bundled public-holiday data** (per-country CSVs + a loader wizard + a monthly cron) and **time rules** (`hr.time.rule`, from `hr_work_entry`), which can convert over/undertime into leaves and allocation credits.

## What It Does & Why It Exists

`hr_holidays` is the request/approval engine for absences. Employees file **time off requests** (`hr.leave`) against **time types** (`hr.work.entry.type` records flagged `time_off_selectable`); HR grants budgets through **allocations** (`hr.leave.allocation`); approvers move requests through a small state machine. A validated leave becomes a `resource.calendar.leaves` row — that is the single handoff point every other module (work entries, planning, timesheets, accruals) consumes. The module also owns **public holidays** (company-wide `resource.calendar.leaves`) and **mandatory days** (days on which employees may not request leave).

---

## The Big Picture — Request Lifecycle

```
            create()                    action_approve()                 action_approve()
 employee ───────────► confirm ──────────────────────► validate1 ────────────────────► validate
                          │        (only if type is 'both')   │                            │
                          │                                    │                            ├─► resource.calendar.leaves created
                          │      action_refuse()               │                            ├─► calendar.event meeting (optional)
                          ├───────────────────────► refuse ◄───┘                            ├─► work entries regenerated (in-module)
                          │                                                                 │
                          │                              action_cancel() wizard             │
                          └────── (delete allowed) ◄──── cancel ◄───────────────────────────┘
                                                                     action_back_to_approval() → confirm
```

States: `confirm` (To Approve) → `validate1` (Second Approval) → `validate` (Approved), plus `refuse` and `cancel` ([hr_leave.py:158](../addons/hr_holidays/models/hr_leave.py#L158)). There is still **no draft state** — a new request is born in `confirm` (a stale `'draft'` literal survives in one write-guard, [hr_leave.py:1604](../addons/hr_holidays/models/hr_leave.py#L1604)).

Step by step:

1. **Create** ([create:1529](../addons/hr_holidays/models/hr_leave.py#L1529)). `default_get` pre-picks the first *country-matching* time type (by `sequence`, `time_off_selectable=True`) that either needs no allocation or has a valid one ([hr_leave.py:95](../addons/hr_holidays/models/hr_leave.py#L95)). The user only enters `request_date_from/to` (+ half-day period or hour range); `date_from/date_to` and durations are computed from the employee's calendar ([_compute_date_from_to:712](../addons/hr_holidays/models/hr_leave.py#L712), [_get_durations:875](../addons/hr_holidays/models/hr_leave.py#L875)). `_check_validity` runs immediately: allocation coverage, negative-cap, and mandatory-day checks ([hr_leave.py:1415](../addons/hr_holidays/models/hr_leave.py#L1415)). **Changed in 20.0:** when `_check_validity` fails during a *multi*-employee generation the offending leaves are silently unlinked and the user gets a bus notification instead of an exception; single requests still raise.
2. **Auto-approval at create** ([_process_auto_approve_activities:1579](../addons/hr_holidays/models/hr_leave.py#L1579)). **Changed in 20.0:** this is no longer only about `no_validation` types — a leave is auto-approved in sudo if the type is `no_validation` **or the creating user is a Time Off Officer**. Either way an "The time off has been automatically approved" chatter note is posted. Otherwise `activity_update()` schedules an approval activity on the responsible ([hr_leave.py:2355](../addons/hr_holidays/models/hr_leave.py#L2355)).
3. **Approve** ([action_approve:1923](../addons/hr_holidays/models/hr_leave.py#L1923)). One button serves both steps: for a `both`-validation leave in `confirm` it writes `validate1` + `first_approver_id`; otherwise it calls `_action_validate`. The first-approval activity is marked done and a "Second approval request" activity is created for the HR responsible ([activity_update:2355](../addons/hr_holidays/models/hr_leave.py#L2355)).
4. **Validate** ([_action_validate:2059](../addons/hr_holidays/models/hr_leave.py#L2059)). Refuses to proceed if any leave falls entirely on non-working days/public holidays (`number_of_days == 0` → "not supposed to work during that period"). **Changed in 20.0:** the bypass list of sickness/incapacity codes that used to live in the work-entry bridge is now inline in `_get_leaves_on_public_holiday` ([hr_leave.py:1949](../addons/hr_holidays/models/hr_leave.py#L1949)) and matches by work-entry-type `code` (`013.00`, `128.00`, `123.00`, …), not by LEAVE1xx ids. Writes `validate`, stamps first/second approver, then `_validate_leave_request` ([:1822](../addons/hr_holidays/models/hr_leave.py#L1822)) creates the `resource.calendar.leaves` row ([_create_resource_leave:1789](../addons/hr_holidays/models/hr_leave.py#L1789)) and, if the type has `create_calendar_meeting`, a `calendar.event` in the employee's calendar. The employee gets a "has been accepted" message.
5. **After validation** the leave is effectively frozen: a constraint blocks date/employee edits in `validate1/validate` ([_check_date_state:1393](../addons/hr_holidays/models/hr_leave.py#L1393)), and any state write away from `validate` deletes the linked `resource.calendar.leaves` first ([write:1613](../addons/hr_holidays/models/hr_leave.py#L1613)). **New in 20.0:** dates *can* be amended on a validated leave without a state round-trip — the write override then re-dates the resource leave in place (`_amend_resource_leave_dates`), which is what the calendar-drag `reschedule_from_calendar` / `can_reschedule` path uses.

### Key Decision Points

- **Time type validation flow** (`leave_validation_type`): `no_validation` / `hr` / `manager` / `both` — decides who must click and how many times.
- **Requires allocation**: with it, the request is checked against granted days; without it (e.g. stock Sick Time Off), employees can request freely.
- **`count_as`** (`working_time` vs `absence`, inherited from `hr.work.entry.type`): replaces 19.0's `time_type`. It drives the overlap check bucket, the zero-duration rejection, the max-absence-per-day constraint and what lands on the resource leave.
- **What happens to a validated leave later** — refuse vs cancel vs delete — has three different guard sets (see the dedicated section below).

---

## Who Can Do What

### Groups ([hr_holidays_security.xml](../addons/hr_holidays/security/hr_holidays_security.xml))

| Group | xmlid | Gets |
|---|---|---|
| Employee | `group_hr_holidays_employee` | **New in 20.0.** The baseline group every internal user gets (implied by `base.default_user_group` and `hr.group_hr_user`). All the "own records" access lines are attached to it instead of `base.group_user` ([hr_holidays_security.xml:8](../addons/hr_holidays/security/hr_holidays_security.xml#L8)) |
| Time Off Responsible | `group_hr_holidays_responsible` | Team-approver role. Auto-granted/removed when a user is set/unset as someone's `leave_manager_id` ([hr_employee.py:311](../addons/hr_holidays/models/hr_employee.py#L311), [hr_employee.py:341](../addons/hr_holidays/models/hr_employee.py#L341), [res_users.py:14](../addons/hr_holidays/models/res_users.py#L14)) |
| Officer: Manage all requests | `group_hr_holidays_user` | See and manage everyone's requests; implies Responsible + HR Officer |
| Administrator | `group_hr_holidays_manager` | Everything, incl. configuration and deleting approved records |

Installing payroll still widens this: **payroll user and payroll manager both imply Time Off Officer** — the rule moved with the merge to [enterprise/hr_payroll/security/hr_payroll_security.xml:14](../enterprise/hr_payroll/security/hr_payroll_security.xml#L14).

### Access — what a plain employee actually sees

**Changed in 20.0:** `ir.model.access.csv` + `<record model="ir.rule">` are gone. Everything is now one unified [`security/ir.access.csv`](../addons/hr_holidays/security/ir.access.csv) with an `operation` column (`c`/`r`/`u`/`d`, `crud`) and an optional `domain`; `hr_holidays_security.xml` keeps only the group definitions.

The class docstring still claims a regular employee "can see all leaves" ([hr_leave.py:40](../addons/hr_holidays/models/hr_leave.py#L40)) — **that is stale**. The employee read line limits reads to *own* leaves (`hr_leave_rule_employee`); Responsible additionally reads their team's (`hr_leave_rule_responsible_read`); Officer reads all. Employees can create/write on own non-`validate/validate1` leaves, and their `leave_manager_id` can write when the type's validation is manager/both/no_validation (`hr_leave_rule_employee_update`).

**Changed in 20.0:** the officer line is a bare `crud` with **no domain** (`hr_leave_rule_user_read`). The 19.0 rule that stopped an officer writing their **own** `validate` leave is gone from the access layer — only `_get_next_states_by_state`/`_check_approval_update` still gate it, and officers get `cancel` on their own leave there.

The leave **description is private**: `name` is a compute over `private_name`; anyone who is not officer/owner/leave-manager sees `*****` ([_compute_description:556](../addons/hr_holidays/models/hr_leave.py#L556)), and the matching `_search_description` narrows non-officers to their own records.

### The approval matrix

Every button's availability comes from `can_approve/can_validate/can_refuse/can_cancel/can_back_to_approve` (+ the new `can_reschedule`) computes, all funneled through `_check_approval_update` → `_get_next_states_by_state` ([hr_leave.py:2255](../addons/hr_holidays/models/hr_leave.py#L2255), [:2209](../addons/hr_holidays/models/hr_leave.py#L2209)):

| Actor | Can do |
|---|---|
| Employee (own leave) | Cancel own `validate1/validate/refuse` leave — but only if it hasn't started yet (`is_in_past` blocks it; officers bypass) ([:2227](../addons/hr_holidays/models/hr_leave.py#L2227)) |
| Time-off manager (`leave_manager_id`) | For `manager` types: `confirm→validate`, `refuse→validate`, and refuse from `confirm`/`validate`. For `both` types: `confirm→validate1` (first approval only) plus `validate1→refuse`. Nothing on `hr` types ([:2242](../addons/hr_holidays/models/hr_leave.py#L2242)) |
| Officer | Everything: approve, validate, refuse, back-to-approval, resurrect cancelled (`cancel→confirm/validate/refuse`) ([:2232](../addons/hr_holidays/models/hr_leave.py#L2232)) |
| Anyone | Superuser bypasses all checks ([:2257](../addons/hr_holidays/models/hr_leave.py#L2257)) |

Double validation has an extra layer: `_check_double_validation_rules` — first approval (`validate1`) requires being the employee's leave manager or an officer; final `validate` on a `both` type requires the officer group; Administrators skip the whole check ([hr_leave.py:1515](../addons/hr_holidays/models/hr_leave.py#L1515)). So the intended split is *manager approves first, HR officer confirms second*.

**Who gets the approval activity** ([_get_responsible_for_approval:2336](../addons/hr_holidays/models/hr_leave.py#L2336)): `manager` type (or `both` in `confirm`) → the employee's `leave_manager_id`, falling back to the direct manager's user, then to `hr_responsible_id`; `hr` type (or `both` in `validate1`) → the employee's `hr_responsible_id`. **Changed in 20.0:** the leave type's `responsible_ids` ("Notify HR") field no longer exists — the HR step is routed per *employee* through `hr_responsible_id`, whose domain is restricted to users in the Time Off Officer group ([hr_version.py:22](../addons/hr_holidays/models/hr_version.py#L22)). Refused/cancelled leaves get their activities unlinked; validated ones get them marked done ([activity_update:2355](../addons/hr_holidays/models/hr_leave.py#L2355)).

---

## hr.work.entry.type — Configuration as Behavior Switches

**Changed in 20.0:** there is no `hr.leave.type` model. A "time off type" is an `hr.work.entry.type` record that `hr_holidays` decorates with the time-off switches ([hr_work_entry_type.py](../addons/hr_holidays/models/hr_work_entry_type.py)). The consequence worth internalizing: **the leave type and the work entry type are now one and the same record**, so the 19.0 indirection `hr.leave.type.work_entry_type_id` is gone — a validated leave materializes as work entries of *itself*.

Only the switches that change flow:

| Field | Behavior change |
|---|---|
| `time_off_selectable` ([:125](../addons/hr_holidays/models/hr_work_entry_type.py#L125)) | **New in 20.0.** The gate that separates "a work entry type" from "a time off type". Off (e.g. overtime/shift-premium types) = never offered in the leave form and skipped by `_check_validity` |
| `country_id` ([:61](../addons/hr_holidays/models/hr_work_entry_type.py#L61)) | **New in 20.0** for time off. Types are country-scoped; `default_get` and the request domain filter on the employee's company country. A company's country cannot be changed while country-typed leaves exist ([res_company.py:9](../addons/hr_holidays/models/res_company.py#L9)) |
| `leave_validation_type` ([:66](../addons/hr_holidays/models/hr_work_entry_type.py#L66)) | `no_validation` = auto-approved at create (in sudo); `hr` = HR responsible; `manager` = employee's approver; `both` = manager first, HR second |
| `requires_allocation` ([:71](../addons/hr_holidays/models/hr_work_entry_type.py#L71)) | On: requests are checked against validated allocations (`_check_validity`), the type only appears in the request dropdown if `has_valid_allocation` ([:244](../addons/hr_holidays/models/hr_work_entry_type.py#L244)). Off: unlimited requests, no balance tracking. **Cannot be flipped once leaves of the type exist** ([:259](../addons/hr_holidays/models/hr_work_entry_type.py#L259)) |
| `employee_requests` ([:72](../addons/hr_holidays/models/hr_work_entry_type.py#L72)) | On: employees may file their own *allocation* requests for this type. Off: only officers allocate |
| `allocation_validation_type` ([:76](../addons/hr_holidays/models/hr_work_entry_type.py#L76)) | Same 4 options, but for the allocation approval chain |
| `allows_negative` + `max_allowed_negative` ([:114](../addons/hr_holidays/models/hr_work_entry_type.py#L114)) | Lets the balance go below zero up to N days/hours. `_check_validity` then only blocks past `-max_allowed_negative`; an allocation (any, even 0-remaining) must still exist ([hr_leave.py:1429](../addons/hr_holidays/models/hr_leave.py#L1429)). A SQL constraint forces `max_allowed_negative > 0` when the flag is on |
| `unpaid` ([:97](../addons/hr_holidays/models/hr_work_entry_type.py#L97)) | A pure flag in this module — payroll semantics live in the payroll layer; accrual plans "based on worked time" also exclude unpaid leave time |
| `request_unit` ([:88](../addons/hr_holidays/models/hr_work_entry_type.py#L88)) | Day / half-day / hour — full treatment in [`hr_holidays_time_off_units.md`](hr_holidays_time_off_units.md). Note: for `day` types the computed duration is `ceil`'d to whole days ([hr_leave.py:1051](../addons/hr_holidays/models/hr_leave.py#L1051)) |
| `unit_of_measure` ([:94](../addons/hr_holidays/models/hr_work_entry_type.py#L94)) | Hours vs days — the unit the *balance* is allocated and displayed in, independent of `request_unit` |
| `count_days_as` ([:108](../addons/hr_holidays/models/hr_work_entry_type.py#L108)) | **New in 20.0.** `working` (duration follows the employee's schedule) vs `calendar` (a full week costs 7). The calendar branch is a separate duration path that is not re-rounded ([hr_leave.py:953](../addons/hr_holidays/models/hr_leave.py#L953)). Frozen once leaves of the type exist ([:206](../addons/hr_holidays/models/hr_work_entry_type.py#L206)) |
| `include_public_holidays_in_duration` ([:98](../addons/hr_holidays/models/hr_work_entry_type.py#L98)) | Label is now "Ignore Public Holidays". On: public holidays inside the request consume balance too (duration computed with `compute_leaves=False`). Guarded: cannot be toggled while current-year leaves overlap a public holiday ([:175](../addons/hr_holidays/models/hr_work_entry_type.py#L175)) |
| `count_as` (base field, [hr_work_entry/hr_work_entry_type.py:36](../addons/hr_work_entry/models/hr_work_entry_type.py#L36)) | `absence` vs `working_time` — replaces 19.0's `time_type` (`leave`/`other`). Copied onto the `resource.calendar.leaves` row; also decides the overlap bucket, presence status, and whether a zero-hour span is rejected or padded |
| `elligible_for_accrual_rate` ([:105](../addons/hr_holidays/models/hr_work_entry_type.py#L105)) | **Moved in 20.0** from `resource.calendar.leaves` to the type (and copied down onto the resource row). Defaults to `count_as != 'absence'`; `working_time` types are *forced* eligible by a constraint ([:169](../addons/hr_holidays/models/hr_work_entry_type.py#L169)) |
| `allow_request_on_top` ([:102](../addons/hr_holidays/models/hr_work_entry_type.py#L102)) | Exempts the type from the overlap check (`dashboard_warning_message` → `_check_date` ValidationError). **Changed in 20.0:** forbidden on `count_as='absence'` types ([:163](../addons/hr_holidays/models/hr_work_entry_type.py#L163)) |
| `support_document` ([:101](../addons/hr_holidays/models/hr_work_entry_type.py#L101)) | Shows the attachment widget on the request |
| `create_calendar_meeting` ([:37](../addons/hr_holidays/models/hr_work_entry_type.py#L37)) | Off: no `calendar.event` on validation |
| `sequence` (base) / `hide_on_dashboard` ([:44](../addons/hr_holidays/models/hr_work_entry_type.py#L44)) | Ordering/default pick in the request form; hide from the dashboard cards while staying requestable |

Stock types are no longer created by `hr_holidays` — it *writes time-off settings onto existing work entry types, matched by code* ([hr_work_entry_type_data.xml](../addons/hr_holidays/data/hr_work_entry_type_data.xml)): `016.00` Paid Time Off (`requires_allocation`, validation `both`), `013.00` Sick Time Off (no allocation, `support_document`, hidden on dashboard), `LEAVE105` Compensatory, `158.00` Unpaid. The rest of that file marks ~160 country-specific payroll codes as `time_off_selectable=False` or configures them per country.

Employees only get **read** on `hr.work.entry.type` (`access_hr_holidays_status_employee` in [ir.access.csv](../addons/hr_holidays/security/ir.access.csv)); Administrators get full `crud`.

---

## Allocations (hr.leave.allocation) — Basics

An allocation is the budget line: employee + type (`work_entry_type_id`) + `number_of_days` + validity window (`date_from`/`date_to`). **Changed in 20.0:** the `allocation_type` selection (`regular`/`accrual`) is gone — an allocation is an accrual one exactly when `accrual_plan_id` is set ([hr_leave_allocation.py:149](../addons/hr_holidays/models/hr_leave_allocation.py#L149); all accrual mechanics in [`hr_holidays_accrual_plans.md`](hr_holidays_accrual_plans.md)).

- **States**: `confirm → validate1 → validate / refuse` — no cancel state ([:87](../addons/hr_holidays/models/hr_leave_allocation.py#L87)). New records must be created in `confirm` ([create:903](../addons/hr_holidays/models/hr_leave_allocation.py#L903)); `no_validation` types auto-approve right after create.
- **Approval** mirrors leaves (`allocation_validation_type`, same `_get_next_states_by_state` shape, [:838](../addons/hr_holidays/models/hr_leave_allocation.py#L838)) with one extra rule: **nobody but an Administrator can approve/refuse their own allocation** ([:1041](../addons/hr_holidays/models/hr_leave_allocation.py#L1041)).
- **Shrink guard**: writing a smaller duration recomputes consumed leaves before/after and refuses if it would drop below what the employee already took (negative types get their cap respected) ([write:926](../addons/hr_holidays/models/hr_leave_allocation.py#L926)). It now only fires when one of `number_of_days_display`/`number_of_hours`/`state`/`date_to` is written.
- **Delete guards**: only `confirm`/`refuse` can be unlinked, and never if validated leaves consumed from it ([:967](../addons/hr_holidays/models/hr_leave_allocation.py#L967), [:975](../addons/hr_holidays/models/hr_leave_allocation.py#L975)). The state guard — not the taken-leaves one — is bypassable with the `allocation_skip_state_check` context, which the departure cleanup uses.
- **Balance math** lives in `hr.employee._get_consumed_leaves(work_entry_types, …)` ([hr_employee.py:544](../addons/hr_holidays/models/hr_employee.py#L544)): leaves in `confirm/validate1/validate` are all "virtually taken" (pending requests reserve balance); allocations are consumed in `date_to`-ascending order (expiring first); excess beyond all allocations is reported as `excess_days` ([:613](../addons/hr_holidays/models/hr_employee.py#L613)). This one method feeds the dashboard, the type's remaining-days display, `_check_validity` and the payroll "no allocation" warning.

Batch tools for officers: **Generate allocations for multiple employees** wizard (by employee/company/department/tag; auto-approves what the caller may approve, [hr_leave_allocation_generate_multi_wizard.py:113](../addons/hr_holidays/wizard/hr_leave_allocation_generate_multi_wizard.py#L113)) and its leave twin (**generates already-validated leaves** when run by an officer, splitting/refusing conflicting existing requests — [hr_leave_generate_multi_wizard.py:59](../addons/hr_holidays/wizard/hr_leave_generate_multi_wizard.py#L59)). **Changed in 20.0:** the leave wizard hard-refuses the batch if any conflicting existing request is an *hourly* leave, because it cannot split those ([:106](../addons/hr_holidays/wizard/hr_leave_generate_multi_wizard.py#L106)).

---

## Refuse vs Cancel vs Delete vs Back-to-Approval

Four distinct exits with different guards and different payroll consequences:

| Action | Who / when | What happens | Guards |
|---|---|---|---|
| **Refuse** ([action_refuse:2093](../addons/hr_holidays/models/hr_leave.py#L2093)) | Officer; leave manager for non-`hr` types. From `confirm/validate1/validate` | State `refuse`, approver stamped, meeting archived, employee + leave manager notified ([_notify_manager:2114](../addons/hr_holidays/models/hr_leave.py#L2114)); resource leave removed via the write-override, and time-rule allocation credits reversed | **No payslip guard** — refusing still deactivates already-paid work entries; `hr_payroll` only recomputes draft slips afterwards ([hr_payroll/hr_leave.py:301](../enterprise/hr_payroll/models/hr_leave.py#L301)). The asymmetry is documented in [`work_entries.md`](work_entries.md) |
| **Cancel** ([action_cancel:1907](../addons/hr_holidays/models/hr_leave.py#L1907) → wizard [hr_holidays_cancel_leave.py](../addons/hr_holidays/wizard/hr_holidays_cancel_leave.py) → [_action_user_cancel:2135](../addons/hr_holidays/models/hr_leave.py#L2135)) | The employee themselves, on own future `validate1/validate/refuse` leave (reason asked in wizard) | `_force_cancel` posts the reason, notifies the responsibles who had approved, sets state `cancel` in sudo, archives the meeting, removes the resource leave ([:2142](../addons/hr_holidays/models/hr_leave.py#L2142)) | `hr_payroll` marks it `payslip_state='done'` and recomputes draft slips ([hr_payroll/hr_leave.py:315](../enterprise/hr_payroll/models/hr_leave.py#L315)) |
| **Delete** ([_unlink_if_correct_states:1664](../addons/hr_holidays/models/hr_leave.py#L1664)) | Employee: only `confirm/validate1/cancel` and not in the past; Officer: only `cancel/confirm`; Administrator: anything | `unlink()` first runs `_prepare_leave_unlink` in sudo — time-rule credits reversed, then `_post_leave_cancel` (meeting + resource leave removed) ([:1684](../addons/hr_holidays/models/hr_leave.py#L1684)) | `hr_payroll` adds a hard stop: cannot delete a leave whose period is covered by a validated/paid regular payslip *confirmed after the leave was created* ([_check_uncovered_by_validated_payslip:370](../enterprise/hr_payroll/models/hr_leave.py#L370)) |
| **Back to Approval** ([action_back_to_approval:1940](../addons/hr_holidays/models/hr_leave.py#L1940)) | Officer, on `validate` | Back to `confirm`, activities rescheduled, meeting + resource leave removed ([_move_validate_leave_to_confirm:1944](../addons/hr_holidays/models/hr_leave.py#L1944)) | `hr_payroll` hides the button when the leave overlaps a validated/paid slip ([_compute_can_back_to_approve:233](../enterprise/hr_payroll/models/hr_leave.py#L233)) and raises `AccessError` for non-officers who reach the method anyway |

Additional edit guards: non-officers cannot modify a leave that already began unless they are its leave manager, and only managers touch cancelled leaves ([write:1599](../addons/hr_holidays/models/hr_leave.py#L1599)); **duplication is blocked** unless every copied leave is cancelled/refused ([copy_data:1760](../addons/hr_holidays/models/hr_leave.py#L1760), bypassable with the `skip_copy_check` context).

---

## Public Holidays & Mandatory Days

### Public holidays

**Changed in 20.0:** `models/resource.py` was split into [`resource_resource.py`](../addons/hr_holidays/models/resource_resource.py), [`resource_calendar.py`](../addons/hr_holidays/models/resource_calendar.py) and [`resource_calendar_leaves.py`](../addons/hr_holidays/models/resource_calendar_leaves.py). Every link below points at the last one.

A public holiday is a `resource.calendar.leaves` row with **no `resource_id`** (company-wide), optionally scoped to one working calendar. `hr_holidays` extends the model with the back-pointer `holiday_id` and `elligible_for_accrual_rate`, which defaults false ([resource_calendar_leaves.py:17](../addons/hr_holidays/models/resource_calendar_leaves.py#L17)) — stock public holidays therefore reduce worked-time accrual unless explicitly marked eligible. Two same-scope public holidays may not overlap, but the guard is Python-only and concurrent creates can race ([:21](../addons/hr_holidays/models/resource_calendar_leaves.py#L21)).

The important flow is **retroactive re-evaluation**: create/write/unlink triggers `_reevaluate_leaves` over every non-refused/cancelled leave in the company/time window, without an applicability filter for the specific calendar ([:61](../addons/hr_holidays/models/resource_calendar_leaves.py#L61), [:116](../addons/hr_holidays/models/resource_calendar_leaves.py#L116)). Durations are recomputed, each leave is bounced through `confirm` and back, the employee may be notified, and an underfunded leave is **auto-refused** ([:97](../addons/hr_holidays/models/resource_calendar_leaves.py#L97)). Validated leaves get their resource rows recreated. **Changed in 20.0:** time-rule *output* leaves (`source_leave_id` set) are excluded from re-evaluation — the rule engine re-runs them from their source instead ([:52](../addons/hr_holidays/models/resource_calendar_leaves.py#L52)); and the scope now keys on `employee_company_id` rather than the leave's own company.

Timezone handling: the conversion from wall time to the company timezone happens in the **loader wizard** (`convert_timezone(..., company.tz)`), and `create` honours a `convert_datetime` context flag. Direct writes on an existing public holiday still skip it. See [`public_holidays_flow.md`](public_holidays_flow.md) before operating across timezones or paid periods.

By default a public holiday inside a request costs nothing because `include_public_holidays_in_duration=False`. When true, the employee leave consumes the holiday. A leave consisting only of excluded public holidays/non-working days validates to 0 days and is rejected (unless its code is on the sickness/incapacity bypass list). Toggling the flag does not reliably recompute all existing past/future-year leaves, so migration needs an explicit reevaluation.

### New in 20.0: bundled public-holiday data, a loader wizard and a cron

`hr_holidays` now ships real public-holiday calendars as CSVs under [`data/public_holidays/`](../addons/hr_holidays/data/public_holidays/) — 20 countries (AU, BE, CH, EG, HK, IN, JO, KE, LT, LU, MA, MX, MY, NL, PL, RO, SA, SK, TR, US), declared under `other_files` so they are read at runtime rather than loaded as records.

Three entry points consume them, all through `_prepare_public_holidays_data(start_date, end_date)` ([resource_calendar_leaves.py:152](../addons/hr_holidays/models/resource_calendar_leaves.py#L152)), which picks the CSV per `company.country_code`, skips dates already covered by an existing company holiday, and reports back three buckets: companies with no country, companies with no data file, and companies already fully covered.

1. **Load Public Holidays wizard** — `load.public.holiday.wizard` ([wizard/load_public_holiday_wizard.py](../addons/hr_holidays/wizard/load_public_holiday_wizard.py)), reachable from the Company Holidays list button. You pick a **year** (must be > 2025), the wizard previews one editable line per holiday (`load.public.holiday.wizard.line`) with a pre-filled **time type** — the `006.00` "Public Holiday" work entry type for the company's country, falling back to the country-less one — and refuses to create anything until every line has a type ([:62](../addons/hr_holidays/wizard/load_public_holiday_wizard.py#L62)). Each created `resource.calendar.leaves` row carries that type's `count_as` and `elligible_for_accrual_rate`.
2. **Monthly cron** "Time Off: Generate Public Holidays" — `_cron_generate_public_holidays` ([:231](../addons/hr_holidays/models/resource_calendar_leaves.py#L231)) silently creates the next rolling **12 months** of holidays for every company, and no-ops under tests.
3. **Company creation** fires the same method immediately ([res_company.py:27](../addons/hr_holidays/models/res_company.py#L27)), so a new company starts with a populated holiday calendar.

Operationally this means public holidays now appear *without anyone asking*, and they land as ordinary `resource.calendar.leaves` rows — so the retroactive `_reevaluate_leaves` path above runs on them like any manual edit.

### Mandatory days (the former "stress days")

`hr.leave.mandatory.day` is a tiny model: name, date range, company, optional working-calendar / departments / job positions scoping ([hr_leave_mandatory_day.py:7](../addons/hr_holidays/models/hr_leave_mandatory_day.py#L7)). Matching is done per employee in `_get_mandatory_days` (calendar + job + department parent-chain filters, [hr_employee.py:509](../addons/hr_holidays/models/hr_employee.py#L509)). Effect: `has_mandatory_day` is computed on the leave ([hr_leave.py:831](../addons/hr_holidays/models/hr_leave.py#L831)) and `_check_validity` raises *"You are not allowed to request time off on a Mandatory Day"* — **for non-officers only**, and now only for leaves not already in `cancel`/`refuse` ([hr_leave.py:1473](../addons/hr_holidays/models/hr_leave.py#L1473)). Employees have read-only access to the model; only Administrators configure it (menu Time Off → Configuration → Mandatory Days). There is still no separate "stress day" model.

---

## Automatic Maintenance Around the Lifecycle

**Changed in 20.0: five crons, not two** ([ir_cron_data.xml](../addons/hr_holidays/data/ir_cron_data.xml)):

| Cron | Interval | What it does |
|---|---|---|
| Accrual Time Off | daily | `_get_to_update_accrual_allocations()._update_accrual()` — see the accrual doc |
| Time Off: Cancel invalid leaves | daily | `_cancel_invalid_leaves` ([hr_leave.py:2525](../addons/hr_holidays/models/hr_leave.py#L2525)) — scans leaves starting within 31 days whose type is fed by accrual allocations and force-cancels (chatter reason: "the accruated amount is insufficient") any that exceed the projected balance beyond the negative cap |
| Time Off: Generate Public Holidays | **monthly, new** | `_cron_generate_public_holidays` — rolling 12 months of country holidays per company |
| Time Off: Process daily time rules | **daily, new** | `_cron_process_day_undertime_rules` — the `hr.time.rule` engine's day pass |
| Time Off: Process weekly time rules | **weekly, new** | `_cron_process_week_time_rules` |

- **Contract/version changes** ([hr_version.py:32](../addons/hr_holidays/models/hr_version.py#L32), [:81](../addons/hr_holidays/models/hr_version.py#L81)): creating or re-dating a version with a different working schedule splits overlapping leaves per version period, refusing/re-creating them (last split segment lands in `confirm`); a constraint blocks a single leave spanning versions with different calendars ([_check_contracts:679](../addons/hr_holidays/models/hr_leave.py#L679)). **Changed in 20.0:** that constraint is skipped for time-rule-generated leaves and can be suppressed with the `skip_leave_version_check` context, which `hr.leave.write` sets automatically when the new dates stay inside the old span.
- **Employee/version calendar change:** the active path is version create/write, which splits/recomputes leaves across schedule periods and can reject insufficient allocations. The apparent employee-write block is still effectively disabled by its own `no_leave_resource_calendar_update` context ([hr_employee.py:328](../addons/hr_holidays/models/hr_employee.py#L328)). Public holidays are not employee-owned: applicability follows the date-effective calendar dynamically.
- **Manager/department change** ([hr_employee.py:367](../addons/hr_holidays/models/hr_employee.py#L367)): pending/future leaves and pending allocations get their `department_id`/`manager_id` refreshed; `leave_manager_id` follows `parent_id.user_id` when it was the default ([:264](../addons/hr_holidays/models/hr_employee.py#L264)).
- **Departure** — **changed in 20.0**: the `hr.departure.wizard` override is gone; the cleanup now hangs off the `hr.employee.departure` record's `action_register` ([hr_employee_departure.py:11](../addons/hr_holidays/models/hr_employee_departure.py#L11)). Leaves crossing the departure date are split at departure+1 (`_split_leaves`, [hr_leave.py:1981](../addons/hr_holidays/models/hr_leave.py#L1981)); post-departure approved leaves are force-cancelled; the remaining ones are **deleted, or refused instead** when a localization overrides `_check_refuse_future_leaves_condition` ([:92](../addons/hr_holidays/models/hr_employee_departure.py#L92)) — the default is delete. Running allocations get `date_to` = departure date, future ones deleted.
- **Presence/UX side effects**: validated current leaves flip `is_absent` and the presence icon (`presence_holiday_absent/present`, [hr_employee.py:114](../addons/hr_holidays/models/hr_employee.py#L114)). **Changed in 20.0:** the Discuss `im_status` → `leave_*` mapping is no longer computed in Python; it lives in the client store patches (`static/src/core/common/im_status_patch.js`). The user display name still gains "✈ Back on <date>" ([res_users.py:40](../addons/hr_holidays/models/res_users.py#L40)), where the return date is the **next working interval** after the leave, not `date_to` ([_get_first_working_interval_batch:126](../addons/hr_holidays/models/hr_employee.py#L126)); `res.partner.leave_date_to` mirrors it for multi-user partners ([res_partner.py:11](../addons/hr_holidays/models/res_partner.py#L11)). Department kanbans count absences and to-approve requests ([hr_department.py:22](../addons/hr_holidays/models/hr_department.py#L22)).
- **New in 20.0 — reporting**: alongside `hr.leave.report` (SQL union of leaves + allocations, [report/hr_leave_report.py](../addons/hr_holidays/report/hr_leave_report.py)) and `hr.leave.report.calendar` (the calendar/dashboard view model, [report/hr_leave_report_calendar.py](../addons/hr_holidays/report/hr_leave_report_calendar.py)), there is a third report model **`hr.leave.employee.report`** ([report/hr_leave_employee_report.py](../addons/hr_holidays/report/hr_leave_employee_report.py)) behind Reporting → *by Employee*. Both calendar-side models now share `hr.leave.display.name.mixin` so leave labels read identically everywhere.

Pure-UI/support files not affecting flow: [hr_employee_public.py](../addons/hr_holidays/models/hr_employee_public.py) (mirrors employee computes for the public model), [calendar_event.py](../addons/hr_holidays/models/calendar_event.py) (no video call on leave meetings, plus an edit-permission compute), [mail_message_subtype.py](../addons/hr_holidays/models/mail_message_subtype.py) (auto-creates department-level subtypes), [mail_activity_type.py](../addons/hr_holidays/models/mail_activity_type.py) (registers the 4 approval activity types as non-unlinkable via `_get_model_info_by_xmlid`), [res_groups.py](../addons/hr_holidays/models/res_groups.py) (marks the new Employee group as "light"), [hr_holidays_summary_employees.py](../addons/hr_holidays/wizard/hr_holidays_summary_employees.py) (PDF summary report launcher), [controllers/webmanifest.py](../addons/hr_holidays/controllers/webmanifest.py) (PWA share-target entry).

---

## Enterprise: the Defer Flow (now inside hr_payroll)

**Changed in 20.0:** `hr_payroll_holidays` no longer exists as a module — it was merged into `hr_payroll`, so installing Payroll is what brings the defer flow. All of it now lives in [enterprise/hr_payroll/models/hr_leave.py](../enterprise/hr_payroll/models/hr_leave.py). Everything still pivots on one field:

| `payslip_state` ([hr_leave.py:17](../enterprise/hr_payroll/models/hr_leave.py#L17)) | Label in 20.0 |
|---|---|
| `normal` | "To compute in next payslip" (default) |
| `done` | "Computed in current payslip" |
| `blocked` | "Payslip to be corrected" — the leave's period is already closed by a validated/paid slip |

### How a leave becomes blocked

On validation, before the base logic runs, `_action_validate` searches the employee's **regular** payslips: if a `validated`/`paid` slip overlaps the leave **and no other, not-yet-validated regular slip also covers it**, `payslip_state='blocked'` ([hr_leave.py:247](../enterprise/hr_payroll/models/hr_leave.py#L247)). Afterwards `_recompute_payslips` refreshes the draft slips (empty ones recompute worked days, computed ones run `action_refresh_from_work_entries`, [:325](../enterprise/hr_payroll/models/hr_leave.py#L325)) — the same refresh runs after refuse, cancel, back-to-approval and delete.

### What blocked means for payroll correctness

- **Excluded from work-entry generation**: `hr.version._get_resource_calendar_leaves` filters blocked leaves out of calendar-based generation ([hr_payroll/hr_version.py:710](../enterprise/hr_payroll/models/hr_version.py#L710)). The already-paid attendance entries of the closed month stay untouched. **Changed in 20.0:** the second exclusion path — the `_cancel_work_entry_conflict` hook that also scheduled the "Leave to Defer" activity — is gone with the old bridge module.
- **Changed in 20.0 — the error surface**: the hard-coded payslip errors were replaced by configurable `hr.payroll.warning` records ([hr_payroll_warning_data.xml](../enterprise/hr_payroll/data/hr_payroll_warning_data.xml)). A `warning`-level record *Leaves to defer* matches every `payslip_state='blocked'` leave and renders on the leave itself (`display_on_model`) as an `issues` JSON entry with a **"Correct Payslip"** action ([hr_leave.py:88](../enterprise/hr_payroll/models/hr_leave.py#L88)). A second one flags leaves whose `excess_days` show no covering allocation.
- **Auto-approval is suppressed** for a `no_validation` leave created by a non-officer when any *danger*-level payroll warning applies; an HR-responsible approval activity is scheduled instead ([_process_auto_approve_activities:65](../enterprise/hr_payroll/models/hr_leave.py#L65)). This is new in 20.0 and is the one place payroll can veto a self-service leave.
- **Guards on destructive paths** (all above in the refuse/cancel/delete table): delete is blocked when a validated/paid regular slip confirmed *after* the leave covers it ([:370](../enterprise/hr_payroll/models/hr_leave.py#L370)); Back-to-Approval is hidden and, if forced, raises for non-officers ([:233](../enterprise/hr_payroll/models/hr_leave.py#L233), [:306](../enterprise/hr_payroll/models/hr_leave.py#L306)). Refuse remains unguarded (community asymmetry).
- `compute_sheet` on regular slips marks every non-blocked, non-refused leave ending before the slip horizon as `done` ([hr_payslip.py:1322](../enterprise/hr_payroll/models/hr_payslip.py#L1322)), and refunding a slip flips the blocked leaves it covered back to `normal` ([_action_refund_payslips:1181](../enterprise/hr_payroll/models/hr_payslip.py#L1181)) — the "green" state is bookkeeping, nothing reads it for money.

### Resolution paths

**Changed in 20.0:** the old `action_report_to_next_month` (which rewrote next month's draft `WORK100` entries into leave-typed ones) and its "Defer to Next Month" server action are **gone**.

1. **Correct Payslip** — `action_adjust_corresponding_payslip` ([:281](../enterprise/hr_payroll/models/hr_leave.py#L281)) finds the most recent `validated`/`paid` slip of the employee's structure type overlapping the leave and delegates to `hr.payslip.action_adjust_payslip()`, i.e. the generic payslip-amendment mechanism. The fiddly work-entry surgery is now payroll's problem, not the leave's.
2. **Mark as handled** — completing the "Leave to Defer" activity: `activity_feedback(['hr_payroll.mail_activity_data_hr_leave_to_defer'])` sets `payslip_state='done'` ([:345](../enterprise/hr_payroll/models/hr_leave.py#L345)); cancelling the leave does the same ([:315](../enterprise/hr_payroll/models/hr_leave.py#L315)).

The **Deferred Time Off Manager** company setting survives in `hr_payroll` ([res_company.py:71](../enterprise/hr_payroll/models/res_company.py#L71), [res_config_settings.py:16](../enterprise/hr_payroll/models/res_config_settings.py#L16)).

Deeper payslip-side context (warning records, adjustment slips, payroll statuses) is in [`hr_payroll.md`](hr_payroll.md).

---

## Configuration & Settings

- **Time Off Approver** (employee form, HR Settings tab → `leave_manager_id`) — who approves `manager`-step requests; setting it auto-adds the user to the Responsible group, unsetting removes it if they manage nobody else ([hr_employee.py:341](../addons/hr_holidays/models/hr_employee.py#L341), [res_users.py:14](../addons/hr_holidays/models/res_users.py#L14)).
- **HR Responsible** (`hr_responsible_id` on the employee/version) — **replaces 19.0's "Notify HR" (`responsible_ids`) on the leave type.** Who gets `hr`-step activities; the field's domain only accepts Time Off Officers ([hr_version.py:22](../addons/hr_holidays/models/hr_version.py#L22)). Empty = nobody is notified (approval still possible for any officer).
- **Deferred Time Off Manager** (Payroll → Settings → `deferred_time_off_manager`, [enterprise/hr_payroll/models/res_config_settings.py:16](../enterprise/hr_payroll/models/res_config_settings.py#L16)).
- **Menus renamed in 20.0** ([hr_holidays_views.xml](../addons/hr_holidays/views/hr_holidays_views.xml)): Configuration → **Time Types** (the `hr.work.entry.type` list), **Accrual Plans**, **Company Holidays** (= `resource.calendar.leaves` without resource, Administrator-only, carries the *Load Public Holidays* button), **Mandatory Days** (Administrator-only). Reporting → *by Employee* / *by Type* / *Balance*.

---

## Dependencies

**Changed in 20.0** — the manifest now declares only three: `hr_work_entry`, `hr_calendar`, `resource`.

| Requires | Why |
|---|---|
| `hr_work_entry` | **new** — owns `hr.work.entry.type` (the time off type itself), `hr.work.entry`, and the `hr.time.rule` engine. Pulls in `hr` transitively |
| `hr_calendar` | **new** — pulls in `calendar` for the optional meeting created per validated leave, plus multi-employee calendar helpers |
| `resource` | working calendars; `resource.calendar.leaves` is the materialized-absence table |
| (`mail`, `hr`, `calendar`) | transitive: chatter, approval activities, notification subtypes, meetings |

| Works with | What it adds |
|---|---|
| `hr_payroll` (enterprise) | the defer flow above — `hr_payroll_holidays` no longer exists |
| `hr_holidays_attendance` | **Changed in 20.0:** the `overtime_deductible` leave-type flag and the extra-hours balance check on approve are **gone**. It now wires attendance into accruals (`worked_hours` frequency prorata, [hr_leave_allocation.py:13](../addons/hr_holidays_attendance/models/hr_leave_allocation.py#L13)) and into the time-rule allocation-credit path ([hr_time_rule.py](../addons/hr_holidays_attendance/models/hr_time_rule.py)) |
| `hr_holidays_gantt`, `hr_holidays_contract_gantt` | Gantt/UI layers only |
| `hr_holidays_homeworking`, `project_timesheet_holidays`, `planning_holidays`, `l10n_fr_hr_holidays`, `l10n_in_hr_holidays` | work-location, analytic-line and Planning effects; full relation map in [`public_holidays_flow.md`](public_holidays_flow.md) |

### New in 20.0: time rules on leaves

`hr.time.rule` comes from `hr_work_entry`; `hr_holidays` extends it with two fields ([hr_time_rule.py:26](../addons/hr_holidays/models/hr_time_rule.py#L26)): **Allocate %** (`leave_compensation_rate`) and **Allocate to** (`allocation_type_id`, restricted to allocation-requiring, time-off-selectable types). A rule that fires on excess/deficit time can therefore (a) *split or trim a leave* into rule-typed output leaves — `hr.leave.source_leave_id` / `output_leave_ids` / `is_time_rule_trimmed` — and (b) *credit an open-ended allocation* at the configured rate, logged on `hr.time.rule.allocation.log` ([_apply_allocation_credits:76](../addons/hr_holidays/models/hr_time_rule.py#L76)). Credits are reversed whenever the source leave is rewritten, refused or deleted. Two of the new crons drive the day/week passes.

---

## Gotchas & Non-Obvious Behavior

- **Refuse vs cancel asymmetry is still the payroll-integrity hole**: refusing a validated leave deactivates already-paid work entries and regenerates attendance, with no payslip guard — only delete and back-to-approval are guarded. Details in [`work_entries.md`](work_entries.md); nothing in `hr_payroll` closes this either.
- **The class docstring lies about visibility**: regular employees see only their *own* leaves ([ir.access.csv](../addons/hr_holidays/security/ir.access.csv), `hr_leave_rule_employee`), not "all leaves" as the 15-year-old docstring at [hr_leave.py:40](../addons/hr_holidays/models/hr_leave.py#L40) claims.
- **New in 20.0 — an officer creating a leave auto-approves it.** `_process_auto_approve_activities` approves in sudo when `validation_type == 'no_validation'` **or** the creating user is in `group_hr_holidays_user` ([hr_leave.py:1590](../addons/hr_holidays/models/hr_leave.py#L1590)). An officer filing their own `both`-validation leave therefore never passes through an approval step at all.
- **Pending requests reserve balance**: `confirm` and `validate1` leaves count as "virtually taken" in every balance computation ([_get_consumed_leaves:544](../addons/hr_holidays/models/hr_employee.py#L544)) — a stack of unapproved requests can block new ones.
- **Changed in 20.0 — the overlap check is now bucketed by `count_as`.** Two leaves only conflict if they share the same `count_as` value and **both** types have `allow_request_on_top=False`; time-rule-generated leaves are excluded entirely ([_compute_dashboard_warning_message:495](../addons/hr_holidays/models/hr_leave.py#L495) → [_check_date:1383](../addons/hr_holidays/models/hr_leave.py#L1383)). In 19.0 only the *other* type's flag was consulted and there was no bucketing, so a `working_time` training and an `absence` now coexist where they used to clash.
- **New in 20.0 — two more hard constraints on `hr.leave`**: `_check_max_absence_per_day` caps hourly absence requests at the schedule's expected hours (24h/day on flexible calendars, [hr_leave.py:1348](../addons/hr_holidays/models/hr_leave.py#L1348)), and `_check_executive_employee_type` forbids **any** leave for employees of contract type "company executive" ([:1409](../addons/hr_holidays/models/hr_leave.py#L1409)).
- **Officers can resurrect cancelled leaves** (`cancel → confirm/validate/refuse` in the transition matrix, [hr_leave.py:2232](../addons/hr_holidays/models/hr_leave.py#L2232)) even though `_check_approval_update` blocks everyone else with "A cancelled leave cannot be modified".
- **Public-holiday edits rewrite history**: `_reevaluate_leaves` changes validated leave durations, may auto-refuse leave and indirectly deactivate validated work entries, while existing holiday work entries remain stale. In 20.0 this is riskier, because the **monthly cron creates public holidays on its own** — a company that never opens the wizard will still get its calendar rewritten. Block paid/validated intervals server-side.
- **A daily cron force-cancels future leaves** whose accrual balance no longer covers them ([_cancel_invalid_leaves:2525](../addons/hr_holidays/models/hr_leave.py#L2525)) — approved leaves can disappear overnight after an allocation/plan change.
- **Fixed in 20.0:** the 19.0 selection→boolean leftovers are gone — `_search_virtual_remaining_leaves` now tests `not work_entry_type.requires_allocation` properly ([hr_work_entry_type.py:281](../addons/hr_holidays/models/hr_work_entry_type.py#L281)) and no `'yes'` string comparisons remain in the module.
- **Employee unlink line on allocations still grants nothing**: its domain requires `state='draft'`, a state allocations never have (`hr_leav_allocation_rule_employee_unlink` in [ir.access.csv](../addons/hr_holidays/security/ir.access.csv)) — employees cannot delete even their own pending allocation requests (officers can).
- **Day-unit types round up**: `ceil(days)` on the computed duration ([hr_leave.py:1051](../addons/hr_holidays/models/hr_leave.py#L1051)) — a 4.5-working-day span costs 5 days, with an explanatory banner (`work_entry_type_increases_duration`, [:863](../addons/hr_holidays/models/hr_leave.py#L863)). `count_days_as='calendar'` types take a different branch and are **not** re-rounded.
- **Dead code in the merged defer flow**: `hr.leave.write` in `hr_payroll` guards on `vals.get('active')`, a field `hr.leave` does not have, and then calls `_check_uncovered_by_validated_payslip()` twice ([enterprise/hr_payroll/models/hr_leave.py:389](../enterprise/hr_payroll/models/hr_leave.py#L389)) — only the `unlink` guard is live. **Fixed in 20.0:** `_issues_dependencies` now exists for real ([:83](../enterprise/hr_payroll/models/hr_leave.py#L83)), so the to-defer warning *is* recomputed reactively on `payslip_state`.
- **`blocked` only triggers against *regular* payslips** (`is_regular`, [enterprise/hr_payroll/models/hr_leave.py:258](../enterprise/hr_payroll/models/hr_leave.py#L258)) — credit notes/refund slips over the period don't cause deferral.
- **Installing payroll still silently promotes every payroll user to Time Off Officer** ([enterprise/hr_payroll/security/hr_payroll_security.xml:14](../enterprise/hr_payroll/security/hr_payroll_security.xml#L14)) — they can approve/refuse anyone's leave.
- **Latent bug in the employee-calendar-change path**: the block at [hr_employee.py:359](../addons/hr_holidays/models/hr_employee.py#L359) still references `l.leave_type_request_unit`, a field that no longer exists on `hr.leave` (it is `work_entry_type_request_unit` now). It never raises only because `write` disables itself with `no_leave_resource_calendar_update`; anything that clears that context key will crash.

---

## Related Docs

- [`INDEX.md`](INDEX.md)
- [`hr_holidays_accrual_plans.md`](hr_holidays_accrual_plans.md) — accrual plans, milestones, carry-over
- [`hr_holidays_time_off_units.md`](hr_holidays_time_off_units.md) — day/half-day/hour units and conversion
- [`work_entries.md`](work_entries.md) — how validated leaves become work entries; the full leave-lifecycle × work-entry table
- [`hr_payroll.md`](hr_payroll.md) — payslip error gates, defer error reactivity caveat, payroll statuses
- [`attendance_work_entry.md`](attendance_work_entry.md) — attendance-sourced entries interacting with leaves
- [`hr_employee_versions.md`](hr_employee_versions.md) — version model that leave splitting reacts to
- [`resource_calendars.md`](resource_calendars.md) — the calendars that price a leave's duration
- [`payroll_wage_types.md`](payroll_wage_types.md) — how leave-typed worked-day lines get amounts

# Time Off — Core Module (hr_holidays) + Payroll Deferral (hr_payroll_holidays)

> **Modules:** `hr_holidays` (community) | **Path:** [`addons/hr_holidays/`](../addons/hr_holidays/)
> `hr_payroll_holidays` (enterprise, auto-install) | **Path:** [`enterprise/hr_payroll_holidays/`](../enterprise/hr_payroll_holidays/)
> **Updated by Codex and verified from source:** 2026-07-12
> Narrow sibling docs: complete public-holiday lifecycle → [`public_holidays_flow.md`](public_holidays_flow.md), accruals → [`hr_holidays_accrual_plans.md`](hr_holidays_accrual_plans.md), day/half-day/hour units → [`hr_holidays_time_off_units.md`](hr_holidays_time_off_units.md), work-entry materialization → [`work_entries.md`](work_entries.md).

## What It Does & Why It Exists

`hr_holidays` is the request/approval engine for absences. Employees file **time off requests** (`hr.leave`) against **time off types** (`hr.leave.type`); HR grants budgets through **allocations** (`hr.leave.allocation`); approvers move requests through a small state machine. A validated leave becomes a `resource.calendar.leaves` row — that is the single handoff point every other module (work entries, planning, timesheets, accruals) consumes. The module also owns **public holidays** (company-wide `resource.calendar.leaves`) and **mandatory days** (days on which employees may not request leave).

`hr_payroll_holidays` solves one payroll-specific problem: a leave approved **after** its month's payslip is already validated/paid. It flags such leaves (`payslip_state='blocked'`), keeps them out of work-entry generation so they cannot corrupt a closed period, and gives payroll two resolution paths (defer to next month, or mark handled manually).

---

## The Big Picture — Request Lifecycle

```
            create()                    action_approve()                 action_approve()
 employee ───────────► confirm ──────────────────────► validate1 ────────────────────► validate
                          │        (only if type is 'both')   │                            │
                          │                                    │                            ├─► resource.calendar.leaves created
                          │      action_refuse()               │                            ├─► calendar.event meeting (optional)
                          ├───────────────────────► refuse ◄───┘                            ├─► work entries regenerated (bridge)
                          │                                                                 │
                          │                              action_cancel() wizard             │
                          └────── (delete allowed) ◄──── cancel ◄───────────────────────────┘
                                                                     action_back_to_approval() → confirm
```

States: `confirm` (To Approve) → `validate1` (Second Approval) → `validate` (Approved), plus `refuse` and `cancel` ([hr_leave.py:129](../addons/hr_holidays/models/hr_leave.py#L129)). There is **no draft state** in v19 — a new request is born in `confirm` (a stale `'draft'` literal survives in one write-guard, [hr_leave.py:908](../addons/hr_holidays/models/hr_leave.py#L908)).

Step by step:

1. **Create** ([create:863](../addons/hr_holidays/models/hr_leave.py#L863)). `default_get` pre-picks the first leave type (by `sequence`) that either needs no allocation or has a valid one ([hr_leave.py:79](../addons/hr_holidays/models/hr_leave.py#L79)). The user only enters `request_date_from/to` (+ half-day period or hour range); `date_from/date_to` and durations are computed from the employee's calendar ([_compute_date_from_to:431](../addons/hr_holidays/models/hr_leave.py#L431), [_get_durations:552](../addons/hr_holidays/models/hr_leave.py#L552)). `_check_validity` runs immediately: allocation coverage, negative-cap, and mandatory-day checks ([hr_leave.py:751](../addons/hr_holidays/models/hr_leave.py#L751)). If the type is `no_validation`, the request is **auto-approved in sudo** right inside create with an "automatically approved" chatter note ([hr_leave.py:894](../addons/hr_holidays/models/hr_leave.py#L894)). Otherwise `activity_update()` schedules an approval activity on the responsible ([hr_leave.py:1465](../addons/hr_holidays/models/hr_leave.py#L1465)).
2. **Approve** ([action_approve:1097](../addons/hr_holidays/models/hr_leave.py#L1097)). One button serves both steps: for a `both`-validation leave in `confirm` it writes `validate1` + `first_approver_id`; otherwise it calls `_action_validate`. The first-approval activity is marked done and a "Second approval request" activity is created for the officer ([activity_update:1475](../addons/hr_holidays/models/hr_leave.py#L1475)).
3. **Validate** ([_action_validate:1185](../addons/hr_holidays/models/hr_leave.py#L1185)). Refuses to proceed if any leave falls entirely on non-working days/public holidays (`number_of_days == 0` → "not supposed to work during that period", [hr_leave.py:1190](../addons/hr_holidays/models/hr_leave.py#L1190); the work-entry bridge exempts codes LEAVE110/210/280, [hr_work_entry_holidays/hr_leave.py:125](../addons/hr_work_entry_holidays/models/hr_leave.py#L125)). Writes `validate`, stamps first/second approver, then `_validate_leave_request` ([:1009](../addons/hr_holidays/models/hr_leave.py#L1009)) creates the `resource.calendar.leaves` row ([_create_resource_leave:996](../addons/hr_holidays/models/hr_leave.py#L996)) and, if the type has `create_calendar_meeting`, a confidential `calendar.event` in the employee's calendar ([:1014](../addons/hr_holidays/models/hr_leave.py#L1014)). The employee gets a "has been accepted" message.
4. **After validation** the leave is effectively frozen: a constraint blocks date/employee edits in `validate1/validate` ([_check_date_state:743](../addons/hr_holidays/models/hr_leave.py#L743)), and any state write away from `validate` deletes the linked `resource.calendar.leaves` first ([write:913](../addons/hr_holidays/models/hr_leave.py#L913)).

### Key Decision Points

- **Leave type validation flow** (`leave_validation_type`): `no_validation` / `hr` / `manager` / `both` — decides who must click and how many times.
- **Requires allocation**: with it, the request is checked against granted days; without it (e.g. stock Sick Time Off), employees can request freely.
- **What happens to a validated leave later** — refuse vs cancel vs delete — has three different guard sets (see the dedicated section below).

---

## Who Can Do What

### Groups ([hr_holidays_security.xml](../addons/hr_holidays/security/hr_holidays_security.xml))

| Group | xmlid | Gets |
|---|---|---|
| Time Off Responsible | `group_hr_holidays_responsible` | Team-approver role. Auto-granted/removed when a user is set/unset as someone's `leave_manager_id` ([hr_employee.py:220](../addons/hr_holidays/models/hr_employee.py#L220), [res_users.py:48](../addons/hr_holidays/models/res_users.py#L48)) |
| Officer: Manage all requests | `group_hr_holidays_user` | See and manage everyone's requests; implies Responsible + HR Officer |
| Administrator | `group_hr_holidays_manager` | Everything, incl. configuration and deleting approved records |

Installing payroll widens this: **payroll user and payroll manager both imply Time Off Officer** ([hr_payroll_holidays_security.xml:5](../enterprise/hr_payroll_holidays/security/hr_payroll_holidays_security.xml#L5)).

### Record rules — what a plain employee actually sees

The class docstring claims a regular employee "can see all leaves" ([hr_leave.py:38](../addons/hr_holidays/models/hr_leave.py#L38)) — **that is stale**. The `base.group_user` read rule limits reads to *own* leaves ([hr_leave_rule_employee:34](../addons/hr_holidays/security/hr_holidays_security.xml#L34)); Responsible additionally reads their team's ([:72](../addons/hr_holidays/security/hr_holidays_security.xml#L72)); only Officer+ reads all ([:99](../addons/hr_holidays/security/hr_holidays_security.xml#L99)). Employees can write on own non-validated leaves, and their `leave_manager_id` can write when the type's validation is manager/both/no_validation ([:44](../addons/hr_holidays/security/hr_holidays_security.xml#L44)). Officers can never write their **own** `validate` leave through the officer rule ([:109](../addons/hr_holidays/security/hr_holidays_security.xml#L109)).

The leave **description is private**: `name` is a compute over `private_name` (group-restricted to Responsible); anyone who is not officer/owner/leave-manager sees `*****` ([hr_leave.py:322](../addons/hr_holidays/models/hr_leave.py#L322)).

### The approval matrix

Every button's availability comes from `can_approve/can_validate/can_refuse/can_cancel/can_back_to_approve` computes, all funneled through `_check_approval_update` → `_get_next_states_by_state` ([hr_leave.py:1321](../addons/hr_holidays/models/hr_leave.py#L1321), [:1367](../addons/hr_holidays/models/hr_leave.py#L1367)):

| Actor | Can do |
|---|---|
| Employee (own leave) | Cancel own `validate1/validate/refuse` leave — but only if it hasn't started yet (`is_in_past` blocks it; officers bypass) ([:1339](../addons/hr_holidays/models/hr_leave.py#L1339)) |
| Time-off manager (`leave_manager_id`) | For `manager` types: confirm→validate, refuse. For `both` types: confirm→validate1 (first approval only), refuse. Nothing on `hr` types ([:1354](../addons/hr_holidays/models/hr_leave.py#L1354)) |
| Officer | Everything: approve, validate, refuse, back-to-approval, resurrect cancelled (`cancel→confirm/validate/refuse`) ([:1344](../addons/hr_holidays/models/hr_leave.py#L1344)) |
| Anyone | Superuser bypasses all checks ([:1369](../addons/hr_holidays/models/hr_leave.py#L1369)) |

Double validation has an extra layer: `_check_double_validation_rules` — first approval (`validate1`) requires being the employee's leave manager or an officer; final `validate` on a `both` type requires the officer group ([hr_leave.py:850](../addons/hr_holidays/models/hr_leave.py#L850)). So the intended split is *manager approves first, HR officer confirms second*.

**Who gets the approval activity** ([_get_responsible_for_approval:1448](../addons/hr_holidays/models/hr_leave.py#L1448)): `manager` type (or `both` in `confirm`) → the employee's `leave_manager_id`, falling back to the direct manager's user; `hr` type (or `both` in `validate1`) → the type's `responsible_ids` ("Notify HR" users on the leave type). Refused/cancelled leaves get their activities unlinked; validated ones get them marked done ([activity_update:1509](../addons/hr_holidays/models/hr_leave.py#L1509)).

---

## hr.leave.type — Configuration as Behavior Switches

The type is where nearly all behavior is decided ([hr_leave_type.py](../addons/hr_holidays/models/hr_leave_type.py)). Only the switches that change flow:

| Field | Behavior change |
|---|---|
| `leave_validation_type` ([:83](../addons/hr_holidays/models/hr_leave_type.py#L83)) | `no_validation` = auto-approved at create (in sudo); `hr` = only officers; `manager` = employee's approver; `both` = manager first, officer second |
| `requires_allocation` ([:88](../addons/hr_holidays/models/hr_leave_type.py#L88)) | On: requests are checked against validated allocations (`_check_validity`), the type only appears in the request dropdown if `has_valid_allocation` ([:102](../addons/hr_holidays/models/hr_leave_type.py#L102)). Off: unlimited requests, no balance tracking. **Cannot be flipped once leaves of the type exist** ([:244](../addons/hr_holidays/models/hr_leave_type.py#L244)) |
| `employee_requests` ([:89](../addons/hr_holidays/models/hr_leave_type.py#L89)) | On: employees may file their own *allocation* requests for this type (allocation domain [hr_leave_allocation.py:33](../addons/hr_holidays/models/hr_leave_allocation.py#L33)). Off: only officers allocate |
| `allocation_validation_type` ([:92](../addons/hr_holidays/models/hr_leave_type.py#L92)) | Same 4 options, but for the allocation approval chain |
| `allows_negative` + `max_allowed_negative` ([:121](../addons/hr_holidays/models/hr_leave_type.py#L121)) | Lets the balance go below zero up to N days/hours. `_check_validity` then only blocks past `-max_allowed_negative`; an allocation (any, even 0-remaining) must still exist ([hr_leave.py:760](../addons/hr_holidays/models/hr_leave.py#L760)) |
| `unpaid` ([:109](../addons/hr_holidays/models/hr_leave_type.py#L109)) | A pure flag in this module — payroll semantics (unpaid worked-day lines) live in the work-entry/payroll layer; accrual plans "based on worked time" also exclude unpaid leave time |
| `work_entry_type_id` (added by bridge, [hr_work_entry_holidays/hr_leave.py:12](../addons/hr_work_entry_holidays/models/hr_leave.py#L12)) | The pointer that decides which work-entry type a validated leave materializes as — the mechanics are in [`work_entries.md`](work_entries.md) |
| `request_unit` ([:105](../addons/hr_holidays/models/hr_leave_type.py#L105)) | Day / half-day / hour — full treatment in [`hr_holidays_time_off_units.md`](hr_holidays_time_off_units.md). Note: for `day` types the computed duration is `ceil`'d to whole days ([hr_leave.py:627](../addons/hr_holidays/models/hr_leave.py#L627)) |
| `include_public_holidays_in_duration` ([:110](../addons/hr_holidays/models/hr_leave_type.py#L110)) | On: public holidays inside the request consume balance too (duration computed with `compute_leaves=False`, [hr_leave.py:574](../addons/hr_holidays/models/hr_leave.py#L574)). Guarded: cannot be toggled while current-year leaves overlap a public holiday ([:178](../addons/hr_holidays/models/hr_leave_type.py#L178)) |
| `time_type` ([:103](../addons/hr_holidays/models/hr_leave_type.py#L103)) | `leave` (absence) vs `other` (worked time, e.g. training) — copied onto the `resource.calendar.leaves` row and used by accrual "worked time" proration and presence status |
| `allow_request_on_top` ([:114](../addons/hr_holidays/models/hr_leave_type.py#L114)) | Exempts the type from the overlap check (`dashboard_warning_message` → `_check_date` ValidationError). Only allowed on `time_type='other'` types ([:166](../addons/hr_holidays/models/hr_leave_type.py#L166)) |
| `support_document` ([:113](../addons/hr_holidays/models/hr_leave_type.py#L113)) | Shows the attachment widget on the request; payroll dashboard warns on requests missing one (see defer section) |
| `create_calendar_meeting` ([:47](../addons/hr_holidays/models/hr_leave_type.py#L47)) | Off: no `calendar.event` on validation |
| `sequence` / `hide_on_dashboard` ([:45](../addons/hr_holidays/models/hr_leave_type.py#L45), [:52](../addons/hr_holidays/models/hr_leave_type.py#L52)) | Ordering/default pick in the request form; hide from the dashboard cards while staying requestable |
| `responsible_ids` ("Notify HR") ([:77](../addons/hr_holidays/models/hr_leave_type.py#L77)) | The officers who receive `hr`-step approval activities |

Stock types shipped: Paid Time Off (`requires_allocation`, validation `both`), Sick Time Off (no allocation, `support_document`, hidden on dashboard), Compensatory Days, Unpaid ([hr_leave_type_data.xml](../addons/hr_holidays/data/hr_leave_type_data.xml)).

Employees only get **read** on `hr.leave.type` ([ir.model.access.csv](../addons/hr_holidays/security/ir.model.access.csv)); a multi-company rule also matches `company_id=False` types filtered by country ([hr_holidays_security.xml:256](../addons/hr_holidays/security/hr_holidays_security.xml#L256)).

---

## Allocations (hr.leave.allocation) — Basics

An allocation is the budget line: employee + type + `number_of_days` + validity window (`date_from`/`date_to`). Two kinds ([hr_leave_allocation.py:119](../addons/hr_holidays/models/hr_leave_allocation.py#L119)): `regular` (fixed grant) and `accrual` (grows via a plan — all mechanics in [`hr_holidays_accrual_plans.md`](hr_holidays_accrual_plans.md)).

- **States**: `confirm → validate1 → validate / refuse` — no cancel state ([:58](../addons/hr_holidays/models/hr_leave_allocation.py#L58)). New records must be created in `confirm` ([:764](../addons/hr_holidays/models/hr_leave_allocation.py#L764)); `no_validation` types auto-approve right after create ([:781](../addons/hr_holidays/models/hr_leave_allocation.py#L781)).
- **Approval** mirrors leaves (`allocation_validation_type`, same `_get_next_states_by_state` shape, [:668](../addons/hr_holidays/models/hr_leave_allocation.py#L668)) with one extra rule: **nobody but an Administrator can approve/refuse their own allocation** ([:899](../addons/hr_holidays/models/hr_leave_allocation.py#L899)).
- **Shrink guard**: writing a smaller duration recomputes consumed leaves before/after and refuses if it would drop below what the employee already took (negative types get their cap respected) ([write:799](../addons/hr_holidays/models/hr_leave_allocation.py#L799)).
- **Delete guards**: only `confirm`/`refuse` can be unlinked, and never if validated leaves consumed from it ([:823](../addons/hr_holidays/models/hr_leave_allocation.py#L823), [:831](../addons/hr_holidays/models/hr_leave_allocation.py#L831)).
- **Balance math** lives in `hr.employee._get_consumed_leaves` ([hr_employee.py:413](../addons/hr_holidays/models/hr_employee.py#L413)): leaves in `confirm/validate1/validate` are all "virtually taken" (pending requests reserve balance); allocations are consumed in `date_to`-ascending order (expiring first); excess beyond all allocations is reported as `excess_days`. This one method feeds the dashboard, the type's remaining-days display and `_check_validity`.

Batch tools for officers: **Generate allocations for multiple employees** wizard (by employee/company/department/tag; auto-approves what the caller may approve, [hr_leave_allocation_generate_multi_wizard.py:107](../addons/hr_holidays/wizard/hr_leave_allocation_generate_multi_wizard.py#L107)) and its leave twin (**generates already-validated leaves** when run by an officer, splitting/refusing conflicting existing requests — [hr_leave_generate_multi_wizard.py:72](../addons/hr_holidays/wizard/hr_leave_generate_multi_wizard.py#L72)).

---

## Refuse vs Cancel vs Delete vs Back-to-Approval

Four distinct exits with different guards and different payroll consequences:

| Action | Who / when | What happens | Guards |
|---|---|---|---|
| **Refuse** ([action_refuse:1212](../addons/hr_holidays/models/hr_leave.py#L1212)) | Officer; leave manager for non-`hr` types. From `confirm/validate1/validate` | State `refuse`, approver stamped, meeting archived, employee + leave manager notified ([_notify_manager:1233](../addons/hr_holidays/models/hr_leave.py#L1233)); resource leave removed via the write-override; work-entry bridge archives linked entries and regenerates attendance ([hr_work_entry_holidays/hr_leave.py:139](../addons/hr_work_entry_holidays/models/hr_leave.py#L139)) | **No payslip guard** — refusing deactivates even validated/paid work entries. The asymmetry is documented in [`work_entries.md`](work_entries.md) |
| **Cancel** ([action_cancel:1081](../addons/hr_holidays/models/hr_leave.py#L1081) → wizard [hr_holidays_cancel_leave.py:14](../addons/hr_holidays/wizard/hr_holidays_cancel_leave.py#L14) → [_action_user_cancel:1251](../addons/hr_holidays/models/hr_leave.py#L1251)) | The employee themselves, on own future `validate1/validate/refuse` leave (reason asked in wizard) | `_force_cancel` posts the reason, notifies the responsibles who had approved, sets state `cancel` in sudo, archives the meeting, removes the resource leave ([:1258](../addons/hr_holidays/models/hr_leave.py#L1258)) | Work-entry bridge blocks cancel if a **validated** work entry links to the leave; defer module marks it `payslip_state='done'` and recomputes draft slips ([hr_payroll_holidays/hr_leave.py:68](../enterprise/hr_payroll_holidays/models/hr_leave.py#L68)) |
| **Delete** ([_unlink_if_correct_states:944](../addons/hr_holidays/models/hr_leave.py#L944)) | Employee: only `confirm/validate1/cancel` and not in the past; Officer: only `cancel/confirm`; Administrator: anything | `unlink()` first runs `_post_leave_cancel` in sudo (meeting + resource leave removed) ([:961](../addons/hr_holidays/models/hr_leave.py#L961)) | Defer module adds a hard stop: cannot delete a leave covered by a validated/paid payslip ([_unlink_if_no_payslip:210](../enterprise/hr_payroll_holidays/models/hr_leave.py#L210)) |
| **Back to Approval** ([action_back_to_approval:1114](../addons/hr_holidays/models/hr_leave.py#L1114)) | Officer, on `validate` | Back to `confirm`, activities rescheduled, meeting + resource leave removed ([_move_validate_leave_to_confirm:1118](../addons/hr_holidays/models/hr_leave.py#L1118)) | Defer module hides the button when the leave overlaps a validated/paid slip ([_compute_can_back_to_approve:24](../enterprise/hr_payroll_holidays/models/hr_leave.py#L24)) |

Additional edit guards: non-officers cannot modify a leave that already began unless they are its leave manager, and only managers touch cancelled leaves ([write:905](../addons/hr_holidays/models/hr_leave.py#L905)); **duplication is blocked** unless every copied leave is cancelled/refused ([copy_data:966](../addons/hr_holidays/models/hr_leave.py#L966)).

---

## Public Holidays & Mandatory Days

### Public holidays

A public holiday is a `resource.calendar.leaves` row with **no `resource_id`** (company-wide), optionally scoped to one working calendar. `hr_holidays` extends the model with the back-pointer `holiday_id` and `elligible_for_accrual_rate`, which defaults false ([resource.py:15](../addons/hr_holidays/models/resource.py#L15)). The latter means stock public holidays reduce worked-time accrual unless policy/custom code explicitly marks them eligible. Two same-scope public holidays may not overlap, but the guard is Python-only and concurrent creates can race ([:19](../addons/hr_holidays/models/resource.py#L19)).

The important flow is **retroactive re-evaluation**: create/write/unlink triggers `_reevaluate_leaves` over every non-refused/cancelled leave in the company/time window—without an applicability filter for the specific calendar ([:142](../addons/hr_holidays/models/resource.py#L142), [:56](../addons/hr_holidays/models/resource.py#L56)). Durations are recomputed, each leave is bounced through `confirm` and back, the employee may be notified, and an underfunded leave is **auto-refused** ([:88](../addons/hr_holidays/models/resource.py#L88)). Validated leaves get their resource rows recreated. Auto-refusal can indirectly deactivate linked validated work entries; public-holiday work entries themselves are not regenerated.

Timezone handling is narrower than it looks: only calendar-specific **create** explicitly converts the user's wall time to the calendar timezone. All Schedules create and all writes skip that conversion ([:124](../addons/hr_holidays/models/resource.py#L124)). See [`public_holidays_flow.md`](public_holidays_flow.md) before operating across timezones or paid periods.

By default a public holiday inside a request costs nothing because `include_public_holidays_in_duration=False`. When true, the employee leave consumes the holiday. That balance flag is independent from public-holiday/bypass work-entry type priority. A leave consisting only of excluded public holidays/non-working days validates to 0 days and is rejected. Toggling the flag does not reliably recompute all existing past/future-year leaves, so migration needs an explicit reevaluation.

### Mandatory days (the former "stress days")

`hr.leave.mandatory.day` is a tiny model: name, date range, company, optional working-calendar / departments / job positions scoping ([hr_leave_mandatory_day.py:7](../addons/hr_holidays/models/hr_leave_mandatory_day.py#L7)). Matching is done per employee in `_get_mandatory_days` (calendar + job + department parent-chain filters, [hr_employee.py:378](../addons/hr_holidays/models/hr_employee.py#L378)). Effect: `has_mandatory_day` is computed on the leave ([hr_leave.py:507](../addons/hr_holidays/models/hr_leave.py#L507)) and `_check_validity` raises *"You are not allowed to request time off on a Mandatory Day"* — **for non-officers only**; officers can still grant leave over mandatory days ([hr_leave.py:786](../addons/hr_holidays/models/hr_leave.py#L786)). Employees have read-only ACL on the model; only Administrators configure it. There is no separate "stress day" model in v19.

---

## Automatic Maintenance Around the Lifecycle

- **Two daily crons** ([ir_cron_data.xml](../addons/hr_holidays/data/ir_cron_data.xml)): the accrual updater (`_update_accrual`, see accrual doc) and **`_cancel_invalid_leaves`** ([hr_leave.py:1589](../addons/hr_holidays/models/hr_leave.py#L1589)) — scans leaves starting within 31 days whose type is fed by accrual allocations and force-cancels (chatter reason: "the accruated amount is insufficient") any that exceed the projected balance beyond the negative cap.
- **Contract/version changes** ([hr_version.py:26](../addons/hr_holidays/models/hr_version.py#L26)): creating or re-dating a version with a different working schedule splits overlapping leaves per version period, refusing/re-creating them (last split segment lands in `confirm`); a constraint blocks a single leave spanning versions with different calendars ([hr_leave.py:400](../addons/hr_holidays/models/hr_leave.py#L400)).
- **Employee/version calendar change:** the active v19 path is version create/write, which splits/recomputes leaves across schedule periods and can reject insufficient allocations ([hr_version.py:26](../addons/hr_holidays/models/hr_version.py#L26)). The apparent employee-write block is effectively disabled by its own `no_leave_resource_calendar_update` context. Public holidays are not employee-owned: applicability follows the date-effective calendar dynamically.
- **Manager/department change** ([hr_employee.py:252](../addons/hr_holidays/models/hr_employee.py#L252)): pending/future leaves and pending allocations get their `department_id`/`manager_id` refreshed; `leave_manager_id` follows `parent_id.user_id` when it was the default ([:159](../addons/hr_holidays/models/hr_employee.py#L159)).
- **Departure wizard** ([hr_departure_wizard.py:11](../addons/hr_holidays/wizard/hr_departure_wizard.py#L11)): leaves crossing the departure date are split at departure+1 (`_split_leaves`, [hr_leave.py:1126](../addons/hr_holidays/models/hr_leave.py#L1126)); post-departure approved leaves are force-cancelled, unapproved ones deleted; running allocations get `date_to` = departure date, future ones deleted.
- **Presence/UX side effects**: validated current leaves flip `is_absent`, the presence icon (`presence_holiday_absent/present`) and Discuss `im_status` to `leave_*` variants ([hr_employee.py:106](../addons/hr_holidays/models/hr_employee.py#L106), [res_users.py:19](../addons/hr_holidays/models/res_users.py#L19), [res_partner.py:19](../addons/hr_holidays/models/res_partner.py#L19)); the user display name gains "✈ Back on <date>" ([res_users.py:72](../addons/hr_holidays/models/res_users.py#L72)) where the return date is the **next working interval** after the leave, not `date_to` ([hr_employee.py:115](../addons/hr_holidays/models/hr_employee.py#L115)). Department kanbans count absences and to-approve requests ([hr_department.py:22](../addons/hr_holidays/models/hr_department.py#L22)).

Pure-UI files not affecting flow: [hr_employee_public.py](../addons/hr_holidays/models/hr_employee_public.py) (mirrors employee computes for the public model), [calendar_event.py](../addons/hr_holidays/models/calendar_event.py) (no video call on leave meetings), [mail_message_subtype.py](../addons/hr_holidays/models/mail_message_subtype.py) (auto-creates department-level subtypes), [mail_activity_type.py](../addons/hr_holidays/models/mail_activity_type.py) (protects the 4 activity types from unlink), [hr_holidays_summary_employees.py](../addons/hr_holidays/wizard/hr_holidays_summary_employees.py) (PDF summary report launcher).

---

## Enterprise: hr_payroll_holidays — the Defer Flow

Auto-installs with `hr_holidays_gantt + hr_work_entry_holidays + hr_payroll` ([__manifest__.py:9](../enterprise/hr_payroll_holidays/__manifest__.py#L9)). Everything pivots on one field:

| `payslip_state` ([hr_leave.py:16](../enterprise/hr_payroll_holidays/models/hr_leave.py#L16)) | Meaning |
|---|---|
| `normal` | To compute in next payslip (default) |
| `done` | Computed / defer resolved |
| `blocked` | "To defer" — the leave's period is already closed by a validated/paid slip |

### How a leave becomes blocked

On validation, before the base logic runs, `_action_validate` searches the employee's **regular** payslips: if a `validated`/`paid` slip overlaps the leave **and no draft slip also covers it**, `payslip_state='blocked'` ([hr_leave.py:31](../enterprise/hr_payroll_holidays/models/hr_leave.py#L31)). If a draft slip still covers the period the leave stays `normal` and `_recompute_payslips` simply refreshes the draft slips (empty ones recompute worked days, computed ones run `action_refresh_from_work_entries`, [:79](../enterprise/hr_payroll_holidays/models/hr_leave.py#L79)) — the same refresh runs after refuse and cancel too.

### What blocked means for payroll correctness

- **Excluded from work-entry generation twice**: the validated-leave hook `_cancel_work_entry_conflict` skips blocked leaves — so no leave work entry is created for the closed period — and instead schedules a **"Leave to Defer"** activity on the company's `deferred_time_off_manager` (fallback: admin) ([hr_leave.py:99](../enterprise/hr_payroll_holidays/models/hr_leave.py#L99), [res_company.py:10](../enterprise/hr_payroll_holidays/models/res_company.py#L10)); and `hr.version._get_resource_calendar_leaves` filters blocked leaves out of calendar-based generation ([hr_version.py:7](../enterprise/hr_payroll_holidays/models/hr_version.py#L7)). The already-paid attendance entries of the closed month stay untouched.
- **Draft slips overlapping a blocked leave get a danger-level error** "Employee has time off to defer" via `_get_errors_by_slip` ([hr_payslip.py:17](../enterprise/hr_payroll_holidays/models/hr_payslip.py#L17)); danger errors raise `error_count`, which blocks compute/confirm/pay in `hr_payroll`.
- **Guards on destructive paths** (all above in the refuse/cancel/delete table): delete blocked entirely when a validated slip covers the leave ([:210](../enterprise/hr_payroll_holidays/models/hr_leave.py#L210)); Back-to-Approval hidden ([:24](../enterprise/hr_payroll_holidays/models/hr_leave.py#L24)). Refuse remains unguarded (community asymmetry).
- `compute_sheet` on regular slips marks every non-blocked leave ending before the slip horizon as `done` ([hr_payslip.py:37](../enterprise/hr_payroll_holidays/models/hr_payslip.py#L37)) — the "green" state is bookkeeping, nothing reads it for money.

### Resolution paths

1. **Report to Next Month** ([action_report_to_next_month:115](../enterprise/hr_payroll_holidays/models/hr_leave.py#L115), server action "Defer to Next Month" [ir_actions_server_data.xml](../enterprise/hr_payroll_holidays/data/ir_actions_server_data.xml), also a button on the form when blocked+validated). Guards, in order: leave must be `blocked`; span ≤ 2 calendar months; the leave's own window must contain **non-leave** work entries (the days that were wrongly paid as attendance); next month must already have **draft** work entries. Then, walking next month's draft `WORK100` entries, it converts them to the leave's `work_entry_type_id` until the leave's hours are consumed — splitting an entry when only part of its duration is needed (half-day/hourly leaves, [:149](../enterprise/hr_payroll_holidays/models/hr_leave.py#L149)). Net effect: next month's slip pays one leave-typed block in place of attendance, compensating the closed month. Finishing feeds the activity, which flips `payslip_state='done'`.
2. **Defer to next Payslip / Mark as Reported** (server action or completing the activity): `activity_feedback(['...to_defer'])` just sets `payslip_state='done'` ([:110](../enterprise/hr_payroll_holidays/models/hr_leave.py#L110)) — HR handles the correction manually (e.g. an other-input line). Completing the activity from the chatter does the same via `mail.activity._action_done` ([mail_activity.py:10](../enterprise/hr_payroll_holidays/models/mail_activity.py#L10)).

### Dashboard warnings

Three configurable payroll-dashboard warnings ship as data ([hr_payroll_dashboard_warning_data.xml](../enterprise/hr_payroll_holidays/data/hr_payroll_dashboard_warning_data.xml)): **Time Off To Defer** (blocked+validated leaves, opens the dedicated action), **Time Off Without Joined Document** (pending requests of `support_document` types with no attachment), **Time Off Not Related To An Allocation** (excess days from `_get_consumed_leaves` for non-negative allocation types). The leave list/form also gains a `payslip_state` status widget and a "To Defer" filter ([hr_leave_views.xml:10](../enterprise/hr_payroll_holidays/views/hr_leave_views.xml#L10)).

Deeper payslip-side context (error gates, `_issues_dependencies` reactivity caveat) is in [`hr_payroll.md`](hr_payroll.md).

---

## Configuration & Settings

- **Time Off Approver** (employee form, HR Settings tab → `leave_manager_id`) — who approves `manager`-step requests; setting it auto-adds the user to the Responsible group, unsetting removes it if they manage nobody else ([hr_employee.py:220](../addons/hr_holidays/models/hr_employee.py#L220)).
- **Notify HR** (`responsible_ids` on the leave type) — who gets `hr`-step activities. Empty = nobody is notified (approval still possible for any officer).
- **Deferred Time Off Manager** (Payroll → Settings → `deferred_time_off_manager`, [res_config_settings.py:10](../enterprise/hr_payroll_holidays/models/res_config_settings.py#L10)) — the user who receives "Leave to Defer" activities; unset = admin gets them.
- Public holidays: Time Off → Configuration → Public Holidays (= `resource.calendar.leaves` without resource); Mandatory Days: same menu, Administrator-only.

---

## Dependencies

| Requires | Why |
|---|---|
| `hr` | employees, departments, versions (contracts) |
| `resource` | working calendars; `resource.calendar.leaves` is the materialized-absence table |
| `calendar` | optional meeting created per validated leave |
| `mail` | chatter, approval activities, notification subtypes |

| Works with | What it adds |
|---|---|
| `hr_work_entry_holidays` (community bridge) | `work_entry_type_id` on the type; validated leave → leave work entries; refuse/cancel regeneration — see [`work_entries.md`](work_entries.md) |
| `hr_payroll_holidays` (enterprise, auto) | the defer flow above |
| `hr_holidays_attendance` | overtime-deductible leave types (extra-hours balance checks on approve) |
| `hr_holidays_gantt`, `hr_work_entry_holidays_enterprise` | Gantt/UI layers only |
| `project_timesheet_holidays`, `planning_holidays`, etc. | generated analytic lines and Planning effects; full relation map in [`public_holidays_flow.md`](public_holidays_flow.md) |

---

## Gotchas & Non-Obvious Behavior

- **Refuse vs cancel asymmetry is the payroll-integrity hole**: user-cancel is blocked when validated work entries exist; **refuse is not** — it deactivates already-paid entries and regenerates attendance. Details in [`work_entries.md`](work_entries.md); nothing in `hr_payroll_holidays` closes this either.
- **The class docstring lies about visibility**: regular employees see only their *own* leaves (record rule [hr_holidays_security.xml:34](../addons/hr_holidays/security/hr_holidays_security.xml#L34)), not "all leaves" as the 15-year-old docstring claims.
- **`no_validation` still passes through `action_approve` in sudo at create** — approval-side hooks (work entries, defer detection) all run; there is no state where such a leave sits unapproved.
- **Pending requests reserve balance**: `confirm` and `validate1` leaves count as "virtually taken" in every balance computation ([hr_employee.py:459](../addons/hr_holidays/models/hr_employee.py#L459)) — a stack of unapproved requests can block new ones.
- **Overlap check is per-employee and hard**: `_check_date` raises on any overlap with a non-cancelled/refused leave unless the *other* type has `allow_request_on_top` ([hr_leave.py:735](../addons/hr_holidays/models/hr_leave.py#L735), [:276](../addons/hr_holidays/models/hr_leave.py#L276)).
- **Officers can resurrect cancelled leaves** (`cancel → confirm/validate/refuse` in the transition matrix, [hr_leave.py:1353](../addons/hr_holidays/models/hr_leave.py#L1353)) even though `_check_approval_update` blocks everyone else with "A cancelled leave cannot be modified".
- **Public-holiday edits rewrite history**: `_reevaluate_leaves` changes validated leave durations, may auto-refuse leave and indirectly deactivate validated work entries, while existing holiday work entries remain stale. Block paid/validated intervals server-side.
- **A daily cron force-cancels future leaves** whose accrual balance no longer covers them ([_cancel_invalid_leaves:1589](../addons/hr_holidays/models/hr_leave.py#L1589)) — approved leaves can disappear overnight after an allocation/plan change.
- **Stale selection→boolean leftovers**: `requires_allocation` became Boolean in v19, but string comparisons survive. `_search_virtual_remaining_leaves` is a **no-op filter** (`requires_allocation != "yes"` is always True → every type matches, [hr_leave_type.py:276](../addons/hr_holidays/models/hr_leave_type.py#L276)); domain leaves like `('requires_allocation','=','yes')` ([hr_employee.py:72](../addons/hr_holidays/models/hr_employee.py#L72)) still work only because the ORM coerces `'yes'`→True ([domains.py:1448](../odoo/orm/domains.py#L1448)).
- **Employee unlink rule on allocations grants nothing**: its domain requires `state='draft'`, a state allocations never have ([hr_holidays_security.xml:206](../addons/hr_holidays/security/hr_holidays_security.xml#L206)) — employees cannot delete even their own pending allocation requests (officers can, via ACL + officer rule).
- **Day-unit types round up**: `ceil(days)` on the computed duration ([hr_leave.py:627](../addons/hr_holidays/models/hr_leave.py#L627)) — a 4.5-working-day span costs 5 days, with an explanatory banner (`leave_type_increases_duration`, [:539](../addons/hr_holidays/models/hr_leave.py#L539)).
- **Defer flow dead code** in `hr_payroll_holidays`: `action_reset_confirm` overrides a base method that no longer exists ([hr_leave.py:74](../enterprise/hr_payroll_holidays/models/hr_leave.py#L74) — v19 uses `action_back_to_approval`), and the `write` guard keys on an `active` field `hr.leave` doesn't have ([:205](../enterprise/hr_payroll_holidays/models/hr_leave.py#L205)) — only the `unlink` guard is live. Likewise `_error_dependencies` targets a hook renamed to `_issues_dependencies`, so the to-defer error is **not recomputed reactively**; it refreshes on `_recompute_payslips`/`compute_sheet` (caveat detailed in [`hr_payroll.md`](hr_payroll.md)).
- **Report to Next Month needs next month generated first**: the action hard-fails if next month's draft work entries don't exist yet, if the leave spans >2 months, or if next month lacks enough WORK100 hours — in those cases the only path is manual deferral ([hr_leave.py:119-164](../enterprise/hr_payroll_holidays/models/hr_leave.py#L119)).
- **`blocked` only triggers against *regular* payslips** (`is_regular`, [hr_leave.py:35](../enterprise/hr_payroll_holidays/models/hr_leave.py#L35)) — credit notes/refund slips over the period don't cause deferral.
- **Installing payroll silently promotes every payroll user to Time Off Officer** ([hr_payroll_holidays_security.xml:5](../enterprise/hr_payroll_holidays/security/hr_payroll_holidays_security.xml#L5)) — they can approve/refuse anyone's leave.

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

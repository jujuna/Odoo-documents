# Timesheets — hr_timesheet, timesheet_grid, project_timesheet_holidays, timesheet_grid_holidays

> **Modules:** `hr_timesheet` ([`addons/hr_timesheet/`](../addons/hr_timesheet/)) | `timesheet_grid` ([`enterprise/timesheet_grid/`](../enterprise/timesheet_grid/)) | `project_timesheet_holidays` ([`addons/project_timesheet_holidays/`](../addons/project_timesheet_holidays/)) | `timesheet_grid_holidays` ([`enterprise/timesheet_grid_holidays/`](../enterprise/timesheet_grid_holidays/))
>
> **Updated by Codex and verified from source: 2026-07-12.** Written payroll-first: what a payroll/work-log bridge must know about timesheet data, its lifecycle, and its locks. Public-holiday relation map: [`public_holidays_flow.md`](public_holidays_flow.md).

## What It Does & Why It Exists

Employees log hours against projects and tasks. The record is not a dedicated model — it is an `account.analytic.line` with `project_id` set. `hr_timesheet` (community) adds the project/task/employee layer on top of analytic lines and costs the hours against the employee's hourly cost. `timesheet_grid` (enterprise) adds the grid UI, the timer, reminders, the merge wizard, and — critically for payroll — the **validation workflow**: an approver freezes lines with `validated = True`, and a per-employee rolling lock date prevents back-dated edits. `project_timesheet_holidays` auto-generates timesheet lines on an internal project when time off is validated and when public holidays exist, so project time reports stay complete. `timesheet_grid_holidays` is glue that keeps those leave-generated lines out of the enterprise overtime/reminder/timer machinery.

There is **no standard payroll bridge** — payslips never read timesheets ([payroll_wage_types.md](payroll_wage_types.md) §3, §7 row 7). Anything payroll does with this data is custom, which is why the anatomy and the locks below matter.

---

## 1. Anatomy — What Makes a Line a Timesheet

| Question | Answer | Source |
|---|---|---|
| Timesheet vs plain analytic line | `project_id` is set. Every report, rule, and guard filters `project_id != False` | [hr_timesheet.py:238-242](../addons/hr_timesheet/models/hr_timesheet.py#L238), [timesheets_analysis_report.py:69](../addons/hr_timesheet/report/timesheets_analysis_report.py#L69) |
| Task without project | Forbidden — `ValidationError` "cannot be created on a private task"; task given → `project_id` auto-filled from the task | [hr_timesheet.py:243-247](../addons/hr_timesheet/models/hr_timesheet.py#L243) |
| Time value | `unit_amount` (float, hours by default), on `date` (a plain Date — day-based, same shape as a v19 work entry). Max 999999 | [account_analytic_line.py:36-39](../enterprise/timesheet_grid/models/account_analytic_line.py#L36) |
| Company autofill | Forced to the task's company, else the project's company, in `create()` and `write()` | [hr_timesheet.py:249-250](../addons/hr_timesheet/models/hr_timesheet.py#L249), [hr_timesheet.py:361-366](../addons/hr_timesheet/models/hr_timesheet.py#L357) |
| UoM autofill | `product_uom_id` defaults to `company.project_time_mode_id` (Hours by default) — that is the **storage** unit of `unit_amount`. The company "Encoding Method" (`timesheet_encode_uom_id`, hours vs days) only changes widgets/display, not storage | [hr_timesheet.py:257-258](../addons/hr_timesheet/models/hr_timesheet.py#L257), [res_company.py:19-25](../addons/hr_timesheet/models/res_company.py#L19), [res_config_settings.py:20-35](../addons/hr_timesheet/models/res_config_settings.py#L20) |
| Analytic accounts | `account_id` (+ any other mandatory plan columns) copied from the project; missing mandatory plans on the project raise `ValidationError` | [hr_timesheet.py:416-432](../addons/hr_timesheet/models/hr_timesheet.py#L416) |
| Cost | `amount = -unit_amount × employee.hourly_cost`, converted to the account currency, recomputed by `_timesheet_postprocess_values` whenever `unit_amount`/`employee_id`/`account_id` change | [hr_timesheet.py:443-473](../addons/hr_timesheet/models/hr_timesheet.py#L443), [hr_timesheet.py:496-498](../addons/hr_timesheet/models/hr_timesheet.py#L496) |
| Empty description | `name` forced to `'/'` | [hr_timesheet.py:260-261](../addons/hr_timesheet/models/hr_timesheet.py#L260) |

### Employee resolution on create

`create()` guarantees every timesheet ends up with a valid `employee_id` ([hr_timesheet.py:212-355](../addons/hr_timesheet/models/hr_timesheet.py#L212)):

1. Explicit `employee_id` in vals (or `default_employee_id` context) — must be an **active** employee in one of `self.env.companies`, else `ValidationError` "must be created with an active employee in the selected companies". The employee's user becomes `user_id`.
2. No employee — falls back to `user_id` (default: current user) and searches that user's employees **in sudo** (works even though plain employees have no `hr.employee` ACL — [payroll_wage_types.md](payroll_wage_types.md) §8.3). Resolution succeeds if the user has exactly one employee across the allowed companies, or one in the vals' company; otherwise `ValidationError`.
3. On `write()`, setting an archived employee raises `UserError` ([hr_timesheet.py:373-376](../addons/hr_timesheet/models/hr_timesheet.py#L373)).

`department_id` and `manager_id` are stored relateds of the employee ([hr_timesheet.py:74-75](../addons/hr_timesheet/models/hr_timesheet.py#L74)); the analysis report groups by them.

### The project side

- Projects have `allow_timesheets` (default True) and must own an analytic account to allow it — creating a project auto-creates one ([project_project.py:100-151](../addons/hr_timesheet/models/project_project.py#L100)).
- Every company gets an auto-created **Internal** project with Training/Meeting tasks on company creation and at module install ([res_company.py:46-66](../addons/hr_timesheet/models/res_company.py#L46), [__init__.py:15](../addons/hr_timesheet/__init__.py#L15)).
- Projects and tasks with timesheets cannot be deleted (RedirectWarning to the lines) ([project_project.py:176-192](../addons/hr_timesheet/models/project_project.py#L176), [project_task.py:242-274](../addons/hr_timesheet/models/project_task.py#L242)); a task with timesheets cannot be made private ([project_task.py:60-64](../addons/hr_timesheet/models/project_task.py#L60)).
- Task rollups `effective_hours` / `total_hours_spent` / `remaining_hours` / `progress` are stored computes summing `timesheet_ids.unit_amount` ([project_task.py:83-143](../addons/hr_timesheet/models/project_task.py#L83)).

---

## 2. Creation Paths

| Path | Mechanism | Notes |
|---|---|---|
| List/form views | Standard ORM; `default_get` with `is_timesheet` context picks a "favorite" project — mode of the last 5 timesheets' projects, else the company internal project | [hr_timesheet.py:38-48](../addons/hr_timesheet/models/hr_timesheet.py#L38), context set in [hr_timesheet_views.xml:402](../addons/hr_timesheet/views/hr_timesheet_views.xml#L402) |
| Grid view (enterprise) | Cell edits call `grid_update_cell(domain, field, value)`: one draft line in the cell → add to it; several lines or a single **validated** line → `copy()` a new draft line; empty cell → `create()` (needs a project from grouping/context, else RedirectWarning) | [account_analytic_line.py:350-386](../enterprise/timesheet_grid/models/account_analytic_line.py#L350) |
| Timer (enterprise) | `timer.mixin` on the line + `timer.parent.mixin` on the task. Start creates a 0-hour line and a `timer.timer`; stop rounds elapsed minutes by ICP `timesheet_grid.timesheet_min_duration` / `timesheet_rounding` (both default 15) and adds to `unit_amount`, optionally merging into the day's last descriptionless line | [account_analytic_line.py:431-544](../enterprise/timesheet_grid/models/account_analytic_line.py#L431), [account_analytic_line.py:590-595](../enterprise/timesheet_grid/models/account_analytic_line.py#L590), [ir_config_parameter_data.xml](../enterprise/timesheet_grid/data/ir_config_parameter_data.xml) |
| Task timer | Start from the task creates the line ([project_task.py:151-159](../enterprise/timesheet_grid/models/project_task.py#L151)); stop opens a confirmation wizard to name/adjust or discard it ([hr_timesheet_stop_timer_confirmation_wizard.py](../enterprise/timesheet_grid/wizard/hr_timesheet_stop_timer_confirmation_wizard.py)). Timer hidden when encoding UoM is days ([project_project.py:17-29](../enterprise/timesheet_grid/models/project_project.py#L17)) |
| Calendar view | `timesheet_calendar` context: create silently **skips days the employee is not scheduled to work** (per `_get_valid_work_intervals`) and reports via bus notification | [hr_timesheet.py:220-237](../addons/hr_timesheet/models/hr_timesheet.py#L220), [hr_timesheet.py:339-353](../addons/hr_timesheet/models/hr_timesheet.py#L339) |
| Portal | Read-only. `/my/timesheets` lists lines matching `_timesheet_get_portal_domain` (follower/customer of portal-visible projects); the portal ACL is read-only and **inactive** until project sharing toggles it on | [portal.py:69-170](../addons/hr_timesheet/controllers/portal.py#L69), [ir.model.access.xml](../addons/hr_timesheet/security/ir.model.access.xml), [project_collaborator.py:10-21](../addons/hr_timesheet/models/project_collaborator.py#L10) |
| Import | XLSX template exposed when `is_timesheet` context is set | [hr_timesheet.py:546-553](../addons/hr_timesheet/models/hr_timesheet.py#L546) |
| Leave validation / public holidays | sudo-created lines on the company internal project — section 5 | |

---

## 3. Security Model

Three groups, defined in [hr_timesheet_security.xml](../addons/hr_timesheet/security/hr_timesheet_security.xml):

| Group | XML id | Scope |
|---|---|---|
| User: own timesheets only | `group_hr_timesheet_user` | Record rule: own lines (`user_id = user.id`) on visible projects ([L50](../addons/hr_timesheet/security/hr_timesheet_security.xml#L50)) |
| User: all timesheets (approver) | `group_hr_timesheet_approver` | All lines on visible projects ([L64](../addons/hr_timesheet/security/hr_timesheet_security.xml#L64)); may set others' `employee_id` ([hr_timesheet.py:56-60](../addons/hr_timesheet/models/hr_timesheet.py#L56)) |
| Administrator | `group_timesheet_manager` | All lines, no project-visibility filter ([L77](../addons/hr_timesheet/security/hr_timesheet_security.xml#L77)); implies `hr.group_hr_user` |

- `project.group_project_manager` is **implied approver** and shares the manager record rule ([L84](../addons/hr_timesheet/security/hr_timesheet_security.xml#L84), [L81](../addons/hr_timesheet/security/hr_timesheet_security.xml#L77)).
- Python-level ownership guard independent of rules: non-approvers writing someone else's line get `AccessError` ([hr_timesheet.py:200-206](../addons/hr_timesheet/models/hr_timesheet.py#L200)); same check on create in enterprise ([account_analytic_line.py:298-307](../enterprise/timesheet_grid/models/account_analytic_line.py#L298)).
- **Enterprise tightens the base rule**: `timesheet_grid` strips write/unlink from the community user rule and adds a separate write/unlink rule scoped to `validated = False` ([timesheet_security.xml:5-28](../enterprise/timesheet_grid/security/timesheet_security.xml#L5)). So a plain user cannot touch a validated line even via raw ORM.

---

## 4. Validation Flow (enterprise) — the Payroll Gate

### State

`validated` is a plain stored Boolean (`copy=False`, `readonly=True`) with a cosmetic `validated_status` selection `draft`/`validated` computed from it ([account_analytic_line.py:25-27](../enterprise/timesheet_grid/models/account_analytic_line.py#L25)). There is no workflow engine — the flag plus guards *is* the workflow. The analysis report exposes both ([timesheets_analysis_report.py:9-26](../enterprise/timesheet_grid/report/timesheets_analysis_report.py#L9)).

### Who may validate — approver resolution

`_get_domain_for_validation_timesheets()` ([account_analytic_line.py:651-678](../enterprise/timesheet_grid/models/account_analytic_line.py#L651)) is the single source of truth, used by the validate action and the reminder cron:

- **Manager group** (`group_timesheet_manager`): everything with `project_id != False`, including own lines.
- **Approver group**: never own lines (`user_id != uid`), and only employees where the approver is `employee.timesheet_manager_id`, OR the employee has no `timesheet_manager_id` set, OR the employee is in the approver's `subordinate_ids`, OR the approver is the `parent_id`'s user, OR the employee has neither manager nor timesheet approver.
- Validation additionally requires `date <= today` — **future-dated lines cannot be validated**.

`employee.timesheet_manager_id` ("Timesheet Approver") defaults to the employee's manager's user when that user is in the approver group ([hr_employee.py:36-53](../enterprise/timesheet_grid/models/hr_employee.py#L36)). Note: `project_id.user_id` grants the per-line `user_can_validate` UI flag ([account_analytic_line.py:127-138](../enterprise/timesheet_grid/models/account_analytic_line.py#L127)) but is **not** in the action's domain — see Gotchas.

### Validate

`action_validate_timesheet()` ([account_analytic_line.py:180-226](../enterprise/timesheet_grid/models/account_analytic_line.py#L180)), called from list/grid/kanban/pivot buttons and two `ir.actions.server` ([account_analytic_line_views.xml:369](../enterprise/timesheet_grid/views/account_analytic_line_views.xml#L369)):

1. Requires approver group, filters the selection through the domain above (in sudo).
2. Stops all running timers on the selected lines.
3. `sudo().write({'validated': True})`.
4. `_update_last_validated_timesheet_date()` pushes each employee's `last_validated_timesheet_date` forward to the max validated date ([account_analytic_line.py:140-156](../enterprise/timesheet_grid/models/account_analytic_line.py#L140)).
5. Kills any still-running timers on lines dated before the new lock date.

### What validation freezes

| Frozen | Mechanism |
|---|---|
| Edits by non-approvers | `_check_can_write` raises; writing the `validated` field itself is approver-only ([account_analytic_line.py:309-318](../enterprise/timesheet_grid/models/account_analytic_line.py#L309)) + record rule (§3) |
| Deletion by non-approvers | `@api.ondelete` ([account_analytic_line.py:388-394](../enterprise/timesheet_grid/models/account_analytic_line.py#L388)) |
| Timer use | Explicit `UserError` on start/stop/add-time ([account_analytic_line.py:462](../enterprise/timesheet_grid/models/account_analytic_line.py#L457)) |
| Project reassignment via task move | `_compute_project_id` skips validated lines ([account_analytic_line.py:113-116](../enterprise/timesheet_grid/models/account_analytic_line.py#L113)) |
| Grid cell edits | New draft line is copied instead of touching the validated one ([account_analytic_line.py:359-364](../enterprise/timesheet_grid/models/account_analytic_line.py#L350)) |
| Merging | Merge candidates filtered to `not validated` ([account_analytic_line.py:680-681](../enterprise/timesheet_grid/models/account_analytic_line.py#L680)) |
| UI editability | `readonly_timesheet` compute → `_is_readonly()` returns True when validated ([account_analytic_line.py:41-42](../enterprise/timesheet_grid/models/account_analytic_line.py#L41), [hr_timesheet.py:112-125](../addons/hr_timesheet/models/hr_timesheet.py#L112)) |

### The rolling period lock — `last_validated_timesheet_date`

Beyond the per-line freeze, validation locks the **period**. `check_if_allowed()` ([account_analytic_line.py:261-296](../enterprise/timesheet_grid/models/account_analytic_line.py#L261)) runs on create, write and delete:

- Applies to everyone except `group_timesheet_manager` and sudo.
- Blocks create/edit/delete of any timesheet dated `<= employee.last_validated_timesheet_date` — **including new draft lines in an already-validated period**, and including the employee's own lines.
- Exception 1: lines dated exactly **today** are always allowed.
- Exception 2: approvers acting on employees of their own team (same resolution logic as validation, inlined as an employee search at [L264-271](../enterprise/timesheet_grid/models/account_analytic_line.py#L264)) skip the date lock.
- Starting a timer on a line behind the lock silently creates a fresh line dated today instead ([account_analytic_line.py:465-467](../enterprise/timesheet_grid/models/account_analytic_line.py#L465)).

`last_validated_timesheet_date` lives on `hr.employee`, visible only to timesheet managers ([hr_employee.py:43](../enterprise/timesheet_grid/models/hr_employee.py#L43)); the grid frontend fetches it per user to grey out locked cells ([res_users.py:10-17](../enterprise/timesheet_grid/models/res_users.py#L10)).

### Un-validation

`action_invalidate_timesheet()` ([account_analytic_line.py:228-258](../enterprise/timesheet_grid/models/account_analytic_line.py#L228)) — same permission domain with `validated=True` — resets the flag and then **recomputes** each affected employee's lock date from scratch as `max(date)` of their remaining validated lines ([account_analytic_line.py:158-173](../enterprise/timesheet_grid/models/account_analytic_line.py#L158)). The lock date therefore moves backward correctly on reset.

### Company settings — there is no company lock date

Locking in this cluster is entirely the per-employee rolling date; there is no company-level "lock timesheets before X" field. Company-level config is limited to encoding UoM (§1), the two timer ICPs, and reminders (§6). (Invoice-side locking such as billed-at-validation lives in `sale_timesheet_enterprise`, outside this cluster.)

---

## 5. The Leave Bridge — project_timesheet_holidays

Auto-installed with `hr_timesheet + hr_holidays`. Purpose: when someone is off, project reporting still shows where the week went, on a neutral internal project.

### Configuration surface

- Per company: `internal_project_id` (from hr_timesheet) + `leave_timesheet_task_id` ("Time Off" task), auto-created for new companies ([res_company.py:14-29](../addons/project_timesheet_holidays/models/res_company.py#L14)) and backfilled at install ([__init__.py:7-46](../addons/project_timesheet_holidays/__init__.py#L7)). Exposed in Settings ([res_config_settings.py:10-19](../addons/project_timesheet_holidays/models/res_config_settings.py#L10)).
- No per-leave-type project/task in v19 — the settings help text still claims "You can specify another project on each time off type individually", but no `hr.leave.type` extension exists in this module; the only per-type switch is `time_type = 'other'` (Worked Time, [hr_leave_type.py:103](../addons/hr_holidays/models/hr_leave_type.py#L103)) which **skips generation entirely** ([hr_leave.py:29](../addons/project_timesheet_holidays/models/hr_leave.py#L17)).

### Personal leave flow (`hr.leave`)

`_validate_leave_request()` → `_generate_timesheets()` ([hr_leave.py:13-66](../addons/project_timesheet_holidays/models/hr_leave.py#L13)):

1. Per leave, work hours are split per day via `employee._list_work_time_per_day()` (the leave's own `resource.calendar.leaves` record is excluded so the days don't count as already-off). Flexible-hours calendars get special handling: hour-range requests use `request_hour_to - request_hour_from`, half-days use `hours_per_day / 2`, single days use `hours_per_day`.
2. One line per day: name "Time Off (i/n)", internal project + Time Off task, `holiday_id` set, employee/user/company from the leave ([hr_leave.py:68-81](../addons/project_timesheet_holidays/models/hr_leave.py#L68)).
3. Pre-existing lines of the same leaves are unlinked first (idempotent regeneration), then all lines are **created in sudo** — which bypasses every guard in §4, including the period lock.

Deletion mirrors the leave lifecycle: refusal ([hr_leave.py:99-106](../addons/project_timesheet_holidays/models/hr_leave.py#L99)), user cancellation ([L108](../addons/project_timesheet_holidays/models/hr_leave.py#L108)), force-cancel ([L116](../addons/project_timesheet_holidays/models/hr_leave.py#L116)) and shrink-to-zero-days writes ([L123](../addons/project_timesheet_holidays/models/hr_leave.py#L123)) all sudo-unlink the lines (after clearing `holiday_id` to dodge the delete guard). Refusal/cancel then re-generate any public-holiday lines the leave had suppressed ([L83-97](../addons/project_timesheet_holidays/models/hr_leave.py#L83)).

### Public holidays (`resource.calendar.leaves` with no resource)

- Creating a global leave generates one line per working day for **every employee** on the matching calendar(s) in the allowed companies, skipping employees with an approved personal leave covering that day; `global_leave_id` links the line ([resource_calendar_leaves.py:116-182](../addons/project_timesheet_holidays/models/resource_calendar_leaves.py#L116), [create:251](../addons/project_timesheet_holidays/models/resource_calendar_leaves.py#L251)).
- Rescheduling a global leave deletes and regenerates its lines; deleting one cascades its lines (`ondelete='cascade'` on `global_leave_id`) and regenerates the personal-leave lines it had displaced ([write:257-275](../addons/project_timesheet_holidays/models/resource_calendar_leaves.py#L257), [ondelete:277-285](../addons/project_timesheet_holidays/models/resource_calendar_leaves.py#L277)).
- Employee lifecycle keeps them consistent: new/unarchived employees get lines for future public holidays; archiving deletes future ones; changing `resource_calendar_id` rebuilds them ([hr_employee.py:11-73](../addons/project_timesheet_holidays/models/hr_employee.py#L11)).

### Guards on generated lines

- Manual deletion blocked: global-leave lines → hard `UserError`; leave lines → RedirectWarning to the leave ([account_analytic.py:31-40](../addons/project_timesheet_holidays/models/account_analytic.py#L31)).
- Manual **modification** of `holiday_id` lines blocked for everyone except sudo ([account_analytic.py:42-45](../addons/project_timesheet_holidays/models/account_analytic.py#L42)). Global-leave lines have no write guard (only delete).
- Manual timesheets on a time-off task blocked ([account_analytic.py:47-50](../addons/project_timesheet_holidays/models/account_analytic.py#L47)); a task is `is_timeoff_task` when it is the company's leave task or carries any leave-linked line ([project_task.py:24-27](../addons/project_timesheet_holidays/models/project_task.py#L24)).
- Favorite-project default excludes leave lines ([account_analytic.py:52-57](../addons/project_timesheet_holidays/models/account_analytic.py#L52)); the timeoff task is filtered out of the task dropdown ([account_analytic.py:13](../addons/project_timesheet_holidays/models/account_analytic.py#L13)).
- Interaction with validated periods: generation and deletion run in sudo, so **the leave bridge writes and deletes straight through the validation lock**. Standard validation does not exclude `holiday_id/global_leave_id`; if such a line is validated and later regenerated, sudo deletion does not recompute `employee.last_validated_timesheet_date`, so ordinary earlier timesheets can remain falsely locked.

### timesheet_grid_holidays (glue, auto-installed with both parents)

- Overtime avatar/grid totals exclude leave lines (`holiday_id IS NULL AND global_leave_id IS NULL` in the worked-hours SQL) ([hr_employee.py:10-17](../enterprise/timesheet_grid_holidays/models/hr_employee.py#L10)) — this is the module's stated purpose ("prevents taking time offs into account when computing employee overtime", [__manifest__.py](../enterprise/timesheet_grid_holidays/__manifest__.py)).
- Reminder cron ignores leave lines when deciding who timesheeted ([res_company.py:10-15](../enterprise/timesheet_grid_holidays/models/res_company.py#L10)).
- Grid cell updates never target leave lines (`holiday_id = False` injected into the cell domain) ([analytic.py:24-30](../enterprise/timesheet_grid_holidays/models/analytic.py#L24)); merge and timer refuse leave lines/timeoff tasks ([analytic.py:15-35](../enterprise/timesheet_grid_holidays/models/analytic.py#L15)).

---

## 6. Reminders & Crons (enterprise)

Two daily crons on `res.company` ([ir_cron_data.xml](../enterprise/timesheet_grid/data/ir_cron_data.xml)), each self-scheduling via a company `..._nextdate` field recomputed from delay + weekly/monthly interval ([res_company.py:19-92](../enterprise/timesheet_grid/models/res_company.py#L19)):

| Cron | Recipients | Trigger condition |
|---|---|---|
| `_cron_timesheet_reminder_employee` | Users with ≥1 timesheet in the last 3 months whose timesheeted hours < calendar working hours for the elapsed week/month | [res_company.py:103-147](../enterprise/timesheet_grid/models/res_company.py#L103) |
| `_cron_timesheet_reminder` | Every approver-group user who has lines pending validation (per `_get_domain_for_validation_timesheets`) where they are the `timesheet_manager_id` | [res_company.py:150-201](../enterprise/timesheet_grid/models/res_company.py#L150) |

Settings toggles/delays are related fields on the company ([res_config_settings.py:9-19](../enterprise/timesheet_grid/models/res_config_settings.py#L9)). With `timesheet_grid_holidays`, leave lines don't count toward "has timesheeted".

## 7. Merge Wizard (enterprise)

`hr_timesheet.merge.wizard` ([hr_timesheet_merge_wizard.py](../enterprise/timesheet_grid/wizard/hr_timesheet_merge_wizard.py)) — list-view action on selected lines. Eligible lines: `project_id` set, not validated, no running timer ([default_get:28-46](../enterprise/timesheet_grid/wizard/hr_timesheet_merge_wizard.py#L28)). It concatenates distinct descriptions, sums `unit_amount`, takes date/project/task/employee from the first line, then **creates one new line and unlinks the originals** ([action_merge:65-80](../enterprise/timesheet_grid/wizard/hr_timesheet_merge_wizard.py#L65)) — original IDs do not survive a merge. Leave lines refuse merging ([timesheet_grid_holidays/analytic.py:15-22](../enterprise/timesheet_grid_holidays/models/analytic.py#L15)).

---

## 8. Hooks a Payroll Bridge Would Use

Context: [payroll_wage_types.md](payroll_wage_types.md) §7 row 7 (no standard bridge; salary rule may query timesheets directly) and §9.7 (validate → compute flow, worked examples). What to read:

| Need | Read | Why |
|---|---|---|
| "Is a timesheet" | `project_id != False` | The only discriminator (§1) |
| Pay gate | `validated = True` | The approval state; `validated_status` is derived UI sugar ([account_analytic_line.py:25](../enterprise/timesheet_grid/models/account_analytic_line.py#L25)) |
| Period | `date` (Date) + `employee_id` | Day-based, same shape as a v19 work entry |
| Hours | `unit_amount` | Stored in `company.project_time_mode_id` units — Hours unless someone changed it; do **not** confuse with the encoding UoM (§1) |
| Exclude leave-generated time | `holiday_id = False AND global_leave_id = False` | Otherwise every validated vacation double-pays (leave already pays through work entries); partial index exists on exactly this pattern ([account_analytic.py:15](../addons/project_timesheet_holidays/models/account_analytic.py#L15)). Filtering `task_id.is_timeoff_task = False` is a weaker substitute (non-stored compute) |
| Period-close coordination | `employee.sudo().last_validated_timesheet_date` | The rolling lock the UI enforces; a bridge can require it ≥ payslip `date_to` before computing |
| Rate | not here | `amount` is the negative analytic **cost** (hourly_cost), not a pay rate — keep pay rates on the version/salary rule |

Sanctioned rule pattern (precedent: UAE EOS rule, see payroll_wage_types.md §7 row 7):

```python
result = payslip.env['account.analytic.line'].sudo().search_read([
    ('employee_id', '=', employee.id),
    ('project_id', '!=', False),
    ('validated', '=', True),
    ('holiday_id', '=', False),
    ('global_leave_id', '=', False),
    ('date', '>=', payslip.date_from), ('date', '<=', payslip.date_to),
], aggregates=...)  # or _read_group on unit_amount:sum
```

Boundary rule from §9.7 applies: lines validated after compute are missed by a date-window rule — enforce validate-then-compute, or claim lines onto the payslip. Note `validated` alone is not immutability: un-validation (§4) and the sudo leave bridge (§5) can still change history after a payslip computed — a defensive bridge stores the summed amount (or line IDs) on the slip at compute time.

---

## Configuration & Settings

- **Encoding Method** (Settings → Timesheets): swaps `company.timesheet_encode_uom_id` between Hours and Days ([res_config_settings.py:20-35](../addons/hr_timesheet/models/res_config_settings.py#L20)). Day mode changes widgets (`float_toggle` vs `float_time`, [hr_timesheet_data.xml](../addons/hr_timesheet/data/hr_timesheet_data.xml)) and disables the timer ([project_project.py:17-29](../enterprise/timesheet_grid/models/project_project.py#L17)); storage stays in `project_time_mode_id` units.
- **Project Time Unit** (`project_time_mode_id`): the storage/display unit for task hours and `product_uom_id` default. Changing it re-scales the meaning of every stored `unit_amount` — leave it at Hours.
- **Time Off** (Settings): installs `project_timesheet_holidays`; its own settings are the internal project + Time Off task per company (§5).
- **Timer rounding**: ICPs `timesheet_grid.timesheet_min_duration` and `timesheet_grid.timesheet_rounding` (minutes, both default 15) ([res_config_settings.py:20-21](../enterprise/timesheet_grid/models/res_config_settings.py#L20)).
- **Reminders**: per-company employee/approver reminder toggles, delay days, weekly/monthly (§6).

## Dependencies

| Module | Depends on | Notes |
|---|---|---|
| `hr_timesheet` | `hr`, `hr_hourly_cost`, `analytic`, `project`, `uom` | [__manifest__.py:22](../addons/hr_timesheet/__manifest__.py#L22) |
| `timesheet_grid` | `project_enterprise`, `web_grid`, `hr_timesheet`, `timer`, `hr_org_chart` | auto-installs with web_grid+hr_timesheet; [__manifest__.py:11](../enterprise/timesheet_grid/__manifest__.py#L11) |
| `project_timesheet_holidays` | `hr_timesheet`, `hr_holidays` | auto-install; [__manifest__.py:16](../addons/project_timesheet_holidays/__manifest__.py#L16) |
| `timesheet_grid_holidays` | `project_timesheet_holidays`, `timesheet_grid` | auto-install; [__manifest__.py:14](../enterprise/timesheet_grid_holidays/__manifest__.py#L14) |

---

## Gotchas & Non-Obvious Behavior

- **The leave bridge punches through validation.** Leave/public-holiday lines are created, rewritten and deleted in sudo ([hr_leave.py:61-66](../addons/project_timesheet_holidays/models/hr_leave.py#L61)), which bypasses the locks. Standard validation can validate these generated lines, then regeneration deletes them without recalculating the employee's last validated date. A payroll bridge must exclude them from payroll **and validation**, plus repair existing validated lines/cut-offs.
- **`validated` is reversible and history is soft.** Un-validation is one click for the right approver and recomputes the lock date backwards; a payroll consumer must not treat `validated = True` at time T as permanent (§8).
- **"Today" pierces the period lock.** `check_if_allowed` always allows lines dated exactly today, even when today ≤ `last_validated_timesheet_date` ([account_analytic_line.py:279-280](../enterprise/timesheet_grid/models/account_analytic_line.py#L279)). An employee can add hours *inside* an already-validated period as long as they do it on that same day.
- **Validation lock ≠ line lock.** New *draft* lines dated before the lock are blocked too — the lock covers the whole period, not just validated records. Conversely, drafts dated after the lock stay editable indefinitely.
- **`user_can_validate` lies to approvers about their own lines.** The compute returns True for an approver's own timesheets (and for project managers via `project_id.user_id`) ([account_analytic_line.py:127-138](../enterprise/timesheet_grid/models/account_analytic_line.py#L127)), but `action_validate_timesheet`'s domain excludes `user_id = uid` and doesn't know `project_id.user_id` — the button shows, then the action answers "not part of your team". Only `group_timesheet_manager` can validate own lines.
- **Future lines cannot be validated** (`date <= today` in the validation domain) — relevant for pre-filled schedules.
- **Grid edits on validated cells silently fork.** Adding time in a cell whose only line is validated `copy()`s a new draft line ([account_analytic_line.py:359-364](../enterprise/timesheet_grid/models/account_analytic_line.py#L350)) — the cell total mixes one validated and one draft line afterwards.
- **Merging destroys line IDs** (new record, originals unlinked). Any external reference (e.g. a payslip claim table) must handle this before validation, or only reference validated lines (which can't be merged).
- **`amount` is a cost, and it's recomputed.** `-unit_amount × hourly_cost` refreshes on every unit_amount/employee/account write, in sudo, even on validated lines when an approver edits — do not read `amount` as remuneration.
- **Employee resolution can hard-fail imports.** Batch creates without `employee_id` fail with `ValidationError` when the user has several employees across selected companies and no `company_id` in vals disambiguates (§1). Archived employees are always rejected.
- **UoM trap.** Day-encoding changes only the widget; `unit_amount` stays in hours (via `project_time_mode_id`). Summation code must not multiply by encoding factors — `_compute_total_timesheet_time` shows the correct conversion dance ([project_project.py:110-131](../addons/hr_timesheet/models/project_project.py#L110)).
- **Time-off types with `time_type = 'other'` produce no timesheets** — and the settings help text about per-leave-type projects is stale in v19 (§5).
- **Public-holiday lines have no write guard.** Deleting them is blocked, but editing hours on a `global_leave_id` line is not (only `holiday_id` lines are write-protected) ([account_analytic.py:42-45](../addons/project_timesheet_holidays/models/account_analytic.py#L42)).
- **Uninstalling `timesheet_grid` drags down `hr_timesheet` and `sale_timesheet`** ([ir_module_module.py:9-16](../enterprise/timesheet_grid/models/ir_module_module.py#L9)) and deactivates the Timesheets root menu ([__init__.py:16-28](../enterprise/timesheet_grid/__init__.py#L16)).
- **Approvers lose the "My Timesheets" root menu item** — it's blacklisted for them because they get the fuller Timesheets submenu ([ir_ui_menu.py:9-13](../addons/hr_timesheet/models/ir_ui_menu.py#L9)).
- **Employees with timesheets can't be deleted, only archived** — delete wizard forces termination flow for non-approvers ([hr_employee.py:52-57](../addons/hr_timesheet/models/hr_employee.py#L52), [hr_employee_delete_wizard.py](../addons/hr_timesheet/wizard/hr_employee_delete_wizard.py)).
- **Calendar-view creates silently drop non-working days** — batch creation from the calendar skips days outside the employee's work intervals with only a bus toast ([hr_timesheet.py:220-237](../addons/hr_timesheet/models/hr_timesheet.py#L220)).

## Files not covered (pure UI / infra)

`account_analytic_line_calendar_employee.py` (calendar-view employee filter prefs), `ir_http.py` + `controllers/project.py` (UoM info into session for JS widgets), `uom_uom.py` (widget name per UoM), `hr_employee_public.py` (both modules — related field mirrors), `project_update.py` (snapshot of allocated/timesheeted time in project updates), `hr_timesheet/report/project_report.py` (task-analysis SQL columns), `timesheet_grid/models/timesheet_grid_mixin.py` + grid parts of `project_project.py`/`project_task.py` (planned-vs-worked widget data, gantt progress bars), all `static/src` assets, `data/mail_template_data.xml` (reminder mail bodies), `data/web_tour_data.xml`.

## Adjacent modules (other clusters, not documented here)

`hr_timesheet_attendance` (auto-installed report comparing timesheets vs attendances, [manifest](../addons/hr_timesheet_attendance/__manifest__.py)); `sale_timesheet`, `sale_timesheet_enterprise`(+`_holidays`), `sale_timesheet_margin`, `sale_subscription_timesheet` (billing side, incl. billed-at-validation policy); `helpdesk_timesheet`, `helpdesk_sale_timesheet`; `project_timesheet_forecast`(+`_sale`); `website_timesheet`; `spreadsheet_dashboard_*_timesheet`.

## Related Docs

- [`INDEX.md`](INDEX.md)
- [`payroll_wage_types.md`](payroll_wage_types.md) — §7 row 7 + §9.7: how a salary rule consumes these lines; §8.3 verified constraints kept consistent here
- [`work_entries.md`](work_entries.md) — the day-based work-entry shape a bridge would map to
- [`hr_payroll.md`](hr_payroll.md) — payslip engine that would consume the bridge output
- [`hr_holidays_time_off_units.md`](hr_holidays_time_off_units.md) / [`hr_holidays_accrual_plans.md`](hr_holidays_accrual_plans.md) — leave side of the §5 bridge
- [`resource_calendars.md`](resource_calendars.md) — work intervals used by leave-line generation and reminder math
- [`attendance_work_entry.md`](attendance_work_entry.md) — the attendance alternative for actual-hours pay
- [`hr_employee_versions.md`](hr_employee_versions.md) — where pay rates actually live
- [`analytic_accounting.md`](analytic_accounting.md) — the base `account.analytic.line` model timesheets extend

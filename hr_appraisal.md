# HR Appraisal

> **Module:** `hr_appraisal` (+ `hr_appraisal_skills`, `hr_appraisal_survey`) | **Path:** [`enterprise/hr_appraisal/`](../enterprise/hr_appraisal/)
> **Enterprise only** — all three modules ship `license: OEEL-1` and live under `enterprise/`, confirmed in each `__manifest__.py`. Not available on Community.

## What It Does & Why It Exists

Performance review workflow: one `hr.appraisal` record per review cycle per employee, carrying a self-assessment (employee) and a manager assessment side by side, a final rating, a meeting-scheduling shortcut, and optional linked development goals. Used by managers/HR to run periodic reviews and by employees to submit self-feedback. `hr_appraisal_skills` bolts a skills-tracking tab onto the same record so a review cycle can also update the employee's official skill levels. `hr_appraisal_survey` adds an optional 360°-feedback survey layer (colleagues answering a questionnaire about the employee) — separate from, and not required by, the core flow.

---

## The Big Picture — How It Works

```
Draft (1_new) --Confirm--> Ongoing (2_pending) --Mark as Done--> Done (3_done)
   |                            |    |                                |
   auto-fills dept/job/         |    |                                |
   manager from employee_id     |    +-- both sides write feedback    +-- rating locked in,
                                |        in parallel, share when       skills tab opens to
                                |        ready, manager schedules      everyone, next-cycle
                                |        meeting                       date computed
                                +-- confirm email sent to employee+managers
```

Two independent ways a record reaches Draft/Ongoing:
1. **Manual**: someone opens Appraisals → New, or clicks **Request Appraisal** on an employee's form ([hr_employee.py:36-43](../enterprise/hr_appraisal/models/hr_employee.py#L36-L43)). Starts in Draft (`1_new`). `manager_ids` defaults to the acting user, then an onchange resets it to `employee_id.parent_id` once an employee is picked ([hr_appraisal.py:219-228](../enterprise/hr_appraisal/models/hr_appraisal.py#L219-L228)).
2. **Automatic** — a daily cron (`_run_employee_appraisal_plans`) creates records **directly in Ongoing**, per employee, when that employee's `next_appraisal_date` has arrived ([res_company.py:67-79](../enterprise/hr_appraisal/models/res_company.py#L67-L79)).

Once Ongoing, employee and manager can both write their feedback **at the same time** — nothing in the state machine forces one to go first. What's gated is *visibility*: the manager only sees the employee's real text once the employee flips **Shared to Appraisers** on (a toggle, not a submit button); same in reverse for **Shared to Employee** ([hr_appraisal_views.xml:106-119,132-144](../enterprise/hr_appraisal/views/hr_appraisal_views.xml#L106-L144)). Until shared, the other side sees a blurred template preview instead of the real text.

A manager (not the employee) can also schedule a meeting straight from the record — this opens the standard Calendar app pre-filled with both parties as attendees, it does not create the event by itself ([hr_appraisal.py:468-480](../enterprise/hr_appraisal/models/hr_appraisal.py#L468-L480)).

**Mark as Done** requires a `assessment_note` (Final Rating) — without one, the button just shows a dismissible warning banner and does nothing (not a hard block) ([hr_appraisal.py:485-499](../enterprise/hr_appraisal/models/hr_appraisal.py#L485-L499)). Reaching Done force-publishes both feedback sides and computes/announces the next automatic appraisal date.

### Key Decision Points
- **Manual vs. automatic creation:** manual = one person picks one employee, starts in Draft, no email until Confirmed. Automatic (cron) or bulk campaign wizard = starts directly in Ongoing, confirm email fires immediately.
- **Sharing feedback:** a toggle field per side, not a workflow gate — either party can keep typing after sharing; sharing only affects what the *other* person can see.
- **Final rating:** a configurable Many2one (`hr.appraisal.note`), not a hardcoded list — Settings can add/remove/reorder tiers.

---

## When to Use It (and When Not To)

### This module is for:
- Periodic 1:1 performance reviews with a written record, a rating, and an optional meeting log.
- Organizations that want employee self-assessment and manager assessment to coexist on one record before a rating is set.
- Tracking a small number of ongoing development goals per employee alongside reviews.

### Use something else when:
- You need every employee's review cycle to start on **one shared calendar date, automatically, every year** — the built-in automatic plan is per-employee (based on hire/last-review date + a month interval), not calendar-anchored. See Gotchas.
- You need **colleague/peer 360° input** as a first-class, required part of every cycle — `hr_appraisal_survey` exists but is a bolt-on survey, not integrated into the state machine or the Feedback tab.
- You need a real exportable PDF appraisal document — there's no QWeb/report engine here, only a browser print stylesheet (see Gotchas).

---

## Real-World Scenarios

### Scenario 1: HR runs an annual review cycle for the whole company
**Situation:** HR wants every employee reviewed around the same time each year, not staggered by hire date.
**What they do:** Appraisals → **Launch Campaign**, mode "By Company", pick a manager rule and one shared `appraisal_date`. Odoo creates one `hr.appraisal` per employee directly in Ongoing, all sharing that date ([hr_appraisal_campaign_wizard.py:90-131](../enterprise/hr_appraisal/wizard/hr_appraisal_campaign_wizard.py#L90-L131)).
**What happens:** All confirm emails and "Appraisal to fill" activities fire the same day. This has to be triggered by a person each cycle — it is not a recurring schedule by itself.

### Scenario 2: Standard per-employee automatic cycle
**Situation:** A new hire should get their first review some months after joining, then annually after that, with no one having to remember.
**What they do:** Nothing, once Settings → Appraisal → Appraisals Automation is on (default). The employee's `next_appraisal_date` is computed from hire date + `duration_after_recruitment` (default 6 months), then + `duration_first_appraisal` for the second review, then + `duration_next_appraisal` (default 12 months) for every one after ([res_company.py:20-22](../enterprise/hr_appraisal/models/res_company.py#L20-L22), [hr_employee.py:136-154](../enterprise/hr_appraisal/models/hr_employee.py#L136-L154)).
**What happens:** A daily cron creates each employee's next appraisal on their own schedule — two employees hired on different dates get reviewed on different dates, permanently staggered.

### Scenario 3: Manager updates an employee's skill levels during a review
**Situation:** During the review, the manager decides the employee's level in a skill has changed.
**What they do:** Opens the Skills tab (only visible once Ongoing, and only visible to the manager while Ongoing — see Gotchas), edits the level, optionally types a reason in the `justification` column.
**What happens:** The change stays draft-only on the appraisal until **Mark as Done**, at which point it's written back to the employee's real skill record ([hr_appraisal.py (skills module):61-129](../enterprise/hr_appraisal_skills/models/hr_appraisal.py#L61-L129)), and shows up afterward in the Skills Evolution report.

---

## How Things Work Under the Hood

### Core Logic
- **`_run_employee_appraisal_plans()`** ([res_company.py:67-79](../enterprise/hr_appraisal/models/res_company.py#L67-L79)) — the daily cron; finds every employee whose `next_appraisal_date` has passed and creates their next appraisal directly in Ongoing.
- **`write()`** state-transition side effects ([hr_appraisal.py:350-388](../enterprise/hr_appraisal/models/hr_appraisal.py#L350-L388)) — moving to Ongoing resets both publish flags and re-sends the confirm email; moving to Done force-publishes both sides and posts the next-appraisal-date notice.
- **`read()` override** ([hr_appraisal.py:452-466](../enterprise/hr_appraisal/models/hr_appraisal.py#L452-L466)) — when the reading user is the appraisal's own employee, `note` (Private Note) and `assessment_note` (Final Rating) are scrubbed from the payload server-side, regardless of view. This is real field-level security, not just a hidden tab.
- **`action_calendar_event()`** ([hr_appraisal.py:468-480](../enterprise/hr_appraisal/models/hr_appraisal.py#L468-L480)) — opens the standard Calendar app pre-filled with employee + managers + acting user as attendees; no `calendar.event` exists until the user actually saves one.

### Important Fields
- `state` (`1_new`/`2_pending`/`3_done`) — drives almost every `readonly`/`invisible` condition in the form.
- `employee_feedback_published` / `manager_feedback_published` — toggles, not approvals. Default `True`; either side can turn their own off to keep working privately, or a manager can force-publish the employee's (logged to chatter) via a confirm dialog ([boolean_confirm.js:34-48](../enterprise/hr_appraisal/static/src/fields/boolean_confirm.js#L34-L48)).
- `assessment_note` (Final Rating) — Many2one to `hr.appraisal.note`, configurable, never visible or readable by the employee themself.
- `next_appraisal_date` — related to the employee, editable directly on a Done appraisal; lets a manager override the computed next-cycle date for that one employee.

---

## Configuration & Settings

- **Appraisals Automation** (Settings → Employees → Appraisal, `appraisal_plan`, default on) — master switch for the daily automatic-creation cron. Off = nothing is ever auto-created; every appraisal needs a manual New or a Launch Campaign.
- **Appraisals Plans** (`duration_after_recruitment` / `duration_first_appraisal` / `duration_next_appraisal`, months, defaults 6/6/12) — controls the per-employee stagger described above. There is no setting anywhere that turns this into "same calendar date for everyone" ([res_config_settings.py:13-15](../enterprise/hr_appraisal/models/res_config_settings.py#L13-L15)).
- **Evaluation Scale** (Appraisals → Configuration → Evaluation Scale, `hr.appraisal.note`, Administrator-only) — add/remove/reorder the Final Rating options. Shipped defaults: Needs improvement, Meets expectations, Exceeds expectations, Strongly Exceed Expectations ([res_company.py:29-45](../enterprise/hr_appraisal/models/res_company.py#L29-L45)) — note has no color/weight field, just display order.

---

## Dependencies

| Requires | Why |
|---|---|
| `hr`, `calendar`, `mail`, `hr_gantt` (Enterprise) | employee/department data, meeting scheduling, activities/notifications, the Gantt reporting view |

| Works With (optional) | What It Adds |
|---|---|
| `hr_appraisal_skills` | Skills tab on the appraisal + org-wide Skills Evolution report |
| `hr_appraisal_survey` | Optional 360°-feedback survey per appraisal (Community `survey` engine underneath) |

---

## Gotchas & Non-Obvious Behavior

- **No org-wide fixed-date automatic cycle.** The automatic plan is strictly per-employee and interval-based (hire date / last review + N months). "Everyone gets reviewed starting July 1st every year, automatically" is not configurable — the closest built-in equivalent is the **Launch Campaign** bulk wizard, which needs a human to trigger it each cycle and does support one shared date across many employees ([hr_appraisal_campaign_wizard.py:35](../enterprise/hr_appraisal/wizard/hr_appraisal_campaign_wizard.py#L35)).
- **The confirm email doesn't fire on manual Draft creation.** `send_appraisal()` only runs when a record is created directly in Ongoing (cron/campaign) or when `write()` moves it Draft→Ongoing via the **Confirm** button ([hr_appraisal.py:350,367-370](../enterprise/hr_appraisal/models/hr_appraisal.py#L367-L370)). A manually created Draft that never gets confirmed never notifies anyone.
- **The Skills tab is not gated on "employee submitted feedback."** It's gated purely on `state` + role: hidden entirely in Draft; hidden **from the employee themself** during Ongoing (only the manager/officer sees it then); visible to everyone once Done ([hr_skills_views.xml:12](../enterprise/hr_appraisal_skills/views/hr_skills_views.xml#L12)). It's also `readonly` unless `state == '2_pending' and is_manager` ([hr_skills_views.xml:17](../enterprise/hr_appraisal_skills/views/hr_skills_views.xml#L17)) — **the employee can never edit their own skill level or justification through this tab; only the manager can, and only while Ongoing.**
- **Goals don't belong to a review cycle.** `hr.appraisal.goal` has no `appraisal_id` and no link to any specific `hr.appraisal` — it attaches to `employee_ids` directly ([hr_appraisal_goal.py:17-20](../enterprise/hr_appraisal/models/hr_appraisal_goal.py#L17-L20)). The "Goals" button on an appraisal just opens every open goal the employee currently has, filtered by employee, not by cycle. There is no per-cycle snapshot of a goal's progress — the *same* record persists and shows up on every future appraisal until manually completed (`progression` forced to `100%`) or archived. Progress is a fixed 5-step bucket (0/25/50/75/100%), not a free-form percentage.
- **The Skills Evolution report only ever compares the latest two cycles.** The underlying SQL view picks each employee's single most recent Done appraisal and diffs it against the `previous_skill_level_id` snapshotted at that appraisal's confirmation — it's not a multi-cycle historical trend ([hr_appraisal_skill_report.py:65-76](../enterprise/hr_appraisal_skills/report/hr_appraisal_skill_report.py#L65-L76)). Color coding is real and matches green/black/red: `decoration-success` for improvement/just-added, `decoration-danger` for decline, no decoration (default/black) for unchanged ([hr_appraisal_skill_report_views.xml:6-7](../enterprise/hr_appraisal_skills/report/hr_appraisal_skill_report_views.xml#L6-L7)).
- **No real PDF export.** The cog-menu "Print" just calls the browser's print dialog against a print stylesheet — there's no `ir.actions.report` anywhere in the module, despite the manifest description implying a PDF form ([print_menu.js:9-14](../enterprise/hr_appraisal/static/src/component/print_menu.js#L9-L14)).
- **"Only my direct reports" is a UI convenience, not a hard security boundary.** The employee-picker domain restricts a regular manager to their own subordinates client-side ([res_users.py:9-21](../enterprise/hr_appraisal/models/res_users.py#L9-L21)), but the actual record rule only checks `manager_ids`, and picking any employee auto-adds the acting user into `manager_ids` via onchange. Anyone needing to manage appraisals org-wide as a matter of policy should get the **Officer: Access all appraisals** group rather than relying on the picker restriction.
- **Deleting is locked down almost everywhere.** Only Draft appraisals can be deleted at all (`@api.ondelete` guard, [hr_appraisal.py:447-450](../enterprise/hr_appraisal/models/hr_appraisal.py#L447-L450)) — this applies even to Administrators.
- **A dead menu action ships in the box.** `views/hr_employee_views.xml` wires a server action to `model._create_multi_appraisals()`, but no such method exists anywhere in the codebase (verified by full-tree grep) — triggering it raises `AttributeError`.

---

## Related Docs

- [`INDEX.md`](INDEX.md)
- [`hr_employee_versions.md`](hr_employee_versions.md) — employee/manager/department data this module reads from

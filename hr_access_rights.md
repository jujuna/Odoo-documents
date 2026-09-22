# HR Access Rights — Who Sees What, and Why

> **Scope:** `hr`, `hr_holidays`, `hr_attendance`, `hr_recruitment`, `hr_expense`, `hr_payroll`, `hr_appraisal`, `knowledge`, `hr_contract_salary`, `geo_payroll`
> **Purpose:** answer "who can see whose data" without guessing. Every claim links to the rule that produces it.

## Why This Document Exists

The single most common HR support ticket is *"my manager can't see / approve X"*. It is almost never a bug.
Odoo does **not** have one concept of "manager". It has at least six, each stored in a different field,
each controlling a different app. A person who is a manager in the org chart may have zero approval
rights, and a person with no subordinates at all can be the approver for the whole company.

Understanding access in Odoo HR means understanding three layers, applied in this order:

| Layer | What it decides | Where it lives |
|---|---|---|
| **Menu groups** | Whether you even see the menu | `groups="..."` on `<menuitem>` |
| **ACL** (`ir.model.access`) | Whether you can read/write the *model* at all | `security/ir.model.access.csv` |
| **Record rules** (`ir.rule`) | *Which records* of that model you see | `security/*.xml` |
| **Field groups** | Which *fields* on a visible record you see | `groups=` on the field definition |

The critical mechanic: **record rules of the same permission type are OR-ed across groups, and AND-ed with global rules.**
Adding a group can only ever widen what a user sees. Removing a group can silently break an approval flow.

---

## The Six Different "Managers"

| Field | Label in UI | Controls | Default source |
|---|---|---|---|
| `parent_id` | Manager (employee form) | Org chart, appraisal defaults, geo_payroll work logs | set manually |
| `leave_manager_id` | Time Off Approver | Time Off approvals + reading subordinate leaves | auto-copied from `parent_id.user_id` |
| `attendance_manager_id` | Attendance Approver | Attendance records of that employee | set manually |
| `expense_manager_id` | Expense Approver | Expense reports (with the Team Approver group) | set manually |
| `manager_ids` (on `hr.appraisal`) | Appraisal Manager | Reading/writing that appraisal | copied from `parent_id` at creation |
| `hr.department.manager_id` | Department Manager | Time Off *reporting* for the whole department subtree | set on the department |

`leave_manager_id` is the only one Odoo keeps in sync with the org chart:
[`hr_employee.py:159`](../addons/hr_holidays/models/hr_employee.py#L159) recomputes it from `parent_id.user_id`,
but **only if it was still pointing at the previous manager or was empty**. Once someone edits it by hand,
changing the org chart no longer moves the approval.

Two side effects worth knowing:

- Writing `leave_manager_id` **automatically grants** that user the `Time Off Responsible` group
  ([`hr_employee.py:226`](../addons/hr_holidays/models/hr_employee.py#L226)). Nobody has to touch Settings → Users.
- Clearing it removes the group again if the user is no longer anyone's approver
  (`_clean_leave_responsible_users`).

---

## Layer 0 — What a Plain Employee Can Reach

An internal user with **no HR groups at all** (`base.group_user` only) still gets a surprising amount:

| Can do | Mechanism |
|---|---|
| Open the **Employees** app | menu root allows `base.group_user` ([`hr_views.xml:5`](../addons/hr/views/hr_views.xml#L5)) |
| Browse the **Directory** — every colleague's name, job, work phone/email, department, photo, org chart | `hr.employee.public` is readable by `base.group_user` ([ACL](../addons/hr/security/ir.model.access.csv)) |
| See **Departments** kanban | [`hr_views.xml:42`](../addons/hr/views/hr_views.xml#L42) |
| See **everyone's approved time off** in the Time Off calendar | `hr.leave.report.calendar` readable by `base.group_user` |
| Request time off, cancel own pending requests | `hr.leave` ACL is full CRUD for `base.group_user`, narrowed by rules |
| Read own attendance | `group_hr_attendance_own_reader` is implied by `base.group_user` |
| Create/submit own work logs (geo_payroll) | [ACL](../custom_addons/gec_payroll_types/geo_payroll/security/ir.model.access.csv) + own-draft rule |

What they **cannot** do: open the real `hr.employee` form. There is no `base.group_user` line for
`hr.employee` in the ACL — only `hr.group_hr_user`. Self-service works through a completely different
path: the **My Profile** dialog is a `res.users` form, and the HR fields on it are `related` fields
whitelisted in `HR_READABLE_FIELDS` / `HR_WRITABLE_FIELDS`
([`res_users.py:16`](../addons/hr/models/res_users.py#L16)).

> **Consequence for development:** any "employee sees their own record" feature must be built on a model
> the employee has ACL for — never as a page on the employee form. See [`hr_employee_versions.md`](hr_employee_versions.md).

### Directory vs Employees — the same app, two models

- **Directory** → `hr.employee.public`, an SQL view over `hr.employee` exposing only work-related fields
  ([`hr_employee_public.py`](../addons/hr/models/hr_employee_public.py)). No birthday, no private phone,
  no ID documents, no salary.
- **Employees** → the real `hr.employee`, menu restricted to `group_hr_user`
  ([`hr_views.xml:18`](../addons/hr/views/hr_views.xml#L18)).

Private data is protected twice: the plain user has no ACL on `hr.employee`, **and** every sensitive field
carries `groups="hr.group_hr_user"` — private phone/email, birthday, place of birth, bank accounts,
work permit, ID card copy, driving licence, PIN, badge ID, emergency contact
([`hr_employee.py:124-212`](../addons/hr/models/hr_employee.py#L124)).

Contract-money fields are stricter still: `contract_wage`, `contract_date_start/end`, `trial_date_end`,
`structure_type_id` are `groups="hr.group_hr_manager"`
([`hr_employee.py:177`](../addons/hr/models/hr_employee.py#L177)). An HR *Officer* administers people;
only an HR *Administrator* sees the salary.

---

## Employees (`hr`)

| Group | Name in Settings | What it opens |
|---|---|---|
| — | (plain user) | Directory, Departments, own profile dialog |
| `hr.group_hr_user` | Employees: Officer — Manage all employees | Real employee forms, all private fields, Reporting, employee bank accounts |
| `hr.group_hr_manager` | Employees: Administrator | + Configuration, contract/salary fields, `hr.version` write, onboarding plans |

Scoping detail: there is **no** "officer sees only my department" rule. `group_hr_user` sees every employee
in the allowed companies. The only rule on `hr.employee` is the multi-company one, which carries three
OR-branches so that your own record, your manager's record, and your subordinates' records stay visible
even across companies ([`hr_security.xml:28`](../addons/hr/security/hr_security.xml#L28)).

Bank accounts get a dedicated pair of rules: a plain user can only see `res.partner.bank` records that
belong to **non-employees**; HR officers see all of them
([`hr_security.xml:68`](../addons/hr/security/hr_security.xml#L68)).

---

## Time Off (`hr_holidays`)

Three groups plus one invisible one:

| Group | Name in Settings | Sees |
|---|---|---|
| `group_hr_holidays_responsible` | *(not selectable — auto-assigned)* | Requests of employees where they are `leave_manager_id` |
| `group_hr_holidays_user` | Time Off: Officer — Manage all requests | Every request in the company. Implies `hr.group_hr_user` |
| `group_hr_holidays_manager` | Time Off: Administrator | Everything + Configuration (types, accruals, public holidays) |

Note the implication chain: **making someone a Time Off Officer also makes them an HR Officer**
([`hr_holidays_security.xml:16`](../addons/hr_holidays/security/hr_holidays_security.xml#L16)) — so they
gain access to every employee's private data, bank accounts included. This is the most common accidental
over-permission in an HR rollout.

### Who approves what

The approval path is a property of the **time off type**, not of the person
(`leave_validation_type`, [`hr_leave_type.py:83`](../addons/hr_holidays/models/hr_leave_type.py#L83)):

| Setting | Approver |
|---|---|
| None needed | auto-approved |
| By Time Off Officer | anyone in `group_hr_holidays_user` |
| By Employee's Approver | the employee's `leave_manager_id` |
| By Employee's Approver and Time Off Officer | both, in sequence (`validate1` → `validate`) |

So "my manager can't approve my vacation" has exactly two possible causes: the type is set to
*By Time Off Officer*, or `leave_manager_id` points at someone else.

### Write windows

Employees can edit their own request only while it is not `validate`/`validate1`, and delete it only in
`confirm`/`validate1` ([`hr_holidays_security.xml:39-72`](../addons/hr_holidays/security/hr_holidays_security.xml#L39)).
After approval the employee must use *Cancel* (a wizard), not edit.

### The department-manager exception

The **Time Off → Reporting** overview uses `hr.leave.report`, which has its own rule: a plain user sees
rows where `has_department_manager_access = True` — meaning their own rows plus every employee in a
department (or sub-department) where they are `hr.department.manager_id`
([`hr_manager_department_report.py:15`](../addons/hr/report/hr_manager_department_report.py#L15)).
This is the *only* place in standard HR where "department manager" grants data access, and it grants
reporting visibility, not approval rights.

### Privacy in the shared calendar

Everyone sees everyone's approved absences — but not why. `description` and `holiday_status_id` on
`hr.leave.report.calendar` are `groups='hr_holidays.group_hr_holidays_user'`
([`hr_leave_report_calendar.py:34`](../addons/hr_holidays/report/hr_leave_report_calendar.py#L34)).
Colleagues see *"Nino — 3 days"*, officers see *"Nino — Sick Leave"*.

---

## Attendance (`hr_attendance`)

| Group | Sees |
|---|---|
| `group_hr_attendance_own_reader` (implied by every internal user) | own attendance, read-only |
| `group_hr_attendance_officer` | attendance of employees where they are `attendance_manager_id` — read **and write** |
| `group_hr_attendance_user` | all attendance, all employees |
| `group_hr_attendance_manager` | + configuration, kiosk settings |

`attendance_manager_id` is **not** auto-filled from `parent_id`. It has to be set per employee, and the
manager also needs the Officer group — the field alone does nothing
([`hr_attendance_security.xml:57`](../addons/hr_attendance/security/hr_attendance_security.xml#L57)).

---

## Payroll (`hr_payroll` + `geo_payroll`)

| Group | Sees |
|---|---|
| — | **nothing**. `hr.payslip` has no `base.group_user` ACL line |
| `hr_payroll.group_hr_payroll_user` | all payslips, all batches, all salary rules |
| `hr_payroll.group_hr_payroll_manager` | + payslip input types, rule parameters, unit-work rates |

There is no partial payroll visibility and no "managers see their team's payslips" mode. Payroll is
all-or-nothing per company ([ACL](../enterprise/hr_payroll/security/ir.model.access.csv)).
Employees receive payslips as emailed PDFs; `group_payslip_display` only controls whether the PDF preview
panel renders on the payslip form.

### Work logs (custom — `geo_payroll`)

This is the one place where the plain **org-chart manager** (`parent_id`) is the authority
([`security.xml`](../custom_addons/gec_payroll_types/geo_payroll/security/security.xml)):

| Who | Can |
|---|---|
| Employee | read own + own manager's scope; create/edit/delete own logs in `draft`/`rejected` |
| `parent_id.user_id` (direct manager) | read direct reports; write/create their logs in `draft`/`submitted` — i.e. approve or send back |
| Payroll Officer | everything, company-wide |

The **Work Log Approvals** menu under the Employees app has no group restriction — every internal user
sees the menu, and non-managers simply get an empty list (the action is domain-filtered on
`employee_id.parent_id.user_id = uid`).

> Deliberate inconsistency to explain in training: time off follows `leave_manager_id`, work logs follow
> `parent_id`. Changing someone's manager moves their work-log approvals immediately, but moves their
> time-off approvals only if `leave_manager_id` was never edited by hand.

---

## Recruitment (`hr_recruitment` + Alta customization)

| Group | Sees |
|---|---|
| `group_hr_recruitment_interviewer` | only applicants where they are in `interviewer_ids`, or interviewer on the job position. Cannot create or delete |
| `group_hr_recruitment_user` | all applicants, all job positions, all talent pools — **and all chatter in the database** |
| `group_hr_recruitment_manager` | + configuration, activity plans |

Two things to flag:

- The Officer group carries a rule granting `(1,'=',1)` on `mail.message`
  ([`hr_recruitment_security.xml:86`](../addons/hr_recruitment/security/hr_recruitment_security.xml#L86)).
  A recruiter can read chatter on records they otherwise have no business seeing. Grant it deliberately.
- Every internal user is implicitly in `group_applicant_cv_display`, so CVs render on the application form
  for anyone who can open an applicant.

### Salary offers

`hr.contract.salary.offer` is split by role rather than by record ownership
([`hr_contract_salary_security.xml:17`](../enterprise/hr_contract_salary/security/hr_contract_salary_security.xml#L17)):

- HR Administrator → offers with **no applicant** (i.e. existing-employee offers)
- Recruitment Officer → offers with **no employee version** (i.e. candidate offers)

Because rules OR together, a user holding both groups sees both sets. A user holding neither sees none.

Alta's customization adds an `accepted` state that is terminal — an accepted offer cannot be refused or
deleted ([`hr_contract_salary_offer.py:88`](../custom_addons/alta_hr_customization/hr_customization/models/hr_contract_salary_offer.py#L88))
— and routes decision notifications by role on the applicant: `user_id` (recruiter) and `team_leader_id`
get a plain notice, `lawyer_id` additionally gets the offer details.

The candidate reads and signs the offer through a **tokenized public URL**, not a portal account
([`offer.py:13`](../custom_addons/alta_hr_customization/hr_customization/controllers/offer.py#L13)) —
access is `consteq` on `access_token`, and the link stops working once the offer leaves `open` or passes
`offer_end_date`.

### Contract & trial expiry alerts

A daily cron warns 7 days ahead and notifies the employee's `recruitment_recruiter_id`,
`recruitment_team_leader_id` and `recruitment_lawyer_id` — falling back to `hr_responsible_id` if none are
set ([`hr_version.py:16`](../custom_addons/alta_hr_customization/hr_customization/models/hr_version.py#L16)).
The `contract_expiry_notified_for` / `trial_expiry_notified_for` stamps make it fire once per deadline, so
changing the end date re-arms the alert.

---

## Appraisals (`hr_appraisal`)

A plain user sees appraisals where they are the employee **or** are listed in `manager_ids`
([`hr_appraisal_security.xml:79`](../enterprise/hr_appraisal/security/hr_appraisal_security.xml#L79)) —
read-only at rule level; the feedback fields themselves are governed by the appraisal's own
"visible to employee / visible to manager" flags. `group_hr_appraisal_user` sees all appraisals,
`group_hr_appraisal_manager` adds campaigns and configuration.

`manager_ids` is seeded from `parent_id` when the appraisal is created and then frozen — reassigning the
employee later does not move existing appraisals.

---

## Expenses (`hr_expense`)

| Group | Sees |
|---|---|
| — | own expenses in `draft`; own non-draft read-only |
| `group_hr_expense_team_approver` | own + department-manager's employees + `child_of` own employee (org chart!) + `expense_manager_id` + `manager_id` on the sheet |
| `group_hr_expense_user` | all |
| `group_hr_expense_manager` | all + configuration |

Expenses is the one standard app whose approver rule includes the **org chart** (`employee_id child_of
user.employee_ids.ids`) alongside department manager and the explicit `expense_manager_id`
([`ir_rule.xml:12`](../addons/hr_expense/security/ir_rule.xml#L12)). Four different paths to the same
approval right — which is why expense visibility often surprises people.

---

## Knowledge (`knowledge`)

Knowledge ignores HR groups entirely and computes access per article:

- `internal_permission` — `write` / `read` / `none` (Members only) — the default for **all internal users**
- inherited down the article tree from the nearest ancestor that defines it (`inherited_permission`)
- overridden per person by `article_member_ids`
- `is_desynchronized` breaks inheritance for a branch

The record rules simply read the computed flags: `user_has_access` for read, `user_has_write_access` for
write ([`ir_rule.xml`](../enterprise/knowledge/security/ir_rule.xml)). The **Section** shown in the sidebar
(Workspace / Shared / Private) is derived from those permissions, not chosen.

Alta flags one article with `welcome_message = True`; the most recently edited flagged article is linked in
the welcome email sent when HR creates an employee's user
([`res_users.py`](../custom_addons/alta_hr_customization/hr_customization/models/res_users.py)).

---

## Diagnosing "X can't see Y"

Work down the layers in order — the answer is almost always in the first three steps:

1. **Is the menu visible?** No → missing group. Menu groups are the cheapest thing to check.
2. **Empty list where records should be?** Menu is visible but the record rule filters everything out →
   wrong approver field, or the record belongs to another company.
3. **"You are not allowed to access records of type X"?** Missing ACL, not a rule. The group itself is absent.
4. **Record opens but a field is blank/missing?** Field-level `groups=`. Compare against the field
   definition — the value exists, it is just not sent to the browser.
5. **Right in one app, not another?** Different approver field. Check all six.

Debug tooling: Settings → Technical → Security → *Record Rules* / *Access Rights*, filtered by model.
Impersonating with **Log in as** is the fastest reliable test — never validate access from an admin session.

---

## Rollout Checklist

- [ ] Every employee has `parent_id` set — it seeds `leave_manager_id`, appraisals, work-log approvals
- [ ] `leave_manager_id` verified per employee (auto-fill only works if it was never hand-edited)
- [ ] `attendance_manager_id` and `expense_manager_id` set explicitly if those apps are used
- [ ] `hr.department.manager_id` set — required for the Time Off department overview
- [ ] Time off types reviewed: `leave_validation_type` matches who you actually want approving
- [ ] Nobody has Time Off Officer unless they should also see all private employee data (implied group)
- [ ] Recruitment Officer granted deliberately — it carries database-wide chatter read access
- [ ] Payroll groups given only to payroll staff — there is no partial payroll visibility
- [ ] Knowledge article permissions set at the top of each tree, before children are created
- [ ] Access verified by **Log in as** for one plain employee, one manager, one officer

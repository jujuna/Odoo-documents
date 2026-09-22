# Job Positions — `hr.job` and the `department_id` field

> **Module:** `hr` (+ consumers `hr_recruitment`, `website_hr_recruitment`, enterprise `hr_contract_salary`) | **Path:** [`addons/hr/models/hr_job.py`](../addons/hr/models/hr_job.py)
> Scope: the `hr.job` model and specifically how its `department_id` behaves — including when it is left empty. Not a full `hr` module doc.

## What It Does & Why It Exists

A Job Position (`hr.job`) is a named role inside a company — "Developer", "Accountant". It carries a recruitment target (`no_of_recruitment`), a recruiter, an employment type, an optional department, and a job description. It is the anchor object for recruitment: the email alias, the website careers posting, and applicant routing all hang off it. On the employee side it is mostly a label (`job_title`).

The `department_id` on a position is **optional** and is **not** the same relationship as the department on an employee. This is the single most misunderstood part of the model.

---

## `department_id` — the field itself

Defined at [`hr_job.py:38`](../addons/hr/models/hr_job.py#L38):

```python
department_id = fields.Many2one('hr.department', string='Department',
    check_company=True, tracking=True, index='btree_not_null')
```

- **Not `required`** → empty is a fully valid state.
- **No `default`, no `compute`, no `onchange`** → it is a plain manual field. Nothing fills it for you.
- `check_company=True` → if set, the department must belong to the job's company.
- `index='btree_not_null'` → indexed only for non-null rows (empty rows aren't indexed).

### Uniqueness constraint — the empty-department trap

[`hr_job.py:42`](../addons/hr/models/hr_job.py#L42):

```python
_name_company_uniq = models.Constraint(
    'unique(name, company_id, department_id)',
    'The name of the job position must be unique per department in company!')
```

PostgreSQL treats `NULL` as **distinct** in a `UNIQUE` constraint (no `NULLS NOT DISTINCT` here). So when `department_id` is empty, the constraint does **not** fire. You can create **many** positions with the same name in the same company as long as they all have no department. With a department set, the duplicate is blocked.

---

## What the job's department DRIVES (works only when it is set)

Everything below reads `job.department_id`. Leave it empty and each one degrades as noted.

| Consumer | Source | When department is SET | When EMPTY |
|---|---|---|---|
| **Applicant department** | [`hr_applicant.py:569`](../addons/hr_recruitment/models/hr_applicant.py#L569) `_compute_department` | applicant `department_id = job.department_id` (stored, editable) | applicant created with no department |
| **Applicant company** | [`hr_applicant.py:559`](../addons/hr_recruitment/models/hr_applicant.py#L559) `_compute_company` | company taken from `department_id.company_id` | falls back to `job.company_id`, then `env.company` |
| **Email alias defaults** | [`hr_recruitment/hr_job.py:273`](../addons/hr_recruitment/models/hr_job.py#L273) `_alias_get_creation_values` | apply-by-email applicants get this department; company `= department_id.company_id or company_id` | no department on emailed-in applicants; company falls back to job |
| **Department Manager on job** | [`hr_recruitment/hr_job.py:55`](../addons/hr_recruitment/models/hr_job.py#L55) `manager_id = related('department_id.manager_id')` | manager resolved, auto-subscribed | empty — no department manager follows the job |
| **New employee from applicant** | [`hr_applicant.py:1016`](../addons/hr_recruitment/models/hr_applicant.py#L1016), [`:1043`](../addons/hr_recruitment/models/hr_applicant.py#L1043) | employee gets `department_id`; `work_email`/`work_phone` seeded from `department_id.company_id` | employee created with no department; no work_email/phone company defaults |
| **Website careers — department line** | [`website_hr_recruitment_templates.xml:72`](../addons/website_hr_recruitment/views/website_hr_recruitment_templates.xml#L72) `t-if="job.department_id"` | department shown on the job card | line hidden |
| **Website careers — grouping/filter** | [`website_hr_recruitment/hr_job.py:105`](../addons/website_hr_recruitment/models/hr_job.py#L105) | listed under its department filter | listed under the **"Other"** bucket (`is_other_department` → `department_id = None`) |
| **Department recruitment KPIs** | [`hr_recruitment/hr_department.py:19`](../addons/hr_recruitment/models/hr_department.py#L19) | target/hired counts roll up into the department | not counted toward any department |
| **Group By / search** | [`hr_job_views.xml:94`](../addons/hr/views/hr_job_views.xml#L94) group_by; `child_of` filter | grouped under the department; matched by department search | lands in the "None" group; a `child_of` department search won't return it |
| **Salary offer (enterprise)** | [`hr_contract_salary_offer.py:261`](../enterprise/hr_contract_salary/models/hr_contract_salary_offer.py#L261) | offer department auto-filled from the job | left as-is, not auto-filled |

---

## What the job's department does NOT do

- **It does NOT set the employee's department.** On `hr.version` (the employee's record/contract), `job_id` and `department_id` are **independent** fields ([`hr_version.py:116,119`](../addons/hr/models/hr_version.py#L116)). There is **no onchange/compute** copying `job.department_id` → the employee's department. Assigning a position to an existing employee changes their job title, not their department. The only path where a job's department reaches an employee is recruitment **Create Employee**, and even there it flows through the applicant, not through `job_id`.
- **It does NOT affect headcount on the position.** `no_of_employee` / `expected_employees` count `employee_ids` (employees whose `job_id` is this job) regardless of department ([`hr_job.py:51`](../addons/hr/models/hr_job.py#L51)).
- **It does NOT enforce name uniqueness** while empty (Postgres NULL semantics, above).

---

## Gotchas & Non-Obvious Behavior

- **Position department ≠ employee department.** Decoupled in v19. Setting one never moves the other on the employee record. Treat the position's department as a recruitment/reporting attribute, not an employee assignment.
- **Recruitment department is computed but editable.** `applicant.department_id` recomputes from `job_id` whenever the job changes ([`hr_applicant.py:569`](../addons/hr_recruitment/models/hr_applicant.py#L569)); a manual value on the applicant is overwritten if the job is reselected.
- **Empty department = duplicate positions allowed.** Same name + same company + no department can exist many times.
- **Website still lists department-less jobs** — under "Other", not hidden.
- **No department → weaker recruitment defaults**: no department manager follower, no company-derived `work_email`/`work_phone` when creating the employee, company resolved by fallback chain.

---

## Related Docs

- [`INDEX.md`](INDEX.md)
- [`hr_payroll.md`](hr_payroll.md) — employee `hr.version` (job_id/department_id live here), payroll consumers
- [`employee_registry_rs.md`](employee_registry_rs.md) — derives target status from `hr.version`

# hr_customization (Alta) — Candidate Offer Accept/Reject + HR Notifications

> Custom module at [`custom_addons/alta_hr_customization/hr_customization`](../custom_addons/alta_hr_customization/hr_customization). Version 19.0.1.9.0.
> Analyzed end-to-end 2026-08-14 (all 27 files). See **Known Issues** — one confirmed data-loss path.

## Overview

Replaces the enterprise sign-based offer flow with a plain **Accept / Reject** decision for job applicants. A candidate opens the tokenized salary-configurator page, sees fixed offer terms (configurator hidden), fills personal info (ID document, bank, pension-fund membership), and accepts or rejects. Accepting creates an archived `hr.version` snapshot, sets a new terminal `accepted` offer state, and emails the recruiter / team leader / lawyer. The module also adds contract/trial expiry warning mails, a knowledge-article welcome email for new users, and a public "Responsibilities" section on vacancy pages.

## Dependencies

| Module | Why |
|---|---|
| `hr_contract_salary` (enterprise) | Offer model, salary configurator page, personal-info framework — heavily extended |
| `website_hr_recruitment` | Public vacancy page (responsibilities section) |
| `knowledge` | Welcome-article flag + link in welcome mail |
| `geo_payroll` | Provides `hr.employee.pension_fund_member` used by a personal-info question |

## Business Flow — Candidate Offer

1. **Offer creation** — unchanged (recruiter uses `action_generate_offer` from the applicant). Applicant form gains [`team_leader_id` / `lawyer_id`](../custom_addons/alta_hr_customization/hr_customization/models/hr_applicant.py#L7) (lawyer defaults from company setting).
2. **Send by email** — [`action_send_by_email`](../custom_addons/alta_hr_customization/hr_customization/models/hr_contract_salary_offer.py#L70) injects `mark_offer_as_sent` into the composer context; the `message_post` override then logs "offer sent to X by email" on the offer. The applicant mail template `hr_contract_salary.mail_template_send_offer_applicant` is overwritten with a plain "Review employment offer" body (no sign wording).
3. **Candidate page** — [`hr_contract_salary_templates.xml`](../custom_addons/alta_hr_customization/hr_customization/views/hr_contract_salary_templates.xml) retitles the page "Employment Offer", shows a read-only offer card (position, gross wage, contract period, validity), hides the benefit configurator and sidebar (`d-none` when `applicant_id`), and swaps the submit button for **Accept Offer / Reject Offer** inside the personal-info block. Employee (non-applicant) offers keep the stock sign flow untouched.
4. **Accept** — JS patch on `SalaryPackage.submitSalaryPackage` posts to [`/hr_customization/offer/accept`](../custom_addons/alta_hr_customization/hr_customization/controllers/offer.py#L262):
   - token check (`consteq`) + row lock (`try_lock_for_update`) + re-read state → only `open`, non-expired, applicant offers pass; double-accept/reject races are locked out.
   - **Server-side terms lock** — [`_get_locked_offer_inputs`](../custom_addons/alta_hr_customization/hr_customization/controllers/offer.py#L140) discards every submitted salary/benefit value and rebuilds the `version` section from the server (`wage`, `final_yearly_costs`, benefit values); only personal-info sections are taken from the form.
   - Validation: required personal infos (respecting hidden children), valid private email, ID document, bank account.
   - Reuses base `create_new_version` → archived employee + archived `hr.version` (named "Accepted offer - …", linked via `applicant_id` and `accepted_version_id`).
   - Offer → `state='accepted'` (new selection value, terminal), `accepted_date` stamped.
   - Mails: recruiter+team leader get a short notice; lawyer gets the detailed variant (wage, dates, "prepare the employment contract"). Chatter note on offer + applicant.
5. **Reject** — `/hr_customization/offer/reject` → base `action_refuse_offer` + notification to all three users.
6. **Thank-you page** — `/hr_customization/offer/<id>/<decision>`, token-gated, state must match.

**Terminal-state guards:** accepted offers cannot be refused ([`action_refuse_offer` override](../custom_addons/alta_hr_customization/hr_customization/models/hr_contract_salary_offer.py#L86) raises; `archive_applicant` passes `skip_accepted_offer_refusal` so archiving an applicant refuses only the other offers) and cannot be deleted (`@api.ondelete`). Accepted/cancelled offers render "Offer closed" instead of the configurator page.

**Not done on accept:** applicant is not moved to the Hired stage, employee/version stay archived — activation is a manual HR/lawyer step after the real contract is signed.

**Pending vs departed (19.0.1.2.0):** accept stamps [`pending_activation`](../custom_addons/alta_hr_customization/hr_customization/models/hr_employee.py#L47) on the archived employee (skipped for already-active internal candidates); any `active=True` write auto-clears it. Employee search view gains two archived filters: **Pending Start** (`active=False, pending_activation=True`) and **Left Company** (`active=False, pending_activation=False`).

## Expiry Notifications (cron)

Daily cron [`_cron_notify_upcoming_employment_expiry`](../custom_addons/alta_hr_customization/hr_customization/models/hr_version.py#L65): versions whose `contract_date_end` or `trial_date_end` falls within the next 7 days get one mail per deadline (`*_notified_for` markers make it once-per-date; extending the date re-arms it). Recipients: the employee's `recruitment_recruiter_id | recruitment_team_leader_id | recruitment_lawyer_id` (stamped onto the employee at accept time), falling back to `hr_responsible_id`. Per-version savepoint so one failure doesn't kill the batch.

## Welcome Email

`knowledge.article` gets a `welcome_message` flag (checkbox in the article top bar). [`res.users.create`](../custom_addons/alta_hr_customization/hr_customization/models/res_users.py#L7) sends `mail_template_welcome_message` only when all three hold: the user was created with `create_employee`/`create_employee_id` (the HR "Create User" path), the employee has a `work_email`, and `welcome_article_id` resolves. That compute picks the single most recently written flagged article **globally** — not per department, despite `department_ids` existing on the article — so with no flagged article anywhere the mail is skipped silently.

## Email Templates

Six templates in play; only one ever reaches a candidate. Recipients of the four internal ones are assembled in Python and injected as `email_values={'email_to': ...}`, so the `email_to` field on the record (`eval="False"`) is inert — editing it in Settings does nothing.

| XML ID | Model | Recipients | Trigger | Send |
|---|---|---|---|---|
| `hr_contract_salary.mail_template_send_offer_applicant` (overridden) | `hr.contract.salary.offer` | Applicant partner (`use_default_to`, from base) | Manual — **Send by Email** | Composer |
| `mail_template_offer_accepted` | `hr.contract.salary.offer` | Recruiter + Team Leader; Lawyer separately | Candidate accepts | queued (`force_send=False`) |
| `mail_template_offer_rejected` | `hr.contract.salary.offer` | Recruiter + Team Leader + Lawyer | Candidate rejects | queued |
| `mail_template_contract_expiry` | `hr.version` | Employee's recruiter/team leader/lawyer, else `hr_responsible_id` | Daily cron, T-7 on `contract_date_end` | queued |
| `mail_template_trial_expiry` | `hr.version` | same | Daily cron, T-7 on `trial_date_end` | queued |
| `mail_template_welcome_message` | `hr.employee` | `work_email` | User created for an employee | inline (`force_send=True`) |

**Candidate mail is an override, not a new record.** Only `name`, `description`, `body_html` are replaced; subject, `use_default_to` and `lang` stay from enterprise. The body drops the "Configure your package" wording (the configurator is hidden for applicants) and keeps the tokenized link, which is built from composer context — `offer_id`, `access_token`, `validity_end` are injected by base [`action_send_by_email`](../enterprise/hr_contract_salary/models/hr_contract_salary_offer.py#L321), not read off the record.

**One template, two audiences.** [`_send_decision_notification`](../custom_addons/alta_hr_customization/hr_customization/models/hr_contract_salary_offer.py#L39) sends the accepted template twice: plain for recruiter+team leader, and with `show_offer_details=True` for the lawyer, which unlocks the wage / annual cost / start-end dates / "prepare the employment contract" block. The flag is read in the body as `ctx.get('show_offer_details')`; `ctx` is the rendering context exposed at [`mail_render_mixin.py:309`](../addons/mail/models/mail_render_mixin.py#L309). Rendering uses `sudo()` — mandatory, because the controller is `auth="public"` and the body reads group-restricted `wage`. `email_from` is the company partner, falling back to the acting user.

**Expiry sends are self-arming.** [`_send_expiry_notification`](../custom_addons/alta_hr_customization/hr_customization/models/hr_version.py#L41) returns `False` when no recipient has an email, so `*_notified_for` is never stamped and the cron silently retries every day with no chatter trace.

Gotchas shared by all six: no `lang` on the five module-owned templates (rendered in the sender environment's language), `auto_delete=True` so the `mail.mail` is gone after sending (chatter notes are the only audit trail), and neither data file is `noupdate` — every hand edit is reverted on upgrade.

## Configuration

- **Settings → Recruitment → Default Recruitment Lawyer** (`res.company.recruitment_lawyer_id`): default lawyer for new applicants; on save it also backfills all lawyer-less applicants of the company.
- Personal-info records added (noupdate): required ID-document upload, required Bank dropdown (new `bank` dropdown source = all `res.bank`), optional pension-fund checkbox.
- `hr.job.responsibilities` (translatable HTML, own form tab) renders on the public vacancy page below the description.
- **Team Leader payroll visibility (19.0.1.7.0):** new group `group_hr_payroll_team_leader` under the Payroll privilege (below Officer, standalone — implies nothing). Members get read-only `hr.version` + `hr.payslip` (+ `hr.contract.type`) ACLs, record-ruled to **themselves + direct reports** (`employee_id.user_id` or `employee_id.parent_id.user_id` = user); payslips further limited to `validated`/`paid` states (v19 keys — there is no `done`; a wrong `done` key shipped first and made the tab permanently empty, fixed 2026-08-19 incl. a manual `ir_rule` repair in hr3 because the rule is noupdate) — drafts never leak. Seven gated version fields (`date_version`, contract dates, `contract_type_id`, `wage`, `wage_type`, `hourly_wage`) extend their field-groups to the new group. UI: "Contract History" and "Payroll" pages on the public employee card, double-gated (group membership + `parent_user_id == uid or user_id == uid`), `no_open` lists. O2m fields on `hr.employee.public` carry the group too, so non-members get them stripped everywhere. Payslip **lines** (breakdown) deliberately not exposed — net amount only.
- **Knowledge ↔ Department link (19.0.1.6.0):** many2many `knowledge_article_department_rel` — `knowledge.article.department_ids` (tags in the article top bar + list) ↔ `hr.department.knowledge_article_ids` (picker list on the department form, `no_open` + `article_url` "Open" link because the full Knowledge editor form crashes in a modal). Attaching from the department writes on the article — knowledge's own permission layer applies.
- **Manager-only Resume/Certifications on public card (19.0.1.4.0):** stock shows both tabs on `hr.employee.public` to every internal user; a [view inherit](../custom_addons/alta_hr_customization/hr_customization/views/hr_employee_public_views.xml) gates them with `parent_user_id != uid and user_id != uid` (new related field `parent_user_id` = `parent_id.user_id`), so only the direct manager and the employee themselves see them. UI-only — stock read-all record rules on `hr.resume.line`/`hr.employee.skill` unchanged. Added `hr_skills` dependency.
- **Department hierarchy name overflow fix (19.0.1.3.0):** [view inherit](../custom_addons/alta_hr_customization/hr_customization/views/hr_department_views.xml) stamps `o_hr_department_node_header` on the colored header (base `web_hierarchy` hardcodes `height: 30px`, no wrap), and a [scoped SCSS](../custom_addons/alta_hr_customization/hr_customization/static/src/hierarchy/hr_department_hierarchy.scss) makes it auto-height + `overflow-wrap: anywhere`. Employee org chart untouched. Added `hr_org_chart` dependency.

## Edge Cases & Gotchas

- The salary-page overrides key off `applicant_id` in rendering values, so employee-offer behavior is stock; the JS patch also no-ops without the `is_applicant_offer` hidden input.
- `_get_personal_infos` is a **full copy-override** of the base method (only adds the `bank` dropdown branch) — must be re-diffed on every enterprise update.
- Offer statusbar doesn't list `accepted` in `statusbar_visible`; the green "Accepted" ribbon + list decoration carry the state instead.
- `mail_template_data.xml` is **not** `noupdate` — intentional for the base-template override, but user edits to these templates are lost on module upgrade.

## Known Issues (analysis 2026-08-14)

1. **Data loss — accepted version/employee deleted by sibling-offer refusal or deletion.** Base `action_refuse_offer` and `unlink` both call `applicant.unlink_archived_versions()`, which deletes **all** archived versions of the applicant **and their employees**. The accepted snapshot is exactly that (archived version + archived employee holding ID document/bank data). Refusing, rejecting via link, or deleting *any other* offer of the same applicant — including during applicant archiving — destroys the accepted data; `accepted_version_id` silently nulls. Guards only protect the accepted **offer**, not its version.
2. **Duplicate expiry mails per version row.** `contract_date_end` is synced across all versions of a contract period, and the cron iterates versions, not employees — an employee with N versions gets N identical mails/chatter posts.
3. Minor: `lawyer_id` default uses `env.company`, not the applicant's `company_id` (multi-company mismatch); settings backfill runs on every settings save; accepted state relies on config keeping base `acc_number` personal info required — unchecking it opens an accept-time crash path (`bank_account_vals['acc_number']` KeyError / empty-acc create).

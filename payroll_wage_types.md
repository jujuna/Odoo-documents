# Payroll Wage Types — Fixed / Hourly / Daily and Combinations

> Scope: how Odoo 19 computes pay from a wage definition, which salary schemes work with configuration only, and exactly where to extend for daily rates and mixed (fixed+hourly, fixed+daily, hourly+daily) schemes.
> **Updated by Codex and verified through the complete related-module audit on 2026-07-12.** Related docs: [`public_holidays_flow.md`](public_holidays_flow.md), [`hr_payroll.md`](hr_payroll.md), [`attendance_work_entry.md`](attendance_work_entry.md), and the implementation plan [`../PAYROLL_WAGE_TYPES_PLAN.md`](../PAYROLL_WAGE_TYPES_PLAN.md).

> Safety correction: public-holiday pay is source-specific; native attendance overtime may already pay holiday work; retroactive holiday changes can indirectly affect validated entries; and custom one-time components require correction-lineage settlements rather than a single mutable payslip claim. The canonical details and regression matrix are in the linked flow document and updated plan.

---

## 1. The only two standard wage types

`hr.version` (in v19 the contract data lives on the employee version — there is no separate `hr.contract` record anymore) carries:

| Field | Meaning | Source |
|---|---|---|
| `wage_type` | `monthly` (Fixed Wage) or `hourly` (Hourly Wage) — nothing else | [`hr_version.py:42`](../enterprise/hr_payroll/models/hr_version.py#L42) |
| `wage` | fixed wage per pay period | [`hr_version.py:28`](../enterprise/hr_payroll/models/hr_version.py#L28) |
| `hourly_wage` | manual monetary field, used only when `wage_type='hourly'` | [`hr_version.py:46`](../enterprise/hr_payroll/models/hr_version.py#L46) |
| `structure_type_id.wage_type` | default; `wage_type` is `compute=..., store=True, readonly=False` — changing the structure type **resets** any per-version override | [`hr_payroll_structure_type.py:38`](../enterprise/hr_payroll/models/hr_payroll_structure_type.py#L38), [`hr_version.py:67`](../enterprise/hr_payroll/models/hr_version.py#L67) |
| `work_entry_source` | where worked time comes from: `calendar` / `attendance` / `planning` | base [`hr_version.py:27`](../addons/hr_work_entry/models/hr_version.py#L27), extended by [`hr_work_entry_attendance`](../enterprise/hr_work_entry_attendance/models/hr_version.py#L16) and [`hr_work_entry_planning`](../enterprise/hr_work_entry_planning/models/hr_version.py#L14) |

**Both `wage` and `hourly_wage` show on the form for hourly employees — but `wage` is inert.** Everywhere payroll asks for the contract wage it goes through the `contract_wage` dispatcher (`_get_contract_wage_field`: hourly → `hourly_wage`, else `wage`, [hr_version.py:203](../enterprise/hr_payroll/models/hr_version.py#L203)); on an hourly slip `wage` is never read — you could set it to 0 with no payslip effect. It stays visible only because base `hr` owns the field and the payroll view inherit adds `hourly_wage` without hiding `wage` ([hr_employee_views.xml:43-50](../enterprise/hr_payroll/views/hr_employee_views.xml#L43)). Risk: a stale `wage` value becomes instantly active if `wage_type` flips back to monthly (or a structure-type change recomputes it — gotcha §7.2).

**There is no `daily` wage type anywhere in standard code.** A repo-wide sweep found only one `selection_add` on `wage_type` in all of enterprise: Switzerland adds `NoTimeConstraint` ([`l10n_ch_hr_payroll/models/hr_version.py:216`](../enterprise/l10n_ch_hr_payroll/models/hr_version.py#L216)) — for mixed-billing, not daily pay.

### The `schedule_pay='daily'` trap

`schedule_pay` (year/quarter/month/week/**day**, [`hr_payroll_structure_type.py:13`](../enterprise/hr_payroll/models/hr_payroll_structure_type.py#L13)) is the **pay frequency**, not a rate type. With `schedule_pay='daily'` the wage means "per day" but the payslip period becomes **one day** (`date_to = date_from + _get_schedule_timedelta()`, [`hr_payslip.py`](../enterprise/hr_payroll/models/hr_payslip.py#L273)) — you would run a payslip per day. It is not "daily rate paid monthly".

---

## 2. The wage computation chain

```
hr.version (wage_type, wage / hourly_wage, work_entry_source, resource_calendar_id)
   → hr.work.entry records (generated from calendar OR attendances OR planning slots)
      → payslip worked-days lines: one line per work entry type
         days = hours / calendar.hours_per_day (+ rounding)      [_get_worked_day_lines_values]
      → line.amount                                              [_compute_amount]
         hourly:  hourly_wage × hours × work_entry_type.amount_rate
         monthly: (contract_wage / Σ non-extra hours) × hours × amount_rate
   → BASIC rule: result = payslip.paid_amount  (= Σ worked-days amounts)
   → GROSS = BASIC + ALW → NET = GROSS + DED
```

Key anchors:
- Amount formula: [`hr_payslip_worked_days.py:39-56`](../enterprise/hr_payroll/models/hr_payslip_worked_days.py#L39). Skips recompute when payslip is `edited` or not draft.
- Days derivation + rounding: [`hr_payslip.py:845-870`](../enterprise/hr_payroll/models/hr_payslip.py#L845) (`add_days_rounding` remainder is dumped on the biggest line; per-type `round_days` policy).
- Paid amount: [`hr_payslip.py:1643`](../enterprise/hr_payroll/models/hr_payslip.py#L1643) — sum of worked-days amounts, unless `struct_id.use_worked_day_lines` is off, then raw contract wage.
- BASIC rule: [`hr_salary_rule_data.xml:10-21`](../enterprise/hr_payroll/data/hr_salary_rule_data.xml#L10).
- Salary rule eval context (`worked_days`, `inputs`, `version`, `employee`, `payslip`, `categories`, `result_rules`): [`hr_payslip.py:1010-1044`](../enterprise/hr_payroll/models/hr_payslip.py#L1010). Custom fields on `hr.version` are reachable in rule code as `version.x_field` — no framework patching needed.

**The fixed-wage dilution rule (critical for combos):** for `monthly` the hourly rate is `contract_wage / Σ hours of all non-`is_extra_hours` lines`. Any extra paid work-entry type that is **not** flagged `is_extra_hours` enlarges the denominator and silently dilutes the fixed wage instead of paying on top ([`hr_payslip_worked_days.py:51-54`](../enterprise/hr_payroll/models/hr_payslip_worked_days.py#L51)).

**One rate per slip (why independent second rates need code):** on a `monthly` slip **every** line — including `is_extra_hours` ones — prices at the *derived* rate `wage ÷ non-extra hours`; `version.hourly_wage` is never read outside the `wage_type == 'hourly'` branch. Example: wage 1,800 over 176h → an extra 42h line pays 42 × 10.23 = 429.55 in stock; paying it at an independent 15 GEL/h (630.00) is only possible via an override (§8 routing) or a salary rule.

---

## 3. Where worked time can come from

| `work_entry_source` | Module | Mechanism |
|---|---|---|
| `calendar` (default) | `hr_work_entry` (community) | Theoretical schedule intervals; deterministic ("static", [`hr_version.py:386-390`](../addons/hr_work_entry/models/hr_version.py#L386)) |
| `attendance` | `hr_work_entry_attendance` + `hr_payroll_attendance` (enterprise) | Real check-in/outs become work entries ([`hr_version.py:116-186`](../enterprise/hr_work_entry_attendance/models/hr_version.py#L116)); approved `hr.attendance.overtime.line` records become OVERTIME-type entries, rate picked from the overtime **ruleset** ([`hr_version.py:199-258`](../enterprise/hr_work_entry_attendance/models/hr_version.py#L199)); approval/refusal triggers work-entry regeneration ([`hr_attendance_overtime.py:12-32`](../enterprise/hr_work_entry_attendance/models/hr_attendance_overtime.py#L12)) |
| `planning` | `hr_work_entry_planning` (enterprise) | Published `planning.slot` records become work entries ([`hr_version.py:37-56`](../enterprise/hr_work_entry_planning/models/hr_version.py#L37)) |
| timesheets | — | **No bridge exists.** Zero references between `hr_timesheet`/`account.analytic.line` and payroll/work entries in community or enterprise (grep-verified). Timesheet-driven pay is 100% custom development. |

---

## 4. Salary scheme matrix

| Scheme | Standard? | How |
|---|---|---|
| 1. Fixed | Yes — config only | `wage_type='monthly'`, source `calendar`. Unpaid leave auto-prorates via work entry types. |
| 2. Hourly | Yes — config only | `wage_type='hourly'` + `hourly_wage`; source `calendar` (pays schedule) or `attendance` (pays actual presence). |
| 3. Daily | **No** — development | Options in §5. Config-only approximation: `hourly_wage = day_rate / hours_per_day` — only exact when every day has equal hours. |
| 4. Fixed + hourly | Only one shape standard | Fixed wage + hourly-paid **overtime** works out of the box (attendance overtime rulesets; `is_extra_hours` keeps the fixed part undiluted). Any other hourly component on top of fixed = development (§6). |
| 5. Fixed + daily | **No** — development | §6. |
| 6. Hourly + daily | **No** — development | §6. |

---

## 5. Implementing a daily rate (development pattern)

Sanctioned extension points, proven by existing localization overrides:

1. `selection_add=[('daily', 'Daily Wage')]` on **both** `hr.payroll.structure.type.wage_type` and `hr.version.wage_type` (+ `ondelete`), plus a `daily_wage` Monetary on `hr.version`. Precedent: [`l10n_ch_hr_payroll/models/hr_version.py:216`](../enterprise/l10n_ch_hr_payroll/models/hr_version.py#L216).
2. Override `_compute_amount` on `hr.payslip.worked_days`: `amount = daily_wage × number_of_days × amount_rate`. Six modules already override this method the same way (BE, HK, LU, MX, AU + a stub), e.g. Hong Kong computes a per-day wage: [`l10n_hk_hr_payroll/models/hr_payslip_worked_days.py:28-45`](../enterprise/l10n_hk_hr_payroll/models/hr_payslip_worked_days.py#L28). Copy the guard style (`edited`/state check, country/struct filter) and extend `@api.depends` with the new fields.
3. Derived-rate alternative (no new wage_type): keep `monthly` and compute a daily rate in rules — Mexico derives `l10n_mx_daily_salary = wage / days-per-schedule-table` ([`l10n_mx_hr_payroll/models/hr_payslip.py:13-21`](../enterprise/l10n_mx_hr_payroll/models/hr_payslip.py#L13)); Hong Kong computes a statutory 12-month average daily wage ([`l10n_hk_hr_payroll/models/hr_payslip.py:83-121`](../enterprise/l10n_hk_hr_payroll/models/hr_payslip.py#L83)).

Daily-specific hazards: `number_of_days` is **derived** (`hours / hours_per_day`, rounded per work-entry-type `round_days`, remainder shifted to the biggest line — [`hr_payslip.py:850-859`](../enterprise/hr_payroll/models/hr_payslip.py#L850)); half-days ([`_is_half_day`](../enterprise/hr_payroll/models/hr_payslip_worked_days.py#L58)); employees with **no calendar** are "fully flexible" in v19 and `hours_per_day` collapses → days = 0.

---

## 6. Implementing combinations (development patterns)

Standard model = one `wage_type`, one rate path per payslip. Three viable designs:

**A. Salary-rule layer (least invasive).** Keep `wage_type='monthly'` for the fixed part (BASIC), add `x_hourly_rate` / `x_daily_rate` on `hr.version`, mark the hourly/daily-paid work entry types `is_extra_hours=True` (or list them in `struct.unpaid_work_entry_type_ids`) so the fixed wage is not diluted, and add ALW-category rules like `result = worked_days['X123'].number_of_hours * version.x_hourly_rate` (v19: `worked_days` is a plain dict keyed by code — attribute access `worked_days.X123` does not work, see §8.3 #4). No core override; weakness: worked-days lines for those types show amount 0 (or a wrong amount) and the real money appears only in rule lines.

**B. Route rates per work entry type (robust general solution).** Override `_compute_amount` with a rate-resolution helper: work entry types tagged "daily-paid" → `daily_wage × days`, "hourly-paid" → `hourly_wage × hours`, rest → standard fixed proration restricted to fixed-pool hours. Keeps worked-days lines truthful, survives `payslip.paid_amount`/BASIC untouched. This is the pattern the six l10n overrides legitimize.

**C. Wage-components model (Swiss pattern — the only standard multi-component precedent).** `hr.version` holds `wage` + `hourly_wage` + more simultaneously; a payslip one2many of component lines (`base × rate`) is computed from work entries/leaves and rules consume the components: model [`l10n.ch.swiss.wage.component`](../enterprise/l10n_ch_hr_payroll/models/l10n_ch_worked_days.py#L6), builder [`_compute_l10n_ch_swiss_wage_ids`](../enterprise/l10n_ch_hr_payroll/models/hr_payslip.py#L243) (flags `l10n_ch_has_monthly/has_hourly/has_lesson` decide which components appear). Most powerful, most work; CH effectively sidesteps standard worked-days for its structure.

---

## 7. Gotchas catalog for a custom wage-type module

| # | Gotcha | Anchor |
|---|---|---|
| 1 | **One version per payslip.** `version_id = employee._get_version(date_from)`; pay runs pick the version in force per employee/contract ([`hr_payslip.py:1220`](../enterprise/hr_payroll/models/hr_payslip.py#L1220), [`hr_payslip_run.py:120-171`](../enterprise/hr_payroll/models/hr_payslip_run.py#L120)). A mid-month rate/type change is **not** auto-prorated into two slips — the whole period computes at one version's rates. |
| 2 | `wage_type` is a stored compute from structure type — user-set values are wiped when structure type changes; your selection_add must exist on both models. |
| 3 | `_compute_amount` skips `edited` / non-draft slips; your override must too, and new rate fields must be in `@api.depends`. |
| 4 | Fixed-wage dilution: non-`is_extra_hours` paid types enter the proration denominator ([`hr_payslip_worked_days.py:51`](../enterprise/hr_payroll/models/hr_payslip_worked_days.py#L51)). |
| 5 | Attendance source is volatile: entries regenerate on overtime approval/refusal; the generation cron only covers current month → end of next month; attendance edits after compute need a worked-days recompute. Version `ruleset_id = NULL` → zero overtime (see [`attendance_work_entry.md`](attendance_work_entry.md)). |
| 6 | Work-entry conflicts block **pay-run generation**, but an individual slip can silently exclude conflict hours and confirmation can ignore failed validation. Add an explicit custom blocker (see [`hr_payroll.md`](hr_payroll.md) Work Entries). |
| 7 | Timesheet-driven pay: still zero standard bridge, but **the "must invent datetimes" claim is obsolete** — v19 `hr.work.entry` is day-based (`date` + `duration`, [work_entries.md](work_entries.md)), the same shape as a timesheet line. A bridge only needs type mapping, a validation gate (`validated` flag from `timesheet_grid`), and dilution handling (`is_extra_hours`). Alternative with no bridge at all: a salary rule can query timesheets directly — rule code runs in safe_eval with real recordsets and `payslip.env['account.analytic.line'].search(...)` is a sanctioned pattern (official precedent: UAE EOS rule, [`hr_salary_rule_regular_pay_data.xml:268`](../enterprise/l10n_ae_hr_payroll/data/hr_salary_rule_regular_pay_data.xml#L268)). |
| 8 | Turning off `struct.use_worked_day_lines` makes BASIC = raw contract wage ([`hr_payslip.py:1647`](../enterprise/hr_payroll/models/hr_payslip.py#L1647)) — you lose all leave/entry proration and must rebuild it in rules. |
| 9 | Out-of-contract periods get a dedicated worked-days line ([`hr_payslip.py:883-909`](../enterprise/hr_payroll/models/hr_payslip.py#L883)); code `OUT` is forced to amount 0 — handle it in any override. |
| 10 | `hr_payroll` is **enterprise**; community-only deployments need OCA payroll (different API — none of the above applies). No `l10n_ge` payroll exists, so a Georgian setup defines its own structure type/structure/rules — fewer conflicts, but nothing to reuse. |
| 11 | Flexible-schedule employees (empty `resource_calendar_id`) break `hours_per_day`-based day counting — a daily wage type must special-case them. |
| 12 | Schedule-flavor payroll outcomes: **flexible calendar** (quota + hours/day, both manually entered) + calendar source generates *invented* entries filling the quota — monthly always pays full wage (leaves still prorate), but `hourly` pays the **quota, not actual work** (use attendance source for hourly). **Fully flexible** (empty calendar) + calendar source = **silently zero payslip** (no entries generated, payslip skips generation for calendar-less versions, banner-only warning); + attendance source + monthly = all-or-nothing (any entry → full wage, none → 0; leaves can't prorate since leave entries also need a calendar for duration). Details: [work_entries.md](work_entries.md), [resource_calendars.md](resource_calendars.md). |

---

## 8. Design decision — how to build it (2026-07-04, 24-agent workflow, adversarially verified)

Three candidate architectures were designed independently, 16 difficulties were confirmed against source by adversarial verifiers (0 refuted), and a judge scored the designs:

| Design | Score | Verdict |
|---|---|---|
| A — salary-rule layer, zero overrides (components as `is_extra_hours` + struct-unpaid types, money in rule lines) | 5.5 | Rejected: correctness rests on 3 undocumented stock behaviors; component worked-days lines show 0.00; pure daily = `hourly` with rate 0 hack; formula logic lives in noupdate DB data |
| B — `_compute_amount` override with per-work-entry-type rate routing + `daily` wage_type | 7.5 | **Winner (as hybrid)** |
| C — Swiss-style wage-components model | 6 | Rejected: its combo-coverage edge is refuted by the WORK100 hardcode (§8.2 #2), leaving only the highest maintenance surface (parallel money model, `paid_amount` reroute) |

**Chosen: "B+ hybrid"** — Design B (selection_add `('daily','Daily Wage')` on **both** `hr.payroll.structure.type` and `hr.version` + `daily_wage` field + a `paid_at` routing Selection (`fixed_pool|hourly|daily`) on `hr.work.entry.type` + filtered-super override of [`_compute_amount`](../enterprise/hr_payroll/models/hr_payslip_worked_days.py#L39) following the l10n_hk pattern + [`_get_contract_wage_field`](../enterprise/hr_payroll/models/hr_version.py#L203) override) **plus** Design A's data pack (own OT work entry types 125/150/200% with `is_extra_hours=True`, two overtime rulesets, structure type with `default_struct_id` set) **plus** in-override day derivation — never pay off `number_of_days`. Effort ≈ 4–5 dev-days incl. tests. Roadmap (9 steps): skeleton/fields → amount override with safe day math → consumer-chain overrides (`_get_contract_wage_field`, payslip PDF header) → data pack → constraints/config guards → staleness+approval-order gate → views → 6-scheme × source × event test matrix → go-live migration tooling.

### 8.2 Additional verified gotchas (beyond §7; all CONFIRMED with file:line by independent verifiers)

| # | Gotcha | Evidence | Consequence for the module |
|---|---|---|---|
| 1 | `number_of_days` is display-grade: `round(hours/hours_per_day, 5)`, per-type `round_days` (default `NO` = raw float), cross-type rounding remainder dumped on the biggest line | [`hr_payslip.py:845-870`](../enterprise/hr_payroll/models/hr_payslip.py#L845) | Daily pay must derive payable days from `number_of_hours` with an agreed rounding policy — inside the override |
| 2 | **All attendance-sourced presence lands on ONE hardcoded work entry type** (`WORK100`, `env.ref` at generation) | [`hr_work_entry_attendance/models/hr_version.py:199-221`](../enterprise/hr_work_entry_attendance/models/hr_version.py#L199) | Attendance cannot split one person's time into hour-paid vs day-paid; mixed schemes need the day-paid part as separately entered work entries (manual step) |
| 3 | Standard `OVERTIME` type ships `is_extra_hours=False`, `amount_rate=1.0`; every version auto-attaches the default ruleset → fixed+overtime silently adds 0.00 | [`hr_work_entry_type_data.xml:11-16`](../addons/hr_work_entry/data/hr_work_entry_type_data.xml#L11), [`hr_attendance/models/hr_version.py:17-23`](../addons/hr_attendance/models/hr_version.py#L17) | Ship own OT types + rulesets; install-check that defaults aren't in use |
| 4 | `sum` rate-combination rulesets emit one **full-duration** work entry per paid rule over the same interval — hours double by design | [`hr_work_entry_attendance/models/hr_version.py:222-257`](../enterprise/hr_work_entry_attendance/models/hr_version.py#L222) | Configure extra-percentage-only rates or `max` mode; validate ruleset config |
| 5 | Any attendance edit wipes and recreates the whole Mon–Sun week of overtime lines as `to_approve` — approvals destroyed, approved OT vanishes from pay until re-approved | [`hr_attendance.py:314-326`](../addons/hr_attendance/models/hr_attendance.py#L314) | Monthly order-of-operations runbook: corrections → approvals → compute |
| 6 | OT approve/refuse after payslip compute: draft slips stay silently stale; validated periods get conflict-marked duplicate entries and the OT is never paid | [`hr_attendance_overtime.py:12-32`](../enterprise/hr_work_entry_attendance/models/hr_attendance_overtime.py#L12) | Staleness gate: block/warn on confirming a slip whose period's work entries changed after compute |
| 7 | Work-entry tamper-lock after validation applies **only** when the slip's structure == structure type's `default_struct_id` | [`hr_payslip.py:600`](../enterprise/hr_payroll/models/hr_payslip.py#L600) | Always set `default_struct_id`; avoid multi-structure-per-type setups |
| 8 | Switching `work_entry_source` (or calendar) after validated payslips regenerates **nothing** — a calendar→attendance go-live silently no-ops | [`hr_version.py:660-691`](../addons/hr_work_entry/models/hr_version.py#L660) | Go-live server action comparing declared source vs actual entry provenance |
| 9 | Every `wage_type` consumer is a binary `== 'hourly'` branch — a new `daily` value falls into the monthly path everywhere (worked-days amount, `_get_contract_wage_field`, payslip PDF header prints the raw key) | [`hr_payslip_worked_days.py:48`](../enterprise/hr_payroll/models/hr_payslip_worked_days.py#L48), [`report_payslip_templates.xml:65`](../enterprise/hr_payroll/views/report_payslip_templates.xml#L65) | The two overrides must land **together** with the selection_add; inherit the PDF header |
| 10 | `_compute_wage_type` is an **unguarded** stored compute (contrast: `_compute_schedule_pay` has an `if` guard) — structure-type change wipes a custom value. Version-copy leg of the original claim was refuted (PARTIAL) | [`hr_version.py:66-69`](../enterprise/hr_payroll/models/hr_version.py#L66) | selection_add on the structure type makes `daily` a first-class value the compute can carry |
| 11 | The monthly denominator **is** the proration engine: OUT + unpaid hours inflate it on purpose; `or 1` fallback when empty | [`hr_payslip_worked_days.py:51-55`](../enterprise/hr_payroll/models/hr_payslip_worked_days.py#L51) | The restricted "fixed pool" must keep OUT/unpaid hours in its denominator or mid-month hires overpay |
| 12 | Mid-month same-contract version change: pay run slips **only the old version** — the post-switch half of the month is silently unpaid (worked-days on the new-version days zero out via `version_id` mismatch) | [`hr_payslip_run.py:154-159`](../enterprise/hr_payroll/models/hr_payslip_run.py#L154) | Policy + onchange warning: scheme/rate changes effective the 1st only |

23 lower-severity findings were logged but not verified (see workflow output): notable themes — contract-template hiring whitelist drops custom fields (even `hourly_wage`), `hr_contract_salary` configurator hardcodes monthly|hourly, all rates hardwired to company currency, and copying the l10n_ch `ondelete='cascade'` selection_add verbatim would delete employee versions on module uninstall. ~~use `'set default'`~~ **Corrected 2026-07-12 (§8.3 #1): `'set default'` crashes at registry load — use `ondelete={'daily': 'set monthly'}`.**

### 8.3 Plan double-check findings (2026-07-12, 4 verification agents + direct reads, all file:line-confirmed)

Corrections and additions found while verifying [PAYROLL_WAGE_TYPES_PLAN.md](../PAYROLL_WAGE_TYPES_PLAN.md) — two break the plan as written:

| # | Finding | Evidence | Consequence |
|---|---|---|---|
| 1 | **`ondelete='set default'` crashes at registry load** — `hr.version.wage_type` has no `default=`; the ORM asserts `self.default is not None` for that policy. `hr.payroll.structure.type.wage_type` is `required=True, default='monthly'`, so an explicit ondelete dict is mandatory there | [fields_selection.py:148-153](../odoo/orm/fields_selection.py#L148), [hr_version.py:42-45](../enterprise/hr_payroll/models/hr_version.py#L42), [hr_payroll_structure_type.py:38-41](../enterprise/hr_payroll/models/hr_payroll_structure_type.py#L38) | Use `ondelete={'daily': 'set monthly'}` on **both** models (l10n_ch instead injects `default="monthly"` into the version field — also viable) |
| 2 | **Employees cannot open `hr.employee` at all** — no ACL row for `base.group_user`; `get_views` raises a RedirectWarning to `hr.employee.public`; "My Profile" opens a `res.users` preferences dialog whose employee fields pass through `SELF_READABLE_FIELDS` | [ir.model.access.csv:4-6](../addons/hr/security/ir.model.access.csv#L4), [hr_employee.py:1183-1202](../addons/hr/models/hr_employee.py#L1183), [res_users.py:249-262](../addons/hr/models/res_users.py#L249) | A work-log page on the employee form is HR-only. Employee self-service needs its own menu/action on the custom model (default `employee_id` from `user.employee_id`, ACL + own-records rule) — the hr_expense/hr_leave pattern |
| 3 | `edited=True` does **not** protect salary-rule lines from `compute_sheet` — it only stops worked-days `_compute_amount` and excludes the slip from `action_refresh_from_work_entries`; `compute_sheet` has no edited check and wipes/recreates `line_ids` | [hr_payslip.py:785-802](../enterprise/hr_payroll/models/hr_payslip.py#L785), [hr_payslip.py:809](../enterprise/hr_payroll/models/hr_payslip.py#L809), [hr_payslip_worked_days.py:41](../enterprise/hr_payroll/models/hr_payslip_worked_days.py#L41) | Any compute_sheet override runs on edited slips too — guard; "edited freezes amounts" only holds for worked days |
| 4 | Rule-eval `worked_days` is a **plain dict** `{code: line}` — `worked_days['WORK100'].number_of_hours`, not `worked_days.WORK100`; `payslip` is a real recordset and `payslip.env[...].search(...)` is legal in safe_eval (stock precedents: l10n_ae EOSP, l10n_us, l10n_pl) | [hr_payslip.py:1030](../enterprise/hr_payroll/models/hr_payslip.py#L1030), [hr_salary_rule.py:188](../enterprise/hr_payroll/models/hr_salary_rule.py#L188), [l10n_ae rule:268](../enterprise/l10n_ae_hr_payroll/data/hr_salary_rule_regular_pay_data.xml#L268) | Write rule code with dict access; `.get(code, empty)` for optional lines |
| 5 | The recompute bug is precisely located: `_get_fields_that_recompute_payslip` returns `[self._get_contract_wage]` — a **bound method** — while `write()` compares it to string keys, so wage/hourly_wage edits never refresh draft slips; l10n overrides (BE, HK) prove the intended contract is field-name strings | [hr_version.py:278-280](../enterprise/hr_payroll/models/hr_version.py#L278), [hr_version.py:314-317](../enterprise/hr_payroll/models/hr_version.py#L314) | Override returning `['wage', 'hourly_wage', 'daily_wage', 'wage_type']` fixes it with zero core patching. Note `_recompute_payslips` only refreshes `is_regular` draft slips |
| 6 | Claim-on-compute has a stock precedent with a different hook: `hr_payroll_expense` claims at payslip **create** + `action_payslip_draft` (`clear_existing=False`, candidates filtered `payslip_id = False`), releases in `action_payslip_cancel`, and relies on m2o set-null for slip deletion | [hr_payroll_expense/models/hr_payslip.py:68-109](../enterprise/hr_payroll_expense/models/hr_payslip.py#L68) | Claiming in compute_sheet is still fine for late approvals but must be idempotent (fires ≥2× per batch: generate + confirm, on the whole recordset) and must also claim in `action_payslip_draft`; release covers cancel-from-paid (allowed in stock) |
| 7 | Payslip states in v19: `draft / validated / paid / cancel` only; `compute_sheet` is NOT called on payslip create — triggers are the form button, `action_validate`, batch generate + batch confirm, refresh-from-entries | [hr_payslip.py:66-70](../enterprise/hr_payroll/models/hr_payslip.py#L66), [hr_payslip_run.py:407-409](../enterprise/hr_payroll/models/hr_payslip_run.py#L407) | Lifecycle hooks for claim/release: compute_sheet (set-based, no ensure_one), action_payslip_draft, action_payslip_cancel; draft-slip unlink auto-releases via set-null FK |
| 8 | "Conflicts block payslips" is batch-only: `generate_payslips` hard-fails; single-slip `compute_sheet` silently **excludes** conflict entries from pay (`state in ('draft','validated')` domain), and `action_payslip_done` ignores `action_validate()`'s failure | [hr_payslip_run.py:384-391](../enterprise/hr_payroll/models/hr_payslip_run.py#L384), [hr_version.py:216-223](../enterprise/hr_payroll/models/hr_version.py#L216) | Off-batch slips can silently underpay while entries sit in conflict — the staleness/warning guard should count conflict entries too |
| 9 | "Stock OVERTIME pays 0.00" precisely: the line shows a positive amount but adds zero on top for monthly wage (non-extra hours enlarge the denominator → total = contract wage exactly); for hourly it pays straight time, no premium | [hr_payslip_worked_days.py:51-56](../enterprise/hr_payroll/models/hr_payslip_worked_days.py#L51), [hr_work_entry_type_data.xml:11-16](../addons/hr_work_entry/data/hr_work_entry_type_data.xml#L11) | Wording only; the design conclusion (own OT types or rule lines) stands |
| 10 | `contract_wage` stored compute depends only on `wage` (+`wage_on_signature` via hr_contract_salary) — `hourly_wage` was never added upstream, so it's stale for hourly employees; a `daily` type inherits this gap | [hr_version.py:448-451](../addons/hr/models/hr_version.py#L448) | Either extend the depends for `daily_wage`/`hourly_wage` or avoid reading stored `contract_wage` in custom code (use `_get_contract_wage()`) |
| 11 | Dashboard warnings are data records: `hr.payroll.dashboard.warning` with `evaluation_code` safe_eval'd (`mode='exec'`) with `self` = empty payslip recordset; output vars `warning_count/warning_records/warning_action` — one XML record per custom warning, no override | [hr_payroll_dashboard_warning.py:7-28](../enterprise/hr_payroll/models/hr_payroll_dashboard_warning.py#L7), [hr_payslip.py:1839-1853](../enterprise/hr_payroll/models/hr_payslip.py#L1839) | Phase 6 warnings are cheap; beware: one broken warning kills the whole panel |
| 12 | Timesheet facts for the rule path: `validated` flag is enterprise `timesheet_grid`; programmatic create needs `project_id` (or `task_id`) + resolvable active employee, else ValidationError; leave approval creates its own internal-project timesheet lines via sudo (never validates them, never touches work timesheets) | [account_analytic_line.py:25](../enterprise/timesheet_grid/models/account_analytic_line.py#L25), [hr_timesheet.py:212-334](../addons/hr_timesheet/models/hr_timesheet.py#L212), [project_timesheet_holidays/hr_leave.py:13-66](../addons/project_timesheet_holidays/models/hr_leave.py#L13) | OT-approve timesheet generation needs a configured project and an `employee_id`; leave-generated internal lines must be excluded from any timesheet-pay rule (filter by project or `holiday_id = False`) |

Also re-confirmed directly: the l10n_hk `_compute_amount` override is a faithful Phase-2 template including in-override day derivation ([l10n_hk_hr_payslip_worked_days.py:11-47](../enterprise/l10n_hk_hr_payroll/models/hr_payslip_worked_days.py#L11)); rule code technically *can* write/create via method calls but zero stock rules do (rules re-run on previews/recomputes) — keep claims out of rule code.

## 9. Worked examples — how each schedule × wage type × source actually pays

> Added 2026-07-12. The connected walkthrough behind the facts in §2/§7. Mental model: **the payslip is a calculator that reads one table — work entries.** A work entry = "employee, date, type, hours". Schedules, badges, and leaves exist only to fill that table; salary = pricing its rows. Entries appear at exactly three moments: the nightly cron (this month + next), leave approval (replaces the day's entries), payslip creation (auto-fills its own period).

### 9.1 Fixed schedule + monthly wage (the default case)

Employee: Mon–Fri 8h schedule, wage 2,200; month = 22 working days = 176 scheduled hours. Nightly cron creates "Attendance 8h" per scheduled day; approving 1 sick day + 2 unpaid days *replaces* those entries.

| Work entries | Days | Hours | Payslip amount |
|---|---|---|---|
| Attendance | 19 | 152 | 152 × 12.50 = 1,900.00 |
| Sick (rate 100%) | 1 | 8 | 8 × 12.50 = 100.00 |
| Unpaid (rate 0%) | 2 | 16 | 0.00 |
| | | 176 | **BASIC 2,000.00** |

Rate = `2200 ÷ 176 = 12.50` — the wage divided by **all** hours in the table. Full month → exactly 2,200. The schedule's whole payroll role for salaried people: define the "full month" the wage divides by, so absences deduct fairly.

### 9.2 Hourly wage — the source decides what "hours" means

| Source | Pays | Notes |
|---|---|---|
| calendar (fixed schedule) | scheduled hours × rate | presence never checked |
| calendar (**flexible** schedule) | the **invented quota** × rate | almost never intended — use attendance |
| attendance | badge hours × rate | no entry = no pay; forgotten check-out = silently ignored hours |

Badge example, 12 GEL/h: 158 attended hours + 1 approved sick day → Attendance 158 × 12 = 1,896 + Sick 8 × 12 = 96 → BASIC 1,992. Every line is `hours × hourly_wage × amount_rate`, no proration.

### 9.3 Flexible schedule ("40h/week") + monthly wage

The calendar has no slots — only `hours_per_day` (8) and the weekly quota (40), both **typed manually**. Generation *invents* entries: fills each day with 8h until 40h per rolling week, so the table ends up looking exactly like §9.1's (≈176h/month) even though the employee works whenever. Consequences: full wage every month, leaves prorate normally (1 unpaid day = −8 × rate), the clock is never checked. The two manual numbers are the raw material of the payslip — `hours_per_day = 0` breaks day math.

### 9.4 Fully flexible (Working Hours empty) — the trap matrix

No calendar → nothing to invent from → **zero entries** from calendar generation (duration-0 vals dropped), and the payslip skips generation for calendar-less versions entirely:

| + wage type / source | Result |
|---|---|
| monthly + calendar source | **BASIC 0, silently** (banner-only warning) |
| monthly + attendance source | all-or-nothing: any badge entry → full wage; none → 0; leaves can't prorate |
| hourly + attendance source | the one sane combo: all badge hours × rate |

### 9.5 Where each kind of money appears on the payslip

The payslip form has three money surfaces; nothing ever moves between them:

| Surface | Fed by | Needs a work entry type? |
|---|---|---|
| **Worked Days** tab | work entries, one line per type; readonly projection (no add/delete) | yes |
| **Salary Inputs** tab | `hr.payslip.input` (manual one-offs, attachments, expense/commission injections) | no |
| **Salary Computation** tab | salary rules — BASIC (= Σ Worked Days) + every other rule line | no |

Timesheet-paid amounts have no work entry → they can *only* appear as Salary Computation rule lines. That's a structural fact, not a styling choice.

### 9.6 Worked Days tab per scheme — stock vs with our module

Hourly + daily technician (12/h badge + 100/day site missions, 148h attended, 5 site days, 1 sick day):

| Type | Days | Hours | Stock amount | With routing (§8) |
|---|---|---|---|---|
| Attendance | 18.50 | 148:00 | 1,776.00 | 1,776.00 |
| Site Day | 5.00 | 40:00 | **480.00** (40h × 12 — wrong rate) | **500.00** (5 × 100) |
| Sick | 1.00 | 8:00 | 96.00 | 96.00 |

Fixed 1,800 + extra hours entered as `is_extra_hours` entries (42h at intended 15/h):

| Type | Hours | Stock amount | With routing |
|---|---|---|---|
| Attendance + Sick | 176:00 | 1,800.00 | 1,800.00 |
| Extra Hours | 42:00 | **429.55** (derived 10.23/h — §2 one-rate rule) | **630.00** (42 × 15) |

These two tables are the entire justification for the §8 override: stock prices every line of one slip from a single rate.

### 9.7 Timesheet-paid components (the no-work-entry road)

Flow: employee logs hours on tasks (Timesheets app) → PM validates (the pay gate — unvalidated pays nothing) → payslip rule sums validated lines in the period × rate (§7.7 pattern).

Fixed 1,800 + 15/h, 42 validated hours: Worked Days shows only the fixed engine (Attendance 176h → 1,800); Salary Computation shows BASIC 1,800 + "Timesheet hours 42 × 15 = 630" → GROSS 2,430. Dilution is impossible — the hours never enter the worked-days denominator.

Purely timesheet-paid (14/h, own structure with presence types unpaid): Attendance 176h → **0.00**, Sick 8h → 112 (leaves still pay!), rule line 130 × 14 = 1,820 → GROSS 1,932. The schedule survives only to make leave behavior correct.

Boundary rule: hours validated after compute are missed by a date-window rule — either enforce "validate → then compute" in the runbook, or link consumed records to the payslip (claim-on-compute pattern) so late approvals roll into the next slip.

## 10. Module shopping list per scheme

| Need | Modules |
|---|---|
| Any payroll at all | `hr_payroll` (enterprise) + `hr_work_entry` (auto) |
| Pay actual presence / overtime | `hr_attendance` + `hr_work_entry_attendance` + `hr_payroll_attendance` |
| Pay planned shifts | `planning` + `hr_work_entry_planning` + `hr_payroll_planning` |
| Leave-aware payslips | `hr_holidays` + `hr_work_entry_holidays` (+ `hr_payroll_holidays`) |
| Timesheet-driven pay | no standard module — custom bridge (§7.7) |
| Accounting entries from payslips | `hr_payroll_account` |

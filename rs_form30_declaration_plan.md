# rs.ge Form №30 — Monthly Withholding Declaration Export (Plan)

> **Status:** IMPLEMENTED 2026-09-02 as `custom_addons/gec_extra_modules/gec_income_tax_report/gec_income_tax_report` (trimmed v1.0: paid_date instead of the payment chain, no control tab / prefill screen, salary rows default to 1.1/Georgia with a warning) — see [gec_income_tax_report.md](gec_income_tax_report.md). Code not yet installed or run. Research verified from source 2026-09-01.
> **Review round 2026-09-01 (external cross-review, corrections verified from source and applied):** relief-formula sign fixed (release blocker — PIT line is negative, ADV_PIT_PRE positive); rate rules normalized to one-per-rate with validity; category/residency made human-approved defaults (nationality ≠ tax residency); salary rows switched to one-per-payment-event; FX simplified to payment-date conversion of line amounts (+ per-payment move cross-check); 0% WHT tax dropped (stock resets the flag for `amount >= 0`); new WHT taxes + dividend-procedure change re-phased to v1.1 behind accountant sign-off (D3); GL control made source-based, not calendar-month.
> **Goal:** generate the annex file ("დანართი ა — ინფორმაცია გაცემული განაცემებisa და დაკავებული გადასახადის შესახებ") of the monthly declaration "გადახდის წყაროსთან დაკავებული გადასახადის დეკლარაცია" (rs.ge internal form 30), which the accountant uploads on eservices.rs.ge.
> **Domain reference:** [`sashemosavlo_deklaraciebi_sruli_cnobari.md`](../sashemosavlo_deklaraciebi_sruli_cnobari.md) — form rules, classifiers, penalties, file format. This plan does not repeat it.

---

## TL;DR

| Question | Answer |
|---|---|
| What do we build? | One new module (suggested: `gec_rs_form30`) with a **declaration model + line model + XML export**. No changes to any existing module. |
| Where does the data come from? | **Three sources, united in one declaration:** (1) payslips (ხელფასი), (2) `account.payment.withholding.line` records (დივიდენდი, პროცენტი, როიალტი, იჯარა, მომსახურება, არარეზიდენტები), (3) manual lines (anything else). |
| Not from the tax report / GL? | Correct — form 30 is **per-person, per-payment, cash-basis**. Tax grids and account balances have no partner/date/person granularity, and payroll PIT lines carry no tax tags at all. Confirmed the wrong path in [geo_payroll.md](geo_payroll.md) §10 and by source. |
| კატეგორია / სახე on res.partner? | **Category — yes** (one new field on partner, auto-suggested). **სახე — no**: it is a property of each payment, not of the person. It comes from the WHT tax used (payments), is fixed to "ხელფასი" (payroll), or picked manually. |
| Upload automation? | File import only. No published Form №30 submission API has been identified; v1 uses portal file import. We generate the exact SpreadsheetML file the portal's "ატვირთვა ფაილიდან" expects. |
| Dividend / stipend gap? | No new accounting *code* needed — both ride the **standard payment + withholding-line** mechanism that already exists (stock `l10n_account_withholding_tax`). But adopting it for dividends/stipends is an **accounting-process decision (D3)**: v1.0 maps existing taxes + manual rows; the 3 missing tax records ship in v1.1 after the accountant signs off. |

---

## 1. The file we must produce (verified from samples)

- Format: **Excel 2003 SpreadsheetML** (single XML file), worksheet named exactly `data`, header row 1, data rows from row 2, **columns read by position**, every cell `ss:Type="String"`, dates `DD.MM.YYYY`, decimals with dot, UTF-8.
- The **import template is 14 columns** (verified from `temp_30_3017_3_1.xml`, portal template last saved 2025-11-05). The 16-column layout exists only in **exports** — the two extra columns (employee pension contribution, withheld tax) are computed by the portal (matches the lock icons on those columns in the web grid).

| # | Column | Source in Odoo |
|---|---|---|
| 1 | პ/ნ (11 digits person / 9 digits company) | partner `vat` / employee `version.identification_id` |
| 2 | სახელი / სამართლებრივი ფორმა | split of partner/employee name (editable on line) |
| 3 | გვარი / დასახელება | same split |
| 4 | მისამართი | partner address / `version.private_city…` |
| 5 | რეზიდენტობა (country code, GE=268) | partner's approved `rs.form30.country` default (classifier model, §4.3) |
| 6 | კატეგორია (classifier ID, e.g. `4` = "1.1 დაქირავებით მომუშავე") | partner/employee category field |
| 7 | განაცემის სახე (classifier ID, e.g. `1` = ხელფასი) | fixed per source (see §5) |
| 8 | განაცემი თანხა (GEL, **gross**) | GROSS+advances (payroll) / WHT base (payments) |
| 9 | სხვა შეღავათი | art. 82 exempt portion (payroll), else 0 |
| 10 | გაცემის თარიღი | real payment date (see §5.1/§5.2) |
| 11 | განაკვეთი (%) | 20 (salary) / `ABS(tax.amount)` (payments) |
| 12 | საერთ. ხელშეკრულებით გათავისუფლებული | manual (non-resident treaty cases) |
| 13 | უცხოეთში გადახდილი ჩასათვლელი | manual |
| 14 | გაცემულია ხაზინიდან | always **empty** for us |

⚠️ **Verification item V1:** the current portal template must be re-downloaded ("ფაილის ნიმუში" button) before first live use and column count/order compared — the generator's column map must be data-driven so a layout change is a config edit, not code.

⚠️ **Verification item V2:** since the import file has **no pension column**, confirm on the first test import what the portal does with the employee 2% (auto-computes? asks in the grid?). Our declaration lines still store the pension amount for control either way.

## 2. Classifiers = data, not code (verified from `30_data_7_202505.xlsx`, v7, period 202505)

- 18 recipient categories (**classifier IDs ≠ display numbers**: ID `4` = "1.1", ID `42` = "4 — უცხო ქვეყნის მოქალაქეები").
- 15 payment types (1 ხელფასი, 2 დივიდენდი, 3 პროცენტი, 5 სტიპენდია, 6 სხვა, 7 მომსახურება, 16 მოგება, 17 როიალტი, 19 იჯარა, 20 ამხანაგობა, 21 დაბრუნებული პენსია, 22/23 თამაშობები, 24 სასტუმრო; 18 defunct since 202412).
- **127 allowed (category × type) combinations, normalized to one rule per rate** — this is the user's "active combinations" requirement. A single `allowed_rates` list per combination cannot express reality: individual rates carry their own validity (gambling 2% ends 202312, 5% starts 202401; salary 5%/12% have separate effective dates/conditions; type 18 dies 202412). Used for (a) period-aware validation before export, (b) defaulting the rate when exactly one is valid for the period.
- 262 RS country codes (not pure ISO — includes RS-specific codes).
- Classifiers are **period-versioned** (rs.ge changes them; changelog in the cnobari §3.5). Model records carry `valid_from`/`valid_to` (YYYYMM) + the classifier file version as source note.

## 3. Source architecture — why these three and nothing else

| Source | Covers სახე | Mechanism (verified) |
|---|---|---|
| **A. Payroll** (`hr.payslip` of geo_payroll) | 1 ხელფასი | GROSS/PIT/PENSION_EE lines + `ADVANCE_PAY` inputs; payment date via NET(3130) payment. §5.1 |
| **B. Payment withholding lines** (`account.payment.withholding.line`, stock module, persisted) | 2, 3, 5, 6, 7, 16, 17, 19 — anything paid via a payment | Stored per payment: `base_amount` (gross!), `amount` (withheld), `tax_id` (→ rate), partner+date on the payment. Works on **standalone payments without a bill** (dividend to a shareholder). §5.2 |
| **C. Manual lines** | anything exotic (ამხანაგობა, corrections, treaty columns) | Free entry in the declaration with matrix validation. |

Rejected alternatives (do not re-litigate):
- **Tax report / tax grids:** aggregates per tag; no person, no date; payroll PIT lines have **no tags/`tax_line_id` at all** ([account_chart_template.py:87-89](../custom_addons/gec_payroll_types/geo_payroll/models/account_chart_template.py#L87) keeps PIT on non-reconcilable 3320, settled "through the tax flow"). Also stated in [geo_payroll.md](geo_payroll.md) §10.
- **GL balances (3320):** 3320 mixes three streams — payroll PIT, resident WHT taxes (`gec_l10n_ge_tax` credits 3320 for res. dividends/interest/royalty), advance prepaid PIT legs (1733↔3320). All 33xx are `reconcile=False`. Usable only as a **cross-check total**, never as the row source.
- **`account.return` framework:** aggregate/report-oriented; wrong shape for a per-person annex. Optional thin integration later (deadline card), phase 3.

## 4. New module design

**Name:** `gec_rs_form30` (suggested), at `custom_addons/gec_extra_modules/gec_rs_form30`.
**Depends:** `geo_payroll`, `gec_l10n_ge_tax` (pulls `l10n_account_withholding_tax`, `account`). No `employee_registry_rs` dependency — see D2 (resolved). License OEEL-1 like `gec_l10n_ge_tax`.
**Target stack (D1):** `gec_modules_hr3` — **the local test/development DB** (user 2026-09-01), where `geo_payroll`, `gec_payroll_bank`, `gec_l10n_ge_tax`, `l10n_account_withholding_tax`, `gec_localization`, `basis_bank`, `accountant` are all installed and `employee_registry_rs` is not. Production must run the same stack — **re-run the same `ir_module_module` check on the production DB before deploy** (Phase 0).
**Touches nothing existing** — only additive inherited fields.

### 4.1 Models

| Model | Purpose |
|---|---|
| `rs.form30.category` | classifier data (18) — `code`, `name`, validity |
| `rs.form30.income.type` | classifier data (15) — `code`, `name`, validity |
| `rs.form30.country` | classifier data (262): RS `code`, Georgian name, validity, optional `res_country_id` mapping — see §4.3 |
| `rs.form30.rate.rule` | **one record per (category, type, rate, valid_from, valid_to)** (~150 rows after normalizing the 127 matrix cells) + `requires_manual_review` flag + RS note for conditional rates (e.g. salary 5% = international-company status only); period-aware validation + defaulting |
| `rs.form30.declaration` | company, period (month), state (`draft/ready/exported`), line_ids, control totals, generate/export buttons |
| `rs.form30.line` | all 14 columns as fields + pension amount (control) + computed expected tax (control) + `source` (`payslip/payment/manual`) + traceability m2o (`payslip_id` / `withholding_line_id`) + `warning` text |

### 4.2 Inherited fields (additive only)

| Model | New field | Why |
|---|---|---|
| `res.partner` | `rs_form30_category_id` + `rs_form30_residency_id` (→ `rs.form30.country`) | **Manually approved defaults — never silently assigned.** No Odoo field proves tax residency: `hr.version.country_id` is *nationality*, `private_country_id` is the address country, and the 183-day rule lives outside the system. Generation may *show* a suggestion (individual/company + country hints), but a legal category is committed only by a human — once per partner as the default, overridable per line. Rows with an unset category fail pre-flight; rows where nationality contradicts the category get a warning. Offshore categories (31/32) always manual — no offshore-country list in v1. |
| `account.tax` | `rs_form30_income_type_id` (+ optional `rs_form30_category_hint`) | maps each WHT tax → სახე. Values for the existing 8 taxes filled by `post_init` **only-if-empty** (the configurator pattern already used in this project). |

### 4.3 Country codes — own classifier model `rs.form30.country` (D2 resolved 2026-09-01, refined in review round 2)

A dedicated classifier model (`code`, Georgian name, validity, optional `res_country_id`), loaded from the form-30 classifier's own country sheet (`30_data_7_202505.xlsx`, 262 codes) — that sheet, not the employee-registry list, is the authoritative source for this column. Partner residency defaults point to this model; the declaration line stores the selected classifier code. Export validation blocks rows with no residency code.

Why a model, not a Char field on `res.country`: the DB holds **251 `res.country` records vs 262 RS entries** (verified) — RS-only entries (მულტისავალუტო, გაყოფილი ზონა, უცნობი…) have no `res.country` record to carry a field. The model covers the full classifier, follows the same pattern as the category/type classifiers, and does not touch `res.country` at all. `res_country_id` is mapped in data where a counterpart exists, so `partner.country_id` can pre-fill a *suggestion*.

Why not reuse `employee_registry_rs.rs_country_code`: the module is **not installed in the target DB** (verified via `ir_module_module`), and depending on it would force-install its RS registry models and daily sync cron into the payroll DB for the sake of one field.

### 4.4 Missing WHT taxes — added inside `gec_l10n_ge_tax` (D7, user 2026-09-01), no migration scripts

> **DONE 2026-09-02 (gec_l10n_ge_tax 19.0.1.1.0):** 7 taxes shipped — resident services 20% (1.2.1) and 5% (1.2.2), resident residential rent 5%, stipend 20% → 3320; offshore royalties / interest / services 15% (3.1/3.2) → 3310.02. Loaded only-if-missing by `_ge_tax_apply_maintenance` on `-u`. The two note items "resident royalties 5% → 3310.01" and "non-resident royalties 20% → 3310.02" were **not** created: neither combination exists in the v7 rate matrix (see §4.5).

**Placement (D7):** the user decided the new tax records live in `gec_l10n_ge_tax` itself, not in the form-30 module. Mechanism — the module's own established pattern, **no `migrations/` directory**: add the taxes to the `@template('ge', 'account.tax')` dicts (new installs get them automatically) and extend the existing `_ge_tax_apply_maintenance` upgrade pass (it already reruns on every `-u`) to load **only the taxes whose xmlid does not exist yet** into installed ge companies. The only-if-missing check is load-bearing: re-running `_load_data` on an existing tax **duplicates its repartition lines** (documented landmine, verified 2026-06-28). The form-30 module then only sets `rs_form30_income_type_id` on them.

`gec_l10n_ge_tax` currently ships 8 payment-time WHT taxes ([account_chart_template.py:178-233](../custom_addons/gec_extra_modules/gec_l10n_ge_tax/models/account_chart_template.py#L178)): non-resident dividends/interest/royalty 5%, mgmt 10%, rent 20% → `3310.02`; resident dividends 5%, interest 5%, royalty 20% → `3320`. Missing for form 30 practice, to be added as data in the new module (same `rep()`-style repartition, negative percent, `is_withholding_tax_on_payment=True`):

| New tax | Rate | Type / Category | Account |
|---|---|---|---|
| WHT 20% — მომსახურება არარეგისტრირებული ფიზ. პირისგან | 20 | 7 / `26` | 3320 |
| WHT 20% — სტიპენდია | 20 | 5 / `4` or `30` | 3320 |
| WHT 5% — იჯარა (საცხოვრებელი, ფიზ. პირი) | 5 | 19 / `27` | 3320 |

**No 0% WHT tax** — stock Odoo actively resets `is_withholding_tax_on_payment` for `amount >= 0` ([account_tax.py:36-40](../addons/l10n_account_withholding_tax/models/account_tax.py#L36)); a data-loaded 0% record would be silently stripped on the first UI edit. Treaty-exempt declarable payments = **manual lines** (D5 resolved).

**Phasing:** these tax records are an accounting-process change, not reporting — they ship as a **`gec_l10n_ge_tax` update alongside form-30 v1.1** (D3 **accepted by user 2026-09-01**; brief the accountant before the first dividend/stipend under the new procedure). Form-30 v1.0 works without them: those payments enter as manual lines.

### 4.5 Manager's category→tax worksheet (2026-09-01) — recorded as a NOTE, not confirmed

The user and their manager drafted a mapping of recipient categories to existing/new WHT taxes. Per the user's own instruction it is **not confirmed and must not drive the logic yet**. Checked against the official 127-row rate matrix, it contains real errors that must be resolved in the accountant round before any tax is created:

| Worksheet claim | Check against the official matrix / design |
|---|---|
| 1.1 employed → "WHT 20% Resident Royalties" | Salary never goes through payment WHT — it is the **payroll source** (PIT rule). No tax needed or usable here. |
| Reusing "…Royalties" taxes for services/deductions/salary because the rate matches | **Do not reuse one tax across different income types.** The whole auto-generation maps tax → სახე; one tax serving salary+services+royalty would label every row "როიალტი" and make the GL unauditable. Rule: one tax per (income type, rate, residency) actually used, named by substance. Rate match ≠ same tax. |
| "Category 4 (უცხო ქვეყნის მოქალაქეები) → WHT 20%" | **Invalid combination.** Display "4" = classifier ID 42, which the matrix allows ONLY type 22 (gambling withdrawals) at 0%. This is the ID-vs-display trap again (classifier ID 4 = category "1.1"). Nothing to create. |
| 3.1 → "WHT 5% Non-res Royalties" | Matrix: 3.1 royalty/interest/services/other = **15%**; only **dividend** is 5%. Either dividends were meant (existing tax) or a 15% offshore tax is needed — clarify. |
| 3.6 / 3.8 (telecom/transport) → "WHT 5% Non-res Royalties" | Matrix: **everything is 10%** for these categories. The existing `nr_mgmt_10` carries the right rate; if these payments actually occur, a dedicated "WHT 10% — international telecom/transport" tax (type 7) is cleaner than reusing mgmt/royalty names. |
| Category 2 → "Interest 5% (res or nr)" | Matrix allows only dividend 5 / interest 5 for resident enterprises. Dividends must use the **dividend** tax (type 2), not interest (type 3) — the type mapping is the point. |
| New tax "WHT 20% — Non-Resident Individual Royalties → 3310.02" | **No such matrix combination exists.** Non-res individual royalty = 5% (3.4) or 15% (3.2). The only 20% rows for non-res individuals are **rent** (covered by existing `nr_rent_20`) and **salary** (payroll). State which სახე is actually meant before creating anything. |
| New tax "WHT 5% — resident (1.2.2 services) → **3310.01**" | Rate and category are right (1.2.2: services/other/rent = 5%). The **account is wrong for the current wiring**: 3310.01 is Profit Tax; all resident-individual WHT posts to **3320** (accountant's own 2026-07-06 decision, and where the existing res taxes post). Recommend 3320; if the accountant now wants 3310.01, that decision must be explicit and consistent. |
| 1.4 note ("benefit deduction withheld 20% regardless of limit") | Parked — this is a payroll/benefit design question, not a payment WHT tax; today `BENEFIT_DED` is post-tax and not a განაცემი. Raise in the accountant round. |

**Resulting candidate tax list for the accountant round** (union of §4.4 and the worksheet, each with its own სახე mapping): resident services 20% (cat 1.2.1, type 7) · resident services 5% and/or rent 5% (cat 1.2.2, types 7/19) · stipend 20% (type 5) · optionally telecom/transport 10% (cats 3.6/3.8, type 7) · optionally offshore 15% set (cats 3.1/3.2) if such payees ever exist. The worksheet's two proposed taxes are **not** created as written — one targets a non-existent combination, the other the wrong account. Rates 15 (offshore), 4 (oil&gas), 3, 2 — not shipped; added only if such payees ever exist.

## 5. Generation rules (the exact math — verified from source)

### 5.1 Salary rows (source A) — one row per paid payslip (= per payment event)

Slip selection: slips whose **NET(3130) payment date** falls in the declaration month — chain `payslip.move_id → account.move.matched_payment_ids → account.payment.date`, filtered to payments reconciled against the slip's NET account (avoids pension-agency payments on 3181/3182). Fallback: `hr.payslip.paid_date` in month **with a warning flag** (paths that fabricate dates: Mark-as-Paid uses `today()`; payment-report wizard uses operator-entered date). Off-cycle advance slips ("GEO Benefits Pay" structure, `is_regular=False`) are included the same way — they have their own NET payment.

**v1.0 gate — one slip, one payment:** a slip is auto-generated only when **exactly one** NET payment settles it. Multiple or partial payments on one slip → the slip is surfaced in a needs-manual list and its row(s) are entered by hand (which date belongs to which amount is an accountant judgement). Proportional auto-allocation is deferred to v1.1.

Per slip (rule codes from [payroll_structure_data.xml](../custom_addons/gec_payroll_types/geo_payroll/data/payroll_structure_data.xml) / [payroll_benefit_data.xml](../custom_addons/gec_payroll_types/geo_payroll/data/payroll_benefit_data.xml)):

```
განაცემი (col 8)      = GROSS line total  +  Σ ADVANCE_PAY input amounts
საპენსიო 2% (control)  = −PENSION_EE line  +  ADV_PEE_PRE line
დაკავებული PIT (control)= (−PIT line)      +  ADV_PIT_PRE line
                          ⚠ signs: the PIT line is NEGATIVE, ADV_PIT_PRE is POSITIVE —
                          withheld = (−PIT) + ADV_PIT_PRE, never −(PIT + ADV_PIT_PRE)
სხვა შეღავათი (col 9)  = (GROSS + ADVANCE_PAY inputs) − taxable,
                         taxable = [(−PIT) + ADV_PIT_PRE] / (0.196 if pension member else 0.20)
                         (= 0 relief when employee has no exemption category — skip inversion entirely)
რეიტი (col 11)         = 20
```

Why this is correct: advance repayment months already have GROSS reduced by the `ADVANCE` rule (ALW seq 29, negative — asserted in [test_benefits.py:219-224](../custom_addons/gec_payroll_types/geo_payroll/tests/test_benefits.py#L219)), and the payout month carries `ADVANCE_PAY` + prepaid PIT/pension legs — so per-slip cash amounts sum to the same yearly totals as accrual. `REPAY_*` lines are balance-sheet closings — **never added** (double count). BONUS is inside GROSS (nothing extra to do). `BENEFIT_DED` is post-tax — irrelevant to the declaration.

Inversion caveats (flagged as line warnings, all amounts editable): rounding ±0.01; `PIT=0` slips (full exemption) take relief = the slip's own consumption of the yearly cap; `pension_fund_member` is non-versioned — cross-check against `PENSION_EE != 0`; `edited=True` slips break the invariant → warning + manual review.

Identity per row: `payslip.version_id.identification_id` (11 digits), name from `employee.legal_name` (split — §6), address from `version.private_city/street`. **Residency and category come from the employee's approved partner defaults** — `employee.work_contact_id.rs_form30_residency_id` / `.rs_form30_category_id` (the same work-contact partner geo_payroll already uses on NET move lines). Nationality (`version.country_id`) is used only to *warn* when it contradicts the approved values — never to assign them. Missing approved values block export; a one-time batch-prefill screen (suggest → accountant confirms) makes setting the ~29 employee defaults a five-minute job.

### 5.2 Payment rows (source B) — one row per withholding line

Selection: `account.payment.withholding.line` of outbound payments with `payment.date` in the declaration month, **payment state `in_process`/`paid` only — never canceled or draft**. This filter is load-bearing: withholding lines survive payment cancellation (verified live 2026-09-01 — a canceled payment kept its base-100/tax-5 line), so without it, canceled payments would produce declaration rows.

```
განაცემი (col 8)  = line.base_amount converted to GEL at payment.date
                    (line amounts are stored in PAYMENT currency; posting used the
                    same payment-date rate, so conversion reproduces the booked GEL)
რეიტი (col 11)     = ABS(tax_id.amount)   — never reconstructed as tax/base (both fields are user-editable)
დაკავებული (control)= line.amount converted the same way
სახე (col 7)       = tax_id.rs_form30_income_type_id
კატეგორია (col 6)  = partner.rs_form30_category_id (human-approved default; line-editable)
თარიღი (col 10)    = payment.date
```

Why conversion instead of reading the posted WH move lines per row: there is **no FK from withholding line to journal item**, and several lines with the same tax merge into one WH-Tax aml — per-line matching is ambiguous by construction. The moves are still used as a **per-payment cross-check** in the control tab (Σ converted line amounts vs the payment move's WH-Tax leg; discrepancy → warning). NBG auto-rates exist for EUR/USD via `nbg_rates`; other currencies need manual rates — limitation L5.

### 5.3 Manual rows (source C)

Free lines validated against the matrix. Used for: ამხანაგობა shares, treaty columns 12/13, one-off cases, and anything paid outside the WHT-line mechanism during the transition period.

### 5.4 Per-type source map — all 15 სახე

The type is **chosen by how the operation is recorded** (which WHT tax sits on the payment); only ხელფასი is structural. Type 18 is abolished from period 202412 — kept in classifier data with `valid_to=202411` for amended old periods only, never generated.

| ID | სახე | Source of the value | Status |
|---|---|---|---|
| 1 | ხელფასი | payslip: GROSS+ADVANCE_PAY / PIT+ADV_PIT_PRE / PENSION_EE+ADV_PEE_PRE; date = NET payment | auto now |
| 2 | დივიდენდი | payment withholding line, existing res/nr dividend 5% taxes — **after D3** (wizard WHT → payment step); until then manual | auto after D3 |
| 3 | პროცენტი | payment withholding line, existing res/nr interest 5% taxes | auto now |
| 5 | სტიპენდია | payment withholding line, **new** 20% tax (v1.1 data, D3 gate) | auto after v1.1 |
| 6 | სხვა | catch-all (3% goods cat 35/40, 15% offshore, 20% other) — rate depends on category | manual |
| 7 | მომსახურება | nr: existing mgmt/technical 10% → auto now; resident unregistered individual 20%: **new** tax | half now / half after |
| 16 | მოგება | nr profit-type 10% — no tax, no object | manual (rare) |
| 17 | როიალტი | payment withholding line, existing res 20% / nr 5% taxes | auto now |
| 18 | სოც. დაბეგვრადი | abolished 202412 | never generated |
| 19 | იჯარა | nr rent 20% exists → auto now; resident residential 5%: **new** tax | half now / half after |
| 20 | ამხანაგობა | nothing models partnerships | manual |
| 21 | დაბრუნებული პენსია | pension-agency flow | n/a for this company |
| 22/23 | თამაშობები | gambling operators only | n/a |
| 24 | სასტუმრო ნომრები | tourist-enterprise scheme (cat 1.3, 5%) | n/a today; mapped tax if ever |

## 6. Name / legal-form splitting

No first/last split exists anywhere (verified: `hr.employee` has only `name`/`legal_name`; no custom module adds one). Strategy: generator pre-splits — individuals: first token = სახელი, rest = გვარი; companies: known legal-form prefixes (შპს, სს, იმ, ააიპ, კს, სპს…) → col 2, remainder → col 3. Both columns stay **editable on the line**; pre-flight flags rows where the split looks wrong (1 token, >3 tokens, no known prefix). No new name fields on partner/employee in v1.

## 7. Validations and controls

**Pre-flight (blocking export):**
- ID number: 11 digits (individual) / 9 (company); non-empty.
- (category, type) pair exists in matrix; rate ∈ allowed list; date within period; country code non-empty; category set.
- Salary rows: slip not `edited` without review; paid-date-fallback rows acknowledged.

**Control tab (informative, non-blocking) — source-based, never calendar-month GL:**
- The declaration is cash-basis; payroll moves are accrual-dated. An August slip paid in September belongs to September's declaration while its move sits in August — so the control totals PIT/pension **over the exact slips selected by payment events**, wherever their moves sit. Equality against "this month's 3320 movement" would be wrong by design.
- GL 3320/3310.02 monthly movement is shown only as an **informational timing bridge** (accrual vs cash difference listed, grouped by source — 3320 is shared by payroll PIT, resident WHT and advance prepaid legs).
- Per-payment WHT cross-check: Σ converted withholding-line amounts vs the payment move's WH-Tax leg.
- Pension totals vs pensions.ge expectation (2% of salary gross of members).
- **Unmatched-payments helper** (outbound payments to individuals without withholding lines — the completeness net): **optional, v1.1**, not in the v1.0 core.

## 8. Accountant runbook (procedures, no new accounting flows)

| Income | Procedure |
|---|---|
| ხელფასი | Nothing new. Pay salaries via the existing pay wizard (it writes real payment dates). Avoid list-view "Mark as Paid" — it fabricates the date. |
| დივიდენდი | **This is an accounting-process decision (D3), owned by the accountant — the reporting module must not force it and works either way.** Recommended target state: distribution JE as today (CIT wizard for CIT 15%) but WHT moves to the payment step — wizard's dividend-WHT rate → 0, payout registered as a payment with the 5% dividend WHT line → auto rows. Rationale: the wizard books WHT as raw JE lines — invisible to the declaration and to tax tags (known gap, `gec_l10n_ge_tax` ANALYSIS_AND_FIXES #11), and detection from its account/description would be brittle guessing; the tax code withholds **at payment** anyway (cash-basis date for col 10). D3 **accepted 2026-09-01** — this is the standard procedure once the accountant is briefed; any dividends still run through the old wizard-WHT path in the meantime = **manual declaration lines**. |
| სტიპენდია / მომსახურება ფიზ. პირზე / იჯარა | Standalone payment (or bill + Register Payment) with the matching WHT tax line. |
| არარეზიდენტები | Same; treaty relief entered in cols 12/13 on the line. Treaty-exempt payments with no withholding = **manual declaration lines** (D5: no 0% WHT tax exists or will exist — stock strips the flag). |
| Process rules | Register payments per vendor/bill — **grouped multi-bill registration silently disables withholding** (stock wizard behavior, verified). **Never send a WHT-carrying payment through the Basis Bank flow** until L9 is fixed — it transmits the gross (`payment.amount`), overpaying the vendor by the withheld tax; execute those as Manual Payment (net amount typed in the bank). |

## 9. Decisions — ALL RESOLVED 2026-09-01 (user acceptance + DB verification)

| # | Decision | Outcome |
|---|---|---|
| ~~D1~~ | **RESOLVED — target stack = `gec_modules_hr3`, the local test/dev DB** (user 2026-09-01; all needed modules verified installed via `ir_module_module`). Production is assumed to run the same stack — **the same check must be re-run on the production DB before deploy** (Phase 0); if prod diverges, D1 reopens. | Develop + test on hr3; verify prod at deploy. |
| ~~D2~~ | **RESOLVED — self-contained country codes.** `employee_registry_rs` is NOT installed in `gec_modules_hr3` (verified); depending on it would force-install its registry models + daily sync cron into the payroll DB for one field. | Own `res.country.rs_form30_country_code` field, data from the form-30 classifier sheet (§4.3). |
| ~~D3~~ | **ACCEPTED (user 2026-09-01) — dividend WHT at payment** (wizard rate → 0, payout payment carries the 5% WHT line). Unblocks the v1.1 new-tax data (stipend/services/rent). Remaining task: brief the accountant on the new dividend procedure before the first distribution under it. | At-payment. |
| ~~D4~~ | **ACCEPTED (user 2026-09-01) — salary month = payment month** (cash basis, matches გაცემის თარიღი). | Payment month. |
| ~~D7~~ | **DECIDED (user 2026-09-01) — new WHT taxes live in `gec_l10n_ge_tax`, no migration scripts** (template dicts + only-if-missing load in `_ge_tax_apply_maintenance`; see §4.4). Exact tax list pending the accountant round (§4.5 — the worksheet's two proposals are not created as written). | In gec_l10n_ge_tax; form-30 module only maps them. |
| ~~D5~~ | **RESOLVED — no 0% WHT tax.** Stock resets `is_withholding_tax_on_payment` for `amount >= 0` ([account_tax.py:36-40](../addons/l10n_account_withholding_tax/models/account_tax.py#L36)); a data-loaded 0% record dies on the first UI edit. | Treaty-exempt declarable payments = manual lines. |
| ~~D6~~ | **RESOLVED — one row per payment event.** Salaries: one row per paid payslip (advance and salary paid on different dates keep their own dates); payments: one row per withholding line. | Merge rows only when employee, date, category, type, rate and relief treatment are all identical (optional). |
| V1/V2 | **STILL OPEN — not decidable by acceptance:** portal template re-download + pension-column behavior on first import (see §1). These are facts on rs.ge's side, verifiable only against a draft declaration. | Phase 4 acceptance test on a draft declaration. |

## 10. Limitations / risks — when each one bites, and how likely

Likelihoods calibrated against `gec_modules_hr3` on 2026-09-01 (1 company, 29 active employees, 1 art-82 exemption assignment, 58 payments — all GEL, 1 withholding line so far). **hr3 is the local test/dev DB (user-confirmed)** — these numbers describe the intended setup, not production reality. Before go-live, re-run on the production DB: company count (→ L6), payment currencies (→ L5), exemption assignments (→ L3), withholding-line usage (→ L1); any divergence moves the corresponding chance up.

| # | Limitation | When it bites (concrete case) | Chance | What limits the damage |
|---|---|---|---|---|
| L1 | Payment without its WHT line → **missing declaration row** | (a) accountant pays an individual's rent/service bill and forgets the withholding line; (b) Register Payment over several bills with grouping — the wizard **silently hides** the WHT section; (c) dividend paid before the accountant is briefed on the D3 procedure; (d) money sent straight from internet banking, only the bank statement reaches Odoo — no payment record at all | **High in the first 2–3 months** (the DB has exactly 1 withholding line today — the habit doesn't exist yet), falling to low–medium once routine sets in and the v1.1 helper lands. Scales with the number of non-salary payments to individuals/non-residents per month | Monthly pre-filing review; control tab; missed row = დაზუსტებული amendment (self-amendment before an audit carries no fine — სსკ 274/275) |
| L2 | Fabricated salary payment dates | Someone flips slips to paid from the payslip **list view** ("Mark as Paid" is hidden on the form but alive in the list and in the pay-run action — it stamps `today()`), or the payment-report wizard with a hand-typed date, instead of the gec_payroll_bank pay wizard | **Low–medium** — your standard flow writes real dates (both non-draft slips in hr3 carry a real `paid_date`), but the wrong button is one click away for any payroll user; expect a few incidents a year, mostly with new staff | Such rows have no matched payment → generator flags them, date editable. Wrong date inside the same month is harmless; crossing a month boundary = row lands in the wrong declaration → amendment |
| L3 | Art-82 relief is derived (inversion), not stored; exemption year is accrual-based | Only for employees assigned to an exemption category — **today exactly 1 of 29**. Sub-cases: rounding ±0.01; a slip edited via Edit Payslip Lines breaks the inversion invariant; December salary paid in January while the yearly cap is nearly consumed (payroll consumed the cap in the old year, the declaration reports the row in the new one) | **Marginal today** (one employee); rounding = common but immaterial; edited slips = rare; the Dec/Jan cap case = at most once a year per exempt employee, and only if December pay actually slips into January | Affected rows carry warnings; column 9 is editable; rs.ge validates on import anyway |
| L4 | Classifier drift (rs.ge re-versions categories/types/rates per period) | rs.ge publishes version 8+ **and** the change touches something you use. History: ~1 change per year (202011, 202201, 202301, 202401, 202412, 202505) — but every recorded change hit exotic types (gambling, hotels, type 18); salary 20% / dividend 5% never moved | Drift itself: **near-certain, ~annually**. A drift that silently breaks *your* filing: **low** — the portal rejects invalid combos line-by-line, so the failure mode is a loud rejected upload, not a wrong accepted filing. Residual risk: amending an old period with current-period rules — the per-rate validity dates exist precisely for that | V1 habit (re-download the template each period), period-aware rate rules, portal validation |
| L5 | FX rates beyond EUR/USD are not auto-fetched | First payment to a non-resident in a third currency (GBP, TRY, AED…) — `nbg_rates` feeds only EUR/USD, Odoo silently converts at a stale/missing rate → wrong GEL base in GL **and** declaration | **Zero today** (all 58 payments in hr3 are GEL). Once such a vendor appears: **high per payment** unless the rate is entered manually first — Odoo gives no stale-rate warning | Cheap addition to pre-flight: warn when a source payment's currency has no rate row for the payment date. Long-term option (separate decision — touches `nbg_rates`): extend its `CURRENCIES` list |
| L6 | Exemption cap is not company-scoped | Same person employed by 2+ companies in the same DB, both with exemption categories — each company grants the full yearly cap | **Zero today** — hr3 has exactly 1 company. Revisit only if a second company is ever added | None needed now |
| L7 | Amendments = full annex re-upload | Anything found after filing: a late-registered WHT payment, a corrected payslip, a category error caught by GRS camera review | **Medium** — a few amendments a year is normal accounting life. The mechanical risk is low: rs.ge *replaces* the whole annex, so the portal flow itself forces completeness | Regenerate keeps manual rows, so rebuilding an old month is deterministic; self-amendment before audit = no fine |
| L9 | **Basis Bank sends the GROSS on WHT payments** — both payload builders use `float(self.amount)` ([account_payment.py:241,246,264](../custom_addons/gec_basis_bank_integration/basis_bank/models/account_payment.py#L241)); a withholding payment's `amount` is gross, so the vendor would be overpaid by the withheld tax, and the confirmation matcher (compares the bank report to the same `self.amount`) would **confirm** the overpayment; the 5-GEL gap surfaces only at bank reconciliation (statement 100 vs outstanding 95) | Any WHT-carrying vendor payment pushed through the Basis send flow | **Certain per payment** if the flow is used for WHT payments — this is a live defect, not a risk | Process rule (§8): WHT payments = Manual Payment only, net typed in the bank. Proper fix = small change in `basis_bank` (net payload + matcher, or a send-time guard) — separate decision, candidate for v1.1 |
| L8 | Stale project docs mislead future work | A future session/developer trusts [payroll_payment_flow.md](payroll_payment_flow.md)'s claim that 3320 became reconcilable in 19.0.1.12.0 (the migration dir is empty; no code does this) or geo_payroll README's version (19.0.1.7.0 vs manifest 19.0.1.31.0) | **Medium if left unfixed** — these docs are the project's primary knowledge base and are read by every session; this session nearly inherited the error | Two one-line doc corrections, pending as a separate task |

## 11. Phases & effort (net dev time)

**v1.0** — decisions are resolved (§9); Phase 0 is now purely technical prep:

| Phase | Content | Est. |
|---|---|---|
| 0 | **V1: download the current portal template ("ფაილის ნიმუში") and lock the column map from it — before writing the exporter.** Classifier CSVs generated from the xlsx (categories, types, per-rate rules, countries). Re-run the D1 module check on the **production** DB. | 0.5 d |
| 1 | Module skeleton, 4 classifier models + data (incl. `rs.form30.country`), partner default fields + one-time batch-prefill screen, tax mapping field, security | 1.5 d |
| 2 | Declaration + line models, generation A (one-NET-payment gate, needs-manual list) / B, name splitting, validations, views | 2 d |
| 3 | SpreadsheetML export (lxml, column-map data-driven), source-based control tab | 1 d |
| 4 | Acceptance: generate a real month → import into a **draft** declaration on rs.ge; **V2: observe pension-column behavior**; fix | 0.5–1 d |
| — | Tests (project release gate): generation math incl. advances/exemptions/partial-payment gate, currency conversion, matrix validation, XML golden file | 1 d |

**v1.0 total ≈ 5.5–6.5 dev days.**

**v1.1 (after the accountant is briefed — D3):** the 3 WHT tax records + their type mapping; unmatched-payments helper; FX stale-rate pre-flight warning; optional proportional allocation for multi-payment slips. **≈ 1–1.5 d.**

Out of scope entirely: declaration main-form fields (portal computes from annex), pensions.ge reporting, annual declaration, direct API upload, offshore-country list, in-kind fringe benefits (don't exist in payroll yet).

---

## 12. Live-testing observations (2026-09-01, `gec_modules_hr3`) — challenges noted, NO ACTION NEEDED NOW

Recorded from a hands-on payment/WHT test session on the test DB. These are **notes for the build and the accountant runbook — nothing is to be done about them right now.**

- **Entry-less payments exist in this DB.** A payment method line *without* a payment/outstanding account (the "ბანკი / Manual Payment" method here) creates a payment with **no journal entry at all** (stock v19): the bill is later settled directly by the bank statement, and no "Outstanding credits" widget ever appears. Consequence for form 30: **a WHT payment registered on such a method would book no tax in the GL** (the WHT legs live inside the payment's entry), while its withholding *line* record may still exist — an inconsistency the generator should detect (warn/exclude). Runbook rule when we get there: **WHT payments only via methods that have a payment account** (e.g. Basis Bank Transfer → 1210.04). Exact stock behavior of withholding-on-entry-less to be verified once, at build time.
- **Withholding lines survive payment cancellation** (verified: canceled payment kept base 100 / tax 5). The §5.2 state filter exists because of this; the control tab should also ignore canceled payments' lines.
- **Cancel/reset experiments leave stale bill↔payment links** — the test bill shows "Payments 5" of which 3 are canceled; `basis_bank` reset also tears down reconciliation and warns "reconcile manually". Harmless for the declaration (we read withholding lines + state filter), just noise to expect in real DBs.
- **Two settlement flavors coexist** and confuse operators: entry-full payments (statement reconciles the *payment's* 1210.04 leg — 95 meets −95) vs entry-less payments (statement reconciles the *bill* directly — −100 meets the 3110 line). Vendor-payment statement lines are always **negative**; a positive line makes Odoo suggest "Receivable" and shows a doubled imbalance. Operator education, zero development.
- **Partial/installment payments with WHT work in stock** (proportional base via the paid factor) and fit the per-withholding-line row source as-is; the one-payment gate concerns payroll slips only.
- **L9 (Basis sends gross on WHT payments)** remains the one live defect — already tracked in §10 with its process rule; fix is a v1.1 candidate in `basis_bank`, decision pending.

## Research coverage (this plan's evidence base)

- Samples fully parsed: `Export.xml` (16-col export), `temp_30_3017_3_1.rar` → 14-col import template, `30_data_7_202505.xlsx` (4 classifier sheets re-verified programmatically).
- Source read end-to-end: stock `l10n_account_withholding_tax` (models + payment integration), key files of `gec_l10n_ge_tax` (tax templates, CIT wizard, DGV report inventory), `geo_payroll` structures/benefit/exemption rules + tests, `gec_payroll_bank` pay wizard, `employee_registry_rs` country/identity fields, `gec_localization` CoA CSV (31xx/33xx/34xx/53xx blocks), `nbg_rates`, plus targeted greps across all of `custom_addons` (no existing form-30/SpreadsheetML code anywhere — greenfield confirmed). `ai_accountant`, `gec_rs_waybill`, `gec_id_sign` inventoried: no overlap with this module beyond the reusable rs.ge REST client (irrelevant while no declaration API exists).

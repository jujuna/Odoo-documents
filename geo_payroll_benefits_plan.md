# geo_payroll — Benefits & Deductions Plan (v1)

**Status:** IMPLEMENTED 2026-08-22 in `geo_payroll` 19.0.1.14.0 (code written, suite NOT
run, NOT yet upgraded on a DB). Design was adversarially verified pre-implementation
(6 agents, 37 claims, 0 refuted) and the implementation passed a second 4-lens
adversarial review (22 findings — 4 blockers + 4 majors, all fixed; see §15).
Naming decision (user): no `gec` in any new model/field/code name. Migration files
banned (user): existing-company accounts ship via `_benefit_fill_missing_accounts`,
a fill-only-empty pass run from a `<function>` tag on every upgrade.

**Requirements confirmation (2026-08-25):** manager walked through concrete scenarios and
confirmed the shipped semantics unchanged — company_amount always enters GROSS (PIT + pension
if member apply, then pay the net), employee_amount is always a post-tax deduction from net
(net 1000, amount 50 → pay 950), separate mode correctly carries no employee side. His
"like the 2% pension company part" phrasing meant *financed by the company*, not COMP-category
cost-only mechanics. No behavior change required.

**19.0.1.15.0 (2026-08-25): `taxable` flag REMOVED.** Since the manager's rule is "always add
to gross", the non-taxable escape hatch was deleted before ever running on a database: the
`taxable` field, the `BONUS_NT` input type + 5 rules, the `BENNT` category, and the
`+ categories['BENNT']` term in all 5 NET formulas are gone (plus the dead
`BENEFIT_ACCOUNT_CODES` constant). Every company bonus is `BONUS` → ALW → GROSS → taxed.
References to BONUS_NT/BENNT below this line are historical. If a legally exempt payment
ever appears, re-adding the mechanism is a bounded, known change (this file documents it).

**19.0.1.16.0–19.0.1.19.0 (2026-08-26): SALARY ADVANCES added — see §16.** Two phases, both
in payroll: the pay-out payslip (`ADVANCE_PAY` → taxed in full, Dr `1730`; with salary or as
its own Benefits slip per `pay_mode`), then repayments over the next N salary payslips
(pre-GROSS `ADVANCE`, reducing the taxable base, Cr `1730`). Supersedes the §10 deferral.

**Implementation deltas vs the plan below:**
- Models are `hr.payroll.benefit` / `hr.payroll.benefit.line` (+ wizards
  `hr.payroll.benefit.assign`, `hr.payroll.benefit.payrun`); marker field is
  `hr.payslip.input.benefit_line_id`; codes are `BONUS` / `BONUS_NT` / `BENEFIT_DED`.
- `wage_percent` amount type dropped from v1 (per-line amounts cover 13th salary).
- **Separate programs pay the company bonus only.** Employee-paid items are modeled
  as With Salary programs (deducted on the salary slip). A per-side split of one
  line across two slips would need per-side consumption state — rejected as complexity.
- `BENEFIT_DED` books to `7416` (expense contra via negative flip), NOT `3160`:
  a partnerless reconcilable-payable line hard-blocks geo's payment register on
  every deduction slip. Accountant can re-route in UI (fill-only-empty preserves it).

## 1. Goal

One central model where HR creates a bonus/deduction program (e.g. "ქორწინების ბონუსი",
"Fitpass"), assigns batches of employees from that record, controls one-time vs recurring,
controls who pays (company / employee / both), and chooses whether it pays **inside the
regular salary payslip** or **as a separate payment** — per program, so one client can pay
bonuses separately while another pays with salary. Income tax and pension apply
automatically. Minimal code, minimal validations.

| User goal | How the plan meets it |
|---|---|
| 1. Central bonus/deduction model | New model `gec.payroll.benefit` + employee lines |
| 2. With salary OR separately | `pay_mode` per program + one new off-cycle "GEO Benefits" structure |
| 3. No per-employee card editing | Employees assigned in batch from the program form; nothing written to `hr.version` |
| 4. Company / employee / both | Two amount fields per program (`company_amount`, `employee_amount`), overridable per line |
| 5. Easy/fast | One form, one "Add Employees" action, automatic payslip pickup |
| 6. Minimal code | ~750 lines: 2 models, 1 payslip compute extension, data XML, views, 1 migration. Reuses the stock input-line pattern used by `hr_payroll_expense`/`hr_payroll_sale_commission` |
| 7. Tax/pension | Taxable bonuses land in the ALW category → existing `GROSS`/`PIT`/`PENSION_*` rules apply with zero changes |

## 2. The structure question — answered and verified from source

**Yes, an employee can be paid a second payslip on another structure in the same month**,
but only if that structure is NOT the default structure of its structure type:

- Core computes `is_regular = (struct_id.type_id.default_struct_id == struct_id)`
  ([hr_payslip.py:394](../enterprise/hr_payroll/models/hr_payslip.py#L394)). Core has **no
  constraint at all** against overlapping payslips — only a soft same-structure/same-dates
  warning ([hr_payslip.py:1346](../enterprise/hr_payroll/models/hr_payslip.py#L1346)).
- geo_payroll's double-pay guards are all scoped to regular slips **in both directions**
  (validating the benefits slip skips them via `_gec_is_regular_base`; validating the
  regular sibling filters the search results with `.filtered('is_regular')`):
  `_gec_check_no_overlap` ([hr_payslip.py:302](../custom_addons/gec_payroll_types/geo_payroll/models/hr_payslip.py#L302)),
  `_gec_check_version_coverage` ([:351](../custom_addons/gec_payroll_types/geo_payroll/models/hr_payslip.py#L351)).
- geo_payroll silently rewrites the structure of any slip whose structure IS a type default
  (`_gec_align_draft_base_structures`, [:45](../custom_addons/gec_payroll_types/geo_payroll/models/hr_payslip.py#L45)).
  A non-default structure is never realigned, on any path (compute, version recompute,
  reset-to-draft, run reset — all verified).
- Off-cycle slips never claim work logs/timesheets (`_gec_in_claim_scope` requires the
  version default structure, [:91](../custom_addons/gec_payroll_types/geo_payroll/models/hr_payslip.py#L91)),
  skip all settlement/zeroing guards, and `action_payslip_done` neither validates nor
  conflicts with their work entries ([enterprise :600](../enterprise/hr_payroll/models/hr_payslip.py#L600)).

**Consequence:** the separate-payment mode uses one new structure type **"GEO Benefits"**
whose `default_struct_id` stays EMPTY, holding one structure **"GEO Benefits Pay"**. That
slip computes `is_regular = False`, coexists with the monthly salary slip, is invisible to
every overlap guard, and never touches work-item claiming.

**Two load-bearing invariants** (verified consequences if broken):

1. **`default_struct_id` on the GEO Benefits type must stay empty forever.** It is a plain
   editable m2o — if anyone sets it in the UI, every benefits slip instantly flips to
   `is_regular = True` and the overlap guard starts hard-blocking the monthly slips.
   Ship a one-line constraint on the type (worth its raise).
2. **No `BASIC`/`paid_amount`-based rule may ever be copied onto the Benefits structure.**
   With `use_worked_day_lines = False`, `_get_paid_amount()` returns the FULL contract
   wage ([enterprise :1643](../enterprise/hr_payroll/models/hr_payslip.py#L1643)) — a
   copied BASIC rule would silently pay the whole salary again.

## 3. Rejected alternatives (why not X)

| Alternative | Why rejected |
|---|---|
| Stock **Salary Adjustments** (`hr.salary.attachment`) | Deduction-shaped only; no company-paid side; no with-salary/separate routing; multi-employee records must be split before payment (`record_payment` raises, [hr_salary_attachment.py:387](../enterprise/hr_payroll/models/hr_salary_attachment.py#L387)); all adjustments of one type collapse into ONE aggregated payslip line; payment recording fires only on the `state='paid'` write (never on the Payment Report path). Wrapping it in our model = syncing two models = more code than injecting inputs ourselves. |
| **Property inputs** (v19 salary-input rules stored on version/payslip) | Values are managed per employee on the version — exactly the per-card editing the user refuses. No one-time semantics, no consumption tracking, one value per rule (benefits of the same kind would merge). Also the family of the known separator-crash workaround. |
| Salary inputs written onto `hr.version` by our model | Same sync problem, pollutes versioned contract data with transient benefit state, and version writes trigger payslip recompute machinery. |
| One structure/rule per benefit | Rule explosion, HR cannot self-serve, violates "minimal code". |

## 4. Architecture

```
gec.payroll.benefit (program)  ──1:n──  gec.payroll.benefit.line (per employee)
        │                                        │
        │  injected at input-compute time        │  consumption stamp (once-benefits)
        ▼                                        ▼
hr.payslip.input  (one line per benefit line, marker field gec_benefit_line_id)
        ▼
3 generic salary rules (read inputs, one payslip line per input line, named by benefit)
        ▼
existing GROSS → PENSION_EE → PIT → PENSION_ER → NET   (untouched — automatic tax)
```

Injection extends `_compute_input_line_ids` — the exact pattern of
[hr_payroll_expense](../enterprise/hr_payroll_expense/models/hr_payslip.py#L23),
[hr_payroll_sale_commission](../enterprise/hr_payroll_sale_commission/models/hr_payslip.py#L14)
and five l10n modules. geo_payroll currently never touches input lines (verified by
full-module grep), so the hook is free.

## 5. New models

### `gec.payroll.benefit` (program)

| Field | Type | Meaning |
|---|---|---|
| `name` | Char, required | "ქორწინების ბონუსი", "Fitpass" |
| `company_id` | M2O res.company | default env company |
| `company_amount` | Monetary ≥ 0 | company-paid CASH amount per period (bonus) |
| `employee_amount` | Monetary ≥ 0 | employee-paid amount per period (net deduction) |
| `amount_type` | Selection: `fixed` / `wage_percent` | `wage_percent`: company amount = % × version wage (covers 13th salary = 100%) |
| `recurrence` | Selection: `once` / `monthly` | once = next computed payslip only, then done |
| `date_from`, `date_to` | Date | active window for `monthly`; `date_to` empty = until stopped |
| `pay_mode` | Selection: `with_salary` / `separate` | where the COMPANY bonus lands. Employee deductions ALWAYS go on the regular salary slip (a separate slip containing only a deduction would be a negative payment — nonsense) |
| `taxable` | Boolean, default True | True → bonus enters ALW/GROSS (PIT+pension apply). False → after-tax category (see §7) |
| `line_ids` | O2M benefit lines | |
| `active` | Boolean | archive to retire |
| `note` | Text | conditions ("მნიშვნელობა არ აქვს, ქალბატონი იქნება თუ მამაკაცი…") |

### `gec.payroll.benefit.line` (one employee in one program)

| Field | Type | Meaning |
|---|---|---|
| `benefit_id` | M2O, required, ondelete cascade | |
| `employee_id` | M2O hr.employee, required | |
| `company_amount`, `employee_amount` | Monetary | default from program, per-line override (their sheet has "ინდივიდუალურად … არ გვაქვს განსაზღვრული" cases) |
| `date_from`, `date_to` | Date, optional | per-line override of the program window |
| `payslip_id` | M2O hr.payslip, copy=False | consumption stamp for `once` programs — set at payslip validation, cleared on cancel/draft |
| `state` | computed | `pending` / `done` (once) or `running` / `expired` (monthly) — pure display |
| `active` | Boolean | stop one employee without touching the rest |

SQL uniqueness: one active line per (benefit, employee). Unlink guard only when
`payslip_id` is set (archive instead).

Total new raises in the feature: **2** (consumed-line unlink guard + the
empty-default-struct constraint from §2). Everything else is domain-filtered injection —
no validation walls.

**Batch assignment UX:** "Add Employees" button on the program → small wizard with an
employee many2many (dropdown filters by department/tag work out of the box) → creates
lines in bulk. HR never opens an employee card.

## 6. Payslip integration (hardened per verification)

### 6.1 Injection (`_compute_input_line_ids` extension in geo_payroll)

New marker field `hr.payslip.input.gec_benefit_line_id` (M2O benefit line). The override
calls `super()` first, then — **strictly idempotently**: unlink all marked lines, re-create
from scratch. Idempotency is mandatory, not hygiene: geo's `compute_sheet` realigns
`struct_id` before computing, `struct_id` is a dependency of this compute, so the
extension re-fires mid-`compute_sheet` in the same transaction (verified).

Scope table — which slips receive what:

| Slip | Receives |
|---|---|
| Regular salary slip (struct == version default), state draft | `with_salary` bonus parts + ALL employee-deduction parts (any pay_mode) |
| "GEO Benefits Pay" slip, state draft | bonus parts of `pay_mode = separate` programs only |
| Refund slips (`credit_note` / `is_refund_payslip` / origin set + credit_note) | **nothing injected** — refunds copy-negate the origin's `line_ids` directly ([enterprise :726-740](../enterprise/hr_payroll/models/hr_payslip.py#L726), verified: `input_line_ids` is NOT copied, o2m copy defaults False; `_gec_check_refund_reversal` passes because negated lines are exact). Excluding refunds also prevents a stray Compute Sheet on a refund draft from re-adding positive benefit lines |
| Correction slips (`origin_payslip_id` set, not credit_note) | **mirror of the ROOT origin's marked inputs** (same root-walking as `_gec_component_settlements`) — NOT fresh eligibility. Otherwise a refund+correction cycle silently un-pays the benefit (refund reverses it, correction never re-adds it, no guard catches it — verified gap) |
| Validated/paid/edited slips | untouched — the hook filters `state == 'draft' and not edited` itself, because the stock compute has NO state guard and re-fires on validated slips too (verified) |

Eligibility matching = employee + company + period overlap + not consumed + **not already
injected into another live slip** (plain search on the marker, excluding refund slips;
applies to both `once` and `monthly`). This one rule simultaneously prevents: double
pickup by mid-period version-split sibling slips, double pickup by an accidental duplicate
Benefits slip (geo's double-pay framework deliberately ignores non-regular slips — our
dedup is the only guard there, verified), and with-salary/separate cross-talk.

Amounts: one `hr.payslip.input` per benefit line and side, `name` = program name,
positive amounts (sign flip lives in the rule — stock convention).

Input codes: `GEC_BONUS` (taxable bonus), `GEC_BONUS_NT` (non-taxable bonus),
`GEC_BEN_DED` (employee deduction).

### 6.2 Recompute trigger

`_compute_input_line_ids` depends only on employee/version/struct/dates
([hr_payslip.py:284](../enterprise/hr_payroll/models/hr_payslip.py#L284)) — creating a
benefit AFTER draft slips exist would not appear on them, and `compute_sheet` does NOT
rebuild input lines. Fix: benefit/line create-write-unlink hooks call
`env.add_to_compute(Payslip._fields['input_line_ids'], <draft, non-edited slips>)`.
Verified: `modified()` would NOT work (it invalidates dependents, not the field itself),
and the draft filter must live in our hook. HR then hits Compute Sheet as usual.

### 6.3 One-time consumption

On `action_payslip_done`: stamp `payslip_id` on the once-lines behind this slip's marked
inputs. On cancel / reset-to-draft: clear the stamp. ~20 lines inside the existing
overrides — no new workflow, no cron, no states.

## 7. Salary rules & structure changes

Data-file layout verified: structures/types live in the `noupdate="1"` block
([payroll_structure_data.xml:3](../custom_addons/gec_payroll_types/geo_payroll/data/payroll_structure_data.xml#L3)),
**salary rules live in the `noupdate="0"` block (:80)** — so new rules AND the NET formula
edit ship automatically on module upgrade. No migration needed for formulas (accounts are
a different story, §9).

### New rules — added to the 4 GEO structures + the new Benefits structure

| Seq | Code | Category | Condition | Amount |
|---|---|---|---|---|
| 30 | `GEC_BONUS` | ALW | `'GEC_BONUS' in inputs` | `result = inputs['GEC_BONUS'].amount; result_name = inputs['GEC_BONUS'].name` |
| 170 | `GEC_BEN_DED` | DED (post-tax: sequence AFTER PIT at 140) | `'GEC_BEN_DED' in inputs` | `result = -inputs['GEC_BEN_DED'].amount; result_name = …` |
| 180 | `GEC_BONUS_NT` | new category **BENNT** | `'GEC_BONUS_NT' in inputs` | `result = inputs['GEC_BONUS_NT'].amount; result_name = …` |

- Multiple inputs of one code → the engine emits **one payslip line per input line**, each
  named after its program ([hr_payslip.py:1134](../enterprise/hr_payroll/models/hr_payslip.py#L1134)) —
  the payslip shows "Marriage Bonus 1000" and "Fitpass −80" as separate named lines with
  zero extra code (verified, incl. `result_name` per line).
- `PIT` needs **no change**: self-contained on `categories['GROSS']`, never reads DED —
  the taxable bonus raises the PIT/pension base automatically, the post-tax deduction
  cannot corrupt it. Verified numerically: member, wage 1000 + bonus 500 →
  PENSION_EE −30, PIT −294, NET 1176 = 0.784 × 1500 (exact linearity).
- **One existing rule edited on all 4 structures + the new one:** `NET` formula gains
  `+ categories['BENNT']` (categories are `DefaultDictPayroll(lambda: 0)` — no effect when
  unused; each structure carries its OWN NET rule copy, all 5 must be edited or that
  scheme silently drops non-taxable bonuses — verified).
- `GEC_BEN_DED` keeps the module's negative-result convention — the account sign-flip in
  §9 depends on it.
- **Sequence invariant:** category accumulation is strictly sequential — any
  category-contributing rule at sequence > 200 silently drops out of NET. All new rules
  stay in 30–180; document this next to the rules.

### New structure

- `hr.payroll.structure.type` "GEO Benefits" (country GE, wage_type monthly,
  **no default_struct_id — load-bearing, constrained per §2**).
- `hr.payroll.structure` "GEO Benefits Pay": `use_worked_day_lines = False`, rules:
  `GEC_BONUS`, `GEC_BONUS_NT`, `GROSS`, `PENSION_EE`, `PIT`, `PENSION_ER`, `NET`
  (same formulas; NET carries `employee_move_line=True` like the other 4 — per-rule
  boolean, forgetting it breaks partner stamping/per-employee splitting, verified).
  No BASIC, no deduction rule (§2 invariant 2).
- `_gec_set_missing_default_struct` data hook is scoped by xmlid to the unit type only
  (verified) — it cannot accidentally set a default on the new type. Verified there is no
  code path that crashes on a type with empty `default_struct_id`.
- Employees never carry the Benefits type on versions — nothing assigns it; version
  constraints would give clean ValidationErrors, not crashes (verified).

### New rule category + input types

- `hr.salary.rule.category` BENNT: **must explicitly set `country_id` eval False** (like
  the stock categories). If omitted, the default (installing company's country) can
  mismatch the GE rules and the rule↔category country constraint rejects installation on
  non-GE-default databases (verified trap).
- `hr.payslip.input.type` `GEC_BONUS` / `GEC_BONUS_NT` / `GEC_BEN_DED`, country GE,
  `available_in_attachments = False` (the stock attachment machinery then never
  drops/rebuilds our lines — verified). Added to `input_line_type_ids` of ALL 5
  structures so the injected lines are also manually addable/editable in Other Inputs.
- Note, not a v1 problem: stock salary adjustments (if a client ever creates them) would
  inject their input lines into Benefits slips too, but no GEO structure has an
  `ATTACH_SALARY`-family rule, so those lines are inert everywhere in this module.

## 8. Separate payment flow (client who pays bonuses apart)

1. HR sets `pay_mode = separate` on the program (or on all their programs).
2. New menu action **"Benefits Pay Run"**: pick period → finds employees with active
   separate-mode bonus lines in that period → creates one `hr.payslip.run` + payslips with
   `struct_id = GEO Benefits Pay` **set explicitly in create vals** (core
   `_compute_struct_id` only fills empty struct — verified) — ~30 lines.
   Stock `generate_payslips` cannot be reused: run version-selection filters by the run
   structure's TYPE ([hr_payslip_run.py:27](../custom_addons/gec_payroll_types/geo_payroll/models/hr_payslip_run.py#L27)),
   no version carries the Benefits type, and with zero versions the stock button raises —
   hide/ignore the stock Generate button on this run.
   Skip employees whose lines net to zero — a zero-line slip holds the run at "ready"
   forever (verified).
3. Slips compute: bonus inputs → GROSS → PIT/pension → NET. Flat 20%/2% rates make the
   split mathematically identical to paying with salary (no progressive brackets in GE).
4. Validation: no overlap guard fires (`is_regular = False`); run-level coverage check
   passes (verified for a run of only non-regular slips); work entries untouched.
5. Payment: once §9 is configured, the standard Pay button, the geo paid-flip
   (`account_payment_register.py`), and the Basis Bank bridge all work unchanged —
   verified both are structure-agnostic (they key on the NET rule's credit account and
   reconcilable lines, no `is_regular` filter anywhere in `gec_payroll_bank`).

## 9. Accounting — MANDATORY configuration, not optional polish

Verified failure mode if skipped: the Benefits structure's own NET rule has no credit
account and the structure no journal → no journal entry is created, the Pay button raises
"credit account … not reconciliable", geo's register-payment raises "No open net salary
lines", the bank bridge raises "NET salary rule has no credit account". **The separate
flow is dead on arrival without this section.**

| Rule | Debit field | Credit field | Booking |
|---|---|---|---|
| `GEC_BONUS` | `7410` Wages and Salaries (or `7416` Other Employee Benefits — **accountant decision**) | — | Dr expense |
| `GEC_BONUS_NT` | `7416` — **required, not optional**: a BENNT line with no debit account leaves NET crediting 3130 with no expense leg; the imbalance goes to the journal's Adjustment line and raises at validation if the SLR journal has no default account (verified) | — | Dr expense |
| `GEC_BEN_DED` | `3160` Liability to Company Personnel (or contra `7415`/`7416` — **accountant decision**) | — | negative total flips → Cr (verified flip, conditional on the negative-result convention) |
| Benefits-structure `GROSS`/`PIT`/`PENSION_*`/`NET` | same mapping as the 4 existing structures; NET credit `3130` reconcilable + `employee_move_line=True`; `journal_id` = per-company SLR journal | | |

Delivery in two pieces (verified necessity):

1. Extend `_configure_payroll_account_ge` (it maps by explicit rule xmlid — add the new
   xmlids; keep the skip-guard predicate on the original 4 structures so its semantics
   don't shift) → covers fresh `ge`-chart companies.
2. A one-shot migration (pattern of `migrations/19.0.1.9.0/post-migrate.py`) that fills
   ONLY the new rules' accounts + Benefits journal on already-configured companies —
   the 19.0.1.5.0 skip-guard means they would otherwise never receive them.

Multi-company/multi-customer: input types, category, structures all country-GE — same
record-rule visibility pattern as the existing 4 structures (verified identical).

## 10. Taxes — what applies automatically, what needs confirmation

- **Cash bonus, taxable (default):** ALW → GROSS → PIT 20% on (GROSS − 2% pension for
  members), PENSION_EE/ER 2% — fully automatic, zero rule changes. [Certain — verified numerically]
- **Employee deduction:** post-tax, does not reduce the PIT base — correct for benefit
  cost-sharing (Fitpass, insurance premium share). [Certain]
- **`taxable = False` escape hatch:** for anything the accountant declares exempt.
- **NOT in v1 — company-paid in-kind fringe benefits** (e.g. company-paid insurance
  premium as taxable employee income, ხელფასის სახით მიღებული სარგებელი, with its
  gross-up rules): tracked on the program for cost visibility only. Needs a
  georgian-tax-advisor/accountant ruling on the exact base before building — phase 2.
  Mechanically it is one more rule pair (ALW line + offsetting DED line = tax borne by
  employee, net cash unchanged).
- ~~**NOT in v1 — salary advances (ხელფასის ავანსი)**~~ — **built in 19.0.1.16.0, see §16.**
  The original assumption ("must not run through GROSS/PIT") was refined by the client's
  actual practice: the advance is taxed in full at pay-out, so each repayment installment
  must *reduce* the payslip's taxable base — a negative pre-GROSS rule, not a post-tax one.

## 11. Mapping the client's Excel catalog

| Sheet row | v1 mechanism |
|---|---|
| პრემია (მე-13 ხელფასი) — yearly, 1 salary | Program: once (created each December) or `wage_percent` 100%, taxable |
| ინდივიდუალური პრემია | Program: once, per-line amounts |
| გამოუყენებელი შვებულების ანაზღაურება | Off-scope: leave module territory; interim: once-program with HR-computed amount |
| ოვერტაიმი | Already covered by Work Logs (`WORKLOG_OT`) — do not duplicate |
| ქორწინების/ბავშვის ბონუსი 1000 | Program: once, company 1000 |
| გარდაცვალების დახმარება 1000 | Program: once, company 1000 |
| ფინანსური დახმარება | Program: once, per-line amount |
| ხელფასის ავანსი (1 თვე / 2-3 თვე) | Phase 2 (see §10 — not income) |
| ჯანმრთელობის დაზღვევა — employee pays | Program: monthly, employee_amount = premium |
| ფიტპასი — employee pays / split | Program: monthly, employee_amount (and company_amount for the split case) |

## 12. Code footprint

| Piece | Est. lines |
|---|---|
| `gec_payroll_benefit.py` (2 models + wizard) | ~230 |
| `hr_payslip.py` additions (injection + consumption + recompute trigger) | ~110 |
| `hr_payslip_input.py` (marker field) | ~10 |
| Data XML (category, input types, structure type + structure, 3 rules × 5 structures, 5 NET edits) | ~200 |
| `account_chart_template.py` mapping additions | ~25 |
| Migration (accounts/journal on configured companies) | ~30 |
| Views + menu + security | ~180 |
| **Total** | **~750 in geo_payroll** — vs ~7,100 existing |

New raises: **2** (§5). No new workflow states, no cron, no settlement-ledger extension.

## 13. Open decisions

1. Module placement: inside `geo_payroll` (recommended — the rules/NET edit live in its
   data file) vs a separate `gec_payroll_benefits` module (cleaner sale packaging, but
   must edit another module's rule records — fragile).
2. Expense account for bonuses: `7410` vs `7416` (accountant).
3. Credit account for employee benefit deductions: `3160` vs expense contra (accountant).
4. `wage_percent` amount type in v1 or defer (13th-salary convenience).
5. Company-level default for `pay_mode` in Settings, or per-program only (v1: per-program).

## 15. Implementation review record (2026-08-22, post-code)

Second adversarial pass (4 lenses: engine integration, ORM/v19, data-XML/load order,
tests/flows) on the written code — 22 findings, all blockers/majors fixed in-place:

| Fixed | Defect |
|---|---|
| blocker | Onchange NewId turned `('payslip_id','!=',self.id)` into match-all and stripped the slip's own benefit inputs → injection now hard-skips non-int ids |
| blocker | `BENEFIT_DED` on partnerless payable `3160` killed the Pay button → moved to `7416` expense contra |
| blocker | Validated→draft reset (list action / run reset) kept the once-stamp while the forced recompute deleted the input → a line stamped by a slip stays eligible *for that slip* (self-healing) |
| major | `ondelete='cascade'` on the marker could SQL-delete input rows of validated slips via monthly-line deletion → both unlink guards now also block lines referenced by validated/paid slips' inputs |
| major | Monthly benefits double-paid on mid-month version splits → blocking adds same-calendar-month collision |
| major | Injection/consumption on structures lacking the benefit rules marked benefits paid while paying nothing → rule-existence gate per side |
| major | Cancelling a chain root released the once-stamp while a validated correction kept paying → release re-stamps onto the surviving validated slip |
| minor | Payrun wizard created error-slips for ended contracts → contract-overlap filter; release now uses `active_test=False`; payslip deletion re-syncs sibling drafts; help texts fixed |

Accepted (documented, not fixed): no validation-time lock/re-check of benefit inputs
(concurrent two-period drafts can double-inject a once-benefit — same class of race the
work-log path closes with `lock_for_update`; deliberate "no raise walls" trade-off), and
no guard against manual deletion of an injected input line on a draft (recompute restores it).

## 16. Salary advances (19.0.1.16.0–19.0.1.19.0, 2026-08-26)

**Business case:** employee earns 3K/month, company advances 10K, agreed repayment over 10
months. Georgian practice (client-confirmed): PIT/pension on the whole 10K are withheld **at
the advance pay-out**, so each later payslip must tax only the reduced base — month = 3K
gross − 1K repayment = 2K taxable → PIT/pension on 2K, NET on 2K.

**Two phases, both inside payroll (19.0.1.19.0), rebooked per the accountant's 4-account
prepaid spec in 19.0.1.21.0 (2026-08-27, "ხელფასების გატერება 1.xlsx" — E1–E5/R1–R7/C1–C5
with test cases T1–T3):**

1. **Pay-out (E1)** — until the line is stamped, injection offers one `ADVANCE_PAY` input
   carrying the GROSS advance A; four rules split it into the prepaid assets, **no expense,
   nothing enters GROSS**: net → Dr `1730` (ADV category, adds to NET so the employee is
   paid), Dr `1731`/Cr `3181` employee pension 2%, Dr `1733`/Cr `3320` income tax 20% on
   (A − 2%), Dr `1732`/Cr `3182` company pension 2% (COMP-category zero-NET legs; pension
   legs conditioned on `pension_fund_member` — C4). Rounding per R3: components rounded,
   net takes the residual. `pay_mode` = where the pay-out slip is (With Salary = combined
   slip, Separate = Benefits Pay Run slip). Validation stamps the line as before.
2. **Repayment (corrected 2026-08-28, 19.0.1.23.0 — accountant rejected the sheet's own
   full-accrual-plus-closing shape when seeing it live):** `ADVANCE` (ALW seq 29, unbooked)
   subtracts the gross installment D **before GROSS**, so PIT/pension compute on the
   reduced base directly — monthly declared figures are the net ones (D=2,500 on S=4,350:
   GROSS 1,850, PIT 362.60, pension 37+37). The prepaids are consumed by one-sided legs:
   `REPAY_NET` Cr `1730` netto(D) (employee partner via employee_move_line), `REPAY_PEE`
   Cr `1731`, `REPAY_PIT` Cr `1733`, and `REPAY_PER` Dr `7490`/Cr `1732` (the company
   share becomes that month's expense, keeping total ER expense = 2% of full salary).
   The one-sided credits balance against the ALW reduction inside the entry. Employee
   cash = netto(S) − netto(D), unchanged through every redesign.

Deliberate deviation from the sheet: **R7 (installment ≤ month's net) is not enforced in
code** — a rule-level cap would desynchronize the input ledger that tracks repayment, and an
injection-level cap can only guess gross for hourly/daily schemes. It stays a configuration
duty (D = total/count is agreed per contract); C2/C5 remain manual accounting procedures.

**How it works:**

| Piece | Mechanism |
|---|---|
| Marking | `advance` checkbox + `payslip_count` integer (= number of REPAYMENT slips; the pay-out slip is not counted) on the program ([hr_payroll_benefit.py](../custom_addons/gec_payroll_types/geo_payroll/models/hr_payroll_benefit.py)); `employee_amount` = advance total (per-line override as usual); recurrence/company side hidden and ignored; `pay_mode` = where the PAY-OUT goes |
| Rules | Pay-out family (`ADVANCE_PAY` net, ADV category seq 28 + `ADV_PEE_PRE`/`ADV_PIT_PRE`/`ADV_PER_PRE` COMP seq 31-33) on 4 base structures **and** GEO Benefits Pay; repayment family (`ADVANCE` net, ADV seq 171 + `REPAY_PEE`/`REPAY_PIT`/`REPAY_PER` COMP seq 172-174) on the 4 base structures only ([payroll_benefit_data.xml](../custom_addons/gec_payroll_types/geo_payroll/data/payroll_benefit_data.xml)). New `ADV` category added into all 5 NET formulas; GROSS is untouched in both phases |
| Accounts | E1: Dr `1730`(net) / Dr `1731`+Cr **`3182`** / Dr `1733`+Cr `3320` / Dr `1732`+Cr **`3181`**. E3: net leg flips to Cr `1730`, COMP legs Dr `3182`/`3320`/`3181` against Cr `1731`/`1733`/`1732`. **Interim convention follows the monthly rules and CoA names (employee=3182, company=3181), NOT the sheet — its interim columns are transposed, same known issue as the 2026-07 tax sheet; 19.0.1.22.0 fixed the crossing that 1.21.0 copied in.** Codes `1731`/`1732`/`1733` added to the gec_localization CoA CSV (additive rows, 19.0.1.2.0) and created-if-missing per existing ge-company by `_benefit_fill_missing_accounts`; fill-only-empty ships all rule mappings. No expense at pay-out (R6) — 7410/7490 accrue monthly via the normal salary rules |
| Partners (19.0.1.22.0) | The six prepaid/closing legs carry the Pension Agency / State Treasury partner like the monthly rules (a partner-less open payable line blocks the Pay button, and matching account+partner lets the E3 closings reconcile against E2's credits); the two `1730` net legs set `employee_move_line` so their lines split per employee with the employee as partner — the sheet's R4 |
| Per-slip amount | `remaining_total / remaining_installments`, last installment takes the exact remainder — self-correcting under count/total edits and rounding (10K/3 = 3333.33 + 3333.33/34 + rest). A line whose own total is 0 falls back to the program's Advance Total (19.0.1.17.0 — line amounts are copied at assign time, so a total typed after assigning employees would otherwise silently pay nothing) |
| Tracking | Pay-out = the once-stamp (`payslip_id`); repayments stay **stateless — the injected `ADVANCE` inputs ARE the ledger**, counted one-per-correction-chain (`_advance_carrier_inputs`, now filtered to the repayment input type so the pay-out input is never miscounted as an installment) |
| Payslip deletion/cancel | A deleted/cancelled repayment slip's inputs die → the count drops → the installment returns to the pool. Cancelling the pay-out slip releases the stamp → repayment inputs on drafts vanish on recompute and the pay-out re-offers itself on the next matching slip |
| Form-created slips (19.0.1.20.0) | The web form saves the NewId-computed input list explicitly (injection skips NewIds by design), which suppresses the server-side compute at create — slip 59 in live testing stayed input-empty forever. Fix: the create override re-marks fresh non-edited drafts (`add_to_compute` on `input_line_ids`) so injection runs once with real ids. Wizard/code-created slips never had the problem |
| Visibility | Computed `payslip_ids` ("Payslips") m2m on the line (pay-out + repayments) + state pending (no pay-out yet) / running / done (count reached on validated repayment slips) |
| Benefits slips | Carry separate-mode advance **pay-outs** (`ADVANCE_PAY` rule exists there) but never repayments; the Benefits structure has no `ADVANCE` rule (rule-existence gate as backstop). Only one live slip may carry an unstamped line's pay-out at a time |

7 advance tests in [test_benefits.py](../custom_addons/gec_payroll_types/geo_payroll/tests/test_benefits.py):
pay-out-with-salary + repayment tax math, pay-out-separate via wizard + next-month start,
stop-after-count, rounding remainder, deleted-repayment return, pay-out-cancel release,
program-total fallback. No new raises anywhere in the feature.

## 14. Verification record (2026-08-22)

Six adversarial reviewers checked 37 claims against source. Highlights that changed the
plan: corrections must mirror origin inputs (silent benefit un-pay otherwise); refunds
must be excluded from injection; `modified()` cannot trigger the input recompute;
the stock compute has no draft-state guard; `_get_paid_amount` returns full wage on
no-worked-days structures; BENNT needs explicit `country_id`; `GEC_BONUS_NT` needs its own
debit account or moves raise; payment flow is dead without §9's per-company config +
migration. Confirmed unchanged-by-design: refund copy-negate, correction chain checks,
Edit Payslip Lines reseeding (7 codes only), settlement-match guard (7 codes only),
paid-write attachment hook (no-op), bank bridge structure-agnostic, work-entry isolation,
tax linearity.

# Form 30 From Journal Entries: Plan B (2026-10-13)

> **Status (2026-10-13, second session):** step 1 committed by the user (`077d628`); phase 0 done on the test database `gec20_form30_test`; phase 3b in progress (build plan `Claude outputs/form30_planB_20261013/plans/build_plan_phase3b.md`); phases 5, 6, 7 open.
> **Earlier status (2026-10-13, end of first session):** plan B approved by the user as **provisional**: it is reviewed again after
> testing on a test database and may change. Phases 1 and 2 are built and committed (`f7d3ad1`, `d789e51`), not deployed on
> `gec20_prod1`. **Step 1** (3a + 2b + 0b + S1, section 6) is planned: build plan written, Opus bug-hunter run started, no code
> yet. Phases 0, 3b and 5-7 are open. Handoff for the next session: [form30_handoff_20261013.md](form30_handoff_20261013.md).
> The previous design (income type from account rules, rate guessed from amounts) is kept in
> [form30_entry_redesign_plan_v2_account_rules_20261013.md](form30_entry_redesign_plan_v2_account_rules_20261013.md) and
> summarised in [section 9](#9-alternatives-kept-for-after-testing).
> **Tags:** **[Certain]** read in code or data; **[Likely]** inferred, not run; **[Guessing]** depends on tax law or the accountant.
> **Sources:** the user and the accountant (2026-10-13), the accountant's table "rs.ge Form 30 Income Type" (xlsx, read
> 2026-10-13), the external review [form30_plan_review_astra.md](/private/tmp/form30_plan_review_astra.md) checked by our
> verifiers, and the current module ([gec_income_tax_report.md](gec_income_tax_report.md)).
> **Replaces** in [withholding_treasury_form30_plan.md](withholding_treasury_form30_plan.md): Rule B "withholding is chosen
> at payment", I-2, phases 2 and 5 (automatic Treasury payment), and the payment-withholding-line source of Form 30.

---

## Table of Contents

- [1. The flow in one example](#1-the-flow-in-one-example)
- [2. Decisions](#2-decisions)
- [3. Facts the design rests on](#3-facts-the-design-rests-on)
- [4. Design](#4-design)
- [5. Review findings and answers](#5-review-findings-and-answers)
- [6. Phases](#6-phases)
- [7. Decisions still open](#7-decisions-still-open)
- [8. Tests to propose (written only on a yes)](#8-tests-to-propose-written-only-on-a-yes)
- [9. Alternatives kept for after testing](#9-alternatives-kept-for-after-testing)
- [10. saas-19.4 (branch 19.0)](#10-saas-194-branch-190)
- [11. Evidence and agents](#11-evidence-and-agents)

---

## 1. The flow in one example

Ana does a service for 100 GEL; 20% income tax is withheld. The accountant books in two steps, as in her table. [Certain for
the table; prod1 MISC/2026/10/0017 is the one-step variant of the same entry]

| Step | Who | What happens |
|---|---|---|
| 1 | Accountant | Posts one entry: Dr 740100 100 / Cr 310110 100 Ana (accrual); Dr 310110 20 Ana / Cr 331320 20 State Treasury (withholding) |
| 2 | Odoo | The 331320 line gets **Withholding Tax** = "WHT 20% - Resident Individual Services": proposed from the accounts and Ana's category, editable |
| 3 | Odoo | Checks gross × rate = tax: 100 × 20% = 20. A different booked tax shows a warning on the entry |
| 4 | Accountant | **Pay** on Ana's line pays 80 (100 − 20 netted); **Pay** on the Treasury line pays 20 as a treasury transfer, code 101001000 |
| 5 | Bank | Both payments are matched with their bank transactions |
| 6 | Form 30 | One row for Ana: gross 100, tax 20, type 7 and rate 20 **from the tax**, category from Ana's contact, dated on the bank transaction of Ana's payment |

If Ana is paid in parts in two months (50 on 28 Sep, 30 on 3 Oct), September gets gross 62.50 / tax 12.50 and October gets
37.50 / 7.50: each part takes its share of the gross and the tax (50 of 80 = 62.5%). The accountant's check: 50 ÷ 0.8 × 0.2 = 12.50.

## 2. Decisions

| # | Decision | Who, when |
|---|---|---|
| 1 | Withholding is booked in the journal entry by hand, never at payment | user + accountant, 2026-10-13 |
| 2 | **Plan B:** the income type and rate come from a withholding tax named on the entry's tax line, as today's payment rows take them from the tax. The accountant's account table only proposes the tax. **Provisional, revisited after testing** | user, 2026-10-13 |
| 3 | The 23 withholding taxes stay active; their **Tax Type** becomes **None** (instead of archiving), so bills and the Pay dialog no longer offer them | user, 2026-10-13 |
| 4 | One row per person per source (entry or payslip) and per month of payment | user (U3, U2), 2026-10-13 |
| 5 | A row whose person's payment is not yet matched with the bank still appears, with a warning; export leaves warned rows out by default, a tick box includes them, and the user is warned before export | user (U1) |
| 6 | The row date is the bank transaction date of the person's own payment; tax and pension payments never give the date | user (U2 clarification) |
| 7 | **U2:** a person paid in parts in different months gets one row per month, each part with its share of the gross and the tax | user + accountant, 2026-10-13 |
| 8 | **U3:** several people in one entry give one row each; the tax and pension are split by each person's share of the net | user, 2026-10-13 |
| 9 | **U5:** a row whose tax is not paid yet is exported, with the note "tax was due with the payment on <date>: late". Tax is due when the person is paid (Tax Code art. 154); the 15th is the declaration deadline | user, 2026-10-13; rule checked on the rs.ge page and art. 154 |
| 10 | U0: the classification (Withholding Tax) is kept on the entry and is editable. U4: the annex E service type comes from the tax (as today); when the tax has none, from the contact's default | user (U0; U4 confirmed 2026-10-13) |
| 11 | The old source (withholding lines on payments) stops producing new rows; existing rows keep their links (no migration) | user decision 6 of the previous plan, narrowed by review R8 |

## 3. Facts the design rests on

| Fact | Evidence |
|---|---|
| Today's payment rows take income type and rate from the tax: `rate = abs(tax.amount)`, chosen because tax ÷ base is unreliable | [rs_form30_declaration.py:363, :367](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L363); [gec_income_tax_report.md](gec_income_tax_report.md) Design Decisions |
| The RS rules belong to the income type; the tax's "RS Declaration Rules" tab is a window onto them, shown when the tax has **Withhold** ticked | [account_tax.py:35-36](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/account_tax.py#L35); [account_tax_views.xml:11](../custom_addons/gec_odoo_modules/gec_income_tax_report/views/account_tax_views.xml#L11); prod1: 152 rules, 15 types |
| Odoo offers withholding in the Pay dialog and on the payment only for taxes with Tax Type **Purchases** (outbound) | [account_withholding_line.py:429-434](../addons/l10n_account_withholding_tax/models/account_withholding_line.py#L429), [wizard :126-152](../addons/l10n_account_withholding_tax/wizards/account_payment_register.py#L126), [payment :48-65](../addons/l10n_account_withholding_tax/models/account_payment.py#L48) |
| The bill line tax picker lists only Purchases taxes; an entry line's picker has no type filter | [account_move_views.xml:1368, :1578](../addons/account/views/account_move_views.xml#L1368), [account_move.py:7276-7282](../addons/account/models/account_move.py#L7276) |
| A withholding tax on an entry line books nothing (prod1 test entry 322: the WHT tax on 740100 produced no tax line) | prod1 move 322, 2026-10-13; [l10n_account_withholding_tax account_tax.py:80-81](../addons/l10n_account_withholding_tax/models/account_tax.py#L80) |
| Changing a used tax's Tax Type is not blocked | [account_tax.py:626-628](../addons/account/models/account_tax.py#L626) |
| Apply Tax / RS Change refuses a tax whose Tax Type is not Purchases | [rs_form30_tax_change.py:138-141](../custom_addons/gec_odoo_modules/gec_income_tax_report/wizard/rs_form30_tax_change.py#L138) |
| prod1 has 23 withholding taxes (purchase, active): 18 mapped to a Form 30 type; gift, goods 3%, non-resident other, telecom and oil & gas have none; types 6, 16, 18 (expired 202411), 20, 21, 22, 23, 24 have no tax; no tax has a service type | prod1 `account_tax`, 2026-10-13 |
| The accountant's table books in two steps (accrual C/D, then withholding D/F), F = 331210 (salary 331310), "331320 may be used on all entries except salary" | xlsx, 2026-10-13 |
| 331210 and 331212 are not payable (`liability_current`, no reconcile): a tax line there cannot use Pay; 331320 can | prod1 `account_account` ids 172, 174 |
| Paying entry lines nets the open lines of one partner, account and currency; direction from the balance sum, amount from the residual sum | [account_payment_register.py:286-292, :305, :398-399](../addons/account/wizard/account_payment_register.py#L286) |
| A second Pay dialog after full settlement is refused by core; after a partial one it can overpay | verifier ROW3.1, ROW3.2 |
| The CIT wizard puts the shareholder as partner on the withholding line; its account can be any account (prod1 MISC/2026/10/0018: WHT 50 on payable 340120, partner Emma Granger) | [cit_wizard.py:40-43, :96](../custom_addons/gec_odoo_modules/gec_localization/wizards/cit_wizard.py#L40); prod1 move 318 |
| A payslip correction is computed in full; geo_payroll nets origin, refund and correction so only the difference is paid; today's builder reports every paid slip's GROSS (1,000 + 1,100 = 2,100) | [hr_payslip_account.py:106-160](../custom_addons/gec_odoo_modules/geo_payroll/models/hr_payslip_account.py#L106), [rs_form30_declaration.py:246](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L246); verifier R10a-d |
| `reversal_move_ids` has no state filter; posting a cancel-reversal unreconciles the original from the person's payment | [account_move.py:661](../addons/account/models/account_move.py#L661); verifier R5a-b |
| A payment's bank transactions are links (`reconciled_statement_line_ids`), not amounts | [account_payment.py:804-830](../addons/account/models/account_payment.py#L804) |
| Declarations have two states, one per company and month; nothing records which rows went into a file; Reset + Generate deletes generated rows; an emptied annex keeps its old file; `write` guards only a company change | [rs_form30_declaration.py:116, :133-134, :174, :183-222](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L116); verifier R2, R9, R14 |
| The treaty allowance is drawn read-then-create at Generate, per contact across companies; usage rows cascade with their declaration rows | [rs_form30_declaration.py:638-667](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L638); verifier R15 |

## 4. Design

### 4.1 Withholding taxes become Form 30 classifiers

- **Tax Type = None** on the 23 taxes (phase 0, configuration). Effects [Likely, from the code above; to be tried on a test database]:
  - the Pay dialog and payment form no longer offer withholding; vendor bills can no longer carry these taxes;
  - the taxes stay active, keep **Withhold** ticked, their Form 30 income type, validity dates and the RS Declaration Rules tab.
- **Apply Tax / RS Change** accepts Tax Type None (one condition in [rs_form30_tax_change.py:138-141](../custom_addons/gec_odoo_modules/gec_income_tax_report/wizard/rs_form30_tax_change.py#L138)); the replacement tax it creates keeps the same Tax Type.
- **Every income type used needs a tax.** Missing today (prod1 SELECT, verified 2026-10-13): 6, 16, 18 (expired 202411), 20, 21 (returned pension), 22, 23, 24. Type 6 can come from the gift, goods and non-resident-other taxes once they get an income type. New taxes go into `gec_localization`'s template with Tax Type None (accountant: rates, A9).
- **New template taxes** come with Tax Type Purchases unless the template says None. The template rows of withholding taxes are changed to None (phase 3b). An upgrade never rewrites existing taxes, so this protects new companies and a reinstall of gec_localization (which reloads the template values, addons/account/models/ir_module.py:85); existing companies get None from phase 0.

### 4.2 Withholding Tax on the entry line

| Field on `account.move.line` | What it holds |
|---|---|
| Withholding Tax (`gec_withholding_tax_id`, gec_localization) | A withholding tax with a Form 30 income type. Set on the entry's tax line (F). Called "Form 30 Tax" in earlier drafts |
| Picked by hand (technical, `copy=False`) | Set when the user chooses the tax; the proposal never overwrites it. Precedent: `technical_price_unit`, [sale_order_line.py:229, 767-795](../addons/sale/models/sale_order_line.py#L229) |

- **Proposal** (only on posted general-journal entries that are not payment, statement or payslip entries):
  1. the accountant's table gives the income type from the accrual accounts (C debit, D credit);
  2. among the taxes of that type, keep those whose rate the RS rules allow for the recipient's category on the entry date;
  3. exactly one left: proposed; otherwise empty, and the entry shows "pick the Form 30 tax".
- The table is stored per company with its defaults from the xlsx, created only where missing and never re-run on upgrade (review R16). Collisions in the table (16/20, 22/23, 19/24 share accounts) only leave the proposal empty (A1).
- **Check:** expected tax = round((gross − employee pension) × rate / 100, 2), compared with the booked tax; a difference is a warning on the entry and on the row. The rate is never derived from amounts.
- **Recipient(s):** the partners of the liability lines (D) that net to a credit; never the partner on the tax line (review R13.7).
- **Safety net on the entry:** a posted entry with a credit on a withholding tax account (331210, 331212, 331310, 331320 for non-salary) and no Withholding Tax shows "Form 30 tax missing" and is listed on the declaration (review R11).
- **Detect Again** is a button (entries not picked by hand, open months only); it never runs on install or upgrade.

### 4.3 Pay button (built in phase 2) and its fixes

Built: Pay on each open payable credit line of a posted general-journal entry, netting the open lines of the same partner and
account; refusals for no partner, other contacts on the account, mixed currencies, nothing owed, method without Outstanding
account; hidden on payslip entries.

Fixes (phase 2b):
- **A line with a Withholding Tax is paid only to a contact with a Treasury Code** (an account-based rule was dropped: on MISC/2026/10/0018 the dividend itself sits on 331320 and the tax on 340120). Otherwise: "This is a tax line: set the State Treasury as its partner." (review R13, prod1 MISC/2026/10/0018)
- **CIT wizard:** the withholding line and the CIT line get the State Treasury contact as partner; its tax account defaults to 331320 (A5, A7).
- The mixed-currency message no longer points to Amounts to Settle, which does not list misc lines without a due date.
- Optional: a residual check at Create Payment, like the payroll snapshot guard, against a stale dialog after a partial payment (ROW3.2).

### 4.4 Rows

**Sources.** (a) posted entries with a Withholding Tax; (b) paid payslips (type 1, unchanged source); (c) manual rows.

**Discovery (review R3).** A month's candidates are found from the payment side, not from the source date:
the person's liability lines settled by payments or bank transactions dated in the month, followed back to their source.
Sources with no settlement at all stay in an **Unpaid** list on the declaration (no row, no date).

**Amounts per person.**

| Item | Rule |
|---|---|
| Net | net credit on the liability account (D) for the person, after all debits on D in the entry |
| Tax | the entry's net credit on its tax line(s); with several people, split by each person's share of the net (U3); rounding remainder on the last person |
| Employee pension | named accounts only: credits on the pension liability (332010) minus debits on the employer-pension expense accounts named in the company setting (721000, 740900); never "any other expense" (review R7) |
| Gross | net + tax + employee pension (100 for both the one-step and two-step booking; 1,000 for a dividend 950 + 50) |
| Rate, type | from the Withholding Tax |
| Category, residency | from the contact on the row date, as today |
| Currency | GEL company books only; a foreign-currency source is warned until A8 is answered |

**Settlement and month (U2).** The person's liability lines are followed through `account.partial.reconcile`:

| Settlement | Counts as cash | Date |
|---|---|---|
| A payment matched with the bank | yes | the bank transaction date |
| A payment not yet matched | yes, with a **warning** | the payment date |
| A bank transaction reconciled directly on the line | yes | the bank transaction date |
| Netting inside the entry (Dr D tax, Dr D pension) | no | — |
| Write-off, exchange difference, another entry | no: the row is warned "settled without payment" | — |

Each payment part takes its share of the gross and the tax: part ÷ net. Parts in one month make one row; parts in two months
make one row per month. A payment that settles two sources is split by its partial amounts, which `account.partial.reconcile`
records per line.

**Salaries (type 1).** Checked on 2026-10-13 against prod1 (Opus bug-hunter on 3 scout reports): September Form 30 tax
6,287.95 = 331320 credits, pension 603.26 = half of 332010; advances, repayments and exempt relief are right. The paths that
break, and the plan's answer:

| # | Path | Today | Plan B |
|---|---|---|---|
| S1 | A net-pay payment is rejected or never sent; core "Mark Unpaid" keeps `paid_date`; the slip is paid again next month | declared in both months (Pay Salaries), or kept in the old month (Register Payment) | step 1: Mark Unpaid clears the Payment Date and a new payment's date wins; phase 5: a rejected or cancelled payment is never the main settlement, and a row In File whose payment is later rejected is warned |
| S2 | Net pay settled straight from a bank statement line | slip never Paid, never declared | phase 5: salary candidates = slips whose NET line is settled (payment or statement line), not slips in state Paid |
| S3 | Zero net but income tax above zero (no NET line) | never declared | phase 5: such a slip is a candidate on its validation date, with a warning |
| S4 | Net paid in two parts in two months | all in the last month | phase 5: split by month, as U2 |
| S5 | No bank statements matched (prod1: all 11 payslip payments unmatched, Basis journal 0 statement lines) | n/a | every row would be warned and left out by default: open question U6 |

- The date becomes the bank transaction of the net-pay payment (payment date with a warning before matching, see U6).
- The safety net "tax credit without Withholding Tax" skips payslip entries.
- Keep payroll's net posting to 310310 and income tax on 331320: the table's 331310 is not payable, so Pay Salaries would refuse every slip, and a gross posting to 310310 would overpay the employee (A3).
- **Corrections:** an origin, its refund and its correction are reported as one family: if all are paid in the same month, one row with the correction's figures; if the origin was declared earlier, the correction month gets the difference (gross, tax, pension) as its own row. A correction whose difference is zero gives no row. Accountant to confirm (A10).
- Zero-net slips, advances and benefits paid to third parties: as today, plus a warning listing them, until A10 is answered.
- The settled NET line is read from the posted entry itself, not from today's salary-rule account (review R10g).

**Reversals (review R5).** A posted reversal of an **unpaid** source removes it. A source that was paid and later reversed stays,
with a warning "reversed after payment: correct the declaration". Draft reversals are ignored.

**Annex E.** Entries whose Withholding Tax has a service type and whose recipient is flagged IE or Small Business, dated by the same
rule. Lines get the source entry, a date, a warning and the export mark (review R11d).

**Warnings and notes.**

| Kind | Examples | Export |
|---|---|---|
| Blocker | missing ID, category, type, date; RS rule refuses the pair or rate; currency not GEL | never |
| Warning | payment not matched with the bank; booked tax ≠ expected tax; settled without payment; reversed after payment; Form 30 tax picked against the proposal | left out by default; the tick box includes them |
| Note | tax or pension not paid yet: "tax was due with the payment on <date>: late" (U5) | exported |

**Rate-table check.** The constraint runs only for hand-made rows; generated rows carry problems as blockers, so one bad row
no longer stops Generate Lines for everyone.

**Old source.** No new rows from payment withholding lines. Existing rows keep `withholding_line_id`; a payment withholding line
dated in the month is listed as a warning on the declaration. A bill or invoice carrying a withholding tax, paid in the month,
is listed too.

### 4.5 Export and history

- Each row gets **In File** (set at export) and the export date. Excluded rows never count as declared (review R2).
- **Already declared:** a source + person + month already **In File** of another declaration is skipped. A source declared under one month whose bank date later moves gets a warning "declared in September, bank date is October: correct one of them" instead of a silent skip.
- **Reset to Draft** keeps rows that were In File; Generate rebuilds only the others. An exported declaration therefore keeps its evidence (verifier: today's Reset + Generate deletes it).
- **Export** recomputes the selected rows (In File = not warned, or warned with the tick box), checks them again (freshness, review R14), clears files of annexes that became empty, rebuilds the explanation workbook (review R9), and is refused while another export of the same declaration runs (row lock).
- **Server-side lock:** rows In File cannot be written or deleted except through Reset to Draft (review R14).
- **Treaty allowance** is drawn at export only, under a lock on the contact, once per row; Reset releases it explicitly instead of by cascade (review R15).
- Counts on the form: rows in file, rows left out, warnings, blockers, unpaid sources.
- No "filed/accepted" state: the user uploads to rs.ge; the export date is the record. [the review's revision snapshots go further than needed]

## 5. Review findings and answers

### 5.1 Our bug-hunter on the previous plan (H1-H20)

All 20 were answered in the previous version; their answers still hold under plan B except H9/H10/H17 (rate and type now come
from the tax) and H11/H13 (the proposal table is created once and never re-runs detection).

### 5.2 External review (Astra/Sol), checked by 4 Haiku scouts and 4 Opus verifiers

| ID | Finding | Verdict | Answer in plan B |
|---|---|---|---|
| R1 | Withhold-and-Pay sends the gross to the bank; archiving is no send guard | confirmed (existing code); no bank exposure on prod1 today | phase 0b: refuse a bank send of any payment with withholding lines; Tax Type None removes new ones |
| R2 | "Exported" ≠ declared; Reset + Generate deletes the evidence | confirmed (history part); filing state overstated | 4.5 In File, Reset keeps exported rows |
| R3 | One-month lookback misses older sources; no unpaid list | confirmed | 4.4 discovery from the payment side; Unpaid list |
| R4 | Partial, grouped, write-off settlements need amounts | confirmed / partly | 4.4 settlement table, U2 split by month |
| R5 | Reversal links erase paid income; plan §10 D2 "none" was wrong | confirmed | 4.4 reversals; section 10 D2 corrected |
| R6 | U5's "due by the 15th" reason is wrong | confirmed (rs.ge page, art. 154) | decision 9, note wording |
| R7 | Pension formula breaks with unrelated expense lines | confirmed | 4.4 named pension accounts |
| R8 | Removing the old source is a migration; manual rows need a path | partly | decision 11 (keep links); manual rows already survive; a create action for them in phase 5 |
| R9 | Emptied annex keeps its old file; workbook stale | confirmed (existing bug) | 4.5 |
| R10 | Payroll corrections reported in full | confirmed (live bug, 0 cases on prod1) | 4.4 salaries, A10 |
| R11 | Entries without a tax line give no row; annex E too broad | confirmed | 4.2 safety net; annex E only for service taxes |
| R12 | Rate guessed from amounts is unreliable | partly (no ambiguous non-salary pair in 2026) | removed: rate from the tax |
| R13 | Pay sends the dividend tax to the shareholder | confirmed on prod1 MISC/2026/10/0018 | 4.3 phase 2b |
| R14 | Rows go stale; no server-side lock | confirmed | 4.5 |
| R15 | Treaty allowance race and cascade | confirmed / partly | 4.5 |
| R16 | Defaults re-detect on upgrade; branch access | partly | 4.2 created once, no detection on upgrade; rule access via the parent company (`parent_of`) |
| — | Second Pay dialog after full payment | refuted (core refuses) | — |
| — | Failed export loses the previous one | refuted | — |

## 6. Phases

Each phase: `odoo-builder` writes it, scouts collect the result, `odoo-reviewer` and `odoo-verifier` for critical phases, the
existing module tests on a scratch database; the user approves and commits.

| Phase | Goal | Modules | Status |
|---|---|---|---|
| 0 | Tax Type = None on the withholding taxes; settle open bills that carry a withholding tax first (a bill still open at the switch is paid at the gross, no tax booked). prod1 holds test data: no per-record cleanup (user 2026-10-13) | test DB | **done on `gec20_form30_test`** (fresh DB, generator data, 46 taxes in 2 companies, 2026-10-13); prod1 when the user decides |
| 0b | Refuse a bank send (single, batch, approval) of a payment with withholding lines | gec_bank | part of step 1 (built) |
| 1 | Treasury type and code from the contact (Basis, TBC); BOG refuses treasury payments | basis_bank, tbc_bank, bog_bank | **built, committed `f7d3ad1`**; 289/289 tests |
| 2 | Pay button on entry lines; hidden on payslips; payslip date order | gec_localization, geo_payroll | **built, committed `d789e51`**; 360/360 tests |
| **Step 1** = 3a + 2b + 0b + S1 | **3a:** Withholding Tax field on journal items (no proposal); change wizard accepts Tax Type None. **2b:** a line with a Withholding Tax is paid only to a Treasury Code contact; CIT wizard sets the field and the State Treasury on its tax lines; message fix. **0b** (row above). **S1:** Mark Unpaid clears the payslip Payment Date; a new payment's date wins | gec_localization, gec_income_tax_report, gec_bank, geo_payroll | **built 2026-10-13 (second session), committed by the user `077d628`**: build plan v3; 289 + 409 existing tests green; repro 12/12; Opus reviewer (no blocker, 4 should-fix, fixed) + Opus verifier (2 payroll-date claims confirmed, fixed: D2 new date only for slips the payment paid; D1 clears only when an Odoo payment once paid the slip); ka_GE strings. Provisional: CIT withholding account default 331320 and dividend tax default (A5, A7). Before prod1 `-u` ||
| 3b | Proposal table with xlsx defaults, amount check, safety net, taxes for the types that have none | gec_income_tax_report, gec_localization | open (A1, A9) |
| 5 | Row builder from entries and payslips: discovery, settlement and month split, people split, corrections, reversals, annex E, warnings and notes, Unpaid list | gec_income_tax_report | open |
| 6 | Export history: In File, Reset keeps exported rows, freshness, file clearing, lock, allowance at export, counts | gec_income_tax_report | open |
| 7 | Docs, READMEs, ka_GE, saas-19.4 backport, developer maps | all touched | open |

Phase 4 of the previous plan (type on the entry) is merged into phase 3.

## 7. Decisions still open

| ID | Question | Who |
|---|---|---|
| A1 | Account table collisions (16/20, 22/23, 19/24 share C and D): which accounts separate them, or leave the proposal empty | accountant |
| A2 | Non-residents: tax line on 331212 or 331320 | accountant |
| A3 | Salary income tax: payroll posts 331320, the table says 331310. Recommendation: keep 331320 (331310 is not payable, so Pay Salaries would refuse every slip). Employer pension: payroll posts 740900, the table says 721000 (P&L only, no Form 30 effect; a change needs the 10 prod1 rule accounts edited) | accountant |
| A4 | Type 7 with pension 2% + 2%: is the employee 2% deducted before the 20% | accountant |
| A5 | Dividends: C = 510310 (table) or 530110 (CIT wizard); tax account 331320 | accountant |
| A6 | Types 22/23 paid straight from the bank in the entry (D = 120110): declare by entry date, or leave to the portal | accountant |
| A7 | Liability accounts that cannot be paid (310990 for 5, 6, 16, 20; 120110 for 22, 23) and tax account 331210 (not payable): switch to payable accounts for the Pay flow | accountant |
| A8 | Foreign-currency entries: GEL rate of the entry date or of the payment date | accountant |
| A9 | Taxes to create for types 6, 16, 20, 21, 22, 23, 24 (18 expired 202411) (rates), and the income type of the gift, goods 3%, non-resident other, telecom and oil & gas taxes | accountant |
| A10 | Payroll: correction families (difference in the correction month), advances (month of the advance or of the final slip), zero-net slips | accountant |
| A11 | Type 18 in the table: valid only to 202411 in the RS classifier, and no payroll rule uses 310315. What are these payments | accountant |
| U6 | Bank statements: are they imported and matched every month? If not, every row is "payment not matched" and left out by default; the tick box includes them | user |

## 8. Tests to propose (written only on a yes)

| Phase | Behaviour |
|---|---|
| 0b | A payment with withholding lines is refused at single send, batch send and approval |
| 2b | Pay on a tax line with a non-Treasury partner is refused; CIT wizard lines carry the Treasury |
| 3 | Proposal picks the one tax allowed for the category; two candidates leave it empty; picked-by-hand survives; amount check warns at 19 instead of 20; Tax Type None hides withholding in the Pay dialog |
| 5 | One-step and two-step entries give gross 100 / tax 20; 50 in Sep + 30 in Oct give 62.50 / 12.50 and 37.50 / 7.50; two people split 20 / 20; write-off is warned; July payment banked in October is found; correction 1,000 → 1,100 gives 1,000 then +100, not 2,100 |
| 6 | Excluded rows are not In File; Reset keeps exported rows; emptied annex file cleared; allowance drawn once |

## 9. Alternatives kept for after testing

| Option | Idea | Why not now |
|---|---|---|
| A: tax computed on the entry line | The tax on the expense line; Odoo books the tax line | The 23 taxes would have to stop being withholding taxes, which also changes vendor bills; the tax line's partner is unchecked. prod1 entry 322 showed a withholding tax on an entry line books nothing |
| Previous plan (v2): account rules | Income type from the account combination per company; rate fitted from booked tax ÷ base | Contradicts today's documented rate rule; no law-change tool; small-amount and treaty cases. Full text: [v2 backup](form30_entry_redesign_plan_v2_account_rules_20261013.md) |

## 10. saas-19.4 (branch 19.0)

The core APIs plan B uses are the same in saas-19.4 (withholding domain, Tax Type, payment register, reconciliation,
`ir.access.csv`). Differences:

| # | Difference | Plan B |
|---|---|---|
| D1 | `action_payslip_paid` writes today's Payment Date; geo_payroll now writes the date after it (phase 2) | done in 20.0; port with phase 7 |
| D2 | `_reverse_moves(cancel=True)` unreconciles before copying. **Effect is not "none":** reversals are handled in 4.4 | test reversal cases on both versions |
| D3 | `set_line_bank_statement_line` has no `allow_partial` | new code passes only the ids |
| D4 | Withholding line without number refused | none once Tax Type is None |
| D5 | `account.move.line.name` is the Label on 19.4 | new code does not read labels |
| D6 | Manifest `saas~19.4.x`, Font Awesome icons | `v20_only` rows in the port docs |

`gec_prod1` runs Odoo 19.0, not saas-19.4; plan B does not apply to it without an Odoo upgrade. The port happens per phase
after the 20.0 commit (`docs/backport_tools`, port docs), with the module tests on a saas-19.4 test database.

## 11. Evidence and agents

- prod1 checks (2026-10-13, read-only): MISC/2026/10/0007, 0010, 0013, 0017, 0018, 0019; SLR/2026/09/0016; test drafts 321, 322; payments 83-86, 88-99, 105-107; the 23 withholding taxes and their accounts; 152 RS rules.
- Built phases 1-2: 289 + 360 existing tests green; runtime repro on scratch databases (78 netting, Treasury from the contact, refusals, BOG block, payslip hiding).
- Agents on 2026-10-13: previous plan 9 + 6 Haiku scouts, 1 Opus bug-hunter, 1 Opus verifier; phases 1-2 build: 11 Haiku scouts, 10 Sonnet builders, 2 Opus bug-hunters, 2 Opus reviewers, 1 Opus verifier; external review check: 4 Haiku scouts, 4 Opus verifiers; plan B facts: 2 Haiku scouts.

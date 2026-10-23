# Form 30 From Journal Entries: Redesign Plan (2026-10-13)

> **Status (2026-10-13):** phases 1 and 2 **built on 20.0, uncommitted** (see [6.1](#61-built-phases-1-and-2)); phases 0 and
> 3-7 open. Plan reviewed by the Opus bug-hunter (5 blockers, 11 should-fix, all taken into this version) and the Opus
> verifier (10 claims: 8 confirmed, 2 refuted and corrected). Checked against the Odoo 20 source in this repo and
> `gec20_prod1` (read-only `SELECT`s).
> **Tags:** **[Certain]** read in code or data; **[Likely]** inferred, not run; **[Guessing]** depends on tax law, not code.
> **Source of the change:** the user and the accountant (2026-10-13), with the accountant's table
> "rs.ge Form 30 Income Type" (xlsx, 15 types × accrual and withholding accounts).
> **Replaces** in [withholding_treasury_form30_plan.md](withholding_treasury_form30_plan.md):
> - Rule B "withholding is chosen at payment"; withholding is now **booked in the journal entry by hand**.
> - I-2, phase 2 and phase 5 (the automatic Treasury payment).
> - The payment-withholding-line source of Form 30.
>
> Phase 5a of that plan is phase 1 here.

---

## Table of Contents

- [1. The new flow in one example](#1-the-new-flow-in-one-example)
- [2. What the user and the accountant decided](#2-what-the-user-and-the-accountant-decided)
- [3. Facts the design rests on](#3-facts-the-design-rests-on)
- [4. Design](#4-design)
- [5. Review findings and how the plan answers them](#5-review-findings-and-how-the-plan-answers-them)
- [6. Phases](#6-phases)
- [7. Decisions](#7-decisions)
- [8. Tests to propose (written only on a yes)](#8-tests-to-propose-written-only-on-a-yes)
- [9. Evidence and agents](#9-evidence-and-agents)
- [10. saas-19.4 (branch 19.0) compatibility](#10-saas-194-branch-190-compatibility)

---

## 1. The new flow in one example

Ana is owed 100 GEL for services, 20% is withheld. Prod1 already has this entry: MISC/2026/10/0017. [Certain]

| Step | What happens | Accounts |
|---|---|---|
| 1 | The accountant posts one journal entry with the withholding inside it | Dr 740100 100 / Cr 310110 80, partner Ana / Cr 331320 20, partner State Treasury |
| 2 | Odoo recognises the combination 740100 / 310110 / 331320 as income type **7** (service fee) and shows it on the entry | — |
| 3 | Each payable credit line has a **Pay** button: Ana's pays 80; the Treasury's pays 20 as a treasury transfer, code 101001000 | two payments |
| 4 | The bank statement arrives; both payments are reconciled with their bank transactions | — |
| 5 | **Generate Lines** gives **one** Form 30 row for Ana: gross 100, tax 20, rate 20, dated on the **bank transaction** of Ana's payment | — |

Payroll works the same way. SLR/2026/09/0016 has three payments (net pay, pension, income tax) and gives **one** row, dated on the bank transaction of the net pay.

## 2. What the user and the accountant decided

| # | Decision | Source |
|---|---|---|
| 1 | The income type comes from the account combination: **C** expense (debit), **D** liability to the person (credit), **F** tax (credit). Defaults come from the xlsx; the accountant can change them. For every type except salary, F may also be **331320** | user, accountant |
| 2 | Withholding is booked in the entry by hand, never at payment. Each payable line of a misc entry gets a **Pay** button. No partner on the line → error. The withholding options are hidden | user |
| 3 | One Form 30 row per **source entry** (salary slip or misc entry), not per payment | user |
| 4 | A row whose payment is not yet reconciled with the bank still appears, with a **warning**. Export leaves warned rows out by default, a tick box includes them, and the user is warned before exporting | user |
| 5 | The row date is the **bank transaction date** of the person's payment, once reconciled. The pension and Treasury payments are never the "main" one | user |
| 6 | The old source (withholding lines on payments) is **removed** | user |
| 7 | Detection result is kept on the entry, not in Odoo's withholding table (that table belongs to a payment, and Odoo books the tax again from it) | user asked, plan recommends (U0) |

## 3. Facts the design rests on

| Fact | Evidence |
|---|---|
| MISC/2026/10/0017 = Dr 740100 100 / Cr 310110 80 (Ana) / Cr 331320 20 (Treasury), paid by PBNK5/2026/00023 (80) and 00024 (20) on Basis. Neither payment is matched to a bank line | prod1 lines 1016-1018, payments 106-107 |
| SLR/2026/09/0016: 4 payable lines, 3 payments; one pension payment (56) covers both 2% shares; the employer share is debited on 740900 | prod1 lines 730-735, payments 83-85 |
| All 24 accounts of the xlsx exist. **310990, 331210, 331212 and 120110 are not reconcilable payables**, so no payment or bank line can settle them. 331320 and 310110 are reconcilable payables | prod1 `account_account` |
| Paying one entry line (`account.move.line.action_register_payment`) has no check on entry type or partner. The payment's counterpart uses **that line's account**, and the wizard reconciles on it | [account_move_line.py:1729](../addons/account/models/account_move_line.py#L1729), [account_payment_register.py:1082, 1154, 1264-1293](../addons/account/wizard/account_payment_register.py#L1082); prod1 partials 230, 231 (verifier V2) |
| Open lines of the same partner and account are netted into one payment by the dialog | [account_payment_register.py:358-401](../addons/account/wizard/account_payment_register.py#L358) |
| A payment method line without an Outstanding account posts **no** journal entry | [account_payment.py:687-689, 1146](../addons/account/models/account_payment.py#L687); prod1: Manual Payment on BNK2-BNK7, CSH1 |
| The withholding radio, tab and lines show only while the company has an **active** withholding tax: both computes search with the default active filter | [wizard:126-152](../addons/l10n_account_withholding_tax/wizards/account_payment_register.py#L126), [payment:48-65](../addons/l10n_account_withholding_tax/models/account_payment.py#L48) (verifier V1) |
| Archived taxes stay archived on `-u gec_localization`: its maintenance function only creates missing xmlids and never writes `active`. A **new** tax added to the template later would come back active | [template_ge.py:50-67](../custom_addons/gec_odoo_modules/gec_localization/models/template_ge.py#L50) (verifier V7) |
| Odoo's withholding line must belong to a payment, and adding one makes Odoo rewrite the payment's entry with the tax lines | [account_payment_withholding_line.py:18-20](../addons/l10n_account_withholding_tax/models/account_payment_withholding_line.py#L18), [account_payment.py:122-128](../addons/l10n_account_withholding_tax/models/account_payment.py#L122) |
| Bank transaction of a payment: `reconciled_statement_line_ids` (from its Outstanding line; gec_bank auto-match reconciles that line). Bank transaction of an entry paid straight from the bank: `counterpart_line.statement_line_id`. Date = the statement line's move date | [account_payment.py:199-208, 804-830](../addons/account/models/account_payment.py#L199), [gec_bank:84-97](../custom_addons/gec_odoo_modules/gec_bank/models/account_bank_statement_line.py#L84), [account_move_line.py:207-213](../addons/account/models/account_move_line.py#L207) (verifier V3, V4) |
| prod1: no payment of MISC 0017 or SLR 0016 is bank-matched yet. MISC/2026/10/0007 was paid straight from BNK1 by two transactions (140 + 40) | prod1 statement lines 117, 118 |
| Treasury payments PBNK5/2026/00022 and 00024 have no transfer type and no code: Basis cannot send them | prod1 payments 105, 107 |
| `basisbank_transfer_type` is a plain field, editable on the payment form, filled by code only from Pay Salaries. TBC's `tbc_transfer_type` is computed and **overwrites a manual Treasury** when the bank account or currency changes | [basis views:37](../custom_addons/gec_odoo_modules/basis_bank/views/account_payment_views.xml#L37), [tbc account_payment.py:104-124](../custom_addons/gec_odoo_modules/tbc_bank/models/account_payment.py#L104) (verifier V9, corrected) |
| Form 30 export writes every row and ignores warnings; the main-part totals, `warning_count` and the workbook use every row | [rs_form30_declaration.py:149-157, 198-218, 421-473](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L149) |
| The rate-table check is a constraint on every row: one refused row stops Generate Lines for everyone | [:804-820](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L804) (verifier V6) |
| An exported declaration **can** be reset to draft and rebuilt (Reset to Draft button, no group) | [:220-222](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L220), [views:29](../custom_addons/gec_odoo_modules/gec_income_tax_report/views/rs_form30_declaration_views.xml#L29) (verifier V5, refuted my claim) |
| `payslip_ids` on an entry exists only with `hr_payroll_account`: geo_payroll has it, gec_localization does not | verifier V8 |
| A row button inside an embedded list works on a read-only list. Core precedent: picking moves, "Details" button | [stock_picking_views.xml:405-406](../addons/stock/views/stock_picking_views.xml#L405) (verifier V10) |
| The RS rate table separates 19 from 24 by category from 2025/05, but not 16 from 20 or 22 from 23 | [rs.form30.rate.rule.csv](../custom_addons/gec_odoo_modules/gec_income_tax_report/data/rs.form30.rate.rule.csv) rows 36/39, 48/53, 56/57 |

## 4. Design

### 4.1 Account combinations (configuration)

- **New model `rs.form30.account.rule`**, one row per income type and company: company, income type, **Expense account** (C), **Liability account** (D), **Tax accounts** (F, several).
  - E is the same account as D, so it needs no field.
  - A new model is needed because F holds several accounts and rules are per company.
  - The rules show as a list on the income type form (current company) and under the Form 30 configuration menu.
  - `ir.access.csv`: read for users, full for accounting managers, and a company restriction row.
  - Lookup uses `company.root_id`, so branches use the parent's rules.
- **Defaults** come from the xlsx. They are created only where a company has no rule yet, so the accountant's edits survive upgrades. Pattern: the `_rs_form30_map_ge_taxes` data function ([account_tax.py:68-79](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/account_tax.py#L68)).
  - Non-salary types get F = the file's account + 331320 (+ 331212 if A2 says yes).
  - Type 21 gets no rule.
  - The function then runs **Detect Again**, so entries posted before the install get a type.
- **Warnings on a rule** (shown, not blocking, so the accountant sees what to fix):
  - **Collision:** another rule has the same C and D and an F account in common.
  - **D cannot be paid:** D is not a reconcilable Payable account. Entries of this type could never be paid or dated. This applies to the file's 310990 (types 5, 6, 16, 20) and 120110 (types 22, 23). See A7.

### 4.2 Detection kept on the entry

| Field on `account.move` | What it holds |
|---|---|
| Form 30 Income Type | Set when exactly one rule matches. **Editable** |
| Picked by hand (technical, `copy=False`) | Set when the user picks the type. Detection never overwrites such an entry. Core precedent: `technical_price_unit` in [sale_order_line.py:229, 767-795](../addons/sale/models/sale_order_line.py#L229) |
| Form 30 Recipient | The partner on the D line |

- Detection looks only at posted general-journal entries. It skips:
  - payslip entries (`payslip_ids`);
  - payment entries (`origin_payment_id`);
  - bank statement entries (`statement_line_id`);
  - reversed entries and their reversals (`reversal_move_ids`, `reversed_entry_id`).
- Entries where several types fit keep the type empty. Generate Lines then keeps the only type the RS table allows for the recipient's category on that date, which settles 19 vs 24. If several still fit, the row is warned.
- **Detect Again** (a button, and part of Generate Lines) refreshes entries not picked by hand. This is how a rule change reaches entries posted earlier.

### 4.3 Pay button on journal-entry lines

- **Where:** a Pay button on each row of the entry's Journal Items list. It shows only when all of these hold:
  - the entry is posted, in a general journal, and is not a payment or bank statement entry;
  - the line is Payable, is a **credit** (balance < 0), not reconciled, with an open amount.
- **Which module:** the button lives in `gec_localization`. `geo_payroll` hides it on payslip entries, because only geo_payroll can see payslips (verifier V8). Payslips are paid by Pay Salaries, which also marks the slip Paid.
- **What it pays:** all open lines of the entry with the **same partner and account**, together. Core nets them into one payment. With the xlsx's two-step booking (Cr 310110 100 / Dr 310110 20 / Dr 310110 2), Ana gets **78**, not 100.
- **Refusals:**
  - No partner → "Reset the entry to draft and set a partner on this line." The partner column is read-only on posted entries.
  - A payment method without an Outstanding account is refused, because it would post no entry and leave the line open. Pattern: [geo_payroll account_payment_register.py:15-18](../custom_addons/gec_odoo_modules/geo_payroll/models/account_payment_register.py#L15).
- **Hiding the withholding options:** archive the 23 withholding taxes (phase 0). `display_withholding` is then False on every screen. That is configuration, with no override of the core dialog.
- **Pension Agency account:** the dialog proposes the Agency's first account by sequence (BOG), not the one at the paying bank. The user changes it in the dialog. [Certain]

### 4.4 Rows: one per source, dated on the bank transaction

**Amounts for a misc entry** with a Form 30 Income Type (not salary):

| Item | Rule |
|---|---|
| Person | the Recipient |
| Tax | net credit on F (credits − debits) |
| Gross | net credit on D for the recipient + tax + employee pension. This gives 100 for MISC 0017, 100 for the xlsx's two-step entry, and 1,000 for a CIT-wizard dividend (950 + 50) |
| Employee pension (types 1, 7, 18) | credits on 332010 − employer-share debits on expense accounts other than C [Likely, A4] |
| Rate | the RS-table rate r for which round((gross − pension) × r / 100, 2) is within 0.01 of the tax. None fits: no rate, warning |
| Category, residency | from the contact on the row date, as today |
| Currency | converted to GEL on the row date [Guessing: A8] |

**Dates and months.** One rule for misc entries and salary:

| Item | Rule |
|---|---|
| Main settlement | Misc: whatever settled the recipient's D line, a payment or a bank transaction directly. Salary: the net-pay payment. Pension and Treasury payments are never the main one |
| Row date | the bank transaction date of the main settlement once reconciled; before that, the main payment's date with a **warning**. For salaries this is the **net-pay payment's date, not the slip's Payment Date**: on saas-19.4 the slip's Payment Date can hold the day it was marked paid ([section 10](#10-saas-194-branch-190-compatibility), D1) |
| Month | the declaration takes the sources whose row date falls in its month. Candidates are looked up from one month earlier, so a 30 Sep payment banked on 1 Oct reaches October. This fixes the date/selection mismatch the bug-hunter found for salaries |
| Several bank transactions | the last one; warning if they fall in different months (U2) |
| Already declared | a source already on an **exported** row of another declaration is skipped. No double declaration |
| Declared late | a source whose row date is in an **earlier** month but was never exported is listed as a warning on the next declaration ("belongs to September, never declared: file a correction"). Nothing is lost silently |

**Warnings.** Two kinds, so a normal month is not emptied (U5):

| Kind | Examples | Export |
|---|---|---|
| **Warning** | main payment not reconciled with the bank; two income types possible; rate not in the RS table; more than one recipient; type 1 found on an entry that is not a payslip | left out by default |
| **Note** | tax or pension not paid yet, or its payment not reconciled (tax is due by the 15th of the next month, so it is often unpaid when filing) | exported |

**Other changes:**
- **Rate-table check:** the constraint runs only for hand-made rows. Generated rows carry the problem as a warning, and export still validates them ([:822-844](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L822)).
- **Exemption allowance** is drawn only for rows that are exported ([:638-667](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L638)).
- **Annex E:** entries matching C and D whose recipient is flagged Individual Entrepreneur or Small Business (no F). The month follows the same date rule. The service type comes from a new default on the contact (U4).
- **Safety nets** (warnings on the declaration, not rows):
  - payment withholding lines dated in the month;
  - a bill or invoice carrying a withholding tax, paid in the month;
  - an entry with a credit on an F account and a payable to a non-authority partner that matches no rule.
- **Old source removed:**
  - `_withholding_lines`, `_payment_line_vals`, the annex E builder from withholding lines;
  - `withholding_line_id` on rows and annex E lines;
  - the workbook's payment sheet and the trace for payment rows.

  Rows get `move_id` instead. New warning texts are added to `_localize_warning` ([:54-96](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L54)).

### 4.5 Export with or without warned rows

- New tick box on the declaration: **Export rows with warnings**, off by default.
- One row set ("rows to export") feeds the files, the main-part totals, the form totals and `warning_count`, and the explanation workbook. Annex A and the main part therefore always agree.
- The Export button asks for confirmation. The form shows how many warned rows are left out or included.
- Missing-data errors (ID, category, type, date) block only for rows that are exported.

## 5. Review findings and how the plan answers them

**Bug-hunter (Opus):**

| # | Severity | Finding | Answer in this plan |
|---|---|---|---|
| H1 | blocker | A row left out of one month is lost once the bank date lands in that month, or is declared twice when it was already exported with the tick box | rows keep `move_id`/`payslip_id`; exported sources are skipped; late sources are listed as warnings (4.4) |
| H2 | blocker | Salary: slips selected by `paid_date` but dated on the bank date, so they fall out of every month | one date rule for both; candidates looked up from one month earlier (4.4) |
| H3 | blocker | The rate-table constraint still stops Generate Lines | the constraint applies only to hand-made rows (4.4) |
| H4 | blocker | The xlsx's own D accounts (310990, 120110) and F 331210 can never be paid or bank-matched, so rows stay warned forever | rule warning "D cannot be paid" (4.1); unpaid tax is a note, not a warning (4.4); accountant A7 |
| H5 | blocker, money | Pay on one line of a two-step entry pays the gross (100 instead of 78) | Pay settles all open lines of the same partner and account; credit lines only (4.3) |
| H6 | should-fix | Pay shows on withhold-only payment entries in MISC (prod1 MISC/2026/10/0010) | hidden on payment and statement entries and on debit lines (4.3) |
| H7 | should-fix, money | A payment method without an Outstanding account posts nothing; the line stays open and invites a second payment | refused under the Pay button (4.3) |
| H8 | should-fix, money | Archiving the taxes makes open bills that carry one pay in full (prod1 BILL/2026/10/0007, residual 100, tax 5) | phase 0: settle or clean open documents with a withholding tax first; safety net for such documents (4.4) |
| H9 | should-fix | Gross = debits on C gives 4.25% for a CIT dividend; tax = credits on F double-counts a reclass inside the entry | gross from D + F + pension; tax = net F (4.4) |
| H10 | should-fix | 19/24 never detected when only a unique match is stored | resolved at Generate Lines by the RS table and category (4.2) |
| H11 | should-fix | At install, entries are detected before any rule exists | defaults function runs Detect Again (4.1) |
| H12 | should-fix | A hand-picked type is overwritten on recompute | "picked by hand" flag, sale precedent (4.2) |
| H13 | should-fix | Branch entries never match | rules looked up by `root_id` (4.1) |
| H14 | should-fix | Reversed entries stay on Form 30 | skipped (4.2) |
| H15 | should-fix | Left-out rows still use the exemption allowance | drawn only for exported rows (4.4) |
| H16 | should-fix | A hand-made salary entry is dropped silently | warning (4.4) |
| H17 | note | ±0.05 rate snap fails for small amounts | tolerance on the tax amount (4.4) |
| H18 | note | Payroll's employer pension is on 740900, not 721000 | pension formula uses any expense account other than C (4.4) |
| H19 | note | The tax-change wizard needs an active tax | rate rules stay editable in their own list; wizard use after archiving to be checked in phase 5 |
| H20 | note | October's 7 test withholding payments (35 GEL) drop out with the old source | phase 0 decision (D7 of the old plan) |

**Verifier (Opus), 10 claims:**

| Claim | Result |
|---|---|
| V1 archiving hides withholding everywhere | confirmed |
| V2 a payment from a line uses that line's account | confirmed; 310110 is also the default payable, so 331320 is the real proof |
| V3 bank lines via `reconciled_statement_line_ids` | confirmed (caveat: only for lines on the Outstanding account) |
| V4 bank line of an entry paid directly | confirmed |
| V5 exported declarations can never be rebuilt | **refuted**: Reset to Draft exists. Risk R8 rewritten: the "already exported" check in 4.4 covers it |
| V6 one refused row stops Generate Lines | confirmed |
| V7 archived taxes stay archived on upgrade | confirmed; the premise was wrong (gec_localization does run a maintenance function), and new template taxes would come back active |
| V8 `payslip_ids` only in geo_payroll | confirmed |
| V9 Basis payroll-only / TBC keeps values | **refuted as worded**: Basis type is editable on the form; TBC overwrites a manual Treasury. Phase 1 design adjusted |
| V10 row button in a read-only list | confirmed (stock picking precedent) |

## 6. Phases

Each phase: `odoo-builder` writes it, scouts collect the result, `odoo-reviewer` and `odoo-verifier` for critical phases; you approve and commit.

| Phase | Goal | Modules | Size | Critical |
|---|---|---|---|---|
| 0 | prod1 preparation (you run it): settle or clean open documents that carry a withholding tax (prod1: BILL/2026/10/0007); decide the 7 October test withholding payments; then archive the 23 withholding taxes | prod1 | Small | money |
| 1 | Treasury type and code from the contact. **Basis:** computed, fills only an empty type, so existing payments keep theirs. **TBC:** the treasury branch checked first, so a Treasury code is never overwritten. **BOG:** refuses a hand-made Treasury payment, honest message | basis_bank, tbc_bank, bog_bank | Small | money |
| 2 | Pay button: same-partner-and-account netting, credit lines only, refusals; geo_payroll hides it on payslip entries. geo_payroll also writes the payslip Payment Date **after** `action_payslip_paid`, as Pay Salaries already does (saas-19.4 D1) | gec_localization, geo_payroll | Small | payments |
| 3 | Account rules, defaults from the xlsx, rule warnings | gec_income_tax_report | Medium | new model, security |
| 4 | Income type, "picked by hand" and recipient on the entry; Detect Again | gec_income_tax_report | Small–medium | core model fields |
| 5 | New row builder (misc + salary), date rule, exported/late tracking, warnings and notes, annex E from entries, safety nets, constraint limited to hand-made rows, old source removed, workbook | gec_income_tax_report | Large | declaration |
| 6 | Export with or without warned rows; one row set for files, totals and workbook | gec_income_tax_report | Small | declaration |
| 7 | Docs, READMEs, ka_GE translations, 19.0 (saas~19.4) backport, developer map refresh | all touched | Medium | — |

### 6.1 Built: phases 1 and 2

Built 2026-10-13 in `custom_addons/gec_odoo_modules` (branch 20.0, uncommitted). Build plan reviewed by 2 Opus bug-hunters
before coding, result by 2 Opus reviewers; the one should-fix (R1) was confirmed by the verifier and fixed.

| Phase | What changed | Proof |
|---|---|---|
| 1 | **Basis:** Transfer Type and Treasury Code computed from the contact's Treasury Code (editable, stored; only on a partner change; a given value wins). A Treasury type is dropped when the partner changes to a contact without a code, and the code is cleared. A batch send now refuses a payment with no type (before: only single sends). **TBC:** the contact's code wins over the IBAN logic; a stale Treasury becomes National; code cleared on a partner change. **BOG:** a payment to a Treasury Code contact is refused at Submit for Approval and at every send; the payroll message no longer blames the bank. ka_GE strings added | existing tests 289/289 (basis, tbc, bog, gec_bank, gec_payroll_bank) on `gec20_scenario_bankfix3`; runtime repro 5/5 |
| 2 | **gec_localization:** Pay on each open payable credit line of a posted general-journal entry (not payment or bank entries). It pays the line with the other open lines of the same partner and account, netted. Refusals: no partner; same account with no partner or another contact of the partner; mixed currencies; nothing owed (residual **and** balance must be negative); payment method without an Outstanding account. **geo_payroll:** hidden on payslip entries; payslip Payment Date written after `action_payslip_paid` (saas-19.4 D1). ka_GE strings added | existing tests 360/360 (geo_payroll, gec_payroll_bank) on `gec20_geo_payroll_test`; runtime repro: Cr 100 / Dr 20 / Dr 2 pays **78** and reconciles all three; the Treasury line's payment gets Treasury + 101001000; payslip entry PSLR/2026/01/0001: 4 open credits, no Pay |

**Before `-u` on gec20_prod1:**
- Phase 0 first. Until the 23 withholding taxes are archived, the Pay dialog still offers Withhold and Pay (default Payment Only); choosing it books the tax twice.
- Payments 105 and 107 (Basis, State Treasury, pending) keep an empty type, because an upgrade does not recompute existing rows. Set Treasury + 101001000 by hand, or cancel them in phase 0.
- Basis and TBC journals preselect **Manual Payment**, which has no Outstanding account, so Pay refuses it. Pick the bank-transfer method, or give Manual Payment an Outstanding account. The cash journal has the same gap.
- A Basis batch of only Treasury payments now goes as the op 6 treasury package, which has never been used. Check it against the Basis API before the first live batch.

## 7. Decisions

Answered by the user on 2026-10-13:

| ID | Question | Decision |
|---|---|---|
| U0 | Keep the detected type on the entry, or detect only at Generate Lines | **on the entry** |
| U1 | Before bank reconciliation: a warned row, or no row | **warned row**, left out of the export by default |
| U2 | The person's own line paid in parts (e.g. 50 on 28 Sep + 30 on 3 Oct) | **one row, dated on the last part**; warning when the parts span months. The tax and pension payments never give the date (decision 5) |
| U4 | Annex E service type: default on the contact or on the rule | **on the contact** |
| U5 | Unpaid tax or pension: warning (left out) or note (exported) | **note, exported** |

Still open:

| ID | Question | Recommendation | Who |
|---|---|---|---|
| U3 | More than one recipient in one entry (prod1 MISC/2026/10/0019: Dr 740100 200 / Cr 310110 80 Ana / Cr 331320 40 Treasury / Cr 310110 80 Michael Williams) | **support it**: the type comes from the accounts, so one type for the entry; one row per person; tax and pension split in proportion to each person's net (Ana 20 / 100, Michael 20 / 100); each row dated on that person's own payment; a row whose resulting rate does not fit the person's category is warned. Rows and "already declared" keyed by entry + person. About 30-50 more lines in phase 5 | you |
| A1 | Colliding defaults 16/20 and 22/23: which account changes | — | accountant |
| A2 | Non-residents: is 331212 also an F account | — | accountant |
| A3 | Salary: income tax on 331320 is right (file says 331310)? Does not block | — | accountant |
| A4 | Type 7 with pension 2% + 2%: is the employee 2% deducted before the 20% | — | accountant |
| A5 | Dividends: C = 510310 (file) or 530110 (CIT wizard) | — | accountant |
| A6 | Types 22/23 pay straight from the bank in the entry: declare by entry date, or leave to the portal | — | accountant |
| A7 | D accounts that cannot be paid (310990 for 5, 6, 16, 20; 120110 for 22, 23): switch to a reconcilable Payable account | — | accountant |
| A8 | Foreign-currency entries: GEL rate of the entry date or of the payment date | — | accountant |

## 8. Tests to propose (written only on a yes)

| Phase | Behaviour |
|---|---|
| 1 | Hand-made Basis and TBC payment to the State Treasury gets Treasury and 101001000; TBC keeps it after a bank-account change; BOG refuses |
| 2 | Pay on a two-step entry pays 78; no partner → error; hidden on payslip, payment and statement entries and on debit lines; method without Outstanding account refused |
| 3 | Defaults created once per `ge` company; edited rule survives an upgrade; collision and "D cannot be paid" warnings |
| 4 | MISC-style entry → type 7; hand-picked type survives a rule change; reversed entry skipped; branch uses parent rules |
| 5 | One row per entry with two payments; bank date after reconciliation; 30 Sep → 1 Oct reaches October once; exported source not repeated; late source listed; refused rate warns; dividend gross 1,000 |
| 6 | Warned rows left out by default; totals match the exported rows; tick box includes them |

## 9. Evidence and agents

- prod1 checks (2026-10-13, read-only):
  - MISC/2026/10/0007, 0010, 0013, 0017 and 0018, and SLR/2026/09/0016: lines and partials;
  - payments 83-85 and 105-107, and their bank links;
  - the 24 accounts;
  - statement lines;
  - IE and small-business flags (0), service types on taxes (0), withholding taxes (23 active).
- Code read through agents: core payment dialog, line payment, netting and reconciliation; withholding dialog and payment form; bank statement matching (core, enterprise, gec_bank); chart template reload and gec_localization maintenance; Form 30 declaration, rows, constraint, export, summary, workbook and tests; payroll payment flow; CIT wizard; basis, TBC and BOG transfer types.
- Agents for this redesign (2026-10-13): **9 Haiku scouts**, **1 Opus bug-hunter**, **1 Opus verifier**; for section 10, **6 Haiku scouts**.

## 10. saas-19.4 (branch 19.0) compatibility

Checked 2026-10-13 by file comparison: saas-19.4 core and enterprise in `../../odoo19` against 20.0, and our `gec_odoo_modules` branch 19.0 against 20.0. Nothing was run on 19.4. The 19.4 companion plan is `../../odoo19/documentations/withholding_form30_plans_saas194.md`.

**Verdict.** The plan ports to saas-19.4 as written. The core APIs it uses are the same, the security format is the same (`ir.access.csv`), and our modules on branch 19.0 equal 20.0 apart from version strings and icons. [Certain]

**Odoo 19.0 is a different case.** It is not saas-19.4: its withholding module has only a "Withhold Tax Amounts" checkbox (`should_withhold_tax`), and our branch-19.0 modules cannot be installed on it. [Certain]

### 10.1 The same in saas-19.4

| What the plan uses | saas-19.4 location |
|---|---|
| Withholding choice (Withhold and Pay / Withhold Only / Payment Only), `display_withholding` rule, Withhold Only, withholding line bound to a payment, bank line reduced by the withholding (so I-1 gross amount is identical) | `odoo19/addons/l10n_account_withholding_tax/wizards/account_payment_register.py:14-21, 121-147`, `models/account_payment.py:13-20, 47-64, 113-123`; `odoo19/addons/account/models/account_payment.py:360-402` |
| Paying one line, netting by partner and account, payment on the line's account, reconcile | `odoo19/addons/account/models/account_move_line.py:1683`; `wizard/account_payment_register.py:275-408, 1079, 1151, 1260-1288` |
| Payment states draft / paid / reconciled; no journal entry without an Outstanding account | `odoo19/addons/account/models/account_payment.py:37-50, 482-504, 1111` |
| Bank transaction of a payment or an entry | `account_payment.py:186-191, 718-806`; `account_move.py:211, 218, 234, 5521-5525` |
| Shared accounts with per-company code; tax `active` | `account_account.py:43, 116`; `account_tax.py:140` |
| `payslip_ids` on the entry | `odoo19/enterprise/hr_payroll_account/models/account_move.py:9-15` (file identical) |
| Security `ir.access.csv`, `models.Constraint`, `Domain`, `precompute`, `company_dependent` | `odoo19/odoo/addons/base/models/ir_access.py:66`; `odoo/orm/table_objects.py:88`; `odoo/orm/fields.py:289-294` |
| Row button in an embedded list | `odoo19/addons/stock/views/stock_picking_views.xml:320-321` |
| Our modules | gec_income_tax_report, gec_localization: identical except version + 29 icons; basis_bank, tbc_bank, bog_bank, gec_bank, gec_payroll_bank: identical except version; geo_payroll: differs only in payslip-input code the plan does not touch |

### 10.2 Differences that matter

| # | Difference | Effect | What the plan does |
|---|---|---|---|
| D1 | saas-19.4 `action_payslip_paid` always writes Payment Date = today (`odoo19/enterprise/hr_payroll/models/hr_payslip.py:976-979`); 20 keeps a date set before (`:1115-1118`). geo_payroll sets the date **before** calling it ([hr_payslip_account.py:102-104](../custom_addons/gec_odoo_modules/geo_payroll/models/hr_payslip_account.py#L102)), so on 19.4 the Register Payment path stores today. Pay Salaries sets it after ([hr_payslip.py:413-414](../custom_addons/gec_odoo_modules/gec_payroll_bank/models/hr_payslip.py#L413)), fine on both | salary rows dated by the slip's Payment Date can be wrong on 19.4 (already true today) | rows use the net-pay payment or bank date (4.4); geo_payroll swaps the order on both branches (phase 2) |
| D2 | `_reverse_moves(cancel=True)` unreconciles before copying on 19.4 (`odoo19/addons/account/models/account_move.py:5813-5817`) | none | reversed entries and their reversals are skipped (4.2) |
| D3 | `set_line_bank_statement_line(ids)` has no `allow_partial` on 19.4 (`odoo19/enterprise/account_accountant/models/account_bank_statement.py:1520`) | none: gec_bank passes only the ids | new code must not pass `allow_partial` |
| D4 | 19.4 refuses a withholding line with no number and no sequence (`account_withholding_line.py:365-368`); 20-only `withholding_hide_name` and a post-init hook | none once the withholding taxes are archived | — |
| D5 | 19.4 `account.move.line.name` is the Label; 20 splits `name` and `label` | only if new code reads line labels | new code does not read labels |
| D6 | Manifest versions `saas~19.4.x`; Font Awesome icons on 19.4, Material on 20 | the Pay button icon, any new grid icon | recorded as `v20_only` rows in `docs/ports/<module>_20.0_to_saas-19.4.md` |

### 10.3 19.x databases (PostgreSQL 14, port 5432, read-only)

| Database | Core | State |
|---|---|---|
| `gec_prod1` | **Odoo 19.0** (base 19.0.1.3) | Old modules: gec_l10n_ge_tax (15 withholding taxes, field `is_withholding_tax_on_payment`), gec_localization, gec_income_tax_report and geo_payroll are installed. Withholding is a checkbox only. Branch-19.0 modules cannot be installed (version `saas~19.4` refused). Needs an Odoo upgrade before this plan applies; gec_l10n_ge_tax is deleted in 20.0 and must not be installed with the port |
| `gecrestore1` | saas~19.4 | Withholding Tax installed (the 2026-10-13 test); no gec modules |
| `gec_modules_19_4` | saas~19.4 | gec modules present, not installed |

**Port procedure, per phase:**
1. The 20.0 phase is committed first.
2. The same files are copied to branch 19.0, changing only `v20_only` rows (version, icons).
3. The per-file delta is proved with `docs/backport_tools`, and the port doc is updated.
4. The module tests run on a saas-19.4 test database. They have never run there for gec_income_tax_report.

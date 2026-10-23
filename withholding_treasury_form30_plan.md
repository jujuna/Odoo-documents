# Withholding, Treasury Payments and Form 30: Analysis and Plan (2026-10-12)

> **Status:** analysis and plan, nothing built. Checked on 2026-10-12 against the Odoo 20 source in this repo and the
> working database `gec20_prod1` (PostgreSQL 16, port 5433) with read-only `SELECT`s.
> **Tags:** **[Certain]** read in code or the database; **[Likely]** inferred from code that was read, not run;
> **[Unverified]** not checked. Line links point at the 20.0 tree as of this date.
> **Scope agreed with the user:** withholding is used **only for salaries and for miscellaneous journal entries**, never
> on vendor bills or customer invoices.
> **Superseded in part (2026-10-13):** the user and the accountant moved withholding into the journal entry. The current
> plan is **plan B** in [form30_entry_redesign_plan.md](form30_entry_redesign_plan.md): the entry's tax line names a
> withholding tax, which gives Form 30 its income type and rate; the 23 taxes get Tax Type None. Rule B, I-2, phases 2
> and 5, and the payment-withholding-line source are replaced there. What happened to this plan's items:
> - **5a / I-18** (Treasury type and code from the contact): **built**, commit `f7d3ad1` (Basis, TBC; BOG refuses).
> - **I-17** (BOG cannot pay the Treasury): BOG now refuses such payments with an honest message (`f7d3ad1`); building the
>   BOG treasury document is still open.
> - **I-1** (Withhold and Pay sends the gross): plan B step 0b refuses any bank send of a payment with withholding lines
>   (planned, not built). prod1 has one such payment (86, Manual Payment, no bank exposure).
> - **5.13** (Treasury and Pension by bank): still valid.
> - Handoff of the 2026-10-13 session: [form30_handoff_20261013.md](form30_handoff_20261013.md).
> **saas-19.4 (branch 19.0), checked 2026-10-13:** same core withholding module and same bank-module code. Section 5.13
> (Treasury and Pension by bank) and I-1 (gross amount on Withhold and Pay) hold unchanged. Odoo **19.0** (`gec_prod1`)
> differs: its payment has only a "Withhold Tax Amounts" checkbox. Details: [form30_entry_redesign_plan.md section 10](form30_entry_redesign_plan.md#10-saas-194-branch-190-compatibility).
> **Updated 2026-10-13:** Form 30 rewritten by income type ([section 6](#6-form-30-rows-by-income-type)); bill items
> moved out of the Form 30 story ([7.6](#76-not-form-30-bill-side-effects)); how Basis, TBC and BOG pay the Treasury and
> the Pension Agency ([5.13](#513-paying-the-treasury-and-the-pension-agency-by-bank)).

---

## Table of Contents

- [1. Summary](#1-summary)
- [2. Questions answered today](#2-questions-answered-today)
- [3. Plain-language concepts](#3-plain-language-concepts)
- [4. Working rules until the plan is built](#4-working-rules-until-the-plan-is-built)
- [5. Findings by topic](#5-findings-by-topic)
- [6. Form 30: rows by income type](#6-form-30-rows-by-income-type)
- [7. Issues list](#7-issues-list)
- [8. Plan](#8-plan)
- [9. Decisions needed](#9-decisions-needed)
- [10. Changes made today](#10-changes-made-today)
- [11. Evidence index](#11-evidence-index)

---

## 1. Summary

| Topic | Result |
|---|---|
| Where a withholding tax is assigned | **Only at payment** (Pay window, Withholdings tab). Never on a bill, invoice, journal-entry line, product or contact default. Salaries never use an Odoo tax: the payslip computes income tax and pension. This matches the accountant, Odoo's own draft Georgian module and Argentina. [Certain] |
| Why the withholding tax records exist | They are the "rule card" picked at payment: rate, account (331210 resident / 331212 non-resident), Form 30 income type, certificate numbering. Without them Form 30 gets no line. [Certain] |
| Biggest money risk | **Withhold and Pay** through Basis, TBC or BOG sends the **gross** amount (100 instead of 80). Odoo's own SEPA/ISO 20022 files do the same. Nothing on `gec20_prod1` was sent this way yet. [Certain] |
| Correction to advice given earlier today | **Withhold Only** on a journal-entry line that carries no withholding tax most likely produces an amount of **0**: the dialog takes the Withhold Only amount from the document's declared withholding, and a journal entry declares none. Argentina overrides exactly this. Must be tested before anyone uses it. [Likely, not run] |
| What works today for a misc entry, in accounting terms | Journal entry for the full amount, then Pay with **Withhold and Pay** and a hand-added withholding line: Payable 100 / Bank 80 / 331210 20, certificate, Form 30 line. **But only with a non-API payment method** until the bank modules send the net. [Likely, core test covers the invoice case] |
| Paying the State Treasury | No module anywhere (core, other countries, ours, Odoo's Georgian PR) creates the government payment. Payroll is the only exception: Pay Salaries already pays income tax to the Treasury. For misc withholding it is a manual step today. [Certain] |
| Form 30 | **Never reads a bill or a journal entry.** Income type 1 (salary) comes from paid payslips, always at rate 20. Every other income type comes from the withholding tax picked at payment: the tax carries the income type ([rs.form30.income.type](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_classifier.py#L56)). No tax carries types 6, 16 or 20-24 today. That is configuration, not code: the accountant can set the type on a tax. 5 of the 23 taxes have no type. Hand-made rows (other salary rates, income without a withholding line) have no UI. See [section 6](#6-form-30-rows-by-income-type). [Certain] |
| Treasury and Pension by bank | Pension is a normal transfer to the Pension Agency's account in the paying bank (Basis, TBC, BOG). The Treasury is paid by code: Basis and TBC can do it, and Pay Salaries fills the code; on a hand-made payment you set it yourself. **BOG cannot, because our module never built it**, not because BOG refuses: our BOG API notes describe the treasury document. See [5.13](#513-paying-the-treasury-and-the-pension-agency-by-bank). [Certain] |
| Docs | Our docs tell users to put withholding taxes on the bill, product or contact default. That contradicts the scope; it does not affect Form 30 ([7.6](#76-not-form-30-bill-side-effects)). [Certain] |

---

## 2. Questions answered today

| # | Question | Short answer | Section |
|---|---|---|---|
| 1 | Why does bank reconciliation show PBNK5 but not the MISC withholding entry of BILL/2026/10/0008? | The MISC entry moved no money: its lines are already reconciled or sit on accounts that do not allow reconciliation | [5.1](#51-bank-reconciliation-matching) |
| 2 | What to set in **Withholding Tax Base**? | A dedicated technical account; the user created 331213 | [5.3](#53-withholding-tax-base-setting) |
| 3 | Check the payment of BILL/2026/10/0009 | Correct; base pair now on 331213 | [5.3](#53-withholding-tax-base-setting) |
| 4 | How was MISC/2026/10/0012 reconciled automatically? | Register Payment reconciles every payment with the bill; a withhold record has no bank part, so it shows "Reconciled" at once | [5.2](#52-withholding-mechanics-in-core) |
| 5 | Settings page crash `recruitment_lawyer_id` | Installed modules missing from the addons path; `odoo.conf` fixed, restart pending | [5.12](#512-environment-settings-crash) |
| 6 | How to pay 5 GEL to the government? | A separate treasury transfer; booked to 331212 | [5.4](#54-paying-the-state-treasury) |
| 7 | Why does MISC/2026/10/0006 appear in reconciliation? | One open line on 160610, an account core `l10n_ge` makes reconcilable | [5.1](#51-bank-reconciliation-matching) |
| 8 | Why a separate withhold "payment" if it never reaches the bank? Other countries? Two payments from a journal entry? | It closes the bill part and books the debt to the government; no country creates the government payment; journal lines are paid from Amounts to Settle | [5.2](#52-withholding-mechanics-in-core), [5.5](#55-paying-journal-entries), [5.9](#59-where-withholding-is-assigned) |
| 9 | When are payments needed; bank import only; reconciliation with and without payments | Payments are needed to send money from Odoo and for withholding | [5.6](#56-payments-versus-bank-only-reconciliation) |
| 10 | Do we send 2 bank transfers from 1 payment? | No: 1 payment = 1 transfer; batches choose the Basis endpoint | [5.7](#57-bank-modules-basis-tbc-bog) |
| 11 | Why can't I see misc entries in Aged Payable? | It shows only open lines, and only trade payables by default | [5.5](#55-paying-journal-entries) |
| 12 | Accounts and partners for the new entries; should they have taxes? | No taxes on either entry; partners only on Payable lines | [4](#4-working-rules-until-the-plan-is-built) |
| 13 | When do we use taxes at all? What about salaries? | VAT on invoices and bills; withholding at payment; salaries in the payslip | [5.8](#58-salaries), [5.9](#59-where-withholding-is-assigned) |
| 14 | Where should withholding taxes be assigned? (via /odoo-team, with Odoo's Georgian PR) | At payment only | [5.9](#59-where-withholding-is-assigned) |
| 15 | (2026-10-13) Form 30 is not built from bills; where do its rows come from? | Correct: no bill is read. Salary rows from payslips, all other income types from the withholding tax picked at payment | [6](#6-form-30-rows-by-income-type) |
| 16 | (2026-10-13) How do Basis, TBC and BOG pay the Treasury and the Pension Agency? Why can't BOG pay the Treasury? | See the section | [5.13](#513-paying-the-treasury-and-the-pension-agency-by-bank) |

---

## 3. Plain-language concepts

| Term | Meaning |
|---|---|
| Payment (Odoo) | A record that says "we send / receive money". One payment = **one** bank transfer. [Certain] |
| Withhold Only | Records the withholding only: the person is owed less, the government is owed more. **No money moves.** It lands in the Miscellaneous journal. [Certain] |
| Payment Only | A normal payment, no withholding. |
| Withhold and Pay | One payment that does both: bank pays the net, the tax goes to 331210/331212. Its **Amount field stays the gross**. [Certain] |
| Outstanding Payments (120410) | "Sent, but the bank statement has not confirmed it yet." The bank line is later matched to it. |
| Reconciled (payment status) | Its bank part has nothing left to match. A withhold record has no bank part, so it is Reconciled at once. It does **not** mean the government was paid. [Certain] |
| In Payment (bill status) | Paid by a payment, but the bank has not confirmed it yet. |
| Trade / Non Trade payable | Aged Payable shows only trade payables until **Non Trade Payable** is ticked. 331320 is non-trade. [Certain] |
| A tax in Odoo | An instruction: compute this amount, book it on the tax account, send it to the declaration. Put it on exactly one document. |

---

## 4. Working rules until the plan is built

**Salaries** (works today): payslip → Pay Salaries → employee, Pension Agency and State Treasury payments, sent in batches. Form 30 reads the paid payslip. No Odoo tax. [Certain]

**Misc journal entry for a person** (example: Ana, 100 GEL, 20% withholding):

| Step | Entry / action | Accounts and partner | Status |
|---|---|---|---|
| 1 | Journal entry, no taxes | Dr **740100** Professional & Compliance Services (or 741100 Rent) 100 / Cr **310110** Payable, partner **Ana**, 100 | [Certain] |
| 2 | Ana's line → Pay → **Withhold and Pay**, payment method **Manual Payment** (not Basis), Withholdings tab → Add a line: tax "WHT 20% - Resident Individual Services (unregistered)", base 100 | Payable 100 / Outstanding 80 / 331210 20; certificate; Form 30 line | [Likely]; test once on a scratch DB |
| 3 | Send the 80 from Internet Banking; match the bank line to the payment | — | [Certain] |
| 4 | Entry 2, no taxes | Dr **331210** 20 / Cr **331320** 20, partner **სახელმწიფო ხაზინა** | [Certain] |
| 5 | Aged Payable (tick Non Trade Payable) → Treasury → Pay → BASIS GEL; on the payment: Transfer Type **Treasury**, Treasury Code **101001000** | — | [Certain] |

**Never** (until fixed):
- **Withhold and Pay** with a Basis, TBC or BOG payment method: sends 100 instead of 80. [Certain]
- **Withhold Only** on a journal-entry line: likely amount 0. [Likely]
- A withholding tax on a bill, journal-entry line, product, or as a contact's **Default Purchase Tax** (the last one replaces VAT). [Certain]
- **Send to Basis** on `gec20_prod1` for tests: the connection is live. [Certain]
- A Treasury payment through **BOG**: Odoo lets a hand-made one go out with no account, and BOG refuses it ([5.13](#513-paying-the-treasury-and-the-pension-agency-by-bank)). [Certain]
- A Treasury payment on Basis or TBC without **Transfer Type Treasury** and **Treasury Code 101001000** set on it (PBNK5/2026/00022 has neither). [Certain]

Where to pay a journal-entry line: Accounting → Reporting → **Aged Payable** → click the partner's amount → "Amounts to Settle" list → tick → **Pay**. The journal entry form has no Pay button. [Certain]

---

## 5. Findings by topic

### 5.1 Bank reconciliation matching

- The "Journal Items to Match" search shows only posted, unreconciled lines on accounts that **allow reconciliation**, and excludes payable/receivable lines that belong to payments ([account_bank_statement_line.py:515](../addons/account/models/account_bank_statement_line.py#L515)). [Certain]
- BILL/2026/10/0008: every line of its withhold entry MISC/2026/10/0011 fails that rule (payable already reconciled; 331212 and the base lines not reconcilable). Only PBNK5/2026/00020's Outstanding line (−95) qualifies. [Certain]
- MISC/2026/10/0006 (a VAT test entry created by a script on 2026-10-09, ref "VAT TEST ... Own building repair") shows because its −1,000 line sits on **160610 Cost of Production**, which core `l10n_ge` ships as reconcilable ([account.account-ge.csv:41](../addons/l10n_ge/data/template/account.account-ge.csv#L41)); it is the MRP overhead account ([template_ge.py:37](../addons/l10n_ge/models/template_ge.py#L37)). Any open line there appears in every bank search. [Certain]
- The test bank line "tetetet" (−95, 2026-10-09) is on **BNK1 Bank** (120110), while the payment went through **BNK5 BASIS GEL** (120003, statements from Basis). Odoo allows the match through the shared 120410, but it would book the cash on the wrong bank. [Certain]

### 5.2 Withholding mechanics in core

| Fact | Evidence |
|---|---|
| A withholding tax never changes a document total; it is applied only at payment | [account_tax.py:13-16](../addons/l10n_account_withholding_tax/models/account_tax.py#L13), [:80-81](../addons/l10n_account_withholding_tax/models/account_tax.py#L80) |
| Modes: Withhold and Pay / Withhold Only / Payment Only | [wizards/account_payment_register.py:13-18](../addons/l10n_account_withholding_tax/wizards/account_payment_register.py#L13) |
| Default mode: Payment Only unless the document declares withholding | [:72-79](../addons/l10n_account_withholding_tax/wizards/account_payment_register.py#L72) |
| Withholdings tab needs a purchase withholding tax and a single editable payment; the list is editable (Add a line) | [:127-152](../addons/l10n_account_withholding_tax/wizards/account_payment_register.py#L127), [views:10, 19-22](../addons/l10n_account_withholding_tax/wizards/account_payment_register_views.xml#L19) |
| **Withhold Only amount = the document's declared withholding residual**; Withhold and Pay amount = the full residual | [:192-211](../addons/l10n_account_withholding_tax/wizards/account_payment_register.py#L192) |
| Withhold Only proration factor = amount / declared withholding, 0 when nothing is declared | [account_payment_withholding_line.py:62-82](../addons/l10n_account_withholding_tax/models/account_payment_withholding_line.py#L62), [wizards/account_payment_register_withholding_line.py:40-77](../addons/l10n_account_withholding_tax/wizards/account_payment_register_withholding_line.py#L40) |
| Withhold Only is posted on the first general journal and has no bank line | [:231-240](../addons/l10n_account_withholding_tax/wizards/account_payment_register.py#L231), [account_payment.py:153-154](../addons/l10n_account_withholding_tax/models/account_payment.py#L153) |
| The bank line of Withhold and Pay is reduced by the withheld amount in core; the payment Amount stays gross | [account/models/account_payment.py:405-406](../addons/account/models/account_payment.py#L405); prod1 PBNK1/2026/00023: Amount 100, Outstanding 95 |
| Withholding lines carry the payment's partner, not an authority | [account_withholding_line.py:387](../addons/l10n_account_withholding_tax/models/account_withholding_line.py#L387) |
| Register Payment reconciles every created payment with the paid lines | [account/wizard/account_payment_register.py:1264-1293](../addons/account/wizard/account_payment_register.py#L1264) |
| Payment status Reconciled when the bank part has no residual | [account/models/account_payment.py:496-518](../addons/account/models/account_payment.py#L496) |
| Our withholding taxes carry no tax tags, so nothing reaches Odoo tax reports | prod1 lines of MISC/2026/10/0012 (no tags) |
| On the payment form, Withhold Only is hidden unless the payment is linked to a bill | [withhold_selector.js:8-16](../addons/l10n_account_withholding_tax/static/src/components/withhold_selector/withhold_selector.js#L8) |
| Argentina overrides the Withhold Only amount to "fill it from the lines" because it never declares withholding on documents | [l10n_ar_withholding/wizards/account_payment_register.py:24-27](../addons/l10n_ar_withholding/wizards/account_payment_register.py#L24) |

### 5.3 Withholding Tax Base setting

- The field `withholding_tax_base_account_id` decides where the +base / −base pair of each withholding goes; empty means the expense account of the paid line ([account_withholding_line.py:482](../addons/l10n_account_withholding_tax/models/account_withholding_line.py#L482)). [Certain]
- Core precedents: Argentina "Tax Base Account" and India "TDS (Withholding Control)" are dedicated technical accounts; Chile, Colombia and Peru reuse the withholding liability. [Certain]
- An off-balance account would make every withholding payment fail: off-balance and normal accounts cannot share an entry ([account_move_line.py:1849-1854](../addons/account/models/account_move_line.py#L1849)). [Certain]
- Done by the user: account **331213** (Current Liabilities, not reconcilable) set as the base account; BILL/2026/10/0009's withhold entry put the pair on 331213. Its English name is "Withholding Tax (WHT)" and it has no Georgian name. [Certain]

### 5.4 Paying the State Treasury

- No flow in core, in any country module, in Odoo's Georgian PR or in our modules clears 331210/331212 or pays withholding to the Treasury. India records the deposit in a separate "TDS challan" (payroll), Chile and Ecuador collect it in a monthly tax return. [Certain]
- Payroll is our only Treasury flow: income tax posts on **331320** (Payable, reconcilable, non-trade) with partner State Treasury, and Pay Salaries pays it ([payroll_payment_flow.md](payroll_payment_flow.md)). [Certain]
- A payment's counterpart must be a Payable or Receivable account ([account_payment.py:169](../addons/account/models/account_payment.py#L169), [:247](../addons/account/models/account_payment.py#L247)), so 331210/331212 cannot be paid directly; the debt must first move to a Payable line of the Treasury. [Certain]
- Alternative without a payment: bank reconciliation **Set Account** puts the bank line on any account ([account_bank_statement.py:1308](../enterprise/account_accountant/models/account_bank_statement.py#L1308)). After two lines on the same account Odoo creates a matching rule from the common label text ([:1431](../enterprise/account_accountant/models/account_bank_statement.py#L1431)); all Georgian taxes go to the same treasury code, so check the proposal on every treasury line. [Certain]
- Basis can send a hand-made treasury payment: Transfer Type Treasury and Treasury Code typed on the payment ([basis_bank account_payment.py:277](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L277), [views:55-57](../custom_addons/gec_odoo_modules/basis_bank/views/account_payment_views.xml#L55)). Only payroll fills them automatically ([account_payment_method_line.py:71-74](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment_method_line.py#L71), called only from [hr_payslip.py:380](../custom_addons/gec_odoo_modules/gec_payroll_bank/models/hr_payslip.py#L380)). TBC never sets treasury outside payroll; BOG has no treasury transfer in our module (why: [5.13](#513-paying-the-treasury-and-the-pension-agency-by-bank)). [Certain]
- Deadline: declaration and payment by the 15th of the next month ([rs_form30_full_declaration_gap_plan.md](rs_form30_full_declaration_gap_plan.md), deadline row). The user's company pays the tax on the same day as the person. [Certain for the doc]
- `gec20_prod1`: 331212 holds **35 GEL** from 7 TEST withholdings; nothing was ever paid against it. [Certain]

### 5.5 Paying journal entries

- The journal entry form has no Pay button; core refuses "You cannot register payments for miscellaneous entries" ([account_move.py:6733-6735](../addons/account/models/account_move.py#L6733)). [Certain]
- Journal **lines** are paid from the "Amounts to Settle" list, which has a **Pay** button ([account_move_views.xml:400-407](../addons/account/views/account_move_views.xml#L400), [:2233-2239](../addons/account/views/account_move_views.xml#L2233)) and is opened by clicking an amount in **Aged Payable** ([account_aged_partner_balance.py:325-345](../enterprise/account_reports/models/account_aged_partner_balance.py#L325)). The dialog checks account type, residual, company, branch and direction, but not the move type ([account_payment_register.py:1003-1056](../addons/account/wizard/account_payment_register.py#L1003)). [Certain]
- Two lines of two partners make two payments (one per partner and account) in one click ([account_payment_register.py:286-292](../addons/account/wizard/account_payment_register.py#L286), [:456-475](../addons/account/wizard/account_payment_register.py#L456)). Register Payment creates no batch; batches come from the payment list action **Create batch payment** ([account_batch_payment_views.xml:4-13](../enterprise/account_batch_payment/views/account_batch_payment_views.xml#L4)). [Certain]
- Aged Payable shows only open lines and, by default, only trade payables; **Non Trade Payable** must be ticked in the Account filter ([account_report.py:1364-1365](../enterprise/account_reports/models/account_report.py#L1364)). That is why MISC/2026/10/0013's Treasury line (331320, non-trade) was not visible. [Certain]

### 5.6 Payments versus bank-only reconciliation

| Fact | Evidence |
|---|---|
| Payment states in 20: draft, paid, reconciled, canceled, rejected | [account_payment.py:37-50](../addons/account/models/account_payment.py#L37) |
| With an outstanding account, a payment posts Payable / Outstanding; the bank line later matches the Outstanding line | [:1146](../addons/account/models/account_payment.py#L1146) |
| With Accounting installed and no outstanding account, a payment creates **no** journal entry; the bank line then closes the bill directly | [:984-991](../addons/account/models/account_payment.py#L984), [:1146](../addons/account/models/account_payment.py#L1146), [account_bank_statement.py:2219-2232](../enterprise/account_accountant/models/account_bank_statement.py#L2219) |
| "In Payment" comes from the accountant module's hook; a bill matched only to a bank line becomes Paid | [enterprise/accountant/models/account_move.py:7-9](../enterprise/accountant/models/account_move.py#L7), [account_move.py:1326-1357](../addons/account/models/account_move.py#L1326) |
| Default reconciliation models: Internal Transfers, Bank Fees; no shipped matching rules | [chart_template.py:1207-1231](../addons/account/models/chart_template.py#L1207) |
| Batch payments group several payments into one bank line | [account_batch_payment/__manifest__.py:5-13](../enterprise/account_batch_payment/__manifest__.py#L5) |
| Our bank modules require an Outstanding Payments account that allows reconciliation | [gec_bank account_payment_method_line.py:155-171](../custom_addons/gec_odoo_modules/gec_bank/models/account_payment_method_line.py#L155) |

Bank import only (no payments): one step, bank is the truth; but nothing can be sent from Odoo, bills stay Not Paid until matched, and **no withholding lines exist, so Form 30 gets nothing**. Payments are required for API sending, withholding, Pay Salaries and batches. [Certain]

### 5.7 Bank modules (Basis, TBC, BOG)

- **One payment = one transfer.** The batch decides the Basis endpoint: salary package, GEL package, treasury package, or "Single Transfers Batch" (op 7) for mixed types, sent with **one OTP** ([account_batch_payment.py:81-92](../custom_addons/gec_odoo_modules/basis_bank/models/account_batch_payment.py#L81), [:252-266](../custom_addons/gec_odoo_modules/basis_bank/models/account_batch_payment.py#L252), [basisbank_service.py:161-170](../custom_addons/gec_odoo_modules/basis_bank/services/basisbank_service.py#L161)). Example on prod1: BATCH/OUT/2026/0022 salary package (1 employee), BATCH/OUT/2026/0021 single batch (Pension Agency + State Treasury). [Certain]
- **Gross amount sent.** All three adapters send `payment.amount`: [basis_bank:215](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L215), [:220](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L220), [:238](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L238); [tbc_bank:443](../custom_addons/gec_odoo_modules/tbc_bank/models/account_payment.py#L443); [bog_bank:537](../custom_addons/gec_odoo_modules/bog_bank/models/account_payment.py#L537). With Withhold and Pay that is the gross. No guard exists in basis_bank, gec_bank, tbc_bank, bog_bank or gec_payroll_bank. Odoo's own ISO 20022 export also uses `payment.amount` ([account_iso20022 account_batch_payment.py:164](../enterprise/account_iso20022/models/account_batch_payment.py#L164)). Verifier: confirmed. [Certain]
- **Exposure on prod1:** the only Withhold and Pay payment (PBNK1/2026/00023) used Manual Payment. Test payments PBNK5/2026/00020 and 00021 (TEST Ana, 95 each) are **Pending**, never sent. The Basis connection is live (direct mode, bis.bankonline.ge). [Certain]
- **Matching:** Basis matches statement lines to sent payments by the bank's internal ID or DocNum ([account_bank_statement_line.py:21-31](../custom_addons/gec_odoo_modules/basis_bank/models/account_bank_statement_line.py#L21)). The shared gec_bank matcher compares `payment.amount` ([gec_bank account_bank_statement_line.py:82](../custom_addons/gec_odoo_modules/gec_bank/models/account_bank_statement_line.py#L82)), so a Withhold and Pay payment would likely never auto-match its net bank line. [Likely; noted by the verifier, not traced]
- India's module defaults to **Withhold Only** instead of Withhold and Pay for single payments ([l10n_in/wizard/account_payment_register.py:19-23](../addons/l10n_in/wizard/account_payment_register.py#L19)). [Certain]

### 5.8 Salaries

- Example SLR/2026/09/0016 (TEST Ana, gross 1,400): 720100 Dr 1,400; 332010 Cr 28 (Pension Agency); 740900 Dr 28 / 332010 Cr 28 (employer pension); **331320 Cr 274.40 (State Treasury)**; 310310 Cr 1,097.60 (Ana). The State Treasury payment PBNK6/2026/00002 (274.40, TBC) exists. [Certain]
- Pay Salaries creates one payment per receiver, puts authorities first, marks payslips Paid, seals batches, and sets the treasury transfer type automatically ([payroll_payment_flow.md](payroll_payment_flow.md); [hr_payslip.py:293-389](../custom_addons/gec_odoo_modules/gec_payroll_bank/models/hr_payslip.py#L293)). [Certain]
- No Odoo tax is involved; India works the same way (salary rule `TDS`, [hr_salary_rule_regular_pay_data.xml:362-373](../enterprise/l10n_in_hr_payroll/data/salary_rules/hr_salary_rule_regular_pay_data.xml#L362)). [Certain]

### 5.9 Where withholding is assigned

**Core:** three places: bill line (pre-fills the Pay window, total unchanged), added by hand at payment ([test_account_withholding_flows.py:40](../addons/l10n_account_withholding_tax/tests/test_account_withholding_flows.py#L40)), or on a payment created directly. A journal-entry line never computes withholding ([account_move.py:44](../addons/l10n_account_withholding_tax/models/account_move.py#L44)). [Certain]

**Other countries:**

| Pattern | Countries | Evidence |
|---|---|---|
| Chosen at payment, never on the document | Argentina (partner's registered regimes are proposed at payment) | [wizards/account_payment_register.py:150-183](../addons/l10n_ar_withholding/wizards/account_payment_register.py#L150), [res_partner.py:16-39](../addons/l10n_ar_withholding/models/res_partner.py#L16) |
| On the bill line, taken at payment | India, Philippines, Saudi Arabia (deducted), Peru (enterprise) | [account_demo.py:615](../addons/l10n_in/demo/account_demo.py#L615), [l10n_ph __manifest__.py:13](../addons/l10n_ph/__manifest__.py#L13), [account.tax-sa.csv:140](../addons/l10n_sa/data/template/account.tax-sa.csv#L140), [l10n_pe_edi_withholding __manifest__.py:7](../enterprise/l10n_pe_edi_withholding/__manifest__.py#L7) |
| Negative tax on the bill that lowers the total at once | Colombia, Mexico, Chile | [account.tax-co.csv:26](../addons/l10n_co/data/template/account.tax-co.csv#L26), [account.tax-mx.csv:2](../addons/l10n_mx/data/template/account.tax-mx.csv#L2), [account.tax-cl.csv:10](../addons/l10n_cl/data/template/account.tax-cl.csv#L10) |
| Separate withholding document from the posted bill | Ecuador ("Add Withhold") | [l10n_ec_edi account_move.py:392-399](../enterprise/l10n_ec_edi/models/account_move.py#L392) |
| None | Brazil | — |

**Odoo's own Georgian module** ([odoo/odoo#292088](https://github.com/odoo/odoo/pull/292088), "[ADD] l10n_ge_withholding: Georgian withholding tax on payments", draft, base 20.0, head `1ba12307390d`, last update 2026-10-06, not merged): [Certain, from the PR patches]
- Depends on `l10n_ge` and `l10n_account_withholding_tax`, auto-installs with `l10n_ge`.
- 56 purchase taxes: **12 "deducted"** (withholding flag, active, percent, negative) and **44 "gross-up"** (company pays the tax on top: division, cash basis, inactive). Accounts 331210 (tag-carrying), 331211 (gross expense), 331212 (cash-basis transition).
- In its tests the **deducted tax is added at payment** on bills that carry no tax; only the gross-up tax is put on the bill line.
- New contact field **Withholding Tax Categories** (the 18 RS.ge categories, same as our `rs.form30.category`) filters which taxes are offered on that contact's bills and payments.
- A **Withholding Tax Return** report by income type (1w-12w), gross and deducted, from tax tags; no tax closing, and nothing about the Treasury or code 101001000.
- A treaty-exempt amount on withholding lines.
- Earlier comparison with ours (2026-10-07): the 18 categories match ours; all 56 tax/category/rate combinations are valid in our rate matrix.

### 5.10 Our Georgian setup

| Fact | Evidence |
|---|---|
| 23 withholding taxes, all active, purchase, flag set, `on_invoice`; resident → 331210, non-resident → 331212 | [account.tax-ge.csv:32-120](../custom_addons/gec_odoo_modules/gec_localization/data/template/account.tax-ge.csv#L32); prod1 SELECT |
| No fiscal position maps to them; no product carries them; **7 posted vendor bills** carry one (test bills) | prod1 SELECTs |
| A contact's **Default Purchase Tax** accepts withholding taxes and then **replaces the VAT** of the line (the sales field excludes them) | [res_partner.py:21](../custom_addons/gec_odoo_modules/gec_localization/models/res_partner.py#L21), [:27](../custom_addons/gec_odoo_modules/gec_localization/models/res_partner.py#L27), [account_tax.py:16](../custom_addons/gec_odoo_modules/gec_localization/models/account_tax.py#L16) |
| **Docs contradict the rule:** "Put the WHT tax on the bill line (or among the product's purchase taxes)", "the bill carries the WHT tax; the payment withholds it", README step 1 posts the bill with the tax from the product, the contact default or by hand | [l10n_ge.md:34](l10n_ge.md), [l10n_ge.md:237](l10n_ge.md), [gec_localization README.md:225-226](../custom_addons/gec_odoo_modules/gec_localization/README.md), [:281-282](../custom_addons/gec_odoo_modules/gec_localization/README.md) |
| CIT wizard books dividend withholding as plain journal lines, not a tax | [cit_wizard.py:40-41](../custom_addons/gec_odoo_modules/gec_localization/wizards/cit_wizard.py#L40), [:92-98](../custom_addons/gec_odoo_modules/gec_localization/wizards/cit_wizard.py#L92) |
| Treasury Code field and the State Treasury contact (101001000) | [res_partner.py:30-34](../custom_addons/gec_odoo_modules/gec_localization/models/res_partner.py#L30), [geo_payroll res_partner_data.xml:12-16](../custom_addons/gec_odoo_modules/geo_payroll/data/res_partner_data.xml#L12) |
| Tax choice in the tests is doubtful: "WHT 5% - Non-resident Royalties" on a Utilities bill to TEST Ana; "Non-resident Interest" for TEST Maka; both contacts have no Tax ID, no country, no Form 30 category | prod1 SELECTs |

### 5.11 Odoo bank files and withholding

Odoo's own ISO 20022 / SEPA export has no withholding handling and sends `payment.amount` (grep of `withhold` in account_sepa, account_batch_payment, account_iso20022: no hits). The gross-amount issue is therefore not only ours; core avoids it in India by defaulting to Withhold Only. [Certain]

### 5.12 Environment: Settings crash

- "res.config.settings.recruitment_lawyer_id field is undefined": `hr_customization` (in `custom_addons/alta_hr_customization`) is installed on prod1, but the running server's `addons_path` did not include that folder, so its views loaded without its Python fields. `booking_engine` and `base_industry_data` (in `custom_addons/extra_modules`) were in the same state. [Certain]
- Fixed in `odoo.conf` (both folders added). **The server must be restarted** for it to take effect; not done (the server process was not started from a terminal of this session). [Certain]

### 5.13 Paying the Treasury and the Pension Agency by bank

Checked 2026-10-13; an Opus verifier confirmed all 10 claims and corrected line numbers.

Both authority contacts come from `geo_payroll` data ([res_partner_data.xml:4-17](../custom_addons/gec_odoo_modules/geo_payroll/data/res_partner_data.xml#L4)):
- **სახელმწიფო ხაზინა** (id 73): Treasury Code 101001000, no bank account.
- **საპენსიო სააგენტო** (id 72): no Treasury Code, 10 bank accounts, one per Georgian bank ([res_partner_bank_data.xml](../custom_addons/gec_odoo_modules/geo_payroll/data/res_partner_bank_data.xml)).

The contact's **Treasury Code** is what makes a payment a treasury transfer. [Certain]

| | Basis | TBC | BOG |
|---|---|---|---|
| **State Treasury**: what is sent | Transfer Type **Treasury** + Treasury Code. Single payment or mixed batch: group `TreasuryTransfers` in op 7 ([account_payment.py:277-283](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L277)). Batch of only treasury payments, GEL, one sender: op 6 treasury package ([:213-217](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L213), [account_batch_payment.py:84-92](../custom_addons/gec_odoo_modules/basis_bank/models/account_batch_payment.py#L84)) | Transfer Type **Treasury** → `TreasuryTransfer` with a 9-digit `treasuryCode` and no recipient account ([account_payment.py:454-463](../custom_addons/gec_odoo_modules/tbc_bank/models/account_payment.py#L454), [:312-317](../custom_addons/gec_odoo_modules/tbc_bank/models/account_payment.py#L312)). Every payment is sent alone through `transfers/single`, batches included ([account_batch_payment.py:24-44](../custom_addons/gec_odoo_modules/tbc_bank/models/account_batch_payment.py#L24)) | **Not built.** No treasury field; the document builder puts only an IBAN in `BeneficiaryAccountNumber` ([account_payment.py:542](../custom_addons/gec_odoo_modules/bog_bank/models/account_payment.py#L542)) |
| **Pay Salaries** | fills type and code from the contact ([account_payment_method_line.py:71-75](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment_method_line.py#L71)) | fills type and code from the contact ([account_payment_method_line.py:73-75](../custom_addons/gec_odoo_modules/tbc_bank/models/account_payment_method_line.py#L73)) | **refuses the whole run** before any payment is created: "Bank of Georgia sends no treasury transfers from Odoo..." ([account_payment_method_line.py:47-63](../custom_addons/gec_odoo_modules/bog_bank/models/account_payment_method_line.py#L47), raised at [hr_payslip.py:236-238](../custom_addons/gec_odoo_modules/gec_payroll_bank/models/hr_payslip.py#L236)) |
| **Hand-made payment** (misc withholding, Entry 2) | you set Transfer Type Treasury and type the code ([views:37, 55-57](../custom_addons/gec_odoo_modules/basis_bank/views/account_payment_views.xml#L37)). Without a type, the send stops: "Set a Basis Bank transfer type before sending" ([account_payment.py:301-302](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L301)) | you set Treasury and the code. Otherwise the type stays National and the send stops: "The recipient bank account is missing" ([account_payment.py:113-116](../custom_addons/gec_odoo_modules/tbc_bank/models/account_payment.py#L113), [:318-319](../custom_addons/gec_odoo_modules/tbc_bank/models/account_payment.py#L318)) | **Odoo does not stop it.** The payment goes out with no recipient account, and BOG refuses it after a live call (the payroll check above is the only refusal, and only Pay Salaries calls it) |
| **Pension Agency** | its Basis account (CBASGE22) → **Internal** | its TBC account → **TransferWithinBank** | its BOG account → **domestic** |

The Pension Agency account is the one whose BIC matches the paying journal ([gec_bank account_move_line.py:20-24](../custom_addons/gec_odoo_modules/gec_bank/models/account_move_line.py#L20)), applied at Register Payment ([account_payment_register.py:19-27](../custom_addons/gec_odoo_modules/gec_bank/models/account_payment_register.py#L19)). Pension is always a normal transfer inside the paying bank; no bank treats it as treasury. [Certain]

**Why BOG cannot pay the Treasury:** the limit is in our `bog_bank`, not at BOG. [Certain]
- Our BOG API reference describes a Treasury payment as an ordinary domestic document whose `BeneficiaryAccountNumber` holds the treasury code ([bog.md:278](../custom_addons/gec_odoo_modules/bog_bank/bog.md#L278), [:318-320](../custom_addons/gec_odoo_modules/bog_bank/bog.md#L318)). BOG has error codes for it: 13 "Not Set Treasury code", 40 "The Treasury code is incorrect", 59 ([:676](../custom_addons/gec_odoo_modules/bog_bank/bog.md#L676), [:741](../custom_addons/gec_odoo_modules/bog_bank/bog.md#L741), [:760](../custom_addons/gec_odoo_modules/bog_bank/bog.md#L760)). Nothing in bog.md says the API refuses treasury payments.
- The module never built that branch. Instead of sending an empty account, Pay Salaries refuses Treasury rows on a BOG channel.
  - The error message "Bank of Georgia sends no treasury transfers" blames the bank.
  - The module's own docstring states it correctly: "The module sends no treasury transfers" ([account_payment_method_line.py:38-39](../custom_addons/gec_odoo_modules/bog_bank/models/account_payment_method_line.py#L38)).
- To build it:
  - Put the contact's Treasury Code in `BeneficiaryAccountNumber`.
  - Do **not** send `PayerInn` on our own treasury payments. The module sends `PayerInn` on every document ([account_payment.py:547](../custom_addons/gec_odoo_modules/bog_bank/models/account_payment.py#L547)), but BOG's code 59 allows payer name and INN only on a treasury payment made for a third person ([bog.md:760](../custom_addons/gec_odoo_modules/bog_bank/bog.md#L760)).
  - bog.md's own open question Q7 ([:1000](../custom_addons/gec_odoo_modules/bog_bank/bog.md#L1000)) is still unanswered, so test in BOG's sandbox first. [Likely]
- prod1 has `bog_bank` installed but no BOG journal and no BOG payment method. Nothing can go through BOG there today. [Certain]

**prod1** (payments to contacts 72 and 73, all outbound, state Paid): [Certain]

| Bank | Treasury payments | Pension payments | Bank side |
|---|---|---|---|
| Basis (BNK5) | 2, 5, 8, 19, 75: Treasury, 101001000 | 1, 4, 7, 18, 74: Internal, account CBASGE22 | all **Pending**, never sent. Batches 1, 3, 5, 7, 21 are op 7 single batches in draft: each mixes one treasury and one pension payment, so neither op 6 nor op 4 applies |
| Basis (BNK5) | **105 = PBNK5/2026/00022, 20.00, 2026-10-12** (Entry 2 of the misc test): **no transfer type, no code, no batch** | — | cannot be sent, single or in a batch, until Treasury + 101001000 are set |
| TBC (BNK6) | 84: Treasury, 101001000, 274.40 | 83: TransferWithinBank, account TBCBGE22 | batch 27 in state Sent; no bank reference on the payments |
| Manual (BNK1) | 50, 53, 56 | 49, 55 | — |

Noticed by the verifier, not checked: a Basis batch of treasury payments that also holds one payment with no transfer type may be sent as op 6 with a wrong item ([account_batch_payment.py:82](../custom_addons/gec_odoo_modules/basis_bank/models/account_batch_payment.py#L82)). [Unverified]

---

## 6. Form 30: rows by income type

**No bill and no journal entry feeds a row.** **Generate Lines** deletes the generated rows and rebuilds annex A from two builders only ([rs_form30_declaration.py:188-190](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L188)). The row builders contain no `move_type`, `in_invoice` or bill search. They look at the payslip's and the payment's journal entry only to add a warning ([:292](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L292), [:349](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L349)).

A bill matters only indirectly. When a bill is paid with withholding, core copies the withholding lines onto the **payment** ([account_payment_register.py:300-304](../addons/l10n_account_withholding_tax/wizards/account_payment_register.py#L300)), and Form 30 reads the payment. **Payment Only** copies none, so it gives no row. Journal items feed only the main-part cells 58-69 ([:475-520](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L475)). Annex D (cars) is typed by hand. [Certain]

| Source | Builder | Income type | Rate | Row date |
|---|---|---|---|---|
| Payslip in state Paid, not a credit note, Payment Date in the month | `_salary_line_vals` ([:255-261](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L255)) | always **1**, hard-coded ([:264](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L264), [:306](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L306)) | always **20** ([:38](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L38), [:310](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L310)) | payslip Payment Date |
| Withholding line of an outbound payment, state Paid or Reconciled, payment date in the month | `_payment_line_vals` ([:318-326](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L318)) | the **withholding tax's** Form 30 Income Type ([:363](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L363)) | the tax's percent ([:367](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L367)) | payment date ([:366](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L366)) |
| Same withholding lines, recipient who pays own tax | `_service_line_vals` → annex E ([:379-383](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L379)) | service type from the tax | — | — |
| Hand-made row (`source = manual`) | none: kept on regenerate ([:188](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L188)), but the list is read-only, `create="0" edit="0"` ([views:62-63](../custom_addons/gec_odoo_modules/gec_income_tax_report/views/rs_form30_declaration_views.xml#L62)), and no code creates one. Odoo's generic import or an RPC call could still create one; not tested [Likely] | — | — | — |

**Income types** are the 15 records of `rs.form30.income.type` ([model](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_classifier.py#L56), [data](../custom_addons/gec_odoo_modules/gec_income_tax_report/data/rs.form30.income.type.csv)). A non-salary type reaches Form 30 only through a withholding tax that carries it. The module sets the type on 18 of our 23 withholding taxes at install, and fills only empty values ([account_tax.py:4-23](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/account_tax.py#L4), [:78](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/account_tax.py#L78)); prod1 matches. The type stays editable on the tax form, page "RS Declaration Rules" ([account_tax_views.xml:9, 14](../custom_addons/gec_odoo_modules/gec_income_tax_report/views/account_tax_views.xml#L9)). [Certain]

| Code | Income type | How a row is made today | Withholding taxes on prod1 (id) |
|---|---|---|---|
| 1 | ხელფასი (salary) | payslip, rate 20 only; or at payment with a salary WHT tax | 64, 67 |
| 2 | დივიდენდი (dividend) | at payment | 48, 56 |
| 3 | პროცენტი (interest) | at payment | 49, 54, 57 |
| 5 | სტიპენდია (stipend) | at payment | 62 |
| 6 | სხვა (other) | **no tax carries it today** (D4) | — |
| 7 | მომსახურების ანაზღაურება (service fee) | at payment | 51, 55, 60, 61 |
| 16 | მოგება (profit) | **no tax carries it today** | — |
| 17 | როიალტი (royalty) | at payment | 50, 53, 59 |
| 18 | social-tax remuneration | valid only to 2024/11 | — |
| 19 | იჯარის მომსახურების ანაზღაურება (rent) | at payment | 52, 58, 63 |
| 20 | partnership income share | **no tax carries it today** | — |
| 21 | დაბრუნებული პენსია (returned pension) | **no tax carries it today** | — |
| 22, 23 | gambling / slot-machine withdrawals | **no tax carries it today** | — |
| 24 | hotel-room remuneration | **no tax carries it today** | — |
| no type | gift 20%, goods without waybill 3%, non-resident other income 10%, telecom/transport 10%, oil and gas 4% | row created without a type, warns ([:344-345](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L344)), blocks export ([:826-831](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L826)) | 65, 66, 68, 69, 70 |

"No tax carries it today" is a **configuration gap, not a code limit**. Once the accountant sets that type on a withholding tax, or creates one, and the tax is picked at payment, Generate Lines declares it wherever the rate matrix allows the pair. The matrix has rules for all of them: type 6 has 16, type 16 has 11, type 20 has 6. An earlier draft of this plan said these types could "never" be declared; the verifier refuted that. [Certain]

Payroll never produces a type other than 1: `geo_payroll` and `gec_payroll_bank` contain no Form 30 reference. [Certain]

What this means for the agreed scope:
- **Salaries:** work, except for employees whose rate is not 20. The rate matrix allows type 1 at other rates in some categories ([rs.form30.rate.rule.csv](../custom_addons/gec_odoo_modules/gec_income_tax_report/data/rs.form30.rate.rule.csv) rows 3-6, 28, 41-42, 74-75, 97-99, 111, 123):
  - 0, 5, 10 and 12 in the usual category;
  - only 4 in category 3.5;
  - only 10 in category 3.6.

  The builder always writes 20. [Certain]
- **Misc journal entries:** a row exists only when the line is paid with withholding and a withholding tax is picked in the **Withholdings** tab. The tax picked is the only thing that decides the income type and the rate. [Certain]
- **Types no tax carries** (6, 16, 20-24): set the type on a withholding tax first (D4). Income with no withholding line in Odoo at all still needs a hand-made row, and the UI has none (F30-2). [Certain]

prod1: one declaration, 2026/09, exported, 17 rows, all payslip rows of type 1. The 7 October withholding lines (types 3 and 17) are not declared yet; 6 sit on payments that paid test bills BILL/2026/10/0003-0009, one (MISC/2026/10/0010) on no bill. [Certain]

Problems:

| # | Problem | Evidence | Status |
|---|---|---|---|
| F30-1 | **Withholding booked in a journal entry gives no row.** This covers any misc-entry split (Ana 80 / Treasury 20) and the CIT wizard's dividend withholding | sources above; [gec_income_tax_report.md](gec_income_tax_report.md) (CIT wizard note) | [Certain] |
| F30-2 | **Annex A rows cannot be added or edited in the UI.** The model supports manual rows (kept on regenerate), but the list is read-only and no action exists. That leaves two things with no way into Odoo's file: every salary rate other than 20, and any withheld income that has no withholding line in Odoo. Odoo's generic import may still work; not tested | [views:62-63](../custom_addons/gec_odoo_modules/gec_income_tax_report/views/rs_form30_declaration_views.xml#L62), [rs_form30_declaration.py:188](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L188), [:599-601](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L599); [gec_income_tax_report.md](gec_income_tax_report.md) lines 130 and 228 contradict each other; README "Salary rows always use rate 20" | [Certain] |
| F30-3 | **A Withhold Only record is declared even if the person was never paid.** The filter checks only payment state, direction and date. Example: MISC/2026/10/0010 (TEST Ana, WHT 5) has its payable line still open, not matched to any bill or payment, yet it would produce a row. The row date is the withhold record's date, not the cash date | [:320-326](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L320); prod1 SELECT | [Certain] for the filter; the tax-rule consequence is [Likely] |
| F30-4 | **5 of 23 withholding taxes have no Form 30 income type** (ids 65 gift 20%, 66 goods without waybill 3%, 68 non-resident other income 10%, 69 international telecom/transport 10%, 70 oil and gas subcontractor 4%), so their rows cannot export | prod1 SELECT; [l10n_ge.md](l10n_ge.md) Form 30 note | [Certain] |
| F30-5 | **A transfer sent from Internet Banking (bank line only) gives no row** | [gec_income_tax_report.md](gec_income_tax_report.md) (bank-statement note) | [Certain] |
| F30-6 | **October test data would not export:** 7 withholding lines (WHT/2026/00001-00007), all TEST contacts without Tax ID, country or category, with non-resident taxes | prod1 SELECT | [Certain] (test data) |
| F30-7 | If "Withhold Only" on journal lines is made to work (see I-2), the row date and the cash date can fall in different months | design | [Likely] |
| F30-8 | **Salary rows are always type 1 at rate 20**, whatever the employee's category; payroll has no field for another type or rate. Some categories have no type-1 rule at 20 (1.3, 3.5, 3.6). For an employee in one of them, the matrix check would probably refuse the row and stop Generate Lines for the whole declaration ([:804-820](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L804)) [Likely, noticed by the verifier, not run] | [:38](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L38), [:264](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L264), [:310](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L310); no Form 30 reference in geo_payroll / gec_payroll_bank | [Certain] |

Known from earlier sessions, **not re-checked today**: the `ISO_TABLE` generator path (`parents[5]`), a stale export file when an annex becomes empty, `action_export_explanation` writing on the declaration (access error for read-only users), category and income-type pickers that do not search by code. The v20 `is_company` split of Georgian individuals is **fixed** ([gec_localization res_partner.py:45](../custom_addons/gec_odoo_modules/gec_localization/models/res_partner.py#L45)). [Certain for the fix]

Only one declaration exists on prod1: **2026/09, exported**. [Certain]

---

## 7. Issues list

Each issue: what happens (with numbers), cause, simplest fix that follows core.

### Rule A: money sent to the bank must equal the cash line

| ID | Severity | What happens | Cause | Simplest fix |
|---|---|---|---|---|
| I-1 | High | Ana is owed 100, 20% withheld: Withhold and Pay through Basis/TBC/BOG sends **100**, the government gets nothing, and the 80 bank line never auto-matches | adapters send `payment.amount` ([5.7](#57-bank-modules-basis-tbc-bog)) | Adapters send the payment's liquidity (bank) line amount and match on it; until then refuse Withhold and Pay on bank-API methods with a clear message |
| I-2 | High | Misc entry Ana 100: Withhold Only from the journal line likely creates a 0 amount, so the documented flow cannot work | Withhold Only amount = declared withholding residual, 0 for journal entries ([5.2](#52-withholding-mechanics-in-core)) | Use Withhold and Pay (after I-1). Optional: Argentina-style override that takes the Withhold Only amount from the lines. Prove on a scratch DB first |

### Rule B: a withholding tax is chosen only at payment

Form 30 does not depend on this rule: it reads the payment's withholding line, never a bill ([section 6](#6-form-30-rows-by-income-type)). The bill items that used to sit here (I-3 to I-5) are listed apart in [7.6](#76-not-form-30-bill-side-effects).

### Rule C: the government is paid by a real payment linked to the debt

| ID | Severity | What happens | Cause | Simplest fix |
|---|---|---|---|---|
| I-6 | Medium | Every misc withholding needs Entry 2 and a hand-made treasury payment with Transfer Type and code typed by hand | no flow ([5.4](#54-paying-the-state-treasury)) | Phase 5: Treasury payment created automatically (Pay Salaries pattern); treasury type filled automatically for contacts with a Treasury Code |
| I-7 | Decision | Which Payable account holds "withholding to pay to the Treasury" | 331210/331212 are not Payable | Accountant: new account or 331320 |
| I-8 | Low | Aged Payable hides the Treasury line | non-trade filter ([5.5](#55-paying-journal-entries)) | Document; no code |
| I-17 | Medium | BOG cannot pay the Treasury. Pay Salaries refuses the whole run on a BOG channel. A hand-made BOG payment to the Treasury is not stopped in Odoo: it goes out with no recipient account and BOG refuses it after a live call | `bog_bank` never built the treasury document, although our BOG API notes describe it ([5.13](#513-paying-the-treasury-and-the-pension-agency-by-bank)) | Treasury Code in `BeneficiaryAccountNumber`, no `PayerInn` on own treasury payments, BOG sandbox test. Until then, also refuse hand-made BOG payments to a Treasury Code contact. Not urgent: prod1 has no BOG journal |
| I-18 | Medium | Hand-made treasury payments need Transfer Type and Treasury Code typed by hand (Basis, TBC). prod1 payment PBNK5/2026/00022 (20 GEL) has neither and cannot be sent | only Pay Salaries fills them ([5.13](#513-paying-the-treasury-and-the-pension-agency-by-bank)) | Fill type and code from the contact's Treasury Code on every Basis and TBC payment, the same way Pay Salaries does |
| I-19 | Low | The BOG message "Bank of Georgia sends no treasury transfers from Odoo" blames the bank | wording ([account_payment_method_line.py:62](../custom_addons/gec_odoo_modules/bog_bank/models/account_payment_method_line.py#L62)), copied into READMEs | Say "This module does not send treasury transfers yet", or drop it once I-17 is built |

### Rule D: Form 30 must declare what was withheld and paid

| ID | Severity | What happens | Cause | Simplest fix |
|---|---|---|---|---|
| I-9 | High | Withholding in journal entries and CIT dividends missing from Form 30 | F30-1 | Pay the journal line with withholding and pick the tax in the Withholdings tab; decide for CIT dividends (D3) |
| I-10 | High | Salary rates other than 20, and withheld income with no withholding line in Odoo, cannot be declared from Odoo | F30-2, F30-8 | Give annex A an add/edit path for manual rows (they already survive regenerate), or state in the docs that these go on the portal by hand |
| I-11 | Medium | Withhold Only records declared without a matching cash payment | F30-3 | Decide the rule with the accountant (declare on cash payment date), then filter |
| I-12 | Medium | 5 taxes without income type; no tax carries types 6, 16, 20-24 | F30-4, [section 6](#6-form-30-rows-by-income-type) | Configuration: the accountant sets the types on the taxes (or adds taxes) on the tax form; no code |

### Rule E: test safely

| ID | Severity | What happens | Cause | Simplest fix |
|---|---|---|---|---|
| I-13 | High | Pressing Send to Basis on prod1 moves real money | live connection | Test on a scratch DB; cancel PBNK5/2026/00020 and 00021 |
| I-14 | Low | Test debris on prod1: 331212 35 GEL, MISC/2026/10/0010 open +5 on Ana, MISC/2026/10/0013 posted before its withholding (331210 −20), MISC/2026/10/0006 open on 160610, bank line "tetetet" on the wrong bank | tests | Clean up or reverse (user's decision) |
| I-15 | Low | 331213 is named "Withholding Tax (WHT)" with no Georgian name | setup | Rename: "Withholding Tax (WHT) Base (technical)" / "გადახდის წყაროსთან დაკავებული გადასახადი — ბაზა (ტექნიკური)" |
| I-16 | Low | Settings page crashes until the server restarts | addons path | Restart the server with `odoo.conf` |

### 7.6 Not Form 30: bill side effects

These concern bills and VAT, not Form 30. I-3 stays because it silently drops VAT. [Certain]

| ID | Severity | What happens | Cause | Simplest fix |
|---|---|---|---|---|
| I-3 | Low (VAT) | A contact with Default Purchase Tax = a WHT tax: the bill line loses its VAT tax (18% or VAT Exempt) and gets only the WHT tax, so the purchase is missing from the VAT Report. No prod1 contact is set this way (only contact 212 has a default, and it is not a WHT tax) | domain allows withholding taxes ([res_partner.py:27](../custom_addons/gec_odoo_modules/gec_localization/models/res_partner.py#L27)); the default replaces every non-withholding tax ([account_tax.py:8-16](../custom_addons/gec_odoo_modules/gec_localization/models/account_tax.py#L8)) | Add `('is_withholding_tax', '=', False)` like the sales field |
| I-4 | Low | Docs tell users to put WHT taxes on bills, products and contact defaults | docs ([5.10](#510-our-georgian-setup)) | Rewrite: salaries = payslip, misc = at payment |
| I-5 | Low | 7 posted test bills carry WHT taxes | test data | Clean up on prod1 (user's decision) |

---

## 8. Plan

Run through /odoo-team: scouts collect, the main session plans, the builder writes, bug-hunter / reviewer / verifier on money changes. Each phase is approved and committed by the user. Tests are proposed per phase and written only on the user's yes.

| Phase | Goal | Changes | Modules | Size | Depends on |
|---|---|---|---|---|---|
| 0 | Prove the two open behaviours | On a scratch DB: (a) Withhold Only from a journal-entry line, (b) Withhold and Pay from a journal-entry line with a hand-added line; record the entries and the Form 30 rows | none | Small | user's OK for a scratch DB |
| 1 | Money safety (I-1) | Send the liquidity-line amount for payments with withholding; match statements on it; until shipped, refuse Withhold and Pay on bank-API methods | basis_bank, tbc_bank, bog_bank, gec_bank | Small–medium, critical | Phase 0 |
| 2 | One-click misc flow (I-2) | Journal line → Withhold and Pay through Basis gives 80 to the person, 331210, certificate and Form 30 row; optional Argentina-style Withhold Only amount | gec_localization (optional override) | Small | Phase 1 |
| 3 | Docs and VAT safety net, not Form 30 (I-3, I-4, I-8) | Hide WHT taxes from the contact Default Purchase Tax; rewrite `l10n_ge.md` "Withholding at Payment", gec_localization README section 8 and contact defaults, `gec_income_tax_report.md` sources (by income type, as in section 6) | gec_localization, documentations | Tiny + docs | — |
| 4 | Form 30 (I-9 to I-12) | /odoo-team review of gec_income_tax_report (bug-hunter), then: manual-row path for types 6, 16, 20-24 and non-20 salary rates; income types for the 5 taxes; cash-date rule for Withhold Only; CIT dividend decision | gec_income_tax_report, gec_localization data | Medium | accountant decisions |
| 5 | Treasury payment (I-6, I-7) | When a payment with withholding is confirmed: move the tax to the Treasury Payable, create the treasury payment (type and code from the contact, see 5a), batch it with the person's payment | gec_bank + bank adapters, or a small glue module | Medium, critical | Phase 1, D1 |
| 5a | Treasury fields from the contact (I-18) | Every Basis and TBC payment to a contact with a Treasury Code gets Transfer Type Treasury and the code, not only Pay Salaries | basis_bank, tbc_bank (or gec_bank) | Small | — |
| 5b | BOG treasury transfer (I-17, I-19) | Treasury branch in the BOG document, no `PayerInn` on own treasury payments, BOG sandbox test; until then refuse hand-made BOG treasury payments and fix the message | bog_bank | Small–medium, money | D10, BOG sandbox |
| 6 | Data cleanup (I-5, I-13 to I-16) | Cancel test payments, reverse or reconcile test entries, rename 331213, restart the server | prod1 (user runs) | Small | user |

Optional later: the contact **Withholding Tax Categories** from Odoo's PR (filters offered taxes); wait until Odoo merges it to avoid a duplicate field.

---

## 9. Decisions needed

| ID | Question | Who |
|---|---|---|
| D1 | Payable account for "withholding to pay to the Treasury": new account or 331320 | Accountant |
| D2 | Form 30: declare on the date the person is paid (cash) or on the withholding date | Accountant |
| D3 | Dividend withholding from the CIT wizard: must it appear in Form 30 | Accountant |
| D4 | Income types for the 5 taxes without one. Earlier guess in [rs_form30_full_declaration_gap_plan.md](rs_form30_full_declaration_gap_plan.md) (A13): 6, 6, 6, 7, 7 for gift, goods without waybill, non-resident other income, telecom/transport, oil and gas [Likely, not confirmed] | Accountant |
| D9 | Salary rates other than 20 and withheld income with no withholding line: build a manual-row path in annex A, or declare them on the portal by hand | User + accountant |
| D10 | Build BOG treasury transfers (Phase 5b). Needed only if a company pays taxes through BOG; prod1 has no BOG journal | User |
| D11 | Which withholding taxes should carry types 6, 16, 20-24 (configuration on the tax form) | Accountant |
| D5 | Fix I-1 by sending the net (recommended) or only by refusing Withhold and Pay | User |
| D6 | Build the automatic Treasury payment (Phase 5) or keep the manual Entry 2 | User |
| D7 | Clean up the prod1 test data | User |
| D8 | Scratch DB for Phase 0 | User |

---

## 10. Changes made today

| What | Where | State |
|---|---|---|
| Gotchas: Withhold Only never appears in bank reconciliation; how to choose the base account and never an off-balance one | [taxes.md](taxes.md) "Withholding Taxes → Gotchas" | uncommitted |
| Section "Paying the State Treasury is a separate, manual step" | [l10n_ge.md](l10n_ge.md) "Withholding at Payment" | uncommitted; must be revised in Phase 3 |
| `addons_path` + `custom_addons/alta_hr_customization` + `custom_addons/extra_modules` | `odoo.conf` | not in git; restart pending |
| This plan and its INDEX row | `documentations/` | new |
| Account 331213 created and set as Withholding Tax Base; BILL/2026/10/0009, MISC/2026/10/0012, PBNK5/2026/00021, MISC/2026/10/0013 created | prod1, by the user | live |
| Nothing written to any database by Claude; no code changed | — | — |
| 2026-10-13: section 6 rewritten by income type; 5.13 added; bill items moved to 7.6; I-17 to I-19, F30-8, phases 5a/5b, D9 to D11 added | this plan | uncommitted |

---

## 11. Evidence index

### Database checks (`gec20_prod1`, read-only)

| Check | Result |
|---|---|
| BILL/2026/10/0008, MISC/2026/10/0011, PBNK5/2026/00020 lines and reconciliations | bill 100 = 95 + 5, matching #104; only the 120410 −95 line open |
| Statement line "tetetet" | id 121, −95.00, 2026-10-09, BNK1, unreconciled |
| Journals BNK1 / BNK5 | Bank 120110 (source undefined) / BASIS GEL 120003 (basisbank) |
| Company setting after the user's change | Withholding Tax Base = 331213 |
| BILL/2026/10/0009 chain | bill line tax "WHT 5% - Non-resident Royalties"; base pair on 331213; 331212 −5; PBNK5/2026/00021 95 |
| Payments 97-100 | withhold records Reconciled; PBNK5 payments Paid, Basis state Pending, no send date |
| Basis connection | direct mode, active, bis.bankonline.ge |
| Lines on 331212 | 7 × 5.00 = 35.00, partners TEST Maka (4) and TEST Ana (3) |
| Payments to State Treasury | PBNK6/2026/00002 274.40 (TBC); PBNK5/2026/00002, 00005, 00008, 00011, 00016 (Basis); PBNK1 manual ones; counterpart 331320 (checked 00011, 00016) |
| Basis batches | 0022 salary package; 0021 and 0005 single batch (Pension Agency + Treasury); 0007 single batch with 4 payments |
| SLR/2026/09/0016 | lines as in [5.8](#58-salaries) |
| MISC/2026/10/0006 | VAT test entry by `__system__`, 160610 −1,000 open |
| Misc-journal payable lines | all reconciled except MISC/2026/10/0010 (+5, TEST Ana) |
| MISC/2026/10/0013 | 331210 Dr 20 (open), 331320 Cr 20 State Treasury (open) |
| Withholding taxes | 23, all active; 5 without Form 30 income type (65, 66, 68, 69, 70); income types of 51, 55, 58-61, 63 checked |
| Fiscal positions / products / bills with WHT | 0 / 0 / 7 posted bills |
| Withhold and Pay payments | only PBNK1/2026/00023: Amount 100, Outstanding 95, Manual Payment |
| Form 30 declarations | one: 2026/09, exported |
| Withholding lines | 7 (WHT/2026/00001-00007), October, TEST contacts without Tax ID, country or category |
| Installed modules missing from the addons path | hr_customization, booking_engine, base_industry_data |
| Accounts for the entries | 740100, 741100, 749000 (expense); 310110 (Payable, trade); 331320 (Payable, non-trade, reconcilable) |
| 2026-10-13: Form 30 rows | declaration 1 (2026/09): 17 rows, all `payslip`, type 1, rate 20; no `payment` or `manual` rows |
| 2026-10-13: withholding lines vs bills | 7 lines on payments 86-99 (types 3 and 17); 6 reconciled with BILL/2026/10/0003-0009, line 5 (MISC/2026/10/0010) with no bill |
| 2026-10-13: taxes by income type | 1: 64, 67; 2: 48, 56; 3: 49, 54, 57; 5: 62; 7: 51, 55, 60, 61; 17: 50, 53, 59; 19: 52, 58, 63; none: 65, 66, 68, 69, 70 |
| 2026-10-13: rate rules | 152 rows; type 1 at rates 0, 4, 5, 10, 12, 20 depending on category |
| 2026-10-13: contacts 72 / 73 | Pension Agency: no code, 10 accounts (ids 1-10, one per bank, all trusted); State Treasury: code 101001000, no account |
| 2026-10-13: payments to 72 / 73 | 18, all outbound Paid; table in [5.13](#513-paying-the-treasury-and-the-pension-agency-by-bank) |
| 2026-10-13: BOG on prod1 | `bog_bank` installed; no BOG journal, no `bog_transfer` method line |

### Code checked (beyond the links above)

- Bank reconciliation search, Set Account, learned rules, payment-without-entry matching: [account_bank_statement_line.py:515](../addons/account/models/account_bank_statement_line.py#L515), [account_bank_statement.py:1308](../enterprise/account_accountant/models/account_bank_statement.py#L1308), [:1431](../enterprise/account_accountant/models/account_bank_statement.py#L1431), [:2219](../enterprise/account_accountant/models/account_bank_statement.py#L2219).
- Payment register: [account_payment_register.py:1003-1056](../addons/account/wizard/account_payment_register.py#L1003), [:1264-1293](../addons/account/wizard/account_payment_register.py#L1264), [:1295-1377](../addons/account/wizard/account_payment_register.py#L1295).
- Withholding module: account_tax.py, account_move.py, account_payment.py, account_withholding_line.py, account_payment_withholding_line.py, both wizards and their views, `withhold_selector.js`, the flow and amount tests.
- Countries: l10n_ar_withholding, l10n_in (+ l10n_in_hr_payroll TDS rule and challan), l10n_ec / l10n_ec_edi, l10n_co / l10n_co_edi / l10n_co_reports, l10n_pe / l10n_pe_edi_withholding, l10n_ph / l10n_ph_reports, l10n_mx / l10n_mx_edi, l10n_br, l10n_cl / l10n_cl_reports_f29, l10n_sa (+ empty l10n_sa_withholding_tax), account_reports (no withholding code).
- Ours: basis_bank (payment, batch, method line, statement line, service, views), gec_bank (method line config, statement matching, sendable checks), tbc_bank, bog_bank, gec_payroll_bank (Pay Salaries, register override), geo_payroll (register override, State Treasury data), gec_localization (taxes, contact defaults, treasury code, CIT wizard, templates), gec_income_tax_report (declaration, service rows, cars, views, grids, security, docs).
- Odoo's Georgian PR #292088: all 26 files (manifest, tax CSV, categories, report, models, views, tests).

### Agents used today

13 Haiku scouts (Treasury flow, paying non-payable liabilities, withholding settlement, paying journal entries, other countries' government payments, payments vs bank-only, Form 30 sources, batches and treasury fill, core assignment, Argentina/India, eight countries, Odoo's Georgian PR, our setup) and 1 Opus verifier (6 claims, all confirmed, two citations corrected).

2026-10-13: 12 Haiku scouts in two workflows:
- Form 30: income type model, declaration builders, payslip path, prod1 rows, payment withholding path, existing docs.
- Banks: Basis, TBC and BOG treasury/pension, Pay Salaries authorities, gec_bank hooks + prod1 payments, earlier BOG claim.

2 Opus verifiers:
- Form 30: 7 claims, 6 confirmed, A3 "types 6/16/20-24 can never be declared" refuted (configuration gap).
- Banks: 10 claims, all confirmed, 4 line corrections.

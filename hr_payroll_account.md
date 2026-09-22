# Payroll Accounting — From Payslip to Journal Entry

> **Modules:** `hr_payroll_account` | **Path:** [`enterprise/hr_payroll_account/`](../enterprise/hr_payroll_account/)
> Siblings covered here: `hr_payroll_account_iso20022` (SEPA/ISO 20022 salary payments), `hr_payroll_expense` (expense reimbursement through payslips), `project_hr_payroll_account` (project stat button only).
>
> **Updated by Codex and verified from source: 2026-07-12.** Custom wage/work-log implementation plan: [`../PAYROLL_WAGE_TYPES_PLAN.md`](../PAYROLL_WAGE_TYPES_PLAN.md).

## What It Does & Why It Exists

`hr_payroll_account` is the bridge between HR payroll and the general ledger — the "money-out" side of payroll. Without it, a validated payslip is just an HR document; with it, validating a payslip also produces a **draft** `account.move` in a dedicated salary journal, built line by line from the debit/credit accounts configured on each salary rule. It also provides the payment side: a **Pay** button on the payslip that opens the standard register-payment wizard against the payslip's journal entry, tracks reconciliation, and flips the payslip to `paid` automatically. It auto-installs whenever `hr_payroll` and `accountant` are both installed ([__manifest__.py:38](../enterprise/hr_payroll_account/__manifest__.py#L38)). This is the module a Georgian implementation must configure (accounts on rules, journal on structure) before payroll can hit the GL.

---

## The Big Picture — How It Works

```
Draft payslip (computed lines)
        |  "Create Draft Entry" button (= action_payslip_done)
        v
Payslip state: validated  +  DRAFT account.move in structure's salary journal
        |  accountant reviews & posts the move (manual)
        v
Posted move
        |  "Pay" button -> account.payment.register wizard
        v
Payment created & reconciled against the NET payable line
        |  when move residual == 0
        v
Payslip state: paid (paid_date = payment date)
```

The validate button is relabelled **Create Draft Entry** by this module ([hr_payslip_views.xml:21](../enterprise/hr_payroll_account/views/hr_payslip_views.xml#L21)) because that is literally what it does: [action_payslip_done()](../enterprise/hr_payroll_account/models/hr_payslip.py#L43) runs the base HR validation, then calls `_action_create_account_move()` for every slip that has a journal. The move is **created in draft, never auto-posted** — the test suite explicitly asserts you must post it before registering payment ([test_hr_payroll_payment.py:70](../enterprise/hr_payroll_account/tests/test_hr_payroll_payment.py#L70)).

### Key Decision Points

- **Per-slip vs per-batch moves** — company setting `batch_payroll_move_lines`. Off (default): one move per payslip. On: all slips of a validation are merged into one move per (journal, month), lines aggregated and anonymized, and the per-slip Pay button disappears.
- **Which accounts** — set per salary rule (`account_debit` / `account_credit`, both company-dependent). Rules without accounts are silently skipped in the move.
- **Accounting date** — payslip field `date` ("Date Account"); empty means end of month of `date_to`.
- **How the NET is booked** — the NET line is booked at its full total minus every rule flagged `not_computed_in_net`.

---

## Rule → Journal Item Mapping (the core)

Everything is driven by fields added to `hr.salary.rule` ([hr_salary_rule.py](../enterprise/hr_payroll_account/models/hr_salary_rule.py)):

| Field | Effect on the journal entry |
|---|---|
| `account_debit` / `account_credit` | Company-dependent. Positive rule total → debit on `account_debit`, credit on `account_credit`. Negative total swaps sides. A rule may have one, both, or neither. |
| `not_computed_in_net` | Reduces the amount booked for the **NET** line (accounting only — payslip NET itself is untouched). The flagged rule must carry its own accounts to be booked independently ([hr_salary_rule.py:17](../enterprise/hr_payroll_account/models/hr_salary_rule.py#L17)). |
| `split_move_lines` | Journal item label = payslip **line** name instead of rule name, so lines don't merge (used by default on deduction/attachment/child-support/reimbursement rules, [hr_salary_rule_data.xml](../enterprise/hr_payroll_account/data/hr_salary_rule_data.xml)). |
| `employee_move_line` | Puts the employee's work contact as partner on the journal item and prevents cross-employee merging (set by default on NET rules). Ignored in batch mode. |
| `debit_tag_ids` / `credit_tag_ids` | Tax report grids stamped on the debit/credit journal item — this is how payroll amounts land in tax reports without real taxes ([hr_salary_rule.py:20](../enterprise/hr_payroll_account/models/hr_salary_rule.py#L20)). Exposed per payslip line as computed fields meant to be overridden by localizations ([hr_payslip_line.py:24](../enterprise/hr_payroll_account/models/hr_payslip_line.py#L24)). |
| `analytic_distribution` | Rule-level analytic distribution (rule inherits `analytic.mixin`, [hr_salary_rule.py:9](../enterprise/hr_payroll_account/models/hr_salary_rule.py#L9)). |
| `partner_id` (base field) | Third party of the rule (tax office, pension fund…) — becomes the journal item partner when `employee_move_line` is off ([hr_payslip_line.py:34](../enterprise/hr_payroll/models/hr_payslip_line.py#L34)). |

### Move construction, step by step

[_action_create_account_move()](../enterprise/hr_payroll_account/models/hr_payslip.py#L54):

1. **Scope widening:** if a slip belongs to a batch and the batch has any validated/cancelled slip ([_are_payslips_ready](../enterprise/hr_payroll/models/hr_payslip_run.py#L419)), *all* slips of the batch are pulled in. Then filter: `state == 'validated'`, no existing `move_id`, structure has a journal ([hr_payslip.py:64](../enterprise/hr_payroll_account/models/hr_payslip.py#L64)).
2. **Grouping:** batch mode → one bucket per (journal, month); normal mode → one bucket per slip ([hr_payslip.py:70](../enterprise/hr_payroll_account/models/hr_payslip.py#L70)). Month key = `slip.date or end_of(date_to, 'month')`.
3. **Line generation** per slip ([_prepare_slip_lines](../enterprise/hr_payroll_account/models/hr_payslip.py#L166)): iterate payslip lines that have a category; skip zero totals; for the `NET` line subtract every `not_computed_in_net` rule total ([hr_payslip.py:172](../enterprise/hr_payroll_account/models/hr_payslip.py#L172)); book debit account side, then credit account side. Lines merge into an existing line when name, account, side, analytic distribution and tax tags all match ([_get_existing_lines](../enterprise/hr_payroll_account/models/hr_payslip.py#L254)) — unless `employee_move_line` forces separation (non-batch mode).
4. **Multi-bank split:** if the rule has `employee_move_line` and the employee has several bank accounts, the NET amount is split into one journal item per bank account using the employee's fixed/percentage salary allocations ([hr_payslip.py:132](../enterprise/hr_payroll_account/models/hr_payslip.py#L132), allocation math in [compute_salary_allocations](../enterprise/hr_payroll/models/hr_payslip.py#L2190)). Each item stores `employee_bank_account_id`, a field this module adds to `account.move.line` ([account_move_line.py:7](../enterprise/hr_payroll_account/models/account_move_line.py#L7)).
5. **Balancing:** if debits ≠ credits, an **Adjustment Entry** line on the journal's `default_account_id` absorbs the difference; missing default account raises ([_prepare_adjust_line](../enterprise/hr_payroll_account/models/hr_payslip.py#L222)).
6. **Creation:** moves created with `sudo()` ([hr_payslip.py:274](../enterprise/hr_payroll_account/models/hr_payslip.py#L274)) — payroll officers don't need account-creation rights. Slips get `move_id` and `date` written back; in batch mode the run gets `move_id` too ([hr_payslip.py:119](../enterprise/hr_payroll_account/models/hr_payslip.py#L119)).

Move header: `ref` = "Month Year" of the period, `narration` = list of slip id + employee name per slip ([hr_payslip.py:91](../enterprise/hr_payroll_account/models/hr_payslip.py#L91)).

### Taxes and tax grids

There are no `tax_ids` on salary rules. Instead, each generated journal item copies the **default taxes of the GL account** (`account.tax_ids`) ([hr_payslip.py:163](../enterprise/hr_payroll_account/models/hr_payslip.py#L163)) and carries the rule's debit/credit **tax grids**. So payroll-to-tax-report wiring is done with grids on rules, not taxes.

---

## Journal Resolution & Required Configuration

| Where | What | Source |
|---|---|---|
| `hr.payroll.structure.journal_id` | The **only** journal source. Company-dependent, required in the form view, defaults to the journal of `hr_payroll.default_structure`. | [hr_payroll_structure.py:15](../enterprise/hr_payroll_account/models/hr_payroll_structure.py#L15) |
| `hr.payslip.journal_id` | Related (read-only) to `struct_id.journal_id`. | [hr_payslip.py:16](../enterprise/hr_payroll_account/models/hr_payslip.py#L16) |
| Journal currency | Constraint: must be the company currency — payroll entries are always company-currency ([hr_payroll_structure.py:19](../enterprise/hr_payroll_account/models/hr_payroll_structure.py#L19)). |
| Journal deletion | Blocked while any salary structure references it ([account_journal.py:10](../enterprise/hr_payroll_account/models/account_journal.py#L10)). |

**Install hooks:** a pre-init hook renames any pre-existing journal coded `SLR` (to `SLR0`, `SLR1`…) to free the code ([__init__.py:18](../enterprise/hr_payroll_account/__init__.py#L18)); the post-init hook then creates a miscellaneous "Salaries" journal (code `SLR`) per company with a chart template and assigns it to the default structures ([__init__.py:10](../enterprise/hr_payroll_account/__init__.py#L10), templates in [account_chart_template.py:69](../enterprise/hr_payroll_account/models/account_chart_template.py#L69)).

**Localization hook:** after loading a chart template, `_load_payroll_accounts` looks for `_configure_payroll_account_<template_code>` ([account_chart_template.py:16](../enterprise/hr_payroll_account/models/account_chart_template.py#L16)). The generic helper [_configure_payroll_account()](../enterprise/hr_payroll_account/models/account_chart_template.py#L26) maps account codes and tax grids onto rules per company — this is exactly what the ~30 `l10n_*_hr_payroll_account` modules do, and the pattern to copy for a Georgian `_configure_payroll_account_ge`.

### What breaks when configuration is missing

| Missing | Behavior |
|---|---|
| Journal on structure | Slip shows a dashboard warning "Account Journal not configured on Structure" ([hr_payslip.py:25](../enterprise/hr_payroll_account/models/hr_payslip.py#L25)); validation succeeds but **no move is created, silently** — the filter just drops the slip. |
| Debit or credit account on a rule | No error. The one-sided imbalance is silently absorbed by the Adjustment Entry on the journal default account. |
| Journal `default_account_id` when adjustment needed | `UserError` at move creation ([hr_payslip.py:225](../enterprise/hr_payroll_account/models/hr_payslip.py#L225)). |
| Non-reconcilable credit account on NET rule | Pay button raises "The credit account on the NET salary rule is not reconciliable" ([hr_payslip.py:283](../enterprise/hr_payroll_account/models/hr_payslip.py#L283)). |
| Untrusted employee bank account (`allow_out_payment` off) | Pay button raises "An employee bank account is untrusted" ([hr_payslip.py:286](../enterprise/hr_payroll_account/models/hr_payslip.py#L286)). |

---

## Paying Payslips

The base **Mark as Paid** button is hidden by this module ([hr_payslip_views.xml:39](../enterprise/hr_payroll_account/views/hr_payslip_views.xml#L39)); payment goes through accounting:

1. **Pay** button (visible when `state == 'validated'`, move exists, batch mode off, user in `account.group_account_invoice`) calls [action_register_payment()](../enterprise/hr_payroll_account/models/hr_payslip.py#L277). Guards: slip not paid, NET credit account reconcilable, all employee bank accounts trusted, move **posted**. It opens the standard `account.payment.register` wizard on the move's lines with defaults: partner = employee work contact, bank = primary employee bank account, plus contexts `payment_consider_partner` and (from the button) `hr_payroll_payment_register` / `dont_redirect_to_payments` ([hr_payslip_views.xml:30](../enterprise/hr_payroll_account/views/hr_payslip_views.xml#L30)).
2. Under `hr_payroll_payment_register`, the payment wizard accepts `liability_current` accounts as payable — normally only receivable/payable can be paid ([account_payment.py:10](../enterprise/hr_payroll_account/models/account_payment.py#L10)). So the salary payable account does not need to be of type Payable.
3. The wizard groups lines per `employee_bank_account_id` when set (multi-bank split → one payment per bank account), else falls back to the partner's first bank account ([account_payment_register.py:10](../enterprise/hr_payroll_account/wizard/account_payment_register.py#L10)).
4. After reconciliation, [_reconcile_payments()](../enterprise/hr_payroll_account/wizard/account_payment_register.py#L24) posts cross-links in the chatter and, once **every** line of the payslip move has zero residual, writes the slip to `state = 'paid'` with `paid_date` = payment date.

Batch mode / no per-slip payments: pay the posted batch move manually or export a payment file (below), then use the batch's **Mark as Paid** ([action_paid](../enterprise/hr_payroll/models/hr_payslip_run.py#L284)).

### Payment reports (CSV / SEPA)

The base `hr.payroll.payment.report.wizard` (in `hr_payroll`) exports a CSV of net amounts per employee bank account and stamps `paid_date` on the slips ([hr_payroll_payment_report_wizard.py:90](../enterprise/hr_payroll/wizard/hr_payroll_payment_report_wizard.py#L90)) — it does **not** set state to paid and touches no accounting.

`hr_payroll_account_iso20022` adds `sepa` and `iso20022_ch` export formats with a bank-journal selector ([hr_payroll_payment_report_wizard.py:10](../enterprise/hr_payroll_account_iso20022/wizard/hr_payroll_payment_report_wizard.py#L10)):

- Builds one payment per (slip, employee bank account) from the salary allocations and generates a pain.001 credit transfer XML through the bank journal ([hr_payslip.py:16](../enterprise/hr_payroll_account_iso20022/models/hr_payslip.py#L16), [_create_sepa_binary](../enterprise/hr_payroll_account_iso20022/wizard/hr_payroll_payment_report_wizard.py#L15)).
- Payments are flagged with SEPA category purpose **SALA** ([account_journal.py:241](../enterprise/account_iso20022/models/account_journal.py#L241)) and priority HIGH for Belgian companies; pain.001.001.09 journals get a persistent per-slip UETR ([hr_payslip.py:19](../enterprise/hr_payroll_account_iso20022/models/hr_payslip.py#L19)).
- Checks: payment date not in the past, employees have named work contacts, journal bank account is an IBAN ([hr_payroll_payment_report_wizard.py:29](../enterprise/hr_payroll_account_iso20022/wizard/hr_payroll_payment_report_wizard.py#L29)).
- SEPA becomes the default export format only for EUR companies ([hr_payslip.py:54](../enterprise/hr_payroll_account_iso20022/models/hr_payslip.py#L54)) — a GEL company keeps CSV, so this module is mostly irrelevant for Georgia except its payroll-dashboard warning listing employees with invalid IBANs ([hr_payroll_dashboard_warning_data.xml:5](../enterprise/hr_payroll_account_iso20022/data/hr_payroll_dashboard_warning_data.xml#L5)).

---

## Cancel, Refund, Set to Draft

- **Cancel** ([action_payslip_cancel](../enterprise/hr_payroll_account/models/hr_payslip.py#L38)) calls `move_id._unlink_or_reverse()` before the base cancel. The account module decides per move ([account_move.py:5458](../addons/account/models/account_move.py#L5458)): deletable (no hash, after lock date, no CABA/exchange links) → reset to draft and **unlink**; protected by restrictive audit trail → set move to **cancel**; otherwise → **reverse** with auto-reconciliation. Only payroll managers can cancel a validated slip ([hr_payslip.py:625](../enterprise/hr_payroll/models/hr_payslip.py#L625)).
- **Set to Draft** exists only on cancelled slips ([hr_payslip_views.xml:82](../enterprise/hr_payroll/views/hr_payslip_views.xml#L82)) and does not touch the move.
- **Refund / Correction** (`refund_sheet` / `correct_sheet`, base module) copies the slip as a `credit_note` with negated lines ([hr_payslip.py:723](../enterprise/hr_payroll/models/hr_payslip.py#L723)). When the refund slip is validated, negative totals naturally book on the opposite sides — unless the company uses **storno** accounting, in which case credit-note slips book negative amounts on the *same* side ([hr_payslip.py:186](../enterprise/hr_payroll_account/models/hr_payslip.py#L186)).
- **Guard:** `action_payslip_done` refuses if any selected slip is already `paid` ([hr_payslip.py:48](../enterprise/hr_payroll_account/models/hr_payslip.py#L48)).

---

## Analytic Distribution

Three layers, first non-empty wins per line ([hr_payslip.py:161](../enterprise/hr_payroll_account/models/hr_payslip.py#L161)):

1. `analytic_distribution` on the **salary rule** (rule-specific costs).
2. `analytic_distribution` on the employee's **hr.version** (contract) — added by this module via `analytic.mixin` ([hr_version.py:6](../enterprise/hr_payroll_account/models/hr_version.py#L6)), editable on the employee payroll tab and contract templates.
3. Nothing.

`project_hr_payroll_account` is UI-only on top of this: it counts hr.versions whose analytic distribution includes the project's account and shows a "Contracts" stat button on the project ([project_project.py:14](../enterprise/project_hr_payroll_account/models/project_project.py#L14)). No accounting logic.

---

## Expenses Reimbursed Through Payslips (`hr_payroll_expense`)

Flow: an employee expense (paid `own_account`, state approved/posted) is flagged **Reimburse In Next Payslip** ([action_report_in_next_payslip](../enterprise/hr_payroll_expense/models/hr_expense.py#L53)). Draft payslip creation (or set-to-draft) auto-links all such expenses of the employee ([_link_expenses_to_payslip](../enterprise/hr_payroll_expense/models/hr_payslip.py#L111)) — but only if the structure has a rule with code **EXPENSES**. The expense total is injected as an *other input* line of type `hr_payroll_expense.expense_other_input` ([_update_expense_input_line_ids](../enterprise/hr_payroll_expense/models/hr_payslip.py#L132)), which the EXPENSES rule turns into a payslip line.

The accounting closure happens at **posting time of the payslip move** ([account_move.py:10](../enterprise/hr_payroll_expense/models/account_move.py#L10)): the expense moves are posted if needed, then the payslip-move line on the EXPENSES rule's debit account is matched and auto-reconciled against the expenses' payable lines, marking the expenses paid — the employee gets one payment (the payslip) covering salary plus expenses. Hard requirements enforced by pre-validation errors and [`_get_expense_rule_account_id_map`](../enterprise/hr_payroll_expense/models/hr_payroll_structure.py#L10): the EXPENSES rule must have a **debit** account of type `liability_payable`. Cancelling the payslip releases the expenses for a future slip ([hr_payslip.py:68](../enterprise/hr_payroll_expense/models/hr_payslip.py#L68)); expenses cannot be pulled out of a validated/paid slip ([hr_expense.py:42](../enterprise/hr_payroll_expense/models/hr_expense.py#L42)). Deleting a payslip move also unlinks/reverses the expense moves ([account_move.py:34](../enterprise/hr_payroll_expense/models/account_move.py#L34)).

---

## Multi-Company

- `account_debit`, `account_credit` on rules and `journal_id` on structures are **company-dependent** — one shared structure can post to different CoAs per company. Configure them logged into each company (or `with_company`).
- Moves are created `sudo()` in the slip's company; `journal_id` is `check_company` ([hr_payslip.py:16](../enterprise/hr_payroll_account/models/hr_payslip.py#L16)).
- `batch_payroll_move_lines` is per company ([res_company.py:10](../enterprise/hr_payroll_account/models/res_company.py#L10)); the chart-template loader force-enables it for BE/CH ([account_chart_template.py:40](../enterprise/hr_payroll_account/models/account_chart_template.py#L40)).

---

## Configuration & Settings

- **Batch Account Move Lines** (Payroll settings → Accounting section) — merges all slips validated together into one move per journal+month with aggregated, anonymized lines. Side effects: per-slip **Pay** button disappears, `employee_move_line` is ignored (no partner, no per-employee lines, no multi-bank split) ([res_config_settings.py:10](../enterprise/hr_payroll_account/models/res_config_settings.py#L10), [hr_payslip_views.xml:31](../enterprise/hr_payroll_account/views/hr_payslip_views.xml#L31)).
- **Salary journal** — per structure (Payroll → Configuration → Structures, Accounting field group). Set its **Default Account** too: it is the adjustment-entry account.
- **Rule accounts / grids** — per rule, "Accounting" tab ([hr_salary_rule_views.xml](../enterprise/hr_payroll_account/views/hr_salary_rule_views.xml)); grids filtered to `applicability = taxes`.
- **Employee bank accounts** — must have `allow_out_payment` (trusted) to pay; the res.partner.bank form warns and auto-links accounts created from the employee form to `employee.bank_account_ids` ([res_partner_bank.py:18](../enterprise/hr_payroll_account/models/res_partner_bank.py#L18)).

### Wiring a Georgian structure safely (checklist)

1. Confirm the `SLR` "Salaries" journal exists per company and set its default account (adjustment target — any imbalance from mis-configured rules lands here; pick a clearing account you monitor).
2. On each structure used, set `journal_id` **per company**.
3. Gross/employer-cost rules: `account_debit` = expense account. Withholding rules (PIT, pension employee part): `account_credit` = the tax/pension payable liability. NET rule: `account_credit` = salaries-payable account with **reconcile = True** and type `liability_current` or `liability_payable`; keep `employee_move_line` on to get per-employee payable lines.
4. Rules that must not shrink the booked NET amount stay unflagged; a rule already inside NET that you book separately (e.g. a benefit-in-kind netting) needs `not_computed_in_net` **plus** its own accounts.
5. Employer-side contributions (pension employer 2%) belong in rules that never enter NET category totals; give them debit expense + credit payable.
6. If the payroll declaration should feed tax report grids, put grids on `debit_tag_ids`/`credit_tag_ids` instead of inventing taxes.
7. Make sure the expense/liability accounts used have **no default taxes** (`account.tax_ids`) unless you really want tax lines on salary moves.

---

## Dependencies

| Requires | Why |
|---|---|
| `hr_payroll` | payslips, rules, structures, batches — the documents being posted |
| `accountant` | full accounting (moves, payments, reconciliation, register wizard) |
| `base_iban` | IBAN validation for employee bank accounts |

| Works With | What It Adds |
|---|---|
| `hr_payroll_account_iso20022` | SEPA/ISO 20022 salary payment files (pain.001) from payslip batches |
| `hr_payroll_expense` | expense reimbursement folded into the payslip, auto-reconciled on posting |
| `project_hr_payroll_account` | "Contracts" counter on projects via analytic distribution |
| `l10n_*_hr_payroll_account` | per-country account/grid presets via `_configure_payroll_account_<code>` |

---

## Gotchas & Non-Obvious Behavior

- **No journal = silent no-move.** A validated slip whose structure lacks a journal is skipped without error — only a dashboard warning flags it beforehand ([hr_payslip.py:64](../enterprise/hr_payroll_account/models/hr_payslip.py#L64)). You can end up with paid-in-HR payslips that never hit the GL.
- **Missing rule accounts don't error — they get "adjusted".** A forgotten credit account shifts its amount into the Adjustment Entry on the journal default account, keeping the move balanced and the mistake invisible. Audit the adjustment line every run.
- **Custom ALW rules need a hard setup blocker.** Because missing rule accounts do not stop validation, the wage/work-log module must verify company-specific debit/credit accounts and journal configuration before payroll compute/confirm; a warning is not enough.
- **Reversal blocks re-posting.** If cancel *reversed* the move (lock date / hash), `move_id` stays on the slip; after Set to Draft and re-validation, `_action_create_account_move` skips the slip because `move_id` is set — no new entry is ever created ([hr_payslip.py:64](../enterprise/hr_payroll_account/models/hr_payslip.py#L64)). Only the unlink path clears `move_id` (m2o set-null).
- **Validating one batch slip can post the whole batch.** `_action_create_account_move` widens to all slips of a run as soon as the run "is ready" (any slip validated or cancelled) ([hr_payslip.py:59](../enterprise/hr_payroll_account/models/hr_payslip.py#L59)).
- **`not_computed_in_net` is accounting-only** and assumes the flagged rule's total is already included in NET; it subtracts `abs(total)` from the NET booking regardless of the rule's sign logic ([hr_payslip.py:174](../enterprise/hr_payroll_account/models/hr_payslip.py#L174)).
- **Account default taxes leak into payroll moves.** Every generated line copies `account.tax_ids` ([hr_payslip.py:163](../enterprise/hr_payroll_account/models/hr_payslip.py#L163)); an expense account with a default purchase tax will create tax lines on posting the salary move.
- **The IBAN check in this module is dead code.** [hr_payroll_payment_report_wizard.py:23](../enterprise/hr_payroll_account/wizard/hr_payroll_payment_report_wizard.py#L23) filters `state == "done"`, a state that no longer exists (v19 states: draft/validated/paid/cancel — base wizard correctly uses `validated`, [hr_payroll_payment_report_wizard.py:86](../enterprise/hr_payroll/wizard/hr_payroll_payment_report_wizard.py#L86)). Invalid IBANs are only caught by the iso20022 dashboard warning, not by the CSV export.
- **Payment date ≠ paid state.** The payment report wizard writes `paid_date` on slips at export time ([hr_payroll_payment_report_wizard.py:90](../enterprise/hr_payroll/wizard/hr_payroll_payment_report_wizard.py#L90)) even though the slips are still `validated`; the `paid` state comes only from register-payment reconciliation or the batch's Mark as Paid.
- **`paid` flips only on full-move reconciliation.** `_reconcile_payments` requires zero residual on *all* lines of the payslip move ([account_payment_register.py:36](../enterprise/hr_payroll_account/wizard/account_payment_register.py#L36)) — a partial payment (e.g. only NET paid, tax payable still open on a reconcilable account) leaves the slip `validated`.
- **Batch mode kills payment automation.** With `batch_payroll_move_lines`, no Pay button, no per-employee lines, no multi-bank split — you pay from the accounting side or via payment files, then mark the run paid manually.
- **Workspace Basis Bank integration widens through shared moves.** It filters selected sendable slips but passes all lines of each selected `move_id` to payment registration. In batch mode a shared move can include employees/slips outside the intended selection. Test subset/mixed-state exports or require per-slip moves for that integration.
- **Multi-bank splits can hard-fail validation.** `compute_salary_allocations` raises `ValidationError` when fixed allocations exceed or undershoot the net ([hr_payslip.py:2212](../enterprise/hr_payroll/models/hr_payslip.py#L2212)).
- **Refund + storno companies** book negatives on the same side instead of swapping ([hr_payslip.py:186](../enterprise/hr_payroll_account/models/hr_payslip.py#L186)) — relevant if the Georgian company ever enables storno.
- **Salary journal is undeletable and must be company-currency** ([account_journal.py:10](../enterprise/hr_payroll_account/models/account_journal.py#L10), [hr_payroll_structure.py:19](../enterprise/hr_payroll_account/models/hr_payroll_structure.py#L19)).
- **EXPENSES rule contract:** code exactly `EXPENSES`, debit account type exactly `liability_payable`, else pre-validation errors block the slip ([hr_payslip.py:42](../enterprise/hr_payroll_expense/models/hr_payslip.py#L42)). Auto-reconciliation silently gives up when more than two accounts are involved ([account_move.py:92](../enterprise/hr_payroll_expense/models/account_move.py#L92)).

---

## Related Docs

- [`INDEX.md`](INDEX.md)
- [`hr_payroll.md`](hr_payroll.md) — the payslip lifecycle this module hooks into (states, compute_sheet, batches)
- [`payroll_wage_types.md`](payroll_wage_types.md) — wage types and the custom work-log plan that pays via salary rules
- [`work_entries.md`](work_entries.md) — how worked days are generated before a slip is computed
- [`hr_employee_versions.md`](hr_employee_versions.md) — hr.version (contract) records that carry the analytic distribution fallback
- [`attendance_work_entry.md`](attendance_work_entry.md), [`resource_calendars.md`](resource_calendars.md) — upstream time sources
- [`analytic_accounting.md`](analytic_accounting.md) — analytic distribution mechanics used by rules/contracts
- [`odoo_tax_account_constraints.md`](odoo_tax_account_constraints.md) — account/journal constraints that also bind payroll moves

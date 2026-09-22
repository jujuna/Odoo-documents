# Tax Returns & Period Locking (`account.return`) — Enterprise

> How Odoo 20 Enterprise turns "file the month's VAT" into a guided workflow: return cards, checks, validation, the closing entry, and the lock dates that freeze the period.
> Complements [`taxes.md`](taxes.md) — that doc covers the closing-entry mechanics and the lock-date family in depth; this one covers the **return lifecycle** around them.
> Georgian specifics (`gec_l10n_ge_tax` DGV return) at the end.
>
> **Verified against Odoo 20 source (2026-09-22).** Odoo 20 reworked this area substantially — see [What changed in Odoo 20](#what-changed-in-odoo-20) before trusting older notes.

---

## Overview

`account.return` (Enterprise [`account_reports`](../enterprise/account_reports/models/account_return.py)) models one filing obligation for one period — "VAT return for June 2026". Cards are auto-generated per periodicity, walk through a state workflow with automated checks, and validation is the moment everything happens at once: the tax closing entry is posted, the return gets `date_lock`, and the company `tax_lock_date` advances to the period end. Community has none of this — no cards, no closing entry, no filing workflow (see [`taxes.md`](taxes.md#the-community--enterprise-split-read-this-first)).

UI: **Accounting → Closing → Tax Returns** ([account_return_views.xml:244](../enterprise/account_reports/views/account_return_views.xml#L244), menu parented on `account.account_closing_menu`).

---

## What changed in Odoo 20

Read this first if you are coming from a 19.0 setup or from the previous version of this doc.

| Area | Odoo 19 | Odoo 20 |
|---|---|---|
| **Closing accounts** | `account.tax.group.tax_payable_account_id` / `tax_receivable_account_id` / `advance_tax_payment_account_id` — one settlement triplet **per tax group** | Fields **removed from `account.tax.group`**. They now live on `account.return.type`, company-dependent ([account_return.py:162](../enterprise/account_reports/models/account_return.py#L162)-[196](../enterprise/account_reports/models/account_return.py#L196)) — one triplet **per return type** |
| Rounding accounts | — | `tax_closing_rounding_profit_account_id` / `..._loss_account_id` on the return type ([account_return.py:95](../enterprise/account_reports/models/account_return.py#L95)) |
| Config error | RedirectWarning pointing at tax groups | RedirectWarning pointing at the **return type form** ([`_ensure_tax_closing_accounts_configured`](../enterprise/account_reports/models/account_return.py#L2025)) |
| `action_validate` | `action_validate(bypass_failing_tests=False)`; passing `True` flipped leftover `anomaly` checks to `reviewed` | `action_validate()` — **no bypass argument, no silent check override**. Unresolved checks simply hide the button ([`_compute_show_submit_button`](../enterprise/account_reports/models/account_return.py#L1322)) |
| Reset | Rolled `tax_lock_date` back to `date_from − 1 day` automatically | **Does not move any lock date.** It refuses with a `UserError` if the tax/hard lock still covers the period — you lower the lock yourself first ([account_return.py:1727](../enterprise/account_reports/models/account_return.py#L1727)) |
| Closing move on reset | reversal / draft flavour | Unreconciled, then `button_draft()` + `unlink()`; payment-reconciliation moves between the payable and receivable accounts are deleted too ([account_return.py:1755](../enterprise/account_reports/models/account_return.py#L1755)-[1806](../enterprise/account_reports/models/account_return.py#L1806)) |
| Return categories | Tax returns only | New `category` field: `account_return` \| `audit` ([account_return.py:62](../enterprise/account_reports/models/account_return.py#L62)), with `audit_status` and `account.audit.account.status` for the audit workflow |
| Amount to pay | — | `period_amount_to_pay` / `total_amount_to_pay` computed from the settlement accounts at validation ([account_return.py:1559](../enterprise/account_reports/models/account_return.py#L1559)-[1560](../enterprise/account_reports/models/account_return.py#L1560)) |
| EC Sales List | generic handling | Dedicated `_generate_ec_sales_returns` + `is_ec_sales_list_return_type` |
| Checks | ad-hoc records | Backed by `account.return.check.template`, with `approver_ids`, `supervisor_id`, `notes`, `cycle_id` and a `file` check type (upload a document) |

**Impact on a 19→20 upgrade:** any custom module that writes `tax_payable_account_id` / `tax_receivable_account_id` on `account.tax.group` will fail on install. `gec_l10n_ge_tax` does exactly that — see [Georgian setup](#georgian-setup-gec_l10n_ge_tax).

---

## Return types and periodicity

`account.return.type` defines the obligation. Key fields ([account_return.py:61](../enterprise/account_reports/models/account_return.py#L61) onward):

| Field | Meaning |
|---|---|
| `category` | `account_return` (a filing) or `audit` (an internal audit cycle). Audit returns skip the whole closing/lock machinery. |
| `report_id` | The `account.report` this return files (e.g. a VAT declaration). Presence of a report drives the richer workflow. |
| `deadline_periodicity` / `default_deadline_periodicity` | Monthly · 2 months · Quarterly · 4 months · Semi-annually · Annually · Fiscal Year. The non-default field is company-dependent; the `default_*` value is the master-data fallback. |
| `deadline_days_delay` / `default_deadline_days_delay` | Days after period end until the filing deadline. `0` means "let the company setting decide". |
| `deadline_start_date` | Anchor for computing period boundaries (fallback 2025-01-01, [account_return.py:849](../enterprise/account_reports/models/account_return.py#L849)). |
| `tax_payable_account_id` · `tax_receivable_account_id` · `advance_tax_payment_account_id` | **New location in 20.** Company-dependent settlement accounts for the closing entry. |
| `tax_closing_rounding_profit_account_id` · `..._loss_account_id` | Where the tax report's rounding difference lands. |

**Periodicity resolution** ([`_get_periodicity`](../enterprise/account_reports/models/account_return.py#L846)): `type.deadline_periodicity` **or** `company.account_return_periodicity`. The company field defaults to **monthly** ([res_company.py:29](../enterprise/account_reports/models/res_company.py#L29)) and is exposed in Accounting Settings; `account_return_reminder_day` (default 7, [res_company.py:36](../enterprise/account_reports/models/res_company.py#L36)) doubles as the deadline fallback (below).

### How cards get generated

[`_try_create_returns_for_fiscal_year`](../enterprise/account_reports/models/account_return.py#L577) walks a **rolling window**, not the whole company history:

- Window: `today − 1 year` … `today` (Odoo 19 ran to `today + 1 year`; 20 stops at today).
- A period is kept only when its computed deadline sits between `company.account_opening_date` and `today + 1 year`.
- Periods that already have a matching return are left alone; mismatched *unlocked, incomplete* returns are deleted and recreated.
- The cron [`_cron_generate_or_refresh_all_returns`](../enterprise/account_reports/models/account_return.py#L440) refreshes everything daily; `_send_submission_reminder` (new in 20) chases due cards.

A **branch with its own VAT number** (different from its parent's) gets its own return cards ([account_return.py:625](../enterprise/account_reports/models/account_return.py#L625)) — relevant for Georgia: branches are not separate VAT payers, so keep branch VAT empty or equal to the parent. [`_can_return_exist`](../enterprise/account_reports/models/account_return.py#L425) is the gate: only the main branch of a same-VAT subtree, or a foreign-VAT fiscal position, may own a return.

**Deadline** ([`_evaluate_deadline`](../enterprise/account_reports/models/account_return.py#L1138)):

```
date_deadline = date_to + (type.deadline_days_delay or company.account_return_reminder_day)
```

So an unset `deadline_days_delay` does **not** mean "due on the period end" — it means "due `account_return_reminder_day` days later" (7 by default). Completed returns stop recomputing it.

---

## State workflow and checks

Each type picks a workflow ([account_return.py:107](../enterprise/account_reports/models/account_return.py#L107)): Reviewed · Reviewed-Submitted · **Reviewed-Submitted-Paid** (tax reports with a `report_id`) · Paid. A generic `state` char routes into the matching selection field.

Each card carries `check_ids` (`account.return.check`, [account_return.py:3296](../enterprise/account_reports/models/account_return.py#L3296)) — automated verifications: draft entries in the period, unreconciled bank lines, bills without attachments, inactive tax tags, overdue receivables/payables, sequence gaps, VIES validity, and so on. Each check carries a `result` from `todo` / `reviewed` / `supervised` / `anomaly` (shared with `account.move`, [account_move.py:60](../addons/account/models/account_move.py#L60)).

New in 20:

- Checks are instantiated from **`account.return.check.template`** records, which also carry a `cycle_id`.
- `type` is `check` or **`file`** — a "upload this document" step, not just a pass/fail.
- `approver_ids` / `supervisor_id` record who signed off. Only an Accounting Administrator can set a supervisor.
- `unresolved_check_count` counts `todo` + `anomaly`. For review-submit workflows the Submit button only appears when that count is **zero** ([account_return.py:1322](../enterprise/account_reports/models/account_return.py#L1322)) — there is no "validate anyway" flag any more.

---

## Validation = closing + lock

[`action_validate()`](../enterprise/account_reports/models/account_return.py#L1493) → [`_proceed_with_locking`](../enterprise/account_reports/models/account_return.py#L1508):

1. **Audit shortcut** — if `return_type_category == 'audit'`, the return goes straight to `reviewed` + completed. None of the steps below run.
2. **Sequential guard** — refuses if an earlier-deadline, non-audit return of the same type is still unlocked and incomplete ([account_return.py:1529](../enterprise/account_reports/models/account_return.py#L1529)): *"You cannot lock this return as there are previous returns that are waiting to be posted."* Periods validate strictly in order.
3. **Carryover** — `_generate_carryover_external_values` freezes the report's carryover values for the period.
4. **Locking attachment** — the filing PDF is generated **only when the workflow has no `submitted` state**; otherwise the export happens at submission instead ([account_return.py:1535](../enterprise/account_reports/models/account_return.py#L1535)-[1537](../enterprise/account_reports/models/account_return.py#L1537)).
5. **Closing entry** — for tax returns, [`_generate_tax_closing_entries`](../enterprise/account_reports/models/account_return.py#L1993) builds and **immediately posts** one move per company in `company_ids`, dated `date_to`, in `company._get_tax_closing_journal()`. See [the closing entry](#the-closing-entry-in-odoo-20) below.
6. **Kill exceptions** — every active `account.lock_exception` on `tax_lock_date` for those companies is revoked ([account_return.py:1543](../enterprise/account_reports/models/account_return.py#L1543)-[1547](../enterprise/account_reports/models/account_return.py#L1547)).
7. **Lock** — the company's **`tax_lock_date` is set to `date_to`** when the report's country matches the fiscal country and the lock is not already past it ([account_return.py:1555](../enterprise/account_reports/models/account_return.py#L1555)); default external values are seeded for the next period.
8. **Amounts** — `period_amount_to_pay` and `total_amount_to_pay` are computed from the settlement accounts, so the card can show what is still owed.
9. `date_lock` is set to **today** (the day you filed), not to `date_to` ([account_return.py:1562](../enterprise/account_reports/models/account_return.py#L1562)), and the state becomes `reviewed`.

After that the card moves through Submit (mark as filed with the authority) and Pay (register the payment against the closing entry via `account.return.payment.wizard`), ending `is_completed`.

### The closing entry in Odoo 20

[`_compute_tax_closing_entry`](../enterprise/account_reports/models/account_return.py#L2048) runs one SQL pass over the report's move lines, keeping only repartition lines with `use_in_tax_closing`, grouped by tax / tax group / account. For each tax account it emits a line that zeroes the period balance, then books the net on **one settlement triplet resolved from the return type** ([`_get_tax_closing_accounts`](../enterprise/account_reports/models/account_return.py#L2224)):

```
(advance_tax_payment_account_id, tax_receivable_account_id, tax_payable_account_id)
   ← account.return.type, with_company(company)
```

Because the triplet is per return type rather than per tax group, **every tax group on the same return now consolidates into a single payable/receivable line**. In Odoo 19 two tax groups with different settlement accounts produced two counterpart lines; in 20 they cannot.

Missing payable/receivable accounts hard-stop with a `RedirectWarning` onto the return-type form ([account_return.py:2025](../enterprise/account_reports/models/account_return.py#L2025)). The advance-payment account, if set, is drained first (`_get_carryover_accounts_to_balance`). An entirely empty tax report still produces two 0-valued lines so the move exists.

---

## Reopening a validated return

[`action_reset_tax_return_common`](../enterprise/account_reports/models/account_return.py#L1693) — **Accounting Administrator only**:

1. Refused if a *later* return of the same type is already locked ([account_return.py:1709](../enterprise/account_reports/models/account_return.py#L1709)) — unwind in reverse order only.
2. **Refused if the period is still tax- or hard-locked** ([account_return.py:1727](../enterprise/account_reports/models/account_return.py#L1727)): *"The operation is refused as it would impact an already issued tax statement. Please change the following lock dates to proceed: …"*
3. Refused if carryover values it must delete would impact an already-locked later period.
4. Deletes the period's carryover external values and zeroes the amounts to pay.
5. Unreconciles the closing move, deletes any two-line reconciliation move that sits between the payable and receivable accounts, then `_reset_common` drafts and **unlinks** the closing move, clears `date_lock`, `date_submission`, attachments and check approvals.

> **This is the biggest operational change in 20.** Validation still *sets* `tax_lock_date`, but reset no longer *unsets* it. Reopening June therefore takes two steps: lower `tax_lock_date` to 2026-05-31 (Lock Dates wizard, or grant yourself a `tax_lock_date` lock exception), then reset the return. Forget the first step and you get the "already issued tax statement" error with no hint that the lock came from your own earlier validation.

---

## Which lock date does what

Detailed treatment: [`taxes.md → Tax Lock Dates`](taxes.md#tax-lock-dates). Operational summary:

| Lock (`res.company`) | Set by | Blocks |
|---|---|---|
| `tax_lock_date` ([company.py:84](../addons/account/models/company.py#L84)) | **Automatically** by validating a tax return (above); manual via Lock Dates wizard | Posted-entry changes to lines that *affect the tax report* (`tax_ids` / `tax_line_id` / tax tags) dated ≤ lock ([`_check_tax_lock_date`](../addons/account/models/account_move_line.py#L1882)) |
| `fiscalyear_lock_date` ([company.py:79](../addons/account/models/company.py#L79)) | Manual (month-end/year-end close) | Everything dated ≤ lock, all journals |
| `sale_lock_date` / `purchase_lock_date` ([company.py:90](../addons/account/models/company.py#L90)) | Manual | Sale / purchase journals only — lets you close AR before AP |
| `hard_lock_date` ([company.py:100](../addons/account/models/company.py#L100)) | Manual, deliberate | Everything, **irreversible**, no exceptions — year-end after audit |

The four soft locks accept per-user, audited `account.lock_exception` records; effective dates are the computed `user_*_lock_date` fields ([company.py:111](../addons/account/models/company.py#L111)-[115](../addons/account/models/company.py#L115)), resolved by [`_get_user_lock_date`](../addons/account/models/company.py#L749), which walks `parent_ids` and takes the **strictest** lock in the branch chain. Violations are reported by [`_get_lock_date_violations`](../addons/account/models/company.py#L817). UI: Accounting → Lock Dates.

**Month-close recipe:** validate the tax return (tax lock moves automatically) → optionally set `fiscalyear_lock_date` to the same month-end once AR/AP/bank are done → leave `hard_lock_date` for year-end.

---

## Georgian setup (`gec_l10n_ge_tax`)

> **Module path:** [`custom_addons/gec_odoo_modules/gec_l10n_ge_tax/`](../custom_addons/gec_odoo_modules/gec_l10n_ge_tax/) (an identical copy also sits under `custom_addons/odoo_taxes/`). The manifest still declares `'version': '19.0.1.1.0'` and `custom_addons` is **not in `odoo20/odoo.conf`'s `addons_path`** — none of this is loaded in the Odoo 20 instance yet.

**Return type** ([dgv_tax_report.xml:283](../custom_addons/gec_odoo_modules/gec_l10n_ge_tax/data/dgv_tax_report.xml#L283)): `report_id` = DGV report, `country_id` = GE, `default_deadline_periodicity = monthly`, `default_deadline_days_delay = 15` → deadline the 15th of the following month, matching the Georgian monthly VAT calendar. (Periodicity *is* pinned on the type now; the older note saying it drifts to the company setting is obsolete.)

**No closing entry.** The module overrides `_generate_tax_closing_entries` to return early for the GE VAT return ([account_return.py:7](../custom_addons/gec_odoo_modules/gec_l10n_ge_tax/models/account_return.py#L7)) — accountant decision 2026-07-06: 3330/3340 keep raw running balances and the budget is settled per declaration instead. Validation still runs the checks, locks the period and advances `tax_lock_date`; it just posts nothing.

**Georgian filing calendar** (monthly, all by the **15th** of the following month): VAT declaration + payment; withholding declaration for amounts withheld on payment; CIT declaration for months with distributions; Form III-19 reverse-charge VAT for non-VAT-registered payers.

### Two blockers before this module runs on Odoo 20

1. **Tax-group settlement fields are gone.** [`account_chart_template.py:14`](../custom_addons/gec_odoo_modules/gec_l10n_ge_tax/models/account_chart_template.py#L14) and [`:358`](../custom_addons/gec_odoo_modules/gec_l10n_ge_tax/models/account_chart_template.py#L358) write `tax_payable_account_id` / `tax_receivable_account_id` on `account.tax.group` (all nine GE groups → account 3399). Those fields no longer exist on that model in Odoo 20. The template load will raise. The fix is to drop the tax-group writes and — only if a closing entry is ever wanted — set the pair on the `ge_vat_return_type` record instead. Given the closing override above, the 3399 settlement config is dead weight either way.
2. **`l10n_ge` now ships in core.** Odoo 20 added [`addons/l10n_ge`](../addons/l10n_ge/) ("Georgia - Accounting": GE chart of accounts, tax groups, taxes, fiscal positions, VAT report) and it registers `@template('ge')` ([template_ge.py:54](../addons/l10n_ge/models/template_ge.py#L54)) — the same template code `gec_localization` uses ([template_ge.py:9](../custom_addons/gec_odoo_modules/gec_localization/models/template_ge.py#L9)). Decide which chart wins before installing either: keeping both installed merges two account sets under one template code.

`use_in_tax_closing = False` is still forced on the 1% turnover tax and the 15 WHT taxes ([account_chart_template.py:350](../custom_addons/gec_odoo_modules/gec_l10n_ge_tax/models/account_chart_template.py#L350)), which remains correct — those are settled per the withholding declaration, not a VAT sweep.

---

## Gotchas

- **Validation posts immediately.** Where a closing entry is generated at all, it is created *and posted* inside validation — there is no draft review step.
- **Reset does not unlock.** Validation sets `tax_lock_date`; reset leaves it. Lower the lock first or the reset is refused. (Odoo 19 rolled it back for you.)
- **No "validate anyway".** The `bypass_failing_tests` argument is gone. Resolve or explicitly review every check, or the button stays hidden.
- **Strict ordering both ways.** Can't validate June before May; can't reset May while June is locked.
- **Tax lock ≠ full lock.** A non-tax reclassification dated in a tax-locked month still posts; only tax-relevant lines are frozen. Use `fiscalyear_lock_date` for a true month close.
- **Exceptions are auto-revoked.** Validating a return revokes active tax-lock exceptions — a colleague's temporary unlock dies the moment you file.
- **One settlement line per return.** Tax groups no longer carry their own payable/receivable accounts, so a return that used to split settlement across groups now consolidates.
- **`date_lock` is the filing date, not the period end.** It records when you validated; the period boundary is `date_to`.
- **Report total ≠ closing total** when repartition lines feed the grid but are excluded from closing (`use_in_tax_closing = False`) — exactly the GE WHT design.

---

## Related Docs

- [`INDEX.md`](INDEX.md)
- [`taxes.md`](taxes.md) — closing-entry mechanics and the lock-date family in depth
- [`gec_l10n_ge_tax.md`](gec_l10n_ge_tax.md) — the Georgian tax module itself

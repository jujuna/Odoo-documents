# Tax Returns & Period Locking (`account.return`) — Enterprise

> How Odoo 19 Enterprise turns "file the month's VAT" into a guided workflow: return cards, checks, validation, the closing entry, and the lock dates that freeze the period.
> Complements [`taxes.md`](taxes.md) — that doc covers the closing-entry mechanics and the lock-date family in depth; this one covers the **return lifecycle** around them.
> Georgian specifics (`gec_l10n_ge_tax` DGV return) at the end.

---

## Overview

`account.return` (Enterprise [`account_reports`](../enterprise/account_reports/models/account_return.py)) models one filing obligation for one period — "VAT return for June 2026". Cards are auto-generated per periodicity, walk through a state workflow with automated checks, and validation is the moment everything happens at once: the tax closing entry is posted, the return gets `date_lock`, and the company `tax_lock_date` advances to the period end. Community has none of this — no cards, no closing entry, no filing workflow (see [`taxes.md`](taxes.md#the-community--enterprise-split-read-this-first)).

UI: **Accounting → Closing → Tax Returns** (in some views "Reporting → Tax Return").

## Return types and periodicity

`account.return.type` defines the obligation. Key fields ([account_return.py:96](../enterprise/account_reports/models/account_return.py#L96)):

| Field | Meaning |
|---|---|
| `report_id` | The `account.report` this return files (e.g. a VAT declaration). Presence of a report drives the richer workflow. |
| `deadline_periodicity` / `default_deadline_periodicity` | Monthly / trimester / year… The non-default field is company-dependent; it falls back to the `default_*` value ([account_return.py:130](../enterprise/account_reports/models/account_return.py#L130)). |
| `deadline_days_delay` / `default_deadline_days_delay` | Days after period end until the filing deadline. |
| `deadline_start_date` | Anchor for computing period boundaries (fallback 2025-01-01, [account_return.py:541](../enterprise/account_reports/models/account_return.py#L541)). |

**Periodicity resolution** ([account_return.py:534](../enterprise/account_reports/models/account_return.py#L534)): `type.deadline_periodicity` **or** `company.account_return_periodicity`. The company field defaults to **monthly** ([res_company.py:20](../enterprise/account_reports/models/res_company.py#L20)) and is exposed in Accounting Settings ("Periodicity"); `account_return_reminder_day` (default 7) shifts when the card demands attention.

Cards are generated from the company opening date forward, skipping periods that already have a locked/completed return ([account_return.py:385](../enterprise/account_reports/models/account_return.py#L385)). A **branch with its own VAT number** (different from the parent's) gets its own return cards ([account_return.py:346](../enterprise/account_reports/models/account_return.py#L346)) — relevant for Georgia: branches are not separate VAT payers, so keep branch VAT empty/equal to the parent.

`date_deadline` = period end + `deadline_days_delay` ([account_return.py:835](../enterprise/account_reports/models/account_return.py#L835)); completed returns stop recomputing it.

## State workflow and checks

Each type picks a workflow ([account_return.py:82](../enterprise/account_reports/models/account_return.py#L82)): Review · Review-Submit · **Review-Submit-Pay** (tax reports with a `report_id`) · Pay. A generic `state` char routes into the matching selection field ([account_return.py:641](../enterprise/account_reports/models/account_return.py#L641), [902](../enterprise/account_reports/models/account_return.py#L902)).

Each card carries `check_ids` (`account.return.check`) — automated verifications (draft entries in period, unreconciled bank lines, report anomalies…). Unresolved checks are counted against the card; validating marks remaining `anomaly` results as reviewed ([account_return.py:1176](../enterprise/account_reports/models/account_return.py#L1176)).

## Validation = closing + lock

`action_validate(bypass_failing_tests)` ([account_return.py:1155](../enterprise/account_reports/models/account_return.py#L1155)) → `_proceed_with_locking` ([account_return.py:1180](../enterprise/account_reports/models/account_return.py#L1180)):

1. **Sequential guard** — refuses if an earlier-deadline return of the same type is still unposted ([account_return.py:1194](../enterprise/account_reports/models/account_return.py#L1194)): *"You cannot lock this return as there are previous returns that are waiting to be posted."* Periods validate strictly in order.
2. **Closing entry** — for tax returns, `_generate_tax_closing_entries` builds and **immediately posts** one move per company, dated `date_to`: it zeroes each VAT account (only repartition lines with `use_in_tax_closing`) and books the net on the tax group's payable/receivable account. Full mechanics + worked example in [`taxes.md`](taxes.md#from-report-to-closing-entry). Missing tax-group accounts hard-stop with a RedirectWarning.
3. **Lock** — the return gets `date_lock`; the company's **`tax_lock_date` is set to `date_to`** if it isn't already past it, and active per-user tax-lock exceptions are deactivated ([account_return.py:1218](../enterprise/account_reports/models/account_return.py#L1218)-[1228](../enterprise/account_reports/models/account_return.py#L1228)).
4. Locking attachments (the filing PDF/export) are generated ([account_return.py:1209](../enterprise/account_reports/models/account_return.py#L1209)).

After that the card moves through Submit (mark as filed with the authority) and Pay (register the payment against the closing entry), ending `is_completed`.

## Reopening a validated return

`action_reset_tax_return_common` ([account_return.py:1378](../enterprise/account_reports/models/account_return.py#L1378)) — **Accounting Administrator only**:

- Refused if a *later* return of the same type is already locked (unwind in reverse order only).
- Refused if carryover values it must delete would impact an already-locked later period.
- Deletes the period's carryover external values, then **rolls `tax_lock_date` back to `date_from − 1 day`** and clears `date_lock`.

So reopening June rolls the company tax lock back to May 31 — July stays open. The closing entry itself is handled via the reset flow (reversal/draft depends on the return flavor); re-validation regenerates it.

## Which lock date does what

Detailed treatment: [`taxes.md → Tax Lock Dates`](taxes.md#tax-lock-dates). Operational summary:

| Lock (`res.company`) | Set by | Blocks |
|---|---|---|
| `tax_lock_date` | **Automatically** by validating a tax return (above); manual via Lock Dates wizard | Posted-entry changes to lines that *affect the tax report* (`tax_ids` / `tax_line_id` / tax tags) dated ≤ lock ([account_move_line.py:1389](../addons/account/models/account_move_line.py#L1389)) |
| `fiscalyear_lock_date` | Manual (month-end/year-end close) | Everything dated ≤ lock, all journals |
| `sale_lock_date` / `purchase_lock_date` | Manual | Sale / purchase journals only — lets you close AR before AP |
| `hard_lock_date` | Manual, deliberate | Everything, **irreversible**, no exceptions — year-end after audit |

The four soft locks accept per-user, audited `account.lock_exception` records; effective dates are the computed `user_*_lock_date` fields, and branches inherit the strictest parent lock ([company.py:109](../addons/account/models/company.py#L109)). UI: Accounting → Lock Dates.

**Month-close recipe:** validate the tax return (tax lock moves automatically) → optionally set `fiscalyear_lock_date` to the same month-end once AR/AP/bank are done → leave `hard_lock_date` for year-end.

## Georgian setup (`gec_l10n_ge_tax`)

- Return type **"VAT (DGV)"** ([dgv_tax_report.xml](../custom_addons/gec_extra_modules/gec_l10n_ge_tax/data/dgv_tax_report.xml)): `report_id` = DGV report, country GE, `default_deadline_days_delay = 15` → deadline the 15th of the following month, matching the Georgian monthly VAT calendar. Periodicity is **not pinned** on the type — it falls back to the company setting, whose default is monthly; pin `default_deadline_periodicity = 'monthly'` on the type to make it drift-proof.
- Closing config: every GE tax group settles on **3399** (unified budget settlement); WHT and small-biz-1% repartition lines carry `use_in_tax_closing = False`, so validation sweeps only 3330/3340/3343/3344 and never touches 3310.02/3320 balances (those are paid per the withholding declaration, not the VAT closing).
- Georgian filing calendar (monthly, all by the **15th** of the following month): VAT declaration + payment; withholding declaration for amounts withheld on payment; CIT declaration for months with distributions; Form III-19 reverse-charge VAT for non-VAT-registered payers.
- Status caveat (2026-07): the DGV report layout is a placeholder (not filing-ready) and the closing config was fixed in code on 2026-07-03 but still needs `-u gec_l10n_ge_tax` + the acceptance test before the first real validation — see the module's [ANALYSIS_AND_FIXES.md](../custom_addons/gec_extra_modules/gec_l10n_ge_tax/ANALYSIS_AND_FIXES.md).

## Gotchas

- **Validation posts immediately.** The closing entry is created *and posted* inside validation — there is no draft review step.
- **Strict ordering both ways.** Can't validate June before May; can't reopen May while June is locked.
- **Tax lock ≠ full lock.** A non-tax reclassification dated in a tax-locked month still posts; only tax-relevant lines are frozen. Use `fiscalyear_lock_date` for a true month close.
- **Exceptions are per-user and auto-revoked.** Validating a return deactivates active tax-lock exceptions — a colleague's temporary unlock dies the moment you file.
- **Report total ≠ closing total** when repartition lines feed the grid but are excluded from closing (`use_in_tax_closing = False`) — exactly the GE WHT design.

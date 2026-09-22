# Deferred Expenses and Revenue — Odoo 20

> Reviewed against the local source on 2026-09-22. Generation is in [`account_accountant`](../enterprise/account_accountant/); reports and grouped generation are in [`account_reports`](../enterprise/account_reports/).
> This documents software behavior and illustrative entries. Earlier database-specific examples and statements about statutory tax treatment have not been treated as evidence of current behavior.
> For a customer-invoice walkthrough, see [Deferred Revenue](deferred_revenue.md).

## What Deferral Does

Deferral moves an expense or revenue from the invoice's accounting date into configured recognition periods. It operates on **journal-item balances**, not payment receipts. A bill can be deferred before it is paid, and a customer invoice can be deferred before cash is collected.

Example: a 1,200 GEL annual subscription bill uses an expense account. With monthly recognition for January 1–December 31, Odoo can reverse the initial expense into a holding asset and recognize 100 GEL expense each month.

| Step | Expense deferral | Revenue deferral |
|---|---|---|
| Original invoice/bill | DR Expense / CR Payable | DR Receivable / CR Revenue |
| Initial reclassification | DR Holding asset / CR Expense | DR Revenue / CR Holding liability |
| Recognition | **DR Expense / CR Holding asset** | **DR Holding liability / CR Revenue** |

The monthly expense recognition direction above corrects the reversed debit/credit explanation in the former revenue guide. Tax and payment entries are separate from this simplified example.

## Configuration: Five Settings Per Side

Sources: [`res_company.py`](../enterprise/account_accountant/models/res_company.py), [`settings view`](../enterprise/account_accountant/views/res_config_settings_views.xml).

| Purpose | Expense field | Revenue field |
|---|---|---|
| Journal | `deferred_expense_journal_id` | `deferred_revenue_journal_id` |
| Company default holding account | `deferred_expense_account_id` | `deferred_revenue_account_id` |
| Generation mode | `generate_deferred_expense_entries_method` | `generate_deferred_revenue_entries_method` |
| Amount calculation | `deferred_expense_amount_computation_method` | `deferred_revenue_amount_computation_method` |
| **Periodicity** | `deferred_expense_periodicity` | `deferred_revenue_periodicity` |

Generation defaults to `on_validation`; the alternative is `manual` (**Manually & Grouped**). Computation defaults to `month`; alternatives are `day` and `full_months`. Periodicity defaults to `month` and also supports `year`. It is displayed for on-validation mode.

The Settings UI selects active general journals, asset-current/prepayment holding accounts for expenses, and current-liability holding accounts for revenue. These are UI domains; the company fields themselves do not contain a universal Python constraint enforcing those exact account types.

### Per-Account Deferral Settings

[`account.account`](../enterprise/account_accountant/models/account_account.py) adds:

- `is_deferred`: **Deferred** flag. The invoice-line view makes the deferred start field required when this is enabled.
- `deferred_account_id`: an account-specific holding account, preferred over the company's default during both individual and grouped generation.

The account form exposes these fields for `expense`, `expense_other`, `income` and `income_other`; its holding-account domain depends on the source account type. This UI visibility is narrower than every account the generation engine can process. See [`account_account_views.xml`](../enterprise/account_accountant/views/account_account_views.xml).

## Eligible Source Lines and Dates

[`_has_deferred_compatible_account()`](../enterprise/account_accountant/models/account_move.py) accepts:

| Source document | Financial-account internal group |
|---|---|
| Purchase invoice/refund/receipt | expense |
| Sales invoice/refund/receipt | income |
| Miscellaneous journal entry | expense or income |

`deferred_start_date` and `deferred_end_date` are inclusive. **The line's end date does not have to be month-end.** The constraint rejects a start without an end and a start later than the end. The abnormal-date warning catches some likely off-by-one ranges; it does not prohibit all partial months.

Onchange behavior fills a missing opposite date with the date just entered and clears dates incompatible with the account/document. Separately, the stored start-date compute can fill an absent start from the invoice date when an end date exists. Consequently “enter an end date and the start always becomes invoice date” is not a reliable description of every UI/ORM path. Check both dates explicitly.

The invoice form's current XML presents deferred dates alongside account information and also defines optional/hidden fields; journal items use a **Deferred Date** date-range widget. Do not rely on the old instruction that two independently visible Start/End columns always appear by default. See [`account_move_views.xml`](../enterprise/account_accountant/views/account_move_views.xml).

## Walkthrough: Annual Vendor Bill

Assumptions: 1,200 GEL company-currency balance, dates January 1–December 31, `month` calculation, `month` periodicity, on-validation mode, no taxes in this illustration.

1. Configure the expense deferral journal and default/per-account holding account.
2. Enter the bill on its normal expense account, with both deferred dates.
3. Set analytic distribution if this cost needs analytic reporting.
4. Post the bill and open its generated deferred entries.
5. Review entry dates and amounts; due entries can post immediately and future entries remain scheduled.

| Entry | Date | Debit | Credit |
|---|---|---|---|
| Bill | January 1 | Expense 1,200 | Payable 1,200 |
| Initial deferral | Bill accounting date | Holding asset 1,200 | Expense 1,200 |
| First recognition | January 31 | Expense 100 | Holding asset 100 |
| Later recognition | Each applicable period end | Expense 100 | Holding asset 100 |

After January's recognition, the holding asset is 1,100 and recognized expense is 100. At completion, the holding amount for this example is zero. The bill's payment status is independent.

## On-Validation Generation

Source: [`account_move.py`, `_post()` and `_generate_deferred_entries()`](../enterprise/account_accountant/models/account_move.py).

The override calls base posting, then requests generation for on-validation moves with deferred starts. `_generate_deferred_entries()` returns unless the source is actually **posted**, so a future invoice merely scheduled by soft posting does not immediately generate its deferrals.

For each eligible source line it:

1. Resolves expense or revenue settings and requires a deferred journal.
2. Builds the configured periods and skips unnecessary deferrals.
3. Resolves `line.account_id.deferred_account_id` before the company fallback.
4. Creates an initial reclassification at the source move's **accounting date**.
5. Creates one recognition entry per retained period, dated at that period's end (clipped to the line end date).
6. Links all generated moves through `deferred_original_move_ids`, adds their journal items after that relation exists, removes zero-total recognition moves and calls `_post(soft=True)`.

Dates entirely within the same accounting month can be skipped because reversing and recognizing would cancel within that month. `_get_deferred_periods()` also skips a single period whose start month equals the source accounting month; this condition applies to yearly periodicity as well. Full-month calculation has additional short-period skip behavior. Do not assume every line with dates creates an initial reversal plus a fixed number of monthly entries.

The line helper carries analytic distribution and product/category data; generation also supplies partner and product values. These statements refer to individual generation, not a guarantee that grouped entries preserve each original partner/product separately.

### Periodicity Selection Caveat

The local `_get_deferred_entries_periodicity()` uses `is_outbound()`, not the source account's income/expense group. Consequently it chooses:

| Move type | Selected periodicity setting |
|---|---|
| Vendor bill / purchase receipt | Expense |
| Customer invoice / sales receipt | Revenue |
| Customer credit note (`out_refund`) | **Expense** |
| Vendor refund (`in_refund`) | **Revenue** |
| Miscellaneous entry | Revenue |

This differs from generation-mode selection, which checks purchase/sales documents and the deferred account groups in miscellaneous entries. With mixed expense/income miscellaneous lines and different generation modes, Odoo raises an error and asks for separate entries. These are current source behaviors to verify when choosing different settings for the two sides.

## Calculation Methods

Sources: `_get_deferred_diff_dates()`, `_get_deferred_period_amount()`, `_get_deferred_periods()` in [`account_move.py`](../enterprise/account_accountant/models/account_move.py).

| Method | Calculation |
|---|---|
| `day` | Actual elapsed days divided by total covered days |
| `month` | 30-day-month difference, with month-end normalization; full calendar months have equal weight |
| `full_months` | Resets calculation boundaries to the first of their month, after converting inclusive ends to exclusive boundaries |

Full Months does **not** give every touched month an equal full share. A partial terminal month can receive zero; zero-total recognition moves are then deleted.

### Verified Arithmetic Example

For 900 GEL, April 15–June 14, with monthly periodicity:

| Calculation | April | May | June |
|---|---|---|---|
| Months | 240 | 450 | 210 |
| Full Months | 450 | 450 | 0 |

The 30-day calculation weights April as 16/30 and June as 14/30, so the old 225/450/225 example was inaccurate. These values were checked by executing the two pure calculation methods extracted from this checkout, without loading an Odoo database.

For 900 GEL, April 1–June 30, day-based calculation uses 91 days: April and June each have 30, May 31. Amounts are approximately 296.70, 306.59 and a final residual of 296.71 at two-decimal rounding.

Individual generation forces the last amount to the remaining balance to absorb accumulated rounding. The implementation subtracts `line.currency_id.round(balance)` from that remaining balance even though the input is company-currency `line.balance`; inspect differing currency precisions when diagnosing a rounding edge case rather than assuming a universal precision rule.

### Yearly Periodicity

Yearly periods follow `company.compute_fiscalyear_dates()`, not necessarily January–December. The first/last periods are clipped to the deferral range. Amount-computation method and periodicity are independent: yearly entries can still use day, month or full-month allocation math.

## Manually and Grouped

Sources: [`account_deferred_reports.py`, `_get_moves_to_defer()` / `_generate_deferral_entry()`](../enterprise/account_reports/models/account_deferred_reports.py).

In manual mode, posting does not create the individual recognition schedule. Open the relevant Deferred Expenses/Revenues report, review the selected period and use **Generate entry**.

The selected **report end must be the last day of a month**. This is the month-end restriction that the old documents incorrectly applied to every invoice line. Generation uses posted originals only and rejects a locked period.

It creates a grouped adjustment at report end to leave only the recognized-to-date amount on the original income/expense accounts, with the remainder on holding accounts. It then creates the opposite entry dated the next day. Both are passed to `_post(soft=True)`; due entries may already be posted when the action returns. “Generate, then manually post both” is not the actual unconditional workflow.

For a 1,200 expense of which 100 should remain recognized at January end, the net grouped adjustment is DR Holding 1,100 / CR Expense 1,100, reversed February 1. At the next month-end, a new adjustment establishes the then-current deferred balance. This is a period-end adjustment/reversal process, not the same set of individual monthly entries as on-validation mode.

Original-account grouping defaults to account; holding lines group by resolved `deferred_account_id`. Analytic distributions are weighted from source balances. Grouped entries do not retain a distinct partner/product trace on every original amount; the source-move relation provides the audit path.

**Local source discrepancy:** the report handler's `_get_deferred_lines()` passes the boolean `is_reverse` to `_get_deferred_amounts_by_line()` as `deferred_type`. That helper selects the expense calculation method only when this argument equals the string `"expense"`; a boolean therefore selects the **revenue** calculation method for grouped expenses too. Report display passes the proper expense/revenue string. Consequently, different expense and revenue calculation settings can make a grouped expense adjustment disagree with the displayed expense allocation. This follows from the source call chain; it has not been reproduced in a database. Individual generation passes the correct string.

Already-generated filtering checks for linked entries at the report end that are posted or future scheduled (`auto_post = at_date`). The report distinguishes never-generated, partially generated and fully generated states. Existing entries do not imply that every newly added eligible original has been included.

## Deferred Reports

The report handlers are `account.deferred.expense.report.handler` and `account.deferred.revenue.report.handler`. Menu actions live under Accounting's Review/Regularization Entries hierarchy. Sources: [`handler`](../enterprise/account_reports/models/account_deferred_reports.py), [`menus`](../enterprise/account_reports/data/menuitems.xml).

| Column | Meaning |
|---|---|
| Total | Full amount in the selected eligible source population |
| Not Started | Deferral starts after the viewed end |
| Before | Calculated allocation before the first viewed period |
| Selected period columns | Allocation within each viewed period |
| Recognized | Calculated cumulative allocation through viewed end |
| **≤ 12 Months** | Future portion within the next 12 months |
| **> 12 Months** | Remaining future portion beyond that boundary |

The previous single “Later” column is now split. Report allocations are calculated from original line dates/balances; a recognized column is not by itself proof that every scheduled recognition move posted successfully.

The report excludes a line as fully inside the selected period only when **both deferral endpoints and the original move's accounting date** are inside it. A full-year report can therefore hide a deferral entirely contained and booked in that year; selecting a narrower period is useful, but is not a universal cure for an empty report.

### Generation Versus Report Account Filters

Generation accepts expense/income internal groups. The expense report explicitly lists `expense`, `expense_depreciation`, `expense_direct_cost`; the revenue report lists `income`, `income_other`. Thus **`expense_other` can be generated but is absent from the expense report's explicit filter**, even though the account form exposes deferral settings for it. This is a source discrepancy, not a claim that such a line cannot generate entries.

The handler caches fetched original lines within the transaction. Report grouping and displayed allocations should not be described as a direct sum of all posted deferral entries.

## Taxes, Currency and Analytics

### Tax Dates Are Conditional

[`account_tax.py`](../enterprise/account_accountant/models/account_tax.py) carries deferred dates into tax grouping only for compatible source lines with both dates and a repartition line where **`use_in_tax_closing` is false**. Tax-closing repartition lines do not inherit those dates through that path. Non-deductible/expense allocations can therefore participate in deferral when otherwise eligible.

Generated deferral moves suppress automatic recomputation of account default taxes through `_get_computed_taxes()`. This explains software behavior; it does not establish the legal VAT reporting/deductibility date for every jurisdiction or cash-basis configuration. The blanket “VAT is never deferred and always reported on invoice date” statement is too broad.

### Currency

Recognition uses the source journal item's `balance`, in company currency. It does not revalue the source invoice at each recognition date. Payment-related exchange differences remain a separate process. See [Currency Exchange and Transit](currency_exchange_transit.md).

### Analytic Distribution and Odoo 20 Budgets

Individual deferral journal items carry the original distribution, including both the expense/revenue and holding sides. Posting creates analytic amounts with the usual **`amount = -balance`** sign. The old guide reversed those analytic signs and omitted holding-side effects.

For a 1,200 expense and 100 recognition, with matching dates/companies/analytic dimensions:

| Posting | Analytic amount | Expense-budget contribution if holding is `asset_current` |
|---|---|---|
| Bill expense debit | -1,200 | +1,200 |
| Initial expense credit | +1,200 | -1,200 |
| Initial holding debit | -1,200 | +1,200 |
| Recognition expense debit | -100 | +100 |
| Recognition holding credit | +100 | -100 |

Odoo 20 budgets include `asset_current`, so the initial net consumption in this example is **1,200**, and the later two-sided recognition has net zero contribution. Deferral does not automatically spread expense-budget consumption in the same way as the P&L.

If the holding account is **`asset_prepayments`**, it is not among the budget report's explicit eligible asset types. With that account type, the expense-only contributions can cancel at initial deferral and appear gradually on recognition. Revenue holding liabilities are also excluded, so the usual revenue-budget effect follows the income side. Account type and actual matches determine the result. See [Analytic Budget](analytic_budget.md) and [`budget_report.py`](../enterprise/account_budget/reports/budget_report.py).

## Resetting, Editing and Credit Notes

Source: [`account_move.py`, `button_draft()`, `unlink()`, line `write()` / `copy_data()`](../enterprise/account_accountant/models/account_move.py).

- Reset is blocked when **any generated deferral is linked to more than one original move**. The check is relational, not simply “all manual mode invoices are blocked.”
- Otherwise generated moves are processed with `_unlink_or_reverse()`. Depending on whether deletion is allowed and audit-trail protection applies, they can be deleted, canceled or reversed. Posted does not automatically mean reversed. Reversal accounting dates can be adjusted.
- Changing the account of an already-deferred line with both dates is blocked. Inspect/reset the linked deferrals before editing; changing dates alone should not be assumed to rebuild a posted schedule automatically.
- Deferred date fields are `copy=False`, but reversal copying explicitly preserves them when `move_reverse_cancel` is in context. Standard credit-note behavior depends on that reversal path and the actual copied dates/amounts.
- Refunds reverse the economic signs. They do not inherently know a contract's termination date or choose the correct remaining recognition period; review the credit note and its generated schedule, especially the periodicity selection caveat above.

## Automatic Posting and Failures

The daily [`service_cron.xml`](../addons/account/data/service_cron.xml) calls [`_autopost_draft_entries()`](../addons/account/models/account_move.py). It selects draft moves dated through today with `auto_post != no`. The shipped next-call expression initializes a 02:00 timestamp; the installed schedule/server timezone determines actual execution, not a guaranteed 02:00 local posting in every database.

Future deferrals use `auto_post = at_date`. Due entries are normally posted by the cron, and missed runs can catch up later. After a batch `UserError`, the cron retries individually; for a failing move it posts the error message and sets **`auto_post = no`**. Fixing configuration later does not by itself re-enable its automatic attempts. Review the chatter and explicitly resolve/re-enable or post the affected entry within normal accounting restrictions.

## Troubleshooting

| Symptom | Check |
|---|---|
| No generated entries | Actual source state, generation mode, both dates, account compatibility and same-period skip rules |
| No holding account configured | Per-account override first, then company fallback |
| Report empty despite generated entries | Account filter (including `expense_other` mismatch), selected dates, original accounting date and company/options |
| Recognition dates are yearly | Side-specific periodicity; refunds/misc use the method's outbound-based selection |
| Partial last month receives zero | Full Months normalization and removal of zero-total recognition moves |
| Cannot reset grouped original | A linked generated move has multiple originals |
| Deferred entry remains draft after a failure | Chatter, `auto_post`, due date and accounting restrictions |
| Budget consumes the full bill immediately | Holding-account type may be included by the Odoo 20 budget filter |

## Source Verification

Reviewed the implementation and relevant existing [`generation tests`](../enterprise/account_accountant/tests/test_deferred_management.py) and [`report tests`](../enterprise/account_reports/tests/test_deferred_reports.py). Only the isolated proration arithmetic above was executed during this documentation update; the database-dependent test suites were not run.

## Related Docs

- [Deferred Revenue](deferred_revenue.md)
- [Analytic Accounting](analytic_accounting.md)
- [Analytic Budget](analytic_budget.md)
- [Documentation index](INDEX.md)

# Deferred Revenue — Odoo 20

> Reviewed against the local source on 2026-09-22. Generation: [`account_accountant`](../enterprise/account_accountant/). Reporting/grouped generation: [`account_reports`](../enterprise/account_reports/).
> This customer-invoice guide shares the mechanics documented in [Deferred Expenses and Revenue](deferred_expenses_revenue.md).

## Purpose

Deferred revenue allocates an invoiced income amount across its configured delivery period. For example, a 3,600 GEL invoice covering April 1–March 31 can recognize 300 GEL each month, with the unrecognized balance held in a liability account.

**Invoicing is not receipt of cash.** Deferral works from the invoice's journal-item balance whether or not the customer has paid. The generated reclassification/recognition entries do not themselves move cash or settle the receivable.

This is useful for subscriptions, maintenance and services billed for a period. The dates and recognition method must reflect the intended accounting treatment; the software does not infer contractual performance obligations from the invoice description.

## Configuration

Sources: [`res_company.py`](../enterprise/account_accountant/models/res_company.py), [`settings view`](../enterprise/account_accountant/views/res_config_settings_views.xml).

| Setting | Field | Values / behavior |
|---|---|---|
| Journal | `deferred_revenue_journal_id` | UI selects an active general journal |
| Default holding account | `deferred_revenue_account_id` | UI selects `liability_current` |
| Generate Entries | `generate_deferred_revenue_entries_method` | `on_validation` (default) or `manual` |
| Computation | `deferred_revenue_amount_computation_method` | `month` (default), `day`, `full_months` |
| **Periodicity** | `deferred_revenue_periodicity` | `month` (default) or fiscal `year`; shown for on-validation mode |

A source income account can also have **`deferred_account_id`**, which overrides the company holding account, and **`is_deferred`**, which makes deferred date entry required in the invoice UI. These are defined in [`account_account.py`](../enterprise/account_accountant/models/account_account.py). The normal revenue account remains on the invoice; the holding account is used in generated moves.

The holding-account type restriction above is a UI selection domain. It is not a universal backend constraint on every way a company field could be written.

Expense and revenue settings are separate, but the local periodicity selector has exceptions for refunds/miscellaneous entries described below.

## Walkthrough: 3,600 GEL Annual Service Invoice

Assumptions: company currency GEL, monthly calculation and periodicity, on-validation generation, no taxes in this example, invoice accounting date April 1.

1. Configure the revenue journal and company/per-income-account holding account.
2. Create the customer invoice on an `income` or `income_other` account.
3. Enter deferred dates **2026-04-01 through 2027-03-31**. Verify both dates rather than relying on onchange defaults.
4. Set analytic distribution if needed.
5. Post the invoice, then inspect its generated deferred entries.

The invoice form's current view includes deferred-date controls alongside account information, and the journal-item view uses a date-range widget. The old instruction to enable two separate Start Date and End Date columns is not a universal description of this UI. See [`account_move_views.xml`](../enterprise/account_accountant/views/account_move_views.xml).

### Original Invoice

```text
DR Customer receivable       3,600
CR Service revenue           3,600
```

### Initial Reclassification, at the Invoice Accounting Date

```text
DR Service revenue           3,600
CR Deferred revenue          3,600
```

### Each Monthly Recognition, for This Full-Month Example

```text
DR Deferred revenue            300
CR Service revenue             300
```

The first recognition is April 30 and the final one March 31. After April's recognition, this contract's holding liability is 3,300 and recognized revenue is 300. If the first period is already due when posting, its recognition can post immediately; the final P&L effect on that day need not be zero.

Future recognition moves remain scheduled with `auto_post = at_date`. A future source invoice that is only scheduled, rather than actually posted, does not immediately generate its deferral schedule.

### Why the Debit/Credit Signs Work

Source revenue `line.balance` is negative. The initial reclassification multiplies it by -1 on the revenue account and +1 on the holding account: debit revenue, credit liability. Recognition multiplies it by +1 on revenue and -1 on holding: **credit revenue, debit liability**.

The same code handles expense balances with the opposite economic direction. Expense recognition is **debit expense / credit holding asset**, not debit holding / credit expense. Source: [`_generate_deferred_entries()`](../enterprise/account_accountant/models/account_move.py).

## Dates, Calculation and Periodicity

Both deferred endpoints are inclusive. **Any valid end date can be used; month-end is not mandatory on the invoice line.** Start must not exceed end, and a start requires an end. Onchanges can copy one endpoint to the other; the stored compute can fill an absent start from invoice date in another path.

| Computation | Behavior |
|---|---|
| Months | 30-day-month weighting with end-of-month normalization |
| Days | Actual calendar-day weighting |
| Full Months | First-of-month-normalized boundaries; a partial terminal month can receive zero |

For a 900 GEL service from April 15–June 14 with monthly periodicity, source-helper calculations give:

| Method | April | May | June |
|---|---|---|---|
| Months | 240 | 450 | 210 |
| Full Months | 450 | 450 | 0 |

For full April–June using Days, 91 covered days produce approximately 296.70, 306.59 and a final residual of 296.71. The final individual recognition amount is forced to the remaining balance, and zero-total recognition moves are deleted.

**Yearly periodicity** creates fiscal-year periods, clipped to the line dates. It is separate from the amount-computation method. Do not assume all schedules have monthly recognition dates or calendar-year boundaries.

Unnecessary same-month deferrals can be skipped. There is also a single-period skip condition based on the period start month and accounting month, plus additional Full Months short-range behavior. See `_get_deferred_periods()` and `_generate_deferred_entries()` in [`account_move.py`](../enterprise/account_accountant/models/account_move.py).

### Credit-Note Periodicity Caveat

The local periodicity selector uses `is_outbound()`: a customer invoice uses revenue periodicity, but a **customer credit note uses expense periodicity**. Vendor refunds and miscellaneous entries use revenue periodicity. This is distinct from generation-mode selection. If expense and revenue periodicities differ, verify the credit note's generated dates rather than assuming they mirror the original invoice schedule.

## On Validation Versus Manually and Grouped

| Mode | Result |
|---|---|
| On validation | Per-source-line initial reclassification and recognition schedule, created when the invoice posts |
| Manually & Grouped | Report-end adjustment of the unrecognized balance plus a next-day reversal |

In manual mode, open **Deferred Revenues** under Accounting's Review/Regularization Entries, review the report period and use **Generate entry**. The report end must be month-end, and the period must not be locked. This requirement applies to the report-generation action, not the invoice line's end date.

For 3,600 invoiced with 300 recognized by April end, the net grouped adjustment is:

```text
April 30: DR Revenue 3,300 / CR Deferred revenue 3,300
May 1:    DR Deferred revenue 3,300 / CR Revenue 3,300
```

May's closing adjustment then establishes the remaining deferred balance for that closing date. The action calls `_post(soft=True)` on both moves, so it may return already-posted due entries and a scheduled future reversal. It is not merely a draft-entry creation action.

Source: [`account_deferred_reports.py`](../enterprise/account_reports/models/account_deferred_reports.py).

## Deferred Revenues Report

The handler is `account.deferred.revenue.report.handler`. It filters source accounts to `income` and `income_other`, requires both deferred dates, and computes allocations from original balances/dates.

| Column | Meaning |
|---|---|
| Total | Full eligible source amount |
| Not Started | Deferrals beginning after the selected end |
| Before | Allocation before the viewed periods |
| Selected period(s) | Amount allocated to each period |
| Recognized | Calculated cumulative allocation through the selected end |
| **≤ 12 Months** | Future allocation within the following 12 months |
| **> 12 Months** | Future allocation beyond that point |

The current report splits the former Later column into two horizons. “Recognized” is a calculated schedule amount; inspect actual journal-entry states if verifying posted accounting.

The fully-inside-period exclusion requires the start, end **and original accounting date** to lie inside the selected report range. Thus selecting a full year can hide an invoice booked and fully recognized in that year, while an invoice booked earlier need not be excluded by that same condition. Company, account type, dates and report options also affect visibility.

Manual-mode warnings distinguish pending, partially generated and fully generated adjustments. Linked posted or future-scheduled entries at the report end prevent regeneration of the same eligible originals through that path.

## Taxes, Analytics and Financial Reports

### Tax Behavior

[`account_tax.py`](../enterprise/account_accountant/models/account_tax.py) does not carry deferred dates onto tax repartition lines used in tax closing. Compatible tax allocations with `use_in_tax_closing = False` can inherit dates. Generated deferral moves also suppress automatic addition/recomputation of account default taxes.

This source behavior does not justify the old blanket statement that every VAT amount is legally due on invoice date or that no tax amount can be deferred. Cash-basis behavior, localization and tax configuration are separate from the revenue-recognition schedule.

### Analytic Distribution

Individual generated lines carry the source distribution onto both revenue and holding sides. For a credit to revenue, the analytic amount is positive; for its initial debit reversal, negative. Monthly recognition then adds positive income analytics.

The Odoo 20 budget report excludes liability holding accounts. With matching dimensions/date/company and a normal current-liability holding account, a revenue budget therefore sees the income-side initial cancellation and subsequent recognition. Analytic account balances can include both sides and need not equal budget achieved amounts. See [Analytic Budget](analytic_budget.md).

Grouped entries weight distributions from original balances and group by source/holding accounts. They do not promise a separately preserved partner/product line for every source invoice.

### P&L, Balance Sheet and Cash

The P&L reflects posted recognition amounts on the income account; the liability reflects posted reclassification less posted recognition. A future schedule entry does not affect those reports until posted. The invoice receivable is settled through payments/reconciliation, independently of deferral. There is no assumption that cash arrived on the invoice date.

Recognition uses the original **company-currency balance** rather than converting the invoice afresh every month. Currency settlement gains/losses are handled separately. See [Currency Exchange and Transit](currency_exchange_transit.md).

## Changes, Refunds and Posting Failures

- Reset to draft is blocked if a linked deferral entry combines **more than one original move**. Manual mode alone is not the deciding condition.
- Otherwise `_unlink_or_reverse()` deletes, cancels or reverses generated moves according to their deletion/audit protections. Not every posted move is automatically reversed.
- Changing the account on an already-deferred source line with both dates is blocked. Merely changing a date should not be assumed to regenerate an existing schedule.
- Reversal copying preserves deferred dates when `move_reverse_cancel` is present, despite the fields being `copy=False` normally. Check the actual dates and amounts on a credit note; the engine does not infer early-termination treatment.
- The daily auto-post job processes due scheduled drafts. If an individual posting fails with `UserError`, it records the error in chatter and sets **`auto_post = no`**. Fixing the cause does not automatically re-enable posting.

Sources: [`deferral lifecycle`](../enterprise/account_accountant/models/account_move.py), [`base move lifecycle and cron`](../addons/account/models/account_move.py), [`cron definition`](../addons/account/data/service_cron.xml).

## Technical Reference

| Model/field or method | Role |
|---|---|
| `account.move.line.deferred_start_date`, `deferred_end_date` | Inclusive service period |
| `has_deferred_moves` | Parent move has generated deferral links |
| `account.move.deferred_move_ids` | Generated moves linked to an original |
| `deferred_original_move_ids` | Originals linked to a generated move |
| `deferred_entry_type` | Computed on linked generated moves: expense/revenue/misc; **false on an original without such original links** |
| `_get_deferred_entries_method()` | Chooses generation mode and checks mixed miscellaneous entries |
| `_get_deferred_entries_periodicity()` | Chooses period setting through outbound direction |
| `_get_deferred_periods()` | Monthly/fiscal-year boundaries and skip condition |
| `_get_deferred_period_amount()` | Day/month/full-month math |
| `_generate_deferred_entries()` | Individual schedule generation |
| `account.deferred.revenue.report.handler` | Revenue report and grouped-generation specialization |

## Related Docs

- [Deferred Expenses and Revenue](deferred_expenses_revenue.md) — shared implementation, source discrepancies and budget examples
- [Chart of Accounts](accounting_coa.md)
- [Accounting Reports](accounting_reports.md)
- [Documentation index](INDEX.md)

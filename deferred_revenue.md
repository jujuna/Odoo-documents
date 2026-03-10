# Deferred Revenue — Odoo 19

> For: accountants, finance managers, and developers.
> Source: `account_accountant` + `account_reports` (both enterprise).
> All technical references traced to actual source code.
> See also: [deferred_expenses_revenue.md](deferred_expenses_revenue.md) for the combined reference and expense-focused walkthrough.

---

## The Problem This Solves

Your company receives 1200 GEL on January 1 for an annual consulting contract (Jan–Dec).

**Without deferral:**
- January P&L: +1200 GEL revenue
- February–December P&L: 0 GEL
- January looks like a record month, the rest of the year looks dead

**With deferral:**
- January–December P&L: +100 GEL per month
- Balance sheet shows how much revenue you still owe (haven't yet earned)
- Reports reflect reality — revenue matched to the period you deliver the service

IFRS 15 and Georgian GAAP both require revenue recognition in the period the performance obligation is satisfied, not when cash is received.

---

## When to Use Deferred Revenue

Use it whenever you invoice a customer upfront for something delivered **over multiple future months**:

| Situation | Example |
|---|---|
| Annual SaaS subscription | Customer pays 12 months upfront |
| Prepaid consulting retainer | 6-month retainer billed in advance |
| Annual maintenance contract | Support agreement paid at start |
| Training program | Multi-month course billed upfront |
| Membership / license fee | Annual membership fee |

**Do NOT use for:**
- Monthly invoices where revenue is earned the same month
- One-time product sales fully delivered at invoicing
- Progress billing where each invoice matches completed work

---

## How It Differs from Deferred Expenses

| Dimension | Deferred Expense | Deferred Revenue |
|---|---|---|
| Source document | Vendor bill (`in_invoice`, `in_refund`) | Customer invoice (`out_invoice`, `out_refund`) |
| Account type required | `expense`, `expense_depreciation`, `expense_direct_cost` | `income`, `income_other` |
| Holding account type | Current Asset / Prepayments (`asset_current`, `asset_prepayments`) | Current Liability (`liability_current`) |
| Balance sheet meaning | "We paid but haven't consumed yet" | "We received but haven't earned yet" |
| Initial entry: holding account side | Debit (asset increases) | Credit (liability increases) |
| Monthly recognition | DR Holding → CR Expense (asset decreases, expense recognized) | DR Holding → CR Revenue (liability decreases, revenue recognized) |
| Sign in report | `is_reverse = True` | `is_reverse = False` |
| Config fields | `deferred_expense_*` | `deferred_revenue_*` |
| `deferred_entry_type` value | `'expense'` | `'revenue'` |

Source: [account_deferred_reports.py:438](../enterprise/account_reports/models/account_deferred_reports.py#L438) — sign logic
Source: [account_move.py:162](../enterprise/account_accountant/models/account_move.py#L162) — entry type computation

---

## Two Things You Must Configure First

### 1. The Invoice Line Account (Revenue Account)
This is the normal revenue/income account you already use — for example `4XX Consulting Revenue`. Nothing special needed. It must be of type **Income** or **Other Income**.

### 2. The Deferred Revenue Account (Holding Account)
This is a **balance sheet account** that temporarily holds the unearned revenue until it is recognized each month. Example: `2400 Deferred Revenue`.

This account must be of type **Current Liabilities** — it represents money you received but haven't yet earned (you owe the customer the service).

**Where to configure:** Accounting → Configuration → Settings → search "Deferred"

---

## Configuration — All 4 Revenue Fields

All settings live on `res.company` and are exposed in Settings → Accounting → Deferred.

| Setting (UI label) | Company field | Values | Notes |
|---|---|---|---|
| Deferred Revenue Journal | `deferred_revenue_journal_id` | Any journal | Required; error raised on validation if missing |
| Deferred Revenue Account | `deferred_revenue_account_id` | Current Liability account | Must be type `liability_current` |
| Generate Deferred Revenue Entries | `generate_deferred_revenue_entries_method` | `on_validation` / `manual` | Independent from expense setting |
| Deferred Revenue Based on | `deferred_revenue_amount_computation_method` | `day` / `month` / `full_months` | Controls proration |

Source: [res_company.py:47–73](../enterprise/account_accountant/models/res_company.py#L47)
Source: [res_config_settings.py](../enterprise/account_accountant/models/res_config_settings.py)

**Important:** Revenue and expense settings are fully independent. You can use `on_validation` for revenue and `manually & grouped` for expenses (or vice versa).

---

## Step-by-Step: How to Defer a Customer Invoice

**Scenario:** You invoice a customer 3600 GEL for a 12-month consulting contract (April 1 – March 31).

**Step 1** — Create the customer invoice (Accounting → Customers → Invoices → New)

**Step 2** — Add the invoice line: 3600 GEL, account = `4XX Consulting Revenue`

**Step 3** — Enable the date columns on the line:
Click the small grid icon at the right edge of the line headers → enable **Start Date** and **End Date**

**Step 4** — Set the dates:
- Start Date: `2026-04-01`
- End Date: `2027-03-31` — always the **last day** of the last month

**Step 5** — Validate (confirm) the invoice

That's it. Odoo handles everything automatically from here.

---

## What Odoo Creates Automatically (On Validation Mode)

After you validate the invoice above, Odoo creates these journal entries:

**Entry 1 — Removes the 3600 GEL from revenue on the invoice date**
```
Debit  Consulting Revenue (4XX)       3,600 GEL   ← removes premature revenue from P&L
Credit Deferred Revenue (2400)        3,600 GEL   ← parks on balance sheet as liability
```
Result: the 3600 GEL does NOT appear in P&L today. It sits on the balance sheet as unearned revenue.

**Entry 2 — April 30: recognizes April's share**
```
Debit  Deferred Revenue (2400)          300 GEL   ← reduces "owed to customer" liability
Credit Consulting Revenue (4XX)         300 GEL   ← recognizes earned revenue in P&L
```

**Entry 3 — May 31: recognizes May's share**
```
Debit  Deferred Revenue (2400)          300 GEL
Credit Consulting Revenue (4XX)         300 GEL
```

*...continues monthly...*

**Entry 13 — March 31 (next year): recognizes last month**
```
Debit  Deferred Revenue (2400)          300 GEL
Credit Consulting Revenue (4XX)         300 GEL
```

Total recognized: 3600 GEL. Deferred Revenue balance returns to zero.

### Sign logic in the code

The sign difference from expenses is at [account_move.py:336–369](../enterprise/account_accountant/models/account_move.py#L336):

**Expense initial reversal (line 338):**
```python
[(line.account_id, -1), (deferred_account, 1)]   # CR expense, DR prepaid
```

**Revenue monthly recognition (line 369):**
```python
[(deferred_amounts['account_id'], 1), (deferred_account, -1)]   # DR revenue, CR deferred
```

Both expense and revenue use the same `_generate_deferred_entries()` method — the account type determines the sign direction.

---

## How Monthly Amounts Are Calculated

Same three methods as expenses, configured independently:

### Months (default)
Treats every month as 30 days. Best for most subscriptions and retainers.

**Example: 3600 GEL, April 1 – March 31 (12 months)**
- Each month = 300 GEL

### Days
Divides by actual calendar days. Best for daily-rate contracts.

**Example: 900 GEL, April 1 – June 30 (91 days)**
- April: 30/91 × 900 = 296.70 GEL
- May: 31/91 × 900 = 306.59 GEL
- June: 30/91 × 900 = 296.71 GEL (last period absorbs rounding)

### Full Months
Counts partial first/last month as a full month.

**Example: 900 GEL, April 15 – June 14**
- Months method: April = 0.5, May = 1, June = 0.5 → 225 / 450 / 225
- Full Months method: April = full, May = full → 450 / 450 / 0

Source: [account_move.py:195](../enterprise/account_accountant/models/account_move.py#L195) — `_get_deferred_period_amount()`

---

## Two Generation Modes

### Mode 1: "On invoice validation" (default, recommended)

All entries created when you confirm the invoice. Each monthly entry auto-posts on the last day of its month via the daily cron.

### Mode 2: "Manually & Grouped"

No entries on validation. At month-end, go to the report and click "Generate Entry."

**Monthly workflow:**
1. End of month → Accounting → Review → Regularization Entries → **Deferred Revenue**
2. Check the warning banner
3. Click "Generate Entry"
4. Review and post the created entry

Creates two entries per generate action:
- Entry 1 (grouped): all pending revenue deferrals combined, dated = period end
- Entry 2 (reversal): exact reversal dated = period end + 1 day

Same mechanics as deferred expense manual mode. Source: [account_deferred_reports.py:498](../enterprise/account_reports/models/account_deferred_reports.py#L498)

---

## How Deferral Affects Your Financial Reports

### Balance Sheet (Current Liabilities)

The **Deferred Revenue account** (`liability_current` type) appears under Current Liabilities. Its balance = total unearned revenue across all active deferrals.

Example at April 30 (after April recognition of the 3600 GEL contract):
```
Deferred Revenue (2400)    3,300 GEL   ← 3600 - 300 earned in April
```
This tells the reader: "we have received 3600 but only earned 300 so far — we still owe 3300 worth of service."

### P&L / Income Statement

The **revenue account** (e.g. `4XX Consulting Revenue`) only receives the **monthly portion**. On the invoice date the revenue is reversed — so the invoice validation itself adds nothing to P&L.

```
April P&L:  Consulting Revenue   +300 GEL
May P&L:    Consulting Revenue   +300 GEL
...
```

### Trial Balance

- `2400 Deferred Revenue`: CR balance (reducing as months pass)
- `4XX Consulting Revenue`: CR balance builds up each month

At the end of the 12 months: Deferred Revenue = 0, total revenue recognized = 3600 GEL.

### Cash Flow Statement

Cash was received at invoice date → shows in Operating Activities for that period. The monthly recognition entries are non-cash movements between balance sheet and P&L — they do NOT affect cash flow.

---

## The Deferred Revenue Report

**Where:** Accounting → Review → Regularization Entries → **Deferred Revenue**

Same structure as the expense report, but filters for `account_type IN ('income', 'income_other')`.

### Report columns

| Total | Not Started | Before | [Current Month] | Recognized | Later |
|---|---|---|---|---|---|
| 3,600 | — | — | 300 | 300 | 3,300 |

- **Total** — original invoice amount
- **Not Started** — deferrals with start date after viewed period
- **Before** — amount recognized in prior periods
- **[month]** — recognized in this specific month
- **Recognized** — cumulative to end of viewed period
- **Later** — still on balance sheet, future months

Click any number → opens the underlying journal entries.

### Report handler

Two separate report classes, both inheriting `account.deferred.report.handler`:

| Report | Handler class | `_get_deferred_report_type()` |
|---|---|---|
| Deferred Expenses | `account.deferred.expense.report.handler` | `'expense'` |
| Deferred Revenue | `account.deferred.revenue.report.handler` | `'revenue'` |

Source: [account_deferred_reports.py:649–664](../enterprise/account_reports/models/account_deferred_reports.py#L649)

### Why the report shows nothing

Same rule as expenses: **the report hides deferrals fully contained within the selected period.**

Select a full year when the deferral runs within that year → appears empty.
Fix: select a specific month.

Source: [account_deferred_reports.py:24](../enterprise/account_reports/models/account_deferred_reports.py#L24) — `_get_domain_fully_inside_period()`

---

## Which Accounts Can Be Deferred (Revenue Side)

| Move type | Account internal group required | Account types |
|---|---|---|
| Customer invoice / receipt | `income` | `income`, `income_other` |
| Manual journal entry | `expense` OR `income` | Any compatible type |

Source: [account_move.py:694](../enterprise/account_accountant/models/account_move.py#L694) — `_has_deferred_compatible_account()`

If the account is wrong type, `_onchange_deferred_start_date()` and `_onchange_deferred_end_date()` clear the dates silently.

---

## VAT / Tax and Revenue Deferral

**Standard VAT is NOT deferred.** Same rule as expenses.

When you invoice a customer with 18% VAT:
- The net amount (e.g. 3000 GEL) → deferred and spread monthly
- The VAT amount (e.g. 540 GEL) → posted to the VAT liability account on the **invoice date**, reported in that month's VAT return

VAT output liability arises at the point of invoicing, not when revenue is recognized. This is standard under Georgian tax law and IFRS.

Source: [account_tax.py:38](../enterprise/account_accountant/models/account_tax.py#L38) — tax lines with `use_in_tax_closing = True` are never deferred.

---

## Analytic Distribution

Same as expenses — analytic distribution from the original invoice line is **proportionally carried** to every deferral entry.

Your project/cost center reports will show revenue spread correctly across months.

For grouped manual entries: distribution is weighted by each line's balance relative to the total.

Source: [account_deferred_reports.py:568](../enterprise/account_reports/models/account_deferred_reports.py#L568)

---

## Cancellation and Editing

### Reset an invoice to draft
If in "on_validation" mode: Odoo deletes future draft entries and reverses posted ones. Clean reset.

### Reset an invoice that was grouped (manual mode)
Blocked. Use a credit note instead.

### Change the income account on a deferred line
Blocked after deferral entries exist. Reset to draft first → change → revalidate.

Source: [account_move.py:120](../enterprise/account_accountant/models/account_move.py#L120) — `button_draft()`

---

## Credit Notes (Revenue Refunds)

When you create a credit note for a deferred revenue invoice:
- The credit note lines carry the same deferral dates
- Signs are **reversed** compared to the original invoice
- The deferred revenue liability decreases proportionally

This handles partial refunds, early termination of contracts, and cancellation scenarios correctly.

---

## Key Rules to Remember

1. **End date is inclusive and must be the last day of a month** — use `2027-03-31`, not `2027-04-01`
2. **Start date defaults to invoice date** if you only set an end date
3. **If all three dates (invoice, start, end) are in the same month** — Odoo skips deferral entirely. Revenue goes straight to P&L
4. **The deferred account must be type = Current Liabilities** — not Receivable or other types
5. **The invoice line account must be type = Income or Other Income** — the report only filters these account types
6. **Monthly amounts always sum to exactly the original total** — last period absorbs rounding
7. **VAT is never deferred** — only the net amount is spread. VAT hits the tax report on the invoice date
8. **Multi-currency invoices** — deferral entries use the company-currency balance from the original invoice. Exchange rate locked at invoice date
9. **Fiscal year end** — entries cross fiscal years automatically
10. **Cron must run daily** — missed entries post on next run

---

## Common Mistakes Quick Reference

| What went wrong | How to recognize it | How to fix it |
|---|---|---|
| Report shows nothing | Selected full year; deferral is within that year | Select a specific month |
| Deferred account type is wrong | Report shows nothing, entries exist | Set account type to `liability_current` |
| Invoice line account is wrong type | No deferral date fields visible | Use an Income or Other Income type account |
| End date = first of next month | Warning on invoice line | Change to last day of last month |
| Invoice, start, end all same month | No entries created | Expected — extend date range to cover multiple months |
| Revenue and deferred account are the same | Entries zero out | Use separate Deferred Revenue account |
| Want to edit a grouped invoice | Cannot reset to draft | Use credit note |
| Lock date blocks month-end entry | Monthly entry stays draft | Remove lock date or manually post |
| Cron not running | All monthly entries stay draft | Settings → Technical → Scheduled Actions → verify active |
| Customer asks for partial refund | Revenue recognized for past months | Create credit note with matching deferral dates |

---

## Technical Reference

### Key files
- Generation logic: [account_move.py:274](../enterprise/account_accountant/models/account_move.py#L274) — `_generate_deferred_entries()`
- Revenue report handler: [account_deferred_reports.py:658](../enterprise/account_reports/models/account_deferred_reports.py#L658)
- Company settings: [res_company.py:47](../enterprise/account_accountant/models/res_company.py#L47)
- Settings UI: [res_config_settings_views.xml:55](../enterprise/account_accountant/views/res_config_settings_views.xml#L55)

### Key fields on `account.move.line`
| Field | Purpose |
|---|---|
| `deferred_start_date` | When deferral begins. [account_move.py:551](../enterprise/account_accountant/models/account_move.py#L551) |
| `deferred_end_date` | When deferral ends (inclusive). [account_move.py:558](../enterprise/account_accountant/models/account_move.py#L558) |
| `has_deferred_moves` | True if parent move has generated entries. [account_move.py:564](../enterprise/account_accountant/models/account_move.py#L564) |

### Key fields on `account.move`
| Field | Purpose |
|---|---|
| `deferred_move_ids` | Many2many to generated deferral entries |
| `deferred_original_move_ids` | Inverse — which original invoices this entry came from |
| `deferred_entry_type` | `'revenue'` for customer invoices. [account_move.py:162](../enterprise/account_accountant/models/account_move.py#L162) |

### Revenue-specific code paths

**Entry type determination** — [account_move.py:170–171](../enterprise/account_accountant/models/account_move.py#L170):
```python
else:  # not purchase document and not journal entry
    move.deferred_entry_type = 'revenue'
```

**Generation method selection** — [account_move.py:156](../enterprise/account_accountant/models/account_move.py#L156):
```python
return self.company_id.generate_deferred_revenue_entries_method
```

**Account compatibility check** — [account_move.py:694](../enterprise/account_accountant/models/account_move.py#L694):
```python
self.move_id.is_sale_document(include_receipts=True)
and self.account_id.internal_group == 'income'
```

**Report domain filter** — [account_deferred_reports.py:39](../enterprise/account_reports/models/account_deferred_reports.py#L39):
```python
account_types = ('income', 'income_other')
```

**Report sign** — [account_deferred_reports.py:438](../enterprise/account_reports/models/account_deferred_reports.py#L438):
```python
is_reverse=self._get_deferred_report_type() == 'expense'  # False for revenue
```

---

## Related Docs

- [INDEX.md](INDEX.md)
- [deferred_expenses_revenue.md](deferred_expenses_revenue.md) — combined reference with expense walkthrough
- [accounting_coa.md](accounting_coa.md) — account types and chart of accounts
- [accounting_reports.md](accounting_reports.md) — reporting engine

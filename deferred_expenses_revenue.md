# Deferred Expenses & Revenue — Odoo 19

> For: accountants, finance managers, and developers.
> Source: `account_accountant` + `account_reports` (both enterprise).
> All technical references traced to actual source code.

---

## The Problem This Solves

Your company pays 1200 GEL on January 1 for an annual BirdWatch license (Jan–Dec).

**Without deferral:**
- January P&L: −1200 GEL expense
- February–December P&L: 0 GEL
- Your monthly reports look wrong — January seems very expensive, other months seem fine

**With deferral:**
- January–December P&L: −100 GEL per month
- Balance sheet shows how much of the prepayment is still unused each month
- Your reports reflect reality

This is not optional for proper accounting — IFRS and Georgian GAAP both require matching expenses to the period they relate to.

---

## When to Use Deferred Expenses

Use it whenever you pay upfront for something that covers **multiple future months**:

| Situation | Example |
|---|---|
| Annual software license | BirdWatch, Parking.Logic V12 |
| Annual support contract | IT maintenance agreement |
| Prepaid insurance | Property insurance for the year |
| Prepaid rent | 6-month office rent paid upfront |
| Multi-year equipment lease | Prepaid portion |

**Do NOT use** for:
- Monthly invoices you pay as you go (just post directly to expense)
- One-time purchases that are fully consumed in the same month
- Fixed asset purchases (use the Assets module instead)

**Revenue side:** same logic applies if your company receives prepayment from a customer for a service you will deliver over multiple months.

---

## Deferred Revenue — The Mirror Image

Everything above applies to revenue too, but in reverse. Your company receives $1,200 in January for a service you will deliver over 12 months.

Without deferral: January revenue = $1,200, rest of year = $0 (inaccurate).
With deferral: $100/month recognized as you actually deliver the service.

**Initial entry when customer invoice is posted:**
```
Debit  Revenue Account (income)          $1,200   ← removes premature revenue from P&L
Credit Deferred Revenue (liability)      $1,200   ← parks on balance sheet
```

**Each month recognition:**
```
Debit  Deferred Revenue (liability)        $100   ← reduces the "owed to customer" amount
Credit Revenue Account (income)            $100   ← recognizes earned revenue in P&L
```

**Balance Sheet:** Deferred Revenue appears under **Current Liabilities** — it is money you received but haven't earned yet (you still owe the customer the service). Each month the liability decreases.

**Separate configuration:** Deferred revenue has its own journal, holding account, generation method, and amount method — all configured independently from deferred expenses. A company can use `on_validation` for expenses and `manually & grouped` for revenue simultaneously.

---

## Which Accounts Can Be Deferred

Deferral date fields only become available on bill/invoice lines when the account type is compatible:

| Move type | Account internal group required | Account types |
|---|---|---|
| Vendor bill / receipt | `expense` | `expense`, `expense_depreciation`, `expense_direct_cost` |
| Customer invoice / receipt | `income` | `income`, `income_other` |
| Manual journal entry | `expense` OR `income` | Any of the above |

You **cannot** defer on receivable, payable, asset, bank, or liability accounts — the date fields won't appear.

**Mixed journal entry rule:** If a manual journal entry contains both expense AND income accounts with deferral dates, and the company uses different generation methods for each type, Odoo raises an error:
> "Having different deferred entries generation methods for expenses and revenues is not supported on journal entries involving both expense and revenue accounts. You can split this entry into two entries instead."

Source: [account_move.py:141](../enterprise/account_accountant/models/account_move.py#L141)

---

## How Deferral Affects Your Financial Reports

This is the most important accounting concept to understand before using this feature.

### Balance Sheet (მოკლევადიანი აქტივები)

The **Prepaid Expenses account** (`asset_prepayments` type) appears under Current Assets. Its balance at any point = total unrecognized prepaid amount across all active deferrals.

Example at April 30 (after April recognition):
```
Prepaid Expenses (1520)    27.32 GEL   ← BirdWatch remaining (33 - 5.68 - 8.11)
```
This tells the reader: "we have already paid for services we haven't yet received."

### P&L / Income Statement

The **expense account** (e.g. `6XX Subscriptions`) only receives the **monthly portion**. On the bill date the expense is reversed — so the bill validation itself adds nothing to P&L. Only the monthly cron-posted entries add to P&L.

```
March P&L:  Subscriptions expense   +5.68 GEL
April P&L:  Subscriptions expense   +8.11 GEL
...
```

### Trial Balance

Both accounts appear:
- `1520 Prepaid`: DR balance (reducing as months pass)
- `6XX Subscriptions`: CR balance builds up each month

At the end of the deferral period: Prepaid = 0, total expense recognized = original bill amount.

### Reports by Period (Critical for monthly close)

When you look at any financial report for a specific month:
- The monthly recognition entry (posted on last day of month) is included
- The original bill's reversal is on the bill date, not the report period
- Future month entries are draft → not included → do not distort current period

**This means monthly P&L reports are accurate from day one of setup.**

---

## Two Things You Must Configure First

Before using deferred expenses, two accounts must be set up:

### 1. The Bill Line Account (Expense Account)
This is the normal expense account you already use — for example `6XX Subscription Expenses`. Nothing special needed. It just must be of type **Expense**.

### 2. The Deferred Account (Prepaid/Holding Account)
This is a **balance sheet account** that temporarily holds the prepaid amount until it is recognized each month. Example: `1520 Prepaid Expenses`.

This account must be of type **Prepayments** (not regular Current Assets — this is the most common mistake).

**Why two accounts?** The deferred account acts like a "waiting room" on the balance sheet. Money goes in when you pay, and comes out month by month as it is earned/consumed.

**Where to configure:** Accounting → Configuration → Settings → search "Deferred"

---

## Step-by-Step: How to Defer a Vendor Bill

**Scenario:** You receive a BirdWatch invoice for 360 GEL covering April 1 – June 30.

**Step 1** — Create the vendor bill as normal (Accounting → Vendors → Bills → New)

**Step 2** — Add the invoice line: 360 GEL, account = `6XX Subscription Expenses`

**Step 3** — Enable the date columns on the line:
Click the small grid icon (`⊞`) at the right edge of the line headers → enable **Start Date** and **End Date**

**Step 4** — Set the dates:
- Start Date: `2026-04-01`
- End Date: `2026-06-30` ← always the **last day** of the last month, not `2026-07-01`

**Step 5** — Validate (confirm) the bill

That's it. Odoo handles everything automatically after this point.

---

## What Odoo Creates Automatically

After you validate the bill above, Odoo immediately creates these journal entries behind the scenes:

**Entry 1 — Takes the 360 GEL off the expense account on the billing date**
```
Debit  Prepaid Expenses (1520)    360 GEL
Credit Subscription Expenses      360 GEL
```
Result: the 360 GEL does NOT appear in P&L today. It sits on the balance sheet as prepaid.

**Entry 2 — April 30: recognizes April's share**
```
Debit  Subscription Expenses      120 GEL
Credit Prepaid Expenses (1520)    120 GEL
```

**Entry 3 — May 31: recognizes May's share**
```
Debit  Subscription Expenses      120 GEL
Credit Prepaid Expenses (1520)    120 GEL
```

**Entry 4 — June 30: recognizes June's share**
```
Debit  Subscription Expenses      120 GEL
Credit Prepaid Expenses (1520)    120 GEL
```

Total recognized: 360 GEL. Prepaid balance returns to zero. ✓

Entries 2–4 are created on the validation date but only **post automatically** when their month arrives. You do not need to do anything each month.

---

## Real Example From Your System

Bill `BILL/2026/03/0004` — 33 GEL, deferred 2026-03-10 → 2026-07-11:

| Entry | Date | Debit | Credit | Amount |
|---|---|---|---|---|
| Initial reversal | 2026-03-09 (bill date) | Prepaid | Expenses | 33.00 |
| March recognition | 2026-03-31 | Expenses | Prepaid | 5.68 |
| April recognition | 2026-04-30 | Expenses | Prepaid | 8.11 |
| May recognition | 2026-05-31 | Expenses | Prepaid | 8.11 |
| June recognition | 2026-06-30 | Expenses | Prepaid | 8.11 |
| July recognition | 2026-07-11 | Expenses | Prepaid | 2.99 |

March is partial (March 10–31 = 22 days of a 123-day period). July is also partial (July 1–11). The last entry absorbs any rounding so the total is always exactly 33.00.

---

## How Monthly Amounts Are Calculated

Configured in Settings → "Based on":

### Months (default)
Treats every month as 30 days. February and March get the same amount. Best for most subscriptions.

**Example: 90 GEL, March 1 – May 31**
- Each month = 1/3 of total = 30 GEL

### Days
Divides by actual calendar days. February gets slightly less than March. Best for daily-rate contracts.

**Example: 90 GEL, March 1 – May 31 (91 days)**
- March: 31/91 × 90 = 30.66 GEL
- April: 30/91 × 90 = 29.67 GEL
- May: 30/91 × 90 = 29.67 GEL

### Full Months
Counts partial first/last month as a full month. Best when your contract says "first month is fully charged regardless of start date."

**Example: 90 GEL, March 15 – May 14**
- Months method: March = 0.5 month, April = 1 month, May = 0.5 month → 22.50 / 45.00 / 22.50
- Full Months method: March = full, April = full → 45.00 / 45.00 / 0 (May is excluded)

---

## Two Generation Modes

### Mode 1: "On bill validation" (default, recommended)

Odoo creates all entries **automatically when you confirm the bill**. Nothing more to do. Each monthly entry posts itself on the last day of its month.

Good for: most companies. Set it and forget it.

### Mode 2: "Manually & Grouped"

Odoo does NOT create entries when you validate the bill. Instead, at the end of each month, your accountant goes to the report and clicks **"Generate Entry"**.

What's different: instead of one entry per bill, Odoo creates **one grouped entry per month** combining ALL pending deferrals from all bills. This gives you one clean journal entry per period.

Good for: companies that want to review and approve all deferrals at month-end before they post, or prefer minimal journal entry count.

**Monthly workflow in manual mode:**
1. End of month → Accounting → Review → Regularization Entries → Deferred Expenses
2. Check the warning banner — it tells you if entries still need to be generated
3. Click "Generate Entry"
4. Review the created entry, post it

**Critical constraint for "Generate Entry":** The selected period must end on the **last day of a month**. If you select a period ending mid-month, Odoo rejects with:
> "You cannot generate entries for a period that does not end at the end of the month."

Also: **Lock date is enforced** — if the selected period is locked, "Generate Entry" raises an error. You cannot backdoor-generate entries for a locked period.

### What "Manually & Grouped" Actually Creates

For each "Generate Entry" action, Odoo creates exactly **two entries**:

```
Entry 1 (grouped deferral):  date = April 30, auto_post='at_date'
  → ALL pending deferrals for ALL bills combined into ONE entry
  → Contains line pairs: (expense account, deferred account) for each account group

Entry 2 (automatic reversal): date = May 1, auto_post='at_date'
  → Exact reversal of Entry 1
  → Ref: "Reversal of Grouped Deferral Entry of April 2026"
```

**Why the reversal?** The grouped entry is a monthly "snapshot." The reversal on day+1 clears it, so next month's generate action can create a fresh snapshot. This prevents double-counting. The net effect across two months is zero — only the current month's entry is "live" at any given time.

**Relation to original bills** is written directly via SQL (not ORM) to avoid memory issues on large datasets with many bills. Source: [account_deferred_reports.py:529](../enterprise/account_reports/models/account_deferred_reports.py#L529)

---

## The Deferred Expenses Report

**Where:** Accounting → Review → Regularization Entries → Deferred Expenses

This report shows all active deferrals — what has been recognized and what is still pending.

### Reading the report columns

For the BirdWatch bill (33 GEL) viewed in **March 2026**:

| Total | Not Started | Before | March 2026 | Recognized | Later |
|---|---|---|---|---|---|
| 33.00 | — | — | 5.68 | 5.68 | 27.32 |

- **Total** — the full original bill amount
- **Not Started** — deferrals that haven't begun yet (start date is after the viewed period)
- **Before** — amount recognized in periods before the one you're viewing
- **[month]** — what was recognized in that specific month
- **Recognized** — total recognized up to the end of the viewed period
- **Later** — still on the balance sheet, will be recognized in future months

Click any number → Odoo opens the underlying journal entries.

### Why the report shows nothing — the most common problem

**The report hides deferrals that are fully contained within your selected period.**

If you select **year 2026** and your deferral runs March–July 2026: all dates fall inside 2026 → report appears empty.

**Fix: select a specific month, not the full year.**

Select March 2026 → the deferral end date (July) is outside March → report shows the data.

This is intentional — the report is designed to show deferrals that cross period boundaries.

### Warning banners on the report (manual mode only)

| Banner | Meaning | Action |
|---|---|---|
| Yellow warning: "partially generated" | Some bills have entries, some don't | Click Generate Entry to catch up |
| Yellow warning: "never generated" | Bills are pending but nothing generated yet | Click Generate Entry |
| Blue info: "fully generated" | All caught up | Nothing needed |
| "There are unposted entries..." | Entries exist as draft | Click "Post Journal Entries" on the banner |

---

## Analytic Distribution — How It Carries Through

Analytic distribution (cost centers, projects) from the original bill line is **proportionally carried** to every deferral entry.

**Example:** Bill with 70% to Project A, 30% to Project B → every monthly recognition entry gets the same 70%/30% split.

**Result:** Analytic reports, project cost tracking, and budget comparisons all see expenses spread correctly across months — not just on the billing date.

**For grouped manual entries:** analytic distribution is weighted by each line's balance relative to the total grouped amount.

Source: [account_deferred_reports.py:568](../enterprise/account_reports/models/account_deferred_reports.py#L568)

---

## Partner and Product — Preserved on All Entries

Each deferral entry line carries `partner_id` and `product_id` from the original bill line. This means you can filter journal items or reports by vendor/customer or product to trace exactly which deferred expense or revenue came from which transaction.

---

## What Happens If You Need to Cancel or Edit

### Reset a bill to draft
If the bill was in "on_validation" mode: Odoo automatically **deletes** future draft deferral entries and **reverses** already-posted ones. The bill returns to draft cleanly and you can edit and revalidate.

### Reset a bill to draft that was grouped with others (manual mode)
Odoo **blocks** this. You cannot reset to draft because one journal entry covers multiple bills. **Use a credit note instead.**

### Change the expense account on a deferred bill line
**Blocked** after deferral entries exist. Reset to draft first → change the account → revalidate.

### The end date is wrong and bill is already validated
Reset to draft → fix the end date → revalidate. New entries will be created with the correct dates.

---

## VAT / Tax and Deferral — Critical Accounting Point

**Standard VAT is NOT deferred.** This is one of the most important things to understand.

When you have a vendor bill with 18% VAT:
- The net amount (e.g. 1000 GEL) → deferred and spread monthly
- The VAT amount (e.g. 180 GEL) → posted to the VAT account **on the bill date**, reported in that month's VAT return

**Why?** VAT deductibility is determined by the bill date, not by when the service is consumed. Georgian tax law (and IFRS) allows you to claim the input VAT in the period you receive the invoice, regardless of when the related expense is recognized in P&L.

So for a 1180 GEL annual subscription bill (1000 net + 180 VAT):
- VAT return (March): +180 GEL input VAT → claimed immediately
- March P&L: only the March net portion (e.g. 81.97 GEL)
- Balance sheet: remaining unrecognized net (e.g. 918.03 GEL) as prepaid

**Source:** [account_tax.py:38](../enterprise/account_accountant/models/account_tax.py#L38) — tax lines only get deferred dates when `use_in_tax_closing = False`. Standard VAT has `use_in_tax_closing = True` → always posted immediately.

Non-deductible taxes (not in VAT closing, e.g. expense-allocated non-deductible VAT) are deferred together with the base amount.

---

## How the Monthly Posting Actually Happens — The Cron Job

Monthly deferral entries do NOT post themselves by magic. There is a **daily scheduled cron job** that handles it.

**Cron:** "Account: Post draft entries with auto_post enabled and accounting date up to today"
**Runs:** every day at 2:00 AM
**Source:** [service_cron.xml](../addons/account/data/service_cron.xml) → calls `_autopost_draft_entries()`

The cron finds all draft moves where:
- `state = draft`
- `date <= today`
- `auto_post != 'no'`

All deferral entries are created with `auto_post = 'at_date'` → they are picked up by this cron on their date.

### What this means practically

- You do NOT need to do anything each month — the cron handles it overnight
- If the server is down overnight on March 31 → the March entry stays draft, posts the next time the cron runs
- If a **lock date** is set that covers the entry's date → the cron fails to post it, logs an error message on the entry, moves to the next one — the entry stays draft until the lock is removed
- You can manually post a draft deferral entry anytime from Accounting → Journal Entries (no need to wait for cron)

---

## How Deferral Connects to Budgets

Budgets in Odoo are tracked via **analytic accounts**. The budget system reads `account_analytic_line` (AAL) records — not directly journal entries.

**Key point:** When a deferral entry is posted, it creates an AAL record because it carries the `analytic_distribution` from the original bill.

### The full budget flow for a deferred expense

**Step 1 — Bill validated (e.g. March 9):**
- Bill creates AAL: +33 GEL on March 9 for analytic "Parking System"
- Initial reversal creates AAL: −33 GEL on March 9 for analytic "Parking System"
- Net AAL on March 9: **0 GEL** → budget sees nothing for March 9

**Step 2 — March 31 cron runs:**
- Monthly entry posts: +5.68 GEL on March 31 → AAL created: +5.68 GEL on March 31
- Budget for March sees: **5.68 GEL** consumed

**Step 3 — April 30:**
- 8.11 GEL → budget for April sees **8.11 GEL** consumed

**Result:** Budget consumption is spread across months, matching the recognition schedule. This is the correct behavior — your budget for "Parking System subscriptions" is consumed gradually, not all at once on the billing date.

### Budget date range matters

The budget line has `date_from` and `date_to`. AALs are matched if `aal.date >= date_from AND aal.date <= date_to`.

- Budget line for March 2026 only: sees 5.68 GEL
- Budget line for Q1 2026: sees 5.68 GEL (only March is in Q1)
- Budget line for full year 2026: sees all 33 GEL across months

**Source:** [budget_report.py:88](../enterprise/account_budget/reports/budget_report.py#L88)

---

## Key Rules to Remember

1. **End date is inclusive and must be the last day of a month** — use `2026-12-31`, not `2027-01-01`
2. **Start date defaults to invoice date** if you only set an end date
3. **If all three dates (bill, start, end) are in the same month** — Odoo skips deferral entirely. The expense goes straight to P&L. This is correct behavior.
4. **The deferred account must have type = Prepayments** — not generic Current Assets
5. **The bill line account must have type = Expense** — the report only shows expense-type accounts
6. **Monthly amounts always sum to exactly the original total** — last period absorbs rounding
7. **VAT is never deferred** — only the net amount is spread across months. VAT hits the tax report on the bill date.
8. **Multi-currency bills** — deferral entries use the same company-currency balance as the original bill. The exchange rate is locked at billing date. No revaluation per period.
9. **Fiscal year end** — deferral entries cross fiscal years automatically. No special handling needed. A Jan–Dec annual subscription started in November will have entries in both the current and next fiscal year.
10. **Cron must run daily** — if the server is down, missed entries post on the next cron run. They do not accumulate errors, just delay by one day.

---

## Common Mistakes Quick Reference

| What went wrong | How to recognize it | How to fix it |
|---|---|---|
| Wrong date selected in report | Report is empty even though bill exists | Change report period to a specific month |
| Deferred account type is wrong | Report shows nothing, entries exist in DB | Set account type to "Prepayments" |
| Bill line account is wrong type | Entries exist but not in report | Bill line must use an Expense-type account |
| End date = first of next month | Warning on bill line, odd split amounts | Change to last day of last month |
| Bill date, start, end all same month | No entries created | Expected — extend date range to cover multiple months |
| Same account used for both roles | Entries zero out | Use separate Prepaid account for deferred side |
| Want to edit a grouped bill | Cannot reset to draft | Use credit note |
| Lock date set for past month | Monthly entry stays draft, error on the entry | Remove lock date or manually post the entry |
| Cron not running | All monthly entries stay draft | Settings → Technical → Scheduled Actions → verify "Post draft entries" is active and next run date is correct |
| Budget shows full cost on billing date instead of monthly | Analytic distribution not set on bill line | Set analytic distribution on the bill line before validation |
| VAT appears in wrong month's tax report | Should not happen — VAT always posts on bill date | Verify tax has `use_in_tax_closing = True` |

---

## Configuration Reference — All 8 Company Fields

All settings live on `res.company` and are exposed in Settings → Accounting → Deferred.

| Setting | Company field | Values | Notes |
|---|---|---|---|
| Deferred Expense Journal | `deferred_expense_journal_id` | Any journal | Required; raised as error if missing on validation |
| Deferred Expense Account | `deferred_expense_account_id` | Prepayments account | Must be type Prepayments |
| Expense Generation Method | `generate_deferred_expense_entries_method` | `on_validation` / `manually` | Per-type, independent of revenue setting |
| Expense Amount Method | `deferred_expense_amount_computation_method` | `day` / `month` / `full_months` | Controls proration |
| Deferred Revenue Journal | `deferred_revenue_journal_id` | Any journal | Required; raised as error if missing on validation |
| Deferred Revenue Account | `deferred_revenue_account_id` | Current liability account | Must be correct liability type |
| Revenue Generation Method | `generate_deferred_revenue_entries_method` | `on_validation` / `manually` | Independent of expense setting |
| Revenue Amount Method | `deferred_revenue_amount_computation_method` | `day` / `month` / `full_months` | Controls proration |

Source: [res_config_settings.py](../enterprise/account_accountant/models/res_config_settings.py)

---

## Technical Reference (for developers)

### Key files
- Generation logic: [account_move.py:274](../enterprise/account_accountant/models/account_move.py#L274) — `_generate_deferred_entries()`
- Report handler: [account_deferred_reports.py](../enterprise/account_reports/models/account_deferred_reports.py)
- Company settings: [res_config_settings.py](../enterprise/account_accountant/models/res_config_settings.py)

### Key fields on `account.move.line`
| Field | Purpose |
|---|---|
| `deferred_start_date` | When deferral begins. Auto-set to invoice date if only end date is filled. [account_move.py:551](../enterprise/account_accountant/models/account_move.py#L551) |
| `deferred_end_date` | When deferral ends (inclusive). [account_move.py:558](../enterprise/account_accountant/models/account_move.py#L558) |
| `has_deferred_moves` | True if parent move has generated deferral entries. [account_move.py:564](../enterprise/account_accountant/models/account_move.py#L564) |
| `has_abnormal_deferred_dates` | True if date range = N months + 1 day (likely off-by-one mistake). [account_move.py:674](../enterprise/account_accountant/models/account_move.py#L674) |

### Key fields on `account.move`
| Field | Purpose |
|---|---|
| `deferred_move_ids` | Many2many to generated deferral entries (relation: `account_move_deferred_rel`) |
| `deferred_original_move_ids` | Inverse — which original bills this deferral entry came from |
| `deferred_entry_type` | `expense` / `revenue` / `misc` / `False`. Computed from original move type. [account_move.py:162](../enterprise/account_accountant/models/account_move.py#L162) |

### Period generation
`_get_deferred_ends_of_month()` — [account_move.py:739](../enterprise/account_accountant/models/account_move.py#L739): returns last day of each calendar month in the date range. These become the `date` of each deferral move.

`_get_deferred_periods()` — [account_move.py:751](../enterprise/account_accountant/models/account_move.py#L751): returns `[]` if start/end/invoice all in same month (skip condition).

### Amount calculation
`_get_deferred_period_amount()` — [account_move.py:195](../enterprise/account_accountant/models/account_move.py#L195): handles `day`, `month`, `full_months`. Last period uses `force_balance = remaining` for exact rounding. [account_move.py:358](../enterprise/account_accountant/models/account_move.py#L358)

`_get_deferred_diff_dates()` — [account_move.py:176](../enterprise/account_accountant/models/account_move.py#L176): 30-day month normalization. Month-end days normalized to 30 so Feb/Mar/Apr get equal treatment.

### Report exclusion logic
`_get_domain_fully_inside_period()` — [account_deferred_reports.py:24](../enterprise/account_reports/models/account_deferred_reports.py#L24): excludes lines where start_date, end_date, AND move date are all within the selected period.

`is_already_generated` — SQL subquery [account_deferred_reports.py:83](../enterprise/account_reports/models/account_deferred_reports.py#L83): True when a deferral move exists for period end date that is posted or scheduled.

### Reset to draft
`button_draft()` — [account_move.py:120](../enterprise/account_accountant/models/account_move.py#L120): calls `_unlink_or_reverse()` on deferral entries. Posted entries are reversed; draft entries are deleted. Grouped entries (manual mode) block the reset with UserError.

### Tax suppression
`_get_computed_taxes()` — [account_move.py:793](../enterprise/account_accountant/models/account_move.py#L793): deferral moves with `deferred_original_move_ids` skip tax recomputation to prevent the expense account's default tax from generating new tax lines on each monthly recognition.

### Manual mode entry structure
`_generate_deferral_entry()` — [account_deferred_reports.py:498](../enterprise/account_reports/models/account_deferred_reports.py#L498): creates one grouped move + one automatic reversal (date + 1 day). Relation to original moves inserted via raw SQL to avoid ORM memory issues on large datasets. [account_deferred_reports.py:529](../enterprise/account_reports/models/account_deferred_reports.py#L529)

### Analytic distribution
Carried proportionally from original bill lines to all deferral entries. Ratio = `line_balance / total_key_amount`. [account_deferred_reports.py:568](../enterprise/account_reports/models/account_deferred_reports.py#L568)

### Mixed expense+income journal entry
If a manual journal entry contains both expense and income accounts with deferral dates, and the company has different generation methods for each type → UserError. [account_move.py:149](../enterprise/account_accountant/models/account_move.py#L149)

### `_has_deferred_compatible_account()` — When Date Fields Appear

Deferral fields (`deferred_start_date`, `deferred_end_date`) are only usable when:
- Purchase document (`in_invoice`, `in_refund`, `in_receipt`) → account must have `internal_group == 'expense'`
- Sale document (`out_invoice`, `out_refund`, `out_receipt`) → account must have `internal_group == 'income'`
- Journal entry → account must be `expense` OR `income`

If the account is wrong type, the `_onchange_deferred_start_date()` and `_onchange_deferred_end_date()` handlers clear the dates.

Source: [account_move.py:694](../enterprise/account_accountant/models/account_move.py#L694)

### `deferred_entry_type` Values

| Value | When | Meaning |
|---|---|---|
| `expense` | Original move is a vendor bill/receipt | Deferred expense entry |
| `revenue` | Original move is a customer invoice/receipt | Deferred revenue entry |
| `misc` | Original move is a journal entry OR entry combines bills of different types | Miscellaneous deferred entry |
| `False` | Not a deferral entry | Regular journal entry |

Source: [account_move.py:162](../enterprise/account_accountant/models/account_move.py#L162)

### Report Account Type Filters

The report domain (`_get_domain()`) only includes lines where account type is:

| Report | Account types included |
|---|---|
| Deferred Expenses | `expense`, `expense_depreciation`, `expense_direct_cost` |
| Deferred Revenue | `income`, `income_other` |

Wrong account type = the line exists in the DB but is invisible in the report.

Source: [account_deferred_reports.py:39](../enterprise/account_reports/models/account_deferred_reports.py#L39)

### `_get_deferred_diff_dates()` — 30-Day Month Algorithm

```python
# If start or end is the last day of their month, normalize to day 30
if start.day == last_day_of_month(start): start_day = 30
if end.day == last_day_of_month(end): end_day = 30

nb_months = end.month - start.month + 12 * (end.year - start.year)
nb_days = end_day - start_day
result = (nb_months * 30 + nb_days) / 30   # returns fractional months
```

This ensures Feb 28, March 31, and April 30 are all treated as "day 30" in their respective months, giving equal monthly weights. Source: [account_move.py:176](../enterprise/account_accountant/models/account_move.py#L176)

### `is_already_generated` — How the Report Detects Prior Generation

```sql
NOT EXISTS (
    SELECT 1 FROM account_move_deferred_rel AS amdr
    LEFT JOIN account_move AS am ON amdr.deferred_move_id = am.id
    WHERE amdr.original_move_id = account_move_line.move_id
      AND am.date = [report_date_to]
      AND (
          am.state = 'posted'
          OR (am.auto_post = 'at_date' AND am.date >= today)
      )
)
```

A deferral is "already generated" if a deferral entry exists dated at the period end that is either already posted OR scheduled for auto-posting in the future. This prevents duplicate generation.

Source: [account_deferred_reports.py:83](../enterprise/account_reports/models/account_deferred_reports.py#L83)

### Audit Trail Interaction

If audit trail protection is active on the company, deferral moves protected by it cannot be unlinked directly. Odoo detects this via `_is_protected_by_audit_trail()` and instead reverses the move before removing the link. This preserves audit trail integrity.

Source: [account_move.py:132](../enterprise/account_accountant/models/account_move.py#L132)

### On Validation — Exact Entry Sequence

For each bill line with deferral dates, `_generate_deferred_entries()` creates:

1. **Full reversal move** (dated = bill date, `auto_post='at_date'`)
   - CR expense account (removes from P&L), DR deferred account (parks on BS)
   - Posted immediately on validation

2. **N recognition moves** (one per period, dated = last day of each month, `auto_post='at_post'`)
   - DR expense account (moves to P&L), CR deferred account (clears from BS)
   - Last period: `force_balance = remaining_balance` to avoid rounding drift

Zero-amount moves are unlinked immediately after creation.

Source: [account_move.py:274](../enterprise/account_accountant/models/account_move.py#L274)

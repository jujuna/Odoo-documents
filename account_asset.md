# account_asset — Fixed Assets & Depreciation

> Source: `enterprise/account_asset/`
> Last updated: 2026-03-10

---

## The Core Idea — What Problem Does This Solve?

You buy a laptop for $1,200. It will last 3 years. Should that $1,200 hit your expenses all in January when you bought it? No — because you're going to use it for 36 months. Putting the full cost in January would make January look horribly expensive and the next 35 months look artificially cheap.

The solution: **spread the cost across the months you actually use it.** $1,200 ÷ 36 months = $33.33/month. That's depreciation.

```
WITHOUT depreciation:           WITH depreciation:
Jan:  −$1,200.00                Jan:  −$33.33
Feb:       $0.00                Feb:  −$33.33
Mar:       $0.00                Mar:  −$33.33
...                             ...every month for 3 years
```

**The accounting principle behind this:** match expenses to the period in which they were used (called the "matching principle").

---

## Asset or Expense? A Decision Guide

The rule is simple: **will you use it beyond the current accounting period?** If yes → asset. If no → expense.

| Purchase | Decision | Reason |
|---|---|---|
| Laptop, desktop computer | Asset | Lasts 3–5 years |
| Company car or van | Asset | Lasts many years |
| Office furniture | Asset | Lasts many years |
| Building renovation | Asset | Capital improvement, long life |
| Perpetual software license | Asset | Long-term intangible |
| Printer paper | Expense | Used up immediately |
| Annual software subscription | Expense | Already a monthly/yearly cost |
| Phone bill | Expense | Monthly service, consumed now |

---

## The Three Numbers That Matter

Every asset has three values you'll see constantly. Think of them like this:

```
You buy a laptop for $1,200. You estimate it'll be worth $200 as scrap at the end.
Only $1,000 will actually be "used up" over its life.

Original Value        = $1,200   ← what you paid
Not Depreciable Value = $200     ← salvage / what's left at end of life
Depreciable Value     = $1,000   ← original − salvage = what gets expensed over time

After 6 months of depreciation ($500 posted):
Depreciable Value (remaining) = $500   ← what's still left to expense
Book Value                    = $700   ← $500 remaining + $200 salvage
                                          (this is what the asset is worth on your books right now)
```

The key insight: **Book Value = what your balance sheet shows. It decreases every time a depreciation entry is posted.**

| Name in Odoo | What it is | Changes when? |
|---|---|---|
| Original Value | What you paid (+ any non-deductible taxes) | Set once at creation |
| Not Depreciable Value (Salvage) | Estimated scrap value at end of life | Set manually or by % model |
| Depreciable Value (header) | What's still left to depreciate | Decreases with each posted entry |
| Book Value | Current accounting worth | Decreases with each posted entry |

> **Important:** Depreciable Value and Book Value only change when entries are **posted** (confirmed). Draft entries sitting in the board have zero effect on these numbers.

---

## Asset Lifecycle — From Purchase to Disposal

Here's what happens to an asset from creation to end of life:

```
STEP 1: Asset Created
  ┌─────────────────────────────────────────────────────┐
  │  Draft                                              │
  │  Asset exists but depreciation hasn't started.      │
  │  You can still edit everything.                     │
  └─────────────────────────────────────────────────────┘
                          │
                   Click "Confirm"
                          │
                          ▼
STEP 2: Asset Running
  ┌─────────────────────────────────────────────────────┐
  │  Running (open)                                     │
  │  Odoo generates the full depreciation schedule.     │
  │  Every night, the system posts entries that are due. │
  └─────────────────────────────────────────────────────┘
          │              │              │
       Pause          Sell          Dispose
          │              │              │
          ▼              ▼              ▼
STEP 3: Paused        Closed         Closed
  Depreciation      Asset sold.    Asset scrapped.
  temporarily       Gain/loss      No money
  stopped.          recorded.      received.
          │
       Resume
          │
          ▼
  Back to Running

(You can also Cancel an asset at any time — reverses all entries.)
```

| Status | Technical name | What it means in plain terms |
|---|---|---|
| Model | `model` | A template. Not a real asset — used to pre-fill settings when creating new assets |
| Draft | `draft` | Asset created but not started. You can still change everything |
| Running | `open` | Active. Depreciation is happening automatically every month |
| On Hold | `paused` | Temporarily stopped. Clock pauses. Future entries shift forward |
| Closed | `close` | Fully depreciated or sold/disposed. Done |
| Cancelled | `cancelled` | All entries reversed. As if the asset never existed |

---

## The Depreciation Board Tab — What It Is and How to Read It

The Depreciation Board is a **pre-generated schedule of all future expense entries** for the asset. When you confirm an asset, Odoo immediately creates the entire plan — every single monthly (or yearly) journal entry — as draft `account.move` records. Think of it like a loan amortization table in reverse: instead of paying off a debt, you're "using up" an asset's value over time.

### What Each Row Represents

Each row is a **journal entry** (`account.move`) that will eventually be posted to your books.

| Column | Field | What it tells you |
|---|---|---|
| Date | `date` | Last day of the period this entry covers (e.g., Mar 31) |
| Ref | `ref` | Optional reference label |
| Depreciation | `depreciation_value` | How much expense is recognized THIS period only |
| Cumulative Depreciation | `asset_depreciated_value` | Running total of ALL depreciation from start to this row |
| Remaining Value | `asset_remaining_value` | What's still left to depreciate AFTER this row |
| Journal Entry | `name` | Clickable link to the actual `account.move` record |

Visual cues in the list:
- Blue text = Draft (planned, not yet in your books)
- Normal text = Posted (locked in your accounting)
- Faded text = Cancelled

Source: [account_asset_views.xml:253-267](../enterprise/account_asset/views/account_asset_views.xml#L253)

### Draft vs. Posted — Why It Matters

**Draft row** = "This is planned but hasn't happened yet." Zero effect on your P&L, balance sheet, or the Book Value / Depreciable Value numbers in the header.

**Posted row** = "This expense is recorded." Each posted row creates this journal entry:
```
Debit   Depreciation Expense (P&L)      $1,000
Credit  Accumulated Depreciation (BS)   $1,000
```
Your profit decreases, and the asset's balance sheet value drops.

### The Board In Action — Step-by-Step Example

**Machine: $12,000, 12 months, no salvage, starting Jan 1**

The moment you confirm, Odoo generates 12 rows:
```
Row  | Date     | Depreciation | Cumulative | Remaining | Status
-----|----------|-------------|------------|-----------|-------
1    | Jan 31   | $1,000      | $1,000     | $11,000   | Posted  ← date passed
2    | Feb 28   | $1,000      | $2,000     | $10,000   | Posted  ← date passed
3    | Mar 31   | $1,000      | $3,000     |  $9,000   | Posted  ← date passed
4    | Apr 30   | $1,000      | $4,000     |  $8,000   | Draft   ← future
...
12   | Dec 31   | $1,000      | $12,000    |      $0   | Draft   ← last row
```

All 12 exist immediately as drafts. Every night, the cron job posts any row whose date <= today. If today is March 15, rows 1-3 are Posted and rows 4-12 are still Draft.

### Prorata — Partial First Period

If the asset starts mid-month, the first row covers only the remaining days.

**Example: Laptop $1,000, 10 months, starting March 10**

```
Date       | Amount  | Cumulative | Remaining
-----------|---------|------------|----------
Mar 31     |  $71.00 |    $71.00  |  $929.00   ← partial month (March 10-31)
Apr 30     | $100.00 |   $171.00  |  $829.00
May 31     | $100.00 |   $271.00  |  $729.00
Jun 30     | $100.00 |   $371.00  |  $629.00
Jul 31     | $100.00 |   $471.00  |  $529.00
Aug 31     | $100.00 |   $571.00  |  $429.00
Sep 30     | $100.00 |   $671.00  |  $329.00
Oct 31     | $100.00 |   $771.00  |  $229.00
Nov 30     | $100.00 |   $871.00  |  $129.00
Dec 31     | $100.00 |   $971.00  |   $29.00
Jan 31     |  $29.00 | $1,000.00  |    $0.00   ← asset closes automatically
```

**Why 11 rows for 10 months?** The first partial month + the leftover in January together equal one full $100 month. The total always equals exactly $1,000.

### The Last Row Must Reach Zero

The last row's Remaining Value must always be exactly $0. This is enforced by a constraint ([account_asset.py:449-458](../enterprise/account_asset/models/account_asset.py#L449)). If it's not zero, Odoo raises an error — the schedule is broken.

### What Happens Every Night (Auto-Posting)

Odoo runs a background job (cron) every day around 2:00 AM. It looks for any depreciation entry whose date has passed and posts it automatically. You don't need to do anything — **depreciation posts itself on schedule**.

### How the Board Is Computed Internally

When you confirm an asset (or recompute after a modification):

1. `compute_depreciation_board()` ([account_asset.py:638](../enterprise/account_asset/models/account_asset.py#L638)) deletes all future draft moves
2. `_recompute_board()` ([account_asset.py:651](../enterprise/account_asset/models/account_asset.py#L651)) loops through each period:
   - Calls `_compute_board_amount()` to calculate the amount based on the depreciation method
   - Linear: equal amounts each period (proportional to days)
   - Degressive: percentage of remaining value (higher early, lower later)
   - Degressive-then-linear: `max(degressive, linear)` — switches when linear becomes larger
3. Creates `account.move` records for each period
4. Auto-posts any moves whose date <= today

Cumulative values (`asset_depreciated_value`, `asset_remaining_value`) are computed fields that iterate through all moves in date order — see [account_move.py:49-67](../enterprise/account_asset/models/account_move.py#L49).

---

## Three Depreciation Methods

### Method 1: Straight Line (most common)

Equal amounts every period. Simple and predictable.

```
Monthly expense = Total to depreciate ÷ Number of months

$1,000 over 10 months = $100/month (every month, same amount)
```

**When to use:** furniture, buildings, equipment — anything that ages evenly.

### Method 2: Declining Balance (faster depreciation early on)

Instead of a fixed amount, takes a fixed **percentage of whatever's left**. This means you depreciate more in the early years and less later.

```
Rate = 30% per year

Year 1: $1,000 × 30% = $300 expense → $700 remaining
Year 2: $700  × 30% = $210 expense → $490 remaining
Year 3: $490  × 30% = $147 expense → $343 remaining
...keeps going, never fully reaches zero on its own
```

**When to use:** vehicles, computers, technology — things that lose value faster early on.

### Method 3: Declining then Straight Line

Starts like Method 2 (declining). Once the straight-line amount would be bigger than the declining amount, it automatically switches to straight line. This guarantees the asset reaches exactly $0.

```
When declining gives $50/month but straight-line would give $80/month:
→ switch to $80/month (whichever is larger wins)
```

**When to use:** required by law in some countries (France, Belgium, etc.).

---

## How the First/Last Period Is Calculated (Prorata)

If your asset starts on the 15th of a month, you don't depreciate the full month — only the days you actually used it. Odoo calls this "prorata computation."

| Setting | Name | How it works |
|---|---|---|
| Based on days | `daily_computation` | Counts actual calendar days |
| Based on months | `constant_periods` | Treats every month as 30 days, year as 360 days |
| No Prorata | `none` | Always starts at the beginning of the fiscal year — first period is always full |

**Practical difference:**
- "Based on days": February has 28 days, March has 31 — they count differently
- "Based on months": every month counts as exactly 30 days regardless of actual length

---

## What Happens When You Pause an Asset?

Sometimes an asset isn't being used — equipment in storage, a car being repaired for months. You can pause depreciation.

**When you pause:**
1. Odoo posts a partial depreciation entry for the days used so far in the current period
2. All future draft entries are deleted
3. The asset is frozen

**When you resume:**
1. Odoo calculates how many days the asset was paused
2. Shifts every future entry forward by exactly those days
3. Regenerates the full schedule
4. Resumes posting automatically

The pause duration is stored and accumulated — if you pause twice, both periods shift the schedule.

---

## Selling or Disposing of an Asset

### Disposing (Scrapping)

You throw away or scrap the asset. No money comes in.

What Odoo posts:
```
1. Final depreciation entry (for the partial period up to disposal date)

2. Closing entry:
   DR  Accumulated Depreciation    (all the depreciation posted so far)
   DR  Loss on Disposal            (if book value > 0 at time of disposal)
   CR  Asset Account               (the original purchase cost)
```

### Selling

You sell the asset to someone. A customer invoice is involved.

```
1. Final depreciation entry (partial period up to sale date)

2. Closing entry:
   DR  Accumulated Depreciation    (all depreciation so far)
   CR  Asset Account               (original cost — removes it from books)
   CR  Sale Proceeds               (linked to customer invoice line)
   CR  Gain on Sale                (if you sold for MORE than book value)
   -- OR --
   DR  Loss on Sale                (if you sold for LESS than book value)
```

**Example:**
```
Original cost: $1,200
Accumulated depreciation so far: $900
Book value at time of sale: $300
Selling price: $400

→ Gain on Sale = $400 − $300 = $100
```

The gain/loss accounts are configured at the company level (Settings → Accounting).

---

## Re-evaluating an Asset (Changing Its Value)

Life happens — an asset gets renovated and is worth more, or it gets damaged and is worth less. You can re-evaluate a running asset.

### Value Goes UP

Example: You spent $5,000 renovating a building. The building's asset needs to increase.

What Odoo does:
1. Posts depreciation up to today (covers the period before the change)
2. Creates a **journal entry** recording the value increase
3. Creates a **new child asset** for the increase amount — this child depreciates in parallel, following the same schedule as the parent
4. Recomputes future entries for the remaining life

The child asset appears under "Gross Increase" on the parent asset form.

### Value Goes DOWN

Example: Equipment damaged, worth less than books show.

What Odoo does:
1. Posts depreciation up to today
2. Posts an immediate write-down entry (reduces book value now)
3. Recomputes future entries with lower amounts spread across remaining life

---

## Creating Assets From Vendor Bills (Automatic Flow)

This is the most efficient way. Instead of manually creating assets, Odoo creates them automatically when you post a vendor bill — IF the account on the bill is configured correctly.

**Setup on the account (Chart of Accounts → edit):**

| Setting | Effect |
|---|---|
| "No" | Nothing happens — bill posts normally |
| "Create in draft" | Asset is created in Draft — you still need to manually confirm it |
| "Create and validate" | Asset is created AND confirmed automatically — depreciation starts right away |
| "Multiple Assets per Line" | If you bought 5 laptops on one line, creates 5 separate assets (one per unit) |
| "Asset Models" | Links a template — the asset is pre-filled with the template's settings |

**The automatic flow:**
```
You receive vendor bill for 3 laptops → post the bill
  ↓
Odoo sees the account is configured as "Create and validate"
  ↓
Creates 3 assets (one per laptop), fills from the linked template
  ↓
Confirms all 3 automatically — depreciation schedule generated
  ↓
Each night: entries that are due get posted automatically
```

**When auto-creation does NOT trigger:**
- Account type is not "Fixed Asset" or "Non-current Asset"
- The line amount is zero
- The line is a tax line
- It's a customer invoice (not a vendor bill)

---

## Using Asset Templates (Models)

Instead of filling the same settings every time (method, period, accounts...), you can create a **Model** — a template.

**How to create a template:** open any asset → "Save as Model" button.

**What the template stores:** depreciation method, duration, accounts, journal, prorata type.

**How to use it:** when creating a new asset, select the model in the "Model" field → all settings are pre-filled.

**Most powerful use:** link the model to an account in the Chart of Accounts. Every bill posted on that account auto-creates an asset already filled with the right settings.

---

## Asset Groups — Organizing Your Assets

You can organize assets into groups (e.g., "Vehicles", "IT Equipment", "Furniture").

- Go to Accounting → Configuration → Asset Groups
- Each group is just a name + list of assets
- Set `Asset Group` on individual asset forms
- Groups appear as filters in the asset list view

Groups don't affect depreciation calculation — they're purely for organization and reporting.

---

## Non-Deductible Taxes and Asset Cost

In some countries, certain taxes are not fully deductible. For example, in Belgium, 50% of car-related taxes cannot be claimed as an expense. That 50% must be capitalized — added to the asset cost.

**What Odoo does automatically:**
```
Car purchase: $10,000 + $2,100 VAT (50% non-deductible)
Non-deductible portion: $2,100 × 50% = $1,050

Asset original_value = $10,000 + $1,050 = $11,050
```

Odoo adds a note in the asset's chatter explaining why the original value doesn't match the purchase amount.

---

## Migrating From Another System

If you're importing existing assets that were already partially depreciated in another system, use the **"Already Depreciated Amount"** field.

**Example:** Asset has been running for 2 years in your old system. $800 already depreciated. You want to import it into Odoo with the remaining $200 still to depreciate.

- Set `already_depreciated_amount_import = $800`
- Odoo will start the board from the correct remaining position
- The board will reflect that $800 was already expensed (shown as cumulative)
- Only the remaining $200 will generate new entries

---

## Full Flow Summary — From Purchase to Closure

```
PURCHASE
  ↓ (vendor bill posted on fixed asset account)
ASSET CREATED (Draft)
  ↓ (review: check method, duration, salvage value)
CONFIRM
  ↓
DEPRECIATION BOARD GENERATED
  All future entries created as drafts with future dates
  ↓
EVERY NIGHT (automated cron)
  Any entry with date ≤ today → posted automatically
  ↓
MODIFICATIONS (if needed):
  ├─ Value changed? → Re-evaluate (Modify Asset button)
  ├─ Taking it out of service temporarily? → Pause
  ├─ Back in service? → Resume
  ├─ Sold? → Sell (link to customer invoice)
  └─ Scrapped? → Dispose
  ↓
LAST ENTRY POSTED
  Asset automatically moves to Closed state
  Book value = $0
  (Salvage value is released at disposal)
```

---

## What Each Button Does on the Asset Form

| Button / Action | When to use it | What it does |
|---|---|---|
| **Confirm** | After reviewing a draft asset | Locks settings, generates full depreciation schedule, starts automatic posting |
| **Modify Asset** | Any time on a running asset | Opens wizard for: sell, dispose, re-evaluate, pause |
| **Pause** (in wizard) | Asset temporarily out of use | Posts partial current-period entry, freezes future entries |
| **Resume** (separate button) | After a pause | Shifts future entries forward by paused days, restarts |
| **Sell** (in wizard) | Asset sold to a customer | Needs a customer invoice; records gain/loss |
| **Dispose** (in wizard) | Asset scrapped/thrown away | No invoice needed; records loss if book value > 0 |
| **Re-evaluate** (in wizard) | Value or duration changes | Adjusts future schedule; creates child asset if value increased |
| **Cancel** | Mistake — asset should not exist | Reverses ALL posted entries; resets everything |
| **Set to Draft** | Need to edit a confirmed asset | Reverts to draft (only if no posted entries) |
| **Save as Model** | Create a reusable template | Saves current settings as a template for future assets |

---

## The Journal Entries Behind the Scenes

You don't need to create any journal entries manually. Odoo handles all of them. But here's what actually happens in your accounting:

**Every depreciation period:**
```
Debit   Depreciation Expense (P&L)          $100
Credit  Accumulated Depreciation (BS)        $100
```
- The expense account reduces your profit this month
- The balance sheet shows the asset at original cost minus accumulated depreciation

**Your balance sheet looks like:**
```
Assets:
  Equipment (original cost)          $1,200
  Less: Accumulated Depreciation      ($300)
  Net Book Value                       $900
```

**At disposal (scrapping):**
```
Debit   Accumulated Depreciation     $1,000   (all depreciation so far)
Debit   Loss on Disposal               $200   (remaining book value = gone)
Credit  Equipment Account            $1,200   (removes original cost from books)
```

**At sale (sold for $250, book value was $200):**
```
Debit   Accumulated Depreciation     $1,000
Credit  Equipment Account            $1,200
Credit  Cash / AR                     $250    (sale proceeds)
Credit  Gain on Sale                   $50    ($250 − $200 book value)
```

---

## Where to Find Everything in Odoo

| Menu / Location | Purpose |
|---|---|
| Accounting → Assets | List of all your assets; create new ones |
| Accounting → Assets → (open asset) | See the asset form, depreciation board, history |
| Asset form → Depreciation Board tab | All scheduled entries — past (posted) and future (draft) |
| Asset form → Modify Asset button | Sell, dispose, pause, re-evaluate |
| Asset form → Gross Increase button | Child assets from re-evaluations |
| Asset form → Posted Entries button | The actual journal entries that were posted |
| Accounting → Configuration → Asset Groups | Create/manage groups like "Vehicles", "IT" |
| Chart of Accounts → (edit account) → Assets tab | Configure auto-creation from bills |
| Accounting → Reporting → Assets Report | Overview of all assets with current book values |
| Journal Items list → Action → Turn as an Asset | Manually convert a posted journal item into an asset |

---

## Common Mistakes and How to Avoid Them

**"I confirmed the asset but the depreciation board looks wrong"**
→ You cannot edit most fields after confirming. Use "Modify Asset → Re-evaluate" to change duration, value, or salvage.

**"The Depreciable Value on the header isn't changing"**
→ It only changes when entries are **posted** (either manually or by the nightly cron). Draft entries don't count.

**"I have 10 months of depreciation but there are 11 rows in the board"**
→ Normal. If the asset started mid-month, the first partial period + the leftover in the last period together equal one full period.

**"Book Value is 0 even though I set a salvage value"**
→ After the asset is fully closed and disposed, book value becomes 0. The salvage value was released at disposal.

**"I need to sell an asset that has a gross increase child"**
→ You must Dispose the child asset(s) first. Then sell the parent.

**"The bill was posted but no asset was created"**
→ Check: is the account type "Fixed Asset" or "Non-current Asset"? Is `create_asset` set to something other than "No"?

**"I want to delete an asset but Odoo won't let me"**
→ You can't delete running, paused, or closed assets. First cancel it, then delete if needed.

---

## Technical Reference (for Developers)

### Core Model Fields — `account.asset`

| Field | Type | Purpose |
|---|---|---|
| `state` | Selection | `model/draft/open/paused/close/cancelled` |
| `method` | Selection | `linear / degressive / degressive_then_linear` |
| `method_number` | Integer | Number of depreciation periods |
| `method_period` | Selection | `'1'` = monthly, `'12'` = yearly (stored as string) |
| `method_progress_factor` | Float | Declining rate (e.g., `0.3` = 30%) |
| `prorata_computation_type` | Selection | `none / constant_periods / daily_computation` |
| `prorata_date` | Date | Depreciation start date (may = fiscal year start for `none`) |
| `paused_prorata_date` | Date (computed) | `prorata_date` shifted forward by all accumulated paused days |
| `acquisition_date` | Date | Purchase date |
| `original_value` | Monetary | Cost + non-deductible taxes |
| `salvage_value` | Monetary | Non-depreciable residual |
| `salvage_value_pct` | Float | Auto-compute salvage as % of original (set on models only) |
| `value_residual` | Monetary (computed) | Remaining depreciable — updated only on posted entries |
| `book_value` | Monetary (computed, stored) | `value_residual + salvage + children.book_value` |
| `total_depreciable_value` | Monetary (computed) | `original_value − salvage_value` |
| `already_depreciated_amount_import` | Monetary | For migrations: pre-existing depreciation |
| `asset_paused_days` | Float | Accumulated days paused |
| `asset_lifetime_days` | Float (computed) | Total days in the full schedule |
| `parent_id` | Many2one | Set when this is a gross increase child |
| `children_ids` | One2many | Gross increase child assets |
| `asset_group_id` | Many2one | Optional group (e.g., "Vehicles") |
| `depreciation_move_ids` | One2many | All journal entries (draft + posted) |
| `original_move_line_ids` | Many2many | Bill line(s) that created this asset |
| `net_gain_on_sale` | Monetary | `selling_price − book_value` recorded at sale |

### `account.move` Fields Added by this Module

| Field | Purpose |
|---|---|
| `asset_id` | The asset this entry belongs to |
| `depreciation_value` | Expense for this period |
| `asset_depreciated_value` | Cumulative depreciation up to this row |
| `asset_remaining_value` | What's still left to depreciate after this row |
| `asset_depreciation_beginning_date` | Start of the period this entry covers |
| `asset_move_type` | `depreciation / purchase / sale / disposal / positive_revaluation / negative_revaluation` |
| `asset_value_change` | True if this entry is a re-evaluation (not regular depreciation) |

### Key Methods

| Method | File | What it does |
|---|---|---|
| `validate()` | [account_asset.py:857](../enterprise/account_asset/models/account_asset.py#L857) | Confirms asset, generates board, posts past entries |
| `compute_depreciation_board()` | [account_asset.py:638](../enterprise/account_asset/models/account_asset.py#L638) | Deletes future drafts, regenerates full schedule |
| `_recompute_board()` | [account_asset.py:651](../enterprise/account_asset/models/account_asset.py#L651) | Core loop — one entry dict per period |
| `_compute_board_amount()` | [account_asset.py:568](../enterprise/account_asset/models/account_asset.py#L568) | Amount for one period (all 3 methods) |
| `_get_linear_amount()` | [account_asset.py:554](../enterprise/account_asset/models/account_asset.py#L554) | Linear amount via cumulative subtraction (avoids rounding drift) |
| `_degressive_linear_amount()` | [account_asset.py:1185](../enterprise/account_asset/models/account_asset.py#L1185) | `max(degressive, linear)` for method 3 |
| `_get_end_period_date()` | [account_asset.py:712](../enterprise/account_asset/models/account_asset.py#L712) | End of period: month-end or fiscal year-end |
| `_get_delta_days()` | [account_asset.py:726](../enterprise/account_asset/models/account_asset.py#L726) | Days between dates (actual or 30-day month) |
| `_get_last_day_asset()` | [account_asset.py:752](../enterprise/account_asset/models/account_asset.py#L752) | Last day of the full depreciation schedule |
| `_get_residual_value_at_date()` | [account_asset.py:1203](../enterprise/account_asset/models/account_asset.py#L1203) | Interpolated theoretical value at any mid-period date |
| `_create_move_before_date()` | [account_asset.py:1044](../enterprise/account_asset/models/account_asset.py#L1044) | Posts partial depreciation up to a date (pause/sell/dispose) |
| `_cancel_future_moves()` | [account_asset.py:1101](../enterprise/account_asset/models/account_asset.py#L1101) | Deletes drafts + reverses posted entries after a date |
| `_get_disposal_moves()` | [account_asset.py:1117](../enterprise/account_asset/models/account_asset.py#L1117) | Builds closing disposal/sale journal entry |
| `_auto_create_asset()` | [account_move.py:194](../enterprise/account_asset/models/account_move.py#L194) | Creates assets from a posted bill |
| `set_to_close()` | [account_asset.py:889](../enterprise/account_asset/models/account_asset.py#L889) | Sells or disposes, creates closing entry |
| `set_to_cancelled()` | [account_asset.py:925](../enterprise/account_asset/models/account_asset.py#L925) | Reverses all posted entries, resets state |
| `pause()` | [account_asset.py:983](../enterprise/account_asset/models/account_asset.py#L983) | Posts partial entry, sets state to paused |
| `resume_after_pause()` | [account_asset.py:974](../enterprise/account_asset/models/account_asset.py#L974) | Opens resume wizard |
| `asset_modify.modify()` | [asset_modify.py:231](../enterprise/account_asset/wizard/asset_modify.py#L231) | Full re-evaluation: intermediate entry, child asset, board recompute |
| `asset_modify.sell_dispose()` | [asset_modify.py:387](../enterprise/account_asset/wizard/asset_modify.py#L387) | Calls `set_to_close()` with or without invoice |

### Account Configuration Fields (`account.account`)

| Field | Values | Meaning |
|---|---|---|
| `create_asset` | `no / draft / validate` | Whether and how to auto-create assets from bills |
| `multiple_assets_per_line` | Boolean | One asset per unit qty (qty rounded down to int) |
| `asset_model_ids` | Many2many | Templates to use; one asset per template per bill line |
| `can_create_asset` | Computed Boolean | True only for account types `asset_fixed` or `asset_non_current` |

### Company-Level Fields (`res.company`)

| Field | Purpose |
|---|---|
| `gain_account_id` | Account for gain on asset sale |
| `loss_account_id` | Account for loss on asset sale |

Both are editable in the Modify Asset wizard and save back to the company on change.

### Write Override Behavior

Changing `account_depreciation_id`, `account_depreciation_expense_id`, or `journal_id` on a running asset propagates automatically to all **future draft** entries.
Changing `analytic_distribution` propagates to all draft entries.

Source: [account_asset.py:530-548](../enterprise/account_asset/models/account_asset.py#L530)

### Reverse Entry Behavior

When you reverse a posted depreciation entry:
- If a draft entry exists → its amount increases by the reversed amount
- If no draft exists (and asset isn't closing) → a new draft entry is created at the end of the next period

Source: [account_move.py:139-172](../enterprise/account_asset/models/account_move.py#L139)

### `_get_delta_days()` — 30-day Month Formula (constant_periods)

```
start_prorata = (days_in_start_month - start_day + 1) / days_in_start_month
end_prorata   = end_day / days_in_end_month

delta = (start_prorata × 30) + (end_prorata × 30)
      + (end_year - start_year) × 360
      + (end_month - start_month - 1) × 30
```

### Constraints Summary

| Constraint | Rule |
|---|---|
| `_check_depreciations` | Last entry must have `asset_remaining_value == 0` for open assets |
| `_constrains_check_asset_state` | Cannot post entry linked to a draft asset |
| `_check_active` | Cannot archive unless state is `close` or `model` |
| `_check_related_purchase` | Cannot add/remove bill lines after confirming |
| `_unlink_if_model_or_draft` | Cannot delete open/paused/closed assets |
| Deletion with posted entries | Cannot delete if any posted entries exist |
| Lock date | Cannot re-evaluate/sell/dispose before fiscal lock date |
| Sell with children | Must dispose children before selling parent |
| Future posted entries | Cannot open wizard if there are unreversed future posted entries |

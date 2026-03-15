# Stock Valuation (Inventory Valuation)

> **Module:** `stock_account` + `stock_landed_costs` | **Path:** [`addons/stock_account/`](../addons/stock_account/) + [`addons/stock_landed_costs/`](../addons/stock_landed_costs/)
> **Odoo Apps category:** Inventory / Accounting

## How to Read This Document

This doc is organized **top-down**: business concepts first, then technical details.

- **Sections 1-9 (up to "Decision Matrix")** -- Pure business logic. No code. Read these to understand what stock valuation IS and why it exists.
- **"What Accounts Are Involved"** -- The bridge between business and code. Explains the accounting entries in plain English.
- **"Core Concepts" onward** -- Technical reference. Models, fields, methods, code traces. Come back here when you need to understand HOW Odoo implements a concept.

If you're learning Odoo business flows, read straight through the walkthroughs. Each one builds on the previous. If you already know accounting, skip to the Decision Matrix and then the walkthroughs for your use case.

---

## What It Does

Tracks the monetary value of inventory as products move between locations. Assigns a cost to every stock move using one of three costing methods (Standard, FIFO, Average). When configured for perpetual (real-time) valuation, automatically creates journal entries that keep the balance sheet in sync with physical stock. Supports lot-level valuation, landed cost allocation, and periodic closing for companies that don't use perpetual mode.

**Odoo 19 architecture note:** There is no `stock.valuation.layer` model. Valuation is computed directly on `stock.move` fields (`value`, `remaining_qty`, `remaining_value`). Historical adjustments are tracked via `product.value` records. All cost calculations (FIFO stack, AVCO average) are computed on-the-fly from move history.

---

## Why Inventory Valuation Matters (Business Context)

Every company that holds physical stock needs to answer two questions for accounting:

1. **How much is the inventory on our balance sheet worth right now?** (Balance Sheet -- Current Assets)
2. **When we sell something, what did it cost us?** (Profit & Loss -- Cost of Goods Sold)

Without inventory valuation, a company knows what it sold products *for* (revenue) but not what those products *cost* (expense). That means no accurate profit margin, no correct financial statements, and no way to pass an audit.

Odoo's `stock_account` module bridges the gap between the warehouse (physical goods) and accounting (financial records). Every time goods enter or leave the warehouse, the system can optionally create a journal entry that moves value between accounts.

---

## The Two Big Decisions

Before using inventory valuation, a company must make two choices. These are set per product category (so different product types can use different rules).

### Decision 1: When Should Accounting Know About Stock Changes?

| Choice | Name | How it works | Best for |
|---|---|---|---|
| **After the fact** | Periodic (at closing) | No journal entries during daily operations. At the end of the month/quarter, an accountant runs a "closing" that compares physical inventory value to the books and posts the difference. | Small companies, companies with an accountant who reconciles manually, companies that don't need real-time financial reporting. |
| **Immediately** | Perpetual (real-time) | Every time a receipt or delivery is validated, Odoo automatically creates a journal entry. The balance sheet is always up to date. | Companies that need real-time financial visibility, companies with auditors who expect automated inventory tracking, any company using FIFO or AVCO seriously. |

**Where to set it:** Inventory > Configuration > Product Categories > "Inventory Valuation" field.

### Decision 2: How Should We Calculate the Cost of Each Unit?

This is the "costing method." It determines what cost Odoo assigns when you send a product out the door.

| Method | Plain English | Best for | Example |
|---|---|---|---|
| **Standard Price** | Every unit costs the same fixed amount. You set the price manually and it stays until you change it. | Manufacturing (where you set planned costs), simple businesses with stable purchase prices, companies that don't track actual purchase cost per receipt. | You set "Desk Lamp" cost = $25. No matter if you bought some for $23 and some for $27, Odoo values every lamp at $25 until you change it. |
| **First In First Out (FIFO)** | The oldest purchase cost is used first when you sell. Each receipt keeps its actual cost, and deliveries "consume" from the oldest receipt forward. | Trading companies, retail, any business where purchase prices change often and you want actual cost tracking. Required for accurate cost reporting in most industries. | You bought 10 lamps at $23, then 10 at $27. When you sell 12, Odoo costs 10 at $23 + 2 at $27 = $284. |
| **Average Cost (AVCO)** | Every receipt recalculates a running weighted average. All units in stock share the same average cost. | Companies that buy the same product frequently at varying prices and want a smoothed cost. Common in food/commodity industries. | You have 10 lamps at $23 ($230 total). You buy 10 more at $27 ($270 total). New average = $500 / 20 = $25/unit. |

**Where to set it:** Inventory > Configuration > Product Categories > "Costing Method" field.

---

## Anglo-Saxon vs Continental Accounting

This is a fundamental configuration that changes **when expenses are recognized**. Think of it this way:

> **Anglo-Saxon** = "I'll record the expense only when I sell the product" (cost stays on balance sheet until sale)
> **Continental** = "I'll record the expense when I buy the product" (cost goes to P&L immediately, then adjusted at period end)

**Why does this matter?** It determines how your financial statements look during the month. Anglo-Saxon shows inventory as an asset and only converts it to expense (COGS) when you invoice a customer. Continental records the purchase as an expense right away, then adjusts at month-end.

| Aspect | Anglo-Saxon (Perpetual) | Continental |
|---|---|---|
| **When is expense recognized?** | At invoice time -- COGS lines auto-generated | At period closing -- variation entry posted |
| **Purchase bill account** | Stock Valuation account (deferred to sale) | Expense account (immediately expensed) |
| **COGS lines on invoice?** | Yes (`display_type='cogs'`) | No |
| **Configuration** | `company.anglo_saxon_accounting = True` | `False` (default) |
| **Typical use** | US, UK, Australia, international IFRS | France, Germany, Belgium, many EU countries |
| **Purchase price difference** | Standard cost only -- posted to price diff account | Not applicable |

Source: [`account/models/company.py`](../addons/account/models/company.py) -- `anglo_saxon_accounting` field

### How It Affects the Purchase Flow

**Anglo-Saxon -- step by step:**
1. You receive goods -> Journal entry moves value INTO Stock Valuation (balance sheet asset)
2. You get the vendor bill -> Bill debits Stock Valuation (not Expense!), credits AP
3. The cost sits on the balance sheet until you sell the product
4. Only when you invoice a customer does the cost move from Stock Valuation to COGS (expense)

**Continental -- step by step:**
1. You receive goods -> Same journal entry as Anglo-Saxon (Stock Valuation increases)
2. You get the vendor bill -> Bill debits **Expense** (P&L), credits AP -- cost is expensed NOW
3. At month-end, accountant runs closing -> Adjusting entry reconciles the stock variation
4. No COGS lines are auto-generated on customer invoices

**The practical difference:** Mid-month, Anglo-Saxon shows accurate inventory value on the balance sheet. Continental shows the purchase as an expense immediately, which means your P&L fluctuates with purchases, not sales.

### How It Affects the Sale Flow

**Anglo-Saxon:** On customer invoice posting, auto-generated COGS lines move cost from Stock Valuation to Expense. This is the moment the "cost of the sale" appears on the P&L. Source: [`_stock_account_prepare_realtime_out_lines_vals()`](../addons/stock_account/models/account_move.py#L68-L160)

**Continental:** No COGS lines on invoice. At period closing, `_get_continental_realtime_variation_vals()` posts the cumulative inventory variation. The P&L only shows accurate cost-of-sales figures after the closing is run. Source: [`res_company.py:258-304`](../addons/stock_account/models/res_company.py#L258-L304)

### Purchase Price Difference (Anglo-Saxon + Standard Cost Only)

When a vendor bill price differs from `standard_price`, Odoo creates price difference lines on the bill.

Source: [`purchase_stock/models/account_invoice.py:12-106`](../addons/purchase_stock/models/account_invoice.py#L12-L106)

**Condition:** `anglo_saxon_accounting = True` AND `cost_method == 'standard'`

**Example:** Product standard price = $9, vendor bills $10:
```
Original bill line:    Debit Stock Valuation $10, Credit AP $10
Price diff lines:      Debit Price Difference $1, Credit Stock Valuation $1
Net effect:            Stock Valuation = $9 (standard), Price Diff = $1 (variance)
```

The price difference account comes from `product.categ_id.property_price_difference_account_id`. If not set, the expense account is used as fallback.

Source: [`account_invoice.py:49-54`](../addons/purchase_stock/models/account_invoice.py#L49-L54)

---

## Complete Business Flow Walkthroughs

These walkthroughs follow real user actions in the Odoo UI, explaining what happens behind the scenes at each step.

---

### Walkthrough 1: "I Buy Products and Sell Them" (Trading Company, Perpetual + AVCO)

This is the most common scenario. A company buys goods from suppliers and resells them to customers.

**The complete lifecycle in one sentence:** You buy goods (inventory increases on balance sheet) -> you receive the bill (confirms the cost) -> you sell goods (inventory decreases, COGS appears on P&L) -> you invoice the customer (COGS journal entry auto-created, revenue recorded).

**Setup:**
- Product Category "Merchandise": Costing Method = Average Cost (AVCO), Inventory Valuation = Perpetual
- Product "USB Cable": Category = Merchandise, Sale Price = $15
- Accounts configured: Stock Valuation = 1400, COGS/Expense = 5100, Revenue = 4000

#### Step 1: First Purchase (PO + Receipt)

**User action:** Create Purchase Order: 100 USB Cables @ $8 each, confirm it.

**User action:** Go to receipt, validate it (click "Validate").

**What happens:**
- Odoo creates a stock move: Supplier Location -> WH/Stock
- This is an "incoming" move (unvalued location -> valued location)
- Move value = $8 x 100 = $800
- Product `standard_price` updated to $8.00 (this IS the average cost)
- Journal entry auto-created:

| Account | Debit | Credit | Explanation |
|---|---|---|---|
| 1400 Stock Valuation | $800 | | Inventory increased on balance sheet |
| Stock Input (interim) | | $800 | Temporary holding until bill arrives |

**Result:** Balance sheet shows $800 of inventory. Product cost = $8.00.

#### Step 2: Receive Vendor Bill

**User action:** Vendor sends invoice for $8/unit. Create bill from PO, post it.

**What happens:**
- The bill confirms the cost was indeed $8 -- no change to move value
- If the vendor billed $9 instead, the move value would be updated from $800 to $900, and the average cost would change to $9.00

#### Step 3: Second Purchase at a Different Price

**User action:** New PO: 50 USB Cables @ $10 each. Confirm, receive, validate.

**What happens:**
- New move value = $10 x 50 = $500
- AVCO recalculation:
  - Total inventory value = $800 (from first purchase) + $500 = $1,300
  - Total quantity = 100 + 50 = 150
  - New average cost = $1,300 / 150 = **$8.67/unit**
- Product `standard_price` updated to $8.67
- Journal entry: Debit Stock Valuation $500, Credit Stock Input $500

**Result:** 150 units in stock, total value $1,300, unit cost $8.67.

#### Step 4: Sell to a Customer

**User action:** Create SO: 80 USB Cables @ $15 each (sale price). Confirm, deliver.

**What happens at delivery validation:**
- Stock move: WH/Stock -> Customer Location
- This is an "outgoing" move (valued -> unvalued)
- Move value = $8.67 x 80 = $693.60
- No journal entry YET from the stock move itself (COGS are posted at invoice time)

**Remaining inventory:** 70 units, value = $606.40 ($8.67 x 70), average cost stays $8.67.

#### Step 5: Invoice the Customer

**User action:** Create invoice from SO, post it.

**What happens -- the invoice gets these lines:**

| Account | Debit | Credit | Type |
|---|---|---|---|
| 1200 Accounts Receivable | $1,200 | | Normal invoice line |
| 4000 Revenue | | $1,200 | Normal invoice line |
| 5100 COGS | $693.60 | | Auto-generated (COGS) |
| 1400 Stock Valuation | | $693.60 | Auto-generated (COGS) |

**This is the key moment:** The COGS lines are auto-generated. They record:
- The cost of the goods you just sold ($693.60) as an expense (Profit & Loss)
- Reduction of inventory value on the balance sheet by the same amount

**Profit on this sale:** Revenue $1,200 - COGS $693.60 = **$506.40 gross profit** (42.2% margin).

---

### Walkthrough 2: "I Need to Track Exact Purchase Costs" (Perpetual + FIFO)

FIFO is used when you want the actual purchase cost to flow through to COGS, not a blended average. This gives the most accurate cost tracking but creates more complexity.

**Real-world analogy:** Think of a grocery store shelf stocked from the back. The oldest items are at the front (customers grab them first). Each batch has a different cost written on the box. When you sell, you sell the oldest batch first and record THAT batch's cost as your expense. That's FIFO.

**Setup:**
- Product "Olive Oil (1L)": FIFO, Perpetual valuation
- Three purchases at different prices over time

#### The FIFO Stack in Action

```
Jan 5:  Receive 200 bottles @ $6.00 each  =  $1,200
Jan 20: Receive 150 bottles @ $7.50 each  =  $1,125
Feb 10: Receive 100 bottles @ $8.00 each  =  $800

FIFO Stack (oldest at top):
  Layer 1: 200 @ $6.00  ($1,200)
  Layer 2: 150 @ $7.50  ($1,125)
  Layer 3: 100 @ $8.00  ($800)
  Total: 450 bottles, $3,125 value
```

#### Customer Order: 280 Bottles

**User action:** SO for 280 bottles, deliver and invoice.

**FIFO consumes from oldest first:**
```
  From Layer 1: 200 bottles @ $6.00 = $1,200  (layer fully consumed)
  From Layer 2:  80 bottles @ $7.50 = $600    (70 remain in layer)
  Total COGS = $1,800

  Remaining stack:
    Layer 2:  70 @ $7.50  ($525)
    Layer 3: 100 @ $8.00  ($800)
    Total: 170 bottles, $1,325 value
```

**COGS on the invoice = $1,800** (not $1,944 which would be AVCO at $6.94, not $1,680 which would be standard at $6.00).

**Why FIFO matters here:** The actual cost of the bottles you sold was $1,800. If you used AVCO, you'd report $1,944 -- overstating COGS by $144 and understating profit. FIFO gives the real picture.

#### What Happens to standard_price?

After this delivery, Odoo updates `standard_price`:
```
Remaining value / Remaining qty = $1,325 / 170 = $7.79/unit
```
This is used as a display price and fallback, not for FIFO calculations.

---

### Walkthrough 3: "We Import Goods and Have Shipping/Customs Costs" (Landed Costs)

Landed costs let you add freight, insurance, customs duties, and other costs to the actual product cost so your inventory valuation reflects the TRUE cost of getting goods to your warehouse.

**Why this matters:** If you buy a product for $10 from China but pay $3 in shipping and $2 in customs, your TRUE cost is $15/unit, not $10. Without landed costs, your inventory is undervalued, your margins look better than they are, and your cost analysis is wrong. Landed costs fix this by distributing the extra costs across the products in the shipment.

**Setup:**
- Enable "Landed Costs" in Inventory > Settings
- Product "Ceramic Tile" (AVCO or FIFO, Perpetual)

#### The Scenario

You import two products in one shipment:

| Product | Quantity | Unit Price | Total |
|---|---|---|---|
| Ceramic Tile (Box) | 500 | $12 | $6,000 |
| Marble Slab | 100 | $45 | $4,500 |
| **Subtotal** | | | **$10,500** |

Additional costs from the shipment:
- Ocean freight: $1,500
- Customs duty: $800
- Insurance: $200

**Total true cost:** $10,500 + $2,500 = $13,000

Without landed costs, your inventory would show $10,500 -- understating the true cost by $2,500.

#### Step-by-Step in Odoo

**1. Receive the goods** -- validate the receipt as normal. Inventory shows $10,500.

**2. Create a Landed Cost** (Inventory > Operations > Landed Costs):
- Link it to the receipt picking
- Add cost lines:

| Cost Product | Amount | Split Method | Why this split |
|---|---|---|---|
| Ocean Freight | $1,500 | By Volume | Larger items take more container space |
| Customs Duty | $800 | By Current Cost | Duty is typically proportional to value |
| Insurance | $200 | By Current Cost | Insurance is proportional to value |

**3. Click "Compute"** -- Odoo calculates how to distribute:

**By Volume (Freight $1,500):** If tiles have volume 0.05 m3/box and marble has 0.2 m3/slab:
- Total volume: (500 x 0.05) + (100 x 0.2) = 25 + 20 = 45 m3
- Tiles: $1,500 x (25/45) = $833.33
- Marble: $1,500 x (20/45) = $666.67

**By Current Cost (Customs $800):**
- Tiles: $800 x ($6,000/$10,500) = $457.14
- Marble: $800 x ($4,500/$10,500) = $342.86

**By Current Cost (Insurance $200):**
- Tiles: $200 x ($6,000/$10,500) = $114.29
- Marble: $200 x ($4,500/$10,500) = $85.71

**4. Click "Validate":**

| Product | Original Cost | Freight | Customs | Insurance | **New Total** | **New Unit Cost** |
|---|---|---|---|---|---|---|
| Ceramic Tile | $6,000 | $833 | $457 | $114 | **$7,404** | **$14.81** |
| Marble Slab | $4,500 | $667 | $343 | $86 | **$5,596** | **$55.96** |

Now when you sell a box of tiles, COGS will be $14.81 instead of $12.00 -- reflecting the true landed cost.

---

### Walkthrough 4: "We Manufacture Products" (Standard Cost + Production)

Standard costing is the most common method for manufacturers. You set a planned cost, and any difference between planned and actual becomes a variance.

**Setup:**
- Product "Wooden Chair": Standard Price = $50, Perpetual valuation
- Components: Wood ($15), Screws ($2), Cushion ($8) = $25 material
- Labor: $15/chair, Overhead: $10/chair

#### Why Standard Cost for Manufacturing?

Manufacturing has a problem: you don't know the final cost of a product until production is complete. But you need to value WIP (Work In Progress) and finished goods as they move through the factory.

Standard cost solves this by using a **planned cost** ($50/chair). At the end of the period, you compare planned vs actual and book the variance.

#### The Flow

**1. Set standard price = $50** on the Wooden Chair product.

**2. Produce 20 chairs:**
- Raw materials consumed: 20 x $25 = $500 (actual)
- Labor recorded: 20 x $15 = $300 (actual)
- Overhead applied: 20 x $10 = $200 (actual)
- Actual cost: $1,000

**3. Production order validated:**
- Finished goods valued at standard: 20 x $50 = **$1,000**
- In this case, actual = standard, so no variance

**4. If actual cost was $1,100 instead:**
- Standard valuation: 20 x $50 = $1,000
- Actual cost: $1,100
- Variance: $100 unfavorable (you spent more than planned)
- The variance is posted to a "Price Difference" account

**5. Sell 10 chairs at $80 each:**
- Revenue: $800
- COGS (at standard): 10 x $50 = $500
- Gross profit: $300

**Key point:** With standard cost, COGS is predictable and consistent. Variances are tracked separately, giving management visibility into cost control.

---

### Walkthrough 5: "Our Prices Change Constantly and We Need Smooth Costs" (AVCO Flow)

**Setup:** Product "Coffee Beans (kg)", Average Cost, Perpetual valuation

#### Month of Purchases and Sales

```
Week 1: Buy 500 kg @ $4.00/kg = $2,000
  -> Average cost: $4.00
  -> Inventory: 500 kg, value $2,000

Week 1: Sell 200 kg
  -> COGS: 200 x $4.00 = $800
  -> Inventory: 300 kg, value $1,200

Week 2: Buy 400 kg @ $5.00/kg = $2,000
  -> New average: ($1,200 + $2,000) / (300 + 400) = $3,200 / 700 = $4.57
  -> Inventory: 700 kg, value $3,200

Week 3: Sell 500 kg
  -> COGS: 500 x $4.57 = $2,285
  -> Inventory: 200 kg, value $914

Week 4: Buy 300 kg @ $4.50/kg = $1,350
  -> New average: ($914 + $1,350) / (200 + 300) = $2,264 / 500 = $4.53
  -> Inventory: 500 kg, value $2,264
```

**Why AVCO is good here:** Coffee prices change every week. FIFO would give you wildly different COGS from sale to sale. AVCO smooths the cost, so management sees a consistent margin trend.

---

### Walkthrough 6: "We Track Costs Per Lot/Serial Number" (Lot Valuation)

**The problem without lot valuation:** Normally, Odoo treats all units of the same product as having the same cost (AVCO average or FIFO stack). But what if different batches of the same product have VERY different costs, and you need to track profitability per batch? Standard AVCO would blend all costs together, hiding which batches are profitable.

**Use case:** A wine distributor buys different vintages at different prices. Lot "Chateau 2020" costs $15/bottle, Lot "Chateau 2022" costs $22/bottle. When they sell from "Chateau 2020," the COGS should be $15, not the average of all lots.

**Setup:** Product "Red Wine", `lot_valuated = True` (checkbox "Valuation by Lot/Serial"), AVCO

**What changes with lot valuation:**
- Each lot gets its own `standard_price`
- When Lot 2020 is received at $15, that lot's cost = $15
- When Lot 2022 is received at $22, that lot's cost = $22
- On delivery, Odoo uses the **lot's cost**, not the product average
- The product's `total_value` = sum of all lots' values

**When to use:** Wine, pharmaceuticals, electronics with serial numbers that have different acquisition costs, any product where the lot/serial identity matters for cost tracking.

---

### Walkthrough 7: Periodic Valuation (Manual Closing Flow)

Not every company wants automatic journal entries on every receipt/delivery. Smaller companies or those with a dedicated accountant might prefer periodic valuation.

**How it differs:**
- During the month, receipts and deliveries happen normally
- **No journal entries are created from stock moves**
- The inventory module tracks all quantities and values internally
- At month-end, the accountant clicks Inventory > Operations > "Close Stock Valuation"
- Odoo compares:
  - What the inventory system says the value is (based on quants + cost method)
  - What the accounting ledger shows for the stock valuation account
  - Posts the **difference** as a single journal entry

**Example:**
```
Jan 1:  Stock Valuation account balance = $50,000
Jan:    Purchased $12,000 of goods, sold $8,000 of goods (at cost)
        But no JEs were posted during the month
Jan 31: Inventory system says total value = $54,000
        Accounting shows = $50,000 (no changes during month)
        Closing entry:
          Debit:  Stock Valuation  $4,000
          Credit: Stock Variation  $4,000
```

**Automated closing:** In Settings, you can set `inventory_period` to "Daily" or "Monthly" to have a cron job create closing entries automatically.

---

### Walkthrough 8: Dropship (Supplier Ships Directly to Customer)

**Setup:** Product "Custom Part", AVCO, Perpetual. Route: Dropship.

**Flow:**
1. SO created, generates PO automatically
2. Vendor ships directly to customer (no warehouse receipt)
3. Stock move: Supplier Location -> Customer Location

**Valuation:**
- Move detected as dropship by [`_is_dropshipped()`](../addons/stock_account/models/stock_move.py#L548-L557): `location.usage == 'supplier'` AND `location_dest.usage == 'customer'`
- `is_dropship = True`, but `is_in = False` and `is_out = False` (goods never enter company stock)
- Move gets valued like an incoming move: `move.value = _get_value()`
- `standard_price` is updated
- No inventory on balance sheet since goods bypass the warehouse

**Return flow:**
- Customer returns to supplier: Customer Location -> Supplier Location
- Detected by [`_is_dropshipped_returned()`](../addons/stock_account/models/stock_move.py#L559-L568)

---

### Walkthrough 9: Customer Return (Reverse Flow)

**Scenario:** Customer returns 10 units from a sale where COGS was $8.67/unit.

**Flow:**
1. Create return from delivery (Inventory > Operations > Returns)
2. Return stock move: Customer Location -> WH/Stock
3. This is an "incoming" move (`is_in = True`)

**Value determination:**
- `_get_value_data()` checks `_get_value_from_returns()` first
- If the original outgoing move exists: `value = origin_move.value * return_qty / origin_valued_qty`
- So returned value = $8.67 * 10 = $86.70 (preserves original cost)
- Inventory increases by $86.70

Source: [`_get_value_from_returns()`](../addons/stock_account/models/stock_move.py#L439-L447)

**On credit note:** COGS lines are reversed, moving value back from Expense to Stock Valuation.

---

## When to Use What -- Decision Matrix

| Business Type | Recommended Costing | Recommended Valuation | Why |
|---|---|---|---|
| **Retailer/Trader** | FIFO | Perpetual | You resell what you buy. FIFO tracks actual purchase cost. Perpetual gives real-time COGS. |
| **Manufacturer** | Standard | Perpetual | Planned costs are set in advance. Variances tracked separately. |
| **Food/Commodity** | AVCO | Perpetual | Prices fluctuate constantly. AVCO smooths the cost. |
| **Small Business** | Standard | Periodic | Simple setup. Accountant reconciles at month-end. |
| **Importer** | FIFO + Landed Costs | Perpetual | Each shipment has different costs. Landed costs capture freight/duty. |
| **Wine/Pharma/Serialized** | FIFO or AVCO + Lot Valuation | Perpetual | Different lots have different costs. Need per-lot tracking. |
| **Dropshipper** | Standard | Periodic | Never holds inventory. Valuation is minimal. |

---

## What Accounts Are Involved -- Plain English

Understanding the accounts is crucial. Here are the accounts involved and what each one represents in business terms:

| Account | Type | What it represents | When it changes |
|---|---|---|---|
| **Stock Valuation** (e.g., 1400) | Balance Sheet -- Current Asset | "How much inventory do we own right now?" | Increases on receipt, decreases on delivery/sale |
| **COGS / Expense** (e.g., 5100) | Profit & Loss -- Expense | "What did the products we sold this period cost us?" | Increases when customer invoice is posted |
| **Stock Input (interim)** | Balance Sheet -- Liability | "We received goods but haven't been billed yet." Think of it as an IOU to the supplier -- you have the goods, but you haven't recorded the bill. When the bill arrives, this account zeros out. | Credited on receipt, debited when vendor bill arrives |
| **Stock Output (interim)** | Balance Sheet -- Asset | "We delivered goods but haven't invoiced the customer yet." Think of it as a claim -- you gave goods away and need to bill for them. When the invoice is posted, this account zeros out. | Debited on delivery, credited when customer invoice is posted |
| **Price Difference** | P&L -- Expense | "Difference between what we expected to pay and what we actually paid" | Only with Standard cost when bill differs from standard |
| **Inventory Loss** | P&L -- Expense | "Value of goods lost/damaged/stolen" | When inventory adjustment reduces quantity |
| **Stock Variation** | P&L -- Expense | "Change in inventory value during the period" | At periodic closing |

### How Money Flows Through Accounts (Perpetual AVCO)

```
PURCHASE FLOW:
                         Receipt                    Vendor Bill
  Vendor                Validated                    Posted
    |                      |                           |
    |   Stock Input     <--+-->  Stock Valuation       |
    |   (Liability)        |     (Asset)               |
    |                      |     + $1,000              |
    |                      |                           |
    |                      |     Stock Input        <--+-->  Accounts Payable
    |                      |     (Liability)            |    (Liability)
    |                      |     - $1,000               |    + $1,000

SALE FLOW:
                        Delivery                   Customer Invoice
  Customer              Validated                    Posted
    |                      |                           |
    |   (move valued       |                           |
    |    internally but    |                           |
    |    COGS posted at -->+---------------------->    |
    |    invoice time)     |                           |
    |                      |     Stock Valuation    <--+  (COGS auto-line)
    |                      |     (Asset)               |
    |                      |     - $800                |
    |                      |                           |
    |                      |     COGS Expense       <--+  (COGS auto-line)
    |                      |     (P&L)                 |
    |                      |     + $800                |
    |                      |                           |
    |                      |     Revenue            <--+  (Invoice line)
    |                      |     (P&L)                 |
    |                      |     + $1,200              |
    |                      |                           |
    |                      |     Accounts Receivable<--+  (Invoice line)
    |                      |     (Asset)               |
    |                      |     + $1,200              |
```

### How Money Flows (Perpetual + Anglo-Saxon + Standard Cost -- Purchase Price Difference)

```
PURCHASE FLOW WITH PRICE DIFFERENCE:

  Receipt validated (100 units, standard_price = $9):
    Debit:  Stock Valuation  $900
    Credit: Stock Input       $900

  Vendor bill posted ($10/unit = $1,000 total):
    Debit:  Stock Valuation  $1,000   (bill line account overridden to stock val)
    Credit: Accounts Payable $1,000

    Auto price diff lines (display_type='cogs'):
    Debit:  Price Difference  $100    (10 - 9 = $1/unit * 100 units)
    Credit: Stock Valuation   $100

  Net effect on Stock Valuation: +$900 (receipt) +$1,000 (bill) -$100 (price diff) = $900 = standard
```

---

## Common Questions from Odoo Users

### Q: I changed the product cost. What happened to existing inventory?

**Standard cost:** Changing `standard_price` immediately changes the displayed total value of your stock. But it does NOT create any journal entry. The accounting books won't match until the next closing (periodic) or until you sell (perpetual -- COGS uses new price).

**AVCO:** You normally don't manually change the cost -- Odoo recalculates it on every receipt. If you DO manually change it, Odoo creates a `product.value` record to track the override and recomputes affected moves.

**FIFO:** Manual price changes are mostly irrelevant. FIFO always uses the actual receipt costs. The `standard_price` is just updated for display purposes.

### Q: What happens if I sell more than I have (negative stock)?

Odoo allows negative stock if "No Negative Stock" is not enforced. For valuation:
- **FIFO:** Extrapolates cost using the last known receipt price. When goods eventually arrive, the cost may be corrected.
- **AVCO:** Uses the current `standard_price` (the running average). If stock was already at zero, uses the last known average.
- **Standard:** Always uses the fixed price, so negative stock doesn't affect the cost.

**Risk:** Selling into negative stock means your COGS is estimated, not actual. This can lead to corrections later.

### Q: Can I change the costing method after I have transactions?

Technically possible by changing the product category's costing method. Odoo will recompute `standard_price` for all products in that category. However, **this does not rewrite historical journal entries.** Past COGS entries stay as they were. This is a major decision -- do it at the start of a fiscal year with an accountant's guidance.

### Q: What's the difference between "Standard Price" on the product and the actual inventory value?

- `standard_price` is a **per-unit** number on the product card
- `total_value` is the **computed total** value of all stock on hand
- For Standard cost: `total_value = standard_price x qty_on_hand` (always)
- For AVCO: `standard_price` IS the average, so `total_value = standard_price x qty_on_hand`
- For FIFO: `standard_price` is an approximation (total_value / qty_on_hand). The real value comes from the FIFO stack.

### Q: Where do I see the inventory valuation in Odoo?

- **Per product:** Product form > "Valuation" smart button (shows total_value, avg_cost)
- **Per quant:** Inventory > Reporting > Inventory Valuation (shows value per location/lot)
- **In accounting:** General Ledger for the Stock Valuation account
- **Closing report:** Inventory > Operations > Close Stock Valuation (periodic only)

### Q: When does a vendor bill change the move value?

When `account.move._post()` is called on a vendor bill, it triggers `_set_value()` on linked incoming stock moves. The `_get_value_data()` priority chain then picks up the bill amount via `_get_value_from_account_move()` (which returns the actual invoiced price), replacing the PO-based estimate. This updates `move.value`, then `_update_standard_price()` adjusts the product's `standard_price`.

Source: [`account_move.py:42`](../addons/stock_account/models/account_move.py#L42) -- `self.line_ids._get_stock_moves().filtered(lambda m: m.is_in)._set_value()`

---

## Dependencies

### Requires
| Module | Why |
|---|---|
| `stock` | Core inventory engine -- locations, pickings, moves, quants |
| `account` | Journal entries, accounts, fiscal positions |

### Optional Integrations
| Module | What it enables |
|---|---|
| `stock_landed_costs` | Allocates freight/customs/other costs to receipt moves, adjusting their value |
| `purchase_stock` | Gets move value from vendor bills and PO lines instead of standard price |
| `sale_stock` | Generates COGS lines on customer invoices, prevents double-counting |
| `mrp` | Production cost valuation (WIP accounts) |

### Provides To
| Consumer | What they use |
|---|---|
| `account.move` | COGS journal items on customer invoices via `_stock_account_prepare_realtime_out_lines_vals()` |
| `stock.quant` | `value` field computed from product valuation |
| `account_reports` | Stock valuation data for inventory reports |

---

## Glossary (Quick Reference for Learners)

| Term | Plain English |
|---|---|
| **COGS** | Cost of Goods Sold. The amount you paid for products you sold. Shows on the Profit & Loss as an expense. |
| **Balance Sheet** | A snapshot of what your company OWNS (assets) and OWES (liabilities) at a point in time. Inventory is an asset. |
| **P&L / Income Statement** | Shows revenue minus expenses over a period. COGS is an expense here. Revenue minus COGS = Gross Profit. |
| **Journal Entry (JE)** | A record of a financial transaction. Always has equal debits and credits. Odoo creates these automatically for stock moves. |
| **Debit / Credit** | Debit = left side, Credit = right side. For assets: debit increases, credit decreases. For expenses: debit increases. For liabilities/revenue: credit increases. |
| **Interim Account** | A temporary holding account. Balances out when both sides of a transaction are complete (e.g., goods received + bill posted). |
| **Valued Location** | A location where inventory has monetary value (internal warehouses, transit). Supplier/Customer locations are NOT valued. |
| **Stock Move** | A record of products moving from one location to another. Every pick, delivery, receipt, and transfer creates stock moves. |
| **Perpetual Valuation** | Real-time accounting. Every stock move automatically creates a journal entry. |
| **Periodic Valuation** | Batch accounting. No JEs during the month. One closing entry at month-end adjusts everything at once. |
| **Standard Price** | The `standard_price` field on a product. For Standard costing = manual fixed cost. For AVCO = running average. For FIFO = display approximation. |

---

> **From here on, the document becomes technical.** The sections below explain HOW Odoo implements the business flows described above -- models, fields, methods, and code traces. Refer back to the walkthroughs if you need context on WHY something works the way it does.

---

## Core Concepts

### Valued Locations

Only locations with `usage` in `['internal', 'transit']` **and** a `company_id` are considered "valued". Everything else (customer, supplier, production, inventory loss) is unvalued.

Source: [`stock_location.py:36-41`](../addons/stock_account/models/stock_location.py#L36-L41)

```
_should_be_valued() = bool(self.company_id) and self.usage in ['internal', 'transit']
```

### Move Direction Detection

| Direction | Condition | Method |
|---|---|---|
| **Incoming** (`is_in`) | Unvalued source -> Valued destination, not dropship-returned | [`_is_in()`](../addons/stock_account/models/stock_move.py#L508-L516) |
| **Outgoing** (`is_out`) | Valued source -> Unvalued destination, not dropship | [`_is_out()`](../addons/stock_account/models/stock_move.py#L538-L546) |
| **Dropship** (`is_dropship`) | Supplier -> Customer (or via intercompany transit) | [`_is_dropshipped()`](../addons/stock_account/models/stock_move.py#L548-L557) |
| **Dropship Return** | Customer -> Supplier | [`_is_dropshipped_returned()`](../addons/stock_account/models/stock_move.py#L559-L568) |

A move is **valued** (`is_valued`) if `is_in OR is_out`. Computed on done moves only.

Source: [`stock_move.py:89-92`](../addons/stock_account/models/stock_move.py#L89-L92)

**Direction detection algorithm:** The system iterates over `move_line_ids`, checking each line's source/destination location via `_should_be_valued()`. A single move can have both in-lines and out-lines (e.g., internal transfer between valued locations with different valuation accounts). The `_get_move_directions()` method returns a dict mapping move IDs to sets of directions (`'in'`, `'out'`).

Source: [`_get_move_directions()`](../addons/stock_account/models/stock_move.py#L465-L486)

### Consignment Exclusion

Moves with `restrict_partner_id` different from the company's partner are excluded from valuation. This handles consigned goods that the company doesn't own.

Source: [`_should_exclude_for_valuation()`](../addons/stock_account/models/stock_move.py#L625-L631)

---

## Valuation Methods

### Periodic vs Perpetual

Set at **product category** level (company-dependent) or falls back to **company** default.

| Method | Technical value | UI Label | When journal entries are created |
|---|---|---|---|
| Periodic | `periodic` | "Periodic (at closing)" | Only during manual/scheduled closing |
| Perpetual | `real_time` | "Perpetual (at invoicing)" | Automatically on every stock move + COGS on invoice posting |

**Product Category fields:**
- `property_valuation` (Selection, company_dependent): [`product.py:485-494`](../addons/stock_account/models/product.py#L485-L494)

**Company defaults:**
- `inventory_valuation` (Selection, default=`'periodic'`): [`res_company.py:29-36`](../addons/stock_account/models/res_company.py#L29-L36)

**Product Template computed fields:**
- `valuation` -- computed from `categ_id.property_valuation`, falls back to `company.inventory_valuation`: [`product.py:69-74`](../addons/stock_account/models/product.py#L69-L74)

---

## Costing Methods

Set at **product category** level (company-dependent) or falls back to **company** default.

| Method | Technical value | UI Label | How outgoing cost is determined |
|---|---|---|---|
| Standard | `standard` | "Standard Price" | Fixed `standard_price` on product |
| FIFO | `fifo` | "First In First Out (FIFO)" | Oldest incoming move's actual cost consumed first |
| Average | `average` | "Average Cost (AVCO)" | Weighted average recomputed on every receipt |

**Product Category field:**
- `property_cost_method` (Selection, company_dependent): [`product.py:495-509`](../addons/stock_account/models/product.py#L495-L509)

**Company default:**
- `cost_method` (Selection, default=`'standard'`): [`res_company.py:38-47`](../addons/stock_account/models/res_company.py#L38-L47)

---

### Standard Price -- How It Works

The simplest method. A fixed `standard_price` on the product is used for all valuations.

**Incoming move value:**
```
move.value = standard_price * quantity
```

**Outgoing move value:**
```
move.value = standard_price * quantity
```

**When standard_price changes:** A `product.value` record is created to track the history. This does NOT retroactively change existing move values.

Source: [`_change_standard_price()`](../addons/stock_account/models/product.py#L193-L205)

**Historical price lookup:** For reporting at a past date, `_get_standard_price_at_date()` searches `product.value` records.

Source: [`product.py:207-223`](../addons/stock_account/models/product.py#L207-L223)

**Example:**
```
Product "Widget A" -- Standard Price: $10

Receipt: 100 units from Supplier
  move.value = $10 * 100 = $1,000

Delivery: 30 units to Customer
  move.value = $10 * 30 = $300

Change standard price to $12
  product.value record created (old=$10, new=$12)

Next delivery: 20 units
  move.value = $12 * 20 = $240
```

---

### FIFO -- How It Works

Builds a stack of incoming moves ordered oldest-first. Outgoing moves consume from the oldest layer.

**Key method:** [`_run_fifo(quantity, lot, at_date, location)`](../addons/stock_account/models/product.py#L368-L407)

**Algorithm:**
1. Call `_run_fifo_get_stack()` to build the FIFO stack
2. Pop moves from the stack (oldest first), accumulating cost until the requested quantity is consumed
3. If quantity exceeds available stock, extrapolate using the last move's unit price (or `standard_price` if no moves exist)

**Stack construction:** [`_run_fifo_get_stack()`](../addons/stock_account/models/product.py#L409-L460)
1. Determine `fifo_stack_size` = current `qty_available` (minus any `fifo_qty_already_processed` from context)
2. Search incoming moves (`is_in=True`) ordered by `date desc, id desc` (newest first)
3. Walk backwards from newest until accumulated quantity >= `fifo_stack_size`
4. Reverse the stack so oldest is first
5. Track `remaining_qty_on_first_stack_move` for partial consumption

**Why search newest-first then reverse?** Performance. The FIFO stack only needs the most recent incoming moves that account for current on-hand quantity. By searching newest-first, Odoo stops as soon as it has enough moves to cover `qty_available`. This avoids loading the entire purchase history.

**Performance:** Fetches in batches of 100 moves to avoid memory issues.

**Outgoing move valuation:** [`_set_value()`](../addons/stock_account/models/stock_move.py#L258-L308)
```python
if move.product_id.cost_method == 'fifo':
    valued_qty = move._get_valued_qty()
    move.value = move.product_id.with_context(
        fifo_qty_already_processed=fifo_qty_processed[move.product_id]
    )._run_fifo(valued_qty)
```

The `fifo_qty_already_processed` context key handles multiple outgoing moves validated simultaneously -- each subsequent move sees the reduced stack.

**Standard price update after FIFO out:** After outgoing moves, `standard_price` is updated to `total_value / qty_available`. If no stock remains, uses the last incoming move's unit price.

Source: [`_update_standard_price()`](../addons/stock_account/models/product.py#L462-L476)

**Example:**
```
Receipt #1: 50 units @ $8 each = $400
Receipt #2: 30 units @ $12 each = $360
Receipt #3: 20 units @ $10 each = $200
  Total stock: 100 units, total value: $960

Delivery: 60 units
  FIFO consumes:
    50 units from Receipt #1 @ $8 = $400
    10 units from Receipt #2 @ $12 = $120
  move.value = $520

  Remaining stack:
    20 units from Receipt #2 @ $12 = $240
    20 units from Receipt #3 @ $10 = $200
  standard_price updated: $440 / 40 = $11.00
```

---

### Average Cost (AVCO) -- How It Works

Recomputes a weighted average from all incoming and outgoing moves in chronological order.

**Key method:** [`_run_avco(at_date, lot, method)`](../addons/stock_account/models/product.py#L262-L366)

**Returns:** `(avco_unit_value, avco_total_value)` tuple.

**Algorithm:**
1. Load all incoming/dropship moves + all `product.value` manual updates, ordered by date
2. If only manual values exist (no moves), return the last manual value
3. Process all moves chronologically:
   - **On incoming move:** Add quantity and value, recalculate average: `avco_value = avco_total_value / quantity`
   - **On outgoing move:** Deduct quantity and proportional value: `out_value = out_qty * avco_value`
   - **On manual price update:** Override `avco_value` and recompute `avco_total_value`
4. Handle negative stock: when `previous_qty <= 0`, reset average to the incoming move's unit price

**Outgoing move valuation:** For AVCO, outgoing moves use `standard_price * quantity` (since `standard_price` is kept in sync with the running average).

Source: [`_set_value()` line 303-304](../addons/stock_account/models/stock_move.py#L303-L304)

**Standard price update after AVCO receipt:** After incoming moves, `standard_price` is updated to `_run_avco()[0]` (the current unit average).

Source: [`_update_standard_price()`](../addons/stock_account/models/product.py#L474-L476)

**AVCO and negative stock:** When stock goes to zero or negative, the average cost is "frozen" at the last known value. When new stock arrives, the average resets to the incoming move's unit price (because there's nothing to average against). This can cause cost jumps -- a common source of confusion.

**Example:**
```
Receipt #1: 100 units @ $10 = $1,000
  avco_value = $10.00, total = $1,000
  standard_price updated to $10.00

Receipt #2: 50 units @ $16 = $800
  avco_total = $1,000 + $800 = $1,800
  avco_value = $1,800 / 150 = $12.00
  standard_price updated to $12.00

Delivery: 80 units
  move.value = $12.00 * 80 = $960
  avco_total = $1,800 - $960 = $840
  quantity = 70
  avco_value stays $12.00

Receipt #3: 30 units @ $15 = $450
  avco_total = $840 + $450 = $1,290
  avco_value = $1,290 / 100 = $12.90
  standard_price updated to $12.90
```

---

### Comparison of Costing Methods

| Aspect | Standard | FIFO | AVCO |
|---|---|---|---|
| `standard_price` meaning | Manually set cost | Approximation: `total_value / qty_available` | Running weighted average (authoritative) |
| Updated when? | Manual only | After outgoing moves | After incoming moves |
| Outgoing value formula | `standard_price * qty` | Stack-based (oldest first) | `standard_price * qty` |
| Incoming value source | Priority chain (bill > PO > std price) | Priority chain (bill > PO > std price) | Priority chain (bill > PO > std price) |
| Landed costs? | Not supported | Supported | Supported |
| Negative stock handling | Uses fixed price (safe) | Extrapolates from last receipt (risky) | Uses frozen average (risky) |
| Performance | Fastest | Slowest (stack computation) | Medium |
| Accuracy | Low (manual) | Highest (actual costs) | Medium (smoothed) |

---

## Incoming Move Value Priority

When computing the value of an incoming move, Odoo checks sources in this priority order:

| Priority | Source | Method | When used |
|---|---|---|---|
| 1 | Manual override | [`_get_manual_value()`](../addons/stock_account/models/stock_move.py#L412-L428) | User created a `product.value` record for this move |
| 2 | Vendor bill | [`_get_value_from_account_move()`](../addons/stock_account/models/stock_move.py#L430-L431) | Posted bill linked to PO line (overridden in `purchase_stock`) |
| 3 | Production | [`_get_value_from_production()`](../addons/stock_account/models/stock_move.py#L433-L434) | Manufacturing order cost (overridden in `mrp_account`) |
| 4 | PO/SO line | [`_get_value_from_quotation()`](../addons/stock_account/models/stock_move.py#L436-L437) | Purchase order line price (overridden in `purchase_stock`) |
| 5 | Return origin | [`_get_value_from_returns()`](../addons/stock_account/models/stock_move.py#L439-L447) | Proportional value from the original outgoing move |
| 6 | Standard price | [`_get_value_from_std_price()`](../addons/stock_account/models/stock_move.py#L449-L460) | Fallback: `standard_price * quantity` |
| 7 | Extra costs | [`_get_value_from_extra()`](../addons/stock_account/models/stock_move.py#L462-L463) | Landed costs (overridden in `stock_landed_costs`) |

Full logic: [`_get_value_data()`](../addons/stock_account/models/stock_move.py#L313-L398)

Each source returns `{'value': float, 'quantity': float, 'description': str}`. The system works through the priority list, reducing `remaining_qty` at each step. If a manual update covers the full quantity, extra costs are skipped.

**Important detail:** Priority 7 (extra costs from landed costs) is additive -- it uses the full `valued_qty`, not `remaining_qty`. It adds ON TOP of whatever base value was determined. However, if a manual override covers the full quantity (`add_extra_value` becomes `False`), extra costs are skipped.

---

## Business Flow -- Perpetual Valuation

```
Stock Move Done  -->  _action_done()  -->  _set_value()  -->  _create_account_move()
       |                                       |                       |
       |                              Compute move.value        Create JE if:
       |                              using cost method         - product.is_storable
       |                                       |                - move.is_valued
       |                                       |                - location has valuation_account_id
       |                                       |                - product.valuation == 'real_time'
       |                                       v
       |                              _update_standard_price()
       |                              (FIFO & AVCO only)
       v
Invoice Posted  -->  _post()  -->  _stock_account_prepare_realtime_out_lines_vals()
                                           |
                                   Create COGS lines (display_type='cogs')
                                   Debit: Expense/COGS account
                                   Credit: Stock Valuation account
```

### Step-by-Step: `_action_done()`

Source: [`stock_move.py:161-174`](../addons/stock_account/models/stock_move.py#L161-L174)

1. **Before** `super()._action_done()`: Set value on outgoing moves (needs current FIFO stack before quantities change)
2. Call `super()._action_done()` (marks moves as done, updates quants)
3. **After**: Set value on incoming/dropship moves
4. `_create_account_move()` -- create journal entries for real-time valued moves
5. Update `standard_price` for FIFO products that had outgoing moves
6. Create analytic lines

**Why outgoing BEFORE super and incoming AFTER?** Outgoing moves need the FIFO stack in its current state (before new incoming moves change it). Incoming moves need `super()` to run first because `is_in`/`is_out` are computed from move lines which are only finalized during `super()._action_done()`.

### Journal Entry Creation

Source: [`_create_account_move()`](../addons/stock_account/models/stock_move.py#L176-L193)

**Eligibility check** [`_should_create_account_move()`](../addons/stock_account/models/stock_move.py#L616-L623):
- Product is storable
- Move is valued (`is_in` or `is_out`)
- At least one location (source or destination) has `valuation_account_id`
- Product valuation is `'real_time'`

**Account determination** [`_get_account_move_line_vals()`](../addons/stock_account/models/stock_move.py#L201-L221):

| Scenario | Debit Account | Credit Account |
|---|---|---|
| Source location has `valuation_account_id` | Product's Stock Valuation account | Source location's `valuation_account_id` |
| Dest location has `valuation_account_id` | Dest location's `valuation_account_id` | Product's Stock Valuation account |

The journal entry is auto-posted immediately.

**Journal used:** `company.account_stock_journal_id` (not category-level journal). Source: [`stock_move.py:187`](../addons/stock_account/models/stock_move.py#L187)

---

## Business Flow -- Periodic Valuation

No journal entries are created during stock moves. Instead, a closing process compares inventory value vs accounting value and posts the difference.

### Closing Process

Source: [`action_close_stock_valuation()`](../addons/stock_account/models/res_company.py#L49-L83)

Three sub-steps run in sequence:

| Step | Method | What it does |
|---|---|---|
| 1. Location reclassification | [`_get_location_valuation_vals()`](../addons/stock_account/models/res_company.py#L167-L223) | For locations with `valuation_account_id`: sums move values since last closing, creates entries to reclassify |
| 2. Stock variation global | [`_get_stock_valuation_account_vals()`](../addons/stock_account/models/res_company.py#L225-L256) | Compares inventory value (from product computation) vs accounting balance (sum of posted AMLs), posts the difference to the variation account |
| 3. Continental perpetual variation | [`_get_continental_realtime_variation_vals()`](../addons/stock_account/models/res_company.py#L258-L304) | For perpetual+continental: posts inventory variation over the fiscal period to variation/expense accounts |

### Automated Closing (Cron)

Source: [`_cron_post_stock_valuation()`](../addons/stock_account/models/res_company.py#L136-L142)

| `inventory_period` | UI Label | Frequency |
|---|---|---|
| `manual` | "Manual" | Never (user clicks button) |
| `daily` | "Daily" | Every day |
| `monthly` | "Monthly" | Last day of each month |

Cron job record: `stock_account.ir_cron_post_stock_valuation` -- calls `res_company._cron_post_stock_valuation()`.

**Closing date tracking:** The last closing date is stored in `ir.config_parameter`. Only moves after the last closing are included in the next closing. Source: [`_get_last_closing_date()`](../addons/stock_account/models/res_company.py#L326-L340)

---

## COGS on Customer Invoices (Anglo-Saxon)

When a customer invoice is posted, Odoo auto-generates two additional journal lines per eligible product line.

Source: [`_stock_account_prepare_realtime_out_lines_vals()`](../addons/stock_account/models/account_move.py#L68-L160)

**Conditions:**
- Invoice is a sale document (`is_sale_document()`)
- Product has `valuation == 'real_time'`
- Product passes `_eligible_for_stock_account()`

### COGS Value Computation

Source: [`_get_cogs_value()`](../addons/stock_account/models/account_move_line.py#L51-L74)

The COGS unit price is determined by:
1. If invoice is a reversal (credit note): use the original COGS line's `price_unit`
2. If stock moves exist (done state): call `moves._get_cogs_price_unit(cogs_qty)`
   - **FIFO:** `sum(moves.value) / sum(valued_qty)` -- actual move cost
   - **Standard/AVCO:** `product.standard_price`
3. If no stock moves: use `product.standard_price` (Standard/AVCO) or `product._run_fifo(qty) / qty` (FIFO)
4. Final formula: `(price_unit * cogs_qty - already_posted_cogs) / invoice_qty`

Source for COGS price unit: [`_get_cogs_price_unit()`](../addons/stock_account/models/stock_move.py#L238-L245)

### Eligible for Stock Account

Source: [`_eligible_for_stock_account()`](../addons/stock_account/models/account_move_line.py#L30-L35)

Returns `True` only if:
- Product is storable (`is_storable`)
- ALL linked stock moves are NOT dropshipped

Dropshipped products don't get COGS lines because they never enter the company's stock.

### Purchase Bill Account Override

For vendor bills with real-time valuation, the invoice line account is overridden from the expense account to the stock valuation account. This defers the expense until goods are sold.

Source: [`_compute_account_id()`](../addons/stock_account/models/account_move_line.py#L13-L24)

**Example:** Buy product for $9, sell for $10.

**Original invoice lines:**

| Account | Debit | Credit |
|---|---|---|
| 101200 Account Receivable | 10.00 | |
| 200000 Product Sales | | 10.00 |

**Auto-generated COGS lines** (`display_type='cogs'`):

| Account | Debit | Credit |
|---|---|---|
| 500000 COGS (expense) | 9.00 | |
| 110100 Stock Valuation | | 9.00 |

**On draft/cancel:** COGS lines are automatically deleted.

Source: [`button_draft()`](../addons/stock_account/models/account_move.py#L46-L52), [`button_cancel()`](../addons/stock_account/models/account_move.py#L54-L62)

**On posting:** Incoming move values are also recomputed (vendor bill amounts become known).

Source: [`_post()`](../addons/stock_account/models/account_move.py#L29-L44)

---

## Key Models

### `stock.move` -- Valuation Fields
> [`stock_move.py`](../addons/stock_account/models/stock_move.py)

| Field | Type | Purpose |
|---|---|---|
| `value` | Monetary | Current monetary value of the move (zero if not valued) |
| `value_justification` | Text (computed) | Human-readable description of how value was determined |
| `value_computed_justification` | Text (computed) | Description of computed vs actual value difference |
| `value_manual` | Monetary (computed, inverse) | User-adjustable value, creates `product.value` on write |
| `remaining_qty` | Float (computed) | Quantity still in stock (FIFO: from stack position) |
| `remaining_value` | Monetary (computed) | Value of remaining quantity |
| `is_in` | Boolean (computed, stored) | True if incoming (unvalued -> valued) |
| `is_out` | Boolean (computed, stored) | True if outgoing (valued -> unvalued) |
| `is_dropship` | Boolean (computed, stored) | True if supplier -> customer |
| `is_valued` | Boolean (computed) | `is_in OR is_out` |
| `price_unit` | Float | Legacy field (to be removed, use `value`) |
| `standard_price` | Float (related) | From `product_id.standard_price` |
| `to_refund` | Boolean | Trigger SO/PO quantity update on returns |

**`remaining_qty` and `remaining_value`** -- These represent how much of an incoming move's quantity is still in stock (not consumed by outgoing FIFO moves). For FIFO, this drives the stack. For AVCO/Standard, `remaining_value = remaining_qty * standard_price`.

---

### `product.value` -- Price History & Manual Adjustments
> [`product_value.py`](../addons/stock_account/models/product_value.py)

Tracks manual value updates for products, lots, and individual moves.

| Field | Type | Purpose |
|---|---|---|
| `product_id` | Many2one(product.product) | Related product |
| `lot_id` | Many2one(stock.lot) | Optional lot-specific value |
| `move_id` | Many2one(stock.move) | Optional move-specific override |
| `value` | Monetary | New unit price (for product/lot) or total value (for move) |
| `date` | Datetime | When the change was made |
| `user_id` | Many2one(res.users) | Who made the change |
| `description` | Char | Reason for the change |

**On create:** Triggers `_set_value()` on all affected stock moves to recompute their values.

Source: [`create()`](../addons/stock_account/models/product_value.py#L72-L96)

**Role in AVCO:** Manual `product.value` records act as "price resets" in the AVCO timeline. When `_run_avco()` encounters one, it overrides `avco_value` and recomputes `avco_total_value = avco_value * current_qty`.

**Role in Standard:** When `standard_price` is changed, `_change_standard_price()` creates a `product.value` record. This allows `_get_standard_price_at_date()` to look up the historical price.

---

### `product.product` -- Valuation Computed Fields
> [`product.py`](../addons/stock_account/models/product.py)

| Field | Type | Purpose |
|---|---|---|
| `avg_cost` | Monetary (computed) | Average cost per unit |
| `total_value` | Monetary (computed) | Total inventory value |
| `company_currency_id` | Many2one (computed) | Company currency |

**Value computation** [`_compute_value()`](../addons/stock_account/models/product.py#L141-L169):
- **Standard:** `total_value = standard_price * qty_available`
- **AVCO:** `total_value = _run_avco()[1]` (total value from weighted average replay)
- **FIFO:** `total_value = _run_fifo(qty_available)` (value from stack)
- Supports `to_date` context for historical valuation
- Supports `warehouse_id` context for location-specific valuation

---

### `product.template` -- Valuation Configuration Fields
> [`product.py`](../addons/stock_account/models/product.py)

| Field | Type | Purpose |
|---|---|---|
| `cost_method` | Selection (computed) | From `categ_id.property_cost_method` or `company.cost_method` |
| `valuation` | Selection (computed) | From `categ_id.property_valuation` or `company.inventory_valuation` |
| `lot_valuated` | Boolean (computed, stored, editable) | Enable per-lot cost tracking |
| `property_price_difference_account_id` | Many2one (company_dependent) | Price diff account for standard cost |

---

### `stock.lot` -- Lot-Level Valuation
> [`stock_lot.py`](../addons/stock_account/models/stock_lot.py)

When `product_template.lot_valuated = True`, each lot/serial gets its own cost tracking.

| Field | Type | Purpose |
|---|---|---|
| `standard_price` | Float (company_dependent) | Cost per unit for this lot |
| `avg_cost` | Monetary (computed, stored) | Average cost per unit |
| `total_value` | Monetary (computed) | Total inventory value for this lot |
| `lot_valuated` | Boolean (related) | From `product_id.lot_valuated` |

**Lot valuation logic** [`_compute_value()`](../addons/stock_account/models/stock_lot.py#L21-L44):
- Standard: `lot.standard_price * qty_valued`
- AVCO: `product._run_avco(lot=lot)` -- lot-filtered weighted average
- FIFO: `product._run_fifo(qty, lot=lot)` -- lot-filtered FIFO stack

**On lot creation:** If the product is lot-valuated, the lot inherits `product.standard_price`.

Source: [`create()`](../addons/stock_account/models/stock_lot.py#L67-L75)

**How lot valuation changes outgoing moves:** In `_set_value()`, when `product.lot_valuated = True`, outgoing moves iterate over `move_line_ids` and use each line's `lot_id.standard_price * quantity_product_uom`. This bypasses FIFO/AVCO computation on the product level and delegates to lot-level pricing.

Source: [`_set_value()` lines 289-297](../addons/stock_account/models/stock_move.py#L289-L297)

---

### `stock.quant` -- Quant-Level Value
> [`stock_quant.py`](../addons/stock_account/models/stock_quant.py)

| Field | Type | Purpose |
|---|---|---|
| `value` | Monetary (computed) | Quant's proportional value |
| `accounting_date` | Date | Override date for inventory adjustment JEs |
| `cost_method` | Selection (computed) | From product category |

**Value computation** [`_compute_value()`](../addons/stock_account/models/stock_quant.py#L47-L65):
```
quant.value = quant.quantity * (product.total_value / product.qty_available)
```
For lot-valuated products, uses lot-level `total_value` and `product_qty` instead.

**Exclusions:** Returns 0 if location is not valued, owner is supplier (consignment), quantity is zero.

**Inventory adjustments:** When `_apply_inventory()` is called, it respects `accounting_date` for the journal entry date via `force_period_date` context.

Source: [`_apply_inventory()`](../addons/stock_account/models/stock_quant.py#L80-L87)

---

### `stock.landed.cost` -- Landed Costs
> [`stock_landed_cost.py`](../addons/stock_landed_costs/models/stock_landed_cost.py)

| Field | Type | Purpose |
|---|---|---|
| `name` | Char | Auto-sequence (LC/YYYY/####) |
| `date` | Date | Landed cost date |
| `picking_ids` | Many2many(stock.picking) | Target transfers |
| `cost_lines` | One2many(stock.landed.cost.lines) | Individual cost items |
| `valuation_adjustment_lines` | One2many(stock.valuation.adjustment.lines) | Computed per-product adjustments |
| `state` | Selection | `draft` / `done` / `cancel` |
| `account_move_id` | Many2one(account.move) | Created journal entry |
| `account_journal_id` | Many2one(account.journal) | Journal for posting |
| `vendor_bill_id` | Many2one(account.move) | Linked vendor bill |

**States:**

| State | Meaning | Can Transition To |
|---|---|---|
| `draft` | Not yet applied | `done`, `cancel` |
| `done` | Validated, JE created, move values updated | -- (cannot cancel, must create negative LC) |
| `cancel` | Cancelled | -- |

**Creating from vendor bill:** The `button_create_landed_costs()` method on `account.move` filters invoice lines with `is_landed_costs_line=True` and creates cost lines automatically. Products must have `landed_cost_ok=True` (service type only).

Source: [`account_move.py:21-40`](../addons/stock_landed_costs/models/account_move.py#L21-L40)

---

### `stock.landed.cost.lines` -- Cost Line Items
> [`stock_landed_cost.py:273-301`](../addons/stock_landed_costs/models/stock_landed_cost.py#L273-L301)

| Field | Type | Purpose |
|---|---|---|
| `product_id` | Many2one(product.product) | The cost product (e.g., "Freight") |
| `price_unit` | Monetary | Total cost amount |
| `split_method` | Selection | How to distribute across products |
| `account_id` | Many2one(account.account) | Expense account for the cost |

### Split Methods

| Value | UI Label | Formula |
|---|---|---|
| `equal` | "Equal" | `cost / total_lines` |
| `by_quantity` | "By Quantity" | `cost * (line_qty / total_qty)` |
| `by_current_cost_price` | "By Current Cost" | `cost * (line_former_cost / total_cost)` |
| `by_weight` | "By Weight" | `cost * (line_weight / total_weight)` |
| `by_volume` | "By Volume" | `cost * (line_volume / total_volume)` |

Source: [`compute_landed_cost()`](../addons/stock_landed_costs/models/stock_landed_cost.py#L180-L243)

**Rounding:** Uses `currency.round()` with HALF-UP rounding. Rounding differences are applied to the last valuation line.

---

### `stock.valuation.adjustment.lines` -- Per-Move Adjustments
> [`stock_landed_cost.py:304-388`](../addons/stock_landed_costs/models/stock_landed_cost.py#L304-L388)

| Field | Type | Purpose |
|---|---|---|
| `move_id` | Many2one(stock.move) | The receipt move being adjusted |
| `quantity` | Float | Move quantity |
| `weight` | Float | Product weight * quantity |
| `volume` | Float | Product volume * quantity |
| `former_cost` | Monetary | Original move value |
| `additional_landed_cost` | Monetary | Computed adjustment amount |
| `final_cost` | Monetary | `former_cost + additional_landed_cost` |

---

## Landed Costs -- Full Flow

### Restriction

Landed costs can **only** be applied to products with `cost_method` in `('fifo', 'average')`. Standard price products are excluded.

Source: [`get_valuation_lines()`](../addons/stock_landed_costs/models/stock_landed_cost.py#L155-L178)

### Validation Flow

Source: [`button_validate()`](../addons/stock_landed_costs/models/stock_landed_cost.py#L103-L153)

1. `compute_landed_cost()` -- splits costs across products using the chosen split method
2. `_check_sum()` -- validates that total adjustment equals `amount_total` and each cost line's adjustments sum to its `price_unit`
3. For each adjustment line with `product.valuation == 'real_time'`:
   - Creates accounting entries: Debit Stock Valuation, Credit Expense account
   - Proportional to `remaining_qty / quantity` (only adjusts the still-in-stock portion)
4. Calls `_set_value()` on all adjusted moves -- recomputes their values with the landed cost included
5. Posts the journal entry

### How Landed Costs Integrate with Move Value

When `_get_value_data()` runs on a move that has landed costs, the `_get_value_from_extra()` method (overridden in `stock_landed_costs`) adds the landed cost amount to the move's base value.

Source: [`stock_landed_costs/models/stock_move.py:14-40`](../addons/stock_landed_costs/models/stock_move.py#L14-L40)

This means landed costs become part of the move's `value` field, which then feeds into FIFO stack calculations and AVCO computations.

**Example:**
```
Receipt: 100 units of Product A @ $10 = $1,000
Receipt: 50 units of Product B @ $20 = $1,000

Landed Cost: $300 freight, split "By Quantity"
  Product A: $300 * (100/150) = $200 additional
  Product B: $300 * (50/150) = $100 additional

Product A move value: $1,000 + $200 = $1,200 (effective cost: $12/unit)
Product B move value: $1,000 + $100 = $1,100 (effective cost: $22/unit)

Journal Entry:
  Debit: Stock Valuation Account  $300
  Credit: Freight Expense Account  $300
```

---

## Account Configuration

### Product Accounts

Source: [`_get_product_accounts()`](../addons/stock_account/models/product.py#L96-L108)

**Fallback order for Stock Valuation Account:**
1. `product_category.property_stock_valuation_account_id` (company-dependent)
2. Company-dependent fallback for the field
3. `res.company.account_stock_valuation_id`

**Stock Variation Account:** `stock_valuation_account.account_stock_variation_id` (related field on the account itself)

### Account-Level Fields

Source: [`account_account.py`](../addons/stock_account/models/account_account.py)

| Field | Type | Purpose |
|---|---|---|
| `account_stock_variation_id` | Many2one(account.account) | "Variation Account" -- inventory variation at closing |
| `account_stock_expense_id` | Many2one(account.account) | "Expense Account" -- counterpart for closing adjustments |

### Product Category Fields

Source: [`product.py:479-538`](../addons/stock_account/models/product.py#L479-L538)

| Field | Technical Name | UI Label | Type | Purpose |
|---|---|---|---|---|
| Valuation | `property_valuation` | "Inventory Valuation" | Selection (company_dependent) | `periodic` or `real_time` |
| Cost Method | `property_cost_method` | "Costing Method" | Selection (company_dependent) | `standard`, `fifo`, `average` |
| Stock Journal | `property_stock_journal` | "Stock Journal" | Many2one (company_dependent) | Journal for automated JEs |
| Stock Valuation Account | `property_stock_valuation_account_id` | "Stock Valuation Account" | Many2one (company_dependent) | Balance sheet inventory account |
| Price Difference Account | `property_price_difference_account_id` | "Price Difference Account" | Many2one (company_dependent) | Holds standard vs bill price difference |
| Stock Variation Account | `account_stock_variation_id` | "Stock Variation Account" | Many2one (related) | From `property_stock_valuation_account_id.account_stock_variation_id` |
| Anglo-Saxon Accounting | `anglo_saxon_accounting` | -- | Boolean (computed) | From `company.anglo_saxon_accounting` |

### Company-Level Fields

Source: [`res_company.py:9-47`](../addons/stock_account/models/res_company.py#L9-L47)

| Field | Technical Name | UI Label | Default |
|---|---|---|---|
| Stock Journal | `account_stock_journal_id` | "Stock Journal" | -- |
| Stock Valuation Account | `account_stock_valuation_id` | "Stock Valuation Account" | -- |
| Production WIP Account | `account_production_wip_account_id` | "Production WIP Account" | -- |
| Production WIP Overhead | `account_production_wip_overhead_account_id` | "Production WIP Overhead" | -- |
| Inventory Period | `inventory_period` | "Inventory Period" | `manual` |
| Valuation | `inventory_valuation` | "Valuation" | `periodic` |
| Cost Method | `cost_method` | "Cost Method" | `standard` |
| Anglo-Saxon | `anglo_saxon_accounting` | "Anglo-Saxon Accounting" | -- |

### Location-Level Fields

Source: [`stock_location.py:11-14`](../addons/stock_account/models/stock_location.py#L11-L14)

| Field | Technical Name | Purpose |
|---|---|---|
| Stock Valuation Account | `valuation_account_id` | Location-specific expense account for reclassification |

When a location has `valuation_account_id`, moves into/out of that location create separate reclassification journal entries (debiting the location's account and crediting the product's stock valuation account, or vice versa).

---

## Configuration (Settings)

Source: [`res_config_settings.py`](../addons/stock_account/models/res_config_settings.py)

| Setting | Technical Name | Type | Effect |
|---|---|---|---|
| Landed Costs | `module_stock_landed_costs` | Boolean | Installs the `stock_landed_costs` module |
| Display Lots on Invoices | `group_lot_on_invoice` | Boolean | `implied_group='stock_account.group_lot_on_invoice'` -- shows lot/serial numbers on invoice lines |

### Landed Costs Settings

Source: [`addons/stock_landed_costs/models/res_config_settings.py`](../addons/stock_landed_costs/models/res_config_settings.py)

| Setting | Technical Name | Type | Effect |
|---|---|---|---|
| LC Journal | `lc_journal_id` | Many2one(account.journal) | Default journal for landed cost entries |

---

## Key Methods

| Method | File:Line | Purpose |
|---|---|---|
| `_action_done()` | [`stock_move.py:161`](../addons/stock_account/models/stock_move.py#L161) | Orchestrates valuation on move completion |
| `_set_value()` | [`stock_move.py:258`](../addons/stock_account/models/stock_move.py#L258) | Assigns monetary value to moves based on cost method |
| `_get_value_data()` | [`stock_move.py:313`](../addons/stock_account/models/stock_move.py#L313) | Priority-based value resolution for incoming moves |
| `_get_valued_qty()` | [`stock_move.py:400`](../addons/stock_account/models/stock_move.py#L400) | Returns quantity in product UOM for valued move lines |
| `_create_account_move()` | [`stock_move.py:176`](../addons/stock_account/models/stock_move.py#L176) | Creates and posts stock journal entry |
| `_should_create_account_move()` | [`stock_move.py:616`](../addons/stock_account/models/stock_move.py#L616) | Eligibility check for JE creation |
| `_get_account_move_line_vals()` | [`stock_move.py:201`](../addons/stock_account/models/stock_move.py#L201) | Determines debit/credit accounts and amounts |
| `_get_cogs_price_unit()` | [`stock_move.py:238`](../addons/stock_account/models/stock_move.py#L238) | COGS unit price (FIFO: from move values; else: standard_price) |
| `_get_move_directions()` | [`stock_move.py:465`](../addons/stock_account/models/stock_move.py#L465) | Classify move lines as in/out based on location valuation |
| `_run_fifo()` | [`product.py:368`](../addons/stock_account/models/product.py#L368) | Computes FIFO cost for given quantity |
| `_run_fifo_get_stack()` | [`product.py:409`](../addons/stock_account/models/product.py#L409) | Builds the ordered FIFO stack of incoming moves |
| `_run_avco()` | [`product.py:262`](../addons/stock_account/models/product.py#L262) | Computes weighted average cost |
| `_update_standard_price()` | [`product.py:462`](../addons/stock_account/models/product.py#L462) | Updates standard_price from FIFO/AVCO computation |
| `_compute_value()` | [`product.py:141`](../addons/stock_account/models/product.py#L141) | Computes `total_value` and `avg_cost` on product |
| `_get_product_accounts()` | [`product.py:96`](../addons/stock_account/models/product.py#L96) | Returns stock valuation + variation accounts |
| `_change_standard_price()` | [`product.py:193`](../addons/stock_account/models/product.py#L193) | Creates product.value record on manual price change |
| `_with_valuation_context()` | [`product.py:239`](../addons/stock_account/models/product.py#L239) | Adds valued locations and owner filters to context |
| `_get_remaining_moves()` | [`product.py:250`](../addons/stock_account/models/product.py#L250) | Returns remaining inventory by move (FIFO stack) |
| `action_close_stock_valuation()` | [`res_company.py:49`](../addons/stock_account/models/res_company.py#L49) | Manual/auto closing entry creation |
| `_stock_account_prepare_realtime_out_lines_vals()` | [`account_move.py:68`](../addons/stock_account/models/account_move.py#L68) | COGS line generation on invoice posting |
| `_stock_account_prepare_anglo_saxon_in_lines_vals()` | [`purchase_stock/account_invoice.py:12`](../addons/purchase_stock/models/account_invoice.py#L12) | Purchase price difference lines (Anglo-Saxon + Standard) |
| `_get_cogs_value()` | [`account_move_line.py:51`](../addons/stock_account/models/account_move_line.py#L51) | COGS value per invoice line |
| `_eligible_for_stock_account()` | [`account_move_line.py:30`](../addons/stock_account/models/account_move_line.py#L30) | Checks if product line qualifies for COGS |
| `_compute_account_id()` | [`account_move_line.py:13`](../addons/stock_account/models/account_move_line.py#L13) | Overrides purchase bill account to stock valuation |
| `button_validate()` | [`stock_landed_cost.py:103`](../addons/stock_landed_costs/models/stock_landed_cost.py#L103) | Validates landed cost, creates JE, updates move values |
| `compute_landed_cost()` | [`stock_landed_cost.py:180`](../addons/stock_landed_costs/models/stock_landed_cost.py#L180) | Splits costs across products |

---

## Technical Scenarios (Code-Level Trace)

> For business-level walkthroughs, see "Complete Business Flow Walkthroughs" at the top of this document.
> These scenarios show what methods are called under the hood.

### Scenario 1: Purchase Receipt -- Code Trace (Perpetual FIFO)

```
1. Receipt validated -> stock.picking.button_validate()
   -> stock.move._action_done()
   -> _is_in() = True (Supplier loc is unvalued, WH/Stock is valued)
   -> _set_value(): move.value = _get_value()
      Priority chain: _get_value_from_quotation() returns PO line price * qty
   -> _create_account_move(): Debit Stock Valuation, Credit Location Account
   -> _update_standard_price(): standard_price = total_value / qty_available

2. Vendor bill posted -> account.move._post()
   -> _set_value() re-called on the receipt move
   -> _get_value_from_account_move() now returns actual bill amount
   -> move.value updated, standard_price updated
```

### Scenario 2: Customer Delivery + Invoice -- Code Trace (AVCO)

```
1. Delivery validated -> stock.move._action_done()
   -> _is_out() = True (WH/Stock is valued, Customers is unvalued)
   -> _set_value() called BEFORE super (line 165-166)
      move.value = standard_price * valued_qty (line 304)
   -> super()._action_done() runs
   -> _create_account_move(): only if location has valuation_account_id

2. Invoice posted -> account.move._post()
   -> _stock_account_prepare_realtime_out_lines_vals()
   -> For each eligible line:
      -> line._get_cogs_value() computes COGS price
      -> moves._get_cogs_price_unit() returns product.standard_price (AVCO)
   -> Creates display_type='cogs' lines:
      Debit COGS/Expense, Credit Stock Valuation
```

### Scenario 3: Purchase Receipt + Bill -- Code Trace (Anglo-Saxon Standard Cost)

```
1. Receipt validated -> stock.move._action_done()
   -> _set_value(): move.value = _get_value()
      No bill yet -> _get_value_from_quotation() returns PO price * qty
   -> _create_account_move(): Debit location_dest.valuation_account_id, Credit stock_valuation

2. Vendor bill posted -> account.move._post() (purchase_stock override)
   -> _stock_account_prepare_anglo_saxon_in_lines_vals()
   -> For each line: cost_method == 'standard' check
   -> _get_price_unit_val_dif_and_relevant_qty() computes difference
   -> If bill_price != standard_price:
      Creates price diff lines (display_type='cogs'):
        Debit: property_price_difference_account_id
        Credit: stock_valuation account (same as bill line account)
   -> env['account.move.line'].create(lines_vals_list)
   -> Then super()._post() runs
   -> _set_value() re-called on incoming moves (line 42)
```

### Scenario 4: Inventory Adjustment -- Code Trace

```
1. User updates quant quantity -> stock.quant._apply_inventory()
   -> Creates stock.move: WH/Stock -> Inventory Loss location
   -> _is_out() = True (valued -> unvalued)
   -> move.value = standard_price * adjustment_qty
   -> JE: Debit Inventory Loss, Credit Stock Valuation
```

### Scenario 5: Landed Cost Validation -- Code Trace

```
1. button_validate() called
   -> compute_landed_cost(): splits cost_lines across valuation_adjustment_lines
   -> _check_sum(): validates total adjustments == amount_total
   -> For each adjustment line (real_time products only):
      _create_accounting_entries():
        diff = additional_landed_cost * (remaining_qty / quantity)
        Debit Stock Valuation, Credit Expense
      Amount proportional to remaining_qty / quantity
   -> Creates account.move with all lines, posts it
   -> _set_value() re-called on all adjusted moves
      -> _get_value_from_extra() now includes landed cost amounts
   -> _update_standard_price() on affected products
```

### Scenario 6: Customer Return -- Code Trace

```
1. Return picking validated -> stock.move._action_done()
   -> _is_in() = True (Customer is unvalued, WH/Stock is valued)
   -> _set_value(): move.value = _get_value()
      -> _get_value_from_returns(): origin_move.value * qty / origin_valued_qty
   -> _create_account_move(): Debit location.valuation_account_id, Credit Stock Valuation
   -> _update_standard_price(): AVCO/FIFO recalculated

2. Credit note posted -> account.move._post()
   -> _stock_account_prepare_realtime_out_lines_vals()
   -> sign = -1 (out_refund)
   -> COGS lines reversed:
      Credit COGS/Expense, Debit Stock Valuation
```

### Scenario 7: Dropship -- Code Trace

```
1. Dropship move done -> stock.move._action_done()
   -> _is_dropshipped() = True (supplier -> customer)
   -> is_in = False, is_out = False, is_dropship = True
   -> _set_value() called for dropship moves (line 168)
      -> move.value = _get_value() (treated like incoming for value)
   -> _create_account_move(): NOT created (is_valued = False since not is_in/is_out)
   -> _update_standard_price() called

Note: Dropship moves update standard_price but don't create
stock journal entries since goods never enter company stock.
COGS is handled at invoice posting time.
```

---

## Historical Valuation (Reporting at Past Dates)

Odoo supports computing inventory value at any past date using context keys.

**Context key:** `to_date` -- when set, all valuation computations filter moves up to this date.

**How it works:**
- `_compute_value()` passes `to_date` to `_run_fifo()` and `_run_avco()`
- `_run_fifo_get_stack()` filters moves with `date <= at_date`
- `_run_avco()` filters moves with `date <= at_date`
- `_get_standard_price_at_date()` finds the latest `product.value` record before the date

**Where used:** Inventory Valuation report, accounting reports that need point-in-time inventory values.

Source: [`_compute_value()`](../addons/stock_account/models/product.py#L141-L169) -- checks `self.env.context.get('to_date')`

---

## Security & Access

### stock_account

| Model | Access Group | CRUD |
|---|---|---|
| `product.value` | `stock.group_stock_manager` | Full CRUD |

### stock_landed_costs

| Model | Access Group | CRUD |
|---|---|---|
| `stock.landed.cost` | `stock.group_stock_manager` | Full CRUD |
| `stock.landed.cost.lines` | `stock.group_stock_manager` | Full CRUD |
| `stock.valuation.adjustment.lines` | `stock.group_stock_manager` | Full CRUD |

**Row-level security:** Landed costs enforce multi-company isolation with domain `[('company_id', 'in', company_ids)]`.

---

## Edge Cases & Gotchas

- **Negative stock with FIFO:** When outgoing quantity exceeds available stock, `_run_fifo()` extrapolates using the last known move's unit price. If no moves exist at all, falls back to `standard_price`. This means COGS may be estimated, not actual.

- **Multiple outgoing moves validated simultaneously:** The `fifo_qty_already_processed` context key prevents double-counting from the FIFO stack. Without it, all moves would see the same stack.

- **Landed costs only for FIFO/AVCO:** Standard-price products are excluded from landed cost allocation. `get_valuation_lines()` explicitly checks `cost_method not in ('fifo', 'average')`.

- **Cannot cancel validated landed costs:** You must create a negative landed cost to reverse. Source: [`button_cancel()`](../addons/stock_landed_costs/models/stock_landed_cost.py#L97-L101)

- **COGS lines have `display_type='cogs'`:** These are auto-managed. They're created on `_post()`, deleted on `button_draft()` and `button_cancel()`. Never manually edit them. The `cogs_origin_id` field links them back to the originating invoice line.

- **Vendor bill revalues receipt:** When a vendor bill is posted, `_post()` calls `_set_value()` on incoming moves. This updates the move value from PO price to actual bill price. This is critical for FIFO accuracy.

- **`disable_auto_revaluation` context:** Used internally to prevent infinite recursion when `_update_standard_price()` writes to `standard_price`, which would normally trigger `_change_standard_price()` again.

- **Consignment goods excluded:** Quants and moves with `owner_id` different from the company partner are excluded from valuation. This is the `_should_exclude_for_valuation()` check on both `stock.move` (line 625) and `stock.move.line`.

- **Closing date tracking:** The last closing date is stored in `ir.config_parameter` (key: `{company_id}.stock_valuation_closing_ids`). Only moves after the last closing are included in the next closing. Source: [`_get_last_closing_date()`](../addons/stock_account/models/res_company.py#L326-L340)

- **Category change triggers recomputation:** Changing a product's category (which may change cost method or valuation type) triggers `_update_standard_price()` on all variants. Source: [`ProductTemplate.write()`](../addons/stock_account/models/product.py#L76-L91)

- **Outgoing moves valued before super():** In `_action_done()`, outgoing moves get their value set BEFORE `super()._action_done()` runs. This is a deliberate design choice -- the FIFO stack must be read before incoming moves (processed in the same batch) change it. Limitation: simultaneous in+out validation may not reflect the incoming moves' cost.

- **Purchase price difference only for Standard + Anglo-Saxon:** The `_stock_account_prepare_anglo_saxon_in_lines_vals()` method explicitly checks `cost_method == 'standard'` (line 44). FIFO and AVCO products don't get price difference entries because their cost is dynamic.

- **COGS not created for dropship:** `_eligible_for_stock_account()` returns `False` if any linked stock move is a dropship. Dropship COGS is handled differently through the stock move's direct valuation.

- **Copy excludes COGS lines:** When duplicating a journal entry, COGS lines (`display_type='cogs'`) are stripped out. Source: [`copy_data()`](../addons/stock_account/models/account_move.py#L18-L27)

- **Currency conversion on price difference:** Purchase price differences are converted from invoice currency to company currency at today's date, not the invoice date. Source: [`account_invoice.py:77-81`](../addons/purchase_stock/models/account_invoice.py#L77-L81)

---

## Related Docs

- [`INDEX.md`](INDEX.md)
- [`inventory.md`](inventory.md) -- Core inventory (warehouses, routes, quants, reservations)
- [`accounting_coa.md`](accounting_coa.md) -- Chart of Accounts setup (stock accounts configuration)
- [`accounting_fixed_costs_guide.md`](accounting_fixed_costs_guide.md) -- Account types and reconciliation

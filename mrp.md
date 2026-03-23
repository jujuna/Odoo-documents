# Manufacturing (MRP)

> **Module:** `mrp` | **Path:** [`addons/mrp/`](../addons/mrp/)
> **Odoo Apps category:** Manufacturing
> **Enterprise extension:** `mrp_workorder` | **Path:** [`enterprise/mrp_workorder/`](../enterprise/mrp_workorder/)

---

## What It Does

The MRP module manages the full manufacturing process: defining how products are built (Bills of Material), scheduling production on work centers, tracking component consumption, and recording finished goods output. It creates Manufacturing Orders (MOs) that drive stock moves for raw materials and finished products. When Work Orders are enabled, each manufacturing step is tracked separately on specific work centers with time logging, capacity planning, and optional quality checks (enterprise).

---

## Key Concepts (Glossary)

Before diving in, here are the terms you will encounter throughout this document:

| Term | What It Means |
|---|---|
| **Bill of Material (BOM)** | A recipe/blueprint that lists what components (raw materials) and operations (steps) are needed to make a product. Think of it like a cooking recipe. |
| **Manufacturing Order (MO)** | A work ticket that tells the factory "make X units of this product using this BOM." It tracks the entire production run from start to finish. |
| **Work Order (WO)** | A single step within an MO. If your BOM has 3 operations (Cut, Assemble, Paint), the MO will have 3 work orders -- one per step. |
| **Work Center** | A physical machine, workstation, or area where operations happen -- e.g., "CNC Machine #2", "Assembly Line A", "Paint Booth". |
| **Operation** | A manufacturing step defined on a BOM -- e.g., "Cutting", "Welding", "Quality Check". Each operation runs on a specific work center. |
| **Component** | A raw material or sub-product consumed during manufacturing. Listed as BOM lines. |
| **Finished Product** | The output of manufacturing. What the MO produces. |
| **By-Product** | A secondary/incidental output created during manufacturing. Example: sawdust produced when cutting wood. |
| **Kit (Phantom BOM)** | A product that is never physically assembled. When sold or used in another BOM, it "explodes" into its individual components. No MO is created. |
| **Backorder** | When you produce fewer units than planned and click "Mark as Done", Odoo creates a new MO for the remaining quantity. That new MO is the backorder. |
| **Scrap** | Removing defective components or products from inventory during production. |
| **Unbuild** | The reverse of manufacturing -- disassembling a finished product back into its components. |
| **BOM Explosion** | The process of breaking down a BOM (and any nested BOMs) into a flat list of individual components. Happens automatically. |
| **Flexible Consumption** | Controls whether workers can consume more/less/different components than the BOM prescribes. |
| **OEE** | Overall Equipment Effectiveness -- a percentage measuring how productively a work center is used. |
| **MPS** | Master Production Schedule -- a planning tool for forecasting demand and scheduling production across time periods. |
| **Lead Time** | How many days it takes to manufacture a product. Used by the scheduler to plan when to start production. |

---

## When to Use This Module

Use MRP when your business transforms raw materials or components into finished products and you need to track that process inside Odoo.

### Best For
- Companies that manufacture, assemble, or kit products
- Tracking component consumption and finished goods production
- Scheduling production across work centers with capacity constraints
- Costing manufactured products (material + labor)
- Managing multi-step manufacturing with operation dependencies

### Not For
- Pure resellers (use Sales + Inventory instead)
- Subcontracting only without in-house manufacturing (use `mrp_subcontracting` standalone)
- Simple kitting without production tracking (phantom BOMs work without MOs)

---

## Quick Start Guide

New to MRP? Follow these steps to get your first manufacturing order running:

### Step 1: Enable Manufacturing
Install the **Manufacturing** app from Apps. That is it -- the module is ready.

### Step 2: Create a Product to Manufacture
1. Go to **Manufacturing -> Products -> Products -> New**
2. Set **Product Type** to "Goods" (must be a storable product)
3. Save

### Step 3: Create a Bill of Material
1. Go to **Manufacturing -> Bills of Materials -> New**
2. Select your product
3. Set **BOM Type** to "Manufacture this product"
4. In the **Components** tab, add raw materials with quantities
5. Save

### Step 4: Create a Manufacturing Order
1. Go to **Manufacturing -> Operations -> Manufacturing Orders -> New**
2. Select your product (the BOM auto-fills)
3. Set the quantity to produce
4. Click **Confirm** -- Odoo reserves your components from stock
5. Click **Mark as Done** -- Odoo consumes components and adds the finished product to inventory

**That is the simplest possible flow.** Everything below builds on this foundation.

---

## Real-World Use Cases

### Use Case 1: Furniture Manufacturer with Multi-Step Assembly
**Situation:** A furniture company builds tables. Each table requires a wooden top, 4 legs, screws, and varnish. Assembly happens in two steps: frame assembly, then finishing.

**In Odoo:** Create a BOM for "Dining Table" with components and two operations (Frame Assembly on "Assembly Line" work center, Finishing on "Paint Booth"). Create an MO for 10 tables. Confirm and plan. Workers start each work order, log time, and mark done. Odoo consumes components and receives finished tables into stock.

**Result:** Full traceability of materials consumed, labor time per operation, and production cost per unit.

### Use Case 2: Electronics Company with Partial Production
**Situation:** A batch of 100 circuit boards is in production but only 80 pass quality. The remaining 20 need to be produced in a follow-up run.

**In Odoo:** Start the MO for 100 units. After producing 80, click "Mark as Done". Odoo asks whether to create a backorder for the remaining 20. Confirm backorder. A new MO is created for 20 units with components already reserved.

**Result:** Inventory is accurate (80 boards received), and the remaining production is tracked separately.

### Use Case 3: Kit Product (Phantom BOM)
**Situation:** An e-commerce company sells a "Starter Kit" containing 3 products but never physically assembles them. When a sale order is confirmed, all 3 components should be picked from stock individually.

**In Odoo:** Create a BOM of type "Kit" (phantom) for the Starter Kit with the 3 component products. When a SO is confirmed, Odoo explodes the kit into 3 separate delivery lines. No MO is created.

**Result:** No manufacturing overhead. Stock is managed at the component level. The kit is just a sales convenience.

### Use Case 4: Auto-Created MO from a Sale Order
**Situation:** A customer orders 50 custom chairs. You want Odoo to automatically create a manufacturing order when the sale is confirmed.

**In Odoo:** Install `sale_mrp`. On the product, set the route to "Manufacture". Create a BOM. When the sale order is confirmed, Odoo's procurement engine calls [`_run_manufacture()`](../addons/mrp/models/stock_rule.py#L81) which automatically creates and confirms an MO for 50 chairs.

**Result:** No manual MO creation needed. Sales demand directly drives production.

### Use Case 5: Subcontracted Manufacturing
**Situation:** You design circuit boards but a vendor assembles them. You send components; they send back finished boards.

**In Odoo:** Install `mrp_subcontracting`. Create a BOM of type "Subcontracting" and link it to the vendor. When you receive goods from that vendor, Odoo automatically creates an MO at the subcontractor's virtual location, consuming components and producing finished goods.

**Result:** You track what the vendor makes without managing their shop floor.

---

## How-To Scenarios

### How to Create a Bill of Material
1. **Manufacturing -> Bills of Materials -> New**
2. Set the **Product** (must be a storable product)
3. Set **BOM Type**: "Manufacture this product" (normal) or "Kit" (phantom)
4. Add **Components** tab: each line specifies a component product and quantity per unit
5. (Optional) Add **Operations** tab: each operation specifies a work center, duration, and sequence. Requires "Work Orders" setting enabled.
6. (Optional) Add **By-Products** tab: secondary outputs from manufacturing
7. (Optional) Set **Flexible Consumption**: Allowed / Allowed with warning / Blocked

**What happens behind the scenes:** The BOM is the blueprint. When an MO is created for the product, [`_compute_workorder_ids()`](../addons/mrp/models/mrp_production.py#L605) generates work orders from operations, and component moves are created from BOM lines.

### How to Create and Process a Manufacturing Order
1. **Manufacturing -> Operations -> Manufacturing Orders -> New**
2. Select the **Product** and **Bill of Material** (auto-selected if only one BOM exists)
3. Set **Quantity** to produce
4. Click **Confirm** -- reserves components, creates stock moves
5. Click **Plan** (if work orders exist) -- schedules operations on work center calendars
6. For each work order: click **Start**, then **Done** when finished
7. Click **Mark as Done** on the MO -- posts inventory (consumes components, receives finished product)

**What happens behind the scenes:** Confirm calls [`action_confirm()`](../addons/mrp/models/mrp_production.py#L1581) which creates stock moves and confirms work orders. Mark as Done calls [`button_mark_done()`](../addons/mrp/models/mrp_production.py#L2170) which posts all moves to inventory.

### How to Enable Work Orders
1. **Settings -> Manufacturing -> Operations**
2. Enable **"Work Orders"** (field `group_mrp_routings`, implies group `mrp.group_mrp_routings`)
3. Save. Now BOMs show an **Operations** tab and MOs show **Work Orders** tab.

### How to Set Up Operation Dependencies
1. Enable **"Work Order Dependencies"** in Settings -> Manufacturing -> Operations (field `group_mrp_workorder_dependencies`, implies group `mrp.group_mrp_workorder_dependencies`)
2. On the BOM Operations tab, use the **Blocked By** field on each operation to specify which operations must complete first
3. When an MO is created, work orders inherit these dependencies. Blocked work orders show state "Waiting for another WO" until predecessors complete.

### How to Manufacture with Lot/Serial Numbers
1. On the finished product, enable **Tracking** = "By Lots" or "By Unique Serial Number" (in product form -> Inventory tab)
2. On components, enable tracking if you need to trace which lot of raw material went into which finished product
3. Create and confirm your MO
4. Before clicking **Mark as Done**, assign a **Lot/Serial Number** to the finished product
5. If using serial tracking, each individual unit needs its own serial -- Odoo will prompt you

**Why this matters:** Lot/serial tracking gives you full forward and backward traceability. You can answer "which customer received lot X?" and "which raw material lots went into finished product Y?"

### How to Handle Backorders (Partial Production)
1. Confirm an MO for, say, 100 units
2. Set **Quantity Producing** to the actual amount produced (e.g., 80)
3. Click **Mark as Done**
4. A wizard appears: "You produced 80 out of 100. Create a backorder for the remaining 20?"
5. Choose **Create Backorder** -- Odoo creates a new MO for 20 units with components already reserved
6. Choose **No Backorder** -- Odoo closes the MO. The 20 unproduced units are simply dropped.

**What happens behind the scenes:** [`button_mark_done()`](../addons/mrp/models/mrp_production.py#L2170) detects the under-production and calls [`_action_generate_backorder_wizard()`](../addons/mrp/models/mrp_production.py#L1784). If confirmed, [`_split_productions()`](../addons/mrp/models/mrp_production.py#L1932) creates the backorder MO with proportional stock moves and reservations. The original MO is renamed (e.g., `WH/MO/00001-001`) and the backorder gets the next sequence (e.g., `WH/MO/00001-002`).

---

## Understanding Bills of Material (BOM) in Depth

### BOM Types

#### `normal` -- Manufacture this product
Standard manufacturing BOM. Creates a Manufacturing Order with work orders for each operation. Components are consumed; finished product is produced.

**When to use:**
- Furniture assembly -- a table BOM defines wood top, legs, screws, varnish as components + operations (frame assembly, finishing). MO reserves components, work orders guide workers, finished tables land in stock with full cost traceability.
- Partial production -- start an MO for 100 units, produce 80, mark as done. Odoo creates a backorder MO for the remaining 20 with components already reserved.
- Multi-level manufacturing -- a sub-assembly (e.g., motor) has its own normal BOM. When the parent product MO is confirmed, Odoo triggers a separate MO for the sub-assembly via procurement rules.
- Make-to-order -- with `sale_mrp` installed, confirming a sale order auto-creates an MO for the exact quantity ordered.

#### `phantom` -- Kit
No MO is created. When used in a sale order or another MO, the kit is "exploded" into its individual components via [`explode()`](../addons/mrp/models/mrp_bom.py#L409). The kit product itself never appears in stock moves.

**When to use:**
- Product bundles -- an e-commerce "Starter Kit" containing 3 products. SO confirmation explodes the kit into 3 separate delivery lines, each picked individually from stock.
- Pre-packed sets -- a cosmetics gift set (lipstick + mascara + case). Stock is tracked at the component level; the customer sees one line item on the quote.
- Nested kits in manufacturing -- a normal BOM includes a phantom sub-BOM. During MO creation, `explode()` flattens the kit into individual components on the MO -- no separate MO for the sub-assembly.
- Variable packaging -- 6 bottles of wine sold as a "6-pack" or individually. The phantom BOM maps 1 "6-pack" to 6x single bottle. Stock exists only as single bottles; the 6-pack is a sales-only SKU.

#### `subcontract` -- Subcontracting (requires `mrp_subcontracting`)
The product is manufactured by an external vendor. No in-house MO is created directly. Instead, when you receive goods from the subcontractor, Odoo automatically creates an MO at the subcontractor's virtual location.

**When to use:**
- Outsourced assembly -- you design circuit boards but a vendor assembles them
- Overflow production -- your factory is at capacity, so you send excess work to a partner

### Multi-Level BOMs (Sub-Assemblies)

A finished product can contain components that themselves have BOMs. This creates a multi-level BOM structure.

**Example:**
```
Bicycle (finished product)
  |-- Frame Assembly (has its own BOM = sub-assembly)
  |     |-- Steel Tube
  |     |-- Welding Rod
  |-- Wheel Set (has its own BOM = sub-assembly)
  |     |-- Rim
  |     |-- Spokes
  |     |-- Tire
  |-- Seat
  |-- Handlebars
```

**How it works:**
- If the sub-assembly BOM is **normal**: Odoo creates a separate MO for the sub-assembly. The parent MO waits until the sub-assembly is produced. This is triggered by procurement rules.
- If the sub-assembly BOM is **phantom (kit)**: Odoo flattens the sub-assembly into the parent MO. No separate MO is created -- all components appear directly on the parent MO.

**When to use normal sub-assemblies:** When the sub-assembly is stocked independently (you keep Frame Assemblies in inventory) or when it is produced on a different work center/schedule.

**When to use phantom sub-assemblies:** When the sub-assembly is never stocked -- it is always made as part of the parent product.

### Flexible Consumption Modes

Controls what happens when a worker consumes more/less/different components than the BOM prescribes. Set on the BOM; enforced at Mark as Done via [`_get_consumption_issues()`](../addons/mrp/models/mrp_production.py#L1716).

| Mode | Field Value | What Happens | Who Can Override | When to Use |
|---|---|---|---|---|
| **Allowed** | `flexible` | No validation. Any quantity accepted. | Everyone | Prototyping, high-waste processes, material substitution |
| **Allowed with warning** | `warning` | Warning wizard appears. Any manufacturing user can click Confirm. | Any manufacturing user | Standard manufacturing (default). Catches accidents. |
| **Blocked** | `strict` | Wizard appears but Confirm is hidden. Only a **Force** button is available, restricted to Manufacturing Managers. | Manufacturing Managers only | Pharma, aerospace, food -- strict material accountability |

---

## By-Products

By-products are secondary outputs created during manufacturing. They are not the main product but have value or need tracking.

**Examples:**
- Sawdust produced when cutting wood
- Whey produced when making cheese
- Metal shavings from CNC machining
- Glycerin produced during soap manufacturing

### How to Set Up By-Products

1. Enable **By-Products** in Settings -> Manufacturing -> Operations (field `group_mrp_byproducts`)
2. Open a BOM -> **By-Products** tab -> Add a line
3. Set the by-product, quantity, and optionally which operation produces it

### By-Product Fields

| Field | Purpose |
|---|---|
| `product_id` | The by-product item |
| `product_qty` | Quantity produced per BOM unit |
| `operation_id` | "Produced in Operation" -- ties by-product output to a specific work order step |
| `cost_share` | Percentage of total manufacturing cost allocated to this by-product (0-100%) |

### Cost Sharing

The `cost_share` field determines how manufacturing costs are split between the main product and by-products.

**Example:** A sawmill BOM produces planks (main product) and sawdust (by-product with `cost_share = 5%`).
- Total manufacturing cost: $1000
- Sawdust receives: $1000 x 5% = $50
- Planks receive: $1000 x 95% = $950

**Constraint:** Total `cost_share` across all by-products on a BOM cannot exceed 100%.

---

## Manufacturing Steps (1, 2, 3-Step)

The warehouse setting `manufacture_steps` ([`stock_warehouse.py:31`](../addons/mrp/models/stock_warehouse.py#L31)) controls how many stock operations are involved in manufacturing.

**Configuration:** Inventory -> Configuration -> Warehouses -> select warehouse -> **Manufacture** field.

### 1-Step Manufacturing (`mrp_one_step`)

```
Warehouse Stock  --->  Manufacturing  --->  Warehouse Stock
```

- Components are consumed directly from the warehouse stock location
- Finished products land in stock immediately
- Simplest setup. No extra transfers.

**When to use:** Small operations. Components are stored near the production area. No staging or post-production inspection needed.

### 2-Step Manufacturing (`pbm`)

```
Warehouse Stock  --->  Pre-Production Location  --->  Manufacturing  --->  Warehouse Stock
                 (Pick Components transfer)
```

- An internal transfer (pick list) moves components from warehouse to a pre-production staging area
- The MO consumes from the pre-production location
- Finished products go directly to stock

**When to use:** Storage and production floor are in different areas. You want a picking step to stage components before workers start. Helps warehouse team prepare materials in advance.

### 3-Step Manufacturing (`pbm_sam`)

```
Warehouse Stock  --->  Pre-Production  --->  Manufacturing  --->  Post-Production  --->  Warehouse Stock
                 (Pick Components)                           (Store Finished Products)
```

- Pick components from stock to pre-production
- Manufacture (consumes from pre-production, produces to post-production)
- Store finished products from post-production to stock

**When to use:** Full control environments. Post-production step allows quality inspection, packaging, or labeling before products enter sellable stock.

### What Odoo Creates Per Step Configuration

| Picking Type | 1-step | 2-step | 3-step | Purpose |
|---|---|---|---|---|
| Manufacturing (`manu_type_id`) | Yes | Yes | Yes | The actual production operation |
| Pick Components (`pbm_type_id`) | No | Yes | Yes | Internal transfer: Stock -> Pre-Production location |
| Store Finished Product (`sam_type_id`) | No | No | Yes | Internal transfer: Post-Production -> Stock |

Source: [`stock_warehouse.py:221`](../addons/mrp/models/stock_warehouse.py#L221)

---

## Work Centers

A work center represents a physical location or machine where manufacturing operations happen -- an assembly line, a CNC machine, a paint booth. It defines capacity, availability (calendar), cost rate, and efficiency.

**When to create one:** Create a work center for each distinct production resource you need to schedule, track time on, or cost separately. If two machines do the same job, create both and link them as alternatives.

### Key Work Center Fields

| Field | UI Label | What It Controls |
|---|---|---|
| `name` | "Work Center" | Display name |
| `code` | "Code" | Short reference for reports |
| `time_start` | "Setup Time" | Fixed minutes added before each work order (not scaled by quantity). Example: 15 min to warm up a paint booth. |
| `time_stop` | "Cleanup Time" | Fixed minutes added after each work order. Example: 10 min to clean equipment. |
| `costs_hour` | "Cost per Hour" | Hourly rate for product costing. Applied to actual or estimated time depending on operation's `cost_mode`. |
| `time_efficiency` | "Time Efficiency" | Percentage (default 100%). Values below 100 increase scheduled duration. Example: 80% efficiency means a 15-min cycle is scheduled as 18.75 min (`15 x 100/80`). Use for slower machines or workers in training. |
| `resource_calendar_id` | "Working Hours" | Calendar defining when this work center operates. Work orders are only scheduled during these hours. |
| `alternative_workcenter_ids` | "Alternatives" | During planning, Odoo checks the primary work center and all alternatives, picks whichever has the earliest available slot. |
| `capacity_ids` | "Capacity" | Product-specific capacity overrides (see below) |
| `oee_target` | "OEE Target" | Target OEE percentage (default 90%), used for visual alerts |

### Work Center Status

Work centers have a real-time status computed from productivity logs:

| Status | Meaning | How It Is Set |
|---|---|---|
| **Normal** (idle) | No active work | No open productivity records |
| **In Production** | Actively producing | A worker has started a work order (productivity log with `loss_type` = productive) |
| **Blocked** | Equipment down | Someone clicked "Block" or logged an issue (availability/quality loss). All running work orders are stopped. |

To unblock: call [`unblock()`](../addons/mrp/models/mrp_workcenter.py#L285) -- closes the blocking log and returns to Normal.

### Product-Specific Capacity

Override default capacity and setup/cleanup times for specific products via `mrp.workcenter.capacity` lines.

**Example:** A CNC machine processes metal brackets at 4 units/cycle but plastic housings at 2 units/cycle. Add two capacity lines. The bracket work order schedules fewer cycles (shorter duration) than the housing work order for the same quantity.

**Duration formula** ([`mrp_routing.py:115`](../addons/mrp/models/mrp_routing.py#L115)):
```
cycle_number = ceil(quantity / capacity)
total_time = setup + cleanup + cycle_number x cycle_time x 100 / time_efficiency
```

**Numeric example:** Produce 100 brackets, capacity=4, setup=10min, cleanup=5min, cycle_time=15min, efficiency=100%.
`cycles = ceil(100/4) = 25`. `total = 10 + 5 + 25 x 15 = 390 minutes`.

### Work Center Time Off and Maintenance

Work centers respect their **Working Hours** calendar. To block a work center for maintenance:

1. Add a **Time Off** entry on the work center's resource calendar (or on the work center directly)
2. During planning, [`_get_first_available_slot()`](../addons/mrp/models/mrp_workcenter.py#L337) skips these blocked periods
3. Work orders are scheduled only during available working hours

The scheduling algorithm iterates 14-day windows (up to 700 days forward) to find an available slot large enough for the work order duration.

**Alternative work centers:** If the primary work center has no available slots soon, Odoo automatically checks alternative work centers and picks whichever is available earliest.

### OEE (Overall Equipment Effectiveness)

OEE measures how productively a work center is used over the last 30 days:

```
OEE = productive_time / (productive_time + blocked_time) x 100
```

Computed at [`mrp_workcenter.py:242`](../addons/mrp/models/mrp_workcenter.py#L242). Compare against `oee_target` to spot underperforming equipment.

**Performance** metric: `expected_duration / actual_duration x 100` -- shows whether work orders take longer than planned.

---

## Operations

An operation is a single manufacturing step on a BOM. Each operation runs on a specific work center and defines how long it takes and how cost is calculated. When an MO is confirmed, each operation becomes a work order.

**When to add operations:** When you need to track individual manufacturing steps, schedule work on specific machines, log labor time, or calculate per-step costs. Without operations, the MO has no work orders and production is a single confirm-and-done step.

### Duration Computation Modes

| Mode | How Duration Is Calculated | When to Use |
|---|---|---|
| **Manual** (`manual`) | Uses the fixed `time_cycle_manual` value you enter | New operations with no history. Predictable processes. |
| **Computed** (`auto`) | Averages the last N completed work orders (default N=10). Falls back to manual if no history. | Mature operations where real data improves accuracy. |

For **auto** mode, [`_compute_time_cycle()`](../addons/mrp/models/mrp_routing.py#L72) calculates: for each past WO, `duration / cycles` where `cycles = ceil(qty_produced / capacity)`, then averages the results.

### Cost Computation Modes

| Mode | Formula | When to Use |
|---|---|---|
| **Actual time** (`actual`) | `actual_duration / 60 x costs_hour` | When accurate post-production costing matters. Requires workers to start/stop timers. |
| **Estimated time** (`estimated`) | `duration_expected / 60 x costs_hour` | For quoting or planning when you don't track actual shop floor time. |

---

## Business Flow

### Manufacturing Order Lifecycle

```
Draft  -->  Confirmed  -->  In Progress  -->  To Close  -->  Done
  |            |                |
  v            v                v
Cancel      Cancel           Cancel
```

### MO States Explained

| State | What It Means | What You Can Do |
|---|---|---|
| **Draft** | MO exists but nothing has happened yet. Components are NOT reserved. You can freely edit product, BOM, quantity. | Confirm, Cancel, or Delete |
| **Confirmed** | Stock moves created. Components reserved (if available). Work orders ready to start. | Start work orders, Check Availability, Plan, Cancel |
| **In Progress** | At least one work order has been started, or a worker is actively producing. | Continue working, Mark as Done, Cancel |
| **To Close** | All work orders are done or cancelled. The MO is ready to be finalized. | Mark as Done |
| **Done** | Inventory posted. Components consumed, finished product received into stock. MO is locked. | Nothing -- this is final |
| **Cancelled** | All moves cancelled. Nothing was produced. | Nothing -- this is final |

### Work Order Lifecycle

```
Waiting (blocked)  -->  Ready  -->  In Progress  -->  Finished (done)
                                        |
                                        v
                                     Cancel
```

| State | What It Means |
|---|---|
| **Waiting for another WO** (`blocked`) | Previous work orders must complete first, or materials are unavailable |
| **Ready** (`ready`) | Can be started -- predecessors complete, materials available |
| **In Progress** (`progress`) | Worker is actively producing, timer running |
| **Finished** (`done`) | Quantities registered, time logged |
| **Cancelled** (`cancel`) | Skipped or MO was cancelled |

### What Happens When You Click Each Button

| Button | Method Called | What It Does |
|---|---|---|
| **Confirm** | [`action_confirm()`](../addons/mrp/models/mrp_production.py#L1581) | Creates stock moves for components and finished product. Confirms work orders. Triggers procurement for missing components. Sets state to Confirmed. |
| **Plan** | [`button_plan()`](../addons/mrp/models/mrp_production.py#L1663) | Auto-confirms if still draft. Schedules each work order on work center calendars. Finds available time slots. Creates calendar blocks. |
| **Check Availability** | [`action_assign()`](../addons/mrp/models/mrp_production.py#L1658) | Tries to reserve components from current stock. Updates availability status. |
| **Start** (on WO) | [`button_start()`](../addons/mrp/models/mrp_workorder.py#L645) | Starts the timer. Moves MO to In Progress state. |
| **Done** (on WO) | [`button_finish()`](../addons/mrp/models/mrp_workorder.py#L694) | Records produced quantity. Stops timer. Auto-picks unpicked components. |
| **Pause** (on WO) | [`button_pending()`](../addons/mrp/models/mrp_workorder.py#L742) | Pauses work -- closes current timer without finishing the work order. |
| **Mark as Done** (on MO) | [`button_mark_done()`](../addons/mrp/models/mrp_production.py#L2170) | Posts all stock moves to inventory. Finishes remaining work orders. Creates backorder if partial production. Locks the MO. |
| **Cancel** | [`action_cancel()`](../addons/mrp/models/mrp_production.py#L1797) | Cancels all stock moves and work orders. |

### action_confirm() -- Step by Step

1. Copies `consumption` setting from BOM
2. Creates stock moves for components (`move_raw_ids`) and finished products (`move_finished_ids`)
3. Confirms all moves via `_action_confirm()`
4. Triggers procurement scheduler for components not in stock
5. Confirms work orders and sets their cost mode
6. Confirms any related picking (for 2/3-step manufacturing)
7. Transitions state from `draft` to `confirmed`

### button_mark_done() -- Step by Step

1. Runs sanity checks (quantities, serial numbers)
2. Prompts for serial numbers if product is serial-tracked
3. Sets quantities on finished product moves
4. Finishes all work orders
5. Posts inventory via [`_post_inventory()`](../addons/mrp/models/mrp_production.py#L1862)
6. Sets state to `done`, locks the MO
7. If `qty_produced < product_qty`, calls [`_split_productions()`](../addons/mrp/models/mrp_production.py#L1932) to create a backorder for the remaining quantity

---

## How Work Orders Are Generated

When a BOM with operations is selected on an MO (or when product/qty changes in draft state), [`_compute_workorder_ids()`](../addons/mrp/models/mrp_production.py#L605) runs:

1. Calls [`bom.explode()`](../addons/mrp/models/mrp_bom.py#L409) to recursively expand the BOM (handles phantom sub-BOMs)
2. For each BOM that has operations, creates one `mrp.workorder` per operation
3. Each work order inherits: operation name, work center, expected duration, sequence
4. Component moves (`move_raw_ids`) are linked to specific work orders based on `bom_line.operation_id`
5. If operation dependencies are enabled on the BOM, `blocked_by_workorder_ids` is set based on `blocked_by_operation_ids`

Work orders are ordered by `sequence`. In the simplest case (no dependencies), they are all `ready` immediately. With dependencies enabled, only work orders whose predecessors are complete are `ready`; others are `blocked`.

---

## Scheduling (Planning)

When the user clicks **Plan**, [`button_plan()`](../addons/mrp/models/mrp_production.py#L1663) calls [`_plan_workorders()`](../addons/mrp/models/mrp_production.py#L1672):

1. For each work order (in dependency order):
   - Calculates expected duration: `(qty / capacity) x cycle_time + setup_time + cleanup_time`, adjusted by `time_efficiency`
   - Finds the next available slot on the work center's resource calendar
   - Creates a calendar leave (resource.calendar.leaves) to block that time slot
   - Sets `date_start` and `date_finished` on the work order
2. Updates MO `date_start` (earliest WO start) and `date_finished` (latest WO finish)
3. Sets `is_planned = True`

Alternative work centers are considered if the primary work center has no available slots in the near future.

---

## Component Consumption Flow

### How Components Are Tracked

Each component BOM line creates a `stock.move` in `move_raw_ids`:

| Field | Purpose |
|---|---|
| `raw_material_production_id` | Links move to the parent MO |
| `operation_id` | Which BOM operation consumes this component |
| `workorder_id` | Specific work order (set during planning) |
| `unit_factor` | Ratio: `component_qty / bom_qty`. Used to scale consumption with `qty_producing` |
| `should_consume_qty` | Expected quantity based on BOM formula |
| `picked` | Boolean: has the quantity been registered/confirmed |

### What Happens During Work Orders

1. When a work order starts, `qty_producing` is set to `qty_remaining` (or user-specified)
2. Component moves linked to that work order get their `quantity` set to `qty_producing x unit_factor`
3. When the work order finishes ([`button_finish()`](../addons/mrp/models/mrp_workorder.py#L694)), unpicked moves are auto-picked
4. When the MO is marked done, all moves are posted to inventory

---

## Scrap During Manufacturing

Workers can scrap defective components or finished products directly from an MO.

### How to Scrap

1. Open a confirmed/in-progress MO -> click **Scrap** button ([`button_scrap()`](../addons/mrp/models/mrp_production.py#L2359))
2. Select the product to scrap (component or finished product), quantity, and optionally a lot/serial
3. Confirm -> creates a `stock.scrap` record
4. Scrap generates a stock move from the source location to the scrap location (virtual inventory loss location)
5. The scrapped quantity is removed from available stock but remains traceable

**When to use:** A component is damaged during production, or a finished product fails inspection. Scrap removes it from productive inventory without cancelling the MO.

**Auto-replenishment:** If the scrap record has `should_replenish=True`, Odoo triggers a replenishment rule to reorder the scrapped product.

---

## Unbuild Orders

Unbuild orders reverse the manufacturing process -- disassemble a finished product back into its components.

> **Model:** `mrp.unbuild` | [`mrp_unbuild.py:11`](../addons/mrp/models/mrp_unbuild.py#L11)

### How to Unbuild

1. **Manufacturing -> Operations -> Unbuild Orders -> New**
2. Select the finished **Product**, **BOM**, and **Quantity**
3. Optionally link to a specific done MO (`mo_id`) and lot/serial
4. Click **Unbuild** -> [`action_unbuild()`](../addons/mrp/models/mrp_unbuild.py#L165):
   - Creates **consume moves**: finished product moves from location to production area
   - Creates **produce moves**: components move from production area back to destination location
   - If linked to an MO, uses the original MO's lot/serial tracking for accuracy
   - Posts activity note on the linked MO

**When to use:**
- Product recalled or returned -- break it down for component recovery
- Wrong product manufactured -- unbuild and reuse materials
- Quality failure on finished goods -- recover usable components

**Key constraint:** If linked to an MO, the MO must be in `done` state.

---

## Split and Merge Manufacturing Orders

### Splitting an MO

Divide one MO into multiple smaller MOs. Useful for batch sizing, parallel production on different lines, or scheduling flexibility.

1. Open an MO in draft/confirmed state -> **Split** button ([`action_split()`](../addons/mrp/models/mrp_production.py#L2468))
2. The split wizard shows: number of splits, quantity per split, optional responsible user and schedule date per split
3. Confirm -> creates backorder MOs with distributed quantities and stock moves

**Bulk split:** Select multiple MOs in list view -> Split opens a batch splitting wizard.

### Merging MOs

Combine multiple MOs into one. Useful when several small orders for the same product can be produced together.

1. Select multiple MOs in list view -> **Merge** ([`action_merge()`](../addons/mrp/models/mrp_production.py#L2484))
2. Requirements:
   - All MOs must be in **draft or confirmed** state
   - Same **product**, same **BOM**, same **picking type**
   - No manually added components or by-products (only BOM-defined lines)
3. Creates one merged MO with combined quantity

---

## Auto-Creation of Manufacturing Orders

MOs do not always need to be created manually. Odoo can automatically create them from:

### 1. Sale Orders (Make-to-Order)
- Requires `sale_mrp` module
- Set the product's route to include "Manufacture"
- When a sale order is confirmed, the procurement engine calls [`_run_manufacture()`](../addons/mrp/models/stock_rule.py#L81)
- An MO is automatically created and confirmed for the ordered quantity

### 2. Reorder Rules (Make-to-Stock)
- Set a reorder rule on the product with the "Manufacture" route
- When stock drops below the minimum, the scheduler creates an MO to replenish up to the maximum
- The MO is linked to the reorder rule (`orderpoint_id`)

### 3. Other Manufacturing Orders (Multi-Level BOM)
- When an MO needs a component that has its own BOM
- Odoo creates a child MO for the sub-assembly via procurement rules
- The child MO must complete before the parent MO can consume the component

### How _run_manufacture() Works

1. Finds the matching BOM (checks `values['bom_id']`, then `orderpoint.bom_id`, then `_bom_find`)
2. Checks if an existing draft/confirmed MO already exists for the same product+BOM -- if yes, increases its quantity instead of creating a duplicate
3. Otherwise creates a new MO via `_prepare_mo_vals` (sets dates, origin, picking type)
4. Auto-confirms if the procurement rule says so
5. Logs chatter links back to the triggering sale order or reorder rule

---

## Subcontracting Overview

> Requires `mrp_subcontracting` module ([`addons/mrp_subcontracting/`](../addons/mrp_subcontracting/))

Subcontracting lets you outsource manufacturing to external vendors while tracking production in Odoo.

### How It Works

1. **Create a Subcontracting BOM:** Set BOM type to "Subcontracting" and add the vendor(s) in `subcontractor_ids`
2. **Create a Purchase Order / Receipt:** When you receive goods from the subcontractor, Odoo detects the subcontracting BOM
3. **Automatic MO Creation:** On receipt confirmation, [`stock.move._action_confirm`](../addons/mrp_subcontracting/models/stock_move.py#L143) creates a linked MO at the subcontractor's virtual location
4. **Component Consumption:** Components are consumed from the subcontractor's location (reservation is bypassed -- components are assumed to be at the vendor)
5. **Finished Goods Receipt:** The finished product appears in your warehouse

### Key Constraints
- Subcontracting BOMs **cannot** have operations (no work orders -- the vendor handles production)
- Subcontracting BOMs **cannot** have by-products
- Components can be sent to the subcontractor via a resupply route

---

## Master Production Schedule (MPS)

> Requires `mrp_mps` module (install via Settings -> Manufacturing -> Master Production Schedule)

MPS is a demand planning tool that helps you forecast production needs across time periods.

### What It Does
- Shows a grid of products x time periods (weeks/months)
- For each cell: forecasted demand, existing supply, planned production, projected stock
- Lets you set safety stock targets
- One-click replenishment: creates MOs or purchase orders to meet the schedule

### How to Use
1. Enable MPS in Settings -> Manufacturing
2. Go to **Manufacturing -> Planning -> Master Production Schedule**
3. Add products to the schedule
4. Enter demand forecasts per period
5. Odoo calculates how much to produce to meet demand while maintaining safety stock
6. Click **Replenish** to create the MOs

---

## Manufacturing Costs

> Requires `mrp_account` module ([`addons/mrp_account/`](../addons/mrp_account/))

Manufacturing cost is calculated when an MO is marked done via [`_cal_price()`](../addons/mrp_account/models/mrp_production.py#L57):

```
Total Cost = Raw Material Cost + Work Center Cost + Extra Cost
```

| Cost Component | How It Is Calculated |
|---|---|
| **Raw Material Cost** | Sum of consumed stock move values (component cost x consumed qty, using product costing method) |
| **Work Center Cost** | Sum of each work order's cost: `(duration / 60) x workcenter.costs_hour`. Uses actual or estimated time depending on operation's `cost_mode` |
| **Employee Cost** (enterprise) | `(duration / 60) x workcenter.employee_costs_hour x employee_ratio` per operation |
| **Extra Cost** | Manual per-unit adjustment field `extra_cost` on the MO x finished qty |

### By-Product Cost Allocation

Each by-product can have a `cost_share` percentage. The finished product receives the remaining share.

**Example:** Total cost = $1000, by-product sawdust has cost_share = 5%
- Sawdust cost: $1000 x 5% = $50
- Main product cost: $1000 x 95% = $950

**Final `price_unit`** on the finished product move = `total_cost x (1 - byproduct_share/100) / finished_qty`

### WIP Journal Entries
When work orders complete, [`_post_labour()`](../addons/mrp_account/models/mrp_production.py#L93) posts a journal entry debiting the production location's valuation account and crediting the expense account (work center or product expense).

---

## Manufacturing Lead Time

Two BOM fields control scheduling lead times ([`mrp_bom.py:86`](../addons/mrp/models/mrp_bom.py#L86)):

| Field | UI Label | Purpose |
|---|---|---|
| `produce_delay` | "Manufacturing Lead Time" | Average days to manufacture. Used by the scheduler to calculate when to start production. |
| `days_to_prepare_mo` | "Days to prepare Manufacturing Order" | Days in advance to create and confirm MOs, giving time to replenish components. |

**How they affect scheduling:** When a demand (sale order, reorder rule) triggers production, the scheduler subtracts `produce_delay + days_to_prepare_mo` from the demand date to determine when the MO should be created and started.

**Example:** Customer needs 50 chairs by March 20. Lead time = 5 days, prep time = 2 days. Odoo schedules the MO to start by March 13 (20 - 5 - 2).

---

## Reports

### Available Reports

| Report | What It Shows | Where to Find |
|---|---|---|
| **BOM Structure & Cost** | Explodes a BOM tree showing all components, costs per level, routes, and lead times | BOM form -> "Structure & Cost" button |
| **MO Overview** | Components, replenishments, and supply chain state for a specific MO | MO form -> "Overview" button |
| **Production Analysis** | Pivot/graph analysis of production data across MOs | Manufacturing -> Reporting -> Production Analysis |
| **OEE Report** | Equipment effectiveness per work center | Manufacturing -> Reporting -> OEE |
| **Delays Report** | Manufacturing orders that are late vs. scheduled | Manufacturing -> Reporting -> Delays |
| **Allocation Report** | Resource allocation across work centers and time periods | Manufacturing -> Reporting -> Allocation |

Source files: [`addons/mrp/report/`](../addons/mrp/report/)

### MO Overview (Valuation & Overview) -- Deep Dive

The MO Overview is a detailed report accessible from the **"Overview" stat button** on any Manufacturing Order form ([mrp_production_views.xml:268](../addons/mrp/views/mrp_production_views.xml#L268)). It shows component availability, replenishment sources, and **three cost columns** that together form the "valuation" aspect.

Backend model: [`report.mrp.report_mo_overview`](../addons/mrp/report/mrp_report_mo_overview.py) (AbstractModel).
Frontend OWL component: [`MoOverview`](../addons/mrp/static/src/components/mo_overview/mrp_mo_overview.js).

#### When It Appears

The Overview button is **always visible** on the MO form -- no state/group condition. It works in all MO states: Draft, Confirmed, In Progress, Done. However, the **content changes depending on state**:

| MO State | What's Shown | Cost Columns Visible |
|---|---|---|
| **Draft / Confirmed** | Components, availability (free qty, on-hand, reserved), replenishment sources (POs, child MOs, in-transit), receipt dates | BoM Cost, MO Cost |
| **In Progress** | Same + real-time consumption data | MO Cost, Real Cost |
| **Done** | Final consumed quantities, unit costs, cost breakdown per product (if byproducts exist) | MO Cost, Real Cost, Unit Costs |

#### The Three Cost Columns

These are the core of the "valuation" feature. Each line (component, operation, byproduct) has three cost values:

| Column | Field | What It Means | How It's Calculated |
|---|---|---|---|
| **BoM Cost** | `bom_cost` | The theoretical cost based strictly on the BoM definition | `bom_line.product_qty * unit_price * (mo_qty / bom_qty)` -- scales from BoM ratio to MO quantity |
| **MO Cost** | `mo_cost` | The expected cost for this specific MO, accounting for replenishment sources and actual planned quantities | For components: `unit_cost * expected_qty` + replenishment costs from child MOs/POs. For operations: `_compute_expected_operation_cost()` based on work center hourly rate * expected duration |
| **Real Cost** | `real_cost` | The actual cost incurred after production starts/finishes | For components: `unit_cost * actually_consumed_qty`. For operations: `actual_duration * hourly_rate`. When `mrp_account` is installed, uses `move._get_price_unit()` (actual valuation price) instead of `standard_price` |

Source: [_format_component_move()](../addons/mrp/report/mrp_report_mo_overview.py#L524), [_get_operations_data()](../addons/mrp/report/mrp_report_mo_overview.py#L285)

#### Color Decorators (Cost Comparison)

The report highlights cost variances with colors via [`_get_comparison_decorator()`](../addons/mrp/report/mrp_report_mo_overview.py#L270):

| Color | Meaning |
|---|---|
| **Green** (`success`) | Actual/current cost is **lower** than the reference cost |
| **Red** (`danger`) | Actual/current cost is **higher** than the reference cost |
| No color | Costs match |

What gets compared depends on MO state:
- **Before production starts**: MO Cost vs BoM Cost (did MO quantities deviate from BoM?)
- **After production starts**: Real Cost vs MO Cost (did actual consumption deviate from plan?)

#### Component Cost Calculation Details

For each component (`move_raw`):

1. **Unit cost**: `product.standard_price` converted to the move's UoM. With `mrp_account` installed and move done: actual `move._get_price_unit()` ([mrp_account override](../addons/mrp_account/report/mrp_report_mo_overview.py#L10))
2. **BoM cost**: `unit_cost * bom_line_qty * (mo_qty / bom_qty)` -- the BoM's theoretical amount scaled to MO quantity
3. **MO cost**: Sums up costs from replenishment sources. If a component comes from a child MO, it recursively computes that child MO's costs. If from a PO, uses the PO price. Remaining (non-replenished) quantity uses `standard_price`
4. **Real cost**: `unit_cost * quantity_actually_consumed` (only after picking/consumption)

#### Operation Cost Calculation Details

For each work order:

| State | MO Cost | Real Cost |
|---|---|---|
| **Not started** | `_compute_expected_operation_cost()` = `(duration_expected / 60) * costs_hour` | Same as MO Cost (estimated) |
| **In progress** | Same expected cost (or theorical if no expected duration) | `_compute_current_operation_cost()` = `(actual_duration / 60) * costs_hour` |
| **Done** | Expected cost (without employee cost in mrp_workorder) | `(actual_hours) * costs_hour` per work center |

With `mrp_workorder` (Enterprise), employee costs are added as separate lines per employee, using `employee_costs_hour` rate ([enterprise override](../enterprise/mrp_workorder/report/mrp_report_mo_overview.py#L10)).

#### Byproduct Cost Allocation

Each byproduct move has a `cost_share` field (percentage). The report:
1. Computes total costs (components + operations)
2. Multiplies by `cost_share / 100` for each byproduct
3. The **remaining share** (`1 - sum_of_byproduct_shares`) goes to the finished product

Source: [`_get_byproducts_data()`](../addons/mrp/report/mrp_report_mo_overview.py#L429)

#### Cost Breakdown Table (Done MOs with Byproducts)

When an MO is **done** and has **byproducts with cost_share > 0**, a cost breakdown table appears showing per-unit costs split between components and operations for each output product.

Source: [`_get_cost_breakdown_data()`](../addons/mrp/report/mrp_report_mo_overview.py#L143)

#### Summary Footer (Done MOs)

When MO is done, the footer shows ([_get_report_extra_lines()](../addons/mrp/report/mrp_report_mo_overview.py#L114)):

| Line | Formula |
|---|---|
| Unit MO Cost | `total_mo_cost / qty_produced` |
| Unit BoM Cost | `total_bom_cost / qty_produced` |
| Unit Real Cost | `total_real_cost / qty_produced` |
| Component Costs (total + unit) | Sum of all component `mo_cost` / `bom_cost` / `real_cost` |
| Operation Costs (total + unit) | Sum of all operation `mo_cost` / `bom_cost` / `real_cost` |

#### Data Flow

```
MO Form -> "Overview" stat button
  -> action_report_mo_overview (ir.actions.report)
    -> OWL component calls: report.mrp.report_mo_overview.get_report_values(production_id)
      -> _get_report_data()
        -> _get_components_data()     # components + replenishment lines
        -> _get_operations_data()     # work orders + durations + costs
        -> _compute_cost_sums()       # totals for components + operations
        -> _get_byproducts_data()     # cost allocation to byproducts
        -> _get_mo_summary()          # header row with final costs
        -> _get_report_extra_lines()  # footer with unit costs (done MOs)
        -> _get_cost_breakdown_data() # per-product breakdown (done + byproducts)
```

---

## Shop Floor (Enterprise)

> Requires `mrp_workorder` module

The Shop Floor is a tablet-optimized interface for production workers. Instead of navigating Odoo's back-office, workers see a simplified view focused on their work center.

### What Workers See
- List of work orders assigned to their work center
- Current operation instructions
- Quality check steps (if configured)
- Timer controls (Start / Pause / Done)
- Component scanning (barcode support)
- Lot/serial number registration

### How to Access
- **Manufacturing -> Shop Floor** (dedicated menu)
- Or navigate from a specific work order

### Time Tracking
The Shop Floor automatically tracks:
- When each work order was started and finished
- Pause durations
- Which employee worked on which order
- Productive vs. non-productive time (used for OEE calculation)

---

## Enterprise Extension: mrp_workorder

The enterprise `mrp_workorder` module adds:

| Feature | Description |
|---|---|
| Shop floor tablet interface | Touch-optimized UI for workers on the production floor |
| Quality checks | Integration with `quality.check` and `quality.point` -- run inspections during work orders |
| Employee tracking | Track which employees worked on each work order, login/logout per employee |
| Barcode scanning | Scan serial numbers, components, and work orders |
| Quality alerts | Create quality alerts directly from work order issues |
| Worksheets | Attach instruction pages/worksheets to operations |
| Production notes | Log notes per work order for future reference |

---

## Quality Checks in Manufacturing

Quality checks let you define inspections that workers must complete during production. They are an **enterprise** feature spread across several modules:

| Module | What It Adds |
|---|---|
| `quality` ([`enterprise/quality/`](../enterprise/quality/)) | Base framework: quality points, checks, alerts, teams |
| `quality_control` ([`enterprise/quality_control/`](../enterprise/quality_control/)) | Pass/fail, measurement with tolerances, frequency control |
| `quality_mrp` ([`enterprise/quality_mrp/`](../enterprise/quality_mrp/)) | Links checks to Manufacturing Orders |
| `quality_mrp_workorder` ([`enterprise/quality_mrp_workorder/`](../enterprise/quality_mrp_workorder/)) | Embeds checks as work order steps on shop floor tablet |

### Enabling Quality Checks

1. **Settings -> Manufacturing -> Operations** -> enable **Quality** (installs `quality_control`)
2. **Work Orders** must also be enabled (quality checks are steps inside work orders)
3. Create at least one **Quality Team** (Quality -> Configuration -> Quality Control Teams)

### How It Works: End-to-End

```
1. SETUP (one-time)
   BOM -> Operation -> add Quality Points (steps)
         e.g., "Measure thickness" (measure type, tolerance 4.8-5.2mm)
         e.g., "Visual inspection" (pass/fail type)
         e.g., "Register components" (register_consumed_materials type)

2. PRODUCTION
   MO confirmed -> Work Orders created from BOM operations

3. WORK ORDER START
   Worker clicks Start -> _create_checks() auto-generates quality.check
   records from the operation's quality points
   -> Checks form a doubly-linked chain (previous <-> next)
   -> First check becomes current_quality_check_id

4. CHECK EXECUTION (shop floor tablet)
   Worker sees current check -> completes it (pass/fail/measure/scan)
   -> _next() advances to next check in chain
   -> Failed check? Worker can create a Quality Alert

5. WORK ORDER FINISH
   Worker clicks Done -> verify_quality_checks() runs:
   - Auto-passes: register_consumed_materials, register_byproducts, instructions
   - All other types MUST be explicitly passed/failed
   - If any non-auto check is still 'none' -> UserError, cannot finish
```

### Check Types

| Type | What the Worker Does | Auto-pass on WO Finish? |
|---|---|---|
| **Pass - Fail** | Clicks Pass or Fail -- operator judgment | No |
| **Measure** | Enters numeric value; auto-pass/fail by comparing to tolerance range | No |
| **Instructions** | Reads on-screen instructions | Yes |
| **Take a Picture** | Uploads or captures photo evidence | No |
| **Register Consumed Materials** | Scans/selects component being consumed | Yes |
| **Register Production** | Enters lot/serial for finished product | No |
| **Register By-products** | Registers by-product output | Yes |
| **Print Label** | Prints product/lot label (PDF or ZPL) | No |

### Control Frequency

[`check_execute_now()`](../enterprise/quality_control/models/quality.py#L99) decides whether a check is created:

| Frequency | Behavior |
|---|---|
| **All** | Always creates the check (default) |
| **Randomly** | Creates check N% of the time (e.g., 30% = roughly 3 out of 10 WOs) |
| **Periodically** | Only if no check from this point exists within the last N days/weeks/months |
| **On-demand** | Manual creation only. Cannot be used with work order quality points. |

### Quality Alerts

When a check fails, the worker can create a **quality alert** from the work order. The alert auto-fills workorder, production order, work center, and product.

Alerts follow a kanban pipeline: **New -> Confirmed -> Action Proposed -> Solved**. Each alert tracks:
- **Root cause**: Workcenter Failure, Parts Quality, Work Operation, Others
- **Corrective action**: what was fixed
- **Preventive action**: how to prevent recurrence
- **Priority**: normal / low / high / very high

---

## Configuration Reference

| Setting | Field | Location | What It Enables |
|---|---|---|---|
| Work Orders | `group_mrp_routings` | Settings -> Manufacturing -> Operations | Operations on BOMs, work orders on MOs |
| By-Products | `group_mrp_byproducts` | Settings -> Manufacturing -> Operations | By-product lines on BOMs |
| Work Order Dependencies | `group_mrp_workorder_dependencies` | Settings -> Manufacturing -> Operations | "Blocked By" field on operations |
| Unlock Manufacturing Orders | `group_unlocked_by_default` | Settings -> Manufacturing -> Operations | MOs are unlocked by default (can edit after confirm) |
| Allocation Report | `group_mrp_reception_report` | Settings -> Manufacturing -> Operations | Shows allocation report for MOs |
| Subcontracting | `module_mrp_subcontracting` | Settings -> Manufacturing -> Operations | Installs `mrp_subcontracting` module |
| Quality | `module_quality_control` | Settings -> Manufacturing -> Operations | Installs `quality_control` module |
| PLM | `module_mrp_plm` | Settings -> Manufacturing -> Operations | Installs `mrp_plm` (Product Lifecycle Management) |
| Master Production Schedule | `module_mrp_mps` | Settings -> Manufacturing -> Operations | Installs `mrp_mps` for demand-driven planning |

---

## Dependencies

### Requires (must be installed)

| Module | Why |
|---|---|
| `product` | Product definitions (BOM references products) |
| `stock` | Stock moves for component consumption and finished product receipt |
| `resource` | Work center calendars, capacity planning, scheduling |

### Optional Integrations

| Module | What It Enables |
|---|---|
| `mrp_workorder` (enterprise) | Shop floor tablet interface, quality checks, employee tracking on work orders |
| `mrp_subcontracting` | Outsource manufacturing operations to vendors |
| `mrp_plm` | Product Lifecycle Management -- engineering change orders on BOMs |
| `mrp_mps` | Master Production Schedule -- demand-driven planning |
| `quality_control` | Quality checks integrated into work order steps |
| `stock_account` / `mrp_account` | Manufacturing cost computation and journal entries |
| `sale_mrp` | Auto-creates MOs from confirmed sale orders |
| `purchase_mrp` | Triggers purchase orders for missing components |

---

## Key Models Reference

### `mrp.production` -- Manufacturing Order
> [`mrp_production.py`](../addons/mrp/models/mrp_production.py)

| Field | Type | UI Label | Purpose |
|---|---|---|---|
| `name` | Char | "Reference" | Auto-generated sequence (e.g., WH/MO/00001) |
| `product_id` | Many2one (product.product) | "Product" | Product being manufactured |
| `product_qty` | Float | "Quantity" | Quantity to produce |
| `bom_id` | Many2one (mrp.bom) | "Bill of Material" | BOM used for this production |
| `state` | Selection | "State" | Lifecycle state (see States table) |
| `reservation_state` | Selection | "Materials Availability" | `confirmed` (waiting), `assigned` (ready), `waiting` |
| `date_start` | Datetime | "Start Date" | Planned or actual start |
| `date_finished` | Datetime | "End Date" | Planned or actual end |
| `move_raw_ids` | One2many (stock.move) | "Components" | Stock moves for raw materials to consume |
| `move_finished_ids` | One2many (stock.move) | "Finished Products" | Stock moves for finished goods to receive |
| `workorder_ids` | One2many (mrp.workorder) | "Work Orders" | Operations to perform |
| `qty_producing` | Float | "Quantity Producing" | Current batch quantity being produced |
| `lot_producing_ids` | Many2many (stock.lot) | "Lot/Serial Number" | Lot/serial for finished product |
| `is_planned` | Boolean | "Is Planned" | True when work orders have scheduled dates |
| `is_locked` | Boolean | "Is Locked" | Prevents changes after completion |
| `location_src_id` | Many2one (stock.location) | "Components Location" | Where components are picked from |
| `location_dest_id` | Many2one (stock.location) | "Finished Products Location" | Where finished goods are stored |
| `consumption` | Selection | "Flexible Consumption" | `flexible`, `warning`, or `strict` -- copied from BOM on confirm |

### `mrp.workorder` -- Work Order
> [`mrp_workorder.py`](../addons/mrp/models/mrp_workorder.py)

| Field | Type | UI Label | Purpose |
|---|---|---|---|
| `name` | Char | "Work Order" | Operation name |
| `production_id` | Many2one (mrp.production) | "Manufacturing Order" | Parent MO |
| `operation_id` | Many2one (mrp.routing.workcenter) | "Operation" | BOM operation this WO executes |
| `workcenter_id` | Many2one (mrp.workcenter) | "Work Center" | Where this operation is performed |
| `state` | Selection | "Status" | `blocked`, `ready`, `progress`, `done`, `cancel` |
| `sequence` | Integer | "Sequence" | Execution order |
| `qty_production` | Float | "Original Production Quantity" | Total qty from MO |
| `qty_producing` | Float | "Currently Produced Quantity" | Batch being produced now |
| `qty_produced` | Float | "Quantity Produced" | Already finished |
| `qty_remaining` | Float | "Quantity Remaining" | Left to produce |
| `duration_expected` | Float | "Expected Duration" | Planned minutes (from operation) |
| `duration` | Float | "Real Duration" | Actual minutes (from time logs) |
| `date_start` | Datetime | "Start Date" | Scheduled/actual start |
| `date_finished` | Datetime | "End Date" | Scheduled/actual end |
| `time_ids` | One2many (mrp.workcenter.productivity) | "Time Tracking" | Productivity time logs |
| `blocked_by_workorder_ids` | Many2many (mrp.workorder) | "Blocked By" | WOs that must complete first |
| `move_raw_ids` | Many2many (stock.move) | "Moves" | Component moves consumed in this WO |

### `mrp.bom` -- Bill of Material
> [`mrp_bom.py`](../addons/mrp/models/mrp_bom.py)

| Field | Type | UI Label | Purpose |
|---|---|---|---|
| `product_tmpl_id` | Many2one (product.template) | "Product" | Product this BOM manufactures |
| `product_id` | Many2one (product.product) | "Product Variant" | Specific variant (blank = all variants) |
| `product_qty` | Float | "Quantity" | Base quantity this BOM produces |
| `type` | Selection | "BOM Type" | `normal` (Manufacture), `phantom` (Kit), `subcontract` (Subcontracting) |
| `bom_line_ids` | One2many (mrp.bom.line) | "Components" | List of component products and quantities |
| `operation_ids` | One2many (mrp.routing.workcenter) | "Operations" | Manufacturing steps/operations |
| `byproduct_ids` | One2many (mrp.bom.byproduct) | "By-Products" | Secondary outputs |
| `consumption` | Selection | "Flexible Consumption" | `flexible`, `warning`, `strict` |
| `ready_to_produce` | Selection | "Manufacturing Readiness" | `all_available` or `asap` |
| `allow_operation_dependencies` | Boolean | "Operation Dependencies" | Enable per-operation sequencing |
| `produce_delay` | Float | "Manufacturing Lead Time" | Lead time in days |

### `mrp.bom.line` -- BOM Component Line
> [`mrp_bom.py:656`](../addons/mrp/models/mrp_bom.py#L656)

| Field | Type | UI Label | Purpose |
|---|---|---|---|
| `product_id` | Many2one (product.product) | "Component" | Component product |
| `product_qty` | Float | "Quantity" | Quantity per BOM unit |
| `operation_id` | Many2one (mrp.routing.workcenter) | "Consumed in Operation" | Which operation consumes this component |
| `bom_product_template_attribute_value_ids` | Many2many | "Apply on Variants" | Restrict line to specific product variants |

### `mrp.bom.byproduct` -- By-Product Line
> [`mrp_bom.py:829`](../addons/mrp/models/mrp_bom.py#L829)

| Field | Type | UI Label | Purpose |
|---|---|---|---|
| `product_id` | Many2one (product.product) | "By-product" | The secondary product |
| `product_qty` | Float | "Quantity" | Quantity produced per BOM unit |
| `operation_id` | Many2one (mrp.routing.workcenter) | "Produced in Operation" | Which operation creates this by-product |
| `cost_share` | Float | "Cost Share (%)" | Percentage of manufacturing cost allocated to this by-product (0-100) |

### `mrp.routing.workcenter` -- Operation
> [`mrp_routing.py:9`](../addons/mrp/models/mrp_routing.py#L9)

| Field | Type | UI Label | Purpose |
|---|---|---|---|
| `name` | Char | "Operation" | Operation name |
| `bom_id` | Many2one (mrp.bom) | "Bill of Material" | Parent BOM |
| `workcenter_id` | Many2one (mrp.workcenter) | "Work Center" | Where this operation runs |
| `sequence` | Integer | "Sequence" | Execution order |
| `time_mode` | Selection | "Duration Computation" | `manual` (fixed) or `auto` (computed from past WOs) |
| `time_mode_batch` | Integer | "Based on last" | Number of past work orders to average (default 10) |
| `time_cycle_manual` | Float | "Manual Duration" | Fixed cycle time in minutes |
| `time_cycle` | Float (computed) | "Duration" | Effective cycle time |
| `blocked_by_operation_ids` | Many2many | "Blocked By" | Operations that must complete first |
| `cost_mode` | Selection | "Cost Mode" | `actual` or `estimated` cost calculation |

### `mrp.workcenter` -- Work Center
> [`mrp_workcenter.py:21`](../addons/mrp/models/mrp_workcenter.py#L21)

| Field | Type | UI Label | Purpose |
|---|---|---|---|
| `name` | Char | "Work Center" | Name |
| `code` | Char | "Code" | Short reference |
| `time_start` | Float | "Setup Time" | Fixed minutes before each work order |
| `time_stop` | Float | "Cleanup Time" | Fixed minutes after each work order |
| `costs_hour` | Float | "Cost per Hour" | Hourly rate for costing |
| `time_efficiency` | Float | "Time Efficiency" | Percentage (default 100) |
| `resource_calendar_id` | Many2one | "Working Hours" | When this work center operates |
| `alternative_workcenter_ids` | Many2many | "Alternatives" | Fallback work centers for scheduling |
| `oee` | Float (computed) | "OEE" | Overall Equipment Effectiveness (last 30 days) |
| `oee_target` | Float | "OEE Target" | Target percentage (default 90) |
| `performance` | Float (computed) | "Performance" | `expected_duration / actual_duration x 100` |

---

## Key Methods Reference

### Manufacturing Order

| Method | Location | Purpose |
|---|---|---|
| `action_confirm()` | [`mrp_production.py:1581`](../addons/mrp/models/mrp_production.py#L1581) | Confirm MO: create moves, confirm WOs, trigger procurement |
| `action_assign()` | [`mrp_production.py:1658`](../addons/mrp/models/mrp_production.py#L1658) | Reserve components from stock |
| `button_plan()` | [`mrp_production.py:1663`](../addons/mrp/models/mrp_production.py#L1663) | Schedule work orders on calendars |
| `_plan_workorders()` | [`mrp_production.py:1672`](../addons/mrp/models/mrp_production.py#L1672) | Find calendar slots for each WO |
| `button_mark_done()` | [`mrp_production.py:2170`](../addons/mrp/models/mrp_production.py#L2170) | Finalize: post inventory, handle backorders |
| `_post_inventory()` | [`mrp_production.py:1862`](../addons/mrp/models/mrp_production.py#L1862) | Post all stock moves |
| `action_cancel()` | [`mrp_production.py:1797`](../addons/mrp/models/mrp_production.py#L1797) | Cancel MO, all moves and work orders |
| `_compute_workorder_ids()` | [`mrp_production.py:605`](../addons/mrp/models/mrp_production.py#L605) | Generate work orders from BOM operations |
| `_split_productions()` | [`mrp_production.py:1932`](../addons/mrp/models/mrp_production.py#L1932) | Create backorder MO for partial production |

### Work Order

| Method | Location | Purpose |
|---|---|---|
| `button_start()` | [`mrp_workorder.py:645`](../addons/mrp/models/mrp_workorder.py#L645) | Start timer, set WO and MO to progress |
| `button_finish()` | [`mrp_workorder.py:694`](../addons/mrp/models/mrp_workorder.py#L694) | Record produced qty, stop timer, pick components |
| `button_pending()` | [`mrp_workorder.py:742`](../addons/mrp/models/mrp_workorder.py#L742) | Pause work order |
| `action_cancel()` | [`mrp_workorder.py:750`](../addons/mrp/models/mrp_workorder.py#L750) | Cancel work order |

### Bill of Material

| Method | Location | Purpose |
|---|---|---|
| `explode()` | [`mrp_bom.py:409`](../addons/mrp/models/mrp_bom.py#L409) | Recursively expand BOM (handles phantom/kit sub-BOMs) |
| `_bom_find()` | [`mrp_bom.py:378`](../addons/mrp/models/mrp_bom.py#L378) | Find the applicable BOM for a given product |

### Procurement

| Method | Location | Purpose |
|---|---|---|
| `_run_manufacture()` | [`stock_rule.py:81`](../addons/mrp/models/stock_rule.py#L81) | Auto-create MO from procurement (sale order, reorder rule) |

---

## UI Entry Points

| Entry Point | Path in UI | What It Does |
|---|---|---|
| Manufacturing Orders | Manufacturing -> Operations -> Manufacturing Orders | Create, view, and manage production orders |
| Bills of Materials | Manufacturing -> Bills of Materials | Define product recipes (components + operations) |
| Work Centers | Manufacturing -> Configuration -> Work Centers | Configure machines/stations with capacity and costs |
| Work Orders | Manufacturing -> Operations -> Work Orders | View all work orders across MOs |
| Unbuild Orders | Manufacturing -> Operations -> Unbuild Orders | Reverse a manufacturing order (disassemble) |
| Shop Floor | Manufacturing -> Shop Floor | Tablet-optimized worker interface (enterprise) |
| Production Analysis | Manufacturing -> Reporting -> Production Analysis | Pivot/graph analysis of MOs |
| MPS | Manufacturing -> Planning -> Master Production Schedule | Demand-driven production planning |

---

## Edge Cases and Gotchas

| Gotcha | Explanation |
|---|---|
| **Phantom BOMs don't create MOs** | They are exploded into components. If you need production tracking, use `normal` type. |
| **Changing BOM after confirm** | Stock moves are already created. Changing the BOM on a confirmed MO does NOT automatically update component moves. Use "Add a line" to manually adjust. |
| **Strict consumption** | With `strict` consumption, only Manufacturing Managers can close the MO if consumed quantities differ from the BOM formula. |
| **Backorders are automatic** | If you produce less than planned and click Mark as Done, Odoo offers to create a backorder. The remaining components stay reserved on the new MO. |
| **Work center blocking** | If a work center's `working_state` is `blocked`, workers cannot start work orders on it. Used for maintenance or equipment failures. |
| **Duration calculation** | Factors in setup time, cleanup time, cycle time, efficiency percentage, and work center capacity. Actual duration is tracked via productivity time logs. |
| **Serial-tracked products** | If the finished product uses serial tracking, Odoo requires lot/serial assignment before marking done. Each unit gets its own serial. |
| **MO locking** | After marking done, the MO is locked. To edit, enable "Unlock Manufacturing Orders" setting, or a Manufacturing Manager can unlock it. |
| **Merging requires identical BOMs** | You can only merge MOs that have the same product, BOM, and picking type, with no manually added lines. |
| **Subcontracting BOMs have no operations** | The vendor handles production steps. You cannot add work orders to a subcontracting BOM. |
| **Auto-MO grouping** | When the procurement engine creates an MO, it first checks if a draft/confirmed MO already exists for the same product+BOM. If yes, it increases the quantity instead of creating a duplicate. |

---

## Common Questions (FAQ)

**Q: How do I know if my components are available?**
A: Check the **Materials Availability** field on the MO. "Available" means all components are reserved. "Waiting" means some are missing. Click **Check Availability** to retry reservation.

**Q: Can I produce more than the MO quantity?**
A: Yes, if consumption is set to `flexible` or `warning`. Set `qty_producing` higher than `qty_remaining`. The extra quantity will be received into stock.

**Q: What happens if I cancel an MO that has reserved components?**
A: All reservations are released. The components go back to available stock. Nothing is consumed.

**Q: Can I add components that are not on the BOM?**
A: Yes, click "Add a line" on the Components tab. This only works if consumption is not `strict` (or you are a Manufacturing Manager).

**Q: How do I see the cost breakdown of what I manufactured?**
A: Open the done MO -> look for the **Unit Cost** field and the **Cost Analysis** smart button (requires `mrp_account`). The BOM also has a **Structure & Cost** report button.

**Q: What is the difference between Plan and Confirm?**
A: **Confirm** creates stock moves and reserves components. **Plan** goes further -- it schedules work orders on work center calendars with specific start/end dates. Plan auto-confirms if the MO is still in draft.

**Q: Can I change the quantity after confirming?**
A: Yes, if the MO is not locked. Odoo will adjust component quantities proportionally. For done MOs, you need the "Unlock Manufacturing Orders" setting.

**Q: How do backorder names work?**
A: The original MO gets renamed with a suffix (e.g., `WH/MO/00001-001`). The backorder gets the next number (`WH/MO/00001-002`). All share the same `production_group_id`.

---

## Relationship Diagram

```
Manufacturing Order (mrp.production)
    |
    |-- BOM (mrp.bom)
    |     |-- BOM Lines (mrp.bom.line) ............. [components]
    |     |-- Operations (mrp.routing.workcenter) ... [manufacturing steps]
    |     |-- By-Products (mrp.bom.byproduct) ....... [secondary outputs]
    |     '-- Operation Dependencies ................ [if enabled]
    |
    |-- Work Orders (mrp.workorder) ................. [one per operation]
    |     |-- Work Center (mrp.workcenter)
    |     |-- Time Logs (mrp.workcenter.productivity)
    |     |-- Quality Checks (quality.check) ........ [enterprise]
    |     '-- Component Moves (stock.move subset)
    |
    |-- Stock Moves
    |     |-- Raw Materials (move_raw_ids) .......... [components consumed]
    |     '-- Finished Products (move_finished_ids) . [output received]
    |
    '-- Backorders (mrp.production) ................. [if partial production]
```

---

## Equipment & Maintenance

> **Module:** `maintenance` (community) + `mrp_maintenance` (enterprise) + `hr_maintenance` + `stock_maintenance`
> **Path:** [`addons/maintenance/`](../addons/maintenance/) | [`enterprise/mrp_maintenance/`](../enterprise/mrp_maintenance/)

### What It Does

Tracks physical equipment (machines, tools, vehicles), schedules corrective and preventive maintenance, measures reliability (MTBF/MTTR), and integrates with MRP work centers to block scheduling during maintenance windows.

### Equipment Categories

**Model:** `maintenance.equipment.category` | [maintenance.py:23](../addons/maintenance/models/maintenance.py#L23)

Categories group equipment by type and assign a default technician. Each category can define **custom properties** (extra fields) that apply to all equipment in that category.

| Field | Type | UI Label | Purpose |
|---|---|---|---|
| `name` | Char | Category Name | e.g. "CNC Machines", "Forklifts", "Conveyor Belts" |
| `technician_user_id` | Many2one | Responsible | Default technician -- auto-fills on equipment and requests |
| `equipment_ids` | One2many | Equipment | All equipment in this category |
| `equipment_count` | Integer | Equipment Count | Computed |
| `maintenance_open_count` | Integer | Current Maintenance | Non-done, non-archived requests across all equipment |
| `equipment_properties_definition` | PropertiesDefinition | Equipment Properties | Custom fields for equipment (e.g. "Max RPM", "Voltage") |
| `fold` | Boolean | Folded in Pipe | Auto-folds if category has no equipment |

**Where:** Maintenance > Configuration > Equipment Categories

**Practical use:** Set up categories like "3D Printers", "Lathes", "Assembly Robots". Assign a technician per category. When any equipment in that category needs repair, the technician auto-assigns.

### Equipment

**Model:** `maintenance.equipment` | [maintenance.py:110](../addons/maintenance/models/maintenance.py#L110)

Inherits: `mail.thread`, `mail.activity.mixin`, `maintenance.mixin`

| Field | Type | UI Label | Purpose |
|---|---|---|---|
| `name` | Char | Equipment Name | e.g. "CNC Mill #3" |
| `category_id` | Many2one | Equipment Category | Groups equipment; brings default technician |
| `serial_no` | Char | Serial Number | Unique constraint; copy=False |
| `model` | Char | Model | Hardware model name |
| `owner_user_id` | Many2one | Owner | Person responsible for the equipment |
| `partner_id` | Many2one | Vendor | Supplier / service provider |
| `partner_ref` | Char | Vendor Reference | |
| `cost` | Float | Cost | Purchase cost |
| `warranty_date` | Date | Warranty Expiration | |
| `effective_date` | Date | Effective Date | When equipment became operational (MTBF baseline) |
| `scrap_date` | Date | Scrap Date | Retirement date |
| `equipment_properties` | Properties | Properties | Custom fields defined by category |

**Extensions by module:**

| Module | Field | Purpose |
|---|---|---|
| `hr_maintenance` | `employee_id` | Assigned employee |
| `hr_maintenance` | `department_id` | Assigned department |
| `hr_maintenance` | `equipment_assign_to` | Selection: employee / department / other |
| `mrp_maintenance` | `workcenter_id` | Links equipment to MRP work center |
| `stock_maintenance` | `location_id` | Internal stock location where equipment is stored |

**Where:** Maintenance > Equipment > Machines & Tools

### Maintenance Mixin (MTBF/MTTR)

**Model:** `maintenance.mixin` (abstract) | [maintenance.py:69](../addons/maintenance/models/maintenance.py#L69)

Mixed into both `maintenance.equipment` AND `mrp.workcenter`. Provides reliability metrics:

| Field | Type | UI Label | How Computed |
|---|---|---|---|
| `expected_mtbf` | Integer | Expected MTBF (days) | Manual input -- expected days between failures |
| `mtbf` | Integer | MTBF (days) | `(latest_failure - effective_date) / count_of_done_corrective_requests` |
| `mttr` | Integer | MTTR (days) | Average `(close_date - request_date)` across done corrective requests |
| `estimated_next_failure` | Date | Estimated Next Failure | `latest_failure_date + mtbf days` |
| `latest_failure_date` | Date | Latest Failure | Most recent corrective request's `request_date` |

**MTBF** = Mean Time Between Failure -- რამდენ ხანში ფუჭდება საშუალოდ
**MTTR** = Mean Time To Repair -- რამდენი ხანი სჭირდება შეკეთებას საშუალოდ

### Maintenance Request

**Model:** `maintenance.request` | [maintenance.py:181](../addons/maintenance/models/maintenance.py#L181)

Inherits: `mail.thread.cc`, `mail.activity.mixin`

#### Core Fields

| Field | Type | UI Label | Purpose |
|---|---|---|---|
| `name` | Char | Subjects | Request title |
| `equipment_id` | Many2one | Equipment | Which equipment needs maintenance |
| `category_id` | Many2one | Category | Auto-filled from equipment |
| `maintenance_type` | Selection | Maintenance Type | **corrective** (something broke) or **preventive** (scheduled) |
| `user_id` | Many2one | Technician | Auto-computed from equipment/category technician |
| `maintenance_team_id` | Many2one | Team | Required; defaults from equipment |
| `stage_id` | Many2one | Stage | Kanban stage |
| `priority` | Selection | Priority | 0=Very Low, 1=Low, 2=Normal, 3=High |
| `schedule_date` | Datetime | Scheduled Date | When maintenance is planned |
| `schedule_end` | Datetime | End Date | Computed: schedule_date + 1 hour (editable) |
| `close_date` | Date | Close Date | Auto-set when stage.done=True |
| `kanban_state` | Selection | Kanban State | normal / blocked / done |

#### Recurring (Preventive Only)

| Field | Type | UI Label | Purpose |
|---|---|---|---|
| `recurring_maintenance` | Boolean | Recurring | Only True when maintenance_type='preventive' |
| `repeat_interval` | Integer | Repeat Every | Default 1 |
| `repeat_unit` | Selection | Unit | day / week / month / year |
| `repeat_type` | Selection | Until | forever / until specific date |
| `repeat_until` | Date | End Date | Stop recurring after this date |

#### Instructions

| Field | Type | Purpose |
|---|---|---|
| `instruction_type` | Selection | pdf / google_slide / text |
| `instruction_pdf` | Binary | Attach PDF instructions |
| `instruction_google_slide` | Char | Google Slides URL |
| `instruction_text` | Html | Rich text instructions |

#### MRP Extension (`mrp_maintenance`)

| Field | Type | Purpose |
|---|---|---|
| `maintenance_for` | Selection | **equipment** or **workcenter** |
| `production_id` | Many2one | Link to mrp.production |
| `workorder_id` | Many2one | Link to mrp.workorder |
| `workcenter_id` | Many2one | Computed from equipment_id when maintenance_for='equipment' |
| `block_workcenter` | Boolean | Creates resource.calendar.leaves to block WC scheduling |
| `recurring_leaves_count` | Integer | Number of future slots to pre-block (preventive) |

### Maintenance Stages

Default stages (from [maintenance_data.xml](../addons/maintenance/data/maintenance_data.xml)):

| Stage | Sequence | Done? | Fold? | Behavior |
|---|---|---|---|---|
| New Request | 1 | No | No | Initial state |
| In Progress | 2 | No | No | Work started |
| Repaired | 3 | Yes | Yes | Triggers close_date + recurring copy |
| Scrap | 4 | Yes | Yes | Equipment retired |

### Maintenance Teams

**Model:** `maintenance.team` | [maintenance.py:406](../addons/maintenance/models/maintenance.py#L406)

Teams group technicians and can receive requests via **email alias**. Dashboard shows:

| Counter | What it counts |
|---|---|
| `todo_request_count` | Non-done, non-archived requests |
| `todo_request_count_date` | Requests with schedule_date set |
| `todo_request_count_high_priority` | Priority = 3 (High) |
| `todo_request_count_block` | Kanban state = blocked |
| `todo_request_count_unscheduled` | No schedule_date + not done |

### Business Flows

#### Corrective Maintenance (რაღაც გაფუჭდა)

```
Equipment breaks
    -> Create request (maintenance_type='corrective')
    -> Technician auto-assigned from equipment/category
    -> Stage: New Request -> In Progress -> Repaired
    -> close_date auto-set when stage.done=True
    -> MTBF/MTTR metrics updated on equipment
```

#### Preventive Maintenance (დაგეგმილი)

```
Create request (maintenance_type='preventive', recurring=True)
    -> Set repeat: every 2 weeks
    -> Schedule first date
    -> Complete (move to Repaired stage)
    -> System AUTO-CREATES next request:
         schedule_date = previous + 2 weeks
         stage = New Request
    -> Chain continues forever (or until repeat_until date)
```

#### Work Center Maintenance (MRP integration)

```
Create request for work center (maintenance_for='workcenter')
    -> block_workcenter=True
    -> System creates resource.calendar.leaves on workcenter
    -> MRP scheduling avoids this workcenter during maintenance window
    -> If preventive + recurring_leaves_count=3:
         Pre-blocks next 3 future maintenance windows
    -> Manufacturing orders cannot be scheduled during blocked periods
```

### Security

| Model | Regular User (`base.group_user`) | Manager (`group_equipment_manager`) |
|---|---|---|
| Equipment | Read only | CRUD |
| Equipment Category | Read only | CRUD |
| Maintenance Request | CRUD | CRUD |
| Stage | Read only | CRUD |
| Team | Read only | CRUD |

### UI Entry Points

| Menu | What it shows |
|---|---|
| Maintenance > Dashboard | Team kanban with request counters |
| Maintenance > Maintenance > Maintenance Requests | Kanban/list/calendar of requests |
| Maintenance > Equipment > Machines & Tools | Equipment kanban/list |
| Maintenance > Configuration > Equipment Categories | Category management |
| Maintenance > Configuration > Maintenance Teams | Team setup |
| Maintenance > Configuration > Stages | Stage customization |
| MRP Work Center form > Maintenance tab | MTBF/MTTR + linked requests (with `mrp_maintenance`) |

---

## Related Docs

- [`INDEX.md`](INDEX.md)
- [`inventory.md`](inventory.md) -- stock moves and reservations used by MRP
- [`stock_valuation.md`](stock_valuation.md) -- costing of manufactured products

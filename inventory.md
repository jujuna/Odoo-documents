# Inventory (Stock)

> **Module:** `stock` + `sale_stock` | **Path:** [`addons/stock/`](../addons/stock/) + [`addons/sale_stock/`](../addons/sale_stock/)
> **Odoo Apps category:** Inventory

## What It Does

Manages physical stock movement between locations. Tracks quantities per location using quants, reserves stock for demand, and validates transfers that physically move goods. Integrates with Sales to generate deliveries automatically when a sale order is confirmed.

---

## Dependencies

### Requires
| Module | Why |
|---|---|
| `stock` | Core inventory engine — locations, pickings, moves, quants, rules |
| `sale` | Sale orders that trigger stock demand |
| `sale_stock` | Bridges `sale.order` → `stock.picking` via procurement rules |

### Optional Integrations
| Module | What it enables |
|---|---|
| `stock_account` | Creates COGS journal entries when deliveries are validated |
| `purchase_stock` | Receipts from purchase orders |
| `mrp` | Consumption moves for production orders |

### Provides To
| Consumer | What they use |
|---|---|
| `account_move` | `stock.move` for COGS and inventory valuation |
| `sale.order.line` | `qty_delivered` computed from done moves |

---

## Core Concepts

### Locations

Every unit of stock lives in a `stock.location`. Source: [`addons/stock/models/stock_location.py:32`](../addons/stock/models/stock_location.py#L32)

| Usage | Meaning | Examples |
|---|---|---|
| `internal` | Physical location inside warehouse | WH/Stock, WH/Output, WH/Input |
| `customer` | Virtual destination for outgoing | Customers (virtual) |
| `supplier` | Virtual source for incoming | Vendors (virtual) |
| `view` | Container node, no products stored | WH/ (root view) |
| `transit` | Inter-company/inter-warehouse buffer | Transit location |
| `inventory` | Counterpart for inventory adjustments | Inventory Adjustments |
| `production` | Counterpart for manufacturing consumption | Production |

Every warehouse has its own sub-tree of locations under a `view` root: `WH/`, `WH/Stock`, `WH/Input`, `WH/Quality Control`, `WH/Output`, `WH/Packing Zone`.

### Quants — The Source of Truth for Stock

`stock.quant` is the table that stores actual on-hand quantities. Source: [`addons/stock/models/stock_quant.py:19`](../addons/stock/models/stock_quant.py#L19)

One quant row = one unique combination of `(product, location, lot, package, owner)`.

| Field | Meaning |
|---|---|
| `quantity` | Physical units on hand (read-only, updated by move validation) |
| `reserved_quantity` | Units committed to pending outgoing moves |
| `available_quantity` | `quantity - reserved_quantity` — what can still be promised |

**Key rule:** `available_quantity` going negative is allowed in some configurations but signals a stock problem.

Quants are **never created manually** by users. They are created/updated automatically when `stock.move` records are validated.

---

## Warehouse Configuration

Source: [`addons/stock/models/stock_warehouse.py`](../addons/stock/models/stock_warehouse.py)

### What Gets Created With a Warehouse

When a warehouse is created ([`stock_warehouse.py:113`](../addons/stock/models/stock_warehouse.py#L113)):
1. A `view` location tree is built under `WH/`
2. Picking types (operation types) are created: Receipts, Delivery Orders, Internal Transfers, Pick, Pack
3. Routes are created with stock rules defining how products flow

### Delivery Steps (Outgoing Shipments)

Field: `delivery_steps` on `stock.warehouse`. UI label: **"Outgoing Shipments"** (radio buttons).
Source: [`addons/stock/models/stock_warehouse.py:62`](../addons/stock/models/stock_warehouse.py#L62)

> **Visibility:** The "Warehouse Configuration" tab appears when either **Storage Locations** (`stock.group_adv_location`) or **Multi-Warehouses** (`stock.group_stock_multi_warehouses`) is enabled. However, the `reception_steps` and `delivery_steps` fields themselves are inside a `groups="stock.group_adv_location"` sub-group — they only appear when **Storage Locations** is enabled. Source: [`stock_warehouse_views.xml:35`](../addons/stock/views/stock_warehouse_views.xml#L35), [`stock_warehouse_views.xml:38`](../addons/stock/views/stock_warehouse_views.xml#L38)

---

#### `ship_only` — Ship only (1 step) — **default**

**When to use:** Small warehouse. One person picks from shelf and loads the truck at the same time. No intermediate staging area needed.

**What Odoo creates:** A single **Delivery Order** (operation type: "Delivery Orders", sequence prefix `WH/OUT`).

**Flow:**
```
Customer orders product A
→ SO confirmed
→ 1 picking created: WH/OUT/00001  (WH/Stock → Customers)
→ Warehouse worker picks product from shelf and marks done
→ Picking validated → product leaves stock
```

**Active operation types:** Delivery Orders (`out_type_id`) only. Pick and Pack types are archived. Source: [`stock_warehouse.py:969`](../addons/stock/models/stock_warehouse.py#L969)

---

#### `pick_ship` — Pick + Ship (2 steps)

**When to use:** Medium/large warehouse. Picking team is separate from shipping team. Pickers collect goods from shelves to an Output staging zone; a different person (or team) then loads and ships from that zone.

**What Odoo creates:** Two pickings created in stages (not simultaneously):
1. **Pick** order (type: "Pick", prefix `WH/PICK`): WH/Stock → WH/Output — created at SO confirmation via pull rule
2. **Delivery Order** (type: "Delivery Orders", prefix `WH/OUT`): WH/Output → Customers — created when PICK is validated, via push rule

Source: [`test_sale_stock.py:1085`](../addons/sale_stock/tests/test_sale_stock.py#L1085)

**Flow:**
```
SO confirmed
→ 1 picking created:
    WH/PICK/00001  (state=assigned if stock available)
→ Picker validates WH/PICK: products move to WH/Output
→ push rule fires (_push_apply in _action_done): WH/OUT/00001 created (state=assigned)
→ Shipper validates WH/OUT: products leave for customer
```

**Active operation types:** Pick (`pick_type_id`) + Delivery Orders (`out_type_id`). Pack type is archived. Source: [`stock_warehouse.py:969`](../addons/stock/models/stock_warehouse.py#L969)

---

#### `pick_pack_ship` — Pick + Pack + Ship (3 steps)

**When to use:** E-commerce or B2C warehouse. Orders contain multiple products that need to be assembled into a box before shipping. Three distinct roles: picker, packer, shipper.

**What Odoo creates:** Three pickings created in stages (one per validated step):
1. **Pick** order (type: "Pick", prefix `WH/PICK`): WH/Stock → WH/Packing Zone — created at SO confirmation via pull rule
2. **Pack** order (type: "Pack", prefix `WH/PACK`): WH/Packing Zone → WH/Output — created when PICK is validated, via push rule
3. **Delivery Order** (type: "Delivery Orders", prefix `WH/OUT`): WH/Output → Customers — created when PACK is validated, via push rule

Source: [`test_sale_stock.py:1840`](../addons/sale_stock/tests/test_sale_stock.py#L1840)

**Flow:**
```
SO confirmed
→ 1 picking created:
    WH/PICK/00001  (state=assigned)
→ Picker validates WH/PICK: products move to Packing Zone
→ push rule fires: WH/PACK/00001 created (state=assigned)
→ Packer boxes the products, validates WH/PACK: products move to Output
→ push rule fires: WH/OUT/00001 created (state=assigned)
→ Shipper validates WH/OUT: products dispatched to customer
```

**Active operation types:** Pick + Pack + Delivery Orders. All three are active. Source: [`stock_warehouse.py:974`](../addons/stock/models/stock_warehouse.py#L974)

---

**Route rules generated per step** ([`stock_warehouse.py:779`](../addons/stock/models/stock_warehouse.py#L779)):
```
ship_only:      [Stock → Customer   (pull, Delivery Orders)]
pick_ship:      [Stock → Output     (pull, Pick)]
                [Output → Customer  (push, Delivery Orders)]
pick_pack_ship: [Stock → Packing    (pull, Pick)]
                [Packing → Output   (push, Pack)]
                [Output → Customer  (push, Delivery Orders)]
```

---

#### Cross-Docking (`xdock_type_id`)

Every warehouse has a `xdock_type_id` picking type (Cross Dock Type). Cross-docking bypasses the stock storage location entirely — goods flow directly from receiving to outbound staging without being put away.

Source: [`stock_warehouse.py:80`](../addons/stock/models/stock_warehouse.py#L80)

```
Traditional flow:    Vendor → WH/Input → WH/Stock → WH/Output → Customer
Cross-dock flow:     Vendor → WH/Input → WH/Output → Customer
```

The cross-dock route uses a pull rule from Input to Output (with `xdock_type_id` as operation type) that fires when an outgoing demand is already waiting. Products with the cross-dock route assigned bypass storage entirely. Common for: perishable goods, high-turnover items, or drop-ship variants.

---

### Reception Steps (Incoming Shipments)

Field: `reception_steps` on `stock.warehouse`. UI label: **"Incoming Shipments"** (radio buttons).
Same visibility requirement as Delivery Steps.
Source: [`addons/stock/models/stock_warehouse.py:56`](../addons/stock/models/stock_warehouse.py#L56)

---

#### `one_step` — Receive and store (1 step) — **default**

**When to use:** Small warehouse. Goods arrive and go straight to stock shelf immediately.

**What Odoo creates:** A single **Receipt** (operation type: "Receipts", prefix `WH/IN`).

**Flow:**
```
Purchase order confirmed (or receipt created manually)
→ 1 picking created: WH/IN/00001  (Vendors → WH/Stock)
→ Worker receives goods, fills done quantities
→ Receipt validated → quants created/updated in WH/Stock
```

**Active operation types:** Receipts (`in_type_id`) only. Quality Control and Storage types are archived. Source: [`stock_warehouse.py:983`](../addons/stock/models/stock_warehouse.py#L983)

---

#### `two_steps` — Receive then store (2 steps)

**When to use:** You need to count and verify goods before putting them in their final bin. Goods land in an Input area first; a separate step moves them to the actual stock location.

**What Odoo creates:** Two pickings created in stages:
1. **Receipt** (type: "Receipts", prefix `WH/IN`): Vendors → WH/Input — created at PO confirmation via pull rule
2. **Storage** (type: "Storage", prefix `WH/STOR`): WH/Input → WH/Stock — created when Receipt is validated, via push rule

**Flow:**
```
PO confirmed
→ 1 picking created:
    WH/IN/00001   (Vendors → WH/Input)
→ Worker receives truck, validates WH/IN: products land in WH/Input
→ push rule fires (_push_apply in _action_done): WH/STOR/00001 created (state=assigned)
→ Worker moves goods to correct shelf, validates WH/STOR: products enter WH/Stock
```

**Active operation types:** Receipts (`in_type_id`) + Storage (`store_type_id`). QC type archived. Source: [`stock_warehouse.py:983`](../addons/stock/models/stock_warehouse.py#L983)

---

#### `three_steps` — Receive, quality control, then store (3 steps)

**When to use:** Industries where incoming goods must pass a quality check before entering sellable stock (food, pharma, electronics). A QC team inspects goods in an isolated zone before approving them.

**What Odoo creates:** Three chained pickings:
1. **Receipt** (type: "Receipts", prefix `WH/IN`): Vendors → WH/Input
2. **Quality Control** (type: "Quality Control", prefix `WH/QC`): WH/Input → WH/Quality Control
3. **Storage** (type: "Storage", prefix `WH/STOR`): WH/Quality Control → WH/Stock

**Flow:**
```
PO confirmed
→ 3 pickings created:
    WH/IN/00001  (Vendors → WH/Input)
    WH/QC/00001  (WH/Input → WH/QC zone, state=waiting)
    WH/STOR/00001 (WH/QC → WH/Stock, state=waiting)
→ Receiving team validates WH/IN
→ WH/QC becomes assigned; QC team inspects goods
→ QC team validates WH/QC (or triggers scrap if goods fail)
→ WH/STOR becomes assigned; warehouse worker puts goods on shelf
→ WH/STOR validated: goods are now in WH/Stock and available
```

**Active operation types:** Receipts + Quality Control (`qc_type_id`) + Storage. All three active. Source: [`stock_warehouse.py:979`](../addons/stock/models/stock_warehouse.py#L979)

---

### Putaway Rules

Source: [`stock_location.py:296`](../addons/stock/models/stock_location.py#L296) (`_get_putaway_strategy`)

Putaway rules tell Odoo **where inside a destination location** to put incoming goods. They fire when a move line's destination is set (e.g., on receipt validation). If no rule matches, goods land at the root destination location.

#### Rule matching

A rule is eligible if ALL of the following match (or the field is empty = "any"):
- `product_id` matches the incoming product
- `category_id` matches the product's category (or any parent category)
- `package_type_ids` contains the package type on the incoming package/packaging

#### Rule priority sort (highest wins)

When multiple rules match, the most specific wins:

```python
putaway_rules.sorted(lambda rule: (
    bool(rule.package_type_ids),              # 1st: package-specific rules
    bool(rule.product_id),                    # 2nd: product-specific rules
    bool(rule.category_id == categs[:1]),     # 3rd: exact category match (not parent)
    bool(rule.category_id),                   # 4th: parent category match
), reverse=True)
```

Source: [`stock_location.py:323`](../addons/stock/models/stock_location.py#L323)

**Example:** iPhone 15 arriving on a pallet — if a product-specific rule exists (iPhone 15 → High-Security), it wins over a package-specific rule (Pallet → Bulk), because `bool(product_id)` ranks higher.

### Routes & Rules

Source: [`addons/stock/models/stock_rule.py`](../addons/stock/models/stock_rule.py) | [`addons/stock/models/stock_location.py:516`](../addons/stock/models/stock_location.py#L516)

#### Purpose — Why Routes and Rules Exist

When Odoo needs to fulfil a demand — a sale order line, a reorder rule, an MTO trigger — it has no hardcoded knowledge of what to do. It doesn't know whether to create a delivery, trigger a purchase, start manufacturing, or transfer from another warehouse. **Routes and rules are the answer to that question.**

A **route** is a named policy: "here is how a product travels from origin to destination."
A **rule** is one step in that policy: "if product X is needed at location B, create a move from location A using operation type Z."

Together they decouple business logic from code. You configure routes and rules; Odoo evaluates them at runtime.

---

**The core question routes answer:**

> "A demand exists for product X at location Y. What do I do?"

The answer depends on which routes are configured on the product, its category, or the warehouse. Examples:

| Situation | Route | What fires |
|---|---|---|
| Normal sale, goods in stock | WH: Deliver in 1 step (default) | Pull rule → Delivery Order from WH/Stock → Customers |
| Sale, 2-step warehouse | WH: Deliver in 2 steps | Pull rule → Pick (Stock→Output) + chained Delivery Order |
| Product to be bought, ordered per demand | Buy + Replenish on Order (MTO) | MTO pull rule (make_to_order) fires delivery move → second run() for WH/Stock → Buy rule (`action=buy`) → `_run_buy()` → PO created |
| Product to be bought, replenished via min/max rule | Buy (+ orderpoint) | Orderpoint calls run() for WH/Stock → Buy rule → `_run_buy()` → PO created |
| Product not stocked, ordered per demand | Replenish on Order (MTO) | `make_to_order` rule → upstream procurement before delivery (needs Buy or Manufacture route to complete the chain) |
| Product made in-house | Manufacture | Pull rule → Production Order (via `_run_manufacture()`) |
| WH needs stock from WH2 | WH: Supply from WH2 | Pull rules → Transfer WH2/Stock → Transit → WH/Stock |

---

**When to assign routes:**

| Where | Effect |
|---|---|
| Product → Inventory tab → Routes | Only this product follows this route |
| Product Category → Routes | All products in the category follow this route |
| Warehouse → Route checkbox | Default route for all products through that warehouse |
| SO/PO line → Route (via `values['route_ids']`) | Override for one specific document line |

If no route is assigned, Odoo falls back to warehouse routes. If nothing matches even after walking up the location hierarchy, procurement fails with "No rule found".

---

**When rules are created:**

Rules are almost never created manually by users. They are created automatically:
- When a warehouse is created → delivery/reception route rules are created automatically
- When `delivery_steps` or `reception_steps` changes → old rules archived, new ones created
- When `resupply_wh_ids` is ticked → inter-warehouse route rules created
- When `buy_to_resupply` is enabled → buy rule created on the "Buy" route

The only cases where you create rules manually are custom routing logic not covered by warehouse configuration.

---

A `stock.route` is a named path (e.g., "WH: Deliver in 2 steps"). A `stock.rule` is one hop in that path.

---

#### `stock.route` — Named Path
> [`addons/stock/models/stock_location.py:516`](../addons/stock/models/stock_location.py#L516)

| Field | Meaning |
|---|---|
| `rule_ids` | Ordered list of `stock.rule` records that make up this route |
| `sequence` | Priority order — lower sequence = higher priority |
| `product_selectable` | Can be set on a product's Inventory tab |
| `product_categ_selectable` | Can be set on a product category |
| `warehouse_selectable` | Used as the default route for a warehouse |
| `package_type_selectable` | Can be set on a package type |
| `supplied_wh_id` | For inter-warehouse routes: the destination warehouse |
| `supplier_wh_id` | For inter-warehouse routes: the source warehouse |

> **Routes section visibility on product form:** The "Operations" group (containing `route_ids`) is controlled by the computed field `has_available_route_ids` on `product.template`. It returns `True` only when `stock.route.search_count([('product_selectable', '=', True)]) > 0`. If no route has `product_selectable=True`, the Routes section is completely hidden — even if routes exist and Multi-Step Routes is enabled. Source: [`product.py:907`](../addons/stock/models/product.py#L907), [`product_views.xml:208`](../addons/stock/views/product_views.xml#L208)

> **`stock_route_product` uses template ID:** The relation table stores `product_template.id`, not `product.product.id`. When querying route assignments by product variant, join via `product_template` — querying `WHERE product_id = <variant_id>` will return no rows even if the route is correctly assigned.

When a route is archived, all its rules are also archived. Source: [`stock_location.py:569`](../addons/stock/models/stock_location.py#L569)

#### Route resolution priority in `_search_rule_for_warehouses()`

When looking up rules for a procurement, Odoo collects valid route IDs in this priority order:

1. **`route_ids` from the procurement** (e.g., from the SO line's explicit route override)
2. **`packaging_uom_id.package_type_id.route_ids`** — routes on the packaging's package type (often overlooked)
3. **Product routes** (`product.route_ids`) + **product category routes** (`categ_id.total_route_ids`)
4. **Warehouse routes** (filtered by `warehouse_id` in domain)

Source: [`stock_rule.py:506`](../addons/stock/models/stock_rule.py#L506)

Package type routes (step 2) allow pallets, refrigerated packages, or hazmat packages to automatically follow a different route than the product's default — without any SO line configuration.

---

#### `stock.rule` — One Hop in a Route
> [`addons/stock/models/stock_rule.py:42`](../addons/stock/models/stock_rule.py#L42)

| Field | Type | Meaning |
|---|---|---|
| `action` | Selection | `pull`, `push`, `pull_push` — controls when the rule fires |
| `procure_method` | Selection | `make_to_stock`, `make_to_order`, `mts_else_mto` |
| `auto` | Selection | `manual` (creates new move) or `transparent` (rewrites destination on existing move) |
| `location_src_id` | Many2one | Where to take stock from |
| `location_dest_id` | Many2one | Where to deliver stock |
| `location_dest_from_rule` | Boolean | If True, move destination = rule's `location_dest_id`; if False, destination comes from the picking type |
| `picking_type_id` | Many2one | Which operation type the created move uses |
| `warehouse_id` | Many2one | Warehouse scope for this rule |
| `delay` | Integer | Days subtracted from planned date when creating the move |
| `propagate_cancel` | Boolean | If True, cancelling this move cancels the next move in chain |
| `propagate_carrier` | Boolean | Propagates shipping carrier down the chain |
| `push_domain` | Char | Optional domain filter — push rule only fires if the move matches |
| `route_id` | Many2one | Parent route (cascade delete) |
| `sequence` | Integer | Within a route, lower = evaluated first |

---

#### `action` field — Full Value Set and Trigger Chains

The `action` field on `stock.rule` is a Selection extended by multiple modules. The full set of values in a standard Odoo installation with Purchase and Manufacturing:

| Value | Module | What it creates | UI label |
|---|---|---|---|
| `pull` | `stock` | `stock.move` (internal transfer) | Pull From |
| `push` | `stock` | `stock.move` (chained move on arrival) | Push To |
| `pull_push` | `stock` | Acts as both depending on the caller | Pull & Push |
| `buy` | `purchase_stock` | `purchase.order` + `purchase.order.line` | Buy |
| `manufacture` | `mrp` | `mrp.production` (manufacturing order) | Manufacture |

Source: [`purchase_stock/models/stock_rule.py:18`](../addons/purchase_stock/models/stock_rule.py#L18) | [`mrp/models/stock_rule.py:14`](../addons/mrp/models/stock_rule.py#L14)

`pull`, `pull_push`, `buy`, and `manufacture` are dispatched by `run()` via dynamic `_run_<action>()`. **`push` rules are never dispatched through `run()`** — `_get_rule_domain()` explicitly excludes them (`action != 'push'`, see [`stock_rule.py:652`](../addons/stock/models/stock_rule.py#L652)). Push rules are triggered exclusively by `_push_apply()` in `stock.move._action_done()`. Source: [`stock_rule.py:493`](../addons/stock/models/stock_rule.py#L493)

---

##### `pull` — Demand-Driven Transfer

**SO confirmation never checks stock availability.** It always transitions the SO to `state = sale` and creates the delivery. The delivery sits in `confirmed` (or `waiting`) state until stock is available. Stock shortage does NOT block SO confirmation.

**What triggers it — all `stock.rule.run()` call sites:**

| Trigger | Source | Notes |
|---|---|---|
| SO line confirmed | [`sale_stock/models/sale_order_line.py:404`](../addons/sale_stock/models/sale_order_line.py#L404) | Primary entry point for sales flow |
| Move `_action_confirm` | [`stock/models/stock_move.py:1575`](../addons/stock/models/stock_move.py#L1575) | Only when `procure_method = make_to_order` or `mts_else_mto` |
| Orderpoint scheduler | [`stock/models/stock_orderpoint.py:745`](../addons/stock/models/stock_orderpoint.py#L745) | Min/max reorder rules; cron runs `run_scheduler()` |
| Replenish wizard | [`stock/wizard/product_replenish.py:93`](../addons/stock/wizard/product_replenish.py#L93) | User clicks "Replenish" on a product |
| Return picking | [`stock/wizard/stock_picking_return.py:263`](../addons/stock/wizard/stock_picking_return.py#L263) | When a return is confirmed |
| Scrap | [`stock/models/stock_scrap.py:168`](../addons/stock/models/stock_scrap.py#L168) | When a scrap order is validated |
| MRP production | [`mrp/models/stock_move.py:340`](../addons/mrp/models/stock_move.py#L340) | Manufacturing order confirmation |
| POS order | [`point_of_sale/models/pos_order.py:1739`](../addons/point_of_sale/models/pos_order.py#L1739) | POS order confirmed |

**What it creates:**
- A `stock.move` from `location_src_id` → `location_dest_id`
- Move is created as SUPERUSER (triggering user may have no stock rights)
- `_action_confirm()` is called immediately on the new move

**Real examples:**
```
SO confirmed, ship_only warehouse:
  pull rule: WH/Stock → Customers  (picking_type=Delivery Orders)
  → 1 stock.move created → 1 picking WH/OUT/00001

SO confirmed, pick_ship warehouse:
  pull rule: WH/Output → Customers  (picking_type=Delivery Orders, procure_method=make_to_order)
  → move state=waiting → fires upstream run() for WH/Output
  pull rule: WH/Stock → WH/Output  (picking_type=Pick, procure_method=make_to_stock)
  → 2 moves created → 2 pickings: WH/PICK/00001 (assigned) + WH/OUT/00001 (waiting)
```

---

##### `push` — Event-Driven Transfer (Arrival-Based)

**What triggers it:**
- `stock.move._push_apply()` called from:
  - `_action_confirm()` — for negative-qty (return) moves
  - `_action_done()` — after a move is validated (line 2127)
- Rule lookup: `_get_push_rule(product, move.location_dest_id, {route_ids, warehouse_id})` — walks up the location hierarchy looking for a push rule whose `location_src_id` matches where the goods just arrived

**What it creates:**
- A new `stock.move` starting from where the previous move ended
- `auto = manual` → creates a new separate move (new picking)
- `auto = transparent` → rewrites `location_dest_id` on the existing move (no new picking)

**Real examples:**
```
2-step reception (two_steps):
  Receipt validated: goods arrive at WH/Input
  → _push_apply() fires after _action_done()
  → push rule found: WH/Input → WH/Stock  (picking_type=Storage)
  → new stock.move created → WH/STOR/00001 picking appears (state=assigned)

Return of a delivery:
  Return picking confirmed
  → _push_apply() fires on _action_confirm() (negative-qty move)
  → checks for push rules on the return destination
```

**Push does NOT fire on returns-of-returns** — guard built into `_push_apply()` to prevent infinite loops. Source: [`stock_move.py:1144`](../addons/stock/models/stock_move.py#L1144)

---

##### `pull_push` — Dual Mode

Acts as `pull` when reached from `run()`. Acts as `push` when reached from `_push_apply()`.

```python
# In run() — line 486
action = 'pull' if rule.action == 'pull_push' else rule.action
actions_to_run[action].append((procurement, rule))
# → calls _run_pull()

# In _get_push_rule() — line 671
domain = Domain('action', 'in', ('push', 'pull_push'))
# → both push and pull_push are found by push rule lookup
```

Used in routes that need to work both ways: once as a demand-triggered move, once as an arrival-triggered move. Less common in standard configuration.

---

##### `buy` — Creates a Purchase Order (added by `purchase_stock`)
> [`purchase_stock/models/stock_rule.py:59`](../addons/purchase_stock/models/stock_rule.py#L59)

**What triggers it:**
- Same `run()` call as `pull` — but `_get_rule()` finds a rule with `action='buy'` instead of `action='pull'`
- Triggered by: SO confirmation (if product has "Buy" route), orderpoint replenishment, MTO chain pointing to a buy rule

**What it creates:**
1. Looks up matching vendor (supplier) via `_get_matching_supplier()` — uses `product.seller_ids`, checks min qty, currency, date validity
2. If no supplier exists → error (from orderpoint context) or silently sets move to `make_to_stock` and notifies responsible user
3. Calls `_make_po_get_domain()` to find an existing open PO for the same partner/company/currency/delivery address
4. If open PO found → adds a new `purchase.order.line` to it (or merges into existing line)
5. If no open PO found → creates `purchase.order` (as SUPERUSER) + new line
6. PO line is linked back to the original `stock.move` via `move_dest_ids`

**Key detail:** One PO can absorb multiple procurements for the same supplier — `_run_buy()` groups by `_make_po_get_domain()` key before creating/updating POs. Source: [`purchase_stock/models/stock_rule.py:93`](../addons/purchase_stock/models/stock_rule.py#L93)

**Flow:**
```
SO confirmed, product has "Buy" route:
  run() → _get_rule() finds buy rule on "Buy" route
  → _run_buy():
      supplier found on product.seller_ids
      domain = (partner=vendor, company, currency, incoterm, ...)
      existing open PO for this vendor? yes → add line
                                         no  → create new PO (draft)
  → PO line linked to stock.move via move_dest_ids
  → When PO is confirmed → receipt (WH/IN/00001) created
  → Receipt validated → stock.move done → SO delivery can proceed
```

**`buy` rule has no `location_src_id`** — makes sense: the source is the vendor, which is external. Source: [`purchase_stock/models/stock_rule.py:42`](../addons/purchase_stock/models/stock_rule.py#L42)

---

##### `manufacture` — Creates a Manufacturing Order (added by `mrp`)
> [`mrp/models/stock_rule.py:81`](../addons/mrp/models/stock_rule.py#L81)

**What triggers it:**
- Same `run()` dispatch as `pull` and `buy` — `_get_rule()` finds a rule with `action='manufacture'`
- Triggered by: SO confirmation (MTO + Manufacture route), orderpoint for manufactured product, explicit MTO chain

**What it creates:**
- An `mrp.production` (manufacturing order) for the product and qty
- Created as SUPERUSER (same reason as moves and POs — triggering user may have no MFG rights)
- Auto-confirmed if: no work orders AND (triggered by orderpoint OR move's `procure_method = make_to_stock`)
- Source: [`mrp/models/stock_rule.py:35`](../addons/mrp/models/stock_rule.py#L35)

**Filter:** `manufacture` routes are only valid for a product if that product has a Bill of Materials with `type='normal'`. If no BOM exists, the route is filtered out during rule search. Source: [`mrp/models/stock_rule.py:74`](../addons/mrp/models/stock_rule.py#L74)

**Flow:**
```
SO confirmed, product has "Manufacture" route + MTO:
  run() → _get_rule() finds manufacture rule
  → _run_manufacture():
      mrp.production created (SUPERUSER)
      auto-confirm: if no raw_ids → (no workorders AND (from orderpoint OR downstream make_to_stock)); if has raw_ids → not from orderpoint
      production linked to stock.move via move_dest_ids
  → MO confirmed → component reservation starts
  → MO validated → finished product move done → delivery can proceed
```

---

##### Summary: Which `action` to use for which business need

| Business need | action value | Document created | Triggered by |
|---|---|---|---|
| Move goods between internal locations | `pull` | `stock.move` | Demand (SO, orderpoint, MTO) |
| Move goods automatically after arrival | `push` | `stock.move` | Validation of previous move |
| Replenish by buying from vendor | `buy` | `purchase.order` | Demand (SO, orderpoint, MTO) |
| Replenish by making in-house | `manufacture` | `mrp.production` | Demand (SO, orderpoint, MTO) |

---

#### `procure_method` field — How to Source Stock

| Value | UI Label | Behaviour |
|---|---|---|
| `make_to_stock` | Take From Stock | Reserve from stock at `location_src_id`. Move state → `confirmed`. |
| `make_to_order` | Trigger Another Rule | Do NOT take from stock. Create an upstream procurement to bring goods to `location_src_id`. Move state → `waiting` until upstream move is done. |
| `mts_else_mto` | Take From Stock, if unavailable, Trigger Another Rule | Try MTS first; if not enough stock, trigger another rule for the missing qty. Source: [`stock_rule.py:304`](../addons/stock/models/stock_rule.py#L304) |

In multi-step routes, the **first rule** in the chain uses `make_to_stock` (take from real stock). Subsequent rules use `make_to_order` (wait for upstream). Odoo sets this automatically in `_get_supply_pull_rules_values()`. Source: [`stock_warehouse.py:858`](../addons/stock/models/stock_warehouse.py#L858)

---

#### Custom Fallback Route Pattern (Secondary Location)

Use case: deliver from `WH/Stock`; if stock is insufficient, pull automatically from `WH/Stock2`.

**Rule setup (both rules on same route):**

| Rule | Source | Destination | Operation Type | `procure_method` | Sequence |
|---|---|---|---|---|---|
| Delivery | WH/Stock | Customers | Delivery Orders | **`mts_else_mto`** | 20 |
| Replenishment | WH/Stock2 | WH/Stock | Internal Transfers | `make_to_stock` | 21 |

**Critical:** `mts_else_mto` must be on the **delivery rule** (Rule 1), not the replenishment rule. The delivery rule is the one confirmed during SO → it is the only rule whose `procure_method` is checked by `_action_confirm()` at [`stock_move.py:1554`](../addons/stock/models/stock_move.py#L1554). The replenishment rule is called as the upstream target — it just needs to reserve from Stock2 (`make_to_stock`).

**Prerequisites:**
1. Route must have `product_selectable = True` — otherwise Routes section is invisible on product form
2. Route must be assigned to the product (product form → Inventory tab → Routes)
3. **Multi-Step Routes** setting must be ON (`stock.group_adv_location`) for the Routes tab section to render

**What happens at SO confirmation:**
```
SO confirmed
  → _action_launch_stock_rule() → stock.rule.run()
  → delivery move confirmed (mts_else_mto)
  → tries to reserve from WH/Stock
  → shortfall detected → fires upstream run() for WH/Stock
  → finds replenishment rule (Stock2 → Stock)
  → creates WH/INT/XXXXX internal transfer
  → validate internal transfer first → then Check Availability on delivery works
```

**What does NOT work:**
- `Check Availability` on an already-created picking does NOT trigger pull rules — it only reserves existing stock. Pull rules only fire during procurement (`_action_confirm` with `create_proc=True`).
- Assigning the route to a product after the SO is confirmed has no retroactive effect on existing moves.

Source: [`stock_move.py:1540-1575`](../addons/stock/models/stock_move.py#L1540)

---

#### `auto` field — How a Push Rule Creates the Next Move

| Value | Behaviour |
|---|---|
| `manual` | Creates a brand-new `stock.move` as the next step. The original move ends at `location_dest_id` and the new move starts there. |
| `transparent` | Rewrites `location_dest_id` on the original move — no extra move is created. The system then calls `_push_apply()` again recursively to check for more rules. |

Source: [`stock_rule.py:233`](../addons/stock/models/stock_rule.py#L233)

---

#### How `run()` Dispatches Procurements
> [`stock_rule.py:450`](../addons/stock/models/stock_rule.py#L450)

```
run(procurements)
  for each procurement:
    1. Skip if product type != 'consu' or qty == 0
    2. _get_rule(product, location, values)  ← find the matching rule
       if no rule found → raise UserError / ProcurementException
    3. Group by action: actions_to_run['pull'] = [...], actions_to_run['push'] = [...]
  for each action group:
    call _run_<action>(procurements)  ← dynamic dispatch
    e.g. _run_pull(), _run_push(), _run_buy() (purchase_stock), _run_manufacture() (mrp)
```

---

#### How `_run_pull()` Creates Moves
> [`stock_rule.py:288`](../addons/stock/models/stock_rule.py#L288)

```
for each (procurement, rule):
    move_values = rule._get_stock_move_values(...)
      → sets: product, qty, location_src_id, location_dest_id (from rule or picking type)
      → sets: procure_method, picking_type_id, date (planned_date - delay), rule_id
    moves = stock.move.sudo().create(moves_values)  ← always SUPERUSER
    moves._action_confirm()
```

Key detail: moves are created as `SUPERUSER` because the triggering user (e.g., salesperson) may not have stock rights. Source: [`stock_rule.py:313`](../addons/stock/models/stock_rule.py#L313)

---

#### How `_action_confirm()` Decides Move State
> [`stock_move.py:1536`](../addons/stock/models/stock_move.py#L1536)

For each move being confirmed:

| Condition | Result |
|---|---|
| Has `move_orig_ids` (upstream move exists) | state = `waiting` |
| `procure_method == make_to_order` AND `create_proc=True` | state = `waiting` + creates upstream procurement (triggers `run()` recursively) |
| `procure_method == mts_else_mto` | state = `confirmed` + creates upstream procurement for any shortfall |
| Otherwise | state = `confirmed` |

After state is set, `_assign_picking()` groups moves into a `stock.picking`.

---

#### How `_push_apply()` Fires Push Rules
> [`stock_move.py:1113`](../addons/stock/models/stock_move.py#L1113)

Called at two moments:
1. Inside `_action_confirm()` — for negative-qty moves (returns)
2. Inside `_action_done()` at line 2127 — after moves are validated, to create the next hop

For each done/confirmed move:
1. Find push rule via `_get_push_rule(product, move.location_dest_id, {route_ids, warehouse_id})`
2. If rule has `push_domain` — evaluate domain against the move; skip rule if it doesn't match, look for next rule
3. Do NOT fire if the move is a return of a return (guard against loops)
4. Call `rule._run_push(move)` — creates next move (manual) or rewrites destination (transparent)
5. New move is confirmed via `_action_confirm()`

---

#### Route Resolution Priority
> [`stock_rule.py:547`](../addons/stock/models/stock_rule.py#L547)

When looking for a pull rule for a procurement, Odoo checks these route sources in order:

1. Routes on the procurement itself (`values['route_ids']`) — e.g., from SO line
2. Routes on the packaging UoM's package type
3. Routes on the product (`product.route_ids`)
4. Routes on the product category (`product.categ_id.total_route_ids`)
5. Routes on the warehouse (`warehouse.route_ids`)

Within each source, rules are sorted by `route_sequence` then `sequence` (ascending — lower = higher priority).

If nothing is found at `location_dest_id`, Odoo walks **up the location hierarchy** (parent → grandparent → ...) and repeats the search. Source: [`stock_rule.py:573`](../addons/stock/models/stock_rule.py#L573)

---

#### `propagate_cancel`
> [`stock_rule.py:97`](../addons/stock/models/stock_rule.py#L97)

When a move is cancelled and `propagate_cancel = True` on its rule, the **next** move in the chain (`move_dest_ids`) is also cancelled automatically.

In a 3-step chain, only the first two rules have `propagate_cancel = True`; the last rule has it `False` to prevent cancelling the outgoing delivery when an upstream step is cancelled. Source: [`stock_warehouse.py:839`](../addons/stock/models/stock_warehouse.py#L839)

---

**MTO (Make to Order):** The global route "Replenish on Order" contains one rule per warehouse with `procure_method = make_to_order`. When a product has this route, confirming a SO creates the move as `waiting` and immediately fires `run()` again to trigger an upstream procurement (purchase order, production order, etc.).

> **The MTO route (`stock.route_warehouse0_mto`) is `active = False` by default.** It does not appear on the product's Inventory tab until enabled.
> **How to enable:** Inventory → Configuration → Settings → **"Replenish on Order (MTO)"** → Save.
> Internally this sets `route_warehouse0_mto.active = True`. Source: [`stock/models/res_config_settings.py:61`](../addons/stock/models/res_config_settings.py#L61)

---

#### MTO Chain — How It Works

The "chain" is the link between an outgoing delivery move and the upstream supply document (PO receipt move or MO output move). The two participants are linked via:

- `move_orig_ids` on the delivery move → points to the upstream move (what supplies it)
- `move_dest_ids` on the upstream move → points back to the delivery move (what it feeds)

The delivery move stays in `waiting` state until the upstream move is `done`. Source: [`stock_move.py:1548`](../addons/stock/models/stock_move.py#L1548)

**Exact trigger — inside `_action_confirm()`** ([stock_move.py:1550](../addons/stock/models/stock_move.py#L1550)):

```python
elif move.procure_method == 'make_to_order':
    move_waiting.add(move.id)      # state → waiting
    if create_proc:
        move_create_proc.add(move.id)  # fires upstream run()
```

Then at line 1575:
```python
self.env['stock.rule'].run(procurement_requests, ...)
```

This is a **recursive `run()` call** — it fires a second procurement for `move.location_id` (WH/Stock), which then finds the Buy or Manufacture rule.

**Full sequence (Buy + MTO):**

```
SO confirmed
  → run([Procurement(product, qty, location=Customers)])
  → MTO pull rule found (procure_method=make_to_order)
  → _run_pull(): create Move A (WH/Stock → Customers, make_to_order)
  → _action_confirm() on Move A:
       state = waiting
       fires run([Procurement(product, qty, location=WH/Stock)])  ← recursive
         → Buy rule found
         → _run_buy(): PO created (draft)
           PO line → Move B (Vendor → WH/Stock)
           Move B.move_dest_ids = [Move A]
           Move A.move_orig_ids = [Move B]

User confirms PO → WH/IN/00001 created
User validates WH/IN/00001:
  → Move B done → quant WH/Stock +qty
  → _trigger_assign() fires on Move B
  → Move A: waiting → assigned
  → WH/OUT/00001 becomes Ready
```

**Why MTO alone (without Buy or Manufacture) fails:** The recursive `run()` fires for `WH/Stock`. If no rule matches that location, Odoo raises `UserError: No rule found`. MTO must always be combined with Buy or Manufacture.

**`procure_method` comparison:**

| Value | Move state after confirm | Upstream proc fired? | Takes from stock? |
|---|---|---|---|
| `make_to_stock` | `confirmed` | No | Yes — reserves from shelf |
| `make_to_order` | `waiting` | Yes — always | No |
| `mts_else_mto` | `confirmed` | Yes — only for shortfall qty | Partially |

**`mts_else_mto` split logic** ([stock_move.py:1661](../addons/stock/models/stock_move.py#L1661)):

```python
free_qty = max(forecasted_qties_by_loc[move.location_id][move.product_id.id], 0)
quantity = max(move.product_qty - free_qty, 0)  # upstream proc fires for this qty only
```

Example: SO for 100 units, 60 in stock → upstream `run()` fires for qty=40 only. The 60 are reserved normally from stock.

---

#### `_get_mto_procurement_date()` — Customization Hook

Source: [`stock_move.py:1714`](../addons/stock/models/stock_move.py#L1714)

```python
def _get_mto_procurement_date(self):
    return self.date
```

Returns the date used when firing an upstream MTO procurement. Default is the move's scheduled date. Override this method in a custom module to add buffer days, seasonal adjustments, or vendor-specific lead times.

---

#### `_break_mto_link()` — MTO Chain Cleanup on SO Modification

Source: [`stock_move.py:2612`](../addons/stock/models/stock_move.py#L2612)

```python
def _break_mto_link(self, parent_move):
    self.move_orig_ids = [Command.unlink(parent_move.id)]
    self.procure_method = 'make_to_stock'
    self._recompute_state()
```

Called when an MTO chain is modified (e.g., SO quantity reduced). Removes the upstream link from `move_orig_ids`, converts the move's `procure_method` back to `make_to_stock`, and recomputes state. Prevents orphaned MTO procurements when the originating demand shrinks.

---

#### `_get_rule_domain()` — Inter-Company Location Trick

Source: [`stock_rule.py:645`](../addons/stock/models/stock_rule.py#L645)

When `_get_rule_domain()` is called with a transit location (inter-company location), it automatically appends the Customer location to the domain:

```python
if self._check_intercomp_location(locations):
    location_ids.append(self.env.ref('stock.stock_location_customers').id)
```

This means a single rule that delivers to Customer also handles inter-company transit delivery — you do not need to duplicate rules for the inter-company case. `_check_intercomp_location()` returns True when the location has `usage = 'transit'` AND matches `stock.stock_location_inter_company`.

**Multi-company filtering:** When called as superuser, the domain also restricts rules by company (regular users are filtered by record rules):

```python
domain_company = ['|', ('company_id', '=', False), ('company_id', 'child_of', list(company_ids))]
```

Rules with `company_id = False` are shared across all companies. Source: [`stock_rule.py:656`](../addons/stock/models/stock_rule.py#L656)

---

#### `location_final_id` — The True End Destination
> [`stock_move.py:85`](../addons/stock/models/stock_move.py#L85)

In a multi-step route, each move only knows its **immediate** destination (`location_dest_id`). But the chain also carries `location_final_id` — the ultimate destination of the whole chain.

`location_dest_id` is computed: it takes the picking type's default destination unless `location_final_id` is a sub-location of that default destination, in which case it uses `location_final_id` directly. Source: [`stock_move.py:235`](../addons/stock/models/stock_move.py#L235)

This is what allows a 2-step delivery to correctly route products from WH/Stock all the way to the Customer location — Move 1 carries `location_final_id = Customers` even though its immediate `location_dest_id = WH/Output`.

---

#### How Moves Are Grouped Into Pickings
> [`stock_move.py:1400`](../addons/stock/models/stock_move.py#L1400)

After `_action_confirm()` sets the move state, `_assign_picking()` groups confirmed moves into `stock.picking` records.

**Grouping key** (`_key_assign_picking()`): `(reference_ids, location_id, location_dest_id, picking_type_id)`. If `partner_id` is set and no reference_ids, partner is added to the key. Source: [`stock_move.py:1375`](../addons/stock/models/stock_move.py#L1375)

**Logic:**
1. Search for an existing `not done / not cancel` picking matching the grouping key.
2. If found → add move to that picking (merge `origin` field if different).
3. If not found → create a new picking.

For SO-confirmed moves, `reference_ids` is set to the SO's `stock_reference_ids` (see [`sale_order_line.py:289`](../addons/sale_stock/models/sale_order_line.py#L289)). Different SOs have different reference_ids, so they produce **separate** pickings even for the same customer. Merging into one picking only happens for moves with identical reference_ids (e.g. moves from the same SO, or moves with no references that share the same partner).

---

#### Orderpoints (Reorder Rules) — Scheduler-Driven Procurement
> [`addons/stock/models/stock_orderpoint.py`](../addons/stock/models/stock_orderpoint.py)

`stock.warehouse.orderpoint` is the "min/max" replenishment rule. It is the second major source of procurements after SO confirmation.

| Field | Meaning |
|---|---|
| `product_id` | Product to replenish |
| `location_id` | Location to keep stocked |
| `warehouse_id` | Warehouse |
| `product_min_qty` | Minimum stock level — triggers a replenishment when forecast drops below this |
| `product_max_qty` | Target level to replenish to |
| `qty_to_order` | Computed: `max(min_qty, max_qty) - (forecast + in_progress)` |
| `qty_to_order_computed` | Stored version recomputed by scheduler |
| `route_id` | Route override for this orderpoint (optional; falls back to product/category/warehouse routes) |
| `rule_ids` | Computed: rules found for this product+location+route combination (shown in UI as replenishment chain) |
| `effective_route_id` | Computed: `route_id` if set, else `_get_default_route()` — the route that will actually fire |
| `replenishment_uom_id` | Round up `qty_to_order` to a multiple of this UoM |
| `trigger` | `auto` (scheduler fires it daily) / `manual` (user fires it via Replenish button) |
| `deadline_date` | Computed: date before which you must order to avoid falling below `product_min_qty`. If `qty_on_hand < product_min_qty` → today. Otherwise: walks future moves to find when stock first drops below min. Source: [`stock_orderpoint.py:125`](../addons/stock/models/stock_orderpoint.py#L125) |
| `lead_horizon_date` | Computed: `today + total_delay + horizon_time` — the date until which forecast is checked |
| `lead_days` | Computed: total lead time from `rule_ids._get_lead_days()` |
| `snoozed_until` | If set, this orderpoint is hidden/skipped until that date |
| `show_supply_warning` | True when `rule_ids` is empty — no route/rule found for this product+location |

**Constraint:** One orderpoint per `(product, location, company)`. Source: [`stock_orderpoint.py:101`](../addons/stock/models/stock_orderpoint.py#L101)

---

##### How Routes Connect to an Orderpoint

When you create or open an orderpoint, `_compute_rules()` runs ([`stock_orderpoint.py:191`](../addons/stock/models/stock_orderpoint.py#L191)):

```
_compute_rules():
  call product._get_rules_from_location(location_id, route_ids=orderpoint.route_id)
  → same priority order as SO: product routes → category routes → warehouse routes
  → if route_id is set: only rules on that route are considered
  result stored in orderpoint.rule_ids
```

**`rule_ids` determines three things:**
1. Which rule fires when `run()` is called (`_get_default_rule()` preview)
2. The `lead_days` (total delay from all rules in the chain)
3. Whether the "No supply chain configured" warning is shown (`show_supply_warning = not rule_ids`)

If `rule_ids` is empty — the orderpoint has no route/rule configured. It will fail when the scheduler tries to process it.

---

##### Lead Days and `lead_horizon_date` — Why Forecast Isn't Checked for Today

The threshold check (`qty_forecast < product_min_qty`) does NOT use today's stock. It uses `qty_forecast` at `lead_horizon_date`.

Source: [`stock_orderpoint.py:180`](../addons/stock/models/stock_orderpoint.py#L180), [`stock_orderpoint.py:461`](../addons/stock/models/stock_orderpoint.py#L461)

```
_compute_lead_days():
  rule_ids._get_lead_days(product) →
    for each pull/pull_push rule: add rule.delay
    for buy rule: add vendor.seller.delay + company.days_to_purchase
    add company.horizon_days (global lookahead window)
  → total_delay = rule delays summed
  lead_horizon_date = today + total_delay + horizon_days

qty_forecast = product.virtual_available  (computed at lead_horizon_date, NOT today)
```

**What this means in practice:**
- Vendor lead time = 30 days → `lead_horizon_date = today + 30`
- `qty_forecast` = what stock will look like 30 days from now (accounting for existing POs, incoming moves, and outgoing moves)
- If that future forecast < `product_min_qty` → order now so stock arrives before the minimum is breached

**If no vendor is found:** lead days defaults to **365 days**. This means the forecast is checked 365 days in the future — if negative, an order is triggered. Source: [`purchase_stock/models/stock_rule.py:221`](../addons/purchase_stock/models/stock_rule.py#L221)

---

##### `qty_to_order` Computation
> [`stock_orderpoint.py:461`](../addons/stock/models/stock_orderpoint.py#L461)

```
if qty_forecast < product_min_qty:  ← checked at lead_horizon_date, not today
    qty_in_progress = open PO lines for this product+location (purchase_stock override)
    qty_forecast_with_visibility = virtual_available(at lead_horizon_date) + qty_in_progress
    qty_to_order = max(product_min_qty, product_max_qty) - qty_forecast_with_visibility
    round up to replenishment_uom_id multiple
```

**Double-order prevention via `qty_in_progress`:**
`purchase_stock` overrides `_quantity_in_progress()` ([`purchase_stock/models/stock.py:322`](../addons/purchase_stock/models/stock.py#L322)) to include quantities from open PO lines for this product at this location. This prevents creating a second PO if one is already in progress.

Without `purchase_stock`: base implementation returns 0 (no in-progress tracking).

---

##### `trigger` — Auto vs Manual

| Value | When it runs | How to trigger |
|---|---|---|
| `auto` | Daily scheduler — `_run_scheduler_tasks()` picks up all `trigger='auto'` orderpoints | No user action needed |
| `manual` | Only when user clicks "Replenish" or "Order Once" button | User action required |

The scheduler domain: `[('trigger', '=', 'auto'), ('product_id.active', '=', True)]`. Source: [`stock_rule.py:742`](../addons/stock/models/stock_rule.py#L742)

**Snoozed orderpoints** (`snoozed_until` field): temporarily hidden from the replenishment view and skipped by the scheduler until that date.

---

##### Manual "Replenish" Button
> [`stock_orderpoint.py:342`](../addons/stock/models/stock_orderpoint.py#L342)

`action_replenish()` directly calls `_procure_orderpoint_confirm()` — same code path as scheduler, no waiting needed. Used for both `trigger='auto'` and `trigger='manual'` orderpoints. After replenishment, auto-deletes temporary `trigger='manual'` orderpoints that had `qty_to_order <= 0`.

---

##### Replenishment Report — Dynamic Orderpoints

`_get_orderpoint_action()` ([`stock_orderpoint.py:492`](../addons/stock/models/stock_orderpoint.py#L492)) powers the **Inventory → Operations → Replenishment** view:

1. Queries all internal locations for products with negative forecast (on_hand + incoming - outgoing < 0)
2. Subtracts already-in-progress quantities (open POs, existing orderpoints)
3. Auto-creates temporary `trigger='manual'` orderpoints (SUPERUSER) for items not already covered
4. Auto-deletes these temporary orderpoints after they are fulfilled (`_unlink_processed_orderpoints`)

These auto-created orderpoints are invisible to the user — they only appear in the replenishment report list and disappear once replenished.

---

**How it fires** ([`stock_orderpoint.py:707`](../addons/stock/models/stock_orderpoint.py#L707)):
```
_procure_orderpoint_confirm()
  for each orderpoint in batches of 1000:
    if qty_to_order > 0:
      date = lead_horizon_date → adjusted by horizon_days if set
      values = _prepare_procurement_values(date)
        → includes: route_ids=orderpoint.route_id, date_planned, date_deadline, warehouse_id
      Procurement(product, qty_to_order, uom, location, name, origin, company, values)
      → stock.rule.run([procurement], from_orderpoint=True)
         from_orderpoint=True: if no vendor → raise immediately (not silent fallback)
         from_orderpoint=True: if no rule → ProcurementException (caught per-savepoint)

  on ProcurementException per orderpoint:
    → skip that orderpoint, continue others
    → schedule mail.activity warning on product.product_tmpl_id for responsible user
```

**`from_orderpoint=True` changes behavior:**
- Without: no vendor → silently sets move to `make_to_stock`, logs to responsible user (MTO chain behaviour)
- With: no vendor → immediately raises error + warning activity on product template

Runs inside a `savepoint` — if one orderpoint fails (no rule, no vendor), only that orderpoint is skipped; the rest continue. Source: [`stock_orderpoint.py:744`](../addons/stock/models/stock_orderpoint.py#L744)

---

#### The Stock Scheduler — What Runs It All
> [`stock_rule.py:690`](../addons/stock/models/stock_rule.py#L690)

`StockRule._run_scheduler_tasks()` is the core scheduled action (runs daily by default):

```
_run_scheduler_tasks():
  1. Fetch all trigger='auto' + product.active=True orderpoints
     _compute_qty_to_order_computed()   ← recompute all qty_to_order stored values
     _compute_deadline_date()           ← recompute deadline dates
     _procure_orderpoint_confirm()      ← fire all auto orderpoints that need stock
     commit every 1000 (if use_new_cursor=True)

  2. _get_moves_to_assign_domain():
       find all confirmed/partially_available moves where:
         reservation_date <= today  OR  picking_type.reservation_method = at_confirm
     stock.move._action_assign()        ← reserve stock for those moves
     batches of 1000, each committed separately (if use_new_cursor=True)
     sorted by: reservation_date, -priority, date, id

  3. stock.quant._quant_tasks()         ← merge duplicate quants
```

**`run_scheduler()` vs `_run_scheduler_tasks()`:**
- `run_scheduler()` is the public method called by the scheduled action (cron). Wraps `_run_scheduler_tasks()` in a try/except that logs and re-raises.
- `_run_scheduler_tasks()` is the actual implementation, extensible by other modules.

**`use_new_cursor=True`** (set by the cron job): each batch opens its own DB cursor and commits independently. Allows partial progress to be saved if the job is interrupted.

This is the scheduled path that keeps stock reserved and POs/receipts created for min/max rules. Without the scheduler running, orderpoints accumulate but don't fire.

---

#### `_clean_reservations()` — Quant Reservation Reconciliation

Source: [`stock_quant.py:1131`](../addons/stock/models/stock_quant.py#L1131)

Called as part of the scheduler's `_quant_tasks()`. Compares `reserved_quantity` on each quant against the sum of `quantity_product_uom` across all matching move lines in assigned/partially_available/waiting/confirmed states. If there is a discrepancy, updates the quant to match the move lines.

Also removes reservations on bypass locations (`should_bypass_reservation() = True`) — those quants should never have a non-zero `reserved_quantity`.

Fixes data integrity issues from: interrupted transactions, manual DB edits, or concurrency edge cases.

---

### Routes & Rules — End-to-End Cases by Document Type

#### Case 1: SO → Delivery, stock available (1-step, MTS)

**Product routes:** none special (falls back to warehouse route "WH: Deliver in 1 step")
**Warehouse:** `delivery_steps = ship_only`

**Rule involved:**
```
Route: "WH: Deliver in 1 step"
  Rule: action=pull, procure_method=make_to_stock
        location_src_id = WH/Stock
        location_dest_id = Customers
        picking_type = Delivery Orders
```

**Flow:**
```
SO confirmed
  → _action_launch_stock_rule()
  → run([Procurement(product, qty, location=Customers)])
  → _get_rule(product, Customers) → pull rule found
  → _run_pull(): create stock.move (WH/Stock → Customers, make_to_stock)
  → _action_confirm(): state = confirmed
  → _assign_picking(): WH/OUT/00001 created

Scheduler or manual Check Availability:
  → _action_assign() → reserves quant in WH/Stock
  → move state = assigned, WH/OUT/00001 state = assigned (Ready)

Operator validates WH/OUT/00001:
  → quant WH/Stock: quantity -10
  → SO line qty_delivered = 10
```

---

#### Case 2: SO → 2-step delivery (pick_ship), stock available

**Warehouse:** `delivery_steps = pick_ship`

**Rules involved:**
```
Route: "WH: Deliver in 2 steps"
  Rule 1: action=pull
          location_src_id = WH/Stock
          location_dest_id = Customers  (stored), effective dest = WH/Output (via pick_type default)
          picking_type = Pick

  Rule 2: action=push
          location_src_id = WH/Output
          location_dest_id = Customers
          picking_type = Delivery Orders
          (fires via _push_apply() when PICK is validated — not at SO confirmation)
```
Source: [`stock_warehouse.py:780`](../addons/stock/models/stock_warehouse.py#L780)

**Flow:**
```
SO confirmed
  → run([Procurement(product, qty, location=Customers)])
  → _get_rule(product, Customers) → Rule 1 found (pull, pick_type)
  → _run_pull(): create Move A (WH/Stock → WH/Output via pick_type default, location_final=Customers)
  → _action_confirm(): state = confirmed
  → _assign_picking(): WH/PICK/00001 created

Result at SO confirmation:
  WH/PICK/00001 (Move A): state = assigned (stock in WH/Stock)
  [no OUT picking yet — OUT is created by push rule when PICK is validated]

Operator validates WH/PICK/00001:
  → goods move WH/Stock → WH/Output
  → _action_done() on Move A
  → _push_apply() finds push rule: WH/Output → Customers (out_type)
  → creates Move B → WH/OUT/00001 created (state=assigned if Output has stock)

Operator validates WH/OUT/00001:
  → SO line qty_delivered updated
```
Source: [`test_sale_stock.py:1085`](../addons/sale_stock/tests/test_sale_stock.py#L1085) (only 1 picking at SO confirm), [`test_sale_stock.py:1102`](../addons/sale_stock/tests/test_sale_stock.py#L1102) (2nd picking after done)

---

#### Case 3: SO → MTO → auto Purchase Order

**Product routes:** "Buy" + "Replenish on Order (MTO)"
**Warehouse:** `delivery_steps = ship_only`

**Rules involved:**
```
Route: "Replenish on Order (MTO)"  [on product]
  Rule: action=pull, procure_method=make_to_order
        location_src_id = WH/Stock
        location_dest_id = Customers
        picking_type = Delivery Orders

Route: "Buy"  [on product or warehouse]
  Rule: action=buy
        location_dest_id = WH/Stock
        picking_type = Receipts
```

**Flow:**
```
SO confirmed
  → run([Procurement(product, qty, location=Customers)])
  → _get_rule(product, Customers)
      product has MTO route → MTO pull rule found (procure_method=make_to_order)
  → _run_pull(): create Move A (WH/Stock → Customers, make_to_order)
  → _action_confirm():
      make_to_order → state = waiting
      fires run([Procurement(product, qty, location=WH/Stock)])

  → _get_rule(product, WH/Stock)
      product has Buy route → buy rule found
  → _run_buy():
      _get_matching_supplier() → Vendor A found on product.seller_ids
      _make_po_get_domain() = (partner=Vendor A, company=MyCompany, ...)
      existing open PO for Vendor A? no → create purchase.order (SUPERUSER, draft)
      create purchase.order.line for product, qty=10
      PO line linked to Move A via move_dest_ids

Result:
  WH/OUT/00001 (Move A): state = waiting
  PO/00001 (draft): 1 line → product qty=10

User confirms PO/00001:
  → receipt WH/IN/00001 created (Vendor → WH/Stock)

User validates WH/IN/00001:
  → quant WH/Stock: +10
  → _trigger_assign() fires on Move A
  → Move A: waiting → assigned
  → WH/OUT/00001 becomes Ready

User validates WH/OUT/00001 → delivery done
```

**Key:** The SO never directly creates a PO. The MTO rule creates a `waiting` move which fires a second `run()` call to WH/Stock. The "Buy" rule answers that second call.

---

#### Case 4: SO → MTO → auto Manufacturing Order

Same as Case 3 but product has "Manufacture" route instead of "Buy".

**Rules involved:**
```
Route: "Replenish on Order (MTO)"  [on product]
  Rule: action=pull, procure_method=make_to_order
        location_src_id = WH/Stock
        location_dest_id = Customers

Route: "Manufacture"  [on product, requires BOM]
  Rule: action=manufacture
        location_dest_id = WH/Stock
        picking_type = Manufacturing
```

**Flow difference at step 2 of Case 3:**
```
  → _get_rule(product, WH/Stock)
      product has Manufacture route + BOM exists → manufacture rule found
  → _run_manufacture():
      mrp.production created (SUPERUSER)
      auto-confirm logic (_should_auto_confirm_procurement_mo):
        if no raw_ids: auto-confirm when (no workorders AND (from orderpoint OR downstream move.procure_method == make_to_stock))
        if has raw_ids: auto-confirm when not from orderpoint
      NOTE: MTO procurement has procure_method=make_to_order downstream → does NOT auto-confirm
      Source: mrp/models/stock_rule.py:35
      MO linked to Move A via move_dest_ids

Result:
  WH/OUT/00001 (Move A): state = waiting
  MO/00001: confirmed, component reservation started

MO validated (components consumed, finished product produced):
  → finished product move done → WH/Stock +qty
  → _trigger_assign() fires on Move A
  → WH/OUT/00001 becomes Ready → operator validates → delivery done
```

**Filter:** If the product has no BOM with `type='normal'`, the Manufacture route is filtered out by `_filter_warehouse_routes()` and the rule is never found. Source: [`mrp/models/stock_rule.py:74`](../addons/mrp/models/stock_rule.py#L74)

---

#### Case 5: Manual PO → 1-step receipt (no rules involved)

Routes/rules play **no role** in manual PO creation. The user creates the PO directly.

```
User creates purchase.order (draft)
  → adds order lines manually

User confirms PO:
  → stock.move created (Vendor → WH/Stock) for each line
  → picking WH/IN/00001 created (no reservation needed for incoming)
  → move state = assigned

User validates WH/IN/00001:
  → quant WH/Stock: +qty per line
  → _trigger_assign() fires: any waiting outgoing moves for these products
    may become assigned automatically
```

---

#### Case 6: Orderpoint (reorder rule) → auto PO

**Setup:** Orderpoint on product X: `min_qty=5`, `max_qty=20`, route=Buy

```
Daily scheduler: _run_scheduler_tasks()
  → _procure_orderpoint_confirm():

      orderpoint checks: qty_forecast = 3 < product_min_qty = 5
      qty_to_order = max(5, 20) - (3 + 0 in_progress) = 17

      builds Procurement(product=X, qty=17, location=WH/Stock, route_ids=Buy)
      → run([procurement], from_orderpoint=True)

  → _get_rule(product=X, WH/Stock, route_ids=Buy)
      Buy route rule found (action=buy)
  → _run_buy():
      _get_matching_supplier() → Vendor A
      existing open PO for Vendor A today? yes → add line qty=17
                                              no → create new PO (draft)

  [savepoint per batch — if this orderpoint fails, others continue]

User receives PO, confirms it → WH/IN/00001 created
User validates receipt → WH/Stock +17
```

**from_orderpoint=True** makes `_run_buy()` raise an immediate error if no supplier exists, instead of silently failing. Without this flag (e.g. from MTO), it logs and continues.

---

#### Case 7: Orderpoint → auto Manufacturing Order

**Setup:** Orderpoint on manufactured product, route=Manufacture

```
Scheduler → _procure_orderpoint_confirm()
  → run([Procurement(product, qty, location=WH/Stock, route_ids=Manufacture)])
  → _get_rule() → manufacture rule found (BOM exists)
  → _run_manufacture():
      mrp.production created (SUPERUSER)
      _should_auto_confirm_procurement_mo() = True
        (from_orderpoint=True + no workorders)
      → MO auto-confirmed immediately
      → component reservation started automatically

Components available → MO validated → WH/Stock +qty
```

---

#### Summary: What triggers what

| Trigger | run() called? | Rule action found | Document created |
|---|---|---|---|
| SO confirmed (MTS) | YES | `pull` (make_to_stock) | stock.move + picking |
| SO confirmed (MTO + Buy) | YES × 2 | `pull` → `buy` | stock.move + PO |
| SO confirmed (MTO + Manufacture) | YES × 2 | `pull` → `manufacture` | stock.move + MO |
| Orderpoint fires | YES | `pull` | stock.move + picking |
| Orderpoint fires | YES | `buy` | PO (draft) |
| Orderpoint fires | YES | `manufacture` | MO (auto-confirmed) |
| MTO move confirmed | YES (recursive) | `buy` or `manufacture` | PO or MO |
| Picking validated (multi-step) | NO | `push` fires | next stock.move in chain |
| Manual PO confirmed | NO | — | receipt picking directly |
| Manual MO confirmed | NO | — | component moves directly |

**Pattern:** Routes/rules fire only when demand is created automatically (SO, orderpoints, MTO chains). Manual documents bypass the rule system and create stock movements directly.

---

#### Route Combinations — Practical Cheat Sheet

> **Why Buy alone never creates a PO on SO confirm:**
> `_get_rule_domain()` filters by `location_dest_id IN [procurement.location + parents]`. SO calls `run()` for `Customers`. Buy rule has `location_dest_id = WH/Stock` — it never matches the Customers search. Only MTO + the second recursive `run()` for WH/Stock reaches the Buy rule.
> Source: [`stock_rule.py:652`](../addons/stock/models/stock_rule.py#L652)

| Routes checked on product | SO confirm result | Delivery state | Auto-PO/MO? | Notes |
|---|---|---|---|---|
| None (default) | Delivery created | `confirmed` (waiting for stock) | No | Warehouse pull rule (make_to_stock) fires |
| **Buy only** | Delivery created | `confirmed` (waiting for stock) | **No** | Buy rule targets WH/Stock — not reached from SO. PO only via orderpoint. |
| **MTO only** | **Error** | — | — | Second run() for WH/Stock finds no rule → UserError. Never use MTO without Buy or Manufacture. |
| **Buy + MTO** | Delivery + PO created | `waiting` (until PO receipt) | **YES — PO** | MTO rule fires first (Customers), then Buy rule fires (WH/Stock). PO is draft, must be confirmed by user. |
| **Manufacture + MTO** | Delivery + MO created | `waiting` (until MO done) | **YES — MO** | Same chain as Buy+MTO but manufacture rule fires for WH/Stock. MO is auto-confirmed if no workorders. |
| Manual delivery (any routes) | Raw picking only | `confirmed` | **No** | `run()` never called. `rule_id = NULL`. Routes completely bypassed. |

**When a PO IS created on SO confirm:**
1. Product has **Buy + MTO** checked
2. Product has a **vendor** set on its Purchase tab (`product.seller_ids`)
3. If no vendor → delivery move silently falls back to `make_to_stock` and responsible user is notified (no error, no PO)

**When Buy route DOES trigger a PO (without MTO):**
- Orderpoint (reorder rule) runs → calls `run()` directly for `WH/Stock` with Buy route → Buy rule found → PO created

---

## Business Flow: Sale Order → Delivery

```
SO Draft
   ↓  Confirm (button)
_action_confirm() [sale_stock/models/sale_order.py:213]
   ↓
_action_launch_stock_rule() [sale_stock/models/sale_order_line.py:374]
   ↓  for each storable line with unmatched qty
stock.rule.run(procurements) [stock/models/stock_rule.py:450]
   ↓
_run_pull() [stock/models/stock_rule.py:288]
   ↓  creates stock.move records and groups them into stock.picking
stock.move._action_confirm()
   ↓
stock.picking created (state=confirmed or waiting)
   ↓  reservation trigger (depends on picking type reservation_method)
action_assign() / _action_assign() [stock/models/stock_picking.py:1196]
   ↓  reserves quants
stock.picking state=assigned (Ready)
   ↓  warehouse operator validates
button_validate() [stock/models/stock_picking.py:1397]
   ↓
_action_done() [stock/models/stock_picking.py:1256]
   ↓  moves state→done, quants updated
sale.order.line.qty_delivered updated (via compute)
```

### Step 1 — SO Confirmation

When user clicks **Confirm** on a sale order:

1. [`SaleOrder._action_confirm()`](../addons/sale_stock/models/sale_order.py#L213) calls `order_line._action_launch_stock_rule()`.
2. For each storable line, a `Procurement` namedtuple is built with: product, qty, UoM, destination location (customer), origin (SO name), warehouse, partner, dates.
3. `stock.rule.run(procurements)` finds the matching rule by route and location and calls `_run_pull()`.
4. `_run_pull()` creates `stock.move` records (as SUPERUSER) and calls `_action_confirm()` on them.
5. Moves are grouped into a `stock.picking` by `(picking_type, origin, partner, scheduled_date, company)`.

### Step 2 — Picking State After Confirmation

The picking state is computed from move states. Source: [`addons/stock/models/stock_picking.py:575`](../addons/stock/models/stock_picking.py#L575)

| State | Meaning |
|---|---|
| `draft` | Not confirmed yet |
| `waiting` | Waiting for another operation (chained moves) |
| `confirmed` | Waiting for stock to become available |
| `assigned` | All (or enough) moves are reserved — Ready |
| `done` | Transfer validated |
| `cancel` | Cancelled |

### Step 3 — Reservation

Reservation is how Odoo commits available stock to a specific transfer. It writes `reserved_quantity` on the matching `stock.quant` row and creates `stock.move.line` detail records.

**Reservation methods** (set on `stock.picking.type`): Source: [`addons/stock/models/stock_picking.py:68`](../addons/stock/models/stock_picking.py#L68)

| Method | Behavior |
|---|---|
| `at_confirm` | Reserves immediately when picking is confirmed |
| `manual` | Operator must click "Check Availability" |
| `by_date` | Reserves N days before scheduled date (scheduled action) |

**What happens during reservation** ([`stock_move._action_assign()`](../addons/stock/models/stock_move.py#L1888)):

1. For each move in `confirmed/waiting/partially_available` state:
2. Compute `missing_reserved_qty = product_uom_qty - already_reserved`
3. Call `_update_reserved_quantity()` on `stock.quant` — increments `reserved_quantity` and returns how much was actually taken
4. Create `stock.move.line` records for each `(location, lot, package, owner)` combination
5. If full qty reserved → move state = `assigned`
6. If partial → move state = `partially_available`

**Bypass reservation** — some moves skip reservation entirely. `stock.move._should_bypass_reservation()` returns True when:
- The source location's `usage` is `supplier`, `customer`, `inventory`, or `production`
- OR the product is not storable (`is_storable = False`)

Source: [`stock_location.py:410`](../addons/stock/models/stock_location.py#L410), [`stock_move.py:1812`](../addons/stock/models/stock_move.py#L1812)

Moves that bypass reservation are created directly in `assigned` state — no quant reservation needed. This is why incoming receipts (source = supplier location) never need a "Check Availability" step.

**Unreserve** via `do_unreserve()` ([`stock_picking.py:1394`](../addons/stock/models/stock_picking.py#L1394)) → `move._do_unreserve()` → decrements `reserved_quantity` on quants, deletes move lines.

### Step 4 — Validation (button_validate)

Source: [`addons/stock/models/stock_picking.py:1397`](../addons/stock/models/stock_picking.py#L1397)

1. **Sanity check** — verifies quantities are set, lots are filled if tracked.
2. **Pre-action hook** — triggers backorder wizard if some lines are not fully done.
3. **`_action_done()`** ([`stock_picking.py:1256`](../addons/stock/models/stock_picking.py#L1256)):
   - Calls `stock.move._action_done()` for all moves
   - Moves update `stock.quant.quantity` (decrements source, increments destination)
   - `reserved_quantity` on quants returns to 0 for validated lines
   - `date_done` is set on the picking
   - If incoming/internal moves, triggers `_trigger_assign()` to auto-reserve other waiting moves that now have stock
4. Sale order line `qty_delivered` is recomputed from done moves.

### Backorder Logic

If only part of the demand is fulfilled at validation time:
- A **backorder** picking is created with the remaining quantities
- `backorder_id` on the new picking points to the original
- Controlled by `picking_type.create_backorder`: `ask` / `always` / `never`

---

## Move States

Source: [`addons/stock/models/stock_move.py:107`](../addons/stock/models/stock_move.py#L107)

| State | Meaning |
|---|---|
| `draft` | Created but not confirmed |
| `waiting` | Waiting for upstream move (chained, multi-step) |
| `confirmed` | Confirmed but stock not yet reserved |
| `partially_available` | Some stock reserved, not all |
| `assigned` | Fully reserved, ready to process |
| `done` | Validated, physical move recorded |
| `cancel` | Cancelled |

---

## Multi-Step Delivery: How Chaining Works

For `pick_ship` (2 steps), pickings are created in stages — **not all at SO confirmation**:

**At SO confirmation:**
- Pull rule fires → Move 1 (Pick): WH/Stock → WH/Output (effective), `picking_type=pick_type`
- WH/PICK/00001 created, state = assigned (if stock available)
- No OUT picking yet

**When WH/PICK is validated:**
- `_action_done()` calls `_push_apply()` on Move 1
- Push rule found: WH/Output → Customer, `picking_type=out_type`
- Move 2 (Ship) created → WH/OUT/00001 created (state=assigned)

For `pick_pack_ship` (3 steps), each step's picking is created when the previous step is validated via push rule. At SO confirmation only the PICK picking exists.

Source: [`test_sale_stock.py:1085`](../addons/sale_stock/tests/test_sale_stock.py#L1085) (1 picking after confirm), [`test_sale_stock.py:1102`](../addons/sale_stock/tests/test_sale_stock.py#L1102) (2nd after done), [`stock_move.py:2127`](../addons/stock/models/stock_move.py#L2127) (_push_apply called in _action_done)

---

## Key Models

### `stock.warehouse`
> [`addons/stock/models/stock_warehouse.py`](../addons/stock/models/stock_warehouse.py)

| Field | Type | Purpose |
|---|---|---|
| `lot_stock_id` | Many2one(stock.location) | Main storage location (WH/Stock) |
| `delivery_steps` | Selection | `ship_only`, `pick_ship`, `pick_pack_ship` |
| `reception_steps` | Selection | `one_step`, `two_steps`, `three_steps` |
| `delivery_route_id` | Many2one(stock.route) | Route used for outgoing |
| `reception_route_id` | Many2one(stock.route) | Route used for incoming |
| `mto_pull_id` | Many2one(stock.rule) | MTO rule for this warehouse |
| `out_type_id` | Many2one(stock.picking.type) | Delivery operation type |
| `pick_type_id` | Many2one(stock.picking.type) | Pick operation type |
| `in_type_id` | Many2one(stock.picking.type) | Receipt operation type |

### `stock.picking.type`
> [`addons/stock/models/stock_picking.py:20`](../addons/stock/models/stock_picking.py#L20)

Operation type controls how a picking behaves.

| Field | Type | Purpose |
|---|---|---|
| `code` | Selection | `incoming`, `outgoing`, `internal` |
| `reservation_method` | Selection | When to reserve: `at_confirm`, `manual`, `by_date` |
| `create_backorder` | Selection | `ask`, `always`, `never` |
| `default_location_src_id` | Many2one | Default source location |
| `default_location_dest_id` | Many2one | Default destination location |

### `stock.picking`
> [`addons/stock/models/stock_picking.py:538`](../addons/stock/models/stock_picking.py#L538)

Groups multiple moves into one transfer document.

| Field | Type | Purpose |
|---|---|---|
| `picking_type_id` | Many2one | Operation type |
| `state` | Selection | Computed from move states |
| `move_ids` | One2many(stock.move) | All moves in this transfer |
| `move_line_ids` | One2many(stock.move.line) | Detail lines (per lot/location) |
| `backorder_id` | Many2one(stock.picking) | Original picking if this is a backorder |
| `scheduled_date` | Datetime | When this transfer should be processed |
| `date_deadline` | Datetime | Deadline to deliver on-time to customer |
| `move_type` | Selection | `direct` (partial OK) / `one` (all at once) |

### `stock.move`
> [`addons/stock/models/stock_move.py:18`](../addons/stock/models/stock_move.py#L18)

One product line in a transfer. The granular unit of demand.

| Field | Type | Purpose |
|---|---|---|
| `product_id` | Many2one | Product to move |
| `product_uom_qty` | Float | Demanded quantity |
| `quantity` | Float | Done quantity (filled at validation) |
| `location_id` | Many2one(stock.location) | Source |
| `location_dest_id` | Many2one(stock.location) | Destination |
| `state` | Selection | See move states above |
| `procure_method` | Selection | `make_to_stock` / `make_to_order` |
| `move_dest_ids` | Many2many(stock.move) | Next move(s) in chain |
| `move_orig_ids` | Many2many(stock.move) | Previous move(s) in chain |
| `rule_id` | Many2one(stock.rule) | Rule that generated this move |
| `sale_line_id` | Many2one(sale.order.line) | Source SO line (added by sale_stock) |

### `stock.move.line`
> [`addons/stock/models/stock_move_line.py`](../addons/stock/models/stock_move_line.py)

Detail record for one move: specific lot, package, sub-location. Created during reservation.

### `stock.quant`
> [`addons/stock/models/stock_quant.py:19`](../addons/stock/models/stock_quant.py#L19)

Physical stock ledger. One row per `(product, location, lot, package, owner)`.

| Field | Meaning |
|---|---|
| `quantity` | On-hand (set by move validation) |
| `reserved_quantity` | Committed to pending moves |
| `available_quantity` | `quantity - reserved_quantity` |

### `stock.rule`
> [`addons/stock/models/stock_rule.py:42`](../addons/stock/models/stock_rule.py#L42)

Defines how a procurement is fulfilled: which picking type, source/dest locations, supply method.

---

## Key Methods

| Method | File:Line | Purpose |
|---|---|---|
| `SaleOrder._action_confirm()` | [`sale_stock/models/sale_order.py:213`](../addons/sale_stock/models/sale_order.py#L213) | Triggers stock rule on SO confirmation |
| `SaleOrderLine._action_launch_stock_rule()` | [`sale_stock/models/sale_order_line.py:374`](../addons/sale_stock/models/sale_order_line.py#L374) | Builds procurements and calls `stock.rule.run()` |
| `StockRule.run()` | [`stock/models/stock_rule.py:450`](../addons/stock/models/stock_rule.py#L450) | Finds matching rules and dispatches to `_run_pull()` |
| `StockRule._run_pull()` | [`stock/models/stock_rule.py:288`](../addons/stock/models/stock_rule.py#L288) | Creates `stock.move` records and confirms them |
| `StockPicking.action_assign()` | [`stock/models/stock_picking.py:1196`](../addons/stock/models/stock_picking.py#L1196) | Triggers reservation (Check Availability button) |
| `StockMove._action_assign()` | [`stock/models/stock_move.py:1888`](../addons/stock/models/stock_move.py#L1888) | Reserves quants and creates move lines |
| `StockQuant._update_reserved_quantity()` | [`stock/models/stock_quant.py:1098`](../addons/stock/models/stock_quant.py#L1098) | Increments/decrements `reserved_quantity` on quants |
| `StockPicking.button_validate()` | [`stock/models/stock_picking.py:1397`](../addons/stock/models/stock_picking.py#L1397) | Validates the transfer (Validate button) |
| `StockPicking._action_done()` | [`stock/models/stock_picking.py:1256`](../addons/stock/models/stock_picking.py#L1256) | Finalises moves, updates quants, triggers downstream assigns |
| `StockPicking.do_unreserve()` | [`stock/models/stock_picking.py:1394`](../addons/stock/models/stock_picking.py#L1394) | Releases reserved quantities back to available |

---

## Reservation Deep Dive

### How `_action_assign()` Works

Source: [`addons/stock/models/stock_move.py:1888`](../addons/stock/models/stock_move.py#L1888)

For each move:

1. Compute `missing_qty = product_uom_qty - already_reserved`.
2. If `procure_method = make_to_order` and no upstream move → skip (no stock to reserve).
3. If `move_orig_ids` exists (chained): look at what upstream move lines delivered to the intermediate location and reserve from there.
4. Otherwise: call `_update_reserved_quantity(need, location_id)` on `stock.quant`.
   - Quant selects available units respecting removal strategy (FIFO/FEFO/LIFO).
   - `reserved_quantity` incremented on the quant.
   - Returns actual taken quantity.
5. Create `stock.move.line` records for each `(location, lot, package, owner)` combination.
6. Move state → `assigned` if fully reserved, `partially_available` if partial.

### Removal Strategy (Quant Selection)

**What it is:** When Odoo reserves stock for a delivery/transfer, it needs to decide **which specific quants** (which lot, which shelf, which package) to take from. The removal strategy is the rule that controls this picking order.

**When it fires:** During reservation (`_action_assign`). The chain is:

1. A picking is confirmed or the user clicks "Check Availability"
2. `stock.move._action_assign()` is called — [stock_move.py:1888](../addons/stock/models/stock_move.py#L1888)
3. For each move, it calls `_update_reserved_quantity()` — [stock_move.py:1975](../addons/stock/models/stock_move.py#L1975)
4. Which calls `stock.quant._get_reserve_quantity()` — [stock_quant.py:833](../addons/stock/models/stock_quant.py#L833)
5. Which calls `stock.quant._gather()` — [stock_quant.py:770](../addons/stock/models/stock_quant.py#L770)
6. **Inside `_gather()`**, the removal strategy is resolved and quants are sorted accordingly
7. `_get_reserve_quantity()` then walks the sorted quants one by one, reserving from each until the needed qty is fulfilled

**In plain terms:** "I need 25 units of Product X from WH/Stock. Which quants do I take first?" The removal strategy answers that question.

#### Where to set it (lookup priority)

Source: [`stock_quant.py:617–627`](../addons/stock/models/stock_quant.py#L617)

| Priority | Where | Field | UI label | Behavior |
|---|---|---|---|---|
| 1st (wins) | Product Category form | `removal_strategy_id` | "Force Removal Strategy" | Overrides everything. Applies regardless of which location stock is picked from. |
| 2nd | Location form (walks up parents) | `removal_strategy_id` | "Removal Strategy" | If product category has no strategy, Odoo checks the source location. If empty, checks the parent location, then grandparent, etc. |
| Default | — | — | — | If nothing is set anywhere: **FIFO** |

**Example:** Product category "Dairy" has FEFO set. Location WH/Stock has FIFO set. When reserving milk → **FEFO wins** (product category always takes priority).

#### Available strategies

Source: [`stock_quant.py:740–747`](../addons/stock/models/stock_quant.py#L740), [`stock_quant.py:770–790`](../addons/stock/models/stock_quant.py#L770)

**FIFO — First In First Out** (method: `fifo`, default)

Sorts by: `in_date ASC, id ASC`

Picks quants that **entered the location earliest**. `in_date` is stamped on the quant when stock physically arrives (receipt validation). If two quants arrived at the same time, the one with the lower database ID goes first.

**LIFO — Last In First Out** (method: `lifo`)

Sorts by: `in_date DESC, id DESC`

Opposite of FIFO — picks the **most recently arrived** quants first.

**FEFO — First Expiry First Out** (method: `fefo`)

Sorts by: `removal_date ASC, in_date ASC, id ASC`

Picks quants whose **removal date is soonest**. Requires the `product_expiry` module (Settings > Inventory > Traceability > Expiration Dates). Source: [`product_expiry/models/stock_quant.py:25–28`](../addons/product_expiry/models/stock_quant.py#L25)

Key dates on `stock.lot` (all auto-computed from `expiration_date` minus product template offsets):

| Field | UI label | What it means | Used by FEFO? |
|---|---|---|---|
| `expiration_date` | Expiration Date | Goods become dangerous / must not be consumed | No |
| `removal_date` | Removal Date | Goods should be pulled from shelves | **Yes — this is the sort key** |
| `use_date` | Best Before Date | Quality starts deteriorating (not dangerous) | No |
| `alert_date` | Alert Date | Triggers expiration alert activity | No |

Source: [`production_lot.py:12–20`](../addons/product_expiry/models/production_lot.py#L12)

Important: when `removal_date` passes (is in the past), `available_quantity` on the quant is forced to **0** — the lot becomes unreservable. Source: [`product_expiry/models/stock_quant.py:30–36`](../addons/product_expiry/models/stock_quant.py#L30)

**Closest Location** (method: `closest`)

Sorts by: `location_id.complete_name ASC` (Python sort, not SQL)

Picks quants from the sub-location whose **full path name comes first alphabetically** (e.g., `WH/Stock/Aisle-1/Shelf-A` before `WH/Stock/Aisle-2/Shelf-B`). This is a proxy for physical proximity — works if location naming reflects physical layout. Source: [`stock_quant.py:788–789`](../addons/stock/models/stock_quant.py#L788)

**Least Packages** (method: `least_packages`)

Uses an **A* search algorithm** to find the fewest packages that cover the needed quantity. Source: [`stock_quant.py:629–737`](../addons/stock/models/stock_quant.py#L629)

How it works:
1. Groups quants by `package_id`, calculates available qty per package
2. Unpackaged items are treated as individual units (qty=1 each)
3. Runs A* search: tries combinations of packages, uses heuristic `remaining_qty / largest_package_qty` to estimate remaining packages needed
4. Returns the combination that uses the fewest packages to fulfil the demand
5. If no packages exist, falls back to standard FIFO domain
6. Catches `MemoryError` gracefully if the search space is too large

Example: Need 50 units. Available packages: [48, 25, 25, 10]. Algorithm picks the 48-pack + one 25-pack (2 packages, 73 units) rather than 25+25+10 (3 packages, 60 units).

#### End-to-end walkthrough

Scenario: Warehouse stores cheese (tracked by lot). Product category "Dairy" has **FEFO** removal strategy.

| Lot | `in_date` | `removal_date` | Available qty |
|---|---|---|---|
| LOT-A | Jan 1 | Mar 15 | 20 |
| LOT-B | Jan 10 | Mar 5 | 15 |
| LOT-C | Feb 1 | Mar 25 | 30 |

Sale order confirmed for 25 units. Reservation runs:

1. `_action_assign()` called on the delivery move
2. `_gather()` resolves strategy → FEFO (from product category)
3. Quants sorted by `removal_date ASC`: LOT-B (Mar 5), LOT-A (Mar 15), LOT-C (Mar 25)
4. `_get_reserve_quantity()` walks the sorted list:
   - LOT-B: take all 15 → remaining need = 10
   - LOT-A: take 10 of 20 → remaining need = 0
5. Two `stock.move.line` records created (one per lot)
6. Move state → `assigned`

Result: LOT-B (expiring soonest) is fully consumed first. LOT-C is untouched.

If the strategy were **FIFO** instead: LOT-A (Jan 1, oldest) would be taken first (20 units), then LOT-B (5 units). Expiration dates would be ignored entirely — LOT-B might expire on the shelf.

### available_quantity vs virtual_available

| Field | Location | Meaning |
|---|---|---|
| `available_quantity` | `stock.quant` | On-hand minus reserved (current) |
| `qty_available` | `product.product` | Total on-hand across all internal locations |
| `free_qty` | `product.product` | `qty_available` minus all reserved |
| `virtual_available` | `product.product` | Forecasted: on-hand + incoming - outgoing |

---

## Delivery Status on Sale Order

Source: [`addons/sale_stock/models/sale_order.py:33`](../addons/sale_stock/models/sale_order.py#L33)

| `delivery_status` | Condition |
|---|---|
| `False` | No pickings or all cancelled |
| `pending` | Pickings exist, none done |
| `started` | At least one picking done, no line qty delivered yet |
| `partial` | At least one picking done, some `qty_delivered` > 0 |
| `full` | All pickings done or cancelled |

`qty_delivered` on each order line is computed from done outgoing `stock.move` records ([`sale_stock/models/sale_order_line.py:196`](../addons/sale_stock/models/sale_order_line.py#L196)).

---

## UI Entry Points

| Entry Point | Path | What It Does |
|---|---|---|
| Confirm button | SO form | Triggers `_action_confirm()`, creates pickings |
| Delivery smart button | SO form | Opens related `stock.picking` records |
| Check Availability | Picking form | Calls `action_assign()`, reserves stock |
| Unreserve | Picking form | Calls `do_unreserve()`, frees reserved stock |
| Validate | Picking form | Calls `button_validate()`, finalises transfer |
| Return | Picking form (done) | Creates reverse picking |
| Backorder | Wizard at validation | Creates new picking for remaining qty |
| Inventory menu | Inventory → Operations → Transfers | Lists all pickings by type |
| Inventory Overview | Inventory → Overview | Kanban by operation type |

---

## Configuration

| Setting | Location | Effect |
|---|---|---|
| `delivery_steps` (UI: "Outgoing Shipments") | Inventory → Config → Warehouses → Warehouse Configuration tab | Sets how many operations a delivery requires — **only visible when Storage Locations (`stock.group_adv_location`) is enabled** |
| `reception_steps` (UI: "Incoming Shipments") | Inventory → Config → Warehouses → Warehouse Configuration tab | Sets how many operations a receipt requires — **only visible when Storage Locations (`stock.group_adv_location`) is enabled** |
| `reservation_method` | Operation Type form | When stock gets reserved |
| `create_backorder` | Operation Type form | Whether leftover qty creates a new picking |
| `use_create_lots` | Operation Type form | Whether new lot numbers can be created |
| Multi-Locations | Settings → Inventory | Enables sub-locations within warehouses |
| Multi-Warehouses | Settings → Inventory | Enables multiple warehouses per company |

---

## Edge Cases & Gotchas

- **Negative stock:** By default Odoo allows it. There is no `allow_negative_stock` field on `stock.location`. Negative stock prevention is handled as a parameter in quant availability logic (`stock.quant`), not as a per-location config field. Source: [`stock_quant.py`](../addons/stock/models/stock_quant.py)
- **MTO + MTS hybrid:** `mts_else_mto` procure method first tries to take from stock; only triggers an order if stock is insufficient.
- **SO line qty decrease after confirmation:** For moves that are not yet done, Odoo automatically reduces the move quantity to match the new SO line quantity. This applies to both pick and delivery moves. Source: [`test_sale_stock.py:1092`](../addons/sale_stock/tests/test_sale_stock.py#L1092)
- **Cancelling a confirmed SO:** Calls `picking_ids.action_cancel()` for all non-done pickings and unreserves all stock. Source: [`sale_stock/models/sale_order.py:252`](../addons/sale_stock/models/sale_order.py#L252)
- **Changing delivery address on SO:** Odoo creates a chatter warning on open pickings but does NOT automatically update `partner_id` on them unless `update_delivery_shipping_partner` context is set. Source: [`sale_stock/models/sale_order.py:160`](../addons/sale_stock/models/sale_order.py#L160)
- **Picking state is computed:** `stock.picking.state` is computed from move states — you cannot write it directly.
- **Reservation priority:** When multiple pickings compete for the same stock, high-priority (urgent) pickings and those with earlier deadlines are reserved first. Sort order in `action_assign()`: `(-priority, not deadline, deadline, date, id)`. Source: [`stock_picking.py:1203`](../addons/stock/models/stock_picking.py#L1203)
- **Validated incoming moves trigger auto-assign:** After validating a receipt or internal transfer, `_trigger_assign()` runs to auto-reserve any waiting outgoing moves that now have sufficient stock. Source: [`stock_picking.py:1277`](../addons/stock/models/stock_picking.py#L1277)
- **Delivery date propagation:** `commitment_date` on SO propagates to `date_deadline` on stock moves. Source: [`sale_stock/models/sale_order.py:176`](../addons/sale_stock/models/sale_order.py#L176)
- **Check Availability never triggers pull rules:** `action_assign()` / `_action_assign()` only reserves stock that already exists at the source location. It does NOT trigger procurement or fire pull rules. Pull rules fire exclusively during `_action_confirm()` (when `procure_method` is `make_to_order` or `mts_else_mto`) or when `stock.rule.run()` is called directly by SO confirmation, scheduler, Replenish button, etc.
- **`Quantity Done` is never auto-filled by Check Availability:** Check Availability creates `stock.move.line` records with `quantity` (reserved). `qty_done` is only set when the user validates or when an immediate transfer dialog fills it. These are separate concerns — reservation ≠ done.
- **Custom fallback route: `mts_else_mto` belongs on the delivery rule, not the replenishment rule:** In a Stock → Customers (delivery) + Stock2 → Stock (replenishment) chain, set `procure_method=mts_else_mto` on the delivery rule. `_action_confirm()` checks `move.rule_id.procure_method` on the delivery move — the replenishment rule's `procure_method` is irrelevant at that stage. See [`stock_move.py:1554`](../addons/stock/models/stock_move.py#L1554).
- **Existing moves ignore newly assigned routes:** Assigning a route to a product or changing rule `procure_method` after a picking is already created has no effect on that picking's move. The move already has `rule_id` set. Only new SO confirmations will use the updated configuration.

---

## Related Docs

- [`INDEX.md`](INDEX.md)

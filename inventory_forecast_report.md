# Inventory Forecast Report

> **Module:** `stock` | **Path:** [`addons/stock/`](../addons/stock/)
> **Odoo Apps category:** Inventory

## What It Does

The Forecast Report shows — per product per warehouse — exactly how much stock will be available over time, why, and when. It matches every outgoing demand to a supply source (reserved stock, free stock, transit stock, or a pending receipt) and shows any unmet demand explicitly. It also shows a stepped line chart of the cumulative forecasted quantity over a rolling window. The report is the primary tool for planners to understand if and when they can fulfill demand.

---

## Dependencies

### Requires
| Module | Why |
|---|---|
| `stock` | `stock.move`, `stock.quant`, `stock.warehouse`, `stock.location` — all core data sources |
| `product` | `product.product` / `product.template` — the product records the report is built around |

### Optional Integrations
| Module | What it enables |
|---|---|
| `sale_stock` | Sale order lines appear as `document_out` source links in report lines |
| `purchase_stock` | Purchase order lines appear as `document_in` source links in report lines |
| `mrp` | Manufacturing orders appear as demand; components appear as outgoing |
| `stock_account` | No direct effect on forecast; valuation is separate |

---

## Architecture — Two Separate Data Sources

The Forecast Report is built from **two independent systems** that work in parallel:

| System | Model / File | What it powers |
|---|---|---|
| Reconciliation engine | [`stock_forecasted.py`](../addons/stock/report/stock_forecasted.py) | Header summary numbers + detail lines table |
| SQL view | [`report_stock_quantity.py`](../addons/stock/report/report_stock_quantity.py) | The line graph (stepped chart) |

Both are triggered when you open the report. They share the same warehouse context but are computed independently.

---

## Part 1 — Header Summary Numbers

### Where they come from

Header numbers are computed by [`_get_report_header()`](../addons/stock/report/stock_forecasted.py#L112) which reads fields computed on `product.product`.

All four quantity fields are computed together by [`_compute_quantities()`](../addons/stock/models/product.py#L151) → [`_compute_quantities_dict()`](../addons/stock/models/product.py#L163).

### The four numbers

| UI Label | Python Field | Formula | Source |
|---|---|---|---|
| On Hand | `qty_available` | `SUM(stock_quant.quantity)` for internal locations | [`product.py:246`](../addons/stock/models/product.py#L246) |
| Free To Use | `free_qty` | `qty_available − reserved_quantity − expired_unreserved_qty` | [`product.py:250`](../addons/stock/models/product.py#L250) |
| Incoming | `incoming_qty` | `SUM(stock_move.product_qty)` for moves inbound to warehouse, state IN `waiting/confirmed/assigned/partially_available` | [`product.py:251`](../addons/stock/models/product.py#L251) |
| Outgoing | `outgoing_qty` | `SUM(stock_move.product_qty)` for moves outbound from warehouse, same states | [`product.py:252`](../addons/stock/models/product.py#L252) |
| Forecasted Quantity | `virtual_available` | `qty_available + incoming_qty − outgoing_qty − expired_unreserved_qty` | [`product.py:253`](../addons/stock/models/product.py#L253) |

### Exact query logic

`_compute_quantities_dict()` fires **three `_read_group` queries** per call:

1. **Quants query** — groups `stock.quant` by `product_id`, sums `quantity` and `reserved_quantity`. Only reads quants in the location domain (internal locations under the warehouse).
2. **Moves-in query** — groups `stock.move` by `product_id`, sums `product_qty`. Filter: state IN `(waiting, confirmed, assigned, partially_available)` AND destination inside warehouse.
3. **Moves-out query** — same as moves-in but source inside warehouse, destination outside.

Draft moves (`state='draft'`) are **excluded** from all four fields. They are shown separately in the header as **Draft Quantities** via [`_move_draft_domain()`](../addons/stock/report/stock_forecasted.py#L49) → [`_get_report_header()`](../addons/stock/report/stock_forecasted.py#L136-141).

### Historical / date-range mode

When `to_date` context is set to a past date, `_compute_quantities_dict()` switches to a **reverse calculation**:
- Starts from current quant quantities
- Subtracts moves done after `to_date` (incoming)
- Adds moves done after `to_date` (outgoing)
- This reconstructs what the stock looked like at that past date

Source: [`product.py:213-223`](../addons/stock/models/product.py#L213)

---

## Part 2 — The Stepped Line Graph

### Model

[`report.stock.quantity`](../addons/stock/report/report_stock_quantity.py#L7) — a **PostgreSQL VIEW** (not a stored table). Recreated on `init()` every time the module updates.

### What it stores

Each row represents one product × one warehouse × one day × one state:

| `state` | Meaning | `product_qty` sign |
|---|---|---|
| `forecast` | Running cumulative stock level for that day | positive = stock present |
| `in` | Expected receipts scheduled on that day | positive |
| `out` | Expected deliveries scheduled on that day | negative |

### How the view is built (SQL logic)

The `init()` SQL creates the view in three `UNION ALL` parts: [source: `report_stock_quantity.py:50-182`](../addons/stock/report/report_stock_quantity.py#L50)

**Part A — `state='out'` / `state='in'` rows (pending moves):**
- Reads all `stock.move` where `state NOT IN ('draft', 'cancel')` and `product_qty != 0`
- Determines source warehouse (`whs_id`) and destination warehouse (`whd_id`) via `parent_path` lookup on `stock_location`
- A move with `whs_id` set and `whd_id=NULL` → `state='out'`, `product_qty = -product_qty`
- A move with `whd_id` set and `whs_id=NULL` → `state='in'`, `product_qty = +product_qty`
- Inter-warehouse moves (both whs and whd set) are **duplicated** via `GENERATE_SERIES(0,1)`: one out-row for source warehouse, one in-row for destination warehouse
- Only non-done moves appear here

**Part B — `state='forecast'` rows from quants (current stock base):**
- For every quant in an internal or transit location, generates **one row per day** over the report window (`today - period` to `today + period`)
- Each row carries `q.quantity` (the current physical quantity) as the base level for every day
- Source: [`report_stock_quantity.py:130-150`](../addons/stock/report/report_stock_quantity.py#L130)

**Part C — `state='forecast'` rows from moves (adjustments over time):**
- For every move (done or pending), generates rows that **adjust the forecast** for a date range:
  - Done moves: generate rows from `today - period` up to `move.date - 1 day`. Sign is reversed (a done outgoing move means the goods have left, so the base is *higher* before that date).
  - Pending moves: generate rows from `GREATEST(move.date, today - period)` to `today + period`. Sign mirrors the movement direction.
- Source: [`report_stock_quantity.py:151-180`](../addons/stock/report/report_stock_quantity.py#L151)

The final `GROUP BY` sums all `product_qty` per `(product_id, state, date, company_id, warehouse_id)` to produce the net daily values.

### Report period setting

Controlled by system parameter `stock.report_stock_quantity_period` (default: `3` months).
Read at view creation time: [`report_stock_quantity.py:184`](../addons/stock/report/report_stock_quantity.py#L184).
Change requires re-running `init()` (module upgrade or manual recreate).

### Graph rendering

[`StockForecastedGraphRenderer`](../addons/stock/static/src/stock_forecasted/forecasted_graph.js#L5) extends the standard `GraphRenderer`:
- Forces `stepped: true` on all datasets → flat horizontal lines between events
- Removes intermediate data points where the value did not change (`null` = span gaps) to keep the chart clean
- Domain used: `[["state", "=", "forecast"], ["warehouse_id", "=", warehouseId], [product filter]]`

---

## Part 3 — Detail Lines Table

### Purpose

Every outgoing demand is reconciled against available supply and rendered as one or more table rows. The table shows **where the stock for each delivery will come from** — or flags it as unavailable.

### Move selection and ordering

Source: [`_get_report_lines()`](../addons/stock/report/stock_forecasted.py#L239)

```
Outgoing moves (outs):
  1. Past outs  (reservation_date <= today) → order: priority desc, date, id
  2. Future outs (reservation_date > today OR reservation_date IS NULL) → order: reservation_date, priority desc, date, id
  Combined: past_outs | future_outs  (past outs have priority over future outs)

Incoming moves (ins):
  order: priority desc, date, id
```

Only moves in states `waiting`, `confirmed`, `partially_available`, `assigned` are included. `draft` and `cancel` are excluded.

### What `reservation_date` is

`reservation_date` is a stored computed field on `stock.move`: [`stock_move.py:193`](../addons/stock/models/stock_move.py#L193)

| `reservation_method` on picking type | `reservation_date` value |
|---|---|
| `by_date` | `move.date - reservation_days_before` (or `reservation_days_before_priority` for urgent moves) |
| `manual` | `False` (null) |
| `at_confirm` | Set to today when the move is confirmed |

Moves without a `reservation_date` are treated as future and sorted last. This means **urgent/priority moves are satisfied first** in the forecast reconciliation.

### Reconciliation algorithm — 5 passes per out move

For each outgoing move, demand is satisfied in this exact order:

#### Pass 1 — Reserved stock
- Checks linked pick/pack moves (via `_rollup_move_origs()`) for state `partially_available` or `assigned`
- Reads `move.quantity` (reserved qty) on those linked moves
- Subtracts already-counted reservations (`used_reserved_moves` dict prevents double-counting when multiple outs share the same pick/pack)
- Deducts from `currents` (current stock dict keyed by `(product_id, location_id)`)
- Source: [`stock_forecasted.py:241-268`](../addons/stock/report/stock_forecasted.py#L241)

**Produces line type:** On-Hand (reserved) — `document_out` set, no `document_in`, `replenishment_filled=True`, `in_transit=True` if the reserved move has upstream `move_orig_ids`

#### Pass 2 — Free current stock
- From unreserved demand remaining after Pass 1
- Checks `currents[(product_id, location_id)]` for available non-reserved stock at the source location
- Handles chained moves: if the source move has `move_orig_ids`, uses qty delivered by those origs minus qty already consumed by sibling moves
- Deducts taken quantity from `currents`
- Source: [`stock_forecasted.py:270-303`](../addons/stock/report/stock_forecasted.py#L270)

**Produces line type:** On-Hand (free) — `document_out` set, no `document_in`, `replenishment_filled=True`, `in_transit=False`

#### Pass 3 — Transit stock
- Stock that is inside the warehouse total but not at the correct sub-location to be reserved from
- `transit_stock = product_sum[product_id] - free_stock` where `product_sum` sums all warehouse locations except sub-locations of the main stock location
- `unreservable_qty = min(demand_out, transit_stock)`
- Source: [`stock_forecasted.py:449-452`](../addons/stock/report/stock_forecasted.py#L449)

**Produces line type:** In-Transit — `document_out` set, no `document_in`, `replenishment_filled=True`, `in_transit=True`

#### Pass 4 — Incoming moves (procurement-linked first, then any)
- First: tries `dest_ids_to_in_ids[out.id]` — incoming moves that are directly linked to this out via procurement chain (`_rollup_move_dests`)
- Second: if still demand remaining, tries any available `ins_per_product[product_id]`
- Splits incoming move qty across multiple outs if needed (`taken_from_in = min(demand, in_data['qty'])`)
- Source: [`stock_forecasted.py:306-328`](../addons/stock/report/stock_forecasted.py#L306) (`_reconcile_out_with_ins`)

**Produces line type:** Reconciled — both `document_in` and `document_out` set, `replenishment_filled=True`

#### Pass 5 — Unreconciled (not available)
- Any remaining demand after Passes 1-4 that could not be satisfied
- Source: [`stock_forecasted.py:467-469`](../addons/stock/report/stock_forecasted.py#L467)

**Produces line type:** Not Available — `document_out` set, no `document_in`, `replenishment_filled=False`

### After all outs are processed — remaining items

**Free Stock line:** remaining `currents[product_id, wh_stock_location_id]` not allocated to any out.
- Shows if line `quantity == 0` only when there are no other lines for the product
- Source: [`stock_forecasted.py:474-476`](../addons/stock/report/stock_forecasted.py#L474)

**Unused Incoming lines:** incoming moves with remaining `qty > 0` not matched to any out.
- Source: [`stock_forecasted.py:479-483`](../addons/stock/report/stock_forecasted.py#L479)

### Line type summary

| Condition | `document_in` | `document_out` | `in_transit` | `replenishment_filled` | Display meaning |
|---|---|---|---|---|---|
| On-Hand (reserved from pick/pack) | No | Yes | No | Yes | Stock already reserved for this delivery |
| On-Hand (reserved, in transit to slot) | No | Yes | Yes | Yes | Reserved but physically at wrong sub-location |
| On-Hand (from free stock) | No | Yes | No | Yes | Will be taken from available stock |
| In-Transit (unreservable) | No | Yes | Yes | Yes | Stock in warehouse but wrong location, cannot reserve yet |
| Reconciled (matched to receipt) | Yes | Yes | No | Yes | Delivery matched to an incoming shipment |
| Free Stock (no demand) | No | No | No | Yes | Available stock with no demand assigned |
| Unused Incoming | Yes | No | — | — | Receipt not matched to any demand |
| Not Available | No | Yes | No | No | Demand exists but no supply found |

Source: [`forecasted_details.js:47-61`](../addons/stock/static/src/stock_forecasted/forecasted_details.js#L47)

### `_rollup_move_origs` and `_rollup_move_dests`

These are recursive traversals of the move chain: [`stock_move.py:2484-2514`](../addons/stock/models/stock_move.py#L2484)

- `_rollup_move_origs()` — walks backward through `move_orig_ids` chain. Returns all upstream move IDs.
- `_rollup_move_dests()` — walks forward through `move_dest_ids` chain. Returns all downstream move IDs.
- Both use `seen` set to prevent infinite loops in cyclic chains.
- Cache is prewarmed before the reconciliation loop via `_rollup_move_origs_fetch()` and `_rollup_move_dests_fetch()`.

These are critical for 3-step routes where a delivery (OUT) is linked to a PACK move linked to a PICK move. The reconciliation looks up all the way to the PICK to find reservations.

### `location_final_id` and multi-step routes

`location_final_id` on `stock.move` is the **actual final destination** in a multi-step route, as opposed to `location_dest_id` which may be an intermediate stop.

In `_move_domain()`, the out-domain uses:
```python
'|',
('location_dest_id', 'not in', wh_location_ids),
'&',
('location_final_id', '!=', False),
('location_final_id', 'not in', wh_location_ids),
```
This correctly identifies a move as "leaving the warehouse" even if its current intermediate destination is still inside the warehouse. Source: [`stock_forecasted.py:36-41`](../addons/stock/report/stock_forecasted.py#L36)

---

## Part 4 — `forecast_availability` Widget (in Picking Form)

This is a separate, inline forecast shown per operation line on a picking, not part of the Forecast Report page itself.

### Field definition

`stock.move.forecast_availability` — computed, not stored, `compute_sudo=True`. Source: [`stock_move.py:190`](../addons/stock/models/stock_move.py#L190)

Computed by [`_compute_forecast_information()`](../addons/stock/models/stock_move.py#L502).

### Computation logic per state

| Move state | `forecast_availability` value | Logic |
|---|---|---|
| `assigned` | `move.quantity` (reserved qty in product UoM) | Already fully reserved — use what's reserved |
| `draft`, `free_qty >= demand` | `free_qty` | Enough free stock right now |
| `draft`, consuming, insufficient | `virtual_available - product_qty` | Net forecast after subtracting this move's demand |
| `waiting/confirmed/partially_available`, outgoing | Result of `_get_forecast_availability_outgoing()` | Queries `report.stock.quantity` view |
| `incoming` (receipt) | `virtual_available + product_qty` (if draft) | Adding this receipt improves the forecast |
| Internal move, enough `free_qty` | `free_qty` | Sufficient stock at source location |

For unreserved outgoing moves, [`_get_forecast_availability_outgoing()`](../addons/stock/models/stock_move.py#L2516) queries the `report.stock.quantity` view to find the **first date** when the running cumulative forecast reaches the required quantity. That date becomes `forecast_expected_date`.

### Widget colors

[`forecast_widget.js`](../addons/stock/static/src/widgets/forecast_widget.js)

| Color | Class | Condition | Meaning |
|---|---|---|---|
| Green | `text-bg-success` | `forecast_availability >= product_qty` AND no `forecast_expected_date` | Stock available now from current inventory |
| Yellow | `text-bg-warning` | `forecast_availability >= product_qty` AND `forecast_expected_date <= date_deadline` | Will be covered by a future receipt, on time |
| Red | `text-bg-danger` | `forecast_availability < product_qty` OR `forecast_expected_date > date_deadline` | Cannot fulfill, or will be late |

The widget appears in the picking form on `stock.move` lines: [`stock_picking_views.xml:288`](../addons/stock/views/stock_picking_views.xml#L288).
Clicking the widget opens the full Forecast Report for that product.

---

## Part 5 — Lead Time Display

Shown in the report header. Computed by [`_get_product_leadtime()`](../addons/stock/report/stock_forecasted.py#L98):

1. Gets the warehouse stock location from context
2. Calls `product._get_rules_from_location(location)` to find applicable procurement rules
3. Calls `rule._get_lead_days(product)` which sums all delays across the rule chain
4. Returns `total_delay` (days) and `details` (breakdown per rule)

Frontend (`ForecastedHeader.leadTime`) picks the product with the **lowest** total delay if multiple variants are shown, and computes "Earliest Possible Arrival" as `today + total_delay`. Source: [`forecasted_header.js:30-48`](../addons/stock/static/src/stock_forecasted/forecasted_header.js#L30)

---

## Part 6 — Warehouse Filter and Context

The OWL component [`StockForecasted`](../addons/stock/static/src/stock_forecasted/stock_forecasted.js#L14) loads all active warehouses on startup and adds a warehouse switcher to the control panel.

- On switch: calls `updateWarehouse(id)` → `reloadReport()` which dispatches a new `ir.actions.client` action with the new `warehouse_id` in context (replaces the current action on the breadcrumb stack)
- Backend uses `warehouse_id` from context in [`_get_warehouse()`](../addons/stock/report/stock_forecasted.py#L153) — falls back to first active warehouse if not set
- All location domains are derived from `warehouse.view_location_id` (includes all child locations)
- The "free stock" location is `warehouse.lot_stock_id` specifically

Source: [`stock_forecasted.js:87-105`](../addons/stock/static/src/stock_forecasted/stock_forecasted.js#L87)

---

## Key Models

### `stock.forecasted_product_product` — reconciliation engine
> [`addons/stock/report/stock_forecasted.py`](../addons/stock/report/stock_forecasted.py)

Abstract model. No stored fields. All computation is on-demand per `get_report_values()` call.

### `stock.forecasted_product_template` — template variant
> [`addons/stock/report/stock_forecasted.py:506`](../addons/stock/report/stock_forecasted.py#L506)

Inherits from `stock.forecasted_product_product`. Overrides `get_report_values()` to pass `product_template_ids` instead of `product_ids`.

### `report.stock.quantity` — graph data view
> [`addons/stock/report/report_stock_quantity.py`](../addons/stock/report/report_stock_quantity.py)

`_auto = False` (PostgreSQL VIEW). Never written directly. Rebuilt on module init.
Fields: `date`, `product_id`, `product_tmpl_id`, `state` (`forecast`/`in`/`out`), `product_qty`, `company_id`, `warehouse_id`.

---

## Key Methods

| Method | File:Line | Purpose |
|---|---|---|
| `get_report_values()` | [`stock_forecasted.py:16`](../addons/stock/report/stock_forecasted.py#L16) | Entry point — called by OWL component, returns all data for the report |
| `_get_report_data()` | [`stock_forecasted.py:156`](../addons/stock/report/stock_forecasted.py#L156) | Orchestrates header + lines |
| `_get_report_header()` | [`stock_forecasted.py:112`](../addons/stock/report/stock_forecasted.py#L112) | Builds header: product quantities, draft qty, lead time |
| `_get_report_lines()` | [`stock_forecasted.py:239`](../addons/stock/report/stock_forecasted.py#L239) | Core reconciliation — matches outs to supply |
| `_reconcile_out_with_ins()` | [`stock_forecasted.py:306`](../addons/stock/report/stock_forecasted.py#L306) | Inner loop: matches one out to available ins |
| `_prepare_report_line()` | [`stock_forecasted.py:174`](../addons/stock/report/stock_forecasted.py#L174) | Builds a single display line dict with all flags |
| `_move_domain()` | [`stock_forecasted.py:30`](../addons/stock/report/stock_forecasted.py#L30) | Builds in/out domain accounting for `location_final_id` |
| `_move_confirmed_domain()` | [`stock_forecasted.py:55`](../addons/stock/report/stock_forecasted.py#L55) | Adds state filter for confirmed/waiting/assigned/partially_available |
| `_move_draft_domain()` | [`stock_forecasted.py:49`](../addons/stock/report/stock_forecasted.py#L49) | Adds state filter for draft moves only (header only) |
| `_get_warehouse()` | [`stock_forecasted.py:153`](../addons/stock/report/stock_forecasted.py#L153) | Reads warehouse from context, falls back to first active |
| `_get_product_leadtime()` | [`stock_forecasted.py:98`](../addons/stock/report/stock_forecasted.py#L98) | Resolves procurement rule chain and sums delays |
| `action_reserve_linked_picks()` | [`stock_forecasted.py:490`](../addons/stock/report/stock_forecasted.py#L490) | Reserves stock for a move's upstream picks — called from Reserve button |
| `action_unreserve_linked_picks()` | [`stock_forecasted.py:497`](../addons/stock/report/stock_forecasted.py#L497) | Unreserves upstream picks — called from Unreserve button |
| `_compute_quantities_dict()` | [`product.py:163`](../addons/stock/models/product.py#L163) | Computes all 5 quantity fields with 3 DB queries |
| `_compute_forecast_information()` | [`stock_move.py:502`](../addons/stock/models/stock_move.py#L502) | Computes `forecast_availability` and `forecast_expected_date` per move |
| `_get_forecast_availability_outgoing()` | [`stock_move.py:2516`](../addons/stock/models/stock_move.py#L2516) | Queries `report.stock.quantity` view to find when outgoing demand will be met |
| `_compute_reservation_date()` | [`stock_move.py:645`](../addons/stock/models/stock_move.py#L645) | Computes when a move should start reserving based on picking type method |
| `_rollup_move_origs()` | [`stock_move.py:2497`](../addons/stock/models/stock_move.py#L2497) | Recursively walks upstream move chain |
| `_rollup_move_dests()` | [`stock_move.py:2494`](../addons/stock/models/stock_move.py#L2494) | Recursively walks downstream move chain |
| `report.stock.quantity.init()` | [`report_stock_quantity.py:36`](../addons/stock/report/report_stock_quantity.py#L36) | Recreates the PostgreSQL VIEW on module install/upgrade |

---

## UI Entry Points

| Entry Point | Path in UI | What It Does |
|---|---|---|
| Forecasted Qty stat button | Product Template form → smart button | Opens full Forecast Report via `action_product_tmpl_forecast_report` |
| Forecasted Qty stat button | Product Variant form → smart button | Opens full Forecast Report via `action_product_forecast_report` |
| Forecast widget column | Inventory → Transfers → Operation lines | Shows `forecast_availability` colored badge per move line; click opens report |
| Replenish button | Forecast Report header | Opens `product.replenish` wizard pre-filled with warehouse context |
| Update Quantity button | Forecast Report header | Opens `stock.quant` in inventory mode for manual adjustments |
| Reserve / Unreserve | Forecast Report detail lines | Calls `action_reserve_linked_picks` / `action_unreserve_linked_picks` on linked picks |
| Warehouse switcher | Forecast Report control panel | Reloads report for the selected warehouse |

Actions defined in [`addons/stock/views/stock_forecasted.xml`](../addons/stock/views/stock_forecasted.xml):
- `stock_forecasted_product_product_action` — tag: `stock_forecasted`, res_model: `product.product`
- `stock_forecasted_product_template_action` — tag: `stock_forecasted`, res_model: `product.template`

---

## Configuration

| Setting | Location | Effect |
|---|---|---|
| `stock.report_stock_quantity_period` | Technical → System Parameters | Number of months the graph covers before and after today (default: `3`). Change requires module upgrade to rebuild the view. |
| `reservation_method` on picking type | Inventory → Configuration → Operations Types → Reservation field | Controls how `reservation_date` is computed per move (`at_confirm`, `by_date`, `manual`) |
| `reservation_days_before` | Picking type form | Days before scheduled date to start reserving (used when `reservation_method='by_date'`) |
| `reservation_days_before_priority` | Picking type form | Same but for urgent moves (priority = `1`) |
| `stock.group_stock_user` security group | — | Controls visibility of Reserve/Unreserve buttons. `user_can_edit_pickings` flag in report data. Source: [`stock_forecasted.py:171`](../addons/stock/report/stock_forecasted.py#L171) |

---

## Edge Cases & Gotchas

- **Draft moves are NOT in the 4 header numbers.** They appear separately in the header as "Draft Quantities". Draft moves are NOT reconciled in the detail lines at all. Only states `waiting`, `confirmed`, `assigned`, `partially_available` count.

- **`virtual_available` ≠ graph forecast.** The header's Forecasted Quantity (`virtual_available`) is a simple formula computed from current quants and pending moves. The graph's `forecast` state in `report.stock.quantity` is a daily cumulative sum built by the SQL view and includes done moves in the historical window. They can differ momentarily due to caching or timing.

- **`reservation_date` controls priority, not scheduling.** Past-reservation-date outs are sorted and processed FIRST in reconciliation, meaning their demand is satisfied before future-dated outs. This is how urgent moves "jump the queue."

- **Multi-step routes and `location_final_id`.** In a 3-step delivery (PICK → PACK → OUT), the OUT move's `location_dest_id` is the customer location and `location_final_id` is also the customer. But the PACK move's `location_dest_id` is Output and `location_final_id` is customer. The forecast uses `location_final_id` to determine if the PACK move is an outgoing warehouse move.

- **Sub-location quantities bubble up.** If stock is in `WH/Stock/Shelf-A` (a sub-location of `WH/Stock`), `currents[product_id, WH/Stock]` is incremented too. This ensures sub-location stock is visible at the main stock level. Source: [`stock_forecasted.py:390-399`](../addons/stock/report/stock_forecasted.py#L390)

- **Same pick/pack for multiple outs.** `used_reserved_moves` dict prevents double-counting reservations when two OUT moves share the same PICK or PACK move. Each reservation is counted at most once across all outs. Source: [`stock_forecasted.py:403`](../addons/stock/report/stock_forecasted.py#L403)

- **Interwarehouse transfers in the graph.** The SQL view duplicates interwarehouse moves (`GENERATE_SERIES(0,1)`) to produce both an OUT row for the source warehouse and an IN row for the destination. This ensures each warehouse's forecast is self-contained.

- **`forecast_availability` is not stored.** Computed on every read, not cached in DB. Loading a picking with many lines triggers `_compute_forecast_information()` for all lines, which queries `report.stock.quantity`. This is `compute_sudo=True` — access control is bypassed.

- **Expiry-aware mode.** If `with_expiration` context key is set, `_compute_quantities_dict()` additionally subtracts expired-but-unreserved quants from `free_qty` and `virtual_available`. Source: [`product.py:207-210`](../addons/stock/models/product.py#L207)

- **Forecast graph is a VIEW, not live data.** The `report.stock.quantity` view is a static SQL VIEW — it always reflects the current state of `stock_move` and `stock_quant` tables at query time. It is NOT precomputed or cached. However it is also NOT refreshed by triggers — the view definition is fixed until next module upgrade.

---

## Related Docs

- [`INDEX.md`](INDEX.md)
- [`inventory.md`](inventory.md) — core inventory: moves, quants, routes, reservations, multi-step

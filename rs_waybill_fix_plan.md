# rs_waybill — Corrections Fix Plan (Odoo 20)

> **Date:** 2026-09-25 · **Scope:** `rs_waybill` only, plus one hook in `rs_base_methods`. E-invoice and invoice-wizard items (#11, #29, #34–#36, #42, #45, #59–#61) stay in [`rs_waybill_einvoice_fix_plan.md`](rs_waybill_einvoice_fix_plan.md); its waybill items are re-verified and superseded here ([mapping](#5-old-numbers--new-numbers)).
> **Evidence:** 31 scenarios and 6 fix prototypes run against the real module code on a throwaway Odoo 20 database (`gec20_scenario_waybill`, rs.ge faked in memory, dropped afterwards) — [log](#6-scenario-log). Tags: **[S#]** reproduced in scenario # · **[F#]** fix mechanism proven · **[C]** read in code, not run · **[D]** decision needed.
> **gec20_prod1 today:** 0 of 2,001 waybills are linked to a delivery or receipt, no operation type has "Create RS Waybill", the stock-integration date is empty. None of this has touched its data. Fix before switching the integration on.

Every correction path except "remove a line before dispatch" (S29) fails in at least one realistic variant. The forward flow (SO → delivery → waybill → validate, S0) works.

---

## 1. How corrections must work — 7 rules

Each issue in section 2 breaks one of these rules. They follow core Odoo's correction toolbox ([`stock_transfers_corrections.md`](stock_transfers_corrections.md#which-correction-to-use)) and RS semantics: a waybill documents one physical transport, and type 5 is a separate reverse transport ([`waybill_api.md` §2.2](../waybill_api.md), [`RS_WAYBILL_RULES.md` §2, §9](../RS_WAYBILL_RULES.md)).

| Rule | Statement | Core mechanism |
|---|---|---|
| **R1** | A delivery linked to an RS waybill carries exactly what the waybill declares: demand = reserved = declared. Save splits the unreserved rest into a backorder; validation (button or RS close) runs only when shipped = declared. | Split [`action_split_transfer()`](../addons/stock/models/stock_picking.py#L1247) |
| **R2** | Before dispatch, an Edit is an order change: the waybill line, its move and its SO line change by the same delta. SO writes never re-procure. | `skip_procurement` [`sale_order_line.py:381`](../addons/sale_stock/models/sale_order_line.py#L381) |
| **R3** | After dispatch, an Edit corrects the same shipment: the done move is changed in place; an omitted product becomes a done move on the same delivery. A decrease asks one question: ship the missing quantity later, or reduce the order. | `move.quantity` inverse [`_set_quantity()`](../addons/stock/models/stock_move.py#L465); move on a done picking is done at once [`stock_move.py:855`](../addons/stock/models/stock_move.py#L855); SO line linked like [`_action_synch_order()`](../addons/sale_stock/models/stock.py#L93) |
| **R4** | A physical return is never an Edit. Return on the delivery → type-5 return waybill; the original waybill stays as issued. | [`_create_return()`](../addons/stock/models/stock_picking.py#L976) |
| **R5** | Cancel voids the RS document only. An open delivery stays and gets a new waybill. A completed waybill is not cancelled. | — |
| **R6** | RS-side changes (sync, Update, drift) run the same R2/R3 code as a target state (waybill vs delivery), one savepoint per waybill. What fails or needs a decision is flagged and retried. | The module's own buyer pattern [`_compute_buyer_goods_delta()`](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1614) |
| **R7** | Buyer side mirrors R3: Receive = accept the vendor's corrected quantities on the same receipt, after the RS confirm. Only a vendor type-5 waybill sends goods back. | `move.quantity`, then the PO line: no new receipt when `product_qty ≤ qty_received` [`purchase_order_line.py:218`](../addons/purchase_stock/models/purchase_order_line.py#L218) |

### Event → action

| # | Event | Odoo (target) | RS | Today |
|---|---|---|---|---|
| 1 | Before dispatch, customer changes a quantity | Edit: move demand and SO line ± Δ | Edit | S1: the other open delivery drops 6 → 1, SO 10 → 5 · S31: partial delivery shrinks the order 10 → 9 |
| 2 | Before dispatch, product added / removed / replaced | Edit: new move + SO line · move cancelled + SO − qty · both | Edit | S18: the second edit of an added line doubles demand (10 vs 5) · S29: remove OK |
| 3 | Only part of the order is in stock | Save splits: delivery = reserved; backorder gets its own waybill | two waybills | S9: ships 10, RS 8 · S10: RS 12 + backorder waybill 2 · S30: RS 8 + backorder waybill 3 |
| 4 | After dispatch, more left than recorded | Edit: done move `quantity = new`, SO + Δ | Edit | S2: blocked · S27: from RS half applied (delivered 11 / ordered 10) · S19: serial number with quantity 2 |
| 5 | After dispatch, a product left undocumented | Edit: done move on the same delivery + SO line | Edit | S3: the new move lands in the open backorder and validates it · S4: 8 shipped for 5 |
| 6 | After dispatch, fewer left (short-ship) | Edit: done move `quantity = new` (stock back at once), then "later / reduce" | Edit | S22: phantom return waits for a warehouse user; SO 10 / 8 shows "Fully Delivered" · S6: closing the popup loses it |
| 7 | Customer physically returns goods | Return on the delivery → type-5 waybill | new type 5; original unchanged | S7: Edit + "Goods returned" → RS net 6 for a real 8 · S11: synced type 5 leaves SO delivered at 10 |
| 8 | Shipment postponed / abandoned before dispatch | Cancel the waybill; delivery stays; new waybill later | `ref_waybill` | S16: delivery cancelled, SO stranded and locked · S15: RS-side cancel → delivery can never ship |
| 9 | Completed shipment recorded by mistake | [D] RS rules forbid cancelling completed → Edit to the real quantity | Edit | S8: Cancel allowed; + "Goods returned" → RS net −5 · S24: RS-side cancel is silent |
| 10 | Seller edits on the RS portal | Same as 1–6, through the sync | — | S23: decrease parked, stock wrong until someone clicks · S14: rename + quantity → second SO line and second delivery |
| 11 | Vendor corrects after we received | Receive: done receipt corrected in place, then the PO | `confirm_waybill` | S12: outgoing "return" validated automatically, no links |
| 12 | Vendor adds a product | Receive: PO line at the waybill price, receipt validated at picking level | `confirm_waybill` | S32: PO price = cost 5 (waybill 25), receipt without `date_done` |

---

## 2. Issues and fixes

Paths: `rs_waybill.py` = [`models/rs_waybill.py`](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py), `actions` = [`models/rs_waybill_actions.py`](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill_actions.py), `picking` = [`models/stock_picking.py`](../custom_addons/gec_odoo_modules/rs_waybill/models/stock_picking.py), `sync` = [`models/rs_waybill_sync.py`](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill_sync.py).

### Phase 0 — Odoo 20 break

#### W1. Split Transfer crashes on every picking — new, P1 [F3]
- **Repro.** Any delivery with a partial reservation → **Split** → `TypeError: StockPicking._create_backorder() got an unexpected keyword argument 'from_manual_backorder'`.
- **Cause.** v20 added `from_manual_backorder` to [`_create_backorder()`](../addons/stock/models/stock_picking.py#L1397), passed by [`action_split_transfer()`](../addons/stock/models/stock_picking.py#L1260). The override at [`picking:551`](../custom_addons/gec_odoo_modules/rs_waybill/models/stock_picking.py#L551) keeps the v19 signature. With enterprise `quality_control` (not installed on prod1) every backorder would likely break too, because it passes the flag positionally ([`quality_control/stock_picking.py:98`](../enterprise/quality_control/models/stock_picking.py#L98)) — read from the signatures, not run.
- **Fix.**
  ```python
  def _create_backorder(self, backorder_moves=None, from_manual_backorder=False):
      backorders = super()._create_backorder(backorder_moves=backorder_moves,
                                             from_manual_backorder=from_manual_backorder)
  ```

### Phase 1 — Open delivery (R1, R2)

#### W2. One waybill line overwrites the whole SO line — #14, P1 [S1, S2, S27, S31, F6]
- **S1.** SO 10, stock 4 → D1 4 done. D2 6 open, waybill active. Edit W2 6 → 5 → RS **5**, D2 demand **1**, SO ordered **5**. Expected: D2 5, SO 9. Core absorbs the negative procurement into the open move ([`stock_move.py:1442`](../addons/stock/models/stock_move.py#L1442)).
- **S2.** Both deliveries done. Edit W1 4 → 5 → refused: "The ordered quantity of a sale order line cannot be decreased below the amount already delivered" ([`sale_order_line.py:416`](../addons/sale_stock/models/sale_order_line.py#L416)).
- **S27.** Same change made on RS, then Update → D1 **5 done**, SO ordered 10 / delivered **11**; the error only reaches the chatter; the second Update finds nothing to do.
- **S31.** SO 10, 8 reserved, waybill 8 active. One unit arrives, Edit 8 → 9 → demand 9, SO **9**: the customer's order lost a unit.
- **Cause.** `move.sale_line_id.product_uom_qty = d['new_qty']` at [`rs_waybill.py:1267`](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1267) and [`:1383`](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1383), with procurement on.
- **Fix** (both places; S31 also needs W3):
  ```python
  sol = move.sale_line_id.with_context(skip_procurement=True)
  sol.product_uom_qty += d['new_qty'] - d['old_qty']
  ```
- **Proof F6.** S1 with the fix → D2 5/5, SO 9, procurement quantity 9 (consistent).

#### W3. Waybill quantity and delivery demand drift apart — new + #54, P1 [S9, S10, S30, S31, F3]
- **S9.** SO 10, stock 8 → waybill 8 saved and activated. Stock +2, re-reserve → delivery 10/10, waybill 8. Validate → **10 shipped, RS completed at 8**, SO delivered 10, no warning.
- **S10.** Waybill 10 active, Edit 10 → 12 with 10 in stock → delivery 12/10. RS completes → delivery done 10 + backorder 2 **with its own new waybill 2** → RS declares 12 + 2.
- **S30.** Same through the Validate button (5 in stock, Edit 5 → 8) → RS 8 + backorder waybill 3.
- **Cause.** Waybill lines copy the reserved quantity ([`picking:266`](../custom_addons/gec_odoo_modules/rs_waybill/models/stock_picking.py#L266)) and stop following the picking once on RS ([`picking:307`](../custom_addons/gec_odoo_modules/rs_waybill/models/stock_picking.py#L307)). Neither [`_action_done()`](../custom_addons/gec_odoo_modules/rs_waybill/models/stock_picking.py#L563) nor [`_do_validate_linked_picking()`](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L2000) compares quantities.
- **Fix (R1).**
  1. [`action_save_to_rs()`](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill_actions.py#L106), before `save_waybill`: if an open move of the linked delivery has `quantity < product_uom_qty`, call `picking.action_split_transfer()` (needs W1). The backorder gets its waybill through the existing hook. Safe with reservation "At Confirmation" (both prod1 types); with "Manually", core unreserves the original after a split ([`stock_picking.py:1426`](../addons/stock/models/stock_picking.py#L1426)).
  2. One helper on `stock.picking`, `_rs_qty_mismatch()` → `{product: (declared, shipping)}`, move quantities converted to the product UoM.
  3. `_action_done()` pre-check for seller pickings whose waybill is on RS: mismatch → `UserError` naming product, waybill quantity and delivery quantity.
  4. `_do_validate_linked_picking()`: mismatch on an outgoing picking → do not validate; set `rs_post_commit_error`. The drift job retries once stock is reserved.
- **Proof F3.** SO 10, 8 reserved → split → delivery 8/8 = waybill 8; backorder 2 with its own waybill 2.

#### W4. An added line on an open delivery doubles on the next edit — new, P2 [S18, F2]
- **Repro.** Open delivery. Edit: add B 4 → correct. Edit B 4 → 5 → delivery **B 5 + B 5**, RS 5, SO 5.
- **Cause.** The added move is created outside procurement (no `rule_id`), so [`_get_qty_procurement()`](../addons/sale_stock/models/sale_order_line.py#L346) ignores it; the next SO write procures 5 again.
- **Fix.** W2: every module write to an SO line quantity uses `skip_procurement`. Nothing else.

### Phase 2 — Done delivery (R3, R4, R5)

#### W5. First move line overwritten; serial numbers get quantity 2 — #13, P1 [S13, S4, S19, F1]
- **S13.** Receipt demand 10 with lot lines 4 + 6 → `_force_validate_moves` → LA 10 + LB 6 = **16 received**.
- **S4.** Added product reserved on two shelves (2 + 3) → first line set to 5 → **8 shipped for 5**, on-hand −3.
- **S19.** Serial product delivered with SN1. Edit 1 → 2 → **SN1 with quantity 2**; quants SN1 Stock −1 / Customers 2.
- **Cause.** `move_line_ids[0].quantity = …` at [`rs_waybill.py:1366`](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1366), [`:1411`](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1411), [`:1854`](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1854).
- **Fix.** Core inverse `move.quantity = new_qty`: it spreads over lots and locations, reduces the last lines first and applies putaway. For a tracked product, raise when the result has a line without lot ("enter the lot/serial for the extra quantity").
- **Proof F1.** Done 10 on lots A 4 / B 6 → `quantity = 8` → A 4 / B 4, delivered 8. Untracked 10 → 12 → one line 12, delivered 12.

#### W6. A product added after dispatch hijacks the open backorder — new, P1 [S3, F2]
- **Repro.** SO 10 C, stock 4 → D1 4 done (W1); D2 6 open (draft W2). Edit W1: add X 3 →
  - X's move is assigned to **D2** (same order, partner, locations — [`stock_move.py:1599`](../addons/stock/models/stock_move.py#L1599)) and validated there;
  - D2 is **done, holding only X 3**; C 6 moves to a new D3 **with no waybill**; W2 (declares C 6) points to a done picking that holds X.
- **Cause.** [`rs_waybill.py:1386-1424`](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1386) creates the SO line with procurement on, then `_action_done()`s whatever move procurement produced.
- **Fix (R3).**
  ```python
  sol = self.env['sale.order.line'].with_context(skip_procurement=True).create({
      'order_id': so.id, 'product_id': line.product_id.id,
      'product_uom_qty': line.quantity, 'price_unit': line.unit_price})
  move = self.env['stock.move'].create({       # created on a done picking = done at once
      'product_id': line.product_id.id, 'product_uom_qty': line.quantity,
      'uom_id': line.product_id.uom_id.id, 'picking_id': picking.id,
      'location_id': picking.location_id.id, 'location_dest_id': picking.location_dest_id.id,
      'company_id': picking.company_id.id, 'sale_line_id': sol.id})
  move.quantity = line.quantity                # core inverse: reserves first, then posts stock
  line.stock_move_id = move
  ```
  Same picking = same waybill; no second picking, `date_done` kept, no move-level `_action_done` (#58 for this path).
- **Proof F2.** SO line delivered 2/2, one picking, `date_done` kept. That line's `_get_qty_procurement` is 0 (no rule), which is why W2's `skip_procurement` is required on later writes.

#### W7. Short-ship: stock stays wrong, the popup can be lost, the order is never decided — #18, #56, new, P1 [S6, S22, S23, F1]
- **S6.** Done 10, Edit 10 → 8, close the popup → `pending_return_json` empty, delivery 10, RS 8. Reconcile Delivery → "Nothing to reconcile".
- **S22.** "Short-ship — adjust Odoo only" → return picking **Ready**; stock is unchanged until a warehouse user validates a receipt of goods that never left. After it: SO ordered 10 / delivered 8, Delivery Status "full"; the next SO change re-procures 2 ([`sale_order_line.py:304`](../addons/sale_stock/models/sale_order_line.py#L304)).
- **S23.** Same decrease made on RS → delivery 10, on-hand 0 (truth 3) until someone clicks Reconcile.
- **Cause.** The quantities live only in the transient wizard ([`actions:299`](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill_actions.py#L299)); the correction is a return picking ([`rs_waybill.py:1438`](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1438)); nothing asks about the missing quantity.
- **Fix (R3).** In the done branch (manual and sync), set `move.quantity = new_qty` (removed line → 0; core allows 0 on a done move). Stock and SO delivered are right at once. Write `pending_return_json = {product: missing}` **before** returning the popup. The popup keeps two buttons with new meanings:
  - **Deliver later** → `self.env['stock.rule'].run(sol._create_procurements(missing, sol.product_uom_id, sol._prepare_procurement_values()))`. Pass the quantity explicitly: `_action_launch_stock_rule()` would re-count and miss the rule-less moves of W6.
  - **Reduce the order** → `sol.with_context(skip_procurement=True).product_uom_qty -= missing`.
  Both clear `pending_return_json`; Reconcile Delivery reopens the popup.

#### W8. "Goods returned — create return waybill" counts the return twice on RS — new, P1 [S7, S8]
- **S7.** Done 10, Edit 10 → 8, "Goods returned" → RS original **8** plus type-5 return **2** → RS net **6**. Real: 8 (SO delivered 8).
- **S8.** Cancel a completed waybill, "Goods returned" → RS original cancelled **and** type-5 for 5 → RS net **−5**.
- **Cause.** [`return_decision_wizard.py:22`](../custom_addons/gec_odoo_modules/rs_waybill/wizards/return_decision_wizard.py#L22) + [`rs_waybill.py:1438`](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1438): the original is changed and a reverse waybill is added for the same goods.
- **Fix (R4).** Delete this option from the Edit, Reconcile and Cancel paths. Physical returns use **Return** on the delivery; its receipt gets the type-5 waybill ([`picking:449`](../custom_addons/gec_odoo_modules/rs_waybill/models/stock_picking.py#L449), after W22). In v20 delivery returns use the Receipts operation type ([`stock_warehouse.py:367`](../addons/stock/models/stock_warehouse.py#L367)), so a type-5 waybill appears only when Receipts has "Create RS Waybill" on; W22 is then mandatory.

#### W9. Cancel on a completed waybill — #56, #21, P1 [S8, S24] [D]
- **S8.** Cancel → RS −2, waybill cancelled, delivery done, SO delivered 5. Popup closed → nothing pending.
- **S24.** RS-side cancel of a completed waybill → waybill cancelled, delivery done, no flag.
- **RS.** "Completed (2) can be edited, but never cancelled" ([`RS_WAYBILL_RULES.md` §9](../RS_WAYBILL_RULES.md)); `ref_waybill` "cancels an already-active waybill" ([`waybill_api.md` §6.7](../waybill_api.md)). The button shows for completed waybills ([`rs_waybill_views.xml:87`](../custom_addons/gec_odoo_modules/rs_waybill/views/rs_waybill_views.xml#L87)); the code sends `ref_waybill` on status 2 ([`rs_waybill.py:1513`](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1513)).
- **Fix.** [D] Test `ref_waybill` on a status-2 waybill with the RS test account ([`waybill_api.md` §1](../waybill_api.md)).
  - Refused → hide Cancel for completed waybills; delete `_action_reverse_completed_waybill`.
  - Accepted → Cancel = Edit every line to 0 (W7); never a return waybill.
  - Either way: when sync, Update or drift turns a seller waybill with a done delivery into cancelled, set `rs_post_commit_error` and an activity (S24). Refuse Cancel on an active waybill whose delivery is already done ("Complete it instead") — old #21.

#### W10. Cancel on an active waybill strands the order — new, P2 [S16] [D]
- **Repro.** Waybill active, delivery Ready → Cancel → delivery **cancelled**, SO 5 ordered / 0 delivered, no open delivery, SO lines **still locked**.
- **Cause.** [`actions:527`](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill_actions.py#L527) cancels the delivery. The SO lock counts cancelled waybills ([`sale_order.py:18`](../custom_addons/gec_odoo_modules/rs_waybill/models/sale_order.py#L18)); the PO version already excludes them ([`purchase_order.py:28`](../custom_addons/gec_odoo_modules/rs_waybill/models/purchase_order.py#L28)).
- **Fix (R5, recommended).** After the RS cancel keep the delivery: `picking.waybill_id = False`, then `picking._rs_try_create_waybill()` → new draft waybill. Lock compute: copy the PO version (`w.rs_internal_id and w.state != 'cancelled'`). Cancelling the delivery or the SO stays the way to abandon an order.

#### W11. RS-side cancel of an active waybill blocks the delivery for good — new, P2 [S15]
- **Repro.** Waybill cancelled on the RS portal → Update → Validate: "linked waybill was cancelled on RS.GE. Create a new waybill…". Unreserve + Check Availability → still no new waybill.
- **Cause.** [`picking:168`](../custom_addons/gec_odoo_modules/rs_waybill/models/stock_picking.py#L168) returns as soon as any waybill is linked, cancelled or not.
- **Fix.** `if self.waybill_id and self.waybill_id.state != 'cancelled':` — Check Availability then creates a fresh waybill (same path as W10).

#### W12. Buyer change on a delivered waybill rewrites the SO customer — new, P2 [S21] [D]
- **Repro.** Completed waybill, Edit the buyer → the confirmed, delivered SO and the done delivery both get the new customer.
- **Cause.** [`rs_waybill.py:726-739`](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L726) writes `partner_id` on a confirmed SO; core makes it read-only once confirmed ([`sale_order_views.xml:461`](../addons/sale/views/sale_order_views.xml#L461)).
- **Fix.** Once the delivery is done or the SO has an invoice, refuse a buyer change in Edit ("a different buyer is a different sale: return and re-issue"). Before that, update only the open delivery's partner. [D] if the business wants to reassign the SO before dispatch.

### Phase 3 — RS-side changes (R6)

#### W13. RS changes are applied half-way and committed — #55, P1 [S27]
- **Repro.** S27 (W2): the done move was raised, the SO write raised, the exception was swallowed with no savepoint, the sync committed. The snapshot is cleared, so no later run retries.
- **Correction to the old plan.** Its note "#14 half applied is wrong" holds for the manual Edit (full rollback) but not for sync, Update and drift: [`rs_waybill.py:1585-1591`](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1585) catches everything.
- **Fix.** `_apply_rs_goods_diff_auto` computes a target state instead of replaying a one-shot snapshot: per waybill line, `line.quantity − (move.quantity if done else move.product_uom_qty)`; moves with no line = removed; lines with no move = added. Apply it inside `with self.env.cr.savepoint():`. On failure: `rs_post_commit_error` + note; the next Update, sync or drift computes the same delta again and retries. The manual Edit can apply the same helper after the popup; it keeps its snapshot only to build the RS tombstones for deleted lines ([`actions:262`](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill_actions.py#L262)).

#### W14. Lines matched by barcode + name: a rename on RS duplicates the sale — #64, #32, P1 [S14]
- **Repro.** Done 10, stock 30. On RS rename the line and change 10 → 12 → Update → **second SO line 12/12 and second delivery 12 done**, pending return 10, on-hand **8** (truth 18).
- **Cause.** [`sync:727-756`](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill_sync.py#L727) keys lines on `(bar_code, name)`: the renamed line is deleted and recreated without `stock_move_id`, so the diff sees "removed 10 + added 12". [`_goods_lines_changed()`](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill_sync.py#L696) compares barcode, quantity and price only.
- **Fix.** Match on `rs_good_id` first, `(bar_code, name)` only for lines that have none. Compare `name`, `vat_type` and `unit_name` in `_goods_lines_changed`. With W13 a rename can no longer create a sale.

#### W15. Invoice lock bypassed by sync, Update and drift — #62, P2 [C]
- **Fix.** `rs_waybill` gets `_rs_can_auto_apply()` returning True, called before goods diffs and cascades are applied. `rs_base_methods` overrides it with `not self.is_locked_by_invoice`. When False: keep the pending change and set `rs_post_commit_error`.

#### W16. Reverse-created lines have no `stock_move_id` — #15, P2 [C]
- **Fix.** Old #15: set the link in `_rs_build_moves_on_picking` and after the SO confirm. W13 falls back to the product for older records.

#### W17. Seller sync overwrites the start address with the company street — new, P3 [C]
- **Cause.** The seller overrides carry `'start_address': company.street` ([`sync:171`](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill_sync.py#L171), [`sync:380`](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill_sync.py#L380)), applied over the RS value ([`sync:438`](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill_sync.py#L438)). A warehouse start address ("Kostava 1, Tbilisi", [`picking:384`](../custom_addons/gec_odoo_modules/rs_waybill/models/stock_picking.py#L384)) becomes "Kostava 1" locally, and the next Edit sends that to RS.
- **Fix.** Drop `start_address` from both seller override dicts.

#### W18–W20. Carried sync items — unchanged [C]
- **W18 (#23)** backfill builds documents for cancelled waybills. P2.
- **W19 (#24)** per-row failures do not stop the cursor ([`sync:392`](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill_sync.py#L392) checks chunk failures only). P2.
- **W20 (#63)** drift never fills `company_id` on old rows. P3.

### Phase 4 — Returns and type 5 (R4)

#### W21. Type-5 returns carry no sale/purchase links — #22, P1 [S11, F5]
- **Repro.** Done 10. Seller type-5 waybill for 4 → receipt built and validated → `sale_line_id` empty, `origin_returned_move_id` empty, SO delivered **10** (truth 6); invoicing still offers 10.
- **Fix.** Build the return with core `_create_return()` on the original delivery (seller) or receipt (buyer), through the existing `_create_return_picking` helper. Fall back to plain moves only when no original is found.
- **Proof F5.** `_create_return()` for 4 → links set, SO delivered 10 → 6.

#### W22. Any receipt on an RS-enabled Receipts type becomes a "return" waybill — new, P2 [S25]
- **Repro.** Manual receipt from a vendor, no PO → type-5 waybill with the **vendor as buyer**.
- **Cause.** [`picking:455`](../custom_addons/gec_odoo_modules/rs_waybill/models/stock_picking.py#L455) skips only PO receipts.
- **Fix.** `if not self.return_id: return` (core field, [`stock_picking.py:46`](../addons/stock/models/stock_picking.py#L46)).

#### W23. Cancelling a vendor receipt cancels the vendor's waybill — #20, P2 [S26]
- **Repro.** Buyer receipt Ready → Cancel → `ref_waybill` on the vendor's document → RS −101 → receipt not cancelled.
- **Fix.** Old #20: cascade only for seller-direction waybills ([`picking:129`](../custom_addons/gec_odoo_modules/rs_waybill/models/stock_picking.py#L129)).

### Phase 5 — Buyer side (R7)

#### W24. A vendor decrease ships goods back automatically; Receive changes stock before the RS confirm — #19, #17, #47, P1 [S12, F4]
- **Repro.** PO 10 received. Vendor 10 → 8 on RS. Receive → **outgoing transfer to the vendor, validated at once**, no `origin_returned_move_id`, no `return_id`; on-hand 8.
- **Causes.** [`rs_waybill.py:1792-1840`](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1792) builds and force-validates the return; [`:1695-1789`](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1695) swallows errors without a savepoint; [`actions:594-605`](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill_actions.py#L594) reconciles before `confirm_waybill`.
- **Fix.** Receive → `confirm_waybill` → commit → reconcile inside `_rs_post_commit` (savepoint, flag, drift retry — as the seller side does). On a done receipt the reconcile is in place: `move.quantity = new` on the receipt move, then the PO line quantity. Delete `_reconcile_buyer_decrease_done`. Receive means "we accept the vendor's corrected quantity"; Reject means dispute, with no stock change.
- **Proof F4.** Done receipt 10 → `quantity = 8`, PO 8 → received 8, still one receipt. → 12 behaves the same.

#### W25. Vendor-added product priced at cost; its receipt has no `date_done` — #49 = #57, #58, P2 [S32]
- **Repro.** Vendor adds B 4 @ 25 (cost 5) → Receive → PO line price **5**; new receipt done with `date_done` **empty**.
- **Fix.** Take the price from the waybill line, as the PO creation does ([`rs_waybill.py:952`](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L952)). Validate the new receipt with `button_validate()` (picking level). `_force_validate_moves` then has no caller left; delete it.

#### W26–W29. Carried buyer items — unchanged [C]
- **W26 (#48)** PO cancelled although its receipt is done. P2.
- **W27 (#50)** every vendor waybill creates a new PO. [D]
- **W28 (#52)** Update backfill creates the PO in the user's active company. P2.
- **W29 (#53)** two-step PO approval leaves the waybill without a receipt. P3.

### Carried unchanged, not re-run [C]
#16 distribution remainder adds stock that never left [D] · #25 waybill company from `env.company` · #26 SOAP call inside `stock.picking.write` · #27 auto-created products not storable [D] · #28 price, discount, UoM, currency [D] · #31 dead "Enable Stock Integration" switch · #33 ACL. Bodies in the old plan.

Not a bug on its own: S5 (added product with no stock → on-hand −2). Core's own done-line correction does the same ([`stock_move_line.py:411`](../addons/stock/models/stock_move_line.py#L411)); the goods left, so the stock record was wrong. W6's core inverse reserves existing stock first.

---

## 3. Review of the external assessment

It describes the intended design correctly. It misses the defects that break RS or stock, and one of its judgements is wrong.

| Its case | Verdict | Evidence |
|---|---|---|
| 1 Before dispatch, quantity change also sets the SO | Correct only for a single delivery. With a split order it cuts the other open delivery (6 → 1); on a partial reservation it shrinks the order | S1, S31 → W2, W3 |
| 2 Add / remove a product before dispatch | Add works once; the next edit of that line doubles the demand. Remove works | S18, S29 → W4 |
| 3 Wrong product before dispatch | Mechanism correct (remove + add); inherits case 2 | W4 |
| 4 Done, more left | Blocked on split orders, half-applied from RS; a serial number ends with quantity 2 | S2, S27, S19 → W2, W5 |
| 5 Done, product omitted | Worse than stated: the move can land in the open backorder and validate it; overstated when reserved on several shelves | S3, S4 → W6 |
| 6 Short-ship | Correct. Missing: stock waits for a warehouse user to validate a return nobody received; "Fully Delivered"; the next SO change re-procures | S22 → W7 |
| 7 Two return mechanisms, "a separate business/document decision" | **Disagree.** Editing the original down and issuing a type-5 counts the return twice on RS. RS rules decide it: a return is a new reverse transport | S7 → W8 |
| 8 Wrong product after delivery | Mechanism correct; inherits cases 5 and 6 | W6, W7 |
| 9 Cancel before delivery, "the customer may still want it delivered another day" | Not possible: the delivery is cancelled and the SO lines stay locked | S16 → W10 |
| 10 Cancel a completed waybill | RS rules say completed waybills cannot be cancelled. If RS accepts, "Goods returned" reverses twice; closing the popup loses the reversal | S8 → W8, W9 |
| 11 Header-only changes | Correct; a buyer change also rewrites the customer of a delivered SO | S21 → W12 |
| 12 RS-portal edits | Correct for simple cases. Missing: rename + quantity duplicates the sale; half-apply; stock wrong until a click; RS cancel strands the delivery or goes unnoticed | S14, S27, S23, S15, S24 → W9, W11, W13, W14 |
| 13 Buyer corrections | Correct, including the automatic vendor return; vendor-added lines priced at cost | S12, S32 → W24, W25 |
| 14 Vendor cancels | Correct (code, not re-run) | W26 |
| 15 Distribution remainder | Correct; the remainder also adds stock that never left | #16 |
| 16 Invoice lock | Correct for the four buttons; sync, Update and drift bypass it | W15 |

**On the 4/10 rating:** a score is less useful than the count. It rates the design; the runs test the code. Every correction path except "remove a line before dispatch" fails in at least one realistic variant (section 6). Its closing advice — fix stock, order linking and accounting before adding correction variants — stands; the rules in section 1 remove variants instead of adding them (one Edit meaning before dispatch, one after, returns only through Return).

---

## 4. Order of work

| Phase | Items | Why in this order |
|---|---|---|
| 0 | W1 | One signature; core Split is broken today; W3 needs it |
| 1 | W2, W3, W4 | Open-delivery edits keep order, delivery and RS equal |
| 2 | W5–W12 | Done-delivery edits, returns, cancels; W7/W8 remove the return-decision paths |
| 3 | W13–W20 | The sync reuses the phase 1–2 helpers |
| 4 | W21–W23 | Returns get core links |
| 5 | W24–W29 | Buyer bridge; dormant until POs are linked to waybills |
| — | Carried items | After the rules are in place |

Decisions needed first: W9 (RS test: `ref_waybill` on completed), W10 (keep the delivery on Cancel), W12 (buyer change before dispatch), W27, carried #16, #27, #28.

**Tests (ask first).** The scenario harness can become `tests/test_corrections.py`: one test per scenario, asserting the target numbers. Candidates: S1, S2, S3, S7, S9, S10, S12, S13, S14, S19, S22, S27, S31, plus F1–F6 as positive cases.

---

## 5. Old numbers → new numbers

| Old | New | Change |
|---|---|---|
| #13 | W5 | Two more places (1411, 1854) and serial corruption found |
| #14 | W2 | Split-order case worse than stated (open delivery cut 6 → 1); sync path half-applies |
| #15 | W16 | Unchanged |
| #16, #25, #26, #27, #28, #31, #33 | carried | Not re-run |
| #17, #19, #47 | W24 | Merged: one fix (confirm first, correct in place) |
| #18, #56 | W7, W9 | Fix changed: in-place correction + pending written before the popup |
| #20 | W23 | Reproduced (RS −101) |
| #21 | W9 | Refuse Cancel when the delivery is done |
| #22 | W21 | Reproduced; `_create_return()` proven |
| #23, #24, #63 | W18, W19, W20 | Unchanged |
| #32, #64 | W14 | Merged; rename variant reproduced |
| #48, #50, #52, #53 | W26–W29 | Unchanged |
| #49, #57 | W25 | Duplicates merged |
| #54 | W3 | Fix changed: split at Save + quantity check instead of a return decision |
| #55 | W13 | Generalised: any exception, not only lot errors; target state instead of snapshot |
| #58 | W6, W25 | Most callers removed by W5, W6, W24, W25 |
| #62 | W15 | Unchanged |
| — | W1, W3 (drift), W4, W6, W8, W10, W11, W12, W17, W22 | New |

---

## 6. Scenario log

Run 2026-09-25 on `gec20_scenario_waybill` (Odoo 20, `rs_waybill`, `sale_management`, `purchase_stock`, `stock_account`; no invoices involved). rs.ge was replaced by an in-memory fake of `save_waybill`, `send_waybill`, `close_waybill(_vd)`, `ref_waybill`, `confirm_waybill` and `get_full_waybill`; every other line of module and core code ran as shipped. Delivery Orders and Receipts both had "Create RS Waybill" on (Receipts because v20 sends delivery returns there). The database and its filestore were dropped afterwards.

| # | Setup → action | Result |
|---|---|---|
| S0 | SO 10 → delivery → waybill activated → Validate | Delivery done, waybill completed, RS 10 — correct |
| S1 | SO 10, stock 4: D1 4 done; +6 → D2 6 active; Edit W2 6 → 5 | RS 5, D2 demand 1, SO ordered 5 |
| S2 | SO 10 = 4 + 6, both done; Edit W1 4 → 5 | Refused: "cannot be decreased below the amount already delivered" |
| S3 | SO 10 C, stock 4: D1 done, D2 6 open; Edit W1: add X 3 | X validated inside D2; D2 done with X only; C 6 moved to D3 with no waybill |
| S4 | Done 5; Edit: add Y 5, Y on two shelves (2 + 3) | Y lines 5 + 3 = 8 done; on-hand −3; picking `date_done` empty |
| S5 | Done 3; Edit: add N 2, N not in stock | Done 2, on-hand −2 (core-like) |
| S6 | Done 10; Edit 10 → 8; close popup | Pending empty; delivery 10; RS 8; Reconcile: "Nothing to reconcile" |
| S7 | Done 10; Edit 10 → 8; "Goods returned" | RS original 8 + type-5 return 2 → RS net 6; SO delivered 8 |
| S8 | Done 5; Cancel; then "Goods returned" | RS −2, delivery done, SO delivered 5, nothing pending; then type-5 for 5 → RS net −5 |
| S9 | SO 10, stock 8 → waybill 8 active; +2, re-reserve; Validate | 10 shipped, RS completed at 8 |
| S10 | Waybill 10 active; Edit 10 → 12 (stock 10); RS completes | Delivery 10 done + backorder 2 with its own waybill 2; RS original 12 |
| S11 | Done 10; seller type-5 waybill for 4 → receipt → Validate | No `sale_line_id`, no `origin_returned_move_id`; SO delivered 10 |
| S12 | PO 10 received; vendor 10 → 8; Receive | Outgoing picking to the vendor done at once; no return links; on-hand 8 |
| S13 | Receipt demand 10, lot lines 4 + 6; `_force_validate_moves` | LA 10 + LB 6 = 16 received |
| S14 | Done 10 (stock 30); RS: rename + 10 → 12; Update | Second SO line 12/12 + second delivery 12; pending return 10; on-hand 8 (truth 18) |
| S15 | Waybill active; RS cancels; Update; Validate; Check Availability | Validate refused; no new waybill is ever created |
| S16 | Waybill active; Cancel | Delivery cancelled; SO 5/0 with no delivery; SO lines locked |
| S18 | Open delivery; Edit: add B 4; Edit B 4 → 5 | Delivery B 5 + B 5; RS 5; SO 5 |
| S19 | Serial product, done with SN1; Edit 1 → 2 | SN1 move line quantity 2; SN1 Stock −1, Customers 2 |
| S21 | Done; Edit buyer → other customer | Confirmed SO and done delivery get the new customer |
| S22 | Done 10; Edit 10 → 8; "Short-ship" | Return Ready, stock unchanged; after validation SO 10/8, Delivery Status "full", procurement 8 vs 10 |
| S23 | Done 10; RS 10 → 7; Update | Waybill 7, pending 3; delivery 10; on-hand 0 (truth 3) |
| S24 | Done 5; RS cancels the completed waybill; Update | Waybill cancelled; delivery done; no flag |
| S25 | Manual vendor receipt, no PO, RS-enabled Receipts | Type-5 waybill with the vendor as buyer |
| S26 | Buyer receipt Ready; Cancel (RS answers −101) | `ref_waybill` sent for the vendor's waybill; receipt not cancelled |
| S27 | SO 10 = 4 + 6 done; RS W1 4 → 5; Update twice | D1 5 done, SO 10/11; error in chatter only; second Update: nothing |
| S28 | Done 10; RS 10 → 12 + new lot product 3 (lot in stock); Update | Applied (supplementary delivery) — works when stock and lot exist |
| S29 | Open 2-line delivery; Edit: remove B | RS tombstone, move gone, SO B 0 — correct |
| S30 | Open 5 (stock 5); Edit 5 → 8; Validate | 5 done + backorder 3 with its own waybill 3; RS original 8 |
| S31 | SO 10, stock 8 → waybill 8 active; +1; Edit 8 → 9 | Demand 9, SO ordered 9 |
| S32 | PO received; vendor adds B 4 @ 25 (cost 5); Receive | PO line price 5; new receipt done, `date_done` empty |

Fix prototypes (plain core calls, no module change):

| # | Call | Result |
|---|---|---|
| F1 | Done move on lots A 4 / B 6: `quantity = 8`; untracked done 10: `quantity = 12` | A 4 / B 4, delivered 8; one line 12, delivered 12 |
| F2 | SO line (`skip_procurement`) + move on the done delivery with `sale_line_id`, `quantity = 2` | Delivered 2/2, one picking, `date_done` kept; that line's procurement count 0 |
| F3 | SO 10, 8 reserved: split | Delivery 8/8 = waybill 8; backorder 2 with its own waybill 2 (Split button needs W1) |
| F4 | Done receipt 10: `quantity = 8`, PO 8; then 12 / 12 | Received 8, then 12; always one receipt |
| F5 | `_create_return()` on a done delivery, 4 units | Return move has `sale_line_id` and `origin_returned_move_id`; SO delivered 10 → 6 |
| F6 | S1 with move demand 5 + SO −1 (`skip_procurement`) | D2 5/5, SO 9, procurement 9 |

# rs_waybill + rs_einvoice + rs_base_methods — Findings and Fix Plan

**Date:** 2026-09-18 · **Sources:** two independent source reviews (Claude, Codex), every item re-verified against this checkout's Odoo 19 core · **Status:** none of the 65 findings are fixed. **The 20.0 port is** — G1–G4 and G7 were applied 2026-09-22 and all three modules now install on gec20_prod1. **Core-safety review + provoke steps added 2026-09-18** (section below the priority table).

Tags: **[C]** proven from code · **[L]** strong inference · **[D]** business rule must be decided first.
**Canonical folder: `custom_addons/gec_odoo_modules` — nothing else.** (Decided 2026-09-19.) All three modules live there and every path below points there. Older copies elsewhere on disk (`gec_rs_waybill`, `rs_base`, `gec_project`, `gec_rs_invoice`) are dead — do not read, edit or install from them, and keep them off `--addons-path`.

Paths: `W` = [rs_waybill](../custom_addons/gec_odoo_modules/rs_waybill) · `E` = [rs_einvoice](../custom_addons/gec_odoo_modules/rs_einvoice) · `B` = [rs_base_methods](../custom_addons/gec_odoo_modules/rs_base_methods).

**gec_modules2 is a TEST database, not production** (corrected 2026-09-19 — an earlier pass in this file and in project memory called it "live"). Every `gec_modules2` reference below confirms a mechanism fires on realistic data, or checks an index/field/install-state fact; it is never evidence of a current production condition. Read "N posted bills show X on gec_modules2" as "N test-DB records show X", not as "N production records are wrong right now."

## Re-verified against Odoo 20 core — 2026-09-22

Everything below this section was written and verified against **Odoo 19**. This checkout is **20.0**.
Every core `file:line` the plan cites was re-resolved against the 20.0 tree by symbol (line numbers
all drifted; only the deltas that change a finding or a fix are listed here). Sources: branch `20.0`
working tree, compared with `git show 19.0:<path>`.

**Verdict: no finding is invalidated. Three core changes rewrite fixes, one correction kills a stated
mechanism, and the modules themselves no longer run on 20.0 — the plan cannot be executed until the
four blockers below are cleared.**

### A. Blockers — the three modules do not run on 20.0 (new, not in the plan)

| # | What | Where | Effect |
|---|---|---|---|
| V1 | `stock.return.picking` / `stock.return.picking.line` **deleted** (`[REM] stock: remove return wizard`) | [rs_waybill.py:1453](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1453) | `_create_return_picking` raises `KeyError: 'stock.return.picking'`. Every return path dies: edit-down, cancel-completed, type-5 |
| V2 | `stock.move.product_uom` → **`uom_id`**; `stock.move.line.product_uom_id` → **`uom_id`**; `purchase.order.line.product_uom_id` → **`uom_id`** | [stock_picking.py:223](../custom_addons/gec_odoo_modules/rs_waybill/models/stock_picking.py#L223), [rs_waybill.py:956](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L956), [1378](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1378), [1421](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1421), [1711](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1711), [1760](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1760), [1860](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1860) | 7 sites. PO creation, move-line creation and the rs.ge `UNIT_TXT` payload all raise `ValueError: Invalid field`. `account.move.line.product_uom_id` and `sale.order.line.product_uom_id` are **unchanged** — the two wizard sites in `rs_base_methods` are fine |
| V3 | OWL 3: `useState` is no longer exported by `@odoo/owl`; `t-esc` is retired (609 core files in 19.0 → 2 in 20.0) | [waybill_list_kpis.js:13,36](../custom_addons/gec_odoo_modules/rs_waybill/static/src/dashboard/waybill_list_kpis.js#L13), [waybill_list_kpis.xml](../custom_addons/gec_odoo_modules/rs_waybill/static/src/dashboard/waybill_list_kpis.xml) | The waybill dashboard KPI component fails at setup. Core's replacement is `proxy()` ([dialog.js:75](../addons/web/static/src/core/dialog/dialog.js#L75)) and `t-out`. `odoo/upgrade_code/owl3-migration.py` does this mechanically |
| V4 | `ir.model.access` + `ir.rule` merged into `ir.access` | — | **Already fixed 2026-09-22.** All three modules now ship `security/ir.access.csv` (rs_einvoice 16 rows, rs_waybill 18, rs_base_methods 6); `rs_einvoice` installs on gec20_prod1. Item **#36** now reads [rs_waybill/security/ir.access.csv:2](../custom_addons/gec_odoo_modules/rs_waybill/security/ir.access.csv#L2) — still `base.group_user,crud`, so the finding stands unchanged |
| V5 | `product.tracking` dropped the `'none'` value and is no longer required/defaulted ([stock/models/product.py:835-841](../addons/stock/models/product.py#L835); v19 had `('none','By Quantity')`, `required=True, default='none'`) | [rs_waybill.py:2029](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L2029) | **Silent, not a crash.** `move.product_id.tracking == 'none'` is now always False, so the branch it guards never runs. The v20 equivalent is `not move.product_id.tracking` |
| V6 | `ir.config_parameter.get_param` / `set_param` **removed**, replaced by typed accessors `get_bool/get_int/get_float/get_str` and `set_bool/set_int/set_float/set_str` ([ir_config_parameter.py:66-131](../odoo/addons/base/models/ir_config_parameter.py#L66)) | [res_company.py:69,73,80](../custom_addons/gec_odoo_modules/rs_waybill/models/res_company.py#L69), [rs_waybill_sync.py:278,279,304,389](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill_sync.py#L278) | `AttributeError: 'ir.config_parameter' object has no attribute 'get_param'` **at install** — `res_company.init()` runs during `init_models`. `config_parameter=` on `res.config.settings` fields is unaffected ([res_config.py:220-331](../odoo/addons/base/models/res_config.py#L220)) |
| V7 | `res.partner.company_registry` and `res.company.company_registry` **removed** (commit `6f8c2526a00 [REF] base,*: multi ID for UBL + remove company_registry`); country-specific IDs now live in the `additional_identifiers` JSON ([res_partner.py:330](../odoo/addons/base/models/res_partner.py#L330)) | 33 non-test sites across `rs_waybill` + `rs_base_methods`, 21 more in tests | `ValueError: Wrong @depends ... Dependency field 'company_registry' not found` at registry init, then every TIN lookup, search domain and waybill payload. **There is no `GE_*` key** in `ADDITIONAL_IDENTIFIERS_METADATA` (58 keys, none Georgian), and the column does not exist in gec20_prod1 — so `vat` is the only field left for a Georgian TIN |
| V8 | `uom` view xmlids renamed: `product_uom_form_view` → `uom_uom_view_form`, `product_uom_tree_view` → `uom_uom_view_list`, `product_uom_form_action` → `uom_uom_action_list` | [uom_uom_views.xml:7,19](../custom_addons/gec_odoo_modules/rs_waybill/views/uom_uom_views.xml#L7) | `ParseError` at install. The `uom.product_uom_*` **data** xmlids (unit, kgm, gram, …) are unchanged — all 11 the module references still resolve |
| V9 | `sale_stock`'s order-form extension now carries `<field name="priority">20</field>` ([sale_order_views.xml:8](../addons/sale_stock/views/sale_order_views.xml#L8)); it had none in 19.0 | [sale_order_views.xml](../custom_addons/gec_odoo_modules/rs_waybill/views/sale_order_views.xml) | Our view (default priority 16) now applies **before** it, so `//button[@name='action_view_delivery']` is not in the arch yet → "cannot be located in parent view" |
| V10 | List-view columns are wrapped in `<column>` elements in 20.0 | [sale_order_views.xml](../custom_addons/gec_odoo_modules/rs_waybill/views/sale_order_views.xml), [stock_picking.xml:49](../custom_addons/gec_odoo_modules/rs_waybill/views/stock_picking.xml#L49) | `product_id` is no longer a direct child of `<list>` — on `sale.order.line` it is inside `<column name="product_and_description">`, on the picking move list inside an unnamed `<column>`. Bare `<field>` children of `<list>` still work, so only `product_id` anchors broke |

### B. Core changes that rewrite a stated fix

**The return wizard is gone — #16, #22, #25 and the module's own `_create_return_picking` all need new API.**
Odoo 20 makes returns picking-native: [`_create_return()`](../addons/stock/models/stock_picking.py#L976), with
[`action_return`](../addons/stock/models/stock_picking.py#L812) / [`action_return_all`](../addons/stock/models/stock_picking.py#L823)
as the UI entry points and `return_id` / `return_ids` / `show_return` fields on the picking.

The per-module overrides that the plan relied on **survived, but moved off the wizard onto `stock.picking`**,
so the guarantees the ADJUST verdicts for #22 and #25 were built on still hold:

| What the plan needed | v19 (wizard) | v20 |
|---|---|---|
| `origin_returned_move_id` | `stock/wizard/stock_picking_return.py:39` | [stock_picking.py:949](../addons/stock/models/stock_picking.py#L949) in `_prepare_return_move_default_values` |
| `purchase_line_id` + partner | `purchase_stock/models/stock.py:128` | [purchase_stock/models/stock.py:46-50](../addons/purchase_stock/models/stock.py#L46) |
| `sale_line_id` | `sale_stock/wizard/stock_picking_return.py:11` | [sale_stock/models/stock.py:399-403](../addons/sale_stock/models/stock.py#L399) |
| `to_refund` | `stock_account/wizard/stock_picking_return.py:10` | [stock_account/models/stock_picking.py:34-37](../addons/stock_account/models/stock_picking.py#L34) |

Two behavioural differences to carry into the fixes:

- **Return quantities start at 0, not at the delivered quantity.** `_prepare_return_move_default_values`
  sets `product_uom_qty = move_id.quantity if not self.show_return else 0`
  ([stock_picking.py:939](../addons/stock/models/stock_picking.py#L939)). The wizard's
  `product_return_moves` lines are gone, so the caller writes `product_uom_qty` per move itself
  (match by `move.origin_returned_move_id`) or calls `action_return_all`.
- **`_create_return()` leaves the picking in `draft`** and does not confirm or assign — the same
  `action_confirm()` / `action_assign()` the module already calls afterwards still apply, and
  "leave the return *Ready*, the warehouse validates" (the #22/#25 verdict) is still the right shape.

**#15 (forced validation) — the ADJUST verdict holds, with renamed dependencies.** `stock.move.quantity`
still has the spreading inverse: field [stock_move.py:171](../addons/stock/models/stock_move.py#L171),
inverse `_set_quantity` at [465](../addons/stock/models/stock_move.py#L465), putaway applied at
[2668](../addons/stock/models/stock_move.py#L2668). `picked` unchanged. But the fix must be written
against `uom_id`, not `product_uom` (see V2).

**#4 / #5 — `_check_draftable` lost one of its three blocks, so auto-cancel is *less* constrained on 20.0.**
[account_move.py:7010](../addons/account/models/account_move.py#L7010) now refuses only
exchange-difference entries and hash-locked entries; the v19 tax-cash-basis refusal
(`move.tax_cash_basis_rec_id or move.tax_cash_basis_origin_move_id`) is deleted. `button_cancel` is
byte-identical ([7039](../addons/account/models/account_move.py#L7039)) and still calls
`remove_move_reconcile()` at [7049](../addons/account/models/account_move.py#L7049) — **#4 is confirmed
and marginally worse**. Consequence for the #5 *Provoke* recipe: the cash-basis route to an
un-cancellable original no longer exists; use the hash lock (*Lock Posted Entries with Hash*), which
is unchanged.

**#30 — holds, but the field moved out of `stock`.** `is_storable` is now defined in
[product_template.py:127](../addons/product/models/product_template.py#L127) (still `default=False`),
compute `_compute_is_storable` at [477](../addons/product/models/product_template.py#L477) still only
forces False for non-`consu` types, so a `True` passed to `create()` still wins. Two v20 additions to
watch when writing the fix: a new `store_by` selection ([stock/models/product.py:842](../addons/stock/models/product.py#L842))
whose inverse writes both `is_storable` and `tracking`, and `tracking` no longer accepts `'none'` —
use `False`.

**#6 — the "no upselling" correction is still right, and now has a second escape hatch.**
`qty_delivered > product_uom_qty` is still the only trigger
([sale_order_line.py:1388-1396](../addons/sale/models/sale_order_line.py#L1388)); v20 adds
`and not (line.qty_overage and line.order_id.invoice_overages)` at
[1394](../addons/sale/models/sale_order_line.py#L1394). Drafts still count in `qty_invoiced`
(the filter moved into `_prepare_qty_invoiced`, [1286](../addons/sale/models/sale_order_line.py#L1286)),
and the credit-note copy the verdict leans on is unchanged
([account_move.py:5898](../addons/account/models/account_move.py#L5898),
[sale/account_move_line.py:41-43](../addons/sale/models/account_move_line.py#L41),
[purchase/account_invoice.py:667-670](../addons/purchase/models/account_invoice.py#L667)).

### C. One correction: #40's mechanism is wrong, in v19 as well as v20

The plan's core evidence for #40 is `account_move_line.py:378-382 (digits='Product Price')` plus
`fields_numeric.py:140-144 (Float.convert_to_cache rounds to digits[1])`. That citation points at
`product_uom_id`, not `price_unit`. The real definition — **identical in 19.0 and 20.0** — is
[account_move_line.py:457-461](../addons/account/models/account_move_line.py#L457):

```python
price_unit = fields.Float(
    string='Unit Price',
    compute='_compute_price_unit', store=True, readonly=False, precompute=True,
    min_display_digits='Product Price',
)
```

`min_display_digits` without `digits` sets `digits = False`
([fields_numeric.py:124-126](../odoo/orm/fields_numeric.py#L124)), so `get_digits()` returns falsy and
`convert_to_cache` **does not round** ([169-173](../odoo/orm/fields_numeric.py#L169)); the column is
`numeric` with no scale — confirmed on gec20_prod1: `account_move_line.price_unit` is `numeric` with
`numeric_scale` NULL. `_rs_pulled_line_vals` does not round either
([account_move_sync.py:630-634](../custom_addons/gec_odoo_modules/rs_einvoice/models/account_move_sync.py#L630)).

The 0.01 drift observed on the gec_modules2 test DB is not disputed, but the stated cause is not the
field precision, and therefore the proposed fix ("raise the Product Price `decimal.precision`") would
change nothing. **Re-derive #40 against the v19 DB before acting on it** — where the rounded value
actually enters is still unknown.

### D. Claims re-checked and unchanged

`Field.__set__` always writes ([fields.py:2019](../odoo/orm/fields.py#L2019), #3) ·
`_sql_constraints` still only warned and ignored ([model_classes.py:175](../odoo/orm/model_classes.py#L175), #33) ·
`account.tax.price_include` still computed with a `search=` method, so the `('price_include','=',False)` domain works ([account_tax.py:122](../addons/account/models/account_tax.py#L122), #38) ·
`_update_line_quantity` guard ([sale_stock/sale_order_line.py:420](../addons/sale_stock/models/sale_order_line.py#L420), #17) ·
`_prepare_qty_received` still nets out returns ([purchase_stock/purchase_order_line.py:62-87](../addons/purchase_stock/models/purchase_order_line.py#L62), #22/#25) ·
the done-move cancel guard, which the plan mis-cited as `stock_move.py:2032` in v19 too — it is `_action_cancel` at [stock_move.py:2274](../addons/stock/models/stock_move.py#L2274), and `unlink()` has no such guard (#24) ·
`stock.picking._action_done` still delegates to `todo_moves._action_done()` ([stock_picking.py:1013](../addons/stock/models/stock_picking.py#L1013)), so **#62 holds and grows**: a bare `moves._action_done()` now also skips a new v20 no-backorder follower notification ([1017-1037](../addons/stock/models/stock_picking.py#L1017)) on top of `date_done`, `_trigger_assign`, `_intercompany_unpack` and `_send_confirmation_email` ·
journal hash mode and all five lock dates unchanged (#41, #45).

### E. Not re-verified

Items **39, 42–61, 63–68** were re-checked only where they cite a core file (all such citations are
covered above). Their module-side mechanics and the test-DB counts were not re-run on 20.0, and the
gec_modules2 figures throughout this file are Odoo 19 test-DB numbers.

### F. One dead-code finding turned up by the comparison

`_name_search` is overridden in [res_partner.py:36](../custom_addons/gec_odoo_modules/rs_waybill/models/res_partner.py#L36)
and [fleet_vehicle.py:37](../custom_addons/gec_odoo_modules/rs_waybill/models/fleet_vehicle.py#L37). Core has no such
method: `name_search` searches `display_name` directly and dispatches to `_search_display_name`
([models.py:1593-1622](../odoo/orm/models.py#L1593), [1521](../odoo/orm/models.py#L1521)). Neither override has ever
run — this was already true on 19.0, so it is not a 20.0 regression. Whatever partner and vehicle lookup behaviour they
were meant to add (TIN search, plate search) is simply absent; port them to `_search_display_name(operator, value)`
or delete them.

---

## G. How to fix the 20.0 blockers

**Status 2026-09-22: G1–G4 and G7 are APPLIED. All three modules install and upgrade cleanly on
gec20_prod1** (`-i rs_waybill,rs_base_methods` → `installed`, no traceback). G5 is still optional and
not applied; the test suite is not ported (see G8).

The sections below are kept as the record of what each fix is and why. `_sql_constraints` is the only
warning left in the install log, and that is plan item **#33**, not a 20.0 regression.

### G1 — V2: the UoM renames (7 sites)

Pure rename, no logic change. Odoo 20 renamed the UoM field on three models
([stock_move.py:68](../addons/stock/models/stock_move.py#L68),
[stock_move_line.py:33](../addons/stock/models/stock_move_line.py#L33),
[purchase_order_line.py:48](../addons/purchase/models/purchase_order_line.py#L48)):

| Model | 19.0 | 20.0 |
|---|---|---|
| `stock.move` | `product_uom` | `uom_id` |
| `stock.move.line` | `product_uom_id` | `uom_id` |
| `purchase.order.line` | `product_uom_id` | `uom_id` |
| `account.move.line` | `product_uom_id` | **unchanged** |
| `sale.order.line` | `product_uom_id` | **unchanged** |

| File | Line | Now | Becomes |
|---|---|---|---|
| [stock_picking.py](../custom_addons/gec_odoo_modules/rs_waybill/models/stock_picking.py#L223) | 223 | `'unit_name': move.product_uom.name` | `'unit_name': move.uom_id.name` |
| [rs_waybill.py](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L956) | 956 | `'product_uom_id': line.product_id.uom_id.id` (PO line) | `'uom_id': line.product_id.uom_id.id` |
| [rs_waybill.py](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1378) | 1378 | `'product_uom_id': move.product_uom.id` (move line) | `'uom_id': move.uom_id.id` |
| [rs_waybill.py](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1421) | 1421 | `'product_uom_id': m.product_uom.id` (move line) | `'uom_id': m.uom_id.id` |
| [rs_waybill.py](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1711) | 1711 | `'product_uom_id': product.uom_id.id` (PO line) | `'uom_id': product.uom_id.id` |
| [rs_waybill.py](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1760) | 1760 | `'product_uom_id': product.uom_id.id` (PO line) | `'uom_id': product.uom_id.id` |
| [rs_waybill.py](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1860) | 1860 | `'product_uom_id': move.product_uom.id` (move line) | `'uom_id': move.uom_id.id` |

The two `product_uom_id` keys in [rs_invoice_from_waybill_wizard.py:358,419](../custom_addons/gec_odoo_modules/rs_base_methods/wizards/rs_invoice_from_waybill_wizard.py#L358)
build `account.move.line` vals — **leave them alone.**

Knock-on: **#31**'s fix text is written against the old names. When that item is implemented it must read
`move.uom_id._compute_quantity(qty, product.uom_id)` and `move.uom_id.rs_unit_id`, not `move.product_uom`.

### G2 — V1: rewrite `_create_return_picking` on the picking-native API

This is the one real rewrite. [rs_waybill.py:1441-1468](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1441)
drives the deleted `stock.return.picking` wizard. The v20 shape is: create the return, write the
quantities yourself, drop the untouched lines, then confirm and assign.

What the wizard did for us and what replaces it:

| v19 wizard | v20 |
|---|---|
| `create({})` built one `product_return_moves` line per non-cancelled, non-inventory move | [`picking._create_return()`](../addons/stock/models/stock_picking.py#L976) creates one **`stock.move`** per non-cancelled move, at `product_uom_qty = 0` |
| set `return_line.quantity` | write `move.product_uom_qty`, matching by `move.origin_returned_move_id` |
| a zero line produced **no move** | a zero move still exists — `unlink()` it |
| raised *"Please specify at least one non-zero quantity"* when all were zero | nothing raises — check `move_ids` yourself |
| `action_create_returns()` confirmed + assigned | `_create_return()` leaves the picking **draft** — you confirm and assign |
| `_can_return()` refused non-done pickings | gone; the method's own `picking.state != 'done'` guard already covers it |

Replace lines 1452-1468 with:

```python
        skip = not create_waybill
        # Odoo 20 deleted stock.return.picking; returns are picking-native now.
        # _create_return() copies every non-cancelled move at quantity 0 and leaves the
        # picking in draft (stock_picking.py:976, :939), so we set the quantities, drop
        # the lines we are not returning, and confirm/assign under the skip flag.
        return_picking = picking.with_context(skip_rs_auto_create=skip)._create_return()
        remaining = dict(qty_to_return)
        for move in return_picking.move_ids:
            want = remaining.get(move.product_id.id, 0.0)
            # Per-move share, not the whole product quantity on every move (issue #16).
            take = min(want, move.origin_returned_move_id.quantity or want) if want else 0.0
            move.product_uom_qty = take
            if take:
                remaining[move.product_id.id] = want - take
        return_picking.move_ids.filtered(lambda m: not m.product_uom_qty).unlink()
        if not return_picking.move_ids:
            return_picking.unlink()
            return False
        return_picking.with_context(skip_rs_auto_create=skip).action_confirm()
        return_picking.with_context(skip_rs_auto_create=skip).action_assign()
        return return_picking
```

Three things this buys:

- **It closes #16 in the same edit.** The old loop wrote the full product quantity onto *every* return
  line of that product (2 moves of A, return 2 → 2 + 2 = 4). Because v20 makes us write
  `product_uom_qty` per move ourselves, the per-move decrement is now the natural way to write it —
  this is exactly the fix #16 asks for, expressed against `origin_returned_move_id` instead of the
  wizard's `move_id`. **#16's own fix text is superseded by this patch.**
- **#22 and #25 keep their ADJUST verdicts.** The wizard's per-module overrides survived on
  `stock.picking._prepare_return_move_default_values`, so a return built this way still carries
  `origin_returned_move_id`, `purchase_line_id` + partner, `sale_line_id` and `to_refund` (see the
  table in section B). Both items can be implemented on top of this method rather than hand-building
  moves.
- **"Leave the return Ready" is now the default**, not something to arrange: `_create_return()` does
  not validate, and the two calls above stop at Ready.

One behavioural difference to accept or guard: v19's wizard skipped moves whose
`location_dest_usage == 'inventory'`; v20's `_create_return` only skips `state == 'cancel'`. For a
waybill-linked delivery or receipt that destination does not occur, so the patch above ignores it — add
`and m.origin_returned_move_id.location_dest_usage != 'inventory'` to the `unlink` filter if that ever
changes.

### G3 — V3: OWL 3 in the waybill dashboard

Two mechanical edits, both inside
[static/src/dashboard/](../custom_addons/gec_odoo_modules/rs_waybill/static/src/dashboard/). Everything else
in that component is untouched: `onWillStart`, `status`, `useBus`, `useService`, `static template`, the
`{...listView, Controller: ...}` registry spread, `model.bus` `"update"`, `model.config.domain` and
`searchModel.getSearchItems` / `.query` / `.toggleSearchItem` all still exist in 20.0.

**[waybill_list_kpis.js:13](../custom_addons/gec_odoo_modules/rs_waybill/static/src/dashboard/waybill_list_kpis.js#L13)** — `useState` is no longer exported by `@odoo/owl`:

```diff
-import { onWillStart, status, useState } from "@odoo/owl";
+import { onWillStart, proxy, status } from "@odoo/owl";
```

**[waybill_list_kpis.js:36](../custom_addons/gec_odoo_modules/rs_waybill/static/src/dashboard/waybill_list_kpis.js#L36)**:

```diff
-        this.kpis = useState({
+        this.kpis = proxy({
```

`proxy()` is the direct replacement — same call shape, same reactivity, and it is what core now uses
([dialog.js:75,106](../addons/web/static/src/core/dialog/dialog.js#L75)). The `Object.assign(this.kpis, {...})`
at the end of `refreshKpis` keeps working unchanged.

**[waybill_list_kpis.xml](../custom_addons/gec_odoo_modules/rs_waybill/static/src/dashboard/waybill_list_kpis.xml)** — 8 occurrences of `t-esc`, all
`t-esc="..."` → `t-out="..."`. `t-out` escapes the same way for plain values, so there is no
behavioural change here.

`odoo/upgrade_code/owl3-migration.py` performs both edits mechanically across a whole addons path;
running it is safer than hand-editing if you also want the other custom modules done at the same time.

**Out of scope for this file but the same fix:** `bsc_strategy`, `id_ge_sign`, `gec_income_tax_report`,
`gec_analytic_margin` and `dps_account_report_filter` all still import `useState` and/or use `t-esc`,
and `gec_income_tax_report` also imports **`useRef`**, which is likewise gone in 20.0 (295 core files
in 19.0 → 0 in 20.0).

### G4 — V5: the `tracking == 'none'` branch

[rs_waybill.py:2029](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L2029) reads:

```python
                        if move.product_id.tracking == 'none':
                            move.quantity = move.product_uom_qty
                        else:
                            tracked_unfilled |= move
```

In 20.0 `tracking` is `False` / `'lot'` / `'serial'` — the `'none'` value and the `required=True,
default='none'` are gone ([product.py:835-841](../addons/stock/models/product.py#L835)). The comparison
is now always False, so **every** unfilled incoming move is reported as tracked and nothing is
force-filled — the receipt silently stops being completed. Fix:

```diff
-                        if move.product_id.tracking == 'none':
+                        if not move.product_id.tracking:
                             move.quantity = move.product_uom_qty
```

Grep for other `tracking` comparisons before shipping: this is the only one in the three modules today.

### G5 — F: port the two dead `_name_search` overrides

Core has no `_name_search`. `name_search` searches `display_name` directly and the hook is
`_search_display_name(operator, value)`, which returns a **domain**, not a recordset
([models.py:1593-1622](../odoo/orm/models.py#L1593), [1521](../odoo/orm/models.py#L1521)). Both overrides
below have therefore never run — on 19.0 either. Porting them turns two silently missing features back on.

**[res_partner.py:36-44](../custom_addons/gec_odoo_modules/rs_waybill/models/res_partner.py#L36)** — widen the
partner search by TIN:

```python
    @api.model
    def _search_display_name(self, operator, value):
        domain = super()._search_display_name(operator, value)
        if value and self.env.context.get('search_partner_by_tin'):
            joiner = Domain.AND if operator in Domain.NEGATIVE_OPERATORS else Domain.OR
            domain = joiner([
                domain,
                Domain('company_registry', operator, value),
                Domain('vat', operator, value),
            ])
        return domain
```

**[fleet_vehicle.py:37-49](../custom_addons/gec_odoo_modules/rs_waybill/models/fleet_vehicle.py#L37)** — replace the
name match with plate / driver / TIN, which is what the old code meant by setting `name = ''`:

```python
    @api.model
    def _search_display_name(self, operator, value):
        if value and self.env.context.get('show_driver_vehicle_label'):
            joiner = Domain.AND if operator in Domain.NEGATIVE_OPERATORS else Domain.OR
            return joiner([
                Domain('license_plate', operator, value),
                Domain('driver_id.name', operator, value),
                Domain('driver_id.vat', operator, value),
                Domain('driver_id.company_registry', operator, value),
            ])
        return super()._search_display_name(operator, value)
```

`Domain` is already imported in `res_partner.py`; add `from odoo.fields import Domain` to
`fleet_vehicle.py`. The `NEGATIVE_OPERATORS` branch mirrors what core's own `_search_display_name`
does — OR-ing a `not ilike` would widen the result instead of narrowing it.

### G6 — order of work, and what it unblocks

1. **G1** (renames) — mechanical, no behaviour change, and G2 depends on `uom_id` existing.
2. **G2** (`_create_return_picking`) — the only rewrite. Closes **#16** on the way and re-enables the
   return paths that **#21**, **#22**, **#24**, **#25** and **#60** all sit on.
3. **G4** (`tracking`) — one line, but it silently disables receipt completion until fixed.
4. **G3** (OWL) — front-end only; the dashboard is broken but nothing server-side depends on it.
5. **G5** (`_search_display_name`) — optional; it restores a feature rather than fixing a break.

That order was followed on 2026-09-22, with G7 folded in as each install failure surfaced it. G5 was
left out. The 65 open items below are actionable again. Nothing in G changes the plan's findings —
**#40 still needs re-deriving first** (section C), and the gec_modules2 counts throughout this file
remain Odoo 19 test-DB numbers.


### G7 — V6–V10: the blockers found by actually installing (all applied)

V1–V5 came from reading the source. V6–V10 came from running `-i rs_waybill` until it stopped failing.
Each one is applied.

**V6 — `ir.config_parameter`.** Straight rename to the typed accessor, chosen by what the key holds:

| File | Was | Now |
|---|---|---|
| [res_company.py:69](../custom_addons/gec_odoo_modules/rs_waybill/models/res_company.py#L69) | `ICP.get_param(_MIGRATION_FLAG)` | `ICP.get_bool(_MIGRATION_FLAG)` |
| [res_company.py:73](../custom_addons/gec_odoo_modules/rs_waybill/models/res_company.py#L73) | `ICP.get_param(param, '')` | `ICP.get_str(param, '')` |
| [res_company.py:80](../custom_addons/gec_odoo_modules/rs_waybill/models/res_company.py#L80) | `ICP.set_param(_MIGRATION_FLAG, '1')` | `ICP.set_bool(_MIGRATION_FLAG, True)` |
| [rs_waybill_sync.py:278-279](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill_sync.py#L278) | `ICP.get_param(key, '')` | `ICP.get_str(key, '')` |
| [rs_waybill_sync.py:304,389](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill_sync.py#L304) | `ICP.set_param(cursor_key, now_str)` | `ICP.set_str(cursor_key, now_str)` |

`get_bool` is backward-compatible with the legacy `'1'` the v19 code wrote: `_get` converts through
`str2bool`, and `str2bool('1')` is `True`. An unparseable value returns the default rather than raising,
because `_get` catches `ValueError` and yields `INVALID_VALUE` ([ir_config_parameter.py:132-150](../odoo/addons/base/models/ir_config_parameter.py#L132)).

**V7 — `company_registry` → `vat`.** This is the one with a judgement call in it, and 20.0 forces the
answer:

- the field and its column are gone from `res.partner` and `res.company`;
- its replacement, `additional_identifiers`, has **no Georgian key** — all 58 entries of
  `ADDITIONAL_IDENTIFIERS_METADATA` ([odoo/tools/partner_identifiers.py:479](../odoo/tools/partner_identifiers.py#L479))
  are for other countries, and `l10n_ge` adds none;
- `res_partner.company_registry` does not exist as a column in gec20_prod1, so there is no stored
  Georgian TIN to migrate out of it;
- the module already read `company_registry or vat` everywhere, so `vat` was always the fallback.

So every site collapses to `vat`, which is exactly what the fallback already did whenever
`company_registry` was empty. 33 non-test sites:

| Shape | Sites | Becomes |
|---|---|---|
| `(x.company_registry or x.vat or '')` | 13 | `(x.vat or '')` |
| `x.company_registry or x.vat or False` | 2 | `x.vat or False` |
| `['|', ('company_registry','=',t), ('vat','=',t)]` | 6 | `[('vat','=',t)]` |
| `'company_registry': self.seller_tin` in partner `create` | 1 | dropped (`'vat'` was already in the same dict) |
| `@api.depends(... 'company_registry')` | 2 | dependency dropped |
| `_compute_display_name` preferring `company_registry` over `vat` | 1 | `vat` only |

**Behavioural note worth stating plainly:** on a database where the TIN was stored in
`company_registry` and **not** in `vat`, that TIN is now invisible to the module. gec20_prod1 has no
such column so nothing is lost there, but any other 19.0 database must have its TINs moved into `vat`
before these modules are pointed at it.

**V8 — uom view refs.** [uom_uom_views.xml](../custom_addons/gec_odoo_modules/rs_waybill/views/uom_uom_views.xml):
`ref="uom.product_uom_form_view"` → `ref="uom.uom_uom_view_form"`, `ref="uom.product_uom_tree_view"` →
`ref="uom.uom_uom_view_list"`. The `//field[@name='name']` xpath inside still resolves
([uom_uom_views.xml:24](../addons/uom/views/uom_uom_views.xml#L24)).

**V9 — view priority.** [sale_order_views.xml](../custom_addons/gec_odoo_modules/rs_waybill/views/sale_order_views.xml)
gained `<field name="priority">25</field>` on the view that inherits `sale.view_order_form`, so it
applies after `sale_stock`'s priority-20 extension and the `action_view_delivery` button exists by then.
This is the standard core idiom — `sale_project`, `sale_expense` and others do the same.

**V10 — `<column>` anchors.** Two xpaths re-anchored:

```diff
-<xpath expr="//field[@name='order_line']/list/field[@name='product_id']" position="after">
+<xpath expr="//field[@name='order_line']/list/column[@name='product_and_description']" position="after">
```
```diff
-<xpath expr="//field[@name='move_ids']/list/field[@name='product_id']" position="attributes">
+<xpath expr="//field[@name='move_ids']/list//field[@name='product_id']" position="attributes">
```

The first inserts `bar_code` as its own list column after the product column; the second is a
`position="attributes"` edit, so a descendant axis is enough. `product_uom_qty` and `quantity` are still
direct `<list>` children and needed no change.

**A pre-flight that is worth reusing:** parse every inherited view in the three modules, load the base
parent arch out of core XML, and run each `xpath expr` against it. It caught V10 before the installer
did and gave exactly one false positive (V9's button, which comes from a sibling extension rather than
the base arch). It does not model sibling extensions or priorities, so it narrows the install-fail loop
rather than replacing it.

### G8 — what is still not done

- **The test suite is not ported.** Seven files still use removed APIs: `company_registry` in
  `common.py`, `test_display_names.py`, `test_sync_resilience.py`, `test_sync_users.py`,
  `test_data_integrity.py`, `test_live_view_drift.py`; `get_param`/`set_param` in `test_sync_users.py`
  and `test_company_settings.py`. They will fail on 20.0 until ported the same way as G6/G7.
- **G5** (`_name_search` → `_search_display_name`) is not applied — it restores a feature that has never
  worked rather than fixing a break.
- **The OWL dashboard is not runtime-verified.** `useState` → `proxy` and the 8 `t-esc` → `t-out` are
  applied and every surrounding API was confirmed to still exist in 20.0, but the KPI cards have not
  been opened in a browser.
- **`_sql_constraints` still warns** at every load. That is plan item **#33**, unchanged from 19.0.
- **#40 still needs re-deriving** before anyone acts on it (section C).

### G9 — nested `next` actions crash the web client (fixed; **not** a 20.0 change)

Found 2026-09-22 by clicking *Import Selected* on the rs.ge Buyer Inbox with no matching vendor:

```
TypeError: Cannot read properties of undefined (reading 'map')
    at _preprocessAction (web.assets_web.min.js)
    at doAction / doActionButton
```

The warning notification is shown first and is correct; the crash is the action that runs *after* it.

**Mechanism.** `call_button` passes the returned action through `clean_action`, which calls
`generate_views()` to build `views` from `view_mode` when it is missing
([utils.py:40-43](../addons/web/controllers/utils.py#L40), [122-157](../addons/web/controllers/utils.py#L122)).
It only does this for the **top-level** action. When the top level is an
`ir.actions.client` / `display_notification`, the action nested under `params.next` is never touched.
The client then reads `action.views.map(...)` unconditionally for any `ir.actions.act_window`
([action_plugin.js:476](../addons/web/static/src/webclient/actions/action_plugin.js#L476)), and a
`next` carrying only `view_mode` has no `views`.

**This is not a 20.0 regression.** `_preprocessAction` is byte-identical between 19.0
(`action_service.js:418`) and 20.0 (`action_plugin.js:452`) — verified by diff — and `display_notification`
returns `params.next` the same way in both. The branch simply had not been hit before: it needs
*Import Selected* to create **zero** bills.

**Fix — spell `views` out on any action used as a nested `next`:**

- [rs_buyer_inbox_wizard.py:406](../custom_addons/gec_odoo_modules/rs_einvoice/models/rs_buyer_inbox_wizard.py#L406) — the "no bills imported" warning's `next` **was removed entirely**. Adding `views` made it work, and working turned out to be wrong: the wizard is opened as a page, so a `target='new'` re-open stacked a second copy of it on top. `_executeClientAction` only navigates when the notification returns a `next` ([action_plugin.js:1391](../addons/web/static/src/webclient/actions/action_plugin.js#L1391), identical in 19.0), so with no `next` the toast shows and the operator stays on the wizard they are already looking at — which is what the `next` was trying to achieve.
- [rs_replace_preview_wizard.py:131](../custom_addons/gec_odoo_modules/rs_einvoice/models/rs_replace_preview_wizard.py#L131) — `_open_drafts_action()` is returned directly in one place (safe) and as a `next` in another (not): added `'views': [(False, 'form')]` and `[(False, 'list'), (False, 'form')]` to its two branches.

The other five nested `next` values in the three modules are `ir.actions.act_window_close` or
`ir.actions.client` / `soft_reload`, which carry no `views` requirement and need no change.

**Two rules for this codebase:**

1. An `act_window` dict that can end up under `params.next` must carry an explicit `views`;
   `view_mode` alone is only enough for an action returned at the top level.
2. Use `next` only for *intentional navigation* (opening the records you just created). A `next` that
   re-opens the wizard the operator is already in duplicates it instead of refreshing it — omit `next`
   and the view simply stays put.

**The underlying message was right, and the flow had a trap in it.** `_rs_find_partner_by_tin`
([rs_buyer_inbox_wizard.py:106](../custom_addons/gec_odoo_modules/rs_einvoice/models/rs_buyer_inbox_wizard.py#L106))
searches `vat`; the partner carrying TIN 12345678910 on gec20_prod1 was created at 16:00:27, two
minutes *after* the 15:58:13 failure — i.e. the operator created it **because** of the message.

`partner_id` on the inbox line was a plain stored m2o, resolved once when *Search rs.ge* built the row.
So creating the vendor the message asks for changed nothing until the whole search was re-run, and the
same message came back. Measured on gec20_prod1: 89 lines stuck with an empty `partner_id`, all stamped
15:57:56, while the lookup run against the live database returns `res.partner(6,) satesto k`.

**Fixed:** `_do_import` now retries `_rs_find_partner_by_tin` when the stored match is empty, before
giving up ([rs_buyer_inbox_wizard.py:494](../custom_addons/gec_odoo_modules/rs_einvoice/models/rs_buyer_inbox_wizard.py#L494)),
reusing the search path's own ambiguity wording. A vendor created in response to the message now works
on the next *Import Selected* without re-running the search.

## Re-verification against the re-uploaded rs_waybill — 2026-09-19

A second copy of `rs_waybill` was committed to `gec_odoo_modules` today (`c61d118 "Added rs_waybill"`, 2026-09-19 14:52). It carries **no code change**: `diff -r` between the old `gec_rs_waybill/rs_waybill` copy and [gec_odoo_modules/rs_waybill](../custom_addons/gec_odoo_modules/rs_waybill) exits 0 with empty output over all 78 files (py, xml, csv, js, scss, po, png); the only addition is a `README.md` carried over from the old repo (titled `# gec_rs_waybill`, dated 2026-08-13). The source repo's HEAD is still `f086e17 "fix & optimization"` (2026-08-13) with nothing newer on its remote.

**All 37 rs_waybill items below (1, 15-31, 34-36, 50-62, 66-68) are therefore unchanged.** Spot-verified at identical line numbers in the new copy: #1 ([__manifest__.py:13](../custom_addons/gec_odoo_modules/rs_waybill/__manifest__.py#L13)), #15 ([rs_waybill.py:1853](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1853)), #16 ([1459](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1459)), #17 ([1271](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1271)), #22 ([1790](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1790)), #23 ([stock_picking.py:129](../custom_addons/gec_odoo_modules/rs_waybill/models/stock_picking.py#L129)), #26 ([rs_waybill_sync.py:506](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill_sync.py#L506)), #28 ([stock_picking.py:194](../custom_addons/gec_odoo_modules/rs_waybill/models/stock_picking.py#L194)), #29 ([stock_picking.py:543](../custom_addons/gec_odoo_modules/rs_waybill/models/stock_picking.py#L543)), #30 ([rs_waybill_sync.py:796](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill_sync.py#L796) + [product_product.py:293,374](../custom_addons/gec_odoo_modules/rs_waybill/models/product_product.py#L293), `is_storable` absent module-wide), #34 (`rs_waybill.enable_stock` still read by nothing outside the settings view), #35 ([rs_waybill_sync.py:694](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill_sync.py#L694)), #36 ([ir.model.access.csv:2](../custom_addons/gec_odoo_modules/rs_waybill/security/ir.model.access.csv#L2)), #62 ([rs_waybill.py:1425,1866](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1425)), #66 (`_rs_assert_not_invoice_linked` occurs 0 times in rs_waybill; still only the 4 actions at [rs_base_methods/rs_waybill.py:82-95](../custom_addons/gec_odoo_modules/rs_base_methods/models/rs_waybill.py#L82)), #67 ([rs_waybill_sync.py:1096](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill_sync.py#L1096), no `company_id` in `_map_rs_waybill_vals`), #68 ([rs_waybill_sync.py:727](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill_sync.py#L727)).

**#1 (dependency cycle) was fixed and removed from this file on 2026-09-19.** One residual from it is still open: [rs_waybill_soap_service.py:34](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill_soap_service.py#L34) calls `self.env.user._get_rs_credentials()` bare, so `rs_waybill` installed without `rs_base_methods` raises `AttributeError` on every rs.ge call instead of a readable UserError.

One thing changed for the worse:

- **Duplicate copies — settled 2026-09-19.** `custom_addons/gec_odoo_modules` is the canonical folder (see the header). The older copies stay on disk but are dead: off `--addons-path`, never read, never edited. The former "duplicate module copies" item was removed from this file as a result.

## Priority table

| # | Prio | Module | Area | Issue |
|---|---|---|---|---|
| 3 | P0 | `rs_base_methods` | bridge | Vendor bills with waybill links: Accept / Status Update raise |
| 4 | P1 | `rs_einvoice` | accounting | Auto-cancel of paid invoices unreconciles payments |
| 5 | P1 | `rs_einvoice` | accounting | Status-8 cleanup runs once, never retried |
| 6 | P1 | `rs_einvoice` | accounting | Reissue copy doubles sale-order invoiced qty |
| 7 | P1 | `rs_einvoice` | accounting | Original + replacement both posted until buyer accepts |
| 8 | P1 | `rs_einvoice` | accounting | Supplier reissue loses PO links; empty replacement possible |
| 9 | P1 | `rs_einvoice` | accounting | Preview wizard bypasses the foreign-currency guard |
| 10 | P1 | `rs_einvoice` | accounting | Net advance settlement drops VAT residual |
| 11 | P1 | `rs_einvoice` | accounting | Reimport merge: name-only match, discount kept |
| 12 | P1 | `rs_einvoice` | accounting | Accept on rs.ge never compares bill to rs.ge lines |
| 13 | P1 | `rs_einvoice` | accounting | Pull writes invoice_date against the immutable guard |
| 14 | P1 | `rs_einvoice` | accounting | Line sync continues after failed delete / verify |
| 15 | P2 | `rs_waybill` | stock | Forced validation overwrites the first move line |
| 16 | P2 | `rs_waybill` | stock | Return quantity repeated per move |
| 17 | P2 | `rs_waybill` | stock/sale | Sale line quantity overwritten by one delivery |
| 18 | P2 | `rs_waybill` | stock | Reverse-created documents lack stock_move_id |
| 19 | P2 | `rs_waybill` | stock | Distribution load never leaves stock, remainder adds stock |
| 20 | P2 | `rs_waybill` | stock/purchase | Buyer reconcile partial, retry sees nothing |
| 21 | P2 | `rs_waybill` | stock | Return-decision popup not persisted on manual edit |
| 22 | P2 | `rs_waybill` | stock/purchase | Vendor decrease auto-ships goods back |
| 23 | P2 | `rs_waybill` | stock | Picking cancel cascade hits vendor waybills |
| 24 | P2 | `rs_waybill` | stock | rs.ge cancel committed, Odoo refuses, nothing flagged |
| 25 | P2 | `rs_waybill` | stock/sale/purchase | Type-5 returns carry no order links |
| 26 | P2 | `rs_waybill` | sync | Backfill builds documents for cancelled waybills |
| 27 | P2 | `rs_waybill` | sync | Failed rows fall behind the cursor |
| 28 | P2 | `rs_waybill` | multi-company | Waybill company taken from env.company |
| 29 | P2 | `rs_waybill` | stock | SOAP call inside picking write |
| 30 | P2 | `rs_waybill` | stock | Auto-created products not storable |
| 31 | P2 | `rs_waybill, rs_base_methods` | all | Price / discount / unit / currency not normalized [D] |
| 32 | P2 | `rs_base_methods` | bridge | Invoice wizard ignores the move → sale line link |
| 33 | P3 | `rs_base_methods` | tech | `_sql_constraints` ignored, no unique on link table |
| 34 | P3 | `rs_waybill` | tech | "Enable Stock Integration" switch is dead |
| 35 | P3 | `rs_waybill` | sync | Change detector ignores VAT type / unit |
| 36 | P3 | `rs_waybill` | security | Waybill ACL: delete for every internal user |
| 38 | P3 | `rs_einvoice` | accounting | 18% tax lookup may pick a price-included tax |


## Core-safety review — 2026-09-18

Question answered here: does each fix stay inside Odoo 19 core accounting / sale / stock logic, and does it keep rs.ge consistent. Rule applied: reuse the core mechanism (`copy(include_business_fields)`, `stock.return.picking`, the `stock.move.quantity` inverse, a delta write on `sale.order.line`) instead of a hand-built replica; add no user-facing validation — a check is acceptable only when it *skips an automatic destructive action*.

Verdicts: **OK** fix as written · **ADJUST** issue real, fix should change · **NO-VALIDATION** plan adds a check we do not want · **DECIDE** business rule first.

### Corrections to the text above (found while re-verifying)
- **#6 "Upselling" is wrong.** Upselling needs `qty_delivered > product_uom_qty` ([sale_order_line.py:1088-1091](../addons/sale/models/sale_order_line.py#L1088)); with invoiced 20 > ordered 10 the SO shows *Fully Invoiced* (1092).
- **#17 "half applied" is wrong.** The core error rolls the whole transaction back in both paths: the manual edit has no commit before the dispatch ([rs_waybill_actions.py:246-280](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill_actions.py#L246)), the sync rolls back per row ([rs_waybill_sync.py:580](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill_sync.py#L580)). The damage is the silent overwrite when core does *not* raise.
- **#24 "3 such pairs"** = 3 *active* waybills on *done* deliveries (the precondition), not 3 broken records. Today gec_modules2 has 0 cancelled-waybill / done-picking pairs.

### Verdict table

| # | Verdict | Core evidence / reason |
|---|---|---|
| 3 | OK | Module-internal. `Field.__set__` always calls `write` ([fields.py:1841-1845](../odoo/orm/fields.py#L1841)); the context flag alone fixes it — drop the "write only when the value differs" part |
| 4 | OK, change the recovery text | `_check_draftable` blocks only exchange-difference, cash-basis and hashed moves ([account_move.py:6090-6115](../addons/account/models/account_move.py#L6090)); `button_cancel` unreconciles (6136). The guard skips an automatic destructive action, it is not a user validation. The manual step for a paid original must be Odoo's own: **credit note (Skip rs.ge), reconciled with the replacement** — the module already treats `reversal_move_ids` as neutralised ([account_move.py:857](../custom_addons/gec_odoo_modules/rs_einvoice/models/account_move.py#L857), [sync.py:121](../custom_addons/gec_odoo_modules/rs_einvoice/models/account_move_sync.py#L121)). Do not tell accountants to unreconcile a received payment. |
| 5 | OK | Target method is already state-idempotent (855-858) |
| 6 | **ADJUST → take (a)** | Drafts count in `qty_invoiced` ([sale_order_line.py:1000](../addons/sale/models/sale_order_line.py#L1000)) and core's own credit note uses the same `include_business_fields` copy ([account_move.py:5428](../addons/account/models/account_move.py#L5428)), so the copy itself is the Odoo way. Option (b) detaches the replacement from the SO — `invoice_ids`, the Invoices smart button, `qty_to_invoice`, the analytic default all hang on `sale_line_ids` — and re-linking by product is a hand-built `_create_invoices`. Take (a) + the #7 flag. For 6 → 2: cancel the stranded replacement if it is still draft and never sent (`rs_einv_id` empty), otherwise flag it. |
| 7 | OK | Informational stored compute, no validation |
| 8 | OK | Same copy mechanism core uses for credit notes; purchase copies `purchase_line_id` under it ([account_invoice.py:529-532](../addons/purchase/models/account_invoice.py#L529)); cancel + copy in one transaction, so no over-billed PO window |
| 9 | OK | Moves an existing check, adds none |
| 10 | OK | rs.ge payload only, Odoo entries untouched |
| 11 | OK | One `Char` on `account.move.line` is the smallest stable key; `discount: 0.0` is right because the rs.ge price is already net |
| 12 | **NO-VALIDATION** | Make the wrong value impossible instead: in `action_rs_buyer_accept` pull the rs.ge lines *before* the draft is posted (move [buyer.py:343-344](../custom_addons/gec_odoo_modules/rs_einvoice/models/account_move_buyer.py#L343) above the post at 327) and run `_rs_merge_pulled_to_bill_lines` — it realigns qty/price/taxes and keeps operator metadata (247). An already-posted mismatch gets an `_rs_log` warning, exactly like the invoice_date case (190-197). No raise. |
| 13 | OK | Removing a block on a draft = core behaviour (drafts are editable). Narrower alternative if the block must stay for manual edits: let Pull write with the existing `rs_allow_post_send_edit` bypass (1387) |
| 14 | OK | Handling an I/O failure is not a data validation |
| 15 | **ADJUST** | Use the core inverse: `move.quantity = move.product_uom_qty; move.picked = True` ([stock_move.py:171](../addons/stock/models/stock_move.py#L171), [439-478](../addons/stock/models/stock_move.py#L439), [2377](../addons/stock/models/stock_move.py#L2377)). It spreads the quantity over existing lots/packages and applies putaway; gap arithmetic on `move_line_ids[0]` is a replica of it. Keep the direct move-line edits only in the *done* branch (1370-1379), where core's own UI edits done lines the same way. `moves._action_done()` on a subset is core-internal API (`stock.picking._action_done` calls it, [stock_picking.py:1273](../addons/stock/models/stock_picking.py#L1273)) — acceptable. |
| 16 | OK | Core return wizard stays; only the per-line quantity changes |
| 17 | OK | The delta is what a user edit does; `_update_line_quantity` ([sale_stock:419](../addons/sale_stock/models/sale_order_line.py#L419)) still protects; move-first keeps `_action_launch_stock_rule` (369-397) from re-procuring |
| 18 | OK | Module link only |
| 19 | DECIDE | The transit-location model is core's internal-transfer pattern |
| 20 | OK | Savepoint = core partial-failure pattern; no commit inside the block |
| 21 | OK | |
| 22 | **ADJUST** | Use `stock.return.picking` on the receipt. Core then sets `origin_returned_move_id` ([stock_picking_return.py:39](../addons/stock/wizard/stock_picking_return.py#L39)), `purchase_line_id` + partner ([purchase_stock/models/stock.py:128-132](../addons/purchase_stock/models/stock.py#L128)) and `to_refund` ([stock_account wizard:10-15](../addons/stock_account/wizard/stock_picking_return.py#L10)), and `_prepare_qty_received` counts it ([purchase_order_line.py:65-67](../addons/purchase_stock/models/purchase_order_line.py#L65)). Leave the return *Ready*; the warehouse validates. |
| 23 | OK | |
| 24 | OK | Check core (`stock_move.py:2032`) before the rs.ge call |
| 25 | **ADJUST** | Same as #22 for both directions: the wizard on the original picking sets `sale_line_id` ([sale_stock wizard:11-12](../addons/sale_stock/wizard/stock_picking_return.py#L11)) / `purchase_line_id`; hand-built moves miss `origin_returned_move_id` and are invisible to `qty_delivered` / `qty_received` |
| 26 | OK | |
| 27 | OK | |
| 28 | OK | Document company, not `env.company` — core multi-company rule |
| 29 | OK | No I/O inside `write` |
| 30 | OK, confirm the business rule | A value passed to `create` wins; the compute only forces False for non-consumables ([product.py:860-861](../addons/stock/models/product.py#L860)). Right only if every rs.ge good is a tracked physical product |
| 31 | DECIDE | |
| 32 | OK | `stock_move_id.sale_line_id` is the link core invoicing itself uses |
| 33 | OK | v19 `models.Constraint`; 0 duplicates in gec_modules2, so the upgrade adds it cleanly |
| 34 | OK | Prefer removing the dead switches — a setting nothing reads |
| 35 | OK | |
| 36 | OK | Access rights are security, not validation |
| 38 | OK | `price_include` is computed with a `search=` method in v19 ([account_tax.py:137-140](../addons/account/models/account_tax.py#L137)), so the domain works |

### Root design note (#4–#7)
The module voids a document with `button_draft` + `button_cancel`. Core permits that, but core's own meaning of it is "this invoice was never really issued"; the Odoo-native way to void an invoice the buyer has seen is a credit note. The 2026-06-08 decision removed the *up-front* credit note because a rejection would have to undo it. That objection does not exist at status 7 / 8, which are terminal. Keep cancel for unpaid originals (the books end identical, no reconciliation is touched). For paid or partially paid originals the manual step is a credit note marked Skip rs.ge, reconciled against the replacement — no unreconciliation of a received payment. No code beyond #4 is needed for this; it is the wording of the activity.

### How to provoke — conventions
Run every step on a copy of gec_modules2 (already a test DB, not production) — copy it anyway so nothing here touches the shared test data: `createdb -T gec_modules2 <copy>`. **Shell** = call the module method the rs.ge event would trigger, so no rs.ge account is needed. **rs.ge** = needs a test rs.ge account. Each issue below has a *Provoke* line.

---

## P0 — fix before anything else

### 3. Vendor bills with waybill links cannot be accepted [C]
- **Module.** `rs_base_methods`
- **Issue.** [B/models/account_move.py:204-228](../custom_addons/gec_odoo_modules/rs_base_methods/models/account_move.py#L204) assigns `link.sync_state` etc. without `rs_auto_sync`; the link model's `write` raises for vendor bills without that context ([B/models/rs_einvoice_waybill_link.py:224-231](../custom_addons/gec_odoo_modules/rs_base_methods/models/rs_einvoice_waybill_link.py#L224)). Field assignment always calls `write`, even with the same value ([fields.py:1845](../odoo/orm/fields.py#L1845)).
- **Effect.** Pull bill → Sync Waybills adds one link → Status Update or Accept on rs.ge (Accept refreshes first, `E/models/account_move_buyer.py:311`) → "Waybill links on vendor bills are managed by Sync Waybills and cannot be edited manually". Bill stuck. Latent in gec_modules2 (its 10 links are on customer invoices).
- **Provoke.** rs.ge: Pull a vendor bill, Sync Waybills so one link exists, click Status Update → "Waybill links on vendor bills are managed by Sync Waybills…". Shell: on any link whose move is a vendor bill run `link.sync_state = 'synced'` without context → same error; that is the write `_rs_refresh_waybill_links` performs at B/account_move.py:206.
- **Fix.** In `_rs_refresh_waybill_links` iterate `self.rs_einv_waybill_link_ids.with_context(rs_auto_sync=True)` and write only when the value differs. Same context in the `action_rs_delete` override (263).
- **Review.** OK. The context flag alone is the fix; skip the "write only when the value differs" part.

---

## P1 — accounting

### 4. Auto-cancel of paid invoices unreconciles payments [C]
- **Module.** `rs_einvoice`
- **Issue.** [E/models/account_move.py:785-849](../custom_addons/gec_odoo_modules/rs_einvoice/models/account_move.py#L785) `_rs_auto_cancel_after_rs_cancellation` calls `button_draft` + `button_cancel` and assumes Odoo refuses paid invoices. Odoo 19 `button_draft` refuses only exchange-difference, cash-basis and hashed moves ([account_move.py:6090-6115](../addons/account/models/account_move.py#L6090)); `button_cancel` unreconciles every line ([6136](../addons/account/models/account_move.py#L6136)).
- **When.** Status 7 = buyer confirmed our cancellation (`E/models/account_move_sync.py:118`), status 8 = buyer accepted a Correct & Reissue (`account_move.py:851`, `sync.py:113/230`), and the recovery cron.
- **Example.** INV/001, 118 GEL, paid. Correction accepted → INV/001 reset and cancelled, payment 118 now unallocated, INV/002 (80) open and unpaid. Receivables and cash allocation wrong, no error. gec_modules2 has 24 posted invoices at status 2/3 with partial payment.
- **Provoke.** Post a customer invoice and register a full payment. Shell: `inv._rs_auto_cancel_after_rs_cancellation()` → `inv.state == 'cancel'`, the payment is no longer reconciled (Customers → Payments) and the receivable shows it as an open credit.
- **Fix.** First lines of `_rs_auto_cancel_after_rs_cancellation`:
```python
if self.payment_state != 'not_paid':
    self._rs_log("rs.ge cancelled/superseded this document but it has payments — cancel manually.", 'error')
    self._rs_schedule_manual_reversal_activity(reason=_("payments are reconciled"))
    return
```
Same rule the buyer side already applies (`E/models/account_move_buyer.py:435-448`). The accountant unreconciles and re-applies the payment to the replacement.
- **Review.** OK — the guard skips an automatic destructive action, it is not a user validation. Change the activity text: the recovery for a paid original is a credit note marked Skip rs.ge, reconciled with the replacement (the module already treats `reversal_move_ids` as neutralised), not an unreconciliation of a received payment.

### 5. Status-8 cleanup never retried [C]
- **Module.** `rs_einvoice`
- **Issue.** `_rs_neutralize_after_correction_accepted` fires only on the transition 4/5 → 8 ([E/models/account_move_sync.py:113-117](../custom_addons/gec_odoo_modules/rs_einvoice/models/account_move_sync.py#L113), 230-233). If the cancel fails (#4 guard, locked period) the next refresh sees 8 → 8 and does nothing. The recovery cron handles status 7 only (`E/models/rs_buyer_inbox_wizard.py:1029-1035`).
- **Effect.** Original and accepted correction stay posted together: double revenue and VAT, permanently.
- **Provoke.** rs.ge: Correct & Reissue, post and send the correction. Make the original un-cancellable: on the sales journal enable *Lock Posted Entries with Hash* and click Lock on the original (`inalterable_hash` → `_check_draftable` raises). Buyer accepts (status 8) → Status Update → activity "cancel manually". Click Status Update again → nothing happens, original still posted. The trigger fires only on `previous_status in ('4','5')` (sync.py:113-117).
- **Fix.** Make it state-based: in `action_rs_refresh_status`, after the status write, `if status == '8' and self.rs_einv_replacement_mode == 'correction' and self.rs_einv_replaces_id.state == 'posted': self.rs_einv_replaces_id._rs_neutralize_after_correction_accepted()` (already idempotent). Add the same case to `_cron_rs_recover_stranded_cancellations`. Dedupe the activity with `rs_einv_reversal_pending_at` as status 7 does.

### 6. Reissue copy doubles the sale-order invoiced quantity [C]
- **Module.** `rs_einvoice`
- **Issue.** Both reissue flows copy the invoice with `include_business_fields=True` ([E/models/rs_replace_orchestrator.py:143, 206](../custom_addons/gec_odoo_modules/rs_einvoice/models/rs_replace_orchestrator.py#L143)). Sale copies `sale_line_ids` under that flag ([sale/account_move_line.py:36-39](../addons/sale/models/account_move_line.py#L36)); `qty_invoiced` counts every non-cancelled invoice line, drafts included ([sale_order_line.py:996-1000](../addons/sale/models/sale_order_line.py#L996)).
- **Example.** SO line 10 invoiced by INV/001. Correct & Reissue → SO shows invoiced 20, status "Fully invoiced" or "Upselling", until INV/001 is cancelled (days or weeks; forever if the buyer rejects a Cancel & Reissue and the draft is stranded).
- **Provoke.** SO with 10 units → invoice → post. Shell: `inv.with_context(include_business_fields=True).copy({})` (what the orchestrator does at 143/206) → SO line Invoiced Qty = 20, Invoice Status *Fully Invoiced*, Invoices smart button = 2. No rs.ge needed.
- **Fix [D].** (a) Accept the window and make it visible (#7). (b) Clear links on the copy: `new_invoice.invoice_line_ids.write({'sale_line_ids': [Command.clear()]})`, then in the success branch of `_rs_auto_cancel_after_rs_cancellation` (the bridge already hooks there for waybill links, `B/models/account_move.py:301-307`) move `sale_line_ids` from the original's lines to the replacement's lines matched by product; log unmatched lines. (b) keeps the SO right at all times but needs the correction lines to stay product-compatible. Also handle 6 → 2 (buyer rejected the cancellation, `sync.py:97-112`): cancel or flag the stranded replacement draft.
- **Review.** ADJUST — take (a). Option (b) detaches the replacement from the SO (`invoice_ids`, Invoices smart button, `qty_to_invoice`, analytic default) and re-links by product = a hand-built `_create_invoices`. The copy itself is core's own mechanism (credit notes use it, `account_move.py:5428`). "Upselling" does not occur: it needs delivered > ordered; the SO shows Fully Invoiced. For 6 → 2 cancel the stranded draft only if never sent (`rs_einv_id` empty), else flag.

### 7. Both invoices posted during the acceptance window [C, by design]
- **Module.** `rs_einvoice`
- **Issue.** Original is neutralised only at status 8 (`E/models/rs_replace_orchestrator.py:182-193`, `account_move.py:851`).
- **Example.** Original 100, corrected 80 → 180 posted for days; a month-end close inside the window double-counts revenue, VAT and receivables.
- **Provoke.** rs.ge: Correct & Reissue, post the correction, do not accept yet. Accounting → Invoices, filter Posted → both listed; Reporting → Tax Report for the month → VAT counted twice. Shell: `env['account.move'].search([('rs_einv_replaces_id.state','=','posted'),('state','=','posted')])`.
- **Fix.** No code change without redesign (rs.ge needs the replacement posted). Add a stored boolean `rs_einv_correction_in_flight` on the original (True while `rs_einv_replaced_by_id.rs_einv_status in ('4','5')`), a list filter, and a line in the daily deadline cron so accountants exclude these at close.

### 8. Supplier reissue loses PO links; empty replacement possible [C]
- **Module.** `rs_einvoice`
- **Issue.** [E/models/account_move_buyer.py:563-631](../custom_addons/gec_odoo_modules/rs_einvoice/models/account_move_buyer.py#L563) cancels the original bill, then creates a bare bill from rs.ge rows: no `product_id`, `purchase_line_id`, analytic. A failed line pull is caught (614-624).
- **Effect.** Original cancelled → PO `qty_invoiced` drops → PO is "To Bill" again → a second bill from the PO = double payable. Replacement can be an empty draft.
- **Provoke.** PO 10 → receive → Create Bill → post. On the bill: Reset to Draft, Cancel → PO Billing Status back to *Waiting Bills*, Create Bill offers 10 again — that is what the supplier reissue does at buyer.py:567-568 before the bare `create()` at 600-606. Empty case: make `_rs_refresh_pulled_lines` raise (shell monkeypatch) → caught at 614-624, `new_draft.invoice_line_ids` empty.
- **Fix.** Reorder and copy: 1) `_rs_refresh_pulled_lines(service, raise_on_failure=True)` on the original **before** any change; 2) `new_draft = self.with_context(include_business_fields=True).copy({...})` keeps purchase links, products, analytics (purchase copies `purchase_line_id` under that flag, [purchase/account_invoice.py:529-532](../addons/purchase/models/account_invoice.py#L529)); 3) apply rs.ge qty/price with `_rs_merge_pulled_to_bill_lines` (after #11); 4) then reset and cancel the original.

### 9. Preview wizard bypasses the currency guard [C]
- **Module.** `rs_einvoice`
- **Issue.** The GEL-only check lives in `action_rs_import_supplier_correction` (`E/models/account_move_buyer.py:728-737`); the inbox preview calls `_rs_execute_cancel_and_reissue` directly ([rs_replace_preview_wizard.py:62](../custom_addons/gec_odoo_modules/rs_einvoice/models/rs_replace_preview_wizard.py#L62)); the replacement copies `currency_id` (604) but imports GEL amounts unchanged.
- **Example.** USD bill, correction 118 GEL → replacement 118 USD.
- **Provoke.** rs.ge: vendor bill in USD linked to rs.ge → Buyer Inbox → tick its correction row → Preview → Execute: no currency error, replacement created in USD with the GEL figures. Compare the guard in `action_rs_import_supplier_correction` (728-737) with the preview call (wizard:62).
- **Fix.** Move the currency check into `_rs_execute_cancel_and_reissue`, right after the blockers (506), so every entry point shares it.

### 10. Net advance settlement drops the VAT residual [C]
- **Module.** `rs_einvoice`
- **Issue.** [E/models/account_move_sync.py:488-527](../custom_addons/gec_odoo_modules/rs_einvoice/models/account_move_sync.py#L488) scales each line's VAT by adjusted/original gross, then puts the whole VAT residual on the **last** taxable line and clamps at 0 (519-526).
- **Example.** Taxable 118 + 118 (VAT 18 each), exempt 236, down-payment offset 236 incl. VAT 36. Target VAT = 0. Scaled VAT 9 + 9 = 18; residual −18 → last line max(9−18, 0) = 0 → rs.ge receives VAT 9, Odoo has 0.
- **Provoke.** Shell, no rs.ge: customer invoice with lines A 100 + 18%, B 100 + 18%, C 200 exempt and a down-payment offset of −236 incl. 18% VAT, advance settlement mode Net. Call `inv._rs_get_lines_payload()` (sync.py:425) and print `vat_amount` per row → one taxable row still carries VAT 9 while the invoice's VAT total is 0.
- **Fix.** Allocate offset VAT by VAT share, not gross share:
```python
vat_share = total_offset_vat / total_regular_vat if total_regular_vat else 0.0
for p in payloads:
    if p['vat_amount'] > 0:
        p['vat_amount'] = self._rs_round(p['vat_amount'] * (1 - vat_share), 2)
```
then spread the remaining cents over all taxable lines in a loop instead of clamping one line.

### 11. Reimport merge: name-only match, discount kept [C]
- **Module.** `rs_einvoice`
- **Issue.** `_rs_merge_pulled_to_bill_lines` ([E/models/account_move_buyer.py:246-298](../custom_addons/gec_odoo_modules/rs_einvoice/models/account_move_buyer.py#L246)) keys rows by lowercased description and keeps the first; `_rs_pulled_line_vals` (`sync.py:623-640`) writes `price_unit` but not `discount`.
- **Example.** Two rs.ge lines "Delivery" → one bill line, the other deleted as "no longer on rs.ge". Line with 10% discount → rs.ge net price 90 kept with 10% → 81.
- **Provoke.** Shell: on a draft pulled vendor bill create two `rs_einv_pulled_line_ids` snapshots with the same `goods` text (different `rs_line_id` and `full_amount`) and give one bill line `discount = 10`; run `bill._rs_merge_pulled_to_bill_lines()` → one bill line left for the pair (RS Logs: "removed 1 bill line(s)"), and the discounted line keeps 10% on the rs.ge net price.
- **Fix.** Add `rs_line_id = fields.Char(copy=False)` on `account.move.line`, set it from `snap.rs_line_id`, match on it first (name + occurrence index as fallback). Add `'discount': 0.0` to the vals.

### 12. Accept never compares the bill to rs.ge lines [C]
- **Module.** `rs_einvoice`
- **Issue.** `action_rs_buyer_accept` refreshes the snapshot (`E/models/account_move_buyer.py:344`) but never checks that bill lines equal it.
- **Effect.** Operator edits amounts, posts, accepts → booked input VAT ≠ what rs.ge certifies.
- **Provoke.** rs.ge: Pull a bill, change one line's unit price, post, Accept on rs.ge → accepted without complaint. Then compare `sum(bill.invoice_line_ids.mapped('price_total'))` with `sum(bill.rs_einv_pulled_line_ids.mapped('full_amount'))`.
- **Fix.** After the refresh: compare Σ`price_total` of product lines vs Σ`full_amount`, and Σ(`price_total` − `price_subtotal`) vs Σ`drg_amount`; raise when the difference exceeds 0.01 × lines unless `context.get('rs_force_accept')`.
- **Review.** NO-VALIDATION. Pull the rs.ge lines before the draft is posted (move 343-344 above the post at 327) and run `_rs_merge_pulled_to_bill_lines` so the lines *are* the rs.ge lines; a posted mismatch gets an `_rs_log` warning like the invoice_date case (190-197). No raise.

### 13. Pull writes invoice_date against the immutable guard [C]
- **Module.** `rs_einvoice`
- **Issue.** `action_rs_buyer_pull` sets `invoice_date` on drafts (`E/models/account_move_buyer.py:189`); the write guard refuses `invoice_date` changes on any move with an rs.ge ID (`E/models/account_move.py:1384-1414`).
- **Effect.** Manual Pull on a draft bill dated differently from the rs.ge operation date → "Cannot change 'invoice_date' … Delete it on RS first". Inbox imports pass only because the date already matches.
- **Provoke.** Shell, no rs.ge: draft vendor bill with `rs_einv_id` set; `bill.invoice_date = bill.invoice_date + timedelta(days=1)` → "Cannot change 'invoice_date' … Delete it on RS first". That is the write Pull performs at buyer.py:189.
- **Fix.** In the guard skip buyer-side drafts: `if not move.rs_einv_id or move.rs_einv_skip or (move.rs_einv_is_buyer_side and move.state == 'draft'): continue`.
- **Review.** OK. Narrower alternative if manual edits must stay blocked: let Pull write under the existing `rs_allow_post_send_edit` bypass (1387).

### 14. Line sync continues after failed delete / verify [C]
- **Module.** `rs_einvoice`
- **Issue.** `_rs_sync_lines`: obsolete-slot delete errors are only logged ([E/models/account_move_sync.py:378-391](../custom_addons/gec_odoo_modules/rs_einvoice/models/account_move_sync.py#L378)); a failed verification read returns normally (393-402).
- **Effect.** Send to buyer goes out while rs.ge still holds stale extra lines; buyer sees wrong totals.
- **Provoke.** Shell: delete one line of a sent invoice, make `service.delete_invoice_desc` raise (monkeypatch), click Update on RS → RS Logs show only a warning, the method returns, Send to buyer still allowed while rs.ge holds the extra line.
- **Fix.** Collect delete failures and raise after the loop; on verification failure set `rs_einv_lines_sync_state = 'partial'` and raise the existing count-mismatch error.

---

## P2 — stock, sale, purchase

### 15. Forced validation overwrites the first move line [C]
- **Module.** `rs_waybill`
- **Issue.** `_force_validate_moves` ([W/models/rs_waybill.py:1849-1866](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1849)) writes the full demand into `move_line_ids[0]` and marks all lines picked; same at 1414-1417.
- **Example.** Move lines 4 + 6, demand 10 → 10 + 6 = 16 received. Happens with lots, packages, putaway to several locations.
- **Provoke.** Receipt for 10 of a lot-tracked product; before validating, enter two move lines by hand (lot A 4, lot B 6). Shell: `wb._force_validate_moves(move)` → `move.quantity` = 16 (line A overwritten to 10, line B still 6), on-hand +16.
- **Fix.** Adjust only the gap, as the qty_up branch already does (1372-1374):
```python
gap = move.product_uom_qty - sum(move.move_line_ids.mapped('quantity'))
if gap:
    move.move_line_ids[0].quantity += gap
```
- **Review.** ADJUST. Use the core inverse `move.quantity = move.product_uom_qty; move.picked = True` (`stock_move.py:171, 439-478, 2377`) instead of touching `move_line_ids[0]`; it spreads over lots/packages and applies putaway. Keep direct move-line edits only in the done branch (1370-1379). `moves._action_done()` on a subset is core-internal API and acceptable.

### 16. Return quantity repeated per move [C]
- **Module.** `rs_waybill`
- **Issue.** `_create_return_picking` ([W/models/rs_waybill.py:1458-1459](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1458)) gives every return line of a product the whole product quantity.
- **Example.** Delivery has two moves of A (3 + 3); return 2 → return lines 2 + 2 = 4.
- **Provoke.** SO with product A on two lines (3 + 3) → deliver, validate → waybill completed. Shell: `wb._create_return_picking({A.id: 2}, create_waybill=False)` → the return picking has two moves of 2 = 4.
- **Fix.** Decrement per line: `take = min(remaining[pid], return_line.move_id.quantity); return_line.quantity = take; remaining[pid] -= take`.
- **20.0.** Superseded by [G2](#g2--v1-rewrite-_create_return_picking-on-the-picking-native-api): the wizard this fix edits no longer exists, and the G2 rewrite of `_create_return_picking` carries the per-move decrement.

### 17. Sale line quantity overwritten by one delivery [C]
- **Module.** `rs_waybill`
- **Issue.** `move.sale_line_id.product_uom_qty = d['new_qty']` ([W/models/rs_waybill.py:1271](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1271) and 1387): one delivery's quantity replaces the whole ordered quantity.
- **Example.** Order 10 split 4 + 6; edit the first waybill to 5 → SO line becomes 5. With a done backorder core raises "cannot be decreased below the amount already delivered" ([sale_order_line.py:419](../addons/sale_stock/models/sale_order_line.py#L419)); in the sync path stock was already changed, so the change is half applied.
- **Provoke.** SO 10; deliver 4, backorder 6, validate both → two completed waybills. Edit the first waybill 4 → 5 → core error "cannot be decreased below the amount already delivered" (the SO line is set to 5 while delivered is 11). Variant: leave the backorder open, edit the first to 5 → succeeds, SO ordered = 5; validate the backorder → delivered 11 vs ordered 5, no re-procurement.
- **Fix.** Apply the delta: `sol.product_uom_qty += d['new_qty'] - d['old_qty']` (both in the diff dict). Keep "move first, SO second" so no re-procurement happens.
- **Review.** OK. Correction to the Example: the core error rolls the whole transaction back in both paths, nothing is half-applied; the damage is the silent overwrite when core does not raise (variant in Provoke).

### 18. Reverse-created documents lack stock_move_id [C]
- **Module.** `rs_waybill`
- **Issue.** `_rs_create_so_and_delivery_from_waybill` (884-917) and `_rs_build_moves_on_picking` ([W/models/rs_waybill.py:1104-1120](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1104)) never set `line.stock_move_id`; correction branches skip lines without it (1261-1262, 1364-1366).
- **Effect.** rs.ge changes a quantity on a synced waybill → waybill shows 12, delivery and SO keep 10, no message.
- **Provoke.** Sync a seller waybill from rs.ge (buyer set, type 2, in scope) → SO + delivery auto-created. Shell: `wb.line_ids.mapped('stock_move_id')` → empty. Change a quantity on rs.ge and sync → delivery and SO unchanged, no message.
- **Fix.** In `_rs_build_moves_on_picking`: `line.stock_move_id = Move.create(...).id`. In `_rs_create_so_and_delivery_from_waybill` after `action_confirm`, match `delivery.move_ids` to lines by product (then sequence) and set `stock_move_id`.

### 19. Distribution load never leaves stock, remainder adds stock [C]
- **Module.** `rs_waybill`
- **Issue.** A type-4 parent without buyer creates no stock document (`_rs_create_documents_if_missing` 880 needs `buyer_id`); sub-waybills create SO + delivery each; the remainder creates a customer → warehouse receipt (873-875 → 1076). Several remainders allowed (`W/models/rs_waybill_actions.py:842-889`).
- **Example.** Load 10, sell 6, remainder 4 → Odoo −6 + 4 = −2; truth −6.
- **Provoke.** Type-4 distribution waybill, no buyer, 10 units, Activate → `wb.picking_id` empty, on-hand unchanged. Sub-waybill 6 to a buyer → SO + delivery, on-hand −6. Remainder waybill 4 → receipt customer → warehouse, on-hand −2 (truth −6). Create Remainder again → allowed.
- **Fix [D].** Model the truck: on parent activation an internal transfer stock → distribution/transit location; subs deliver from that location; remainder = internal transfer back, not a receipt. Make `_sub_available` subtract remainder waybills so only one can exist.

### 20. Buyer reconcile partial, retry sees nothing [C]
- **Module.** `rs_waybill`
- **Issue.** `_reconcile_buyer_goods` done branch ([W/models/rs_waybill.py:1745-1781](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1745)) writes PO lines, then validates moves; the `try/except` (1693, 1782) has no savepoint. Caller clears pending and confirms on rs.ge (`W/models/rs_waybill_actions.py:600-603`). Retry compares waybill vs PO **ordered** qty (1612-1638), now equal.
- **Effect.** PO = rs.ge, stock ≠ both, nothing left to retry.
- **Provoke.** Buyer waybill + PO + done receipt. Shell: monkeypatch `wb._force_validate_moves` to raise, then `wb._reconcile_buyer_goods({product.id: 2})` → PO line +2, chatter "reconcile could not complete"; `wb._compute_buyer_goods_delta()` → `{}`; receipt still 10 received.
- **Fix.** Wrap the branch in `with self.env.cr.savepoint():`; return False on failure; in `action_confirm_waybill` skip `confirm_waybill` and keep `pending_goods_json` when reconcile failed; for done receipts compare against `qty_received`.

### 21. Return-decision popup not persisted on manual edit [C]
- **Module.** `rs_waybill`
- **Issue.** `action_submit_edit_to_rs` clears the snapshot ([W/models/rs_waybill_actions.py:254](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill_actions.py#L254)), commits (280), opens the wizard (299-300) without saving `pending_return_json`.
- **Effect.** Close the popup → rs.ge already reduced, delivery still full, no button to come back.
- **Provoke.** rs.ge: completed seller waybill → Edit → reduce a quantity → Save → Return Decision popup → close it with X → `wb.pending_return_json` empty, no Reconcile Delivery button, rs.ge already at the lower quantity.
- **Fix.** Before returning the wizard: `self.pending_return_json = json.dumps({str(k): v for k, v in qty_to_return.items()})` (as the auto path does at `rs_waybill.py:1568-1576`). The wizard already clears it (`W/wizards/return_decision_wizard.py:27, 48`).

### 22. Vendor decrease auto-ships goods back [C]
- **Module.** `rs_waybill`
- **Issue.** `_reconcile_buyer_decrease_done` ([W/models/rs_waybill.py:1790-1838](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill.py#L1790)) creates **and validates** an outgoing picking to the vendor, with no waybill.
- **Effect.** Vendor fixes a typo on their waybill → Odoo ships goods out; stock wrong; movement undocumented.
- **Provoke.** Shell: buyer waybill with PO + done receipt; `wb._reconcile_buyer_decrease_done(po, product, 1, po_line)` → a new outgoing transfer to Partners/Vendors in state Done, on-hand −1, no waybill anywhere.
- **Fix.** Mirror the seller side: accumulate the decrease and open the Return Decision wizard on Receive (physical return → return picking left **Ready** for the warehouse; paperwork only → PO quantity only). At minimum stop calling `_force_validate_moves` there.
- **Review.** ADJUST. Use `stock.return.picking` on the receipt: core sets `origin_returned_move_id`, `purchase_line_id`, partner and `to_refund`, and `_prepare_qty_received` (purchase_stock 65-67) counts it. Leave the return Ready.
- **20.0.** Verdict unchanged, API changed: `stock.return.picking` is gone — build the return with `picking._create_return()` via the rewritten `_create_return_picking` ([G2](#g2--v1-rewrite-_create_return_picking-on-the-picking-native-api)). The four fields core sets still come for free (section B table), and "leave it Ready" is now the default.

### 23. Picking cancel cascade hits vendor waybills [C]
- **Module.** `rs_waybill`
- **Issue.** `stock.picking.action_cancel` ([W/models/stock_picking.py:129-157](../custom_addons/gec_odoo_modules/rs_waybill/models/stock_picking.py#L129)) refuses/deletes any linked waybill; `_action_done` filters seller direction only (575).
- **Effect.** Cancel a receipt or PO linked to a vendor waybill → `ref_waybill` on the vendor's document → **[L]** rs.ge −101 "another taxpayer" → cancel fails with an rs.ge error.
- **Provoke.** rs.ge: buyer-direction waybill linked to a receipt → cancel the receipt (or the PO) → the cascade calls `action_refuse_waybill` on the vendor's document. Without rs.ge: `targets = self.filtered('waybill_id')` at stock_picking.py:129 has no direction filter.
- **Fix.** `targets = self.filtered(lambda p: p.waybill_id and p.waybill_id.waybill_direction == 'seller')`. Buyer-direction pickings just cancel locally.

### 24. rs.ge cancel committed, Odoo refuses, nothing flagged [C]
- **Module.** `rs_waybill`
- **Issue.** Waybill Refuse: rs.ge refused → commit ([W/models/rs_waybill_actions.py:513-519](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill_actions.py#L513)) → the picking cascade is skipped when the picking is done (527). Picking Cancel: rs.ge first, commit, then core cancel (`stock_picking.py:129-157`), which refuses done moves ([stock_move.py:2033](../addons/stock/models/stock_move.py#L2033)).
- **Effect.** Active waybill on a done delivery → Refuse → rs.ge cancelled, goods still shipped in Odoo, no return, no flag. gec_modules2 has 3 such pairs.
- **Provoke.** The copy DB has 3 active waybills on done deliveries: `SELECT w.id FROM rs_waybill w JOIN stock_picking p ON p.id = w.picking_id WHERE w.state = 'active' AND p.state = 'done'`. rs.ge: Refuse one → cancelled on rs.ge and locally, picking stays Done, no return, no activity.
- **Fix.** In `action_refuse_waybill`, before the rs.ge call: `if self.picking_id.state == 'done': return self._action_reverse_completed_waybill()` (same as the completed branch at 503-504). In `stock.picking.action_cancel` refuse up front when any move is done, before touching rs.ge.
- **Review.** OK. "3 such pairs" = 3 active waybills on done deliveries (precondition); 0 broken records today.

### 25. Type-5 returns carry no order links [C]
- **Module.** `rs_waybill`
- **Issue.** `_rs_create_return_transfer_from_waybill` (1076-1101) and `_rs_create_return_delivery_from_waybill` (973-1026) build bare moves via `_rs_build_moves_on_picking`: no `origin_returned_move_id`, `sale_line_id`, `purchase_line_id`, `to_refund`.
- **Example.** Customer returns 4 of 10 via a synced type-5 → stock +4, SO still "delivered 10" → invoice 10. Vendor return → stock −4, PO still "received 10" → bill 10.
- **Provoke.** Seller type-5 return waybill synced from rs.ge for 4 units of a delivered SO → receipt created → Complete → on-hand +4, SO Delivered still 10, Create Invoice offers 10. Shell: `wb.picking_id.move_ids.mapped('origin_returned_move_id')` and `.mapped('sale_line_id')` both empty.
- **Fix.** Seller: find the original delivery (waybill's `sales_order_id`, or same buyer + products) and use `stock.return.picking` as `_create_return_picking` does (1441-1468). Buyer: set `purchase_line_id` and `to_refund=True` on the moves as 1827-1835 does, matching PO lines by product.
- **Review.** ADJUST. Same as #22: the return wizard on the original picking sets `sale_line_id` / `purchase_line_id` and `origin_returned_move_id`; hand-built moves are invisible to `qty_delivered` / `qty_received`.
- **20.0.** Same as #22 — the hooks moved onto `stock.picking._prepare_return_move_default_values`, so route both directions through [G2](#g2--v1-rewrite-_create_return_picking-on-the-picking-native-api) instead of the deleted wizard.

### 26. Backfill builds documents for cancelled waybills [C]
- **Module.** `rs_waybill`
- **Issue.** [W/models/rs_waybill_sync.py:506-515](../custom_addons/gec_odoo_modules/rs_waybill/models/rs_waybill_sync.py#L506) backfills existing in-scope waybills with no `state != 'cancelled'` check (the new-record branch has it at 546).
- **Effect.** A cancelled seller waybill synced earlier without documents gets a confirmed SO + delivery; only buyer-side documents are auto-cancelled.
- **Provoke.** Shell: pick a seller waybill with `state == 'cancelled'`, `buyer_id` set, `picking_id` empty and all lines mapped; `wb._rs_create_documents_if_missing()` → confirmed SO + delivery created.
- **Fix.** Add `and existing.state != 'cancelled'` at 506, plus `if self.state == 'cancelled': return` at the top of `_rs_create_documents_if_missing` (869).

### 27. Failed rows fall behind the cursor [C]
- **Module.** `rs_waybill`
- **Issue.** Per-row failure → rollback + continue (`W/models/rs_waybill_sync.py:578-584`); the cursor advances when the list fetches succeeded (386-389).
- **Effect.** A waybill that failed to import is never fetched again unless rs.ge modifies it.
- **Provoke.** Shell: monkeypatch `_sync_goods_lines` to raise for one rs_id, run the sync → log "… 1 FAILED", the company's cursor parameter advanced; the next sync does not fetch that waybill again.
- **Fix.** Return `failed_ids` from `_process_rs_rows`; if any, do not advance the cursor, or keep them in a parameter and retry them at the start of the next run.

### 28. Waybill company taken from env.company [C]
- **Module.** `rs_waybill`
- **Issue.** `_rs_try_create_waybill` vals ([W/models/stock_picking.py:194-206](../custom_addons/gec_odoo_modules/rs_waybill/models/stock_picking.py#L194), also 362-375, 465-475) omit `company_id`, `seller_tin`, `seller_name`; defaults use `env.company` (`rs_waybill.py:93-98`).
- **Effect.** Multi-company: the scheduler, or a user active in company A, reserves company B's delivery → waybill filed under A's TIN with A's credentials.
- **Provoke.** Two companies with rs.ge credentials. Company selector on A, open a company-B delivery (both allowed), Check Availability → the auto-created waybill has `company_id` = A and A's TIN in `seller_tin`.
- **Fix.** Add to all three dicts: `'company_id': self.company_id.id, 'seller_name': self.company_id.name, 'seller_tin': self.company_id.company_registry or self.company_id.vat`.

### 29. SOAP call inside picking write [C]
- **Module.** `rs_waybill`
- **Issue.** `_rs_resync_waybill_from_picking_type` calls `save_waybill` from `stock.picking.write` ([W/models/stock_picking.py:541-548](../custom_addons/gec_odoo_modules/rs_waybill/models/stock_picking.py#L541)).
- **Effect.** Changing the operation type mutates rs.ge; an rs.ge failure blocks the field edit.
- **Provoke.** Picking whose waybill is saved on rs.ge (`rs_internal_id` set, draft). Put wrong rs.ge credentials on your user, change the picking's Operation Type, Save → the save fails with the rs.ge error. With good credentials the rs.ge waybill changes on a picking field edit.
- **Fix.** Remove 541-548; update local fields only and post a chatter note "waybill changed, click Save on RS".

### 30. Auto-created products not storable [C]
- **Module.** `rs_waybill`
- **Issue.** Products created from rs.ge omit `is_storable` (`W/models/rs_waybill_sync.py:796-801`; `W/models/product_product.py:293-300, 374-378`); default is False ([product.py:787-789](../addons/stock/models/product.py#L787)).
- **Effect.** Goods flow through pickings without quants; on-hand never shows; no valuation.
- **Provoke.** Sync a buyer waybill with a barcode unknown to Odoo → product auto-created → Product form: *Track Inventory* unchecked. Receive → Inventory → On Hand shows nothing. gec_modules2 already has one: `SELECT id FROM product_template WHERE is_rs_product AND NOT is_storable`.
- **Fix.** Add `'is_storable': True` to the three create dicts.
- **Review.** OK once the business rule is confirmed: every rs.ge good is a tracked physical product. A value in `create` wins; the compute only forces False for non-consumables (`product.py:860-861`).
- **20.0.** Still true, but `is_storable` now lives in `product/models/product_template.py:127` (compute `_compute_is_storable`, `:477`). Watch the new `store_by` inverse, and note `tracking` no longer accepts `'none'` ([G4](#g4--v5-the-tracking--none-branch)).

### 31. Price / discount / unit / currency not normalized [C] [D]
- **Module.** `rs_waybill, rs_base_methods`
- **Issue.** Export: price = `sale_line.price_unit` (`W/models/stock_picking.py:217`), no discount, no currency; `UNIT_ID` from `product.uom_id` while quantity is in `move.product_uom` (`rs_waybill_soap_service.py:274` vs `stock_picking.py:223`). Import: waybill price → SO/PO `price_unit` with Odoo taxes added on top (`rs_waybill.py:905, 955`); waybill quantity into the product UoM without conversion (903-904, 954-956, 1113-1114). Bridge wizard: `lst_price` with the pricelist currency (`B/wizards/rs_invoice_from_waybill_wizard_line.py:155`, wizard 93-99). Price-only rs.ge changes are ignored by `_compute_line_diff`.
- **Effect [L].** If rs.ge prices include VAT, every auto-created SO, PO and later invoice is overstated by the VAT rate. Dozen vs unit: ×12 on stock and invoices. Discounted orders declare list price on the waybill.
- **Provoke.** SO with a 10% discount → deliver → waybill line price = undiscounted SO price. SO in USD → the same number is sent as GEL. Product in Dozen sold in Units → UNIT_ID from the product UoM (soap_service.py:274). Change only a price on rs.ge → sync → no diff (`_compute_line_diff` yields quantity types only, rs_waybill.py:1143-1176).
- **Fix.** Decide with the accountant whether the rs.ge waybill price is VAT-inclusive. Then: export `price_unit × (1 − discount/100)` converted to GEL and made VAT-inclusive with `tax_ids.compute_all` when required; import `rs_price / (1 + rate)` for VAT_TYPE 0 (or use price-included taxes); convert quantities with `move.product_uom._compute_quantity(qty, product.uom_id)` both ways and send `move.product_uom.rs_unit_id`; in the wizard convert `lst_price` with `currency._convert` or use the pricelist price.

### 32. Invoice wizard ignores the move → sale line link [C]
- **Module.** `rs_base_methods`
- **Issue.** `_match_sale_line` ([B/wizards/rs_invoice_from_waybill_wizard_line.py:91-142](../custom_addons/gec_odoo_modules/rs_base_methods/wizards/rs_invoice_from_waybill_wizard_line.py#L91)) searches SO lines by partner + product and takes the first; it never reads `waybill_line_id.stock_move_id.sale_line_id`. The over-delivery warning is per line (168-185).
- **Example.** SO: 5 A at 10 and 5 A at 20. Both waybill lines match the first line → invoice 10 A at 10; `qty_invoiced` misallocated; no warning.
- **Provoke.** SO: 5 A @ 10 and 5 A @ 20 → deliver → waybill → Create Invoice from Waybill → both wizard lines matched to the first SO line → invoice 10 A @ 10; SO line 2 Invoiced Qty 0, line 1 Invoiced Qty 10.
- **Fix.** First statement of `_match_sale_line`: `sol = wb_line.stock_move_id.sale_line_id; if sol: return sol`, keep the search as fallback. In `_validate_preflight` sum quantities per `sale_line_id` against `qty_to_invoice`.

---

## P3 — technical

### 33. `_sql_constraints` ignored [C]
- **Module.** `rs_base_methods`
- **Issue.** [B/models/rs_einvoice_waybill_link.py:77-80](../custom_addons/gec_odoo_modules/rs_base_methods/models/rs_einvoice_waybill_link.py#L77). Odoo 19 logs a warning and ignores it ([model_classes.py:162](../odoo/orm/model_classes.py#L162)); the live table has no unique constraint.
- **Provoke.** `SELECT conname FROM pg_constraint WHERE conrelid = 'rs_einvoice_waybill_link'::regclass` → primary key + 5 foreign keys only (verified on gec_modules2). Shell: create the same link twice under `rs_auto_sync=True` → succeeds.
- **Fix.** `_unique_move_waybill = models.Constraint('UNIQUE(move_id, waybill_id)', 'A waybill can only be linked once to the same invoice.')`.

### 34. "Enable Stock Integration" switch is dead [C]
- **Module.** `rs_waybill`
- **Issue.** `W/models/res_config_settings.py:30` stores `rs_waybill.enable_stock`; nothing reads it (the module's own comment says so). Scope is driven by the cutoff date (`rs_waybill.py:577-591`).
- **Provoke.** Settings → RS Waybill → untick Enable Stock Integration → sync a new in-scope waybill → SO / PO / transfer still created.
- **Fix.** read the parameter at the top of `_in_integration_scope` and return False when off, or remove the three "Enable" switches.
- **Review.** OK. Prefer removing the three dead switches over wiring them.

### 35. Change detector ignores VAT type / unit [C]
- **Module.** `rs_waybill`
- **Issue.** `_goods_lines_changed` (`W/models/rs_waybill_sync.py:694-706`) compares barcode, quantity, price only.
- **Provoke.** On rs.ge change only the VAT type or the unit text of a goods line → sync → line unchanged; the sync log counts it as "skipped (unchanged)".
- **Fix.** also compare `vat_type` vs `VAT_TYPE` and `unit_name` vs `UNIT_TXT`.

### 36. Waybill ACL: delete for every internal user [C]
- **Module.** `rs_waybill`
- **Issue.** `W/security/ir.access.csv:2,4` (was `ir.model.access.csv:2-3` before the 2026-09-22 `ir.access` migration) grants full CRUD on `rs.waybill` and lines to `base.group_user`; rs.ge-mutating buttons carry no groups.
- **Provoke.** Log in as an internal user without Inventory or Accounting groups → Waybills → open one → Delete allowed; Refuse and Cancel buttons visible.
- **Fix.** add user/manager groups, restrict unlink to manager, put `groups=` on Refuse / Delete / Cancel buttons.

### 38. 18% tax lookup may pick a price-included tax [C]
- **Module.** `rs_einvoice`
- **Issue.** `_rs_get_purchase_vat_18` (`E/models/account_move_sync.py:613-621`) matches `amount == 18`.
- **Provoke.** Accounting → Taxes: create a purchase tax 18%, Included in Price = Tax Included, sequence lower than the real one. Pull a bill with VAT → Shell: `bill._rs_get_purchase_vat_18().price_include` → True; bill total below the rs.ge `full_amount`.
- **Fix.** add `('price_include', '=', False)` and prefer a company setting for the purchase VAT tax.

---

## Session 2 — Accounting / sale / purchase / stock core-integration sweep (2026-09-18/19)

Second-pass sweep, scoped by the user to: payment/reconciliation vs purchase/bill/invoice/sale, and stock/stock-return vs sale/invoice. Six readers covered seller accounting, buyer accounting, purchase, and stock core end to end (no XML, no CSV, no tests). **This batch was NOT put through an adversarial verify pass** (skipped at the user's instruction) — each item carries the reader's own core file:line citations, and a `Status` line where I personally re-checked the claim against the gec_modules2 TEST DB with a direct query (never production). Treat items without a `Status` line as single-pass and re-check before acting on them.

Two items reproduce concretely on the gec_modules2 TEST DB, not just in theory: **#39** (every posted rs.ge-pulled bill checked there books 0.00 input VAT against a certified rs.ge VAT amount) and **#40** (rounding produces a real 0.01 cent drift on a posted test-DB bill). Whether production shows the same pattern is unverified — check production's own data before treating #39/#40 as a live financial-reporting problem. The entire purchase-order bridge (#50-57, #62) is confirmed not exercised on gec_modules2 — 0 of 2,145 buyer waybills there have ever linked a PO — so those are real defects in code, unconfirmed against production, waiting for the day someone turns that integration on.

| # | Prio | Module | Area | Issue | Test-DB status |
|---|---|---|---|---|---|
| 39 | P1 | `rs_einvoice (buyer)` | accounting | Taxed rs.ge lines booked untaxed at gross when no 18% purchase tax exists; Accept still posts and confirms | Reproduced (test DB) |
| 40 | P2 | `rs_einvoice (buyer)` | accounting | price_unit = amount/qty rounded to 2 decimals makes bill totals differ from the rs.ge certified total by cents | Reproduced (test DB) |
| 41 | P2 | `rs_einvoice (buyer)` | accounting | Accepting a supplier cancellation on a draft bill posts it first, then tries to cancel; hash-locked purchase journal leaves the void bill posted | Not exercised (test DB) |
| 42 | P2 | `rs_einvoice (buyer)` | accounting | Reject and Accept-cancellation paths ignore reversal_move_ids / payment_state 'reversed'; auto-cancel strands a reconciled credit note | Not exercised (test DB) |
| 43 | P3 | `rs_einvoice (buyer)` | accounting | Bills created from rs.ge (inbox, cron, pull) carry no purchase order link; PO stays 'To Bill' beside a posted bill | Not exercised (test DB) |
| 44 | P1 | `rs_einvoice (seller)` | accounting | Any credit note (draft, cancelled, Skip-rs.ge partial) permanently disables the local cancel at rs.ge status 7 and 8 - silently, no TODO | Reproduced (test DB) |
| 45 | P1 | `rs_einvoice (seller)` | accounting | Auto-cancel of a prior-period original rewrites an already declared VAT period (no lock dates in live DB) | Reproduced (test DB) |
| 46 | P2 | `rs_einvoice (seller)` | accounting | GEL amounts sent to rs.ge are recomputed from the rate table, not from the booked invoice_currency_rate | Not exercised (test DB) |
| 47 | P2 | `rs_einvoice (seller)` | accounting | Sent (Pending) invoice reset to draft, buyer confirms meanwhile, re-post succeeds with edited lines; rs.ge keeps the confirmed old lines | Not exercised (test DB) |
| 48 | P3 | `rs_einvoice (seller)` | accounting | rs.ge status 7 written by _rs_apply_status_update never triggers the local cancel | Reproduced (test DB) |
| 49 | P3 | `rs_einvoice (seller)` | accounting | Pulled rs.ge lines lose cents: price_unit stored at 2 dp and VAT recomputed by account.tax, so bill total != rs.ge full_amount | Reproduced (test DB) |
| 50 | P1 | `rs_waybill + rs_einvoice (purchase bridge)` | purchase | Reimport Lines strips purchase_line_id from PO-created bill lines; PO drops to Waiting Bills while the bill stays posted | Not exercised (test DB) |
| 51 | P2 | `rs_waybill + rs_einvoice (purchase bridge)` | purchase | Receive applies PO/receipt/return changes before the rs.ge confirm and keeps them when the confirm fails | Not exercised (test DB) |
| 52 | P2 | `rs_waybill + rs_einvoice (purchase bridge)` | purchase | Seller cancel cascade cancels a PO whose receipt is already done — received stock with no PO to bill against | Not exercised (test DB) |
| 53 | P2 | `rs_waybill + rs_einvoice (purchase bridge)` | purchase | Lines the vendor adds on the waybill enter the PO at product.standard_price, not the waybill price | Not exercised (test DB) |
| 54 | P2 | `rs_waybill + rs_einvoice (purchase bridge)` | purchase | Vendor waybill always spawns a new PO; an existing open PO from the same vendor is never matched | Not exercised (test DB) |
| 55 | P2 | `rs_waybill + rs_einvoice (purchase bridge)` | purchase | Bill pulled from rs.ge is never linked to the PO the module built from the same waybill | Not exercised (test DB) |
| 56 | P2 | `rs_waybill + rs_einvoice (purchase bridge)` | purchase | Update-button backfill creates the PO in the user's active company, not the waybill's company | Not exercised (test DB) |
| 57 | P3 | `rs_waybill + rs_einvoice (purchase bridge)` | purchase | Two-step PO approval leaves the waybill without a receipt; the receipt created at approval is never linked | Not exercised (test DB) |
| 58 | P2 | `rs_waybill (stock core)` | stock | Completion cascade closes a partially reserved delivery: remainder becomes a backorder with its own auto-waybill while the first waybill already declared the full quantity | code-level |
| 59 | P2 | `rs_waybill (stock core)` | stock | Seller-side RS goods auto-apply swallows exceptions without a savepoint, so a multi-line change is applied half-way and the sync commits it; the snapshot is gone, so it is never retried | code-level |
| 60 | P2 | `rs_waybill (stock core)` | stock | _action_reverse_completed_waybill cancels on rs.ge and locally but never persists the return quantities; closing the popup leaves a cancelled waybill with a done delivery and no way back | code-level |
| 61 | P2 | `rs_waybill (stock core)` | stock | Vendor-added product on a buyer waybill becomes a PO line priced at product cost, not the rs.ge unit price, so the vendor bill built from the PO disagrees with the waybill | Not exercised (test DB) |
| 62 | P3 | `rs_waybill (stock core)` | stock | moves._action_done() bypasses stock.picking._action_done: hook-built receipts and supplementary deliveries end Done with no date_done, no _trigger_assign of waiting moves, no confirmation email | code-level |

---

### 39. Taxed rs.ge lines booked untaxed at gross when no 18% purchase tax exists; Accept still posts and confirms [C]
- **Module.** `rs_einvoice (buyer)`
- **Mechanism.** _rs_get_purchase_vat_18 searches account.tax by type_tax_use=purchase, amount=18 (sync.py:613-621). When nothing is found, _rs_pulled_line_vals takes the else branch (sync.py:630-632): price_unit = full_amount/qty (VAT-inclusive gross), tax_ids = [(5,0,0)]. _rs_auto_import_pulled_to_bill_lines only appends an rs.einvoice.log warning (sync.py:660-672). action_rs_buyer_accept then posts the draft (buyer.py:326-330) and calls buyer_accept_invoice (346-348) without looking at the bill's tax lines; the merge/refresh at 343-344 only rewrites the snapshot, not the bill.
- **Core collision.** Odoo's tax report and the 3330-type input-VAT account are fed only by tax lines generated from account.move.line.tax_ids; a product line with empty tax_ids produces no tax line and no tax grid amount. The bill Odoo books is expense=gross, VAT=0, while the rs.ge e-invoice the same click confirms certifies base+VAT. Nothing in core would have produced a VAT-free bill for a VAT invoice.
- **Core evidence.** addons/account/models/account_move_line.py:378-383 (price_unit/price_subtotal fields; tax computed from tax_ids); addons/account/models/account_move.py:5476-5500 (_post has no rs.ge/tax-presence check). Test-DB check (gec_modules2, not production): account_tax has only one 18% tax and it is type_tax_use='sale' (id 929, company 1); no purchase 18% tax exists. Every posted rs.ge-pulled bill shows amount_tax = 0.00 against rs.ge drg_amount > 0: BILL/2026/05/0028 (status 8) 0.00 vs 15254.08; BILL/2026/05/0018 (status 8) 0.00 vs 6008.95; BILL/2026/05/0030 (status 8) 0.00 vs 508.58; 12 of 12 posted pulled bills on the test DB (not a production count).
- **Mismatch.** BILL/2026/05/0028: Odoo expense 99999.00, input VAT 0.00, payable 99999.00. rs.ge (accepted, status 8): base 84744.92, VAT 15254.08, total 99999.00. Purchase VAT report for the period understates deductible input VAT by 15254.08 for this one bill; the expense account is overstated by the same amount.
- **Status.** **Reproduced on the gec_modules2 TEST DB (not production).** Confirmed on gec_modules2: 15 posted rs.ge-pulled bills checked, all show amount_tax=0.00 against rs.ge drg_amount 338-58,558 GEL; no purchase-type tax at 18% exists (only tax id 929, type_tax_use='sale').
- **Provoke.** Company has no purchase tax at exactly 18% (gec_modules2 today). Buyer Inbox -> tick a taxed supplier invoice -> Import Selected -> bill lines appear with price = gross and no tax; RS Logs carries one warning. Click Accept on rs.ge -> bill posts, rs.ge moves to 2/8. Reporting -> Tax Report: input VAT 0 for a supplier invoice rs.ge certifies with VAT.
- **Fix.** Resolve the tax through core's company default instead of a magic-number search: company_id.account_purchase_tax_id (the same default core's _compute_tax_ids uses for lines without product), then a fiscal-position map, with the amount=18 search as last fallback. When a taxed rs.ge line still has no tax to map to, treat it exactly like a failed _rs_refresh_pulled_lines(raise_on_failure=True) in action_rs_buyer_accept: stop before action_post so the confirmed rs.ge document and the booked bill never diverge. Pair with the #12 adjust (merge lines before post).

### 40. price_unit = amount/qty rounded to 2 decimals makes bill totals differ from the rs.ge certified total by cents [C]
- **Module.** `rs_einvoice (buyer)`
- **Mechanism.** _rs_pulled_line_vals derives price_unit as (full - vat)/qty or full/qty (sync.py:626-635) and stores it on account.move.line.price_unit. The rs.ge row carries full_amount as the authoritative line total; the division result is then rounded by the field's decimal precision and multiplied back by qty, so the subtotal no longer equals full_amount. Nothing re-checks the line total against the snapshot before Accept posts the bill (buyer.py:326-348).
- **Core collision.** account.move.line.price_unit has digits='Product Price' (2 decimals by default); Float.convert_to_cache rounds to those digits, and price_subtotal = quantity x rounded price_unit. Core's own import paths keep the line total exact (they set price_unit from an exact unit price, not a division). The payable Odoo books is not the amount the supplier's certified invoice states.
- **Core evidence.** addons/account/models/account_move_line.py:378-382 (digits='Product Price'); addons/product/data/product_data.xml:19-22 (Product Price = 2 digits); odoo/orm/fields_numeric.py:140-144 (Float.convert_to_cache rounds to digits[1]). Test-DB check (gec_modules2, not production): BILL/2026/05/0030 (posted, rs.ge status 8) line qty 3.00, price_unit 1111.33, price_total 3333.99 vs rs.ge snapshot g_number 3, full_amount 3334.00; BILL/2026/05/0002 (posted) 99999.99 vs 100000.00; draft 5554 8747.43 vs 8747.42. 3 test-DB records differ today (not a production count).
- **Mismatch.** rs.ge line: qty 3, full_amount 3334.00. Odoo: 3 x 1111.33 = 3333.99 payable. Vendor is paid 3334.00 per the certified invoice -> the bill shows 0.01 over-payment (payment_state stays partial/paid with a 0.01 write-off need) or the vendor is short-paid 0.01; the e-invoice total on rs.ge and the AP entry disagree.
- **Status.** **Reproduced on the gec_modules2 TEST DB (not production).** Confirmed on gec_modules2: BILL/2026/05/0002, qty 3, price_unit 33333.33, price_subtotal 99999.99 vs rs.ge full_amount 100000.00 — the exact 0.01 drift described.
- **Provoke.** Pull any rs.ge invoice whose full_amount is not divisible by its quantity at 2 decimals (3 tonnes for 3334.00 GEL). Accept on rs.ge -> bill posted at 3333.99 while rs.ge shows 3334.00. Register a payment of 3334.00 -> 0.01 outstanding credit on the vendor.
- **Fix.** Keep the rs.ge line total authoritative: after building the line, compare line.price_subtotal (or price_total) with the snapshot using currency.compare_amounts; when they differ, either raise the 'Product Price' decimal.precision (core's own answer for fractional unit prices) or import the line as quantity 1 x full_amount with the quantity kept in the description/UoM, so quantity x price_unit reproduces the certified amount exactly.

### 41. Accepting a supplier cancellation on a draft bill posts it first, then tries to cancel; hash-locked purchase journal leaves the void bill posted [C]
- **Module.** `rs_einvoice (buyer)`
- **Mechanism.** action_rs_buyer_accept posts any draft bill unconditionally (326-330, context rs_buyer_accept_in_progress bypasses the module's own _post guard) before deciding what the accept means. For rs.ge status 6 (target 7 = we confirm the supplier's cancellation) it then calls _rs_auto_cancel_after_rs_cancellation (401-403), i.e. button_draft + button_cancel on a bill that was posted one statement earlier. If the cancel fails, the bill stays posted with rs.ge status 7 and only an activity is scheduled (405-415); the recovery cron (rs_buyer_inbox_wizard.py:1015-1070) re-runs the same button_draft and fails the same way.
- **Core collision.** Core hashes on post for journals with restrict_mode_hash_table (write(): state=posted -> _hash_moves(), domain restrict_mode_hash_table=True), and _check_draftable refuses to reset a hashed move. Core's own path for a void document that is still draft is button_cancel on the draft (allowed, no post). The module manufactures a posted, numbered, hashed vendor bill for a document rs.ge considers void.
- **Core evidence.** addons/account/models/account_move.py:3946-3947 (self._hash_moves() when vals state == 'posted'), 4546-4556 (_get_move_hash_domain: state posted AND restrict_mode_hash_table), 6114-6115 (_check_draftable raises on inalterable_hash), 6126-6138 (button_cancel works directly on drafts). Test-DB check: gec_modules2 purchase journal BILL has restrict_mode_hash_table unset, so the hash branch is latent there; the post-then-cancel sequence itself runs on every 6->7 accept of a draft.
- **Mismatch.** Draft bill 118 GEL (100 + 18 VAT), supplier cancels on rs.ge (status 6), purchase journal has 'Lock posted entries with hash'. Accept on rs.ge -> Odoo: bill posted, BILL/2026/09/0041 assigned, inalterable_hash set, AP 118 and input VAT 18 booked, rs.ge status 7. Auto-cancel fails ('You cannot reset to draft a locked journal entry'); books keep AP 118 / VAT 18 for an invoice rs.ge shows as cancelled. Without hash: a posted-then-cancelled bill consuming sequence number 0041 that core would never have created from a draft.
- **Status.** **Not exercised on the gec_modules2 test DB** (needs a hash-locked purchase journal; not set on gec_modules2 today) but the post-then-cancel sequence itself runs on every draft-status-6 accept regardless.
- **Provoke.** Cron or inbox creates a draft bill from rs.ge (status 1). Supplier requests cancellation (status 6) before the bill is posted. Set the purchase journal to hash-lock posted entries. Open the draft, click Accept on rs.ge -> bill is posted and hashed, then the RS Logs show 'auto-cancel failed', an activity is scheduled, and the bill stays posted at rs.ge status 7. Status Update / the recovery cron never clear it.
- **Fix.** Branch on target_status before touching state: for target 7 do not post; call button_cancel() on the draft directly (core 6126-6138 handles drafts) after the rs.ge accept succeeds, and only post for targets 2 and 8. For a posted original at target 7 keep the #4 payment guard.

### 42. Reject and Accept-cancellation paths ignore reversal_move_ids / payment_state 'reversed'; auto-cancel strands a reconciled credit note [C]
- **Module.** `rs_einvoice (buyer)`
- **Mechanism.** _rs_do_buyer_reject blocks only payment_state in ('paid','partial','in_payment') (792-794) and then calls _rs_auto_cancel_after_rs_cancellation on the posted bill (890-895). action_rs_buyer_accept target 7 (401-403) has no payment or reversal check at all. Both differ from the two other callers, action_rs_refresh_status (account_move_sync.py:119-122, requires not self.reversal_move_ids) and the recovery cron (rs_buyer_inbox_wizard.py:1034, reversal_move_ids = False). A bill fully offset by a Skip-rs.ge vendor credit note has payment_state 'reversed', passes both guards, and is reset + cancelled; button_cancel unreconciles the credit note.
- **Core collision.** Core sets payment_state 'reversed' for an in_invoice reconciled only with in_refund moves, and button_cancel calls line_ids.remove_move_reconcile() on every line. After the module's cancel the credit note remains posted and unreconciled: core would never leave a standalone posted refund whose original is cancelled without either cancelling the refund too or keeping the pair reconciled.
- **Core evidence.** addons/account/models/account_move.py:1305-1312 (in_reverse -> payment_state 'reversed'); 6126-6136 (button_cancel -> button_draft on posted, then line_ids.remove_move_reconcile()); custom_addons/gec_odoo_modules/rs_einvoice/models/rs_correction_wizard.py:202-213 (flow 'skip' creates a credit note without rs.ge status checks, so this state is reachable on a status-1 bill).
- **Mismatch.** Bill 118 GEL posted (rs.ge status 1). Accountant creates a Skip-rs.ge credit note 118 reconciled with it -> bill payment_state 'reversed', AP net 0, VAT net 0. Reject on rs.ge -> rs.ge status 0, bill reset and cancelled, credit note unreconciled. Books now: AP -118 (open vendor credit), input VAT -18, no bill. Same result if the supplier cancels (status 6) and the buyer clicks Accept.
- **Status.** **Not exercised on the gec_modules2 test DB** (needs a Skip-rs.ge credit note reconciled against a draft/posted bill before a Reject/Accept-cancel; not checked for an existing occurrence).
- **Provoke.** Vendor bill pulled and posted, status 1. Add Credit Note -> RS Treatment 'Only correct Odoo, not rs.ge' -> Reverse -> reconcile. Payment state shows Reversed. RS E-Invoice tab -> Reject on rs.ge with a reason -> bill becomes Cancelled; Accounting -> Vendors -> Refunds shows the credit note still posted with amount_residual -118.
- **Fix.** Same skip rule as #4 but stated on the move's reconciliation, not on a payment list: in action_rs_buyer_accept (target 7) and _rs_do_buyer_reject skip the automatic cancel when payment_state != 'not_paid' or reversal_move_ids is set, and leave the manual step to the accountant (credit note already exists in this case: cancel it with the bill or keep both). Reuse the guard already present in action_rs_refresh_status and the recovery cron so all four entry points agree.

### 43. Bills created from rs.ge (inbox, cron, pull) carry no purchase order link; PO stays 'To Bill' beside a posted bill [C]
- **Module.** `rs_einvoice (buyer)`
- **Mechanism.** _do_import and _sync_one_user create the bill with move_type, partner_id, journal_id, invoice_date only; _rs_auto_import_pulled_to_bill_lines adds product lines with name/quantity/price_unit/tax_ids and no product_id or purchase_line_id. Nothing calls the purchase module's bill-to-PO matching, and the operator never sees the Auto-Complete field because the lines are already there when the form opens.
- **Core collision.** Core's own bill-import paths link the bill to its purchase order (purchase_vendor_bill_id auto-complete, _find_and_set_purchase_orders used by EDI/OCR imports), so purchase.order.line.qty_invoiced and the PO invoice_status reflect the bill. A bill imported by this module leaves qty_invoiced at 0 and the PO in 'To Bill'; Create Bill from the PO then produces a second payable for the same goods. Sibling of #8 (reissue) and #32 (waybill wizard), but this is the primary pull path every vendor bill goes through.
- **Core evidence.** addons/purchase/models/account_invoice.py:19-48 (purchase_vendor_bill_id / _onchange_purchase_auto_complete), 447 (_find_and_set_purchase_orders signature only; body not read). qty_invoiced aggregation on purchase.order.line: not verified.
- **Mismatch.** PO 10 units @ 100, received. rs.ge inbox imports the supplier's bill for those 10 units -> posted bill 1180 with lines lacking purchase_line_id. PO line qty_invoiced = 0, invoice_status = 'to invoice'; Create Bill on the PO -> second draft for 10 units; if posted, payable 2360 for 1180 of goods.
- **Status.** **Not exercised on the gec_modules2 test DB** — confirmed 0 of 2,145 buyer waybills there have ever linked a purchase_id, so the buyer-side PO bridge has not run there yet; a code defect for the day it does, unconfirmed against production.
- **Provoke.** Confirm a PO and receive it. Buyer Inbox -> Import Selected the supplier's rs.ge invoice for that PO -> Accept on rs.ge. Open the PO: Billing Status still 'Waiting Bills', Create Bill offers the full quantity again.
- **Fix.** After the bill is created and before _rs_auto_import_pulled_to_bill_lines, run the core matcher (_find_and_set_purchase_orders with the partner and rs.ge total, or expose purchase_vendor_bill_id on the inbox row) so lines come from the PO with purchase_line_id, then apply rs.ge qty/price via _rs_merge_pulled_to_bill_lines (#11/#12 adjustments); fall back to bare lines only when no PO matches.

### 44. Any credit note (draft, cancelled, Skip-rs.ge partial) permanently disables the local cancel at rs.ge status 7 and 8 - silently, no TODO [C]
- **Module.** `rs_einvoice (seller)`
- **Mechanism.** _rs_neutralize_after_correction_accepted returns early when `self.reversal_move_ids` is non-empty (856-859); the status-7 block in action_rs_refresh_status requires `not self.reversal_move_ids` (sync.py:121); the recovery cron domain has `('reversal_move_ids','=',False)`. All three treat the mere existence of a reversal as 'already neutralised'. reversal_move_ids includes draft and cancelled credit notes and books-only Skip-rs.ge notes (bad_debt, intercompany_mirror, partial amounts). None of the three branches logs, schedules _rs_schedule_manual_reversal_activity or sets rs_einv_reversal_pending_at when skipping; _rs_replace_preflight (orchestrator 46-119) does not check reversal_move_ids either, so Correct & Reissue is allowed on such an original. The reversal wizard skips _rs_assert_can_be_reversed entirely for flow 'skip' (rs_correction_wizard.py:208-212), so a Skip-CN can be created at any rs.ge status.
- **Core collision.** reversal_move_ids is a plain One2many on reversed_entry_id with no state filter; a partial or books-only credit note is not a full reversal. Core's meaning of 'reversed' is payment_state == 'reversed' (full reconciled reversal). The module never cancels the original, so the original + partial CN + accepted correction all stay posted.
- **Core evidence.** addons/account/models/account_move.py:630 `reversal_move_ids = fields.One2many('account.move', 'reversed_entry_id')` (read). Test-DB check (gec_modules2, not production): INV/2026/00153 posted, rs_einv_status 7, payment_state not_paid, reversal RINV/2026/00071 posted skip_reason intercompany_mirror, rs_einv_reversal_pending_at NULL - gate active, no escalation. 76 posted rs.ge invoices already carry a reversal.
- **Mismatch.** Status 8 case: original INV 118 GEL (VAT 18) has a books-only CN of -18 GEL (bad_debt); correction accepted for 100 GEL (VAT 15.25). rs.ge: one live invoice 100 GEL. Odoo posted: 118 - 18 + 100 = 200 GEL revenue, VAT 18 + 15.25 = 33.25 vs rs.ge 15.25. Status 7 case (live): rs.ge void, Odoo INV/2026/00153 still posted with full receivable and VAT; no activity anywhere.
- **Status.** **Precondition reproduced on the gec_modules2 TEST DB (not production)**: 76 posted rs.ge-linked moves already carry a reversal_move_ids entry on gec_modules2 (incl. INV/2026/00153, skip_reason intercompany_mirror). Whether any of the 76 also has an accepted correction pending was not individually checked.
- **Provoke.** Post INV 118 with 18% VAT, Send to RS, buyer confirms (2). Add Credit Note with RS Treatment = Skip rs.ge, reason bad_debt, amount 18, post it. On the original run Correct & Reissue, post/send the correction, buyer accepts (8). Status Update -> original stays posted, RS Logs show no 'cancelling this original' entry, no TODO. Variant: Cancel on RS (6), buyer confirms (7), Status Update -> same silence. Shell: `inv._rs_neutralize_after_correction_accepted()` returns None with inv.state still 'posted'.
- **Fix.** Replace the existence test with core's notion of fully reversed: skip only when `payment_state == 'reversed'` or when the posted out_refund reversals sum to amount_total; otherwise fall through to the normal cancel path, and when the cancel is refused call _rs_schedule_manual_reversal_activity and set rs_einv_reversal_pending_at (same as the exception branch). Apply the same predicate in the recovery cron domain and in _rs_replace_preflight. For the paid/partially reversed case the manual step is core's _reverse_moves(cancel=True) on the remainder, marked Skip rs.ge reason 'replacement'.

### 45. Auto-cancel of a prior-period original rewrites an already declared VAT period (no lock dates in live DB) [C]
- **Module.** `rs_einvoice (seller)`
- **Mechanism.** _rs_auto_cancel_after_rs_cancellation does button_draft + button_cancel on the original with no regard to move.date. The buyer acts inside the 30-day #996 window, so the acceptance (status 7/8) routinely lands in the month after the original's operation date. The replacement is dated today (orchestrator 148-149 / 213-214). Result: the original's revenue, receivable and VAT are removed retroactively from month N; the replacement lands in month N+1.
- **Core collision.** Core's way to undo an issued invoice after the period is the reversal wizard, whose date defaults to today, so the past period stays intact. Core protects against un-posting into a closed period only through lock dates (write hook runs _check_fiscal_lock_dates/_check_tax_lock_date when state leaves 'posted'); with no lock dates set the retroactive change goes through silently. The fix plan's root design note (#4-#7: 'books end identical') holds only when original and acceptance fall in the same VAT month.
- **Core evidence.** addons/account/wizard/account_move_reversal.py:17 `date = fields.Date(... default=fields.Date.context_today)`; addons/account/models/account_move.py:3895-3900 (lock check only on state leaving posted, only if a lock date exists), 2790-2807 _check_fiscal_lock_dates, addons/account/models/account_move_line.py:1389-1406 _check_tax_lock_date. Test-DB check (gec_modules2, not production): both companies have tax_lock_date, fiscalyear_lock_date and sale_lock_date NULL, so the protection never fires.
- **Mismatch.** INV/001 dated 2026-08-20, 118 GEL, VAT 18, in the August tax report already filed. Correct & Reissue for 100 GEL (VAT 15.25), buyer accepts 2026-09-03. Odoo after Status Update: August tax report VAT 0 for this customer (was 18), August revenue -100; September +100 revenue, VAT 15.25. Declared August return says 18; Odoo's August report now says 0. Core reversal path would leave August at 18 and put -18 + 15.25 in September.
- **Status.** **Precondition reproduced on the gec_modules2 TEST DB (not production)**: both companies have fiscalyear_lock_date, tax_lock_date, sale_lock_date and purchase_lock_date all NULL on gec_modules2, so the only protection core has against this is currently off.
- **Provoke.** Set no lock dates (as in gec_modules2). Post a customer invoice dated last month, Send to RS, buyer confirms. This month: Correct & Reissue, post, Send to RS, Send to buyer, buyer accepts. Status Update. Open Reporting > Tax Report for last month before and after: the original's VAT disappears. Shell (no rs.ge): `inv._rs_auto_cancel_after_rs_cancellation()` on a posted invoice dated last month -> state 'cancel', no error.
- **Fix.** When the original's date is in an earlier VAT month than today (or before tax_lock_date), neutralise with core's `_reverse_moves(default_values_list=[{'date': today, 'rs_einv_skip': True, 'rs_einv_skip_reason': 'replacement'}], cancel=True)` instead of button_draft/button_cancel; the 'replacement' skip reason and its button_draft protection (account_move.py:1806-1813) already exist for exactly this pairing. Keep button_cancel only for same-month originals. Independently, set tax_lock_date monthly so core's write hook (3895-3900) turns any remaining retroactive cancel into the manual TODO branch.

### 46. GEL amounts sent to rs.ge are recomputed from the rate table, not from the booked invoice_currency_rate [C]
- **Module.** `rs_einvoice (seller)`
- **Mechanism.** _rs_amount_to_gel converts line.price_total / (price_total - price_subtotal) with `currency_id._convert(..., target_date)` where target_date is invoice_date or a caller-supplied rate_date; _rs_get_fx_rate reads res.currency.rate directly. The move's stored `invoice_currency_rate` is never read. _rs_expected_advance_settlements (seller.py:303-305) additionally converts the offset line at the advance's invoice_date, a third rate.
- **Core collision.** Core books invoice lines in company currency through the move's stored invoice_currency_rate (readonly=False, user-editable, frozen at posting); every line's balance and the tax lines' balance use that rate. The tax report and the receivable are in GEL from that rate. The module's payload uses whatever the rate table says at call time, so a manual rate override or a rate row added/edited after posting makes rs.ge VAT != booked VAT.
- **Core evidence.** addons/account/models/account_move.py:530-537 (invoice_currency_rate store=True, readonly=False, copy=False), 1145-1148 compute; addons/account/models/account_move_line.py:722-726 `line.currency_rate = line.move_id.invoice_currency_rate`, 1062-1064 balance = amount / rate. Test-DB check (gec_modules2, not production): 19 rs.ge-linked invoices in a currency other than the company currency.
- **Mismatch.** USD invoice 100 + 18 VAT, rate table 2.70 USD->GEL on invoice_date; accountant sets Currency Rate to 2.75 before posting. Odoo tax line balance = 18 x 2.75 = 49.50 GEL; rs.ge receives vat_amount = 18 x 2.70 = 48.60 GEL, full_amount 318.60 vs booked 324.50. Same drift if the 2.70 row is corrected to 2.72 after posting: books stay 48.60, next Update on RS sends 48.96.
- **Status.** **Not exercised on the gec_modules2 test DB** (needs a manual Currency Rate override or a res.currency.rate row edited after posting; 19 non-GEL rs.ge-linked invoices exist but individual rate edits not checked).
- **Provoke.** Company GEL, customer invoice in USD, one line 100 USD + 18% VAT. Edit the Currency Rate field on the invoice to a value different from the table, post. Shell: `inv._rs_get_lines_payload()[0]['vat_amount']` vs `abs(inv.line_ids.filtered('tax_line_id').balance)` differ. Or post with the table rate, then edit the res.currency.rate row for that date and repeat.
- **Fix.** Build the payload from company-currency fields the ledger already holds: `abs(line.balance)` for the net, tax-line `balance` (or `line.price_total - line.price_subtotal` divided by `move.invoice_currency_rate`) for VAT, i.e. `amount_currency / move.invoice_currency_rate` instead of `currency._convert` at a date. Drop _rs_get_fx_rate as a rate source; keep it only as the 'rate exists' precheck if wanted.

### 47. Sent (Pending) invoice reset to draft, buyer confirms meanwhile, re-post succeeds with edited lines; rs.ge keeps the confirmed old lines [C]
- **Module.** `rs_einvoice (seller)`
- **Mechanism.** _rs_raise_if_locked(allow_pending=True) lets a status-1 invoice go to draft. On re-post, _post calls super()._post() first (1621) and only then _rs_auto_sync_pending_sent_edits, which runs action_rs_edit inside a savepoint and converts every UserError into a chatter warning (1640-1654). action_rs_edit refreshes and refuses when the status is no longer 0/1/4 (seller.py:821-830). So when the buyer confirmed (status 2) during the draft window, the edited invoice is posted, the refusal is swallowed, and rs_einv_has_pending_changes stays True with no path to push (Update on RS refuses forever at status 2).
- **Core collision.** Core _post posts whatever the draft holds; the module's own status guard exists only after the post and is non-blocking, so the certified rs.ge document and the posted Odoo document diverge with only a chatter line.
- **Core evidence.** addons/account/models/account_move.py:5476 _post (completes; no rs.ge knowledge) - module ordering verified at account_move.py:1621-1622. Refusal path seller.py:825-830 read. [Likely] the status-1 -> 2 transition during the draft window is common: 58 posted invoices sit at status 1 in gec_modules2.
- **Mismatch.** INV 118 GEL (VAT 18) sent, status 1. Reset to draft, line changed to 236 GEL (VAT 36). Buyer confirms the 118 version on rs.ge. Re-post: Odoo posted 236 / VAT 36, tax report 36; rs.ge confirmed 118 / VAT 18, declaration 18. Update on RS: 'Cannot update - status is now Confirmed'.
- **Status.** **Not exercised on the gec_modules2 test DB** (needs a Sent(Pending) invoice reset to draft, edited, and confirmed by the buyer before re-post; 58 invoices sit at status 1 today per the reader's grep, individual draft-window overlap not checked).
- **Provoke.** Post + Send to RS + Send to buyer (status 1). Reset to Draft (allowed with the pending warning). Change quantity 1 -> 2. On rs.ge (or via the buyer test account) confirm the invoice. Post the draft: succeeds; chatter shows 'Auto-sync of edited lines to rs.ge after posting failed: Cannot update this document - rs.ge status is now Confirmed'. Compare amount_total to the rs.ge document.
- **Fix.** Move the pending-edit sync ahead of super()._post() in the override (refresh status first, then action_rs_edit, then post) so the existing action_rs_edit status guard aborts the post inside the same transaction; alternatively, when the refreshed status is 2 route the edited draft through _rs_do_correct_reissue (copy as correction of the confirmed original) instead of posting it as the same document.

### 48. rs.ge status 7 written by _rs_apply_status_update never triggers the local cancel [C]
- **Module.** `rs_einvoice (seller)`
- **Mechanism.** action_rs_cancel verifies with get_invoice and, when the status is already not '6', calls _rs_apply_status_update(target, new_status) (1104-1105). That helper only writes rs_einv_status and posts chatter; the status-7 side effect (_rs_auto_cancel_after_rs_cancellation) lives solely in action_rs_refresh_status (sync.py:118-125). When the buyer confirms immediately (auto-confirm buyers, or a buyer that acts within the verification round-trip) Odoo stores status 7 while the invoice stays posted, rs_einv_cancel_pending_at is set, and nothing runs until a manual Status Update or the (off-by-default) recovery cron.
- **Core collision.** Module-internal bypass of its own hook: same state (7) reached by two writers, only one of which mirrors the state into Odoo. Odoo keeps a posted invoice and receivable for a document rs.ge has voided.
- **Core evidence.** not verified against core (module-internal). Test-DB check (gec_modules2, not production): INV/2026/00151 and INV/2026/00152 are posted, rs_einv_status 7, payment_state not_paid, no reversal, rs_einv_reversal_pending_at NULL - the exact state this path leaves behind ([Likely] cause; a skipped Status Update is the alternative explanation).
- **Mismatch.** INV 118 GEL: rs.ge status 7 (cancelled, buyer confirmed); Odoo state posted, receivable 118, VAT 18 still in the tax report; Cancel and Reissue replacement 118 also posted later -> 236 booked for one sale until someone clicks Status Update.
- **Status.** **Precondition reproduced on the gec_modules2 TEST DB (not production)**: INV/2026/00151 and INV/2026/00152 on gec_modules2 are posted, rs_einv_status 7, payment_state not_paid, no reversal — the exact leftover state; whether the cause is this path or a skipped Status Update was not distinguished.
- **Provoke.** Cancel on RS on a confirmed invoice whose buyer auto-confirms cancellations. After the click, RS Logs show 'Cancel on RS (status: Confirmed -> Cancellation Confirmed)' but the invoice is still Posted and the TODO 'Waiting for buyer to confirm' is open. Shell: `inv._rs_apply_status_update(inv.rs_einv_id, '7')` on a posted invoice -> rs_einv_status '7', state 'posted'.
- **Fix.** In action_rs_cancel's verification tail call `move.action_rs_refresh_status()` (which owns the 7/8 side effects) instead of `_rs_apply_status_update`, or have `_rs_apply_status_update` call `_rs_auto_cancel_after_rs_cancellation` when the routed status is '7' and the target move is posted. Enable _cron_rs_recover_stranded_cancellations as the backstop.

### 49. Pulled rs.ge lines lose cents: price_unit stored at 2 dp and VAT recomputed by account.tax, so bill total != rs.ge full_amount [C]
- **Module.** `rs_einvoice (seller)`
- **Mechanism.** _rs_pulled_line_vals derives `price_unit = (full_amount - drg_amount) / qty` and attaches the 18% purchase tax; price_unit is stored with 'Product Price' precision (2 dp) and Odoo then recomputes subtotal = qty x rounded price and VAT = 18% of that. Neither the supplier's base nor the supplier's VAT is preserved when base/qty is not a 2-dp number or when the supplier rounded VAT differently.
- **Core collision.** Core computes the bill's VAT and total from price_unit x quantity through account.tax; the module hands it a truncated unit price, so the payable and input VAT booked differ from the rs.ge-certified document the supplier will collect on.
- **Core evidence.** addons/account/models/account_move_line.py:378-382 `price_unit = fields.Float(... digits='Product Price')` (default 2 dp). Module math read at sync.py:626-634.
- **Mismatch.** rs.ge row: qty 3, full_amount 100.00, drg_amount 15.26. Module: base 84.74, unit 28.2467 -> stored 28.25; Odoo: subtotal 84.75, VAT round(15.255) = 15.26, total 100.01. Payable 100.01 vs supplier invoice 100.00; after paying 100.00 the bill shows amount_residual 0.01 and payment_state 'partial'. Second shape: full 100.00, vat 15.25 (supplier half-even) -> base 84.75 -> Odoo VAT 15.26 -> total 100.01, input VAT claimed 15.26 vs certified 15.25.
- **Status.** **Reproduced on the gec_modules2 TEST DB (not production).** Confirmed on gec_modules2 (see acct-buyer #2 query): several pulled lines round to a price_subtotal one cent off full_amount.
- **Provoke.** Shell, no rs.ge: on a draft vendor bill create an rs_pulled snapshot with g_number 3, full_amount 100.00, drg_amount 15.26; run `bill._rs_auto_import_pulled_to_bill_lines()`; compare `bill.amount_total` (100.01) with the snapshot's full_amount (100.00).
- **Fix.** Let core carry the exact gross: use a price-included 18% purchase tax variant with `price_unit = full_amount / qty` (Odoo then derives base and VAT from the gross), or write the line with `quantity = qty` and `price_unit` at full float precision via `digits` override on the import path, and compare `amount_total` to full_amount after import as the merge already does for counts (#11/#12 territory).

### 50. Reimport Lines strips purchase_line_id from PO-created bill lines; PO drops to Waiting Bills while the bill stays posted [C]
- **Module.** `rs_waybill + rs_einvoice (purchase bridge)`
- **Mechanism.** [Certain] _rs_merge_pulled_to_bill_lines unlinks every product line whose lowercased name does not equal an rs.ge goods text (281) and re-adds rs.ge rows through _rs_pulled_line_vals, whose dict carries only name/quantity/price_unit/tax_ids — no product_id, no purchase_line_id (sync.py:635-640). With rs_force_replace in context all product lines are unlinked first (236-237). A bill produced by Create Bill on a PO names its lines from the PO line ('[CODE] Product'), which rarely equals the vendor's rs.ge goods text, so most or all lines fall into the unmatched branch.
- **Core collision.** qty_invoiced is the sum of account.move.line records that carry purchase_line_id (invoice_lines) and are not cancelled; invoice_ids on the PO is the set of moves reached through order_line.invoice_lines. Lines without purchase_line_id are invisible to both, so Billing Status and the Bills smart button revert as if the bill never existed. Differs from known #11 (matching key): the damage here is the lost PO link on the recreated lines, which #11's rs_line_id key would not restore.
- **Core evidence.** addons/purchase/models/purchase_order_line.py:189-199 (_prepare_qty_invoiced over line.invoice_lines), :164-176 (qty_to_invoice), addons/purchase/models/purchase_order.py:46-68 (invoice_status), :71-75 (invoice_ids from order_line.invoice_lines.move_id)
- **Mismatch.** PO/001 line A 10 units @100, BILL/001 created from the PO and posted: qty_invoiced 10, invoice_status 'invoiced', invoice_count 1. Pull + Reimport Lines on the draft (or before posting) with rs.ge goods text 'Product A' vs line name '[A] Product A': line unlinked, new line 10 @100 without purchase_line_id. BILL/001 still totals 1,180 GEL incl. VAT and posts; PO/001 now qty_invoiced 0, qty_to_invoice 10, invoice_status 'to invoice', invoice_count 0. Create Bill on PO/001 yields BILL/002 1,180 → payable to the vendor 2,360 for 1,180 of goods.
- **Status.** **Not exercised on the gec_modules2 test DB** — confirmed 0 of any checked rs.ge-linked bill lines carry purchase_line_id, and 0 buyer waybills carry purchase_id, so the buyer-side PO bridge has never actually run live; this is a code defect for the day it does.
- **Provoke.** Confirm a PO, receive it, Create Bill (draft), set rs_einv_id and Pull from rs.ge so pulled snapshots exist, click Reimport Lines (or Reimport with force replace). Open the PO: Billing Status back to Waiting Bills, Bills smart button 0. Post the bill, then Create Bill again on the PO — a second bill is offered.
- **Fix.** Never unlink a line that has purchase_line_id; write qty/price/taxes onto it (the merge already does this for matched lines). For rs.ge rows that need a new line on a PO-linked bill, build vals from purchase.order.line._prepare_account_move_line() of the PO line matched by product, then overlay rs.ge qty/price — that is how core's Create Bill sets purchase_line_id/product_id/account/analytic. Drop the rs_force_replace wipe for bills whose lines carry purchase_line_id.

### 51. Receive applies PO/receipt/return changes before the rs.ge confirm and keeps them when the confirm fails [C]
- **Module.** `rs_waybill + rs_einvoice (purchase bridge)`
- **Mechanism.** [Certain] action_confirm_waybill runs _reconcile_buyer_goods (PO line writes, hook-built receipt moves force-validated, vendor-return picking validated) at 601, then calls service.confirm_waybill at 603 and commits at 605. When confirm_waybill raises, the except at 617 only logs and counts 'skipped'; nothing rolls back the Odoo changes made at 601, and the request (or the next loop iteration's cr.commit) commits them. is_confirmed stays '0' / reconfirm pending. The Reject path (634-640) documents 'PO and receipt stay untouched', which is no longer true after a failed Receive.
- **Core collision.** The module's own single-commit rule ('the buyer click is the single commit moment', rs_waybill.py:1537-1540) and the refuted-list rule that a commit is only safe BEFORE the rs.ge call: here stock moves are done and a vendor return is shipped, then the rs.ge step can still fail, and the change is committed anyway by normal request-end commit. Done stock moves cannot be undone by Odoo (stock_move._action_cancel refuses done moves — not verified in this session).
- **Core evidence.** not verified (request-end commit is ORM transaction semantics; stock_move.py:2033 refusal of done-move cancel is cited in the fix plan #24 but not re-read here)
- **Mismatch.** Vendor edited waybill 10 → 12 (pending +2). Buyer clicks Receive: PO line 10 → 12, supplementary receipt of 2 force-validated (on-hand +2, qty_received 12), rs.ge confirm raises (timeout). Waybill: is_confirmed '0', is_buyer_reconfirm_needed True, notification 'skipped'. Buyer now clicks Reject: rs.ge records rejection of the vendor's change, PO 12 / stock +2 stay. Vendor reverts waybill to 10 → sync → pending −2 → next Receive ships 2 back to the vendor (#22) for goods that were only ever booked, not received.
- **Status.** **Not exercised on the gec_modules2 test DB** (same dormant bridge).
- **Provoke.** Buyer waybill with PO + done receipt. Monkeypatch rs.waybill.soap.service.confirm_waybill to raise; add a pending +2 delta (edit a waybill line quantity via _sync_goods_lines or set pending_goods_json); click Receive. Observe PO qty 12 and a done supplementary receipt while is_confirmed is still '0'; click Reject.
- **Fix.** Order the steps like the seller side: rs.ge confirm first, commit, then run _reconcile_buyer_goods inside _rs_post_commit (savepoint + rs_post_commit_error + drift retry). If the reconcile must stay first, wrap 595-603 in one env.cr.savepoint() and let a confirm failure roll it back.

### 52. Seller cancel cascade cancels a PO whose receipt is already done — received stock with no PO to bill against [C]
- **Module.** `rs_waybill + rs_einvoice (purchase bridge)`
- **Mechanism.** [Certain] When the synced/drift state becomes 'cancelled', _cascade_cancel_purchase cancels the linked PO. For a done receipt the picking is left alone (2092) and the PO is cancelled anyway. The docstring assumes a later type-5 return will fix the goods, but that return carries no PO link (known #25) and, more importantly, the PO is now in state 'cancel' with qty_received still 10.
- **Core collision.** Core purchase.order.button_cancel raises only for locked orders or non-draft bills; purchase_stock leaves done receipts untouched and posts a note. After cancel the PO's qty_to_invoice is forced to 0 and invoice_status to 'no', so Create Bill is impossible; the receipt's valuation entry (Stock Valuation / Stock Interim Received) has no bill to clear it, and any vendor bill pulled from rs.ge lands without purchase_line_id (see Reimport finding). Manual Odoo would refuse to cancel here by practice (reset the PO, bill it, then return via stock.return.picking).
- **Core evidence.** addons/purchase/models/purchase_order.py:641-649 (button_cancel), addons/purchase_stock/models/purchase_order.py:186-199 (done pickings only get a note), :204-208 (only non-done moves cancelled), addons/purchase/models/purchase_order_line.py:170-176 (qty_to_invoice 0 unless state 'purchase'), addons/purchase/models/purchase_order.py:50-51 (invoice_status 'no'); interim-account posting: not verified
- **Mismatch.** PO/003 10 × 100 GEL, receipt done: qty_received 10, on-hand +10, stock valuation +1,000. Vendor cancels the waybill on rs.ge → sync → PO/003 state 'cancel', invoice_status 'no', qty_to_invoice 0, qty_received still 10. Stock shows 1,000 GEL of goods bought from this vendor with a cancelled order and no billable line; the accrued-purchases report (received − invoiced) can never close for this PO.
- **Status.** **Not exercised on the gec_modules2 test DB** (same dormant bridge).
- **Provoke.** Buyer waybill in scope → PO + receipt; click Receive (receipt done). On rs.ge (or shell: wb.write({'state':'cancelled'}); wb._cascade_cancel_purchase()) cancel the waybill. PO state = cancel, receipt state = done, Create Bill unavailable.
- **Fix.** Skip the PO cancel when any line has qty_received > 0 (or any picking is done); post the activity the module already has and leave the PO in 'purchase' so it can still be billed or returned. A physical return goes through stock.return.picking on the done receipt (sets purchase_line_id, origin_returned_move_id, to_refund so qty_received drops), never through PO cancel.

### 53. Lines the vendor adds on the waybill enter the PO at product.standard_price, not the waybill price [C]
- **Module.** `rs_waybill + rs_einvoice (purchase bridge)`
- **Mechanism.** [Certain] _reconcile_buyer_goods creates PO lines for products the vendor added after the PO existed with price_unit = product.standard_price, while the waybill line for that product carries the vendor's unit_price. For an increase on an existing line the old price is kept. The initial PO creation (955) uses the waybill price, so the same waybill produces two price sources.
- **Core collision.** purchase_stock values incoming moves from the PO line price (_get_stock_move_price_unit → price_unit_discounted) and re-values moves when price_unit/product_qty change; qty_to_invoice and Create Bill take the PO line price. So the receipt's stock valuation and the proposed bill use a cost price (0.00 for products auto-created from rs.ge, known #30 population) instead of what the vendor declared and will invoice.
- **Core evidence.** addons/purchase_stock/models/purchase_order_line.py:238-241 (_get_stock_move_price_unit from price_unit_discounted), :111-121 (price write propagates to open moves and _set_value), addons/purchase/models/purchase_order_line.py:170-176 (qty_to_invoice); bill line price from _prepare_account_move_line: not verified
- **Mismatch.** Vendor adds product B 5 × 20 GEL to an active waybill (waybill total +100). Receive → PO line B: 5 × 0.00 (B was auto-created from rs.ge, standard_price 0) → PO amount_total unchanged, receipt move for B valued 0.00, stock valuation +0 instead of +100, Create Bill proposes 0.00 for B while the vendor's rs.ge e-invoice says 100 + 18 VAT.
- **Status.** **Not exercised on the gec_modules2 test DB** (same dormant bridge).
- **Provoke.** Buyer waybill → PO + receipt (Ready or done). Add a new product line 5 @ 20 on rs.ge and sync (or shell: create rs.waybill.line on wb with product B, quantity 5, unit_price 20; wb._compute_buyer_goods_delta()); click Receive. Open the PO: line B price 0.00 (or the product's cost), receipt SVL for B = 0.
- **Fix.** Use the matching waybill line's unit_price (as 955 does) for created lines, or omit price_unit and let purchase.order.line._compute_price_unit_and_date_planned_and_name pick the vendor pricelist. Price-only changes on existing lines are known #31/#35.

### 54. Vendor waybill always spawns a new PO; an existing open PO from the same vendor is never matched [C]
- **Module.** `rs_waybill + rs_einvoice (purchase bridge)`
- **Mechanism.** [Certain] _rs_create_purchase_from_waybill never searches purchase.order for an open order of the resolved vendor with unreceived lines for the same products; every in-scope buyer waybill creates and confirms its own PO. [Likely] In normal purchasing the buyer's PO exists before the vendor ships, so each delivery duplicates the order.
- **Core collision.** qty_received on the buyer's own PO counts only moves attached to that PO's lines (_get_po_line_moves); the receipt built for the module's PO belongs to the new PO, so the original stays 'To Receive' with its own Ready receipt, and purchase reporting counts the quantity twice. Core's own matching path (a receipt on the existing PO, quantities via stock.move.quantity, extra products via _action_synch_order which creates PO lines with product_qty 0 / qty_received on the SAME order) is bypassed.
- **Core evidence.** addons/purchase_stock/models/purchase_order_line.py:55-80 (_prepare_qty_received over line._get_po_line_moves), :168-198 (_create_or_update_picking attaches only to the line's own order pickings), addons/purchase_stock/models/stock_move.py:58-90 (_action_synch_order adds unlinked done moves to the picking's PO)
- **Mismatch.** PO/001 (manual) 100 units, receipt WH/IN/001 Ready. Vendor ships 40 with a waybill → PO/002 40 units + WH/IN/002; Receive → PO/002 qty_received 40, PO/001 qty_received 0, WH/IN/001 still Ready for 100; forecasted incoming 140 vs truth 60 outstanding; purchase.report ordered 140 for 100 bought; the vendor's bill (for PO/001) can only match one of the two orders.
- **Status.** **Not exercised on the gec_modules2 test DB** (same dormant bridge).
- **Provoke.** Confirm a manual PO for 100 of product A with vendor V. Sync (or Update) a buyer waybill from V for 40 of A in scope. Purchases list: two confirmed POs for V; Inventory → Receipts: two open/done receipts for the same goods.
- **Fix.** Before creating, search purchase.order [('partner_id.commercial_partner_id',…),('company_id',…),('state','=','purchase')] with lines whose qty_received < product_qty for the waybill's products; link the waybill to that PO and its open receipt, and drive quantities through the receipt's stock.move.quantity inverse (partial receipt + core backorder) instead of rewriting product_qty. If linking to a larger PO, _compute_buyer_goods_delta must compare against the receipt moves, not PO ordered quantity, or it will shrink the PO to the shipped quantity (same overwrite pattern as known #17).

### 55. Bill pulled from rs.ge is never linked to the PO the module built from the same waybill [C]
- **Module.** `rs_waybill + rs_einvoice (purchase bridge)`
- **Mechanism.** [Certain] rs_waybill builds and receives the PO from the vendor's waybill; rs_einvoice imports the vendor's e-invoice as bare bill lines (name/qty/price/tax only). Neither side looks the other up (rs_base_methods' waybill↔invoice link is metadata, and its invoice wizard is seller-side, known #32). The bill therefore never sets purchase_line_id, and the PO never sees the bill. [Likely] this is the default path for a vendor who files both a waybill and an e-invoice on rs.ge.
- **Core collision.** Core's vendor-bill flow (Create Bill from PO, or auto-complete from purchase_vendor_bill_id) sets purchase_line_id on every line so qty_invoiced, invoice_status, invoice_ids and the accrued-purchases report reconcile receipt against bill. Bare lines leave the PO 'Waiting Bills' with qty_to_invoice = qty_received forever.
- **Core evidence.** addons/purchase/models/purchase_order_line.py:189-199 (qty_invoiced from invoice_lines), :164-176 (qty_to_invoice = qty_received − qty_invoiced for receive-based products), addons/purchase/models/purchase_order.py:46-68 (invoice_status), :71-75 (invoice_ids)
- **Mismatch.** Waybill → PO/004 10 × 100, received 10 (qty_to_invoice 10, 'Waiting Bills'). Vendor e-invoice pulled → BILL/010 10 × 100 + 18% posted, payable 1,180. PO/004 still 'Waiting Bills', qty_invoiced 0, invoice_count 0. Accountant clicks Create Bill → BILL/011 1,180 → payable 2,360 for one delivery; accrual report shows 1,000 uninvoiced receipts indefinitely.
- **Status.** **Not exercised on the gec_modules2 test DB** (same dormant bridge) — confirmed 0 bill lines with purchase_line_id on gec_modules2.
- **Provoke.** Sync one in-scope buyer waybill (PO + receipt, Receive). Buyer Inbox → import the vendor's e-invoice for the same goods → post. Open PO/004: Billing Status Waiting Bills, Bills 0; Create Bill still offered.
- **Fix.** When a pulled bill's partner has a waybill-linked PO with qty_to_invoice > 0 (via rs.einvoice.waybill.link → rs.waybill.purchase_id, or vendor + products), create the bill with purchase.order.action_create_invoice / purchase.order.line._prepare_account_move_line and then overlay rs.ge qty/price with _rs_merge_pulled_to_bill_lines, so purchase_line_id/product/account/analytic come from core.

### 56. Update-button backfill creates the PO in the user's active company, not the waybill's company [C]
- **Module.** `rs_waybill + rs_einvoice (purchase bridge)`
- **Mechanism.** [Certain] The cron sync is scoped (rs_waybill_sync.py:109, 164, 202: with_company(company)) so its POs land in the right company. The Update button (action_update_rs_status) and its backfill run in the operator's active company with no with_company(self.company_id); purchase.order takes company_id from env.company and picking_type from that company's warehouse. Opposite direction of known #28 (waybill company from env.company): here the PO/receipt company diverges from the waybill's company.
- **Core collision.** purchase.order.company_id defaults to env.company; _prepare_picking uses order.picking_type_id (the env company's default warehouse). Multi-company rule: a document's company must follow the source document, not the active company.
- **Core evidence.** addons/purchase/models/purchase_order.py:160 (company_id default env.company), :91-94 (partner_id check_company=True), addons/purchase_stock/models/purchase_order.py:377-386 (_create_picking with order.company_id / order._prepare_picking)
- **Mismatch.** Waybill W (company B, TIN B, buyer_tin B) has no PO yet (product just mapped). Operator with active company A opens W and clicks Update → PO/A-005 company A, receipt in A's warehouse, Receive → on-hand +10 in company A; W.company_id = B, B has no PO/receipt, B's qty_received 0 while B is the taxpayer that received the goods on rs.ge.
- **Status.** **Not exercised on the gec_modules2 test DB** (same dormant bridge).
- **Provoke.** Two companies with rs.ge credentials. Company selector = A. Open a company-B buyer waybill whose lines were just mapped (no purchase_id), click Update. PO company = A.
- **Fix.** Create through self.env['purchase.order'].with_company(self.company_id) with 'company_id': self.company_id.id and a picking_type_id from a warehouse of that company; same in the type-5 return-delivery builder (973-1026 already passes company_id on the picking but takes the warehouse by company — keep that pattern).

### 57. Two-step PO approval leaves the waybill without a receipt; the receipt created at approval is never linked [C]
- **Module.** `rs_waybill + rs_einvoice (purchase bridge)`
- **Mechanism.** [Certain] button_confirm puts the PO in 'to approve' when the company uses two-step validation, the amount is at/over the limit and the acting user is not a purchase manager (the sync borrows the lowest-id credentialed user). No receipt exists, waybill.picking_id stays empty, and _rs_has_outstanding_step returns False because purchase_id is set. Receive then confirms on rs.ge with no stock movement. When a manager approves later, _create_picking builds the receipt, but nothing links it to the waybill, so _cascade_validate_receipt never validates it.
- **Core collision.** purchase.order.button_confirm → 'to approve' branch skips button_approve, and purchase_stock creates the receipt only in button_approve.
- **Core evidence.** addons/purchase/models/purchase_order.py:625-639 (to approve branch), :1249-1258 (_approval_allowed), addons/purchase_stock/models/purchase_order.py:177-180 (_create_picking only in button_approve)
- **Mismatch.** Company two_step, limit 5,000 GEL; vendor waybill 8,000 GEL synced by a non-manager credentialed user → PO 'To Approve', waybill.picking_id NULL. Receive → rs.ge is_confirmed 1; Odoo qty_received 0, on-hand +0. Manager approves → WH/IN Ready, waybill_id NULL, stays Ready until validated by hand; drift/repair never picks it up.
- **Status.** **Not exercised on the gec_modules2 test DB** (same dormant bridge; also needs two-step PO approval, which gec_modules2 does not use — both companies are one_step).
- **Provoke.** Settings → Purchase → Purchase Order Approval = two levels, limit 5,000; make the rs.ge credentialed user a Purchase User only. Sync an 8,000 GEL buyer waybill → PO state 'to approve', wb.picking_id empty. Click Receive → is_confirmed '1', no receipt done. Live DBs are one_step today (gec_modules2), so latent.
- **Fix.** After button_confirm, if state == 'to approve' do not confirm on rs.ge automatically: raise the activity the module already uses and stop; in an override of purchase.order.button_approve, when the order has waybill_id records with no picking_id, link the freshly created incoming picking (picking.waybill_id / waybill.picking_id) so the existing receive cascade validates it.

### 58. Completion cascade closes a partially reserved delivery: remainder becomes a backorder with its own auto-waybill while the first waybill already declared the full quantity [C]
- **Module.** `rs_waybill (stock core)`
- **Mechanism.** [Certain] _do_validate_linked_picking lets a picking in state partially_available through and calls button_validate() with skip_backorder=True. In core that context only suppresses the backorder wizard; _action_done then runs with cancel_backorder=False, so core validates what is reserved and creates a backorder for the rest. The module's stock.picking._create_backorder override immediately creates a second draft waybill on that backorder. The completed waybill (the rs.ge legal document) keeps the full line quantity; the code never compares move.quantity with the waybill line quantity and never records the gap in pending_return_json. If the picking type has create_backorder='never', core cancels the remainder instead, and the SO line stays under-delivered with no re-procurement.
- **Core collision.** Core standard flow: a user validating a partially reserved picking is asked by the backorder wizard, or explicitly chooses no-backorder; either way the delivered document (the picking) says what shipped. Here the rs.ge waybill says the full quantity, the picking says less, and a second waybill is spawned for the same goods.
- **Core evidence.** addons/stock/models/stock_picking.py:1487-1490 (skip_backorder only skips _action_generate_backorder_wizard), 1420-1427 (cancel_backorder=False unless picking type create_backorder == 'never'), addons/stock/models/stock_move.py:2096-2107 and 2138-2139 (unpicked/zero-quantity moves are split into a backorder, cancelled only when cancel_backorder), addons/stock/models/stock_move.py write (demand raised above reserved quantity flips 'assigned' to 'partially_available' without unreserving) read in this session
- **Mismatch.** Waybill WB1 completed on rs.ge with line A = 12. Odoo: WB1.picking_id done with move A quantity 10, SO line A qty_delivered 10 (ordered 12), backorder picking with move A demand 2 in state confirmed, plus a new draft waybill WB2 with line A = 2 linked to the backorder. rs.ge total declared for A = 12 now, 14 once WB2 is activated; Odoo delivered 10. With create_backorder='never': move for 2 cancelled, SO line ordered 12 / delivered 10 forever.
- **Status.** **Reproducible in code**; not checked against a live occurrence.
- **Provoke.** SO for 10 of A, 10 in stock, delivery Ready, waybill saved+activated on rs.ge (line 10). Edit the waybill, raise A to 12, submit (rs.ge accepts 12; _apply_line_diffs_to_picking_in_place sets move demand 12, action_assign reserves nothing more, picking becomes partially_available). Close the waybill on rs.ge (or sync a status-2 row) so _cascade_validate_picking runs. Result: picking Done with 10, backorder for 2 with a fresh draft waybill, no chatter message about the 2-unit gap.
- **Fix.** In _do_validate_linked_picking, before button_validate, compute per product max(0, waybill line qty - move.quantity) for outgoing pickings and feed it into the module's own reconcile path (pending_return_json + the Return Decision wizard: physical return via stock.return.picking, or paperwork-only), exactly as _apply_rs_goods_diff_auto does at 1568-1580; and skip the backorder auto-waybill for a backorder whose parent picking's waybill already covers the demand (module stock_picking.py:551-559). Do not add a user-facing validation; this is skipping an automatic destructive action.

### 59. Seller-side RS goods auto-apply swallows exceptions without a savepoint, so a multi-line change is applied half-way and the sync commits it; the snapshot is gone, so it is never retried [C]
- **Module.** `rs_waybill (stock core)`
- **Mechanism.** [Certain] _apply_rs_goods_diff_auto catches every exception, posts a chatter note and clears the snapshot. Diffs are applied one after another; a UserError in the third diff leaves the first two written. The sync loop then commits the row (its rollback only triggers when the exception escapes, which it never does here). On the next sync the waybill lines already equal rs.ge, so _compute_line_diff returns nothing and the missing part is never re-applied. Seller-side sibling of known item 20 (which covers only _reconcile_buyer_goods).
- **Core collision.** Core raises UserError('You need to supply a Lot/Serial Number for product') from stock.move.line._action_done and expects the caller's transaction to roll back; here the partial state is committed. Core's own pattern for tolerated partial failures is cr.savepoint() per unit of work.
- **Core evidence.** addons/stock/models/stock_move_line.py:664 (Lot/Serial UserError raised in _action_done); addons/stock/models/stock_move.py:2082-2107 (_action_done) read; module sync commit at rs_waybill_sync.py:578 read
- **Mismatch.** rs.ge edit on a completed seller waybill: A 10 -> 12 and new lot-tracked product B = 3. After sync: done move A quantity 12, SO line A ordered 12 / delivered 12 (applied); SO line B ordered 3 / delivered 0 with a supplementary delivery for B left in state confirmed/assigned (procurement ran, _action_done raised); waybill line B quantity 3 with stock_move_id empty. rs.ge says 15 units delivered, Odoo 12. Next sync: no diff, nothing pending, only a chatter note.
- **Status.** **Reproducible in code**; not checked against a live occurrence.
- **Provoke.** Completed seller waybill with SO + done delivery for A=10. On rs.ge edit the waybill: A=12 and add B (a lot-tracked product) 3. Run the seller sync. Check chatter ('could not be auto-applied ... Lot/Serial'), then wb.sales_order_id.order_line: A 12/12, B 3/0; wb.line_ids for B has no stock_move_id; open delivery for B exists. Run sync again: unchanged.
- **Fix.** Wrap each diff in `with self.env.cr.savepoint():` (core partial-failure pattern) and, on failure, append the failed diff to a pending field (reuse pending_return_json / pending_goods_json style) so action_reconcile_pending_return or the drift job re-applies it; for lot-tracked 'added' products leave the procured delivery Ready for the warehouse (as the tracked_unfilled branch at 2029-2032 already does for receipts) instead of forcing _action_done.

### 60. _action_reverse_completed_waybill cancels on rs.ge and locally but never persists the return quantities; closing the popup leaves a cancelled waybill with a done delivery and no way back [C]
- **Module.** `rs_waybill (stock core)`
- **Mechanism.** [Certain] The completed-waybill cancel path sends refuse_waybill to rs.ge, writes state='cancelled' and returns a TransientModel wizard. The qty_to_return dict lives only in the wizard record. If the user closes the dialog, presses Escape, or the request errors after the rs.ge call, nothing records that a return is owed. Known item 21 covers the same hole on the manual-edit path (action_submit_edit_to_rs); this is the cancel path, and the fix planned for item 24 routes every refuse-on-done-picking into this method, widening the exposure.
- **Core collision.** Core has no concept of an rs.ge cancellation; the Odoo-side state it leaves is a done delivery (quants moved, SO qty_delivered counted, invoiceable) whose legal document has been voided, with no stock.return.picking created and no marker that one is owed.
- **Core evidence.** not verified (module-only logic; core return mechanism stock.return.picking read at addons/stock/wizard/stock_picking_return.py:161-220)
- **Mismatch.** Waybill: state cancelled, waybill_status -2, rs.ge cancelled. Odoo: picking done, quant for A -10, SO line A qty_delivered 10, invoice_status 'to invoice' for 10, pending_return_json empty, Reconcile Delivery button raises 'Nothing to reconcile'. rs.ge says 0 delivered; Odoo says 10 delivered and billable.
- **Status.** **Reproducible in code**; not checked against a live occurrence.
- **Provoke.** Completed seller waybill on a done delivery for 10 of A. Click Refuse/Cancel Waybill (state completed -> _action_reverse_completed_waybill). When the Return Decision popup opens, close it with X. Check wb.state == 'cancelled', wb.picking_id.state == 'done', wb.pending_return_json is False, Create Invoice on the SO offers 10.
- **Fix.** Before returning the wizard at 1518, persist the dict: self.pending_return_json = json.dumps({str(k): v ...}) exactly as the auto path does at 1568-1576; the wizard already clears it on either button and action_reconcile_pending_return re-opens it. Keep the rs.ge refuse first (deliberate orphan protection), but the local write at 1512 plus the pending marker should be the last thing before the popup.

### 61. Vendor-added product on a buyer waybill becomes a PO line priced at product cost, not the rs.ge unit price, so the vendor bill built from the PO disagrees with the waybill [C]
- **Module.** `rs_waybill (stock core)`
- **Mechanism.** [Certain] When the vendor adds a product that is not yet on the PO, _reconcile_buyer_goods creates the PO line with price_unit = standard_price (average/standard cost) instead of the waybill line's unit_price that the sync just wrote. Quantities are reconciled on every Receive, the price never is. The PO amount and any bill created from it (Create Bill / e-invoice matching) carry the wrong price. Known item 31 is about normalising the rs.ge price (VAT-inclusive, unit, currency); this item ignores the rs.ge price entirely. Also applies when the product has no PO line in the not-done branch (1705-1714).
- **Core collision.** Core purchase bills take price_unit from the PO line (_prepare_account_move_line), so the wrong PO price propagates to account.move.line and to purchase price reporting; core's own receipt-time flow never invents a price.
- **Core evidence.** addons/purchase/models/purchase_order_line.py:588 (_prepare_account_move_line price_unit = PO line price_unit converted) read
- **Mismatch.** rs.ge waybill line B: 10 x 25 GEL = 250. PO line B created by reconcile: 10 x standard_price 20 = 200. Vendor bill from PO: B 200 vs e-invoice/waybill 250; PO amount_total off by 50 (before VAT). _compute_buyer_goods_delta returns {} afterwards, so nothing flags it.
- **Status.** **Not exercised on the gec_modules2 test DB** (same dormant buyer-PO bridge as the purchase group).
- **Provoke.** Buyer waybill synced with PO + receipt for A. On rs.ge the vendor adds product B, qty 10, price 25 (B's cost in Odoo is 20). Sync, then click Receive. Open the PO: line B price 20. Create Bill: line B 200. Waybill line B shows unit_price 25.
- **Fix.** Use the waybill line's price like _rs_create_purchase_from_waybill does (955): look up self.line_ids by product and pass line.unit_price (after whatever normalisation item 31 decides). Also write price_unit on existing PO lines when the synced unit_price changed, so PO and rs.ge agree on amount, not only quantity.

### 62. moves._action_done() bypasses stock.picking._action_done: hook-built receipts and supplementary deliveries end Done with no date_done, no _trigger_assign of waiting moves, no confirmation email [C]
- **Module.** `rs_waybill (stock core)`
- **Mechanism.** [Certain] The picking's state becomes 'done' through _compute_state once all its moves are done, but everything stock.picking._action_done does at picking level is skipped: date_done is never written, done incoming moves do not run _trigger_assign for confirmed/partially_available moves of the same product, and the delivery confirmation email is not sent. This is distinct from the refuted point (calling the move-level API is legitimate); the finding is the concrete picking-level state left behind.
- **Core collision.** stock.picking._action_done writes date_done and priority, runs _trigger_assign for incoming/internal done moves and _send_confirmation_email; stock.move._action_done does none of these. sale_stock and purchase_stock derive effective_date (Arrival) from picking.date_done and sale copies effective_date into the invoice's delivery_date.
- **Core evidence.** addons/stock/models/stock_picking.py:1256-1282 (picking-level _action_done: date_done write at 1274, _trigger_assign 1277-1278, email 1280), 606 (date_done is a plain stored field, no compute), 816-846 (_compute_state derives 'done' from moves); addons/stock/models/stock_move.py:2082-2147 (no date_done write); addons/stock/models/stock_move.py:2451-2463 (_trigger_assign reserves waiting make_to_stock moves); addons/purchase_stock/models/purchase_order.py:55-58 and addons/sale_stock/models/sale_order.py:84-88 (effective_date filters date_done, so it stays False rather than crashing); addons/sale_stock/models/sale_order.py:301 (invoice delivery_date = effective_date)
- **Mismatch.** Vendor raises A by 2 on a buyer waybill; Receive -> hook-built receipt WH/IN/00042: state 'done', date_done NULL, Date of Transfer empty in the list; PO receipt_status 'full' but effective_date (Arrival) False when this is the PO's only done receipt; quant A +2 while an existing SO delivery for A in state 'confirmed' stays unreserved until the scheduler runs (core would have reserved it immediately). Seller side: the supplementary delivery for an added product is Done with date_done NULL, so SO effective_date and the invoice delivery_date miss it.
- **Status.** **Reproducible in code**; not checked against a live occurrence.
- **Provoke.** Buyer waybill with PO + done receipt for A=10, another SO delivery for 2 of A waiting (0 on hand after the first receipt). Vendor edits the waybill to A=12 on rs.ge; sync; click Receive. Inspect the new receipt: state done, date_done empty; the waiting delivery is still 'confirmed'. Purchase order form shows Arrival empty.
- **Fix.** Validate at picking level with core: mark only the module's moves picked (move.quantity = move.product_uom_qty; move.picked = True, the core inverse already recommended for item 15) and call picking.with_context(skip_backorder=True).button_validate(); core then puts the other unpicked moves into a backorder (cancel_backorder=False) and runs date_done/_trigger_assign/email. If a picking must never be touched as a whole, split the module's moves into their own picking first with the core _create_backorder/_split mechanism rather than calling _action_done on a subset.

## Session 3 — Sale-flow and stock-actions/sync sweep (2026-09-19)

The two readers left unfinished in Session 2 (workflow stopped early), re-run to completion, no verify pass, same rules (no XML/CSV/tests, no user-facing validations proposed). Neither reader ran a psql check, so nothing here is marked against the gec_modules2 test DB — every item is a code-level finding.

Two of the six matter most: **#63** and **#65** both show the `rs_invoice_from_waybill_wizard` can attach an invoice line to the wrong sale order line, or push a sale order line's invoiced quantity past what it was ever delivered, with no warning and no checkbox — the wizard's own safety gates (`has_unmatched`, `has_overdelivery`) don't cover the cases that actually produce a wrong `qty_invoiced`. **#66** shows the four-button invoice lock (`_rs_assert_not_invoice_linked`) is bypassed by every automatic path (Update button, sync cron, drift-repair cron) — the one guard meant to force a quantity change through an invoice correction is defeated by rs.ge itself.

| # | Prio | Module | Area | Issue |
|---|---|---|---|---|
| 63 | P1 | `rs_base_methods (invoice-from-waybill wizard)` | sale | Wizard's matcher can silently attach an invoice line to an unrelated sale order when the intended SO has no open candidate line |
| 64 | P2 | `rs_base_methods (invoice-from-waybill wizard)` | sale | Overdelivery confirmation is checked per wizard line against a static SO remaining quantity, so two lines matched to the same sale order line can jointly exceed it without the confirm checkbox ever being required |
| 65 | P1 | `rs_base_methods (invoice-from-waybill wizard)` | sale | Standalone wizard mode skips the unmatched/overdelivery confirmation gates entirely, even though the same per-line SO matching that needs them still runs |
| 66 | P1 | `rs_waybill (actions/sync/bridge)` | stock | Invoice-lock guard only covers the four manual buttons; RS-driven sync/Update/drift paths silently rewrite an already-invoiced waybill's delivered quantities |
| 67 | P2 | `rs_waybill (actions/sync/bridge)` | stock | Drift-repair cron explicitly targets company_id=False waybills for repair but never writes company_id, so they stay unscoped forever and get polled under every company's credentials |
| 68 | P2 | `rs_waybill (actions/sync/bridge)` | stock | Goods lines are matched to RS.GE items by (bar_code, name) with FIFO order, not by the stable rs_good_id both sides already carry — duplicate-named lines can have quantity/price cross-assigned to the wrong stock move |

---

### 63. Wizard's matcher can silently attach an invoice line to an unrelated sale order when the intended SO has no open candidate line [C]
- **Module.** `rs_base_methods (invoice-from-waybill wizard)`
- **Mechanism.** _match_sale_line first tries to narrow candidates to the waybill's own sale order or the wizard's seed/common SO (preferred_so, lines 118-129). If that SO simply has no sale.order.line for this product with qty_to_invoice>0 (product not ordered there, or already fully invoiced through another channel), on_preferred is empty and `narrowed` stays False, so `candidates` reverts to the FULL, partner+product-scoped, cross-SO search result built at wizard_line.py:76-89 / 96-106 (no order_id restriction at all). Line 130-131 then returns that global candidate whenever exactly one exists anywhere for the same partner+product, with no further check that it belongs to the SO the wizard/waybill is actually about.
- **Core collision.** sale.order.line.qty_invoiced is computed purely from invoice_line.sale_line_ids (addons/sale/models/sale_order_line.py:996-1005, _prepare_qty_invoiced sums every non-cancelled invoice line reachable through sale_line_ids) and qty_to_invoice/invoice_status follow from it (1037-1064). Odoo has no mechanism to detect 'this invoice line was meant for a different SO'; whichever sale.order.line the invoice line names via sale_line_ids is the one whose books move.
- **Core evidence.** addons/sale/models/sale_order_line.py:996-1005 (_prepare_qty_invoiced), :1037-1064 (_compute_qty_to_invoice / invoice_status), :1472-1500 (_prepare_invoice_line sets sale_line_ids via Command.link(self.id)) — all read this session.
- **Mismatch.** SO-A (the real order behind this waybill's delivery) never ordered product X — only products Y and Z. SO-Z, an older, unrelated open order for the SAME customer, still has product X with qty_to_invoice=6. The delivery waybill for SO-A also happens to carry a line for product X (e.g. a substitution or extra item the vendor shipped, quantity 4). _match_sale_line: preferred_so=SO-A, candidates for (partner, X) = {SO-Z's line} only (SO-A has none), on_preferred empty -> narrowed=False -> candidates stays {SO-Z line} -> len==1 -> matched to SO-Z. Result: SO-Z.qty_invoiced jumps from 0 to 4 (of an order it never delivered anything for) and its invoice_status can flip to Fully Invoiced/Invoiced; SO-A shows no trace of this line at all. The created invoice's invoice_origin still reads 'SO-A' (from seed._prepare_invoice(), never overwritten because distinct_sos has only 1 member, wizard.py:455) while the invoice line's sale_line_ids point at SO-Z - the invoice's own Source Document field disagrees with the sale order it actually updated.
- **Status.** Not checked against the gec_modules2 test DB — code-level finding only.
- **Provoke.** Open the wizard from SO-A's Sale Order (whose delivery included an extra/substituted product X not on SO-A's own lines), pick the waybill, and create the invoice. Neither has_unmatched (line is matched, just to the wrong order) nor has_overdelivery (SO-Z has plenty of remaining) fires, and _validate_preflight's SO-consistency check only compares waybill_ids.mapped('sales_order_id') to seed_sale_order_id (wizard.py:254,271-277) - it never looks at line_ids.mapped('sale_line_id.order_id'), so this cross-order attachment passes silently with no checkbox to tick.
- **Fix.** In _match_sale_line, when on_preferred is empty, do not fall back to a global cross-SO search at all for a wizard opened with a seed/common SO - return False (unmatched) instead, the same as the ambiguous-natural case already does at line 142. Separately, in _validate_preflight, compare self.line_ids.mapped('sale_line_id.order_id') (not just waybill_ids.mapped('sales_order_id')) against seed_sale_order_id/common_sale_order_id and raise the existing 'different sale orders' UserError (wizard.py:266-270) when they diverge.

### 64. Overdelivery confirmation is checked per wizard line against a static SO remaining quantity, so two lines matched to the same sale order line can jointly exceed it without the confirm checkbox ever being required [C]
- **Module.** `rs_base_methods (invoice-from-waybill wizard)`
- **Mechanism.** has_overdelivery is `any(l.quantity > l.qty_to_invoice_remaining for l in line_ids)` - a per-line comparison. qty_to_invoice_remaining is a related field straight to sale_line_id.qty_to_invoice, i.e. the SO line's currently STORED remaining-to-invoice quantity; it is not reduced within the wizard as other lines destined for the same sale_line_id are considered, and each of those sibling lines becomes its own separate invoice_line_ids entry when the wizard is not in standalone mode (wizard.py:466-469, one Command.create per wizard line, no aggregation), so nothing sums them before comparing to the limit.
- **Core collision.** account.move.create() posts every one of those Command.create entries as its own invoice line carrying sale_line_ids=[that SO line]; sale.order.line.qty_invoiced then sums quantity across ALL of them (addons/sale/models/sale_order_line.py:996-1005), with no cap at product_uom_qty or at the qty_to_invoice value read earlier. Core relies entirely on the caller not to invoice more than qty_to_invoice in one pass; this wizard's own safety gate is what is supposed to enforce that, and it doesn't when the excess is split across lines.
- **Core evidence.** addons/sale/models/sale_order_line.py:996-1005 (_prepare_qty_invoiced, no cap), :1037-1052 (_compute_qty_to_invoice = product_uom_qty/qty_delivered minus qty_invoiced) - both read this session.
- **Mismatch.** Sale order line: product A, ordered 10, delivered 10, qty_invoiced 0 -> qty_to_invoice_remaining = 10 for every wizard line that matches it. Two different waybills (e.g. two partial deliveries the operator is invoicing together) both match this same sale_line_id, each declaring 8 units. Per line: 8 <= 10 -> has_overdelivery stays False for both, no confirmation asked. The invoice is created with two separate 8-unit lines against the same sale_line_id -> qty_invoiced becomes 16 against an ordered/delivered quantity of 10, invoice_status flips to Fully Invoiced for a line invoiced 60% past its ordered amount, and nobody ever saw or ticked 'Confirm: over-delivery OK'.
- **Status.** Not checked against the gec_modules2 test DB — code-level finding only.
- **Provoke.** From an SO with one line (qty 10, fully delivered, nothing invoiced), pick two waybills whose lines both correctly match that same SO line (a realistic split-delivery case) with quantities 8 and 8. Submit the wizard: no warning, no checkbox required, invoice created for 16 units against a 10-unit order line.
- **Fix.** Compute has_overdelivery (and the block in _validate_preflight, lines 313-318) from a running total per sale_line_id across all wizard lines in the SAME submission - e.g. group line_ids by sale_line_id, sum quantity per group, and compare the sum to that sale_line_id's qty_to_invoice - instead of comparing each line in isolation to the same unreduced related field.

### 65. Standalone wizard mode skips the unmatched/overdelivery confirmation gates entirely, even though the same per-line SO matching that needs them still runs [C]
- **Module.** `rs_base_methods (invoice-from-waybill wizard)`
- **Mechanism.** Both confirmation checks are wrapped in `if not self.is_standalone`: `if (not self.is_standalone and self.has_unmatched and not self.i_confirm_unmatched): raise ...` and the identical pattern for has_overdelivery (lines 307-318). The is_standalone docstring claims this is safe because standalone mode 'enables line aggregation' (which nets returns against deliveries), but _match_sale_line (wizard_line.py) runs unconditionally regardless of is_standalone, and _aggregate_invoice_lines only rejects a NET-NEGATIVE bucket (lines 406-410); it has no check that a bucket's summed quantity stays within its matched sale_line_id's qty_to_invoice.
- **Core collision.** Same as the overdelivery mechanism above: sale.order.line.qty_invoiced (addons/sale/models/sale_order_line.py:996-1005) sums whatever the invoice ends up carrying in sale_line_ids, uncapped. The wizard's own gate is the only thing standing between 'waybill lines happen to match a real SO line' and an uncontrolled qty_invoiced write; standalone mode removes that gate while still doing the matching that can produce a match.
- **Core evidence.** addons/sale/models/sale_order_line.py:996-1005, :1037-1052 (read this session, same citations as the previous finding).
- **Mismatch.** Standalone wizard (opened from the waybill list, no seed SO) with a single waybill line for product A, quantity 20, that matches (via _rs_prefetch_sale_line_candidates / _match_sale_line, which does not consult is_standalone) an open sale.order.line for product A with qty_to_invoice = 5. is_standalone is True, so the has_overdelivery block (wizard.py:313-318) never runs; _aggregate_invoice_lines only rejects when the summed bucket quantity is negative (line 407), and +20 is not negative, so it passes straight into invoice_line_ids with sale_line_ids set (line 422-423). The SO line's qty_invoiced becomes 20 against an ordered/delivered amount of 5, with the operator never told an SO line even existed.
- **Status.** Not checked against the gec_modules2 test DB — code-level finding only.
- **Provoke.** Open the wizard from the Waybills list (default_is_standalone context) for a waybill whose product happens to match an open, mostly-already-invoiced SO line for the same partner. Create the invoice: it posts with no unmatched/overdelivery warning of any kind, and the matched SO line is now overinvoiced.
- **Fix.** Drop the `not self.is_standalone` guard on the overdelivery check specifically (it is about a concrete matched sale_line_id, which can occur in standalone mode); keep it only for has_unmatched if unmatched lines are truly expected/normal in standalone use. Alternatively extend _aggregate_invoice_lines' existing negative-quantity guard (lines 396-434) to also compare each bucket's summed quantity against its sale_line_id's qty_to_invoice and route an excess into the same UserError path used for negative buckets.

### 66. Invoice-lock guard only covers the four manual buttons; RS-driven sync/Update/drift paths silently rewrite an already-invoiced waybill's delivered quantities [C]
- **Module.** `rs_waybill (actions/sync/bridge)`
- **Mechanism.** rs_base_methods/rs_waybill.py:67-80 defines _rs_assert_not_invoice_linked(), raising when is_locked_by_invoice is True (a non-cancelled account.move holds this waybill via rs.einvoice.waybill.link, computed at lines 26-40). It is applied only to action_refuse_waybill, action_edit_waybill, action_submit_edit_to_rs and action_delete_waybill (lines 82-96) — the four buttons an operator would click. It is NOT applied to action_update_rs_status (rs_waybill_actions.py:315-371), which unconditionally calls self.write(vals), self._sync_goods_lines(goods) and self._apply_rs_goods_diff_auto(goods_snapshot) at lines 326-332, nor to the cron/sync engine: rs_waybill_sync.py's _process_rs_rows existing-branch (lines 479-491, esp. existing._apply_rs_goods_diff_auto(goods_snapshot) at 491) and _cron_rs_drift_repair_one (lines 1141-1157, esp. waybill._apply_rs_goods_diff_auto(goods_snapshot) at 1149). All three call sites also run _cascade_validate_picking()/_cascade_validate_receipt() afterwards with no lock check.
- **Core collision.** Module-internal invariant collision, with a downstream sale-order effect. The guard's own message says a locked waybill can only change "by making a correction on the invoice" — but _apply_rs_goods_diff_auto (per this codebase's own already-documented items #58/#59) edits done-move quantities directly, which drives sale.order.line.qty_delivered on the linked SO. That compute path is core (addons/sale/models/sale_order_line.py qty_delivered from stock moves) but its exact line was not re-read in this session — not verified here; the confirmed defect is that three separate code paths reach the same quantity-mutating method the four guarded buttons are explicitly blocked from reaching.
- **Core evidence.** not verified for the exact sale_order_line.qty_delivered compute in this session. The bypass itself is directly verified: rs_base_methods/rs_waybill.py:82-96 lists exactly 4 overridden actions; rs_waybill_actions.py:326-332 and rs_waybill_sync.py:484-491,1146-1149 call the same goods-diff/validate machinery with no is_locked_by_invoice check anywhere in either file.
- **Mismatch.** Waybill WB-1 delivered 10 units, invoiced via rs.einvoice.waybill.link (is_locked_by_invoice=True — Edit/Refuse/Delete now correctly refuse with "attached to an invoice"). The seller then edits WB-1's quantity to 12 directly on rs.ge (not through Odoo). Next drift-repair pass or a click on "Update" pulls goods=12, bypasses the lock, and (per the already-documented diff-apply mechanism) bumps the done delivery/SO line to 12. Result: SO line shows delivered 12 / invoiced 10 with no invoice correction trail, even though the whole point of the lock was to force any such change through "a correction on the invoice" — the guard is defeated by the one code path (RS itself) that is guaranteed to eventually disagree with a posted invoice.
- **Status.** Not checked against the gec_modules2 test DB — code-level finding only.
- **Provoke.** Post a seller invoice from a waybill (rs.einvoice.waybill.link created, is_locked_by_invoice=True). Confirm the Edit Waybill button now raises "attached to an invoice". On rs.ge (or in shell) change a goods quantity on the same waybill, then either click Update on the waybill or let the drift-repair cron run. The quantity changes locally with no error and no reference to the invoice being out of sync.
- **Fix.** Reuse the same _rs_assert_not_invoice_linked() check (or a read-only variant of it) as a guard inside action_update_rs_status before calling _apply_rs_goods_diff_auto/_cascade_validate_picking, and inside _process_rs_rows / _cron_rs_drift_repair_one before the same calls — when locked, skip the auto-apply and log/flag it (the same activity-scheduling pattern rs_einvoice already uses for other skip-and-flag cases) instead of applying it silently.

### 67. Drift-repair cron explicitly targets company_id=False waybills for repair but never writes company_id, so they stay unscoped forever and get polled under every company's credentials [C]
- **Module.** `rs_waybill (actions/sync/bridge)`
- **Mechanism.** _map_rs_waybill_vals (lines 595-691) builds the full field-value dict used both by the sync engine and the drift-repair cron to detect and apply changes — it never includes a 'company_id' key. _cron_rs_drift_repair_one's domain (lines 1096-1102) explicitly includes '|', ('company_id','=', sync_company.id), ('company_id','=', False), with the code's own comment (1099-1101) saying company_id=False rows "predate the company field; sweep them with the first pass rather than leaving them permanently unchecked." The 'drifted' dict (lines 1123-1139) is built purely by iterating vals.items(), so 'company_id' can never appear in it; waybill.write(drifted) at 1144 therefore never sets company_id, yet waybill.rs_drifted_checked is stamped at line 1187 regardless — the row is marked "checked" without ever being fixed.
- **Core collision.** Multi-company scoping/record rules key off company_id; a permanently NULL company_id on a business record is a state the company field was added specifically to eliminate (per the module's own res_company.py migration note read in this same scope). Not verified against this specific model's ir.rule XML in this pass (XML reads excluded from scope by the task's own instructions), so the exact visibility behavior under the record rule is not verified.
- **Core evidence.** not verified against ir.rule XML (excluded from this task's scope). Directly verified in Python: rs_waybill_sync.py:595-691 (_map_rs_waybill_vals return dict has no 'company_id' key at any point), :1096-1102 (drift domain explicitly OR's in company_id=False), :1099-1101 (comment stating intent to sweep/repair these rows), :1123-1144 (drifted dict built only from vals.items(), then written), :1187 (rs_drifted_checked stamped unconditionally after the try block).
- **Mismatch.** Waybill WB-old has company_id=False (created before the company field existed) and its picking_id.company_id = Company A. Company A's drift pass matches it via ('company_id','=', A.id) OR ('company_id','=', False) — either clause matches — fetches it fine and finds nothing else drifted, sets rs_drifted_checked=now(). Company B's drift pass (run under B's own rs.ge credentials) ALSO matches the SAME row via ('company_id','=', False), and calls service.get_full_waybill(waybill.rs_internal_id) using B's credentials for a waybill whose rs_internal_id belongs to A's rs.ge taxpayer account. Every future cycle repeats this: the row's company_id never gets set, so it is re-fetched under whichever company happens to run next, forever, and any report or view scoped by company_id treats it as belonging to no one or everyone depending on the record rule.
- **Status.** Not checked against the gec_modules2 test DB — code-level finding only.
- **Provoke.** In a two-company database, create (or simulate via shell) an rs.waybill row with company_id set to False and rs_internal_id pointing to a real waybill under Company A's rs.ge account. Run the drift-repair cron once under Company A's credentials, then once under Company B's credentials (both companies' passes share the domain's ('company_id','=', False) branch). Confirm via SELECT that company_id is still NULL after both passes and that rs_drifted_checked advanced each time.
- **Fix.** In _map_rs_waybill_vals, when the waybill being processed has no company_id, include 'company_id': self.env.company.id in the returned vals (the same one-time-fill pattern the akciz sync in product_product.py already uses: 'only write what actually differs' plus never overwrite a value already set) so the very first successful repair or sync pass under the correct company's credentials stamps it permanently.

### 68. Goods lines are matched to RS.GE items by (bar_code, name) with FIFO order, not by the stable rs_good_id both sides already carry — duplicate-named lines can have quantity/price cross-assigned to the wrong stock move [C]
- **Module.** `rs_waybill (actions/sync/bridge)`
- **Mechanism.** _sync_goods_lines builds existing_by_key = {(bar_code, name): [lines...]} (lines 725-728) and, for each RS goods item, picks 'the first unmatched existing line with that key' (lines 749-754) — pure FIFO by whatever order self.line_ids and the RS goods list happen to be in. _goods_lines_changed (694-706) does the same thing via a sort-and-zip. Neither ever consults rs_good_id, even though rs.waybill.line.rs_good_id is stored (written at line 764/837 and read at 764) and RS's own item carries item.get('ID'). The module's own comment on _sync_rs_good_ids (line 828-831) states order is guaranteed only for the save_waybill response ('RS returns goods in the same order they were sent'), i.e. no such guarantee is claimed for get_full_waybill/get_waybills — the calls _sync_goods_lines actually consumes its data from.
- **Core collision.** Not a core-Odoo API collision directly; the collision is with the module's own downstream consumer of these lines. A seller waybill built from a picking sets stock_move_id per line at creation (stock_picking.py:214-228, _rs_line_vals_from_move includes 'stock_move_id': move.id). _apply_rs_goods_diff_auto (used by action_update_rs_status, the sync engine and the drift cron — already the subject of known items #58/#59) computes its diff from these same line records after _sync_goods_lines has run, and drives stock.move.quantity per the matched line. If two lines share (bar_code, name) — e.g. the same product appears on two different SO lines (different price tiers) merged into two separate moves on one delivery — and RS's returned order for that pair differs from the last poll, the FIFO match can pair item A's new values onto move-linked line B and vice versa.
- **Core evidence.** not verified whether Odoo core would in fact keep two SO lines for the same product as two separate (unmerged) stock moves on one delivery — stock.move's own merge-key logic (addons/stock/models/stock_move.py, the _prepare_merge_moves_distinct_fields / merge candidates path) was not re-read in this session, so the precondition for two same-product waybill lines with distinct stock_move_id is plausible but not confirmed against that core method. Directly verified in this module: rs_waybill_sync.py:725-728 and :749-754 (key = (bar_code, name), FIFO candidate pick), :828-838 (_sync_rs_good_ids' own comment limiting the order guarantee to the save_waybill response only), stock_picking.py:214-228 (_rs_line_vals_from_move sets stock_move_id per line at creation).
- **Mismatch.** Waybill has line1 (stock_move_id=Move-A, product X, qty 5, price 10) and line2 (stock_move_id=Move-B, product X, qty 3, price 20) — same bar_code/name, different price tier. On a later poll RS's goods array returns the pair in the opposite order with real new quantities (item for the price-20 tier now 3→6, item for price-10 tier now 5→2). Because matching is FIFO by (bar_code,name) and not by rs_good_id, line1 (really the price-10/Move-A line) can end up written with the price-20 item's new quantity (6) instead of its own (2), and line2 gets 2 instead of 6. The subsequent diff-apply then raises Move-A's demand to 6 and Move-B's to 2 — the reverse of what RS actually declared — so qty_delivered on the two different SO lines ends up swapped relative to rs.ge's own record.
- **Status.** Not checked against the gec_modules2 test DB — code-level finding only.
- **Provoke.** Create an SO with two lines for the same product at two different unit prices (5 units @10, 3 units @20), deliver both on one picking so two waybill lines share the same bar_code/name but different stock_move_id and unit_price. Edit both quantities on rs.ge in one save. Run the sync/drift job and, using a debugger or a monkeypatched SOAP client that reorders the GOODS list between two polls, verify which local line (by stock_move_id) receives which new quantity vs which RS item ID reported that quantity.
- **Fix.** Match by rs_good_id first (the identity _sync_rs_good_ids already establishes as canonical right after save_waybill), falling back to the (bar_code, name) + FIFO heuristic only for lines that have never been assigned an rs_good_id yet (brand-new lines on this poll).

## Known behaviour, no change proposed
- Reset to draft / Cancel on any rs.ge-linked move needs rs.ge reachable (`E/models/account_move.py:1756-1802`). During an outage accountants cannot correct those documents.
- Credit notes are never filed on rs.ge (`E/models/account_move_seller.py:65-75`); a correction is a replacement invoice plus a cancelled original, so Odoo credit-note reports do not show rs.ge corrections.
- Once the refresh and recovery crons are enabled (off by default, `E/data/ir_cron.xml`), general-ledger changes can originate from a cron.
- `cr.commit()` before an rs.ge call is deliberate orphan protection (15 in `W/models/rs_waybill_actions.py`, 8 in e-invoice flows); the risky commits are the ones after Odoo state changes (#21, #24).
- Module-root `AUDIT.md` / `CODE_REVIEW.md` are partially stale; this file supersedes them for the items above.

### Session 2 coverage note
Readers: seller accounting (account_move.py, account_move_seller.py, account_move_sync.py, rs_replace_orchestrator.py, rs_base_methods/account_move.py — full read); buyer accounting (account_move_buyer.py, rs_buyer_inbox_wizard.py, rs_correction_wizard.py, rs_replace_preview_wizard.py, rs_einvoice_models.py, rs_einvoice_view_wizard.py, account_move_view_data.py, rs_einvoice_waybill_link.py — full read); purchase (purchase_order.py full read, plus targeted methods in rs_waybill.py / rs_waybill_sync.py / rs_waybill_actions.py / stock_picking.py / account_move_buyer.py / account_move_sync.py); stock core (rs_waybill.py, rs_waybill_line.py, return_decision_wizard.py — full read).
Not run in this pass: a **sale-flow reader** (SO↔invoice↔delivery quantity consistency — sale_order.py, the invoice-from-waybill wizard) failed to complete and was not retried; a **stock-actions/sync reader** (rs_waybill_actions.py, rs_waybill_sync.py, stock_picking.py, product_product.py, res_company.py, res_partner.py, account_tax.py end to end) was still running when the workflow was stopped early at the user's request. XML/CSV/security/data files and tests were excluded from this pass by design (see priority in the request). Neither of those two gaps has been swept yet — flag if you want them done as a follow-up.

### Session 3 coverage note
Sale-flow reader: full read of `rs_waybill/models/sale_order.py`, `rs_base_methods/models/sale_order.py`, `rs_base_methods/wizards/rs_invoice_from_waybill_wizard.py` and `..._wizard_line.py`, plus targeted sections of `rs_waybill.py`, `stock_picking.py` and the `rs_einvoice` advance-settlement code; core reads in `addons/sale/models/sale_order_line.py` and `sale_order.py`. Did not deep-read the native advance-settlement selection logic end-to-end against `sale_order.invoice_ids`/`qty_invoiced` (confirmed it only builds the rs.ge payload, does not touch SO fields, so left out under the effort budget) — worth a closer pass if advance settlement and this wizard are ever used together on the same order. Stock-actions reader: full read of `rs_waybill_actions.py`, `rs_waybill_sync.py`, `stock_picking.py`, `product_product.py`, `rs_waybill_adjustment.py`, `rs_product_external_ref.py`, `res_company.py`, `res_partner.py`, `account_tax.py`, and `rs_base_methods/models/rs_waybill.py` — no gaps reported.

This closes the six-reader sweep requested for payment/reconciliation vs sale/purchase/bill/invoice and stock/stock-return vs sale/invoice. All six flows (seller accounting, buyer accounting, sale, purchase, stock core, stock actions/sync) have now been read end to end at least once; XML/CSV/security/data files and tests remain unswept by design.

## Suggested order
1 → 2, 3 → 4, 5 → decide 6/7 → 15, 16, 17, 18, 21, 24, 26, 28 (small mechanical fixes) → 8, 9, 11, 12, 13, 14 → 20, 22, 23, 25 → decide 31 → 32 → P3.

The 2026-09-18 core-safety review keeps this order and changes the *content* of five items: 6 takes option (a), 12 becomes a merge instead of a raise, 15 / 22 / 25 use the core mechanism (`stock.move.quantity` inverse, `stock.return.picking`) instead of hand-built moves.

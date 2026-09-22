# Partner Default Taxes + Product "Not Taxed" — Plan

> **Status:** IMPLEMENTED 2026-09-09 inside `gec_l10n_ge_tax` (user's decision, overrides D6). Code written, not yet installed or run. Q6 unanswered, default applied: withholding kept.
> **Decisions:** D4 and D8 taken by the user; D1, D2, D7 accepted by default (no objection); D3 stays at "withholding kept" until Q6 is answered.
> **Scope:** quotations/sales orders, purchase orders, customer invoices, vendor bills on the Georgian databases (`gec_new3`, `gec_modules_hr3` profile: `sale`, `purchase`, `account_accountant`, `account_asset`, `gec_l10n_ge_tax`, `l10n_account_withholding_tax` installed; POS, eCommerce, `purchase_stock`, subscriptions not installed — verified by `psql` on both DBs).
> **Generic mechanics:** [`taxes.md`](taxes.md) (fiscal positions, tax selection chain), [`gec_l10n_ge_tax.md`](gec_l10n_ge_tax.md) (GE taxes and grids).

---

## 0. Plain summary

**What you will see**

1. **Two fields on the contact**, in the Sales & Purchase tab next to Fiscal Position: *Default Sales Tax* and *Default Purchase Tax*. Per company. A new child contact copies them from its parent company; when you change them on the parent, the children follow.
2. **One checkbox on the product**, *Not Taxed*, next to the Sales Taxes field. When checked, the product's tax fields hide.
3. **One rule**, applied every time Odoo fills the tax column on a new line — quotations, sales orders, purchase orders, customer invoices, vendor bills:
   - product is Not Taxed → no tax proposed; add one by hand if needed;
   - contact has a default tax for this direction → it replaces the product's tax; a fiscal position on the contact (Export, Non-resident) still does its job on top;
   - otherwise everything works as today.
4. **Changing the customer or vendor** on a draft document recomputes the taxes on its lines.

| You set | You get on the line |
|---|---|
| Product 18%, contact empty | 18%, as today |
| Product 18%, customer *Default Sales Tax* = VAT 0% Export (Sale) | 0% Export |
| Product 18%, vendor *Default Purchase Tax* = VAT Exempt (Purchase) | 0%, nothing on the VAT return |
| Product Not Taxed | no tax; add one by hand if needed |

**How, technically.** One small module, about 90 lines. One shared function holds the rule. Three existing Odoo methods call it after doing their normal work: the invoice line method, the sales order line method, the purchase order line method. Nothing in the tax engine, reports, payments or posted documents changes. Manual edits on any line still work.

**After install, the accountant configures**

- non-VAT-registered vendors: *Default Purchase Tax* = `VAT Exempt (Purchase)` (D8);
- customers with a fixed regime, e.g. export: *Default Sales Tax* = `VAT 0% Export (Sale)`;
- products that are not a supply at all (deposits, penalties, pass-through costs): *Not Taxed* (D4). Exempt or zero-rated goods keep their exempt/0% tax instead.

---

## 1. Verdict

| Question | Answer |
|---|---|
| Does it break Odoo logic? | No, **if** it is done as a post-processing override of the three methods that *propose* line taxes, each calling `super()`. Nothing in the tax engine, GL, payments, or reports is touched. Users can still edit taxes on any line. |
| Is it "the Odoo way"? | Half. Odoo's own answer to "this partner gets other taxes" is a fiscal position pinned on the contact ([`taxes.md` FAQ](taxes.md#faq-is-there-a-default-tax-per-partner)). The partner fields duplicate that with a simpler UI and one real advantage: they can put a tax on a product that has none, which a fiscal position cannot. |
| Where is the real risk? | Not in code. Four accounting traps: (1) "no tax" removes the line from the VAT return — **accepted by the user as a manual step** (D4); (2) a single replacement tax silently drops payment-time withholding — **avoided, withholding kept** (D3, Q6 open); (3) an empty Many2one cannot say "no VAT" — **solved with `VAT Exempt (Purchase)`** (D8); (4) partner tax and fiscal position on the same contact = two places deciding one thing — **layered, see section 3**. |
| Size | One small module, ~90 lines of Python, two view inheritances, no new model, no migration, no version bump. |

---

## 2. What Odoo does today (verified)

Taxes are **proposed** by three independent methods. All start from the product, fall back to the account (invoices only), then let the fiscal position remap.

| Document | Method | Trigger | Passes result to |
|---|---|---|---|
| Invoice / bill / refund line | `_get_computed_taxes` [account_move_line.py:921](../addons/account/models/account_move_line.py#L921); account fallback at [:928](../addons/account/models/account_move_line.py#L928) / [:933](../addons/account/models/account_move_line.py#L933); remap at [:945](../addons/account/models/account_move_line.py#L945) | `_compute_tax_ids` on product/account change [:913](../addons/account/models/account_move_line.py#L913); "Update taxes" button `action_update_fpos_values` [account_move.py:5798](../addons/account/models/account_move.py#L5798) | the posted move |
| Sales order line | `_compute_tax_ids` [sale_order_line.py:542](../addons/sale/models/sale_order_line.py#L542), depends only on `product_id`, `company_id` [:541](../addons/sale/models/sale_order_line.py#L541); cache hook `_get_custom_compute_tax_cache_key` [:566](../addons/sale/models/sale_order_line.py#L566) | product change; "Update taxes" `action_update_taxes` [sale_order.py:1335](../addons/sale/models/sale_order.py#L1335) | invoice line, copied verbatim [:1503](../addons/sale/models/sale_order_line.py#L1503) |
| Purchase order line | `_compute_tax_id` [purchase_order_line.py:145](../addons/purchase/models/purchase_order_line.py#L145); `tax_ids` is a plain Many2many, no stored compute [:33](../addons/purchase/models/purchase_order_line.py#L33) | product onchange [:389](../addons/purchase/models/purchase_order_line.py#L389); PO onchange on fiscal position [purchase_order.py:469](../addons/purchase/models/purchase_order.py#L469) | bill line, copied verbatim [:589](../addons/purchase/models/purchase_order_line.py#L589) |

Facts that shape the design:

- **The partner has no tax field.** Its only lever is `property_account_position_id` ([partner.py:546](../addons/account/models/partner.py#L546)), a company-dependent, commercial field ([partner.py:706](../addons/account/models/partner.py#L706)).
- **Fiscal positions remap, never add.** Empty product taxes stay empty on orders; on invoices the account default steps in ([account_move_line.py:928](../addons/account/models/account_move_line.py#L928)).
- **Changing the partner does not recompute taxes** on existing lines. Odoo shows an "Update taxes" button only when the fiscal position changed ([sale_order.py:410](../addons/sale/models/sale_order.py#L410)).
- **Withholding lives on the bill line.** GE practice: post the bill with the WHT tax on the line, withholding is computed at payment from those lines ([odoo_taxes/README.md §8](../custom_addons/odoo_taxes/gec_l10n_ge_tax/README.md), [account_payment_register.py:129](../addons/l10n_account_withholding_tax/wizards/account_payment_register.py#L129)). Any rule that *replaces* line taxes can delete the WHT tax.
- **Exempt and zero-rated GE taxes exist for the return.** They carry base tags only, so the base still reaches the DGV grids ([gec_l10n_ge_tax.md](gec_l10n_ge_tax.md)). A line with *no* tax is invisible to the return.

---

## 3. Target behaviour

Precedence, evaluated per line, in this order:

1. **Product "Not Taxed"** → no tax proposed at all; the user adds one by hand on the line when needed (D4).
2. **Partner default tax for the direction** (sale or purchase, read on the commercial partner, in the document's company) → replaces the product/account default. The fiscal position still remaps the result (D1). Withholding taxes from the product are kept (D3).
3. **Otherwise unchanged:** product → account fallback (invoices) → fiscal position.

| Product taxes | Partner tax | Fiscal position on contact | Result |
|---|---|---|---|
| VAT 18% (Sale) | — | — | VAT 18% (today) |
| VAT 18% (Sale) | VAT 0% Export (Sale) | — | VAT 0% Export |
| VAT 18% (Sale) | — | Export (GE) | VAT 0% Export (today) |
| VAT 18% (Sale) | VAT 18% (Sale) | Export (GE) | VAT 0% Export — the position remaps the partner tax (D1) |
| none | VAT 18% (Sale) | — | VAT 18% (today: account default on invoices, nothing on orders) |
| VAT 18% + WHT 20% (Purchase) | VAT Exempt (Purchase) | — | VAT Exempt (Purchase) + WHT 20% (D3) |
| anything, product Not Taxed | anything | anything | nothing proposed (D4) |

---

## 4. Decisions

| # | Decision | Chosen | Status (2026-09-09) | Alternative not taken | Why / risk |
|---|---|---|---|---|---|
| D1 | Partner tax vs fiscal position | Partner tax **replaces the default**, fiscal position **still remaps** afterwards | Default accepted, no objection | Partner tax final, fiscal position skipped for taxes | Keeps every Odoo behaviour intact (export/RC positions, `tax_country_id`, price re-computation on tax-included changes). A tax the position does not map passes through untouched, so "VAT 0% Export" as partner tax works either way. The alternative silently disables the three GE positions for that contact. |
| D2 | Child contacts | Both fields added to `_commercial_fields` | Default accepted, no objection | Plain fields, no sync | Commercial fields are copied to a new child at creation and pushed to children whenever the parent's value changes ([res_partner.py:721](../odoo/addons/base/models/res_partner.py#L721), [:802](../odoo/addons/base/models/res_partner.py#L802)). Same behaviour as Fiscal Position and Payment Terms. Consequence: a child cannot keep a *different* tax than its parent for long; the next parent write overwrites it. |
| D3 | Withholding | Partner tax replaces only non-withholding taxes; product WHT taxes are kept; the partner fields' domain excludes WHT taxes | **Open (Q6).** User said "it's okay to have one tax"; if that means the line must end with only the partner tax, this line is dropped | Literal replacement | Without it, "vendor purchase tax = VAT Exempt" on a bill for a product carrying "WHT 20% Services" removes the withholding and the payment withholds nothing. Money, not cosmetics. |
| D4 | "Not Taxed" meaning | **Literal** — nothing is proposed; a tax can still be added by hand on the line | **Decided by user** | "No VAT only", WHT kept (my recommendation) | Residual risk accepted by the user: an exempt or zero-rated sale where nobody adds the exempt tax by hand is missing from the DGV return (section 9). |
| D5 | Multi-company | Fields `company_dependent=True, check_company=True`, copied from the `property_account_payable_id` declaration ([partner.py:536](../addons/account/models/partner.py#L536)) | Technical, mine | Plain Many2one | Taxes belong to one company; a shared partner in a branch setup would otherwise carry company A's tax into company B. |
| D6 | Where the code lives | **Inside `gec_l10n_ge_tax`**; the module now also depends on `sale` and `purchase` | **Decided by user 2026-09-09**, overrides my recommendation | New module `gec_partner_taxes` | Consequence: the tax localization can no longer be installed without the Sales and Purchase apps. Both are installed on every GE database today. |
| D7 | Partner change after lines exist | `order_id.partner_id` / `move_id.partner_id` added to the overridden computes' `@api.depends`; one extra `@api.onchange('partner_id')` on the PO | Default accepted, no objection | Keep Odoo's manual "Update taxes" button | Odoo's button only appears when the *fiscal position* changed, so a partner-tax-only change would be missed. Trade-off: recompute overwrites manual tax edits on lines when the partner changes, exactly as a fiscal position change does today. |
| D8 | "Non-VAT vendor" | Existing grid-less `VAT Exempt (Purchase)` tax as the partner purchase tax ([account_chart_template.py:167](../custom_addons/odoo_taxes/gec_l10n_ge_tax/models/account_chart_template.py#L167), repartition with no tags) | **Decided by user** | New "No VAT" tax; or a second boolean per partner | An empty Many2one means "no rule", not "no tax". A concrete 0% tax with no grids is the only way to express "this vendor charges no VAT" without a fourth field. |

---

## 5. Data model

| Model | Field | Type | Notes |
|---|---|---|---|
| `res.partner` | `property_sale_tax_id` | Many2one `account.tax`, `company_dependent`, `check_company` | domain: `type_tax_use = sale`, `is_withholding_tax_on_payment = False`; label "Default Sales Tax" |
| `res.partner` | `property_purchase_tax_id` | same | domain: `type_tax_use = purchase`, not withholding; label "Default Purchase Tax" |
| `res.partner` | `_commercial_fields()` | override | `super() + ['property_sale_tax_id', 'property_purchase_tax_id']` |
| `product.template` | `not_taxed` | Boolean | label "Not Taxed"; when set, the form hides Sales/Purchase Taxes (wrong value made impossible instead of validated) |

No new model, no ACL file, no sequence, no cron.

---

## 6. Code touch points

### 6.1 One rule, one place

`account.tax` gets one `@api.model` helper used by all three callers, so the rule cannot drift:

```python
def _gec_partner_product_taxes(self, taxes, partner, product, company, type_tax_use, fiscal_position):
    if product.not_taxed:
        return self.env['account.tax']
    withholding = taxes.filtered('is_withholding_tax_on_payment')
    partner = partner.commercial_partner_id.with_company(company)
    partner_tax = partner.property_sale_tax_id if type_tax_use == 'sale' else partner.property_purchase_tax_id
    if not partner_tax:
        return taxes
    return fiscal_position.map_tax(partner_tax) | withholding
```

`map_tax` on an empty fiscal position returns its input unchanged ([partner.py:155](../addons/account/models/partner.py#L155)), so no branching is needed. If Q6 resolves to "only the partner tax", the last line becomes `return fiscal_position.map_tax(partner_tax)`.

### 6.2 The three overrides

| File in `gec_l10n_ge_tax` | Method | Change |
|---|---|---|
| `models/account_move_line.py` | `_get_computed_taxes` | `taxes = super()`; return unchanged unless `display_type == 'product'` and the move is a sale or purchase document; else pass through the helper with `move.partner_id`, `move.fiscal_position_id`. The guard keeps the `account_accountant` deferral and `account_asset` early-return paths untouched. Add `move_id.partner_id` to `_compute_tax_ids` depends (D7). |
| `models/sale_order_line.py` | `_compute_tax_ids` | `super()`, then for lines with a product and `product_type != 'combo'` pass `line.tax_ids` through the helper with `order.partner_id`, `order.fiscal_position_id`. `@api.depends('order_id.partner_id')` on the override (D7). The existing cache in `super()` is unaffected: we post-process its output. |
| `models/purchase_order_line.py` | `_compute_tax_id` | `super()`, then the helper with `order.partner_id` and the same fiscal position expression `super()` uses. |
| `models/purchase_order.py` | new `@api.onchange('partner_id')` | `self.order_line._compute_tax_id()` (D7; the standard onchange only recomputes when the fiscal position value changed). |
| `views/res_partner_views.xml` | inherit `account.view_partner_property_form` | both fields after `property_account_position_id` in group `fiscal_information` ([partner_view.xml:262](../addons/account/views/partner_view.xml#L262)), same `options` and group restriction. |
| `views/product_views.xml` | inherit `account.product_template_form_view` | `not_taxed` before the Sales Taxes label; `invisible="not_taxed"` on `taxes_id` and `supplier_taxes_id` ([product_view.xml:89](../addons/account/views/product_view.xml#L89)). |

### 6.3 Dependency sweep (Hard Rule 4)

| Hook | Callers | Overrides in `addons` / `enterprise` / `custom_addons` | Effect of our change |
|---|---|---|---|
| `account.move.line._get_computed_taxes` | `_compute_tax_ids` [:919](../addons/account/models/account_move_line.py#L919); `action_update_fpos_values` [account_move.py:5806](../addons/account/models/account_move.py#L5806); inter-company invoices [account_inter_company_rules:49](../enterprise/account_inter_company_rules/models/account_move.py#L49) (not installed) | `account_accountant` deferral moves return `self.tax_ids` early [:793](../enterprise/account_accountant/models/account_move.py#L793); `account_asset` asset moves likewise [:338](../enterprise/account_asset/models/account_move.py#L338) | Both are journal entries, excluded by our sale/purchase-document guard. `action_update_fpos_values` compares `price_include` sets before/after; semantics unchanged. |
| `sale.order.line._compute_tax_ids` | compute trigger; `_recompute_taxes` [sale_order.py:1347](../addons/sale/models/sale_order.py#L1347) | `sale_loyalty` [:35](../addons/sale_loyalty/models/sale_order_line.py#L35) (not installed) | Result copied to the invoice line [:1503](../addons/sale/models/sale_order_line.py#L1503), so invoices from orders follow the order. |
| `purchase.order.line._compute_tax_id` | `_product_id_change` [:389](../addons/purchase/models/purchase_order_line.py#L389); PO onchange [purchase_order.py:473](../addons/purchase/models/purchase_order.py#L473) | none installed (`l10n_in` wizard irrelevant) | Result copied to the bill line [:589](../addons/purchase/models/purchase_order_line.py#L589). |
| `purchase.order.line._prepare_purchase_order_line` [:626](../addons/purchase/models/purchase_order_line.py#L626) | replenishment / requisition only | `purchase_requisition(_stock)` (not installed) | Not overridden now (Simplicity §2). Needed the day `purchase_stock` is installed on a GE database. |

### 6.4 Build steps

| Step | Who | What |
|---|---|---|
| 1 | Claude | **Done 2026-09-09** in `custom_addons/odoo_taxes/gec_l10n_ge_tax`: `models/res_partner.py`, `product_template.py`, `account_tax.py`, `account_move_line.py`, `sale_order_line.py`, `purchase_order.py`, `purchase_order_line.py`, `views/res_partner_views.xml`, `views/product_views.xml`; manifest depends and data updated; both READMEs updated. Q6 default kept: withholding preserved. |
| 2 | User | Upgrade the module (`-u gec_l10n_ge_tax`) on a **copy** of `gec_new3`; open a contact, a product, a quotation, a purchase order, a customer invoice, a vendor bill. |
| 3 | User | Run the acceptance matrix (section 10) by hand; report any row that fails with the document number. |
| 4 | Accountant | Configure vendors, customers and products as listed in section 0. |
| 5 | Later | Align the rs.ge waybill wizard if that database uses it; add the `_prepare_purchase_order_line` override the day `purchase_stock` is installed (section 8). |

---

## 7. What does not change

- Fiscal position detection and account mapping.
- The tax engine, repartition, grids, closing entry, DGV report.
- Payment-time withholding mechanics; only the *presence* of WHT taxes on lines matters, and D3 keeps them.
- Posted documents. Computes only run on draft lines when a trigger fires; nothing is recomputed retroactively.
- Manual line taxes remain editable; the module changes the proposal, not the field.
- Company default taxes on new products ([product.py:37](../addons/account/models/product.py#L37)).

---

## 8. Known gaps (decide before build)

| Gap | Why | Handling |
|---|---|---|
| Expenses (`hr_expense`, installed on `gec_modules_hr3`) | `_compute_tax_ids` reads product supplier taxes only, no partner involved [hr_expense.py:568](../addons/hr_expense/models/hr_expense.py#L568) | Out of scope. Vendor taxes on expenses would need a separate decision. |
| rs.ge waybill → invoice wizard (`rs_base`) | builds line taxes from the raw product and ignores even fiscal positions [rs_invoice_from_waybill_wizard.py:89](../custom_addons/rs_base/rs_base_methods/wizards/rs_invoice_from_waybill_wizard.py#L89) | If this wizard is used on the same database, route `_product_default_taxes` through the helper. One-line change in that module. |
| Auto-created PO lines (`purchase_stock`, `purchase_requisition`) | `_prepare_purchase_order_line` sets `tax_ids` in vals, bypassing the onchange | Not installed on the GE databases. Add the override when it is. |
| POS, eCommerce | taxes computed in JS from the product and fiscal position | Not installed. If ever installed, partner taxes will not apply there. |
| Existing draft orders/invoices | no trigger fires on install | Use "Update taxes" per document, or accept. No data script. |

---

## 9. Georgia compliance notes

- **[Certain] "No tax" is not "exempt".** Our localization gives exempt and zero-rated supplies real taxes with base tags precisely so the base reaches the return ([gec_l10n_ge_tax.md](gec_l10n_ge_tax.md)). A product flagged Not Taxed produces no grid entry. **[Likely]** the GE VAT return expects exempt and zero-rated turnover to be declared. **User decision 2026-09-09:** the checkbox stays literal; on exempt or zero-rated products the accountant adds `VAT Exempt (Sale)` / `VAT 0% Export (Sale)` by hand on the line, or keeps the tax on the product and leaves Not Taxed unchecked.
- **[Certain] Non-VAT-registered vendor.** `VAT Exempt (Purchase)` has no tags at all ([account_chart_template.py:167](../custom_addons/odoo_taxes/gec_l10n_ge_tax/models/account_chart_template.py#L167)); as partner purchase tax it removes VAT without touching the return. The label "VAT Exempt" prints on such bills; accepted (D8).
- **[Certain] Withholding.** If D3 is dropped (Q6), a replacement tax on a vendor whose products carry WHT removes the WHT tax and the payment withholds nothing. The accountant would have to re-add the WHT tax on every such bill line.
- **Two places.** Once both exist, agree the rule of thumb: fiscal position = *regime* (export, reverse charge, non-resident), partner tax = *VAT status* of the counterparty. Do not set both on one contact unless the layered result in section 3 is intended.

---

## 10. Acceptance matrix (tests only if requested)

| # | Setup | Expect |
|---|---|---|
| 1 | Partner with sale tax 0% Export, product with 18% | SO line and direct invoice line: 0% Export |
| 2 | Same, plus Export (GE) position pinned | same result; position remap is a no-op on 0% Export |
| 3 | Partner with sale tax 18%, position Export (GE) | 0% Export (D1) |
| 4 | Vendor with purchase tax VAT Exempt (Purchase), product 18% + WHT 20% | bill line: VAT Exempt + WHT 20%; register payment proposes the 20% withholding (changes if Q6 drops D3) |
| 5 | Product Not Taxed with 18% + WHT 20% | bill line: no tax proposed (D4); the user may add one by hand |
| 6 | Product Not Taxed, sale side | SO/invoice line: no tax |
| 7 | No partner tax, product without taxes, direct invoice | account default tax (unchanged behaviour) |
| 8 | Child contact created under a parent with taxes set | child carries both taxes in the current company and in other companies |
| 9 | Change partner on a draft SO/invoice with lines | taxes recomputed for the new partner (D7) |
| 10 | Deferral entry from `account_accountant` | untouched (guard) |

---

## 11. Open questions

| # | Question | Blocks | Status |
|---|---|---|---|
| Q1 | Is `VAT Exempt (Purchase)` acceptable as the "non-VAT vendor" tax? | D8 | Resolved 2026-09-09: yes |
| Q2 | Must a child contact ever hold a different tax than its parent company? | D2 | Closed by default 2026-09-09: no, commercial-field sync |
| Q3 | Partner tax replaces the default and the fiscal position still remaps, or partner tax is final? | D1 | Closed by default 2026-09-09: still remaps |
| Q4 | Which database profile is the target? | section 8 | Closed by default 2026-09-09: GE profile (no stock, no POS) |
| Q5 | Should Not Taxed also strip withholding taxes? | D4 | Resolved 2026-09-09: literal, nothing proposed |
| Q6 | "It's okay to have one tax": must the line end with only the partner tax (WHT dropped), or is one field per direction enough (WHT kept, current default)? | D3 | **Open** |

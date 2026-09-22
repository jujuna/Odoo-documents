# gec_l10n_ge_tax — Georgian Tax Layer: How Tax Grids Feed the DGV Report

> **Module:** `gec_l10n_ge_tax` | **Path:** [`custom_addons/odoo_taxes/gec_l10n_ge_tax/`](../custom_addons/odoo_taxes/gec_l10n_ge_tax/)
> Depends on `gec_localization` (the "ge" CoA), Enterprise `accountant`/`account_reports`, and the withholding framework.
> **This doc covers the tax-grid → DGV chain end-to-end (verified from source 2026-07-15).** WHT payment-time flow, CIT wizard and the maintenance hook are covered at pointer level only.
> Generic tax engine mechanics (repartition, fiscal positions, closing): [`taxes.md`](taxes.md).

## What a "tax grid" is

A grid is an `account.account.tag` with `applicability='taxes'` and a country. It is a **label
stamped on journal items at posting time** — independent of which GL account the line hits. Tax
reports then aggregate move lines **by tag, not by account**. That separation is the whole point:
`3330` VAT Payable can carry output VAT, RC output and customs VAT while the declaration still
splits them into different boxes, because each line carries a different tag.

## The chain in this module

```
data/account_tax_tags.xml          33 tags: [GE-VAT] / [GE-WHT] / [GE-SmallBiz], country=GE
        |  referenced BY NAME
models/account_chart_template.py   @template('ge','account.tax') — every tax's repartition
                                   lines carry base-tag / tax-tag names; stock
                                   _deref_account_tags resolves name -> tag id at chart load
        |  invoice/bill/payment posts
account.move.line.tax_tag_ids      each generated line copies its repartition line's tags
        |  summed by tag
data/dgv_tax_report.xml            account.report "VAT Declaration (DGV)", engine=tax_tags,
                                   formula = tag name, leading '-' flips the sign
        |  period end
tax groups -> 3399                 every GE tax group settles to the unified budget account
```

### 1. Tags — [`account_tax_tags.xml`](../custom_addons/odoo_taxes/gec_l10n_ge_tax/data/account_tax_tags.xml)

Three families, always in base/tax pairs: `[GE-VAT]` (sales, purchases, reverse charge, customs),
`[GE-WHT]` (non-resident dividends/interest/royalty/mgmt/rent + resident dividends/interest/royalty,
each base + tax), `[GE-SmallBiz]` (1% turnover). Plain names — no stock `+`/`-` prefixes; the sign
lives in the report formula instead.

### 2. Taxes attach tags via repartition lines — [`account_chart_template.py:44`](../custom_addons/odoo_taxes/gec_l10n_ge_tax/models/account_chart_template.py#L44)

The `rep()` helper builds each tax's repartition: a `base` line carrying the base tag, a `tax` line
carrying the tax account + tax tag, optionally a second ±100% leg. Tag names are strings; stock
[`_deref_account_tags`](../addons/account/models/chart_template.py#L1268) maps name → tag record
per country at chart setup. Examples:

- **VAT 18% Sale**: base tag `Taxable sales 18% - base`; tax leg → `account_3330` + tag
  `Taxable sales 18% - VAT`. Refund repartition uses the **same tags** — a credit note books
  opposite-sign balances on the same grid, so refunds reduce the declaration automatically.
- **Reverse charge**: main leg +100% and a second leg −100% → `account_3330` with tag
  `Reverse charge - output VAT due` ([account_chart_template.py:134](../custom_addons/odoo_taxes/gec_l10n_ge_tax/models/account_chart_template.py#L134)).
  Net GL effect zero, but both legs are tagged, so output-due and input-credit both appear on the
  report — grids fire even when money doesn't move.
- **Zero-rated / exempt / out-of-scope**: base-tag-only repartition — no tax amount, but the
  turnover still lands in its declaration box.

### 3. Posting stamps the grids

When an invoice/bill posts, the engine matches each computed amount to its repartition line and
copies that line's `tag_ids` into the journal item's `tax_tag_ids`. From that moment the grid is
**stored on the move line** — visible as the "Tax Grids" column in journal items, filterable, and
immune to later edits of the tax definition (changed repartition affects only future postings).

### 4. The DGV report reads tags — [`dgv_tax_report.xml`](../custom_addons/odoo_taxes/gec_l10n_ge_tax/data/dgv_tax_report.xml)

`account.report` "VAT Declaration (DGV)" (root = generic tax report, `availability_condition`
country=GE). Every leaf line has one expression with `engine="tax_tags"` and `formula` = the tag
name. Verified engine mechanics
([account_report.py:3858](../enterprise/account_reports/models/account_report.py#L3858)):

- SQL sums `account_move_line.balance` grouped by tag over the period
  ([account_report.py:3877](../enterprise/account_reports/models/account_report.py#L3877)).
- A **leading `-` in the formula multiplies the summed balance by −1**
  ([account_report.py:3921](../enterprise/account_reports/models/account_report.py#L3921)).
  Output/sales lines are credits (negative balances) → their formulas use `-<tag>` to display
  positive; input/purchase lines are debits → plain tag name.
- Parent boxes are `aggregation_formula` over child codes (e.g. `GE_OUT = GE_OUT_VAT.balance +
  GE_OUT_RC.balance`).
- Creating a `tax_tags` expression **auto-creates a tag named like the formula (sign stripped) if
  none exists** — which is why the tags file loads *before* the report file: the expressions find
  the pre-created tags by name instead of spawning duplicates.

Worked example — post a 100 GEL sale with VAT 18%:

| Journal item | Balance | Tag |
|---|---|---|
| Receivable | +118 | — |
| Income | −100 | `[GE-VAT] Taxable sales 18% - base` |
| `3330` VAT Payable | −18 | `[GE-VAT] Taxable sales 18% - VAT` |

DGV "Taxable sales base (18%)" = `-(−100)` = 100; "Output VAT (18%)" = `-(−18)` = 18. A full credit
note adds +100/+18 on the same tags → boxes drop back to 0.

### 5. Settlement

All GE tax groups point `tax_payable_account_id`/`tax_receivable_account_id` to `account_3399`
(unified budget settlement, [account_chart_template.py:14](../custom_addons/odoo_taxes/gec_l10n_ge_tax/models/account_chart_template.py#L14));
the Enterprise closing nets the period into it.

## Install/upgrade engineering (why the hooks exist)

- **`pre_init_hook`** ([__init__.py:9](../custom_addons/odoo_taxes/gec_l10n_ge_tax/__init__.py#L9)):
  pre-split DBs already hold these tags under `gec_localization` xmlids; loading the tags file
  would hit the (name, applicability, country) unique constraint. The hook **adopts** existing
  tags under this module's xmlids and strips old ownership so `-u gec_localization` can't
  garbage-collect them.
- **`post_init_hook`** ([__init__.py:45](../custom_addons/odoo_taxes/gec_l10n_ge_tax/__init__.py#L45)):
  backfills tax groups / fiscal positions / taxes into companies already on the `ge` chart —
  creating **only records missing** for that company (`template.ref(...)` check), so re-installs
  never duplicate or overwrite tuned taxes. Ends with `_ge_tax_apply_maintenance()`.

## Gotchas

- **The DGV layout is a placeholder** (file header, lines 12–15): tag wiring is real, but box
  order, human box numbers and some per-box signs are illustrative — reconcile against the
  official rs.ge DGV form before filing.
- **Sign convention is per-formula, not per-tag** — these tags have no `+`/`-` stock pairing; if
  you add a report line, remember output boxes need the leading `-`.
- **Grids ≠ accounts**: reclassifying a posted line to another account keeps its declaration box;
  removing/adding tags on a posted line changes the declaration without touching the GL.
- **Payroll uses the same tag objects** — `hr.salary.rule.debit_tag_ids`/`credit_tag_ids` stamp
  tags directly on payslip move lines with no tax involved. Nothing to stamp today: every tag
  here is VAT/WHT/small-biz; no salary declaration report or tags exist (see
  [`geo_payroll.md`](geo_payroll.md) §10 — the rs.ge salary declaration is per-employee detail,
  the wrong shape for grids).

## Default taxes per contact and Not Taxed products (2026-09-09)

Two fields on the contact (`property_sale_tax_id`, `property_purchase_tax_id`: company-dependent, commercial) and a `not_taxed` flag on the product template change *which* tax a line proposes; the grid chain above is untouched. One helper, [`account.tax._ge_partner_product_taxes`](../custom_addons/odoo_taxes/gec_l10n_ge_tax/models/account_tax.py), runs after `super()` in the three Odoo methods that propose line taxes ([`account_move_line.py`](../custom_addons/odoo_taxes/gec_l10n_ge_tax/models/account_move_line.py), [`sale_order_line.py`](../custom_addons/odoo_taxes/gec_l10n_ge_tax/models/sale_order_line.py), [`purchase_order_line.py`](../custom_addons/odoo_taxes/gec_l10n_ge_tax/models/purchase_order_line.py)). Order: Not Taxed → nothing proposed; partner default tax → replaces the product/account default, the fiscal position still remaps it, product withholding taxes are kept; otherwise standard. Design, decisions and the accounting traps: [`partner_taxes_plan.md`](partner_taxes_plan.md). Status: code written 2026-09-09, not yet installed or run. The module now depends on `sale` and `purchase`.

## Pointer-level (not yet documented in depth)

Payment-time WHT flow (interim accounts `3315`/`3316`, sequence in
[`wht_sequence.xml`](../custom_addons/odoo_taxes/gec_l10n_ge_tax/data/wht_sequence.xml)),
CIT distribution wizard ([`wizards/cit_wizard.py`](../custom_addons/odoo_taxes/gec_l10n_ge_tax/wizards/cit_wizard.py)),
return plumbing ([`models/account_return.py`](../custom_addons/odoo_taxes/gec_l10n_ge_tax/models/account_return.py)),
maintenance pass ([`ge_tax_maintenance.xml`](../custom_addons/odoo_taxes/gec_l10n_ge_tax/data/ge_tax_maintenance.xml)).

## Related docs

- [`taxes.md`](taxes.md) — the generic engine (repartition, fiscal positions, closing entry)
- [`geo_payroll.md`](geo_payroll.md) — payroll accounting + why salary grids stay empty
- [`odoo_tax_account_constraints.md`](odoo_tax_account_constraints.md) — account/journal constraints
- [`accounting_reports.md`](accounting_reports.md) — report framework

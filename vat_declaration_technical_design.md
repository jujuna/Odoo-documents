# VAT declaration module — technical design for a small, correct build

> **Module to create:** `gec_vat_report` (nothing exists yet; design of 2026-10-21) | **Pattern:** `gec_income_tax_report`
> (Form 30) | **Companions:** [`vat_declaration_build_plan.md`](vat_declaration_build_plan.md) (what and in which order),
> [`vat_declaration_rs_portal_pages.md`](vat_declaration_rs_portal_pages.md) (every portal cell and grid),
> [`vat_declaration_research_2026.md`](vat_declaration_research_2026.md) (rules and sources).
> Verified against Odoo 20 source, our modules and `gec20_prod1` on 2026-10-21. Every claim carries its path:line.

Goal of this file: the whole module in the fewest moving parts, with core Odoo doing the heavy lifting, no JavaScript,
no formula engine, no posting hooks, no second tax mapping, and no validation that blocks an accountant. Medium effort,
high standard.

---

## 1. Ten decisions that keep it small

| # | Decision | Why (evidence) |
|---|---|---|
| T1 | **One number source:** annex ა totals come from core's VAT Report through its Python API, never from our own tag sums | `report.get_options()` + `_compute_expression_totals_for_each_column_group()` is how core's UAE return reads its own report ([account_return.py:27-34](../enterprise/l10n_ae_reports/models/account_return.py#L27)); keeps Odoo's report and our form identical by construction |
| T2 | **Cells are data, not code:** one CSV row per portal input, code = portal id | Form 30 does this with `rs.form30.summary.cell` ([rs_form30_summary.py:4-22](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_summary.py#L4)); the portal doc already lists every id, label, help text and locked flag |
| T3 | **Formulas are 30 lines of Python**, copied from the portal JavaScript | section 2 of the portal doc; Form 30 computes its cells the same way in `_summary_values` ([rs_form30_declaration.py:1141](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L1141)) |
| T4 | **No JavaScript.** Cell pages and grids are plain `<list editable="bottom">` with `readonly="computed"` | core syntax in 20.0 ([account_move_views.xml:1549-1594](../addons/account/views/account_move_views.xml#L1549)); the Form 30 widgets are hard-wired to Form 30 names and models (summary grid opens `rs.form30.explain`, [rs_form30_summary_grid.js:34](../custom_addons/gec_odoo_modules/gec_income_tax_report/static/src/components/rs_form30_summary_grid/rs_form30_summary_grid.js#L34)), so reuse would mean a payroll dependency or a copy |
| T5 | **One page per portal tab** = one `One2many` with a Python `domain` on the same line model | core pattern: `invoice_line_ids` is `line_ids` filtered by a domain ([account_move.py](../addons/account/models/account_move.py)) |
| T6 | **Ten models, no abstract mixin** | one per distinct grid shape; the six "reference + period + VAT" grids (ბ IV, V, VII, VIII, IX, X) share one model with a `grid` selection, their list views differ only in visible columns |
| T7 | **Credit notes and corrections are read from the rs.ge chain, not guessed** | `rs_einv_replaces_id`, `rs_einv_replacement_mode`, `rs_einv_status`, the reversal's skip reason "replacement" ([account_move.py:205-246](../custom_addons/gec_odoo_modules/rs_einvoice/models/account_move.py#L205), [account_move_cancel.py:180-199](../custom_addons/gec_odoo_modules/rs_einvoice/models/account_move_cancel.py#L180)) |
| T8 | **Dropped 2026-10-22** (portal attaches confirmed invoices itself, X2; no test company, X4; export deferred to plan Phase 6). Original: **Annex ბ I / II go to rs.ge by API, not by spreadsheet** | the portal attaches confirmed invoices to a declaration number; the API has `get_seq_nums` and `add_inv_to_decl` ([rs_invoice_api_docs.md:772-799](../rs_invoice_api_docs.md)); spreadsheet export stays for the manual grids only |
| T9 | **Warnings, never blocks** | the portal validates on upload and on submit; Form 30's `generation_warnings` text field is enough ([rs_form30_declaration.py:301](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L301)) |
| T10 | **Nothing touches posting, invoices, taxes or stock** | the module only reads `account.move`, writes its own tables, and calls rs.ge when the accountant clicks |

Not built on purpose: `account.report.line` records, a report handler, OWL widgets, crons, a return type (optional later),
Excel import, stock or waybill links, a December pro-rata engine, excise.

---

## 2. Module layout

```
gec_vat_report/
  __manifest__.py            depends: gec_localization, account_reports, rs_einvoice
  models/
    rs_vat_declaration.py    header + generate + cells + chains (the only file with logic, ~350 lines)
    rs_vat_cell.py           rs.vat.cell (catalog), rs.vat.cell.line (values)
    rs_vat_lines.py          the 8 row models, fields only
    rs_vat_export.py         xlsxwriter per grid + download action (~120 lines)
    rs_vat_rsge.py           attach to declaration through rs.ge (~80 lines)
    rs_soap_service.py       2 wrappers: get_seq_nums, add_inv_to_decl (inherits rs.soap.service)
  data/rs.vat.cell.csv       ~125 rows, generated from the portal doc
  views/rs_vat_declaration_views.xml, views/menus.xml
  security/ir.access.csv     last in the manifest
  tests/                     only after the user says which behaviours to cover
```

Dependencies, stated: `gec_localization` (chart and taxes, already everywhere), `account_reports` (the report API; the VAT
Report is only visible with it anyway), `rs_einvoice` (series, numbers, status, chains, advance settlements, SOAP
service and credentials). No dependency on `gec_income_tax_report`, `geo_payroll` or `rs_waybill`.

---

## 3. Models

### 3.1 `rs.vat.declaration`

| Field | Type | Note |
|---|---|---|
| `company_id` | M2O res.company, required, default env.company | `_check_company_auto = True` |
| `date_from`, `date_to`, `period` | Date (month), Date computed, Integer YYYYMM computed | Form 30 pattern ([rs_form30_declaration.py:253-257](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L253)) |
| `decl_type` | Selection primary / adjusted | the portal's "პირველადი / დაზუსტებული"; no unique constraint on the month, a warning when another declaration of the month exists |
| `rs_seq_num` | Char | the portal declaration number, typed or taken from `get_seq_nums` |
| `state` | draft / exported | as Form 30 |
| `cell_line_ids` | O2M rs.vat.cell.line | all cells; plus five filtered O2M for the pages: `cell_a1_ids` (domain tab = 1), `cell_a2_ids`, `cell_a3_ids`, `cell_p3_ids` (tab 16), `cell_margin_ids` (tab 17) |
| `invoice_line_ids` | O2M rs.vat.invoice.line | plus `sale_invoice_line_ids` (part = sale), `purchase_invoice_line_ids` (part = purchase) |
| `advance_link_ids` | O2M rs.vat.advance.link | sub-grids of tabs 4, 5, 13, 14; filtered O2M per page |
| `customs_line_ids`, `ref_line_ids` (+ six filtered O2M by `grid`), `petrol_invoice_line_ids` (+ two by part), `petrol_balance_line_ids`, `tourist_line_ids` | O2M | rows of the other grids |
| `not_declared_move_ids` | M2M account.move, readonly | posted invoices of the month with VAT and no rs.ge number, or whose rs.ge status is not confirmed |
| `generation_warnings` | Text | one line per finding |
| `report_vat_total`, `form_vat_total` | Monetary computed | core report ა I.15 VAT versus the form's cell 1: the difference is the cross-month corrections |
| `export_file_<grid>` + filename | Binary, 9 pairs | one per grid that has a spreadsheet import |
| `name` | Char computed | "დღგ 2026/09 Company" |

Buttons: **Generate**, **Export files**, **Attach to rs.ge** (Phase 2b), **Reset to draft**. No "confirm" state: the
portal is the record of filing.

### 3.2 `rs.vat.cell` (catalog, CSV) and `rs.vat.cell.line`

`rs.vat.cell`: `code` (portal id, e.g. `355_1`, `353_44_1`, `358_17`, `359_1_5`; unique), `tab` (1, 2, 3, 16, 17), `row`
("1", "1¹", "14³"), `name` (Georgian label from the form), `column` (base / vat / total / goods / fixed_assets /
purchase_price / sale_price), `note` (the portal tooltip), `computed`, `proposed`, `december_only`, `sequence`.

`rs.vat.cell.line`: `declaration_id`, `cell_id`, `value`, `proposed_value`, `odoo_value` (Odoo's own figure for the
same cell, shown beside the portal's 18 %), related `code`, `name`, `note`, `tab`, `computed`, `proposed`, `sequence`.

Sync rule, copied from Form 30 ([rs_form30_declaration.py:1243-1266](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L1243)):
computed cells are always overwritten; proposed cells follow Odoo until the accountant types something else
(`value != proposed_value`); typed cells are never touched.

### 3.3 Row models (fields only, portal column order, `declaration_id` cascade, `company_id` related stored)

| Model | Tabs | Fields beyond the key | Source |
|---|---|---|---|
| `rs.vat.invoice.line` | 4, 5 | `part` sale/purchase, `move_id`, `series`, `number`, `period` (YYYY-MM), `partner_tin`, `amount`, `reduce_amount`, `korect_series`, `korect_number`, `rs_status`, `source` auto/manual, `attached` (Phase 2b), `attach_message` | posted invoices, bills, chains |
| `rs.vat.advance.link` | 4, 5, 13, 14 | `part`, `petrol` Boolean, `delivery_series/number`, `advance_series/number`, `amount`, `final_move_id`, `advance_move_id` | `rs.einvoice.advance.settlement` ([rs_einvoice_models.py:76-125](../custom_addons/gec_odoo_modules/rs_einvoice/models/rs_einvoice_models.py#L76)) |
| `rs.vat.customs.line` | 6 | `move_id`, `assessment_number`, `customs_code`, `assessment_date`, `amount` | bills with tag `25(T)` |
| `rs.vat.ref.line` | 7, 8, 9, 10, 11, 12 | `grid` (iv/v/vii/viii/ix/x), `ref_number`, `ref_date`, `period`, `partner_tin`, `partner_name`, `owner_tin`, `owner_name`, `amount` | typed |
| `rs.vat.petrol.invoice.line` | 13, 14 | `part`, 14 portal columns (series, number, date, corrected series/number/date, stationary dispatch/destination, counterparty TIN, product code, qty l, qty kg, amount, reduce_amount) | typed |
| `rs.vat.petrol.balance.line` | 15 | `product_code` + 11 (kg, l) pairs; `closing_kg`, `closing_l` computed `3+4−5−6−8−10−11` | typed |
| `rs.vat.tourist.line` | 18 | `cadastral_code`, `status_from`, `status_to`, `amount_5`, `amount_6`, `amount_7` computed `max(5−6, 0)` | typed |

Column labels in the list views are the portal's Georgian headers (portal doc, section 5).

---

## 4. Generate, step by step (`action_generate`)

Runs on a draft declaration; rebuilds `source = auto` rows, keeps manual rows and typed cells.

**Step 1 — core report totals (T1).** 
```python
report = self.env.ref('l10n_ge.tax_report_ge')
options = report.with_context(allowed_company_ids=self.company_id.ids).with_company(self.company_id).get_options({
    'date': {'date_from': str(self.date_from), 'date_to': str(self.date_to), 'period_type': 'custom', 'mode': 'range'},
    'all_entries': False,
})
totals = report._compute_expression_totals_for_each_column_group(report.line_ids.expression_ids, options)[0]
value = {(e.report_line_id.code, e.label): v['value'] for e, v in totals.items()}
```
`previous_options['date']` keys are `date_from`, `date_to`, `period_type` ([account_report.py:1028-1029, 664-666](../enterprise/account_reports/models/account_report.py#L1028)); companies come from `allowed_company_ids`
([account_return.py:1943](../enterprise/account_reports/models/account_return.py#L1943)); the result is keyed by column-group
index, then expression ([account_report.py:3626-3656, 3798](../enterprise/account_reports/models/account_report.py#L3626)).
[Likely] `'mode': 'range'` is ignored; keep `period_type = 'custom'`. The builder confirms on a scratch DB.

**Step 2 — proposals (T2).** A constant map, portal cell → (`ge_N`, label):

| Portal cells | Core |
|---|---|
| `355_1, 355_2, 355_3, 355_4, 355_5, 355_6, 355_6_1, 355_7, 355_7_1, 355_8` | `ge_1, ge_3, ge_4, ge_5, ge_6, ge_7, ge_8, ge_9, ge_10, ge_11 .base` |
| `355_9 … 355_14` | `ge_12 … ge_17 .base` |
| `355_14_1, 355_14_2, 355_14_3` | `ge_18, ge_19, ge_20 .base` |
| `356_1, 356_2, 356_3` | `ge_21, ge_22, ge_23 .base` |
| `353_14, 353_24, 353_34, 353_44, 353_44_1, 353_54, 353_74, 353_84` | `ge_24, ge_25, ge_26, ge_27, ge_28, ge_29, ge_32, ge_33 .tax` (column 4; column 5 stays typed) |
| `odoo_value` of every `355_x_5` and `356_x5` | the matching `.tax` (Odoo's own VAT, for comparison only) |

**Step 3 — correction chains (T7).** For each posted customer invoice of the month with
`rs_einv_replacement_mode = 'correction'` and `rs_einv_status = '8'` whose `rs_einv_replaces_id.date` is in an
**earlier** month: `delta = vat(corrector) − vat(replaced)`; add `−delta` to the proposal of `358_7` when negative or
`358_6` when positive; subtract the corrector's and its reversal's own contributions from the ა I proposals so the month
keeps only its own sales. `vat(move)` = `−amount_tax_signed` for customer documents ([account_move.py:592-595,
1260](../addons/account/models/account_move.py#L592)); the per-tag contribution of the two chain documents is read with
one `read_group` on their `line_ids` grouped by `tax_tag_ids` (a handful of lines, no engine). Same-month chains need
nothing: the original is cancelled and the corrector is already the month's sale. Correctors at status 4 or 5 go to
`not_declared_move_ids` with a warning. Vendor-side corrections mirror into `358_12` / `358_13`.
**Gap (2026-10-22):** the corrector is dated when the wizard creates it, the original's reversal when the buyer accepts
([account_move_reissue.py:213-214](../custom_addons/gec_odoo_modules/rs_einvoice/models/account_move_reissue.py#L213),
[account_move_cancel.py:169-199](../custom_addons/gec_odoo_modules/rs_einvoice/models/account_move_cancel.py#L169)). A
corrector created in month M and accepted in M+1 is not "a corrector of the month" in M+1: M's core report holds
original + corrector, M+1 the reversal alone. No rs_einvoice test covers the reversal wizard or these chains (2026-10-22).
**Rule (plan Q9, decided 2026-10-22): a correction counts in the month the buyer accepts it.** Generate therefore keys on
acceptance, not on the corrector's date: (a) a corrector of month M that is not accepted (status 4 / 5) or whose
original was reversed in a later month is taken out of M's ა I proposals and listed under Not Declared; (b) in the
month of the original's "replacement" reversal (skip reason `replacement`, dated on acceptance), `delta = vat(corrector)
− vat(original)` goes to `358_7` (decrease) or `358_6` (increase), and the reversal, plus the corrector if it is dated in
that month, are taken out of that month's ა I; (c) a same-month chain needs nothing (original cancelled). This fits
rs_einvoice as it is: the original stays posted until acceptance and the reversal is dated on acceptance. Odoo's own VAT
Report still counts a straddling corrector in its creation month; the form shows that difference on its own line.
Cancel & Reissue (mode `fresh`) keeps the copy's creation date when it is posted after status 7: check in Phase 2.

**Step 4 — computed cells (T3).** One function, no engine:
```python
def _cell_values(self, v):          # v: dict code -> typed or proposed value
    r2 = lambda x: round(x + 0.0, 2)
    for r in ('1', '2', '3', '4', '5', '6', '6_1', '7', '7_1', '8'):
        v[f'355_{r}_5'] = r2(v[f'355_{r}'] * 0.18)
    v['355_1_1_5'] = v['359_5']
    v['355_15'] = r2(sum(v[f'355_{r}_5'] for r in ('1', '1_1', '2', '3', '4', '5', '6', '6_1', '7', '7_1', '8')))
    ...
    v['358_15'] = r2(v['358_1'] + v['358_6'] + v['358_8'] + v['358_9'] + v['358_12'] + v['358_14'])
    v['358_16'] = r2(v['358_7'] + v['358_10'] + v['358_11'] + v['358_13'])
    diff = r2(v['358_15'] - v['358_16'])
    v['358_17'], v['358_18'] = (math.floor(diff), 0) if diff > 0 else (0, math.floor(-diff))
```
The full list is section 2 of the portal doc (ა II × 18 %, ა III column 3 = 4 + 5 and totals, III-19⁶ margin VAT,
`358_1/2/3/5/8/11`). `358_10` = Σ `ref_line_ids` of grid ix; `355_8` += Σ `tourist_line_ids.amount_7`.

**Step 5 — rows.** `rs.vat.invoice.line` from posted `out_invoice` / `out_refund` (part sale) and `in_invoice` /
`in_refund` (part purchase) dated in the month, company currency amounts:

| Column | Odoo value | Evidence |
|---|---|---|
| `series`, `number` | `rs_einv_series`, `rs_einv_number` (raw strings from rs.ge) | [account_move_sync.py:47-57](../custom_addons/gec_odoo_modules/rs_einvoice/models/account_move_sync.py#L47) |
| `period` | `invoice_date` year-month | [account_move.py:387-392](../custom_addons/gec_odoo_modules/rs_einvoice/models/account_move.py#L387) |
| `partner_tin` | `commercial_partner_id.vat` | core |
| `amount` / `reduce_amount` | `abs(amount_tax_signed)`: invoices and increasing correctors → amount; credit notes and reducing correctors → reduce | core `amount_tax_signed` |
| `korect_series/number` | `rs_einv_replaces_id` or `reversed_entry_id` series and number | chain fields |
| `rs_status` | `rs_einv_status` | statuses: 2 confirmed, 8 correction confirmed, 3 corrected original |

Rows without a series and number, or with a status outside 2 / 3 / 8, are created with a warning and listed in
`not_declared_move_ids`. `rs.vat.advance.link` from `rs.einvoice.advance.settlement` rows whose `final_move_id` is in the
month (`vat_amount` = the attached VAT). `rs.vat.customs.line` from bills with a line tagged `25(T)`: `assessment_number`
= Bill Reference, `assessment_date` = Bill Date, `amount` = the `EX ONLY` tax line.

**Step 6 — sync cells and write warnings.** `_sync_cell_lines()` as in Form 30; `report_vat_total` versus `form_vat_total`
shown on the form.

---

## 5. Export (`action_export`) and attach (`action_attach_rsge`)

**Spreadsheets.** `xlsxwriter` as core does ([account_report.py:7822-7836](../enterprise/account_reports/models/account_report.py#L7822)):
one workbook per grid, one sheet, header row + rows in the portal's column order, stored in the Binary field and offered
through `ir.actions.act_url` on `/web/content/<model>/<id>/<field>/<name>?download=true`
([rs_form30_declaration_xlsx.py:46-56](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration_xlsx.py#L46)).
Column names and formats are taken from one portal **ექსპორტი** file per grid (input X1); until then the header row is
the portal `x_name` list from the portal doc, marked provisional. Grids: 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 18. Not 4 / 5
(see next paragraph) unless a primary declaration turns out not to accept API attachment.

**rs.ge attachment (T8).** The portal's annex ბ I / II are the invoices attached to the declaration number: after the
buyer confirms, the seller marks the invoices of the period and clicks "attach to declaration"; the invoices then appear
"ავტომატურად" in the declaration's registers (Revenue Service manual, quoted in the research notes). The SOAP API exposes
the same action: `get_seq_nums(sag_periodi)` returns the period's declaration numbers and `add_inv_to_decl(seq_num,
inv_id)` attaches one invoice ([rs_invoice_api_docs.md:772-799](../rs_invoice_api_docs.md)). Our `rs.soap.service` has
no wrapper for either yet ([rs_soap_service.py:134-561](../custom_addons/gec_odoo_modules/rs_einvoice/models/rs_soap_service.py#L134)): two
ten-line methods, same shape as `get_invoice`. The button: take the company's rs.ge user the way the crons do
(`_rs_responsible_user`, [res_users.py:195-208](../custom_addons/gec_odoo_modules/rs_base_methods/models/res_users.py#L195)),
read or confirm `rs_seq_num`, call `add_inv_to_decl` for every auto row with a status in 2 / 3 / 8, store the result on
the row. Buyer side (bills) attaches to the buyer's own declaration number (`seq_num_b`). The portal declaration must
exist first; the accountant creates it in the portal as today. [Likely] the attach call is idempotent; test on one invoice
of a test taxpayer before the button goes to accountants.

---

## 6. Views, security, data

- **Form:** header buttons + state; title; a group with month, type, declaration number, totals and the two comparison
  figures; a warning box; a notebook with 18 pages in portal order, each page an editable list on the filtered O2M. Cell
  lists: `code`, `name`, `note` (optional), `value` (`readonly="computed"`), `odoo_value`, `proposed_value`
  (`optional="hide"`), `computed` invisible. Grid lists: the portal columns, `sum` on amounts, `source` and `rs_status`
  on invoice rows, `move_id` as a link.
- **List:** name, month, type, company, cells 17 / 18, state badge. **Menu:** Accounting > Reporting > დღგ-ის
  დეკლარაცია (sequence 61, next to Form 30 at 60, [menus.xml:3-7](../custom_addons/gec_odoo_modules/gec_income_tax_report/views/menus.xml#L3)).
- **Security:** per row model two access rows (`account.group_account_readonly` r, `account.group_account_user` crud) and a
  company rule `[('company_id', 'in', company_ids)]`, exactly the Form 30 rows ([ir.access.csv:8-13](../custom_addons/gec_odoo_modules/gec_income_tax_report/security/ir.access.csv#L8)); `rs.vat.cell`: `base.group_user` r, `account.group_account_manager` crud.
- **Cell catalog CSV:** generated from the portal doc by a script, columns `id,code,tab,row,name,column,note,computed,proposed,december_only,sequence`; ~125 rows; `data/rs.vat.cell.csv` loads by file name ([convert.py:739-740](../odoo/tools/convert.py#L739)).
- **Constraints:** `models.Constraint('UNIQUE(code)')` on the catalog only ([partner.py:340-341](../addons/account/models/partner.py#L340) for the 20.0 syntax). No other constraint.

---

## 7. What the accountant does each month (the whole flow)

1. Phase 0 done once: taxes right, so the core VAT Report is right.
2. Month closed in Odoo: invoices and bills posted, rs.ge statuses refreshed (Status Update, or the crons once enabled).
3. New declaration, month, **Generate**: cells of tabs 1-3 proposed, Part III computed, invoice rows built, warnings listed.
4. Fix what the warnings say (an invoice without rs.ge number, a corrector not yet confirmed), type the few manual cells,
   Generate again.
5. On the portal: create the month's declaration, then in Odoo **Attach to rs.ge** (or export files for the manual grids).
6. Compare the portal's locked cells with Odoo's: they must match to the lari because both use the same formulas.
7. Submit on the portal; **Export** in Odoo keeps the files and the rows as the record of what was declared.

---

## 8. Effort and order

| Phase | Deliverable | Size | Needs |
|---|---|---|---|
| 1 | module, catalog, cells (tabs 1, 2, 3, 16, 17), Generate steps 1-4 and 6, form, list, menu, access | ~350 Python, ~125 CSV rows, ~400 XML | Phase 0 of the plan |
| 2 | invoice rows, advance links, customs rows (steps 3 and 5), Not Declared list | ~200 Python | real rs.ge data on a test company |
| 2b | attach to rs.ge: 2 SOAP wrappers in `rs_einvoice`, one button | ~100 Python | one test taxpayer, X2 confirmed live |
| 3 | `rs.vat.ref.line` and tourist rows, their cell effects, spreadsheet export | ~150 Python, ~200 XML | X1 export samples |
| 4 | petroleum rows and balances | ~80 Python, ~150 XML | none; last, only because every tab is wanted |

Tests to propose when the user asks: cells against the September 2026 capture (975.60 / 5,420 / 500 / 475), a cross-month
chain (1,000 → 700: cell 7 = 54), a same-month chain (no cell 7), invoice rows for an invoice, a credit note and a
corrector, the attach button against the offline SOAP harness that `rs_einvoice` already has.

---

## 9. Things that look tempting and are wrong

| Temptation | Why not |
|---|---|
| Sum tax tags ourselves for annex ა | two engines, two answers; the core engine handles sign inversion, multi-company and cancelled moves already |
| Put Part III into the core report as `account.report.line` records | the form owns the typed cells and the chains; a second home for the same numbers |
| Reuse the Form 30 grid widgets | hard-wired names and a payroll dependency; plain lists do the job |
| Validate caps (cell 7 ≤ ბ I + ბ VIII, ა I.1-3 ≥ invoices) as constraints | the portal rejects them anyway; a warning line is enough |
| Create the portal declaration from Odoo | no API call creates one; the accountant does it |
| Export ბ I / II as spreadsheets by default | the portal fills them from attached invoices; a spreadsheet would duplicate rows |
| A cron that generates declarations | the accountant opens a month when the books are closed |

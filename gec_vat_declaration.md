# VAT Declaration (rs.ge) — `gec_vat_declaration`

> **Module:** `gec_vat_declaration` | **Path:** [`custom_addons/gec_odoo_modules/gec_vat_declaration/`](../custom_addons/gec_odoo_modules/gec_vat_declaration/)
> **Status:** Phase 1 of [`vat_declaration_build_plan.md`](../dev_notes/plans/vat_declaration_build_plan.md), built 2026-10-22, commits `4daad73` + `8759c4a` (grid, Georgian),
> 12 tests pass on a scratch DB (incl. a browser test of the grid). Tab 4 (annex ბ I, `b888439`) and tab 5 (annex ბ II,
> `cd2d81a`) added 2026-10-26; neither has tests of its own yet. Installed on gec20_prod1 since 2026-10-22, upgraded with
> tab 4 on 2026-10-26 and with tab 5 on 2026-10-27. Tab 17 (III-19⁶) proposed from sold margin-scheme fixed assets
> since 2026-10-28 (8 tests of its own, 20 in total), uncommitted; prod1 needs -u gec_vat_declaration.

## What It Does & Why It Exists

Georgian VAT payers file a monthly declaration on the rs.ge portal by the 15th. The portal form has 18 tabs; five of them
are cell forms whose numbers come from the books: ა I (taxable operations), ა II (reverse charge), ა III (creditable
VAT), Part III (the final calculation) and III-19⁶ (margin scheme). This module rebuilds those five tabs inside Odoo as
a **VAT Declaration** record per company and month: Odoo proposes every cell it can from its own VAT Report, applies the
portal's own formulas to the locked cells, and keeps what the accountant types. The accountant compares the result with
the portal, copies the cells, and marks the month as filed. Tabs 4 and 5 (annexes ბ I and ბ II) list the month's issued and
received tax invoices as rs.ge sees them, to compare with the portal's own lists. The other 11 tabs (customs, manual
grids, petroleum, tourist) come in later phases.

---

## The Big Picture — How It Works

```
New declaration (company, month)  -->  Generate  -->  type the manual cells, Save  -->  copy to the portal  -->  Mark as Filed
                                       (Odoo proposals    (locked cells recomputed           (locked; Reset to Draft
                                        + portal formulas)  on every Save)                     to change it)
```

1. **Generate** reads the month's totals from core's Georgian VAT Report (`l10n_ge.tax_report_ge`) through the report
   API, the way Odoo's own tax returns do: posted entries only, the company plus its branches with the same VAT number.
   The report's numbers are stored on each cell as **Odoo** (`odoo_value`).
2. Each cell is one of three kinds, copied from Form 30:
   - **Computed** (locked on the portal): always the portal formula, e.g. VAT = base × 18 %, Part III 17 / 18.
   - **Proposed** (editable on the portal, Odoo has a source): follows Odoo until the accountant types something else;
     after that Generate never overwrites it.
   - **Typed** (no Odoo source): never touched.
3. **Save** recomputes every locked cell after typing, so Part III always shows the result the portal will show.
4. Warnings are listed on the form and never block (duplicates, rounding, negative cells, December rows, branches).

### Key Decision Points
- **ა III fixed assets (decided 2026-10-22):** Odoo's report has one VAT total per row. Column 5 (fixed assets) is typed;
  column 4 (goods/services) is proposed as Odoo's row total − column 5; column 3 = 4 + 5, so the row total stays
  Odoo's number.
- **Corrections (Q9, decided 2026-10-22):** a correction counts in the month the buyer accepts it. Tab 4 lists it in
  that month; Part III cells 6 / 7 from the correction chain are not built yet, so cell 7 is still typed.
- **Primary or adjusted:** several declarations of one month are allowed (adjusted ones); Generate warns about the others.

---

## Real-World Scenarios

### Scenario 1: September, one sale and one purchase
**Situation:** Sales of 5,420 + 18 % VAT to a VAT-registered customer, a purchase with 500 VAT.
**What they do:** Accounting > Reporting > **VAT Declaration (rs.ge)**, New, month September, **Generate**.
**What happens:** ა I row 1 = 5,420 with VAT 975.60; ა III row 1 = 500; Part III 1 = 975.60, 2 = 5,420, 11 = 500,
17 = **475** (975.60 − 500, rounded down to whole lari as the portal does). Same numbers as the portal capture.

### Scenario 2: Part of the input VAT is a fixed asset
**What they do:** On ა III, type 100 in row 1 column 5, Save.
**What happens:** Column 4 becomes 400, column 3 stays 500, Part III does not change.

### Scenario 3: A turnover decrease typed by hand
**What they do:** Part III, type 54 in cell 7, Save.
**What happens:** Cell 16 = 554, cell 17 = 421. With 1,000 instead: cell 17 = 0, cell 18 = 524 (refund side).

### Scenario 4: December
**What happens:** ა III rows 6 and 6¹ (own-built building, own repairs), columns 4 and 5, can be typed only in a
December declaration; the portal unlocks them only then (Order 996 Art. 75 §5). Other months show them locked at 0.

---

## The pages (rebuilt 2026-10-22 to look like rs.ge)

Each page is a grid drawn by the `gec_vat_grid` widget, laid out like the portal page:

| Tab | Green bar (full portal title) | Columns | Rows |
|---|---|---|---|
| 1 · ა-I დასაბეგრი | დანართი "ა" ნაწილი I დღგ-ით დასაბეგრი ოპერაციები | დასაბეგრი ბრუნვა · 18% | 22 |
| 2 · ა-II უკუდაბეგვრა | დანართი "ა" ნაწილი II უკუდაბეგვრის წესით დარიცხული დღგ | უკუდაბეგვრას დაქვემდებარებული ბრუნვა · 18% | 4 |
| 3 · ა-III ჩასათვლელი | დანართი "ა" ნაწილი III დღგ-ის ჩასათვლელი თანხა | ჯამი · საქონელზე/მომსახურებაზე · ძირითად საშუალებაზე | 11 |
| 16 · III გაანგარიშება | დღგ-ის საერთო თანხის გაანგარიშება | დასაბეგრი ოპერაციები · გადასახდელი · შესამცირებელი (numbered 1 · 2 · 3) | 20 |
| 17 · III-19⁶ მარჟა | the portal's III-19⁶ title | შესყიდვის ფასი · მიწოდების ფასი · დღგ | 5 |

- One row per portal row; a cell sits in the column where the portal has its input (catalog fields `line`,
  `line_label`, `slot`, taken from the portal capture). Part III pairs (6)/(7), (9)/(10), (12)/(13), (15)/(16) share a row.
- Lock = calculated by the portal (read-only); wand = proposed by Odoo (editable, follows Odoo until typed); no icon =
  typed. Click an editable cell to type; Save recomputes the locked cells.
- A grey "Odoo x" under a cell shows Odoo's figure when it differs: Odoo's proposal on a proposed cell, Odoo's own report
  figure on a locked cell (e.g. Odoo's real VAT beside the portal's 18 %).
- Georgian interface: `i18n/ka_GE.po` (house terms: გენერირება, მონახაზზე დაბრუნება, ჩაკეტილი, შემოთავაზებული).
- Proof: the browser test renders the grid (22 rows, lock icons, no OWL error); screenshots of all 5 pages in
  `Claude outputs/vat_phase1_20261022/screens_ka/`.

## Tab 4 — annex ბ I, issued tax invoices (added 2026-10-26)

Nothing on this page goes to rs.ge: the portal attaches confirmed invoices to the declaration by itself. The page shows
what Odoo expects the portal's ბ I to hold, so the accountant can compare before filing.

**Which invoices become rows** (`_gec_b1_scan`, [gec_vat_declaration.py:363](../custom_addons/gec_odoo_modules/gec_vat_declaration/models/gec_vat_declaration.py#L363)): customer
invoices of the company and its same-VAT branches with an rs.ge number and an rs.ge status of confirmed (2), corrected
original (3) or confirmed correction (8). Cancelled ones are included: when a correction is accepted in the same month,
rs_einvoice cancels the original in Odoo, but rs.ge keeps listing it as status 3.

**Which month a row belongs to** (`_gec_b1_month`, [:347](../custom_addons/gec_odoo_modules/gec_vat_declaration/models/gec_vat_declaration.py#L347)): its invoice date, except a correction,
which counts in the month the buyer accepted it. When the original sits in an earlier VAT month, rs_einvoice reverses it
on acceptance with a credit note marked Skip rs.ge, reason "replacement", dated that day
([account_move_cancel.py:169](../custom_addons/gec_odoo_modules/rs_einvoice/models/account_move_cancel.py#L169)); that date
is the month.

| Column | From |
|---|---|
| სერია, ნომერი | the invoice's rs.ge series and number |
| დასაბეგრი ოპერაციის თვე | invoice date (shown as the first day of the month) |
| მყიდველის ს/ნ | buyer Tax ID as sent to rs.ge (`rs_einv_buyer_tin`) |
| დღგ: გადასახდელი / შესამცირებელი | an invoice: its VAT; a correction: its VAT minus the corrected invoice's VAT, an increase on the left, a decrease on the right. VAT counts only tax lines whose tax has Tax Category Code S, the same VAT rs_einvoice sends (`_gec_invoice_vat`); City Tax, Small Business turnover and 0% taxes add nothing |
| კორექტირებული ფაქტურის სერია, ნომერი | the corrected invoice (corrections only) |

Example (prod1, October 2026): original `ეა-87 0060685` VAT 3,600, correction `ეკ 15610312` to 2,700 → two rows,
3,600 payable and 900 reduced; the page's net equals the 2,700 Odoo books.

The sub-grid lists advance offsets from rs_einvoice's native advance settlements that rs.ge accepted (status 200):
delivery invoice, advance invoice, VAT. Rows linked to an Odoo invoice or settlement are rebuilt on every Generate;
typed rows (a paper invoice) are kept and shown shaded.

**The page** is drawn by the `gec_vat_rows` widget
([gec_vat_rows.js](../custom_addons/gec_odoo_modules/gec_vat_declaration/static/src/components/gec_vat_rows/gec_vat_rows.js)),
copied from the portal's ბ I HTML: green title, two-row header ("დღგ-ს თანხა" and "ანგარიშ ფაქტურა რომლის
კორექტირებაც წარმოებს" over their two columns), the portal's column widths (12/15/15/15/10/10/12/11 %), the "?"
help text, a totals row (fields `b1_amount`, `b1_reduce_amount`, `b1_advance_amount`), month shown as `10.2026`. Per
row: an open icon for Odoo rows, a delete icon for typed rows; **Add a row** adds a typed row. Not copied: the portal's
filter row, page-size selector, export and import (export is plan Phase 6).

**Companies:** the same as the VAT report, the declaring company and its own branches with the same Tax ID
(`_get_branches_with_same_vat` limited to `child_of` the company).

**Warnings** (never block): invoices to a contact with a Tax ID that are missing from rs.ge or not accepted (grouped by
rs.ge status, first 20 names), a correction counted in another month, an invoice cancelled in Odoo but still confirmed
on rs.ge, an accepted correction whose original still counts in Odoo (`rs_einv_correction_in_flight`: run Status
Update, unreconcile payments first), and ბ I VAT above ა I rows 1-3 (the portal requires rows 1-3 to cover the month's
invoices).

## Tab 5 — annex ბ II, received tax invoices (added 2026-10-26)

Same page as tab 4, with the supplier's Tax ID and the creditable VAT (`ჩასათვლელი`). It lists what Odoo expects the
portal's ბ II to hold. The buyer side differs from the seller side in three ways, and each rule follows from it.

| Point | Rule | Why |
|---|---|---|
| Which bills | vendor bills with an rs.ge number and status 2 / 3 / 8, in any Odoo state | the portal lists rs.ge-accepted invoices; a draft or cancelled bill gets a warning |
| Which month | the bill's **accounting date** | that is where Odoo's VAT report credits the VAT (ა III); core moves a late bill into the first open month when the tax lock date covers its invoice date |
| VAT | the bill's tax lines without Georgian withholding taxes (`gec_is_withholding`) | a bill can carry withholding next to VAT |
| Correction | a bill linked to the bill it replaces (`rs_einv_replaces_id`); the row is the change against it | rs_einvoice imports a supplier correction as a new bill ("fresh" mode) and cancels the original ([account_move_buyer.py:650](../custom_addons/gec_odoo_modules/rs_einvoice/models/account_move_buyer.py#L650)) |

Code: `_gec_b2_scan` ([gec_vat_declaration.py:483](../custom_addons/gec_odoo_modules/gec_vat_declaration/models/gec_vat_declaration.py#L483)), `_gec_bill_vat` ([:478](../custom_addons/gec_odoo_modules/gec_vat_declaration/models/gec_vat_declaration.py#L478)).
Rows are `gec.vat.invoice.line` with `part = purchase` (ბ I rows have `part = sale`). rs_einvoice keeps no advance links
for bills, so the ბ II advance sub-grid holds typed rows only.

Example (prod1 copy, September 2026): bill `ეა-86 7706173` VAT 500.80 (posted) and `ეა-86 7674590` VAT 49.27 (accepted
on rs.ge, still a draft in Odoo), total 550.07; warnings for the draft and three bills still pending on rs.ge.

**Warnings:** accepted on rs.ge but a draft in Odoo (VAT not credited); cancelled in Odoo but confirmed on rs.ge; a
correction whose original was in an earlier month; bills waiting on rs.ge (grouped by status; from 1 October 2026 they
must be accepted or rejected before the 5th); posted bills with VAT from Georgian suppliers not linked to rs.ge; ბ II
VAT differs from ა III row 1.

**Known gap in rs_einvoice [Certain]:** importing a supplier correction cancels the original bill even when it sits in
an earlier, already declared month (no lock date set). Odoo's VAT of that month drops after filing and the correction
month credits the full VAT, while rs.ge counts only the change. The declaration warns; the fix belongs in rs_einvoice
(reverse in the current month, as the seller side does).

## Tab 17 — III-19⁶, the margin scheme (rebuilt 2026-10-28 on fixed assets)

A VAT payer that resells second-hand goods, works of art, collectors' items or antiques pays VAT on the margin only:
per row, VAT = (sale price − purchase price) ÷ 1.18 × 0.18, a loss row counting 0. The row total goes to ა I row 1¹ and
Part III. The four categories exclude each other in the law (Tax Code Art. 157: "secondary goods" are used goods other
than art, collectibles and antiques). The accountant books these goods as **fixed assets** (decided 2026-10-28), so
the category is on the asset.

**The accountant's flow**

| Step | Where | What Odoo keeps |
|---|---|---|
| 1. Buy | Vendor bill, description-only line on a fixed-asset account (one line per item, quantity 1), usually no tax | Core creates the asset; its **Asset Value** (`original_value`) is the purchase price |
| 2. Classify | Asset form: **Margin Scheme** = Second-hand Goods / Work of Art / Collectors' Item / Antique; model "No depreciation"; Confirm | `gec_margin_scheme` ([account_asset.py](../custom_addons/gec_odoo_modules/gec_vat_declaration/models/account_asset.py)) |
| 3. Sell | Customer invoice, description-only line, no tax; post it | — |
| 4. Link | Asset → Modify Depreciation → **Sell**, pick that invoice line; post the draft "Sale" entry core creates | The invoice line's **Sold Asset** (`gec_sold_asset_id`), written by our extension of core's `set_to_close` |
| 5. Declare | VAT Declaration → Generate | Tab 17 proposes purchase and sale price per category |

Core keeps no link from a sold asset to its invoice line (the Sell action only writes chatter,
[account_asset_variant.py:711-758](../enterprise/account_asset/models/account_asset_variant.py#L711)), hence step 4's
field. A new Sell or Dispose of the same asset (after Set to Running) moves the link; an invoice that was credited keeps
it, so its credit note still shows a warning. The column is on customer invoice lines (not credit notes), hidden by
default; Margin Scheme shows on assets of Georgian companies only.

**What Generate proposes** (`_gec_margin_scan`, [gec_vat_declaration.py](../custom_addons/gec_odoo_modules/gec_vat_declaration/models/gec_vat_declaration.py)):
posted invoice lines of the month (accounting date, as ა I) linked to an asset with a category, summed per category.
Sale price = the lines' amount in GEL as booked; purchase price = the asset's Asset Value, counted once: in the month of
the asset's first non-credited invoice line, or together with a sale that was later credited (goods returned and sold
again count the purchase price again in the resale month). The 8 price cells are proposed (wand) and follow Odoo until typed.

Example (scratch DB test): assets 1,000 / 500 / 300 / 200 sold for 1,180 / 618 / 354 / 500 → rows 27.46 / 18.00 / 8.24
/ 45.76, ა I row 1¹ = 99.46.

**Warnings** (never block):

| Warning | Meaning |
|---|---|
| sold with a tax | The line carries a tax: the sale price leaves it out and a VAT tax also reaches Odoo's VAT report (the core "18% Margin Scheme" charges 18% of the full price) |
| no longer closed | The asset was set to running after its sale (sale undone) |
| credit notes cancel margin-scheme sales | Correct the row by hand |
| without a purchase price | Asset Value 0: VAT on the full sale price |
| without VAT and without a category | A sold asset that looks like a margin sale but has no category |
| purchase price already counted | The same asset sold through invoices of two months; only the sale price counts here |
| sold or disposed without a posted invoice line | Core's Sale/Disposal entry of the month has no linked invoice (receipt, Point of Sale, cancelled invoice): type the row if it was a margin sale |
| sold this month on an invoice of another month | Sell done after the invoice's month: the sale belongs to the invoice's month (regenerate or adjust that declaration) |

**Setup rules:** one bill line per item (core makes one asset per line and Sell closes the whole asset); confirm
the asset before selling (Modify Depreciation shows on running assets only); sell on a customer invoice (the Sell picker
offers invoices only); "No depreciation" model for goods held for resale. If `gec_property_tax_report` (Form 15) is
installed, tick "Exempt from Property Tax" on margin assets, otherwise they enter the property-tax base.

**Not covered / open:** whether rs.ge expects a tax invoice for margin sales and how the margin VAT is booked to
333002 (accountant question #30); assets bought with deductible VAT (the margin scheme normally excludes them; no
warning).

## How Things Work Under the Hood

- **Catalog** `gec.vat.cell`: 109 cells (ა I 32, ა II 7, ა III 33, Part III 24, III-19⁶ 13), code = portal input id
  without `control_` (`355_1_5`, `353_43_1`, `358_17`), Georgian label and portal tooltip. Generated from the portal
  capture by `Claude outputs/vat_portal_20261021/tools/gen_cell_csv.py`, which fails unless the counts match.
- **Values** `gec.vat.declaration.line`: `value`, `proposed_value` (last proposal), `odoo_value` (Odoo's figure).
- **`_gec_report_totals()`** ([gec_vat_declaration.py:281](../custom_addons/gec_odoo_modules/gec_vat_declaration/models/gec_vat_declaration.py#L281)) — report options with
  `period_type: 'month'` and `tax_unit: 'company_only'` on a sudo report object scoped to the company tree, as core's
  return does ([account_return.py:1158](../enterprise/account_reports/models/account_return.py#L1158)). A `return_period` date would raise: Georgia has no VAT return type.
- **`ODOO_SOURCE`** ([gec_vat_declaration.py:11](../custom_addons/gec_odoo_modules/gec_vat_declaration/models/gec_vat_declaration.py#L11)) — portal cell → core line: ა I bases from `ge_1`, `ge_3`…`ge_20`
  (row 1¹ comes from tab 17, not from `ge_2`), ა II from `ge_21`…`ge_23`, ა III totals from `ge_24`…`ge_33`; Odoo's own VAT
  per row is kept beside the portal's 18 % for comparison.
- **`compute_cells()`** ([gec_vat_declaration.py:97](../custom_addons/gec_odoo_modules/gec_vat_declaration/models/gec_vat_declaration.py#L97)) — the portal JavaScript formulas in dependency order (margin
  scheme, ა I, ა II, ა III, Part III 1-11, 15 / 16, 17 / 18). Half-up rounding to 2 decimals; 17 / 18 floored. The portal
  reads a negative input as 0 (`parseFloat('0' + value)`), so negatives count as 0 in the formulas, are kept as typed and
  produce a warning.
- **`_gec_sync_cell_lines()`** ([gec_vat_declaration.py:315](../custom_addons/gec_odoo_modules/gec_vat_declaration/models/gec_vat_declaration.py#L315)) — proposals first (column 4 reads the current
  column 5), then formulas on the merged values; runs on create, Generate and every Save of a draft. Form 30's order
  (formulas before proposals) would leave the cells one save behind.

### Guards
- Company or month cannot change once a cell has a value; a filed declaration's cell lines cannot be written; a filed
  declaration cannot be deleted; catalog cells cannot be deleted while used (`ondelete='restrict'`).

---

## Gotchas
- **[Certain] Odoo's VAT Report and this form differ by design** where the portal differs: VAT is base × 18 % (Odoo's own
  VAT per row is shown beside it, with a warning when they differ), and a correction counts when the buyer accepts it.
- **[Certain] Old prod1 invoices sit on tag 2 (`18% S`)** from before the Phase 0 tax fix: a prod1 Generate of those months
  shows ა I row 1 empty and a margin-scheme warning.
- **[Likely] Rounding:** the portal's `round_2` body is not in the capture; half-up is assumed (a 0.01 difference is possible
  on exact half-tetri values).
- **[Certain] A margin-scheme row sold below cost counts 0**, as on the portal (`control_359_sum` builds `'0' + value`),
  so it never lowers Part III.
- **[Certain] The portal itself is inconsistent on ა III row 4¹:** its page-load sum of Part III cell 11 leaves `353_43_1`
  out, its edit-time sum (`control_353_sum`) includes it. The form follows the edit-time sum; check cell 11 on the
  portal when row 4¹ has a value.
- **Warnings refresh on Generate and on every Save.** The ა I / ა II "Odoo VAT ≠ 18 %" warning appears only for rows whose
  base still equals Odoo's.
- **Recompute runs through the form** (the tab fields). A line written directly by import or RPC is not recomputed until
  the next Save or Generate.
- **[Likely] A correction row carries only the change** (900 reduced, not the new 2,700), and **[Guessing] its month
  column shows the correction's own date**; neither is confirmed against a portal month that holds a correction.
- **[Likely] Final invoices in native advance mode:** rs.ge receives only the regular lines (full VAT), while the row
  takes Odoo's VAT, which nets the down-payment line, and the sub-grid subtracts the advance again. None exist yet on
  prod1; the rule is open.
- **Typed rows of a filed declaration** are read-only in the form only; unlike the cell lines, the row models have no
  server-side lock.
- **The acceptance month is the day Odoo learns it:** the reversal is dated when Status Update runs, not when the buyer
  clicked on rs.ge. A late Status Update moves the correction into the next month.
- **Not modelled:** the portal's "18 %" checkbox on ა I (VAT always computed), Part III cell 10 (ბ IX rows, Phase 3),
  December cells 19-20 (not in the captured form).

## Related
- [`vat_declaration_build_plan.md`](../dev_notes/plans/vat_declaration_build_plan.md) · [`vat_declaration_technical_design.md`](../dev_notes/plans/vat_declaration_technical_design.md) ·
  [`vat_declaration_rs_portal_pages.md`](../dev_notes/reference/vat_declaration_rs_portal_pages.md) · [`l10n_ge.md`](l10n_ge.md) (the VAT Report and the tax fixes) ·
  [`gec_income_tax_report.md`](gec_income_tax_report.md) (Form 30, the pattern)

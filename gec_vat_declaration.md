# VAT Declaration (rs.ge) — `gec_vat_declaration`

> **Module:** `gec_vat_declaration` | **Path:** [`custom_addons/gec_odoo_modules/gec_vat_declaration/`](../custom_addons/gec_odoo_modules/gec_vat_declaration/)
> **Status:** Phase 1 of [`vat_declaration_build_plan.md`](../dev_notes/plans/vat_declaration_build_plan.md), built 2026-10-22, commits `4daad73` + `8759c4a` (grid, Georgian),
> 12 tests pass on a scratch DB (incl. a browser test of the grid). Not installed on gec20_prod1.

## What It Does & Why It Exists

Georgian VAT payers file a monthly declaration on the rs.ge portal by the 15th. The portal form has 18 tabs; five of them
are cell forms whose numbers come from the books: ა I (taxable operations), ა II (reverse charge), ა III (creditable
VAT), Part III (the final calculation) and III-19⁶ (margin scheme). This module rebuilds those five tabs inside Odoo as
a **VAT Declaration** record per company and month: Odoo proposes every cell it can from its own VAT Report, applies the
portal's own formulas to the locked cells, and keeps what the accountant types. The accountant compares the result with
the portal, copies the cells, and marks the month as filed. The other 13 tabs (invoice registers, customs, petroleum,
tourist) come in later phases.

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
- **Corrections (Q9, decided 2026-10-22):** a correction counts in the month the buyer accepts it. Handled in Phase 2
  (Part III cells 6 / 7 from the rs.ge correction chain); Phase 1 leaves cell 7 to be typed.
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

## How Things Work Under the Hood

- **Catalog** `gec.vat.cell`: 109 cells (ა I 32, ა II 7, ა III 33, Part III 24, III-19⁶ 13), code = portal input id
  without `control_` (`355_1_5`, `353_43_1`, `358_17`), Georgian label and portal tooltip. Generated from the portal
  capture by `Claude outputs/vat_portal_20261021/tools/gen_cell_csv.py`, which fails unless the counts match.
- **Values** `gec.vat.declaration.line`: `value`, `proposed_value` (last proposal), `odoo_value` (Odoo's figure).
- **`_gec_report_totals()`** ([gec_vat_declaration.py:263](../custom_addons/gec_odoo_modules/gec_vat_declaration/models/gec_vat_declaration.py#L263)) — report options with
  `period_type: 'month'` and `tax_unit: 'company_only'` on a sudo report object scoped to the company tree, as core's
  return does ([account_return.py:1158](../enterprise/account_reports/models/account_return.py#L1158)). A `return_period` date would raise: Georgia has no VAT return type.
- **`ODOO_SOURCE`** ([gec_vat_declaration.py:9](../custom_addons/gec_odoo_modules/gec_vat_declaration/models/gec_vat_declaration.py#L9)) — portal cell → core line: ა I bases from `ge_1`, `ge_3`…`ge_20`
  (row 1¹ comes from tab 17, not from `ge_2`), ა II from `ge_21`…`ge_23`, ა III totals from `ge_24`…`ge_33`; Odoo's own VAT
  per row is kept beside the portal's 18 % for comparison.
- **`compute_cells()`** ([gec_vat_declaration.py:95](../custom_addons/gec_odoo_modules/gec_vat_declaration/models/gec_vat_declaration.py#L95)) — the portal JavaScript formulas in dependency order (margin
  scheme, ა I, ა II, ა III, Part III 1-11, 15 / 16, 17 / 18). Half-up rounding to 2 decimals; 17 / 18 floored. The portal
  reads a negative input as 0 (`parseFloat('0' + value)`), so negatives count as 0 in the formulas, are kept as typed and
  produce a warning.
- **`_gec_sync_cell_lines()`** ([gec_vat_declaration.py:296](../custom_addons/gec_odoo_modules/gec_vat_declaration/models/gec_vat_declaration.py#L296)) — proposals first (column 4 reads the current
  column 5), then formulas on the merged values; runs on create, Generate and every Save of a draft. Form 30's order
  (formulas before proposals) would leave the cells one save behind.

### Guards
- Company or month cannot change once a cell has a value; a filed declaration's lines cannot be written; a filed
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
- **Not modelled:** the portal's "18 %" checkbox on ა I (VAT always computed), Part III cell 10 (ბ IX rows, Phase 3),
  December cells 19-20 (not in the captured form).

## Related
- [`vat_declaration_build_plan.md`](../dev_notes/plans/vat_declaration_build_plan.md) · [`vat_declaration_technical_design.md`](../dev_notes/plans/vat_declaration_technical_design.md) ·
  [`vat_declaration_rs_portal_pages.md`](../dev_notes/reference/vat_declaration_rs_portal_pages.md) · [`l10n_ge.md`](l10n_ge.md) (the VAT Report and the tax fixes) ·
  [`gec_income_tax_report.md`](gec_income_tax_report.md) (Form 30, the pattern)

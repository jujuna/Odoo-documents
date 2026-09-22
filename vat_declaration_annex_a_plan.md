# VAT Declaration — Annex "a" Parts I–III: build plan

> **Target module:** [`custom_addons/gec_odoo_modules/gec_income_tax_report`](../custom_addons/gec_odoo_modules/gec_income_tax_report) (as instructed)
> **Source spec:** accountant's `დღგ დანართი ა.xlsx` — sheets `ა I`, `ა II`, `ა III` + 3 portal screenshots
> **Status:** PLAN, 2026-09-21. Nothing written yet.

---

## First: the module choice is wrong, and it costs you something real

`gec_income_tax_report` is the **withholding** declaration (Form 30). Its manifest depends on `geo_payroll`, so installing the VAT declaration would drag payroll into every database that only needs VAT. Meanwhile `gec_l10n_ge_tax` is literally named *"Georgia - Taxes & VAT Reporting"*, already owns the 15 `[GE-VAT]` tax grids ([`data/account_tax_tags.xml`](../custom_addons/odoo_taxes/gec_l10n_ge_tax/data/account_tax_tags.xml)), the DGV report and the `ge_vat_return_type` — that is where this belongs.

**The risk in putting it in `gec_income_tax_report`:** a payroll-free client installing the VAT declaration also installs `geo_payroll`, and any future payroll bug blocks VAT filing.

**But it changes almost nothing in the work.** The file layout below is identical either way, and `gec_income_tax_report` **already depends on `gec_l10n_ge_tax`** (manifest line 13), so the tags are reachable from day one and no manifest change is needed. Moving later is `git mv` + two manifest edits. **The plan below builds it where you asked.**

---

## The idea in one paragraph

Copy the Form 30 *main part* pattern that already works in this module: a **cell catalogue** loaded from CSV plus a **value row per cell** on the declaration, where each cell is one of three kinds — **computed** (arithmetic, never typed), **proposed** (Odoo fills it from the ledger and keeps refreshing until the accountant overwrites it), or **manual** (Odoo never touches it). The numbers Odoo can derive come from the **GE VAT tax grids that already exist**, summed off `account.move.line.tax_tag_ids` — the same source the DGV report uses, so there is one tax mapping in the system, not two.

```
account.move.line.tax_tag_ids   →  _tag_sum(cell.tag_expr)  ─┐
part-I/II values × 18%          →  formula                  ─┼→  rs.vat.line  →  OWL grid (editable
accountant types the rest       →  manual                   ─┘   (base/vat/         unless computed)
                                                                  goods/assets)      + per-row "why?"
```

---

## Strict separation from Form 30 — own model, own menu

**The VAT declaration is a different declaration from the income tax declaration.** Same monthly rhythm, same company, nothing else in common: different tax, different law, different portal pages, different lifecycle, different accountant signing it off. Nothing is shared at record level.

| | Income Tax Declaration (Form 30) | VAT Declaration (annex "a") |
|---|---|---|
| Model | `rs.form30.declaration` | **`rs.vat.declaration`** — new, no inheritance |
| Cells | `rs.form30.summary.cell` / `.line` | **`rs.vat.cell` / `rs.vat.line`** — new |
| Menu | *Accounting → Reporting → Income Tax Declaration (Form 30)* ([`menus.xml`](../custom_addons/gec_odoo_modules/gec_income_tax_report/views/menus.xml) `menu_rs_form30_declaration`, sequence 60) | **new sibling: *Accounting → Reporting → VAT Declaration*, sequence 61** |
| Config submenu | *Configuration → rs.ge Form 30 (Advanced)* | **own submenu, only if a cell catalogue screen is wanted** |
| Data | payslips, withholding payments, cars, services | posted journal items carrying `[GE-VAT]` tax grids |

**Reuse is by copy, not by inheritance.** `rs.vat.cell` / `rs.vat.line` repeat the 53 lines of `rs_form30_summary.py` with different value fields, and `_sync_lines()` repeats the refresh policy. Do **not** add a `declaration_type` selection to the Form 30 models to serve both — that would put two unrelated declarations on one record set, break the `UNIQUE(company_id, date_from)` constraint's meaning, and make every Form 30 domain need a type filter. Two small independent model sets are cheaper than one shared one.

Both declarations living in one module is a packaging decision (see the objection above); it must not become a data-model decision.

---

## What we reuse (nothing here gets rewritten)

| Reused | Where it is today | Used for |
|---|---|---|
| Cell catalogue + value-row shape | [`models/rs_form30_summary.py`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_summary.py) (53 lines total) | `rs.vat.cell` / `rs.vat.line` are the same two classes with different value fields |
| **Three-way refresh policy** (computed always follows, proposed follows until edited via a `proposed_value` shadow, manual never touched) | [`rs_form30_declaration.py:522`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L522) `_sync_summary_lines` | copied verbatim — this is the hard part and it is already solved |
| `_read_group` over posted move lines in the period | [`rs_form30_declaration.py:475`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L475) `_ledger_values` | the `_tag_sum()` helper is this method's domain with `tax_tag_ids` instead of `account_id` |
| Declaration header (company, `date_from` forced to day 1, `date_to`/`period` computed, draft/exported, one-per-company-per-month constraint) | [`rs_form30_declaration.py:99–183`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L99) | `rs.vat.declaration` header |
| Per-cell explanation page + `_trace_item` | [`wizard/rs_form30_explain.py`](../custom_addons/gec_odoo_modules/gec_income_tax_report/wizard/rs_form30_explain.py), [`rs_form30_declaration.py:416`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L416) | "why is cell 1 = 1000?" → list of invoices with links |
| OWL grid: row editable unless `computed`, per-row explain button | [`rs_form30_summary_grid.js`](../custom_addons/gec_odoo_modules/gec_income_tax_report/static/src/components/rs_form30_summary_grid/rs_form30_summary_grid.js) (61 lines) | the three declaration pages |
| Explanation workbook (xlsx) | [`models/rs_form30_declaration_xlsx.py`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration_xlsx.py) | optional, phase 3 |
| The 15 `[GE-VAT]` tags + the sign rule | [`gec_l10n_ge_tax/data/account_tax_tags.xml`](../custom_addons/odoo_taxes/gec_l10n_ge_tax/data/account_tax_tags.xml), sign convention documented at the top of [`dgv_tax_report.xml`](../custom_addons/odoo_taxes/gec_l10n_ge_tax/data/dgv_tax_report.xml) | every automatic number |

**Sign rule, carried over as-is:** sales tags sit on credit lines (negative balance), so their expression carries a leading `-`; purchase tags sit on debit lines and use the plain name.

---

## Data source, row by row

Legend: **AUTO** = Odoo computes it from the ledger · **CALC** = pure arithmetic, no data source · **TYPED** = accountant enters it, Odoo proposes nothing

### Part I — taxable operations (18% + exempt-with-credit)

Columns: `D` = taxable base (`დასაბეგრი ბრუნვა`) · `E` = VAT, **always `D × 18%`** except code 1¹.

| Code | Row | Where the base comes from | Kind |
|---|---|---|---|
| **1** | supply for consideration | tag `[GE-VAT] Taxable sales 18% - base`, **excluding** lines with `is_downpayment = True` (those are code 2) | AUTO |
| **1¹** | margin-scheme VAT | portal pulls it from annex III-19⁶; no margin scheme in our stack | TYPED (0) |
| **2** | advance received before supply | same tag, **only** `is_downpayment = True` lines that increase turnover this month (`account.move.line.is_downpayment`, [addons/sale/models/account_move_line.py:11](../addons/sale/models/account_move_line.py#L11)) | AUTO — **see Q1** |
| **3** | free supply of goods (VAT was credited) | no Odoo concept; needs a dedicated 18% tax or a journal convention | TYPED |
| **4** | goods shortage | market price ≠ Odoo's stock cost, so a stock-loss move cannot produce this figure | TYPED |
| **5** | free services for personal use | accountant note: *"we count nothing for state companies, Tako will supply extra logic"* | TYPED — **Q2** |
| **6** | own-built building put into use | accountant note: *"needs thinking"* | TYPED — **Q3** |
| **6¹** | own-force repair of own building | accountant note: *"need to work out how to know building repair costs"* | TYPED — **Q4** |
| **7** | barter (pre-2021 leg only) | legacy, practically always 0 | TYPED |
| **7¹** | goods retained after ceasing activity / dereg | one-off event | TYPED |
| **8** | other taxable operations | catch-all | TYPED |
| **9** | supplies to TC 172(3) persons (diplomats) | needs a new tag + a 0%-with-credit tax | TYPED → AUTO after **T1** |
| **10** | natural gas to thermal power plants | not our line of business | TYPED (0) |
| **11** | TC 172(1)/(2) incl. international transport | tag `[GE-VAT] Zero-rated intl transport - base` — **covers only part of 172(1)/(2)** | AUTO (partial) |
| **12** | international-treaty project supplies | needs a new tag | TYPED → AUTO after **T2** |
| **13** | other exempt-with-credit | catch-all | TYPED |
| *(sub)* | of which: shortage found by a tax-authority inventory | no code in the xlsx — a memo sub-row of 13 | TYPED |
| **14** | export / re-export | tag `[GE-VAT] Zero-rated export sales - base`. **Caveat:** rs.ge wants the *customs value*, which can differ from the invoice amount | AUTO — **Q5** |
| **14¹** | financial operations / services | exempt-without-credit; needs its own tag | TYPED → AUTO after **T3** |
| **14²** | supply of immovable property / land | needs its own tag | TYPED → AUTO after **T4** |
| **14³** | other exempt without credit | tag `[GE-VAT] Exempt sales (no credit) - base`, once 14¹ and 14² are split out of it | AUTO |
| **15** | **Total** | `Σ VAT column of codes 1 … 8` (xlsx `=SUM(E3:E13)`) | CALC |

### Part II — reverse charge

| Code | Row | Source | Kind |
|---|---|---|---|
| **1** | services from a non-established taxable person | tag `[GE-VAT] Reverse charge - base` | AUTO |
| **2** | foreign goods bought in a customs warehouse (TC 164¹(4)) | rare, no tag | TYPED |
| **3** | foreign goods bought from a FIZ enterprise (TC 164¹(5)) | rare, no tag | TYPED |
| **4** | **Total** | `Σ VAT of 1+2+3`. *(The xlsx writes `=SUM(E2:E5)`, which reaches one row too high into the header — a spreadsheet slip, not a rule.)* | CALC |

### Part III — creditable input VAT

Columns: `D` = total (**always `E + F`**) · `E` = VAT on goods/services · `F` = VAT on fixed assets.

| Code | Row | Source | Kind |
|---|---|---|---|
| **1** | VAT on domestic purchases from taxable persons | tag `[GE-VAT] Domestic purchases 18% - VAT credit`, split E/F — **see Q6** | AUTO |
| **2** | import VAT | tag `[GE-VAT] Import VAT - input credit`, same split | AUTO |
| **3** | import VAT assessed by tax-authority decision | no ledger trace | TYPED |
| **4** | reverse-charge VAT | **= Part II code 4**. Cross-check against tag `[GE-VAT] Reverse charge - input VAT credit` and warn on a mismatch | CALC |
| **4¹** | from annex "b" part X row 4 | annex "b" is out of scope for pages 1–3 | TYPED (0) |
| **5** | fixed assets retained after ceasing activity / dereg | pro-rated over tax years by hand | TYPED |
| **6** | own-built building — creditable | xlsx says *"filled automatically"*: `Part I code 6 × 18%` | CALC |
| **6¹** | own-force repair — creditable | xlsx says *"filled automatically"*: `Part I code 6¹ × 18%` | CALC |
| **7** | barter VAT | no invoice is issued between the parties | TYPED |
| **8** | VAT paid under TC 161¹ (auction / direct sale) | no ledger trace | TYPED |
| **9** | **Total** | `Σ` of each of D, E, F | CALC |

### The honest headline

**34 value rows across the three pages: 8 come from the ledger automatically, 10 are pure arithmetic, 16 the accountant types.** That ratio improves to roughly 12 automatic once the four new tags below exist and the taxes that carry them are configured. It will never reach 100% — rows 3–8 and 7¹ describe events that leave no invoice in Odoo.

---

## New tax grids needed in `gec_l10n_ge_tax`

Four tags, plus the 0%-with-credit taxes that carry them. Data-only change to [`account_tax_tags.xml`](../custom_addons/odoo_taxes/gec_l10n_ge_tax/data/account_tax_tags.xml) and the chart template.

| ID | Tag name | Feeds |
|---|---|---|
| **T1** | `[GE-VAT] Exempt w/credit - diplomatic (172.3) - base` | Part I code 9 |
| **T2** | `[GE-VAT] Exempt w/credit - treaty project (172.5) - base` | Part I code 12 |
| **T3** | `[GE-VAT] Exempt no credit - financial services - base` | Part I code 14¹ |
| **T4** | `[GE-VAT] Exempt no credit - immovable/land - base` | Part I code 14² |

After T3/T4 exist, `[GE-VAT] Exempt sales (no credit) - base` stops being a catch-all and means "other" (code 14³). **Existing postings keep the old tag** — no migration, so the first month after the change needs a manual reconcile of 14¹/14²/14³.

---

## Files

**New in `gec_income_tax_report`:**

```
models/rs_vat_cell.py            rs.vat.cell  + rs.vat.line          (~60 lines, copy of rs_form30_summary.py)
models/rs_vat_declaration.py     rs.vat.declaration + _tag_sum()     (~180 lines)
data/rs.vat.cell.csv             34 rows: part, code, name, note, sequence, column_set, kind, tag_expr, formula
views/rs_vat_declaration_views.xml   list + form (3 notebook pages, one grid each) + action + own menuitem
static/src/components/rs_vat_grid/   copy of rs_form30_summary_grid (js/xml/scss)
wizard/rs_vat_explain.py         per-cell "why?" page (phase 3)
security/ir.model.access.csv     +3 model lines
```

**Changed:** `__manifest__.py` (data + assets lists only — **no new dependency**), `models/__init__.py`, and [`views/menus.xml`](../custom_addons/gec_odoo_modules/gec_income_tax_report/views/menus.xml) — one new entry beside the Form 30 one, not nested under it:

```xml
<menuitem id="menu_rs_vat_declaration"
          name="VAT Declaration"
          parent="account.menu_finance_reports"
          action="action_rs_vat_declaration"
          sequence="61"/>
```

### The one design decision worth stating

Put the **tag mapping in the CSV, not in Python**: `rs.vat.cell.tag_expr` holds the tag name with an optional leading `-` for the sign, exactly like an `account.report.expression` formula. Then one generic 10-line `_tag_sum()` serves every AUTO row, and changing a mapping is a data edit. Only three cells need named Python handlers — the down-payment split (codes 1 and 2) and the fixed-asset split (Part III codes 1 and 2).

---

## Build order

| Phase | What | Result |
|---|---|---|
| **1** | 3 new models + CSV catalogue + `_sync_lines()` + list/form with 3 grids + **its own Reporting menu beside Form 30** | The three pages exist and show zeros; the accountant can already type |
| **2** | `_tag_sum()` + the CALC formulas + the two Python splits | 8 rows fill themselves; totals and VAT columns compute |
| **3** | The 4 new tags + the taxes that carry them + the explain wizard | ~12 rows automatic, each with a "why?" trace |
| **4** | Compare a real month against the portal, side by side | Sign-offs on Q1, Q5, Q6 |

Phase 1 alone is usable: typing 34 numbers into a form that remembers them, totals them and never loses them beats typing them on the portal.

---

## Open questions

| # | Question | Who decides |
|---|---|---|
| **Q1** | Down payments: does the final invoice's negative down-payment line net code 2 to zero across months, and is code 1 then already the difference the form asks for? **Must be checked against a real Odoo down-payment invoice in the DB before writing the split.** | verify in DB, then accountant |
| **Q2** | Code 5 — the extra logic for state companies that Tako will supply | accountant |
| **Q3** | Code 6 — how a self-built building's production cost is identified in Odoo | accountant + dev |
| **Q4** | Code 6¹ — how building repair costs are recognised (dedicated account? analytic account?) | accountant + dev |
| **Q5** | Code 14 — do we report the invoice amount or the customs value from the export declaration? If customs value, the `rs_waybill`/`rs_einvoice` data may be the better source | accountant |
| **Q6** | Part III E/F split — is a purchase "fixed assets" when the counterpart account type is `asset_fixed`, or only when an `account.asset` exists (`original_move_line_ids`, [enterprise/account_asset/models/account_asset.py:135](../enterprise/account_asset/models/account_asset.py#L135))? | accountant |
| **Q7** | Do we also need the **filing file**, or only the on-screen form? Form 30 exports SpreadsheetML for the portal importer; the VAT pages appear to be typed on the portal, in which case no export is needed | accountant |

Q1, Q6 and Q7 block phase 2. Q2–Q5 only affect rows that stay TYPED until answered, so they block nothing.

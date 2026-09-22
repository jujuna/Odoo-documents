# gec_income_tax_report — rs.ge Form 30 Declaration Export

> **Status:** source 19.0.1.9.0 (2026-09-03), installed on `gec_modules_hr3` and `codex_form30_grid_ui_20260902`; **no test-suite run is evidenced** (three test classes, see §9). 1.7.0 adds the matrix constraint on lines (§4). Versions 1.2–1.4 added the read-only OWL lines grid, the Georgian translation and the translated warning display (§9); they also removed the UI path for manual rows (§8). Companion change: `gec_l10n_ge_tax` 19.0.1.1.0 adds 7 WHT taxes (resident services 20%/5%, resident rent 5%, stipend 20% on 3320; offshore royalties/interest/services 15% on 3310.02) plus an only-if-missing template loader in its maintenance pass. Trimmed v1.0 scope of [`rs_form30_declaration_plan.md`](rs_form30_declaration_plan.md).
> **Path:** `custom_addons/gec_odoo_modules/gec_income_tax_report` (`custom_addons/gec_odoo_modules` is on `addons_path`; the older nested copy under `gec_extra_modules` is superseded).
> **Domain reference:** [`sashemosavlo_deklaraciebi_sruli_cnobari.md`](../sashemosavlo_deklaraciebi_sruli_cnobari.md).
> **Guides in the module:** [`README.md`](../custom_addons/gec_odoo_modules/gec_income_tax_report/README.md) for the accountant, [`README_DEV.md`](../custom_addons/gec_odoo_modules/gec_income_tax_report/README_DEV.md) for developers; `tools/generate_classifier_csv.py` regenerates the classifier data from a new rs.ge xlsx.

> **19.0.1.10.0 source update (2026-09-05):** contact category history (`rs_form30_category_history_ids` →
> `rs.form30.partner.category`) uses inclusive, non-overlapping Valid From / Valid To dates. Salary rows resolve by
> `paid_date`, payment rows by `payment.date`, manual suggestions by the row date. The old `rs_form30_category_id`
> remains a fallback only while no history exists, so no migration script is needed. Once history exists, gaps warn and
> block export instead of using the old/default category. Existing report rows remain snapshots until regeneration.
> Contact forms/lists show a computed current category. No new test cases were added for it. Historical notes below describe 1.9.0.
>
> **19.0.1.11.0 (2026-09-05, installed on `gec_modules_hr3`):** Codex cleanup pass ([`SIMPLIFICATION_REVIEW.md`](../custom_addons/gec_odoo_modules/gec_income_tax_report/SIMPLIFICATION_REVIEW.md)):
> grid footer totals computed once per render, batched country lookups in the residency sync, error labels built only for
> failing lines, company locked once a declaration has lines, `current_version_id` used by the hr.version sync. The history
> feature had a live trap: **Valid From defaulted to today**, so a first history entry blanked the category of every row of
> the month being declared (hr3, 2026-09-05, three rows, export blocked). The default was removed on 2026-09-13.
>
> **2026-09-13 (source only, hr3 not upgraded yet):** `rs.form30.country`, the partner field `rs_form30_country_id` and the
> 19.0.1.9.0 nationality ↔ residency sync were removed. Residency is the contact's standard `country_id`; the rs.ge code is
> `res.country.rs_form30_code`, loaded for 235 countries by `data/res.country.csv`. A country without a code blocks the export.
>
> **19.0.1.12.0 (2026-09-14/15, source in `custom_addons/gec_odoo_modules/gec_income_tax_report`, the authoritative copy;
> not run, not committed):** the module now builds four pages. Annex D (`rs.form30.car.line`, typed, prefilled from
> `fleet.vehicle` + `hr_fleet` driver, fixed tax per `rs.form30.car.engine` band, 5-column file), annex E
> (`rs.form30.service.line`: withholding lines whose partner is flagged individual entrepreneur or small business leave
> annex A and land here, service type from `account.tax.rs_form30_service_type_id`, 7-column file), a treaty allowance
> ledger on the contact (`rs_form30_exempt_limit`, `rs.form30.exempt.usage`), a manager-only tax/RS-rule change wizard,
> and the **main part** (§10): on 2026-09-15 `_summary_values` was rewritten to derive every cell 16–69 from the annex
> rows and the ledger; `rs.form30.summary.cell` gained a `proposed` flag, `rs.form30.category` an `is_organization`
> column, `hr.work.location` a `rs_form30_autonomous_republic` selection for cells 57¹/57². The 2026-09-15 UI strings are
> not yet translated. Two test methods still call `_recipient_classification` with a stale third positional argument.

## 1. Purpose

The monthly "გადახდის წყაროსთან დაკავებული გადასახადის დეკლარაცია" (rs.ge form 30) needs one annex row per recipient and payment: who was paid, what kind of income, how much, when, at which rate. The portal computes the withheld tax and the pension 2% itself. This module collects the rows from Odoo, validates them against the rs.ge classifier matrix and writes the exact import file. Nothing is booked and no existing flow changes.

## 2. Flow

```
Accounting > Reporting > Income Tax Declaration (Form 30)
  create month  ->  Generate Lines  ->  review warnings (manual rows: see §8)  ->  Export rs.ge File  ->  upload on eservices.rs.ge
```

| Step | What happens | Where |
|---|---|---|
| Generate | Deletes payslip/payment rows of the month, keeps manual rows, rebuilds from the two sources | [`rs_form30_declaration.py`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py) `action_generate` |
| Review | Rows with a `warning` are tinted in the read-only lines grid (§9); since 19.0.1.4.0 nothing can be edited or added from the form, see §8 | declaration form, Lines tab |
| Export | Blocks on rule violations, otherwise stores the file on the declaration and sets state `exported` | `action_export`, `_check_lines`, `_build_xml` |

Regenerating after an amendment is safe: manual rows survive, auto rows are rebuilt from the current data.

## 3. Sources and math

**Payslips** (`hr.payslip`, state `paid`, `paid_date` in the month, not a credit note). One row per slip, cash basis: the row belongs to the month the salary was paid, not the month it was earned.

| Column | Value |
|---|---|
| Gross amount | `GROSS` + `ADVANCE_PAY` input amounts |
| Withheld tax (control) | `-PIT` + `ADV_PIT_PRE` |
| Pension (control) | `-PENSION_EE` + `ADV_PEE_PRE` |
| Other relief | only for employees in an `hr.payroll.tax.exemption`: gross − tax / 0.196 (0.20 for non pension members) |
| Date | `paid_date` (written by both pay wizards with the real payment date) |
| Rate | 20 |
| Category / residency | category from the work contact, else 1.1 with a warning; residency = the work contact's `country_id`, else the nationality on the employee version, else Georgia with a warning; the file gets `res.country.rs_form30_code` (2026-09-13: the `rs.form30.country` classifier, the partner residency field and the nationality sync were removed) |

Payroll data is read with `sudo()` because the accountant filing the declaration normally has no payroll access.

**Payments** (`account.payment.withholding.line` of outbound payments in state `in_process`/`paid`, payment date in the month). One row per withholding line: gross = `base_amount`, tax = `amount`, both converted to company currency at the payment date; income type = the withholding tax's Form 30 income type; rate = `abs(tax.amount)`; category from the partner, residency = the partner's `country_id`. Canceled payments are excluded because their withholding lines survive cancellation.

**Manual rows**: anything else (partnership shares, treaty relief columns, corrections). The model supports them (`source = manual`, kept on regenerate, `_onchange_partner_id` fills identity, category and residency), but the current form gives no way to create or edit them: the lines grid is read-only and there is no line menu or action. Today they can only be created through the ORM or an import (§8).

## 4. Validation: matrix at creation, completeness at export

**Matrix (constraint on the line, 19.0.1.7.0):** classifiers valid for the declaration period, (category, income type) pair present in the matrix, rate among the pair's allowed rates for the period. A line that fails is never stored: Generate Lines aborts as a whole with one error naming every offending payslip or payment, hand-made or imported lines are refused the same way, and changing the declaration month re-checks the existing lines. "Inactive" here means outside the validity period taken from the rs.ge notes; the classifiers' `active` flag is a local archive switch and is not part of the check.

**Completeness (export only):** ID number present (9 or 11 digits when residency is Georgia); residency, category, income type, date present; date inside the month; amount positive. Errors are listed together in one message, nothing is exported until they are fixed.

## 5. Classifiers = data

Three models loaded from `30_data_7_202505.xlsx` (v7): 18 categories, 15 income types, 152 rate rules (the 127 matrix cells normalized to one rule per rate, with `valid_from`/`valid_to` in YYYYMM for the dated notes such as type 18 ending 202411 or salary 12% from 202412). Editable under Accounting > Configuration > rs.ge Form 30 by account managers. Country codes are no longer a classifier: `res.country.rs_form30_code` (Char on the core model, `data/res.country.csv` with `id = base.xx`) holds the rs.ge code for 235 of Odoo's 251 countries; the generator prints the 27 rs.ge codes that have no Odoo country (000 ევროპა, 999 უცნობი, historic states) and does not ship them.

## 6. File format

Excel 2003 SpreadsheetML, worksheet `data`, one header row, 14 columns read by position, every cell `ss:Type="String"`, dates `DD.MM.YYYY`, decimals with a dot, treasury column `1` or blank. Header texts copied from the portal template of 2025-11-05.

Verified 2026-09-03 against the three rs.ge source files (`~/Downloads`, all downloaded 2026-09-01 during planning):

| File | What it is | Result |
|---|---|---|
| `temp_30_3017_3_1.rar` → `temp_30_3017_3_1.xml` | the portal's 14-column import template ("ნიმუში", last saved 2025-11-05), sample row + red note "1 = paid from treasury, otherwise leave blank" | our 14 headers are identical after trimming (four template headers carry a trailing space); same `Table ss:StyleID` with text format `@` |
| `Export.xml` | the portal's own annex export: 16 columns = the 14 import columns plus **pension (col 9)** and **withheld tax (col 13)** inserted; three headers worded differently (`სხვა შეღავათი` singular, treaty column without "ან შემცირებას" and with "(ლარი)", foreign-tax column with "/ შესამცირებელი საშემოსავლო გადასახადი (ლარი)"); empty treasury cell exported as one space | any compare-import must map by position (1-8, 10-12, 14-16), not by header text; the space-for-empty convention of `_build_xml` matches the portal |
| `30_data_7_202505.xlsx` | classifier workbook v7 (4 sheets: კატეგორია 18, განაცემის სახე 15, ქვეყნები 262, განაკვეთები 127 cells) | the four CSVs are identical to it: names, display codes, 152 expanded (category, type, rate) cells, validity notes; special country codes present: `000` ევროპა, `536` გაყოფილი ზონა, `896` მულტისავალუტო, `899` განას რესპ., `900` ამაღლების კუნძული, `999` უცნობი |

The export row in `Export.xml` (250 GEL salary row, rate 0, tax 0, pension 0) predates the module and was typed into the portal grid; it is not a round-trip result. The real round trip (upload our file, export, compare) is still the open portal probe of §8.

## 7. Configuration touch points

| Model | Field | Set by |
|---|---|---|
| `res.partner` | `rs_form30_category_history_ids` → `rs.form30.partner.category` (category + inclusive Valid From / Valid To, periods must not overlap) | accountant, per contact. A row takes the history entry covering its payment date (`paid_date` for salary rows, `payment.date` for payment rows), resolved by [`_rs_form30_category_on`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/res_partner.py). **Valid From defaults to today** ([`rs_form30_partner_category.py`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_partner_category.py)): for a first entry clear it (empty = always applied) or backdate it before the declared month, otherwise every past payment resolves to no category, generation stores a blank category with the warning "No Form 30 category covers the payment date" and export fails with "missing category". The form's computed "Current Form 30 Category" is evaluated for today and does not reveal such a gap |
| `res.partner` | `rs_form30_category_id` (legacy single category, label "Category Without History") | used only while the contact has no history entry, hidden on the form once history exists, so a history entry silently overrides it. hr3 example: Abigail Carter held 3.4; a history line created with the first dropdown option 1.1 then failed her 5% royalty rows against the matrix (1.1 + royalty allows 20% only, 1.2.1 has no royalty cell, 3.4 allows 5%) |
| `res.partner` | `country_id` (standard Country) | residency. Each `res.country` carries `rs_form30_code` (235 of 251, `data/res.country.csv`); a country without a code blocks the export with "X has no rs.ge country code" |
| `account.tax` | `rs_form30_income_type_id` | data `<function>` tag on every install/update for the 15 `gec_l10n_ge_tax` withholding taxes (only where empty); manually for taxes created in the UI |
| `hr.version` | `identification_id` | HR, mandatory for every employee row |
| `hr.version` | `country_id` (Nationality) | HR; used as residency only when the work contact has no country (the 19.0.1.9.0 two-way sync was removed 2026-09-13) |

## 8. Limitations and open items

- **History Valid From default removed 2026-09-13** (was today, 19.0.1.10.0; reproduced on hr3 2026-09-05 with three blank rows). Empty Valid From = always applied; the strict resolver is unchanged.
- **Residency ↔ category cross-check is a warning** (2026-09-13, `_recipient_classification`): 3.x with code 268, or 1.x/2 with a foreign code, gets "Residency and category disagree"; category 4 is skipped; export is not blocked. Until then hr3's Abigail Carter (268 + 3.4) passed silently.
- Portal probe still pending: pension and tax are computed by rs.ge, so the row math must be confirmed once with a draft declaration under a company registered in the pension e-system (see the plan's V2 and the slip 66 example, where payroll's PIT and a full-pension-deduction formula differ by 24 GEL for an exempt employee).
- Relief is derived, not stored; rows of exempt employees carry a warning and are meant to be checked.
- Rows of payments whose method has no journal entry are flagged, since the withholding is not booked.
- Foreign-currency payments need an exchange rate for the payment date; no rate fetching is included.
- One declaration per company and month; amendments regenerate and re-upload the full annex.
- **Manual rows and row edits have no UI path** since the grid became read-only (19.0.1.4.0): the form sets `line_ids` `readonly="1"` with `create/edit/delete="0"` on the sub-list and no `rs.form30.line` action exists, `_onchange_partner_id` is unreachable from the UI. Both READMEs describe this limitation (rewritten 2026-09-05; `README_USER.md` was folded into `README.md`). Either an editable mode / line action is added or manual rows stay import-only.
- Tests exist ([`test_form30.py`](../custom_addons/gec_odoo_modules/gec_income_tax_report/tests/test_form30.py)); no run result is recorded, and an installed module does not prove the suite passed.

## 9. Lines grid (`rs_form30_grid`), translation, tests

The Lines tab renders `line_ids` with a custom OWL field widget ([`rs_form30_grid.js`](../custom_addons/gec_odoo_modules/gec_income_tax_report/static/src/components/rs_form30_grid/rs_form30_grid.js)) that extends `X2ManyField` and replaces the list renderer with a fixed 16-column worktable laid out like the rs.ge annex (grouped headers: recipient name, payment, reliefs). Cells go through the standard `Field` component in readonly mode; the sub-list arch in the form view only tells the widget which fields to load.

| Feature | Behaviour |
|---|---|
| Filter row | text search per column; dropdowns for residency, category, income type (options built from the loaded page); Yes/No for treasury; date picker for the payment date. Client-side only, never sent to the server |
| Column widths | auto-fit to the container (ResizeObserver), drag handles per column, "Fit Columns" resets |
| Totals row | sums of the **visible rows of the current page** (page size 100), so they differ from the declaration totals in the header group when filters or paging apply |
| Row marker | № + source dot (payslip / payment / manual) + warning icon whose tooltip is the translated warning; warning rows tinted |
| Header stats | row count and the declaration's `warning_count` |

Translation: [`i18n/ka_GE.po`](../custom_addons/gec_odoo_modules/gec_income_tax_report/i18n/ka_GE.po) (161 entries, none empty) covers model strings, Python warnings and the grid template texts. Warnings are stored in canonical English in `warning`; `warning_display` (computed, `depends_context('lang')`) translates them for display, so stored data stays language-independent and regeneration never changes wording.

Tests in `test_form30.py`: `TestForm30Salary` (13 tests on `GeoPayrollCase`: salary row math, work-contact VAT fallback, exempt relief, month filter, manual rows kept, XML golden row, matrix constraint on rate / pair / abolished income type, generation refused for a resident-company work contact, rejected export on a bad ID, helpers, canonical warning), `TestForm30Payments` (register wizard with a withholding line to one payment row and export; the same flow with an employee-category partner and a 5% royalty tax refused at generation), `TestForm30Grid` (`HttpCase.browser_js` on the declaration form). The grid test only proves the widget mounts: its `tbody tr` selector also matches the empty-state row, so it would pass with zero lines rendered.

## 10. Main part (page 5, cells 16–69) — derived since 2026-09-15

Source: [`rs_form30_declaration.py`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py) `_summary_values`, `_ledger_values`, `_sync_summary_lines`, `RsForm30Line._main_part_cells`, `_taxable_base`, `_portal_tax`; layout in [`data/rs.form30.summary.cell.csv`](../custom_addons/gec_odoo_modules/gec_income_tax_report/data/rs.form30.summary.cell.csv). Legal basis: Order 996 art. 38 §6 (instruction of 2026-02-09) and the accountant's formulas workbook `საშემოსავლო ძირითადი ნაწილი.xlsx` (2026-09-15); no portal upload has confirmed the routing.

**Three kinds of cell.** `computed` (44 cells, 16–57 incl. 20¹, 56², 57): rewritten at every Generate and Export, padlock in the grid. `proposed` (57¹, 57², 58, 59, 61, 63, 65–69): typed on the portal, Odoo proposes them and keeps refreshing while `value` still equals `proposed_value` (the last proposal, added 2026-09-17 after the fill-while-empty rule froze 58/61/65/66 on hr3), wand in the grid. Neither (56¹, 60, 62, 64): typed by the accountant, never written.

**Definitions.** Base of an annex A row = `amount − pension_amount − other_relief` (portal col 7 − 8 − 9). Tax = `round(base × rate / 100)` (portal col 12). Organizations = categories with `is_organization` (rs.ge ids 2, 31, 33, 38, 39 = portal 2, 3.1, 3.3, 3.7, 3.8).

| Cells | Rule |
|---|---|
| 16 / 17 | Σ amount / Σ base of income type 1 rows |
| 18 | Σ amount of resident-individual royalty rows; memo, not summed into 39 (the workbook's SUMPRODUCT double-counted it) |
| 19 / 20 / 20¹ | individuals, types 6, 7, 17, 19, 20, by rate 20 / 5 / 3, base; non-resident rate-20 rows also land in 19 (assumption) |
| 21 | individuals, types 5, 16, 21, 22, 23, base |
| 22–25 | dividends / interest to individuals: amount, then base |
| 26 | categories 1.3 and 3.10, base |
| 27–32 / 33–38 | non-resident individuals by art. 134 sub-point (3.2 → 32, 3.6 → 29, 3.5 → 30, royalty at 5 → 28, other 10 % → 31), amount / base; 27 and 33 are sums |
| 39 | Σ tax over individual rows |
| 40–47 / 48–55 | organizations (3.1 → 45, 3.8 → 42, 3.7 → 43, dividends → 46, interest → 47, royalty at 5 → 41, other → 44), amount / base; 40 and 48 are sums |
| 56 | Σ tax over organization rows |
| 56¹ / 56² | typed / 12 % of it |
| 57 | 39 + 56 + 56² + Σ annex D tax − Σ annex A foreign tax credit |
| 57¹ / 57² | Σ tax of salary rows whose `autonomous_republic` (snapshot of `hr.version.work_location_id.rs_form30_autonomous_republic`) is adjara / abkhazia |
| 58 | −Σ posted balance on `account_type = income` accounts in the month (assumption: all income accounts) |
| 59 | tick when a posted `internal_group = expense` line exists in the month (the workbook treated it as an amount) |
| 61 / 65 / 66 | per-person salary totals: count, max, min > 0 |
| 63 | Σ inbound cash-journal payments in the month (assumption) |
| 67 | balance of the cash journals' default accounts at `date_to` |
| 68 / 69 | positive per-partner balances on chart account `account_1431` at `date_to`: sum, count (assumption: 1431 only) |

Refresh triggers: `create()`, `action_generate()`, `action_export()`. Per-row **question-mark button** in the main-part grid (2026-09-17, OWL `explain()` → `rs.form30.explain` transient with `cell_code` + QWeb `main_part_explanation`): `_summary_values(trace)` records every contribution while computing, the page shows for that one cell the formula, the stored value, its kind, the contributing rows or journal items with their arithmetic and source links, and flags a locked cell whose stored value differs from a fresh calculation. 19.0.1.13.0 (2026-09-17) dropped the repeated glossary header and the unreachable all-cells mode (`cell_code` is now required); the only line it carried that had no other home, which categories count as organizations, moved into the `{orgs}` placeholder of the cell 39 and 56 formulas. New fields: `rs.form30.line.autonomous_republic`, `rs.form30.category.is_organization` (CSV column, also emitted by `tools/generate_classifier_csv.py`), `rs.form30.summary.cell.proposed`, `hr.work.location.rs_form30_autonomous_republic` (form inherit on `hr.hr_work_location_form_view`). The export button is now visible when only annex E has rows.

**Explanation workbook (19.0.1.14.0, 2026-09-17, run on hr3 through the shell).** Header button **Explanation Workbook** → [`rs_form30_declaration_xlsx.py`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration_xlsx.py) `RsForm30DeclarationXlsx.action_export_explanation` (second `_inherit` class on the declaration) writes `form30_explained_<period>.xlsx` into the new Binary `explanation_file` and returns an `act_url` download, so the file is both downloaded and kept on the form. One `_summary_values(trace)` call feeds eight xlsxwriter sheets: *Read me* (facts, sheet guide, definitions, organizations by name, the five assumptions), *Annex A* (per row: base, portal tax, withheld tax and their difference, the cells the row feeds, source link, tax or payroll rule, work location, warnings), *Payslips* (payslip-side build of each salary row incl. relief formula and ID / category / residency provenance), *Payments* (payment, bills settled, tax, category on the date and the history entry that gave it, residency, annex A or E and why), *Annex D*, *Annex E*, *Main part* (value, kind, status, formula in words) and *Cell details* (the trace, one block per cell with links). The page helpers `RsForm30Explain._formulas()` and `_cell_state()` were extracted as `@api.model` methods and are shared. Snapshot semantics: stored values, stale cells flagged; every click overwrites the previous file. Texts English, untranslated.

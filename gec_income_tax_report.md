# gec_income_tax_report — rs.ge Form 30 (withholding declaration)

> **Module:** `gec_income_tax_report` 20.0.1.14.0 | **Path:** [`custom_addons/gec_odoo_modules/gec_income_tax_report/`](../custom_addons/gec_odoo_modules/gec_income_tax_report/)
> Verified against Odoo 20 source on 2026-09-24.

## Status on Odoo 20

- **Ported and tested, not installed.** The manifest, OWL 3 grids, icons, `ir.access.csv`, withholding field names, payment states, `_display_address` and the Binary file fields are ported. The module is `uninstalled` on `gec20_prod1` (checked 2026-09-24). On a scratch database (2026-09-24) 32 of its 33 tests pass; the failing one is the next point.
- **Individuals with a Tax ID are exported as companies.** In 20.0 `is_company` is computed: a contact is a company when it is its own commercial entity and has a Tax ID ([res_partner.py:946](../odoo/addons/base/models/res_partner.py#L946)); core commit `f2965048f60f` removed the Person/Company switch, and writing `is_company = False` is recomputed away. `l10n_ge` does not refine it, while 15 other localizations do (e.g. [l10n_uz](../addons/l10n_uz/models/res_partner.py#L8): only a 9-digit TIN is a company). A recipient whose 11-digit personal number is in Tax ID therefore gets an empty first-name column, the full name in the last-name column and the "Legal form not detected" warning, on payment rows, annex E rows and the manual-row onchange, which all split on `is_company` ([`_split_name`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L693)). Salary rows are not affected. `test_payment_row` fails on this. Open decision: a Georgian `_compute_is_company` in `gec_localization` (9-digit ID = organization, 11-digit = person), or splitting by the Form 30 category's `is_organization` in this module.

## What It Does & Why It Exists

Every month a Georgian employer files the "გადახდის წყაროსთან დაკავებული გადასახადის დეკლარაცია" (rs.ge form 30) by the 15th. The portal needs one annex row per recipient and payment: who was paid, which category of recipient, which kind of income, how much, when, at which rate. The portal then computes the withheld tax, the pension 2% and the main-part totals itself.

This module collects those rows from Odoo, checks them against the rs.ge classifier matrix and writes the import files the portal accepts. It builds four pages of the declaration:

| Portal page | What the module does |
|---|---|
| 2. Annex A (payments and withheld tax) | Generated from paid payslips and payment withholding lines; read-only grid; 14-column file |
| 3. Annex D (private use of a company car) | Rows typed by the accountant, pre-filled from the vehicle; 5-column file |
| 4. Annex E (service fees not withheld at source) | Generated from withholding lines of recipients who pay their own tax; 7-column file |
| 5. Main part (cells 16–69) | Derived as a cross-check and as proposals for the typed cells; no file, the accountant copies it |

Page 1 (payer constants) stays on the portal. The module books nothing, sends nothing and runs no cron. The accountant files; payroll and the withholding taxes do the accounting.

---

## The Big Picture — How It Works

```
Accounting > Reporting > Income Tax Declaration (Form 30)
New (month) --> Generate Lines --> review warnings, fix sources, regenerate
            --> Annex D rows by hand --> check main part --> Export rs.ge Files --> upload on eservices.rs.ge
```

| Step | What happens | Source |
|---|---|---|
| New | One declaration per company and month; the month defaults to last month and must start on day 1 | [`RsForm30Declaration`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L98) |
| Generate Lines | Deletes payslip and payment rows and all annex E rows, keeps manual annex A rows and annex D rows, rebuilds from the sources, refreshes the main part | [`action_generate`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L183) |
| Review | Warning rows are tinted; each row links to its payslip or payment | annex A grid |
| Export rs.ge Files | Validates each annex that has rows, stores one file per annex (`form30_a_YYYYMM.xml`, `_d_`, `_e_`), sets state `exported` | [`action_export`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L198) |
| Reset to Draft | Allows regeneration after an amendment | `action_draft` |

Generation reads the database at the click. Late data appears only at the next Generate. Everything runs in one transaction: a refused row rolls back the deletion too.

### Key Decision Points

- **Category of the recipient:** the contact's category history, resolved on the payment date. It decides which rates are allowed.
- **Income type and rate:** the withholding tax used on the payment. One tax per income type; never reuse a tax because the rate matches.
- **Residency:** the contact's standard Country; each `res.country` carries its rs.ge code.
- **Annex A or annex E:** the contact flags **Individual Entrepreneur** or **Small Business Status** move that contact's withholding rows to annex E.
- **Cells 57¹ / 57²:** the work location flag Adjara / Abkhazia on the employee's version.

---

## When to Use It (and When Not To)

### This module is for:
- A Georgian company paying salaries through `geo_payroll` and withheld income (dividends, interest, royalties, rent, services, stipends, non-resident fees) through Odoo payments with withholding lines.
- The monthly filing, and its amendments, on eservices.rs.ge.

### Use something else when:
- VAT declaration: `l10n_ge`'s VAT report, see [`l10n_ge.md`](l10n_ge.md).
- Profit distribution and CIT: the `gec_localization` CIT wizard. Its "Withhold Dividend Tax (5%)" books journal lines that Form 30 never sees ([cit_wizard.py:35](../custom_addons/gec_odoo_modules/gec_localization/wizards/cit_wizard.py#L35)); see the dividend rule under Design decisions.
- Pension payments to the agency: `geo_payroll` / `gec_payroll_bank`.

---

## Real-World Scenarios

### Scenario 1: September salaries paid on 5 October
**Situation:** payroll runs September payslips; the accountant pays them with Pay Salaries (`gec_payroll_bank`) on 5 October.
**What they do:** early November, create the October declaration and press Generate Lines.
**What happens:** each slip marked paid with `paid_date` in October gives one row (income type 1, rate 20). The rows belong to October because Form 30 is cash basis.

### Scenario 2: Royalty to a resident individual
**Situation:** a bill carries the tax "WHT 20% - Resident Individual Royalties" on its line.
**What they do:** Register Payment. The wizard defaults to **Withhold and Pay** and proposes the withholding line from the bill ([`_get_default_withhold`](../addons/l10n_account_withholding_tax/wizards/account_payment_register.py#L72)).
**What happens:** the payment's withholding line becomes an annex A row: income type 17 from the tax, rate 20, category from the contact on the payment date, amount converted to GEL at the payment date.

### Scenario 3: Service fee to a registered sole trader
**Situation:** the contact is ticked **Individual Entrepreneur (ი/მ)**, and the payment still carried a withholding line.
**What happens:** the row goes to annex E, with the service type set on the tax. A payment without a withholding line never reaches annex E; the accountant adds such fees on the portal.

### Scenario 4: Company car used privately
**What they do:** Annex D tab, Add a line, pick the vehicle. Plate, engine band and driver fill in; the employee fills the name and personal number.
**What happens:** the tax amount follows the band (e.g. 100 GEL under 2,500 cm3) and is added to cell 57. Generate Lines never touches these rows.

---

## How Things Work Under the Hood

### Annex A — salary rows ([`_salary_line_vals`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L246))

One row per `hr.payslip` of the company in state `paid`, not a credit note, `paid_date` in the month. Payroll is read with `sudo()`, because the accountant filing the declaration usually has no payroll access.

| Column | Value |
|---|---|
| Gross amount | `GROSS` line + Σ `ADVANCE_PAY` inputs; slips with amount ≤ 0 are skipped |
| Withheld tax (control) | `−PIT` + `ADV_PIT_PRE` |
| Pension (control) | `−PENSION_EE` + `ADV_PEE_PRE` |
| Other relief (col. 9) | employees in any `hr.payroll.tax.exemption` only: `amount − tax / 0.196` (`0.20` for non-members of the pension scheme), with a warning |
| Date | `paid_date` |
| Rate | always 20 |
| ID | `version.identification_id`; else the work contact's Tax ID, with a warning |
| Name / address | `legal_name` split into first / last name; the version's private street and city |
| Category / residency | work contact's category on `paid_date`; a contact with no category at all gets 1.1 with a warning, a gap in its history leaves the row empty. Residency = work contact country, else the version's Nationality, else Georgia with a warning |

Further warnings: no payment matched on the slip's journal entry, and `edited` slips. Rule codes come from `geo_payroll` ([payroll_structure_data.xml:224](../custom_addons/gec_odoo_modules/geo_payroll/data/payroll_structure_data.xml#L224), [payroll_benefit_data.xml:56](../custom_addons/gec_odoo_modules/geo_payroll/data/payroll_benefit_data.xml#L56)).

`paid_date` is written with the real bank date by Pay Salaries ([gec_payroll_bank hr_payslip.py:408](../custom_addons/gec_odoo_modules/gec_payroll_bank/models/hr_payslip.py#L408)) and by Register Payment on the payroll entry ([geo_payroll account_payment_register.py:24](../custom_addons/gec_odoo_modules/geo_payroll/models/account_payment_register.py#L24)). Core **Mark as Paid** writes today, but only on slips with no `paid_date` yet ([hr_payslip.py:1062](../enterprise/hr_payroll/models/hr_payslip.py#L1062)).

### Annex A — payment rows ([`_payment_line_vals`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L324))

One row per `account.payment.withholding.line` of an outbound payment of the company dated in the month, in state `paid` (posted) or `reconciled` (matched with the statement, or all its bills paid; [`_compute_state`](../addons/account/models/account_payment.py#L496)). Draft, canceled and rejected payments stay out, because their withholding lines survive cancellation.

| Column | Value |
|---|---|
| Gross amount / tax (control) | `base_amount` / `amount`, converted from the payment currency at the payment date |
| Income type | the tax's **Form 30 Income Type** |
| Rate | `abs(tax.amount)` for percent taxes, else 0 with a warning |
| Date | payment date |
| ID / name / address | contact Tax ID without spaces or a two-letter prefix (`GE01008057135` → `01008057135`); company names split into legal form + name |
| Category / residency | contact category on the payment date and contact country; missing values warn and block the export |

Warnings: tax without income type, non-percent tax, payment without journal entry (the withholding is not booked), company name without a known legal form. A tax whose Form 30 validity (set by the change wizard) excludes the payment date stops the generation ([`_rs_form30_check_payment_date`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/account_tax.py#L59)).

**Treaty allowance (col. 12).** A contact can carry **Tax Exempt Under International Agreement**. Each new row draws its withheld tax from that allowance into column 12 and logs the draw in `rs.form30.exempt.usage` ([`_rs_form30_draw_exempt`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L639)). The allowance is per person, shared across companies. Column 12 is a disclosure: it does not reduce cell 57.

**Manual rows** (`source = manual`) survive regeneration, but the form offers no way to create or edit them: the annex A list is read-only and no `rs.form30.line` action exists. Today they can only come from code or an import.

### Annex E — service rows ([`_service_line_vals`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L368))

Same withholding lines, but only those whose contact is flagged individual entrepreneur or small business ([`_rs_form30_pays_own_tax`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/res_partner.py#L61)). Values: ID, names, address, country, the tax's **Form 30 Service Type** (8 portal kinds), base amount in GEL. Export needs ID, service type and a residency with an rs.ge code.

### Annex D — car rows ([`rs_form30_car.py`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_car.py#L14))

Typed in the grid. Picking a vehicle fills the plate, the vehicle's **rs.ge Engine Band** and the `hr_fleet` driver employee; the employee fills "Surname,Name" and the personal number. The tax amount is the band amount: over 3,500 cm3 300, 2,500–3,500 200, under 2,500 100, hybrid 60 (`data/rs.form30.car.engine.csv`, editable). Export needs plate, name and a 9- or 11-digit personal number. The file carries the band **number** (1–4), not the volume.

### Validation: matrix at creation, completeness at export

- **Matrix** ([`_check_matrix`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L801), a constraint): category and income type valid in the declaration period, the pair present in the rate matrix, the rate among the pair's allowed rates for the period. A failing line is never stored: Generate Lines aborts as a whole and names every offending payslip or payment. Changing the declaration month re-checks existing lines. The classifiers' `active` flag is not part of the check.
- **Completeness** ([`_validation_errors`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L818), export only): ID, residency, category, income type and date present; residency has an rs.ge code; a Georgian ID has 9 or 11 digits; the date inside the month; amount positive. All errors are listed at once (first 40).

### Classifiers = data

| Data | Content |
|---|---|
| `rs.form30.category` | 18 recipient categories; classifier ID ≠ portal number (ID `4` = "1.1", ID `42` = "4"); `is_organization` marks 2, 3.1, 3.3, 3.7, 3.8 |
| `rs.form30.income.type` | 15 income types; type 18 valid to 202411 |
| `rs.form30.rate.rule` | 152 rules = one per (category, type, rate) with YYYYMM validity, from the v7 workbook `30_data_7_202505.xlsx` |
| `res.country.rs_form30_code` | rs.ge code for 235 countries (Georgia = 268); rs.ge codes without an Odoo country (000 Europe, 999 unknown, historic states) are not shipped |
| `rs.form30.car.engine`, `rs.form30.service.type` | 4 engine bands, 8 service types |
| `rs.form30.summary.cell` | 60 main-part rows |

Accounting Administrators edit them under Accounting > Configuration > rs.ge Form 30 (Advanced). A manual edit of a rate rule sets its xmlid to `noupdate`, so later CSV reloads keep it ([rs_form30_classifier.py:91](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_classifier.py#L91)). Country codes load through a data function, because base ships country xmlids as `noupdate` and a CSV row would be skipped on upgrade ([`_rs_form30_load_codes`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/res_country.py#L15)). `tools/generate_classifier_csv.py` rebuilds the CSVs from a new rs.ge workbook.

### Export files ([`_build_xml`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L570))

Excel 2003 SpreadsheetML, worksheet `data`, one header row, every cell `ss:Type="String"`, dates `DD.MM.YYYY`, decimals with a dot, empty cells written as one space (as the portal's own export does). Annex A has the 14 portal import columns; the portal screen shows 16, because it adds pension and tax. Annex E follows the portal import order, which puts service type and amount before address and residency.

### Main part (cells 16–69)

[`_summary_values`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L417) derives every cell from the annex rows and the ledger; [`_sync_summary_lines`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L518) stores them at create, Generate and Export.

| Kind | Cells | Refresh |
|---|---|---|
| Computed (padlock) | 44 cells, 16–57 incl. 20¹, 56² | always overwritten; the portal computes them too, so they are a cross-check |
| Proposed (wand) | 57¹, 57², 58, 59, 61, 63, 65–69 | Odoo refreshes the value while it still equals the last proposal (`proposed_value`); a typed value stays. Cell 59 is a checkbox and is always overwritten |
| Typed | 56¹, 60, 62, 64 | never touched |

Definitions: base of a row = amount − pension − other relief (portal col. 7 − 8 − 9); tax = round(base × rate / 100) (portal col. 12). Routing ([`_main_part_cells`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L740)):

| Cells | Rule |
|---|---|
| 16 / 17 | Σ amount / Σ base of income type 1 rows |
| 18 | Σ amount of royalty rows to resident individuals; memo, not summed into 39 |
| 19 / 20 / 20¹ | individuals, types 6, 7, 17, 19, 20 by rate 20 / 5 / 3, base; non-resident rows at 20 also land in 19 |
| 21 | individuals, types 5, 16, 21, 22, 23, base |
| 22–25 | dividends / interest to individuals: amount, then base |
| 26 | categories 1.3 and 3.10, base |
| 27–32 / 33–38 | non-resident individuals: 3.2 → 32, 3.6 → 29, 3.5 → 30, royalty at 5 → 28, other → 31; amount / base; 27 and 33 are sums |
| 39 | Σ tax of individual rows |
| 40–47 / 48–55 | organizations: 3.1 → 45, 3.8 → 42, 3.7 → 43, dividends → 46, interest → 47, royalty at 5 → 41, other → 44; amount / base; 40 and 48 are sums |
| 56 / 56² | Σ tax of organization rows / 12% of typed 56¹ |
| 57 | 39 + 56 + 56² + Σ annex D tax − Σ annex A foreign tax credit (Order 996 art. 38) |
| 57¹ / 57² | Σ tax of salary rows whose `autonomous_republic` is Adjara / Abkhazia |
| 58 | −Σ posted balance on `income` accounts in the month |
| 59 | ticked when a posted expense line exists in the month |
| 61 / 65 / 66 | salary persons: count, highest total, lowest total above zero |
| 63 | Σ inbound payments on cash journals in the month |
| 67 | balance of the cash journals' default accounts at month end |
| 68 / 69 | positive per-partner balances on 140311 "Settlements with Accountable Persons" (`gec_account_140311`) at month end: sum, count |

Assumptions not yet confirmed by a portal upload: 58 takes every income account, 63 every cash-journal receipt, 68/69 only 140311, non-resident rate-20 rows in 19.

**Question-mark button** per main-part row: opens `rs.form30.explain` with the formula, the stored value, its kind, every contributing row or journal item with its arithmetic and link, and flags a computed cell whose stored value differs from a fresh calculation ([rs_form30_explain.py:73](../custom_addons/gec_odoo_modules/gec_income_tax_report/wizard/rs_form30_explain.py#L73)).

**Explanation Workbook** (header button): one `_summary_values(trace)` call writes `form30_explained_<period>.xlsx` with eight sheets (Read me, Annex A, Payslips, Payments, Annex D, Annex E, Main part, Cell details), stores it on the declaration and downloads it ([`action_export_explanation`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration_xlsx.py#L39)). It is a snapshot; every click overwrites it.

### Tax / RS change wizard

Accounting Administrators only, from the tax form's **RS Declaration Rules** tab ([rs_form30_tax_change.py:130](../custom_addons/gec_odoo_modules/gec_income_tax_report/wizard/rs_form30_tax_change.py#L130)). For a dated law change it can copy the tax with a new rate and close the old one the day before (`rs_form30_date_from` / `_to`, `rs_form30_previous_tax_id`), and end or start rate rules from the effective month. Rules are shared by every company and tax with that income type. It never changes the payroll salary rate.

### Screens, translation, tests

- Grids are OWL 3 field widgets extending `X2ManyField` ([rs_form30_grid.js:70](../custom_addons/gec_odoo_modules/gec_income_tax_report/static/src/components/rs_form30_grid/rs_form30_grid.js#L70)): column filters and totals apply to the **current page** (100 rows), column widths auto-fit and drag, warning rows tinted, light and dark theme.
- `i18n/ka_GE.po` translates 326 strings (form, grids, warnings, wizard). Not translated: the explanation formulas, the workbook, and the work-location field. Warnings are stored in English and translated at display (`warning_display`), so regeneration never changes stored text.
- Tests: 33 methods in [`test_form30.py`](../custom_addons/gec_odoo_modules/gec_income_tax_report/tests/test_form30.py) (salary, payments, grid) and [`test_tax_configuration.py`](../custom_addons/gec_odoo_modules/gec_income_tax_report/tests/test_tax_configuration.py) (change wizard, category history). On 20: 32 pass, `test_payment_row` fails on `is_company` (see Status). The grid test's `tbody tr` selector also matches the empty-state row, so it passes with zero lines.

---

## Configuration & Settings

| Where | Field | What it changes |
|---|---|---|
| Contact > Sales & Purchase > rs.ge Form 30 | **Form 30 Category History** (category, inclusive Valid From / Valid To, no overlap) | The category of every row paid on a date inside the period. Empty Valid From = always applied. Once history exists it replaces the legacy **Category Without History**, and a gap leaves the row without category (export blocked) |
| same | **Individual Entrepreneur** / **Small Business Status** | Moves the contact's withholding rows from annex A to annex E |
| same | **Tax Exempt Under International Agreement** | Treaty allowance drawn into column 12; **Usage** lists every draw |
| Contact > Country | standard `country_id` | Residency; a country without rs.ge code blocks the export |
| Accounting > Configuration > Taxes > a withholding tax | **Form 30 Income Type**, **Form 30 Service Type** | Income type of annex A rows / service kind of annex E rows. Filled on install and update for 18 of the 23 `gec_localization` withholding taxes ([`GE_TAX_INCOME_TYPES`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/account_tax.py#L4)) where still empty; service type always by hand |
| Employees > Configuration > Work Locations | **Form 30 Autonomous Republic** | Feeds 57¹ / 57² with the tax of salary rows at that location |
| Fleet > Vehicle | **rs.ge Engine Band** | Pre-fills the band of annex D rows |
| Employee (version) | Identification No, Nationality | Salary row ID; Nationality is the residency fallback |

Not mapped to an income type on install: "WHT 20% - Gift to Individual", "WHT 3% - Goods from Individual without Waybill", "WHT 10% - Non-resident Other GE-source Income", "WHT 10% - Non-resident Int'l Telecom/Transport", "WHT 4% - Non-resident Oil & Gas Subcontractor" ([account.tax-ge.csv](../custom_addons/gec_odoo_modules/gec_localization/data/template/account.tax-ge.csv)). Their rows warn and cannot be exported until the income type is set.

Income types by source: 1 from payslips (and from the "WHT 20% - Salary (PIT)" / "Non-resident Employment" taxes when salary is paid outside payroll); 2, 3, 5, 7, 17, 19 from the mapped taxes; 6 only once the gift, goods or non-resident other tax gets its income type; 16, 20, 21–24 have no tax and need manual rows. Type 18 is valid only to 202411.

Access ([ir.access.csv](../custom_addons/gec_odoo_modules/gec_income_tax_report/security/ir.access.csv)): read-only accounting users see declarations; users with full accounting features (`account.group_account_user`) create, generate and export; Accounting Administrators edit classifiers and run the change wizard. Declarations and all line models carry a company restriction row.

---

## Dependencies

| Requires | Why |
|---|---|
| `geo_payroll` | Payslips, rule codes `GROSS`, `PIT`, `PENSION_EE`, `ADV_PIT_PRE`, `ADV_PEE_PRE`, input `ADVANCE_PAY`, the tax exemption model, `pension_fund_member` |
| `gec_localization` | The Georgian withholding taxes (on top of core `l10n_ge`, see [`l10n_ge.md`](l10n_ge.md)) and account 140311 |
| `l10n_account_withholding_tax` | `account.payment.withholding.line`, `account.tax.is_withholding_tax` |
| `hr_fleet` | Vehicles with a driver employee for annex D |

| Works With (not a dependency) | What It Adds |
|---|---|
| `gec_payroll_bank` | Pay Salaries writes the real `paid_date` |
| `basis_bank` | Sends `payment.amount`, which is the **gross** on a withholding payment ([account_payment.py:255](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L255)); execute withholding payments outside the Basis send flow |
| `nbg_rates` | Fetches only EUR and USD ([nbg_rates.py:12](../custom_addons/gec_odoo_modules/nbg_rates/models/nbg_rates.py#L12)); other currencies need a manual rate for the payment date |

---

## Design Decisions and Why

| Decision | Reason |
|---|---|
| Rows come from payslips and withholding lines, never from tax grids, GL balances or `account.return` | Form 30 is per person, per payment, cash basis. Grids and balances have no person or date. Payroll income tax is a salary rule posting to 331320, not an `account.tax`. 331210 collects the resident withholding taxes of all recipients, so a balance cannot be split per person. `account.return` is an aggregate filing card |
| Category on the contact, income type on the tax | A category describes the recipient; the income type describes the payment. One person can receive salary, dividends and royalties. Rule: one tax per (income type, rate, residency) actually used, named by substance |
| Category and residency are set by a person | No Odoo field proves tax residency: the version's Country is nationality, the private country is an address, the 183-day rule lives outside the system. Salary rows default to 1.1 / Georgia with a warning; payment rows block the export. Offshore categories 3.1 / 3.2 are always set by hand: there is no offshore-country list |
| Salary month = payment month; one row per payment event | Cash basis matches the portal's payment date. One row per paid payslip (an advance paid on another date keeps its own row) and one per withholding line |
| Salary math never adds `REPAY_*` lines | Advance repayments are balance-sheet closings; the advance was declared when paid (`ADVANCE_PAY`), and the repayment month's `GROSS` is already reduced by the `ADVANCE` rule. `BONUS` is inside `GROSS`; `BENEFIT_DED` is a post-tax deduction and not declared. Signs: withheld = (−PIT) + ADV_PIT_PRE, never −(PIT + ADV_PIT_PRE) |
| Payment amounts converted from the withholding line, not read from its journal item | The withholding line has no link to its journal item, and lines with the same tax merge into one item |
| Rate = `abs(tax.amount)` | Base and withheld amount are both editable on the line; tax / base is not a reliable rate |
| Dividends: withhold on the payout payment | The CIT wizard's own dividend WHT books plain journal lines, invisible to Form 30. Leave it off and pay the dividend with the 5% dividend withholding tax |
| No 0% withholding tax for treaty cases | In 20.0 a 0% withholding tax keeps its flag ([account_tax.py:40](../addons/l10n_account_withholding_tax/models/account_tax.py#L40)), but the matrix allows rate 0 only for salary and gambling payouts, so its rows are refused. Use the treaty allowance (col. 12) |
| New withholding taxes live in `gec_localization` | Its maintenance pass creates missing template records per company and never rewrites existing ones ([template_ge.py:36](../custom_addons/gec_odoo_modules/gec_localization/models/template_ge.py#L36)); this module only maps the income type |
| Country codes on `res.country` | The Form 30 classifier sheet is the authority for the residency column, so the module ships its own codes and needs no other registry module |
| File import, no API | No rs.ge submission API for Form 30 was identified [Unverified]; the portal's "ატვირთვა ფაილიდან" takes the SpreadsheetML file |
| Names are split, not stored | Individuals: first token = first name, rest = last name. Companies: a known legal form (შპს, სს, ი/მ …) goes to column 2 |

---

## Gotchas & Non-Obvious Behavior

- **Individuals with a Tax ID are split as companies** on 20: see Status.
- **Register Payment carries withholding only in edit mode.** The payment gets withholding lines only when the selected bills form one batch (same vendor, account, currency, bank account) and there is one bill line or **Group Payments** is ticked ([account_payment_register.py:1312](../addons/account/wizard/account_payment_register.py#L1312)); only the wizard path copies them ([`_create_payment_vals_from_wizard`](../addons/l10n_account_withholding_tax/wizards/account_payment_register.py#L281)). Several bills with Group Payments unticked lose the withholding: no row.
- **Withhold Only** payments (`withhold = 'withhold'`) have no bank line; the tax is booked, the net is paid later ([account_payment.py:131](../addons/l10n_account_withholding_tax/models/account_payment.py#L131)). Their withholding lines give rows dated on that payment, not on the later net payment.
- **Edited payslips warn forever.** Any inline line edit sets `hr.payslip.edited` and nothing clears it ([hr_payslip.py:173](../enterprise/hr_payroll/models/hr_payslip.py#L173)), so the "Payslip lines were edited manually" warning stays for that slip.
- **Relief is derived, not stored.** The inversion assumes payroll's PIT = (taxable − 2% of taxable) × 20%. The portal computes (gross − 2% of gross − relief) × 20%, so for an exempt employee payroll withholds 0.4% of the relief more than the portal expects (24 GEL on 6,000 relief). With a vendor benefit company share (`BIK`), payroll takes pension on `GROSS − BIK` ([payroll_structure_data.xml:212](../custom_addons/gec_odoo_modules/geo_payroll/data/payroll_structure_data.xml#L212)) while the portal takes 2% of column 7. Details: [`rs_form30_full_declaration_gap_plan.md`](rs_form30_full_declaration_gap_plan.md) §4.
- **Relief follows today's data.** `pension_fund_member` sits on the employee, not the version, so regenerating an old month uses today's flag. The art. 82 exemption is pooled per person (no company on `hr.payroll.tax.exemption`) and consumed by payslip year, while rows follow the payment date: a December salary paid in January used the old year's cap.
- **Do not reconcile Form 30 with the month's ledger movement** on 331210 / 331310 / 331320. Payslip entries are dated by accrual, the declaration by payment: a September slip paid in October sits in September's ledger and October's declaration.
- **A payment that exists only as a bank statement line** (money sent from internet banking) has no withholding line and gives no row. Partial payments of a bill withhold on a proportional base; each payment gives its own row.
- **The column layout is hard-coded** (`HEADERS`). Before the first live filing, download the portal sample ("ნიმუში") and compare the 14 columns.
- **Salary rate is always 20.** The matrix also allows 0, 5, 10 and 12 for employees; such cases need other rows.
- **Annex E sees only withheld payments.** Fees correctly paid without withholding do not reach annex E.
- **Totals in the grid footer** cover the visible page only; the header totals cover the declaration. `Total Pension 2%` is the employee share only.
- **One declaration per company and month.** An amendment regenerates and re-uploads the full annex; on the portal delete the uploaded rows first, because a second import adds duplicates.
- **Classifier drift:** rs.ge re-versions the classifiers about once a year. Rules carry validity periods, so old months still validate with their own rules; a new combination is refused until the CSVs are reloaded.
- **Portal probe still open:** the row math has never been compared with a portal-computed draft under a company registered in the pension e-system.

---

## Related Docs

- [`INDEX.md`](INDEX.md)
- [`rs_form30_full_declaration_gap_plan.md`](rs_form30_full_declaration_gap_plan.md) — the full declaration (pages 1–6) against Order 996 art. 38, open decisions for the accountant
- [`l10n_ge.md`](l10n_ge.md) — Georgian chart, taxes and VAT report (`l10n_ge` + `gec_localization`)
- [`geo_payroll.md`](geo_payroll.md) — the payslip side (PIT, pension, exemptions, advances)
- Module guides: [`README.md`](../custom_addons/gec_odoo_modules/gec_income_tax_report/README.md) (accountant), [`README_DEV.md`](../custom_addons/gec_odoo_modules/gec_income_tax_report/README_DEV.md) (developer)
- Domain reference: [`sashemosavlo_deklaraciebi_sruli_cnobari.md`](../sashemosavlo_deklaraciebi_sruli_cnobari.md) — form rules, classifiers, penalties

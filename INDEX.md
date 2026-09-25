# Documentation Index

> Internal knowledge base for the Odoo 20 project, built from the 20.0 source in `../addons/`, `../enterprise/` and
> `../custom_addons/`. Every fact links to the source line it comes from.
> Odoo 19 versions of every file stay on the `19.0` branch of this repo: `git -C documentations show 19.0:<file>`.

## How to use

- Start with the module's doc before reading code. One file covers one module or one cross-module topic.
- **Status** says how far a file can be trusted on 20.0:
  - **20** (date): checked against the 20.0 source on that date; no Odoo 19 content.
  - **20 + 19 notes** (date): checked against 20.0 on that date, but it still carries Odoo 19 comparisons, and its line
    links may have drifted since the source was pulled.
  - **19**: written for Odoo 19 and not reviewed for 20. Verify before relying on it.
- New and updated docs follow [`doc-template.md`](../.claude/skills/odoo-dev/references/doc-template.md). Add or update the
  row here in the same change.
- Check a doc's source links with `python3 .claude/skills/odoo-dev/scripts/doc_link_check.py documentations/<file>.md`
  (run from the project root). It reports missing files, modules deleted in 20.0, lines past the end of a file, and links
  whose target line no longer holds the named symbol.
- Verified Odoo 19 to 20 code changes live in [`v20-changes.md`](../.claude/skills/odoo-dev/references/v20-changes.md),
  not in these docs.

---

## Accounting

| Topic | File | What it covers | Status |
|---|---|---|---|
| Chart of accounts | [`accounting_coa.md`](accounting_coa.md) | Account types, the `parent_id` tree (no account groups), `compute_sql` fields, company-dependent codes, tags, opening balances, chart template loading, company-level defaults, the category-account cascade, inventory variation closing in core `account`. | 20 (2026-09-24) |
| Taxes | [`taxes.md`](taxes.md) | The `account.tax` engine: computation types, price-included taxes, repartition lines and tax grids, tax groups and totals, fiscal positions, product and company defaults, cash basis, tax closing, reports, sale/purchase/POS flows, FAQ. | 20 + 19 notes (2026-09-22, cleanup started 2026-09-24) |
| Tax, account and move constraints | [`odoo_tax_account_constraints.md`](odoo_tax_account_constraints.md) | 158 validations that can block chart loading, tax saving or posting, each with trigger, error text, source line and how to avoid it. | 19 |
| Reporting engine | [`accounting_reports.md`](accounting_reports.md) | Report expression engines and formulas, aggregation bounds, currency consolidation, account hierarchy, report lines and columns, snapshots, Balance Sheet and P&L structures, Trial Balance, Interco Comparison, report options. | 20 + 19 notes (2026-09-22) |
| Tax returns and locking | [`account_returns.md`](account_returns.md) | `account.return`: filing cards per period and type, check templates, `action_validate()` posting the closing entry and advancing the tax lock date, reset rules. No Georgian return type is shipped. | 20 (2026-09-24) |
| Fixed assets | [`account_asset.md`](account_asset.md) | `account.asset` + `account.asset.variant` schedules (statutory, other ledgers, gross increases), 4 methods incl. no depreciation, multi-ledger via `account.journal.group`, depreciation models, bill-to-asset creation, pause/sell/dispose, re-evaluation. | 20 (2026-09-24) |
| Deferred expenses and revenue | [`deferred_expenses_revenue.md`](deferred_expenses_revenue.md) | Settings, eligible lines, date entry, calculation methods with worked amounts, on-validation and grouped generation, reports, tax and budget effects, reset rules, cron, troubleshooting. | 20 (2026-09-24) |
| Deferred revenue walkthrough | [`deferred_revenue.md`](deferred_revenue.md) | Customer-side walkthrough, sign logic, grouped example, reading the report, VAT, revenue budgets, credit notes, common mistakes. | 20 (2026-09-24) |
| Analytic accounting | [`analytic_accounting.md`](analytic_accounting.md) | Plans as columns, the distribution JSON, analytic items created at posting, two-way sync, line splitting, applicability scoring, distribution models, balances, settings and menus. | 20 (2026-09-24) |
| `account.analytic.account` model | [`account_analytic_account.md`](account_analytic_account.md) | One plan per account with a per-plan column, non-stored debit/credit/balance, company and plan changes, duplication, security. | 20 (2026-09-24) |
| Analytic budgets | [`analytic_budget.md`](analytic_budget.md) | Budget states and revisions, the Generate wizard, matching rules, budget types, what consumes a budget, purchase commitments and the over-budget warning, theoretical amount, project progress. | 20 (2026-09-24) |
| Fixed costs guide | [`accounting_fixed_costs_guide.md`](accounting_fixed_costs_guide.md) | Account types, parent accounts, tax repartition and tags, reconciliation, lock dates, year-end, payment terms, journal types, analytic distribution, budgets and their vocabulary, budget vs P&L. | 20 + 19 notes (2026-09-22) |
| Loading accounting data | [`accounting_migration.md`](accounting_migration.md) | Opening balances: trial balance, open receivables and payables, inventory, fixed assets, banks, lock dates, opening entry mechanics, import reconciliation, validation queries, templates, error messages. | 20 + 19 notes (2026-09-22) |
| Companies vs branches | [`accounting_multicompany_branches.md`](accounting_multicompany_branches.md) | Branches vs separate companies, shared vs separate charts, inter-company rules, consolidation, impact on sales/purchase/inventory/invoicing/expenses/payroll, `ir.access` security, pitfalls, decision framework. | 20 + 19 notes (2026-09-22) |
| Currency exchange and transit | [`currency_exchange_transit.md`](currency_exchange_transit.md) | Rate lookup (a rate applies from the next day; NBG rates therefore one day late), exchange accounts, when payments get exchange entries, worked USD/EUR cases, unreconcile, revaluation. | 20 (2026-09-24) |
| One bank, many currencies | [`bank_journal_multicurrency_setup.md`](bank_journal_multicurrency_setup.md) | Bank accounts carrying name and BIC, one journal per currency, shared-IBAN layout, creation paths (online sync, manual, journal form), currency rules, dropdown search, fixing duplicates. | 20 (2026-09-24) |
| Off-balance sheet | [`off_balance_sheet.md`](off_balance_sheet.md) | Isolation rules (no mixing, no taxes, no reconciliation), where the type can be selected, reports (Trial Balance yes, Balance Sheet no), Georgian 9900xx accounts, scenarios. | 20 (2026-09-24) |
| Equity (cap table, UBO) | [`equity.md`](equity.md) | Transactions, security classes, the cap table SQL view (ownership, voting, dilution), valuations, UBO, portal; not linked to the ledger. | 20 (2026-09-24) |

## Georgian localization, rs.ge and banks

| Topic | File | What it covers | Status |
|---|---|---|---|
| Georgian accounting localization | [`l10n_ge.md`](l10n_ge.md) | Core chart `ge` (accounts, 36 VAT taxes, 4 fiscal positions, VAT Report tags) and our `gec_localization` (extra accounts, 31 taxes incl. 23 withholding, payroll accounts, contact default taxes, Not Taxed, CIT wizard, BIC from IBAN). Tag-to-declaration flow, withholding at payment, three shipped mapping defects, setup checklist. | 20 (2026-09-24) |
| Form 30 withholding declaration | [`gec_income_tax_report.md`](gec_income_tax_report.md) | Annex A from paid payslips and withholding lines, annex D cars, annex E self-paying recipients, main part cells 16-69, validation, export, design decisions. Tested on 20 (32 of 33 pass); individuals with a Tax ID export as companies (open); module not installed on gec20_prod1. | 20 (2026-09-24) |
| Form 30 full declaration, gap plan (Georgian) | [`rs_form30_full_declaration_gap_plan.md`](rs_form30_full_declaration_gap_plan.md) | Pages 1-6 against Order 996 art. 38: what the module builds, open items, remaining phases, accountant decisions, category-to-tax check. | 20 (2026-09-24) |
| VAT annex "a" plan | [`vat_declaration_annex_a_plan.md`](vat_declaration_annex_a_plan.md) | Plan, nothing built. Core `l10n_ge`'s VAT Report already maps every code; the real gaps (fiscal-position defect, fixed-asset split, advances, customs value, Part III code 3, no return type) and open questions. | 20 (2026-09-24) |
| rs.ge e-invoice advances | [`rs_einvoice_down_payments.md`](rs_einvoice_down_payments.md) | Advance invoices and their settlement: net offset vs native rs.ge attach, how the mode is chosen, eligibility, guards, VAT-compliance verdict. | 20 + 19 notes (2026-09-23) |
| rs_waybill / rs_einvoice findings | [`rs_waybill_einvoice_fix_plan.md`](rs_waybill_einvoice_fix_plan.md) | Open findings with effect, fix location and how to provoke them. The top section is the Odoo 20 port status; the item bodies were verified against Odoo 19. | 20 delta + 19 body |
| rs modules method reference | [`rs_modules_method_reference.md`](rs_modules_method_reference.md) | Per-method reference of `rs_base_methods` + `rs_einvoice`. Written against the old copies (`rs_base`, `gec_rs_invoice`); its paths do not exist in the 20.0 tree. | 19 |
| RS employee registry | [`employee_registry_rs.md`](employee_registry_rs.md) | Employee registry sync with rs.ge: buttons and daily cron, one RS login per legal entity, termination pushes, sync log. | 20 + 19 notes (2026-09-23) |
| Basis Bank | [`basis_bank.md`](basis_bank.md) | Transfers and salary/treasury packages with OTP and optional approval, statement import both ways, Paid until the bank confirms then Reconciled, 48-hour confirm-or-reset cron, journal detection (BIC `CBASGE22` + connection), payroll via `gec_payroll_bank`. | 20 (2026-09-24) |
| Georgian ID card signing | [`id_ge_sign.md`](id_ge_sign.md) | Qualified signature with the Georgian ID card in Odoo Sign: desktop-app flow, PAdES checks, stacked signers, trust settings. Does not load on 20.0 (extends the removed `sign.completed.document`); the doc describes the port. | 20 (2026-09-24) |

## Inventory and manufacturing

| Topic | File | What it covers | Status |
|---|---|---|---|
| Inventory | [`inventory.md`](inventory.md) | Warehouses and locations, routes and rules, multi-step flows, SO to delivery, reservation and removal, backorders, returns and portal returns, scrap moves, lots, packages, putaway, replenishment, batches and waves, secondary-location pattern, security, settings. | 20 (2026-09-24) |
| Forecasted report | [`inventory_forecast_report.md`](inventory_forecast_report.md) | Header quantities and lead time, the graph view, matching demand to reserved, free and transit stock or receipts, table actions, the availability badge, module extensions. | 20 (2026-09-24) |
| Stock valuation | [`stock_valuation.md`](stock_valuation.md) | Standard/FIFO/AVCO, Anglo-Saxon vs continental, periodic vs perpetual (configured in `account`), COGS, price differences, landed costs, lot valuation, dropship and returns, closing, walkthroughs. | 20 + 19 notes (2026-09-22) |
| Manufacturing and maintenance | [`mrp.md`](mrp.md) | BoMs (kits, batch size, continuous production), MO states, consumption warning, backorders, work orders, planning, procurement MOs, scrap and unbuild, costing, Shop Floor, quality checks, maintenance requests, MTBF/MTTR. | 20 (2026-09-24) |

## HR, time off and attendance

| Topic | File | What it covers | Status |
|---|---|---|---|
| Employees and versions | [`hr_employee_versions.md`](hr_employee_versions.md) | Employee as a timeline of `hr.version`: version in force, contract dates, templates, calendar and timezone on the version, departure, the payroll "Version update" dialog. | 20 + 19 notes (2026-09-22, dialog 2026-09-24) |
| HR access rights | [`hr_access_rights.md`](hr_access_rights.md) | Who sees what: `ir.access` layers, the six different managers, what a plain user reaches, officer vs administrator, payroll access levels, a diagnosis ladder. | 20 + 19 notes (2026-09-22) |
| Time off | [`hr_holidays.md`](hr_holidays.md) | Leaves, allocations, approvals, time-off types as work entry types, public holiday loading, payroll interaction, crons, security. | 20 + 19 notes (2026-09-22, cleanup started 2026-09-24) |
| Accrual plans | [`hr_holidays_accrual_plans.md`](hr_holidays_accrual_plans.md) | Plans and milestones, the accrual engine, carry-over (and when it wipes the balance), backdating, caps, batch allocation. | 20 + 19 notes (2026-09-22) |
| Time off units | [`hr_holidays_time_off_units.md`](hr_holidays_time_off_units.md) | Unit of measure vs request unit, per-request durations, hours-to-days conversion. | 20 + 19 notes (2026-09-22) |
| Public holidays | [`public_holidays_flow.md`](public_holidays_flow.md) | Manual entry, loader wizard and cron (no Georgian data), leave re-evaluation, time rules, timesheets, payslip hours and pricing, the GROSS trap, overtime on holidays, Georgian checklist, the country-only time type trap. | 20 (2026-09-24) |
| Resource calendars | [`resource_calendars.md`](resource_calendars.md) | Fixed / Variable / Undefined calendars, flexible hours, `hours_per_day`, half days, calendar leaves, timezone on the version, the interval engine and who calls it. | 20 (2026-09-24) |
| Attendance and payroll | [`attendance_work_entry.md`](attendance_work_entry.md) | Clock records, validation modes, time rules and crons, attendance-based vs schedule-based pay, payroll warnings, settings, Georgian overtime recipe, access. | 20 (2026-09-24) |
| Work entries and time rules | [`work_entries.md`](work_entries.md) | Work entries as values computed at payslip time, `hr.time.rule` reclassifying attendances and leaves, work entry types, payslip consumption, security. | 20 + 19 notes (2026-09-22) |
| Timesheets, validation and locks | [`timesheets.md`](timesheets.md) | Timesheet lines as analytic lines, creation paths incl. the Timesheets Assistant, validation and locks, costs, payroll use. | 20 + 19 notes (2026-09-22) |
| Timesheets and analytic lines | [`hr_timesheet.md`](hr_timesheet.md) | Timesheet costing, the analytic profitability classification, project reporting. | 20 + 19 notes (2026-09-22) |
| Appraisals | [`hr_appraisal.md`](hr_appraisal.md) | States, creation paths, sharing, the Done lock, bulk actions. | 20 + 19 notes (2026-09-22) |
| Job positions | [`hr_job_positions.md`](hr_job_positions.md) | Job department vs employee department, duplicate names, recruitment links. | 20 + 19 notes (2026-09-22) |
| Recruitment sourcing | [`hr_recruitment_sourcing.md`](hr_recruitment_sourcing.md) | Source, medium and campaign on applicants, tracker URLs. | 20 + 19 notes (2026-09-22) |
| Alta HR customization | [`hr_customization.md`](hr_customization.md) | Offer Accept/Reject on locked terms, contract and trial expiry cron, team-leader access to versions, payslips and attendances, timesheet change history, welcome mail. | 20 (2026-09-24) |

## Payroll

| Topic | File | What it covers | Status |
|---|---|---|---|
| Payroll core | [`hr_payroll.md`](hr_payroll.md) | Payslips and pay runs: states and blockers, warnings, worked days, salary rules and inputs, refunds and corrections, accounting and payment, integrations, crons, symptom-to-cause appendix. | 20 + 19 notes (2026-09-22) |
| Payroll accounting | [`hr_payroll_account.md`](hr_payroll_account.md) | Payslip to journal entry: validation, move construction and line merging, batch mode, entry preview, warnings. | 20 + 19 notes (2026-09-22) |
| Paying payslips | [`payroll_payment_flow.md`](payroll_payment_flow.md) | Stock Pay and Mark as Paid, payment register rules, our net-payable layout on `l10n_ge`, Pay Salaries batches with Basis Bank, `geo_payroll` Register Payment, checklist. | 20 (2026-09-24) |
| Wage types | [`payroll_wage_types.md`](payroll_wage_types.md) | Fixed and hourly pricing (wage over the calendar's hours in the period), where worked time comes from, scheme matrix, the daily-rate pattern, combinations, `geo_payroll` schemes. | 20 (2026-09-24) |
| Georgian payroll (`geo_payroll`) | [`geo_payroll.md`](geo_payroll.md) | Pay schemes, work logs, Georgian income tax and pension, benefits, register payment, payslip header, troubleshooting. Updated for 20 section by section by the payroll sessions. | partly 20 |
| `geo_payroll` design plans | [`geo_payroll_implementation_plan.md`](geo_payroll_implementation_plan.md), [`geo_payroll_unit_work_plan.md`](geo_payroll_unit_work_plan.md), [`geo_payroll_benefits_plan.md`](geo_payroll_benefits_plan.md) | Design specs of implemented features (base design, piecework, benefits). | 19 |
| `geo_payroll` manual tests | [`geo_payroll_testing.md`](geo_payroll_testing.md) | Click-by-click manual test guide. | 19 |

## Platform

| Topic | File | What it covers | Status |
|---|---|---|---|
| Mail | [`mail_configuration.md`](mail_configuration.md) | Alias domains, outgoing servers and From resolution, personal servers, the queue, incoming servers, routing, aliases, bounces and blacklist, notifications, system parameters, troubleshooting. | 20 (2026-09-24) |
| Microsoft Entra ID login | [`azure_entra_sso.md`](azure_entra_sso.md) | Entra ID through `auth_oauth` (implicit flow): provider values, the authorization header parameter, user linking, sign-up default, error meanings, session timeouts, LDAP alternative. | 20 (2026-09-24) |
| AI | [`ai_module.md`](ai_module.md) | Odoo AI through IAP (no own API keys): agents, skills, tools, async sessions, AI server actions and fields, RAG with pgvector, the `ai_mcp` server, module map. | 20 (2026-09-24) |
| Dashboards | [`board_dashboard.md`](board_dashboard.md) | My Dashboard boards and spreadsheet dashboards: pinning, layouts, shipping a board, sections, publication, sample data, editing, access, share links. | 20 (2026-09-24) |

## Plans and practice material

| Topic | File | What it covers | Status |
|---|---|---|---|
| Multi-branch cost allocation (Georgian) | [`multi_branch_cost_allocation_plan.md`](multi_branch_cost_allocation_plan.md) | Plan, not implemented: allocating payroll and costs across branches of one legal entity with analytic accounts. | 19 |
| Certification practice | [`certification_exam.md`](certification_exam.md) | 98 multiple-choice questions across 16 apps, with explanations. | 19 |

---

## Georgian tax law (sources)

Converted legal texts and their analysis. Not Odoo docs, and not tied to an Odoo version.

| Source | Analysis | Converted text |
|---|---|---|
| MoF Order #996 (31 Dec 2010), Tax Administration Instruction, original text | [`mof_order_996_2010.md`](mof_order_996_2010.md) | [`sources/mof_order_996_2010_ka.md`](sources/mof_order_996_2010_ka.md) (Georgian) |

## Module READMEs

Each custom module keeps a user guide (`README.md`) and a developer guide (`README_DEV.md`) in its own folder. These were not
part of the 2026-09-24 review; some still mention Odoo 19 (noted below).

| Module | User guide | Developer guide |
|---|---|---|
| `gec_localization` | [`README.md`](../custom_addons/gec_odoo_modules/gec_localization/README.md) | [`README_DEV.md`](../custom_addons/gec_odoo_modules/gec_localization/README_DEV.md) (says 9 accounts; the code has 10) |
| `geo_payroll` | [`README.md`](../custom_addons/gec_odoo_modules/geo_payroll/README.md) | [`README_DEV.md`](../custom_addons/gec_odoo_modules/geo_payroll/README_DEV.md) |
| `gec_payroll_bank` | [`README.md`](../custom_addons/gec_odoo_modules/gec_payroll_bank/README.md) (still says 19.0) | [`README_DEV.md`](../custom_addons/gec_odoo_modules/gec_payroll_bank/README_DEV.md) |
| `basis_bank` | [`README.md`](../custom_addons/gec_odoo_modules/basis_bank/README.md) | [`README_DEV.md`](../custom_addons/gec_odoo_modules/basis_bank/README_DEV.md), backlog [`KNOWN_ISSUES.md`](../custom_addons/gec_odoo_modules/basis_bank/KNOWN_ISSUES.md) |
| `gec_income_tax_report` | [`README.md`](../custom_addons/gec_odoo_modules/gec_income_tax_report/README.md) | [`README_DEV.md`](../custom_addons/gec_odoo_modules/gec_income_tax_report/README_DEV.md) (still says Odoo 19), wiring map [`developer_map.html`](../custom_addons/gec_odoo_modules/gec_income_tax_report/developer_map.html) |

## Files outside this folder

| File | What it is |
|---|---|
| [`../basisbank_api.md`](../basisbank_api.md) | Basis Bank API reference (the bank's spec; not tied to an Odoo version). |
| [`../eapi_rs.md`](../eapi_rs.md) | rs.ge e-invoice REST API specification (Georgian). |
| [`../sashemosavlo_deklaraciebi_sruli_cnobari.md`](../sashemosavlo_deklaraciebi_sruli_cnobari.md) | Income declarations domain reference (Georgian). |
| [`../rs_einvoice_method_reference.md`](../rs_einvoice_method_reference.md), [`../rs_einvoice_method_reference_2026-06-08.md`](../rs_einvoice_method_reference_2026-06-08.md) | Odoo 19 method references of the old `gec_rs_invoice` copy of `rs_einvoice`; not maintained. |

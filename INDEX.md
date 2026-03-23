# Odoo Business Module Documentation

> Internal knowledge base — built from reading actual Odoo 19 source code.
> Every fact in these files is traceable to a real source file path.
> Updated as we learn. Never written from assumptions.

---

## How to Use

- Each file covers one Odoo business module end-to-end.
- Code references are clickable links to the actual source.
- "Dependencies" sections tell you which modules must be installed and what integrations exist.
- Start with a module's doc before asking questions — the answer may already be there.

---

## Module Index

| Module | File | Status | Last Updated |
|---|---|---|---|
| `hr_payroll` | [`hr_payroll.md`](hr_payroll.md) | Complete — salary inputs, adjustments, rule computation | 2026-02-26 |
| `account_budget` + `project_account_budget` | [`analytic_budget.md`](analytic_budget.md) | Complete — budget flow, achieved amount logic, project integration | 2026-02-26 |
| `stock` + `sale_stock` | [`inventory.md`](inventory.md) | Complete — warehouses, routes, SO→delivery flow, reservations, quants, multi-step, secondary-location fallback pattern | 2026-03-03 |
| `stock` — Forecast Report | [`inventory_forecast_report.md`](inventory_forecast_report.md) | Complete — header numbers, graph SQL view, reconciliation algorithm, forecast widget, lead time | 2026-02-27 |
| `account` — Chart of Accounts | [`accounting_coa.md`](accounting_coa.md) | Complete — prerequisites, account types, groups, roots, tags, multi-company, opening balances, security, chart template loading | 2026-03-03 |
| `account_reports` — Reporting Engine | [`accounting_reports.md`](accounting_reports.md) | Complete — 6 engines, all standard reports, options system, date scopes, groupby, variants, composite reports, audit drill-down | 2026-03-03 |
| `hr_attendance` + `hr_work_entry` | [`attendance_work_entry.md`](attendance_work_entry.md) | Complete — attendance→work entry flow, timezone split, same-day archive problem, overtime ruleset setup, payslip integration, Reset vs Regenerate Overtimes | 2026-03-03 |
| Accounting Migration Guide | [`accounting_migration.md`](accounting_migration.md) | Complete — trial balance import, AR/AP open items, inventory, fixed assets, banks, lock dates, suspense account pattern, opening entry mechanics | 2026-03-03 |
| **Certification Exam — All Modules** | [`certification_exam.md`](certification_exam.md) | 98 questions across 16 modules — Inventory, MRP, POS, HR, Spreadsheet, Accounting, Timesheets, Project, Knowledge, eCommerce, Website, Marketing, CRM, Survey, Sales, AI, Studio, Purchase | 2026-03-07 |
| `account_asset` — Fixed Assets | [`account_asset.md`](account_asset.md) | Complete — depreciation concepts, 3 board columns, value fields, lifecycle states, all 3 methods, cron, worked example, re-evaluation (increase/decrease), pause/resume, auto-create logic, non-deductible taxes, asset groups, company gain/loss accounts, reverse-move behavior, write propagation, all constraints | 2026-03-10 |
| `account_accountant` + `account_reports` — Deferred Expenses/Revenue | [`deferred_expenses_revenue.md`](deferred_expenses_revenue.md) | Complete — Balance Sheet/P&L/Cash Flow/Budget/Tax connections, expense+revenue mirror, on_validation vs manual entry structures, analytic propagation, lock date, audit trail, account type requirements, mixed entry constraint, all 8 config fields, report exclusion logic | 2026-03-10 |
| `account` + `account_budget` — Fixed Costs Guide | [`accounting_fixed_costs_guide.md`](accounting_fixed_costs_guide.md) | Complete — all 18 account types, tax repartition + account tags, reconciliation (partial/full/multi-currency), 5 lock date types, year-end filtering mechanics, payment terms + due dates, analytic distribution JSON + multi-plan, budget states + drill-down, committed amount, budget vs P&L connection | 2026-03-10 |
| `account_accountant` — Deferred Revenue | [`deferred_revenue.md`](deferred_revenue.md) | Complete — revenue-focused standalone: journal entries, sign logic, liability holding account, config, report handler, generation modes, VAT exclusion, credit notes, common mistakes | 2026-03-10 |
| `stock_account` + `stock_landed_costs` — Stock Valuation | [`stock_valuation.md`](stock_valuation.md) | Complete — 3 costing methods (Standard/FIFO/AVCO) with algorithms, Anglo-Saxon vs Continental accounting, purchase price difference, perpetual vs periodic valuation, COGS computation chain, landed cost allocation (5 split methods), lot-level valuation, dropship/return flows, closing process, historical valuation, account configuration, value priority chain, security, 9 business walkthroughs, 7 code-level traces | 2026-03-13 |
| `board` + `spreadsheet_dashboard` — Dashboards | [`board_dashboard.md`](board_dashboard.md) | Complete — two dashboard systems (legacy board + spreadsheet), data models, storage (ir.ui.view.custom XML vs binary JSON), frontend OWL components, drag-drop layout, add-to-dashboard flow, spreadsheet dashboard groups/shares, HTTP routes, sample data mechanism, 4 customization approaches (UI pin, spreadsheet editor, XML data records, custom board view), access control, enterprise edition features | 2026-03-14 |
| `mrp` + `mrp_workorder` + `maintenance` — Manufacturing & Maintenance | [`mrp.md`](mrp.md) | Complete — MO lifecycle, work orders, BOMs (normal + phantom), operations, work centers, scheduling/planning, component consumption, backorders, enterprise shop floor/quality, configuration settings, equipment categories, maintenance requests (corrective/preventive), MTBF/MTTR, work center blocking, maintenance teams | 2026-03-19 |
| `account` + `account_inter_company_rules` + `account_reports` — Multi-Company vs Branches | [`accounting_multicompany_branches.md`](accounting_multicompany_branches.md) | Complete — Part 1: branches vs multi-company architecture, shared vs separate CoA, inter-company rules, consolidation reports, analytic accounting, pros/cons. Part 2: cross-module impact (Sales, Purchase, Inventory, Invoicing, Expenses, Payroll), security model (ir.rule patterns: `in` vs `parent_of` vs `+[False]`), permissions matrix with user examples, end-to-end SO-to-payment flow comparison, common pitfalls, decision framework | 2026-03-18 |
| `equity` — Cap Table & UBO | [`equity.md`](equity.md) | Complete — 4 transaction types (issuance/transfer/exercise/cancellation), security classes (shares/options), SQL-view cap table (ownership/voting/dilution), valuations, UBO (9 control methods + 8 auth roles), portal access, NO accounting integration (standalone module), security groups | 2026-03-20 |

---

## Documentation Standards

Each module file follows this structure:

1. **Overview** — what the module does in 3–5 sentences
2. **Dependencies** — required modules, optional integrations, what it provides to others
3. **Business Flow** — the end-to-end process with state transitions
4. **Key Models** — core data models with purpose and key fields
5. **Key Methods** — important business logic methods with file:line references
6. **UI Entry Points** — menus, views, wizards the user interacts with
7. **Configuration** — settings, groups, and options that change behavior
8. **Edge Cases & Gotchas** — non-obvious behavior, constraints, known limits

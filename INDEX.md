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

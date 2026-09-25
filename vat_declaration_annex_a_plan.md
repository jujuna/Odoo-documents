# VAT Declaration — Annex "a" Parts I–III: build plan

> **Module:** none built (plan of 2026-09-21) | **Path:** target to be decided, see [Where it belongs](#where-it-belongs)
> Verified against Odoo 20 source on 2026-09-24.

Source spec: the accountant's `დღგ დანართი ა.xlsx` (sheets `ა I`, `ა II`, `ა III`) and three portal screenshots. Nothing is written yet.

---

## First: Odoo 20 already ships this report

Core `l10n_ge` contains a **VAT Report** (`l10n_ge.tax_report_ge`, a variant of the generic tax report) whose lines are annex "a" parts I–III, code by code, with Base and Tax columns ([account_tax_report_data.xml](../addons/l10n_ge/data/account_tax_report_data.xml)). Every line reads tax tags `N(B)` / `N(T)`, and `l10n_ge` ships one tax per code that carries them ([account.tax-ge.csv](../addons/l10n_ge/data/template/account.tax-ge.csv)). `gec_localization` adds no VAT grids and states that the VAT declaration is `l10n_ge`'s report ([__manifest__.py:16](../custom_addons/gec_odoo_modules/gec_localization/__manifest__.py#L16)). Our former module `gec_l10n_ge_tax`, its `[GE-VAT]` tags and its DGV report do not exist in 20.0; see [`l10n_ge.md`](l10n_ge.md).

**What this does to the plan.** Its core idea was an own model (`rs.vat.declaration`) plus a CSV cell catalogue summing `[GE-VAT]` tags. In 20.0 that would duplicate a core report, and the four new tags it asked for (T1–T4 for codes 9, 12, 14¹, 14²) already exist as `l10n_ge` taxes. The risk of building it as written: two VAT figures in one database that can disagree, and our own tag mapping to maintain beside core's, which Odoo upgrades.

**What I would do instead:** run one real month through `l10n_ge`'s VAT Report and compare it with the portal first. Then build only the gaps listed below, as data on top of `l10n_ge` (taxes, tags, report expressions in `gec_localization`), not as a parallel declaration model.

---

## Row by row: what `l10n_ge` covers

Legend: **TAX** = an `l10n_ge` tax carries the tag, so the row fills from every document that uses that tax · **AGG** = report aggregation · **TYPED** = no tax; the value is entered by hand · report line codes are `ge_N`.

### Part I — output VAT

| Code | Row | Report line / `l10n_ge` tax (tag) | Kind | Remaining issue |
|---|---|---|---|---|
| 1 | supply for consideration | `ge_1` / `18%` (1) | TAX | the fiscal-position defect below |
| 1¹ | margin scheme | `ge_2` / `18% S` (2) | TAX | no margin scheme in our stack |
| 2 | advance received before supply | `ge_3` / `18% AD` (3) | TAX | sale down-payment invoices reuse the order lines' taxes ([sale_order.py:2590](../addons/sale/models/sale_order.py#L2590)), so advances land in code 1 unless `18% AD` is set by hand — **Q1** |
| 3 | free supply of goods | `ge_4` / `18% FOC G` (4) | TAX | |
| 4 | goods shortage | `ge_5` / `18% L` (5), tax scope "none" | TAX | journal entry needed; market price ≠ stock cost |
| 5 | free services for personal use | `ge_6` / `18% FOC S` (6) | TAX | **Q2** |
| 6 | own-built building put into use | `ge_7` / `18% B` (7) | TAX | **Q3** |
| 6¹ | own-force repair of own building | `ge_8` / `18% R` (8) | TAX | **Q4** |
| 7 | barter | `ge_9` / `18% BA` (9) | TAX | |
| 7¹ | goods retained after ceasing activity | `ge_10` / `18% RE` (10), scope "none" | TAX | one-off journal entry |
| 8 | other taxable operations | `ge_11` / `18% O` (11) | TAX | |
| 9 | supplies to TC 172(3) persons | `ge_12` / `0% EXT D` (12) | TAX | base only |
| 10 | natural gas to thermal power plants | `ge_13` / `0% EXT G` (13) | TAX | not our business |
| 11 | TC 172(1) incl. international transport | `ge_14` / `0% EXT I` (14) | TAX | |
| 12 | international-treaty projects | `ge_15` / `0% EXT P` (15) | TAX | |
| 13 | other exempt with credit | `ge_16` / `0% EXT TA` (16) | TAX | the line's label mixes code 13 with its "of which: shortage found by a tax-authority inventory" sub-row; the sub-row has no line of its own |
| 14 | export / re-export | `ge_17` / `0% EX` (17) | TAX | invoice base, not customs value — **Q5** |
| 14¹ | financial services | `ge_18` / `0% EXT F` (18) | TAX | |
| 14² | immovable property / land | `ge_19` / `0% EXT L` (19) | TAX | |
| 14³ | other exempt without credit | `ge_20` / `0% EXT O` (20) | TAX | |
| 15 | total | `ge_001`: tax = lines of codes 1–8, base = all lines | AGG | matches the xlsx `=SUM(E3:E13)` |

### Part II — reverse charge

| Code | Row | Report line / tax | Kind |
|---|---|---|---|
| 1 | services from a non-established person | `ge_21` / `18% R C S` | TAX |
| 2 | goods bought in a customs warehouse | `ge_22` / `18% R C G C` | TAX |
| 3 | goods bought from a FIZ enterprise | `ge_23` / `18% R C G F` | TAX |
| 4 | total | `ge_002` | AGG |

The xlsx formula `=SUM(E2:E5)` reaches one row into the header; the report sums lines 1–3 only.

### Part III — creditable input VAT

The report has Base and Tax only. The annex's split of column D into **E (goods/services)** and **F (fixed assets)** does not exist — **Q6**.

| Code | Row | Report line / tax | Kind | Remaining issue |
|---|---|---|---|---|
| 1 | domestic purchases from VAT payers | `ge_24` / purchase `18%` (24) | TAX | E/F split |
| 2 | import VAT | `ge_25` / `18%`, `12%`, `5% EX ONLY` (+ base taxes) | TAX | E/F split |
| 3 | import VAT assessed by a tax-authority decision | `ge_26`; no tax carries tag 26 | TYPED | only a journal entry with the tag, or an editable expression |
| 4 | reverse-charge VAT | `ge_27`; the three Part II taxes also post 27(T) | TAX | equals Part II total by construction |
| 4¹ | from annex "b" part X row 4 | `ge_28`, editable external value | TYPED | typed in the report itself |
| 5 | fixed assets retained after ceasing activity | `ge_29` / `18% FA` | TAX | `18% FA` is this case, not fixed-asset purchases |
| 6 / 6¹ | creditable part of Part I codes 6 / 6¹ | `ge_30` / `18% BU`, `ge_31` / `18% RFA` | TAX | the xlsx derives them as Part I × 18%; here they are separate taxes that must be booked together with Part I |
| 7 | barter | `ge_32` / purchase `18% BA` | TAX | |
| 8 | TC 161¹ auction / direct sale | `ge_33` / `18% AU` | TAX | |
| 9 | total | `ge_003` | AGG | |

The report adds a net calculation (`ge_34` total output VAT, `ge_35` net payable) that the annex does not have.

**The honest headline.** Every code except Part III 3 has a tax and a line; 4¹ is typed in the report; the three totals aggregate. "Automatic" now depends on the accountant picking the right tax on each document. Codes that describe events without an invoice (Part I 4, 6, 6¹, 7¹; Part III 5, 6, 6¹) still need a journal entry carrying the tax.

---

## Gaps on top of `l10n_ge`

| # | Gap | Why it matters |
|---|---|---|
| G1 | **Fiscal-position defect.** Under "Georgia (VAT Registered)" `18%` is replaced by all six taxes whose original tax is `18%`; under "Georgia (non-VAT Registered)" `18%` is dropped | wrong totals on codes 1, 1¹, 2, 8, 14¹–14³ until fixed; see [`l10n_ge.md`](l10n_ge.md) |
| G2 | Part III E/F split | needs fixed-asset purchase taxes with their own tags, or code — **Q6** |
| G3 | Advances (code 2) | down payments carry the order's `18%` — **Q1** |
| G4 | Export customs value (code 14) | the report takes the invoice base — **Q5** |
| G5 | Part III 3 | no tax; needs an editable expression like `ge_28`, or a tagged journal entry |
| G6 | **No Georgian VAT return card** | `account_reports` ships only the annual CIT and audit return types ([account_return_data.xml](../enterprise/account_reports/data/account_return_data.xml)) and there is no `l10n_ge_reports`, so no monthly card, closing entry or automatic tax lock exists for Georgia; see [`account_returns.md`](account_returns.md) — **Q8** |
| G7 | Filing file | the VAT pages seem to be typed on the portal — **Q7** |

---

## Where it belongs

- **Not in `gec_income_tax_report`.** That module is the withholding declaration; its manifest depends on `geo_payroll` ([__manifest__.py](../custom_addons/gec_odoo_modules/gec_income_tax_report/__manifest__.py)). A payroll-free client installing a VAT feature would install payroll, and any payroll bug would block VAT filing.
- **`gec_localization`** already depends on `l10n_ge` and holds our Georgian taxes ([template/account.tax-ge.csv](../custom_addons/gec_odoo_modules/gec_localization/data/template/account.tax-ge.csv)). Gaps G2 and G5 are data there. It creates template records that are missing in a company and never rewrites existing ones ([template_ge.py:36](../custom_addons/gec_odoo_modules/gec_localization/models/template_ge.py#L36)).

### If an own declaration screen is still wanted

Only if the accountant needs something the report cannot show (a per-row "why?" page, a typed-cell workflow). Then copy the Form 30 main-part pattern, which already works:

| Reused | Where it is | Used for |
|---|---|---|
| Cell catalogue + value row | [`rs_form30_summary.py`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_summary.py) (46 lines) | `rs.vat.cell` / `rs.vat.line` with base / VAT / goods / assets fields |
| Three-way refresh (computed always follows, proposed follows until edited via `proposed_value`, typed never touched) | [`_sync_summary_lines`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L518) | copied as is |
| `_read_group` over posted lines of the period | [`_ledger_values`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L471) | a tag sum over `tax_tag_ids` with `l10n_ge`'s tags and sign convention (sales formulas negative, `-1(B)`; purchases plain, `24(B)`) |
| Header: company, month from day 1, period, draft/exported, one per company and month | [`RsForm30Declaration`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L98) | `rs.vat.declaration` |
| Per-cell explanation + `_trace_item` | [`rs_form30_explain.py`](../custom_addons/gec_odoo_modules/gec_income_tax_report/wizard/rs_form30_explain.py), [`_trace_item`](../custom_addons/gec_odoo_modules/gec_income_tax_report/models/rs_form30_declaration.py#L412) | invoices behind a cell, with links |
| OWL grid, row editable unless computed | [`rs_form30_summary_grid.js`](../custom_addons/gec_odoo_modules/gec_income_tax_report/static/src/components/rs_form30_summary_grid/rs_form30_summary_grid.js) (61 lines) | the three pages |

Rules if built: own models, no `declaration_type` on the Form 30 models (it would break the meaning of their `UNIQUE(company_id, date_from)` and put a type filter on every Form 30 domain); own menu beside Form 30 under `account.menu_finance_reports` ([account_menuitem.xml:36](../addons/account/views/account_menuitem.xml#L36)); access in `security/ir.access.csv` with company restriction rows, loaded last in the manifest.

---

## Build order

| Phase | What | Result |
|---|---|---|
| 1 | Fix G1; post one real month with the right `l10n_ge` taxes; compare the VAT Report with the portal, line by line | proof of what the report already gets right; answers Q1, Q5 |
| 2 | Accountant answers Q6–Q8 | decides G2, G6, G7 |
| 3 | Data in `gec_localization`: fixed-asset purchase taxes and tags (G2), Part III 3 expression (G5), optionally a return type (G6) | report complete for our cases |
| 4 | Only if still needed: own screen as above | explanation and typed-cell workflow |

---

## Open questions

| # | Question | Who decides |
|---|---|---|
| Q1 | Advances: should down-payment invoices carry `18% AD` (code 2)? Does the final invoice's negative down-payment line then net code 1 correctly across months? Check a real down-payment invoice first; see [`rs_einvoice_down_payments.md`](rs_einvoice_down_payments.md) | verify in DB, then accountant |
| Q2 | Code 5: the extra rule for state companies that Tako will supply | accountant |
| Q3 | Code 6: how the production cost of a self-built building is identified | accountant + dev |
| Q4 | Code 6¹: how repair costs of own buildings are recognised (dedicated account? analytic?) | accountant + dev |
| Q5 | Code 14: invoice amount or customs value? If customs value, `rs_waybill` / `rs_einvoice` data may be the better source | accountant |
| Q6 | Part III E/F: is a purchase "fixed assets" when its account type is `asset_fixed` ([account_account.py:73](../addons/account/models/account_account.py#L73)), or only when an `account.asset` holds it (`original_move_line_ids`, [account_asset.py:50](../enterprise/account_asset/models/account_asset.py#L50))? | accountant |
| Q7 | Is a filing file needed, or only the on-screen figures? | accountant |
| Q8 | Is a monthly Georgian VAT return card wanted (deadline the 15th, closing entry or not, tax lock)? | accountant |

Q1, Q5 and Q6 block phase 3. Q2–Q4 affect only rows that stay manual until answered.

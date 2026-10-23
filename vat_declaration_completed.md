# VAT declaration — what is done, how, and what is open

> Work log for [`vat_declaration_build_plan.md`](vat_declaration_build_plan.md), written 2026-10-22.
> **Done:** Phase 0 (tax setup fixes, committed `92a35f7`) and Phase 1 (declaration form for the 5 cell tabs, committed `4daad73`).
> **How it works for users:** [`gec_vat_declaration.md`](gec_vat_declaration.md), [`l10n_ge.md`](l10n_ge.md#corrections-to-l10n_ges-vat-taxes).

## At a glance

| Item | State | Where |
|---|---|---|
| Phase 0: core Georgian VAT tax fixes | **Built, tested, committed** `92a35f7` (branch 20.0, not pushed, not on 19.0) | `gec_localization` |
| Phase 0 on gec20_prod1 | **Applied** 2026-10-22, checked by SQL before and after | local DB only |
| Phase 1: VAT Declaration form (tabs 1, 2, 3, 16, 17) | **Built, reviewed, committed `4daad73`**; 2026-10-22 rebuilt as portal-style grid + Georgian translation, commit `8759c4a` (12/12 tests), NOT on prod1 | `gec_vat_declaration` (new) |
| Phases 2-6 | Not started | plan |

---

## 1. Decisions taken (user, 2026-10-22)

| # | Question | Decision | Effect |
|---|---|---|---|
| D1 | Which sale taxes get the non-VAT and Domestic positions | All 10 sale taxes that list VAT Registered | A Georgian buyer without Tax ID keeps 18 % |
| D2 | Automatic reverse charge on foreign bills | **No.** Vendor's Default Purchase Tax = `18% R C S` for services | A foreign bill without that default gets no VAT tax |
| D3 | Repair existing companies at upgrade | **No.** Code correct for new installs; local gec20_prod1 repaired once by hand; **VPS and horeca never touched** | No upgrade-time rewrite |
| X1 | Portal export files per grid | Deferred: spreadsheet export/import = Phase 6, later | — |
| X2 | Does the portal attach confirmed invoices to a new declaration | **Yes, automatically** | API attach dropped (design T8) |
| X3 | Format of `rs_einv_series` | Checked on prod1: `ეა-86`, `ეა-87`, one `ეკ` without number | — |
| X4 | Test company on rs.ge | **None** | No API attach |
| Q6 | ა III column 5 (fixed assets) | **Typed**; column 4 automatic = Odoo row total − column 5 | Row total always equals Odoo's report |
| Q9 | Which month a correction counts in | **B: the month the buyer accepts it** | Phase 2 keys corrections on acceptance |
| M1 | Names | Module `gec_vat_declaration`, models `gec.vat.*` (never `l10n_ge*` — Odoo's own Georgian modules use it — never `rs.`, Serbia in Odoo) | No clash with Odoo's future modules |
| — | Waybill → invoice wizard fix (old fix 4) | Moved out of Phase 0 | See open items |
| — | Tests | Approved for Phase 0 and Phase 1 | 6 + 10 tests |

---

## 2. Phase 0 — tax setup fixes (`gec_localization`, commit `92a35f7`)

### What was wrong in core `l10n_ge` (proven by tests that fail on the old code)
| Case | Core as shipped | Now |
|---|---|---|
| Sale 1,000 to a customer with Tax ID | 6 taxes (18% S, AD, O, EXT F/L/O replace 18%) | one 18% → 180 |
| Sale to a Georgian customer without Tax ID (or pinned individual) | VAT removed | 18% kept |
| Foreign vendor bill with purchase 18% | 3 reverse-charge taxes | no tax; `18% R C S` via vendor default |
| Import VAT bill 180 with `18% EX ONLY` | totals 360 | totals 180 (vendor bills only) |

### How
- **New chart loads:** override of core's root template method `_get_account_tax` ([template_ge.py:59](../custom_addons/gec_odoo_modules/gec_localization/models/template_ge.py#L59)) edits l10n_ge's rows before they are created: removes only the wrong source from 9 "Replaces" links, adds the 2 positions only where VAT Registered is listed, sets `price_include_override` on the 3 EX ONLY taxes. Rows are read with `.get()` (the template data is a defaultdict).
- **Existing companies:** `_ge_fix_core_vat_taxes` ([template_ge.py:87](../custom_addons/gec_odoo_modules/gec_localization/models/template_ge.py#L87)) applies the same fixes to records: once from the `post_init` hook ([__init__.py:5](../custom_addons/gec_odoo_modules/gec_localization/__init__.py#L5), install only) and after every `ge` chart load or reload ([template_ge.py:119](../custom_addons/gec_odoo_modules/gec_localization/models/template_ge.py#L119)); a reload alone would link positions but keep the bad links. Unlinks only the wrong source, fills Included in Price only when empty, includes archived records. Never runs on `-u`.
- **Tests:** [test_ge_vat_mapping.py](../custom_addons/gec_odoo_modules/gec_localization/tests/test_ge_vat_mapping.py#L57), 6 tests (Tax-ID sale, no-Tax-ID and pinned sales, foreign bill with and without R C S, import bill, install repair, chart reload). All pass; each fails without its fix (negative control run).
- **Install path proof:** scratch DB with core l10n_ge installed first: 10 links before, 1 (export) after installing the module.

### gec20_prod1 (local working DB), repaired 2026-10-22 through odoo shell (same method, not raw SQL)
| | Before | After |
|---|---|---|
| "Replaces" links | 10 | 1 (`0% EX` ← 18%) |
| 10 sale taxes' positions | VAT Registered only | VAT Registered, non-VAT, Domestic individual |
| `18/12/5% EX ONLY` | not price-included | `tax_included` |
| Company domestic fiscal position | empty (18% hidden in pickers) | Georgia (VAT Registered) |
| Taxes flagged domestic | 0 | 122 (8 foreign-only taxes correctly not) |
Raw SQL was not used: `is_domestic` is a stored compute that SQL would leave stale. Pitfall found and written into the
odoo-dev skill (`references/fields.md`): recomputing the company field alone did not recompute `is_domestic`.

---

## 3. Phase 1 — VAT Declaration form (`gec_vat_declaration`, commit `4daad73`)

### What it does
Accounting > Reporting > **VAT Declaration (rs.ge)**: one record per company and month (primary or adjusted), 5 pages
= the portal's ა I, ა II, ა III, Part III, III-19⁶ (109 cells). **Generate** reads the month from core's VAT Report;
the portal's own formulas fill the locked cells; **Save** recomputes after typing; **Mark as Filed** locks it.
Full description: [`gec_vat_declaration.md`](gec_vat_declaration.md).

### How (key code)
| Piece | Where | Note |
|---|---|---|
| Cell catalog, 109 cells | `data/gec.vat.cell.csv`, generated by `Claude outputs/vat_portal_20261021/tools/gen_cell_csv.py` | Counts checked 32/7/33/24/13; portal id = code; Georgian labels and tooltips |
| Odoo source map | [gec_vat_declaration.py:9](../custom_addons/gec_odoo_modules/gec_vat_declaration/models/gec_vat_declaration.py#L9) `ODOO_SOURCE` | 47 (cell → core line, label) pairs, a test checks they exist in the report |
| Portal formulas | [gec_vat_declaration.py:95](../custom_addons/gec_odoo_modules/gec_vat_declaration/models/gec_vat_declaration.py#L95) `compute_cells` | Dependency order, half-up rounding, floor for 17/18, negatives count 0 like the portal |
| Report totals | [gec_vat_declaration.py:263](../custom_addons/gec_odoo_modules/gec_vat_declaration/models/gec_vat_declaration.py#L263) | Same call as Odoo's own tax returns: posted only, company + same-VAT branches, `period_type: 'month'` |
| Sync rule | [gec_vat_declaration.py:297](../custom_addons/gec_odoo_modules/gec_vat_declaration/models/gec_vat_declaration.py#L297) | Proposals first, then formulas; typed cells never touched; proposed follow Odoo until typed |
| Save / Generate / warnings | [:206](../custom_addons/gec_odoo_modules/gec_vat_declaration/models/gec_vat_declaration.py#L206), [:232](../custom_addons/gec_odoo_modules/gec_vat_declaration/models/gec_vat_declaration.py#L232), [:335](../custom_addons/gec_odoo_modules/gec_vat_declaration/models/gec_vat_declaration.py#L335) | Warnings never block |
| Tests | [test_gec_vat_declaration.py](../custom_addons/gec_odoo_modules/gec_vat_declaration/tests/test_gec_vat_declaration.py#L60), 10 tests | September example 975.60 / 5,420 / 500 / 475, ა III split, cell 7, posted-only and other company, typed cell survives Generate, locks, December cells, ა II and margin formulas, report codes |

### Verified on scratch DB `gec20_vat_p1_test` (local, mine)
September example reproduces the portal capture (975.60 / 5,420 / 500 / 475); ა III column 5 = 100 → column 4 = 400;
cell 7 = 54 → cell 17 = 421, cell 7 = 1,000 → cell 18 = 524; month change refused after a value; filed lines and
filed delete refused; `353_64` locked in November, typed in December (36 → Part III 11 = 36).

---

### 3b. Pages rebuilt like rs.ge (2026-10-22, commit `8759c4a`)
The first version showed one list line per cell (109 lines, ა III row 1 three times). User: wrong, must look like the
portal. Rebuilt with a Form 30-style grid widget `gec_vat_grid`: one row per portal row, the portal's columns, lock /
wand icons, green bar with the full Georgian title, short tab labels (`1 · ა-I დასაბეგრი` …). Layout taken from the
portal HTML (catalog fields `line`, `line_label`, `slot`; rows 22/4/11/20/5). Data, Generate and formulas unchanged.
Georgian translation added (`i18n/ka_GE.po`, 104 strings). Reviewer fixes applied: the "Odoo" hint uses Odoo's
rounding check (a raw float compare hid ~40 % of 1-tetri differences), one click puts the cursor in a cell (checked in
a live browser), Enter/Tab keyboard path, readable portal notes, dark-mode contrast. 12/12 tests incl. a browser test
that opens all 5 pages and checks a filed declaration has no input; screenshots in
`Claude outputs/vat_phase1_20261022/screens_ka/`. Details: [`gec_vat_declaration.md`](gec_vat_declaration.md#the-pages-rebuilt-2026-10-22-to-look-like-rsge).

## 4. How the work was done (agent team)

| Step | Who | What it caught |
|---|---|---|
| Impact map, code tracing | ~12 Haiku scouts | core template merge order, install paths, fiscal-position map, Form 30 pattern, report API, rs_einvoice correction flow |
| Plan check before coding | Opus bug-hunter (×2) | Phase 0: noupdate function also runs on `--reinit` (→ post_init hook), removing positions would narrow taxes, tests passing for the wrong reason. Phase 1: **Generate would always fail** (`return_period` date), sync order, December cells, branch warning, copy/delete safety |
| Code | Sonnet builder (×2) | — |
| Independent review | Opus reviewer (×2) | Phase 0: chart reload half-repair, archived records. Phase 1: **margin row below cost lowered VAT** (portal counts 0), warnings not refreshed on Save, test gaps |
| Proof of findings | Opus verifier | Confirmed the margin rule from the portal's own JavaScript |
| Runs | me | scratch DBs, negative-control test runs (tests fail on the old code), prod1 before/after SQL |

Docs updated: [`l10n_ge.md`](l10n_ge.md), [`taxes_quick_guide.md`](taxes_quick_guide.md), [`l10n_ge_vat_report.md`](l10n_ge_vat_report.md) (Georgian),
[`gec_vat_declaration.md`](gec_vat_declaration.md) (new), [`vat_declaration_build_plan.md`](vat_declaration_build_plan.md),
[`vat_declaration_technical_design.md`](vat_declaration_technical_design.md), [`INDEX.md`](INDEX.md), gec_localization `README.md` / `README_DEV.md`,
`.claude/skills/odoo-dev/references/coupling-map.md` (T13, T14) and `fields.md` (recompute pitfall).

---

## 5. Issues and open items

### To do next (nothing blocks them)
| # | Item | Why |
|---|---|---|
| 2 | **Install Phase 1 on gec20_prod1** so it can be tried | Not installed yet |
| 4 | **19.0 backport** of Phase 0 (and later Phase 1) | Standing rule: every fix goes to both branches |
| 5 | Drop scratch DB `gec20_vat_p1_test` with its filestore | When Phase 1 is closed |

### Known issues
| # | Issue | Impact | Status |
|---|---|---|---|
| 6 | prod1: 30 open sales-order lines and 5 draft invoice lines still carry the old wrong taxes | Invoicing those orders copies the old taxes | Advice: leave (test records); ask if they must be recomputed |
| 7 | prod1: old test invoices sit on tag 2 (`18% S`) | A prod1 Generate of Sep/Oct shows ა I row 1 empty and a margin warning | Expected, not a bug |
| 8 | Import VAT booked as a **journal entry** with `18% EX ONLY` still doubles | Journal entries ignore Included in Price | Rule: book customs VAT as a vendor bill |
| 9 | Foreign bills without a vendor default get **no VAT tax** (D2) | Missed reverse charge if the default is not set | Monthly review; Phase 2 warning planned |
| 10 | rs_einvoice: a correction created in one month and accepted in the next is counted twice in the first month by Odoo's own VAT Report | Declaration must follow Q9 = B | Phase 2 (design step 3 rule written) |
| 11 | rs_einvoice has **no tests** for the Credit Note window and the correction chains | Phase 2 relies on them | Propose tests before Phase 2 |
| 12 | "Only correct Odoo" credit notes with reasons Other / Netting / Down Payment can carry VAT rs.ge never sees | Odoo VAT lower than rs.ge | Phase 2 warning |
| 13 | Cancel & Reissue: the new invoice keeps its creation date even if posted next month | Possible wrong month | Check in Phase 2 |
| 14 | Waybill → invoice wizard ignores the contact's Default Sales Tax on lines without a sale order | Rare wrong tax | Separate small rs_base_methods item |
| 15 | "Replaces" field now visible on the 10 domestic sale taxes | Cosmetic | None |

### Not sure / unverified (idk)
| # | Item | Why unsure |
|---|---|---|
| 16 | Portal rounding `round_2` assumed half-up | Its code is not in the portal capture; a 0.01 difference is possible on exact half-tetri |
| 17 | Portal sums ა III row 4¹ two different ways (page load vs edit) | Our form follows the edit-time sum; check cell 11 on the portal when row 4¹ has a value |
| 18 | Does an **adjusted** (დაზუსტებული) declaration also fill ბ I by itself? | The captured September adjusted declaration showed ბ I empty; ask the accountant |
| 19 | December cells 19-20 of Part III | Not in the captured (September) form; need a December capture |
| 20 | Q1 (advances `18% AD`), Q8 (monthly Tax Return card) | Still open in the plan, needed for Phase 5 |

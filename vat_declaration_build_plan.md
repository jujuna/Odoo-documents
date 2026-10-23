# VAT Declaration (დღგ-ის დეკლარაცია) — build plan: own form, all 18 portal tabs

> **Module:** Phase 0 built and committed (`gec_localization`, `92a35f7`), Phase 1 built and committed (`gec_vat_declaration`, `4daad73`,
> not pushed) — 2026-10-22. Plan of 2026-10-21, revised after the portal, module and web research |
> **Target:** module `gec_vat_declaration` (`gec.vat.*`, renamed from `gec_vat_report` / `rs.vat.*`) on the Form 30
> pattern + Phase 0 data fixes in `gec_localization`. Supersedes [`vat_declaration_annex_a_plan.md`](vat_declaration_annex_a_plan.md).

**Progress and open items: [`vat_declaration_completed.md`](vat_declaration_completed.md)** — what is done, how, the
decisions taken, and every known issue and unverified point.

Read with it:
- [`vat_declaration_technical_design.md`](vat_declaration_technical_design.md) — **how** to build it small: ten decisions, models, the Generate algorithm, export, attach, views, security, effort.
- [`vat_declaration_rs_portal_pages.md`](vat_declaration_rs_portal_pages.md) — every portal tab, cell id, locked-cell formula, grid column and help text (generated from the portal DOM).
- [`vat_declaration_research_2026.md`](vat_declaration_research_2026.md) — rules 2025-2026 with sources, how the portal fills annex ბ, and the module facts the design rests on.

Sources: the e-form guide `01_decl_info_845.pdf`, MoF Order #996 Art. 75 `01_instr_845.pdf`, the portal DOM `rs_pages.html`,
the rs.ge API notes `rs_invoice_api_docs.md`, and the web research above.

**Decision (user, 2026-10-21):** every one of the 18 tabs is built in Odoo as an own declaration form like Form 30; tabs
1-3 are filled from Odoo's core VAT Report, the rest are added by us. The earlier idea (Part III as extra report lines,
annex ბ as a plain list) is dropped.

---

## Verdict in six lines

1. **[Certain] Tabs 1-3 exist as core `l10n_ge`'s VAT Report**; the form reads its totals through the report API
   (design T1), so Odoo's report and the form never disagree.
2. **[Certain] Those numbers are wrong on prod1 today** (six taxes on every B2B sale, three reverse-charge taxes on a
   foreign bill). Phase 0 fixes the inputs first.
3. **[Certain] Annex ბ I / II fill themselves:** the portal attaches confirmed invoices to a new declaration
   automatically (accountant, X2, 2026-10-22). Odoo does not attach by API (no test company, X4); it lists the rows
   only to compare with the portal.
4. **[Certain] The locked cells follow fixed formulas** copied from the portal JavaScript; the form recomputes them the
   same way (design T3), so Odoo shows what the portal will show, to the lari.
5. **[Certain] Corrections are declared from the rs.ge chain** (design T7): a cross-month Correct & Reissue is one delta
   into Part III cell 7 or 6, never two documents.
6. **[Certain] Waybills carry no VAT data**; not an input. From 1 October 2026 the buyer side must confirm or reject
   received invoices before the 5th of the next month (research notes §2): the buyer inbox and crons of `rs_einvoice`
   become part of the monthly routine.

---

## Architecture in one table (details in the technical design)

| Piece | Choice |
|---|---|
| Module | `gec_vat_report`, depends `gec_localization`, `account_reports`, `rs_einvoice` |
| Numbers for tabs 1-3 | core VAT Report through `get_options` + `_compute_expression_totals_for_each_column_group` |
| Cells | `rs.vat.cell` catalog (CSV, code = portal id) + `rs.vat.cell.line` values; computed / proposed / typed as Form 30 |
| Formulas | ~30 lines of Python from the portal JS, incl. `floor` for cells 17 / 18 |
| Rows | 8 thin models: invoice rows (ბ I/II), advance links, customs rows, one `ref.line` model for ბ IV/V/VII/VIII/IX/X, petrol invoices, petrol balances, tourist rows |
| UI | plain editable lists, one notebook page per portal tab, no JavaScript |
| Out to rs.ge | nothing for ბ I/II (the portal attaches them); xlsx per grid for tabs 6-15, 18 later (Phase 6) |
| Validations | warnings only; no posting hooks; no constraint beyond the catalog's unique code |

---

## Phase 0 — make the inputs right (prerequisite, nothing else is worth testing before it)

All items are config/data; three are specified in
[`L10N_GE_VAT_MAPPING_REPAIR_PLAN.md`](../custom_addons/gec_odoo_modules/gec_localization/docs/L10N_GE_VAT_MAPPING_REPAIR_PLAN.md).
Status 2026-10-22: **fixes 1-3 built** in `gec_localization`, uncommitted. They come from the chart template
([template_ge.py:58](../custom_addons/gec_odoo_modules/gec_localization/models/template_ge.py#L58)), are repaired once at
install and after every `ge` chart load
([:87](../custom_addons/gec_odoo_modules/gec_localization/models/template_ge.py#L87)), and are never applied on upgrade. 6 tests
pass and each fails without its fix. Fix 5 is applied on gec20_prod1 (with fixes 1-3, by the same method through odoo shell);
fix 4 moved out; fix 6 is open (operational). Details: [`l10n_ge.md`](l10n_ge.md#corrections-to-l10n_ges-vat-taxes).

| # | Fix | Where | Evidence |
|---|---|---|---|
| 1 | Change A+B: drop the nine "Replaces" edges (18% → S, AD, O, EXT F, EXT L, EXT O; purchase 18% → R C S, R C G C, R C G F). Keep 18% → 0% EX. | `template_ge.py`: core hook `_get_account_tax` ([chart_template.py:1137](../addons/account/models/chart_template.py#L1137)) + one guarded method in `_ge_gec_apply_maintenance` | prod1 `account_tax_alternatives`: 9 of 9 edges present; `map_tax` keeps every destination ([partner.py:106-112, 169-173](../addons/account/models/partner.py#L106)) |
| 2 | Change C: add positions `nonvat` and `domestic` to the ten sale taxes so a contact without Tax ID keeps 18% | same methods, `Command.link` | prod1: positions 4 and 6 have no tax memberships |
| 3 | Change D: `price_include_override = tax_included` on `18% / 12% / 5% EX ONLY` (import bill of 180 otherwise posts 360) | same methods | prod1 taxes 31, 33, 35: division 100 %, override NULL |
| 4 | **Moved out of Phase 0 (2026-10-22).** The waybill → invoice wizard already remaps product lines by the fiscal position after create, so with fix 1 a VAT-registered customer gets one 18%; contacts without Tax ID are refused. Left: on lines without a sale order it ignores the contact's Default Sales Tax and Not Taxed, and rs_base_methods does not depend on gec_localization. Separate follow-up | [rs_invoice_from_waybill_wizard.py:224-229, 329-360, 509-515](../custom_addons/gec_odoo_modules/rs_base_methods/wizards/rs_invoice_from_waybill_wizard.py#L509) | scout 2026-10-22 |
| 5 | prod1 only: `res_company.domestic_fiscal_position_id` is NULL, so the tax pickers hide 18%. Recompute on a clone first. | data | prod1 query 2026-10-21 |
| 6 | Operational, no code: enable the `rs_einvoice` buyer sync and status crons (shipped inactive) or run the buyer inbox before the 5th of each month, for the 1 October 2026 confirmation rule | [ir_cron.xml:19-57](../custom_addons/gec_odoo_modules/rs_einvoice/data/ir_cron.xml#L19) | research notes §2 |

Decided 2026-10-22: **D1** Change C covers all ten sale taxes. **D2** no automatic reverse charge; vendor default
purchase tax `18% R C S`. **D3** the code is right for a fresh install only (no upgrade-time rewrite); the local
gec20_prod1 is repaired once by SQL; no other database (VPS, horeca) is touched. Four tests in `gec_localization`
cover the four cases below.
Done when a scratch DB shows 1,000 / 180 on a B2B sale and on a no-Tax-ID sale, one reverse-charge tax on a foreign
service bill, 180 on an import bill of 180.

---

## Phase 1 — module skeleton and the five cell tabs (1, 2, 3, 16, 17)

**Status 2026-10-22: built**, committed `4daad73`: module `gec_vat_declaration` (models `gec.vat.*`, renamed from
`gec_vat_report` / `rs.vat.*` to avoid Odoo's `l10n_ge_*` names), 109 cells, 5 pages (the other tabs come with their
phases), Save recomputes, 10 tests pass on a scratch DB. How it works: [`gec_vat_declaration.md`](gec_vat_declaration.md).
Build plan with the bug-hunter's corrections: `Claude outputs/vat_phase1_20261022/PLAN.md`.

Design sections 2, 3.1, 3.2, 4 (steps 1, 2, 4, 6), 6. Deliverables: manifest, `rs.vat.declaration`, cell catalog CSV
(generated from the portal doc), cell lines, Generate with proposals from the core report and the portal formulas,
form with 18 pages (grid pages empty), list, menu, access rows, company rules.

Done when: on a scratch DB with Phase 0 and one posted month, cells 1, 2, 3, 5, 8, 11, 15-18 equal the portal's for the
same month; a typed cell 7 moves 16 and 17 / 18 exactly as the portal does; the capture's September values (975.60 /
5,420 / 500 / 475) reproduce from the same inputs.

---

## Phase 2 — ბ I, ბ II, advance sub-grids, ბ III (tabs 4, 5, 6)

Design sections 3.3, 4 (steps 3 and 5), 5. Rows from posted invoices and bills with their rs.ge series, numbers and
statuses; correction chains as one delta; advance links from `rs.einvoice.advance.settlement`; customs rows from bills
tagged `25(T)` (Bill Reference = assessment number); the Not Declared list and warnings.

**2b — Attach to rs.ge: dropped (2026-10-22).** The portal attaches confirmed invoices itself (X2) and there is no
test company to try `add_inv_to_decl` on (X4). Open: the captured September 2026 adjusted declaration showed ბ I empty;
confirm with the accountant that a correction declaration fills itself too.

Caveat [Certain]: prod1 holds 5 vendor bills with rs.ge ids and no customer invoice (2026-10-21); test data must be
filed from a test company.

Done when: ბ I rows of a month, AMOUNT − შესამცირებელი, equal Part III cell 1 of the same declaration (instruction §3¹);
Odoo's ბ I rows match the portal's ბ I of the same month.

---

## Phase 3 — manual grids ბ IV, V, VII, VIII, IX, X and ა IV (tabs 7-12, 18)

`rs.vat.ref.line` (one model, six list views), tourist rows, their effects on cells (ბ IX → Part III 10; tab 18 column 7 →
ა I 8; the caps as warnings). No spreadsheet export yet (Phase 6).

---

## Phase 4 — petroleum tabs 13, 14, 15

Thin rows and balances with the closing-balance formula. Last, only because every tab is wanted.

---

## Phase 5 — advances and the return card

- Advances (ა I cell 2, Part III 4¹): advance invoice carries `18% AD` (one override of `_prepare_invoice_line` in
  `gec_localization`, positive down-payment quantity only); the final invoice's deduction keeps `18%`; 4¹ typed. Needs Q1.
  The 1 September 2025 invoice-level link of advance and delivery invoices is already what `rs_einvoice` native attach does.
- Optional `account.return.type` for Georgia (monthly card, 15th deadline, closing entry): one data record in
  `gec_vat_report`, which already depends on `account_reports`. Needs Q8.

---

## Phase 6 — spreadsheet export and import (later, user 2026-10-22)

xlsx per grid (tabs 6-15, 18) in the portal's layout, for upload by the portal's import. Needs X1: one portal
**ექსპორტი** file per grid. Not started until the user asks.

---

## Not built, on purpose

| Item | Why |
|---|---|
| Own tag sums, report lines or a formula engine | one number source (core report) + 30 lines of Python |
| OWL widgets | the Form 30 ones are hard-wired to Form 30; plain lists suffice |
| Posting hooks, invoice locks, blocking checks | user's brief; the portal validates on upload and submit |
| Spreadsheet export of ბ I / II | the portal fills them from attached invoices; the API attaches |
| December cells (Part III 19-20, ა III rows 6 / 6¹ unlock) | not in the captured form; add from a December capture |
| Reverse-charge timing (Art. 66), excise on invoices (sent as 0), exempt-without-credit sent as zero-rated (G1) | separate `rs_einvoice` items, not declaration work |
| Portal lookups (TIN → name, declaration number → period, customs refresh) | server-side on rs.ge; typed here |

---

## Decisions and inputs needed before coding

| # | Item | Blocks |
|---|---|---|
| D1-D3 | Decided 2026-10-22 (Phase 0 section) | — |
| X1 | One portal export file per grid (tabs 6-15, 18) — deferred with the export | Phase 6 |
| X2 | Answered 2026-10-22: the portal attaches confirmed invoices to a new declaration automatically | — |
| X3 | Answered from gec20_prod1 2026-10-22: `rs_einv_series` holds `ეა-86`, `ეა-87` (`<code>-<NN>`); one `ეკ` without NN (move 561) | — |
| X4 | No test company: API attach dropped | — |
| Q1 | Advances carry `18% AD`? | Phase 5 |
| Q6 | ა III column 5 (fixed assets): typed, or split by account type? | Phase 1 cell map |
| Q8 | Monthly return card wanted? | Phase 5 |
| Q9 | (Rewritten 2026-10-22 after tracing rs_einvoice.) A Correct & Reissue / Cancel & Reissue creates a replacement **copy invoice** dated the day it is created, never a VAT credit note; the old invoice is cancelled when the buyer accepts in the same month, or reversed by a "replacement" credit note dated the acceptance day ([account_move_reissue.py:143-151, 206-215](../custom_addons/gec_odoo_modules/rs_einvoice/models/account_move_reissue.py#L143), [account_move_cancel.py:131-136, 169-178](../custom_addons/gec_odoo_modules/rs_einvoice/models/account_move_cancel.py#L131)). **Decided 2026-10-22 (user): a correction counts in the month the buyer accepts it.** Example: invoice 1,000 / 180 on 5 Oct, correction to 700 / 126 sent 30 Oct, accepted 2 Nov → October declares 1,000 / 180, November Part III cell 7 = 54. Implemented in the declaration's Generate (design step 3), not in rs_einvoice's dates. | Phase 1-2 |
| M1 | Module name `gec_vat_report`, model prefix `rs.vat.*` | Phase 1 |

---

## Evidence used (2026-10-21, two agent rounds)

| # | Task | Result |
|---|---|---|
| 1-9 | first round: our VAT docs, core `l10n_ge` data, `rs_einvoice`, `rs_waybill`, custom VAT code, repair status, core report mechanics, Form 30 pattern, portal DOM | see the portal doc and the first version of this plan |
| 10 | `gec_localization` deep map | tax defaulting precedence, maintenance hook, 22 core overrides, no tests ([research §4](vat_declaration_research_2026.md)) |
| 11 | `rs_einvoice` deep dive | payload VAT rule, advances, header write-back, chains, buyer pull taxes, statuses, views, 12 tests, crons inactive |
| 12 | `rs_waybill` + `rs_base_methods` | wizard taxes, credentials per user and company, no VAT on waybills |
| 13 | core building blocks | `get_options` keys, totals shape, `amount_tax_signed`, xlsx download, list syntax, constraints, return type |
| 14 | Form 30 widgets and code skeleton | widgets not reusable without copy; model, sync and export code quoted for the pattern |
| 15 | web research | portal attachment mechanism (2010 manual, API, rs.ge service), 1 Sep 2025 advance rule, 1 Oct 2026 confirmation rule, deadlines, Order 996 amendments 2026 |

Agents: 15 Haiku scouts, 3 web-fetch agents, 0 builders, 0 Opus reviewers (plan only).

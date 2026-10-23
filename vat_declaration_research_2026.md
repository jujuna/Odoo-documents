# VAT declaration — research notes, rules and sources (2025-2026)

> **Status:** research of 2026-10-21, nothing built | **Companions:** [`vat_declaration_build_plan.md`](vat_declaration_build_plan.md),
> [`vat_declaration_technical_design.md`](vat_declaration_technical_design.md), [`vat_declaration_rs_portal_pages.md`](vat_declaration_rs_portal_pages.md).
> Each fact carries its source and a confidence tag. Web pages were read on 2026-10-21; quotes are verbatim.

---

## 1. How the portal fills annex ბ (the question that shapes the module)

**Answer [Likely]:** annex ბ I / II are the e-invoices **attached to the declaration number**, not an upload and not a
figure the accountant types. Attachment is an action on confirmed invoices (portal button, or the API call), and the
declaration's registers then show them. The grids keep a manual add row and a spreadsheet import for paper invoices and
corrections.

Evidence:
- Revenue Service IT Centre manual of the e-invoice system (December 2010, 21 pages, `revenue.mof.ge/RTOS/DOCS/manual.pdf`,
  text extracted locally): after the buyer confirms, the invoice gets a mark that lets the seller "პარალელურად მოვახდინოთ
  აღნიშნული ა/ფაქტურის მიბმა დღგ-ს დეკლარაციის შესაბამის რეესტრებთან"; in the register "დეკლარაციაზე მისაბმელი" one
  picks the year and month, marks the invoices and clicks "დეკლარაციაზე მიბმა"; the declaration number then appears on
  the invoice and "ა/ფაქტურები ამ ნომრით რეგისტრირებული დღგ-ს დეკლარაციის შესაბამის რეესტრებში ავტომატურად მიებმება
  (დაფიქსირდება)"; paper invoices can be typed in the same register; a wrong attachment is removed with a delete button;
  after the declaration is submitted the invoice shows "გადაგზავნილია დეკლარაცია". The same steps apply to corrective
  invoices (p. 20-21). [Certain for the 2010 text; Likely still the mechanism]
- The SOAP API (PDF v3.0.5, 2026-05-06, live-checked): `get_seq_nums(sag_periodi)` returns the period's declaration
  numbers, `add_inv_to_decl(user_id, seq_num, inv_id)` attaches an invoice, `get_decl_date(decl_num, un_id)` returns a
  declaration's period, `get_invoice` returns `seq_num_s` / `seq_num_b` (seller's and buyer's declaration number) and
  `dec_status` ([rs_invoice_api_docs.md:199-227, 772-825](../rs_invoice_api_docs.md)). [Certain]
- rs.ge service "დღგ-ს დეკლარაციაში დანართების ცვლილება" (eservices.rs.ge, p=198) exists "პირთათვის, რომელთაც სურს …
  დღგ-ს დეკლარაციის დანართებში არასწორად მიბმული ანგარიშ-ფაქტურების … ცვლილების განხორციელება", and the taxpayer
  rating panel lists "გამოწერილი და დადასტურებული ანგარიშ-ფაქტურების ან/და სპეც ანგარიშ-ფაქტურების დეკლარაციაზე
  მიუბმელობა" as a negative factor. [Certain]
- The captured September 2026 adjusted declaration shows 0 rows in ბ I with an add row and an xlsx import
  ([portal doc, tab 4](vat_declaration_rs_portal_pages.md)). [Certain]
- Not found anywhere: an official text saying the annexes fill themselves without the attach step, or the spreadsheet
  template. The rs.ge usage guide of the service and the 2019 brochure's declaration module instruction load by script
  or are images; the balance.ge guide that names a "დეკლარაციაზე მიბმის სტატუსი" field returned 403.

Consequence for the design: Odoo attaches by API (design T8) and keeps spreadsheets for the manual grids. Still to
verify live, on a test taxpayer: that `add_inv_to_decl` works on a primary declaration and whether the portal attaches
confirmed invoices by itself on creation (input X2/X4 in the plan).

---

## 2. Rules in force or announced, 2025-2026

| Date | Rule | Source | Effect on us |
|---|---|---|---|
| since 2019 (unchanged) | VAT return and payment by the **15th** of the month after the period; reverse-charge VAT is charged and credited in the same declaration | RS brochure 2019 ("არაუგვიანეს საანგარიშო პერიოდის (თვის) მომდევნო თვის 15 რიცხვისა"); ibccs.tax 2026; gegidze 2026 [Certain] | return deadline if a return card is ever added |
| 1 Sep 2025 | Advance and delivery invoices are linked **at invoice level**: "საქონლის/მომსახურების მიწოდების ანგარიშ-ფაქტურაშივე მოხდება მასთან დაკავშირებული ე.წ ავანსის ანგარიშ-ფაქტურის რეკვიზიტების მითითება"; applies to invoices issued from that date | Kreston, 7 Aug 2025, amendment to Order 996 [Certain]; API v3.0.5 advance methods [Certain] | matches `rs_einvoice` native attach (`attach_advance_invoice`, `update_advance_invoice`) and the annex ბ sub-grid; the advance pairing in the declaration annex is the old way |
| 1 Oct 2026 | Timely **confirmation or rejection** of received invoices: if a received საფ/ნსაფ is still pending on the 5th of the month after the period, the taxpayer and sub-users lose portal services except the invoice modules until they act; the Revenue Service also expects advance invoices to be confirmed in time so the buyer can credit the VAT; a voluntary trial with SMS notices ran before | Revenue Service statement via Sputnik 7 Jul 2026; ibccs.ge 17 Aug 2026 ("ცვლილება ამ ეტაპზე კანონმდებლობაში ჯერ არ ასახულა"); ibccs.tax Sep 2026 [Certain for the statements; no legal act found] | the buyer side matters now: the `rs_einvoice` buyer inbox and the buyer crons (all `active = False` by default, [ir_cron.xml:19-57](../custom_addons/gec_odoo_modules/rs_einvoice/data/ir_cron.xml#L19)) should run monthly before the 5th |
| 4 Feb 2026 | Order N2243 (RS head): fine relief on late VAT registration if the declaration is filed by the Tax Code deadline (15th) | Kreston Feb 2026 [Certain] | none for the form |
| 1 Jan 2026 | Investment gold supply and import exempt with credit (Law 1061-IVმს-XIმპ, 14 Nov 2025); real-estate exemption with credit kept until 1 Jan 2029; import VAT base rule kept until 2028 | Kreston Nov 2025, Mar-Apr 2026 [Certain] | taxes exist (0% EXT lines); no form change |
| 2026 (Feb, Aug) | Order 996 amended by N33/N34, N52, N253: profit-tax declaration, market-organisation chapter removed; nothing on the VAT form in the summaries read | Kreston Feb, Aug, Sep 2026 [Certain for the summaries] | the form captured on 2026-10-21 is the one to build; Art. 75 text in hand is dated 2024-02-13 |
| 4 Nov 2025 | Order №24351: receivables and paid advances treated as salary only for non-residents (income tax) | Kreston Nov 2025 [Certain] | not VAT |

Not found: a 2025 or 2026 change to electronic waybills (search returned only the pyrotechnics e-waybill rule from
1 Jan 2026, customs side); a 2026 change of the VAT declaration form.

---

## 3. Law points the form relies on (from the instruction and the Tax Code)

- Art. 75 of Order 996 (consolidated text of 2024-02-13, in `01_instr_845.pdf`): cross-references between annex ა and
  Part III (§3), the invoice floor for ა I cells 1-3 (§3¹), the caps for ა III cells 3, 4¹, 7, 8 and Part III cell 7
  (§3⁴, §3⁵), December-only cells 19-20 and ა III 6 / 6¹ (§5, §3⁵), advance example (§5¹), annex ბ parts (§5¹-§7⁷).
- Tax Code Art. 179 (adjustment of the taxable amount) with Order 996 Art. 73¹: an adjustment is declared in the
  period it happens; without a corrective invoice it goes through annex ბ VIII / IX, with one through the invoice
  registers and Part III cells 6 / 7 (9 / 10 for reverse charge). [Certain from the instruction text]
- Art. 163 tax point for advances; Art. 172-173 exemptions; Art. 176 credit; Art. 161¹ auctions (ბ IV); Art. 164¹
  customs warehouse and FIZ (ა II 2-3).
- Corrector semantics: a `k_invoice` is a new version of the invoice (original → status 3, corrector → 8, next
  correction on the last confirmed corrector) ([rs_invoice_api_docs.md:405-445](../rs_invoice_api_docs.md)). Odoo's
  `l10n_ge_edi` k4 sends the returned quantities and is therefore wrong; ours sends the new totals.

---

## 4. Our modules, the facts the design rests on

### gec_localization
- Tax defaulting precedence as coded ([account_tax.py:49-68](../custom_addons/gec_odoo_modules/gec_localization/models/account_tax.py#L49)):
  `not_taxed` product → no taxes; contact default (sale: `property_sale_tax_id`; purchase: `_gec_partner_purchase_tax`)
  replaces product taxes; a withholding default is added to the VAT for a VAT payer, replaces it otherwise; a VAT or
  0 % default is remapped by the fiscal position; order lines and invoice lines call the same helper.
- `_ge_gec_apply_maintenance` loads missing template records per company and never rewrites existing ones
  ([template_ge.py:37-72](../custom_addons/gec_odoo_modules/gec_localization/models/template_ge.py#L37)); the repair plan's
  changes A-D are not in it; it runs on every install and upgrade (`data/ge_tax_maintenance.xml`).
- 22 overrides of core methods, 0 automated tests, no `account.report` reference; the only tagged custom tax is the
  reverse-charge "Form III-19" purchase tax (21(B) / 21(T)).
- Docs drift: [`l10n_ge.md:391`](l10n_ge.md) says the CIT wizard debits 530110 by default (no default in code); the
  "Decisions" table has D1-D5 and D8 only.

### rs_einvoice
- Payload: per line `full_amount` = |price_total| in GEL, `vat_amount` = |price_total − price_subtotal| when the line has
  a tax, `−1` when it has none, so a 0 % tax sends `0` (zero-rated) and no tax sends `−1` (untaxed)
  ([account_move_sync.py:579-612](../custom_addons/gec_odoo_modules/rs_einvoice/models/account_move_sync.py#L579)); exempt-without-credit
  taxes therefore file as zero-rated (open item G1).
- Advances: `rs_einv_is_advance` set at create when every product line is a down payment; settlement mode auto-switches to
  `native_attach` when eligible; `rs.einvoice.advance.settlement` rows hold the attached VAT per advance
  ([account_move.py:819-841](../custom_addons/gec_odoo_modules/rs_einvoice/models/account_move.py#L819), [account_move_seller.py:472-674](../custom_addons/gec_odoo_modules/rs_einvoice/models/account_move_seller.py#L472)).
- Header write-back stores series (raw), number (cleaned), `seq_num_s/b`; the rs.ge operation date is not stored, the
  month comes from `invoice_date` ([account_move_sync.py:47-57](../custom_addons/gec_odoo_modules/rs_einvoice/models/account_move_sync.py#L47), [account_move.py:387-392](../custom_addons/gec_odoo_modules/rs_einvoice/models/account_move.py#L387)).
- Chains: Correct & Reissue copies with `include_business_fields` (sale links kept), original cancelled or reversed after
  status 8; a correction of a confirmed correction is possible, the base is the last status-8 corrector
  ([account_move.py:1404-1451](../custom_addons/gec_odoo_modules/rs_einvoice/models/account_move.py#L1404)).
- Buyer side: pulled lines get the company's 18 % purchase tax when `drg_amount > 0`, otherwise no tax and gross price;
  the fiscal position and the contact default are not applied ([account_move_sync.py:663-698](../custom_addons/gec_odoo_modules/rs_einvoice/models/account_move_sync.py#L663)).
- Tests: 12 methods; none covers corrections, advances, buyer pull lines or payload VAT. Crons for buyer sync and status
  refresh are shipped inactive.
- Views: no list columns and no search filter for rs.ge series, number or status (gap G3 stands).

### rs_waybill and rs_base_methods
- Waybills carry no tax amounts and no invoice link; `vat_type` is a 0/1/2 code from `account.tax.rs_vat_type`, which is
  `0` on every prod1 tax ([stock_picking.py:339-373](../custom_addons/gec_odoo_modules/rs_waybill/models/stock_picking.py#L339)).
- The invoice-from-waybill wizard sets `tax_ids` explicitly (sale line taxes, else product taxes) so `gec_localization`'s
  contact default never runs; it does remap through the fiscal position after create
  ([rs_invoice_from_waybill_wizard.py:329-360, 509-515](../custom_addons/gec_odoo_modules/rs_base_methods/wizards/rs_invoice_from_waybill_wizard.py#L329)).
  No test covers the wizard.
- rs.ge credentials are per user and company (`res.users.settings`), a company's "RS Responsible User" serves crons
  ([res_users.py:195-208](../custom_addons/gec_odoo_modules/rs_base_methods/models/res_users.py#L195)); the same lookup serves
  the declaration's attach button.
- Excise is sent as 0 on every invoice line (TODO at [rs_soap_service.py:365-367](../custom_addons/gec_odoo_modules/rs_einvoice/models/rs_soap_service.py#L365)).

### Core blocks confirmed for the design
- `account.report.get_options(previous_options)` with `date = {date_from, date_to, period_type: 'custom'}` and
  `allowed_company_ids` in context; `_compute_expression_totals_for_each_column_group(expressions, options)` → index 0 →
  `{expression: {'value': …}}` ([account_report.py:995-1029, 1642-1652, 3601-3656](../enterprise/account_reports/models/account_report.py#L995); [account_return.py:1922-1943](../enterprise/account_reports/models/account_return.py#L1922)).
- `amount_tax_signed` is the company-currency VAT of a move ([account_move.py:592-595, 1260](../addons/account/models/account_move.py#L592)).
- Binary + `ir.actions.act_url` download, `xlsxwriter` in-memory workbook ([hr_payroll_payment_report_wizard.py:48-49, 178-179](../enterprise/hr_payroll/wizard/hr_payroll_payment_report_wizard.py#L48); [account_report.py:7822-7843](../enterprise/account_reports/models/account_report.py#L7822)).
- Editable lists with `readonly="<field>"` and `column_invisible` in 20.0 ([account_move_views.xml:1549-1594](../addons/account/views/account_move_views.xml#L1549)); `models.Constraint` replaces `_sql_constraints` ([partner.py:340-341](../addons/account/models/partner.py#L340)).
- `account.return.type` is enterprise-only; a country record needs `report_id`, `country_id`, deadline fields
  ([account_return_data.xml:4-9](../enterprise/l10n_at_reports/data/account_return_data.xml#L4)).

---

## 5. Still open

| Id | Question | Who |
|---|---|---|
| X1 | One portal export file per grid (tabs 6-15, 18) for the spreadsheet layout | user |
| X2 / X4 | Does a primary declaration attach confirmed invoices by itself, and does `add_inv_to_decl` work from the API on one? Test on a test taxpayer | user + dev |
| X3 | Real `rs_einv_series` values on filed invoices (the portal wants `<code>-<NN>`) | SQL on a DB with filed invoices |
| D1-D3 | Mapping repair decisions (Phase 0) | user |
| Q1 | Advance invoices carry `18% AD` | accountant |
| Q6 | ა III column 5 (fixed assets) typed, or split by account type | accountant |
| Q8 | Monthly return card wanted | user |
| Q9 | Same-month credit notes: netted in ა I (design assumption) or declared in cell 7 | accountant |
| G1 | `rs_einvoice` sends exempt-without-credit lines as zero-rated | dev, separate fix |

---

## 6. Sources read

- rs.ge: `eservices.rs.ge/ServiceRequestNew.aspx?p=198`; `rs.ge/ServicesCatalog?…guid=2849F970…` (script-loaded, empty);
  `rs.ge/Legislation?cat=4&tab=1` (script-loaded); brochure `rs.ge/Media/Default/Images/Brochures/დღგ_11.10.2019.pdf`
  (text extracted); manual `revenue.mof.ge/RTOS/DOCS/manual.pdf` (2010, text extracted); `e.rs.ge/app/VideoHelp?video=450`
  (title only); `infohub.rs.ge/…/6c300407…` (title only).
- Kreston Georgia monthly summaries: Nov 2025, Feb 2026, Mar-Apr 2026, Aug 2026, Sep 2026; article of 7 Aug 2025 on the
  invoice rule; statement of 23 Sep 2026.
- ibccs.ge post of 17 Aug 2026 and ibccs.tax guide (Sep 2026); gegidze guide (Oct 2026); Sputnik Georgia 7 Jul 2026;
  bm.ge 11 Nov 2022 (project stage of the advance rule).
- matsne.gov.ge document 1339213 (Order 57 of 2005, repealed 2007; not the current instruction).
- In the repo: `rs_invoice_api_docs.md` (API v3.0.5 + live checks), `01_instr_845.pdf` (Art. 75), `01_decl_info_845.pdf`,
  `rs_pages.html` (portal DOM).
- Extracted texts kept for re-reading (outside git): `Claude outputs/vat_portal_20261021/sources/` — the 2010 manual, the
  2019 brochure, Art. 75, the e-form guide, and Odoo's `l10n_ge_edi` PR diff.

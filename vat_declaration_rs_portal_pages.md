# rs.ge VAT declaration portal — the 18 tabs, cell by cell

> **Source:** `rs_pages.html` (the portal wizard `decl.rs.ge/decls.aspx`, declaration N 76819693, 2026/09, type
> "დაზუსტებული"), captured 2026-10-21 as 18 copies of the wizard DOM, one per tab; parsed with a script, not retyped.
> **Companion of:** [`vat_declaration_build_plan.md`](vat_declaration_build_plan.md) (what we build and in which order).
> Every label, help text, portal id and formula below is copied from the HTML. Judgements are tagged.

The captured account looks like a test taxpayer ([Likely]: the series list contains `კკკკკ`, the authority-decision
list contains `ტესტ`, `AXALI`, `qqqqqqqqqqqqqq`); the form structure is the production form.

---

## 1. Tab map (portal numbering, not the PDF's)

The PDF guide numbers 15 pages; the live wizard has 18 steps. PDF page 9 (annex ბ VI, abolished) does not exist as a
tab; the petroleum tabs 13-15, the margin-scheme tab 17 and the tourist tab 18 were not numbered in the PDF.

| Tab | PDF page | Content | Kind | Inputs / locked | xlsx import | Odoo source of the data |
|---|---|---|---|---|---|---|
| 1 | 1 | ა I — დღგ-ით დასაბეგრი ოპერაციები, cells 1-15 | cell form (ctrl 355) | 34 / 12 | no | core VAT Report `ge_1`…`ge_20` |
| 2 | 2 | ა II — უკუდაბეგვრის წესით დარიცხული დღგ, cells 1-4 | cell form (ctrl 356) | 8 / 4 | no | `ge_21`…`ge_23` |
| 3 | 3 | ა III — დღგ-ის ჩასათვლელი თანხა, cells 1-9, three columns | cell form (ctrl 353) | 34 / 17 | no | `ge_24`…`ge_33` |
| 4 | 4 | ბ I — issued tax invoices (incl. corrections) + advance-offset sub-grid | grid + sub-grid | 13 + 5 fields | yes | customer invoices / credit notes with rs.ge ids, `rs.einvoice.advance.settlement` |
| 5 | 5 | ბ II — received tax invoices (incl. corrections) + advance-offset sub-grid | grid + sub-grid | 13 + 5 | yes | vendor bills / refunds with rs.ge ids |
| 6 | 6 | ბ III — customs declarations used for credit | grid, server-validated | 6 (3 locked) | yes | import-VAT bills (`25(T)` tag); numbers must exist in the customs system |
| 7 | 7 | ბ IV — Art. 161¹ auction / enforcement purchases | grid, TIN lookups | 9 (2 locked) | yes | none (typed) |
| 8 | 8 | ბ V — barter before 2021 | grid, declaration lookup | 7 (2 locked) | yes | none (typed) |
| 9 | 10 | ბ VII — tax/customs authority decisions on import VAT | grid, decision dropdown | 5 (1 locked) | yes | none (typed; decisions come from rs.ge) |
| 10 | 11 | ბ VIII — turnover reduction without corrective invoice | grid, declaration lookup | 5 (1 locked) | yes | none (typed) |
| 11 | 12 | ბ IX — reverse-charge reduction | grid, declaration lookup | 5 (1 locked) | yes | none (typed); **feeds Part III cell 10** |
| 12 | 13 | ბ X — reverse-charge VAT creditable after registration | grid, calculation lookup | 5 (1 locked) | yes | none (typed) |
| 13 | — | ბ II¹ — issued petroleum invoices (ნსაფ) + advance sub-grid | grid + sub-grid | 16 + 5 | yes | none (no fuel trade) |
| 14 | — | ბ II² — received petroleum invoices (ნსაფ) + advance sub-grid | grid + sub-grid | 16 + 5 | yes | none |
| 15 | — | №III-10 — ფაქტიურად დარიცხული ნაშთები (petroleum stock balances) | grid | 25 (2 locked) | yes | none |
| 16 | 14 | Part III — დღგ-ის საერთო თანხის გაანგარიშება, cells 1-18 | cell form (ctrl 358) | 25 / 11 | no | computed from tabs 1-3 + typed cells |
| 17 | — | №III-19⁶ Part III — margin scheme (second-hand goods, art, collectibles, antiques) | cell form (ctrl 359) | 14 / 5 | no | none; **feeds ა I cell 1¹** |
| 18 | — | ა IV — tourist-enterprise status cancellation | grid | 8 (1 locked) | yes | none; **col 7 feeds ა I cell 8** (Art. 75 §3⁹) |

Cells 19-20 of Part III (December pro-rata) are not in tab 16 of this September declaration: [Likely] the portal adds
them only in the December form.

---

## 2. How a cell form works (tabs 1, 2, 3, 16, 17)

- Every cell is an `<input>` with id `control_<ctrl>_<row>[_<sub>][_<col>]` and attribute `x_name="COL_…"`.
  `ctrl` = 355 (ა I), 356 (ა II), 353 (ა III), 358 (Part III), 359 (III-19⁶). Example: `control_355_6_1_5` = ა I row 6¹,
  column 5 (VAT); `control_353_613` = ა III row 6¹, column 3.
- Editable cells have class `decl_input_t`; **locked cells have `readonly` and class `decl_input_tb`** and are written
  by the page's JavaScript (`control_<ctrl>_sum`). Numbers are rounded with `round_2` (2 decimals); Part III cells 17 and
  18 are additionally **truncated to whole lari with `Math.floor`**.
- Help text = the `title` attribute of the `?` icon (`ks_info_title`) in the row; copied verbatim in the tables below.
- ა I has a checkbox **"18%"** (checked by default). Checked: the VAT column of rows 1-8 is locked and computed as
  base × 18 / 100. Unchecked: those VAT cells become editable (for rounding differences against the invoices).
- The Part III header shows "დარიცხვა / შემცირება" (475 / 0 on the capture) = cells 17 / 18.

### Formulas the portal applies (verbatim logic, [Certain])

| Target | Formula |
|---|---|
| ა I `355_<r>_5` for r in 1, 2, 3, 4, 5, 6, 6_1, 7, 7_1, 8 | `round_2(355_<r> × 18 / 100)` while the 18% box is checked |
| ა I `355_1_1_5` (row 1¹) | `= 359_5` (margin-scheme total, tab 17); not 18% of anything |
| ა I `355_15` | `Σ VAT column of rows 1, 1¹, 2, 3, 4, 5, 6, 6¹, 7, 7¹, 8` |
| ა II `356_<r>5` for r in 1, 2, 3 | `round_2(356_<r> × 18 / 100)`; `356_4 = Σ` |
| ა III `353_<r>3` (column 3 = total) | `353_<r>4 + 353_<r>5` (col 4 goods/services VAT + col 5 fixed-asset VAT) for rows 1, 2, 3, 4, 4¹, 5, 6, 6¹, 7, 8 |
| ა III `353_93 / 94 / 95` | column totals of the ten rows above |
| Part III `358_1` | `Σ 355_{1,1_1,2,3,4,5,6,6_1,7,7_1,8}_5` (= ა I cell 15) |
| Part III `358_2` | `355_1 + 355_2 + 355_3 + 355_4 + 355_5 + 355_6 + 355_6_1 + 355_7 + 355_7_1 + 355_8` (row 1¹ base is **not** included) |
| Part III `358_3` | `355_9 + 355_10 + 355_11 + 355_12 + 355_13 + 355_14` |
| Part III `358_5` | `355_14_1 + 355_14_2 + 355_14_3` |
| Part III `358_8` | `356_15 + 356_25 + 356_35` (= ა II cell 4) |
| Part III `358_10` | server value `V_COL_10` of stored procedure 120 = the ბ IX amounts (tab 11 `control_357_ch`) |
| Part III `358_11` | `Σ 353_<r>3` for rows 1, 2, 3, 4, 4¹, 5, 6, 6¹, 7, 8 (= ა III cell 9) |
| Part III `358_15` | `358_1 + 358_6 + 358_8 + 358_9 + 358_12 + 358_14` |
| Part III `358_16` | `358_7 + 358_10 + 358_11 + 358_13` |
| Part III `358_17` | `floor(358_15 − 358_16)` when 15 > 16, else 0 |
| Part III `358_18` | `floor(358_16 − 358_15)` when 16 > 15, else 0 |
| III-19⁶ `359_<r>_5` | `round_2((359_<r>_4 − 359_<r>) / 1.18 × 0.18)` (sale price − purchase price, VAT inside); `359_5 = Σ` |

Typed Part III cells: 4, 4¹, 4², 4³, 4.4, 4.5 (turnover, informational), 6, 7, 9, 12, 13, 14, 14.1 (VAT). Cell 14.1 is a
sub-row of 14 and is not summed.

Locked for another reason: ა III rows 6 and 6¹, all three columns (`353_64/65`, `353_614/615`) — the help text points to
Art. 75 §5 (year-end declaration); [Likely] the portal unlocks them in December only.

### Odoo → portal cell map (for "Generate" in the own form)

Core report `l10n_ge.tax_report_ge` line codes ([account_tax_report_data.xml](../addons/l10n_ge/data/account_tax_report_data.xml)):

| Portal cell (editable base / amount) | Core line | Note |
|---|---|---|
| 355_1 … 355_8 (rows 1, 2, 3, 4, 5, 6, 6¹, 7, 7¹, 8) | `ge_1`, `ge_3`, `ge_4`, `ge_5`, `ge_6`, `ge_7`, `ge_8`, `ge_9`, `ge_10`, `ge_11` `.base` | VAT column is the portal's 18 %; Odoo's own `.tax` is shown beside it as a check |
| 355_1_1_5 (row 1¹) | `ge_2.tax` | only via tab 17 in the portal |
| 355_9 … 355_14 | `ge_12` … `ge_17` `.base` | exempt with credit; 355_13_1 ("of which" shortage) has no Odoo source |
| 355_14_1, 355_14_2, 355_14_3 | `ge_18`, `ge_19`, `ge_20` `.base` | exempt without credit |
| 356_1, 356_2, 356_3 | `ge_21`, `ge_22`, `ge_23` `.base` | reverse charge |
| 353_14, 353_24, 353_34, 353_44, 353_44_1, 353_54, 353_74, 353_84 (column 4) | `ge_24` … `ge_27`, `ge_28`, `ge_29`, `ge_32`, `ge_33` `.tax` | column 5 (fixed assets) has no core source: typed, or split later by account type (old Q6) |
| 353_64, 353_65, 353_614, 353_615 | `ge_30`, `ge_31` | locked on the portal except December |

---

## 3. How a grid works (tabs 4-15, 18)

- Three zones per grid: a **filter row** (dropdowns, from/to ranges, month pickers; not data), an **add row** (the
  data entry widgets, class `g_add_field`, each with the server column name `x_name`), and the stored rows with
  edit/delete icons, a page-size selector (3…300) and a pager.
- Widgets: `ksddl` dropdown (series code; when the code ends with `-` a 2-digit **series number** input next to it
  is enabled, giving `<code>-<NN>`, e.g. `ავ-01`; codes without `-` such as `ქთ`, `სტ`, `სკ` take no number);
  `number_z` integer inputs with min/max (`NOMERI` 0…9999999); `ksd_m` month picker (`ISSUE_DATE`, month + year);
  `kscombo` autocomplete that asks the server (`SA_IDENT_NO_PAIR` = counterparty TIN, min 3 chars; declaration
  numbers; assessment numbers; decisions); `ksdate` date pickers; plain `number` amounts (2 decimals, `data-m-dec=4`
  for petroleum quantities). Hidden per row: `ID`, `SEQ_NUM` (declaration number), `INV_TYPE` (1 on ბ I, 2 on ბ II).
- **Import** = `<form action="FileUpload.ashx" enctype="multipart/form-data">` with
  `<input type="file" accept="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet">`: every grid
  accepts one **xlsx** upload; the sub-grids (advance offsets) have export only. The accepted column layout is not in
  the HTML: **export one file per grid from the portal (ექსპორტი) before writing the Odoo export** (the export file is
  the template).
- Rows are server-validated where the add row uses a lookup: ბ III assessment numbers (customs system; date, VAT and
  customs code come back locked; "გრაფიკი" entries unlock date and amount), ბ VII decisions (dropdown of the taxpayer's
  decisions with date and amount), ბ V / VIII / IX / X registration numbers of the taxpayer's own prior declarations
  (period filled, locked), ბ IV TINs (name filled, locked). An xlsx row must carry values that pass the same lookups.
- Sub-grid "advance offsets" (ბ I, ბ II, ბ II¹, ბ II²): pick the delivery invoice (`INVOICE_ID`, autocomplete limited to
  this declaration's invoices), then the advance invoice (`INVOICE_ID_AV`, limited to advances linked to that invoice);
  the VAT amount `AMOUNT` is prefilled from the advance invoice label and can be edited.
- Grid totals that reach cells: ბ IX → Part III cell 10 (server); tab 17 → ა I cell 1¹; tab 18 column 7 → ა I cell 8
  (instruction §3⁹; the capture has no rows, so not observed); ბ VII / IV / V / X totals only **cap** ა III cells 3, 8,
  7, 4¹ (instruction §3⁵) and ბ I reduce + ბ VIII cap Part III cell 7.

### Grid columns and the Odoo field behind each (ბ I / ბ II)

| # | Column (portal) | `x_name` | Odoo source (customer invoice side; vendor side symmetric) |
|---|---|---|---|
| 1 | სერია | SERIA (code + 2-digit no.) | `account.move.rs_einv_series` (format to confirm against real values) |
| 2 | ნომერი | NOMERI | `rs_einv_number` |
| 3 | დასაბეგრი ოპერაციის განხორციელების თვე | ISSUE_DATE (month) | `invoice_date` month (`rs_einv_operation_month/year`) |
| 4 | მყიდველის/მიმღების ს/ნ (ბ II: მომწოდებლის ს/ნ) | SA_IDENT_NO_PAIR | commercial partner `vat` (`rs_einv_buyer_tin` / `rs_einv_seller_tin`) |
| 5 | დღგ-ს თანხა > გადასახდელი (incl. additional after correction) | AMOUNT | VAT of the move in GEL (18 % tax lines) |
| 6 | დღგ-ს თანხა > კორექტირების შედეგად შესამცირებელი | REDUCE_AMOUNT | VAT of credit notes / reducing corrections |
| 7-8 | ანგარიშ-ფაქტურა რომლის კორექტირებაც წარმოებს > სერია, ნომერი | KORECT_SERIA, KORECT_NOMERI | series/number of `rs_einv_replaces_id` or `reversed_entry_id` |
| sub | მიწოდების ფაქტურის სერია/ნომერი, ავანსის ფაქტურის სერია/ნომერი, თანხა | INVOICE_ID, INVOICE_ID_AV, AMOUNT | `rs.einvoice.advance.settlement` (`final_move_id`, `advance_move_id`, `vat_amount`) |

Other grids (one line each; full column lists in the tab sections below): ბ III = assessment number, customs code,
assessment date, VAT; ბ IV = document number, seller TIN + name, owner TIN + name, purchase date, VAT; ბ V =
declaration number, supplier TIN + name, period, VAT; ბ VII = decision number, decision date, VAT; ბ VIII / IX / X =
declaration (or calculation) number, period, VAT; ბ II¹ / II² = ნსაფ series, N, date; corrected ნსაფ series, N, date;
stationary registration N (dispatch, destination); counterparty TIN; product code; quantity in l and kg; VAT payable;
VAT reduced; №III-10 = product code + 11 quantity pairs (kg, l) with closing balance `12 = 3+4−5−6−8−10−11` computed;
ა IV = cadastral code, status dates, two amounts and `7 = max(5 − 6, 0)` computed.

---

## 4. What the HTML does not answer

1. The xlsx column order and header text per grid (not in the DOM) — needed before any export code.
2. Whether a **primary** declaration comes with ბ I / ბ II pre-filled from the e-invoice system. The capture (an
   adjusted declaration) shows 0 rows with manual add + import, so the accountant should open a primary declaration
   and look.
3. The exact format of `rs_einv_series` values stored by `rs_einvoice` versus the portal's `<code>-<NN>` convention.
4. Server validations behind `call_sp` (customs refresh 143, ბ IX total 120, ბ X 148): only their inputs and outputs are
   visible.
5. December-only cells (Part III 19-20, ა III rows 6 and 6¹).

---

## 5. Per-tab detail (generated from the HTML)

Columns in the cell tables: **Portal id** = the input id with its server column (`COL_…`) and whether it is editable or
locked; **Help text** = the `?` tooltip verbatim. Grid tables list the add-row fields in portal order with the widget
rules the portal enforces.


### Tab 1 — დანართი "ა" ნაწილი I დღგ-ით დასაბეგრი ოპერაციები

Type: cell form. Inputs: 34, locked: 12. Import: no.

| Cell | Label | Portal id (column, editable) | Editable | Help text (portal tooltip) |
|---|---|---|---|---|
|  | ოპერაციის შინაარსი / დასაბეგრი ბრუნვა | checkbox `18%` | locked |  |
| (1) | ანაზღაურების სანაცვლოდ საქონლის მიწოდება ან/და მომსახურების გაწევა | `control_355_1` (COL_1, yes)<br>`control_355_1_5` (COL_1_5, locked) | mixed | საანგარიშო თვეში 18%-იანი განაკვეთით დასაბეგრი ანაზღაურების სანაცვლოდ მიწოდებული საქონლის/გაწეული მომსახურების თანხების ჯამი, დღგ-ის გარეშე.ამასთან, თუ წინა საანგარიშო პერიოდებში მიღებული და დაბეგრილი ე.წ. ავანსის სანაცვლოდ მიმდინარე საანგარიშო პერიოდში ხდება საქონლის/მომსახურების მიწოდება, მაშინ შეიტანება სხვაობის თანხა.შენიშვნა: პირველი, მე-2 და მე-3 უჯრების ჯამი არ უნდა იყოს დაბეგვრაზე წარმოდგენილ, შესაბამის თვეში გამოწერილი საფ-ების მიხედვით დასაბეგრ ბრუნვაზე ნაკლები. |
| (1 1 ) | დღგ, სპეციალური სქემით (მარჟით) დასაბეგრ ოპერაციებზე | `control_355_1_1_5` (COL_1_1_5, locked) | locked | საანგარიშო პერიოდში სპეციალური სქემით დაბეგრილი ოპერაციების დღგ-ის თანხა. ავტომატურად გადმოიტანება დანართი №III-19 პრიმა 6-ის III ნაწილის მე-5 სტრიქონის (მე-5 სვეტის) ჯამური მონაცემი. |
| (2) | საქონლის მიწოდებამდე ან/და მომსახურების გაწევამდე ანაზღაურებული თანხა | `control_355_2` (COL_2, yes)<br>`control_355_2_5` (COL_2_5, locked) | mixed | საქონლის/მომსახურების მიწოდებამდე 18%-იანი განაკვეთით დასაბეგრი ოპერაციის მიხედვით მიღებული საკომპენსაციო თანხის/თანხის ნაწილის ჯამი, დღგ-ის გარეშე (ე.წ. „ავანსი“);ამასთან, ბარტერული ოპერაციის ფარგლებში წინასწარ მიღებული საქონელი/მომსახურება, ფულისგან განსხვავებით, ავანსად არ განიხილება.შენიშვნა: პირველი, მე-2 და მე-3 უჯრების ჯამი არ უნდა იყოს დაბეგვრაზე წარმოდგენილ, შესაბამის თვეში გამოწერილი საფ-ების მიხედვით დასაბეგრ ბრუნვაზე ნაკლები. |
| (3) | საქონლის უსასყიდლოდ მიწოდება, თუ ამ საქონელზე ან მასზე გაწეულ ხარჯზე დღგ სრულად ან ნაწილობრივ არის ჩათვლილი | `control_355_3` (COL_3, yes)<br>`control_355_3_5` (COL_3_5, locked) | mixed | უსასყიდლოდ მიწოდებული საქონლის შესყიდვის ფასი ამ ან ანალოგიურ საქონელზე,ან თუ ასეთი არ არსებობს - მისი წარმოების ფასი.შენიშვნა: პირველი, მე-2 და მე-3 უჯრების ჯამი არ უნდა იყოს დაბეგვრაზე წარმოდგენილ, შესაბამის თვეში გამოწერილი საფ-ების მიხედვით დასაბეგრ ბრუნვაზე ნაკლები. |
| (4) | საქონლის დანაკლისი | `control_355_4` (COL_4, yes)<br>`control_355_4_5` (COL_4_5, locked) | mixed | 18%-იანი განაკვეთით დასაბეგრი საქონლის დანაკლისის (მათ შორის, ინვენტარიზაციის შედეგების შესახებ საგადასახადო ორგანოს მიერ შედგენილი ოქმის შესაბამისად გამოვლენილი დანაკლისის) საბაზრო ფასი, დღგ-ის გარეშე (მიუხედავად იმისა, გასაჩივრებულია თუ არა ოქმის შედეგები გადამხდელის მიერ). |
| (5) | უსასყიდლოდ მომსახურების გაწევა დაქირავებული პირის პირადი სარგებლობისთვის ან საკუთარი საქმიანობის მიზნიდან განსხვავებული მიზნით | `control_355_5` (COL_5, yes)<br>`control_355_5_5` (COL_5_5, locked) | mixed | უსასყიდლოდ მომსახურების გაწევასთან დაკავშირებული ყველა დანახარჯის ღირებულება.შენიშვნა: ამ სტრიქონში არ შეიტანება სახელმწიფოსთვის ან/და მუნიციპალიტეტისთვის მომსახურების უსასყიდლოდ გაწევა. |
| (6) | საკუთარი წარმოების შენობის/ნაგებობის ძირითად საშუალებად გამოყენება თუ სხვა პირისგან შეძენის შემთხვევაში სრულად ან ნაწილობრივ შეიზღუდებოდა ჩათვლის უფლება | `control_355_6` (COL_6, yes)<br>`control_355_6_5` (COL_6_5, locked) | mixed | იმ შენობის/ნაგებობის წარმოების ფასი, რომლის ძირითად საშუალებად გამოყენება დაიწყო საანგარიშო პერიოდში. შენიშვნა: საკუთარ წარმოებად განიხილება დასაბეგრი პირის საკუთრებაში/მფლობელობაში არსებულ მიწის ნაკვეთზე შენობის/ნაგებობის მშენებლობა საკუთარი ძალებით ან/და სამშენებლო-სამონტაჟო მომსახურების შეძენის გზით. |
| (6 1 ) | საკუთარი ძირითადი საშუალების (შენობის/ნაგებობის) რემონტის განხორციელება, თუ ამ მომსახურების სხვა პირისგან შეძენის შემთხვევაში სრულად ან ნაწილობრივ შეიზღუდებოდა ჩათვლის უფლება | `control_355_6_1` (COL_6_1, yes)<br>`control_355_6_1_5` (COL_6_1_5, locked) | mixed | რემონტთან დაკავშირებული ყველა დანახარჯის ღირებულება. შენიშვნა: განხორციელებულად განიხილება ძირითადი საშუალების (შენობის/ნაგებობის) რემონტი საკუთარი ძალებით ან/და სარემონტო მომსახურების/სამუშაოების იმ პირისგან შეძენის გზით, რომელიც არ არის რეგისტრირებული დღგ-ის გადამხდელად. |
| (7) | საქონლის/მომსახურების გაცვლის (ბარტერული) ოპერაცია | `control_355_7` (COL_7, yes)<br>`control_355_7_5` (COL_7_5, locked) | mixed | აღნიშნული გრაფა ივსება იმ შემთხვევაში, როდესაც საქონლის მიწოდება/მომსახურების გაწევა განხორციელებულია 2021 წლის 1 იანვრამდე, ხოლო სანაცვლო საქონლის მიწოდება/მომსახურების გაწევა ხორციელდება 2021 წლის 1 იანვარს ან შემდგომ პერიოდებში. დღგ-ით დასაბეგრი ოპერაციის თანხა განისაზღვრება ამ ოპერაციის ფარგლებში მიწოდებული საქონლის/გაწეული მომსახურების საბაზრო ფასით, დღგ-ის გარეშე. |
| (7 1 ) | ეკონომიკური საქმიანობის შეწყვეტის შემდეგ საქონლის საკუთარ მფლობელობაში დატოვება ან დღგ-ის რეგისტრაციის გაუქმების შემთხვევაში ნაშთად დარჩენილი საქონელი, თუ ამ საქონელზე ან მასზე გაწეულ ხარჯზე დღგ სრულა | `control_355_7_1` (COL_7_1, yes)<br>`control_355_7_1_5` (COL_7_1_5, locked) | mixed | ეკონომიკური საქმიანობის შეწყვეტის შედეგად საკუთარ მფლობელობაში დატოვებული საქონლის ან დღგ-ის რეგისტრაციის გაუქმების მომენტში ნაშთად დარჩენილი საქონლის შესყიდვის ფასი ამ ან ანალოგიურ საქონელზე, ან თუ ასეთი არ არსებობს − მისი წარმოების ფასი, რომელიც დგინდება საქონლის დასაკუთრების (მფლობელობაში დარჩენის) ან დღგ-ის გადამხდელად რეგისტრაციის გაუქმების მომენტში. |
| (8) | სხვა დასაბეგრი ოპერაციები | `control_355_8` (COL_8, yes)<br>`control_355_8_5` (COL_8_5, locked) | mixed | 18%-იანი განაკვეთით დასაბეგრი სხვა ოპერაციები სსკ-ის 160-ე და 160¹ მუხლების შესაბამისად, გარდა წინა სტრიქონებზე შეტანილი ოპერაციებისა (მაგ. საწარმოს ან ამხანაგობის მიერ, შესაბამისად, პარტნიორისთვის ან ამხანაგობის წევრისთვის, წილის სანაცვლოდ საქონლის საკუთრებაში გადაცემა/მომსახურების გაწევა და სხვა). |
| (9) | საქონლის მიწოდება ან/და მომსახურების გაწევა საქართველოს საგადასახადო კოდექსის 172-ე მუხლის მე-3 ნაწილით გათვალისწინებულ პირთათვის | `control_355_9` (COL_9, yes) | yes | უცხოეთის დიპლომატიური წარმომადგენლობებისათვის, მათი წევრებისათვის მიწოდებული საქონლის/მომსახურების ღირებულება, რომელიც გათავისუფლებულია დღგ-ისაგან ჩათვლის უფლებით ფინანსთა მინისტრის 31.12.2010 #996 ბრძანებით დადგენილი პირობების დაცვით. (იხ. დიპლომატების ვალიდურობის საძიებო: https://rs.ge/DiplomatSearch). |
| (10) | თბოელექტროსადგურებისათვის ბუნებრივი აირის მიწოდება | `control_355_10` (COL_10, yes) | yes | თბოელექტროსადგურებისთვის მიწოდებული ბუნებრივი აირის ღირებულება, რომელიც გათავისუფლებულია დღგ-ისაგან ჩათვლის უფლებით. |
| (11) | საქონლის მიწოდება ან/და მომსახურების გაწევა საქართველოს საგადასახადო კოდექსის 172-ე მუხლის პირველი ან მეორე ნაწილით გათვალისწინებულ შემთხვევაში | `control_355_11` (COL_11, yes) | yes | სსკ-ის 172-ე მუხლის პირველი ნაწილით გათვალისწინებულ შემთხვევებში მიწოდებული საქონლის ან/და გაწეული მომსახურების ღირებულება, მათ შორის, საერთაშორისო გადაზიდვის/გადაყვანის და მასთან უშუალოდ დაკავშირებული მომსახურებების ღირებულება, რომელიც გათავისუფლებულია დღგ-ისგან ჩათვლის უფლებით. |
| (12) | ცალკეული საერთაშორისო ხელშეკრულებებით გათვალისწინებული პროექტის ფარგლებში მიწოდებული საქონელი ან/და გაწეული მომსახურება | `control_355_12` (COL_12, yes) | yes | სსკ-ის 172-ე მუხლის მე-5 ნაწილით გათვალისწინებული პროექტების ფარგლებში იმ პირებისათვის მიწოდებული საქონლის/მომსახურების ღირებულება, რომლებსაც გააჩნიათ საგადასახადო ორგანოს მიერ გაცემული შეღავათით სარგებლობის დამადასტურებელი სერტიფიკატი, ან რომლებიც ირიცხებიან შეღავათით მოსარგებლე პირთა ერთიან ელ.რეესტრში https://rs.ge/TaxPrivileges |
| (13) | ჩათვლის უფლებით დღგ-სგან გათავისუფლებული სხვა ოპერაციები | `control_355_13` (COL_13, yes) | yes | დღგ-ისგან ჩათვლის უფლებით გათავისუფლებული სხვა ოპერაციები, გარდა წინა სტრიქონებზე ასახულისა (მათ შორის, საგადასახადო ორგანოს მიერ გამოვლენილი ისეთი საქონლის დანაკლისი, რომლის მიწოდება გათავისუფლებულია დღგ-ისგან ჩათვლის უფლებით). |
|  | მათ შორის: საგადასახადო ორგანოს მიერ ინვენტარიზაციის შედეგად გამოვლენილი სასაქონლო- მატერიალური ფასეულობების დანაკლისი | `control_355_13_1` (COL_13_1, yes) | yes |  |
| (14) | საქონლის მიწოდება საქართველოს ფარგლების გარეთ (საქონლის ექსპორტი/რეექსპორტი) | `control_355_14` (COL_14, yes) | yes | ექსპორტის პროცედურაში დეკლარირებული ან რეექსპორტში მოქცეული საქონლის საბაჟო ღირებულება. |
| (14 1 ) | ფინანსური ოპერაციები/ფინანსური მომსახურება | `control_355_14_1` (COL_14_1, yes) | yes | საანგარიშო პერიოდში ფინანსური ოპერაციების/ფინანსური მომსახურების ბრუნვის თანხა. |
| (14 2 ) | უძრავი ნივთის (მიწის ნაკვეთის) მიწოდება | `control_355_14_2` (COL_14_2, yes) | yes | უძრავი ნივთის (მიწის ნაკვეთის) შესყიდვის ფასი, თუ აღნიშნული საქონლის შეძენისას არ წარმოშობილა ან/და არ გამოყენებულა დღგ-ის ჩათვლის უფლება. |
| (14 3 ) | ჩათვლის უფლების გარეშე გათავისუფლებული სხვა ოპერაციები | `control_355_14_3` (COL_14_3, yes) | yes | სსკ-ის მიხედვით დღგ-ისგან ჩათვლის უფლების გარეშე გათავისუფლებული ოპერაციები, გარდა 14¹-14² სტრიქონებში შეტანილი ოპერაციებისა. |
| (15) | სულ | `control_355_15` (COL_15, locked) | locked | ივსება ავტომატურად. |



### Tab 2 — დანართი "ა" ნაწილი II უკუდაბეგვრის წესით დარიცხული დღგ

Type: cell form. Inputs: 8, locked: 4. Import: no.

| Cell | Label | Portal id (column, editable) | Editable | Help text (portal tooltip) |
|---|---|---|---|---|
|  | ოპერაციის შინაარსი / უკუდაბეგვრას დაქვემდებარებული ბრუნვა / 18% |  | yes |  |
| (1) | საქართველოს ტერიტორიაზე საანგარიშო პერიოდში მიღებული მომსახურება, დასაბეგრი პირისგან, რომელიც არ არის დაფუძნებული ან ჩვეულებრივ არ ცხოვრობს საქართველოში, ან საქართველოში არ გააჩნია ფიქსირებული დაწესებ | `control_356_1` (COL_1, yes)<br>`control_356_15` (COL_1_5, locked) | mixed | მომსახურებისთვის გასაცემი თანხა. |
| (2) | საბაჟო საწყობში საგადასახადო კოდექსის 164 1 -ე მუხლის მე-4 ნაწილით გათვალისწინებულ შემთხვევაში პირისგან შეძენილი უცხოური საქონელი, რომელიც თავისუფალ მიმოქცევაში გაშვების საბაჟო პროცედურაში ექცევა | `control_356_2` (COL_2, yes)<br>`control_356_25` (COL_2_5, locked) | mixed | საბაჟო საწყობში უცხოური საქონლის შესყიდვის ღირებულებასა და საქონლის იმპორტის თანხას შორის დადებითი სხვაობა, თუ საქონლის იმპორტი და მიწოდება არ არის დღგ-ისგან გათავისუფლებული, ან/და საბაჟო საწყობში უცხოური საქონლის შესყიდვის ღირებულება, თუ საქონლის იმპორტი გათავისუფლებულია დღგ-ისგან, ხოლო საქონლის მიწოდება დღგ-ით იბეგრება. |
| (3) | საგადასახადო კოდექსის 164 1 -ე მუხლის მე-5 ნაწილით გათვალისწინებულ შემთხვევაში თიზ-ის საწარმოსგან შეძენილი უცხოური საქონელი, რომელიც თავისუფალ მიმოქცევაში გაშვების საბაჟო პროცედურაში ექცევა. | `control_356_3` (COL_3, yes)<br>`control_356_35` (COL_3_5, locked) | mixed | თიზ-ის საწარმოსგან უცხოური საქონლის შესყიდვის ღირებულებასა და საქონლის იმპორტის თანხას შორის დადებითი სხვაობის თანხა, თუ საქონლის იმპორტი და მიწოდება არ არის დღგ-ისგან გათავისუფლებული, ან/და თიზ-ის საწარმოსგან უცხოური საქონლის შესყიდვის ღირებულება, თუ საქონლის იმპორტი გათავისუფლებულია დღგ-ისგან, ხოლო საქონლის მიწოდება დღგ-ით იბეგრება. |
| (4) | სულ | `control_356_4` (COL_4, locked) | locked | ივსება ავტომატურად. |



### Tab 3 — დანართი "ა" ნაწილი III დღგ-ის ჩასათვლელი თანხა

Type: cell form. Inputs: 34, locked: 17. Import: no.

| Cell | Label | Portal id (column, editable) | Editable | Help text (portal tooltip) |
|---|---|---|---|---|
|  | ოპერაციის შინაარსი / ჯამი (სვეტი 4+ სვეტი 5) / საქონელზე/მომსახურებაზე გადახდილი დღგ / ძირითად საშუალებაზე გადახდილი დღგ-ის თანხა |  | yes |  |
| (1) | საქართველოს ტერიტორიაზე სხვა დასაბეგრი პირისგან საქონლის /მომსახურების შეძენისთვის გადახდილი / გადასახდელი დღგ | `control_353_13` (COL_1_3, locked)<br>`control_353_14` (COL_1_4, yes)<br>`control_353_15` (COL_1_5, yes) | mixed | დასაბეგრი პირისგან საფ-ით შეძენილ საქონელზე/მომსახურებაზე ან/და ძირითად საშუალებებზე გადახდილი ან გადასახდელი დღგ, მათ შორის, ანაზღაურების სანაცვლოდ საქონლის მიწოდებად ან მომსახურების გაწევად განხილულ ოპერაციებთან დაკავშირებით გადასახდელი დღგ, მისაწოდებელ საქონელზე/მომსახურებაზე გადახდილი დღგ (ე.წ. „ავანსის“ დღგ), რომლებიც გამიზნულია ან გამოიყენება დღგ-ით დასაბეგრი ოპერაციის განხორციელებისთვის. |
| (2) | საქონლის იმპორტისას გადახდილი /გადასახდელი დღგ | `control_353_23` (COL_2_3, locked)<br>`control_353_24` (COL_2_4, yes)<br>`control_353_25` (COL_2_5, yes) | mixed | საქონლის იმპორტთან დაკავშირებით, იმპორტის დეკლარაციის საფუძველზე გადახდილი/გადასახდელი დღგ. |
| (3) | საგადასახადო ორგანოს გადაწყვეტილების საფუძველზე საქონლის იმპორტთან დაკავშირებით დარიცხული დღგ | `control_353_33` (COL_3_3, locked)<br>`control_353_34` (COL_3_4, yes)<br>`control_353_35` (COL_3_5, yes) | mixed | საგადასახადო ორგანოს გადაწყვეტილების საფუძველზე საქონლის იმპორტთან დაკავშირებით დარიცხული დღგ, რომელიც გადახდილია ბიუჯეტში გადამხდელის მიერ. |
| (4) | დღგ, დარიცხული უკუდაბეგვრის წესით | `control_353_43` (COL_4_3, locked)<br>`control_353_44` (COL_4_4, yes)<br>`control_353_45` (COL_4_5, yes) | mixed | ამავე დეკლარაციის 'ა' დანართის მე-2 ნაწილის მე-4 სტრიქონზე ასახული უკუდაბეგვრის დღგ-ის თანხა. |
| (4 1 ) | უკუდაბეგვრის წესით დარიცხული დღგ-ის თანხის გაანგარიშებაში ასახული დღგ | `control_353_43_1` (COL_4_1_3, locked)<br>`control_353_44_1` (COL_4_1_4, yes)<br>`control_353_45_1` (COL_4_1_5, yes) | mixed | ამავე დეკლარაციის 'ბ' დანართის X ნაწილის მე-4 სტრიქონზე ასახული დღგ-ის თანხა |
| (5) | ეკონომიკური საქმიანობის შეწყვეტის შემდეგ ძირითადი საშუალებების საკუთარ მფლობელობაში დატოვების ან დღგ-ის გადამხდელის რეგისტრაციის გაუქმების შემთხვევაში, ნაშთად არსებულ ძირითად საშუალებასთან მიმართებაში | `control_353_53` (COL_5_3, locked)<br>`control_353_54` (COL_5_4, yes)<br>`control_353_55` (COL_5_5, yes) | mixed | დღგ-ის თანხა საგადასახადო წლების მიხედვით, ამ ძირითადი საშუალებების დღგ-ით დასაბეგრ ოპერაციებში გამოყენების პროპორციულად. |
| (6) | საკუთარი წარმოების შენობა-ნაგებობის ძირითად საშუალებად გამოყენების შემთხვევაში დარიცხული (გადასახდელი) დღგ-ის ჩასათვლელი თანხა | `control_353_63` (COL_6_3, locked)<br>`control_353_64` (COL_6_4, locked)<br>`control_353_65` (COL_6_5, locked) | locked | ასეთის არსებობის შემთხვევაში, აღნიშნული ინფორმაცია, საბოლოო შედეგის გათვალისწინებით, ასახეთ გადასახადების ადმინისტრირების შესახებ საქართველოს ფინანსთა მინისტრის N996 ბრძანების 75-ე მუხლის მე-5 ნაწილის შესაბამისად ამავე დეკლარაციის მე-19 ან მე-20 გრაფაში. |
| (6 1 ) | საკუთარი ძალებით განხორციელებული ძირითადი საშუალების (შენობის/ნაგებობის)რემონტის შემთხვევაში დარიცხული (გადასახდელი) დღგ-ის ჩასათვლელი თანხა | `control_353_613` (COL_6_1_3, locked)<br>`control_353_614` (COL_6_1_4, locked)<br>`control_353_615` (COL_6_1_5, locked) | locked | ასეთის არსებობის შემთხვევაში, აღნიშნული ინფორმაცია, საბოლოო შედეგის გათვალისწინებით, ასახეთ გადასახადების ადმინისტრირების შესახებ საქართველოს ფინანსთა მინისტრის N996 ბრძანების 75-ე მუხლის მე-5 ნაწილის შესაბამისად ამავე დეკლარაციის მე-19 ან მე-20 გრაფაში. |
| (7) | დღგ, დარიცხული საქონლის/მომსახურების გაცვლის (ბარტერული) ოპერაციის შემთხვევაში | `control_353_73` (COL_7_3, locked)<br>`control_353_74` (COL_7_4, yes)<br>`control_353_75` (COL_7_5, yes) | mixed | აღნიშნული გრაფა ივსება იმ შემთხვევაში, როდესაც გაცვლის (ბარტერული) ოპერაციის ორივე მხარე წარმოადგენს დღგ-ის გადამხდელად რეგისტრირებულ დასაბეგრ პირს და ეს ოპერაცია იბეგრება დღგ-ით, ჩასათვლელი თანხა განისაზღვრება მიწოდებულ საქონელზე/გაწეულ მომსახურებაზე დარიცხული და შესაბამის დღგ-ის დეკლარაციაში ასახული დღგ-ის თანხა სანაცვლო საქონლის/მომსახურების მიღების მომენტში. დღგ-ის ჩათვლის მიღების საფუძველია ამ ოპერაციაზე დარიცხული და შესაბამისი პერიოდის დღგ-ის დეკლარაციაში ასახული დღგ-ის თანხა, რომელზეც, დასაბეგრ პირებს შორის საგადასახადო ანგარიშ-ფაქტურა არ გამოწერილა. |
| (8) | დღგ, გადახდილი საქართველოს საგადასახადო კოდექსის 161 1 მუხლით გათვალისწინებულ შემთხვევებში | `control_353_83` (COL_8_3, locked)<br>`control_353_84` (COL_8_4, yes)<br>`control_353_85` (COL_8_5, yes) | mixed | საგადასახადო დავალიანების გადახდევინების უზრუნველყოფის ღონისძიების ფარგლებში ან სხვა ფულადი ვალდებულებების გადახდევინების მიზნით საქონლის აუქციონის, პირდაპირი მიყიდვის ან სხვა წესით შეძენილ საქონელზე, საქონლის შეძენის დამადასტურებელი შესაბამისი დოკუმენტის საფუძველზე გადახდილი დღგ-ის თანხა. |
| (9) | სულ | `control_353_93` (COL_9_3, locked)<br>`control_353_94` (COL_9_4, locked)<br>`control_353_95` (COL_9_5, locked) | locked | ივსება ავტომატურად. |



### Tab 4 — დანართი "ბ" ნაწილი I დასაბეგრ ოპერაციებზე (მათ შორის, ჩათვლის უფლებით გათავისუფლებულ ოპერაციებზე) გამოწერილი საგადასახადო ანგარიშ-ფაქტურები (მათ შორის, კორექტირების)

xlsx import: yes. Scripts: grid_66_combo_86_change, grid_66_combo_87_change, k_seria_chamge, seria_chamge

Grid 1 columns: სერია | ნომერი | დასაბეგრი ოპერაციის განხორციელების თვე | მყიდველის/ მიმღების ს/ნ | დღგ-ს თანხა > გადასახდელი (მათ შორის, კორექტირების შედეგად დამატებით გადასახდელი) | დღგ-ს თანხა > კორექტირების შედეგად შესამცირებელი | ანგარიშ ფაქტურა რომლის კორექტირებაც წარმოებს > სერია | ანგარიშ ფაქტურა რომლის კორექტირებაც წარმოებს > ნომერი

Grid 2 columns: მიწოდების ფაქტურის სერია | მიწოდების ფაქტურის ნომერი | ავანსის ფაქტურის სერია | ავანსის ფაქტურის ნომერი | თანხა

Add row 1 fields (portal column name, widget, rules):

| # | x_name | Widget | Editable | Rules / options |
|---|---|---|---|---|
| 1 | SERIA | dropdown (ddl_id=9, value = code + '-' + the number input that follows) | yes | 53 options: ჯო-, ჯთ-, ჯე-, შს-, ყგ-, ქთ, ფო, ტლ-, სქ-, სტ, სნ-, სკ, სე-, სდ, სგ-, რწ-, რუ, პს-, მწ-, მს, მგ-, კპ-, კო-, კნ-, კკკკკ, კე-, იჯ-, ის-, თწ-, თს- … |
| 2 | SERIA | number (2-digit series number appended to the dropdown code) | yes | data-v-min=0; data-v-max=99; data-w-empty=empty; data-l-zero=keep; x_d=n; x_delimiter=- |
| 3 | NOMERI | number | yes | data-v-min=0; data-v-max=9999999; data-w-empty=empty; data-l-zero=keep |
| 4 | ISSUE_DATE | month picker (month + year; range 01.01.1990-22.10.2026) | yes |  |
| 5 | SA_IDENT_NO_PAIR | autocomplete (server lookup, ddl_id=41, minlength=3) | yes |  |
| 6 | AMOUNT | number | yes | data-w-empty=empty |
| 7 | REDUCE_AMOUNT | number | yes | data-w-empty=empty |
| 8 | KORECT_SERIA | dropdown (ddl_id=44, value = code + '-' + the number input that follows) | yes | 55 options: ჯო-, ჯთ-, ჯე-, შს-, ყგ-, ქთ, ფო, ტლ-, სქ-, სტ, სნ-, სკ, სე-, სდ, სგ-, რწ-, რუ, პს-, მწ-, მს, მგ-, კპ-, კო-, კნ-, კკკკკ, კე-, იჯ-, ის-, თწ-, თს- … |
| 9 | KORECT_SERIA | number (2-digit series number appended to the dropdown code) | yes | data-v-min=0; data-v-max=99; data-w-empty=empty; data-l-zero=keep; x_d=n; x_delimiter=- |
| 10 | KORECT_NOMERI | number | yes | data-v-min=0; data-v-max=9999999; data-w-empty=empty; data-l-zero=keep |
| 11 | ID | hidden | yes |  |
| 12 | INV_TYPE | hidden | yes | data-w-empty=empty |
| 13 | SEQ_NUM | hidden | yes |  |
Add row 2 fields (portal column name, widget, rules):

| # | x_name | Widget | Editable | Rules / options |
|---|---|---|---|---|
| 1 | INVOICE_ID | autocomplete (server lookup, ddl_id=86, minlength=2) | yes | [{'name': 'v_seq_num' , 'value' : '76819693' } ] |
| 2 | INVOICE_ID_AV | autocomplete (server lookup, ddl_id=87, minlength=2) | yes | [{'name': 'v_seq_num' , 'value' : '76819693' } ] |
| 3 | AMOUNT | number | yes |  |
| 4 | ID | hidden | yes |  |
| 5 | SEQ_NUM | hidden | yes |  |

Buttons: წინა | შემდეგი | ექსპორტი | იმპორტი

Help texts:
- აისახება დასაბეგრ (მ.შ. კორექტირების) ოპერაციებზე (მ.შ. ჩათვლის უფლებით გათავისუფლებულ ოპერაციებზე), აგრეთვე დასაბეგრი „ავანსების“ მიხედვით გამოწერილი საფ-ების მონაცემები.
- აისახება „ავანსის“ საფ-ების მონაცემები და დღგ-ის ის თანხა, რომლითაც შემცირდება საანგარიშო თვის დასაბეგრ ოპერაციებზე დარიცხული დღგ.


### Tab 5 — დანართი "ბ" ნაწილი II შეძენილ საქონელზე/მომსახურებაზე გამოწერილი საგადასახადო ანგარიშ-ფაქტურები (მათ შორის, კორექტირების)

xlsx import: yes. Scripts: grid_67_combo_88_change, grid_67_combo_89_change, k_seria_chamge, seria_chamge

Grid 1 columns: სერია | ნომერი | დასაბეგრი ოპერაციის განხორციელების თვე | მომწოდებლის ს/ნ | დღგ-ს თანხა > ჩასათვლელი, მათ შორის, კორექტირების შედეგად დამატებით ჩასათვლელი | დღგ-ს თანხა > კორექტირების შედეგად შესამცირებელი | ანგარიშ ფაქტურა რომლის კორექტირებაც წარმოებს > სერია | ანგარიშ ფაქტურა რომლის კორექტირებაც წარმოებს > ნომერი

Grid 2 columns: მიწოდების ფაქტურის სერია | მიწოდების ფაქტურის ნომერი | ავანსის ფაქტურის სერია | ავანსის ფაქტურის ნომერი | თანხა

Add row 1 fields (portal column name, widget, rules):

| # | x_name | Widget | Editable | Rules / options |
|---|---|---|---|---|
| 1 | SERIA | dropdown (ddl_id=9, value = code + '-' + the number input that follows) | yes | 53 options: ჯო-, ჯთ-, ჯე-, შს-, ყგ-, ქთ, ფო, ტლ-, სქ-, სტ, სნ-, სკ, სე-, სდ, სგ-, რწ-, რუ, პს-, მწ-, მს, მგ-, კპ-, კო-, კნ-, კკკკკ, კე-, იჯ-, ის-, თწ-, თს- … |
| 2 | SERIA | number (2-digit series number appended to the dropdown code) | yes | data-v-min=0; data-v-max=99; data-w-empty=empty; data-l-zero=keep; x_d=n; x_delimiter=- |
| 3 | NOMERI | number | yes | data-v-min=0; data-v-max=9999999; data-w-empty=empty; data-l-zero=keep |
| 4 | ISSUE_DATE | month picker (month + year; range 01.01.1990-22.10.2026) | yes |  |
| 5 | SA_IDENT_NO_PAIR | autocomplete (server lookup, ddl_id=41, minlength=3) | yes |  |
| 6 | AMOUNT | number | yes | data-w-empty=empty |
| 7 | REDUCE_AMOUNT | number | yes | data-w-empty=empty |
| 8 | KORECT_SERIA | dropdown (ddl_id=44, value = code + '-' + the number input that follows) | yes | 55 options: ჯო-, ჯთ-, ჯე-, შს-, ყგ-, ქთ, ფო, ტლ-, სქ-, სტ, სნ-, სკ, სე-, სდ, სგ-, რწ-, რუ, პს-, მწ-, მს, მგ-, კპ-, კო-, კნ-, კკკკკ, კე-, იჯ-, ის-, თწ-, თს- … |
| 9 | KORECT_SERIA | number (2-digit series number appended to the dropdown code) | yes | data-v-min=0; data-v-max=99; data-w-empty=empty; data-l-zero=keep; x_d=n; x_delimiter=- |
| 10 | KORECT_NOMERI | number | yes | data-v-min=0; data-v-max=9999999; data-w-empty=empty; data-l-zero=keep |
| 11 | ID | hidden | yes |  |
| 12 | INV_TYPE | hidden | yes | data-w-empty=empty |
| 13 | SEQ_NUM | hidden | yes |  |
Add row 2 fields (portal column name, widget, rules):

| # | x_name | Widget | Editable | Rules / options |
|---|---|---|---|---|
| 1 | INVOICE_ID | autocomplete (server lookup, ddl_id=89, minlength=2) | yes | [{'name': 'v_seq_num' , 'value' : '76819693' } ] |
| 2 | INVOICE_ID_AV | autocomplete (server lookup, ddl_id=88, minlength=2) | yes | [{'name': 'v_seq_num' , 'value' : '76819693' } ] |
| 3 | AMOUNT | number | yes |  |
| 4 | ID | hidden | yes |  |
| 5 | SEQ_NUM | hidden | yes |  |

Buttons: წინა | შემდეგი | ექსპორტი | იმპორტი

Help texts:
- აისახება შეძენილ (მ.შ. კორექტირების) ოპერაციებზე (მ.შ. ჩათვლის უფლებით გათავისუფლებულ ოპერაციებზე), აგრეთვე გადახდილი „ავანსების“ მიხედვით გამოწერილი საფ-ების მონაცემები.
- აისახება „ავანსის“ საფ-ების მონაცემები და დღგ-ის ის თანხა, რომლითაც შემცირდება შეძენილ საქონელზე/მომსახურებაზე გამოწერილი საფ-ების მიხედვით ჩასათვლელი დღგ.


### Tab 6 — დანართი "ბ" ნაწილი III საქონლის იმპორტისას წარდგენილი საბაჟო დეკლარაციები

xlsx import: yes. Scripts: fn_293_grid_7_refresh, nomeri_chamge

Grid 1 columns: შეფასების ნომერი

Add row 1 fields (portal column name, widget, rules):

| # | x_name | Widget | Editable | Rules / options |
|---|---|---|---|---|
| 1 | COL_2 | autocomplete (server lookup, ddl_id=11, minlength=2) | yes | [{'name': 'v_seq_num' , 'value' : '76819693' } ] |
| 2 | COL_2_2 | number | locked |  |
| 3 | COL_3 | date | locked |  |
| 4 | COL_4 | number | locked |  |
| 5 | ID | hidden | yes |  |
| 6 | SEQ_NUM | hidden | yes |  |

Buttons: წინა | შემდეგი | ექსპორტი | იმპორტი

Help texts:
- საბაჟო დეკლარაციების თანხის განახლება
- მიეთითება დღგ-ის ჩათვლაში გამოყენებული საბაჟო დეკლარაციის მონაცემები. კერძოდ, საბაჟო დეკლარაციის გრაფაში მითითებული შეფასების ნომერი (მხოლოდ ციფრები), თარიღი და დღგ-ის თანხა, ხოლო თუ საბაჟო დეკლარაციას არ გააჩნია გრაფა – საბაჟო დეკლარაციის ნომერი (მხოლოდ ციფრები), თარიღი და დღგ-ის თანხა.


### Tab 7 — დანართი "ბ" ნაწილი IV

xlsx import: yes. Scripts: grid_97_col_3_change, grid_97_col_5_change

Grid 1 columns: საქართველოს საგადასახადო კოდექსის 161 1 მუხლის შესაბამისად საქონლის შეძენის დამადასტურებელი შესაბამისი დოკუმენტი > | საქართველოს საგადასახადო კოდექსის 161 1 მუხლის შესაბამისად საქონლის შეძენის დამადასტურებელი შესაბამისი დოკუმენტი > შეძენის დამადასტურებელი შესაბამისი დოკუმენტის ნომერი | საქართველოს საგადასახადო კოდექსის 161 1 მუხლის შესაბამისად საქონლის შეძენის დამადასტურებელი შესაბამისი დოკუმენტი > რეალიზაციის განმახორციელებელი უფლებამოსილი პირის საიდენტიფიკაციო ნომერი | საქართველოს საგადასახადო კოდექსის 161 1 მუხლის შესაბამისად საქონლის შეძენის დამადასტურებელი შესაბამისი დოკუმენტი > რეალიზაციის განმახორციელებელი უფლებამოსილი პირის დასახელება | საქართველოს საგადასახადო კოდექსის 161 1 მუხლის შესაბამისად საქონლის შეძენის დამადასტურებელი შესაბამისი დოკუმენტი > საქონლის/სამეურვეო ქონების მესაკუთრის საიდენტიფიკაციო ნომერი | საქართველოს საგადასახადო კოდექსის 161 1 მუხლის შესაბამისად საქონლის შეძენის დამადასტურებელი შესაბამისი დოკუმენტი > საქონლის/სამეურვეო ქონების მესაკუთრის დასახელება | საქართველოს საგადასახადო კოდექსის 161 1 მუხლის შესაბამისად საქონლის შეძენის დამადასტურებელი შესაბამისი დოკუმენტი > საქონლის/სამეურვეო ქონების შესყიდვის თარიღი

Add row 1 fields (portal column name, widget, rules):

| # | x_name | Widget | Editable | Rules / options |
|---|---|---|---|---|
| 1 | COL_2 | text | yes |  |
| 2 | COL_3 | autocomplete (server lookup, ddl_id=98, minlength=3) | yes |  |
| 3 | COL_4 | text | locked |  |
| 4 | COL_5 | autocomplete (server lookup, ddl_id=98, minlength=3) | yes |  |
| 5 | COL_6 | text | locked |  |
| 6 | COL_7 | date | yes |  |
| 7 | COL_8 | number | yes |  |
| 8 | ID | hidden | yes |  |
| 9 | SEQ_NUM | hidden | yes |  |

Buttons: წინა | შემდეგი | ექსპორტი | იმპორტი

Help texts:
- მიეთითება საგადასახადო დავალიანების გადახდევინების უზრუნველყოფის ღონისძიების ფარგლებში ან სხვა ფულადი ვალდებულების გადახდევინების მიზნით საქონლის აუქციონის, პირდაპირი მიყიდვის ან სხვა წესით რეალიზაციის შემთხვევაში საქონლის შეძენის დამადასტურებელი შესაბამისი დოკუმენტის ნომერი, რეალიზაციის განმახორციელებელი უფლებამოსილი პირის ან/და საქონლის/სამეურვეო ქონების მესაკუთრის საიდენტიფიკაციო მონაცემები, ქონების შესყიდვის თარიღი და დღგ-ის თანხა.


### Tab 8 — დანართი "ბ" ნაწილი V

xlsx import: yes. Scripts: grid_69_col_2_change, grid_69_col_3_change

Grid 1 columns: საქონლის/მომსახურების გაცვლის (ბარტერული) ოპერაციის შედეგად შეძენილი საქონელი/მომსახურება > | საქონლის/მომსახურების გაცვლის (ბარტერული) ოპერაციის შედეგად შეძენილი საქონელი/მომსახურება > დეკლარაციის ნომერი | საქონლის/მომსახურების გაცვლის (ბარტერული) ოპერაციის შედეგად შეძენილი საქონელი/მომსახურება > მომწოდებლის ს/ნ | საქონლის/მომსახურების გაცვლის (ბარტერული) ოპერაციის შედეგად შეძენილი საქონელი/მომსახურება > მომწოდებლის დასახელება | საქონლის/მომსახურების გაცვლის (ბარტერული) ოპერაციის შედეგად შეძენილი საქონელი/მომსახურება > საანგარიშო პერიოდი (თვე და წელი)

Add row 1 fields (portal column name, widget, rules):

| # | x_name | Widget | Editable | Rules / options |
|---|---|---|---|---|
| 1 | COL_2 | autocomplete (server lookup, ddl_id=94, minlength=0) | yes | [{'name': 'V_SEQ_NUM' , 'value' : '76819693' }] |
| 2 | COL_3 | autocomplete (server lookup, ddl_id=41, minlength=3) | yes |  |
| 3 | COL_4 | text | locked |  |
| 4 | COL_5 | text | locked |  |
| 5 | COL_6 | number | yes |  |
| 6 | ID | hidden | yes |  |
| 7 | SEQ_NUM | hidden | yes |  |

Buttons: წინა | შემდეგი | ექსპორტი | იმპორტი

Help texts:
- ივსება იმ შემთხვევაში, თუ გაცვლის (ბარტერის) თითოეული ოპერაცია იბეგრება დღგით (არ გამოწერილა საფ-ი) და საქონლის მიწოდება/მომსახურების გაწევა განხორციელებულია 2021 წლის 1 იანვრამდე, ხოლო სანაცვლო საქონლის მიწოდება/მომსახურების გაწევა ხორციელდება 2021 წლის 1 იანვარს ან შემდგომ პერიოდებში. მიეთითება: იმ დეკლარაციის სარეგისტრაციო ნომერი, რომლითაც დადეკლარირდა ბარტერის ფარგლებში მიწოდებულ საქონელზე/მომსახურებაზე გადასახდელი დღგ. შენიშვნა: ამ დანართით ასახული დღგ-ის თანხა არ უნდა იყოს ამავე დანართში მითითებული დღგ-ის დეკლარაციით ბარტერულ ოპერაციაზე დარიცხულ დღგ-ის თანხაზე მეტი.


### Tab 9 — დანართი "ბ" ნაწილი VII

xlsx import: yes. Scripts: grid_98_col_2_change

Grid 1 columns: საგადასახადო/საბაჟო ორგანოს გადაწყვეტილების საფუძველზე საქონლის იმპორტთან დაკავშირებით დარიცხული და გადახდილი დღგ > | საგადასახადო/საბაჟო ორგანოს გადაწყვეტილების საფუძველზე საქონლის იმპორტთან დაკავშირებით დარიცხული და გადახდილი დღგ > დარიცხვის შესახებ საგადასახადო/საბაჟო ორგანოს გადაწყვეტილების ნომერი | საგადასახადო/საბაჟო ორგანოს გადაწყვეტილების საფუძველზე საქონლის იმპორტთან დაკავშირებით დარიცხული და გადახდილი დღგ > დარიცხვის შესახებ საგადასახადო/საბაჟო ორგანოს გადაწყვეტილების თარიღი

Add row 1 fields (portal column name, widget, rules):

| # | x_name | Widget | Editable | Rules / options |
|---|---|---|---|---|
| 1 | COL_2 | dropdown (ddl_id=101, value = code + '' + the number input that follows) | yes | 90 options: ტესტ (05.05.2021,200), 111 (25.05.2021,18000.84), 850 (21.05.2021,1278), 2222222 (12.07.2021,1278), 11112 (20.07.2021,10000), 1111111 (23.07.2021,50038), AXALI (24.07.2021,50038), 1122 (07.06.2021,1000), l123 (21.12.2021,30900), 1233 (12.04.2022,300), qqqqqqqqqqqqqq (03.03.2022,15), 555-111 (04.10.2022,10), A (27.06.2023,300), 30250 (04.12.2023,18000), 30971 (11.12.2023,122367565), 5227 (11.03.2024,117563), 2222 (19.03.2024,200), 20622 (19.09.2024,18000), 20623 (19.09.2024,18000), 20624 (19.09.2024,18000), 20621 (19.09.2024,18000), 20688 (20.09.2024,18000), 20693 (20.09.2024,18000), 20695 (20.09.2024,18000), 20696 (20.09.2024,18000), 5666 (01.10.2024,1000), 321 (08.10.2024,18000), 123 (19.11.2024,100), 100 (28.11.2024,100), 3333 (16.01.2025,100) … |
| 2 | COL_3 | text | locked |  |
| 3 | COL_4 | number | yes |  |
| 4 | ID | hidden | yes |  |
| 5 | SEQ_NUM | hidden | yes |  |

Buttons: წინა | შემდეგი | ექსპორტი | იმპორტი

Help texts:
- მიეთითება საგადასახადო ორგანოს იმ გადაწყვეტილების ნომერი და თარიღი, რომლის საფუძველზეც განხორციელდა საქონლის იმპორტთან დაკავშირებით დღგ-ის დარიცხვა და მის შესაბამისად ბიუჯეტში გადახდილი დღგ-ის თანხა. შენიშვნა: დანართით დეკლარირებული დღგ-ის თანხა არ უნდა იყოს ამავე დანართში მითითებული საგადასახადო ორგანოს გადაწყვეტილებით საქონლის იმპორტთან დაკავშირებით დარიცხულ დღგ-ის თანხაზე მეტი.


### Tab 10 — დანართი "ბ" ნაწილი VIII

xlsx import: yes. Scripts: grid_74_col_2_change

Grid 1 columns: დღგ ბრუნვის კორექტირებაზე (დღგ-ის შესამცირებელი თანხა) > | დღგ ბრუნვის კორექტირებაზე (დღგ-ის შესამცირებელი თანხა) > დეკლარაციის ნომერი | დღგ ბრუნვის კორექტირებაზე (დღგ-ის შესამცირებელი თანხა) > საანგარიშო პერიოდი

Add row 1 fields (portal column name, widget, rules):

| # | x_name | Widget | Editable | Rules / options |
|---|---|---|---|---|
| 1 | COL_2 | autocomplete (server lookup, ddl_id=112, minlength=0) | yes | [{'name': 'V_SEQ_NUM' , 'value' : '76819693' }] |
| 2 | COL_3 | text | locked |  |
| 3 | COL_4 | number | yes |  |
| 4 | ID | hidden | yes |  |
| 5 | SEQ_NUM | hidden | yes |  |

Buttons: წინა | შემდეგი | ექსპორტი | იმპორტი

Help texts:
- დანართი ივსება იმ შემთხვევაში, თუ გასულ საანგარიშო პერიოდებში დღგ-ით დაბეგრილია ოპერაცია, არ არის გამოწერილი საფ-ი და ხდება ასეთი ოპერაციის კორექტირება (შემცირება) სსკ-ის 179-ე მუხლის შესაბამისად. მიეთითება დღგ-ის იმ დეკლარაციის მონაცემები, რომლითაც განხორციელდა დასაბეგრ ოპერაციაზე (კორექტირებამდე) დღგ-ის დეკლარირება, აგრეთვე დღგ-ის თანხა, რომლითაც მცირდება ბიუჯეტში შესატანი დღგ. შენიშვნა: დღგ-ის თანხა არ უნდა იყოს მითითებული დღგ-ის დეკლარაციით დარიცხულ დღგ-სა და ამავე საანგარიშო პერიოდებზე გამოწერილი საფ-ების მიხედვით დღგ-ის სხვაობაზე მეტი.


### Tab 11 — დანართი "ბ" ნაწილი IX

xlsx import: yes. Scripts: control_357_ch, grid_74_col_2_change

Grid 1 columns: დღგ უკუდაბეგვრით დასაბეგრი ოპერაციის კორექტირებაზე (დღგ-ის შესამცირებელი თანხა) > | დღგ უკუდაბეგვრით დასაბეგრი ოპერაციის კორექტირებაზე (დღგ-ის შესამცირებელი თანხა) > დეკლარაციის ნომერი | დღგ უკუდაბეგვრით დასაბეგრი ოპერაციის კორექტირებაზე (დღგ-ის შესამცირებელი თანხა) > საანგარიშო პერიოდი

Add row 1 fields (portal column name, widget, rules):

| # | x_name | Widget | Editable | Rules / options |
|---|---|---|---|---|
| 1 | COL_2 | autocomplete (server lookup, ddl_id=113, minlength=0) | yes | [{'name': 'V_SEQ_NUM' , 'value' : '76819693' }] |
| 2 | COL_3 | text | locked |  |
| 3 | COL_4 | number | yes |  |
| 4 | ID | hidden | yes |  |
| 5 | SEQ_NUM | hidden | yes |  |

Buttons: წინა | შემდეგი | ექსპორტი | იმპორტი

Help texts:
- დანართი ივსება იმ შემთხვევაში, როდესაც სსკ-ის 179-ე მუხლის შესაბამისად განხორციელდა უკუდაბეგვრის წესით დაბეგრილი დღგ-ით დასაბეგრი ოპერაციის კორექტირება (შემცირება). მიეთითება დღგ-ის დეკლარაციის/გაანგარიშების სარეგისტრაციო ნომერი, რომელშიც ასახულია კორექტირებამდე უკუდაბეგვრით დასაბეგრი ოპერაცია. ასევე, მიეთითება დეკლარაციის/გაანგარიშების მონაცემები და დღგ-ის თანხა, რომლითაც ხდება დღგ-ით უკუდაბეგვრით დასაბეგრი ოპერაციის კორექტირება (შემცირება).შენიშვნა: დღგ-ის თანხა არ უნდა იყოს მითითებული დეკლარაციით/გაანგარიშებით დარიცხულ დღგ-ზე მეტი.


### Tab 12 — დანართი "ბ" ნაწილი X

xlsx import: yes. Scripts: control_352_ch, grid_111_col_2_change

Grid 1 columns: უკუდაბეგვრის წესით დარიცხული დღგ-ის თანხის გაანგარიშებაში ასახული დღგ-ის თანხა, რომელიც ექვემდებარება ჩათვლას > | უკუდაბეგვრის წესით დარიცხული დღგ-ის თანხის გაანგარიშებაში ასახული დღგ-ის თანხა, რომელიც ექვემდებარება ჩათვლას > გაანგარიშების სარეგისტრაციო ნომერი | უკუდაბეგვრის წესით დარიცხული დღგ-ის თანხის გაანგარიშებაში ასახული დღგ-ის თანხა, რომელიც ექვემდებარება ჩათვლას > საანგარიშო პერიოდი

Add row 1 fields (portal column name, widget, rules):

| # | x_name | Widget | Editable | Rules / options |
|---|---|---|---|---|
| 1 | COL_2 | autocomplete (server lookup, ddl_id=144, minlength=0) | yes | [{'name': 'V_SEQ_NUM' , 'value' : '76819693' }] |
| 2 | COL_3 | text | locked |  |
| 3 | COL_4 | number | yes |  |
| 4 | ID | hidden | yes |  |
| 5 | SEQ_NUM | hidden | yes |  |

Buttons: წინა | შემდეგი | ექსპორტი | იმპორტი

Help texts:
- დანართი ივსება იმ შემთხვევაში, როდესაც 176-ე მუხლის მე-2 ნაწილის და საქართველოს ფინანსთა მინისტრის N996 ბრძანების 73² მუხლის შესაბამისად პირს უკუდაბეგვრის წესით დარიცხული დღგ-ის თანხის გაანგარიშებაში ასახული დღგ-ის თანხის დადგენილი წესით ჩათვლის უფლება წარმოექმნა დღგ-ის გადამხდელად რეგისტრაციის შემდეგ. მიეთითება უკუდაბეგვრის წესით დარიცხული დღგ-ის თანხის გაანგარიშების სარეგისტრაციო ნომერი, რომელშიც ასახულია უკუდაბეგვრის წესით დარიცხული დღგის თანხა, აგრეთვე დღგ-ის თანხა/თანხის ნაწილი, რომელიც ექვემდებარა ჩათვლას. შენიშვნა: დღგ-ის თანხა არ უნდა იყოს უკუდაბეგვრის წესით დარიცხული დღგ-ის თანხის გაანგარიშებაში ასახული დღგის თანხაზე მეტი


### Tab 13 — გამოწერილი (მათ შორის, შიდა გადაზიდვაზე) ნავთობპროდუქტების საგადასახადო ანგარიშ- ფაქტურები (მათ შორის, კორექტირების) ნაწილი II 1

xlsx import: yes. Scripts: grid_72_combo_86_change, grid_72_combo_87_change

Grid 1 columns: ნსაფ მათ შორის კორექტირების > სერია | ნსაფ მათ შორის კორექტირების > N | ნსაფ მათ შორის კორექტირების > თარიღი | ნსაფ რომლის კორექტ-აც ხდება > სერია | ნსაფ რომლის კორექტ-აც ხდება > N | ნსაფ რომლის კორექტ-აც ხდება > თარიღი | სტაციონარის რეგისტრაციის N > გაგზავნის | სტაციონარის რეგისტრაციის N > დანიშულების | მყიდველის ს/ნ | ნ/პროდ უქტის კოდი | რაოდ. ლ-ში | რაოდ. კგ-ში | დღგ-ის თანხა > გადასახდელი(მათ შორის, კორექტირების შედეგად დამატებით გადახდილი) | დღგ-ის თანხა > კორექტირების შედეგად შესამცირებელი

Grid 2 columns: მიწოდების სპეც ფაქტურის სერია | მიწოდების სპეც ფაქტურის ნომერი | ავანსის ფაქტურის სერია | ავანსის ფაქტურის ნომერი | თანხა

Add row 1 fields (portal column name, widget, rules):

| # | x_name | Widget | Editable | Rules / options |
|---|---|---|---|---|
| 1 | COL_1 | dropdown (ddl_id=12, value = code + '' + the number input that follows) | yes | 4 options: აა, ას, აშ, აი |
| 2 | COL_2 | number | yes | data-v-min=0; data-v-max=9999999; data-l-zero=keep |
| 3 | COL_3 | date | yes |  |
| 4 | COL_4 | dropdown (ddl_id=22, value = code + '' + the number input that follows) | yes | 8 options: აა, ას, აშ, აი, ეი, ეშ, ეა, ეს |
| 5 | COL_5 | number | yes | data-v-min=0; data-v-max=9999999; data-l-zero=keep |
| 6 | COL_6 | date | yes |  |
| 7 | COL_7 | autocomplete (server lookup, ddl_id=14, minlength=1) | yes |  |
| 8 | COL_8 | autocomplete (server lookup, ddl_id=13, minlength=1) | yes |  |
| 9 | COL_9 | autocomplete (server lookup, ddl_id=41, minlength=3) | yes |  |
| 10 | COL_10 | autocomplete (server lookup, ddl_id=15, minlength=1) | yes |  |
| 11 | COL_11 | number | yes |  |
| 12 | COL_12 | number | yes |  |
| 13 | COL_14 | number | yes |  |
| 14 | COL_16 | number | yes |  |
| 15 | ID | hidden | yes |  |
| 16 | SEQ_NUM | hidden | yes |  |
Add row 2 fields (portal column name, widget, rules):

| # | x_name | Widget | Editable | Rules / options |
|---|---|---|---|---|
| 1 | INVOICE_ID | autocomplete (server lookup, ddl_id=114, minlength=2) | yes | [{'name': 'v_seq_num' , 'value' : '76819693' } ] |
| 2 | INVOICE_ID_AV | autocomplete (server lookup, ddl_id=116, minlength=2) | yes | [{'name': 'v_seq_num' , 'value' : '76819693' } ] |
| 3 | AMOUNT | number | yes |  |
| 4 | ID | hidden | yes |  |
| 5 | SEQ_NUM | hidden | yes |  |

Buttons: წინა | შემდეგი | ექსპორტი | იმპორტი


### Tab 14 — შეძენილი ნავთობპროდუქტებზე გამოწერილი ნავთობპროდუქტების საგადასახადო ანგარიშ- ფაქტურები (მათ შორის, კორექტირების) ნაწილი II 2

xlsx import: yes. Scripts: grid_73_combo_88_change, grid_73_combo_89_change

Grid 1 columns: ნსაფ მათ შორის კორექტირების > სერია | ნსაფ მათ შორის კორექტირების > N | ნსაფ მათ შორის კორექტირების > თარიღი | ნსაფ რომლის კორექტ-აც ხდება > სერია | ნსაფ რომლის კორექტ-აც ხდება > N | ნსაფ რომლის კორექტ-აც ხდება > თარიღი | სტაციონარის რეგისტრაციის N > გაგზავნის | სტაციონარის რეგისტრაციის N > დანიშულების | გამყიდველის ს/ნ | ნ/პროდ უქტის კოდი | რაოდ. ლ-ში | რაოდ. კგ-ში | დღგ-ის თანხა > ჩასათვლელი(მათ შორის, კორექტირების შედეგად დამატებით ჩასათვლელი) | დღგ-ის თანხა > კორექტირების შედეგად შესამცირებელი

Grid 2 columns: მიწოდების სპეც ფაქტურის სერია | მიწოდების სპეც ფაქტურის ნომერი | ავანსის ფაქტურის სერია | ავანსის ფაქტურის ნომერი | თანხა

Add row 1 fields (portal column name, widget, rules):

| # | x_name | Widget | Editable | Rules / options |
|---|---|---|---|---|
| 1 | COL_1 | dropdown (ddl_id=12, value = code + '' + the number input that follows) | yes | 4 options: აა, ას, აშ, აი |
| 2 | COL_2 | number | yes | data-v-min=0; data-v-max=9999999; data-l-zero=keep |
| 3 | COL_3 | date | yes |  |
| 4 | COL_4 | dropdown (ddl_id=22, value = code + '' + the number input that follows) | yes | 8 options: აა, ას, აშ, აი, ეი, ეშ, ეა, ეს |
| 5 | COL_5 | number | yes | data-v-min=0; data-v-max=9999999; data-l-zero=keep |
| 6 | COL_6 | date | yes |  |
| 7 | COL_7 | autocomplete (server lookup, ddl_id=13, minlength=1) | yes |  |
| 8 | COL_8 | autocomplete (server lookup, ddl_id=14, minlength=1) | yes |  |
| 9 | COL_9 | autocomplete (server lookup, ddl_id=41, minlength=3) | yes |  |
| 10 | COL_10 | autocomplete (server lookup, ddl_id=15, minlength=1) | yes |  |
| 11 | COL_11 | number | yes |  |
| 12 | COL_12 | number | yes |  |
| 13 | COL_14 | number | yes |  |
| 14 | COL_16 | number | yes |  |
| 15 | ID | hidden | yes |  |
| 16 | SEQ_NUM | hidden | yes |  |
Add row 2 fields (portal column name, widget, rules):

| # | x_name | Widget | Editable | Rules / options |
|---|---|---|---|---|
| 1 | INVOICE_ID | autocomplete (server lookup, ddl_id=115, minlength=2) | yes | [{'name': 'v_seq_num' , 'value' : '76819693' } ] |
| 2 | INVOICE_ID_AV | autocomplete (server lookup, ddl_id=117, minlength=2) | yes | [{'name': 'v_seq_num' , 'value' : '76819693' } ] |
| 3 | AMOUNT | number | yes |  |
| 4 | ID | hidden | yes |  |
| 5 | SEQ_NUM | hidden | yes |  |

Buttons: წინა | შემდეგი | ექსპორტი | იმპორტი


### Tab 15 — ფაქტიურად დარიცხული ნაშთები

xlsx import: yes. Scripts: sum_cntrol_10

Grid 1 columns: ოთხნი შნა კოდი | რაო დენობა > რეალიზ ებული ნსაფ- ით | რაო დენობა > რეალიზ ებული ნსაფის გარეშე | ნაშთი თვის დასა წყისში > გახარ ჯულის (პირადი მოხმარე ბისათვის) | ნაშთი თვის დასა წყისში > გადამუშ ავებუ ლის ოდენობა | მიღე ბული და წარმოე ბული > | მიღე ბული და წარმოე ბული > | თვის განმავ ლობაში ფაქტი ურად გახა რჯული > | თვის განმავ ლობაში ფაქტი ურად გახა რჯული > | თვის განმავ ლობაში ფაქტი ურად გახა რჯული > | თვის განმავ ლობაში ფაქტი ურად გახა რჯული > | თვის განმავ ლობაში ფაქტი ურად გახა რჯული > | თვის განმავ ლობაში ფაქტი ურად გახა რჯული > | თვის განმავ ლობაში ფაქტი ურად გახა რჯული > | თვის განმავ ლობაში ფაქტი ურად გახა რჯული > | თვის განმავ ლობაში ფაქტი ურად გახა რჯული > | თვის განმავ ლობაში ფაქტი ურად გახა რჯული > | თვის განმავ ლობაში ფაქტი ურად გახა რჯული > | თვის განმავ ლობაში ფაქტი ურად გახა რჯული > | თვის განმავ ლობაში ფაქტი ურად გახა რჯული > | თვის განმავ ლობაში ფაქტი ურად გახა რჯული > | 12= 3+4 -5-6 -8-10-11 > | 12= 3+4 -5-6 -8-10-11 >

Add row 1 fields (portal column name, widget, rules):

| # | x_name | Widget | Editable | Rules / options |
|---|---|---|---|---|
| 1 | COL_1 | autocomplete (server lookup, ddl_id=15, minlength=1) | yes |  |
| 2 | COL_2_1 | number | yes | data-m-dec=4 |
| 3 | COL_2_2 | number | yes | data-m-dec=4 |
| 4 | COL_3_1 | number | yes | data-m-dec=4 |
| 5 | COL_3_2 | number | yes | data-m-dec=4 |
| 6 | COL_4_1 | number | yes | data-m-dec=4 |
| 7 | COL_4_2 | number | yes | data-m-dec=4 |
| 8 | COL_5_1 | number | yes | data-m-dec=4 |
| 9 | COL_5_2 | number | yes | data-m-dec=4 |
| 10 | COL_6_1 | number | yes | data-m-dec=4 |
| 11 | COL_6_2 | number | yes | data-m-dec=4 |
| 12 | COL_7_1 | number | yes | data-m-dec=4 |
| 13 | COL_7_2 | number | yes | data-m-dec=4 |
| 14 | COL_8_1 | number | yes | data-m-dec=4 |
| 15 | COL_8_2 | number | yes | data-m-dec=4 |
| 16 | COL_9_1 | number | yes | data-m-dec=4 |
| 17 | COL_9_2 | number | yes | data-m-dec=4 |
| 18 | COL_10_1 | number | yes | data-m-dec=4 |
| 19 | COL_10_2 | number | yes | data-m-dec=4 |
| 20 | COL_11_1 | number | yes | data-m-dec=4 |
| 21 | COL_11_2 | number | yes | data-m-dec=4 |
| 22 | COL_12_1 | number | locked | data-m-dec=4 |
| 23 | COL_12_2 | number | locked | data-m-dec=4 |
| 24 | ID | hidden | yes |  |
| 25 | SEQ_NUM | hidden | yes |  |

Buttons: წინა | შემდეგი | ექსპორტი | იმპორტი

Help texts:
- საქონლის დასახელება და ოთხნიშნა კოდი (შეიტანეთ მარტო კოდი)
- ფაქტიური ნაშთის ოდენობა საანგარიშო თვის დასა წყისში
- თვის განმავლობაში ფაქტიურად მიღებული და წარმოებულის რაოდენობა
- თვის განმავლობაში ფაქტიურად გახარჯული
- ფაქტიური ნაშთი თვის ბოლოსთვის (12=3+4-5-6-8-10-11 )
- ნსაფ ის გამოწერით რეალიზებული ნავთობპროდუქციის რაოდენობა


### Tab 16 — დღგ-ის საერთო თანხის გაანგარიშება

Type: cell form. Inputs: 25, locked: 11. Import: no.

| Cell | Label | Portal id (column, editable) | Editable | Help text (portal tooltip) |
|---|---|---|---|---|
| (1) | დღგ, დარიცხული საგადასახადო პერიოდში განხორციელებულ ბრუნვაზე (მათ შორის ,დღგ დარიცხული უძრავი ქონების შექმნა/მართვა/რეალიზაციასთან დაკავშირებულ დასაბეგრ ბრუნვაზე ) | `control_358_1` (COL_1, locked) | locked | ივსება ავტომატურად. |
| (2) | 18%-იანი განაკვეთით დასაბეგრი ბრუნვა | `control_358_2` (COL_2, locked) | locked | ივსება ავტომატურად. |
| (3) | დღგ-ის ჩათვლის უფლებით გათავისუფლებული ბრუნვა | `control_358_3` (COL_3, locked) | locked | ივსება ავტომატურად. |
| (4) | საქართველოს ტერიტორიის გარეთ მომსახურების გაწევასთან/საქონლის მიწოდებასთან დაკავშირებული ბრუნვა | `control_358_4` (COL_4, yes) | yes | ინფორმაციული ხასიათისაა და მასში აისახება საანგარიშო პერიოდში საქონელი/მომსახურება, რომელიც გამიზნულია დღგ-ით დასაბეგრი ოპერაციის განხორციელებისთვის და რომლის გამოყენება მოხდა საქართველოს ტერიტორიის გარეთ მომსახურების გაწევისთვის/საქონლის მიწოდებისთვის. |
| (4 1 ) | საანგარიშო პერიოდში განხორციელებულ საქონლის მიწოდებაზე / მომსახურების გაწევაზე წინასწარ გადახდილი საკომპენსაციო თანხა/თანხის ნაწილი, რომელიც წინა საანგარიშო პერიოდების მიხედვით ექვემდებარებოდა დაბეგვრ | `control_358_4_1` (COL_4_1, yes) | yes | ინფორმაციული ხასიათისაა და მასში აისახება წინა საანგარიშო პერიოდებში მიღებული და დაბეგრილი საკომპენსაციო თანხა/თანხის ნაწილი (ე.წ. ავანსი), რომლის სანაცვლო საქონლის/მომსახურების მიწოდება განხორციელდა მიმდინარე საანგარიშო პერიოდში. |
| (4 2 ) | ყველა აქტივის ან მისი ნაწილის (დამოუკიდებლად ფუნქციონირებადი ქვედანაყოფის) სხვა დასაბეგრი პირისთვის მიწოდება | `control_358_4_2` (COL_4_2, yes) | yes | ინფორმაციული ხასიათისაა და მასში აისახება საწარმოს ყველა აქტივის ან დამოუკიდებლად მოქმედი ქვედანაყოფის მიწოდების შემთხვევაში ამ აქტივების ღირებულება ჯამურად (გარიგების შესაბამისად) |
| (4 3 ) | ყველა აქტივის ან მისი ნაწილის (დამოუკიდებლად ფუნქციონირებადი ქვედანაყოფის) სხვა დასაბეგრი პირისაგან მიღება | `control_358_4_3` (COL_4_3, yes) | yes | ინფორმაციული ხასიათისაა და მასში აისახება საწარმოს ყველა აქტივის ან დამოუკიდებლად მოქმედი ქვედანაყოფის მიღების შემთხვევაში ამ აქტივების ღირებულება ჯამურად (გარიგების შესაბამისად) |
| (4 4 ) | საწარმოს კაპიტალში ან ამხანაგობაში აქტივების შეტანა | `control_358_4_4` (COL_4_4, yes) | yes | ინფორმაციული ხასიათისაა და მასში აისახება აქტივების სხვა საწარმოს კაპიტალში შეტანის შემთხვევაში ამ აქტივების ჯამური ღირებულება |
| (4 5 ) | აქტივების გადაცემა საწარმოს რეორგანიზაციისას | `control_358_4_5` (COL_4_5, yes) | yes | ინფორმაციული ხასიათისაა და მასში აისახება აქტივების ჯამური ღირებულება, როდესაც ხდება მათი გადაცემა საწარმოს რეორგანიზაციის შემთხვევაში |
| (5) | დღგ-ისაგან ჩათვლის უფლების გარეშე გათავისუფლებული ბრუნვა | `control_358_5` (COL_5, locked) | locked | ივსება ავტომატურად. |
| (6) | დღგ ბრუნვის კორექტირებაზე / (7) | `control_358_6` (COL_6, yes)<br>`control_358_7` (COL_7, yes) | yes | აღნიშნულ სტრიქონებზე აისახება ბრუნვის კორექტირების შედეგები. მე-6 სტრიქონზე დამატებით გადასახდელი დღგ, ხოლო მე-7 სტრიქონზე შესამცირებელი დღგ.საყურადღებოა, რომ მე-7 სტრიქონის მონაცემი არ უნდა იყოს დანართი „ბ“-ს I ნაწილის და დანართი „ბ“-ს VIII ნაწილის დღგ-ის თანხების ჯამზე მეტი. |
| (8) | უკუდაბეგვრის წესით დარიცხული დღგ | `control_358_8` (COL_8, locked) | locked | ივსება ავტომატურად. |
| (9) | დღგ უკუდაბეგვრით დასაბეგრი ოპერაციის კორექტირებაზე / (10) | `control_358_9` (COL_9, yes)<br>`control_358_10` (COL_10, locked) | mixed | დღგ-ით უკუდაბეგვრით დასაბეგრი ოპერაციის კორექტირების შედეგად, დამატებით გადასახდელი დღგ-ის თანხა. // ივსება ავტომატურად. |
| (11) | დღგ-ის ჩასათვლელი (შესამცირებელი) თანხა | `control_358_11` (COL_11, locked) | locked | ივსება ავტომატურად. |
| (12) | დღგ ჩასათვლელი თანხის კორექტირებით / (13) | `control_358_12` (COL_12, yes)<br>`control_358_13` (COL_13, yes) | yes | აღნიშნულ სტრიქონებზე აისახება ჩასათვლელი თანხის კორექტირების შედეგები, კერძოდ, ჩათვლილი თანხის შემცირების შემთხვევაში ბიუჯეტში გადასახდელი დღგ-ის თანხა მიეთითება მე-12 სტრიქონში, ხოლო ჩათვლილი თანხის გაზრდის შემთხვევაში დღგ-ის შესამცირებელი თანხა - მე-13 სტრიქონში. |
| (14) | დღგ-ის თანხა საქონელზე/მომსახურებაზე, რომელიც ჩათვლილი იყო ადრე და ექვემდებარება აღდგენას | `control_358_14` (COL_14, yes) | yes | აღდგენას დაქვემდებარებული ჩათვლილი დღგ-ის თანხა (მათ შორის ჩათვლილად მიჩნეული) იმ საქონელზე/მომსახურებაზე, რომელიც საანგარიშო პერიოდში გამოიყენება ოპერაციებში, რომელზეც ჩათვლა არ ხორციელდება. |
| (14 1 ) | დღგ-ის თანხა, რომელზეც ითვლება, რომ პირმა მიიღო ჩათვლა | `control_358_14_1` (COL_14_1, yes) | yes | მიეთითება მე-14 სტრიქონში ასახული თანხიდან, დღგ-ის თანხა იმ საქონელზე, რომლის მიღების საანგარიშო პერიოდში დღგ ჩათვლილად იქნა მიჩნეული. |
| (15) | ჯამი / (16) | `control_358_15` (COL_15, locked)<br>`control_358_16` (COL_16, locked) | locked | ივსება ავტომატურად. |
| (17) | სულ გამოანგარიშებულია ბიუჯეტში გადასახდელად (სტ.15-სტ.16, როცა სტ.15>სტ.16) | `control_358_17` (COL_17, locked) | locked | ივსება ავტომატურად. |
| (18) | სულ გამოანგარიშებულია შესამცირებლად (სტ.16-სტ.15, როცა სტ.16>სტ.15) | `control_358_18` (COL_18, locked) | locked | ივსება ავტომატურად. |



### Tab 17 — სპეციალური სქემით დაბეგრილი ოპერაციების შესახებ ნაწილი III - დღგ-ს საერთო თანხის გაანგარიშება დანართი №III-19 6

Type: cell form. Inputs: 14, locked: 5. Import: no.

| Cell | Label | Portal id (column, editable) | Editable | Help text (portal tooltip) |
|---|---|---|---|---|
|  | დასაბეგრი ოპერაციები / მოგების მარჟა(სვ.4-სვ.3) / დღგ-ს თანხა ((სვ.4 - სვ.3) : 1,18 x 0,18) |  | yes |  |
|  | საქონლის შესყიდვის ფასი / საქონლის მიწოდების ფასი |  | yes |  |
| (1) | საანგარიშო პერიოდში მიწოდებული მეორადი ნივთები: | `control_359_1` (COL_1, yes)<br>`control_359_1_4` (COL_1_4, yes)<br>`control_359_1_5` (COL_1_5, locked) | mixed |  |
| (2) | საანგარიშო პერიოდში მიწოდებული ხელოვნების ნიმუშები: | `control_359_2` (COL_2, yes)<br>`control_359_2_4` (COL_2_4, yes)<br>`control_359_2_5` (COL_2_5, locked) | mixed |  |
| (3) | საანგარიშო პერიოდში მიწოდებული საკოლექციო ნივთები: | `control_359_3` (COL_3, yes)<br>`control_359_3_4` (COL_3_4, yes)<br>`control_359_3_5` (COL_3_5, locked) | mixed |  |
| (4) | საანგარიშო პერიოდში მიწოდებული ანტიკვარიატი: | `control_359_4` (COL_4, yes)<br>`control_359_4_4` (COL_4_4, yes)<br>`control_359_4_5` (COL_4_5, locked) | mixed |  |
| (5) | სულ დარიცხული დღგ (სტ.1 + სტ.2+ სტ.3+ სტ.4) | `control_359_5` (COL_5, locked) | locked |  |



### Tab 18 — დანართი "ა" ნაწილი IV დღგ-ით დასაბეგრი თანხა ტურისტული საწარმოს სტატუსის გაუქმებისას

xlsx import: yes. Scripts: grid_107_sum

Grid 1 columns: ტურისტული საწარმოს ობიექტი > საკადასტრო კოდი | ტურისტული საწარმოს ობიექტი > სტატუსის მინიჭების თარიღი | ტურისტული საწარმოს ობიექტი > სტატუსის გაუქმების თარიღი | სსკ-ს 172-ე მუხლის მე-4 ნაწილის „ქ“ ქვეპუნქტით გათვალისწინებული დღგ-ისგან ჩათვლის უფლებით გათავისუფლებული ბრუნვის 1.18-ზე გაყოფის შედეგად მიღებულ თანხა | სასტუმროს ფუნქციონირების შედეგად დღგ-ით დასაბეგრი ოპერაციების (გარდა დღგ-ისგან გათავისუფლებული ოპერაციებისა) დეკლარირებული (მათ შორის, საგადასახადო ორგანოს მიერ აღნიშნული ობიექტის მიხედვით დამატებით დარიცხული) თანხა (დღგ-ს გარეშე) | დასაბეგრი თანხა(სვ.5-სვ.6)

Add row 1 fields (portal column name, widget, rules):

| # | x_name | Widget | Editable | Rules / options |
|---|---|---|---|---|
| 1 | COL_2 | text | yes |  |
| 2 | COL_3 | date | yes |  |
| 3 | COL_4 | date | yes |  |
| 4 | COL_5 | number | yes |  |
| 5 | COL_6 | number | yes |  |
| 6 | COL_7 | number | locked |  |
| 7 | ID | hidden | yes |  |
| 8 | SEQ_NUM | hidden | yes |  |

Buttons: წინა | შემდეგი | ექსპორტი | იმპორტი

Help texts:
- დღგ-ით დასაბეგრი თანხა ტურისტული საწარმოს სტატუსის გაუქმებისას

# MoF Order #996 — Tax Administration Instruction (original 2010 text)

> **Source document:** `matsne-1167887-0.doc` — Order of the Minister of Finance of Georgia #996, 31 December 2010, "On Tax Administration" (`გადასახადების ადმინისტრირების შესახებ`).
> **Full converted text:** [`sources/mof_order_996_2010_ka.md`](sources/mof_order_996_2010_ka.md) (Georgian, 906 KB).
> **Scope of this file:** what the order is, how it is built, what each part actually governs, where it is wrong on its own terms, and what is and isn't usable today.

---

## Read this first — you have the wrong version for operational use

The `-0` in the filename is matsne's publication index: this is **publication 0, the text as adopted**, effective 1 January 2011. It carries no amendment notes, no consolidation date, and no marginal history. Anything decided from it today will be wrong on most operational detail.

Two checks that settle it without leaving the file:

| Evidence | What it proves |
|---|---|
| Arts. 40–41 build a **classic profit-tax declaration** — gross income minus deductions, taxable profit, 5-year loss carry-forward | Predates the Estonian-model CIT (in force 1 Jan 2017). Chapter XI's CIT half is dead. |
| Arts. 25, 52–54, 57–60 describe **paper strict-accounting forms** with printed series, six-digit numbers, a purchase fee, courier dispatch and surrender of spoiled blanks by 15 January | Predates the electronic rs.ge waybill and e-invoice services our `rs_*` modules talk to. |

A consolidated English digest of the **current** order (as at 24 April 2026) already exists at `~/.claude/skills/synced/.../georgian-tax-advisor/references/order-996-administration.md`. Comparing the two shows the drift concretely — these articles exist in the consolidated text and are **absent here**: Art. 6¹ (taxpayer category), Art. 7¹ (GRS-initiated registration), Art. 7² (obligations during dissolution), Art. 17¹ (waiving appeal rights), and the whole small-business / fixed-tax / international-company / marketplace regime set. Our own [`rs_einvoice_down_payments.md`](rs_einvoice_down_payments.md) cites "Order #996 Art. 53" for a 1 September 2025 advance-settlement rule; **Art. 53 in this text is only about issuing an invoice on supply and says nothing about advances**. Same article number, different content.

**Use this file for:** understanding the architecture the current order inherited, tracing why a rule exists, and reading the 2011 baseline of a provision. **Do not use it for:** anything a client or the tax authority will act on.

---

## What the order is

The Tax Code of Georgia states what is taxed. Order #996 states **how you comply** — which form, filed where, by when, in how many copies, and what the tax authority does with it. It is issued under Tax Code art. 2(3), and Article 3 of the enacting order repeals **20 earlier ministerial orders**, folding registration, tax secrecy, e-communication, advance rulings, personal accounting cards, simplified bookkeeping, every declaration form and the whole petroleum/excise-stamp machinery into one instrument. That consolidation is the reason the document is 187 pages: it is not a set of principles, it is the complete operational rulebook, forms included.

The enacting order also preserves strict-accounting forms already issued to taxpayers (Art. 2), so the transition on 1 January 2011 did not invalidate stock in hand.

---

## Structure at a glance

6 parts (`კარი`) · 26 chapters (`თავი`) · 107 articles (`მუხლი`) · ~90 annexes

| Part | Chapters | Articles | Subject |
|---|---|---|---|
| I | I–VIII | 1–23 | Tax registration and communication with the authority |
| II | IX–XI | 24–45 | Income and profit taxes: bookkeeping, deductions, declarations |
| III | XII–XIX | 46–75 | VAT: registration, invoices, petroleum, reverse charge, exemptions, credit, reporting |
| IV | XX–XXII | 76–86 | Excise: declaration, stamps, exemptions |
| V | XXIII–XXIV | 87–92 | Property tax: enterprise and individual |
| VI | XXV–XXVI | 93–107 | Fees: gambling business, natural resources |

Annex numbering follows the part: `I-01…I-21`, `II-01…II-11`, `III-01…III-25`, `IV-01…IV-10`, `V-01…V-04`, `VI-01…VI-12`.

---

## Part I — Registration and communication (Arts. 1–23)

**The spine of the whole system is the identification number.** Art. 1 defines registration as two acts: assigning a TIN and writing the record into the unified register. Art. 3 makes the number structural — a seven-digit territorial range plus a legal-form code — and then makes it permanent: *changing it (except where wrongly assigned) or reusing it for another person is prohibited*. Art. 7 closes the loop by forbidding reassignment of a liquidated or deceased person's number. Every later mechanism in the order — the personal accounting card, the invoice registers, the relief registers — hangs off that one immutable key.

Registration is **immediate on filing** (Art. 3(7)) and must happen **before economic activity starts** (Art. 2). Two escapes from the procedure are worth knowing: a Georgian citizen who is not an entrepreneur can simply quote the personal number on the ID card when declaring and paying, with no registration procedure at all (Art. 2(4)); and if a person trades without registering, the authority **registers them itself** off an offence protocol, filling in the application form on their behalf (Art. 5).

**Tax secrecy (Ch. II)** is drawn as an exhaustive list rather than a principle — declarations, letters, audit orders and acts, offence protocols, assessment orders, demands, accounting cards, settlement data, payment and inkaso orders, data on waybills and invoices, and bank-sourced information (Art. 9(1)). The obligation is **perpetual**. Only four things are outside it: status, name, address, TIN. Art. 10(4) adds the rule that matters in practice: *information about a taxpayer can never be made secret from that taxpayer*.

**Electronic communication (Ch. III)** is the part that aged best. Art. 11(2) already grants an unsigned electronic document filed through rs.ge **the same legal force as a signed and sealed paper one**. Onboarding is by video call or application I-07, live in 3 working days. Two rules define the risk boundary: a document that fails to register on the site **is not received, whatever the cause** (Art. 12(2)), and a document the authority sends is **served the moment the addressee opens it**, with the site reporting that back (Art. 12(3)).

**Tax demand (Ch. VI)** has three grounds, eight mandatory contents and a 5-working-day service deadline from the assessment decision; three forms exist (I-09 general, I-10 individual property, I-11 land). The mirror instrument, the **taxpayer's request** (I-13), has exactly one ground: overpayment.

**Advance rulings (Ch. VII)** run a heavy pipeline — any territorial office triages in 2 working days, a working group drafts, the Revenue Service advisory council comments, and the **Minister of Finance must agree** before the ruling issues (Art. 19). Five refusal grounds block it, all variations on "this period or issue is already under audit, protocol, or criminal proceedings". A separate track (Art. 20) handles commodity code and country-of-origin rulings — one good per application, laboratory opinions at the applicant's cost, and amendment possible only **before the goods declaration is filed**.

**Personal accounting card (Ch. VIII)** is the ledger the taxpayer never sees directly but every dispute runs through. A card is opened per tax type, per offence type, per fee type and per abolished tax, for **every active taxpayer at the start of each tax year**. Two special cases drive later chapters: reverse-charge VAT gets its **own card** (Art. 22(7)), and excise gets **two** — "excise stamps" for stamp purchases and "excise" for the monthly declaration (Art. 22(8)).

---

## Part II — Income and profit taxes (Arts. 24–45)

### The waybill is the primary document, and it is not a credit document

Art. 24(2) makes the **waybill (`სასაქონლო ზედნადები`) mandatory for every domestic supply of goods in economic activity**, and Art. 24(3) extends it to moving goods *between a company's own branches, workshops and sites*. Art. 25 then spends 5,900 characters on the mechanics: three identical copies (buyer, seller, carrier), the date equal to the supply date with **the month written in words**, distribution rules where the distributor carries blank waybills for its own buyers, a **partially-filled waybill** that can accumulate repeated supplies to one buyer across a calendar month and must be closed by the last day of that month, and a return convention (`უკან დაბრუნება` in column 9).

The last paragraph is the one to remember: **Art. 25(22) — a waybill is not a ground for VAT or excise credit.** The waybill proves movement; only a tax invoice, a goods declaration or a reverse-charge payment document proves credit. Every later argument about invoice-vs-waybill in the order descends from this split.

Art. 26 adds the first turnover-based digitisation threshold in the document: **over GEL 1 million annual turnover, the waybill register must be electronic**, carrying number, date, both parties' names and TINs, and value.

### Simplified bookkeeping is a physically sealed book

Art. 28 is a period piece worth reading precisely because it shows what "simplified" meant: a laced, numbered, **physically sealed** book (II-02), sealed on application II-03, one per tax year unless the authority allows more, entries in chronological order from primary documents, **cash basis** (income on receipt or the right to dispose, expenses on actual payment) except for depreciable assets, foreign-language documents needing Georgian translation, corrections justified and signed, closure on 31 December with the totals feeding the annual declarations, and a **6-year retention**. Art. 28(11) is explicit that keeping the book does not waive the waybill obligation.

### Art. 29 — the 10% related-party safe harbour

Related-party status **does not affect a transaction** if the recipient could buy the analogous good or service from an unrelated person at a price not more than **10% above** the related-party price. "Analogous" is defined by comparable conditions: physical characteristics, quality, reputation, seasonality, quantity, payment terms. A note in the text states the article applies **beyond income and profit tax** — it is a general valuation rule.

### Art. 30 — the leasing article

At 17,900 characters with **eleven worked examples**, this is the longest article in the order and the only one that teaches by arithmetic. It answers a single question: how does a lessor account for an asset it has leased out?

The mechanism, in order:

1. Each leased-out asset becomes **its own group**, like a building. Assets under GEL 1,000 are not grouped separately.
2. A previously-depreciated asset is **recomputed** at lease start (original cost less depreciation at the statutory rate for the years in use), the donor group's balance drops by that amount, and any excess over the group balance falls into gross income. If the asset had been fully written off under TC art. 112, the **whole** recomputed value enters income.
3. An arm's-length test: lease payments discounted at *(the Minister's TC-107 rate less 55% of it)* must not be below the book-value-minus-residual difference. Example 6 runs it at a 31% statutory rate → 14% discount rate → annuity factor 3.433, and forces the lessor to gross annual lease income from 5,000 up to 5,521.
4. Depreciation on the leased-out asset equals the **principal (discounted) part** of each period's payment, capped at the group balance — a finance-lease amortisation schedule expressed as tax depreciation.
5. Termination **without** buy-out: recompute depreciation normally, return the asset to its ordinary group, excess to income (a negative difference is deducted). Termination **with** buy-out: proceeds to income, group zeroed and deducted — and the proceeds may not be below *remaining discounted principal + residual value* (Example 10 imputes 7,238 against an actual 6,000).
6. The lessee books the asset at **what it actually paid or owes**, excluding amounts already expensed as lease service.

### Declarations: the box-by-box half of the order

Arts. 32–45 pair each declaration with an article that walks its boxes. The pattern is identical everywhere: Part I identity and type (primary/corrected), Part II filled by the tax authority, Part III the computation, TIN on every page, signature certifying truth and completeness, and an obligation to **add a note whenever a box must hold something other than what the instruction says**.

| Declaration | Form | Filing rule |
|---|---|---|
| Annual PIT | II-04 | Art. 32–33; Art. 34(7) sets 1 April for employees of diplomatic-status organisations |
| Inheritance / gift (3rd–4th line heirs, ≥ GEL 150,000) | II-05 | By the 15th of the month after transfer; **tax payable over a 2-year schedule** (Art. 36(2)(ვ)) |
| Withholding at source | II-06 | By the 15th of the following month |
| Recipient information / international-enterprise services | II-07 / II-08 | Within 30 calendar days of year end |
| Corporate profit tax | II-09 | Art. 40–41 — **obsolete since the 2017 CIT reform** |
| Partnership profit/loss distribution | II-10 | Art. 42–43; members and their shares listed in Part IV |
| Write-off of assets destroyed under special conditions | II-11 | Art. 44 — decision of the MoF Disputes Council, covers occupied territories |

Two details in the withholding declaration are worth carrying forward because they still shape payroll reporting: **in-kind salary is dated to the last day of the month** (Art. 38(7)(ა)), and the declaration collects statistics alongside tax — headcount, output value, cash turnover, and the **maximum and minimum salary paid** in the period (boxes 35–41).

Art. 34 handles a narrow but recurring case: international organisations with diplomatic status are **not tax agents**, may volunteer to act as one (and then bear no Tax Code Part XIII liability — the individual remains the taxable person), and have **no reporting obligation at all**. The employee pays PIT monthly by the 15th and files the annual declaration by 1 April.

---

## Part III — VAT (Arts. 46–75)

This is the part with the longest operational half-life, because the documents it defines — the tax invoice, the correction invoice, the credit rules — survived into the electronic era with their logic intact.

### Registration edge cases

Art. 46(2) is the one people get wrong: when a registered VAT payer **dies**, whoever actually holds the property and continues the business must notify within **2 working days** and request registration, and is treated as a VAT payer **from the date of death** — not from the application. Deregistration (Art. 47) can be initiated by the authority in writing, with the payer's consent returned on form III-03.

### Art. 50 — the anti-abuse safeguard

An operation is "goodsless" or a transaction "fictitious" only if it is established that **it did not happen between the persons named in the documents**. Then the protective sentence: *the mere fact that the supplier has no documents proving it bought the goods or incurred the cost is not sufficient grounds* to treat the operation as goodsless. This is the article that stops a buyer's credit being denied because of the seller's missing upstream paperwork.

### The three documents, and when each is used

| Document | Annex | When |
|---|---|---|
| Tax invoice (`საფ`) | III-05 | Default; the **same form** is used for corrections |
| Special tax invoice | III-06 | Supply **with transport** — and then **no waybill is required** (Art. 52(2)) |
| Petroleum special tax invoice (`ნსაფ`) | III-09 | The petroleum products listed in III-08 |
| Continuation sheet | III-07 | Too many goods lines for one invoice |
| Computer invoice (`კსაფ`) | — | Fully computerised payers supplying services or utilities continuously (Art. 56) |

Mechanics that still matter (Art. 53): two copies of equal force; **separate invoices for the supply and for the correction**; line 2 only filled on a correction; services get a dash in box 7 and, in box 8, either the service date or, if the service spans more than a day, **the reporting period written in words**; an operation **exempt with the right of credit** shows `0` on the VAT lines; wrong details other than the VAT amount are corrected by crossing out and writing over, signed. On the buyer's request, several waybill-based supplies in one period may be summarised into **one invoice** with a mandatory continuation sheet.

Delivery and control (Art. 54): the standard invoice reaches the buyer **within 30 calendar days of the request**; the transport-accompanying III-06 reaches them **immediately on supply**. Handing a wrongly-filled invoice to the buyer is **forbidden**; all copies are surrendered for cancellation by **15 January** of the following year. A lost issued invoice is replaced by a new invoice for the same operation **bearing the same date**, noting the lost one's series and number.

The correction invoice (Art. 55) has a distinctive shape: quantity, compensation and tax appear as **two rows — before correction and after correction** — and the "Total" row carries the **difference** between them. This is the ancestor of every correction flow our rs modules implement.

Art. 56 attaches a hard consequence to register quality: if the buyer's data are **missing or wrong** in the computer-invoice register, **VAT credit on those invoices is blocked** until the payer files a reasoned written explanation.

### Petroleum (Ch. XIV) — the strictest regime in the order

Arts. 57–62 exist because fuel was the fraud surface. The `ნსაფ` is a protected strict-accounting document with a **series that encodes the operation**: `ai` import-to-storage, `ash` export-to-border or internal transfer, `as` wholesale, `aa` retail (computer versions prefix `k`). Four copies. One product, one vehicle (one wagon). Corrections are allowed **only before transport begins** and **never** to the date, quantity, value, VAT/excise or the stationary-object codes. And Art. 58(9): **an incorrectly or incompletely filled `ნსაფ` has no legal force and is not a credit document** — a harder rule than anything applied to ordinary invoices.

Around it sits a control apparatus: stationary objects (depots, refineries, tanks) must be registered (III-14/III-15); wholesale and retail **daily journals** (III-16/III-17) are kept at the object, may not be removed, must be written *before* transport starts or unloading begins, may not be erased, and are retained 6 years; blank forms are issued only against a documented application (III-12/III-13) within **72 hours** (immediately for imports), refusable if the applicant's reports are missing. Art. 62(5) even codifies a twelve-condition specification for **fuel-card loyalty discount systems** — down to requiring that the price actually paid is not below cost and that every card is chipped or magnetic, registered and numbered.

Also note Art. 60(5): **paper invoice forms were sold, not given** — the fee set by Government Decree #96 of 30 March 2010.

### Reverse charge (Ch. XVI) — where the credit comes from the bank

Art. 66 is the article to internalise. The payment order must be labelled "VAT accrued by reverse charge", and then: **the bank debit document is itself the VAT credit document**, credited in the declaration of the period **in which the bank debited the money** — not the period of the service. Amounts sitting on the reverse-charge special card may **not** be treated as overpayments or used against other arrears before the period's return is filed. And where the authority transfers another tax's overpayment to cover reverse-charge VAT, **its notice is the payment document** that grants the credit.

### Exemptions with a register behind them (Ch. XVII)

Art. 71 is the model that our tax configuration mirrors: the donor files the participant list twice a year, the participant applies (III-22), the authority issues a certificate (III-23) within **10 working days** and enters the person in a **unified electronic register** — and then the supplier **must check the register before issuing the invoice** and only then writes `0` on the VAT line. Relief is a register lookup, not a certificate on paper.

Art. 68 handles diplomats with a value threshold: **up to GEL 100** per supply, the accreditation card plus a signed cash-register receipt is enough and no invoice is needed; **above GEL 100**, a tax invoice is mandatory with `0` VAT and the **accreditation card number written in the buyer's TIN field**. VAT wrongly charged is reclaimed on III-21 within **3 months**, refunded within **1 month**, with a 15-day defect cure that suspends the clock.

Art. 69 lists the export/transit carriage evidence by transport mode (CMR or TIR, bill of lading, air waybill, rail consignment note) plus the goods declaration and the service contract — and adds the trap: if the **carrier changes inside Georgia**, the exemption holds only if the handover happened **under state control**.

### VAT credit and its unwinding (Ch. XVIII)

Art. 72 sets which documents escape the statutory time limits on invoices: the goods declaration, the reverse-charge payment document, the temporary-import payment document, and fee-payment documents of listed public legal entities whose tariffs are VAT-inclusive by law. On registration taking effect, credit is available on **inventory** but **not on fixed assets already in use**.

Self-built buildings get their own treatment: input VAT on construction is creditable, and the self-charged VAT on commissioning is credited **fully** if the building serves only credit-eligible operations, **fully** if the mixed use is inseparable and last year's exempt-without-credit turnover was **under 20%** of total, otherwise **partially in the year's final declaration** on the annual ratio.

Art. 73 is the unwinding engine:

| Trigger | Adjustment |
|---|---|
| Exempt-without-credit operations reach **5% or more** of annual turnover | Credit recalculated / cancelled |
| Inventory written off under the Tax Code; losses within authorised norms | **No** cancellation |
| Mixed inseparable use | Cancel pro rata in the period, then **true up in the year's final period** on the annual ratio |
| Fixed assets other than buildings | **1/5 per year for 5 years** from commissioning |
| Self-built buildings | **1/10 per year for 10 years** |

The declaration wiring follows (Art. 75): boxes 20 and 21 are filled **only in the last period of the tax year** — the negative true-up difference to box 20, the positive to box 21 — and both post to the personal accounting card.

---

## Part IV — Excise (Arts. 76–86)

Art. 76 carries a rule that generalises well: **a corrected declaration must be filed on the form that was in force for the period being corrected.**

The excise declaration (Art. 77) is a credit machine rather than a rate table — lines for input excise capped at the excise computed on the output, excise on goods held for **ageing/maturing**, restoration of credit on returned goods and on ageing stock never used in taxable operations, and recovery of excise paid on exports later documented. Lines 14 and 15 are the transfer mechanism between the taxpayer's **"excise" card and "excise stamps" card** — the two-card design from Art. 22(8) paying off.

Stamps (Ch. XXI) are specified physically: the glue must make removal impossible without damage, the alcohol stamp goes over the cap in a **"Г" shape** with the volume indicator up and the flag to the side, hard cigarette packs are stamped left-side-through-back, soft packs from the top across three sides. Nominal values are set **in euro per 1,000 stamps**, converted at the NBG rate at settlement — EUR 6.6 and 6.595 for the two alcohol stamp families, 1.72 to 8.06 across the tobacco colours, 4.03 for beer. *(Treat these numbers as 2010 values only.)*

Two commercial rules survive: **damaged stamps are not taken back** — with one exception for stamped cigars needing repackaging, allowed only by individual act of the Revenue Service head; and unused stamps may be exchanged for stamps of a different specification but **the same origin** (local for local, import for import).

Art. 83 sets out confiscation of unstamped goods with the safeguards that make it usable — two officers minimum, the order and ID shown, a protocol listing the goods and the documents they were bought on, **seizure proceeding even if the owner is absent** (noted in the protocol), only the unstamped goods taken, 5 days to a MoF warehouse, and every case reported to Internal Audit and the Investigation Department. For wrongly-stamped goods the person who **collected the stamps** is identified for follow-up.

Art. 84 introduces the **bank guarantee alternative** for bunker and aviation fuel: pay the excise on import or lodge a guarantee for at least the excise, valid at least 2 months, released against acceptance acts (IV-08) for the volume actually delivered on board.

---

## Part V — Property tax (Arts. 87–92)

Two declarations, V-01 for enterprises and V-03 for individuals, both split by **local self-government unit** because the rate is local. Two things are easy to get wrong and are stated plainly:

- **The two halves of the declaration use different reference dates.** Non-land property is reported **for the past tax year**; land is reported as at **1 April of the current tax year** (Arts. 88(4)(კ) and 88(5)(კ), repeated for individuals in Art. 91).
- **Leased-out property keeps a shadow valuation.** Its value is the book value at the moment of leasing, and thereafter *the residual value it would have had if it had not been leased out* (Art. 88(4)(გ.ბ)) — the mirror of the Art. 30 treatment on the income-tax side.

For individuals the tax authority, not the taxpayer, fills the rate and tax columns. The family declaration collects the household's prior-year income in three bands (over 40,000 / 40,000–100,000 / over 100,000), which is the threshold mechanism for the individual property tax. A person with no filing obligation under TC art. 205(13)(a) says so on form V-04.

---

## Part VI — Fees (Arts. 93–107)

**Gambling (Ch. XXV)** is administered through physical **payment marks** — strict-accounting stickers, issued **free**, bought in the quarter before the reporting quarter, with the quarter digit **cut out** of the mark at issue, affixed visibly on each table, machine, roulette wheel and cash desk on the first day of the quarter and removed on the last. Start mid-quarter and the marks are issued for the current quarter but **the fee is paid in full**. Reserve equipment must be **sealed**, and Art. 103(4) closes the obvious hole: an unsealed reserve table must be removed from the hall, otherwise it counts as operating and is charged.

**Natural resources (Ch. XXVI)** has one genuinely non-obvious feature: column 3 of the computation uses **six different measurement periods depending on the resource** — annual for agricultural water, monthly for timber and for "other resources", quarterly (¼ of the licensed annual) for mineral and bottling water, half-yearly (½ of annual) for licensed minerals, monthly-derived-from-daily for CO₂, and the full licensed share of the annual quota for Black Sea fishing.

---

## What this means for our Odoo work

The 2010 text does not describe the interfaces our modules use, but it describes the **legal objects** they move, and several of its rules are still the reason our code behaves as it does.

| Order concept | Where it surfaces in our stack |
|---|---|
| Waybill as movement proof, **never** a credit document (Art. 25(22)) | `rs_waybill` ↔ `rs_einvoice` separation; the bridge links them but VAT comes only from the invoice side |
| Special invoice **replaces** the waybill when transport accompanies supply (Art. 52(2)) | Why a supply can legitimately have an invoice and no waybill |
| Correction invoice = **two rows, before and after, totals as the difference** (Art. 55) | The shape of every correction flow in [`rs_waybill_einvoice_fix_plan.md`](rs_waybill_einvoice_fix_plan.md) and [`rs_einvoice_down_payments.md`](rs_einvoice_down_payments.md) |
| Reverse-charge credit arises **when the bank debits**, evidenced by the payment document (Art. 66) | The payment-time withholding/RC design in [`gec_l10n_ge_tax.md`](gec_l10n_ge_tax.md) |
| Credit unwinding: 5% trigger, 1/5 over 5 years, 1/10 over 10 years, year-end true-up in boxes 20/21 (Arts. 73, 75) | Nothing in our stack computes this — it is a known gap, not an implemented feature |
| Exemption by **register lookup before invoicing** (Art. 71(6)) | The pattern behind fiscal-position-driven 0% supply |
| In-kind salary dated to the **last day of the month** (Art. 38(7)(ა)) | `geo_payroll` benefit and in-kind handling |
| Withholding declaration carries headcount, max and min salary (Art. 38(6)) | Fields a Georgian payroll report needs that standard Odoo has no place for |
| Two-year payment schedule on gift/inheritance PIT (Art. 36(2)(ვ)) | Not modelled anywhere |
| Property tax: land at **1 April current year**, other property for the **past year** | Any property-tax reporting we build must carry two reference dates |

**Do not** port any deadline, threshold or rate from this file into code. Take the structure; take the current numbers from the consolidated text.

---

## Defects in the original document

These are errors in the 2010 text itself, not conversion artefacts. They are listed because they change what a literal reading yields.

| Where | Problem |
|---|---|
| Art. 24(2) | Cites the special VAT invoice as annex **№II-06**; II-06 is the withholding declaration (Art. 37). The special invoice is **III-06** (Art. 52(2)). |
| Art. 54(1) | Refers to forms **№II-05 / №II-06**; means **III-05 / III-06**. |
| Art. 62(1)(a) | Cites the wholesale petroleum journal as annex **№II-16**; it is **III-16**. |
| Art. 33(5)(მ) | "income tax = the taxable amount shown in **box 36** × rate" — the taxable amount is box **35**; box 36 is the tax itself. |
| Art. 38(7)(ე) | Annex "a" column 5 must equal declaration **box 31**; the enterprise withholding total is box **34**. Box 31 is the 15% slice. |
| Art. 30 | Two examples are both numbered **"Example 6"**. |
| Art. 28 | Two paragraphs are both numbered **13**. |
| Art. 34 | Printed as "მუხლი **.34.**" — stray leading dot; the article is otherwise normal. |
| Art. 72 | Paragraph numbering jumps **4 → 6**; there is no paragraph 5. |
| Art. 78 | Paragraph numbering jumps **4 → 6**; there is no paragraph 5. |
| Art. 81 | Paragraphs **2 and 3 are missing**, yet paragraph 5 conditions the return on "the requirements of paragraphs 1 and 2". |
| Throughout | Frequent typos in the Georgian (`საგადასახდო`, `პიზიკური`, `აღრიცვხის`, `მოგების გადასაახადი`), reproduced verbatim in the conversion. |

---

## Conversion fidelity — what the Markdown does and does not contain

The full text was produced with `textutil` (binary `.doc` → UTF-8 text) and then structured into headings by part / chapter / article / annex. Parsing was verified: **107 of 107 articles** and 6 parts and 26 chapters are present and correctly ordered.

What is lost, and you should not assume otherwise:

1. **Table structure.** The legacy `.doc` tables do not survive `textutil`; `pandoc` on the HTML output finds **zero** `<table>` elements. Every annex form is therefore a flat sequence of its cell labels, in reading order. Field names survive; the grid does not.
2. **Ten embedded OLE objects are gone entirely** — only the placeholder text `EMBED Excel.Sheet.8` remains. These are the forms most worth having:

   | Annex | Form |
   |---|---|
   | II-01 | Waybill (2 objects) |
   | III-06 | Special tax invoice |
   | III-07 | Tax invoice continuation sheet |
   | III-11 | Petroleum consumption information |
   | III-25 | VAT declaration |
   | V-01 | Enterprise property tax declaration (4 objects) |
   | VI-11 | Gambling fee declaration (`Msxml2.SAXXMLReader`) |

3. **Floating text boxes were dumped at the end of the document** by the converter, out of order and partly in Latin transliteration (`aqcizuri marka`, `xelmZRvaneli`). Everything after Art. 107 was **cut** at the conversion stage; that content is form-field labels, not normative text.
4. **Page and image references are dead.** `PAGE` field codes and figure references such as "IV-02, fig. 6" point to images that do not exist in the text file.
5. Two annexes are mis-labelled in the source itself (`№1-01` printed over the waybill annex header); the conversion reproduces the error rather than silently fixing it.

For the annex form layouts, go back to the original `.doc` or to matsne.

---

## Coverage of this analysis

All **107 articles** were read end to end from the converted text and are reflected above or in the structure map. The ~90 annexes were **not** read cell by cell: they are form layouts, their structure is flattened by the conversion, and ten of them are missing entirely (above). Where an article describes an annex's columns — Arts. 33, 38, 41, 43, 58, 75, 77, 88, 91, 105, 107 — that description was read in full and is the basis for what this file says about those forms.

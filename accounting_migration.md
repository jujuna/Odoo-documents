# Odoo 19 Accounting Migration Tutorial

> Audience: Accounting and implementation teams migrating from another accounting system (QuickBooks, Xero, Sage, SAP, 1C, custom ERP) to Odoo 19.
>
> Goal: Start Odoo with correct Balance Sheet, P&L, Aged Receivable/Payable, inventory valuation, and fixed assets on day one.
>
> Scope: How to import opening balances and open accounting data, what can go wrong, and how to prevent it.

---

## 1) What This Tutorial Gives You

By the end of this tutorial you will know:

- Which migration approach to choose (opening only, opening + open items, mid-year, full history).
- How Odoo 19 opening balances actually work internally.
- The exact import sequence that avoids double counting.
- How to handle AR/AP, inventory, banks, fixed assets, and multi-currency safely.
- Which validation checks must pass before go-live.
- The most common failure cases and how to fix them.

---

## 2) First, Choose Your Migration Type

Pick one case before you build files.

| Case | Use it when | Data imported into Odoo | Effort | Risk |
|---|---|---|---|---|
| A. Opening balances only | Small business, no need invoice-level history in Odoo | Trial balance totals only | Low | Medium (AR/AP aging detail weak) |
| B. Opening balances + open items (recommended) | Most real projects | Trial balance + open AR/AP + inventory + assets + bank opening | Medium | Low if validated |
| C. Mid-year cut-over | You cannot wait for year-end | YTD balances + open items + all controls around P&L carry-over | Medium-High | Medium |
| D. Full historical migration | Legal/audit requirement for full drill-down in Odoo | Full journal history + reconciliations + taxes | High | High |

This tutorial is built for **Case B**, with notes for A/C/D.

---

## 3) How Odoo 19 Opening Balances Really Work (Critical)

These mechanics come directly from Odoo 19 source.

### 3.1 One company opening move is used by opening fields

Odoo company has:

- `account_opening_move_id`
- `account_opening_date`

Source:
- `addons/account/models/company.py` (`account_opening_move_id`, `account_opening_date`)

When opening balances are set through account fields (`opening_debit` / `opening_credit`), Odoo creates/updates **one move** linked to `account_opening_move_id`.

### 3.2 Opening move date is opening date minus 1 day

Source:
- `res.company._get_default_opening_move_values()` in `addons/account/models/company.py`

If `account_opening_date = 2025-01-01`, opening move date becomes `2024-12-31`.

### 3.3 Opening field imports are batched, then one update is done

Source:
- `account.account._set_opening_debit_credit()`
- `account.account._load_precommit_update_opening_move()`
- `addons/account/models/account_account.py`

Odoo stores import values in precommit memory and updates the opening move once per transaction. This is why opening balance CSV import performs reasonably even on larger COA.

### 3.4 If opening move is unbalanced, Odoo inserts balancing line

Source:
- `res.company._update_opening_move()`
- `res.company.get_unaffected_earnings_account()`
- `addons/account/models/company.py`

Difference is posted to `equity_unaffected` ("Undistributed Profits/Losses" / current year earnings bucket).

Practical meaning:
- Odoo will not crash if source TB is unbalanced.
- But this is a red flag: your source migration data is wrong.

### 3.5 Once opening move is posted, opening field import is blocked

Source:
- `res.company._update_opening_move()` in `addons/account/models/company.py`

You must reset opening move to draft before changing `opening_debit/opening_credit`.

### 3.6 Receivable/payable accounts are always reconcilable

Source:
- `account.account._check_reconcile()` in `addons/account/models/account_account.py`

For `asset_receivable` and `liability_payable`, `reconcile` must be true.

### 3.7 Import-time reconciliation tagging (`matching_number` with `I*` prefix)

When you import journal lines and want Odoo to reconcile them automatically after posting, set a `matching_number` value on the import lines. Odoo enforces a naming pattern:

- `P<number>` — partial reconciliation
- `I<anything>` — import/temporary marker, pending real reconciliation

Any `matching_number` set during import that does not start with `I` is automatically prefixed with `I` by Odoo's `_sanitize_vals()`.

Source: [`_sanitize_vals() — account_move_line.py:1568`](../addons/account/models/account_move_line.py#L1568)

```python
vals['matching_number'] = f"I{vals['matching_number']}"
```

After all move lines with the same `matching_number` are posted, `_reconcile_marked()` processes them and performs real reconciliation:

Source: [`addons/account/models/account_move_line.py:3012`](../addons/account/models/account_move_line.py#L3012)

```python
def _reconcile_marked(self):
    """Process the pending reconciliation of entries marked (i.e. during imports).
    The entries can be marked using the string `I*` as matching number where `*` can be anything.
    Once all the entries using identical numbers are posted, this function proceeds to do the real matching.
    """
```

**Critical constraint:** `_reconcile_marked()` groups by **both** `matching_number` and `account_id`:

```python
for _matching_number, account, lines in self._read_group(
    domain=[('matching_number', 'in', temp_numbers)],
    groupby=['matching_number', 'account_id'],
    ...
```

Source: [`_reconcile_marked() — account_move_line.py:3024`](../addons/account/models/account_move_line.py#L3024)

This means: the same `matching_number` value on lines using **different** accounts will NOT reconcile together. All lines sharing a marker must be on the same AR or AP account.

**Practical use in migration:** If you import AR open items as journal lines and want to pre-mark which invoice lines offset which payment lines (from partial payments in the old system), assign matching `matching_number` values in your CSV. Odoo will reconcile them after posting. Ensure all lines with the same number use the same receivable/payable account.

### 3.8 COA onboarding editor hides `equity_unaffected` accounts

When you open the Chart of Accounts via the onboarding dashboard button (before the opening move is posted), Odoo uses a custom list view with a domain filter that hides all accounts with `account_type = 'equity_unaffected'`.

Source: [`addons/account/models/onboarding_onboarding_step.py:92`](../addons/account/models/onboarding_onboarding_step.py#L92)

```python
# Hide the current year earnings account as it is automatically computed
domain = [
    ...
    ('account_type', '!=', 'equity_unaffected'),
]
```

This is intentional — the `equity_unaffected` balance is automatically computed by the balancing line logic in `_update_opening_move()`. You cannot (and should not) manually set its opening balance through the UI. If you set opening balances correctly, this account stays at zero in the opening move.

After the opening move is posted, the COA button shows the normal list view with all accounts visible.

---

## 4) Important Correction Before You Start

Do not mix these two concepts:

- **Opening move engine**: Odoo-managed move linked to `company.account_opening_move_id`, maintained through `opening_debit/opening_credit` fields.
- **Manual journal entries**: Standard entries you create yourself in Misc journal.

They are not the same thing.

If you create a manual JE, it does **not** automatically become `account_opening_move_id`.

Use one strategy consistently:

- Strategy 1 (recommended): use opening fields for GL opening balances.
- Strategy 2: use manual opening JEs only, and ignore opening fields entirely.

This tutorial uses Strategy 1.

---

## 5) Pre-Migration Checklist (Do This First)

### 5.1 Governance

- Freeze date agreed (last date in old system).
- Cut-over date agreed (first date in Odoo).
- Data owner assigned (who signs trial balance and open item extracts).
- Test environment prepared (clone or separate DB).

### 5.2 Odoo configuration baseline

- Fiscal country and localization installed.
- Chart of accounts finalized.
- Company currency set.
- Fiscal year settings checked.
- Multi-currency enabled if needed.
- Required modules installed:
  - `account`
  - `stock` (+ `stock_account` if inventory valuation entries needed)
  - `account_asset` (Enterprise) if fixed assets are managed in Odoo

### 5.3 Data extraction baseline from legacy system

Export as of cut-off date:

- Trial balance (all GL accounts, debits/credits).
- Open AR items (per customer document, outstanding amount, due date, currency).
- Open AP items (per vendor document, outstanding amount, due date, currency).
- Bank balances by account.
- Inventory by product/location/lot + valuation basis.
- Fixed asset register (cost, method, life, accumulated depreciation).

### 5.4 Mapping files you must maintain

- Account mapping: legacy account -> Odoo account code/type.
- Partner mapping: legacy customer/vendor id -> Odoo partner.
- Tax mapping (if importing transactional history).
- Product mapping (inventory and valuation).

---

## 6) Recommended Migration Architecture

Use dedicated migration clearing accounts, not one generic account.

Create these temporary accounts (example naming):

- `MIG_AR_CLEAR`
- `MIG_AP_CLEAR`
- `MIG_BANK_CLEAR`
- `MIG_STOCK_CLEAR`
- `MIG_ASSET_CLEAR` (optional)

Recommended properties:

- Type: usually `asset_current` for technical clearing.
- Reconcilable: true for AR/AP clearing if you will reconcile lines.
- **`tax_ids` must be empty.** If an account has default taxes configured, Odoo's `_compute_tax_ids()` will auto-apply those taxes to any invoice line using that account. Migration clearing accounts with taxes create unintended tax lines and distort your tax report.

Source: [`_compute_tax_ids() — account_move_line.py:912`](../addons/account/models/account_move_line.py#L912), [`_get_computed_taxes() — account_move_line.py:921`](../addons/account/models/account_move_line.py#L921)

Why separate accounts:

- Faster troubleshooting.
- You always know which stream is not cleared.
- Cleaner sign control and audit trail.

Hard rule at go-live:

- Every migration clearing account must end at zero (or explicit approved exception).

---

## 7) End-to-End Sequence (Do Not Reorder)

1. Configure COA, partners, products, currencies.
2. Import opening GL balances through `opening_debit/opening_credit`.
3. Import AR open items.
4. Import AP open items.
5. Import inventory quantities and valuation.
6. Import fixed assets (if applicable).
7. Set bank opening balances and start reconciliation baseline.
8. Validate all reports and clearing accounts.
9. Post opening move.
10. Lock dates.

Reordering usually causes double counting or missing balances.

---

## 8) Step-by-Step Tutorial

### Step 1 - Prepare Odoo master data

### 1.1 Chart of accounts quality gate

Before import, verify account types because reports depend on them.

Common required mapping:

- AR -> `asset_receivable`
- AP -> `liability_payable`
- Bank/Cash -> `asset_cash`
- Inventory -> `asset_current` or localization-specific stock valuation account setup
- Fixed assets cost -> `asset_fixed`
- Accumulated depreciation -> usually fixed/non-current asset class (by localization)
- Equity and retained earnings -> `equity` / `equity_unaffected` as applicable

If account type is wrong, financial statements and close behavior are wrong.

### 1.2 Partners

Import all customers/vendors before open items.

Minimum fields:

- Name
- Customer/Vendor relevance
- Receivable/payable properties if customized
- VAT/tax id if needed

### 1.3 Currencies

If legacy data has foreign currency open items:

- Enable multi-currency first.
- Load rates for cut-off and go-live period.

---

### Step 2 - Import opening trial balance (GL totals)

Use the Chart of Accounts import with opening fields.

Source behavior:
- `account.account.opening_debit/opening_credit`
- `account.account._load_precommit_update_opening_move()`

### 2.1 Build opening TB file

Required columns (typical):

- `code`
- `opening_debit`
- `opening_credit`

### 2.2 Replace detail streams with migration clearing totals

**First, decide whether you will import individual invoices/bills:**

| Plan | Opening TB approach |
|---|---|
| Will import open invoices + bills (full sub-ledger) | Use clearing accounts — do NOT put real AR/AP in TB |
| Will NOT import invoices/bills (balance-only migration) | Put real AR/AP accounts directly in TB — no clearing needed |
| Will import bank statements | Use `MIG_BANK_CLEAR` — do NOT put real bank balance in TB |
| Will NOT import bank statements | Put real bank accounts directly in TB |

**If you are importing detail streams**, replace those accounts in the opening TB:

- Replace AR total account with `MIG_AR_CLEAR` total.
- Replace AP total account with `MIG_AP_CLEAR` total.
- Replace inventory total with `MIG_STOCK_CLEAR` total (if inventory will be loaded later).
- Replace bank totals with `MIG_BANK_CLEAR` (if bank opening imported later).

Reason:

You will rebuild these balances from detailed sub-ledger data in later steps.
If you put the real AR/AP account in the opening TB AND later import individual invoices/bills, those accounts will be double-counted.

**If you are NOT importing invoices/bills (balance-only):**

Put the real account directly in the opening TB file. No clearing account needed.
The trade-off: AR/AP balance is correct on the Trial Balance, but Aged Receivable/Payable reports will show nothing — there are no open lines to reconcile. You lose the ability to track which customer owes what, or reconcile individual payments against invoices.

#### Worked example (full import — invoices and bills will be imported)

**Your legacy trial balance on cut-off date (Dec 31, 2024):**

| Account | Debit | Credit |
|---|---|---|
| Cash 1010 | 15,000 | |
| Accounts Receivable 1100 | 84,500 | |
| Inventory 1400 | 42,000 | |
| Equipment 1500 | 120,000 | |
| Accumulated Depreciation 1510 | | 38,000 |
| Accounts Payable 2000 | | 31,200 |
| Bank Loan 2500 | | 95,000 |
| Share Capital 3000 | | 60,000 |
| Retained Earnings 3100 | | 37,300 |
| **Total** | **261,500** | **261,500** |

**What goes into the Odoo COA import file (columns: `code`, `opening_debit`, `opening_credit`):**

| code | opening_debit | opening_credit | Note |
|---|---|---|---|
| 1010 | 15,000 | | Cash — import as-is, no detail stream |
| 9901 | 84,500 | | MIG_AR_CLEAR replaces account 1100 |
| 9903 | 42,000 | | MIG_STOCK_CLEAR replaces account 1400 |
| 1500 | 120,000 | | Equipment — import as-is |
| 1510 | | 38,000 | Accumulated depreciation — import as-is |
| 9902 | | 31,200 | MIG_AP_CLEAR replaces account 2000 |
| 2500 | | 95,000 | Bank loan — import as-is |
| 3000 | | 60,000 | Share capital — import as-is |
| 3100 | | 37,300 | Retained earnings — import as-is |

Accounts 1100, 1400, and 2000 are **not in this file at all**. Their balances will be built up from the detail imports in Steps 3, 4, and 5.

**After Step 3 (import open AR invoices), each invoice Odoo creates:**

```
Debit:  1100 Accounts Receivable   (per invoice amount)
Credit: 9901 MIG_AR_CLEAR          (same amount)
```

After all invoices are imported: `9901 MIG_AR_CLEAR = 84,500 (debit from TB) − 84,500 (credit from invoices) = 0`

**After Step 4 (import open AP bills), each bill Odoo creates:**

```
Credit: 2000 Accounts Payable      (per bill amount)
Debit:  9902 MIG_AP_CLEAR          (same amount)
```

After all bills are imported: `9902 MIG_AP_CLEAR = 31,200 (credit from TB) − 31,200 (debit from bills) = 0`

**At Step 9 (validation), all clearing accounts must be zero:**

| Account | Expected | If not zero |
|---|---|---|
| 9901 MIG_AR_CLEAR | 0 | Invoice amounts don't match TB total — find the gap |
| 9902 MIG_AP_CLEAR | 0 | Bill amounts don't match TB total — find the gap |
| 9903 MIG_STOCK_CLEAR | 0 | Inventory valuation doesn't match TB total — find the gap |

#### Worked example (balance-only — no invoices or bills imported)

Same legacy trial balance. No invoices or bills will be imported.

**What goes into the Odoo COA import file:**

| code | opening_debit | opening_credit | Note |
|---|---|---|---|
| 1010 | 15,000 | | Cash |
| 1100 | 84,500 | | AR — real account, balance only |
| 1400 | 42,000 | | Inventory — real account, balance only |
| 1500 | 120,000 | | Equipment |
| 1510 | | 38,000 | Accumulated depreciation |
| 2000 | | 31,200 | AP — real account, balance only |
| 2500 | | 95,000 | Bank loan |
| 3000 | | 60,000 | Share capital |
| 3100 | | 37,300 | Retained earnings |

No clearing accounts. No detail import steps needed.
Trial Balance will show correct totals from day one.
Aged Receivable and Aged Payable reports will be empty — no open lines exist to show.

### 2.3 Import and verify opening move generated

After import:

- Verify company has `account_opening_move_id`.
- Open that move and check date = opening date minus one day.
- Keep it draft until full validation.

---

### Lock date warning — must configure before any imports

When Odoo posts a move, it checks whether the move date violates any lock date. If it does, **it silently shifts the move date forward** to the day after the lock date:

```python
lock_dates = move._get_violated_lock_dates(move.date, affects_tax_report)
if lock_dates:
    move.date = move._get_accounting_date(..., lock_dates=lock_dates)
# _get_accounting_date: invoice_date = lock_dates[-1][0] + timedelta(days=1)
```

Source: [`account_move.py:5580`](../addons/account/models/account_move.py#L5580), [`account_move.py:6473`](../addons/account/models/account_move.py#L6473)

**Consequence:** If you import AR invoices dated Dec 31, 2024 but a `fiscalyear_lock_date` of Dec 31, 2024 is already set, every invoice will post on Jan 1, 2025 — the wrong period.

**Required: before any import step**, verify that no lock date covers your migration cut-off dates. Lock dates must be either unset or set to a date before your oldest migration entry.

---

### Step 3 - Import open customer receivables (AR)

You have two supported patterns.

### Pattern AR-1 (recommended): open invoices in Odoo

Use when you need invoice-level follow-up, dispute handling, reminders, and user-friendly operations.

Import each open invoice with:

- Customer
- Invoice number/reference
- Invoice date
- Due date
- Outstanding amount
- Currency
- One migration line account = `MIG_AR_CLEAR`
- No taxes unless legally required for this method

Resulting accounting logic per invoice:

- Debit receivable (customer account)
- Credit `MIG_AR_CLEAR`

This automatically clears the AR clearing amount loaded in Step 2.

### Pattern AR-2 (faster): journal item open entries (no invoice documents)

Use when you only need aging/reconciliation, not invoice documents in Odoo.

Import journal entry lines with:

- Receivable account
- Partner
- Maturity date
- Amount (and currency fields if needed)
- Counterpart on `MIG_AR_CLEAR`

Important:

Aged report in Odoo is based on receivable/payable move lines, dates, partner, and residuals (not strictly invoice objects).

Source:
- `enterprise/account_reports/models/account_aged_partner_balance.py`

If you skip partner/maturity data, aging output becomes poor or grouped as unknown.

### AR control checks

- Sum of imported open AR detail must equal legacy AR outstanding total.
- `MIG_AR_CLEAR` should be zero (or very close with approved FX rounding).

---

### Step 4 - Import open vendor payables (AP)

Same principle as AR.

### Pattern AP-1 (recommended): open vendor bills

Per bill:

- Vendor
- Bill reference/number
- Bill date
- Due date
- Outstanding amount
- Currency
- Migration line account = `MIG_AP_CLEAR`
- Taxes usually blank for migration opening bills unless legal requirement says otherwise

Accounting per bill:

- Credit payable
- Debit `MIG_AP_CLEAR`

### Pattern AP-2 (faster): journal item open entries

Import payable line details with partner and due date, counterpart to `MIG_AP_CLEAR`.

### AP control checks

- AP detail total equals legacy AP outstanding total.
- `MIG_AP_CLEAR` returns to zero.

---

### Step 5 - Import inventory opening quantities and valuation

### 5.1 Understand when accounting entries are created

Inventory journal entries are only created when **all four** conditions are met simultaneously:

```python
def _should_create_account_move(self):
    return (
        self.product_id.is_storable
        and self.is_valued
        and (self.location_dest_id.valuation_account_id or self.location_id.valuation_account_id)
        and self.product_id.valuation == 'real_time'
    )
```

Source: [`_should_create_account_move() — stock_account/models/stock_move.py:616`](../addons/stock_account/models/stock_move.py#L616)

| Condition | What it means |
|---|---|
| `product_id.is_storable` | Product type must be "Storable Product" (not consumable or service) |
| `is_valued` | The move must be a valued move (receipt/delivery, not internal unless configured) |
| `location.valuation_account_id` | Source or destination location must have a valuation account set |
| `product_id.valuation == 'real_time'` | Product costing method must be Automated (not Manual/Periodic) |

If any condition is false, no accounting entry is created — the inventory count creates stock lines but has zero financial impact.

**Critical: value is resolved in this fallback order:**

1. Manual value override
2. Invoice/Bill amount (if a related purchase order or sale order exists)
3. Production cost
4. SO/PO quotation lines
5. Returns from related moves
6. `standard_price` at the time of the move

Source: [`_get_value_data() — stock_account/models/stock_move.py:313`](../addons/stock_account/models/stock_move.py#L313)

**Migration risk:** If products have `standard_price = 0` at the time the inventory adjustment is validated, all stock moves will be valued at 0. The `MIG_STOCK_CLEAR` account will not go to zero, and your inventory will appear on the balance sheet at zero value.

**Required precheck before Step 5:** Set all product `standard_price` values to the correct opening cost *before* importing inventory quantities. For FIFO/AVCO products, also verify the costing method is correct before the first move.

If valuation is periodic/manual, inventory counts do not create accounting entries — you manage the opening inventory value entirely through your opening TB entries.

### 5.2 Import physical stock

Use inventory adjustment import (`stock.quant`) with fields such as:

- Product
- Location
- Counted quantity
- Lot/serial where needed
- Optional accounting date

Sources:
- `addons/stock/models/stock_quant.py` (`action_apply_inventory`, `action_apply_all`)
- `addons/stock_account/models/stock_quant.py` (`accounting_date`)

### 5.3 Valuation alignment

For real-time valuation, stock moves generate account entries using stock valuation/interim/location valuation accounts depending on move path.

Do not assume one universal counterpart account.

Practical migration method:

- Configure stock valuation accounts correctly before import.
- If needed, map temporary counterpart to `MIG_STOCK_CLEAR` for migration period.
- After import, verify inventory valuation report and GL stock valuation account.

### 5.4 Inventory control checks

- Quantities match legacy physical count.
- Stock valuation total matches legacy inventory value at cut-off.
- `MIG_STOCK_CLEAR` is zero after final reclass/reconciliation.

---

### Step 6 - Import fixed assets (Enterprise `account_asset`)

Source model:
- `enterprise/account_asset/models/account_asset.py`

### 6.1 Key fields for migration

- `name`
- `original_value`
- `salvage_value`
- `acquisition_date`
- `method`
- `method_number`
- `method_period`
- `account_asset_id`
- `account_depreciation_id`
- `account_depreciation_expense_id`

### 6.2 Critical field for legacy imports

Use `already_depreciated_amount_import`.

Source: [`enterprise/account_asset/models/account_asset.py:158`](../enterprise/account_asset/models/account_asset.py#L158)

Field help text (from source): "In case of an import from another software, you might need to use this field to have the right depreciation table report. This is the value that was already depreciated with entries not computed from this model."

**How it affects computation:**

The `value_residual` field (depreciable remaining value) is calculated as:

```
value_residual = original_value
               - salvage_value
               - already_depreciated_amount_import
               - sum(posted_depreciation_moves.depreciation_value)
```

Source: [`_compute_value_residual()`](../enterprise/account_asset/models/account_asset.py#L320)

This means: you keep the full historical cost in `original_value`, put legacy accumulated depreciation in `already_depreciated_amount_import`, and Odoo calculates the remaining schedule from there. You do **not** need to post years of historical depreciation entries.

**Book value formula:**

`book_value = value_residual + salvage_value`

If your asset had cost $100,000, salvage $5,000, and $40,000 already depreciated:
- `original_value` = 100,000
- `salvage_value` = 5,000
- `already_depreciated_amount_import` = 40,000
- `value_residual` = 100,000 − 5,000 − 40,000 = 55,000
- `book_value` = 55,000 + 5,000 = 60,000

### 6.3 Asset migration patterns

- Pattern FA-1 (recommended): migrate remaining depreciation via `already_depreciated_amount_import`.
- Pattern FA-2: migrate only net book value as new asset (simpler, less historical fidelity).
- Pattern FA-3: recreate full historical depreciation moves (high effort, rarely needed).

### 6.4 Asset control checks

- Gross asset value matches legacy register.
- Accumulated depreciation matches legacy.
- Net book value matches legacy.
- Future depreciation schedule dates/amounts are acceptable.

---

### Step 7 - Set bank opening balances

### 7.1 One journal per bank account

Each physical bank account should have its own bank journal.

### 7.2 Methods

- Method BK-1: import first bank statement with opening baseline.
- Method BK-2: post opening GL line then reconcile bank feed starting next day.

Remember:

Bank statement lines initially post against journal suspense account until reconciliation.

Source:
- `account.journal.suspense_account_id`
- `addons/account/models/account_journal.py`
- `addons/account/models/account_bank_statement_line.py`

### 7.3 Bank control checks

- Bank GL balance equals legacy ending bank balance.
- Statement opening balance equals expected first import point.
- `MIG_BANK_CLEAR` is zero after final alignment.

---

### Step 8 - Multi-currency specifics

### 8.1 Opening TB import limitation

`opening_debit/opening_credit` works in company currency totals at account level.

If you need document-level foreign currency exposure, import detailed open items with:

- `currency_id`
- `amount_currency`
- proper company-currency balance

### 8.2 Exchange rates

Load authoritative rates before importing foreign currency open items.

### 8.3 Expected residual FX

Small FX differences may appear between cut-off and payment date. Define tolerance and write-off process.

---

### Step 9 - Validate before posting

Run all checks on cut-off date and compare to legacy signed reports.

### 9.1 Mandatory report checks

- Trial Balance: debit = credit and matches legacy by account.
- Balance Sheet: assets = liabilities + equity.
- P&L: expected opening logic for selected migration case.
- Aged Receivable: total and aging buckets match legacy open AR.
- Aged Payable: total and aging buckets match legacy open AP.
- Inventory valuation matches legacy stock value.
- Asset register totals match legacy.

### 9.2 Mandatory account checks

Every migration clearing account:

- `MIG_AR_CLEAR = 0`
- `MIG_AP_CLEAR = 0`
- `MIG_STOCK_CLEAR = 0`
- `MIG_BANK_CLEAR = 0`

If any is non-zero, stop and investigate.

### 9.3 Random sampling checks

- 10 random customers: legacy outstanding vs Odoo outstanding.
- 10 random vendors: same test.
- 10 random SKUs: quantity and valuation.
- 10 random assets: cost, accumulated depreciation, NBV.

### 9.4 SQL validation queries

Run directly against the Odoo database. Replace `YOUR_COMPANY_ID` with the `res.company.id` value.

```sql
-- Opening move is balanced (must return 0)
SELECT SUM(balance)
FROM account_move_line
WHERE move_id = (
    SELECT account_opening_move_id FROM res_company WHERE id = YOUR_COMPANY_ID
);

-- All clearing accounts must be zero (must return no rows)
SELECT aa.code, aa.name, SUM(aml.balance) AS balance
FROM account_move_line aml
JOIN account_account aa ON aml.account_id = aa.id
WHERE aa.code LIKE 'MIG_%'
  AND aml.company_id = YOUR_COMPANY_ID
GROUP BY aa.code, aa.name
HAVING ROUND(SUM(aml.balance), 2) != 0;

-- Total open AR residual (compare against legacy AR total)
SELECT ROUND(SUM(aml.amount_residual), 2) AS open_ar
FROM account_move_line aml
JOIN account_account aa ON aml.account_id = aa.id
WHERE aa.account_type = 'asset_receivable'
  AND aml.company_id = YOUR_COMPANY_ID
  AND aml.parent_state = 'posted'
  AND NOT aml.reconciled;

-- Total open AP residual (compare against legacy AP total, expect negative)
SELECT ROUND(SUM(aml.amount_residual), 2) AS open_ap
FROM account_move_line aml
JOIN account_account aa ON aml.account_id = aa.id
WHERE aa.account_type = 'liability_payable'
  AND aml.company_id = YOUR_COMPANY_ID
  AND aml.parent_state = 'posted'
  AND NOT aml.reconciled;

-- Trial balance: all posted moves sum to zero
SELECT ROUND(SUM(balance), 2)
FROM account_move_line
WHERE company_id = YOUR_COMPANY_ID
  AND parent_state = 'posted';
```

`amount_residual` is a stored computed field on `account.move.line` ([account_move_line.py:241](../addons/account/models/account_move_line.py#L241)). It reflects the unreconciled balance after partial reconciliations.

---

### Step 10 - Post opening move and lock periods

### 10.1 Post opening move

Post only after all controls pass.

### 10.2 Lock dates in Odoo 19

Odoo lock fields are:

- `fiscalyear_lock_date`
- `tax_lock_date`
- `sale_lock_date`
- `purchase_lock_date`
- `hard_lock_date`

Source:
- `LOCK_DATE_FIELDS` in `addons/account/models/company.py`

### 10.3 Hard lock warning

`hard_lock_date` cannot be removed or moved backwards.

Source:
- `res.company._validate_locks()` in `addons/account/models/company.py`

When setting lock dates, Odoo can block you if there are draft entries or unreconciled bank statement lines up to that date. Clean those first.

Use hard lock only after final sign-off.

---

## 9) Case-Specific Guidance

### Case A - Opening balances only

Use only when operational teams do not need invoice/bill-level legacy data in Odoo.

Risks:

- Limited partner aging detail.
- Harder cash application and collection workflows for legacy items.

### Case C - Mid-year cut-over

Main challenge: P&L continuity.

Rules:

- Decide whether YTD income/expense is imported into Odoo GL.
- Keep consistent reporting story for statutory and management reporting.
- Align date filters and opening entry dates carefully.

### Case D - Full history

Usually requires migration scripts and rehearsal cycles.

Add controls for:

- sequence integrity
- tax report parity
- reconciliation parity
- document attachments and references

---

## 10) Common Migration Failures and How to Fix

| Symptom | Typical root cause | Fix |
|---|---|---|
| Trial balance mismatch | Source export not final, mapping errors, sign inversion | Re-extract TB, freeze source, rerun mapping checks |
| AR/AP totals correct but aging wrong | Missing partner or due dates on open items | Reimport open items with partner and maturity data |
| Clearing account not zero | Stream partially imported (AR/AP/stock/bank) | Reconcile stream totals and rerun missing imports |
| Inventory value mismatch | Costing/valuation setup wrong before inventory import | Correct product/category valuation setup, then reapply opening stock in clean DB |
| Asset NBV mismatch | Wrong method/lifetime or missing `already_depreciated_amount_import` | Correct asset fields and recompute board |
| Cannot adjust opening balances | Opening move already posted | Reset opening move to draft (authorized user), reimport opening fields |
| Unexpected equity delta | Odoo auto balancing line used | Fix source TB and reimport opening balances |
| Lock date cannot be changed | Hard lock restrictions | Move forward only; avoid hard lock before final approval |

---

## 11) Official Odoo Import Templates

Odoo provides built-in Excel import templates. Download them via the **Import** button on any list view — each list view's import dialog offers "Download Template."

### Template paths in source

| Template | UI path | File path | Use for |
|---|---|---|---|
| Chart of Accounts | Accounting → Configuration → Chart of Accounts → Import | `/account/static/xls/coa_import_template.xlsx` | `opening_debit/opening_credit` import |
| Journal Items (AML) | Accounting → Accounting → Journal Items → Import | `/account/static/xls/aml_import_template.xlsx` | Misc journal entry lines |
| Misc Operations (Journal Entries) | Accounting → Accounting → Journal Entries → Import | `/account/static/xls/misc_operations_import_template.xlsx` | Full journal entry import |
| Customer Invoices / Credit Notes | Accounting → Customers → Invoices → Import | `/account/static/xls/customer_invoices_credit_notes_import_template.xlsx` | AR open items (invoice pattern) |
| Vendor Bills / Refunds | Accounting → Vendors → Bills → Import | `/account/static/xls/vendor_bills_refunds_import_template.xlsx` | AP open items (bill pattern) |

Source: [`account_account.get_import_templates()`](../addons/account/models/account_account.py#L1152), [`account_move.get_import_templates()`](../addons/account/models/account_move.py#L7186), [`account_move_line.get_import_templates()`](../addons/account/models/account_move_line.py#L3353)

**How the importer matches column headers** (in priority order):
1. Exact match on technical field name (case-insensitive) — e.g. `partner_id`
2. Match on user-translated field label — e.g. `Customer`
3. Match on English field label — e.g. `Partner`

Source: [`base_import.py:833–841`](../addons/base_import/models/base_import.py#L833)

**Practical guidance:** Use the official Odoo template headers as-is. Do not rename columns. If you must use custom headers, match the English field label exactly. Technical names (`field_name`) and English UI labels both work — translated labels depend on the importer's language context.

---

## 12) Error Messages You Will Encounter

These are exact error messages from Odoo 19 source. Knowing them saves diagnosis time.

| Message | Source location | When you see it | How to fix |
|---|---|---|---|
| "Please install a chart of accounts or create a miscellaneous journal before proceeding." | `company.py:809` | Trying to set opening balances before a general journal exists | Install COA first or create a Miscellaneous journal manually |
| "You cannot import the 'openning_balance' if the opening move (%s) is already posted. If you are absolutely sure you want to modify the opening balance of your accounts, reset the move to draft." | `company.py:866` | Trying to write `opening_debit/opening_credit` after the opening entry is posted | Reset the opening entry to draft (Accounting Manager access required) |
| "Incorrect fiscal year date: day is out of range for month." | `setup_wizards.py:41` | Setting fiscal year end to an invalid date (e.g., Feb 30) | Use a valid calendar date |
| "You cannot have a receivable/payable account that is not reconcilable. (account code: %s)" | `account_account.py:23` | Trying to set `reconcile = False` on an AR/AP account | Do not change `reconcile` on these accounts — it is enforced |
| "An Off-Balance account can not be reconcilable" | `account_account.py:174` | Setting `reconcile = True` on an `off_balance` account | Off-balance accounts cannot be reconciled |
| "You cannot switch an account to prevent the reconciliation if some partial reconciliations are still pending." | `account_account.py:1034` | Trying to disable reconcile on an account that has unfinished reconciliations | Clear all partial reconciliations first |
| "A temporary number can not be used in a real matching" | `account_move_line.py:1463` | Setting an `I*` matching number on a line that already has real partial reconciles | Do not mix import markers with real reconciled lines |
| "There are still draft entries in the period you want to hard lock." | `company.py:573` | Setting hard lock date when draft entries exist up to that date | Post or delete all draft entries up to the lock date |

---

## 13) File Templates You Should Maintain

Keep versioned migration files in Git or controlled storage:

- `01_coa_opening_balances.csv`
- `02_partners.csv`
- `03_ar_open_items.csv`
- `04_ap_open_items.csv`
- `05_inventory_opening.csv`
- `06_assets_opening.csv`
- `07_bank_opening.csv`
- `08_validation_matrix.xlsx`

Recommended columns by file (minimum):

### 13.1 Opening COA file

- `code`
- `opening_debit` and `opening_credit` — two separate columns, one per side
- **or** `opening_balance` — single signed column: positive = debit, negative = credit

`opening_balance` is a first-class field on `account.account` ([account_account.py:118](../addons/account/models/account_account.py#L118)). Using it reduces sign mistakes when your source data is already a signed net balance rather than split debit/credit columns.

### 13.2 AR open items (invoice pattern)

- `partner_id`
- `invoice_date`
- `invoice_date_due`
- `ref`
- `invoice_line_ids/name`
- `invoice_line_ids/price_unit`
- `invoice_line_ids/account_id` (migration clearing account)
- `currency_id` (if needed)

### 13.3 AP open items (bill pattern)

- Same idea as AR, vendor side.

### 13.4 Inventory opening

- `product_id`
- `location_id`
- `inventory_quantity`
- `lot_id` (if tracked)
- `accounting_date` (optional, with stock_account)

### 13.5 Asset opening

- `name`
- `original_value`
- `already_depreciated_amount_import`
- `salvage_value`
- `acquisition_date`
- `method`
- `method_number`
- `method_period`
- `account_asset_id`
- `account_depreciation_id`
- `account_depreciation_expense_id`

---

## 14) Rehearsal Plan (Highly Recommended)

Run at least 2 full dry runs.

For each dry run:

1. Start from clean test DB snapshot.
2. Execute full sequence end-to-end.
3. Record runtime and issues.
4. Update mapping/templates.
5. Repeat until no unexplained deltas remain.

Target before production run:

- Zero unexplained differences.
- Documented signed validation matrix.
- Clear rollback plan.

---

## 15) Go-Live Cutover Runbook (Short Form)

1. Freeze legacy postings.
2. Take final extracts (TB/open items/inventory/assets/bank).
3. Run import sequence in production.
4. Run validation matrix and obtain sign-off.
5. Post opening move.
6. Set lock dates.
7. Start daily operations in Odoo from go-live date.

---

## 16) What Was Fixed/Improved Compared to the Previous Document

Main corrections:

- Clarified that manual JEs are not automatically the same as Odoo opening move engine.
- Corrected AR/AP clearing logic with explicit migration clearing account design.
- Added two valid AR/AP migration patterns (invoice documents vs open item journal lines).
- Added aged report reality from code (based on receivable/payable move lines, partner, due date).
- Added fixed asset migration best practice using `already_depreciated_amount_import`.
- Clarified inventory accounting behavior based on valuation mode and stock_account logic.
- Clarified opening move identification (company linked move), not by assuming a special journal name.
- Strengthened control framework with a mandatory zero-balance clearing matrix.

Usability improvements:

- Reorganized as a tutorial/runbook with strict execution order.
- Added decision matrix and case-specific guidance.
- Added practical templates and rehearsal plan.
- Added common failure table with direct fixes.

---

## 17) Source References (Odoo 19 Code)

- Opening move fields and update logic:
  - `addons/account/models/company.py`
  - Methods: `_get_default_opening_move_values`, `_update_opening_move`, `get_unaffected_earnings_account`
- Opening field import batching:
  - `addons/account/models/account_account.py`
  - Methods: `_set_opening_debit_credit`, `_load_precommit_update_opening_move`
- Lock date fields and hard lock constraints:
  - `addons/account/models/company.py`
  - `LOCK_DATE_FIELDS`, `_validate_locks`
- Receivable/payable reconcile constraint:
  - `addons/account/models/account_account.py` (`_check_reconcile`)
- Aged receivable/payable engine:
  - `enterprise/account_reports/models/account_aged_partner_balance.py`
- Inventory adjustment and valuation flow:
  - `addons/stock/models/stock_quant.py`
  - `addons/stock_account/models/stock_quant.py`
  - `addons/stock_account/models/stock_move.py`
- Asset migration fields and depreciation logic:
  - `enterprise/account_asset/models/account_asset.py`
  - Fields: `already_depreciated_amount_import` (line 158), `_compute_value_residual` (line 320)
- Import-time reconciliation tagging:
  - `addons/account/models/account_move_line.py`
  - Method: `_reconcile_marked` (line 3012), `_prepare_create_values` (line 1573 — auto I-prefix)
  - Field: `matching_number` (line 284)
- Official import templates:
  - `addons/account/models/account_account.py` (`get_import_templates`, line 1152)
  - `addons/account/models/account_move.py` (`get_import_templates`, line 7186)
- COA onboarding editor behavior:
  - `addons/account/models/onboarding_onboarding_step.py` (`action_open_step_chart_of_accounts`, line 80)

---

## 18) Final Practical Rules

- Never do first import on production.
- Never post opening move before full validation.
- Never leave migration clearing accounts unexplained.
- Never set hard lock date before final sign-off.
- Keep every migration file versioned and reproducible.

If you follow this runbook, your Odoo 19 accounting start will be controlled, auditable, and operationally usable from day one.

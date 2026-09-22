# Odoo 20 Accounting Migration Tutorial

> Audience: Accounting and implementation teams migrating from another accounting system (QuickBooks, Xero, Sage, SAP, 1C, custom ERP) to Odoo 20.
>
> Goal: Start Odoo with correct Balance Sheet, P&L, Aged Receivable/Payable, inventory valuation, and fixed assets on day one.
>
> Scope: How to import opening balances and open accounting data, what can go wrong, and how to prevent it.
>
> Odoo version: **20.0**. Sections 3.9, 3.10, Step 5 and Step 6 cover mechanics that changed between 19 and 20 — see [What Changed Between Odoo 19 and Odoo 20](#16-what-changed-between-odoo-19-and-odoo-20) for the full delta.

---

## 1) What This Tutorial Gives You

By the end of this tutorial you will know:

- Which migration approach to choose (opening only, opening + open items, mid-year, full history).
- How Odoo 20 opening balances actually work internally.
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

## 3) How Odoo 20 Opening Balances Really Work (Critical)

These mechanics come directly from Odoo 20 source.

### 3.1 One company opening move is used by opening fields

Odoo company has:

- `account_opening_move_id` — [company.py:175](../addons/account/models/company.py#L175)
- `account_opening_date` — [company.py:177](../addons/account/models/company.py#L177)

When opening balances are set through account fields (`opening_debit` / `opening_credit`), Odoo creates/updates **one move** linked to `account_opening_move_id`.

In Odoo 20 `account_opening_date` defaults to **today** (`default=lambda self: fields.Date.today()`). In 19 it had no default. Practical effect: a fresh database already has an opening date, so the opening move lands on *yesterday* unless you set the real cut-off date first. Set `account_opening_date` before the first `opening_debit`/`opening_credit` import.

### 3.2 Opening move date is opening date minus 1 day

Source: [`_get_default_opening_move_values() — company.py:949`](../addons/account/models/company.py#L949)

If `account_opening_date = 2025-01-01`, opening move date becomes `2024-12-31`.

### 3.3 Opening field imports are batched, then one update is done

Source: [`_set_opening_debit_credit() — account_account.py:736`](../addons/account/models/account_account.py#L736), [`_load_precommit_update_opening_move() — account_account.py:955`](../addons/account/models/account_account.py#L955)

Odoo stores import values in precommit memory and updates the opening move once per transaction. This is why opening balance CSV import performs reasonably even on larger COA.

### 3.4 If opening move is unbalanced, Odoo inserts balancing line

Source: [`_update_opening_move() — company.py:1009`](../addons/account/models/company.py#L1009), [`get_unaffected_earnings_account() — company.py:977`](../addons/account/models/company.py#L977)

Difference is posted to `equity_unaffected` ("Undistributed Profits/Losses" / current year earnings bucket).

Practical meaning:
- Odoo will not crash if source TB is unbalanced.
- But this is a red flag: your source migration data is wrong.

### 3.5 Once opening move is posted, opening field import is blocked

Source: [`_update_opening_move() — company.py:1009`](../addons/account/models/company.py#L1009), guard message at [company.py:1022](../addons/account/models/company.py#L1022)

You must reset opening move to draft before changing `opening_debit/opening_credit`.

Odoo 20 adds a **Validate and Post** button directly in the opening-balance list view (`account.init_accounts_tree`), calling `account.account.action_validate_opening_move()`. It is irreversible from that screen and affects the active company only.
Source: [`action_validate_opening_move() — account_account.py:1184`](../addons/account/models/account_account.py#L1184), [`init_accounts_tree — setup_wizards_view.xml:89`](../addons/account/wizard/setup_wizards_view.xml#L89)

### 3.6 Receivable/payable accounts are always reconcilable — but `reconcile` means something narrower in Odoo 20

The constraint is unchanged: for `asset_receivable` and `liability_payable`, `reconcile` must be true.
Source: [`_check_reconcile() — account_account.py:34`](../addons/account/models/account_account.py#L34)

What changed is the **meaning** of the flag:

| | Odoo 19 | Odoo 20 |
|---|---|---|
| Label | "Allow Reconciliation" | "Payment Reconciliation" |
| Help | "allows invoices & payments matching of journal items" | "used in bank reconciliation. Currency rate difference entries will be automatically created if needed" |
| Toggling it | rewrote `amount_residual` on every open line (`_toggle_reconcile_to_true/false`) | no side effect — both helpers were removed |
| Blocks manual matching? | effectively yes | **no** — `_check_amls_exigibility_for_reconciliation()` only checks same account + same company root |

Source: [`reconcile — account_account.py:112`](../addons/account/models/account_account.py#L112), [`_check_amls_exigibility_for_reconciliation() — account_move_line.py:2969`](../addons/account/models/account_move_line.py#L2969)

**Migration consequence:** you no longer have to pre-flip `reconcile` on clearing accounts before matching lines on them, and you no longer get the old "You cannot switch an account to prevent the reconciliation if some partial reconciliations are still pending" error (that message no longer exists in Odoo 20). Still set `reconcile = True` on AR/AP clearing accounts — the flag drives bank reconciliation and automatic FX-difference entries.

### 3.7 Import-time reconciliation tagging (`matching_number` with `I*` prefix)

When you import journal lines and want Odoo to reconcile them automatically after posting, set a `matching_number` value on the import lines. Odoo enforces a naming pattern:

- `P<number>` — partial reconciliation
- `I<anything>` — import/temporary marker, pending real reconciliation

Any `matching_number` set during import that does not start with `I` is automatically prefixed with `I` by Odoo's `_sanitize_vals()`.

Source: [`_sanitize_vals() — account_move_line.py:2063`](../addons/account/models/account_move_line.py#L2063)

```python
vals['matching_number'] = f"I{vals['matching_number']}"
```

After all move lines with the same `matching_number` are posted, `_reconcile_marked()` processes them and performs real reconciliation:

Source: [`_reconcile_marked() — account_move_line.py:3485`](../addons/account/models/account_move_line.py#L3485)

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

Source: [`_reconcile_marked() — account_move_line.py:3499`](../addons/account/models/account_move_line.py#L3499)

This means: the same `matching_number` value on lines using **different** accounts will NOT reconcile together. All lines sharing a marker must be on the same AR or AP account.

Two Odoo 20 changes here:

- `_sanitize_vals()` accepts a `skip_matching_number_check` context key that suppresses the automatic `I` prefix. Use it only if you are writing a *real* matching number yourself; for imports, leave it off and let Odoo add the prefix.
- `_reconcile_marked()` no longer flips `account.reconcile` to `True` behind your back. In Odoo 19 it logged "has reconciled lines, changing the config" and silently enabled the flag. Now the account config is left exactly as you imported it.

**Practical use in migration:** If you import AR open items as journal lines and want to pre-mark which invoice lines offset which payment lines (from partial payments in the old system), assign matching `matching_number` values in your CSV. Odoo will reconcile them after posting. Ensure all lines with the same number use the same receivable/payable account.

### 3.8 COA onboarding editor hides `equity_unaffected` accounts

When you open the Chart of Accounts via the onboarding dashboard button (before the opening move is posted), Odoo uses a custom list view with a domain filter that hides all accounts with `account_type = 'equity_unaffected'`.

Source: [`action_open_step_chart_of_accounts() — onboarding_onboarding_step.py:79`](../addons/account/models/onboarding_onboarding_step.py#L79), domain at [line 93](../addons/account/models/onboarding_onboarding_step.py#L93)

```python
# Hide the current year earnings account as it is automatically computed
domain = [
    ...
    ('account_type', '!=', 'equity_unaffected'),
]
```

This is intentional — the `equity_unaffected` balance is automatically computed by the balancing line logic in `_update_opening_move()`. You cannot (and should not) manually set its opening balance through the UI. If you set opening balances correctly, this account stays at zero in the opening move.

After the opening move is posted, the COA button shows the normal list view with all accounts visible.

### 3.9 The chart of accounts is now a tree — `account.group` is gone (Odoo 20)

This is the single biggest COA change between 19 and 20, and it affects both your import file and your reports.

| | Odoo 19 | Odoo 20 |
|---|---|---|
| Grouping mechanism | separate `account.group` model, matched by `code_prefix_start` / `code_prefix_end` ranges | `account.account.parent_id` — accounts are their own parents |
| Model on account | `group_id` (computed from code prefixes) | `parent_id`, `parent_path`, `parent_ids` |
| Storage | `_parent_store` on `account.group` | `_parent_store` on `account.account` |
| Default `_order` | `code, placeholder_code` | `code_path, account_type, name_path` |
| Report hierarchy filter | rebuilt lines from `account.group` prefix ranges | walks `account.account.parent_id` |

Source: [`parent_id — account_account.py:133`](../addons/account/models/account_account.py#L133), [`_order / _parent_store — account_account.py:29`](../addons/account/models/account_account.py#L29), report side at [`_create_hierarchy() — account_report.py:1434`](../enterprise/account_reports/models/account_report.py#L1434)

Consequences for migration:

- **`account.group` records no longer exist.** Any legacy import file or script that created `account.group` rows will fail. Convert those groups into parent accounts.
- **Parent accounts may have no code.** Odoo 20 dropped the "The code must be set for every company to which this account belongs" check from `_ensure_code_is_unique()`. A pure grouping account can carry a name and no code.
  Source: [`_ensure_code_is_unique() — account_account.py:1089`](../addons/account/models/account_account.py#L1089)
- **Import `parent_id` explicitly** if you want a hierarchy — it is not derived from the code. In a CSV, use `parent_id/id` (external ID) or `parent_id` (name match), and import parents before children.
- `code_path` and `name_path` are computed ` / `-joined paths used for ordering and searching. You do not import them.
- Account codes may now contain **dashes**: `ACCOUNT_CODE_REGEX` went from `^[A-Za-z0-9.]+$` to `^[A-Za-z0-9.-]+$`. A legacy chart using codes like `1100-01` imports as-is in Odoo 20 and would have been rejected in 19.
  Source: [`ACCOUNT_CODE_REGEX — account_account.py:17`](../addons/account/models/account_account.py#L17)

### 3.10 Creating a bank/cash account auto-creates a journal (Odoo 20)

`account.account.create()` now calls `_create_default_journals()`. Every created account with `account_type` in `asset_cash` or `liability_credit_card` that is not already some journal's `default_account_id` gets a new `account.journal` (`bank` or `credit` type) named after the account.

Source: [`_create_default_journals() — account_account.py:1129`](../addons/account/models/account_account.py#L1129)

**Migration consequence:** importing a legacy chart with 12 bank/cash accounts silently creates 12 bank journals. Two ways to control this:

- Pass `skip_auto_account_journal_creation` in the import context to skip the call entirely ([account_account.py:1052](../addons/account/models/account_account.py#L1052)), or `chart_template_load` to make `_create_default_journals()` return immediately ([account_account.py:1131](../addons/account/models/account_account.py#L1131)). Chart-template loading uses the latter, which is why installing a localization does not produce duplicate bank journals.
- Or let it happen and clean up afterwards — but check journal codes and sequences before you post anything, because each new journal starts its own numbering.

This also means the old advice "create the bank journal first, then point it at the account" is reversed in Odoo 20 for imports: create the account and let Odoo build the journal, then rename/recode it.

### 3.11 Account-level stock accounts (Odoo 20)

`account.account` gained two fields used by the new periodic inventory closing:

- `account_stock_variation_id` — "At closing, register the inventory variation of the period into a specific account"
- `account_stock_expense_id` — "Counterpart used at closing for accounting adjustments to inventory valuation"

Source: [`account_account.py:156`](../addons/account/models/account_account.py#L156)

Set these on your stock valuation account before Step 5 if the company runs periodic valuation (the Odoo 20 default). See Step 5.

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

Source: [`_compute_tax_ids() — account_move_line.py:1293`](../addons/account/models/account_move_line.py#L1293), [`_get_computed_taxes() — account_move_line.py:1302`](../addons/account/models/account_move_line.py#L1302)

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
# _post()
lock_dates = move._get_violated_lock_dates(move.date, affects_tax_report)
if lock_dates:
    move.date = move._get_accounting_date(move._get_accounting_date_source(), affects_tax_report, lock_dates=lock_dates)

# _get_accounting_date()
if lock_dates:
    invoice_date = lock_dates[-1][0] + timedelta(days=1)
```

Source: [`_post() — account_move.py:6252`](../addons/account/models/account_move.py#L6252), [`_get_accounting_date() — account_move.py:7427`](../addons/account/models/account_move.py#L7427)

The shifted date is **not** simply "lock date + 1 day". Odoo moves the date into the first open period, then adjusts it so sequence numbering stays increasing:

| Document | Sequence resets | Resulting date |
|---|---|---|
| Sale document | monthly (or no sequence yet) | `min(today, end of month of lock_date + 1)` |
| Sale document | yearly | `min(today, end of year of lock_date + 1)` |
| Other (bills, misc) | monthly | end of month if that month is already past, else `max(date, today)` |
| Other | yearly | Dec 31 if that year is already past, else `max(date, today)` |

**Consequence:** If you import AR invoices dated Dec 31, 2024 but a `fiscalyear_lock_date` of Dec 31, 2024 is already set, every invoice posts in January 2025 (or later) — the wrong period, and silently.

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

### 5.0 Odoo 20 default is PERIODIC valuation — read this first

In Odoo 20 the valuation configuration moved up to the company and **defaults to periodic**:

| Field on `res.company` | Default | Meaning |
|---|---|---|
| `inventory_valuation` | `periodic` | `periodic` = "Periodic (at closing)", `real_time` = "Perpetual (at invoicing)" |
| `cost_method` | `standard` | `standard` / `average`; `stock_account` adds `fifo` |
| `account_stock_valuation_id` | — | default stock valuation account |
| `account_stock_journal_id` | — | default journal for stock entries |
| `inventory_period` | `manual` | `manual` / `daily` / `monthly` — how often the closing entry is generated |

Source: [`company.py:343-365`](../addons/account/models/company.py#L343)

`product.template.valuation` and `cost_method` are now **computed**, resolving in this order: product category property → company default.
Source: [`valuation` / `cost_method` — account/models/product.py:108](../addons/account/models/product.py#L108), [`_compute_valuation() — product.py:197`](../addons/account/models/product.py#L197), [`_compute_cost_method() — product.py:209`](../addons/account/models/product.py#L209)

Note the module move: in Odoo 19 these fields lived in `stock_account/models/product.py`. In Odoo 20 `property_valuation`, `property_cost_method`, `property_stock_valuation_account_id`, `property_stock_journal` and the computed `valuation` / `cost_method` are defined in **`account/models/product.py`**, because periodic closing works even without `stock` installed.

**What this changes for migration:** on a fresh Odoo 20 database, importing inventory produces **no accounting entries at all** unless you explicitly switch the company (or the product category) to `real_time`. That is not a bug — it is the new default. Decide up front:

| Decision | What you do in Step 5 |
|---|---|
| Keep periodic (default) | Load quantities only. Carry the opening inventory value through the opening TB on the real stock account. No `MIG_STOCK_CLEAR` needed. Run the first closing entry after go-live. |
| Switch to perpetual | Set `inventory_valuation = 'real_time'` **before** any stock move, configure valuation accounts, then follow 5.1 below with `MIG_STOCK_CLEAR`. |

Under periodic valuation, Odoo generates the stock entry at closing, not per move:

- `res.company.action_close_stock_valuation()` builds the closing journal entry — [company.py:1278](../addons/account/models/company.py#L1278)
- `_cron_post_stock_valuation()` runs it automatically for companies with `inventory_period` in `daily` / `monthly` — [company.py:1447](../addons/account/models/company.py#L1447), cron record [`service_cron.xml:23`](../addons/account/data/service_cron.xml#L23)
- The variation and expense counterparts come from `account.account.account_stock_variation_id` / `account_stock_expense_id` (see 3.11)

**Do not run a closing before the opening move is posted and validated.** `action_close_stock_valuation()` refuses to generate an entry dated before an existing closing ("It exists closing entries after the selected date"), so an accidental early closing is painful to unwind.

### 5.1 When real-time accounting entries are created

With `real_time` valuation, inventory journal entries are created only when **all five** conditions hold:

```python
def _should_create_account_move(self):
    self.ensure_one()
    return self.product_id.is_storable and self.is_valued\
    and (self.location_dest_id.valuation_account_id or self.location_id.valuation_account_id)\
    and not self.uom_id.is_zero(self.quantity)\
    and self.product_id.valuation == 'real_time'
```

Source: [`_should_create_account_move() — stock_account/models/stock_move.py:756`](../addons/stock_account/models/stock_move.py#L756)

| Condition | What it means |
|---|---|
| `product_id.is_storable` | Product must be a goods product tracked in inventory (not consumable or service) |
| `is_valued` | Move must be `is_in`, `is_out` or `is_dropship` |
| `location.valuation_account_id` | Source or destination location must have a valuation account set |
| `not uom_id.is_zero(quantity)` | **New in Odoo 20** — zero-quantity moves are skipped outright |
| `product_id.valuation == 'real_time'` | Resolved from category, then company (see 5.0) |

If any condition is false, no accounting entry is created — the inventory count creates stock lines but has zero financial impact.

**Critical: value is resolved in this fallback order:**

1. Manual value override (`_get_manual_value`)
2. Invoice/Bill amount (if a related purchase or sale document exists)
3. SO/PO lines
4. `standard_price` at the time of the move

Source: [`_get_value_data() — stock_account/models/stock_move.py:442`](../addons/stock_account/models/stock_move.py#L442)

**Migration risk:** If products have `standard_price = 0` at the time the inventory adjustment is validated, all stock moves will be valued at 0. The `MIG_STOCK_CLEAR` account will not go to zero, and your inventory will appear on the balance sheet at zero value.

**Required precheck before Step 5:** Set all product `standard_price` values to the correct opening cost *before* importing inventory quantities. For FIFO/AVCO products, also verify the costing method is correct before the first move — changing `res.company.cost_method` afterwards triggers `_correct_inventory_valuation()`, which replays valuation from the last closing date.
Source: [`ResCompany.write() — stock_account/models/res_company.py:18`](../addons/stock_account/models/res_company.py#L18)

### 5.2 Import physical stock

Use inventory adjustment import (`stock.quant`) with fields such as:

- Product
- Location
- Counted quantity
- Lot/serial where needed
- Optional accounting date

Sources: [`action_apply_inventory() — stock_quant.py:465`](../addons/stock/models/stock_quant.py#L465), [`action_apply_all() — stock_quant.py:550`](../addons/stock/models/stock_quant.py#L550), [`accounting_date — stock_account/models/stock_quant.py:12`](../addons/stock_account/models/stock_quant.py#L12)

### 5.3 Valuation alignment

For real-time valuation, stock moves generate account entries using the source and destination **location** valuation accounts (`stock.location.valuation_account_id`) — not a single global account.

Do not assume one universal counterpart account.

Practical migration method:

- Configure stock valuation accounts correctly before import.
- If needed, map temporary counterpart to `MIG_STOCK_CLEAR` for migration period.
- After import, verify inventory valuation report and GL stock valuation account.

For periodic valuation, there is nothing to align per move. Instead:

- Confirm `res.company.get_inventory_value()` (what the valuation report shows) matches the legacy inventory value at cut-off.
- Confirm the opening TB stock balance matches that same number. The first closing entry then posts only genuine post-go-live movement.

### 5.4 Inventory control checks

- Quantities match legacy physical count.
- Stock valuation total matches legacy inventory value at cut-off.
- `MIG_STOCK_CLEAR` is zero after final reclass/reconciliation (perpetual only).
- Periodic only: no closing entry exists with a date on or before the opening date.

---

### Step 6 - Import fixed assets (Enterprise `account_asset`)

**Odoo 20 restructured this module.** An asset is no longer one flat record. Read 6.0 before building your import file.

### 6.0 The three-model structure (new in Odoo 20)

| Model | File | What it holds |
|---|---|---|
| `account.asset` | [account_asset.py](../enterprise/account_asset/models/account_asset.py) | The asset itself: name, cost, acquisition date, fixed-asset account, asset group, properties |
| `account.asset.variant` | [account_asset_variant.py:25](../enterprise/account_asset/models/account_asset_variant.py#L25) | One depreciation *book* for that asset: state, journal, depreciation/expense accounts, `already_depreciated_amount_import`, `value_residual`, `book_value`, the depreciation move lines |
| `account.depreciation.model` | [account_depreciation_model.py:14](../enterprise/account_asset/models/account_depreciation_model.py#L14) | Reusable method configuration: `method`, `method_number`, `method_period`, `method_progress_factor`, `prorata_computation_type`, `salvage_value_percent`, journal, ledger accounts |

Every asset gets a `main_variant_id` created implicitly on `create()`. With multi-ledger companies (a company that has `account.journal.group` records), an asset can carry additional *ledger variants* — a second depreciation book in a secondary ledger, e.g. tax vs statutory depreciation.
Source: [`AccountAsset.create() — account_asset.py:410`](../enterprise/account_asset/models/account_asset.py#L410), [`account_asset_ledger_variant.py`](../enterprise/account_asset/models/account_asset_ledger_variant.py)

Practical consequences for an import:

- `method`, `method_number`, `method_period` are **no longer writable on the asset**. On `account.asset.variant` they are `related='model_id.*'`, so the duration and method come from the depreciation model. You import `model_id`, not the individual method fields.
- `account.asset.create()` splits your vals: keys matching `account.asset` fields stay on the asset, keys matching non-readonly non-related fields of `account.asset.variant` are forwarded to the main variant.
  Source: [`_split_assets_variants_vals() — account_asset.py:446`](../enterprise/account_asset/models/account_asset.py#L446)
- `account_depreciation_id` / `account_depreciation_expense_id` live on the variant. To seed them from a flat import file, Odoo 20 added two **import-only** (`store=False`) fields on `account.asset`:
  `import_account_depreciation_id` and `import_account_depreciation_expense_id` — [account_asset.py:149](../enterprise/account_asset/models/account_asset.py#L149). `create()` copies them onto the main variant.
- `salvage_value` is now computed from the model's `salvage_value_percent` (`store=True, readonly=False`), so it is still importable, but a value you import can be overwritten if the model's percentage recomputes. Its label is now "Not Depreciable Value".
- `method` gained a `no_depreciation` option, and `account.depreciation.model` gained `method_mode` (`duration` vs `rate`) with `method_rate`.

**Import order:** depreciation models → assets (with `model_id` + `import_account_*`) → verify each asset's main variant.

### 6.1 Key fields for migration

On `account.asset`:

- `name`
- `original_value`
- `acquisition_date`
- `account_asset_id`
- `asset_group_id` (optional)
- `import_account_depreciation_id`
- `import_account_depreciation_expense_id`

Forwarded to the main `account.asset.variant`:

- `model_id` (required on the variant — points at an `account.depreciation.model`)
- `already_depreciated_amount_import`
- `salvage_value`
- `prorata_date`, `prorata_computation_type` (if you need to override the model)

### 6.2 Critical field for legacy imports

Use `already_depreciated_amount_import`.

Source: [`account_asset_variant.py:127`](../enterprise/account_asset/models/account_asset_variant.py#L127) (exposed on the asset as a writable related field at [account_asset.py:128](../enterprise/account_asset/models/account_asset.py#L128))

Field help text (from source): "In case of an import from another software, you might need to use this field to have the right depreciation table report. This is the value that was already depreciated with entries not computed from this model."

**How it affects computation:**

The `value_residual` field (depreciable remaining value) is calculated as:

```
value_residual = original_value
               - salvage_value
               - already_depreciated_amount_import
               - sum(posted_depreciation_moves.depreciation_value)
```

Source: [`_compute_value_residual() — account_asset_variant.py:258`](../enterprise/account_asset/models/account_asset_variant.py#L258)

This means: you keep the full historical cost in `original_value`, put legacy accumulated depreciation in `already_depreciated_amount_import`, and Odoo calculates the remaining schedule from there. You do **not** need to post years of historical depreciation entries.

**Book value formula:**

`book_value = value_residual + salvage_value + sum(children_ids.book_value)`

(the `children_ids` term covers gross-value-increase sub-assets; it is zero for a plain imported asset)
Source: [`_compute_book_value() — account_asset_variant.py:281`](../enterprise/account_asset/models/account_asset_variant.py#L281)

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

`amount_residual` is a stored computed field on `account.move.line` ([account_move_line.py:280](../addons/account/models/account_move_line.py#L280)). It reflects the unreconciled balance after partial reconciliations.

Odoo 20 adds `residual_at_date` / `residual_currency_at_date` — the residual **as of a given date**, computed in SQL from the partial reconciliations whose `max_date` falls on or before that date. It is what the Aged Receivable/Payable reports now read, so use it when you want an as-of-cut-off comparison rather than a today comparison. It only differs from `amount_residual` when the `recon_limit` context key is set (the `open_on` field sets it).
Source: [`residual_at_date — account_move_line.py:328`](../addons/account/models/account_move_line.py#L328), [`_compute_sql_residual_at_date() — account_move_line.py:1120`](../addons/account/models/account_move_line.py#L1120)

---

### Step 10 - Post opening move and lock periods

### 10.1 Post opening move

Post only after all controls pass.

### 10.2 Lock dates in Odoo 20

Unchanged from 19. The four soft locks plus one hard lock:

- `fiscalyear_lock_date` (labelled "Global Lock Date")
- `tax_lock_date`
- `sale_lock_date`
- `purchase_lock_date`
- `hard_lock_date`

Source: [`SOFT_LOCK_DATE_FIELDS` / `LOCK_DATE_FIELDS` — company.py:60](../addons/account/models/company.py#L60)

For branches, the effective lock date is the **maximum across the company and all its ancestors**, minus any active `account.lock_exception` for the current user.
Source: [`_get_user_lock_date() — company.py:749`](../addons/account/models/company.py#L749)

### 10.3 Hard lock warning

`hard_lock_date` cannot be removed or moved backwards.

Source: [`_validate_locks() — company.py:694`](../addons/account/models/company.py#L694)

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

| Template (Odoo 20 label) | UI path | File path | Use for |
|---|---|---|---|
| Template for Chart of Accounts | Accounting → Configuration → Chart of Accounts → Import | `/account/static/xls/coa_import_template.xlsx` | `opening_debit/opening_credit` import |
| Template for Journal Items | Accounting → Accounting → Journal Items → Import | `/account/static/xls/aml_import_template.xlsx` | Misc journal entry lines |
| Template for Misc. Operations | Accounting → Accounting → Journal Entries → Import | `/account/static/xls/misc_operations_import_template.xlsx` | Full journal entry import |
| Template for Invoices / Credit Notes | Accounting → Customers → Invoices → Import | `/account/static/xls/customer_invoices_credit_notes_import_template.xlsx` | AR open items (invoice pattern) |
| Template for Bills / Refunds | Accounting → Vendors → Bills → Import | `/account/static/xls/vendor_bills_refunds_import_template.xlsx` | AP open items (bill pattern) |

`account.move.get_import_templates()` picks the template from `default_move_type` in the context, so the label you see depends on which list view you opened the import dialog from.

Source: [`account_account.get_import_templates() — account_account.py:1198`](../addons/account/models/account_account.py#L1198), [`account_move.get_import_templates() — account_move.py:8252`](../addons/account/models/account_move.py#L8252), [`account_move_line.get_import_templates() — account_move_line.py:3839`](../addons/account/models/account_move_line.py#L3839)

**How the importer matches column headers** (in priority order):
1. A mapping the user saved previously for this model
2. Exact match on technical field name / English label / translated label
3. Fuzzy match — word distance between the header and the field name or label, restricted to fields whose type is compatible with the column's detected data type

Source: [`_get_mapping_suggestion() — base_import.py:833`](../addons/base_import/models/base_import.py#L833)

**Practical guidance:** Use the official Odoo template headers as-is. Do not rename columns. If you must use custom headers, use the technical field name — it is unambiguous and language-independent. Because step 3 is a *fuzzy* match, a mistyped header does not fail loudly; it silently maps to the nearest field. Always review the mapping screen before running the import.

---

## 12) Error Messages You Will Encounter

These are exact error messages from Odoo 20 source. Knowing them saves diagnosis time.

| Message | Source location | When you see it | How to fix |
|---|---|---|---|
| "Please install a chart of accounts or create a miscellaneous journal before proceeding." | [company.py:964](../addons/account/models/company.py#L964) | Trying to set opening balances before a general journal exists | Install COA first or create a Miscellaneous journal manually |
| "You cannot import the 'openning_balance' if the opening move (%s) is already posted. If you are absolutely sure you want to modify the opening balance of your accounts, reset the move to draft." | [company.py:1022](../addons/account/models/company.py#L1022) | Trying to write `opening_debit/opening_credit` after the opening entry is posted | Reset the opening entry to draft (Accounting Manager access required) |
| "Incorrect fiscal year date: day is out of range for month. Month: %(month)s; Day: %(day)s" | [setup_wizards.py:39](../addons/account/wizard/setup_wizards.py#L39) | Setting fiscal year end to an invalid date (e.g., Feb 30) | Use a valid calendar date |
| "You cannot have a receivable/payable account that is not reconcilable. (account code: %s)" | [account_account.py:38](../addons/account/models/account_account.py#L38) | Trying to set `reconcile = False` on an AR/AP account | Do not change `reconcile` on these accounts — it is enforced |
| "An Off-Balance account can not be reconcilable" | [account_account.py:170](../addons/account/models/account_account.py#L170) | Setting `reconcile = True` on an `off_balance` account | Off-balance accounts cannot be reconciled |
| "Bank & Cash accounts cannot be shared between companies." | [account_account.py:259](../addons/account/models/account_account.py#L259) | An `asset_cash` account imported with more than one company in `company_ids` | One bank/cash account per company — split the record |
| "Account codes must be unique. You can't create accounts with these duplicate codes: %s" | [account_account.py:1126](../addons/account/models/account_account.py#L1126) | Two accounts with the same code in the same company branch | Deduplicate the import file; codes are checked across parent and child companies |
| "The account code can only contain alphanumeric characters, dots, and dashes. (account code: %s)" | [account_account.py:293](../addons/account/models/account_account.py#L293) | Code contains spaces, slashes, etc. | Clean the legacy codes. Note dashes are now allowed (they were not in 19) |
| "A temporary number can not be used in a real matching" | [account_move_line.py:1956](../addons/account/models/account_move_line.py#L1956) | Setting an `I*` matching number on a line that already has real partial reconciles | Do not mix import markers with real reconciled lines |
| "There are still draft entries in the period you want to hard lock. You should either post or delete them." | [company.py:726](../addons/account/models/company.py#L726) | Setting hard lock date when draft entries exist up to that date | Post or delete all draft entries up to the lock date |
| "It exists closing entries after the selected date. Cancel them before generate an entry prior to them" | [company.py:1283](../addons/account/models/company.py#L1283) | Running a periodic inventory closing dated before an existing one | Cancel the later closing entry first |

**Removed in Odoo 20:** "You cannot switch an account to prevent the reconciliation if some partial reconciliations are still pending." The `_toggle_reconcile_to_false()` helper that raised it no longer exists — see 3.6.

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

`opening_balance` is a first-class field on `account.account` ([account_account.py:145](../addons/account/models/account_account.py#L145)). Using it reduces sign mistakes when your source data is already a signed net balance rather than split debit/credit columns.

Add `parent_id` if you are importing a hierarchical chart (see 3.9), and import parent rows before child rows.

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

### 13.5 Asset opening (Odoo 20 column set)

- `name`
- `original_value`
- `acquisition_date`
- `account_asset_id`
- `model_id` — the `account.depreciation.model` that carries `method` / `method_number` / `method_period`
- `already_depreciated_amount_import`
- `salvage_value`
- `import_account_depreciation_id`
- `import_account_depreciation_expense_id`

Do **not** put `method`, `method_number` or `method_period` in the file — they are read-only related fields in Odoo 20. Create the depreciation models first (file `06a_depreciation_models.csv`) and reference them by external ID.

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

## 16) What Changed Between Odoo 19 and Odoo 20

If you have run this migration before on Odoo 19, these are the deltas that change your files or your sequence.

| Area | Odoo 19 | Odoo 20 | Impact on migration |
|---|---|---|---|
| Chart of accounts structure | `account.group` model, matched by code prefix ranges | `account.account.parent_id` tree (`_parent_store`); `account.group` removed | Rewrite group imports as parent accounts; import `parent_id`; parents before children (3.9) |
| Account code | `^[A-Za-z0-9.]+$`, required on every company | dashes allowed; no longer required on every company | Legacy codes with `-` import as-is; grouping accounts may be code-less |
| Bank/cash account creation | no side effect | `_create_default_journals()` auto-creates a bank/credit journal | Importing a chart creates journals; suppress with `skip_auto_account_journal_creation` (3.10) |
| `account.reconcile` | gated matching, rewrote residuals when toggled | bank-reconciliation flag only; toggling has no side effect | No need to pre-flip it on clearing accounts (3.6) |
| `account_opening_date` | no default | defaults to today | Set the real cut-off date before the first opening import (3.1) |
| Opening-balance UI | post from the move form | "Validate and Post" button in the opening-balance list | Faster, but irreversible from that screen (3.5) |
| Inventory valuation config | product category property, per product | `res.company.inventory_valuation` / `cost_method` / `account_stock_valuation_id`, category and product override it | New DBs default to **periodic** — no stock entries at all unless you opt into `real_time` (5.0) |
| Periodic closing | manual journal entries | `action_close_stock_valuation()` + `_cron_post_stock_valuation()` driven by `inventory_period` | Post the opening move before any closing runs (5.0) |
| Valuation field location | `stock_account/models/product.py` | `account/models/product.py` | Path changes in scripts and studio references |
| Fixed assets | one flat `account.asset` | `account.asset` + `account.asset.variant` + `account.depreciation.model` | `method`/`method_number`/`method_period` are no longer importable on the asset; import `model_id` and the two `import_account_*` fields (6.0) |
| Aged report residual | inline partial-reconciliation SQL | `account.move.line.residual_at_date` computed-SQL field | Cut-off comparisons are easier and match the report exactly (9.4) |
| Security files | `ir.model.access.csv` + `ir.rule` | unified `ir.access.csv` / `ir.access` model | Any custom migration module's security files must be converted |

Everything else in this runbook — the opening-move engine, the clearing-account design, the import order, the validation matrix — is unchanged between 19 and 20.

---

## 17) Source References (Odoo 20 Code)

| Topic | File | Symbols / lines |
|---|---|---|
| Opening move fields and update logic | [account/models/company.py](../addons/account/models/company.py) | `account_opening_move_id` (175), `account_opening_date` (177), `_get_default_opening_move_values` (949), `get_unaffected_earnings_account` (977), `_update_opening_move` (1009) |
| Opening field import batching | [account/models/account_account.py](../addons/account/models/account_account.py) | `opening_debit`/`opening_credit`/`opening_balance` (143–145), `_set_opening_debit_credit` (736), `_load_precommit_update_opening_move` (955), `action_validate_opening_move` (1184) |
| Hierarchical chart of accounts | [account/models/account_account.py](../addons/account/models/account_account.py) | `_order`/`_parent_store` (29–30), `parent_id` (133), `ACCOUNT_CODE_REGEX` (17), `_ensure_code_is_unique` (1089), `_create_default_journals` (1129) |
| Lock dates and hard lock | [account/models/company.py](../addons/account/models/company.py) | `SOFT_LOCK_DATE_FIELDS`/`LOCK_DATE_FIELDS` (60, 67), `_validate_locks` (694), `_get_user_lock_date` (749), `_get_violated_lock_dates` (865) |
| Lock-date move shifting | [account/models/account_move.py](../addons/account/models/account_move.py) | `_post` lock check (6252), `_get_accounting_date` (7427) |
| Reconcile constraints and semantics | [account/models/account_account.py](../addons/account/models/account_account.py) | `_check_reconcile` (34), `_constrains_reconcile` (165), `reconcile` (112), `_compute_reconcile` (711) |
| Import-time reconciliation tagging | [account/models/account_move_line.py](../addons/account/models/account_move_line.py) | `matching_number` (358), `_sanitize_vals` (2063), `_reconcile_marked` (3485), `_check_amls_exigibility_for_reconciliation` (2969) |
| Residual fields | [account/models/account_move_line.py](../addons/account/models/account_move_line.py) | `amount_residual` (280), `residual_at_date` (328), `_compute_sql_residual_at_date` (1120) |
| Aged receivable/payable engine | [account_reports/models/account_aged_partner_balance.py](../enterprise/account_reports/models/account_aged_partner_balance.py) | `_aged_partner_report_custom_engine_common` (85) |
| Inventory adjustment | [stock/models/stock_quant.py](../addons/stock/models/stock_quant.py), [stock_account/models/stock_quant.py](../addons/stock_account/models/stock_quant.py) | `action_apply_inventory` (465), `action_apply_all` (550), `accounting_date` (12) |
| Perpetual valuation entries | [stock_account/models/stock_move.py](../addons/stock_account/models/stock_move.py) | `_should_create_account_move` (756), `_get_value_data` (442) |
| Periodic valuation config and closing | [account/models/company.py](../addons/account/models/company.py), [account/models/product.py](../addons/account/models/product.py) | `inventory_valuation` (343), `inventory_period` (358), `action_close_stock_valuation` (1278), `_cron_post_stock_valuation` (1447), `valuation` (108) |
| Asset migration | [account_asset/models/account_asset.py](../enterprise/account_asset/models/account_asset.py), [account_asset_variant.py](../enterprise/account_asset/models/account_asset_variant.py), [account_depreciation_model.py](../enterprise/account_asset/models/account_depreciation_model.py) | `import_account_depreciation_id` (149), `_split_assets_variants_vals` (446); variant `already_depreciated_amount_import` (127), `_compute_value_residual` (258), `_compute_book_value` (281) |
| Official import templates | [account_account.py](../addons/account/models/account_account.py), [account_move.py](../addons/account/models/account_move.py), [account_move_line.py](../addons/account/models/account_move_line.py) | `get_import_templates` (1198 / 8252 / 3839) |
| Importer header matching | [base_import/models/base_import.py](../addons/base_import/models/base_import.py) | `_get_mapping_suggestion` (833), `_get_mapping_suggestions` (993) |
| COA onboarding editor | [account/models/onboarding_onboarding_step.py](../addons/account/models/onboarding_onboarding_step.py) | `action_open_step_chart_of_accounts` (79) |

---

## 18) Final Practical Rules

- Never do first import on production.
- Never post opening move before full validation.
- Never leave migration clearing accounts unexplained.
- Never set hard lock date before final sign-off.
- Keep every migration file versioned and reproducible.

If you follow this runbook, your Odoo 20 accounting start will be controlled, auditable, and operationally usable from day one.

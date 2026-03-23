# Equity (Cap Table Management)

> **Module:** `equity` | **Path:** [`enterprise/equity/`](../enterprise/equity/)
> **Odoo Apps category:** Accounting/Accounting (UI placement only -- no accounting integration)

## What It Does

Manages company **cap tables** (capitalization tables): who owns what securities (shares and options), ownership percentages, voting rights, and company valuations over time. Also tracks **Ultimate Beneficial Owners (UBO)** for AML/KYC regulatory compliance. This is a **corporate governance tool**, not an accounting tool -- it does not create journal entries, does not post to the general ledger, and has no effect on the Balance Sheet report.

---

## When to Use This Module

Track equity ownership structure, cap table changes, and shareholder communications. Required when your company needs to report UBO information under EU Anti-Money Laundering directives.

### Best For
- Startups and companies tracking share issuance across funding rounds (Seed, Series A, etc.)
- Stock option pool management for employees (issuance, vesting, exercise, expiration)
- Maintaining legally required UBO declarations with document attachments
- Shareholder portal access -- allowing investors to view their positions externally

### Not For
- **Recording equity in accounting** -- Balance Sheet equity accounts (retained earnings, share capital) are managed through `account` module journal entries, not this module
- **Payroll stock compensation** -- use `hr_payroll` for salary-based compensation
- **Simple partner ownership tracking** -- if you only need to note "Company A owns Company B" without detailed cap table math, use contact fields instead

---

## Real-World Use Cases

### Use Case 1: Seed Funding Round
**Situation:** A startup raises EUR 500,000 from two investors. The founder already holds 10,000 ordinary shares.
**In Odoo:** Equity > Ownership > Transactions > Create. Set transaction_type = "Issuance", security_class = "Seed Shares", subscriber = Investor A, securities = 2,000, price per security = 125. Repeat for Investor B. Record a Valuation of EUR 1,250,000.
**Result:** Cap Table shows each holder's ownership %, voting rights %, and stake valuation. Dashboard displays the company kanban card with updated shareholder count and valuation chart.

### Use Case 2: Employee Stock Option Exercise
**Situation:** An employee was granted 500 options from the "Option Pool" class 2 years ago. They want to exercise (convert) them into ordinary shares.
**In Odoo:** Equity > Ownership > Transactions > Create. Set transaction_type = "Exercise", subscriber = Employee, security_class = "Option Pool" (options type), destination_class = "Ordinary Shares" (shares type), securities = 500.
**Result:** 500 options disappear from the employee's option pool balance, 500 ordinary shares appear. Ownership and voting percentages recalculate across all holders. The method [`_compute_invalid_securities_error()`](../enterprise/equity/models/equity_transaction.py#L137) validates the employee actually holds enough options before allowing the transaction.

### Use Case 3: UBO Declaration for Regulatory Compliance
**Situation:** EU regulations require companies to declare individuals who own 25%+ or control the company. A company has a majority shareholder (60%) and a CEO who controls day-to-day operations.
**In Odoo:** Equity > Ownership > UBO > Create. For the majority shareholder: control_method = "co_1" (Capital Ownership), ownership = 60%, voting_rights = 60%, attach identity document. For the CEO: control_method = "co_3" (Executive Officer), auth_rep_role = "CEO". Send portal form request via activity to collect signed declarations.
**Result:** UBO records maintained with document attachments and expiration dates. PDF report generated from portal submission. Activity tracking ensures follow-up on missing documents.

### Use Case 4: Share Transfer Between Shareholders
**Situation:** Founder A sells 1,000 shares to a new investor.
**In Odoo:** Equity > Ownership > Transactions > Create. Set transaction_type = "Transfer", seller = Founder A, subscriber = New Investor, security_class = "Ordinary Shares", securities = 1,000, price per security = 200.
**Result:** Cap table automatically deducts 1,000 shares from Founder A and adds 1,000 to New Investor. Validation at [`_compute_invalid_securities_error():156-204`](../enterprise/equity/models/equity_transaction.py#L156) ensures the seller has enough shares. Both parties can be notified via the "Send to Seller" / "Send to Subscriber" buttons.

---

## How-To Scenarios

### How to Create a Security Class
1. Equity > Configuration > Security Classes > Create
2. Set **Name** (e.g., "Ordinary Shares", "Series A Preferred", "Option Pool")
3. Set **Type** (`class_type`): "Shares" or "Options"
4. **Votes per Share** (`share_votes`): defaults to 1 for shares, 0 for options (editable for dual-class structures)
5. **Dividend Payout** (`dividend_payout`): defaults to True for shares, False for options (editable)

**Why this works:** The [`_compute_share_votes()`](../enterprise/equity/models/equity_security_class.py#L49) and [`_compute_dividend_payout()`](../enterprise/equity/models/equity_security_class.py#L54) methods set defaults based on class_type but allow manual override. Cannot change type once transactions exist ([`_check_existing_transactions()`](../enterprise/equity/models/equity_security_class.py#L30)).

### How to Record a Company Valuation
1. Equity > Ownership > Valuations > Create
2. Select **Company** (`partner_id`), set **Date** and **Event** type ("Audit" or "Transaction")
3. Enter either **Valuation** amount or **Price per Share** (`share_price`) -- the other calculates automatically
4. Optionally attach supporting documents (audit report, term sheet)

**Why this works:** [`_compute_share_price()`](../enterprise/equity/models/equity_valuation.py#L55) divides valuation by total shares. The inverse [`_inverse_compute_share_price()`](../enterprise/equity/models/equity_valuation.py#L61) lets you set share_price and compute total valuation. The cap table's SQL view joins the latest valuation to compute each holder's stake value via [`LATERAL JOIN`](../enterprise/equity/models/equity_cap_table.py#L85).

### How to Send Shareholder Portal Access
1. Open a transaction > click "Send to Subscriber" or "Send to Seller"
2. An email wizard opens with a pre-filled template containing a portal access link
3. The shareholder receives a unique URL with an encrypted access token

**Why this works:** [`_equity_ensure_token()`](../enterprise/equity/models/res_partner.py#L138) generates a UUID token stored in a `NO_ACCESS` group field. The portal templates at [`equity_portal_templates.xml`](../enterprise/equity/views/equity_portal_templates.xml) render the shareholder's transactions, cap table position, and valuations.

---

## Dependencies

### Requires (must be installed)
| Module | Why |
|---|---|
| `portal` | Shareholder portal access -- external users view their equity positions via unique URLs |

### Optional Integrations
None. The equity module is fully standalone.

### Provides To (what other modules consume from this one)
None. No other standard Odoo module depends on equity.

### NOT Connected To
| Module | Clarification |
|---|---|
| `account` | **No dependency.** The Balance Sheet "Equity" section comes from journal entries on equity-type accounts, not from this module. The module is categorized under Accounting in the UI (`module_category_accounting`) for menu placement only. |

---

## Business Flow

### Transaction Flow
```
Create Security Class  →  Record Transaction  →  Cap Table Updates  →  Valuation Reflects
       ↓                        ↓                       ↓                      ↓
  Shares or Options     Issuance/Transfer/       SQL view recomputes     Holder stake =
                        Exercise/Cancellation    ownership, voting,      (securities / total)
                                                 dilution %              × latest valuation
```

### UBO Flow
```
Create UBO Record  →  Send Portal Form Request  →  Portal Submission  →  PDF Generated + Activity Closed
       ↓                        ↓                        ↓                         ↓
  Set control method    Mail activity created       External user fills     _ubo_portal_form_filled()
  + holder details      (7-day deadline)            OWL form + uploads     creates PDF attachment
                                                    identity document      and marks activity done
```

### Transaction Types Summary
| Type | Securities Created? | Requires Seller? | Requires Destination Class? | Cap Table Effect |
|---|---|---|---|---|
| **Issuance** | Yes -- new securities | No | No | +N for subscriber |
| **Transfer** | No -- existing move | Yes (must differ from subscriber) | No | -N for seller, +N for subscriber |
| **Exercise** | Converts type | No | Yes (must be 'shares') | -N options, +N shares for subscriber |
| **Cancellation** | No -- removed | No | No | -N for subscriber |

---

## Key Models

### `equity.transaction` -- Securities Transaction
> [`equity_transaction.py`](../enterprise/equity/models/equity_transaction.py)

| Field | Type | UI Label | Purpose |
|---|---|---|---|
| `transaction_type` | `Selection` | "Transaction Type" | `issuance`, `transfer`, `exercise`, `cancellation` |
| `partner_id` | `Many2one(res.partner)` | "Company" | The issuing company |
| `date` | `Date` | -- | Transaction date (required) |
| `securities` | `Float` | "# Securities" | Number of securities (must be positive) |
| `security_class_id` | `Many2one(equity.security.class)` | "Class" | Share/option class |
| `subscriber_id` | `Many2one(res.partner)` | "Subscriber" | Recipient of securities |
| `seller_id` | `Many2one(res.partner)` | "Seller" | Only for transfer transactions |
| `destination_class_id` | `Many2one(equity.security.class)` | -- | Only for exercise (target shares class) |
| `security_price` | `Float` | "Price per Security" | Auto-populated from previous transaction, editable |
| `transfer_amount` | `Monetary` | "Total" | securities x security_price |
| `expiration_date` | `Date` | "Expiration" | Auto-computed: date + 3 years (for options) |

**Constraints:**
- [`_check_seller_and_subscriber()`](../enterprise/equity/models/equity_transaction.py#L77) -- seller and subscriber must differ in transfers; shares must have subscriber
- [`_check_transaction_type()`](../enterprise/equity/models/equity_transaction.py#L91) -- exercise requires options→shares; destination_class only on exercise; seller only on transfer
- [`_check_invalid_securities_error()`](../enterprise/equity/models/equity_transaction.py#L85) -- validates sufficient securities available for cancellation/transfer/exercise

### `equity.security.class` -- Security Class Definition
> [`equity_security_class.py`](../enterprise/equity/models/equity_security_class.py)

| Field | Type | UI Label | Purpose |
|---|---|---|---|
| `name` | `Char` | -- | Class name (e.g., "ORD", "Seed", "Option Pool") |
| `class_type` | `Selection` | "Type" | `shares` or `options` |
| `share_votes` | `Integer` | "Votes per Share" | Default: 1 for shares, 0 for options |
| `dividend_payout` | `Boolean` | -- | Default: True for shares, False for options |
| `sequence` | `Integer` | -- | Display ordering |

**Constraints:**
- [`_check_existing_transactions()`](../enterprise/equity/models/equity_security_class.py#L30) -- cannot change `class_type` if transactions exist

### `equity.cap.table` -- Cap Table (SQL View)
> [`equity_cap_table.py`](../enterprise/equity/models/equity_cap_table.py)

**Not a real database table** (`_auto = False`). Computed dynamically from transactions via a SQL query with window functions.

| Field | Type | Purpose |
|---|---|---|
| `partner_id` | `Many2one(res.partner)` | Company |
| `holder_id` | `Many2one(res.partner)` | Shareholder/option holder |
| `security_class_id` | `Many2one(equity.security.class)` | Security type held |
| `securities` | `Float` | Total securities held |
| `votes` | `Float` | Total voting rights (securities x share_votes) |
| `ownership` | `Float` | % of company shares owned (shares only) |
| `voting_rights` | `Float` | % of total voting power |
| `dividend_payout` | `Float` | % eligible for dividends |
| `dilution` | `Float` | % of all securities (including options) |
| `valuation` | `Float` | Holder's stake value (dilution x latest company valuation) |

**Key logic in [`_table_query`](../enterprise/equity/models/equity_cap_table.py#L29):**
- Sums all transaction effects per (partner, holder, security_class) triplet
- Issuance/Transfer: +securities for subscriber
- Exercise: -securities from options class, +securities to destination shares class
- Transfer: also -securities from seller
- Cancellation: -securities from subscriber
- Ownership = holder's shares / total shares (PARTITION BY partner)
- Valuation = holder's dilution x latest `equity.valuation` (via LATERAL JOIN)
- Supports date filtering via `current_date` context key

### `equity.valuation` -- Company Valuation Record
> [`equity_valuation.py`](../enterprise/equity/models/equity_valuation.py)

| Field | Type | UI Label | Purpose |
|---|---|---|---|
| `event` | `Selection` | -- | `audit` or `transaction` (why valuation was recorded) |
| `date` | `Date` | -- | Valuation date |
| `partner_id` | `Many2one(res.partner)` | "Company" | Valued company |
| `valuation` | `Monetary` | -- | Total company valuation amount |
| `securities` | `Float` | "# Securities" | Computed: total securities as of date |
| `shares` | `Float` | "# Shares" | Computed: shares only (excludes options) |
| `security_price` | `Monetary` | "Price per Security" | Computed: valuation / total securities |
| `share_price` | `Float` | "Price per Share" | Computed (with inverse): valuation / shares |

### `equity.ubo` -- Ultimate Beneficial Owner
> [`equity_ubo.py`](../enterprise/equity/models/equity_ubo.py)

| Field | Type | UI Label | Purpose |
|---|---|---|---|
| `partner_id` | `Many2one(res.partner)` | "Company" | Company being controlled |
| `holder_id` | `Many2one(res.partner)` | "Holder" | Individual person (not company) |
| `start_date` | `Date` | "Control Start Date" | When control began |
| `end_date` | `Date` | "Control End Date" | When control ended (optional) |
| `control_method` | `Selection` | -- | One of 9 methods (see table below) |
| `ownership` | `Float` | -- | % owned (only visible for co_1) |
| `voting_rights` | `Float` | -- | % voting rights (only visible for co_1) |
| `auth_rep_role` | `Selection` | "Role" | Position held (only visible for co_3, ngo_2) |
| `attachment_ids` | `One2many(ir.attachment)` | "Attachments" | Identity documents |
| `attachment_expiration_date` | `Date` | "Document Exp. Date" | When documents expire |

**UBO Control Methods:**

| Code | Category | Meaning |
|---|---|---|
| `co_1` | Company | Capital ownership or voting rights (25%+) |
| `co_2` | Company | Control by other means |
| `co_3` | Company | Executive officer (CEO, director, etc.) |
| `ngo_1` | NGO | Directors |
| `ngo_2` | NGO | Individuals with representation authority |
| `ngo_3` | NGO | Day-to-day management |
| `ngo_4` | NGO | Founders of a foundation |
| `ngo_5` | NGO | Main interest beneficiaries |
| `ngo_6` | NGO | Control by other means |

**Authorized Representative Roles** (for `co_3`, `ngo_2`): Board Member, Managing Director, Chairman, Auditor, Liquidator, CEO, Secretary, Treasurer.

**Constraints:**
- [`_unique_ubo`](../enterprise/equity/models/equity_ubo.py#L67) -- unique (partner_id, holder_id) -- one UBO record per person per company

### `res.partner` -- Extensions
> [`res_partner.py`](../enterprise/equity/models/res_partner.py)

**Company-level fields:**
- `equity_currency_id` -- default currency for equity transactions
- `equity_legal_form` -- company legal structure (free text)
- `equity_formation_date` -- when company was formed
- `equity_transaction_ids` / `equity_transaction_count` -- linked transactions
- `equity_shareholders_count` -- distinct holders from cap table
- `equity_valuation_ids` / `equity_last_valuation` -- linked valuations

**Individual-level fields (UBO):**
- `ubo_birth_date`, `ubo_birth_place` -- personal details
- `ubo_national_identifier` -- ID number
- `ubo_pep` -- Politically Exposed Person flag

---

## Key Methods

| Method | File:Line | Purpose |
|---|---|---|
| `_table_query` | [`equity_cap_table.py:29`](../enterprise/equity/models/equity_cap_table.py#L29) | SQL view computing ownership/voting/dilution from transactions |
| `get_cap_table_data()` | [`equity_cap_table.py:112`](../enterprise/equity/models/equity_cap_table.py#L112) | Aggregates cap table data per partner/holder for the OWL component |
| `_compute_invalid_securities_error()` | [`equity_transaction.py:137`](../enterprise/equity/models/equity_transaction.py#L137) | Validates available securities before allowing cancellation/transfer/exercise |
| `_compute_security_price()` | [`equity_transaction.py:207`](../enterprise/equity/models/equity_transaction.py#L207) | Auto-fills price from most recent previous transaction |
| `submit_ubo_form_data()` | [`equity_ubo.py:104`](../enterprise/equity/models/equity_ubo.py#L104) | Processes portal UBO form submission (create/update records + attachments) |
| `_ubo_portal_form_filled()` | [`res_partner.py:152`](../enterprise/equity/models/res_partner.py#L152) | Generates PDF from portal submission, attaches to activity, marks done |
| `open_equity_dashboard()` | [`res_partner.py:98`](../enterprise/equity/models/res_partner.py#L98) | Smart routing: if 1 company, opens cap table directly; if multiple, opens kanban |
| `action_partner_equity_send()` | [`res_partner.py:200`](../enterprise/equity/models/res_partner.py#L200) | Opens email composer with portal access link for shareholder |
| `get_valuation_chart_data()` | [`equity_valuation.py:90`](../enterprise/equity/models/equity_valuation.py#L90) | Generates time-series data for valuation charts (day/month/year frequency) |

---

## UI Entry Points

| Entry Point | Path in UI | What It Does |
|---|---|---|
| Dashboard | Equity > Dashboard | Kanban of companies with shareholder count, valuation, and trend chart |
| Transactions | Equity > Ownership > Transactions | List/kanban/form for recording equity transactions |
| Valuations | Equity > Ownership > Valuations | List/form for company valuation records with chart |
| UBO | Equity > Ownership > UBO | List/form for Ultimate Beneficial Owner declarations |
| Cap Table | Equity > Reporting > Cap Table | Custom OWL component showing holders, classes, percentages |
| Cap Table Pivot | Equity > Reporting > Cap Table Pivot | Standard pivot view of cap table data |
| Valuation Graph | Equity > Reporting > Valuation | Graph view of valuations over time |
| Security Classes | Equity > Configuration > Security Classes | Define share/option classes |
| Send to Subscriber | Transaction form button | Email shareholder with portal access link |
| Send to Seller | Transaction form button (transfer only) | Email seller with portal access link |

---

## Configuration

| Setting | Location | Effect |
|---|---|---|
| `group_equity_viewer` | Users > Accounting > Equity: Viewer | Read-only access to all equity data |
| `group_equity_manager` | Users > Accounting > Equity: Manager | Full CRUD on transactions/valuations/UBOs (no delete on transactions) |
| Security Classes | Equity > Configuration > Security Classes | Define shares vs options, votes per share, dividend eligibility |
| Equity Currency | Contact form > Equity tab | Sets default currency for all equity transactions of that company |

No `res.config.settings` fields exist for this module -- all configuration is done through security groups and security classes.

---

## Edge Cases & Gotchas

- **Not connected to Balance Sheet.** The "Equity" section in Balance Sheet reports comes from `account.move` entries on equity-type accounts (`account_type` = `equity`). This module does not create any journal entries. If you issue shares worth EUR 500,000, you must also create a manual journal entry (Debit: Bank, Credit: Share Capital) in the accounting module separately.

- **Cap table is a SQL view, not a table.** `equity.cap.table` has `_auto = False` and uses `_table_query` to compute data on-the-fly. It cannot be written to. Every `create()` or `write()` on `equity.transaction` calls [`invalidate_model()`](../enterprise/equity/models/equity_transaction.py#L275) on the cap table.

- **Date-aware cap table.** Pass `current_date` in context to get cap table as of a specific date. Without it, defaults to `datetime.max.date()` (all transactions included). This is how valuations compute securities counts at a specific point in time.

- **3-year option expiration.** All transactions auto-compute `expiration_date` = date + 3 years via [`_compute_expiration_date()`](../enterprise/equity/models/equity_transaction.py#L106). This applies to all transactions (not just options), but expiration display logic only shows for option issuances.

- **Price propagation.** New transactions auto-populate `security_price` from the most recent previous transaction for the same company. This is a convenience default -- it can be overridden manually.

- **No delete on transactions.** Managers can create and edit transactions but cannot delete them ([`ir.model.access.csv`](../enterprise/equity/security/ir.model.access.csv) -- `perm_unlink=0`). Only system administrators can delete.

- **UBO uniqueness.** Only one UBO record per (company, holder) pair. You cannot have overlapping UBO records for the same person at the same company -- use `end_date` to mark historical control periods and create a new record for the new period.

- **Portal record rule.** Portal and internal users can only see transactions where they are the `seller_id` or `subscriber_id`. Equity Viewers/Managers see all transactions.

---

## Related Docs

- [`INDEX.md`](INDEX.md)
- [`accounting_coa.md`](accounting_coa.md) -- Balance Sheet equity accounts (the accounting side)
- [`accounting_reports.md`](accounting_reports.md) -- Balance Sheet report that shows accounting equity (unrelated to this module)

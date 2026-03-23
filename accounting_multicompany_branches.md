# Accounting: Multi-Company vs Branches -- Decision Guide with Examples

> **Modules:** `account`, `account_inter_company_rules`, `account_reports`, `account_accountant`, `analytic`
> **Paths:** [`addons/account/`](../addons/account/), [`enterprise/account_inter_company_rules/`](../enterprise/account_inter_company_rules/), [`enterprise/account_reports/`](../enterprise/account_reports/), [`addons/analytic/`](../addons/analytic/)
> **Odoo Version:** 19

---

## The Core Question

You have one business with multiple locations or divisions. Odoo gives you three ways to organize them:

| | **Analytic Accounts** | **Branches** | **Multi-Company** |
|---|---|---|---|
| What it is | Tags on journal entries | Divisions inside ONE legal entity | Separate legal entities |
| Legal identity | None -- just labels | None -- parent's VAT | Each has own VAT |
| Chart of Accounts | 1 shared | 1 shared | 1 per company (separate records) |
| Currency | One | Must match parent | Can differ per company |
| Tax return | 1 combined | 1 combined | 1 per company (unless Tax Unit) |
| Fiscal year | Shared | Shared (delegated from root) | Independent per company |
| Lock dates | Shared | Inherited from root (max of ancestors) | Independent per company |
| Bank accounts | Shared | 1 per branch (required, cannot share) | 1 per company |
| Invoice sequences | Shared | Per branch journal | Per company journal |
| Inter-entity invoicing | N/A | Not needed | Required (auto or manual) |
| Balance Sheet split | Not possible by location | Filter by branch | Separate per company |
| Reports | Analytic filter on P&L only | Company filter on everything | Consolidation toggle |
| Access control per location | Not possible | Yes (company-based) | Yes (company-based) |
| Setup effort | 30 seconds per location | 5 minutes per branch | Hours per company |

**Think of it this way:**
- **Analytic Accounts** = sticky notes on your journal entries ("this cost belongs to Batumi")
- **Branches** = departments inside your company with their own bank accounts and invoice numbers
- **Multi-Company** = completely separate businesses that happen to share one Odoo database

---

## Quick Decision Checklist

Answer each question. If ANY answer is "yes" -- use Multi-Company.

| Question | YES = | NO = |
|---|---|---|
| Separate legal entities (different VAT numbers)? | Multi-Company | Could be branches |
| Separate tax returns? | Multi-Company | Could be branches |
| Different currencies? | Multi-Company | Could be branches |
| Independent Chart of Accounts? | Multi-Company | Could be branches |
| Different fiscal years? | Multi-Company | Could be branches |
| Can one entity sue the other? | Multi-Company | Branches |

ALL answers "no"? Then ask:

| Question | YES = | NO = |
|---|---|---|
| Need per-location bank accounts? | Branches | Could be analytic |
| Need per-location invoice numbering? | Branches | Could be analytic |
| Need per-location access control? | Branches | Could be analytic |
| Need per-location Balance Sheet? | Branches | Could be analytic |

ALL answers "no"? Use **Analytic Accounts** (simplest).

---

## Running Example: "Atlas Group"

Throughout this document, one consistent example shows how each approach works.

**Business:** Atlas Group operates from 3 locations:
- **Tbilisi HQ** -- head office, admin, finance
- **Batumi Office** -- sales team, coastal region
- **Kutaisi Warehouse** -- logistics, distribution

**Monthly numbers (simplified):**

| | Tbilisi HQ | Batumi Office | Kutaisi Warehouse | Total |
|---|---|---|---|---|
| Revenue | 80,000 | 50,000 | 20,000 | 150,000 |
| COGS | 30,000 | 20,000 | 15,000 | 65,000 |
| Salaries | 25,000 | 12,000 | 8,000 | 45,000 |
| Rent | 5,000 | 3,000 | 4,000 | 12,000 |
| **Net Income** | **20,000** | **15,000** | **-7,000** | **28,000** |

---

## Approach A: Branches (Recommended for Atlas Group)

### What Are Branches?

Branches are child companies that share their parent's Chart of Accounts, taxes, and fiscal positions. They are NOT separate legal entities. Think of them as departments with their own bank accounts and journal sequences.

**When Luka in Batumi creates an invoice, the invoice says "Atlas Group" (the legal entity) but internally Odoo knows it belongs to the Batumi branch.**

### Setup

Atlas Group is ONE legal entity, one VAT, one currency (GEL). Use branches.

```
Atlas Group (root company)        <-- CoA, taxes, fiscal positions live here
  |-- Batumi Office (branch)      <-- inherits CoA, gets own journals + bank
  |-- Kutaisi Warehouse (branch)  <-- inherits CoA, gets own journals + bank
```

**Source:** [`res_company.py:36-41`](../odoo/addons/base/models/res_company.py#L36-L41) -- `parent_id`, `child_ids`, `root_id` fields define the hierarchy.

**Important:** Once you create a branch under a parent, you **cannot change the parent later**. The hierarchy is locked at creation. **Source:** [`res_company.py:342-343`](../odoo/addons/base/models/res_company.py#L342-L343) -- raises UserError: "The company hierarchy cannot be changed."

### Chart of Accounts: ONE shared CoA

All 3 locations use the same accounts. When the CoA template loads on the root company, it recursively loads on all children.

**Source:** [`chart_template.py:253-254`](../addons/account/models/chart_template.py#L253-L254)

```
110000  Accounts Receivable     --> shared by all 3 locations
210000  Accounts Payable        --> shared by all 3 locations
400000  Sales Revenue           --> shared by all 3 locations
500000  Cost of Goods Sold      --> shared by all 3 locations
600000  Salaries Expense        --> shared by all 3 locations
620000  Rent Expense            --> shared by all 3 locations
```

**How sharing works technically:** `account.account` uses `company_ids` (Many2many) -- one account record is linked to multiple companies. **Source:** [`account_account.py:97-99`](../addons/account/models/account_account.py#L97-L99)

The `code_store` field is `company_dependent=True` -- the same account can show different codes per company if needed. **Source:** [`account_account.py:40`](../addons/account/models/account_account.py#L40)

**Exception:** Bank/Cash accounts CANNOT be shared between companies. If an account has type `asset_cash` and `len(company_ids) > 1`, Odoo raises an error. **Source:** [`account_account.py:278-279`](../addons/account/models/account_account.py#L278-L279)

### Journals: Each Branch Gets Its Own

Each branch gets its own set of journals so entries are traceable and sequences are separate.

| Journal | Company | Code | Example Invoice |
|---|---|---|---|
| Customer Invoices | Atlas Group (HQ) | INV | INV/2026/0001 |
| Customer Invoices | Batumi Office | INV | INV/2026/0001 (separate counter) |
| Customer Invoices | Kutaisi Warehouse | INV | INV/2026/0001 (separate counter) |
| Bank | Atlas Group (HQ) | BNK1 | -- |
| Bank | Batumi Office | BNK2 | -- |
| Petty Cash | Kutaisi Warehouse | CSH1 | -- |

Journal entries automatically assign to the branch the user is working in via `_compute_company_id()`. **Source:** [`account_move.py:874-878`](../addons/account/models/account_move.py#L874-L878)

```python
# How company auto-assigns on journal entries:
@api.depends('journal_id')
def _compute_company_id(self):
    for move in self:
        if move.journal_id.company_id not in move.company_id.parent_ids:
            move.company_id = (move.journal_id.company_id or self.env.company)._accessible_branches()[:1]
```

**Key insight:** Branches can ACCESS journals from the parent company via the `parent_of` security rule. But the entry's `company_id` will still be set to the user's branch. **Source:** [`account_security.xml:146-150`](../addons/account/security/account_security.xml#L146-L150)

### Fiscal Year & Lock Dates: Inherited from Root

**Root-delegated fields** (set once on root, automatically inherited by all branches):

| Field | Purpose | Source |
|---|---|---|
| `fiscalyear_last_day` | Last day of fiscal year | [`company.py:75`](../addons/account/models/company.py#L75) |
| `fiscalyear_last_month` | Last month of fiscal year | [`company.py:76`](../addons/account/models/company.py#L76) |
| `account_storno` | Use storno accounting (reversal entries) | [`company.py:320-326`](../addons/account/models/company.py#L320-L326) |
| `tax_exigibility` | Cash-basis vs accrual VAT | Same source |

**Source:** [`company.py:320-326`](../addons/account/models/company.py#L320-L326) -- `_get_company_root_delegated_field_names()` enforces these match root.

**Lock dates:** Each branch CAN technically have its own lock date value, but the effective lock date is the **maximum across all ancestors**. The `_get_user_lock_date()` method iterates over `parent_ids` and takes the strictest (latest) date.

**Source:** [`company.py:596-606`](../addons/account/models/company.py#L596-L606)

**Example:** If Atlas Group (root) sets `fiscalyear_lock_date = 2025-12-31`, then Batumi and Kutaisi also cannot post entries on or before 2025-12-31, even if they haven't set their own lock date.

### What the Profit & Loss Looks Like

**P&L -- Atlas Group (all branches, January 2026)**

| Account | Tbilisi HQ | Batumi | Kutaisi | **Total** |
|---|---|---|---|---|
| 400000 Sales Revenue | 80,000 | 50,000 | 20,000 | **150,000** |
| 500000 COGS | (30,000) | (20,000) | (15,000) | **(65,000)** |
| **Gross Profit** | **50,000** | **30,000** | **5,000** | **85,000** |
| 600000 Salaries | (25,000) | (12,000) | (8,000) | **(45,000)** |
| 620000 Rent | (5,000) | (3,000) | (4,000) | **(12,000)** |
| **Net Income** | **20,000** | **15,000** | **(7,000)** | **28,000** |

**How to get this:**
1. Go to Accounting > Reporting > Profit & Loss
2. In the company filter (top-right), select all branches
3. Reports automatically include all accessible branches via `_accessible_branches()`. **Source:** [`res_company.py:425-446`](../odoo/addons/base/models/res_company.py#L425-L446)

**P&L -- Batumi Office only:** Switch active company to "Batumi Office" -- the report filters to that branch's journal entries automatically.

### What the Balance Sheet Looks Like

**Balance Sheet -- Atlas Group (all branches, Jan 31, 2026)**

| Account | Amount |
|---|---|
| **Assets** | |
| 110000 Accounts Receivable | 42,000 |
| 120000 Bank (HQ) | 95,000 |
| 120001 Bank (Batumi) | 23,000 |
| 120002 Bank (Kutaisi) | 8,000 |
| 150000 Inventory | 65,000 |
| **Total Assets** | **233,000** |
| **Liabilities** | |
| 210000 Accounts Payable | 38,000 |
| 230000 Tax Payable | 12,000 |
| **Total Liabilities** | **50,000** |
| **Equity** | |
| 300000 Share Capital | 155,000 |
| 350000 Retained Earnings | 28,000 |
| **Total Equity** | **183,000** |

**Key:** ONE balance sheet, ONE set of equity accounts. Bank accounts are separate per branch (enforced by Odoo) but everything else consolidates naturally. No elimination entries needed.

### Tax Return

ONE tax return for the entire entity. All branch transactions roll up. The VAT is shared (or inherited from parent if branch has none).

**Source:** [`enterprise/account_reports/models/res_company.py:133-177`](../enterprise/account_reports/models/res_company.py#L133-L177) -- `_get_branches_with_same_vat()` collects all branches sharing the same VAT number.

### Pros and Cons

**Pros:**

| Advantage | Example |
|---|---|
| Simple setup -- create branch, done | Adding a new Zugdidi office: create branch, assign users, start invoicing. No CoA, no taxes. 5 minutes. |
| One CoA to maintain | Tax authority adds new account code? Update once. With multi-company and 10 entities, that's 10 updates. |
| One tax return, no intercompany invoicing | Tbilisi provides IT services to Batumi? Just a journal entry. No invoice, no bill, no reconciliation. |
| Reports auto-aggregate | Open P&L, select all branches -- combined result instantly. No consolidation module. |
| Shared fiscal year and lock dates | Accountant locks January for all locations in one action. |
| Low ongoing maintenance | One set of tax rates, one set of payment terms. VAT changes from 18% to 20%? One update. |

**Cons:**

| Disadvantage | Example |
|---|---|
| Cannot have different currencies | Batumi starts invoicing in USD -- impossible. Must restructure to multi-company. |
| Cannot have independent fiscal years | Acquired entity with March 31 year-end must switch to December 31. |
| All locations see the same accounts | Kutaisi accountant can accidentally post to HQ's consulting revenue account. |
| Lock dates cascade from root | Unlocking November for Kutaisi unlocks it for everyone. The effective lock date is the max across all ancestors. |
| Cannot do separate external audits | No standalone financials for one branch. The audit covers the entire legal entity. |
| Payroll requires separate runs per branch | Cannot combine all employees in one payslip run. |

**Best for:** Retail chains (same country/owner), regional sales offices, construction companies with project offices, any single legal entity wanting per-location P&L.

**Not for:** Different countries/currencies, locations that might become separate legal entities, need for strict data isolation between locations.

---

## Approach B: Multi-Company (Separate Legal Entities)

### What Is Multi-Company?

Each company is a fully independent legal entity with its own Chart of Accounts, its own journals, its own taxes, its own bank accounts, its own fiscal year, and its own lock dates. They happen to share one Odoo database.

**When Luka in Batumi Trading LLC creates an invoice, it says "Batumi Trading LLC" and is legally a Batumi Trading document. Atlas Group cannot see it unless they have cross-company access.**

### When Atlas Group Needs This Instead

Suppose Batumi is actually "Batumi Trading LLC" (VAT: GE987654321) and Kutaisi is "Kutaisi Logistics LLC" (VAT: GE111222333). Now you MUST use multi-company.

```
Atlas Holding (root)           <-- parent, may or may not have its own accounting
  |-- Batumi Trading LLC       <-- separate company, own CoA, own VAT
  |-- Kutaisi Logistics LLC    <-- separate company, own CoA, own VAT
```

Or 3 completely independent companies with no parent-child at all:
```
Atlas Group LLC          <-- company 1
Batumi Trading LLC       <-- company 2
Kutaisi Logistics LLC    <-- company 3
```

### Chart of Accounts: Separate per Company

Each company loads its own CoA template independently. They CAN use the same template (e.g., all install Georgian CoA) but the resulting account records are physically separate.

**Source:** [`chart_template.py:172-254`](../addons/account/models/chart_template.py#L172-L254) -- `_load()` creates accounts per company.

| | Atlas Group | Batumi Trading | Kutaisi Logistics |
|---|---|---|---|
| 110000 A/R | Record #101 | Record #201 | Record #301 |
| 400000 Revenue | Record #102 | Record #202 | Record #302 |

Even if codes are identical, these are separate `account.account` records. You maintain 3 copies.

**Can they have different CoA structures?** Yes. Atlas uses a 6-digit CoA while Batumi uses a 4-digit CoA. This is impossible with branches.

### What the P&L Looks Like

Each company sees ONLY its own numbers:

**P&L -- Batumi Trading LLC only (January 2026)**

| Account | Amount |
|---|---|
| 400000 Sales Revenue | 50,000 |
| 500000 COGS | (20,000) |
| 600000 Salaries | (12,000) |
| 620000 Rent | (3,000) |
| **Net Income** | **15,000** |

To see the combined picture, you need the consolidation toggle (see below).

### What the Balance Sheet Looks Like

Each company has its OWN balance sheet with its OWN equity:

**Balance Sheet -- Batumi Trading LLC (Jan 31, 2026)**

| Account | Amount |
|---|---|
| 110000 Accounts Receivable | 15,000 |
| 120000 Bank | 23,000 |
| 150000 Inventory | 18,000 |
| **Total Assets** | **56,000** |
| 210000 Accounts Payable | 11,000 |
| **Total Liabilities** | **11,000** |
| 300000 Share Capital | 30,000 |
| 350000 Retained Earnings | 15,000 |
| **Total Equity** | **45,000** |

**Key difference from branches:** Each company has its own equity. Investments between companies show as assets/liabilities (intercompany receivables/payables), not as shared equity.

### Inter-Company Transactions

When Atlas Group sells goods to Batumi Trading for 10,000:

**Without inter-company rules (manual):**
1. Atlas creates Sales Invoice to Batumi Trading: DR A/R 10,000 / CR Revenue 10,000
2. Someone manually creates Purchase Bill in Batumi Trading: DR COGS 10,000 / CR A/P 10,000
3. You do both manually -- error-prone, time-consuming

**With `account_inter_company_rules` (automatic):**
1. Atlas posts Sales Invoice to Batumi Trading
2. Odoo automatically creates matching Bill in Batumi Trading
3. The bill lands in Batumi's configured `intercompany_purchase_journal_id`

**Source:** [`enterprise/account_inter_company_rules/models/account_move.py:11-25`](../enterprise/account_inter_company_rules/models/account_move.py#L11-L25)

**Configuration per company:**

| Field | Purpose | Source |
|---|---|---|
| `intercompany_generate_bills_refund` | Enable auto-bill creation when invoiced by another company | [`res_company.py:7-28`](../enterprise/account_inter_company_rules/models/res_company.py#L7-L28) |
| `intercompany_document_state` | `'draft'` (review first) or `'posted'` (auto-post) | Same file |
| `intercompany_purchase_journal_id` | Which journal receives the auto-generated bills | Same file |
| `intercompany_user_id` | User context for creating the mirror document | Same file |

**Example journal entries for 10,000 intercompany sale:**

In **Atlas Group** books:
```
DR  110100  Intercompany A/R - Batumi    10,000
    CR  400000  Sales Revenue                        10,000
```

In **Batumi Trading** books (auto-generated):
```
DR  500000  COGS / Purchases             10,000
    CR  210100  Intercompany A/P - Atlas             10,000
```

### Consolidated P&L

To see the group-wide picture, use the consolidation feature in `account_reports`.

**How to generate:**
1. Accounting > Reporting > Profit & Loss
2. Select all 3 companies in the company filter
3. Enable the "Consolidation" toggle
4. Report groups by account code across companies

**Source:** [`enterprise/account_reports/models/account_report.py:1983-1990`](../enterprise/account_reports/models/account_report.py#L1983-L1990)

**Consolidated P&L -- simple (January 2026)**

| Account | Atlas | Batumi | Kutaisi | **Consolidated** |
|---|---|---|---|---|
| 400000 Revenue | 80,000 | 50,000 | 20,000 | **150,000** |
| 500000 COGS | (30,000) | (20,000) | (15,000) | **(65,000)** |
| 600000 Salaries | (25,000) | (12,000) | (8,000) | **(45,000)** |
| 620000 Rent | (5,000) | (3,000) | (4,000) | **(12,000)** |
| **Net Income** | **20,000** | **15,000** | **(7,000)** | **28,000** |

**WARNING:** This simple consolidation does NOT eliminate intercompany transactions. If Atlas sold 10,000 to Batumi, both Atlas revenue AND Batumi COGS are inflated. True consolidated P&L requires manual elimination entries:

**With elimination (what accountants actually need):**

| Account | Atlas | Batumi | Kutaisi | Elimination | **True Consolidated** |
|---|---|---|---|---|---|
| 400000 Revenue | 80,000 | 50,000 | 20,000 | (10,000) | **140,000** |
| 500000 COGS | (30,000) | (20,000) | (15,000) | 10,000 | **(55,000)** |
| **Net Income** | **20,000** | **15,000** | **(7,000)** | **0** | **28,000** |

Odoo's consolidation toggle is additive only (sum by account code). For IFRS-compliant elimination, you need manual consolidation journal entries.

### Tax Returns

Each company files its own tax return independently. Unless you set up a **Tax Unit** (group VAT filing) which groups companies sharing one VAT return.

**Source:** [`enterprise/account_reports/models/account_return.py:225-243`](../enterprise/account_reports/models/account_return.py#L225-L243)

### Pros and Cons

**Pros:**

| Advantage | Example |
|---|---|
| True legal separation | Batumi Trading LLC has its own VAT (GE987654321). If Batumi gets sued, Atlas Group's assets are protected. |
| Different currencies | Atlas operates in GEL, Batumi invoices in USD. Each has own functional currency. |
| Independent fiscal years | Atlas closes December 31. Acquired German subsidiary closes March 31. No forced alignment. |
| Independent lock dates | Atlas locked Q1 but Batumi still needs to fix a March entry. Batumi unlocks its own without affecting Atlas. |
| Independent audits | Each LLC hands its auditor a clean, standalone set of financials. |
| Different CoA structures | Atlas uses Georgian CoA, German subsidiary uses SKR04. They coexist. |
| Data isolation | Batumi's accountant cannot see or post to Atlas's accounts. |

**Cons:**

| Disadvantage | Example |
|---|---|
| Complex setup (CoA x N) | Adding a 4th entity: install CoA, configure 15+ journals, set up tax rates, create fiscal positions. Hours, not minutes. |
| Inter-company invoicing overhead | Atlas charges Batumi 5,000/month consulting. That's 12 invoices + 12 bills per year for one recurring charge. |
| Nx maintenance | Tax rate 18% -> 20%? Update in each company separately. Forget one = incorrect calculations. |
| Consolidation is extra work | "What's our total revenue?" requires selecting all companies, toggling consolidation. Still doesn't eliminate intercompany. |
| Users switch companies constantly | CFO reviewing 3 entities must switch active company repeatedly. Wrong company = posting in wrong entity. |
| Intercompany balances must reconcile at month-end | Atlas's "IC A/R from Batumi" must match Batumi's "IC A/P to Atlas" exactly. |

**Best for:** Multiple legal entities, different countries/currencies, holding+subsidiary structures, franchises, joint ventures.

**Not for:** All locations part of one legal entity (use branches), 10+ entities with limited staff, very frequent inter-entity transactions.

---

## Approach C: Analytic Accounts (Simplest, No Company Overhead)

### What Are Analytic Accounts?

Analytic accounts are tags on journal entry lines. They add reporting dimensions (location, department, project) without creating any company or branch structure. The accounting structure stays completely flat -- one company, one CoA, one set of journals.

**When Luka tags an invoice line with "Batumi Office" analytic, nothing changes about the journal entry itself. The analytic tag is just metadata for filtering reports later.**

### How It Works Technically

**Analytic Plans** define the dimensions you want to track. **Analytic Accounts** are the values within each plan.

```
Atlas Group LLC (single company, no branches)
  Analytic Plan: "Location"           <-- the dimension
    - Tbilisi HQ                      <-- an analytic account
    - Batumi Office                   <-- an analytic account
    - Kutaisi Warehouse               <-- an analytic account
  Analytic Plan: "Department"         <-- second dimension (optional)
    - Sales
    - Operations
    - Admin
```

**Key models:**

| Model | What it is | Company-scoped? | Source |
|---|---|---|---|
| `account.analytic.plan` | A reporting dimension (Location, Department, Project) | Applicability rules are company-dependent | [`analytic_plan.py:14`](../addons/analytic/models/analytic_plan.py#L14) |
| `account.analytic.account` | A value within a plan (e.g., "Batumi Office") | YES -- `company_id` required | [`analytic_account.py:61-65`](../addons/analytic/models/analytic_account.py#L61-L65) |
| `analytic_distribution` | JSON field on `account.move.line` storing the distribution | Stored as JSON dict | [`account_move_line.py:417-419`](../addons/account/models/account_move_line.py#L417-L419) |

**How distribution is stored:** The `analytic_distribution` field is a JSON dictionary. Keys are analytic account IDs (comma-separated if combined), values are percentages:

```python
# Example: 100% to Batumi Office (ID=5)
{"5": 100.0}

# Example: 60% Batumi, 40% Kutaisi
{"5": 60.0, "7": 40.0}

# Example: multi-plan -- Batumi Office + Sales Department
{"5,12": 100.0}  # 5 = Batumi (Location plan), 12 = Sales (Department plan)
```

**Example journal entry -- Batumi sale for 5,000:**
```
DR  110000  Accounts Receivable    5,000   [analytic_distribution: {"5": 100}]
    CR  400000  Sales Revenue              5,000   [analytic_distribution: {"5": 100}]
```

### Multiple Plans Simultaneously

You can have multiple analytic plans active at once. Each plan creates its own column on journal entry lines.

**Example:** Atlas Group wants to track by Location AND Department AND Project:

| Invoice Line | Amount | Location | Department | Project |
|---|---|---|---|---|
| Consulting for Client X | 5,000 | Batumi | Sales | Project Alpha |
| Warehouse supplies | 2,000 | Kutaisi | Operations | -- |
| Office rent | 3,000 | Tbilisi | Admin | -- |

This gives you multi-dimensional analysis: "Show me all Sales department costs in Batumi for Project Alpha" -- a single report filter.

**Source:** Plans support hierarchy via `parent_id` and `parent_store=True`. [`analytic_plan.py:30-37`](../addons/analytic/models/analytic_plan.py#L30-L37)

### Can You Force Users to Tag Entries? (Mandatory Analytics)

**YES.** Each plan has an `default_applicability` field with three options:

| Value | Meaning |
|---|---|
| `optional` | Users can skip the analytic tag |
| `mandatory` | Users MUST tag 100% of the amount. Posting fails otherwise. |
| `unavailable` | Plan doesn't appear on this document type |

**Source:** [`analytic_plan.py:78-87`](../addons/analytic/models/analytic_plan.py#L78-L87) -- `default_applicability` is `company_dependent=True`

Enforcement happens in `_validate_analytic_distribution()` on `account.move.line`. If a mandatory plan doesn't have 100% distribution, Odoo raises a `RedirectWarning` and blocks posting.

**Source:** [`account_move_line.py:3043-3074`](../addons/account/models/account_move_line.py#L3043-L3074)

**You can also set per-document-type rules** via `account.analytic.applicability` records. Example: Location is mandatory on customer invoices but optional on journal entries.

### What the P&L Looks Like

Same numbers as branches, but breakdown comes from analytic filter, not company filter:

**Analytic P&L -- by Location (January 2026)**

| Account | Tbilisi HQ | Batumi Office | Kutaisi WH | **Unallocated** | **Total** |
|---|---|---|---|---|---|
| 400000 Revenue | 80,000 | 50,000 | 20,000 | 0 | **150,000** |
| 500000 COGS | (30,000) | (20,000) | (15,000) | 0 | **(65,000)** |
| 600000 Salaries | (25,000) | (12,000) | (8,000) | 0 | **(45,000)** |
| 620000 Rent | (5,000) | (3,000) | (4,000) | 0 | **(12,000)** |
| **Net Income** | **20,000** | **15,000** | **(7,000)** | **0** | **28,000** |

**Critical gotcha:** If someone forgets the analytic tag, it falls into "Unallocated." With branches, every entry is automatically assigned to the user's branch. Set `default_applicability = 'mandatory'` to prevent this.

**Balance Sheet CANNOT split by location.** Analytic filtering only works on P&L (income/expense accounts). A/R, A/P, bank balances are always company-wide. You cannot produce a "Batumi Balance Sheet" with analytics.

### Pros and Cons

**Pros:**

| Advantage | Example |
|---|---|
| Simplest setup | Adding "Rustavi Office" = create one analytic account. 30 seconds. |
| One CoA, one set of journals | Accountant manages one chart, one tax config. Zero duplication. |
| Multi-dimensional analysis | Track by location AND department AND project simultaneously. "Batumi + Sales + Project Alpha" in one filter. |
| No company switching | Users never change active company. No "oops, wrong company." |
| Easy to add/remove | Close Kutaisi? Stop using that analytic account. No company to deactivate. |

**Cons:**

| Disadvantage | Example |
|---|---|
| Human error risk (forgetting tags) | 50 invoices without analytic = 50 entries in "Unallocated." Mitigate with `mandatory` applicability. |
| No access control per location | Kutaisi bookkeeper can see and edit Tbilisi entries. No restriction possible. |
| No separate invoice sequences | All invoices share one sequence: INV/2026/0001, 0002... No BAT/2026/0001. |
| No separate bank accounts per location | All banks belong to the single company. |
| No per-location lock dates | Lock January for everyone or no one. |
| Balance Sheet doesn't split | A/R, bank, equity are company-wide. Only P&L splits by analytic. |
| No legal standing | "Batumi Office" as analytic has no VAT, no legal identity. |

**Best for:** Department-level P&L, project costing (consulting firms, construction), small company with 2-3 locations sharing everything, temporary tracking (events, pop-ups).

**Not for:** Locations needing own bank accounts, invoice numbering, access control, Balance Sheet split, or any legal/regulatory independence.

---

## Side-by-Side: All 3 Approaches

### Setup Complexity

| Task | Analytic Only | Branches | Multi-Company |
|---|---|---|---|
| Create locations | Create analytic accounts | Create branch companies | Create full companies |
| CoA setup | 1 CoA | 1 CoA (shared) | 1 CoA per company |
| Journal setup | 1 set | 1 set per branch (auto) | 1 set per company (manual) |
| Tax setup | 1 set | 1 set (shared) | 1 set per company |
| Bank accounts | Shared | 1 per branch (required) | 1 per company |
| Access rights | Standard | Branch-aware | Company-aware |
| **Total effort** | **Minutes** | **Hours** | **Days** |

### Report Behavior

| Report | Analytic Only | Branches | Multi-Company |
|---|---|---|---|
| P&L per location | Analytic filter | Company filter | Switch company |
| P&L combined | Default view | Select all branches | Consolidation toggle |
| Balance Sheet per location | **Not possible** | Filter by branch | Switch company |
| Balance Sheet combined | Default view | Select all branches | Consolidation toggle |
| Tax return | 1 combined | 1 combined | 1 per company |
| Intercompany elimination | N/A | N/A | Manual entries needed |

### Scenario Decision Table

| Scenario | Recommended | Why |
|---|---|---|
| 3 stores, same country, same VAT | **Branches** | Shared CoA simplifies, per-store bank accounts |
| HQ + factory, same legal entity | **Branches** | Different journals per branch handle workflow separation |
| Parent + 2 subsidiaries, different VATs | **Multi-Company** | Legal separation required |
| Holding + subsidiaries, different countries | **Multi-Company** | Different currencies, fiscal years, tax rules |
| Single company, department cost tracking | **Analytic Only** | No company/branch overhead |
| Franchise (legally independent stores) | **Multi-Company** | Each franchise is its own legal entity |
| Department P&L, no balance sheet split | **Analytic Only** | Simplest possible |
| Regional offices with own bank accounts | **Branches** | Need separate bank accounts but shared CoA |
| All 3: legal entities with internal divisions + project tracking | **Multi-Company + Branches + Analytics (hybrid)** | Companies for legal, branches for offices, analytics for projects |

---

## Case Studies: Atlas Group Decisions

### Case 1: All Locations Are Departments (Same Legal Entity)

**Decision: Branches**

- One VAT: GE123456789
- One bank relationship (separate accounts per branch)
- One tax return
- Per-location P&L needed
- Year-end: one set of closing entries

Setup time: ~1 hour. Ongoing maintenance: minimal.

### Case 2: Batumi Is a Separate LLC, Kutaisi Is a Department

**Decision: Hybrid -- Multi-Company for Batumi + Branch for Kutaisi**

```
Atlas Group LLC (root)           <-- own CoA, VAT: GE123456789
  |-- Kutaisi Warehouse (branch) <-- shares Atlas CoA
Batumi Trading LLC               <-- own CoA, VAT: GE987654321
```

- Atlas + Kutaisi file one tax return
- Batumi files its own
- Intercompany rules handle Atlas <-> Batumi invoicing
- Kutaisi entries auto-roll into Atlas reports

### Case 3: All Three Are Separate LLCs + Project Tracking

**Decision: Multi-Company + Analytics**

```
Atlas Holding (parent, no operations)
  |-- Atlas Group LLC         <-- Analytic plans: Department, Project
  |-- Batumi Trading LLC      <-- Same analytic plans
  |-- Kutaisi Logistics LLC   <-- Same analytic plans
```

Each company is independent for accounting. Inside each company, analytic accounts track departments and projects. The CFO uses the consolidation toggle for group-wide views.

---

## Part 2: Cross-Module Impact

> How branches and multi-company affect Sales, Purchase, Inventory, Expenses, Payroll, and Analytic Reporting.

---

## Security Model: How Company Filtering Works

Every multi-company rule in Odoo uses one of these patterns:

| Pattern | Meaning | Used For |
|---|---|---|
| `('company_id', 'in', company_ids)` | User sees records ONLY in their assigned companies | Transactional data (SO, PO, invoices, pickings, payslips) |
| `('company_id', 'parent_of', company_ids)` | User sees records from their company AND all ancestors | Config data (journals, accounts, taxes, fiscal positions) |
| `('company_id', 'in', company_ids + [False])` | User sees company-scoped OR shared records | Master data (locations, routes, products) |

**Source:** [`account_security.xml:128-228`](../addons/account/security/account_security.xml#L128-L228)

**`company_ids`** is a context variable (not a field) automatically populated with the user's allowed companies. When the user switches companies in the top-right selector, `company_ids` changes and all record visibility re-evaluates instantly.

### Who Can See What?

| Scenario | Can See? | Why |
|---|---|---|
| Branch user sees parent's config (journals, taxes, CoA) | **YES** | `parent_of` rule on config records |
| Branch user sees parent's transactions (invoices, SOs) | **NO** | `in` rule -- parent not in branch user's `company_ids` by default |
| Branch user sees sibling branch's records | **NO** | Siblings don't have `parent_of` or `in` relationship |
| Parent user sees branch records | Only if assigned | User must have the branch in their `company_ids` |

**Source:** [`res_company.py:425-443`](../odoo/addons/base/models/res_company.py#L425-L443) -- `_accessible_branches()` method

### User Company Assignment

Each user has two fields:
- `company_id` -- current active company ("working as")
- `company_ids` -- all companies they're allowed to access

`self.env.company` returns the active `company_id`. The company switcher changes which companies are active. All `ir.rule` filters re-evaluate instantly.

---

## Sales Module

### Company Scoping

| Aspect | Behavior | Source |
|---|---|---|
| SO `company_id` default | `self.env.company` (user's active company) | [`sale_order.py:60-63`](../addons/sale/models/sale_order.py#L60-L63) |
| Changeable? | Yes in draft, locked after confirmation | Same |
| Warehouse must match company | Enforced | [`sale_stock/models/sale_order.py:74-77`](../addons/sale_stock/models/sale_order.py#L74-L77) |

**Branch behavior:** When Luka (Batumi salesman) creates an SO:
1. SO gets `company_id = Batumi Office`
2. Warehouse auto-selects Batumi WH
3. Invoice from SO inherits `company_id = Batumi Office`
4. Delivery picking inherits company from warehouse's picking type

**Who sees Luka's SO:**
- Batumi users: YES
- Tbilisi HQ users: Only if Batumi is in their `company_ids`
- Kutaisi users: NO (sibling branch)

### Inter-Company SO/PO Flow

When SO in Company A is confirmed for a partner that IS Company B:

```
1. SO confirmed in Company A (customer = Company B's partner)
2. If Company B has intercompany_generate_purchase_orders = True:
   -> Auto-creates PO in Company B (vendor = Company A's partner)
   -> auto_generated = True prevents infinite loop
```

**Source:** [`enterprise/sale_purchase_inter_company_rules/models/sale_order.py:11-21`](../enterprise/sale_purchase_inter_company_rules/models/sale_order.py#L11-L21)

Reverse works too: PO in Company B can auto-create SO in Company A.

### Practical Issues

| Issue | Branches | Multi-Company |
|---|---|---|
| Salesman in A sells to customer in B's territory | Works fine -- customer is shared | Works fine -- separate SO in A |
| Shared pricelist | Works -- pricelists can be company-agnostic | Each company needs own pricelist |
| SO needs stock from different location | Internal transfer (simple) | Inter-company PO/SO chain (complex) |

---

## Purchase Module

### Company Scoping

| Aspect | Behavior | Source |
|---|---|---|
| PO `company_id` default | `self.env.company` | [`purchase_order.py:160`](../addons/purchase/models/purchase_order.py#L160) |
| Vendor bill from PO | Bill created with `company_id = PO.company_id` | [`purchase_order.py:941`](../addons/purchase/models/purchase_order.py#L941) |

### Practical Issues

| Issue | Branches | Multi-Company |
|---|---|---|
| Central purchasing for all locations | PO in HQ, goods to branch warehouse | PO in Company A, inter-company transfer to B |
| Vendors shared? | Yes -- vendors not company-scoped | Yes -- same partner across companies |
| Different payment terms per location | Not possible -- inherited from parent | Each company has its own |

---

## Inventory / Stock Module

### Company Scoping -- Strictest Module

Inventory is the most strictly company-scoped module. Key rules:

| Model | Shared Allowed? | Source |
|---|---|---|
| `stock.warehouse` | NO -- one per company, required | [`stock_warehouse.py:37-40`](../addons/stock/models/stock_warehouse.py#L37-L40) |
| `stock.picking` | NO -- company from picking type | [`stock_picking.py:634-636`](../addons/stock/models/stock_picking.py#L634-L636) |
| `stock.move` | NO | [`stock_security.xml:108-112`](../addons/stock/security/stock_security.xml#L108-L112) |
| `stock.quant` | Via location (company-scoped) | [`stock_quant.py:56`](../addons/stock/models/stock_quant.py#L56) |
| `stock.location` | YES (`company_id` can be NULL) | [`stock_location.py:60-63`](../addons/stock/models/stock_location.py#L60-L63) |

**Warehouse:** Each branch MUST have its own warehouse. Cannot share. Name and code must be unique per company.

**Quant company:** `company_id` is a related field from `location_id.company_id`. One company cannot see another's inventory.

**Picking company chain:** `Warehouse -> Picking Type -> Picking` -- unbreakable.

### Atlas Group with Branches -- Inventory

```
Atlas Group (root)
  |-- Warehouse: "Tbilisi Central" (company: Atlas Group)
  |-- Batumi Office (branch)
       |-- Warehouse: "Batumi WH" (company: Batumi Office)
  |-- Kutaisi Warehouse (branch)
       |-- Warehouse: "Kutaisi WH" (company: Kutaisi Warehouse)
```

- Internal transfer Kutaisi -> Batumi = simple internal transfer (same root company)
- Total inventory view: user with access to all branches sees all warehouses
- Each branch has own picking types and sequences

### Practical Issues

| Issue | Branches | Multi-Company |
|---|---|---|
| Transfer between locations | Internal transfer (simple) | Inter-company transfer (requires Enterprise module + PO/SO chain) |
| Central inventory visibility | Select all branches in filter | Must switch between companies |
| SO in branch A, stock in branch B | Create internal transfer B -> A first | Requires inter-company PO from A to B |

### Inter-Company Stock Transfers (Multi-Company Only)

Requires `sale_purchase_stock_inter_company_rules` (Enterprise).

| Field | Purpose | Source |
|---|---|---|
| `intercompany_warehouse_id` | Default warehouse for incoming transfers | [`enterprise/sale_purchase_stock_inter_company_rules/models/res_company.py:8-14`](../enterprise/sale_purchase_stock_inter_company_rules/models/res_company.py#L8-L14) |
| `intercompany_receipt_type_id` | Receipt operation type in target company | Same file |

---

## HR Expenses

### Company Scoping

| Aspect | Behavior | Source |
|---|---|---|
| `company_id` default | `self.env.company` (user's active company at creation) | [`hr_expense.py:86-92`](../addons/hr_expense/models/hr_expense.py#L86-L92) |
| `company_id` readonly | YES -- locked after creation | Same, line 90 |
| `_check_company_auto` | YES | [`hr_expense.py:46`](../addons/hr_expense/models/hr_expense.py#L46) |

### How Expense Approval Works Across Branches

Approval rules check employee relationships (department manager, expense manager, subordinates) but do NOT explicitly filter by company. The global `company_ids` rule acts as the backstop.

**This means:** A manager in Tbilisi CAN approve expenses from Batumi employees IF:
1. The manager has Batumi in their `company_ids` AND
2. The employee relationship allows it (department manager, expense manager)

**Source:** [`ir_rule.xml:13-23`](../addons/hr_expense/security/ir_rule.xml#L13-L23)

### Expense to Journal Entry Flow

1. Expenses grouped by `company_id`
2. Journal selected from `company.expense_journal_id` or first purchase journal in that company
3. Journal entry created in the expense's company
4. Analytic distribution from expense line carries through to the journal entry

**Source:** [`hr_expense.py:1536-1553`](../addons/hr_expense/models/hr_expense.py#L1536-L1553)

**Key:** Journal entry always goes to the expense's company (set at creation, readonly). Employee traveling to another branch still gets the expense in their home branch.

### Practical Example

**Scenario:** Luka (Batumi) travels to Tbilisi for a meeting, spends 500 GEL on hotel.

| Approach | What Happens |
|---|---|
| **Branches** | Luka's active company = Batumi at expense creation time. Expense `company_id = Batumi Office`. Journal entry posts to Batumi's expense journal. Batumi P&L shows the 500 cost. Nino (CFO) with all-branch access can approve. |
| **Multi-Company** | Same -- expense in Batumi Trading LLC. Journal entry in Batumi. But Nino must have Batumi Trading in her `company_ids` to see and approve it. |
| **Analytic** | Expense in the single company. Luka tags it "Batumi Office" analytic. No company switching needed. Any manager can approve (no company barrier). |

### Practical Issues

| Issue | Branches | Multi-Company | Analytic |
|---|---|---|---|
| Employee travels to another location | Expense stays in employee's branch | Expense stays in employee's company | Tag with destination analytic |
| Cross-location approval | Works if manager has access to employee's branch | Works if manager has access to employee's company | No barrier -- single company |
| Expense report for all locations | Manager with all-branch access sees all | Must switch between companies | Single report, filter by analytic |
| Employee transfers to new branch | New expenses in new branch; old stay in old | Same | Just change analytic tag |

---

## HR Payroll

### Company Scoping -- Strictly Per Company

| Aspect | Behavior | Source |
|---|---|---|
| Payslip `company_id` | **Computed from `employee_id.company_id`** -- not user's active company | [`hr_payslip.py:92-95`](../enterprise/hr_payroll/models/hr_payslip.py#L92-L95) |
| Payslip Run `company_id` | `self.env.company` (one run per company/branch) | [`hr_payslip_run.py:58-59`](../enterprise/hr_payroll/models/hr_payslip_run.py#L58-L59) |
| Employee belongs to one company | YES -- enforced by constraint | [`hr_employee.py:247-248`](../addons/hr/models/hr_employee.py#L247-L248) |

### Salary Structures: Shared by Country, Not Company

Structures are scoped by **country**, not company. All companies in the same country share structures.

**Source:** [`hr_payroll_structure.py:44-51`](../enterprise/hr_payroll/models/hr_payroll_structure.py#L44-L51)

**This means:** Whether you use branches or multi-company, if all entities are in Georgia, they share the same salary structures. The difference is only in how payslip runs and journal entries are organized.

### Contracts: Tied to Employee's Company

Contract `company_id` is computed from `employee_id.company_id`. Cannot be overridden.

**Source:** [`hr_version.py:196-200`](../addons/hr/models/hr_version.py#L196-L200)

### Practical Example

**Atlas Group with Branches -- Payroll January 2026:**

```
Branch: Tbilisi HQ      -> 15 employees -> Payslip Run "January 2026 - Tbilisi"
Branch: Batumi Office    ->  8 employees -> Payslip Run "January 2026 - Batumi"
Branch: Kutaisi WH       ->  5 employees -> Payslip Run "January 2026 - Kutaisi"
```

- **3 separate payslip runs** -- one per branch, even though they share CoA
- All salary structures shared (same country = Georgia)
- Journal entries post to each branch's journals (Batumi payslip -> Batumi salary journal)
- HR manager with all-branch access can view all payslips
- **Cannot combine into one payslip run.** This is a hard limitation.

### Payroll with Multi-Company

Exactly the same behavior -- one payslip run per company. The only difference: structures would also be shared if companies are in the same country. If companies are in different countries, each uses its country's structures.

### Practical Issues

| Issue | Branches | Multi-Company | Analytic |
|---|---|---|---|
| Run payroll for all locations at once | NO -- one run per branch | NO -- one run per company | YES -- single company, one run for all |
| Employee in two locations | One company only -- must choose primary | Same | Single company -- use analytic tags |
| Different pay scales per location | Salary rules with branch-specific conditions | Each company can have different rule parameters | Not supported by analytics alone |
| Payroll journal entries | Each branch's salary journal | Each company's salary journal | Single salary journal |
| Payroll report across all locations | Multi-branch access sees all | Must switch companies | Single report |

---

## Analytic Accounting: How It Works With Branches and Multi-Company

### Analytics Are Orthogonal to Company Structure

Analytic accounts work the SAME way regardless of whether you use branches, multi-company, or no branches at all. They add reporting dimensions on top of whatever company structure you choose.

**Example combinations:**
- Branches + Analytics: Track by branch (company filter) AND by department (analytic filter)
- Multi-Company + Analytics: Track by legal entity (company) AND by project (analytic)
- Just Analytics: Track everything by analytic plans only

### What Reports Can Filter By Analytic

| Report | Analytic Filter Available? | Source |
|---|---|---|
| P&L | YES -- via analytic groupby/filter | [`enterprise/account_reports/models/account_analytic_report.py:12-15`](../enterprise/account_reports/models/account_analytic_report.py#L12-L15) |
| Balance Sheet | Partial -- only for P&L-type accounts | Same |
| General Ledger | YES | Same |
| Trial Balance | YES | Same |

**How report filtering works:** When `options['analytic_accounts']` is set, the report adds filters on `account.move.line.analytic_distribution`. With groupby enabled, it creates a shadowing query that projects `account.analytic.line` data into move line schema.

**Source:** [`enterprise/account_reports/models/account_analytic_report.py:99-165`](../enterprise/account_reports/models/account_analytic_report.py#L99-L165)

### Analytics + Branches: Best of Both Worlds

Use branches for operational isolation (bank accounts, invoice sequences, access control) and analytics for additional dimensions:

```
Atlas Group (root)
  |-- Batumi Office (branch)      <-- company-level isolation
  |-- Kutaisi Warehouse (branch)  <-- company-level isolation

Analytic Plans (cross-cutting):
  Department: Sales, Operations, Admin, Finance
  Project: Project Alpha, Project Beta, Client X
```

This gives you:
- P&L by branch (company filter)
- P&L by department (analytic filter)
- P&L by branch + department (both filters)
- Separate bank accounts per branch
- Separate invoice sequences per branch
- Access control per branch
- Multi-dimensional project cost tracking via analytics

---

## Cross-Module Summary: How Company Is Determined

| Module | `company_id` Source | Readonly? | Source |
|---|---|---|---|
| Sale Order | `self.env.company` (user's active company) | No (draft) | [`sale_order.py:60`](../addons/sale/models/sale_order.py#L60) |
| Purchase Order | `self.env.company` | No (draft) | [`purchase_order.py:160`](../addons/purchase/models/purchase_order.py#L160) |
| Invoice | Computed from `journal_id.company_id` | No (editable but recomputed) | [`account_move.py:875`](../addons/account/models/account_move.py#L875) |
| Stock Picking | Related from `picking_type_id.company_id` | YES | [`stock_picking.py:634`](../addons/stock/models/stock_picking.py#L634) |
| Expense | `self.env.company` | YES | [`hr_expense.py:86`](../addons/hr_expense/models/hr_expense.py#L86) |
| Payslip | Computed from `employee_id.company_id` | YES | [`hr_payslip.py:92`](../enterprise/hr_payroll/models/hr_payslip.py#L92) |

### What Branches Share vs Isolate

| Resource | Branches | Multi-Company |
|---|---|---|
| Chart of Accounts | **SHARED** (one CoA, `company_ids` Many2many) | **SEPARATE** per company |
| Journals | **SHARED access** (`parent_of`), but each branch has own set | **SEPARATE** per company |
| Tax rates | **SHARED** (`parent_of`) | **SEPARATE** per company |
| Fiscal positions | **SHARED** (`parent_of`) | **SEPARATE** per company |
| Products | **SHARED** (`company_id` can be False) | **SHARED** (`company_id` can be False) |
| Customers/Partners | **SHARED** (not company-scoped) | **SHARED** (not company-scoped) |
| Employees | **ISOLATED** per branch | **ISOLATED** per company |
| Warehouses | **ISOLATED** per branch | **ISOLATED** per company |
| Inventory (quants) | **ISOLATED** per branch warehouse | **ISOLATED** per company |
| Sale/Purchase Orders | **ISOLATED** per branch | **ISOLATED** per company |
| Invoices | **ISOLATED** per branch | **ISOLATED** per company |
| Expenses | **ISOLATED** per branch | **ISOLATED** per company |
| Payslips | **ISOLATED** per branch | **ISOLATED** per company |
| Salary Structures | **SHARED** (by country) | **SHARED** (by country) |
| Lock Dates | Inherited from root (max of ancestors) | **INDEPENDENT** per company |
| Fiscal Year | **SHARED** from root (delegated) | **INDEPENDENT** per company |

---

## Common Pitfalls & How to Fix Them

### 1. "User Posted in Wrong Company"

**Symptom:** User forgets to switch active company before creating records.

| Approach | Risk | Mitigation |
|---|---|---|
| Branches | MEDIUM -- user sees all branches in switcher | Train users to check active company. `_check_company_auto` catches mismatches. |
| Multi-Company | HIGH -- completely wrong legal entity | Same training. Consider per-user default company. |
| Analytic | LOW -- single company | No company switching needed. |

### 2. "Manager Can't Approve Employee's Expense"

**Root cause:** Manager does not have the employee's branch in their `company_ids`.

**Fix:** Add the employee's branch to the manager's allowed companies. Expense approval checks employee relationships but the global `company_ids` filter blocks access first.

### 3. "Payroll Run Doesn't Include All Employees"

**Root cause:** Payslip runs are per-company. Each branch needs its own run.

**Fix:** Create separate payslip runs per branch. Cannot combine. This is by design.

### 4. "SO Confirmed but No Delivery Created"

**Root cause:** Warehouse doesn't match SO's company, or warehouse not configured for that branch.

**Fix:** Each branch needs a warehouse. SO auto-picks warehouse matching `company_id`.

### 5. "Inter-Company Transfer Creates Nothing"

**Root cause:** Missing module or configuration:
- `sale_purchase_stock_inter_company_rules` not installed
- `intercompany_generate_purchase_orders` not enabled on target company
- `intercompany_user_id` not set
- `intercompany_warehouse_id` not set

### 6. "Branch User Sees Parent's Journals but Not Parent's Invoices"

**This is by design.** Journals use `parent_of` (config = shared). Invoices use `in company_ids` (transactions = isolated). Branch user can POST to a parent journal (creating an entry in the branch) but CANNOT READ the parent's existing entries unless parent is in their `company_ids`.

### 7. "Employee Transferred Between Branches -- Old Records Invisible"

**Root cause:** Employee gets new `company_id`. Old records stay in old branch. New branch users can't see old branch data.

**Fix:** User needs both companies in `company_ids` to see full history. Or: HR manager with all-company access views complete records.

---

## Permissions Matrix: Atlas Group Example

### Users and Access

| User | Role | `company_ids` | Active Company |
|---|---|---|---|
| Nino (CFO) | Finance Manager | Atlas + Batumi + Kutaisi | Atlas Group |
| Giorgi | Batumi Sales Manager | Atlas + Batumi | Batumi Office |
| Tamta | Kutaisi Warehouse Mgr | Atlas + Kutaisi | Kutaisi WH |
| Luka | Batumi Salesman | Batumi only | Batumi Office |
| Ana | Kutaisi Stock Clerk | Kutaisi only | Kutaisi WH |

### What Each User Sees (Branches Setup)

| Record | Nino (CFO) | Giorgi (Batumi Mgr) | Luka (Batumi Sales) | Ana (Kutaisi Stock) |
|---|---|---|---|---|
| Tbilisi SOs | YES | YES (Atlas in companies) | NO | NO |
| Batumi SOs | YES | YES | YES (own) | NO |
| Kutaisi SOs | YES | NO | NO | NO |
| Batumi inventory | YES | YES | NO | NO |
| Kutaisi inventory | YES | NO | NO | YES |
| Journals/CoA/Taxes (config) | ALL | ALL (parent_of) | ALL (parent_of) | ALL (parent_of) |

**Key observations:**
1. Config (journals, accounts, taxes) is ALWAYS visible via `parent_of` -- every branch user sees the root's config
2. Transactions (SOs, invoices, pickings) are ISOLATED via `in company_ids` -- only visible if user has that company
3. Luka with ONLY Batumi is fully isolated from Kutaisi and HQ transactions
4. Nino with ALL 3 companies sees everything

---

## End-to-End Flow: Sale to Payment

### Branch Flow (Batumi is a branch)

```
1. Luka creates SO in Batumi
   -> company_id = Batumi Office (auto from active company)
   -> warehouse = Batumi WH (auto from company)

2. SO confirmed
   -> Delivery created: company_id = Batumi (from picking type)
   -> Stock reserved in Batumi WH

3. Delivery validated
   -> Stock moves in Batumi company
   -> Quants updated in Batumi WH

4. Invoice created from SO
   -> company_id = Batumi (from SO)
   -> Journal: Batumi's sales journal
   -> Sequence: INV/2026/0001 (Batumi's own counter)

5. Payment received
   -> Batumi's bank journal
   -> Reconciled against Batumi AR

6. Reporting
   -> Nino opens P&L, selects all branches -> sees combined
   -> Filters Batumi only -> sees Batumi P&L
   -> Same CoA, same account codes, no consolidation needed
```

### Multi-Company Flow (Batumi Trading LLC is separate)

```
1. Luka creates SO in Batumi Trading LLC
   -> company_id = Batumi Trading LLC
   -> warehouse = Batumi WH

2. SO confirmed
   -> IF customer IS Atlas Group: auto-creates PO in Atlas Group (inter-company)
   -> Delivery in Batumi Trading

3. Delivery validated
   -> IF inter-company: syncs receipt in Atlas Group

4. Invoice created
   -> company_id = Batumi Trading LLC
   -> Separate CoA, separate journal, separate sequence
   -> IF customer IS Atlas Group: auto-creates vendor bill in Atlas Group

5. Payment received
   -> Batumi Trading's bank journal, Batumi's own AR

6. Reporting
   -> Nino must use consolidation toggle for combined view
   -> Inter-company transactions inflate totals without elimination
   -> Manual elimination entries needed for true consolidated view
```

---

## FAQ

**Q: Can I switch from branches to multi-company later?**
A: Technically possible but painful. You'd need to create new companies, migrate journal entries, reassign all documents. Plan this decision carefully upfront.

**Q: Can I switch from multi-company to branches?**
A: Even harder. Separate CoAs must be merged, intercompany balances reconciled and eliminated. Avoid this scenario.

**Q: Can branches have different currencies?**
A: No. `currency_id` is a root-delegated field. Branches must use the root company's currency. Need different currencies = use multi-company.

**Q: Can I mix branches AND multi-company AND analytics?**
A: Yes. Common pattern: separate legal entities as companies, branches inside each company for locations, analytics for projects/departments. All three work together.

**Q: Can I make analytic tagging mandatory to prevent "Unallocated" entries?**
A: Yes. Set `default_applicability = 'mandatory'` on the analytic plan. Odoo will block posting any entry that doesn't have 100% distribution for that plan.

**Q: Are payslip runs always per-company, even with branches?**
A: Yes. Each branch needs its own payslip run. This is a hard limitation. With analytics (no branches), you'd have one run for all employees.

**Q: How do lock dates work with branches?**
A: The effective lock date for a branch is the **maximum** across itself and all ancestor companies. Root sets lock date = all branches inherit. Branches CAN set their own (stricter) but cannot be less strict than the root.

**Q: What modules do I need?**

| Need | Module | License |
|---|---|---|
| Branches | `account` (built-in) | Community |
| Multi-company | `account` + company setup | Community |
| Inter-company invoicing | `account_inter_company_rules` | Enterprise |
| Inter-company SO/PO | `sale_purchase_inter_company_rules` | Enterprise |
| Inter-company stock transfers | `sale_purchase_stock_inter_company_rules` | Enterprise |
| Report consolidation | `account_reports` | Enterprise |
| Tax units (group VAT) | `account_reports` | Enterprise |
| Analytic accounting | `analytic` + `account` | Community |

---

## One-Line Summary

| Situation | Use |
|---|---|
| One legal entity, multiple locations | **Branches** |
| Multiple legal entities, same group | **Multi-Company + Inter-company Rules** |
| Just need cost center / project tracking | **Analytic Accounts** |
| Legal entities + internal divisions + project tracking | **Multi-Company + Branches + Analytics** |

---

## Related Docs

- [`INDEX.md`](INDEX.md)

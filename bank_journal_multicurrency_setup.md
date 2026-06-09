# Bank Journal Setup — Multi-Currency Accounts at the Same Bank

> **Topic:** Creating bank journals correctly when one physical bank holds multiple accounts in different currencies.
> **Related modules:** `account`, `account_accountant`, `account_online_synchronization`
> **Related doc:** [`currency_exchange_transit.md`](currency_exchange_transit.md)

---

## The Goal

You have **one physical bank** (e.g., Bank of Georgia) where you hold multiple accounts in different currencies (GEL, USD, EUR). You want:

- **1** `res.bank` record for the institution
- **N** `res.partner.bank` records (one per IBAN, one per currency)
- **N** `account.journal` records (one per currency)

End state:

```
res.bank: "Bank of Georgia" (BIC: BAGAGE22)
   │
   ├── IBAN GE...001  ──── Journal "BoG GEL" (currency: GEL)
   ├── IBAN GE...002  ──── Journal "BoG USD" (currency: USD)
   └── IBAN GE...003  ──── Journal "BoG EUR" (currency: EUR)
```

---

## Why a Journal per Currency

A `account.journal` has a `currency_id` field. If set, every move in that journal is denominated in that currency. **A bank journal cannot mix currencies.** So one IBAN → one currency → one journal.

This is also required for internal transfers between currencies — see [`currency_exchange_transit.md`](currency_exchange_transit.md) for the Liquidity Transfer account mechanics.

---

## Q&A — Discoveries from a Real Setup Session

### Q1: I have a bank with 3 accounts (GEL/USD/EUR). How do transfers work between them?

Odoo uses a **transit account** (called "Liquidity Transfer", account code `101701`) as an intermediary. A single journal entry can only belong to ONE journal — so to move money from GEL Bank to USD Bank, Odoo creates two journal entries, both touching the transit account:

```
GEL Bank  ──────►  Liquidity Transfer  ──────►  USD Bank
  (Journal 1)         (the middleman)            (Journal 2)
```

After both posts, transit account nets to zero. If dates differ and the exchange rate changed, Odoo auto-creates an exchange gain/loss entry.

Full mechanics: [`currency_exchange_transit.md`](currency_exchange_transit.md) sections "Real-World Example 2" and "Exchange Gain/Loss Deep Dive".

---

### Q2: Should I create 3 banks (3 journals)?

Yes — **3 journals**, but **1 institution**. The structure is layered:

| Layer | Odoo model | How many | Purpose |
|---|---|---|---|
| Institution | `res.bank` | **1** | The physical bank ("Bank of Georgia") |
| Account number | `res.partner.bank` | **3** | The IBANs (GE...001, ...002, ...003) |
| Journal | `account.journal` | **3** | Where transactions are recorded, one per currency |
| GL account | `account.account` | **3** | Auto-created per journal (e.g., 1011, 1012, 1013) |

The `res.bank` is just the institution's "identity card" — name, BIC, address. It's shared by all IBANs at that bank.

---

### Q3: When I click `New → Bank` it creates a new `res.bank` every time. Is that correct?

**No — that's the bug in your workflow.** The `res.bank` (institution) should be created **once**, then reused.

There are two different dialogs in Odoo, and they behave differently:

#### Dialog A — Manual journal wizard (correct for our case)

**Path:** Dashboard → `New` button (top-left) → click **Bank** card

This opens [`account.setup.bank.manual.config`](../addons/account/wizard/setup_wizards.py#L93). The view is [`setup_bank_account_wizard`](../addons/account/wizard/setup_wizards_view.xml#L34-L58):

| Field | Behavior |
|---|---|
| `acc_number` | Type the IBAN |
| `bank_id` | **Many2one dropdown** — autocomplete searches existing `res.bank` records. Pick existing or click "Create" |
| `bank_bic` | Auto-fills from selected bank |

The `bank_id` field has no domain filter — it shows ALL existing `res.bank` records. You can SELECT existing.

#### Dialog B — Online bank sync dialog (the trap)

**Path:** Dashboard → **Bank tile** (with Chase / BoA / Wells Fargo logos) → "Search 26,000 banks"

This opens an OWL widget that queries an **external service** (`odoofin.com`) at `/proxy/v2/get_dashboard_institutions` ([`account_journal.py:80`](../enterprise/account_online_synchronization/models/account_journal.py#L80)). It searches Odoo's catalog of supported banks for API auto-sync — **not your local `res.bank` table**.

When you search "Bank of Georgia" and the bank isn't in the catalog, you get a `+ Add BANK OF GEORGIA` fallback button. That button calls [`create_new_bank_account_action`](../enterprise/account_online_synchronization/models/account_online.py#L417):

```python
# enterprise/account_online_synchronization/models/account_online.py:446
if data.get('name'):
    bank = self.env['res.bank'].sudo().create({
        'name': data['name'],
        'bic': data.get('swift_code'),
    })
```

**This code ALWAYS creates a new `res.bank` — it never searches for an existing one.** Every time you use this dialog, you get a duplicate.

---

### Q4: Why don't I see my existing "BOG" bank when I search "BOG"?

Two possible reasons:

1. **You're searching in Dialog B (online sync)** — that searches OdooFin's external catalog (~26k mostly US banks), not your local `res.bank`. Georgian banks won't appear there.

2. **In Dialog A's Bank dropdown**, the display name format is `name + " - " + bic` ([`res_bank.py:35-38`](../odoo/addons/base/models/res_bank.py#L35-L38)):

   ```python
   name = (bank.name or '') + (bank.bic and (' - ' + bank.bic) or '')
   ```

   So a bank named `"BOG"` with `bic="GEBA"` appears in the dropdown as **"BOG - GEBA"**. If you're scanning for exactly "BOG", you may miss it.

---

## What Was Wrong in the Real Setup

Before fixing: the workflow had created duplicate institution records.

| `res.bank` id | name | bic |
|---|---|---|
| 6 | BANK OF GEORGIA | GE |
| 7 | BANK OF GEORGIA | GE | ← duplicate |

| `res.partner.bank` id | acc_number | bank_id (→ res.bank) |
|---|---|---|
| 4 | 100 | 6 |
| 5 | 101 | 7 ← points to duplicate |

| `account.journal` | linked IBAN | currency |
|---|---|---|
| 100 (BNK5) | id=4 | NULL ← should be GEL or USD |
| 101 (BNK6) | id=5 | NULL ← should be the other currency |

**Two issues:**

1. Two `res.bank` records exist for what should be ONE bank. Each journal got its own duplicate because the user was using **Dialog B** and clicking `+ Add BANK OF GEORGIA` every time — and that code path doesn't dedupe.
2. The journals have no currency set. Without a currency, both operate in company currency (GEL). Multi-currency separation doesn't work.

---

## The Correct Workflow (Going Forward)

### Once per bank: create the `res.bank`

**Path:** Contacts app → **Configuration** → **Bank Accounts** → **Banks** → **New**

| Field | Value |
|---|---|
| Name | Bank of Georgia |
| BIC | BAGAGE22 (the real SWIFT code) |
| Country | Georgia |

Save. Do this **only once** per physical bank.

### Per account: create the journal

**Path A (preferred):** Dashboard → top-left **`New`** button → click **Bank** card

In the wizard ([`account.setup.bank.manual.config`](../addons/account/wizard/setup_wizards.py#L93)):

| Field | What to do |
|---|---|
| Account Number | Type the IBAN |
| **Bank** | Click dropdown → start typing → **select the existing record** from the suggestion list |
| BIC | Auto-fills |

**Critical:** in the Bank dropdown, do NOT click the `+ Create "Bank of Georgia"` option at the bottom — that creates a new `res.bank`. Always pick the existing one from the suggestions.

**Path B (also works):** Top menu **Accounting** → **Configuration** → **Journals** → **New**

Opens the journal form directly. Set Type = Bank, Currency = USD/EUR/GEL, then fill the Bank Account field (the bank sub-record picker works the same way).

### Set the journal's currency

**Path:** Accounting → Configuration → Journals → open the journal

| Field | Set to |
|---|---|
| Currency | The currency of this account (USD, EUR, GEL, etc.) |

Save. **Do this before posting any transactions** — once entries exist on the journal, currency can no longer be changed.

---

## The Decision Tree

```
Adding a new bank account at a bank you already have?
   │
   ├── Dashboard → "New" button (top-left)  ← CORRECT
   │        └── "Bank" card in journal-type wizard
   │              └── Wizard with Account Number + Bank dropdown
   │                    └── PICK EXISTING bank from dropdown (don't "+ Create")
   │
   ├── Accounting → Configuration → Journals → "New"  ← ALSO CORRECT
   │        └── Journal form opens directly
   │              └── Set Currency, then fill Bank Account → pick existing bank
   │
   └── Dashboard → "Bank" TILE (with Chase / BoA logos)  ← WRONG
            └── "Search 26,000 banks" or "+ Add XYZ" button
                  └── Always creates a NEW res.bank → duplicates every time
```

---

## How to Fix Existing Duplicates

If you already have duplicate `res.bank` records (like the example above):

### Step 1 — Pick the "keeper"

Contacts → Configuration → Bank Accounts → Banks. Open the one to keep. Fix its BIC and country if wrong.

### Step 2 — Reassign IBANs from the duplicate

Contacts → Configuration → Bank Accounts → **Bank Accounts** (the sub-menu). Open each IBAN currently pointing to the duplicate `res.bank` → change its **Bank** field to the keeper.

### Step 3 — Archive the duplicate

Banks list → open the now-orphaned `res.bank` → **Actions** menu → **Archive**.

### Step 4 — Set currency on each journal

Accounting → Configuration → Journals → open each bank journal → set **Currency**. Do this before posting transactions.

---

## Key Sources

### Manual wizard (the correct path)

- [`account.setup.bank.manual.config`](../addons/account/wizard/setup_wizards.py#L93) — wizard model, inherits `res.partner.bank`
- [`setup_bank_account_wizard`](../addons/account/wizard/setup_wizards_view.xml#L34-L58) — the form view with `acc_number` / `bank_id` / `bank_bic`
- [`setting_init_bank_account_action`](../addons/account/models/company.py#L764-L776) — action triggered by `New → Bank` card
- [`set_bank_account()`](../addons/account/models/account_journal.py#L1045-L1061) — links the IBAN to the journal

### Online sync dialog (the trap)

- [`BankConfigureWidget`](../enterprise/account_online_synchronization/static/src/components/bank_configure/bank_configure.js) — the OWL widget on the Bank dashboard tile
- [`fetch_online_sync_favorite_institutions`](../enterprise/account_online_synchronization/models/account_journal.py#L80) — fetches the catalog from `odoofin.com`
- [`create_new_bank_account_action`](../enterprise/account_online_synchronization/models/account_online.py#L417) — the "+ Add XYZ" handler; line 446 is the unconditional `res.bank` create that causes duplicates

### Bank display name format

- [`res.bank._compute_display_name`](../odoo/addons/base/models/res_bank.py#L34-L38) — produces `name + " - " + bic`
- [`res.bank._search_display_name`](../odoo/addons/base/models/res_bank.py#L40-L47) — uses `bic =ilike "X%"` OR `name ilike "X"`

---

## Gotchas & Non-Obvious Behavior

- **Online sync dialog never dedupes**: the `+ Add XYZ` fallback always creates a new `res.bank`. Avoid this dialog for manual setup.
- **Dashboard has two "New" entry points**: the top-left `New` button opens the correct journal wizard; the **Bank tile** opens the online sync dialog. They look similar but lead to different places.
- **Currency must be set before posting**: once a journal has entries, you can't change its currency.
- **Many2one quick-create trap**: in the Bank dropdown, `+ Create "XYZ"` always creates a new `res.bank` even if an identical one exists. Only use it the first time; otherwise pick from suggestions.
- **Display name `"BOG - GEBA"` ≠ "BOG"**: the dropdown appends BIC to the bank name. Don't assume a bank is missing just because its bare name isn't in the list.
- **`res.bank` has no `company_id`**: it's a shared global record. There's no multi-company filter; all companies see all banks.
- **No record rules on `res.bank`**: visibility is not restricted by user/group/company — if it doesn't appear, the issue is either active=False or you're in the wrong dialog.

---

## Related Docs

- [`INDEX.md`](INDEX.md)
- [`currency_exchange_transit.md`](currency_exchange_transit.md) — Liquidity Transfer mechanics, transit account, exchange gain/loss
- [`accounting_coa.md`](accounting_coa.md) — chart of accounts, where bank GL accounts come from

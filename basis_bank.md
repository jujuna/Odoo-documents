# Basis Bank Integration (`basis_bank`)

> **Module:** `basis_bank` | **Path:** [`custom_addons/gec_odoo_modules/basis_bank/`](../custom_addons/gec_odoo_modules/basis_bank/) | **Version:** 19.0.1.15.0
> Written 2026-09-17 from every Python, XML, CSV and Markdown file in the module, the bank's API PDF (`BBAPI Tech Doc Eng_Geo.pdf`, 20 pages) and live data in the `gec_new` database. Coverage: 100% of source files. Not read: `i18n/ka_GE.po` (translations only), `developer_map.html` (generated), the icon.
> User guide: [`README.md`](../custom_addons/gec_odoo_modules/basis_bank/README.md). Developer guide: [`README_DEV.md`](../custom_addons/gec_odoo_modules/basis_bank/README_DEV.md). Review backlog: [`KNOWN_ISSUES.md`](../custom_addons/gec_odoo_modules/basis_bank/KNOWN_ISSUES.md). Bank API extraction: [`basisbank_api.md`](../basisbank_api.md) (project root).

## What It Does & Why It Exists

Georgian companies banking at Basis Bank (BIC `CBASGE22`) want to pay vendors, salaries and the treasury from Odoo without retyping transfers in Internet Banking, and want Odoo to know when the money really left. Basis Bank exposes a small REST API at `bis.bankonline.ge`: log in, upload transfer packages with a Digipass one-time password, and download the account statement (`GetReport`).

This module is the transport layer between standard Odoo payments and that API. Standard Odoo still creates the payments, posts the journal entries and reconciles; the module only transmits outbound payments, records the bank's verdict in its own field **Basis Bank Status**, and imports the statement back so that a sent payment becomes *Paid* only after the statement shows the debit. It never books a journal entry of its own.

Roles: accountants and treasury staff send and import, a named approver (plus delegates) approves when the connection is in approval mode, and a Basis Bank manager owns the connection, credentials and API logs.

---

## The Big Picture — How It Works

```
Register Payment on a Basis journal        Import Statement (wizard or daily cron)
  transfer type: Internal/National/                 |
  Foreign/Treasury                                  v
        |                                  GetReport(Account, Ccy, dates, page)
        v                                           |
  [optional] Batch  --> Submit for Approval -->     v
        |               Approve (approver)   statement lines, both directions:
        v                                      +amount  our IBAN is CreditAcc (money in)
  Send to Basis Bank + OTP                     -amount  our IBAN is DebitAcc  (money out)
        |                                           |
        v                                           v
  bank reply: Sent / Failed / Unknown       auto-match NEGATIVE lines to Sent payments
        |                                           |
        v                                           v
  payment stays In Process  ------------->  Confirmed by Statement --> Paid
                                             (48 h with no match --> Not in Bank Report,
                                              entry reset to draft or flagged if locked)
```

Two independent halves meet in the middle:

1. **Outbound send.** A payment (or a batch of payments) on a Basis journal is sent with an OTP. The bank answers per package or per transfer. The module writes the answer to `basisbank_state` and forces Odoo's payment state to stay *In Process* even if core would have called it *Paid* ([account_payment.py:147-175](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L147)).
2. **Statement import.** The wizard calls `GetReport` for one IBAN, one currency and a date range, and turns every item into a standard `account.bank.statement.line`. Items where our IBAN is the credit side become positive lines (incoming money), items where our IBAN is the debit side become negative lines (outgoing money). The negative lines are then matched against payments in *Sent to Bank* and confirm them.

### Key Decision Points

- **Processing mode on the connection** ([basisbank_connection.py:47-57](../custom_addons/gec_odoo_modules/basis_bank/models/basisbank_connection.py#L47)): *Approve in Odoo first* (default, needs an approver record), *Direct*, or *Manual confirmation in Internet Banking*. It decides whether a second person must click Approve before the OTP is entered, and whether a sent batch waits as *Awaiting IB Confirmation*.
- **Transfer type on the payment** (`internal`, `national`, `foreign`, `treasury`): decides the payload shape, the mandatory fields (BIC, treasury code, SWIFT address, charges) and the GEL-only rule for national and treasury ([account_payment.py:258-311](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L258)).
- **Which bank operation a batch uses** is computed, not chosen ([account_batch_payment.py:123-141](../custom_addons/gec_odoo_modules/basis_bank/models/account_batch_payment.py#L123)): salary flag + all GEL + one sender IBAN → Salary package (op 5); only internal → GEL package (op 4); only treasury → Treasury package (op 6); anything else → Single transfers batch (op 7). Packages are all-or-nothing at the bank; the single batch gets a verdict per transfer.
- **What makes a journal a Basis journal** is the bank's BIC alone ([account_journal.py:40-48](../custom_addons/gec_odoo_modules/basis_bank/models/account_journal.py#L40)). There is no checkbox, so every company that merely banks at Basis gets the *In Process* hold on outbound payments.

---

## Does the statement import bring in both inbound and outbound transactions?

Yes. Three independent proofs, from the bank's specification, from the module's code and from real bank responses stored in a live database.

### 1. The bank's specification (PDF section 8, GetReport)

`GetReport` is the bank's account statement ("ამონაწერი"). The request names one `Account`, one `Ccy`, a date range and a 1-based `PageNo`. Each returned item carries, among 25 fields, `DebitAcc`, `DebitAccName`, `CreditAcc`, `CreditAccName`, `Amount` and `DocType`. The direction of a line is therefore encoded by which side our own IBAN sits on. The PDF's only worked example is an incoming item (`DocType: "CashIn"`, our account in `CreditAcc`). The PDF never states in words that both directions are returned, so the specification alone is only an indication.

### 2. The module's code

The import wizard decides the sign of every line from the account pair, and creates a line for both outcomes ([basisbank_statement_import_wizard.py:185-196](../custom_addons/gec_odoo_modules/basis_bank/wizard/basisbank_statement_import_wizard.py#L185)):

```python
def _amount_sign(self, item):
    """Return +1 if our IBAN is the credit side (money in), -1 if the debit side (out), None if neither."""
    ...
    if our_acc == debit:
        return -1
    if our_acc == credit:
        return 1
    return None
```

`_build_line_vals` ([basisbank_statement_import_wizard.py:137-183](../custom_addons/gec_odoo_modules/basis_bank/wizard/basisbank_statement_import_wizard.py#L137)) applies that sign to `abs(Amount)`, picks the counterparty name from the opposite side (`DebitAccName` for incoming, `CreditAccName` for outgoing) and appends the line. Only two kinds of item are skipped and counted: items without `BankInternalID`, and items where our IBAN is on neither side. Nothing filters on direction. The `DocType` value is not used at all, so the undocumented vocabulary (`TransferIn`, `TransferOut`, `BankInternal`, `CashIn`) cannot break the import.

The only direction filter in the module is downstream, in the auto-confirmation hook: `_basisbank_auto_match` looks at `amount < 0` lines only ([account_bank_statement_line.py:21-24](../custom_addons/gec_odoo_modules/basis_bank/models/account_bank_statement_line.py#L21)). That is deliberate: an incoming line must never confirm an outbound payment. Incoming lines are still imported; they simply wait in the bank reconciliation widget like any other statement line.

### 3. Real bank responses (database `gec_new`, module 19.0.1.4.0, connection to `bis.bankonline.ge` API `v2`)

Every API call is logged with its redacted request and full response in `basisbank.api.log`. Four `GetReport` calls exist for the GEL journal (IBAN `GE55BS…6488`). Classifying every returned item by which side holds that IBAN:

| Call date | Requested range | Items | Our IBAN in `CreditAcc` (in) | Our IBAN in `DebitAcc` (out) | Neither |
|---|---|---|---|---|---|
| 2026-06-03 | 06-02 to 06-03 | 10 | 9 | 1 (`BankInternal`, a bank fee) | 0 |
| 2026-06-09 | 06-08 to 06-09 | 20 | 19 | 1 (`TransferOut`) | 0 |
| 2026-06-12 | 06-11 to 06-12 | 4 | 4 | 0 | 0 |
| 2026-06-14 | 06-10 to 06-15 | 14 | 7 | 7 (`TransferOut`) | 0 |
| **Total** | | **48** | **39** | **9** | **0** |

`DocType` by direction: `TransferIn` 39 (all incoming), `TransferOut` 8 and `BankInternal` 1 (all outgoing). Every `Amount` in all 48 items is a positive number, including the 9 outgoing ones. This settles an open question in the README: statement amounts are plain magnitudes, and direction comes only from the debit/credit accounts. Exactly as the code assumes.

The statement lines actually stored in that database match:

| Statement (core name) | Lines | Positive (in) | Negative (out) |
|---|---|---|---|
| BNK2 Statement 2026-06-03 | 10 | 9 | 1 (−80.00) |
| BNK2 Statement 2026-06-09 | 20 | 19 | 1 (−437.70) |
| BNK2 Statement 2026-06-11 | 4 | 4 | 0 |
| **Total** | **34** | **32 (+1,276,831.89)** | **2 (−517.70)** |

**How those lines got there.** Not through the menu wizard and not through the scheduler. All 3 statements and all 34 lines have `create_uid = 1` (`__system__`), the user the cron runs as; a person using the wizard would have created them under their own login. At the exact second of each import the cron method posted "Daily statement sync failed for Basis Bank USD/EUR" on the connection chatter, a message only `_cron_daily_statement_sync` writes ([basisbank_connection.py:240-272](../custom_addons/gec_odoo_modules/basis_bank/models/basisbank_connection.py#L240)), and the cron's `lastcall` equals the last import time. Yet the cron record has `active = false` and its `write_date` equals its `create_date` (2026-05-26), so the scheduler never fired it. The only mechanism that fits is **Run Manually** on the scheduled action, which executes the code as the cron user and stamps `lastcall` whatever the active flag says. It was triggered four times: 2026-06-02 (failed for all three journals), 2026-06-03, 2026-06-09 and 2026-06-12 (GEL imported, USD/EUR failed each time before any bank call was logged; their IBANs are the demo placeholders, and the exact exception cannot be reconstructed because `gec_new` runs 19.0.1.4.0 code that is no longer on disk).

The fourth `GetReport` call (2026-06-14) produced no statement. Its window, sent date minus two days to today plus one, is the signature of a report lookup by *Resync* or the 48-hour check for a payment sent on 2026-06-12 ([account_payment.py:597-600](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L597)). Those lookups read the report and never import lines, so its 10 items that are not in the statement table are expected, not lost.

Two `GetReport` fields appear in the live responses but not in the PDF schema: `TransactionReference` (present) and `DocType` values beyond `CashIn`. The module ignores both.

### What this does not prove

Whether an outbound transfer **sent from Odoo** appears in the report in a way the module can match. No Odoo-initiated transfer has yet been observed on a statement in any database. See the gotcha on identifier spaces below.

---

## When to Use It (and When Not To)

### This module is for:
- A company with at least one bank journal at Basis Bank that wants to send vendor payments, treasury payments and salary batches from Odoo with one OTP per batch.
- Accountants who want the bank statement pulled into Odoo daily without a file export from Internet Banking.
- Companies that want a second person (approver) between the person who prepares a payment and the person who enters the OTP.

### Use something else when:
- The journal is at another bank: nothing here applies; `is_basisbank` is false and the module stays invisible.
- You only need statement files: standard `account_bank_statement_import` handles CSV/OFX/CAMT without any bank API.
- You want payroll to be sent automatically: the payroll bridge `gec_payroll_bank` prepares the batches, but the send is always a human with the OTP. There is no unattended send by design ([README_DEV.md section 12](../custom_addons/gec_odoo_modules/basis_bank/README_DEV.md)).

---

## Real-World Scenarios

### Scenario 1: Pay a vendor bill in GEL to another Georgian bank
**Situation:** An accountant at a company on the Georgian chart of accounts has a posted vendor bill of 1,340 GEL; the vendor banks at Bank of Georgia.
**What they do:** Register Payment on the Basis GEL journal, set Transfer Type *National*, make sure the memo is filled and the vendor's bank account has *Allow Out Payments* ticked, then **Send to Basis Bank** and type the Digipass OTP. In the default mode they first click **Submit for Approval** and an approver clicks **Approve**.
**What happens:** The module takes a row lock, re-runs every check, posts the payment entry if it was draft, and sends one item in `NationalCurrencyTransfers` of the single-transfers batch (op 7). On `ErrorCode 0` for that item the payment becomes *Sent to Bank* with the bank's reference and Odoo's state is held at *In Process* ([account_payment.py:411-472](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L411)). It becomes *Paid* only once a later statement import shows the 1,340 debit and the matcher confirms it.

### Scenario 2: Import yesterday's statement and reconcile
**Situation:** The same accountant opens Odoo in the morning.
**What they do:** **Basis Bank > Operations > Import Statement**, pick the GEL journal and yesterday's dates. Or leave it to the *Daily statement sync* cron once it is switched on (it ships disabled).
**What happens:** The wizard pages through `GetReport`, builds one statement with every item as a line: customer receipts as positive lines, the vendor transfer, bank fees and salary advances as negative lines. Re-importing the same dates creates nothing new, because each line carries `unique_import_id = basisbank/<journal>/<BankInternalID>` and core enforces uniqueness. Negative lines are offered to the auto-matcher; positive lines wait in the reconciliation widget. The wizard reports imported, skipped and confirmed counts.

### Scenario 3: Send a salary run
**Situation:** HR validated the June payslips; the company pays salaries from the Basis GEL journal.
**What they do:** In the payroll bridge (`gec_payroll_bank`) they click *Pay Salaries*. It creates the net-pay payments and a batch flagged `basisbank_salary`. They open the batch and **Send to Basis Bank** with the OTP.
**What happens:** The batch routes to the Salary package (op 5) because every payment is GEL from one sender IBAN. The bank accepts or rejects the whole package. If nobody sends the batch within 48 hours a to-do activity is scheduled for the approver or creator, because the payslips are already marked paid ([account_batch_payment.py:93-121](../custom_addons/gec_odoo_modules/basis_bank/models/account_batch_payment.py#L93)).

### Scenario 4: The send timed out
**Situation:** The bank did not answer within 15 seconds.
**What they do:** Nothing rash. The payment shows *Unknown*. They click **Resync from Bank**.
**What happens:** Resync reads the report for a window around the send date and confirms the payment if an item with `DocNum` equal to the payment id and the same amount is found; otherwise it reports "not found yet". A resend is only allowed through **Reset to Pending**, which re-checks the report first so a transfer that did execute is confirmed instead of duplicated ([account_payment.py:834-870](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L834)).

---

## How Things Work Under the Hood

### Core Logic

- **`basisbank.service._call()`** ([basisbank_service.py:190-259](../custom_addons/gec_odoo_modules/basis_bank/services/basisbank_service.py#L190)) — one HTTPS POST per bank call, always `https://` regardless of the `http://` in the PDF, 15-second timeout, `TicketId` injected from the connection. Every call writes an audit row on a separate cursor so the log survives a rolled-back send, with `Password`, `Otp` and `TicketId` redacted. Only `GetReport` retries once on an invalid ticket (code 3); sends never auto-retry.
- **Session ticket** ([basisbank_connection.py:108-129](../custom_addons/gec_odoo_modules/basis_bank/models/basisbank_connection.py#L108)) — the bank's session dies after 10 minutes of inactivity; the module stores the ticket for 9 minutes and slides the expiry on every call.
- **`_amount_sign()` and `_build_line_vals()`** — the direction logic described above. The wizard, not the service, owns pagination; `fetch_report_items()` in the service duplicates the loop for Resync and the cron.
- **`_basisbank_auto_match()`** ([account_bank_statement_line.py:19-90](../custom_addons/gec_odoo_modules/basis_bank/models/account_bank_statement_line.py#L19)) — runs inside `create()` of statement lines. For negative Basis lines it looks up payments in *Sent* or *Not in Bank Report* first by `basisbank_bank_internal_id`, then by `DocNum == payment id`, but the `DocNum` route is only tried for payments that have **no** bank id yet. Same journal, same company and equal amount (converted if currencies differ) are required. Each confirmation runs in its own savepoint so one bad payment cannot abort the import.
- **`_basisbank_confirm_from_statement()`** ([account_payment.py:209-236](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L209)) — writes *Confirmed*, re-posts the entry if the 48-hour check had drafted it, marks it sent and calls `action_validate` so Odoo flips *In Process* to *Paid*. It does not reconcile the statement line; that is still the accountant's job.
- **Paid gating** ([account_payment.py:134-175](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L134)) — an outbound Basis payment refuses *Paid* until confirmed, unless its statement line was reconciled by hand on a reconcilable Outstanding Payments account. That escape hatch is what frees a transfer typed directly in Internet Banking.
- **48-hour confirm-or-reset cron** ([account_payment.py:641-732](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L641)) — hourly. For payments sent more than 48 hours ago it does one report fetch per journal and currency, matches by bank id then `DocNum`, and confirms what it finds. What it does not find is reset: reconciliation removed, entry back to draft, state *Not in Bank Report*, chatter on the payment and on the bills it was paying. Lock-dated periods are only flagged. This is the single place the module rewrites posted accounting.
- **Send pipeline** (payment [411-472](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L411), batch [218-282](../custom_addons/gec_odoo_modules/basis_bank/models/account_batch_payment.py#L218)) — `FOR UPDATE NOWAIT` lock, state and approval re-check, authenticate, post draft entries, then two savepoints: one around the upload and reply parsing, one around finalization. Any exception parks the record in *Unknown*, which blocks resending until Resync clears it.
- **Rejection** ([account_payment.py:562-588](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L562)) — rejected payments are cancelled only if unreconciled; a rejected but reconciled payment (a salary) is flagged and left for a human, so a payable is never silently reopened.

### Important Fields (only the ones that matter)

- `basisbank_state` on the payment (9 values) and on the batch (9 values) — the bank truth, separate from Odoo's `state`. Only *Confirmed by Statement* means money moved. Default is `pending` on every payment, even inbound and non-Basis ones (backlog D8).
- `basisbank_bank_internal_id` — the reference the bank returned when it accepted a single transfer, unique per company. Packages return no per-payment reference.
- `basisbank_endpoint` on the batch — the computed operation (op 4/5/6/7); the batch `name` becomes the bank's `PackageName` and must be unique per journal and endpoint.
- `is_basisbank` on the journal — stored compute from the BIC; drives every button's visibility.
- `unique_import_id` on statement lines — `basisbank/<journal_id>/<BankInternalID>`, the deduplication key and the hook the auto-matcher recognises.

---

## Configuration & Settings

- **Connection** (Basis Bank > Configuration > Connections, one per company) — login, password, host `bis.bankonline.ge`, version (`v1` default; the live `gec_new` connection uses `v2`), processing mode, approver. *Test Connection* must turn the state *Active*; *Blocked* (bank codes 4/5) refuses every send.
- **Journal IBAN** — the journal's bank account number is the `Account` sent to `GetReport` and the `SenderAcc` of every upload. Without it neither send nor import works. Spaces are stripped and the comparison is case-insensitive.
- **Outstanding Payments account** on the *Basis Bank Transfer* method line — pre-filled from the chart (`1210.04` on the Georgian chart). It must stay reconcilable, otherwise the *Paid* gate becomes circular (backlog A1).
- **Trusted receiver accounts** — every receiver `res.partner.bank` needs *Allow Out Payments*; this is the usual first blocker.
- **Crons** ([ir_cron_data.xml](../custom_addons/gec_odoo_modules/basis_bank/data/ir_cron_data.xml)) — 48-hour check hourly (on), stale salary batches every 4 hours (on), daily statement sync (off; imports yesterday to today for every Basis journal of each active connection, one savepoint per journal). All three are `noupdate`, so XML edits do not propagate on upgrade. As of 2026-09-17 the daily sync has never run on schedule in any database: inactive since install in `gec_new` (triggered by hand four times, see the proof section) and inactive with no `lastcall` in `gec_modules_hr3`.
- **Groups** — *Basis Bank / User* (also grants Invoicing) can send, import, resync and reset; *Basis Bank / Manager* (also grants Accounting Manager) owns connections, approvers, logs and the password change.

---

## Dependencies

| Requires | Why |
|---|---|
| `account_accountant` | Bank reconciliation widget, the manual release path for held payments |
| `account_batch_payment` | The batch model the packages are built on |
| `account_bank_statement_import` | `_create_bank_statements()` and the `unique_import_id` uniqueness that deduplicates imports |
| `hr_payroll_account` | Payslip journal entries for the legacy salary path |
| `payment` | The secret-masking logger |
| `mail` | Chatter, followers for approvers, activities for stale batches |
| `gec_localization` | The BasisBank `res.bank` record and the Georgian chart with the Outstanding Payments account |
| `gec_payroll_bank` | The five payroll adapter hooks on `account.payment.method.line` and the *Pay Salaries* entry point |

---

## Gotchas & Non-Obvious Behavior

- **Two identifier spaces, one field.** The reference the bank returns when it accepts a single transfer is short and letter-prefixed (`I345` live; `I28`, `G6178`, `V216`, `T1582` in the PDF). The `BankInternalID` on statement items is a 9-digit number (`575750594` live; `56722141` in the PDF). Both are stored and compared in `basisbank_bank_internal_id`. [Certain] the formats differ. [Likely] the statement-import matcher can therefore never confirm a single-batch payment by bank id, and because it skips the `DocNum` route for payments that already hold a bank id, such payments can only be confirmed by the 48-hour cron or Resync, which do fall back to `DocNum`. Whether the bank echoes our `DocNum` on statement items is still unverified: in `gec_new` the single Odoo-sent transfer (1 GEL, reference `I345`) never appeared on any statement and ended as *Not in Bank Report*.
- **Incoming lines never confirm anything.** By design. They are imported and left for reconciliation. The confirmed counter in the wizard only ever counts outbound payments.
- **Import is not reconciliation.** A confirmed payment is *Paid* while the Outstanding Payments account still shows the amount until the statement line is reconciled.
- **Skips are silent to the user.** Items without `BankInternalID` or where our IBAN is on neither side are only counted and logged on the server. No opening or closing balance is written, so a gap does not trigger core's balance check (backlog B6).
- **Two identical copies on disk.** `custom_addons/gec_odoo_modules/basis_bank` and `custom_addons/gec_basis_bank_integration/basis_bank` are byte-identical at 19.0.1.15.0 (checked 2026-09-17). The README, README_DEV and INDEX name the second path. Edit one and copy, or delete one.
- **`action_basisbank_import_statement` on the journal has no button.** The import is reached from the Basis Bank menu only ([account_journal.py:95-104](../custom_addons/gec_odoo_modules/basis_bank/models/account_journal.py#L95)).
- **Run Manually imports even while the cron is off.** Odoo's *Run Manually* on the scheduled action executes `_cron_daily_statement_sync` as `__system__` and stamps `lastcall`, ignoring `active`. Every statement in `gec_new` was produced this way. Statement lines created by `__system__` are the fingerprint.
- **Demo journals make every sync run report failures.** The cron loops over all Basis journals with an IBAN, including the USD/EUR demo journals with placeholder IBANs; each fails and posts "Daily statement sync failed" on the connection while the GEL import succeeds in its own savepoint. Replace or remove the demo journals before switching the cron on.
- **The `_cron_daily_statement_sync` range overlaps on purpose.** Yesterday to today every day; duplicates are absorbed by the unique import id, but the wizard's *skipped* count will be non-zero every morning.
- **Legacy code still ships.** `hr.payslip._basisbank_send_salaries` and friends have no menu or button since 19.0.1.14.0; the live salary path is `gec_payroll_bank`. The XLSX salary upload wizard raises "temporarily disabled" on its first line.
- **Package sends give no per-payment reference.** Confirmation of a package member relies entirely on the bank echoing `DocNum`, which nobody has observed yet.
- **Bank code 6 (service suspended) marks payments Failed**, not retryable, although the transfer was never attempted. Reset to Pending after the service is back.
- **Tests cover only the payroll adapter** (2 tests). The send state machine, matching and crons are untested.

---

## Related Docs

- [`INDEX.md`](INDEX.md)
- [`basisbank_api.md`](../basisbank_api.md) — endpoint-by-endpoint extraction of the bank PDF (project root)
- [`basis_bank.md`](../basis_bank.md) (project root) — the original 2026-05 analysis and module plan; historical, states and paths differ from what shipped
- [`payroll_payment_flow.md`](payroll_payment_flow.md) — how payslips become payments before they reach a Basis batch
- [`bank_journal_multicurrency_setup.md`](bank_journal_multicurrency_setup.md) — journal currency setup, which the import wizard enforces against the requested `Ccy`

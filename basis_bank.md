# Basis Bank Integration (`basis_bank`)

> **Module:** `basis_bank` 20.0.1.15.0 | **Path:** [`custom_addons/gec_odoo_modules/basis_bank/`](../custom_addons/gec_odoo_modules/basis_bank/)
> Verified against Odoo 20 source on 2026-09-24.

## What It Does & Why It Exists

Georgian companies that bank at Basis Bank (BIC `CBASGE22`) want to pay vendors, salaries and the State Treasury from Odoo without retyping transfers in Internet Banking, and want Odoo to know when the money really left. Basis Bank exposes a small REST API at `bis.bankonline.ge`: log in, upload transfer packages with a Digipass one-time password (OTP), and download the account statement (`GetReport`).

This module is the transport layer between standard Odoo payments and that API. Standard Odoo still creates the payments, posts the journal entries and reconciles. The module transmits outbound payments, records the bank's verdict in its own field **Basis Bank Status**, and imports the statement back. A sent payment reaches *Reconciled* only after the statement shows the debit. The module never books a journal entry of its own.

In Odoo 20 payment states, *Paid* means posted and waiting for the bank; *Reconciled* means matched with the statement. A posted Basis payment stays *Paid* until the bank confirms it.

Roles: accountants and treasury staff send and import; a named approver (plus delegates) approves when the connection is in approval mode; a Basis Bank manager owns the connection, credentials and API logs.

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
  (posts it if still draft: state Paid)             |
        |                                           v
        v                                  auto-match NEGATIVE lines to Sent payments
  bank reply: Sent / Failed / Unknown               |
        |                                           v
        v                                  Confirmed by Statement --> Reconciled
  payment stays Paid  --------------------> (48 h with no match --> Not in Bank Report,
                                             entry reset to draft, or flagged if locked)
```

Two independent halves meet in the middle:

1. **Outbound send.** A payment (or a batch of payments) on a Basis journal is sent with an OTP. The bank answers per package or per transfer, and the module writes the answer to `basisbank_state`. The send posts the payment if it is still a draft, so its Odoo state is *Paid*. The module refuses *Mark as Reconciled* (`action_validate`) until the bank confirms the transfer ([account_payment.py:171](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L171)). Core moves a payment to *Reconciled* on its own only when its outstanding line is matched, or when every bill it pays is *Paid* ([account_payment.py:496](../addons/account/models/account_payment.py#L496)). With `accountant` installed (it comes with `hr_payroll_account`), a bill paid by an unmatched payment is *In Payment*, not *Paid* ([account_move.py:7](../enterprise/accountant/models/account_move.py#L7)). So neither happens before the statement line is reconciled.
2. **Statement import.** The wizard calls `GetReport` for one IBAN, one currency and a date range, and turns every item into a standard `account.bank.statement.line`. Items where our IBAN is the credit side become positive lines (money in); items where our IBAN is the debit side become negative lines (money out). The negative lines are then matched against payments in *Sent to Bank*, which confirms them.

### Key Decision Points

- **Processing mode on the connection** ([basisbank_connection.py:47](../custom_addons/gec_odoo_modules/basis_bank/models/basisbank_connection.py#L47)): *Approve in Odoo first* (default, needs an approver record), *Direct*, or *Manual confirmation in Internet Banking*. It decides whether a second person must click **Approve** before the OTP is entered, and whether a sent batch waits as *Awaiting IB Confirmation*. Switching to a mode without approval clears the approver ([basisbank_connection.py:126](../custom_addons/gec_odoo_modules/basis_bank/models/basisbank_connection.py#L126)).
- **Transfer type on the payment** (`internal`, `national`, `foreign`, `treasury`): decides the payload shape and the mandatory fields. Treasury needs a Treasury Code and has no receiver account; foreign needs country, city, address and charges ([account_payment.py:128](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L128)). National and treasury transfers must be in GEL.
- **Which bank operation a batch uses** is computed, not chosen ([account_batch_payment.py:73](../custom_addons/gec_odoo_modules/basis_bank/models/account_batch_payment.py#L73)): salary flag + all GEL + one sender IBAN gives the Salary package (op 5); only internal transfers in GEL from one IBAN give the GEL package (op 4); only treasury transfers in GEL from one IBAN give the Treasury package (op 6); anything else is a Single transfers batch (op 7). Packages are all-or-nothing at the bank; op 7 gets a verdict per transfer.
- **What makes a journal a Basis journal**: a bank journal whose bank account BIC is `CBASGE22` (8 or 11 characters, [account_journal.py:102](../custom_addons/gec_odoo_modules/basis_bank/models/account_journal.py#L102)) **and** a Basis connection on its company or a parent company ([account_journal.py:46](../custom_addons/gec_odoo_modules/basis_bank/models/account_journal.py#L46)). A company that only banks at Basis, without a connection, keeps the standard payment rules. Creating, moving or deleting a connection re-evaluates the journals of its company and branches ([basisbank_connection.py:104](../custom_addons/gec_odoo_modules/basis_bank/models/basisbank_connection.py#L104)). A connection in *Error* or *Blocked* still counts, so a failed login never lifts the guard on payments already at the bank.

---

## Does the statement import bring in both inbound and outbound transactions?

Yes. The bank's specification allows it and the module's code imports both.

### 1. The bank's specification (PDF section 8, GetReport)

`GetReport` is the bank's account statement. The request names one `Account`, one `Ccy`, a date range and a 1-based `PageNo`. Each returned item carries, among 25 fields, `DebitAcc`, `DebitAccName`, `CreditAcc`, `CreditAccName`, `Amount` and `DocType`. The direction of a line is therefore encoded by which side our own IBAN sits on. The PDF's only worked example is an incoming item (`DocType: "CashIn"`, our account in `CreditAcc`), and it never states in words that both directions are returned. Endpoint-by-endpoint extraction: [`basisbank_api.md`](../basisbank_api.md).

### 2. The module's code

- `_amount_sign()` returns -1 when our IBAN is `DebitAcc`, +1 when it is `CreditAcc`, and nothing when it is neither ([basisbank_statement_import_wizard.py:165](../custom_addons/gec_odoo_modules/basis_bank/wizard/basisbank_statement_import_wizard.py#L165)).
- `_build_line_vals()` applies that sign to `abs(Amount)`, so the import is right whether the bank sends signed or unsigned amounts; a negative `Amount` only logs a warning ([basisbank_statement_import_wizard.py:117](../custom_addons/gec_odoo_modules/basis_bank/wizard/basisbank_statement_import_wizard.py#L117)). The counterparty name comes from the opposite side (`DebitAccName` for money in, `CreditAccName` for money out).
- Only two kinds of item are skipped and counted: items without `BankInternalID`, and items where our IBAN is on neither side. Core then skips zero-amount lines ([account_journal.py:282](../enterprise/account_bank_statement_import/models/account_journal.py#L282)). Nothing filters on direction, and `DocType` is not read at all, so its undocumented values cannot break the import.

The only direction filter in the module is downstream: `_basisbank_auto_match()` looks at `amount < 0` lines only ([account_bank_statement_line.py:19](../custom_addons/gec_odoo_modules/basis_bank/models/account_bank_statement_line.py#L19)). That is deliberate: an incoming line must never confirm an outbound payment. Incoming lines are still imported and wait in the bank reconciliation screen like any other statement line.

### What is not proven yet

Live Odoo 20 data: `gec20_prod1` has no `GetReport` call yet (API log checked 2026-09-24: 4 login calls). Whether an outbound transfer **sent from Odoo** shows up in the report in a way the module can match is [Unverified]; see the gotcha on identifier spaces below.

---

## When to Use It (and When Not To)

### This module is for:
- A company with at least one bank journal at Basis Bank that wants to send vendor payments, treasury payments and salary batches from Odoo with one OTP per batch.
- Accountants who want the bank statement pulled into Odoo without a file export from Internet Banking.
- Companies that want a second person (the approver) between the person who prepares a payment and the person who enters the OTP.

### Use something else when:
- **The journal is at another bank, or the company has no Basis connection**: nothing here applies; `is_basisbank` is false and the module stays invisible.
- **You only need statement files**: standard `account_bank_statement_import` handles CSV/OFX/CAMT without any bank API.
- **You want payroll sent automatically**: `gec_payroll_bank` prepares the batches, but the send is always a person with the OTP. There is no unattended send by design ([README_DEV.md §12](../custom_addons/gec_odoo_modules/basis_bank/README_DEV.md)).

---

## Real-World Scenarios

### Scenario 1: Pay a vendor bill in GEL to another Georgian bank
**Situation:** An accountant at a company on the Georgian chart (`l10n_ge`) has a posted vendor bill of 1,340 GEL; the vendor banks at Bank of Georgia.
**What they do:** **Register Payment** on the Basis GEL journal with the *Basis Bank Transfer* method, which shows the **Vendor Bank Account** field. They set Transfer Type *National*, fill the memo, and check that the vendor's bank account is trusted (*Allow Out Payments*) and has a BIC. With `gec_localization`, typing the vendor's Georgian IBAN fills the BIC. In the default mode they click **Submit for Approval**, an approver clicks **Approve**, then someone clicks **Send to Basis Bank** and types the OTP.
**What happens:** The module locks the payment row, re-runs every check, posts the payment if it is a draft (state *Paid*) and sends one item in `NationalCurrencyTransfers` of op 7 ([account_payment.py:455](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L455)). The receiver name sent is the account holder's name, else the commercial partner's name ([account_payment.py:242](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L242)). On `ErrorCode 0` for that item the payment becomes *Sent to Bank* with the bank's reference and stays *Paid*. It becomes *Reconciled* only once a statement import, a Resync or the 48-hour check finds the 1,340 debit.

### Scenario 2: Import yesterday's statement and reconcile
**Situation:** The same accountant opens Odoo in the morning.
**What they do:** **Basis Bank > Operations > Import Statement**, pick the GEL journal and yesterday's dates. Or leave it to the *Daily statement sync* cron once it is switched on (it ships inactive).
**What happens:** The wizard pages through `GetReport` and builds one statement with every item as a line: customer receipts as positive lines, the vendor transfer, bank fees and salary transfers as negative lines. Re-importing the same dates creates nothing new, because each line carries `unique_import_id = basisbank/<journal>/<BankInternalID>` and core refuses duplicates ([account_bank_statement.py:17](../enterprise/account_bank_statement_import/models/account_bank_statement.py#L17)). Negative lines go to the auto-matcher; positive lines wait in the reconciliation screen. The wizard reports imported, skipped and confirmed counts.

### Scenario 3: Send a salary run
**Situation:** HR validated the month's payslips; the company pays salaries from the Basis GEL journal.
**What they do:** A Payroll Administrator clicks **Pay Salaries** on the pay run (module `gec_payroll_bank`). It creates the net-pay payments through the standard payment register and one batch per bank channel; the Basis batch is flagged `basisbank_salary`. They open the batch and **Send to Basis Bank** with the OTP.
**What happens:** Before anything is created, every recipient account must have a BIC ([account_payment_method_line.py:44](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment_method_line.py#L44)). Each payment gets its transfer type: *treasury* for a recipient whose commercial partner has a Treasury Code (the State Treasury), otherwise *internal* when the recipient's BIC is Basis Bank's and *national* for other banks; non-GEL payments are refused ([account_payment_method_line.py:68](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment_method_line.py#L68)). The batch routes to the Salary package (op 5) because every payment is GEL from one sender IBAN, and the bank accepts or rejects the whole package. The payslips read *Paid* as soon as the payments exist, so `gec_payroll_bank`'s watchdog (every 4 hours) schedules an activity for the batch creator when a batch is not transmitted within 48 hours, and at once when it failed or its outcome is uncertain ([account_batch_payment.py:105](../custom_addons/gec_odoo_modules/gec_payroll_bank/models/account_batch_payment.py#L105)). Basis Bank reports where each batch stands through `_gec_payroll_handoff_state()` ([account_payment_method_line.py:107](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment_method_line.py#L107)).

### Scenario 4: The send timed out
**Situation:** The bank did not answer within 15 seconds.
**What they do:** Nothing rash. The payment shows *Unknown*. They click **Resync from Bank**.
**What happens:** Resync reads the report for a window of two days around the send date (always reaching tomorrow) and confirms the payment if the bank has it, using the shared matching rule below ([account_payment.py:666](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L666)). Otherwise it reports "not found yet". A resend is only possible through **Reset to Pending**, which re-checks the report first, so a transfer that did execute is confirmed instead of duplicated ([account_payment.py:867](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L867)).

---

## How Things Work Under the Hood

### Core Logic

- **`basisbank.service._call()`** ([basisbank_service.py:213](../custom_addons/gec_odoo_modules/basis_bank/services/basisbank_service.py#L213)) — one HTTPS POST per bank call (always `https://`, whatever the PDF says), 15-second timeout, `TicketId` injected from the connection. Every call writes an audit row on its own cursor, so the log survives a rolled-back send, with passwords, OTP and ticket masked ([basisbank_service.py:284](../custom_addons/gec_odoo_modules/basis_bank/services/basisbank_service.py#L284)). Only `GetReport` retries once after re-login on an invalid ticket (code 3); sends never retry. Codes 4/5 set the connection to *Blocked*, code 6 or a failed login to *Error*.
- **Session ticket** ([basisbank_connection.py:146](../custom_addons/gec_odoo_modules/basis_bank/models/basisbank_connection.py#L146)) — the bank's session dies after 10 minutes of inactivity; the module keeps the ticket for 9 minutes, slides the expiry on every call, and logs in again when less than 30 seconds remain.
- **`fetch_report_items()`** ([basisbank_service.py:183](../custom_addons/gec_odoo_modules/basis_bank/services/basisbank_service.py#L183)) — pages through the whole report. The import wizard, Resync, Reset to Pending and the 48-hour check all read the bank through it.
- **One matching rule for report readers** — `_basisbank_match_report_items()` pairs payments with report items by `BankInternalID` first, then `DocNum` (the Odoo payment id). A candidate must be a debit from the payment's own IBAN for the exact amount ([account_payment.py:642](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L642), [account_payment.py:677](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L677)). Resync (payment and batch), Reset to Pending and the 48-hour check use it.
- **Statement-line auto-match** — `_basisbank_auto_match()` runs inside `create()` of statement lines ([account_bank_statement_line.py:19](../custom_addons/gec_odoo_modules/basis_bank/models/account_bank_statement_line.py#L19)). For negative Basis lines it looks up payments in *Sent* or *Not in Bank Report* on the line's journal: by bank id first, then by `DocNum`, but the `DocNum` route is only tried for payments that have **no** bank id yet. It matches on the journal, not the company, because a payment made from a branch keeps the branch as company. The amount must be equal (converted when currencies differ). Each confirmation runs in its own savepoint, and batches whose payments are all confirmed become *Done*.
- **`_basisbank_confirm_from_statement()`** ([account_payment.py:212](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L212)) — writes *Confirmed*, re-posts the entry if the 48-hour check had drafted it (and warns that the bill reconciliation was lost), marks it sent, and calls `action_validate` so the payment moves to *Reconciled*. Core refuses that for a bank/cash outstanding account, so such a payment stays *Paid*. It does not reconcile the statement line; that is still the accountant's job.
- **Reconcile gating** ([account_payment.py:158](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L158)) — an outbound Basis payment refuses *Mark as Reconciled* until confirmed. The escape hatch: a statement line reconciled by hand on a reconcilable Outstanding Payments account moves the payment to *Reconciled* through core, which frees a transfer typed directly in Internet Banking. The 48-hour check then marks it *Confirmed*.
- **48-hour confirm-or-reset cron** ([account_payment.py:699](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L699)) — hourly, up to 500 payments per run. It takes payments sent more than 48 hours ago that are still *Sending*, *Sent* or *Unknown* (or *Pending* inside a batch stuck in *Sending*/*Unknown*). Payments already matched by hand are confirmed. For the rest it fetches the report once per journal and currency and confirms what it finds. What it does not find is reset: reconciliation removed, entry back to draft, state *Not in Bank Report*, chatter on the payment and on the bills it was paying ([account_payment.py:793](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L793)). Payments in a locked period are only flagged. This is the single place the module rewrites posted accounting.
- **Send pipeline** (payment [account_payment.py:455](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L455), batch [account_batch_payment.py:166](../custom_addons/gec_odoo_modules/basis_bank/models/account_batch_payment.py#L166)) — `lock_for_update()` (refuses at once with "already being processed" when another transaction holds the row), state and approval re-check (the approver must still be authorized at send time), the pre-send check, login, posting of draft payments, then two savepoints: one around the upload and reply parsing, one around finalization. Any exception parks the record in *Unknown*, which blocks resending until Resync clears it. A wrong OTP or expired session (codes 2/3) un-posts the payments and returns to *Awaiting OTP*; code 999 gives *Unknown* ([account_payment.py:543](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L543)).
- **Pre-send check** — `_basisbank_check_before_send()` lists every problem at once, for single and batch sends ([account_payment.py:355](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L355)): receiver account present and trusted, BIC for national/foreign, a memo, GEL for national/treasury. It also runs the payment method setup check of `gec_payroll_bank`: an Outstanding Payments account that is set, reconcilable, not a bank/cash account and not the journal's own account ([account_payment_method_line.py:87](../custom_addons/gec_odoo_modules/gec_payroll_bank/models/account_payment_method_line.py#L87)), plus a Basis connection that is not blocked and a journal IBAN ([account_payment_method_line.py:29](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment_method_line.py#L29)).
- **Rejection** ([account_payment.py:602](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L602)) — rejected payments are cancelled only if unreconciled; a rejected but reconciled payment (a salary) is flagged and left for a person, so a payable is never silently reopened.
- **Maker-checker guards** — editing amount, partner, recipient account, memo, reference or transfer type after approval voids the approval ([account_payment.py:20](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L20)); changing a batch's payments voids the batch approval ([account_batch_payment.py:105](../custom_addons/gec_odoo_modules/basis_bank/models/account_batch_payment.py#L105)). Payments in *Sent* or *Confirmed* cannot be cancelled, deleted or reset to draft by hand ([account_payment.py:180](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L180)).

### Important Fields (only the ones that matter)

- `basisbank_state` on the payment (9 values) — the bank truth, separate from Odoo's `state`. Computed and stored: *Pending* for outbound payments on Basis journals, empty for every other payment; a state the send flow set is kept even if the journal stops being a Basis journal ([account_payment.py:96](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L96)). Only *Confirmed by Statement* means money moved. The batch has its own 9-value `basisbank_state`.
- `basisbank_bank_internal_id` — the reference the bank returned when it accepted a single transfer, unique per company. Packages return no per-payment reference.
- `basisbank_endpoint` on the batch — the computed operation (op 4/5/6/7); the batch `name` becomes the bank's `PackageName` and must be unique per journal and endpoint.
- `is_basisbank` on the journal — stored; BIC plus connection; drives every button's visibility.
- `unique_import_id` on statement lines — `basisbank/<journal_id>/<BankInternalID>`, the deduplication key and the marker the auto-matcher recognises.

---

## Configuration & Settings

- **Connection** (Basis Bank > Configuration > Connections, one per company) — login, password, host `bis.bankonline.ge`, API version (default `v2`, [basisbank_connection.py:41](../custom_addons/gec_odoo_modules/basis_bank/models/basisbank_connection.py#L41)), processing mode, approver. **Test Connection** must turn the state *Active*; *Blocked* (bank codes 4/5) refuses every send. A connection on a parent company also serves the Basis-BIC journals of its branches ([account_journal.py:22](../custom_addons/gec_odoo_modules/basis_bank/models/account_journal.py#L22)).
- **Journal bank account** — BIC `CBASGE22` and the real IBAN. With `gec_localization` you type only the IBAN: a Georgian IBAN with bank code `BS` fills bank name and BIC ([res_partner_bank.py:30](../custom_addons/gec_odoo_modules/gec_localization/models/res_partner_bank.py#L30)). The IBAN is the `Account` sent to `GetReport` and the `SenderAcc` of every upload; without it neither send nor import works. Spaces are stripped and the comparison ignores case.
- **Basis Bank Transfer payment method** — offered only on journals whose bank account BIC starts with `CBASGE22` ([account_payment_method.py:19](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment_method.py#L19)) and added to them automatically, with the chart's Outstanding Payments account pre-filled ([account_journal.py:67](../custom_addons/gec_odoo_modules/basis_bank/models/account_journal.py#L67)): `120410` on `l10n_ge`, reconcilable ([account.account-ge.csv:11](../addons/l10n_ge/data/template/account.account-ge.csv#L11)). Every method you send with must pass the outstanding-account check above; the send names the method to fix.
- **Trusted receiver accounts** — every receiver `res.partner.bank` needs *Allow Out Payments*; this is the usual first blocker. Only a user with *Validate bank account* rights (or Settings) can trust an account, and never OdooBot outside install or test mode, so scripts and crons must run as a real user ([res_partner_bank.py:317](../addons/account/models/res_partner_bank.py#L317)).
- **Crons** ([ir_cron_data.xml](../custom_addons/gec_odoo_modules/basis_bank/data/ir_cron_data.xml)) — 48-hour check hourly (active); daily statement sync (inactive). The sync imports yesterday to today for every Basis journal with an IBAN of each *Active* connection, one savepoint per journal, and posts a chatter note on the connection when a journal fails ([basisbank_connection.py:255](../custom_addons/gec_odoo_modules/basis_bank/models/basisbank_connection.py#L255)). Both records are `noupdate`, so XML edits do not reach existing databases on upgrade.
- **Groups** — *Basis Bank / User* (implies Invoicing) can send, import, resync and reset; *Basis Bank / Manager* (implies User only, no extra accounting rights) owns connections, approvers, API logs and the password change. The admin user is added to Manager on install.

---

## Dependencies

| Requires | Why |
|---|---|
| `account_accountant` | Bank reconciliation screen, the manual release path for held payments |
| `account_batch_payment` | The batch model the packages are built on |
| `account_bank_statement_import` | `_create_bank_statements()` (returns statement ids, duplicate count and zero-amount count) and the `unique_import_id` constraint that deduplicates imports |
| `hr_payroll_account` | Payroll payments; it also installs `accountant`, whose *In Payment* bill state keeps unconfirmed payments at *Paid* |
| `mail` | Chatter, approver followers, activities |
| `gec_localization` | Bank name and BIC from Georgian IBANs; `l10n_ge` chart with the `120410` Outstanding Payments account |
| `gec_payroll_bank` | *Pay Salaries*, the payroll adapter hooks on `account.payment.method.line`, the payment method setup check and the unsent-batch watchdog |

Python: `requests`.

---

## Gotchas & Non-Obvious Behavior

- **Two identifier spaces, one field.** In the bank's PDF, upload replies carry short letter-prefixed references (`I28`, `G6178`, `V216`, `T1582`), while `GetReport` items carry a numeric `BankInternalID` (`56722141`). Both are stored and compared in `basisbank_bank_internal_id`. [Likely] the statement-import matcher can therefore never confirm a single-transfer payment by bank id, and because it skips the `DocNum` route for payments that already hold a bank id, such payments are confirmed only by the 48-hour check, Resync or Reset to Pending, which do fall back to `DocNum`. Whether the bank echoes our `DocNum` on statement items is [Unverified].
- **Package sends give no per-payment reference.** Confirmation of a package member relies entirely on the bank echoing `DocNum` ([KNOWN_ISSUES.md](../custom_addons/gec_odoo_modules/basis_bank/KNOWN_ISSUES.md) B2).
- **Creating the connection makes old payments sendable.** The compute gives *Pending* to every outbound payment already on the company's Basis-BIC journals, so a posted, unmatched old payment shows **Send to Basis Bank** (KNOWN_ISSUES A3). Create the connection before the first payments on the journal.
- **Incoming lines never confirm anything.** By design. The *confirmed* counter of the wizard only counts outbound payments that were *Sent to Bank* before the import; a payment confirmed from *Not in Bank Report* is confirmed but not counted ([basisbank_statement_import_wizard.py:76](../custom_addons/gec_odoo_modules/basis_bank/wizard/basisbank_statement_import_wizard.py#L76)).
- **Import is not reconciliation.** A confirmed payment is *Reconciled* while the statement line and `120410` Outstanding Payments stay open until the accountant matches them (KNOWN_ISSUES B1).
- **Skips are silent to the user.** Items without `BankInternalID`, or where our IBAN is on neither side, are only counted and logged on the server. No opening or closing balance is written, so a gap does not trigger core's balance check (KNOWN_ISSUES B3).
- **The daily sync range overlaps on purpose.** Yesterday to today every day; duplicates are absorbed by the unique import id, so the *skipped* count is non-zero every morning.
- **The "Basis Bank" bank-feed option is a label only.** The module adds it to the journal's bank feed choices ([account_journal.py:87](../custom_addons/gec_odoo_modules/basis_bank/models/account_journal.py#L87)), but no code reads that value; imports run only through the wizard and the daily cron.
- **The approver can approve their own payment.** `user_can_approve()` only checks that the user is the approver or a delegate ([basisbank_approval.py:51](../custom_addons/gec_odoo_modules/basis_bank/models/basisbank_approval.py#L51)). Separation of duties depends on who is named. The approver record must belong to the connection's own company (KNOWN_ISSUES C1).
- **Core Validate is hidden on Basis batches** ([account_batch_payment_views.xml:22](../custom_addons/gec_odoo_modules/basis_bank/views/account_batch_payment_views.xml#L22)), so the only way out is **Send to Basis Bank**. The guard is in the view only: `validate_batch()` called from code still marks the payments sent without any bank call.
- **Bank code 6 (service suspended) marks payments Failed**, not retryable, although the transfer was never attempted (KNOWN_ISSUES B4). Reset to Pending after the service is back.
- **A single-send reply without our `ClientInternalID` uses its first item** ([account_payment.py:514](../custom_addons/gec_odoo_modules/basis_bank/models/account_payment.py#L514), KNOWN_ISSUES B5).
- **Tests cover only the payroll adapter** (2 tests). The send state machine, matching and crons are untested. `developer_map.html` in the module predates the Odoo 20 port (KNOWN_ISSUES D4).

---

## Related Docs

- [`INDEX.md`](INDEX.md)
- [`basisbank_api.md`](../basisbank_api.md) — endpoint-by-endpoint extraction of the bank PDF (project root)
- Module guides: [`README.md`](../custom_addons/gec_odoo_modules/basis_bank/README.md) (user), [`README_DEV.md`](../custom_addons/gec_odoo_modules/basis_bank/README_DEV.md) (developer), [`KNOWN_ISSUES.md`](../custom_addons/gec_odoo_modules/basis_bank/KNOWN_ISSUES.md) (open items)
- [`bank_journal_multicurrency_setup.md`](bank_journal_multicurrency_setup.md) — journal currency setup; the import wizard refuses a currency that differs from the journal's

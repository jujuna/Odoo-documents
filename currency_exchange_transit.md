# Currency Exchange and Transit Accounts — Odoo 20

> Reviewed against the local source on 2026-09-22. Core: [`account`](../addons/account/) and [`res.currency`](../odoo/addons/base/models/res_currency.py). Enterprise integrations: [`accountant`](../enterprise/accountant/), [`account_accountant`](../enterprise/account_accountant/) and [`account_reports`](../enterprise/account_reports/).
> Examples below are illustrative calculations, not newly verified transactions in a live database.

## What the Components Do

Multi-currency journal items keep both a company-currency amount and an amount in the line currency. Reconciliation can create exchange differences when those amounts settle at different valuations. A transit account separately tracks money moving between bank accounts until the two bank-side transactions are matched.

| Concept | Purpose |
|---|---|
| `balance` | Signed company-currency amount: debit minus credit |
| `currency_id`, `amount_currency` | Line currency and signed amount in that currency |
| `amount_residual`, `amount_residual_currency` | Remaining unreconciled amounts in the two currencies |
| Funds in Transit | Clearing account for inter-bank movements |
| Outstanding Receipts/Payments | Clearing accounts between payment registration and bank reconciliation |
| Bank suspense | Temporary counterpart before a bank transaction is categorized/matched |
| Exchange gain/loss | Adjustment arising from currency reconciliation |
| Currency revaluation | Separate period-end report/wizard for unrealized differences |

Transit, outstanding and suspense accounts are separate concepts even though some fallback code can use transit as an outstanding account.

## Configuration

1. Enable the Multi-Currencies group and activate the required currencies. The settings field `group_multi_currency` is defined in [`base_setup`](../addons/base_setup/models/res_config_settings.py).
2. Configure exchange rates and the appropriate currency on each bank journal. Automatic rate providers require an additional integration such as [`currency_rate_live`](../enterprise/currency_rate_live/).
3. Verify the company's transfer account and exchange journal/accounts.
4. Decide whether payment method lines should use outstanding accounts, according to the desired payment/bank reconciliation flow.

### Account Settings

Source: [`company.py`](../addons/account/models/company.py), [`chart_template.py`](../addons/account/models/chart_template.py), [`payment method lines`](../addons/account/models/account_payment_method.py).

| Field | Meaning / selector restriction |
|---|---|
| `transfer_account_id` | Inter-Banks Transfer Account; reconcilable `asset_current` |
| `currency_exchange_journal_id` | General journal for exchange differences |
| `income_currency_exchange_account_id` | Income-group account for gains |
| `expense_currency_exchange_account_id` | `expense` / `expense_other` account for losses |
| `account.payment.method.line.payment_account_id` | Outstanding account used by that payment method |

The chart template creates **Funds in Transit**, a reconcilable current asset, along with utility accounts for outstanding receipts/payments. Codes are derived from the chart's prefixes and code length; `101701`, `101403` and `101404` are not universal Odoo defaults. Chart data, localization and subsequent configuration determine actual codes and assignments.

The Account form exposes an optional forced currency; leaving it empty allows different line currencies. In the current Chart of Accounts list, the reconciliation toggle is hidden for cash, credit-card and off-balance types. A clearing account must be reconcilable for matching its items. A zero balance by itself does not mean its lines have been reconciled.

## Exchange Rate Lookup in This Checkout

Source: [`res_currency.py`, `_get_rates()`, `_get_conversion_rate()` and `_convert()`](../odoo/addons/base/models/res_currency.py).

Conversion resolves branch companies through their **root company**. Rates can be root-company-specific or shared. The local `_get_rates()` query selects a rate **strictly before** the requested date (`name < date`), then falls back to the earliest available rate, and finally 1.0 when no rate is found. It also returns the selected rate date alongside the rate.

This is a material implementation detail: a rate entered on a transaction date is not necessarily selected when an earlier rate exists. Do not assume a same-day rate is used without checking the result in this source/configuration. UI rate/inverse-rate representations also differ from a plain sentence such as “1 USD = 2.70 GEL.”

`_convert()` multiplies by the resolved conversion rate and normally rounds in the target currency. The examples below specify **effective accounting valuations**; they do not assume that merely entering those dated rates reproduces them automatically.

## When Payments Create Journal Entries

Sources: [`account_payment.py`](../addons/account/models/account_payment.py), [`accountant account_move.py`](../enterprise/accountant/models/account_move.py).

A payment's `outstanding_account_id` is computed from its payment method configuration. `_generate_journal_entry()` selects payments that have no move **and do have an outstanding account**. Therefore “Enterprise payments never create entries” is incorrect.

| Situation | Behavior |
|---|---|
| Outstanding account configured | Payment move can be generated using that account |
| No outstanding account and base invoicing behavior | `create()` fills a fallback account so payment accounting can proceed |
| No outstanding account and `_get_invoice_in_payment_state() == 'in_payment'` | No automatic fallback solely from ordinary payment creation; the payment can exist without its own move |
| `force_payment_move` context | Creation requests the fallback even with accounting behavior enabled |

The `'in_payment'` override is defined by **`accountant`** in this checkout, not by an assumption based only on the presence of `account_accountant`.

`_get_outstanding_account()` first resolves the appropriate chart-template Outstanding Receipts or Outstanding Payments account for the company root. Only if that is unavailable does it fall back to `company.transfer_account_id`; it raises an error if neither exists.

Enterprise bank reconciliation can match payments/underlying invoice items and accounts for the bank transaction. It also explicitly forces payment moves in selected flows, such as early-payment-discount handling. Do not assume every bank match creates a previously missing payment's own `move_id`; inspect the resulting statement and payment records. See [`account_bank_statement.py`](../enterprise/account_accountant/models/account_bank_statement.py).

## Example: Paying a USD Vendor Bill in a GEL Company

Assume a $5,000 bill is booked at an effective valuation of 2.70 GEL/USD and a full settlement at 2.75 GEL/USD. Ignore tax and fees for this example.

### Bill

| Account | Debit GEL | Credit GEL | USD amount |
|---|---|---|---|
| Expense | 13,500 | — | +5,000 |
| Payable | — | 13,500 | -5,000 |

### Settlement through a configured outstanding account

| Account | Debit GEL | Credit GEL | USD amount |
|---|---|---|---|
| Payable | 13,750 | — | +5,000 |
| Outstanding Payments | — | 13,750 | -5,000 |

The payable amounts match in USD but leave a +250 GEL residual. Reconciliation can correct it with:

| Account | Debit GEL | Credit GEL |
|---|---|---|
| Exchange loss | 250 | — |
| Payable | — | 250 |

The payable clears after that adjustment. Bank reconciliation subsequently clears outstanding payments against the bank transaction. If the payment has no accounting move, the settlement accounting is instead established through the bank flow; the exact line structure must be read from that result.

For `_get_exchange_account(company, amount)`, a positive residual-to-fix selects the loss account and a nonpositive amount selects gain. The sign of a customer's or vendor's currency payment alone is not the rule.

## Why Use Transit for an Internal Transfer?

Each move has one journal, but it can contain accounts associated with different banks. The old explanation that a single journal entry cannot debit one bank account and credit another is too strong. Transit supports **separate bank transactions, separate statement reconciliation and transfers in flight**, rather than satisfying an absolute cross-account restriction.

Typical flow:

```text
Source bank transaction:       DR Transit / CR Source bank
Destination bank transaction:  DR Destination bank / CR Transit
Then match the open transit items and resolve any genuine residual.
```

An unmatched balance can legitimately remain while funds are in transit. Completing the second bank transaction does not itself guarantee that the clearing lines were reconciled.

### Example: USD 138.66 Sent, EUR 120 Received

Assume the company currency is USD and the receiving transaction is valued at 1.1555 USD/EUR, with no fee.

| Transaction | Debit USD | Credit USD |
|---|---|---|
| Source bank: Transit | 138.66 | — |
| Source bank: USD bank | — | 138.66 |
| Destination bank: EUR bank | 138.66 | — |
| Destination bank: Transit | — | 138.66 |

Record/import both bank transactions. Categorize the first against Funds in Transit, then match the other transaction against the open transit item, reviewing the proposed currency amounts. The destination bank amount is EUR 120. The source bank amount is USD -138.66. Counterpart `currency_id` / `amount_currency` values depend on the reconciliation path and any forced account currency; they are not universally EUR on both transit lines.

With these exact valuations, the transit company balance is zero. A difference can arise from rates, actual bank conversion, fees, rounding or input errors. Classify a bank fee as a fee rather than assuming every difference is an FX adjustment. Even transactions on the same date can differ if their effective valuations differ.

### Paired Payments and the Transfer Action

The local payment model retains `paired_internal_transfer_payment_id` but does not define the old `is_internal_transfer`, `destination_journal_id` or `_create_paired_internal_transfer_payment()` implementation. A remaining dashboard action context includes `default_is_internal_transfer`; that context key does not restore the missing pairing logic.

Do not expect the transfer action to automatically create the destination-side payment. Account for both sides through the actual bank transactions or an intentionally designed manual-entry flow, then reconcile the clearing account. Avoid posting manual bank entries and later independently categorizing the same statement movement, which would duplicate the bank effect.

Source: [`account_journal_dashboard.py`, `open_payments_action()`](../addons/account/models/account_journal_dashboard.py), [`account_payment.py`](../addons/account/models/account_payment.py).

## Settlement in a Third Currency

A USD invoice paid in EUR in a GEL company requires more than subtracting two GEL totals. Reconciliation considers the selected reconciliation currency, foreign residuals, effective rates and the amount actually settled.

For example, EUR 2,760 × 2.94 = **GEL 8,114.40**, not GEL 8,114. A USD 3,000 invoice originally valued at GEL 8,100 has a historical difference of GEL 14.40 from that receipt. But at a settlement valuation of 2.75 GEL/USD, USD 3,000 corresponds to GEL 8,250. The receipt cannot simply be declared a full settlement with a GEL 14.40 exchange gain; it may leave an unpaid amount or require an explicit agreed adjustment. Review the remaining amount in the invoice currency as well as company currency.

## Reconciliation and Exchange-Difference Internals

Source: [`account_move_line.py`](../addons/account/models/account_move_line.py).

1. `reconcile()` delegates to `_reconcile_plan()` and `_reconcile_plan_with_sync()`.
2. Partial reconciliation preparation evaluates residuals and effective currency rates. Exchange corrections can be needed on either the company-currency or foreign-currency side; they are not limited to a single final invoice-closing event.
3. `_prepare_exchange_difference_move_vals()` builds balancing lines on the original account and the gain/loss account. An optional exchange analytic distribution applies to the gain/loss line.
4. `_create_exchange_difference_moves()` checks journal and gain/loss configuration, creates moves and posts the subset flagged `to_post`. It does not unconditionally post every generated move.
5. Reconciliation links are handled through `reconciled_lines_ids`; partial reconciliation retains `exchange_move_id` for its associated correction.

Dates are based on the exchange journal's accounting date and reconciled line dates, taking accounting-date restrictions into account. Context flags `no_exchange_difference` and `no_exchange_difference_no_recursive` control correction generation; internal creation uses them to avoid recursion.

Undoing a partial reconciliation processes its linked exchange move through `_unlink_or_reverse()`. Whether an entry is deleted or reversed depends on that move's protection/state; realized differences do not simply “stay forever” after an unreconcile. Source: [`account_partial_reconcile.py`, `unlink()`](../addons/account/models/account_partial_reconcile.py).

## Unrealized Currency Revaluation

The Enterprise [`Multicurrency Revaluation report`](../enterprise/account_reports/models/account_multicurrency_revaluation_report.py) and [`wizard`](../enterprise/account_reports/wizard/multicurrency_revaluation.py) are separate from automatic settlement exchange differences.

The wizard uses:

- `account_revaluation_journal_id`;
- `account_revaluation_expense_provision_account_id`;
- `account_revaluation_income_provision_account_id`;
- a valuation date and a required, editable reversal date.

It builds adjustments from the included report account/currency lines. The reversal date defaults to the report end plus one day, but is not hardcoded to that date. `create_entries()` posts the adjustment, creates its reversal, sets the selected reversal date and calls `action_post()` on it. Date/autopost behavior follows the normal posting machinery; do not describe this as merely creating an unposted reversal for a custom currency cron.

The wizard raises “No adjustment needed” when there are no adjustment lines. Check report inclusions/exclusions and prior adjustments before generating again. This process does not replace payment reconciliation or edit the historical invoice's original balance.

## Troubleshooting

| Symptom | Check |
|---|---|
| Payment has no journal entry | Outstanding account, payment state and `accountant` behavior; it may be an intended record-only payment |
| Wrong converted amount | Root-company rate selection, strict-before-date lookup, inverse-rate orientation, effective/manual valuation and rounding |
| Transfer has one side only | Import/record the other bank transaction; do not assume paired-payment generation |
| Transit balance is zero but items remain open | Reconcile the corresponding items; zero balance and reconciliation status differ |
| Residual on transit | Missing side, actual conversion spread, fees, dates, line currencies or duplicate entry |
| Exchange posting fails | Company exchange journal, gain/loss accounts and accounting restrictions |
| Unrealized adjustment does not match realized gain/loss | Different date, residual population, report settings and provisioning workflow |
| Reconciliation result changes after undo | Linked exchange moves can be removed/reversed and recomputed on the next reconciliation |

## Related Docs

- [Documentation index](INDEX.md)
- [Chart of accounts](accounting_coa.md)
- [Fixed costs and reconciliation](accounting_fixed_costs_guide.md)
- [Migration](accounting_migration.md)

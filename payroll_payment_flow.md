# Payroll Payment Flow — Stock Mechanics, Localization Standards, GEC Design Analysis

> Researched 2026-08-05 from Odoo 19 source (7-agent sweep, adversarially verified) + live DB `gec_modules_hr3`.
> Companion docs: [geo_payroll.md](geo_payroll.md) §10 (booking pattern decision), [../BASIS_SALARY_NET_PAYMENT_HANDOFF.md](../BASIS_SALARY_NET_PAYMENT_HANDOFF.md) (agreed fix plan, 2026-08-02).
> Status: **DECIDED + code shipped 2026-08-05** — Option B (standard net-payable layout) chosen after the accountant rejected 3160; `geo_payroll` 19.0.1.8.0 configurator + test updated, **19.0.1.9.0 adds a fingerprint-guarded migration** that realigns already-configured ge companies on upgrade (only rewrites rules still matching the old shipped mapping; custom accountant values untouched).
> **19.0.1.10.0 + basis_bank 19.0.1.12.0 (same day): NET-only payment filter in code** — user rejected both the account-type change on 3181/3182 (Payable→Current is required before un-reconciling, core constraint) and leaving multiple payments. AU-precedent solution instead: `hr.payslip.action_register_payment` override replaces the wizard's `active_ids` with the structure's NET-account lines; `account.payment.register._reconcile_payments` override flips the slip to `paid` when its NET lines are settled (stock demands every line at zero — open pension interims would block forever); `_basisbank_send_salaries` passes only NET lines (handoff Edit A; Edits B/C obsolete under the net-payable layout). 3181/3182 stay Payable+reconcilable — the accountant checkbox question is **dropped**. **Verified live on slip 36** (one payment 23.52 → NET reconciled → slip paid; withholding legs open by design). **basis_bank 19.0.1.13.0**: stale-salary-batch watchdog cron — a batch never transmitted within 48h of creation gets a one-time to-do activity + chatter note (slips read Paid while no money moved; the payment-level 48h guard can't see never-sent batches). Suite run + cleanup still pending (§6).

## 1. The stock payment chain (what the Pay button actually does)

| Step | What happens | Source |
|---|---|---|
| 1. Guard | `NET` rule's **Credit Account** must have `reconcile=True`, else `UserError: The credit account on the NET salary rule is not reconciliable`. Stock enterprise code. Also blocks: already-paid slips, untrusted employee bank (`allow_out_payment=False`), unposted move. | [hr_payslip.py:281-289](../enterprise/hr_payroll_account/models/hr_payslip.py#L281) |
| 2. Sweep | The button passes **ALL move lines** of the slip's entry to `account.payment.register` (`default_partner_id`=employee work contact, `payment_consider_partner=True`). It does NOT pre-filter to the NET line. | [hr_payslip.py:290-296](../enterprise/hr_payroll_account/models/hr_payslip.py#L290) |
| 3. Wizard filter | Keeps a line only if account type ∈ (`asset_receivable`, `liability_payable`) — extended with `liability_current` under the Pay-button context — AND residual ≠ 0. Non-reconcilable accounts always report residual 0, so they drop out silently. | [account_payment_register.py:952-965](../addons/account/wizard/account_payment_register.py#L952), [account_payment.py:11-15](../enterprise/hr_payroll_account/models/account_payment.py#L11), [account_move_line.py:773-778](../addons/account/models/account_move_line.py#L773) |
| 4. Batching | One payment per batch, key = `(partner, account, currency, partner_bank, partner_type)`. Same account+partner lines **net into one batch** (never opposite-direction pairs); different accounts or partners = separate payments. Direction = sign of the batch's summed balance. | [account_payment_register.py:265-283, 349-358, 388-389](../addons/account/wizard/account_payment_register.py#L265) |
| 5. Paid flip | Only under the Pay-button context (`hr_payroll_payment_register`), slip → `paid` **only when EVERY line of the slip's move has zero residual at that moment**. Any reconcilable line left open (transit legs, pension interims) blocks it permanently — the check never re-fires later. | [account_payment_register.py:24-42](../enterprise/hr_payroll_account/wizard/account_payment_register.py#L24) |

Two structural consequences:

- **Every open payable-type line gets its own payment.** Stock salary rules can carry a third-party `partner_id` (tax authority, insurer) — in stock designs extra payable lines are either real third-party debts or sit on non-reconcilable interim accounts and vanish at step 3.
- **The guard exists because a payment can only *close an open item*.** The payslip books "we owe employee X" as a credit on a reconcilable account; the payment books the opposite and reconciliation marries the two. Without a reconcilable NET credit account there is nothing a payment could ever settle — the debt would stay open forever and the slip could never become `paid`. With a bank account there (our 1210 case) it also protects against booking the cash outflow twice.

## 2. What stock localizations do (survey of all 25 l10n_*_hr_payroll_account modules)

No module ever sets `reconcile=True` in Python — the flag always comes from the country CoA CSV. The generic `_configure_payroll_account` only writes rule accounts/tags and the Salaries journal ([account_chart_template.py:26-67](../enterprise/hr_payroll_account/models/account_chart_template.py#L26)).

| Country | NET credit account | Type / reconcile | Deduction style | Pattern |
|---|---|---|---|---|
| AE | 201002 Payables | payable / **True** | liability in debit field (sign-flip) | standard |
| SA | 201002 Payables | payable / **True** | debit field | standard |
| JO | 200101 Payables | payable / **True** | debit field (tax/social also reconcilable) | standard |
| EG | 201002 Payables | payable / **True** | debit field; **interims 201026/201027 reconcile=False** | standard |
| US | 2300 Salary Payable | current / **True** | debit field → 2301 (reconcilable) | standard |
| IN | 300010 Salary Exp Payable | current / **True** | debit field (all reconcile=False) | standard |
| MX | 210.01.01 Provision | current / **True** | debit field | standard |
| HK | 2217 Salaries Payable | current / True | debit field (MPF reconcile=False) | standard |
| KE | 2220 Net Wages (intended) | payable / True | credit field | standard — **stock bug: mapping silently no-ops** |
| AU | 21300 Wages & Salaries | current / **True** | debit field; gross composed on expense 62430 | standard + ABA bank-file batch; duplicates the same NET guard in its run flow |
| **BE** | 455000 Remuneration | current / **False** | both fields mixed | **never uses the Pay button** — `batch_payroll_move_lines` forced on (button hidden), pays via SEPA files |
| **CH** | none — no NET mapping | transit 1090 asset / True | everything transits 1090 | **the only stock gross-clearing design** — net = residual on pass-through 1090; also batch/SEPA only, button hidden |
| LT, PL, RO, SK, TR, ID, MY, BD, LU, MA, NL, PK, FR | — | — | — | empty stubs, no mapping |

**The two stock families:**

1. **Wizard-flow countries** (AE/SA/JO/EG/US/IN/MX/HK/AU): earnings debit expense only; deductions park the liability in one field (engine sign-flips negative amounts — [hr_payslip.py:185-209](../enterprise/hr_payroll_account/models/hr_payslip.py#L185)); NET credits a reconcilable payable carrying the employee partner (`employee_move_line=True`). The slip move's open payable lines are few and each is a *real* debt.
2. **Batch-file countries** (BE/CH): booking style incompatible with the per-slip wizard → Odoo **hides the Pay button entirely** (`batch_payroll_move_lines`) and pays through SEPA batch files instead.

Even stock is imperfect here: KE and US ship silent mapping bugs; JO/US/AE leave withholding liabilities reconcilable, so their Pay button would also emit extra (legitimate, but partner-less) payments.

## 3. The GEC design measured against this

Georgian gross-payable booking (accountant's decision, [geo_payroll.md](geo_payroll.md) §10): earnings Dr 7410 / Cr 3130 at gross; PENSION_EE/PIT pull back out of 3130; NET moves the net from 3130 onward. This is **the Swiss family** — 3130 is our 1090 pass-through. Switzerland pairs that booking with batch payments and a hidden Pay button; we paired it with the wizard flow, which is the mismatch.

What each experiment hit:

| NET config | Result | Why |
|---|---|---|
| Cr **1210** (bank) | guard error (current state) | 1210 is `asset_cash`, never reconcilable; also the slip move itself would book the cash outflow — paying on top would double-book the bank |
| Cr **3160**, Dr 3130 | 5 payments (pension member) / 3 payments (non-member) | wizard sweeps every open payable line: 3130 no-partner batch (−net), 3130 partner batch (+net, *inbound*), 3160 partner (−net, the only real one), plus 3182/3181 pension interims (−0.60 each). The ± pair is on **different accounts** (3130 vs 3160), not a same-account artifact |

Beyond the visible junk payments, three quieter gaps:

1. **Paid-state deadlock.** Slip flips to `paid` only if *all* lines reach zero residual during the wizard run. Open transit legs (3130 trio) and open pension interims (3181/3182, reconcilable) block it forever. The handoff's Edit C reconciles the 3130 trio but does **not** cover pension members — their 3181/3182 lines stay open until the pension-agency payment, so their slips can never flip via the wizard. EG's precedent: interim accounts are `reconcile=False` (our 3325 PIT interim already is — the pension interims are not).
2. **Entry-less payments.** All 8 existing payments have `move_id=NULL` — journal 16 has no outstanding-payment account, so payments post no GL entry and reconcile nothing until bank-statement confirmation. Consequence: even a perfect single NET payment cannot flip the slip at wizard time in this journal configuration; the Basis flow's post-send settlement check would also trip on this.
3. **Account mismatch.** The reverted NET rule credits bank **1210** — an account attached to **no bank journal at all**. Journal map (verified 2026-08-05): 16 "ბანკი" → 1211, 19 "Basis Bank GEL" → 1212 (`is_basisbank`), 20 USD → 1213, 21 EUR → 1214. No payment flow could ever have matched a 1210 booking; manual Pay-button payments went through 1211, the Basis flow auto-picks journal 19 → 1212 (`_basisbank_salary_journal`: is_basisbank + type bank + company currency).

## 4. Options — **Option B chosen 2026-08-05** (accountant rejected 3160, which removed Option A's account; NET payable = 3130 itself). Code side shipped in `geo_payroll` 19.0.1.8.0: configurator remapped (earnings/PENSION_EE/PIT debit-only, NET credit 3130), `test_journal_entry_per_account_balances` re-asserted to the 1020-debit move + NET partner check, README rewritten. Remaining: hr3 UI rule edits (configurator skips configured companies), 3181/3182 reconcile checkbox (accountant), cleanup §6, Basis journal outstanding-account check.

| # | Option | Changes | Outcome | Risk |
|---|---|---|---|---|
| A **(recommended)** | Keep gross-payable booking; NET Dr 3130 / Cr 3160; implement handoff Edits A+B+C ([BASIS_SALARY_NET_PAYMENT_HANDOFF.md](../BASIS_SALARY_NET_PAYMENT_HANDOFF.md) §2): Basis flow passes **only NET-account lines** to the wizard, settlement check matches, transit trio internally reconciled | ~25-30 lines, one file (`basis_bank/models/hr_payslip.py`) | one outbound payment per employee = net; accountant's booking untouched | pension members still can't auto-flip to `paid` unless 3181/3182 become non-reconcilable (ask accountant); stock Pay button stays wrong unless given the same filter or left unused |
| B | Adopt the standard l10n pattern: earnings debit-only (drop Cr 3130 legs), PIT/PENSION liabilities via sign-flip only, NET credit-only → 3160 | config only (rule accounts in UI) + `reconcile=False` on 3181/3182 | stock Pay button works out of the box, one payment | overturns the accountant's locked gross-payable decision; loses gross visibility on 3130 |
| C | BE/CH style: enable `batch_payroll_move_lines`, never use the wizard | one company flag | button hidden, no junk possible | merged monthly moves — Basis flow explicitly warns shared moves can leak slips across the intended subset ([basis_bank.md](../basis_bank.md) 2026-07-12 audit); payment must be fully rethought |
| — | Never: `reconcile=True` on 1210, or NET credit = bank | — | silences the guard | books every salary out of the bank twice; breaks bank reconciliation |

## 4b. Authority payments — pension in the sweep, PIT pending (2026-08-06, `geo_payroll` 19.0.1.11.0)

The NET-only filter (19.0.1.10.0) deliberately dropped the withholding legs; the missing half
is now built on the stock third-party mechanism instead of a separate accounting routine:

- **Stock mechanism**: [hr_salary_rule.py:66](../enterprise/hr_payroll/models/hr_salary_rule.py#L66)
  `partner_id` ("eventual third party") is stamped on the rule's move lines by
  [hr_payslip.py:130](../enterprise/hr_payroll_account/models/hr_payslip.py#L130). The payment
  wizard batches per (partner, account, currency)
  ([account_payment_register.py:266](../addons/account/wizard/account_payment_register.py#L266))
  and only sees `asset_receivable`/`liability_payable` lines with open residual
  ([account_payment.py:209](../addons/account/models/account_payment.py#L209)).
- **geo_payroll 19.0.1.11.0**: pension rules (8, all 4 structures) ship the shared Pension
  Agency partner (`geo_payroll.partner_pension_agency`, upgradable `noupdate="0"` rule
  records — reaches existing DBs on `-u geo_payroll`). `action_register_payment` now passes
  **all open payable lines with a partner** and pre-sets `default_group_payment`; result per
  run = one NET payment per employee + one aggregated agency payment per pension account.
  A payable line without a partner raises, naming the rule. Paid-flip unchanged (NET settled).
- **PIT stays out — with a nuance found 2026-08-06**: the Pay button's view context
  (`hr_payroll_payment_register`,
  [hr_payslip_views.xml:30](../enterprise/hr_payroll_account/views/hr_payslip_views.xml#L30))
  makes enterprise add `liability_current` to the wizard's valid account types
  ([account_payment.py:13](../enterprise/hr_payroll_account/models/account_payment.py#L13)) —
  so 3320 is *type-eligible* from the button. It is still dropped because a non-reconcilable
  account has zero `amount_residual` and the wizard keeps only open-residual lines
  ([account_payment_register.py:958](../addons/account/wizard/account_payment_register.py#L958));
  the geo override applies the same residual rule. **Path (a) implemented 2026-08-06 in
  19.0.1.12.0**: `reconcile=True` on 3320 (type stays `liability_current`; flipped by the
  configurator for fresh companies and a guarded migration for existing ones — only the
  account the PIT rules book to, only when still off) + State Treasury partner
  (`geo_payroll.partner_state_treasury`) on the 4 PIT rules. Pay now yields NET per employee
  + pension agency payments + one aggregated treasury payment. Accepted caveat, accountant
  informed: gec_l10n_ge_tax resident-WHT postings on 3320 become open items to match against
  their treasury payments. Alternative (b) — retype unused 3325 — kept only if the
  accountant later rejects open items on 3320.
- **Bank layer untouched**: payments stay standard `account.payment`; basis_bank (or any
  future bank module) transmits its journal's payments — agency/treasury payments send as
  op 7 singles or a treasury batch (op 6), never inside the op 5 salary package
  (`_basisbank_net_payable_lines` keeps the salary batch NET-only).

## 5. Questions for the accountant

1. **3181/3182 pension interims: are they open-item accounts?** Do you match individual employee contributions against agency payments per employee, or settle monthly in aggregate? If aggregate → they should be `reconcile=False` like 3325 (EG precedent), which removes them from payment sweeps and unblocks the `paid` state.
2. **Who owns 3130's cleanliness?** In the gross-payable design 3130 nets to zero per slip but the three legs stay unreconciled open items. Is internal reconciliation per slip (Edit C) acceptable, or do you want 3130 statements clean by another process?
3. **Net-payable account** — accountant rejected 3160 (2026-08-05). Two coherent choices remain: (a) standard remap → **3130 Wages Payable itself becomes the net payable** (its literal purpose; used once per slip, no new account needed); (b) keep gross-through-3130 → accountant must name another reconcilable payable for the employee net debt; it cannot be neither.
4. **Which bank account is salary cash paid from** — 1210 or 1211? The current data contradicts itself.
5. Confirm the still-pending hr3 rule edits from the earlier round: PIT → 3320 vs current 3325 interim, PENSION_ER expense → 7490 vs current 7411.
6. Is the `paid` state on payslips operationally required (reports, HR queries), or is payment tracking in Accounting sufficient? (Determines how hard we must fight gap #1.)

## 6. Current garbage in gec_modules_hr3 (cleanup list, do not mistake for regressions)

- Payments 1-5 (July, Abigail) and 24-26 (Aug 5, Aka Foster): all `in_process`, `move_id=NULL`, zero GL impact, orphaned from deleted slip moves → cancel when convenient. (Extends handoff §5 list.)
- Payslip 10 (Abigail July) back in draft, move deleted; payslip 36 (Aka Foster Aug) validated on move 49 which credits bank 1210 directly — must be reset/recomputed after the NET rule decision.
- Only struct 7 (GEO Daily) NET rule has accounts at all; GEO Monthly/Hourly/Unit NET rules are empty → same guard error awaits them.
- Mitchell Admin June duplicates (slips 3, 4) — pre-existing, see handoff §5.

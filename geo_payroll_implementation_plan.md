# GEO Payroll — Final Implementation Design

> Module: `geo_payroll` · Odoo 19 Enterprise · current version: **19.0.1.5.0**
> (19.0.1.4.0 added PIT 20% + pension 2%+2% rules, the `pension_fund_member` field and the
> ge-chart account auto-configuration; 19.0.1.5.0 made PIT self-contained, empty timesheet-project
> allowlist = all projects for additive schemes, and the configurator virgin-companies-only — see
> [`geo_payroll.md`](geo_payroll.md) §10 for the current accounting reality.)
>
> This document records the design that is actually built after the review and hardening passes.
> Earlier proposals in `PAYROLL_WAGE_TYPES_PLAN.md` are historical and do not override this file.

The user-facing behavior is explained in [geo_payroll.md](geo_payroll.md). Manual verification is in
[geo_payroll_testing.md](geo_payroll_testing.md).

---

## 1. Locked decisions

1. One `pay_scheme` field represents six supported salary schemes.
2. Pure Daily salary is paid only from approved Daily Work Logs.
3. Pure Hourly base salary is paid only from Odoo work entries.
4. Timesheets are additive only for Fixed + Hourly and Daily + Hourly.
5. Overtime is an independent optional work-log component.
6. Approved work-log amounts are frozen at approval. Timesheet amounts are frozen when claimed.
7. Late eligible items may carry forward to a later regular payslip at their work-date rate.
8. Only an unedited regular base payslip using the version's default structure may create claims.
9. No data-migration script is included. Legacy hidden source values repair themselves on the next
   relevant contract-version save.
10. ~~Georgian PIT, pension, complete accounting configuration, and tax correctness are outside
    this module's current scope~~ — superseded 2026-07-15: PIT/pension rules + ge-chart account
    configuration now live in this module (19.0.1.4.0+); remaining tax gaps are the salary
    declaration export and the accepted limitations listed in `geo_payroll.md` §16.

---

## 2. Scheme mapping

| Pay Scheme | Technical wage type | Base | Scheme addition |
|---|---|---|---|
| Fixed | monthly | Odoo work entries × monthly wage logic | — |
| Hourly | hourly | paid work-entry hours × hourly wage | — |
| Daily | daily | approved Daily logs × daily wage | — |
| Fixed + Daily | monthly | Fixed base | approved Daily logs |
| Fixed + Hourly | monthly | Fixed base | validated allowed timesheets |
| Daily + Hourly | daily | Daily-log base | validated allowed timesheets |

`pay_scheme` drives two stored readonly flags:

- `worklog_daily_enabled` for Fixed + Daily;
- `timesheet_extra_enabled` for Fixed + Hourly and Daily + Hourly.

`worklog_ot_enabled` stays independent because overtime may be added to any scheme.

The chosen Salary Structure Type must have the same technical wage type as the scheme. A constraint
rejects mismatches instead of silently selecting a different structure.

---

## 3. Hidden source fields

> **Superseded 2026-07-14 for `hourly_source` — see §13.** `hourly_source='timesheet'` is now a
> shipped, visible mode for the pure Hourly scheme (inherited across version creates, guarded by
> the §13 routing guard). This section's "unsupported" framing still applies only to
> `daily_source='calendar'` and to `timesheet` on non-Hourly schemes, which the normalizer still
> repairs.

`daily_source` and `hourly_source` were originally compatibility fields with their alternative
modes disabled.

| Field | Supported value | Compatibility value |
|---|---|---|
| `daily_source` | `work_log` | `calendar` (still rejected) |
| `hourly_source` | `work_entry`, `timesheet` (Hourly scheme only, since §13) | `timesheet` on other schemes (normalized away) |

`hr.version.create()` and `write()` enforce the supported values server-side. The same normalizer sets
the technical wage type from the chosen scheme, including Odoo's protected-copy
`employee.create_version()` path. This covers the form, imports, RPC, templates, and automated
actions. The constraints remain as a final invariant check.

The employee fields are writable related mirrors of the current `version_id`. They are not separate
copies: reading the employee reads the current version, and changing the employee writes that version.
Changing which version is effective automatically changes what the employee mirror displays; it does
not rewrite other historical versions.

### Why there is no migration

Changing a Python default never rewrites existing stored rows. Older versions can therefore contain
`daily_source='calendar'`. Instead of a bulk migration, the next relevant version save normalizes the
hidden values in the same transaction. A user can switch an old employee to Daily without exposing or
manually editing the technical field.

The runtime is safe before that save as well:

- Pure Daily always routes approved Daily logs to `daily_basic`.
- No calendar-priced Daily payslip branch remains.
- No new hourly-timesheet-base claim can be created.

Since §13 (2026-07-14), the `timesheet_basic` route is live: the shipped structures all contain a
`TIMESHEET_BASIC` salary rule and Hourly-from-Timesheets versions create such claims.

---

## 4. Salary amount flow

### Fixed and Hourly base

Odoo generates work entries and worked-day lines. Stock `paid_amount` pricing supplies `BASIC`:

- Fixed uses Odoo's monthly proration logic.
- Hourly uses paid work-entry hours × `hourly_wage` × work-entry-type rate.

The module does not replace work-entry generation or `work_entry_source`.

### Daily base

Odoo worked-day lines may still exist, but their Daily amount is zero because no calendar day units
are assigned. Approved Daily logs create frozen `daily_basic` settlements. The `DAILY_BASIC` salary
rule sums those settlements.

```text
approved units × daily_wage frozen at approval → daily_basic settlement → DAILY_BASIC
```

### Fixed + Daily

The Fixed base remains `BASIC`. Approved Daily logs are frozen as `worklog_daily` and paid by
`WORKLOG_DAILY`.

### Timesheet additions

A timesheet can become `timesheet_extra` only when all eligibility checks pass:

- validated;
- correct employee and company;
- positive and no more than 24 hours on one line;
- date covered by an employee contract version;
- project in the version's payroll allow-list;
- date on or after `timesheet_pay_start_date`;
- enabled additive-timesheet scheme and positive hourly rate;
- not a holiday, global-leave, or work-log-generated analytic line;
- no existing active claim.

The amount uses the version active on the timesheet date:

```text
timesheet hours × work-date version hourly_wage → timesheet_extra settlement → TIMESHEET_EXTRA
```

### Overtime

Approved overtime uses:

```text
hours × hourly_wage × percentage
```

Approval freezes the version, rate, amount, component, and currency. Hourly employees paid from
Attendances cannot approve custom overtime logs because attendance hours already reach the base pay.

---

## 5. Settlement ownership and lifecycle

Every payable work log or timesheet is represented by an immutable
`hr.payroll.component.settlement` row. Partial unique indexes allow only one active claim per source.
Row locks serialize concurrent claims.

The destination must be:

- draft;
- regular base pay, not a refund or correction;
- unedited;
- the same employee/company;
- dated on or after the source item;
- using the contract version's default salary structure.

Recompute is idempotent: valid claims stay attached; only stale claims are released; new eligible
items are then claimed. Cancel and deletion release active claims. Pay-run deletion releases child
claims before PostgreSQL cascades the payslip deletion.

At confirmation:

- overlapping regular payslips are blocked to prevent duplicate base salary;
- claim identity/source amounts are revalidated;
- unclaimed eligible sources block confirmation;
- each custom salary line must equal its settlement total.

Refunds and corrections follow Odoo's origin-based lifecycle, and component totals walk to the root
original. Validation requires every active positive correction to have one active refund that exactly
reverses the origin's salary lines. The rule is aggregate, so it supports multiple pairs without
inventing a second pairing model; Odoo's legitimate refund-only flow stays valid. Cancelling a refund
is blocked only when that would leave more active corrections than refunds.

---

## 6. Configuration changes without destructive resets

The module declares every GEO payroll input that can change a draft result:

- scheme, wage type, and Salary Structure Type;
- monthly, hourly, and daily rates;
- overtime enablement;
- hidden sources;
- timesheet project allow-list and cutoff date.

When one changes, only true regular base payslips that are draft and unedited are refreshed. If the
Salary Structure Type changed, those payslips move to the version's new default structure first.

If a version changes while its base payslip is cancelled, the slip is outside the draft-refresh
domain. When the user explicitly sets that regular base slip back to Draft, it is aligned and
recomputed. Special slips remain excluded. Confirmation also rejects a Daily base slip containing
nonzero schedule-based `BASIC`, closing the pre-upgrade stale-line path.

The transition does not clear:

- `wage`;
- `hourly_wage`;
- `daily_wage`;
- `worklog_ot_enabled`;
- timesheet projects;
- timesheet cutoff date.

It also does not rewrite validated/paid history, refunds, corrections, off-cycle structures, or
manually edited slips.

Approved work logs keep their frozen component/rate/amount even if the later live configuration
changes. Timesheet eligibility and rate are re-evaluated while the owning payslip is still draft.

---

## 7. File-by-file implementation

| File | Responsibility |
|---|---|
| `models/hr_version.py` | Scheme fields, computed flags, wage type, source normalization, constraints, draft refresh, template whitelist |
| `models/hr_employee.py` | Related/inherited mirrors from the current version |
| `models/hr_payroll_structure_type.py` | Adds the Daily wage type |
| `models/hr_employee_work_log.py` | Workflow, permissions, uniqueness/hour caps, approval routing, frozen snapshots |
| `models/account_analytic_line.py` | Prevents edits/deletion while a timesheet has an active payroll claim |
| `models/hr_payroll_component_settlement.py` | Immutable claim ledger and one-active-claim constraints |
| `models/hr_payslip.py` | Claiming, carry-forward, stale-claim release, confirm guards, corrections |
| `models/hr_payslip_run.py` | Releases claims before pay-run cascade deletion |
| `models/hr_payslip_worked_days.py` | Daily worked-day amount behavior |
| `data/payroll_structure_data.xml` | Three GEO structures and conditional component salary rules |
| `views/hr_version_views.xml` | Scheme/rate/timesheet configuration; shows Hourly Source for the Hourly scheme (§13), hides `daily_source` |

No stock Odoo file in `addons/` or `enterprise/` is modified.

---

## 8. Security and integrity guards built

- Work-log x2many sudo-command bypass is disabled.
- Normal employees can work only with their permitted logs and cannot approve themselves.
- Approval requires contract coverage, a live pay route, and a positive rate.
- Daily units are limited to one per employee/date; overtime is capped at 24 aggregate hours per date.
- Claimed timesheet source fields cannot change until the claim is released.
- Currency and component snapshots prevent later company/configuration changes from silently repricing
  an approved work log.
- Rule-existence and default-structure gates prevent a source from being locked by a slip that cannot
  actually pay it.
- Active-claim unique indexes and row locks prevent concurrent double claims.
- A second overlapping regular payslip is blocked at confirmation.
- Hidden payroll-source inspection uses a privileged read without elevating the caller's write; HR
  managers without Payroll can edit HR-owned version fields but retain Odoo's contract-date limits.
- Stale settlement release is a privileged internal ledger operation, so a payroll officer with the
  intended read-only ledger ACL can still recompute a draft payslip.
- Positive corrections cannot validate without one exact, active origin reversal per correction.

---

## 9. Build status

| Area | Status |
|---|---|
| Six schemes and three wage types | Built |
| Approved Daily Work Log base | Built |
| Fixed + Daily | Built |
| Fixed/Daily + timesheet additions | Built |
| Independent overtime work logs | Built |
| Frozen settlement ledger and carry-forward | Built |
| Pay-run deletion claim release | Built |
| Old hidden-source transition repair | Built in 19.0.1.1.1 |
| Safe draft base-payslip refresh | Built in 19.0.1.1.1 |
| Pay-run reopen/type-change refresh | Built in 19.0.1.1.2 |
| Off-cycle stale-claim release | Built in 19.0.1.1.2 |
| Immutable-ledger RPC-context hardening | Built in 19.0.1.1.2 |
| Non-payroll HR version-write and payroll-officer stale-release fixes | Built in 19.0.1.1.3 |
| Correction/refund financial balance guard | Built in 19.0.1.1.3 |
| Scheme/type normalization in copied versions | Built in 19.0.1.1.3 |
| Calendar-priced Daily | Not supported; runtime branch removed |
| Hourly base from timesheets | Not supported; runtime route disabled |
| Georgian PIT/pension/full gross-to-net | Built in 19.0.1.4.0+ (member-conditional 2%+2%, PIT 20% on pension-reduced base, gross-payable journal mapping) |
| Confirm-time accounting/journal blocker | Not built |
| Automated regression suite | Shipped in 19.0.1.1.2; manual guide retained |

---

## 10. Remaining production blockers

The module should not yet be sold as complete Georgian payroll because:

1. Timesheets have a 24-hour per-line limit but no aggregate employee/date ceiling.
2. Ordinary project timesheets can overlap paid or unpaid leave.
3. Native attendance/planning overtime and custom overtime are not fully reconciled.
4. A privileged direct `validated=True` timesheet write can bypass normal timer/future-date workflow.
5. Work-log company follows the employee's current company; transfers can strand an old-currency log.
6. A manager can create and approve a direct report's payable log; stronger segregation may be needed.
7. Georgian PIT/pension and account auto-configuration exist since 19.0.1.4.0; still absent:
   salary declaration export, confirm-time missing-journal blocker, effective-dated pension
   membership (accepted), and the Employer Cost dashboard composition is pending accountant review.
8. The suite verifies unique indexes and locking invariants, but it does not yet run a true
   two-worker concurrent compute race or browser/timer end-to-end workflow.

Resolved 2026-07-13 by the version-split rework (former blockers 1-3): version-aware overlap guard,
per-version base segmentation, and leaf-first correction-chain lifecycle — see §12.

These are release decisions, not hidden implementation details. Keep them visible in sales and
production-readiness reviews.

---

## 11. Manual release gate

Before any production deployment:

1. Upgrade the module and confirm version `19.0.1.2.0`.
2. Run every case in [geo_payroll_testing.md](geo_payroll_testing.md).
3. Test an existing employee switching from Monthly/Hourly to Daily.
4. Verify the switch preserves all rates and optional configuration.
5. Verify an existing draft base payslip changes structure and recomputes.
6. Verify validated and paid history does not change.
7. Verify refunds, corrections, and off-cycle slips are not automatically reset by version edits.
8. Reconcile `BASIC + custom components + deductions = GROSS/NET` against expected payroll results.
9. Run real Georgian payroll scenarios only after the missing tax/accounting layer is implemented.

---

## 12. Version-split rework (2026-07-13)

Design settled after a three-round adversarial review (Claude + Codex, both fact-checking against
enterprise source) and verified by the complete automated regression suite. Approved business consequences:
every `hr.version` effective inside a period — including administrative-only changes — produces a
separate full-period payslip, PDF, and payment line; manual flows must create all sibling drafts
before confirming any; HR still dates versions on period boundaries whenever possible.

Why full-period slips: work entries are version-bound and a payslip aggregates only its own
version's entries, so standard `OUT` lines prorate each slip to its slice. A clipped slip instead
divides the full fixed wage by its own attendance hours and **overpays** (1,600 + 2,000 instead of
800 + 1,000 for a Jan 16 change); standard's own selection picks one version per contract and
**underpays** (the post-change slice gets no slip at all).

| Change | Where |
|---|---|
| Slice-complete version selection (same filters as standard, slice intersection in Python — `date_start/date_end` search maps to contract dates) | `hr_payslip_run.py::_get_valid_version_ids` |
| Version-aware duplicate-base guard (same version + date overlap only) | `hr_payslip.py::_gec_check_no_overlap` |
| Shortened fixed-wage slips blocked at validation | `hr_payslip.py::_gec_check_full_schedule_period_for_fixed_wage` |
| Claim windows per version slice; earliest slice in the period owns carry-forward (order-independent, covers mid-period contract starts) | `hr_payslip.py::_gec_claim_window` + both candidate domains + `_gec_check_claims` + `_gec_settlement_still_valid` |
| Version coverage gate: every employed slice needs exactly one regular slip (existence, any non-cancelled state) at slip confirm and run validate | `hr_payslip.py::_gec_check_version_coverage`, `hr_payslip_run.py::action_validate` |
| Leaf-first correction lifecycle: live descendants block cancel/draft-reset (batch chain allowed), any descendants block delete; run delete/reset guarded too | `hr_payslip.py::_gec_check_no_live_descendants`, `_gec_descendant_slips`, ondelete hooks, `hr_payslip_run.py` |
| Financial correction balance: each active correction needs one exact active reversal; refund-only remains supported | `hr_payslip.py::_gec_check_correction_chains`, `_gec_check_correction_balance_after_removal` |
| Settlement audit field `source_version_id` (work log's approval version / version at timesheet date) | `hr_payroll_component_settlement.py`, both claim creators, settlement views |

Open follow-up: standard `action_draft_linked_entries` is version-blind; the
`test_cancelling_one_slice_slip_preserves_the_other*` sentinels decide whether a version-aware
override is needed. Pre-change snapshot: `geo_payroll_freeze_2026-07-13_pre_v2.tar.gz` next to the
module.

## 13. Hourly-from-Timesheets — locked specification (2026-07-14) — IMPLEMENTED

Unlocks P0 decision #2 (§9). Settled over four adversarial review rounds (Claude + Codex, all
claims verified against module and enterprise source). **Implemented 2026-07-14** (module
19.0.1.2.0): every build item below shipped, plus `tests/test_timesheet_hourly_base.py`
(policy math, guards, routing, waiver, caps, cross-scheme carry-forward, pay-run lifecycle) and
updates to the routing-affected legacy tests. The per-day aggregate cap and the OT exclusion also
closed two §8 known limitations. Waiver wizard shipped as `gec.payroll.timesheet.waiver`
(Payroll > Waive Timesheet Pay, manager-only, permanent per-line stamp excluded from claiming and
from the strandable query).

**Post-implementation review hardening (same day, round 6):**

- Strandable set now includes lines **claimed by a draft payslip** (their claim is released by the
  recompute a routing flip triggers, stranding them just the same); lines claimed by validated/paid
  slips are being paid and never count. Flow: cancel/recompute the draft, waive, then flip.
- Waiver wizard validates the selection against the exact strandable set (rejects unvalidated,
  claimed, wrong-project, out-of-slice, or never-payable lines), locks the lines and re-checks
  claims before writing — no unrelated-line waivers, no waive/claim race.
- Routing guard locks the employee row, serializing with payslip confirmation's overlap lock — the
  finalized-payroll protection cannot be raced by a concurrent pay-run validation.
- Waived lines cannot be deleted (audit evidence); restore = manager clears the stamp (documented
  limitation: no dedicated audited restore action).
- Confirm-time claim check now enforces the settlement invariant literally: `source_version_id`
  must equal the version active on the line's work date and the amount must equal the current
  work-date rate × hours (`_gec_settlement_still_valid` gained the same source-version equality, so
  stale rows release and re-claim on recompute).
- Accepted as correct, not fixed: unvalidated draft timesheets never block a routing change —
  after leaving Timesheets mode they validate as ordinary non-payroll lines, because work entries
  pay that period (paying them too would double-pay).

**Round 7 hardening (2026-07-14, second post-implementation review):**

- Clause 1 also blocks routing edits on a version whose **finalized carried-forward settlements**
  exist elsewhere (`source_version_id` search): a validated Feb slip paying a Jan-priced line
  locks the Jan version's routing — otherwise the invariant breaks live and Jan's own later slip
  double-pays those hours.
- The strand guard now also covers **project allow-list narrowing and cutoff moves** on
  Timesheets-mode versions (m2m command resolution pre-write; widening is free). Extras schemes
  stay outside by explicit policy (additive component; documented in geo_payroll.md §8).
- Waiver stamps are now writable **only** through `_gec_write_waiver` (work-log `_write_workflow`
  precedent): direct writes rejected for everyone incl. sudo/RPC; new manager-only
  `action_gec_restore_payroll_pay` clears all three stamps together; waived lines' identity
  fields (`_GEC_LOCKED_FIELDS`) frozen while waived.
- Claim path re-runs the **full** eligibility predicate after `lock_for_update()` with a full
  cache invalidate (was: settlements-only) — closes the waive-vs-claim race from the claimant's
  side.
- Guard message corrected: draft claims are released by cancelling/deleting the draft
  (recomputing an unchanged payslip keeps a valid claim).
- Held as policy, not fixed: wage edits after finalized payroll stay allowed — unclaimed lines
  deliberately price at the work-date version's current wage (corrections apply to unpaid work;
  finalized settlements keep frozen amounts). Documented in geo_payroll.md.

### Business policy (accepted by business 2026-07-14)

When `pay_scheme = hourly` and `hourly_source = timesheet`, gross base pay equals eligible
validated timesheet hours × the work-date version's `hourly_wage`. **Nothing else pays**: work
entries (Working Schedule, Attendances, Planning), paid leave, public holidays, overtime work
logs, and daily work logs all contribute zero money. No fallback to work-entry pay.

Explicitly accepted consequences — recorded so nobody rediscovers them:

- An employee on approved paid leave or a public holiday earns **0** for those hours.
- **No premium pay is possible in this mode.** Blocking overtime work logs removes the module's
  only >100% mechanism: overtime, night work, and hours worked on a public holiday all pay flat
  100% through timesheets. Staffing must avoid legal-overtime situations for these employees, or
  the premium obligation accrues with no way to pay it (Georgian labor-law risk — flagged,
  business accepted).
- A zero payslip with no eligible timesheets is **correct**. A zero payslip despite eligible
  timesheets (missing rule, wrong structure, edited slip) is an **error** and must be blocked.
- Late-validated timesheets carry forward and pay in a later slip at their work-date rate,
  including across a later scheme/source switch.

Examples at 10 GEL/hour: 160 work-entry hours + no timesheets → 0; 160 work-entry hours +
12 eligible validated timesheet hours → 120; 8h approved paid leave → 0; unvalidated or
disallowed-project line → 0.

### Core invariant (three clauses, per source version — never per destination slip)

1. Every `timesheet_basic` settlement's `source_version_id` is `hourly + timesheet` **at the
   line's work date**.
2. A slip whose own version is timesheet-mode has zero work-entry base (worked-day amounts and
   BASIC line both 0).
3. A work-date version in work-entry mode never produces `timesheet_basic` (resolver branches
   per work-date version).

Per-destination-slip exclusivity is wrong: after a source switch, one slip may legitimately hold
positive work-entry `BASIC` (its own period) plus positive `TIMESHEET_BASIC` (carried forward
from a timesheet-mode period).

### Build items

| Item | Where | Notes |
|---|---|---|
| `TIMESHEET_BASIC` rule, category BASIC, on **all three** GEO structures | `payroll_structure_data.xml` | Hourly-only would strand cross-scheme carry-forward (Jan hourly-timesheet → Feb fixed, late Jan line); matches the existing `DAILY_BASIC`/`TIMESHEET_EXTRA` pattern |
| Public predicate `payslip.gec_uses_timesheet_hourly_base()` | `hr_payslip.py` | Non-underscore (safe_eval rejects `_` attrs; precedent `gec_component_total`); reads version via `sudo()`; single driver for the rule, zeroing, guards, simulation, reports |
| Conditional worked-day zeroing for hourly+timesheet slips | `hr_payslip_worked_days.py::_compute_amount` | Clone the Daily filter incl. `edited`/`state`/no-version/`OUT` guards; **the one override that can regress work-entry employees** — highest review priority |
| BASIC rule branch to 0 in timesheet mode | structure data | Defense in depth + fixes salary simulation (`version` is in the v19 rule localdict). Daily has the same sim artifact today — fix in a **separate** follow-up change, never bundled |
| Resolver branch: `_gec_timesheet_component_code` → `timesheet_basic` for hourly+timesheet work-date versions | `hr_payslip.py` | Component still resolved per work-date version, priced at the work-date rate |
| Shared eligibility predicate extracted from `_gec_timesheet_payable` | `hr_payslip.py` | One version-scoped helper consumed by the claim path, `_gec_check_unclaimed`, and the routing guard — never a hand-copied condition list |
| Config gate as version constraint | `hr_version.py` | Timesheet mode requires: positive `hourly_wage`, `timesheet_pay_start_date`, non-empty project allow-list, default structure containing `TIMESHEET_BASIC` in category BASIC |
| Source inheritance across version creates | `hr_version.py::_normalize_payroll_values` | Replace force-reset/legacy-repair with per-scheme validation; today `create(force_sources=True)` resets the source on **every** dated contract edit — the top silent-flip hazard |
| Four-clause routing guard on in-place `hourly_source`/`pay_scheme` writes | `hr_version.py::write` | See below |
| Confirm guard keyed on the slip version's mode, independent of `_gec_can_claim` | `hr_payslip.py` | Timesheet-mode regular slip: default struct required, `edited` blocked (Daily-guard precedent), rule present, worked-day base provably 0; zero settlements allowed only when zero eligible lines exist |
| Per-date aggregate cap ≤ 24h/employee/date across lines | claim path | Closes the pinned 30h/day known limitation for base pay |
| OT exclusion (two enforcement points) | `hr_version.py` + `hr_employee_work_log.py::action_approve` | Constraint: `worklog_ot_enabled` cannot be set on hourly+timesheet; approval guard mirrors the existing hourly+attendance block. Pre-switch approved OT logs stay payable via their frozen snapshot — intentional, do not "fix" |

Daily work logs need no new code: pure hourly has no daily route today
(`_resolve_component_code` → False → approval already refuses with "no pay route").

### Four-clause routing guard (server-side; warnings are form-only and bypassed by RPC/imports)

1. Version has a validated/paid regular slip → **block** any in-place routing change; require a
   new dated version. Stock work-entry `BASIC` has no settlement ledger row, so this is the only
   thing preventing a mutated version from double-paying a late timesheet over already-paid
   work-entry hours. Also makes live-field reads in the invariant sound.
2. Leaving timesheet mode would strand eligible validated unclaimed lines → **block** with
   count/list, unless a Payroll-Manager waiver wizard is used: per-line **permanent** stamp
   (reason, user, date, line IDs), waived lines excluded from both the strandable query and all
   future claiming (else a later flip-back resurrects them), reversal only by a manager clearing
   the stamp. The wizard is the *only* real abandonment path — a dated version deliberately keeps
   old-slice lines payable via carry-forward, and settling pays hours that should not pay.
3. Only draft slips/claims exist → allow; existing recompute triggers + idempotent stale-claim
   release handle the rest.
4. Entering timesheet mode → config constraint must pass; form-only onchange preview of how many
   historical validated lines become payable.

Resulting state machine: every validated timesheet is in exactly one auditable state —
**paid / claimable / waived**.

### What stays untouched (regression assertions)

- `work_entry_source` selection and all three generators; work-entry generation, leave
  processing, and conflict validation (conflicts still block timesheet-mode payroll — payslip
  `error_count` gates `compute_sheet`; `action_payslip_done` validates period entries).
- Existing `hourly_source = work_entry` employees: the same DB and work entries must produce
  byte-identical worked-day lines and salary-line totals before/after upgrade (draft recompute
  and untouched validated slips both compared). All standard hourly money math funnels through
  `hr_payslip_worked_days._compute_amount` + `_get_paid_amount` only; the attendance/planning
  payslip extensions are stat-buttons.
- Settlement lifecycle, corrections/refunds (generic per `(rule_id, code)`), carry-forward.

Estimated effort: 1–2 days mechanics, 5–8 days production-safe incl. the regression matrix
(per-source × full/partial month × leave/holiday × transitions × corrections), plus payroll UAT.

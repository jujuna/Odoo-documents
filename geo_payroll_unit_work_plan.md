# GEO Payroll — Unit Work (Piecework) Extension: Locked Specification

> Status: **IMPLEMENTED 2026-07-14, round-4 and round-5 review fixes applied** (module
> 19.0.1.3.0). Codex's empirical reviews: suite 242/243 green on a disposable upgraded DB after
> hand-repairing R4-1; round 5 caught the repair hook's `<function>`/`call_kw` signature defect
> (R5-1) that broke both fresh install and upgrade. All five findings fixed in source — final
> clean fresh-install + 1.2.0→1.3.0 upgrade + suite run still pending. Decided 2026-07-14 with
> the business; review history in §12.
> Shipped per this spec plus `tests/test_unit_work.py` (catalog, hygiene, routing matrix, freeze,
> display, math, guards, split, corrections, pay-run, upgrade-repair helper) and the 8-scheme
> transition matrix; user guide and testing guide updated (Cases 8/9, Part 4C).
> Target: `geo_payroll` 19.0.1.2.0 → **19.0.1.3.0**, extended in place (no new module).
> This is the single shared spec for both implementing agents (Claude + Codex). It consolidates
> both draft plans; §12 records what was corrected between them, so do not re-litigate those points.
>
> Behavior reference for the existing module: [geo_payroll.md](geo_payroll.md).
> Design history: [geo_payroll_implementation_plan.md](geo_payroll_implementation_plan.md).

---

## 1. Requirement and locked business decisions

Construction piecework: a catalog defines unit work types (name + UoM + price per unit, e.g.
"Tile laying, 1 ft² = 10 GEL"). Employees file Work Logs of a new type **Unit** (date, catalog
item, quantity); approved unit logs pay through the settlement ledger exactly like Daily logs do.

Decisions confirmed by the business (2026-07-14):

| # | Decision |
|---|---|
| 1 | Exactly **two new Pay Schemes**: `unit` (Per Unit — unit logs are the whole base) and `daily_unit` (Daily + Per Unit — daily logs are the base, unit logs are an addition). No Fixed + Unit, no Hourly + Unit. |
| 2 | The UoM is a **label**: the catalog item fixes it, the Work Log displays it read-only, quantity is entered in that unit. **No UoM conversion** (v19 removed `uom.category`; there is no native compatibility scoping — [uom_uom.py:17](../addons/uom/models/uom_uom.py#L17)). |
| 3 | The rate catalog is **global** — shared across all companies, one price everywhere. No `company_id` on the model. Safety comes from an approval-time currency-match refusal, not per-company rows. |
| 4 | Amounts **freeze at approval** (existing Daily/Overtime pattern). No effective-dated price history: editing a catalog price affects only future approvals; approved logs and settlements never reprice. |
| 5 | Quantity is any positive decimal, no upper bound, **multiple unit logs per employee/date/item allowed** (no uniqueness constraint, unlike Daily). |
| 6 | **Overtime stays independently available** on both new schemes (existing `worklog_ot` semantics; requires `worklog_ot_enabled` + positive `hourly_wage`). |
| 7 | Catalog **managed by Payroll Managers only**; readable by all internal users (they must pick items when filing logs; the price is not confidential). |
| 8 | The employee sees the price and a **live computed amount** on the log form before submission. |

---

## 2. Scheme design

| Pay Scheme | `wage_type` | Structure type | Base | Addition | OT possible |
|---|---|---|---|---|---|
| `unit` (Per Unit) | **`unit` (new)** | **GEO Unit Pay (new)** | Approved unit logs → `UNIT_BASIC` | — | Yes |
| `daily_unit` (Daily + Per Unit) | `daily` (existing) | GEO Daily Pay (existing) | Approved daily logs → `DAILY_BASIC` | Approved unit logs → `UNIT_EXTRA` | Yes |

Why this split:

- `daily_unit` maps to `wage_type='daily'` exactly like `daily_hourly` does today
  ([hr_version.py:9](../custom_addons/gec_payroll_types/geo_payroll/models/hr_version.py#L9)), so **all
  daily machinery covers it for free**: worked-day zeroing, the stale-BASIC confirm guard, and the
  daily-log route (`_resolve_component_code` keys on `wage_type == 'daily'`). Daily Wage fields are
  genuinely relevant for these employees.
- Pure `unit` gets its own technical wage type + structure so unit employees are not "pretend daily"
  and no Daily Wage field appears for them. Work entries still exist (calendar, leave, conflicts)
  but contribute **zero money** for both schemes — same policy as pure Daily.

```text
Unit log amount          = quantity × frozen price_per_unit
Per Unit base            = Σ unit_basic settlements            → UNIT_BASIC (category BASIC)
Daily + Per Unit gross   = Σ daily_basic + Σ unit_extra (+ OT) → DAILY_BASIC + UNIT_EXTRA (+ WORKLOG_OT)
```

## 3. Component routing (two codes, role-based — matches module convention)

The module's pattern: the component identifies the **role** the source plays, and the category
follows. Daily logs already split `daily_basic` (BASIC, when base) vs `worklog_daily` (ALW, when
addition); timesheets split `timesheet_basic` vs `timesheet_extra`. Unit logs follow it:

| Work-date version scheme | Unit log resolves to | Rule | Category |
|---|---|---|---|
| `unit` | `unit_basic` | `UNIT_BASIC` (sequence 4) | BASIC |
| `daily_unit` | `unit_extra` | `UNIT_EXTRA` (sequence 28) | ALW |
| anything else | `False` → **approval refused** ("no pay route") | — | — |

Resolver addition in `_resolve_component_code`
([hr_employee_work_log.py:204](../custom_addons/gec_payroll_types/geo_payroll/models/hr_employee_work_log.py#L204)):
branch on `version.pay_scheme` directly — **no new stored flags** on `hr.version` (precedent: the
timesheet-mode predicate branches on scheme+source, not a flag). Daily logs on pure `unit` already
refuse approval with no code change (`wage_type != 'daily'`, `worklog_daily_enabled` False).

Both rules ship on **all four** GEO structures (carry-forward across scheme switches — the §13
`TIMESHEET_BASIC` lesson: a late-approved January unit log must still pay on a February Fixed slip
under its frozen component).

## 4. New model: `hr.payroll.unit.rate` (global catalog)

New file `models/hr_payroll_unit_rate.py`:

| Field | Definition |
|---|---|
| `name` | Char, required (e.g. "Tile Laying") |
| `uom_id` | Many2one `uom.uom`, required, `ondelete='restrict'` |
| `price_per_unit` | Monetary, `currency_field='currency_id'`, `required=True` (plus the `> 0` constraint below) |
| `currency_id` | Many2one `res.currency`, required, `ondelete='restrict'`, default `lambda self: self.env.company.currency_id` — **never hardcode GEL in code**; GEL arrives via the company |
| `active` | Boolean, default True (archive instead of delete) |

`_description` required. `_order = 'name, id'`. **No `company_id`** (decision #3, like `uom.uom`
itself), therefore no multi-company record rule. Constraint: `price_per_unit > 0`
(`currency_id.compare_amounts`). Optional guard: `@api.ondelete` blocking unlink when any work log
references the rate is unnecessary — `work_unit_id` is `ondelete='restrict'`, archive is the path.

## 5. Work Log extension (`hr.employee.work.log`)

- `type` selection gains `('unit', 'Unit Work')` (field is owned by this module — plain edit, not `selection_add`).
- New fields:
  - `work_unit_id` — Many2one `hr.payroll.unit.rate`, `ondelete='restrict'`, `index='btree_not_null'`, tracking.
  - `unit_qty` — Float, tracking.
  - `unit_uom_id` — non-stored computed display field, `compute_sudo=True`, no groups (round 3 —
    not a plain related field): before approval it shows the live catalog UoM
    (`work_unit_id.uom_id`); from approval on it shows `unit_uom_snapshot_id`. A live related field
    would mislabel a reopened approved log after a post-approval catalog UoM edit (the settlement
    stays correct; the form would not).
  - `unit_uom_snapshot_id` — Many2one `uom.uom`, `copy=False`, readonly, `ondelete='restrict'`,
    payroll-gated like the sibling snapshots. Needed because the UoM reaches the log through the
    **live catalog hop**: `work_unit_id` is frozen on the log, but a manager can edit the catalog
    row's `uom_id` after approval, which would silently relabel the frozen amount (round-2 review
    finding). Populated at approval, cleared by reset-to-draft, and the settlement copies from it.
  - `unit_price_display` / `unit_amount_display` — non-stored computed Monetary, **no `groups`,
    `compute_sudo=True`** (the `settlement_state` precedent at
    [hr_employee_work_log.py:57](../custom_addons/gec_payroll_types/geo_payroll/models/hr_employee_work_log.py#L57)):
    while draft/submitted they show the live catalog price and `unit_qty × price`; once approved
    they show `rate_snapshot` / `amount_snapshot`, so the employee always sees the number payroll
    will pay (decision #8). `compute_sudo` is mandatory — employees cannot read the payroll-gated
    snapshot fields directly, so a plain related/compute would raise AccessError for them.
- `_check_quantities` gains a `unit` branch and symmetric hygiene:
  - unit: `unit_qty > 0` (float_compare, 2 digits), no upper bound, `hours == 0`, `units == 0`, `work_unit_id` required;
  - overtime/daily branches additionally require `unit_qty == 0` and no `work_unit_id`.
- `_onchange_type`: entering `unit` zeroes `hours`/`units`; leaving `unit` clears `work_unit_id` and `unit_qty`.
- `action_approve` unit branch, in the same style/order as the existing checks:
  1. route check via resolver (shared with all types — refuses on wrong scheme);
  2. refuse if `work_unit_id` archived ("pick a current rate item");
  3. refuse if `work_unit_id.currency_id != log.currency_id` (employee company currency) — the multi-currency guard for the global catalog;
  4. `rate = work_unit_id.price_per_unit`, refuse non-positive (existing message pattern);
  5. `amount = currency.round(unit_qty * rate)`; freeze via the existing `_write_workflow` payload
     (version, rate_snapshot, amount_snapshot, component_code_snapshot, currency_id_snapshot,
     **unit_uom_snapshot_id** for unit logs, approver, time). `action_reset_to_draft` clears
     `unit_uom_snapshot_id` alongside the other snapshots (harmless False for non-unit logs).
- **Exactly one new snapshot field on the log** (`unit_uom_snapshot_id`, rationale above).
  `work_unit_id`/`unit_qty` need no snapshots: they live on the log itself and are frozen by the
  existing "approved logs are frozen" write guard; the log cannot be deleted once it has
  settlement history. Quantity validation keeps the module-wide `precision_digits=2` convention —
  v19 has no per-UoM precision to defer to (one global product decimal setting,
  [uom_uom.py:62](../addons/uom/models/uom_uom.py#L62)).
- `unit_uom_snapshot_id` joins **both** protection sets: the `create()` forge-stripping tuple and
  the `write()` forbidden-fields set — symmetry with the sibling snapshots (round 3).
- Unchanged: daily uniqueness (daily-only), overtime 24h cap (overtime-only), workflow states,
  ownership/approver rules.

## 6. Settlement ledger (`hr.payroll.component.settlement`)

- `component_code` selection += `('unit_basic', 'Unit Work (Basic)')`, `('unit_extra', 'Unit Work (Extra)')`.
- New field `uom_id` — Many2one `uom.uom`, `ondelete='restrict'` — set only for unit claims, so the
  Work Items ledger is self-describing ("35 ft² × 10 = 350"). Immutability/write-block untouched.
- Claim creation ([hr_payslip.py:108](../custom_addons/gec_payroll_types/geo_payroll/models/hr_payslip.py#L108))
  passes `quantity` per type — `{'overtime': hours, 'daily': units, 'unit': unit_qty}` — and
  `uom_id` from `log.unit_uom_snapshot_id` for unit logs (never from the live catalog).

**Explicitly no changes** to `_gec_check_claims`, `_gec_settlement_still_valid`,
`_gec_claim_window`, carry-forward, stale release, correction chains, overlap/coverage guards,
`hr_payslip_run.py`, timesheet claiming, or the waiver flow — the work-log branch of claim
validation compares against the frozen `amount_snapshot` generically and already covers unit logs.
Do not add code there. Reviewed and rejected in round 2: re-comparing settlement
quantity/rate/uom/source-version against the log's frozen copies. Both sides are immutable after
approval+claim (settlement `write()` raises; approved logs are frozen; reset-to-draft is blocked
while a claim is active), so every such equality holds by construction — the checks would be dead
code. The load-bearing live checks are state, window, component, and amount, and they exist.

## 7. Payslip + worked days

- `_GEC_COMPONENT_RULE_CODE` += `{'unit_basic': 'UNIT_BASIC', 'unit_extra': 'UNIT_EXTRA'}`.
- `_gec_check_daily_base_uses_logs`
  ([hr_payslip.py:191](../custom_addons/gec_payroll_types/geo_payroll/models/hr_payslip.py#L191)):
  extend the filter from `wage_type != 'daily'` to `wage_type not in ('daily', 'unit')` and make the
  error message cover both ("Daily/Unit payslip still contains schedule-based BASIC pay…").
  `daily_unit` is already covered (its wage_type is `daily`).
- `hr_payslip_worked_days._compute_amount`
  ([hr_payslip_worked_days.py:14](../custom_addons/gec_payroll_types/geo_payroll/models/hr_payslip_worked_days.py#L14)):
  add a `unit` wage-type branch forcing `amount = 0.0`, with the same `edited`/`state != 'draft'`
  skip guards as the timesheet-base branch. **This is the one override that can regress other
  schemes — keep the daily/timesheet/other split exactly as is.** Without it, stock payroll prices
  the unknown wage type like monthly and pays schedule money on top of unit pay.

## 8. `hr.version` + structure type

- `pay_scheme` selection += `('unit', 'Per Unit')`, `('daily_unit', 'Daily + Per Unit')`.
- `_PAY_SCHEME_WAGE_TYPE` += `{'unit': 'unit', 'daily_unit': 'daily'}`.
- `wage_type` `selection_add=[('unit', 'Unit Wage')]`, `ondelete={'unit': 'set monthly'}` on **both**
  `hr.version` and `hr.payroll.structure.type` (the `'set default'` value crashes at registry load —
  use `'set monthly'`, the proven daily pattern).
- `_compute_scheme_components`: no change (both existing flags stay False for the new schemes; the
  compute already assigns every record).
- `_check_pay_scheme_wage_type` additions, mirroring the TIMESHEET_BASIC precedent:
  - `wage_type == 'unit'` → the structure type's default structure must contain a `UNIT_BASIC` rule
    in category BASIC (else approved unit logs sit silently unpaid);
  - `pay_scheme == 'daily_unit'` → default structure must contain a `UNIT_EXTRA` rule in category
    ALW (round 2: category checked on both sides — a miscategorized rule pays the same gross today
    but silently misclassifies once the tax layer lands).
  - Everything else is map-driven and needs no new branches (`hourly_source='timesheet'` already
    requires `pay_scheme == 'hourly'`, so timesheet mode can never combine with the new schemes).
- `_get_normalized_wage`: return `0.0` for `wage_type == 'unit'` (dashboard cosmetics).
- `_get_contract_wage()` (exists — [hr_version.py:453](../addons/hr/models/hr_version.py#L453),
  feeds `contract_wage` and payroll consumers): override to return `0.0` for `wage_type == 'unit'`.
  Round-2 finding: scheme switches deliberately preserve `wage`, so a Fixed → Unit employee keeps a
  historical monthly wage in the field; without this override `contract_wage` and simulations
  display it. The payslip itself was never at risk (worked-day zeroing + confirm guard), this is
  display/simulation hygiene. `_get_contract_wage_field` still falls through to `'wage'` — it
  returns a field name and cannot "return zero".
- Template whitelist / recompute-trigger lists: no additions needed (`pay_scheme`,
  `structure_type_id`, `wage_type` are already in both; there are no new per-version fields).
- `hr_employee.py` mirrors: no change (no new per-version fields).
- Routing guard `_gec_check_routing_change`: no change — `pay_scheme` is already a guarded routing
  field, so in-place switches away from finalized `unit`/`daily_unit` versions are already blocked.

## 9. Data, security, views

**`data/payroll_structure_data.xml`**
- noupdate=1 block: `structure_type_geo_unit` ("GEO Unit Pay", wage_type `unit`, country GE) +
  `structure_geo_unit` ("GEO Unit Salary", `use_worked_day_lines` True, unpaid-leave type linked) +
  default-struct back-reference — copy the existing daily records' shape.
- noupdate=0 block (upgradable rules):
  - the full rule set on the unit structure: `BASIC` (**`result = 0.0`** — explicit zero, the
    hourly-timesheet-mode precedent; the GEO Unit structure is only ever legal on unit versions, so
    a hard zero is defense-in-depth for simulation and stale-wage display, seq 1),
    `DAILY_BASIC` (2), `TIMESHEET_BASIC` (3), `UNIT_BASIC` (4), `WORKLOG_OT` (25), `WORKLOG_DAILY`
    (26), `TIMESHEET_EXTRA` (27), `UNIT_EXTRA` (28), `GROSS` (100), `NET` (200) — 10 rules, all
    condition/amount expressions copied from the existing pattern
    (`payslip.gec_component_total('<code>')`);
  - `UNIT_BASIC` (seq 4, BASIC) + `UNIT_EXTRA` (seq 28, ALW) added to the **three existing**
    structures (monthly, hourly, daily) — this is the carry-forward requirement and ships on module
    upgrade because rules are noupdate=0.

**`security/ir.model.access.csv`**
- `hr.payroll.unit.rate`: read for `base.group_user`; read/write/create/unlink for
  `hr_payroll.group_hr_payroll_manager`. No record rules (global model, decision #3).

**Views**
- New `views/hr_payroll_unit_rate_views.xml`: list + form + action + menu under the payroll root
  (`hr_work_entry_enterprise.menu_hr_payroll_root`, groups `hr_payroll.group_hr_payroll_manager`,
  sequence after Waive Timesheet Pay). List shows name, uom, price, currency (invisible), active toggle via filter.
- `views/hr_work_log_views.xml`: on the main form and every embedded list (My Profile, employee
  directory card, hr.employee page, payroll list) add `work_unit_id`, `unit_uom_id`, `unit_qty`,
  `unit_price_display`, `unit_amount_display` with `invisible="type != 'unit'"` and the same
  per-state readonly conditions as `hours`/`units` (the three display fields are always readonly).
  Existing project/task/reason fields stay as optional metadata.
- `views/hr_payslip_views.xml`: settlement list/form gain `uom_id` (optional column).
- `views/hr_version_views.xml`: **verify only — expected no-op.** Existing conditions already
  behave: `daily_wage` shows for `daily_unit` (`wage_type == 'daily'`) and hides for `unit`; the
  OT hourly-rate row keys on `worklog_ot_enabled`; timesheet fields key on
  `timesheet_extra_enabled`/hourly checks. Do not invent edits.

**`__manifest__.py`**: version `19.0.1.3.0`; `depends` += `'uom'` (direct model reference; today it
is only transitive via `timesheet_grid → hr_timesheet`); data list += the new view file.

**`tests/common.py`**: `_scheme_wage_type` map += the two new schemes, or every fixture helper
breaks; `_make_work_log` gains unit kwargs; a `_make_unit_rate` helper.

## 10. Invariants (test these, in both agents' implementations)

1. Every `unit_basic`/`unit_extra` settlement points at an approved `type='unit'` log whose frozen
   `amount_snapshot = round(unit_qty × price at approval)`; later catalog edits change nothing.
2. A pure `unit` slip has zero work-entry money: all worked-day amounts 0, `BASIC` line 0 —
   enforced at confirm, not just computed.
3. A `daily_unit` slip: `BASIC` 0, `DAILY_BASIC` = Σ daily logs, `UNIT_EXTRA` = Σ unit logs,
   `WORKLOG_OT` additive when enabled; `GROSS = BASIC cat + ALW cat` unchanged.
4. Unit logs on any other scheme, daily logs on pure `unit`, and archived/currency-mismatched
   rates are **refused at approval** — no approved-but-unpayable logs.
5. Claiming, recompute idempotency, carry-forward (incl. across a later scheme switch),
   version-slice ownership, cancel/delete releases, correction chains: identical behavior to the
   existing suites, now including unit components.
6. The settlement's `uom_id` equals the log's approval-time UoM even after the catalog row's
   `uom_id` is changed post-approval (snapshot, never the live catalog value).
7. A Fixed → Unit switch that preserves a historical `wage` shows `contract_wage = 0` and pays
   `BASIC = 0` on unit slips (rule + `_get_contract_wage` + confirm guard, all three).

## 11. Test plan (new `tests/test_unit_work.py` + touched suites)

- Catalog: manager-only manage, internal-user read, positive-price constraint, archive flow.
- Log constraints: qty > 0 boundaries, cross-field zeros both directions, rate required,
  multiple same-day logs allowed, onchange clearing.
- Approval: routing matrix (unit scheme → `unit_basic`; `daily_unit` → `unit_extra`; each other
  scheme refused; daily log on `unit` refused), freeze semantics (price change after approval, rate
  archived after approval still pays, **catalog `uom_id` changed after approval — settlement keeps
  the snapshot**), currency mismatch refusal, OT approval allowed on both new schemes, display
  fields switch from live price to frozen snapshots at approval (as employee, via `compute_sudo`),
  and a reopened approved log still shows the snapshot UoM/price after post-approval catalog edits
  (employee-level display test, round 3).
- Scheme math (mirror `test_payroll_schemes.py`): pure unit with N logs across items/dates;
  zero-log unit slip confirms at 0; `daily_unit` exact totals incl. OT; BASIC = 0 assertions +
  worked-day amount assertions on both; Fixed → Unit switch with preserved historical `wage`
  (contract_wage 0, slip BASIC 0); misconfigured structures rejected by the constraint (missing
  `UNIT_BASIC`, `UNIT_BASIC` outside BASIC, `UNIT_EXTRA` outside ALW).
- Lifecycle: claim idempotency, recompute-release on repricing... (not applicable — unit claims
  never reprice: frozen at approval; assert exactly that), carry-forward across period and across
  scheme switch, mid-period version split (each slice claims its own dates' logs),
  confirm guards (unclaimed log blocks, line-vs-settlement mismatch blocks, stale schedule BASIC on
  a unit slip blocks), cancel/reopen reclaim, pay-run compute/validate/reset, refund/correction
  chain over a slip carrying unit settlements (`gec_component_total` sign and root-walk).
- Transition matrix in `test_payslip_lifecycle.py`: extend the scheme list to 8 (56 directed
  transitions) — the loop is already dynamic.
- Regression: existing fixed/hourly/daily/timesheet suites untouched and green.

## 12. Cross-review corrections (settled — do not re-litigate)

| Point | Resolution |
|---|---|
| One component (`unit_basic` everywhere) vs two | **Two** (`unit_basic`/`unit_extra`) — matches the module's role-based convention (daily/timesheet precedents). Claude's single-code draft dropped. |
| "Return zero contract wage" | Settled across rounds 1+2: `_get_contract_wage_field` still returns `'wage'` (it names a field and cannot return a value); the zero comes from overriding the value hook `_get_contract_wage()` (verified to exist) plus the `_get_normalized_wage` branch. |
| Catalog currency default | `self.env.company.currency_id` — never a hardcoded GEL. |
| New stored version flags for unit routing | None — resolver branches on `pay_scheme`. |
| Settlement validation changes | None — see round-2 B4 below (both sides immutable; equality re-checks are dead code). |
| `hr_version_views.xml` | Verify-only, expected no-op. |
| Settlement `uom_id` | Included, `ondelete='restrict'`, copied from the log's UoM snapshot. |
| Rule-existence constraint | Covers both, with category on both sides (round 2): `UNIT_BASIC` in BASIC for `unit`, `UNIT_EXTRA` in ALW for `daily_unit`. |
| Missed by both drafts | `_onchange_type` clearing of unit fields; `tests/common._scheme_wage_type` map; `daily_unit` constraint side. |
| Quantity field name | Pinned: **`unit_qty`** (Codex's draft said `unit_quantity` — do not use; one name everywhere: model, views, tests). |
| Freeze implementation | Round 2 supersedes round 1: **one** new snapshot column, `unit_uom_snapshot_id` (the UoM reaches the log through the live catalog hop — a real freeze gap Codex found). Still no `qty` snapshot: `unit_qty` lives on the log and the approved-write guard freezes it. |

Round-2 review (Codex's four "blockers" against this spec):

| Finding | Resolution |
|---|---|
| B1 — UoM not frozen | **Accepted.** `unit_uom_snapshot_id` on the log (approval writes, reset clears, settlement copies from it). |
| B2 — stale wage after Fixed → Unit | **Accepted, mechanics verified**: `_get_contract_wage()` exists ([hr_version.py:453](../addons/hr/models/hr_version.py#L453)) → override to 0 for `unit`; unit-structure BASIC rule = explicit `0.0`. Scope corrected: the payslip was already protected (zeroing + confirm guard); this fixes display/simulation. |
| B3 — price display / preview not frozen | **Accepted, fix corrected**: Codex's as-written fix would AccessError for employees (snapshots are payroll-gated). Use `unit_price_display`/`unit_amount_display` with `compute_sudo=True`, no groups — the `settlement_state` precedent. |
| B4 — "weak" settlement validation | **Rejected.** Settlement and approved log are both immutable and reset is blocked while claimed — every proposed equality (quantity/rate/uom/source-version vs frozen copies) holds by construction. Dead code; the live checks (state, window, component, amount) already exist. Anyone reopening this must name a concrete mutation path first. |
| Secondary: `price_per_unit` required | Accepted (`required=True` + the existing `> 0` constraint). |
| Secondary: `UNIT_EXTRA` category | Accepted — constraint checks ALW on the extra side too. |
| Secondary: qty precision from UoM | **Rejected.** v19 has no per-UoM precision — `uom.rounding` is one global product decimal setting ([uom_uom.py:62](../addons/uom/models/uom_uom.py#L62)); coupling payroll validation to it is worse than the module-wide `precision_digits=2` convention. |

Round-4 review (Codex, against the implemented code; empirical — registry load + full suite on a
disposable upgrade of the test DB, 242/243 green after repairing finding 1 by hand):

| Finding | Resolution |
|---|---|
| R4-1 HIGH — duplicate `structure_type_geo_unit` xmlid in noupdate=1 leaves `default_struct_id` empty on **upgrade** (second record skipped once the id exists; init-mode installs were fine, which is why the legacy three types never hit it) | **Fixed**: back-ref record replaced by an idempotent `<function>` (`_gec_set_missing_default_struct`) in the noupdate=0 block — fills only an EMPTY default, so upgrades never overwrite a customer-selected structure. Helper + only-if-empty behavior unit-tested. |
| R4-2 HIGH — display test approved the log in the worker's env (correctly refused as self-approval) | **Fixed**: log re-enveloped to the payroll test user before `action_approve()`. |
| R4-3 MEDIUM — display fields keyed on `state == 'approved'`, so approve → cancel → catalog edit → reopen showed live values on a cancelled log | **Fixed**: display branches on `unit_uom_snapshot_id` (set at approval, cleared only by reset), covering cancelled-after-approved; regression test added. |
| R4-4 MEDIUM — employee inline lists lacked `unit_uom_id`/`unit_price_display` (decision #8 says employees see unit + price) | **Fixed**: both fields added to all four embedded lists (My Profile, directory card, hr.employee page, payroll list). |
| R5-1 P1 — the R4-1 repair hook had the wrong signature: `<function eval>` routes through `call_kw`, which browses the FIRST eval element into `self` for regular methods (raw arg pass-through exists only for `@api.model`); fresh install and upgrade both died with a TypeError. The unit test had called the method directly with the imagined signature, so it validated the wrong mental model — a data-file hook is only really tested by loading the data file. | **Fixed** (round 5): method is now `def _gec_set_missing_default_struct(self, structure_id)` operating on `self`; XML unchanged; test calls it on the recordset. |

## 13. Explicit non-goals

No UoM conversion; no per-project or per-employee prices; no effective-dated rate history; no
quantity cap or same-day dedup; no Fixed + Unit / Hourly + Unit; no changes to the settlement,
correction, version-split, or waiver architecture. (The "tax layer stays out (separate module)"
non-goal was superseded 2026-07-15: PIT/pension rules live in `geo_payroll` itself since
19.0.1.4.0 — see [`geo_payroll.md`](geo_payroll.md) §10.)

Accepted behavior to document in [geo_payroll.md](geo_payroll.md) after implementation: on
`daily_unit`, a daily log and unit logs on the same date both pay — that is the scheme's intent,
not a defect (unlike the pinned same-day daily+timesheet limitation).

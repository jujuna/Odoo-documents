# geo_payroll — Manual Testing Guide (step by step)

> Goal: check by hand that every pay variation produces the right payslip.
> This is the manual/browser companion to the automated Odoo regression suite described in Part 8.
> Test database: **gec_modules_hr**.

**Numbers used in every example:**

- Monthly wage = **1,600**
- Hourly wage = **10**
- Daily wage = **80**
- A full month = **20 working days = 160 hours** (Mon–Fri, 8h/day)

**Taxes (since 19.0.1.4.0):** every payslip now carries `PIT` (−20%) and, when the employee's
**Pension Fund Member** box (Payroll tab) is ticked, `PENSION_EE` (−2%) and `PENSION_ER` (+2%,
company cost, not part of NET). So expect **NET = 0.80 × GROSS** for a non-member and
**NET = 0.784 × GROSS** for a member (PIT is charged on gross minus the employee's pension).
GROSS expectations in the cases below are unchanged; every "GROSS = NET" phrasing predates the
tax rules — read it as "NET = 0.8 × GROSS" for the default non-member test employee.

---

## Part 0 — Understand 4 words first (2 minutes)

Before testing, be clear on four terms. This also answers "what is Structure Type?".

| Word | Plain meaning | Example |
|---|---|---|
| **Pay Scheme** | The friendly switch **you** pick on the contract. The module's idea. | "Fixed + Daily" |
| **Wage Type** | The technical kind of pay: monthly / hourly / daily. Set **automatically** from the scheme. | monthly |
| **Salary Structure Type** (`structure_type_id`) | The "pay plan" the employee is on. It carries the wage type **and points to the rules** to use. | "GEO Monthly Pay" |
| **Salary Structure** | The actual list of rules (BASIC, GROSS, NET…) that the payslip runs. | "GEO Monthly Salary" |

**How they connect (this is the key picture):**

```
You pick Pay Scheme
        │  (module sets automatically)
        ▼
   Wage Type  ──────────►  must match  ──────────►  Salary Structure Type
                                                           │  (has a "default structure")
                                                           ▼
                                                    Salary Structure  = the rules
                                                           │
                                                           ▼
                                          The payslip runs those rules
```

**So what does `structure_type_id` do on the employee?**
It is the link that tells the payslip **which rules to run**. When you create a payslip, Odoo copies the structure type's *default structure* onto the payslip automatically. It also fixes the **wage type**. The module ships exactly three structure types, one per wage type:

| Pick this Pay Scheme | Wage type becomes | Use this Structure Type |
|---|---|---|
| Fixed / Fixed + Daily / Fixed + Hourly | monthly | **GEO Monthly Pay** |
| Hourly | hourly | **GEO Hourly Pay** |
| Daily / Daily + Hourly / Daily + Per Unit | daily | **GEO Daily Pay** |
| Per Unit | unit | **GEO Unit Pay** |

If the scheme and the structure type don't match, the contract **won't save** — that's on purpose.

> **Rule of thumb:** Pay Scheme is what you choose; Structure Type is what makes it work under the hood. Keep them matched using the table above.

---

## Part 1 — Set up once

1. **Upgrade the module.** In `gec_modules_hr` the module must be at version **19.0.1.3.0**. Older versions do not contain the Unit Work (piecework) release, the Hourly-from-Timesheets release, or the complete automated regression and lifecycle hardening.
2. **Log in as a Payroll Manager.** Payroll users can file work logs, approve them, and run payslips all by themselves. This lets you test the *numbers* without needing a second "manager" user. (You'll test the approval roles later, in Part 5.)
3. **Make a test employee** called `TEST Worker` so you never touch real people.
4. On that employee, set a **Working Schedule** = *Standard 40 hours/week* (Mon–Fri, 8h). This is on the employee's **Work Information** tab.

---

## Part 2 — The 5 steps you repeat for every case

Every single test is the same 5 steps. Learn this once:

1. **Open the employee's contract** (the Payroll / Work Information area) and set:
   - **Pay Scheme**
   - **Salary Structure Type** (from the matching table in Part 0)
   - **Work Entry Source** (usually *Working Schedule*)
   - the **rates** you need (Wage / Hourly Wage / Daily Wage)
2. **Add the inputs** the case needs (work logs, timesheets) — see Part 4. For plain Fixed/Hourly there's nothing to add.
3. Go to **Payroll → Payslips → New**. Choose `TEST Worker`, pick a **full month** as the period. The Structure fills in automatically.
4. Click **Compute Sheet**.
5. **Read two tabs and compare to the expected number:**
   - **Worked Days & Inputs** tab = the *base* pay (Fixed/Hourly hours).
   - **Salary Computation** tab = *all* lines, plus **Gross** at the bottom.

> If **Worked Days is empty**: go to **Payroll → Work Entries**, click **Generate** for that month, then Compute Sheet again.

**Important habit:** overtime, daily logs, and timesheets **never** show in the Worked Days tab — only as lines in Salary Computation. If you ever see them in Worked Days, something is misconfigured.

For a Daily employee, schedule/work-entry rows can still be visible in Worked Days, but their
**Amount must be 0**. Only the approved logs appear as money through `DAILY_BASIC`.

---

## Part 3 — Test each scheme

Do them in this order. Each says: what to set, what to add, and what you must see.

### Case 1 — Fixed (plain monthly salary)

- **Set:** Pay Scheme = *Fixed* · Type = *GEO Monthly Pay* · Source = *Working Schedule* · Wage = 1600.
- **Add:** nothing.
- **Compute. You should see:**
  - Worked Days: `20 days / 160h / 1,600`
  - `BASIC` = **1,600** · **GROSS = 1,600**

**Now prove proration works:**
- Give the employee **2 days of unpaid Time Off** in that month, recompute.
- `BASIC` should drop to **1,440** (144 paid hours; the 16 unpaid hours pay 0).

### Case 2 — Hourly (from Work Entries, default)

- **Set:** Pay Scheme = *Hourly* · Type = *GEO Hourly Pay* · Source = *Working Schedule* · Hourly Wage = 10 · Hourly Source = *Work Entries*.
- **Add:** nothing.
- **You should see:** `BASIC` = 160h × 10 = **1,600**.

### Case 2b — Hourly from Timesheets ("nothing else pays")

- **Set:** Pay Scheme = *Hourly* · Type = *GEO Hourly Pay* · Hourly Wage = 10 · **Hourly Source = Timesheets** · Payroll Timesheet Projects = your allowed project · Timesheet Pay From = period start. Saving without the projects, the Pay From date, or a positive wage must be **refused**.
- **Add:** 2 validated timesheets on the allowed project (8h + 4h, Part 4B).
- **You should see:**
  - schedule/work-entry rows exist but every **Amount = 0**, `BASIC` = **0**
  - `TIMESHEET_BASIC` = 12h × 10 = **120** · **GROSS = 120, NET = 96** (non-member)
- **Extra checks:**
  - a month with no timesheets confirms at **GROSS 0** (that is correct, not a bug);
  - paid leave or a public holiday adds **nothing** unless hours are logged on an allowed project (and then they pay flat 100%);
  - **Pay Overtime Work Logs** cannot be ticked, and approving an overtime log is refused ("the timesheet is the record");
  - two 15h lines on the same date block computation (over the 24h/day total);
  - with an unclaimed validated timesheet — or one claimed by a **draft** payslip — switching Hourly Source back to *Work Entries* is refused; either create a new dated version, or (for claimed lines) cancel/recompute the draft first, then use **Payroll > Waive Timesheet Pay** (manager-only) and retry;
  - the waiver wizard refuses anything outside the exact strandable set (unvalidated, claimed, wrong project, other employee); waiver stamps cannot be written directly (only the wizard and the manager-only **Restore Payroll Pay** action touch them), and a waived line can be neither deleted nor edited until restored;
  - narrowing the Payroll Timesheet Projects list or moving **Pay From** forward is refused while it would strand validated lines — adding a project is always allowed;
  - after any payslip of this version is validated — or a later payslip has paid one of its carried-forward timesheets — changing the source or scheme in place is refused; a new dated version is the only path.

### Case 3 — Daily

> Test this with an existing employee as well as a new one. Switching an old employee to Daily must repair the hidden legacy source automatically; the employee must save without asking you to edit `daily_source`.

- **Set:** Pay Scheme = *Daily* · Type = *GEO Daily Pay* · Daily Wage = 80.
- **Add:** **20 approved daily work logs** (Part 4A), one per working day, units = 1.
- **You should see:**
  - schedule/work-entry rows may exist, but their **Amount = 0**
  - `DAILY_BASIC` = **1,600** · **GROSS = 1,600**
- **Extra checks:** one log with units 0.5 → 40 for that day. A day with no log → nothing for that day.

### Case 4 — Fixed + Daily (salary + extra day-work)

- **Set:** Pay Scheme = *Fixed + Daily* · Type = *GEO Monthly Pay* · Wage = 1600 · Daily Wage = 80.
- **Add:** **1 approved daily log** (e.g. a Saturday the employee worked extra).
- **You should see:** `BASIC` 1,600 + `WORKLOG_DAILY` 80 · **GROSS = 1,680**.

### Case 5 — Fixed + Hourly (salary + timesheet hours)

- **Set:** Pay Scheme = *Fixed + Hourly* · Type = *GEO Monthly Pay* · Wage = 1600 · Hourly Wage = 10. Also set the **Timesheet Pay project list** + a **Pay From** date (Part 4B).
- **Add:** **12 validated timesheet hours** on an allowed project.
- **You should see:** `BASIC` 1,600 + `TIMESHEET_EXTRA` 120 (12 × 10) · **GROSS = 1,720**.

### Case 6 — Daily + Hourly (day-work + timesheet hours)

- **Set:** Pay Scheme = *Daily + Hourly* · Type = *GEO Daily Pay* · Daily Wage = 80 · Hourly Wage = 10 + timesheet project list + Pay From date.
- **Add:** 20 approved daily logs **and** 10 validated timesheet hours.
- **You should see:** `DAILY_BASIC` 1,600 + `TIMESHEET_EXTRA` 100 · **GROSS = 1,700**.

### Case 7 — Overtime (add to any scheme)

- **Set:** tick **Pay Overtime Work Logs** on the contract.
- **Add:** approve one overtime log: **3 hours at 150%**.
- **You should see:** an extra `WORKLOG_OT` = 3 × 10 × 1.5 = **45**. On top of Fixed: GROSS = **1,645**.

### Case 8 — Per Unit (piecework)

- **Prepare once:** as a Payroll Manager, open **Payroll → Unit Work Rates** and create e.g.
  *Tile Laying*, UoM = m², Price per Unit = **10**.
- **Set:** Pay Scheme = *Per Unit* · Type = *GEO Unit Pay*. No wage fields are needed.
- **Add:** unit work logs (Part 4C): e.g. 12.5 m² on one day, 4 m² on another; approve them.
- **You should see:**
  - schedule/work-entry rows may exist, but every **Amount = 0**, `BASIC` = **0**
  - `UNIT_BASIC` = 16.5 × 10 = **165** · **GROSS = 165, NET = 132** (non-member)
- **Extra checks:**
  - a month with no approved unit logs confirms at **GROSS 0** (correct, not a bug);
  - change the rate's price to 15 after approving — the approved log still pays at 10, a log
    approved afterwards pays at 15;
  - change the rate's UoM after approval — the log form and Work Items ledger keep the old unit;
  - several unit logs on the same day (even the same rate item) all pay;
  - Overtime can be ticked and paid on top (needs a positive Hourly Wage).

### Case 9 — Daily + Per Unit

- **Set:** Pay Scheme = *Daily + Per Unit* · Type = *GEO Daily Pay* · Daily Wage = 80.
- **Add:** approved daily logs for worked days AND approved unit logs for output.
- **You should see:** `DAILY_BASIC` for the days + `UNIT_EXTRA` for the units, `BASIC` = 0.
  Example: 1 day (80) + 8 m² (80) on the same date = **GROSS 160** — a day rate plus piecework
  on the same day is the point of this scheme.

---

## Part 4 — How to add the inputs

### 4A. Add a work log (overtime or daily)

1. Go to **Payroll → Work Logs → New**.
2. Fill: **Employee** = TEST Worker · **Date** · **Type**:
   - *Overtime* → enter **hours** and pick a **%** (100/125/150/200).
   - *Daily Work* → enter **units** (1 = full day, 0.5 = half day).
3. Click **Submit**, then **Approve**.
4. Approval is the moment the amount is **frozen**. Only approved logs get paid.
5. Recompute the payslip.

> If **Approve is refused** saying there's no pay route: the contract doesn't pay that log type (e.g. overtime while "Pay Overtime" is off, or a daily log on a scheme that doesn't pay daily). Fix the contract, then approve. This refusal is a safety feature.

### 4B. Add a payable timesheet

A timesheet is paid **only** if all of these are true — otherwise it's silently ignored:

1. On the contract, set **Timesheet Pay projects** (the allow-list) and a **Timesheet Pay From** date.
2. Log time on one of those projects (**Timesheets** app), dated **on/after** the Pay From date and inside the month.
3. **Validate** the timesheet (as the manager/payroll).
4. Recompute the payslip.

Common reasons a timesheet doesn't pay: not validated · project not in the allow-list · dated before the Pay From date · more than 24h on one line · zero/negative hours.

### 4C. Add a unit work log (piecework)

1. Go to **Payroll → Work Logs → New** (or the employee's own Work Logs tab).
2. Fill: **Employee** · **Date** · **Type** = *Unit Work* · **Unit Rate** (from the catalog) ·
   **Quantity**. The unit, current price, and computed amount display automatically.
3. Click **Submit**, then **Approve**. Approval freezes price, amount, currency, and unit.
4. Recompute the payslip.

> Approval is refused when: the scheme has no unit route (only Per Unit and Daily + Per Unit pay
> unit logs) · the rate item is archived · the rate currency differs from the employee company ·
> the quantity is not positive. These refusals are safety features.

---

## Part 5 — Prove the safety guards (very important)

"Correct" also means "refuses to do the wrong thing." Test these:

| Test | What to do | What must happen |
|---|---|---|
| Fixed on Attendances trap | Fixed scheme, Source = *Attendances*, badge only 15 days | Still pays ~1,600 → this is why **Fixed must use Working Schedule** |
| Daily with no logs | Daily scheme, approve no logs | `DAILY_BASIC` = 0 (no schedule/holiday pay) |
| Overtime route off | Untick Pay Overtime, try to approve an overtime log | **Approval refused** |
| Change flag after approval | Approve an OT log, then untick Pay Overtime, recompute | Log **still pays** (frozen at approval) |
| Unit rate archived | Approve a unit log, archive the rate, try to approve another draft on it | Approved log still pays; new approval **refused** |
| Unit price/UoM changed after approval | Edit the catalog rate after approving a unit log | Approved log keeps its frozen price, amount, and unit |
| Unit log on wrong scheme | File a unit log for a Fixed/Hourly/Daily employee, approve | **Approval refused** ("no pay route") |
| Two payslips same month | Confirm one payslip, make a second regular one for the same month, confirm | **Blocked** — can't pay base twice |
| Approve your own log | As a **normal** employee (not payroll), file and try to approve your own log | **Blocked** |
| Touch someone else's log | As a normal user, try to edit another employee's log from *My Profile* | **Blocked** |
| Daily units too big | Daily log with units = 2 | **Rejected** — one date only |
| Old employee → Daily | On an existing employee, change Scheme to Daily and Type to GEO Daily Pay in one save | Saves normally; no hidden `daily_source` error |
| Preserve settings | Before switching schemes, fill all three rates, overtime, projects, and cutoff date | All values remain after the switch |
| Existing draft slip | Compute a draft slip, then change Scheme + matching Type | Draft base slip moves to the new default structure and recalculates |
| Finalized history | Change the current version after another slip is validated/paid | Validated/paid slip remains unchanged |
| Special slips | Keep a draft refund/correction/off-cycle slip, then edit the version | Special slip is not automatically reset |
| Cancel → Draft | Cancel a regular base slip, change the version, then set the slip to Draft | It aligns to the current default structure and recalculates |
| Stale Daily BASIC | Try to confirm a Daily slip carrying nonzero schedule-based `BASIC` | **Blocked**; recompute until `BASIC = 0` |

---

## Part 6 — When a number is wrong (quick troubleshooting)

| Symptom | Most likely cause |
|---|---|
| Base pay is 0 | No work entries generated → **Payroll → Work Entries → Generate**; or Daily scheme (base is in `DAILY_BASIC`, not `BASIC`) |
| Fixed pays full wage despite absences | Source is Attendances/Planning — switch to **Working Schedule** |
| Expected add-on line is missing | The log/timesheet isn't **approved/validated**, or the payslip isn't using the version's default structure |
| Contract won't save | Pay Scheme and Structure Type don't match — use the table in Part 0 |
| `NET = GROSS` | Wrong since 19.0.1.4.0 — `PIT` should always deduct 20%; the structure is missing the tax rules (upgrade the module) |
| `PENSION_EE`/`PENSION_ER` = 0 | Employee's **Pension Fund Member** box is unticked |
| PIT looks 0.4% too high for a member | `PENSION_EE` didn't run (membership unticked or rule sequence changed) — PIT must compute on gross **minus** employee pension |

### What a configuration change is allowed to reset

Changing Scheme + matching Salary Structure Type may recalculate an unedited draft regular base
payslip because its old structure/lines are no longer correct. It must **not** clear Wage, Hourly
Wage, Daily Wage, overtime, project allow-list, or the timesheet cutoff date. It must not rewrite
validated/paid history, refunds, corrections, manually edited slips, or off-cycle slips.

---

## Part 7 — Optional: read the raw result in the database

Read-only check of exactly what a payslip produced (safe):

```sql
-- run:  psql -d gec_modules_hr
SELECT p.number, r.code, l.total
FROM hr_payslip_line l
JOIN hr_payslip p     ON l.slip_id = p.id
JOIN hr_salary_rule r ON l.salary_rule_id = r.id
WHERE p.employee_id = <TEST_WORKER_ID>
ORDER BY p.id, r.sequence;
```

You should be able to add up `BASIC + DAILY_BASIC + WORKLOG_* + TIMESHEET_EXTRA` and get exactly the `GROSS` line.

---

## Part 8 — Automated Odoo regression suite

The addon now ships post-install tests under
`custom_addons/gec_payroll_types/geo_payroll/tests/`. The suite covers:

| Test file | Main coverage |
|---|---|
| `test_hr_version.py` | all six mappings, source normalization, constraints, inherited values, effective-date versions, and scheme/type changes during `create_version()` |
| `test_correction_chain.py` | exact refund reversal, correction/refund balance (including multiple pairs), native refund-only flow, forged lineage validation, cancellation order, pay-run lineage deletion |
| `test_payroll_schemes.py` | exact BASIC/component/GROSS/NET amounts for every scheme, proration, all overtime percentages |
| `test_payslip_lifecycle.py` | claim gates, idempotent recompute, confirmation guards, overlap, refunds/corrections, all 56 scheme-to-different-scheme changes (8 schemes), state preservation |
| `test_payrun.py` | batch compute/validate/paid/reset, claims, version/type change while finalized, special-slip preservation |
| `test_timesheet.py` | validation/project/cutoff/rate/date eligibility, carry-forward, repricing and release |
| `test_timesheet_hourly_base.py` | Hourly-from-Timesheets: "nothing else pays" math, work-entry zeroing, config gate, confirm guards (edited / rule drift / unclaimed lines), source inheritance, routing guard (finalized block + strandable block), waiver wizard and permanence, per-day 24h aggregate cap (base and extra modes), OT refusal, cross-scheme carry-forward |
| `test_unit_work.py` | Unit Work (piecework): catalog constraints/ACL/archive/delete, quantity boundaries and cross-field hygiene, routing matrix (both unit schemes pay, all six legacy schemes refuse), freeze semantics (price/UoM changes after approval, forged snapshots, frozen approved logs), employee display fields, exact Per Unit and Daily + Per Unit math with zero work-entry base, tamper guards, carry-forward across a scheme switch, mid-period version split, correction chains, pay-run lifecycle, structure-rule constraints |
| `test_work_log.py` | quantities, uniqueness, aggregate 24h overtime cap, workflow, permissions and frozen snapshots |
| `test_settlement.py` | immutable ledger, source locks, unique active claims, cancel/delete/pay-run releases |
| `test_security.py` | employee/manager/payroll roles, nested profile writes, field groups, multi-company rules, non-payroll HR version writes, payroll-officer stale-claim recompute |
| `test_version_segmentation.py` | mid-period version changes, add-on components: each work item priced by its work-date version and claimed by its slice's payslip; clipped monthly split blocked |
| `test_version_split.py` | mid-period version changes, base pay: batch generates one full-period slip per version slice (wage / admin-only / cross-wage-type), OUT proration amounts (800+1000=1800), version coverage gate, carry-forward ownership both compute orders + re-hire, cancel-one-of-pair work-entry/settlement preservation, payment totals, leaf-first correction-chain guards |
| `test_known_limitations.py` | executable documentation of the still-unresolved edge cases (same-day cross-source pay, attendance/planning OT reconciliation) |

Run the whole addon suite from the Odoo repository root:

```bash
createdb geo_payroll_test
data_venv/bin/python odoo-bin \
  -d geo_payroll_test \
  --addons-path=addons,enterprise,custom_addons/gec_payroll_types \
  -i geo_payroll \
  --test-enable \
  --test-tags /geo_payroll \
  --stop-after-init \
  --http-port=18069
```

The suite is a strong regression gate, not a mathematical proof of every future input. The unresolved
product policies in the implementation plan remain outside a “safe and supported” claim: true
multi-worker race execution, leave/cross-source overlap, attendance/planning overtime
reconciliation, and Georgian tax/pension/accounting rules.

The remaining unresolved cases stay pinned in `test_known_limitations.py` as **characterization
tests** — each asserts what the module does *today* (including where today's behavior is wrong) and
turns red the instant the behavior changes, forcing whoever closes the gap to update the assertion:

- Same-day daily log + timesheet both paying (no cross-source dedup).
- `skip`: attendance/planning overtime reconciliation has no implementation to exercise yet.

**Resolved 2026-07-14 (Hourly-from-Timesheets release)** and moved to `test_timesheet_hourly_base.py`:
the per-day 24h aggregate cap — two same-day 15h lines now block computation instead of paying 30h,
in both the extra and the base timesheet modes.

> Note: these are green characterization tests rather than expected-failures because Odoo's test
> runner has no xfail concept — it counts `@unittest.expectedFailure` as a hard failure.

**Resolved by the version-split rework (2026-07-13)** and moved out of the limitations file into
behavior tests:

- Mid-period version base segmentation: one FULL-PERIOD payslip per version slice, prorated by
  standard `OUT` lines. `test_version_split.py` asserts the real generated-work-entry amounts
  (wage 1,600 → 2,000 on Jan 16 pays 800 + 1,000 = 1,800), including admin-only version changes
  and cross-wage-type transitions with per-version structures.
- The old adjacent clipped split is now **blocked**: each shortened fixed-wage slip pays the full
  monthly wage for a partial period (would total 3,600 instead of 1,800).
- The duplicate-base guard is version-aware; a coverage gate blocks slip and pay-run validation
  while any employed version slice has no payslip (or has a duplicate).
- Root-correction cancellation is solved **leaf-first**: a root with live corrections cannot be
  cancelled or reset, and any descendants — even cancelled — block deletion (audit lineage), so a
  correction's totals no longer drop from 45 to 0.

`test_version_segmentation.py` still proves the add-on components: every work item is priced by the
version effective on its own work-date and claimed by the payslip of the slice owning that date;
carry-forward from before the period belongs to the earliest slice's slip regardless of compute
order. The cancel-one-of-a-pair tests (`test_cancelling_one_slice_slip_preserves_the_other*`) are
the sentinels for standard's version-blind `action_draft_linked_entries` — if they turn red on a
real run, add the agreed version-aware override in `geo_payroll`.

---

*Behavior reference: [geo_payroll.md](geo_payroll.md). Design & build history: [geo_payroll_implementation_plan.md](geo_payroll_implementation_plan.md).*

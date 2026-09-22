# Time Off — Accrual Plans

> **Updated 2026-08-24.** Module: `hr_holidays`. Models: [`hr.leave.accrual.plan`](../addons/hr_holidays/models/hr_leave_accrual_plan.py), [`hr.leave.accrual.level`](../addons/hr_holidays/models/hr_leave_accrual_plan_level.py) (model renamed in v19 — the file name still says `..._plan_level.py`). Engine: [`hr_leave_allocation.py`](../addons/hr_holidays/models/hr_leave_allocation.py). Public-holiday interaction: [`public_holidays_flow.md`](public_holidays_flow.md).

## What It Does

An accrual plan makes an employee's time-off balance **grow gradually over time** instead of granting a fixed lump of days. You attach the plan to an **accrual allocation** (Time Off ▸ Allocations ▸ Allocation Type = *Accrual*, then pick the plan). A nightly scheduled action then tops up the balance according to the plan's rules.

A plan is just a template: rules live in the plan header (**Configuration**) plus one or more **Milestones (levels)**.

## How It Works (flow)

1. Build the plan: set the Configuration options + add milestones.
2. Give an employee an **Accrual** allocation and select the plan.
3. The accrual cron (`_update_accrual`) repeatedly adds `added_value` at each `frequency` occurrence, promotes the employee through milestones by seniority, caps the balance, and carries over / resets unused days on the carry-over date.

## Plan Configuration Fields

| Field (UI) | Model field | What it does |
|---|---|---|
| **When the time is accrued?** | `accrued_gain_time` | `start` = days granted up-front at the period start; `end` = granted after the period is worked (default). Source: [`:34`](../addons/hr_holidays/models/hr_leave_accrual_plan.py#L34) |
| **It is based on worked time?** (only if accrued at *end*) | `is_based_on_worked_time` | `Yes` = accrual is proportional to time actually worked (unpaid time off reduces it); `No` = full accrual for the whole calendar period regardless of absences. Source: [`:31`](../addons/hr_holidays/models/hr_leave_accrual_plan.py#L31) |
| **Do you need a carry-over?** | `can_be_carryover` | Master switch: allow unused days to roll into the next year. Source: [`:39`](../addons/hr_holidays/models/hr_leave_accrual_plan.py#L39) |
| **When … carried-over?** | `carryover_date` | `year_start` (Jan 1), `allocation` (allocation's anniversary), or `other` = custom day/month (`carryover_day` / `carryover_month`). Source: [`:40`](../addons/hr_holidays/models/hr_leave_accrual_plan.py#L40) |
| **Switch employees to the new accrual level** (only if >1 milestone) | `transition_mode` | When an employee reaches a higher milestone: `immediately` apply it, or `end_of_accrual` wait until the current period finishes. Source: [`:26`](../addons/hr_holidays/models/hr_leave_accrual_plan.py#L26) |

## Milestones (Levels)

Each milestone is a seniority tier. An employee sits on the highest milestone their tenure qualifies for, and accrues at that tier's rate.

| Card text (UI) | Model field(s) | Meaning |
|---|---|---|
| **After X day(s)/year(s)** | `start_count` + `start_type` (+ `milestone_date`) | Seniority threshold, measured from the allocation start, at which this milestone activates. `start_count = 0` → "At allocation creation". Source: [`level:23`](../addons/hr_holidays/models/hr_leave_accrual_plan_level.py#L23) |
| **Accrual frequency: 1 day(s) every year on the 1 of January** | `added_value` + `added_value_type` + `frequency` (+ day/month detail fields) | How much is granted and how often (hourly … yearly). Source: [`level:39`](../addons/hr_holidays/models/hr_leave_accrual_plan_level.py#L39), [`level:45`](../addons/hr_holidays/models/hr_leave_accrual_plan_level.py#L45) |
| **Unused days will be transferred totally / lost / up to N** | `action_with_unused_accruals` + `carryover_options` + `postpone_max_days` | `all` = carried over (`unlimited` = "totally", `limited` = "up to N"); `lost` = reset to 0 at carry-over. Source: [`level:115`](../addons/hr_holidays/models/hr_leave_accrual_plan_level.py#L115) |
| **A balance cap is set to 100 day(s)** | `cap_accrued_time` + `maximum_leave` | Hard ceiling: the allocation balance never exceeds this. (`cap_accrued_time_yearly` / `maximum_leave_yearly` cap the amount accrued per year.) Source: [`level:104`](../addons/hr_holidays/models/hr_leave_accrual_plan_level.py#L104) |

`accrued_gain_time` is shared from the plan onto every level ([`level:22`](../addons/hr_holidays/models/hr_leave_accrual_plan_level.py#L22)), so all milestones grant at the same start/end timing.

## What the "accrual period" is

It is **not a separate field** — the accrual period is **one cycle of the milestone's Frequency**. The cron advances exactly one frequency cycle each time (`_get_next_date`). Source: [`level:272`](../addons/hr_holidays/models/hr_leave_accrual_plan_level.py#L272).

| Frequency | One accrual period = |
|---|---|
| Daily | 1 day |
| Weekly | 1 week |
| Twice a month | ~half a month (between the two chosen days) |
| Monthly | 1 month |
| Twice a year | ~6 months |
| Yearly | 1 year |

So "**At the start / end of the accrual period**" just means: grant the days at the beginning or the end of each such cycle.

## Start vs End — advance vs arrears

The setting does not change **how much** is granted, only **which period the grant belongs to**:

- **At the start** = paid **in advance**. On 1 March the employee receives March's days, before March is worked.
- **At the end** = paid **in arrears**. On 1 March the employee receives February's days, because February is now over.

Both modes therefore fire on the *same calendar dates* (the milestone's accrual dates). The balance under `start` is permanently **one full period ahead** of the same plan under `end`.

15 h monthly on the 1st, allocation starting 1 January:

| Date | At the start (advance) | At the end (arrears) |
|---|---|---|
| 1 Jan | +15 → 15 (for January) | 0 (January not worked yet) |
| 1 Feb | +15 → 30 (for February) | +15 → 15 (for January) |
| 1 Mar | +15 → 45 | +15 → 30 |
| … | … | … |
| 1 Dec | +15 → 180 (12th grant) | +15 → 165 (for November) |

Same plan, yearly frequency on 1 January, employee hired 1 January: **start** gives the full year immediately; **end** gives nothing until 1 January of the *following* year — the employee waits 12 months for a balance.

Two consequences of choosing `start`:

1. **Worked-time proration becomes impossible** and the option disappears from the form ([`plan:104`](../addons/hr_holidays/models/hr_leave_accrual_plan.py#L104)) — Odoo cannot prorate on hours worked in a period that has not happened yet.
2. **Over-granting risk on leavers and long absences** — days are on the balance before they are earned, so a mid-year leaver holds more than they accrued.

Internally the "advance" behaviour is a pre-grant: at the end of a cron run the engine grants the *next* period and sets `already_accrued = True` ([`allocation:613`](../addons/hr_holidays/models/hr_leave_allocation.py#L613)); when the loop later reaches that accrual date it skips the add, so nothing is counted twice.

## The Engine — what the nightly cron actually does

Cron **"Accrual Time Off: Updates the number of time off"**, every 1 day, runs `model._update_accrual()` ([`ir_cron_data.xml:4`](../addons/hr_holidays/data/ir_cron_data.xml#L4)).

It picks up only allocations that are **`allocation_type = accrual`**, **`state = validate` (approved)**, have a plan and an employee, are not past `date_to`, and whose `nextcall <= today` ([`allocation:637`](../addons/hr_holidays/models/hr_leave_allocation.py#L637)). A draft or to-approve allocation accrues nothing.

Each allocation carries its own cursor:

| Field | Meaning |
|---|---|
| `lastcall` | last date on which days were actually accrued |
| `nextcall` | next date the engine must act on (accrual date, carry-over date, level-transition date, or carry-over expiry — whichever comes first) |
| `already_accrued` | "the next period is already paid" flag, used by `accrued_gain_time = start` to avoid double-granting |
| `yearly_accrued_amount` | running total for the **yearly cap**, reset on every carry-over date |

`_process_accrual_plans` ([`allocation:434`](../addons/hr_holidays/models/hr_leave_allocation.py#L434)) loops `while nextcall <= today`, so a cron that has been down for months catches up in one pass. Each loop: pick the milestone valid at `nextcall`, compute the period, add days, apply caps, apply the carry-over policy if the date is a carry-over date, then move `lastcall`/`nextcall` forward.

**At the start of the period** is implemented by granting the *upcoming* period's days at the end of the run and setting `already_accrued = True` ([`allocation:613-628`](../addons/hr_holidays/models/hr_leave_allocation.py#L613)); when the loop later reaches that date it skips the add. Net effect: with `start`, the days of period *N* are on the balance from the first day of period *N*.

Setting `accrued_gain_time = start` also force-clears `is_based_on_worked_time` ([`plan:104`](../addons/hr_holidays/models/hr_leave_accrual_plan.py#L104)) — you cannot prorate by worked time when you pay up-front, and the option disappears from the form.

## Carry-over OFF does not mean "balance keeps growing"

This is the single most misread part of the feature.

- `can_be_carryover` unchecked → the whole **Carry Over Options** group is hidden on the milestone ([`views:66`](../addons/hr_holidays/views/hr_leave_accrual_views.xml#L66)) **and** `action_with_unused_accruals` is force-computed to **`lost`** ([`level:241`](../addons/hr_holidays/models/hr_leave_accrual_plan_level.py#L241)).
- The carry-over **date** is still computed and still hit by the engine — `_get_carryover_date` never checks `can_be_carryover` ([`allocation:317`](../addons/hr_holidays/models/hr_leave_allocation.py#L317)), and `carryover_date` defaults to **`year_start` = 1 January**.
- On that date the engine executes `number_of_days = min(number_of_days, 0) + leaves_taken` ([`allocation:554`](../addons/hr_holidays/models/hr_leave_allocation.py#L554)) — i.e. **the unused balance is wiped to zero**; only already-taken time stays accounted for.

So an unchecked carry-over box = strict **use-it-or-lose-it on 31 December**, not "unlimited accumulation". Confirmed by `test_accrual_lost_first_january` ([`tests`](../addons/hr_holidays/tests/test_accrual_allocations.py)): 3 days/year, gain at start, lost → the balance is still 3 after four years.

Order on 1 January (gain at start): wipe first (inside the loop), then the new period's grant (after the loop) — so the employee starts 1 January with exactly one fresh period's worth.

## The first period is prorated

`_process_accrual_plan_level` ([`allocation:414`](../addons/hr_holidays/models/hr_leave_allocation.py#L414)) computes `period_prorata = call_days / period_days` whenever the allocation's start does not coincide with a period boundary ([`:431`](../addons/hr_holidays/models/hr_leave_allocation.py#L431)).

Monthly-on-the-1st plan, allocation starting 24 August → first grant = `(1 Sep − 24 Aug) / (1 Sep − 1 Aug) = 8/31` of the monthly amount. A yearly-on-1-January plan started on 24 August gives `130/365` of the yearly amount for the stub year, then the full amount on 1 January.

This proration is **calendar-day based**, not worked-time based (worked-time proration is a separate switch and is unavailable with `start`).

To avoid a partial first period, set the allocation's **Start Date to the first day of a period** (e.g. the 1st of the hire month for a monthly-on-the-1st plan) — then `start_period == start_date` and the employee gets the full amount.

## Testing accruals

Nothing accrues on demand: the balance only moves when the **daily cron** runs. Two traps when testing:

- **A neutralized database has all crons disabled** — `neutralize.sql` runs `UPDATE ir_cron SET active = false` for everything except `autovacuum_job` ([`neutralize.sql:10`](../odoo/addons/base/data/neutralize.sql#L10)). On a DB showing the red *"Database neutralized for testing"* banner, accruals never run until you re-activate "Accrual Time Off: Updates the number of time off" in Settings ▸ Technical ▸ Scheduled Actions and trigger it manually.
- **Only approved allocations accrue** (`state = validate`). A record sitting in *To Approve* shows a simulated figure from `_onchange_date_from` but the cron ignores it.

## Backdating `date_from` does not back-pay

`_add_lastcalls` runs on **create** ([`allocation:770`](../addons/hr_holidays/models/hr_leave_allocation.py#L770)) and anchors `lastcall` at `max(previous period boundary relative to today, allocation start)` ([`allocation:738`](../addons/hr_holidays/models/hr_leave_allocation.py#L738)).

The rule that follows: **the current period is granted in full, every completed period before today is silently skipped.**

| Plan created today (24 Aug) with `date_from` = 1 Jan | Result |
|---|---|
| Monthly on the 1st | `lastcall` = 1 Aug → 15 h for August only; **Jan–Jul (7 × 15 h) never granted** |
| Yearly on 1 Jan | `lastcall` = 1 Jan → the current period is 1 Jan → 1 Jan, so the **full 180 h is granted** |

`date_from` otherwise only drives milestone seniority and the proration anchor. To hand out skipped entitlement, add a separate **regular** allocation for the missed amount.

The first cron run also posts a log note on the allocation: *"This allocation have already ran once, any modification won't be effective…"* ([`allocation:443`](../addons/hr_holidays/models/hr_leave_allocation.py#L443)). Editing the plan afterwards does not retro-correct days already granted.

## Hours are stored as days

`number_of_days` is always the storage unit. A milestone encoded in hours is divided by the employee's calendar `hours_per_day` at the allocation start ([`allocation:426`](../addons/hr_holidays/models/hr_leave_allocation.py#L426)); the same conversion applies to `maximum_leave`, `maximum_leave_yearly` and `postpone_max_days`.

15 h/month with an 8 h/day calendar = 1.875 days/month. **An employee with no working calendar (fully flexible) uses 24 h/day** ([`hr_employee.py:614`](../addons/hr_holidays/models/hr_employee.py#L614)) — 15 h would become 0.625 days. Always check the calendar before encoding an hour-based plan. See [`hr_holidays_time_off_units.md`](hr_holidays_time_off_units.md).

## Yearly cap vs balance cap

| Option (UI) | Field | Semantics |
|---|---|---|
| **Define a yearly cap?** — "Accrual will stop until next carry-over date if accrued time's reach N" | `cap_accrued_time_yearly` / `maximum_leave_yearly` | Limits how much is **granted between two carry-over dates**. Counter `yearly_accrued_amount` is reset to 0 on the carry-over date ([`allocation:561`](../addons/hr_holidays/models/hr_leave_allocation.py#L561)); the grant is trimmed by the remaining headroom ([`allocation:343`](../addons/hr_holidays/models/hr_leave_allocation.py#L343)). |
| **Define a balance cap?** — "The plan will be on hold if the balance reach N" | `cap_accrued_time` / `maximum_leave` | Limits the **standing balance**: `days_to_add = min(days_to_add, leaves_taken + maximum_leave − number_of_days)` ([`allocation:346`](../addons/hr_holidays/models/hr_leave_allocation.py#L346)). Taking time off frees the ceiling again; accrual resumes automatically. |

A yearly cap equal to `frequency count × added_value` (e.g. 12 × 15 h = 180 h) never binds — it is only a safety net against future edits to the frequency.

## Worked Example — two ways to give 180 hours a year

Both plans below use `accrued_gain_time = start`, carry-over unchecked, one milestone reached "At allocation creation".

| | **Monthly**: 15 h every month on the 1st, yearly cap 180 h | **Annual**: 180 h every year on 1 January |
|---|---|---|
| Grant events per year | 12 | 1 |
| Balance on 1 February | 30 h | 180 h |
| Balance on 1 December | 180 h | 180 h |
| Can the employee take 3 weeks in February? | No — only what has accrued | Yes — the full year is available on day 1 |
| Allocation created 24 Aug | 8/31 × 15 h ≈ 3.9 h now, then 15 h per month | 130/365 × 180 h ≈ 64 h now, 180 h on 1 Jan |
| 1 January | balance wiped, 15 h granted | balance wiped, 180 h granted |
| Leaver in June | has earned ~6 × 15 h = 90 h | still holds 180 h (over-granted) |
| Risk | employee cannot take a long holiday early in the year | company over-grants to leavers and to unpaid-leave absences |

Monthly = pay-as-you-earn, matches severance/settlement math. Annual = simple entitlement, front-loaded risk. If the balance must survive year-end, **the carry-over checkbox must be ticked on the plan** and the milestone set to *Carried over* — otherwise both plans reset every 1 January.

## Assigning a Plan to an Employee

The plan does nothing on its own — it is applied through an **allocation**:

1. **Time Off ▸ Management ▸ Allocations ▸ New**.
2. **Allocation Type = Accrual Allocation** (the `accrual_plan_id` field only appears then). Source: [`allocation:119`](../addons/hr_holidays/models/hr_leave_allocation.py#L119).
3. Pick the **Time Off Type** (`holiday_status_id`) and the **Accrual Plan** (the dropdown is filtered to plans matching that type).
4. Pick the **Employee(s)** and a **Start Date** (`date_from`) — milestone seniority ("After X years") is counted from this date.
5. Confirm / Approve. The nightly accrual cron then tops up the balance automatically.

**Batch assignment:** allocations are per-employee in v19 (no multi-employee field on the allocation). To grant a plan to many people at once use the **"Generate time off allocations for multiple employees"** wizard — grant by employee list, whole company, department, or employee tag; it supports Accrual Allocation type ([`hr_leave_allocation_generate_multi_wizard.py:107`](../addons/hr_holidays/wizard/hr_leave_allocation_generate_multi_wizard.py#L107)).

**Unit of the grant:** each milestone grants in **Day(s) or Hour(s)** (`added_value_type`, [`level:39`](../addons/hr_holidays/models/hr_leave_accrual_plan_level.py#L39)). The accrual allocation *displays* in the milestone's unit, not the leave type's Duration Type ([`allocation:303`](../addons/hr_holidays/models/hr_leave_allocation.py#L303)) — for an hour-based type, grant hours to keep every screen in hours. See [`hr_holidays_time_off_units.md`](hr_holidays_time_off_units.md).

## Regular vs Accrual Allocation

Both give an employee a balance of a time-off type, but the way days arrive differs:

| | Regular Allocation | Accrual Allocation |
|---|---|---|
| How days are granted | A **fixed** number, **all at once** | **Grows over time** via an accrual plan |
| Needs an accrual plan? | No | Yes (`accrual_plan_id`) |
| Starting balance | The full amount you type (must be > 0) | Usually 0, then the cron adds days |
| DB rule | `number_of_days > 0` required | can start at 0 |
| Typical use | "Give everyone 20 vacation days for 2026", one-off bonus days, manual top-up | "Earn 2 days/month", seniority leave, part-time proportional, pay-as-you-work |

Source: `allocation_type` [`allocation:119`](../addons/hr_holidays/models/hr_leave_allocation.py#L119), constraint [`allocation:133`](../addons/hr_holidays/models/hr_leave_allocation.py#L133).

## "Eligible for Accrual Rate?" (on the Time Off Type)

Field `elligible_for_accrual_rate` on `hr.leave.type`, help: *"this time off type will be taken into account for accruals computation."* Source: [`hr_leave_type.py:116`](../addons/hr_holidays/models/hr_leave_type.py#L116).

It **only matters when an accrual plan is "based on worked time"**, where it decides whether time taken under this leave type still counts as **worked time** (so the employee keeps earning accrual during it):

- **Checked** → counts as worked → the employee **still accrues** while on this leave (for example, a paid leave type deliberately configured as eligible).
- **Unchecked** → does **not** count → that absence **reduces** the accrual (e.g. unpaid leave).

Default: "worked time" types are auto-eligible, pure leave types default to *not* eligible ([`hr_leave_type.py:393`](../addons/hr_holidays/models/hr_leave_type.py#L393)). The worked-time accrual adds eligible leave hours onto worked hours ([`allocation:385`](../addons/hr_holidays/models/hr_leave_allocation.py#L385)). If the plan is **not** based on worked time (whole calendar days), this flag has no effect.

Public holidays use the similarly named field on `resource.calendar.leaves`, whose stock default is **False** and whose normal Public Holidays UI does not expose it. Therefore stock public holidays reduce worked-time-based accrual unless customization/data explicitly marks them eligible. Decide and audit the Georgian policy separately from the holiday's payroll work-entry type.

## Use Cases

- **Seniority plan** (the screenshot): from day 1 → 1 day/year; after 4 years → 2 days/year; after 8 years → 3 days/year. Rewards tenure; carry-over capped at 100 days.
- **Monthly build-up**: e.g. ~1.67 days every month, capped at 20/year — statutory vacation accrued across the year rather than granted up front.
- **Worked-time based**: part-timers / hourly staff accrue in proportion to hours actually worked (`is_based_on_worked_time = Yes`).
- **Use-it-or-lose-it**: `action_with_unused_accruals = lost` so any unused balance resets on the carry-over date.

## Related Docs

- [`INDEX.md`](INDEX.md)

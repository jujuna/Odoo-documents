# Time Off — Accrual Plans

> Module: `hr_holidays`. Models: [`hr.leave.accrual.plan`](../addons/hr_holidays/models/hr_leave_accrual_plan.py), [`hr.leave.accrual.plan.level`](../addons/hr_holidays/models/hr_leave_accrual_plan_level.py).

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

## Assigning a Plan to an Employee

The plan does nothing on its own — it is applied through an **allocation**:

1. **Time Off ▸ Management ▸ Allocations ▸ New**.
2. **Allocation Type = Accrual Allocation** (the `accrual_plan_id` field only appears then). Source: [`allocation:119`](../addons/hr_holidays/models/hr_leave_allocation.py#L119).
3. Pick the **Time Off Type** (`holiday_status_id`) and the **Accrual Plan** (the dropdown is filtered to plans matching that type).
4. Pick the **Employee(s)** and a **Start Date** (`date_from`) — milestone seniority ("After X years") is counted from this date.
5. Confirm / Approve. The nightly accrual cron then tops up the balance automatically.

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

- **Checked** → counts as worked → the employee **still accrues** while on this leave (e.g. paid leave, public holidays).
- **Unchecked** → does **not** count → that absence **reduces** the accrual (e.g. unpaid leave).

Default: "worked time" types are auto-eligible, pure leave types default to *not* eligible ([`hr_leave_type.py:393`](../addons/hr_holidays/models/hr_leave_type.py#L393)). The worked-time accrual adds eligible leave hours onto worked hours ([`allocation:385`](../addons/hr_holidays/models/hr_leave_allocation.py#L385)). If the plan is **not** based on worked time (whole calendar days), this flag has no effect.

## Use Cases

- **Seniority plan** (the screenshot): from day 1 → 1 day/year; after 4 years → 2 days/year; after 8 years → 3 days/year. Rewards tenure; carry-over capped at 100 days.
- **Monthly build-up**: e.g. ~1.67 days every month, capped at 20/year — statutory vacation accrued across the year rather than granted up front.
- **Worked-time based**: part-timers / hourly staff accrue in proportion to hours actually worked (`is_based_on_worked_time = Yes`).
- **Use-it-or-lose-it**: `action_with_unused_accruals = lost` so any unused balance resets on the carry-over date.

## Related Docs

- [`INDEX.md`](INDEX.md)

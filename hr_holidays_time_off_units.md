# Time Off Duration Units — Days, Half-Days, Hours

> **Module:** `hr_holidays` | **Path:** [`addons/hr_holidays/`](../addons/hr_holidays/)
> Scope: how the Day / Half-Day / Hours unit works across leave types, allocations, requests, and balances. Accrual plans have their own doc: [`hr_holidays_accrual_plans.md`](hr_holidays_accrual_plans.md).

## What Controls the Unit

One field controls everything: **`request_unit` on the time off type** — labeled **"Duration Type"**, the radio at the very top of the type form (Day / Half-Day / Hours) ([`hr_leave_type.py:105`](../addons/hr_holidays/models/hr_leave_type.py#L105), [`hr_leave_type_views.xml:66`](../addons/hr_holidays/views/hr_leave_type_views.xml#L66)).

There is **no per-request choice**. On the request, `request_unit_hours` is a stored compute with no inverse — it is forced to `request_unit == 'hour'` of the selected type ([`hr_leave.py:472`](../addons/hr_holidays/models/hr_leave.py#L472)). Same for half-day ([`hr_leave.py:467`](../addons/hr_holidays/models/hr_leave.py#L467)). If a user still sees days after picking a type, that type's Duration Type is not actually set to Hours (or they are picking a different type with the same name — common in multi-company DBs, where types are duplicated per company).

## How Hours Mode Changes Each Screen

| Screen | Day type | Hour type |
|---|---|---|
| Time off request | Date range + duration in days | Date + **Hours from → to** time selectors ([`hr_leave_views.xml:389`](../addons/hr_holidays/views/hr_leave_views.xml#L389)); duration shows `H:MM hours` ([`hr_leave.py:667`](../addons/hr_holidays/models/hr_leave.py#L667)) |
| Allocation (regular) | "Allocation: N **Days**" | Field swaps to `number_of_hours_display` — "Allocation: N **Hours**" ([`hr_leave_allocation_views.xml:167`](../addons/hr_holidays/views/hr_leave_allocation_views.xml#L167)) |
| Balance / dashboard | remaining days | remaining hours ([`hr_leave_type.py:385`](../addons/hr_holidays/models/hr_leave_type.py#L385)) |

The hour request is entered as a **time range** (e.g. 09:00 → 11:00 = 2:00), not a raw hour count. `date_from/date_to` are built from the picked date plus `request_hour_from/to` ([`hr_leave.py:441`](../addons/hr_holidays/models/hr_leave.py#L441)).

## Storage and Conversion — Days Are Always the Internal Unit

Hours are a display layer. Both leaves and allocations store `number_of_days`; hour figures are converted through the **employee's working calendar**:

- Allocation entered as hours → `number_of_days = hours / employee._get_hours_per_day(date_from)` ([`hr_leave_allocation.py:274`](../addons/hr_holidays/models/hr_leave_allocation.py#L274))
- Hours displayed back → `days * hours_per_day` ([`hr_leave_allocation.py:222`](../addons/hr_holidays/models/hr_leave_allocation.py#L222))
- `_get_hours_per_day()` reads the calendar's **"Average Hour per Day"** (`resource.calendar.hours_per_day`, computed from attendance lines but manually editable — [`resource_calendar.py:102`](../addons/resource/models/resource_calendar.py#L102)); an employee **without a calendar (fully flexible) counts 24 h/day** ([`hr_employee.py:614`](../addons/hr_holidays/models/hr_employee.py#L614))

So a 24-day entitlement on an 8 h/day schedule is allocated as **192 hours**, stored as 24 days, and a 2-hour request consumes 0.25 day internally.

## Worked Example — "24 days, taken by the hour"

1. Time Off > Configuration > Time Off Types: set **Duration Type = Hours** on the type (requires allocation stays on).
2. New Allocation for the employee: the duration field now reads Hours — enter **192** (24 × 8).
3. Employee requests: picks the type, picks today, sets 09:00 → 11:00. Duration shows **2:00 hours**; balance drops from 192 h to 190 h.
4. Prerequisite: the employee's working schedule averages 8 h/day; the conversion uses that number, not a hardcoded 8.

## Gotchas & Non-Obvious Behavior

- **Unit is forced by the type, per request.** No mixed-unit requests on one type; switch the type's Duration Type and every new request follows.
- **Accrual allocations ignore the type's unit.** A running accrual allocation displays in the accrual plan level's unit (`added_value_type`), not the type's `request_unit` ([`hr_leave_allocation.py:303`](../addons/hr_holidays/models/hr_leave_allocation.py#L303)). A plan granting "1 day per month" shows the allocation in days even when the type is hour-based.
- **Flexible employees skew conversions.** No working calendar → 24 h/day divisor; 192 h becomes 8 days instead of 24. Give the employee a real 8 h calendar before allocating.
- **Hours are recomputed from days.** `number_of_hours_display` is derived from stored days × current calendar average; changing the calendar's hours/day changes the displayed hours of existing allocations.
- **Changing the type's unit retro-affects existing records' display** — stored `request_unit_hours` recomputes through the related `leave_type_request_unit`, and balances re-render in the new unit. Days stored internally stay consistent, so no data migration is needed.
- **Half-day mode** is the same mechanic: `request_unit_half` forced from the type, request picks AM/PM per day ([`hr_leave.py:449`](../addons/hr_holidays/models/hr_leave.py#L449)).

## Related Docs

- [`INDEX.md`](INDEX.md)
- [`hr_holidays_accrual_plans.md`](hr_holidays_accrual_plans.md) — accruals grant balances into these same allocations; the plan level's unit wins on accrual allocations
- [`hr_payroll.md`](hr_payroll.md) — validated leaves become work entries; hour-based leaves map to partial-day work entries

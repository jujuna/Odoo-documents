# Handoff: Form 30 plan B session (2026-10-13)

> Read this first in a new session. It says what was decided, what was built, what was found, what was running when the
> session ended, and what to do next. Details live in the files linked below; this page does not repeat them.
> **Tags:** [Certain] checked in code, data or git; [Likely] inferred; [Open] not done.
> **Start prompt for the next session:** `Claude outputs/form30_planB_20261013/NEXT_SESSION_PROMPT.md`.

---

## 1. Read in this order

| # | File | What it is |
|---|---|---|
| 1 | this file | state, next steps, open questions |
| 2 | [form30_entry_redesign_plan.md](form30_entry_redesign_plan.md) | **plan B** (provisional): decisions (section 2), design (4), review findings (5), phases (6), open questions (7) |
| 3 | `Claude outputs/form30_planB_20261013/plans/build_plan_step1.md` | the next build step, ready for the bug-hunter |
| 4 | [gec_income_tax_report.md](gec_income_tax_report.md), [geo_payroll.md](geo_payroll.md) | module docs, with the issues found today at the top |
| 5 | [withholding_form30_plans_saas194.md](../../odoo19/documentations/withholding_form30_plans_saas194.md) | saas-19.4 port notes (branch 19.0) |
| 6 | [withholding_treasury_form30_plan.md](withholding_treasury_form30_plan.md) | background (2026-10-12), partly replaced; its header lists what happened to each item |

## 2. State at a glance

| Item | Status | Where |
|---|---|---|
| Plan B | approved by the user as **provisional** ("after testing we may change it") | plan sections 2, 4 |
| Phase 1: Treasury type and code from the contact (Basis, TBC); BOG refuses treasury payments | **built, committed `f7d3ad1`** (by the user) | gec_odoo_modules 20.0 |
| Phase 2: Pay button on journal-entry lines; hidden on payslip entries; payslip Payment Date written after `action_payslip_paid` | **built, committed `d789e51`** (by the user) | gec_odoo_modules 20.0 |
| Phases 1-2 on gec20_prod1 | **not upgraded** (`-u` not run). The prod1 server (started with `--dev=reload,xml`) already runs the new Python; the Pay button view is not loaded | see section 7 |
| Phases 1-2 on branch 19.0 (saas-19.4) | **not ported** | port procedure in the 19.4 companion |
| Step 1 (3a + 2b + 0b + S1) | **built in the second session, committed by the user `077d628`** (build plan v3; tests 289 + 409 green, repro 12/12, reviewer + verifier, ka_GE) | `Claude outputs/form30_planB_20261013/plans/build_plan_step1.md`, `evidence/step1/` (impact_map_step1.md, result_sweep_step1.md) |
| Phase 0 | **done on the fresh test database `gec20_form30_test`** (generator data; 46 withholding taxes Tax Type None; no bank or rs.ge logins) | `tools/phase0_testdb.py` |
| Phases 3b, 5, 6, 7 | open; 3b facts collected | `evidence/phase3b/facts_phase3b.md` |
| Agent upgrade (impact map, flow sweep, 5 Haiku in parallel) | **done** in `.claude/` | section 8 |
| Coupling map `.claude/skills/odoo-dev/references/coupling-map.md` | **done**: full map of 23 modules (9 scouts + Opus synthesis), verifier checked 22 edges, corrections applied, two missing couplings added (B0 payment amount, R2b salary tax vs 331320) | section 8 |

## 3. Decisions (2026-10-13)

User and accountant; full table in plan section 2.

- Withholding is booked **by hand in the journal entry**, never at payment. The accountant's table books in two steps:
  Dr expense / Cr liability (gross), then Dr liability / Cr tax account.
- **Plan B** (provisional): the entry's tax line names a withholding tax (field **Withholding Tax**,
  `gec_withholding_tax_id`, in gec_localization); Form 30 takes the income type and the rate from that tax, as today's payment
  rows do (`rate = abs(tax.amount)`, never tax ÷ base). The accountant's account table only **proposes** the tax.
- The 23 withholding taxes stay active with **Tax Type = None** (user: yes) instead of being archived. This hides them from
  bills and the Pay dialog and keeps the RS Declaration Rules tab and Apply Tax / RS Change.
- U0 type kept on the entry; U1 an unmatched payment gives a warned row (left out of export by default, tick box includes it);
  **U2** a person paid in parts in two months gets one row per month, each part with its share of gross and tax (accountant:
  50 ÷ 0.8 × 0.2 = 12.50); **U3** two people in one entry give two rows, tax split by net; U4 annex E service type from the tax,
  the contact's default as fallback; **U5** unpaid tax is exported with a note "tax was due with the payment: late".
- Tax law (checked): withheld tax is due **when the person is paid** (Tax Code art. 154; rs.ge guidance); the 15th of next
  month is the declaration deadline. My earlier U5 reason ("due by the 15th") was wrong.
- Option A (Odoo computes the tax on the entry line) was rejected for now: a withholding tax on an entry line books nothing
  (tested by the user on prod1, entry 322), and making it work would change every vendor bill.

## 4. What was built and how it was proven

| Phase | Modules | Proof |
|---|---|---|
| 1 (`f7d3ad1`) | basis_bank, tbc_bank, bog_bank (+ ka_GE.po) | 289/289 existing tests on `gec20_scenario_bankfix3`; runtime repro: Treasury contact gets Treasury + 101001000, cleared on partner change, Basis batch refuses an empty type, BOG refuses |
| 2 (`d789e51`) | gec_localization (field `gec_can_pay`, `action_gec_pay_entry_line`, `account_payment_register.py`, `views/account_move_views.xml`, ka_GE.po), geo_payroll (hide on payslips, date order) | 360/360 existing tests on `gec20_geo_payroll_test`; repro: Cr 100 / Dr 20 / Dr 2 pays **78** and reconciles all three; the Treasury line's payment gets Treasury + 101001000; payslip PSLR/2026/01/0001 shows no Pay; all refusals fire |

Reviews: 2 Opus bug-hunters on the build plan, 2 Opus reviewers on the result, 1 Opus verifier; finding R1 (residual vs
balance direction) confirmed and fixed. Repro addons (`zz_form30_repro`, `zz_form30_repro_payroll`) were installed on the
scratch databases and uninstalled again; their code is kept in `Claude outputs/form30_planB_20261013/repro_addons/`.

## 5. What was found

**External review** (Astra/Sol, saved as `Claude outputs/form30_planB_20261013/review_external/astra_sol_review.md`),
checked by 4 Haiku scouts and 4 Opus verifiers (results: `review_external/verifier_results.md`). Verdicts per finding are in
plan section 5.2. Most important:

- **R13, in built code:** the Pay button pays any open payable credit line to its partner. On prod1 MISC/2026/10/0018 (CIT
  wizard) the 50 dividend tax sits on payable 340120 with the shareholder Emma Granger, so Pay would send the tax to her.
  Fix = step 1 (A3, A5). Phase 2 must not reach prod1 before step 1.
- **Live bugs in today's Form 30 module** (not caused by us): payroll corrections reported in full (R10), emptied annex keeps
  its file (R9), no server lock on exported rows (R14), treaty allowance race (R15). Listed in
  [gec_income_tax_report.md](gec_income_tax_report.md).
- Refuted or overstated: a second Pay dialog after full payment (core refuses it); several-rates-fit for small amounts (no
  non-salary 2026 pair); "a failed export loses the previous one".

**Payroll analysis** (3 scouts + Opus bug-hunter on prod1 data, `evidence/payroll/`): totals match today (September tax
6,287.95 = 331320 credits). Paths that break: S1 rejected/unsent payment + Mark Unpaid keeps the date (step 1 fixes it),
S2 bank-statement settlement never declared, S3 zero net with tax never declared, S4 parts in two months, corrections.
Keep income tax on 331320 (the table's 331310 is not payable). Details in [geo_payroll.md](geo_payroll.md) and plan 4.4.

**Other findings**

- The tax form's **RS Declaration Rules** tab is a window onto the income type's rules (`rs.form30.rate.rule`, 152 rules on
  prod1); Apply Tax / RS Change requires a Purchases tax today (step 1 changes that).
- RS rule lists print "202,504" for April 2025 (integer YYYYMM with a thousands separator): small view fix, not done.
- The 23 withholding taxes on prod1: 18 mapped to a Form 30 income type; gift, goods 3%, non-resident other, telecom, oil & gas
  are not; income types 6, 16, 18 (expired 202411), 20, 21 (returned pension), 22, 23, 24 have no tax (accountant A9).
- Web client error "invalid input syntax for type integer: virtual_1774" when saving an **existing draft** entry after adding a
  tax and deleting a line: an Odoo 20 web-client issue (a line created during the edit is sent as a delete), not our code.
  Workaround: save between steps or start a new entry. Not reproduced on a scratch database.

## 6. Next steps (in order)

1. **Step 1** (build plan v2 ready, bug-hunter already run): builders per module
   (gec_localization, gec_income_tax_report, gec_bank, geo_payroll), the existing tests on the two scratch databases, a
   throwaway repro, reviewer + verifier, ka_GE strings. The user commits.
2. The user runs **phase 0** on prod1 (section 7), then `-u` of phases 1, 2 and step 1 together.
3. Port phases 1-2 (and step 1 once committed) to branch 19.0 (saas-19.4), per the companion.
4. **Phase 3b** (proposal table, amount check, safety net, missing taxes): needs A1 and A9.
5. **Phases 5-6** (row builder, export history): needs A10, U6 and the payroll fixes S2-S4 in the design.
6. Phase 7: READMEs, developer maps, translations, port.

## 7. gec20_prod1 notes and deploy checklist

- The server process runs with `--dev=reload,xml` (seen as pid 61555 on 2026-10-13): it reloads our Python on every file
  change, so phases 1-2 code is live without `-u`; new views and fields need `-u`.
- Before `-u`: settle **BILL/2026/10/0007** (open, carries a WHT tax); decide the **7 test withholding payments**
  (86 = PBNK1/2026/00023 Withhold and Pay, Manual Payment; 88-99 Withhold Only on MISC); set Treasury + 101001000 on Basis
  payments **105 and 107** (an upgrade does not recompute their empty type); set **Tax Type = None** on the 23 withholding taxes.
- Pending Basis test payments **94, 96, 98, 100, 106, 108** (to TEST persons) also have no transfer type: set one or cancel
  them; single and batch sends now refuse a payment without a type.
- Basis/TBC journals preselect **Manual Payment**, which has no Outstanding account; Pay refuses it until the user picks the
  bank-transfer method or Manual Payment gets an Outstanding account. The cash journal has the same gap.
- A Basis batch of only treasury payments now goes as the **op 6 treasury package**, never used before: check it against the
  Basis API before the first live batch. Never send test payments through Basis on prod1 (live link).
- Test drafts **321 and 322** (entries created by the user while testing option A) are still on prod1, unposted: the user
  deletes them.
- MISC/2026/10/0018 (CIT wizard, test) carries the R13 case: before `-u`, reset it, set the State Treasury (partner 73) on
  lines 1024 (CIT) and 1026 (dividend WHT), set Withholding Tax 56 on line 1026, post again.
- Before Tax Type None: the step-1 bug-hunter counted **5 open posted bills** carrying withholding taxes (BILL/2026/10/0007 is
  one); settle or clean them first.

## 8. Agents and process (changed today)

The user found that the agents missed data couplings (the RS rules on taxes, the payroll postings to 331320) and that 3
parallel Haiku agents were too few.

| Change | File |
|---|---|
| New rule: **impact map before any design** (coupling-map rows, one flow sweep per business object, docs of every module in scope), shown to the user before the plan | `.claude/skills/odoo-dev/SKILL.md`, `.claude/skills/odoo-team/SKILL.md` |
| New sweep type **Tier 4: flow sweep** (who produces, reads, configures an object; what the data shows) with today's misses as examples | `.claude/skills/odoo-dev/references/dependencies.md` |
| Scout: flow-sweep task type, "Consumers elsewhere" line, all four `custom_addons` roots | `.claude/agents/odoo-scout.md` |
| Bug-hunter: "Map the consumers" step, unswept consumer = finding, our consumers named; reviewer, verifier, builder: consumer checks | `.claude/agents/*.md` |
| Limits: up to 5 Haiku, 3 Sonnet, 2 Opus, never more than 6 at once | the two skills; `.claude/settings.json` `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` = "6" (from the next session) |
| **Coupling map** of our 22 functional modules by business object | `.claude/skills/odoo-dev/references/coupling-map.md`, built by `workflow_scripts/gec-coupling-map-wf_8b1c428e-3c8.js` (no scratchpad paths, rerunnable as is). Installed 2026-10-13 (raw output, verifier report and the earlier seed in `Claude outputs/form30_planB_20261013/coupling_map/`) |

Backups of every changed agent, skill and settings file: `Claude outputs/agents_backup_20261013/`.
Memory: `project_form30_entry_redesign_20261013.md`, `feedback_impact_map_before_design.md`,
`feedback_throttle_parallel_agents.md` (updated).

## 9. Open questions

| ID | Question | Who |
|---|---|---|
| U6 | Are bank statements imported and matched every month? If not, every Form 30 row is "payment not matched" and left out by default | user |
| A1-A11 | Account-table collisions; non-resident tax account; salary tax account (keep 331320); pension on type 7; dividend accounts; types 22/23; liability accounts that cannot be paid (310990, 120110, 331210); currency; taxes to create for types without one; payroll corrections, advances, zero net; type 18 | accountant (plan section 7) |

## 10. Files

| What | Where |
|---|---|
| Plans | `documentations/form30_entry_redesign_plan.md` (plan B), `form30_entry_redesign_plan_v2_account_rules_20261013.md` (previous design), `withholding_treasury_form30_plan.md` (background), `../../odoo19/documentations/withholding_form30_plans_saas194.md` (19.4) |
| Build plans | `Claude outputs/form30_planB_20261013/plans/` (phases 1-2, step 1; companion backup before plan B) |
| Evidence | `Claude outputs/form30_planB_20261013/evidence/` (`phase1_2/`, `step1/`, `payroll/`, `plan_b_facts/`) |
| External review and verdicts | `Claude outputs/form30_planB_20261013/review_external/` |
| Test logs | `Claude outputs/form30_planB_20261013/test_logs/` |
| Repro addons, PO and xlsx tools | `Claude outputs/form30_planB_20261013/repro_addons/`, `tools/` |
| Workflow scripts of this session | `Claude outputs/form30_planB_20261013/workflow_scripts/` |
| Accountant's table | `~/Downloads/rs.ge Form 30 Income Type (rs.form30.income.type) (1).xlsx` (read with `tools/read_xlsx.py`; contents summarised in plan section 3) |
| Scratch databases used (mine) | `gec20_scenario_bankfix3` (bank modules), `gec20_geo_payroll_test` (payroll, Form 30) |
| Indexes updated | `documentations/INDEX.md` (handoff first, plan B, v2 backup); `../../odoo19/documentations/INDEX.md` links the 19.4 companion |
| Memory notes touched today | `MEMORY.md` (index), `project_form30_entry_redesign_20261013.md`, `feedback_impact_map_before_design.md` (new), `feedback_throttle_parallel_agents.md`, `feedback_use_odoo_agents.md`; from the morning session: `project_wht_treasury_payment_design_20261012.md`, `project_19_0_branch_saas194_backport.md` (gec_prod1 is Odoo 19.0), `feedback_withholding_not_bills.md` |
| Unrelated work today | commit `0f1f7a9` "waybill module update" (rs_waybill, 15 files, the user's own, before this session); untracked `bank_flows.html` in gec_odoo_modules (not ours) |

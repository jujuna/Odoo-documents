# Multi-Branch Cost Allocation — Atlas Group სცენარი

> **სტატუსი:** დაგეგმვის ფაზა — implementation არ დაწყებულა
> **ვერსია:** v3.2 (compressed — 34% line reduction without losing critical content)
> **შექმნის თარიღი:** 2026-04-28
> **ბოლო განახლება:** 2026-04-28
> **მიზანი:** ერთ იურიდიულ პირში მრავალბრენჩიანი ხელფასის და ხარჯის გადანაწილება ანალიტიკურ ანგარიშებზე, რათა Profit & Loss რეპორტი ნახო ბრენჩობრივ ჭრილში
> **დამატებითი მოდულები რომლებიც დაფარავენ:** `hr_timesheet`, `hr_payroll`, `hr_payroll_account`, `account_reports`, `analytic`

---

## TL;DR — Executive Summary

**პრობლემა:** ერთი იურიდიული პირი (Atlas Group), რამდენიმე შიდა ბრენჩი. გვინდა Profit & Loss-ში ცალცალკე ვუყუროთ რამდენი დახარჯა, შემოსავალი, ხელფასი თითო ბრენჩს. სტანდარტულად ოდუ 19 ხელფასს ერთ ხაზად აყრის, პროექტი ერთ ანალიტიკურ ანგარიშს ეთითება, ემპლოის ერთი კონტრაქტი/კომპანია აქვს.

**გადაწყვეტა (Phase A — OPEX-by-Branch):**

1. **Branch ანალიტიკური პლანი** ([analytic.account.plan](../addons/analytic/models/analytic_plan.py#L116)) — accounts B6, B7, HQ, ...
2. **ერთი payslip per ემპლოი** — სტანდარტული ხელფასის თვლა უცვლელი (BASIC, GROSS, NET, taxes)
3. **Per-line Branch on timesheet** ([account_analytic_line.x_plan*_id](../addons/hr_timesheet/models/hr_timesheet.py#L67)) — ყოველი ხაზი ცალცალკე branch-ით
4. **Dynamic analytic_distribution payslip move-ზე** — timesheet-ების real-time aggregation-ით
5. **Post-create direct write** ([account.move.line.analytic_distribution](../addons/account/models/account_move_line.py#L1304)) — `_compute_analytic_distribution`-ის overwrite-ისგან დაცული
6. **P&L Analytic Group By** ([account_reports/account_analytic_report.py](../enterprise/account_reports/models/account_analytic_report.py#L50)) — ცალცალკე სვეტი თითო Branch-ზე

**Out of Phase A scope (Phase B):** Revenue per Branch, COGS per Branch, full Branch P&L. ეს ცალკე initiative-ი — sale_timesheet workflow rework, stock.move analytic propagation, customer invoice mandatory.

**13 კრიტიკული რისკი ([§4](#4-რისკების-სრული-რეესტრი-v2--reclassified)):**

| Priority | რისკი | სტატუსი | Mitigation |
|---|---|---|---|
| 🔴 P0 | Payroll merge/batching → distribution loss | known | `batch_payroll_move_lines=False` + post-create direct write |
| 🔴 P0 | `account.analytic.distribution.model` overwrites | known | Post-create direct write (Option C, §0.14) |
| 🔴 P0 | Old salary rules empty analytic | known | Module 2 deploy + `home_branch_account_id` fallback |
| 🔴 P0 | Credit note Mirror — preserve origin distribution | known | `_mirror_origin_distribution()` (§0.17) |
| 🟡 P1 | Idempotency: `_create_analytic_lines` no guard | known | Avoid manual repost; optional guard |
| 🟡 P1 | Asset depreciation Unallocated | reporting gap | Phase 0 ORM backfill (asset.write triggers draft moves) |
| 🟡 P1 | hr_expense submit posting blocker | known | Phase 3 staged, training |
| 🟡 P1 | sale_timesheet SO line wins | Phase B scope | Out of Phase A |
| 🟡 P1 | Stock COGS Unallocated | Phase B scope | Out of Phase A |
| 🟡 P1 | Bank payment no analytic | Phase B optional | Custom override later |
| 🟡 P2 | Multi-currency analytic constraint | architecture | Single legal entity recommended |
| 🟢 P2 | account_budget conflict | OK | Budget on separate plan |
| 🟢 P2 | Historical posted moves | acceptable | "Unallocated" in P&L is OK |

**Phase rollout:** 0 (Pre-flight backfill) → 1 (Soft optional) → 2 (Custom modules) → 3 (Hard mandatory staged) → 4 (Reports finalization)

**Custom modules:** 
1. `hr_timesheet_branch_per_line` — configurable plan, gated constraint, smart defaults
2. `hr_payroll_branch_breakdown` — read-only breakdown UI, dynamic distribution, credit note Mirror, edge case handling
3. `account_payment_branch_propagation` (optional) — Cash Flow by Branch

**Performance**: <100 emp → no concern; 100-500 → batch=False fine; 500+ → composite index `(employee_id, date, x_plan2_id)` required.

---

---

## 0. გასწორებული მიგნებები — External Review + v3.1 Hardening

გარე review-მ აღმოაჩინა 6 კრიტიკული/მნიშვნელოვანი პრობლემა v1 დიზაინში. ყველა დადასტურდა კოდთან გადამოწმებით. ქვემოთ — შესწორებული გადაწყვეტა.

### 0.1 Payslip override redesign (P0)

**პრობლემა v1:** `_action_create_account_move`-ში `slip = slip.with_context(...)` მხოლოდ ლოკალურ ცვლადს ცვლიდა. ამას გარდა, `batch_payroll_move_lines=True` რეჟიმში `_get_existing_lines` ([hr_payslip.py:254-272](../enterprise/hr_payroll_account/models/hr_payslip.py#L254)) **ერთი account-ის ხაზებს merge-ს უკეთებდა სხვადასხვა payslip-იდან** — ანუ ჩვენი per-employee ბრენჩობრივი distribution-ი ერთ ხაზში ერევა და იკარგება.

**კონკრეტული დადასტურება:**
```python
# hr_payslip.py:254-272 — merge condition:
def _get_existing_lines(self, line_ids, line, account_id, debit, credit):
    existing_lines = (
        line_id for line_id in line_ids if
        line_id['name'] == ...
        and line_id['account_id'] == account_id
        and ((line_id['debit'] > 0 and credit <= 0) or ...)
        and (
            (not line_id['analytic_distribution'] and ...)
            or line_id['analytic_distribution'] and any(acc_id in line_id['analytic_distribution'] 
                for acc_id in line.salary_rule_id.distribution_analytic_account_ids)
            ...
        )
    )
```
Merge ამოწმებს `salary_rule_id.distribution_analytic_account_ids` და `version_id.distribution_analytic_account_ids` — **არა context-დან dynamic distribution**.

**გასწორებული გადაწყვეტა:**

**(A)** Override `_prepare_line_values()` უშუალოდ — ყოველი ხაზი ცალკე ხდება, distribution ცალკეული `line.slip_id`-დან წაიკითხება:

```python
def _prepare_line_values(self, line, account, date, debit, credit):
    line_vals_list = super()._prepare_line_values(line, account, date, debit, credit)
    # მხოლოდ expense ექაუნთებზე გადავიწეროთ
    if account.account_type and account.account_type.startswith('expense'):
        # აქ self არის slip-ი — ის slip რომელიც ამ ხაზს ქმნის
        dynamic_dist = self._get_dynamic_distribution()
        if dynamic_dist:
            for line_vals in line_vals_list:
                line_vals['analytic_distribution'] = dynamic_dist
    return line_vals_list
```

**(B)** `batch_payroll_move_lines = False` კომპანიის სეთინგებში — ან custom `_get_existing_lines` override რომელიც per-slip distribution-ს გაიზრდიდა merge condition-ში.

**(C)** `distribution_analytic_account_ids` ([hr_version.py:11](../enterprise/hr_payroll_account/models/hr_version.py#L11)) უნდა იყოს ფართო — Branch plan-ის ყველა ანგარიში (B6, B7, HQ) — რათა merge-ის protection-ი იცნობდეს ჩვენ ნამდვილ analytic-ს.

### 0.2 Hardcoded `x_plan2_id` → Configurable (P1)

**პრობლემა v1:** `x_plan2_id` ფიქსირებული, `analytic.account_analytic_plan_branch_xmlid` არ არსებობს კოდში.

**ფაქტი:** `_strict_column_name()` ([analytic_plan.py:116-122](../addons/analytic/models/analytic_plan.py#L116)):

```python
def _strict_column_name(self):
    self.ensure_one()
    project_plan, _other_plans = self._get_all_plans()
    return 'account_id' if self == project_plan else f"x_plan{self.id}_id"
```

**გასწორებული გადაწყვეტა:**

```python
# res_config_settings-ზე configurable
class ResConfigSettings(models.TransientModel):
    _inherit = 'res.config.settings'
    
    branch_analytic_plan_id = fields.Many2one(
        'account.analytic.plan',
        related='company_id.branch_analytic_plan_id',
        readonly=False,
    )

# ყველგან — plan._column_name()
class HrPayslip(models.Model):
    _inherit = 'hr.payslip'
    
    def _get_branch_column(self):
        plan = self.company_id.branch_analytic_plan_id
        return plan._column_name() if plan else None
    
    def _compute_branch_lines(self):
        for slip in self:
            col = slip._get_branch_column()
            if not col:
                continue
            timesheets = self.env['account.analytic.line']._read_group(
                domain=[..., (col, '!=', False)],
                groupby=[col],
                aggregates=['unit_amount:sum'],
            )
```

**XML ID-ი ჩვენი მოდულის-ი:**

```xml
<!-- custom_addons/your_module/data/branch_plan_data.xml -->
<odoo noupdate="1">
    <record id="branch_analytic_plan" model="account.analytic.plan">
        <field name="name">Branch</field>
        <field name="default_applicability">optional</field>
    </record>
</odoo>
```

ახლა `your_module.branch_analytic_plan` რეალურად ცხოვრობს — ჩვენ-ი XML ID, ჩვენ ვფლობთ.

### 0.3 Constraint Gating (P1)

**პრობლემა v1:** `@api.constrains` install-ისთანავე mandatory.

**გასწორებული გადაწყვეტა:**

```python
class AccountAnalyticLine(models.Model):
    _inherit = 'account.analytic.line'

    @api.constrains('x_plan2_id', 'project_id')  # field name dynamically — see §0.2
    def _check_branch_required(self):
        # კონფიგურაციით გათიშულია სანამ Phase 3 არ ჩავა
        if not self.env.company.enforce_branch_per_line:
            return
        for line in self.filtered('project_id'):
            col = self.env.company.branch_analytic_plan_id._column_name()
            if not line[col]:
                raise ValidationError(_("Branch is required on every timesheet line."))
```

`enforce_branch_per_line` boolean კომპანიის სეთინგებში — Phase 1 soft, Phase 3 hard.

### 0.4 Branch Breakdown Non-Stored

`branch_line_ids` stored=True ვერ ამოიცნობს external timesheet-ის ცვლილებას (depends-ი მხოლოდ payslip ველებზე). **Solution:** `store=False` — recomputed on form load. Optional explicit recompute hook in `compute_sheet()` და `_action_create_account_move()` (§0.15).

### 0.5 რისკების Reclassification

`_validate_analytic_distribution` ([account_move_line.py:3043-3045](../addons/account/models/account_move_line.py#L3043)) მხოლოდ `display_type == 'product'`-ზე მუშაობს:

| ფლოუ | display_type | ვალიდაცია? |
|---|---|---|
| Customer invoice / Vendor bill | 'product' | ✅ |
| Stock COGS | 'cogs' | ❌ silent |
| Asset depreciation | False | ❌ silent |
| Payslip move | False | ❌ silent |

**Reclassification:** R1 (Asset) and R5 (COGS) → 🟡 reporting gaps, **არა** posting blockers. New 🔴 P0: **R0 — Payroll merge/batching** ([hr_payslip.py:254-272](../enterprise/hr_payroll_account/models/hr_payslip.py#L254)).

### 0.6 Scope Split — Phase A vs Phase B

**Phase A (deliverable):** Salary Expense + Vendor Bills + Manual expenses per Branch.

**Phase B (out of scope, future):** Revenue per Branch (sale_timesheet rework), COGS per Branch (stock.move analytic), full P&L by Branch.

Phase A doesn't promise full Branch P&L — only OPEX section.

### 0.7 home_branch_account_id Fallback

Per-employee fallback (better than global HQ default):

```python
class HrVersion(models.Model):
    _inherit = 'hr.version'
    home_branch_account_id = fields.Many2one('account.analytic.account', string="Home Branch")
```

Resolution order: timesheet aggregation → `home_branch_account_id` → legacy `version.analytic_distribution` → empty + log exception.

### 0.8 Backfill — ORM არა SQL (Suggestion)

**პრობლემა v1:** SQL UPDATE asset analytic-ზე — `asset.write()` propagation-ი draft depreciation moves-ზე ([account_asset.py:530-538](../enterprise/account_asset/models/account_asset.py#L530)) **გვერდს უვლიდა**.

```python
# account_asset.py:530-538 — confirms write triggers move sync
def write(self, vals):
    result = super().write(vals)
    for asset in self:
        for move in asset.depreciation_move_ids:
            if move.state == 'draft' and 'analytic_distribution' in vals:
                move.line_ids.analytic_distribution = vals['analytic_distribution']
```

**გასწორებული:** ORM-ით backfill — draft depreciation moves-ზე ავტო-ცვლილება იქნება.

```python
# scripts/backfill_assets.py
def backfill_asset_analytic(env, default_branch_id):
    assets = env['account.asset'].search([
        '|',
        ('analytic_distribution', '=', False),
        ('analytic_distribution', '=', {}),
        ('state', '!=', 'close'),
    ])
    assets.write({'analytic_distribution': {str(default_branch_id): 100}})
    # ↑ ეს ავტომატურად განაახლებს draft depreciation moves-ს
```

### 0.9 Sales/Invoice Branch Hiding (Phase A clean scope)

ხელფასი არ კითხულობს `sale.order` (BASIC = `version.wage × worked_days`, არც ერთი rule SO-ს არ ეხება). შესაბამისად Branch-ის Sales/Invoice-ზე mandatory აზრი არ აქვს Phase A-ში.

**Applicability config (data XML):**

```xml
<odoo noupdate="1">
    <!-- mandatory only on timesheet -->
    <record id="branch_mandatory_timesheet" model="account.analytic.applicability">
        <field name="analytic_plan_id" ref="branch_analytic_plan"/>
        <field name="business_domain">timesheet</field>
        <field name="applicability">mandatory</field>
    </record>
    <!-- hide on sale_order, invoice -->
    <record id="branch_unavailable_sale" model="account.analytic.applicability">
        <field name="analytic_plan_id" ref="branch_analytic_plan"/>
        <field name="business_domain">sale_order</field>
        <field name="applicability">unavailable</field>
    </record>
    <record id="branch_unavailable_invoice" model="account.analytic.applicability">
        <field name="analytic_plan_id" ref="branch_analytic_plan"/>
        <field name="business_domain">invoice</field>
        <field name="applicability">unavailable</field>
    </record>
    <!-- vendor bill: optional or mandatory (Phase A decision) -->
    <record id="branch_optional_bill" model="account.analytic.applicability">
        <field name="analytic_plan_id" ref="branch_analytic_plan"/>
        <field name="business_domain">bill</field>
        <field name="applicability">optional</field>
    </record>
</odoo>
```

### 0.10 Worked Days vs Timesheets — Orthogonal Dimensions

Worked Days (`hr.work.entry` from schedule + leaves) → BASIC computation. Timesheets (`account.analytic.line`) → Branch ratios. ცალცალკე system-ები — orthogonal.

Breakdown იგებს **proportions-ს, არა absolute hours**: `ratio = hours_per_branch / total_timesheet_hours`. Total timesheet ≠ worked_days არ არის პრობლემა. Edge: `total == 0` → fallback `home_branch_account_id` (§0.7).

### 0.11 Salary Computation Flow + Branch Breakdown Placement

Standard payroll computation ([hr_payslip.py:1010](../enterprise/hr_payroll/models/hr_payslip.py#L1010)) — **არც ერთი ნაბიჯი არ ჰკითხავს sale.order-ს, customer-ს, ან Branch-ს:**

```
Step 1-3: Salary Computation (UNCHANGED)
    localdict = {inputs, worked_days, version, employee, ...}
    Salary rules: BASIC = version.wage × worked_days.WORK100.hours / std_hours
                  GROSS = BASIC + allowances
                  NET   = GROSS - taxes - deductions
    Result: hr.payslip.line records (BASIC=1000, GROSS=1500, NET=1050)
    
                ↓ (ჩვენი custom ერევა მხოლოდ აქ)
                
Step 4: Branch Breakdown (Module 2)
    SELECT x_plan2_id, SUM(unit_amount) FROM account_analytic_line
    WHERE employee_id=? AND date BETWEEN ... AND project_id IS NOT NULL
    GROUP BY x_plan2_id
    → {B6: 60%, B7: 30%, HQ: 10%}

Step 5: Journal Entry (post-create direct write — §0.14)
    DR  Salary Expense 1000   analytic_distribution={B6:60, B7:30, HQ:10}
    CR  Salary Payable 1050
    
Step 6: Move._post() → _create_analytic_lines()
    analytic.line: -600 on B6, -300 on B7, -100 on HQ

Step 7: P&L by Branch — column per branch with proportional amounts
```

**ცვლის** მხოლოდ move line-ის `analytic_distribution`-ს და `account.analytic.line` records-ებს. **არ ცვლის** worked days, salary rules, BASIC/GROSS/NET, single payslip, single paycheck.

### 0.12 `distribution_analytic_account_ids` — Computed, არა Manual

[analytic_mixin.py:26-64](../addons/analytic/models/analytic_mixin.py#L26) — **computed Many2many**, extract-ია `analytic_distribution` JSON-ის key-ებიდან. UI-სთვის და search-ისთვის. **ხელით არ ვადგენთ.**

| ველი | რას ვადგენთ | რა ხდება |
|---|---|---|
| `version.analytic_distribution` | არ ვადგენთ | ცარიელი — Module 2 override per-slip |
| `version.distribution_analytic_account_ids` | არასოდეს | computed auto-populated |
| `version.home_branch_account_id` | **ჰო — fallback** | custom M2O |
| `move.line.analytic_distribution` | **ჰო — post-create direct write** | dynamic per-slip |

**Merge consequence:** [hr_payslip.py:260-269](../enterprise/hr_payroll_account/models/hr_payslip.py#L260) — როცა rule + version analytic_distribution **ცარიელია**, merge condition `any(acc_id in [] ...)` → False. **Lines do NOT merge per slip → მუშაობს ჩვენთვის ბუნებრივად.** Custom merge override არ სჭირდება.

### 0.13 Idempotency Risk — `_create_analytic_lines` Duplicates

[account_move_line.py:3076-3087](../addons/account/models/account_move_line.py#L3076) — **არ არის idempotency check**. Standard flows-ი თვითონ აარიდებს double-post-ს, მაგრამ manual repost ან buggy custom code → analytic.lines გადუბლირდება.

**Optional guard Module 2-ში:** payslip move-ებზე override `_create_analytic_lines` რომელიც skip-ს უკეთებს თუ `analytic_line_ids` უკვე არსებობს.

### 0.14 `account.analytic.distribution.model` — Auto-distribution Overwrite Risk

**რისკი:** [account_move_line.py:1120-1133](../addons/account/models/account_move_line.py#L1120) — `_compute_analytic_distribution` ფარდდება accountant-ის კონფიგურაციულ წესებს (Settings → Accounting → Analytic Distribution Models). თუ წესი მატჩდება (e.g. "Partner=Lasha, Account=60* → {HQ:100}"), **ჩვენი dynamic distribution silently overwrite-დება**.

**Vulnerability:** payslip move-ი არ არის invoice → `not is_invoice` ტრიგერი მუშაობს, compute გაეშვება. Dict merge `|`: model rule-ი იმარჯვებს conflicting keys-ზე.

**გადაწყვეტა — Post-create direct write:**

```python
def _action_create_account_move(self):
    res = super()._action_create_account_move()
    for slip in self.filtered('move_id'):
        for line in slip.move_id.line_ids:
            if line.account_id.account_type and line.account_id.account_type.startswith('expense'):
                line.analytic_distribution = slip._get_dynamic_distribution()
    return res
```

Move ფიქსირდება default analytic-ით → ჩვენი direct write ცვლის expense lines-ზე → triggers `_inverse_analytic_distribution` → unlinks/recreates analytic.lines ([account_move_line.py:1304-1321](../addons/account/models/account_move_line.py#L1304)). **`_compute_analytic_distribution` ხელახლა არ გაეშვება** — no trigger field changed. **Idempotent + safe.**

### 0.15 compute_sheet Hook + Explicit Recompute

[hr_payslip.py:785-802](../enterprise/hr_payroll/models/hr_payslip.py#L785) — `compute_sheet()` ხელახლა-ანგარიშობს მხოლოდ `line_ids`-ს. `store=False` `branch_line_ids` next form access-ზე თვითონ recompute-ს უკეთებს — დამატებითი override არ სჭირდება. Optional: `_action_create_account_move`-ში `invalidate_recordset(['branch_line_ids'])` move creation-მდე.

### 0.16 Multi-Company Analytic

[analytic_account.py:16](../addons/analytic/models/analytic_account.py#L16) — `_check_company_domain = check_company_domain_parent_of`. Atlas Root-ზე analytic account-ი ხილვადია children-ში (parent_of). Inter-company rules ([account_move.py:147-159](../enterprise/account_inter_company_rules/models/account_move.py#L147)) **ფილტრავს** company-restricted analytics → ცალკე analytic per legal entity საჭიროა multi-company-ში.

**Recommendation Atlas-ისთვის:**

| სცენარი | Strategy | Branch analytics |
|---|---|---|
| **Single legal entity, multiple cost centers** | მხოლოდ analytic plan, არა Odoo branches | B6/B7/HQ on Atlas Root, company_id=Atlas Root |
| **Atlas Root + 1 sub-company (regulatory split)** | Hybrid: ცალკე analytic per legal entity | B6_AtlasRoot + B6_SubCo (separate accounts), inter-company rules ცალცალკე distribution model |
| **5+ ცალკე legal entities** | სრული multi-company + per-entity analytic | მანუალურად per-company variants |

**Phase A scope:** მხოლოდ Single legal entity-ი — არა Odoo branches. ერთი Atlas Root, ყველა Branch analytic მასზე.

---

### 0.17 Credit Notes / Payslip Refunds (CRITICAL)

[hr_payslip.py:723-746](../enterprise/hr_payroll/models/hr_payslip.py#L723) — `_action_refund_payslips()` ქმნის credit_note copy: `credit_note=True`, amounts negated, `origin_payslip_id=original`. Storno ([hr_payslip.py:186-209](../enterprise/hr_payroll_account/models/hr_payslip.py#L186)) reverses debit/credit signs.

**კრიტიკული ხარვეზი:** თუ credit note dynamic compute გააკეთებს fresh timesheet-დან, edited timesheets-ი → distribution differs from original → P&L per branch ვერ ნულდება (Total OK, branches drift).

**Solution — Credit Note Mirror:** credit note iterates `origin_payslip_id.move_id` expense lines და კოპირებს ფიქსირებულ `analytic_distribution`-ს. Fresh compute არ ხდება. ერთეულ ტესტი: original `{B6:60, B7:40}` → edit timesheets → refund → credit note distribution = **`{B6:60, B7:40}`** (not edited values) → P&L: B6=0, B7=0 ✓.

### 0.18 Concurrency — Snapshot Isolation Sufficient

**ფაქტი:** Odoo PostgreSQL default isolation = REPEATABLE READ ([sql_db.py:373](../odoo/sql_db.py#L373)).

**რას ნიშნავს:**
- Transaction-ი snapshot-ს იღებს start-ზე
- ერთი ტრანზაქციის განმავლობაში მონაცემთა ცვლილებები სხვა ტრანზაქციიდან არ ჩანს
- ORM cache შეიძლება stale იყოს (cache lifetime = cursor lifetime)

**Behavior:** Snapshot isolation (transaction reads consistent T0 state). Mid-batch User B timesheet edit **არ ჩანს** running batch-ისთვის — ეს მისაღებია (consistency guarantee). UI form refresh shows current state, posting uses post-time snapshot.

**Phase A recommendation:** არანაირი snapshot pattern — default Odoo behavior საკმარისია. თუ multiple concurrent payroll officers-ი პრობლემას შექმნიან, optional `distribution_snapshot` JSON field დაემატება Phase A.5-ში.

### 0.19 Edge Cases — Comprehensive List

| # | Edge Case | Behavior | Module 2 Handler |
|---|---|---|---|
| **EC1** | Employee without `version_id` | `_compute_version_id` sets False if employee missing ([hr_payslip.py:1220](../enterprise/hr_payroll/models/hr_payslip.py#L1220)). Then `version_id.analytic_distribution` raises AttributeError. | Null check: `if not self.version_id: return {}` |
| **EC2** | Multiple active versions | `_get_version()` picks `max(versions, key=date_version)` ([hr_employee.py](../addons/hr/models/hr_employee.py)). Latest by `date_version` wins. | Document; may differ from contract date overlap |
| **EC3** | Salary structure without `journal_id` | Filter at [hr_payslip.py:64](../enterprise/hr_payroll_account/models/hr_payslip.py#L64) — payslip never creates move | branch_line_ids compute OK; no move = no analytic.line. Acceptable. |
| **EC4** | Mid-period employee transfer | `payslip.company_id` from employee — **single value**. Cross-company timesheet split breaks. | Domain: filter timesheets by `company_id IN parent_ids` |
| **EC5** | Negative timesheet entries | `unit_amount < 0` (corrections) | Total could be 0 or negative. Guard: `if total_hours <= 0: fallback` |
| **EC6** | Archived analytic account | Active timesheet references `active=False` account | Filter: `('x_plan2_id.active', '=', True)` in domain |
| **EC7** | Multi-company employee | Subsidiary user accessing payslip with parent's analytic | check_company_domain_parent_of allows; UI may not show |
| **EC8** | `compute_sheet` failure | Error in salary rule formula → state stays draft, line_ids partial | Don't rely on line_ids before state='validated' |
| **EC9** | `error_count > 0` | [hr_payslip.py:787](../enterprise/hr_payroll/models/hr_payslip.py#L787) blocks compute_sheet | branch_line_ids compute should skip when error_count |
| **EC10** | Template payslips | Structures can be templates | Filter: `slip.struct_id.country_id` set, exclude templates |
| **EC11** | Multi-step credit note chain | Original → credit → reissue | Each step uses Mirror logic (§0.17) for credit notes |
| **EC12** | `date_to` in locked period | Move post fails | Validate before action_payslip_done; user-friendly error |
| **EC13** | `total_hours = 0` (full leave) | Division by zero | Fallback `version.home_branch_account_id` (§0.7) |
| **EC14** | `home_branch_account_id` empty + 0 timesheets | No analytic available | Log exception, distribution stays empty (Unallocated) |
| **EC15** | Salary attachment on credit note | Auto-negated ([hr_payslip.py:307](../enterprise/hr_payroll/models/hr_payslip.py#L307)) | No special handling — works correctly with Mirror |
| **EC16** | `account_storno=False` on company + credit note | Standard reversal (negative amounts), not storno | Mirror still works — distribution preserved |

### 0.20 Performance Thresholds

| Scale | `batch_payroll_move_lines` | Index | Batch Time |
|---|---|---|---|
| <100 emp | False | none | <5 sec |
| 100-500 | False (correctness) | + (employee_id, date) | 10-30 sec |
| 500+ | False + custom merge (Phase A.5) | + composite (employee_id, date, x_plan2_id) | optimization-dependent |

batch=True performance-სასარგებლოა მაგრამ **merge-ი per-slip distribution-ს კარგავს** ([hr_payslip.py:254-272](../enterprise/hr_payroll_account/models/hr_payslip.py#L254)). v3.1: batch=False, Phase A.5-ში distribution-aware custom merge.

Custom index Module 2-ში — `post_init_hook`:
```python
env.cr.execute(SQL("""
    CREATE INDEX IF NOT EXISTS account_analytic_line_employee_date_plan2_idx
    ON account_analytic_line(employee_id, date, x_plan2_id)
    WHERE project_id IS NOT NULL
"""))
```

500 emp × 150 timesheets: without index ~50-200ms/slip → 25-100 sec; with index ~5-15ms/slip → 2.5-7.5 sec.

### 0.21 Time Off — `project_timesheet_holidays` not `hr_payroll_holidays`

[project_timesheet_holidays/account_analytic.py:9-12](../addons/project_timesheet_holidays/models/account_analytic.py#L9) — community module ქმნის timesheet ხაზებს leaves-დან (`holiday_id`, `global_leave_id` fields). `hr_payroll_holidays` enterprise მხოლოდ work entry filtering-ს აკეთებს.

ფლოუ: Leave → `account.analytic.line` (project_id=Internal) → ჩვენი distribution-ი ხედავს default x_plan2_id-ით Internal პროექტიდან.

---

## 1. ბიზნეს მოთხოვნა

ერთი იურიდიული პირი ("Atlas Group LLC") + რამდენიმე **შიდა ბრენჩი** (B6 Batumi, B7 Kutaisi, HQ Tbilisi). ბრენჩი არ არის ცალკე იურიდიული პირი (no VAT, no separate tax return), მაგრამ გვინდა ცალკე ვუყუროთ ვინ რამდენი იშოვა/დახარჯა.

**პრობლემის 3 ფენა:**

| ფენა | პრობლემა | მოთხოვნა |
|---|---|---|
| დროის ჩაწერა | ერთ ტასკზე ნაწილი B6, ნაწილი B7 | Timesheet per-line ბრენჩობრივად |
| ხელფასის ხარჯი | ერთი contract, ერთი paycheck — მრავალი ბრენჩისთვის | Per-branch cost allocation |
| ფინანსური რეპორტი | Salary ერთ ხაზად | P&L Operating Expenses → ცალცალკე სვეტი ბრენჩზე |

**არ ვაკეთებთ:** ცალკე legal entities, ცალკე payslip/contract/paycheck. **ვაკეთებთ:** Branch analytic plan + dynamic analytic_distribution payslip-ზე + P&L Analytic Group By.

---

## 2. არქიტექტურული გადაწყვეტა

### 2.1 პრინციპები

| პრინციპი | მნიშვნელობა |
|---|---|
| **ერთი წყარო ჭეშმარიტებისა** | `account.analytic.line.x_plan2_id` — ყოველი timesheet ხაზი ცალცალკე ატარებს Branch tag-ს |
| **არ ვცვლით ოდუ-ს ბირთვს** | არ ვცვლით `hr.employee`, `hr.version`, `account.move.line` მოდელებს — მხოლოდ override მცირე custom-ით |
| **ფონური ცხრილები ხელშეუხებელია** | `analytic_distribution` JSON ფორმატი ისეთად რჩება, როგორც ოდუ ელის |
| **ხილული workflow** | Payroll officer ხედავს breakdown-ს, თვითონ შეუძლია გადაამოწმოს, აუდიტი გამჭვირვალეა |

### 2.2 მონაცემთა მოდელის ჯაჭვი

```
res.company "Atlas Root"                      ← legal employer, ერთი
   │
   ├── account.analytic.plan "Project"  (id=1, default)   ← ჩაშენებული
   ├── account.analytic.plan "Branch"   (id=2, custom)    ← ჩვენი მთავარი
   │     ├── account.analytic.account "B6"
   │     ├── account.analytic.account "B7"
   │     └── account.analytic.account "HQ"
   │
   └── account.analytic.applicability                     ← როდის სავალდებულოა
         business_domain='timesheet'   applicability='mandatory'
         business_domain='bill'        applicability='mandatory'
         business_domain='invoice'     applicability='optional'

project.project (1 პროექტი)
   ├── account_id  = AA_x       (Project plan, default for timesheets)
   └── x_plan2_id  = B6 (default, can be overridden per timesheet line)

project.task (ერთ პროექტს ბევრი task)
   └── (ბრენჩი ფიქსირებული აქ NEVER — სხვაგვარად ისევ ერთ B6-ში გავიჭდებით)

account.analytic.line (timesheet ხაზი — fundamental granularity!)
   ├── ხაზი #1: 5h, x_plan2_id=B6
   ├── ხაზი #2: 3h, x_plan2_id=B7   ← user-override per line
   └── ხაზი #3: 2h, x_plan2_id=B6

hr.payslip
   ├── ერთი ჩვეულებრივი payslip ემპლოიზე
   └── + custom: branch_line_ids (One2many — read-only breakdown)
            ├── B6: 60h, 60%, 720 GEL
            ├── B7: 30h, 30%, 360 GEL
            └── HQ: 10h, 10%, 120 GEL

account.move (payslip-ის ჯურნალის ჩანაწერი)
   └── line_ids
       ├── DR Salary Expense 1,200  analytic_distribution={B6:60,B7:30,HQ:10}
       ├── CR Salary Payable 1,050
       └── ...

account.analytic.line (move post-ი ავტო-ქმნის)
   ├── -720 GEL on Salary Expense, x_plan2_id=B6
   ├── -360 GEL on Salary Expense, x_plan2_id=B7
   └── -120 GEL on Salary Expense, x_plan2_id=HQ
```

### 2.3 P&L by Branch — საბოლოო შედეგი

```
                                      B6      B7      HQ      Total
                                      ─────────────────────────────
Revenue                              80,000  50,000  20,000  150,000
Less Cost of Revenue                      0       0  (15,000) (15,000)
─────────────────────────────────────────────────────────────────────
Gross Profit                         80,000  50,000   5,000  135,000

Less Operating Expenses
  600000 Salary Expense              (720)   (360)   (120)  (1,200)
  610000 Income Tax Expense          (180)   (90)    (30)   (300)
  620000 SSC Expense                 (60)    (30)    (10)   (100)
  640000 Rent Expense                (5,000) (3,000) (4,000) (12,000)
─────────────────────────────────────────────────────────────────────
Operating Income (Loss)              74,040  46,520     840  121,400
─────────────────────────────────────────────────────────────────────
Net Profit                           74,040  46,520     840  121,400
```

---

## 3. ფაქტები კოდიდან (დადასტურებული)

### 3.1 Timesheet-ი არის Analytic Line

ყველა timesheet ფიზიკურად არის `account.analytic.line` ჩანაწერი ([hr_timesheet.py:17](../addons/hr_timesheet/models/hr_timesheet.py#L17)):

```python
class AccountAnalyticLine(models.Model):
    _inherit = 'account.analytic.line'
    
    project_id = fields.Many2one('project.project', ...)
    task_id    = fields.Many2one('project.task', ...)
```

Plan-ის ანგარიშები ([analytic_plan.py:116-122](../addons/analytic/models/analytic_plan.py#L116)):

| Plan | Column |
|---|---|
| Project (root, hardcoded) | `account_id` |
| Branch (id=2) | `x_plan2_id` |
| სხვა plan-ები | `x_plan{plan_id}_id` |

### 3.2 Project-დან Timesheet-ზე Plan-ების კოპირება

წყარო: [hr_timesheet.py:416-432](../addons/hr_timesheet/models/hr_timesheet.py#L416)

```python
def _timesheet_preprocess_get_accounts(self, vals):
    project = self.env['project.project'].sudo().browse(vals.get('project_id'))
    ...
    return {
        fname: project[fname].id
        for fname in self._get_plan_fnames()
    }
```

ანუ: **timesheet ხაზი default-ად მემკვიდრე ხდება ყველა plan-ის ანგარიშისგან პროექტიდან**. Per-line override დაშვებულია, რადგან ველებზე `readonly=False, store=True`.

### 3.3 Per-Line Override შესაძლებელია

[hr_timesheet.py:67-72](../addons/hr_timesheet/models/hr_timesheet.py#L67):

```python
project_id = fields.Many2one('project.project', ...,
    compute='_compute_project_id', store=True, readonly=False)
```

ემპლოი UI-ში ხელით ცვლის `x_plan2_id`-ს ცალკეულ ხაზზე — ცვლილება ფიქსირდება. ეს გვაძლევს per-timesheet-line გრანულარულობას ბრენჩზე.

### 3.4 `auto_account_id` არ არის რეალური სვეტი

[analytic_line.py:23-32](../addons/analytic/models/analytic_line.py#L23):

```python
# Magic column that represents all the plans at the same time, except for the compute
# where it is context dependent, and needs the id of the desired plan.
auto_account_id = fields.Many2one(
    comodel_name='account.analytic.account',
    string='Analytic Account',
    compute='_compute_auto_account',
    inverse='_inverse_auto_account',
    search='_search_auto_account',
)
```

**ფაქტი:** არ არის DB სვეტი. UI helper-ია რომელიც კონტექსტიდან ხედავს `analytic_plan_id`-ს და კითხულობს შესაბამის plan-ის სვეტს.

### 3.5 Move Post-ი ქმნის Analytic Line-ებს ავტომატურად

[account_move.py:5586](../addons/account/models/account_move.py#L5586):

```python
# Create the analytic lines in batch is faster as it leads to less cache invalidation.
to_post.line_ids._create_analytic_lines()
```

[account_move_line.py:3076-3087](../addons/account/models/account_move_line.py#L3076):

```python
def _create_analytic_lines(self):
    self._validate_analytic_distribution()
    analytic_line_vals = []
    for line in self:
        analytic_line_vals.extend(line._prepare_analytic_lines())
    self.env['account.analytic.line'].with_context(skip_analytic_sync=True).create(analytic_line_vals)
```

**ფაქტი:** payslip post-ი → move post-ი → analytic line-ები ავტო-შექმნა. **არანაირი დამატებითი ლოგიკა არ სჭირდება ამ ნაბიჯს.**

### 3.6 Analytic Distribution-ის გადანაწილების ლოგიკა

| `analytic_distribution` ფორმატი | რას ქმნის |
|---|---|
| `{"B6": 60, "B7": 40}` (ცალკე keys) | **2 ცალკე analytic.line** — ერთი B6-ზე, ერთი B7-ზე |
| `{"B6,B7": 100}` (combined key) | **1 analytic.line** რომელშიც **ორივე** plan column შევსებულია |
| `{}` ან `null` | **არანაირი analytic.line** — move post-დება, მაგრამ ფაქტობრივად არ გადანაწილდება |

ჩვენი use case: **ცალკე keys** — `{B6_id: 60, B7_id: 40}` — რადგან B6 და B7 ერთი plan-ის (Branch) ანგარიშებია და ცალკე უნდა იჯდნენ ანალიტიკურ ხაზებზე.

### 3.7 Payslip Move Line Default Analytic

[hr_payslip.py:147,161](../enterprise/hr_payroll_account/models/hr_payslip.py#L147):
```python
'analytic_distribution': line.salary_rule_id.analytic_distribution
                        or line.slip_id.version_id.analytic_distribution,
```

Default-ად ეტარება salary rule-დან ან version-დან. ჩვენი Module 2 post-create direct write-ით ცვლის ამას dynamic-ად.

### 3.8 P&L Analytic Group By + Shadow Query

[account_analytic_report.py:50-96](../enterprise/account_reports/models/account_analytic_report.py#L50) — Branch plan filter → ცალკე სვეტი თითოეულ ანგარიშზე + Total.

[account_analytic_report.py:99-147](../enterprise/account_reports/models/account_analytic_report.py#L99) — რეპორტი **არ კითხულობს `analytic_distribution` JSON-ს**. SQL shadow query-ით წაიკითხავს ფიზიკურ `account.analytic.line` ჩანაწერებს (auto-created move post-ზე). გადანაწილება უკვე ფიზიკურ ხაზებშია — რეპორტი ჯამდება.

### 3.9 P&L სტრუქტურა — სად მიდის ხელფასი

წყარო: [profit_and_loss.xml](../enterprise/account_reports/data/profit_and_loss.xml)

| სექცია | XML ID | Account Type-ები | Engine |
|---|---|---|---|
| Revenue | `account_financial_report_revenue0` | `income` | domain (leaf) |
| Less Cost of Revenue | `account_financial_report_cost_sales0` | `expense_direct_cost` | domain (leaf) |
| **Gross Profit** | `account_financial_report_gross_profit0` | — | aggregation |
| **Less Operating Expenses** ⭐ | `account_financial_report_expense0` | **`expense`** | **domain (leaf)** |
| **Operating Income (Loss)** | `account_financial_report_operating_income0` | — | aggregation |
| Other Income | `account_financial_report_other_income0` | `income_other` | domain (leaf) |
| Other Expenses | `account_financial_report_depreciation0` | `expense_other`, `expense_depreciation` | domain (leaf) |
| **Net Profit** | `account_financial_report_net_profit0` | — | aggregation |

**ხელფასი ლანდდება "Less Operating Expenses"-ში** რადგან salary rule-ების GL ექაუნთებს აქვთ `account_type='expense'` (default).

### 3.10 Sale-Timesheet Chain

[hr_timesheet.py:213-239](../addons/sale_timesheet/models/hr_timesheet.py) — billable პროექტისთვის:

```python
def _timesheet_preprocess_get_accounts(self, vals):
    so_line = self.env['sale.order.line'].browse(vals.get('so_line'))
    if not (so_line and (distribution := so_line.sudo().analytic_distribution)):
        return super()._timesheet_preprocess_get_accounts(vals)
    # SO line's analytic_distribution overrides project's
```

**ფაქტი:** Billable პროექტებზე **SO line-ის analytic იმარჯვებს** პროექტის default-ზე. Invoice line-იც SO line-ის analytic-ს კოპირებს ([account_move_line.py:41-46](../addons/sale/models/account_move_line.py#L41)). Timesheet ხაზი თუ user-მა ხელით შეცვალა B7-ად, ეს ცვლილება **invoice line-ზე გადატანილი არ არის** — ფინალური invoice ATA SO line-ს მისდევს.

### 3.11 Validation Gating

[analytic_mixin.py:174-188](../addons/analytic/models/analytic_mixin.py#L174):

```python
def _validate_distribution(self, **kwargs):
    if self.env.context.get('validate_analytic', False):  # ← FLAG MUST BE SET
        mandatory_plans_ids = [...]
        # Raises ValidationError if 100% distribution not found for mandatory plan
```

**ფაქტი:** `applicability='mandatory'` თვითონ არ არის საკმარისი. Validation მოქმედებს მხოლოდ თუ **`context={'validate_analytic': True}`** ფიქსირდება. ოდუ-ში სტანდარტულად:

| ფლოუ | რთავს? |
|---|---|
| `hr_timesheet` create/write | ✅ რთავს ([hr_timesheet.py:421](../addons/hr_timesheet/models/hr_timesheet.py#L421)) |
| `hr_expense.action_post` | ✅ რთავს |
| `account_move.action_post` (invoice/bill) | ✅ რთავს მხოლოდ `is_invoice() OR is_purchase()` |
| `hr_payroll_account._action_create_account_move` | ❌ **არ რთავს** |
| Manual journal entry | ❌ არ რთავს |

⚠️ **მნიშვნელოვანი:** payslip-ის move ცარიელი analytic_distribution-ით **ფიქსირდება უპრობლემოდ**. ჩვენი dynamic override მთავარი დაცვაა.

---

## 4. რისკების სრული რეესტრი (v3.1 — final)

### 4.1 კრიტიკული რისკები (🔴 P0)

**R0 — Payroll Move Line Merge & Batching** ([hr_payslip.py:254-272](../enterprise/hr_payroll_account/models/hr_payslip.py#L254))
`batch_payroll_move_lines=True` რეჟიმში `_get_existing_lines` ხაზებს merge-ს უკეთებს გამოვიდე slip-ი. Per-employee distribution იკარგება. **Mitigation:** `batch_payroll_move_lines=False` + Module 2 (§0.1).

**R2 — Old Salary Rules / Versions ცარიელი Analytic** ([hr_payslip.py:147,161](../enterprise/hr_payroll_account/models/hr_payslip.py#L147))
Module 2-ის deploy-მდე payslip ცარიელი analytic-ით silently post-დება (display_type ≠ 'product'). P&L Branch column-ები ცარიელი, Total OK. **Mitigation:** Module 2 + `home_branch_account_id` fallback (§0.7).

**R3 — sale_timesheet Invoice Chain** ([hr_timesheet.py:213-239](../addons/sale_timesheet/models/hr_timesheet.py))
Billable პროექტზე SO line-ის analytic იმარჯვებს timesheet-ის override-ზე. Invoice line-ი SO-ს მისდევს, არა timesheet-ს. **Mitigation:** Phase B scope (out of A).

### 4.2 საშუალო რისკები (🟡 — Reporting Gaps, არა Posting Blockers)

**R1' — Asset Depreciation Reporting Gap** ([account_asset/account_move.py:273-295](../enterprise/account_asset/models/account_move.py#L273))
Asset depreciation move ხაზებს `display_type='product'` არ აქვთ → ვალიდაცია გამოტოვებს. ცარიელი analytic post-დება silently → "Unallocated" P&L by Branch-ში. **Mitigation:** Phase 0 ORM backfill (`asset.write` triggers draft depreciation moves sync — §0.8).

**R5' — Stock COGS Reporting Gap** ([stock_account/account_move.py:139,156](../addons/stock_account/models/account_move.py#L139))
COGS ხაზი `display_type='cogs'` — ვალიდაცია გამოტოვებს. `stock.move._get_analytic_distribution()` default ცარიელი. **Mitigation:** Phase B custom override.

**R4 — hr_expense Mandatory Posting Blocker** ([hr_expense/analytic.py](../addons/hr_expense/models/analytic.py))
Expense ხაზებს `display_type='product'` აქვთ — mandatory ვალიდდება. ცარიელი Branch-ით submit ფეილდება. **რეალური posting blocker-ია** (განსხვავებით R1'/R5'). **Mitigation:** Phase 3 staged + employee training.

**R6 — Multi-Currency Analytic Account** ([analytic_account.py:61-102](../addons/analytic/models/analytic_account.py#L61))
Analytic account ერთ company-ს ეკუთვნის, currency related-ია. Cross-company sub-branch-ებით სხვადასხვა ვალუტით — ცალკე analytics საჭირო. **Mitigation:** Single legal entity recommended (§0.16).

**R7 — Bank Payment ცარიელი Analytic** ([account_payment.py](../addons/account/models/account_payment.py))
Salary NET payment bank-ზე — ცარიელი analytic. Cash Flow by Branch ცარიელი. **Mitigation:** Phase B optional Module 3.

### 4.3 დაბალი რისკები (🟢)

#### R8 — account_budget Conflict

**არ არის რეალური რისკი:** Budget-ი ცალ-ცალკე analytic.account-ზე იქმნება. Branch plan ცალკეა Project plan-ისგან, არ ერევა.

#### R9 — Deferred Revenue/Expense

**არ არის რეალური რისკი:** [account_move.py:788](../enterprise/account_accountant/models/account_move.py#L788) — deferred entry split-ი analytic_distribution-ს ხელუხლებლად ატარებს.

#### R10 — Historical Posted Moves

**არ არის ბლოკავი რისკი:** ისტორიული posted move-ი state='posted'-ში — validation არ ეხება მათ retroactively. ცარიელი analytic-ით P&L by Branch-ში "Unallocated" ჩანან.

### 4.4 რისკების შეჯამება ცხრილად — v3.1 final

| # | ხარვეზი | ფაილი | ტიპი | სიმძიმე | ფაზა / Mitigation |
|---|---|---|---|---|---|
| **R0** | **Payroll merge/batching loses distribution** | hr_payroll_account | Logical bug | 🔴 P0 | `batch_payroll_move_lines=False` + Module 2 (§0.1, §9.2) |
| **R-NEW1** | **distribution.model overwrites our analytic** | account | Silent override | 🔴 P0 | Post-create direct write (§0.14, §9.2) |
| **R-NEW2** | **`_create_analytic_lines` no idempotency** | account | Duplicate records | 🟡 P1 | Don't double-post; optional guard (§0.13) |
| **R-NEW3** | **Credit note dynamic compute → P&L drift** | hr_payroll_account | Net-zero broken | 🔴 P0 | Mirror origin distribution (§0.17, §9.2) |
| R2 | Old salary rules/versions empty analytic | hr_payroll_account | Reporting gap | 🔴 P0 | Module 2 + home_branch_account_id |
| R3 | sale_timesheet SO line wins | sale_timesheet | Reporting accuracy | 🔴 | **Phase B (out of A scope)** |
| R1' | Asset depreciation Unallocated | account_asset | Reporting gap | 🟡 | Phase 0 ORM backfill |
| R5' | Stock COGS Unallocated | stock_account | Reporting gap | 🟡 | **Phase B (out of A scope)** |
| R4 | hr_expense submit posting blocker | hr_expense | Posting blocker | 🟡 | Phase 3 staged + training |
| R6 | Multi-currency analytic constraint | analytic | Architecture | 🟡 | Single legal entity recommended (§0.16) |
| R7 | Bank payment no analytic | account | Reporting gap | 🟡 | Phase B optional |
| R8-R10 | account_budget / deferred / history | various | OK | 🟢 | — |

---

## 5. იმპლემენტაციის გეგმა — ფაზობრივი (Phase A vs B)

### Scope Split: Phase A vs Phase B

**Phase A — OPEX by Branch** (this document's focus)

| რას მივიღებთ | როგორ | სიმძიმე |
|---|---|---|
| Salary Expense per Branch | Module 1 + Module 2 | High value |
| Vendor Bills per Branch | applicability mandatory for `bill` | Medium value |
| Manual expense entries per Branch | accountant manual tagging | Medium |
| Operating Expenses sub-totals per Branch | inherent — domain engine splits | Free |
| **Operating Income per Branch** | aggregation engine — Revenue is only Total | **Partial** |

**Phase B — Revenue + COGS by Branch** (NOT in this v2 doc; future scope)

| რას მივიღებთ | რა გვჭირდება |
|---|---|
| Revenue per Branch | applicability mandatory for `invoice`, sale_timesheet workflow rework |
| COGS per Branch | stock.move analytic propagation, picking → analytic logic |
| Asset Depreciation per Branch | asset analytic backfill (started in Phase 0) |
| **Full Branch P&L** | Phase A + Phase B combined |

### Phase 0 — Pre-flight (ერთხელ, წინასწარ)

| ნაბიჯი | მოქმედება | პასუხისმგებელი |
|---|---|---|
| 0.1 | არქიტექტურული გადაწყვეტილება: მხოლოდ analytic plan **ან** plan + Odoo branches (`res.company.parent_id`) | მენეჯმენტი + ჩვენ |
| 0.2 | `analytic.group_analytic_accounting` ჩართვა — Settings → Accounting → Analytics | Admin |
| 0.3 | Branch plan-ის ვერიფიკაცია (id=2 უკვე არსებობს) | Admin |
| 0.4 | Branch ანალიტიკური ანგარიშების შექმნა — B6, B7, HQ ან ფაქტობრივი ბრენჩები | Admin |
| 0.5 | "HQ" ანალიტიკური ანგარიში fallback-ისთვის (full leave employees, internal time-off) | Admin |
| 0.6 | Backfill SQL: ყველა აქტიური asset-ი → default analytic_distribution=HQ | DBA / Developer |
| 0.7 | Backfill: ყველა აქტიური salary rule-ი → analytic_distribution default-ი | Developer |
| 0.8 | Backfill: ყველა ღია SO line-ი → analytic_distribution-ი (თუ billable პროექტი არსებობს) | Developer |

### Phase 1 — Soft Rollout (Warning-only)

| ნაბიჯი | მოქმედება |
|---|---|
| 1.1 | Branch plan `default_applicability = 'optional'` (default-ად) |
| 1.2 | **არანაირი mandatory rule ჯერ-ჯერობით** — ყველაფერი optional |
| 1.3 | Salary rule-ებზე ცალცალკე default `version.analytic_distribution = {hq_id: 100}` |
| 1.4 | Project-ებზე ხელით შევავსოთ `x_plan2_id` |
| 1.5 | მონიტორინგი 2 კვირა: Branch P&L-ში "Unallocated" რამდენი ჩანს? |
| 1.6 | აქცენტი: ემპლოის training timesheet-ში per-line Branch ცვლა |

### Phase 2 — Custom Modules Development

#### Module 1: `hr_timesheet_branch_per_line`

```
custom_addons/hr_timesheet_branch_per_line/
├── __init__.py
├── __manifest__.py
├── models/
│   ├── __init__.py
│   └── hr_timesheet.py        ← default_get override (favorite branch)
├── views/
│   └── hr_timesheet_views.xml ← list view inherit (Branch column visible)
└── data/
    └── analytic_applicability.xml ← Branch mandatory for timesheet domain
```

**ფუნქციონალი:**
- `_get_favorite_branch_id()` — ემპლოის ბოლო 10 timesheet-დან mode
- `default_get` override — ახალი timesheet ხაზზე default Branch ემპლოის ჩვევით
- `@api.constrains` — per-line Branch აუცილებელი (custom — applicability მხოლოდ პროექტის ვალდებულობას ამოწმებს)
- View inherit — `x_plan2_id` ხილვადი ცხრილში, `optional='show'`

#### Module 2: `hr_payroll_branch_breakdown`

```
custom_addons/hr_payroll_branch_breakdown/
├── __init__.py
├── __manifest__.py
├── models/
│   ├── __init__.py
│   ├── hr_payslip.py            ← _compute_branch_lines, dynamic distribution override
│   ├── hr_payslip_branch_line.py ← One2many for breakdown UI
│   └── hr_payslip_account.py    ← _action_create_account_move override
├── views/
│   └── hr_payslip_views.xml     ← Branch Breakdown tab
└── security/
    └── ir.model.access.csv
```

**ფუნქციონალი:**
- `branch_line_ids` One2many → custom model `hr.payslip.branch.line`
- `_compute_branch_lines` — timesheet-აგრეგირება per-employee per-period
- `_get_dynamic_distribution()` — analytic_distribution timesheet-ებიდან
- `_action_create_account_move` override — context propagation custom analytic-ისთვის
- `_prepare_line_values` override — context-დან წაკითხვა custom analytic-ის

#### Module 3 (optional): `account_payment_branch_propagation`

```
custom_addons/account_payment_branch_propagation/
├── models/account_payment.py  ← analytic propagation invoice → bank line
```

**ფუნქციონალი:** Bank entry-ზე analytic_distribution კოპირება invoice-დან, რათა Cash Flow by Branch შეივსოს.

### Phase 3 — Hard Rollout (Mandatory)

| ნაბიჯი | მოქმედება | ფაზის შუალედი |
|---|---|---|
| 3.1 | `account.analytic.applicability` ჩანაწერი: business_domain='timesheet', applicability='mandatory' | Week 1 |
| 3.2 | მონიტორინგი 1 კვირა — timesheet-ის ფეილ ფონი | Week 2 |
| 3.3 | applicability for 'bill' = mandatory | Week 3 |
| 3.4 | applicability for 'invoice' = mandatory ან optional (decision) | Week 4 |
| 3.5 | applicability for 'expense' = mandatory ცალკე ემპლოის training-ის შემდეგ | Week 5 |
| 3.6 | NEVER mandatory for 'general' (manual JE) — accountant flexibility | — |

### Phase 4 — Reports Finalization

| ნაბიჯი | მოქმედება |
|---|---|
| 4.1 | Accounting → Reports → Profit & Loss → "Analytic Group By" → Branch plan |
| 4.2 | Save as default custom view |
| 4.3 | Trial Balance + General Ledger — same filter ჩართვა for audit |
| 4.4 | Optional: custom dashboard widget per CFO use case |

---

## 6. Configuration Reference

### 6.1 `account.analytic.applicability` — სად ცხოვრობს UI-ში

**არ არის ცალკე მენიუ.** Embedded One2many `account.analytic.plan`-ის ფორმაში:

```
Accounting → Configuration → Analytic Accounting → Analytic Plans
  └── ხსნი plan-ს (Branch)
       └── Notebook → tab "Applicability"
            └── ცხრილი: business_domain | company | applicability
```

წყარო: [analytic_plan_views.xml:36-46](../addons/analytic/views/analytic_plan_views.xml#L36)

### 6.2 Available `business_domain` values

| Domain | Module | Context |
|---|---|---|
| `general` (Miscellaneous) | analytic (default) | Misc journal entries |
| `invoice` (Invoice) | account | Customer invoices |
| `bill` (Vendor Bill) | account | Vendor bills |
| `timesheet` (Timesheet) | hr_timesheet | Timesheet creation |
| `expense` (Expense) | hr_expense | Expense reports |
| `purchase_order` | purchase | PO lines |
| `sale_order` | sale | SO lines |
| `manufacturing_order` | mrp_account | MO work orders |

### 6.3 `default_applicability` vs `applicability_ids`

| ველი | სად | Effect |
|---|---|---|
| `default_applicability` | plan-ის ფორმის ზედა ნაწილი | Plan-ის ნაგულისხმევი ყველა business domain-ზე |
| `applicability_ids` (ცხრილი) | "Applicability" tab | Per-business-domain override |

რეკომენდაცია Atlas-ისთვის:

```
Branch plan
├── default_applicability: optional    ← ყველგან ხილვადი default-ად
└── applicability_ids:
    ├── (timesheet, mandatory)         ← timesheet-ის გამორჩევა
    ├── (bill, mandatory)              ← vendor bill-ის გამორჩევა
    └── (general, optional)            ← misc JE დარჩება optional
```

---

## 9. Code Skeleton References

### 9.1 Module 1 — `hr_timesheet_branch_per_line` (v2)

**Configurable plan**, **gated constraint**, **own XML ID**.

```python
# models/res_company.py
from odoo import fields, models


class ResCompany(models.Model):
    _inherit = 'res.company'

    branch_analytic_plan_id = fields.Many2one(
        'account.analytic.plan',
        string="Branch Analytic Plan",
        help="The analytic plan used for branch-level cost allocation.")
    enforce_branch_per_line = fields.Boolean(
        string="Enforce Branch on Every Timesheet Line",
        default=False,
        help="When enabled, every timesheet line must have a branch assigned.")
```

```python
# models/hr_timesheet.py
from odoo import api, models
from odoo.exceptions import ValidationError
from statistics import mode


class AccountAnalyticLine(models.Model):
    _inherit = 'account.analytic.line'

    @api.model
    def _get_branch_column(self):
        plan = self.env.company.branch_analytic_plan_id
        return plan._column_name() if plan else None

    @api.model
    def _get_favorite_branch_id(self, employee_id=False):
        col = self._get_branch_column()
        if not col:
            return False
        employee_id = employee_id or self.env.user.employee_id.id
        if not employee_id:
            return False
        last = self.search(
            [('employee_id', '=', employee_id),
             (col, '!=', False),
             ('project_id', '!=', False)],
            order='date desc, id desc', limit=10,
        )
        return last and mode(last.mapped(f'{col}.id')) or False

    @api.model
    def default_get(self, fields_list):
        result = super().default_get(fields_list)
        col = self._get_branch_column()
        if col and col in fields_list and self.env.context.get('is_timesheet'):
            if not result.get(col):
                emp = result.get('employee_id') or self.env.context.get('default_employee_id')
                fav = self._get_favorite_branch_id(emp)
                if fav:
                    result[col] = fav
        return result

    @api.constrains(lambda self: [self._get_branch_column() or 'project_id', 'project_id'])
    def _check_branch_required(self):
        # Phase 1 soft / Phase 3 hard — gated by company setting
        if not self.env.company.enforce_branch_per_line:
            return
        col = self._get_branch_column()
        if not col:
            return
        for line in self.filtered('project_id'):
            if not line[col]:
                raise ValidationError(self.env._(
                    "Branch is required on every timesheet line."
                ))
```

```xml
<!-- data/branch_analytic_plan_data.xml -->
<odoo noupdate="1">
    <!-- ჩვენი XML ID, ჩვენი ვფლობთ -->
    <record id="branch_analytic_plan" model="account.analytic.plan">
        <field name="name">Branch</field>
        <field name="default_applicability">optional</field>
    </record>
</odoo>
```

```xml
<!-- views/hr_timesheet_views.xml -->
<!-- ❗ Branch column-ის name dynamic, ამიტომ ხელით კონკრეტული plan-ის სვეტს ვუთითებთ.
     თუ მერე plan-ი იცვლება, view ცალკე უნდა მოარგო — ან ცალკე XML ფაილი per plan id. -->
<record id="view_hr_timesheet_line_tree_inherit" model="ir.ui.view">
    <field name="model">account.analytic.line</field>
    <field name="inherit_id" ref="hr_timesheet.hr_timesheet_line_tree"/>
    <field name="arch" type="xml">
        <xpath expr="//field[@name='project_id']" position="after">
            <!-- Use auto_account_id with context — works regardless of plan ID -->
            <field name="auto_account_id" string="Branch"
                   context="{'analytic_plan_id': company.branch_analytic_plan_id.id}"
                   optional="show"/>
        </xpath>
    </field>
</record>
```

```xml
<!-- data/analytic_applicability.xml -->
<!-- Phase 3-ში გააქტიურდება — ჯერ commented out -->
<odoo noupdate="1">
    <!--
    <record id="branch_mandatory_for_timesheet" model="account.analytic.applicability">
        <field name="analytic_plan_id" ref="branch_analytic_plan"/>
        <field name="business_domain">timesheet</field>
        <field name="applicability">mandatory</field>
    </record>
    -->
</odoo>
```

### 9.2 Module 2 — `hr_payroll_branch_breakdown` (v2)

**Non-stored breakdown**, **per-line distribution lookup via line.slip_id**, **batch-aware**, **home_branch fallback**.

```python
# models/hr_version.py
from odoo import fields, models


class HrVersion(models.Model):
    _inherit = 'hr.version'

    home_branch_account_id = fields.Many2one(
        'account.analytic.account',
        string="Home Branch",
        help="Default branch for this employee when no timesheet data is available "
             "during the payroll period.")
```

```python
# models/hr_payslip_branch_line.py — non-stored display only
from odoo import fields, models


class HrPayslipBranchLine(models.Model):
    _name = 'hr.payslip.branch.line'
    _description = 'Salary Cost per Branch (Display)'
    _order = 'hours desc'
    _auto = False  # ❗ in-memory; alternatively store=False on the One2many
    
    # ... same fields, but One2many on payslip is store=False
```

**Alternative (preferred)**: `transient` model OR `store=False` computed One2many.

```python
# models/hr_payslip.py — v3.1 hardened (credit note Mirror, null checks, zero-guards)
from odoo import api, fields, models


class HrPayslip(models.Model):
    _inherit = 'hr.payslip'

    # store=False — display only. Recompute happens on view open.
    branch_line_ids = fields.One2many(
        'hr.payslip.branch.line', 'payslip_id', string="Branch Breakdown",
        compute='_compute_branch_lines', store=False)

    def _get_branch_plan_column(self):
        """Helper: returns the column name for the configured Branch plan, 
        or None if not configured."""
        plan = self.company_id.branch_analytic_plan_id
        return plan._column_name() if plan else None

    def _read_timesheet_branches(self):
        """Aggregate timesheet hours per Branch analytic account for this slip.
        
        Returns list of tuples [(branch_record, hours), ...] for the slip's period.
        Filters: own employee, period range, project set, branch set, branch active,
                 company in payslip's company hierarchy.
        Excludes archived analytic accounts (EC6).
        Includes negative entries (corrections) — guarded for total_hours <= 0.
        """
        self.ensure_one()
        col = self._get_branch_plan_column()
        if not col:
            return []
        
        # Multi-company filter — payslip company + all parents (EC4, EC7)
        company_ids = self.company_id.parent_ids.ids if self.company_id else []
        
        return self.env['account.analytic.line']._read_group(
            domain=[
                ('employee_id', '=', self.employee_id.id),
                ('date', '>=', self.date_from),
                ('date', '<=', self.date_to),
                ('project_id', '!=', False),
                (col, '!=', False),
                (f'{col}.active', '=', True),  # exclude archived (EC6)
                ('company_id', 'in', company_ids),
            ],
            groupby=[col],
            aggregates=['unit_amount:sum'],
        )

    def _compute_branch_lines(self):
        """Display-only breakdown table for the payslip form."""
        for slip in self:
            # Reset using ORM Command for clarity
            slip.branch_line_ids = [(5, 0, 0)]
            
            # EC8/EC9: skip if state is bad or compute had errors
            if slip.state in ('cancel', 'paid'):
                continue
            if not slip._get_branch_plan_column():
                continue
            if not slip.employee_id or not slip.date_from or not slip.date_to:
                continue  # incomplete payslip
            
            timesheets = slip._read_timesheet_branches()
            total_hours = sum(h for _, h in timesheets) or 0.0
            
            cost_base = sum(slip.line_ids.filtered(
                lambda l: l.category_id and l.category_id.code == 'GROSS'
            ).mapped('total'))
            
            # EC5/EC13: zero/negative hours guard
            if total_hours <= 0 or cost_base <= 0:
                continue
            
            slip.branch_line_ids = [(0, 0, {
                'branch_account_id': branch.id,
                'hours': hours,
                'percentage': round(hours / total_hours * 100, 2),
                'cost_amount': round(cost_base * hours / total_hours, 2),
            }) for branch, hours in timesheets]

    def _get_dynamic_distribution(self):
        """Compute analytic_distribution dict for journal entry posting.
        
        Returns: {str(account_id): percentage, ...} — empty dict if no data.
        
        Resolution order:
        1. Credit note → mirror origin payslip's distribution (§0.17)
        2. Timesheets exist → compute proportional distribution
        3. version.home_branch_account_id → 100% to home branch
        4. version.analytic_distribution (legacy fallback) → use as-is
        5. Empty {} → posts as Unallocated, log exception
        """
        self.ensure_one()
        
        # EC1: null check version_id
        if not self.version_id:
            return {}
        
        # §0.17: Credit Note Mirror — preserve original distribution for net-zero
        if self.credit_note and self.origin_payslip_id:
            mirror = self._mirror_origin_distribution()
            if mirror:
                return mirror
            # Fall through to fresh compute if origin lookup fails
        
        plan = self.company_id.branch_analytic_plan_id
        if not plan:
            return self.version_id.analytic_distribution or {}
        
        # Fresh compute from timesheets
        timesheets = self._read_timesheet_branches()
        total_hours = sum(h for _, h in timesheets) or 0.0
        
        # EC5/EC13: zero or negative total — fallback chain
        if total_hours <= 0:
            return self._fallback_distribution()
        
        return {
            str(branch.id): round(hours / total_hours * 100, 2)
            for branch, hours in timesheets
            if hours > 0  # only include positive contributions
        }

    def _mirror_origin_distribution(self):
        """Credit notes should mirror the original payslip's distribution
        to ensure P&L by Branch nets to zero correctly."""
        self.ensure_one()
        if not (self.credit_note and self.origin_payslip_id):
            return None
        origin_move = self.origin_payslip_id.move_id
        if not origin_move:
            return None
        # Find first expense line with analytic_distribution
        origin_line = origin_move.line_ids.filtered(
            lambda l: l.account_id.account_type
                      and l.account_id.account_type.startswith('expense')
                      and l.analytic_distribution
        )
        return origin_line[:1].analytic_distribution or None

    def _fallback_distribution(self):
        """When timesheets have no data, fall back to:
        1. version.home_branch_account_id — 100% to home branch
        2. version.analytic_distribution — legacy fallback
        3. Empty dict + exception log
        """
        self.ensure_one()
        # EC14: home_branch fallback
        home = self.version_id.home_branch_account_id
        if home and home.active:
            return {str(home.id): 100.0}
        # Legacy fallback
        if self.version_id.analytic_distribution:
            return self.version_id.analytic_distribution
        # No allocation possible — log for HR review
        self._log_unallocated_payslip()
        return {}

    def _log_unallocated_payslip(self):
        """Log payslip without timesheet/home_branch — for HR exception report."""
        self.message_post(body=self.env._(
            "Branch breakdown unavailable: no timesheet data and no home branch "
            "configured on contract. Salary expense will appear as 'Unallocated' "
            "in P&L by Branch reports."
        ))
```

```python
# models/hr_payslip_account.py — v3 Option C: POST-CREATE DIRECT WRITE
# (preferred over _prepare_line_values override — protects from
#  account.analytic.distribution.model auto-overwrite)
from odoo import models


class HrPayslipAccount(models.Model):
    _inherit = 'hr.payslip'

    def _action_create_account_move(self):
        """Override to apply dynamic per-employee analytic_distribution
        AFTER move creation, bypassing _compute_analytic_distribution.
        
        Why post-create direct write:
        - _prepare_line_values override gets re-overwritten by 
          _compute_analytic_distribution which queries 
          account.analytic.distribution.model (see §0.14)
        - Direct write triggers _inverse_analytic_distribution which 
          unlinks/recreates analytic.lines correctly (see §0.13)
        - Idempotent under repeated calls
        """
        # Refresh branch breakdown once before move creation
        self.invalidate_recordset(['branch_line_ids'])
        
        res = super()._action_create_account_move()
        
        # Now overwrite analytic_distribution on expense lines per slip
        for slip in self.filtered('move_id'):
            distribution = slip._get_dynamic_distribution()
            if not distribution:
                continue
            
            # Find which move lines belong to this slip via salary rule
            # (when batch_payroll_move_lines=True, multiple slips share a move)
            slip_expense_lines = slip.move_id.line_ids.filtered(
                lambda l: l.account_id.account_type 
                          and l.account_id.account_type.startswith('expense')
            )
            
            # CRITICAL: when batching, we must distinguish per-slip lines.
            # If batch is enabled and merging happened, expense line 
            # represents COMBINED amounts across slips — direct overwrite
            # with one slip's distribution is WRONG.
            #
            # Architectural decision: disable batch_payroll_move_lines 
            # (one move per slip) for clean per-slip distribution.
            if slip.company_id.batch_payroll_move_lines:
                # Future work: implement analytic-aware merge or 
                # per-slip line filtering by partner_id/name
                slip.message_post(body=self.env._(
                    "Warning: batch_payroll_move_lines is enabled — branch "
                    "distribution may be inaccurate. Disable batching for "
                    "per-employee branch breakdown to work correctly."
                ))
                continue
            
            for line in slip_expense_lines:
                # Direct write triggers _inverse_analytic_distribution 
                # which unlinks old analytic.lines and recreates with 
                # new distribution — atomic and safe
                line.analytic_distribution = distribution
        
        return res
```

**Architectural Recommendation v3:**

| აპპროუჩი | მუშაობს? | რეკომენდაცია |
|---|---|---|
| **`_prepare_line_values` override** | ❌ — `_compute_analytic_distribution` overwrites it (§0.14) | Avoid |
| **Context flag to skip distribution.model** | ✅ მუშაობს | OK if accountant team has rules |
| **Post-create direct write (Option C)** | ✅ Cleanest | **Recommended** |
| **`batch_payroll_move_lines = True` + custom merge** | ⚠️ Complex | Future enhancement |

**Setup checklist:**
1. `company.batch_payroll_move_lines = False` — one move per slip, clean per-employee distribution
2. Leave `version.analytic_distribution = {}` (empty) — fallback via `home_branch_account_id`
3. Leave `salary_rule.analytic_distribution = {}` (empty)
4. **Don't manually set `distribution_analytic_account_ids`** — it's computed (§0.12)
5. Module 2 deploys post-create override

**Why merge naturally OK with empty rule/version analytic:**

[hr_payslip.py:260-269](../enterprise/hr_payroll_account/models/hr_payslip.py#L260) merge condition: when both rule and version `analytic_distribution` are empty, **first OR branch ((not...))-ი არ მუშაობს** რადგან move line-ის `analytic_distribution`-ი ცარიელი არ არის (ჩვენ post-create-ად ვადგენთ). ხოლო შემდეგი OR-ები ცდილობენ check `acc_id in distribution_analytic_account_ids` — ცარიელი list-ი. **შედეგი: merge always False → distinct lines per slip.**

ანუ **Option B (custom merge override) საჭირო არ არის** თუ რეცეპტი 1-4 დაცულია.

```xml
<!-- views/hr_payslip_views.xml -->
<record id="view_hr_payslip_form_branch_breakdown" model="ir.ui.view">
    <field name="model">hr.payslip</field>
    <field name="inherit_id" ref="hr_payroll.view_hr_payslip_form"/>
    <field name="arch" type="xml">
        <xpath expr="//notebook" position="inside">
            <page string="Branch Breakdown" name="branch_breakdown">
                <field name="branch_line_ids" readonly="1">
                    <list>
                        <field name="branch_account_id"/>
                        <field name="hours" sum="Total Hours"/>
                        <field name="percentage"/>
                        <field name="cost_amount" sum="Total Cost"/>
                    </list>
                </field>
            </page>
        </xpath>
    </field>
</record>
```

---

## 9.4 Module 1 — `__manifest__.py`

```python
# custom_addons/hr_timesheet_branch_per_line/__manifest__.py
{
    'name': "Timesheet Branch Per Line",
    'version': "19.0.1.0.0",
    'category': "Human Resources/Timesheet",
    'summary': "Per-line Branch analytic on timesheets with smart defaults",
    'description': """
Adds per-line Branch analytic capability to timesheets:
- Configurable Branch plan via res.company
- Smart default from employee's recent timesheet history
- Optional mandatory constraint gated by company setting
- Branch column visible in timesheet list view
""",
    'author': "Atlas Group Internal",
    'depends': [
        'hr_timesheet',
        'analytic',
    ],
    'data': [
        'data/branch_analytic_plan_data.xml',
        'data/analytic_applicability.xml',
        'views/res_config_settings_views.xml',
        'views/hr_timesheet_views.xml',
    ],
    'installable': True,
    'application': False,
    'license': 'LGPL-3',
}
```

## 9.5 Module 2 — `__manifest__.py`

```python
# custom_addons/hr_payroll_branch_breakdown/__manifest__.py
{
    'name': "Payroll Branch Breakdown",
    'version': "19.0.1.0.0",
    'category': "Human Resources/Payroll",
    'summary': "Dynamic per-employee branch cost allocation on payslips",
    'description': """
Computes per-employee branch breakdown from timesheets and applies dynamic
analytic_distribution to payslip journal entries:
- Read-only Branch Breakdown panel on payslip form
- Post-create direct write to bypass account.analytic.distribution.model
- Credit Note Mirror — preserve original distribution for net-zero P&L
- home_branch_account_id fallback for employees with no timesheet data
- Configurable Branch plan via company settings
""",
    'author': "Atlas Group Internal",
    'depends': [
        'hr_payroll',
        'hr_payroll_account',
        'hr_timesheet_branch_per_line',  # depends on Module 1 for plan config
    ],
    'data': [
        'security/ir.model.access.csv',
        'views/hr_payslip_views.xml',
        'views/hr_version_views.xml',
    ],
    'post_init_hook': '_create_custom_indexes',
    'installable': True,
    'application': False,
    'license': 'LGPL-3',
}
```

```python
# custom_addons/hr_payroll_branch_breakdown/__init__.py
from . import models
from odoo.tools.sql import SQL


def _create_custom_indexes(env):
    """Performance optimization for 500+ employee scale."""
    env.cr.execute(SQL("""
        CREATE INDEX IF NOT EXISTS account_analytic_line_employee_date_branch_idx
        ON account_analytic_line(employee_id, date, x_plan2_id)
        WHERE project_id IS NOT NULL AND x_plan2_id IS NOT NULL
    """))
```

```csv
<!-- custom_addons/hr_payroll_branch_breakdown/security/ir.model.access.csv -->
id,name,model_id:id,group_id:id,perm_read,perm_write,perm_create,perm_unlink
access_hr_payslip_branch_line_user,hr.payslip.branch.line.user,model_hr_payslip_branch_line,hr_payroll.group_hr_payroll_user,1,0,0,0
access_hr_payslip_branch_line_manager,hr.payslip.branch.line.manager,model_hr_payslip_branch_line,hr_payroll.group_hr_payroll_manager,1,1,1,1
```

---

## 10. Test Scenarios — სრული Acceptance Criteria

### 10.1 Unit Tests — Module 1

#### TC1.1 Configurable Branch Plan
**Setup:** company.branch_analytic_plan_id = Plan(id=2, "Branch")

| Action | Expected |
|---|---|
| Call `_get_branch_plan_column()` | Returns `'x_plan2_id'` |
| Set company.branch_analytic_plan_id = Plan(id=5) | Returns `'x_plan5_id'` (dynamic) |
| Set company.branch_analytic_plan_id = False | Returns None |

#### TC1.2 Favorite Branch Default
**Setup:** Employee L has 10 timesheets: 7× B6, 3× B7

| Action | Expected |
|---|---|
| Create new timesheet for L (UI default_get) | x_plan2_id pre-filled with B6 |
| Mode of last 10: B6 (7 occurrences) | Verified |
| Employee with 0 timesheets | x_plan2_id stays empty |

#### TC1.3 Constraint Gating
**Setup:** company.enforce_branch_per_line = False

| Action | Expected |
|---|---|
| Create timesheet with project but x_plan2_id=False | OK (saves) |
| Set company.enforce_branch_per_line = True | — |
| Create same timesheet | ValidationError raised |

### 10.2 Unit Tests — Module 2

#### TC2.1 Dynamic Distribution from Timesheets
**Setup:** Employee with timesheets in April: B6=60h, B7=30h, HQ=10h. Total 100h.

| Action | Expected |
|---|---|
| Call `_get_dynamic_distribution()` on April payslip | `{B6_id: 60.0, B7_id: 30.0, HQ_id: 10.0}` |
| Edit timesheet: add 50h on B6 | `{B6_id: 73.33, B7_id: 20.0, HQ_id: 6.67}` (recomputed) |

#### TC2.2 Empty Timesheets — Home Branch Fallback
**Setup:** Employee on full leave, 0 timesheets. version.home_branch_account_id = HQ.

| Action | Expected |
|---|---|
| Call `_get_dynamic_distribution()` | `{HQ_id: 100.0}` |
| Set version.home_branch_account_id = False | Logs exception, returns version.analytic_distribution or {} |
| Both empty | Returns {}, logs message_post |

#### TC2.3 Credit Note Mirror
**Setup:** 
- Original payslip A: distribution `{B6: 60, B7: 40}`, posted, move A
- Edit timesheets so fresh compute would yield `{B6: 80, B7: 20}`
- Refund A → credit_note B with origin_payslip_id=A

| Action | Expected |
|---|---|
| Call `B._get_dynamic_distribution()` | `{B6: 60, B7: 40}` (mirror, not 80/20) |
| `B._mirror_origin_distribution()` | Returns same |
| Set origin move_id=False | Falls through to fresh compute |

#### TC2.4 Zero Total Hours Guard
**Setup:** Negative timesheet correction makes total = 0.

| Action | Expected |
|---|---|
| Call `_get_dynamic_distribution()` | Falls to `_fallback_distribution()` |
| Returns home_branch or empty | No DivisionByZero raised |

#### TC2.5 Archived Account Filter
**Setup:** Branch B7 archived, but timesheets exist on B7.

| Action | Expected |
|---|---|
| Call `_read_timesheet_branches()` | B7 timesheets excluded from result |
| Distribution doesn't include archived B7 | Verified |

#### TC2.6 Multi-Company Filter
**Setup:** Atlas Root + sub-company BranchCo X. Employee on Root. Some timesheets on Atlas Root projects, some on BranchCo X projects.

| Action | Expected |
|---|---|
| `_read_timesheet_branches()` filters by `company_id IN parent_ids` | Both companies' timesheets included |
| Sub-only timesheets (X-only employee) | Only X-side included |

### 10.3 Integration Tests

| Test | Setup | Expected |
|---|---|---|
| **TC3.1 Full Phase A** | 1 emp, B6:60h+B7:40h | Form: B6/60%, B7/40%. Post: move with `{B6:60, B7:40}`, analytic.line B6=-600, B7=-400. P&L: B6=-600, B7=-400, Total=-1000 |
| **TC3.2 Credit Note Net-Zero** | After TC3.1 + refund | Credit note B mirrors `{B6:60, B7:40}` (NOT fresh compute). analytic.line B6=+600, B7=+400. **P&L combined: B6=0, B7=0** ✓ |
| **TC3.3 distribution.model Resistance** | Accountant rule: partner=Lasha, acc=60* → `{HQ:100}` | Without Module 2: HQ wins. With Module 2 post-create write: `{B6:60, B7:40}` preserved. Verify analytic.line: B6+B7 exist, HQ does NOT |
| **TC3.4 Concurrent Edit** | Batch in progress, User B edits timesheet mid-batch | Batch sees T0 snapshot (REPEATABLE READ). UI form refresh shows current. Drift acceptable; "Compute Sheet" syncs |
| **TC3.5 Salary Attachment** | Emp + $200 deduction, dist `{B6:60, B7:40}` | Expense lines split per branch. Payable lines NOT split (deductions stay root for legal compliance) |

### 10.4 Risk Mitigation Tests

| Test | Setup | Expected |
|---|---|---|
| **TC4.1 R0 batch=True** | Bad setting, 2 emps with distinct distributions | Lines merge, Module 2 logs warning, distribution NOT applied. Recommend batch=False |
| **TC4.2 R-NEW1 distribution.model** | Active model rule + Module 2 | Module 2's distribution wins (post-create after compute) |
| **TC4.3 R-NEW2 idempotency** | Manual `move._post()` 2x | Duplicate analytic.lines (count=2N). Optional guard in Module 2 |

### 10.5 Performance Tests

| Test | Setup | Acceptable |
|---|---|---|
| **TC5.1 500-emp batch** | 500 emps, 75K timesheets/month | <10 sec with composite index (10x speedup vs no index) |
| **TC5.2 Form open** | 150 timesheets, store=False compute | <300ms with index |

---

## 11. Backfill Scripts — ORM Python

### 11.1 Project x_plan2_id Backfill

```python
# custom_addons/hr_payroll_branch_breakdown/scripts/backfill_projects.py
def backfill_project_branches(env, default_branch_xmlid='your_module.branch_hq'):
    """Set default Branch on projects without one.
    
    Run via:
      env['ir.actions.server'].create({...}).run()
    or as a manual script in odoo shell.
    """
    plan = env.company.branch_analytic_plan_id
    if not plan:
        raise UserError(env._("Branch plan not configured"))
    col = plan._column_name()
    
    default_branch = env.ref(default_branch_xmlid, raise_if_not_found=False)
    if not default_branch:
        raise UserError(env._("Default branch '%s' not found", default_branch_xmlid))
    
    domain = [(col, '=', False), ('active', '=', True)]
    projects = env['project.project'].search(domain)
    
    print(f"Backfilling {len(projects)} projects with default Branch {default_branch.name}")
    projects.write({col: default_branch.id})
    print("Done.")
```

### 11.2 Asset Analytic Distribution Backfill

```python
def backfill_asset_analytics(env, default_branch_xmlid='your_module.branch_hq'):
    """Set default analytic on assets without one.
    
    asset.write triggers draft depreciation moves sync 
    (account_asset.py:530-538) — automatic propagation."""
    default_branch = env.ref(default_branch_xmlid)
    
    assets = env['account.asset'].search([
        '|',
        ('analytic_distribution', '=', False),
        ('analytic_distribution', '=', {}),
        ('state', '!=', 'close'),
    ])
    
    print(f"Backfilling {len(assets)} assets")
    # Use ORM write so draft depreciation moves auto-update
    assets.write({
        'analytic_distribution': {str(default_branch.id): 100}
    })
    print("Draft depreciation moves auto-updated.")
```

### 11.3 hr.version home_branch_account_id Backfill

```python
def backfill_version_home_branches(env, default_branch_xmlid='your_module.branch_hq'):
    """Set home_branch on contracts without one (fallback for empty timesheets)."""
    default_branch = env.ref(default_branch_xmlid)
    
    versions = env['hr.version'].search([
        ('home_branch_account_id', '=', False),
        ('contract_date_end', '=', False),  # active contracts only
    ])
    
    print(f"Backfilling {len(versions)} active contracts")
    versions.write({'home_branch_account_id': default_branch.id})
    print("Done.")
```

### 11.4 Salary Rule analytic_distribution — leave empty

```python
def verify_salary_rules_empty(env):
    """v3.1 design: keep salary_rule.analytic_distribution EMPTY.
    
    Module 2 handles distribution per-payslip via post-create direct write.
    Empty rule analytic ensures _get_existing_lines doesn't merge incorrectly."""
    rules_with_analytic = env['hr.salary.rule'].search([
        ('analytic_distribution', '!=', False),
        ('analytic_distribution', '!=', {}),
    ])
    if rules_with_analytic:
        print(f"WARNING: {len(rules_with_analytic)} salary rules have static analytic_distribution")
        print("Recommendation: clear them. Module 2 handles distribution dynamically.")
        # rules_with_analytic.write({'analytic_distribution': {}})  # uncomment if confirmed
```

### 11.5 Sale Order Backfill (Phase B prep — optional)

```python
def backfill_open_so_branches(env, default_branch_xmlid='your_module.branch_hq'):
    """Phase B prep: tag open SO lines with Branch.
    
    Phase A keeps Branch unavailable on sale_order — this is for Phase B."""
    default_branch = env.ref(default_branch_xmlid)
    
    so_lines = env['sale.order.line'].search([
        ('order_id.state', 'in', ['draft', 'sent', 'sale']),
        '|',
        ('analytic_distribution', '=', False),
        ('analytic_distribution', '=', {}),
    ])
    so_lines.write({
        'analytic_distribution': {str(default_branch.id): 100}
    })
```

---

## 12. Audit & Logging Strategy

### 12.1 What to Log

| Event | Where | Format |
|---|---|---|
| Dynamic distribution computed | payslip.message_post (mail.thread) | "Branch breakdown: B6=60%, B7=30%, HQ=10% from {total} timesheet hours" |
| Home branch fallback used | payslip.message_post | "No timesheet data — using home_branch_account_id ({name})" |
| Unallocated payslip | payslip.message_post + dedicated exception report | "WARNING: Unallocated payslip — no timesheet, no home_branch" |
| Mirror activated (credit note) | payslip.message_post on credit note | "Mirrored distribution from origin payslip #{origin_id}" |
| Backfill script run | ir.logging | "Backfill: {N} records updated, {default_branch} as default" |
| Mandatory enforcement triggered | ValidationError + ir.logging | "Branch required on timesheet line {line_id}" |
| batch_payroll_move_lines warning | payslip.message_post | "WARNING: batch=True may cause distribution loss" |

### 12.2 Exception Report

```python
# Report: Unallocated Payslips
class UnallocatedPayslipReport(models.AbstractModel):
    _name = 'report.hr_payroll_branch_breakdown.unallocated'
    _description = 'Payslips Without Branch Allocation'
    
    @api.model
    def _get_unallocated_payslips(self, date_from, date_to):
        return self.env['hr.payslip'].search([
            ('date_to', '>=', date_from),
            ('date_from', '<=', date_to),
            ('state', 'in', ['validated', 'paid']),
            ('move_id', '!=', False),
            # No timesheets AND no home_branch
            '|',
                ('employee_id.timesheet_ids.x_plan2_id', '=', False),
                ('version_id.home_branch_account_id', '=', False),
        ])
```

### 12.3 Trail Visibility

`hr.payslip.branch.line` should be `mail.thread` if frequent edits expected. For v3.1: read-only, no thread needed.

`account.move.line` already has audit trail via `_check_balanced` and standard Odoo accounting trail.

---

## 13. Rollback Plan

### 13.1 Phase 0 Rollback (Pre-flight)

If Phase 0 backfill caused issues:

```python
# Rollback project x_plan2_id
projects = env['project.project'].search([('x_plan2_id', '=', backfilled_branch_id)])
projects.write({'x_plan2_id': False})

# Rollback asset analytic_distribution
assets_to_revert = env['account.asset'].search([
    ('analytic_distribution', '=', {str(backfilled_branch_id): 100}),
    ('write_date', '>', backfill_date),
])
assets_to_revert.write({'analytic_distribution': False})
# WARNING: this triggers draft depreciation moves to clear analytic too
```

### 13.2 Phase 2 Rollback (Module Uninstall)

```bash
# Uninstall modules — Odoo handles cascade cleanup
./odoo-bin -d database_name -u hr_payroll_branch_breakdown --stop-after-init
# Then uninstall via UI or:
env['ir.module.module'].search([
    ('name', 'in', [
        'hr_payroll_branch_breakdown',
        'hr_timesheet_branch_per_line',
    ])
]).button_immediate_uninstall()
```

**უნინსტალის შემდეგ:**
- ✅ `hr.payslip.branch.line` records deleted (model removed)
- ✅ `branch_line_ids` field removed from hr.payslip
- ✅ View inheritance reverted
- ⚠️ Existing `account.analytic.line` records on Branch plan **remain** (data, not config)
- ⚠️ Posted journal entries with `analytic_distribution` containing Branch IDs **remain**
- 🟢 P&L by Branch reports continue to work for historical data

### 13.3 Phase 3 Rollback (Mandatory → Optional)

```python
# Remove mandatory applicability
applicability = env['account.analytic.applicability'].search([
    ('analytic_plan_id', '=', branch_plan_id),
    ('applicability', '=', 'mandatory'),
])
applicability.write({'applicability': 'optional'})
# Or delete applicability records entirely
```

### 13.4 Emergency Rollback — Complete Reversion

ყველაზე უარესი შემთხვევა: ფიქსირებული მონაცემები საჭიროა გასუფთავება.

```sql
-- WARNING: Run only in true emergency, in a backup-tested environment
BEGIN;
-- 1. Remove all analytic.line records on Branch plan
DELETE FROM account_analytic_line 
WHERE x_plan2_id IS NOT NULL;

-- 2. Clear x_plan2_id from all analytic.line records
UPDATE account_analytic_line SET x_plan2_id = NULL;

-- 3. Clear from move.line analytic_distribution  
UPDATE account_move_line 
SET analytic_distribution = analytic_distribution - 'b6_id_str'  -- per branch
WHERE analytic_distribution ? 'b6_id_str';

-- 4. Verify, then COMMIT or ROLLBACK
SELECT COUNT(*) FROM account_analytic_line WHERE x_plan2_id IS NOT NULL;  -- should be 0
COMMIT;
-- or: ROLLBACK;
```

**Pre-conditions for emergency rollback:**
- Verified database backup exists
- Communication to all users about downtime
- Accounting team approves data deletion
- Lock dates considered

---

## 14. Glossary

| Term | Meaning |
|---|---|
| **Branch (Atlas context)** | Internal cost center (Batumi office, Kutaisi warehouse, HQ) — NOT a separate legal entity |
| **Odoo Branch** | `res.company.parent_id` hierarchy — sub-company sharing CoA. Different from Atlas Branch. |
| **Branch Plan** | `account.analytic.plan` named "Branch", id=2 in current DB. Configurable via `company.branch_analytic_plan_id`. |
| **Branch Account** | `account.analytic.account` on Branch plan — e.g. B6, B7, HQ. |
| **Plan Column** | `_strict_column_name()` — `account_id` for Project plan, `x_plan{id}_id` for others. Runtime-derived. |
| **`auto_account_id`** | UI helper field, NOT a real DB column. Context-dependent, requires `analytic_plan_id` in context. |
| **`analytic_distribution`** | JSON dict on move.line: `{"acc_id1,acc_id2": pct}`. Stored field. |
| **`distribution_analytic_account_ids`** | Computed Many2many extracted from analytic_distribution keys. NOT manually set. |
| **Dynamic Distribution** | Per-payslip distribution computed from timesheet aggregation (Module 2). |
| **Home Branch** | `version.home_branch_account_id` — fallback for empty timesheets (custom field). |
| **Credit Note Mirror** | Pattern: credit note's distribution = original's distribution, ensuring P&L net-zero per branch. |
| **Phase A** | OPEX-by-Branch only (salary, vendor bills, expenses). Current scope. |
| **Phase B** | Revenue-by-Branch + COGS-by-Branch. Future initiative — sale_timesheet rework, stock.move analytic. |
| **applicability='mandatory'** | Plan must have 100% distribution for the business_domain. Blocks if `validate_analytic=True` context set. |
| **`validate_analytic` context** | Boolean flag that gates `_validate_distribution` enforcement. Not always set automatically. |
| **`_create_analytic_lines`** | Auto-creates `account.analytic.line` records from move line's `analytic_distribution` on `_post()`. |
| **`_inverse_analytic_distribution`** | Direct write trigger that unlinks old analytic.lines and recreates with new distribution. |
| **`account.analytic.distribution.model`** | Auto-distribution rule engine. Configurable via Settings → Accounting. **Risk: can overwrite our explicit distribution.** |
| **batch_payroll_move_lines** | Company setting. True = one move per journal/month (merges); False = one move per slip. v3.1 requires False. |
| **Storno** | Italian/German accounting style — reverses debit/credit instead of negating. Triggered by company.account_storno + credit_note. |

---

## 15. Decision Log

| # | Decision | Date | Rationale | Status |
|---|---|---|---|---|
| D1 | Use only analytic plan, NO Odoo branches | 2026-04-28 | Single legal entity, simpler architecture | ✅ Confirmed |
| D2 | Phase A scope = OPEX only | 2026-04-28 | Revenue/COGS requires Phase B (sale_timesheet, stock.move) | ✅ Confirmed |
| D3 | `batch_payroll_move_lines = False` | 2026-04-28 | Per-slip distribution requires no merge | ✅ Confirmed |
| D4 | Post-create direct write (Option C) | 2026-04-28 | Protects from `_compute_analytic_distribution` overwrite | ✅ Confirmed |
| D5 | `branch_line_ids` store=False | 2026-04-28 | External data dependency cannot use @api.depends | ✅ Confirmed |
| D6 | Configurable plan via `branch_analytic_plan_id` | 2026-04-28 | No hardcoded plan_id=2 | ✅ Confirmed |
| D7 | Credit note Mirror — preserve origin distribution | 2026-04-28 | Net-zero per branch in P&L | ✅ Confirmed |
| D8 | Hide Branch on Sale Order / Invoice (Phase A) | 2026-04-28 | Salary independent of sale; reduce UI noise | ✅ Confirmed |
| D9 | Vendor bill applicability = optional (Phase A) | 2026-04-28 | Avoid blocking accountants; mandatory in Phase 3 staged | ⏳ Pending |
| D10 | `home_branch_account_id` instead of HQ default | 2026-04-28 | Per-employee fallback more accurate | ✅ Confirmed |
| D11 | ORM backfill for assets (not raw SQL) | 2026-04-28 | `asset.write` propagates to draft depreciation moves | ✅ Confirmed |
| D12 | Concurrency: skip snapshot pattern for v3.1 | 2026-04-28 | REPEATABLE READ + post-create write enough; revisit if issues | ⏳ Monitor |
| D13 | Salary attachments: NOT split per branch | 2026-04-28 | Legal compliance — deductions stay at root | ✅ Confirmed |
| D14 | Time off via `project_timesheet_holidays`, not `hr_payroll_holidays` | 2026-04-28 | Correct module identification | ✅ Confirmed |

---

## 16. Migration Checklist

```
PHASE 0 — Pre-flight
☐ Architecture decision: branches vs only analytic plan
☐ Enable analytic.group_analytic_accounting in settings
☐ Create Branch analytic accounts (B6, B7, HQ, ...)
☐ Backfill assets with default analytic_distribution
☐ Backfill salary rules with default analytic_distribution
☐ Backfill versions with default analytic_distribution = {HQ: 100}
☐ Backfill open SO lines with analytic_distribution
☐ Manual project tagging (x_plan2_id per project)

PHASE 1 — Soft rollout (2 weeks)
☐ Deploy to staging
☐ Branch plan default_applicability = optional
☐ NO mandatory rules yet
☐ Monitor: Unallocated count in P&L by Branch
☐ Train employees on per-line Branch override

PHASE 2 — Custom modules
☐ Develop hr_timesheet_branch_per_line module
☐ Develop hr_payroll_branch_breakdown module
☐ Develop account_payment_branch_propagation module (optional)
☐ Unit tests covering all edge cases
☐ User acceptance testing

PHASE 3 — Hard rollout (5 weeks staged)
☐ Week 1: timesheet mandatory
☐ Week 2: monitor failures
☐ Week 3: bill mandatory
☐ Week 4: invoice mandatory (if approved)
☐ Week 5: expense mandatory (with training)

PHASE 4 — Reports
☐ Custom P&L view with Analytic Group By: Branch
☐ Custom Trial Balance view
☐ Custom General Ledger view
☐ CFO dashboard (optional)
☐ Documentation for accountants
```

---

## 17. Related Docs

- [`INDEX.md`](INDEX.md)
- [`hr_payroll.md`](hr_payroll.md) — Payroll structure, salary rules, payslip computation
- [`accounting_multicompany_branches.md`](accounting_multicompany_branches.md) — Multi-company vs branches vs analytic comparison
- [`accounting_reports.md`](accounting_reports.md) — Report engines, analytic_groupby mechanics
- [`analytic_budget.md`](analytic_budget.md) — Analytic budget scope (separate concern from this doc)

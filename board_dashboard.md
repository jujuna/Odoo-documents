# Dashboards (board + spreadsheet_dashboard)

> **Modules:** `board` + `spreadsheet_dashboard` | **Paths:** [`addons/board/`](../addons/board/) and [`addons/spreadsheet_dashboard/`](../addons/spreadsheet_dashboard/)
> **Odoo Apps category:** Productivity / Dashboard

## What It Does

Odoo 19 has **two dashboard systems** under the same `/Dashboards` menu. The **legacy board** (`board.board`) lets each user build a personal dashboard by pinning existing list/graph/pivot views as drag-and-drop blocks. The **spreadsheet dashboard** (`spreadsheet.dashboard`) provides company-wide, spreadsheet-powered dashboards with charts, pivot tables, and KPIs — typically pre-built by module installers (CRM, Accounting, etc.) and editable in Enterprise edition. Both systems serve different use cases: personal quick-view vs. shared analytical dashboards.

---

## When to Use This Module

Dashboards are for anyone who needs at-a-glance visibility into business data without navigating multiple menus. The `board` module is always installed (it comes with Odoo base), so the question is not "should I install it" but "which dashboard system fits my need."

### Best For
- **Quick personal monitoring** — a sales rep who wants their open quotations, pipeline graph, and overdue tasks on one screen (legacy board)
- **Company-wide KPI reporting** — a CFO who wants all managers to see the same revenue/expense charts updated in real time (spreadsheet dashboard)
- **Onboarding new users** — pre-built dashboards from CRM, Accounting, etc. give immediate value before users learn navigation
- **Executive summaries** — combining pivot tables, charts, and KPI cards in one view without switching between menus

### Not For
- **Detailed data entry or editing** — dashboards are read-only; use the actual module views for data manipulation
- **Real-time operational alerts** — use Discuss channels, automated actions, or email alerts instead
- **Complex custom reports with parameters** — use the Accounting Reports engine or custom report wizards

---

## Real-World Use Cases

### Use Case 1: Sales Manager Daily Overview (Legacy Board)
**Situation:** A sales manager starts each day wanting to see: how many quotations are open, which orders were confirmed yesterday, and a pipeline graph by stage.
**In Odoo:**
1. Go to Sales → Orders → Quotations, apply filter "My Quotations" + "Creation Date: Last 7 Days"
2. Click the gear/cog menu → "Add to My Dashboard" → name it "My Open Quotations"
3. Go to Sales → Orders → Orders, apply filter "Last 7 Days", group by "Salesperson", switch to graph view
4. Cog menu → "Add to My Dashboard" → name it "Recent Orders by Salesperson"
5. Go to CRM → Pipeline, switch to pivot view, group by Stage
6. Cog menu → "Add to My Dashboard" → name it "Pipeline by Stage"
7. Open Dashboards → My Dashboard — all three blocks are there, rearrange with drag-and-drop, pick "2-1" layout

**Result:** Every morning, one click to Dashboards → My Dashboard shows a personalized snapshot. Filters are frozen at pin time, so it always shows "last 7 days" relative to when it was pinned — the data refreshes but the filter criteria stay the same.

### Use Case 2: CFO Shared Financial Dashboard (Spreadsheet Dashboard, Enterprise)
**Situation:** A CFO wants all department heads to see the same monthly revenue, expenses by category, and cash flow trend — without each person building their own view.
**In Odoo:**
1. Install `spreadsheet_dashboard_account_accountant` — this creates a pre-built Accounting dashboard
2. Go to Dashboards → Accounting — the dashboard shows revenue, expense, and P&L charts
3. Click "Edit" to customize: add a pivot table with `=ODOO.PIVOT()` pulling from `account.move.line`, add KPI cards
4. Click "Publish" to make it visible to all users with accounting access
5. Set `group_ids` to restrict to `account.group_account_manager` if needed

**Result:** Every department head sees the same live data. No one can accidentally break another's view. The CFO can update the dashboard layout and everyone sees the change.

### Use Case 3: E-commerce Team Performance Tracking (Legacy Board)
**Situation:** An e-commerce manager wants to track website sale orders, delivery status, and customer invoices in one place.
**In Odoo:**
1. Go to Sales → Orders, filter by "Sales Channel = Website", switch to graph view grouped by week
2. Cog menu → "Add to My Dashboard" → "Website Sales Trend"
3. Go to Inventory → Deliveries, filter "Ready" + "Late", list view
4. Cog menu → "Add to My Dashboard" → "Late Deliveries"
5. Go to Accounting → Invoices, filter "Overdue", pivot view grouped by partner
6. Cog menu → "Add to My Dashboard" → "Overdue Invoices"

**Result:** Cross-module visibility in one screen. The manager spots bottlenecks (late deliveries causing overdue invoices) without jumping between Sales, Inventory, and Accounting menus.

### Use Case 4: Sharing a Dashboard with External Stakeholders (Enterprise)
**Situation:** A project manager needs to share a KPI dashboard with a client who does not have an Odoo account.
**In Odoo:**
1. Open the spreadsheet dashboard
2. Click "Share" → a public URL is generated with an access token
3. Optionally attach an Excel export for offline viewing
4. Send the URL to the client

**Result:** The client sees a read-only snapshot at `/dashboard/share/<id>/<token>`. No login required. The data reflects the state at share time. The share can be revoked by deleting the share record.

### Use Case 5: Pre-Built Dashboard via Custom Module (Developer)
**Situation:** A developer building a custom module wants to ship a default dashboard that appears when the module is installed, showing sample data until real records exist.
**In Odoo:**
1. Create a spreadsheet JSON file with charts and pivot tables
2. Define `spreadsheet.dashboard.group` and `spreadsheet.dashboard` records in XML data
3. Set `sample_dashboard_file_path` to the JSON file and `main_data_model_ids` to the relevant models
4. Install the module — users see sample charts immediately, which auto-replace with real data once records are created

**Result:** New users get immediate visual value instead of empty screens. The developer controls the default view for all users.

---

## How-To Scenarios

### How to pin a filtered view to My Dashboard
1. Navigate to any list, graph, or pivot view (e.g., Sales → Orders → Quotations)
2. Apply the filters, group-by, and sorting you want to keep
3. Click the gear/cog icon in the control panel
4. Select "Add to My Dashboard"
5. Enter a descriptive name and confirm
6. Go to Dashboards → My Dashboard to see it

**Why this works:** The [`add_to_dashboard()`](../addons/board/controllers/main.py#L12) controller captures the current action ID, view_mode, domain (your filters), and context (your group_by and sort) as XML attributes on an `<action>` element, then stores it in `ir.ui.view.custom` for your user.

### How to rearrange dashboard blocks
1. Open Dashboards → My Dashboard
2. Use the layout dropdown (top of dashboard) to choose column arrangement: single column, two equal, two-thirds/one-third, etc.
3. Drag any block by its title bar to move it to a different column or position
4. Changes save automatically

**Why this works:** [`BoardController`](../addons/board/static/src/board_controller.js) uses `useSortable()` with `connectGroups: true` for cross-column drag-and-drop. Each move triggers `saveBoard()` which serializes the layout back to XML and POSTs to `/web/view/edit_custom`.

### How to remove a block from My Dashboard
1. Open Dashboards → My Dashboard
2. Click the "X" (close) button on the block you want to remove
3. The block disappears and the layout saves automatically

**Why this works:** Removing a block deletes the `<action>` element from the user's `ir.ui.view.custom` arch XML and saves the updated version.

### How to fold/collapse a dashboard block
1. On My Dashboard, click the fold/minimize icon on any block's title bar
2. The block collapses to just its title, saving screen space
3. Click again to expand

**Why this works:** The `fold` attribute on each `<action>` element toggles between `"0"` (expanded) and `"1"` (collapsed). This is persisted in the user's custom view XML.

### How to create a shared spreadsheet dashboard (Enterprise)
1. Go to Dashboards menu → click "New" (or create from Documents → Spreadsheet)
2. Use the spreadsheet editor: Insert → Pivot to add data from any Odoo model
3. Add charts by selecting data ranges and clicking Insert → Chart
4. Use formulas like `=ODOO.PIVOT("sale.order", "amount_total", "stage_id", "won")` for dynamic KPIs
5. Save, assign to a Dashboard Group (this determines which menu section it appears under)
6. Toggle "Published" to make it visible to other users
7. Set security groups via `group_ids` to control who sees it

**Why this works:** The dashboard data is stored as binary JSON in [`spreadsheet.dashboard`](../addons/spreadsheet_dashboard/models/spreadsheet_dashboard.py) via `spreadsheet.mixin`. The group assignment links it to a `spreadsheet.dashboard.group` which maps to a menu section under Dashboards.

### How to share a dashboard publicly (Enterprise)
1. Open the spreadsheet dashboard you want to share
2. Click the "Share" button
3. A public URL is generated (format: `/dashboard/share/<id>/<token>`)
4. Optionally check "Include Excel export" for offline access
5. Copy and send the URL — no Odoo login required to view

**Why this works:** [`action_get_share_url()`](../addons/spreadsheet_dashboard/models/spreadsheet_dashboard_share.py#L26) creates a `spreadsheet.dashboard.share` record with a UUID access token. The [`_check_dashboard_access()`](../addons/spreadsheet_dashboard/models/spreadsheet_dashboard_share.py#L40) method validates the token before serving data.

---

## Dependencies

### Requires (must be installed)

| Module | Why |
|---|---|
| `spreadsheet_dashboard` | `board` depends on it; provides the `/Dashboards` root menu and spreadsheet dashboard engine |
| `spreadsheet` | `spreadsheet_dashboard` depends on it; provides `spreadsheet.mixin` for binary data storage |

### Optional Integrations (Enterprise)

| Module | What it enables |
|---|---|
| `spreadsheet_dashboard_edition` | Edit mode, publish/unpublish toggle, and share with Excel export for spreadsheet dashboards |
| `spreadsheet_dashboard_crm` | Pre-built CRM pipeline dashboard |
| `spreadsheet_dashboard_account_accountant` | Pre-built accounting dashboard |
| `spreadsheet_dashboard_stock` | Pre-built inventory dashboard |
| `spreadsheet_dashboard_hr_contract` | Pre-built HR contracts dashboard |
| `spreadsheet_dashboard_hr_payroll` | Pre-built payroll dashboard |
| `spreadsheet_dashboard_helpdesk` | Pre-built helpdesk dashboard |
| `spreadsheet_dashboard_mrp_account` | Pre-built manufacturing accounting dashboard |
| `spreadsheet_dashboard_purchase_stock` | Pre-built purchase/stock dashboard |
| `spreadsheet_dashboard_sale_subscription` | Pre-built subscription dashboard |
| `spreadsheet_dashboard_sale_renting` | Pre-built rental dashboard |
| `spreadsheet_dashboard_hr_referral` | Pre-built referral dashboard |
| `spreadsheet_dashboard_marketing_automation` | Pre-built marketing automation dashboard |
| `spreadsheet_dashboard_documents` | Pre-built documents dashboard |

---

## Architecture Overview

```
Two Separate Systems Under One Menu
====================================

1. LEGACY BOARD (board.board)                2. SPREADSHEET DASHBOARD
   Per-user, action-based                       Company-wide, spreadsheet-based
   ┌──────────────────────┐                     ┌──────────────────────┐
   │ ir.ui.view.custom    │                     │ spreadsheet.dashboard│
   │ (XML arch per user)  │                     │ (binary JSON data)   │
   │ ┌──────┐ ┌────────┐  │                     │ ┌──────────────────┐ │
   │ │action│ │ action │  │                     │ │ Charts + Pivots  │ │
   │ │(list)│ │(graph) │  │                     │ │ + KPI cards      │ │
   │ └──────┘ └────────┘  │                     │ └──────────────────┘ │
   └──────────────────────┘                     └──────────────────────┘
   Menu: Dashboards → My Dashboard             Menu: Dashboards → [Group Name]
```

---

## System 1: Legacy Board (`board.board`)

### How It Works

The legacy board is an **AbstractModel** with no database table. Dashboard layout is stored as XML in `ir.ui.view.custom`, one record per user. Each dashboard block is an `<action>` XML element referencing an `ir.actions.act_window` ID.

### Data Model

#### `board.board` — Abstract Dashboard Model
> [`models/board.py`](../addons/board/models/board.py)

| Field | Type | Purpose |
|---|---|---|
| `id` | `Id` | Dummy field required for form view onchange initialization |

This model has **no real fields**. All data lives in `ir.ui.view.custom`.

#### Storage: `ir.ui.view.custom`

| Column | Purpose |
|---|---|
| `user_id` | Owner — each user has their own custom view |
| `ref_id` | Points to `board.board` base form view (`board.board_my_dash_view`) |
| `arch` | XML string containing `<board>` with `<column>` and `<action>` elements |

**Example stored arch:**
```xml
<form string="My Dashboard" js_class="board">
    <board style="2-1">
        <column>
            <action name="123" string="My Sales" view_mode="list"
                    context="{'group_by': ['partner_id']}"
                    domain="[('state', '=', 'sale')]" fold="0"/>
            <action name="456" string="Pipeline" view_mode="graph"
                    context="{}" domain="[]" fold="1"/>
        </column>
        <column>
            <action name="789" string="Tasks" view_mode="list"
                    context="{}" domain="[]" fold="0"/>
        </column>
    </board>
</form>
```

### Key Methods

| Method | File:Line | Purpose |
|---|---|---|
| `get_view()` | [`board.py:23`](../addons/board/models/board.py#L23) | Merges base view with user's `ir.ui.view.custom` arch |
| `_arch_preprocessing()` | [`board.py:39`](../addons/board/models/board.py#L39) | Forces `js_class='board'`, removes `<action>` nodes with `invisible` attribute |
| `add_to_dashboard()` | [`main.py:12`](../addons/board/controllers/main.py#L12) | RPC endpoint that inserts new `<action>` into user's custom view XML |

#### get_view() — Dashboard Loading
> [`board.py:23-36`](../addons/board/models/board.py#L23-L36)

1. Calls `super().get_view()` to get the base board form view
2. Searches `ir.ui.view.custom` for current user's customization of this view
3. If found, replaces the arch with the user's custom arch
4. Runs `_arch_preprocessing()` to set `js_class='board'` and strip unauthorized actions

#### add_to_dashboard() — Adding Actions from Any View
> [`main.py:12-44`](../addons/board/controllers/main.py#L12-L44)

1. Loads "My Dashboard" action via xmlid `board.open_board_my_dash_action`
2. Gets the current board arch (base or user-customized)
3. Creates a new `<action>` element with: action ID, display name, view_mode, context (filters/group_by), domain
4. Inserts it as the **first child** of the first `<column>`
5. Creates or updates `ir.ui.view.custom` for the user

### Frontend Components (OWL)

| Component | File | Purpose |
|---|---|---|
| `BoardView` | [`board_view.js`](../addons/board/static/src/board_view.js) | View type registration + `BoardArchParser` for XML parsing |
| `BoardController` | [`board_controller.js`](../addons/board/static/src/board_controller.js) | Layout management, drag-drop, save to server |
| `BoardAction` | [`board_action.js`](../addons/board/static/src/board_action.js) | Renders each dashboard block by loading its action and instantiating the view |
| `AddToBoard` | [`add_to_board.js`](../addons/board/static/src/add_to_board/add_to_board.js) | Cog menu item "Add to My Dashboard" in list/graph/pivot views |

#### Layout Options

Defined in [`board_controller.js:74-96`](../addons/board/static/src/board_controller.js#L74-L96) and styled in [`board_controller.scss`](../addons/board/static/src/board_controller.scss):

| Layout Code | CSS Grid | Description |
|---|---|---|
| `1` | `1fr` | Single column |
| `1-1` | `1fr 1fr` | Two equal columns |
| `1-1-1` | `1fr 1fr 1fr` | Three equal columns |
| `2-1` | `2fr 1fr` | Wide left, narrow right (default) |
| `1-2` | `1fr 2fr` | Narrow left, wide right |

#### Drag-and-Drop

[`board_controller.js:29-48`](../addons/board/static/src/board_controller.js#L29-L48) uses `useSortable()` with `connectGroups: true` to allow moving action blocks between columns. Every move triggers `saveBoard()` which serializes the current state back to XML and POSTs to `/web/view/edit_custom`.

### How to Add Items to My Dashboard

**From the UI:**
1. Navigate to any list, graph, or pivot view
2. Apply filters, group by, or sorting as desired
3. Click the cog/gear menu icon
4. Select "Add to My Dashboard"
5. Enter a name and confirm
6. The current view (with all active filters/domain/context) is saved as a block

**What gets saved:** action ID, view_mode, domain (from search filters), context (including `group_by` and `orderedBy`), and display name. The `allowed_company_ids` key is explicitly stripped to allow multi-company widget filtering.

---

## System 2: Spreadsheet Dashboard (`spreadsheet.dashboard`)

### How It Works

Spreadsheet dashboards store their content as binary JSON data (via `spreadsheet.mixin`). Each dashboard belongs to a `spreadsheet.dashboard.group` which determines its menu placement. Pre-built dashboards are installed as XML data records with a `sample_dashboard_file_path` pointing to a JSON file.

### Key Models

#### `spreadsheet.dashboard` — Dashboard Record
> [`models/spreadsheet_dashboard.py`](../addons/spreadsheet_dashboard/models/spreadsheet_dashboard.py)

| Field | Type | UI Label | Purpose |
|---|---|---|---|
| `name` | `Char` | — | Dashboard title (translatable) |
| `dashboard_group_id` | `Many2one` → `spreadsheet.dashboard.group` | — | Parent group (determines menu section) |
| `sequence` | `Integer` | — | Display order within group |
| `is_published` | `Boolean` | — | Whether visible to users (default `True`) |
| `company_ids` | `Many2many` → `res.company` | "Companies" | Multi-company visibility filter |
| `group_ids` | `Many2many` → `res.groups` | — | Security groups that can see this dashboard (default: `base.group_user`) |
| `favorite_user_ids` | `Many2many` → `res.users` | "Favorite Users" | Users who favorited this dashboard |
| `is_favorite` | `Boolean` (computed) | "Is Favorite" | Whether current user has favorited it |
| `main_data_model_ids` | `Many2many` → `ir.model` | — | Models checked for empty-data detection (triggers sample data) |
| `sample_dashboard_file_path` | `Char` | — | Path to sample JSON file shown when main models have no data |

**Inherited from `spreadsheet.mixin`:**

| Field | Type | Purpose |
|---|---|---|
| `spreadsheet_binary_data` | `Binary` | Base64-encoded JSON spreadsheet content |
| `spreadsheet_data` | `Text` (computed) | Decoded JSON string |

#### `spreadsheet.dashboard.group` — Dashboard Container
> [`models/spreadsheet_dashboard_group.py`](../addons/spreadsheet_dashboard/models/spreadsheet_dashboard_group.py)

| Field | Type | Purpose |
|---|---|---|
| `name` | `Char` | Group name shown in menu (translatable) |
| `dashboard_ids` | `One2many` | All dashboards in this group |
| `published_dashboard_ids` | `One2many` | Only published dashboards (`is_published = True`) |
| `sequence` | `Integer` | Menu display order |

Groups defined in XML data (installed by modules) cannot be deleted — enforced by [`_unlink_except_spreadsheet_data()`](../addons/spreadsheet_dashboard/models/spreadsheet_dashboard_group.py#L16).

#### `spreadsheet.dashboard.share` — Shared Dashboard Copy
> [`models/spreadsheet_dashboard_share.py`](../addons/spreadsheet_dashboard/models/spreadsheet_dashboard_share.py)

| Field | Type | Purpose |
|---|---|---|
| `dashboard_id` | `Many2one` → `spreadsheet.dashboard` | Source dashboard |
| `excel_export` | `Binary` | Optional Excel file for download |
| `access_token` | `Char` | UUID token for public URL |
| `full_url` | `Char` (computed) | Public share URL: `/dashboard/share/{id}/{token}` |

### Key Methods

| Method | File:Line | Purpose |
|---|---|---|
| `_get_serialized_readonly_dashboard()` | [`spreadsheet_dashboard.py:47`](../addons/spreadsheet_dashboard/models/spreadsheet_dashboard.py#L47) | Returns JSON snapshot with locale + currency for viewer |
| `_dashboard_is_empty()` | [`spreadsheet_dashboard.py:66`](../addons/spreadsheet_dashboard/models/spreadsheet_dashboard.py#L66) | Checks if any `main_data_model_ids` models have zero records |
| `_get_sample_dashboard()` | [`spreadsheet_dashboard.py:59`](../addons/spreadsheet_dashboard/models/spreadsheet_dashboard.py#L59) | Loads sample JSON from `sample_dashboard_file_path` |
| `action_toggle_favorite()` | [`spreadsheet_dashboard.py:39`](../addons/spreadsheet_dashboard/models/spreadsheet_dashboard.py#L39) | Adds/removes current user from favorites |
| `action_get_share_url()` | [`spreadsheet_dashboard_share.py:26`](../addons/spreadsheet_dashboard/models/spreadsheet_dashboard_share.py#L26) | Creates share record with token and returns public URL |
| `_check_dashboard_access()` | [`spreadsheet_dashboard_share.py:40`](../addons/spreadsheet_dashboard/models/spreadsheet_dashboard_share.py#L40) | Validates token + creator's read access before serving shared data |

### HTTP Routes

| Route | Auth | Purpose |
|---|---|---|
| `GET /spreadsheet/dashboard/data/<dashboard>` | `user` | Loads dashboard snapshot for authenticated users |
| `GET /dashboard/share/<id>/<token>` | `public` | Portal page for shared dashboards |
| `GET /dashboard/data/<id>/<token>` | `public` | JSON data endpoint for shared dashboards |
| `GET /dashboard/download/<id>/<token>` | `public` | Excel export download for shared dashboards |

**Dashboard data loading** ([`dashboards_controllers.py:8-33`](../addons/spreadsheet_dashboard/controllers/dashboards_controllers.py#L8-L33)):
1. Checks if dashboard exists
2. Applies multi-company context from cookies
3. If `_dashboard_is_empty()` and `sample_dashboard_file_path` exists, returns sample data with `is_sample: True`
4. Otherwise returns the real serialized dashboard JSON

### Sample Data Mechanism

When a `spreadsheet_dashboard_*` module is installed (e.g., CRM), it creates dashboard records with `sample_dashboard_file_path` pointing to a bundled JSON file. If the relevant data models have no records yet, the controller serves this sample data instead, so new users see example charts rather than blank dashboards. Once real data exists, sample data is never shown again.

---

## UI Entry Points

| Entry Point | Path in UI | What It Does |
|---|---|---|
| My Dashboard | Dashboards → My Dashboard | Opens legacy board with user's pinned actions |
| Add to My Dashboard | Any list/graph/pivot → Cog menu → "Add to My Dashboard" | Pins current filtered view to legacy board |
| Spreadsheet Dashboards | Dashboards → [Group Name] → [Dashboard Name] | Opens a spreadsheet-based dashboard in read-only viewer |
| Edit Dashboard | Dashboard → Edit button (Enterprise) | Opens spreadsheet editor for the dashboard |
| Share Dashboard | Dashboard → Share button (Enterprise) | Creates public share URL with optional Excel export |
| Publish/Unpublish | Dashboard → toggle (Enterprise) | Controls visibility to non-admin users |

---

## Configuration

| Setting | Location | Effect |
|---|---|---|
| `group_ids` on dashboard | `spreadsheet.dashboard` record | Controls which security groups can see a specific dashboard |
| `company_ids` on dashboard | `spreadsheet.dashboard` record | Restricts dashboard to specific companies |
| `is_published` on dashboard | `spreadsheet.dashboard` record | When `False`, hides dashboard from non-admin users |

### Access Control

**Legacy Board:**

| Model | Read | Write | Create | Delete |
|---|---|---|---|---|
| `board.board` | All internal users | No | No | No |

Actual data access is per-user via `ir.ui.view.custom` (only the creating user's record is loaded).

**Spreadsheet Dashboard:**

| Model | Access |
|---|---|
| `spreadsheet.dashboard` | Controlled by `group_ids` field on each record + standard ACL |
| `spreadsheet.dashboard.group` | All internal users (read), admin (write) |
| `spreadsheet.dashboard.share` | Creator + token-based public access |

---

## How to Create a Custom Dashboard

### Option A: Legacy Board — Pin Actions (No Code)

Best for: personal dashboards combining existing views with specific filters.

1. **Create filtered views:** Go to Sales Orders, apply domain filters (e.g., "My Orders", "This Month"), group by desired field
2. **Pin to dashboard:** Cog menu → "Add to My Dashboard" → enter name → confirm
3. **Repeat** for graph views, pivot views, or any other list/graph/pivot
4. **Arrange:** Open Dashboards → My Dashboard → drag blocks between columns, change layout from dropdown

### Option B: Spreadsheet Dashboard — Via UI (Enterprise)

Best for: shared KPI dashboards with charts, formulas, and pivot tables.

1. **Go to** Dashboards menu → click "New" or create from Spreadsheet app
2. **Build** using the spreadsheet editor: insert pivot tables via `Insert → Pivot`, add charts, use formulas like `=ODOO.PIVOT()`, `=ODOO.LIST()`, `=ODOO.PIVOT.HEADER()`
3. **Assign** to a dashboard group (determines menu section)
4. **Publish** to make visible to other users
5. **Set** `group_ids` and `company_ids` for access control

### Option C: Spreadsheet Dashboard — Via Custom Module (Code)

Best for: distributing pre-built dashboards with module installation.

**Step 1: Create the dashboard JSON**

Export an existing dashboard's `spreadsheet_data` or build one manually. Save as a JSON file in your module:

```
custom_addons/my_module/
    data/
        dashboards/
            my_custom_dashboard.json    # Spreadsheet JSON data
        dashboard_data.xml              # XML records
    __manifest__.py
```

See [Spreadsheet JSON Structure](#spreadsheet-json-structure) below for the full schema.

**Step 2: Define XML data records**

```xml
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <!-- Dashboard Group (container) -->
    <record id="dashboard_group_my_module" model="spreadsheet.dashboard.group">
        <field name="name">My Module</field>
        <field name="sequence">10</field>
    </record>

    <!-- Dashboard Record -->
    <record id="dashboard_my_custom" model="spreadsheet.dashboard">
        <field name="name">My Custom Dashboard</field>
        <field name="dashboard_group_id" ref="dashboard_group_my_module"/>
        <field name="sequence">1</field>
        <field name="group_ids" eval="[(4, ref('base.group_user'))]"/>
        <field name="sample_dashboard_file_path">my_module/data/dashboards/my_custom_dashboard.json</field>
        <field name="main_data_model_ids" eval="[(4, ref('sale.model_sale_order'))]"/>
    </record>
</odoo>
```

**Step 3: Update manifest**

```python
{
    'name': 'My Module',
    'depends': ['spreadsheet_dashboard', 'sale'],  # or whatever module provides your data models
    'data': [
        'data/dashboard_data.xml',
    ],
}
```

**Key fields to configure:**

| Field | What to set |
|---|---|
| `sample_dashboard_file_path` | Relative path to sample JSON — shown when no real data exists |
| `main_data_model_ids` | Models to check for empty data (triggers sample mode) |
| `group_ids` | Security groups allowed to see this dashboard |
| `company_ids` | Leave empty for all companies, or restrict to specific ones |
| `is_published` | Set `True` (default) to make visible immediately |

### Option D: Legacy Board — Pre-configured via XML (Code)

To distribute a pre-configured legacy board for all users, create a custom action pointing to `board.board` with a custom form view:

```xml
<record model="ir.ui.view" id="my_custom_board_view">
    <field name="name">My Team Dashboard</field>
    <field name="model">board.board</field>
    <field name="arch" type="xml">
        <form string="My Team Dashboard">
            <board style="1-1">
                <column>
                    <action name="%(sale.action_quotations_with_onboarding)d"
                            string="My Quotations"
                            view_mode="list"
                            context="{'search_default_my_quotation': 1}"
                            domain="[]"/>
                </column>
                <column>
                    <action name="%(crm.crm_lead_all_pipeline)d"
                            string="Pipeline"
                            view_mode="graph"
                            context="{}"
                            domain="[]"/>
                </column>
            </board>
        </form>
    </field>
</record>

<record model="ir.actions.act_window" id="action_my_custom_board">
    <field name="name">My Team Dashboard</field>
    <field name="res_model">board.board</field>
    <field name="view_mode">form</field>
    <field name="context">{'disable_toolbar': True}</field>
    <field name="usage">menu</field>
    <field name="view_id" ref="my_custom_board_view"/>
</record>

<menuitem id="menu_my_custom_board"
          name="My Team Dashboard"
          parent="spreadsheet_dashboard.spreadsheet_dashboard_menu_root"
          action="action_my_custom_board"
          sequence="50"/>
```

The `name` attribute on `<action>` is the **numeric ID** of an `ir.actions.act_window` record. Use `%(xmlid)d` syntax to reference by xmlid. Each `<action>` element supports:

| Attribute | Purpose |
|---|---|
| `name` | Action ID (numeric or `%(xmlid)d`) |
| `string` | Display title for the block |
| `view_mode` | Which view to render: `list`, `graph`, `pivot`, `calendar` |
| `context` | Python dict string with `group_by`, `search_default_*`, `orderedBy` |
| `domain` | Python domain expression string for filtering |
| `fold` | `"0"` = expanded, `"1"` = collapsed |

---

## Spreadsheet JSON Structure

The `spreadsheet_binary_data` field (and sample JSON files at `sample_dashboard_file_path`) use the following schema. Real examples live under [`enterprise/spreadsheet_dashboard_*/data/files/`](../enterprise/).

### Top-Level Keys

```json
{
  "version": "18.5.10",
  "sheets": [],
  "styles": {},
  "formats": {},
  "borders": {},
  "revisionId": "START_REVISION",
  "uniqueFigureIds": true,
  "settings": {},
  "pivots": {},
  "pivotNextId": 1,
  "lists": {},
  "listNextId": 1,
  "globalFilters": [],
  "customTableStyles": {},
  "chartOdooMenusReferences": {}
}
```

| Key | Type | Purpose |
|---|---|---|
| `version` | String | Spreadsheet format version (e.g., `"18.5.10"`) |
| `sheets` | Array | Sheet objects containing grids, cells, figures |
| `styles` | Object | Named style definitions `{ id: styleObj }` |
| `formats` | Object | Named number/date format strings `{ id: formatStr }` |
| `borders` | Object | Named border style definitions `{ id: borderObj }` |
| `revisionId` | String | Revision identifier (`"START_REVISION"` for new dashboards) |
| `uniqueFigureIds` | Boolean | Whether figure IDs are guaranteed unique |
| `settings` | Object | Locale, decimal separators, date format |
| `pivots` | Object | Pivot data sources `{ id: pivotConfig }` |
| `pivotNextId` | Number | Next auto-increment pivot ID |
| `lists` | Object | List data sources `{ id: listConfig }` |
| `listNextId` | Number | Next auto-increment list ID |
| `globalFilters` | Array | Shared filters across pivots/lists/charts |
| `customTableStyles` | Object | Custom table styling definitions |
| `chartOdooMenusReferences` | Object | Maps chart figure IDs to Odoo menu XML IDs (click-through navigation) |

### Sheet Object

Each entry in `sheets[]`:

```json
{
  "id": "Sheet1",
  "name": "Dashboard",
  "colNumber": 7,
  "rowNumber": 82,
  "rows": { "6": { "size": 40 } },
  "cols": { "0": { "size": 275 } },
  "merges": ["A1:B2"],
  "cells": { "A7": "=ODOO.LIST(1,1,\"name\")", "B1": "Revenue" },
  "styles": { "A7": 1, "A24": 2 },
  "formats": { "A10:A17": 1 },
  "borders": { "A23:C23": 1 },
  "conditionalFormats": [],
  "dataValidationRules": [],
  "figures": [],
  "tables": [],
  "areGridLinesVisible": true,
  "isVisible": true,
  "headerGroups": { "ROW": [], "COL": [] },
  "comments": {}
}
```

| Field | Type | Purpose |
|---|---|---|
| `id` | String | Unique sheet identifier |
| `name` | String | Tab name displayed in UI |
| `colNumber` / `rowNumber` | Number | Grid dimensions |
| `rows` / `cols` | Object | Custom sizes by index: `{ "0": { "size": 275 } }` |
| `merges` | Array | Merged ranges: `["A1:B2", "C5:D6"]` |
| `cells` | Object | Cell values/formulas keyed by ref: `{ "A1": "text", "B2": "=SUM()" }` |
| `styles` | Object | Style index per cell/range (refs top-level `styles`) |
| `formats` | Object | Format index per cell/range (refs top-level `formats`) |
| `borders` | Object | Border index per cell/range (refs top-level `borders`) |
| `figures` | Array | Charts, scorecards, images (see [Figures / Charts](#figures--charts)) |
| `tables` | Array | Spreadsheet table definitions |
| `conditionalFormats` | Array | Conditional formatting rules |
| `areGridLinesVisible` | Boolean | Show/hide gridlines |

### Pivots — `ODOO.PIVOT` Data Source

Each entry in `pivots: { id: {...} }`:

```json
{
  "id": "1",
  "type": "ODOO",
  "model": "crm.lead",
  "name": "Pipeline Analysis",
  "domain": [["type", "=", "opportunity"]],
  "context": {},
  "measures": [
    { "id": "expected_revenue", "fieldName": "expected_revenue", "aggregator": "sum" },
    { "id": "__count", "fieldName": "__count" }
  ],
  "columns": [{ "fieldName": "stage_id", "order": "asc" }],
  "rows": [{ "fieldName": "user_id", "order": "asc" }],
  "sortedColumn": null,
  "formulaId": "1",
  "fieldMatching": {
    "<global-filter-uuid>": { "chain": "date_deadline", "type": "date", "offset": 0 }
  }
}
```

| Field | Type | Purpose |
|---|---|---|
| `id` | String | Referenced in `=ODOO.PIVOT("1", ...)` formulas |
| `type` | String | Always `"ODOO"` for Odoo-connected pivots |
| `model` | String | Odoo model technical name |
| `name` | String | Display name in UI |
| `domain` | Array | Standard Odoo domain filter |
| `context` | Object | Odoo context (search defaults, etc.) |
| `measures` | Array | Fields to aggregate: `{ id, fieldName, aggregator }` |
| `columns` | Array | Column grouping fields: `{ fieldName, order, granularity }` |
| `rows` | Array | Row grouping fields: `{ fieldName, order, granularity }` |
| `sortedColumn` | null/Object | Active sort configuration |
| `formulaId` | String | Links pivot to `=ODOO.PIVOT()` cells |
| `fieldMatching` | Object | Maps global filter UUIDs to model fields for filtering |

**Measure aggregators:** `"sum"`, `"avg"`, `"min"`, `"max"`, `"count"`, `"count_distinct"`

**Granularity** (for date fields in rows/columns): `"day"`, `"week"`, `"month"`, `"quarter"`, `"year"`

**`fieldMatching` value structure:**
```json
{ "chain": "date_field", "type": "date", "offset": 0 }
{ "chain": "partner_id", "type": "many2one" }
{ "chain": "tag_ids", "type": "many2many" }
```
- `chain` — dot-path to the model field (e.g., `"user_id.country_id"`)
- `type` — field type for proper filter application
- `offset` — for date filters, month offset to shift the period

### Lists — `ODOO.LIST` Data Source

Each entry in `lists: { id: {...} }`:

```json
{
  "id": "1",
  "model": "sale.order",
  "name": "Top Sales Orders",
  "columns": ["name", "partner_id", "amount_total", "state"],
  "domain": [["state", "=", "sale"]],
  "context": {},
  "orderBy": [{ "name": "amount_total", "asc": false }],
  "fieldMatching": {
    "<global-filter-uuid>": { "chain": "date_order", "type": "date", "offset": 0 }
  }
}
```

| Field | Type | Purpose |
|---|---|---|
| `id` | String | Referenced in `=ODOO.LIST("1", ...)` formulas |
| `model` | String | Odoo model technical name |
| `name` | String | Display name |
| `columns` | Array | Field names to fetch (column order) |
| `domain` | Array | Standard Odoo domain filter |
| `context` | Object | Odoo context |
| `orderBy` | Array | Sort rules: `[{ "name": "field", "asc": true/false }]` |
| `fieldMatching` | Object | Global filter field mapping (same structure as pivots) |

### Global Filters

Each entry in `globalFilters[]`:

**Date filter:**
```json
{
  "id": "5dac8b40-3868-4049-a237-6fc28656c7a4",
  "type": "date",
  "label": "Period",
  "defaultValue": "this_month"
}
```

`defaultValue` options: `"today"`, `"yesterday"`, `"this_week"`, `"this_month"`, `"this_quarter"`, `"this_year"`, `"last_7_days"`, `"last_30_days"`, `"last_90_days"`, `"last_12_months"`, `"last_month"`, `"month_to_date"`, `"year_to_date"`

**Relation filter:**
```json
{
  "id": "2967df50-3aec-4336-af5d-4eaceb383120",
  "type": "relation",
  "label": "Salesperson",
  "modelName": "res.users",
  "defaultValue": { "operator": "in", "ids": "current_user" },
  "defaultValueDisplayNames": []
}
```

`defaultValue.operator` options: `"in"`, `"not in"`, `"child_of"`, `"set"`, `"not set"`
`defaultValue.ids` — array of record IDs, or `"current_user"` for dynamic current user

### Figures / Charts

Located in `sheets[].figures[]`. All figures share a common wrapper:

```json
{
  "id": "uuid-string",
  "tag": "chart",
  "width": 500,
  "height": 300,
  "col": 0,
  "row": 0,
  "offset": { "x": 0, "y": 9 },
  "data": { ... }
}
```

**Scorecard (KPI card):**
```json
"data": {
  "type": "scorecard",
  "title": { "text": "New MRR", "bold": true, "color": "#434343" },
  "keyValue": "Data!D2",
  "baseline": "Data!E2",
  "baselineDescr": { "text": "vs last month" },
  "baselineMode": "percentage",
  "baselineColorUp": "#00A04A",
  "baselineColorDown": "#DC6965",
  "background": "#EFF6FF",
  "humanize": false
}
```

| Field | Purpose |
|---|---|
| `keyValue` | Cell ref for the main KPI number |
| `baseline` | Cell ref for comparison value |
| `baselineMode` | `"text"`, `"percentage"`, or `"difference"` |
| `baselineColorUp` / `baselineColorDown` | Colors for positive/negative trend |
| `humanize` | Abbreviate large numbers (1.2M instead of 1,200,000) |

**Odoo chart (connected to model):**
```json
"data": {
  "type": "odoo_bar",
  "title": { "text": "Revenue by Month" },
  "background": "#FFFFFF",
  "legendPosition": "top",
  "metaData": {
    "resModel": "account.move.line",
    "measure": "balance",
    "groupBy": ["date:month"],
    "mode": "bar",
    "order": null
  },
  "searchParams": {
    "domain": [["move_id.state", "=", "posted"]],
    "context": {},
    "groupBy": ["date:month"],
    "orderBy": [],
    "comparison": null
  },
  "fieldMatching": { ... },
  "stacked": false,
  "verticalAxisPosition": "left",
  "axesDesign": { "y": { "title": { "text": "Balance" } } }
}
```

Odoo chart `type` values: `"odoo_bar"`, `"odoo_line"`, `"odoo_pie"`

**Static chart (cell-range based):**
```json
"data": {
  "type": "line",
  "dataSetsHaveTitle": false,
  "dataSets": [{ "dataRange": "Data!B13:B19", "yAxisId": "y" }],
  "labelRange": "Data!A13:A19",
  "labelsAsText": true,
  "legendPosition": "none",
  "stacked": false,
  "cumulative": true,
  "fillArea": true
}
```

Static chart `type` values: `"bar"`, `"line"`, `"pie"`, `"doughnut"`, `"area"`

### Styles and Formats

**Styles** (`styles: { id: styleObj }`):
```json
{
  "1": { "textColor": "#01666b", "fontSize": 16, "bold": true },
  "2": { "fillColor": "#f8f9fa", "align": "center" },
  "3": { "italic": true, "wrapping": "wrap" }
}
```

Properties: `textColor`, `fillColor`, `fontSize`, `bold`, `italic`, `align` (`"left"` / `"center"` / `"right"`), `wrapping` (`"overflow"` / `"wrap"` / `"clip"`)

**Formats** (`formats: { id: formatString }`):
```json
{
  "1": "mmmm yyyy",
  "2": "[$$]#,##0",
  "3": "0.00%",
  "4": "#,##0.00"
}
```

### Settings

```json
{
  "locale": {
    "name": "English (US)",
    "code": "en_US",
    "thousandsSeparator": ",",
    "decimalSeparator": ".",
    "dateFormat": "mm/dd/yyyy",
    "timeFormat": "hh:mm:ss",
    "formulaArgSeparator": ",",
    "weekStart": 7
  }
}
```

### chartOdooMenusReferences

Maps chart figure IDs to Odoo menu XML IDs. When a user clicks a chart, Odoo navigates to the linked menu action:

```json
{
  "a6a21399-abd8-4175-8239-648be24e3cea": "crm.crm_menu_root",
  "b7c32400-bce9-5286-9340-759cf335f34b": "sale.sale_menu_root"
}
```

---

## Spreadsheet Formulas Reference

### ODOO.PIVOT

Retrieves aggregated values from a pivot data source.

| Formula | Purpose |
|---|---|
| `=ODOO.PIVOT(pivot_id, measure)` | Total value for a measure |
| `=ODOO.PIVOT(pivot_id, measure, row_field, row_value, ...)` | Value filtered by row/column groups |

```
=ODOO.PIVOT("1", "expected_revenue")
=ODOO.PIVOT("1", "expected_revenue", "stage_id", 4)
=ODOO.PIVOT("1", "amount_total", "partner_id", 12, "date:month", "03/2026")
=ODOO.PIVOT("1", "__count")
```

Arguments after `measure` are field/value pairs that filter the pivot. Date fields use `granularity` syntax: `"date:month"`, `"date:quarter"`, `"date:year"`.

### ODOO.PIVOT.HEADER

Retrieves the display label for a pivot group header.

```
=ODOO.PIVOT.HEADER("1", "stage_id", 4)
=ODOO.PIVOT.HEADER("1", "date:month", "03/2026")
=ODOO.PIVOT.HEADER("1")
```

Returns the human-readable name (e.g., stage name, partner name, formatted date) rather than the raw ID.

### ODOO.PIVOT.TABLE

Inserts an entire pivot table that auto-expands across cells.

```
=ODOO.PIVOT.TABLE("1")
=ODOO.PIVOT.TABLE("1", TRUE, FALSE)
```

Arguments: `(pivot_id, include_row_totals, include_col_totals)`. Defaults to `TRUE, TRUE`.

### ODOO.LIST

Retrieves a single cell value from a list data source.

```
=ODOO.LIST("1", 1, "name")
=ODOO.LIST("1", 1, "amount_total")
=ODOO.LIST("1", 3, "partner_id")
```

Arguments: `(list_id, row_index, field_name)`. `row_index` is 1-based.

### ODOO.LIST.HEADER

Retrieves the column header label for a list field.

```
=ODOO.LIST.HEADER("1", "name")
=ODOO.LIST.HEADER("1", "amount_total", "Total Amount")
```

Arguments: `(list_id, field_name, [optional_display_name])`. If `optional_display_name` is provided, it overrides the field's default label.

### ODOO.FILTER.VALUE

Returns the current value of a global filter by its label.

```
=ODOO.FILTER.VALUE("Period")
=ODOO.FILTER.VALUE("Salesperson")
```

### _t() — Translatable Text

Wraps a string for Odoo's translation system. The text inside is extractable by Odoo's `i18n` tools.

```
=_t("Revenue")
=_t("Total Sales")
```

### Odoo Action Links in Cells

Cells can contain markdown-style links that navigate to Odoo views when clicked:

```
[View Orders](odoo://view/{"viewType":"list","action":{"modelName":"sale.order","domain":[["state","=","sale"]]}})
```

---

## Edge Cases and Gotchas

- **Legacy board is per-user only.** There is no way to share a legacy board configuration with other users through the UI. Each user's `ir.ui.view.custom` is independent. To share, create a base view in XML (Option D above).
- **Legacy board has no form view blocks.** Only `list`, `graph`, `pivot`, `calendar` views can be added. Form views and kanban views are not supported in board blocks.
- **Legacy board actions use frozen filters.** The domain and context are captured at the time of pinning. If the underlying action's default filters change, the board block keeps its original filters.
- **Spreadsheet dashboards require Enterprise for editing.** Community edition can only view pre-built dashboards. The `spreadsheet_dashboard_edition` module provides the edit/publish/share capabilities.
- **Sample data disappears permanently.** Once any record exists in the `main_data_model_ids` models, the sample dashboard is never shown again — even if all records are later deleted. The check is `search_count([], limit=1) == 0`.
- **Dashboard groups from modules cannot be deleted.** The [`_unlink_except_spreadsheet_data()`](../addons/spreadsheet_dashboard/models/spreadsheet_dashboard_group.py#L16) constraint prevents deleting groups that have external IDs (installed via XML).
- **Multi-company filtering.** The dashboard data controller reads `cids` from cookies to set `allowed_company_ids` context. This means dashboard data respects the user's current company selection in the top bar.
- **`allowed_company_ids` stripped from board context.** The [`add_to_dashboard()`](../addons/board/controllers/main.py#L26-L27) controller explicitly removes `allowed_company_ids` from saved context so the multi-company widget works correctly on each dashboard load.
- **Mobile layout.** On small screens, the legacy board forces single-column layout via [`board_controller.js:25-26`](../addons/board/static/src/board_controller.js#L25-L26).

---

## Related Docs

- [`INDEX.md`](INDEX.md)

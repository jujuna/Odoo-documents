# Dashboards — Odoo 20

> Reviewed against the local source on 2026-09-22. Modules: [`board`](../addons/board/), [`spreadsheet_dashboard`](../addons/spreadsheet_dashboard/), and Enterprise [`spreadsheet_dashboard_edition`](../enterprise/spreadsheet_dashboard_edition/).

## Two Dashboard Systems

| System | Best use | Storage and scope |
|---|---|---|
| My Dashboard (`board.board`) | Pin existing filtered views into a personal page | XML layout in `ir.ui.view.custom`, per user and base view |
| Spreadsheet dashboards (`spreadsheet.dashboard`) | Shared KPIs, formulas, pivots, lists and charts | Spreadsheet snapshot/revisions plus dashboard access configuration |

`board` depends on `spreadsheet_dashboard`, which depends on `spreadsheet`. Both are Community modules in this checkout. Enterprise `spreadsheet_dashboard_edition` adds collaborative editing and editor actions and depends on `spreadsheet_edition`; it is auto-install. The Community dashboard module already contains publication fields, favorites, share records and public share routes. Sharing is not exclusively supplied by the Enterprise editor.

Use a board for a salesperson's filtered orders and pipeline views. Use a spreadsheet dashboard for a finance team's combined KPI sheet or a reusable department dashboard. A public share is a frozen snapshot; it is not a live public query endpoint into the underlying business models.

## My Dashboard: User Flow

1. Open an existing window action, choose a view and apply filters/grouping.
2. In its cog menu, choose **Add to My Dashboard**, supply a title and add it.
3. Open **Dashboards → My Dashboard** and refresh if prompted.
4. Move block headers between columns, select a layout, collapse blocks or remove them with confirmation.

The menu's availability condition requires an `ir.actions.act_window`, an action ID and a view type other than `form`. The source does **not** limit it to list/graph/pivot/calendar or categorically exclude kanban. A particular action/view still needs to support embedding.

Source: [`add_to_board.js`](../addons/board/static/src/add_to_board/add_to_board.js).

### Storage and Loading

[`board.board`](../addons/board/models/board.py) is an abstract, `_auto = False` model with a dummy `id`; it does not store dashboard business records. Its `create()` returns the empty model recordset. `get_view()` reads the current user's custom XML for the requested base view, substitutes it for the base architecture, then adds `js_class = board`.

`_arch_preprocessing()` removes action nodes carrying an `invisible` attribute. This XML preprocessing is separate from access enforcement: data loaded by embedded views remains subject to the user's normal permissions.

[`/board/add_to_dashboard`](../addons/board/controllers/main.py) is an authenticated `jsonrpc` route. It inserts a new `<action>` at the beginning of the first dashboard column and creates a user-specific `ir.ui.view.custom`. It explicitly strips `allowed_company_ids` from saved context so pinning a block does not freeze the selected companies.

The frontend saves the current domain, pre-favorite grouping/order context and title. It removes `search_default_*` keys from the action's global context. These filters are captured when pinning; changing the original action later does not replace the block's saved filters.

### Rendering and Layout

Sources: [`board_view.js`](../addons/board/static/src/board_view.js), [`board_controller.js`](../addons/board/static/src/board_controller.js), [`board_action.js`](../addons/board/static/src/board_action.js).

- `BoardArchParser` reads columns and action attributes, including title, action ID, view mode, domain, context and fold state.
- `BoardAction` loads the referenced action through `/web/action/load`, caches its definition by action ID and embeds its view without a control panel. List blocks disable selectors; selecting a record opens its form.
- The controller supports `1`, `1-1`, `1-2`, `2-1`, and `1-1-1` layouts. Reducing the column count moves blocks into the final visible column.
- Dragging, folding and layout changes serialize the XML and save through `/web/view/edit_custom`.
- Small-screen mode selects one column without saving that choice as the persistent layout.

A personal board layout is not shared through a share-link UI. A custom module can distribute a base board view; each user's later customization remains separate.

### Developer Example: Base Board

Use actual action XML IDs from dependencies and numeric interpolation in the action node:

```xml
<record id="my_board_view" model="ir.ui.view">
    <field name="name">My Team Overview</field>
    <field name="model">board.board</field>
    <field name="arch" type="xml">
        <form string="Team Overview">
            <board style="1">
                <column>
                    <action name="%(sale.action_orders)d"
                            string="Sales Orders" view_mode="list"
                            domain="[('state', '=', 'sale')]"/>
                </column>
            </board>
        </form>
    </field>
</record>
```

The module needs `board` and `sale`, plus a window action/menu opening this form. Follow the shipped [`board_views.xml`](../addons/board/views/board_views.xml) for the full action structure. Existing custom views can override later changes to the base XML.

## Spreadsheet Dashboard Models

Source: [`spreadsheet_dashboard.py`](../addons/spreadsheet_dashboard/models/spreadsheet_dashboard.py).

| Field/model | Purpose |
|---|---|
| `name`, `sequence` | Translated name and ordering |
| `dashboard_group_id` | Required dashboard **Section** |
| `spreadsheet_binary_data` / `spreadsheet_data` | Snapshot fields supplied by `spreadsheet.mixin` |
| `is_published` | Defaults true; published dashboards populate the dashboard navigator |
| `group_ids` | Access groups; defaults to internal users |
| `allowed_user_ids` | Additional specifically allowed users |
| `company_ids` | Company visibility restriction |
| `favorite_user_ids`, `is_favorite` | Per-user favorite state |
| `main_data_model_ids` | Models checked to decide whether to display sample data |
| `sample_dashboard_file_path` | Optional sample snapshot resource |
| `spreadsheet.dashboard.group` | Section with dashboards and published-dashboard subset |
| `spreadsheet.dashboard.favorite.filters` | Named saved global-filter presets, optionally shared/default |
| `spreadsheet.dashboard.share` | Stored copy with token, active flag and optional Excel export |

`action_toggle_favorite()` changes only the current user's membership, using sudo for that write. Favorite filters have `user_ids`, `global_filters`, `is_default` and `active`; an empty users list means shared with all users under their access rules. Sources: [`favorite filters`](../addons/spreadsheet_dashboard/models/spreadsheet_dashboard_favorite_filters.py), [`section model`](../addons/spreadsheet_dashboard/models/spreadsheet_dashboard_group.py).

## Loading, Publication and Sample Data

The client action is `action_spreadsheet_dashboard`, with optional `params.dashboard_id`. The [`loader service`](../addons/spreadsheet_dashboard/static/src/bundle/dashboard_action/dashboard_loader_service.js) loads sections with `published_dashboard_ids`, maintains client-side state and builds a favorites section.

The authenticated [`data controller`](../addons/spreadsheet_dashboard/controllers/dashboards_controllers.py) serves `/spreadsheet/dashboard/data/<dashboard>`. The base serializer returns snapshot, empty revisions, user locale, company currency and translation namespace. Enterprise overrides serialization to include collaborative revisions and a locale-update command.

Publication controls normal navigation. It is **not** itself a record-access rule: the access CSV does not deny reads solely because `is_published` is false. Unpublishing is not a substitute for restricting users/groups/companies or revoking share links.

Sample data is selected when a sample path is configured and `_dashboard_is_empty()` returns true. In Community, **any** configured main model with no records makes that check true. It is evaluated again; creating one record does not permanently disable samples, and another empty main model can still trigger them. The emptiness check uses sudo when the user lacks model read access; that check is not a grant to view business data. Enterprise additionally requires no spreadsheet revisions, including inactive revisions, before considering a dashboard empty.

The current controller does not manually parse a `cids` cookie. Company context and dashboard record rules apply through the request/ORM; data sources have their own model permissions.

## Access and Sharing

Sources: [`ir.access.csv`](../addons/spreadsheet_dashboard/security/ir.access.csv), [`security.xml`](../addons/spreadsheet_dashboard/security/security.xml), [`share model`](../addons/spreadsheet_dashboard/models/spreadsheet_dashboard_share.py), [`share routes`](../addons/spreadsheet_dashboard/controllers/share.py).

For internal users, dashboard read access can be granted by a matching access group **or** membership in `allowed_user_ids`. The global company restriction still applies. Dashboard Admin (`spreadsheet_dashboard.group_dashboard_manager`) receives management access. Allowing a user to read the dashboard does not grant that user access to every model queried by its pivots/lists/charts.

Share records belong to their creator under the user access rule; dashboard administrators can manage them. A public request must supply a valid constant-time-checked token, the share must exist and be active, and its creator must still have read access to the source dashboard. A token alone is not the entire check.

| Route | Authentication and effect |
|---|---|
| `/dashboard/share/<share_id>/<token>` | Public frozen-dashboard page after share checks |
| `/dashboard/data/<share_id>/<token>` | Public GET of the stored shared snapshot after share checks |
| `/dashboard/download/<share_id>/<token>` | **Logged-in user required**, plus `base.group_allow_export` and share checks |

`action_get_share_url()` creates a share from the supplied snapshot and optionally packages supplied Excel files. Existing links display that stored copy; editing the live dashboard does not refresh it. Archive/deactivate or delete a share to disable its routes. The normal dashboard UI already includes a share button in the Community [`dashboard action`](../addons/spreadsheet_dashboard/static/src/bundle/dashboard_action/dashboard_action.js).

Sections installed with a non-export external ID cannot be deleted. The model explicitly permits the `__export__` external-ID case, so “any XML ID prevents deletion” is too broad.

## Editing and Publishing

Enterprise [`spreadsheet_dashboard_edition`](../enterprise/spreadsheet_dashboard_edition/models/spreadsheet_dashboard.py) adds `action_edit_dashboard` / `action_open_spreadsheet`, collaborative snapshot/revision loading and editor metadata. `is_from_data` is inferred from both a sample file path and an XML ID; it is not simply a test for every preinstalled record.

A practical flow is to create/edit a spreadsheet dashboard, assign its section and access scope, verify the actual data sources, then publish it. Configuration menus expose dashboards, sections and share links for dashboard administrators.

With [`spreadsheet_dashboard_documents`](../enterprise/spreadsheet_dashboard_documents/wizard/documents_to_dashboard.py), converting a spreadsheet document creates a dashboard, transfers its cell-comment threads and **archives the original document**. It is not an ongoing live link between two independently edited copies.

## Developer Example: Install a Spreadsheet Dashboard

Build/export a snapshot using this checkout's spreadsheet editor or adapt a shipped dashboard. Declare dependencies for both the dashboard module and every business model/XML ID referenced.

```xml
<odoo>
    <record id="my_dashboard_section" model="spreadsheet.dashboard.group">
        <field name="name">Operations</field>
        <field name="sequence">50</field>
    </record>
    <record id="my_dashboard" model="spreadsheet.dashboard">
        <field name="name">Operations Overview</field>
        <field name="dashboard_group_id" ref="my_dashboard_section"/>
        <field name="spreadsheet_binary_data" type="bytes"
               file="my_module/data/operations_dashboard.json"/>
        <field name="group_ids" eval="[Command.set([ref('base.group_user')])]"/>
        <field name="sequence">10</field>
        <field name="is_published">True</field>
    </record>
</odoo>
```

`my_module` and its JSON file are placeholders. Add this XML to the module manifest's `data`. Use `Command.set` when replacing access groups; linking a restricted group without removing a broad default group may leave broader access than intended. For optional samples, set `main_data_model_ids` and `sample_dashboard_file_path` as in the shipped [`Sales dashboard XML`](../addons/spreadsheet_dashboard_sale/data/dashboards.xml).

## Snapshot Format and Formulas

Spreadsheet serialization has its own version/migrations. **Do not set snapshot version to `20.0` just because the server is Odoo 20.** The shipped [`Sales snapshot`](../addons/spreadsheet_dashboard_sale/data/files/sales_dashboard.json) currently declares `19.3.10`.

That snapshot contains `sheets`, `styles`, `formats`, `borders`, `revisionId`, `settings`, `pivots`, `lists`, `globalFilters`, `namedRanges`, `customTableStyles`, counters and `odooLinkReferences`. Sheets include cell contents plus separate formatting maps, dimensions, tables, figures and visibility settings. Copy an exported versioned structure rather than treating an old hand-written JSON example as a complete stable schema.

Odoo pivot definitions contain model/domain/context, row and column fields, measure IDs/fields, sorting, a `formulaId`, and `fieldMatching` for global filters. Lists contain model/domain/context, ordering and **column objects** such as `{"name": "amount_total"}`—not just an array of field-name strings. Explicit `string` headers in source dashboards are checked in Enterprise tests unless `translateHeaders` is enabled; this extra validation is test-only.

Global filters must be mapped to relevant source fields through `fieldMatching`; adding a filter label alone does not make it filter every source. Relation filters identify a model; date filters carry ranges/defaults, with date offsets interpreted by the matching implementation. Charts may use cell ranges or Odoo sources, and their version-specific figure data should be exported from this build.

### Current Formula Names

Sources: [`spreadsheet library`](../addons/spreadsheet/static/src/o_spreadsheet/o_spreadsheet.js), [`list functions`](../addons/spreadsheet/static/src/list/list_functions.js), [`filter functions`](../addons/spreadsheet/static/src/pivot/pivot_functions.js), [`migrations`](../addons/spreadsheet/static/src/o_spreadsheet/migration.js).

| Formula | Current purpose |
|---|---|
| `=PIVOT.VALUE("1", "amount_total")` | Aggregate measure from pivot 1; optional dimension/value pairs narrow the result |
| `=PIVOT.HEADER("1", "partner_id", 12)` | Pivot group label |
| `=PIVOT("1")` | Spill a pivot table |
| `=ODOO.LIST.VALUE("1", 1, "name")` | One list cell; row index is 1-based |
| `=ODOO.LIST("1", 20)` | Spill list rows, optionally limiting row count |
| `=ODOO.LIST.HEADER("1", "name")` | Column label; optional third argument overrides the display label |
| `=ODOO.FILTER.VALUE("Period")` | Current filter value; can return an array/range, not necessarily a human-readable single label |
| `=ODOO.FILTER.LABEL("Period")` | Human-readable representation of the current filter value |

Pivot IDs, measure IDs and fields must match the snapshot definitions. `PIVOT` arguments are `(pivot_id, row_count, include_total, include_column_titles, column_count, include_measure_titles)`, with optional arguments and totals/titles defaulting true. The old `ODOO.PIVOT.TABLE(id, row_totals, column_totals)` signature is not the current API.

Migration maps `ODOO.PIVOT` → `PIVOT.VALUE`, `ODOO.PIVOT.HEADER` → `PIVOT.HEADER`, and `ODOO.PIVOT.TABLE` → `PIVOT`. The older three-argument `ODOO.LIST` cell formula must likewise not be copied as the current spill function. Default unbounded list retrieval has a 10,000-row guard and asks for an explicit row count if exceeded.

## Troubleshooting

| Symptom | Check |
|---|---|
| Dashboard absent from navigator | Publication, section, groups/allowed users, company rule |
| Dashboard opens but data is missing | Model access, record rules, source domain, global-filter mappings and enabled companies |
| Sample values appear | Configured main models and sample file; Enterprise revision history |
| Public link stopped working | Active share, token and creator's continued source-dashboard read access |
| Anonymous viewer cannot download Excel | Download route requires authentication and export rights |
| Board block ignores a new action default | It retains the domain/context captured when pinned |
| Old formulas fail in a new snapshot | Spreadsheet migration version and current formula names/signatures |
| Source XML changed but personal board did not | User-specific custom architecture overrides the base view |

## Related Docs

- [Documentation index](INDEX.md)

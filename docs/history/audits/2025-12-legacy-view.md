> **ARCHIVED 2026-05-01** — Preserved for historical context. See [current docs](../../README.md) for current state.

# Legacy HAML View Audit — Node & Instance Management

**Purpose:** Compare legacy `powernode-server` HAML views against the System extension's React UI; identify gaps worth porting and patterns to preserve.

**Scope:** Nodes + node instances + node modules. Other System:: areas (providers, volumes, networks, etc.) audited separately as needed.

**Source files:**
- Legacy HAML: `~/Drive/Projects/powernode-server/app/views/nodes/`, `app/views/node_instances/`
- React: `extensions/system/frontend/src/{pages/app/system,features/system/components/nodes}/`

---

## Coverage matrix

| Feature | Legacy | React | Status | Priority |
|---|---|---|---|---|
| Node list | `nodes/index.html.haml` | `NodeList.tsx` | ✅ | — |
| Node detail | `nodes/show.html.haml` (tabbed) | `NodeDetailModal.tsx` (tabbed) | ✅ | — |
| Node create | `nodes/_form.html.haml` | `CreateNodeModal.tsx` | ✅ | — |
| Node edit | `nodes/edit.html.haml` | `EditNodeModal.tsx` | ✅ | — |
| Node delete + confirm | `nodes/show.html.haml` | confirm modal in `NodesPage.tsx` | ✅ | — |
| Toggle enabled | row dropdown | `NodeList.tsx` | ✅ | — |
| Instance list | `_node_instances.html.haml` | Instances tab in `NodeDetailModal.tsx` | ✅ | — |
| Instance create | `_node_instances.html.haml` | `CreateInstanceModal.tsx` | ✅ | — |
| Instance edit | `node_instances/edit.html.haml` | `EditInstanceModal.tsx` | 🔄 | physical-only fields incomplete |
| Lifecycle: start / stop / reboot | `_node_instance_control.html.haml` | `NodeInstanceControls.tsx` | ✅ | — |
| Lifecycle: terminate | `_node_instance_control.html.haml` | `NodeInstanceControls.tsx` (with two-click confirm) | ✅ | — |
| Lifecycle: cleanse | `_node_instance_control.html.haml` | absent | ❌ | medium |
| Lifecycle: sync | `_node_instance_control.html.haml` | absent | ❌ | medium |
| Cascading provider selects (connection → region → type → AZ → subnet) | `_node_instances.html.haml:8-27` | `CreateInstanceModal.tsx:124-218` | ✅ | — |
| Set primary instance | `_node_instance_details.html.haml` | absent | ❌ | medium |
| Public IP associate / disassociate | `_node_instance_details.html.haml` | `NodeDetailModal.tsx` IP rows (cloud-only, gated by `system.instances.control`) | ✅ | — |
| Copy IP to clipboard | `_node_instance_details.html.haml` (clipboard.js) | `NodeDetailModal.tsx:168-176` | ✅ | — |
| Physical: create boot image | `_node_instance_control.html.haml` | absent | ❌ | low |
| Physical: reset key | `_node_instance_control.html.haml` | absent | ❌ | low |
| Physical: static netboot fields | `node_instances/edit.html.haml` | partial | 🔄 | low |
| Volumes display on instance | `_node_instance_volumes.html.haml` | absent | ❌ | low |
| Mount points display | `_node_instance_mount_points.html.haml` | absent | ❌ | low |
| Node modules tab — list | `_node_modules_tab.html.haml` | Modules tab in `NodeDetailModal.tsx` | 🔄 | list-only |
| Module subscribe / unsubscribe | `_node_module.html.haml` | absent | ❌ | medium |
| Module enable + copy-path | `_node_module_operations.html.haml` | absent | ❌ | medium |
| Module versions: restore / delete / purge | `_node_module_operations.html.haml` | absent | ❌ | low |
| Module lifecycle: build / commit | `_node_module_operations.html.haml` | absent | ❌ | low |
| Module dependency creation (config → instance) | `_node_module_controls.html.haml` | absent | ❌ | low |
| Puppet modules list | `_node_module_puppet_modules.html.haml` | absent | ❌ | low |
| Operations live updates | implicit (refresh button) | `NodeDetailModal.tsx` Operations tab + `useSystemWebSocket` | ✅ — improvement | — |
| Permission gating | `can?(:update, @node)` etc. | `currentUser.permissions.includes(...)` | ✅ | — |

Legend: ✅ covered · 🔄 partial / different · ❌ missing

---

## Patterns worth preserving

### 1. Status-driven control button visibility
Legacy uses `case node_instance.status` in `_node_instance_control.html.haml` to expose only valid lifecycle actions per state. React preserves this in `NodeInstanceControls.tsx` (`isRunning` / `isStopped` flags), but only for start/stop/reboot — needs extension to terminate / cleanse / sync.

### 2. Cascading cloud-provider selects
Legacy form (`_node_instances.html.haml:8-27`) chains five selects (connection → region → instance type → AZ → subnet) where each populates the next. React `CreateInstanceModal.tsx` exposes all five as flat dropdowns without filtering. This is the **largest concrete UX gap**: in production, an account with multiple connections has hundreds of instance-type/region combinations and the flat select is unworkable.

**Implementation note:** the React fix is a `useEffect` chain that reloads each downstream list when its upstream value changes, plus reset of all downstream values on upstream change.

### 3. Definition-list two-column detail layout
Legacy uses `%dl.dl-horizontal` in `_node_instance_details.html.haml`. React preserves this with Tailwind `grid-cols-1 md:grid-cols-2 gap-6` in `NodeDetailModal.tsx:283-348`. Same shape, different rendering.

### 4. Permission gating throughout
Legacy and React both gate visibility on user permissions. Legacy uses CanCanCan's `can?`; React uses `currentUser.permissions.includes(...)`. Pattern equivalent.

### 5. Refresh-on-demand vs. polling
Legacy uses an explicit refresh button per tab, no polling. React's `useOperations` hook (after recent refactor) is also no-poll: initial fetch + manual refresh + ActionCable subscription for live updates. Both eschew interval polling.

### 6. Confirmation patterns
Legacy used Rails browser-confirm (`data: { confirm }`). React replaced with proper modal components (`NodeDetailModal.tsx:486-511`). Strict improvement; preserve.

---

## Gaps worth porting (prioritized)

### Critical (do now)

- ~~**C1. Cascading cloud-provider selects**~~ — ✅ **Resolved** in `CreateInstanceModal.tsx:124-218` (six-level cascade: connection → region → {instance type, AZ, network} → subnet, with per-level loading state and downstream-clear-on-change).

### High (next sprint)

- ~~**H1. Quick-action terminate**~~ — ✅ **Resolved.** Added to `NodeInstanceControls.tsx` (both compact dropdown and standard bar). Two-click 5-second armed confirm pattern guards against accidents. Routes to new `POST /node_instances/:id/terminate` → `terminate` operation → `Runtime::ControlInstance`.
- ~~**H2. Public IP associate/disassociate**~~ — ✅ **Resolved.** Added inline buttons in `NodeDetailModal.tsx` next to the IP display. Backend wired through new `Runtime::ManagePublicIp` runtime which bridges to existing provider adapter `allocate_ip`/`associate_ip`/`disassociate_ip`/`release_ip` interface. Allocation IDs cached in `NodeInstance.config` to support clean release on disassociate.

### Medium (when relevant customer workflow surfaces)

- **M1. Set-primary-instance** action.
- **M2. Cleanse / sync** lifecycle actions exposed as instance card buttons.
- **M3. Module subscribe/unsubscribe** in node Modules tab.
- **M4. Module enable + copy-path** form in module detail modal.
- **M5. Physical-instance edit form** completeness (static netboot, MAC, gateway).

### Low (advanced features, gate on real demand)

- L1. Physical instance: boot image create / download.
- L2. Physical instance: reset key.
- L3. Module version operations (restore / delete / purge).
- L4. Module lifecycle (build / commit) UI.
- L5. Puppet-modules display on node.
- L6. Volumes + mount-points display on instance card.
- L7. Module dependency creation (config-module → instance-module).

---

## React implementation that improves on legacy

### Operations tab (live progress)
`NodeDetailModal.tsx` has an Operations tab with progress bars subscribed via `useSystemWebSocket`. Legacy had no equivalent — operations were tracked separately and required manual refresh. This is a strict improvement worth keeping.

### Modular component layout
Legacy nests partials (`_node_instance.html.haml` renders four sub-partials inline). React splits into named components (`NodeList`, `NodeDetailModal`, `CreateInstanceModal`, etc.) — easier to test and reason about.

### Responsive desktop + mobile
`NodeList.tsx` renders a desktop table and mobile cards via responsive utilities. Legacy was desktop-only AdminLTE.

### State-aware copy-to-clipboard
`NodeDetailModal.tsx:168-176` shows feedback (Copy → Check icon transition) on success. Legacy used `clipboard.js` with no UI feedback.

---

## Suggested next actions

1. ~~Schedule **C1** (cascading selects)~~ — ✅ Resolved in `CreateInstanceModal.tsx`.
2. ~~Schedule **H1** + **H2** as a small bundle of `NodeInstanceControls.tsx` enhancements~~ — ✅ Resolved.
3. Address the gaps surfaced in §Extended Audit below.

---

# Extended audit — remaining System view dirs

The original audit (above) covered `nodes/`, `node_instances/`, and `node_modules/`. This extension covers the rest of the `~/Drive/Projects/powernode-server/app/views/` directories that fall under System scope.

## Coverage matrix — providers + cloud catalog

| Legacy view dir | Resource | React surface | Status | Notes |
|---|---|---|---|---|
| `providers/` (6 files) | `Provider` | `ProvidersPage.tsx` + provider components | ✅ | Standard CRUD covered |
| `provider_connections/` (6 files) | `ProviderConnection` | `ProviderConnectionsPage` (exists) | 🔄 | **Missing: credential test button** in React detail modal — legacy had `test` action |
| `provider_regions/` (6 files) | `ProviderRegion` | Read-only via providers tab | 🔄 | No dedicated CRUD page in React; legacy allowed direct edit |
| `provider_availability_zones/` (6 files) | `ProviderAvailabilityZone` | Read-only via instance create cascade | 🔄 | OK — AZs are provider-defined, not user-managed |
| `provider_instance_types/` (6 files) | `ProviderInstanceType` | Read-only via instance create cascade | 🔄 | OK — instance types are catalog data |
| `provider_networks/` (6 files) | `ProviderNetwork` | `NetworksPage.tsx` | ✅ | |
| `provider_network_subnets/` (6 files) | `ProviderNetworkSubnet` | Read-only via instance create cascade | 🔄 | OK — auto-discovered |
| `provider_volumes/` (8 files) | `ProviderVolume` | `VolumesPage.tsx` | 🔄 | **Missing: `custom_mount_script` + `mount_script` selector** in volume form; **missing: RAID configuration** (legacy had `raid_level` from `RAID_LEVELS` enum, currently commented out in legacy too) |
| `provider_volume_types/` (6 files) | `ProviderVolumeType` | Read-only catalog | 🔄 | OK |

## Coverage matrix — node configuration

| Legacy view dir | Resource | React surface | Status | Notes |
|---|---|---|---|---|
| `node_architectures/` (6 files) | `NodeArchitecture` | `ArchitecturesPage.tsx` | ✅ | |
| `node_platforms/` (6 files) | `NodePlatform` | `PlatformsPage.tsx` | ✅ | |
| `node_templates/` (9 files) | `NodeTemplate` | `TemplatesPage.tsx` + `TemplateList`, `TemplateDetailModal`, `CreateTemplateModal` | 🔄 | **Missing: Template Export action** (legacy `export.html.haml` downloads template + selected modules — useful for backup/transfer); missing module-subscription cascade UI |
| `node_scripts/` (6 files) | `NodeScript` | `ScriptsPage.tsx` | ✅ | |
| `node_mount_points/` (6 files) | `NodeMountPoint` | Inside module detail / volume form | 🔄 | OK — composable into module/volume flows |
| `node_module_categories/` (6 files) | `NodeModuleCategory` | Read-only via module pages | 🔄 | OK — taxonomy |
| `node_module_copy_paths/` (6 files) | `NodeModuleCopyPath` | Inside module detail | 🔄 | Coverage incomplete; legacy let users add multiple copy_paths per module |

## Coverage matrix — puppet, operations, workers

| Legacy view dir | Resource | React surface | Status | Notes |
|---|---|---|---|---|
| `puppet_modules/` (7 files) | `PuppetModule` | `PuppetModulesPage.tsx` + `PuppetModuleList`, `PuppetModuleDetailModal`, `PuppetModuleFormModal` | 🔄 | **Missing: nested `PuppetResource` form** (legacy `_puppet_resource_fields.html.haml` had add/remove of resources per module, each with name/description/path/enabled/data; the `data` field used a codemirror text area for puppet manifest content) |
| `operations/` (3 files) | `Operation` | `OperationsPage.tsx` + Operations tab in `NodeDetailModal` | ✅ | React surface is richer than legacy (live progress via WebSocket vs. legacy's manual refresh) |
| `agents/` (6 files) | Legacy `Agent` → modern `Worker` | `WorkersPage.tsx` | ✅ | Schema migrated; SCrypt auth → JWT. Full coverage |

## Patterns worth preserving (extended)

### 1. `pages/_pages.html.haml` partial
Many legacy show-pages render a `pages/_pages` partial — this attaches CMS-style documentation pages to a resource (provider, template, etc.). Not currently in the React side. **Verdict:** defer; CMS attachment is a low-value ergonomic and can be added when an operator surfaces the need.

### 2. Search + sort on index pages
Legacy index pages (e.g., `nodes/index.html.haml`) use Ransack `search_form_for` + `sort_link` for keyword search and column sorting. React `NodeList.tsx` has filter chips but lacks free-text search across name+description. **Verdict:** medium priority; cheap to add via existing `apply_filters` controller path that already accepts `name` query.

### 3. Codemirror text area for structured data
Legacy puppet resource form uses `codemirror` for the `data` field (puppet manifest source). React puppet form uses a plain textarea. **Verdict:** medium priority; if puppet authoring becomes a real workflow, swap to a code editor like Monaco or CodeMirror 6.

### 4. Cascading select on volume create
Legacy `provider_volumes/_form` has region → volume_type cascade (similar to instance create). React `CreateVolumeModal.tsx` already has cascading region/zone, but verify volume_type updates after region change.

---

## Gaps worth porting (prioritized — extended)

### High priority

- **E-H1. Provider connection "Test credentials" button** — exists in legacy as a `test` action; missing in React's `ProviderConnections*` UI. Without it, operators have no in-UI way to verify a connection works before relying on it. Backend route already exists (`POST /api/v1/system/provider_connections/:id/test`); frontend just needs to wire a button + loading state + result toast.
- **E-H2. Template Export** — legacy `export.html.haml` lets the user download a node_template plus selected node_modules as a portable bundle. Useful for backups, environment promotion, and operator hand-offs. Backend route + serializer would be new; frontend gets a "Download" button on the template detail modal.
- **E-H3. Puppet nested PuppetResource form** — without this, puppet modules in React are display-only. To author puppet config in-platform, the user needs add/remove of resources, each with a code-editor for the manifest body.

### Medium priority

- **E-M1. Node list keyword search** (name + description Ransack-equivalent) — single text input that filters server-side via existing controller filter param.
- **E-M2. Volume `custom_mount_script` + selector** — currently the React volume form is missing the optional mount-script override field.
- **E-M3. Volume RAID configuration UI** — even legacy had this commented out; hold until a customer requests it.
- **E-M4. ProviderRegions CRUD page** — legacy let admins edit regions directly. Defer until catalog drift becomes a real problem.

### Low priority

- **E-L1. Resource-attached CMS pages** (provider/template/connection → pages). Defer; low operator value.
- **E-L2. Module copy_paths add/remove UI completeness** in module detail.
- **E-L3. Volume RAID member management** (raid0/raid1 selection of underlying volumes).

---

*Original audit generated 2026-04-29 (nodes/instances/modules); extended audit generated 2026-04-30 (providers/templates/puppet/volumes/operations/agents). Source diffs against `~/Drive/Projects/powernode-server/app/views/`.*

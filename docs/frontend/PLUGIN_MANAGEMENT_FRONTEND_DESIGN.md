# Plugin Management Frontend Design

**Status**: Design Phase
**Created**: 2025-01-14
**System**: Universal Plugin System - Frontend Integration

## Executive Summary

This document outlines the frontend architecture for managing the Universal Plugin System. The design integrates plugin marketplace browsing, installation management, and workflow/provider integration into the existing Powernode AI Orchestration interface.

**Core Principles**:
- **Unified Experience**: Plugin management integrated seamlessly with existing AI Providers and Workflows
- **Permission-Based**: All access control uses permissions, never roles
- **Theme-Aware**: Complete dark/light mode support using theme classes
- **Intuitive**: Follows established Powernode UI patterns (PageContainer, Modals, Cards)
- **Type-Safe**: Full TypeScript coverage with comprehensive interfaces
- **Mobile-First**: Responsive design from mobile to desktop

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Navigation Integration](#navigation-integration)
3. [Component Hierarchy](#component-hierarchy)
4. [User Workflows](#user-workflows)
5. [Data Flow](#data-flow)
6. [Integration Points](#integration-points)
7. [Permission Requirements](#permission-requirements)
8. [Implementation Phases](#implementation-phases)
9. [Code Examples](#code-examples)

---

## Architecture Overview

### System Context

```
┌─────────────────────────────────────────────────────────────────┐
│                    AI Orchestration Section                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │   Providers  │  │   Agents     │  │  Workflows   │          │
│  │   (Enhanced) │  │              │  │  (Enhanced)  │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              NEW: Plugin Marketplace                      │  │
│  │  - Browse Plugins   - Install/Uninstall                  │  │
│  │  - Marketplace Sync - Configuration                      │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Feature Map

**Marketplace Management** (`/app/ai/plugins/marketplace`):
- Browse available plugins across marketplaces
- Filter by type, category, verified status
- Search plugins by name, description, capabilities
- View detailed plugin information (manifest, reviews, stats)
- Sync marketplace catalogs

**Plugin Discovery** (`/app/ai/plugins`):
- Browse all available plugins
- View plugin details, ratings, and reviews
- Compare plugins side-by-side
- Install plugins with configuration

**Installation Management** (`/app/ai/plugins/installed`):
- View installed plugins by account
- Activate/deactivate installations
- Configure plugin settings
- Manage plugin credentials (secure)
- Update plugins to newer versions
- Uninstall plugins

**Provider Integration** (Enhanced `/app/ai/providers`):
- AI Provider plugins appear in provider list
- Special "Plugin" badge on plugin-based providers
- Quick install from provider creation modal
- Link to plugin marketplace from provider page

**Workflow Integration** (Enhanced `/app/ai/workflows`):
- Workflow node plugins appear in node palette
- Visual indicator for plugin-based nodes
- Plugin configuration within node editor
- Quick install from workflow builder

---

## Navigation Integration

### Primary Navigation Structure

Add to existing AI Orchestration navigation section:

```typescript
// In shared/utils/navigation.tsx - AI Orchestration section

{
  id: 'ai-orchestration',
  name: 'AI Orchestration',
  href: '/app/ai',
  icon: Brain,
  description: 'Manage AI providers, agents, workflows, and conversations',
  permissions: ['ai.providers.read', 'ai.agents.read', 'ai.workflows.read'],
  order: 4
}
```

### AI Section Sub-Routes

```typescript
// Routes for AI section in DashboardPage.tsx

<Route path="/app/ai" element={<AiOrchestrationLayout />}>
  {/* Existing Routes */}
  <Route index element={<Navigate to="/app/ai/dashboard" />} />
  <Route path="dashboard" element={<AiDashboardPage />} />
  <Route path="providers" element={<AiProvidersPage />} />
  <Route path="agents" element={<AgentsPage />} />
  <Route path="workflows" element={<WorkflowsPage />} />
  <Route path="workflows/:id" element={<WorkflowDetailPage />} />
  <Route path="conversations" element={<ConversationsPage />} />
  <Route path="monitoring" element={<MonitoringPage />} />
  <Route path="analytics" element={<AnalyticsPage />} />

  {/* NEW: Plugin Routes */}
  <Route path="plugins" element={<PluginsPage />} />
  <Route path="plugins/installed" element={<InstalledPluginsPage />} />
  <Route path="plugins/marketplace" element={<PluginMarketplacePage />} />
  <Route path="plugins/:id" element={<PluginDetailPage />} />
</Route>
```

### AI Dashboard Quick Actions

Add plugin quick actions to AI dashboard:

```typescript
// In AiDashboardPage.tsx quick actions

{
  id: 'browse-plugins',
  name: 'Browse Plugins',
  href: '/app/ai/plugins',
  icon: Package,
  description: 'Discover AI providers and workflow nodes',
  permissions: ['ai.plugins.browse']
}
```

---

## Component Hierarchy

### Page Components

#### 1. PluginsPage (Browse All Plugins)
**Path**: `frontend/src/features/ai-plugins/components/PluginsPage.tsx`

```
PluginsPage
├── PageContainer
│   ├── Summary Stats (Total, Installed, Available, Verified)
│   ├── Search & Filters
│   │   ├── SearchInput (name, description, capabilities)
│   │   ├── PluginTypeFilter (ai_provider, workflow_node, integration)
│   │   ├── StatusFilter (available, installed, deprecated)
│   │   └── VerifiedFilter (official, verified, community)
│   ├── Plugin Grid
│   │   └── PluginCard[] (image, name, author, type badges, ratings)
│   └── Pagination
└── Modals
    ├── PluginDetailModal (manifest, reviews, install)
    └── InstallPluginModal (configuration, credentials)
```

**Actions**:
- Browse Marketplace (link to marketplace page)
- Sync Marketplaces (admin only)
- Manage Installed (link to installed page)

#### 2. InstalledPluginsPage (Account Installations)
**Path**: `frontend/src/features/ai-plugins/components/InstalledPluginsPage.tsx`

```
InstalledPluginsPage
├── PageContainer
│   ├── Summary Stats (Total Installed, Active, Inactive, Updates Available)
│   ├── Filters
│   │   ├── StatusFilter (active, inactive, error, updating)
│   │   └── TypeFilter (ai_provider, workflow_node)
│   ├── Installation Grid
│   │   └── InstalledPluginCard[] (plugin info, status, config button)
│   └── Pagination
└── Modals
    ├── ConfigurePluginModal (configuration settings)
    ├── PluginCredentialsModal (secure credential input)
    └── UninstallConfirmModal
```

**Actions**:
- Browse Plugins (link to browse page)
- Refresh Status
- Activate All / Deactivate All (bulk operations)

#### 3. PluginMarketplacePage (Marketplace Management)
**Path**: `frontend/src/features/ai-plugins/components/PluginMarketplacePage.tsx`

```
PluginMarketplacePage
├── PageContainer
│   ├── Marketplace List
│   │   └── MarketplaceCard[] (name, type, plugin count, last sync)
│   └── Selected Marketplace Plugins
│       ├── MarketplaceInfo (description, source, stats)
│       ├── Plugin Grid
│       │   └── PluginCard[] (from selected marketplace)
│       └── Pagination
└── Modals
    ├── CreateMarketplaceModal (name, type, source)
    ├── SyncMarketplaceModal (sync progress)
    └── MarketplaceSettingsModal (configuration)
```

**Actions**:
- Create Marketplace (permission required)
- Sync All Marketplaces
- Manage Marketplace (edit, delete)

#### 4. PluginDetailPage (Full Plugin Details)
**Path**: `frontend/src/features/ai-plugins/components/PluginDetailPage.tsx`

```
PluginDetailPage
├── PageContainer
│   ├── Plugin Header
│   │   ├── Icon, Name, Author, Version
│   │   ├── Type Badges (ai_provider, workflow_node)
│   │   ├── Verification Badge (official, verified)
│   │   └── Install/Manage Button
│   ├── Tabs
│   │   ├── Overview (description, capabilities, screenshots)
│   │   ├── Manifest (JSON viewer with syntax highlight)
│   │   ├── Reviews (rating distribution, user reviews)
│   │   ├── Changelog (version history)
│   │   └── Stats (downloads, installs, ratings)
│   └── Sidebar
│       ├── Quick Info (license, homepage, source)
│       ├── Requirements (dependencies, compatibility)
│       └── Related Plugins
└── Modals
    ├── InstallPluginModal
    └── WriteReviewModal (if installed)
```

### Shared Components

#### PluginCard
**Path**: `frontend/src/features/ai-plugins/components/PluginCard.tsx`

```typescript
interface PluginCardProps {
  plugin: Plugin;
  showInstallButton?: boolean;
  showConfigButton?: boolean;
  onInstall?: (plugin: Plugin) => void;
  onConfigure?: (plugin: Plugin) => void;
  onViewDetails?: (plugin: Plugin) => void;
}
```

**Visual Design**:
```
┌─────────────────────────────────────────────┐
│ [Icon]  Plugin Name            [Verified ✓] │
│         by Author                           │
│                                             │
│ Brief description of what the plugin does  │
│ and its primary capabilities...            │
│                                             │
│ [AI Provider] [Workflow Node]  ⭐ 4.8 (24)  │
│                                             │
│ 1.2k installs • v2.1.0 • Updated 2 days ago│
│                                             │
│ [View Details]      [Install] or [Configure]│
└─────────────────────────────────────────────┘
```

#### InstalledPluginCard
**Path**: `frontend/src/features/ai-plugins/components/InstalledPluginCard.tsx`

```typescript
interface InstalledPluginCardProps {
  installation: PluginInstallation;
  onActivate?: () => void;
  onDeactivate?: () => void;
  onConfigure?: () => void;
  onUninstall?: () => void;
}
```

**Visual Design**:
```
┌─────────────────────────────────────────────┐
│ [Icon]  Plugin Name          [Status Badge] │
│         Installed 3 days ago                │
│                                             │
│ 127 executions • $2.43 total cost          │
│ Last used: 2 hours ago                      │
│                                             │
│ [Configure] [Deactivate] [•••]             │
└─────────────────────────────────────────────┘
```

#### InstallPluginModal
**Path**: `frontend/src/features/ai-plugins/components/InstallPluginModal.tsx`

```typescript
interface InstallPluginModalProps {
  plugin: Plugin;
  isOpen: boolean;
  onClose: () => void;
  onSuccess: (installation: PluginInstallation) => void;
}
```

**Steps**:
1. **Review**: Display plugin details, manifest, permissions
2. **Configure**: JSON editor for configuration based on manifest schema
3. **Credentials**: Secure input for authentication fields (if required)
4. **Confirm**: Review and install

#### ConfigurePluginModal
**Path**: `frontend/src/features/ai-plugins/components/ConfigurePluginModal.tsx`

```typescript
interface ConfigurePluginModalProps {
  installation: PluginInstallation;
  isOpen: boolean;
  onClose: () => void;
  onSuccess: () => void;
}
```

**Tabs**:
- **Configuration**: JSON editor with schema validation
- **Credentials**: Secure credential management
- **Activity**: Execution history and metrics
- **Danger Zone**: Deactivate, uninstall

#### PluginTypeBadge
**Path**: `frontend/src/features/ai-plugins/components/PluginTypeBadge.tsx`

```typescript
type PluginType = 'ai_provider' | 'workflow_node' | 'integration' | 'webhook' | 'tool';

const PluginTypeBadge: React.FC<{ type: PluginType }> = ({ type }) => {
  const config = {
    ai_provider: { label: 'AI Provider', icon: Brain, color: 'bg-theme-info' },
    workflow_node: { label: 'Workflow Node', icon: Zap, color: 'bg-theme-success' },
    integration: { label: 'Integration', icon: Link, color: 'bg-theme-warning' },
    webhook: { label: 'Webhook', icon: Webhook, color: 'bg-theme-purple' },
    tool: { label: 'Tool', icon: Wrench, color: 'bg-theme-orange' }
  };

  // Render badge with icon and theme-aware colors
};
```

---

## User Workflows

### Workflow 1: Install AI Provider Plugin

**User Story**: As a developer, I want to install an AI provider plugin so I can use a new LLM service.

**Steps**:
1. Navigate to **AI Orchestration → Plugins**
2. Filter by **Type: AI Provider**
3. Search for "Mistral AI" or browse verified providers
4. Click **PluginCard** to view details
5. Review manifest, capabilities, pricing info
6. Click **Install Plugin**
7. **InstallPluginModal** opens:
   - Step 1: Review permissions required
   - Step 2: Configure base URL, timeout settings
   - Step 3: Enter API key (secure input, encrypted storage)
   - Step 4: Confirm installation
8. System installs plugin and registers provider
9. Success notification: "Mistral AI Provider installed successfully"
10. Plugin appears in:
    - **Installed Plugins** page (active status)
    - **AI Providers** page (with "Plugin" badge)
    - **Agent configuration** dropdown (available for selection)

**Technical Flow**:
```typescript
// User clicks Install
const handleInstall = async () => {
  const installation = await pluginsApi.installPlugin(pluginId, {
    configuration: { api_base_url: 'https://api.mistral.ai' }
  });

  // Set credentials separately (encrypted)
  await pluginsApi.setInstallationCredential(installation.id, {
    credential_key: 'api_key',
    credential_value: apiKey
  });

  // Success notification
  addNotification({
    type: 'success',
    title: 'Plugin Installed',
    message: 'Mistral AI Provider is now available'
  });

  // Refresh providers list
  await providersApi.getProviders();
};
```

### Workflow 2: Install Workflow Node Plugin

**User Story**: As a workflow designer, I want to install a custom node plugin for data transformation.

**Steps**:
1. Navigate to **AI Orchestration → Workflows → Create/Edit Workflow**
2. Open **Node Palette**
3. Notice "Browse More Nodes" button at bottom
4. Click **Browse More Nodes** → redirects to `/app/ai/plugins?type=workflow_node`
5. Search for "JSON Transform" plugin
6. Click plugin to view details
7. Click **Install Plugin**
8. **InstallPluginModal** opens (minimal config for node plugins)
9. Confirm installation
10. Plugin installs and registers node type
11. **Workflow Builder** automatically updates node palette
12. New node type appears in appropriate category
13. User can now drag node into workflow canvas

**Technical Flow**:
```typescript
// In WorkflowBuilder.tsx - detect new node types
useEffect(() => {
  const loadAvailableNodes = async () => {
    const installedNodePlugins = await pluginsApi.getInstalledNodePlugins();

    // Merge with built-in nodes
    setAvailableNodes([
      ...builtInNodes,
      ...installedNodePlugins.map(plugin => ({
        type: plugin.manifest.workflow_nodes[0].node_type,
        category: plugin.manifest.workflow_nodes[0].category,
        label: plugin.name,
        icon: plugin.manifest.workflow_nodes[0].icon,
        isPlugin: true
      }))
    ]);
  };

  loadAvailableNodes();
}, []);
```

### Workflow 3: Manage Plugin Marketplace

**User Story**: As a platform admin, I want to create a private marketplace for my organization's plugins.

**Steps**:
1. Navigate to **AI Orchestration → Plugins → Marketplace**
2. Click **Create Marketplace**
3. **CreateMarketplaceModal** opens:
   - Name: "Acme Corp Plugins"
   - Owner: "acme-corp"
   - Type: **Private**
   - Visibility: **Team**
   - Source Type: **Git**
   - Source URL: "https://github.com/acme-corp/ai-plugins"
4. Click **Create**
5. System creates marketplace, attempts initial sync
6. **SyncMarketplaceModal** shows progress
7. Success: "Synced 12 plugins from Acme Corp Plugins"
8. Marketplace appears in list with plugin count
9. Click marketplace card to view plugins
10. Team members can now browse and install private plugins

**Permission Required**: `ai.plugins.marketplace.create`

### Workflow 4: Configure Installed Plugin

**User Story**: As a user, I want to update my plugin configuration to change timeout settings.

**Steps**:
1. Navigate to **AI Orchestration → Plugins → Installed**
2. Find plugin in installed list
3. Click **Configure** button on InstalledPluginCard
4. **ConfigurePluginModal** opens with tabs:
   - **Configuration**: JSON editor with current settings
   - **Credentials**: Secure credential management
   - **Activity**: Recent executions and metrics
5. Update configuration: `{ "timeout": 60, "max_retries": 5 }`
6. Click **Save Configuration**
7. System validates against manifest schema
8. Success notification: "Plugin configuration updated"
9. Plugin immediately uses new configuration

---

## Data Flow

### State Management Pattern

Follow existing AI Orchestration pattern:

```typescript
// features/ai-plugins/hooks/usePlugins.ts
export const usePlugins = () => {
  const [plugins, setPlugins] = useState<Plugin[]>([]);
  const [loading, setLoading] = useState(false);
  const [filters, setFilters] = useState<PluginFilters>({});

  const loadPlugins = useCallback(async () => {
    setLoading(true);
    try {
      const response = await pluginsApi.listPlugins(filters);
      setPlugins(response);
    } catch (error) {
      addNotification({ type: 'error', message: 'Failed to load plugins' });
    } finally {
      setLoading(false);
    }
  }, [filters]);

  return { plugins, loading, filters, setFilters, loadPlugins };
};
```

### API Service Integration

Already implemented in `frontend/src/shared/services/ai/PluginsApiService.ts`:

```typescript
// Available methods (20+ already implemented)
class PluginsApiService {
  // Marketplace Management
  async listMarketplaces(): Promise<PluginMarketplace[]>
  async createMarketplace(data: CreatePluginMarketplaceRequest): Promise<PluginMarketplace>
  async syncMarketplace(id: string): Promise<SyncResult>

  // Plugin Management
  async listPlugins(filters?: PluginFilters): Promise<Plugin[]>
  async getPlugin(id: string): Promise<{ plugin: Plugin; is_installed: boolean }>
  async installPlugin(id: string, config?: InstallPluginRequest): Promise<PluginInstallation>
  async uninstallPlugin(id: string): Promise<void>
  async searchPlugins(query: string): Promise<Plugin[]>

  // Installation Management
  async listInstallations(filters?: InstallationFilters): Promise<PluginInstallation[]>
  async activateInstallation(id: string): Promise<PluginInstallation>
  async deactivateInstallation(id: string): Promise<PluginInstallation>
  async configureInstallation(id: string, config: UpdatePluginConfigurationRequest): Promise<PluginInstallation>
  async setInstallationCredential(id: string, credential: SetPluginCredentialRequest): Promise<void>

  // Helper Methods
  async getInstalledProviderPlugins(): Promise<Plugin[]>
  async getInstalledNodePlugins(): Promise<Plugin[]>
}
```

### Real-Time Updates

Use existing WebSocket patterns for plugin status updates:

```typescript
// In PluginsPage.tsx
useEffect(() => {
  const ws = new WebSocket('/cable');

  ws.onmessage = (event) => {
    const data = JSON.parse(event.data);

    if (data.type === 'plugin_installation_status') {
      // Update installation status in real-time
      setPlugins(prev => prev.map(p =>
        p.id === data.plugin_id ? { ...p, installation: data.installation } : p
      ));
    }
  };

  return () => ws.close();
}, []);
```

---

## Integration Points

### 1. AI Providers Page Enhancement

**File**: `frontend/src/features/ai-providers/components/AiProvidersPage.tsx`

**Changes**:
```typescript
// Add plugin badge to provider cards
const ProviderCard = ({ provider }) => {
  const isPlugin = provider.configuration?.is_plugin;

  return (
    <Card>
      <div className="flex items-center gap-2">
        <h3>{provider.name}</h3>
        {isPlugin && (
          <Badge variant="info" size="sm">
            <Package className="h-3 w-3 mr-1" />
            Plugin
          </Badge>
        )}
      </div>
      {/* Rest of card content */}
    </Card>
  );
};

// Add "Browse Plugins" action
const pageActions = (
  <>
    <Button variant="outline" onClick={() => navigate('/app/ai/plugins?type=ai_provider')}>
      <Package className="h-4 w-4 mr-2" />
      Browse Plugins
    </Button>
    {/* Existing actions */}
  </>
);
```

**Quick Install from Provider Modal**:
```typescript
// In CreateProviderModal.tsx
<div className="border-t border-theme pt-4">
  <p className="text-sm text-theme-secondary mb-2">
    Or install a provider plugin:
  </p>
  <Button
    variant="outline"
    onClick={() => navigate('/app/ai/plugins?type=ai_provider')}
    className="w-full"
  >
    Browse Provider Plugins
  </Button>
</div>
```

### 2. Workflow Builder Enhancement

**File**: `frontend/src/shared/components/workflow/WorkflowBuilder.tsx`

**Changes**:
```typescript
// Enhanced node palette with plugin nodes
const NodePalette = () => {
  const [builtInNodes, setBuiltInNodes] = useState([]);
  const [pluginNodes, setPluginNodes] = useState([]);

  useEffect(() => {
    const loadNodes = async () => {
      const installedNodePlugins = await pluginsApi.getInstalledNodePlugins();

      const pluginNodeTypes = installedNodePlugins.flatMap(plugin =>
        plugin.manifest.workflow_nodes.map(nodeConfig => ({
          type: nodeConfig.node_type,
          category: nodeConfig.category,
          label: plugin.name,
          icon: nodeConfig.icon,
          color: nodeConfig.color,
          isPlugin: true,
          pluginId: plugin.id
        }))
      );

      setPluginNodes(pluginNodeTypes);
    };

    loadNodes();
  }, []);

  return (
    <div className="node-palette">
      {/* Built-in nodes */}
      <NodeCategory title="Data" nodes={builtInNodes.filter(n => n.category === 'data')} />
      <NodeCategory title="Logic" nodes={builtInNodes.filter(n => n.category === 'logic')} />
      <NodeCategory title="AI" nodes={builtInNodes.filter(n => n.category === 'ai')} />

      {/* Plugin nodes */}
      {pluginNodes.length > 0 && (
        <NodeCategory
          title="Plugin Nodes"
          nodes={pluginNodes}
          icon={<Package className="h-4 w-4" />}
        />
      )}

      {/* Browse more plugins */}
      <Button
        variant="ghost"
        size="sm"
        onClick={() => navigate('/app/ai/plugins?type=workflow_node')}
        className="w-full mt-2"
      >
        <Plus className="h-4 w-4 mr-2" />
        Browse More Nodes
      </Button>
    </div>
  );
};

// Plugin node rendering with special styling
const renderNode = (node) => {
  if (node.data.isPlugin) {
    return (
      <div className="workflow-node plugin-node border-2 border-dashed border-theme-info">
        <div className="flex items-center gap-2">
          <Package className="h-4 w-4 text-theme-info" />
          <span>{node.data.label}</span>
        </div>
        {/* Node content */}
      </div>
    );
  }

  // Regular node rendering
};
```

### 3. Agent Configuration Enhancement

**File**: `frontend/src/features/ai-agents/components/AgentConfigurationForm.tsx`

**Changes**:
```typescript
// Provider dropdown includes plugin providers
const ProviderSelect = ({ value, onChange }) => {
  const [providers, setProviders] = useState([]);

  useEffect(() => {
    const loadProviders = async () => {
      const allProviders = await providersApi.getProviders();

      // Group by plugin vs built-in
      const grouped = {
        'Built-in Providers': allProviders.filter(p => !p.configuration?.is_plugin),
        'Plugin Providers': allProviders.filter(p => p.configuration?.is_plugin)
      };

      setProviders(grouped);
    };

    loadProviders();
  }, []);

  return (
    <Select value={value} onChange={onChange}>
      {Object.entries(providers).map(([group, items]) => (
        <optgroup key={group} label={group}>
          {items.map(provider => (
            <option key={provider.id} value={provider.id}>
              {provider.name}
              {provider.configuration?.is_plugin && ' [Plugin]'}
            </option>
          ))}
        </optgroup>
      ))}

      <option disabled>─────────────</option>
      <option value="__browse_plugins__">📦 Browse Provider Plugins...</option>
    </Select>
  );
};
```

---

## Permission Requirements

Following Powernode's **permission-based access control** (never role-based):

### Plugin Permissions

```typescript
// Backend: server/config/permissions.rb additions

plugin_permissions = {
  # Browse and view plugins
  'ai.plugins.browse' => 'Browse available plugins in marketplace',
  'ai.plugins.read' => 'View plugin details and manifests',

  # Install and manage plugins
  'ai.plugins.install' => 'Install plugins to account',
  'ai.plugins.configure' => 'Configure installed plugins',
  'ai.plugins.uninstall' => 'Uninstall plugins from account',

  # Marketplace management
  'ai.plugins.marketplace.create' => 'Create plugin marketplaces',
  'ai.plugins.marketplace.sync' => 'Sync marketplace catalogs',
  'ai.plugins.marketplace.manage' => 'Manage marketplace settings',

  # Plugin development/publishing
  'ai.plugins.create' => 'Create and register new plugins',
  'ai.plugins.publish' => 'Publish plugins to marketplace',
  'ai.plugins.review' => 'Review and rate plugins',

  # Admin permissions
  'ai.plugins.admin' => 'Full plugin system administration'
}
```

### Frontend Permission Checks

```typescript
// In component usage
const { hasPermission } = usePermissions();

const canBrowsePlugins = hasPermission('ai.plugins.browse');
const canInstallPlugins = hasPermission('ai.plugins.install');
const canManageMarketplace = hasPermission('ai.plugins.marketplace.create');

// Navigation visibility
{
  id: 'plugins',
  name: 'Plugins',
  href: '/app/ai/plugins',
  icon: Package,
  permissions: ['ai.plugins.browse', 'ai.plugins.read'],
  order: 7
}

// Action button visibility
{canInstallPlugins && (
  <Button onClick={handleInstall}>
    Install Plugin
  </Button>
)}

// Admin-only marketplace features
{canManageMarketplace && (
  <Button onClick={() => setShowCreateMarketplace(true)}>
    Create Marketplace
  </Button>
)}
```

---

## Implementation Phases

### Phase 1: Core Plugin Pages (Week 1)
**Goal**: Basic plugin browsing and viewing

**Deliverables**:
- ✅ TypeScript types (already complete)
- ✅ API service (already complete)
- ⬜ PluginsPage component (browse all plugins)
- ⬜ PluginCard component (visual plugin representation)
- ⬜ PluginDetailModal component (full plugin details)
- ⬜ Basic navigation integration
- ⬜ Permission-based access control

**Estimated Effort**: 2-3 days

### Phase 2: Installation Management (Week 1-2)
**Goal**: Install, configure, and manage plugins

**Deliverables**:
- ⬜ InstallPluginModal (multi-step installation)
- ⬜ InstalledPluginsPage (view installations)
- ⬜ InstalledPluginCard component
- ⬜ ConfigurePluginModal (settings and credentials)
- ⬜ Activate/deactivate functionality
- ⬜ Uninstall with confirmation

**Estimated Effort**: 3-4 days

### Phase 3: Marketplace Management (Week 2)
**Goal**: Marketplace creation, sync, and browsing

**Deliverables**:
- ⬜ PluginMarketplacePage (marketplace list and plugins)
- ⬜ MarketplaceCard component
- ⬜ CreateMarketplaceModal
- ⬜ SyncMarketplaceModal with progress
- ⬜ Marketplace filtering and search

**Estimated Effort**: 2-3 days

### Phase 4: Provider Integration (Week 2-3)
**Goal**: Seamless provider plugin integration

**Deliverables**:
- ⬜ Plugin badge on AiProviderCard
- ⬜ "Browse Plugins" link in AiProvidersPage
- ⬜ Quick install from CreateProviderModal
- ⬜ Plugin provider filtering
- ⬜ Real-time provider registry updates

**Estimated Effort**: 2 days

### Phase 5: Workflow Integration (Week 3)
**Goal**: Workflow node plugin integration

**Deliverables**:
- ⬜ Enhanced node palette with plugin nodes
- ⬜ Plugin node visual styling (dashed border)
- ⬜ "Browse More Nodes" button
- ⬜ Quick install from workflow builder
- ⬜ Dynamic node type registration
- ⬜ Plugin node execution integration

**Estimated Effort**: 3-4 days

### Phase 6: Advanced Features (Week 3-4)
**Goal**: Polish and advanced functionality

**Deliverables**:
- ⬜ Plugin reviews and ratings system
- ⬜ Plugin comparison tool
- ⬜ Update notifications for installed plugins
- ⬜ Plugin usage analytics dashboard
- ⬜ Bulk operations (activate all, update all)
- ⬜ Plugin dependency visualization
- ⬜ WebSocket real-time updates

**Estimated Effort**: 4-5 days

### Total Timeline: 3-4 weeks

---

## Code Examples

### Example 1: PluginsPage Component Structure

```typescript
// frontend/src/features/ai-plugins/components/PluginsPage.tsx

import React, { useState, useEffect, useCallback } from 'react';
import { Package, Search, Filter, RefreshCw } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Card } from '@/shared/components/ui/Card';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { pluginsApi } from '@/shared/services/ai';
import type { Plugin } from '@/shared/types/plugin';
import { PluginCard } from './PluginCard';
import { PluginFilters } from './PluginFilters';
import { PluginDetailModal } from './PluginDetailModal';
import { InstallPluginModal } from './InstallPluginModal';

export const PluginsPage: React.FC = () => {
  const [plugins, setPlugins] = useState<Plugin[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [showFilters, setShowFilters] = useState(false);
  const [selectedPluginId, setSelectedPluginId] = useState<string | null>(null);
  const [installingPluginId, setInstallingPluginId] = useState<string | null>(null);
  const [filters, setFilters] = useState({
    type: undefined,
    status: 'available',
    verified: undefined
  });

  const { addNotification } = useNotifications();
  const { hasPermission } = usePermissions();

  const canBrowsePlugins = hasPermission('ai.plugins.browse');
  const canInstallPlugins = hasPermission('ai.plugins.install');

  const loadPlugins = useCallback(async () => {
    if (!canBrowsePlugins) return;

    try {
      setLoading(true);
      const response = await pluginsApi.listPlugins({
        ...filters,
        search: searchQuery || undefined
      });
      setPlugins(response);
    } catch (error) {
      console.error('Failed to load plugins:', error);
      addNotification({
        type: 'error',
        title: 'Error',
        message: 'Failed to load plugins. Please try again.'
      });
    } finally {
      setLoading(false);
    }
  }, [filters, searchQuery, canBrowsePlugins, addNotification]);

  useEffect(() => {
    loadPlugins();
  }, [loadPlugins]);

  const handleSearch = useCallback((query: string) => {
    setSearchQuery(query);
  }, []);

  const handleFilterChange = useCallback((newFilters: any) => {
    setFilters(prev => ({ ...prev, ...newFilters }));
  }, []);

  const handleViewDetails = useCallback((pluginId: string) => {
    setSelectedPluginId(pluginId);
  }, []);

  const handleInstall = useCallback((pluginId: string) => {
    if (!canInstallPlugins) {
      addNotification({
        type: 'error',
        title: 'Permission Denied',
        message: 'You do not have permission to install plugins'
      });
      return;
    }
    setInstallingPluginId(pluginId);
  }, [canInstallPlugins, addNotification]);

  const handleInstallSuccess = useCallback(() => {
    loadPlugins(); // Refresh list
    setInstallingPluginId(null);
    addNotification({
      type: 'success',
      title: 'Plugin Installed',
      message: 'Plugin has been installed successfully'
    });
  }, [loadPlugins, addNotification]);

  const pageActions = (
    <div className="flex items-center gap-2">
      <Button
        variant="outline"
        size="sm"
        onClick={loadPlugins}
        className="flex items-center gap-1"
      >
        <RefreshCw className="h-4 w-4" />
        Refresh
      </Button>

      <Button
        variant="outline"
        size="sm"
        onClick={() => navigate('/app/ai/plugins/marketplace')}
        className="flex items-center gap-1"
      >
        <Package className="h-4 w-4" />
        Marketplaces
      </Button>

      <Button
        onClick={() => navigate('/app/ai/plugins/installed')}
        className="flex items-center gap-1"
      >
        <Package className="h-4 w-4" />
        Installed Plugins
      </Button>
    </div>
  );

  if (!canBrowsePlugins) {
    return (
      <PageContainer title="Plugins">
        <EmptyState
          icon={Package}
          title="Permission Required"
          description="You don't have permission to browse plugins"
        />
      </PageContainer>
    );
  }

  if (loading) {
    return (
      <PageContainer
        title="AI Plugins"
        description="Browse and install AI providers, workflow nodes, and integrations"
      >
        <LoadingSpinner className="py-12" />
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title="AI Plugins"
      description="Browse and install AI providers, workflow nodes, and integrations"
      actions={pageActions}
    >
      {/* Summary Stats */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
        <Card className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-theme-tertiary">Total Plugins</p>
              <p className="text-2xl font-semibold text-theme-primary">{plugins.length}</p>
            </div>
            <Package className="h-10 w-10 text-theme-info opacity-50" />
          </div>
        </Card>

        <Card className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-theme-tertiary">AI Providers</p>
              <p className="text-2xl font-semibold text-theme-primary">
                {plugins.filter(p => p.plugin_types.includes('ai_provider')).length}
              </p>
            </div>
            <Brain className="h-10 w-10 text-theme-success opacity-50" />
          </div>
        </Card>

        <Card className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-theme-tertiary">Workflow Nodes</p>
              <p className="text-2xl font-semibold text-theme-primary">
                {plugins.filter(p => p.plugin_types.includes('workflow_node')).length}
              </p>
            </div>
            <Zap className="h-10 w-10 text-theme-warning opacity-50" />
          </div>
        </Card>

        <Card className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-theme-tertiary">Verified</p>
              <p className="text-2xl font-semibold text-theme-primary">
                {plugins.filter(p => p.is_verified).length}
              </p>
            </div>
            <CheckCircle className="h-10 w-10 text-theme-info opacity-50" />
          </div>
        </Card>
      </div>

      {/* Search and Filters */}
      <div className="mb-6">
        <div className="flex items-center gap-4 mb-4">
          <div className="flex-1 relative">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-theme-tertiary" />
            <Input
              placeholder="Search plugins by name, description, or capabilities..."
              value={searchQuery}
              onChange={(e) => handleSearch(e.target.value)}
              className="pl-10"
            />
          </div>

          <Button
            variant="outline"
            onClick={() => setShowFilters(!showFilters)}
            className="flex items-center gap-2"
          >
            <Filter className="h-4 w-4" />
            Filters
          </Button>
        </div>

        {showFilters && (
          <PluginFilters
            filters={filters}
            onFiltersChange={handleFilterChange}
          />
        )}
      </div>

      {/* Plugins Grid */}
      {plugins.length === 0 ? (
        <EmptyState
          icon={Package}
          title="No plugins found"
          description="Try adjusting your search or filters"
          action={
            <Button onClick={() => { setSearchQuery(''); setFilters({}); }}>
              Clear Filters
            </Button>
          }
        />
      ) : (
        <div className="grid grid-cols-1 lg:grid-cols-2 xl:grid-cols-3 gap-6">
          {plugins.map((plugin) => (
            <PluginCard
              key={plugin.id}
              plugin={plugin}
              showInstallButton={canInstallPlugins}
              onViewDetails={handleViewDetails}
              onInstall={handleInstall}
            />
          ))}
        </div>
      )}

      {/* Modals */}
      {selectedPluginId && (
        <PluginDetailModal
          pluginId={selectedPluginId}
          isOpen={!!selectedPluginId}
          onClose={() => setSelectedPluginId(null)}
          onInstall={handleInstall}
        />
      )}

      {installingPluginId && (
        <InstallPluginModal
          pluginId={installingPluginId}
          isOpen={!!installingPluginId}
          onClose={() => setInstallingPluginId(null)}
          onSuccess={handleInstallSuccess}
        />
      )}
    </PageContainer>
  );
};
```

### Example 2: PluginCard Component

```typescript
// frontend/src/features/ai-plugins/components/PluginCard.tsx

import React from 'react';
import { Package, ExternalLink, Download, Settings, CheckCircle, Star } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import type { Plugin } from '@/shared/types/plugin';
import { PluginTypeBadge } from './PluginTypeBadge';

interface PluginCardProps {
  plugin: Plugin;
  showInstallButton?: boolean;
  showConfigButton?: boolean;
  onInstall?: (pluginId: string) => void;
  onConfigure?: (pluginId: string) => void;
  onViewDetails?: (pluginId: string) => void;
}

export const PluginCard: React.FC<PluginCardProps> = ({
  plugin,
  showInstallButton = false,
  showConfigButton = false,
  onInstall,
  onConfigure,
  onViewDetails
}) => {
  const isInstalled = plugin.status === 'installed';
  const isOfficial = plugin.is_official;
  const isVerified = plugin.is_verified;

  return (
    <Card className="p-6 hover:border-theme-info transition-colors cursor-pointer">
      <div className="flex items-start gap-4 mb-4">
        {/* Plugin Icon */}
        <div className="h-12 w-12 bg-theme-surface-elevated rounded-lg flex items-center justify-center flex-shrink-0">
          {plugin.manifest.plugin?.icon ? (
            <img
              src={plugin.manifest.plugin.icon}
              alt={plugin.name}
              className="h-8 w-8"
            />
          ) : (
            <Package className="h-8 w-8 text-theme-info" />
          )}
        </div>

        {/* Plugin Header */}
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1">
            <h3 className="text-lg font-semibold text-theme-primary truncate">
              {plugin.name}
            </h3>
            {isOfficial && (
              <Badge variant="info" size="sm" className="flex-shrink-0">
                <CheckCircle className="h-3 w-3 mr-1" />
                Official
              </Badge>
            )}
            {isVerified && !isOfficial && (
              <Badge variant="success" size="sm" className="flex-shrink-0">
                <CheckCircle className="h-3 w-3 mr-1" />
                Verified
              </Badge>
            )}
          </div>

          <p className="text-sm text-theme-tertiary">
            by {plugin.author}
          </p>
        </div>
      </div>

      {/* Description */}
      <p className="text-sm text-theme-secondary mb-4 line-clamp-2">
        {plugin.description}
      </p>

      {/* Plugin Types */}
      <div className="flex flex-wrap gap-2 mb-4">
        {plugin.plugin_types.map(type => (
          <PluginTypeBadge key={type} type={type} />
        ))}
      </div>

      {/* Ratings and Stats */}
      <div className="flex items-center gap-4 text-sm text-theme-tertiary mb-4">
        {plugin.average_rating && (
          <div className="flex items-center gap-1">
            <Star className="h-4 w-4 text-yellow-500 fill-yellow-500" />
            <span>{plugin.average_rating.toFixed(1)}</span>
            <span>({plugin.rating_count})</span>
          </div>
        )}

        <div className="flex items-center gap-1">
          <Download className="h-4 w-4" />
          <span>{plugin.install_count.toLocaleString()} installs</span>
        </div>
      </div>

      {/* Meta Information */}
      <div className="text-xs text-theme-tertiary mb-4 flex items-center justify-between">
        <span>v{plugin.version}</span>
        <span>Updated {new Date(plugin.updated_at).toLocaleDateString()}</span>
      </div>

      {/* Actions */}
      <div className="flex items-center gap-2">
        <Button
          variant="outline"
          size="sm"
          onClick={() => onViewDetails?.(plugin.id)}
          className="flex-1"
        >
          <ExternalLink className="h-4 w-4 mr-2" />
          Details
        </Button>

        {showConfigButton && isInstalled && (
          <Button
            variant="default"
            size="sm"
            onClick={() => onConfigure?.(plugin.id)}
            className="flex-1"
          >
            <Settings className="h-4 w-4 mr-2" />
            Configure
          </Button>
        )}

        {showInstallButton && !isInstalled && (
          <Button
            variant="default"
            size="sm"
            onClick={() => onInstall?.(plugin.id)}
            className="flex-1"
          >
            <Package className="h-4 w-4 mr-2" />
            Install
          </Button>
        )}

        {isInstalled && !showConfigButton && (
          <Badge variant="success" size="sm" className="flex-1 justify-center">
            <CheckCircle className="h-3 w-3 mr-1" />
            Installed
          </Badge>
        )}
      </div>
    </Card>
  );
};
```

### Example 3: InstallPluginModal

```typescript
// frontend/src/features/ai-plugins/components/InstallPluginModal.tsx

import React, { useState, useEffect } from 'react';
import { X, AlertCircle, CheckCircle, Package } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { pluginsApi } from '@/shared/services/ai';
import type { Plugin, PluginInstallation } from '@/shared/types/plugin';

interface InstallPluginModalProps {
  pluginId: string;
  isOpen: boolean;
  onClose: () => void;
  onSuccess: (installation: PluginInstallation) => void;
}

type InstallStep = 'review' | 'configure' | 'credentials' | 'installing' | 'success';

export const InstallPluginModal: React.FC<InstallPluginModalProps> = ({
  pluginId,
  isOpen,
  onClose,
  onSuccess
}) => {
  const [currentStep, setCurrentStep] = useState<InstallStep>('review');
  const [plugin, setPlugin] = useState<Plugin | null>(null);
  const [loading, setLoading] = useState(true);
  const [configuration, setConfiguration] = useState<Record<string, any>>({});
  const [credentials, setCredentials] = useState<Record<string, string>>({});
  const { addNotification } = useNotifications();

  useEffect(() => {
    const loadPlugin = async () => {
      try {
        setLoading(true);
        const response = await pluginsApi.getPlugin(pluginId);
        setPlugin(response.plugin);

        // Initialize default configuration
        const defaultConfig = {};
        // Parse manifest for default values
        setConfiguration(defaultConfig);
      } catch (error) {
        console.error('Failed to load plugin:', error);
        addNotification({
          type: 'error',
          title: 'Error',
          message: 'Failed to load plugin details'
        });
        onClose();
      } finally {
        setLoading(false);
      }
    };

    if (isOpen && pluginId) {
      loadPlugin();
    }
  }, [isOpen, pluginId, addNotification, onClose]);

  const handleInstall = async () => {
    if (!plugin) return;

    try {
      setCurrentStep('installing');

      // Install plugin with configuration
      const installation = await pluginsApi.installPlugin(plugin.id, {
        configuration
      });

      // Set credentials if provided
      for (const [key, value] of Object.entries(credentials)) {
        if (value) {
          await pluginsApi.setInstallationCredential(installation.id, {
            credential_key: key,
            credential_value: value
          });
        }
      }

      setCurrentStep('success');

      setTimeout(() => {
        onSuccess(installation);
        onClose();
      }, 2000);

    } catch (error) {
      console.error('Failed to install plugin:', error);
      addNotification({
        type: 'error',
        title: 'Installation Failed',
        message: 'Failed to install plugin. Please try again.'
      });
      setCurrentStep('review');
    }
  };

  const renderStep = () => {
    switch (currentStep) {
      case 'review':
        return (
          <div className="space-y-6">
            <div>
              <h3 className="text-lg font-semibold text-theme-primary mb-2">
                Review Plugin Details
              </h3>
              <p className="text-sm text-theme-secondary">
                Please review the plugin information before installing.
              </p>
            </div>

            {plugin && (
              <>
                <div className="bg-theme-surface-elevated rounded-lg p-4">
                  <div className="flex items-center gap-4 mb-4">
                    <Package className="h-10 w-10 text-theme-info" />
                    <div>
                      <h4 className="font-semibold text-theme-primary">{plugin.name}</h4>
                      <p className="text-sm text-theme-tertiary">
                        Version {plugin.version} by {plugin.author}
                      </p>
                    </div>
                  </div>

                  <p className="text-sm text-theme-secondary mb-4">
                    {plugin.description}
                  </p>

                  <div className="flex flex-wrap gap-2">
                    {plugin.plugin_types.map(type => (
                      <Badge key={type} variant="outline" size="sm">
                        {type.replace('_', ' ')}
                      </Badge>
                    ))}
                  </div>
                </div>

                {plugin.manifest.permissions && plugin.manifest.permissions.length > 0 && (
                  <div className="bg-yellow-50 dark:bg-yellow-900/20 rounded-lg p-4">
                    <div className="flex items-start gap-3">
                      <AlertCircle className="h-5 w-5 text-yellow-600 flex-shrink-0 mt-0.5" />
                      <div>
                        <h4 className="font-semibold text-yellow-900 dark:text-yellow-200 mb-2">
                          Required Permissions
                        </h4>
                        <ul className="text-sm text-yellow-800 dark:text-yellow-300 space-y-1">
                          {plugin.manifest.permissions.map(permission => (
                            <li key={permission}>• {permission}</li>
                          ))}
                        </ul>
                      </div>
                    </div>
                  </div>
                )}
              </>
            )}

            <div className="flex justify-end gap-3">
              <Button variant="outline" onClick={onClose}>
                Cancel
              </Button>
              <Button onClick={() => setCurrentStep('configure')}>
                Next: Configuration
              </Button>
            </div>
          </div>
        );

      case 'configure':
        return (
          <div className="space-y-6">
            <div>
              <h3 className="text-lg font-semibold text-theme-primary mb-2">
                Configure Plugin
              </h3>
              <p className="text-sm text-theme-secondary">
                Customize plugin settings for your environment.
              </p>
            </div>

            <div className="space-y-4">
              {/* Configuration fields based on manifest schema */}
              {plugin?.manifest.ai_provider && (
                <>
                  <div>
                    <label className="block text-sm font-medium text-theme-secondary mb-1">
                      API Base URL
                    </label>
                    <Input
                      value={configuration.api_base_url || ''}
                      onChange={(e) => setConfiguration(prev => ({
                        ...prev,
                        api_base_url: e.target.value
                      }))}
                      placeholder="https://api.provider.com/v1"
                    />
                  </div>

                  <div>
                    <label className="block text-sm font-medium text-theme-secondary mb-1">
                      Timeout (seconds)
                    </label>
                    <Input
                      type="number"
                      value={configuration.timeout || 30}
                      onChange={(e) => setConfiguration(prev => ({
                        ...prev,
                        timeout: parseInt(e.target.value)
                      }))}
                    />
                  </div>
                </>
              )}
            </div>

            <div className="flex justify-between">
              <Button variant="outline" onClick={() => setCurrentStep('review')}>
                Back
              </Button>
              <div className="flex gap-3">
                <Button variant="outline" onClick={onClose}>
                  Cancel
                </Button>
                <Button onClick={() => setCurrentStep('credentials')}>
                  Next: Credentials
                </Button>
              </div>
            </div>
          </div>
        );

      case 'credentials':
        return (
          <div className="space-y-6">
            <div>
              <h3 className="text-lg font-semibold text-theme-primary mb-2">
                Set Credentials
              </h3>
              <p className="text-sm text-theme-secondary">
                Provide authentication credentials for the plugin.
              </p>
            </div>

            <div className="space-y-4">
              {plugin?.manifest.ai_provider?.authentication.fields.map(field => (
                <div key={field.name}>
                  <label className="block text-sm font-medium text-theme-secondary mb-1">
                    {field.label} {field.required && <span className="text-red-500">*</span>}
                  </label>
                  <Input
                    type={field.type === 'secret' ? 'password' : 'text'}
                    value={credentials[field.name] || ''}
                    onChange={(e) => setCredentials(prev => ({
                      ...prev,
                      [field.name]: e.target.value
                    }))}
                    placeholder={field.default}
                    required={field.required}
                  />
                </div>
              ))}
            </div>

            <div className="flex justify-between">
              <Button variant="outline" onClick={() => setCurrentStep('configure')}>
                Back
              </Button>
              <div className="flex gap-3">
                <Button variant="outline" onClick={onClose}>
                  Cancel
                </Button>
                <Button onClick={handleInstall}>
                  Install Plugin
                </Button>
              </div>
            </div>
          </div>
        );

      case 'installing':
        return (
          <div className="py-12 text-center">
            <LoadingSpinner />
            <p className="text-theme-secondary mt-4">Installing plugin...</p>
          </div>
        );

      case 'success':
        return (
          <div className="py-12 text-center">
            <div className="inline-flex items-center justify-center w-16 h-16 bg-green-100 dark:bg-green-900/30 rounded-full mb-4">
              <CheckCircle className="h-8 w-8 text-green-600" />
            </div>
            <h3 className="text-lg font-semibold text-theme-primary mb-2">
              Plugin Installed Successfully
            </h3>
            <p className="text-sm text-theme-secondary">
              {plugin?.name} is now available for use.
            </p>
          </div>
        );

      default:
        return null;
    }
  };

  if (loading) {
    return (
      <Modal isOpen={isOpen} onClose={onClose} size="lg">
        <div className="p-6">
          <LoadingSpinner />
        </div>
      </Modal>
    );
  }

  return (
    <Modal isOpen={isOpen} onClose={onClose} size="lg">
      <div className="flex items-center justify-between p-6 border-b border-theme">
        <h2 className="text-xl font-semibold text-theme-primary">Install Plugin</h2>
        <Button
          variant="ghost"
          size="sm"
          onClick={onClose}
          className="h-8 w-8 p-0"
        >
          <X className="h-4 w-4" />
        </Button>
      </div>

      <div className="p-6">
        {renderStep()}
      </div>
    </Modal>
  );
};
```

---

## Summary

This design provides a comprehensive roadmap for integrating plugin management into the Powernode AI Orchestration frontend. The architecture follows established patterns, maintains permission-based security, and provides intuitive user workflows.

**Key Highlights**:
- **Unified Experience**: Plugins integrate seamlessly with existing providers and workflows
- **Type-Safe**: Full TypeScript coverage using existing type definitions
- **Permission-Based**: MANDATORY permission checks, never role-based
- **Theme-Aware**: Complete dark/light mode support
- **Phased Implementation**: 3-4 week timeline with clear deliverables
- **Backend Ready**: API service and types already implemented

**Next Steps**:
1. Review this design document
2. Approve implementation phases
3. Begin Phase 1: Core Plugin Pages
4. Iterate based on user feedback

---

**Document Version**: 1.0
**Last Updated**: 2025-01-14
**Status**: Ready for Implementation

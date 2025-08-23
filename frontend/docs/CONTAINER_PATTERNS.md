# Container Component Patterns
## PageContainer vs TabContainer Usage Guide

---

## 📦 Component Hierarchy

```
PageContainer (Top Level - One per page)
├── Page Header (title, breadcrumbs, actions)
├── Page Description (optional)
└── Page Content
    └── TabContainer (When tabs are needed)
        ├── Tab Navigation
        └── Tab Panels
```

---

## 🎯 PageContainer

**Purpose**: Provides consistent page-level structure including header, breadcrumbs, and consolidated actions.

**When to Use**: 
- Every routable page component
- Top-level layout for any screen
- When you need breadcrumbs and page actions

**Key Features**:
- Page title and description
- Breadcrumb navigation
- Consolidated action buttons
- Consistent padding and layout
- Permission-based action visibility

### PageContainer Example

```tsx
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { Plus, RefreshCw, Download } from 'lucide-react';

export const UsersPage: React.FC = () => {
  const getPageActions = (): PageAction[] => [
    {
      id: 'create',
      label: 'Create User',
      onClick: handleCreate,
      variant: 'primary',
      icon: Plus,
      permission: 'users.create'
    },
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: handleRefresh,
      variant: 'secondary',
      icon: RefreshCw
    },
    {
      id: 'export',
      label: 'Export',
      onClick: handleExport,
      variant: 'outline',
      icon: Download
    }
  ];

  const getBreadcrumbs = () => [
    { label: 'Dashboard', href: '/dashboard', icon: '🏠' },
    { label: 'Users', icon: '👥' }
  ];

  return (
    <PageContainer
      title="User Management"
      description="Manage system users and their permissions"
      breadcrumbs={getBreadcrumbs()}
      actions={getPageActions()}
    >
      {/* Page content goes here */}
    </PageContainer>
  );
};
```

---

## 📑 TabContainer

**Purpose**: Manages tabbed navigation within a page or section.

**When to Use**:
- Multiple related views within a single page
- Settings pages with categories
- Multi-step forms or wizards
- Data views with different perspectives

**Key Features**:
- Multiple tab variants (underline, pills, default)
- URL-based tab routing support
- Badge support for counts/status
- Responsive overflow handling
- Permission-based tab visibility

### TabContainer Example

```tsx
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { Users, Settings, Shield, Activity } from 'lucide-react';

export const AccountPage: React.FC = () => {
  const [activeTab, setActiveTab] = useState('users');

  const tabs = [
    { 
      id: 'users', 
      label: 'Users', 
      icon: <Users className="w-4 h-4" />,
      path: '/users',
      badge: { count: 12, variant: 'info' }
    },
    { 
      id: 'teams', 
      label: 'Teams', 
      icon: '👥',
      path: '/teams',
      badge: { count: 3 }
    },
    { 
      id: 'roles', 
      label: 'Roles & Permissions', 
      icon: <Shield className="w-4 h-4" />,
      path: '/roles'
    },
    { 
      id: 'activity', 
      label: 'Activity', 
      icon: <Activity className="w-4 h-4" />,
      path: '/activity',
      disabled: false
    },
    { 
      id: 'settings', 
      label: 'Settings', 
      icon: <Settings className="w-4 h-4" />,
      path: '/settings',
      permissions: ['account.settings.edit']
    }
  ];

  return (
    <PageContainer
      title="Account Management"
      breadcrumbs={getBreadcrumbs()}
      actions={getPageActions()}
    >
      <TabContainer
        tabs={tabs}
        activeTab={activeTab}
        onTabChange={setActiveTab}
        basePath="/app/account"
        variant="underline"
        size="md"
      >
        <TabPanel tabId="users" activeTab={activeTab}>
          <UsersContent />
        </TabPanel>
        
        <TabPanel tabId="teams" activeTab={activeTab}>
          <TeamsContent />
        </TabPanel>
        
        <TabPanel tabId="roles" activeTab={activeTab}>
          <RolesContent />
        </TabPanel>
        
        <TabPanel tabId="activity" activeTab={activeTab}>
          <ActivityContent />
        </TabPanel>
        
        <TabPanel tabId="settings" activeTab={activeTab}>
          <SettingsContent />
        </TabPanel>
      </TabContainer>
    </PageContainer>
  );
};
```

---

## 🎨 TabContainer Variants

### 1. Underline Tabs (Default)
```tsx
<TabContainer
  tabs={tabs}
  variant="underline"
  size="md"
>
```
![Underline Tabs](underline-tabs.png)
- Clean, minimal design
- Clear active state with colored underline
- Best for main navigation within a page

### 2. Pill Tabs
```tsx
<TabContainer
  tabs={tabs}
  variant="pills"
  size="sm"
>
```
![Pill Tabs](pill-tabs.png)
- Rounded, filled background for active state
- Good for settings or configuration pages
- Clear visual separation

### 3. Default Tabs
```tsx
<TabContainer
  tabs={tabs}
  variant="default"
  size="lg"
>
```
![Default Tabs](default-tabs.png)
- Subtle background change for active state
- Good for nested tab groups
- Less visual prominence

---

## 🔄 URL-Based Tab Routing

TabContainer supports automatic URL-based tab activation:

```tsx
<TabContainer
  tabs={[
    { id: 'overview', label: 'Overview', path: '/' },
    { id: 'users', label: 'Users', path: '/users' },
    { id: 'settings', label: 'Settings', path: '/settings' }
  ]}
  basePath="/app/account"
/>
```

This will automatically sync with routes:
- `/app/account` → Overview tab
- `/app/account/users` → Users tab
- `/app/account/settings` → Settings tab

---

## ✅ Best Practices

### DO's ✅

1. **Use PageContainer for every page**
   ```tsx
   // Every page component should have PageContainer
   <PageContainer title="Page Title">
     {/* content */}
   </PageContainer>
   ```

2. **Place TabContainer inside PageContainer**
   ```tsx
   <PageContainer>
     <TabContainer>
       {/* tabs */}
     </TabContainer>
   </PageContainer>
   ```

3. **Use URL routing for main navigation tabs**
   ```tsx
   <TabContainer basePath="/app/section" tabs={tabs} />
   ```

4. **Add badges for counts/status**
   ```tsx
   tabs={[
     { id: 'pending', label: 'Pending', badge: { count: 5, variant: 'warning' } }
   ]}
   ```

5. **Use icons consistently**
   ```tsx
   // Emojis for simple icons
   { icon: '📊' }
   
   // Lucide icons for actions
   { icon: <Settings className="w-4 h-4" /> }
   ```

### DON'Ts ❌

1. **Don't nest PageContainers**
   ```tsx
   // ❌ WRONG
   <PageContainer>
     <PageContainer>
   ```

2. **Don't put actions in TabContainer**
   ```tsx
   // ❌ WRONG - Actions belong in PageContainer
   <TabContainer actions={actions}>
   
   // ✅ CORRECT
   <PageContainer actions={actions}>
     <TabContainer>
   ```

3. **Don't mix tab navigation patterns**
   ```tsx
   // ❌ WRONG - Multiple tab implementations
   <TabContainer>
   <div className="border-b">
     <button>Custom Tab</button>
   ```

4. **Don't hardcode active tab styles**
   ```tsx
   // ❌ WRONG
   className={activeTab === 'users' ? 'text-blue-500' : 'text-gray-500'}
   
   // ✅ CORRECT - Let TabContainer handle it
   <TabContainer activeTab={activeTab}>
   ```

---

## 🔧 Migration Guide

### Converting Custom Tabs to TabContainer

**Before:**
```tsx
<div className="border-b border-theme mb-6">
  <div className="flex space-x-8">
    {tabs.map(tab => (
      <button
        key={tab.id}
        onClick={() => setActiveTab(tab.id)}
        className={activeTab === tab.id ? 'border-b-2 border-blue-500' : ''}
      >
        {tab.label}
      </button>
    ))}
  </div>
</div>
{activeTab === 'users' && <UsersContent />}
{activeTab === 'teams' && <TeamsContent />}
```

**After:**
```tsx
<TabContainer
  tabs={tabs}
  activeTab={activeTab}
  onTabChange={setActiveTab}
  variant="underline"
>
  <TabPanel tabId="users" activeTab={activeTab}>
    <UsersContent />
  </TabPanel>
  <TabPanel tabId="teams" activeTab={activeTab}>
    <TeamsContent />
  </TabPanel>
</TabContainer>
```

---

## 📊 Component Props Reference

### PageContainer Props

| Prop | Type | Required | Description |
|------|------|----------|-------------|
| `title` | `string` | Yes | Page title |
| `description` | `string` | No | Page description |
| `breadcrumbs` | `Breadcrumb[]` | No | Breadcrumb navigation |
| `actions` | `PageAction[]` | No | Page-level actions |
| `children` | `ReactNode` | Yes | Page content |
| `className` | `string` | No | Additional CSS classes |

### TabContainer Props

| Prop | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `tabs` | `Tab[]` | Yes | - | Tab configuration |
| `activeTab` | `string` | No | First tab | Active tab ID |
| `onTabChange` | `(id: string) => void` | No | - | Tab change handler |
| `basePath` | `string` | No | - | Base URL for routing |
| `variant` | `'default' \| 'pills' \| 'underline'` | No | `'underline'` | Visual style |
| `size` | `'sm' \| 'md' \| 'lg'` | No | `'md'` | Tab size |
| `fullWidth` | `boolean` | No | `false` | Full width tabs |
| `renderContent` | `(activeTab: string) => ReactNode` | No | - | Dynamic content renderer |
| `children` | `ReactNode` | No | - | Static tab panels |

### Tab Configuration

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `id` | `string` | Yes | Unique tab identifier |
| `label` | `string` | Yes | Tab label text |
| `icon` | `string \| ReactNode` | No | Tab icon (emoji or component) |
| `path` | `string` | No | URL path for routing |
| `badge` | `{ count: number, variant?: string }` | No | Badge configuration |
| `disabled` | `boolean` | No | Disable tab |
| `permissions` | `string[]` | No | Required permissions |

---

## 🎯 Common Patterns

### 1. Settings Page with Categories
```tsx
<PageContainer title="Settings">
  <TabContainer
    tabs={[
      { id: 'general', label: 'General', icon: '⚙️' },
      { id: 'security', label: 'Security', icon: '🔒' },
      { id: 'notifications', label: 'Notifications', icon: '🔔' },
      { id: 'billing', label: 'Billing', icon: '💳' }
    ]}
    variant="pills"
  >
    {/* Tab panels */}
  </TabContainer>
</PageContainer>
```

### 2. Data Views with Filters
```tsx
<PageContainer title="Orders">
  <TabContainer
    tabs={[
      { id: 'all', label: 'All Orders', badge: { count: 150 } },
      { id: 'pending', label: 'Pending', badge: { count: 23, variant: 'warning' } },
      { id: 'completed', label: 'Completed', badge: { count: 127, variant: 'success' } }
    ]}
    variant="underline"
  >
    {/* Different filtered views */}
  </TabContainer>
</PageContainer>
```

### 3. Multi-Step Form
```tsx
<PageContainer title="New Product">
  <TabContainer
    tabs={[
      { id: 'details', label: '1. Details', icon: '📝' },
      { id: 'pricing', label: '2. Pricing', icon: '💰', disabled: !hasDetails },
      { id: 'inventory', label: '3. Inventory', icon: '📦', disabled: !hasPricing },
      { id: 'review', label: '4. Review', icon: '✅', disabled: !hasInventory }
    ]}
    activeTab={currentStep}
    variant="pills"
  >
    {/* Form steps */}
  </TabContainer>
</PageContainer>
```

---

## 🚀 Quick Reference

```tsx
// Basic Setup
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';

// Page with Tabs
<PageContainer title="Title" actions={actions}>
  <TabContainer tabs={tabs} variant="underline">
    <TabPanel tabId="tab1" activeTab={activeTab}>
      {/* Content */}
    </TabPanel>
  </TabContainer>
</PageContainer>

// URL-based Tabs
<TabContainer 
  tabs={tabs} 
  basePath="/app/section"
/>

// Dynamic Content
<TabContainer 
  tabs={tabs}
  renderContent={(activeTab) => {
    switch(activeTab) {
      case 'tab1': return <Tab1Content />;
      case 'tab2': return <Tab2Content />;
    }
  }}
/>
```

---

*Last Updated: [Current Date]*
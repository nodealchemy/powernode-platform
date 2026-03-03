---
Last Updated: 2026-02-28
Platform Version: 0.3.1
---

# Admin Panel Developer Specialist Guide

## Related References

For common patterns used across multiple specialists, see these consolidated references:
- **[Permission System Reference](../platform/PERMISSION_SYSTEM_REFERENCE.md)** - Permission-based access control for admin features
- **[Theme System Reference](../platform/THEME_SYSTEM_REFERENCE.md)** - Theme-aware styling classes

## Role & Responsibilities

The Admin Panel Developer specializes in creating comprehensive administrative interfaces, system management panels, and complex data management tools for Powernode's subscription platform.

### Core Responsibilities
- Creating admin dashboard interfaces
- Implementing customer management tools
- Building subscription administration features
- Creating system configuration panels
- Handling bulk operations and exports

### Key Focus Areas
- Complex data management interfaces
- Role-based access control for admin features
- Bulk operations and batch processing UI
- Advanced filtering and search capabilities
- System monitoring and health dashboards

## Admin Panel Architecture Standards

### 1. Page Layout Requirements (CRITICAL)

**ABSOLUTE PROHIBITION**: Admin tab pages MUST NOT create duplicate PageContainer or TabContainer structures.

#### Mandatory Page Structure Pattern
```tsx
// ❌ FORBIDDEN: Admin tab page with duplicate containers
const AdminSettingsTabPage: React.FC = () => {
  return (
    <PageContainer title="Settings">
      <AdminSettingsTabs />
      <SettingsComponent />
    </PageContainer>
  );
};

// ✅ CORRECT: Admin tab page returns component directly
const AdminSettingsTabPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const canAccessSettings = hasPermissions(user, ['admin.settings.manage']);
  
  if (!canAccessSettings) {
    return <Navigate to="/app/admin" replace />;
  }
  
  return <SettingsComponent />;
};
```

**Page Layout Enforcement Rules**:
1. **Parent AdminSettingsPage** provides PageContainer and AdminSettingsTabs
2. **Child tab pages** return component content directly - NO containers
3. **Permission checks** must be performed at tab level
4. **Navigation redirects** for unauthorized access

#### Admin Settings Tab Structure (MANDATORY)
```tsx
// Parent AdminSettingsPage.tsx - ONLY place for containers
export const AdminSettingsPage: React.FC = () => {
  return (
    <PageContainer 
      title="Admin Settings"
      breadcrumb={[
        { label: 'Admin', href: '/app/admin' },
        { label: 'Settings' }
      ]}
    >
      <AdminSettingsTabs /> {/* Navigation tabs */}
      <div className="mt-6">
        <Outlet /> {/* Tab content rendered here */}
      </div>
    </PageContainer>
  );
};

// Child tab pages - NO containers, direct component return
export const AdminSettingsGeneralTabPage: React.FC = () => {
  return <GeneralSettings />;
};

export const AdminSettingsSecurityTabPage: React.FC = () => {
  return <SecuritySettings />;
};

export const AdminSettingsRateLimitingTabPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const canManageRateLimiting = hasPermissions(user, ['admin.settings.security']);
  
  if (!canManageRateLimiting) {
    return <Navigate to="/app/admin/settings" replace />;
  }
  
  return <RateLimitingSettings />;
};
```

### 2. Component Standards (MANDATORY)

#### Standard Button Component Usage
**CRITICAL**: All interactive elements MUST use the standard Button component from `@/shared/components/ui/Button`.

```tsx
// ❌ FORBIDDEN: Custom button implementations
<button
  onClick={handleAction}
  className="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600"
>
  Save Settings
</button>

// ✅ CORRECT: Standard Button component
<Button
  onClick={handleAction}
  variant="primary"
  size="lg"
  loading={saving}
>
  <Save className="w-5 h-5 mr-2" />
  Save Settings
</Button>
```

#### Button Variant Standards
```tsx
// Primary actions
<Button variant="primary">Save Changes</Button>
<Button variant="primary" loading={saving}>Processing...</Button>

// Secondary actions  
<Button variant="secondary">Cancel</Button>
<Button variant="secondary" size="sm">Refresh</Button>

// Danger actions
<Button variant="danger">Delete Item</Button>
<Button variant="warning">Temporarily Disable</Button>

// Success actions
<Button variant="success">Re-enable</Button>
<Button variant="success" size="sm">Activate</Button>
```

### 3. Theme-Aware Styling (CRITICAL)

#### MANDATORY Theme Classes
**ABSOLUTE PROHIBITION**: Hardcoded color classes are FORBIDDEN except `text-white` on colored backgrounds.

```tsx
// ❌ FORBIDDEN: Hardcoded colors
className="bg-yellow-100 border-yellow-400 text-yellow-800"
className="bg-red-500 text-white border-red-600"
className="bg-green-50 border-green-200"

// ✅ CORRECT: Theme-aware classes
className="bg-theme-warning-background border-theme-warning text-theme-warning-dark"
className="bg-theme-error border-theme-error text-white"
className="bg-theme-success-background border-theme-success"
```

#### Standard Theme Color Mapping
```typescript
const THEME_CLASSES = {
  // Backgrounds
  surface: 'bg-theme-surface',
  background: 'bg-theme-background', 
  surfaceSubtle: 'bg-theme-surface-subtle',
  
  // State backgrounds
  warningBg: 'bg-theme-warning-background',
  errorBg: 'bg-theme-error-background',
  successBg: 'bg-theme-success-background',
  
  // Text colors
  primary: 'text-theme-primary',
  secondary: 'text-theme-secondary',
  tertiary: 'text-theme-tertiary',
  
  // State text colors
  error: 'text-theme-error',
  errorDark: 'text-theme-error-dark',
  warning: 'text-theme-warning', 
  warningDark: 'text-theme-warning-dark',
  success: 'text-theme-success',
  successDark: 'text-theme-success-dark',
  
  // Borders
  border: 'border-theme',
  errorBorder: 'border-theme-error',
  warningBorder: 'border-theme-warning',
  successBorder: 'border-theme-success'
} as const;
```

#### Form Input Standards (ACCESSIBILITY CRITICAL)
**MANDATORY**: All form inputs must provide sufficient contrast and theme-aware styling.

```tsx
// ✅ CORRECT: Theme-aware form input with accessibility
<input
  type="number"
  className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:ring-2 focus:ring-theme-primary focus:border-theme-primary"
  value={value}
  onChange={handleChange}
  aria-label="Input description"
/>

// ✅ CORRECT: Emergency control input with proper contrast
<input
  type="number"
  className="w-20 px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:ring-2 focus:ring-theme-warning focus:border-theme-warning text-sm font-medium"
  min="1"
  max="480"
/>
```

### 4. Accessibility Compliance (WCAG AA MANDATORY)

#### Contrast Requirements
- **Text contrast ratio**: Minimum 4.5:1 for normal text, 3:1 for large text
- **Interactive elements**: Minimum 3:1 contrast for focus states
- **Form inputs**: Must have sufficient contrast between text and background

#### ARIA and Semantic HTML
```tsx
// ✅ CORRECT: Proper ARIA labels and semantic structure
<section aria-labelledby="settings-title">
  <h2 id="settings-title" className="text-xl font-semibold text-theme-primary">
    Rate Limiting Settings
  </h2>
  
  <div role="group" aria-labelledby="emergency-controls-title">
    <h3 id="emergency-controls-title" className="font-medium text-theme-warning mb-2">
      Emergency Controls
    </h3>
    
    <label htmlFor="disable-duration" className="block text-sm font-medium">
      Duration (minutes)
    </label>
    <input
      id="disable-duration"
      type="number"
      min="1"
      max="480"
      aria-describedby="disable-help"
      className="..."
    />
    <p id="disable-help" className="text-sm text-theme-secondary">
      Temporarily disable rate limiting for maintenance
    </p>
  </div>
</section>
```

#### Focus Management
```tsx
// ✅ CORRECT: Visible focus states with theme awareness
className="focus:ring-2 focus:ring-theme-primary focus:ring-offset-2 focus:outline-none"

// ✅ CORRECT: Focus trap in modals
const focusableElements = modalRef.current?.querySelectorAll(
  'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
);
```

### 5. Admin Layout Structure (MANDATORY)

#### Admin-Specific Layout Component
```tsx
// src/shared/components/layout/AdminLayout.tsx
import React, { useState } from 'react';
import { Outlet, useNavigate, useLocation } from 'react-router-dom';
import { useAuth } from '@/features/auth/hooks/useAuth';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { AdminSidebar } from './AdminSidebar';
import { AdminHeader } from './AdminHeader';
import { AdminBreadcrumb } from './AdminBreadcrumb';
import { SystemHealthIndicator } from '@/features/admin/components/SystemHealthIndicator';

export const AdminLayout: React.FC = () => {
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const { user } = useAuth();
  const { hasPermission } = usePermissions();
  const navigate = useNavigate();
  const location = useLocation();

  // Redirect if no admin access
  if (!hasPermission('admin.access')) {
    navigate('/unauthorized');
    return null;
  }

  return (
    <div className="min-h-screen bg-theme-background">
      {/* Mobile sidebar */}
      <div className={`fixed inset-0 z-50 lg:hidden ${sidebarOpen ? 'block' : 'hidden'}`}>
        <div className="fixed inset-0 bg-gray-600 bg-opacity-75" onClick={() => setSidebarOpen(false)} />
        <AdminSidebar onClose={() => setSidebarOpen(false)} />
      </div>

      {/* Desktop sidebar */}
      <div className="hidden lg:block lg:fixed lg:inset-y-0 lg:w-64">
        <AdminSidebar />
      </div>

      {/* Main content */}
      <div className="lg:pl-64 flex flex-col min-h-screen">
        {/* Top navigation */}
        <AdminHeader 
          onMenuClick={() => setSidebarOpen(!sidebarOpen)}
          user={user}
        />

        {/* Page content */}
        <main className="flex-1 overflow-auto">
          {/* System health indicator */}
          <div className="bg-theme-surface border-b border-theme px-6 py-2">
            <SystemHealthIndicator />
          </div>

          {/* Breadcrumb */}
          <div className="bg-theme-surface border-b border-theme px-6 py-4">
            <AdminBreadcrumb />
          </div>

          {/* Main content area */}
          <div className="px-6 py-8">
            <Outlet />
          </div>
        </main>
      </div>
    </div>
  );
};

// src/shared/components/layout/AdminSidebar.tsx
interface AdminSidebarProps {
  onClose?: () => void;
}

export const AdminSidebar: React.FC<AdminSidebarProps> = ({ onClose }) => {
  const location = useLocation();
  const { hasPermission } = usePermissions();

  const navigationItems = [
    {
      name: 'Dashboard',
      href: '/app/admin',
      icon: '📊',
      permission: 'admin.access'
    },
    {
      name: 'User Management',
      href: '/app/admin/users',
      icon: '👥',
      permission: 'admin.users.manage'
    },
    {
      name: 'Account Management',
      href: '/app/admin/accounts',
      icon: '🏢',
      permission: 'admin.accounts.manage'
    },
    {
      name: 'Subscription Management',
      href: '/app/admin/subscriptions',
      icon: '💳',
      permission: 'admin.subscriptions.manage'
    },
    {
      name: 'System Settings',
      href: '/app/admin/settings',
      icon: '⚙️',
      permission: 'admin.settings.manage'
    },
    {
      name: 'Audit Logs',
      href: '/app/admin/audit-logs',
      icon: '📋',
      permission: 'admin.audit.read'
    },
    {
      name: 'Performance',
      href: '/app/admin/performance',
      icon: '📈',
      permission: 'admin.performance.read'
    },
    {
      name: 'Maintenance',
      href: '/app/admin/maintenance',
      icon: '🔧',
      permission: 'admin.maintenance.access'
    }
  ];

  const filteredItems = navigationItems.filter(item => 
    hasPermission(item.permission)
  );

  return (
    <div className="flex flex-col h-full bg-theme-surface border-r border-theme">
      {/* Header */}
      <div className="flex items-center justify-between p-6 border-b border-theme">
        <h2 className="text-lg font-semibold text-theme-primary">Admin Panel</h2>
        {onClose && (
          <button
            onClick={onClose}
            className="p-2 rounded-md text-theme-secondary hover:bg-theme-background lg:hidden"
          >
            ✕
          </button>
        )}
      </div>

      {/* Navigation */}
      <nav className="flex-1 px-4 py-6 space-y-2">
        {filteredItems.map((item) => (
          <a
            key={item.name}
            href={item.href}
            className={`flex items-center px-3 py-2 rounded-md text-sm font-medium transition-colors ${
              location.pathname === item.href
                ? 'bg-theme-interactive-primary text-white'
                : 'text-theme-secondary hover:bg-theme-background hover:text-theme-primary'
            }`}
          >
            <span className="mr-3 text-lg">{item.icon}</span>
            {item.name}
          </a>
        ))}
      </nav>

      {/* Footer */}
      <div className="p-4 border-t border-theme">
        <div className="text-xs text-theme-tertiary text-center">
          Admin Panel v1.0
        </div>
      </div>
    </div>
  );
};
```

### 2. Data Management Components (MANDATORY)

#### Advanced Data Table with Admin Features
```tsx
// src/features/admin/components/AdminDataTable.tsx
import React, { useState, useMemo } from 'react';
import { Table, Column, Pagination } from '@/shared/components/data-display/Table';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import { Checkbox } from '@/shared/components/ui/Checkbox';
import { Modal } from '@/shared/components/ui/Modal';
import { useDebounce } from '@/shared/hooks/useDebounce';

interface AdminDataTableProps<T> {
  data: T[];
  columns: Column<T>[];
  loading?: boolean;
  totalCount: number;
  currentPage: number;
  itemsPerPage: number;
  onPageChange: (page: number) => void;
  onItemsPerPageChange: (itemsPerPage: number) => void;
  onSort?: (column: keyof T, direction: 'asc' | 'desc') => void;
  onSearch?: (query: string) => void;
  onFilter?: (filters: Record<string, any>) => void;
  onBulkAction?: (action: string, selectedIds: string[]) => void;
  onExport?: (format: 'csv' | 'xlsx') => void;
  bulkActions?: Array<{ label: string; value: string; danger?: boolean }>;
  filters?: Array<{ 
    key: string; 
    label: string; 
    type: 'select' | 'date' | 'text';
    options?: Array<{ label: string; value: string }>;
  }>;
  searchPlaceholder?: string;
  selectable?: boolean;
}

export function AdminDataTable<T extends { id: string }>({
  data,
  columns,
  loading,
  totalCount,
  currentPage,
  itemsPerPage,
  onPageChange,
  onItemsPerPageChange,
  onSort,
  onSearch,
  onFilter,
  onBulkAction,
  onExport,
  bulkActions = [],
  filters = [],
  searchPlaceholder = "Search...",
  selectable = true
}: AdminDataTableProps<T>) {
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [showBulkConfirm, setShowBulkConfirm] = useState(false);
  const [pendingBulkAction, setPendingBulkAction] = useState<string>('');
  const [currentFilters, setCurrentFilters] = useState<Record<string, any>>({});

  const debouncedSearch = useDebounce(searchQuery, 300);

  // Handle search
  React.useEffect(() => {
    onSearch?.(debouncedSearch);
  }, [debouncedSearch, onSearch]);

  // Selection handlers
  const handleSelectAll = (checked: boolean) => {
    if (checked) {
      setSelectedIds(new Set(data.map(item => item.id)));
    } else {
      setSelectedIds(new Set());
    }
  };

  const handleSelectItem = (id: string, checked: boolean) => {
    const newSelected = new Set(selectedIds);
    if (checked) {
      newSelected.add(id);
    } else {
      newSelected.delete(id);
    }
    setSelectedIds(newSelected);
  };

  // Bulk action handlers
  const handleBulkAction = (action: string) => {
    if (selectedIds.size === 0) return;
    
    setPendingBulkAction(action);
    setShowBulkConfirm(true);
  };

  const confirmBulkAction = () => {
    onBulkAction?.(pendingBulkAction, Array.from(selectedIds));
    setSelectedIds(new Set());
    setShowBulkConfirm(false);
    setPendingBulkAction('');
  };

  // Filter handlers
  const handleFilterChange = (key: string, value: any) => {
    const newFilters = { ...currentFilters, [key]: value };
    if (!value) {
      delete newFilters[key];
    }
    setCurrentFilters(newFilters);
    onFilter?.(newFilters);
  };

  // Enhanced columns with selection
  const enhancedColumns = useMemo(() => {
    const cols = [...columns];
    
    if (selectable) {
      cols.unshift({
        key: 'select' as keyof T,
        header: (
          <Checkbox
            checked={data.length > 0 && selectedIds.size === data.length}
            indeterminate={selectedIds.size > 0 && selectedIds.size < data.length}
            onChange={handleSelectAll}
          />
        ),
        width: '50px',
        render: (_, row) => (
          <Checkbox
            checked={selectedIds.has(row.id)}
            onChange={(checked) => handleSelectItem(row.id, checked)}
          />
        )
      });
    }
    
    return cols;
  }, [columns, data.length, selectedIds, selectable]);

  const allSelected = data.length > 0 && selectedIds.size === data.length;
  const someSelected = selectedIds.size > 0 && selectedIds.size < data.length;

  return (
    <div className="space-y-6">
      {/* Controls */}
      <div className="bg-theme-surface rounded-lg border border-theme p-6">
        <div className="flex flex-col lg:flex-row lg:items-center lg:justify-between space-y-4 lg:space-y-0 lg:space-x-4">
          {/* Search */}
          <div className="flex-1 max-w-md">
            <Input
              placeholder={searchPlaceholder}
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              leftIcon={<SearchIcon className="h-4 w-4" />}
            />
          </div>

          {/* Filters */}
          {filters.length > 0 && (
            <div className="flex flex-wrap gap-2">
              {filters.map((filter) => (
                <div key={filter.key} className="min-w-[150px]">
                  {filter.type === 'select' ? (
                    <Select
                      placeholder={filter.label}
                      value={currentFilters[filter.key] || ''}
                      onChange={(value) => handleFilterChange(filter.key, value)}
                      options={filter.options || []}
                    />
                  ) : (
                    <Input
                      placeholder={filter.label}
                      value={currentFilters[filter.key] || ''}
                      onChange={(e) => handleFilterChange(filter.key, e.target.value)}
                      type={filter.type === 'date' ? 'date' : 'text'}
                    />
                  )}
                </div>
              ))}
            </div>
          )}

          {/* Export */}
          {onExport && (
            <div className="flex space-x-2">
              <Button
                variant="secondary"
                size="sm"
                onClick={() => onExport('csv')}
              >
                Export CSV
              </Button>
              <Button
                variant="secondary"
                size="sm"
                onClick={() => onExport('xlsx')}
              >
                Export Excel
              </Button>
            </div>
          )}
        </div>

        {/* Bulk actions */}
        {selectable && selectedIds.size > 0 && (
          <div className="mt-4 flex items-center justify-between bg-theme-background rounded-md p-3">
            <div className="text-sm text-theme-secondary">
              {selectedIds.size} item{selectedIds.size !== 1 ? 's' : ''} selected
            </div>
            
            <div className="flex space-x-2">
              {bulkActions.map((action) => (
                <Button
                  key={action.value}
                  variant={action.danger ? 'danger' : 'secondary'}
                  size="sm"
                  onClick={() => handleBulkAction(action.value)}
                >
                  {action.label}
                </Button>
              ))}
            </div>
          </div>
        )}
      </div>

      {/* Data table */}
      <Table
        data={data}
        columns={enhancedColumns}
        loading={loading}
        onSort={onSort}
        emptyMessage="No data found"
      />

      {/* Pagination */}
      <Pagination
        currentPage={currentPage}
        totalPages={Math.ceil(totalCount / itemsPerPage)}
        totalItems={totalCount}
        itemsPerPage={itemsPerPage}
        onPageChange={onPageChange}
        onItemsPerPageChange={onItemsPerPageChange}
      />

      {/* Bulk action confirmation */}
      <Modal
        open={showBulkConfirm}
        onOpenChange={setShowBulkConfirm}
        title="Confirm Bulk Action"
        size="sm"
      >
        <div className="space-y-4">
          <p className="text-theme-secondary">
            Are you sure you want to perform "{pendingBulkAction}" on {selectedIds.size} selected items?
            This action cannot be undone.
          </p>
          
          <div className="flex space-x-3 justify-end">
            <Button
              variant="secondary"
              onClick={() => setShowBulkConfirm(false)}
            >
              Cancel
            </Button>
            <Button
              variant="danger"
              onClick={confirmBulkAction}
            >
              Confirm
            </Button>
          </div>
        </div>
      </Modal>
    </div>
  );
}
```

#### User Management Interface
```tsx
// src/features/admin/components/UserManagement.tsx
import React, { useState } from 'react';
import { useApi } from '@/shared/hooks/useApi';
import { adminApi } from '@/features/admin/services/adminApi';
import { AdminDataTable } from './AdminDataTable';
import { CreateUserModal } from './CreateUserModal';
import { ImpersonateUserModal } from './ImpersonateUserModal';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';

interface AdminUser {
  id: string;
  email: string;
  firstName: string;
  lastName: string;
  role: string;
  status: 'active' | 'suspended' | 'pending';
  lastLoginAt: string | null;
  createdAt: string;
  account: {
    id: string;
    name: string;
  };
}

export const UserManagement: React.FC = () => {
  const [currentPage, setCurrentPage] = useState(1);
  const [itemsPerPage, setItemsPerPage] = useState(20);
  const [searchQuery, setSearchQuery] = useState('');
  const [filters, setFilters] = useState<Record<string, any>>({});
  const [sortColumn, setSortColumn] = useState<keyof AdminUser>('createdAt');
  const [sortDirection, setSortDirection] = useState<'asc' | 'desc'>('desc');
  
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [showImpersonateModal, setShowImpersonateModal] = useState(false);
  const [selectedUser, setSelectedUser] = useState<AdminUser | null>(null);

  const { data: usersData, loading, execute: refetchUsers } = useApi(
    () => adminApi.getUsers({
      page: currentPage,
      per_page: itemsPerPage,
      search: searchQuery,
      filters,
      sort: sortColumn,
      direction: sortDirection
    }),
    { 
      immediate: true,
      onError: (error) => console.error('Failed to load users:', error)
    }
  );

  const columns = [
    {
      key: 'email' as keyof AdminUser,
      header: 'Email',
      sortable: true,
      render: (email: string, user: AdminUser) => (
        <div className="space-y-1">
          <div className="font-medium text-theme-primary">{email}</div>
          <div className="text-sm text-theme-secondary">
            {user.firstName} {user.lastName}
          </div>
        </div>
      )
    },
    {
      key: 'account' as keyof AdminUser,
      header: 'Account',
      render: (account: AdminUser['account']) => (
        <div className="text-sm text-theme-primary">{account.name}</div>
      )
    },
    {
      key: 'role' as keyof AdminUser,
      header: 'Role',
      sortable: true,
      render: (role: string) => (
        <Badge variant={getRoleVariant(role)}>
          {role.replace('_', ' ')}
        </Badge>
      )
    },
    {
      key: 'status' as keyof AdminUser,
      header: 'Status',
      sortable: true,
      render: (status: string) => (
        <Badge variant={getStatusVariant(status)}>
          {status}
        </Badge>
      )
    },
    {
      key: 'lastLoginAt' as keyof AdminUser,
      header: 'Last Login',
      render: (lastLoginAt: string | null) => (
        <div className="text-sm text-theme-secondary">
          {lastLoginAt 
            ? new Date(lastLoginAt).toLocaleDateString()
            : 'Never'
          }
        </div>
      )
    },
    {
      key: 'actions' as keyof AdminUser,
      header: 'Actions',
      width: '200px',
      render: (_, user: AdminUser) => (
        <div className="flex space-x-2">
          <Button
            size="sm"
            variant="secondary"
            onClick={() => {
              setSelectedUser(user);
              setShowImpersonateModal(true);
            }}
          >
            Impersonate
          </Button>
          <Button
            size="sm"
            variant="secondary"
            onClick={() => handleEditUser(user)}
          >
            Edit
          </Button>
        </div>
      )
    }
  ];

  const bulkActions = [
    { label: 'Suspend Users', value: 'suspend', danger: true },
    { label: 'Activate Users', value: 'activate' },
    { label: 'Send Reset Email', value: 'reset_password' },
    { label: 'Delete Users', value: 'delete', danger: true }
  ];

  const filterOptions = [
    {
      key: 'status',
      label: 'Status',
      type: 'select' as const,
      options: [
        { label: 'Active', value: 'active' },
        { label: 'Suspended', value: 'suspended' },
        { label: 'Pending', value: 'pending' }
      ]
    },
    {
      key: 'role',
      label: 'Role',
      type: 'select' as const,
      options: [
        { label: 'Admin', value: 'admin' },
        { label: 'Manager', value: 'manager' },
        { label: 'Member', value: 'member' }
      ]
    },
    {
      key: 'created_after',
      label: 'Created After',
      type: 'date' as const
    }
  ];

  const handleBulkAction = async (action: string, selectedIds: string[]) => {
    try {
      await adminApi.bulkUserAction(action, selectedIds);
      refetchUsers();
      // Show success notification
    } catch (error) {
      console.error('Bulk action failed:', error);
      // Show error notification
    }
  };

  const handleExport = async (format: 'csv' | 'xlsx') => {
    try {
      const blob = await adminApi.exportUsers({ format, filters, search: searchQuery });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `users.${format}`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
    } catch (error) {
      console.error('Export failed:', error);
    }
  };

  const handleEditUser = (user: AdminUser) => {
    // Implementation for editing user
    console.log('Edit user:', user);
  };

  const getRoleVariant = (role: string) => {
    const variants = {
      admin: 'danger',
      manager: 'warning',
      member: 'default'
    };
    return variants[role as keyof typeof variants] || 'default';
  };

  const getStatusVariant = (status: string) => {
    const variants = {
      active: 'success',
      suspended: 'danger',
      pending: 'warning'
    };
    return variants[status as keyof typeof variants] || 'default';
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-theme-primary">User Management</h1>
          <p className="text-theme-secondary mt-1">
            Manage user accounts, roles, and permissions
          </p>
        </div>
        
        <Button
          onClick={() => setShowCreateModal(true)}
          icon={<PlusIcon className="h-4 w-4" />}
        >
          Create User
        </Button>
      </div>

      {/* Data table */}
      <AdminDataTable
        data={usersData?.users || []}
        columns={columns}
        loading={loading}
        totalCount={usersData?.totalCount || 0}
        currentPage={currentPage}
        itemsPerPage={itemsPerPage}
        onPageChange={setCurrentPage}
        onItemsPerPageChange={setItemsPerPage}
        onSort={(column, direction) => {
          setSortColumn(column);
          setSortDirection(direction);
        }}
        onSearch={setSearchQuery}
        onFilter={setFilters}
        onBulkAction={handleBulkAction}
        onExport={handleExport}
        bulkActions={bulkActions}
        filters={filterOptions}
        searchPlaceholder="Search users by email, name, or account..."
      />

      {/* Modals */}
      <CreateUserModal
        open={showCreateModal}
        onClose={() => setShowCreateModal(false)}
        onSuccess={refetchUsers}
      />

      {selectedUser && (
        <ImpersonateUserModal
          open={showImpersonateModal}
          onClose={() => {
            setShowImpersonateModal(false);
            setSelectedUser(null);
          }}
          user={selectedUser}
        />
      )}
    </div>
  );
};
```

### 3. System Monitoring Components (MANDATORY)

#### System Health Dashboard
```tsx
// src/features/admin/components/SystemHealthDashboard.tsx
import React from 'react';
import { useApi } from '@/shared/hooks/useApi';
import { useInterval } from '@/shared/hooks/useInterval';
import { adminApi } from '@/features/admin/services/adminApi';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { ProgressBar } from '@/shared/components/ui/ProgressBar';

interface SystemHealth {
  status: 'healthy' | 'degraded' | 'critical';
  services: {
    database: ServiceStatus;
    redis: ServiceStatus;
    sidekiq: ServiceStatus;
    storage: ServiceStatus;
  };
  metrics: {
    cpuUsage: number;
    memoryUsage: number;
    diskUsage: number;
    activeConnections: number;
    responseTime: number;
  };
  alerts: SystemAlert[];
}

interface ServiceStatus {
  status: 'up' | 'down' | 'degraded';
  responseTime: number;
  lastChecked: string;
  error?: string;
}

interface SystemAlert {
  id: string;
  level: 'info' | 'warning' | 'error' | 'critical';
  message: string;
  timestamp: string;
  resolved: boolean;
}

export const SystemHealthDashboard: React.FC = () => {
  const { data: healthData, loading, execute: refetchHealth } = useApi(
    () => adminApi.getSystemHealth(),
    { immediate: true }
  );

  // Refresh every 30 seconds
  useInterval(() => {
    refetchHealth();
  }, 30000);

  if (loading && !healthData) {
    return <div>Loading system health...</div>;
  }

  const health: SystemHealth = healthData || {
    status: 'healthy',
    services: {
      database: { status: 'up', responseTime: 0, lastChecked: '' },
      redis: { status: 'up', responseTime: 0, lastChecked: '' },
      sidekiq: { status: 'up', responseTime: 0, lastChecked: '' },
      storage: { status: 'up', responseTime: 0, lastChecked: '' }
    },
    metrics: {
      cpuUsage: 0,
      memoryUsage: 0,
      diskUsage: 0,
      activeConnections: 0,
      responseTime: 0
    },
    alerts: []
  };

  const getStatusVariant = (status: string) => {
    const variants = {
      healthy: 'success',
      up: 'success',
      degraded: 'warning',
      critical: 'danger',
      down: 'danger'
    };
    return variants[status as keyof typeof variants] || 'default';
  };

  const getAlertVariant = (level: string) => {
    const variants = {
      info: 'default',
      warning: 'warning',
      error: 'danger',
      critical: 'danger'
    };
    return variants[level as keyof typeof variants] || 'default';
  };

  return (
    <div className="space-y-6">
      {/* Overall Status */}
      <Card className="p-6">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="text-xl font-semibold text-theme-primary">System Status</h2>
            <p className="text-theme-secondary mt-1">Overall system health and performance</p>
          </div>
          <Badge variant={getStatusVariant(health.status)} size="lg">
            {health.status.toUpperCase()}
          </Badge>
        </div>
      </Card>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Services Status */}
        <Card className="p-6">
          <h3 className="text-lg font-medium text-theme-primary mb-4">Services</h3>
          <div className="space-y-4">
            {Object.entries(health.services).map(([serviceName, service]) => (
              <div key={serviceName} className="flex items-center justify-between">
                <div className="flex items-center space-x-3">
                  <div className={`w-3 h-3 rounded-full ${
                    service.status === 'up' ? 'bg-theme-success' :
                    service.status === 'degraded' ? 'bg-theme-warning' : 'bg-theme-error'
                  }`} />
                  <div>
                    <div className="font-medium text-theme-primary capitalize">
                      {serviceName}
                    </div>
                    {service.error && (
                      <div className="text-sm text-theme-error">{service.error}</div>
                    )}
                  </div>
                </div>
                <div className="text-right">
                  <Badge variant={getStatusVariant(service.status)}>
                    {service.status}
                  </Badge>
                  <div className="text-xs text-theme-secondary mt-1">
                    {service.responseTime}ms
                  </div>
                </div>
              </div>
            ))}
          </div>
        </Card>

        {/* System Metrics */}
        <Card className="p-6">
          <h3 className="text-lg font-medium text-theme-primary mb-4">System Metrics</h3>
          <div className="space-y-4">
            <div>
              <div className="flex items-center justify-between mb-2">
                <span className="text-sm font-medium text-theme-primary">CPU Usage</span>
                <span className="text-sm text-theme-secondary">{health.metrics.cpuUsage}%</span>
              </div>
              <ProgressBar 
                value={health.metrics.cpuUsage} 
                variant={health.metrics.cpuUsage > 80 ? 'danger' : health.metrics.cpuUsage > 60 ? 'warning' : 'success'}
              />
            </div>

            <div>
              <div className="flex items-center justify-between mb-2">
                <span className="text-sm font-medium text-theme-primary">Memory Usage</span>
                <span className="text-sm text-theme-secondary">{health.metrics.memoryUsage}%</span>
              </div>
              <ProgressBar 
                value={health.metrics.memoryUsage} 
                variant={health.metrics.memoryUsage > 80 ? 'danger' : health.metrics.memoryUsage > 60 ? 'warning' : 'success'}
              />
            </div>

            <div>
              <div className="flex items-center justify-between mb-2">
                <span className="text-sm font-medium text-theme-primary">Disk Usage</span>
                <span className="text-sm text-theme-secondary">{health.metrics.diskUsage}%</span>
              </div>
              <ProgressBar 
                value={health.metrics.diskUsage} 
                variant={health.metrics.diskUsage > 90 ? 'danger' : health.metrics.diskUsage > 75 ? 'warning' : 'success'}
              />
            </div>

            <div className="grid grid-cols-2 gap-4 pt-4 border-t border-theme">
              <div className="text-center">
                <div className="text-2xl font-bold text-theme-primary">
                  {health.metrics.activeConnections}
                </div>
                <div className="text-sm text-theme-secondary">Active Connections</div>
              </div>
              <div className="text-center">
                <div className="text-2xl font-bold text-theme-primary">
                  {health.metrics.responseTime}ms
                </div>
                <div className="text-sm text-theme-secondary">Avg Response Time</div>
              </div>
            </div>
          </div>
        </Card>
      </div>

      {/* System Alerts */}
      {health.alerts.length > 0 && (
        <Card className="p-6">
          <h3 className="text-lg font-medium text-theme-primary mb-4">Recent Alerts</h3>
          <div className="space-y-3">
            {health.alerts.slice(0, 10).map((alert) => (
              <div 
                key={alert.id} 
                className={`flex items-start space-x-3 p-3 rounded-md ${
                  alert.resolved ? 'bg-theme-background opacity-60' : 'bg-theme-surface'
                }`}
              >
                <Badge variant={getAlertVariant(alert.level)} size="sm">
                  {alert.level}
                </Badge>
                <div className="flex-1">
                  <div className={`text-sm ${alert.resolved ? 'line-through' : ''}`}>
                    {alert.message}
                  </div>
                  <div className="text-xs text-theme-secondary mt-1">
                    {new Date(alert.timestamp).toLocaleString()}
                  </div>
                </div>
                {alert.resolved && (
                  <Badge variant="success" size="sm">Resolved</Badge>
                )}
              </div>
            ))}
          </div>
        </Card>
      )}
    </div>
  );
};
```

## Development Commands

### Admin Panel Development
```bash
# Install admin-specific dependencies
npm install @dnd-kit/core @dnd-kit/sortable react-window
npm install @tanstack/react-virtual

# Run admin panel in development
npm start

# Test admin components
npm test -- --testPathPattern=admin

# Build optimized admin panel
npm run build
```

### Security and Permissions Testing
```bash
# Test permission-based access
npm run test:permissions

# Security audit for admin functions
npm audit

# Test bulk operations
npm run test:bulk-operations
```

## Integration Points

### Admin Panel Developer Coordinates With:
- **Security Specialist**: Permission validation, audit logging
- **Backend Test Engineer**: Admin API endpoint testing
- **Data Modeler**: Complex data relationships for admin views
- **Performance Optimizer**: Large dataset handling, bulk operations
- **UI Component Developer**: Complex form components, data tables

## Quick Reference

### Admin Data Table Template
```tsx
const columns = [
  { key: 'name', header: 'Name', sortable: true },
  { key: 'status', header: 'Status', render: (status) => <Badge>{status}</Badge> },
  { key: 'actions', header: 'Actions', render: (_, row) => <ActionButtons row={row} /> }
];

<AdminDataTable
  data={data}
  columns={columns}
  onBulkAction={handleBulkAction}
  bulkActions={[
    { label: 'Delete', value: 'delete', danger: true },
    { label: 'Archive', value: 'archive' }
  ]}
/>
```

### Permission Check Template
```tsx
const { hasPermission } = usePermissions();

if (!hasPermission('admin.users.manage')) {
  return <UnauthorizedAccess />;
}

return <UserManagementInterface />;
```

## Page Layout Validation Commands

### Structure Compliance Audits
```bash
# Check for duplicate PageContainer usage in admin tab pages
grep -r "<PageContainer" src/pages/app/admin/ | grep -v "AdminSettingsPage.tsx"

# Find admin tab pages that incorrectly include AdminSettingsTabs
grep -r "<AdminSettingsTabs" src/pages/app/admin/ | grep -v "AdminSettingsPage.tsx"

# Verify standard Button component usage
grep -r "<button[^>]*className=" src/features/admin/ | wc -l  # Should be minimal
grep -r "<Button" src/features/admin/ | wc -l                # Should be high

# Check for hardcoded colors (should return minimal results)
grep -r "bg-yellow-\|bg-red-\|bg-green-\|text-yellow-\|text-red-" src/features/admin/ | grep -v "text-white"

# Count theme-aware classes (should be substantial)
grep -r "bg-theme-\|text-theme-\|border-theme" src/features/admin/ | wc -l

# Verify accessibility - ARIA labels and semantic HTML
grep -r "aria-label\|aria-describedby\|aria-labelledby" src/features/admin/ | wc -l
grep -r "role=\|id=.*title\|htmlFor=" src/features/admin/ | wc -l
```

### Component Standards Verification
```bash
# Check for custom button implementations (should be minimal)
grep -r "onClick.*className.*px-.*py-" src/features/admin/ | wc -l

# Verify Button component props usage
grep -r "variant=\"primary\|variant=\"secondary\|variant=\"danger" src/features/admin/ | wc -l

# Check loading prop usage
grep -r "loading={.*}" src/features/admin/ | wc -l

# Verify icon usage in buttons
grep -r "<.*Icon.*className=\"w-.*h-.* mr-" src/features/admin/ | wc -l
```

### Accessibility Compliance Checks
```bash
# Verify contrast-compliant input fields
grep -r "bg-theme-surface.*text-theme-primary" src/features/admin/ | grep "input\|textarea" | wc -l

# Check focus ring implementations
grep -r "focus:ring-2.*focus:ring-theme-" src/features/admin/ | wc -l

# Verify semantic HTML usage
grep -r "<section\|<article\|<nav\|<main\|<header\|<footer" src/features/admin/ | wc -l

# Check for proper form labels
grep -r "htmlFor=\|<label.*for=" src/features/admin/ | wc -l
```

### Theme Consistency Validation
```bash
# Emergency Controls theme validation
grep -A10 -B5 "Emergency Controls" src/features/admin/ | grep -E "theme-warning|theme-error|theme-success"

# Recent Violations theme validation  
grep -A10 -B5 "Recent Violations" src/features/admin/ | grep -E "theme-error"

# Form input theme validation
grep -r "className=.*input" src/features/admin/ | grep -E "bg-theme-surface.*text-theme-primary"
```

## Admin Panel Developer Critical Requirements

### 1. ABSOLUTE PROHIBITIONS
- ❌ **NO duplicate PageContainer** in admin tab pages
- ❌ **NO duplicate AdminSettingsTabs** in child components  
- ❌ **NO custom button implementations** - use standard Button component
- ❌ **NO hardcoded color classes** except `text-white` on colored backgrounds
- ❌ **NO insufficient contrast** in form inputs or interactive elements

### 2. MANDATORY PATTERNS
- ✅ **Admin tab pages return components directly** - no containers
- ✅ **Standard Button component** for all interactive elements
- ✅ **Theme-aware styling** using `theme-*` classes exclusively
- ✅ **Permission-based access control** with proper redirects
- ✅ **WCAG AA accessibility compliance** with proper ARIA labels

### 3. CRITICAL VALIDATIONS
- Page structure follows parent/child container pattern
- All buttons use standard component with appropriate variants
- Color usage exclusively through theme classes
- Form inputs meet contrast requirements
- Accessibility features properly implemented

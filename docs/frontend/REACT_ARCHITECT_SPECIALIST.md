---
Last Updated: 2026-02-28
Platform Version: 0.3.1
---

# React Architect Specialist Guide

## Technology Stack

| Technology | Version |
|-----------|---------|
| React | 19.1.1 |
| Vite | 7.2.0 |
| TypeScript | 5.9.3 |
| Tailwind CSS | 4.1.11 |
| Redux Toolkit | (via `@reduxjs/toolkit`) |

## Related References

For common patterns used across multiple specialists, see these consolidated references:
- **[Permission System Reference](../platform/PERMISSION_SYSTEM_REFERENCE.md)** - Frontend permission-based access control
- **[Theme System Reference](../platform/THEME_SYSTEM_REFERENCE.md)** - Theme-aware styling classes
- **[API Response Standards](../platform/API_RESPONSE_STANDARDS.md)** - API response handling
- **[State Management Guide](STATE_MANAGEMENT_GUIDE.md)** - Redux and React Query patterns
- **[Chat System Architecture](../platform/CHAT_SYSTEM_ARCHITECTURE.md)** - Real-time messaging

## Role & Responsibilities

The React Architect specializes in React application structure, TypeScript configuration, routing, and state management for Powernode's subscription platform.

### Core Responsibilities
- Setting up React 19 application with TypeScript 5.9
- Configuring routing and navigation
- Implementing state management (Redux Toolkit + React Query)
- Setting up component architecture with Tailwind v4
- Handling authentication flow and WebSocket communication

### Key Focus Areas
- Modern React 19 patterns and best practices
- TypeScript integration and type safety
- Scalable feature-based component architecture
- Performance optimization strategies
- State management and data flow
- Real-time communication via ActionCable WebSockets

## React Architecture Standards

### 1. Project Structure (MANDATORY)

**CRITICAL**: Follow standardized structure - moving files outside conventions is prohibited.

#### Overall Project Layout
```
powernode-platform/
├── server/     # Rails 8 API (app/controllers/api/v1/, models/, services/, jobs/, spec/)
├── frontend/   # React TypeScript (src/features/, shared/, pages/, assets/)
├── worker/     # Sidekiq service (app/jobs/, services/, controllers/)
├── scripts/    # Development and deployment scripts
├── docs/       # Project documentation
└── .github/    # GitHub workflows and templates
```

#### Frontend Organization (Feature-Based)

**11 Feature Modules:**

| Module | Description |
|--------|-------------|
| `account/` | Account settings and profile management |
| `admin/` | Admin dashboard, user management, system configuration |
| `ai/` | AI agents, conversations, workflows, teams, knowledge graph |
| `baas/` | Backend-as-a-Service tenant management |
| `business/` | Subscriptions, plans, billing management |
| `content/` | Knowledge base articles, pages, file management |
| `delegations/` | Permission delegation and access sharing |
| `developer/` | Developer tools, API keys, webhooks |
| `devops/` | DevOps dashboard, pipelines, containers, Docker/Swarm |
| `missions/` | AI mission management and tracking |
| `privacy/` | Privacy settings and data management |

```
src/
├── features/           # 11 business domain modules
│   └── [feature]/
│       ├── components/ # Feature-specific components
│       ├── hooks/      # Feature-specific hooks
│       ├── services/   # Feature-specific API calls
│       ├── types/      # Feature-specific TypeScript types
│       └── utils/      # Feature-specific utilities
├── shared/             # Cross-feature reusables
│   ├── components/     # UI primitives (ui/, layout/, forms/, data-display/)
│   ├── hooks/          # Reusable hooks
│   ├── services/       # Shared API services (store, slices, WebSocketManager)
│   ├── types/          # Global TypeScript types
│   └── utils/          # Utility functions (logger, theme, permissions)
├── pages/              # Route-based components (public/, app/, admin/)
└── assets/             # Static assets (images/, fonts/, styles/)
```

#### File Naming & Import Rules
- **Components**: PascalCase.tsx (UserProfile.tsx)
- **Hooks**: camelCase starting with 'use' (useUserProfile.ts) 
- **Services**: camelCase ending with 'Api' (userApi.ts)
- **Types**: PascalCase (User.ts, ApiResponse.ts)

```typescript
// ✅ CORRECT imports with path aliases
import { Button } from '@/shared/components/ui/Button';
import { useAuth } from '@/features/auth/hooks/useAuth';

// ❌ WRONG - avoid deep relative imports  
import { Button } from '../../../shared/components/ui/Button';
```

#### Migration Strategy
Phase 1: Establish structure → Phase 2: Move files by feature → Phase 3: Update imports → Phase 4: Remove old structure

#### TypeScript Configuration
```json
// tsconfig.json
{
  "compilerOptions": {
    "target": "ES2020",
    "lib": ["dom", "dom.iterable", "ES6"],
    "allowJs": true,
    "skipLibCheck": true,
    "esModuleInterop": true,
    "allowSyntheticDefaultImports": true,
    "strict": true,
    "forceConsistentCasingInFileNames": true,
    "noFallthroughCasesInSwitch": true,
    "module": "esnext",
    "moduleResolution": "node",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx",
    "baseUrl": "src",
    "paths": {
      "@/*": ["*"],
      "@/shared/*": ["shared/*"],
      "@/features/*": ["features/*"],
      "@/pages/*": ["pages/*"],
      "@/assets/*": ["assets/*"]
    }
  },
  "include": [
    "src/**/*"
  ],
  "exclude": [
    "node_modules",
    "build",
    "dist"
  ]
}
```

#### Path Alias Configuration
```javascript
// craco.config.js
const path = require('path');

module.exports = {
  webpack: {
    alias: {
      '@': path.resolve(__dirname, 'src'),
      '@/shared': path.resolve(__dirname, 'src/shared'),
      '@/features': path.resolve(__dirname, 'src/features'),
      '@/pages': path.resolve(__dirname, 'src/pages'),
      '@/assets': path.resolve(__dirname, 'src/assets')
    }
  },
  typescript: {
    enableTypeChecking: true
  }
};
```

### 2. Component Architecture (MANDATORY)

#### Component Standards
```tsx
// Standard component structure
import React, { useState, useEffect, useCallback } from 'react';
import { ComponentProps, ComponentState } from './types';
import { useComponentHook } from './hooks';

interface Props extends ComponentProps {
  children?: React.ReactNode;
  className?: string;
}

export const ComponentName: React.FC<Props> = ({ 
  prop1, 
  prop2, 
  children,
  className 
}) => {
  // 1. State hooks first
  const [state, setState] = useState<ComponentState>({});
  const [loading, setLoading] = useState(false);
  
  // 2. Context and custom hooks
  const { data, error } = useComponentHook();
  
  // 3. Effect hooks
  useEffect(() => {
    // Side effects
  }, [dependency]);
  
  // 4. Callback handlers
  const handleAction = useCallback((value: string) => {
    // Handler logic
  }, [dependency]);
  
  // 5. Conditional renders
  if (loading) {
    return <LoadingSpinner />;
  }
  
  if (error) {
    return <ErrorAlert message={error} />;
  }
  
  // 6. Main render
  return (
    <div className={cn('component-base-styles', className)}>
      {children}
    </div>
  );
};

ComponentName.displayName = 'ComponentName';
```

#### Theme-Aware Component Pattern (CRITICAL)
**MANDATORY**: All components must use theme-aware CSS classes discovered in platform analysis.

```typescript
// Theme-aware button component
import { cn } from '@/shared/utils/cn';
import { forwardRef } from 'react';

interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'primary' | 'secondary' | 'danger';
  size?: 'xs' | 'sm' | 'md' | 'lg';
  loading?: boolean;
}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(({
  variant = 'primary',
  size = 'md',
  className = '',
  children,
  loading = false,
  disabled,
  ...props
}, ref) => {
  const baseClasses = cn(
    // Base styles with theme-aware classes
    'btn-theme inline-flex items-center justify-center font-medium transition-colors',
    'focus:outline-none focus:ring-2 focus:ring-theme-primary focus:ring-offset-2',
    'disabled:opacity-50 disabled:pointer-events-none',
    
    // Size variants
    {
      'px-2 py-1 text-xs': size === 'xs',
      'px-3 py-1.5 text-sm': size === 'sm', 
      'px-4 py-2 text-base': size === 'md',
      'px-6 py-3 text-lg': size === 'lg'
    },
    
    // Color variants using theme classes
    {
      'bg-theme-primary text-white hover:bg-theme-primary-dark': variant === 'primary',
      'bg-theme-secondary text-theme-secondary-foreground hover:bg-theme-secondary-dark': variant === 'secondary',
      'bg-theme-error text-white hover:bg-theme-error-dark': variant === 'danger'
    },
    
    className
  );
  
  return (
    <button
      ref={ref}
      className={baseClasses}
      disabled={disabled || loading}
      {...props}
    >
      {loading ? (
        <>
          <LoadingSpinner className="mr-2 h-4 w-4" />
          Loading...
        </>
      ) : (
        children
      )}
    </button>
  );
});

Button.displayName = 'Button';
```

**Theme Class Standards** (discovered in platform analysis):
```typescript
// MANDATORY theme classes - never use hardcoded colors
const THEME_CLASSES = {
  // Background colors
  background: 'bg-theme-background',
  surface: 'bg-theme-surface',
  primary: 'bg-theme-primary',
  secondary: 'bg-theme-secondary',
  error: 'bg-theme-error',
  warning: 'bg-theme-warning',
  success: 'bg-theme-success',
  
  // Text colors  
  textPrimary: 'text-theme-primary',
  textSecondary: 'text-theme-secondary',
  textMuted: 'text-theme-muted',
  textError: 'text-theme-error',
  
  // Border colors
  border: 'border-theme',
  borderMuted: 'border-theme-muted',
  
  // Exceptions (only when necessary)
  textWhite: 'text-white' // Only on colored backgrounds
} as const;

// ❌ FORBIDDEN: Hardcoded color classes
// 'bg-red-500', 'text-gray-900', 'border-blue-300'

// ✅ CORRECT: Theme-aware classes  
// 'bg-theme-primary', 'text-theme-secondary', 'border-theme'
```

#### Component Types and Interfaces
```tsx
// types.ts - Component-specific types
export interface User {
  id: string;
  email: string;
  firstName: string;
  lastName: string;
  permissions: string[];
}

export interface ComponentProps {
  user: User;
  onUpdate: (user: User) => void;
  variant?: 'primary' | 'secondary';
}

export interface ComponentState {
  isEditing: boolean;
  formData: Partial<User>;
  errors: Record<string, string>;
}

export type ComponentVariant = 'primary' | 'secondary' | 'danger';

// API response types
export interface ApiResponse<T> {
  success: boolean;
  data: T;
  error?: string;
  meta?: {
    pagination?: PaginationMeta;
    timestamp: string;
  };
}

export interface PaginationMeta {
  currentPage: number;
  totalPages: number;
  totalCount: number;
  perPage: number;
  hasNext: boolean;
  hasPrev: boolean;
}
```

### 3. Permission-Based Access Control (CRITICAL)

#### MANDATORY Pattern: Permission-Only Access Control
**ABSOLUTE RULE**: Frontend access control MUST use permissions ONLY - NEVER roles. This pattern was discovered as consistently implemented across the entire platform.

#### Page Container Structure Requirements (CRITICAL)
**MANDATORY**: Admin settings pages must follow strict container hierarchy to prevent duplicate navigation structures.

```tsx
// ❌ FORBIDDEN: Admin tab page with duplicate containers
const AdminSettingsRateLimitingTabPage: React.FC = () => {
  return (
    <PageContainer title="Rate Limiting Settings">
      <AdminSettingsTabs />
      <RateLimitingSettings />
    </PageContainer>
  );
};

// ✅ CORRECT: Tab page returns component directly
const AdminSettingsRateLimitingTabPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const canManageRateLimiting = hasPermissions(user, ['admin.settings.security']);
  
  if (!canManageRateLimiting) {
    return <Navigate to="/app/admin/settings" replace />;
  }
  
  return <RateLimitingSettings />;
};
```

**Container Hierarchy Rules**:
1. **Parent page** (AdminSettingsPage) provides PageContainer + AdminSettingsTabs
2. **Child tab pages** return component content directly - NO containers  
3. **Permission validation** at tab page level with appropriate redirects
4. **Navigation state** managed by parent component

```typescript
// ✅ CORRECT: Permission-based access control
const { hasPermission } = usePermissions();
const canManageUsers = hasPermission('users.manage');
const canViewBilling = hasPermission('billing.read');

if (!canManageUsers) {
  return <AccessDenied />;
}

// ✅ CORRECT: UI element control
<Button disabled={!hasPermission('users.create')}>
  Create User
</Button>

// ✅ CORRECT: Conditional rendering
{hasPermission('admin.access') && <AdminPanel />}
```

```typescript
// ❌ FORBIDDEN: Role-based access control
const canManage = currentUser?.roles?.includes('account.manager');
const isSystemAdmin = currentUser?.role === 'system.admin';
if (user.roles.includes('billing.manager')) { /* ... */ }

// ❌ FORBIDDEN: Mixed role/permission checks
const hasAccess = user.roles.includes('admin') || user.permissions.includes('read');
```

#### usePermissions Hook Pattern
```typescript
// hooks/usePermissions.ts
import { useAuth } from '@/features/auth/hooks/useAuth';

export const usePermissions = () => {
  const { currentUser } = useAuth();
  
  const hasPermission = (permission: string): boolean => {
    return currentUser?.permissions?.includes(permission) || false;
  };
  
  const hasAnyPermission = (permissions: string[]): boolean => {
    return permissions.some(permission => hasPermission(permission));
  };
  
  const hasAllPermissions = (permissions: string[]): boolean => {
    return permissions.every(permission => hasPermission(permission));
  };
  
  const requirePermission = (permission: string) => {
    if (!hasPermission(permission)) {
      throw new Error(`Missing required permission: ${permission}`);
    }
  };
  
  return { 
    hasPermission, 
    hasAnyPermission, 
    hasAllPermissions, 
    requirePermission 
  };
};
```

#### Permission-Based Component Pattern
```typescript
// components/PermissionGuard.tsx
interface PermissionGuardProps {
  permission: string;
  fallback?: React.ReactNode;
  children: React.ReactNode;
}

export const PermissionGuard: React.FC<PermissionGuardProps> = ({
  permission,
  fallback = <AccessDenied />,
  children
}) => {
  const { hasPermission } = usePermissions();
  
  if (!hasPermission(permission)) {
    return <>{fallback}</>;
  }
  
  return <>{children}</>;
};

// Usage
<PermissionGuard permission="users.manage">
  <UserManagementPanel />
</PermissionGuard>
```

#### Standard Permission Naming Convention
Based on platform analysis, permissions follow `resource.action` format:

#### Admin Settings Navigation Pattern
```tsx
// Parent AdminSettingsPage.tsx - Container provider
export const AdminSettingsPage: React.FC = () => {
  return (
    <PageContainer 
      title="Admin Settings"
      subtitle="Configure system-wide settings and security options"
      breadcrumb={[
        { label: 'Admin Dashboard', href: '/app/admin' },
        { label: 'Settings' }
      ]}
    >
      {/* Tab navigation - rendered once at parent level */}
      <AdminSettingsTabs />
      
      {/* Tab content area */}
      <div className="mt-6">
        <Outlet /> {/* Child tab pages render here */}
      </div>
    </PageContainer>
  );
};

// Child AdminSettingsGeneralTabPage.tsx - Content only
export const AdminSettingsGeneralTabPage: React.FC = () => {
  return <GeneralSettings />; // Direct component return
};

// Child AdminSettingsRateLimitingTabPage.tsx - Permission check + content
export const AdminSettingsRateLimitingTabPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const canManageRateLimiting = hasPermissions(user, ['admin.settings.security']);
  
  if (!canManageRateLimiting) {
    return <Navigate to="/app/admin/settings" replace />;
  }
  
  return <RateLimitingSettings />;
};
```

```typescript
// Permission constants
export const PERMISSIONS = {
  // User Management
  USERS_READ: 'users.read',
  USERS_CREATE: 'users.create', 
  USERS_UPDATE: 'users.update',
  USERS_DELETE: 'users.delete',
  USERS_MANAGE: 'users.manage',
  
  // Billing Operations
  BILLING_READ: 'billing.read',
  BILLING_UPDATE: 'billing.update', 
  BILLING_MANAGE: 'billing.manage',
  INVOICES_CREATE: 'invoices.create',
  PAYMENTS_PROCESS: 'payments.process',
  
  // System Administration
  ADMIN_ACCESS: 'admin.access',
  SYSTEM_ADMIN: 'system.admin',
  ACCOUNTS_MANAGE: 'accounts.manage',
  
  // Content Management
  PAGES_CREATE: 'pages.create',
  PAGES_UPDATE: 'pages.update',
  PAGES_DELETE: 'pages.delete',
  CONTENT_MANAGE: 'content.manage',
  
  // Analytics
  ANALYTICS_READ: 'analytics.read',
  ANALYTICS_EXPORT: 'analytics.export',
  REPORTS_GENERATE: 'reports.generate'
} as const;

type Permission = typeof PERMISSIONS[keyof typeof PERMISSIONS];
```

#### Page-Level Access Control Pattern
```typescript
// pages/UserManagementPage.tsx
import { PermissionGuard } from '@/shared/components/PermissionGuard';
import { PERMISSIONS } from '@/shared/constants/permissions';

const UserManagementPage: React.FC = () => {
  return (
    <PermissionGuard permission={PERMISSIONS.USERS_MANAGE}>
      <PageContainer 
        title="User Management"
        actions={
          <PermissionGuard 
            permission={PERMISSIONS.USERS_CREATE}
            fallback={null}
          >
            <Button onClick={handleCreateUser}>Create User</Button>
          </PermissionGuard>
        }
      >
        <UserList />
      </PageContainer>
    </PermissionGuard>
  );
};
```

**CRITICAL VALIDATION**: Use these audit commands to ensure compliance:
```bash
# Find forbidden role-based access checks (should return empty)
grep -r "\.roles\?\.includes\|\.role.*==\|\.role.*!=" frontend/src/ | grep -v "formatRole\|getRoleColor"

# Find role-based access in components (should return empty for access control)
grep -r "currentUser.*roles\?\." frontend/src/ | grep -v "display\|format\|badge"

# Count permission-based access checks (should be > 0) 
grep -r "hasPermission\|permissions.*includes" frontend/src/ | wc -l

# Page container structure validation
grep -r "<PageContainer" src/pages/app/admin/ | grep -v "AdminSettingsPage.tsx"  # Should be empty
grep -r "<AdminSettingsTabs" src/pages/app/admin/ | grep -v "AdminSettingsPage.tsx"  # Should be empty
```

### 4. Page Layout Architecture (MANDATORY)

#### PageContainer - Universal Page Wrapper
**CRITICAL**: ALL application pages MUST use PageContainer for consistent layout, navigation, and user experience.

```tsx
// Standard page pattern - MANDATORY for ALL pages
import { PageContainer, BreadcrumbItem, PageAction } from '@/shared/components/layout/PageContainer';

export function StandardPage() {
  // Dynamic breadcrumbs based on navigation hierarchy
  const breadcrumbs: BreadcrumbItem[] = [
    {
      label: 'Dashboard',
      href: '/app',
      icon: HomeIcon
    },
    {
      label: 'Section Name',
      href: '/app/section'
    },
    {
      label: 'Current Page'  // No href for current page
    }
  ];

  // Consolidated actions in page header
  const actions: PageAction[] = [
    {
      id: 'back',
      label: 'Back',
      onClick: () => navigate(-1),
      variant: 'outline',
      icon: ArrowLeftIcon
    },
    {
      id: 'create',
      label: 'Create New',
      onClick: handleCreate,
      variant: 'primary',
      icon: PlusIcon
    }
  ];

  return (
    <PageContainer
      title="Page Title"
      description="Clear description of page purpose"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      {/* Page content follows standard patterns */}
      <div className="space-y-6">
        <ContentSection />
      </div>
    </PageContainer>
  );
}
```

#### Breadcrumb System Standards
**REQUIRED**: Follow hierarchical navigation patterns:
- **Dashboard** → **Section** → **Category/Filter** → **Current Page**
- **Clickable navigation** back to any parent level
- **Dynamic updates** for filters, search, or category selections
- **Icon integration** for visual hierarchy

#### Loading and Error State Patterns
```tsx
// MANDATORY: Consistent loading/error patterns with breadcrumbs
if (loading) {
  return (
    <PageContainer
      title="Loading..."
      breadcrumbs={baseBreadcrumbs}
    >
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-primary"></div>
      </div>
    </PageContainer>
  );
}

if (error) {
  return (
    <PageContainer
      title="Error"
      breadcrumbs={baseBreadcrumbs}
      actions={[{ 
        id: 'back', 
        label: 'Go Back', 
        onClick: () => navigate(-1), 
        variant: 'primary',
        icon: ArrowLeftIcon
      }]}
    >
      <div className="text-center py-12">
        <h3 className="text-lg font-medium text-theme-primary mb-2">{error}</h3>
      </div>
    </PageContainer>
  );
}
```

#### Content Organization Standards
```tsx
// Standard content structure within PageContainer
<PageContainer title="..." breadcrumbs={breadcrumbs} actions={actions}>
  {/* 1. Search/Filters Section */}
  <div className="bg-theme-surface rounded-lg border border-theme p-6">
    <SearchAndFilters />
  </div>

  {/* 2. Main Content Area */}
  <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
    <div className="lg:col-span-2">
      <MainContent />
    </div>
    <div className="space-y-6">
      <SidebarContent />
    </div>
  </div>

  {/* 3. Related/Additional Sections */}
  <div className="space-y-6">
    <RelatedContent />
  </div>
</PageContainer>
```

#### Admin Settings Container Hierarchy (CRITICAL)
**Special case for admin settings with tabs**: Follow strict container hierarchy to prevent duplicate navigation structures.

```tsx
// ✅ CORRECT: Parent page provides PageContainer + TabContainer
export const AdminSettingsPage: React.FC = () => {
  return (
    <PageContainer 
      title="Admin Settings"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'Admin Settings' }
      ]}
    >
      <AdminSettingsTabs />
      <div className="mt-6">
        <Outlet /> {/* Child tab pages render here */}
      </div>
    </PageContainer>
  );
};

// ✅ CORRECT: Tab page returns component content directly - NO containers
export const AdminSettingsGeneralTabPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const canAccessGeneral = user?.permissions?.includes('admin.settings.general');
  
  if (!canAccessGeneral) {
    return <Navigate to="/app/admin/settings" replace />;
  }
  
  return <GeneralSettings />; // Direct component return
};
```

#### Text Rendering Standards
**CRITICAL**: Handle user content that may contain markdown appropriately:

```tsx
import { stripMarkdown } from '@/shared/utils/markdownUtils';

// For card previews and excerpts - STRIP markdown
<p className="text-theme-secondary line-clamp-2">
  {stripMarkdown(content.excerpt)}
</p>

// For full content areas - RENDER markdown with ReactMarkdown
<ReactMarkdown
  remarkPlugins={[remarkGfm, remarkBreaks]}
  rehypePlugins={[rehypeHighlight, rehypeRaw]}
  components={customMarkdownComponents}
>
  {content.full_text}
</ReactMarkdown>
```

### 5. Routing and Navigation (MANDATORY)

#### React Router Setup
```tsx
// src/App.tsx
import React from 'react';
import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import { ThemeProvider } from '@/shared/hooks/ThemeContext';
import { AuthProvider } from '@/features/auth/hooks/useAuth';
import { NotificationProvider } from '@/shared/hooks/useNotification';

// Layout components
import { PublicLayout } from '@/shared/components/layout/PublicLayout';
import { DashboardLayout } from '@/shared/components/layout/DashboardLayout';
import { AdminLayout } from '@/shared/components/layout/AdminLayout';

// Route guards
import { ProtectedRoute } from '@/shared/components/ProtectedRoute';
import { AdminRoute } from '@/shared/components/AdminRoute';

// Page imports
import { LoginPage } from '@/pages/public/LoginPage';
import { RegisterPage } from '@/pages/public/RegisterPage';
import { DashboardPage } from '@/pages/app/DashboardPage';
import { SubscriptionsPage } from '@/pages/app/business/SubscriptionsPage';
import { AdminUsersPage } from '@/pages/app/admin/AdminUsersPage';

export const App: React.FC = () => {
  return (
    <ThemeProvider>
      <NotificationProvider>
        <AuthProvider>
          <Router>
            <Routes>
              {/* Public routes */}
              <Route path="/" element={<PublicLayout />}>
                <Route index element={<Navigate to="/login" replace />} />
                <Route path="login" element={<LoginPage />} />
                <Route path="register" element={<RegisterPage />} />
                <Route path="forgot-password" element={<ForgotPasswordPage />} />
                <Route path="reset-password" element={<ResetPasswordPage />} />
                <Route path="verify-email" element={<VerifyEmailPage />} />
              </Route>

              {/* Protected app routes */}
              <Route path="/app" element={
                <ProtectedRoute>
                  <DashboardLayout />
                </ProtectedRoute>
              }>
                <Route index element={<DashboardPage />} />
                <Route path="subscriptions" element={<SubscriptionsPage />} />
                <Route path="billing" element={<BillingPage />} />
                <Route path="analytics" element={<AnalyticsPage />} />
                <Route path="users" element={<UsersPage />} />
                <Route path="settings" element={<SettingsPage />} />
                
                {/* Admin routes */}
                <Route path="admin" element={<AdminRoute><AdminLayout /></AdminRoute>}>
                  <Route index element={<AdminDashboardPage />} />
                  <Route path="users" element={<AdminUsersPage />} />
                  <Route path="accounts" element={<AdminAccountsPage />} />
                  <Route path="settings" element={<AdminSettingsPage />} />
                </Route>
              </Route>

              {/* Catch-all redirect */}
              <Route path="*" element={<Navigate to="/app" replace />} />
            </Routes>
          </Router>
        </AuthProvider>
      </NotificationProvider>
    </ThemeProvider>
  );
};
```

#### Route Guards and Protection
```tsx
// src/shared/components/ProtectedRoute.tsx
import React from 'react';
import { Navigate, useLocation } from 'react-router-dom';
import { useAuth } from '@/features/auth/hooks/useAuth';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';

interface Props {
  children: React.ReactNode;
  fallback?: string;
}

export const ProtectedRoute: React.FC<Props> = ({ 
  children, 
  fallback = '/login' 
}) => {
  const { user, loading } = useAuth();
  const location = useLocation();

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  if (!user) {
    // Redirect to login with return path
    return <Navigate to={fallback} state={{ from: location }} replace />;
  }

  return <>{children}</>;
};

// src/shared/components/AdminRoute.tsx
import React from 'react';
import { useAuth } from '@/features/auth/hooks/useAuth';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { UnauthorizedPage } from '@/pages/public/UnauthorizedPage';

interface Props {
  children: React.ReactNode;
  requiredPermission?: string;
}

export const AdminRoute: React.FC<Props> = ({ 
  children, 
  requiredPermission = 'admin.access' 
}) => {
  const { user } = useAuth();
  const { hasPermission } = usePermissions();

  if (!user || !hasPermission(requiredPermission)) {
    return <UnauthorizedPage />;
  }

  return <>{children}</>;
};
```

### 5. State Management (MANDATORY)

#### Context-Based State Management
```tsx
// src/shared/hooks/ThemeContext.tsx
import React, { createContext, useContext, useReducer, useEffect } from 'react';

type Theme = 'light' | 'dark';

interface ThemeState {
  theme: Theme;
  systemTheme: Theme;
  effectiveTheme: Theme;
}

interface ThemeContextType extends ThemeState {
  setTheme: (theme: Theme | 'system') => void;
  toggleTheme: () => void;
}

const ThemeContext = createContext<ThemeContextType | undefined>(undefined);

type ThemeAction = 
  | { type: 'SET_THEME'; payload: Theme | 'system' }
  | { type: 'SET_SYSTEM_THEME'; payload: Theme }
  | { type: 'TOGGLE_THEME' };

function themeReducer(state: ThemeState, action: ThemeAction): ThemeState {
  switch (action.type) {
    case 'SET_THEME':
      const userTheme = action.payload === 'system' ? null : action.payload;
      const effectiveTheme = userTheme || state.systemTheme;
      
      // Persist user preference
      if (userTheme) {
        localStorage.setItem('theme', userTheme);
      } else {
        localStorage.removeItem('theme');
      }
      
      return {
        ...state,
        theme: userTheme || state.systemTheme,
        effectiveTheme
      };
      
    case 'SET_SYSTEM_THEME':
      const storedTheme = localStorage.getItem('theme') as Theme;
      const newEffectiveTheme = storedTheme || action.payload;
      
      return {
        ...state,
        systemTheme: action.payload,
        theme: storedTheme || action.payload,
        effectiveTheme: newEffectiveTheme
      };
      
    case 'TOGGLE_THEME':
      const nextTheme = state.effectiveTheme === 'light' ? 'dark' : 'light';
      localStorage.setItem('theme', nextTheme);
      
      return {
        ...state,
        theme: nextTheme,
        effectiveTheme: nextTheme
      };
      
    default:
      return state;
  }
}

export const ThemeProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [state, dispatch] = useReducer(themeReducer, {
    theme: 'light',
    systemTheme: 'light',
    effectiveTheme: 'light'
  });

  // Initialize theme from storage and system preference
  useEffect(() => {
    const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
    const systemTheme = mediaQuery.matches ? 'dark' : 'light';
    
    dispatch({ type: 'SET_SYSTEM_THEME', payload: systemTheme });
    
    const handleChange = (e: MediaQueryListEvent) => {
      dispatch({ type: 'SET_SYSTEM_THEME', payload: e.matches ? 'dark' : 'light' });
    };
    
    mediaQuery.addEventListener('change', handleChange);
    return () => mediaQuery.removeEventListener('change', handleChange);
  }, []);

  // Apply theme to document
  useEffect(() => {
    document.documentElement.setAttribute('data-theme', state.effectiveTheme);
    document.documentElement.classList.toggle('dark', state.effectiveTheme === 'dark');
  }, [state.effectiveTheme]);

  const setTheme = (theme: Theme | 'system') => {
    dispatch({ type: 'SET_THEME', payload: theme });
  };

  const toggleTheme = () => {
    dispatch({ type: 'TOGGLE_THEME' });
  };

  return (
    <ThemeContext.Provider value={{ ...state, setTheme, toggleTheme }}>
      {children}
    </ThemeContext.Provider>
  );
};

export const useTheme = () => {
  const context = useContext(ThemeContext);
  if (context === undefined) {
    throw new Error('useTheme must be used within a ThemeProvider');
  }
  return context;
};
```

#### Authentication Context
```tsx
// src/features/auth/hooks/useAuth.tsx
import React, { createContext, useContext, useReducer, useEffect } from 'react';
import { authApi } from '@/features/auth/services/authAPI';
import { User } from '@/shared/types';

interface AuthState {
  user: User | null;
  token: string | null;
  loading: boolean;
  error: string | null;
}

interface AuthContextType extends AuthState {
  login: (email: string, password: string) => Promise<void>;
  logout: () => void;
  register: (userData: RegisterData) => Promise<void>;
  refreshToken: () => Promise<void>;
  clearError: () => void;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

type AuthAction =
  | { type: 'AUTH_START' }
  | { type: 'AUTH_SUCCESS'; payload: { user: User; token: string } }
  | { type: 'AUTH_FAILURE'; payload: string }
  | { type: 'AUTH_LOGOUT' }
  | { type: 'AUTH_CLEAR_ERROR' };

function authReducer(state: AuthState, action: AuthAction): AuthState {
  switch (action.type) {
    case 'AUTH_START':
      return { ...state, loading: true, error: null };
      
    case 'AUTH_SUCCESS':
      // Store token securely
      localStorage.setItem('auth_token', action.payload.token);
      return {
        ...state,
        loading: false,
        error: null,
        user: action.payload.user,
        token: action.payload.token
      };
      
    case 'AUTH_FAILURE':
      return {
        ...state,
        loading: false,
        error: action.payload,
        user: null,
        token: null
      };
      
    case 'AUTH_LOGOUT':
      localStorage.removeItem('auth_token');
      return {
        ...state,
        user: null,
        token: null,
        loading: false,
        error: null
      };
      
    case 'AUTH_CLEAR_ERROR':
      return { ...state, error: null };
      
    default:
      return state;
  }
}

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [state, dispatch] = useReducer(authReducer, {
    user: null,
    token: null,
    loading: true,
    error: null
  });

  // Initialize auth state from stored token
  useEffect(() => {
    const initializeAuth = async () => {
      const storedToken = localStorage.getItem('auth_token');
      
      if (storedToken) {
        try {
          const response = await authApi.validateToken(storedToken);
          
          if (response.success) {
            dispatch({
              type: 'AUTH_SUCCESS',
              payload: {
                user: response.data.user,
                token: storedToken
              }
            });
          } else {
            // Token invalid, clear it
            localStorage.removeItem('auth_token');
            dispatch({ type: 'AUTH_LOGOUT' });
          }
        } catch (error) {
          localStorage.removeItem('auth_token');
          dispatch({ type: 'AUTH_LOGOUT' });
        }
      } else {
        dispatch({ type: 'AUTH_LOGOUT' });
      }
    };

    initializeAuth();
  }, []);

  const login = async (email: string, password: string) => {
    dispatch({ type: 'AUTH_START' });
    
    try {
      const response = await authApi.login({ email, password });
      
      if (response.success) {
        dispatch({
          type: 'AUTH_SUCCESS',
          payload: {
            user: response.data.user,
            token: response.data.token
          }
        });
      } else {
        dispatch({ type: 'AUTH_FAILURE', payload: response.error || 'Login failed' });
      }
    } catch (error) {
      dispatch({ 
        type: 'AUTH_FAILURE', 
        payload: error instanceof Error ? error.message : 'Login failed' 
      });
    }
  };

  const logout = () => {
    dispatch({ type: 'AUTH_LOGOUT' });
  };

  const register = async (userData: RegisterData) => {
    dispatch({ type: 'AUTH_START' });
    
    try {
      const response = await authApi.register(userData);
      
      if (!response.success) {
        dispatch({ type: 'AUTH_FAILURE', payload: response.error || 'Registration failed' });
      }
      // Note: Registration doesn't auto-login, user needs to verify email
    } catch (error) {
      dispatch({ 
        type: 'AUTH_FAILURE', 
        payload: error instanceof Error ? error.message : 'Registration failed' 
      });
    }
  };

  const refreshToken = async () => {
    if (!state.token) return;
    
    try {
      const response = await authApi.refreshToken(state.token);
      
      if (response.success) {
        dispatch({
          type: 'AUTH_SUCCESS',
          payload: {
            user: response.data.user,
            token: response.data.token
          }
        });
      }
    } catch (error) {
      logout();
    }
  };

  const clearError = () => {
    dispatch({ type: 'AUTH_CLEAR_ERROR' });
  };

  return (
    <AuthContext.Provider value={{
      ...state,
      login,
      logout,
      register,
      refreshToken,
      clearError
    }}>
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
};
```

### 6. Custom Hooks Patterns (MANDATORY)

#### API Data Fetching Hook
```tsx
// src/shared/hooks/useApi.tsx
import { useState, useEffect, useCallback } from 'react';
import { ApiResponse } from '@/shared/types';

interface UseApiOptions<T> {
  immediate?: boolean;
  onSuccess?: (data: T) => void;
  onError?: (error: string) => void;
}

interface UseApiReturn<T> {
  data: T | null;
  loading: boolean;
  error: string | null;
  execute: () => Promise<void>;
  reset: () => void;
}

export function useApi<T>(
  apiFunction: () => Promise<ApiResponse<T>>,
  options: UseApiOptions<T> = {}
): UseApiReturn<T> {
  const { immediate = true, onSuccess, onError } = options;
  
  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const execute = useCallback(async () => {
    setLoading(true);
    setError(null);
    
    try {
      const response = await apiFunction();
      
      if (response.success) {
        setData(response.data);
        onSuccess?.(response.data);
      } else {
        const errorMessage = response.error || 'Request failed';
        setError(errorMessage);
        onError?.(errorMessage);
      }
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : 'Request failed';
      setError(errorMessage);
      onError?.(errorMessage);
    } finally {
      setLoading(false);
    }
  }, [apiFunction, onSuccess, onError]);

  const reset = useCallback(() => {
    setData(null);
    setError(null);
    setLoading(false);
  }, []);

  useEffect(() => {
    if (immediate) {
      execute();
    }
  }, [execute, immediate]);

  return { data, loading, error, execute, reset };
}
```

#### Form Management Hook
```tsx
// src/shared/hooks/useForm.tsx
import { useState, useCallback, FormEvent } from 'react';

interface UseFormOptions<T> {
  initialValues: T;
  validate?: (values: T) => Record<keyof T, string>;
  onSubmit: (values: T) => Promise<void> | void;
}

interface UseFormReturn<T> {
  values: T;
  errors: Partial<Record<keyof T, string>>;
  loading: boolean;
  setValue: (field: keyof T, value: T[keyof T]) => void;
  setValues: (values: Partial<T>) => void;
  setError: (field: keyof T, error: string) => void;
  clearError: (field: keyof T) => void;
  handleSubmit: (e: FormEvent) => void;
  reset: () => void;
  isDirty: boolean;
  isValid: boolean;
}

export function useForm<T extends Record<string, any>>({
  initialValues,
  validate,
  onSubmit
}: UseFormOptions<T>): UseFormReturn<T> {
  const [values, setValues] = useState<T>(initialValues);
  const [errors, setErrors] = useState<Partial<Record<keyof T, string>>>({});
  const [loading, setLoading] = useState(false);
  const [isDirty, setIsDirty] = useState(false);

  const setValue = useCallback((field: keyof T, value: T[keyof T]) => {
    setValues(prev => ({ ...prev, [field]: value }));
    setIsDirty(true);
    
    // Clear field error when value changes
    if (errors[field]) {
      setErrors(prev => ({ ...prev, [field]: undefined }));
    }
  }, [errors]);

  const setFormValues = useCallback((newValues: Partial<T>) => {
    setValues(prev => ({ ...prev, ...newValues }));
    setIsDirty(true);
  }, []);

  const setError = useCallback((field: keyof T, error: string) => {
    setErrors(prev => ({ ...prev, [field]: error }));
  }, []);

  const clearError = useCallback((field: keyof T) => {
    setErrors(prev => ({ ...prev, [field]: undefined }));
  }, []);

  const validateForm = useCallback(() => {
    if (!validate) return true;
    
    const validationErrors = validate(values);
    setErrors(validationErrors);
    
    return Object.keys(validationErrors).length === 0;
  }, [values, validate]);

  const handleSubmit = useCallback(async (e: FormEvent) => {
    e.preventDefault();
    
    if (!validateForm()) return;
    
    setLoading(true);
    
    try {
      await onSubmit(values);
    } catch (error) {
      // Handle submission errors
      console.error('Form submission error:', error);
    } finally {
      setLoading(false);
    }
  }, [values, validateForm, onSubmit]);

  const reset = useCallback(() => {
    setValues(initialValues);
    setErrors({});
    setLoading(false);
    setIsDirty(false);
  }, [initialValues]);

  const isValid = Object.keys(errors).length === 0;

  return {
    values,
    errors,
    loading,
    setValue,
    setValues: setFormValues,
    setError,
    clearError,
    handleSubmit,
    reset,
    isDirty,
    isValid
  };
}
```

### 7. Performance Optimization (MANDATORY)

#### Code Splitting and Lazy Loading
```tsx
// src/pages/LazyPages.tsx
import { lazy } from 'react';

// Lazy load page components
export const DashboardPage = lazy(() => 
  import('@/pages/app/DashboardPage').then(m => ({ default: m.DashboardPage }))
);

export const SubscriptionsPage = lazy(() => 
  import('@/pages/app/business/SubscriptionsPage').then(m => ({ default: m.SubscriptionsPage }))
);

export const AnalyticsPage = lazy(() => 
  import('@/pages/app/business/AnalyticsPage').then(m => ({ default: m.AnalyticsPage }))
);

export const AdminUsersPage = lazy(() => 
  import('@/pages/app/admin/AdminUsersPage').then(m => ({ default: m.AdminUsersPage }))
);

// Loading fallback component
export const PageLoadingFallback: React.FC = () => (
  <div className="flex items-center justify-center min-h-screen">
    <div className="text-center">
      <LoadingSpinner size="lg" />
      <p className="mt-4 text-theme-secondary">Loading page...</p>
    </div>
  </div>
);
```

#### React.memo and Performance Patterns
```tsx
// src/shared/components/OptimizedComponent.tsx
import React, { memo, useMemo, useCallback } from 'react';

interface ExpensiveComponentProps {
  data: DataItem[];
  onItemSelect: (id: string) => void;
  filter: string;
}

const ExpensiveComponent: React.FC<ExpensiveComponentProps> = memo(({
  data,
  onItemSelect,
  filter
}) => {
  // Memoize expensive calculations
  const filteredData = useMemo(() => {
    return data.filter(item => 
      item.name.toLowerCase().includes(filter.toLowerCase())
    );
  }, [data, filter]);

  const sortedData = useMemo(() => {
    return [...filteredData].sort((a, b) => a.name.localeCompare(b.name));
  }, [filteredData]);

  // Memoize event handlers
  const handleItemClick = useCallback((id: string) => {
    onItemSelect(id);
  }, [onItemSelect]);

  return (
    <div className="space-y-2">
      {sortedData.map(item => (
        <ItemCard 
          key={item.id}
          item={item}
          onClick={handleItemClick}
        />
      ))}
    </div>
  );
});

ExpensiveComponent.displayName = 'ExpensiveComponent';

// Memoize sub-components
const ItemCard = memo<{ item: DataItem; onClick: (id: string) => void }>(({ 
  item, 
  onClick 
}) => {
  const handleClick = useCallback(() => {
    onClick(item.id);
  }, [item.id, onClick]);

  return (
    <div 
      className="p-4 border rounded cursor-pointer hover:bg-theme-surface"
      onClick={handleClick}
    >
      <h3>{item.name}</h3>
      <p>{item.description}</p>
    </div>
  );
});

ItemCard.displayName = 'ItemCard';
```

## Development Commands

### React Development Setup
```bash
# Create React application with TypeScript
npx create-react-app frontend --template typescript

# Install additional dependencies
npm install react-router-dom @types/react-router-dom
npm install @craco/craco
npm install tailwindcss @tailwindcss/forms @tailwindcss/typography

# Development server
npm start

# Type checking
npm run typecheck
npx tsc --noEmit

# Build for production
npm run build

# Bundle analysis
npm install --save-dev webpack-bundle-analyzer
npm run build && npx webpack-bundle-analyzer build/static/js/*.js
```

### Testing and Quality
```bash
# Run tests
npm test

# Test coverage
npm test -- --coverage

# Lint TypeScript
npm run lint

# Format code
npm run format
```

## Integration Points

### React Architect Coordinates With:
- **UI Component Developer**: Component library architecture, design system
- **Dashboard Specialist**: Data visualization components, chart integration  
- **Admin Panel Developer**: Admin interface architecture, role-based routing
- **Frontend Test Engineer**: Testing setup, component testing strategies
- **API Developer**: Type definitions, API integration patterns

## Quick Reference

### Component Template
```tsx
import React, { useState, useEffect } from 'react';
import { ComponentProps } from './types';
import { useComponentHook } from './hooks';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';

interface Props extends ComponentProps {
  className?: string;
}

export const ComponentName: React.FC<Props> = ({ 
  prop1, 
  className 
}) => {
  const [loading, setLoading] = useState(false);
  const { data, error } = useComponentHook();

  useEffect(() => {
    // Effects
  }, []);

  if (loading) return <LoadingSpinner />;
  if (error) return <ErrorAlert message={error} />;

  return (
    <div className={cn('base-styles', className)}>
      {/* Content */}
    </div>
  );
};
```

### Custom Hook Template
```tsx
import { useState, useEffect } from 'react';

interface UseHookReturn {
  data: any;
  loading: boolean;
  error: string | null;
}

export const useCustomHook = (param: string): UseHookReturn => {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    // Hook logic
  }, [param]);

  return { data, loading, error };
};
```

## Quick Reference

### Project Structure Commands
```bash
# Create new feature directory structure
mkdir -p src/features/new-feature/{components,hooks,services,types,utils}

# Create shared component structure  
mkdir -p src/shared/components/{ui,layout,forms,data-display}

# Verify project structure follows standards
find src/features -type d -name "components" | wc -l  # Count feature components directories
find src/shared -name "*.tsx" | head -5              # List shared components
```

### Essential Development Commands
```bash
# Frontend development - run from $POWERNODE_ROOT/frontend
cd $POWERNODE_ROOT/frontend && npm start             # Start development server
cd $POWERNODE_ROOT/frontend && npm test              # Run test suite
cd $POWERNODE_ROOT/frontend && npm run build         # Production build
cd $POWERNODE_ROOT/frontend && npm run lint          # TypeScript linting
cd $POWERNODE_ROOT/frontend && npm run type-check    # Type checking
```

### File Organization Standards
- **Components**: `PascalCase.tsx` (UserProfile.tsx)
- **Hooks**: `camelCase.ts` starting with 'use' (useUserProfile.ts) 
- **Services**: `camelCase.ts` ending with 'Api' (userApi.ts)
- **Types**: `PascalCase.ts` (User.ts, ApiResponse.ts)
- **Utils**: `camelCase.ts` (dateHelpers.ts)

### Import Path Aliases
```typescript
// Use path aliases instead of relative imports
import { Button } from '@/shared/components/ui/Button';
import { useAuth } from '@/features/auth/hooks/useAuth';
import { userApi } from '@/features/users/services/userApi';
```

## Architecture Validation Commands

### Component Structure Audits
```bash
# Page container hierarchy validation
grep -r "<PageContainer" src/pages/app/admin/ | wc -l
grep -r "return <PageContainer" src/pages/app/admin/AdminSettingsPage.tsx | wc -l  # Should be 1
grep -r "return.*<.*Settings.*/>" src/pages/app/admin/ | wc -l  # Tab pages direct returns

# Permission-based routing validation
grep -r "hasPermissions(user" src/pages/app/admin/ | wc -l
grep -r "<Navigate.*replace" src/pages/app/admin/ | wc -l

# Theme-aware component structure
grep -r "theme-.*" src/shared/components/ | wc -l
grep -r "bg-red-\|bg-blue-\|bg-green-\|bg-yellow-" src/ | grep -v "text-white" | wc -l  # Should be 0
```

### TypeScript Architecture Validation
```bash
# Type safety verification
find src/ -name "*.tsx" -o -name "*.ts" | xargs grep -l "any" | wc -l  # Should be minimal
grep -r "interface.*Props" src/shared/components/ | wc -l
grep -r "forwardRef<HTML.*Props>" src/shared/components/ | wc -l

# Import path alias usage
grep -r "@/shared/" src/ | wc -l
grep -r "@/features/" src/ | wc -l
grep -r "\.\.\./\.\.\./" src/ | wc -l  # Should be minimal
```

### State Management Validation
```bash
# Permission hook usage
grep -r "usePermissions()" src/ | wc -l
grep -r "hasPermission(" src/ | wc -l

# Context usage validation
grep -r "useAuth()" src/ | wc -l
grep -r "useTheme()" src/ | wc -l
grep -r "useNotification()" src/ | wc -l
```

### Performance Pattern Validation
```bash
# React.memo usage
grep -r "React.memo" src/shared/components/ | wc -l
grep -r "useMemo\|useCallback" src/shared/components/ | wc -l

# Lazy loading implementation
grep -r "lazy(() =>" src/pages/ | wc -l
grep -r "Suspense" src/ | wc -l
```

## React Architecture Critical Requirements

### 1. ABSOLUTE PROHIBITIONS
- ❌ **NO duplicate PageContainer** in admin tab pages
- ❌ **NO role-based access control** - permissions only
- ❌ **NO hardcoded colors** except `text-white` on colored backgrounds  
- ❌ **NO relative imports** beyond one level - use path aliases
- ❌ **NO any types** in component props or state
- ❌ **NO uncontrolled re-renders** - proper memo/callback usage

### 2. MANDATORY PATTERNS
- ✅ **Feature-based directory structure** with consistent organization
- ✅ **Permission-based access control** using `hasPermissions()` hook
- ✅ **Theme-aware styling** with `theme-*` classes exclusively
- ✅ **TypeScript strict mode** with proper interface definitions
- ✅ **Path alias imports** for all cross-feature dependencies
- ✅ **Container hierarchy** respecting parent/child relationships

### 3. ARCHITECTURAL VALIDATIONS
- Component structure follows established patterns
- Permission system used correctly throughout
- Type safety maintained across all components
- Performance optimizations properly implemented
- Theme integration consistent and complete

**ALWAYS REFERENCE ../TODO.md FOR CURRENT TASKS AND PRIORITIES**
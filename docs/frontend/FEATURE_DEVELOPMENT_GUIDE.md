# Feature Development Guide

**Standards and patterns for building features in Powernode frontend**

---

## Table of Contents

1. [Overview](#overview)
2. [Feature Structure](#feature-structure)
3. [Required Files](#required-files)
4. [Component Patterns](#component-patterns)
5. [Hook Patterns](#hook-patterns)
6. [Permission Integration](#permission-integration)
7. [Styling Guidelines](#styling-guidelines)
8. [Testing Requirements](#testing-requirements)

---

## Overview

Powernode frontend uses a feature-based architecture where each domain is self-contained with its own components, services, hooks, and types.

### Feature Domains

```
frontend/src/features/
├── account/           # User account, auth, profile
├── admin/             # System administration
├── ai/                # AI agents, workflows, monitoring
├── app/               # App shell, layout
├── baas/              # Billing-as-a-Service
├── business/          # Subscriptions, payments, invoices
├── content/           # CMS pages, blog, KB
├── delegations/       # Permission delegations
├── developer/         # API keys, webhooks, docs
├── devops/            # CI/CD, deployments
├── privacy/           # GDPR, consent management
├── supply-chain/      # Supply chain security
└── system/            # System settings, audit logs
```

---

## Feature Structure

### Standard Feature Layout

```
frontend/src/features/<domain>/
├── index.ts                    # Public exports
├── routes.tsx                  # Feature routes
│
├── components/                 # React components
│   ├── <Domain>List.tsx       # List view
│   ├── <Domain>Form.tsx       # Create/Edit form
│   ├── <Domain>Detail.tsx     # Detail view
│   └── <Domain>Card.tsx       # Card component
│
├── pages/                      # Page components
│   ├── <Domain>ListPage.tsx   # List page
│   ├── <Domain>CreatePage.tsx # Create page
│   └── <Domain>DetailPage.tsx # Detail page
│
├── services/                   # API services
│   └── <domain>Api.ts
│
├── hooks/                      # Custom hooks
│   └── use<Domain>.ts
│
└── types/                      # TypeScript types
    └── index.ts
```

### Example: AI Workflows Feature

```
frontend/src/features/ai/
├── index.ts
├── routes.tsx
│
├── workflows/
│   ├── components/
│   │   ├── WorkflowList.tsx
│   │   ├── WorkflowCard.tsx
│   │   ├── WorkflowBuilder.tsx
│   │   ├── WorkflowExecutionForm.tsx
│   │   └── WorkflowExecutionDetails.tsx
│   │
│   ├── pages/
│   │   ├── WorkflowsPage.tsx
│   │   ├── WorkflowCreatePage.tsx
│   │   └── WorkflowDetailPage.tsx
│   │
│   ├── services/
│   │   └── workflowsApi.ts
│   │
│   └── hooks/
│       ├── useWorkflows.ts
│       └── useWorkflowExecution.ts
│
├── agents/
│   └── ...
│
└── monitoring/
    └── ...
```

---

## Required Files

### Feature Index (index.ts)

Export public API for the feature:

```typescript
// frontend/src/features/<domain>/index.ts

// Components
export { DomainList } from './components/DomainList';
export { DomainCard } from './components/DomainCard';
export { DomainForm } from './components/DomainForm';

// Pages
export { DomainListPage } from './pages/DomainListPage';
export { DomainDetailPage } from './pages/DomainDetailPage';

// Hooks
export { useDomain } from './hooks/useDomain';

// Types
export type { Domain, CreateDomainRequest, UpdateDomainRequest } from './types';

// API
export { domainApi } from './services/domainApi';
```

### Feature Routes (routes.tsx)

```typescript
// frontend/src/features/<domain>/routes.tsx

import { lazy } from 'react';
import { RouteObject } from 'react-router-dom';
import { PermissionGuard } from '@/shared/components/PermissionGuard';

const DomainListPage = lazy(() => import('./pages/DomainListPage'));
const DomainCreatePage = lazy(() => import('./pages/DomainCreatePage'));
const DomainDetailPage = lazy(() => import('./pages/DomainDetailPage'));

export const domainRoutes: RouteObject[] = [
  {
    path: 'domain',
    children: [
      {
        index: true,
        element: (
          <PermissionGuard permission="domain.read">
            <DomainListPage />
          </PermissionGuard>
        ),
      },
      {
        path: 'new',
        element: (
          <PermissionGuard permission="domain.create">
            <DomainCreatePage />
          </PermissionGuard>
        ),
      },
      {
        path: ':id',
        element: (
          <PermissionGuard permission="domain.read">
            <DomainDetailPage />
          </PermissionGuard>
        ),
      },
    ],
  },
];
```

---

## Component Patterns

### List Page Pattern

```typescript
// pages/DomainListPage.tsx

import { useState, useEffect } from 'react';
import { PageContainer } from '@/shared/components/PageContainer';
import { Button } from '@/shared/components/Button';
import { DomainList } from '../components/DomainList';
import { useDomain } from '../hooks/useDomain';
import { usePermission } from '@/shared/hooks/usePermission';

export const DomainListPage = () => {
  const { items, loading, error, refresh } = useDomain();
  const canCreate = usePermission('domain.create');

  // Actions go in PageContainer
  const actions = (
    <>
      {canCreate && (
        <Button href="/domain/new" variant="primary">
          Create New
        </Button>
      )}
      <Button onClick={refresh} variant="secondary">
        Refresh
      </Button>
    </>
  );

  return (
    <PageContainer
      title="Domain Items"
      subtitle="Manage your domain items"
      actions={actions}
    >
      {error && <ErrorAlert message={error} />}

      <DomainList
        items={items}
        loading={loading}
        onItemClick={(item) => navigate(`/domain/${item.id}`)}
      />
    </PageContainer>
  );
};
```

### Detail Page Pattern

```typescript
// pages/DomainDetailPage.tsx

import { useParams } from 'react-router-dom';
import { PageContainer } from '@/shared/components/PageContainer';
import { useDomainDetail } from '../hooks/useDomainDetail';

export const DomainDetailPage = () => {
  const { id } = useParams<{ id: string }>();
  const { item, loading, error, update, remove } = useDomainDetail(id!);
  const canUpdate = usePermission('domain.update');
  const canDelete = usePermission('domain.delete');

  if (loading) return <LoadingSpinner />;
  if (error) return <ErrorPage message={error} />;
  if (!item) return <NotFoundPage />;

  const actions = (
    <>
      {canUpdate && (
        <Button onClick={() => setEditMode(true)}>Edit</Button>
      )}
      {canDelete && (
        <Button variant="danger" onClick={handleDelete}>Delete</Button>
      )}
    </>
  );

  return (
    <PageContainer
      title={item.name}
      subtitle={`ID: ${item.id}`}
      actions={actions}
      breadcrumbs={[
        { label: 'Domain', href: '/domain' },
        { label: item.name },
      ]}
    >
      <DomainDetail item={item} />
    </PageContainer>
  );
};
```

### Form Component Pattern

```typescript
// components/DomainForm.tsx

import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';

const schema = z.object({
  name: z.string().min(1, 'Name is required').max(100),
  description: z.string().optional(),
  status: z.enum(['active', 'inactive']),
});

type FormValues = z.infer<typeof schema>;

interface DomainFormProps {
  initialValues?: Partial<FormValues>;
  onSubmit: (values: FormValues) => Promise<void>;
  onCancel: () => void;
  isLoading?: boolean;
}

export const DomainForm = ({
  initialValues,
  onSubmit,
  onCancel,
  isLoading,
}: DomainFormProps) => {
  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: initialValues,
  });

  return (
    <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
      <div>
        <label className="text-theme-primary">Name</label>
        <input
          {...register('name')}
          className="input-theme"
          disabled={isLoading}
        />
        {errors.name && (
          <span className="text-theme-error">{errors.name.message}</span>
        )}
      </div>

      <div>
        <label className="text-theme-primary">Description</label>
        <textarea
          {...register('description')}
          className="input-theme"
          disabled={isLoading}
        />
      </div>

      <div className="flex gap-2 justify-end">
        <Button type="button" onClick={onCancel} disabled={isLoading}>
          Cancel
        </Button>
        <Button type="submit" variant="primary" loading={isLoading}>
          Save
        </Button>
      </div>
    </form>
  );
};
```

---

## Hook Patterns

### Data Fetching Hook

```typescript
// hooks/useDomain.ts

import { useState, useEffect, useCallback } from 'react';
import { domainApi } from '../services/domainApi';
import { Domain } from '../types';
import { useNotification } from '@/shared/hooks/useNotification';

export const useDomain = () => {
  const [items, setItems] = useState<Domain[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const { showNotification } = useNotification();

  const fetchItems = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const response = await domainApi.getAll();

      if (response.success) {
        setItems(response.data);
      } else {
        setError(response.error || 'Failed to fetch items');
      }
    } catch (err) {
      setError('An unexpected error occurred');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchItems();
  }, [fetchItems]);

  const create = useCallback(async (data: CreateDomainRequest) => {
    const response = await domainApi.create(data);
    if (response.success) {
      setItems(prev => [...prev, response.data]);
      showNotification('Item created successfully', 'success');
      return response.data;
    }
    throw new Error(response.error);
  }, [showNotification]);

  const update = useCallback(async (id: string, data: UpdateDomainRequest) => {
    const response = await domainApi.update(id, data);
    if (response.success) {
      setItems(prev => prev.map(item =>
        item.id === id ? response.data : item
      ));
      showNotification('Item updated successfully', 'success');
      return response.data;
    }
    throw new Error(response.error);
  }, [showNotification]);

  const remove = useCallback(async (id: string) => {
    const response = await domainApi.delete(id);
    if (response.success) {
      setItems(prev => prev.filter(item => item.id !== id));
      showNotification('Item deleted successfully', 'success');
    } else {
      throw new Error(response.error);
    }
  }, [showNotification]);

  return {
    items,
    loading,
    error,
    refresh: fetchItems,
    create,
    update,
    remove,
  };
};
```

### Detail Hook

```typescript
// hooks/useDomainDetail.ts

export const useDomainDetail = (id: string) => {
  const [item, setItem] = useState<Domain | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const fetchItem = async () => {
      try {
        setLoading(true);
        const response = await domainApi.getById(id);
        if (response.success) {
          setItem(response.data);
        } else {
          setError(response.error);
        }
      } catch (err) {
        setError('Failed to load item');
      } finally {
        setLoading(false);
      }
    };

    fetchItem();
  }, [id]);

  const update = async (data: UpdateDomainRequest) => {
    const response = await domainApi.update(id, data);
    if (response.success) {
      setItem(response.data);
      return response.data;
    }
    throw new Error(response.error);
  };

  return { item, loading, error, update };
};
```

---

## Permission Integration

### Permission Checks

```typescript
// CORRECT: Use permissions only
const canEdit = currentUser?.permissions?.includes('domain.update');
const canDelete = currentUser?.permissions?.includes('domain.delete');

// FORBIDDEN: Never use roles
// const isAdmin = currentUser?.roles?.includes('admin');
```

### PermissionGuard Component

```typescript
import { PermissionGuard } from '@/shared/components/PermissionGuard';

// Protect entire component
<PermissionGuard permission="domain.manage">
  <AdminPanel />
</PermissionGuard>

// Multiple permissions (any)
<PermissionGuard permissions={['domain.update', 'domain.delete']} requireAll={false}>
  <ActionButtons />
</PermissionGuard>

// Multiple permissions (all)
<PermissionGuard permissions={['domain.read', 'domain.update']} requireAll={true}>
  <EditableView />
</PermissionGuard>
```

### usePermission Hook

```typescript
import { usePermission } from '@/shared/hooks/usePermission';

const MyComponent = () => {
  const canCreate = usePermission('domain.create');
  const canManage = usePermission('domain.manage');

  return (
    <div>
      {canCreate && <CreateButton />}
      {canManage && <ManageSection />}
    </div>
  );
};
```

---

## Styling Guidelines

### Theme-Aware Colors

```tsx
// CORRECT: Use theme classes
<div className="bg-theme-surface text-theme-primary">
  <h1 className="text-theme-heading">Title</h1>
  <p className="text-theme-secondary">Description</p>
  <button className="bg-theme-primary-500 text-white">Action</button>
</div>

// FORBIDDEN: Hardcoded colors
// <div className="bg-white text-gray-900">
// <button className="bg-blue-500">
```

### Common Theme Classes

| Purpose | Class |
|---------|-------|
| Background | `bg-theme-surface`, `bg-theme-background` |
| Text primary | `text-theme-primary` |
| Text secondary | `text-theme-secondary` |
| Borders | `border-theme-border` |
| Headings | `text-theme-heading` |
| Success | `text-theme-success`, `bg-theme-success` |
| Error | `text-theme-error`, `bg-theme-error` |
| Warning | `text-theme-warning` |

### Component Styling

```tsx
// Use Tailwind classes with theme tokens
<Card className="bg-theme-surface border border-theme-border rounded-lg p-4">
  <CardHeader className="text-theme-heading text-lg font-semibold">
    {title}
  </CardHeader>
  <CardContent className="text-theme-secondary">
    {content}
  </CardContent>
</Card>
```

---

## Testing Requirements

### Component Tests

```typescript
// components/DomainList.test.tsx

import { render, screen } from '@testing-library/react';
import { DomainList } from './DomainList';

describe('DomainList', () => {
  const mockItems = [
    { id: '1', name: 'Item 1', status: 'active' },
    { id: '2', name: 'Item 2', status: 'inactive' },
  ];

  it('should render items', () => {
    render(<DomainList items={mockItems} loading={false} />);

    expect(screen.getByText('Item 1')).toBeInTheDocument();
    expect(screen.getByText('Item 2')).toBeInTheDocument();
  });

  it('should show loading state', () => {
    render(<DomainList items={[]} loading={true} />);

    expect(screen.getByTestId('loading-spinner')).toBeInTheDocument();
  });

  it('should show empty state', () => {
    render(<DomainList items={[]} loading={false} />);

    expect(screen.getByText('No items found')).toBeInTheDocument();
  });
});
```

### Hook Tests

```typescript
// hooks/useDomain.test.ts

import { renderHook, act, waitFor } from '@testing-library/react';
import { useDomain } from './useDomain';
import { domainApi } from '../services/domainApi';

jest.mock('../services/domainApi');

describe('useDomain', () => {
  it('should fetch items on mount', async () => {
    const mockItems = [{ id: '1', name: 'Test' }];
    (domainApi.getAll as jest.Mock).mockResolvedValue({
      success: true,
      data: mockItems,
    });

    const { result } = renderHook(() => useDomain());

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    expect(result.current.items).toEqual(mockItems);
  });

  it('should create item', async () => {
    const newItem = { id: '2', name: 'New' };
    (domainApi.create as jest.Mock).mockResolvedValue({
      success: true,
      data: newItem,
    });

    const { result } = renderHook(() => useDomain());

    await act(async () => {
      await result.current.create({ name: 'New' });
    });

    expect(result.current.items).toContainEqual(newItem);
  });
});
```

### Running Tests

```bash
# Run all tests
cd frontend && CI=true npm test

# Run specific feature tests
CI=true npm test -- --testPathPattern="features/domain"

# Run with coverage
CI=true npm test -- --coverage
```

---

## Checklist for New Features

- [ ] Create feature directory structure
- [ ] Add index.ts with public exports
- [ ] Create routes.tsx with PermissionGuard
- [ ] Implement API service with typed responses
- [ ] Create custom hooks for data fetching
- [ ] Build components with theme-aware styling
- [ ] Add permission checks (never roles)
- [ ] Write component and hook tests
- [ ] Document any new patterns

---

**Document Status**: Complete
**Last Updated**: 2025-01-30
**Source**: `frontend/src/features/`

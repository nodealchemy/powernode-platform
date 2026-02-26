# State Management Guide

**Redux Toolkit + React Query patterns for Powernode frontend**

---

Last Updated: 2026-02-26

## Table of Contents

1. [Overview](#overview)
2. [Store Architecture](#store-architecture)
3. [Slice Patterns](#slice-patterns)
4. [React Query Patterns](#react-query-patterns)
5. [Async Thunks](#async-thunks)
6. [Selectors](#selectors)
7. [Best Practices](#best-practices)

---

## Overview

Powernode uses a **dual state management** approach:
- **Redux Toolkit** — Global application state (auth, UI, configuration)
- **React Query / TanStack Query** — Server state, API data fetching, caching

### Key Principles

- **Redux for global state**: Auth tokens, UI preferences, app configuration
- **React Query for server state**: API data fetching, caching, mutations
- **Feature-based organization**: Slices and queries align with feature domains
- **Typed state**: Full TypeScript coverage
- **Selectors**: Memoized selectors for Redux performance
- **Global notifications**: Centralized notification system via Redux
- **WebSocket integration**: Real-time updates via ActionCable

---

## Store Architecture

### Store Configuration

**Location**: `frontend/src/shared/services/store.ts`

```typescript
import { configureStore } from '@reduxjs/toolkit';
import authReducer from './slices/authSlice';
import uiReducer from './slices/uiSlice';
import configReducer from './slices/configSlice';

export const store = configureStore({
  reducer: {
    auth: authReducer,
    ui: uiReducer,
    config: configReducer,
  },
  middleware: (getDefaultMiddleware) =>
    getDefaultMiddleware({
      serializableCheck: {
        ignoredActions: ['auth/login/fulfilled'],
      },
    }),
});

export type RootState = ReturnType<typeof store.getState>;
export type AppDispatch = typeof store.dispatch;
```

### Slice Directory

```
frontend/src/shared/services/slices/
├── authSlice.ts         # Authentication state (login, tokens, impersonation)
├── authSlice.test.ts
├── uiSlice.ts           # UI state (sidebar, theme, notifications)
├── uiSlice.test.ts
└── configSlice.ts       # Application configuration state
```

> **Note**: Domain-specific data (subscriptions, AI conversations, DevOps pipelines, etc.) is managed via React Query hooks within each feature module, not Redux slices. Redux is reserved for truly global application state.

---

## Slice Patterns

### Auth Slice

**File**: `frontend/src/shared/services/slices/authSlice.ts`

Manages authentication state including login, registration, tokens, and impersonation.

#### State Interface

```typescript
interface User {
  id: string;
  email: string;
  name: string;
  full_name?: string;
  roles: string[];
  permissions?: string[];
  status: string;
  email_verified: boolean;
  account: {
    id: string;
    name: string;
    status: string;
  };
}

interface ImpersonationState {
  isImpersonating: boolean;
  originalUser: User | null;
  impersonatedUser: User | null;
  sessionId: string | null;
  startedAt: string | null;
  expiresAt: string | null;
}

interface AuthState {
  user: User | null;
  access_token: string | null;
  refresh_token: string | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  error: string | null;
  resendingVerification: boolean;
  resendVerificationSuccess: boolean;
  resendCooldown: number;
  impersonation: ImpersonationState;
}
```

#### Async Thunks

```typescript
// Login
export const login = createAsyncThunk(
  'auth/login',
  async ({ email, password }: { email: string; password: string }) => {
    const response = await authApi.login({ email, password });
    return response.data.data || response.data;
  }
);

// Register
export const register = createAsyncThunk(
  'auth/register',
  async (userData: RegisterData, { rejectWithValue }) => {
    try {
      const response = await authApi.register(userData);
      return response.data.data || response.data;
    } catch (error) {
      return rejectWithValue(getErrorMessage(error));
    }
  }
);

// Get current user
export const getCurrentUser = createAsyncThunk(
  'auth/getCurrentUser',
  async (silentAuth: boolean = false, { rejectWithValue }) => {
    // ... implementation
  }
);

// Refresh token
export const refreshAccessToken = createAsyncThunk(
  'auth/refreshToken',
  async (_, { getState, rejectWithValue }) => {
    // ... implementation
  }
);

// Impersonation
export const startImpersonation = createAsyncThunk(
  'auth/startImpersonation',
  async ({ user_id, reason }: { user_id: string; reason?: string }) => {
    // ... implementation
  }
);

export const stopImpersonation = createAsyncThunk(
  'auth/stopImpersonation',
  async () => {
    // ... implementation
  }
);
```

#### Reducers

```typescript
const authSlice = createSlice({
  name: 'auth',
  initialState,
  reducers: {
    clearError: (state) => {
      state.error = null;
    },
    clearAuth: (state) => {
      state.user = null;
      state.access_token = null;
      state.refresh_token = null;
      state.isAuthenticated = false;
      localStorage.removeItem('access_token');
      localStorage.removeItem('refresh_token');
    },
    forceTokenClear: (state) => {
      // Force clear on invalid signatures
      state.user = null;
      state.access_token = null;
      state.refresh_token = null;
      state.isAuthenticated = false;
      state.error = 'Session expired. Please log in again.';
    },
  },
  extraReducers: (builder) => {
    builder
      .addCase(login.pending, (state) => {
        state.isLoading = true;
        state.error = null;
      })
      .addCase(login.fulfilled, (state, action) => {
        state.isLoading = false;
        state.isAuthenticated = true;
        state.user = action.payload.user;
        state.access_token = action.payload.access_token;
        state.refresh_token = action.payload.refresh_token;
        localStorage.setItem('access_token', action.payload.access_token);
        localStorage.setItem('refresh_token', action.payload.refresh_token);
      })
      .addCase(login.rejected, (state, action) => {
        state.isLoading = false;
        state.error = action.error.message || 'Login failed';
      });
      // ... more cases
  },
});
```

### UI Slice

**File**: `frontend/src/shared/services/slices/uiSlice.ts`

Manages UI state including sidebar, theme, loading, and notifications.

#### State Interface

```typescript
interface UIState {
  sidebarOpen: boolean;
  sidebarCollapsed: boolean;
  theme: 'light' | 'dark';
  loading: boolean;
  notifications: Array<{
    id: string;
    type: 'success' | 'error' | 'warning' | 'info';
    message: string;
    timestamp: number;
    details?: Record<string, any>;
  }>;
}
```

#### Reducers

```typescript
const uiSlice = createSlice({
  name: 'ui',
  initialState,
  reducers: {
    toggleSidebar: (state) => {
      state.sidebarOpen = !state.sidebarOpen;
    },
    setSidebarOpen: (state, action: PayloadAction<boolean>) => {
      state.sidebarOpen = action.payload;
    },
    toggleSidebarCollapse: (state) => {
      state.sidebarCollapsed = !state.sidebarCollapsed;
    },
    setTheme: (state, action: PayloadAction<'light' | 'dark'>) => {
      state.theme = action.payload;
    },
    setLoading: (state, action: PayloadAction<boolean>) => {
      state.loading = action.payload;
    },
    addNotification: (state, action) => {
      const notification = {
        ...action.payload,
        id: `${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
        timestamp: Date.now(),
      };
      state.notifications.push(notification);
    },
    removeNotification: (state, action: PayloadAction<string>) => {
      state.notifications = state.notifications.filter(
        (n) => n.id !== action.payload
      );
    },
    clearNotifications: (state) => {
      state.notifications = [];
    },
  },
});
```

---

## React Query Patterns

Domain-specific server state is managed via React Query (TanStack Query) within feature modules. This keeps API data fetching, caching, and mutations close to the components that use them.

### Query Pattern

```typescript
// features/ai/hooks/useConversations.ts
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { conversationApi } from '../services/conversationApi';

export const useConversations = () => {
  return useQuery({
    queryKey: ['conversations'],
    queryFn: conversationApi.getAll,
    staleTime: 5 * 60 * 1000, // 5 minutes
  });
};

export const useConversation = (id: string) => {
  return useQuery({
    queryKey: ['conversations', id],
    queryFn: () => conversationApi.getById(id),
    enabled: !!id,
  });
};
```

### Mutation Pattern

```typescript
export const useCreateConversation = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: conversationApi.create,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['conversations'] });
    },
  });
};
```

### Query Key Factory Pattern

```typescript
// Recommended pattern for organizing query keys
const CONVERSATION_KEYS = {
  all: ['conversations'] as const,
  lists: () => [...CONVERSATION_KEYS.all, 'list'] as const,
  list: (filters: ConversationFilters) => [...CONVERSATION_KEYS.lists(), filters] as const,
  details: () => [...CONVERSATION_KEYS.all, 'detail'] as const,
  detail: (id: string) => [...CONVERSATION_KEYS.details(), id] as const,
};
```

### Context API Usage

In addition to Redux and React Query, specific UI contexts handle scoped state:
- `FooterContext` — Footer visibility and content
- `ThemeContext` — Theme mode management
- `BreadcrumbContext` — Navigation breadcrumbs

### When to Use React Query vs Redux

| Use Case | Technology |
|----------|-----------|
| Auth tokens, user session | Redux (`authSlice`) |
| UI state (sidebar, theme, notifications) | Redux (`uiSlice`) |
| App configuration | Redux (`configSlice`) |
| API data lists (users, agents, pipelines) | React Query |
| Single resource details | React Query |
| Form submissions, mutations | React Query |
| Real-time WebSocket state | React Query + WebSocket invalidation |
| Scoped UI state (footer, breadcrumbs) | Context API |

---

## Async Thunks

### Pattern

```typescript
export const fetchData = createAsyncThunk(
  'domain/actionName',
  async (params: ParamType, { rejectWithValue, getState, dispatch }) => {
    try {
      const response = await apiService.getData(params);

      if (!response.success) {
        return rejectWithValue(response.error || 'Operation failed');
      }

      return response.data;
    } catch (error) {
      // Handle HTTP errors
      if (isErrorWithResponse(error) && error.response?.data) {
        return rejectWithValue(error.response.data);
      }
      return rejectWithValue(getErrorMessage(error));
    }
  }
);
```

### Error Handling

```typescript
// In extraReducers
.addCase(fetchData.rejected, (state, action) => {
  state.loading = false;

  // Handle structured error payload
  const payload = action.payload as { error?: string; message?: string } | string;

  if (typeof payload === 'object') {
    state.error = payload.error || payload.message || 'Operation failed';
  } else {
    state.error = payload || action.error.message || 'Operation failed';
  }
})
```

### Conditional Dispatch

```typescript
export const conditionalFetch = createAsyncThunk(
  'domain/conditionalFetch',
  async (_, { getState }) => {
    const state = getState() as RootState;

    // Skip if already loaded
    if (state.domain.data.length > 0) {
      return state.domain.data;
    }

    const response = await apiService.getData();
    return response.data;
  }
);
```

---

## Selectors

### Basic Selectors

```typescript
// In slice file or separate selectors file
export const selectUser = (state: RootState) => state.auth.user;
export const selectIsAuthenticated = (state: RootState) => state.auth.isAuthenticated;
export const selectIsLoading = (state: RootState) => state.auth.isLoading;
```

### Memoized Selectors

```typescript
import { createSelector } from '@reduxjs/toolkit';

// Base selector
const selectSubscriptions = (state: RootState) => state.subscription.subscriptions;

// Memoized selector
export const selectActiveSubscriptions = createSelector(
  [selectSubscriptions],
  (subscriptions) => subscriptions.filter(sub => sub.status === 'active')
);

export const selectSubscriptionById = createSelector(
  [selectSubscriptions, (_, id: string) => id],
  (subscriptions, id) => subscriptions.find(sub => sub.id === id)
);
```

### Usage in Components

```typescript
import { useSelector } from 'react-redux';
import { selectUser, selectIsAuthenticated } from '@/shared/services/slices/authSlice';

const MyComponent = () => {
  const user = useSelector(selectUser);
  const isAuthenticated = useSelector(selectIsAuthenticated);

  // ... component logic
};
```

---

## Best Practices

### 1. Type Safety

```typescript
// Always type your state
interface MyState {
  data: Item[];
  loading: boolean;
  error: string | null;
}

// Use PayloadAction for typed actions
reducers: {
  setData: (state, action: PayloadAction<Item[]>) => {
    state.data = action.payload;
  },
}
```

### 2. Immutable Updates

Redux Toolkit uses Immer, so you can write "mutating" code:

```typescript
// This is fine - Immer handles immutability
reducers: {
  addItem: (state, action: PayloadAction<Item>) => {
    state.items.push(action.payload);
  },
  updateItem: (state, action: PayloadAction<{ id: string; updates: Partial<Item> }>) => {
    const item = state.items.find(i => i.id === action.payload.id);
    if (item) {
      Object.assign(item, action.payload.updates);
    }
  },
}
```

### 3. Normalized State

For complex data, consider normalizing:

```typescript
interface NormalizedState {
  byId: Record<string, Item>;
  allIds: string[];
}

// Access pattern
const item = state.items.byId[itemId];
const allItems = state.items.allIds.map(id => state.items.byId[id]);
```

### 4. Loading States

Track loading per-operation:

```typescript
interface State {
  data: Item[];
  loadingStates: {
    fetch: boolean;
    create: boolean;
    update: Record<string, boolean>; // Per-item loading
    delete: Record<string, boolean>;
  };
}
```

### 5. Error Handling

Clear errors on new requests:

```typescript
.addCase(fetchData.pending, (state) => {
  state.loading = true;
  state.error = null; // Clear previous error
})
```

### 6. Local Storage Sync

For auth tokens:

```typescript
.addCase(login.fulfilled, (state, action) => {
  state.access_token = action.payload.access_token;
  localStorage.setItem('access_token', action.payload.access_token);
})
.addCase(logout.fulfilled, (state) => {
  state.access_token = null;
  localStorage.removeItem('access_token');
})
```

### 7. Typed Hooks

Create typed versions of useDispatch and useSelector:

```typescript
// hooks.ts
import { TypedUseSelectorHook, useDispatch, useSelector } from 'react-redux';
import type { RootState, AppDispatch } from './store';

export const useAppDispatch = () => useDispatch<AppDispatch>();
export const useAppSelector: TypedUseSelectorHook<RootState> = useSelector;
```

---

## Testing

### Slice Testing

```typescript
import reducer, {
  addNotification,
  removeNotification,
  clearNotifications,
} from './uiSlice';

describe('uiSlice', () => {
  const initialState = {
    sidebarOpen: false,
    sidebarCollapsed: false,
    theme: 'light' as const,
    loading: false,
    notifications: [],
  };

  it('should add notification', () => {
    const notification = { type: 'success' as const, message: 'Test' };
    const state = reducer(initialState, addNotification(notification));

    expect(state.notifications).toHaveLength(1);
    expect(state.notifications[0].message).toBe('Test');
    expect(state.notifications[0].id).toBeDefined();
  });

  it('should remove notification', () => {
    const stateWithNotification = {
      ...initialState,
      notifications: [{ id: '1', type: 'info' as const, message: 'Test', timestamp: Date.now() }],
    };

    const state = reducer(stateWithNotification, removeNotification('1'));
    expect(state.notifications).toHaveLength(0);
  });
});
```

### Thunk Testing

```typescript
import { fetchSubscriptions } from './subscriptionSlice';
import { subscriptionService } from '@/features/business/subscriptions/services/subscriptionService';

jest.mock('@/features/business/subscriptions/services/subscriptionService');

describe('fetchSubscriptions thunk', () => {
  it('should fetch subscriptions successfully', async () => {
    const mockData = [{ id: '1', status: 'active' }];
    (subscriptionService.getSubscriptions as jest.Mock).mockResolvedValue({
      success: true,
      data: mockData,
    });

    const dispatch = jest.fn();
    const getState = jest.fn();

    await fetchSubscriptions()(dispatch, getState, undefined);

    expect(dispatch).toHaveBeenCalledWith(
      expect.objectContaining({
        type: 'subscription/fetchSubscriptions/fulfilled',
        payload: mockData,
      })
    );
  });
});
```

---

**Document Status**: Complete
**Last Updated**: 2026-02-26
**Source**: `frontend/src/shared/services/slices/`, feature-level React Query hooks

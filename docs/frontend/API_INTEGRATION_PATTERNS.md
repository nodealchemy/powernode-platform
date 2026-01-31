# API Integration Patterns

**Feature-based API service architecture and patterns**

---

## Table of Contents

1. [Overview](#overview)
2. [Service Architecture](#service-architecture)
3. [API Client Pattern](#api-client-pattern)
4. [Response Handling](#response-handling)
5. [Error Handling](#error-handling)
6. [Authentication](#authentication)
7. [Best Practices](#best-practices)

---

## Overview

Powernode frontend uses a feature-based API service architecture where each feature domain has its own API service module. This ensures separation of concerns and makes API calls type-safe.

### Key Principles

- **Feature-scoped services**: Each feature has dedicated API services
- **Typed responses**: Full TypeScript coverage for requests and responses
- **Centralized client**: Shared axios instance with interceptors
- **Consistent error handling**: Standardized error format
- **Authentication integration**: Automatic token handling

---

## Service Architecture

### Directory Structure

```
frontend/src/features/
├── account/
│   └── auth/
│       └── services/
│           └── authAPI.ts
├── ai/
│   ├── agents/
│   │   └── services/
│   │       └── agentsApi.ts
│   └── workflows/
│       └── services/
│           └── workflowsApi.ts
├── business/
│   └── subscriptions/
│       └── services/
│           └── subscriptionService.ts
├── admin/
│   └── users/
│       └── services/
│           └── usersApi.ts
└── ...
```

### Service Pattern

```typescript
// feature/domain/services/domainApi.ts

import { apiClient } from '@/shared/services/apiClient';
import { ApiResponse } from '@/shared/types';

export interface Item {
  id: string;
  name: string;
  // ... other fields
}

export interface CreateItemRequest {
  name: string;
  // ... other fields
}

export interface UpdateItemRequest {
  name?: string;
  // ... other fields
}

class ItemsApi {
  private basePath = '/api/v1/items';

  async getItems(): Promise<ApiResponse<Item[]>> {
    const response = await apiClient.get<ApiResponse<Item[]>>(this.basePath);
    return response.data;
  }

  async getItem(id: string): Promise<ApiResponse<Item>> {
    const response = await apiClient.get<ApiResponse<Item>>(`${this.basePath}/${id}`);
    return response.data;
  }

  async createItem(data: CreateItemRequest): Promise<ApiResponse<Item>> {
    const response = await apiClient.post<ApiResponse<Item>>(this.basePath, data);
    return response.data;
  }

  async updateItem(id: string, data: UpdateItemRequest): Promise<ApiResponse<Item>> {
    const response = await apiClient.patch<ApiResponse<Item>>(`${this.basePath}/${id}`, data);
    return response.data;
  }

  async deleteItem(id: string): Promise<ApiResponse<void>> {
    const response = await apiClient.delete<ApiResponse<void>>(`${this.basePath}/${id}`);
    return response.data;
  }
}

export const itemsApi = new ItemsApi();
```

---

## API Client Pattern

### Shared API Client

**File**: `frontend/src/shared/services/apiClient.ts`

```typescript
import axios, { AxiosInstance, AxiosRequestConfig, AxiosError } from 'axios';

const BASE_URL = import.meta.env.VITE_API_URL || '/api/v1';

const createApiClient = (): AxiosInstance => {
  const client = axios.create({
    baseURL: BASE_URL,
    timeout: 30000,
    headers: {
      'Content-Type': 'application/json',
    },
  });

  // Request interceptor - add auth token
  client.interceptors.request.use(
    (config) => {
      const token = localStorage.getItem('access_token');
      if (token) {
        config.headers.Authorization = `Bearer ${token}`;
      }
      return config;
    },
    (error) => Promise.reject(error)
  );

  // Response interceptor - handle errors
  client.interceptors.response.use(
    (response) => response,
    async (error: AxiosError) => {
      const originalRequest = error.config as AxiosRequestConfig & { _retry?: boolean };

      // Handle 401 - token refresh
      if (error.response?.status === 401 && !originalRequest._retry) {
        originalRequest._retry = true;

        try {
          const refreshToken = localStorage.getItem('refresh_token');
          const response = await axios.post(`${BASE_URL}/auth/refresh`, {
            refresh_token: refreshToken,
          });

          const { access_token, refresh_token } = response.data.data;
          localStorage.setItem('access_token', access_token);
          localStorage.setItem('refresh_token', refresh_token);

          // Retry original request
          return client(originalRequest);
        } catch (refreshError) {
          // Refresh failed - redirect to login
          localStorage.removeItem('access_token');
          localStorage.removeItem('refresh_token');
          window.location.href = '/login';
          return Promise.reject(refreshError);
        }
      }

      return Promise.reject(error);
    }
  );

  return client;
};

export const apiClient = createApiClient();
```

### Request Configuration

```typescript
// Custom request with options
const response = await apiClient.get('/endpoint', {
  params: { page: 1, per_page: 20 },
  timeout: 60000,
  headers: { 'X-Custom-Header': 'value' },
});

// File upload
const formData = new FormData();
formData.append('file', file);

const response = await apiClient.post('/upload', formData, {
  headers: { 'Content-Type': 'multipart/form-data' },
  onUploadProgress: (progressEvent) => {
    const percentCompleted = Math.round((progressEvent.loaded * 100) / progressEvent.total!);
    setProgress(percentCompleted);
  },
});
```

---

## Response Handling

### Standard Response Format

Backend returns consistent response format:

```typescript
// Success response
interface ApiResponse<T> {
  success: true;
  data: T;
  message?: string;
  meta?: {
    pagination?: {
      current_page: number;
      total_pages: number;
      total_count: number;
      per_page: number;
    };
  };
}

// Error response
interface ApiErrorResponse {
  success: false;
  error: string;
  errors?: string[];
  details?: Record<string, unknown>;
}
```

### Response Type Guards

```typescript
export function isSuccessResponse<T>(
  response: ApiResponse<T> | ApiErrorResponse
): response is ApiResponse<T> {
  return response.success === true;
}

export function isErrorResponse(
  response: ApiResponse<unknown> | ApiErrorResponse
): response is ApiErrorResponse {
  return response.success === false;
}
```

### Usage in Components

```typescript
const loadItems = async () => {
  try {
    setLoading(true);
    const response = await itemsApi.getItems();

    if (response.success) {
      setItems(response.data);
      if (response.meta?.pagination) {
        setPagination(response.meta.pagination);
      }
    } else {
      showNotification(response.error || 'Failed to load items', 'error');
    }
  } catch (error) {
    showNotification(getErrorMessage(error), 'error');
  } finally {
    setLoading(false);
  }
};
```

---

## Error Handling

### Error Utilities

**File**: `frontend/src/shared/utils/errorHandling.ts`

```typescript
import { AxiosError } from 'axios';

interface ErrorWithResponse {
  response?: {
    data?: {
      error?: string;
      message?: string;
      errors?: string[];
    };
    status?: number;
  };
}

export function isErrorWithResponse(error: unknown): error is ErrorWithResponse {
  return (
    typeof error === 'object' &&
    error !== null &&
    'response' in error
  );
}

export function getErrorMessage(error: unknown): string {
  if (isErrorWithResponse(error)) {
    const data = error.response?.data;
    if (data?.error) return data.error;
    if (data?.message) return data.message;
    if (data?.errors?.length) return data.errors.join(', ');
  }

  if (error instanceof Error) {
    return error.message;
  }

  return 'An unexpected error occurred';
}

export function getValidationErrors(error: unknown): Record<string, string[]> {
  if (isErrorWithResponse(error) && error.response?.data?.errors) {
    // Handle Rails-style validation errors
    return error.response.data.errors as Record<string, string[]>;
  }
  return {};
}

export function isNetworkError(error: unknown): boolean {
  return (
    error instanceof Error &&
    (error.message === 'Network Error' || error.message.includes('ECONNREFUSED'))
  );
}

export function isTimeoutError(error: unknown): boolean {
  return (
    error instanceof Error &&
    (error.message.includes('timeout') || error.message.includes('ETIMEDOUT'))
  );
}
```

### Error Handling in Services

```typescript
class ItemsApi {
  async getItems(): Promise<ApiResponse<Item[]> | ApiErrorResponse> {
    try {
      const response = await apiClient.get<ApiResponse<Item[]>>(this.basePath);
      return response.data;
    } catch (error) {
      // Return error in consistent format
      return {
        success: false,
        error: getErrorMessage(error),
      };
    }
  }
}
```

### Form Error Handling

```typescript
const handleSubmit = async (values: FormValues) => {
  try {
    const response = await itemsApi.createItem(values);

    if (response.success) {
      showNotification('Item created successfully', 'success');
      onSuccess(response.data);
    } else {
      // Show general error
      setError(response.error);
    }
  } catch (error) {
    if (isErrorWithResponse(error) && error.response?.status === 422) {
      // Handle validation errors
      const validationErrors = getValidationErrors(error);
      Object.entries(validationErrors).forEach(([field, messages]) => {
        setFieldError(field, messages[0]);
      });
    } else {
      setError(getErrorMessage(error));
    }
  }
};
```

---

## Authentication

### Auth API Service

**File**: `frontend/src/features/account/auth/services/authAPI.ts`

```typescript
import { apiClient } from '@/shared/services/apiClient';

interface LoginRequest {
  email: string;
  password: string;
}

interface LoginResponse {
  success: boolean;
  data: {
    user: User;
    access_token: string;
    refresh_token: string;
  };
}

interface RegisterRequest {
  email: string;
  password: string;
  name: string;
  account_name: string;
  plan_id?: string;
}

class AuthApi {
  async login(credentials: LoginRequest) {
    return apiClient.post<LoginResponse>('/auth/login', credentials);
  }

  async register(userData: RegisterRequest) {
    return apiClient.post('/auth/register', userData);
  }

  async logout() {
    return apiClient.post('/auth/logout');
  }

  async refreshToken(refreshToken: string) {
    return apiClient.post('/auth/refresh', { refresh_token: refreshToken });
  }

  async getCurrentUser(silentAuth = false) {
    return apiClient.get('/auth/me', {
      headers: silentAuth ? { 'X-Silent-Auth': 'true' } : undefined,
    });
  }

  async resendVerification() {
    return apiClient.post('/auth/resend-verification');
  }

  async verify2FA(verificationToken: string, code: string) {
    return apiClient.post('/auth/verify-2fa', {
      verification_token: verificationToken,
      code,
    });
  }
}

export const authApi = new AuthApi();
```

### Impersonation API

```typescript
class ImpersonationApi {
  async startImpersonation(data: { user_id: string; reason?: string }) {
    const response = await apiClient.post('/admin/impersonation/start', data);
    return response.data;
  }

  async stopImpersonation(sessionToken: string) {
    const response = await apiClient.post('/admin/impersonation/stop', {
      session_token: sessionToken,
    });
    return response.data;
  }

  async validateToken(token: string) {
    const response = await apiClient.get('/admin/impersonation/validate', {
      headers: { 'X-Impersonation-Token': token },
    });
    return response.data;
  }
}

export const impersonationApi = new ImpersonationApi();
```

---

## Best Practices

### 1. Type All Requests and Responses

```typescript
// Good
interface CreateWorkflowRequest {
  name: string;
  description?: string;
  nodes: WorkflowNode[];
}

async createWorkflow(data: CreateWorkflowRequest): Promise<ApiResponse<Workflow>> {
  // ...
}

// Bad
async createWorkflow(data: any): Promise<any> {
  // ...
}
```

### 2. Use Consistent Base Paths

```typescript
class MyApi {
  private basePath = '/api/v1/my-resource';

  // All methods use basePath
  async getAll() {
    return apiClient.get(this.basePath);
  }

  async getOne(id: string) {
    return apiClient.get(`${this.basePath}/${id}`);
  }
}
```

### 3. Handle Loading States

```typescript
const [loading, setLoading] = useState({
  list: false,
  create: false,
  update: {} as Record<string, boolean>,
  delete: {} as Record<string, boolean>,
});

const createItem = async (data: CreateItemRequest) => {
  setLoading(prev => ({ ...prev, create: true }));
  try {
    const response = await itemsApi.createItem(data);
    // ...
  } finally {
    setLoading(prev => ({ ...prev, create: false }));
  }
};
```

### 4. Use Query Parameters Properly

```typescript
interface ListParams {
  page?: number;
  per_page?: number;
  search?: string;
  status?: string;
  sort_by?: string;
  sort_order?: 'asc' | 'desc';
}

async getItems(params: ListParams = {}): Promise<ApiResponse<Item[]>> {
  const response = await apiClient.get(this.basePath, { params });
  return response.data;
}
```

### 5. Cache When Appropriate

```typescript
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';

// Using React Query for caching
const useItems = () => {
  return useQuery({
    queryKey: ['items'],
    queryFn: () => itemsApi.getItems(),
    staleTime: 5 * 60 * 1000, // 5 minutes
  });
};

const useCreateItem = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (data: CreateItemRequest) => itemsApi.createItem(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['items'] });
    },
  });
};
```

### 6. Abort Requests on Unmount

```typescript
useEffect(() => {
  const controller = new AbortController();

  const fetchData = async () => {
    try {
      const response = await apiClient.get('/items', {
        signal: controller.signal,
      });
      setData(response.data);
    } catch (error) {
      if (!axios.isCancel(error)) {
        setError(getErrorMessage(error));
      }
    }
  };

  fetchData();

  return () => controller.abort();
}, []);
```

---

## Testing

### Mock API Client

```typescript
// __mocks__/apiClient.ts
export const apiClient = {
  get: jest.fn(),
  post: jest.fn(),
  patch: jest.fn(),
  delete: jest.fn(),
};
```

### Service Testing

```typescript
import { itemsApi } from './itemsApi';
import { apiClient } from '@/shared/services/apiClient';

jest.mock('@/shared/services/apiClient');

describe('itemsApi', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('should fetch items', async () => {
    const mockItems = [{ id: '1', name: 'Item 1' }];
    (apiClient.get as jest.Mock).mockResolvedValue({
      data: { success: true, data: mockItems },
    });

    const response = await itemsApi.getItems();

    expect(apiClient.get).toHaveBeenCalledWith('/api/v1/items');
    expect(response.success).toBe(true);
    expect(response.data).toEqual(mockItems);
  });

  it('should create item', async () => {
    const newItem = { name: 'New Item' };
    const createdItem = { id: '2', name: 'New Item' };

    (apiClient.post as jest.Mock).mockResolvedValue({
      data: { success: true, data: createdItem },
    });

    const response = await itemsApi.createItem(newItem);

    expect(apiClient.post).toHaveBeenCalledWith('/api/v1/items', newItem);
    expect(response.data).toEqual(createdItem);
  });
});
```

---

**Document Status**: Complete
**Last Updated**: 2025-01-30
**Source**: `frontend/src/features/*/services/`

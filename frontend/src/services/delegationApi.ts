import { api } from './api';

// Helper function for making API requests
const apiRequest = async (endpoint: string, options: RequestInit = {}) => {
  try {
    const method = (options.method || 'GET').toLowerCase();
    const data = options.body ? JSON.parse(options.body as string) : undefined;
    
    let response;
    switch (method) {
      case 'get':
        response = await api.get(endpoint);
        break;
      case 'post':
        response = await api.post(endpoint, data);
        break;
      case 'patch':
        response = await api.patch(endpoint, data);
        break;
      case 'put':
        response = await api.put(endpoint, data);
        break;
      case 'delete':
        response = await api.delete(endpoint);
        break;
      default:
        response = await api.get(endpoint);
    }
    
    return response.data;
  } catch (error: any) {
    if (error.response?.data) {
      throw new Error(error.response.data.message || error.response.data.error || 'API request failed');
    }
    throw error;
  }
};

// Types matching the new role-based delegation system
export interface Role {
  id: string;
  name: string;
  description: string;
}

export interface DelegatedUser {
  id: string;
  email: string;
  full_name: string;
}

export interface Delegation {
  id: string;
  account: {
    id: string;
    name: string;
    subdomain: string;
  };
  delegated_user: DelegatedUser;
  delegated_by: DelegatedUser;
  role: Role | null;
  permissions?: Permission[];
  status: string;
  expires_at: string | null;
  revoked_at: string | null;
  revoked_by: DelegatedUser | null;
  notes: string | null;
  is_active: boolean;
  is_expired: boolean;
  created_at: string;
  updated_at: string;
  // Legacy properties for backward compatibility with old components
  name?: string;
  description?: string;
  sourceAccountId?: string;
  sourceAccountName?: string;
  targetAccountId?: string;
  targetAccountName?: string;
  users?: Array<{ 
    userId?: string; 
    id?: string; 
    email: string; 
    name?: string; 
    firstName?: string;
    lastName?: string;
    role?: string;
    addedAt?: string;
  }>;
  createdAt?: string; // camelCase alias for created_at
  updatedAt?: string; // camelCase alias for updated_at
  expiresAt?: string; // camelCase alias for expires_at
  createdByName?: string;
  revokedByName?: string;
  revokedAt?: string; // camelCase alias for revoked_at
}

export interface Permission {
  id: string;
  resource: string;
  action: string;
  description: string;
  key: string;
}

export interface DelegationFormData {
  delegated_user_email: string;
  role_id?: string;
  permission_ids?: string[];
  expires_at?: string;
  notes?: string;
}

export interface DelegationsResponse {
  delegations: Delegation[];
  meta: {
    total_count: number;
    active_count: number;
    expired_count: number;
  };
}

export interface DelegationResponse {
  delegation: Delegation;
  message?: string;
}

export interface DelegationActivity {
  id: string;
  action: string;
  description: string;
  performed_by: string;
  performed_at: string;
  // Legacy camelCase properties for backward compatibility
  performedBy?: string;
  performedByName?: string;
  performedAt?: string;
  details?: string;
  timestamp?: string;
}

export interface DelegationRequest {
  id: string;
  requesterEmail: string;
  requestedByName?: string;
  requestedByEmail?: string;
  targetAccountId: string;
  permissions: string[];
  status: 'pending' | 'approved' | 'rejected';
  message?: string;
  createdAt: string;
  delegation: {
    name: string;
    description: string;
    sourceAccountName?: string;
    expiresAt?: string;
    permissions: string[];
    users?: Array<{ 
      id?: string; 
      name?: string; 
      firstName?: string;
      lastName?: string;
      email: string; 
      role?: string;
    }>;
  };
}

export interface User {
  id: string;
  email: string;
  firstName: string;
  lastName: string;
  role: string;
}

export const delegationApi = {
  // List all delegations for the current account
  async getDelegations(filters?: { status?: string; role_id?: string }): Promise<DelegationsResponse> {
    const params = new URLSearchParams();
    if (filters?.status) params.append('status', filters.status);
    if (filters?.role_id) params.append('role_id', filters.role_id);
    
    const queryString = params.toString();
    const endpoint = `/api/v1/accounts/current/delegations${queryString ? `?${queryString}` : ''}`;
    
    return apiRequest(endpoint);
  },

  // Get a specific delegation by ID
  async getDelegation(delegationId: string): Promise<DelegationResponse> {
    return apiRequest(`/api/v1/accounts/current/delegations/${delegationId}`);
  },

  // Create a new delegation
  async createDelegation(data: DelegationFormData): Promise<DelegationResponse> {
    return apiRequest('/api/v1/accounts/current/delegations', {
      method: 'POST',
      body: JSON.stringify({ delegation: data }),
    });
  },

  // Update an existing delegation
  async updateDelegation(delegationId: string, updates: Partial<DelegationFormData>): Promise<DelegationResponse> {
    return apiRequest(`/api/v1/accounts/current/delegations/${delegationId}`, {
      method: 'PATCH',
      body: JSON.stringify({ delegation: updates }),
    });
  },

  // Delete a delegation (revoke it)
  async deleteDelegation(delegationId: string): Promise<{ message: string }> {
    return apiRequest(`/api/v1/accounts/current/delegations/${delegationId}`, {
      method: 'DELETE',
    });
  },

  // Activate a delegation
  async activateDelegation(delegationId: string): Promise<DelegationResponse> {
    return apiRequest(`/api/v1/accounts/current/delegations/${delegationId}/activate`, {
      method: 'PATCH',
    });
  },

  // Deactivate a delegation
  async deactivateDelegation(delegationId: string): Promise<DelegationResponse> {
    return apiRequest(`/api/v1/accounts/current/delegations/${delegationId}/deactivate`, {
      method: 'PATCH',
    });
  },

  // Revoke a delegation
  async revokeDelegation(delegationId: string): Promise<DelegationResponse> {
    return apiRequest(`/api/v1/accounts/current/delegations/${delegationId}/revoke`, {
      method: 'PATCH',
    });
  },

  // Get available roles that can be delegated
  async getAvailableRoles(): Promise<Role[]> {
    const response = await apiRequest('/api/v1/roles');
    // Filter out Owner role as it cannot be delegated
    return response.filter((role: Role) => role.name !== 'Owner');
  },

  // Get available permissions for delegation (optionally filtered by role)
  async getAvailablePermissions(roleId?: string): Promise<Permission[]> {
    const params = roleId ? `?role_id=${roleId}` : '';
    return apiRequest(`/api/v1/accounts/current/delegations/available_permissions${params}`);
  },

  // Add permission to delegation
  async addPermissionToDelegation(delegationId: string, permissionId: string): Promise<DelegationResponse> {
    return apiRequest(`/api/v1/accounts/current/delegations/${delegationId}/permissions`, {
      method: 'POST',
      body: JSON.stringify({ permission_id: permissionId }),
    });
  },

  // Remove permission from delegation
  async removePermissionFromDelegation(delegationId: string, permissionId: string): Promise<DelegationResponse> {
    return apiRequest(`/api/v1/accounts/current/delegations/${delegationId}/permissions/${permissionId}`, {
      method: 'DELETE',
    });
  },

  // Get delegation activity log
  async getDelegationActivity(delegationId: string): Promise<{ activities: DelegationActivity[] }> {
    return apiRequest(`/api/v1/accounts/current/delegations/${delegationId}/activity`);
  },

  // Search accounts (placeholder - implement based on backend)
  async searchAccounts(query: string): Promise<{ accounts: any[] }> {
    return apiRequest(`/api/v1/accounts/search?q=${encodeURIComponent(query)}`);
  },

  // Get available users for an account (placeholder - implement based on backend)
  async getAvailableUsers(accountId: string): Promise<{ users: User[] }> {
    return apiRequest(`/api/v1/accounts/${accountId}/users`);
  },


  // Create delegation request (placeholder - implement based on backend)
  async createDelegationRequest(data: any): Promise<{ request: DelegationRequest }> {
    return apiRequest('/api/v1/delegation-requests', {
      method: 'POST',
      body: JSON.stringify(data),
    });
  },

  // Add users to delegation (placeholder - implement based on backend)
  async addUsersToDelegation(delegationId: string, userIds: string[]): Promise<DelegationResponse> {
    return apiRequest(`/api/v1/accounts/current/delegations/${delegationId}/users`, {
      method: 'POST',
      body: JSON.stringify({ user_ids: userIds }),
    });
  },

  // Remove user from delegation (placeholder - implement based on backend)
  async removeUserFromDelegation(delegationId: string, userId: string): Promise<DelegationResponse> {
    return apiRequest(`/api/v1/accounts/current/delegations/${delegationId}/users/${userId}`, {
      method: 'DELETE',
    });
  },

  // Get delegation requests with optional status filter
  async getDelegationRequests(status?: string): Promise<{ requests: DelegationRequest[] }> {
    const params = status ? `?status=${status}` : '';
    return apiRequest(`/api/v1/delegation-requests${params}`);
  },

  // Approve delegation request
  async approveDelegationRequest(requestId: string, note?: string): Promise<{ request: DelegationRequest }> {
    return apiRequest(`/api/v1/delegation-requests/${requestId}/approve`, {
      method: 'POST',
      body: JSON.stringify({ note }),
    });
  },

  // Reject delegation request
  async rejectDelegationRequest(requestId: string, reason: string): Promise<{ request: DelegationRequest }> {
    return apiRequest(`/api/v1/delegation-requests/${requestId}/reject`, {
      method: 'POST',
      body: JSON.stringify({ reason }),
    });
  },
};

// Helper functions for delegation status and permissions
export const delegationHelpers = {
  getStatusColor(delegation: Delegation): string {
    if (delegation.status === 'revoked') return 'text-theme-error bg-theme-error-background border-theme-error-border';
    if (delegation.is_expired) return 'text-theme-warning bg-theme-warning-background border-theme-warning-border';
    if (delegation.status === 'inactive') return 'text-theme-secondary bg-theme-surface border-theme';
    if (delegation.is_active) return 'text-theme-success bg-theme-success-background border-theme-success-border';
    return 'text-theme-secondary bg-theme-surface border-theme';
  },

  getRoleColor(roleName: string): string {
    switch (roleName) {
      case 'Admin': return 'bg-theme-error-background text-theme-error border-theme-error-border';
      case 'Member': return 'bg-theme-info-background text-theme-info border-theme-info-border';
      default: return 'bg-theme-surface text-theme-secondary border-theme';
    }
  },

  getStatusText(delegation: Delegation): string {
    if (delegation.status === 'revoked') return 'Revoked';
    if (delegation.is_expired) return 'Expired';
    if (delegation.status === 'inactive') return 'Inactive';
    if (delegation.is_active) return 'Active';
    return delegation.status.charAt(0).toUpperCase() + delegation.status.slice(1);
  },

  formatExpirationDate(expiresAt: string | null): string {
    if (!expiresAt) return 'Never';
    
    const date = new Date(expiresAt);
    const now = new Date();
    const diffTime = date.getTime() - now.getTime();
    const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));

    if (diffDays < 0) return 'Expired';
    if (diffDays === 0) return 'Expires today';
    if (diffDays === 1) return 'Expires tomorrow';
    if (diffDays <= 7) return `Expires in ${diffDays} days`;
    
    return date.toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric'
    });
  },

  canPerformAction(delegation: Delegation, action: 'activate' | 'deactivate' | 'revoke' | 'edit'): boolean {
    switch (action) {
      case 'activate':
        return delegation.status === 'inactive' && !delegation.is_expired;
      case 'deactivate':
        return delegation.status === 'active' && !delegation.is_expired;
      case 'revoke':
        return delegation.status !== 'revoked';
      case 'edit':
        return delegation.status !== 'revoked';
      default:
        return false;
    }
  },

  getDelegationPriority(delegation: Delegation): number {
    // Higher numbers = higher priority for sorting
    if (delegation.status === 'revoked') return 1;
    if (delegation.is_expired) return 2;
    if (delegation.status === 'inactive') return 3;
    if (delegation.is_active) return 4;
    return 0;
  },
};

// Legacy constant for backward compatibility - consider updating components to use the new permission system
export const DELEGATION_PERMISSIONS = [
  {
    key: 'users.read',
    label: 'View Users',
    description: 'View user information and profiles',
  },
  {
    key: 'users.create',
    label: 'Create Users',
    description: 'Create new user accounts',
  },
  {
    key: 'users.update',
    label: 'Update Users',
    description: 'Modify user information and settings',
  },
  {
    key: 'users.delete',
    label: 'Delete Users',
    description: 'Remove user accounts',
  },
  {
    key: 'accounts.read',
    label: 'View Account',
    description: 'View account information and settings',
  },
  {
    key: 'accounts.update',
    label: 'Manage Account',
    description: 'Modify account settings and configuration',
  },
  {
    key: 'billing.read',
    label: 'View Billing',
    description: 'View billing information and invoices',
  },
  {
    key: 'billing.update',
    label: 'Manage Billing',
    description: 'Modify billing settings and payment methods',
  },
  {
    key: 'analytics.read',
    label: 'View Analytics',
    description: 'View analytics and reporting data',
  },
  {
    key: 'analytics.global',
    label: 'Global Analytics',
    description: 'Access all analytics across the platform',
  },
];

export default delegationApi;
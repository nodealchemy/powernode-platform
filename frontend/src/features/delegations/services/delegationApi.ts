import { api } from '@/shared/services/api';

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
  } catch (error) {
    const apiError = error as {
      response?: { data?: { message?: string; error?: string; details?: string[] | string } };
    };
    if (apiError.response?.data) {
      const { message, error: errorLabel, details } = apiError.response.data;
      // THE REASON IS IN `details`. ApiResponse#render_error puts the caller's
      // message in `error` and the service's own reasons in `details`
      // (server/app/controllers/concerns/api_response.rb) -- and the delegations
      // controller gives `error` only a generic label ("Failed to remove
      // permission") while every real refusal it can raise (privilege escalation,
      // an out-of-role permission name, the widening removal) arrives in
      // `details`. Mapping `message || error` alone therefore drops the entire
      // explanation and leaves the operator with a label. There is no `message`
      // key on that shape at all; it is kept first for the endpoints that do send
      // one, and `details` is appended so the failed VERB stays visible next to
      // the reason for it.
      const reasons = (Array.isArray(details) ? details : [ details ])
        .filter((reason): reason is string => typeof reason === 'string' && reason.length > 0);
      const label = message || errorLabel || 'API request failed';
      throw new Error(reasons.length > 0 ? `${label}: ${reasons.join('; ')}` : label);
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
  // The RESOLVED permission set this delegation confers: the API bounds the stored
  // custom rows by what the role grants LIVE, so this is NOT a count of stored rows.
  permissions?: Permission[];
  // Stored permission names that no longer resolve (the role stopped granting them, or
  // the delegation was moved to another role without a permission rewrite). They confer
  // nothing but stay on the row, so the UI must show them. Clearing one means rewriting
  // the stored permission set through the API (`updateDelegation` /
  // `addPermissionToDelegation` / `removePermissionFromDelegation` below), which is what
  // DelegationDetailsModal's permission-set editor does.
  stale_permission_names?: string[];
  // Which store the RESOLVED set above came from: 'custom' means the delegation carries
  // delegation_permissions rows of its own, 'role' means it carries none and therefore
  // confers its role's whole set, 'none' means neither. Only a 'custom' row has a stored
  // set to edit — on a 'role' row the resolved names belong to the ROLE, and offering a
  // removal for one would act on a delegation_permissions row that does not exist.
  permission_source?: 'custom' | 'role' | 'none';
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
  // Permissions are code-defined and identified by NAME (the dotted catalog key).
  // `name` and `key` are the canonical identifier; resource/action are derived for display.
  name: string;
  key: string;
  resource: string;
  action: string;
  description: string;
}

export interface DelegationFormData {
  delegated_user_email: string;
  role_id?: string;
  permission_names?: string[];
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
      email: string;
      roles?: string[];
    }>;
  };
}

export interface CreateDelegationData {
  delegated_user_email: string;
  role_id: string;
  permission_names: string[];
  expires_at: string;
  notes: string;
}

export interface User {
  id: string;
  email: string;
  name: string;
  roles: string[];
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

  // Update an existing delegation.
  //
  // A `permission_names` REWRITE is the only way to clear a stored set that
  // one-at-a-time removal cannot: DelegationService#remove_permission_from_delegation
  // refuses the removal that would empty the set (an empty custom set falls back to the
  // role's whole permission set, so that removal WIDENS). Note the API treats an EMPTY
  // `permission_names` as absent (`permission_names.present?`), so submitting [] is a
  // silent no-op, never a clear — callers must never offer it as one.
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
    // Filter out Manager role as it cannot be delegated
    return response.filter((role: Role) => role.name !== 'Manager');
  },

  // Get available permissions for delegation (optionally filtered by role)
  async getAvailablePermissions(roleId?: string): Promise<Permission[]> {
    const params = roleId ? `?role_id=${roleId}` : '';
    return apiRequest(`/api/v1/accounts/current/delegations/available_permissions${params}`);
  },

  // Add permission to delegation (by permission NAME)
  async addPermissionToDelegation(delegationId: string, permissionName: string): Promise<DelegationResponse> {
    return apiRequest(`/api/v1/accounts/current/delegations/${delegationId}/permissions`, {
      method: 'POST',
      body: JSON.stringify({ permission_name: permissionName }),
    });
  },

  // Remove permission from delegation (by permission NAME)
  async removePermissionFromDelegation(delegationId: string, permissionName: string): Promise<DelegationResponse> {
    return apiRequest(`/api/v1/accounts/current/delegations/${delegationId}/permissions/${encodeURIComponent(permissionName)}`, {
      method: 'DELETE',
    });
  },

  // Get delegation activity log
  async getDelegationActivity(delegationId: string): Promise<{ activities: DelegationActivity[] }> {
    return apiRequest(`/api/v1/accounts/current/delegations/${delegationId}/activity`);
  },

  // Search accounts (placeholder - implement based on backend)
  async searchAccounts(query: string): Promise<{ accounts: unknown[] }> {
    return apiRequest(`/api/v1/accounts/search?q=${encodeURIComponent(query)}`);
  },

  // Get available users for an account (placeholder - implement based on backend)
  async getAvailableUsers(accountId: string): Promise<{ users: User[] }> {
    return apiRequest(`/api/v1/accounts/${accountId}/users`);
  },


  // Create delegation request (placeholder - implement based on backend)
  async createDelegationRequest(data: CreateDelegationData): Promise<{ request: DelegationRequest }> {
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

// A delegatable permission as rendered in the delegation UI.
export interface DelegationPermissionOption {
  // `key` is the dotted catalog permission name (the canonical identifier).
  key: string;
  label: string;
  description: string;
}

// Humanize a catalog Permission into a delegatable filter option. The catalog has no
// `label`, so it is derived from the dotted name (e.g. "billing.read" -> "Billing Read").
// This keeps delegation permission options sourced from the catalog at runtime instead
// of duplicating (and drifting from) the backend permission list here.
export const deriveDelegationPermissions = (
  permissions: Array<{ name: string; resource: string; action: string; description: string }>
): DelegationPermissionOption[] =>
  permissions.map(permission => {
    const label = `${permission.resource} ${permission.action}`
      .split(/[.\s_]+/)
      .filter(Boolean)
      .map(part => part.charAt(0).toUpperCase() + part.slice(1))
      .join(' ');
    return {
      key: permission.name,
      label,
      description: permission.description,
    };
  });

// Back-compat export retained for callers/tests that import this symbol. The catalog is
// the source of truth, so the static list is intentionally empty here (no hardcoded
// permission names); consumers fetch the catalog via `rolesApi.getPermissions()` and map
// it through `deriveDelegationPermissions` at runtime.
export const DELEGATION_PERMISSIONS: DelegationPermissionOption[] = [];
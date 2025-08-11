import axios, { AxiosError } from 'axios';

const API_BASE_URL = process.env.REACT_APP_API_URL || 'http://localhost:3000/api/v1';

// Types
export interface Delegation {
  id: string;
  name: string;
  description: string;
  sourceAccountId: string;
  sourceAccountName: string;
  targetAccountId: string;
  targetAccountName: string;
  permissions: string[];
  status: 'pending' | 'active' | 'expired' | 'revoked';
  createdBy: string;
  createdByName: string;
  approvedBy?: string;
  approvedByName?: string;
  expiresAt?: string;
  createdAt: string;
  updatedAt: string;
  users: DelegationUser[];
  activityLog?: DelegationActivity[];
}

export interface DelegationUser {
  id: string;
  userId: string;
  email: string;
  firstName: string;
  lastName: string;
  roles: string[];
  addedAt: string;
  addedBy: string;
}

export interface DelegationActivity {
  id: string;
  action: 'created' | 'approved' | 'rejected' | 'revoked' | 'expired' | 'user_added' | 'user_removed' | 'permissions_changed';
  performedBy: string;
  performedByName: string;
  details?: string;
  timestamp: string;
}

export interface CreateDelegationRequest {
  name: string;
  description: string;
  targetAccountId: string;
  permissions: string[];
  userIds?: string[];
  expiresAt?: string;
}

export interface UpdateDelegationRequest {
  name?: string;
  description?: string;
  permissions?: string[];
  expiresAt?: string;
}

export interface DelegationRequest {
  id: string;
  delegation: Delegation;
  requestedBy: string;
  requestedByName: string;
  requestedByEmail: string;
  message?: string;
  status: 'pending' | 'approved' | 'rejected';
  reviewedBy?: string;
  reviewedByName?: string;
  reviewNote?: string;
  createdAt: string;
  reviewedAt?: string;
}

// Available permissions for delegation
export const DELEGATION_PERMISSIONS = [
  { key: 'read_users', label: 'View Users', description: 'View user profiles and information' },
  { key: 'manage_users', label: 'Manage Users', description: 'Create, update, and delete users' },
  { key: 'read_billing', label: 'View Billing', description: 'View billing information and invoices' },
  { key: 'manage_billing', label: 'Manage Billing', description: 'Update payment methods and billing settings' },
  { key: 'read_subscriptions', label: 'View Subscriptions', description: 'View subscription details and history' },
  { key: 'manage_subscriptions', label: 'Manage Subscriptions', description: 'Upgrade, downgrade, or cancel subscriptions' },
  { key: 'read_analytics', label: 'View Analytics', description: 'Access analytics and reports' },
  { key: 'manage_settings', label: 'Manage Settings', description: 'Update account settings and preferences' },
  { key: 'support_access', label: 'Support Access', description: 'Access for customer support purposes' },
];

// API functions
export const delegationApi = {
  // Get all delegations for the current account
  async getDelegations(params?: { status?: string; role?: 'source' | 'target' }) {
    try {
      const response = await axios.get(`${API_BASE_URL}/delegations`, { params });
      return response.data;
    } catch (error) {
      console.error('Error fetching delegations:', error);
      throw error;
    }
  },

  // Get a specific delegation by ID
  async getDelegation(id: string) {
    try {
      const response = await axios.get(`${API_BASE_URL}/delegations/${id}`);
      return response.data;
    } catch (error) {
      console.error('Error fetching delegation:', error);
      throw error;
    }
  },

  // Create a new delegation
  async createDelegation(data: CreateDelegationRequest) {
    try {
      const response = await axios.post(`${API_BASE_URL}/delegations`, data);
      return response.data;
    } catch (error) {
      console.error('Error creating delegation:', error);
      throw error;
    }
  },

  // Update an existing delegation
  async updateDelegation(id: string, data: UpdateDelegationRequest) {
    try {
      const response = await axios.patch(`${API_BASE_URL}/delegations/${id}`, data);
      return response.data;
    } catch (error) {
      console.error('Error updating delegation:', error);
      throw error;
    }
  },

  // Revoke a delegation
  async revokeDelegation(id: string, reason?: string) {
    try {
      const response = await axios.post(`${API_BASE_URL}/delegations/${id}/revoke`, { reason });
      return response.data;
    } catch (error) {
      console.error('Error revoking delegation:', error);
      throw error;
    }
  },

  // Add users to a delegation
  async addUsersToDelegation(id: string, userIds: string[]) {
    try {
      const response = await axios.post(`${API_BASE_URL}/delegations/${id}/users`, { userIds });
      return response.data;
    } catch (error) {
      console.error('Error adding users to delegation:', error);
      throw error;
    }
  },

  // Remove a user from a delegation
  async removeUserFromDelegation(delegationId: string, userId: string) {
    try {
      const response = await axios.delete(`${API_BASE_URL}/delegations/${delegationId}/users/${userId}`);
      return response.data;
    } catch (error) {
      console.error('Error removing user from delegation:', error);
      throw error;
    }
  },

  // Get delegation requests (incoming)
  async getDelegationRequests(status?: 'pending' | 'approved' | 'rejected') {
    try {
      const response = await axios.get(`${API_BASE_URL}/delegation-requests`, { 
        params: { status } 
      });
      return response.data;
    } catch (error) {
      console.error('Error fetching delegation requests:', error);
      throw error;
    }
  },

  // Approve a delegation request
  async approveDelegationRequest(requestId: string, note?: string) {
    try {
      const response = await axios.post(`${API_BASE_URL}/delegation-requests/${requestId}/approve`, { note });
      return response.data;
    } catch (error) {
      console.error('Error approving delegation request:', error);
      throw error;
    }
  },

  // Reject a delegation request
  async rejectDelegationRequest(requestId: string, reason: string) {
    try {
      const response = await axios.post(`${API_BASE_URL}/delegation-requests/${requestId}/reject`, { reason });
      return response.data;
    } catch (error) {
      console.error('Error rejecting delegation request:', error);
      throw error;
    }
  },

  // Get delegation activity log
  async getDelegationActivity(delegationId: string) {
    try {
      const response = await axios.get(`${API_BASE_URL}/delegations/${delegationId}/activity`);
      return response.data;
    } catch (error) {
      console.error('Error fetching delegation activity:', error);
      throw error;
    }
  },

  // Search for accounts to delegate access to
  async searchAccounts(query: string) {
    try {
      const response = await axios.get(`${API_BASE_URL}/accounts/search`, {
        params: { q: query }
      });
      return response.data;
    } catch (error) {
      console.error('Error searching accounts:', error);
      throw error;
    }
  },

  // Get available users to add to delegation
  async getAvailableUsers(accountId: string) {
    try {
      const response = await axios.get(`${API_BASE_URL}/accounts/${accountId}/users`);
      return response.data;
    } catch (error) {
      console.error('Error fetching available users:', error);
      throw error;
    }
  },
};

export default delegationApi;
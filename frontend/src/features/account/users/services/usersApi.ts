import { api } from '@/shared/services/api';

export interface User {
  id: string;
  name: string;
  email: string;
  email_verified: boolean;
  phone?: string;
  roles: string[];  // Array of role names
  permissions: string[];  // Array of permission strings
  status: 'active' | 'suspended' | 'inactive';
  locked: boolean;
  failed_login_attempts: number;
  last_login_at: string | null;
  created_at: string;
  updated_at: string;
  preferences: Record<string, any>;
  account: {
    id: string;
    name: string;
    status: string;
  };
}

export interface UserFormData {
  name: string;
  email: string;
  phone?: string;
  roles: string[];  // Array of role names
  password?: string;
  password_confirmation?: string;
}

export interface UserUpdateData {
  name?: string;
  email?: string;
  phone?: string;
  roles?: string[];
}

export interface UsersListResponse {
  success: boolean;
  data: User[];
  message?: string;
}

export interface UserResponse {
  success: boolean;
  data: User;
  message?: string;
}

export interface UserCreateResponse {
  success: boolean;
  data: User;
  message: string;
}

export interface UserStats {
  total_users: number;
  active_users: number;
  suspended_users: number;
  unverified_users: number;
  recent_logins: number;
}

export interface AdminAccount {
  id: string;
  name: string;
  subdomain: string;
  status: string;
  users_count: number;
  subscription?: {
    id: string;
    plan_name: string;
    status: string;
    created_at: string;
  } | null;
  created_at: string;
  updated_at: string;
}

export interface AdminAccountsResponse {
  success: boolean;
  data: {
    accounts: AdminAccount[];
    total_count: number;
    active_count: number;
    suspended_count: number;
    cancelled_count: number;
  };
}

/**
 * @module UsersApi
 * @description User management service.
 *
 * RESPONSIBILITY: All user CRUD operations, status changes, role management
 * NOT RESPONSIBLE FOR: Admin settings dashboard (use adminSettingsApi for user listing)
 *
 * Handles /users/* and /admin/users/* endpoints.
 */
class UsersApiService {
  // Get all users in current account
  async getUsers(): Promise<UsersListResponse> {
    const response = await api.get('/users');
    return response.data;
  }

  // Get specific user
  async getUser(user_id: string): Promise<UserResponse> {
    const response = await api.get(`/users/${user_id}`);
    return response.data;
  }

  // Create new user
  async createUser(userData: UserFormData): Promise<UserCreateResponse> {
    const response = await api.post('/users', {
      user: userData
    });
    return response.data;
  }

  // Update existing user
  async updateUser(user_id: string, userData: UserUpdateData): Promise<UserResponse> {
    const response = await api.put(`/users/${user_id}`, {
      user: userData
    });
    return response.data;
  }

  // Delete user
  async deleteUser(user_id: string): Promise<{ success: boolean; message: string }> {
    const response = await api.delete(`/users/${user_id}`);
    return response.data;
  }

  // Suspend user
  async suspendUser(user_id: string, reason?: string): Promise<UserResponse> {
    const response = await api.put(`/users/${user_id}/suspend`, {
      reason: reason
    });
    return response.data;
  }

  // Activate user
  async activateUser(user_id: string): Promise<UserResponse> {
    const response = await api.put(`/users/${user_id}/activate`);
    return response.data;
  }

  // Reset user password
  async resetUserPassword(user_id: string): Promise<{ success: boolean; message: string }> {
    const response = await api.post(`/users/${user_id}/reset_password`);
    return response.data;
  }

  // Unlock user account
  async unlockUser(user_id: string): Promise<UserResponse> {
    const response = await api.put(`/users/${user_id}/unlock`);
    return response.data;
  }

  // Resend email verification
  async resendVerification(user_id: string): Promise<{ success: boolean; message: string }> {
    const response = await api.post(`/users/${user_id}/resend_verification`);
    return response.data;
  }

  // Get users for specific account only
  async getAccountUsers(account_id?: string): Promise<UsersListResponse> {
    const response = await api.get('/users', {
      params: { account_id: account_id }
    });
    return response.data;
  }

  // Get all users system-wide (admin only)
  async getAllUsers(): Promise<UsersListResponse> {
    const response = await api.get('/admin/users');
    return response.data;
  }

  // Get all accounts (admin only)
  async getAllAccounts(): Promise<AdminAccountsResponse> {
    const response = await api.get('/admin_settings/accounts');
    return response.data;
  }

  // Create user in specific account (admin only)
  async createAdminUser(userData: UserFormData & { account_id: string }): Promise<UserCreateResponse> {
    const response = await api.post('/admin/users', {
      user: userData,
      account_id: userData.account_id
    });
    return response.data;
  }

  // Update user via admin endpoint (admin only) - supports role updates
  async updateAdminUser(user_id: string, userData: UserUpdateData): Promise<UserResponse> {
    const response = await api.put(`/admin/users/${user_id}`, {
      user: userData
    });
    return response.data;
  }

  // Update user role within account
  async updateUserRole(user_id: string, role: string, account_id?: string): Promise<UserResponse> {
    const response = await api.put(`/users/${user_id}/role`, {
      role,
      account_id: account_id
    });
    return response.data;
  }

  // Remove user from account
  async removeFromAccount(user_id: string, account_id?: string): Promise<{ success: boolean; message: string }> {
    const response = await api.delete(`/accounts/${account_id}/users/${user_id}`);
    return response.data;
  }

  // Impersonate user (admin only)
  async impersonateUser(user_id: string): Promise<{ success: boolean; message: string }> {
    const response = await api.post(`/admin/users/${user_id}/impersonate`);
    return response.data;
  }

  // Get user statistics
  async getUserStats(): Promise<{ success: boolean; data: UserStats }> {
    const response = await api.get('/users/stats');
    return response.data;
  }

  // Fetch available roles from backend - only roles the current user can assign
  async getAvailableRoles(): Promise<Array<{ value: string; label: string; description: string; canAssign?: boolean }>> {
    try {
      const response = await api.get('/roles/assignable');
      if (response.data.success) {
        return response.data.data.map((role: unknown) => {
          const roleData = role as { name?: string; value?: string; label?: string; description?: string };
          const roleName = roleData.name || roleData.value || '';
          return {
            value: roleName,
            label: roleData.label || roleName.split('.').map((part: string) => 
              part.charAt(0).toUpperCase() + part.slice(1)
            ).join(' '),
            description: roleData.description || '',
            canAssign: true // All roles from assignable endpoint can be assigned
          };
        });
      }
      return this.getFallbackRoles();
    } catch (_error) {
      // Fallback to all roles but mark permission restrictions
      try {
        const allRolesResponse = await api.get('/roles');
        if (allRolesResponse.data.success) {
          return allRolesResponse.data.data
            .filter((role: unknown) => {
              const roleData = role as { system_role?: boolean };
              return !roleData.system_role;
            })
            .map((role: unknown) => {
              const roleData = role as { name: string; description?: string };
              return {
                value: roleData.name,
                label: roleData.name.split('.').map((part: string) => 
                  part.charAt(0).toUpperCase() + part.slice(1)
                ).join(' '),
                description: roleData.description || '',
                canAssign: false // Mark as restricted since assignable endpoint failed
              };
            });
        }
      } catch (_error) {
    // Error silently ignored
  }
      return this.getFallbackRoles();
    }
  }

  // Fallback roles in case API fails
  private getFallbackRoles(): Array<{ value: string; label: string; description: string }> {
    return [
      { 
        value: 'account.member', 
        label: 'Account Member', 
        description: 'Basic account member access with limited permissions' 
      },
      { 
        value: 'account.manager', 
        label: 'Account Manager', 
        description: 'Full management access within assigned account' 
      },
      { 
        value: 'billing.manager', 
        label: 'Billing Manager', 
        description: 'Specialized role for billing and payment management' 
      },
      { 
        value: 'content_manager', 
        label: 'Content Manager', 
        description: 'Content management role for pages and documentation' 
      },
      { 
        value: 'support.agent', 
        label: 'Support Agent', 
        description: 'Customer support role with user assistance permissions' 
      }
    ];
  }

  // Get status color for UI
  getStatusColor(status: string): string {
    switch (status) {
      case 'active':
        return 'text-theme-success bg-theme-success-background border-theme-success-border';
      case 'suspended':
        return 'text-theme-error bg-theme-error-background border-theme-error-border';
      case 'inactive':
        return 'text-theme-secondary bg-theme-surface-hover border-theme';
      default:
        return 'text-theme-secondary bg-theme-surface-hover border-theme';
    }
  }

  // Get role color for UI (handles both old single role and new role array)
  getRoleColor(roles: string[] | string): string {
    const roleArray = Array.isArray(roles) ? roles : [roles];
    const primaryRole = roleArray[0] || 'account.member';
    
    // System and administrative roles - red
    if (primaryRole.includes('system.admin') || primaryRole === 'admin') {
      return 'bg-theme-error bg-opacity-10 text-theme-error border border-theme-error border-opacity-20';
    }
    // Management roles - green
    else if (primaryRole.includes('account.manager') || primaryRole.includes('manager')) {
      return 'bg-theme-success bg-opacity-10 text-theme-success border border-theme-success border-opacity-20';
    }
    // Billing roles - blue
    else if (primaryRole.includes('billing.manager') || primaryRole.includes('billing')) {
      return 'bg-theme-interactive-primary bg-opacity-10 text-theme-interactive-primary border border-theme-interactive-primary border-opacity-20';
    }
    // Content and support roles - info
    else if (primaryRole.includes('content_manager') || primaryRole.includes('support.agent')) {
      return 'bg-theme-info bg-opacity-10 text-theme-info border border-theme-info border-opacity-20';
    }
    // Analytics and API roles - warning
    else if (primaryRole.includes('analytics.reader') || primaryRole.includes('api.developer')) {
      return 'bg-theme-warning bg-opacity-10 text-theme-warning border border-theme-warning border-opacity-20';
    }
    // Worker roles - surface
    else if (primaryRole.includes('worker.')) {
      return 'bg-theme-surface text-theme-secondary border border-theme';
    }
    // Default member roles - info blue
    else {
      return 'bg-theme-info bg-opacity-10 text-theme-info border border-theme-info border-opacity-20';
    }
  }
  
  // Format roles for display
  formatRoles(roles: string[]): string {
    if (!roles || roles.length === 0) return 'No roles';
    
    return roles.map(role => {
      return role.replace('.', ' ').replace(/\b\w/g, l => l.toUpperCase());
    }).join(', ');
  }

  // Get users by role (for role management)
  async getUsersByRole(role_id: string): Promise<UsersListResponse> {
    const response = await api.get(`/roles/${role_id}/users`);
    return response.data;
  }

  // Add role to user
  async addRoleToUser(user_id: string, role_id: string): Promise<UserResponse> {
    const response = await api.post(`/users/${user_id}/roles/${role_id}`);
    return response.data;
  }

  // Remove role from user  
  async removeRoleFromUser(user_id: string, role_id: string): Promise<UserResponse> {
    const response = await api.delete(`/users/${user_id}/roles/${role_id}`);
    return response.data;
  }

  // Validate user form data
  validateUserData(userData: UserFormData): string[] {
    const errors: string[] = [];

    if (!userData.name || userData.name.trim().length < 1) {
      errors.push('Name is required');
    }

    if (!userData.email || userData.email.trim().length < 1) {
      errors.push('Email is required');
    } else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(userData.email)) {
      errors.push('Email format is invalid');
    }

    if (!userData.roles || userData.roles.length === 0 || userData.roles.every(role => !role?.trim())) {
      errors.push('At least one role is required');
    }

    if (userData.password && userData.password.length < 8) {
      errors.push('Password must be at least 8 characters long');
    }

    if (userData.password && userData.password !== userData.password_confirmation) {
      errors.push('Password confirmation does not match');
    }

    return errors;
  }
}

export const usersApi = new UsersApiService();
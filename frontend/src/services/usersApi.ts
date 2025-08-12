import { api } from './api';

export interface User {
  id: string;
  first_name: string;
  last_name: string;
  full_name: string;
  email: string;
  email_verified: boolean;
  phone?: string;
  role: string;
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
  first_name: string;
  last_name: string;
  email: string;
  phone?: string;
  role: string;
  password?: string;
  password_confirmation?: string;
}

export interface UserUpdateData {
  first_name?: string;
  last_name?: string;
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

class UsersApiService {
  // Get all users in current account
  async getUsers(): Promise<UsersListResponse> {
    const response = await api.get('/users');
    return response.data;
  }

  // Get specific user
  async getUser(userId: string): Promise<UserResponse> {
    const response = await api.get(`/users/${userId}`);
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
  async updateUser(userId: string, userData: UserUpdateData): Promise<UserResponse> {
    const response = await api.put(`/users/${userId}`, {
      user: userData
    });
    return response.data;
  }

  // Delete user
  async deleteUser(userId: string): Promise<{ success: boolean; message: string }> {
    const response = await api.delete(`/users/${userId}`);
    return response.data;
  }

  // Suspend user
  async suspendUser(userId: string, reason?: string): Promise<UserResponse> {
    const response = await api.put(`/users/${userId}/suspend`, {
      reason: reason
    });
    return response.data;
  }

  // Activate user
  async activateUser(userId: string): Promise<UserResponse> {
    const response = await api.put(`/users/${userId}/activate`);
    return response.data;
  }

  // Reset user password
  async resetUserPassword(userId: string): Promise<{ success: boolean; message: string }> {
    const response = await api.post(`/users/${userId}/reset_password`);
    return response.data;
  }

  // Unlock user account
  async unlockUser(userId: string): Promise<UserResponse> {
    const response = await api.put(`/users/${userId}/unlock`);
    return response.data;
  }

  // Resend email verification
  async resendVerification(userId: string): Promise<{ success: boolean; message: string }> {
    const response = await api.post(`/users/${userId}/resend_verification`);
    return response.data;
  }

  // Get users for specific account only
  async getAccountUsers(accountId?: string): Promise<UsersListResponse> {
    const response = await api.get('/users', {
      params: { account_id: accountId }
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

  // Update user role within account
  async updateUserRole(userId: string, role: string, accountId?: string): Promise<UserResponse> {
    const response = await api.put(`/users/${userId}/role`, {
      role,
      account_id: accountId
    });
    return response.data;
  }

  // Remove user from account
  async removeFromAccount(userId: string, accountId?: string): Promise<{ success: boolean; message: string }> {
    const response = await api.delete(`/accounts/${accountId}/users/${userId}`);
    return response.data;
  }

  // Impersonate user (admin only)
  async impersonateUser(userId: string): Promise<{ success: boolean; message: string }> {
    const response = await api.post(`/admin/users/${userId}/impersonate`);
    return response.data;
  }

  // Get user statistics
  async getUserStats(): Promise<{ success: boolean; data: UserStats }> {
    const response = await api.get('/users/stats');
    return response.data;
  }

  // Available roles for user assignment
  getAvailableRoles(): Array<{ value: string; label: string; description: string }> {
    return [
      { 
        value: 'user', 
        label: 'User', 
        description: 'Basic access to dashboard and account features' 
      },
      { 
        value: 'viewer', 
        label: 'Viewer', 
        description: 'Read-only access to dashboard and analytics' 
      },
      { 
        value: 'analyst', 
        label: 'Analyst', 
        description: 'Advanced analytics and reporting access' 
      },
      { 
        value: 'support', 
        label: 'Support', 
        description: 'User management and customer support access' 
      },
      { 
        value: 'content_manager', 
        label: 'Content Manager', 
        description: 'Manage pages, content, and basic account settings' 
      },
      { 
        value: 'customer_manager', 
        label: 'Customer Manager', 
        description: 'Full user and account management access' 
      },
      { 
        value: 'sales_manager', 
        label: 'Sales Manager', 
        description: 'Analytics, user management, and account oversight' 
      },
      { 
        value: 'billing_manager', 
        label: 'Billing Manager', 
        description: 'Billing, payments, and account management access' 
      },
      { 
        value: 'admin', 
        label: 'Administrator', 
        description: 'Full administrative access except system settings' 
      },
      { 
        value: 'owner', 
        label: 'Owner', 
        description: 'Complete access to all features and settings' 
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

  // Get role color for UI
  getRoleColor(role: string): string {
    switch (role) {
      case 'admin':
        return 'bg-theme-error bg-opacity-10 text-theme-error';
      case 'owner':
        return 'bg-theme-success bg-opacity-10 text-theme-success';
      case 'member':
      default:
        return 'bg-theme-info bg-opacity-10 text-theme-info';
    }
  }

  // Validate user form data
  validateUserData(userData: UserFormData): string[] {
    const errors: string[] = [];

    if (!userData.first_name || userData.first_name.trim().length < 1) {
      errors.push('First name is required');
    }

    if (!userData.last_name || userData.last_name.trim().length < 1) {
      errors.push('Last name is required');
    }

    if (!userData.email || userData.email.trim().length < 1) {
      errors.push('Email is required');
    } else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(userData.email)) {
      errors.push('Email format is invalid');
    }

    if (!userData.role || !userData.role.trim()) {
      errors.push('Role is required');
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
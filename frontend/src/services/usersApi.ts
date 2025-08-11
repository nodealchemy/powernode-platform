import { api } from './api';
import { mockUsers, mockUserStats } from './mockData';

export interface User {
  id: string;
  first_name: string;
  last_name: string;
  full_name: string;
  email: string;
  email_verified: boolean;
  phone?: string;
  roles: string[];
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
  roles: string[];
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

class UsersApiService {
  // Get all users in current account
  async getUsers(): Promise<UsersListResponse> {
    try {
      const response = await api.get('/users');
      return response.data;
    } catch (error) {
      console.warn('API failed, using mock data:', error);
      // Return mock data as fallback
      return {
        success: true,
        data: mockUsers
      };
    }
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
    try {
      const response = await api.get('/users', {
        params: { account_id: accountId }
      });
      return response.data;
    } catch (error) {
      console.warn('API failed, using mock data:', error);
      return {
        success: true,
        data: mockUsers.filter(u => !accountId || u.account?.id === accountId)
      };
    }
  }

  // Get all users system-wide (admin only)
  async getAllUsers(): Promise<UsersListResponse> {
    try {
      const response = await api.get('/admin/users');
      return response.data;
    } catch (error) {
      console.warn('API failed, using mock data:', error);
      return {
        success: true,
        data: mockUsers
      };
    }
  }

  // Get all accounts (admin only)
  async getAllAccounts(): Promise<{ success: boolean; data: any[] }> {
    try {
      const response = await api.get('/admin/accounts');
      return response.data;
    } catch (error) {
      console.warn('API failed:', error);
      return {
        success: true,
        data: []
      };
    }
  }

  // Update user roles within account
  async updateUserRoles(userId: string, roles: string[], accountId?: string): Promise<UserResponse> {
    const response = await api.put(`/users/${userId}/roles`, {
      roles,
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
    try {
      const response = await api.get('/users/stats');
      return response.data;
    } catch (error) {
      console.warn('API failed, using mock data:', error);
      // Return mock data as fallback
      return {
        success: true,
        data: mockUserStats
      };
    }
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
      case 'owner':
        return 'text-purple-700 bg-purple-50 border-purple-200';
      case 'admin':
        return 'text-red-700 bg-red-50 border-red-200';
      case 'billing_manager':
      case 'sales_manager':
      case 'customer_manager':
        return 'text-blue-700 bg-blue-50 border-blue-200';
      case 'content_manager':
      case 'analyst':
        return 'text-indigo-700 bg-indigo-50 border-indigo-200';
      case 'support':
        return 'text-green-700 bg-green-50 border-green-200';
      case 'viewer':
        return 'text-theme-secondary bg-theme-surface-hover border-theme';
      case 'user':
      default:
        return 'text-slate-700 bg-slate-50 border-slate-200';
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

    if (!userData.roles || userData.roles.length === 0 || !userData.roles[0].trim()) {
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
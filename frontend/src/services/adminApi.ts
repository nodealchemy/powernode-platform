import { api } from './api';

// Types for admin data
export interface PlatformStats {
  total_accounts: number;
  active_accounts: number;
  total_users: number;
  active_users: number;
  total_subscriptions: number;
  active_subscriptions: number;
  total_revenue: number;
  monthly_growth: number;
}

export interface SystemSettings {
  maintenance_mode: boolean;
  registration_enabled: boolean;
  email_verification_required: boolean;
  password_complexity_level: 'low' | 'medium' | 'high';
  session_timeout_minutes: number;
  max_failed_login_attempts: number;
  account_lockout_duration: number;
  platform_version: string;
  database_version: string;
  uptime: string | number;
}

export interface UserManagementData {
  total_users: number;
  users_by_role: Record<string, number>;
  users_by_status: Record<string, number>;
  recent_registrations: number;
  email_verification_pending: number;
}

export interface SecuritySettingsData {
  failed_login_attempts_today: number;
  locked_accounts: number;
  recent_security_events: number;
  suspicious_activities: Array<{
    type: string;
    count: number;
  }>;
}

export interface AdminUser {
  id: string;
  email: string;
  full_name: string;
  status: string;
  roles: string[];
  account: {
    id: string;
    name: string;
    status: string;
  };
  last_login_at: string | null;
  email_verified: boolean;
  failed_login_attempts: number;
  locked: boolean;
  created_at: string;
}

export interface AdminAccount {
  id: string;
  name: string;
  subdomain: string | null;
  status: string;
  users_count: number;
  subscription: {
    id: string;
    plan_name: string;
    status: string;
    created_at: string;
  } | null;
  created_at: string;
  updated_at: string;
}

export interface AdminLog {
  id: string;
  action: string;
  resource_type: string;
  resource_id: string | null;
  user: {
    id: string;
    email: string;
    full_name: string;
  } | null;
  account: {
    id: string;
    name: string;
  } | null;
  ip_address: string;
  metadata: Record<string, any>;
  created_at: string;
}

export interface AdminSettingsData {
  system_settings: SystemSettings;
  platform_stats: PlatformStats;
  user_management: UserManagementData;
  security_settings: SecuritySettingsData;
  global_analytics: any;
}

export interface AdminSettingsUpdateRequest {
  maintenance_mode?: boolean;
  registration_enabled?: boolean;
  email_verification_required?: boolean;
  password_complexity_level?: 'low' | 'medium' | 'high';
  session_timeout_minutes?: number;
  max_failed_login_attempts?: number;
  account_lockout_duration?: number;
  system_notifications?: Record<string, any>;
  rate_limiting?: Record<string, any>;
  feature_flags?: Record<string, boolean>;
}

class AdminApiService {
  // Get all admin settings
  async getAdminSettings(): Promise<AdminSettingsData> {
    const response = await api.get('/admin_settings');
    return response.data;
  }

  // Update admin settings
  async updateAdminSettings(settings: AdminSettingsUpdateRequest): Promise<AdminSettingsData> {
    const response = await api.put('/admin_settings', { admin_settings: settings });
    return response.data;
  }

  // Get users for admin management
  async getUsers(): Promise<{
    users: AdminUser[];
    total_count: number;
    active_count: number;
    inactive_count: number;
    suspended_count: number;
  }> {
    const response = await api.get('/admin_settings/users');
    return response.data;
  }

  // Get accounts for admin management
  async getAccounts(): Promise<{
    accounts: AdminAccount[];
    total_count: number;
    active_count: number;
    suspended_count: number;
    cancelled_count: number;
  }> {
    const response = await api.get('/admin_settings/accounts');
    return response.data;
  }

  // Get system logs
  async getSystemLogs(): Promise<{
    logs: AdminLog[];
    total_count: number;
  }> {
    const response = await api.get('/admin_settings/system_logs');
    return response.data;
  }

  // Suspend an account
  async suspendAccount(accountId: string, reason?: string): Promise<void> {
    await api.post('/admin_settings/suspend_account', {
      account_id: accountId,
      reason
    });
  }

  // Activate an account
  async activateAccount(accountId: string, reason?: string): Promise<void> {
    await api.post('/admin_settings/activate_account', {
      account_id: accountId,
      reason
    });
  }

  // Update user status (using existing users endpoint)
  async updateUserStatus(userId: string, status: 'active' | 'inactive' | 'suspended'): Promise<any> {
    const response = await api.put(`/users/${userId}`, {
      user: { status }
    });
    return response.data;
  }

  // Delete user (using existing users endpoint)
  async deleteUser(userId: string): Promise<void> {
    await api.delete(`/users/${userId}`);
  }

  // Get global analytics (if user has permission)
  async getGlobalAnalytics(): Promise<any> {
    const response = await api.get('/analytics/revenue?global=true');
    return response.data;
  }

  // Export system data
  async exportSystemData(type: 'users' | 'accounts' | 'logs' | 'analytics'): Promise<Blob> {
    const response = await api.get(`/analytics/export?type=${type}`, {
      responseType: 'blob'
    });
    return response.data;
  }
}

export const adminApi = new AdminApiService();
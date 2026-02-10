import { api } from '@/shared/services/api';

export interface DevelopmentFeatureFlag {
  name: string;
  enabled: boolean;
}

export interface DevelopmentInfo {
  enterprise_installed: boolean;
  enterprise_enabled: boolean;
  engine_version?: string;
  license_valid?: boolean;
  license_edition?: string;
  feature_flags?: DevelopmentFeatureFlag[];
}

export interface SystemMetrics {
  total_users: number;
  total_accounts: number;
  active_accounts: number;
  suspended_accounts: number;
  cancelled_accounts: number;
  total_subscriptions: number;
  active_subscriptions: number;
  trial_subscriptions: number;
  total_revenue: number;
  monthly_revenue: number;
  failed_payments: number;
  webhook_events_today: number;
  system_health: 'healthy' | 'warning' | 'error';
  uptime: number;
}

export interface AdminUser {
  id: string;
  name: string;
  full_name?: string;
  email: string;
  email_verified: boolean;
  last_login_at: string | null;
  created_at: string;
  account: {
    id: string;
    name: string;
    status: string;
  };
  roles: string[];
}

export interface AdminAccount {
  id: string;
  name: string;
  subdomain: string;
  status: 'active' | 'suspended' | 'cancelled';
  created_at: string;
  updated_at: string;
  users_count: number;
  subscription?: {
    id: string;
    status: string;
    plan: {
      name: string;
      price_cents: number;
    };
    current_period_end: string;
  };
  owner: {
    id: string;
    name: string;
    email: string;
  };
}

export interface SystemLog {
  id: string;
  level: 'info' | 'warning' | 'error' | 'debug';
  message: string;
  timestamp: string;
  source: string;
  metadata?: Record<string, any>;
}

export interface RateLimitingSettings {
  enabled?: boolean;
  api_requests_per_minute?: number;
  impersonation_attempts_per_hour?: number;
  login_attempts_per_hour?: number;
  password_reset_attempts_per_hour?: number;
  registration_attempts_per_hour?: number;
  webhook_requests_per_minute?: number;
  email_verification_attempts_per_hour?: number;
  authenticated_requests_per_hour?: number;
}

export interface AdminSettings {
  id: string;
  system_name: string;
  system_email: string;
  support_email: string;
  copyright_text: string;
  maintenance_mode: boolean;
  registration_enabled: boolean;
  trial_period_days: number;
  max_trial_accounts: number;
  webhook_timeout_seconds: number;
  payment_retry_attempts: number;
  session_timeout_minutes: number;
  password_min_length: number;
  require_email_verification: boolean;
  email_verification_required: boolean;
  allow_account_deletion: boolean;
  backup_retention_days: number;
  log_retention_days: number;
  password_complexity_level: 'low' | 'medium' | 'high';
  max_failed_login_attempts: number;
  account_lockout_duration: number;
  rate_limiting: RateLimitingSettings;
  feature_flags: Record<string, boolean>;
  smtp_settings: {
    host: string;
    port: number;
    username: string;
    use_tls: boolean;
    from_address: string;
  };
  created_at: string;
  updated_at: string;
}

export interface PaymentGatewayStatus {
  stripe: {
    connected: boolean;
    environment: 'live' | 'test';
    last_webhook: string | null;
    webhook_status: 'healthy' | 'warning' | 'unhealthy' | 'no_data';
  };
  paypal: {
    connected: boolean;
    environment: 'live' | 'sandbox';
    last_webhook: string | null;
    webhook_status: 'healthy' | 'warning' | 'unhealthy' | 'no_data';
  };
}

export interface AdminOverviewData {
  metrics: SystemMetrics;
  recent_users: AdminUser[];
  recent_accounts: AdminAccount[];
  recent_logs: SystemLog[];
  payment_gateways: PaymentGatewayStatus;
  settings_summary: Partial<AdminSettings>;
}

/**
 * @module AdminSettingsApi
 * @description Platform configuration and system settings service.
 *
 * RESPONSIBILITY: System settings, health monitoring, rate limiting, security configuration,
 *                 admin dashboard data (user/account/log lists)
 * NOT RESPONSIBLE FOR: Analytics export, user CRUD operations
 *
 * This is the primary owner of /admin_settings/* endpoints.
 */
class AdminSettingsApi {
  // Get admin overview data
  async getOverview(): Promise<{ success: boolean; data?: AdminOverviewData; error?: string }> {
    try {
      const response = await api.get('/admin_settings');
      // Backend returns data in the response directly or wrapped in success/data
      const responseData = response.data;
      if (responseData.success !== undefined) {
        return responseData;
      }
      // Handle case where data is returned directly
      return { success: true, data: responseData };
    } catch (error) {
      const errorMessage =
        error && typeof error === 'object' && 'response' in error
          ? (error as { response?: { data?: { error?: string } } }).response?.data?.error ||
            'Failed to fetch admin overview'
          : 'Failed to fetch admin overview';
      return { success: false, error: errorMessage };
    }
  }

  // Get detailed system metrics
  async getMetrics(): Promise<SystemMetrics> {
    const response = await api.get('/admin_settings/metrics');
    return response.data;
  }

  // Get all users (with pagination)
  async getUsers(options: {
    page?: number;
    per_page?: number;
    search?: string;
    roles?: string[];
    status?: string;
  } = {}): Promise<{
    users: AdminUser[];
    pagination: {
      current_page: number;
      per_page: number;
      total_count: number;
      total_pages: number;
    };
  }> {
    const params = new URLSearchParams();
    
    if (options.page) params.set('page', options.page.toString());
    if (options.per_page) params.set('per_page', options.per_page.toString());
    if (options.search) params.set('search', options.search);
    if (options.roles && options.roles.length > 0) params.set('roles', options.roles.join(','));
    if (options.status && options.status !== 'all') params.set('status', options.status);
    
    const response = await api.get(`/admin_settings/users?${params.toString()}`);
    return response.data;
  }

  // Get all accounts (with pagination)
  async getAccounts(options: {
    page?: number;
    per_page?: number;
    search?: string;
    status?: string;
    plan?: string;
  } = {}): Promise<{
    accounts: AdminAccount[];
    pagination: {
      current_page: number;
      per_page: number;
      total_count: number;
      total_pages: number;
    };
  }> {
    const params = new URLSearchParams();
    
    if (options.page) params.set('page', options.page.toString());
    if (options.per_page) params.set('per_page', options.per_page.toString());
    if (options.search) params.set('search', options.search);
    if (options.status && options.status !== 'all') params.set('status', options.status);
    if (options.plan && options.plan !== 'all') params.set('plan', options.plan);
    
    const response = await api.get(`/admin_settings/accounts?${params.toString()}`);
    return response.data;
  }

  // Get system logs
  async getSystemLogs(options: {
    page?: number;
    per_page?: number;
    level?: string;
    source?: string;
    since?: string;
  } = {}): Promise<{
    logs: SystemLog[];
    pagination: {
      current_page: number;
      per_page: number;
      total_count: number;
      total_pages: number;
    };
  }> {
    const params = new URLSearchParams();
    
    if (options.page) params.set('page', options.page.toString());
    if (options.per_page) params.set('per_page', options.per_page.toString());
    if (options.level && options.level !== 'all') params.set('level', options.level);
    if (options.source && options.source !== 'all') params.set('source', options.source);
    if (options.since) params.set('since', options.since);
    
    const response = await api.get(`/admin_settings/system_logs?${params.toString()}`);
    return response.data;
  }

  // Suspend account
  async suspendAccount(accountId: string, reason?: string): Promise<{ success: boolean; message: string }> {
    const response = await api.post('/admin_settings/suspend_account', {
      account_id: accountId,
      reason
    });
    return response.data;
  }

  // Activate account
  async activateAccount(accountId: string): Promise<{ success: boolean; message: string }> {
    const response = await api.post('/admin_settings/activate_account', {
      account_id: accountId
    });
    return response.data;
  }

  // Update admin settings
  async updateSettings(settings: Partial<AdminSettings>): Promise<{
    success: boolean;
    settings: AdminSettings;
    errors?: string[];
  }> {
    const response = await api.put('/admin_settings', { admin_settings: settings });
    return response.data;
  }

  // Test system health
  async testSystemHealth(): Promise<{
    database: 'healthy' | 'error';
    redis: 'healthy' | 'error';
    background_jobs: 'healthy' | 'error';
    payment_gateways: PaymentGatewayStatus;
    disk_space: {
      available_gb: number;
      used_percent: number;
      status: 'healthy' | 'warning' | 'critical';
    };
  }> {
    const response = await api.get('/admin_settings/health');
    return response.data;
  }

  // Utility methods
  formatBytes(bytes: number, decimals = 2): string {
    if (bytes === 0) return '0 Bytes';

    const k = 1024;
    const dm = decimals < 0 ? 0 : decimals;
    const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];

    const i = Math.floor(Math.log(bytes) / Math.log(k));
    const sizeUnit = sizes[i] || 'Bytes';

    return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizeUnit;
  }

  formatUptime(uptimeSeconds: number): string {
    const days = Math.floor(uptimeSeconds / 86400);
    const hours = Math.floor((uptimeSeconds % 86400) / 3600);
    const minutes = Math.floor((uptimeSeconds % 3600) / 60);
    
    if (days > 0) {
      return `${days}d ${hours}h ${minutes}m`;
    } else if (hours > 0) {
      return `${hours}h ${minutes}m`;
    } else {
      return `${minutes}m`;
    }
  }

  formatCurrency(amountCents: number, currency = 'USD'): string {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: currency.toUpperCase(),
    }).format(amountCents / 100);
  }

  formatNumber(num: number): string {
    return new Intl.NumberFormat().format(num);
  }

  // Rate Limiting Management
  async getRateLimitingStatistics() {
    const response = await api.get('/admin/rate_limiting/statistics');
    return response.data;
  }

  async getRateLimitingViolations() {
    const response = await api.get('/admin/rate_limiting/violations');
    return response.data;
  }

  async getRateLimitingStatus() {
    const response = await api.get('/admin/rate_limiting/status');
    return response.data;
  }

  async getUserRateLimits(identifier: string) {
    const response = await api.get(`/admin/rate_limiting/limits/${encodeURIComponent(identifier)}`);
    return response.data;
  }

  async clearUserRateLimits(identifier: string) {
    const response = await api.delete(`/admin/rate_limiting/limits/${encodeURIComponent(identifier)}`);
    return response.data;
  }

  async disableRateLimitingTemporarily(durationMinutes: number = 60) {
    const response = await api.post('/admin/rate_limiting/disable', {
      duration_minutes: durationMinutes
    });
    return response.data;
  }

  async enableRateLimiting() {
    const response = await api.post('/admin/rate_limiting/enable');
    return response.data;
  }

  // Security Configuration Management
  async getSecurityConfig(): Promise<{
    csrf: {
      enabled: boolean;
      token_name: string;
      protection_method: string;
      require_ssl: boolean;
    };
    jwt: {
      access_token_ttl: number;
      refresh_token_ttl: number;
      algorithm: string;
      blacklist_enabled: boolean;
      require_fresh_tokens_for_sensitive_operations: boolean;
    };
    authentication: {
      max_failed_attempts: number;
      lockout_duration: number;
      require_2fa_for_admin: boolean;
      session_timeout: number;
    };
    api_security: {
      rate_limiting_enabled: boolean;
      cors_enabled: boolean;
      allowed_origins: string[];
      require_api_key_for_write_operations: boolean;
    };
  }> {
    const response = await api.get('/admin_settings/security');
    return response.data;
  }

  async updateSecurityConfig(config: unknown): Promise<{
    success: boolean;
    message: string;
    config: Record<string, unknown>;
  }> {
    const response = await api.put('/admin_settings/security', { security_config: config });
    return response.data;
  }

  async testSecurityConfiguration(): Promise<{
    csrf_protection: 'working' | 'error';
    jwt_validation: 'working' | 'error';
    authentication_flow: 'working' | 'error';
    api_security: 'working' | 'error';
    overall_status: 'healthy' | 'warning' | 'error';
    details: string[];
  }> {
    const response = await api.post('/admin_settings/security/test');
    return response.data;
  }

  async regenerateJwtSecret(): Promise<{
    success: boolean;
    message: string;
    warning: string;
  }> {
    const response = await api.post('/admin_settings/security/regenerate_jwt_secret');
    return response.data;
  }

  async clearBlacklistedTokens(): Promise<{
    success: boolean;
    message: string;
    cleared_count: number;
  }> {
    const response = await api.delete('/admin_settings/security/blacklisted_tokens');
    return response.data;
  }

  getStatusColor(status: string): 'green' | 'yellow' | 'red' | 'blue' | 'gray' {
    switch (status.toLowerCase()) {
      case 'healthy':
      case 'active':
      case 'connected':
        return 'green';
      case 'warning':
      case 'delayed':
      case 'trial':
        return 'yellow';
      case 'error':
      case 'failed':
      case 'suspended':
      case 'cancelled':
        return 'red';
      case 'connecting':
      case 'pending':
        return 'blue';
      default:
        return 'gray';
    }
  }

  getLogLevelColor(level: string): 'green' | 'yellow' | 'red' | 'blue' | 'gray' {
    switch (level.toLowerCase()) {
      case 'info':
        return 'blue';
      case 'warning':
        return 'yellow';
      case 'error':
        return 'red';
      case 'debug':
        return 'gray';
      default:
        return 'gray';
    }
  }

  // Development / Enterprise Toggle
  async getDevelopmentInfo(): Promise<{ success: boolean; data?: DevelopmentInfo; error?: string }> {
    try {
      const response = await api.get('/admin_settings/development');
      const responseData = response.data;
      if (responseData.success !== undefined) {
        return responseData;
      }
      return { success: true, data: responseData };
    } catch (error) {
      const errorMessage =
        error && typeof error === 'object' && 'response' in error
          ? (error as { response?: { data?: { error?: string } } }).response?.data?.error ||
            'Failed to fetch development info'
          : 'Failed to fetch development info';
      return { success: false, error: errorMessage };
    }
  }

  async updateDevelopmentSettings(enterpriseEnabled: boolean): Promise<{ success: boolean; data: { enterprise_enabled: boolean; message: string } }> {
    const response = await api.put('/admin_settings/development', { enterprise_enabled: enterpriseEnabled });
    const responseData = response.data;
    if (responseData.success !== undefined) {
      return responseData;
    }
    return { success: true, data: responseData };
  }

  formatRelativeTime(dateString: string): string {
    const date = new Date(dateString);
    const now = new Date();
    const diffInSeconds = Math.floor((now.getTime() - date.getTime()) / 1000);
    
    if (diffInSeconds < 60) return 'Just now';
    if (diffInSeconds < 3600) return `${Math.floor(diffInSeconds / 60)}m ago`;
    if (diffInSeconds < 86400) return `${Math.floor(diffInSeconds / 3600)}h ago`;
    if (diffInSeconds < 604800) return `${Math.floor(diffInSeconds / 86400)}d ago`;
    
    return date.toLocaleDateString();
  }
}

export const adminSettingsApi = new AdminSettingsApi();
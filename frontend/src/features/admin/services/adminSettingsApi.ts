import { api } from '@/shared/services/api';

export interface ExtensionInfo {
  slug: string;
  name: string;
  description: string;
  icon: string;
  version: string;
  author: string;
  homepage?: string;
  capabilities: string[];
  installed: boolean;
  enabled: boolean;
}

// Core's admin_overview metrics (Admin::SettingsService#system_metrics).
// Billing figures are an extension's: they mount as overview slot cards.
export interface SystemMetrics {
  total_users: number;
  total_accounts: number;
  active_accounts: number;
  suspended_accounts: number;
  cancelled_accounts: number;
  system_health: 'healthy' | 'warning' | 'error';
  uptime: number;
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
  // feature_flags and system_notifications were removed here (fc-38): a
  // command grep across core, every extension and the worker found no
  // reader of either backing AdminSetting key — write-only form fields
  // nothing ever read back.
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

export interface AdminOverviewData {
  metrics: SystemMetrics;
  settings_summary: Partial<AdminSettings>;
}

export interface RedisConfig {
  host: string;
  port: number;
  database: number;
  // Always "" from the server (fc-38 review item #1) — never any part of
  // the real password. password_configured says whether one is set.
  password: string | null;
  password_configured?: boolean;
  ssl: boolean;
  url: string | null;
  connect_timeout: number;
  read_timeout: number;
  write_timeout: number;
  pool_size: number;
}

export interface RedisConnectionStatus {
  status: 'connected' | 'error';
  version?: string;
  memory_used?: string;
  memory_used_bytes?: number;
  latency_ms?: number;
  connected_clients?: number;
  uptime_days?: number;
  error?: string;
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
export interface VaultStatus {
  connected: boolean;
  sealed: boolean | null;
  initialized: boolean | null;
  version: string | null;
  cluster_name: string | null;
}

export interface VaultConfigData {
  status: VaultStatus;
  config: {
    vault_addr: string;
    // Always "" from the server (fc-38 review item #1) — never any part of
    // the real credential. The *_configured flags say whether one is set.
    vault_role_id: string;
    vault_role_id_configured: boolean;
    vault_secret_id: string;
    vault_secret_id_configured: boolean;
    configured: boolean;
  };
  keys: {
    secured_count: number;
    recent_operations: unknown[];
  };
}

export interface VaultConnectionTestData {
  connected: boolean;
  sealed?: boolean;
  initialized?: boolean;
  version?: string;
  latency_ms?: number;
  error?: string;
}

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

  // getUsers()/getAccounts() (`/admin_settings/users`, `/admin_settings/accounts`)
  // were removed here (fc-38): usersApi.getAllUsers() (`/admin/users`) and
  // accountsApi are the canonical clients now — see AdminUsersPage.tsx
  // (fc-21: the admin-dashboard UserManagement.tsx that used to be the
  // other caller had zero route/importer of its own and was deleted).
  // getAccounts() had zero callers, so no migration was needed for it.

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

  // Infrastructure Configuration
  async getInfrastructureConfig(): Promise<{ success: boolean; data?: { redis: RedisConfig; connection: RedisConnectionStatus }; error?: string }> {
    try {
      const response = await api.get('/admin_settings/infrastructure');
      const responseData = response.data;
      if (responseData.success !== undefined) {
        return responseData;
      }
      return { success: true, data: responseData };
    } catch (error) {
      const errorMessage =
        error && typeof error === 'object' && 'response' in error
          ? (error as { response?: { data?: { error?: string } } }).response?.data?.error ||
            'Failed to fetch infrastructure config'
          : 'Failed to fetch infrastructure config';
      return { success: false, error: errorMessage };
    }
  }

  // `clear_password` (fc-38 review round 3 item #3(b)) is the explicit
  // "remove this credential" signal a blank password can't be — see
  // RedisConfig's own doc comment on why blank/omitted means "unchanged".
  async updateInfrastructureConfig(config: Partial<RedisConfig> & { clear_password?: boolean }): Promise<{ success: boolean; data?: { redis: RedisConfig; message: string }; error?: string }> {
    try {
      const response = await api.put('/admin_settings/infrastructure', { redis: config });
      const responseData = response.data;
      if (responseData.success !== undefined) {
        return responseData;
      }
      return { success: true, data: responseData };
    } catch (error) {
      const errorMessage =
        error && typeof error === 'object' && 'response' in error
          ? (error as { response?: { data?: { error?: string } } }).response?.data?.error ||
            'Failed to update infrastructure config'
          : 'Failed to update infrastructure config';
      return { success: false, error: errorMessage };
    }
  }

  async testRedisConnection(config?: Partial<RedisConfig>): Promise<{ success: boolean; data?: RedisConnectionStatus; error?: string }> {
    try {
      const response = await api.post('/admin_settings/infrastructure/test_redis', config ? { redis: config } : {});
      const responseData = response.data;
      if (responseData.success !== undefined) {
        return responseData;
      }
      return { success: true, data: responseData };
    } catch (error) {
      const errorMessage =
        error && typeof error === 'object' && 'response' in error
          ? (error as { response?: { data?: { error?: string } } }).response?.data?.error ||
            'Failed to test Redis connection'
          : 'Failed to test Redis connection';
      return { success: false, error: errorMessage };
    }
  }

  // Vault Configuration
  async getVaultConfig(): Promise<{ success: boolean; data?: VaultConfigData; error?: string }> {
    try {
      const response = await api.get('/admin_settings/vault');
      const responseData = response.data;
      return responseData.success !== undefined ? responseData : { success: true, data: responseData };
    } catch (error) {
      const errorMessage = error && typeof error === 'object' && 'response' in error
        ? (error as { response?: { data?: { error?: string } } }).response?.data?.error || 'Failed to fetch Vault config'
        : 'Failed to fetch Vault config';
      return { success: false, error: errorMessage };
    }
  }

  // clear_vault_role_id/clear_vault_secret_id (fc-38 review round 3 item
  // #3(b)) are the explicit "remove this credential" signal a blank
  // role_id/secret_id can't be — same reasoning as updateInfrastructureConfig's
  // clear_password.
  async updateVaultConfig(config: {
    vault_addr?: string;
    vault_role_id?: string;
    vault_secret_id?: string;
    clear_vault_role_id?: boolean;
    clear_vault_secret_id?: boolean;
  }): Promise<{ success: boolean; data?: { message: string }; error?: string }> {
    try {
      const response = await api.put('/admin_settings/vault', { vault: config });
      return response.data;
    } catch (error) {
      const errorMessage = error && typeof error === 'object' && 'response' in error
        ? (error as { response?: { data?: { error?: string } } }).response?.data?.error || 'Failed to update Vault config'
        : 'Failed to update Vault config';
      return { success: false, error: errorMessage };
    }
  }

  async testVaultConnection(): Promise<{ success: boolean; data?: VaultConnectionTestData; error?: string }> {
    try {
      const response = await api.post('/admin_settings/vault/test');
      return response.data;
    } catch (error) {
      const errorMessage = error && typeof error === 'object' && 'response' in error
        ? (error as { response?: { data?: { error?: string } } }).response?.data?.error || 'Failed to test Vault connection'
        : 'Failed to test Vault connection';
      return { success: false, error: errorMessage };
    }
  }

  // Security Configuration Management
  //
  // getSecurityConfig/updateSecurityConfig/testSecurityConfiguration were
  // removed here (fc-21): their only caller, the unrouted admin-dashboard
  // SecuritySettings.tsx, had zero importers anywhere — AdminSettingsSecurityTabPage.tsx
  // is the live, routed security tab, and it reads/writes security settings
  // through getOverview()/updateSettings() instead, never these three. The
  // matching backend actions/routes/service methods were deleted alongside.
  //
  // regenerateJwtSecret()/clearBlacklistedTokens() were also removed here
  // (fc-21): zero callers anywhere, pre-dating SecuritySettings.tsx's own
  // deletion (it never called them either). The backend actions
  // (regenerate_jwt_secret, clear_blacklisted_tokens) are left alone —
  // secret-rotation operations, out of this task's scope; whether they get
  // a UI or are removed is an operator decision.

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

  // Extensions Management
  async getExtensions(): Promise<{ success: boolean; data?: { extensions: ExtensionInfo[] }; error?: string }> {
    try {
      const response = await api.get('/admin_settings/extensions');
      const responseData = response.data;
      if (responseData.success !== undefined) {
        return responseData;
      }
      return { success: true, data: responseData };
    } catch (error) {
      const errorMessage =
        error && typeof error === 'object' && 'response' in error
          ? (error as { response?: { data?: { error?: string } } }).response?.data?.error ||
            'Failed to fetch extensions'
          : 'Failed to fetch extensions';
      return { success: false, error: errorMessage };
    }
  }

  async toggleExtension(slug: string, enabled: boolean): Promise<{ success: boolean; data?: { slug: string; enabled: boolean; message: string }; error?: string }> {
    try {
      const response = await api.put(`/admin_settings/extensions/${slug}/toggle`, { enabled });
      const responseData = response.data;
      if (responseData.success !== undefined) {
        return responseData;
      }
      return { success: true, data: responseData };
    } catch (error) {
      const errorMessage =
        error && typeof error === 'object' && 'response' in error
          ? (error as { response?: { data?: { error?: string } } }).response?.data?.error ||
            'Failed to toggle extension'
          : 'Failed to toggle extension';
      return { success: false, error: errorMessage };
    }
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
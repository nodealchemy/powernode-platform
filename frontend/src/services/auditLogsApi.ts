import api from './api';

// Types
export interface AuditLog {
  id: string;
  action: string;
  resource_type: string;
  resource_id: string;
  source: string;
  ip_address?: string;
  user_agent?: string;
  user?: {
    id: string;
    email: string;
    full_name: string;
  };
  account?: {
    id: string;
    name: string;
  };
  metadata: Record<string, any>;
  status: 'success' | 'warning' | 'error';
  level: 'debug' | 'info' | 'warning' | 'error';
  message: string;
  created_at: string;
}

export interface DetailedAuditLog extends AuditLog {
  user_agent_parsed?: {
    raw: string;
    browser: string;
    platform: string;
    device: string;
  };
  related_logs: AuditLog[];
  risk_score: number;
}

export interface AuditLogFilters {
  action?: string;
  user_email?: string;
  account_name?: string;
  resource_type?: string;
  source?: string;
  ip_address?: string;
  date_from?: string;
  date_to?: string;
  status?: string;
  page?: number;
  limit?: number;
}

export interface AuditLogStats {
  total_logs: number;
  logs_today: number;
  logs_this_week: number;
  by_action: Record<string, number>;
  by_source: Record<string, number>;
  by_level: Record<string, number>;
  failed_logins_today: number;
  suspicious_activity_count: number;
}

export interface DetailedAuditLogStats extends AuditLogStats {
  top_users: Record<string, number>;
  top_accounts: Record<string, number>;
  hourly_distribution: Record<string, number>;
  error_trend: Record<string, number>;
}

export interface AuditLogsPagination {
  current_page: number;
  per_page: number;
  total_pages: number;
  total_count: number;
}

export interface AuditLogsResponse {
  success: boolean;
  data: {
    logs: AuditLog[];
    pagination: AuditLogsPagination;
    stats: AuditLogStats;
  };
  error?: string;
}

export interface AuditLogResponse {
  success: boolean;
  data: DetailedAuditLog;
  error?: string;
}

export interface AuditLogStatsResponse {
  success: boolean;
  data: DetailedAuditLogStats;
  error?: string;
}

export interface AuditLogExportResponse {
  success: boolean;
  data: {
    format: string;
    content?: string;
    filename?: string;
    job_id?: string;
    estimated_completion?: string;
  };
  message?: string;
  error?: string;
}

// API Service
export const auditLogsApi = {
  // Get audit logs with filters and pagination
  async getAuditLogs(
    filters: AuditLogFilters = {},
    page = 1,
    perPage = 50
  ): Promise<AuditLogsResponse> {
    try {
      const params = new URLSearchParams({
        page: page.toString(),
        per_page: perPage.toString(),
        ...Object.fromEntries(
          Object.entries(filters).filter(([_, value]) => value !== undefined && value !== '')
        ),
      });

      const response = await api.get(`/audit_logs?${params}`);
      return response.data;
    } catch (error: any) {
      return {
        success: false,
        data: {
          logs: [],
          pagination: {
            current_page: 1,
            per_page: perPage,
            total_pages: 0,
            total_count: 0
          },
          stats: {
            total_logs: 0,
            logs_today: 0,
            logs_this_week: 0,
            by_action: {},
            by_source: {},
            by_level: {},
            failed_logins_today: 0,
            suspicious_activity_count: 0
          }
        },
        error: error.response?.data?.error || 'Failed to fetch audit logs'
      };
    }
  },

  // Get single audit log with details
  async getAuditLog(id: string): Promise<AuditLogResponse> {
    try {
      const response = await api.get(`/audit_logs/${id}`);
      return response.data;
    } catch (error: any) {
      return {
        success: false,
        data: {} as DetailedAuditLog,
        error: error.response?.data?.error || 'Failed to fetch audit log'
      };
    }
  },

  // Get audit log statistics
  async getStats(): Promise<AuditLogStatsResponse> {
    try {
      const response = await api.get('/audit_logs/stats');
      return response.data;
    } catch (error: any) {
      return {
        success: false,
        data: {} as DetailedAuditLogStats,
        error: error.response?.data?.error || 'Failed to fetch audit log stats'
      };
    }
  },

  // Export audit logs
  async exportLogs(
    filters: AuditLogFilters = {},
    format: 'csv' | 'json' = 'csv'
  ): Promise<AuditLogExportResponse> {
    try {
      const response = await api.post('/audit_logs/export', {
        ...filters,
        format
      });
      return response.data;
    } catch (error: any) {
      return {
        success: false,
        data: { format },
        error: error.response?.data?.error || 'Failed to export audit logs'
      };
    }
  },

  // Cleanup old audit logs
  async cleanup(cutoffDate: Date): Promise<{ success: boolean; message?: string; error?: string; data?: any }> {
    try {
      const response = await api.delete('/audit_logs/cleanup', {
        params: {
          cutoff_date: cutoffDate.toISOString().split('T')[0] // YYYY-MM-DD format
        }
      });
      return response.data;
    } catch (error: any) {
      return {
        success: false,
        error: error.response?.data?.error || 'Failed to cleanup audit logs'
      };
    }
  },

  // Helper methods
  getLogLevelColor(level: string): string {
    switch (level) {
      case 'error': return 'bg-theme-error bg-opacity-10 text-theme-error';
      case 'warning': return 'bg-theme-warning bg-opacity-10 text-theme-warning';
      case 'info': return 'bg-theme-info bg-opacity-10 text-theme-info';
      case 'debug': return 'bg-theme-surface text-theme-tertiary';
      default: return 'bg-theme-surface text-theme-secondary';
    }
  },

  getStatusColor(status: string): string {
    switch (status) {
      case 'success': return 'bg-theme-success bg-opacity-10 text-theme-success';
      case 'warning': return 'bg-theme-warning bg-opacity-10 text-theme-warning';
      case 'error': return 'bg-theme-error bg-opacity-10 text-theme-error';
      default: return 'bg-theme-surface text-theme-secondary';
    }
  },

  formatLogDate(dateString: string): string {
    const date = new Date(dateString);
    return date.toLocaleString();
  },

  formatLogAction(action: string): string {
    return action.split('_').map(word => 
      word.charAt(0).toUpperCase() + word.slice(1)
    ).join(' ');
  },

  getRiskScoreColor(score: number): string {
    if (score >= 8) return 'bg-theme-error bg-opacity-10 text-theme-error';
    if (score >= 5) return 'bg-theme-warning bg-opacity-10 text-theme-warning';
    if (score >= 3) return 'bg-theme-info bg-opacity-10 text-theme-info';
    return 'bg-theme-success bg-opacity-10 text-theme-success';
  },

  // Available filter options
  getAvailableActions(): string[] {
    return [
      'user_login',
      'user_logout',
      'user_registration',
      'login_failed',
      'subscription_created',
      'subscription_updated',
      'payment_completed',
      'payment_failed',
      'admin_settings_update',
      'impersonation_start',
      'impersonation_end'
    ];
  },

  getAvailableSources(): string[] {
    return [
      'web',
      'api', 
      'system',
      'webhook',
      'admin_panel'
    ];
  },

  getAvailableResourceTypes(): string[] {
    return [
      'User',
      'Account',
      'Subscription',
      'Payment',
      'Invoice',
      'Plan',
      'ApiKey',
      'WebhookEndpoint',
      'SystemSettings'
    ];
  },

  getAvailableStatuses(): string[] {
    return [
      'success',
      'warning', 
      'error'
    ];
  }
};

export default auditLogsApi;
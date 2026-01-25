import { api } from '@/shared/services/api';

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
  old_values: Record<string, unknown>;
  new_values: Record<string, unknown>;
  metadata: Record<string, unknown>;
  status: 'success' | 'warning' | 'error';
  level: 'debug' | 'info' | 'warning' | 'error';
  message: string;
  changes_summary?: string;
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
  severity?: string;
  risk_level?: string;
  page?: number;
  per_page?: number;
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
  data: AuditLog[];
  meta: {
    current_page: number;
    per_page: number;
    total_pages: number;
    total: number;
  };
  error?: string;
}

export interface SecuritySummary {
  totalEvents: number;
  securityEvents: number;
  failedEvents: number;
  highRiskEvents: number;
  suspiciousEvents: number;
  uniqueUsers: number;
  uniqueIps: number;
  bySeverity: Record<string, number>;
  byRiskLevel: Record<string, number>;
  hourlyDistribution: Record<string, number>;
}

export interface ComplianceSummary {
  totalComplianceEvents: number;
  gdprRequests: number;
  ccpaRequests: number;
  dataDeletions: number;
  dataExports: number;
  securityScans: number;
  byRegulation: Record<string, number>;
  monthlyTrend: Record<string, number>;
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
    download_url?: string;
    record_count?: number;
  };
  message?: string;
  error?: string;
}

// API Service
export const auditLogsApi = {
  // Get audit logs with filters and pagination
  async getAuditLogs(filters: AuditLogFilters = {}): Promise<AuditLogsResponse> {
    try {
      const params = new URLSearchParams(
        Object.fromEntries(
          Object.entries(filters).filter(([_, value]) => value !== undefined && value !== '')
        )
      );

      const response = await api.get(`/audit_logs?${params}`);
      return response.data;
    } catch (error: unknown) {
      const httpError = error as { response?: { data?: { error?: string } } };
      return {
        success: false,
        data: [],
        meta: {
          current_page: 1,
          per_page: filters.per_page || 25,
          total_pages: 0,
          total: 0
        },
        error: httpError.response?.data?.error || 'Failed to fetch audit logs'
      };
    }
  },

  // Get security summary analytics
  async getSecuritySummary(timeRange?: string): Promise<SecuritySummary> {
    try {
      const params = timeRange ? `?time_range=${timeRange}` : '';
      const response = await api.get(`/audit_logs/security_summary${params}`);
      return response.data;
    } catch (error: unknown) {
      return {
        totalEvents: 0,
        securityEvents: 0,
        failedEvents: 0,
        highRiskEvents: 0,
        suspiciousEvents: 0,
        uniqueUsers: 0,
        uniqueIps: 0,
        bySeverity: {},
        byRiskLevel: {},
        hourlyDistribution: {}
      };
    }
  },

  // Get compliance summary analytics
  async getComplianceSummary(timeRange?: string): Promise<ComplianceSummary> {
    try {
      const params = timeRange ? `?time_range=${timeRange}` : '';
      const response = await api.get(`/audit_logs/compliance_summary${params}`);
      return response.data;
    } catch (error: unknown) {
      return {
        totalComplianceEvents: 0,
        gdprRequests: 0,
        ccpaRequests: 0,
        dataDeletions: 0,
        dataExports: 0,
        securityScans: 0,
        byRegulation: {},
        monthlyTrend: {}
      };
    }
  },

  // Get activity timeline for analytics
  async getActivityTimeline(limit = 50): Promise<any[]> {
    try {
      const response = await api.get(`/audit_logs/activity_timeline?limit=${limit}`);
      return response.data;
    } catch (error: unknown) {
      return [];
    }
  },

  // Get risk analysis data
  async getRiskAnalysis(timeRange?: string): Promise<any> {
    try {
      const params = timeRange ? `?time_range=${timeRange}` : '';
      const response = await api.get(`/audit_logs/risk_analysis${params}`);
      return response.data;
    } catch (error: unknown) {
      return {
        averageRiskScore: 0,
        highRiskPercentage: 0,
        topRiskActions: [],
        riskTrend: {}
      };
    }
  },

  // Get single audit log with details
  async getAuditLog(id: string): Promise<AuditLogResponse> {
    try {
      const response = await api.get(`/audit_logs/${id}`);
      return response.data;
    } catch (error: unknown) {
      const httpError = error as { response?: { data?: { error?: string } } };
      return {
        success: false,
        data: {} as DetailedAuditLog,
        error: httpError.response?.data?.error || 'Failed to fetch audit log'
      };
    }
  },

  // Get audit log statistics
  async getStats(): Promise<AuditLogStatsResponse> {
    try {
      const response = await api.get('/audit_logs/stats');
      return response.data;
    } catch (error: unknown) {
      const httpError = error as { response?: { data?: { error?: string } } };
      return {
        success: false,
        data: {} as DetailedAuditLogStats,
        error: httpError.response?.data?.error || 'Failed to fetch audit log stats'
      };
    }
  },

  // Export audit logs
  async exportLogs(
    exportOptions: {
      format: 'csv' | 'json' | 'pdf';
      scope: 'current' | 'filtered' | 'all';
      includeMetadata: boolean;
      includeSensitiveData: boolean;
      maxRecords: number;
      filters?: AuditLogFilters;
      customDateRange?: {
        enabled: boolean;
        startDate: string;
        endDate: string;
      };
    }
  ): Promise<AuditLogExportResponse> {
    try {
      const response = await api.post('/audit_logs/export', exportOptions);
      return response.data;
    } catch (error: unknown) {
      const httpError = error as { response?: { data?: { error?: string } } };
      return {
        success: false,
        data: { format: exportOptions.format },
        error: httpError.response?.data?.error || 'Failed to export audit logs'
      };
    }
  },

  // Cleanup old audit logs
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  async cleanup(cutoffDate: Date): Promise<{ success: boolean; message?: string; error?: string; data?: any }> {
    try {
      const response = await api.delete('/audit_logs/cleanup', {
        params: {
          cutoff_date: cutoffDate.toISOString().split('T')[0] // YYYY-MM-DD format
        }
      });
      return response.data;
    } catch (error: unknown) {
      const httpError = error as { response?: { data?: { error?: string } } };
      return {
        success: false,
        error: httpError.response?.data?.error || 'Failed to cleanup audit logs'
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
      'password_reset',
      'subscription_created',
      'subscription_updated',
      'subscription_cancelled',
      'payment_completed',
      'payment_failed',
      'payment_refunded',
      'admin_settings_update',
      'impersonation_started',
      'impersonation_ended',
      'account_locked',
      'account_unlocked',
      'password_changed',
      'two_factor_enabled',
      'two_factor_disabled',
      'api_key_created',
      'security_alert',
      'fraud_detection',
      'suspicious_activity',
      'gdpr_request',
      'ccpa_request',
      'data_export',
      'audit_log_cleanup'
    ];
  },

  getAvailableSeverityLevels(): string[] {
    return [
      'low',
      'medium', 
      'high',
      'critical'
    ];
  },

  getAvailableRiskLevels(): string[] {
    return [
      'low',
      'medium',
      'high', 
      'critical'
    ];
  },

  getAvailableSources(): string[] {
    return [
      'web',
      'api', 
      'system',
      'webhook',
      'admin_panel',
      'mobile_app',
      'integration',
      'automation',
      'scheduler'
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
import { api } from '@/shared/services/api';

// Types
export interface ComponentStatus {
  name: string;
  status: 'operational' | 'degraded' | 'partial_outage' | 'major_outage';
  response_time: number | null;
  description: string;
  metadata?: Record<string, unknown>;
}

export interface Incident {
  id: string;
  title: string;
  status: 'investigating' | 'identified' | 'monitoring' | 'resolved';
  impact: 'none' | 'minor' | 'major' | 'critical';
  started_at: string;
  updated_at: string;
}

export interface UptimeStats {
  last_24_hours: number;
  last_7_days: number;
  last_30_days: number;
  last_90_days: number;
}

export interface SystemStatus {
  overall_status: 'operational' | 'degraded' | 'partial_outage' | 'major_outage';
  components: Record<string, ComponentStatus>;
  incidents: Incident[];
  uptime: UptimeStats;
  last_updated: string;
}

export interface StatusSummary {
  status: 'operational' | 'degraded' | 'partial_outage' | 'major_outage';
  components_operational: number;
  components_total: number;
  active_incidents: number;
  uptime_30_days: number;
  last_updated: string;
}

export interface DailyStatus {
  date: string;
  status: 'operational' | 'degraded' | 'partial_outage' | 'major_outage';
  uptime_percentage: number;
}

export interface StatusHistory {
  period: string;
  uptime_percentage: number;
  daily_status: DailyStatus[];
  incidents_count: number;
  average_response_time_ms: number;
}

// API Service
export const statusApi = {
  // Get full system status
  async getStatus(): Promise<{ success: boolean; data?: SystemStatus; error?: string }> {
    try {
      const response = await api.get('/public/status');
      return response.data;
    } catch {
      const errorMessage =
        error && typeof error === 'object' && 'response' in error
          ? (error as { response?: { data?: { error?: string } } }).response?.data?.error ||
            'Failed to fetch status'
          : 'Failed to fetch status';
      return { success: false, error: errorMessage };
    }
  },

  // Get status summary
  async getSummary(): Promise<{ success: boolean; data?: StatusSummary; error?: string }> {
    try {
      const response = await api.get('/public/status/summary');
      return response.data;
    } catch {
      const errorMessage =
        error && typeof error === 'object' && 'response' in error
          ? (error as { response?: { data?: { error?: string } } }).response?.data?.error ||
            'Failed to fetch summary'
          : 'Failed to fetch summary';
      return { success: false, error: errorMessage };
    }
  },

  // Get status history
  async getHistory(): Promise<{ success: boolean; data?: StatusHistory; error?: string }> {
    try {
      const response = await api.get('/public/status/history');
      return response.data;
    } catch {
      const errorMessage =
        error && typeof error === 'object' && 'response' in error
          ? (error as { response?: { data?: { error?: string } } }).response?.data?.error ||
            'Failed to fetch history'
          : 'Failed to fetch history';
      return { success: false, error: errorMessage };
    }
  },

  // Helper methods
  getStatusColor(status: string): string {
    switch (status) {
      case 'operational':
        return 'bg-theme-success';
      case 'degraded':
        return 'bg-theme-warning';
      case 'partial_outage':
        return 'bg-theme-warning';
      case 'major_outage':
        return 'bg-theme-danger';
      default:
        return 'bg-theme-surface';
    }
  },

  getStatusBgColor(status: string): string {
    switch (status) {
      case 'operational':
        return 'bg-theme-success/20 dark:bg-theme-success/30';
      case 'degraded':
        return 'bg-theme-warning/20 dark:bg-theme-warning/30';
      case 'partial_outage':
        return 'bg-theme-warning/20 dark:bg-theme-warning/30';
      case 'major_outage':
        return 'bg-theme-danger/20 dark:bg-theme-danger/30';
      default:
        return 'bg-theme-surface dark:bg-theme-background/30';
    }
  },

  getStatusTextColor(status: string): string {
    switch (status) {
      case 'operational':
        return 'text-theme-success';
      case 'degraded':
        return 'text-theme-warning';
      case 'partial_outage':
        return 'text-theme-warning';
      case 'major_outage':
        return 'text-theme-danger';
      default:
        return 'text-theme-muted';
    }
  },

  getStatusLabel(status: string): string {
    switch (status) {
      case 'operational':
        return 'All Systems Operational';
      case 'degraded':
        return 'Degraded Performance';
      case 'partial_outage':
        return 'Partial Outage';
      case 'major_outage':
        return 'Major Outage';
      default:
        return 'Unknown';
    }
  },

  getIncidentStatusLabel(status: string): string {
    switch (status) {
      case 'investigating':
        return 'Investigating';
      case 'identified':
        return 'Identified';
      case 'monitoring':
        return 'Monitoring';
      case 'resolved':
        return 'Resolved';
      default:
        return status;
    }
  },

  getIncidentImpactColor(impact: string): string {
    switch (impact) {
      case 'none':
        return 'text-theme-muted';
      case 'minor':
        return 'text-theme-warning';
      case 'major':
        return 'text-theme-warning';
      case 'critical':
        return 'text-theme-danger';
      default:
        return 'text-theme-muted';
    }
  },
};

export default statusApi;

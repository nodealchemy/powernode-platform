import { api } from '@/shared/services/api';

// Helper function for making API requests
const apiRequest = async (endpoint: string, options: RequestInit = {}) => {
  try {
    const method = (options.method || 'GET').toLowerCase();
    const data = options.body ? JSON.parse(options.body as string) : undefined;
    
    let response;
    switch (method) {
      case 'get':
        response = await api.get(endpoint);
        break;
      case 'post':
        response = await api.post(endpoint, data);
        break;
      case 'patch':
        response = await api.patch(endpoint, data);
        break;
      case 'put':
        response = await api.put(endpoint, data);
        break;
      case 'delete':
        response = await api.delete(endpoint);
        break;
      default:
        response = await api.get(endpoint);
    }
    
    return response.data;
  } catch (error: any) {
    // Re-throw with better error context
    throw new Error(error.response?.data?.error || error.message || 'API request failed');
  }
};

export interface MaintenanceStatus {
  mode: boolean;
  message?: string;
  scheduled_start?: string;
  scheduled_end?: string;
  scheduled_message?: string;
}

export interface BackupInfo {
  id: string;
  filename: string;
  size: number;
  created_at: string;
  type: 'manual' | 'scheduled';
  status: 'completed' | 'in_progress' | 'failed';
  download_url?: string;
}

export interface SystemHealth {
  overall_status: 'healthy' | 'warning' | 'critical';
  database: {
    status: 'healthy' | 'warning' | 'critical';
    connection_time: number;
    size: number;
    last_backup: string;
  };
  redis: {
    status: 'healthy' | 'warning' | 'critical';
    memory_usage: number;
    connected_clients: number;
  };
  storage: {
    status: 'healthy' | 'warning' | 'critical';
    total_space: number;
    used_space: number;
    available_space: number;
  };
  services: {
    name: string;
    status: 'healthy' | 'warning' | 'critical';
    uptime: number;
    memory_usage: number;
  }[];
}

export interface CleanupStats {
  old_logs: number;
  expired_sessions: number;
  temporary_files: number;
  audit_logs_older_than_90_days: number;
  orphaned_uploads: number;
  cache_entries: number;
}

export interface MaintenanceSchedule {
  id: string;
  type: 'backup' | 'cleanup' | 'restart' | 'maintenance_mode';
  scheduled_at: string;
  frequency: 'once' | 'daily' | 'weekly' | 'monthly';
  enabled: boolean;
  last_run?: string;
  next_run: string;
  description: string;
}

export interface MaintenanceSystemMetrics {
  cpu_usage: number;
  memory_usage: number;
  disk_usage: number;
  active_users: number;
  database_connections: number;
  queue_size: number;
  response_time_avg: number;
  error_rate: number;
  uptime: number;
}

class MaintenanceApiService {
  // Maintenance Mode
  async getMaintenanceStatus(): Promise<MaintenanceStatus> {
    const response = await apiRequest('/admin/maintenance/status', {
      method: 'GET'
    });
    return response.data;
  }

  async setMaintenanceMode(enabled: boolean, message?: string, scheduledStart?: string, scheduledEnd?: string): Promise<void> {
    await apiRequest('/admin/maintenance/mode', {
      method: 'PUT',
      body: JSON.stringify({
        enabled,
        message,
        scheduled_start: scheduledStart,
        scheduled_end: scheduledEnd
      })
    });
  }

  async scheduleMaintenanceMode(startTime: string, endTime: string, message: string): Promise<void> {
    await apiRequest('/admin/maintenance/schedule', {
      method: 'POST',
      body: JSON.stringify({
        scheduled_start: startTime,
        scheduled_end: endTime,
        message
      })
    });
  }

  // Database Backups
  async getBackups(): Promise<BackupInfo[]> {
    const response = await apiRequest('/admin/maintenance/backups', {
      method: 'GET'
    });
    return response.data ?? [];
  }

  async createBackup(): Promise<{ backup_id: string }> {
    const response = await apiRequest('/admin/maintenance/backups', {
      method: 'POST'
    });
    return response.data;
  }

  async deleteBackup(backupId: string): Promise<void> {
    await apiRequest(`/admin/maintenance/backups/${backupId}`, {
      method: 'DELETE'
    });
  }

  async restoreBackup(backupId: string): Promise<void> {
    await apiRequest(`/admin/maintenance/backups/${backupId}/restore`, {
      method: 'POST'
    });
  }

  async downloadBackup(backupId: string): Promise<string> {
    const response = await apiRequest(`/admin/maintenance/backups/${backupId}/download`, {
      method: 'GET'
    });
    return response.data.download_url;
  }

  // System Health
  async getSystemHealth(): Promise<SystemHealth> {
    const response = await apiRequest('/admin/maintenance/health', {
      method: 'GET'
    });
    return response.data;
  }

  async getSystemMetrics(): Promise<MaintenanceSystemMetrics> {
    const response = await apiRequest('/admin/maintenance/metrics', {
      method: 'GET'
    });
    return response.data;
  }

  // Data Cleanup
  async getCleanupStats(): Promise<CleanupStats> {
    const response = await apiRequest('/admin/maintenance/cleanup/stats', {
      method: 'GET'
    });
    return response.data;
  }

  async runCleanup(options: {
    old_logs?: boolean;
    expired_sessions?: boolean;
    temporary_files?: boolean;
    audit_logs?: boolean;
    orphaned_uploads?: boolean;
    cache_entries?: boolean;
  }): Promise<{ cleaned_items: number; freed_space: number }> {
    const response = await apiRequest('/admin/maintenance/cleanup', {
      method: 'POST',
      body: JSON.stringify(options)
    });
    return response.data;
  }

  // System Operations
  async restartService(serviceName: string): Promise<void> {
    await apiRequest('/admin/maintenance/services/restart', {
      method: 'POST',
      body: JSON.stringify({ service: serviceName })
    });
  }

  async restartSystem(): Promise<void> {
    await apiRequest('/admin/maintenance/system/restart', {
      method: 'POST'
    });
  }

  async flushCache(): Promise<void> {
    await apiRequest('/admin/maintenance/cache/flush', {
      method: 'POST'
    });
  }

  async optimizeDatabase(): Promise<{ tables_optimized: number; space_freed: number }> {
    const response = await apiRequest('/admin/maintenance/database/optimize', {
      method: 'POST'
    });
    return response.data;
  }

  // Maintenance Scheduling
  async getMaintenanceSchedules(): Promise<MaintenanceSchedule[]> {
    const response = await apiRequest('/admin/maintenance/schedules', {
      method: 'GET'
    });
    return response.data ?? [];
  }

  async createMaintenanceSchedule(schedule: Omit<MaintenanceSchedule, 'id' | 'next_run' | 'last_run'>): Promise<MaintenanceSchedule> {
    const response = await apiRequest('/admin/maintenance/schedules', {
      method: 'POST',
      body: JSON.stringify(schedule)
    });
    return response.data;
  }

  async updateMaintenanceSchedule(scheduleId: string, updates: Partial<MaintenanceSchedule>): Promise<MaintenanceSchedule> {
    const response = await apiRequest(`/admin/maintenance/schedules/${scheduleId}`, {
      method: 'PUT',
      body: JSON.stringify(updates)
    });
    return response.data;
  }

  async deleteMaintenanceSchedule(scheduleId: string): Promise<void> {
    await apiRequest(`/admin/maintenance/schedules/${scheduleId}`, {
      method: 'DELETE'
    });
  }

  async runScheduledTask(scheduleId: string): Promise<void> {
    await apiRequest(`/admin/maintenance/schedules/${scheduleId}/run`, {
      method: 'POST'
    });
  }

  // Utility methods
  formatBytes(bytes: number): string {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'] as const;
    const i = Math.min(Math.floor(Math.log(bytes) / Math.log(k)), sizes.length - 1);
    
    // Safe array access with known bounds
    let size: string;
    if (i === 0) size = 'Bytes';
    else if (i === 1) size = 'KB';
    else if (i === 2) size = 'MB';
    else if (i === 3) size = 'GB';
    else size = 'TB';
    
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + size;
  }

  formatUptime(seconds: number): string {
    const days = Math.floor(seconds / (24 * 3600));
    const hours = Math.floor((seconds % (24 * 3600)) / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    
    if (days > 0) {
      return `${days}d ${hours}h ${minutes}m`;
    } else if (hours > 0) {
      return `${hours}h ${minutes}m`;
    } else {
      return `${minutes}m`;
    }
  }

  getStatusColor(status: string): string {
    switch (status) {
      case 'healthy': return 'text-theme-success';
      case 'warning': return 'text-theme-warning';
      case 'critical': return 'text-theme-error';
      default: return 'text-theme-secondary';
    }
  }

  getStatusBgColor(status: string): string {
    switch (status) {
      case 'healthy': return 'bg-theme-success-background';
      case 'warning': return 'bg-theme-warning-background';
      case 'critical': return 'bg-theme-error-background';
      default: return 'bg-theme-background-secondary';
    }
  }
}

export const maintenanceApi = new MaintenanceApiService();
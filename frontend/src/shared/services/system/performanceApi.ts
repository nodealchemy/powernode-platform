import { api } from '@/shared/services/api';
import { isErrorWithResponse } from '@/shared/utils/errorHandling';

// Types
export interface SystemMetrics {
  id: string;
  timestamp: string;
  cpu_usage: number;
  memory_usage: number;
  disk_usage: number;
  network_io: {
    bytes_in: number;
    bytes_out: number;
  };
  database_connections: number;
  active_sessions: number;
  queue_size: number;
  response_time_avg: number;
  error_rate: number;
}

export interface PerformanceSettings {
  cache_enabled: boolean;
  cache_ttl: number;
  max_connections: number;
  query_timeout: number;
  rate_limiting_enabled: boolean;
  compression_enabled: boolean;
  cdn_enabled: boolean;
  database_pool_size: number;
  worker_processes: number;
  log_level: 'debug' | 'info' | 'warn' | 'error';
  monitoring_enabled: boolean;
  alert_thresholds: {
    cpu_threshold: number;
    memory_threshold: number;
    disk_threshold: number;
    error_rate_threshold: number;
    response_time_threshold: number;
  };
}

export interface PerformanceAlert {
  id: string;
  type: 'cpu' | 'memory' | 'disk' | 'error_rate' | 'response_time' | 'queue_size';
  severity: 'low' | 'medium' | 'high' | 'critical';
  message: string;
  value: number;
  threshold: number;
  triggered_at: string;
  resolved_at?: string;
  status: 'active' | 'resolved';
}

export interface PerformanceStats {
  current_metrics: SystemMetrics;
  historical_data: SystemMetrics[];
  active_alerts: PerformanceAlert[];
  optimization_suggestions: string[];
  system_health_score: number;
  uptime_percentage: number;
  peak_usage_times: Array<{
    hour: number;
    cpu_avg: number;
    memory_avg: number;
  }>;
}

export interface CacheStats {
  total_keys: number;
  hit_rate: number;
  miss_rate: number;
  memory_usage: number;
  evictions: number;
  expired_keys: number;
  operations_per_second: number;
}

export interface DatabaseStats {
  active_connections: number;
  max_connections: number;
  slow_queries: number;
  avg_query_time: number;
  deadlocks: number;
  table_locks: number;
  index_usage: number;
  cache_hit_ratio: number;
}

export interface QueueStats {
  total_jobs: number;
  pending_jobs: number;
  processing_jobs: number;
  failed_jobs: number;
  completed_jobs: number;
  avg_processing_time: number;
  queue_latency: number;
  workers_active: number;
}

export interface OptimizationAction {
  id: string;
  type: 'cache_clear' | 'restart_workers' | 'compress_logs' | 'rebuild_indexes' | 'cleanup_temp_files';
  name: string;
  description: string;
  estimated_impact: 'low' | 'medium' | 'high';
  risk_level: 'safe' | 'medium' | 'high';
  estimated_time: string;
}

// API Service
export const performanceApi = {
  // Get current system metrics
  async getSystemMetrics(): Promise<{ success: boolean; data?: SystemMetrics; error?: string }> {
    try {
      const response = await api.get('/admin/performance/metrics');
      return response.data;
    } catch {
      return {
        success: false,
        error: isErrorWithResponse(error) ? (error.response?.data?.error || 'Failed to fetch system metrics') : 'Failed to fetch system metrics'
      };
    }
  },

  // Get performance statistics
  async getPerformanceStats(timeRange = '24h'): Promise<{ success: boolean; data?: PerformanceStats; error?: string }> {
    try {
      const response = await api.get(`/admin/performance/stats?time_range=${timeRange}`);
      return response.data;
    } catch {
      return {
        success: false,
        error: isErrorWithResponse(error) ? (error.response?.data?.error || 'Failed to fetch performance stats') : 'Failed to fetch performance stats'
      };
    }
  },

  // Get performance settings
  async getSettings(): Promise<{ success: boolean; data?: PerformanceSettings; error?: string }> {
    try {
      const response = await api.get('/admin/performance/settings');
      return response.data;
    } catch {
      return {
        success: false,
        error: isErrorWithResponse(error) ? (error.response?.data?.error || 'Failed to fetch performance settings') : 'Failed to fetch performance settings'
      };
    }
  },

  // Update performance settings
  async updateSettings(settings: Partial<PerformanceSettings>): Promise<{ success: boolean; data?: PerformanceSettings; message?: string; error?: string }> {
    try {
      const response = await api.put('/admin/performance/settings', { settings });
      return response.data;
    } catch {
      return {
        success: false,
        error: isErrorWithResponse(error) ? (error.response?.data?.error || 'Failed to update performance settings') : 'Failed to update performance settings'
      };
    }
  },

  // Get cache statistics
  async getCacheStats(): Promise<{ success: boolean; data?: CacheStats; error?: string }> {
    try {
      const response = await api.get('/admin/performance/cache');
      return response.data;
    } catch {
      return {
        success: false,
        error: isErrorWithResponse(error) ? (error.response?.data?.error || 'Failed to fetch cache stats') : 'Failed to fetch cache stats'
      };
    }
  },

  // Get database statistics
  async getDatabaseStats(): Promise<{ success: boolean; data?: DatabaseStats; error?: string }> {
    try {
      const response = await api.get('/admin/performance/database');
      return response.data;
    } catch {
      return {
        success: false,
        error: isErrorWithResponse(error) ? (error.response?.data?.error || 'Failed to fetch database stats') : 'Failed to fetch database stats'
      };
    }
  },

  // Get queue statistics
  async getQueueStats(): Promise<{ success: boolean; data?: QueueStats; error?: string }> {
    try {
      const response = await api.get('/admin/performance/queue');
      return response.data;
    } catch {
      return {
        success: false,
        error: isErrorWithResponse(error) ? (error.response?.data?.error || 'Failed to fetch queue stats') : 'Failed to fetch queue stats'
      };
    }
  },

  // Get active alerts
  async getActiveAlerts(): Promise<{ success: boolean; data?: PerformanceAlert[]; error?: string }> {
    try {
      const response = await api.get('/admin/performance/alerts');
      return response.data;
    } catch {
      return {
        success: false,
        error: isErrorWithResponse(error) ? (error.response?.data?.error || 'Failed to fetch performance alerts') : 'Failed to fetch performance alerts'
      };
    }
  },

  // Dismiss alert
  async dismissAlert(alertId: string): Promise<{ success: boolean; message?: string; error?: string }> {
    try {
      const response = await api.post(`/admin/performance/alerts/${alertId}/dismiss`);
      return response.data;
    } catch {
      return {
        success: false,
        error: isErrorWithResponse(error) ? (error.response?.data?.error || 'Failed to dismiss alert') : 'Failed to dismiss alert'
      };
    }
  },

  // Get available optimization actions
  async getOptimizationActions(): Promise<{ success: boolean; data?: OptimizationAction[]; error?: string }> {
    try {
      const response = await api.get('/admin/performance/optimizations');
      return response.data;
    } catch {
      return {
        success: false,
        error: isErrorWithResponse(error) ? (error.response?.data?.error || 'Failed to fetch optimization actions') : 'Failed to fetch optimization actions'
      };
    }
  },

  // Execute optimization action
  async executeOptimization(actionId: string): Promise<{ success: boolean; message?: string; error?: string }> {
    try {
      const response = await api.post(`/admin/performance/optimizations/${actionId}/execute`);
      return response.data;
    } catch {
      return {
        success: false,
        error: isErrorWithResponse(error) ? (error.response?.data?.error || 'Failed to execute optimization') : 'Failed to execute optimization'
      };
    }
  },

  // Clear cache
  async clearCache(cacheType?: string): Promise<{ success: boolean; message?: string; error?: string }> {
    try {
      const response = await api.post('/admin/performance/cache/clear', { cache_type: cacheType });
      return response.data;
    } catch {
      return {
        success: false,
        error: isErrorWithResponse(error) ? (error.response?.data?.error || 'Failed to clear cache') : 'Failed to clear cache'
      };
    }
  },

  // Restart workers
  async restartWorkers(): Promise<{ success: boolean; message?: string; error?: string }> {
    try {
      const response = await api.post('/admin/performance/workers/restart');
      return response.data;
    } catch {
      return {
        success: false,
        error: isErrorWithResponse(error) ? (error.response?.data?.error || 'Failed to restart workers') : 'Failed to restart workers'
      };
    }
  },

  // Generate performance report
  async generateReport(timeRange = '7d', format = 'pdf'): Promise<{ success: boolean; message?: string; error?: string }> {
    try {
      const response = await api.post('/admin/performance/reports/generate', {
        time_range: timeRange,
        format: format
      });
      return response.data;
    } catch {
      return {
        success: false,
        error: isErrorWithResponse(error) ? (error.response?.data?.error || 'Failed to generate performance report') : 'Failed to generate performance report'
      };
    }
  },

  // Helper methods
  getMetricColor(value: number, thresholds: { warn: number; critical: number }): string {
    if (value >= thresholds.critical) return 'text-theme-error';
    if (value >= thresholds.warn) return 'text-theme-warning';
    return 'text-theme-success';
  },

  getMetricBackgroundColor(value: number, thresholds: { warn: number; critical: number }): string {
    if (value >= thresholds.critical) return 'bg-theme-error-background';
    if (value >= thresholds.warn) return 'bg-theme-warning-background';
    return 'bg-theme-success-background';
  },

  getAlertSeverityColor(severity: string): string {
    switch (severity) {
      case 'critical': return 'bg-theme-error bg-opacity-10 text-theme-error';
      case 'high': return 'bg-theme-error bg-opacity-5 text-theme-error';
      case 'medium': return 'bg-theme-warning bg-opacity-10 text-theme-warning';
      case 'low': return 'bg-theme-info bg-opacity-10 text-theme-info';
      default: return 'bg-theme-surface text-theme-secondary';
    }
  },

  getHealthScoreColor(score: number): string {
    if (score >= 90) return 'text-theme-success';
    if (score >= 70) return 'text-theme-warning';
    return 'text-theme-error';
  },

  formatBytes(bytes: number): string {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    
    let size = 'Bytes';
    let unitIndex = 0;
    
    if (i === 0) { size = 'Bytes'; unitIndex = 0; }
    else if (i === 1) { size = 'KB'; unitIndex = 1; }
    else if (i === 2) { size = 'MB'; unitIndex = 2; }
    else if (i === 3) { size = 'GB'; unitIndex = 3; }
    else if (i >= 4) { size = 'TB'; unitIndex = 4; }
    
    return parseFloat((bytes / Math.pow(k, unitIndex)).toFixed(2)) + ' ' + size;
  },

  formatUptime(seconds: number): string {
    const days = Math.floor(seconds / 86400);
    const hours = Math.floor((seconds % 86400) / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    
    if (days > 0) return `${days}d ${hours}h ${minutes}m`;
    if (hours > 0) return `${hours}h ${minutes}m`;
    return `${minutes}m`;
  },

  formatPercentage(value: number): string {
    return `${value.toFixed(1)}%`;
  },

  validateSettings(settings: Partial<PerformanceSettings>): string[] {
    const errors: string[] = [];

    if (settings.cache_ttl && (settings.cache_ttl < 60 || settings.cache_ttl > 86400)) {
      errors.push('Cache TTL must be between 60 seconds and 24 hours');
    }

    if (settings.max_connections && (settings.max_connections < 10 || settings.max_connections > 1000)) {
      errors.push('Max connections must be between 10 and 1000');
    }

    if (settings.query_timeout && (settings.query_timeout < 1 || settings.query_timeout > 300)) {
      errors.push('Query timeout must be between 1 and 300 seconds');
    }

    if (settings.database_pool_size && (settings.database_pool_size < 5 || settings.database_pool_size > 100)) {
      errors.push('Database pool size must be between 5 and 100');
    }

    if (settings.worker_processes && (settings.worker_processes < 1 || settings.worker_processes > 20)) {
      errors.push('Worker processes must be between 1 and 20');
    }

    return errors;
  }
};

export default performanceApi;
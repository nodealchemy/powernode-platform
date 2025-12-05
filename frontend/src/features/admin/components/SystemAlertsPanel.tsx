import React, { useState, useEffect } from 'react';
import { Button } from '@/shared/components/ui/Button';
import { 
  AlertTriangle, AlertCircle, CheckCircle, Clock,
  Trash2, Bell, Filter
} from 'lucide-react';
import { performanceApi, PerformanceAlert } from '@/shared/services/performanceApi';
import { useNotifications } from '@/shared/hooks/useNotifications';

interface SystemAlertsPanelProps {
  autoRefresh?: boolean;
  refreshInterval?: number;
  maxDisplayedAlerts?: number;
}

interface AlertFilters {
  severity: string[];
  type: string[];
  status: string[];
}

export const SystemAlertsPanel: React.FC<SystemAlertsPanelProps> = ({
  autoRefresh = true,
  refreshInterval = 30000,
  maxDisplayedAlerts = 10
}) => {
  const [alerts, setAlerts] = useState<PerformanceAlert[]>([]);
  const [loading, setLoading] = useState(true);
  const [filters, setFilters] = useState<AlertFilters>({
    severity: [],
    type: [],
    status: ['active']
  });
  const [showFilters, setShowFilters] = useState(false);
  const [dismissingAlerts, setDismissingAlerts] = useState<Set<string>>(new Set());

  const { showNotification } = useNotifications();

  useEffect(() => {
    loadAlerts();

    // Temporarily disable auto-refresh to debug page refresh issues
    // if (autoRefresh) {
    //   const interval = setInterval(loadAlerts, refreshInterval);
    //   return () => clearInterval(interval);
    // }
  }, [autoRefresh, refreshInterval]);

  const loadAlerts = async () => {
    try {
      const response = await performanceApi.getActiveAlerts();
      if (response.success && response.data) {
        setAlerts(response.data);
      }
    } catch (error) {
    } finally {
      setLoading(false);
    }
  };

  const dismissAlert = async (alertId: string) => {
    try {
      setDismissingAlerts(prev => {
        const newSet = new Set(prev);
        newSet.add(alertId);
        return newSet;
      });
      
      const response = await performanceApi.dismissAlert(alertId);
      if (response.success) {
        setAlerts(prev => prev.filter(alert => alert.id !== alertId));
        showNotification('Alert dismissed successfully', 'success');
      } else {
        showNotification(response.error || 'Failed to dismiss alert', 'error');
      }
    } catch (error) {
      showNotification('Failed to dismiss alert', 'error');
    } finally {
      setDismissingAlerts(prev => {
        const newSet = new Set(prev);
        newSet.delete(alertId);
        return newSet;
      });
    }
  };

  const getSeverityConfig = (severity: string) => {
    switch (severity) {
      case 'critical':
        return {
          color: 'border-theme-error bg-theme-error-background',
          textColor: 'text-theme-error',
          icon: AlertTriangle,
          iconColor: 'text-theme-error'
        };
      case 'high':
        return {
          color: 'border-theme-error bg-theme-error-background',
          textColor: 'text-theme-error', 
          icon: AlertCircle,
          iconColor: 'text-theme-error'
        };
      case 'medium':
        return {
          color: 'border-theme-warning bg-theme-warning-background',
          textColor: 'text-theme-warning',
          icon: AlertCircle,
          iconColor: 'text-theme-warning'
        };
      case 'low':
        return {
          color: 'border-theme-info bg-theme-info-background',
          textColor: 'text-theme-info',
          icon: AlertCircle,
          iconColor: 'text-theme-info'
        };
      default:
        return {
          color: 'border-theme bg-theme-surface',
          textColor: 'text-theme-secondary',
          icon: AlertCircle,
          iconColor: 'text-theme-secondary'
        };
    }
  };

  const getTypeDisplayName = (type: PerformanceAlert['type']) => {
    switch (type) {
      case 'cpu': return 'CPU Usage';
      case 'memory': return 'Memory Usage';
      case 'disk': return 'Disk Usage';
      case 'error_rate': return 'Error Rate';
      case 'response_time': return 'Response Time';
      case 'queue_size': return 'Queue Size';
    }
  };

  const filteredAlerts = alerts.filter(alert => {
    if (filters.severity.length > 0 && !filters.severity.includes(alert.severity)) return false;
    if (filters.type.length > 0 && !filters.type.includes(alert.type)) return false;
    if (filters.status.length > 0 && !filters.status.includes(alert.status)) return false;
    return true;
  }).slice(0, maxDisplayedAlerts);

  const toggleFilter = (filterType: keyof AlertFilters, value: string) => {
    setFilters(prev => {
      switch (filterType) {
        case 'severity': {
          const currentFilter = prev.severity;
          const newFilter = currentFilter.includes(value)
            ? currentFilter.filter(v => v !== value)
            : [...currentFilter, value];
          return { ...prev, severity: newFilter };
        }
        case 'type': {
          const currentFilter = prev.type;
          const newFilter = currentFilter.includes(value)
            ? currentFilter.filter(v => v !== value)
            : [...currentFilter, value];
          return { ...prev, type: newFilter };
        }
        case 'status': {
          const currentFilter = prev.status;
          const newFilter = currentFilter.includes(value)
            ? currentFilter.filter(v => v !== value)
            : [...currentFilter, value];
          return { ...prev, status: newFilter };
        }
        default:
          return prev;
      }
    });
  };

  if (loading) {
    return (
      <div className="bg-theme-surface rounded-lg border border-theme p-6">
        <div className="animate-pulse space-y-4">
          <div className="h-4 bg-theme-background rounded w-1/4"></div>
          <div className="space-y-3">
            {[1, 2, 3].map(i => (
              <div key={i} className="h-16 bg-theme-background rounded"></div>
            ))}
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="bg-theme-surface rounded-lg border border-theme">
      {/* Header */}
      <div className="px-6 py-4 border-b border-theme">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-theme-error bg-opacity-10 rounded-lg">
              <Bell className="w-5 h-5 text-theme-error" />
            </div>
            <div>
              <h3 className="text-lg font-semibold text-theme-primary">System Alerts</h3>
              <p className="text-sm text-theme-secondary">
                {filteredAlerts.length} active alert{filteredAlerts.length !== 1 ? 's' : ''}
              </p>
            </div>
          </div>
          
          <div className="flex items-center gap-2">
            <Button variant="outline" onClick={() => setShowFilters(!showFilters)}
              className="p-2 border border-theme rounded-md text-theme-primary hover:bg-theme-surface transition-colors"
              title="Toggle filters"
            >
              <Filter className="w-4 h-4" />
            </Button>
            
            <Button onClick={loadAlerts} variant="outline">
              <Clock className="w-4 h-4" />
            </Button>
          </div>
        </div>

        {/* Filters */}
        {showFilters && (
          <div className="mt-4 p-4 bg-theme-background rounded-lg space-y-3">
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">Severity</label>
              <div className="flex flex-wrap gap-2">
                {['critical', 'high', 'medium', 'low'].map(severity => (
                  <Button variant="outline" onClick={() => toggleFilter('severity', severity)}
                    className={`px-3 py-1 rounded-full text-sm font-medium transition-colors ${
                      filters.severity.includes(severity)
                        ? 'bg-theme-interactive-primary text-white'
                        : 'bg-theme-surface border border-theme text-theme-secondary hover:text-theme-primary'
                    }`}
                  >
                    {severity.charAt(0).toUpperCase() + severity.slice(1)}
                  </Button>
                ))}
              </div>
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">Type</label>
              <div className="flex flex-wrap gap-2">
                {(['cpu', 'memory', 'disk', 'error_rate', 'response_time', 'queue_size'] as const).map((type: PerformanceAlert['type']) => (
                  <Button variant="outline" onClick={() => toggleFilter('type', type)}
                    className={`px-3 py-1 rounded-full text-sm font-medium transition-colors ${
                      filters.type.includes(type)
                        ? 'bg-theme-interactive-primary text-white'
                        : 'bg-theme-surface border border-theme text-theme-secondary hover:text-theme-primary'
                    }`}
                  >
                    {getTypeDisplayName(type)}
                  </Button>
                ))}
              </div>
            </div>
          </div>
        )}
      </div>

      {/* Alerts List */}
      <div className="divide-y divide-theme">
        {filteredAlerts.length === 0 ? (
          <div className="px-6 py-12 text-center">
            <CheckCircle className="w-12 h-12 text-theme-success mx-auto mb-4" />
            <h4 className="text-lg font-medium text-theme-primary mb-2">No Active Alerts</h4>
            <p className="text-theme-secondary">All systems are operating normally</p>
          </div>
        ) : (
          filteredAlerts.map(alert => {
            const config = getSeverityConfig(alert.severity);
            const Icon = config.icon;
            const isDismissing = dismissingAlerts.has(alert.id);

            return (
              <div key={alert.id} className={`p-6 ${config.color}`}>
                <div className="flex items-start justify-between">
                  <div className="flex items-start gap-4">
                    <div className={`p-2 bg-theme-surface bg-opacity-20 rounded-lg ${config.iconColor}`}>
                      <Icon className="w-5 h-5" />
                    </div>
                    
                    <div className="flex-1">
                      <div className="flex items-center gap-2 mb-2">
                        <h4 className={`font-semibold ${config.textColor}`}>
                          {getTypeDisplayName(alert.type)} Alert
                        </h4>
                        <span className={`px-2 py-1 rounded-full text-xs font-medium ${config.textColor} bg-theme-surface bg-opacity-20`}>
                          {alert.severity.toUpperCase()}
                        </span>
                      </div>
                      
                      <p className={`${config.textColor} mb-2`}>{alert.message}</p>
                      
                      <div className={`text-sm ${config.textColor} opacity-75 space-y-1`}>
                        <p>Current Value: <span className="font-medium">{alert.value}</span></p>
                        <p>Threshold: <span className="font-medium">{alert.threshold}</span></p>
                        <p>Triggered: <span className="font-medium">{new Date(alert.triggered_at).toLocaleString()}</span></p>
                      </div>
                    </div>
                  </div>
                  
                  <Button variant="outline" onClick={() => dismissAlert(alert.id)}
                    disabled={isDismissing}
                    className={`p-2 rounded-lg transition-colors ${config.textColor} hover:bg-theme-surface hover:bg-opacity-20 disabled:opacity-50 disabled:cursor-not-allowed`}
                    title="Dismiss alert"
                  >
                    {isDismissing ? (
                      <Clock className="w-4 h-4 animate-spin" />
                    ) : (
                      <Trash2 className="w-4 h-4" />
                    )}
                  </Button>
                </div>
              </div>
            );
          })
        )}
      </div>

      {/* Auto-refresh indicator */}
      {autoRefresh && alerts.length > 0 && (
        <div className="px-6 py-3 border-t border-theme bg-theme-background">
          <p className="text-xs text-theme-secondary text-center">
            Auto-refreshing every {Math.floor(refreshInterval / 1000)} seconds
          </p>
        </div>
      )}
    </div>
  );
};


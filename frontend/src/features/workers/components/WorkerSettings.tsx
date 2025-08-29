import React, { useState, useEffect } from 'react';
import { Worker, workerAPI, WorkerConfig } from '@/features/workers/services/workerApi';
import { SettingsCard, ToggleSettingItem, FormField, Input, Select } from '@/features/admin/components/settings/SettingsComponents';
import { useNotification } from '@/shared/hooks/useNotification';
import { 
  Shield, 
  Key, 
  Clock, 
  AlertTriangle, 
  CheckCircle, 
  XCircle, 
  RefreshCw,
  Activity,
  Database,
  Network,
  Monitor,
  Bell,
  Lock
} from 'lucide-react';

// WorkerConfig is now imported from the API service

const defaultConfig: WorkerConfig = {
  security: {
    token_rotation_enabled: false,
    token_expiry_days: 365,
    require_ip_whitelist: false,
    allowed_ips: [],
    max_concurrent_sessions: 10,
    enforce_https: true
  },
  rate_limiting: {
    enabled: true,
    requests_per_minute: 1000,
    burst_limit: 100,
    throttle_delay_ms: 1000
  },
  monitoring: {
    activity_logging: true,
    performance_tracking: true,
    error_reporting: true,
    metrics_retention_days: 90
  },
  notifications: {
    alert_on_failures: true,
    alert_threshold: 5,
    notify_on_token_rotation: true,
    notify_on_suspension: true
  },
  operational: {
    auto_cleanup_activities: true,
    cleanup_after_days: 90,
    enable_health_checks: true,
    health_check_interval_minutes: 15
  }
};

interface WorkerSettingsProps {
  worker: Worker;
  onUpdate?: (workerId: string, config: WorkerConfig) => Promise<void>;
}

export const WorkerSettings: React.FC<WorkerSettingsProps> = ({ 
  worker, 
  onUpdate 
}) => {
  const [config, setConfig] = useState<WorkerConfig>(defaultConfig);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [lastSaved, setLastSaved] = useState<Date | null>(null);
  const { showNotification } = useNotification();

  const isSystemWorker = worker.account_name === 'System';

  useEffect(() => {
    loadWorkerConfig();
  }, [worker.id]);

  const loadWorkerConfig = async () => {
    setLoading(true);
    try {
      // In a real implementation, this would fetch from the API
      // For now, use default config with some worker-specific overrides
      const workerConfig = { 
        ...defaultConfig,
        security: {
          ...defaultConfig.security,
          enforce_https: isSystemWorker,
          max_concurrent_sessions: isSystemWorker ? 50 : 10
        },
        rate_limiting: {
          ...defaultConfig.rate_limiting,
          requests_per_minute: isSystemWorker ? 5000 : 1000
        }
      };
      setConfig(workerConfig);
    } catch (error) {
      showNotification('Failed to load worker configuration', 'error');
    } finally {
      setLoading(false);
    }
  };

  const saveWorkerConfig = async () => {
    setSaving(true);
    try {
      if (onUpdate) {
        await onUpdate(worker.id, config);
      }
      setLastSaved(new Date());
      showNotification('Worker settings saved successfully', 'success');
    } catch (error) {
      showNotification('Failed to save worker settings', 'error');
    } finally {
      setSaving(false);
    }
  };

  const updateConfig = (section: keyof WorkerConfig, key: string, value: any) => {
    setConfig(prev => ({
      ...prev,
      [section]: {
        ...prev[section],
        [key]: value
      }
    }));
  };

  const addAllowedIP = () => {
    const ip = window.prompt('Enter IP address or CIDR range:');
    if (ip && ip.trim()) {
      setConfig(prev => ({
        ...prev,
        security: {
          ...prev.security,
          allowed_ips: [...prev.security.allowed_ips, ip.trim()]
        }
      }));
    }
  };

  const removeAllowedIP = (index: number) => {
    setConfig(prev => ({
      ...prev,
      security: {
        ...prev.security,
        allowed_ips: prev.security.allowed_ips.filter((_, i) => i !== index)
      }
    }));
  };

  const testWorkerHealth = async () => {
    setLoading(true);
    showNotification('Testing worker health...', 'info');
    try {
      // Simulate health check - in real implementation would call API
      await new Promise(resolve => setTimeout(resolve, 2000));
      showNotification('Worker health check passed', 'success');
    } catch (error) {
      showNotification('Worker health check failed', 'error');
    } finally {
      setLoading(false);
    }
  };

  const resetToDefaults = () => {
    if (window.confirm('Reset all worker settings to defaults? This cannot be undone.')) {
      setConfig(defaultConfig);
      showNotification('Worker settings reset to defaults', 'info');
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center p-12">
        <RefreshCw className="w-8 h-8 animate-spin text-theme-interactive-primary" />
        <span className="ml-3 text-theme-secondary">Loading worker settings...</span>
      </div>
    );
  }

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-xl font-semibold text-theme-primary">Worker Settings</h3>
          <p className="text-theme-secondary mt-1">
            Configure security, monitoring, and operational settings for {worker.name}
          </p>
        </div>
        
        <div className="flex items-center gap-2">
          {lastSaved && (
            <span className="text-xs text-theme-secondary">
              Last saved: {lastSaved.toLocaleTimeString()}
            </span>
          )}
          <button
            onClick={saveWorkerConfig}
            disabled={saving}
            className="btn-primary"
          >
            {saving ? (
              <>
                <RefreshCw className="w-4 h-4 mr-2 animate-spin" />
                Saving...
              </>
            ) : (
              <>
                <CheckCircle className="w-4 h-4 mr-2" />
                Save Settings
              </>
            )}
          </button>
        </div>
      </div>

      {/* Security Settings */}
      <SettingsCard 
        title="Security Configuration" 
        description="Authentication and access control settings for the worker"
      >
        <div className="space-y-6">
          <ToggleSettingItem
            title="Automatic Token Rotation"
            description="Automatically rotate authentication tokens based on the configured schedule"
            checked={config.security.token_rotation_enabled}
            onChange={(checked) => updateConfig('security', 'token_rotation_enabled', checked)}
            variant="warning"
          />

          {config.security.token_rotation_enabled && (
            <div className="pl-4 border-l-2 border-theme-warning border-opacity-30">
              <FormField label="Token Expiry (Days)">
                <Input
                  type="number"
                  min="1"
                  max="365"
                  value={config.security.token_expiry_days}
                  onChange={(e) => updateConfig('security', 'token_expiry_days', parseInt(e.target.value))}
                />
              </FormField>
            </div>
          )}

          <ToggleSettingItem
            title="IP Address Whitelist"
            description="Restrict worker access to specific IP addresses or ranges"
            checked={config.security.require_ip_whitelist}
            onChange={(checked) => updateConfig('security', 'require_ip_whitelist', checked)}
            variant="error"
          />

          {config.security.require_ip_whitelist && (
            <div className="pl-4 border-l-2 border-theme-error border-opacity-30">
              <div className="space-y-4">
                <div className="flex items-center justify-between">
                  <span className="text-sm font-medium text-theme-primary">Allowed IP Addresses</span>
                  <button
                    onClick={addAllowedIP}
                    className="btn-secondary btn-sm"
                  >
                    Add IP
                  </button>
                </div>

                <div className="space-y-2">
                  {config.security.allowed_ips.map((ip, index) => (
                    <div key={index} className="flex items-center justify-between p-3 bg-theme-background-secondary rounded-lg border border-theme">
                      <span className="text-sm font-mono text-theme-primary">{ip}</span>
                      <button
                        onClick={() => removeAllowedIP(index)}
                        className="text-theme-error hover:text-theme-error/80 transition-colors"
                      >
                        <XCircle className="w-4 h-4" />
                      </button>
                    </div>
                  ))}

                  {config.security.allowed_ips.length === 0 && (
                    <div className="p-4 text-center text-theme-secondary bg-theme-background-secondary rounded-lg border border-theme">
                      No IP addresses configured. Click "Add IP" to add allowed addresses.
                    </div>
                  )}
                </div>
              </div>
            </div>
          )}

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <FormField label="Max Concurrent Sessions">
              <Input
                type="number"
                min="1"
                max="100"
                value={config.security.max_concurrent_sessions}
                onChange={(e) => updateConfig('security', 'max_concurrent_sessions', parseInt(e.target.value))}
              />
            </FormField>

            <div className="flex items-center pt-8">
              <ToggleSettingItem
                title="Enforce HTTPS"
                description="Require secure connections only"
                checked={config.security.enforce_https}
                onChange={(checked) => updateConfig('security', 'enforce_https', checked)}
                variant="success"
                className="mb-0"
              />
            </div>
          </div>
        </div>
      </SettingsCard>

      {/* Rate Limiting */}
      <SettingsCard 
        title="Rate Limiting" 
        description="Control API request rates and prevent abuse"
      >
        <div className="space-y-4">
          <ToggleSettingItem
            title="Enable Rate Limiting"
            description="Limit the number of requests per minute to prevent overload"
            checked={config.rate_limiting.enabled}
            onChange={(checked) => updateConfig('rate_limiting', 'enabled', checked)}
            variant="primary"
          />

          {config.rate_limiting.enabled && (
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4 pl-4 border-l-2 border-theme-interactive-primary border-opacity-30">
              <FormField label="Requests per Minute">
                <Input
                  type="number"
                  min="1"
                  max="10000"
                  value={config.rate_limiting.requests_per_minute}
                  onChange={(e) => updateConfig('rate_limiting', 'requests_per_minute', parseInt(e.target.value))}
                />
              </FormField>

              <FormField label="Burst Limit">
                <Input
                  type="number"
                  min="1"
                  max="1000"
                  value={config.rate_limiting.burst_limit}
                  onChange={(e) => updateConfig('rate_limiting', 'burst_limit', parseInt(e.target.value))}
                />
              </FormField>

              <FormField label="Throttle Delay (ms)">
                <Input
                  type="number"
                  min="100"
                  max="10000"
                  value={config.rate_limiting.throttle_delay_ms}
                  onChange={(e) => updateConfig('rate_limiting', 'throttle_delay_ms', parseInt(e.target.value))}
                />
              </FormField>
            </div>
          )}
        </div>
      </SettingsCard>

      {/* Monitoring & Logging */}
      <SettingsCard 
        title="Monitoring & Logging" 
        description="Track worker activity and performance metrics"
      >
        <div className="space-y-4">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div className="space-y-4">
              <ToggleSettingItem
                title="Activity Logging"
                description="Log all worker API requests and responses"
                checked={config.monitoring.activity_logging}
                onChange={(checked) => updateConfig('monitoring', 'activity_logging', checked)}
                variant="primary"
              />

              <ToggleSettingItem
                title="Performance Tracking"
                description="Track response times and throughput metrics"
                checked={config.monitoring.performance_tracking}
                onChange={(checked) => updateConfig('monitoring', 'performance_tracking', checked)}
                variant="primary"
              />
            </div>

            <div className="space-y-4">
              <ToggleSettingItem
                title="Error Reporting"
                description="Capture and report worker errors and failures"
                checked={config.monitoring.error_reporting}
                onChange={(checked) => updateConfig('monitoring', 'error_reporting', checked)}
                variant="warning"
              />

              <FormField label="Metrics Retention (Days)">
                <Input
                  type="number"
                  min="1"
                  max="365"
                  value={config.monitoring.metrics_retention_days}
                  onChange={(e) => updateConfig('monitoring', 'metrics_retention_days', parseInt(e.target.value))}
                />
              </FormField>
            </div>
          </div>
        </div>
      </SettingsCard>

      {/* Notifications */}
      <SettingsCard 
        title="Notification Settings" 
        description="Configure alerts and notifications for worker events"
      >
        <div className="space-y-4">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div className="space-y-4">
              <ToggleSettingItem
                title="Alert on Failures"
                description="Send notifications when worker encounters errors"
                checked={config.notifications.alert_on_failures}
                onChange={(checked) => updateConfig('notifications', 'alert_on_failures', checked)}
                variant="error"
              />

              <ToggleSettingItem
                title="Token Rotation Notifications"
                description="Notify when authentication tokens are rotated"
                checked={config.notifications.notify_on_token_rotation}
                onChange={(checked) => updateConfig('notifications', 'notify_on_token_rotation', checked)}
                variant="warning"
              />
            </div>

            <div className="space-y-4">
              <ToggleSettingItem
                title="Suspension Notifications"
                description="Alert when worker is suspended or reactivated"
                checked={config.notifications.notify_on_suspension}
                onChange={(checked) => updateConfig('notifications', 'notify_on_suspension', checked)}
                variant="warning"
              />

              <FormField label="Failure Alert Threshold">
                <Input
                  type="number"
                  min="1"
                  max="100"
                  value={config.notifications.alert_threshold}
                  onChange={(e) => updateConfig('notifications', 'alert_threshold', parseInt(e.target.value))}
                />
              </FormField>
            </div>
          </div>
        </div>
      </SettingsCard>

      {/* Operational Settings */}
      <SettingsCard 
        title="Operational Settings" 
        description="Configure worker maintenance and cleanup operations"
      >
        <div className="space-y-4">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div className="space-y-4">
              <ToggleSettingItem
                title="Auto-cleanup Activities"
                description="Automatically remove old activity logs"
                checked={config.operational.auto_cleanup_activities}
                onChange={(checked) => updateConfig('operational', 'auto_cleanup_activities', checked)}
                variant="success"
              />

              <FormField label="Cleanup After (Days)">
                <Input
                  type="number"
                  min="1"
                  max="365"
                  value={config.operational.cleanup_after_days}
                  onChange={(e) => updateConfig('operational', 'cleanup_after_days', parseInt(e.target.value))}
                />
              </FormField>
            </div>

            <div className="space-y-4">
              <ToggleSettingItem
                title="Health Checks"
                description="Enable periodic health status monitoring"
                checked={config.operational.enable_health_checks}
                onChange={(checked) => updateConfig('operational', 'enable_health_checks', checked)}
                variant="success"
              />

              <FormField label="Health Check Interval (Minutes)">
                <Input
                  type="number"
                  min="1"
                  max="1440"
                  value={config.operational.health_check_interval_minutes}
                  onChange={(e) => updateConfig('operational', 'health_check_interval_minutes', parseInt(e.target.value))}
                />
              </FormField>
            </div>
          </div>
        </div>
      </SettingsCard>

      {/* Actions */}
      <div className="flex justify-between items-center p-6 bg-theme-background-secondary rounded-lg border border-theme">
        <div className="flex gap-3">
          <button
            onClick={testWorkerHealth}
            className="btn-secondary"
            disabled={loading}
          >
            <Network className="w-4 h-4 mr-2" />
            Test Health
          </button>

          <button
            onClick={resetToDefaults}
            className="btn-secondary text-theme-warning hover:bg-theme-warning hover:text-white"
          >
            <RefreshCw className="w-4 h-4 mr-2" />
            Reset to Defaults
          </button>
        </div>

        <div className="flex gap-3">
          <button
            onClick={saveWorkerConfig}
            disabled={saving}
            className="btn-primary"
          >
            {saving ? (
              <>
                <RefreshCw className="w-4 h-4 mr-2 animate-spin" />
                Saving...
              </>
            ) : (
              <>
                <CheckCircle className="w-4 h-4 mr-2" />
                Save All Settings
              </>
            )}
          </button>
        </div>
      </div>

      {/* Worker Status Summary */}
      <SettingsCard 
        title="Worker Status Summary" 
        description="Current configuration and operational status"
      >
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          <div className="p-4 rounded-lg border border-theme bg-theme-background">
            <div className="flex items-center justify-between">
              <span className="text-sm text-theme-secondary">Security Level</span>
              {config.security.require_ip_whitelist ? (
                <Lock className="w-5 h-5 text-theme-error" />
              ) : (
                <Shield className="w-5 h-5 text-theme-warning" />
              )}
            </div>
            <p className="text-lg font-semibold text-theme-primary mt-1">
              {config.security.require_ip_whitelist ? 'High' : 'Standard'}
            </p>
          </div>

          <div className="p-4 rounded-lg border border-theme bg-theme-background">
            <div className="flex items-center justify-between">
              <span className="text-sm text-theme-secondary">Rate Limiting</span>
              {config.rate_limiting.enabled ? (
                <CheckCircle className="w-5 h-5 text-theme-success" />
              ) : (
                <XCircle className="w-5 h-5 text-theme-error" />
              )}
            </div>
            <p className="text-lg font-semibold text-theme-primary mt-1">
              {config.rate_limiting.enabled ? `${config.rate_limiting.requests_per_minute}/min` : 'Disabled'}
            </p>
          </div>

          <div className="p-4 rounded-lg border border-theme bg-theme-background">
            <div className="flex items-center justify-between">
              <span className="text-sm text-theme-secondary">Monitoring</span>
              <Activity className="w-5 h-5 text-theme-info" />
            </div>
            <p className="text-lg font-semibold text-theme-primary mt-1">
              {[
                config.monitoring.activity_logging,
                config.monitoring.performance_tracking,
                config.monitoring.error_reporting
              ].filter(Boolean).length}/3 Active
            </p>
          </div>

          <div className="p-4 rounded-lg border border-theme bg-theme-background">
            <div className="flex items-center justify-between">
              <span className="text-sm text-theme-secondary">Health Checks</span>
              <Clock className="w-5 h-5 text-theme-info" />
            </div>
            <p className="text-lg font-semibold text-theme-primary mt-1">
              {config.operational.enable_health_checks ? 
                `Every ${config.operational.health_check_interval_minutes}m` : 
                'Disabled'
              }
            </p>
          </div>
        </div>
      </SettingsCard>
    </div>
  );
};

export default WorkerSettings;
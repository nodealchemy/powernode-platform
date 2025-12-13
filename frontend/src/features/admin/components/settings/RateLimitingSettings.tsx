// Rate Limiting Configuration and Management
import React, { useState, useEffect, useCallback } from 'react';
import { 
  Shield, 
  Activity, 
  AlertTriangle, 
  CheckCircle,
  Zap,
  RefreshCw,
  Eye,
  EyeOff,
  Trash2,
  Ban,
  Play,
  Save
} from 'lucide-react';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { adminSettingsApi } from '@/features/admin/services/adminSettingsApi';
import { Button } from '@/shared/components/ui/Button';

interface RateLimitConfig {
  enabled: boolean;
  api_requests_per_minute: number;
  authenticated_requests_per_hour: number;
  login_attempts_per_hour: number;
  registration_attempts_per_hour: number;
  password_reset_attempts_per_hour: number;
  email_verification_attempts_per_hour: number;
  webhook_requests_per_minute: number;
  impersonation_attempts_per_hour: number;
}

interface RateLimitStats {
  enabled: boolean;
  current_violations: number;
  active_limits: number;
  configuration: RateLimitConfig;
  recent_violations: Array<{
    endpoint: string;
    identifier: string;
    count: number;
    limit: number;
    timestamp: string;
  }>;
}

// interface RateLimitEntry {
//   endpoint: string;
//   current: number;
//   limit: number;
//   remaining: number;
//   reset_in: number;
// }

export const RateLimitingSettings: React.FC = () => {
  const { showNotification } = useNotifications();
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [stats, setStats] = useState<RateLimitStats | null>(null);
  const [config, setConfig] = useState<RateLimitConfig>({
    enabled: true,
    api_requests_per_minute: 60,
    authenticated_requests_per_hour: 200,
    login_attempts_per_hour: 10,
    registration_attempts_per_hour: 5,
    password_reset_attempts_per_hour: 3,
    email_verification_attempts_per_hour: 10,
    webhook_requests_per_minute: 100,
    impersonation_attempts_per_hour: 5,
  });

  // Rate limit monitoring
  const [showAdvancedMonitoring, setShowAdvancedMonitoring] = useState(false);
  const [isRefreshingStats, setIsRefreshingStats] = useState(false);
  const [tempDisableMinutes, setTempDisableMinutes] = useState<number>(30);

  const loadOriginalStats = useCallback(async () => {
    try {
      const [statsResponse, violationsResponse, statusResponse] = await Promise.all([
        adminSettingsApi.getRateLimitingStatistics().catch(() => ({ current_violations: 0, active_limits: 0, configuration: config })),
        adminSettingsApi.getRateLimitingViolations().catch(() => ({ violations: [] })),
        adminSettingsApi.getRateLimitingStatus().catch(() => ({ effective_status: config.enabled ? 'enabled' : 'disabled' }))
      ]);
      
      const combinedStats: RateLimitStats = {
        enabled: statusResponse.effective_status === 'enabled',
        current_violations: statsResponse.current_violations || 0,
        active_limits: statsResponse.active_limits || 0,
        configuration: statsResponse.configuration || config,
        recent_violations: violationsResponse.violations || []
      };
      
      setStats(combinedStats);
    } catch (error: unknown) {
      // Fallback to basic stats if API not available
      const basicStats: RateLimitStats = {
        enabled: config.enabled,
        current_violations: 0,
        active_limits: 0,
        configuration: config,
        recent_violations: []
      };
      setStats(basicStats);
      
      // Only show error notification for unexpected errors
      const httpError = error as { response?: { status?: number } };
      if (httpError.response?.status !== 404) {
        showNotification('Rate limiting monitoring may be limited - some features unavailable', 'warning');
      }
    }
  }, [config, showNotification]);

  const loadRateLimitingStats = useCallback(async () => {
    try {
      setIsRefreshingStats(true);
      await loadOriginalStats();
    } catch (error: unknown) {
      showNotification('Failed to load rate limiting stats', 'error');
    } finally {
      setIsRefreshingStats(false);
    }
  }, [loadOriginalStats, showNotification]);

  const loadRateLimitingData = useCallback(async () => {
    try {
      setLoading(true);
      const settingsResponse = await adminSettingsApi.getOverview();
      const settingsSummary = settingsResponse.data?.settings_summary;
      if (settingsSummary?.rate_limiting) {
        const rateLimitingSettings = settingsSummary.rate_limiting;
        setConfig({
          enabled: rateLimitingSettings.enabled ?? true,
          api_requests_per_minute: rateLimitingSettings.api_requests_per_minute || 60,
          authenticated_requests_per_hour: rateLimitingSettings.authenticated_requests_per_hour || 200,
          login_attempts_per_hour: rateLimitingSettings.login_attempts_per_hour || 10,
          registration_attempts_per_hour: rateLimitingSettings.registration_attempts_per_hour || 5,
          password_reset_attempts_per_hour: rateLimitingSettings.password_reset_attempts_per_hour || 3,
          email_verification_attempts_per_hour: rateLimitingSettings.email_verification_attempts_per_hour || 10,
          webhook_requests_per_minute: rateLimitingSettings.webhook_requests_per_minute || 100,
          impersonation_attempts_per_hour: rateLimitingSettings.impersonation_attempts_per_hour || 5,
        });
      }
      
      // Load stats separately to avoid circular dependency
      loadOriginalStats();
    } catch (error: unknown) {
      showNotification('Failed to load rate limiting data', 'error');
    } finally {
      setLoading(false);
    }
  }, [showNotification, loadOriginalStats]);

  useEffect(() => {
    loadRateLimitingData();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []); // Only run once on mount

  useEffect(() => {
    // Auto-refresh stats every 30 seconds when advanced monitoring is open
    let interval: NodeJS.Timeout;
    if (showAdvancedMonitoring) {
      interval = setInterval(() => {
        loadRateLimitingStats();
      }, 30000);
    }
    
    return () => {
      if (interval) clearInterval(interval);
    };
  }, [showAdvancedMonitoring, loadRateLimitingStats]);


  const handleConfigChange = (key: keyof RateLimitConfig, value: number | boolean) => {
    setConfig(prev => ({
      ...prev,
      [key]: value
    }));
  };

  const saveSettings = async () => {
    try {
      setSaving(true);
      await adminSettingsApi.updateSettings({
        rate_limiting: config
      });
      
      showNotification('Rate limiting settings saved successfully', 'success');
      await loadOriginalStats();
    } catch (error: unknown) {
      showNotification('Failed to save rate limiting settings', 'error');
    } finally {
      setSaving(false);
    }
  };

  const refreshStats = async () => {
    await loadRateLimitingStats();
    showNotification('Rate limiting statistics refreshed', 'success');
  };

  const clearLimitsForUser = async (identifier: string) => {
    try {
      const response = await adminSettingsApi.clearUserRateLimits(identifier);
      showNotification(response.message || `Rate limits cleared for ${identifier}`, 'success');
      await loadOriginalStats();
    } catch (error: unknown) {
      const httpError = error as { response?: { status?: number; data?: { error?: string } } };
      if (httpError.response?.status === 404) {
        showNotification('Rate limiting management features are not yet fully available', 'info');
      } else {
        showNotification(httpError.response?.data?.error || 'Failed to clear rate limits', 'error');
      }
    }
  };

  const temporarilyDisableRateLimit = async () => {
    try {
      const response = await adminSettingsApi.disableRateLimitingTemporarily(tempDisableMinutes);
      showNotification(response.message || `Rate limiting disabled for ${tempDisableMinutes} minutes`, 'warning');
      await loadOriginalStats();
    } catch (error: unknown) {
      const httpError = error as { response?: { status?: number; data?: { error?: string } } };
      if (httpError.response?.status === 404) {
        showNotification('Emergency rate limiting controls are not yet fully available', 'info');
      } else {
        showNotification(httpError.response?.data?.error || 'Failed to disable rate limiting', 'error');
      }
    }
  };

  const reEnableRateLimit = async () => {
    try {
      const response = await adminSettingsApi.enableRateLimiting();
      showNotification(response.message || 'Rate limiting re-enabled', 'success');
      await loadOriginalStats();
    } catch (error: unknown) {
      const httpError = error as { response?: { status?: number; data?: { error?: string } } };
      if (httpError.response?.status === 404) {
        showNotification('Emergency rate limiting controls are not yet fully available', 'info');
      } else {
        showNotification(httpError.response?.data?.error || 'Failed to re-enable rate limiting', 'error');
      }
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <div className="animate-spin h-8 w-8 border-4 border-theme-primary border-t-transparent rounded-full"></div>
        <span className="ml-3 text-theme-secondary">Loading rate limiting settings...</span>
      </div>
    );
  }

  const limitCategories = [
    {
      title: 'Authentication Limits',
      description: 'Security-focused limits for user authentication',
      icon: Shield,
      settings: [
        { key: 'login_attempts_per_hour', label: 'Login Attempts per Hour', description: 'Maximum login attempts per user/IP per hour' },
        { key: 'registration_attempts_per_hour', label: 'Registration Attempts per Hour', description: 'New account registrations per IP per hour' },
        { key: 'password_reset_attempts_per_hour', label: 'Password Reset Attempts per Hour', description: 'Password reset requests per user per hour' },
        { key: 'email_verification_attempts_per_hour', label: 'Email Verification Attempts per Hour', description: 'Email verification requests per user per hour' },
        { key: 'impersonation_attempts_per_hour', label: 'Impersonation Attempts per Hour', description: 'Admin impersonation attempts per hour' }
      ]
    },
    {
      title: 'API Request Limits',
      description: 'General API usage limits',
      icon: Zap,
      settings: [
        { key: 'api_requests_per_minute', label: 'API Requests per Minute', description: 'Unauthenticated API requests per IP per minute' },
        { key: 'authenticated_requests_per_hour', label: 'Authenticated Requests per Hour', description: 'API requests for authenticated users per hour' },
        { key: 'webhook_requests_per_minute', label: 'Webhook Requests per Minute', description: 'Incoming webhook requests per minute' }
      ]
    }
  ];

  return (
    <div className="space-y-6">
      {/* Header with Global Controls */}
      <div className="bg-theme-surface rounded-lg border border-theme p-6">
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-theme-primary bg-opacity-10 rounded-lg">
              <Shield className="w-6 h-6 text-theme-primary" />
            </div>
            <div>
              <h2 className="text-xl font-semibold text-theme-primary">Rate Limiting</h2>
              <p className="text-theme-secondary">Configure API rate limits and monitor usage patterns</p>
            </div>
          </div>
          <div className="flex items-center gap-3">
            <Button
              onClick={refreshStats}
              disabled={isRefreshingStats}
              variant="secondary"
              size="sm"
            >
              <RefreshCw className={`w-4 h-4 mr-2 ${isRefreshingStats ? 'animate-spin' : ''}`} />
              Refresh Stats
            </Button>
            <Button
              onClick={() => setShowAdvancedMonitoring(!showAdvancedMonitoring)}
              variant="secondary"
              size="sm"
            >
              {showAdvancedMonitoring ? <EyeOff className="w-4 h-4 mr-2" /> : <Eye className="w-4 h-4 mr-2" />}
              {showAdvancedMonitoring ? 'Hide' : 'Show'} Monitoring
            </Button>
          </div>
        </div>

        {/* Global Enable/Disable */}
        <div className="flex items-center justify-between p-4 bg-theme-surface-subtle rounded-lg mb-6">
          <div className="flex items-center gap-3">
            <div className={`w-3 h-3 rounded-full ${config.enabled ? 'bg-theme-success' : 'bg-theme-danger'}`}></div>
            <div>
              <h3 className="font-medium text-theme-primary">Rate Limiting Status</h3>
              <p className="text-sm text-theme-secondary">
                {config.enabled ? 'Protection active across all endpoints' : 'Rate limiting is disabled'}
              </p>
            </div>
          </div>
          <label className="flex items-center">
            <input
              type="checkbox"
              checked={config.enabled}
              onChange={(e) => handleConfigChange('enabled', e.target.checked)}
              className="sr-only"
            />
            <div className={`relative inline-block w-10 h-6 transition duration-200 ease-in-out rounded-full ${
              config.enabled ? 'bg-theme-success' : 'bg-theme-muted/50'
            }`}>
              <div className={`absolute left-0 top-0 bg-white w-6 h-6 rounded-full shadow transition-transform duration-200 ease-in-out ${
                config.enabled ? 'transform translate-x-4' : ''
              }`}></div>
            </div>
          </label>
        </div>

        {/* Quick Stats */}
        {stats && (
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
            <div className="p-4 bg-theme-surface-subtle rounded-lg">
              <div className="flex items-center gap-3">
                <Activity className="w-5 h-5 text-theme-info" />
                <div>
                  <p className="text-sm text-theme-secondary">Active Limits</p>
                  <p className="text-xl font-semibold text-theme-primary">{stats.active_limits}</p>
                </div>
              </div>
            </div>
            <div className="p-4 bg-theme-surface-subtle rounded-lg">
              <div className="flex items-center gap-3">
                <AlertTriangle className={`w-5 h-5 ${stats.current_violations > 0 ? 'text-theme-danger' : 'text-theme-success'}`} />
                <div>
                  <p className="text-sm text-theme-secondary">Current Violations</p>
                  <p className={`text-xl font-semibold ${stats.current_violations > 0 ? 'text-theme-danger' : 'text-theme-success'}`}>
                    {stats.current_violations}
                  </p>
                </div>
              </div>
            </div>
            <div className="p-4 bg-theme-surface-subtle rounded-lg">
              <div className="flex items-center gap-3">
                <CheckCircle className="w-5 h-5 text-theme-success" />
                <div>
                  <p className="text-sm text-theme-secondary">System Status</p>
                  <p className="text-lg font-medium text-theme-success">
                    {config.enabled ? 'Protected' : 'Unprotected'}
                  </p>
                </div>
              </div>
            </div>
          </div>
        )}
      </div>

      {/* Advanced Monitoring Panel */}
      {showAdvancedMonitoring && stats && (
        <div className="bg-theme-surface rounded-lg border border-theme p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4">Live Monitoring & Emergency Controls</h3>
          
          {/* Emergency Controls */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">
            <div className="p-4 border border-theme bg-theme-warning-background rounded-lg">
              <h4 className="font-medium text-theme-warning mb-2">Temporarily Disable</h4>
              <p className="text-sm text-theme-warning-dark mb-3">Disable rate limiting for maintenance or emergency</p>
              <div className="flex items-center gap-3">
                <input
                  type="number"
                  value={tempDisableMinutes}
                  onChange={(e) => setTempDisableMinutes(parseInt(e.target.value) || 30)}
                  min="1"
                  max="480"
                  className="w-20 px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:ring-2 focus:ring-theme-warning focus:border-theme-warning text-sm font-medium"
                />
                <span className="text-sm text-theme-warning-dark font-medium">minutes</span>
                <Button
                  onClick={temporarilyDisableRateLimit}
                  variant="warning"
                  size="sm"
                  className="ml-auto"
                >
                  <Ban className="w-4 h-4 mr-1" />
                  Disable
                </Button>
              </div>
            </div>
            
            <div className="p-4 border border-theme bg-theme-success-background rounded-lg">
              <h4 className="font-medium text-theme-success mb-2">Re-enable Protection</h4>
              <p className="text-sm text-theme-success-dark mb-3">Immediately restore rate limiting</p>
              <Button
                onClick={reEnableRateLimit}
                variant="success"
                size="sm"
              >
                <Play className="w-4 h-4 mr-1" />
                Re-enable
              </Button>
            </div>
          </div>

          {/* Recent Violations */}
          {stats.recent_violations.length > 0 && (
            <div className="mb-6">
              <h4 className="font-medium text-theme-primary mb-3">Recent Violations</h4>
              <div className="space-y-3">
                {stats.recent_violations.map((violation, index) => (
                  <div key={index} className="flex items-center justify-between p-4 bg-theme-error-background border border-theme-error rounded-lg">
                    <div className="flex items-center gap-3">
                      <AlertTriangle className="w-5 h-5 text-theme-error" />
                      <div>
                        <p className="font-medium text-theme-error">{violation.endpoint}</p>
                        <p className="text-sm text-theme-error-dark">{violation.identifier}</p>
                      </div>
                    </div>
                    <div className="text-right">
                      <p className="font-medium text-theme-error">{violation.count}/{violation.limit}</p>
                      <p className="text-sm text-theme-error-dark">{new Date(violation.timestamp).toLocaleTimeString()}</p>
                    </div>
                    <Button
                      onClick={() => clearLimitsForUser(violation.identifier)}
                      variant="danger"
                      size="xs"
                      iconOnly
                      className="ml-4"
                    >
                      <Trash2 className="w-3 h-3" />
                    </Button>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      )}

      {/* Rate Limit Configuration */}
      <div className="space-y-6">
        {limitCategories.map((category) => (
          <div key={category.title} className="bg-theme-surface rounded-lg border border-theme p-6">
            <div className="flex items-center gap-3 mb-4">
              <div className="p-2 bg-theme-primary bg-opacity-10 rounded-lg">
                <category.icon className="w-5 h-5 text-theme-primary" />
              </div>
              <div>
                <h3 className="text-lg font-semibold text-theme-primary">{category.title}</h3>
                <p className="text-sm text-theme-secondary">{category.description}</p>
              </div>
            </div>
            
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
              {category.settings.map((setting) => (
                <div key={setting.key} className="space-y-2">
                  <label className="block text-sm font-medium text-theme-primary">
                    {setting.label}
                  </label>
                  <input
                    type="number"
                    min="1"
                    max="10000"
                    value={config[setting.key as keyof RateLimitConfig] as number}
                    onChange={(e) => handleConfigChange(setting.key as keyof RateLimitConfig, parseInt(e.target.value) || 1)}
                    className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:ring-2 focus:ring-theme-primary focus:border-theme-primary"
                  />
                  <p className="text-xs text-theme-secondary">{setting.description}</p>
                </div>
              ))}
            </div>
          </div>
        ))}
      </div>

      {/* Save Button */}
      <div className="flex justify-end">
        <Button
          onClick={saveSettings}
          disabled={saving}
          loading={saving}
          variant="primary"
          size="lg"
          className="px-6 py-3"
        >
          <Save className="w-5 h-5 mr-2" />
          Save Rate Limiting Settings
        </Button>
      </div>
    </div>
  );
};


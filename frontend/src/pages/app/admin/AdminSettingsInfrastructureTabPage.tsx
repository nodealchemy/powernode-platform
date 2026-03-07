import React, { useState, useEffect } from 'react';
import { adminSettingsApi, RedisConfig, RedisConnectionStatus } from '@/features/admin/services/adminSettingsApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { ToggleSwitch, SettingsCard } from '@/features/admin/components/settings/SettingsComponents';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { Database, Activity, Settings, Eye, EyeOff, ChevronDown, ChevronUp } from 'lucide-react';

export const AdminSettingsInfrastructureTabPage: React.FC = () => {
  const { showNotification } = useNotifications();
  const [config, setConfig] = useState<RedisConfig | null>(null);
  const [connection, setConnection] = useState<RedisConnectionStatus | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [testing, setTesting] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  const [showAdvanced, setShowAdvanced] = useState(false);

  useEffect(() => {
    loadConfig();
  }, []);

  const loadConfig = async () => {
    setLoading(true);
    const result = await adminSettingsApi.getInfrastructureConfig();
    if (result.success && result.data) {
      setConfig(result.data.redis);
      setConnection(result.data.connection);
    } else {
      showNotification(result.error || 'Failed to load infrastructure config', 'error');
    }
    setLoading(false);
  };

  const handleSave = async () => {
    if (!config) return;
    setSaving(true);
    const result = await adminSettingsApi.updateInfrastructureConfig(config);
    if (result.success) {
      if (result.data?.redis) {
        setConfig(result.data.redis);
      }
      showNotification(result.data?.message || 'Infrastructure config updated', 'success');
    } else {
      showNotification(result.error || 'Failed to update config', 'error');
    }
    setSaving(false);
  };

  const handleTestConnection = async () => {
    setTesting(true);
    const result = await adminSettingsApi.testRedisConnection(config || undefined);
    if (result.success && result.data) {
      setConnection(result.data);
      if (result.data.status === 'connected') {
        showNotification('Redis connection successful', 'success');
      } else {
        showNotification(result.data.error || 'Redis connection failed', 'error');
      }
    } else {
      showNotification(result.error || 'Connection test failed', 'error');
    }
    setTesting(false);
  };

  const updateConfig = (updates: Partial<RedisConfig>) => {
    if (!config) return;
    setConfig({ ...config, ...updates });
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <LoadingSpinner size="lg" message="Loading infrastructure config..." />
      </div>
    );
  }

  if (!config) {
    return (
      <div className="bg-theme-surface rounded-lg border border-theme p-6">
        <div className="text-center">
          <div className="text-6xl mb-4">🖥️</div>
          <h3 className="text-lg font-medium text-theme-primary mb-2">Error Loading Infrastructure Config</h3>
          <p className="text-theme-secondary mb-4">Could not load configuration from the server.</p>
          <button onClick={loadConfig} className="btn-theme btn-theme-primary">
            Try Again
          </button>
        </div>
      </div>
    );
  }

  const resolvedUrl = config.url || `redis://${config.host}:${config.port}/${config.database}`;

  return (
    <div className="space-y-6">
      {/* Connection Status */}
      <SettingsCard
        title="Connection Status"
        description="Current Redis connection health and metrics"
        icon="📡"
      >
        <div className="space-y-4">
          <div className="flex items-center gap-3">
            <span className={`inline-block w-3 h-3 rounded-full ${
              connection?.status === 'connected' ? 'bg-theme-success' : 'bg-theme-error'
            }`} />
            <span className="text-lg font-medium text-theme-primary">
              {connection?.status === 'connected' ? 'Connected' : 'Disconnected'}
            </span>
            {connection?.error && (
              <span className="text-sm text-theme-error">{connection.error}</span>
            )}
          </div>

          {connection?.status === 'connected' && (
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <div className="p-4 bg-theme-background rounded-lg border border-theme text-center">
                <Database className="w-6 h-6 text-theme-interactive-primary mx-auto mb-2" />
                <div className="text-sm font-medium text-theme-primary">{connection.version || 'N/A'}</div>
                <div className="text-xs text-theme-secondary">Redis Version</div>
              </div>
              <div className="p-4 bg-theme-background rounded-lg border border-theme text-center">
                <Activity className="w-6 h-6 text-theme-interactive-primary mx-auto mb-2" />
                <div className="text-sm font-medium text-theme-primary">{connection.memory_used || 'N/A'}</div>
                <div className="text-xs text-theme-secondary">Memory Usage</div>
              </div>
              <div className="p-4 bg-theme-background rounded-lg border border-theme text-center">
                <Activity className="w-6 h-6 text-theme-interactive-primary mx-auto mb-2" />
                <div className="text-sm font-medium text-theme-primary">
                  {connection.latency_ms != null ? `${connection.latency_ms}ms` : 'N/A'}
                </div>
                <div className="text-xs text-theme-secondary">Response Time</div>
              </div>
              <div className="p-4 bg-theme-background rounded-lg border border-theme text-center">
                <Settings className="w-6 h-6 text-theme-interactive-primary mx-auto mb-2" />
                <div className="text-sm font-medium text-theme-primary">
                  {connection.connected_clients ?? 'N/A'}
                </div>
                <div className="text-xs text-theme-secondary">Connected Clients</div>
              </div>
            </div>
          )}

          <div>
            <button
              onClick={handleTestConnection}
              disabled={testing}
              className="btn-theme btn-theme-secondary"
            >
              {testing ? 'Testing...' : 'Test Connection'}
            </button>
          </div>
        </div>
      </SettingsCard>

      {/* Redis Connection */}
      <SettingsCard
        title="Redis Connection"
        description="Configure the Redis server connection"
        icon="🗄️"
      >
        <div className="space-y-6">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">Host</label>
              <input
                type="text"
                value={config.host}
                onChange={(e) => updateConfig({ host: e.target.value })}
                disabled={saving}
                className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">Port</label>
              <input
                type="number"
                min={1}
                max={65535}
                value={config.port}
                onChange={(e) => updateConfig({ port: parseInt(e.target.value) || 6379 })}
                disabled={saving}
                className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">Database</label>
              <input
                type="number"
                min={0}
                max={15}
                value={config.database}
                onChange={(e) => updateConfig({ database: parseInt(e.target.value) || 0 })}
                disabled={saving}
                className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">Password</label>
              <div className="relative">
                <input
                  type={showPassword ? 'text' : 'password'}
                  value={config.password || ''}
                  onChange={(e) => updateConfig({ password: e.target.value || null })}
                  disabled={saving}
                  placeholder="Optional"
                  className="w-full px-3 py-2 pr-10 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute right-2 top-1/2 -translate-y-1/2 text-theme-secondary hover:text-theme-primary"
                >
                  {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                </button>
              </div>
            </div>
          </div>

          <div className="flex items-center justify-between">
            <div>
              <p className="font-medium text-theme-primary">SSL / TLS</p>
              <p className="text-sm text-theme-secondary">Use encrypted connection to Redis</p>
            </div>
            <ToggleSwitch
              checked={config.ssl}
              onChange={(checked) => updateConfig({ ssl: checked })}
              disabled={saving}
              variant="primary"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">URL Override</label>
            <input
              type="text"
              value={config.url || ''}
              onChange={(e) => updateConfig({ url: e.target.value || null })}
              disabled={saving}
              placeholder="redis://user:pass@host:port/db"
              className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
            />
            <p className="text-xs text-theme-secondary mt-1">If set, overrides host/port/database settings above</p>
          </div>

          <div className="p-3 bg-theme-background rounded-lg border border-theme">
            <p className="text-xs text-theme-secondary mb-1">Resolved URL</p>
            <code className="text-sm text-theme-primary break-all">{resolvedUrl}</code>
          </div>

          <div className="flex gap-3">
            <button
              onClick={handleSave}
              disabled={saving}
              className="btn-theme btn-theme-primary"
            >
              {saving ? 'Saving...' : 'Save Connection'}
            </button>
            <button
              onClick={handleTestConnection}
              disabled={testing}
              className="btn-theme btn-theme-secondary"
            >
              {testing ? 'Testing...' : 'Test Before Save'}
            </button>
          </div>
        </div>
      </SettingsCard>

      {/* Advanced Settings */}
      <SettingsCard
        title="Advanced Settings"
        description="Timeout and pool configuration"
        icon="⚙️"
      >
        <div className="space-y-4">
          <button
            type="button"
            onClick={() => setShowAdvanced(!showAdvanced)}
            className="flex items-center gap-2 text-sm font-medium text-theme-interactive-primary hover:text-theme-interactive-primary-hover"
          >
            {showAdvanced ? <ChevronUp className="w-4 h-4" /> : <ChevronDown className="w-4 h-4" />}
            {showAdvanced ? 'Hide advanced settings' : 'Show advanced settings'}
          </button>

          {showAdvanced && (
            <div className="space-y-6 pt-2">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-2">
                    Connect Timeout (seconds)
                  </label>
                  <input
                    type="number"
                    min={1}
                    max={30}
                    value={config.connect_timeout}
                    onChange={(e) => updateConfig({ connect_timeout: parseInt(e.target.value) || 5 })}
                    disabled={saving}
                    className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-2">
                    Read Timeout (seconds)
                  </label>
                  <input
                    type="number"
                    min={1}
                    max={30}
                    value={config.read_timeout}
                    onChange={(e) => updateConfig({ read_timeout: parseInt(e.target.value) || 5 })}
                    disabled={saving}
                    className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-2">
                    Write Timeout (seconds)
                  </label>
                  <input
                    type="number"
                    min={1}
                    max={30}
                    value={config.write_timeout}
                    onChange={(e) => updateConfig({ write_timeout: parseInt(e.target.value) || 5 })}
                    disabled={saving}
                    className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-2">
                    Pool Size
                  </label>
                  <input
                    type="number"
                    min={1}
                    max={100}
                    value={config.pool_size}
                    onChange={(e) => updateConfig({ pool_size: parseInt(e.target.value) || 5 })}
                    disabled={saving}
                    className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                  />
                </div>
              </div>

              <div>
                <button
                  onClick={handleSave}
                  disabled={saving}
                  className="btn-theme btn-theme-primary"
                >
                  {saving ? 'Saving...' : 'Save Advanced Settings'}
                </button>
              </div>
            </div>
          )}
        </div>
      </SettingsCard>
    </div>
  );
};

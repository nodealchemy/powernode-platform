import React, { useState, useEffect } from 'react';
import { useNotification } from '@/shared/hooks/useNotification';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import proxySettingsApi, { 
  ProxyUrlConfig, 
  ProxyDetectionResult, 
  ProxyValidationResult 
} from '@/shared/services/proxySettingsApi';
import ProxyHostList from './ProxyHostList';
import ProxyDetectionStatus from './ProxyDetectionStatus';
import ProxyTestConnection from './ProxyTestConnection';
import APIUrlPreview from './APIUrlPreview';

const ProxySettingsTab: React.FC = () => {
  const { showNotification } = useNotification();
  const showSuccess = (msg: string) => showNotification(msg, 'success');
  const showError = (msg: string) => showNotification(msg, 'error');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [config, setConfig] = useState<ProxyUrlConfig | null>(null);
  const [detection, setDetection] = useState<ProxyDetectionResult | null>(null);
  const [activeTab, setActiveTab] = useState<'config' | 'detection' | 'testing'>('config');

  useEffect(() => {
    loadConfig();
    loadDetection();
  }, []);

  const loadConfig = async () => {
    try {
      const data = await proxySettingsApi.getUrlConfig();
      setConfig(data);
    } catch (error) {
      showError('Failed to load proxy configuration');
    } finally {
      setLoading(false);
    }
  };

  const loadDetection = async () => {
    try {
      const data = await proxySettingsApi.getCurrentDetection();
      setDetection(data);
    } catch (error) {
      console.error('Failed to load detection status:', error);
    }
  };

  const handleSaveConfig = async () => {
    if (!config) return;

    setSaving(true);
    try {
      const updatedConfig = await proxySettingsApi.updateUrlConfig(config);
      setConfig(updatedConfig);
      showSuccess('Proxy configuration saved successfully');
      
      // Reload detection after config change
      await loadDetection();
    } catch (error) {
      showError('Failed to save configuration');
    } finally {
      setSaving(false);
    }
  };

  const handleEnableToggle = () => {
    if (!config) return;
    setConfig({ ...config, enabled: !config.enabled });
  };

  const handleSecurityToggle = (field: keyof ProxyUrlConfig['security']) => {
    if (!config) return;
    setConfig({
      ...config,
      security: {
        ...config.security,
        [field]: !config.security[field]
      }
    });
  };

  const handleExport = async () => {
    try {
      await proxySettingsApi.downloadConfigAsFile();
      showSuccess('Configuration exported successfully');
    } catch (error) {
      showError('Failed to export configuration');
    }
  };

  const handleImport = async (file: File) => {
    try {
      const importedConfig = await proxySettingsApi.parseImportFile(file);
      const updatedConfig = await proxySettingsApi.importConfig(importedConfig);
      setConfig(updatedConfig);
      showSuccess('Configuration imported successfully');
      await loadDetection();
    } catch (error) {
      showError('Failed to import configuration');
    }
  };

  if (loading) {
    return (
      <div className="flex justify-center items-center h-64">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-theme-primary"></div>
      </div>
    );
  }

  if (!config) {
    return (
      <div className="text-center py-8 text-theme-secondary">
        Failed to load configuration
      </div>
    );
  }

  return (
    <PageContainer
      title="Reverse Proxy URL Configuration"
      description="Configure reverse proxy URL handling, trusted hosts, and multi-tenancy settings"
      actions={[
        {
          id: 'save-changes',
          label: 'Save Changes',
          onClick: handleSaveConfig,
          variant: 'primary',
          disabled: saving,
        },
        {
          id: 'export-config',
          label: 'Export',
          onClick: handleExport,
          variant: 'secondary',
        },
        {
          id: 'import-config',
          label: 'Import',
          onClick: () => document.getElementById('import-file')?.click(),
          variant: 'secondary',
        },
      ]}
    >
      {/* Hidden file input for import */}
      <input
        id="import-file"
        type="file"
        accept=".json"
        className="hidden"
        onChange={(e) => {
          const file = e.target.files?.[0];
          if (file) handleImport(file);
          e.target.value = '';
        }}
      />

      {/* Tab Navigation */}
      <div className="border-b border-theme mb-6">
        <nav className="flex space-x-8">
          <button
            onClick={() => setActiveTab('config')}
            className={`py-2 px-1 border-b-2 transition-colors ${
              activeTab === 'config'
                ? 'border-theme-primary text-theme-primary'
                : 'border-transparent text-theme-secondary hover:text-theme-primary'
            }`}
          >
            Configuration
          </button>
          <button
            onClick={() => setActiveTab('detection')}
            className={`py-2 px-1 border-b-2 transition-colors ${
              activeTab === 'detection'
                ? 'border-theme-primary text-theme-primary'
                : 'border-transparent text-theme-secondary hover:text-theme-primary'
            }`}
          >
            Detection Status
          </button>
          <button
            onClick={() => setActiveTab('testing')}
            className={`py-2 px-1 border-b-2 transition-colors ${
              activeTab === 'testing'
                ? 'border-theme-primary text-theme-primary'
                : 'border-transparent text-theme-secondary hover:text-theme-primary'
            }`}
          >
            Testing
          </button>
        </nav>
      </div>

      {/* Tab Content */}
      {activeTab === 'config' && (
        <div className="space-y-6">
          {/* Enable/Disable Toggle */}
          <div className="bg-theme-surface rounded-lg p-6">
            <div className="flex items-center justify-between">
              <div>
                <h3 className="text-lg font-medium text-theme-primary">
                  Proxy URL Configuration
                </h3>
                <p className="mt-1 text-sm text-theme-secondary">
                  Enable reverse proxy URL detection and handling
                </p>
              </div>
              <button
                onClick={handleEnableToggle}
                className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
                  config.enabled ? 'bg-theme-success' : 'bg-theme-muted'
                }`}
              >
                <span
                  className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                    config.enabled ? 'translate-x-6' : 'translate-x-1'
                  }`}
                />
              </button>
            </div>
          </div>

          {/* Default Settings */}
          <div className="bg-theme-surface rounded-lg p-6">
            <h3 className="text-lg font-medium text-theme-primary mb-4">
              Default Settings
            </h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-theme-secondary mb-1">
                  Default Protocol
                </label>
                <select
                  value={config.default_protocol}
                  onChange={(e) => setConfig({ ...config, default_protocol: e.target.value })}
                  className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-primary focus:border-theme-primary"
                >
                  <option value="http">HTTP</option>
                  <option value="https">HTTPS</option>
                  <option value="ws">WS</option>
                  <option value="wss">WSS</option>
                </select>
              </div>
              <div>
                <label className="block text-sm font-medium text-theme-secondary mb-1">
                  Default Host
                </label>
                <input
                  type="text"
                  value={config.default_host || ''}
                  onChange={(e) => setConfig({ ...config, default_host: e.target.value || null })}
                  placeholder="example.com"
                  className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-primary focus:border-theme-primary"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-theme-secondary mb-1">
                  Default Port
                </label>
                <input
                  type="number"
                  value={config.default_port || ''}
                  onChange={(e) => setConfig({ ...config, default_port: e.target.value ? parseInt(e.target.value) : null })}
                  placeholder="443"
                  className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-primary focus:border-theme-primary"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-theme-secondary mb-1">
                  Base Path
                </label>
                <input
                  type="text"
                  value={config.base_path}
                  onChange={(e) => setConfig({ ...config, base_path: e.target.value })}
                  placeholder="/api"
                  className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-primary focus:border-theme-primary"
                />
              </div>
            </div>
          </div>

          {/* Security Settings */}
          <div className="bg-theme-surface rounded-lg p-6">
            <h3 className="text-lg font-medium text-theme-primary mb-4">
              Security Settings
            </h3>
            <div className="space-y-3">
              <label className="flex items-center">
                <input
                  type="checkbox"
                  checked={config.security.enabled}
                  onChange={() => handleSecurityToggle('enabled')}
                  className="h-4 w-4 text-theme-primary border-theme-muted rounded focus:ring-2 focus:ring-theme-primary"
                />
                <span className="ml-2 text-theme-primary">Enable security validation</span>
              </label>
              <label className="flex items-center">
                <input
                  type="checkbox"
                  checked={config.security.strict_mode}
                  onChange={() => handleSecurityToggle('strict_mode')}
                  className="h-4 w-4 text-theme-primary border-theme-muted rounded focus:ring-2 focus:ring-theme-primary"
                />
                <span className="ml-2 text-theme-primary">
                  Strict mode (block untrusted hosts)
                </span>
              </label>
              <label className="flex items-center">
                <input
                  type="checkbox"
                  checked={config.security.validate_host_format}
                  onChange={() => handleSecurityToggle('validate_host_format')}
                  className="h-4 w-4 text-theme-primary border-theme-muted rounded focus:ring-2 focus:ring-theme-primary"
                />
                <span className="ml-2 text-theme-primary">
                  Validate RFC-compliant hostnames
                </span>
              </label>
              <label className="flex items-center">
                <input
                  type="checkbox"
                  checked={config.security.block_suspicious_patterns}
                  onChange={() => handleSecurityToggle('block_suspicious_patterns')}
                  className="h-4 w-4 text-theme-primary border-theme-muted rounded focus:ring-2 focus:ring-theme-primary"
                />
                <span className="ml-2 text-theme-primary">
                  Block suspicious patterns (XSS, injection)
                </span>
              </label>
            </div>
            {config.security.strict_mode && (
              <div className="mt-3 p-3 bg-theme-warning/10 border border-theme-warning rounded-md">
                <p className="text-sm text-theme-warning">
                  ⚠️ Strict mode enabled: Only trusted hosts will be allowed
                </p>
              </div>
            )}
          </div>

          {/* Trusted Hosts */}
          <ProxyHostList
            trustedHosts={config.trusted_hosts}
            onHostsChange={(hosts) => setConfig({ ...config, trusted_hosts: hosts })}
          />

          {/* Multi-Tenancy Settings */}
          <div className="bg-theme-surface rounded-lg p-6">
            <h3 className="text-lg font-medium text-theme-primary mb-4">
              Multi-Tenancy Settings
            </h3>
            <label className="flex items-center">
              <input
                type="checkbox"
                checked={config.multi_tenancy.enabled}
                onChange={() => setConfig({
                  ...config,
                  multi_tenancy: {
                    ...config.multi_tenancy,
                    enabled: !config.multi_tenancy.enabled
                  }
                })}
                className="h-4 w-4 text-theme-primary border-theme-muted rounded focus:ring-2 focus:ring-theme-primary"
              />
              <span className="ml-2 text-theme-primary">
                Enable multi-tenancy with wildcard domains
              </span>
            </label>
            {config.multi_tenancy.enabled && (
              <div className="mt-4 p-4 bg-theme-info/10 border border-theme-info rounded-md">
                <p className="text-sm text-theme-info">
                  ℹ️ Multi-tenancy allows multiple tenants to use the same application instance
                  with separate domains (e.g., *.customers.example.com)
                </p>
              </div>
            )}
          </div>
        </div>
      )}

      {activeTab === 'detection' && (
        <div className="space-y-6">
          <ProxyDetectionStatus detection={detection} onRefresh={loadDetection} />
          {detection?.generated_urls && (
            <APIUrlPreview urls={detection.generated_urls} />
          )}
        </div>
      )}

      {activeTab === 'testing' && (
        <ProxyTestConnection
          onTestComplete={(result) => {
            showSuccess('Proxy test completed successfully');
            loadDetection();
          }}
        />
      )}
    </PageContainer>
  );
};

export default ProxySettingsTab;
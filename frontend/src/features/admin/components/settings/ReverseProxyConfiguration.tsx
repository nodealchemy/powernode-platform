import React, { useState, useEffect } from 'react';
import { FlexBetween, FlexItemsCenter, FlexCol } from '@/shared/components/ui/FlexContainer';
import { GridCols2 } from '@/shared/components/ui/GridContainer';
import { Button } from '@/shared/components/ui/Button';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { Modal } from '@/shared/components/ui/Modal';
import { StatusIndicator } from '@/shared/components/ui/StatusIndicator';
import { TabContainer } from '@/shared/components/ui/TabContainer';
import { useNotification } from '@/shared/hooks/useNotification';
import { reverseProxyApi, ReverseProxyConfig, URLMapping, HealthStatus } from '../../services/reverseProxyApi';
import { 
  Settings, 
  Globe, 
  Server, 
  Shield, 
  Zap, 
  Activity, 
  Download, 
  TestTube, 
  Plus,
  Edit,
  Trash2,
  ToggleLeft,
  ToggleRight,
  RefreshCw,
  AlertTriangle,
  CheckCircle
} from 'lucide-react';

interface ReverseProxyConfigurationProps {
  className?: string;
}

type TabType = 'basic' | 'services' | 'mappings' | 'advanced';

const ReverseProxyConfiguration: React.FC<ReverseProxyConfigurationProps> = ({ className = '' }) => {
  const { showNotification } = useNotification();
  const [activeTab, setActiveTab] = useState<TabType>('basic');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [config, setConfig] = useState<ReverseProxyConfig | null>(null);
  const [healthStatus, setHealthStatus] = useState<HealthStatus | null>(null);
  const [hasChanges, setHasChanges] = useState(false);
  
  // Modal states
  const [showURLMappingModal, setShowURLMappingModal] = useState(false);
  const [showTestModal, setShowTestModal] = useState(false);
  const [showExportModal, setShowExportModal] = useState(false);
  const [editingMapping, setEditingMapping] = useState<URLMapping | null>(null);
  
  // Form states
  const [testResults, setTestResults] = useState<any>(null);
  const [exportConfig, setExportConfig] = useState<string>('');
  const [exportType, setExportType] = useState<'nginx' | 'apache' | 'traefik'>('nginx');

  useEffect(() => {
    loadConfiguration();
  }, []);

  const loadConfiguration = async () => {
    try {
      setLoading(true);
      const data = await reverseProxyApi.getConfiguration();
      setConfig(data.reverse_proxy_config);
      setHealthStatus(data.health_status);
    } catch (error) {
      console.error('Failed to load reverse proxy configuration:', error);
      showNotification('Failed to load reverse proxy configuration', 'error');
    } finally {
      setLoading(false);
    }
  };

  const refreshHealthStatus = async () => {
    try {
      const health = await reverseProxyApi.getHealthStatus();
      setHealthStatus(health);
    } catch (error) {
      console.error('Failed to refresh health status:', error);
      showNotification('Failed to refresh health status', 'error');
    }
  };

  const saveConfiguration = async () => {
    if (!config) return;

    try {
      setSaving(true);
      await reverseProxyApi.updateConfiguration('reverse_proxy_config', config);
      setHasChanges(false);
      showNotification('Reverse proxy configuration saved successfully', 'success');
    } catch (error) {
      console.error('Failed to save configuration:', error);
      showNotification('Failed to save configuration', 'error');
    } finally {
      setSaving(false);
    }
  };

  const testConfiguration = async () => {
    if (!config) return;

    try {
      const results = await reverseProxyApi.testConfiguration(config);
      setTestResults(results);
      setShowTestModal(true);
    } catch (error) {
      console.error('Failed to test configuration:', error);
      showNotification('Failed to test configuration', 'error');
    }
  };

  const generateProxyConfig = async () => {
    try {
      const generated = await reverseProxyApi.generateConfig(exportType);
      setExportConfig(generated.config);
      setShowExportModal(true);
    } catch (error) {
      console.error('Failed to generate configuration:', error);
      showNotification('Failed to generate configuration', 'error');
    }
  };

  const updateConfig = (updates: Partial<ReverseProxyConfig>) => {
    if (config) {
      setConfig({ ...config, ...updates });
      setHasChanges(true);
    }
  };

  const toggleURLMapping = async (mappingId: string) => {
    if (!config) return;

    const mapping = config.url_mappings.find(m => m.id === mappingId);
    if (!mapping) return;

    try {
      await reverseProxyApi.toggleURLMapping(mappingId, !mapping.enabled);
      
      const updatedMappings = config.url_mappings.map(m => 
        m.id === mappingId ? { ...m, enabled: !m.enabled } : m
      );
      
      updateConfig({ url_mappings: updatedMappings });
      showNotification(`URL mapping ${!mapping.enabled ? 'enabled' : 'disabled'}`, 'success');
    } catch (error) {
      console.error('Failed to toggle URL mapping:', error);
      showNotification('Failed to toggle URL mapping', 'error');
    }
  };

  const deleteURLMapping = async (mappingId: string) => {
    if (!config) return;

    try {
      await reverseProxyApi.deleteURLMapping(mappingId);
      
      const updatedMappings = config.url_mappings.filter(m => m.id !== mappingId);
      updateConfig({ url_mappings: updatedMappings });
      showNotification('URL mapping deleted successfully', 'success');
    } catch (error) {
      console.error('Failed to delete URL mapping:', error);
      showNotification('Failed to delete URL mapping', 'error');
    }
  };

  const getServiceStatus = (serviceName: string) => {
    // eslint-disable-next-line security/detect-object-injection
    if (!healthStatus?.services[serviceName]) {
      return { status: 'unknown', color: 'secondary' };
    }
    
    // eslint-disable-next-line security/detect-object-injection
    const service = healthStatus.services[serviceName];
    switch (service.status) {
      case 'healthy':
        return { status: 'healthy', color: 'success' };
      case 'unhealthy':
        return { status: 'unhealthy', color: 'warning' };
      case 'unreachable':
        return { status: 'unreachable', color: 'danger' };
      default:
        return { status: 'unknown', color: 'secondary' };
    }
  };

  if (loading) {
    return (
      <FlexItemsCenter justify="center" className="py-12">
        <LoadingSpinner size="lg" />
        <span className="ml-3 text-theme-secondary">Loading reverse proxy configuration...</span>
      </FlexItemsCenter>
    );
  }

  if (!config) {
    return (
      <Card className="p-8 text-center">
        <AlertTriangle className="w-12 h-12 mx-auto mb-4 text-theme-warning" />
        <h3 className="text-lg font-semibold text-theme-primary mb-2">
          Configuration Not Available
        </h3>
        <p className="text-theme-secondary mb-4">
          Unable to load reverse proxy configuration.
        </p>
        <Button onClick={loadConfiguration} variant="primary">
          <RefreshCw className="w-4 h-4 mr-2" />
          Retry
        </Button>
      </Card>
    );
  }

  return (
    <div className={`space-y-6 ${className}`}>
      {/* Header */}
      <FlexBetween>
        <div>
          <h2 className="text-xl font-semibold text-theme-primary">Reverse Proxy Configuration</h2>
          <p className="text-theme-secondary">
            Configure load balancing, routing, and service discovery
          </p>
        </div>
        
        <FlexItemsCenter gap="sm">
          <Button 
            onClick={refreshHealthStatus}
            variant="secondary"
            size="sm"
          >
            <RefreshCw className="w-4 h-4 mr-2" />
            Refresh Status
          </Button>
          
          <Button 
            onClick={testConfiguration}
            variant="secondary"
            size="sm"
          >
            <TestTube className="w-4 h-4 mr-2" />
            Test Config
          </Button>
          
          <Button 
            onClick={generateProxyConfig}
            variant="secondary"
            size="sm"
          >
            <Download className="w-4 h-4 mr-2" />
            Export
          </Button>
          
          <Button 
            onClick={saveConfiguration}
            disabled={!hasChanges || saving}
            variant="primary"
            size="sm"
          >
            {saving ? <LoadingSpinner size="sm" /> : null}
            Save Changes
          </Button>
        </FlexItemsCenter>
      </FlexBetween>

      {/* Status Overview */}
      {healthStatus && (
        <Card className="p-4">
          <FlexBetween className="mb-4">
            <h3 className="text-lg font-medium text-theme-primary">Service Status</h3>
            <Badge 
              variant={healthStatus.overall_status === 'healthy' ? 'success' : 'warning'}
              className="px-3 py-1"
            >
              {healthStatus.overall_status}
            </Badge>
          </FlexBetween>
          
          <GridCols2 gap="md">
            {Object.entries(healthStatus.services).map(([serviceName, service]) => {
              const statusInfo = getServiceStatus(serviceName);
              return (
                <FlexItemsCenter key={serviceName} className="p-3 bg-theme-surface rounded-lg">
                  <StatusIndicator 
                    status={
                      service.status === 'healthy' ? 'success' :
                      service.status === 'unhealthy' ? 'warning' :
                      service.status === 'unreachable' ? 'error' :
                      'inactive'
                    } 
                    className="mr-3"
                  />
                  <div className="flex-1">
                    <div className="font-medium text-theme-primary capitalize">
                      {serviceName}
                    </div>
                    <div className="text-sm text-theme-secondary">
                      {service.url || 'No URL configured'}
                    </div>
                  </div>
                  {service.response_time && (
                    <div className="text-sm text-theme-tertiary">
                      {service.response_time}ms
                    </div>
                  )}
                </FlexItemsCenter>
              );
            })}
          </GridCols2>
        </Card>
      )}

      {/* Tab Navigation and Content */}
      <TabContainer
        tabs={[
          {
            id: 'basic',
            label: 'Basic',
            icon: <Settings className="w-4 h-4" />,
            content: config ? (
              <BasicConfiguration 
                config={config}
                updateConfig={updateConfig}
              />
            ) : null
          },
          {
            id: 'services',
            label: 'Services',
            icon: <Server className="w-4 h-4" />,
            content: config ? (
              <ServicesConfiguration 
                config={config}
                healthStatus={healthStatus}
                updateConfig={updateConfig}
              />
            ) : null
          },
          {
            id: 'mappings',
            label: 'URL Mappings',
            icon: <Globe className="w-4 h-4" />,
            content: config ? (
              <URLMappingsConfiguration 
                config={config}
                updateConfig={updateConfig}
                onEditMapping={(mapping) => {
                  setEditingMapping(mapping);
                  setShowURLMappingModal(true);
                }}
                onDeleteMapping={deleteURLMapping}
                onToggleMapping={toggleURLMapping}
                onAddMapping={() => {
                  setEditingMapping(null);
                  setShowURLMappingModal(true);
                }}
              />
            ) : null
          },
          {
            id: 'advanced',
            label: 'Advanced',
            icon: <Shield className="w-4 h-4" />,
            content: config ? (
              <AdvancedConfiguration 
                config={config}
                updateConfig={updateConfig}
              />
            ) : null
          }
        ]}
        activeTab={activeTab}
        onTabChange={(tabId) => setActiveTab(tabId as TabType)}
        variant="underline"
      />

      {/* Test Results Modal */}
      {showTestModal && testResults && (
        <Modal
          isOpen={showTestModal}
          onClose={() => setShowTestModal(false)}
          title="Configuration Test Results"
          maxWidth="lg"
        >
          <div className="space-y-4">
            <div>
              <h4 className="font-medium text-theme-primary mb-2">Validation</h4>
              <FlexItemsCenter>
                {testResults.validation.valid ? (
                  <CheckCircle className="w-5 h-5 text-theme-success mr-2" />
                ) : (
                  <AlertTriangle className="w-5 h-5 text-theme-danger mr-2" />
                )}
                <span className={testResults.validation.valid ? 'text-theme-success' : 'text-theme-danger'}>
                  {testResults.validation.valid ? 'Configuration is valid' : 'Configuration has errors'}
                </span>
              </FlexItemsCenter>
              
              {!testResults.validation.valid && testResults.validation.errors.length > 0 && (
                <div className="mt-2 p-3 bg-theme-danger/10 rounded-lg">
                  <ul className="text-sm text-theme-danger space-y-1">
                    {testResults.validation.errors.map((error: string, index: number) => (
                      <li key={index}>• {error}</li>
                    ))}
                  </ul>
                </div>
              )}
            </div>
            
            <div>
              <h4 className="font-medium text-theme-primary mb-2">Connectivity</h4>
              <div className="space-y-2">
                {Object.entries(testResults.connectivity).map(([service, result]: [string, any]) => (
                  <FlexBetween key={service} className="p-2 bg-theme-surface rounded">
                    <span className="font-medium capitalize">{service}</span>
                    <StatusIndicator status={result.status} />
                  </FlexBetween>
                ))}
              </div>
            </div>
          </div>
        </Modal>
      )}

      {/* Export Config Modal */}
      {showExportModal && (
        <Modal
          isOpen={showExportModal}
          onClose={() => setShowExportModal(false)}
          title="Export Proxy Configuration"
          maxWidth="lg"
        >
          <div className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Proxy Type
              </label>
              <select 
                value={exportType}
                onChange={(e) => setExportType(e.target.value as any)}
                className="w-full p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
              >
                <option value="nginx">Nginx</option>
                <option value="apache">Apache</option>
                <option value="traefik">Traefik</option>
              </select>
            </div>
            
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Configuration
              </label>
              <textarea
                value={exportConfig}
                readOnly
                rows={20}
                className="w-full p-3 border border-theme rounded-lg bg-theme-surface text-theme-primary font-mono text-sm resize-none"
              />
            </div>
            
            <FlexItemsCenter justify="end" gap="sm">
              <Button 
                onClick={() => {
                  navigator.clipboard.writeText(exportConfig);
                  showNotification('Configuration copied to clipboard', 'success');
                }}
                variant="secondary"
              >
                Copy to Clipboard
              </Button>
              <Button onClick={() => setShowExportModal(false)}>
                Close
              </Button>
            </FlexItemsCenter>
          </div>
        </Modal>
      )}
    </div>
  );
};

// Basic Configuration Component
const BasicConfiguration: React.FC<{
  config: ReverseProxyConfig;
  updateConfig: (updates: Partial<ReverseProxyConfig>) => void;
}> = ({ config, updateConfig }) => {
  return (
    <div className="space-y-6">
      <Card className="p-6">
        <h3 className="text-lg font-medium text-theme-primary mb-4">Basic Settings</h3>
        
        <div className="space-y-4">
          <FlexBetween>
            <div>
              <label className="block text-sm font-medium text-theme-primary">
                Enable Reverse Proxy
              </label>
              <p className="text-sm text-theme-secondary">
                Enable reverse proxy functionality for load balancing and routing
              </p>
            </div>
            <Button
              onClick={() => updateConfig({ enabled: !config.enabled })}
              variant={config.enabled ? 'success' : 'secondary'}
              size="sm"
            >
              {config.enabled ? (
                <ToggleRight className="w-4 h-4 mr-2" />
              ) : (
                <ToggleLeft className="w-4 h-4 mr-2" />
              )}
              {config.enabled ? 'Enabled' : 'Disabled'}
            </Button>
          </FlexBetween>
          
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">
              Current Environment
            </label>
            <select 
              value={config.current_environment}
              onChange={(e) => updateConfig({ current_environment: e.target.value })}
              className="w-full max-w-xs p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
            >
              <option value="development">Development</option>
              <option value="staging">Staging</option>
              <option value="production">Production</option>
            </select>
          </div>
        </div>
      </Card>
    </div>
  );
};

// Services Configuration Component
const ServicesConfiguration: React.FC<{
  config: ReverseProxyConfig;
  updateConfig: (updates: Partial<ReverseProxyConfig>) => void;
  healthStatus: HealthStatus | null;
}> = ({ config, updateConfig, healthStatus }) => {
  const currentEnvServices = config.environments[config.current_environment] || {};

  const updateServiceConfig = (serviceName: string, updates: any) => {
    const newEnvironments = {
      ...config.environments,
      [config.current_environment]: {
        ...currentEnvServices,
        // eslint-disable-next-line security/detect-object-injection
        [serviceName]: {
          // eslint-disable-next-line security/detect-object-injection
          ...currentEnvServices[serviceName],
          ...updates
        }
      }
    };
    updateConfig({ environments: newEnvironments });
  };

  return (
    <div className="space-y-6">
      <GridCols2 gap="md">
        {Object.entries(currentEnvServices).map(([serviceName, serviceConfig]) => {
          // eslint-disable-next-line security/detect-object-injection
          const status = healthStatus?.services[serviceName];
          
          return (
            <Card key={serviceName} className="p-6">
              <FlexBetween className="mb-4">
                <h3 className="text-lg font-medium text-theme-primary capitalize">
                  {serviceName}
                </h3>
                <StatusIndicator 
                  status={
                    status?.status === 'healthy' ? 'success' :
                    status?.status === 'unhealthy' ? 'warning' :
                    status?.status === 'unreachable' ? 'error' :
                    'inactive'
                  } 
                  size="sm"
                />
              </FlexBetween>
              
              <div className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-2">
                    Host
                  </label>
                  <input
                    type="text"
                    value={serviceConfig.host}
                    onChange={(e) => updateServiceConfig(serviceName, { host: e.target.value })}
                    className="w-full p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                    placeholder="localhost"
                  />
                </div>
                
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-2">
                    Port
                  </label>
                  <input
                    type="number"
                    value={serviceConfig.port}
                    onChange={(e) => updateServiceConfig(serviceName, { port: parseInt(e.target.value) })}
                    className="w-full p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                    placeholder="3000"
                  />
                </div>
                
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-2">
                    Protocol
                  </label>
                  <select
                    value={serviceConfig.protocol}
                    onChange={(e) => updateServiceConfig(serviceName, { protocol: e.target.value })}
                    className="w-full p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                  >
                    <option value="http">HTTP</option>
                    <option value="https">HTTPS</option>
                  </select>
                </div>
                
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-2">
                    Health Check Path
                  </label>
                  <input
                    type="text"
                    value={serviceConfig.health_check_path}
                    onChange={(e) => updateServiceConfig(serviceName, { health_check_path: e.target.value })}
                    className="w-full p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                    placeholder="/health"
                  />
                </div>
                
                {status?.response_time && (
                  <div className="text-sm text-theme-secondary">
                    Response time: {status.response_time}ms
                  </div>
                )}
              </div>
            </Card>
          );
        })}
      </GridCols2>
    </div>
  );
};

// URL Mappings Configuration Component
const URLMappingsConfiguration: React.FC<{
  config: ReverseProxyConfig;
  updateConfig: (updates: Partial<ReverseProxyConfig>) => void;
  onToggleMapping: (id: string) => void;
  onDeleteMapping: (id: string) => void;
  onEditMapping: (mapping: URLMapping) => void;
  onAddMapping: () => void;
}> = ({ 
  config, 
  onToggleMapping, 
  onDeleteMapping, 
  onEditMapping, 
  onAddMapping 
}) => {
  const sortedMappings = config.url_mappings.sort((a, b) => (a.priority || 999) - (b.priority || 999));

  return (
    <div className="space-y-6">
      <FlexBetween>
        <h3 className="text-lg font-medium text-theme-primary">URL Mappings</h3>
        <Button onClick={onAddMapping} variant="primary" size="sm">
          <Plus className="w-4 h-4 mr-2" />
          Add Mapping
        </Button>
      </FlexBetween>
      
      <div className="space-y-4">
        {sortedMappings.map((mapping) => (
          <Card key={mapping.id} className="p-4">
            <FlexBetween className="mb-3">
              <div>
                <FlexItemsCenter className="mb-1">
                  <h4 className="font-medium text-theme-primary mr-3">
                    {mapping.name || mapping.pattern}
                  </h4>
                  <Badge variant={mapping.enabled ? 'success' : 'secondary'} size="sm">
                    {mapping.enabled ? 'Active' : 'Disabled'}
                  </Badge>
                  <Badge variant="info" size="sm" className="ml-2">
                    Priority: {mapping.priority}
                  </Badge>
                </FlexItemsCenter>
                <div className="text-sm text-theme-secondary">
                  {mapping.pattern} → {mapping.target_service}
                </div>
                {mapping.description && (
                  <div className="text-sm text-theme-tertiary mt-1">
                    {mapping.description}
                  </div>
                )}
              </div>
              
              <FlexItemsCenter gap="xs">
                <Button
                  onClick={() => onToggleMapping(mapping.id)}
                  variant="secondary"
                  size="sm"
                >
                  {mapping.enabled ? (
                    <ToggleRight className="w-4 h-4" />
                  ) : (
                    <ToggleLeft className="w-4 h-4" />
                  )}
                </Button>
                <Button
                  onClick={() => onEditMapping(mapping)}
                  variant="secondary"
                  size="sm"
                >
                  <Edit className="w-4 h-4" />
                </Button>
                <Button
                  onClick={() => onDeleteMapping(mapping.id)}
                  variant="danger"
                  size="sm"
                >
                  <Trash2 className="w-4 h-4" />
                </Button>
              </FlexItemsCenter>
            </FlexBetween>
            
            <div className="flex flex-wrap gap-2">
              {mapping.methods.map((method) => (
                <Badge key={method} variant="secondary" size="sm">
                  {method}
                </Badge>
              ))}
            </div>
          </Card>
        ))}
        
        {sortedMappings.length === 0 && (
          <Card className="p-8 text-center">
            <Globe className="w-12 h-12 mx-auto mb-4 text-theme-secondary" />
            <h3 className="text-lg font-medium text-theme-primary mb-2">
              No URL Mappings
            </h3>
            <p className="text-theme-secondary mb-4">
              Add URL mappings to configure request routing.
            </p>
            <Button onClick={onAddMapping} variant="primary">
              <Plus className="w-4 h-4 mr-2" />
              Add Your First Mapping
            </Button>
          </Card>
        )}
      </div>
    </div>
  );
};

// Advanced Configuration Component
const AdvancedConfiguration: React.FC<{
  config: ReverseProxyConfig;
  updateConfig: (updates: Partial<ReverseProxyConfig>) => void;
}> = ({ config, updateConfig }) => {
  return (
    <div className="space-y-6">
      {/* Load Balancing */}
      <Card className="p-6">
        <h3 className="text-lg font-medium text-theme-primary mb-4">Load Balancing</h3>
        <div className="space-y-4">
          <FlexBetween>
            <div>
              <label className="block text-sm font-medium text-theme-primary">
                Enable Load Balancing
              </label>
              <p className="text-sm text-theme-secondary">
                Distribute requests across multiple backend instances
              </p>
            </div>
            <Button
              onClick={() => updateConfig({ 
                load_balancing: { ...config.load_balancing, enabled: !config.load_balancing.enabled }
              })}
              variant={config.load_balancing.enabled ? 'success' : 'secondary'}
              size="sm"
            >
              {config.load_balancing.enabled ? 'Enabled' : 'Disabled'}
            </Button>
          </FlexBetween>
          
          {config.load_balancing.enabled && (
            <div className="space-y-4 pl-4 border-l-2 border-theme">
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Algorithm
                </label>
                <select 
                  value={config.load_balancing.algorithm}
                  onChange={(e) => updateConfig({ 
                    load_balancing: { ...config.load_balancing, algorithm: e.target.value as any }
                  })}
                  className="w-full max-w-xs p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                >
                  <option value="round_robin">Round Robin</option>
                  <option value="least_connections">Least Connections</option>
                  <option value="ip_hash">IP Hash</option>
                </select>
              </div>
              
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Health Check Interval (seconds)
                </label>
                <input
                  type="number"
                  value={config.load_balancing.health_check_interval}
                  onChange={(e) => updateConfig({ 
                    load_balancing: { ...config.load_balancing, health_check_interval: parseInt(e.target.value) }
                  })}
                  className="w-full max-w-xs p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                  min="5"
                  max="300"
                />
              </div>
            </div>
          )}
        </div>
      </Card>

      {/* SSL Configuration */}
      <Card className="p-6">
        <h3 className="text-lg font-medium text-theme-primary mb-4">SSL/TLS Configuration</h3>
        <div className="space-y-4">
          <FlexBetween>
            <div>
              <label className="block text-sm font-medium text-theme-primary">
                Enable SSL/TLS
              </label>
              <p className="text-sm text-theme-secondary">
                Enable HTTPS with SSL/TLS encryption
              </p>
            </div>
            <Button
              onClick={() => updateConfig({ 
                ssl_config: { ...config.ssl_config, enabled: !config.ssl_config.enabled }
              })}
              variant={config.ssl_config.enabled ? 'success' : 'secondary'}
              size="sm"
            >
              {config.ssl_config.enabled ? 'Enabled' : 'Disabled'}
            </Button>
          </FlexBetween>
          
          {config.ssl_config.enabled && (
            <div className="space-y-4 pl-4 border-l-2 border-theme">
              <FlexBetween>
                <div>
                  <label className="block text-sm font-medium text-theme-primary">
                    Enforce HTTPS
                  </label>
                  <p className="text-sm text-theme-secondary">
                    Redirect all HTTP requests to HTTPS
                  </p>
                </div>
                <Button
                  onClick={() => updateConfig({ 
                    ssl_config: { ...config.ssl_config, enforce_https: !config.ssl_config.enforce_https }
                  })}
                  variant={config.ssl_config.enforce_https ? 'success' : 'secondary'}
                  size="sm"
                >
                  {config.ssl_config.enforce_https ? 'Yes' : 'No'}
                </Button>
              </FlexBetween>
              
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Certificate Path
                </label>
                <input
                  type="text"
                  value={config.ssl_config.certificate_path}
                  onChange={(e) => updateConfig({ 
                    ssl_config: { ...config.ssl_config, certificate_path: e.target.value }
                  })}
                  className="w-full p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                  placeholder="/etc/ssl/certs/powernode.crt"
                />
              </div>
              
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Private Key Path
                </label>
                <input
                  type="text"
                  value={config.ssl_config.private_key_path}
                  onChange={(e) => updateConfig({ 
                    ssl_config: { ...config.ssl_config, private_key_path: e.target.value }
                  })}
                  className="w-full p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                  placeholder="/etc/ssl/private/powernode.key"
                />
              </div>
            </div>
          )}
        </div>
      </Card>

      {/* CORS Configuration */}
      <Card className="p-6">
        <h3 className="text-lg font-medium text-theme-primary mb-4">CORS Configuration</h3>
        <div className="space-y-4">
          <FlexBetween>
            <div>
              <label className="block text-sm font-medium text-theme-primary">
                Enable CORS
              </label>
              <p className="text-sm text-theme-secondary">
                Configure Cross-Origin Resource Sharing policies
              </p>
            </div>
            <Button
              onClick={() => updateConfig({ 
                cors_config: { ...config.cors_config, enabled: !config.cors_config.enabled }
              })}
              variant={config.cors_config.enabled ? 'success' : 'secondary'}
              size="sm"
            >
              {config.cors_config.enabled ? 'Enabled' : 'Disabled'}
            </Button>
          </FlexBetween>
          
          {config.cors_config.enabled && (
            <div className="space-y-4 pl-4 border-l-2 border-theme">
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Allowed Origins (one per line)
                </label>
                <textarea
                  value={config.cors_config.allowed_origins.join('\n')}
                  onChange={(e) => updateConfig({ 
                    cors_config: { 
                      ...config.cors_config, 
                      allowed_origins: e.target.value.split('\n').filter(o => o.trim()) 
                    }
                  })}
                  rows={3}
                  className="w-full p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                  placeholder="https://app.powernode.io&#10;https://admin.powernode.io&#10;*"
                />
              </div>
              
              <FlexBetween>
                <div>
                  <label className="block text-sm font-medium text-theme-primary">
                    Allow Credentials
                  </label>
                  <p className="text-sm text-theme-secondary">
                    Allow credentials in cross-origin requests
                  </p>
                </div>
                <Button
                  onClick={() => updateConfig({ 
                    cors_config: { ...config.cors_config, credentials: !config.cors_config.credentials }
                  })}
                  variant={config.cors_config.credentials ? 'success' : 'secondary'}
                  size="sm"
                >
                  {config.cors_config.credentials ? 'Yes' : 'No'}
                </Button>
              </FlexBetween>
            </div>
          )}
        </div>
      </Card>

      {/* Rate Limiting */}
      <Card className="p-6">
        <h3 className="text-lg font-medium text-theme-primary mb-4">Rate Limiting</h3>
        <div className="space-y-4">
          <FlexBetween>
            <div>
              <label className="block text-sm font-medium text-theme-primary">
                Enable Rate Limiting
              </label>
              <p className="text-sm text-theme-secondary">
                Limit request rates to prevent abuse
              </p>
            </div>
            <Button
              onClick={() => updateConfig({ 
                rate_limiting: { ...config.rate_limiting, enabled: !config.rate_limiting.enabled }
              })}
              variant={config.rate_limiting.enabled ? 'success' : 'secondary'}
              size="sm"
            >
              {config.rate_limiting.enabled ? 'Enabled' : 'Disabled'}
            </Button>
          </FlexBetween>
          
          {config.rate_limiting.enabled && (
            <div className="space-y-4 pl-4 border-l-2 border-theme">
              <GridCols2 gap="md">
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-2">
                    Requests per Hour
                  </label>
                  <input
                    type="number"
                    value={config.rate_limiting.default_limit}
                    onChange={(e) => updateConfig({ 
                      rate_limiting: { ...config.rate_limiting, default_limit: parseInt(e.target.value) }
                    })}
                    className="w-full p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                    min="1"
                    max="100000"
                  />
                </div>
                
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-2">
                    Burst Limit
                  </label>
                  <input
                    type="number"
                    value={config.rate_limiting.burst_limit}
                    onChange={(e) => updateConfig({ 
                      rate_limiting: { ...config.rate_limiting, burst_limit: parseInt(e.target.value) }
                    })}
                    className="w-full p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                    min="1"
                    max="10000"
                  />
                </div>
              </GridCols2>
            </div>
          )}
        </div>
      </Card>
    </div>
  );
};

export { ReverseProxyConfiguration };
export default ReverseProxyConfiguration;
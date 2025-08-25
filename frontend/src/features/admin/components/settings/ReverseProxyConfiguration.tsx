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
import { reverseProxyApi, ReverseProxyConfig, URLMapping, HealthStatus, ServiceDiscoveryConfig } from '../../services/reverseProxyApi';
import { URLMappingModal } from './URLMappingModal';
import { TestConfigurationModal } from './TestConfigurationModal';
import { ExportConfigurationModal } from './ExportConfigurationModal';
import { ServiceDiscoveryModal } from './ServiceDiscoveryModal';
import { HealthMonitoringDashboard } from './HealthMonitoringDashboard';
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
  CheckCircle,
  Copy,
  XCircle
} from 'lucide-react';

interface ReverseProxyConfigurationProps {
  className?: string;
}

type TabType = 'basic' | 'services' | 'mappings' | 'advanced' | 'monitoring' | 'discovery';

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
  const [showServiceDiscoveryModal, setShowServiceDiscoveryModal] = useState(false);
  const [editingMapping, setEditingMapping] = useState<URLMapping | null>(null);
  const [serviceDiscoveryConfig, setServiceDiscoveryConfig] = useState<ServiceDiscoveryConfig | null>(null);
  
  // Form states

  useEffect(() => {
    loadConfiguration();
  }, []);

  // Auto-refresh health status every 30 seconds
  useEffect(() => {
    if (!config?.enabled) return;

    const interval = setInterval(() => {
      refreshHealthStatus();
    }, 30000); // 30 seconds

    return () => clearInterval(interval);
  }, [config?.enabled]);

  const loadConfiguration = async () => {
    try {
      setLoading(true);
      const data = await reverseProxyApi.getConfiguration();
      setConfig(data.reverse_proxy_config);
      setHealthStatus(data.health_status);
      setServiceDiscoveryConfig(data.service_discovery_config);
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

  const updateServiceDiscoveryConfig = async (newConfig: ServiceDiscoveryConfig) => {
    try {
      await reverseProxyApi.updateConfiguration('service_discovery_config', newConfig);
      setServiceDiscoveryConfig(newConfig);
      showNotification('Service discovery configuration updated successfully', 'success');
    } catch (error) {
      console.error('Failed to update service discovery configuration:', error);
      showNotification('Failed to update service discovery configuration', 'error');
      throw error;
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

  const testConfiguration = () => {
    setShowTestModal(true);
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

  const handleSaveURLMapping = async (mapping: URLMapping) => {
    if (!config) return;

    try {
      if (editingMapping) {
        // Update existing mapping
        await reverseProxyApi.updateURLMapping(mapping.id, mapping);
        const updatedMappings = config.url_mappings.map(m => 
          m.id === mapping.id ? mapping : m
        );
        updateConfig({ url_mappings: updatedMappings });
      } else {
        // Create new mapping
        const response = await reverseProxyApi.createURLMapping(mapping);
        const newMapping = response.mapping;
        updateConfig({ 
          url_mappings: [...config.url_mappings, newMapping] 
        });
      }
      
      setShowURLMappingModal(false);
      setEditingMapping(null);
    } catch (error) {
      console.error('Failed to save URL mapping:', error);
      throw error; // Re-throw to let modal handle the error
    }
  };

  const getAvailableServices = (): string[] => {
    if (!config) return [];
    const currentEnv = config.current_environment || 'development';
    return Object.keys(config.environments[currentEnv] || {});
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
            onClick={() => setShowExportModal(true)}
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
          },
          {
            id: 'monitoring',
            label: 'Health Monitoring',
            icon: <Activity className="w-4 h-4" />,
            content: healthStatus ? (
              <HealthMonitoringDashboard
                healthStatus={healthStatus}
                onRefresh={refreshHealthStatus}
                refreshing={false}
              />
            ) : null
          },
          {
            id: 'discovery',
            label: 'Service Discovery',
            icon: <Zap className="w-4 h-4" />,
            content: serviceDiscoveryConfig ? (
              <div className="space-y-4">
                <FlexBetween>
                  <div>
                    <h3 className="text-lg font-medium text-theme-primary">Service Discovery</h3>
                    <p className="text-sm text-theme-secondary">
                      Automatically discover and configure services in your environment
                    </p>
                  </div>
                  <Button
                    onClick={() => setShowServiceDiscoveryModal(true)}
                    variant="primary"
                    size="sm"
                  >
                    <Settings className="w-4 h-4 mr-2" />
                    Configure Discovery
                  </Button>
                </FlexBetween>
                <Card className="p-6">
                  <div className="grid grid-cols-2 gap-6">
                    <div>
                      <h4 className="font-medium text-theme-primary mb-2">Status</h4>
                      <Badge variant={serviceDiscoveryConfig.enabled ? 'success' : 'secondary'}>
                        {serviceDiscoveryConfig.enabled ? 'Enabled' : 'Disabled'}
                      </Badge>
                    </div>
                    <div>
                      <h4 className="font-medium text-theme-primary mb-2">Discovery Methods</h4>
                      <div className="flex flex-wrap gap-1">
                        {serviceDiscoveryConfig.methods?.map((method: string) => (
                          <Badge key={method} variant="info" size="sm">
                            {method.replace('_', ' ')}
                          </Badge>
                        )) || <span className="text-theme-secondary text-sm">None configured</span>}
                      </div>
                    </div>
                  </div>
                </Card>
              </div>
            ) : null
          }
        ]}
        activeTab={activeTab}
        onTabChange={(tabId) => setActiveTab(tabId as TabType)}
        variant="underline"
      />


      {/* Export Configuration Modal */}
      <ExportConfigurationModal
        isOpen={showExportModal}
        onClose={() => setShowExportModal(false)}
      />

      {/* Service Discovery Modal */}
      {serviceDiscoveryConfig && (
        <ServiceDiscoveryModal
          isOpen={showServiceDiscoveryModal}
          onClose={() => setShowServiceDiscoveryModal(false)}
          config={serviceDiscoveryConfig}
          onConfigUpdate={updateServiceDiscoveryConfig}
        />
      )}

      {/* URL Mapping Modal */}
      <URLMappingModal
        isOpen={showURLMappingModal}
        onClose={() => {
          setShowURLMappingModal(false);
          setEditingMapping(null);
        }}
        onSave={handleSaveURLMapping}
        mapping={editingMapping}
        availableServices={getAvailableServices()}
      />

      {/* Test Configuration Modal */}
      {config && (
        <TestConfigurationModal
          isOpen={showTestModal}
          onClose={() => setShowTestModal(false)}
          config={config}
        />
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
  const { showNotification } = useNotification();
  const [selectedEnvironment, setSelectedEnvironment] = useState(config.current_environment);
  const [showAddServiceModal, setShowAddServiceModal] = useState(false);
  const [editingService, setEditingService] = useState<string | null>(null);
  const [showServiceTemplates, setShowServiceTemplates] = useState(false);
  
  const currentEnvServices = config.environments[selectedEnvironment] || {};
  const availableEnvironments = ['development', 'staging', 'production'];
  
  // Service templates for quick setup
  const serviceTemplates = [
    {
      name: 'Frontend (React/Vue)',
      type: 'frontend',
      config: {
        host: 'localhost',
        port: 3000,
        protocol: 'http',
        health_check_path: '/',
        base_url: 'http://localhost:3000'
      }
    },
    {
      name: 'Backend API (Rails/Node)',
      type: 'backend',
      config: {
        host: 'localhost',
        port: 5000,
        protocol: 'http',
        health_check_path: '/api/health',
        base_url: 'http://localhost:5000'
      }
    },
    {
      name: 'Worker Service (Sidekiq)',
      type: 'worker',
      config: {
        host: 'localhost',
        port: 6000,
        protocol: 'http',
        health_check_path: '/health',
        base_url: 'http://localhost:6000'
      }
    },
    {
      name: 'Database (PostgreSQL)',
      type: 'database',
      config: {
        host: 'localhost',
        port: 5432,
        protocol: 'tcp',
        health_check_path: '',
        base_url: 'postgresql://localhost:5432'
      }
    },
    {
      name: 'Cache (Redis)',
      type: 'cache',
      config: {
        host: 'localhost',
        port: 6379,
        protocol: 'redis',
        health_check_path: '',
        base_url: 'redis://localhost:6379'
      }
    },
    {
      name: 'Load Balancer (Nginx)',
      type: 'proxy',
      config: {
        host: 'localhost',
        port: 80,
        protocol: 'http',
        health_check_path: '/nginx_status',
        base_url: 'http://localhost'
      }
    },
    {
      name: 'External Reverse Proxy',
      type: 'external_proxy',
      config: {
        host: 'proxy.example.com',
        port: 443,
        protocol: 'https',
        health_check_path: '/health',
        base_url: 'https://proxy.example.com'
      }
    }
  ];

  const updateServiceConfig = (serviceName: string, updates: any) => {
    const newEnvironments = {
      ...config.environments,
      [selectedEnvironment]: {
        ...currentEnvServices,
        [serviceName]: {
          ...currentEnvServices[serviceName],
          ...updates,
          base_url: `${updates.protocol || currentEnvServices[serviceName]?.protocol}://${updates.host || currentEnvServices[serviceName]?.host}:${updates.port || currentEnvServices[serviceName]?.port}`
        }
      }
    };
    updateConfig({ environments: newEnvironments });
  };

  const addService = (name: string, serviceConfig: any) => {
    if (currentEnvServices[name]) {
      showNotification('Service with this name already exists', 'error');
      return;
    }

    const newEnvironments = {
      ...config.environments,
      [selectedEnvironment]: {
        ...currentEnvServices,
        [name]: {
          ...serviceConfig,
          base_url: `${serviceConfig.protocol}://${serviceConfig.host}:${serviceConfig.port}`
        }
      }
    };
    updateConfig({ environments: newEnvironments });
    setShowAddServiceModal(false);
    showNotification(`Service ${name} added successfully`, 'success');
  };

  const deleteService = (serviceName: string) => {
    const newServices = { ...currentEnvServices };
    delete newServices[serviceName];
    
    const newEnvironments = {
      ...config.environments,
      [selectedEnvironment]: newServices
    };
    updateConfig({ environments: newEnvironments });
    showNotification(`Service ${serviceName} deleted successfully`, 'success');
  };

  const duplicateService = (serviceName: string) => {
    const sourceConfig = currentEnvServices[serviceName];
    const newName = `${serviceName}_copy`;
    
    if (currentEnvServices[newName]) {
      showNotification('Service copy already exists', 'error');
      return;
    }

    addService(newName, { 
      ...sourceConfig, 
      port: sourceConfig.port + 1 // Increment port to avoid conflicts
    });
  };

  const copyServiceToEnvironment = (serviceName: string, targetEnv: string) => {
    const sourceConfig = currentEnvServices[serviceName];
    const targetServices = config.environments[targetEnv] || {};
    
    if (targetServices[serviceName]) {
      showNotification(`Service ${serviceName} already exists in ${targetEnv}`, 'error');
      return;
    }

    const newEnvironments = {
      ...config.environments,
      [targetEnv]: {
        ...targetServices,
        [serviceName]: { ...sourceConfig }
      }
    };
    updateConfig({ environments: newEnvironments });
    showNotification(`Service ${serviceName} copied to ${targetEnv}`, 'success');
  };

  const switchEnvironment = (environment: string) => {
    setSelectedEnvironment(environment);
    
    // Initialize environment if it doesn't exist
    if (!config.environments[environment]) {
      const newEnvironments = {
        ...config.environments,
        [environment]: {}
      };
      updateConfig({ environments: newEnvironments });
    }
  };

  const testServiceConnection = async (serviceName: string) => {
    try {
      const result = await reverseProxyApi.testServiceConnection(selectedEnvironment, serviceName);
      
      if (result.status === 'healthy') {
        showNotification(`${serviceName} is healthy (${result.response_time}ms)`, 'success');
      } else if (result.status === 'unhealthy') {
        showNotification(`${serviceName} returned HTTP ${result.response_code}`, 'warning');
      } else {
        showNotification(`${serviceName} is unreachable: ${result.error}`, 'error');
      }
    } catch (error) {
      console.error('Service test failed:', error);
      showNotification(`Failed to test ${serviceName}`, 'error');
    }
  };

  const importServicesFromTemplate = () => {
    const defaultServices = serviceTemplates.reduce((acc, template) => {
      const serviceName = template.type;
      if (!currentEnvServices[serviceName]) {
        acc[serviceName] = template.config;
      }
      return acc;
    }, {} as any);

    if (Object.keys(defaultServices).length === 0) {
      showNotification('All template services already exist', 'warning');
      return;
    }

    const newEnvironments = {
      ...config.environments,
      [selectedEnvironment]: {
        ...currentEnvServices,
        ...defaultServices
      }
    };
    updateConfig({ environments: newEnvironments });
    showNotification(`${Object.keys(defaultServices).length} services imported`, 'success');
  };

  return (
    <div className="space-y-6">
      {/* Environment and Actions Header */}
      <Card className="p-6">
        <FlexBetween className="mb-6">
          <div>
            <h3 className="text-lg font-medium text-theme-primary">Services Configuration</h3>
            <p className="text-sm text-theme-secondary">
              Manage service endpoints and health monitoring across environments
            </p>
          </div>
          <div className="flex items-center space-x-3">
            <Button
              onClick={() => setShowServiceTemplates(true)}
              variant="secondary"
              size="sm"
            >
              <Download className="w-4 h-4 mr-2" />
              Templates
            </Button>
            <Button
              onClick={() => setShowAddServiceModal(true)}
              variant="primary"
              size="sm"
            >
              <Plus className="w-4 h-4 mr-2" />
              Add Service
            </Button>
          </div>
        </FlexBetween>

        {/* Environment Selector */}
        <div className="grid grid-cols-4 gap-4">
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">
              Environment
            </label>
            <select
              value={selectedEnvironment}
              onChange={(e) => switchEnvironment(e.target.value)}
              className="w-full p-3 border border-theme rounded-lg bg-theme-surface text-theme-primary"
            >
              {availableEnvironments.map((env) => (
                <option key={env} value={env}>
                  {env.charAt(0).toUpperCase() + env.slice(1)}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">
              Services Count
            </label>
            <div className="p-3 bg-theme-surface border border-theme rounded-lg">
              <span className="text-theme-primary font-medium">
                {Object.keys(currentEnvServices).length} services
              </span>
            </div>
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">
              Healthy Services
            </label>
            <div className="p-3 bg-theme-surface border border-theme rounded-lg">
              <span className="text-theme-success font-medium">
                {Object.keys(currentEnvServices).filter(name => 
                  healthStatus?.services[name]?.status === 'healthy'
                ).length} healthy
              </span>
            </div>
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">
              Actions
            </label>
            <Button
              onClick={importServicesFromTemplate}
              variant="secondary"
              size="sm"
              className="w-full"
            >
              <Zap className="w-4 h-4 mr-2" />
              Quick Setup
            </Button>
          </div>
        </div>
      </Card>

      {/* Services Grid */}
      {Object.keys(currentEnvServices).length === 0 ? (
        <Card className="p-12 text-center">
          <Server className="w-12 h-12 mx-auto mb-4 text-theme-secondary" />
          <h3 className="text-lg font-medium text-theme-primary mb-2">
            No Services Configured
          </h3>
          <p className="text-theme-secondary mb-6">
            Add services to configure reverse proxy routing for the {selectedEnvironment} environment
          </p>
          <div className="flex justify-center space-x-3">
            <Button
              onClick={() => setShowAddServiceModal(true)}
              variant="primary"
            >
              <Plus className="w-4 h-4 mr-2" />
              Add Your First Service
            </Button>
            <Button
              onClick={importServicesFromTemplate}
              variant="secondary"
            >
              <Download className="w-4 h-4 mr-2" />
              Use Templates
            </Button>
          </div>
        </Card>
      ) : (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {Object.entries(currentEnvServices).map(([serviceName, serviceConfig]) => {
            const status = healthStatus?.services[serviceName];
            const isHealthy = status?.status === 'healthy';
            const isUnhealthy = status?.status === 'unhealthy';
            const isUnreachable = status?.status === 'unreachable';
            
            return (
              <Card key={serviceName} className="p-6">
                {/* Service Header */}
                <FlexBetween className="mb-4">
                  <div className="flex items-center space-x-3">
                    <h4 className="text-lg font-medium text-theme-primary capitalize">
                      {serviceName}
                    </h4>
                    <StatusIndicator 
                      status={
                        isHealthy ? 'success' :
                        isUnhealthy ? 'warning' :
                        isUnreachable ? 'error' :
                        'inactive'
                      } 
                      size="sm"
                    />
                  </div>
                  <div className="flex items-center space-x-2">
                    <Button
                      onClick={() => testServiceConnection(serviceName)}
                      variant="secondary"
                      size="sm"
                    >
                      <Activity className="w-4 h-4" />
                    </Button>
                    <Button
                      onClick={() => setEditingService(editingService === serviceName ? null : serviceName)}
                      variant="secondary"
                      size="sm"
                    >
                      <Settings className="w-4 h-4" />
                    </Button>
                  </div>
                </FlexBetween>

                {/* Service Status */}
                <div className="mb-4 p-3 bg-theme-surface rounded-lg border border-theme">
                  <div className="grid grid-cols-2 gap-4 text-sm">
                    <div>
                      <span className="text-theme-secondary">URL: </span>
                      <span className="text-theme-primary font-mono">
                        {serviceConfig.base_url}
                      </span>
                    </div>
                    <div>
                      <span className="text-theme-secondary">Health: </span>
                      <span className="text-theme-primary">
                        {serviceConfig.health_check_path || 'No health check'}
                      </span>
                    </div>
                    {status?.response_time && (
                      <div>
                        <span className="text-theme-secondary">Response: </span>
                        <span className="text-theme-primary">{status.response_time}ms</span>
                      </div>
                    )}
                    {status?.response_code && (
                      <div>
                        <span className="text-theme-secondary">Status: </span>
                        <span className="text-theme-primary">HTTP {status.response_code}</span>
                      </div>
                    )}
                  </div>
                </div>

                {/* Service Configuration (Expandable) */}
                {editingService === serviceName && (
                  <div className="space-y-4 border-t border-theme pt-4">
                    <div className="grid grid-cols-2 gap-4">
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
                          onChange={(e) => updateServiceConfig(serviceName, { port: parseInt(e.target.value) || 0 })}
                          className="w-full p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                          placeholder="3000"
                        />
                      </div>
                    </div>
                    
                    <div className="grid grid-cols-2 gap-4">
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
                          <option value="tcp">TCP</option>
                          <option value="ws">WebSocket</option>
                          <option value="wss">WebSocket Secure</option>
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
                    </div>

                    {/* Service Actions */}
                    <div className="flex justify-between items-center pt-4 border-t border-theme">
                      <div className="flex space-x-2">
                        <Button
                          onClick={() => duplicateService(serviceName)}
                          variant="secondary"
                          size="sm"
                        >
                          <Copy className="w-4 h-4 mr-2" />
                          Duplicate
                        </Button>
                        <select
                          onChange={(e) => {
                            if (e.target.value) {
                              copyServiceToEnvironment(serviceName, e.target.value);
                              e.target.value = '';
                            }
                          }}
                          className="p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary text-sm"
                        >
                          <option value="">Copy to...</option>
                          {availableEnvironments.filter(env => env !== selectedEnvironment).map(env => (
                            <option key={env} value={env}>
                              {env.charAt(0).toUpperCase() + env.slice(1)}
                            </option>
                          ))}
                        </select>
                      </div>
                      <Button
                        onClick={() => deleteService(serviceName)}
                        variant="danger"
                        size="sm"
                      >
                        <Trash2 className="w-4 h-4 mr-2" />
                        Delete
                      </Button>
                    </div>
                  </div>
                )}
              </Card>
            );
          })}
        </div>
      )}

      {/* Service Templates Modal */}
      {showServiceTemplates && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <Card className="w-full max-w-4xl m-4 p-6 max-h-[80vh] overflow-y-auto">
            <FlexBetween className="mb-6">
              <div>
                <h3 className="text-lg font-semibold text-theme-primary">Service Templates</h3>
                <p className="text-sm text-theme-secondary">
                  Quick setup with pre-configured service templates
                </p>
              </div>
              <Button
                onClick={() => setShowServiceTemplates(false)}
                variant="secondary"
                size="sm"
              >
                <XCircle className="w-4 h-4" />
              </Button>
            </FlexBetween>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {serviceTemplates.map((template) => (
                <Card 
                  key={template.type}
                  className={`p-4 cursor-pointer border-2 transition-all ${
                    currentEnvServices[template.type] 
                      ? 'border-theme-success bg-theme-success/10' 
                      : 'border-theme hover:border-theme-primary/50'
                  }`}
                  onClick={() => {
                    if (!currentEnvServices[template.type]) {
                      addService(template.type, template.config);
                    }
                  }}
                >
                  <FlexBetween className="mb-3">
                    <h4 className="font-medium text-theme-primary">{template.name}</h4>
                    {currentEnvServices[template.type] && (
                      <Badge variant="success" size="sm">Configured</Badge>
                    )}
                  </FlexBetween>
                  <div className="text-sm space-y-1">
                    <div><span className="text-theme-secondary">Port:</span> {template.config.port}</div>
                    <div><span className="text-theme-secondary">Protocol:</span> {template.config.protocol}</div>
                    <div><span className="text-theme-secondary">Health:</span> {template.config.health_check_path || 'None'}</div>
                  </div>
                </Card>
              ))}
            </div>

            <div className="flex justify-between items-center mt-6 pt-4 border-t border-theme">
              <Button
                onClick={importServicesFromTemplate}
                variant="primary"
              >
                <Download className="w-4 h-4 mr-2" />
                Import All Available Templates
              </Button>
              <Button
                onClick={() => setShowServiceTemplates(false)}
                variant="secondary"
              >
                Close
              </Button>
            </div>
          </Card>
        </div>
      )}

      {/* Add Service Modal */}
      {showAddServiceModal && (
        <AddServiceModal
          isOpen={showAddServiceModal}
          onClose={() => setShowAddServiceModal(false)}
          onAddService={addService}
          existingServices={Object.keys(currentEnvServices)}
          templates={serviceTemplates}
        />
      )}
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
                  value={config?.cors_config?.allowed_origins?.join('\n') || ''}
                  onChange={(e) => updateConfig({ 
                    cors_config: { 
                      ...config?.cors_config, 
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
                    cors_config: { ...config?.cors_config, credentials: !config?.cors_config?.credentials }
                  })}
                  variant={config?.cors_config?.credentials ? 'success' : 'secondary'}
                  size="sm"
                >
                  {config?.cors_config?.credentials ? 'Yes' : 'No'}
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

// Add Service Modal Component
interface AddServiceModalProps {
  isOpen: boolean;
  onClose: () => void;
  onAddService: (name: string, config: any) => void;
  existingServices: string[];
  templates: Array<{
    name: string;
    type: string;
    config: {
      host: string;
      port: number;
      protocol: string;
      health_check_path: string;
      base_url: string;
    };
  }>;
}

const AddServiceModal: React.FC<AddServiceModalProps> = ({
  isOpen,
  onClose,
  onAddService,
  existingServices,
  templates
}) => {
  const { showNotification } = useNotification();
  const [serviceName, setServiceName] = useState('');
  const [selectedTemplate, setSelectedTemplate] = useState<string>('');
  const [customConfig, setCustomConfig] = useState({
    host: 'localhost',
    port: 3000,
    protocol: 'http',
    health_check_path: '/health'
  });
  const [useTemplate, setUseTemplate] = useState(true);

  const resetForm = () => {
    setServiceName('');
    setSelectedTemplate('');
    setCustomConfig({
      host: 'localhost',
      port: 3000,
      protocol: 'http',
      health_check_path: '/health'
    });
    setUseTemplate(true);
  };

  const handleClose = () => {
    resetForm();
    onClose();
  };

  const handleSubmit = () => {
    if (!serviceName.trim()) {
      showNotification('Please enter a service name', 'error');
      return;
    }

    if (existingServices.includes(serviceName.toLowerCase())) {
      showNotification('A service with this name already exists', 'error');
      return;
    }

    let config;
    if (useTemplate && selectedTemplate) {
      const template = templates.find(t => t.type === selectedTemplate);
      config = template ? { ...template.config } : customConfig;
    } else {
      config = {
        ...customConfig,
        base_url: `${customConfig.protocol}://${customConfig.host}:${customConfig.port}`
      };
    }

    onAddService(serviceName.toLowerCase(), config);
    handleClose();
  };

  useEffect(() => {
    if (!isOpen) {
      resetForm();
    }
  }, [isOpen]);

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleClose}
      title="Add New Service"
      maxWidth="lg"
    >
      <div className="space-y-6">
        {/* Service Name */}
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-2">
            Service Name *
          </label>
          <input
            type="text"
            value={serviceName}
            onChange={(e) => setServiceName(e.target.value)}
            className="w-full p-3 border border-theme rounded-lg bg-theme-surface text-theme-primary"
            placeholder="e.g., frontend, backend, api"
          />
          <p className="text-xs text-theme-secondary mt-1">
            Use lowercase letters, numbers, and underscores only
          </p>
        </div>

        {/* Configuration Method */}
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-3">
            Configuration Method
          </label>
          <div className="flex space-x-4">
            <Button
              onClick={() => setUseTemplate(true)}
              variant={useTemplate ? 'primary' : 'secondary'}
              size="sm"
            >
              Use Template
            </Button>
            <Button
              onClick={() => setUseTemplate(false)}
              variant={!useTemplate ? 'primary' : 'secondary'}
              size="sm"
            >
              Custom Configuration
            </Button>
          </div>
        </div>

        {/* Template Selection */}
        {useTemplate && (
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">
              Service Template
            </label>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              {templates.map((template) => (
                <Card
                  key={template.type}
                  className={`p-3 cursor-pointer border-2 transition-all ${
                    selectedTemplate === template.type
                      ? 'border-theme-primary bg-theme-primary/5'
                      : 'border-theme hover:border-theme-primary/50'
                  }`}
                  onClick={() => setSelectedTemplate(template.type)}
                >
                  <div className="flex justify-between items-center mb-2">
                    <h4 className="font-medium text-theme-primary text-sm">{template.name}</h4>
                    {selectedTemplate === template.type && (
                      <CheckCircle className="w-4 h-4 text-theme-primary" />
                    )}
                  </div>
                  <div className="text-xs space-y-1 text-theme-secondary">
                    <div>Port: {template.config.port}</div>
                    <div>Protocol: {template.config.protocol}</div>
                  </div>
                </Card>
              ))}
            </div>
          </div>
        )}

        {/* Custom Configuration */}
        {!useTemplate && (
          <div className="space-y-4">
            <h4 className="text-sm font-medium text-theme-primary">Custom Configuration</h4>
            
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Host
                </label>
                <input
                  type="text"
                  value={customConfig.host}
                  onChange={(e) => setCustomConfig(prev => ({ ...prev, host: e.target.value }))}
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
                  value={customConfig.port}
                  onChange={(e) => setCustomConfig(prev => ({ ...prev, port: parseInt(e.target.value) || 3000 }))}
                  className="w-full p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                  placeholder="3000"
                />
              </div>
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Protocol
                </label>
                <select
                  value={customConfig.protocol}
                  onChange={(e) => setCustomConfig(prev => ({ ...prev, protocol: e.target.value }))}
                  className="w-full p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                >
                  <option value="http">HTTP</option>
                  <option value="https">HTTPS</option>
                  <option value="tcp">TCP</option>
                  <option value="ws">WebSocket</option>
                  <option value="wss">WebSocket Secure</option>
                </select>
              </div>
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Health Check Path
                </label>
                <input
                  type="text"
                  value={customConfig.health_check_path}
                  onChange={(e) => setCustomConfig(prev => ({ ...prev, health_check_path: e.target.value }))}
                  className="w-full p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                  placeholder="/health"
                />
              </div>
            </div>

            {/* Preview */}
            <div className="p-3 bg-theme-surface border border-theme rounded-lg">
              <p className="text-sm text-theme-secondary mb-1">Service URL Preview:</p>
              <p className="text-theme-primary font-mono">
                {customConfig.protocol}://{customConfig.host}:{customConfig.port}{customConfig.health_check_path}
              </p>
            </div>
          </div>
        )}
      </div>

      {/* Modal Actions */}
      <div className="flex justify-end space-x-3 mt-6 pt-4 border-t border-theme">
        <Button
          onClick={handleClose}
          variant="secondary"
        >
          Cancel
        </Button>
        <Button
          onClick={handleSubmit}
          variant="primary"
          disabled={!serviceName.trim() || (useTemplate && !selectedTemplate)}
        >
          <Plus className="w-4 h-4 mr-2" />
          Add Service
        </Button>
      </div>
    </Modal>
  );
};

export { ReverseProxyConfiguration };
export default ReverseProxyConfiguration;
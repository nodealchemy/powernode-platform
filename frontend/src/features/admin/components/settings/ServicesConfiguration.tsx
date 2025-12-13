import React, { useState, useEffect, useCallback } from 'react';
import { FlexBetween, FlexItemsCenter } from '@/shared/components/ui/FlexContainer';
import { GridCols2 } from '@/shared/components/ui/GridContainer';
import { Button } from '@/shared/components/ui/Button';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { StatusIndicator } from '@/shared/components/ui/StatusIndicator';
import { TabContainer } from '@/shared/components/ui/TabContainer';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { servicesApi, ServiceConfig, URLMapping, HealthStatus, ServiceDiscoveryConfig } from '../../services/servicesApi';
import { URLMappingModal } from './URLMappingModal';
import { TestConfigurationModal } from './TestConfigurationModal';
import { ExportConfigurationModal } from './ExportConfigurationModal';
import { ServiceDiscoveryModal } from './ServiceDiscoveryModal';
import { HealthMonitoringDashboard } from './HealthMonitoringDashboard';
import {
  BasicConfiguration,
  ServicesListComponent,
  URLMappingsConfiguration,
  AdvancedConfiguration
} from './services-config';
import {
  Settings,
  Globe,
  Server,
  Shield,
  Zap,
  Activity,
  Download,
  TestTube,
  RefreshCw,
  AlertTriangle
} from 'lucide-react';

interface ServicesConfigurationProps {
  className?: string;
}

type TabType = 'basic' | 'services' | 'mappings' | 'advanced' | 'monitoring' | 'discovery';

export const ServicesConfiguration: React.FC<ServicesConfigurationProps> = ({ className = '' }) => {
  const { showNotification } = useNotifications();
  const [activeTab, setActiveTab] = useState<TabType>('basic');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [config, setConfig] = useState<ServiceConfig | null>(null);
  const [healthStatus, setHealthStatus] = useState<HealthStatus | null>(null);
  const [hasChanges, setHasChanges] = useState(false);

  // Modal states
  const [showURLMappingModal, setShowURLMappingModal] = useState(false);
  const [showTestModal, setShowTestModal] = useState(false);
  const [showExportModal, setShowExportModal] = useState(false);
  const [showServiceDiscoveryModal, setShowServiceDiscoveryModal] = useState(false);
  const [editingMapping, setEditingMapping] = useState<URLMapping | null>(null);
  const [serviceDiscoveryConfig, setServiceDiscoveryConfig] = useState<ServiceDiscoveryConfig | null>(null);

  const loadConfiguration = useCallback(async () => {
    try {
      setLoading(true);
      const data = await servicesApi.getConfiguration();
      setConfig(data.service_config);
      setHealthStatus(data.health_status);
      setServiceDiscoveryConfig(data.service_discovery_config);
    } catch {
      showNotification('Failed to load services configuration', 'error');
    } finally {
      setLoading(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const refreshHealthStatus = useCallback(async () => {
    try {
      const health = await servicesApi.getDetailedHealthStatus();
      setHealthStatus(health);
    } catch {
      showNotification('Failed to refresh health status', 'error');
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    loadConfiguration();
  }, [loadConfiguration]);

  // Auto-refresh health status every 30 seconds
  useEffect(() => {
    if (!config?.enabled) return;
    // Temporarily disabled to debug page refresh issues
  }, [config?.enabled, refreshHealthStatus]);

  const updateServiceDiscoveryConfig = async (newConfig: ServiceDiscoveryConfig) => {
    try {
      await servicesApi.updateConfiguration('service_discovery_config', newConfig);
      setServiceDiscoveryConfig(newConfig);
      showNotification('Service discovery configuration updated successfully', 'success');
    } catch (error) {
      showNotification('Failed to update service discovery configuration', 'error');
      throw error;
    }
  };

  const saveConfiguration = async () => {
    if (!config) return;

    try {
      setSaving(true);
      await servicesApi.updateConfiguration('service_config', config);
      setHasChanges(false);
      showNotification('Services configuration saved successfully', 'success');
    } catch {
      showNotification('Failed to save configuration', 'error');
    } finally {
      setSaving(false);
    }
  };

  const testConfiguration = () => {
    setShowTestModal(true);
  };

  const updateConfig = (updates: Partial<ServiceConfig>) => {
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
      await servicesApi.toggleURLMapping(mappingId, !mapping.enabled);

      const updatedMappings = config.url_mappings.map(m =>
        m.id === mappingId ? { ...m, enabled: !m.enabled } : m
      );

      updateConfig({ url_mappings: updatedMappings });
      showNotification(`URL mapping ${!mapping.enabled ? 'enabled' : 'disabled'}`, 'success');
    } catch {
      showNotification('Failed to toggle URL mapping', 'error');
    }
  };

  const deleteURLMapping = async (mappingId: string) => {
    if (!config) return;

    try {
      await servicesApi.deleteURLMapping(mappingId);

      const updatedMappings = config.url_mappings.filter(m => m.id !== mappingId);
      updateConfig({ url_mappings: updatedMappings });
      showNotification('URL mapping deleted successfully', 'success');
    } catch {
      showNotification('Failed to delete URL mapping', 'error');
    }
  };

  const handleSaveURLMapping = async (mapping: URLMapping) => {
    if (!config) return;

    try {
      if (editingMapping) {
        // Update existing mapping
        await servicesApi.updateURLMapping(mapping.id, mapping);
        const updatedMappings = config.url_mappings.map(m =>
          m.id === mapping.id ? mapping : m
        );
        updateConfig({ url_mappings: updatedMappings });
      } else {
        // Create new mapping
        const response = await servicesApi.createURLMapping(mapping);
        const newMapping = response.mapping;
        updateConfig({
          url_mappings: [...config.url_mappings, newMapping]
        });
      }

      setShowURLMappingModal(false);
      setEditingMapping(null);
    } catch (error) {
      throw error; // Re-throw to let modal handle the error
    }
  };

  const getAvailableServices = (): string[] => {
    if (!config) return [];
    const currentEnv = config.current_environment || 'development';
    return Object.keys(config.environments[currentEnv] || {});
  };

  if (loading) {
    return (
      <FlexItemsCenter justify="center" className="py-12">
        <LoadingSpinner size="lg" />
        <span className="ml-3 text-theme-secondary">Loading services configuration...</span>
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
          Unable to load services configuration.
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
          <h2 className="text-xl font-semibold text-theme-primary">Services Configuration</h2>
          <p className="text-theme-secondary">
            Configure service routing, load balancing, and discovery
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
            {Object.entries(healthStatus.services).map(([serviceName, service]) => (
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
            ))}
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
              <ServicesListComponent
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

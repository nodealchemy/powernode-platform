import React, { useState } from 'react';
import { FlexBetween, FlexItemsCenter } from '@/shared/components/ui/FlexContainer';
import { Button } from '@/shared/components/ui/Button';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { StatusIndicator } from '@/shared/components/ui/StatusIndicator';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { servicesApi } from '../../../services/servicesApi';
import { AddServiceModal } from './AddServiceModal';
import {
  Server,
  Download,
  Plus,
  Trash2,
  Activity,
  Settings,
  Copy,
  XCircle,
  Save,
  Zap
} from 'lucide-react';
import type { ServicesListComponentProps, ServiceTemplate, NewServiceConfig } from './types';

// Service templates for quick setup
const SERVICE_TEMPLATES: ServiceTemplate[] = [
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
    name: 'External Load Balancer',
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

const AVAILABLE_ENVIRONMENTS = ['development', 'staging', 'production'];

export const ServicesListComponent: React.FC<ServicesListComponentProps> = ({
  config,
  updateConfig,
  healthStatus
}) => {
  const { showNotification } = useNotifications();
  const [selectedEnvironment, setSelectedEnvironment] = useState(config.current_environment);
  const [showAddServiceModal, setShowAddServiceModal] = useState(false);
  const [editingService, setEditingService] = useState<string | null>(null);
  const [showServiceTemplates, setShowServiceTemplates] = useState(false);

  const currentEnvServices = config.environments[selectedEnvironment] || {};

  const updateServiceConfig = (
    serviceName: string,
    updates: Partial<{ host: string; port: number; protocol: string; health_check_path: string }>
  ) => {
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

  const addService = (name: string, serviceConfig: NewServiceConfig) => {
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
      const result = await servicesApi.testServiceConnection(selectedEnvironment, serviceName);

      if (result.status === 'healthy') {
        showNotification(`${serviceName} is healthy (${result.response_time}ms)`, 'success');
      } else if (result.status === 'unhealthy') {
        showNotification(`${serviceName} returned HTTP ${result.response_code}`, 'warning');
      } else {
        showNotification(`${serviceName} is unreachable: ${result.error}`, 'error');
      }
    } catch {
      showNotification(`Failed to test ${serviceName}`, 'error');
    }
  };

  const importServicesFromTemplate = () => {
    const defaultServices = SERVICE_TEMPLATES.reduce((acc, template) => {
      const serviceName = template.type;
      if (!currentEnvServices[serviceName]) {
        acc[serviceName] = template.config;
      }
      return acc;
    }, {} as Record<string, ServiceTemplate['config']>);

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
              {AVAILABLE_ENVIRONMENTS.map((env) => (
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
            Add services to configure routing for the {selectedEnvironment} environment
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
                  <FlexItemsCenter gap="sm">
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
                  </FlexItemsCenter>
                  <FlexItemsCenter gap="xs">
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
                  </FlexItemsCenter>
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

                    {/* Save Actions */}
                    <div className="flex justify-end space-x-3 pt-4 border-t border-theme">
                      <Button
                        onClick={() => setEditingService(null)}
                        variant="secondary"
                        size="sm"
                      >
                        Cancel
                      </Button>
                      <Button
                        onClick={async () => {
                          try {
                            await servicesApi.updateConfiguration('service_config', config);
                            showNotification('Service configuration saved successfully', 'success');
                            setEditingService(null);
                          } catch {
                            showNotification('Failed to save service configuration', 'error');
                          }
                        }}
                        variant="primary"
                        size="sm"
                      >
                        <Save className="w-4 h-4 mr-2" />
                        Save Changes
                      </Button>
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
                          {AVAILABLE_ENVIRONMENTS.filter(env => env !== selectedEnvironment).map(env => (
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
              {SERVICE_TEMPLATES.map((template) => (
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
      <AddServiceModal
        isOpen={showAddServiceModal}
        onClose={() => setShowAddServiceModal(false)}
        onAddService={addService}
        existingServices={Object.keys(currentEnvServices)}
        templates={SERVICE_TEMPLATES}
      />
    </div>
  );
};

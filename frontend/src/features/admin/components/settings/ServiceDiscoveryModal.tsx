import React, { useState, useEffect } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { FlexBetween, FlexItemsCenter } from '@/shared/components/ui/FlexContainer';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { servicesApi, ServiceDiscoveryConfig } from '../../services/servicesApi';
import { JobProgressModal } from './JobProgressModal';
import { 
  Search, 
  Server,
  CheckCircle,
  XCircle,
  AlertTriangle,
  RefreshCw,
  Settings,
  Network,
  Cpu,
  Globe
} from 'lucide-react';

interface ServiceDiscoveryModalProps {
  isOpen: boolean;
  onClose: () => void;
  config: ServiceDiscoveryConfig;
  onConfigUpdate: (config: ServiceDiscoveryConfig) => Promise<void>;
}

interface DiscoveredService {
  name: string;
  host: string;
  port: number;
  protocol: string;
  health_check_path: string;
  status: 'healthy' | 'unhealthy' | 'unreachable';
  discovered_method: string;
  last_seen: string;
}

export const ServiceDiscoveryModal: React.FC<ServiceDiscoveryModalProps> = ({
  isOpen,
  onClose,
  config,
  onConfigUpdate
}) => {
  const { showNotification } = useNotifications();
  const [discovering, setDiscovering] = useState(false);
  const [discoveredServices, setDiscoveredServices] = useState<DiscoveredService[]>([]);
  const [activeTab, setActiveTab] = useState<'config' | 'discovered'>('config');
  const [formConfig, setFormConfig] = useState<ServiceDiscoveryConfig>(config);
  const [jobId, setJobId] = useState<string | null>(null);
  const [showJobProgress, setShowJobProgress] = useState(false);

  useEffect(() => {
    if (isOpen) {
      setFormConfig(config);
      loadDiscoveredServices();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isOpen, config]);

  const loadDiscoveredServices = async () => {
    try {
      const services = await servicesApi.getDiscoveredServices();
      setDiscoveredServices(services);
    } catch (error) {
      showNotification('Failed to load discovered services', 'error');
    }
  };

  const runServiceDiscovery = async () => {
    try {
      setDiscovering(true);
      const result = await servicesApi.runServiceDiscovery();
      
      // Start job progress tracking
      setJobId(result.job_id);
      setShowJobProgress(true);
      showNotification('Service discovery started', 'info');
      setDiscovering(false);
    } catch (error) {
      showNotification('Failed to start service discovery', 'error');
      setDiscovering(false);
    }
  };

  const handleJobComplete = (result: unknown) => {
    const discoveryResult = result as { services?: any[]; services_count?: number };
    if (discoveryResult && discoveryResult.services) {
      setDiscoveredServices(discoveryResult.services);
      setActiveTab('discovered');
    }
    setShowJobProgress(false);
    showNotification(`Service discovery completed: ${discoveryResult?.services_count || 0} services discovered`, 'success');
    loadDiscoveredServices(); // Refresh the list
  };

  const handleJobError = (error: string) => {
    setShowJobProgress(false);
    showNotification(error || 'Service discovery failed', 'error');
  };

  const handleConfigSave = async () => {
    try {
      await onConfigUpdate(formConfig);
      showNotification('Service discovery configuration updated', 'success');
      onClose();
    } catch (error) {
      showNotification('Failed to update configuration', 'error');
    }
  };

  const updateFormConfig = (field: string, value: string | number | boolean | string[]) => {
    setFormConfig(prev => ({ ...prev, [field]: value }));
  };

  const updateNestedConfig = (section: keyof ServiceDiscoveryConfig, field: string, value: any) => {
    setFormConfig(prev => ({
      ...prev,
      [section]: {
        ...(prev[section] as any),
        [field]: value
      }
    }));
  };

  const addServiceToConfig = async (service: DiscoveredService) => {
    try {
      await servicesApi.addDiscoveredService(service);
      showNotification(`Added ${service.name} to configuration`, 'success');
      loadDiscoveredServices();
    } catch (error) {
      showNotification('Failed to add service to configuration', 'error');
    }
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'healthy':
        return <CheckCircle className="w-4 h-4 text-theme-success" />;
      case 'unhealthy':
        return <AlertTriangle className="w-4 h-4 text-theme-warning" />;
      case 'unreachable':
        return <XCircle className="w-4 h-4 text-theme-danger" />;
      default:
        return <Server className="w-4 h-4 text-theme-secondary" />;
    }
  };

  const getStatusBadgeVariant = (status: string) => {
    switch (status) {
      case 'healthy': return 'success';
      case 'unhealthy': return 'warning';
      case 'unreachable': return 'danger';
      default: return 'secondary';
    }
  };

  const getDiscoveryMethodIcon = (method: string) => {
    switch (method) {
      case 'dns':
        return <Globe className="w-4 h-4 text-theme-primary" />;
      case 'consul':
        return <Network className="w-4 h-4 text-theme-primary" />;
      case 'port_scan':
        return <Cpu className="w-4 h-4 text-theme-primary" />;
      case 'kubernetes':
        return <Server className="w-4 h-4 text-theme-primary" />;
      default:
        return <Search className="w-4 h-4 text-theme-primary" />;
    }
  };

  return (
    <>
      <Modal
        isOpen={isOpen}
        onClose={onClose}
        title="Service Discovery & Health Monitoring"
        maxWidth="2xl"
      >
      <div className="space-y-6">
        {/* Tab Navigation */}
        <div className="flex space-x-1 bg-theme-surface rounded-lg p-1">
          <Button
            onClick={() => setActiveTab('config')}
            variant={activeTab === 'config' ? 'primary' : 'secondary'}
            size="sm"
            className="flex-1"
          >
            <Settings className="w-4 h-4 mr-2" />
            Configuration
          </Button>
          <Button
            onClick={() => setActiveTab('discovered')}
            variant={activeTab === 'discovered' ? 'primary' : 'secondary'}
            size="sm"
            className="flex-1"
          >
            <Search className="w-4 h-4 mr-2" />
            Discovered Services
          </Button>
        </div>

        {/* Configuration Tab */}
        {activeTab === 'config' && (
          <div className="space-y-6">
            {/* Enable Service Discovery */}
            <Card className="p-4">
              <FlexBetween className="mb-4">
                <div>
                  <h3 className="text-lg font-medium text-theme-primary">Service Discovery</h3>
                  <p className="text-sm text-theme-secondary">
                    Automatically discover and monitor services in your environment
                  </p>
                </div>
                <Button
                  onClick={() => updateFormConfig('enabled', !formConfig.enabled)}
                  variant={formConfig.enabled ? 'success' : 'secondary'}
                  size="sm"
                >
                  {formConfig.enabled ? 'Enabled' : 'Disabled'}
                </Button>
              </FlexBetween>

              {formConfig.enabled && (
                <div>
                  <h4 className="text-sm font-medium text-theme-primary mb-3">Discovery Methods</h4>
                  <div className="grid grid-cols-2 gap-3">
                    {['dns', 'consul', 'port_scan', 'kubernetes'].map((method) => (
                      <Button
                        key={method}
                        onClick={() => {
                          const methods = formConfig.methods.includes(method)
                            ? formConfig.methods.filter(m => m !== method)
                            : [...formConfig.methods, method];
                          updateFormConfig('methods', methods);
                        }}
                        variant={formConfig.methods.includes(method) ? 'primary' : 'secondary'}
                        size="sm"
                        className="justify-start"
                      >
                        {getDiscoveryMethodIcon(method)}
                        <span className="ml-2 capitalize">{method.replace('_', ' ')}</span>
                      </Button>
                    ))}
                  </div>
                </div>
              )}
            </Card>

            {/* DNS Configuration */}
            {formConfig.enabled && formConfig.methods.includes('dns') && (
              <Card className="p-4">
                <h4 className="text-sm font-medium text-theme-primary mb-3 flex items-center">
                  <Globe className="w-4 h-4 mr-2" />
                  DNS Discovery Configuration
                </h4>
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className="block text-sm font-medium text-theme-primary mb-2">
                      Timeout (seconds)
                    </label>
                    <input
                      type="number"
                      value={formConfig.dns_config.timeout}
                      onChange={(e) => updateNestedConfig('dns_config', 'timeout', parseInt(e.target.value))}
                      className="w-full p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                      min="1"
                      max="60"
                    />
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-theme-primary mb-2">
                      Retries
                    </label>
                    <input
                      type="number"
                      value={formConfig.dns_config.retries}
                      onChange={(e) => updateNestedConfig('dns_config', 'retries', parseInt(e.target.value))}
                      className="w-full p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                      min="1"
                      max="10"
                    />
                  </div>
                </div>
              </Card>
            )}

            {/* Consul Configuration */}
            {formConfig.enabled && formConfig.methods.includes('consul') && (
              <Card className="p-4">
                <h4 className="text-sm font-medium text-theme-primary mb-3 flex items-center">
                  <Network className="w-4 h-4 mr-2" />
                  Consul Configuration
                </h4>
                <div className="grid grid-cols-2 gap-4 mb-4">
                  <div>
                    <label className="block text-sm font-medium text-theme-primary mb-2">
                      Host
                    </label>
                    <input
                      type="text"
                      value={formConfig.consul_config.host}
                      onChange={(e) => updateNestedConfig('consul_config', 'host', e.target.value)}
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
                      value={formConfig.consul_config.port}
                      onChange={(e) => updateNestedConfig('consul_config', 'port', parseInt(e.target.value))}
                      className="w-full p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                      min="1"
                      max="65535"
                    />
                  </div>
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className="block text-sm font-medium text-theme-primary mb-2">
                      Token (Optional)
                    </label>
                    <input
                      type="password"
                      value={formConfig.consul_config.token || ''}
                      onChange={(e) => updateNestedConfig('consul_config', 'token', e.target.value || null)}
                      className="w-full p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                      placeholder="Optional ACL token"
                    />
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-theme-primary mb-2">
                      Datacenter
                    </label>
                    <input
                      type="text"
                      value={formConfig.consul_config.datacenter}
                      onChange={(e) => updateNestedConfig('consul_config', 'datacenter', e.target.value)}
                      className="w-full p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                      placeholder="dc1"
                    />
                  </div>
                </div>
              </Card>
            )}

            {/* Port Scan Configuration */}
            {formConfig.enabled && formConfig.methods.includes('port_scan') && (
              <Card className="p-4">
                <h4 className="text-sm font-medium text-theme-primary mb-3 flex items-center">
                  <Cpu className="w-4 h-4 mr-2" />
                  Port Scan Configuration
                </h4>
                <div className="space-y-3">
                  <div>
                    <label className="block text-sm font-medium text-theme-primary mb-2">
                      Timeout (seconds)
                    </label>
                    <input
                      type="number"
                      value={formConfig.port_scan_config.timeout}
                      onChange={(e) => updateNestedConfig('port_scan_config', 'timeout', parseInt(e.target.value))}
                      className="w-full p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                      min="1"
                      max="30"
                    />
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-theme-primary mb-2">
                      Port Ranges (Service: Start-End)
                    </label>
                    <div className="space-y-2">
                      {Object.entries(formConfig.port_scan_config.port_ranges).map(([service, [start, end]]) => (
                        <div key={service} className="flex items-center space-x-2">
                          <span className="text-sm text-theme-secondary w-20">{service}:</span>
                          <input
                            type="number"
                            value={start}
                            onChange={(e) => {
                              const newRanges = { ...formConfig.port_scan_config.port_ranges };
                              newRanges[service] = [parseInt(e.target.value), end];
                              updateNestedConfig('port_scan_config', 'port_ranges', newRanges);
                            }}
                            className="flex-1 p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                            min="1"
                            max="65535"
                          />
                          <span className="text-theme-secondary">-</span>
                          <input
                            type="number"
                            value={end}
                            onChange={(e) => {
                              const newRanges = { ...formConfig.port_scan_config.port_ranges };
                              newRanges[service] = [start, parseInt(e.target.value)];
                              updateNestedConfig('port_scan_config', 'port_ranges', newRanges);
                            }}
                            className="flex-1 p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                            min="1"
                            max="65535"
                          />
                        </div>
                      ))}
                    </div>
                  </div>
                </div>
              </Card>
            )}

            {/* Kubernetes Configuration */}
            {formConfig.enabled && formConfig.methods.includes('kubernetes') && (
              <Card className="p-4">
                <h4 className="text-sm font-medium text-theme-primary mb-3 flex items-center">
                  <Server className="w-4 h-4 mr-2" />
                  Kubernetes Configuration
                </h4>
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className="block text-sm font-medium text-theme-primary mb-2">
                      Namespace
                    </label>
                    <input
                      type="text"
                      value={formConfig.kubernetes_config.namespace}
                      onChange={(e) => updateNestedConfig('kubernetes_config', 'namespace', e.target.value)}
                      className="w-full p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                      placeholder="default"
                    />
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-theme-primary mb-2">
                      Label Selector
                    </label>
                    <input
                      type="text"
                      value={formConfig.kubernetes_config.label_selector}
                      onChange={(e) => updateNestedConfig('kubernetes_config', 'label_selector', e.target.value)}
                      className="w-full p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                      placeholder="app=service"
                    />
                  </div>
                </div>
              </Card>
            )}
          </div>
        )}

        {/* Discovered Services Tab */}
        {activeTab === 'discovered' && (
          <div className="space-y-4">
            {/* Discovery Controls */}
            <FlexBetween>
              <div>
                <h3 className="text-lg font-medium text-theme-primary">Discovered Services</h3>
                <p className="text-sm text-theme-secondary">
                  Services found through discovery methods
                </p>
              </div>
              <div className="flex space-x-2">
                <Button
                  onClick={loadDiscoveredServices}
                  variant="secondary"
                  size="sm"
                  disabled={discovering}
                >
                  <RefreshCw className="w-4 h-4 mr-2" />
                  Refresh
                </Button>
                <Button
                  onClick={runServiceDiscovery}
                  variant="primary"
                  size="sm"
                  disabled={discovering}
                >
                  {discovering ? (
                    <>
                      <LoadingSpinner size="sm" className="mr-2" />
                      Discovering...
                    </>
                  ) : (
                    <>
                      <Search className="w-4 h-4 mr-2" />
                      Run Discovery
                    </>
                  )}
                </Button>
              </div>
            </FlexBetween>

            {/* Services List */}
            <div className="space-y-3">
              {discoveredServices.length === 0 ? (
                <Card className="p-8 text-center">
                  <Search className="w-12 h-12 mx-auto mb-4 text-theme-secondary" />
                  <h3 className="text-lg font-medium text-theme-primary mb-2">
                    No Services Discovered
                  </h3>
                  <p className="text-theme-secondary">
                    Click "Run Discovery" to search for services in your environment
                  </p>
                </Card>
              ) : (
                discoveredServices.map((service, index) => (
                  <Card key={`${service.name}-${index}`} className="p-4">
                    <FlexBetween className="mb-3">
                      <FlexItemsCenter>
                        {getStatusIcon(service.status)}
                        <div className="ml-3">
                          <h4 className="font-medium text-theme-primary">{service.name}</h4>
                          <p className="text-sm text-theme-secondary">
                            {service.protocol}://{service.host}:{service.port}
                          </p>
                        </div>
                      </FlexItemsCenter>
                      <div className="flex items-center space-x-2">
                        <Badge variant={getStatusBadgeVariant(service.status)}>
                          {service.status}
                        </Badge>
                        <Button
                          onClick={() => addServiceToConfig(service)}
                          variant="primary"
                          size="sm"
                        >
                          Add to Config
                        </Button>
                      </div>
                    </FlexBetween>

                    <div className="grid grid-cols-3 gap-4 text-sm">
                      <div>
                        <span className="text-theme-secondary">Method: </span>
                        <span className="text-theme-primary capitalize">
                          {service.discovered_method.replace('_', ' ')}
                        </span>
                      </div>
                      <div>
                        <span className="text-theme-secondary">Health Path: </span>
                        <span className="text-theme-primary">{service.health_check_path}</span>
                      </div>
                      <div>
                        <span className="text-theme-secondary">Last Seen: </span>
                        <span className="text-theme-primary">
                          {new Date(service.last_seen).toLocaleTimeString()}
                        </span>
                      </div>
                    </div>
                  </Card>
                ))
              )}
            </div>
          </div>
        )}
      </div>

      {/* Modal Actions */}
      <div className="flex justify-between items-center pt-4 border-t border-theme">
        <div className="flex space-x-2">
          {activeTab === 'discovered' && (
            <Button
              onClick={runServiceDiscovery}
              variant="secondary"
              size="sm"
              disabled={discovering}
            >
              <RefreshCw className="w-4 h-4 mr-2" />
              Run Discovery
            </Button>
          )}
        </div>
        <div className="flex space-x-3">
          <Button
            onClick={onClose}
            variant="secondary"
          >
            Cancel
          </Button>
          {activeTab === 'config' && (
            <Button
              onClick={handleConfigSave}
              variant="primary"
            >
              Save Configuration
            </Button>
          )}
        </div>
      </div>
    </Modal>

      {/* Job Progress Modal */}
      {jobId && (
        <JobProgressModal
          isOpen={showJobProgress}
          onClose={() => setShowJobProgress(false)}
          jobId={jobId}
          jobType="services_service_discovery"
          title="Running Service Discovery"
          onComplete={handleJobComplete}
          onError={handleJobError}
        />
      )}
    </>
  );
};
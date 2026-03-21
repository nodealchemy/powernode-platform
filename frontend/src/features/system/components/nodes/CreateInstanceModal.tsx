import React, { useState, useEffect, useCallback } from 'react';
import { Cpu, Cloud, Server, Zap, Loader2 } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { systemApi } from '@/features/system/services/systemApi';
import type {
  SystemNode,
  SystemNodeInstance,
  SystemProviderConnection,
  SystemProviderRegion,
  SystemProviderInstanceType,
  SystemProviderAvailabilityZone,
  SystemProviderNetwork,
  SystemProviderNetworkSubnet
} from '@/features/system/types/system.types';

interface CreateInstanceModalProps {
  /** The node to create an instance for */
  node: SystemNode | null;
  /** Whether the modal is open */
  isOpen: boolean;
  /** Callback when modal is closed */
  onClose: () => void;
  /** Callback when instance is created successfully */
  onInstanceCreated?: (instance: SystemNodeInstance) => void;
}

interface FormData {
  name: string;
  variety: 'cloud' | 'physical' | 'dynamic';
  private_ip_address: string;
  public_ip_address: string;
  vpn_ip_address: string;
  // Cloud-specific fields
  provider_connection_id: string;
  provider_region_id: string;
  provider_instance_type_id: string;
  provider_availability_zone_id: string;
  provider_network_id: string;
  provider_network_subnet_id: string;
}

interface FormErrors {
  name?: string;
  variety?: string;
  provider_connection_id?: string;
  provider_region_id?: string;
  provider_instance_type_id?: string;
}

/**
 * CreateInstanceModal - Modal for creating new node instances
 *
 * Provides a form to create instances with name, variety,
 * cloud provider configuration (cascading selects), and IP address settings.
 */
export const CreateInstanceModal: React.FC<CreateInstanceModalProps> = ({
  node,
  isOpen,
  onClose,
  onInstanceCreated
}) => {
  const { addNotification } = useNotifications();

  // State
  const [submitting, setSubmitting] = useState(false);
  const [formData, setFormData] = useState<FormData>({
    name: '',
    variety: 'cloud',
    private_ip_address: '',
    public_ip_address: '',
    vpn_ip_address: '',
    provider_connection_id: '',
    provider_region_id: '',
    provider_instance_type_id: '',
    provider_availability_zone_id: '',
    provider_network_id: '',
    provider_network_subnet_id: ''
  });
  const [errors, setErrors] = useState<FormErrors>({});

  // Cascading dropdown data
  const [connections, setConnections] = useState<SystemProviderConnection[]>([]);
  const [regions, setRegions] = useState<SystemProviderRegion[]>([]);
  const [instanceTypes, setInstanceTypes] = useState<SystemProviderInstanceType[]>([]);
  const [availabilityZones, setAvailabilityZones] = useState<SystemProviderAvailabilityZone[]>([]);
  const [networks, setNetworks] = useState<SystemProviderNetwork[]>([]);
  const [subnets, setSubnets] = useState<SystemProviderNetworkSubnet[]>([]);

  // Loading states for cascading selects
  const [loadingConnections, setLoadingConnections] = useState(false);
  const [loadingRegions, setLoadingRegions] = useState(false);
  const [loadingInstanceTypes, setLoadingInstanceTypes] = useState(false);
  const [loadingZones, setLoadingZones] = useState(false);
  const [loadingNetworks, setLoadingNetworks] = useState(false);
  const [loadingSubnets, setLoadingSubnets] = useState(false);

  // Reset form when modal opens
  useEffect(() => {
    if (isOpen && node) {
      setFormData({
        name: `${node.name}-instance-${Date.now().toString(36).slice(-4)}`,
        variety: 'cloud',
        private_ip_address: '',
        public_ip_address: '',
        vpn_ip_address: '',
        provider_connection_id: '',
        provider_region_id: '',
        provider_instance_type_id: '',
        provider_availability_zone_id: '',
        provider_network_id: '',
        provider_network_subnet_id: ''
      });
      setErrors({});
      setRegions([]);
      setInstanceTypes([]);
      setAvailabilityZones([]);
      setNetworks([]);
      setSubnets([]);
    }
  }, [isOpen, node]);

  // Load provider connections on modal open
  useEffect(() => {
    if (isOpen && formData.variety === 'cloud') {
      setLoadingConnections(true);
      systemApi.getProviderConnections()
        .then(setConnections)
        .catch(() => setConnections([]))
        .finally(() => setLoadingConnections(false));
    }
  }, [isOpen, formData.variety]);

  // Load regions when connection changes
  useEffect(() => {
    if (formData.provider_connection_id) {
      const connection = connections.find(c => c.id === formData.provider_connection_id);
      if (connection?.provider_id) {
        setLoadingRegions(true);
        systemApi.getProviderRegions(connection.provider_id)
          .then(setRegions)
          .catch(() => setRegions([]))
          .finally(() => setLoadingRegions(false));
      }
    } else {
      setRegions([]);
    }
    // Clear dependent fields
    setFormData(prev => ({
      ...prev,
      provider_region_id: '',
      provider_instance_type_id: '',
      provider_availability_zone_id: '',
      provider_network_id: '',
      provider_network_subnet_id: ''
    }));
    setInstanceTypes([]);
    setAvailabilityZones([]);
    setNetworks([]);
    setSubnets([]);
  }, [formData.provider_connection_id, connections]);

  // Load instance types, zones, and networks when region changes
  useEffect(() => {
    if (formData.provider_region_id) {
      const connection = connections.find(c => c.id === formData.provider_connection_id);
      if (connection?.provider_id) {
        // Load instance types for provider
        setLoadingInstanceTypes(true);
        systemApi.getProviderInstanceTypes(connection.provider_id)
          .then(setInstanceTypes)
          .catch(() => setInstanceTypes([]))
          .finally(() => setLoadingInstanceTypes(false));

        // Load availability zones for region
        setLoadingZones(true);
        systemApi.getProviderAvailabilityZones(connection.provider_id, formData.provider_region_id)
          .then(setAvailabilityZones)
          .catch(() => setAvailabilityZones([]))
          .finally(() => setLoadingZones(false));

        // Load networks for region
        setLoadingNetworks(true);
        systemApi.getNetworks({ provider_region_id: formData.provider_region_id })
          .then(result => setNetworks(result.networks))
          .catch(() => setNetworks([]))
          .finally(() => setLoadingNetworks(false));
      }
    } else {
      setInstanceTypes([]);
      setAvailabilityZones([]);
      setNetworks([]);
    }
    // Clear dependent fields
    setFormData(prev => ({
      ...prev,
      provider_instance_type_id: '',
      provider_availability_zone_id: '',
      provider_network_id: '',
      provider_network_subnet_id: ''
    }));
    setSubnets([]);
  }, [formData.provider_region_id, formData.provider_connection_id, connections]);

  // Load subnets when network or zone changes
  useEffect(() => {
    if (formData.provider_network_id) {
      setLoadingSubnets(true);
      systemApi.getNetworkSubnets(formData.provider_network_id, formData.provider_availability_zone_id || undefined)
        .then(setSubnets)
        .catch(() => setSubnets([]))
        .finally(() => setLoadingSubnets(false));
    } else {
      setSubnets([]);
    }
    setFormData(prev => ({ ...prev, provider_network_subnet_id: '' }));
  }, [formData.provider_network_id, formData.provider_availability_zone_id]);

  // Form validation
  const validate = useCallback((): boolean => {
    const newErrors: FormErrors = {};

    if (!formData.name.trim()) {
      newErrors.name = 'Name is required';
    } else if (formData.name.length < 3) {
      newErrors.name = 'Name must be at least 3 characters';
    } else if (formData.name.length > 100) {
      newErrors.name = 'Name must be less than 100 characters';
    } else if (!/^[a-zA-Z0-9][a-zA-Z0-9\-_.]*$/.test(formData.name)) {
      newErrors.name = 'Name must start with alphanumeric and contain only letters, numbers, hyphens, underscores, and dots';
    }

    if (!formData.variety) {
      newErrors.variety = 'Instance type is required';
    }

    // Cloud-specific validation
    if (formData.variety === 'cloud') {
      if (!formData.provider_connection_id) {
        newErrors.provider_connection_id = 'Provider connection is required for cloud instances';
      }
      if (!formData.provider_region_id) {
        newErrors.provider_region_id = 'Region is required for cloud instances';
      }
      if (!formData.provider_instance_type_id) {
        newErrors.provider_instance_type_id = 'Instance type is required for cloud instances';
      }
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  }, [formData]);

  // Handle field change
  const handleChange = useCallback((field: keyof FormData, value: string) => {
    setFormData(prev => ({ ...prev, [field]: value }));
    // Clear error when field is edited
    if (errors[field as keyof FormErrors]) {
      setErrors(prev => ({ ...prev, [field]: undefined }));
    }
  }, [errors]);

  // Handle form submission
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!validate() || !node) {
      return;
    }

    setSubmitting(true);

    try {
      const instanceData: Parameters<typeof systemApi.createNodeInstance>[1] = {
        name: formData.name.trim(),
        variety: formData.variety,
        private_ip_address: formData.private_ip_address.trim() || undefined,
        public_ip_address: formData.public_ip_address.trim() || undefined,
        vpn_ip_address: formData.vpn_ip_address.trim() || undefined,
        status: 'pending',
        config: {}
      };

      // Add cloud-specific config
      if (formData.variety === 'cloud') {
        instanceData.config = {
          provider_connection_id: formData.provider_connection_id,
          provider_region_id: formData.provider_region_id,
          provider_instance_type_id: formData.provider_instance_type_id,
          provider_availability_zone_id: formData.provider_availability_zone_id || undefined,
          provider_network_id: formData.provider_network_id || undefined,
          provider_network_subnet_id: formData.provider_network_subnet_id || undefined
        };
      }

      const instance = await systemApi.createNodeInstance(node.id, instanceData);

      addNotification({
        type: 'success',
        message: `Instance "${instance.name}" created successfully`
      });

      onInstanceCreated?.(instance);
      onClose();
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to create instance';
      addNotification({
        type: 'error',
        message: errorMessage
      });
    } finally {
      setSubmitting(false);
    }
  };

  const varietyIcon = {
    cloud: <Cloud className="w-4 h-4" />,
    physical: <Server className="w-4 h-4" />,
    dynamic: <Zap className="w-4 h-4" />
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Create Instance"
      subtitle={node ? `For node: ${node.name}` : undefined}
      icon={<Cpu className="w-6 h-6" />}
      size="xl"
      footer={
        <div className="flex items-center justify-end gap-3">
          <Button variant="ghost" onClick={onClose} disabled={submitting}>
            Cancel
          </Button>
          <Button
            variant="primary"
            onClick={handleSubmit}
            disabled={submitting}
          >
            {submitting ? 'Creating...' : 'Create Instance'}
          </Button>
        </div>
      }
    >
      <form onSubmit={handleSubmit} className="space-y-6">
        {/* Name Field */}
        <div>
          <label htmlFor="instance-name" className="block text-sm font-medium text-theme-primary mb-1">
            Name <span className="text-theme-danger">*</span>
          </label>
          <input
            id="instance-name"
            type="text"
            value={formData.name}
            onChange={(e) => handleChange('name', e.target.value)}
            placeholder="my-instance-01"
            className={`
              w-full px-3 py-2 rounded-lg border bg-theme-surface text-theme-primary
              placeholder-theme-secondary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary
              ${errors.name ? 'border-theme-danger' : 'border-theme'}
            `}
            disabled={submitting}
          />
          {errors.name && (
            <p className="mt-1 text-sm text-theme-danger">{errors.name}</p>
          )}
        </div>

        {/* Instance Type */}
        <div>
          <label htmlFor="instance-variety" className="block text-sm font-medium text-theme-primary mb-1">
            Instance Type <span className="text-theme-danger">*</span>
          </label>
          <div className="grid grid-cols-3 gap-3">
            {(['cloud', 'physical', 'dynamic'] as const).map((type) => (
              <button
                key={type}
                type="button"
                onClick={() => handleChange('variety', type)}
                className={`
                  flex items-center justify-center gap-2 px-4 py-3 rounded-lg border transition-colors
                  ${formData.variety === type
                    ? 'bg-theme-accent text-white border-theme-accent'
                    : 'bg-theme-surface text-theme-secondary border-theme hover:border-theme-accent/50'
                  }
                `}
                disabled={submitting}
              >
                {varietyIcon[type]}
                <span className="capitalize">{type}</span>
              </button>
            ))}
          </div>
          {errors.variety && (
            <p className="mt-1 text-sm text-theme-danger">{errors.variety}</p>
          )}
          <p className="mt-2 text-xs text-theme-secondary">
            {formData.variety === 'cloud' && 'Virtual machine hosted in a cloud provider'}
            {formData.variety === 'physical' && 'Physical hardware server'}
            {formData.variety === 'dynamic' && 'Dynamically provisioned instance'}
          </p>
        </div>

        {/* Cloud Provider Configuration - Cascading Selects */}
        {formData.variety === 'cloud' && (
          <div className="space-y-4 p-4 bg-theme-background rounded-lg border border-theme">
            <h3 className="text-sm font-medium text-theme-primary flex items-center gap-2">
              <Cloud className="w-4 h-4" />
              Cloud Provider Configuration
            </h3>

            {/* Provider Connection */}
            <div>
              <label htmlFor="provider-connection" className="block text-sm font-medium text-theme-secondary mb-1">
                Provider Connection <span className="text-theme-danger">*</span>
              </label>
              <div className="relative">
                <select
                  id="provider-connection"
                  value={formData.provider_connection_id}
                  onChange={(e) => handleChange('provider_connection_id', e.target.value)}
                  className={`
                    w-full px-3 py-2 rounded-lg border bg-theme-surface text-theme-primary
                    focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary
                    ${errors.provider_connection_id ? 'border-theme-danger' : 'border-theme'}
                  `}
                  disabled={submitting || loadingConnections}
                >
                  <option value="">Select a provider connection...</option>
                  {connections.map(conn => (
                    <option key={conn.id} value={conn.id}>
                      {conn.name} ({conn.provider_name})
                    </option>
                  ))}
                </select>
                {loadingConnections && (
                  <Loader2 className="absolute right-8 top-1/2 -translate-y-1/2 w-4 h-4 animate-spin text-theme-secondary" />
                )}
              </div>
              {errors.provider_connection_id && (
                <p className="mt-1 text-sm text-theme-danger">{errors.provider_connection_id}</p>
              )}
            </div>

            {/* Region */}
            <div>
              <label htmlFor="provider-region" className="block text-sm font-medium text-theme-secondary mb-1">
                Region <span className="text-theme-danger">*</span>
              </label>
              <div className="relative">
                <select
                  id="provider-region"
                  value={formData.provider_region_id}
                  onChange={(e) => handleChange('provider_region_id', e.target.value)}
                  className={`
                    w-full px-3 py-2 rounded-lg border bg-theme-surface text-theme-primary
                    focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary
                    ${errors.provider_region_id ? 'border-theme-danger' : 'border-theme'}
                  `}
                  disabled={submitting || !formData.provider_connection_id || loadingRegions}
                >
                  <option value="">Select a region...</option>
                  {regions.map(region => (
                    <option key={region.id} value={region.id}>
                      {region.name} ({region.region_code})
                    </option>
                  ))}
                </select>
                {loadingRegions && (
                  <Loader2 className="absolute right-8 top-1/2 -translate-y-1/2 w-4 h-4 animate-spin text-theme-secondary" />
                )}
              </div>
              {errors.provider_region_id && (
                <p className="mt-1 text-sm text-theme-danger">{errors.provider_region_id}</p>
              )}
            </div>

            {/* Instance Type */}
            <div>
              <label htmlFor="provider-instance-type" className="block text-sm font-medium text-theme-secondary mb-1">
                Instance Size <span className="text-theme-danger">*</span>
              </label>
              <div className="relative">
                <select
                  id="provider-instance-type"
                  value={formData.provider_instance_type_id}
                  onChange={(e) => handleChange('provider_instance_type_id', e.target.value)}
                  className={`
                    w-full px-3 py-2 rounded-lg border bg-theme-surface text-theme-primary
                    focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary
                    ${errors.provider_instance_type_id ? 'border-theme-danger' : 'border-theme'}
                  `}
                  disabled={submitting || !formData.provider_region_id || loadingInstanceTypes}
                >
                  <option value="">Select an instance size...</option>
                  {instanceTypes.map(type => (
                    <option key={type.id} value={type.id}>
                      {type.display_name || type.name}
                    </option>
                  ))}
                </select>
                {loadingInstanceTypes && (
                  <Loader2 className="absolute right-8 top-1/2 -translate-y-1/2 w-4 h-4 animate-spin text-theme-secondary" />
                )}
              </div>
              {errors.provider_instance_type_id && (
                <p className="mt-1 text-sm text-theme-danger">{errors.provider_instance_type_id}</p>
              )}
            </div>

            {/* Availability Zone */}
            <div>
              <label htmlFor="availability-zone" className="block text-sm font-medium text-theme-secondary mb-1">
                Availability Zone
              </label>
              <div className="relative">
                <select
                  id="availability-zone"
                  value={formData.provider_availability_zone_id}
                  onChange={(e) => handleChange('provider_availability_zone_id', e.target.value)}
                  className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                  disabled={submitting || !formData.provider_region_id || loadingZones}
                >
                  <option value="">Auto-select (any zone)</option>
                  {availabilityZones.filter(z => z.operational).map(zone => (
                    <option key={zone.id} value={zone.id}>
                      {zone.name} ({zone.zone_code}) - {zone.status}
                    </option>
                  ))}
                </select>
                {loadingZones && (
                  <Loader2 className="absolute right-8 top-1/2 -translate-y-1/2 w-4 h-4 animate-spin text-theme-secondary" />
                )}
              </div>
            </div>

            {/* Network */}
            <div>
              <label htmlFor="provider-network" className="block text-sm font-medium text-theme-secondary mb-1">
                Network
              </label>
              <div className="relative">
                <select
                  id="provider-network"
                  value={formData.provider_network_id}
                  onChange={(e) => handleChange('provider_network_id', e.target.value)}
                  className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                  disabled={submitting || !formData.provider_region_id || loadingNetworks}
                >
                  <option value="">Default network</option>
                  {networks.map(network => (
                    <option key={network.id} value={network.id}>
                      {network.name} ({network.cidr_block})
                    </option>
                  ))}
                </select>
                {loadingNetworks && (
                  <Loader2 className="absolute right-8 top-1/2 -translate-y-1/2 w-4 h-4 animate-spin text-theme-secondary" />
                )}
              </div>
            </div>

            {/* Subnet */}
            {formData.provider_network_id && (
              <div>
                <label htmlFor="provider-subnet" className="block text-sm font-medium text-theme-secondary mb-1">
                  Subnet
                </label>
                <div className="relative">
                  <select
                    id="provider-subnet"
                    value={formData.provider_network_subnet_id}
                    onChange={(e) => handleChange('provider_network_subnet_id', e.target.value)}
                    className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                    disabled={submitting || loadingSubnets}
                  >
                    <option value="">Auto-select subnet</option>
                    {subnets.map(subnet => (
                      <option key={subnet.id} value={subnet.id}>
                        {subnet.name} ({subnet.cidr_block}) {subnet.is_public ? '(Public)' : '(Private)'}
                      </option>
                    ))}
                  </select>
                  {loadingSubnets && (
                    <Loader2 className="absolute right-8 top-1/2 -translate-y-1/2 w-4 h-4 animate-spin text-theme-secondary" />
                  )}
                </div>
              </div>
            )}
          </div>
        )}

        {/* IP Addresses */}
        <div className="space-y-4">
          <h3 className="text-sm font-medium text-theme-primary">Network Configuration</h3>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            {/* Private IP */}
            <div>
              <label htmlFor="instance-private-ip" className="block text-sm font-medium text-theme-secondary mb-1">
                Private IP
              </label>
              <input
                id="instance-private-ip"
                type="text"
                value={formData.private_ip_address}
                onChange={(e) => handleChange('private_ip_address', e.target.value)}
                placeholder="10.0.0.1"
                className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-surface text-theme-primary placeholder-theme-secondary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary font-mono text-sm"
                disabled={submitting}
              />
            </div>

            {/* Public IP */}
            <div>
              <label htmlFor="instance-public-ip" className="block text-sm font-medium text-theme-secondary mb-1">
                Public IP
              </label>
              <input
                id="instance-public-ip"
                type="text"
                value={formData.public_ip_address}
                onChange={(e) => handleChange('public_ip_address', e.target.value)}
                placeholder="203.0.113.1"
                className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-surface text-theme-primary placeholder-theme-secondary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary font-mono text-sm"
                disabled={submitting}
              />
            </div>

            {/* VPN IP */}
            <div>
              <label htmlFor="instance-vpn-ip" className="block text-sm font-medium text-theme-secondary mb-1">
                VPN IP
              </label>
              <input
                id="instance-vpn-ip"
                type="text"
                value={formData.vpn_ip_address}
                onChange={(e) => handleChange('vpn_ip_address', e.target.value)}
                placeholder="172.16.0.1"
                className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-surface text-theme-primary placeholder-theme-secondary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary font-mono text-sm"
                disabled={submitting}
              />
            </div>
          </div>

          <p className="text-xs text-theme-secondary">
            {formData.variety === 'cloud'
              ? 'IP addresses are typically assigned automatically by the provider. Leave empty for automatic assignment.'
              : 'Specify IP addresses for this instance. Leave empty if not applicable.'}
          </p>
        </div>
      </form>
    </Modal>
  );
};

export default CreateInstanceModal;

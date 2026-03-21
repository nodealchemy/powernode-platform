// System Types for Powernode System Infrastructure Management

export interface SystemNode {
  id: string;
  name: string;
  description?: string;
  enabled: boolean;
  status?: string;
  public_address?: string;
  allocate_public_ip: boolean;
  config: Record<string, unknown>;
  node_template_id?: string;
  node_template_name?: string;
  worker_id?: string;
  instance_count?: number;
  created_at: string;
  updated_at: string;
}

export interface SystemNodeInstance {
  id: string;
  name: string;
  variety: 'cloud' | 'physical' | 'dynamic';
  status: string;
  private_ip_address?: string;
  public_ip_address?: string;
  vpn_ip_address?: string;
  config: Record<string, unknown>;
  node_id: string;
  node_name?: string;
  provider_region_id?: string;
  provider_instance_type_id?: string;
  created_at: string;
  updated_at: string;
}

export interface SystemNodeTemplate {
  id: string;
  name: string;
  description?: string;
  enabled: boolean;
  public: boolean;
  admin_user?: string;
  config: Record<string, unknown>;
  node_platform_id?: string;
  node_platform_name?: string;
  node_count?: number;
  created_at: string;
  updated_at: string;
}

export interface SystemNodePlatform {
  id: string;
  name: string;
  description?: string;
  enabled: boolean;
  public: boolean;
  build_script?: string;
  init_script?: string;
  sync_script?: string;
  node_architecture_id?: string;
  architecture_name?: string;
  template_count?: number;
  module_count?: number;
  created_at: string;
  updated_at: string;
}

export interface SystemNodeArchitecture {
  id: string;
  name: string;
  description?: string;
  kernel_options?: string;
  enabled: boolean;
  public: boolean;
  platform_count?: number;
  created_at: string;
  updated_at: string;
}

export interface SystemNodeScript {
  id: string;
  name: string;
  description?: string;
  variety: 'build' | 'init' | 'sync' | 'custom';
  data?: string;
  enabled: boolean;
  public: boolean;
  created_at: string;
  updated_at: string;
}

export interface SystemProvider {
  id: string;
  name: string;
  description?: string;
  provider_type: string;
  enabled: boolean;
  public: boolean;
  config: Record<string, unknown>;
  capabilities: Record<string, unknown>;
  region_count?: number;
  connection_count?: number;
  created_at: string;
  updated_at: string;
}

export interface SystemProviderRegion {
  id: string;
  name: string;
  description?: string;
  endpoint_url?: string;
  region_code?: string;
  capabilities: Record<string, unknown>;
  provider_id: string;
  provider_name?: string;
  zone_count?: number;
  instance_type_count?: number;
  created_at: string;
  updated_at: string;
}

export interface SystemProviderConnection {
  id: string;
  name: string;
  description?: string;
  endpoint_url?: string;
  config: Record<string, unknown>;
  provider_id: string;
  provider_name?: string;
  created_at: string;
  updated_at: string;
}

export interface SystemProviderInstanceType {
  id: string;
  name: string;
  description?: string;
  instance_type_code: string;
  vcpus?: number;
  memory_mb?: number;
  memory_gb?: number;
  storage_gb?: number;
  hourly_price?: number;
  enabled: boolean;
  specs: Record<string, unknown>;
  display_name?: string;
  provider_id: string;
  provider_name?: string;
  region_count?: number;
  created_at: string;
  updated_at: string;
}

export interface SystemProviderAvailabilityZone {
  id: string;
  name: string;
  zone_code: string;
  status: 'available' | 'impaired' | 'unavailable';
  enabled: boolean;
  capabilities: Record<string, unknown>;
  provider_region_id: string;
  region_name?: string;
  provider_name?: string;
  operational: boolean;
  created_at: string;
  updated_at: string;
}

export interface SystemProviderNetworkSubnet {
  id: string;
  name: string;
  description?: string;
  cidr_block?: string;
  status: string;
  is_public: boolean;
  enabled: boolean;
  config: Record<string, unknown>;
  provider_network_id: string;
  network_name?: string;
  provider_availability_zone_id?: string;
  availability_zone_name?: string;
  created_at: string;
  updated_at: string;
}

export interface SystemNodeModule {
  id: string;
  name: string;
  description?: string;
  variety: 'config' | 'instance' | 'subscription';
  enabled: boolean;
  public: boolean;
  priority: number;
  mask: Record<string, unknown>;
  file_spec: Record<string, unknown>;
  config: Record<string, unknown>;
  node_platform_id?: string;
  node_platform_name?: string;
  category_id?: string;
  category_name?: string;
  dependencies_count?: number;
  dependents_count?: number;
  assignments_count?: number;
  templates_count?: number;
  puppet_modules_count?: number;
  created_at: string;
  updated_at: string;
}

export interface SystemNodeModuleCategory {
  id: string;
  name: string;
  description?: string;
  parent_id?: string;
  parent_name?: string;
  depth: number;
  children_count?: number;
  module_count?: number;
  created_at: string;
  updated_at: string;
}

export interface SystemOperation {
  id: string;
  command: string;
  status: 'pending' | 'scheduled' | 'running' | 'complete' | 'failed' | 'aborted' | 'cancelled';
  description?: string;
  progress: number;
  exclusive: boolean;
  scheduled_at?: string;
  started_at?: string;
  completed_at?: string;
  error_message?: string;
  events: Array<Record<string, unknown>>;
  options: Record<string, unknown>;
  operable_type?: string;
  operable_id?: string;
  initiated_by_id?: string;
  initiated_by_name?: string;
  created_at: string;
  updated_at: string;
}

export interface SystemPuppetModule {
  id: string;
  name: string;
  description?: string;
  enabled: boolean;
  public: boolean;
  version?: string;
  author?: string;
  license?: string;
  source_url?: string;
  project_url?: string;
  forge_name?: string;
  dependencies: Array<{ name: string; version_requirement?: string }>;
  config: Record<string, unknown>;
  metadata: Record<string, unknown>;
  resource_count?: number;
  resource_types?: string[];
  assigned_modules_count?: number;
  created_at: string;
  updated_at: string;
}

export interface SystemPuppetResource {
  id: string;
  name: string;
  description?: string;
  resource_type: string;
  title?: string;
  path?: string;
  data?: string;
  enabled: boolean;
  exported: boolean;
  parameters: Record<string, unknown>;
  config: Record<string, unknown>;
  puppet_module_id: string;
  puppet_module_name?: string;
  resource_identifier?: string;
  created_at: string;
  updated_at: string;
}

export interface SystemProviderVolume {
  id: string;
  name: string;
  description?: string;
  size_gb: number;
  status: string;
  volume_type: string;
  device_name?: string;
  iops?: number;
  throughput?: number;
  encrypted: boolean;
  config: Record<string, unknown>;
  volume_type_id?: string;
  volume_type_name?: string;
  provider_region_id: string;
  provider_region_name?: string;
  region_name?: string;
  node_instance_id?: string;
  attached_instance_id?: string;
  snapshot_count?: number;
  created_at: string;
  updated_at: string;
}

export interface SystemProviderNetwork {
  id: string;
  name: string;
  description?: string;
  cidr_block?: string;
  status: string;
  is_default?: boolean;
  dns_support?: boolean;
  dns_hostnames?: boolean;
  config: Record<string, unknown>;
  provider_region_id?: string;
  provider_region_name?: string;
  region_name?: string;
  subnet_count?: number;
  created_at: string;
  updated_at: string;
}

// Overview Statistics Types
export interface SystemOverviewStats {
  nodes: {
    total: number;
    enabled: number;
    disabled: number;
  };
  instances: {
    total: number;
    running: number;
    stopped: number;
    pending: number;
  };
  templates: {
    total: number;
    public: number;
    private: number;
  };
  platforms: {
    total: number;
    enabled: number;
  };
  providers: {
    total: number;
    enabled: number;
    types: string[];
  };
  regions: {
    total: number;
  };
  modules: {
    total: number;
    enabled: number;
    by_variety: {
      config: number;
      instance: number;
      subscription: number;
    };
  };
  operations: {
    total: number;
    pending: number;
    running: number;
    completed: number;
    failed: number;
  };
  puppet: {
    modules: number;
    resources: number;
    assignments: number;
  };
  volumes: {
    total: number;
    total_size_gb: number;
  };
  networks: {
    total: number;
  };
}

export interface SystemRecentActivity {
  id: string;
  type: 'operation' | 'node' | 'instance' | 'module' | 'provider';
  action: string;
  description: string;
  status?: string;
  entity_name: string;
  entity_id: string;
  initiated_by?: string;
  timestamp: string;
}

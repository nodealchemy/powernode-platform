import { apiClient } from '@/shared/services/apiClient';
import type {
  SystemNode,
  SystemNodeInstance,
  SystemNodeTemplate,
  SystemNodePlatform,
  SystemNodeArchitecture,
  SystemNodeScript,
  SystemProvider,
  SystemProviderRegion,
  SystemProviderConnection,
  SystemProviderInstanceType,
  SystemProviderAvailabilityZone,
  SystemProviderNetworkSubnet,
  SystemNodeModule,
  SystemNodeModuleCategory,
  SystemOperation,
  SystemPuppetModule,
  SystemPuppetResource,
  SystemProviderVolume,
  SystemProviderNetwork,
  SystemOverviewStats,
  SystemRecentActivity,
} from '../types/system.types';

// Helper to extract data from API response
const extractData = <T>(response: { data: { data?: T } & T }): T => {
  return response.data.data || response.data;
};

export const systemApi = {
  // ============ Overview ============
  getOverviewStats: async (): Promise<SystemOverviewStats> => {
    // Fetch counts from multiple endpoints in parallel
    const [
      nodesRes,
      templatesRes,
      platformsRes,
      providersRes,
      modulesRes,
      operationsRes,
      puppetModulesRes,
    ] = await Promise.all([
      apiClient.get<any>('/system/nodes'),
      apiClient.get<any>('/system/node_templates'),
      apiClient.get<any>('/system/node_platforms'),
      apiClient.get<any>('/system/providers'),
      apiClient.get<any>('/system/node_modules'),
      apiClient.get<any>('/system/operations'),
      apiClient.get<any>('/system/puppet_modules'),
    ]);

    const nodes = extractData(nodesRes).nodes || [];
    const templates = extractData(templatesRes).node_templates || [];
    const platforms = extractData(platformsRes).node_platforms || [];
    const providers = extractData(providersRes).providers || [];
    const modules = extractData(modulesRes).node_modules || [];
    const operations = extractData(operationsRes).operations || [];
    const puppetModules = extractData(puppetModulesRes).puppet_modules || [];

    return {
      nodes: {
        total: nodes.length,
        enabled: nodes.filter((n: SystemNode) => n.enabled).length,
        disabled: nodes.filter((n: SystemNode) => !n.enabled).length,
      },
      instances: {
        total: nodes.reduce((sum: number, n: any) => sum + (n.instance_count || 0), 0),
        running: nodes.reduce((sum: number, n: any) => sum + (n.running_instances_count || 0), 0),
        stopped: 0, // Would need detailed status counts
        pending: 0,
      },
      templates: {
        total: templates.length,
        public: templates.filter((t: SystemNodeTemplate) => t.public).length,
        private: templates.filter((t: SystemNodeTemplate) => !t.public).length,
      },
      platforms: {
        total: platforms.length,
        enabled: platforms.filter((p: SystemNodePlatform) => p.enabled).length,
      },
      providers: {
        total: providers.length,
        enabled: providers.filter((p: SystemProvider) => p.enabled).length,
        types: [...new Set(providers.map((p: SystemProvider) => p.provider_type))] as string[],
      },
      regions: {
        total: providers.reduce((sum: number, p: SystemProvider) => sum + (p.region_count || 0), 0),
      },
      modules: {
        total: modules.length,
        enabled: modules.filter((m: SystemNodeModule) => m.enabled).length,
        by_variety: {
          config: modules.filter((m: SystemNodeModule) => m.variety === 'config').length,
          instance: modules.filter((m: SystemNodeModule) => m.variety === 'instance').length,
          subscription: modules.filter((m: SystemNodeModule) => m.variety === 'subscription').length,
        },
      },
      operations: {
        total: operations.length,
        pending: operations.filter((o: SystemOperation) => o.status === 'pending' || o.status === 'scheduled').length,
        running: operations.filter((o: SystemOperation) => o.status === 'running').length,
        completed: operations.filter((o: SystemOperation) => o.status === 'complete').length,
        failed: operations.filter((o: SystemOperation) => o.status === 'failed' || o.status === 'aborted').length,
      },
      puppet: {
        modules: puppetModules.length,
        resources: puppetModules.reduce((sum: number, p: SystemPuppetModule) => sum + (p.resource_count || 0), 0),
        assignments: puppetModules.reduce((sum: number, p: SystemPuppetModule) => sum + (p.assigned_modules_count || 0), 0),
      },
      volumes: {
        total: 0, // Would need volumes endpoint
        total_size_gb: 0,
      },
      networks: {
        total: 0, // Would need networks endpoint
      },
    };
  },

  getRecentActivity: async (limit: number = 10): Promise<SystemRecentActivity[]> => {
    // Get recent operations as activity
    const response = await apiClient.get<any>('/system/operations', {
      params: { per_page: limit },
    });
    const operations = extractData(response).operations || [];

    return operations.map((op: SystemOperation) => ({
      id: op.id,
      type: 'operation' as const,
      action: op.command,
      description: op.description || `Operation: ${op.command}`,
      status: op.status,
      entity_name: op.operable_type || 'System',
      entity_id: op.operable_id || op.id,
      initiated_by: op.initiated_by_name,
      timestamp: op.created_at,
    }));
  },

  // ============ Nodes ============
  getNodes: async (params?: { page?: number; per_page?: number; enabled?: boolean }): Promise<{ nodes: SystemNode[]; meta: any }> => {
    const response = await apiClient.get<any>('/system/nodes', { params });
    const data = extractData(response);
    return { nodes: data.nodes || [], meta: data.meta };
  },

  getNode: async (id: string): Promise<SystemNode> => {
    const response = await apiClient.get<any>(`/system/nodes/${id}`);
    return extractData(response).node;
  },

  createNode: async (data: {
    name: string;
    description?: string;
    enabled?: boolean;
    allocate_public_ip?: boolean;
    node_template_id?: string;
    config?: Record<string, unknown>;
  }): Promise<SystemNode> => {
    const response = await apiClient.post<any>('/system/nodes', { node: data });
    return extractData(response).node;
  },

  updateNode: async (id: string, data: Partial<{
    name: string;
    description: string;
    enabled: boolean;
    allocate_public_ip: boolean;
    node_template_id: string;
    config: Record<string, unknown>;
  }>): Promise<SystemNode> => {
    const response = await apiClient.put<any>(`/system/nodes/${id}`, { node: data });
    return extractData(response).node;
  },

  deleteNode: async (id: string): Promise<void> => {
    await apiClient.delete(`/system/nodes/${id}`);
  },

  // ============ Node Instances ============
  getNodeInstances: async (nodeId: string): Promise<{ node_instances: SystemNodeInstance[] }> => {
    const response = await apiClient.get<any>(`/system/nodes/${nodeId}/node_instances`);
    return { node_instances: extractData(response).node_instances || [] };
  },

  getNodeInstance: async (nodeId: string, instanceId: string): Promise<SystemNodeInstance> => {
    const response = await apiClient.get<any>(`/system/nodes/${nodeId}/node_instances/${instanceId}`);
    return extractData(response).node_instance;
  },

  createNodeInstance: async (nodeId: string, data: {
    name: string;
    description?: string;
    variety?: 'cloud' | 'physical' | 'dynamic';
    status?: string;
    private_ip_address?: string;
    public_ip_address?: string;
    vpn_ip_address?: string;
    config?: Record<string, unknown>;
  }): Promise<SystemNodeInstance> => {
    const response = await apiClient.post<any>(`/system/nodes/${nodeId}/node_instances`, { node_instance: data });
    return extractData(response).node_instance;
  },

  updateNodeInstance: async (nodeId: string, instanceId: string, data: Partial<{
    name: string;
    description: string;
    variety: 'cloud' | 'physical' | 'dynamic';
    status: string;
    private_ip_address: string;
    public_ip_address: string;
    vpn_ip_address: string;
    config: Record<string, unknown>;
  }>): Promise<SystemNodeInstance> => {
    const response = await apiClient.put<any>(`/system/nodes/${nodeId}/node_instances/${instanceId}`, { node_instance: data });
    return extractData(response).node_instance;
  },

  deleteNodeInstance: async (nodeId: string, instanceId: string): Promise<void> => {
    await apiClient.delete(`/system/nodes/${nodeId}/node_instances/${instanceId}`);
  },

  startInstance: async (nodeId: string, instanceId: string): Promise<SystemNodeInstance> => {
    const response = await apiClient.post<any>(`/system/nodes/${nodeId}/node_instances/${instanceId}/start`);
    return extractData(response).node_instance;
  },

  stopInstance: async (nodeId: string, instanceId: string): Promise<SystemNodeInstance> => {
    const response = await apiClient.post<any>(`/system/nodes/${nodeId}/node_instances/${instanceId}/stop`);
    return extractData(response).node_instance;
  },

  rebootInstance: async (nodeId: string, instanceId: string): Promise<SystemNodeInstance> => {
    const response = await apiClient.post<any>(`/system/nodes/${nodeId}/node_instances/${instanceId}/reboot`);
    return extractData(response).node_instance;
  },

  // ============ Templates ============
  getTemplates: async (params?: { page?: number; per_page?: number }): Promise<{ templates: SystemNodeTemplate[]; meta: any }> => {
    const response = await apiClient.get<any>('/system/node_templates', { params });
    const data = extractData(response);
    return { templates: data.node_templates || [], meta: data.meta };
  },

  getTemplate: async (id: string): Promise<SystemNodeTemplate> => {
    const response = await apiClient.get<any>(`/system/node_templates/${id}`);
    return extractData(response).node_template;
  },

  createTemplate: async (data: {
    name: string;
    description?: string;
    node_platform_id?: string;
    admin_user?: string;
    enabled?: boolean;
    public?: boolean;
    config?: Record<string, unknown>;
  }): Promise<SystemNodeTemplate> => {
    const response = await apiClient.post<any>('/system/node_templates', { node_template: data });
    return extractData(response).node_template;
  },

  updateTemplate: async (id: string, data: Partial<{
    name: string;
    description: string;
    node_platform_id: string;
    admin_user: string;
    enabled: boolean;
    public: boolean;
    config: Record<string, unknown>;
  }>): Promise<SystemNodeTemplate> => {
    const response = await apiClient.put<any>(`/system/node_templates/${id}`, { node_template: data });
    return extractData(response).node_template;
  },

  deleteTemplate: async (id: string): Promise<void> => {
    await apiClient.delete(`/system/node_templates/${id}`);
  },

  getTemplateModules: async (templateId: string): Promise<{ modules: SystemNodeModule[] }> => {
    const response = await apiClient.get<any>(`/system/node_templates/${templateId}/modules`);
    const data = extractData(response);
    return { modules: data.node_modules || [] };
  },

  // ============ Platforms ============
  getPlatforms: async (): Promise<SystemNodePlatform[]> => {
    const response = await apiClient.get<any>('/system/node_platforms');
    return extractData(response).node_platforms || [];
  },

  getPlatform: async (id: string): Promise<SystemNodePlatform> => {
    const response = await apiClient.get<any>(`/system/node_platforms/${id}`);
    return extractData(response).node_platform;
  },

  createPlatform: async (data: {
    name: string;
    description?: string;
    node_architecture_id?: string;
    build_script?: string;
    init_script?: string;
    sync_script?: string;
    enabled?: boolean;
    public?: boolean;
  }): Promise<SystemNodePlatform> => {
    const response = await apiClient.post<any>('/system/node_platforms', { node_platform: data });
    return extractData(response).node_platform;
  },

  updatePlatform: async (id: string, data: Partial<{
    name: string;
    description: string;
    node_architecture_id: string;
    build_script: string;
    init_script: string;
    sync_script: string;
    enabled: boolean;
    public: boolean;
  }>): Promise<SystemNodePlatform> => {
    const response = await apiClient.put<any>(`/system/node_platforms/${id}`, { node_platform: data });
    return extractData(response).node_platform;
  },

  deletePlatform: async (id: string): Promise<void> => {
    await apiClient.delete(`/system/node_platforms/${id}`);
  },

  // ============ Architectures ============
  getArchitectures: async (): Promise<SystemNodeArchitecture[]> => {
    const response = await apiClient.get<any>('/system/node_architectures');
    return extractData(response).node_architectures || [];
  },

  getArchitecture: async (id: string): Promise<SystemNodeArchitecture> => {
    const response = await apiClient.get<any>(`/system/node_architectures/${id}`);
    return extractData(response).node_architecture;
  },

  createArchitecture: async (data: {
    name: string;
    description?: string;
    kernel_options?: string;
    enabled?: boolean;
    public?: boolean;
  }): Promise<SystemNodeArchitecture> => {
    const response = await apiClient.post<any>('/system/node_architectures', { node_architecture: data });
    return extractData(response).node_architecture;
  },

  updateArchitecture: async (id: string, data: Partial<{
    name: string;
    description: string;
    kernel_options: string;
    enabled: boolean;
    public: boolean;
  }>): Promise<SystemNodeArchitecture> => {
    const response = await apiClient.put<any>(`/system/node_architectures/${id}`, { node_architecture: data });
    return extractData(response).node_architecture;
  },

  deleteArchitecture: async (id: string): Promise<void> => {
    await apiClient.delete(`/system/node_architectures/${id}`);
  },

  // ============ Scripts ============
  getScripts: async (): Promise<SystemNodeScript[]> => {
    const response = await apiClient.get<any>('/system/node_scripts');
    return extractData(response).node_scripts || [];
  },

  getScript: async (id: string): Promise<SystemNodeScript> => {
    const response = await apiClient.get<any>(`/system/node_scripts/${id}`);
    return extractData(response).node_script;
  },

  createScript: async (data: {
    name: string;
    description?: string;
    variety: 'build' | 'init' | 'sync' | 'custom';
    data?: string;
    enabled?: boolean;
    public?: boolean;
  }): Promise<SystemNodeScript> => {
    const response = await apiClient.post<any>('/system/node_scripts', { node_script: data });
    return extractData(response).node_script;
  },

  updateScript: async (id: string, data: Partial<{
    name: string;
    description: string;
    variety: 'build' | 'init' | 'sync' | 'custom';
    data: string;
    enabled: boolean;
    public: boolean;
  }>): Promise<SystemNodeScript> => {
    const response = await apiClient.put<any>(`/system/node_scripts/${id}`, { node_script: data });
    return extractData(response).node_script;
  },

  deleteScript: async (id: string): Promise<void> => {
    await apiClient.delete(`/system/node_scripts/${id}`);
  },

  // ============ Providers ============
  getProviders: async (): Promise<SystemProvider[]> => {
    const response = await apiClient.get<any>('/system/providers');
    return extractData(response).providers || [];
  },

  getProvider: async (id: string): Promise<SystemProvider> => {
    const response = await apiClient.get<any>(`/system/providers/${id}`);
    return extractData(response).provider;
  },

  createProvider: async (data: {
    name: string;
    description?: string;
    provider_type: string;
    enabled?: boolean;
    public?: boolean;
    config?: Record<string, unknown>;
    capabilities?: Record<string, unknown>;
  }): Promise<SystemProvider> => {
    const response = await apiClient.post<any>('/system/providers', { provider: data });
    return extractData(response).provider;
  },

  updateProvider: async (id: string, data: Partial<{
    name: string;
    description: string;
    provider_type: string;
    enabled: boolean;
    public: boolean;
    config: Record<string, unknown>;
    capabilities: Record<string, unknown>;
  }>): Promise<SystemProvider> => {
    const response = await apiClient.put<any>(`/system/providers/${id}`, { provider: data });
    return extractData(response).provider;
  },

  deleteProvider: async (id: string): Promise<void> => {
    await apiClient.delete(`/system/providers/${id}`);
  },

  testProvider: async (id: string): Promise<{ success: boolean; message: string }> => {
    const response = await apiClient.post<any>(`/system/providers/${id}/test`);
    return extractData(response);
  },

  // ============ Provider Regions ============
  getProviderRegions: async (providerId: string): Promise<SystemProviderRegion[]> => {
    const response = await apiClient.get<any>(`/system/providers/${providerId}/regions`);
    return extractData(response).regions || [];
  },

  getProviderRegion: async (providerId: string, regionId: string): Promise<SystemProviderRegion> => {
    const response = await apiClient.get<any>(`/system/providers/${providerId}/regions/${regionId}`);
    return extractData(response).region;
  },

  createProviderRegion: async (providerId: string, data: {
    name: string;
    description?: string;
    region_code?: string;
    endpoint_url?: string;
    kernel_image?: string;
    machine_image?: string;
    ramdisk_image?: string;
    capabilities?: Record<string, unknown>;
  }): Promise<SystemProviderRegion> => {
    const response = await apiClient.post<any>(`/system/providers/${providerId}/regions`, { region: data });
    return extractData(response).region;
  },

  updateProviderRegion: async (providerId: string, regionId: string, data: Partial<{
    name: string;
    description: string;
    region_code: string;
    endpoint_url: string;
    kernel_image: string;
    machine_image: string;
    ramdisk_image: string;
    capabilities: Record<string, unknown>;
  }>): Promise<SystemProviderRegion> => {
    const response = await apiClient.put<any>(`/system/providers/${providerId}/regions/${regionId}`, { region: data });
    return extractData(response).region;
  },

  deleteProviderRegion: async (providerId: string, regionId: string): Promise<void> => {
    await apiClient.delete(`/system/providers/${providerId}/regions/${regionId}`);
  },

  // ============ Provider Connections ============
  getProviderConnections: async (): Promise<SystemProviderConnection[]> => {
    const response = await apiClient.get<any>('/system/provider_connections');
    return extractData(response).provider_connections || [];
  },

  getProviderConnection: async (id: string): Promise<SystemProviderConnection> => {
    const response = await apiClient.get<any>(`/system/provider_connections/${id}`);
    return extractData(response).provider_connection;
  },

  createProviderConnection: async (data: {
    name: string;
    description?: string;
    provider_id: string;
    access_key?: string;
    secret_key?: string;
    tenant?: string;
    endpoint_url?: string;
    config?: Record<string, unknown>;
  }): Promise<SystemProviderConnection> => {
    const response = await apiClient.post<any>('/system/provider_connections', { provider_connection: data });
    return extractData(response).provider_connection;
  },

  updateProviderConnection: async (id: string, data: Partial<{
    name: string;
    description: string;
    access_key: string;
    secret_key: string;
    tenant: string;
    endpoint_url: string;
    config: Record<string, unknown>;
  }>): Promise<SystemProviderConnection> => {
    const response = await apiClient.put<any>(`/system/provider_connections/${id}`, { provider_connection: data });
    return extractData(response).provider_connection;
  },

  deleteProviderConnection: async (id: string): Promise<void> => {
    await apiClient.delete(`/system/provider_connections/${id}`);
  },

  testProviderConnection: async (id: string): Promise<{ success: boolean; message: string }> => {
    const response = await apiClient.post<any>(`/system/provider_connections/${id}/test`);
    return extractData(response);
  },

  // ============ Modules ============
  getModules: async (params?: { page?: number; per_page?: number; variety?: string; enabled?: boolean }): Promise<{ modules: SystemNodeModule[]; meta: any }> => {
    const response = await apiClient.get<any>('/system/node_modules', { params });
    const data = extractData(response);
    return { modules: data.node_modules || [], meta: data.meta };
  },

  getNodeModules: async (params?: { node_id?: string; page?: number; per_page?: number }): Promise<{ node_modules: SystemNodeModule[] }> => {
    const response = await apiClient.get<any>('/system/node_modules', { params });
    const data = extractData(response);
    return { node_modules: data.node_modules || [] };
  },

  getModuleCategories: async (): Promise<SystemNodeModuleCategory[]> => {
    const response = await apiClient.get<any>('/system/node_module_categories');
    return extractData(response).node_module_categories || [];
  },

  getModuleCategory: async (id: string): Promise<SystemNodeModuleCategory> => {
    const response = await apiClient.get<any>(`/system/node_module_categories/${id}`);
    return extractData(response).node_module_category;
  },

  createModuleCategory: async (data: {
    name: string;
    description?: string;
    parent_id?: string;
    enabled?: boolean;
  }): Promise<SystemNodeModuleCategory> => {
    const response = await apiClient.post<any>('/system/node_module_categories', { node_module_category: data });
    return extractData(response).node_module_category;
  },

  updateModuleCategory: async (id: string, data: Partial<{
    name: string;
    description: string;
    parent_id: string;
    enabled: boolean;
  }>): Promise<SystemNodeModuleCategory> => {
    const response = await apiClient.put<any>(`/system/node_module_categories/${id}`, { node_module_category: data });
    return extractData(response).node_module_category;
  },

  deleteModuleCategory: async (id: string): Promise<void> => {
    await apiClient.delete(`/system/node_module_categories/${id}`);
  },

  // Module Dependencies
  getModuleDependencies: async (moduleId: string): Promise<SystemNodeModule[]> => {
    const response = await apiClient.get<any>(`/system/node_modules/${moduleId}/dependencies`);
    return extractData(response).dependencies || [];
  },

  addModuleDependency: async (moduleId: string, dependencyId: string, data?: {
    dependency_type?: string;
    required?: boolean;
    version_requirement?: string;
  }): Promise<void> => {
    await apiClient.post(`/system/node_modules/${moduleId}/dependencies`, {
      module_dependency: {
        dependency_id: dependencyId,
        ...data
      }
    });
  },

  removeModuleDependency: async (moduleId: string, dependencyId: string): Promise<void> => {
    await apiClient.delete(`/system/node_modules/${moduleId}/dependencies/${dependencyId}`);
  },

  getModule: async (id: string): Promise<SystemNodeModule> => {
    const response = await apiClient.get<any>(`/system/node_modules/${id}`);
    return extractData(response).node_module;
  },

  createModule: async (data: {
    name: string;
    description?: string;
    variety: 'config' | 'instance' | 'subscription';
    node_platform_id?: string;
    category_id?: string;
    priority?: number;
    enabled?: boolean;
    public?: boolean;
    mask?: Record<string, unknown>;
    file_spec?: Record<string, unknown>;
    config?: Record<string, unknown>;
  }): Promise<SystemNodeModule> => {
    const response = await apiClient.post<any>('/system/node_modules', { node_module: data });
    return extractData(response).node_module;
  },

  updateModule: async (id: string, data: Partial<{
    name: string;
    description: string;
    variety: 'config' | 'instance' | 'subscription';
    node_platform_id: string;
    category_id: string;
    priority: number;
    enabled: boolean;
    public: boolean;
    mask: Record<string, unknown>;
    file_spec: Record<string, unknown>;
    config: Record<string, unknown>;
  }>): Promise<SystemNodeModule> => {
    const response = await apiClient.put<any>(`/system/node_modules/${id}`, { node_module: data });
    return extractData(response).node_module;
  },

  deleteModule: async (id: string): Promise<void> => {
    await apiClient.delete(`/system/node_modules/${id}`);
  },

  // ============ Operations ============
  getOperations: async (params?: { page?: number; per_page?: number; status?: string; command?: string; active?: boolean; finished?: boolean }): Promise<{ operations: SystemOperation[]; meta: any }> => {
    const response = await apiClient.get<any>('/system/operations', { params });
    const data = extractData(response);
    return { operations: data.operations || [], meta: data.meta };
  },

  getOperation: async (id: string): Promise<SystemOperation> => {
    const response = await apiClient.get<any>(`/system/operations/${id}`);
    return extractData(response).operation;
  },

  createOperation: async (data: {
    command: string;
    description?: string;
    operable_type?: string;
    operable_id?: string;
    scheduled_at?: string;
    exclusive?: boolean;
    options?: Record<string, unknown>;
  }): Promise<SystemOperation> => {
    const response = await apiClient.post<any>('/system/operations', { operation: data });
    return extractData(response).operation;
  },

  // Operation control actions
  startOperation: async (id: string): Promise<SystemOperation> => {
    const response = await apiClient.post<any>(`/system/operations/${id}/start`);
    return extractData(response).operation;
  },

  completeOperation: async (id: string): Promise<SystemOperation> => {
    const response = await apiClient.post<any>(`/system/operations/${id}/complete`);
    return extractData(response).operation;
  },

  failOperation: async (id: string, errorMessage?: string): Promise<SystemOperation> => {
    const response = await apiClient.post<any>(`/system/operations/${id}/fail`, { error_message: errorMessage });
    return extractData(response).operation;
  },

  abortOperation: async (id: string, reason?: string): Promise<SystemOperation> => {
    const response = await apiClient.post<any>(`/system/operations/${id}/abort`, { reason });
    return extractData(response).operation;
  },

  cancelOperation: async (id: string, reason?: string): Promise<SystemOperation> => {
    const response = await apiClient.post<any>(`/system/operations/${id}/cancel`, { reason });
    return extractData(response).operation;
  },

  retryOperation: async (id: string): Promise<SystemOperation> => {
    const response = await apiClient.post<any>(`/system/operations/${id}/retry`);
    return extractData(response).operation;
  },

  rescheduleOperation: async (id: string, scheduledAt?: string): Promise<SystemOperation> => {
    const response = await apiClient.post<any>(`/system/operations/${id}/reschedule`, { scheduled_at: scheduledAt });
    return extractData(response).operation;
  },

  // ============ Puppet Modules ============
  getPuppetModules: async (params?: { page?: number; per_page?: number }): Promise<{ puppetModules: SystemPuppetModule[]; meta: any }> => {
    const response = await apiClient.get<any>('/system/puppet_modules', { params });
    const data = extractData(response);
    return { puppetModules: data.puppet_modules || [], meta: data.meta };
  },

  getPuppetModule: async (id: string): Promise<SystemPuppetModule> => {
    const response = await apiClient.get<any>(`/system/puppet_modules/${id}`);
    return extractData(response).puppet_module;
  },

  getPuppetResources: async (puppetModuleId: string): Promise<SystemPuppetResource[]> => {
    const response = await apiClient.get<any>(`/system/puppet_modules/${puppetModuleId}/resources`);
    return extractData(response).puppet_resources || [];
  },

  getPuppetResource: async (puppetModuleId: string, resourceId: string): Promise<SystemPuppetResource> => {
    const response = await apiClient.get<any>(`/system/puppet_modules/${puppetModuleId}/resources/${resourceId}`);
    return extractData(response).puppet_resource;
  },

  createPuppetResource: async (puppetModuleId: string, data: {
    name: string;
    description?: string;
    resource_type?: string;
    title?: string;
    path?: string;
    data?: string;
    enabled?: boolean;
  }): Promise<SystemPuppetResource> => {
    const response = await apiClient.post<any>(`/system/puppet_modules/${puppetModuleId}/resources`, { puppet_resource: data });
    return extractData(response).puppet_resource;
  },

  updatePuppetResource: async (puppetModuleId: string, resourceId: string, data: Partial<{
    name: string;
    description: string;
    resource_type: string;
    title: string;
    path: string;
    data: string;
    enabled: boolean;
  }>): Promise<SystemPuppetResource> => {
    const response = await apiClient.put<any>(`/system/puppet_modules/${puppetModuleId}/resources/${resourceId}`, { puppet_resource: data });
    return extractData(response).puppet_resource;
  },

  deletePuppetResource: async (puppetModuleId: string, resourceId: string): Promise<void> => {
    await apiClient.delete(`/system/puppet_modules/${puppetModuleId}/resources/${resourceId}`);
  },

  // Puppet Module Assignments
  getPuppetModuleAssignments: async (puppetModuleId: string): Promise<any[]> => {
    const response = await apiClient.get<any>(`/system/puppet_modules/${puppetModuleId}/assignments`);
    return extractData(response).assignments || [];
  },

  createPuppetModule: async (data: {
    name: string;
    description?: string;
    version?: string;
    author?: string;
    license?: string;
    source_url?: string;
    project_url?: string;
    forge_name?: string;
    enabled?: boolean;
    public?: boolean;
    dependencies?: Array<{ name: string; version_requirement?: string }>;
    config?: Record<string, unknown>;
    metadata?: Record<string, unknown>;
  }): Promise<SystemPuppetModule> => {
    const response = await apiClient.post<any>('/system/puppet_modules', { puppet_module: data });
    return extractData(response).puppet_module;
  },

  updatePuppetModule: async (id: string, data: Partial<{
    name: string;
    description: string;
    version: string;
    author: string;
    license: string;
    source_url: string;
    project_url: string;
    forge_name: string;
    enabled: boolean;
    public: boolean;
    dependencies: Array<{ name: string; version_requirement?: string }>;
    config: Record<string, unknown>;
    metadata: Record<string, unknown>;
  }>): Promise<SystemPuppetModule> => {
    const response = await apiClient.put<any>(`/system/puppet_modules/${id}`, { puppet_module: data });
    return extractData(response).puppet_module;
  },

  deletePuppetModule: async (id: string): Promise<void> => {
    await apiClient.delete(`/system/puppet_modules/${id}`);
  },

  // ============ Volumes ============
  getVolumes: async (params?: { page?: number; per_page?: number; status?: string; attached?: boolean; encrypted?: boolean; search?: string }): Promise<{ volumes: SystemProviderVolume[]; meta: any }> => {
    const response = await apiClient.get<any>('/system/provider_volumes', { params });
    const data = extractData(response);
    return { volumes: data.volumes || [], meta: data.meta };
  },

  getVolume: async (id: string): Promise<SystemProviderVolume> => {
    const response = await apiClient.get<any>(`/system/provider_volumes/${id}`);
    return extractData(response).volume;
  },

  createVolume: async (data: {
    name: string;
    description?: string;
    size_gb: number;
    volume_type_id?: string;
    provider_region_id?: string;
    availability_zone_id?: string;
    iops?: number;
    throughput?: number;
    encrypted?: boolean;
    delete_on_termination?: boolean;
    config?: Record<string, unknown>;
  }): Promise<SystemProviderVolume> => {
    const response = await apiClient.post<any>('/system/provider_volumes', { volume: data });
    return extractData(response).volume;
  },

  updateVolume: async (id: string, data: Partial<{
    name: string;
    description: string;
    size_gb: number;
    iops: number;
    throughput: number;
    delete_on_termination: boolean;
    config: Record<string, unknown>;
  }>): Promise<SystemProviderVolume> => {
    const response = await apiClient.put<any>(`/system/provider_volumes/${id}`, { volume: data });
    return extractData(response).volume;
  },

  deleteVolume: async (id: string): Promise<void> => {
    await apiClient.delete(`/system/provider_volumes/${id}`);
  },

  attachVolume: async (id: string, nodeInstanceId: string, deviceName?: string): Promise<SystemProviderVolume> => {
    const response = await apiClient.post<any>(`/system/provider_volumes/${id}/attach`, {
      node_instance_id: nodeInstanceId,
      device_name: deviceName
    });
    return extractData(response).volume;
  },

  detachVolume: async (id: string): Promise<SystemProviderVolume> => {
    const response = await apiClient.post<any>(`/system/provider_volumes/${id}/detach`);
    return extractData(response).volume;
  },

  createVolumeSnapshot: async (id: string, name?: string, description?: string): Promise<any> => {
    const response = await apiClient.post<any>(`/system/provider_volumes/${id}/snapshot`, { name, description });
    return extractData(response).snapshot;
  },

  // ============ Networks ============
  getNetworks: async (params?: { page?: number; per_page?: number; provider_region_id?: string; search?: string }): Promise<{ networks: SystemProviderNetwork[]; meta: any }> => {
    const response = await apiClient.get<any>('/system/provider_networks', { params });
    const data = extractData(response);
    return { networks: data.networks || [], meta: data.meta };
  },

  getNetwork: async (id: string): Promise<SystemProviderNetwork> => {
    const response = await apiClient.get<any>(`/system/provider_networks/${id}`);
    return extractData(response).network;
  },

  createNetwork: async (data: {
    name: string;
    description?: string;
    provider_region_id: string;
    cidr_block?: string;
    is_public?: boolean;
    enabled?: boolean;
    config?: Record<string, unknown>;
  }): Promise<SystemProviderNetwork> => {
    const response = await apiClient.post<any>('/system/provider_networks', { network: data });
    return extractData(response).network;
  },

  updateNetwork: async (id: string, data: Partial<{
    name: string;
    description: string;
    cidr_block: string;
    is_public: boolean;
    enabled: boolean;
    config: Record<string, unknown>;
  }>): Promise<SystemProviderNetwork> => {
    const response = await apiClient.put<any>(`/system/provider_networks/${id}`, { network: data });
    return extractData(response).network;
  },

  deleteNetwork: async (id: string): Promise<void> => {
    await apiClient.delete(`/system/provider_networks/${id}`);
  },

  // ============ Provider Instance Types ============
  getProviderInstanceTypes: async (providerId?: string): Promise<SystemProviderInstanceType[]> => {
    const url = providerId
      ? `/system/providers/${providerId}/instance_types`
      : '/system/provider_instance_types';
    const response = await apiClient.get<any>(url);
    return extractData(response).instance_types || [];
  },

  getProviderInstanceType: async (providerId: string, instanceTypeId: string): Promise<SystemProviderInstanceType> => {
    const response = await apiClient.get<any>(`/system/providers/${providerId}/instance_types/${instanceTypeId}`);
    return extractData(response).instance_type;
  },

  getInstanceTypesForRegion: async (regionId: string): Promise<SystemProviderInstanceType[]> => {
    const response = await apiClient.get<any>('/system/provider_instance_types/for_region', {
      params: { region_id: regionId }
    });
    return extractData(response).instance_types || [];
  },

  // ============ Provider Availability Zones ============
  getProviderAvailabilityZones: async (providerId: string, regionId: string): Promise<SystemProviderAvailabilityZone[]> => {
    const response = await apiClient.get<any>(`/system/providers/${providerId}/regions/${regionId}/availability_zones`);
    return extractData(response).availability_zones || [];
  },

  getProviderAvailabilityZone: async (providerId: string, regionId: string, zoneId: string): Promise<SystemProviderAvailabilityZone> => {
    const response = await apiClient.get<any>(`/system/providers/${providerId}/regions/${regionId}/availability_zones/${zoneId}`);
    return extractData(response).availability_zone;
  },

  // ============ Network Subnets ============
  getNetworkSubnets: async (networkId: string, availabilityZoneId?: string): Promise<SystemProviderNetworkSubnet[]> => {
    const params = availabilityZoneId ? { availability_zone_id: availabilityZoneId } : {};
    const response = await apiClient.get<any>(`/system/provider_networks/${networkId}/subnets`, { params });
    return extractData(response).subnets || [];
  },

  getNetworkSubnet: async (networkId: string, subnetId: string): Promise<SystemProviderNetworkSubnet> => {
    const response = await apiClient.get<any>(`/system/provider_networks/${networkId}/subnets/${subnetId}`);
    return extractData(response).subnet;
  },
};

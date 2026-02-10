// Plugin API Service
// Platform-agnostic plugin management service

import { BaseApiService, QueryFilters } from '@/shared/services/ai/BaseApiService';
import type {
  PluginMarketplace,
  Plugin,
  PluginInstallation,
  CreatePluginMarketplaceRequest,
  CreatePluginRequest,
  InstallPluginRequest,
  UpdatePluginConfigurationRequest,
  SetPluginCredentialRequest
} from '@/shared/types/plugin';

export interface PluginFilters extends QueryFilters {
  type?: string;
  status?: string;
  verified?: boolean;
  official?: boolean;
}

export interface InstallationFilters extends QueryFilters {
  status?: string;
}

export interface PluginDetailResponse {
  plugin: Plugin;
  installation?: PluginInstallation;
  is_installed: boolean;
}

export interface MarketplaceSyncResponse {
  marketplace: PluginMarketplace;
  synced_plugins: number;
  new_plugins: number;
  updated_plugins: number;
}

class PluginsApiService extends BaseApiService {
  // Override base namespace since plugins use root paths
  protected baseNamespace = '';

  // ===================================================================
  // MARKETPLACE MANAGEMENT
  // ===================================================================

  async listMarketplaces(): Promise<PluginMarketplace[]> {
    const response = await this.get<{ marketplaces: PluginMarketplace[] }>(
      this.buildPath('plugin_marketplaces')
    );
    return response.marketplaces;
  }

  async getMarketplace(id: string): Promise<PluginMarketplace> {
    const response = await this.get<{ marketplace: PluginMarketplace }>(
      this.buildPath('plugin_marketplaces', id)
    );
    return response.marketplace;
  }

  async createMarketplace(data: CreatePluginMarketplaceRequest): Promise<PluginMarketplace> {
    const response = await this.post<{ marketplace: PluginMarketplace }>(
      this.buildPath('plugin_marketplaces'),
      data
    );
    return response.marketplace;
  }

  async updateMarketplace(
    id: string,
    data: Partial<CreatePluginMarketplaceRequest['marketplace']>
  ): Promise<PluginMarketplace> {
    const response = await this.patch<{ marketplace: PluginMarketplace }>(
      this.buildPath('plugin_marketplaces', id),
      { marketplace: data }
    );
    return response.marketplace;
  }

  async deleteMarketplace(id: string): Promise<void> {
    await this.delete(this.buildPath('plugin_marketplaces', id));
  }

  async syncMarketplace(id: string): Promise<MarketplaceSyncResponse> {
    return this.performAction<MarketplaceSyncResponse>(
      'plugin_marketplaces',
      id,
      'sync'
    );
  }

  // ===================================================================
  // PLUGIN MANAGEMENT
  // ===================================================================

  async listPlugins(filters?: PluginFilters): Promise<Plugin[]> {
    const queryString = this.buildQueryString(filters);
    const response = await this.get<{ plugins: Plugin[] }>(
      this.buildPath('plugins') + queryString
    );
    return response.plugins;
  }

  async getPlugin(id: string): Promise<PluginDetailResponse> {
    return this.getOne<PluginDetailResponse>('plugins', id);
  }

  async createPlugin(data: CreatePluginRequest): Promise<Plugin> {
    const response = await this.post<{ plugin: Plugin }>(
      this.buildPath('plugins'),
      data
    );
    return response.plugin;
  }

  async updatePlugin(
    id: string,
    data: Partial<CreatePluginRequest['plugin']>
  ): Promise<Plugin> {
    const response = await this.patch<{ plugin: Plugin }>(
      this.buildPath('plugins', id),
      { plugin: data }
    );
    return response.plugin;
  }

  async deletePlugin(id: string): Promise<void> {
    await this.remove('plugins', id);
  }

  async installPlugin(
    id: string,
    config?: InstallPluginRequest
  ): Promise<PluginInstallation> {
    const response = await this.performAction<{ installation: PluginInstallation }>(
      'plugins',
      id,
      'install',
      config
    );
    return response.installation;
  }

  async uninstallPlugin(id: string): Promise<void> {
    await this.performAction('plugins', id, 'uninstall');
  }

  async searchPlugins(query: string): Promise<Plugin[]> {
    const response = await this.get<{ plugins: Plugin[] }>(
      this.buildPath('plugins', undefined, 'search') + `?q=${encodeURIComponent(query)}`
    );
    return response.plugins;
  }

  async getPluginsByCapability(capability: string): Promise<Plugin[]> {
    const response = await this.get<{ plugins: Plugin[] }>(
      this.buildPath('plugins', undefined, 'by_capability') + `?capability=${encodeURIComponent(capability)}`
    );
    return response.plugins;
  }

  // ===================================================================
  // INSTALLATION MANAGEMENT
  // ===================================================================

  async listInstallations(filters?: InstallationFilters): Promise<PluginInstallation[]> {
    const queryString = this.buildQueryString(filters);
    const response = await this.get<{ installations: PluginInstallation[] }>(
      this.buildPath('plugin_installations') + queryString
    );
    return response.installations;
  }

  async getInstallation(id: string): Promise<PluginInstallation> {
    const response = await this.get<{ installation: PluginInstallation }>(
      this.buildPath('plugin_installations', id)
    );
    return response.installation;
  }

  async updateInstallation(
    id: string,
    data: Partial<PluginInstallation>
  ): Promise<PluginInstallation> {
    const response = await this.patch<{ installation: PluginInstallation }>(
      this.buildPath('plugin_installations', id),
      { installation: data }
    );
    return response.installation;
  }

  async activateInstallation(id: string): Promise<PluginInstallation> {
    const response = await this.performAction<{ installation: PluginInstallation }>(
      'plugin_installations',
      id,
      'activate'
    );
    return response.installation;
  }

  async deactivateInstallation(id: string): Promise<PluginInstallation> {
    const response = await this.performAction<{ installation: PluginInstallation }>(
      'plugin_installations',
      id,
      'deactivate'
    );
    return response.installation;
  }

  async configureInstallation(
    id: string,
    configuration: UpdatePluginConfigurationRequest
  ): Promise<PluginInstallation> {
    const response = await this.patch<{ installation: PluginInstallation }>(
      this.buildPath('plugin_installations', id, undefined, undefined, 'configure'),
      configuration
    );
    return response.installation;
  }

  async setInstallationCredential(
    id: string,
    credential: SetPluginCredentialRequest
  ): Promise<void> {
    await this.performAction(
      'plugin_installations',
      id,
      'set_credential',
      credential
    );
  }

  // ===================================================================
  // HELPER METHODS
  // ===================================================================

  async getAvailableProviderPlugins(): Promise<Plugin[]> {
    return this.listPlugins({ type: 'ai_provider', status: 'available' });
  }

  async getAvailableNodePlugins(): Promise<Plugin[]> {
    return this.listPlugins({ type: 'workflow_node', status: 'available' });
  }

  async getInstalledProviderPlugins(): Promise<Plugin[]> {
    return this.listPlugins({ type: 'ai_provider', status: 'installed' });
  }

  async getInstalledNodePlugins(): Promise<Plugin[]> {
    return this.listPlugins({ type: 'workflow_node', status: 'installed' });
  }
}

export const pluginsApi = new PluginsApiService();

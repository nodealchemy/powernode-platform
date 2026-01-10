import { BaseApiService } from '@/shared/services/ai/BaseApiService';

export interface Plugin {
  id: string;
  plugin_id: string;
  name: string;
  description: string;
  version: string;
  author: string;
  homepage?: string;
  license?: string;
  source_type: 'npm' | 'git' | 'local' | 'marketplace';
  source_url?: string;
  status: 'active' | 'inactive' | 'deprecated';
  is_verified: boolean;
  is_official: boolean;
  plugin_types: string[];
  capabilities: string[];
  manifest?: Record<string, unknown>;
  configuration?: Record<string, unknown>;
  install_count?: number;
  average_rating?: number;
  created_at: string;
  updated_at: string;
  source_marketplace?: {
    id: string;
    name: string;
  };
  plugin_installations?: PluginInstallation[];
}

export interface PluginInstallation {
  id: string;
  status: 'active' | 'inactive' | 'pending' | 'failed';
  installed_at: string;
  execution_count?: number;
  total_cost?: number;
}

export interface PluginFormData {
  plugin_id?: string;
  name: string;
  description: string;
  version: string;
  author: string;
  homepage?: string;
  license?: string;
  source_type: string;
  source_url?: string;
  status: string;
  is_verified?: boolean;
  is_official?: boolean;
  plugin_types?: string[];
  capabilities?: string[];
  configuration?: Record<string, unknown>;
}

class PluginsApiService extends BaseApiService {
  protected baseNamespace = '';

  constructor() {
    super();
  }

  private getBasePath(): string {
    return '/plugins';
  }

  async getPlugins(filters?: { type?: string; status?: string; verified?: boolean; official?: boolean }) {
    const params = new URLSearchParams();
    if (filters?.type) params.append('type', filters.type);
    if (filters?.status) params.append('status', filters.status);
    if (filters?.verified) params.append('verified', 'true');
    if (filters?.official) params.append('official', 'true');

    const queryString = params.toString();
    const path = this.getBasePath() + (queryString ? `?${queryString}` : '');
    return this.get<{ plugins: Plugin[] }>(path);
  }

  async getPlugin(id: string) {
    return this.get<{ plugin: Plugin; installation: PluginInstallation | null; is_installed: boolean }>(`${this.getBasePath()}/${id}`);
  }

  async createPlugin(data: PluginFormData) {
    return this.post<{ plugin: Plugin; message: string }>(this.getBasePath(), { plugin: data });
  }

  async updatePlugin(id: string, data: Partial<PluginFormData>) {
    return this.patch<{ plugin: Plugin; message: string }>(`${this.getBasePath()}/${id}`, { plugin: data });
  }

  async deletePlugin(id: string) {
    return this.delete<{ message: string }>(`${this.getBasePath()}/${id}`);
  }

  async installPlugin(id: string, configuration?: Record<string, unknown>) {
    return this.post<{ installation: PluginInstallation; message: string }>(`${this.getBasePath()}/${id}/install`, { configuration });
  }

  async uninstallPlugin(id: string) {
    return this.delete<{ message: string }>(`${this.getBasePath()}/${id}/uninstall`);
  }

  async searchPlugins(query: string) {
    return this.get<{ plugins: Plugin[] }>(`${this.getBasePath()}/search?q=${encodeURIComponent(query)}`);
  }

  async getPluginsByCapability(capability: string) {
    return this.get<{ plugins: Plugin[] }>(`${this.getBasePath()}/by_capability?capability=${encodeURIComponent(capability)}`);
  }

  getStatusColor(status: string): 'success' | 'warning' | 'danger' | 'secondary' {
    switch (status) {
      case 'active': return 'success';
      case 'inactive': return 'secondary';
      case 'deprecated': return 'warning';
      default: return 'secondary';
    }
  }

  getSourceTypeLabel(sourceType: string): string {
    switch (sourceType) {
      case 'npm': return 'NPM Package';
      case 'git': return 'Git Repository';
      case 'local': return 'Local';
      case 'marketplace': return 'Marketplace';
      default: return sourceType;
    }
  }
}

export const pluginsApi = new PluginsApiService();

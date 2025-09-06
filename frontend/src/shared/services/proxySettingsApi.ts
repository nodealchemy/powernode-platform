import api from '@/shared/services/api';

export interface ProxyUrlConfig {
  enabled: boolean;
  trusted_hosts: string[];
  default_protocol: string;
  default_host: string | null;
  default_port: number | null;
  base_path: string;
  security: {
    enabled: boolean;
    strict_mode: boolean;
    validate_host_format: boolean;
    block_suspicious_patterns: boolean;
  };
  multi_tenancy: {
    enabled: boolean;
    wildcard_patterns: string[];
  };
}

export interface ProxyValidationResult {
  host: string;
  validation: {
    valid: boolean;
    trusted: boolean;
    suspicious: boolean;
    errors: string[];
  };
  timestamp: string;
}

export interface ProxyDetectionResult {
  proxy_detected: boolean;
  proxy_context: {
    forwarded_host?: string;
    forwarded_proto?: string;
    forwarded_port?: string;
    forwarded_path?: string;
    forwarded_for?: string;
    real_ip?: string;
    original_host?: string;
    original_protocol?: string;
    remote_ip?: string;
  };
  generated_urls?: {
    base_url: string;
    api_url: string;
    websocket_url: string;
    frontend_url: string;
    generated_at: string;
    proxy_detected: boolean;
  };
  request_headers: Record<string, string>;
  detection_timestamp: string;
}

export interface ProxyTestResult {
  proxy_context: Record<string, string>;
  validation?: ProxyValidationResult['validation'];
  generated_urls: ProxyDetectionResult['generated_urls'];
  test_performed_at: string;
}

export interface ProxyExportData {
  config: ProxyUrlConfig;
  export_timestamp: string;
  export_format: string;
  version: string;
}

const proxySettingsApi = {
  // Get current proxy URL configuration
  getUrlConfig: async (): Promise<ProxyUrlConfig> => {
    const response = await api.get('/admin/proxy_settings/url_config');
    return response.data.data; // Unwrap the standardized API response
  },

  // Update proxy URL configuration
  updateUrlConfig: async (config: Partial<ProxyUrlConfig>): Promise<ProxyUrlConfig> => {
    const response = await api.put('/admin/proxy_settings/url_config', config);
    return response.data.data; // Unwrap the standardized API response
  },

  // Validate a host pattern
  validateHost: async (host: string): Promise<ProxyValidationResult> => {
    const response = await api.post('/admin/proxy_settings/validate_host', { host });
    return response.data.data; // Unwrap the standardized API response
  },

  // Test proxy headers
  testHeaders: async (headers: Record<string, string>): Promise<ProxyTestResult> => {
    const response = await api.post('/admin/proxy_settings/test_headers', { headers });
    return response.data.data; // Unwrap the standardized API response
  },

  // Get current proxy detection status
  getCurrentDetection: async (): Promise<ProxyDetectionResult> => {
    const response = await api.get('/admin/proxy_settings/current_detection');
    return response.data.data; // Unwrap the standardized API response
  },

  // Add trusted host pattern
  addTrustedHost: async (pattern: string): Promise<{ pattern: string; trusted_hosts: string[] }> => {
    const response = await api.post('/admin/proxy_settings/trusted_hosts', { pattern });
    return response.data.data; // Unwrap the standardized API response
  },

  // Remove trusted host pattern
  removeTrustedHost: async (pattern: string): Promise<{ pattern: string; trusted_hosts: string[] }> => {
    const response = await api.delete(`/admin/proxy_settings/trusted_hosts/${encodeURIComponent(pattern)}`);
    return response.data.data; // Unwrap the standardized API response
  },

  // Reorder trusted host patterns
  reorderTrustedHosts: async (orderedHosts: string[]): Promise<{ trusted_hosts: string[] }> => {
    const response = await api.put('/admin/proxy_settings/trusted_hosts/reorder', { trusted_hosts: orderedHosts });
    return response.data.data; // Unwrap the standardized API response
  },

  // Export configuration
  exportConfig: async (): Promise<ProxyExportData> => {
    const response = await api.get('/admin/proxy_settings/export');
    return response.data.data; // Unwrap the standardized API response
  },

  // Import configuration
  importConfig: async (config: Partial<ProxyUrlConfig>): Promise<ProxyUrlConfig> => {
    const response = await api.post('/admin/proxy_settings/import', { config });
    return response.data.data; // Unwrap the standardized API response
  },

  // Helper: Download configuration as JSON file
  downloadConfigAsFile: async (): Promise<void> => {
    const exportData = await proxySettingsApi.exportConfig();
    const blob = new Blob([JSON.stringify(exportData, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `proxy-config-${new Date().toISOString().split('T')[0]}.json`;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  },

  // Helper: Parse and validate imported file
  parseImportFile: async (file: File): Promise<Partial<ProxyUrlConfig>> => {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = (event) => {
        try {
          const result = event.target?.result;
          if (typeof result !== 'string') {
            throw new Error('Invalid file content');
          }
          const data = JSON.parse(result);
          
          // Extract config from export format or use directly
          const config = data.config || data;
          resolve(config);
        } catch (error) {
          reject(new Error('Invalid configuration file format'));
        }
      };
      reader.onerror = () => reject(new Error('Failed to read file'));
      reader.readAsText(file);
    });
  },
};

export default proxySettingsApi;
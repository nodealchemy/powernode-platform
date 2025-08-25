import { api } from '@/shared/services/api';

export interface ReverseProxyConfig {
  enabled: boolean;
  current_environment: string;
  environments: {
    [key: string]: {
      [serviceName: string]: {
        host: string;
        port: number;
        protocol: string;
        base_url: string;
        health_check_path: string;
      };
    };
  };
  url_mappings: URLMapping[];
  load_balancing: LoadBalancingConfig;
  ssl_config: SSLConfig;
  cors_config: CORSConfig;
  headers: HeadersConfig;
  rate_limiting: RateLimitingConfig;
  compression: CompressionConfig;
}

export interface URLMapping {
  id: string;
  name: string;
  pattern: string;
  target_service: string;
  priority: number;
  methods: string[];
  enabled: boolean;
  description?: string;
}

export interface LoadBalancingConfig {
  enabled: boolean;
  algorithm: 'round_robin' | 'least_connections' | 'ip_hash';
  health_check_interval: number;
  failover_enabled: boolean;
}

export interface SSLConfig {
  enabled: boolean;
  enforce_https: boolean;
  certificate_path: string;
  private_key_path: string;
  protocols: string[];
  ciphers: string;
  hsts_enabled: boolean;
  hsts_max_age: number;
}

export interface CORSConfig {
  enabled: boolean;
  allowed_origins: string[];
  allowed_methods: string[];
  allowed_headers: string[];
  exposed_headers: string[];
  credentials: boolean;
  max_age: number;
}

export interface HeadersConfig {
  security_headers: {
    enabled: boolean;
    x_frame_options: string;
    x_content_type_options: string;
    x_xss_protection: string;
    referrer_policy: string;
  };
  custom_headers: {
    request: Array<{
      name: string;
      value: string;
      enabled: boolean;
    }>;
    response: Array<{
      name: string;
      value: string;
      enabled: boolean;
    }>;
  };
}

export interface RateLimitingConfig {
  enabled: boolean;
  default_limit: number;
  window_size: number;
  burst_limit: number;
}

export interface CompressionConfig {
  enabled: boolean;
  types: string[];
  level: number;
}

export interface ServiceDiscoveryConfig {
  enabled: boolean;
  methods: string[];
  dns_config: {
    enabled: boolean;
    timeout: number;
    retries: number;
  };
  consul_config: {
    enabled: boolean;
    host: string;
    port: number;
    token: string | null;
    datacenter: string;
  };
  port_scan_config: {
    enabled: boolean;
    port_ranges: {
      [serviceName: string]: [number, number];
    };
    timeout: number;
  };
  kubernetes_config: {
    enabled: boolean;
    namespace: string;
    label_selector: string;
  };
}

export interface ProxyTemplates {
  nginx: {
    enabled: boolean;
    config_path: string;
    reload_command: string;
    test_command: string;
  };
  apache: {
    enabled: boolean;
    config_path: string;
    reload_command: string;
    test_command: string;
  };
  traefik: {
    enabled: boolean;
    config_path: string;
    reload_command: string;
    test_command: string | null;
  };
}

export interface HealthStatus {
  environment: string;
  services: {
    [serviceName: string]: {
      status: 'healthy' | 'unhealthy' | 'unreachable';
      url?: string;
      response_code?: string;
      response_time?: number;
      error?: string;
    };
  };
  overall_status: 'healthy' | 'degraded';
  last_checked: string;
}

export interface ConfigValidationResult {
  valid: boolean;
  errors: string[];
}

export interface ConnectivityTestResult {
  [serviceName: string]: {
    status: 'healthy' | 'unhealthy' | 'unreachable';
    response_code?: number;
    response_time_ms?: number;
    url?: string;
    error?: string;
  };
}

export interface GeneratedConfig {
  proxy_type: string;
  config: string;
  filename: string;
  instructions: string;
}

export const reverseProxyApi = {
  // Get all reverse proxy configuration
  async getConfiguration(): Promise<{
    reverse_proxy_config: ReverseProxyConfig;
    service_discovery_config: ServiceDiscoveryConfig;
    proxy_templates: ProxyTemplates;
    health_status: HealthStatus;
  }> {
    const response = await api.get('/reverse_proxy');
    return response.data.data;
  },

  // Update reverse proxy configuration
  async updateConfiguration(
    configType: 'reverse_proxy_config' | 'service_discovery_config' | 'proxy_templates',
    config: Partial<ReverseProxyConfig | ServiceDiscoveryConfig | ProxyTemplates>
  ): Promise<{ message: string }> {
    const response = await api.put('/reverse_proxy', {
      config_type: configType,
      [configType]: config
    });
    return response.data.data;
  },

  // Test configuration before applying
  async testConfiguration(testConfig?: Partial<ReverseProxyConfig>): Promise<{
    validation: ConfigValidationResult;
    connectivity: ConnectivityTestResult;
    message: string;
  }> {
    const response = await api.post('/reverse_proxy/test_configuration', {
      test_config: testConfig
    });
    return response.data.data;
  },

  // Generate proxy configuration file
  async generateConfig(proxyType: 'nginx' | 'apache' | 'traefik'): Promise<GeneratedConfig> {
    const response = await api.post('/reverse_proxy/generate_config', {
      proxy_type: proxyType
    });
    return response.data.data;
  },

  // Get health check status
  async getHealthStatus(): Promise<HealthStatus> {
    const response = await api.get('/reverse_proxy/health_check');
    return response.data.data;
  },

  // Get proxy status
  async getStatus(): Promise<{
    enabled: boolean;
    current_environment: string;
    active_mappings: number;
    services_configured: string[];
    last_updated: string;
  }> {
    const response = await api.get('/reverse_proxy/status');
    return response.data.data;
  },

  // URL Mapping management
  async createURLMapping(mapping: Omit<URLMapping, 'id'>): Promise<{ message: string; mapping: URLMapping }> {
    const response = await api.post('/reverse_proxy/url_mappings', {
      url_mapping: mapping
    });
    return response.data.data;
  },

  async updateURLMapping(id: string, mapping: Partial<URLMapping>): Promise<{ message: string }> {
    const response = await api.put(`/reverse_proxy/url_mappings/${id}`, {
      url_mapping: mapping
    });
    return response.data.data;
  },

  async deleteURLMapping(id: string): Promise<{ message: string }> {
    const response = await api.delete(`/reverse_proxy/url_mappings/${id}`);
    return response.data.data;
  },

  async toggleURLMapping(id: string, enabled: boolean): Promise<{ message: string }> {
    const response = await api.patch(`/reverse_proxy/url_mappings/${id}/toggle`, {
      enabled
    });
    return response.data.data;
  }
};
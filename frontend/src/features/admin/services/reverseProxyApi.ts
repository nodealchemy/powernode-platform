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
  },

  // Service Discovery
  async getDiscoveredServices(): Promise<Array<{
    name: string;
    host: string;
    port: number;
    protocol: string;
    health_check_path: string;
    status: 'healthy' | 'unhealthy' | 'unreachable';
    discovered_method: string;
    last_seen: string;
  }>> {
    const response = await api.get('/reverse_proxy/discovered_services');
    return response.data.data;
  },

  async runServiceDiscovery(): Promise<{
    services: Array<{
      name: string;
      host: string;
      port: number;
      protocol: string;
      health_check_path: string;
      status: 'healthy' | 'unhealthy' | 'unreachable';
      discovered_method: string;
      last_seen: string;
    }>;
    message: string;
  }> {
    const response = await api.post('/reverse_proxy/service_discovery');
    return response.data.data;
  },

  async addDiscoveredService(service: {
    name: string;
    host: string;
    port: number;
    protocol: string;
    health_check_path: string;
    status: string;
    discovered_method: string;
    last_seen: string;
  }): Promise<{ message: string }> {
    const response = await api.post('/reverse_proxy/add_discovered_service', {
      service
    });
    return response.data.data;
  },

  // Health Monitoring
  async getServiceHealthHistory(serviceName: string, hours: number = 24): Promise<{
    service: string;
    timeframe: string;
    data_points: Array<{
      timestamp: string;
      status: 'healthy' | 'unhealthy' | 'unreachable';
      response_time: number;
      response_code: number | null;
      error: string | null;
    }>;
  }> {
    const response = await api.get(`/reverse_proxy/health_history/${serviceName}?hours=${hours}`);
    return response.data.data;
  },

  async updateHealthCheckConfig(serviceName: string, config: {
    interval: number;
    timeout: number;
    health_check_path: string;
    expected_codes: number[];
  }): Promise<{ message: string }> {
    const response = await api.put(`/reverse_proxy/health_config/${serviceName}`, {
      health_config: config
    });
    return response.data.data;
  },

  // Service Management APIs
  async testServiceConnection(environment: string, serviceName: string): Promise<{
    status: 'healthy' | 'unhealthy' | 'unreachable';
    response_code?: number;
    response_time?: number;
    error?: string;
  }> {
    const response = await api.post('/reverse_proxy/test_service', {
      environment,
      service_name: serviceName
    });
    return response.data.data;
  },

  async validateServiceConfig(serviceConfig: {
    host: string;
    port: number;
    protocol: string;
    health_check_path: string;
  }): Promise<{
    valid: boolean;
    errors: string[];
    warnings: string[];
  }> {
    const response = await api.post('/reverse_proxy/validate_service', {
      service_config: serviceConfig
    });
    return response.data.data;
  },

  async getServiceTemplates(): Promise<Array<{
    name: string;
    type: string;
    description: string;
    config: {
      host: string;
      port: number;
      protocol: string;
      health_check_path: string;
      base_url: string;
    };
  }>> {
    const response = await api.get('/reverse_proxy/service_templates');
    return response.data.data;
  },

  async duplicateService(environment: string, serviceName: string, newName: string): Promise<{ message: string }> {
    const response = await api.post('/reverse_proxy/duplicate_service', {
      environment,
      service_name: serviceName,
      new_name: newName
    });
    return response.data.data;
  },

  async exportServices(environment: string): Promise<{
    environment: string;
    services: Record<string, any>;
    export_format: string;
    filename: string;
  }> {
    const response = await api.get(`/reverse_proxy/export_services/${environment}`);
    return response.data.data;
  },

  async importServices(environment: string, services: Record<string, any>): Promise<{
    imported_count: number;
    skipped_count: number;
    errors: string[];
    message: string;
  }> {
    const response = await api.post('/reverse_proxy/import_services', {
      environment,
      services
    });
    return response.data.data;
  }
};
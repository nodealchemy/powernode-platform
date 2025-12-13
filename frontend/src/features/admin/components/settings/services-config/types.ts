import type { ServiceConfig, URLMapping, HealthStatus } from '../../../services/servicesApi';

// Props for BasicConfiguration component
export interface BasicConfigurationProps {
  config: ServiceConfig;
  updateConfig: (updates: Partial<ServiceConfig>) => void;
}

// Props for ServicesListComponent
export interface ServicesListComponentProps {
  config: ServiceConfig;
  updateConfig: (updates: Partial<ServiceConfig>) => void;
  healthStatus: HealthStatus | null;
}

// Props for URLMappingsConfiguration component
export interface URLMappingsConfigurationProps {
  config: ServiceConfig;
  updateConfig: (updates: Partial<ServiceConfig>) => void;
  onToggleMapping: (id: string) => void;
  onDeleteMapping: (id: string) => void;
  onEditMapping: (mapping: URLMapping) => void;
  onAddMapping: () => void;
}

// Props for AdvancedConfiguration component
export interface AdvancedConfigurationProps {
  config: ServiceConfig;
  updateConfig: (updates: Partial<ServiceConfig>) => void;
}

// Service configuration type for new services
export interface NewServiceConfig {
  host: string;
  port: number;
  protocol: string;
  health_check_path: string;
  base_url?: string;
}

// Service template type
export interface ServiceTemplate {
  name: string;
  type: string;
  config: {
    host: string;
    port: number;
    protocol: string;
    health_check_path: string;
    base_url: string;
  };
}

// Props for AddServiceModal component
export interface AddServiceModalProps {
  isOpen: boolean;
  onClose: () => void;
  onAddService: (name: string, config: NewServiceConfig) => void;
  existingServices: string[];
  templates: ServiceTemplate[];
}

// Re-export types from servicesApi
export type { ServiceConfig, URLMapping, HealthStatus } from '../../../services/servicesApi';

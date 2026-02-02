import { api } from '@/shared/services/api';

/**
 * Type-safe error extraction for axios-style errors
 */
interface ApiErrorResponse {
  response?: {
    status?: number;
    data?: {
      error?: string;
      message?: string;
    };
  };
  request?: unknown;
  message?: string;
  config?: {
    url?: string;
    method?: string;
  };
}

function extractApiError(error: unknown, fallback: string): string {
  if (!error || typeof error !== 'object') return fallback;
  const apiError = error as ApiErrorResponse;
  return apiError.response?.data?.error || apiError.response?.data?.message || fallback;
}

// Types
export interface ApiKey {
  id: string;
  name: string;
  description?: string;
  masked_key: string;
  status: 'active' | 'revoked' | 'expired';
  scopes: string[];
  expires_at?: string;
  last_used_at?: string;
  usage_count: number;
  created_at: string;
  created_by?: {
    id: string;
    email: string;
  };
  account?: {
    id: string;
    name: string;
  };
}

export interface DetailedApiKey extends ApiKey {
  key_value?: string; // Only returned on creation/regeneration
  rate_limit_per_hour?: number;
  rate_limit_per_day?: number;
  allowed_ips: string[];
  recent_usage: ApiKeyUsage[];
  usage_stats: {
    requests_today: number;
    requests_this_week: number;
    requests_this_month: number;
    average_requests_per_day: number;
  };
}

export interface ApiKeyUsage {
  id: string;
  endpoint: string;
  method: string;
  status_code: number;
  request_count: number;
  ip_address?: string;
  user_agent?: string;
  created_at: string;
}

export interface ApiKeyStats {
  total_keys: number;
  active_keys: number;
  revoked_keys: number;
  expired_keys: number;
  requests_today: number;
  most_used_keys: Record<string, number>;
}

export interface ApiKeyFormData {
  name: string;
  description?: string;
  scopes: string[];
  expires_at?: string;
  rate_limit_per_hour?: number;
  rate_limit_per_day?: number;
  allowed_ips?: string[];
}

export interface ApiKeysResponse {
  success: boolean;
  data: {
    api_keys: ApiKey[];
    pagination: {
      current_page: number;
      per_page: number;
      total_pages: number;
      total_count: number;
    };
    stats: ApiKeyStats;
  };
  error?: string;
}

export interface ApiKeyResponse {
  success: boolean;
  data?: DetailedApiKey;
  message?: string;
  error?: string;
}

export interface ApiKeyValidationResponse {
  success: boolean;
  valid: boolean;
  data?: {
    id: string;
    name: string;
    scopes: string[];
    account_id?: string;
    expires_at?: string;
  };
  reason?: string;
  error?: string;
}

export interface ApiKeyUsageStatsResponse {
  success: boolean;
  data: {
    usage_stats: Record<string, Record<string, number>>;
    summary: {
      total_requests: number;
      unique_api_keys: number;
      date_range: {
        from?: string;
        to?: string;
      };
    };
  };
  error?: string;
}

export interface AvailableScopesResponse {
  success: boolean;
  data: {
    scopes: string[];
    scope_descriptions: Record<string, string>;
  };
  error?: string;
}

// API Service
export const apiKeysApi = {
  // Get all API keys
  async getApiKeys(page = 1, perPage = 20): Promise<ApiKeysResponse> {
    try {
      const response = await api.get(`/api_keys?page=${page}&per_page=${perPage}`);
      return response.data;
    } catch {
      const apiError = error as ApiErrorResponse;

      // Handle different types of errors
      let errorMessage = 'Failed to fetch API keys';

      if (apiError.response) {
        // Server responded with error status
        const status = apiError.response.status;
        errorMessage = apiError.response.data?.error || `Server error: HTTP ${status}`;
      } else if (apiError.request) {
        // Network error - request was made but no response received
        errorMessage = 'Network error: Unable to reach server (possible cache issue - try hard refresh)';
      } else if (apiError.message) {
        // Other axios errors
        errorMessage = `Request configuration error: ${apiError.message}`;
      }

      return {
        success: false,
        data: {
          api_keys: [],
          pagination: {
            current_page: 1,
            per_page: perPage,
            total_pages: 0,
            total_count: 0
          },
          stats: {
            total_keys: 0,
            active_keys: 0,
            revoked_keys: 0,
            expired_keys: 0,
            requests_today: 0,
            most_used_keys: {}
          }
        },
        error: errorMessage
      };
    }
  },

  // Get single API key
  async getApiKey(id: string): Promise<ApiKeyResponse> {
    try {
      const response = await api.get(`/api_keys/${id}`);
      return response.data;
    } catch {
      return {
        success: false,
        error: extractApiError(error, 'Failed to fetch API key')
      };
    }
  },

  // Create new API key
  async createApiKey(apiKeyData: ApiKeyFormData): Promise<ApiKeyResponse> {
    try {
      const response = await api.post('/api_keys', { api_key: apiKeyData });
      return response.data;
    } catch {
      return {
        success: false,
        error: extractApiError(error, 'Failed to create API key')
      };
    }
  },

  // Update API key
  async updateApiKey(id: string, apiKeyData: Partial<ApiKeyFormData>): Promise<ApiKeyResponse> {
    try {
      const response = await api.put(`/api_keys/${id}`, { api_key: apiKeyData });
      return response.data;
    } catch {
      return {
        success: false,
        error: extractApiError(error, 'Failed to update API key')
      };
    }
  },

  // Delete API key
  async deleteApiKey(id: string): Promise<{ success: boolean; message?: string; error?: string }> {
    try {
      const response = await api.delete(`/api_keys/${id}`);
      return response.data;
    } catch {
      return {
        success: false,
        error: extractApiError(error, 'Failed to delete API key')
      };
    }
  },

  // Regenerate API key
  async regenerateApiKey(id: string): Promise<ApiKeyResponse> {
    try {
      const response = await api.post(`/api_keys/${id}/regenerate`);
      return response.data;
    } catch {
      return {
        success: false,
        error: extractApiError(error, 'Failed to regenerate API key')
      };
    }
  },

  // Toggle API key status (active/revoked)
  async toggleStatus(id: string): Promise<ApiKeyResponse> {
    try {
      const response = await api.post(`/api_keys/${id}/toggle_status`);
      return response.data;
    } catch {
      return {
        success: false,
        error: extractApiError(error, 'Failed to toggle API key status')
      };
    }
  },

  // Get usage statistics
  async getUsageStats(
    apiKeyId?: string,
    dateFrom?: string,
    dateTo?: string
  ): Promise<ApiKeyUsageStatsResponse> {
    try {
      const params = new URLSearchParams();
      if (apiKeyId) params.append('api_key_id', apiKeyId);
      if (dateFrom) params.append('date_from', dateFrom);
      if (dateTo) params.append('date_to', dateTo);

      const response = await api.get(`/api_keys/usage?${params}`);
      return response.data;
    } catch {
      return {
        success: false,
        data: {
          usage_stats: {},
          summary: {
            total_requests: 0,
            unique_api_keys: 0,
            date_range: {}
          }
        },
        error: extractApiError(error, 'Failed to fetch usage stats')
      };
    }
  },

  // Get available scopes
  async getAvailableScopes(): Promise<AvailableScopesResponse> {
    try {
      const response = await api.get('/api_keys/scopes');
      return response.data;
    } catch {
      return {
        success: false,
        data: {
          scopes: [],
          scope_descriptions: {}
        },
        error: extractApiError(error, 'Failed to fetch available scopes')
      };
    }
  },

  // Validate API key
  async validateKey(key: string): Promise<ApiKeyValidationResponse> {
    try {
      const response = await api.post('/api_keys/validate', { key });
      return response.data;
    } catch {
      return {
        success: false,
        valid: false,
        error: extractApiError(error, 'Failed to validate API key')
      };
    }
  },

  // Helper methods
  getStatusColor(status: string): string {
    switch (status) {
      case 'active': return 'bg-theme-success bg-opacity-10 text-theme-success';
      case 'revoked': return 'bg-theme-error bg-opacity-10 text-theme-error';
      case 'expired': return 'bg-theme-warning bg-opacity-10 text-theme-warning';
      default: return 'bg-theme-surface text-theme-secondary';
    }
  },

  getStatusText(status: string): string {
    switch (status) {
      case 'active': return 'Active';
      case 'revoked': return 'Revoked';
      case 'expired': return 'Expired';
      default: return 'Unknown';
    }
  },

  formatUsageCount(count: number): string {
    if (count === 0) return '0';
    if (count < 1000) return count.toString();
    if (count < 1000000) return `${(count / 1000).toFixed(1)}K`;
    return `${(count / 1000000).toFixed(1)}M`;
  },

  formatScope(scope: string): string {
    return scope.split(':').map(part => 
      part.charAt(0).toUpperCase() + part.slice(1)
    ).join(' → ');
  },

  getScopeCategory(scope: string): string {
    const [category] = scope.split(':');
    switch (category) {
      case 'read': return 'Read Access';
      case 'write': return 'Write Access';
      case 'admin': return 'Admin Access';
      case 'webhooks': return 'Webhook Management';
      default: return 'General';
    }
  },

  getScopeCategoryColor(scope: string): string {
    const [category] = scope.split(':');
    switch (category) {
      case 'read': return 'bg-theme-info bg-opacity-10 text-theme-info';
      case 'write': return 'bg-theme-warning bg-opacity-10 text-theme-warning';
      case 'admin': return 'bg-theme-error bg-opacity-10 text-theme-error';
      case 'webhooks': return 'bg-theme-interactive-primary bg-opacity-10 text-theme-interactive-primary';
      default: return 'bg-theme-surface text-theme-secondary';
    }
  },

  isKeyExpired(apiKey: ApiKey): boolean {
    if (!apiKey.expires_at) return false;
    return new Date(apiKey.expires_at) <= new Date();
  },

  isKeyExpiringSoon(apiKey: ApiKey, days = 7): boolean {
    if (!apiKey.expires_at || this.isKeyExpired(apiKey)) return false;
    const expiryDate = new Date(apiKey.expires_at);
    const warningDate = new Date();
    warningDate.setDate(warningDate.getDate() + days);
    return expiryDate <= warningDate;
  },

  validateApiKeyData(data: ApiKeyFormData): string[] {
    const errors: string[] = [];

    if (!data.name?.trim()) {
      errors.push('Name is required');
    } else if (data.name.length > 100) {
      errors.push('Name must be 100 characters or less');
    }

    if (!data.scopes || data.scopes.length === 0) {
      errors.push('At least one scope must be selected');
    }

    if (data.expires_at) {
      const expiryDate = new Date(data.expires_at);
      const now = new Date();
      if (expiryDate <= now) {
        errors.push('Expiry date must be in the future');
      }
      if (expiryDate > new Date(now.getFullYear() + 10, now.getMonth(), now.getDate())) {
        errors.push('Expiry date cannot be more than 10 years in the future');
      }
    }

    if (data.rate_limit_per_hour && (data.rate_limit_per_hour < 1 || data.rate_limit_per_hour > 10000)) {
      errors.push('Hourly rate limit must be between 1 and 10,000');
    }

    if (data.rate_limit_per_day && (data.rate_limit_per_day < 1 || data.rate_limit_per_day > 1000000)) {
      errors.push('Daily rate limit must be between 1 and 1,000,000');
    }

    if (data.allowed_ips) {
      for (const ip of data.allowed_ips) {
        if (!this.isValidIpAddress(ip)) {
          errors.push(`Invalid IP address: ${ip}`);
          break;
        }
      }
    }

    return errors;
  },

  isValidIpAddress(ip: string): boolean {
    // Use safer IP validation without complex regex
    const parts = ip.split('.');
    if (parts.length === 4) {
      // IPv4 validation
      return parts.every(part => {
        const num = parseInt(part, 10);
        return !isNaN(num) && num >= 0 && num <= 255 && part === num.toString();
      });
    }
    // For IPv6, use a simple check for now
    return ip.includes(':') && ip.length >= 3;
  },

  getDefaultFormData(): ApiKeyFormData {
    return {
      name: '',
      description: '',
      scopes: [],
      rate_limit_per_hour: 1000,
      rate_limit_per_day: 10000,
      allowed_ips: []
    };
  },

  copyToClipboard(text: string): Promise<boolean> {
    return navigator.clipboard.writeText(text).then(
      () => true,
      () => false
    );
  },

  generateKeyPreview(keyValue?: string): string {
    if (!keyValue) return 'pk_****...****';
    const parts = keyValue.split('_');
    if (parts.length < 3) return keyValue.substring(0, 8) + '...' + keyValue.slice(-4);
    return `${parts[0]}_${parts[1]}_${'*'.repeat(8)}...${keyValue.slice(-8)}`;
  }
};
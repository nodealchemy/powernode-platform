// Git Provider Types

export interface GitProvider {
  id: string;
  name: string;
  slug: string;
  provider_type: 'github' | 'gitlab' | 'gitea' | 'bitbucket';
  description?: string;
  api_base_url?: string;
  web_base_url?: string;
  is_active: boolean;
  supports_oauth: boolean;
  supports_pat: boolean;
  supports_webhooks: boolean;
  supports_devops: boolean;
  capabilities: string[];
  priority_order: number;
  created_at: string;
}

export interface GitProviderDetail extends GitProvider {
  oauth_config?: Record<string, unknown>;
  webhook_config?: Record<string, unknown>;
  devops_config?: Record<string, unknown>;
  metadata?: Record<string, unknown>;
  credentials_count: number;
}

export interface AvailableProvider {
  id: string;
  name: string;
  slug: string;
  provider_type: string;
  description?: string;
  api_base_url?: string;
  web_base_url?: string;
  supports_oauth: boolean;
  supports_pat: boolean;
  supports_devops: boolean;
  capabilities: string[];
  configured: boolean;
}

export interface CreateProviderData {
  name: string;
  provider_type: 'github' | 'gitlab' | 'gitea' | 'bitbucket';
  description?: string;
  api_base_url?: string;
  web_base_url?: string;
  is_active?: boolean;
  supports_oauth?: boolean;
  supports_pat?: boolean;
  supports_webhooks?: boolean;
  supports_devops?: boolean;
}

export interface UpdateProviderData {
  name?: string;
  description?: string;
  api_base_url?: string;
  web_base_url?: string;
  is_active?: boolean;
}

export interface GitCredential {
  id: string;
  name: string;
  auth_type: 'oauth' | 'personal_access_token';
  provider_type: string;
  external_username?: string;
  external_avatar_url?: string;
  is_active: boolean;
  is_default: boolean;
  scopes: string[];
  last_used_at?: string;
  last_test_status?: string;
  last_sync_at?: string;
  expires_at?: string;
  created_at: string;
  repository_count?: number;
  stats: {
    success_count: number;
    failure_count: number;
    consecutive_failures: number;
    repositories_count: number;
  };
}

export interface GitCredentialDetail extends GitCredential {
  last_error?: string;
  last_test_at?: string;
  healthy: boolean;
  can_be_used: boolean;
  git_provider: GitProvider;
}

export interface CreateCredentialData {
  name: string;
  auth_type: 'oauth' | 'personal_access_token';
  credentials: {
    access_token?: string;
    refresh_token?: string;
    expires_at?: string;
  };
  is_active?: boolean;
  is_default?: boolean;
  expires_at?: string;
}

export interface ConnectionTestResult {
  success: boolean;
  message?: string;
  error?: string;
  rate_limit?: {
    remaining: number;
    limit: number;
    reset_at?: string;
  };
  user_info?: {
    username: string;
    name?: string;
    avatar_url?: string;
  };
  scopes?: string[];
  capabilities?: string[];
}

export interface SyncRepositoriesResult {
  synced_count: number;
  error_count: number;
  repositories: Array<{
    id: string;
    name: string;
    full_name: string;
    is_private: boolean;
    webhook_configured: boolean;
  }>;
}

export interface GitProvidersResponse {
  providers: GitProvider[];
  count: number;
}

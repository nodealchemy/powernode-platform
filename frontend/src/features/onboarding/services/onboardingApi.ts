// Onboarding API service — consolidates the inline apiClient calls made by the
// onboarding feature components (FirstRunWizard).
//
// Behavior-preserving: each method uses the SAME apiClient module the components
// previously called inline, hits the SAME endpoint with the SAME payload, and
// unwraps the axios response EXACTLY as the components did — returning the value
// each component derived from `response.data`. This keeps the components' existing
// apiClient mocks (which assert call paths/args) intercepting unchanged.
import { apiClient } from '@/shared/services/apiClient';
import type { AiProviderCatalog } from '@/shared/types/ai';
import type {
  ProviderCategory,
  ProviderCredentialValues,
  ProviderTypeSlug,
} from '../ProviderCredentialForm';

interface OnboardingStatusResponse {
  data?: {
    completed?: boolean;
    has_credentials?: boolean;
    completed_at?: string | null;
    categories?: Partial<
      Record<ProviderCategory, { has_credentials: boolean; count: number; available: boolean }>
    >;
  };
}

/** Per-category credential presence, as derived from `/onboarding/status`. */
export type OnboardingStatusCategories = Partial<
  Record<ProviderCategory, { has_credentials: boolean; count: number; available: boolean }>
>;

interface AiProviderResponse {
  data?: { provider?: { id?: string } };
}

/** Outcome of the server-side model sync run when an AI credential is saved. */
export interface AiModelSyncResult {
  success: boolean;
  deferred?: boolean;
  model_count: number;
  error: string | null;
  activated?: boolean;
  default?: boolean;
}

interface AiCredentialResponse {
  data?: { credential?: { id?: string }; model_sync?: AiModelSyncResult };
}

export interface AiCredentialCreated {
  id: string | null;
  modelSync: AiModelSyncResult | null;
}

interface GitProviderResponse {
  data?: { provider?: { id?: string } };
}

interface GitCredentialResponse {
  data?: { credential?: { id?: string } };
}

interface CompleteResponseEnvelope {
  data?: { onboarding_completed_at?: string | null };
  onboarding_completed_at?: string | null;
}

export interface CreateProviderViaProviderParams {
  providerType: ProviderTypeSlug;
  /** Display name attached to the created Provider record. */
  name: string;
  /**
   * Provider-level config (e.g. self-hosted Gitea/GitLab or AI API base URL). Sent as
   * `provider.api_base_url` — this configures the Provider, not the credential.
   */
  apiBaseUrl?: string;
  /** Git only: the provider's SSH endpoint, stored in its metadata. */
  ssh?: { host?: string; port?: number };
}

export interface CreateNamedCredentialParams {
  providerId: string;
  credentials: ProviderCredentialValues;
  /** Git only: `ssh_key` stores an SSH key (never the API default); default is a token. */
  authType?: 'personal_access_token' | 'ssh_key';
}

/** One provider-type entry of GET /git/providers/catalog (connection defaults). */
export interface GitProviderCatalogEntry {
  provider_type: string;
  name: string;
  api_base_url: string | null;
  web_base_url: string | null;
  ssh_host: string | null;
  ssh_port: number;
}

export interface CompleteOnboardingParams {
  providerCredentialId: string | null;
  providerType: ProviderTypeSlug | null;
}

/**
 * onboardingApi — singleton service object wrapping every HTTP call the
 * onboarding components make. Method return values match exactly what each
 * component previously read off the axios response.
 */
export const onboardingApi = {
  /**
   * GET `/onboarding/status`. Returns the per-category map the wizard reads via
   * `response.data?.data?.categories ?? {}`.
   */
  async getStatus(): Promise<OnboardingStatusCategories> {
    const response = await apiClient.get<OnboardingStatusResponse>('/onboarding/status');
    return response.data?.data?.categories ?? {};
  },

  /**
   * GET `/onboarding/status`: whether the account is past onboarding, either
   * stamped complete or already holding provider credentials. Drives the
   * OnboardingGate redirect.
   */
  async isComplete(): Promise<boolean> {
    const response = await apiClient.get<OnboardingStatusResponse>('/onboarding/status');
    const status = response.data?.data;
    return Boolean(status?.completed) || Boolean(status?.has_credentials);
  },

  /**
   * GET `/ai/providers/catalog`: the provider-type catalog that pre-fills the
   * AI provider details (name, base URL, default model) on type selection.
   */
  async getAiProviderCatalog(): Promise<AiProviderCatalog> {
    const response = await apiClient.get<{ data?: Partial<AiProviderCatalog> }>('/ai/providers/catalog');
    const data = response.data?.data;
    return { items: data?.items ?? [], known_capabilities: data?.known_capabilities ?? [] };
  },

  /**
   * AI category step 1: create a provider row for this entry. Each wizard entry
   * gets its own provider (matching git); `dedupe_name` has the server number the
   * name when a seeded catalog row already holds it. The Claude Code
   * local-sessions scope is never a target: the server refuses credentials on it.
   */
  async createAiProvider({
    providerType,
    name,
    apiBaseUrl,
  }: CreateProviderViaProviderParams): Promise<string | undefined> {
    const response = await apiClient.post<AiProviderResponse>('/ai/providers', {
      dedupe_name: true,
      provider: {
        provider_type: providerType,
        name,
        ...(apiBaseUrl ? { api_base_url: apiBaseUrl } : {}),
      },
    });
    return response.data?.data?.provider?.id;
  },

  /**
   * AI category step 2: create the credential under a provider. Returns the
   * derived credential id (`credential?.id ?? null`).
   */
  async createAiCredential({
    providerId,
    credentials,
  }: CreateNamedCredentialParams): Promise<AiCredentialCreated> {
    const response = await apiClient.post<AiCredentialResponse>(
      `/ai/providers/${providerId}/credentials`,
      {
        credential: {
          name: 'Onboarding',
          credentials,
          is_active: true,
          is_default: true,
        },
      }
    );
    return {
      id: response.data?.data?.credential?.id ?? null,
      modelSync: response.data?.data?.model_sync ?? null,
    };
  },

  /** Make a working AI provider the account default (POST `/ai/providers/:id/make_default`). */
  async setAiDefaultProvider(providerId: string): Promise<void> {
    await apiClient.post(`/ai/providers/${providerId}/make_default`);
  },

  /** Remove an AI provider the wizard created, with its credential (the server heals the default). */
  async deleteAiProvider(providerId: string): Promise<void> {
    await apiClient.delete(`/ai/providers/${providerId}`);
  },

  /**
   * Git category step 1: create the provider. Returns the created provider id
   * (or undefined — the caller throws when missing, matching prior behavior).
   * `apiBaseUrl`, when given, configures the self-hosted Gitea/GitLab
   * endpoint on the Provider record itself (`provider.api_base_url`) — the
   * base URL is provider config, not credential material.
   */
  async createGitProvider({
    providerType,
    name,
    apiBaseUrl,
    ssh,
  }: CreateProviderViaProviderParams): Promise<string | undefined> {
    const response = await apiClient.post<GitProviderResponse>('/git/providers', {
      provider: {
        provider_type: providerType,
        name,
        ...(apiBaseUrl ? { api_base_url: apiBaseUrl } : {}),
        ...(ssh?.host ? { metadata: { ssh } } : {}),
      },
    });
    return response.data?.data?.provider?.id;
  },

  /**
   * Git category step 2: create the credential under a provider. Returns the
   * derived credential id (`credential?.id ?? null`). `auth_type` is fixed to
   * `personal_access_token` — the only PAT-style flow the onboarding wizard
   * offers today (OAuth is a separate, non-onboarding flow).
   */
  async createGitCredential({
    providerId,
    credentials,
    authType = 'personal_access_token',
  }: CreateNamedCredentialParams): Promise<string | null> {
    const isSsh = authType === 'ssh_key';
    const response = await apiClient.post<GitCredentialResponse>(
      `/git/providers/${providerId}/credentials`,
      {
        credential: {
          name: isSsh ? 'Onboarding SSH key' : 'Onboarding',
          auth_type: authType,
          credentials,
          is_active: true,
          // An SSH key is clone/push access, never the API default.
          is_default: !isSsh,
        },
      }
    );
    return response.data?.data?.credential?.id ?? null;
  },

  /** GET `/git/providers/catalog`: per-type URL and SSH host/port defaults. */
  async getGitProviderCatalog(): Promise<GitProviderCatalogEntry[]> {
    const response = await apiClient.get<{ data?: { items?: GitProviderCatalogEntry[] } }>(
      '/git/providers/catalog'
    );
    return response.data?.data?.items ?? [];
  },

  /** Remove a git provider the wizard added, with its credentials. */
  async deleteGitProvider(providerId: string): Promise<void> {
    await apiClient.delete(`/git/providers/${providerId}`);
  },

  /**
   * POST `/onboarding/complete` to seed templates and stamp completion. The
   * wizard ignores the response body (only success/failure matters), so this
   * resolves to void.
   */
  async complete({ providerCredentialId, providerType }: CompleteOnboardingParams): Promise<void> {
    await apiClient.post<CompleteResponseEnvelope>('/onboarding/complete', {
      provider_credential_id: providerCredentialId,
      provider_type: providerType,
    });
  },
};

export default onboardingApi;

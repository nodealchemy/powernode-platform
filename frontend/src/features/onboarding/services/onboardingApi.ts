// Onboarding API service — consolidates the inline apiClient calls made by the
// onboarding feature components (FirstRunWizard).
//
// Behavior-preserving: each method uses the SAME apiClient module the components
// previously called inline, hits the SAME endpoint with the SAME payload, and
// unwraps the axios response EXACTLY as the components did — returning the value
// each component derived from `response.data`. This keeps the components' existing
// apiClient mocks (which assert call paths/args) intercepting unchanged.
import { apiClient } from '@/shared/services/apiClient';
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

/** `GET /ai/providers?provider_type=…` — used to resolve an existing provider before creating one. */
interface AiProviderIndexResponse {
  data?: { items?: Array<{ id?: string; provider_type?: string }> };
}

interface AiCredentialResponse {
  data?: { credential?: { id?: string } };
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
   * Provider-level config (e.g. self-hosted Gitea/GitLab base URL). Sent as
   * `provider.api_base_url` — this configures the Provider, not the credential.
   */
  apiBaseUrl?: string;
}

export interface CreateNamedCredentialParams {
  providerId: string;
  credentials: ProviderCredentialValues;
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
   * AI category step 1: resolve an existing provider of this type, or create
   * one. The catalog seeds a Provider per type ahead of onboarding, so a bare
   * POST here would create a duplicate missing required fields (422). Instead
   * GET `/ai/providers?provider_type=…` first and reuse `items[0].id` when
   * present; only fall through to create when none exists.
   */
  async createAiProvider({
    providerType,
    name,
  }: CreateProviderViaProviderParams): Promise<string | undefined> {
    const existing = await apiClient.get<AiProviderIndexResponse>('/ai/providers', {
      params: { provider_type: providerType },
    });
    const items = existing.data?.data?.items ?? [];
    if (items.length > 0) {
      return items[0]?.id;
    }

    const response = await apiClient.post<AiProviderResponse>('/ai/providers', {
      provider: {
        provider_type: providerType,
        name,
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
  }: CreateNamedCredentialParams): Promise<string | null> {
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
    return response.data?.data?.credential?.id ?? null;
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
  }: CreateProviderViaProviderParams): Promise<string | undefined> {
    const response = await apiClient.post<GitProviderResponse>('/git/providers', {
      provider: {
        provider_type: providerType,
        name,
        ...(apiBaseUrl ? { api_base_url: apiBaseUrl } : {}),
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
  }: CreateNamedCredentialParams): Promise<string | null> {
    const response = await apiClient.post<GitCredentialResponse>(
      `/git/providers/${providerId}/credentials`,
      {
        credential: {
          name: 'Onboarding',
          auth_type: 'personal_access_token',
          credentials,
          is_active: true,
          is_default: true,
        },
      }
    );
    return response.data?.data?.credential?.id ?? null;
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

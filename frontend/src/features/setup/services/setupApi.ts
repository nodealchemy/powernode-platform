// Setup wizard API client — talks to the registry-driven setup endpoints
// (Api::V1::SetupController). Mirrors the unwrap convention used elsewhere
// (onboardingApi / OnboardingGate): the server wraps payloads under `data`
// (render_success), so each method reads `response.data?.data ?? response.data`.
import apiClient from '@/shared/services/apiClient';

/** A single field within a step's schema (matches Setup::StepRegistry step `schema`). */
export interface SetupFieldDef {
  key: string;
  label: string;
  type: 'text' | 'password' | 'textarea';
  required?: boolean;
  placeholder?: string;
  helper?: string;
}

/** One setup step as annotated by the backend registry. */
export interface SetupStep {
  key: string;
  title: string;
  description?: string;
  order: number;
  required?: boolean;
  owner: string;
  /** Where this step's payload is POSTed (admin has its own endpoint). */
  endpoint?: string;
  /** Completion strategy hint (e.g. "user_exists"); informational for the client. */
  completion?: string;
  /** Field schema for simple steps; rich steps use a client component instead. */
  schema?: SetupFieldDef[];
  /** Client component id for rich steps (Phase 3+); absent for schema steps. */
  component?: string;
  completed: boolean;
  completed_at: string | null;
}

export interface SetupStatus {
  bootstrap_complete: boolean;
  pending: Array<{ owner: string; steps: SetupStep[] }>;
}

/** An extension present in this build, with its current enabled state. */
export interface SetupExtension {
  slug: string;
  version: string | null;
  enabled: boolean;
}

export interface CreateAdminParams {
  token: string;
  name?: string;
  email: string;
  password: string;
}

export interface CreateAdminResult {
  user: { id: string; email: string; name: string | null };
  account: { id: string; name: string | null };
  access_token: string;
  expires_at?: string;
}

interface Envelope<T> {
  data?: T;
}

/** Unwrap `response.data?.data ?? response.data` into the inner payload. */
const inner = <T,>(envelope: (Envelope<T> & Partial<T>) | undefined): T => {
  const env = envelope ?? {};
  return ((env as Envelope<T>).data ?? env) as T;
};

export const setupApi = {
  /**
   * GET /setup/status — publicly reachable. Anonymous callers get only
   * `bootstrap_complete`; authenticated admins also get per-account `pending`.
   */
  async getStatus(): Promise<SetupStatus> {
    const response = await apiClient.get<Envelope<SetupStatus> & Partial<SetupStatus>>('/setup/status');
    return inner<SetupStatus>(response.data);
  },

  /** GET /setup/steps — authenticated (system.admin). Ordered, completion-annotated. */
  async getSteps(): Promise<SetupStep[]> {
    const response = await apiClient.get<Envelope<{ steps: SetupStep[] }>>('/setup/steps');
    return inner<{ steps: SetupStep[] }>(response.data).steps ?? [];
  },

  /** POST /setup/steps/:key — persist one core step's payload, returns the re-annotated step. */
  async submitStep(key: string, payload: Record<string, string>): Promise<SetupStep> {
    const response = await apiClient.post<Envelope<{ step: SetupStep }>>(`/setup/steps/${key}`, payload);
    return inner<{ step: SetupStep }>(response.data).step;
  },

  /** GET /setup/extensions — extensions present in this build + enabled state. */
  async getExtensions(): Promise<SetupExtension[]> {
    const response = await apiClient.get<Envelope<{ extensions: SetupExtension[] }>>('/setup/extensions');
    return inner<{ extensions: SetupExtension[] }>(response.data).extensions ?? [];
  },

  /** POST /setup/extensions/:slug — toggle one extension (non-destructive). */
  async setExtension(slug: string, enabled: boolean): Promise<SetupExtension> {
    const response = await apiClient.post<Envelope<SetupExtension>>(`/setup/extensions/${slug}`, { enabled });
    return inner<SetupExtension>(response.data);
  },

  /** POST /setup/seed — run the idempotent seed wrapper (no-op in builds with no seeder). */
  async seed(): Promise<{ seeded: boolean; reason?: string }> {
    const response = await apiClient.post<Envelope<{ seeded: boolean; reason?: string }>>('/setup/seed', {});
    return inner<{ seeded: boolean; reason?: string }>(response.data);
  },

  /**
   * POST /setup/admin — UNAUTHENTICATED, one-time-token-gated. Creates the first
   * admin and establishes a session (server sets the refresh cookie); the caller
   * then restores the session via the standard refreshAccessToken/getCurrentUser path.
   */
  async createAdmin(params: CreateAdminParams): Promise<CreateAdminResult> {
    const response = await apiClient.post<Envelope<CreateAdminResult>>('/setup/admin', params);
    return inner<CreateAdminResult>(response.data);
  },
};

export default setupApi;

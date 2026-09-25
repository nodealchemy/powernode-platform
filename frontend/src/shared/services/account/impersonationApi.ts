import { api } from '@/shared/services/api';

// Types
export interface ImpersonationRequest {
  user_id: string;
  reason?: string;
}

export interface UserSummary {
  id: string;
  email: string;
  full_name: string;
  roles: string[];
  permissions?: string[];
  status: string;
  last_login_at?: string;
  account?: {
    id: string;
    name: string;
    status: string;
  };
}

export interface ImpersonationSession {
  id: string;
  session_token: string;
  impersonator: UserSummary;
  impersonated_user: UserSummary;
  reason?: string;
  started_at: string;
  ended_at?: string;
  duration?: number;
  active: boolean;
  expired: boolean;
}

export interface ImpersonationStartResponse {
  token: string;
  target_user: UserSummary;
  expires_at: string;
}

export interface ImpersonationValidation {
  valid: boolean;
  session?: ImpersonationSession;
  expires_at?: string;
  message?: string;
}

// Unwraps the server's success envelope ({ success, data, message? } --
// api_response.rb): axios's `response.data` IS that envelope, so the payload is
// one level further in. A `success: false` envelope becomes a thrown Error
// carrying the server's own `error` label.
const unwrap = <T>(envelope: { success?: boolean; data?: T; error?: string }): T => {
  if (!envelope?.success) {
    throw new Error(envelope?.error || 'Impersonation request failed');
  }
  return envelope.data as T;
};

// The one client for /impersonations. It stays in shared because the auth
// slice (shared) owns the impersonation session; the user tables dispatch that
// slice's thunks rather than calling this directly.
export const impersonationApi = {
  async startImpersonation(request: ImpersonationRequest): Promise<ImpersonationStartResponse> {
    const response = await api.post('/impersonations', request);
    return unwrap<ImpersonationStartResponse>(response.data);
  },

  async stopImpersonation(sessionToken: string): Promise<{ duration: number }> {
    const response = await api.delete('/impersonations', {
      data: { session_token: sessionToken }
    });
    return unwrap<{ duration: number }>(response.data);
  },

  // The server answers 200 with data.valid false for a bad token; only a
  // transport or envelope failure throws.
  async validateToken(token: string): Promise<ImpersonationValidation> {
    const response = await api.post('/impersonations/validate', { token });
    return unwrap<ImpersonationValidation>(response.data);
  }
};

export default impersonationApi;

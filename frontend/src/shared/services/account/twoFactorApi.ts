import { api } from '@/shared/services/api';
import type { AuthUser } from '@/features/account/auth/services/authAPI';

// Account type extracted from AuthUser's nested account property
type AccountInfo = AuthUser['account'];

export interface TwoFactorSetupResponse {
  success: boolean;
  message: string;
  qr_code?: string;
  manual_entry_key?: string;
  backup_codes?: string[];
  error?: string;
}

export interface TwoFactorStatusResponse {
  success: boolean;
  two_factor_enabled: boolean;
  backup_codes_count: number;
  enabled_at?: string;
}

export interface TwoFactorVerificationResponse {
  success: boolean;
  message?: string;
  error?: string;
}

export interface BackupCodesResponse {
  success: boolean;
  backup_codes: string[];
  generated_at: string;
  message?: string;
  error?: string;
}

export interface LoginWith2FAResponse {
  success: boolean;
  requires_2fa?: boolean;
  verification_token?: string;
  message?: string;
  user?: AuthUser;
  account?: AccountInfo;
  access_token?: string;
  refresh_token?: string;
  expires_at?: string;
  warning?: string;
  error?: string;
}

export interface Verify2FAResponse {
  success: boolean;
  user?: AuthUser;
  account?: AccountInfo;
  access_token?: string;
  refresh_token?: string;
  expires_at?: string;
  warning?: string;
  error?: string;
}

// Every /two_factor reply is wrapped by ApiResponse#render_success /
// #render_error (server/app/controllers/concerns/api_response.rb) as
// { success, data: {...}, message? } on success or { success: false, error }
// on failure — `api` (shared/services/api.ts) does not unwrap this envelope.
// Unwrap it here, once, so each method below returns the flat, typed shape
// its interface already declares.
interface TwoFactorEnvelope<T> {
  success: boolean;
  data?: T;
  error?: string;
  message?: string;
}

function unwrapTwoFactorEnvelope<T extends object, R extends { success: boolean }>(
  envelope: TwoFactorEnvelope<T>
): R {
  return {
    success: envelope.success,
    error: envelope.error,
    message: envelope.message,
    ...(envelope.data ?? {})
  } as unknown as R;
}

export const twoFactorApi = {
  // Check current 2FA status
  async getStatus(): Promise<TwoFactorStatusResponse> {
    const response = await api.get<TwoFactorEnvelope<{
      two_factor_enabled: boolean;
      backup_codes_count: number;
      enabled_at?: string;
    }>>('/two_factor/status');
    return unwrapTwoFactorEnvelope(response.data);
  },

  // Enable 2FA and get setup information
  async enable(): Promise<TwoFactorSetupResponse> {
    const response = await api.post<TwoFactorEnvelope<{
      qr_code: string;
      manual_entry_key: string;
      backup_codes: string[];
    }>>('/two_factor/enable');
    return unwrapTwoFactorEnvelope(response.data);
  },

  // Verify 2FA setup with a token
  async verifySetup(token: string): Promise<TwoFactorVerificationResponse> {
    const response = await api.post<TwoFactorEnvelope<Record<string, never>>>('/two_factor/verify_setup', {
      token
    });
    return unwrapTwoFactorEnvelope(response.data);
  },

  // Disable 2FA
  async disable(): Promise<TwoFactorVerificationResponse> {
    const response = await api.delete<TwoFactorEnvelope<Record<string, never>>>('/two_factor/disable');
    return unwrapTwoFactorEnvelope(response.data);
  },

  // Get backup codes
  async getBackupCodes(): Promise<BackupCodesResponse> {
    const response = await api.get<TwoFactorEnvelope<{
      backup_codes: string[];
      generated_at: string;
    }>>('/two_factor/backup_codes');
    return unwrapTwoFactorEnvelope(response.data);
  },

  // Regenerate backup codes
  async regenerateBackupCodes(): Promise<BackupCodesResponse> {
    const response = await api.post<TwoFactorEnvelope<{
      backup_codes: string[];
    }>>('/two_factor/regenerate_backup_codes');
    return unwrapTwoFactorEnvelope(response.data);
  },

  // Verify 2FA code during login.
  // Traced (see LoginPage.test.tsx "two-factor authentication flow"): /auth/verify-2fa
  // (server/app/controllers/api/v1/auth/sessions_controller.rb ~256) wraps its reply
  // the same way /two_factor does, so `response.user`/`.account`/`.access_token` here
  // are always undefined — but nothing reads them. TwoFactorVerification.tsx only
  // checks the envelope's top-level `success`/`error` (unaffected by the nesting,
  // since render_success/render_error put those at the top level) and forwards the
  // raw response to onSuccess; LoginPage.handle2FASuccess ignores that payload and
  // re-fetches the user via getCurrentUser() instead. So this does NOT block 2FA
  // login today. Left unwrapped deliberately to avoid touching the login/auth-state
  // path for a field nothing consumes; revisit only if a future caller starts
  // reading these fields directly.
  async verifyLogin(verificationToken: string, code: string): Promise<Verify2FAResponse> {
    const response = await api.post('/auth/verify-2fa', {
      verification_token: verificationToken,
      code
    });
    return response.data;
  }
};

export default twoFactorApi;
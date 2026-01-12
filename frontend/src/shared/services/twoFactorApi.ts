import { api } from '@/shared/services/api';
import type { AuthUser } from '@/features/auth/services/authAPI';

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

export const twoFactorApi = {
  // Check current 2FA status
  async getStatus(): Promise<TwoFactorStatusResponse> {
    const response = await api.get('/api/v1/two_factor/status');
    return response.data;
  },

  // Enable 2FA and get setup information
  async enable(): Promise<TwoFactorSetupResponse> {
    const response = await api.post('/api/v1/two_factor/enable');
    return response.data;
  },

  // Verify 2FA setup with a token
  async verifySetup(token: string): Promise<TwoFactorVerificationResponse> {
    const response = await api.post('/api/v1/two_factor/verify_setup', {
      token
    });
    return response.data;
  },

  // Disable 2FA
  async disable(): Promise<TwoFactorVerificationResponse> {
    const response = await api.delete('/api/v1/two_factor/disable');
    return response.data;
  },

  // Get backup codes
  async getBackupCodes(): Promise<BackupCodesResponse> {
    const response = await api.get('/api/v1/two_factor/backup_codes');
    return response.data;
  },

  // Regenerate backup codes
  async regenerateBackupCodes(): Promise<BackupCodesResponse> {
    const response = await api.post('/api/v1/two_factor/regenerate_backup_codes');
    return response.data;
  },

  // Verify 2FA code during login
  async verifyLogin(verificationToken: string, code: string): Promise<Verify2FAResponse> {
    const response = await api.post('/api/v1/auth/verify-2fa', {
      verification_token: verificationToken,
      code
    });
    return response.data;
  }
};

export default twoFactorApi;
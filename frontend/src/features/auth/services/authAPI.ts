import { api } from '@/shared/services/api';

export interface LoginCredentials {
  email: string;
  password: string;
}

export interface RegisterData {
  email: string;
  password: string;
  first_name: string;
  last_name: string;
  account_name: string;
  plan_id?: string;
  billing_cycle?: string;
}

export interface AuthResponse {
  success: boolean;
  user?: {
    id: string;
    email: string;
    first_name: string;
    last_name: string;
    roles: string[];
    permissions: string[];  // Added permissions array from JWT
    status: string;
    email_verified: boolean;
    account: {
      id: string;
      name: string;
      status: string;
    };
  };
  access_token?: string;
  refresh_token?: string;
  expires_at?: string;
  refresh_expires_at?: string;  // Added for JWT refresh token expiration
  warning?: string;
  message?: string;
  error?: string;
  requires_2fa?: boolean;
  verification_token?: string;
}

export interface RefreshTokenResponse {
  success: boolean;
  access_token: string;
  refresh_token: string;
  expires_at: string;
  refresh_expires_at?: string;
}

class AuthAPI {
  async login(credentials: LoginCredentials) {
    return api.post<AuthResponse>('/auth/login', credentials);
  }

  async register(userData: RegisterData) {
    return api.post<AuthResponse>('/auth/register', userData);
  }

  async logout() {
    return api.post('/auth/logout');
  }

  async refreshToken(refreshToken: string) {
    return api.post<RefreshTokenResponse>('/auth/refresh', {
      refresh_token: refreshToken,
    });
  }

  async getCurrentUser() {
    return api.get('/auth/me');
  }

  async forgotPassword(email: string) {
    return api.post('/auth/forgot-password', { email });
  }

  async resetPassword(token: string, password: string) {
    return api.post('/auth/reset-password', { 
      token, 
      password 
    });
  }

  async verifyEmail(token: string) {
    return api.post('/auth/verify-email', { token });
  }

  async resendVerification() {
    return api.post('/auth/resend-verification');
  }

  async verify2FA(verificationToken: string, code: string) {
    return api.post<AuthResponse>('/auth/verify-2fa', {
      verification_token: verificationToken,
      code: code,
    });
  }
}

export const authAPI = new AuthAPI();
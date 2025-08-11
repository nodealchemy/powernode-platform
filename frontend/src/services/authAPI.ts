import { api } from './api';

export interface LoginCredentials {
  email: string;
  password: string;
}

export interface RegisterData {
  email: string;
  password: string;
  firstName: string;
  lastName: string;
  accountName: string;
  planId?: string;
  billingCycle?: string;
}

export interface AuthResponse {
  user: {
    id: string;
    email: string;
    firstName: string;
    lastName: string;
    role: string;
    status: string;
    emailVerified: boolean;
    account: {
      id: string;
      name: string;
      status: string;
    };
  };
  access_token: string;
  refresh_token: string;
}

export interface RefreshTokenResponse {
  access_token: string;
  refresh_token: string;
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
}

export const authAPI = new AuthAPI();
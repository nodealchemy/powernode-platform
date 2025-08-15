import { api } from './api';

// Types
export interface ImpersonationRequest {
  user_id: string;
  reason?: string;
}

export interface UserSummary {
  id: string;
  email: string;
  full_name: string;
  role: string;
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

export interface ApiResponse<T> {
  success: boolean;
  data?: T;
  message?: string;
  error?: string;
}

// API functions
export const impersonationApi = {
  // Start impersonating a user
  async startImpersonation(request: ImpersonationRequest): Promise<ApiResponse<ImpersonationStartResponse>> {
    try {
      const response = await api.post('/impersonations', request);
      return response.data;
    } catch (error: any) {
      throw error;
    }
  },

  // Stop impersonation
  async stopImpersonation(sessionToken: string): Promise<ApiResponse<{ duration: number }>> {
    try {
      const response = await api.delete('/impersonations', {
        data: { session_token: sessionToken }
      });
      return response.data;
    } catch (error: any) {
      throw error;
    }
  },

  // Get active impersonation sessions
  async getActiveSessions(): Promise<ApiResponse<ImpersonationSession[]>> {
    try {
      const response = await api.get('/impersonations');
      return response.data;
    } catch (error: any) {
      throw error;
    }
  },

  // Get impersonation history
  async getHistory(limit?: number): Promise<ApiResponse<ImpersonationSession[]>> {
    try {
      const response = await api.get('/impersonations/history', { 
        params: { limit } 
      });
      return response.data;
    } catch (error: any) {
      throw error;
    }
  },

  // Get users available for impersonation
  async getImpersonatableUsers(): Promise<ApiResponse<UserSummary[]>> {
    try {
      const response = await api.get('/impersonations/users');
      return response.data;
    } catch (error: any) {
      throw error;
    }
  },

  // Validate impersonation token
  async validateToken(token: string): Promise<ApiResponse<{
    session?: ImpersonationSession;
    expires_at?: string;
  }> & {
    valid?: boolean;
  }> {
    try {
      const response = await api.post('/impersonations/validate', { token });
      return response.data;
    } catch (error: any) {
      throw error;
    }
  }
};

export default impersonationApi;
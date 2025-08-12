import { api } from './api';

export interface Invitation {
  id: string;
  email: string;
  role: string;
  status: 'pending' | 'accepted' | 'expired' | 'canceled';
  invited_by: string;
  invited_at: string;
  expires_at: string;
  account_id: string;
  token: string;
  created_at: string;
  updated_at: string;
}

export interface InviteUserRequest {
  email: string;
  role: string;
  message?: string;
}

export interface ApiResponse<T> {
  success: boolean;
  data: T;
  message?: string;
  errors?: string[];
}

class InvitationsApi {
  /**
   * Get all invitations for the current account
   */
  async getAccountInvitations(accountId?: string): Promise<ApiResponse<Invitation[]>> {
    try {
      const url = accountId 
        ? `/api/v1/accounts/${accountId}/invitations`
        : '/api/v1/invitations';
      
      const response = await api.get(url);
      return {
        success: true,
        data: response.data
      };
    } catch (error: any) {
      return {
        success: false,
        data: [],
        message: error.response?.data?.message || 'Failed to fetch invitations',
        errors: error.response?.data?.errors
      };
    }
  }

  /**
   * Send a new invitation
   */
  async inviteUser(request: InviteUserRequest, accountId?: string): Promise<ApiResponse<Invitation>> {
    try {
      const url = accountId 
        ? `/api/v1/accounts/${accountId}/invitations`
        : '/api/v1/invitations';
        
      const response = await api.post(url, request);
      return {
        success: true,
        data: response.data,
        message: 'Invitation sent successfully'
      };
    } catch (error: any) {
      return {
        success: false,
        data: {} as Invitation,
        message: error.response?.data?.message || 'Failed to send invitation',
        errors: error.response?.data?.errors
      };
    }
  }

  /**
   * Resend an existing invitation
   */
  async resendInvitation(invitationId: string): Promise<ApiResponse<Invitation>> {
    try {
      const response = await api.post(`/api/v1/invitations/${invitationId}/resend`);
      return {
        success: true,
        data: response.data,
        message: 'Invitation resent successfully'
      };
    } catch (error: any) {
      return {
        success: false,
        data: {} as Invitation,
        message: error.response?.data?.message || 'Failed to resend invitation',
        errors: error.response?.data?.errors
      };
    }
  }

  /**
   * Cancel a pending invitation
   */
  async cancelInvitation(invitationId: string): Promise<ApiResponse<boolean>> {
    try {
      await api.delete(`/api/v1/invitations/${invitationId}`);
      return {
        success: true,
        data: true,
        message: 'Invitation canceled successfully'
      };
    } catch (error: any) {
      return {
        success: false,
        data: false,
        message: error.response?.data?.message || 'Failed to cancel invitation',
        errors: error.response?.data?.errors
      };
    }
  }

  /**
   * Accept an invitation (used by invited user)
   */
  async acceptInvitation(token: string, userData: {
    first_name: string;
    last_name: string;
    password: string;
    password_confirmation: string;
  }): Promise<ApiResponse<any>> {
    try {
      const response = await api.post(`/api/v1/invitations/${token}/accept`, userData);
      return {
        success: true,
        data: response.data,
        message: 'Invitation accepted successfully'
      };
    } catch (error: any) {
      return {
        success: false,
        data: null,
        message: error.response?.data?.message || 'Failed to accept invitation',
        errors: error.response?.data?.errors
      };
    }
  }

  /**
   * Get invitation details by token (for acceptance page)
   */
  async getInvitationByToken(token: string): Promise<ApiResponse<Invitation>> {
    try {
      const response = await api.get(`/api/v1/invitations/${token}`);
      return {
        success: true,
        data: response.data
      };
    } catch (error: any) {
      return {
        success: false,
        data: {} as Invitation,
        message: error.response?.data?.message || 'Invitation not found or expired',
        errors: error.response?.data?.errors
      };
    }
  }

  /**
   * Update invitation role (before it's accepted)
   */
  async updateInvitationRole(invitationId: string, role: string): Promise<ApiResponse<Invitation>> {
    try {
      const response = await api.patch(`/api/v1/invitations/${invitationId}`, { role });
      return {
        success: true,
        data: response.data,
        message: 'Invitation updated successfully'
      };
    } catch (error: any) {
      return {
        success: false,
        data: {} as Invitation,
        message: error.response?.data?.message || 'Failed to update invitation',
        errors: error.response?.data?.errors
      };
    }
  }
}

export const invitationsApi = new InvitationsApi();
export default invitationsApi;
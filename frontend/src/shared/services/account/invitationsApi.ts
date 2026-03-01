import { api } from '@/shared/services/api';

// Type for API error response data
interface ApiErrorResponseData {
  message?: string;
  errors?: string[];
}

// Helper function to safely extract error information
const getErrorInfo = (error: unknown, defaultMessage: string) => {
  let errorMessage = defaultMessage;
  let errors: string[] | undefined = undefined;

  if (error && typeof error === 'object' && 'response' in error && error.response &&
      typeof error.response === 'object' && 'data' in error.response && error.response.data &&
      typeof error.response.data === 'object') {
    const responseData = error.response.data as ApiErrorResponseData;
    errorMessage = responseData.message || errorMessage;
    errors = responseData.errors;
  }

  return { errorMessage, errors };
};

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

export interface InvitationsApiResponse<T> {
  success: boolean;
  data: T;
  message?: string;
  errors?: string[];
}

class InvitationsApi {
  /**
   * Get all invitations for the current account
   */
  async getAccountInvitations(accountId?: string): Promise<InvitationsApiResponse<Invitation[]>> {
    try {
      const url = accountId 
        ? `/api/v1/accounts/${accountId}/invitations`
        : '/api/v1/invitations';
      
      const response = await api.get(url);
      return {
        success: true,
        data: response.data
      };
    } catch (error) {
      const { errorMessage, errors } = getErrorInfo(error, 'Failed to fetch invitations');

      return {
        success: false,
        data: [],
        message: errorMessage,
        errors
      };
    }
  }

  /**
   * Send a new invitation
   */
  async inviteUser(request: InviteUserRequest, accountId?: string): Promise<InvitationsApiResponse<Invitation>> {
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
    } catch (error) {
      const { errorMessage, errors } = getErrorInfo(error, 'Failed to send invitation');
      return {
        success: false,
        data: {} as Invitation,
        message: errorMessage,
        errors
      };
    }
  }

  /**
   * Resend an existing invitation
   */
  async resendInvitation(invitationId: string): Promise<InvitationsApiResponse<Invitation>> {
    try {
      const response = await api.post(`/api/v1/invitations/${invitationId}/resend`);
      return {
        success: true,
        data: response.data,
        message: 'Invitation resent successfully'
      };
    } catch (error) {
      const { errorMessage, errors } = getErrorInfo(error, 'Failed to resend invitation');
      return {
        success: false,
        data: {} as Invitation,
        message: errorMessage,
        errors
      };
    }
  }

  /**
   * Cancel a pending invitation
   */
  async cancelInvitation(invitationId: string): Promise<InvitationsApiResponse<boolean>> {
    try {
      await api.delete(`/api/v1/invitations/${invitationId}`);
      return {
        success: true,
        data: true,
        message: 'Invitation canceled successfully'
      };
    } catch (error) {
      const { errorMessage, errors } = getErrorInfo(error, 'Failed to cancel invitation');
      return {
        success: false,
        data: false,
        message: errorMessage,
        errors
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
  }): Promise<InvitationsApiResponse<{ user: { id: string; email: string } } | null>> {
    try {
      const response = await api.post(`/api/v1/invitations/${token}/accept`, userData);
      return {
        success: true,
        data: response.data,
        message: 'Invitation accepted successfully'
      };
    } catch (error) {
      const { errorMessage, errors } = getErrorInfo(error, 'Failed to accept invitation');
      return {
        success: false,
        data: null,
        message: errorMessage,
        errors
      };
    }
  }

  /**
   * Get invitation details by token (for acceptance page)
   */
  async getInvitationByToken(token: string): Promise<InvitationsApiResponse<Invitation>> {
    try {
      const response = await api.get(`/api/v1/invitations/${token}`);
      return {
        success: true,
        data: response.data
      };
    } catch (error) {
      return {
        success: false,
        data: {} as Invitation,
        ...(() => {
          const { errorMessage, errors } = getErrorInfo(error, 'Invitation not found or expired');
          return { message: errorMessage, errors };
        })()
      };
    }
  }

  /**
   * Update invitation role (before it's accepted)
   */
  async updateInvitationRole(invitationId: string, role: string): Promise<InvitationsApiResponse<Invitation>> {
    try {
      const response = await api.patch(`/api/v1/invitations/${invitationId}`, { role });
      return {
        success: true,
        data: response.data,
        message: 'Invitation updated successfully'
      };
    } catch (error) {
      return {
        success: false,
        data: {} as Invitation,
        ...(() => {
          const { errorMessage, errors } = getErrorInfo(error, 'Failed to update invitation');
          return { message: errorMessage, errors };
        })()
      };
    }
  }
}

export const invitationsApi = new InvitationsApi();
export default invitationsApi;
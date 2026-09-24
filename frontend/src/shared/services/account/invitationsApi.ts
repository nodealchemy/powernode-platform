import { api } from '@/shared/services/api';

// Type for the server's real error envelope: { success: false, error: "<label>",
// code?, details? } (server/app/controllers/concerns/api_response.rb). `message`/
// `errors` are kept for backward compatibility with any endpoint that still
// sends the older shape, but the real one is `error`/`details`.
interface ApiErrorResponseData {
  error?: string;
  details?: unknown;
  message?: string;
  errors?: string[];
}

// Helper function to safely extract error information from the server's
// real error envelope.
const getErrorInfo = (error: unknown, defaultMessage: string) => {
  let errorMessage = defaultMessage;
  let errors: string[] | undefined = undefined;

  if (error && typeof error === 'object' && 'response' in error && error.response &&
      typeof error.response === 'object' && 'data' in error.response && error.response.data &&
      typeof error.response.data === 'object') {
    const responseData = error.response.data as ApiErrorResponseData;
    errorMessage = responseData.error || responseData.message || errorMessage;

    if (Array.isArray(responseData.errors)) {
      errors = responseData.errors;
    } else if (
      responseData.details &&
      typeof responseData.details === 'object' &&
      'errors' in responseData.details
    ) {
      const detailErrors = (responseData.details as { errors?: unknown }).errors;
      errors = Array.isArray(detailErrors)
        ? detailErrors.filter((e): e is string => typeof e === 'string')
        : undefined;
    } else if (typeof responseData.details === 'string') {
      errors = [ responseData.details ];
    }
  }

  return { errorMessage, errors };
};

// Unwraps the server's standard success envelope ({ success, data, meta?,
// message? } -- api_response.rb). `api`'s axios response `.data` IS that
// envelope, not the resource itself, so every method below needs this
// second unwrap to reach the real payload. Doing it in one place avoids
// each method reaching into `response.data.data` by hand (and a prior
// version of this file got that wrong everywhere, returning the whole
// envelope as if it were the resource -- harmless for callers that only
// check `.success`, but AcceptInvitationPage reads `invitation.status`,
// which was always `undefined` as a result).
const unwrapEnvelope = <T>(axiosResponseData: unknown): T => {
  if (axiosResponseData && typeof axiosResponseData === 'object' && 'data' in axiosResponseData) {
    return (axiosResponseData as { data: T }).data;
  }
  return axiosResponseData as T;
};

// Matches Api::V1::InvitationsController#invitation_json (the authenticated,
// account-scoped shape -- GET/POST/PATCH /invitations, /invitations/:id).
export interface Invitation {
  id: string;
  email: string;
  first_name: string;
  last_name: string;
  status: 'pending' | 'accepted' | 'expired' | 'cancelled';
  role_names: string[];
  expires_at: string;
  accepted_at: string | null;
  inviter: {
    id: string;
    name: string;
    email: string;
  };
  created_at: string;
  updated_at: string;
  // Only present on #create's response (the invite email link needs it once).
  token?: string;
}

// The PUBLIC, token-only lookup endpoint (GET /invitations/lookup) returns a
// deliberately smaller shape than `Invitation` above -- no id, no token, no
// other invitations -- see Api::V1::InvitationsController#lookup. A
// non-pending or non-existent token never reaches this shape; it comes back
// as an error response instead (404/410), so there is no `status` field
// here to check.
export interface PublicInvitationLookup {
  email: string;
  role_names: string[];
  expires_at: string;
  account: { name: string };
  inviter: { name: string };
}

// Matches Api::V1::InvitationsController#invitation_params exactly: the
// server requires `invitation` params (`params.require(:invitation)`), and
// `Invitation` validates `first_name`/`last_name` presence -- there is no
// `role` (singular) or `message` field anywhere in the real contract.
export interface InviteUserRequest {
  email: string;
  first_name: string;
  last_name: string;
  role_names: string[];
}

export interface InvitationsApiResponse<T> {
  success: boolean;
  data: T;
  message?: string;
  errors?: string[];
}

class InvitationsApi {
  /**
   * Get all invitations for the current account. The server scopes
   * #index to `current_user.account` itself -- there is no
   * /accounts/:id/invitations route (accounts only nests :delegations) --
   * so there is no accountId to pass here.
   */
  async getAccountInvitations(): Promise<InvitationsApiResponse<Invitation[]>> {
    try {
      const response = await api.get('/invitations');
      return {
        success: true,
        data: unwrapEnvelope<Invitation[]>(response.data)
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
   * Send a new invitation. Same account-scoping note as
   * getAccountInvitations above -- no accountId. `invitation_params`
   * requires the body wrapped under `invitation` (`params.require(:invitation)`).
   */
  async inviteUser(request: InviteUserRequest): Promise<InvitationsApiResponse<Invitation>> {
    try {
      const response = await api.post('/invitations', { invitation: request });
      return {
        success: true,
        data: unwrapEnvelope<Invitation>(response.data),
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
      const response = await api.post(`/invitations/${invitationId}/resend`);
      return {
        success: true,
        data: unwrapEnvelope<Invitation>(response.data),
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
      await api.delete(`/invitations/${invitationId}`);
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
   * Accept an invitation (used by invited user). #accept is a COLLECTION
   * route (POST /invitations/accept, not a member route) -- the token
   * identifies the invitation, so it travels in the body, not the URL.
   */
  async acceptInvitation(token: string, userData: {
    first_name: string;
    last_name: string;
    password: string;
    password_confirmation: string;
  }): Promise<InvitationsApiResponse<{ user: { id: string; email: string } } | null>> {
    try {
      const response = await api.post('/invitations/accept', { token, ...userData });
      return {
        success: true,
        data: unwrapEnvelope<{ user: { id: string; email: string } }>(response.data),
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
   * Get invitation details by token (for the acceptance page). Public,
   * unauthenticated lookup -- the invitee has no account yet -- so this
   * hits the token-only collection route, never the authenticated
   * `show` (GET /invitations/:id), which requires a session AND scopes to
   * the CALLER's account.
   */
  async getInvitationByToken(token: string): Promise<InvitationsApiResponse<PublicInvitationLookup>> {
    try {
      const response = await api.get(`/invitations/lookup?token=${encodeURIComponent(token)}`);
      return {
        success: true,
        data: unwrapEnvelope<PublicInvitationLookup>(response.data)
      };
    } catch (error) {
      return {
        success: false,
        data: {} as PublicInvitationLookup,
        ...(() => {
          const { errorMessage, errors } = getErrorInfo(error, 'Invitation not found or expired');
          return { message: errorMessage, errors };
        })()
      };
    }
  }

  /**
   * Update invitation role (before it's accepted). `update_params` permits
   * `role_names: []` (an array) wrapped under `invitation`, same as create
   * -- there is no singular `role` field in the real contract.
   */
  async updateInvitationRole(invitationId: string, roleNames: string[]): Promise<InvitationsApiResponse<Invitation>> {
    try {
      const response = await api.patch(`/invitations/${invitationId}`, { invitation: { role_names: roleNames } });
      return {
        success: true,
        data: unwrapEnvelope<Invitation>(response.data),
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

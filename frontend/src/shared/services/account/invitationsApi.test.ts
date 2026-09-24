import { invitationsApi } from './invitationsApi';

// invitationsApi calls `api` (@/shared/services/api), whose baseURL is
// already '/api/v1' (api.ts getAPIBaseURL default). A literal '/api/v1'
// prefix on top of that baseURL produced /api/v1/api/v1/... and 404d every
// invitation endpoint (fc-01).
//
// These mocks resolve with the REAL server envelope
// ({ success, data, meta?, message? } -- api_response.rb), not the bare
// resource: axios's own `response.data` IS that envelope, and
// invitationsApi must unwrap it a second time to reach the actual payload.
// A mock that skips the envelope (as an earlier version of this file did)
// can't catch a missing unwrap.
const mockGet = jest.fn();
const mockPost = jest.fn();
const mockPatch = jest.fn();
const mockDelete = jest.fn();

jest.mock('@/shared/services/api', () => ({
  __esModule: true,
  api: {
    get: (...args: unknown[]) => mockGet(...args),
    post: (...args: unknown[]) => mockPost(...args),
    patch: (...args: unknown[]) => mockPatch(...args),
    delete: (...args: unknown[]) => mockDelete(...args),
  },
}));

const envelope = <T>(data: T) => ({ data: { success: true, data } });

beforeEach(() => {
  mockGet.mockReset();
  mockPost.mockReset();
  mockPatch.mockReset();
  mockDelete.mockReset();
});

describe('invitationsApi', () => {
  it('getAccountInvitations hits /invitations — the server scopes #index to the current account, no :id route exists', async () => {
    mockGet.mockResolvedValueOnce(envelope([]));
    const result = await invitationsApi.getAccountInvitations();
    expect(mockGet).toHaveBeenCalledWith('/invitations');
    expect(result.data).toEqual([]);
  });

  it('getAccountInvitations unwraps the server envelope to the real invitation array', async () => {
    const invitation = { id: 'inv-1', email: 'a@b.com', status: 'pending' };
    mockGet.mockResolvedValueOnce(envelope([ invitation ]));
    const result = await invitationsApi.getAccountInvitations();
    expect(result.data).toEqual([ invitation ]);
  });

  it('inviteUser posts to /invitations wrapped under `invitation` — no accountId, no /accounts/:id/invitations route exists', async () => {
    mockPost.mockResolvedValueOnce(envelope({ id: 'inv-1' }));
    const request = {
      email: 'a@b.com',
      first_name: 'Jane',
      last_name: 'Doe',
      role_names: [ 'member' ],
    };
    await invitationsApi.inviteUser(request);
    expect(mockPost).toHaveBeenCalledWith('/invitations', { invitation: request });
  });

  it('resendInvitation posts to /invitations/:id/resend', async () => {
    mockPost.mockResolvedValueOnce(envelope({ id: 'inv-1' }));
    await invitationsApi.resendInvitation('inv-1');
    expect(mockPost).toHaveBeenCalledWith('/invitations/inv-1/resend');
  });

  it('cancelInvitation deletes /invitations/:id', async () => {
    mockDelete.mockResolvedValueOnce({});
    const result = await invitationsApi.cancelInvitation('inv-1');
    expect(mockDelete).toHaveBeenCalledWith('/invitations/inv-1');
    expect(result.data).toBe(true);
  });

  it('acceptInvitation posts to /invitations/accept (a COLLECTION route) with the token in the body', async () => {
    mockPost.mockResolvedValueOnce(envelope({ user: { id: 'u-1', email: 'a@b.com' } }));
    const userData = {
      first_name: 'A',
      last_name: 'B',
      password: 'pw',
      password_confirmation: 'pw',
    };
    const result = await invitationsApi.acceptInvitation('tok-1', userData);
    expect(mockPost).toHaveBeenCalledWith('/invitations/accept', { token: 'tok-1', ...userData });
    expect(result.data).toEqual({ user: { id: 'u-1', email: 'a@b.com' } });
  });

  it('getInvitationByToken gets the PUBLIC /invitations/lookup route, never the authenticated /invitations/:token', async () => {
    const lookup = {
      email: 'invitee@example.com',
      role_names: [ 'member' ],
      expires_at: '2026-01-08T00:00:00Z',
      account: { name: 'Acme' },
      inviter: { name: 'Jane Doe' },
    };
    mockGet.mockResolvedValueOnce(envelope(lookup));

    const result = await invitationsApi.getInvitationByToken('tok-1');

    expect(mockGet).toHaveBeenCalledWith('/invitations/lookup?token=tok-1');
    expect(result.data).toEqual(lookup);
  });

  it('getInvitationByToken URL-encodes the token', async () => {
    mockGet.mockResolvedValueOnce(envelope({}));
    await invitationsApi.getInvitationByToken('tok/with special+chars');
    expect(mockGet).toHaveBeenCalledWith(
      `/invitations/lookup?token=${encodeURIComponent('tok/with special+chars')}`
    );
  });

  it('getInvitationByToken surfaces the real server error message on a non-2xx (e.g. expired/not-found)', async () => {
    mockGet.mockRejectedValueOnce({
      response: { status: 410, data: { success: false, error: 'Invitation has expired', code: 'BAD_REQUEST' } },
    });

    const result = await invitationsApi.getInvitationByToken('tok-1');

    expect(result.success).toBe(false);
    expect(result.message).toBe('Invitation has expired');
  });

  it('updateInvitationRole patches /invitations/:id with role_names wrapped under `invitation`', async () => {
    mockPatch.mockResolvedValueOnce(envelope({ id: 'inv-1', role_names: [ 'admin' ] }));
    await invitationsApi.updateInvitationRole('inv-1', [ 'admin' ]);
    expect(mockPatch).toHaveBeenCalledWith('/invitations/inv-1', { invitation: { role_names: [ 'admin' ] } });
  });
});

import { impersonationApi } from './impersonationApi';

// The one /impersonations client. Mocks resolve with the REAL server envelope
// ({ success, data, message? } -- api_response.rb): axios's `response.data` IS
// that envelope, so the client must unwrap it a second time. The shapes below
// are the ImpersonationsController's own render_success payloads.
const mockPost = jest.fn();
const mockDelete = jest.fn();

jest.mock('@/shared/services/api', () => ({
  __esModule: true,
  api: {
    post: (...args: unknown[]) => mockPost(...args),
    delete: (...args: unknown[]) => mockDelete(...args),
  },
}));

const envelope = <T>(data: T, message?: string) => ({ data: { success: true, data, ...(message ? { message } : {}) } });

const userSummary = (id: string) => ({
  id, email: `${id}@example.com`, full_name: `User ${id}`, roles: ['member'],
  permissions: ['team.read'], status: 'active', last_login_at: null,
});

beforeEach(() => {
  mockPost.mockReset();
  mockDelete.mockReset();
});

describe('impersonationApi', () => {
  it('startImpersonation posts to /impersonations and returns the unwrapped token payload', async () => {
    const payload = { token: 'tok-1', target_user: userSummary('u2'), expires_at: '2026-09-25T10:00:00Z' };
    mockPost.mockResolvedValueOnce(envelope(payload, 'Impersonation started successfully'));

    const result = await impersonationApi.startImpersonation({ user_id: 'u2', reason: 'support' });

    expect(mockPost).toHaveBeenCalledWith('/impersonations', { user_id: 'u2', reason: 'support' });
    expect(result).toEqual(payload);
  });

  it('stopImpersonation sends the session token and returns the unwrapped duration', async () => {
    mockDelete.mockResolvedValueOnce(envelope({ duration: 42 }, 'Impersonation ended successfully'));

    const result = await impersonationApi.stopImpersonation('tok-1');

    expect(mockDelete).toHaveBeenCalledWith('/impersonations', { data: { session_token: 'tok-1' } });
    expect(result).toEqual({ duration: 42 });
  });

  it('validateToken reads `valid` from inside data, where the server puts it', async () => {
    const session = {
      id: 's1', session_token: 'tok-1', impersonator: userSummary('u1'), impersonated_user: userSummary('u2'),
      reason: null, started_at: '2026-09-25T09:00:00Z', ended_at: null, duration: 0, active: true, expired: false,
    };
    mockPost.mockResolvedValueOnce(envelope({ valid: true, session, expires_at: '2026-09-25T17:00:00Z' }));

    const result = await impersonationApi.validateToken('tok-1');

    expect(mockPost).toHaveBeenCalledWith('/impersonations/validate', { token: 'tok-1' });
    expect(result).toEqual({ valid: true, session, expires_at: '2026-09-25T17:00:00Z' });
  });

  it('validateToken returns valid:false (not a throw) for a token the server rejects', async () => {
    mockPost.mockResolvedValueOnce(envelope({ valid: false, message: 'Invalid or expired impersonation token' }));

    const result = await impersonationApi.validateToken('stale');

    expect(result.valid).toBe(false);
    expect(result.session).toBeUndefined();
  });

  it('throws the server error when the envelope reports success:false', async () => {
    mockPost.mockResolvedValueOnce({ data: { success: false, error: 'Cannot impersonate other system administrators' } });

    await expect(impersonationApi.startImpersonation({ user_id: 'admin-2' }))
      .rejects.toThrow('Cannot impersonate other system administrators');
  });
});

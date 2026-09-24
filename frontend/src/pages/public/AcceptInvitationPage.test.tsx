import { fireEvent, screen, waitFor } from '@testing-library/react';
import { Route, Routes } from 'react-router-dom';
import { AcceptInvitationPage } from './AcceptInvitationPage';
import { renderWithProviders } from '@/shared/utils/test-utils';

// fc-01: AcceptInvitationPage drives its whole flow through invitationsApi,
// which itself calls `api` (@/shared/services/api, baseURL already
// '/api/v1'). Mocking `api` here (rather than invitationsApi) exercises the
// REAL invitationsApi code, so this catches a reintroduced '/api/v1' prefix,
// a wrong route/verb, or a missed envelope-unwrap at the page level too --
// not just in invitationsApi's own unit test.
//
// Responses below are the REAL server envelope ({ success, data } --
// api_response.rb), not the bare resource: axios's `response.data` IS that
// envelope, and invitationsApi unwraps it a second time. A mock that skips
// the envelope can't catch a missing unwrap.
const mockGet = jest.fn();
const mockPost = jest.fn();

jest.mock('@/shared/services/api', () => ({
  __esModule: true,
  api: {
    get: (...args: unknown[]) => mockGet(...args),
    post: (...args: unknown[]) => mockPost(...args),
    patch: (...args: unknown[]) => mockPost(...args),
    delete: (...args: unknown[]) => mockPost(...args),
  },
}));

// Matches Api::V1::InvitationsController#lookup's real, deliberately minimal
// shape -- no id, no token, no status (a lookup only ever succeeds for a
// pending invitation; anything else is an error response instead).
const PENDING_LOOKUP = {
  email: 'invitee@example.com',
  role_names: [ 'member' ],
  expires_at: '2026-01-08T00:00:00Z',
  account: { name: 'Acme Corp' },
  inviter: { name: 'Jane Recruiter' },
};

const envelope = <T,>(data: T) => ({ data: { success: true, data } });

function renderAtToken(token: string) {
  return renderWithProviders(
    <Routes>
      <Route path="/accept-invitation/:token" element={<AcceptInvitationPage />} />
    </Routes>,
    { route: `/accept-invitation/${token}` }
  );
}

beforeEach(() => {
  mockGet.mockReset();
  mockPost.mockReset();
});

describe('AcceptInvitationPage', () => {
  it('looks up the invitation via the PUBLIC /invitations/lookup route, not the authenticated /invitations/:token', async () => {
    mockGet.mockResolvedValueOnce(envelope(PENDING_LOOKUP));

    renderAtToken('tok-1');

    await waitFor(() => expect(mockGet).toHaveBeenCalledWith('/invitations/lookup?token=tok-1'));
  });

  it('renders the account name and role from the lookup response', async () => {
    mockGet.mockResolvedValueOnce(envelope(PENDING_LOOKUP));

    renderAtToken('tok-1');

    await screen.findByText('Acme Corp');
    expect(screen.getByText('Member')).toBeInTheDocument();
  });

  it('accepting the invitation posts to /invitations/accept (a collection route) with the token in the body', async () => {
    mockGet.mockResolvedValueOnce(envelope(PENDING_LOOKUP));
    mockPost.mockResolvedValueOnce(envelope({ user: { id: 'u-1', email: PENDING_LOOKUP.email } }));

    renderAtToken('tok-1');

    await waitFor(() => expect(mockGet).toHaveBeenCalledWith('/invitations/lookup?token=tok-1'));
    await screen.findByText('Join the Team!');

    fireEvent.change(screen.getByLabelText(/first name/i), { target: { value: 'Jane' } });
    fireEvent.change(screen.getByLabelText(/last name/i), { target: { value: 'Doe' } });
    fireEvent.change(screen.getByLabelText(/^password/i), { target: { value: 'Str0ng!Passw0rd' } });
    fireEvent.change(screen.getByLabelText(/confirm password/i), { target: { value: 'Str0ng!Passw0rd' } });

    fireEvent.click(screen.getByRole('button', { name: /accept invitation/i }));

    await waitFor(() => expect(mockPost).toHaveBeenCalledTimes(1));
    expect(mockPost).toHaveBeenCalledWith('/invitations/accept', {
      token: 'tok-1',
      first_name: 'Jane',
      last_name: 'Doe',
      password: 'Str0ng!Passw0rd',
      password_confirmation: 'Str0ng!Passw0rd',
    });
  });

  it('shows the server\'s real error message for an expired/not-found token (410/404), never a stale "undefined" status', async () => {
    mockGet.mockRejectedValueOnce({
      response: { status: 410, data: { success: false, error: 'Invitation has expired', code: 'GONE' } },
    });

    renderAtToken('tok-1');

    await screen.findByText('Invitation has expired');
    expect(screen.queryByText(/undefined/i)).not.toBeInTheDocument();
  });
});

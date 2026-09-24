import { fireEvent, screen, waitFor } from '@testing-library/react';
import { Route, Routes } from 'react-router-dom';
import { ApprovalResponsePage } from './ApprovalResponsePage';
import { renderWithProviders } from '@/shared/utils/test-utils';

// fc-01 follow-up: ApprovalResponsePage called `apiClient` (which re-exports
// `api`, @/shared/services/api, baseURL already '/api/v1') with a literal
// '/api/v1' prefix, so both the approval-details GET and the approve/reject
// POST hit /api/v1/api/v1/... and 404d -- the same defect class as
// invitationsApi. Mocking `apiClient` (its actual import) here exercises the
// real component code.
const mockGet = jest.fn();
const mockPost = jest.fn();

jest.mock('@/shared/services/apiClient', () => ({
  __esModule: true,
  apiClient: {
    get: (...args: unknown[]) => mockGet(...args),
    post: (...args: unknown[]) => mockPost(...args),
  },
}));

jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: jest.fn() }),
}));

const APPROVAL_DETAILS = {
  step_name: 'Deploy to staging',
  pipeline_name: 'main-ci',
  run_number: '42',
  trigger_type: 'manual',
  trigger_context: {},
  status: 'pending',
  expires_at: '2026-01-08T00:00:00Z',
  time_remaining_seconds: 3600,
  requires_comment: false,
  step_configuration: { step_type: 'approval' },
};

function renderAtToken(path: string) {
  return renderWithProviders(
    <Routes>
      <Route path="/ci-cd/approve/:token" element={<ApprovalResponsePage />} />
      <Route path="/ci-cd/reject/:token" element={<ApprovalResponsePage />} />
    </Routes>,
    { route: path }
  );
}

beforeEach(() => {
  mockGet.mockReset();
  mockPost.mockReset();
});

describe('ApprovalResponsePage', () => {
  it('fetches approval details from /devops/approval_tokens/:token, not /api/v1/devops/approval_tokens/:token', async () => {
    mockGet.mockResolvedValueOnce({ data: { success: true, data: APPROVAL_DETAILS } });

    renderAtToken('/ci-cd/approve/tok-1');

    await waitFor(() => expect(mockGet).toHaveBeenCalledWith('/devops/approval_tokens/tok-1'));
  });

  it('approving posts to /devops/approval_tokens/:token/approve, not /api/v1/...', async () => {
    mockGet.mockResolvedValueOnce({ data: { success: true, data: APPROVAL_DETAILS } });
    mockPost.mockResolvedValueOnce({ data: { success: true, data: { message: 'Approved' } } });

    renderAtToken('/ci-cd/approve/tok-1');

    await screen.findByText('Approve');
    fireEvent.click(screen.getByRole('button', { name: /^approve$/i }));

    await waitFor(() =>
      expect(mockPost).toHaveBeenCalledWith('/devops/approval_tokens/tok-1/approve', { comment: undefined })
    );
  });
});

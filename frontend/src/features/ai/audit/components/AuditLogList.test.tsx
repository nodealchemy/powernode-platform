import { screen, waitFor, fireEvent } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render } from '@/test-utils';
import { AuditLogList } from './AuditLogList';

// Control → Compliance Audit → Audit log, over the real audit client against
// what GovernanceController#audit_log renders: { entries: [...], pagination }
// inside the success envelope.

const mockGet = jest.fn();
jest.mock('@/shared/services/apiClient', () => ({
  apiClient: { get: (...args: unknown[]) => mockGet(...args), put: jest.fn(), post: jest.fn(), delete: jest.fn() },
}));

const ENTRY = {
  id: 'ae-1', entry_id: 'E-1', action_type: 'policy_violation_detected', resource_type: 'Ai::CompliancePolicy',
  resource_id: 'pol-1', outcome: 'blocked', description: 'Prompt blocked by policy', ip_address: '10.0.0.1',
  occurred_at: '2026-09-10T12:00:00Z', user_id: 'u-1',
};

const renderList = () => {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={queryClient}>
      <AuditLogList />
    </QueryClientProvider>,
    { preloadedState: { auth: { user: { permissions: ['ai.governance.read'] }, isLoading: false, isAuthenticated: true } } }
  );
};

beforeEach(() => {
  mockGet.mockReset();
  mockGet.mockResolvedValue({
    data: { success: true, data: { entries: [ENTRY], pagination: { current_page: 1, total_pages: 1, total_count: 1, per_page: 20 } } },
  });
});

describe('AuditLogList — the audit_log payload', () => {
  it('lists the entries the endpoint returns', async () => {
    renderList();

    expect(await screen.findByText(/policy_violation_detected|policy violation detected/i)).toBeInTheDocument();
    expect(mockGet).toHaveBeenCalledWith('/ai/governance/audit_log', expect.anything());
  });

  it('sends the chosen date range', async () => {
    renderList();
    await screen.findByText(/policy_violation_detected|policy violation detected/i);

    fireEvent.change(screen.getByLabelText('Start date'), { target: { value: '2026-09-01' } });
    fireEvent.change(screen.getByLabelText('End date'), { target: { value: '2026-09-15' } });
    fireEvent.click(screen.getByRole('button', { name: 'Apply' }));

    await waitFor(() => expect(mockGet).toHaveBeenCalledWith('/ai/governance/audit_log', {
      params: expect.objectContaining({ start_date: '2026-09-01', end_date: '2026-09-15' }),
    }));
  });
});

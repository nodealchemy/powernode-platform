import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render } from '@/test-utils';
import { ComplianceTab } from './ComplianceTab';

// Control → Policies → Compliance: compliance policies (toggle), their
// violations (resolve) and the account's security events, over the real audit
// client against the payloads GovernanceController actually renders — each
// list wrapped as { <name>: [...], pagination } inside the success envelope.
// Create Policy is ported from the deleted Governance page.

const mockGet = jest.fn();
const mockPut = jest.fn();
jest.mock('@/shared/services/apiClient', () => ({
  apiClient: {
    get: (...args: unknown[]) => mockGet(...args),
    put: (...args: unknown[]) => mockPut(...args),
    post: jest.fn(),
    delete: jest.fn(),
  },
}));

const mockCreatePolicy = jest.fn();
jest.mock('@/shared/services/ai/GovernanceApiService', () => ({
  governanceApi: { createPolicy: (...args: unknown[]) => mockCreatePolicy(...args) },
}));

const mockAddNotification = jest.fn();
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: mockAddNotification, showNotification: jest.fn() }),
}));

const pagination = { current_page: 1, total_pages: 1, total_count: 1, per_page: 20 };
const envelope = (data: unknown) => Promise.resolve({ data: { success: true, data } });

const POLICY = {
  id: 'pol-1', name: 'No PII in prompts', policy_type: 'data_access', status: 'active', enforcement_level: 'block',
  is_system: false, is_required: false, priority: 1, violation_count: 2, created_at: '2026-09-01T00:00:00Z',
};
const VIOLATION = {
  id: 'vio-1', violation_id: 'V-001', severity: 'high', status: 'open', description: 'Prompt carried an email address',
  source_type: 'Ai::Execution', remediation_steps: [], detected_at: '2026-09-02T00:00:00Z',
  policy: { id: 'pol-1', name: 'No PII in prompts' },
};
const EVENT = {
  id: 'evt-1', action: 'login_failed', resource_type: 'User', severity: 'high', risk_level: 'medium',
  source: 'web', ip_address: '10.0.0.9', created_at: '2026-09-03T00:00:00Z',
};

function routeGets(url: string) {
  if (url === '/ai/governance/policies') return envelope({ policies: [POLICY], pagination });
  if (url === '/ai/governance/violations') return envelope({ violations: [VIOLATION], pagination });
  if (url === '/ai/governance/security_events') return envelope({ events: [EVENT], pagination });
  return envelope({});
}

const renderTab = (permissions: string[] = ['ai.governance.read', 'ai.governance.manage']) => {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
  return render(
    <QueryClientProvider client={queryClient}>
      <ComplianceTab />
    </QueryClientProvider>,
    { preloadedState: { auth: { user: { permissions }, isLoading: false, isAuthenticated: true } } }
  );
};

beforeEach(() => {
  jest.clearAllMocks();
  mockGet.mockImplementation(routeGets);
  mockPut.mockImplementation(() => envelope({}));
});

describe('ComplianceTab — lists from the governance endpoints', () => {
  it('shows the policies, their violations (with the policy name) and the security events', async () => {
    renderTab();

    expect(await screen.findByText('No PII in prompts', { selector: '*:not(option)' })).toBeInTheDocument();
    expect(await screen.findByText('Prompt carried an email address')).toBeInTheDocument();
    const violations = screen.getByRole('region', { name: 'Violations' });
    expect(within(violations).getByText('No PII in prompts')).toBeInTheDocument();
    expect(await screen.findByText('login_failed')).toBeInTheDocument();
  });
});

describe('ComplianceTab — writes, for ai.governance.manage holders', () => {
  it('toggles a policy through the toggle endpoint', async () => {
    const user = userEvent.setup();
    renderTab();

    await user.click(await screen.findByTitle('Disable policy'));

    await waitFor(() => expect(mockPut).toHaveBeenCalledWith('/ai/governance/policies/pol-1/toggle'));
  });

  it('resolves a violation through the resolve endpoint', async () => {
    const user = userEvent.setup();
    renderTab();

    await user.click(await screen.findByTitle('Resolve'));

    await waitFor(() => expect(mockPut).toHaveBeenCalledWith('/ai/governance/violations/vio-1/resolve'));
  });

  it('creates a policy from the form', async () => {
    const user = userEvent.setup();
    mockCreatePolicy.mockResolvedValue({ policy: { id: 'pol-2' } });
    renderTab();

    await user.click(await screen.findByRole('button', { name: /create policy/i }));
    const dialog = await screen.findByRole('dialog');
    await user.type(within(dialog).getByLabelText(/^name$/i), 'No External API Keys');
    await user.click(within(dialog).getByRole('button', { name: /^create policy$/i }));

    await waitFor(() =>
      expect(mockCreatePolicy).toHaveBeenCalledWith(expect.objectContaining({ name: 'No External API Keys' })));
  });

  it('surfaces the server error when creating a policy fails, and keeps the form open', async () => {
    const user = userEvent.setup();
    mockCreatePolicy.mockRejectedValue({ response: { data: { error: 'Policy name already exists' } } });
    renderTab();

    await user.click(await screen.findByRole('button', { name: /create policy/i }));
    const dialog = await screen.findByRole('dialog');
    await user.type(within(dialog).getByLabelText(/^name$/i), 'Duplicate');
    await user.click(within(dialog).getByRole('button', { name: /^create policy$/i }));

    await waitFor(() => expect(mockAddNotification).toHaveBeenCalledWith(
      expect.objectContaining({ type: 'error', message: 'Policy name already exists' })));
    expect(screen.getByRole('dialog')).toBeInTheDocument();
  });
});

describe('ComplianceTab — read-only without ai.governance.manage', () => {
  it('offers no toggle, resolve or create', async () => {
    renderTab(['ai.governance.read']);

    await screen.findByText('Prompt carried an email address');
    expect(screen.queryByTitle('Disable policy')).not.toBeInTheDocument();
    expect(screen.queryByTitle('Resolve')).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /create policy/i })).not.toBeInTheDocument();
  });
});

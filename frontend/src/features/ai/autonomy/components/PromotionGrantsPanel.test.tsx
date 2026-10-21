import { render, screen, fireEvent, waitFor, within } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { PromotionGrantsPanel, formatTimeLeft } from './PromotionGrantsPanel';

// Only apiClient and the permission hook are mocked; react-query, the hooks
// and the panel are real.

const mockGet = jest.fn();
const mockPost = jest.fn();
let mockPermissions: string[] = [];

jest.mock('@/shared/services/apiClient', () => ({
  apiClient: {
    get: (...args: unknown[]) => mockGet(...args),
    post: (...args: unknown[]) => mockPost(...args),
    put: jest.fn(),
    patch: jest.fn(),
    delete: jest.fn(),
  },
}));

jest.mock('@/shared/hooks/usePermissions', () => ({
  usePermissions: () => ({ hasPermission: (p: string) => mockPermissions.includes(p) }),
}));

jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: jest.fn() }),
}));

const OPTIONS = {
  categories: ['release.promote'],
  environments: [
    { id: 'env-staging', slug: 'staging', name: 'Staging', tier: 1, is_protected: false },
    { id: 'env-ops', slug: 'ops', name: 'Operations', tier: 2, is_protected: true },
    { id: 'env-prod', slug: 'prod', name: 'Production', tier: 3, is_protected: true },
    // A strict plane that is not named prod: the warning must key on the server's flags, not the slug.
    { id: 'env-eu', slug: 'live-eu', name: 'Live EU', tier: 3, is_protected: true },
  ].map((e) => ({
    ...e,
    strict: e.tier >= 3,
    // live-eu carries limits unlike the defaults, so copy hard-coded to 4h/10 shows up.
    max_lifetime_hours: e.slug === 'live-eu' ? 2 : (e.tier >= 3 ? 4 : 24),
    max_uses_limit: e.slug === 'live-eu' ? 7 : (e.tier >= 3 ? 10 : null),
  })),
  modules: [{ id: 'mod-1', name: 'hub-backend' }, { id: 'mod-2', name: 'hub-worker' }],
  expiry_presets_hours: [1, 4, 8, 24],
  max_lifetime_hours: 24,
  required_permission: 'system.modules.update' as string | null,
};

// An MCP-client agent: it has NO trust score, so a trust-score-sourced
// picker would hide it.
const AGENTS = [
  { id: 'agent-cc', name: 'Claude Code (headersHelper) #13', agent_type: 'mcp_client' },
  { id: 'agent-rm', name: 'Release Manager', agent_type: 'monitor' },
];

const GRANT = {
  id: 'g1', action_category: 'release.promote', status: 'active',
  agent: { id: 'agent-cc', name: 'Claude Code (headersHelper) #13' },
  environment: { id: 'env-ops', slug: 'ops', name: 'Operations', is_protected: true },
  module_ids: [], max_uses: 3, uses_count: 1, uses_remaining: 2,
  expires_at: '2026-10-21T14:00:00Z', seconds_remaining: 5400, reason: 'release train',
  granted_by: { id: 'u1', name: 'Pat Operator' }, revoked_at: null, revoked_by: null,
  created_at: '2026-10-21T10:00:00Z',
};

let mockOptions: typeof OPTIONS = OPTIONS;

function routeGets(url: string, config?: { params?: { search?: string } }) {
  if (url === '/ai/promotion_grants') return Promise.resolve({ data: { data: { promotion_grants: [GRANT] } } });
  if (url === '/ai/promotion_grants/options') return Promise.resolve({ data: { data: mockOptions } });
  if (url === '/ai/agents') {
    const search = config?.params?.search?.toLowerCase();
    const items = search ? AGENTS.filter((a) => a.name.toLowerCase().includes(search)) : AGENTS;
    return Promise.resolve({ data: { data: { items } } });
  }
  if (url === '/ai/autonomy/trust_scores') return Promise.resolve({ data: { data: [] } });
  return Promise.resolve({ data: { data: [] } });
}

function renderPanel() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <PromotionGrantsPanel />
    </QueryClientProvider>
  );
}

beforeEach(() => {
  mockGet.mockReset();
  mockPost.mockReset();
  mockGet.mockImplementation(routeGets);
  mockOptions = OPTIONS;
  mockPermissions = ['ai.promotion_grants.read', 'ai.promotion_grants.manage'];
});

describe('PromotionGrantsPanel', () => {
  it('lists grants with agent, environment, uses/max, time left and who granted', async () => {
    renderPanel();
    const row = await screen.findByTestId('grant-g1');
    expect(within(row).getByText('Claude Code (headersHelper) #13')).toBeInTheDocument();
    expect(within(row).getByText('ops')).toBeInTheDocument();
    expect(within(row).getByText('1/3')).toBeInTheDocument();
    expect(within(row).getByText('1h 30m')).toBeInTheDocument();
    expect(within(row).getByText('Pat Operator')).toBeInTheDocument();
    expect(within(row).getByText('any')).toBeInTheDocument();
  });

  it('revokes an active grant', async () => {
    mockPost.mockResolvedValue({ data: { data: { promotion_grant: { ...GRANT, status: 'revoked' } } } });
    renderPanel();
    const row = await screen.findByTestId('grant-g1');
    fireEvent.click(within(row).getByText('Revoke'));
    await waitFor(() => expect(mockPost).toHaveBeenCalledWith('/ai/promotion_grants/g1/revoke'));
  });

  it('hides issue and revoke without ai.promotion_grants.manage (permissions, never roles)', async () => {
    mockPermissions = ['ai.promotion_grants.read'];
    renderPanel();
    const row = await screen.findByTestId('grant-g1');
    expect(within(row).queryByText('Revoke')).not.toBeInTheDocument();
    expect(screen.queryByText('New grant')).not.toBeInTheDocument();
  });

  describe('the create form', () => {
    async function openForm() {
      renderPanel();
      fireEvent.click(await screen.findByText('New grant'));
      return screen.findByLabelText('Agent');
    }

    it('offers an agent that has no trust score, from the agents list', async () => {
      const picker = await openForm();
      await waitFor(() =>
        expect(within(picker).getByText('Claude Code (headersHelper) #13')).toBeInTheDocument()
      );
      expect(mockGet).toHaveBeenCalledWith('/ai/agents', expect.objectContaining({ params: expect.objectContaining({ scope: 'custom' }) }));
      expect(mockGet).not.toHaveBeenCalledWith('/ai/autonomy/trust_scores');
    });

    it('warns strongly for a strict plane, keyed on the server flags rather than the slug', async () => {
      await openForm();
      expect(screen.queryByRole('alert')).not.toBeInTheDocument();
      fireEvent.change(screen.getByLabelText('Environment'), { target: { value: 'env-eu' } });
      expect(screen.getByRole('alert')).toHaveTextContent(/Live EU/);
    });

    it('takes the strict limits from options, not hard-coded fallbacks (L-2)', async () => {
      await openForm();
      fireEvent.change(screen.getByLabelText('Environment'), { target: { value: 'env-eu' } });
      expect(screen.getByRole('alert')).toHaveTextContent(/at most 2 hours/);
      expect(screen.getByRole('alert')).toHaveTextContent(/max uses \(1-7\)/);
      expect(screen.getByText('4h')).toBeDisabled();
      expect(screen.getByText('1h')).not.toBeDisabled();
      expect(screen.getByText(/Max uses \(required, 1-7\)/)).toBeInTheDocument();
    });

    it('shows the strict limits: no preset over 4h, max uses and a module required', async () => {
      await openForm();
      fireEvent.change(screen.getByLabelText('Environment'), { target: { value: 'env-prod' } });
      expect(screen.getByText('8h')).toBeDisabled();
      expect(screen.getByText('24h')).toBeDisabled();
      expect(screen.getByText('4h')).not.toBeDisabled();
      fireEvent.change(screen.getByLabelText('Agent'), { target: { value: 'agent-cc' } });
      fireEvent.change(screen.getByLabelText('Reason'), { target: { value: 'hotfix' } });
      expect(screen.getByText('Issue grant')).toBeDisabled();
      expect(screen.getByText(/max uses \(1-10\) and at least one module/i)).toBeInTheDocument();
    });

    it('says that anyone who can drive the agent can spend its grant, and offers granter-only', async () => {
      await openForm();
      expect(screen.getByText(/anyone who can drive this agent can spend/i)).toBeInTheDocument();
      expect(screen.getByLabelText(/Only when I drive the agent/i)).not.toBeChecked();
    });

    it('searches the agents server-side, so a large account still finds one', async () => {
      await openForm();
      fireEvent.change(screen.getByLabelText('Search agents'), { target: { value: 'release' } });
      await waitFor(() => expect(mockGet).toHaveBeenCalledWith('/ai/agents',
        expect.objectContaining({ params: expect.objectContaining({ search: 'release' }) })));
      await waitFor(() => expect(within(screen.getByLabelText('Agent')).queryByText('Claude Code (headersHelper) #13')).not.toBeInTheDocument());
      expect(within(screen.getByLabelText('Agent')).getByText('Release Manager')).toBeInTheDocument();
    });

    it('is disabled with an explanation when no extension declares the grantable verb (core mode)', async () => {
      mockOptions = { ...OPTIONS, required_permission: null };
      renderPanel();
      fireEvent.click(await screen.findByText('New grant'));
      expect(await screen.findByText(/no installed extension/i)).toBeInTheDocument();
      expect(screen.getByText('Issue grant')).toBeDisabled();
    });

    it('requires a reason before it can be submitted', async () => {
      await openForm();
      fireEvent.change(screen.getByLabelText('Agent'), { target: { value: 'agent-cc' } });
      fireEvent.change(screen.getByLabelText('Environment'), { target: { value: 'env-ops' } });
      expect(screen.getByText('Issue grant')).toBeDisabled();
    });

    it('submits agent, environment, modules, max uses, preset expiry and reason', async () => {
      mockPost.mockResolvedValue({ data: { data: { promotion_grant: GRANT } } });
      await openForm();
      fireEvent.change(screen.getByLabelText('Agent'), { target: { value: 'agent-cc' } });
      fireEvent.change(screen.getByLabelText('Environment'), { target: { value: 'env-ops' } });
      const modules = screen.getByLabelText('Modules') as HTMLSelectElement;
      (within(modules).getByText('hub-backend') as HTMLOptionElement).selected = true;
      fireEvent.change(modules);
      fireEvent.change(screen.getByLabelText('Max uses'), { target: { value: '2' } });
      fireEvent.click(screen.getByText('8h'));
      fireEvent.change(screen.getByLabelText('Reason'), { target: { value: 'ship the train' } });
      fireEvent.click(screen.getByLabelText(/Only when I drive the agent/i));
      fireEvent.click(screen.getByText('Issue grant'));

      await waitFor(() => expect(mockPost).toHaveBeenCalledWith('/ai/promotion_grants', {
        ai_agent_id: 'agent-cc', environment_id: 'env-ops', action_category: 'release.promote',
        module_ids: ['mod-1'], max_uses: 2, expires_in_hours: 8, reason: 'ship the train',
        granter_driven_only: true,
      }));
    });
  });
});

describe('formatTimeLeft', () => {
  it('renders hours and minutes, or a dash once spent', () => {
    expect(formatTimeLeft(0)).toBe('—');
    expect(formatTimeLeft(59 * 60)).toBe('59m');
    expect(formatTimeLeft(3 * 3600 + 5 * 60)).toBe('3h 5m');
  });
});

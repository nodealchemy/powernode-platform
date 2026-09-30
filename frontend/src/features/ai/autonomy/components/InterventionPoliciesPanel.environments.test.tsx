import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { InterventionPoliciesPanel } from './InterventionPoliciesPanel';

// conditions.environments is a LIST of the account's environment slugs. The
// form's multi-select is sourced from GET /ai/intervention_policies/environments,
// pre-selects what a row already names, and submits an array (never the
// comma-separated string the generic key/value builder used to write).
// Only apiClient is mocked; react-query, the hooks and the panel are real.

const mockGet = jest.fn();
const mockPost = jest.fn();
const mockPut = jest.fn();

jest.mock('@/shared/services/apiClient', () => ({
  apiClient: {
    get: (...args: unknown[]) => mockGet(...args),
    post: (...args: unknown[]) => mockPost(...args),
    put: (...args: unknown[]) => mockPut(...args),
    patch: jest.fn(),
    delete: jest.fn(),
  },
}));

jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: jest.fn() }),
}));

jest.mock('@/shared/utils/logger', () => ({
  logger: { error: jest.fn(), warn: jest.fn(), info: jest.fn(), debug: jest.fn() },
}));

const ENVIRONMENTS = [
  { slug: 'dev', name: 'Development', tier: 0 },
  { slug: 'staging', name: 'Staging', tier: 1 },
  { slug: 'ops', name: 'Operations', tier: 2 },
];

const existing = {
  id: 'p1', action_category: 'release.promote', scope: 'global', policy: 'require_approval', priority: 5,
  is_active: true, agent: null, conditions: { environments: ['staging', 'ops'], trust_tier_minimum: 'trusted' },
  preferred_channels: [], created_at: '2026-09-25T00:00:00Z', updated_at: '2026-09-25T00:00:00Z',
};

function routeGets(url: string) {
  if (url === '/ai/intervention_policies/grouped') {
    return Promise.resolve({ data: { success: true, data: { chains: [], policies: { by_domain: {} } } } });
  }
  if (url === '/ai/intervention_policies/environments') {
    return Promise.resolve({ data: { success: true, data: { environments: ENVIRONMENTS } } });
  }
  if (url === '/ai/intervention_policies') {
    return Promise.resolve({ data: { success: true, data: { policies: [existing], total_count: 1 } } });
  }
  return Promise.resolve({ data: { success: true, data: [] } });
}

// The list's toggle button and the form's submit share the label; the form's is last.
function submitCreate() {
  const buttons = screen.getAllByText('Create Policy');
  fireEvent.click(buttons[buttons.length - 1]);
}

function renderPanel() {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={queryClient}>
      <InterventionPoliciesPanel />
    </QueryClientProvider>
  );
}

describe('InterventionPoliciesPanel environments multi-select', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockGet.mockImplementation(routeGets);
    mockPost.mockResolvedValue({ data: { success: true, data: {} } });
    mockPut.mockResolvedValue({ data: { success: true, data: {} } });
  });

  it('renders the account environments as options and submits the chosen ones as an array', async () => {
    renderPanel();
    fireEvent.click(await screen.findByText('Create Policy'));

    fireEvent.change(screen.getByPlaceholderText('Action category'), { target: { value: 'release.promote' } });
    fireEvent.click(await screen.findByLabelText('Staging'));
    fireEvent.click(screen.getByLabelText('Operations'));
    expect(screen.getByLabelText('Development')).not.toBeChecked();

    submitCreate();

    await waitFor(() => expect(mockPost).toHaveBeenCalled());
    const [url, payload] = mockPost.mock.calls[0];
    expect(url).toBe('/ai/intervention_policies');
    expect(payload.conditions).toEqual({ environments: ['staging', 'ops'] });
  });

  it('omits the environments key when none is selected', async () => {
    renderPanel();
    fireEvent.click(await screen.findByText('Create Policy'));
    fireEvent.change(screen.getByPlaceholderText('Action category'), { target: { value: 'release.promote' } });
    await screen.findByLabelText('Staging');

    submitCreate();

    await waitFor(() => expect(mockPost).toHaveBeenCalled());
    expect(mockPost.mock.calls[0][1].conditions).toEqual({});
  });

  it('pre-selects a policy\'s environments on edit and keeps the other conditions', async () => {
    renderPanel();
    fireEvent.click(await screen.findByText('release.promote'));
    fireEvent.click(await screen.findByText('Edit'));

    expect(await screen.findByLabelText('Staging')).toBeChecked();
    expect(screen.getByLabelText('Operations')).toBeChecked();
    expect(screen.getByLabelText('Development')).not.toBeChecked();

    fireEvent.click(screen.getByLabelText('Development'));
    fireEvent.click(screen.getByText('Save Changes'));

    await waitFor(() => expect(mockPut).toHaveBeenCalled());
    const [url, payload] = mockPut.mock.calls[0];
    expect(url).toBe('/ai/intervention_policies/p1');
    expect(payload.conditions).toEqual({ environments: ['staging', 'ops', 'dev'], trust_tier_minimum: 'trusted' });
  });

  it('does not let the generic builder write the environments key as a string', async () => {
    renderPanel();
    fireEvent.click(await screen.findByText('Create Policy'));
    fireEvent.change(screen.getByPlaceholderText('Action category'), { target: { value: 'release.promote' } });
    fireEvent.change(screen.getByPlaceholderText('Key'), { target: { value: 'environments' } });
    fireEvent.change(screen.getByPlaceholderText('Value'), { target: { value: 'staging,ops' } });
    fireEvent.click(screen.getByText('Add'));

    submitCreate();

    await waitFor(() => expect(mockPost).toHaveBeenCalled());
    expect(mockPost.mock.calls[0][1].conditions).toEqual({});
  });
});

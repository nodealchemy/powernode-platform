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

  async function openEdit() {
    renderPanel();
    fireEvent.click(await screen.findByText('release.promote'));
    fireEvent.click(await screen.findByText('Edit'));
  }

  it('while the environments load, the selected slugs are neither flagged stale nor editable', async () => {
    mockGet.mockImplementation((url: string) => (
      url === '/ai/intervention_policies/environments' ? new Promise(() => {}) : routeGets(url)
    ));
    await openEdit();

    const staging = await screen.findByLabelText('staging');
    expect(staging).toBeChecked();
    expect(staging).toBeDisabled();
    expect(screen.queryByText(/no longer an environment/)).not.toBeInTheDocument();
    expect(screen.getByText('Loading environments...')).toBeInTheDocument();
  });

  it('when the environments fetch fails, shows an error, keeps the selection, and saves it unchanged', async () => {
    mockGet.mockImplementation((url: string) => (
      url === '/ai/intervention_policies/environments' ? Promise.reject(new Error('boom')) : routeGets(url)
    ));
    await openEdit();

    expect(await screen.findByRole('alert')).toHaveTextContent('Could not load environments');
    expect(screen.getByLabelText('staging')).toBeDisabled();
    expect(screen.queryByText(/no longer an environment/)).not.toBeInTheDocument();

    fireEvent.click(screen.getByText('Save Changes'));
    await waitFor(() => expect(mockPut).toHaveBeenCalled());
    expect(mockPut.mock.calls[0][1].conditions.environments).toEqual(['staging', 'ops']);
  });

  it('flags a slug that is no longer an environment once the list has loaded', async () => {
    mockGet.mockImplementation((url: string) => (
      url === '/ai/intervention_policies' ? Promise.resolve({
        data: { success: true, data: { policies: [{ ...existing, conditions: { environments: ['staging', 'gone'] } }], total_count: 1 } },
      }) : routeGets(url)
    ));
    await openEdit();

    expect(await screen.findByLabelText('gone (no longer an environment)')).toBeChecked();
    expect(screen.getByLabelText('Staging')).toBeChecked();
  });

  it('requires confirmation before emptying a non-empty selection widens the policy; cancelling keeps it', async () => {
    await openEdit();
    fireEvent.click(await screen.findByLabelText('Staging'));
    fireEvent.click(screen.getByLabelText('Operations'));
    expect(screen.getByText(/None selected: applies in every environment/)).toBeInTheDocument();

    fireEvent.click(screen.getByText('Save Changes'));
    expect(mockPut).not.toHaveBeenCalled();
    expect(screen.getByRole('alertdialog')).toHaveTextContent('This policy will apply to ALL environments, including production');

    fireEvent.click(screen.getByText('Keep selection'));
    expect(mockPut).not.toHaveBeenCalled();
    expect(screen.queryByRole('alertdialog')).not.toBeInTheDocument();
    expect(screen.getByLabelText('Staging')).toBeChecked();
    expect(screen.getByLabelText('Operations')).toBeChecked();
  });

  it('saves without the environments key once the widening is confirmed', async () => {
    await openEdit();
    fireEvent.click(await screen.findByLabelText('Staging'));
    fireEvent.click(screen.getByLabelText('Operations'));
    fireEvent.click(screen.getByText('Save Changes'));
    fireEvent.click(screen.getByText('Apply to all environments'));

    await waitFor(() => expect(mockPut).toHaveBeenCalled());
    expect(mockPut.mock.calls[0][1].conditions).toEqual({ trust_tier_minimum: 'trusted' });
  });

  it('does not ask for confirmation on a row that never had environments', async () => {
    mockGet.mockImplementation((url: string) => (
      url === '/ai/intervention_policies' ? Promise.resolve({
        data: { success: true, data: { policies: [{ ...existing, conditions: {} }], total_count: 1 } },
      }) : routeGets(url)
    ));
    await openEdit();
    await screen.findByLabelText('Staging');
    fireEvent.click(screen.getByText('Save Changes'));

    await waitFor(() => expect(mockPut).toHaveBeenCalled());
    expect(screen.queryByRole('alertdialog')).not.toBeInTheDocument();
  });

  it('pre-selects a legacy comma-string value, normalised as the server does', async () => {
    mockGet.mockImplementation((url: string) => (
      url === '/ai/intervention_policies' ? Promise.resolve({
        data: { success: true, data: { policies: [{ ...existing, conditions: { environments: ' staging, ops ,staging' } }], total_count: 1 } },
      }) : routeGets(url)
    ));
    await openEdit();

    expect(await screen.findByLabelText('Staging')).toBeChecked();
    expect(screen.getByLabelText('Operations')).toBeChecked();
    expect(screen.getByLabelText('Development')).not.toBeChecked();

    fireEvent.click(screen.getByText('Save Changes'));
    await waitFor(() => expect(mockPut).toHaveBeenCalled());
    expect(mockPut.mock.calls[0][1].conditions.environments).toEqual(['staging', 'ops']);
  });
});

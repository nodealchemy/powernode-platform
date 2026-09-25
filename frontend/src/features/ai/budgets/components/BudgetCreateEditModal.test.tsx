import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { BudgetCreateEditModal } from './BudgetCreateEditModal';

// Creating a budget picks its agent from the account's agents (the same
// agentsApi list the allocate form uses) instead of a typed UUID. Only
// apiClient and agentsApi are mocked; react-query and the modal are real.

const mockPost = jest.fn();

jest.mock('@/shared/services/apiClient', () => ({
  apiClient: {
    get: jest.fn(),
    post: (...args: unknown[]) => mockPost(...args),
    put: jest.fn(),
    delete: jest.fn(),
  },
}));

jest.mock('@/shared/services/ai/AgentsApiService', () => ({
  agentsApi: {
    getAgents: () =>
      Promise.resolve({ items: [{ id: 'a-one', name: 'Agent One' }, { id: 'a-two', name: 'Agent Two' }] }),
  },
}));

const renderModal = () => {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
  const onClose = jest.fn();
  render(
    <QueryClientProvider client={client}>
      <BudgetCreateEditModal onClose={onClose} />
    </QueryClientProvider>,
  );
  return { onClose };
};

describe('BudgetCreateEditModal (create)', () => {
  beforeEach(() => {
    mockPost.mockResolvedValue({ data: { success: true, data: {} } });
  });

  it('offers the account agents and sends the chosen agent id', async () => {
    const { onClose } = renderModal();
    await screen.findByRole('option', { name: 'Agent Two' });
    expect(screen.queryByPlaceholderText(/agent uuid/i)).not.toBeInTheDocument();

    fireEvent.change(screen.getByLabelText('Agent'), { target: { value: 'a-two' } });
    fireEvent.change(screen.getByPlaceholderText('10.00'), { target: { value: '25' } });
    fireEvent.click(screen.getByRole('button', { name: 'Create' }));

    await waitFor(() => expect(mockPost).toHaveBeenCalledTimes(1));
    expect(mockPost).toHaveBeenCalledWith(
      '/ai/autonomy/budgets',
      expect.objectContaining({ agent_id: 'a-two', total_budget_cents: 2_500 }),
    );
    await waitFor(() => expect(onClose).toHaveBeenCalled());
  });

  it('submits nothing until an agent is chosen', async () => {
    renderModal();
    await screen.findByRole('option', { name: 'Agent One' });

    fireEvent.change(screen.getByPlaceholderText('10.00'), { target: { value: '25' } });
    fireEvent.submit(screen.getByRole('button', { name: 'Create' }).closest('form')!);

    expect(await screen.findByText('Please choose an agent')).toBeInTheDocument();
    expect(mockPost).not.toHaveBeenCalled();
  });
});

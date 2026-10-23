import { screen, fireEvent, waitFor } from '@testing-library/react';
import { render } from '@/test-utils';
import { AgentHistoryTab } from './AgentHistoryTab';

jest.mock('@/shared/services/ai', () => ({
  agentsApi: {
    getExecutions: jest.fn(),
    getExecution: jest.fn(),
    cancelExecution: jest.fn(),
    retryExecution: jest.fn(),
  },
}));

import { agentsApi } from '@/shared/services/ai';

const base = { status: 'completed', created_at: new Date().toISOString() };
const withData = {
  ...base,
  id: 'e1',
  source: 'claude_code',
  input_summary: 'Fix the history tab',
  model: 'claude-opus-5',
  tokens_used: 1234,
  cost_usd: 0.5,
  duration_ms: 4000,
};
const bare = { ...base, id: 'e2', source: 'platform' };

const renderTab = () =>
  render(<AgentHistoryTab agentId="agent-1" />, {
    preloadedState: { auth: { user: { id: 'u1', permissions: ['ai.agents.execute'] }, isAuthenticated: true, isLoading: false } },
  });

describe('AgentHistoryTab', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (agentsApi.getExecutions as jest.Mock).mockResolvedValue({ items: [withData, bare] });
    (agentsApi.getExecution as jest.Mock).mockResolvedValue({
      ...withData,
      input_parameters: { task_digest: 'Fix the history tab' },
      output_data: { model_used: 'claude-opus-5' },
      execution_context: { source: 'claude_code', run_key: 'run-42' },
    });
  });

  it('shows the input and source for a row with data, never "No input"', async () => {
    renderTab();
    expect(await screen.findByText('Fix the history tab')).toBeInTheDocument();
    expect(screen.getByText('Claude Code')).toBeInTheDocument();
    expect(screen.queryByText(/No input/)).not.toBeInTheDocument();
  });

  it('says "not recorded" for a row without data', async () => {
    renderTab();
    expect(await screen.findByText('Input not recorded')).toBeInTheDocument();
    expect(screen.getByText('Platform')).toBeInTheDocument();
    expect(screen.queryByText(/No input/)).not.toBeInTheDocument();
  });

  it('fetches the detail endpoint once on expand and renders the context', async () => {
    renderTab();
    const row = await screen.findByText('Fix the history tab');
    fireEvent.click(row);
    expect(await screen.findByText(/run-42/)).toBeInTheDocument();
    expect(agentsApi.getExecution).toHaveBeenCalledTimes(1);
    expect(agentsApi.getExecution).toHaveBeenCalledWith('agent-1', 'e1');
    expect(screen.getByText('claude-opus-5')).toBeInTheDocument();

    fireEvent.click(row); // collapse
    fireEvent.click(row); // re-expand: cached
    await waitFor(() => expect(screen.getByText(/run-42/)).toBeInTheDocument());
    expect(agentsApi.getExecution).toHaveBeenCalledTimes(1);
  });
});

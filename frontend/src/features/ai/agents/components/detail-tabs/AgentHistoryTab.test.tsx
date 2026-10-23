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
  execution_id: 'uuid-e1',
  source: 'claude_code',
  input_summary: 'Fix the history tab',
  model: 'claude-opus-5',
  tokens_used: 1234,
  cost_usd: 0.5,
  duration_ms: 4000,
};
const bare = { ...base, id: 'e2', execution_id: 'uuid-e2' };

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
      input_parameters: {
        task_digest: 'Fix the history tab',
        message_count: 2,
        messages: [{ role: 'user', content: 'SECRET-PROMPT-TEXT' }],
        prompt: 'SECRET-PROMPT-TEXT',
        input: 'SECRET-PROMPT-TEXT',
        system_prompt: 'SECRET-SYSTEM',
      },
      output_data: { model_used: 'claude-opus-5', response: 'SECRET-RESPONSE', content: 'SECRET-RESPONSE' },
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
    expect(screen.getByText('Source not recorded')).toBeInTheDocument();
    expect(screen.queryByText('Platform')).not.toBeInTheDocument();
    expect(screen.queryByText(/No input/)).not.toBeInTheDocument();
  });

  it('fetches the detail endpoint once on expand and renders the context', async () => {
    renderTab();
    const row = await screen.findByText('Fix the history tab');
    fireEvent.click(row);
    expect(await screen.findByText(/run-42/)).toBeInTheDocument();
    expect(agentsApi.getExecution).toHaveBeenCalledTimes(1);
    expect(agentsApi.getExecution).toHaveBeenCalledWith('agent-1', 'uuid-e1');
    expect(screen.getByText('claude-opus-5')).toBeInTheDocument();
    expect(screen.getByText(/message_count/)).toBeInTheDocument();
    expect(screen.getByText(/content not shown until recorded under the redaction rules/)).toBeInTheDocument();
    expect(screen.queryByText(/SECRET-/)).not.toBeInTheDocument();
    expect(screen.queryByText(/"messages"/)).not.toBeInTheDocument();
    ['prompt', 'input', 'system_prompt', 'response', 'content'].forEach((key) => {
      expect(screen.queryByText(new RegExp(`"${key}"`))).not.toBeInTheDocument();
    });

    fireEvent.click(row); // collapse
    fireEvent.click(row); // re-expand: cached
    await waitFor(() => expect(screen.getByText(/run-42/)).toBeInTheDocument());
    expect(agentsApi.getExecution).toHaveBeenCalledTimes(1);
  });

  it.each([
    ['running', 'Cancel', 'cancelExecution'],
    ['failed', 'Retry', 'retryExecution'],
  ])('%s row: %s calls the API with the execution_id', async (status, label, method) => {
    (agentsApi.getExecutions as jest.Mock).mockResolvedValue({
      items: [{ ...withData, status }],
    });
    (agentsApi as unknown as Record<string, jest.Mock>)[method].mockResolvedValue({});
    renderTab();
    fireEvent.click(await screen.findByText('Fix the history tab'));
    fireEvent.click(await screen.findByRole('button', { name: new RegExp(label) }));
    await waitFor(() =>
      expect((agentsApi as unknown as Record<string, jest.Mock>)[method]).toHaveBeenCalledWith('agent-1', 'uuid-e1')
    );
  });
});

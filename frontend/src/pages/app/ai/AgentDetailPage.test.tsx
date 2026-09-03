import { screen } from '@testing-library/react';
import { render } from '@/test-utils';
import AgentDetailPage from './AgentDetailPage';

// IMP-e8513b30152d — the agent detail API returns
// execution_stats.by_executor_kind { platform, claude_code } (HIER-P1C); the
// overview must render both counts and carry the token-comparability
// convention (Claude Code `input` = input + cache_read + cache_creation).
jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useParams: () => ({ agentId: 'agent-1' }),
}));

jest.mock('@/shared/services/ai', () => ({
  agentsApi: {
    getAgent: jest.fn(),
  },
  intelligenceApi: {
    getIntelligenceSummary: jest.fn(),
    getExperienceReplays: jest.fn(),
    getSelfChallenges: jest.fn(),
  },
}));

jest.mock('@/features/ai/chat/context/ChatWindowContext', () => ({
  useChatWindow: () => ({ openConversationMaximized: () => {} }),
}));
jest.mock('@/features/ai/agents/components/AgentConnectionsGraph', () => ({ AgentConnectionsGraph: () => null }));
jest.mock('@/features/ai/memory/components/ContextBrowser', () => ({ ContextBrowser: () => null }));

import { agentsApi } from '@/shared/services/ai';

const agent = {
  id: 'agent-1',
  name: 'CVE Responder',
  description: 'CVE intake and remediation.',
  status: 'active',
  agent_type: 'monitor',
  model: 'claude-opus-5',
  execution_stats: {
    total_executions: 5,
    successful_executions: 5,
    failed_executions: 0,
    success_rate: 100,
    avg_execution_time: 1.5,
    by_executor_kind: { platform: 3, claude_code: 2 },
  },
};

describe('AgentDetailPage overview — Executions card (IMP-e8513b30152d)', () => {
  beforeEach(() => {
    (agentsApi.getAgent as jest.Mock).mockResolvedValue(agent);
  });

  it('renders the platform vs Claude Code execution counts from execution_stats.by_executor_kind', async () => {
    render(<AgentDetailPage />);

    const card = (await screen.findByTestId('agent-executions-card'));
    expect(card).toHaveTextContent('Executions');
    expect(screen.getByTestId('executions-platform-count')).toHaveTextContent('3');
    expect(screen.getByTestId('executions-claude-code-count')).toHaveTextContent('2');
  });

  it('carries the token-comparability convention as a tooltip on the card', async () => {
    render(<AgentDetailPage />);

    const hint = await screen.findByTestId('executions-token-convention');
    expect(hint).toHaveAttribute('title', expect.stringContaining('cache_read'));
    expect(hint).toHaveAttribute('title', expect.stringContaining('cache_creation'));
    expect(hint).toHaveAttribute('title', expect.stringMatching(/not directly comparable/i));
  });

  it('renders zero counts when the API omits by_executor_kind (older backend)', async () => {
    (agentsApi.getAgent as jest.Mock).mockResolvedValue({
      ...agent,
      execution_stats: { ...agent.execution_stats, by_executor_kind: undefined },
    });
    render(<AgentDetailPage />);

    await screen.findByTestId('agent-executions-card');
    expect(screen.getByTestId('executions-platform-count')).toHaveTextContent('0');
    expect(screen.getByTestId('executions-claude-code-count')).toHaveTextContent('0');
  });
});

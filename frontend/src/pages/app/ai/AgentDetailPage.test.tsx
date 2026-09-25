import { screen, fireEvent, waitFor } from '@testing-library/react';
import { Routes, Route } from 'react-router-dom';
import { render } from '@/test-utils';
import AgentDetailPage from './AgentDetailPage';

// fc-43: AgentDetailPage is the ONE agent detail surface. The global
// AgentDetailModal's tabs (Config, History, Teams, Skills, Workspaces) and its
// manage actions (clone, edit, pause/resume, archive, delete) were folded in,
// and the per-agent memory page became the Memory tab at the same URL.

jest.mock('@/shared/services/ai', () => ({
  agentsApi: {
    getAgent: jest.fn(),
    getAgentStats: jest.fn(),
    getAgentAnalytics: jest.fn(),
    cloneAgent: jest.fn(),
    pauseAgent: jest.fn(),
    resumeAgent: jest.fn(),
    archiveAgent: jest.fn(),
    deleteAgent: jest.fn(),
  },
  intelligenceApi: {
    getIntelligenceSummary: jest.fn().mockResolvedValue(null),
    getExperienceReplays: jest.fn().mockResolvedValue(null),
  },
}));

jest.mock('@/features/ai/chat/context/ChatWindowContext', () => ({
  useChatWindow: () => ({ openConversationMaximized: () => {} }),
}));
jest.mock('@/features/ai/agents/components/AgentConnectionsGraph', () => ({
  AgentConnectionsGraph: () => <div data-testid="connections-panel" />,
}));
jest.mock('@/features/ai/memory/components/ContextBrowser', () => ({
  ContextBrowser: () => <div data-testid="knowledge-panel" />,
}));
jest.mock('@/features/ai/agents/components/detail-tabs/AgentHistoryTab', () => ({
  AgentHistoryTab: () => <div data-testid="history-panel" />,
}));
jest.mock('@/features/ai/agents/components/detail-tabs/AgentTeamsTab', () => ({
  AgentTeamsTab: () => <div data-testid="teams-panel" />,
}));
jest.mock('@/features/ai/agents/components/detail-tabs/AgentSkillsTab', () => ({
  AgentSkillsTab: () => <div data-testid="skills-panel" />,
}));
jest.mock('@/features/ai/agents/components/detail-tabs/AgentWorkspacesTab', () => ({
  AgentWorkspacesTab: () => <div data-testid="workspaces-panel" />,
}));
jest.mock('@/features/ai/agents/components/detail-tabs/AgentMemoryTab', () => ({
  AgentMemoryTab: ({ agentId }: { agentId: string }) => <div data-testid="memory-panel">{agentId}</div>,
}));
jest.mock('@/features/ai/agents/components/EditAgentModal', () => ({
  EditAgentModal: ({ isOpen }: { isOpen: boolean }) => (isOpen ? <div data-testid="edit-agent-modal" /> : null),
}));

import { agentsApi } from '@/shared/services/ai';

const agent = {
  id: 'agent-1',
  name: 'CVE Responder',
  description: 'CVE intake and remediation.',
  status: 'active',
  agent_type: 'monitor',
  model: 'claude-opus-5',
  temperature: 0.2,
  max_tokens: 4096,
  system_prompt: 'You triage CVEs.',
  created_at: '2026-09-01T00:00:00Z',
  execution_stats: {
    total_executions: 5,
    successful_executions: 5,
    failed_executions: 0,
    success_rate: 100,
    avg_execution_time: 1.5,
    by_executor_kind: { platform: 3, claude_code: 2 },
  },
};

const ALL_PERMISSIONS = [
  'ai.agents.read', 'ai.agents.create', 'ai.agents.update', 'ai.agents.execute', 'ai.agents.delete',
  'ai.memory.read', 'ai.context.read',
];

const renderAt = (path: string, permissions: string[] = ALL_PERMISSIONS) => {
  window.history.pushState({}, '', path);
  return render(
    <Routes>
      <Route path="/app/ai/agents/:agentId/*" element={<AgentDetailPage />} />
      <Route path="/app/ai/agents" element={<div data-testid="agents-list" />} />
    </Routes>,
    {
      preloadedState: {
        auth: { user: { id: 'u1', permissions }, isAuthenticated: true, isLoading: false },
      },
    },
  );
};

describe('AgentDetailPage — the one agent detail surface (fc-43)', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (agentsApi.getAgent as jest.Mock).mockResolvedValue(agent);
    (agentsApi.getAgentStats as jest.Mock).mockRejectedValue(new Error('no stats'));
    (agentsApi.getAgentAnalytics as jest.Mock).mockRejectedValue(new Error('no analytics'));
  });

  it('renders every detail tab, each at its own path', async () => {
    renderAt('/app/ai/agents/agent-1');

    await screen.findByRole('button', { name: 'Back to Agents' });
    for (const label of ['Overview', 'History', 'Teams', 'Skills', 'Workspaces', 'Knowledge', 'Memory', 'Intelligence', 'Connections']) {
      expect(screen.getByRole('tab', { name: label })).toBeInTheDocument();
    }
  });

  it.each([
    ['history', 'history-panel'],
    ['teams', 'teams-panel'],
    ['skills', 'skills-panel'],
    ['workspaces', 'workspaces-panel'],
    ['knowledge', 'knowledge-panel'],
    ['connections', 'connections-panel'],
    ['memory', 'memory-panel'],
    ['memory/pools', 'memory-panel'],
  ])('deep-links /app/ai/agents/:id/%s to its tab', async (sub, testId) => {
    renderAt(`/app/ai/agents/agent-1/${sub}`);

    expect(await screen.findByTestId(testId)).toBeInTheDocument();
  });

  it('shows the configuration and the platform vs Claude Code split on Overview', async () => {
    renderAt('/app/ai/agents/agent-1');

    expect(await screen.findByText('You triage CVEs.')).toBeInTheDocument();
    expect(screen.getByText('Temperature')).toBeInTheDocument();
    const split = screen.getByTestId('stats-by-executor-kind');
    expect(split).toHaveTextContent('3');
    expect(split).toHaveTextContent('2');
  });

  it('hides the Memory tab without ai.memory.read and Knowledge without ai.context.read', async () => {
    renderAt('/app/ai/agents/agent-1', ['ai.agents.read']);

    await screen.findByRole('button', { name: 'Back to Agents' });
    expect(screen.queryByRole('tab', { name: /^Memory$/ })).not.toBeInTheDocument();
    expect(screen.queryByRole('tab', { name: /^Knowledge$/ })).not.toBeInTheDocument();
  });

  // Each action is gated on the permission AgentsController enforces for it
  // (Ai::AgentHelpers#validate_permissions).
  it.each([
    ['Clone', 'ai.agents.create'],
    ['Edit', 'ai.agents.update'],
    ['Pause', 'ai.agents.execute'],
    ['Archive', 'ai.agents.execute'],
    ['Delete', 'ai.agents.delete'],
  ])('offers %s only with %s', async (label, permission) => {
    const { unmount } = renderAt('/app/ai/agents/agent-1', ['ai.agents.read', permission]);
    expect(await screen.findByRole('button', { name: label })).toBeInTheDocument();
    unmount();

    const others = ALL_PERMISSIONS.filter((p) => p !== permission);
    renderAt('/app/ai/agents/agent-1', others);
    await screen.findByRole('button', { name: 'Back to Agents' });
    expect(screen.queryByRole('button', { name: label })).not.toBeInTheDocument();
  });

  it('offers Resume for a paused agent with ai.agents.execute', async () => {
    (agentsApi.getAgent as jest.Mock).mockResolvedValue({ ...agent, status: 'paused' });
    renderAt('/app/ai/agents/agent-1', ['ai.agents.read', 'ai.agents.execute']);

    expect(await screen.findByRole('button', { name: 'Resume' })).toBeInTheDocument();
  });

  it('offers no manage actions with ai.agents.read alone', async () => {
    renderAt('/app/ai/agents/agent-1', ['ai.agents.read']);

    await screen.findByRole('button', { name: 'Back to Agents' });
    for (const label of ['Edit', 'Clone', 'Pause', 'Archive', 'Delete']) {
      expect(screen.queryByRole('button', { name: label })).not.toBeInTheDocument();
    }
    expect(screen.getByRole('button', { name: 'Chat' })).toBeInTheDocument();
  });

  it('opens the edit modal from Edit', async () => {
    renderAt('/app/ai/agents/agent-1');

    fireEvent.click(await screen.findByRole('button', { name: 'Edit' }));

    expect(screen.getByTestId('edit-agent-modal')).toBeInTheDocument();
  });

  it('pauses an active agent', async () => {
    (agentsApi.pauseAgent as jest.Mock).mockResolvedValue({});
    renderAt('/app/ai/agents/agent-1');

    fireEvent.click(await screen.findByRole('button', { name: 'Pause' }));

    await waitFor(() => expect(agentsApi.pauseAgent).toHaveBeenCalledWith('agent-1'));
  });

  it('opens the clone on its own detail page', async () => {
    (agentsApi.cloneAgent as jest.Mock).mockResolvedValue({ ...agent, id: 'agent-2', name: 'CVE Responder (copy)' });
    renderAt('/app/ai/agents/agent-1');

    fireEvent.click(await screen.findByRole('button', { name: 'Clone' }));

    await waitFor(() => expect(window.location.pathname).toBe('/app/ai/agents/agent-2'));
  });

  it('archives and returns to the agent list', async () => {
    (agentsApi.archiveAgent as jest.Mock).mockResolvedValue({});
    renderAt('/app/ai/agents/agent-1');

    fireEvent.click(await screen.findByRole('button', { name: 'Archive' }));

    expect(await screen.findByTestId('agents-list')).toBeInTheDocument();
    expect(agentsApi.archiveAgent).toHaveBeenCalledWith('agent-1');
  });

  it('deletes only after confirmation, then returns to the agent list', async () => {
    (agentsApi.deleteAgent as jest.Mock).mockResolvedValue({});
    renderAt('/app/ai/agents/agent-1');

    fireEvent.click(await screen.findByRole('button', { name: 'Delete' }));
    expect(agentsApi.deleteAgent).not.toHaveBeenCalled();

    const dialog = await screen.findByRole('dialog');
    fireEvent.click(Array.from(dialog.querySelectorAll('button')).find((b) => b.textContent === 'Delete')!);

    expect(await screen.findByTestId('agents-list')).toBeInTheDocument();
    expect(agentsApi.deleteAgent).toHaveBeenCalledWith('agent-1');
  });

  it('goes back to the agent list (not /app/ai/agents/list, which is not a route)', async () => {
    renderAt('/app/ai/agents/agent-1');

    fireEvent.click(await screen.findByRole('button', { name: 'Back to Agents' }));

    expect(await screen.findByTestId('agents-list')).toBeInTheDocument();
  });

  it('returns to the agent list when the agent cannot be loaded', async () => {
    (agentsApi.getAgent as jest.Mock).mockRejectedValue(new Error('not found'));
    renderAt('/app/ai/agents/missing');

    expect(await screen.findByTestId('agents-list')).toBeInTheDocument();
  });
});

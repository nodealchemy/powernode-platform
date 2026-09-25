import { screen, fireEvent, waitFor } from '@testing-library/react';
import { Routes, Route } from 'react-router-dom';
import { render } from '@/test-utils';
import { AgentsIndexTable } from './AgentsIndexTable';
import { entityRegistry } from '@/shared/services/entityRegistry';
import { registerCoreEntities } from '@/shared/entity/registerCoreEntities';

// fc-43: the agents table opens the one agent detail page — both the name and
// the View action — instead of the deleted global AgentDetailModal (?agent=).

jest.mock('@/shared/services/ai', () => ({
  ...jest.requireActual('@/shared/services/ai'),
  agentsApi: { getAgents: jest.fn() },
}));
jest.mock('@/features/ai/chat/context/ChatWindowContext', () => ({
  useChatWindow: () => ({ openConversationMaximized: () => {} }),
}));
jest.mock('./AgentExpandedRow', () => ({ AgentExpandedRow: () => null }));
jest.mock('./EditAgentModal', () => ({ EditAgentModal: () => null }));

import { agentsApi } from '@/shared/services/ai';

const agent = {
  id: 'a-1',
  name: 'CVE Responder',
  description: 'CVE intake',
  status: 'active',
  agent_type: 'monitor',
  updated_at: '2026-09-25T00:00:00Z',
};

const renderTable = () => {
  window.history.pushState({}, '', '/app/ai/agents');
  return render(
    <Routes>
      <Route path="/app/ai/agents" element={<AgentsIndexTable />} />
      <Route path="/app/ai/agents/:agentId" element={<div data-testid="agent-detail-page" />} />
    </Routes>,
    {
      preloadedState: {
        auth: { user: { id: 'u1', permissions: ['ai.agents.read'] }, isAuthenticated: true, isLoading: false },
      },
    },
  );
};

describe('AgentsIndexTable opens the agent detail page (fc-43)', () => {
  beforeEach(() => {
    entityRegistry.clear();
    registerCoreEntities();
    (agentsApi.getAgents as jest.Mock).mockResolvedValue({ items: [agent] });
  });

  it('links the agent name to /app/ai/agents/:id', async () => {
    renderTable();

    expect(await screen.findByRole('link', { name: 'CVE Responder' })).toHaveAttribute('href', '/app/ai/agents/a-1');
  });

  it('opens the detail page from View details', async () => {
    renderTable();

    fireEvent.click(await screen.findByTitle('View details'));

    expect(await screen.findByTestId('agent-detail-page')).toBeInTheDocument();
    await waitFor(() => expect(window.location.search).toBe(''));
  });
});

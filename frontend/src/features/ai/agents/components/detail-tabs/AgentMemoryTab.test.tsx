import { screen, fireEvent, waitFor } from '@testing-library/react';
import { Routes, Route } from 'react-router-dom';
import { render } from '@/test-utils';
import { AgentMemoryTab } from './AgentMemoryTab';

// fc-43: the per-agent memory page (Agent Memory, AgentMemoryApiService /
// the agent's PersistentContext) became the agent detail page's Memory tab,
// at the same URLs: /app/ai/agents/:id/memory and /memory/pools.

jest.mock('@/features/ai/memory/api/contextApi', () => ({
  contextApi: {
    getAgentMemory: jest.fn(),
    clearAgentMemory: jest.fn(),
    deleteEntry: jest.fn(),
    formatBytes: (n: number) => `${n} B`,
  },
}));
jest.mock('@/shared/services/ai/AgentMemoryApiService', () => ({
  agentMemoryApiService: { getMemoryPools: jest.fn() },
}));
jest.mock('@/features/ai/memory/components/MemoryViewer', () => ({
  MemoryViewer: ({ onAddEntry }: { onAddEntry: () => void }) => (
    <button type="button" data-testid="memory-viewer" onClick={onAddEntry}>viewer</button>
  ),
}));
jest.mock('@/features/ai/memory/components/EntryEditor', () => ({
  EntryEditor: ({ contextId }: { contextId: string }) => <div data-testid="entry-editor">{contextId}</div>,
}));

import { contextApi } from '@/features/ai/memory/api/contextApi';
import { agentMemoryApiService } from '@/shared/services/ai/AgentMemoryApiService';

const renderAt = (path: string) => {
  window.history.pushState({}, '', path);
  return render(
    <Routes>
      <Route path="/app/ai/agents/:agentId/memory/*" element={<AgentMemoryTab agentId="agent-1" />} />
      <Route path="/app/ai/knowledge/contexts/:id" element={<div data-testid="context-detail" />} />
    </Routes>,
  );
};

describe('AgentMemoryTab (fc-43)', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (contextApi.getAgentMemory as jest.Mock).mockResolvedValue({
      success: true,
      data: { memory: { id: 'ctx-1', name: 'CVE Responder memory', entry_count: 4, data_size_bytes: 512 } },
    });
    (agentMemoryApiService.getMemoryPools as jest.Mock).mockResolvedValue({
      items: [{ id: 'p1', name: 'Shared triage', pool_type: 'shared', entry_count: 7, created_at: '' }],
    });
  });

  it('shows the agent memory at /memory', async () => {
    renderAt('/app/ai/agents/agent-1/memory');

    expect(await screen.findByText('CVE Responder memory')).toBeInTheDocument();
    expect(screen.getByTestId('memory-viewer')).toBeInTheDocument();
    expect(contextApi.getAgentMemory).toHaveBeenCalledWith('agent-1');
  });

  it('shows the memory pools at /memory/pools', async () => {
    renderAt('/app/ai/agents/agent-1/memory/pools');

    expect(await screen.findByText('Shared triage')).toBeInTheDocument();
    expect(screen.queryByTestId('memory-viewer')).not.toBeInTheDocument();
  });

  it('switches sub-views by path', async () => {
    renderAt('/app/ai/agents/agent-1/memory');

    fireEvent.click(await screen.findByRole('tab', { name: /Memory Pools/ }));

    await waitFor(() => expect(window.location.pathname).toBe('/app/ai/agents/agent-1/memory/pools'));
  });

  it('opens the entry editor inline for Add Memory', async () => {
    renderAt('/app/ai/agents/agent-1/memory');

    fireEvent.click(await screen.findByRole('button', { name: 'Add Memory' }));

    expect(screen.getByTestId('entry-editor')).toHaveTextContent('ctx-1');
  });

  it('clears the memory only after confirmation', async () => {
    (contextApi.clearAgentMemory as jest.Mock).mockResolvedValue({ success: true, cleared: 4 });
    renderAt('/app/ai/agents/agent-1/memory');

    fireEvent.click(await screen.findByRole('button', { name: 'Clear All' }));
    expect(contextApi.clearAgentMemory).not.toHaveBeenCalled();

    const dialog = await screen.findByRole('dialog');
    fireEvent.click(Array.from(dialog.querySelectorAll('button')).find((b) => b.textContent === 'Clear All')!);

    await waitFor(() => expect(contextApi.clearAgentMemory).toHaveBeenCalledWith('agent-1'));
  });

  it('links to the full context in Knowledge', async () => {
    renderAt('/app/ai/agents/agent-1/memory');

    fireEvent.click(await screen.findByRole('button', { name: 'View Full Context' }));

    expect(await screen.findByTestId('context-detail')).toBeInTheDocument();
  });
});

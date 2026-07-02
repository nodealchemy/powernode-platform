import React from 'react';
import { renderHook, act, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { useAgentMemorySelection } from './useAgentMemorySelection';
import { agentsApi } from '@/shared/services/ai';
import { fetchMemoryStats } from '../api/memoryApi';

jest.mock('@/shared/services/ai', () => ({
  agentsApi: {
    getAgents: jest.fn(),
  },
}));
jest.mock('../api/memoryApi', () => ({
  fetchMemoryStats: jest.fn(),
}));
const mockAddNotification = jest.fn();
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: mockAddNotification }),
}));

const agents = [
  { id: 'agent-1', name: 'Alpha', status: 'active' },
  { id: 'agent-2', name: 'Beta', status: 'active' },
];
const statsFixture = { short_term: { count: 3 } };

function makeWrapper(initialEntry = '/memory') {
  const Wrapper: React.FC<{ children: React.ReactNode }> = ({ children }) => (
    <MemoryRouter initialEntries={[initialEntry]}>{children}</MemoryRouter>
  );
  return Wrapper;
}

describe('useAgentMemorySelection', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (agentsApi.getAgents as jest.Mock).mockResolvedValue({ items: agents });
    (fetchMemoryStats as jest.Mock).mockResolvedValue(statsFixture);
  });

  it('loads agents, auto-selects the first, and loads its stats', async () => {
    const { result } = renderHook(() => useAgentMemorySelection(), {
      wrapper: makeWrapper(),
    });

    expect(result.current.agentsLoading).toBe(true);
    await waitFor(() => expect(result.current.agentsLoading).toBe(false));

    expect(result.current.agents).toEqual(agents);
    expect(result.current.selectedAgentId).toBe('agent-1');
    await waitFor(() => expect(result.current.stats).toEqual(statsFixture));
    expect(fetchMemoryStats).toHaveBeenCalledWith('agent-1');
  });

  it('respects an agent id already present in the URL and does not override it', async () => {
    const { result } = renderHook(() => useAgentMemorySelection(), {
      wrapper: makeWrapper('/memory?memory_agent=agent-2'),
    });

    await waitFor(() => expect(result.current.agentsLoading).toBe(false));
    expect(result.current.selectedAgentId).toBe('agent-2');
    await waitFor(() => expect(fetchMemoryStats).toHaveBeenCalledWith('agent-2'));
    expect(fetchMemoryStats).not.toHaveBeenCalledWith('agent-1');
  });

  it('handleAgentChange switches the selection and refetches stats', async () => {
    const { result } = renderHook(() => useAgentMemorySelection(), {
      wrapper: makeWrapper(),
    });
    await waitFor(() => expect(result.current.agentsLoading).toBe(false));
    await waitFor(() => expect(fetchMemoryStats).toHaveBeenCalledWith('agent-1'));

    act(() => {
      result.current.handleAgentChange('agent-2');
    });

    expect(result.current.selectedAgentId).toBe('agent-2');
    await waitFor(() => expect(fetchMemoryStats).toHaveBeenCalledWith('agent-2'));
  });

  it('keeps previous stats on a stats fetch error by default', async () => {
    const { result } = renderHook(() => useAgentMemorySelection(), {
      wrapper: makeWrapper(),
    });
    await waitFor(() => expect(result.current.stats).toEqual(statsFixture));

    (fetchMemoryStats as jest.Mock).mockRejectedValueOnce(new Error('boom'));
    act(() => {
      result.current.handleAgentChange('agent-2');
    });
    await waitFor(() => expect(fetchMemoryStats).toHaveBeenCalledWith('agent-2'));

    expect(result.current.stats).toEqual(statsFixture);
  });

  it('clears stats on a fetch error when clearStatsOnError is set', async () => {
    const { result } = renderHook(
      () => useAgentMemorySelection({ clearStatsOnError: true }),
      { wrapper: makeWrapper() },
    );
    await waitFor(() => expect(result.current.stats).toEqual(statsFixture));

    (fetchMemoryStats as jest.Mock).mockRejectedValueOnce(new Error('boom'));
    act(() => {
      result.current.handleAgentChange('agent-2');
    });
    await waitFor(() => expect(result.current.stats).toBeNull());
  });

  it('tracks statsLoading around the fetch', async () => {
    let resolveStats: (v: unknown) => void = () => {};
    (fetchMemoryStats as jest.Mock).mockImplementation(
      () => new Promise((resolve) => { resolveStats = resolve; }),
    );
    const { result } = renderHook(() => useAgentMemorySelection(), {
      wrapper: makeWrapper(),
    });

    await waitFor(() => expect(result.current.statsLoading).toBe(true));
    act(() => resolveStats(statsFixture));
    await waitFor(() => expect(result.current.statsLoading).toBe(false));
    expect(result.current.stats).toEqual(statsFixture);
  });

  it('notifies on agents load failure and finishes loading', async () => {
    (agentsApi.getAgents as jest.Mock).mockRejectedValueOnce(new Error('down'));
    const { result } = renderHook(() => useAgentMemorySelection(), {
      wrapper: makeWrapper(),
    });

    await waitFor(() => expect(result.current.agentsLoading).toBe(false));
    expect(result.current.agents).toEqual([]);
    expect(result.current.selectedAgentId).toBe('');
    expect(mockAddNotification).toHaveBeenCalledWith({
      type: 'error',
      message: 'Failed to load agents',
    });
    expect(fetchMemoryStats).not.toHaveBeenCalled();
  });
});

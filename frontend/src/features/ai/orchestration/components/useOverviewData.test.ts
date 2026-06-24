import { renderHook, act, waitFor } from '@testing-library/react';
import { useOverviewData } from './useOverviewData';
import * as aiOrchestrationMonitor from '../services/aiOrchestrationMonitor';
import { agentsApi, providersApi, conversationsApi } from '@/shared/services/ai';

// Regression: the 30s fallback poll evaluated isConnected() only once at effect
// setup. WS connection state was never lifted into React state, so a mid-session
// disconnect produced no re-render and the poll effect never re-ran to start
// polling -> dashboard silently froze until reload. The fix lifts connection
// status into React state via the monitor's connection-change subscription so the
// poll effect re-runs on disconnect (starts polling) and on reconnect (stops).

jest.mock('@/shared/services/ai', () => ({
  providersApi: { getProviders: jest.fn() },
  agentsApi: { getAgents: jest.fn() },
  conversationsApi: { getConversations: jest.fn() },
}));
jest.mock('../services/aiOrchestrationMonitor');

describe('useOverviewData fallback poll on mid-session disconnect', () => {
  let connectionListener: ((connected: boolean) => void) | undefined;
  let connected: boolean;

  beforeEach(() => {
    jest.clearAllMocks();
    jest.clearAllTimers();
    jest.useFakeTimers();

    connectionListener = undefined;
    connected = true; // start the session connected

    (aiOrchestrationMonitor.useAIOrchestrationMonitor as jest.Mock).mockReturnValue({
      subscribe: jest.fn(() => jest.fn()),
      isConnected: jest.fn(() => connected),
      onConnectionChange: jest.fn((handler: (c: boolean) => void) => {
        connectionListener = handler;
        return () => {
          connectionListener = undefined;
        };
      }),
      monitor: null,
    });
    (aiOrchestrationMonitor.resetAIOrchestrationMonitor as jest.Mock).mockImplementation(() => {});

    (providersApi.getProviders as jest.Mock).mockResolvedValue({ providers: [] });
    (agentsApi.getAgents as jest.Mock).mockResolvedValue({ agents: [] });
    (conversationsApi.getConversations as jest.Mock).mockResolvedValue({ items: [] });
  });

  afterEach(() => {
    jest.runOnlyPendingTimers();
    jest.useRealTimers();
  });

  it('starts the 30s fallback poll after a mid-session disconnect', async () => {
    renderHook(() => useOverviewData());

    // Initial load (one call) while connected; advancing time must NOT poll.
    await waitFor(() => expect(providersApi.getProviders).toHaveBeenCalledTimes(1));
    act(() => {
      jest.advanceTimersByTime(60000);
    });
    expect(providersApi.getProviders).toHaveBeenCalledTimes(1);

    // Mid-session disconnect: monitor notifies, hook lifts it into state and the
    // poll effect re-runs to start the fallback interval.
    act(() => {
      connected = false;
      connectionListener?.(false);
    });
    act(() => {
      jest.advanceTimersByTime(30000);
    });

    await waitFor(() => expect(providersApi.getProviders).toHaveBeenCalledTimes(2));
  });
});

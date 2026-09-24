import React from 'react';
import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { renderWithProviders } from '@/test-utils';
import { ApprovalQueuePanel } from './ApprovalQueuePanel';

// MCP identity plan R2: an agent or MCP client that asks for a human-only
// action parks it, and only a person in their own session decides it. The
// card must say so, and it must show the exact action (the description the
// tool wrote), so the person knows what they are confirming.

const mockGet = jest.fn();
const mockPost = jest.fn();

jest.mock('@/shared/services/apiClient', () => ({
  __esModule: true,
  apiClient: {
    get: (...args: unknown[]) => mockGet(...args),
    post: (...args: unknown[]) => mockPost(...args),
  },
  default: {
    get: (...args: unknown[]) => mockGet(...args),
    post: (...args: unknown[]) => mockPost(...args),
  },
}));

jest.mock('@/shared/components/entity', () => ({
  EntityLink: ({ label }: { label: React.ReactNode }) => <span>{label}</span>,
}));

jest.mock('@/shared/hooks/useWebSocket', () => {
  const socket = { isConnected: false, error: null, subscribe: () => () => undefined };
  return { useWebSocket: () => socket };
});
jest.mock('@/shared/hooks/usePolling', () => ({ usePolling: jest.fn() }));

const HUMAN_ROW = {
  id: 'req-h',
  request_id: 'req-h',
  action_category: 'campaign.resume',
  source_type: 'Ai::DeferredOperation',
  status: 'pending',
  description: 'Resume campaign "Alpha": max_failed 2 -> 6',
  request_data: { action_category: 'campaign.resume' },
  created_at: '2026-09-11T00:00:00Z',
  current_step_can_approve: true,
  requires_human_session: true,
};

const PLAIN_ROW = {
  id: 'req-p',
  request_id: 'req-p',
  action_category: 'release.rollback',
  source_type: 'Ai::DeferredOperation',
  status: 'pending',
  description: 'Roll a module back',
  request_data: { action_category: 'release.rollback' },
  created_at: '2026-09-11T00:01:00Z',
  current_step_can_approve: true,
  requires_human_session: false,
};

const renderPanel = () => {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  return renderWithProviders(
    <QueryClientProvider client={queryClient}>
      <ApprovalQueuePanel />
    </QueryClientProvider>,
    {
      preloadedState: {
        auth: {
          user: { id: 'u-1', permissions: ['ai.agents.read', 'ai.autonomy.approve'] },
          isAuthenticated: true,
          isLoading: false,
        },
      },
    }
  );
};

describe('ApprovalQueuePanel human-only requests', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockGet.mockImplementation((url: string) =>
      Promise.resolve(
        String(url).endsWith('/req-h')
          ? { data: { data: { ...HUMAN_ROW, step_statuses: [], decisions: [] } } }
          : { data: { data: [HUMAN_ROW, PLAIN_ROW] } }
      )
    );
  });

  it('badges the human-only row, and only it, and shows the exact action it asks for', async () => {
    renderPanel();

    expect(await screen.findByText('Resume campaign "Alpha": max_failed 2 -> 6')).toBeInTheDocument();
    expect(screen.getAllByText('Needs a person')).toHaveLength(1);
    expect(screen.getByText('Roll a module back')).toBeInTheDocument();
  });

  it('explains, once expanded, that only a person decides it, here, in their own session', async () => {
    const user = userEvent.setup();
    renderPanel();

    await user.click(await screen.findByText('campaign.resume'));

    expect(
      await screen.findByText(/Only a person can decide this, here, in their own session\. An agent or MCP client cannot\s+approve or reject it\./)
    ).toBeInTheDocument();
  });
});

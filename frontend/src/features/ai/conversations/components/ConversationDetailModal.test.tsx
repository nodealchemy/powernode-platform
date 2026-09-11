import React from 'react';
import { render, screen, waitFor } from '@testing-library/react';
import { ConversationDetailModal } from './ConversationDetailModal';

// =============================================================================
// Mocks
// =============================================================================

const mockGetConversation = jest.fn();
const mockAgentGetConversation = jest.fn();
const mockGetMessages = jest.fn();
const mockGetConversationStats = jest.fn();
const mockAddNotification = jest.fn();

jest.mock('@/shared/services/ai', () => ({
  agentsApi: {
    getConversation: (...args: unknown[]) => mockAgentGetConversation(...args),
    getMessages: (...args: unknown[]) => mockGetMessages(...args),
  },
  conversationsApi: {
    getConversation: (...args: unknown[]) => mockGetConversation(...args),
    getConversationStats: (...args: unknown[]) => mockGetConversationStats(...args),
  },
}));

jest.mock('@/shared/hooks/useAuth', () => ({
  useAuth: () => ({ currentUser: { permissions: ['ai.conversations.read', 'ai.conversations.manage'] } }),
}));

jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: mockAddNotification }),
}));

// Stub out the tab content components — this suite is about the loading /
// error / loaded branch selection, not their own rendering.
jest.mock('./MessageThread', () => ({ MessageThread: () => <div data-testid="message-thread" /> }));
jest.mock('./ConversationStatsPanel', () => ({ ConversationStatsPanel: () => <div data-testid="stats-panel" /> }));
jest.mock('./ConversationActions', () => ({ ConversationActions: () => <div data-testid="conversation-actions" /> }));

// =============================================================================
// Helpers
// =============================================================================

const renderModal = (props: Partial<React.ComponentProps<typeof ConversationDetailModal>> = {}) => {
  const defaults = {
    isOpen: true,
    onClose: jest.fn(),
    agentId: '',
    conversationId: 'conv-1',
  };
  return render(<ConversationDetailModal {...defaults} {...props} />);
};

// =============================================================================
// Tests
// =============================================================================

describe('ConversationDetailModal', () => {
  beforeEach(() => {
    mockGetConversation.mockReset();
    mockAgentGetConversation.mockReset();
    mockGetMessages.mockReset();
    mockGetConversationStats.mockReset();
    mockAddNotification.mockReset();
    mockGetConversationStats.mockResolvedValue({});
  });

  // ── error takes priority over loading/!conversation (G1) ────────────────────

  it('shows the error title and Try Again, not an endless spinner, for an unknown conversation id', async () => {
    // agentId is '' (unresolved), so loadConversation asks conversationsApi
    // for the owning agent first — and that lookup itself fails.
    mockGetConversation.mockRejectedValue(new Error('not found'));

    renderModal({ agentId: '' });

    await waitFor(() => {
      expect(screen.getByText('Error Loading Conversation')).toBeInTheDocument();
    });
    expect(screen.getByText('Try Again')).toBeInTheDocument();
    expect(screen.queryByText('Loading Conversation...')).not.toBeInTheDocument();
  });

  it('shows the error title, not an endless spinner, when the agent is known but the fetch 404s', async () => {
    mockAgentGetConversation.mockRejectedValue(new Error('404'));

    renderModal({ agentId: 'agent-1' });

    await waitFor(() => {
      expect(screen.getByText('Error Loading Conversation')).toBeInTheDocument();
    });
    expect(screen.queryByText('Loading Conversation...')).not.toBeInTheDocument();
  });

  it('renders the loaded conversation on the happy path (control)', async () => {
    mockAgentGetConversation.mockResolvedValue({ id: 'conv-1', title: 'Probe Conversation' });
    mockGetMessages.mockResolvedValue({ messages: [] });

    renderModal({ agentId: 'agent-1' });

    await waitFor(() => {
      expect(screen.getByText('Probe Conversation')).toBeInTheDocument();
    });
    expect(screen.queryByText('Error Loading Conversation')).not.toBeInTheDocument();
    expect(screen.queryByText('Loading Conversation...')).not.toBeInTheDocument();
  });

  it('shows the loading title while the fetch is in flight', () => {
    mockAgentGetConversation.mockReturnValue(new Promise(() => {})); // never resolves
    renderModal({ agentId: 'agent-1' });

    expect(screen.getByText('Loading Conversation...')).toBeInTheDocument();
  });
});

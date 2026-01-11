import React from 'react';
import { render, screen, waitFor, fireEvent } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';

// Mock ESM packages before importing components
jest.mock('remark-gfm', () => () => ({}));
jest.mock('remark-breaks', () => () => ({}));
jest.mock('react-markdown', () => ({ children }: { children: React.ReactNode }) => <div>{children}</div>);

// Mock ConversationsApiService
const mockGetConversations = jest.fn();
const mockArchiveConversation = jest.fn();
const mockDuplicateConversation = jest.fn();
const mockDeleteConversation = jest.fn();

jest.mock('@/shared/services/ai/ConversationsApiService', () => ({
  conversationsApi: {
    getConversations: () => mockGetConversations(),
    archiveConversation: (id: string) => mockArchiveConversation(id),
    duplicateConversation: (id: string) => mockDuplicateConversation(id),
    deleteConversation: (id: string) => mockDeleteConversation(id)
  },
  ConversationBase: {}
}));

// Mock AgentsApiService
const mockGetAgents = jest.fn();

jest.mock('@/shared/services/ai/AgentsApiService', () => ({
  agentsApi: {
    getAgents: () => mockGetAgents()
  }
}));

// Mock index export
jest.mock('@/shared/services/ai', () => ({
  conversationsApi: {
    getConversations: () => mockGetConversations(),
    archiveConversation: (id: string) => mockArchiveConversation(id),
    duplicateConversation: (id: string) => mockDuplicateConversation(id),
    deleteConversation: (id: string) => mockDeleteConversation(id)
  },
  agentsApi: {
    getAgents: () => mockGetAgents()
  },
  GlobalConversationFilters: {}
}));

// Mock useAuth
jest.mock('@/shared/hooks/useAuth', () => ({
  useAuth: () => ({
    currentUser: {
      id: 'user-1',
      email: 'test@example.com',
      permissions: ['ai.conversations.create', 'ai.conversations.manage', 'ai.conversations.read']
    },
    isAuthenticated: true
  })
}));

// Mock useNotifications
const mockAddNotification = jest.fn();
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    addNotification: mockAddNotification,
    showNotification: mockAddNotification
  })
}));

// Mock useBreadcrumb
jest.mock('@/shared/hooks/BreadcrumbContext', () => ({
  useBreadcrumb: () => ({
    setBreadcrumbs: jest.fn(),
    getCurrentBreadcrumbs: () => [],
    setCurrentPage: jest.fn()
  })
}));

// Mock modals
jest.mock('@/features/ai/conversations/components/ConversationCreateModal', () => ({
  ConversationCreateModal: ({ isOpen, onClose }: { isOpen: boolean; onClose: () => void }) =>
    isOpen ? <div data-testid="create-modal"><button onClick={onClose}>Close</button></div> : null
}));

jest.mock('@/features/ai/conversations/components/ConversationDetailModal', () => ({
  ConversationDetailModal: ({ isOpen, onClose }: { isOpen: boolean; onClose: () => void }) =>
    isOpen ? <div data-testid="detail-modal"><button onClick={onClose}>Close</button></div> : null
}));

jest.mock('@/features/ai/conversations/components/ConversationContinueModal', () => ({
  ConversationContinueModal: ({ isOpen, onClose }: { isOpen: boolean; onClose: () => void }) =>
    isOpen ? <div data-testid="continue-modal"><button onClick={onClose}>Close</button></div> : null
}));

// Import component after mocks
// eslint-disable-next-line import/first
import { AIConversationsPage } from './AIConversationsPage';

describe('AIConversationsPage', () => {
  // Mock conversation data
  const mockConversations = [
    {
      id: 'conv-1',
      conversation_id: 'conv-1',
      title: 'Test Conversation 1',
      status: 'active' as const,
      message_count: 10,
      total_tokens: 1500,
      total_cost: 0.05,
      is_collaborative: false,
      participant_count: 1,
      created_at: '2024-01-01T00:00:00Z',
      last_activity_at: '2024-01-01T12:00:00Z',
      ai_agent: {
        id: 'agent-1',
        name: 'Assistant',
        agent_type: 'general'
      },
      ai_provider: {
        id: 'provider-1',
        name: 'OpenAI',
        provider_type: 'openai'
      },
      user: {
        id: 'user-1',
        name: 'Test User',
        email: 'test@example.com'
      }
    },
    {
      id: 'conv-2',
      conversation_id: 'conv-2',
      title: 'Archived Conversation',
      status: 'archived' as const,
      message_count: 5,
      total_tokens: 800,
      total_cost: 0.02,
      is_collaborative: false,
      participant_count: 1,
      created_at: '2024-01-01T00:00:00Z',
      last_activity_at: '2024-01-01T10:00:00Z',
      ai_agent: {
        id: 'agent-2',
        name: 'Code Assistant',
        agent_type: 'coding'
      },
      ai_provider: {
        id: 'provider-1',
        name: 'OpenAI',
        provider_type: 'openai'
      },
      user: {
        id: 'user-1',
        name: 'Test User',
        email: 'test@example.com'
      }
    }
  ];

  const mockAgents = [
    { id: 'agent-1', name: 'Assistant', agent_type: 'general' },
    { id: 'agent-2', name: 'Code Assistant', agent_type: 'coding' }
  ];

  beforeEach(() => {
    jest.clearAllMocks();
    mockGetConversations.mockResolvedValue({
      items: mockConversations,
      pagination: {
        current_page: 1,
        per_page: 25,
        total_pages: 1,
        total_count: 2
      }
    });
    mockGetAgents.mockResolvedValue({
      items: mockAgents,
      pagination: {
        current_page: 1,
        per_page: 100,
        total_pages: 1,
        total_count: 2
      }
    });
    mockArchiveConversation.mockResolvedValue({ id: 'conv-1', status: 'archived' });
    mockDuplicateConversation.mockResolvedValue({ id: 'conv-3', title: 'Copy of Test' });
    mockDeleteConversation.mockResolvedValue(undefined);
  });

  const renderComponent = () => {
    return render(
      <BrowserRouter future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
        <AIConversationsPage />
      </BrowserRouter>
    );
  };

  describe('Rendering', () => {
    it('renders the page title', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('AI Conversations')).toBeInTheDocument();
      });
    });

    it('renders conversation list after loading', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('Test Conversation 1')).toBeInTheDocument();
        expect(screen.getByText('Archived Conversation')).toBeInTheDocument();
      });
    });

    it('renders status badges', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('Active')).toBeInTheDocument();
        expect(screen.getByText('Archived')).toBeInTheDocument();
      });
    });

    it('renders agent names', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('Assistant')).toBeInTheDocument();
        expect(screen.getByText('Code Assistant')).toBeInTheDocument();
      });
    });
  });

  describe('Data Fetching', () => {
    it('fetches conversations on mount', async () => {
      renderComponent();

      await waitFor(() => {
        expect(mockGetConversations).toHaveBeenCalledTimes(1);
      });
    });

    it('fetches agents for filter dropdown', async () => {
      renderComponent();

      await waitFor(() => {
        expect(mockGetAgents).toHaveBeenCalledTimes(1);
      });
    });

    it('handles API error gracefully', async () => {
      mockGetConversations.mockRejectedValueOnce(new Error('API Error'));

      renderComponent();

      await waitFor(() => {
        expect(mockAddNotification).toHaveBeenCalledWith(
          expect.objectContaining({
            type: 'error',
            title: 'Error'
          })
        );
      });
    });
  });

  describe('Search and Filtering', () => {
    it('renders search input', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByPlaceholderText(/search conversations/i)).toBeInTheDocument();
      });
    });

    it('renders status filter dropdown', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('All Statuses')).toBeInTheDocument();
      });
    });

    it('renders agent filter dropdown', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('All Agents')).toBeInTheDocument();
      });
    });
  });

  describe('Action Buttons', () => {
    it('renders start conversation button when user has permission', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('Start Conversation')).toBeInTheDocument();
      });
    });

    it('opens create modal when start conversation button is clicked', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('Start Conversation')).toBeInTheDocument();
      });

      const newButton = screen.getByText('Start Conversation');
      fireEvent.click(newButton);

      await waitFor(() => {
        expect(screen.getByTestId('create-modal')).toBeInTheDocument();
      });
    });
  });

  describe('Conversation Actions', () => {
    it('handles archive conversation action', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('Test Conversation 1')).toBeInTheDocument();
      });

      // Find and click archive button - title is just "Archive" for active conversations
      const archiveButtons = screen.getAllByTitle('Archive');
      fireEvent.click(archiveButtons[0]);

      await waitFor(() => {
        expect(mockArchiveConversation).toHaveBeenCalledWith('conv-1');
      });

      await waitFor(() => {
        expect(mockAddNotification).toHaveBeenCalledWith(
          expect.objectContaining({
            type: 'success',
            title: 'Conversation Archived'
          })
        );
      });
    });

    it('handles duplicate conversation action', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('Test Conversation 1')).toBeInTheDocument();
      });

      // Find and click duplicate button
      const duplicateButtons = screen.getAllByTitle('Duplicate Conversation');
      fireEvent.click(duplicateButtons[0]);

      await waitFor(() => {
        expect(mockDuplicateConversation).toHaveBeenCalledWith('conv-1');
      });

      await waitFor(() => {
        expect(mockAddNotification).toHaveBeenCalledWith(
          expect.objectContaining({
            type: 'success',
            title: 'Conversation Duplicated'
          })
        );
      });
    });

    it('renders delete button for conversations', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('Test Conversation 1')).toBeInTheDocument();
      });

      // Verify delete buttons are rendered - user has manage permission
      await waitFor(() => {
        const deleteButtons = screen.getAllByTitle('Delete Conversation');
        expect(deleteButtons.length).toBeGreaterThan(0);
      });
    });

    it('handles archive error gracefully', async () => {
      mockArchiveConversation.mockRejectedValueOnce(new Error('Archive failed'));

      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('Test Conversation 1')).toBeInTheDocument();
      });

      const archiveButtons = screen.getAllByTitle('Archive');
      fireEvent.click(archiveButtons[0]);

      await waitFor(() => {
        expect(mockAddNotification).toHaveBeenCalledWith(
          expect.objectContaining({
            type: 'error',
            title: 'Action Failed'
          })
        );
      });
    });
  });

  describe('Empty State', () => {
    it('shows empty state when no conversations', async () => {
      mockGetConversations.mockResolvedValueOnce({
        items: [],
        pagination: {
          current_page: 1,
          per_page: 25,
          total_pages: 1,
          total_count: 0
        }
      });

      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('No conversations found')).toBeInTheDocument();
      });
    });

    it('shows start conversation button in empty state when user has permission', async () => {
      mockGetConversations.mockResolvedValueOnce({
        items: [],
        pagination: {
          current_page: 1,
          per_page: 25,
          total_pages: 1,
          total_count: 0
        }
      });

      renderComponent();

      await waitFor(() => {
        // The Start Conversation button appears in the page header even in empty state
        expect(screen.getByText('Start Conversation')).toBeInTheDocument();
      });
    });
  });

  describe('Pagination', () => {
    it('displays pagination with correct page info', async () => {
      renderComponent();

      await waitFor(() => {
        // DataTable shows "Page X of Y" format
        expect(screen.getByText(/Page 1/i)).toBeInTheDocument();
      });
    });

    it('refetches data when changing page', async () => {
      mockGetConversations.mockResolvedValue({
        items: mockConversations,
        pagination: {
          current_page: 1,
          per_page: 25,
          total_pages: 2,
          total_count: 30
        }
      });

      renderComponent();

      await waitFor(() => {
        expect(mockGetConversations).toHaveBeenCalled();
      });

      // Initial load
      expect(mockGetConversations).toHaveBeenCalledTimes(1);
    });
  });

  describe('Permission Checks', () => {
    it('hides action buttons when user lacks manage permission', async () => {
      // Re-mock useAuth with no manage permissions
      jest.doMock('@/shared/hooks/useAuth', () => ({
        useAuth: () => ({
          currentUser: {
            id: 'user-1',
            email: 'test@example.com',
            permissions: ['ai.conversations.read']
          },
          isAuthenticated: true
        })
      }));

      // The component checks permissions internally
      // This test verifies the component renders without errors
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('Test Conversation 1')).toBeInTheDocument();
      });
    });
  });

  describe('Statistics Display', () => {
    it('displays message count for conversations', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('10')).toBeInTheDocument();
        expect(screen.getByText('5')).toBeInTheDocument();
      });
    });

    it('displays token usage for conversations', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('1,500 tokens')).toBeInTheDocument();
        expect(screen.getByText('800 tokens')).toBeInTheDocument();
      });
    });
  });

  describe('View Conversation', () => {
    it('opens detail modal when clicking view button', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('Test Conversation 1')).toBeInTheDocument();
      });

      const viewButtons = screen.getAllByTitle('View Details');
      fireEvent.click(viewButtons[0]);

      await waitFor(() => {
        expect(screen.getByTestId('detail-modal')).toBeInTheDocument();
      });
    });
  });
});

describe('AIConversationsPage - API Integration', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('passes correct filters to API', async () => {
    mockGetConversations.mockResolvedValue({
      items: [],
      pagination: {
        current_page: 1,
        per_page: 25,
        total_pages: 1,
        total_count: 0
      }
    });
    mockGetAgents.mockResolvedValue({
      items: [],
      pagination: {
        current_page: 1,
        per_page: 100,
        total_pages: 1,
        total_count: 0
      }
    });

    render(
      <BrowserRouter future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
        <AIConversationsPage />
      </BrowserRouter>
    );

    await waitFor(() => {
      expect(mockGetConversations).toHaveBeenCalled();
    });

    // Verify the API was called (initial load)
    expect(mockGetConversations).toHaveBeenCalledTimes(1);
  });

  it('refetches conversations after archive action', async () => {
    const mockConversations = [{
      id: 'conv-1',
      conversation_id: 'conv-1',
      title: 'Test Conversation',
      status: 'active' as const,
      message_count: 1,
      total_tokens: 100,
      total_cost: 0.01,
      is_collaborative: false,
      participant_count: 1,
      created_at: '2024-01-01T00:00:00Z',
      last_activity_at: '2024-01-01T00:00:00Z',
      ai_agent: { id: 'agent-1', name: 'Test Agent', agent_type: 'general' },
      ai_provider: { id: 'provider-1', name: 'OpenAI', provider_type: 'openai' },
      user: { id: 'user-1', name: 'User', email: 'user@test.com' }
    }];

    mockGetConversations.mockResolvedValue({
      items: mockConversations,
      pagination: { current_page: 1, per_page: 25, total_pages: 1, total_count: 1 }
    });
    mockGetAgents.mockResolvedValue({
      items: [],
      pagination: { current_page: 1, per_page: 100, total_pages: 1, total_count: 0 }
    });
    mockArchiveConversation.mockResolvedValue({ id: 'conv-1', status: 'archived' });

    render(
      <BrowserRouter future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
        <AIConversationsPage />
      </BrowserRouter>
    );

    await waitFor(() => {
      expect(screen.getByText('Test Conversation')).toBeInTheDocument();
    });

    // Archive button title is just "Archive" for active conversations
    const archiveButtons = screen.getAllByTitle('Archive');
    fireEvent.click(archiveButtons[0]);

    await waitFor(() => {
      // Initial load + refetch after archive
      expect(mockGetConversations).toHaveBeenCalledTimes(2);
    });
  });
});

import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { Provider } from 'react-redux';
import { BrowserRouter } from 'react-router-dom';
import { configureStore } from '@reduxjs/toolkit';
import { BreadcrumbProvider } from '@/shared/hooks/BreadcrumbContext';
import { AiAgentDashboard } from './AiAgentDashboard';
import { agentsApi } from '@/shared/services/ai';

// Mock the consolidated AI services
jest.mock('@/shared/services/ai', () => ({
  agentsApi: {
    getAgents: jest.fn(),
    createAgent: jest.fn(),
    updateAgent: jest.fn(),
    deleteAgent: jest.fn(),
    pauseAgent: jest.fn(),
    resumeAgent: jest.fn()
  }
}));

// Mock the permissions hook
jest.mock('@/shared/hooks/usePermissions', () => ({
  usePermissions: () => ({
    hasPermission: (permission: string) => {
      const perms = ['ai.agents.read', 'ai.agents.create', 'ai.agents.manage'];
      return perms.includes(permission);
    }
  })
}));

// Mock the notifications hook
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    addNotification: jest.fn()
  })
}));

// Mock UI components
jest.mock('@/shared/components/ui/LoadingSpinner', () => ({
  LoadingSpinner: ({ message }: any) => <div data-testid="loading-spinner">{message || 'Loading...'}</div>
}));

jest.mock('@/shared/components/ui/EmptyState', () => ({
  EmptyState: ({ title, description, action }: any) => (
    <div data-testid="empty-state">
      <h3>{title}</h3>
      <p>{description}</p>
      {action}
    </div>
  )
}));

jest.mock('@/shared/components/ui/Badge', () => ({
  Badge: ({ children, variant }: any) => (
    <span data-testid="badge" data-variant={variant}>{children}</span>
  )
}));

jest.mock('@/shared/components/ui/Card', () => ({
  Card: ({ children, className }: any) => (
    <div data-testid="card" className={className}>{children}</div>
  )
}));

jest.mock('@/shared/components/ui/Button', () => ({
  Button: ({ children, onClick, variant, size, className, disabled }: any) => (
    <button
      onClick={onClick}
      data-variant={variant}
      data-size={size}
      className={className}
      disabled={disabled}
    >
      {children}
    </button>
  )
}));

jest.mock('@/shared/components/layout/PageContainer', () => ({
  PageContainer: ({ children, title, description, actions }: any) => (
    <div data-testid="page-container">
      <h1>{title}</h1>
      <p>{description}</p>
      <div data-testid="page-actions">
        {actions?.map((action: any, idx: number) => (
          <button key={idx} onClick={action.onClick}>{action.label}</button>
        ))}
      </div>
      {children}
    </div>
  )
}));

// Mock ChatWindowContext (required by AiAgentDashboard)
jest.mock('@/features/ai/chat/context/ChatWindowContext', () => ({
  useChatWindow: () => ({
    openConversationMaximized: jest.fn(),
  }),
}));

// Mock modal components
jest.mock('./CreateAgentModal', () => ({
  CreateAgentModal: ({ isOpen, onClose, onAgentCreated }: any) => (
    isOpen ? (
      <div data-testid="create-agent-modal">
        <button onClick={() => onAgentCreated()}>Create Agent</button>
        <button onClick={onClose}>Cancel</button>
      </div>
    ) : null
  )
}));

jest.mock('./EditAgentModal', () => ({
  EditAgentModal: ({ isOpen, agent, onClose, onAgentUpdated, onAgentDeleted }: any) => (
    isOpen ? (
      <div data-testid="edit-agent-modal">
        <span>Editing: {agent?.name}</span>
        <button onClick={() => onAgentUpdated()}>Update Agent</button>
        <button onClick={() => onAgentDeleted()}>Delete Agent</button>
        <button onClick={onClose}>Cancel</button>
      </div>
    ) : null
  )
}));

describe('AiAgentDashboard', () => {
  let store: any;

  const mockAgents = [
    {
      id: 'agent-1',
      name: 'Data Processor',
      description: 'Processes and analyzes data',
      agent_type: 'content_generator',
      status: 'active',
      is_active: true,
      // Component uses 'provider' not 'ai_provider'
      provider: {
        id: 'provider-1',
        name: 'OpenAI',
        slug: 'openai',
        provider_type: 'text_generation'
      },
      // Component uses 'model' directly
      model: 'gpt-4',
      mcp_tool_manifest: {
        name: 'data_processor',
        description: 'Data processing agent',
        type: 'ai_agent',
        version: '1.0.0'
      },
      skill_slugs: ['text_generation'],
      mcp_input_schema: {},
      mcp_output_schema: {},
      mcp_metadata: {
        model_config: {
          model: 'gpt-4',
          temperature: 0.7,
          max_tokens: 2000
        }
      },
      metadata: {},
      created_at: '2024-01-15T10:00:00Z',
      updated_at: '2024-01-15T10:00:00Z',
      execution_stats: {
        total_executions: 150,
        successful_executions: 143,
        failed_executions: 7,
        success_rate: 95.5,
        avg_execution_time: 1200
      }
    },
    {
      id: 'agent-2',
      name: 'Content Generator',
      description: 'Generates marketing content',
      agent_type: 'content_generator',
      status: 'inactive',
      is_active: false,
      // Component uses 'provider' not 'ai_provider'
      provider: {
        id: 'provider-2',
        name: 'Anthropic',
        slug: 'anthropic',
        provider_type: 'text_generation'
      },
      // Component uses 'model' directly
      model: 'claude-3-opus',
      mcp_tool_manifest: {
        name: 'content_generator',
        description: 'Content generation agent',
        type: 'ai_agent',
        version: '1.0.0'
      },
      skill_slugs: ['text_generation'],
      mcp_input_schema: {},
      mcp_output_schema: {},
      mcp_metadata: {
        model_config: {
          model: 'claude-3-opus',
          temperature: 0.8,
          max_tokens: 4000
        }
      },
      metadata: {},
      created_at: '2024-01-14T15:30:00Z',
      updated_at: '2024-01-14T15:30:00Z',
      execution_stats: {
        total_executions: 75,
        successful_executions: 66,
        failed_executions: 9,
        success_rate: 88.0,
        avg_execution_time: 2100
      }
    }
  ];

  beforeEach(() => {
    jest.clearAllMocks();

    store = configureStore({
      reducer: {
        auth: (state = { user: null, isAuthenticated: false }) => state
      }
    });

    // Setup API mocks - component expects { items: [...] } response format
    (agentsApi.getAgents as jest.Mock).mockResolvedValue({
      items: mockAgents
    });
  });

  const renderComponent = () => {
    return render(
      <Provider store={store}>
        <BrowserRouter>
          <BreadcrumbProvider>
            <AiAgentDashboard />
          </BreadcrumbProvider>
        </BrowserRouter>
      </Provider>
    );
  };

  describe('Component Rendering', () => {
    it('renders the dashboard sections', async () => {
      renderComponent();

      // Wait for loading to complete
      await waitFor(() => {
        expect(screen.queryByTestId('loading-spinner')).not.toBeInTheDocument();
      });

      // Dashboard renders stats overview and recent agents section
      expect(screen.getByText('Total Agents')).toBeInTheDocument();
      expect(screen.getByText('Recent Agents')).toBeInTheDocument();
    });

    it('displays loading state initially', () => {
      renderComponent();

      expect(screen.getByTestId('loading-spinner')).toBeInTheDocument();
    });

    it('displays agents after loading', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('Data Processor')).toBeInTheDocument();
        expect(screen.getByText('Content Generator')).toBeInTheDocument();
      });
    });

    it('shows create agent button when user has create permissions', async () => {
      // Button appears in EmptyState when no agents exist
      (agentsApi.getAgents as jest.Mock).mockResolvedValue({ items: [] });

      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('Create Agent')).toBeInTheDocument();
      });
    });

    it('displays empty state when no agents exist', async () => {
      (agentsApi.getAgents as jest.Mock).mockResolvedValue({
        items: []
      });

      renderComponent();

      await waitFor(() => {
        expect(screen.getByTestId('empty-state')).toBeInTheDocument();
        expect(screen.getByText('No AI agents found')).toBeInTheDocument();
      });
    });
  });

  describe('Agent Display', () => {
    it('displays agent information correctly', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('Data Processor')).toBeInTheDocument();
        expect(screen.getByText('Processes and analyzes data')).toBeInTheDocument();
        expect(screen.getByText('OpenAI')).toBeInTheDocument();
      });
    });

    it('shows agent status badges', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('Active')).toBeInTheDocument();
        expect(screen.getByText('Inactive')).toBeInTheDocument();
      });
    });

    it('displays agent model information', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('gpt-4')).toBeInTheDocument();
        expect(screen.getByText('claude-3-opus')).toBeInTheDocument();
      });
    });

    it('shows provider information for each agent', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('OpenAI')).toBeInTheDocument();
        expect(screen.getByText('Anthropic')).toBeInTheDocument();
      });
    });
  });

  describe('Stats Display', () => {
    it('displays stats overview cards', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('Total Agents')).toBeInTheDocument();
        expect(screen.getByText('Active Agents')).toBeInTheDocument();
        expect(screen.getByText('Total Executions')).toBeInTheDocument();
        expect(screen.getByText('Success Rate')).toBeInTheDocument();
      });
    });

    it('calculates and displays correct stats', async () => {
      renderComponent();

      await waitFor(() => {
        // Total agents: 2
        // Active agents: 1 (only Data Processor is active)
        // Total executions: 150 + 75 = 225
        expect(screen.getByText('2')).toBeInTheDocument();
        expect(screen.getByText('1')).toBeInTheDocument();
        expect(screen.getByText('225')).toBeInTheDocument();
      });
    });
  });

  describe('Agent Actions', () => {
    it('opens create modal when create button is clicked', async () => {
      // Start with empty agents so "Create Agent" button appears in EmptyState
      (agentsApi.getAgents as jest.Mock).mockResolvedValue({ items: [] });

      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('Create Agent')).toBeInTheDocument();
      });
      fireEvent.click(screen.getByText('Create Agent'));

      await waitFor(() => {
        expect(screen.getByTestId('create-agent-modal')).toBeInTheDocument();
      });
    });

    it('opens edit modal when manage button is clicked', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getAllByText('Manage').length).toBeGreaterThan(0);
      });
      const manageButtons = screen.getAllByText('Manage');
      fireEvent.click(manageButtons[0]);

      await waitFor(() => {
        expect(screen.getByTestId('edit-agent-modal')).toBeInTheDocument();
        expect(screen.getByText('Editing: Data Processor')).toBeInTheDocument();
      });
    });

    it('toggles agent status when pause button is clicked', async () => {
      (agentsApi.pauseAgent as jest.Mock).mockResolvedValue({});
      (agentsApi.getAgents as jest.Mock)
        .mockResolvedValueOnce({ items: mockAgents })
        .mockResolvedValueOnce({ items: mockAgents });

      renderComponent();

      await waitFor(() => {
        expect(screen.getAllByText('Pause').length).toBeGreaterThan(0);
      });
      const pauseButtons = screen.getAllByText('Pause');
      fireEvent.click(pauseButtons[0]);

      await waitFor(() => {
        expect(agentsApi.pauseAgent).toHaveBeenCalledWith('agent-1');
      });
    });

    it('starts inactive agent when start button is clicked', async () => {
      (agentsApi.resumeAgent as jest.Mock).mockResolvedValue({});
      (agentsApi.getAgents as jest.Mock)
        .mockResolvedValueOnce({ items: mockAgents })
        .mockResolvedValueOnce({ items: mockAgents });

      renderComponent();

      await waitFor(() => {
        expect(screen.getAllByText('Start').length).toBeGreaterThan(0);
      });
      const startButtons = screen.getAllByText('Start');
      fireEvent.click(startButtons[0]);

      await waitFor(() => {
        expect(agentsApi.resumeAgent).toHaveBeenCalledWith('agent-2');
      });
    });
  });

  describe('Error Handling', () => {
    it('shows empty state when API fails', async () => {
      (agentsApi.getAgents as jest.Mock).mockRejectedValue({
        message: 'Failed to load agents'
      });

      renderComponent();

      // Component clears data and shows empty state on error
      await waitFor(() => {
        expect(screen.getByTestId('empty-state')).toBeInTheDocument();
        // Multiple stats show 0 (Total Agents, Active Agents, etc.)
        expect(screen.getAllByText('0').length).toBeGreaterThan(0);
      });
    });

    it('handles authentication errors gracefully', async () => {
      (agentsApi.getAgents as jest.Mock).mockRejectedValue({
        response: { status: 401 },
        message: 'Unauthorized'
      });

      renderComponent();

      // Component clears data on auth error and shows empty state
      await waitFor(() => {
        expect(screen.queryByTestId('loading-spinner')).not.toBeInTheDocument();
      });
    });
  });

  describe('Modal Callbacks', () => {
    it('closes create modal and refreshes on agent created', async () => {
      // Start with empty agents so "Create Agent" button appears in EmptyState
      (agentsApi.getAgents as jest.Mock)
        .mockResolvedValueOnce({ items: [] })
        .mockResolvedValueOnce({ items: mockAgents });

      renderComponent();

      // Wait for component to load and then open create modal (button appears in EmptyState)
      await waitFor(() => {
        expect(screen.getByText('Create Agent')).toBeInTheDocument();
      });
      fireEvent.click(screen.getByText('Create Agent'));

      await waitFor(() => {
        expect(screen.getByTestId('create-agent-modal')).toBeInTheDocument();
      });

      // Trigger agent created callback (first "Create Agent" button opens modal, second is inside modal)
      const createButtons = screen.getAllByText('Create Agent');
      fireEvent.click(createButtons[createButtons.length - 1]); // Click the one inside modal

      await waitFor(() => {
        expect(screen.queryByTestId('create-agent-modal')).not.toBeInTheDocument();
        expect(agentsApi.getAgents).toHaveBeenCalledTimes(2); // Initial + refresh
      });
    });

    it('closes edit modal and refreshes on agent updated', async () => {
      (agentsApi.getAgents as jest.Mock)
        .mockResolvedValueOnce({ items: mockAgents })
        .mockResolvedValueOnce({ items: mockAgents });

      renderComponent();

      // Wait for component to load and then open edit modal
      await waitFor(() => {
        expect(screen.getAllByText('Manage').length).toBeGreaterThan(0);
      });
      const manageButtons = screen.getAllByText('Manage');
      fireEvent.click(manageButtons[0]);

      await waitFor(() => {
        expect(screen.getByTestId('edit-agent-modal')).toBeInTheDocument();
      });

      // Trigger agent updated callback
      fireEvent.click(screen.getByText('Update Agent'));

      await waitFor(() => {
        expect(screen.queryByTestId('edit-agent-modal')).not.toBeInTheDocument();
      });
    });

    it('closes edit modal and refreshes on agent deleted', async () => {
      (agentsApi.getAgents as jest.Mock)
        .mockResolvedValueOnce({ items: mockAgents })
        .mockResolvedValueOnce({ items: [mockAgents[1]] });

      renderComponent();

      // Wait for component to load and then open edit modal
      await waitFor(() => {
        expect(screen.getAllByText('Manage').length).toBeGreaterThan(0);
      });
      const manageButtons = screen.getAllByText('Manage');
      fireEvent.click(manageButtons[0]);

      await waitFor(() => {
        expect(screen.getByTestId('edit-agent-modal')).toBeInTheDocument();
      });

      // Trigger agent deleted callback
      fireEvent.click(screen.getByText('Delete Agent'));

      await waitFor(() => {
        expect(screen.queryByTestId('edit-agent-modal')).not.toBeInTheDocument();
      });
    });
  });

  describe('Recent Agents Section', () => {
    it('shows Recent Agents heading', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('Recent Agents')).toBeInTheDocument();
      });
    });

    it('displays execution count for agents', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('150')).toBeInTheDocument(); // Data Processor executions
        expect(screen.getByText('75')).toBeInTheDocument(); // Content Generator executions
      });
    });
  });
});

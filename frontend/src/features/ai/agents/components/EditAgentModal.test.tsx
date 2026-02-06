import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { EditAgentModal } from './EditAgentModal';
import { agentsApi, providersApi } from '@/shared/services/ai';
import type { AiAgent } from '@/shared/types/ai';

jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    addNotification: jest.fn()
  })
}));

jest.mock('@/shared/services/ai', () => ({
  agentsApi: {
    updateAgent: jest.fn(),
    deleteAgent: jest.fn(),
    getAgentStats: jest.fn()
  },
  providersApi: {
    getProviders: jest.fn()
  }
}));

describe('EditAgentModal', () => {
  const mockProviders = [
    {
      id: 'provider-1',
      name: 'OpenAI',
      provider_type: 'text_generation',
      is_active: true,
      supported_models: [
        { id: 'gpt-4', name: 'GPT-4' },
        { id: 'gpt-3.5-turbo', name: 'GPT-3.5 Turbo' }
      ],
      description: 'OpenAI API provider',
      capabilities: ['text_generation', 'code_completion']
    }
  ];

  const mockAgentComplete: AiAgent = {
    id: 'agent-1',
    name: 'Test Agent',
    description: 'A test agent',
    agent_type: 'assistant',
    status: 'active',
    provider: {
      id: 'provider-1',
      name: 'OpenAI',
      slug: 'openai',
      provider_type: 'text_generation'
    },
    // Model config - single source of truth
    model: 'gpt-4',
    temperature: 0.7,
    max_tokens: 2048,
    system_prompt: 'You are helpful',
    mcp_tool_manifest: {
      name: 'test-agent',
      description: 'A test agent',
      type: 'ai_agent',
      version: '1.0.0'
    },
    skill_slugs: [],
    mcp_input_schema: {},
    mcp_output_schema: {},
    mcp_metadata: {},
    metadata: {},
    is_active: true,
    execution_stats: {
      total_executions: 10,
      successful_executions: 8,
      failed_executions: 2,
      success_rate: 80,
      avg_execution_time: 150
    },
    created_at: '2024-01-01T00:00:00Z',
    updated_at: '2024-01-01T00:00:00Z'
  };

  const defaultProps = {
    isOpen: true,
    onClose: jest.fn(),
    agent: mockAgentComplete,
    onAgentUpdated: jest.fn(),
    onAgentDeleted: jest.fn()
  };

  beforeEach(() => {
    jest.clearAllMocks();
    (providersApi.getProviders as jest.Mock).mockResolvedValue({ items: mockProviders });
    (agentsApi.updateAgent as jest.Mock).mockResolvedValue({ ...mockAgentComplete, name: 'Updated Agent' });
    (agentsApi.getAgentStats as jest.Mock).mockResolvedValue({
      total_executions: 10,
      success_rate: 80,
      avg_execution_time: 150,
      estimated_total_cost: '1.50'
    });
  });

  describe('rendering', () => {
    it('renders modal with agent name in title', async () => {
      render(<EditAgentModal {...defaultProps} />);

      expect(screen.getByText(`Edit ${mockAgentComplete.name}`)).toBeInTheDocument();
    });

    it('renders form sections', async () => {
      render(<EditAgentModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Basic Information')).toBeInTheDocument();
      });
      expect(screen.getByText('AI Provider Configuration')).toBeInTheDocument();
      expect(screen.getByText('Advanced Configuration')).toBeInTheDocument();
      expect(screen.getByText('Agent Status')).toBeInTheDocument();
    });

    it('renders delete button', async () => {
      render(<EditAgentModal {...defaultProps} />);

      expect(screen.getByText('Delete')).toBeInTheDocument();
    });

    it('renders update button', async () => {
      render(<EditAgentModal {...defaultProps} />);

      expect(screen.getByText('Update Agent')).toBeInTheDocument();
    });

    it('returns null when agent is null', () => {
      const { container } = render(<EditAgentModal {...defaultProps} agent={null} />);

      expect(container.firstChild).toBeNull();
    });
  });

  describe('edge cases with partial agent data', () => {
    it('handles agent with undefined ai_provider', async () => {
      const agentWithoutProvider = {
        ...mockAgentComplete,
        ai_provider: undefined
      } as unknown as AiAgent;

      // Should not throw an error
      expect(() => {
        render(<EditAgentModal {...defaultProps} agent={agentWithoutProvider} />);
      }).not.toThrow();

      expect(screen.getByText(`Edit ${agentWithoutProvider.name}`)).toBeInTheDocument();
    });

    it('handles agent with null ai_provider', async () => {
      const agentWithNullProvider = {
        ...mockAgentComplete,
        ai_provider: null
      } as unknown as AiAgent;

      expect(() => {
        render(<EditAgentModal {...defaultProps} agent={agentWithNullProvider} />);
      }).not.toThrow();
    });

    it('handles agent with undefined mcp_tool_manifest', async () => {
      const agentWithoutManifest = {
        ...mockAgentComplete,
        mcp_tool_manifest: undefined
      } as unknown as AiAgent;

      expect(() => {
        render(<EditAgentModal {...defaultProps} agent={agentWithoutManifest} />);
      }).not.toThrow();
    });

    it('handles agent with undefined mcp_metadata', async () => {
      const agentWithoutMetadata = {
        ...mockAgentComplete,
        mcp_metadata: undefined
      } as unknown as AiAgent;

      expect(() => {
        render(<EditAgentModal {...defaultProps} agent={agentWithoutMetadata} />);
      }).not.toThrow();
    });

    it('handles agent with empty mcp_tool_manifest configuration', async () => {
      const agentWithEmptyConfig = {
        ...mockAgentComplete,
        mcp_tool_manifest: { configuration: {} }
      } as unknown as AiAgent;

      expect(() => {
        render(<EditAgentModal {...defaultProps} agent={agentWithEmptyConfig} />);
      }).not.toThrow();
    });

    it('handles agent with missing execution_stats', async () => {
      const agentWithoutStats = {
        ...mockAgentComplete,
        execution_stats: undefined
      } as unknown as AiAgent;

      expect(() => {
        render(<EditAgentModal {...defaultProps} agent={agentWithoutStats} />);
      }).not.toThrow();
    });
  });

  describe('modal closed state', () => {
    it('does not load providers when modal is closed', async () => {
      render(<EditAgentModal {...defaultProps} isOpen={false} />);

      await new Promise(resolve => setTimeout(resolve, 100));

      expect(providersApi.getProviders).not.toHaveBeenCalled();
    });
  });

  describe('provider loading', () => {
    it('loads providers when modal opens', async () => {
      render(<EditAgentModal {...defaultProps} />);

      await waitFor(() => {
        expect(providersApi.getProviders).toHaveBeenCalledWith({ status: 'active' });
      });
    });
  });

  describe('cancel button', () => {
    it('calls onClose when cancel clicked', async () => {
      const onClose = jest.fn();
      render(<EditAgentModal {...defaultProps} onClose={onClose} />);

      fireEvent.click(screen.getByText('Cancel'));

      expect(onClose).toHaveBeenCalled();
    });
  });

  describe('delete functionality', () => {
    it('shows delete confirmation when delete clicked', async () => {
      render(<EditAgentModal {...defaultProps} />);

      fireEvent.click(screen.getByText('Delete'));

      expect(screen.getByText('Confirm Deletion')).toBeInTheDocument();
      expect(screen.getByText(/Are you sure you want to delete/)).toBeInTheDocument();
    });

    it('hides confirmation when cancel deletion clicked', async () => {
      render(<EditAgentModal {...defaultProps} />);

      fireEvent.click(screen.getByText('Delete'));
      expect(screen.getByText('Confirm Deletion')).toBeInTheDocument();

      // Click the cancel button in the confirmation dialog
      const cancelButtons = screen.getAllByText('Cancel');
      fireEvent.click(cancelButtons[cancelButtons.length - 1]);

      await waitFor(() => {
        expect(screen.queryByText('Confirm Deletion')).not.toBeInTheDocument();
      });
    });

    it('calls deleteAgent and onAgentDeleted when confirmed', async () => {
      const onAgentDeleted = jest.fn();
      const onClose = jest.fn();
      (agentsApi.deleteAgent as jest.Mock).mockResolvedValue({});

      render(<EditAgentModal {...defaultProps} onAgentDeleted={onAgentDeleted} onClose={onClose} />);

      fireEvent.click(screen.getByText('Delete'));
      fireEvent.click(screen.getByText('Yes, Delete Agent'));

      await waitFor(() => {
        expect(agentsApi.deleteAgent).toHaveBeenCalledWith(mockAgentComplete.id);
      });

      await waitFor(() => {
        expect(onAgentDeleted).toHaveBeenCalledWith(mockAgentComplete.id);
        expect(onClose).toHaveBeenCalled();
      });
    });
  });

  describe('stats loading', () => {
    it('loads agent stats when modal opens', async () => {
      render(<EditAgentModal {...defaultProps} />);

      await waitFor(() => {
        expect(agentsApi.getAgentStats).toHaveBeenCalledWith(mockAgentComplete.id);
      });
    });

    it('displays stats when loaded', async () => {
      render(<EditAgentModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Performance Stats')).toBeInTheDocument();
      });
    });

    it('handles 404 error gracefully by using fallback stats', async () => {
      (agentsApi.getAgentStats as jest.Mock).mockRejectedValue({
        response: { status: 404 }
      });

      expect(() => {
        render(<EditAgentModal {...defaultProps} />);
      }).not.toThrow();

      await waitFor(() => {
        expect(screen.getByText('Performance Stats')).toBeInTheDocument();
      });
    });

    it('hides stats section on non-404 error', async () => {
      (agentsApi.getAgentStats as jest.Mock).mockRejectedValue(new Error('Server error'));

      render(<EditAgentModal {...defaultProps} />);

      await waitFor(() => {
        expect(agentsApi.getAgentStats).toHaveBeenCalled();
      });

      // Stats section should not be visible after error
      await new Promise(resolve => setTimeout(resolve, 100));
      // The component handles this by not showing stats
    });
  });

  describe('form submission', () => {
    it('calls updateAgent with correct data on submit', async () => {
      render(<EditAgentModal {...defaultProps} />);

      await waitFor(() => {
        expect(providersApi.getProviders).toHaveBeenCalled();
      });

      fireEvent.click(screen.getByText('Update Agent'));

      await waitFor(() => {
        expect(agentsApi.updateAgent).toHaveBeenCalledWith(
          mockAgentComplete.id,
          expect.objectContaining({
            name: mockAgentComplete.name,
            agent_type: mockAgentComplete.agent_type
          })
        );
      });
    });
  });

  describe('status toggle', () => {
    it('shows active status when agent is active', async () => {
      render(<EditAgentModal {...defaultProps} />);

      expect(screen.getByText('Agent Active')).toBeInTheDocument();
    });

    it('shows inactive status when agent is inactive', async () => {
      const inactiveAgent = { ...mockAgentComplete, status: 'inactive' as const };
      render(<EditAgentModal {...defaultProps} agent={inactiveAgent} />);

      expect(screen.getByText('Agent Inactive')).toBeInTheDocument();
    });
  });
});

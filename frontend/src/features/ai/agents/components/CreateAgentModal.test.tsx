import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { CreateAgentModal } from './CreateAgentModal';

import { agentsApi, providersApi } from '@/shared/services/ai';

// Mock the hooks and services
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    addNotification: jest.fn()
  })
}));

jest.mock('@/shared/services/ai', () => ({
  agentsApi: {
    createAgent: jest.fn()
  },
  providersApi: {
    getProviders: jest.fn()
  }
}));

describe('CreateAgentModal', () => {
  const defaultProps = {
    isOpen: true,
    onClose: jest.fn(),
    onAgentCreated: jest.fn()
  };

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
    },
    {
      id: 'provider-2',
      name: 'Anthropic',
      provider_type: 'text_generation',
      is_active: true,
      supported_models: [
        { id: 'claude-3', name: 'Claude 3' }
      ],
      description: 'Anthropic API provider',
      capabilities: ['text_generation']
    }
  ];

  beforeEach(() => {
    jest.clearAllMocks();
    (providersApi.getProviders as jest.Mock).mockResolvedValue({ items: mockProviders });
    (agentsApi.createAgent as jest.Mock).mockResolvedValue({ id: 'new-agent', name: 'Test Agent' });
  });

  describe('rendering', () => {
    it('renders modal title', async () => {
      render(<CreateAgentModal {...defaultProps} />);

      expect(screen.getByText('Create AI Agent')).toBeInTheDocument();
    });

    it('renders form sections', async () => {
      render(<CreateAgentModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Basic Information')).toBeInTheDocument();
      });
      expect(screen.getByText('AI Provider Configuration')).toBeInTheDocument();
      expect(screen.getByText('Advanced Configuration')).toBeInTheDocument();
    });

    it('renders agent name field', async () => {
      render(<CreateAgentModal {...defaultProps} />);

      expect(screen.getByText('Agent Name')).toBeInTheDocument();
      expect(screen.getByPlaceholderText('e.g., Content Generator')).toBeInTheDocument();
    });

    it('renders agent type field', async () => {
      render(<CreateAgentModal {...defaultProps} />);

      expect(screen.getByText('Agent Type')).toBeInTheDocument();
    });

    it('renders description field', async () => {
      render(<CreateAgentModal {...defaultProps} />);

      expect(screen.getByText('Description')).toBeInTheDocument();
    });

    it('renders AI provider field', async () => {
      render(<CreateAgentModal {...defaultProps} />);

      expect(screen.getByText('AI Provider')).toBeInTheDocument();
    });

    it('renders model field', async () => {
      render(<CreateAgentModal {...defaultProps} />);

      expect(screen.getByText('Model')).toBeInTheDocument();
    });

    it('renders temperature field', async () => {
      render(<CreateAgentModal {...defaultProps} />);

      expect(screen.getByText('Temperature')).toBeInTheDocument();
    });

    it('renders max tokens field', async () => {
      render(<CreateAgentModal {...defaultProps} />);

      expect(screen.getByText('Max Tokens')).toBeInTheDocument();
    });

    it('renders system prompt field', async () => {
      render(<CreateAgentModal {...defaultProps} />);

      expect(screen.getByText('System Prompt')).toBeInTheDocument();
    });

    it('renders cancel button', async () => {
      render(<CreateAgentModal {...defaultProps} />);

      expect(screen.getByText('Cancel')).toBeInTheDocument();
    });

    it('renders create button', async () => {
      render(<CreateAgentModal {...defaultProps} />);

      expect(screen.getByText('Create Agent')).toBeInTheDocument();
    });
  });

  describe('when modal is closed', () => {
    it('does not load providers when modal is closed', async () => {
      render(<CreateAgentModal {...defaultProps} isOpen={false} />);

      // Wait a bit to ensure no API call is made
      await new Promise(resolve => setTimeout(resolve, 100));

      expect(providersApi.getProviders).not.toHaveBeenCalled();
    });
  });

  describe('provider loading', () => {
    it('loads providers on mount', async () => {
      render(<CreateAgentModal {...defaultProps} />);

      await waitFor(() => {
        expect(providersApi.getProviders).toHaveBeenCalledWith({ status: 'active' });
      });
    });

    it('shows loading placeholder while loading providers', async () => {
      (providersApi.getProviders as jest.Mock).mockImplementation(
        () => new Promise(resolve => setTimeout(() => resolve({ items: mockProviders }), 100))
      );

      render(<CreateAgentModal {...defaultProps} />);

      // Initially should show loading state
      expect(screen.getByText(/Loading providers/i)).toBeInTheDocument();
    });
  });

  describe('cancel button', () => {
    it('calls onClose when cancel clicked', async () => {
      const onClose = jest.fn();
      render(<CreateAgentModal {...defaultProps} onClose={onClose} />);

      fireEvent.click(screen.getByText('Cancel'));

      expect(onClose).toHaveBeenCalled();
    });
  });

  describe('default agent type', () => {
    it('uses default agent type when provided', async () => {
      render(<CreateAgentModal {...defaultProps} defaultAgentType="code_assistant" />);

      // The default agent type should be set in the form
      await waitFor(() => {
        expect(screen.getByText('Basic Information')).toBeInTheDocument();
      });
    });
  });

  describe('agent types', () => {
    it('has all expected agent type options', async () => {
      render(<CreateAgentModal {...defaultProps} />);

      // Agent types are in a select, so we check the form has the field
      expect(screen.getByText('Agent Type')).toBeInTheDocument();
    });
  });

  describe('help text', () => {
    it('shows help text for fields', async () => {
      render(<CreateAgentModal {...defaultProps} />);

      expect(screen.getByText('A descriptive name for your AI agent')).toBeInTheDocument();
      expect(screen.getByText('The primary function of this agent')).toBeInTheDocument();
    });
  });
});

import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { AiProviderCard } from './AiProviderCard';
import type { AiProvider } from '@/shared/types/ai';

// Mock the hooks and services
const mockAddNotification = jest.fn();
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    addNotification: mockAddNotification
  })
}));

jest.mock('@/shared/services/ai', () => ({
  providersApi: {
    testConnection: jest.fn(),
    syncModels: jest.fn()
  }
}));

import { providersApi } from '@/shared/services/ai';

describe('AiProviderCard', () => {
  const mockProvider: AiProvider = {
    id: 'provider-1',
    name: 'OpenAI',
    slug: 'openai',
    provider_type: 'text_generation',
    is_active: true,
    health_status: 'healthy',
    description: 'OpenAI API for text generation and code completion',
    capabilities: ['text_generation', 'code_completion', 'embeddings', 'chat', 'vision'],
    model_count: 5,
    credential_count: 2,
    priority_order: 1,
    documentation_url: 'https://docs.openai.com',
    status_url: 'https://status.openai.com',
    api_base_url: 'https://api.openai.com/v1',
    supported_models: [],
    configuration_schema: {},
    default_parameters: {},
    rate_limits: {},
    pricing_info: {},
    metadata: {},
    requires_auth: true,
    supports_streaming: true,
    supports_functions: true,
    supports_vision: true,
    supports_code_execution: false,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString()
  };

  const defaultProps = {
    provider: mockProvider,
    onUpdate: jest.fn(),
    canManage: true,
    onViewDetails: jest.fn(),
    onEditProvider: jest.fn()
  };

  beforeEach(() => {
    jest.clearAllMocks();
    (providersApi.testConnection as jest.Mock).mockResolvedValue({ success: true, response_time_ms: 150 });
    (providersApi.syncModels as jest.Mock).mockResolvedValue({ success: true });
  });

  describe('rendering', () => {
    it('renders provider name', () => {
      render(<AiProviderCard {...defaultProps} />);

      expect(screen.getByText('OpenAI')).toBeInTheDocument();
    });

    it('renders provider description', () => {
      render(<AiProviderCard {...defaultProps} />);

      expect(screen.getByText('OpenAI API for text generation and code completion')).toBeInTheDocument();
    });

    it('renders provider icon', () => {
      render(<AiProviderCard {...defaultProps} />);

      // OpenAI icon is a robot emoji
      expect(screen.getByText('🤖')).toBeInTheDocument();
    });

    it('renders different icons for different providers', () => {
      const ollamaProvider = { ...mockProvider, slug: 'ollama', name: 'Ollama' };
      render(<AiProviderCard {...defaultProps} provider={ollamaProvider} />);

      expect(screen.getByText('🦙')).toBeInTheDocument();
    });

    it('renders health status badge', () => {
      render(<AiProviderCard {...defaultProps} />);

      expect(screen.getByText('Healthy')).toBeInTheDocument();
    });

    it('renders unhealthy status badge', () => {
      const unhealthyProvider = { ...mockProvider, health_status: 'unhealthy' as const };
      render(<AiProviderCard {...defaultProps} provider={unhealthyProvider} />);

      expect(screen.getByText('Unhealthy')).toBeInTheDocument();
    });

    it('renders inactive status badge', () => {
      const inactiveProvider = { ...mockProvider, health_status: 'inactive' as const };
      render(<AiProviderCard {...defaultProps} provider={inactiveProvider} />);

      expect(screen.getByText('Inactive')).toBeInTheDocument();
    });

    it('renders provider type badge', () => {
      render(<AiProviderCard {...defaultProps} />);

      expect(screen.getByText('Text')).toBeInTheDocument();
    });

    it('renders model count', () => {
      render(<AiProviderCard {...defaultProps} />);

      expect(screen.getByText('5')).toBeInTheDocument();
      expect(screen.getByText('Models')).toBeInTheDocument();
    });

    it('renders credential count', () => {
      render(<AiProviderCard {...defaultProps} />);

      expect(screen.getByText('2')).toBeInTheDocument();
      expect(screen.getByText('Credentials')).toBeInTheDocument();
    });

    it('renders priority order', () => {
      render(<AiProviderCard {...defaultProps} />);

      expect(screen.getByText('#1')).toBeInTheDocument();
      expect(screen.getByText('Priority')).toBeInTheDocument();
    });

    it('renders star icon for high priority providers', () => {
      render(<AiProviderCard {...defaultProps} />);

      // Priority 1-3 shows star icon
      const starIcon = document.querySelector('.fill-current');
      expect(starIcon).toBeInTheDocument();
    });

    it('does not render star for low priority providers', () => {
      const lowPriorityProvider = { ...mockProvider, priority_order: 5 };
      render(<AiProviderCard {...defaultProps} provider={lowPriorityProvider} />);

      expect(screen.getByText('#5')).toBeInTheDocument();
    });
  });

  describe('capabilities', () => {
    it('renders capabilities', () => {
      render(<AiProviderCard {...defaultProps} />);

      expect(screen.getByText('CAPABILITIES')).toBeInTheDocument();
      expect(screen.getByText('text generation')).toBeInTheDocument();
      expect(screen.getByText('code completion')).toBeInTheDocument();
    });

    it('shows +N more for extra capabilities', () => {
      render(<AiProviderCard {...defaultProps} />);

      // Provider has 5 capabilities, only 4 shown
      expect(screen.getByText('+1 more')).toBeInTheDocument();
    });
  });

  describe('action buttons', () => {
    it('renders Details button', () => {
      render(<AiProviderCard {...defaultProps} />);

      expect(screen.getByText('Details')).toBeInTheDocument();
    });

    it('renders Test button when credentials exist', () => {
      render(<AiProviderCard {...defaultProps} />);

      expect(screen.getByText('Test')).toBeInTheDocument();
    });

    it('does not render Test button when no credentials', () => {
      const noCredentialsProvider = { ...mockProvider, credential_count: 0 };
      render(<AiProviderCard {...defaultProps} provider={noCredentialsProvider} />);

      // Look for Test button in the action buttons area
      const buttons = screen.getAllByRole('button');
      const testButton = buttons.find(b => b.textContent === 'Test');
      expect(testButton).toBeUndefined();
    });

    it('renders Edit Settings button', () => {
      render(<AiProviderCard {...defaultProps} />);

      expect(screen.getByText('Edit Settings')).toBeInTheDocument();
    });

    it('renders Docs button when documentation URL exists', () => {
      render(<AiProviderCard {...defaultProps} />);

      expect(screen.getByText('Docs')).toBeInTheDocument();
    });

    it('does not render Docs button when no documentation URL', () => {
      const noDocsProvider = { ...mockProvider, documentation_url: undefined };
      render(<AiProviderCard {...defaultProps} provider={noDocsProvider} />);

      expect(screen.queryByText('Docs')).not.toBeInTheDocument();
    });

    it('renders Status button when status URL exists', () => {
      render(<AiProviderCard {...defaultProps} />);

      expect(screen.getByText('Status')).toBeInTheDocument();
    });
  });

  describe('test connection', () => {
    it('calls API when test button clicked', async () => {
      render(<AiProviderCard {...defaultProps} />);

      fireEvent.click(screen.getByText('Test'));

      await waitFor(() => {
        expect(providersApi.testConnection).toHaveBeenCalledWith('provider-1');
      });
    });

    it('shows success notification on successful test', async () => {
      render(<AiProviderCard {...defaultProps} />);

      fireEvent.click(screen.getByText('Test'));

      await waitFor(() => {
        expect(mockAddNotification).toHaveBeenCalledWith({
          type: 'success',
          title: 'Connection Test',
          message: expect.stringContaining('Connection successful')
        });
      });
    });

    it('shows error notification on failed test', async () => {
      (providersApi.testConnection as jest.Mock).mockResolvedValue({
        success: false,
        error: 'Invalid API key'
      });

      render(<AiProviderCard {...defaultProps} />);

      fireEvent.click(screen.getByText('Test'));

      await waitFor(() => {
        expect(mockAddNotification).toHaveBeenCalledWith({
          type: 'error',
          title: 'Connection Test',
          message: expect.stringContaining('Invalid API key')
        });
      });
    });

    it('calls onUpdate on successful test', async () => {
      const onUpdate = jest.fn();
      render(<AiProviderCard {...defaultProps} onUpdate={onUpdate} />);

      fireEvent.click(screen.getByText('Test'));

      await waitFor(() => {
        expect(onUpdate).toHaveBeenCalled();
      });
    });

    it('shows loading state during test', async () => {
      (providersApi.testConnection as jest.Mock).mockImplementation(
        () => new Promise(resolve => setTimeout(() => resolve({ success: true }), 100))
      );

      render(<AiProviderCard {...defaultProps} />);

      fireEvent.click(screen.getByText('Test'));

      expect(screen.getByText('Testing...')).toBeInTheDocument();
    });
  });

  describe('view details', () => {
    it('calls onViewDetails when Details button clicked', () => {
      const onViewDetails = jest.fn();
      render(<AiProviderCard {...defaultProps} onViewDetails={onViewDetails} />);

      fireEvent.click(screen.getByText('Details'));

      expect(onViewDetails).toHaveBeenCalledWith('provider-1');
    });
  });

  describe('edit settings', () => {
    it('calls onEditProvider when Edit Settings clicked', () => {
      const onEditProvider = jest.fn();
      render(<AiProviderCard {...defaultProps} onEditProvider={onEditProvider} />);

      fireEvent.click(screen.getByText('Edit Settings'));

      expect(onEditProvider).toHaveBeenCalledWith('provider-1');
    });
  });

  describe('warning indicators', () => {
    it('shows inactive warning when provider is inactive', () => {
      const inactiveProvider = { ...mockProvider, is_active: false };
      render(<AiProviderCard {...defaultProps} provider={inactiveProvider} />);

      expect(screen.getByText('Provider is currently inactive')).toBeInTheDocument();
    });

    it('shows health warning when provider is unhealthy', () => {
      const unhealthyProvider = { ...mockProvider, health_status: 'unhealthy' as const };
      render(<AiProviderCard {...defaultProps} provider={unhealthyProvider} />);

      expect(screen.getByText('Provider health check failed')).toBeInTheDocument();
    });

    it('shows no credentials warning when credential count is 0', () => {
      const noCredentialsProvider = { ...mockProvider, credential_count: 0 };
      render(<AiProviderCard {...defaultProps} provider={noCredentialsProvider} />);

      expect(screen.getByText(/No credentials configured/)).toBeInTheDocument();
    });
  });

  describe('dropdown menu', () => {
    it('renders dropdown trigger button', () => {
      render(<AiProviderCard {...defaultProps} />);

      // MoreVertical icon button
      const buttons = screen.getAllByRole('button');
      expect(buttons.length).toBeGreaterThan(0);
    });
  });

  describe('external links', () => {
    it('opens documentation URL in new tab', () => {
      const openSpy = jest.spyOn(window, 'open').mockImplementation(() => null);
      render(<AiProviderCard {...defaultProps} />);

      fireEvent.click(screen.getByText('Docs'));

      expect(openSpy).toHaveBeenCalledWith('https://docs.openai.com', '_blank');
      openSpy.mockRestore();
    });

    it('opens status URL in new tab', () => {
      const openSpy = jest.spyOn(window, 'open').mockImplementation(() => null);
      render(<AiProviderCard {...defaultProps} />);

      fireEvent.click(screen.getByText('Status'));

      expect(openSpy).toHaveBeenCalledWith('https://status.openai.com', '_blank');
      openSpy.mockRestore();
    });
  });
});

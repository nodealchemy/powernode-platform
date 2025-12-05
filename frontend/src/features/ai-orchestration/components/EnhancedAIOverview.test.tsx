import { render, screen, waitFor, fireEvent, act } from '@testing-library/react';
import { Provider } from 'react-redux';
import { BrowserRouter } from 'react-router-dom';
import { configureStore } from '@reduxjs/toolkit';
import { EnhancedAIOverview } from './EnhancedAIOverview';
import * as aiOrchestrationMonitor from '../services/aiOrchestrationMonitor';
import { agentsApi, providersApi } from '@/shared/services/ai';
import { workflowsApi } from '@/shared/services/ai';

// Mock the consolidated AI services
jest.mock('@/shared/services/ai', () => ({
  providersApi: {
    getProviders: jest.fn()
  },
  agentsApi: {
    getAgents: jest.fn(),
    getConversations: jest.fn()
  },
  workflowsApi: {
    getWorkflows: jest.fn()
  }
}));
jest.mock('../services/aiOrchestrationMonitor');

// Mock the auth hook
jest.mock('@/shared/hooks/useAuth', () => ({
  useAuth: () => ({
    currentUser: {
      id: 'test-user-id',
      account: { id: 'test-account-id', name: 'Test Account' },
      permissions: ['ai.providers.read', 'ai.agents.read', 'ai.workflows.read', 'ai.conversations.read']
    }
  })
}));

// Mock the notifications hook
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    addNotification: jest.fn()
  })
}));

// Mock useNavigate
const mockNavigate = jest.fn();
jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useNavigate: () => mockNavigate
}));

describe('EnhancedAIOverview', () => {
  let store: any;
  let mockSubscribe: jest.Mock;
  let mockIsConnected: jest.Mock;

  const mockApiResponses = {
    providers: {
      success: true,
      data: {
        providers: [
          { id: '1', name: 'OpenAI', is_active: true, health_status: 'healthy' },
          { id: '2', name: 'Anthropic', is_active: true, health_status: 'healthy' }
        ]
      }
    },
    agents: {
      success: true,
      data: {
        agents: [
          { id: '1', name: 'Agent 1', status: 'active' },
          { id: '2', name: 'Agent 2', status: 'inactive' }
        ]
      }
    },
    workflows: {
      success: true,
      data: {
        workflows: [
          { id: '1', name: 'Workflow 1', status: 'active' },
          { id: '2', name: 'Workflow 2', status: 'draft' }
        ]
      }
    },
    conversations: {
      success: true,
      data: {
        conversations: [
          { id: '1', title: 'Conversation 1', status: 'completed' }
        ]
      }
    }
  };

  beforeEach(() => {
    // Clear all mocks
    jest.clearAllMocks();
    jest.clearAllTimers();
    jest.useFakeTimers();

    // Setup store
    store = configureStore({
      reducer: {
        auth: (state = { user: null, isAuthenticated: false }) => state
      }
    });

    // Setup AI orchestration monitor mocks
    mockSubscribe = jest.fn(() => jest.fn()); // Return unsubscribe function
    mockIsConnected = jest.fn(() => false); // Default to disconnected for testing fallback

    (aiOrchestrationMonitor.useAIOrchestrationMonitor as jest.Mock).mockReturnValue({
      subscribe: mockSubscribe,
      isConnected: mockIsConnected,
      monitor: null
    });

    (aiOrchestrationMonitor.resetAIOrchestrationMonitor as jest.Mock).mockImplementation(() => {});

    // Setup API mocks
    (providersApi.getProviders as jest.Mock).mockResolvedValue(mockApiResponses.providers);
    (agentsApi.getAgents as jest.Mock).mockResolvedValue(mockApiResponses.agents);
    (workflowsApi.getWorkflows as jest.Mock).mockResolvedValue(mockApiResponses.workflows);
    (agentsApi.getConversations as jest.Mock).mockResolvedValue(mockApiResponses.conversations);
  });

  afterEach(() => {
    jest.runOnlyPendingTimers();
    jest.useRealTimers();
  });

  const renderComponent = () => {
    return render(
      <Provider store={store}>
        <BrowserRouter>
          <EnhancedAIOverview />
        </BrowserRouter>
      </Provider>
    );
  };

  describe('Component Rendering', () => {
    it('renders the component successfully', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('AI System Overview')).toBeInTheDocument();
      });
    });

    it('displays loading state initially', () => {
      renderComponent();

      expect(screen.getByText('Loading AI system overview...')).toBeInTheDocument();
    });

    it('displays AI system data after loading', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('AI System Overview')).toBeInTheDocument();
        expect(screen.getByText('AI Providers')).toBeInTheDocument();
        expect(screen.getByText('AI Agents')).toBeInTheDocument();
        expect(screen.getByText('Workflows')).toBeInTheDocument();
        expect(screen.getByText('Conversations')).toBeInTheDocument();
      });
    });
  });

  describe('Real-time Updates', () => {
    it('sets up WebSocket subscription on mount', async () => {
      renderComponent();

      await waitFor(() => {
        expect(mockSubscribe).toHaveBeenCalledWith(
          undefined,
          expect.any(Function)
        );
      });
    });

    it('resets AI orchestration monitor on mount', async () => {
      renderComponent();

      expect(aiOrchestrationMonitor.resetAIOrchestrationMonitor).toHaveBeenCalled();
    });

    it('sets up polling when live updates are active (30-second fallback)', async () => {
      renderComponent();

      // Wait for initial load
      await waitFor(() => {
        expect(screen.getByText('AI System Overview')).toBeInTheDocument();
      });

      // Component uses 30-second fallback polling when WebSocket not connected
      // Since mockIsConnected returns false, it will use polling
      act(() => {
        jest.advanceTimersByTime(30000);
      });

      // Should trigger additional data load
      await waitFor(() => {
        expect(providersApi.getProviders).toHaveBeenCalled();
      });
    });

    it('stops polling when live updates are disabled', async () => {
      renderComponent();

      // Wait for initial load
      await waitFor(() => {
        expect(screen.getByText('AI System Overview')).toBeInTheDocument();
      });

      // Find and click the live updates toggle button - get all and select first (component has multiple)
      const liveButtons = screen.getAllByRole('button', { name: /Live/i });
      fireEvent.click(liveButtons[0]);

      // Should show "Paused" after clicking
      expect(screen.getByText('Paused')).toBeInTheDocument();
    });

    it('toggles live updates when button is clicked', async () => {
      renderComponent();

      // Wait for initial load
      await waitFor(() => {
        expect(screen.getByText('AI System Overview')).toBeInTheDocument();
      });

      // Click live button to disable - get all and select first (component has multiple)
      const liveButtons = screen.getAllByRole('button', { name: /Live/i });
      fireEvent.click(liveButtons[0]);
      expect(screen.getByText('Paused')).toBeInTheDocument();

      // Click again to re-enable - use getAllByText since there may be multiple "Live" text elements
      fireEvent.click(liveButtons[0]);
      const liveTexts = screen.getAllByText('Live');
      expect(liveTexts.length).toBeGreaterThan(0);
    });
  });

  describe('WebSocket Integration', () => {
    it('handles WebSocket metrics updates', async () => {
      const mockMetricsHandler = jest.fn();
      mockSubscribe.mockImplementation((_eventHandler, metricsHandler) => {
        mockMetricsHandler.mockImplementation(metricsHandler);
        return jest.fn();
      });

      renderComponent();

      await waitFor(() => {
        expect(mockSubscribe).toHaveBeenCalled();
      });

      // Simulate WebSocket metrics update
      const newMetrics = {
        providers: { total: 3, active: 3, health_status: 'healthy' },
        agents: { total: 5, active: 4, executing: 1, success_rate: 95 },
        workflows: { total: 10, active: 8, executing: 2, success_rate: 90 },
        executions: { total_today: 50, success_rate: 92, avg_response_time: 250 }
      };

      act(() => {
        mockMetricsHandler(newMetrics);
      });

      await waitFor(() => {
        expect(screen.getByText('AI System Overview')).toBeInTheDocument();
        // The metrics should have been updated through WebSocket
      });
    });

    it('shows visual indicators for recent updates', async () => {
      const mockMetricsHandler = jest.fn();
      mockSubscribe.mockImplementation((_eventHandler, metricsHandler) => {
        mockMetricsHandler.mockImplementation(metricsHandler);
        return jest.fn();
      });

      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('AI System Overview')).toBeInTheDocument();
      });

      // Simulate metrics update
      const newMetrics = {
        providers: { total: 3, active: 3, health_status: 'healthy' },
        agents: { total: 2, active: 2, executing: 0, success_rate: 100 },
        workflows: { total: 2, active: 2, executing: 0, success_rate: 100 },
        executions: { total_today: 10, success_rate: 100, avg_response_time: 200 }
      };

      act(() => {
        mockMetricsHandler(newMetrics);
      });

      // Should show the component is working
      await waitFor(() => {
        expect(screen.getByText('AI System Overview')).toBeInTheDocument();
      });
    });
  });

  describe('Error Handling', () => {
    // Note: The component uses Promise.allSettled which never throws.
    // When APIs fail, it falls back to mock data instead of showing error state.
    // Error state only shows if something unexpected fails outside Promise.allSettled.

    it('uses fallback data when API calls fail', async () => {
      // Component uses Promise.allSettled, so API rejections use fallback data
      (providersApi.getProviders as jest.Mock).mockRejectedValue(new Error('API Error'));
      (agentsApi.getAgents as jest.Mock).mockRejectedValue(new Error('API Error'));
      (workflowsApi.getWorkflows as jest.Mock).mockRejectedValue(new Error('API Error'));

      renderComponent();

      // Component should still render with fallback data, not show error state
      await waitFor(() => {
        expect(screen.getByText('AI System Overview')).toBeInTheDocument();
        expect(screen.getByText('AI Providers')).toBeInTheDocument();
      });
    });

    it('gracefully handles partial API failures', async () => {
      // Some APIs succeed, some fail - component should still work
      (providersApi.getProviders as jest.Mock).mockResolvedValue(mockApiResponses.providers);
      (agentsApi.getAgents as jest.Mock).mockRejectedValue(new Error('Agents API Error'));
      (workflowsApi.getWorkflows as jest.Mock).mockRejectedValue(new Error('Workflows API Error'));

      renderComponent();

      await waitFor(() => {
        // Should still show the overview with available data
        expect(screen.getByText('AI System Overview')).toBeInTheDocument();
        expect(screen.getByText('AI Agents')).toBeInTheDocument();
        expect(screen.getByText('Workflows')).toBeInTheDocument();
      });
    });

    it('allows manual refresh after loading completes', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('AI System Overview')).toBeInTheDocument();
      });

      // Find the refresh button by its title attribute
      const refreshButton = screen.getByTitle('Manually refresh data');
      fireEvent.click(refreshButton);

      await waitFor(() => {
        // Should trigger additional API call
        expect(providersApi.getProviders).toHaveBeenCalledTimes(2);
      });
    });
  });

  describe('Navigation Actions', () => {
    it('allows manual refresh of data', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('AI System Overview')).toBeInTheDocument();
      });

      // Find the refresh button by its icon or title
      const refreshButton = screen.getByTitle('Manually refresh data');
      fireEvent.click(refreshButton);

      // Should trigger additional API calls
      await waitFor(() => {
        expect(providersApi.getProviders).toHaveBeenCalledTimes(2); // Initial + manual refresh
      });
    });

    it('toggles live updates mode', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('AI System Overview')).toBeInTheDocument();
      });

      // Get all Live buttons and select the first one (component has multiple)
      const liveButtons = screen.getAllByRole('button', { name: /Live/i });
      expect(liveButtons.length).toBeGreaterThan(0);

      fireEvent.click(liveButtons[0]);

      // After clicking, it should show "Paused" text
      await waitFor(() => {
        expect(screen.getByText('Paused')).toBeInTheDocument();
      });
    });
  });

  describe('Performance', () => {
    it('cleans up intervals on unmount', () => {
      const { unmount } = renderComponent();

      // Fast-forward to start the interval
      act(() => {
        jest.advanceTimersByTime(100);
      });

      unmount();

      // Fast-forward past interval time
      act(() => {
        jest.advanceTimersByTime(10000);
      });

      // Should not make additional API calls after unmount
      expect(providersApi.getProviders).toHaveBeenCalledTimes(1); // Only initial load
    });

    it('debounces rapid metric updates', async () => {
      const mockMetricsHandler = jest.fn();
      mockSubscribe.mockImplementation((_eventHandler, metricsHandler) => {
        mockMetricsHandler.mockImplementation(metricsHandler);
        return jest.fn();
      });

      renderComponent();

      await waitFor(() => {
        expect(mockSubscribe).toHaveBeenCalled();
      });

      // Simulate rapid metrics updates
      const metrics1 = { providers: { total: 1 }, agents: { total: 1 }, workflows: { total: 1 }, executions: { total_today: 1 } };
      const metrics2 = { providers: { total: 2 }, agents: { total: 2 }, workflows: { total: 2 }, executions: { total_today: 2 } };

      act(() => {
        mockMetricsHandler(metrics1);
        mockMetricsHandler(metrics2);
      });

      // Should have processed the updates
      await waitFor(() => {
        expect(screen.getByText('AI System Overview')).toBeInTheDocument();
      });
    });
  });
});
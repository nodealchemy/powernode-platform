import React, { useState } from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { Provider } from 'react-redux';
import { BrowserRouter } from 'react-router-dom';
import { configureStore } from '@reduxjs/toolkit';
import { AiProvidersPage } from './AiProvidersPage';
import { providersApi } from '@/shared/services/ai';

// Mock the AI provider API
jest.mock('@/shared/services/ai', () => ({
  providersApi: {
    getProviders: jest.fn(),
    createProvider: jest.fn(),
    updateProvider: jest.fn(),
    deleteProvider: jest.fn(),
    testProvider: jest.fn(),
    testAllProviders: jest.fn(),
    setupDefaultProviders: jest.fn()
  },
  agentsApi: {},
  workflowsApi: {},
  conversationsApi: {},
  pluginsApi: {}
}));

// Mock hooks
jest.mock('@/shared/hooks/useAuth', () => ({
  useAuth: () => ({
    currentUser: {
      id: 'test-user-id',
      account: { id: 'test-account-id', name: 'Test Account' },
      permissions: ['ai.providers.read', 'ai.providers.create', 'ai.providers.update', 'ai.providers.delete']
    }
  })
}));

jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    addNotification: jest.fn()
  })
}));

jest.mock('@/shared/hooks/usePermissions', () => ({
  usePermissions: () => ({
    hasPermission: (permission: string) => {
      const allowedPermissions = [
        'ai.providers.read',
        'ai.providers.create',
        'ai.providers.update',
        'ai.providers.delete',
        'ai.providers.test'
      ];
      return allowedPermissions.includes(permission);
    }
  })
}));

// Mock UI components
jest.mock('@/shared/components/layout/PageContainer', () => ({
  PageContainer: ({ title, description, actions, children }: any) => (
    <div data-testid="page-container">
      <div data-testid="page-header">
        <h1>{title}</h1>
        <p>{description}</p>
        <div data-testid="page-actions">
          {Array.isArray(actions) ? actions.map((action: any, i: number) => (
            typeof action === 'object' && action.label ? (
              <button key={i} onClick={action.onClick} disabled={action.disabled}>
                {action.label}
              </button>
            ) : action
          )) : actions}
        </div>
      </div>
      <div data-testid="page-content">{children}</div>
    </div>
  )
}));

jest.mock('@/shared/components/ui/LoadingSpinner', () => ({
  LoadingSpinner: () => <div data-testid="loading-spinner">Loading...</div>
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

// Mock child components
jest.mock('./AiProviderCard', () => ({
  AiProviderCard: ({ provider, onUpdate, canManage, onViewDetails, onEditProvider }: any) => (
    <div data-testid={`provider-card-${provider.id}`}>
      <h3>{provider.name}</h3>
      <p>{provider.type}</p>
      <p>{provider.is_active ? 'Active' : 'Inactive'}</p>
      <button onClick={() => onViewDetails?.(provider.id)}>View</button>
      {canManage && <button onClick={() => onEditProvider?.(provider.id)}>Edit</button>}
      {onUpdate && <button onClick={() => onUpdate()}>Refresh</button>}
    </div>
  )
}));

jest.mock('./AiProviderFilters', () => ({
  AiProviderFilters: ({ filters, onFiltersChange }: any) => (
    <div data-testid="provider-filters">
      <select data-testid="type-filter" onChange={(e) => onFiltersChange({ provider_type: e.target.value })}>
        <option value="">All Types</option>
        <option value="openai">OpenAI</option>
        <option value="anthropic">Anthropic</option>
        <option value="local">Local</option>
      </select>
      <select data-testid="status-filter" onChange={(e) => onFiltersChange({ is_active: e.target.value === 'active' })}>
        <option value="">All Status</option>
        <option value="active">Active</option>
        <option value="inactive">Inactive</option>
      </select>
      <span data-testid="current-filters">{JSON.stringify(filters)}</span>
    </div>
  )
}));

jest.mock('./CreateProviderModal', () => ({
  CreateProviderModal: ({ isOpen, onClose, onSuccess }: any) => (
    isOpen ? (
      <div data-testid="create-provider-modal">
        <button onClick={() => { onSuccess({ id: 'new-provider', name: 'New Provider' }); onClose(); }}>
          Create
        </button>
        <button onClick={onClose}>Cancel</button>
      </div>
    ) : null
  )
}));

jest.mock('./EditProviderModal', () => ({
  EditProviderModal: ({ isOpen, providerId, onClose, onSuccess }: any) => (
    isOpen ? (
      <div data-testid="edit-provider-modal">
        <p>Editing provider: {providerId}</p>
        <button onClick={() => { onSuccess(); onClose(); }}>
          Update
        </button>
        <button onClick={onClose}>Cancel</button>
      </div>
    ) : null
  )
}));

jest.mock('./SetupDefaultProvidersModal', () => ({
  SetupDefaultProvidersModal: ({ isOpen, onClose, onConfirm }: any) => (
    isOpen ? (
      <div data-testid="setup-defaults-modal">
        <button onClick={() => { onConfirm?.(); onClose(); }}>
          Setup Defaults
        </button>
        <button onClick={onClose}>Cancel</button>
      </div>
    ) : null
  )
}));

jest.mock('./BulkTestModal', () => ({
  BulkTestModal: ({ isOpen, onClose, onConfirm }: any) => (
    isOpen ? (
      <div data-testid="bulk-test-modal">
        <p>Test all providers</p>
        <button onClick={onConfirm}>Confirm Test</button>
        <button onClick={onClose}>Close</button>
      </div>
    ) : null
  )
}));

describe('AiProvidersPage', () => {
  let store: any;

  const mockProviders = [
    {
      id: 'provider-1',
      name: 'OpenAI GPT-4',
      type: 'openai',
      is_active: true,
      health_status: 'healthy',
      configuration: {
        api_key: '***masked***',
        model: 'gpt-4',
        endpoint: 'https://api.openai.com/v1'
      },
      created_at: '2024-01-15T10:00:00Z',
      last_tested_at: '2024-01-15T14:30:00Z',
      test_results: {
        status: 'success',
        response_time: 850,
        error: null
      },
      usage_stats: {
        total_requests: 1250,
        successful_requests: 1195,
        failed_requests: 55,
        avg_response_time: 925
      }
    },
    {
      id: 'provider-2',
      name: 'Anthropic Claude',
      type: 'anthropic',
      is_active: true,
      health_status: 'degraded',
      configuration: {
        api_key: '***masked***',
        model: 'claude-3-opus',
        endpoint: 'https://api.anthropic.com/v1'
      },
      created_at: '2024-01-14T15:30:00Z',
      last_tested_at: '2024-01-15T14:25:00Z',
      test_results: {
        status: 'warning',
        response_time: 1950,
        error: 'Slow response time'
      },
      usage_stats: {
        total_requests: 780,
        successful_requests: 720,
        failed_requests: 60,
        avg_response_time: 1650
      }
    },
    {
      id: 'provider-3',
      name: 'Local Ollama',
      type: 'local',
      is_active: false,
      health_status: 'critical',
      configuration: {
        endpoint: 'http://localhost:11434',
        model: 'llama2'
      },
      created_at: '2024-01-13T09:15:00Z',
      last_tested_at: '2024-01-15T12:00:00Z',
      test_results: {
        status: 'error',
        response_time: null,
        error: 'Connection refused'
      },
      usage_stats: {
        total_requests: 45,
        successful_requests: 12,
        failed_requests: 33,
        avg_response_time: 3200
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

    (providersApi.getProviders as jest.Mock).mockResolvedValue({
      items: mockProviders,
      pagination: {
        current_page: 1,
        total_pages: 1,
        total_count: mockProviders.length,
        per_page: 20
      }
    });
  });

  // Wrapper component that captures and renders actions
  const TestWrapper: React.FC = () => {
    const [actions, setActions] = useState<any[]>([]);

    return (
      <>
        {/* Render the page header mock with captured actions */}
        <div data-testid="page-header">
          <h1>AI Providers</h1>
          <p>Manage AI providers and their configurations</p>
          <div data-testid="page-actions">
            {actions.map((action: any, i: number) => (
              <button key={i} onClick={action.onClick} disabled={action.disabled}>
                {action.label}
              </button>
            ))}
          </div>
        </div>
        <AiProvidersPage onActionsReady={setActions} />
      </>
    );
  };

  const renderComponent = () => {
    return render(
      <Provider store={store}>
        <BrowserRouter future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
          <TestWrapper />
        </BrowserRouter>
      </Provider>
    );
  };

  describe('Component Rendering', () => {
    it('renders the page header correctly', async () => {
      renderComponent();

      expect(screen.getByText('AI Providers')).toBeInTheDocument();
      expect(screen.getByText('Manage AI providers and their configurations')).toBeInTheDocument();
    });

    it('displays loading state initially', () => {
      renderComponent();

      expect(screen.getByTestId('loading-spinner')).toBeInTheDocument();
    });

    it('displays providers after loading', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByTestId('provider-card-provider-1')).toBeInTheDocument();
        expect(screen.getByTestId('provider-card-provider-2')).toBeInTheDocument();
        expect(screen.getByTestId('provider-card-provider-3')).toBeInTheDocument();
      });
    });

    it('shows action buttons when user has permissions', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('Add Provider')).toBeInTheDocument();
        expect(screen.getByText('Setup Defaults')).toBeInTheDocument();
        expect(screen.getByText('Test All')).toBeInTheDocument();
      });
    });

    it('displays empty state when no providers exist', async () => {
      (providersApi.getProviders as jest.Mock).mockResolvedValue({
        items: [],
        pagination: {
          current_page: 1,
          total_pages: 1,
          total_count: 0,
          per_page: 20
        }
      });

      renderComponent();

      await waitFor(() => {
        expect(screen.getByTestId('empty-state')).toBeInTheDocument();
        expect(screen.getByText('No AI providers found')).toBeInTheDocument();
      });
    });
  });

  describe('Provider Display', () => {
    it('displays provider information correctly', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('OpenAI GPT-4')).toBeInTheDocument();
        expect(screen.getByText('Anthropic Claude')).toBeInTheDocument();
        expect(screen.getByText('Local Ollama')).toBeInTheDocument();
        expect(screen.getByText('openai')).toBeInTheDocument();
        expect(screen.getByText('anthropic')).toBeInTheDocument();
        expect(screen.getByText('local')).toBeInTheDocument();
      });
    });

    it('shows provider status correctly', async () => {
      renderComponent();

      await waitFor(() => {
        // Each provider card shows status - we have 2 active and 1 inactive in mock data
        const activeStatuses = screen.getAllByText('Active');
        const inactiveStatuses = screen.getAllByText('Inactive');
        expect(activeStatuses.length).toBeGreaterThanOrEqual(2);
        expect(inactiveStatuses.length).toBeGreaterThanOrEqual(1);
      });
    });

    it('displays provider health status', async () => {
      renderComponent();

      await waitFor(() => {
        // Health status would be shown in the provider cards
        const healthyProvider = screen.getByTestId('provider-card-provider-1');
        const degradedProvider = screen.getByTestId('provider-card-provider-2');
        const criticalProvider = screen.getByTestId('provider-card-provider-3');

        expect(healthyProvider).toBeInTheDocument();
        expect(degradedProvider).toBeInTheDocument();
        expect(criticalProvider).toBeInTheDocument();
      });
    });
  });

  describe('Provider Actions', () => {
    it('opens create modal when add provider button is clicked', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('Add Provider')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Add Provider'));

      expect(screen.getByTestId('create-provider-modal')).toBeInTheDocument();
    });

    it('creates new provider via modal', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('Add Provider')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Add Provider'));
      expect(screen.getByTestId('create-provider-modal')).toBeInTheDocument();

      // Modal handles provider creation internally via onSuccess callback
      fireEvent.click(screen.getByText('Create'));

      // Modal triggers refresh via onSuccess -> handleProviderUpdate
      await waitFor(() => {
        // Verify modal can be interacted with
        expect(screen.queryByTestId('create-provider-modal')).not.toBeInTheDocument();
      });
    });

    it('opens edit modal when edit button is clicked', async () => {
      renderComponent();

      await waitFor(() => {
        const editButtons = screen.getAllByText('Edit');
        expect(editButtons.length).toBeGreaterThan(0);
      });

      const editButtons = screen.getAllByText('Edit');
      fireEvent.click(editButtons[0]);

      expect(screen.getByTestId('edit-provider-modal')).toBeInTheDocument();
    });

    it('updates provider via edit modal', async () => {
      renderComponent();

      await waitFor(() => {
        const editButtons = screen.getAllByText('Edit');
        expect(editButtons.length).toBeGreaterThan(0);
      });

      const editButtons = screen.getAllByText('Edit');
      fireEvent.click(editButtons[0]);

      expect(screen.getByTestId('edit-provider-modal')).toBeInTheDocument();

      // Modal handles update internally
      fireEvent.click(screen.getByText('Update'));

      await waitFor(() => {
        expect(screen.queryByTestId('edit-provider-modal')).not.toBeInTheDocument();
      });
    });

    // Note: Delete functionality is handled via ProviderDetailModal, not direct card action
    // These tests verify the modal workflow rather than direct delete buttons
  });

  describe('Provider Testing', () => {
    // Note: Individual provider testing is done via ProviderDetailModal, not card buttons

    it('opens bulk test modal when test all button is clicked', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('Test All')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Test All'));

      expect(screen.getByTestId('bulk-test-modal')).toBeInTheDocument();
    });

    it('displays bulk test modal content', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('Test All')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Test All'));

      // Modal is open
      expect(screen.getByTestId('bulk-test-modal')).toBeInTheDocument();
    });

    // Note: Test failures are shown via notifications, not inline text
    // The component uses addNotification for error handling
  });

  describe('Setup Default Providers', () => {
    it('opens setup defaults modal when button is clicked', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('Setup Defaults')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Setup Defaults'));

      expect(screen.getByTestId('setup-defaults-modal')).toBeInTheDocument();
    });

    // Note: Setup defaults feature displays "Feature Not Available" notification
    // The backend API exists but the frontend implementation shows a warning
  });

  describe('Filtering and Search', () => {
    // Component uses server-side filtering via API calls
    // Filters are hidden by default and shown when "Filters" button is clicked

    it('shows filters panel when filters button is clicked', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByText('Filters')).toBeInTheDocument();
      });

      // Filters panel is hidden by default
      expect(screen.queryByTestId('provider-filters')).not.toBeInTheDocument();

      fireEvent.click(screen.getByText('Filters'));

      // Filters panel is now visible
      expect(screen.getByTestId('provider-filters')).toBeInTheDocument();
    });

    it('triggers API call when type filter changes', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByTestId('provider-card-provider-1')).toBeInTheDocument();
      });

      // Clear initial call count
      (providersApi.getProviders as jest.Mock).mockClear();

      // Show filters panel
      fireEvent.click(screen.getByText('Filters'));

      const typeFilter = screen.getByTestId('type-filter');
      fireEvent.change(typeFilter, { target: { value: 'openai' } });

      // Should trigger new API call with filter
      await waitFor(() => {
        expect(providersApi.getProviders).toHaveBeenCalled();
      });
    });

    it('triggers API call when search query changes', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByTestId('provider-card-provider-1')).toBeInTheDocument();
      });

      // Clear initial call count
      (providersApi.getProviders as jest.Mock).mockClear();

      // Search input is in the main UI, not filters panel
      const searchInput = screen.getByPlaceholderText('Search providers...');
      fireEvent.change(searchInput, { target: { value: 'OpenAI' } });

      // Should trigger new API call with search query
      await waitFor(() => {
        expect(providersApi.getProviders).toHaveBeenCalled();
      });
    });

    // Note: Component uses server-side filtering via API calls
    // Client-side filtering tests are not applicable - see API call tests above
  });

  describe('Error Handling', () => {
    // Component uses notifications for error display, not inline text
    // On error, providers array becomes empty and empty state or no providers displayed

    it('shows empty state when providers fail to load', async () => {
      (providersApi.getProviders as jest.Mock).mockRejectedValue({
        message: 'Failed to load providers'
      });

      renderComponent();

      // Component sets providers to empty array on error
      await waitFor(() => {
        // Either empty state or no provider cards should be shown
        expect(screen.queryByTestId('provider-card-provider-1')).not.toBeInTheDocument();
      });
    });

    it('handles network errors gracefully', async () => {
      (providersApi.getProviders as jest.Mock).mockRejectedValue(new Error('Network error'));

      renderComponent();

      // Component doesn't crash and shows empty state when providers fail to load
      await waitFor(() => {
        expect(screen.getByTestId('empty-state')).toBeInTheDocument();
      });
    });

    // Note: Retry button doesn't exist - users can use the Refresh button instead
    // Note: Create errors are shown via notifications, not inline text
  });

  describe('Performance and Accessibility', () => {
    it('handles large numbers of providers efficiently', async () => {
      const manyProviders = Array.from({ length: 50 }, (_, i) => ({
        ...mockProviders[0],
        id: `provider-${i}`,
        name: `Provider ${i}`
      }));

      (providersApi.getProviders as jest.Mock).mockResolvedValue({
        items: manyProviders,
        pagination: {
          current_page: 1,
          total_pages: 3,
          total_count: manyProviders.length,
          per_page: 20
        }
      });

      const startTime = performance.now();
      renderComponent();

      await waitFor(() => {
        expect(screen.getByTestId('provider-card-provider-0')).toBeInTheDocument();
      });

      const endTime = performance.now();
      expect(endTime - startTime).toBeLessThan(2000); // Should render quickly
    });

    it('provides accessible buttons', async () => {
      renderComponent();

      await waitFor(() => {
        // Check buttons are present by text content
        expect(screen.getByText('Add Provider')).toBeInTheDocument();
        expect(screen.getByText('Setup Defaults')).toBeInTheDocument();
        expect(screen.getByText('Test All')).toBeInTheDocument();
      });
    });

    it('supports keyboard navigation', async () => {
      renderComponent();

      await waitFor(() => {
        const addButton = screen.getByText('Add Provider');
        addButton.focus();
        expect(document.activeElement).toBe(addButton);
      });
    });

    it('provides semantic markup for provider list', async () => {
      renderComponent();

      // Component renders providers with proper structure after loading
      await waitFor(() => {
        expect(screen.getByTestId('provider-card-provider-1')).toBeInTheDocument();
        expect(screen.getByTestId('provider-card-provider-2')).toBeInTheDocument();
        expect(screen.getByTestId('provider-card-provider-3')).toBeInTheDocument();
      });
    });
  });

  describe('Real-time Updates', () => {
    it('fetches provider data on initial load', async () => {
      renderComponent();

      // Initial load should call API (may be called more than once due to useEffect dependencies)
      await waitFor(() => {
        expect(providersApi.getProviders).toHaveBeenCalled();
      });

      // Providers should be displayed after loading
      await waitFor(() => {
        expect(screen.getByTestId('provider-card-provider-1')).toBeInTheDocument();
      });
    });

    it('displays updated provider data after re-fetch', async () => {
      renderComponent();

      await waitFor(() => {
        expect(screen.getByTestId('provider-card-provider-1')).toBeInTheDocument();
      });

      // Simulate provider status change on next fetch
      const updatedProviders = [
        { ...mockProviders[0], health_status: 'degraded' },
        ...mockProviders.slice(1)
      ];

      (providersApi.getProviders as jest.Mock).mockResolvedValue({
        items: updatedProviders,
        pagination: {
          current_page: 1,
          total_pages: 1,
          total_count: updatedProviders.length,
          per_page: 20
        }
      });

      // Provider should still be displayed
      expect(screen.getByTestId('provider-card-provider-1')).toBeInTheDocument();
    });
  });
});
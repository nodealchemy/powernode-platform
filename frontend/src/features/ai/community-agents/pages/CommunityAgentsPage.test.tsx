import { render, screen, fireEvent } from '@testing-library/react';
import { Provider } from 'react-redux';
import { BrowserRouter } from 'react-router-dom';
import { configureStore } from '@reduxjs/toolkit';
import { BreadcrumbProvider } from '@/shared/hooks/BreadcrumbContext';
import { CommunityAgentsPage } from './CommunityAgentsPage';

// Mock the API service
jest.mock('@/shared/services/ai', () => ({
  communityAgentsApi: {
    discoverAgents: jest.fn(),
    getFederationPartners: jest.fn(),
  },
}));

// Mock the permissions hook
jest.mock('@/shared/hooks/usePermissions', () => ({
  usePermissions: () => ({
    hasPermission: () => true,
  }),
}));

// Mock the notifications hook
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    addNotification: jest.fn(),
  }),
}));

// Mock UI components
jest.mock('@/shared/components/ui/Tabs', () => ({
  Tabs: ({ children, value, onValueChange: _onValueChange }: any) => (
    <div data-testid="tabs" data-value={value}>
      {children}
    </div>
  ),
  TabsList: ({ children }: any) => <div data-testid="tabs-list">{children}</div>,
  TabsTrigger: ({ children, value, onClick }: any) => (
    <button data-testid={`tab-trigger-${value}`} onClick={() => onClick?.(value)}>
      {children}
    </button>
  ),
  TabsContent: ({ children, value, className }: any) => (
    <div data-testid={`tab-content-${value}`} className={className}>
      {children}
    </div>
  ),
}));

// Mock child components
jest.mock('../components/AgentDiscovery', () => ({
  AgentDiscovery: ({ onInvokeAgent, onSelectAgent }: any) => (
    <div data-testid="agent-discovery">
      Agent Discovery Component
      <button
        data-testid="invoke-agent-btn"
        onClick={() => onInvokeAgent?.({ id: 'agent-1', name: 'Test Agent' })}
      >
        Invoke Agent
      </button>
      <button
        data-testid="select-agent-btn"
        onClick={() => onSelectAgent?.({ id: 'agent-1', name: 'Test Agent' })}
      >
        View Details
      </button>
    </div>
  ),
}));

jest.mock('../components/FederationPartnerList', () => ({
  FederationPartnerList: ({ onSelectPartner, onCreatePartner }: any) => (
    <div data-testid="federation-partner-list">
      Federation Partner List
      <button
        data-testid="select-partner-btn"
        onClick={() => onSelectPartner?.({ id: 'partner-1', name: 'Test Partner' })}
      >
        Select Partner
      </button>
      <button data-testid="create-partner-btn" onClick={onCreatePartner}>
        Create Partner
      </button>
    </div>
  ),
}));

describe('CommunityAgentsPage', () => {
  let store: any;

  beforeEach(() => {
    jest.clearAllMocks();

    store = configureStore({
      reducer: {
        auth: (state = { user: null, isAuthenticated: false }) => state,
      },
    });
  });

  const renderComponent = (props = {}) => {
    return render(
      <Provider store={store}>
        <BrowserRouter>
          <BreadcrumbProvider>
            <CommunityAgentsPage {...props} />
          </BreadcrumbProvider>
        </BrowserRouter>
      </Provider>
    );
  };

  describe('Initial Rendering', () => {
    it('renders the tabs component', () => {
      renderComponent();

      expect(screen.getByTestId('tabs')).toBeInTheDocument();
      expect(screen.getByTestId('tabs-list')).toBeInTheDocument();
    });

    it('renders discover tab trigger', () => {
      renderComponent();

      expect(screen.getByTestId('tab-trigger-discover')).toBeInTheDocument();
    });

    it('renders federation tab trigger', () => {
      renderComponent();

      expect(screen.getByTestId('tab-trigger-federation')).toBeInTheDocument();
    });

    it('renders agent discovery component', () => {
      renderComponent();

      expect(screen.getByTestId('agent-discovery')).toBeInTheDocument();
    });

    it('renders federation partner list component', () => {
      renderComponent();

      expect(screen.getByTestId('federation-partner-list')).toBeInTheDocument();
    });
  });

  describe('Callbacks', () => {
    it('calls onInvokeAgent when agent is invoked', () => {
      const onInvokeAgent = jest.fn();
      renderComponent({ onInvokeAgent });

      fireEvent.click(screen.getAllByTestId('invoke-agent-btn')[0]);

      expect(onInvokeAgent).toHaveBeenCalledWith(
        expect.objectContaining({
          id: 'agent-1',
          name: 'Test Agent',
        })
      );
    });

    it('calls onViewPartnerDetails when partner is selected', () => {
      const onViewPartnerDetails = jest.fn();
      renderComponent({ onViewPartnerDetails });

      fireEvent.click(screen.getAllByTestId('select-partner-btn')[0]);

      expect(onViewPartnerDetails).toHaveBeenCalledWith(
        expect.objectContaining({
          id: 'partner-1',
          name: 'Test Partner',
        })
      );
    });

    it('opens create partner modal when create partner is clicked', () => {
      renderComponent({});

      fireEvent.click(screen.getAllByTestId('create-partner-btn')[0]);

      expect(screen.getByText('Add Federation Partner')).toBeInTheDocument();
    });

    it('calls onViewAgentDetails when agent details is requested', () => {
      const onViewAgentDetails = jest.fn();
      renderComponent({ onViewAgentDetails });

      fireEvent.click(screen.getAllByTestId('select-agent-btn')[0]);

      expect(onViewAgentDetails).toHaveBeenCalledWith(
        expect.objectContaining({
          id: 'agent-1',
          name: 'Test Agent',
        })
      );
    });
  });

  describe('Tab Content', () => {
    it('shows discover content in discover tab', () => {
      renderComponent();

      expect(screen.getAllByTestId('tab-content-discover')[0]).toBeInTheDocument();
      expect(screen.getAllByTestId('agent-discovery')[0]).toBeInTheDocument();
    });

    it('shows federation content in federation tab', () => {
      renderComponent();

      expect(screen.getAllByTestId('tab-content-federation')[0]).toBeInTheDocument();
      expect(screen.getAllByTestId('federation-partner-list')[0]).toBeInTheDocument();
    });
  });
});

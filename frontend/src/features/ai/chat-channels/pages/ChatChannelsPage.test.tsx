import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { Provider } from 'react-redux';
import { BrowserRouter } from 'react-router-dom';
import { configureStore } from '@reduxjs/toolkit';
import { BreadcrumbProvider } from '@/shared/hooks/BreadcrumbContext';
import { ChatChannelsPage } from './ChatChannelsPage';

// Mock the API service
jest.mock('@/shared/services/ai', () => ({
  chatChannelsApi: {
    getChannels: jest.fn(),
    getChannelMetrics: jest.fn(),
    getChannelSessions: jest.fn(),
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
jest.mock('@/shared/components/ui/Button', () => ({
  Button: ({ children, onClick, variant, className }: any) => (
    <button onClick={onClick} data-variant={variant} className={className}>
      {children}
    </button>
  ),
}));

// Mock child components
jest.mock('../components/ChannelList', () => ({
  ChannelList: ({ onSelectChannel, onSettingsChannel }: any) => (
    <div data-testid="channel-list">
      <button
        data-testid="select-channel-btn"
        onClick={() =>
          onSelectChannel({
            id: 'channel-1',
            name: 'Test Channel',
            platform: 'telegram',
            status: 'connected',
          })
        }
      >
        Select Channel
      </button>
      <button
        data-testid="settings-channel-btn"
        onClick={() =>
          onSettingsChannel({
            id: 'channel-1',
            name: 'Test Channel',
            platform: 'telegram',
            status: 'connected',
          })
        }
      >
        Open Settings
      </button>
    </div>
  ),
}));

jest.mock('../components/ChannelSessions', () => ({
  ChannelSessions: ({ channelId, onSelectSession }: any) => (
    <div data-testid="channel-sessions">
      Channel Sessions for {channelId}
      <button onClick={onSelectSession}>Select Session</button>
    </div>
  ),
}));

jest.mock('../components/ChannelMetrics', () => ({
  ChannelMetrics: ({ channelId }: any) => (
    <div data-testid="channel-metrics">Metrics for {channelId}</div>
  ),
}));

jest.mock('../components/SessionTransferModal', () => ({
  SessionTransferModal: ({ isOpen }: any) =>
    isOpen ? <div data-testid="transfer-modal">Transfer Modal</div> : null,
}));

jest.mock('../components/ChannelSettingsModal', () => ({
  ChannelSettingsModal: ({ isOpen, channelId }: any) =>
    isOpen ? <div data-testid="settings-modal">Settings for {channelId}</div> : null,
}));

jest.mock('../components/SessionMessages', () => ({
  SessionMessages: ({ sessionId, onBack }: any) => (
    <div data-testid="session-messages">
      Messages for {sessionId}
      <button onClick={onBack}>Back</button>
    </div>
  ),
}));

describe('ChatChannelsPage', () => {
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
            <ChatChannelsPage {...props} />
          </BreadcrumbProvider>
        </BrowserRouter>
      </Provider>
    );
  };

  describe('Initial Rendering', () => {
    it('renders the channel list by default', () => {
      renderComponent();

      expect(screen.getByTestId('channel-list')).toBeInTheDocument();
    });

    it('does not show channel detail view initially', () => {
      renderComponent();

      expect(screen.queryByTestId('channel-metrics')).not.toBeInTheDocument();
      expect(screen.queryByTestId('channel-sessions')).not.toBeInTheDocument();
    });
  });

  describe('Channel Selection', () => {
    it('shows channel detail view when a channel is selected', async () => {
      renderComponent();

      fireEvent.click(screen.getByTestId('select-channel-btn'));

      await waitFor(() => {
        // Title appears in multiple places (page title + breadcrumb), so use getAllByText
        expect(screen.getAllByText('Test Channel').length).toBeGreaterThan(0);
        expect(screen.getByTestId('channel-metrics')).toBeInTheDocument();
        expect(screen.getByTestId('channel-sessions')).toBeInTheDocument();
      });
    });

    it('displays channel platform and status in detail view', async () => {
      renderComponent();

      fireEvent.click(screen.getByTestId('select-channel-btn'));

      await waitFor(() => {
        expect(screen.getByText(/telegram/i)).toBeInTheDocument();
        expect(screen.getByText(/connected/i)).toBeInTheDocument();
      });
    });

    it('passes correct channelId to child components', async () => {
      renderComponent();

      fireEvent.click(screen.getByTestId('select-channel-btn'));

      await waitFor(() => {
        expect(screen.getByText('Metrics for channel-1')).toBeInTheDocument();
        expect(screen.getByText('Channel Sessions for channel-1')).toBeInTheDocument();
      });
    });
  });

  describe('Navigation', () => {
    it('returns to channel list when back button is clicked', async () => {
      renderComponent();

      // Select a channel
      fireEvent.click(screen.getByTestId('select-channel-btn'));

      await waitFor(() => {
        expect(screen.getByTestId('channel-metrics')).toBeInTheDocument();
      });

      // Click back button (component uses "Back to List")
      fireEvent.click(screen.getByText('Back to List'));

      await waitFor(() => {
        expect(screen.getByTestId('channel-list')).toBeInTheDocument();
        expect(screen.queryByTestId('channel-metrics')).not.toBeInTheDocument();
      });
    });
  });

  describe('Settings Modal', () => {
    it('opens settings modal from channel list', async () => {
      renderComponent();

      fireEvent.click(screen.getByTestId('settings-channel-btn'));

      await waitFor(() => {
        expect(screen.getByTestId('settings-modal')).toBeInTheDocument();
      });
    });

    it('opens settings modal from channel detail view', async () => {
      renderComponent();

      // Select a channel first
      fireEvent.click(screen.getByTestId('select-channel-btn'));

      await waitFor(() => {
        expect(screen.getByText('Settings')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Settings'));

      await waitFor(() => {
        expect(screen.getByTestId('settings-modal')).toBeInTheDocument();
      });
    });
  });
});

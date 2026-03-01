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

// Mock the split-panel child components (replaces old ChannelList/ChannelSessions/ChannelMetrics)
const mockOnSelectChannel = jest.fn();

jest.mock('../components/ChannelListPanel', () => ({
  ChannelListPanel: ({ selectedChannelId, onSelectChannel }: any) => {
    // Store the callback so tests can trigger channel selection
    mockOnSelectChannel.mockImplementation(onSelectChannel);
    return (
      <div data-testid="channel-list-panel">
        <span>Selected: {selectedChannelId || 'none'}</span>
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
      </div>
    );
  },
}));

jest.mock('../components/ChannelDetailPanel', () => ({
  ChannelDetailPanel: ({ channel }: any) => (
    <div data-testid="channel-detail-panel">
      {channel ? (
        <>
          <span data-testid="detail-channel-name">{channel.name}</span>
          <span data-testid="detail-channel-platform">{channel.platform}</span>
          <span data-testid="detail-channel-status">{channel.status}</span>
        </>
      ) : (
        <span data-testid="no-channel-selected">No channel selected</span>
      )}
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
    it('renders the channel list panel', () => {
      renderComponent();

      expect(screen.getByTestId('channel-list-panel')).toBeInTheDocument();
    });

    it('renders the channel detail panel', () => {
      renderComponent();

      expect(screen.getByTestId('channel-detail-panel')).toBeInTheDocument();
    });

    it('shows no channel selected initially', () => {
      renderComponent();

      expect(screen.getByTestId('no-channel-selected')).toBeInTheDocument();
    });
  });

  describe('Channel Selection', () => {
    it('passes selected channel to detail panel when a channel is selected', async () => {
      renderComponent();

      fireEvent.click(screen.getByTestId('select-channel-btn'));

      await waitFor(() => {
        expect(screen.getByTestId('detail-channel-name')).toHaveTextContent('Test Channel');
      });
    });

    it('displays channel platform in detail panel', async () => {
      renderComponent();

      fireEvent.click(screen.getByTestId('select-channel-btn'));

      await waitFor(() => {
        expect(screen.getByTestId('detail-channel-platform')).toHaveTextContent('telegram');
      });
    });

    it('displays channel status in detail panel', async () => {
      renderComponent();

      fireEvent.click(screen.getByTestId('select-channel-btn'));

      await waitFor(() => {
        expect(screen.getByTestId('detail-channel-status')).toHaveTextContent('connected');
      });
    });

    it('passes selected channel id to list panel', async () => {
      renderComponent();

      fireEvent.click(screen.getByTestId('select-channel-btn'));

      await waitFor(() => {
        expect(screen.getByText('Selected: channel-1')).toBeInTheDocument();
      });
    });
  });
});

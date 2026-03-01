import React from 'react';
import { render, screen, fireEvent, waitFor, act } from '@testing-library/react';
import { Provider } from 'react-redux';
import { BrowserRouter } from 'react-router-dom';
import { configureStore } from '@reduxjs/toolkit';
import { NotificationBell } from './NotificationBell';

// Mock notification API
const mockGetNotifications = jest.fn();
const mockGetUnreadCount = jest.fn();
const mockMarkAsRead = jest.fn();
const mockDismiss = jest.fn();
const mockMarkAllAsRead = jest.fn();

// Mock ChatWindowContext used by NotificationBell
jest.mock('@/features/ai/chat/context/ChatWindowContext', () => ({
  useChatWindow: () => ({
    openConversationMaximized: jest.fn(),
  }),
}));

// Mock notification WebSocket
jest.mock('@/shared/hooks/useNotificationWebSocket', () => ({
  useNotificationWebSocket: () => ({
    isConnected: false,
  }),
}));

jest.mock('../services/notificationApi', () => ({
  notificationApi: {
    getNotifications: (...args: any[]) => mockGetNotifications(...args),
    getUnreadCount: (...args: any[]) => mockGetUnreadCount(...args),
    markAsRead: (...args: any[]) => mockMarkAsRead(...args),
    dismiss: (...args: any[]) => mockDismiss(...args),
    markAllAsRead: (...args: any[]) => mockMarkAllAsRead(...args)
  }
}));

// Create mock store
const createMockStore = (isAuthenticated = true) => configureStore({
  reducer: {
    auth: () => ({
      isAuthenticated,
      user: isAuthenticated ? { id: 'user-1', email: 'test@example.com' } : null
    })
  }
});

const renderWithProviders = (component: React.ReactElement, isAuthenticated = true) => {
  const store = createMockStore(isAuthenticated);
  return render(
    <Provider store={store}>
      <BrowserRouter>
        {component}
      </BrowserRouter>
    </Provider>
  );
};

describe('NotificationBell', () => {
  const mockNotifications = [
    {
      id: 'notif-1',
      title: 'Subscription Renewed',
      message: 'Your subscription has been automatically renewed',
      severity: 'success',
      read: false,
      created_at: new Date().toISOString(),
      action_url: '/app/billing',
      action_label: 'View Billing'
    },
    {
      id: 'notif-2',
      title: 'Payment Failed',
      message: 'Your payment method declined',
      severity: 'error',
      read: true,
      created_at: new Date(Date.now() - 3600000).toISOString() // 1 hour ago
    },
    {
      id: 'notif-3',
      title: 'System Update',
      message: 'Maintenance scheduled for tonight',
      severity: 'warning',
      read: false,
      created_at: new Date(Date.now() - 86400000).toISOString() // 1 day ago
    }
  ];

  beforeEach(() => {
    jest.clearAllMocks();
    jest.useFakeTimers();
    mockGetNotifications.mockResolvedValue({
      notifications: mockNotifications,
      unread_count: 2
    });
    mockGetUnreadCount.mockResolvedValue(2);
    mockMarkAsRead.mockResolvedValue({ success: true });
    mockDismiss.mockResolvedValue({ success: true });
    mockMarkAllAsRead.mockResolvedValue({ success: true });
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  describe('rendering', () => {
    it('renders bell button', async () => {
      renderWithProviders(<NotificationBell />);

      expect(screen.getByRole('button', { name: 'Notifications' })).toBeInTheDocument();
    });

    it('shows unread count badge when > 0', async () => {
      renderWithProviders(<NotificationBell />);

      await waitFor(() => {
        expect(screen.getByText('2')).toBeInTheDocument();
      });
    });

    it('shows 99+ when unread count exceeds 99', async () => {
      mockGetNotifications.mockResolvedValue({
        notifications: mockNotifications,
        unread_count: 150
      });

      renderWithProviders(<NotificationBell />);

      await waitFor(() => {
        expect(screen.getByText('99+')).toBeInTheDocument();
      });
    });

    it('does not show badge when unread count is 0', async () => {
      mockGetNotifications.mockResolvedValue({
        notifications: [],
        unread_count: 0
      });

      renderWithProviders(<NotificationBell />);

      await waitFor(() => {
        expect(mockGetNotifications).toHaveBeenCalled();
      });

      expect(screen.queryByText('0')).not.toBeInTheDocument();
    });

    it('applies custom className', () => {
      renderWithProviders(<NotificationBell className="custom-class" />);

      const container = screen.getByRole('button', { name: 'Notifications' }).parentElement;
      expect(container).toHaveClass('custom-class');
    });
  });

  describe('dropdown behavior', () => {
    it('opens dropdown when bell clicked', async () => {
      renderWithProviders(<NotificationBell />);

      await waitFor(() => {
        expect(mockGetNotifications).toHaveBeenCalled();
      });

      fireEvent.click(screen.getByRole('button', { name: 'Notifications' }));

      expect(screen.getByText('Notifications')).toBeInTheDocument();
    });

    it('closes dropdown when clicked again', async () => {
      renderWithProviders(<NotificationBell />);

      await waitFor(() => {
        expect(mockGetNotifications).toHaveBeenCalled();
      });

      const bellButton = screen.getByRole('button', { name: 'Notifications' });
      fireEvent.click(bellButton);

      expect(screen.getByText('Subscription Renewed')).toBeInTheDocument();

      fireEvent.click(bellButton);

      expect(screen.queryByText('Subscription Renewed')).not.toBeInTheDocument();
    });

    it('reloads notifications when dropdown opens', async () => {
      renderWithProviders(<NotificationBell />);

      await waitFor(() => {
        expect(mockGetNotifications).toHaveBeenCalledTimes(1);
      });

      fireEvent.click(screen.getByRole('button', { name: 'Notifications' }));

      await waitFor(() => {
        expect(mockGetNotifications).toHaveBeenCalledTimes(2);
      });
    });

    it('shows View all notifications link', async () => {
      renderWithProviders(<NotificationBell />);

      await waitFor(() => {
        expect(mockGetNotifications).toHaveBeenCalled();
      });

      fireEvent.click(screen.getByRole('button', { name: 'Notifications' }));

      expect(screen.getByText('View all notifications')).toBeInTheDocument();
    });
  });

  describe('notification list', () => {
    it('shows notification titles', async () => {
      renderWithProviders(<NotificationBell />);

      await waitFor(() => {
        expect(mockGetNotifications).toHaveBeenCalled();
      });

      fireEvent.click(screen.getByRole('button', { name: 'Notifications' }));

      expect(screen.getByText('Subscription Renewed')).toBeInTheDocument();
      expect(screen.getByText('Payment Failed')).toBeInTheDocument();
      expect(screen.getByText('System Update')).toBeInTheDocument();
    });

    it('shows notification messages', async () => {
      renderWithProviders(<NotificationBell />);

      await waitFor(() => {
        expect(mockGetNotifications).toHaveBeenCalled();
      });

      fireEvent.click(screen.getByRole('button', { name: 'Notifications' }));

      expect(screen.getByText('Your subscription has been automatically renewed')).toBeInTheDocument();
    });

    it('shows action labels when present', async () => {
      renderWithProviders(<NotificationBell />);

      await waitFor(() => {
        expect(mockGetNotifications).toHaveBeenCalled();
      });

      fireEvent.click(screen.getByRole('button', { name: 'Notifications' }));

      expect(screen.getByText('View Billing →')).toBeInTheDocument();
    });

    it('shows empty state when no notifications', async () => {
      mockGetNotifications.mockResolvedValue({
        notifications: [],
        unread_count: 0
      });

      renderWithProviders(<NotificationBell />);

      await waitFor(() => {
        expect(mockGetNotifications).toHaveBeenCalled();
      });

      fireEvent.click(screen.getByRole('button', { name: 'Notifications' }));

      expect(screen.getByText('No notifications')).toBeInTheDocument();
      expect(screen.getByText("You're all caught up!")).toBeInTheDocument();
    });
  });

  describe('mark as read', () => {
    it('calls markAsRead API when mark as read button clicked', async () => {
      renderWithProviders(<NotificationBell />);

      await waitFor(() => {
        expect(mockGetNotifications).toHaveBeenCalled();
      });

      fireEvent.click(screen.getByRole('button', { name: 'Notifications' }));

      const markReadButtons = screen.getAllByTitle('Mark as read');
      fireEvent.click(markReadButtons[0]);

      await waitFor(() => {
        expect(mockMarkAsRead).toHaveBeenCalledWith('notif-1');
      });
    });

    it('shows Mark all read button when unread notifications exist', async () => {
      renderWithProviders(<NotificationBell />);

      await waitFor(() => {
        expect(mockGetNotifications).toHaveBeenCalled();
      });

      fireEvent.click(screen.getByRole('button', { name: 'Notifications' }));

      expect(screen.getByText('Mark all read')).toBeInTheDocument();
    });

    it('calls markAllAsRead API when clicked', async () => {
      renderWithProviders(<NotificationBell />);

      await waitFor(() => {
        expect(mockGetNotifications).toHaveBeenCalled();
      });

      fireEvent.click(screen.getByRole('button', { name: 'Notifications' }));
      fireEvent.click(screen.getByText('Mark all read'));

      await waitFor(() => {
        expect(mockMarkAllAsRead).toHaveBeenCalled();
      });
    });
  });

  describe('dismiss', () => {
    it('calls dismiss API when dismiss button clicked', async () => {
      renderWithProviders(<NotificationBell />);

      await waitFor(() => {
        expect(mockGetNotifications).toHaveBeenCalled();
      });

      fireEvent.click(screen.getByRole('button', { name: 'Notifications' }));

      const dismissButtons = screen.getAllByTitle('Dismiss');
      fireEvent.click(dismissButtons[0]);

      await waitFor(() => {
        expect(mockDismiss).toHaveBeenCalledWith('notif-1');
      });
    });
  });

  describe('authentication', () => {
    it('does not load notifications when not authenticated', async () => {
      renderWithProviders(<NotificationBell />, false);

      await act(async () => {
        jest.advanceTimersByTime(100);
      });

      expect(mockGetNotifications).not.toHaveBeenCalled();
    });

    it('resets state when not authenticated', async () => {
      renderWithProviders(<NotificationBell />, false);

      expect(screen.queryByText('2')).not.toBeInTheDocument();
    });
  });

  describe('time formatting', () => {
    it('shows Just now for recent notifications', async () => {
      const recentNotification = {
        ...mockNotifications[0],
        created_at: new Date().toISOString()
      };
      mockGetNotifications.mockResolvedValue({
        notifications: [recentNotification],
        unread_count: 1
      });

      renderWithProviders(<NotificationBell />);

      await waitFor(() => {
        expect(mockGetNotifications).toHaveBeenCalled();
      });

      fireEvent.click(screen.getByRole('button', { name: 'Notifications' }));

      expect(screen.getByText('Just now')).toBeInTheDocument();
    });

    it('shows hours ago for older notifications', async () => {
      const hourAgoNotification = {
        ...mockNotifications[0],
        created_at: new Date(Date.now() - 3600000).toISOString() // 1 hour ago
      };
      mockGetNotifications.mockResolvedValue({
        notifications: [hourAgoNotification],
        unread_count: 1
      });

      renderWithProviders(<NotificationBell />);

      await waitFor(() => {
        expect(mockGetNotifications).toHaveBeenCalled();
      });

      fireEvent.click(screen.getByRole('button', { name: 'Notifications' }));

      expect(screen.getByText('1h ago')).toBeInTheDocument();
    });

    it('shows days ago for older notifications', async () => {
      const dayAgoNotification = {
        ...mockNotifications[0],
        created_at: new Date(Date.now() - 86400000 * 2).toISOString() // 2 days ago
      };
      mockGetNotifications.mockResolvedValue({
        notifications: [dayAgoNotification],
        unread_count: 1
      });

      renderWithProviders(<NotificationBell />);

      await waitFor(() => {
        expect(mockGetNotifications).toHaveBeenCalled();
      });

      fireEvent.click(screen.getByRole('button', { name: 'Notifications' }));

      expect(screen.getByText('2d ago')).toBeInTheDocument();
    });
  });
});

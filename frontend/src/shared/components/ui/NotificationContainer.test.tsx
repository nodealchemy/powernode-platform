import React from 'react';
import { screen, fireEvent, waitFor, act } from '@testing-library/react';
import { renderWithProviders, mockAuthenticatedState } from '@/shared/utils/test-utils';
import { NotificationContainer } from './NotificationContainer';
import { addNotification, removeNotification } from '@/shared/services/slices/uiSlice';

// Mock timers for auto-dismiss functionality
jest.useFakeTimers();

describe('NotificationContainer', () => {
  beforeEach(() => {
    jest.clearAllTimers();
  });

  afterEach(() => {
    act(() => {
      jest.runOnlyPendingTimers();
    });
    jest.clearAllTimers();
  });

  it('renders nothing when no notifications exist', () => {
    const { container } = renderWithProviders(<NotificationContainer />, {
      preloadedState: mockAuthenticatedState
    });
    expect(container.firstChild).toBeNull();
  });

  it('displays success notifications with correct styling and icon', () => {
    const stateWithNotification = {
      ...mockAuthenticatedState,
      ui: {
        ...mockAuthenticatedState.ui,
        notifications: [{
          id: '1',
          type: 'success' as const,
          message: 'Operation completed successfully'
        }]
      }
    };

    renderWithProviders(<NotificationContainer />, {
      preloadedState: stateWithNotification
    });

    const notification = screen.getByText('Operation completed successfully');
    expect(notification).toBeInTheDocument();

    const container = notification.closest('div');
    expect(container).toHaveClass('bg-theme-success');
    
    // Check for success icon (checkmark)
    const successIcon = container?.querySelector('svg path[d*="M5 13l4 4L19 7"]');
    expect(successIcon).toBeInTheDocument();
  });

  it('displays error notifications with correct styling and icon', () => {
    const stateWithNotification = {
      ...mockAuthenticatedState,
      ui: {
        ...mockAuthenticatedState.ui,
        notifications: [{
          id: '2',
          type: 'error' as const,
          message: 'Something went wrong',
          timestamp: Date.now()
        }]
      }
    };

    renderWithProviders(<NotificationContainer />, {
      preloadedState: stateWithNotification
    });

    const notification = screen.getByText('Something went wrong');
    expect(notification).toBeInTheDocument();

    const container = notification.closest('div');
    expect(container).toHaveClass('bg-theme-error');
    
    // Check for error icon (X)
    const errorIcon = container?.querySelector('svg path[d*="M6 18L18 6M6 6l12 12"]');
    expect(errorIcon).toBeInTheDocument();
  });

  it('displays warning notifications with correct styling and icon', () => {
    const stateWithNotification = {
      ...mockAuthenticatedState,
      ui: {
        ...mockAuthenticatedState.ui,
        notifications: [{
          id: '3',
          type: 'warning' as const,
          message: 'Please review your settings',
          timestamp: Date.now()
        }]
      }
    };

    renderWithProviders(<NotificationContainer />, {
      preloadedState: stateWithNotification
    });

    const notification = screen.getByText('Please review your settings');
    expect(notification).toBeInTheDocument();

    const container = notification.closest('div');
    expect(container).toHaveClass('bg-theme-warning');
    
    // Check for warning icon (triangle with exclamation)
    const warningIcon = container?.querySelector('svg path[d*="M12 9v2m0 4h.01"]');
    expect(warningIcon).toBeInTheDocument();
  });

  it('displays info notifications with correct styling and icon', () => {
    const stateWithNotification = {
      ...mockAuthenticatedState,
      ui: {
        ...mockAuthenticatedState.ui,
        notifications: [{
          id: '4',
          type: 'info' as const,
          message: 'Here is some information',
          timestamp: Date.now()
        }]
      }
    };

    renderWithProviders(<NotificationContainer />, {
      preloadedState: stateWithNotification
    });

    const notification = screen.getByText('Here is some information');
    expect(notification).toBeInTheDocument();

    const container = notification.closest('div');
    expect(container).toHaveClass('bg-theme-info');
    
    // Check for info icon (circle with i)
    const infoIcon = container?.querySelector('svg path[d*="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"]');
    expect(infoIcon).toBeInTheDocument();
  });

  it('displays multiple notifications simultaneously', () => {
    const stateWithNotifications = {
      ...mockAuthenticatedState,
      ui: {
        ...mockAuthenticatedState.ui,
        notifications: [
          { id: '5', type: 'success' as const, message: 'Success message', timestamp: Date.now() },
          { id: '6', type: 'error' as const, message: 'Error message', timestamp: Date.now() },
          { id: '7', type: 'info' as const, message: 'Info message', timestamp: Date.now() }
        ]
      }
    };

    renderWithProviders(<NotificationContainer />, {
      preloadedState: stateWithNotifications
    });

    expect(screen.getByText('Success message')).toBeInTheDocument();
    expect(screen.getByText('Error message')).toBeInTheDocument();
    expect(screen.getByText('Info message')).toBeInTheDocument();
  });

  it('allows manual dismissal of notifications', () => {
    const stateWithNotification = {
      ...mockAuthenticatedState,
      ui: {
        ...mockAuthenticatedState.ui,
        notifications: [{
          id: '8',
          type: 'info' as const,
          message: 'Dismissible notification',
          timestamp: Date.now()
        }]
      }
    };

    const { store } = renderWithProviders(<NotificationContainer />, {
      preloadedState: stateWithNotification
    });

    const notification = screen.getByText('Dismissible notification');
    expect(notification).toBeInTheDocument();

    // Find and click dismiss button
    const dismissButton = screen.getByTitle('Dismiss');
    fireEvent.click(dismissButton);

    expect(screen.queryByText('Dismissible notification')).not.toBeInTheDocument();
  });

  it('auto-dismisses notifications after 5 seconds', async () => {
    const stateWithNotification = {
      ...mockAuthenticatedState,
      ui: {
        ...mockAuthenticatedState.ui,
        notifications: [{
          id: '9',
          type: 'success' as const,
          message: 'Auto-dismiss test',
          timestamp: Date.now()
        }]
      }
    };

    renderWithProviders(<NotificationContainer />, {
      preloadedState: stateWithNotification
    });

    expect(screen.getByText('Auto-dismiss test')).toBeInTheDocument();

    // Fast-forward time by 5 seconds
    await act(async () => {
      jest.advanceTimersByTime(5000);
    });

    await waitFor(() => {
      expect(screen.queryByText('Auto-dismiss test')).not.toBeInTheDocument();
    });
  });

  it('clears timeouts when component unmounts', async () => {
    const stateWithNotification = {
      ...mockAuthenticatedState,
      ui: {
        ...mockAuthenticatedState.ui,
        notifications: [{
          id: '10',
          type: 'info' as const,
          message: 'Unmount test',
          timestamp: Date.now()
        }]
      }
    };

    const { unmount, store } = renderWithProviders(<NotificationContainer />, {
      preloadedState: stateWithNotification
    });

    expect(screen.getByText('Unmount test')).toBeInTheDocument();

    // Unmount before timeout
    unmount();

    // Fast-forward time
    await act(async () => {
      jest.advanceTimersByTime(5000);
    });

    // Notification should still exist in store since timeout was cleared
    const state = store.getState();
    expect(state.ui.notifications).toHaveLength(1);
  });

  it('handles notification updates properly', async () => {
    // Start with both notifications
    const stateWithNotifications = {
      ...mockAuthenticatedState,
      ui: {
        ...mockAuthenticatedState.ui,
        notifications: [
          {
            id: '1',
            type: 'success' as const,
            message: 'First notification',
            timestamp: Date.now() - 100
          },
          {
            id: '2',
            type: 'error' as const,
            message: 'Second notification',
            timestamp: Date.now()
          }
        ]
      }
    };

    renderWithProviders(<NotificationContainer />, {
      preloadedState: stateWithNotifications
    });

    // Both should be visible initially
    expect(screen.getByText('First notification')).toBeInTheDocument();
    expect(screen.getByText('Second notification')).toBeInTheDocument();

    // Manually dismiss the first one
    const dismissButtons = screen.getAllByTitle('Dismiss');
    fireEvent.click(dismissButtons[0]);

    // First should be gone, second should still be visible
    await waitFor(() => {
      expect(screen.queryByText('First notification')).not.toBeInTheDocument();
    });
    expect(screen.getByText('Second notification')).toBeInTheDocument();
  });

  it('truncates long messages appropriately', () => {
    const longMessage = 'This is a very long notification message that should be truncated when it exceeds the maximum width allowed for notifications in the UI';

    const stateWithNotification = {
      ...mockAuthenticatedState,
      ui: {
        ...mockAuthenticatedState.ui,
        notifications: [{
          id: '11',
          type: 'info' as const,
          message: longMessage,
          timestamp: Date.now()
        }]
      }
    };

    renderWithProviders(<NotificationContainer />, {
      preloadedState: stateWithNotification
    });

    const messageElement = screen.getByText(longMessage);
    expect(messageElement).toBeInTheDocument();
    expect(messageElement).toHaveClass('truncate', 'max-w-xs');
  });

  it('positions notifications correctly', () => {
    const stateWithNotification = {
      ...mockAuthenticatedState,
      ui: {
        ...mockAuthenticatedState.ui,
        notifications: [{
          id: '1',
          type: 'success' as const,
          message: 'Position test',
          timestamp: Date.now()
        }]
      }
    };

    const { container } = renderWithProviders(<NotificationContainer />, {
      preloadedState: stateWithNotification
    });

    const notificationContainer = container.firstChild as HTMLElement;
    expect(notificationContainer).toHaveClass('fixed', 'top-4', 'left-1/2', 'transform', '-translate-x-1/2', 'z-50');
  });

  it('applies fade-in animation to notifications', () => {
    const stateWithNotification = {
      ...mockAuthenticatedState,
      ui: {
        ...mockAuthenticatedState.ui,
        notifications: [{
          id: '1',
          type: 'success' as const,
          message: 'Animation test',
          timestamp: Date.now()
        }]
      }
    };

    renderWithProviders(<NotificationContainer />, {
      preloadedState: stateWithNotification
    });

    const notificationElement = screen.getByText('Animation test').closest('div');
    expect(notificationElement).toHaveClass('animate-fade-in');
  });

  it('handles rapid notification additions and removals', async () => {
    const notifications = Array.from({ length: 5 }, (_, i) => ({
      id: `${i + 1}`,
      type: 'info' as const,
      message: `Notification ${i + 1}`,
      timestamp: Date.now() + i
    }));

    const stateWithNotifications = {
      ...mockAuthenticatedState,
      ui: {
        ...mockAuthenticatedState.ui,
        notifications
      }
    };

    const { rerender } = renderWithProviders(<NotificationContainer />, {
      preloadedState: stateWithNotifications
    });

    // All should be visible
    for (let i = 0; i < 5; i++) {
      expect(screen.getByText(`Notification ${i + 1}`)).toBeInTheDocument();
    }

    // Manually dismiss some
    const dismissButtons = screen.getAllByTitle('Dismiss');
    fireEvent.click(dismissButtons[0]);
    fireEvent.click(dismissButtons[1]);

    expect(screen.queryByText('Notification 1')).not.toBeInTheDocument();
    expect(screen.queryByText('Notification 2')).not.toBeInTheDocument();
    expect(screen.getByText('Notification 3')).toBeInTheDocument();

    // Auto-dismiss remaining after 5 seconds
    await act(async () => {
      jest.advanceTimersByTime(5000);
    });

    await waitFor(() => {
      expect(screen.queryByText('Notification 3')).not.toBeInTheDocument();
      expect(screen.queryByText('Notification 4')).not.toBeInTheDocument();
      expect(screen.queryByText('Notification 5')).not.toBeInTheDocument();
    });
  });

  it('handles dismiss button hover states', () => {
    const stateWithNotification = {
      ...mockAuthenticatedState,
      ui: {
        ...mockAuthenticatedState.ui,
        notifications: [{
          id: '1',
          type: 'success' as const,
          message: 'Hover test',
          timestamp: Date.now()
        }]
      }
    };

    renderWithProviders(<NotificationContainer />, {
      preloadedState: stateWithNotification
    });

    const dismissButton = screen.getByTitle('Dismiss');
    expect(dismissButton).toHaveClass('hover:bg-black', 'hover:bg-opacity-10', 'transition-colors');
  });

  it('maintains proper spacing between multiple notifications', () => {
    const stateWithNotifications = {
      ...mockAuthenticatedState,
      ui: {
        ...mockAuthenticatedState.ui,
        notifications: [
          { id: '15', type: 'success' as const, message: 'First', timestamp: Date.now() },
          { id: '16', type: 'error' as const, message: 'Second', timestamp: Date.now() },
          { id: '17', type: 'info' as const, message: 'Third', timestamp: Date.now() }
        ]
      }
    };

    const { container } = renderWithProviders(<NotificationContainer />, {
      preloadedState: stateWithNotifications
    });

    const notificationContainer = container.firstChild as HTMLElement;
    expect(notificationContainer).toHaveClass('space-y-2');
  });

  it('ensures accessibility for screen readers', () => {
    const stateWithNotification = {
      ...mockAuthenticatedState,
      ui: {
        ...mockAuthenticatedState.ui,
        notifications: [{
          id: '18',
          type: 'error' as const,
          message: 'Accessibility test',
          timestamp: Date.now()
        }]
      }
    };

    renderWithProviders(<NotificationContainer />, {
      preloadedState: stateWithNotification
    });

    const dismissButton = screen.getByTitle('Dismiss');
    expect(dismissButton).toHaveAttribute('title', 'Dismiss');

    // Icons should have proper SVG structure for screen readers
    const errorIcon = screen.getByText('Accessibility test').closest('div')?.querySelector('svg');
    expect(errorIcon).toHaveAttribute('viewBox', '0 0 24 24');
  });
});
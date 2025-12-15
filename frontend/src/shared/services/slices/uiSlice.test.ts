import uiReducer, {
  toggleSidebar,
  setSidebarOpen,
  toggleSidebarCollapse,
  setSidebarCollapsed,
  setTheme,
  setLoading,
  addNotification,
  removeNotification,
  clearNotifications
} from './uiSlice';

interface NotificationState {
  id: string;
  type: 'success' | 'error' | 'warning' | 'info';
  message: string;
  timestamp: number;
}

interface TestUIState {
  sidebarOpen: boolean;
  sidebarCollapsed: boolean;
  theme: 'light' | 'dark';
  loading: boolean;
  notifications: NotificationState[];
}

describe('uiSlice', () => {
  const initialState: TestUIState = {
    sidebarOpen: false, // Collapsed by default on mobile
    sidebarCollapsed: false,
    theme: 'light' as const,
    loading: false,
    notifications: []
  };

  it('should return the initial state', () => {
    expect(uiReducer(undefined, { type: 'unknown' })).toEqual(initialState);
  });

  describe('sidebar actions', () => {
    it('should toggle sidebar open state', () => {
      const currentState = { ...initialState, sidebarOpen: false };
      const actual = uiReducer(currentState, toggleSidebar());
      expect(actual.sidebarOpen).toBe(true);

      const nextState = uiReducer(actual, toggleSidebar());
      expect(nextState.sidebarOpen).toBe(false);
    });

    it('should set sidebar open state explicitly', () => {
      const currentState = { ...initialState, sidebarOpen: false };
      
      const openState = uiReducer(currentState, setSidebarOpen(true));
      expect(openState.sidebarOpen).toBe(true);

      const closedState = uiReducer(openState, setSidebarOpen(false));
      expect(closedState.sidebarOpen).toBe(false);
    });

    it('should toggle sidebar collapse state', () => {
      const currentState = { ...initialState, sidebarCollapsed: false };
      const actual = uiReducer(currentState, toggleSidebarCollapse());
      expect(actual.sidebarCollapsed).toBe(true);

      const nextState = uiReducer(actual, toggleSidebarCollapse());
      expect(nextState.sidebarCollapsed).toBe(false);
    });

    it('should set sidebar collapsed state explicitly', () => {
      const currentState = { ...initialState, sidebarCollapsed: false };
      
      const collapsedState = uiReducer(currentState, setSidebarCollapsed(true));
      expect(collapsedState.sidebarCollapsed).toBe(true);

      const expandedState = uiReducer(collapsedState, setSidebarCollapsed(false));
      expect(expandedState.sidebarCollapsed).toBe(false);
    });
  });

  describe('theme actions', () => {
    it('should set theme to light', () => {
      const currentState = { ...initialState, theme: 'dark' as const };
      const actual = uiReducer(currentState, setTheme('light'));
      expect(actual.theme).toBe('light');
    });

    it('should set theme to dark', () => {
      const currentState = { ...initialState, theme: 'light' as const };
      const actual = uiReducer(currentState, setTheme('dark'));
      expect(actual.theme).toBe('dark');
    });

    it('should maintain other state when changing theme', () => {
      const currentState = {
        ...initialState,
        sidebarOpen: false,
        sidebarCollapsed: true,
        loading: true,
        notifications: [
          {
            id: '1',
            type: 'success' as const,
            message: 'Test',
            timestamp: Date.now()
          }
        ]
      };

      const actual = uiReducer(currentState, setTheme('dark'));
      
      expect(actual.theme).toBe('dark');
      expect(actual.sidebarOpen).toBe(false);
      expect(actual.sidebarCollapsed).toBe(true);
      expect(actual.loading).toBe(true);
      expect(actual.notifications).toHaveLength(1);
    });
  });

  describe('loading actions', () => {
    it('should set loading state to true', () => {
      const currentState = { ...initialState, loading: false };
      const actual = uiReducer(currentState, setLoading(true));
      expect(actual.loading).toBe(true);
    });

    it('should set loading state to false', () => {
      const currentState = { ...initialState, loading: true };
      const actual = uiReducer(currentState, setLoading(false));
      expect(actual.loading).toBe(false);
    });
  });

  describe('notification actions', () => {
    beforeEach(() => {
      // Mock Date.now() to ensure consistent timestamps in tests
      jest.spyOn(Date, 'now').mockReturnValue(1234567890);
    });

    afterEach(() => {
      jest.restoreAllMocks();
    });

    it('should add a notification', () => {
      const notification = {
        type: 'success' as const,
        message: 'Operation successful'
      };

      const actual = uiReducer(initialState, addNotification(notification));

      expect(actual.notifications).toHaveLength(1);
      expect(actual.notifications[0]).toEqual({
        id: '1234567890_0',
        type: 'success',
        message: 'Operation successful',
        timestamp: 1234567890
      });
    });

    it('should add multiple notifications with unique IDs', () => {
      let currentState = initialState;

      // Mock different timestamps for each notification (called twice per notification: id and timestamp)
      jest.spyOn(Date, 'now')
        .mockReturnValueOnce(1000)
        .mockReturnValueOnce(1000)
        .mockReturnValueOnce(2000)
        .mockReturnValueOnce(2000)
        .mockReturnValueOnce(3000)
        .mockReturnValueOnce(3000);

      const notifications = [
        { type: 'success' as const, message: 'First' },
        { type: 'error' as const, message: 'Second' },
        { type: 'warning' as const, message: 'Third' }
      ];

      notifications.forEach(notification => {
        currentState = uiReducer(currentState, addNotification(notification));
      });

      expect(currentState.notifications).toHaveLength(3);
      expect(currentState.notifications[0].id).toBe('1000_0');
      expect(currentState.notifications[1].id).toBe('1000_1');
      expect(currentState.notifications[2].id).toBe('2000_2');
      expect(currentState.notifications.map(n => n.message)).toEqual(['First', 'Second', 'Third']);
    });

    it('should support all notification types', () => {
      let currentState = initialState;
      const types: Array<'success' | 'error' | 'warning' | 'info'> = ['success', 'error', 'warning', 'info'];

      types.forEach((type, index) => {
        jest.spyOn(Date, 'now').mockReturnValue(index + 1);
        currentState = uiReducer(currentState, addNotification({
          type,
          message: `${type} message`
        }));
      });

      expect(currentState.notifications).toHaveLength(4);
      expect(currentState.notifications.map(n => n.type)).toEqual(types);
    });

    it('should remove a specific notification by ID', () => {
      const stateWithNotifications = {
        ...initialState,
        notifications: [
          {
            id: '1',
            type: 'success' as const,
            message: 'First',
            timestamp: 1000
          },
          {
            id: '2',
            type: 'error' as const,
            message: 'Second',
            timestamp: 2000
          },
          {
            id: '3',
            type: 'info' as const,
            message: 'Third',
            timestamp: 3000
          }
        ]
      };

      const actual = uiReducer(stateWithNotifications, removeNotification('2'));

      expect(actual.notifications).toHaveLength(2);
      expect(actual.notifications.map(n => n.id)).toEqual(['1', '3']);
      expect(actual.notifications.map(n => n.message)).toEqual(['First', 'Third']);
    });

    it('should not remove notification if ID does not exist', () => {
      const stateWithNotifications = {
        ...initialState,
        notifications: [
          {
            id: '1',
            type: 'success' as const,
            message: 'Test',
            timestamp: 1000
          }
        ]
      };

      const actual = uiReducer(stateWithNotifications, removeNotification('nonexistent'));

      expect(actual.notifications).toHaveLength(1);
      expect(actual.notifications[0].id).toBe('1');
    });

    it('should clear all notifications', () => {
      const stateWithNotifications = {
        ...initialState,
        notifications: [
          {
            id: '1',
            type: 'success' as const,
            message: 'First',
            timestamp: 1000
          },
          {
            id: '2',
            type: 'error' as const,
            message: 'Second',
            timestamp: 2000
          }
        ]
      };

      const actual = uiReducer(stateWithNotifications, clearNotifications());

      expect(actual.notifications).toHaveLength(0);
      expect(actual.notifications).toEqual([]);
    });

    it('should maintain notification order when adding and removing', () => {
      let currentState = initialState;

      // Add three notifications (mock Date.now twice per notification)
      jest.spyOn(Date, 'now')
        .mockReturnValueOnce(1000)
        .mockReturnValueOnce(1000)
        .mockReturnValueOnce(2000)
        .mockReturnValueOnce(2000)
        .mockReturnValueOnce(3000)
        .mockReturnValueOnce(3000);

      currentState = uiReducer(currentState, addNotification({
        type: 'success',
        message: 'First'
      }));
      currentState = uiReducer(currentState, addNotification({
        type: 'error',
        message: 'Second'
      }));
      currentState = uiReducer(currentState, addNotification({
        type: 'info',
        message: 'Third'
      }));

      expect(currentState.notifications.map(n => n.message)).toEqual(['First', 'Second', 'Third']);

      // Remove middle notification
      currentState = uiReducer(currentState, removeNotification('1000_1'));

      expect(currentState.notifications.map(n => n.message)).toEqual(['First', 'Third']);

      // Add another notification
      jest.spyOn(Date, 'now').mockReturnValueOnce(4000).mockReturnValueOnce(4000);
      currentState = uiReducer(currentState, addNotification({
        type: 'warning',
        message: 'Fourth'
      }));

      expect(currentState.notifications.map(n => n.message)).toEqual(['First', 'Third', 'Fourth']);
    });

    it('should handle edge cases for notification management', () => {
      // Test removing from empty array
      let currentState = initialState;
      currentState = uiReducer(currentState, removeNotification('nonexistent'));
      expect(currentState.notifications).toHaveLength(0);

      // Test clearing empty array
      currentState = uiReducer(currentState, clearNotifications());
      expect(currentState.notifications).toHaveLength(0);

      // Test adding notification with empty message
      jest.spyOn(Date, 'now').mockReturnValue(1000);
      currentState = uiReducer(currentState, addNotification({
        type: 'info',
        message: ''
      }));
      expect(currentState.notifications[0].message).toBe('');
    });

    it('should preserve other state when manipulating notifications', () => {
      const complexState = {
        ...initialState,
        sidebarOpen: false,
        sidebarCollapsed: true,
        theme: 'dark' as const,
        loading: true
      };

      jest.spyOn(Date, 'now').mockReturnValue(1000);
      const withNotification = uiReducer(complexState, addNotification({
        type: 'success',
        message: 'Test'
      }));

      expect(withNotification.sidebarOpen).toBe(false);
      expect(withNotification.sidebarCollapsed).toBe(true);
      expect(withNotification.theme).toBe('dark');
      expect(withNotification.loading).toBe(true);
      expect(withNotification.notifications).toHaveLength(1);

      const clearedNotifications = uiReducer(withNotification, clearNotifications());

      expect(clearedNotifications.sidebarOpen).toBe(false);
      expect(clearedNotifications.sidebarCollapsed).toBe(true);
      expect(clearedNotifications.theme).toBe('dark');
      expect(clearedNotifications.loading).toBe(true);
      expect(clearedNotifications.notifications).toHaveLength(0);
    });
  });

  describe('state immutability', () => {
    it('should not mutate the original state', () => {
      const originalState = { ...initialState };
      const newState = uiReducer(originalState, toggleSidebar());

      expect(originalState).toEqual(initialState);
      expect(newState).not.toBe(originalState);
    });

    it('should not mutate notifications array when adding', () => {
      jest.spyOn(Date, 'now').mockReturnValue(1000);
      
      const originalState = { ...initialState };
      const newState = uiReducer(originalState, addNotification({
        type: 'success',
        message: 'Test'
      }));

      expect(originalState.notifications).toEqual([]);
      expect(newState.notifications).not.toBe(originalState.notifications);
      expect(newState.notifications).toHaveLength(1);
    });
  });
});
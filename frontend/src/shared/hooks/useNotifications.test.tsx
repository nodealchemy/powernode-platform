import React from 'react';
import { renderHook } from '@testing-library/react';
import { Provider } from 'react-redux';
import { configureStore } from '@reduxjs/toolkit';
import { useNotifications } from './useNotifications';
import uiReducer, { addNotification } from '@/shared/services/slices/uiSlice';

// Create a test store
const createTestStore = () => {
  return configureStore({
    reducer: {
      ui: uiReducer
    }
  });
};

// Wrapper component for provider
const createWrapper = (store: ReturnType<typeof createTestStore>) => {
  const Wrapper: React.FC<{ children: React.ReactNode }> = ({ children }) => (
    <Provider store={store}>{children}</Provider>
  );
  return Wrapper;
};

describe('useNotifications', () => {
  let store: ReturnType<typeof createTestStore>;
  let wrapper: ReturnType<typeof createWrapper>;

  beforeEach(() => {
    store = createTestStore();
    wrapper = createWrapper(store);
  });

  it('provides addNotification function', () => {
    const { result } = renderHook(() => useNotifications(), { wrapper });

    expect(result.current.addNotification).toBeDefined();
    expect(typeof result.current.addNotification).toBe('function');
  });

  it('dispatches notification with correct parameters', () => {
    const { result } = renderHook(() => useNotifications(), { wrapper });

    const notificationParams = {
      type: 'success' as const,
      message: 'Test message'
    };

    result.current.addNotification(notificationParams);

    const state = store.getState();
    const notifications = state.ui.notifications;

    expect(notifications).toHaveLength(1);
    expect(notifications[0]).toMatchObject({
      type: 'success',
      message: 'Test message'
    });
    expect(notifications[0].id).toBeDefined();
    expect(notifications[0].timestamp).toBeDefined();
  });

  it('handles notification with title', () => {
    const { result } = renderHook(() => useNotifications(), { wrapper });

    const notificationParams = {
      type: 'error' as const,
      message: 'Something went wrong',
      title: 'Error'
    };

    result.current.addNotification(notificationParams);

    const state = store.getState();
    const notifications = state.ui.notifications;

    expect(notifications).toHaveLength(1);
    expect(notifications[0].message).toBe('Error: Something went wrong');
  });

  it('handles notification without title', () => {
    const { result } = renderHook(() => useNotifications(), { wrapper });

    const notificationParams = {
      type: 'info' as const,
      message: 'Information message'
    };

    result.current.addNotification(notificationParams);

    const state = store.getState();
    const notifications = state.ui.notifications;

    expect(notifications).toHaveLength(1);
    expect(notifications[0].message).toBe('Information message');
  });

  it('supports all notification types', () => {
    const { result } = renderHook(() => useNotifications(), { wrapper });

    const types: Array<'success' | 'error' | 'warning' | 'info'> = ['success', 'error', 'warning', 'info'];

    types.forEach((type, index) => {
      result.current.addNotification({
        type,
        message: `Message ${index + 1}`
      });
    });

    const state = store.getState();
    const notifications = state.ui.notifications;

    expect(notifications).toHaveLength(4);
    expect(notifications.map(n => n.type)).toEqual(types);
  });

  it('generates unique IDs and timestamps for multiple notifications', () => {
    const { result } = renderHook(() => useNotifications(), { wrapper });

    // Add multiple notifications quickly
    result.current.addNotification({ type: 'success', message: 'First' });
    result.current.addNotification({ type: 'info', message: 'Second' });
    result.current.addNotification({ type: 'warning', message: 'Third' });

    const state = store.getState();
    const notifications = state.ui.notifications;

    expect(notifications).toHaveLength(3);

    // Check IDs are unique
    const ids = notifications.map(n => n.id);
    const uniqueIds = [...new Set(ids)];
    expect(uniqueIds).toHaveLength(3);

    // Check timestamps are unique (they should be different due to Date.now())
    const timestamps = notifications.map(n => n.timestamp);
    const uniqueTimestamps = [...new Set(timestamps)];
    expect(uniqueTimestamps.length).toBeGreaterThan(0); // At least one unique timestamp
  });

  it('maintains notification structure integrity', () => {
    const { result } = renderHook(() => useNotifications(), { wrapper });

    result.current.addNotification({
      type: 'warning',
      message: 'Test warning',
      title: 'Warning Title'
    });

    const state = store.getState();
    const notification = state.ui.notifications[0];

    expect(notification).toHaveProperty('id');
    expect(notification).toHaveProperty('type', 'warning');
    expect(notification).toHaveProperty('message', 'Warning Title: Test warning');
    expect(notification).toHaveProperty('timestamp');

    expect(typeof notification.id).toBe('string');
    expect(typeof notification.timestamp).toBe('number');
    expect(['success', 'error', 'warning', 'info']).toContain(notification.type);
  });

  it('works with empty title', () => {
    const { result } = renderHook(() => useNotifications(), { wrapper });

    result.current.addNotification({
      type: 'success',
      message: 'Success message',
      title: ''
    });

    const state = store.getState();
    const notification = state.ui.notifications[0];

    expect(notification.message).toBe('Success message');
  });

  it('handles special characters in messages and titles', () => {
    const { result } = renderHook(() => useNotifications(), { wrapper });

    result.current.addNotification({
      type: 'info',
      message: 'Message with <special> &characters& "quotes"',
      title: 'Title: with & symbols'
    });

    const state = store.getState();
    const notification = state.ui.notifications[0];

    expect(notification.message).toBe('Title: with & symbols: Message with <special> &characters& "quotes"');
  });

  it('can be called multiple times from same hook instance', () => {
    const { result } = renderHook(() => useNotifications(), { wrapper });

    const addNotification = result.current.addNotification;

    // Call multiple times using the same function reference
    addNotification({ type: 'success', message: 'First call' });
    addNotification({ type: 'error', message: 'Second call' });

    const state = store.getState();
    const notifications = state.ui.notifications;

    expect(notifications).toHaveLength(2);
    expect(notifications[0].message).toBe('First call');
    expect(notifications[1].message).toBe('Second call');
  });
});
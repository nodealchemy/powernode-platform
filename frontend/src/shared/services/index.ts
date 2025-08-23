import { configureStore } from '@reduxjs/toolkit';
import authSlice from './slices/authSlice';
import uiSlice from './slices/uiSlice';
import subscriptionSlice from './slices/subscriptionSlice';

export const store = configureStore({
  reducer: {
    auth: authSlice,
    ui: uiSlice,
    subscription: subscriptionSlice,
  },
  middleware: (getDefaultMiddleware) =>
    getDefaultMiddleware({
      serializableCheck: {
        ignoredActions: ['persist/PERSIST', 'persist/REHYDRATE'],
      },
    }),
});

export type RootState = ReturnType<typeof store.getState>;
export type AppDispatch = typeof store.dispatch;

// Re-export store slices with specific exports to avoid collisions
export { default as authSlice } from './slices/authSlice';
export { default as uiSlice } from './slices/uiSlice';
export { default as subscriptionSlice } from './slices/subscriptionSlice';

// Export specific actions with prefixes to avoid collisions
export { 
  clearAuth, 
  forceTokenClear, 
  clearResendVerificationSuccess, 
  decrementResendCooldown,
  clearError as clearAuthError,  // Rename to avoid collision
  resendVerificationEmail,
  login,
  register,
  logout,
  startImpersonation,
  stopImpersonation,
  checkImpersonationStatus,
  getCurrentUser,
  refreshAccessToken
} from './slices/authSlice';

export {
  toggleSidebar,
  setSidebarOpen,
  toggleSidebarCollapse,
  setSidebarCollapsed,
  setTheme,
  setLoading,
  addNotification,
  removeNotification,
  clearNotifications
} from './slices/uiSlice';

export {
  setCurrentSubscription,
  setAvailablePlans,
  clearError as clearSubscriptionError,  // Rename to avoid collision
  fetchSubscriptions,
  fetchSubscription,
  createSubscription,
  updateSubscription,
  cancelSubscription
} from './slices/subscriptionSlice';
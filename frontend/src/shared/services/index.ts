import { configureStore } from '@reduxjs/toolkit';
import authSlice from '@/shared/services/slices/authSlice';
import uiSlice from '@/shared/services/slices/uiSlice';

export const store = configureStore({
  reducer: {
    auth: authSlice,
    ui: uiSlice,
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
export { default as authSlice } from '@/shared/services/slices/authSlice';
export { default as uiSlice } from '@/shared/services/slices/uiSlice';
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
} from '@/shared/services/slices/authSlice';

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
} from '@/shared/services/slices/uiSlice';


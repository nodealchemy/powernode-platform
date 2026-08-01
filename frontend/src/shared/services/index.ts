import { combineReducers, configureStore, type Reducer } from '@reduxjs/toolkit';
import authSlice from '@/shared/services/slices/authSlice';
import uiSlice from '@/shared/services/slices/uiSlice';
import configSlice from '@/shared/services/slices/configSlice';

// The reducers core owns. Extensions add theirs at load time via
// injectReducer() below; this map is the immutable base every rebuild starts
// from, so an injection can never drop a core slice.
const staticReducers = {
  auth: authSlice,
  ui: uiSlice,
  config: configSlice,
};

export const store = configureStore({
  reducer: staticReducers,
  middleware: (getDefaultMiddleware) =>
    getDefaultMiddleware({
      serializableCheck: {
        ignoredActions: ['persist/PERSIST', 'persist/REHYDRATE'],
      },
    }),
});

// ---------------------------------------------------------------------------
// Extension state seam
// ---------------------------------------------------------------------------
// Extensions compose into the platform through featureRegistry (routes, nav,
// settings tabs, channels, component slots). State was the one axis with no
// seam: an extension could define a Redux slice but had nowhere to register the
// reducer, so `state.<slice>` was permanently undefined and any selector
// reading it threw. This is not hypothetical — an extension shipped exactly
// that, a complete slice registered in no store, and it went unnoticed because
// nothing rendered the components that would have thrown.
//
// Ordering is already guaranteed by the loader: extension register() runs
// synchronously at module load (extensionLoader's eager glob) and runtime
// extensions are awaited in index.tsx, both BEFORE the first render — so a
// reducer injected from register() is present before anything selects it.
const injectedReducers: Record<string, Reducer> = {};

/**
 * Register an extension's reducer under `key`, rebuilding the store's reducer
 * from the static core set plus everything injected so far.
 *
 * Call from the extension's register(), beside its featureRegistry calls.
 * Idempotent: re-registering the same key is a no-op, so HMR and a
 * double-invoked register() cannot clobber live slice state.
 *
 * Core deliberately does not know which keys exist — it must not depend on any
 * extension. Type them from the extension side by augmenting ExtensionState.
 */
export function injectReducer(key: string, reducer: Reducer): void {
  if (Object.prototype.hasOwnProperty.call(injectedReducers, key)) return;

  injectedReducers[key] = reducer;
  store.replaceReducer(combineReducers({ ...staticReducers, ...injectedReducers }));
}

/** Keys injected so far — for diagnostics and tests, not for feature code. */
export function injectedReducerKeys(): string[] {
  return Object.keys(injectedReducers);
}

/**
 * Augmentable map of extension-owned state. Empty in core by design; an
 * extension declares its own slice via declaration merging:
 *
 *   declare module '@/shared/services' {
 *     interface ExtensionState { subscription: SubscriptionState }
 *   }
 */
// eslint-disable-next-line @typescript-eslint/no-empty-interface
export interface ExtensionState {}

// Partial<> is deliberate and load-bearing: extension slices are absent until
// their register() runs, and a runtime extension that exceeds the boot timeout
// in index.tsx registers AFTER the first render. Typing these as always-present
// would let a selector assert a slice that genuinely is not there yet — which
// is the exact bug this seam exists to prevent. The type tells the truth, so
// consumers are forced to read defensively.
export type RootState = ReturnType<typeof store.getState> & Partial<ExtensionState>;
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

export { default as configSlice } from '@/shared/services/slices/configSlice';
export { fetchPlatformConfig } from '@/shared/services/slices/configSlice';


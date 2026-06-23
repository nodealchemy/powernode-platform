import React, { useEffect } from 'react';
import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import { Provider, useDispatch, useSelector } from 'react-redux';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { RootState, AppDispatch } from '@/shared/services';
import { store } from '@/shared/services';
import { getCurrentUser, refreshAccessToken, clearAuth, forceTokenClear, checkImpersonationStatus } from '@/shared/services/slices/authSlice';
import { isTokenInvalidError, isValidTokenFormat } from '@/shared/utils/tokenUtils';
import { loadAllExtensions } from '@/shared/services/extensionLoader';
import { featureRegistry } from '@/shared/services/featureRegistry';
import { registerCoreEntities } from '@/shared/entity/registerCoreEntities';

// Theme Provider
import { ThemeProvider } from '@/shared/hooks/ThemeContext';
import { BreadcrumbProvider } from '@/shared/hooks/BreadcrumbContext';
import { FooterProvider } from '@/shared/contexts/FooterContext';

// Components
import { ProtectedRoute } from '@/shared/components/ui/ProtectedRoute';
import { PublicRoute } from '@/shared/components/ui/PublicRoute';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { NotificationContainer } from '@/shared/components/ui/NotificationContainer';

// Pages
import { LoginPage } from '@/pages/public/LoginPage';
// Registration is an extension feature. The owning extension registers a public
// '/register' route via featureRegistry.registerPublicRoutes(...), which renders
// first (see the public-routes block below) and wins by first-match. This core
// fallback is used only when no extension provides registration.
const RegisterPage: React.FC = () =>
  React.createElement(
    'div',
    { className: 'p-8 text-center text-theme-secondary' },
    'Registration is available in Business edition.'
  );
import { DashboardPage } from '@/pages/app/DashboardPage';
import { ForgotPasswordPage } from '@/pages/public/ForgotPasswordPage';
import { ResetPasswordPage } from '@/pages/public/ResetPasswordPage';
import { VerifyEmailPage } from '@/pages/public/VerifyEmailPage';
import { UnauthorizedPage } from '@/pages/public/UnauthorizedPage';
import { WelcomePage } from '@/pages/public/WelcomePage';
import { AcceptInvitationPage } from '@/pages/public/AcceptInvitationPage';
import { PageViewPage } from '@/pages/public/PageViewPage';
import { McpOAuthCallbackPage } from '@/pages/public/oauth/McpOAuthCallbackPage';
import { OAuthConsentPage } from '@/pages/public/oauth/OAuthConsentPage';
import { StatusPage } from '@/pages/public/StatusPage';
import { ApprovalResponsePage } from '@/features/devops/pipelines/pages/ApprovalResponsePage';
import { DetachedChatPage } from '@/features/ai/chat/pages/DetachedChatPage';
const ProvisioningPage = React.lazy(() => import('@/pages/ProvisioningPage'));
const SetupWizard = React.lazy(() =>
  import('@/features/setup/SetupWizard').then((m) => ({ default: m.SetupWizard }))
);
import apiClient from '@/shared/services/apiClient';
import { logger } from '@/shared/utils/logger';

interface OnboardingStatusResponse {
  data?: { completed?: boolean; has_credentials?: boolean };
  completed?: boolean;
  has_credentials?: boolean;
}

/**
 * OnboardingGate — wraps protected routes that depend on a configured provider.
 *
 * When the operator has not yet completed BYOC onboarding (no provider creds and
 * no `account.metadata.onboarding_completed_at` stamp), redirect to /onboarding.
 *
 * Failures from `GET /api/v1/onboarding/status` are non-fatal — the gate falls
 * through to the wrapped children so the platform stays usable when Slice C is
 * absent or down. The check is account-level state and only runs on mount.
 */
const OnboardingGate: React.FC<{ children: React.ReactElement }> = ({ children }) => {
  const [status, setStatus] = React.useState<'unknown' | 'ok' | 'redirect'>('unknown');

  React.useEffect(() => {
    let cancelled = false;
    const check = async () => {
      try {
        const response = await apiClient.get<OnboardingStatusResponse>('/onboarding/status');
        const envelope = response.data ?? {};
        const inner = envelope.data ?? envelope;
        const complete = Boolean(inner.completed) || Boolean(inner.has_credentials);
        if (!cancelled) setStatus(complete ? 'ok' : 'redirect');
      } catch (err) {
        // Endpoint absent (M2 not yet shipped) or transient failure — fail open
        // so the user can still reach the app.
        logger.debug('OnboardingGate: status check failed; falling through', {
          error: err instanceof Error ? err.message : String(err),
        });
        if (!cancelled) setStatus('ok');
      }
    };
    void check();
    return () => {
      cancelled = true;
    };
  }, []);

  if (status === 'unknown') {
    return <LoadingSpinner message="Checking setup…" />;
  }
  if (status === 'redirect') {
    return <Navigate to="/setup" replace />;
  }
  return children;
};

import './App.css';
import '@/assets/styles/themes.css';
import '@/assets/styles/public-theme.css';
import '@/assets/styles/deprecated-css-override.css';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30_000,
      retry: 1,
      refetchOnWindowFocus: false,
    },
  },
});

// Register core object types with the entity-reference registry once, at module
// import time — before <Router> renders — so <EntityLink>/<EntityReferenceHost>
// can resolve them. Mirrors how extensions register from their register() at
// import time (extensionLoader.ts). Idempotent: re-registration overwrites by
// type. Explicit call (not a side-effect import) keeps the wiring discoverable.
registerCoreEntities();

const AppContent: React.FC = () => {
  const dispatch = useDispatch<AppDispatch>();
  const { isAuthenticated, access_token, user } = useSelector((state: RootState) => state.auth);
  const [initializing, setInitializing] = React.useState(true);
  const [showAuthFallback, setShowAuthFallback] = React.useState(false);
  const initializingRef = React.useRef(false); // Prevent double initialization

  // Extension registration happens synchronously at module import time
  // (see frontend/src/shared/services/extensionLoader.ts). By the time
  // this component renders, featureRegistry is already populated, so
  // there's no need to gate route resolution or subscribe for re-renders.
  // The loadAllExtensions() call below is a backward-compat no-op kept
  // in case future async loading is re-introduced.
  useEffect(() => {
    loadAllExtensions().catch(() => {
      // Extension loading failure is non-fatal
    });
  }, []);

  // Auth initialization with proper dependencies to prevent double execution
  useEffect(() => {
    // Prevent double initialization
    if (initializingRef.current) {
      return;
    }

    initializingRef.current = true;

    // Try to restore user session if we have a token
    const initializeAuth = async () => {
      // CRITICAL: If user is already loaded (e.g., from login), skip initialization
      if (user && access_token) {
        // User already authenticated and loaded, complete initialization immediately
        setInitializing(false);
        initializingRef.current = false;
        return;
      }

      // Starting auth initialization
      // Set a timeout to prevent infinite loading
      const timeoutId = setTimeout(() => {
        setShowAuthFallback(true);
      }, 5000); // 5 second timeout, then show fallback

      try {

        // Validate token format if we have one in memory (e.g., from a previous session's Redux persist)
        if (access_token && !isValidTokenFormat(access_token)) {
          dispatch(forceTokenClear());
          // Continue to check impersonation token instead of returning early
        }

        // Check for impersonation first, even if regular tokens are invalid
        const impersonationToken = localStorage.getItem('impersonationToken');

        if (impersonationToken || !user) {
          
          // PRIORITY: If we have an impersonation token, validate it first
          if (impersonationToken) {
            try {
              const impersonationData = await dispatch(checkImpersonationStatus()).unwrap();
              
              if (impersonationData && impersonationData.valid) {
                return; // Skip regular authentication entirely
              } else {
                localStorage.removeItem('impersonationToken');
              }
            } catch (impersonationError) {
              localStorage.removeItem('impersonationToken');
            }
          }
          
          // If no valid impersonation session, proceed with regular authentication.
          // When we have an access_token in memory, try /auth/me directly.
          // Otherwise skip straight to refresh (avoids a guaranteed 401 on every page load).
          if (access_token) {
            try {
              await dispatch(getCurrentUser(true)).unwrap();
              return; // Success — session restored
            } catch (error) {
              if (isTokenInvalidError(error)) {
                dispatch(forceTokenClear());
                return;
              }
              // Token expired — fall through to refresh below
            }
          }

          // Refresh the access token via HttpOnly cookie
          try {
            await dispatch(refreshAccessToken()).unwrap();

            // After refresh, check for impersonation session again
            const impersonationToken = localStorage.getItem('impersonationToken');
            if (impersonationToken) {
              try {
                const impersonationData = await dispatch(checkImpersonationStatus()).unwrap();
                if (impersonationData && impersonationData.valid) {
                  return; // Skip regular user fetch
                } else {
                  localStorage.removeItem('impersonationToken');
                }
              } catch (impersonationError) {
                localStorage.removeItem('impersonationToken');
              }
            }

            // If no valid impersonation, get regular user
            await dispatch(getCurrentUser(true)).unwrap();
          } catch (refreshError) {
            // Check if this is a token invalidity error
            if (isTokenInvalidError(refreshError)) {
              dispatch(forceTokenClear());
            } else {
              // No valid refresh cookie or refresh failed — user needs to log in
              dispatch(clearAuth());
            }
          }
        }
      } catch (error) {
        dispatch(clearAuth());
      } finally {
        clearTimeout(timeoutId);
        setInitializing(false);
        initializingRef.current = false; // Reset initialization flag
      }
    };

    void initializeAuth();
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dispatch]); // Remove access_token, refresh_token, user to prevent infinite loop

  const handleAuthFallback = () => {
    dispatch(clearAuth());
    setInitializing(false);
    initializingRef.current = false; // Reset initialization flag
  };

  if (initializing) {
    return (
      <LoadingSpinner 
        message={showAuthFallback ? "Having trouble loading..." : "Restoring your session..."}
        showAuthFallback={showAuthFallback}
        onAuthFallback={handleAuthFallback}
      />
    );
  }

  return (
    <Router>
      <div className="App bg-theme-background min-h-screen text-theme-primary">
        <Routes>
          {/* Extension-registered public marketing routes (rendered first; fall through to App.tsx defaults below when the marketing extension is absent or hasn't yet registered a given path) */}
          {featureRegistry.getPublicRoutes().map((route) => (
            <Route
              key={`public:${route.path}`}
              path={route.path}
              element={
                <React.Suspense fallback={<LoadingSpinner message="Loading..." />}>
                  {React.createElement(route.component as React.ComponentType)}
                </React.Suspense>
              }
            />
          ))}

          {/* Public routes — /pricing is owned by the business extension's PricingPage */}
          <Route
            path="/login"
            element={
              <PublicRoute>
                <LoginPage />
              </PublicRoute>
            }
          />
          <Route
            path="/register"
            element={
              <PublicRoute>
                <React.Suspense fallback={<LoadingSpinner message="Loading..." />}>
                  <RegisterPage />
                </React.Suspense>
              </PublicRoute>
            }
          />
          <Route
            path="/forgot-password"
            element={
              <PublicRoute>
                <ForgotPasswordPage />
              </PublicRoute>
            }
          />
          <Route
            path="/reset-password/:token"
            element={
              <PublicRoute>
                <ResetPasswordPage />
              </PublicRoute>
            }
          />
          <Route
            path="/accept-invitation/:token"
            element={
              <PublicRoute>
                <AcceptInvitationPage />
              </PublicRoute>
            }
          />

          {/* OAuth consent page — must be before /app/* catch-all */}
          <Route
            path="/app/oauth/authorize"
            element={<OAuthConsentPage />}
          />

          {/* First-run setup wizard (PUBLIC, token-gated admin step). Registered
              before /app/* and outside ProtectedRoute so it renders standalone
              before any user exists. Reached via the one-time setup URL printed
              to the service console at first boot; self-disables once an admin exists. */}
          <Route
            path="/setup"
            element={
              <React.Suspense fallback={<LoadingSpinner message="Loading setup…" />}>
                <SetupWizard />
              </React.Suspense>
            }
          />

          {/* Legacy onboarding path — unified into the registry-driven /setup
              wizard (which now drives the provider steps too). Redirect any stale
              links/redirects there. */}
          <Route path="/app/onboarding" element={<Navigate to="/setup" replace />} />

          {/* AI provisioning chat (System extension). Registered before
              /app/* so it renders standalone with its own layout. */}
          <Route
            path="/app/system/provision"
            element={
              <ProtectedRoute requireEmailVerification>
                <OnboardingGate>
                  <React.Suspense fallback={<LoadingSpinner message="Loading provisioning…" />}>
                    <ProvisioningPage />
                  </React.Suspense>
                </OnboardingGate>
              </ProtectedRoute>
            }
          />

          {/* Legacy dashboard redirect */}
          <Route
            path="/dashboard/*"
            element={<Navigate to="/app" replace />}
          />
          <Route
            path="/app/*"
            element={
              <ProtectedRoute requireEmailVerification>
                <OnboardingGate>
                  <DashboardPage />
                </OnboardingGate>
              </ProtectedRoute>
            }
          />

          {/* Email verification route (authenticated but not verified) */}
          <Route
            path="/verify-email"
            element={
              <ProtectedRoute>
                <VerifyEmailPage />
              </ProtectedRoute>
            }
          />

          {/* Unauthorized page */}
          <Route path="/unauthorized" element={<UnauthorizedPage />} />

          {/* Welcome page route */}
          <Route
            path="/welcome"
            element={
              <PublicRoute>
                <WelcomePage />
              </PublicRoute>
            }
          />

          {/* Public page viewing route */}
          <Route
            path="/pages/:slug"
            element={<PageViewPage />}
          />

          {/* Public Status Page */}
          <Route
            path="/status"
            element={<StatusPage />}
          />

          {/* CI/CD Pipeline Approval Routes (public, token-based auth) */}
          <Route
            path="/ci-cd/approve/:token"
            element={<ApprovalResponsePage />}
          />
          <Route
            path="/ci-cd/reject/:token"
            element={<ApprovalResponsePage />}
          />

          {/* Detached chat window (popup or new tab) */}
          <Route
            path="/chat/detached"
            element={
              <ProtectedRoute>
                <DetachedChatPage />
              </ProtectedRoute>
            }
          />

          {/* OAuth callback routes */}
          <Route
            path="/oauth/mcp/callback"
            element={<McpOAuthCallbackPage />}
          />

          {/* Default redirects */}
          <Route
            path="/"
            element={
              isAuthenticated ? (
                <Navigate to="/app" replace />
              ) : (
                <Navigate to="/welcome" replace />
              )
            }
          />
          <Route
            path="/dashboard"
            element={<Navigate to="/app" replace />}
          />

          {/* Catch all route */}
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
        
        {/* Global notification container */}
        <NotificationContainer />
      </div>
    </Router>
  );
};

const App: React.FC = () => {
  return (
    <QueryClientProvider client={queryClient}>
      <Provider store={store}>
        <ThemeProvider>
          <BreadcrumbProvider>
            <FooterProvider>
              <AppContent />
            </FooterProvider>
          </BreadcrumbProvider>
        </ThemeProvider>
      </Provider>
    </QueryClientProvider>
  );
};

export default App;

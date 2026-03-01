import React, { useEffect } from 'react';
import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import { Provider, useDispatch, useSelector } from 'react-redux';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { RootState, AppDispatch } from '@/shared/services';
import { store } from '@/shared/services';
import { getCurrentUser, refreshAccessToken, clearAuth, forceTokenClear, checkImpersonationStatus } from '@/shared/services/slices/authSlice';
import { isTokenInvalidError, isValidTokenFormat } from '@/shared/utils/tokenUtils';
import { loadAllExtensions } from '@/shared/services/extensionLoader';

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
// Registration and plan selection are enterprise features, lazy-loaded when available
const RegisterPage = (typeof __EXTENSIONS__ !== 'undefined' && __EXTENSIONS__.includes('enterprise'))
  ? React.lazy(() => import('@ext/enterprise/pages/public/RegisterPage'))
  : () => React.createElement('div', { className: 'p-8 text-center text-theme-secondary' }, 'Registration is available in Enterprise edition.');
const PlanSelectionPage = (typeof __EXTENSIONS__ !== 'undefined' && __EXTENSIONS__.includes('enterprise'))
  ? React.lazy(() => import('@ext/enterprise/pages/public/PlanSelectionPage'))
  : () => React.createElement('div', { className: 'p-8 text-center text-theme-secondary' }, 'Plan selection is available in Enterprise edition.');
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
import { ApprovalResponsePage as AiWorkflowApprovalResponsePage } from '@/features/ai/workflows/pages/ApprovalResponsePage';
import { DetachedChatPage } from '@/features/ai/chat/pages/DetachedChatPage';

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

const AppContent: React.FC = () => {
  const dispatch = useDispatch<AppDispatch>();
  const { isAuthenticated, access_token, user } = useSelector((state: RootState) => state.auth);
  const [initializing, setInitializing] = React.useState(true);
  const [showAuthFallback, setShowAuthFallback] = React.useState(false);
  const initializingRef = React.useRef(false); // Prevent double initialization

  // Load all discovered extensions
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
          {/* Public routes */}
          <Route
            path="/plans"
            element={
              <PublicRoute>
                <React.Suspense fallback={<LoadingSpinner message="Loading..." />}>
                  <PlanSelectionPage />
                </React.Suspense>
              </PublicRoute>
            }
          />
          <Route
            path="/pricing"
            element={<Navigate to="/plans" replace />}
          />
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

          {/* Legacy dashboard redirect */}
          <Route
            path="/dashboard/*"
            element={<Navigate to="/app" replace />}
          />
          <Route
            path="/app/*"
            element={
              <ProtectedRoute requireEmailVerification>
                <DashboardPage />
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

          {/* AI Workflow Approval Routes (public, token-based auth) */}
          <Route
            path="/ai-workflows/approve/:token"
            element={<AiWorkflowApprovalResponsePage />}
          />
          <Route
            path="/ai-workflows/reject/:token"
            element={<AiWorkflowApprovalResponsePage />}
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

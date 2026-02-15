import React, { useEffect } from 'react';
import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import { Provider, useDispatch, useSelector } from 'react-redux';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { RootState, AppDispatch } from '@/shared/services';
import { store } from '@/shared/services';
import { getCurrentUser, refreshAccessToken, clearAuth, forceTokenClear, checkImpersonationStatus } from '@/shared/services/slices/authSlice';
import { fetchPlatformConfig } from '@/shared/services/slices/configSlice';
import { isTokenInvalidError, isValidTokenFormat } from '@/shared/utils/tokenUtils';

// Theme Provider
import { ThemeProvider } from '@/shared/hooks/ThemeContext';
import { BreadcrumbProvider } from '@/shared/hooks/BreadcrumbContext';
import { FooterProvider } from '@/shared/contexts/FooterContext';

// React Query client
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: 1,
      staleTime: 30_000,
      refetchOnWindowFocus: false,
    },
  },
});

// Components
import { ProtectedRoute } from '@/shared/components/ui/ProtectedRoute';
import { PublicRoute } from '@/shared/components/ui/PublicRoute';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { NotificationContainer } from '@/shared/components/ui/NotificationContainer';

// Pages
import { LoginPage } from '@/pages/public/LoginPage';
import { DashboardPage } from '@/pages/app/DashboardPage';
import { ForgotPasswordPage } from '@/pages/public/ForgotPasswordPage';
import { ResetPasswordPage } from '@/pages/public/ResetPasswordPage';
import { VerifyEmailPage } from '@/pages/public/VerifyEmailPage';
import { UnauthorizedPage } from '@/pages/public/UnauthorizedPage';
import { WelcomePage } from '@/pages/public/WelcomePage';
import { AcceptInvitationPage } from '@/pages/public/AcceptInvitationPage';
import { PageViewPage } from '@/pages/public/PageViewPage';
import { McpOAuthCallbackPage } from '@/pages/public/oauth/McpOAuthCallbackPage';
import { ApprovalResponsePage } from '@/features/devops/pipelines/pages/ApprovalResponsePage';
import { ApprovalResponsePage as AiWorkflowApprovalResponsePage } from '@/features/ai/workflows/pages/ApprovalResponsePage';
import { DetachedChatPage } from '@/features/ai/chat/pages/DetachedChatPage';

import './App.css';
import '@/assets/styles/themes.css';
import '@/assets/styles/public-theme.css';
import '@/assets/styles/deprecated-css-override.css';

const AppContent: React.FC = () => {
  const dispatch = useDispatch<AppDispatch>();
  const { isAuthenticated, access_token, refresh_token, user } = useSelector((state: RootState) => state.auth);
  const [initializing, setInitializing] = React.useState(true);
  const [showAuthFallback, setShowAuthFallback] = React.useState(false);
  const initializingRef = React.useRef(false); // Prevent double initialization

  // Auth initialization with proper dependencies to prevent double execution
  useEffect(() => {
    // Prevent double initialization
    if (initializingRef.current) {
      return;
    }

    initializingRef.current = true;

    // Try to restore user session if we have a token
    const initializeAuth = async () => {
      // Fetch platform config (enterprise state, feature flags) in parallel with auth
      dispatch(fetchPlatformConfig());

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

        // First, validate token format before attempting API calls
        if (access_token && !isValidTokenFormat(access_token)) {
          dispatch(forceTokenClear());
          // Continue to check impersonation token instead of returning early
        }

        if (refresh_token && !isValidTokenFormat(refresh_token)) {
          dispatch(forceTokenClear());
          // Continue to check impersonation token instead of returning early
        }

        // Check for impersonation first, even if regular tokens are invalid
        const impersonationToken = localStorage.getItem('impersonationToken');

        if (impersonationToken || (access_token && !user)) {
          
          // PRIORITY: If we have an impersonation token, validate it first
          if (impersonationToken) {
            try {
              const impersonationData = await dispatch(checkImpersonationStatus()).unwrap();
              
              if (impersonationData && impersonationData.valid) {
                return; // Skip regular authentication entirely
              } else {
                localStorage.removeItem('impersonationToken');
              }
            } catch (_error) {
              localStorage.removeItem('impersonationToken');
            }
          }
          
          // If no valid impersonation session, proceed with regular authentication
          try {
            await dispatch(getCurrentUser(true)).unwrap(); // silentAuth = true during initialization
          } catch (error) {
            
            // Check if this error indicates invalid tokens that should be cleared immediately
            if (isTokenInvalidError(error)) {
              dispatch(forceTokenClear());
              return;
            }
            
            // If that fails, try to refresh the access token
            if (refresh_token) {
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
                  } catch (_error) {
                    localStorage.removeItem('impersonationToken');
                  }
                }
                
                // If no valid impersonation, get regular user
                await dispatch(getCurrentUser(true)).unwrap(); // silentAuth = true during initialization
              } catch (refreshError) {
                // Check if this is a token invalidity error
                if (isTokenInvalidError(refreshError)) {
                  dispatch(forceTokenClear());
                } else {
                  // Clear all auth data if both attempts fail
                  dispatch(clearAuth());
                }
              }
            } else {
              // No refresh token available, clear auth data
              dispatch(clearAuth());
            }
          }
        }
      } catch (_error) {
        dispatch(clearAuth());
      } finally {
        clearTimeout(timeoutId);
        setInitializing(false);
        initializingRef.current = false; // Reset initialization flag
      }
    };

    void initializeAuth();
   
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
            element={<Navigate to="/login" replace />}
          />
          <Route
            path="/pricing"
            element={<Navigate to="/login" replace />}
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
            element={<Navigate to="/login" replace />}
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


          {/* DevOps Pipeline Approval Routes (public, token-based auth) */}
          <Route
            path="/devops/approve/:token"
            element={<ApprovalResponsePage />}
          />
          <Route
            path="/devops/reject/:token"
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

          {/* Detached Chat Window */}
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
    <Provider store={store}>
      <QueryClientProvider client={queryClient}>
        <ThemeProvider>
          <BreadcrumbProvider>
            <FooterProvider>
              <AppContent />
            </FooterProvider>
          </BreadcrumbProvider>
        </ThemeProvider>
      </QueryClientProvider>
    </Provider>
  );
};

export default App;

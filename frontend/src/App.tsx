import React, { useEffect } from 'react';
import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import { Provider } from 'react-redux';
import { store } from '@/shared/services';
import { useDispatch, useSelector } from 'react-redux';
import { RootState, AppDispatch } from '@/shared/services';
import { getCurrentUser, refreshAccessToken, clearAuth, forceTokenClear, checkImpersonationStatus } from '@/shared/services/slices/authSlice';
import { isTokenInvalidError, isValidJWTFormat } from '@/shared/utils/tokenUtils';

// Theme Provider
import { ThemeProvider } from '@/shared/hooks/ThemeContext';
import { BreadcrumbProvider } from '@/shared/hooks/BreadcrumbContext';

// Components
import { ProtectedRoute } from '@/shared/components/ui/ProtectedRoute';
import { PublicRoute } from '@/shared/components/ui/PublicRoute';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { NotificationContainer } from '@/shared/components/ui/NotificationContainer';

// Pages
import { LoginPage } from '@/pages/public/LoginPage';
import { RegisterPage } from '@/pages/public/RegisterPage';
import { PlanSelectionPage } from '@/pages/public/PlanSelectionPage';
import { DashboardPage } from '@/pages/app/DashboardPage';
import { ForgotPasswordPage } from '@/pages/public/ForgotPasswordPage';
import { ResetPasswordPage } from '@/pages/public/ResetPasswordPage';
import { VerifyEmailPage } from '@/pages/public/VerifyEmailPage';
import { UnauthorizedPage } from '@/pages/public/UnauthorizedPage';
import { WelcomePage } from '@/pages/public/WelcomePage';
import { AcceptInvitationPage } from '@/pages/public/AcceptInvitationPage';

import './App.css';
import '@/assets/styles/themes.css';

const AppContent: React.FC = () => {
  const dispatch = useDispatch<AppDispatch>();
  const { isAuthenticated, accessToken, refreshToken, user } = useSelector((state: RootState) => state.auth);
  const [initializing, setInitializing] = React.useState(true);
  const [showAuthFallback, setShowAuthFallback] = React.useState(false);

  useEffect(() => {
    // Try to restore user session if we have a token
    const initializeAuth = async () => {
      // Set a timeout to prevent infinite loading
      const timeoutId = setTimeout(() => {
        setShowAuthFallback(true);
      }, 5000); // 5 second timeout, then show fallback

      try {
        // First, validate token format before attempting API calls
        if (accessToken && !isValidJWTFormat(accessToken)) {
          dispatch(forceTokenClear());
          // Continue to check impersonation token instead of returning early
        }
        
        if (refreshToken && !isValidJWTFormat(refreshToken)) {
          dispatch(forceTokenClear());
          // Continue to check impersonation token instead of returning early
        }
        
        // Check for impersonation first, even if regular tokens are invalid
        const impersonationToken = localStorage.getItem('impersonationToken');
        
        if (impersonationToken || (accessToken && !user)) {
          // Check if there's an active impersonation session first
          
          
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
          
          // If no valid impersonation session, proceed with regular authentication
          try {
            await dispatch(getCurrentUser()).unwrap();
          } catch (error) {
            
            // Check if this error indicates invalid tokens that should be cleared immediately
            if (isTokenInvalidError(error)) {
              dispatch(forceTokenClear());
              return;
            }
            
            // If that fails, try to refresh the access token
            if (refreshToken) {
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
                await dispatch(getCurrentUser()).unwrap();
              } catch (refreshError: any) {
                
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
      } catch (error) {
        dispatch(clearAuth());
      } finally {
        clearTimeout(timeoutId);
        setInitializing(false);
      }
    };

    initializeAuth();
  }, [dispatch, accessToken, refreshToken, user]);

  const handleAuthFallback = () => {
    dispatch(clearAuth());
    setInitializing(false);
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
    <Router 
      future={{
        v7_startTransition: true,
        v7_relativeSplatPath: true,
      }}
    >
      <div className="App bg-theme-background min-h-screen text-theme-primary">
        <Routes>
          {/* Public routes */}
          <Route
            path="/plans"
            element={
              <PublicRoute>
                <PlanSelectionPage />
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
                <RegisterPage />
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

function App() {
  return (
    <Provider store={store}>
      <ThemeProvider>
        <BreadcrumbProvider>
          <AppContent />
        </BreadcrumbProvider>
      </ThemeProvider>
    </Provider>
  );
}

export default App;

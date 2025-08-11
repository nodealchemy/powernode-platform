import React, { useEffect } from 'react';
import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import { Provider } from 'react-redux';
import { store } from './store';
import { useDispatch, useSelector } from 'react-redux';
import { RootState, AppDispatch } from './store';
import { getCurrentUser, refreshAccessToken, clearAuth, forceTokenClear } from './store/slices/authSlice';
import { isTokenInvalidError, isValidJWTFormat } from './utils/tokenUtils';

// Theme Provider
import { ThemeProvider } from './contexts/ThemeContext';

// Components
import { ProtectedRoute } from './components/common/ProtectedRoute';
import { PublicRoute } from './components/common/PublicRoute';
import { LoadingSpinner } from './components/common/LoadingSpinner';

// Pages
import { LoginPage } from './pages/auth/LoginPage';
import { RegisterPage } from './pages/auth/RegisterPage';
import { PlanSelectionPage } from './pages/auth/PlanSelectionPage';
import { DashboardPage } from './pages/dashboard/DashboardPage';
import { ForgotPasswordPage } from './pages/auth/ForgotPasswordPage';
import { ResetPasswordPage } from './pages/auth/ResetPasswordPage';
import { VerifyEmailPage } from './pages/auth/VerifyEmailPage';
import { UnauthorizedPage } from './pages/auth/UnauthorizedPage';
import { WelcomePage } from './pages/WelcomePage';
import { AcceptInvitationPage } from './pages/auth/AcceptInvitationPage';

import './App.css';
import './styles/themes.css';

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
        console.warn('Authentication initialization timed out');
        setShowAuthFallback(true);
      }, 5000); // 5 second timeout, then show fallback

      try {
        // First, validate token format before attempting API calls
        if (accessToken && !isValidJWTFormat(accessToken)) {
          console.warn('Invalid access token format detected, clearing tokens');
          dispatch(forceTokenClear());
          return;
        }
        
        if (refreshToken && !isValidJWTFormat(refreshToken)) {
          console.warn('Invalid refresh token format detected, clearing tokens');
          dispatch(forceTokenClear());
          return;
        }
        
        if (accessToken && !user) {
          try {
            // First try to get current user with existing token
            await dispatch(getCurrentUser()).unwrap();
          } catch (error) {
            console.error('Failed to restore user session with access token:', error);
            
            // Check if this error indicates invalid tokens that should be cleared immediately
            if (isTokenInvalidError(error)) {
              console.log('Detected invalid token error, clearing all auth data');
              dispatch(forceTokenClear());
              return;
            }
            
            // If that fails, try to refresh the access token
            if (refreshToken) {
              try {
                await dispatch(refreshAccessToken()).unwrap();
                // After successful refresh, try to get user again
                await dispatch(getCurrentUser()).unwrap();
              } catch (refreshError: any) {
                console.error('Failed to refresh token and restore session:', refreshError);
                
                // Check if this is a token invalidity error
                if (isTokenInvalidError(refreshError)) {
                  console.log('Detected invalid token signatures during refresh, clearing all auth data');
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
        console.error('Unexpected error during auth initialization:', error);
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

          {/* Protected routes */}
          <Route
            path="/dashboard/*"
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
                <Navigate to="/dashboard" replace />
              ) : (
                <Navigate to="/welcome" replace />
              )
            }
          />

          {/* Catch all route */}
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </div>
    </Router>
  );
};

function App() {
  return (
    <Provider store={store}>
      <ThemeProvider>
        <AppContent />
      </ThemeProvider>
    </Provider>
  );
}

export default App;

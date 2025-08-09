import React, { useEffect } from 'react';
import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import { Provider } from 'react-redux';
import { store } from './store';
import { useDispatch, useSelector } from 'react-redux';
import { RootState, AppDispatch } from './store';
import { getCurrentUser } from './store/slices/authSlice';

// Components
import { ProtectedRoute } from './components/common/ProtectedRoute';
import { PublicRoute } from './components/common/PublicRoute';
import { LoadingSpinner } from './components/common/LoadingSpinner';
import { NotificationContainer } from './components/common/NotificationContainer';

// Pages
import { LoginPage } from './pages/auth/LoginPage';
import { RegisterPage } from './pages/auth/RegisterPage';
import { DashboardPage } from './pages/dashboard/DashboardPage';
import { ForgotPasswordPage } from './pages/auth/ForgotPasswordPage';
import { ResetPasswordPage } from './pages/auth/ResetPasswordPage';
import { VerifyEmailPage } from './pages/auth/VerifyEmailPage';
import { UnauthorizedPage } from './pages/auth/UnauthorizedPage';

import './App.css';

const AppContent: React.FC = () => {
  const dispatch = useDispatch<AppDispatch>();
  const { isAuthenticated, accessToken, user } = useSelector((state: RootState) => state.auth);
  const [initializing, setInitializing] = React.useState(true);

  useEffect(() => {
    // Try to restore user session if we have a token
    const initializeAuth = async () => {
      if (accessToken && !user) {
        try {
          await dispatch(getCurrentUser()).unwrap();
        } catch (error) {
          console.error('Failed to restore user session:', error);
        }
      }
      setInitializing(false);
    };

    initializeAuth();
  }, [dispatch, accessToken, user]);

  if (initializing) {
    return <LoadingSpinner />;
  }

  return (
    <Router 
      future={{
        v7_startTransition: true,
        v7_relativeSplatPath: true,
      }}
    >
      <div className="App">
        <NotificationContainer />
        <Routes>
          {/* Public routes */}
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

          {/* Default redirects */}
          <Route
            path="/"
            element={
              isAuthenticated ? (
                <Navigate to="/dashboard" replace />
              ) : (
                <Navigate to="/login" replace />
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
      <AppContent />
    </Provider>
  );
}

export default App;

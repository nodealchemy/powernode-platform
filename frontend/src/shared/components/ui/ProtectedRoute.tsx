import React, { useMemo } from 'react';
import { Navigate, useLocation } from 'react-router-dom';
import { useSelector, shallowEqual } from 'react-redux';
import { RootState } from '@/shared/services';
import { LoadingSpinner } from './LoadingSpinner';

interface ProtectedRouteProps {
  children: React.ReactNode;
  requiredPermissions?: string[];
  requireEmailVerification?: boolean;
  requireAdminAccess?: boolean;
}

// Memoize the entire component to prevent unnecessary re-renders
export const ProtectedRoute: React.FC<ProtectedRouteProps> = React.memo(({
  children,
  requiredPermissions = [],
  requireEmailVerification = false,
  requireAdminAccess = false,
}) => {
  const location = useLocation();

  // Use separate selectors with shallowEqual to prevent unnecessary re-renders
  const isAuthenticated = useSelector((state: RootState) => state.auth.isAuthenticated);
  const user = useSelector((state: RootState) => state.auth.user, shallowEqual);
  const isLoading = useSelector((state: RootState) => state.auth.isLoading);

  // Memoize the redirect state to prevent object recreation on every render
  const loginRedirectState = useMemo(() => {
    // Don't include state if already on login page to prevent loops
    return location.pathname === '/login' ? undefined : { from: location.pathname };
  }, [location.pathname]);

  // Show loading spinner while authentication state is being determined
  // CRITICAL: Wait for loading to complete before making redirect decisions
  // This prevents infinite loops when isAuthenticated=true but user is still being fetched
  if (isLoading || (isAuthenticated && !user)) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  // Check if user is authenticated (only after loading is complete)
  if (!isAuthenticated || !user) {
    return <Navigate to="/login" state={loginRedirectState} replace />;
  }

  // Check if email verification is required
  if (requireEmailVerification && !user.email_verified) {
    return <Navigate to="/verify-email" replace />;
  }

  // Permission-based access control
  if (requiredPermissions.length > 0) {
    const hasPermission = requiredPermissions.some(permission => 
      user.permissions?.includes(permission)
    );
    if (!hasPermission) {
      return <Navigate to="/unauthorized" replace />;
    }
  }

  // Admin access check using permissions
  if (requireAdminAccess) {
    const hasAdminAccess = user.permissions?.includes('admin.access') || 
                          user.permissions?.includes('system.admin');
    if (!hasAdminAccess) {
      return <Navigate to="/unauthorized" replace />;
    }
  }

  return <>{children}</>;
});

ProtectedRoute.displayName = 'ProtectedRoute';
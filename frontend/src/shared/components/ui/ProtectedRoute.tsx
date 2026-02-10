import React, { useMemo, useEffect, useState } from 'react';
import { Navigate, useLocation } from 'react-router-dom';
import { useSelector, shallowEqual } from 'react-redux';
import { RootState } from '@/shared/services';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';

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

  // Track if we've waited long enough for user data to load
  const [waitedForUser, setWaitedForUser] = useState(false);

  // If authenticated but no user, wait briefly then force redirect
  // This prevents infinite loading when there's a timing issue
  useEffect(() => {
    if (isAuthenticated && !user && !isLoading) {
      const timer = setTimeout(() => {
        setWaitedForUser(true);
      }, 500); // Wait 500ms for user data to populate
      return () => clearTimeout(timer);
    }
    // Reset when user becomes available
    if (user) {
      setWaitedForUser(false);
    }
  }, [isAuthenticated, user, isLoading]);

  // Memoize the redirect state to prevent object recreation on every render
  const loginRedirectState = useMemo(() => {
    // Don't include state if already on login page to prevent loops
    return location.pathname === '/login' ? undefined : { from: location.pathname };
  }, [location.pathname]);

  // Show loading spinner while authentication state is being determined
  // CRITICAL: Wait for loading to complete before making redirect decisions
  // But don't wait forever - if we've waited and still no user, redirect to login
  if (isLoading || (isAuthenticated && !user && !waitedForUser)) {
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
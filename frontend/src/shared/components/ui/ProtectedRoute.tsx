import React from 'react';
import { Navigate, useLocation } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';

interface ProtectedRouteProps {
  children: React.ReactNode;
  requiredPermissions?: string[];
  requireEmailVerification?: boolean;
  requireAdminAccess?: boolean;
}

export const ProtectedRoute: React.FC<ProtectedRouteProps> = ({
ProtectedRoute.displayName = 'ProtectedRoute';
  children,
  requiredPermissions = [],
  requireEmailVerification = false,
  requireAdminAccess = false,
}) => {
  const location = useLocation();
  const { isAuthenticated, user } = useSelector((state: RootState) => state.auth);

  // Check if user is authenticated
  if (!isAuthenticated || !user) {
    return <Navigate to="/login" state={{ from: location }} replace />;
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
};
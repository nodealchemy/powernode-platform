import React, { useEffect, useState } from 'react';
import { useSelector, useDispatch } from 'react-redux';
import { AlertCircle, RefreshCw, Shield, User } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { RootState, AppDispatch } from '@/shared/services';
import { refreshAccessToken, getCurrentUser } from '@/shared/services/slices/authSlice';
import { useAuth } from '@/shared/hooks/useAuth';
import { usePermissions } from '@/shared/hooks/usePermissions';

interface AuthenticationCheckProps {
  requiredPermissions?: string[];
  children: React.ReactNode;
  fallback?: React.ReactNode;
}

export const AuthenticationCheck: React.FC<AuthenticationCheckProps> = ({
  requiredPermissions = [],
  children,
  fallback
}) => {
  const dispatch = useDispatch<AppDispatch>();
  const { currentUser, isAuthenticated, isLoading } = useAuth();
  const { hasAnyPermission, hasPermission } = usePermissions();
  const [refreshing, setRefreshing] = useState(false);
  const [refreshAttempted, setRefreshAttempted] = useState(false);
  
  const authState = useSelector((state: RootState) => state.auth);
  
  // Check if user has required permissions
  const hasRequiredPermissions = requiredPermissions.length === 0 || 
    hasAnyPermission(requiredPermissions) ||
    hasPermission('system.admin') ||
    hasPermission('*.*');

  // Attempt token refresh if not authenticated but have tokens
  useEffect(() => {
    const attemptRefresh = async () => {
      if (!isAuthenticated && !refreshAttempted && authState.refresh_token) {
        try {
          setRefreshing(true);
          setRefreshAttempted(true);
          await dispatch(refreshAccessToken()).unwrap();
          // After successful token refresh, get updated user data
          await dispatch(getCurrentUser(false)).unwrap();
        } catch {
          // Token refresh failed, user will see authentication required message
        } finally{
          setRefreshing(false);
        }
      }
    };

    attemptRefresh();
  }, [dispatch, isAuthenticated, refreshAttempted, authState.refresh_token]);

  const handleManualRefresh = async () => {
    try {
      setRefreshing(true);
      await dispatch(refreshAccessToken()).unwrap();
      await dispatch(getCurrentUser(false)).unwrap();
    } catch {
      console.error('Manual refresh failed:', error);
    } finally {
      setRefreshing(false);
    }
  };

  const handleReload = () => {
    window.location.reload();
  };

  // Show loading while refreshing or initial loading
  if (isLoading || refreshing) {
    return (
      <div className="flex items-center justify-center p-8">
        <LoadingSpinner size="lg" message="Verifying authentication..." />
      </div>
    );
  }

  // Show authentication error if not authenticated
  if (!isAuthenticated) {
    const defaultFallback = (
      <Card className="p-6 border-theme-error bg-theme-error bg-opacity-5">
        <div className="flex items-start space-x-3">
          <AlertCircle className="h-6 w-6 text-theme-error flex-shrink-0 mt-1" />
          <div className="flex-1">
            <h3 className="text-lg font-semibold text-theme-error mb-2">
              Authentication Required
            </h3>
            <p className="text-theme-tertiary mb-4">
              Your session has expired or authentication failed. Please sign in again to access AI features.
            </p>
            <div className="flex gap-3">
              <Button
                onClick={handleManualRefresh}
                variant="primary"
                disabled={refreshing}
              >
                <RefreshCw className="w-4 h-4 mr-2" />
                {refreshing ? 'Refreshing...' : 'Refresh Session'}
              </Button>
              <Button
                onClick={handleReload}
                variant="secondary"
                disabled={refreshing}
              >
                Reload Page
              </Button>
            </div>
          </div>
        </div>
      </Card>
    );

    return (fallback || defaultFallback) as React.ReactElement;
  }

  // Show permissions error if authenticated but missing permissions
  if (!hasRequiredPermissions) {
    const defaultPermissionsFallback = (
      <Card className="p-6 border-theme-warning bg-theme-warning bg-opacity-5">
        <div className="flex items-start space-x-3">
          <Shield className="h-6 w-6 text-theme-warning flex-shrink-0 mt-1" />
          <div className="flex-1">
            <h3 className="text-lg font-semibold text-theme-warning mb-2">
              Insufficient Permissions
            </h3>
            <p className="text-theme-tertiary mb-3">
              You need additional permissions to access this AI feature.
            </p>
            
            {/* Show user info */}
            <div className="mb-4 p-3 bg-theme-surface rounded-lg">
              <div className="flex items-center space-x-2 mb-2">
                <User className="h-4 w-4 text-theme-secondary" />
                <span className="text-sm font-medium text-theme-primary">
                  {currentUser?.name}
                </span>
                <span className="text-sm text-theme-tertiary">({currentUser?.email})</span>
              </div>
              
              <div className="mb-2">
                <span className="text-sm font-medium text-theme-secondary mr-2">Current roles:</span>
                <div className="flex flex-wrap gap-1">
                  {currentUser?.roles?.map(role => (
                    <Badge key={role} variant="secondary" size="sm">{role}</Badge>
                  ))}
                </div>
              </div>
              
              <div>
                <span className="text-sm font-medium text-theme-secondary mr-2">Required permissions:</span>
                <div className="flex flex-wrap gap-1">
                  {requiredPermissions.map(permission => (
                    <Badge key={permission} variant="outline" size="sm">{permission}</Badge>
                  ))}
                </div>
              </div>
            </div>
            
            <p className="text-sm text-theme-tertiary">
              Contact your system administrator to grant the necessary permissions for AI features.
            </p>
          </div>
        </div>
      </Card>
    );

    return (fallback || defaultPermissionsFallback) as React.ReactElement;
  }

  // All checks passed, render children
  return <>{children}</>;
};
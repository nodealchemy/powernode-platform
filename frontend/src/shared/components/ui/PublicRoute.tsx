import React from 'react';
import { Navigate } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';

interface PublicRouteProps {
  children: React.ReactNode;
  redirectTo?: string;
}

export const PublicRoute: React.FC<PublicRouteProps> = ({
  children,
  redirectTo = '/app',
}) => {
  const { isAuthenticated } = useSelector((state: RootState) => state.auth);

  // If user is authenticated, redirect to protected area
  if (isAuthenticated) {
    return <Navigate to={redirectTo} replace />;
  }

  return <>{children}</>;
};
// Admin Settings - Rate Limiting Tab Page
import React from 'react';
import { useSelector } from 'react-redux';
import { Navigate } from 'react-router-dom';
import { RateLimitingSettings } from '@/features/admin/components/settings/RateLimitingSettings';
import { RootState } from '@/shared/services';
import { hasPermissions } from '@/shared/utils/permissionUtils';

const AdminSettingsRateLimitingTabPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  
  // Check if user has rate limiting settings permission
  const canManageRateLimiting = hasPermissions(user, ['admin.settings.security']);
  
  // Redirect if user doesn't have permission
  if (!canManageRateLimiting) {
    return <Navigate to="/app/admin/settings" replace />;
  }

  return <RateLimitingSettings />;
};

export default AdminSettingsRateLimitingTabPage;
import React from 'react';
import { useSelector } from 'react-redux';
import { Navigate } from 'react-router-dom';
import { ReverseProxyConfiguration } from '@/features/admin/components/settings/ReverseProxyConfiguration';
import { RootState } from '@/shared/services';
import { hasPermissions } from '@/shared/utils/permissionUtils';

export const AdminSettingsReverseProxyTabPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  
  // Check if user has reverse proxy settings permission
  const canManageReverseProxy = hasPermissions(user, ['admin.settings.edit']);
  
  // Redirect if user doesn't have permission
  if (!canManageReverseProxy) {
    return <Navigate to="/app/admin/settings" replace />;
  }

  return (
    <div className="bg-theme-surface rounded-lg border border-theme">
      <div className="p-6">
        <ReverseProxyConfiguration />
      </div>
    </div>
  );
};

export default AdminSettingsReverseProxyTabPage;
import React from 'react';
import { useSelector } from 'react-redux';
import { Navigate } from 'react-router-dom';
import { EmailConfiguration } from '@/features/admin/components/settings/EmailConfiguration';
import { RootState } from '@/shared/services';
import { hasPermissions } from '@/shared/utils/permissionUtils';

export const AdminSettingsEmailTabPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  
  // Check if user has email settings permission
  const canManageEmailSettings = hasPermissions(user, ['admin.settings.email']);
  
  // Redirect if user doesn't have permission
  if (!canManageEmailSettings) {
    return <Navigate to="/app/admin/settings" replace />;
  }

  return (
    <div className="bg-theme-surface rounded-lg border border-theme">
      <div className="p-6">
        <EmailConfiguration />
      </div>
    </div>
  );
};

export default AdminSettingsEmailTabPage;
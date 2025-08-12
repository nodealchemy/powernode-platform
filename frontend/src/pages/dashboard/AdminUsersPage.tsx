import React from 'react';
import { useSelector } from 'react-redux';
import { Navigate } from 'react-router-dom';
import { RootState } from '../../store';
import { SystemUserManagement } from '../../components/admin/SystemUserManagement';
import { Breadcrumb } from '../../components/ui/Breadcrumb';
import { hasAdminAccess } from '../../utils/permissionUtils';

export const AdminUsersPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const isAdmin = hasAdminAccess(user);

  // Redirect non-admins to dashboard
  if (!isAdmin) {
    return <Navigate to="/dashboard" replace />;
  }

  const breadcrumbItems = [
    { label: 'Dashboard', path: '/dashboard', icon: '🏠' },
    { label: 'Admin', path: '/dashboard/admin', icon: '⚙️' },
    { label: 'Users', icon: '👥' }
  ];

  return (
    <div className="space-y-6">
      <div>
        <Breadcrumb items={breadcrumbItems} className="mb-4" />
        <h1 className="text-2xl font-bold text-theme-primary">System Users</h1>
        <p className="text-theme-secondary mt-1">
          Manage all users across the entire platform. Admin access required.
        </p>
      </div>

      <SystemUserManagement />
    </div>
  );
};

export default AdminUsersPage;
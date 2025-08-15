import React from 'react';
import { useSelector } from 'react-redux';
import { Navigate } from 'react-router-dom';
import { RootState } from '../../store';
import { SystemUserManagement } from '../../components/admin/SystemUserManagement';
import { PageContainer } from '../../components/layout/PageContainer';
import { hasAdminAccess } from '../../utils/permissionUtils';

export const AdminUsersPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const isAdmin = hasAdminAccess(user);

  // Redirect non-admins to dashboard
  if (!isAdmin) {
    return <Navigate to="/dashboard" replace />;
  }

  const breadcrumbs = [
    { label: 'Dashboard', href: '/dashboard', icon: '🏠' },
    { label: 'Admin', href: '/dashboard/admin', icon: '⚙️' },
    { label: 'System Users', icon: '👥' }
  ];

  return (
    <PageContainer
      title="System Users"
      description="Manage all users across the entire platform. Admin access required."
      breadcrumbs={breadcrumbs}
    >
      <SystemUserManagement />
    </PageContainer>
  );
};

// No default export - use named export only
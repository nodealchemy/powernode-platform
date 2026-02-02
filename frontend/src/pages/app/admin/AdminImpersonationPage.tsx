import React, { useState, useCallback } from 'react';
import { useSelector } from 'react-redux';
import { Navigate } from 'react-router-dom';
import { RootState } from '@/shared/services';
import { hasPermissions } from '@/shared/utils/permissionUtils';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { Button } from '@/shared/components/ui/Button';
import { Card } from '@/shared/components/ui/Card';
import { ImpersonationHistory } from '@/features/admin/components';
import { ImpersonateUserModal } from '@/features/admin/components/users/ImpersonateUserModal';
import {
  RefreshCw,
  UserCheck,
  History,
  AlertTriangle,
  Shield,
} from 'lucide-react';

export const AdminImpersonationPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const [showImpersonateModal, setShowImpersonateModal] = useState(false);
  const [refreshKey, setRefreshKey] = useState(0);

  // WebSocket for real-time updates
  usePageWebSocket({
    pageType: 'admin',
    onDataUpdate: () => {
      // Trigger data refresh if needed
    }
  });

  // Check permissions
  const canImpersonate = hasPermissions(user, ['admin.users.impersonate', 'admin.access']);
  const canViewHistory = hasPermissions(user, ['admin.impersonation.read', 'admin.access']);

  const handleRefresh = useCallback(() => {
    setRefreshKey(prev => prev + 1);
  }, []);

  if (!canViewHistory) {
    return <Navigate to="/app" replace />;
  }

  const pageActions: PageAction[] = [
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: handleRefresh,
      variant: 'secondary',
      icon: RefreshCw,
    },
    ...(canImpersonate ? [{
      id: 'impersonate',
      label: 'Impersonate User',
      onClick: () => setShowImpersonateModal(true),
      variant: 'primary' as const,
      icon: UserCheck,
    }] : []),
  ];

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Admin', href: '/app/admin' },
    { label: 'Impersonation' }
  ];

  return (
    <PageContainer
      title="User Impersonation"
      description="Impersonate users for support and debugging purposes"
      breadcrumbs={breadcrumbs}
      actions={pageActions}
    >
      {/* Warning Banner */}
      <Card className="mb-6 border-l-4 border-l-theme-warning">
        <div className="p-4 flex items-start gap-4">
          <AlertTriangle className="h-6 w-6 text-theme-warning flex-shrink-0 mt-0.5" />
          <div>
            <h3 className="font-medium text-theme-primary mb-1">
              Important Security Notice
            </h3>
            <p className="text-sm text-theme-secondary">
              Impersonation allows administrators to view the application as another user.
              All impersonation sessions are logged for security auditing. Sessions are limited
              to 8 hours and require a valid reason for compliance purposes.
            </p>
          </div>
        </div>
      </Card>

      {/* Quick Actions */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
        <Card className="p-6">
          <div className="flex items-center gap-4">
            <div className="p-3 bg-theme-interactive-primary/10 rounded-lg">
              <UserCheck className="h-6 w-6 text-theme-interactive-primary" />
            </div>
            <div>
              <h3 className="font-semibold text-theme-primary">Start Session</h3>
              <p className="text-sm text-theme-secondary">
                Begin impersonating a user
              </p>
            </div>
          </div>
          {canImpersonate && (
            <Button
              variant="outline"
              size="sm"
              className="mt-4 w-full"
              onClick={() => setShowImpersonateModal(true)}
            >
              Select User
            </Button>
          )}
        </Card>

        <Card className="p-6">
          <div className="flex items-center gap-4">
            <div className="p-3 bg-theme-success/10 rounded-lg">
              <History className="h-6 w-6 text-theme-success" />
            </div>
            <div>
              <h3 className="font-semibold text-theme-primary">Session History</h3>
              <p className="text-sm text-theme-secondary">
                View all past sessions
              </p>
            </div>
          </div>
          <Button
            variant="outline"
            size="sm"
            className="mt-4 w-full"
            onClick={() => {
              const historySection = document.getElementById('impersonation-history');
              historySection?.scrollIntoView({ behavior: 'smooth' });
            }}
          >
            View History
          </Button>
        </Card>

        <Card className="p-6">
          <div className="flex items-center gap-4">
            <div className="p-3 bg-theme-warning/10 rounded-lg">
              <Shield className="h-6 w-6 text-theme-warning" />
            </div>
            <div>
              <h3 className="font-semibold text-theme-primary">Audit Compliance</h3>
              <p className="text-sm text-theme-secondary">
                All actions are logged
              </p>
            </div>
          </div>
          <Button
            variant="outline"
            size="sm"
            className="mt-4 w-full"
            onClick={() => window.open('/app/audit-logs?category=impersonation', '_self')}
          >
            View Logs
          </Button>
        </Card>
      </div>

      {/* Impersonation History */}
      <div id="impersonation-history" key={refreshKey}>
        <ImpersonationHistory />
      </div>

      {/* Impersonate User Modal */}
      <ImpersonateUserModal
        isOpen={showImpersonateModal}
        onClose={() => setShowImpersonateModal(false)}
      />
    </PageContainer>
  );
};

export default AdminImpersonationPage;

import React, { useState, useCallback } from 'react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { UsersTable } from '@/features/account/users/components/users-table';

/** Administration → All Users: every account's users. */
const AdminUsersPage: React.FC = () => {
  const [actions, setActions] = useState<PageAction[]>([]);
  const handleActionsReady = useCallback((newActions: PageAction[]) => {
    setActions(newActions);
  }, []);

  return (
    <PageContainer
      title="All Users"
      description="Users across every account"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'Admin', href: '/app/admin/settings' },
        { label: 'Users' }
      ]}
      actions={actions}
    >
      <UsersTable scope="all" onActionsReady={handleActionsReady} />
    </PageContainer>
  );
};

export { AdminUsersPage };

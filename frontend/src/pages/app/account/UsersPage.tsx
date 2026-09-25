import React, { useState, useCallback } from 'react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { UsersTable } from '@/features/account/users/components/users-table';

interface UsersContentProps {
  onActionsReady?: (actions: PageAction[]) => void;
}

/** The current account's users. ProfilePage embeds this as its Users tab. */
export const UsersContent: React.FC<UsersContentProps> = ({ onActionsReady }) => (
  <UsersTable scope="account" onActionsReady={onActionsReady} />
);

const UsersPage: React.FC = () => {
  const [actions, setActions] = useState<PageAction[]>([]);
  const handleActionsReady = useCallback((newActions: PageAction[]) => {
    setActions(newActions);
  }, []);

  return (
    <PageContainer
      title="User Management"
      description="Manage the users in your account"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'Profile', href: '/app/profile' },
        { label: 'Users' }
      ]}
      actions={actions}
    >
      <UsersContent onActionsReady={handleActionsReady} />
    </PageContainer>
  );
};

export { UsersPage };

import React, { useState } from 'react';
import { Plus } from 'lucide-react';
import { useMutation } from '@tanstack/react-query';
import { Button } from '@/shared/components/ui/Button';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { getErrorMessage } from '@/shared/utils/apiErrors';
import { governanceApi } from '@/shared/services/ai/GovernanceApiService';
import { PolicyList } from '@/features/ai/audit/components/PolicyList';
import { ViolationList } from '@/features/ai/audit/components/ViolationList';
import { SecurityEventList } from '@/features/ai/audit/components/SecurityEventList';
import { useInvalidateCompliancePolicies } from '@/features/ai/audit/api/auditApi';
import { CreatePolicyModal, type CreatePolicyFormData } from './CreatePolicyModal';

const Section: React.FC<{ title: string; action?: React.ReactNode; children: React.ReactNode }> = ({
  title, action, children,
}) => (
  <section aria-label={title} className="space-y-3">
    <div className="flex items-center justify-between">
      <h3 className="text-base font-semibold text-theme-primary">{title}</h3>
      {action}
    </div>
    {children}
  </section>
);

/**
 * Control → Policies → Compliance rules: compliance policies (toggle, create), the
 * violations they raise (resolve) and the account's security events. Reads
 * need ai.governance.read (the route's gate); every write is offered only to
 * ai.governance.manage holders, the permission GovernanceController checks.
 */
export const ComplianceTab: React.FC = () => {
  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();
  const canManage = hasPermission('ai.governance.manage');
  const invalidatePolicies = useInvalidateCompliancePolicies();
  const [showCreate, setShowCreate] = useState(false);

  const createPolicy = useMutation({
    mutationFn: (data: CreatePolicyFormData) =>
      governanceApi.createPolicy({
        name: data.name,
        policy_type: data.policy_type,
        enforcement_level: data.enforcement_level,
        category: data.category || undefined,
        description: data.description || undefined,
      }),
    onSuccess: () => {
      invalidatePolicies();
      addNotification({ type: 'success', message: 'Policy created' });
      setShowCreate(false);
    },
    onError: (error) => {
      addNotification({ type: 'error', message: getErrorMessage(error, 'Failed to create policy') });
    },
  });

  return (
    <div className="space-y-8">
      <Section
        title="Compliance policies"
        action={canManage ? (
          <Button variant="primary" size="sm" onClick={() => setShowCreate(true)}>
            <Plus className="h-4 w-4 mr-1" /> Create Policy
          </Button>
        ) : undefined}
      >
        <PolicyList />
      </Section>
      <Section title="Violations">
        <ViolationList />
      </Section>
      <Section title="Security events">
        <SecurityEventList />
      </Section>

      <CreatePolicyModal
        isOpen={showCreate}
        onClose={() => setShowCreate(false)}
        onSubmit={(data) => createPolicy.mutate(data)}
        submitting={createPolicy.isPending}
      />
    </div>
  );
};

import React, { useState } from 'react';
import { Shield, Key, ShieldAlert, CheckSquare } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer } from '@/shared/components/ui/TabContainer';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useProvisionIdentity } from '../api/securityExtApi';
import { SecurityScoreCard } from '../components/SecurityScoreCard';
import { AgentIdentityList } from '../components/AgentIdentityList';
import { QuarantineList } from '../components/QuarantineList';
import { AsiComplianceMatrix } from '../components/AsiComplianceMatrix';

export const SecurityDashboardPage: React.FC = () => {
  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();
  const [activeTab, setActiveTab] = useState('identities');
  const [provisionAgentId, setProvisionAgentId] = useState('');
  const [showProvisionModal, setShowProvisionModal] = useState(false);

  const provisionIdentity = useProvisionIdentity();

  const canView = hasPermission('ai.security.manage');

  if (!canView) {
    return (
      <PageContainer
        title="Agent Security"
        breadcrumbs={[
          { label: 'Dashboard', href: '/app' },
          { label: 'AI', href: '/app/ai' },
          { label: 'Agent Security' },
        ]}
      >
        <div className="text-center py-12">
          <Shield className="h-12 w-12 text-theme-muted mx-auto mb-4 opacity-50" />
          <p className="text-theme-secondary">You do not have permission to view security data.</p>
        </div>
      </PageContainer>
    );
  }

  const handleProvision = () => {
    setShowProvisionModal(true);
  };

  const handleProvisionSubmit = () => {
    if (!provisionAgentId.trim()) {
      addNotification({ type: 'error', message: 'Agent ID is required' });
      return;
    }

    provisionIdentity.mutate({ agent_id: provisionAgentId.trim() }, {
      onSuccess: () => {
        addNotification({ type: 'success', message: 'Identity provisioned successfully' });
        setShowProvisionModal(false);
        setProvisionAgentId('');
      },
      onError: () => {
        addNotification({ type: 'error', message: 'Failed to provision identity' });
      },
    });
  };

  const tabs = [
    {
      id: 'identities',
      label: 'Agent Identities',
      icon: <Key className="h-4 w-4" />,
      content: <AgentIdentityList onProvision={handleProvision} />,
    },
    {
      id: 'quarantine',
      label: 'Quarantine',
      icon: <ShieldAlert className="h-4 w-4" />,
      content: <QuarantineList />,
    },
    {
      id: 'compliance',
      label: 'ASI Compliance',
      icon: <CheckSquare className="h-4 w-4" />,
      content: <AsiComplianceMatrix />,
    },
  ];

  return (
    <PageContainer
      title="Agent Security"
      description="Manage agent identities, quarantine zones, and OWASP ASI compliance"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'AI', href: '/app/ai' },
        { label: 'Agent Security' },
      ]}
    >
      {/* Score Cards */}
      <SecurityScoreCard />

      {/* Tabbed Content */}
      <TabContainer
        tabs={tabs}
        activeTab={activeTab}
        onTabChange={setActiveTab}
        variant="underline"
      />

      {/* Provision Modal */}
      {showProvisionModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center">
          <div className="absolute inset-0 bg-black bg-opacity-50" onClick={() => setShowProvisionModal(false)} />
          <div className="relative bg-theme-card border border-theme rounded-lg shadow-lg p-6 w-full max-w-md">
            <h3 className="text-lg font-semibold text-theme-primary mb-4">Provision New Identity</h3>
            <p className="text-sm text-theme-secondary mb-4">
              Enter the agent ID to provision a new cryptographic identity.
            </p>
            <input
              type="text"
              value={provisionAgentId}
              onChange={(e) => setProvisionAgentId(e.target.value)}
              placeholder="Agent ID"
              className="w-full px-3 py-2 rounded border border-theme bg-theme-bg text-theme-primary placeholder:text-theme-muted mb-4"
              autoFocus
            />
            <div className="flex justify-end gap-3">
              <button
                onClick={() => { setShowProvisionModal(false); setProvisionAgentId(''); }}
                className="px-4 py-2 text-sm text-theme-secondary hover:text-theme-primary"
              >
                Cancel
              </button>
              <button
                onClick={handleProvisionSubmit}
                disabled={provisionIdentity.isPending || !provisionAgentId.trim()}
                className="px-4 py-2 text-sm bg-theme-primary text-theme-on-primary rounded hover:opacity-90 disabled:opacity-50"
              >
                {provisionIdentity.isPending ? 'Provisioning...' : 'Provision'}
              </button>
            </div>
          </div>
        </div>
      )}
    </PageContainer>
  );
};

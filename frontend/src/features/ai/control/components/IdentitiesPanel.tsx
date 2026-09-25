import React, { useState } from 'react';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useProvisionIdentity } from '@/features/ai/security/api/securityExtApi';
import { SecurityScoreCard } from '@/features/ai/security/components/SecurityScoreCard';
import { AgentIdentityList } from '@/features/ai/security/components/AgentIdentityList';
import { QuarantineList } from '@/features/ai/security/components/QuarantineList';

/**
 * Control → Safety → Identities & quarantine: the security score, agent
 * cryptographic identities (provision, rotate, revoke) and the quarantine
 * list. Moved from Governance → Security; its ASI compliance matrix went to
 * Compliance Audit.
 */
export const IdentitiesPanel: React.FC = () => {
  const { addNotification } = useNotifications();
  const [provisionAgentId, setProvisionAgentId] = useState('');
  const [showProvisionModal, setShowProvisionModal] = useState(false);
  const provisionIdentity = useProvisionIdentity();

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

  return (
    <div className="space-y-6">
      <SecurityScoreCard />
      <section aria-label="Agent identities" className="space-y-3">
        <h3 className="text-base font-semibold text-theme-primary">Agent identities</h3>
        <AgentIdentityList onProvision={() => setShowProvisionModal(true)} />
      </section>
      <section aria-label="Quarantine" className="space-y-3">
        <h3 className="text-base font-semibold text-theme-primary">Quarantine</h3>
        <QuarantineList />
      </section>

      {showProvisionModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center">
          <div className="absolute inset-0 bg-black/50" onClick={() => setShowProvisionModal(false)} />
          <div className="relative bg-theme-surface border border-theme rounded-lg shadow-lg p-6 w-full max-w-md">
            <h3 className="text-lg font-semibold text-theme-primary mb-4">Provision New Identity</h3>
            <p className="text-sm text-theme-secondary mb-4">
              Enter the agent ID to provision a new cryptographic identity.
            </p>
            <input
              type="text"
              value={provisionAgentId}
              onChange={(e) => setProvisionAgentId(e.target.value)}
              placeholder="Agent ID"
              className="w-full px-3 py-2 rounded border border-theme bg-theme-surface text-theme-primary placeholder:text-theme-tertiary mb-4"
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
                className="px-4 py-2 text-sm bg-theme-interactive-primary text-theme-on-primary rounded hover:opacity-90 disabled:opacity-50"
              >
                {provisionIdentity.isPending ? 'Provisioning...' : 'Provision'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

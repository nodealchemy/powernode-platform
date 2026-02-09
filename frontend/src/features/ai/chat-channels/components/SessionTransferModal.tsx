import React, { useState, useEffect } from 'react';
import { ArrowRight } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Select } from '@/shared/components/ui/Select';
import { Loading } from '@/shared/components/ui/Loading';
import { chatChannelsApi, agentsApi } from '@/shared/services/ai';
import type { ChatSessionSummary } from '@/shared/services/ai';

interface Agent {
  id: string;
  name: string;
}

interface SessionTransferModalProps {
  isOpen: boolean;
  onClose: () => void;
  session: ChatSessionSummary | null;
  onTransferred: () => void;
}

export const SessionTransferModal: React.FC<SessionTransferModalProps> = ({
  isOpen,
  onClose,
  session,
  onTransferred,
}) => {
  const [agents, setAgents] = useState<Agent[]>([]);
  const [selectedAgentId, setSelectedAgentId] = useState('');
  const [loading, setLoading] = useState(false);
  const [fetchingAgents, setFetchingAgents] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (isOpen) {
      setSelectedAgentId('');
      setError(null);
      loadAgents();
    }
  }, [isOpen]);

  const loadAgents = async () => {
    try {
      setFetchingAgents(true);
      const response = await agentsApi.getAgents({ per_page: 100 });
      setAgents(
        (response.items || []).map((a) => ({ id: a.id, name: a.name }))
      );
    } catch {
      setError('Failed to load agents');
    } finally {
      setFetchingAgents(false);
    }
  };

  const handleTransfer = async () => {
    if (!session || !selectedAgentId) return;

    try {
      setLoading(true);
      setError(null);
      await chatChannelsApi.transferSession(session.id, selectedAgentId);
      onTransferred();
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to transfer session');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Transfer Session"
      maxWidth="md"
      footer={
        <div className="flex justify-end gap-2">
          <Button variant="secondary" onClick={onClose} disabled={loading}>
            Cancel
          </Button>
          <Button
            variant="primary"
            onClick={handleTransfer}
            disabled={!selectedAgentId || loading}
          >
            {loading ? <Loading size="sm" /> : <ArrowRight className="w-4 h-4 mr-1" />}
            Transfer
          </Button>
        </div>
      }
    >
      <div className="space-y-4">
        {session && (
          <div className="p-3 rounded-lg bg-theme-bg-secondary">
            <p className="text-sm text-theme-text-secondary">Current Session</p>
            <p className="font-medium text-theme-text-primary">{session.platform_user_id}</p>
            {session.platform_username && (
              <p className="text-sm text-theme-text-secondary">
                @{session.platform_username}
              </p>
            )}
          </div>
        )}

        {error && (
          <div className="p-3 rounded-lg bg-theme-status-error/10 text-theme-status-error text-sm">
            {error}
          </div>
        )}

        {fetchingAgents ? (
          <div className="flex justify-center p-4">
            <Loading size="md" />
          </div>
        ) : (
          <Select
            label="Transfer to Agent"
            value={selectedAgentId}
            onChange={(value) => setSelectedAgentId(value)}
            options={[
              { value: '', label: 'Select an agent...' },
              ...agents.map((agent) => ({ value: agent.id, label: agent.name })),
            ]}
          />
        )}
      </div>
    </Modal>
  );
};

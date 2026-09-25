import React, { useState, useEffect, useCallback } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Select } from '@/shared/components/ui/Select';
import { Button } from '@/shared/components/ui/Button';
import { Loading } from '@/shared/components/ui/Loading';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { agentsApi, containerExecutionApi } from '@/shared/services/ai';
import type { AiAgent } from '@/shared/types/ai';

interface CreateSandboxModalProps {
  isOpen: boolean;
  onClose: () => void;
  onCreated?: () => void;
}

export const CreateSandboxModal: React.FC<CreateSandboxModalProps> = ({
  isOpen,
  onClose,
  onCreated,
}) => {
  const { addNotification } = useNotifications();
  const [agents, setAgents] = useState<AiAgent[]>([]);
  const [agentId, setAgentId] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [isCreating, setIsCreating] = useState(false);

  const resetForm = useCallback(() => {
    setAgentId('');
    setIsCreating(false);
  }, []);

  useEffect(() => {
    if (!isOpen) {
      resetForm();
      return;
    }

    setIsLoading(true);
    agentsApi
      .getMyAgents()
      .then((items) => setAgents(items || []))
      .catch((err) => {
        addNotification({
          type: 'error',
          message: err instanceof Error ? err.message : 'Failed to load agents',
        });
      })
      .finally(() => setIsLoading(false));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isOpen]);

  const handleCreate = async () => {
    if (!agentId) return;

    setIsCreating(true);
    try {
      await containerExecutionApi.createSandbox({ agent_id: agentId });
      addNotification({ type: 'success', message: 'Sandbox created' });
      onCreated?.();
      onClose();
    } catch (err) {
      addNotification({
        type: 'error',
        message: err instanceof Error ? err.message : 'Failed to create sandbox',
      });
    } finally {
      setIsCreating(false);
    }
  };

  return (
    <Modal isOpen={isOpen} onClose={onClose} title="Create Agent Sandbox">
      {isLoading ? (
        <div className="flex items-center justify-center p-8">
          <Loading size="lg" />
        </div>
      ) : (
        <div className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Agent</label>
            <Select value={agentId} onChange={setAgentId} className="w-full">
              <option value="">Select an agent...</option>
              {agents.map((agent) => (
                <option key={agent.id} value={agent.id}>
                  {agent.name}
                </option>
              ))}
            </Select>
          </div>

          <div className="flex justify-end gap-2 pt-2">
            <Button variant="ghost" onClick={onClose} disabled={isCreating}>
              Cancel
            </Button>
            <Button variant="primary" onClick={handleCreate} disabled={!agentId || isCreating}>
              {isCreating ? 'Creating...' : 'Create Sandbox'}
            </Button>
          </div>
        </div>
      )}
    </Modal>
  );
};

export default CreateSandboxModal;

import React from 'react';
import { Settings } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import { Button } from '@/shared/components/ui/Button';

export interface LoopSettingsForm {
  name: string;
  description: string;
  max_iterations: number;
  repository_url: string;
  default_agent_id: string;
}

interface LoopSettingsModalProps {
  isOpen: boolean;
  onClose: () => void;
  settingsForm: LoopSettingsForm;
  onFormChange: (updates: Partial<LoopSettingsForm>) => void;
  onSave: () => void;
  loading: boolean;
  agents: { id: string; name: string }[];
}

export const LoopSettingsModal: React.FC<LoopSettingsModalProps> = ({
  isOpen,
  onClose,
  settingsForm,
  onFormChange,
  onSave,
  loading,
  agents,
}) => {
  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Loop Settings"
      icon={<Settings className="w-5 h-5 text-theme-brand-primary" />}
      size="md"
      footer={
        <>
          <Button
            variant="outline"
            onClick={onClose}
            disabled={loading}
          >
            Cancel
          </Button>
          <Button
            variant="primary"
            onClick={onSave}
            disabled={loading || !settingsForm.name.trim()}
          >
            {loading ? 'Saving...' : 'Save Settings'}
          </Button>
        </>
      }
    >
      <div className="space-y-4">
        <div>
          <label className="block text-sm font-medium text-theme-text-primary mb-1">
            Name *
          </label>
          <Input
            value={settingsForm.name}
            onChange={(e) => onFormChange({ name: e.target.value })}
            placeholder="Loop name"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-text-primary mb-1">
            Description
          </label>
          <Input
            value={settingsForm.description}
            onChange={(e) => onFormChange({ description: e.target.value })}
            placeholder="Optional description..."
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-text-primary mb-1">
            Max Iterations
          </label>
          <Input
            type="number"
            value={settingsForm.max_iterations}
            onChange={(e) => onFormChange({ max_iterations: parseInt(e.target.value) || 50 })}
            min={1}
            max={1000}
          />
          <p className="text-xs text-theme-text-secondary mt-1">
            Maximum number of AI iterations before stopping
          </p>
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-text-primary mb-1">
            Repository URL
          </label>
          <Input
            value={settingsForm.repository_url}
            onChange={(e) => onFormChange({ repository_url: e.target.value })}
            placeholder="https://github.com/user/repo"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-text-primary mb-1">
            Default Agent
          </label>
          <Select
            value={settingsForm.default_agent_id}
            onChange={(value) => onFormChange({ default_agent_id: value })}
          >
            <option value="">No agent selected</option>
            {agents.map((agent) => (
              <option key={agent.id} value={agent.id}>
                {agent.name}
              </option>
            ))}
          </Select>
          <p className="text-xs text-theme-text-secondary mt-1">
            AI agent that will execute loop tasks
          </p>
        </div>
      </div>
    </Modal>
  );
};

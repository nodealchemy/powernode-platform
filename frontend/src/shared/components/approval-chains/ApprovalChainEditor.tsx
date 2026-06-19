import { useState } from 'react';
import { Route } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { PlusIcon } from '@heroicons/react/24/outline';
import { StepBuilder } from './StepBuilder';
import type { ApprovalChain, ApprovalChainStep } from '@/shared/types/approval';
import type { ChainCreatePayload } from '@/shared/hooks/useApprovalChains';

interface ApprovalChainEditorProps {
  isOpen: boolean;
  chain?: ApprovalChain | null;
  onClose: () => void;
  onSave: (payload: ChainCreatePayload) => Promise<void>;
}

const EMPTY_STEP: ApprovalChainStep = {
  name: 'Approval',
  approvers: [{ type: 'permission', value: 'system.infra_tasks.control' }],
  required_approvals: 1,
};

/**
 * Modal editor for an approval chain. Lets operators create or edit a
 * chain — name, sequential/parallel toggle, timeout, ordered steps.
 */
export function ApprovalChainEditor({ isOpen, chain, onClose, onSave }: ApprovalChainEditorProps) {
  const [name, setName] = useState(chain?.name || '');
  const [description, setDescription] = useState(chain?.description || '');
  const [isSequential, setIsSequential] = useState(chain?.is_sequential ?? true);
  const [timeoutHours, setTimeoutHours] = useState<number>(chain?.timeout_hours ?? 4);
  const [timeoutAction, setTimeoutAction] = useState<'approve' | 'reject' | 'escalate'>(
    chain?.timeout_action || 'reject'
  );
  const [steps, setSteps] = useState<ApprovalChainStep[]>(
    chain?.steps && chain.steps.length > 0 ? chain.steps : [{ ...EMPTY_STEP }]
  );
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const updateStep = (idx: number, next: ApprovalChainStep) =>
    setSteps((prev) => prev.map((s, i) => (i === idx ? next : s)));

  const removeStep = (idx: number) =>
    setSteps((prev) => prev.filter((_, i) => i !== idx));

  const addStep = () =>
    setSteps((prev) => [
      ...prev,
      { ...EMPTY_STEP, name: `Step ${prev.length + 1}` },
    ]);

  const handleSave = async () => {
    setError(null);
    if (!name.trim()) {
      setError('Name is required');
      return;
    }
    if (steps.length === 0) {
      setError('At least one step is required');
      return;
    }
    if (steps.some((s) => s.approvers.length === 0)) {
      setError('Every step must have at least one approver');
      return;
    }

    setSaving(true);
    try {
      await onSave({
        name: name.trim(),
        description: description.trim() || undefined,
        is_sequential: isSequential,
        timeout_hours: timeoutHours,
        timeout_action: timeoutAction,
        steps,
      });
      onClose();
    } catch (e) {
      setError((e as Error).message || 'Save failed');
    } finally {
      setSaving(false);
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      variant="centered"
      size="2xl"
      title={chain ? `Edit Chain: ${chain.name}` : 'New Approval Chain'}
      icon={<Route className="w-6 h-6" />}
      footer={
        <div className="flex items-center justify-between w-full">
          <span className="text-xs text-theme-tertiary">
            {error ? <span className="text-theme-danger-fg">{error}</span> : `${steps.length} step${steps.length === 1 ? '' : 's'}`}
          </span>
          <div className="flex gap-2">
            <Button variant="ghost" onClick={onClose}>
              Cancel
            </Button>
            <Button variant="primary" onClick={handleSave} disabled={saving}>
              {saving ? 'Saving…' : 'Save Chain'}
            </Button>
          </div>
        </div>
      }
    >
      <div className="space-y-4">
        <div>
          <label className="block text-xs font-medium text-theme-secondary mb-1">Name</label>
          <input
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="e.g. SRE then Manager"
            className="w-full px-3 py-1.5 text-sm rounded border border-theme bg-theme-background text-theme-primary"
          />
        </div>

        <div>
          <label className="block text-xs font-medium text-theme-secondary mb-1">
            Description
          </label>
          <textarea
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            rows={2}
            className="w-full px-3 py-1.5 text-sm rounded border border-theme bg-theme-background text-theme-primary"
          />
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
          <label className="flex items-center gap-2 text-sm text-theme-primary">
            <input
              type="checkbox"
              checked={isSequential}
              onChange={(e) => setIsSequential(e.target.checked)}
            />
            Sequential
          </label>
          <div>
            <label className="block text-xs font-medium text-theme-secondary mb-1">
              Timeout (hours)
            </label>
            <input
              type="number"
              min={1}
              value={timeoutHours}
              onChange={(e) => setTimeoutHours(parseInt(e.target.value, 10) || 4)}
              className="w-full px-2 py-1 text-sm rounded border border-theme bg-theme-background text-theme-primary"
            />
          </div>
          <div>
            <label className="block text-xs font-medium text-theme-secondary mb-1">
              Timeout action
            </label>
            <select
              value={timeoutAction}
              onChange={(e) =>
                setTimeoutAction(e.target.value as 'approve' | 'reject' | 'escalate')
              }
              className="w-full px-2 py-1 text-sm rounded border border-theme bg-theme-background text-theme-primary"
            >
              <option value="reject">Reject</option>
              <option value="approve">Approve</option>
              <option value="escalate">Escalate</option>
            </select>
          </div>
        </div>

        <div className="space-y-3">
          {steps.map((step, idx) => (
            <StepBuilder
              key={idx}
              step={step}
              index={idx}
              total={steps.length}
              onChange={(next) => updateStep(idx, next)}
              onDelete={() => removeStep(idx)}
            />
          ))}
          <Button variant="secondary" size="sm" onClick={addStep}>
            <PlusIcon className="h-4 w-4" /> Add step
          </Button>
        </div>
      </div>
    </Modal>
  );
}

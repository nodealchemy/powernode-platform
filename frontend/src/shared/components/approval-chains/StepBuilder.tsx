import { useState } from 'react';
import { Button } from '@/shared/components/ui/Button';
import { TrashIcon, PlusIcon } from '@heroicons/react/24/outline';
import type { ApprovalChainStep, ApproverSpec } from '@/shared/types/approval';

interface StepBuilderProps {
  step: ApprovalChainStep;
  index: number;
  total: number;
  onChange: (next: ApprovalChainStep) => void;
  onDelete?: () => void;
}

const APPROVER_TYPES = [
  { value: 'permission', label: 'Permission' },
  { value: 'role', label: 'Role' },
  { value: 'user', label: 'User UUID' },
  { value: 'wildcard', label: 'Anyone' },
] as const;

/**
 * Editor for a single approval step within an ApprovalChain. Renders the
 * step name, an editable approver list (typed specs: permission / role /
 * user / wildcard), and the required-approvals counter.
 */
export function StepBuilder({ step, index, total, onChange, onDelete }: StepBuilderProps) {
  const [draftType, setDraftType] = useState<'permission' | 'role' | 'user' | 'wildcard'>('permission');
  const [draftValue, setDraftValue] = useState('');

  const updateStep = (patch: Partial<ApprovalChainStep>) => onChange({ ...step, ...patch });

  const addApprover = () => {
    if (draftType === 'wildcard') {
      updateStep({ approvers: [...step.approvers, '*'] });
    } else if (draftValue.trim()) {
      updateStep({
        approvers: [...step.approvers, { type: draftType, value: draftValue.trim() }],
      });
      setDraftValue('');
    }
  };

  const removeApprover = (idx: number) => {
    updateStep({ approvers: step.approvers.filter((_, i) => i !== idx) });
  };

  const renderApprover = (spec: ApproverSpec, idx: number) => {
    let label: string;
    if (spec === '*') label = 'Anyone (any active user)';
    else if (typeof spec === 'string') label = `User ${spec.slice(0, 8)}…`;
    else label = `${spec.type}: ${spec.value}`;

    return (
      <div
        key={idx}
        className="flex items-center gap-2 px-2 py-1 rounded bg-theme-background-secondary text-xs"
      >
        <span className="flex-1 text-theme-primary">{label}</span>
        <button
          onClick={() => removeApprover(idx)}
          className="text-theme-tertiary hover:text-theme-danger-fg"
          aria-label="Remove approver"
        >
          <TrashIcon className="h-3.5 w-3.5" />
        </button>
      </div>
    );
  };

  return (
    <div className="rounded-lg border border-theme p-3 space-y-3">
      <div className="flex items-center justify-between">
        <span className="text-xs font-semibold text-theme-tertiary">
          Step {index + 1} of {total}
        </span>
        {onDelete && total > 1 && (
          <button
            onClick={onDelete}
            className="text-theme-tertiary hover:text-theme-danger-fg text-xs"
          >
            Remove step
          </button>
        )}
      </div>

      <div>
        <label className="block text-[11px] font-medium text-theme-secondary mb-1">Name</label>
        <input
          type="text"
          value={step.name}
          onChange={(e) => updateStep({ name: e.target.value })}
          className="w-full text-sm px-2 py-1 rounded border border-theme bg-theme-background text-theme-primary"
        />
      </div>

      <div>
        <label className="block text-[11px] font-medium text-theme-secondary mb-1">
          Approvers ({step.approvers.length})
        </label>
        <div className="space-y-1 mb-2">
          {step.approvers.length === 0 ? (
            <p className="text-xs text-theme-tertiary italic">No approvers — step would auto-fail</p>
          ) : (
            step.approvers.map(renderApprover)
          )}
        </div>
        <div className="flex items-center gap-2">
          <select
            value={draftType}
            onChange={(e) => setDraftType(e.target.value as typeof draftType)}
            className="text-xs px-2 py-1 rounded border border-theme bg-theme-background text-theme-primary"
          >
            {APPROVER_TYPES.map((t) => (
              <option key={t.value} value={t.value}>
                {t.label}
              </option>
            ))}
          </select>
          {draftType !== 'wildcard' && (
            <input
              type="text"
              value={draftValue}
              onChange={(e) => setDraftValue(e.target.value)}
              placeholder={
                draftType === 'permission'
                  ? 'e.g. system.infra_tasks.control'
                  : draftType === 'role'
                  ? 'e.g. sre'
                  : 'user UUID'
              }
              className="flex-1 text-xs px-2 py-1 rounded border border-theme bg-theme-background text-theme-primary"
            />
          )}
          <Button variant="secondary" size="xs" onClick={addApprover}>
            <PlusIcon className="h-3 w-3" /> Add
          </Button>
        </div>
      </div>

      <div className="flex items-center gap-3">
        <label className="text-[11px] font-medium text-theme-secondary">
          Required approvals
        </label>
        <input
          type="number"
          min={1}
          value={step.required_approvals || 1}
          onChange={(e) =>
            updateStep({ required_approvals: Math.max(1, parseInt(e.target.value, 10) || 1) })
          }
          className="w-16 text-sm px-2 py-1 rounded border border-theme bg-theme-background text-theme-primary"
        />
        <label className="flex items-center gap-1.5 text-[11px] text-theme-secondary ml-auto">
          <input
            type="checkbox"
            checked={!!step.allow_self_approval}
            onChange={(e) => updateStep({ allow_self_approval: e.target.checked })}
          />
          Allow self-approval
        </label>
      </div>
    </div>
  );
}

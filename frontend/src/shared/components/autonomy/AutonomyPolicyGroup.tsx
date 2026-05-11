import { useState } from 'react';
import { Button } from '@/shared/components/ui/Button';
import type { AutonomyLevel } from '@/shared/types/autonomy';

interface AutonomyPolicyGroupProps {
  label: string;
  agentName: string;
  actions: string[];
  /** Optional human labels per action; falls back to the action_category itself */
  actionLabels?: Record<string, string>;
  getPolicy: (agentName: string, action: string) => AutonomyLevel;
  updatePolicy: (agentName: string, action: string, level: AutonomyLevel) => void;
  onDirty: () => void;
  onSave?: () => Promise<void>;
  isDirty?: boolean;
}

/**
 * Per-domain autonomy policy editor — renders an action list with per-row
 * dropdowns plus a "Set all" bulk-set control. Used inside System Settings
 * Modal (one instance per domain tab) and Trading Settings Panel (one instance
 * per agent role).
 *
 * Promoted to shared from Trading 2026-05-10 — autonomy is a platform-wide
 * feature, every extension that grows agents will need this UI.
 */
export function AutonomyPolicyGroup({
  label,
  agentName,
  actions,
  actionLabels = {},
  getPolicy,
  updatePolicy,
  onDirty,
  onSave,
  isDirty,
}: AutonomyPolicyGroupProps) {
  const [saving, setSaving] = useState(false);

  const handleSave = async () => {
    if (!onSave) return;
    setSaving(true);
    try {
      await onSave();
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="rounded-lg border border-theme overflow-hidden">
      <div className="px-4 py-2.5 bg-theme-background-secondary flex items-center justify-between">
        <span className="text-xs font-semibold text-theme-primary">{label}</span>
        <div className="flex items-center gap-2">
          <span className="text-[10px] text-theme-tertiary">{actions.length} actions</span>
          <select
            value=""
            onChange={(e) => {
              if (!e.target.value) return;
              const level = e.target.value as AutonomyLevel;
              actions.forEach((action) => updatePolicy(agentName, action, level));
              onDirty();
              e.target.value = '';
            }}
            className="text-[10px] px-1.5 py-0.5 rounded border border-theme bg-theme-background text-theme-accent w-[80px]"
          >
            <option value="">Set all</option>
            <option value="block">Disabled</option>
            <option value="require_approval">Suggest</option>
            <option value="notify_and_proceed">Auto-exec</option>
            <option value="auto_approve">Full auto</option>
          </select>
          {onSave && (
            <Button
              variant="primary"
              size="xs"
              onClick={handleSave}
              disabled={!isDirty || saving}
            >
              {saving ? 'Saving…' : 'Save Permissions'}
            </Button>
          )}
        </div>
      </div>
      <div className="p-3">
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-x-3 gap-y-1">
          {actions.map((action) => (
            <div key={action} className="flex items-center gap-1.5 py-0.5">
              <span className="text-xs text-theme-primary truncate flex-1 min-w-0">
                {actionLabels[action] || action}
              </span>
              <select
                value={getPolicy(agentName, action)}
                onChange={(e) => {
                  updatePolicy(agentName, action, e.target.value as AutonomyLevel);
                  onDirty();
                }}
                className="text-[11px] px-1.5 py-0.5 rounded border border-theme bg-theme-background text-theme-primary shrink-0 w-[100px]"
              >
                <option value="block">Disabled</option>
                <option value="require_approval">Suggest</option>
                <option value="notify_and_proceed">Auto-execute</option>
                <option value="auto_approve">Full auto</option>
              </select>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

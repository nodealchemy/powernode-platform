import React from 'react';
import { Crown, ArrowDown, ArrowUp, ArrowLeftRight, AlertTriangle } from 'lucide-react';

export interface AuthorityOverrides {
  workers_can_escalate_directly: boolean;
  specialists_can_delegate: boolean;
  lateral_delegation_allowed: boolean;
  emergency_escalation_enabled: boolean;
}

interface AuthorityConfigSectionProps {
  overrides: AuthorityOverrides;
  onUpdate: (overrides: AuthorityOverrides) => void;
}

const AUTHORITY_LEVELS = [
  { level: 1, label: 'Manager / Lead', roles: 'Delegate, override, set authority, broadcast' },
  { level: 2, label: 'Coordinator / Specialist', roles: 'Delegate (if allowed), escalate, coordinate' },
  { level: 3, label: 'Worker / Researcher / Writer', roles: 'Execute, escalate, collaborate, self-organize' },
  { level: 4, label: 'Reviewer / Validator', roles: 'Observe, review — cannot direct others' },
];

const TOGGLE_OPTIONS: Array<{ key: keyof AuthorityOverrides; label: string; description: string; icon: React.ReactNode }> = [
  {
    key: 'workers_can_escalate_directly',
    label: 'Direct Escalation',
    description: 'Workers can skip levels when escalating to managers',
    icon: <ArrowUp className="h-3.5 w-3.5" />,
  },
  {
    key: 'specialists_can_delegate',
    label: 'Specialist Delegation',
    description: 'Specialists and coordinators can delegate tasks to workers',
    icon: <ArrowDown className="h-3.5 w-3.5" />,
  },
  {
    key: 'lateral_delegation_allowed',
    label: 'Lateral Delegation',
    description: 'Agents at the same authority level can delegate to each other',
    icon: <ArrowLeftRight className="h-3.5 w-3.5" />,
  },
  {
    key: 'emergency_escalation_enabled',
    label: 'Emergency Escalation',
    description: 'Allow skip-level escalation in emergency situations',
    icon: <AlertTriangle className="h-3.5 w-3.5" />,
  },
];

export const AuthorityConfigSection: React.FC<AuthorityConfigSectionProps> = ({ overrides, onUpdate }) => {
  const handleToggle = (key: keyof AuthorityOverrides) => {
    onUpdate({ ...overrides, [key]: !overrides[key] });
  };

  return (
    <div className="bg-theme-surface border border-theme rounded-lg p-4 space-y-4">
      <div className="flex items-center gap-2 mb-2">
        <Crown className="h-4 w-4 text-theme-primary" />
        <h4 className="text-sm font-semibold text-theme-primary">Authority Hierarchy</h4>
      </div>

      {/* Authority Levels Display */}
      <div className="space-y-1.5">
        {AUTHORITY_LEVELS.map(({ level, label, roles }) => (
          <div
            key={level}
            className="flex items-start gap-3 px-3 py-2 bg-theme-bg rounded-md"
          >
            <span className="flex-shrink-0 w-6 h-6 flex items-center justify-center rounded-full bg-theme-primary/10 text-theme-primary text-xs font-bold">
              {level}
            </span>
            <div className="min-w-0">
              <p className="text-sm font-medium text-theme-primary">{label}</p>
              <p className="text-xs text-theme-secondary">{roles}</p>
            </div>
          </div>
        ))}
      </div>

      {/* Override Toggles */}
      <div className="border-t border-theme pt-4 space-y-3">
        <p className="text-xs font-medium text-theme-secondary uppercase tracking-wide">Authority Overrides</p>
        {TOGGLE_OPTIONS.map(({ key, label, description, icon }) => (
          <div key={key} className="flex items-center justify-between gap-3">
            <div className="flex items-center gap-2 min-w-0">
              <span className="flex-shrink-0 text-theme-secondary">{icon}</span>
              <div className="min-w-0">
                <p className="text-sm text-theme-primary">{label}</p>
                <p className="text-xs text-theme-secondary">{description}</p>
              </div>
            </div>
            <button
              type="button"
              role="switch"
              aria-checked={overrides[key]}
              onClick={() => handleToggle(key)}
              className={`relative flex-shrink-0 w-10 h-5 rounded-full transition-colors ${
                overrides[key] ? 'bg-theme-primary' : 'bg-theme-accent'
              }`}
            >
              <span className={`absolute top-0.5 left-0.5 w-4 h-4 rounded-full bg-white transition-transform ${
                overrides[key] ? 'translate-x-5' : ''
              }`} />
            </button>
          </div>
        ))}
      </div>
    </div>
  );
};

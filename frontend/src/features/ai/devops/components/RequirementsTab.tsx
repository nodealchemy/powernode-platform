import React from 'react';
import { X } from 'lucide-react';

const inputClass = 'w-full px-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary';
const labelClass = 'block text-sm font-medium text-theme-primary mb-1';

interface RequirementsTabProps {
  secretsRequired: string[];
  integrationsRequired: string[];
  newSecret: string;
  newIntegration: string;
  onNewSecretChange: (value: string) => void;
  onNewIntegrationChange: (value: string) => void;
  onAddSecret: () => void;
  onAddIntegration: () => void;
  onRemoveSecret: (index: number) => void;
  onRemoveIntegration: (index: number) => void;
}

export const RequirementsTab: React.FC<RequirementsTabProps> = ({
  secretsRequired,
  integrationsRequired,
  newSecret,
  newIntegration,
  onNewSecretChange,
  onNewIntegrationChange,
  onAddSecret,
  onAddIntegration,
  onRemoveSecret,
  onRemoveIntegration,
}) => {
  return (
    <div className="space-y-6">
      <div>
        <label className={labelClass}>Required Secrets</label>
        <p className="text-xs text-theme-secondary mb-2">Secret keys that must be configured before using this template.</p>
        <div className="flex flex-wrap gap-1.5 mb-2">
          {secretsRequired.map((secret, i) => (
            <span key={i} className="inline-flex items-center gap-1 px-2 py-1 text-xs rounded bg-theme-warning/10 text-theme-warning font-mono">
              {secret}
              <button onClick={() => onRemoveSecret(i)} className="hover:text-theme-danger">
                <X size={10} />
              </button>
            </span>
          ))}
        </div>
        <div className="flex gap-2">
          <input
            type="text"
            value={newSecret}
            onChange={(e) => onNewSecretChange(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); onAddSecret(); } }}
            placeholder="e.g. git_provider_token"
            className={`${inputClass} font-mono`}
          />
          <button onClick={onAddSecret} className="btn-theme btn-theme-secondary btn-theme-sm whitespace-nowrap">
            Add
          </button>
        </div>
      </div>
      <div>
        <label className={labelClass}>Required Integrations</label>
        <p className="text-xs text-theme-secondary mb-2">Integration types that must be connected.</p>
        <div className="flex flex-wrap gap-1.5 mb-2">
          {integrationsRequired.map((integration, i) => (
            <span key={i} className="inline-flex items-center gap-1 px-2 py-1 text-xs rounded bg-theme-info/10 text-theme-info">
              {integration}
              <button onClick={() => onRemoveIntegration(i)} className="hover:text-theme-danger">
                <X size={10} />
              </button>
            </span>
          ))}
        </div>
        <div className="flex gap-2">
          <input
            type="text"
            value={newIntegration}
            onChange={(e) => onNewIntegrationChange(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); onAddIntegration(); } }}
            placeholder="e.g. git_provider"
            className={inputClass}
          />
          <button onClick={onAddIntegration} className="btn-theme btn-theme-secondary btn-theme-sm whitespace-nowrap">
            Add
          </button>
        </div>
      </div>
    </div>
  );
};

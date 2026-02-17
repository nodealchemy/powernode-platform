import React, { useState } from 'react';
import type { RiskContract, RiskRule } from '../types/codeFactory';

interface Props {
  contract: RiskContract | null;
  onSave: (data: Partial<RiskContract>) => void;
  onClose: () => void;
}

const DEFAULT_RISK_RULE: RiskRule = {
  tier: 'standard',
  patterns: ['**/*'],
  required_checks: ['lint', 'tests'],
  evidence_required: false,
  min_reviewers: 1,
};

export const ContractEditor: React.FC<Props> = ({ contract, onSave, onClose }) => {
  const [name, setName] = useState(contract?.name || '');
  const [riskTiers, setRiskTiers] = useState<RiskRule[]>(
    contract?.risk_tiers?.length ? contract.risk_tiers : [{ ...DEFAULT_RISK_RULE }]
  );
  const [saving, setSaving] = useState(false);

  const handleAddTier = () => {
    setRiskTiers([...riskTiers, { ...DEFAULT_RISK_RULE }]);
  };

  const handleRemoveTier = (index: number) => {
    setRiskTiers(riskTiers.filter((_, i) => i !== index));
  };

  const handleTierChange = (index: number, field: keyof RiskRule, value: unknown) => {
    setRiskTiers(
      riskTiers.map((tier, i) => (i === index ? { ...tier, [field]: value } : tier))
    );
  };

  const handleSave = async () => {
    if (!name.trim()) return;
    setSaving(true);
    try {
      await onSave({ name, risk_tiers: riskTiers });
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div className="bg-theme-surface border border-theme rounded-lg shadow-xl w-full max-w-2xl max-h-[90vh] overflow-y-auto p-6">
        <div className="flex items-center justify-between mb-6">
          <h2 className="text-lg font-semibold text-theme-primary">
            {contract ? 'Edit Contract' : 'New Risk Contract'}
          </h2>
          <button onClick={onClose} className="text-theme-secondary hover:text-theme-primary">
            ✕
          </button>
        </div>

        <div className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-1">Name</label>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              className="w-full px-3 py-2 bg-theme-secondary-bg rounded border border-theme-border text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent"
              placeholder="Production Risk Contract"
            />
          </div>

          <div>
            <div className="flex items-center justify-between mb-2">
              <label className="text-sm font-medium text-theme-secondary">Risk Tiers</label>
              <button
                onClick={handleAddTier}
                className="text-xs text-theme-accent hover:underline"
              >
                + Add Tier
              </button>
            </div>

            {riskTiers.map((tier, index) => (
              <div key={index} className="card-theme p-3 mb-3 space-y-2">
                <div className="flex items-center justify-between">
                  <select
                    value={tier.tier}
                    onChange={(e) => handleTierChange(index, 'tier', e.target.value)}
                    className="px-2 py-1 bg-theme-secondary-bg rounded border border-theme-border text-sm text-theme-primary"
                  >
                    <option value="low">Low</option>
                    <option value="standard">Standard</option>
                    <option value="high">High</option>
                    <option value="critical">Critical</option>
                  </select>
                  {riskTiers.length > 1 && (
                    <button
                      onClick={() => handleRemoveTier(index)}
                      className="text-xs text-theme-error hover:underline"
                    >
                      Remove
                    </button>
                  )}
                </div>
                <div>
                  <label className="text-xs text-theme-secondary">Patterns (comma-separated)</label>
                  <input
                    type="text"
                    value={tier.patterns.join(', ')}
                    onChange={(e) =>
                      handleTierChange(index, 'patterns', e.target.value.split(',').map(p => p.trim()))
                    }
                    className="w-full px-2 py-1 bg-theme-secondary-bg rounded border border-theme-border text-sm text-theme-primary"
                  />
                </div>
                <div>
                  <label className="text-xs text-theme-secondary">Required Checks (comma-separated)</label>
                  <input
                    type="text"
                    value={tier.required_checks.join(', ')}
                    onChange={(e) =>
                      handleTierChange(index, 'required_checks', e.target.value.split(',').map(c => c.trim()))
                    }
                    className="w-full px-2 py-1 bg-theme-secondary-bg rounded border border-theme-border text-sm text-theme-primary"
                  />
                </div>
                <div className="flex items-center gap-4">
                  <label className="flex items-center gap-1 text-xs text-theme-secondary">
                    <input
                      type="checkbox"
                      checked={tier.evidence_required}
                      onChange={(e) => handleTierChange(index, 'evidence_required', e.target.checked)}
                    />
                    Evidence Required
                  </label>
                  <label className="flex items-center gap-1 text-xs text-theme-secondary">
                    Min Reviewers:
                    <input
                      type="number"
                      min="0"
                      value={tier.min_reviewers}
                      onChange={(e) => handleTierChange(index, 'min_reviewers', parseInt(e.target.value) || 0)}
                      className="w-16 px-1 py-0.5 bg-theme-secondary-bg rounded border border-theme-border text-sm text-theme-primary"
                    />
                  </label>
                </div>
              </div>
            ))}
          </div>
        </div>

        <div className="flex justify-end gap-3 mt-6 pt-4 border-t border-theme-border">
          <button
            onClick={onClose}
            className="px-4 py-2 text-sm font-medium text-theme-secondary hover:text-theme-primary transition-colors"
          >
            Cancel
          </button>
          <button
            onClick={handleSave}
            disabled={saving || !name.trim()}
            className="px-4 py-2 text-sm font-medium bg-theme-accent text-theme-on-primary rounded hover:opacity-90 disabled:opacity-50 transition-opacity"
          >
            {saving ? 'Saving...' : contract ? 'Update' : 'Create'}
          </button>
        </div>
      </div>
    </div>
  );
};

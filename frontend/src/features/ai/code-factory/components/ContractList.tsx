import React, { useState } from 'react';
import type { RiskContract, RiskRule } from '../types/codeFactory';

interface Props {
  contracts: RiskContract[];
  compact?: boolean;
  loading?: boolean;
  onEdit?: (contract: RiskContract) => void;
  onActivate?: (id: string) => void;
  onSave?: (id: string, data: Partial<RiskContract>) => Promise<RiskContract | undefined>;
}

const statusColors: Record<string, string> = {
  draft: 'bg-theme-secondary-bg text-theme-secondary',
  active: 'bg-theme-success-bg text-theme-success',
  archived: 'bg-theme-warning-bg text-theme-warning',
};

const tierColors: Record<string, string> = {
  low: 'text-theme-secondary',
  standard: 'text-theme-info',
  high: 'text-theme-warning',
  critical: 'text-theme-error',
};

export const ContractList: React.FC<Props> = ({ contracts, compact, loading, onActivate, onSave }) => {
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editName, setEditName] = useState('');
  const [editTiers, setEditTiers] = useState<RiskRule[]>([]);
  const [saving, setSaving] = useState(false);

  if (loading) {
    return <div className="text-center py-8 text-theme-secondary">Loading contracts...</div>;
  }

  if (contracts.length === 0) {
    return (
      <div className="text-center py-8 text-theme-secondary">
        No risk contracts found. Create one to get started.
      </div>
    );
  }

  const toggleExpand = (id: string) => {
    if (expandedId === id) {
      setExpandedId(null);
      setEditingId(null);
    } else {
      setExpandedId(id);
      setEditingId(null);
    }
  };

  const startEditing = (contract: RiskContract) => {
    setEditingId(contract.id);
    setEditName(contract.name);
    setEditTiers(contract.risk_tiers?.map(t => ({ ...t })) || []);
  };

  const cancelEditing = () => {
    setEditingId(null);
  };

  const handleSave = async (contract: RiskContract) => {
    if (!onSave || !editName.trim()) return;
    setSaving(true);
    try {
      await onSave(contract.id, { name: editName, risk_tiers: editTiers });
      setEditingId(null);
    } finally {
      setSaving(false);
    }
  };

  const handleTierChange = (index: number, field: keyof RiskRule, value: unknown) => {
    setEditTiers(prev => prev.map((tier, i) => (i === index ? { ...tier, [field]: value } : tier)));
  };

  const addTier = () => {
    setEditTiers(prev => [...prev, { tier: 'standard', patterns: ['**/*'], required_checks: ['test_suite'], evidence_required: false, min_reviewers: 0 }]);
  };

  const removeTier = (index: number) => {
    setEditTiers(prev => prev.filter((_, i) => i !== index));
  };

  return (
    <div className="space-y-3">
      {contracts.map((contract) => {
        const isExpanded = expandedId === contract.id;
        const isEditing = editingId === contract.id;
        const tiers = isEditing ? editTiers : (contract.risk_tiers || []);

        return (
          <div key={contract.id} className="card-theme overflow-hidden">
            {/* Header row — always visible */}
            <div
              className="p-4 flex items-center justify-between hover:bg-theme-hover transition-colors cursor-pointer"
              onClick={() => toggleExpand(contract.id)}
            >
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <span className={`transition-transform text-xs text-theme-secondary ${isExpanded ? 'rotate-90' : ''}`}>
                    {'\u25B6'}
                  </span>
                  <h4 className="text-sm font-medium text-theme-primary truncate">{contract.name}</h4>
                  <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${statusColors[contract.status] || ''}`}>
                    {contract.status}
                  </span>
                </div>
                {!compact && (
                  <div className="flex items-center gap-4 mt-1 ml-5 text-xs text-theme-secondary">
                    <span>v{contract.version}</span>
                    <span>{contract.risk_tiers?.length || 0} tiers</span>
                    {contract.repository && <span>{contract.repository.full_name || contract.repository.name}</span>}
                    {contract.activated_at && (
                      <span>Activated {new Date(contract.activated_at).toLocaleDateString()}</span>
                    )}
                  </div>
                )}
              </div>
              <div className="flex items-center gap-2" onClick={(e) => e.stopPropagation()}>
                {!compact && contract.status === 'draft' && onActivate && (
                  <button
                    onClick={() => onActivate(contract.id)}
                    className="px-3 py-1 text-xs font-medium bg-theme-accent text-theme-on-primary rounded hover:opacity-90 transition-opacity"
                  >
                    Activate
                  </button>
                )}
              </div>
            </div>

            {/* Expanded details */}
            {isExpanded && !compact && (
              <div className="border-t border-theme-border px-4 pb-4">
                {/* Toolbar */}
                <div className="flex items-center justify-between py-3">
                  <div className="text-xs text-theme-secondary">
                    Created {new Date(contract.created_at).toLocaleDateString()}
                    {contract.created_by && <span> by {contract.created_by.name || contract.created_by.email}</span>}
                  </div>
                  <div className="flex items-center gap-2">
                    {isEditing ? (
                      <>
                        <button
                          onClick={cancelEditing}
                          className="px-3 py-1 text-xs text-theme-secondary hover:text-theme-primary transition-colors"
                        >
                          Cancel
                        </button>
                        <button
                          onClick={() => handleSave(contract)}
                          disabled={saving || !editName.trim()}
                          className="px-3 py-1 text-xs font-medium bg-theme-accent text-theme-on-primary rounded hover:opacity-90 disabled:opacity-50 transition-opacity"
                        >
                          {saving ? 'Saving...' : 'Save'}
                        </button>
                      </>
                    ) : (
                      onSave && contract.status !== 'archived' && (
                        <button
                          onClick={() => startEditing(contract)}
                          className="px-3 py-1 text-xs text-theme-accent hover:underline"
                        >
                          Edit
                        </button>
                      )
                    )}
                  </div>
                </div>

                {/* Name field (edit mode) */}
                {isEditing && (
                  <div className="mb-4">
                    <label className="block text-xs font-medium text-theme-secondary mb-1">Name</label>
                    <input
                      type="text"
                      value={editName}
                      onChange={(e) => setEditName(e.target.value)}
                      className="w-full px-3 py-2 bg-theme-secondary-bg rounded border border-theme-border text-sm text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent"
                    />
                  </div>
                )}

                {/* Risk Tiers */}
                <div>
                  <div className="flex items-center justify-between mb-2">
                    <h5 className="text-xs font-semibold text-theme-secondary uppercase tracking-wider">Risk Tiers</h5>
                    {isEditing && (
                      <button onClick={addTier} className="text-xs text-theme-accent hover:underline">+ Add Tier</button>
                    )}
                  </div>
                  <div className="space-y-2">
                    {tiers.map((tier, index) => (
                      <div key={index} className="bg-theme-secondary-bg rounded-lg p-3">
                        {isEditing ? (
                          <div className="space-y-2">
                            <div className="flex items-center justify-between">
                              <select
                                value={tier.tier}
                                onChange={(e) => handleTierChange(index, 'tier', e.target.value)}
                                className="px-2 py-1 bg-theme-surface rounded border border-theme-border text-sm text-theme-primary"
                              >
                                <option value="low">Low</option>
                                <option value="standard">Standard</option>
                                <option value="high">High</option>
                                <option value="critical">Critical</option>
                              </select>
                              {editTiers.length > 1 && (
                                <button onClick={() => removeTier(index)} className="text-xs text-theme-error hover:underline">
                                  Remove
                                </button>
                              )}
                            </div>
                            <div>
                              <label className="text-xs text-theme-secondary">Patterns (comma-separated)</label>
                              <input
                                type="text"
                                value={tier.patterns.join(', ')}
                                onChange={(e) => handleTierChange(index, 'patterns', e.target.value.split(',').map(p => p.trim()))}
                                className="w-full px-2 py-1 bg-theme-surface rounded border border-theme-border text-sm text-theme-primary"
                              />
                            </div>
                            <div>
                              <label className="text-xs text-theme-secondary">Required Checks (comma-separated)</label>
                              <input
                                type="text"
                                value={tier.required_checks.join(', ')}
                                onChange={(e) => handleTierChange(index, 'required_checks', e.target.value.split(',').map(c => c.trim()))}
                                className="w-full px-2 py-1 bg-theme-surface rounded border border-theme-border text-sm text-theme-primary"
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
                                  className="w-16 px-1 py-0.5 bg-theme-surface rounded border border-theme-border text-sm text-theme-primary"
                                />
                              </label>
                            </div>
                          </div>
                        ) : (
                          <div className="flex items-start justify-between">
                            <div className="space-y-1">
                              <div className="flex items-center gap-2">
                                <span className={`text-sm font-semibold capitalize ${tierColors[tier.tier] || 'text-theme-primary'}`}>
                                  {tier.tier}
                                </span>
                                {tier.evidence_required && (
                                  <span className="px-1.5 py-0.5 text-[10px] bg-theme-warning-bg text-theme-warning rounded">evidence</span>
                                )}
                                {tier.min_reviewers > 0 && (
                                  <span className="px-1.5 py-0.5 text-[10px] bg-theme-info-bg text-theme-info rounded">
                                    {tier.min_reviewers} reviewer{tier.min_reviewers > 1 ? 's' : ''}
                                  </span>
                                )}
                              </div>
                              <div className="flex flex-wrap gap-1">
                                {tier.patterns.map((p, pi) => (
                                  <span key={pi} className="font-mono text-xs text-theme-secondary bg-theme-surface px-1.5 py-0.5 rounded">
                                    {p}
                                  </span>
                                ))}
                              </div>
                              {tier.required_checks.length > 0 && (
                                <div className="flex flex-wrap gap-1 mt-0.5">
                                  {tier.required_checks.map((check, ci) => (
                                    <span key={ci} className="text-xs text-theme-accent bg-theme-accent/10 px-1.5 py-0.5 rounded">
                                      {check}
                                    </span>
                                  ))}
                                </div>
                              )}
                            </div>
                          </div>
                        )}
                      </div>
                    ))}
                  </div>
                </div>

                {/* Remediation Config */}
                {Object.keys(contract.remediation_config || {}).length > 0 && !isEditing && (
                  <div className="mt-4">
                    <h5 className="text-xs font-semibold text-theme-secondary uppercase tracking-wider mb-2">Remediation Config</h5>
                    <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
                      {Object.entries(contract.remediation_config).map(([tier, config]) => {
                        const cfg = config as Record<string, unknown>;
                        return (
                          <div key={tier} className="bg-theme-secondary-bg rounded p-2">
                            <span className={`text-xs font-medium capitalize ${tierColors[tier] || 'text-theme-primary'}`}>{tier}</span>
                            <div className="text-[10px] text-theme-secondary mt-0.5">
                              {cfg.auto_remediate ? 'Auto-remediate' : 'Manual approval'}
                              {cfg.max_attempts != null && <span> ({String(cfg.max_attempts)} max)</span>}
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  </div>
                )}

                {/* Contract ID */}
                <div className="mt-4 text-[10px] text-theme-secondary font-mono">
                  ID: {contract.id}
                </div>
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
};

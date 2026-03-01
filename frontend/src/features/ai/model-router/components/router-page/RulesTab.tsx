import React from 'react';
import {
  Route, Search, ChevronDown, ChevronUp, Clock, Shield,
  Loader2, Crosshair, ToggleLeft, ToggleRight, Trash2
} from 'lucide-react';
import { RoutingRule } from '@/shared/services/ai/ModelRouterApiService';

interface RulesTabProps {
  rules: RoutingRule[];
  expandedRuleId: string | null;
  expandedRuleDetails: Record<string, RoutingRule>;
  loadingExpandId: string | null;
  onExpandRule: (ruleId: string) => void;
  onToggleRule: (ruleId: string) => void;
  onDeleteClick: (ruleId: string) => void;
  onCreateClick: () => void;
  getRuleTypeColor: (type: string) => string;
}

const formatLabel = (key: string): string =>
  key.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase());

const DetailValue: React.FC<{ value: unknown }> = ({ value }) => {
  if (value === null || value === undefined) return <span className="text-theme-tertiary italic">—</span>;
  if (Array.isArray(value)) {
    if (value.length === 0) return <span className="text-theme-tertiary italic">none</span>;
    return (
      <div className="flex flex-wrap gap-1 mt-0.5">
        {value.map((v, i) => (
          <span key={i} className="px-1.5 py-0.5 text-xs bg-theme-surface rounded border border-theme font-mono">{String(v)}</span>
        ))}
      </div>
    );
  }
  if (typeof value === 'object') {
    return <pre className="text-xs bg-theme-surface p-2 rounded overflow-x-auto font-mono mt-0.5">{JSON.stringify(value, null, 2)}</pre>;
  }
  if (typeof value === 'boolean') return <span className={value ? 'text-theme-success' : 'text-theme-danger'}>{value ? 'Yes' : 'No'}</span>;
  if (typeof value === 'number') return <span className="font-mono">{value.toLocaleString()}</span>;
  return <span className="font-mono">{String(value)}</span>;
};

const DetailSection: React.FC<{ title: string; icon: React.ReactNode; children: React.ReactNode }> = ({ title, icon, children }) => (
  <div className="bg-theme-bg rounded-lg p-3">
    <h4 className="flex items-center gap-1.5 text-xs font-semibold text-theme-secondary uppercase tracking-wide mb-2.5">
      {icon} {title}
    </h4>
    {children}
  </div>
);

const renderJsonEntries = (obj: Record<string, unknown> | undefined): React.ReactNode => {
  if (!obj || Object.keys(obj).length === 0) return <p className="text-xs text-theme-tertiary italic">Not configured</p>;
  return (
    <dl className="space-y-2">
      {Object.entries(obj).map(([key, value]) => (
        <div key={key}>
          <dt className="text-xs text-theme-secondary">{formatLabel(key)}</dt>
          <dd className="text-xs text-theme-primary"><DetailValue value={value} /></dd>
        </div>
      ))}
    </dl>
  );
};

const renderThresholds = (thresholds: RoutingRule['thresholds']): React.ReactNode => {
  if (!thresholds) return <p className="text-xs text-theme-tertiary italic">No thresholds set</p>;
  const entries: [string, string | null][] = [
    ['Max Cost / 1k Tokens', thresholds.max_cost_per_1k_tokens != null ? `$${Number(thresholds.max_cost_per_1k_tokens).toFixed(4)}` : null],
    ['Max Latency', thresholds.max_latency_ms != null ? `${Number(thresholds.max_latency_ms).toLocaleString()}ms` : null],
    ['Min Quality Score', thresholds.min_quality_score != null ? Number(thresholds.min_quality_score).toFixed(2) : null],
  ];
  const validEntries = entries.filter((e): e is [string, string] => e[1] !== null);
  if (validEntries.length === 0) return <p className="text-xs text-theme-tertiary italic">No thresholds set</p>;
  return (
    <dl className="space-y-1.5">
      {validEntries.map(([label, val]) => (
        <div key={label} className="flex justify-between text-xs">
          <dt className="text-theme-secondary">{label}</dt>
          <dd className="font-mono text-theme-primary">{val}</dd>
        </div>
      ))}
    </dl>
  );
};

export const RulesTab: React.FC<RulesTabProps> = ({
  rules,
  expandedRuleId,
  expandedRuleDetails,
  loadingExpandId,
  onExpandRule,
  onToggleRule,
  onDeleteClick,
  onCreateClick,
  getRuleTypeColor,
}) => {
  if (rules.length === 0) {
    return (
      <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
        <Route size={48} className="mx-auto text-theme-secondary mb-4" />
        <h3 className="text-lg font-semibold text-theme-primary mb-2">No routing rules</h3>
        <p className="text-theme-secondary mb-6">Create routing rules to optimize AI request distribution</p>
        <button onClick={onCreateClick} className="btn-theme btn-theme-primary">Create Rule</button>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {rules.map(rule => {
        const isExpanded = expandedRuleId === rule.id;
        const detail = expandedRuleDetails[rule.id];
        const isLoadingDetail = loadingExpandId === rule.id;

        return (
          <div key={rule.id} className="bg-theme-surface border border-theme rounded-lg overflow-hidden">
            <div
              className="flex items-center justify-between p-4 cursor-pointer select-none hover:bg-theme-surface-hover/50 transition-colors"
              onClick={() => onExpandRule(rule.id)}
            >
              <div className="flex items-center gap-3">
                {isExpanded
                  ? <ChevronUp size={16} className="text-theme-accent flex-shrink-0" />
                  : <ChevronDown size={16} className="text-theme-secondary flex-shrink-0" />}
                <span className="text-sm font-mono text-theme-secondary">#{rule.priority}</span>
                <h3 className="font-medium text-theme-primary">{rule.name}</h3>
                <span className={`px-2 py-1 text-xs rounded ${getRuleTypeColor(rule.rule_type)}`}>{rule.rule_type}</span>
              </div>
              <div className="flex items-center gap-3" onClick={e => e.stopPropagation()}>
                <button onClick={() => onToggleRule(rule.id)} className="text-theme-secondary hover:text-theme-primary transition-colors" title={rule.is_active ? 'Disable' : 'Enable'}>
                  {rule.is_active ? <ToggleRight size={20} className="text-theme-success" /> : <ToggleLeft size={20} />}
                </button>
                <button onClick={() => onDeleteClick(rule.id)} className="inline-flex items-center gap-1 px-2 py-1 text-xs rounded border border-theme-danger/30 text-theme-danger hover:bg-theme-danger/10 transition-colors" title="Delete rule">
                  <Trash2 size={13} /> Delete
                </button>
              </div>
            </div>

            {(rule.description || rule.stats) && (
              <div className="px-4 pb-3 -mt-1">
                {rule.description && <p className="text-sm text-theme-secondary mb-2 pl-7">{rule.description}</p>}
                {rule.stats && (
                  <div className="flex gap-4 text-xs text-theme-secondary pl-7">
                    <span>{rule.stats.times_matched} matched</span>
                    <span className="text-theme-success">{rule.stats.times_succeeded} succeeded</span>
                    <span className="text-theme-danger">{rule.stats.times_failed} failed</span>
                    <span>{(rule.stats.success_rate * 100).toFixed(1)}% success</span>
                  </div>
                )}
              </div>
            )}

            {isExpanded && (
              <div className="border-t border-theme px-4 py-4">
                {isLoadingDetail ? (
                  <div className="flex items-center justify-center py-8">
                    <Loader2 size={20} className="animate-spin text-theme-accent" />
                    <span className="ml-2 text-sm text-theme-secondary">Loading rule details...</span>
                  </div>
                ) : detail ? (
                  <div>
                    {detail.description && !rule.description && (
                      <p className="text-sm text-theme-secondary mb-4">{detail.description}</p>
                    )}
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                      <DetailSection title="Conditions" icon={<Search size={12} />}>
                        {renderJsonEntries(detail.conditions)}
                      </DetailSection>
                      <DetailSection title="Target" icon={<Crosshair size={12} />}>
                        {renderJsonEntries(detail.target)}
                      </DetailSection>
                      <DetailSection title="Thresholds" icon={<Shield size={12} />}>
                        {renderThresholds(detail.thresholds)}
                      </DetailSection>
                      <DetailSection title="Metadata" icon={<Clock size={12} />}>
                        <dl className="space-y-1.5">
                          <div className="flex justify-between text-xs">
                            <dt className="text-theme-secondary">Rule ID</dt>
                            <dd className="font-mono text-theme-primary truncate ml-2" title={detail.id}>
                              {detail.id.length > 16 ? `${detail.id.slice(0, 16)}...` : detail.id}
                            </dd>
                          </div>
                          {detail.created_at && (
                            <div className="flex justify-between text-xs">
                              <dt className="text-theme-secondary">Created</dt>
                              <dd className="text-theme-primary">{new Date(detail.created_at).toLocaleDateString()}</dd>
                            </div>
                          )}
                          {detail.updated_at && (
                            <div className="flex justify-between text-xs">
                              <dt className="text-theme-secondary">Updated</dt>
                              <dd className="text-theme-primary">{new Date(detail.updated_at).toLocaleDateString()}</dd>
                            </div>
                          )}
                          {detail.stats?.last_matched_at && (
                            <div className="flex justify-between text-xs">
                              <dt className="text-theme-secondary">Last Matched</dt>
                              <dd className="text-theme-primary">{new Date(detail.stats.last_matched_at).toLocaleDateString()}</dd>
                            </div>
                          )}
                        </dl>
                      </DetailSection>
                    </div>
                  </div>
                ) : null}
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
};

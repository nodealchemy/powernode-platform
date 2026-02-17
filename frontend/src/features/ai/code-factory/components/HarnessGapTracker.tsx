import React, { useState } from 'react';
import type { HarnessGap, HarnessGapMetrics, SlaCompliance } from '../types/codeFactory';

interface Props {
  gaps: HarnessGap[];
  metrics: HarnessGapMetrics | null;
  slaCompliance: SlaCompliance | null;
  onRefresh: () => void;
  onAddTestCase?: (gapId: string, testReference: string) => Promise<void>;
  onCloseGap?: (gapId: string, notes?: string) => Promise<void>;
  onNavigateToContract?: (contractId: string) => void;
}

const severityColors: Record<string, string> = {
  low: 'bg-theme-secondary-bg text-theme-secondary',
  medium: 'bg-theme-warning-bg text-theme-warning',
  high: 'bg-theme-error-bg text-theme-error',
  critical: 'bg-theme-danger/20 text-theme-danger',
};

const statusColors: Record<string, string> = {
  open: 'bg-theme-error-bg text-theme-error',
  in_progress: 'bg-theme-info-bg text-theme-info',
  case_added: 'bg-theme-accent/10 text-theme-accent',
  verified: 'bg-theme-success-bg text-theme-success',
  closed: 'bg-theme-secondary-bg text-theme-secondary',
};

export const HarnessGapTracker: React.FC<Props> = ({
  gaps, metrics, slaCompliance, onRefresh, onAddTestCase, onCloseGap, onNavigateToContract,
}) => {
  const [filterStatus, setFilterStatus] = useState<string>('all');
  const [filterSeverity, setFilterSeverity] = useState<string>('all');
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [testRefInput, setTestRefInput] = useState('');
  const [closeNotesInput, setCloseNotesInput] = useState('');
  const [actionLoading, setActionLoading] = useState(false);

  const filteredGaps = gaps.filter((gap) => {
    if (filterStatus !== 'all' && gap.status !== filterStatus) return false;
    if (filterSeverity !== 'all' && gap.severity !== filterSeverity) return false;
    return true;
  });

  const handleAddTestCase = async (gapId: string) => {
    if (!onAddTestCase || !testRefInput.trim()) return;
    setActionLoading(true);
    try {
      await onAddTestCase(gapId, testRefInput.trim());
      setTestRefInput('');
    } finally {
      setActionLoading(false);
    }
  };

  const handleCloseGap = async (gapId: string) => {
    if (!onCloseGap) return;
    setActionLoading(true);
    try {
      await onCloseGap(gapId, closeNotesInput.trim() || undefined);
      setCloseNotesInput('');
    } finally {
      setActionLoading(false);
    }
  };

  const slaTimeRemaining = (deadline: string): { text: string; overdue: boolean } => {
    const diff = new Date(deadline).getTime() - Date.now();
    const hours = Math.abs(diff) / (1000 * 60 * 60);
    if (diff < 0) return { text: `${hours.toFixed(0)}h overdue`, overdue: true };
    if (hours < 24) return { text: `${hours.toFixed(0)}h remaining`, overdue: false };
    return { text: `${(hours / 24).toFixed(0)}d remaining`, overdue: false };
  };

  return (
    <div className="space-y-4">
      {/* Metrics Row */}
      {metrics && (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
          <div className="card-theme p-3 text-center">
            <div className="text-xl font-semibold text-theme-primary">{metrics.total}</div>
            <div className="text-xs text-theme-secondary">Total Gaps</div>
          </div>
          <div className="card-theme p-3 text-center">
            <div className="text-xl font-semibold text-theme-error">{metrics.open}</div>
            <div className="text-xs text-theme-secondary">Open</div>
          </div>
          <div className="card-theme p-3 text-center">
            <div className="text-xl font-semibold text-theme-info">{metrics.in_progress}</div>
            <div className="text-xs text-theme-secondary">In Progress</div>
          </div>
          <div className="card-theme p-3 text-center">
            <div className="text-xl font-semibold text-theme-success">
              {metrics.sla_compliance_rate.toFixed(0)}%
            </div>
            <div className="text-xs text-theme-secondary">SLA Compliance</div>
          </div>
        </div>
      )}

      {/* SLA Warnings */}
      {slaCompliance && slaCompliance.past_sla_count > 0 && (
        <div className="card-theme p-3 border-l-4 border-theme-error">
          <div className="text-sm font-medium text-theme-error mb-1">
            {slaCompliance.past_sla_count} gap(s) past SLA
          </div>
          <div className="space-y-1">
            {slaCompliance.past_sla_gaps.map((g) => (
              <div key={g.id} className="flex items-center gap-2 text-xs text-theme-secondary">
                <span className="font-mono">{g.incident_id}</span>
                <span className={`px-1.5 py-0.5 rounded text-[10px] ${severityColors[g.severity] || ''}`}>
                  {g.severity}
                </span>
                <span className="text-theme-error">{g.hours_overdue.toFixed(0)}h overdue</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Filters */}
      <div className="flex items-center gap-3">
        <select
          value={filterStatus}
          onChange={(e) => setFilterStatus(e.target.value)}
          className="text-xs bg-theme-secondary-bg text-theme-primary border border-theme-border rounded px-2 py-1"
        >
          <option value="all">All Statuses</option>
          <option value="open">Open</option>
          <option value="in_progress">In Progress</option>
          <option value="case_added">Case Added</option>
          <option value="verified">Verified</option>
          <option value="closed">Closed</option>
        </select>
        <select
          value={filterSeverity}
          onChange={(e) => setFilterSeverity(e.target.value)}
          className="text-xs bg-theme-secondary-bg text-theme-primary border border-theme-border rounded px-2 py-1"
        >
          <option value="all">All Severities</option>
          <option value="critical">Critical</option>
          <option value="high">High</option>
          <option value="medium">Medium</option>
          <option value="low">Low</option>
        </select>
        <button
          onClick={onRefresh}
          className="text-xs text-theme-accent hover:text-theme-accent-hover ml-auto"
        >
          Refresh
        </button>
      </div>

      {/* Gaps List */}
      {filteredGaps.length === 0 ? (
        <div className="text-center py-8 text-theme-secondary text-sm">
          No harness gaps match the current filters.
        </div>
      ) : (
        <div className="space-y-2">
          {filteredGaps.map((gap) => {
            const isExpanded = expandedId === gap.id;
            const sla = gap.sla_deadline ? slaTimeRemaining(gap.sla_deadline) : null;

            return (
              <div key={gap.id} className="card-theme overflow-hidden">
                {/* Header */}
                <div
                  className="p-3 flex items-center justify-between hover:bg-theme-hover transition-colors cursor-pointer"
                  onClick={() => setExpandedId(isExpanded ? null : gap.id)}
                >
                  <div className="flex items-center gap-2 min-w-0">
                    <span className={`transition-transform text-xs text-theme-secondary ${isExpanded ? 'rotate-90' : ''}`}>
                      {'\u25B6'}
                    </span>
                    <span className={`px-2 py-0.5 rounded text-xs font-medium ${severityColors[gap.severity] || ''}`}>
                      {gap.severity}
                    </span>
                    <span className={`px-2 py-0.5 rounded text-xs font-medium ${statusColors[gap.status] || ''}`}>
                      {gap.status.replace(/_/g, ' ')}
                    </span>
                    <span className="text-sm font-mono text-theme-primary truncate">{gap.incident_id}</span>
                  </div>
                  <div className="flex items-center gap-2 text-xs text-theme-secondary flex-shrink-0">
                    {gap.test_case_added && (
                      <span className="text-theme-success">{'\u2713'} Test</span>
                    )}
                    {sla && (
                      <span className={sla.overdue ? 'text-theme-error font-medium' : ''}>
                        {sla.text}
                      </span>
                    )}
                  </div>
                </div>

                {/* Expanded Details */}
                {isExpanded && (
                  <div className="border-t border-theme-border px-4 pb-4 space-y-3 pt-3">
                    {/* Description */}
                    <div>
                      <h5 className="text-xs font-semibold text-theme-secondary uppercase tracking-wider mb-1">Description</h5>
                      <p className="text-sm text-theme-primary">{gap.description}</p>
                    </div>

                    {/* Detail Grid */}
                    <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
                      <div className="bg-theme-secondary-bg rounded p-2">
                        <div className="text-[10px] text-theme-secondary">Source</div>
                        <div className="text-xs text-theme-primary capitalize">{gap.incident_source.replace(/_/g, ' ')}</div>
                      </div>
                      <div className="bg-theme-secondary-bg rounded p-2">
                        <div className="text-[10px] text-theme-secondary">Created</div>
                        <div className="text-xs text-theme-primary">{new Date(gap.created_at).toLocaleDateString()}</div>
                      </div>
                      {gap.sla_deadline && (
                        <div className={`rounded p-2 ${sla?.overdue ? 'bg-theme-error-bg' : 'bg-theme-secondary-bg'}`}>
                          <div className="text-[10px] text-theme-secondary">SLA Deadline</div>
                          <div className={`text-xs ${sla?.overdue ? 'text-theme-error font-medium' : 'text-theme-primary'}`}>
                            {new Date(gap.sla_deadline).toLocaleString()}
                          </div>
                        </div>
                      )}
                      {gap.resolved_at && (
                        <div className="bg-theme-success-bg rounded p-2">
                          <div className="text-[10px] text-theme-secondary">Resolved</div>
                          <div className="text-xs text-theme-success">{new Date(gap.resolved_at).toLocaleDateString()}</div>
                        </div>
                      )}
                    </div>

                    {/* Test Case Reference */}
                    {gap.test_case_reference && (
                      <div>
                        <h5 className="text-xs font-semibold text-theme-secondary uppercase tracking-wider mb-1">Test Case</h5>
                        <span className="text-xs font-mono text-theme-accent bg-theme-accent/10 px-2 py-1 rounded">
                          {gap.test_case_reference}
                        </span>
                      </div>
                    )}

                    {/* Resolution Notes */}
                    {gap.resolution_notes && (
                      <div>
                        <h5 className="text-xs font-semibold text-theme-secondary uppercase tracking-wider mb-1">Resolution</h5>
                        <p className="text-sm text-theme-primary bg-theme-secondary-bg rounded p-2">{gap.resolution_notes}</p>
                      </div>
                    )}

                    {/* Linked Contract */}
                    {gap.risk_contract_id && onNavigateToContract && (
                      <div className="flex items-center gap-2">
                        <span className="text-xs text-theme-secondary">Contract:</span>
                        <button
                          onClick={() => onNavigateToContract(gap.risk_contract_id!)}
                          className="text-xs text-theme-accent hover:underline"
                        >
                          View Contract
                        </button>
                      </div>
                    )}

                    {/* Actions */}
                    {gap.status !== 'closed' && (onAddTestCase || onCloseGap) && (
                      <div className="border-t border-theme-border pt-3 space-y-2">
                        {/* Add Test Case */}
                        {onAddTestCase && !gap.test_case_added && (
                          <div className="flex items-center gap-2">
                            <input
                              type="text"
                              value={testRefInput}
                              onChange={(e) => setTestRefInput(e.target.value)}
                              placeholder="spec/features/example_spec.rb:42"
                              className="flex-1 px-2 py-1 bg-theme-secondary-bg rounded border border-theme-border text-xs text-theme-primary font-mono focus:outline-none focus:ring-1 focus:ring-theme-accent"
                              onClick={(e) => e.stopPropagation()}
                            />
                            <button
                              onClick={() => handleAddTestCase(gap.id)}
                              disabled={actionLoading || !testRefInput.trim()}
                              className="px-3 py-1 text-xs font-medium bg-theme-accent text-theme-on-primary rounded hover:opacity-90 disabled:opacity-50"
                            >
                              Add Test
                            </button>
                          </div>
                        )}

                        {/* Close Gap */}
                        {onCloseGap && gap.test_case_added && (
                          <div className="flex items-center gap-2">
                            <input
                              type="text"
                              value={closeNotesInput}
                              onChange={(e) => setCloseNotesInput(e.target.value)}
                              placeholder="Resolution notes (optional)"
                              className="flex-1 px-2 py-1 bg-theme-secondary-bg rounded border border-theme-border text-xs text-theme-primary focus:outline-none focus:ring-1 focus:ring-theme-accent"
                              onClick={(e) => e.stopPropagation()}
                            />
                            <button
                              onClick={() => handleCloseGap(gap.id)}
                              disabled={actionLoading}
                              className="px-3 py-1 text-xs font-medium bg-theme-success text-theme-on-primary rounded hover:opacity-90 disabled:opacity-50"
                            >
                              Close Gap
                            </button>
                          </div>
                        )}
                      </div>
                    )}

                    {/* Footer */}
                    <div className="text-[10px] text-theme-secondary font-mono pt-1">
                      ID: {gap.id}
                    </div>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
};

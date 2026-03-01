import React, { useState } from 'react';
import type { RiskContract, ReviewState, HarnessGap, HarnessGapMetrics, SlaCompliance } from '../types/codeFactory';

interface Props {
  contracts: RiskContract[];
  reviewStates: ReviewState[];
  harnessGaps: HarnessGap[];
  gapMetrics: HarnessGapMetrics | null;
  slaCompliance: SlaCompliance | null;
  onNavigateTab?: (tab: string) => void;
}

const STATUS_ORDER: Record<string, number> = {
  pending: 0, preflight: 1, reviewing: 2, remediating: 3,
  verifying: 4, evidence_capture: 5, completed: 6, clean: 6,
  failed: -1, stale: -2, dirty: 2,
};

const STEPS = ['Preflight', 'Review', 'Remediation', 'Verify', 'Evidence', 'Complete'];

const severityColors: Record<string, string> = {
  low: 'bg-theme-secondary-bg text-theme-secondary',
  medium: 'bg-theme-warning-bg text-theme-warning',
  high: 'bg-theme-error-bg text-theme-error',
  critical: 'bg-theme-danger/20 text-theme-danger',
};

const MiniProgressBar: React.FC<{ status: string }> = ({ status }) => {
  const idx = STATUS_ORDER[status] ?? 0;
  const isFailed = status === 'stale' || status === 'dirty' || status === 'failed';
  return (
    <div className="flex gap-0.5">
      {STEPS.map((_, i) => (
        <div
          key={i}
          className={`h-1 flex-1 rounded-full ${
            idx > i
              ? 'bg-theme-success'
              : idx === i
              ? isFailed ? 'bg-theme-error' : 'bg-theme-accent'
              : 'bg-theme-tertiary-bg'
          }`}
        />
      ))}
    </div>
  );
};

export const CodeFactoryStatsCards: React.FC<Props> = ({
  contracts, reviewStates, harnessGaps, gapMetrics, slaCompliance, onNavigateTab,
}) => {
  const [expandedCard, setExpandedCard] = useState<string | null>(null);

  const activeContracts = contracts.filter(c => c.status === 'active');
  const draftContracts = contracts.filter(c => c.status === 'draft');
  const cleanReviews = reviewStates.filter(s => s.status === 'clean');
  const dirtyReviews = reviewStates.filter(s => s.status === 'dirty');
  const activeRuns = reviewStates.filter(s =>
    !['clean', 'dirty', 'stale', 'completed'].includes(s.status)
  );
  const slaRate = gapMetrics?.sla_compliance_rate ?? 100;
  const openGaps = harnessGaps.filter(g => g.status === 'open' || g.status === 'in_progress');
  const criticalGaps = openGaps.filter(g => g.severity === 'critical' || g.severity === 'high');

  const toggleExpand = (card: string) => {
    setExpandedCard(expandedCard === card ? null : card);
  };

  return (
    <div className="space-y-4">
      {/* Primary Metrics Row */}
      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3">
        {/* Active Contracts */}
        <div
          className="card-theme p-3 text-center cursor-pointer hover:ring-1 hover:ring-theme-accent/30 transition-all"
          onClick={() => toggleExpand('contracts')}
        >
          <div className="text-2xl font-bold text-theme-accent">{activeContracts.length}</div>
          <div className="text-xs text-theme-secondary mt-0.5">Active Contracts</div>
          {draftContracts.length > 0 && (
            <div className="text-[10px] text-theme-warning mt-0.5">{draftContracts.length} draft</div>
          )}
        </div>

        {/* Active Runs */}
        <div
          className="card-theme p-3 text-center cursor-pointer hover:ring-1 hover:ring-theme-accent/30 transition-all"
          onClick={() => toggleExpand('runs')}
        >
          <div className="text-2xl font-bold text-theme-info">{activeRuns.length}</div>
          <div className="text-xs text-theme-secondary mt-0.5">Active Runs</div>
          {activeRuns.length > 0 && (
            <div className="mt-1"><MiniProgressBar status={activeRuns[0].status} /></div>
          )}
        </div>

        {/* Clean Reviews */}
        <div
          className="card-theme p-3 text-center cursor-pointer hover:ring-1 hover:ring-theme-accent/30 transition-all"
          onClick={() => onNavigateTab?.('runs')}
        >
          <div className="text-2xl font-bold text-theme-success">{cleanReviews.length}</div>
          <div className="text-xs text-theme-secondary mt-0.5">Clean</div>
        </div>

        {/* Dirty Reviews */}
        <div
          className="card-theme p-3 text-center cursor-pointer hover:ring-1 hover:ring-theme-accent/30 transition-all"
          onClick={() => onNavigateTab?.('runs')}
        >
          <div className="text-2xl font-bold text-theme-error">{dirtyReviews.length}</div>
          <div className="text-xs text-theme-secondary mt-0.5">Dirty</div>
        </div>

        {/* SLA Compliance */}
        <div
          className={`card-theme p-3 text-center cursor-pointer hover:ring-1 hover:ring-theme-accent/30 transition-all ${
            slaRate < 80 ? 'border-l-2 border-theme-error' : ''
          }`}
          onClick={() => toggleExpand('sla')}
        >
          <div className={`text-2xl font-bold ${slaRate >= 90 ? 'text-theme-success' : slaRate >= 70 ? 'text-theme-warning' : 'text-theme-error'}`}>
            {slaRate.toFixed(0)}%
          </div>
          <div className="text-xs text-theme-secondary mt-0.5">SLA Compliance</div>
        </div>

        {/* Open Gaps */}
        <div
          className={`card-theme p-3 text-center cursor-pointer hover:ring-1 hover:ring-theme-accent/30 transition-all ${
            criticalGaps.length > 0 ? 'border-l-2 border-theme-error' : ''
          }`}
          onClick={() => toggleExpand('gaps')}
        >
          <div className="text-2xl font-bold text-theme-warning">{openGaps.length}</div>
          <div className="text-xs text-theme-secondary mt-0.5">Open Gaps</div>
          {criticalGaps.length > 0 && (
            <div className="text-[10px] text-theme-error mt-0.5">{criticalGaps.length} critical/high</div>
          )}
        </div>
      </div>

      {/* Expandable Detail Panels */}
      {expandedCard === 'contracts' && (
        <div className="card-theme p-4 space-y-3">
          <div className="flex items-center justify-between">
            <h4 className="text-sm font-semibold text-theme-primary">Contract Overview</h4>
            <button onClick={() => onNavigateTab?.('contracts')} className="text-xs text-theme-accent hover:underline">
              View All
            </button>
          </div>
          {contracts.length === 0 ? (
            <div className="text-xs text-theme-secondary text-center py-2">No contracts yet.</div>
          ) : (
            <div className="space-y-2">
              {contracts.slice(0, 5).map((contract) => (
                <div key={contract.id} className="flex items-center justify-between bg-theme-secondary-bg rounded-lg px-3 py-2">
                  <div className="flex items-center gap-2 min-w-0">
                    <span className="text-sm text-theme-primary truncate">{contract.name}</span>
                    <span className={`px-1.5 py-0.5 rounded-full text-[10px] font-medium ${
                      contract.status === 'active'
                        ? 'bg-theme-success-bg text-theme-success'
                        : contract.status === 'draft'
                        ? 'bg-theme-secondary-bg text-theme-secondary border border-theme-border'
                        : 'bg-theme-warning-bg text-theme-warning'
                    }`}>
                      {contract.status}
                    </span>
                  </div>
                  <div className="flex items-center gap-2 text-xs text-theme-secondary flex-shrink-0">
                    <span>{contract.risk_tiers?.length || 0} tiers</span>
                    {contract.repository && (
                      <span className="font-mono">{contract.repository.name}</span>
                    )}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {expandedCard === 'runs' && (
        <div className="card-theme p-4 space-y-3">
          <div className="flex items-center justify-between">
            <h4 className="text-sm font-semibold text-theme-primary">Active Runs</h4>
            <button onClick={() => onNavigateTab?.('runs')} className="text-xs text-theme-accent hover:underline">
              View All
            </button>
          </div>
          {activeRuns.length === 0 ? (
            <div className="text-xs text-theme-secondary text-center py-2">No active runs.</div>
          ) : (
            <div className="space-y-2">
              {activeRuns.slice(0, 5).map((run) => (
                <div key={run.id} className="bg-theme-secondary-bg rounded-lg px-3 py-2 space-y-1.5">
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <span className="text-sm font-medium text-theme-primary">PR #{run.pr_number}</span>
                      <span className="text-xs font-mono text-theme-secondary">{run.head_sha?.substring(0, 8)}</span>
                      {run.risk_tier && (
                        <span className={`text-[10px] font-medium capitalize ${
                          run.risk_tier === 'critical' ? 'text-theme-error'
                            : run.risk_tier === 'high' ? 'text-theme-warning'
                            : 'text-theme-info'
                        }`}>{run.risk_tier}</span>
                      )}
                    </div>
                    <div className="flex items-center gap-2 text-xs text-theme-secondary">
                      <span>{run.review_findings_count} findings</span>
                      {run.critical_findings_count > 0 && (
                        <span className="text-theme-error">{run.critical_findings_count} critical</span>
                      )}
                    </div>
                  </div>
                  <MiniProgressBar status={run.status} />
                  <div className="flex items-center gap-3 text-[10px] text-theme-secondary">
                    <span className="capitalize">{run.status.replace(/_/g, ' ')}</span>
                    <span>{run.remediation_attempts} remediations</span>
                    {run.risk_contract && <span className="text-theme-accent">{run.risk_contract.name}</span>}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {expandedCard === 'sla' && slaCompliance && (
        <div className="card-theme p-4 space-y-3">
          <div className="flex items-center justify-between">
            <h4 className="text-sm font-semibold text-theme-primary">SLA Status</h4>
            <button onClick={() => onNavigateTab?.('harness-gaps')} className="text-xs text-theme-accent hover:underline">
              View Gaps
            </button>
          </div>
          {/* SLA Bar */}
          <div>
            <div className="flex items-center justify-between text-xs mb-1">
              <span className="text-theme-secondary">Compliance Rate</span>
              <span className={slaRate >= 90 ? 'text-theme-success' : slaRate >= 70 ? 'text-theme-warning' : 'text-theme-error'}>
                {slaRate.toFixed(1)}%
              </span>
            </div>
            <div className="h-2 bg-theme-tertiary-bg rounded-full overflow-hidden">
              <div
                className={`h-full rounded-full transition-all ${
                  slaRate >= 90 ? 'bg-theme-success' : slaRate >= 70 ? 'bg-theme-warning' : 'bg-theme-error'
                }`}
                style={{ width: `${Math.min(slaRate, 100)}%` }}
              />
            </div>
          </div>
          {/* Overdue Items */}
          {slaCompliance.past_sla_count > 0 ? (
            <div className="space-y-1.5">
              <div className="text-xs font-medium text-theme-error">
                {slaCompliance.past_sla_count} gap(s) past SLA
              </div>
              {slaCompliance.past_sla_gaps.slice(0, 5).map((g) => (
                <div key={g.id} className="flex items-center gap-2 bg-theme-error-bg rounded px-2 py-1.5">
                  <span className="text-xs font-mono text-theme-primary">{g.incident_id}</span>
                  <span className={`px-1.5 py-0.5 rounded text-[10px] ${severityColors[g.severity] || ''}`}>
                    {g.severity}
                  </span>
                  <span className="text-xs text-theme-error ml-auto">{g.hours_overdue.toFixed(0)}h overdue</span>
                </div>
              ))}
            </div>
          ) : (
            <div className="text-xs text-theme-success text-center py-1">All gaps within SLA</div>
          )}
          {/* Gap Breakdown */}
          {gapMetrics && (
            <div className="grid grid-cols-4 gap-2 pt-1">
              <div className="text-center">
                <div className="text-sm font-semibold text-theme-primary">{gapMetrics.total}</div>
                <div className="text-[10px] text-theme-secondary">Total</div>
              </div>
              <div className="text-center">
                <div className="text-sm font-semibold text-theme-error">{gapMetrics.open}</div>
                <div className="text-[10px] text-theme-secondary">Open</div>
              </div>
              <div className="text-center">
                <div className="text-sm font-semibold text-theme-info">{gapMetrics.in_progress}</div>
                <div className="text-[10px] text-theme-secondary">In Progress</div>
              </div>
              <div className="text-center">
                <div className="text-sm font-semibold text-theme-success">{gapMetrics.closed}</div>
                <div className="text-[10px] text-theme-secondary">Closed</div>
              </div>
            </div>
          )}
        </div>
      )}

      {expandedCard === 'gaps' && (
        <div className="card-theme p-4 space-y-3">
          <div className="flex items-center justify-between">
            <h4 className="text-sm font-semibold text-theme-primary">Open Harness Gaps</h4>
            <button onClick={() => onNavigateTab?.('harness-gaps')} className="text-xs text-theme-accent hover:underline">
              View All
            </button>
          </div>
          {openGaps.length === 0 ? (
            <div className="text-xs text-theme-success text-center py-2">No open gaps</div>
          ) : (
            <>
              {/* Severity Breakdown */}
              {gapMetrics?.by_severity && Object.keys(gapMetrics.by_severity).length > 0 && (
                <div className="flex items-center gap-2">
                  {Object.entries(gapMetrics.by_severity).map(([sev, count]) => (
                    <span key={sev} className={`px-2 py-0.5 rounded text-xs ${severityColors[sev] || ''}`}>
                      {sev}: {count}
                    </span>
                  ))}
                </div>
              )}
              {/* Gap List */}
              <div className="space-y-1.5">
                {openGaps.slice(0, 5).map((gap) => {
                  const sla = gap.sla_deadline
                    ? (() => {
                        const diff = new Date(gap.sla_deadline).getTime() - Date.now();
                        const hours = Math.abs(diff) / (1000 * 60 * 60);
                        if (diff < 0) return { text: `${hours.toFixed(0)}h overdue`, overdue: true };
                        if (hours < 24) return { text: `${hours.toFixed(0)}h left`, overdue: false };
                        return { text: `${(hours / 24).toFixed(0)}d left`, overdue: false };
                      })()
                    : null;

                  return (
                    <div key={gap.id} className="flex items-center gap-2 bg-theme-secondary-bg rounded px-3 py-2">
                      <span className={`px-1.5 py-0.5 rounded text-[10px] font-medium ${severityColors[gap.severity] || ''}`}>
                        {gap.severity}
                      </span>
                      <span className="text-xs font-mono text-theme-primary">{gap.incident_id}</span>
                      <span className="text-xs text-theme-secondary truncate flex-1">{gap.description}</span>
                      {gap.test_case_added && (
                        <span className="text-[10px] text-theme-success">{'\u2713'} Test</span>
                      )}
                      {sla && (
                        <span className={`text-[10px] flex-shrink-0 ${sla.overdue ? 'text-theme-error font-medium' : 'text-theme-secondary'}`}>
                          {sla.text}
                        </span>
                      )}
                    </div>
                  );
                })}
                {openGaps.length > 5 && (
                  <div className="text-[10px] text-theme-secondary text-center pt-1">
                    +{openGaps.length - 5} more
                  </div>
                )}
              </div>
            </>
          )}
        </div>
      )}
    </div>
  );
};

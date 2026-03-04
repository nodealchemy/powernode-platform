import React, { useState, useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import {
  Shield, AlertTriangle, CheckCircle, Clock, Plus, ShieldCheck,
  FileText, Eye, Radio, Gauge, Users
} from 'lucide-react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { useNotifications } from '@/shared/hooks/useNotifications';
import {
  governanceApi,
  CompliancePolicy,
  PolicyViolation,
  ApprovalChain,
  ApprovalRequest,
  GovernanceReport,
  CollusionIndicator,
} from '@/shared/services/ai/GovernanceApiService';
import { intelligenceApi } from '@/shared/services/ai/IntelligenceApiService';
import type { StigmergicSignal, PressureField, TeamRestructureEvent, CoordinationSummary } from '@/shared/services/ai/IntelligenceApiService';
import { SecurityContent } from '@/features/ai/security/pages/SecurityDashboardPage';
import { AuditLogList } from '@/features/ai/audit/components/AuditLogList';

function getSeverityColor(severity: string): string {
  switch (severity) {
    case 'critical': return 'text-theme-error bg-theme-error/10';
    case 'high': case 'medium': return 'text-theme-warning bg-theme-warning/10';
    case 'low': return 'text-theme-info bg-theme-info/10';
    default: return 'text-theme-secondary bg-theme-surface';
  }
}

function getStatusColor(status: string): string {
  switch (status) {
    case 'active': return 'text-theme-success bg-theme-success/10';
    case 'disabled': return 'text-theme-error bg-theme-error/10';
    default: return 'text-theme-secondary bg-theme-surface';
  }
}

const PoliciesContent: React.FC<{ policies: CompliancePolicy[]; loading: boolean }> = ({ policies, loading }) => {
  if (loading) return <LoadingSpinner size="sm" className="py-8" />;
  if (policies.length === 0) {
    return (
      <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
        <Shield size={48} className="mx-auto text-theme-secondary mb-4" />
        <h3 className="text-lg font-semibold text-theme-primary mb-2">No policies configured</h3>
        <p className="text-theme-secondary">Create compliance policies to govern AI operations</p>
      </div>
    );
  }
  return (
    <div className="space-y-4">
      {policies.map(policy => (
        <div key={policy.id} data-testid="policy-card" className="bg-theme-surface border border-theme rounded-lg p-4">
          <div className="flex items-center justify-between mb-2">
            <div className="flex items-center gap-3">
              <h3 className="font-medium text-theme-primary">{policy.name}</h3>
              <span className={`px-2 py-1 text-xs rounded ${getStatusColor(policy.status)}`}>{policy.status}</span>
              <span className="px-2 py-1 text-xs bg-theme-interactive-primary/10 text-theme-interactive-primary rounded">{policy.enforcement_level}</span>
            </div>
            <span className="text-sm text-theme-secondary">{policy.violation_count} violations</span>
          </div>
          <p className="text-sm text-theme-secondary">{policy.description}</p>
        </div>
      ))}
    </div>
  );
};

const ViolationsContent: React.FC<{ violations: PolicyViolation[]; loading: boolean }> = ({ violations, loading }) => {
  if (loading) return <LoadingSpinner size="sm" className="py-8" />;
  if (violations.length === 0) {
    return (
      <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
        <CheckCircle size={48} className="mx-auto text-theme-success mb-4" />
        <h3 className="text-lg font-semibold text-theme-primary mb-2">No violations</h3>
        <p className="text-theme-secondary">All AI operations are compliant</p>
      </div>
    );
  }
  return (
    <div className="space-y-4">
      {violations.map(violation => (
        <div key={violation.id} className="bg-theme-surface border border-theme rounded-lg p-4">
          <div className="flex items-center justify-between mb-2">
            <div className="flex items-center gap-3">
              <span className={`px-2 py-1 text-xs rounded ${getSeverityColor(violation.severity)}`}>{violation.severity.toUpperCase()}</span>
              <span className="text-sm text-theme-secondary">{violation.violation_id}</span>
            </div>
            <span className="text-sm text-theme-secondary">{violation.status}</span>
          </div>
          <p className="text-sm text-theme-primary mb-2">{violation.description}</p>
          <p className="text-xs text-theme-secondary">Policy: {violation.policy.name}</p>
        </div>
      ))}
    </div>
  );
};

const ApprovalsContent: React.FC<{
  pendingApprovals: ApprovalRequest[];
  approvalChains: ApprovalChain[];
  loading: boolean;
  onDecision: (requestId: string, decision: 'approved' | 'rejected') => void;
}> = ({ pendingApprovals, approvalChains, loading, onDecision }) => {
  if (loading) return <LoadingSpinner size="sm" className="py-8" />;
  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Pending Approvals</h3>
        {pendingApprovals.length === 0 ? (
          <div className="text-center py-8 bg-theme-surface border border-theme rounded-lg">
            <CheckCircle size={32} className="mx-auto text-theme-success mb-2" />
            <p className="text-theme-secondary">No pending approvals</p>
          </div>
        ) : (
          <div className="space-y-4">
            {pendingApprovals.map(request => (
              <div key={request.id} className="bg-theme-surface border border-theme rounded-lg p-4">
                <div className="flex items-center justify-between mb-2">
                  <span className="font-medium text-theme-primary">{request.request_id}</span>
                  <div className="flex gap-2">
                    <button onClick={() => onDecision(request.id, 'approved')} className="btn-theme btn-theme-success btn-theme-sm">Approve</button>
                    <button onClick={() => onDecision(request.id, 'rejected')} className="btn-theme btn-theme-danger btn-theme-sm">Reject</button>
                  </div>
                </div>
                <p className="text-sm text-theme-secondary">{request.description}</p>
              </div>
            ))}
          </div>
        )}
      </div>
      <div>
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Approval Chains</h3>
        {approvalChains.length === 0 ? (
          <div className="text-center py-8 bg-theme-surface border border-theme rounded-lg">
            <p className="text-theme-secondary">No approval chains configured</p>
          </div>
        ) : (
          <div className="space-y-4">
            {approvalChains.map(chain => (
              <div key={chain.id} className="bg-theme-surface border border-theme rounded-lg p-4">
                <div className="flex items-center justify-between">
                  <h4 className="font-medium text-theme-primary">{chain.name}</h4>
                  <span className={`px-2 py-1 text-xs rounded ${getStatusColor(chain.status)}`}>{chain.status}</span>
                </div>
                <p className="text-sm text-theme-secondary mt-1">{chain.description}</p>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};

function getReportTypeColor(type: string): string {
  switch (type) {
    case 'collusion_suspicion': return 'text-theme-error bg-theme-error/10';
    case 'safety_concern': return 'text-theme-error bg-theme-error/10';
    case 'policy_violation': return 'text-theme-warning bg-theme-warning/10';
    case 'anomaly': return 'text-theme-warning bg-theme-warning/10';
    case 'resource_abuse': return 'text-theme-warning bg-theme-warning/10';
    case 'pattern_drift': return 'text-theme-info bg-theme-info/10';
    default: return 'text-theme-secondary bg-theme-surface';
  }
}

function getCollusionTypeLabel(type: string): string {
  switch (type) {
    case 'synchronized_output': return 'Synchronized Output';
    case 'mutual_approval': return 'Mutual Approval';
    case 'resource_hoarding': return 'Resource Hoarding';
    case 'trust_inflation': return 'Trust Inflation';
    case 'echo_chamber': return 'Echo Chamber';
    default: return type;
  }
}

const ReportsContent: React.FC<{ reports: GovernanceReport[]; loading: boolean; onResolve: (id: string) => void }> = ({ reports, loading, onResolve }) => {
  if (loading) return <LoadingSpinner size="sm" className="py-8" />;
  if (reports.length === 0) {
    return (
      <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
        <FileText size={48} className="mx-auto text-theme-success mb-4" />
        <h3 className="text-lg font-semibold text-theme-primary mb-2">No governance reports</h3>
        <p className="text-theme-secondary">Automated governance scans have not detected any issues</p>
      </div>
    );
  }
  return (
    <div className="space-y-4">
      {reports.map(report => (
        <div key={report.id} data-testid="report-card" className="bg-theme-surface border border-theme rounded-lg p-4">
          <div className="flex items-center justify-between mb-2">
            <div className="flex items-center gap-3">
              <span className={`px-2 py-1 text-xs rounded ${getSeverityColor(report.severity)}`}>{report.severity.toUpperCase()}</span>
              <span className={`px-2 py-1 text-xs rounded ${getReportTypeColor(report.report_type)}`}>{report.report_type.replace(/_/g, ' ')}</span>
              <span className={`px-2 py-1 text-xs rounded ${getStatusColor(report.status === 'open' || report.status === 'investigating' ? 'active' : 'disabled')}`}>{report.status}</span>
            </div>
            <div className="flex items-center gap-3">
              {report.confidence_score !== null && (
                <span className="text-xs text-theme-secondary">Confidence: {(report.confidence_score * 100).toFixed(0)}%</span>
              )}
              {(report.status === 'open' || report.status === 'confirmed') && (
                <button onClick={() => onResolve(report.id)} className="btn-theme btn-theme-sm btn-theme-success">Resolve</button>
              )}
            </div>
          </div>
          <div className="flex items-center gap-4 text-sm text-theme-secondary">
            {report.subject_agent && <span>Agent: <span className="text-theme-primary">{report.subject_agent.name}</span></span>}
            {report.monitor_agent && <span>Detected by: {report.monitor_agent.name}</span>}
            {report.auto_remediated && <span className="text-theme-success">Auto-remediated</span>}
            <span>{new Date(report.created_at).toLocaleDateString()}</span>
          </div>
        </div>
      ))}
    </div>
  );
};

const CollusionContent: React.FC<{ indicators: CollusionIndicator[]; loading: boolean }> = ({ indicators, loading }) => {
  if (loading) return <LoadingSpinner size="sm" className="py-8" />;
  if (indicators.length === 0) {
    return (
      <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
        <Eye size={48} className="mx-auto text-theme-success mb-4" />
        <h3 className="text-lg font-semibold text-theme-primary mb-2">No collusion indicators</h3>
        <p className="text-theme-secondary">Multi-agent collusion detection has not found suspicious patterns</p>
      </div>
    );
  }
  return (
    <div className="space-y-4">
      {indicators.map(indicator => (
        <div key={indicator.id} data-testid="collusion-card" className="bg-theme-surface border border-theme rounded-lg p-4">
          <div className="flex items-center justify-between mb-2">
            <div className="flex items-center gap-3">
              <span className={`px-2 py-1 text-xs rounded ${indicator.correlation_score >= 0.7 ? 'text-theme-error bg-theme-error/10' : 'text-theme-warning bg-theme-warning/10'}`}>
                {(indicator.correlation_score * 100).toFixed(0)}% correlation
              </span>
              <span className="font-medium text-theme-primary">{getCollusionTypeLabel(indicator.indicator_type)}</span>
            </div>
            <span className="text-sm text-theme-secondary">{new Date(indicator.created_at).toLocaleDateString()}</span>
          </div>
          {indicator.agent_cluster.length > 0 && (
            <div className="flex items-center gap-2 mt-2">
              <span className="text-xs text-theme-secondary">Agents involved:</span>
              <div className="flex flex-wrap gap-1">
                {indicator.agent_cluster.map((agentId, idx) => (
                  <span key={idx} className="px-2 py-0.5 text-xs bg-theme-interactive-primary/10 text-theme-interactive-primary rounded">
                    {typeof agentId === 'string' ? agentId.slice(0, 8) : agentId}
                  </span>
                ))}
              </div>
            </div>
          )}
        </div>
      ))}
    </div>
  );
};

// ---- Coordination Tab Content ----
const getSignalTypeColor = (t: string) => {
  switch (t) {
    case 'pheromone': return 'success';
    case 'pressure': return 'warning';
    case 'beacon': return 'info';
    case 'warning': return 'danger';
    case 'discovery': return 'primary';
    default: return 'secondary';
  }
};

const getFieldTypeLabel = (t: string) => t.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase());

const CoordinationContent: React.FC<{
  coordSummary: CoordinationSummary | null;
  signals: StigmergicSignal[];
  pressureFields: PressureField[];
  teamEvents: TeamRestructureEvent[];
  loading: boolean;
}> = ({ coordSummary, signals, pressureFields, teamEvents, loading }) => {
  if (loading) return <LoadingSpinner size="sm" className="py-8" />;

  return (
    <div className="space-y-6">
      {/* Summary */}
      {coordSummary && (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <Card className="p-4 text-center">
            <div className="text-2xl font-bold text-theme-success">{coordSummary.signals.active}</div>
            <div className="text-xs text-theme-tertiary">Active Signals</div>
            <div className="text-xs text-theme-secondary mt-1">{coordSummary.signals.fading} fading</div>
          </Card>
          <Card className="p-4 text-center">
            <div className="text-2xl font-bold text-theme-warning">{coordSummary.pressure_fields.actionable}</div>
            <div className="text-xs text-theme-tertiary">Actionable Pressures</div>
            <div className="text-xs text-theme-secondary mt-1">Avg: {(coordSummary.pressure_fields.avg_pressure * 100).toFixed(0)}%</div>
          </Card>
          <Card className="p-4 text-center">
            <div className="text-2xl font-bold text-theme-primary">{coordSummary.pressure_fields.total}</div>
            <div className="text-xs text-theme-tertiary">Pressure Fields</div>
          </Card>
          <Card className="p-4 text-center">
            <div className="text-2xl font-bold text-theme-info">{coordSummary.team_events.recent_24h}</div>
            <div className="text-xs text-theme-tertiary">Team Events (24h)</div>
            <div className="text-xs text-theme-secondary mt-1">{coordSummary.team_events.total} total</div>
          </Card>
        </div>
      )}

      {/* Stigmergic Signals */}
      <Card className="p-6">
        <div className="flex items-center gap-2 mb-4">
          <Radio size={18} className="text-theme-success" />
          <h3 className="text-lg font-medium text-theme-primary">Stigmergic Signals</h3>
          <Badge variant="secondary" size="sm">{signals.length}</Badge>
        </div>
        {signals.length === 0 ? (
          <p className="text-sm text-theme-tertiary">No active signals. Agents emit signals to coordinate behavior indirectly.</p>
        ) : (
          <div className="space-y-3">
            {signals.map(s => (
              <div key={s.id} className="border border-theme-border rounded-lg p-3">
                <div className="flex items-center justify-between mb-2">
                  <div className="flex items-center gap-2">
                    <Badge variant={getSignalTypeColor(s.signal_type) as 'success' | 'warning' | 'info' | 'danger'} size="sm">{s.signal_type}</Badge>
                    <span className="text-sm font-medium text-theme-primary">{s.signal_key}</span>
                  </div>
                  <div className="flex items-center gap-3 text-xs">
                    <span className="text-theme-secondary">Strength: <strong>{(s.strength * 100).toFixed(0)}%</strong></span>
                    <span className="text-theme-tertiary">{s.reinforce_count} reinforced</span>
                    <span className="text-theme-tertiary">{s.perceive_count} perceived</span>
                  </div>
                </div>
                {s.emitter_agent && <span className="text-xs text-theme-info">Emitted by {s.emitter_agent.name}</span>}
                {/* Strength bar */}
                <div className="mt-2 h-1.5 bg-theme-surface-secondary rounded-full overflow-hidden">
                  <div className="h-full bg-theme-success rounded-full transition-all" style={{ width: `${s.strength * 100}%` }} />
                </div>
              </div>
            ))}
          </div>
        )}
      </Card>

      {/* Pressure Fields */}
      <Card className="p-6">
        <div className="flex items-center gap-2 mb-4">
          <Gauge size={18} className="text-theme-warning" />
          <h3 className="text-lg font-medium text-theme-primary">Pressure Fields</h3>
          <Badge variant="secondary" size="sm">{pressureFields.length}</Badge>
        </div>
        {pressureFields.length === 0 ? (
          <p className="text-sm text-theme-tertiary">No pressure fields measured. Fields detect quality gradients that guide agent behavior.</p>
        ) : (
          <div className="space-y-3">
            {pressureFields.map(f => (
              <div key={f.id} className="border border-theme-border rounded-lg p-3">
                <div className="flex items-center justify-between mb-2">
                  <div className="flex items-center gap-2">
                    <Badge variant={f.actionable ? 'warning' : 'secondary'} size="sm">{getFieldTypeLabel(f.field_type)}</Badge>
                    <span className="text-sm text-theme-primary">{f.artifact_ref}</span>
                  </div>
                  <div className="flex items-center gap-3 text-xs">
                    <span className={f.actionable ? 'text-theme-warning font-medium' : 'text-theme-secondary'}>
                      Pressure: {(f.pressure_value * 100).toFixed(0)}%
                    </span>
                    <span className="text-theme-tertiary">Threshold: {(f.threshold * 100).toFixed(0)}%</span>
                    <span className="text-theme-tertiary">Addressed {f.address_count}x</span>
                  </div>
                </div>
                <div className="mt-2 h-1.5 bg-theme-surface-secondary rounded-full overflow-hidden relative">
                  <div className="h-full rounded-full transition-all" style={{
                    width: `${f.pressure_value * 100}%`,
                    backgroundColor: f.actionable ? 'var(--color-warning)' : 'var(--color-info)'
                  }} />
                  {/* Threshold marker */}
                  <div className="absolute top-0 h-full w-0.5 bg-theme-error" style={{ left: `${f.threshold * 100}%` }} />
                </div>
              </div>
            ))}
          </div>
        )}
      </Card>

      {/* Team Restructure Events */}
      <Card className="p-6">
        <div className="flex items-center gap-2 mb-4">
          <Users size={18} className="text-theme-info" />
          <h3 className="text-lg font-medium text-theme-primary">Team Restructure Events</h3>
          <Badge variant="secondary" size="sm">{teamEvents.length}</Badge>
        </div>
        {teamEvents.length === 0 ? (
          <p className="text-sm text-theme-tertiary">No team restructure events. Events occur when teams dynamically adapt their structure.</p>
        ) : (
          <div className="space-y-3">
            {teamEvents.map(e => (
              <div key={e.id} className="border border-theme-border rounded-lg p-3">
                <div className="flex items-center justify-between mb-2">
                  <div className="flex items-center gap-2">
                    <Badge variant="info" size="sm">{e.event_type.replace(/_/g, ' ')}</Badge>
                    {e.team && <span className="text-sm text-theme-primary">{e.team.name}</span>}
                    {e.agent && <span className="text-xs text-theme-secondary">({e.agent.name})</span>}
                  </div>
                  <span className="text-xs text-theme-tertiary">{new Date(e.created_at).toLocaleDateString()}</span>
                </div>
                {e.rationale && Object.keys(e.rationale).length > 0 && (
                  <p className="text-xs text-theme-secondary">{JSON.stringify(e.rationale).slice(0, 200)}</p>
                )}
              </div>
            ))}
          </div>
        )}
      </Card>
    </div>
  );
};

const governanceTabs = [
  { id: 'policies', label: 'Policies', icon: <Shield size={16} />, path: '/' },
  { id: 'violations', label: 'Violations', icon: <AlertTriangle size={16} />, path: '/violations' },
  { id: 'approvals', label: 'Approvals', icon: <CheckCircle size={16} />, path: '/approvals' },
  { id: 'reports', label: 'Reports', icon: <FileText size={16} />, path: '/reports' },
  { id: 'collusion', label: 'Collusion', icon: <Eye size={16} />, path: '/collusion' },
  { id: 'coordination', label: 'Coordination', icon: <Radio size={16} />, path: '/coordination' },
  { id: 'security', label: 'Security', icon: <ShieldCheck size={16} />, path: '/security' },
  { id: 'audit', label: 'Audit Log', icon: <Clock size={16} />, path: '/audit' },
];

export const GovernancePage: React.FC = () => {
  const location = useLocation();
  const { addNotification } = useNotifications();
  const queryClient = useQueryClient();

  const getActiveTab = () => {
    const path = location.pathname;
    if (path.includes('/governance/violations')) return 'violations';
    if (path.includes('/governance/approvals')) return 'approvals';
    if (path.includes('/governance/reports')) return 'reports';
    if (path.includes('/governance/collusion')) return 'collusion';
    if (path.includes('/governance/coordination')) return 'coordination';
    if (path.includes('/governance/security')) return 'security';
    if (path.includes('/governance/audit')) return 'audit';
    return 'policies';
  };

  const [activeTab, setActiveTab] = useState(getActiveTab());

  useEffect(() => {
    const newTab = getActiveTab();
    if (newTab !== activeTab) setActiveTab(newTab);
  }, [location.pathname]);

  const { data, isLoading, refetch } = useQuery({
    queryKey: ['governance'],
    queryFn: async () => {
      const [policiesRes, violationsRes, chainsRes, pendingRes, summaryRes, reportsRes, collusionRes, coordSummaryRes, signalsRes, fieldsRes, eventsRes] = await Promise.all([
        governanceApi.getPolicies(),
        governanceApi.getViolations(),
        governanceApi.getApprovalChains(),
        governanceApi.getPendingApprovals(),
        governanceApi.getSummary(),
        governanceApi.getGovernanceReports().catch(() => ({ items: [] })),
        governanceApi.getCollusionIndicators().catch(() => ({ items: [] })),
        intelligenceApi.getCoordinationSummary().catch(() => ({ summary: null })),
        intelligenceApi.getSignals({ active: 'true' }).catch(() => ({ items: [] })),
        intelligenceApi.getPressureFields().catch(() => ({ items: [] })),
        intelligenceApi.getTeamEvents().catch(() => ({ items: [] })),
      ]);
      return {
        policies: policiesRes.items || [],
        violations: violationsRes.items || [],
        approvalChains: chainsRes.items || [],
        pendingApprovals: pendingRes.approval_requests || [],
        summary: summaryRes.summary || null,
        reports: reportsRes.items || [],
        collusionIndicators: collusionRes.items || [],
        coordSummary: coordSummaryRes.summary || null,
        signals: signalsRes.items || [],
        pressureFields: fieldsRes.items || [],
        teamEvents: eventsRes.items || [],
      };
    },
  });

  const decisionMutation = useMutation({
    mutationFn: ({ requestId, decision }: { requestId: string; decision: 'approved' | 'rejected' }) =>
      governanceApi.decideApproval(requestId, { decision }),
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: ['governance'] });
      addNotification({ type: 'success', message: `Request ${variables.decision}` });
    },
    onError: () => {
      addNotification({ type: 'error', message: 'Failed to process approval' });
    },
  });

  const resolveMutation = useMutation({
    mutationFn: (reportId: string) =>
      governanceApi.resolveGovernanceReport(reportId, { resolution_status: 'remediated' }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['governance'] });
      addNotification({ type: 'success', message: 'Report resolved' });
    },
    onError: () => {
      addNotification({ type: 'error', message: 'Failed to resolve report' });
    },
  });

  usePageWebSocket({ pageType: 'ai', onDataUpdate: () => { refetch(); } });
  const { refreshAction } = useRefreshAction({ onRefresh: () => { refetch(); }, loading: isLoading });

  const summary = data?.summary;
  const securityScore = summary
    ? (summary.violations.total > 0
      ? Math.round(((summary.violations.total - summary.violations.open) / summary.violations.total) * 100)
      : 100)
    : null;

  const getBreadcrumbs = () => {
    const base: Array<{ label: string; href?: string }> = [
      { label: 'Dashboard', href: '/app' },
      { label: 'AI', href: '/app/ai' },
    ];
    const activeTabInfo = governanceTabs.find(t => t.id === activeTab);
    if (activeTab === 'policies') {
      base.push({ label: 'Governance' });
    } else {
      base.push({ label: 'Governance', href: '/app/ai/governance' });
      if (activeTabInfo) base.push({ label: activeTabInfo.label });
    }
    return base;
  };

  return (
    <PageContainer
      title="Governance & Compliance"
      description="Compliance policies, approval workflows, security, and audit logging for AI operations"
      breadcrumbs={getBreadcrumbs()}
      actions={[
        refreshAction,
        { id: 'create-policy', label: 'Create Policy', onClick: () => {}, icon: Plus, variant: 'primary' as const },
      ]}
    >
      {summary && !isLoading && (
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
          <Card className="p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-tertiary">Total Policies</p>
                <p className="text-2xl font-semibold text-theme-primary">{summary.policies.total}</p>
              </div>
              <div className="h-10 w-10 bg-theme-interactive-primary bg-opacity-10 rounded-lg flex items-center justify-center">
                <Shield className="h-5 w-5 text-theme-interactive-primary" />
              </div>
            </div>
            <p className="text-xs text-theme-tertiary mt-2">{summary.policies.active} active</p>
          </Card>
          <Card className="p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-tertiary">Active Violations</p>
                <p className="text-2xl font-semibold text-theme-error">{summary.violations.open}</p>
              </div>
              <div className="h-10 w-10 bg-theme-error bg-opacity-10 rounded-lg flex items-center justify-center">
                <AlertTriangle className="h-5 w-5 text-theme-error" />
              </div>
            </div>
            <p className="text-xs text-theme-tertiary mt-2">{summary.violations.total} total</p>
          </Card>
          <Card className="p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-tertiary">Pending Approvals</p>
                <p className="text-2xl font-semibold text-theme-warning">{summary.approvals.pending}</p>
              </div>
              <div className="h-10 w-10 bg-theme-warning bg-opacity-10 rounded-lg flex items-center justify-center">
                <Clock className="h-5 w-5 text-theme-warning" />
              </div>
            </div>
            <p className="text-xs text-theme-tertiary mt-2">{summary.approvals.approved} approved</p>
          </Card>
          <Card className="p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-tertiary">Security Score</p>
                <p className="text-2xl font-semibold text-theme-success">{securityScore}%</p>
              </div>
              <div className="h-10 w-10 bg-theme-success bg-opacity-10 rounded-lg flex items-center justify-center">
                <ShieldCheck className="h-5 w-5 text-theme-success" />
              </div>
            </div>
            <p className="text-xs text-theme-tertiary mt-2">{summary.violations.total - summary.violations.open} resolved</p>
          </Card>
        </div>
      )}

      <TabContainer
        tabs={governanceTabs}
        activeTab={activeTab}
        onTabChange={setActiveTab}
        basePath="/app/ai/governance"
        variant="underline"
      >
        <TabPanel tabId="policies" activeTab={activeTab}>
          <PoliciesContent policies={data?.policies || []} loading={isLoading} />
        </TabPanel>
        <TabPanel tabId="violations" activeTab={activeTab}>
          <ViolationsContent violations={data?.violations || []} loading={isLoading} />
        </TabPanel>
        <TabPanel tabId="approvals" activeTab={activeTab}>
          <ApprovalsContent
            pendingApprovals={data?.pendingApprovals || []}
            approvalChains={data?.approvalChains || []}
            loading={isLoading}
            onDecision={(requestId, decision) => decisionMutation.mutate({ requestId, decision })}
          />
        </TabPanel>
        <TabPanel tabId="reports" activeTab={activeTab}>
          <ReportsContent
            reports={data?.reports || []}
            loading={isLoading}
            onResolve={(id) => resolveMutation.mutate(id)}
          />
        </TabPanel>
        <TabPanel tabId="collusion" activeTab={activeTab}>
          <CollusionContent indicators={data?.collusionIndicators || []} loading={isLoading} />
        </TabPanel>
        <TabPanel tabId="coordination" activeTab={activeTab}>
          <CoordinationContent
            coordSummary={data?.coordSummary || null}
            signals={data?.signals || []}
            pressureFields={data?.pressureFields || []}
            teamEvents={data?.teamEvents || []}
            loading={isLoading}
          />
        </TabPanel>
        <TabPanel tabId="security" activeTab={activeTab}>
          <SecurityContent />
        </TabPanel>
        <TabPanel tabId="audit" activeTab={activeTab}>
          <AuditLogList />
        </TabPanel>
      </TabContainer>
    </PageContainer>
  );
};

export default GovernancePage;

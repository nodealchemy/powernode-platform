import React from 'react';
import { FileText } from 'lucide-react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { EntityLink } from '@/shared/components/entity';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { governanceApi, GovernanceReport } from '@/shared/services/ai/GovernanceApiService';

export const GOVERNANCE_REPORTS_QUERY_KEY = ['control', 'governance-reports'] as const;

function getSeverityColor(severity: string): string {
  switch (severity) {
    case 'critical': return 'text-theme-error-fg bg-theme-error-fg/10';
    case 'high': case 'medium': return 'text-theme-warning-fg bg-theme-warning-fg/10';
    case 'low': return 'text-theme-info-fg bg-theme-info-fg/10';
    default: return 'text-theme-secondary bg-theme-surface';
  }
}

function getStatusColor(status: string): string {
  switch (status) {
    case 'active': return 'text-theme-success-fg bg-theme-success-fg/10';
    case 'disabled': return 'text-theme-error-fg bg-theme-error-fg/10';
    default: return 'text-theme-secondary bg-theme-surface';
  }
}

function getReportTypeColor(type: string): string {
  switch (type) {
    case 'collusion_suspicion': return 'text-theme-error-fg bg-theme-error-fg/10';
    case 'safety_concern': return 'text-theme-error-fg bg-theme-error-fg/10';
    case 'policy_violation': return 'text-theme-warning-fg bg-theme-warning-fg/10';
    case 'anomaly': return 'text-theme-warning-fg bg-theme-warning-fg/10';
    case 'resource_abuse': return 'text-theme-warning-fg bg-theme-warning-fg/10';
    case 'pattern_drift': return 'text-theme-info-fg bg-theme-info-fg/10';
    default: return 'text-theme-secondary bg-theme-surface';
  }
}

const ReportsContent: React.FC<{
  reports: GovernanceReport[];
  loading: boolean;
  canResolve: boolean;
  onResolve: (id: string) => void;
}> = ({ reports, loading, canResolve, onResolve }) => {
  if (loading) return <LoadingSpinner size="sm" className="py-8" />;
  if (reports.length === 0) {
    return (
      <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
        <FileText size={48} className="mx-auto text-theme-success-fg mb-4" />
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
              {canResolve && (report.status === 'open' || report.status === 'confirmed') && (
                <button onClick={() => onResolve(report.id)} className="btn-theme btn-theme-sm btn-theme-success">Resolve</button>
              )}
            </div>
          </div>
          <div className="flex items-center gap-4 text-sm text-theme-secondary">
            {report.subject_agent && <span>Agent: <EntityLink type="agent" id={report.subject_agent.id} label={report.subject_agent.name} /></span>}
            {report.monitor_agent && <span>Detected by: <EntityLink type="agent" id={report.monitor_agent.id} label={report.monitor_agent.name} /></span>}
            {report.auto_remediated && <span className="text-theme-success-fg">Auto-remediated</span>}
            <span>{new Date(report.created_at).toLocaleDateString()}</span>
          </div>
        </div>
      ))}
    </div>
  );
};

/**
 * Governance scan results (Compliance Audit → Reports). Reading needs
 * ai.governance.read; resolving is a write the server gates on
 * ai.governance.manage, so the action is only offered to its holders.
 */
export const GovernanceReportsPanel: React.FC = () => {
  const queryClient = useQueryClient();
  const { addNotification } = useNotifications();
  const { hasPermission } = usePermissions();
  const { data: reports = [], isLoading } = useQuery({
    queryKey: GOVERNANCE_REPORTS_QUERY_KEY,
    queryFn: async () => (await governanceApi.getGovernanceReports()).items ?? [],
  });
  const resolve = useMutation({
    mutationFn: (reportId: string) =>
      governanceApi.resolveGovernanceReport(reportId, { resolution_status: 'remediated' }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: GOVERNANCE_REPORTS_QUERY_KEY });
      addNotification({ type: 'success', message: 'Report resolved' });
    },
    onError: () => addNotification({ type: 'error', message: 'Failed to resolve report' }),
  });

  return (
    <ReportsContent
      reports={reports}
      loading={isLoading}
      canResolve={hasPermission('ai.governance.manage')}
      onResolve={(id) => resolve.mutate(id)}
    />
  );
};

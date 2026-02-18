import React, { useState, useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import {
  Shield, AlertTriangle, CheckCircle, Clock, Plus, ShieldCheck
} from 'lucide-react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { Card } from '@/shared/components/ui/Card';
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
} from '@/shared/services/ai/GovernanceApiService';
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

const governanceTabs = [
  { id: 'policies', label: 'Policies', icon: <Shield size={16} />, path: '/' },
  { id: 'violations', label: 'Violations', icon: <AlertTriangle size={16} />, path: '/violations' },
  { id: 'approvals', label: 'Approvals', icon: <CheckCircle size={16} />, path: '/approvals' },
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
      const [policiesRes, violationsRes, chainsRes, pendingRes, summaryRes] = await Promise.all([
        governanceApi.getPolicies(),
        governanceApi.getViolations(),
        governanceApi.getApprovalChains(),
        governanceApi.getPendingApprovals(),
        governanceApi.getSummary(),
      ]);
      return {
        policies: policiesRes.items || [],
        violations: violationsRes.items || [],
        approvalChains: chainsRes.items || [],
        pendingApprovals: pendingRes.approval_requests || [],
        summary: summaryRes.summary || null,
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

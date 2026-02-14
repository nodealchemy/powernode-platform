// Governance Page - AI Workflow Governance & Compliance Suite
import React, { useState, useEffect } from 'react';
import { Plus, Shield, AlertTriangle, CheckCircle, Clock, FileText, Search, Filter } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { useDispatch } from 'react-redux';
import { addNotification } from '@/shared/services/slices/uiSlice';
import { AppDispatch } from '@/shared/services';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';
import {
  governanceApi,
  CompliancePolicy,
  PolicyViolation,
  ApprovalChain,
  ApprovalRequest,
  DataClassification,
  ComplianceSummary
} from '@/shared/services/ai/GovernanceApiService';

// Type guard for API errors
interface ApiErrorResponse {
  response?: {
    data?: {
      error?: string;
    };
  };
}

function isApiError(error: unknown): error is ApiErrorResponse {
  return typeof error === 'object' && error !== null && 'response' in error;
}

function getErrorMessage(error: unknown, fallback: string): string {
  if (isApiError(error)) {
    return error.response?.data?.error || fallback;
  }
  if (error instanceof Error) {
    return error.message;
  }
  return fallback;
}

type TabType = 'policies' | 'violations' | 'approvals' | 'classifications' | 'reports' | 'audit';

const GovernancePage: React.FC = () => {
  const dispatch = useDispatch<AppDispatch>();
  const [activeTab, setActiveTab] = useState<TabType>('policies');
  const [policies, setPolicies] = useState<CompliancePolicy[]>([]);
  const [violations, setViolations] = useState<PolicyViolation[]>([]);
  const [approvalChains, setApprovalChains] = useState<ApprovalChain[]>([]);
  const [pendingApprovals, setPendingApprovals] = useState<ApprovalRequest[]>([]);
  const [classifications, setClassifications] = useState<DataClassification[]>([]);
  const [summary, setSummary] = useState<ComplianceSummary | null>(null);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState<string>('all');

  // WebSocket for real-time updates
  usePageWebSocket({
    pageType: 'ai',
    onDataUpdate: () => {
      loadData();
    }
  });

  useEffect(() => {
    loadData();
  }, []);

  const loadData = async () => {
    try {
      setLoading(true);
      const [policiesRes, violationsRes, chainsRes, pendingRes, classificationsRes, summaryRes] = await Promise.all([
        governanceApi.getPolicies(),
        governanceApi.getViolations(),
        governanceApi.getApprovalChains(),
        governanceApi.getPendingApprovals(),
        governanceApi.getClassifications(),
        governanceApi.getSummary()
      ]);
      setPolicies(policiesRes.items || []);
      setViolations(violationsRes.items || []);
      setApprovalChains(chainsRes.items || []);
      setPendingApprovals(pendingRes.approval_requests || []);
      setClassifications(classificationsRes.items || []);
      setSummary(summaryRes.summary || null);
    } catch (error) {
      dispatch(addNotification({
        type: 'error',
        message: getErrorMessage(error, 'Failed to load governance data')
      }));
    } finally {
      setLoading(false);
    }
  };

  const handleApprovalDecision = async (requestId: string, decision: 'approved' | 'rejected') => {
    try {
      await governanceApi.decideApproval(requestId, { decision });
      dispatch(addNotification({
        type: 'success',
        message: `Request ${decision}`
      }));
      loadData();
    } catch (error) {
      dispatch(addNotification({
        type: 'error',
        message: getErrorMessage(error, 'Failed to process approval')
      }));
    }
  };

  const getSeverityColor = (severity: string): string => {
    switch (severity) {
      case 'critical': return 'text-theme-danger bg-theme-danger/10';
      case 'high': return 'text-theme-warning bg-theme-warning/10';
      case 'medium': return 'text-theme-warning bg-theme-warning/10';
      case 'low': return 'text-theme-info bg-theme-info/10';
      default: return 'text-theme-secondary bg-theme-surface';
    }
  };

  const getStatusColor = (status: string): string => {
    switch (status) {
      case 'active': return 'text-theme-success bg-theme-success/10';
      case 'draft': return 'text-theme-secondary bg-theme-surface';
      case 'disabled': return 'text-theme-danger bg-theme-danger/10';
      default: return 'text-theme-secondary bg-theme-surface';
    }
  };

  const { refreshAction } = useRefreshAction({
    onRefresh: loadData,
    loading,
  });

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'AI', href: '/app/ai' },
    { label: 'Governance' }
  ];

  const tabs = [
    { id: 'policies' as TabType, label: 'Policies', icon: Shield },
    { id: 'violations' as TabType, label: 'Violations', icon: AlertTriangle },
    { id: 'approvals' as TabType, label: 'Approvals', icon: CheckCircle },
    { id: 'classifications' as TabType, label: 'Classifications', icon: FileText },
    { id: 'reports' as TabType, label: 'Reports', icon: FileText },
    { id: 'audit' as TabType, label: 'Audit Log', icon: Clock }
  ];

  return (
    <PageContainer
      title="Governance & Compliance"
      description="Enterprise compliance policies, approval workflows, and audit logging for AI operations"
      breadcrumbs={breadcrumbs}
      actions={[
        refreshAction,
        {
          id: 'generate-report',
          label: 'Generate Report',
          onClick: () => {},
          icon: FileText,
          variant: 'secondary' as const
        },
        {
          id: 'create-policy',
          label: 'Create Policy',
          onClick: () => {},
          icon: Plus,
          variant: 'primary' as const
        }
      ]}
    >
      {/* Summary Cards */}
      {summary && (
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-secondary">Total Policies</p>
                <p className="text-2xl font-bold text-theme-primary">{summary.policies.total}</p>
              </div>
              <Shield className="h-8 w-8 text-theme-accent" />
            </div>
            <p className="text-xs text-theme-secondary mt-2">{summary.policies.active} Active</p>
          </div>
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-secondary">Open Violations</p>
                <p className="text-2xl font-bold text-theme-danger">{summary.violations.open}</p>
              </div>
              <AlertTriangle className="h-8 w-8 text-theme-danger" />
            </div>
            <p className="text-xs text-theme-secondary mt-2">{summary.violations.total} Total</p>
          </div>
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-secondary">Pending Approvals</p>
                <p className="text-2xl font-bold text-theme-warning">{summary.approvals.pending}</p>
              </div>
              <Clock className="h-8 w-8 text-theme-warning" />
            </div>
            <p className="text-xs text-theme-secondary mt-2">{summary.approvals.approved} Approved</p>
          </div>
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-secondary">Data Detections</p>
                <p className="text-2xl font-bold text-theme-primary">{summary.data_detections.total}</p>
              </div>
              <CheckCircle className="h-8 w-8 text-theme-success" />
            </div>
            <p className="text-xs text-theme-secondary mt-2">PII/PHI/PCI detected</p>
          </div>
        </div>
      )}

      {/* Tabs */}
      <div className="border-b border-theme mb-6">
        <nav className="flex gap-4">
          {tabs.map(tab => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`flex items-center gap-2 px-4 py-2 border-b-2 transition-colors ${
                activeTab === tab.id
                  ? 'border-theme-accent text-theme-accent'
                  : 'border-transparent text-theme-secondary hover:text-theme-primary'
              }`}
            >
              <tab.icon size={16} />
              {tab.label}
            </button>
          ))}
        </nav>
      </div>

      {/* Filters */}
      <div className="flex flex-wrap gap-4 mb-6">
        <div className="flex-1 min-w-64">
          <div className="relative">
            <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-theme-secondary" />
            <input
              type="search"
              placeholder="Search..."
              className="w-full pl-10 pr-4 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
            />
          </div>
        </div>
        <div className="flex items-center gap-2">
          <Filter size={16} className="text-theme-secondary" />
          <select
            value={statusFilter}
            onChange={(e) => setStatusFilter(e.target.value)}
            className="px-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
          >
            <option value="all">All Status</option>
            <option value="active">Active</option>
            <option value="draft">Draft</option>
            <option value="disabled">Disabled</option>
          </select>
        </div>
      </div>

      {/* Tab Content */}
      {loading ? (
        <div className="text-center py-12">
          <div className="inline-block animate-spin rounded-full h-8 w-8 border-4 border-theme-accent border-t-theme-primary"></div>
          <p className="mt-4 text-theme-secondary">Loading governance data...</p>
        </div>
      ) : (
        <>
          {/* Policies Tab */}
          {activeTab === 'policies' && (
            <div className="space-y-4">
              {policies.length === 0 ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <Shield size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No policies configured</h3>
                  <p className="text-theme-secondary mb-6">Create compliance policies to govern AI operations</p>
                </div>
              ) : (
                policies.map(policy => (
                  <div key={policy.id} data-testid="policy-card" className="bg-theme-surface border border-theme rounded-lg p-4">
                    <div className="flex items-center justify-between mb-2">
                      <div className="flex items-center gap-3">
                        <h3 className="font-medium text-theme-primary">{policy.name}</h3>
                        <span data-testid="policy-status-badge" className={`px-2 py-1 text-xs rounded ${getStatusColor(policy.status)}`}>
                          {policy.status}
                        </span>
                        <span data-testid="policy-enforcement-badge" className="px-2 py-1 text-xs bg-theme-accent/10 text-theme-accent rounded">
                          {policy.enforcement_level}
                        </span>
                      </div>
                      <span className="text-sm text-theme-secondary">{policy.violation_count} violations</span>
                    </div>
                    <p className="text-sm text-theme-secondary">{policy.description}</p>
                  </div>
                ))
              )}
            </div>
          )}

          {/* Violations Tab */}
          {activeTab === 'violations' && (
            <div className="space-y-4">
              {violations.length === 0 ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <CheckCircle size={48} className="mx-auto text-theme-success mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No violations</h3>
                  <p className="text-theme-secondary">All AI operations are compliant</p>
                </div>
              ) : (
                violations.map(violation => (
                  <div key={violation.id} className="bg-theme-surface border border-theme rounded-lg p-4">
                    <div className="flex items-center justify-between mb-2">
                      <div className="flex items-center gap-3">
                        <span className={`px-2 py-1 text-xs rounded ${getSeverityColor(violation.severity)}`}>
                          {violation.severity.toUpperCase()}
                        </span>
                        <span className="text-sm text-theme-secondary">{violation.violation_id}</span>
                      </div>
                      <span className="text-sm text-theme-secondary">{violation.status}</span>
                    </div>
                    <p className="text-sm text-theme-primary mb-2">{violation.description}</p>
                    <p className="text-xs text-theme-secondary">Policy: {violation.policy.name}</p>
                  </div>
                ))
              )}
            </div>
          )}

          {/* Approvals Tab */}
          {activeTab === 'approvals' && (
            <div className="space-y-6">
              {/* Pending Approvals */}
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
                            <button
                              onClick={() => handleApprovalDecision(request.id, 'approved')}
                              className="btn-theme btn-theme-success btn-theme-sm"
                            >
                              Approve
                            </button>
                            <button
                              onClick={() => handleApprovalDecision(request.id, 'rejected')}
                              className="btn-theme btn-theme-danger btn-theme-sm"
                            >
                              Reject
                            </button>
                          </div>
                        </div>
                        <p className="text-sm text-theme-secondary">{request.description}</p>
                      </div>
                    ))}
                  </div>
                )}
              </div>

              {/* Approval Chains */}
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
                          <span className={`px-2 py-1 text-xs rounded ${getStatusColor(chain.status)}`}>
                            {chain.status}
                          </span>
                        </div>
                        <p className="text-sm text-theme-secondary mt-1">{chain.description}</p>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </div>
          )}

          {/* Classifications Tab */}
          {activeTab === 'classifications' && (
            <div className="space-y-4">
              {classifications.length === 0 ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <FileText size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No classifications</h3>
                  <p className="text-theme-secondary">Define data classifications for PII, PHI, and PCI detection</p>
                </div>
              ) : (
                classifications.map(classification => (
                  <div key={classification.id} className="bg-theme-surface border border-theme rounded-lg p-4">
                    <div className="flex items-center justify-between mb-2">
                      <h3 className="font-medium text-theme-primary">{classification.name}</h3>
                      <span className="px-2 py-1 text-xs bg-theme-accent/10 text-theme-accent rounded">
                        {classification.classification_level.toUpperCase()}
                      </span>
                    </div>
                    <p className="text-sm text-theme-secondary mb-2">{classification.description}</p>
                    <div className="flex gap-4 text-xs text-theme-secondary">
                      {classification.requires_encryption && <span>• Encryption Required</span>}
                      {classification.requires_masking && <span>• Masking Required</span>}
                      {classification.requires_audit && <span>• Audit Required</span>}
                    </div>
                    <p className="text-xs text-theme-secondary mt-2">{classification.detection_count} detections</p>
                  </div>
                ))
              )}
            </div>
          )}

          {/* Reports Tab */}
          {activeTab === 'reports' && (
            <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
              <FileText size={48} className="mx-auto text-theme-secondary mb-4" />
              <h3 className="text-lg font-semibold text-theme-primary mb-2">Compliance Reports</h3>
              <p className="text-theme-secondary mb-6">Generate compliance reports in PDF, HTML, JSON, or CSV format</p>
              <button className="btn-theme btn-theme-primary">
                Generate Report
              </button>
            </div>
          )}

          {/* Audit Log Tab */}
          {activeTab === 'audit' && (
            <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
              <Clock size={48} className="mx-auto text-theme-secondary mb-4" />
              <h3 className="text-lg font-semibold text-theme-primary mb-2">Audit Log</h3>
              <p className="text-theme-secondary">View complete audit trail of AI operations</p>
            </div>
          )}
        </>
      )}
    </PageContainer>
  );
};

export default GovernancePage;

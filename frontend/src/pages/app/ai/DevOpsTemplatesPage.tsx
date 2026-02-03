// DevOps Templates Page - AI Pipeline Templates for CI/CD
import React, { useState, useEffect } from 'react';
import { Plus, GitBranch, Play, Search, Filter, Code, AlertTriangle, CheckCircle, BarChart3 } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { useDispatch } from 'react-redux';
import { addNotification } from '@/shared/services/slices/uiSlice';
import { AppDispatch } from '@/shared/services';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import {
  devopsApi,
  DevopsTemplate,
  DevopsInstallation,
  PipelineExecution,
  DeploymentRisk,
  CodeReview,
  DevopsAnalytics
} from '@/shared/services/ai/DevopsApiService';

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

type TabType = 'templates' | 'installations' | 'executions' | 'risks' | 'reviews' | 'analytics';

const DevOpsTemplatesPage: React.FC = () => {
  const dispatch = useDispatch<AppDispatch>();
  const [activeTab, setActiveTab] = useState<TabType>('templates');
  const [templates, setTemplates] = useState<DevopsTemplate[]>([]);
  const [installations, setInstallations] = useState<DevopsInstallation[]>([]);
  const [executions, setExecutions] = useState<PipelineExecution[]>([]);
  const [risks, setRisks] = useState<DeploymentRisk[]>([]);
  const [reviews, setReviews] = useState<CodeReview[]>([]);
  const [analytics, setAnalytics] = useState<DevopsAnalytics | null>(null);
  const [loading, setLoading] = useState(true);
  const [categoryFilter, setCategoryFilter] = useState<string>('all');
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
      const [templatesRes, installationsRes, executionsRes, risksRes, reviewsRes, analyticsRes] = await Promise.all([
        devopsApi.getTemplates(),
        devopsApi.getInstallations(),
        devopsApi.getExecutions(),
        devopsApi.getRisks(),
        devopsApi.getReviews(),
        devopsApi.getAnalytics()
      ]);
      setTemplates(templatesRes.items || []);
      setInstallations(installationsRes.items || []);
      setExecutions(executionsRes.items || []);
      setRisks(risksRes.items || []);
      setReviews(reviewsRes.items || []);
      setAnalytics(analyticsRes.analytics || null);
    } catch (error) {
      dispatch(addNotification({
        type: 'error',
        message: getErrorMessage(error, 'Failed to load DevOps data')
      }));
    } finally {
      setLoading(false);
    }
  };

  const handleInstallTemplate = async (template: DevopsTemplate) => {
    try {
      await devopsApi.installTemplate(template.id);
      dispatch(addNotification({
        type: 'success',
        message: `"${template.name}" installed successfully`
      }));
      // Reload installations
      const installationsRes = await devopsApi.getInstallations();
      setInstallations(installationsRes.items || []);
    } catch (error) {
      dispatch(addNotification({
        type: 'error',
        message: getErrorMessage(error, 'Failed to install template')
      }));
    }
  };

  const handleRiskDecision = async (riskId: string, decision: 'approve' | 'reject') => {
    try {
      if (decision === 'approve') {
        await devopsApi.approveRisk(riskId);
      } else {
        await devopsApi.rejectRisk(riskId);
      }
      dispatch(addNotification({
        type: 'success',
        message: `Deployment ${decision}d`
      }));
      loadData();
    } catch (error) {
      dispatch(addNotification({
        type: 'error',
        message: getErrorMessage(error, 'Failed to process decision')
      }));
    }
  };

  const getStatusColor = (status: string): string => {
    switch (status) {
      case 'completed': case 'approved': case 'published': case 'active': return 'text-theme-success bg-theme-success/10';
      case 'running': case 'analyzing': case 'pending': return 'text-theme-info bg-theme-info/10';
      case 'failed': case 'rejected': return 'text-theme-danger bg-theme-danger/10';
      case 'draft': case 'paused': return 'text-theme-secondary bg-theme-surface';
      default: return 'text-theme-secondary bg-theme-surface';
    }
  };

  const getRiskColor = (level: string): string => {
    switch (level) {
      case 'critical': return 'text-theme-danger bg-theme-danger/10';
      case 'high': return 'text-theme-warning bg-theme-warning/10';
      case 'medium': return 'text-theme-warning bg-theme-warning/10';
      case 'low': return 'text-theme-success bg-theme-success/10';
      default: return 'text-theme-secondary bg-theme-surface';
    }
  };

  const isInstalled = (templateId: string): boolean => {
    return installations.some(i => i.template.id === templateId && i.status === 'active');
  };

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'AI', href: '/app/ai' },
    { label: 'DevOps Templates' }
  ];

  const tabs = [
    { id: 'templates' as TabType, label: 'Templates', icon: Code },
    { id: 'installations' as TabType, label: 'Installations', icon: GitBranch },
    { id: 'executions' as TabType, label: 'Executions', icon: Play },
    { id: 'risks' as TabType, label: 'Risk Assessments', icon: AlertTriangle },
    { id: 'reviews' as TabType, label: 'Code Reviews', icon: CheckCircle },
    { id: 'analytics' as TabType, label: 'Analytics', icon: BarChart3 }
  ];

  return (
    <PageContainer
      title="DevOps AI Templates"
      description="Pre-built AI workflow templates for DevOps pipelines, code review, and deployment validation"
      breadcrumbs={breadcrumbs}
      actions={[
        {
          label: 'New Execution',
          onClick: () => {},
          icon: Play,
          variant: 'secondary' as const
        },
        {
          label: 'Create Template',
          onClick: () => {},
          icon: Plus,
          variant: 'primary' as const
        }
      ]}
    >
      {/* Analytics Summary */}
      {analytics && (
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-secondary">Total Executions</p>
                <p className="text-2xl font-bold text-theme-primary">{analytics.total_executions}</p>
              </div>
              <Play className="h-8 w-8 text-theme-accent" />
            </div>
            <p className="text-xs text-theme-secondary mt-2">{(analytics.success_rate * 100).toFixed(1)}% success rate</p>
          </div>
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-secondary">Deployments</p>
                <p className="text-2xl font-bold text-theme-primary">{analytics.deployments.total}</p>
              </div>
              <GitBranch className="h-8 w-8 text-theme-info" />
            </div>
          </div>
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-secondary">Code Reviews</p>
                <p className="text-2xl font-bold text-theme-primary">{analytics.code_reviews.total}</p>
              </div>
              <CheckCircle className="h-8 w-8 text-theme-success" />
            </div>
            <p className="text-xs text-theme-danger mt-2">{analytics.code_reviews.critical_issues} critical issues</p>
          </div>
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-secondary">Avg Duration</p>
                <p className="text-2xl font-bold text-theme-primary">
                  {analytics.average_duration_ms ? `${(analytics.average_duration_ms / 1000).toFixed(1)}s` : 'N/A'}
                </p>
              </div>
              <BarChart3 className="h-8 w-8 text-theme-accent" />
            </div>
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
              className="w-full pl-10 pr-4 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>
        </div>
        <div className="flex items-center gap-2">
          <Filter size={16} className="text-theme-secondary" />
          <select
            value={categoryFilter}
            onChange={(e) => setCategoryFilter(e.target.value)}
            className="px-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-blue-500"
          >
            <option value="all">All Categories</option>
            <option value="code_quality">Code Quality</option>
            <option value="deployment">Deployment</option>
            <option value="documentation">Documentation</option>
            <option value="testing">Testing</option>
          </select>
        </div>
        <div className="flex items-center gap-2">
          <select
            value={statusFilter}
            onChange={(e) => setStatusFilter(e.target.value)}
            className="px-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-blue-500"
          >
            <option value="all">All Status</option>
            <option value="published">Published</option>
            <option value="draft">Draft</option>
            <option value="archived">Archived</option>
          </select>
        </div>
      </div>

      {/* Tab Content */}
      {loading ? (
        <div className="text-center py-12">
          <div className="inline-block animate-spin rounded-full h-8 w-8 border-4 border-theme-accent border-t-theme-primary"></div>
          <p className="mt-4 text-theme-secondary">Loading DevOps data...</p>
        </div>
      ) : (
        <>
          {/* Templates Tab */}
          {activeTab === 'templates' && (
            <div className="space-y-4">
              {templates.length === 0 ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <Code size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No templates</h3>
                  <p className="text-theme-secondary mb-6">Create AI pipeline templates for your DevOps workflows</p>
                </div>
              ) : (
                <div data-testid="devops-templates-grid" className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                  {templates.map(template => (
                    <div key={template.id} data-testid="devops-template-card" className="bg-theme-surface border border-theme rounded-lg p-4 hover:border-theme-accent transition-colors">
                      <div className="flex items-center justify-between mb-2">
                        <h3 className="font-medium text-theme-primary">{template.name}</h3>
                        <span data-testid="template-status-badge" className={`px-2 py-1 text-xs rounded ${getStatusColor(template.status)}`}>
                          {template.status}
                        </span>
                      </div>
                      <p className="text-sm text-theme-secondary mb-3 line-clamp-2">{template.description}</p>
                      <div className="flex items-center justify-between mb-3">
                        <div className="flex gap-2 text-xs text-theme-secondary">
                          <span className="px-2 py-1 bg-theme-accent/10 rounded">{template.category}</span>
                          <span className="px-2 py-1 bg-theme-accent/10 rounded">{template.template_type}</span>
                        </div>
                      </div>
                      <div className="flex items-center justify-between">
                        <span className="text-sm text-theme-secondary">
                          {template.installation_count} installs
                        </span>
                        {isInstalled(template.id) ? (
                          <span className="text-sm text-theme-success font-medium">Installed</span>
                        ) : (
                          <button
                            onClick={() => handleInstallTemplate(template)}
                            className="btn-theme btn-theme-primary btn-theme-sm"
                          >
                            Install
                          </button>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}

          {/* Installations Tab */}
          {activeTab === 'installations' && (
            <div className="space-y-4">
              {installations.length === 0 ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <GitBranch size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No installations</h3>
                  <p className="text-theme-secondary">Install templates to use them in your pipelines</p>
                </div>
              ) : (
                installations.map(installation => (
                  <div key={installation.id} className="bg-theme-surface border border-theme rounded-lg p-4">
                    <div className="flex items-center justify-between mb-2">
                      <div className="flex items-center gap-3">
                        <h3 className="font-medium text-theme-primary">{installation.template.name}</h3>
                        <span className={`px-2 py-1 text-xs rounded ${getStatusColor(installation.status)}`}>
                          {installation.status}
                        </span>
                      </div>
                      <span className="text-sm text-theme-secondary">v{installation.installed_version}</span>
                    </div>
                    <div className="flex gap-4 text-sm text-theme-secondary">
                      <span>{installation.execution_count} executions</span>
                      <span className="text-theme-success">{(installation.success_rate * 100).toFixed(1)}% success</span>
                    </div>
                  </div>
                ))
              )}
            </div>
          )}

          {/* Executions Tab */}
          {activeTab === 'executions' && (
            <div className="space-y-4">
              {executions.length === 0 ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <Play size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No executions</h3>
                  <p className="text-theme-secondary">Pipeline executions will appear here</p>
                </div>
              ) : (
                executions.map(execution => (
                  <div key={execution.id} className="bg-theme-surface border border-theme rounded-lg p-4">
                    <div className="flex items-center justify-between mb-2">
                      <div className="flex items-center gap-3">
                        <span className="font-mono text-sm text-theme-primary">{execution.execution_id}</span>
                        <span className={`px-2 py-1 text-xs rounded ${getStatusColor(execution.status)}`}>
                          {execution.status}
                        </span>
                        <span className="px-2 py-1 text-xs bg-theme-accent/10 text-theme-accent rounded">
                          {execution.pipeline_type}
                        </span>
                      </div>
                      {execution.duration_ms && (
                        <span className="text-sm text-theme-secondary">
                          {(execution.duration_ms / 1000).toFixed(2)}s
                        </span>
                      )}
                    </div>
                    <div className="flex gap-4 text-xs text-theme-secondary">
                      {execution.branch && <span>Branch: {execution.branch}</span>}
                      {execution.commit_sha && <span>Commit: {execution.commit_sha.substring(0, 7)}</span>}
                      {execution.pull_request_number && <span>PR #{execution.pull_request_number}</span>}
                    </div>
                  </div>
                ))
              )}
            </div>
          )}

          {/* Risks Tab */}
          {activeTab === 'risks' && (
            <div className="space-y-4">
              {risks.length === 0 ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <AlertTriangle size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No risk assessments</h3>
                  <p className="text-theme-secondary">Deployment risk assessments will appear here</p>
                </div>
              ) : (
                risks.map(risk => (
                  <div key={risk.id} className="bg-theme-surface border border-theme rounded-lg p-4">
                    <div className="flex items-center justify-between mb-2">
                      <div className="flex items-center gap-3">
                        <span className="font-mono text-sm text-theme-primary">{risk.assessment_id}</span>
                        <span className={`px-2 py-1 text-xs rounded ${getRiskColor(risk.risk_level)}`}>
                          {risk.risk_level.toUpperCase()}
                        </span>
                        <span className={`px-2 py-1 text-xs rounded ${getStatusColor(risk.status)}`}>
                          {risk.status}
                        </span>
                      </div>
                      {risk.status === 'assessed' && (
                        <div className="flex gap-2">
                          <button
                            onClick={() => handleRiskDecision(risk.id, 'approve')}
                            className="btn-theme btn-theme-success btn-theme-sm"
                          >
                            Approve
                          </button>
                          <button
                            onClick={() => handleRiskDecision(risk.id, 'reject')}
                            className="btn-theme btn-theme-danger btn-theme-sm"
                          >
                            Reject
                          </button>
                        </div>
                      )}
                    </div>
                    <p className="text-sm text-theme-secondary mb-2">{risk.summary}</p>
                    <div className="flex gap-4 text-xs text-theme-secondary">
                      <span>{risk.deployment_type}</span>
                      <span>Target: {risk.target_environment}</span>
                      {risk.risk_score !== null && <span>Score: {risk.risk_score}</span>}
                    </div>
                    {risk.recommendations.length > 0 && (
                      <div className="mt-2 text-xs text-theme-secondary">
                        <strong>Recommendations:</strong> {risk.recommendations.join(', ')}
                      </div>
                    )}
                  </div>
                ))
              )}
            </div>
          )}

          {/* Reviews Tab */}
          {activeTab === 'reviews' && (
            <div className="space-y-4">
              {reviews.length === 0 ? (
                <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                  <CheckCircle size={48} className="mx-auto text-theme-secondary mb-4" />
                  <h3 className="text-lg font-semibold text-theme-primary mb-2">No code reviews</h3>
                  <p className="text-theme-secondary">AI code reviews will appear here</p>
                </div>
              ) : (
                reviews.map(review => (
                  <div key={review.id} className="bg-theme-surface border border-theme rounded-lg p-4">
                    <div className="flex items-center justify-between mb-2">
                      <div className="flex items-center gap-3">
                        <span className="font-mono text-sm text-theme-primary">{review.review_id}</span>
                        <span className={`px-2 py-1 text-xs rounded ${getStatusColor(review.status)}`}>
                          {review.status}
                        </span>
                        {review.overall_rating && (
                          <span className="px-2 py-1 text-xs bg-theme-accent/10 text-theme-accent rounded">
                            {review.overall_rating}
                          </span>
                        )}
                      </div>
                      <span className={`text-sm font-medium ${
                        review.approval_recommendation === 'approve' ? 'text-theme-success' :
                        review.approval_recommendation === 'reject' ? 'text-theme-danger' :
                        'text-theme-warning'
                      }`}>
                        {review.approval_recommendation}
                      </span>
                    </div>
                    <div className="flex gap-4 text-sm text-theme-secondary mb-2">
                      <span>{review.files_reviewed} files</span>
                      <span className="text-theme-success">+{review.lines_added}</span>
                      <span className="text-theme-danger">-{review.lines_removed}</span>
                    </div>
                    <div className="flex gap-4 text-xs text-theme-secondary">
                      <span>{review.issues_found} issues</span>
                      {review.critical_issues > 0 && (
                        <span className="text-theme-danger">{review.critical_issues} critical</span>
                      )}
                      <span>{review.suggestions_count} suggestions</span>
                    </div>
                  </div>
                ))
              )}
            </div>
          )}

          {/* Analytics Tab */}
          {activeTab === 'analytics' && (
            <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
              <BarChart3 size={48} className="mx-auto text-theme-secondary mb-4" />
              <h3 className="text-lg font-semibold text-theme-primary mb-2">DevOps Analytics</h3>
              <p className="text-theme-secondary">Detailed analytics and insights coming soon</p>
            </div>
          )}
        </>
      )}
    </PageContainer>
  );
};

export default DevOpsTemplatesPage;

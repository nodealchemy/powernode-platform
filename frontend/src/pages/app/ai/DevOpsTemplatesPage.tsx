// DevOps Templates Page - AI Pipeline Templates for CI/CD
import React, { useState, useEffect } from 'react';
import { Plus, GitBranch, Play, Search, Filter, Code, AlertTriangle, CheckCircle, BarChart3, RefreshCw, Pencil, Trash2, Tag, Shield, Clock, Download, Star } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Modal } from '@/shared/components/ui/Modal';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import DevopsTemplateFormModal, { TemplateFormData } from '@/features/ai/devops/components/DevopsTemplateFormModal';
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

// Extracted content component (without PageContainer) for embedding in other pages
export const TemplatesContent: React.FC = () => {
  return <DevOpsTemplatesInner standalone={false} />;
};

const DevOpsTemplatesInner: React.FC<{ standalone: boolean }> = ({ standalone }) => {
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
  const [detailModal, setDetailModal] = useState<{ isOpen: boolean; template: DevopsTemplate | null; loading: boolean }>({ isOpen: false, template: null, loading: false });
  const [createModal, setCreateModal] = useState(false);
  const [editModal, setEditModal] = useState<{ isOpen: boolean; template: DevopsTemplate | null }>({ isOpen: false, template: null });
  const [saving, setSaving] = useState(false);
  const { confirm, ConfirmationDialog } = useConfirmation();

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

  const handleCreateTemplate = async (data: TemplateFormData) => {
    try {
      setSaving(true);
      await devopsApi.createTemplate(data as unknown as Record<string, unknown>);
      dispatch(addNotification({ type: 'success', message: `"${data.name}" created successfully` }));
      setCreateModal(false);
      loadData();
    } catch (error) {
      dispatch(addNotification({ type: 'error', message: getErrorMessage(error, 'Failed to create template') }));
    } finally {
      setSaving(false);
    }
  };

  const handleViewTemplate = async (template: DevopsTemplate) => {
    setDetailModal({ isOpen: true, template, loading: true });
    try {
      const res = await devopsApi.getTemplate(template.id);
      setDetailModal({ isOpen: true, template: res.template, loading: false });
    } catch (error) {
      dispatch(addNotification({ type: 'error', message: getErrorMessage(error, 'Failed to load template details') }));
      setDetailModal({ isOpen: true, template, loading: false });
    }
  };

  const handleEditFromDetail = () => {
    if (!detailModal.template) return;
    const template = detailModal.template;
    setDetailModal({ isOpen: false, template: null, loading: false });
    handleEditTemplate(template);
  };

  const handleEditTemplate = async (template: DevopsTemplate) => {
    // Fetch detailed template data for editing
    try {
      const res = await devopsApi.getTemplate(template.id);
      setEditModal({ isOpen: true, template: res.template });
    } catch {
      setEditModal({ isOpen: true, template });
    }
  };

  const handleSaveTemplate = async (data: TemplateFormData) => {
    if (!editModal.template) return;
    try {
      setSaving(true);
      await devopsApi.updateTemplate(editModal.template.id, data as unknown as Record<string, unknown>);
      dispatch(addNotification({ type: 'success', message: `"${data.name}" updated successfully` }));
      setEditModal({ isOpen: false, template: null });
      loadData();
    } catch (error) {
      dispatch(addNotification({ type: 'error', message: getErrorMessage(error, 'Failed to update template') }));
    } finally {
      setSaving(false);
    }
  };

  const handleUninstallTemplate = (installation: DevopsInstallation) => {
    confirm({
      title: 'Uninstall Template',
      message: `Are you sure you want to uninstall "${installation.template.name}"? This will remove the template from your account.`,
      variant: 'danger',
      confirmLabel: 'Uninstall',
      onConfirm: async () => {
        await devopsApi.uninstallTemplate(installation.id);
        dispatch(addNotification({ type: 'success', message: `"${installation.template.name}" uninstalled successfully` }));
        const installationsRes = await devopsApi.getInstallations();
        setInstallations(installationsRes.items || []);
      },
    });
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

  const innerContent = (
    <>
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
              className="w-full pl-10 pr-4 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
            />
          </div>
        </div>
        <div className="flex items-center gap-2">
          <Filter size={16} className="text-theme-secondary" />
          <select
            value={categoryFilter}
            onChange={(e) => setCategoryFilter(e.target.value)}
            className="px-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
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
            className="px-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
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
                    <div
                      key={template.id}
                      data-testid="devops-template-card"
                      className="bg-theme-surface border border-theme rounded-lg p-4 hover:border-theme-accent transition-colors cursor-pointer"
                      onClick={() => handleViewTemplate(template)}
                    >
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
                      <div className="flex items-center justify-between" onClick={(e) => e.stopPropagation()}>
                        <span className="text-sm text-theme-secondary">
                          {template.installation_count} installs
                        </span>
                        <div className="flex items-center gap-2">
                          {template.is_owner && (
                            <button
                              onClick={() => handleEditTemplate(template)}
                              className="p-1.5 text-theme-secondary hover:text-theme-primary hover:bg-theme-hover rounded transition-colors"
                              title="Edit template"
                            >
                              <Pencil size={14} />
                            </button>
                          )}
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
                      <div className="flex items-center gap-3">
                        <span className="text-sm text-theme-secondary">v{installation.installed_version}</span>
                        <button
                          onClick={() => handleUninstallTemplate(installation)}
                          className="p-1.5 text-theme-secondary hover:text-theme-danger hover:bg-theme-danger/10 rounded transition-colors"
                          title="Uninstall template"
                        >
                          <Trash2 size={14} />
                        </button>
                      </div>
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
      {/* Create Template Modal */}
      <DevopsTemplateFormModal
        isOpen={createModal}
        onClose={() => setCreateModal(false)}
        onSave={handleCreateTemplate}
        mode="create"
        saving={saving}
      />

      {/* Detail Template Modal */}
      <Modal
        isOpen={detailModal.isOpen}
        onClose={() => setDetailModal({ isOpen: false, template: null, loading: false })}
        title={detailModal.template?.name || 'Template Details'}
        maxWidth="2xl"
        footer={
          <div className="flex justify-between w-full">
            <div>
              {detailModal.template?.is_owner && (
                <button
                  onClick={handleEditFromDetail}
                  className="btn-theme btn-theme-secondary btn-theme-sm flex items-center gap-2"
                >
                  <Pencil size={14} />
                  Edit Template
                </button>
              )}
            </div>
            <div className="flex gap-3">
              <button
                onClick={() => setDetailModal({ isOpen: false, template: null, loading: false })}
                className="btn-theme btn-theme-secondary btn-theme-sm"
              >
                Close
              </button>
              {detailModal.template && !isInstalled(detailModal.template.id) && (
                <button
                  onClick={() => {
                    if (detailModal.template) {
                      handleInstallTemplate(detailModal.template);
                      setDetailModal({ isOpen: false, template: null, loading: false });
                    }
                  }}
                  className="btn-theme btn-theme-primary btn-theme-sm"
                >
                  Install
                </button>
              )}
            </div>
          </div>
        }
      >
        {detailModal.loading ? (
          <div className="text-center py-8">
            <div className="inline-block animate-spin rounded-full h-6 w-6 border-4 border-theme-accent border-t-theme-primary"></div>
            <p className="mt-3 text-theme-secondary text-sm">Loading template details...</p>
          </div>
        ) : detailModal.template && (
          <div className="space-y-5">
            {/* Status badges row */}
            <div className="flex flex-wrap gap-2">
              <span className={`px-2.5 py-1 text-xs font-medium rounded ${getStatusColor(detailModal.template.status)}`}>
                {detailModal.template.status}
              </span>
              <span className="px-2.5 py-1 text-xs font-medium rounded bg-theme-accent/10 text-theme-accent">
                {detailModal.template.visibility}
              </span>
              <span className="px-2.5 py-1 text-xs rounded bg-theme-surface text-theme-secondary border border-theme">
                v{detailModal.template.version}
              </span>
              {detailModal.template.is_featured && (
                <span className="px-2.5 py-1 text-xs font-medium rounded bg-theme-warning/10 text-theme-warning flex items-center gap-1">
                  <Star size={12} /> Featured
                </span>
              )}
              {isInstalled(detailModal.template.id) && (
                <span className="px-2.5 py-1 text-xs font-medium rounded text-theme-success bg-theme-success/10">
                  Installed
                </span>
              )}
            </div>

            {/* Description */}
            <div>
              <p className="text-sm text-theme-secondary">{detailModal.template.description}</p>
            </div>

            {/* Metadata grid */}
            <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
              <div className="bg-theme-bg border border-theme rounded-lg p-3">
                <div className="flex items-center gap-2 text-theme-secondary mb-1">
                  <Tag size={12} />
                  <span className="text-xs">Category</span>
                </div>
                <p className="text-sm font-medium text-theme-primary">{detailModal.template.category.replace('_', ' ')}</p>
              </div>
              <div className="bg-theme-bg border border-theme rounded-lg p-3">
                <div className="flex items-center gap-2 text-theme-secondary mb-1">
                  <Code size={12} />
                  <span className="text-xs">Type</span>
                </div>
                <p className="text-sm font-medium text-theme-primary">{detailModal.template.template_type.replace('_', ' ')}</p>
              </div>
              <div className="bg-theme-bg border border-theme rounded-lg p-3">
                <div className="flex items-center gap-2 text-theme-secondary mb-1">
                  <Download size={12} />
                  <span className="text-xs">Installs</span>
                </div>
                <p className="text-sm font-medium text-theme-primary">{detailModal.template.installation_count}</p>
              </div>
              <div className="bg-theme-bg border border-theme rounded-lg p-3">
                <div className="flex items-center gap-2 text-theme-secondary mb-1">
                  <Clock size={12} />
                  <span className="text-xs">Published</span>
                </div>
                <p className="text-sm font-medium text-theme-primary">
                  {detailModal.template.published_at ? new Date(detailModal.template.published_at).toLocaleDateString() : 'Not published'}
                </p>
              </div>
            </div>

            {/* Tags */}
            {detailModal.template.tags && detailModal.template.tags.length > 0 && (
              <div>
                <h4 className="text-xs font-medium text-theme-secondary uppercase tracking-wide mb-2">Tags</h4>
                <div className="flex flex-wrap gap-1.5">
                  {detailModal.template.tags.map((tag, i) => (
                    <span key={i} className="px-2 py-0.5 text-xs rounded-full bg-theme-accent/10 text-theme-accent">
                      {tag}
                    </span>
                  ))}
                </div>
              </div>
            )}

            {/* Integrations & Secrets */}
            {((detailModal.template.integrations_required && detailModal.template.integrations_required.length > 0) ||
              (detailModal.template.secrets_required && detailModal.template.secrets_required.length > 0)) && (
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {detailModal.template.integrations_required && detailModal.template.integrations_required.length > 0 && (
                  <div>
                    <h4 className="text-xs font-medium text-theme-secondary uppercase tracking-wide mb-2">Required Integrations</h4>
                    <div className="flex flex-wrap gap-1.5">
                      {detailModal.template.integrations_required.map((int, i) => (
                        <span key={i} className="px-2 py-1 text-xs rounded bg-theme-info/10 text-theme-info">
                          {int}
                        </span>
                      ))}
                    </div>
                  </div>
                )}
                {detailModal.template.secrets_required && detailModal.template.secrets_required.length > 0 && (
                  <div>
                    <h4 className="text-xs font-medium text-theme-secondary uppercase tracking-wide mb-2 flex items-center gap-1">
                      <Shield size={12} /> Required Secrets
                    </h4>
                    <div className="flex flex-wrap gap-1.5">
                      {detailModal.template.secrets_required.map((secret, i) => (
                        <span key={i} className="px-2 py-1 text-xs rounded bg-theme-warning/10 text-theme-warning font-mono">
                          {secret}
                        </span>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            )}

            {/* Variables */}
            {detailModal.template.variables && detailModal.template.variables.length > 0 && (
              <div>
                <h4 className="text-xs font-medium text-theme-secondary uppercase tracking-wide mb-2">Variables</h4>
                <div className="bg-theme-bg border border-theme rounded-lg divide-y divide-theme">
                  {(detailModal.template.variables as Array<{ name: string; default?: string; description?: string }>).map((variable, i) => (
                    <div key={i} className="px-3 py-2 flex items-center justify-between">
                      <div>
                        <span className="text-sm font-mono text-theme-primary">{variable.name}</span>
                        {variable.description && (
                          <p className="text-xs text-theme-secondary">{variable.description}</p>
                        )}
                      </div>
                      {variable.default && (
                        <span className="text-xs font-mono text-theme-secondary bg-theme-surface px-2 py-0.5 rounded">
                          {variable.default}
                        </span>
                      )}
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Workflow Definition (condensed) */}
            {detailModal.template.workflow_definition && (
              <div>
                <h4 className="text-xs font-medium text-theme-secondary uppercase tracking-wide mb-2">Workflow Pipeline</h4>
                <div className="bg-theme-bg border border-theme rounded-lg p-4">
                  {(detailModal.template.workflow_definition as { nodes?: Array<{ id: string; type: string; label: string }> }).nodes ? (
                    <div className="flex flex-wrap items-center gap-2">
                      {((detailModal.template.workflow_definition as { nodes: Array<{ id: string; type: string; label: string }> }).nodes).map((node, i, arr) => {
                        const nodeColors: Record<string, { bg: string; text: string; border: string; dot: string }> = {
                          trigger: { bg: 'bg-theme-info/15', text: 'text-theme-info', border: 'border-theme-info/30', dot: 'bg-current' },
                          ai: { bg: 'bg-theme-primary/10', text: 'text-theme-primary', border: 'border-theme-primary/25', dot: 'bg-current' },
                          action: { bg: 'bg-theme-success/15', text: 'text-theme-success', border: 'border-theme-success/30', dot: 'bg-current' },
                          condition: { bg: 'bg-theme-warning/15', text: 'text-theme-warning', border: 'border-theme-warning/30', dot: 'bg-current' },
                        };
                        const colors = nodeColors[node.type] || { bg: 'bg-theme-danger/15', text: 'text-theme-danger', border: 'border-theme-danger/30', dot: 'bg-current' };
                        return (
                          <React.Fragment key={node.id}>
                            <div className={`inline-flex items-center gap-1.5 px-3 py-1.5 text-xs rounded-md font-medium border ${colors.bg} ${colors.text} ${colors.border}`}>
                              <span className={`w-2 h-2 rounded-full ${colors.dot}`} />
                              {node.label}
                            </div>
                            {i < arr.length - 1 && (
                              <span className="text-theme-secondary/60 text-sm">&rarr;</span>
                            )}
                          </React.Fragment>
                        );
                      })}
                    </div>
                  ) : (
                    <p className="text-xs text-theme-secondary">No workflow nodes defined</p>
                  )}
                </div>
                {/* Legend */}
                <div className="flex flex-wrap gap-3 mt-2 text-[10px] text-theme-secondary">
                  <span className="flex items-center gap-1 text-theme-info"><span className="w-2 h-2 rounded-full bg-current" /> Trigger</span>
                  <span className="flex items-center gap-1 text-theme-success"><span className="w-2 h-2 rounded-full bg-current" /> Action</span>
                  <span className="flex items-center gap-1 text-theme-primary"><span className="w-2 h-2 rounded-full bg-current" /> AI</span>
                  <span className="flex items-center gap-1 text-theme-warning"><span className="w-2 h-2 rounded-full bg-current" /> Condition</span>
                </div>
              </div>
            )}

            {/* Usage Guide */}
            {detailModal.template.usage_guide && (
              <div>
                <h4 className="text-xs font-medium text-theme-secondary uppercase tracking-wide mb-2">Usage Guide</h4>
                <div className="bg-theme-bg border border-theme rounded-lg p-4 text-sm text-theme-primary prose prose-sm max-w-none">
                  <pre className="whitespace-pre-wrap font-sans text-sm">{detailModal.template.usage_guide}</pre>
                </div>
              </div>
            )}

            {/* Input/Output Schema */}
            {(detailModal.template.input_schema || detailModal.template.output_schema) && (
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {detailModal.template.input_schema && Object.keys(detailModal.template.input_schema).length > 0 && (
                  <div>
                    <h4 className="text-xs font-medium text-theme-secondary uppercase tracking-wide mb-2">Input Schema</h4>
                    <div className="bg-theme-bg border border-theme rounded-lg p-3">
                      {Object.entries(detailModal.template.input_schema).map(([key, val]) => (
                        <div key={key} className="flex items-start justify-between py-1">
                          <span className="text-xs font-mono text-theme-primary">{key}</span>
                          <span className="text-xs text-theme-secondary">{(val as { type?: string })?.type || 'unknown'}</span>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
                {detailModal.template.output_schema && Object.keys(detailModal.template.output_schema).length > 0 && (
                  <div>
                    <h4 className="text-xs font-medium text-theme-secondary uppercase tracking-wide mb-2">Output Schema</h4>
                    <div className="bg-theme-bg border border-theme rounded-lg p-3">
                      {Object.entries(detailModal.template.output_schema).map(([key, val]) => (
                        <div key={key} className="flex items-start justify-between py-1">
                          <span className="text-xs font-mono text-theme-primary">{key}</span>
                          <span className="text-xs text-theme-secondary">{(val as { type?: string })?.type || 'unknown'}</span>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            )}
          </div>
        )}
      </Modal>

      {/* Edit Template Modal */}
      <DevopsTemplateFormModal
        isOpen={editModal.isOpen}
        onClose={() => setEditModal({ isOpen: false, template: null })}
        onSave={handleSaveTemplate}
        template={editModal.template}
        mode="edit"
        saving={saving}
      />

      {ConfirmationDialog}
    </>
  );

  if (!standalone) {
    return innerContent;
  }

  return (
    <PageContainer
      title="DevOps AI Templates"
      description="Pre-built AI workflow templates for DevOps pipelines, code review, and deployment validation"
      breadcrumbs={breadcrumbs}
      actions={[
        {
          label: 'Refresh',
          onClick: () => loadData(),
          icon: RefreshCw,
          variant: 'secondary' as const
        },
        {
          label: 'New Execution',
          onClick: () => {},
          icon: Play,
          variant: 'secondary' as const
        },
        {
          label: 'Create Template',
          onClick: () => setCreateModal(true),
          icon: Plus,
          variant: 'primary' as const
        }
      ]}
    >
      {innerContent}
    </PageContainer>
  );
};

const DevOpsTemplatesPage: React.FC = () => {
  return <DevOpsTemplatesInner standalone={true} />;
};

export default DevOpsTemplatesPage;

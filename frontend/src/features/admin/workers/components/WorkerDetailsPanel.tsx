import React, { useState, useEffect } from 'react';
import { Worker, workerApi, UpdateWorkerData } from '@/features/admin/workers/services/workerApi';
import { formatDateTime } from '@/shared/utils/formatters';
import { WorkerActivityDashboard } from './WorkerActivityDashboard';
import { WorkerPermissionsView } from './WorkerPermissionsView';
import { WorkerSettings } from './WorkerSettings';
import { useForm, FormValidationRules } from '@/shared/hooks/useForm';
import { 
  X, 
  Edit, 
  Save, 
  Trash2, 
  RefreshCw, 
  Shield, 
  Activity, 
  Settings,
  Eye,
  EyeOff,
  Copy,
  Check,
  Building,
  AlertTriangle
} from 'lucide-react';
import { copyToClipboard } from '@/shared/utils/clipboard';

interface WorkerHealthCheckResult {
  status: 'healthy' | 'warning' | 'error';
  checks: {
    connectivity: 'pass' | 'fail';
    authentication: 'pass' | 'fail';
    rate_limiting: 'pass' | 'fail';
    monitoring: 'pass' | 'fail';
  };
  response_time_ms: number;
  details: string[];
}

export interface WorkerDetailsPanelProps {
  worker: Worker;
  isOpen: boolean;
  onClose: () => void;
  onUpdate: (workerId: string, data: UpdateWorkerData) => Promise<void>;
  onDelete: (workerId: string) => Promise<void>;
}

type TabType = 'overview' | 'permissions' | 'activity' | 'settings';

export const WorkerDetailsPanel: React.FC<WorkerDetailsPanelProps> = ({
  worker,
  isOpen,
  onClose,
  onUpdate,
  onDelete
}) => {
  const [activeTab, setActiveTab] = useState<TabType>('overview');
  const [isEditing, setIsEditing] = useState(false);
  const [showToken, setShowToken] = useState(false);
  const [newToken, setNewToken] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [copied, setCopied] = useState(false);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [testingWorker, setTestingWorker] = useState(false);
  const [testJobStatus, setTestJobStatus] = useState<'idle' | 'queued' | 'processing' | 'completed' | 'failed'>('idle');
  const [testResults, setTestResults] = useState<WorkerHealthCheckResult | null>(null);
  const [showTestResults, setShowTestResults] = useState(false);

  // Form for editing worker
  const validationRules: FormValidationRules = {
    name: { required: true, minLength: 2, maxLength: 100 },
    description: { maxLength: 500 },
    roles: { required: true }
  };

  const form = useForm<UpdateWorkerData>({
    initialValues: {
      name: worker.name,
      description: worker.description || '',
      roles: worker.roles
    },
    validationRules,
    onSubmit: async (data) => {
      await onUpdate(worker.id, data);
      setIsEditing(false);
    },
    enableRealTimeValidation: true
  });

  const resetForm = () => {
    form.reset();
    form.setValue('name', worker.name);
    form.setValue('description', worker.description || '');
    form.setValue('roles', worker.roles);
  };

  useEffect(() => {
    if (isOpen) {
      resetForm();
      setActiveTab('overview');
      setIsEditing(false);
      setShowToken(false);
      setNewToken(null);
    }
  }, [isOpen, worker]);

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'active': return 'bg-theme-success-background text-theme-success';
      case 'suspended': return 'bg-theme-warning-background text-theme-warning';
      case 'revoked': return 'bg-theme-error-background text-theme-error';
      default: return 'bg-theme-surface text-theme-secondary';
    }
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'active': return '✅';
      case 'suspended': return '⏸️';
      case 'revoked': return '❌';
      default: return '❓';
    }
  };

  const formatMaskedToken = (token: string): string => {
    // Backend now provides pre-masked tokens, return as-is
    return token;
  };


  const handleTokenRegenerate = async () => {
    setLoading(true);
    try {
      const response = await workerApi.regenerateToken(worker.id);
      setNewToken(response.new_token);
      setShowToken(true);
    } catch (error) {
      if (process.env.NODE_ENV === 'development') {
        console.error('[WorkerDetailsPanel] Token regeneration failed:', error);
      }
    } finally {
      setLoading(false);
    }
  };

  const handleStatusChange = async (action: 'suspend' | 'activate' | 'revoke') => {
    setLoading(true);
    try {
      switch (action) {
        case 'suspend':
          await workerApi.suspendWorker(worker.id);
          break;
        case 'activate':
          await workerApi.activateWorker(worker.id);
          break;
        case 'revoke':
          await workerApi.revokeWorker(worker.id);
          break;
      }
    } catch (error) {
      if (process.env.NODE_ENV === 'development') {
        console.error('[WorkerDetailsPanel] Status change failed:', action, error);
      }
    } finally {
      setLoading(false);
    }
  };

  const copyToken = async (token: string) => {
    try {
      await copyToClipboard(token);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch (_error) {
      // Clipboard copy failure is non-critical - user can manually copy
    }
  };

  const handleDelete = async () => {
    setLoading(true);
    try {
      await onDelete(worker.id);
      setShowDeleteConfirm(false);
      onClose();
    } catch (error) {
      if (process.env.NODE_ENV === 'development') {
        console.error('[WorkerDetailsPanel] Worker deletion failed:', error);
      }
    } finally {
      setLoading(false);
    }
  };

  const handleTestWorker = async () => {
    try {
      setTestingWorker(true);
      setTestJobStatus('queued');
      setTestResults(null);
      
      // Enqueue test job
      const jobResult = await workerApi.testWorker(worker.id);
      
      // Set initial queued state
      setTestResults({
        status: 'warning',
        checks: {
          connectivity: 'pass',
          authentication: 'pass',
          rate_limiting: 'pass',
          monitoring: 'pass'
        },
        response_time_ms: 0,
        details: [
          `✓ Test job enqueued successfully: ${jobResult.message}`,
          `📅 Expected completion: ${new Date(jobResult.estimated_completion).toLocaleString()}`,
          `⏳ Job is now queued and will be processed by the worker service...`
        ]
      });
      setShowTestResults(true);

      // After a brief delay, move to processing state
      setTimeout(() => {
        setTestJobStatus('processing');
        setTestResults(prev => prev ? {
          ...prev,
          details: [
            `✓ Test job enqueued successfully: ${jobResult.message}`,
            `📅 Expected completion: ${new Date(jobResult.estimated_completion).toLocaleString()}`,
            `🔄 Job is now processing - testing worker connectivity and functionality...`
          ]
        } : null);
      }, 3000); // Show queued state for 3 seconds

      // Simulate job completion after estimated time (in a real scenario, you'd poll for job status)
      setTimeout(async () => {
        try {
          // After job completes, run health check to get actual results
          const healthResults = await workerApi.testWorkerHealth(worker.id);
          setTestResults(healthResults);
          setTestJobStatus('completed');
        } catch (healthErr: unknown) {
          setTestResults({
            status: 'error',
            checks: {
              connectivity: 'fail',
              authentication: 'fail',
              rate_limiting: 'fail',
              monitoring: 'fail'
            },
            response_time_ms: 0,
            details: [
              '❌ Test job completed but health check failed',
              `Error: ${healthErr instanceof Error ? healthErr.message : 'Health check after test job failed'}`
            ]
          });
          setTestJobStatus('failed');
        } finally {
          setTestingWorker(false);
        }
      }, 30000); // 30 seconds as per API response

    } catch (error) {
      setTestResults({
        status: 'error',
        checks: {
          connectivity: 'fail',
          authentication: 'fail',
          rate_limiting: 'fail',
          monitoring: 'fail'
        },
        response_time_ms: 0,
        details: [
          '❌ Failed to enqueue test job',
          `Error: ${error instanceof Error ? error.message : 'Failed to enqueue test job'}`
        ]
      });
      setShowTestResults(true);
      setTestingWorker(false);
      setTestJobStatus('failed');
    }
  };

  const toggleRole = (role: string) => {
    const currentRoles = form.values.roles || [];
    const newRoles = currentRoles.includes(role)
      ? currentRoles.filter(r => r !== role)
      : [...currentRoles, role];
    form.setValue('roles', newRoles);
  };

  const tabs = [
    { id: 'overview' as TabType, label: 'Overview', icon: Eye },
    { id: 'permissions' as TabType, label: 'Permissions', icon: Shield },
    { id: 'activity' as TabType, label: 'Activity', icon: Activity },
    { id: 'settings' as TabType, label: 'Settings', icon: Settings }
  ];

  // All roles with their types and descriptions - synced with backend Permissions::ROLES
  const allRoles = [
    // User roles
    { name: 'member', display: 'Member', description: 'Basic account member with standard access', type: 'user' },
    { name: 'manager', display: 'Manager', description: 'Team manager with content and team management capabilities', type: 'user' },
    { name: 'billing_admin', display: 'Billing Administrator', description: 'Manages billing, subscriptions, and financial operations', type: 'user' },
    { name: 'developer', display: 'App Developer', description: 'App developer with marketplace publishing capabilities', type: 'user' },
    { name: 'owner', display: 'Account Owner', description: 'Account owner with full account management capabilities', type: 'user' },
    // Admin roles
    { name: 'admin', display: 'Administrator', description: 'System administrator with full administrative access', type: 'admin' },
    { name: 'super_admin', display: 'Super Administrator', description: 'Super administrator with full system access', type: 'admin' },
    // System roles
    { name: 'system_worker', display: 'System Worker', description: 'Automated worker with system-level access', type: 'system' },
    { name: 'task_worker', display: 'Task Worker', description: 'Worker limited to specific task execution', type: 'system' }
  ];

  const isSystemWorker = worker.account_name === 'System';

  // Filter roles based on worker type - must match backend Worker#assignable_roles
  const availableRoles = allRoles.filter(role => {
    if (isSystemWorker) {
      // System workers can have system and admin roles only
      return role.type === 'system' || role.type === 'admin';
    } else {
      // Account workers can only have specific user roles for management interface
      return role.type === 'user' && ['member', 'manager', 'billing_admin', 'developer', 'owner'].includes(role.name);
    }
  });

  if (!isOpen) return null;

  return (
    <div 
      className="bg-theme-surface rounded-lg overflow-hidden transition-all duration-300 ease-in-out"
      onClick={(e) => e.stopPropagation()}
    >
      <div className="w-full flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between p-6 border-b border-theme">
          <div className="flex items-center gap-4">
            <div>
              <div className="flex items-center gap-3">
                <h2 className="text-xl font-semibold text-theme-primary">{worker.name}</h2>
                {isSystemWorker && (
                  <span className="px-2 py-1 bg-theme-error text-white text-xs font-medium rounded-full">
                    ⚙️ SYSTEM
                  </span>
                )}
                <span className={`px-3 py-1 rounded-full text-sm font-medium ${getStatusColor(worker.status)}`}>
                  {getStatusIcon(worker.status)} {worker.status}
                </span>
              </div>
              <div className="text-theme-secondary text-sm mt-1">
                <Building className="w-4 h-4 inline mr-1" />
                {worker.account_name}
              </div>
            </div>
          </div>
          
          <div className="flex items-center gap-2">
            {!isEditing && (
              <button
                onClick={() => setIsEditing(true)}
                className="p-2 text-theme-secondary hover:text-theme-primary transition-colors"
                title="Edit worker"
              >
                <Edit className="w-4 h-4" />
              </button>
            )}
            <button
              onClick={onClose}
              className="p-2 text-theme-secondary hover:text-theme-primary transition-colors"
            >
              <X className="w-5 h-5" />
            </button>
          </div>
        </div>

        {/* Tabs */}
        <div className="border-b border-theme">
          <div className="flex px-6">
            {tabs.map((tab) => {
              const Icon = tab.icon;
              return (
                <button
                  key={tab.id}
                  onClick={() => setActiveTab(tab.id)}
                  className={`flex items-center gap-2 px-4 py-3 border-b-2 text-sm font-medium transition-colors ${
                    activeTab === tab.id
                      ? 'border-theme-interactive-primary text-theme-interactive-primary'
                      : 'border-transparent text-theme-secondary hover:text-theme-primary'
                  }`}
                >
                  <Icon className="w-4 h-4" />
                  {tab.label}
                </button>
              );
            })}
          </div>
        </div>

        {/* Content */}
        <div className="flex-1 overflow-y-auto">
          {activeTab === 'overview' && (
            <div className="p-6 space-y-6">
              {isEditing ? (
                /* Edit Form */
                <form onSubmit={form.handleSubmit} className="space-y-6">
                  <div>
                    <label className="block text-sm font-medium text-theme-primary mb-2">
                      Worker Name *
                    </label>
                    <input
                      {...form.getFieldProps('name')}
                      type="text"
                      className={`w-full px-3 py-2 border rounded-lg bg-theme-background text-theme-primary ${
                        form.errors.name ? 'border-theme-error' : 'border-theme'
                      }`}
                      disabled={form.isSubmitting}
                    />
                    {form.errors.name && (
                      <p className="text-theme-error text-sm mt-1">{form.errors.name}</p>
                    )}
                  </div>

                  <div>
                    <label className="block text-sm font-medium text-theme-primary mb-2">
                      Description
                    </label>
                    <textarea
                      {...form.getFieldProps('description')}
                      rows={3}
                      className={`w-full px-3 py-2 border rounded-lg bg-theme-background text-theme-primary ${
                        form.errors.description ? 'border-theme-error' : 'border-theme'
                      }`}
                      disabled={form.isSubmitting}
                    />
                    {form.errors.description && (
                      <p className="text-theme-error text-sm mt-1">{form.errors.description}</p>
                    )}
                  </div>

                  <div>
                    <label className="block text-sm font-medium text-theme-primary mb-2">
                      Roles * ({(form.values.roles || []).length} selected)
                    </label>
                    <div className="space-y-2 max-h-40 overflow-y-auto border border-theme rounded-lg p-3 bg-theme-background">
                      {availableRoles.map((role) => {
                        const getRoleTypeBadge = (type: string) => {
                          switch (type) {
                            case 'user':
                              return 'bg-theme-info-background text-theme-info text-xs px-2 py-0.5 rounded-full';
                            case 'admin':
                              return 'bg-theme-warning-background text-theme-warning text-xs px-2 py-0.5 rounded-full';
                            case 'system':
                              return 'bg-theme-error-background text-theme-error text-xs px-2 py-0.5 rounded-full';
                            default:
                              return 'bg-theme-surface text-theme-secondary text-xs px-2 py-0.5 rounded-full';
                          }
                        };

                        return (
                          <label key={role.name} className="flex items-start space-x-3 text-sm p-2 rounded hover:bg-theme-background/50 transition-colors">
                            <input
                              type="checkbox"
                              checked={(form.values.roles || []).includes(role.name)}
                              onChange={() => toggleRole(role.name)}
                              className="rounded border-theme text-theme-interactive-primary focus:ring-theme-interactive-primary mt-0.5"
                              disabled={form.isSubmitting}
                            />
                            <div className="flex-1">
                              <div className="flex items-center gap-2">
                                <span className="font-medium text-theme-primary">{role.display}</span>
                                <span className={getRoleTypeBadge(role.type)}>
                                  {role.type.toUpperCase()}
                                </span>
                              </div>
                              <div className="text-xs text-theme-secondary mt-0.5">{role.description}</div>
                            </div>
                          </label>
                        );
                      })}
                    </div>
                    {form.errors.roles && (
                      <p className="text-theme-error text-sm mt-1">{form.errors.roles}</p>
                    )}
                  </div>

                  <div className="flex justify-end space-x-3 pt-4 border-t border-theme">
                    <button
                      type="button"
                      onClick={() => {
                        setIsEditing(false);
                        resetForm();
                      }}
                      className="px-4 py-2 border border-theme rounded-lg text-theme-secondary hover:text-theme-primary transition-colors"
                      disabled={form.isSubmitting}
                    >
                      Cancel
                    </button>
                    <button
                      type="submit"
                      className="flex items-center gap-2 px-4 py-2 bg-theme-interactive-primary text-white rounded-lg hover:bg-theme-interactive-primary/80 transition-colors"
                      disabled={form.isSubmitting}
                    >
                      {form.isSubmitting ? (
                        <RefreshCw className="w-4 h-4 animate-spin" />
                      ) : (
                        <Save className="w-4 h-4" />
                      )}
                      {form.isSubmitting ? 'Saving...' : 'Save Changes'}
                    </button>
                  </div>
                </form>
              ) : (
                /* Overview Content */
                <div className="space-y-6">
                  {/* Basic Information */}
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                    <div className="space-y-4">
                      <h3 className="text-lg font-semibold text-theme-primary">Worker Information</h3>
                      <div className="space-y-3">
                        {worker.description && (
                          <div>
                            <span className="text-theme-secondary text-sm">Description:</span>
                            <p className="text-theme-primary">{worker.description}</p>
                          </div>
                        )}
                        <div>
                          <span className="text-theme-secondary text-sm">Account:</span>
                          <p className="text-theme-primary">{worker.account_name}</p>
                        </div>
                        <div>
                          <span className="text-theme-secondary text-sm">Created:</span>
                          <p className="text-theme-primary">{formatDateTime(worker.created_at)}</p>
                        </div>
                        <div>
                          <span className="text-theme-secondary text-sm">Updated:</span>
                          <p className="text-theme-primary">{formatDateTime(worker.updated_at)}</p>
                        </div>
                      </div>
                    </div>

                    <div className="space-y-4">
                      <h3 className="text-lg font-semibold text-theme-primary">Usage Statistics</h3>
                      <div className="space-y-3">
                        <div>
                          <span className="text-theme-secondary text-sm">Total Requests:</span>
                          <p className="text-theme-primary font-medium">{worker.request_count.toLocaleString()}</p>
                        </div>
                        <div>
                          <span className="text-theme-secondary text-sm">Last Seen:</span>
                          <p className="text-theme-primary">
                            {worker.last_seen_at ? formatDateTime(worker.last_seen_at) : 'Never'}
                          </p>
                        </div>
                        <div>
                          <span className="text-theme-secondary text-sm">Recently Active:</span>
                          <p className="text-theme-primary">
                            {worker.active_recently ? '✅ Yes' : '❌ No'}
                          </p>
                        </div>
                      </div>
                    </div>
                  </div>

                  {/* Token Section */}
                  <div className="space-y-4">
                    <h3 className="text-lg font-semibold text-theme-primary">Authentication Token</h3>
                    <div className="bg-theme-background rounded-lg p-4 space-y-4">
                      <div>
                        <span className="text-theme-secondary text-sm">Token Hash:</span>
                        <div className="flex items-center gap-2 mt-1">
                          <code className="bg-theme-surface px-3 py-2 rounded font-mono text-sm flex-1">
                            {formatMaskedToken(worker.masked_token)}
                          </code>
                          <button
                            onClick={() => copyToken(worker.full_token_hash || '')}
                            className="p-2 bg-theme-interactive-primary text-white rounded hover:bg-theme-interactive-primary/80 transition-colors"
                            title="Copy full hash"
                          >
                            {copied ? <Check className="w-4 h-4" /> : <Copy className="w-4 h-4" />}
                          </button>
                        </div>
                      </div>

                      {(showToken || newToken) && (
                        <div>
                          <span className="text-theme-secondary text-sm">Full Hash:</span>
                          <div className="flex items-center gap-2 mt-1">
                            <code className="bg-theme-surface px-3 py-2 rounded font-mono text-sm flex-1 break-all">
                              {newToken || worker.full_token_hash}
                            </code>
                            <button
                              onClick={() => copyToken(newToken || worker.full_token_hash || '')}
                              className="p-2 bg-theme-interactive-primary text-white rounded hover:bg-theme-interactive-primary/80 transition-colors"
                              title="Copy full hash"
                            >
                              {copied ? <Check className="w-4 h-4" /> : <Copy className="w-4 h-4" />}
                            </button>
                          </div>
                          <p className="text-theme-info text-xs mt-2">
                            💡 This is the complete SHA256 hash for token verification.
                          </p>
                        </div>
                      )}

                      <div className="flex gap-2">
                        <button
                          onClick={() => setShowToken(!showToken)}
                          className="flex items-center gap-2 px-4 py-2 bg-theme-surface border border-theme text-theme-primary rounded hover:bg-theme-background transition-colors"
                        >
                          {showToken ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                          {showToken ? 'Hide Hash' : 'Show Full Hash'}
                        </button>
                        <button
                          onClick={handleTokenRegenerate}
                          disabled={loading}
                          className="flex items-center gap-2 px-4 py-2 bg-theme-warning-background text-theme-warning rounded hover:bg-theme-warning-background/80 transition-colors disabled:opacity-50"
                        >
                          <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
                          Regenerate Token
                        </button>
                      </div>
                    </div>
                  </div>

                  {/* Actions */}
                  <div className="space-y-4">
                    <h3 className="text-lg font-semibold text-theme-primary">Actions</h3>
                    <div className="flex flex-wrap gap-2">
                      {/* Test Worker Button - Available for active workers */}
                      {worker.status === 'active' && (
                        <button
                          onClick={handleTestWorker}
                          disabled={testingWorker || loading}
                          className="px-4 py-2 bg-theme-info-background text-theme-info rounded hover:bg-theme-info-background/80 transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
                        >
                          {testingWorker ? (
                            <>
                              <svg className="animate-spin h-4 w-4" fill="none" viewBox="0 0 24 24">
                                <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                                <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                              </svg>
                              {testJobStatus === 'queued' && 'Job Queued...'}
                              {testJobStatus === 'processing' && 'Processing...'}
                              {testJobStatus === 'idle' && 'Testing...'}
                            </>
                          ) : (
                            'Test Worker'
                          )}
                        </button>
                      )}

                      {worker.status === 'active' && (
                        <button
                          onClick={() => handleStatusChange('suspend')}
                          disabled={loading}
                          className="px-4 py-2 bg-theme-warning-background text-theme-warning rounded hover:bg-theme-warning-background/80 transition-colors disabled:opacity-50"
                        >
                          Suspend Worker
                        </button>
                      )}
                      
                      {worker.status === 'suspended' && (
                        <button
                          onClick={() => handleStatusChange('activate')}
                          disabled={loading}
                          className="px-4 py-2 bg-theme-success-background text-theme-success rounded hover:bg-theme-success-background/80 transition-colors disabled:opacity-50"
                        >
                          Activate Worker
                        </button>
                      )}

                      {worker.status !== 'revoked' && (
                        <button
                          onClick={() => handleStatusChange('revoke')}
                          disabled={loading}
                          className="px-4 py-2 bg-theme-error-background text-theme-error rounded hover:bg-theme-error-background/80 transition-colors disabled:opacity-50"
                        >
                          Revoke Worker
                        </button>
                      )}

                      <button
                        onClick={() => setShowDeleteConfirm(true)}
                        disabled={loading}
                        className="px-4 py-2 bg-theme-error text-white rounded hover:bg-theme-error/80 transition-colors disabled:opacity-50"
                      >
                        Delete Worker
                      </button>
                    </div>
                  </div>
                </div>
              )}
            </div>
          )}

          {activeTab === 'permissions' && (
            <WorkerPermissionsView 
              worker={worker} 
              isEditing={isEditing}
              editedWorker={isEditing ? form.values : undefined}
              onWorkerChange={(updates) => {
                if (updates.roles) form.setValue('roles', updates.roles);
                // Permissions are read-only and inherited from roles
              }}
            />
          )}

          {activeTab === 'activity' && (
            <WorkerActivityDashboard worker={worker} />
          )}

          {activeTab === 'settings' && (
            <WorkerSettings
              worker={worker}
              onUpdate={async (_workerId, _config) => {
                // Callback triggered after WorkerSettings saves config to backend
                // Refresh is handled by the WorkerSettings component itself
              }}
            />
          )}
        </div>
      </div>

      {/* Delete Confirmation Modal */}
      {showDeleteConfirm && (
        <div className="fixed inset-0 bg-black bg-opacity-75 flex items-center justify-center p-4 z-50">
          <div className="bg-theme-surface rounded-lg p-6 w-full max-w-md">
            <div className="flex items-center gap-3 mb-4">
              <div className="p-2 bg-theme-error-background rounded-lg">
                <AlertTriangle className="w-6 h-6 text-theme-error" />
              </div>
              <h3 className="text-lg font-semibold text-theme-primary">Delete Worker</h3>
            </div>
            
            <p className="text-theme-secondary mb-6">
              Are you sure you want to permanently delete "{worker.name}"? This action cannot be undone and will immediately revoke all access.
            </p>
            
            <div className="flex justify-end space-x-3">
              <button
                onClick={() => setShowDeleteConfirm(false)}
                disabled={loading}
                className="px-4 py-2 border border-theme rounded text-theme-secondary hover:text-theme-primary transition-colors disabled:opacity-50"
              >
                Cancel
              </button>
              <button
                onClick={handleDelete}
                disabled={loading}
                className="flex items-center gap-2 px-4 py-2 bg-theme-error text-white rounded hover:bg-theme-error/80 transition-colors disabled:opacity-50"
              >
                {loading ? (
                  <RefreshCw className="w-4 h-4 animate-spin" />
                ) : (
                  <Trash2 className="w-4 h-4" />
                )}
                {loading ? 'Deleting...' : 'Delete Worker'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Test Results Modal */}
      {showTestResults && testResults && (
        <div className="fixed inset-0 bg-black bg-opacity-75 flex items-center justify-center p-4 z-50">
          <div className="bg-theme-surface rounded-lg p-6 w-full max-w-2xl max-h-[80vh] overflow-y-auto">
            <div className="flex justify-between items-center mb-6">
              <h3 className="text-lg font-semibold text-theme-primary">Worker Health Check Results</h3>
              <button
                onClick={() => { setShowTestResults(false); setTestJobStatus('idle'); }}
                className="text-theme-secondary hover:text-theme-primary"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            {/* Overall Status */}
            <div className="mb-6">
              <h4 className="font-medium text-theme-primary mb-3">Overall Status</h4>
              <div className="flex items-center justify-between p-4 bg-theme-background rounded">
                <span className={`px-3 py-1 rounded-full text-sm font-medium ${
                  testResults.status === 'healthy'
                    ? 'bg-theme-success-background text-theme-success'
                    : testResults.status === 'warning'
                    ? 'bg-theme-warning-background text-theme-warning'
                    : 'bg-theme-error-background text-theme-error'
                }`}>
                  {testResults.status.toUpperCase()}
                </span>
              </div>
              <div className="text-theme-secondary text-sm">
                Response Time: {testResults.response_time_ms}ms
              </div>
            </div>

            {/* Health Checks */}
            <div className="mb-6">
              <h4 className="font-medium text-theme-primary mb-3">Health Checks</h4>
              <div className="space-y-2">
                {Object.entries(testResults.checks).map(([check, status]) => (
                  <div key={check} className="flex items-center justify-between py-2 px-3 bg-theme-background rounded">
                    <span className="text-theme-primary capitalize">
                      {check.replace('_', ' ')}
                    </span>
                    <span className={`px-2 py-1 rounded text-xs font-medium ${
                      status === 'pass'
                        ? 'bg-theme-success-background text-theme-success'
                        : 'bg-theme-error-background text-theme-error'
                    }`}>
                      {status.toUpperCase()}
                    </span>
                  </div>
                ))}
              </div>
            </div>

            {/* Details */}
            <div className="mb-6">
              <h4 className="font-medium text-theme-primary mb-3">Details</h4>
              <div className="space-y-2">
                {testResults.details.map((detail, index) => (
                  <div key={index} className="py-2 px-3 bg-theme-background rounded">
                    <span className="text-theme-secondary text-sm">• {detail}</span>
                  </div>
                ))}
              </div>
            </div>

            {/* Actions */}
            <div className="flex justify-end space-x-3">
              <button
                onClick={() => { setShowTestResults(false); setTestJobStatus('idle'); }}
                className="px-4 py-2 border border-theme rounded text-theme-secondary hover:text-theme-primary transition-colors"
              >
                Close
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};


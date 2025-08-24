import React, { useState, useEffect, useCallback } from 'react';
import { Worker, WorkerDetailsResponse, workerAPI, UpdateWorkerData } from '@/features/workers/services/workerApi';
import { WorkerActivityList } from './WorkerActivityList';
import { WorkerEditForm } from './WorkerEditForm';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { copyToClipboard } from '@/shared/utils/clipboard';

// Helper function to format masked tokens with appropriate asterisks
const formatMaskedToken = (maskedToken: string): string => {
  // If token looks like "swt_****...****" format, keep it as is
  if (maskedToken.includes('_') && maskedToken.length < 25) {
    return maskedToken;
  }
  
  // For longer tokens, show first 8 chars + ****** + last 4 chars
  if (maskedToken.length > 20) {
    const start = maskedToken.substring(0, 8);
    const end = maskedToken.substring(maskedToken.length - 4);
    return `${start}******${end}`;
  }
  
  return maskedToken;
};

interface WorkerDetailsProps {
  worker: Worker;
  editMode?: boolean;
  onWorkerUpdate: (workerId: string, data: any) => Promise<any>;
  onTokenRegenerate: (workerId: string) => Promise<string>;
  onStatusChange: (workerId: string, action: 'suspend' | 'activate' | 'revoke') => Promise<any>;
  initialTab?: 'overview' | 'activities' | 'settings' | 'edit';
}

export const WorkerDetails: React.FC<WorkerDetailsProps> = ({
WorkerDetails.displayName = 'WorkerDetails';
  worker,
  editMode = false,
  onWorkerUpdate,
  onTokenRegenerate,
  onStatusChange,
  initialTab = 'overview'
}) => {
  const [details, setDetails] = useState<WorkerDetailsResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<'overview' | 'activities' | 'settings' | 'edit'>(editMode ? 'edit' : initialTab);
  const [showToken, setShowToken] = useState(false);
  const [newToken, setNewToken] = useState<string | null>(null);
  const [showConfirmRevoke, setShowConfirmRevoke] = useState(false);

  const loadWorkerDetails = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const response = await workerAPI.getWorker(worker.id);
      setDetails(response);
    } catch (err: any) {
      setError(err.message || 'Failed to load worker details');
    } finally {
      setLoading(false);
    }
  }, [worker.id]);

  useEffect(() => {
    loadWorkerDetails();
  }, [loadWorkerDetails]);

  const handleTokenRegenerate = async () => {
    try {
      const newTokenValue = await onTokenRegenerate(worker.id);
      setNewToken(newTokenValue);
      setShowToken(true);
      await loadWorkerDetails();
    } catch (err: any) {
      console.error('Failed to regenerate token:', err);
    }
  };

  const handleStatusChange = async (action: 'suspend' | 'activate' | 'revoke') => {
    try {
      await onStatusChange(worker.id, action);
      await loadWorkerDetails();
      if (action === 'revoke') {
        setShowConfirmRevoke(false);
      }
    } catch (err: any) {
      console.error('Failed to change worker status:', err);
    }
  };

  const copyToken = async (token: string) => {
    try {
      await copyToClipboard(token);
      // Could add a toast notification here
    } catch (err) {
      console.error('Failed to copy token:', err);
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'active': return 'bg-theme-success-background text-theme-success';
      case 'suspended': return 'bg-theme-warning-background text-theme-warning';
      case 'revoked': return 'bg-theme-error-background text-theme-error';
      default: return 'bg-theme-surface text-theme-secondary';
    }
  };

  const getPermissionColor = (permission: string) => {
    switch (permission) {
      case 'super_admin': return 'bg-theme-error-background text-theme-error';
      case 'admin': return 'bg-theme-warning-background text-theme-warning';
      case 'standard': return 'bg-theme-success-background text-theme-success';
      case 'readonly': return 'bg-theme-info-background text-theme-info';
      default: return 'bg-theme-surface text-theme-secondary';
    }
  };

  const getRoleColor = (role: string) => {
    switch (role) {
      case 'system': return 'bg-theme-error-background text-theme-error';
      case 'user': return 'bg-theme-info-background text-theme-info';
      default: return 'bg-theme-surface text-theme-secondary';
    }
  };

  if (loading) {
    return (
      <div className="flex justify-center py-8">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  if (error) {
    return (
      <div className="text-center py-8">
        <div className="bg-theme-error-background rounded-lg p-4 max-w-md mx-auto">
          <p className="text-theme-error font-medium">Error Loading Worker Details</p>
          <p className="text-theme-error text-sm mt-1">{error}</p>
          <button
            onClick={loadWorkerDetails}
            className="btn-theme btn-theme-danger mt-3"
          >
            Try Again
          </button>
        </div>
      </div>
    );
  }

  const currentWorker = details?.worker || worker;

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="border-b border-theme pb-4">
        <div className="flex justify-between items-start">
          <div>
            <h2 className="text-2xl font-bold text-theme-primary">{currentWorker.name}</h2>
            {currentWorker.description && (
              <p className="text-theme-secondary mt-1">{currentWorker.description}</p>
            )}
            <div className="flex flex-wrap gap-2 mt-3">
              <span className={`px-3 py-1 rounded-full text-sm font-medium ${getStatusColor(currentWorker.status)}`}>
                {currentWorker.status}
              </span>
              <span className={`px-3 py-1 rounded-full text-sm font-medium ${getPermissionColor(currentWorker.permissions)}`}>
                {currentWorker.permissions}
              </span>
              <span className={`px-3 py-1 rounded-full text-sm font-medium ${getRoleColor(currentWorker.role)}`}>
                {currentWorker.role}
              </span>
            </div>
          </div>
        </div>
      </div>

      {/* Tabs */}
      <div className="border-b border-theme">
        <nav className="flex space-x-8">
          {['overview', 'activities', 'settings', 'edit'].map((tab) => (
            <button
              key={tab}
              onClick={() => setActiveTab(tab as any)}
              className={`py-2 px-1 border-b-2 font-medium text-sm transition-colors ${
                activeTab === tab
                  ? 'border-theme-interactive-primary text-theme-interactive-primary'
                  : 'border-transparent text-theme-secondary hover:text-theme-primary hover:border-theme-secondary'
              }`}
            >
              {tab.charAt(0).toUpperCase() + tab.slice(1)}
            </button>
          ))}
        </nav>
      </div>

      {/* Tab Content */}
      <div className="mt-6">
        {activeTab === 'overview' && (
          <div className="space-y-6">
            {/* Basic Information */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div className="space-y-4">
                <h3 className="text-lg font-semibold text-theme-primary">Worker Information</h3>
                <div className="space-y-3">
                  <div>
                    <span className="text-theme-secondary text-sm">Name:</span>
                    <p className="text-theme-primary font-medium">{currentWorker.name}</p>
                  </div>
                  <div>
                    <span className="text-theme-secondary text-sm">Account:</span>
                    <p className="text-theme-primary">{currentWorker.account_name}</p>
                  </div>
                  <div>
                    <span className="text-theme-secondary text-sm">Role:</span>
                    <p className="text-theme-primary">{currentWorker.role}</p>
                  </div>
                  <div>
                    <span className="text-theme-secondary text-sm">Permissions:</span>
                    <p className="text-theme-primary">{currentWorker.permissions}</p>
                  </div>
                  <div>
                    <span className="text-theme-secondary text-sm">Status:</span>
                    <p className="text-theme-primary">{currentWorker.status}</p>
                  </div>
                </div>
              </div>

              <div className="space-y-4">
                <h3 className="text-lg font-semibold text-theme-primary">Usage Statistics</h3>
                <div className="space-y-3">
                  <div>
                    <span className="text-theme-secondary text-sm">Total Requests:</span>
                    <p className="text-theme-primary font-medium">{currentWorker.request_count.toLocaleString()}</p>
                  </div>
                  <div>
                    <span className="text-theme-secondary text-sm">Last Seen:</span>
                    <p className="text-theme-primary">
                      {currentWorker.last_seen_at 
                        ? new Date(currentWorker.last_seen_at).toLocaleString()
                        : 'Never'
                      }
                    </p>
                  </div>
                  <div>
                    <span className="text-theme-secondary text-sm">Created:</span>
                    <p className="text-theme-primary">{new Date(currentWorker.created_at).toLocaleString()}</p>
                  </div>
                  <div>
                    <span className="text-theme-secondary text-sm">Updated:</span>
                    <p className="text-theme-primary">{new Date(currentWorker.updated_at).toLocaleString()}</p>
                  </div>
                </div>
              </div>
            </div>

            {/* Token Section */}
            <div className="space-y-4">
              <h3 className="text-lg font-semibold text-theme-primary">Authentication Token</h3>
              <div className="bg-theme-background rounded-lg p-4 space-y-4">
                <div>
                  <span className="text-theme-secondary text-sm">Masked Token:</span>
                  <div className="flex items-center gap-2 mt-1">
                    <code className="bg-theme-surface px-3 py-2 rounded font-mono text-sm">
                      {formatMaskedToken(currentWorker.masked_token)}
                    </code>
                    <button
                      onClick={() => copyToken(currentWorker.masked_token)}
                      className="px-3 py-1 bg-theme-interactive-primary text-white rounded text-sm hover:bg-theme-interactive-primary/80 transition-colors"
                    >
                      Copy
                    </button>
                  </div>
                </div>

                {showToken && currentWorker.token && (
                  <div>
                    <span className="text-theme-secondary text-sm">Full Token:</span>
                    <div className="flex items-center gap-2 mt-1">
                      <code className="bg-theme-surface px-3 py-2 rounded font-mono text-sm break-all">
                        {newToken || currentWorker.token}
                      </code>
                      <button
                        onClick={() => copyToken(newToken || currentWorker.token!)}
                        className="px-3 py-1 bg-theme-interactive-primary text-white rounded text-sm hover:bg-theme-interactive-primary/80 transition-colors"
                      >
                        Copy
                      </button>
                    </div>
                    <p className="text-theme-warning text-xs mt-2">
                      ⚠️ Store this token securely. It won't be shown again.
                    </p>
                  </div>
                )}

                <div className="flex gap-2">
                  <button
                    onClick={() => setShowToken(!showToken)}
                    className="px-4 py-2 bg-theme-surface border border-theme text-theme-primary rounded hover:bg-theme-background transition-colors"
                  >
                    {showToken ? 'Hide Token' : 'Show Full Token'}
                  </button>
                  <button
                    onClick={handleTokenRegenerate}
                    className="px-4 py-2 bg-theme-warning-background text-theme-warning rounded hover:bg-theme-warning-background/80 transition-colors"
                  >
                    Regenerate Token
                  </button>
                </div>
              </div>
            </div>

            {/* Actions */}
            <div className="space-y-4">
              <h3 className="text-lg font-semibold text-theme-primary">Actions</h3>
              <div className="flex flex-wrap gap-2">
                {currentWorker.status === 'active' && (
                  <button
                    onClick={() => handleStatusChange('suspend')}
                    className="px-4 py-2 bg-theme-warning-background text-theme-warning rounded hover:bg-theme-warning-background/80 transition-colors"
                  >
                    Suspend Worker
                  </button>
                )}
                
                {currentWorker.status === 'suspended' && (
                  <button
                    onClick={() => handleStatusChange('activate')}
                    className="px-4 py-2 bg-theme-success-background text-theme-success rounded hover:bg-theme-success-background/80 transition-colors"
                  >
                    Activate Worker
                  </button>
                )}

                {currentWorker.status !== 'revoked' && (
                  <button
                    onClick={() => setShowConfirmRevoke(true)}
                    className="px-4 py-2 bg-theme-error-background text-theme-error rounded hover:bg-theme-error-background/80 transition-colors"
                  >
                    Revoke Worker
                  </button>
                )}
              </div>
            </div>
          </div>
        )}

        {activeTab === 'activities' && (
          <WorkerActivityList workerId={worker.id} />
        )}

        {activeTab === 'edit' && (
          <WorkerEditForm
            worker={currentWorker}
            onUpdate={async (data: UpdateWorkerData) => {
              await onWorkerUpdate(worker.id, data);
              setActiveTab('overview');
            }}
            onCancel={() => setActiveTab('overview')}
          />
        )}

        {activeTab === 'settings' && (
          <div className="space-y-6">
            <h3 className="text-lg font-semibold text-theme-primary">Worker Settings</h3>
            <p className="text-theme-secondary">Additional worker settings and configurations will be available here.</p>
          </div>
        )}
      </div>

      {/* Confirm Revoke Modal */}
      {showConfirmRevoke && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
          <div className="bg-theme-surface rounded-lg p-6 w-full max-w-md">
            <h3 className="text-lg font-semibold text-theme-primary mb-4">Revoke Worker</h3>
            <p className="text-theme-secondary mb-6">
              Are you sure you want to revoke this worker? This action cannot be undone and will immediately disable all access.
            </p>
            <div className="flex justify-end space-x-3">
              <button
                onClick={() => setShowConfirmRevoke(false)}
                className="px-4 py-2 border border-theme rounded text-theme-secondary hover:text-theme-primary transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={() => handleStatusChange('revoke')}
                className="px-4 py-2 bg-theme-error-background text-theme-error rounded hover:bg-theme-error-background/80 transition-colors"
              >
                Revoke Worker
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default WorkerDetails;
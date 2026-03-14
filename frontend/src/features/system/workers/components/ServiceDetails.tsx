import React, { useState, useEffect, useCallback } from 'react';
import { Service, ServiceDetailsResponse, service_api } from '@/shared/services/system/serviceApi';
import { ServiceActivityList } from './ServiceActivityList';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { copyToClipboard } from '@/shared/utils/clipboard';
import { useNotifications } from '@/shared/hooks/useNotifications';

interface ServiceDetailsProps {
  service: Service;
  onTokenRegenerate: (serviceId: string) => Promise<string>;
  onStatusChange: (serviceId: string, action: 'suspend' | 'activate' | 'revoke') => Promise<void>;
}

export const ServiceDetails: React.FC<ServiceDetailsProps> = ({
  service,
  onTokenRegenerate,
  onStatusChange
}) => {
  const { addNotification } = useNotifications();
  const [details, setDetails] = useState<ServiceDetailsResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<'overview' | 'activities' | 'settings'>('overview');
  const [showToken, setShowToken] = useState(false);
  const [newToken, setNewToken] = useState<string | null>(null);
  const [showConfirmRevoke, setShowConfirmRevoke] = useState(false);

  const loadServiceDetails = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const response = await service_api.getService(service.id);
      setDetails(response);
    } catch (error) {
      const errorMessage = error instanceof Error && 'response' in error &&
                          typeof (error as { response?: { data?: { error?: string } } }).response?.data?.error === 'string'
                          ? (error as { response: { data: { error: string } } }).response.data.error
                          : 'Failed to load service details';
      setError(errorMessage);
    } finally {
      setLoading(false);
    }
  }, [service.id]);

  useEffect(() => {
    loadServiceDetails();
  }, [loadServiceDetails]);

  const handleTokenRegenerate = async () => {
    try {
      const token = await onTokenRegenerate(service.id);
      setNewToken(token);
      setShowToken(true);
      await loadServiceDetails(); // Reload to get updated details
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to regenerate token';
      addNotification({ type: 'error', message: errorMessage });
    }
  };


  const getStatusColor = (status: string) => {
    switch (status) {
      case 'active':
        return 'bg-theme-success text-theme-success border border-theme';
      case 'suspended':
        return 'bg-theme-warning text-theme-warning border border-theme';
      case 'revoked':
        return 'bg-theme-error text-theme-error border border-theme';
      default:
        return 'bg-theme-background-secondary text-theme-secondary border border-theme';
    }
  };

  if (loading) {
    return <LoadingSpinner message="Loading service details..." />;
  }

  if (error) {
    return (
      <div className="flex items-center justify-center h-full">
        <div className="text-center">
          <div className="text-theme-error text-4xl mb-4">⚠️</div>
          <p className="text-theme-error mb-4">{error}</p>
          <button
            onClick={loadServiceDetails}
            className="text-theme-link hover:text-theme-link-hover underline"
          >
            Try again
          </button>
        </div>
      </div>
    );
  }

  if (!details) {
    return <div className="flex items-center justify-center h-full">No details available</div>;
  }

  return (
    <div className="flex-1 flex flex-col h-full">
      {/* Header */}
      <div className="px-4 sm:px-6 lg:px-8 py-4 border-b border-theme bg-theme-surface">
        <div className="flex items-center justify-between mb-4">
          <div>
            <h2 className="text-xl font-semibold text-theme-primary">{service.name}</h2>
            <p className="text-sm text-theme-secondary mt-1">{service.description || 'No description provided'}</p>
          </div>
          <div className="flex items-center gap-3">
            <span className={`px-3 py-1 rounded-full border text-sm font-medium ${getStatusColor(service.status)}`}>
              {service.status.charAt(0).toUpperCase() + service.status.slice(1)}
            </span>
          </div>
        </div>

        {/* Tabs */}
        <div className="flex space-x-8">
          {['overview', 'activities', 'settings'].map((tab) => (
            <button
              key={tab}
              onClick={() => setActiveTab(tab as 'overview' | 'activities' | 'settings')}
              className={`pb-2 border-b-2 text-sm font-medium ${
                activeTab === tab
                  ? 'border-theme-link text-theme-link'
                  : 'border-transparent text-theme-secondary hover:text-theme-primary hover:border-theme'
              }`}
            >
              {tab.charAt(0).toUpperCase() + tab.slice(1)}
            </button>
          ))}
        </div>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto">
        {activeTab === 'overview' && (
          <div className="p-4 sm:p-6 lg:p-8">
            {/* Stats Cards */}
            <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
              <div className="bg-theme-surface p-4 rounded-lg border border-theme">
                <div className="text-2xl font-bold text-theme-link">{details.activity_summary.total_requests}</div>
                <div className="text-sm text-theme-secondary">Total Requests</div>
              </div>
              <div className="bg-theme-surface p-4 rounded-lg border border-theme">
                <div className="text-2xl font-bold text-theme-success">{details.activity_summary.successful_requests}</div>
                <div className="text-sm text-theme-secondary">Successful</div>
              </div>
              <div className="bg-theme-surface p-4 rounded-lg border border-theme">
                <div className="text-2xl font-bold text-theme-error">{details.activity_summary.failed_requests}</div>
                <div className="text-sm text-theme-secondary">Failed</div>
              </div>
              <div className="bg-theme-surface p-4 rounded-lg border border-theme">
                <div className="text-2xl font-bold text-theme-info">{details.activity_summary.unique_actions.length}</div>
                <div className="text-sm text-theme-secondary">Unique Actions</div>
              </div>
            </div>

            {/* Service Information */}
            <div className="bg-theme-surface rounded-lg border border-theme p-6 mb-6">
              <h3 className="text-lg font-medium text-theme-primary mb-4">Service Information</h3>
              <dl className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <dt className="text-sm font-medium text-theme-secondary">Account</dt>
                  <dd className="mt-1 text-sm text-theme-primary">{service.account_name}</dd>
                </div>
                <div>
                  <dt className="text-sm font-medium text-theme-secondary">Permissions</dt>
                  <dd className="mt-1 text-sm text-theme-primary capitalize">{service.permissions.replace('_', ' ')}</dd>
                </div>
                <div>
                  <dt className="text-sm font-medium text-theme-secondary">Created</dt>
                  <dd className="mt-1 text-sm text-theme-primary">{new Date(service.created_at).toLocaleString()}</dd>
                </div>
                <div>
                  <dt className="text-sm font-medium text-theme-secondary">Last Seen</dt>
                  <dd className="mt-1 text-sm text-theme-primary">
                    {service.last_seen_at ? new Date(service.last_seen_at).toLocaleString() : 'Never'}
                  </dd>
                </div>
                <div className="md:col-span-2">
                  <dt className="text-sm font-medium text-theme-secondary">Authentication Token</dt>
                  <dd className="mt-1 flex items-center gap-2">
                    <code className="text-sm bg-theme-background-secondary px-2 py-1 rounded border border-theme">
                      {showToken && newToken ? newToken : service.masked_token}
                    </code>
                    <button
                      onClick={() => copyToClipboard(showToken && newToken ? newToken : service.token || service.masked_token, { successMessage: 'Token copied to clipboard!' })}
                      className="text-theme-link hover:text-theme-link-hover text-sm transition-colors duration-150"
                    >
                      Copy
                    </button>
                    <button
                      onClick={handleTokenRegenerate}
                      className="text-theme-warning hover:text-theme-warning text-sm transition-colors duration-150 opacity-80 hover:opacity-100"
                    >
                      Regenerate
                    </button>
                  </dd>
                </div>
              </dl>
            </div>

            {/* Recent Activity */}
            <div className="bg-theme-surface rounded-lg border border-theme p-6">
              <h3 className="text-lg font-medium text-theme-primary mb-4">Recent Activity</h3>
              {details.recent_activities.length > 0 ? (
                <div className="space-y-3">
                  {details.recent_activities.slice(0, 5).map((activity) => (
                    <div key={activity.id} className="flex items-center justify-between py-2 border-b border-theme last:border-0">
                      <div className="flex items-center gap-3">
                        <div className={`w-2 h-2 rounded-full ${activity.successful ? 'bg-theme-success-solid' : 'bg-theme-danger-solid'}`}></div>
                        <div>
                          <div className="text-sm font-medium text-theme-primary">{activity.action}</div>
                          <div className="text-xs text-theme-secondary">
                            {new Date(activity.performed_at).toLocaleString()}
                          </div>
                        </div>
                      </div>
                      <div className="text-xs text-theme-secondary">
                        {activity.duration && `${activity.duration}ms`}
                      </div>
                    </div>
                  ))}
                  <button
                    onClick={() => setActiveTab('activities')}
                    className="text-theme-link hover:text-theme-link-hover text-sm mt-3 transition-colors duration-150"
                  >
                    View all activities →
                  </button>
                </div>
              ) : (
                <p className="text-theme-secondary text-sm">No recent activity</p>
              )}
            </div>
          </div>
        )}

        {activeTab === 'activities' && (
          <ServiceActivityList service={service} />
        )}

        {activeTab === 'settings' && (
          <div className="p-4 sm:p-6 lg:p-8">
            <div className="bg-theme-surface rounded-lg border border-theme p-6">
              <h3 className="text-lg font-medium text-theme-primary mb-4">Service Settings</h3>
              <p className="text-sm text-theme-secondary mb-4">
                Configure service permissions and status. Changes take effect immediately.
              </p>
              
              <div className="space-y-4">
                <div className="flex items-center justify-between p-4 bg-theme-background-secondary border border-theme rounded-lg">
                  <div>
                    <h4 className="font-medium text-theme-primary">Service Status</h4>
                    <p className="text-sm text-theme-secondary">Control whether this service can authenticate</p>
                  </div>
                  <div className="flex gap-2">
                    {service.status === 'active' && (
                      <button
                        onClick={() => onStatusChange(service.id, 'suspend')}
                        className="px-3 py-1 bg-theme-warning text-theme-warning rounded text-sm hover:bg-theme-warning border border-theme font-medium transition-colors duration-200 opacity-90 hover:opacity-100"
                      >
                        Suspend
                      </button>
                    )}
                    {service.status === 'suspended' && (
                      <button
                        onClick={() => onStatusChange(service.id, 'activate')}
                        className="px-3 py-1 bg-theme-success text-theme-success rounded text-sm hover:bg-theme-success border border-theme font-medium transition-colors duration-200 opacity-90 hover:opacity-100"
                      >
                        Activate
                      </button>
                    )}
                    {service.status !== 'revoked' && (
                      <button
                        onClick={() => setShowConfirmRevoke(true)}
                        className="px-3 py-1 bg-theme-error text-theme-error rounded text-sm hover:bg-theme-error border border-theme font-medium transition-colors duration-200 opacity-90 hover:opacity-100"
                      >
                        Revoke
                      </button>
                    )}
                  </div>
                </div>

                <div className="p-4 bg-theme-background-secondary border border-theme rounded-lg">
                  <h4 className="font-medium text-theme-primary mb-2">Token Management</h4>
                  <p className="text-sm text-theme-secondary mb-3">
                    Regenerate the authentication token if it has been compromised.
                  </p>
                  <button
                    onClick={handleTokenRegenerate}
                    className="px-4 py-2 bg-theme-interactive-primary text-white rounded text-sm hover:bg-theme-interactive-primary-hover transition-colors duration-200"
                  >
                    Regenerate Token
                  </button>
                </div>
              </div>
            </div>
          </div>
        )}
      </div>

      {/* New Token Modal */}
      {newToken && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div className="bg-theme-surface rounded-lg p-6 max-w-md w-full mx-4">
            <h3 className="text-lg font-medium text-theme-primary mb-4">New Token Generated</h3>
            <p className="text-sm text-theme-secondary mb-4">
              Copy this token now - it won't be shown again for security reasons.
            </p>
            <div className="bg-theme-background-secondary border border-theme rounded p-3 mb-4">
              <code className="text-sm break-all">{newToken}</code>
            </div>
            <div className="flex gap-3">
              <button
                onClick={() => copyToClipboard(newToken, { successMessage: 'New token copied to clipboard!' })}
                className="flex-1 bg-theme-interactive-primary text-white px-4 py-2 rounded text-sm hover:bg-theme-interactive-primary-hover transition-colors duration-200"
              >
                Copy Token
              </button>
              <button
                onClick={() => setNewToken(null)}
                className="px-4 py-2 border border-theme text-theme-primary rounded text-sm hover:bg-theme-surface-hover transition-colors duration-200"
              >
                Close
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Confirm Revoke Modal */}
      {showConfirmRevoke && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div className="bg-theme-surface rounded-lg p-6 max-w-md w-full mx-4">
            <h3 className="text-lg font-medium text-theme-primary mb-4">Revoke Service</h3>
            <p className="text-sm text-theme-secondary mb-4">
              Are you sure you want to revoke this service? This action cannot be undone and will permanently disable authentication for this service.
            </p>
            <div className="flex gap-3">
              <button
                onClick={() => {
                  onStatusChange(service.id, 'revoke');
                  setShowConfirmRevoke(false);
                }}className="flex-1 bg-theme-error text-white px-4 py-2 rounded text-sm hover:bg-theme-error transition-colors duration-200 opacity-90 hover:opacity-100"
              >
                Yes, Revoke Service
              </button>
              <button
                onClick={() => setShowConfirmRevoke(false)}
                className="px-4 py-2 border border-theme text-theme-primary rounded text-sm hover:bg-theme-surface-hover transition-colors duration-200"
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};


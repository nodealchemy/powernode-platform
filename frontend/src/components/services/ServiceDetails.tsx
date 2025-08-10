import React, { useState, useEffect, useCallback } from 'react';
import { Service, ServiceDetailsResponse, serviceAPI } from '../../services/serviceApi';
import { ServiceActivityList } from './ServiceActivityList';
import { LoadingSpinner } from '../common/LoadingSpinner';

interface ServiceDetailsProps {
  service: Service;
  onServiceUpdate: (serviceId: string, data: any) => Promise<any>;
  onTokenRegenerate: (serviceId: string) => Promise<string>;
  onStatusChange: (serviceId: string, action: 'suspend' | 'activate' | 'revoke') => Promise<any>;
}

export const ServiceDetails: React.FC<ServiceDetailsProps> = ({
  service,
  onServiceUpdate,
  onTokenRegenerate,
  onStatusChange
}) => {
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
      const response = await serviceAPI.getService(service.id);
      setDetails(response);
    } catch (error: any) {
      setError(error.response?.data?.error || 'Failed to load service details');
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
    } catch (error: any) {
      alert(error.message);
    }
  };

  const copyToClipboard = (text: string) => {
    navigator.clipboard.writeText(text);
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'active':
        return 'bg-green-100 text-green-800 border-green-200';
      case 'suspended':
        return 'bg-yellow-100 text-yellow-800 border-yellow-200';
      case 'revoked':
        return 'bg-red-100 text-red-800 border-red-200';
      default:
        return 'bg-gray-100 text-gray-800 border-gray-200';
    }
  };

  if (loading) {
    return <LoadingSpinner message="Loading service details..." />;
  }

  if (error) {
    return (
      <div className="flex items-center justify-center h-full">
        <div className="text-center">
          <div className="text-red-500 text-4xl mb-4">⚠️</div>
          <p className="text-red-600 mb-4">{error}</p>
          <button
            onClick={loadServiceDetails}
            className="text-blue-600 hover:text-blue-700 underline"
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
      <div className="px-6 py-4 border-b border-gray-200 bg-white">
        <div className="flex items-center justify-between mb-4">
          <div>
            <h2 className="text-xl font-semibold text-gray-900">{service.name}</h2>
            <p className="text-sm text-gray-600 mt-1">{service.description || 'No description provided'}</p>
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
              onClick={() => setActiveTab(tab as any)}
              className={`pb-2 border-b-2 text-sm font-medium ${
                activeTab === tab
                  ? 'border-blue-600 text-blue-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
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
          <div className="p-6">
            {/* Stats Cards */}
            <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
              <div className="bg-white p-4 rounded-lg border border-gray-200">
                <div className="text-2xl font-bold text-blue-600">{details.activity_summary.total_requests}</div>
                <div className="text-sm text-gray-600">Total Requests</div>
              </div>
              <div className="bg-white p-4 rounded-lg border border-gray-200">
                <div className="text-2xl font-bold text-green-600">{details.activity_summary.successful_requests}</div>
                <div className="text-sm text-gray-600">Successful</div>
              </div>
              <div className="bg-white p-4 rounded-lg border border-gray-200">
                <div className="text-2xl font-bold text-red-600">{details.activity_summary.failed_requests}</div>
                <div className="text-sm text-gray-600">Failed</div>
              </div>
              <div className="bg-white p-4 rounded-lg border border-gray-200">
                <div className="text-2xl font-bold text-purple-600">{details.activity_summary.unique_actions.length}</div>
                <div className="text-sm text-gray-600">Unique Actions</div>
              </div>
            </div>

            {/* Service Information */}
            <div className="bg-white rounded-lg border border-gray-200 p-6 mb-6">
              <h3 className="text-lg font-medium text-gray-900 mb-4">Service Information</h3>
              <dl className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <dt className="text-sm font-medium text-gray-500">Account</dt>
                  <dd className="mt-1 text-sm text-gray-900">{service.account_name}</dd>
                </div>
                <div>
                  <dt className="text-sm font-medium text-gray-500">Permissions</dt>
                  <dd className="mt-1 text-sm text-gray-900 capitalize">{service.permissions.replace('_', ' ')}</dd>
                </div>
                <div>
                  <dt className="text-sm font-medium text-gray-500">Created</dt>
                  <dd className="mt-1 text-sm text-gray-900">{new Date(service.created_at).toLocaleString()}</dd>
                </div>
                <div>
                  <dt className="text-sm font-medium text-gray-500">Last Seen</dt>
                  <dd className="mt-1 text-sm text-gray-900">
                    {service.last_seen_at ? new Date(service.last_seen_at).toLocaleString() : 'Never'}
                  </dd>
                </div>
                <div className="md:col-span-2">
                  <dt className="text-sm font-medium text-gray-500">Authentication Token</dt>
                  <dd className="mt-1 flex items-center gap-2">
                    <code className="text-sm bg-gray-100 px-2 py-1 rounded border">
                      {showToken && newToken ? newToken : service.masked_token}
                    </code>
                    <button
                      onClick={() => copyToClipboard(showToken && newToken ? newToken : service.token || service.masked_token)}
                      className="text-blue-600 hover:text-blue-700 text-sm"
                    >
                      Copy
                    </button>
                    <button
                      onClick={handleTokenRegenerate}
                      className="text-orange-600 hover:text-orange-700 text-sm"
                    >
                      Regenerate
                    </button>
                  </dd>
                </div>
              </dl>
            </div>

            {/* Recent Activity */}
            <div className="bg-white rounded-lg border border-gray-200 p-6">
              <h3 className="text-lg font-medium text-gray-900 mb-4">Recent Activity</h3>
              {details.recent_activities.length > 0 ? (
                <div className="space-y-3">
                  {details.recent_activities.slice(0, 5).map((activity) => (
                    <div key={activity.id} className="flex items-center justify-between py-2 border-b border-gray-100 last:border-0">
                      <div className="flex items-center gap-3">
                        <div className={`w-2 h-2 rounded-full ${activity.successful ? 'bg-green-500' : 'bg-red-500'}`}></div>
                        <div>
                          <div className="text-sm font-medium text-gray-900">{activity.action}</div>
                          <div className="text-xs text-gray-500">
                            {new Date(activity.performed_at).toLocaleString()}
                          </div>
                        </div>
                      </div>
                      <div className="text-xs text-gray-500">
                        {activity.duration && `${activity.duration}ms`}
                      </div>
                    </div>
                  ))}
                  <button
                    onClick={() => setActiveTab('activities')}
                    className="text-blue-600 hover:text-blue-700 text-sm mt-3"
                  >
                    View all activities →
                  </button>
                </div>
              ) : (
                <p className="text-gray-500 text-sm">No recent activity</p>
              )}
            </div>
          </div>
        )}

        {activeTab === 'activities' && (
          <ServiceActivityList service={service} />
        )}

        {activeTab === 'settings' && (
          <div className="p-6">
            <div className="bg-white rounded-lg border border-gray-200 p-6">
              <h3 className="text-lg font-medium text-gray-900 mb-4">Service Settings</h3>
              <p className="text-sm text-gray-600 mb-4">
                Configure service permissions and status. Changes take effect immediately.
              </p>
              
              <div className="space-y-4">
                <div className="flex items-center justify-between p-4 border border-gray-200 rounded-lg">
                  <div>
                    <h4 className="font-medium text-gray-900">Service Status</h4>
                    <p className="text-sm text-gray-600">Control whether this service can authenticate</p>
                  </div>
                  <div className="flex gap-2">
                    {service.status === 'active' && (
                      <button
                        onClick={() => onStatusChange(service.id, 'suspend')}
                        className="px-3 py-1 bg-yellow-100 text-yellow-800 rounded text-sm hover:bg-yellow-200"
                      >
                        Suspend
                      </button>
                    )}
                    {service.status === 'suspended' && (
                      <button
                        onClick={() => onStatusChange(service.id, 'activate')}
                        className="px-3 py-1 bg-green-100 text-green-800 rounded text-sm hover:bg-green-200"
                      >
                        Activate
                      </button>
                    )}
                    {service.status !== 'revoked' && (
                      <button
                        onClick={() => setShowConfirmRevoke(true)}
                        className="px-3 py-1 bg-red-100 text-red-800 rounded text-sm hover:bg-red-200"
                      >
                        Revoke
                      </button>
                    )}
                  </div>
                </div>

                <div className="p-4 border border-gray-200 rounded-lg">
                  <h4 className="font-medium text-gray-900 mb-2">Token Management</h4>
                  <p className="text-sm text-gray-600 mb-3">
                    Regenerate the authentication token if it has been compromised.
                  </p>
                  <button
                    onClick={handleTokenRegenerate}
                    className="px-4 py-2 bg-blue-600 text-white rounded text-sm hover:bg-blue-700"
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
          <div className="bg-white rounded-lg p-6 max-w-md w-full mx-4">
            <h3 className="text-lg font-medium text-gray-900 mb-4">New Token Generated</h3>
            <p className="text-sm text-gray-600 mb-4">
              Copy this token now - it won't be shown again for security reasons.
            </p>
            <div className="bg-gray-50 border border-gray-200 rounded p-3 mb-4">
              <code className="text-sm break-all">{newToken}</code>
            </div>
            <div className="flex gap-3">
              <button
                onClick={() => {
                  copyToClipboard(newToken);
                  alert('Token copied to clipboard!');
                }}
                className="flex-1 bg-blue-600 text-white px-4 py-2 rounded text-sm hover:bg-blue-700"
              >
                Copy Token
              </button>
              <button
                onClick={() => setNewToken(null)}
                className="px-4 py-2 border border-gray-300 text-gray-700 rounded text-sm hover:bg-gray-50"
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
          <div className="bg-white rounded-lg p-6 max-w-md w-full mx-4">
            <h3 className="text-lg font-medium text-gray-900 mb-4">Revoke Service</h3>
            <p className="text-sm text-gray-600 mb-4">
              Are you sure you want to revoke this service? This action cannot be undone and will permanently disable authentication for this service.
            </p>
            <div className="flex gap-3">
              <button
                onClick={() => {
                  onStatusChange(service.id, 'revoke');
                  setShowConfirmRevoke(false);
                }}
                className="flex-1 bg-red-600 text-white px-4 py-2 rounded text-sm hover:bg-red-700"
              >
                Yes, Revoke Service
              </button>
              <button
                onClick={() => setShowConfirmRevoke(false)}
                className="px-4 py-2 border border-gray-300 text-gray-700 rounded text-sm hover:bg-gray-50"
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

export default ServiceDetails;
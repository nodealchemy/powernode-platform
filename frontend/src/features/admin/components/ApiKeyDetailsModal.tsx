import React from 'react';
import { Button } from '@/shared/components/ui/Button';
import { Eye } from 'lucide-react';
import { apiKeysApi, DetailedApiKey } from '@/features/api-keys/services/apiKeysApi';

export interface ApiKeyDetailsModalProps {
  apiKey: DetailedApiKey | null;
  isOpen: boolean;
  onClose: () => void;
  onApiKeyUpdated?: () => void;
}

export const ApiKeyDetailsModal: React.FC<ApiKeyDetailsModalProps> = ({
  apiKey,
  isOpen,
  onClose,
  onApiKeyUpdated: _onApiKeyUpdated
}) => {
  if (!isOpen || !apiKey) return null;

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
      <div className="bg-theme-surface rounded-lg shadow-xl max-w-4xl w-full max-h-[90vh] overflow-hidden">
        <div className="px-6 py-4 border-b border-theme flex items-center justify-between">
          <h3 className="text-lg font-semibold text-theme-primary">{apiKey.name}</h3>
          <Button onClick={onClose} variant="outline">
            <Eye className="w-5 h-5" />
          </Button>
        </div>

        <div className="overflow-auto max-h-[calc(90vh-140px)] p-6">
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {/* Key Info */}
            <div className="space-y-4">
              <div>
                <h4 className="font-medium text-theme-primary mb-3">Key Information</h4>
                <div className="space-y-3">
                  <div>
                    <label className="text-sm text-theme-secondary">Status</label>
                    <div className={`inline-flex px-2 py-1 text-xs rounded-full ${apiKeysApi.getStatusColor(apiKey.status)}`}>
                      {apiKeysApi.getStatusText(apiKey.status)}
                    </div>
                  </div>

                  <div>
                    <label className="text-sm text-theme-secondary">Created</label>
                    <p className="text-theme-primary">{new Date(apiKey.created_at).toLocaleString()}</p>
                  </div>

                  {apiKey.expires_at && (
                    <div>
                      <label className="text-sm text-theme-secondary">Expires</label>
                      <p className="text-theme-primary">{new Date(apiKey.expires_at).toLocaleString()}</p>
                    </div>
                  )}

                  {apiKey.last_used_at && (
                    <div>
                      <label className="text-sm text-theme-secondary">Last Used</label>
                      <p className="text-theme-primary">{new Date(apiKey.last_used_at).toLocaleString()}</p>
                    </div>
                  )}

                  <div>
                    <label className="text-sm text-theme-secondary">Total Usage</label>
                    <p className="text-theme-primary">{apiKeysApi.formatUsageCount(apiKey.usage_count)} requests</p>
                  </div>
                </div>
              </div>

              {/* Scopes */}
              <div>
                <h4 className="font-medium text-theme-primary mb-3">Permissions</h4>
                <div className="space-y-2">
                  {apiKey.scopes.map((scope) => (
                    <div key={scope} className={`inline-flex px-2 py-1 text-xs rounded-full mr-2 mb-2 ${apiKeysApi.getScopeCategoryColor(scope)}`}>
                      {apiKeysApi.formatScope(scope)}
                    </div>
                  ))}
                </div>
              </div>
            </div>

            {/* Usage Stats */}
            <div className="space-y-4">
              <div>
                <h4 className="font-medium text-theme-primary mb-3">Usage Statistics</h4>
                {apiKey.usage_stats && (
                  <div className="grid grid-cols-2 gap-4">
                    <div className="bg-theme-background p-3 rounded-lg">
                      <div className="text-sm text-theme-secondary">Today</div>
                      <div className="text-lg font-semibold text-theme-primary">
                        {apiKey.usage_stats.requests_today}
                      </div>
                    </div>

                    <div className="bg-theme-background p-3 rounded-lg">
                      <div className="text-sm text-theme-secondary">This Week</div>
                      <div className="text-lg font-semibold text-theme-primary">
                        {apiKey.usage_stats.requests_this_week}
                      </div>
                    </div>

                    <div className="bg-theme-background p-3 rounded-lg">
                      <div className="text-sm text-theme-secondary">This Month</div>
                      <div className="text-lg font-semibold text-theme-primary">
                        {apiKey.usage_stats.requests_this_month}
                      </div>
                    </div>

                    <div className="bg-theme-background p-3 rounded-lg">
                      <div className="text-sm text-theme-secondary">Daily Average</div>
                      <div className="text-lg font-semibold text-theme-primary">
                        {Math.round(apiKey.usage_stats.average_requests_per_day)}
                      </div>
                    </div>
                  </div>
                )}
              </div>

              {/* Rate Limits */}
              {(apiKey.rate_limit_per_hour || apiKey.rate_limit_per_day) && (
                <div>
                  <h4 className="font-medium text-theme-primary mb-3">Rate Limits</h4>
                  <div className="space-y-2">
                    {apiKey.rate_limit_per_hour && (
                      <div className="flex justify-between">
                        <span className="text-theme-secondary">Per Hour</span>
                        <span className="text-theme-primary">{apiKey.rate_limit_per_hour.toLocaleString()}</span>
                      </div>
                    )}
                    {apiKey.rate_limit_per_day && (
                      <div className="flex justify-between">
                        <span className="text-theme-secondary">Per Day</span>
                        <span className="text-theme-primary">{apiKey.rate_limit_per_day.toLocaleString()}</span>
                      </div>
                    )}
                  </div>
                </div>
              )}

              {/* IP Restrictions */}
              {apiKey.allowed_ips && apiKey.allowed_ips.length > 0 && (
                <div>
                  <h4 className="font-medium text-theme-primary mb-3">Allowed IPs</h4>
                  <div className="space-y-1">
                    {apiKey.allowed_ips.map((ip, index) => (
                      <div key={index} className="text-sm text-theme-secondary font-mono bg-theme-background px-2 py-1 rounded">
                        {ip}
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </div>
          </div>

          {/* Recent Usage */}
          {apiKey.recent_usage && apiKey.recent_usage.length > 0 && (
            <div className="mt-6">
              <h4 className="font-medium text-theme-primary mb-3">Recent Activity</h4>
              <div className="overflow-x-auto">
                <table className="w-full">
                  <thead>
                    <tr className="border-b border-theme">
                      <th className="text-left text-sm text-theme-secondary pb-2">Endpoint</th>
                      <th className="text-left text-sm text-theme-secondary pb-2">Method</th>
                      <th className="text-left text-sm text-theme-secondary pb-2">Status</th>
                      <th className="text-left text-sm text-theme-secondary pb-2">Requests</th>
                      <th className="text-left text-sm text-theme-secondary pb-2">Time</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-theme">
                    {apiKey.recent_usage.slice(0, 10).map((usage) => (
                      <tr key={usage.id}>
                        <td className="py-2 text-sm text-theme-primary font-mono">{usage.endpoint}</td>
                        <td className="py-2 text-sm text-theme-secondary">{usage.method}</td>
                        <td className="py-2">
                          <span className={`text-xs px-2 py-1 rounded ${
                            usage.status_code < 300 ? 'bg-theme-success-background text-theme-success' :
                            usage.status_code < 400 ? 'bg-theme-warning-background text-theme-warning' :
                            'bg-theme-error-background text-theme-error'
                          }`}>
                            {usage.status_code}
                          </span>
                        </td>
                        <td className="py-2 text-sm text-theme-primary">{usage.request_count}</td>
                        <td className="py-2 text-sm text-theme-secondary">
                          {new Date(usage.created_at).toLocaleString()}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}
        </div>

        <div className="px-6 py-4 border-t border-theme flex justify-end">
          <Button onClick={onClose} variant="outline">
            Close
          </Button>
        </div>
      </div>
    </div>
  );
};

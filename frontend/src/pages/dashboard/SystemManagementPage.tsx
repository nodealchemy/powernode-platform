import React from 'react';
import { Routes, Route, Navigate } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { RootState } from '../../store';
import { TabNavigation, MobileTabNavigation } from '../../components/ui/TabNavigation';
import { Breadcrumb } from '../../components/ui/Breadcrumb';
import { hasAdminAccess } from '../../utils/permissionUtils';
import { ServicesPage } from './ServicesPage';
import PaymentGatewaysPage from './PaymentGatewaysPage';
import { AdminSettingsPage } from './AdminSettingsPage';

const tabs = [
  { id: 'services', label: 'Services', path: '/dashboard/system/services', icon: '⚡' },
  { id: 'gateways', label: 'Payment Gateways', path: '/dashboard/system/gateways', icon: '💳' },
  { id: 'admin', label: 'Admin Config', path: '/dashboard/system/admin', icon: '🔧' },
  { id: 'audit', label: 'Audit Logs', path: '/dashboard/system/audit', icon: '📝' },
  { id: 'webhooks', label: 'Webhooks', path: '/dashboard/system/webhooks', icon: '🔗' },
  { id: 'api', label: 'API Keys', path: '/dashboard/system/api', icon: '🔑' },
];

const AuditLogsPage: React.FC = () => {
  const auditLogs = [
    { id: 1, action: 'User Login', user: 'admin@example.com', ip: '192.168.1.1', timestamp: '2024-03-15 10:30:00', status: 'success' },
    { id: 2, action: 'Plan Updated', user: 'admin@example.com', ip: '192.168.1.1', timestamp: '2024-03-15 10:25:00', status: 'success' },
    { id: 3, action: 'Payment Failed', user: 'customer@example.com', ip: '203.0.113.0', timestamp: '2024-03-15 09:45:00', status: 'error' },
    { id: 4, action: 'Subscription Created', user: 'customer@example.com', ip: '203.0.113.0', timestamp: '2024-03-15 09:30:00', status: 'success' },
    { id: 5, action: 'Password Changed', user: 'user@example.com', ip: '198.51.100.0', timestamp: '2024-03-15 08:15:00', status: 'success' },
  ];

  return (
    <div className="space-y-6">
      <div className="bg-theme-surface rounded-lg p-6">
        <div className="flex justify-between items-center mb-6">
          <div>
            <h2 className="text-xl font-semibold text-theme-primary">Audit Logs</h2>
            <p className="text-theme-secondary mt-1">Track all system activities and changes</p>
          </div>
          <div className="flex space-x-3">
            <select className="px-3 py-2 border border-theme rounded-lg text-theme-primary bg-theme-background">
              <option>All Actions</option>
              <option>Authentication</option>
              <option>User Management</option>
              <option>Billing</option>
              <option>System Changes</option>
            </select>
            <input
              type="date"
              className="px-3 py-2 border border-theme rounded-lg text-theme-primary bg-theme-background"
            />
            <button className="btn-theme btn-theme-secondary">
              Export Logs
            </button>
          </div>
        </div>

        <div className="bg-theme-background rounded-lg overflow-hidden">
          <table className="w-full">
            <thead className="bg-theme-surface border-b border-theme">
              <tr>
                <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Action</th>
                <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">User</th>
                <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">IP Address</th>
                <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Timestamp</th>
                <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Status</th>
                <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Details</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-theme">
              {auditLogs.map((log) => (
                <tr key={log.id} className="hover:bg-theme-surface-hover">
                  <td className="py-3 px-4 text-theme-primary font-medium">{log.action}</td>
                  <td className="py-3 px-4 text-theme-secondary">{log.user}</td>
                  <td className="py-3 px-4 text-theme-secondary font-mono text-xs">{log.ip}</td>
                  <td className="py-3 px-4 text-theme-secondary text-sm">{log.timestamp}</td>
                  <td className="py-3 px-4">
                    <span className={`text-xs px-2 py-1 rounded-full ${
                      log.status === 'success' 
                        ? 'bg-theme-success bg-opacity-10 text-theme-success' 
                        : 'bg-theme-error bg-opacity-10 text-theme-error'
                    }`}>
                      {log.status}
                    </span>
                  </td>
                  <td className="py-3 px-4">
                    <button className="text-theme-link hover:text-theme-link-hover text-sm">
                      View
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <div className="mt-4 flex items-center justify-between">
          <p className="text-sm text-theme-secondary">
            Showing 1 to 5 of 1,234 entries
          </p>
          <div className="flex space-x-2">
            <button className="px-3 py-1 border border-theme rounded text-theme-primary hover:bg-theme-surface-hover">
              Previous
            </button>
            <button className="px-3 py-1 bg-theme-interactive-primary text-white rounded">
              1
            </button>
            <button className="px-3 py-1 border border-theme rounded text-theme-primary hover:bg-theme-surface-hover">
              2
            </button>
            <button className="px-3 py-1 border border-theme rounded text-theme-primary hover:bg-theme-surface-hover">
              3
            </button>
            <button className="px-3 py-1 border border-theme rounded text-theme-primary hover:bg-theme-surface-hover">
              Next
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};

const WebhooksPage: React.FC = () => {
  const webhooks = [
    { id: 1, url: 'https://api.example.com/webhooks/stripe', events: ['payment.success', 'payment.failed'], status: 'active', lastTriggered: '2024-03-15 10:30:00' },
    { id: 2, url: 'https://api.example.com/webhooks/subscription', events: ['subscription.created', 'subscription.updated'], status: 'active', lastTriggered: '2024-03-15 09:15:00' },
    { id: 3, url: 'https://api.example.com/webhooks/user', events: ['user.created', 'user.deleted'], status: 'inactive', lastTriggered: '2024-03-14 15:45:00' },
  ];

  return (
    <div className="space-y-6">
      <div className="bg-theme-surface rounded-lg p-6">
        <div className="flex justify-between items-center mb-6">
          <div>
            <h2 className="text-xl font-semibold text-theme-primary">Webhook Management</h2>
            <p className="text-theme-secondary mt-1">Configure webhook endpoints and event subscriptions</p>
          </div>
          <button className="btn-theme btn-theme-primary">
            Add Webhook
          </button>
        </div>

        <div className="space-y-4">
          {webhooks.map((webhook) => (
            <div key={webhook.id} className="bg-theme-background rounded-lg p-4 border border-theme">
              <div className="flex items-start justify-between">
                <div className="flex-1">
                  <div className="flex items-center space-x-3 mb-2">
                    <h3 className="font-medium text-theme-primary">{webhook.url}</h3>
                    <span className={`text-xs px-2 py-1 rounded-full ${
                      webhook.status === 'active' 
                        ? 'bg-theme-success bg-opacity-10 text-theme-success' 
                        : 'bg-theme-surface text-theme-tertiary'
                    }`}>
                      {webhook.status}
                    </span>
                  </div>
                  <div className="flex flex-wrap gap-2 mb-2">
                    {webhook.events.map((event) => (
                      <span key={event} className="text-xs bg-theme-surface px-2 py-1 rounded text-theme-secondary">
                        {event}
                      </span>
                    ))}
                  </div>
                  <p className="text-xs text-theme-tertiary">
                    Last triggered: {webhook.lastTriggered}
                  </p>
                </div>
                <div className="flex space-x-2">
                  <button className="text-theme-link hover:text-theme-link-hover text-sm">
                    Test
                  </button>
                  <button className="text-theme-link hover:text-theme-link-hover text-sm">
                    Edit
                  </button>
                  <button className="text-theme-error hover:text-theme-error-hover text-sm">
                    Delete
                  </button>
                </div>
              </div>
            </div>
          ))}
        </div>

        <div className="mt-6 bg-theme-background rounded-lg p-4 border border-theme">
          <h3 className="font-medium text-theme-primary mb-3">Webhook Events</h3>
          <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
            {[
              'payment.success', 'payment.failed', 'payment.refunded',
              'subscription.created', 'subscription.updated', 'subscription.cancelled',
              'user.created', 'user.updated', 'user.deleted',
              'invoice.created', 'invoice.paid', 'invoice.overdue'
            ].map((event) => (
              <label key={event} className="flex items-center space-x-2 text-sm">
                <input type="checkbox" className="rounded border-theme text-theme-interactive-primary" />
                <span className="text-theme-secondary">{event}</span>
              </label>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
};

const ApiKeysPage: React.FC = () => {
  const apiKeys = [
    { id: 1, name: 'Production API Key', key: 'pk_live_...abc123', created: '2024-01-15', lastUsed: '2024-03-15 10:30:00', status: 'active' },
    { id: 2, name: 'Development API Key', key: 'pk_test_...xyz789', created: '2024-02-01', lastUsed: '2024-03-15 09:15:00', status: 'active' },
    { id: 3, name: 'Mobile App Key', key: 'pk_mobile_...def456', created: '2024-02-15', lastUsed: '2024-03-14 15:45:00', status: 'revoked' },
  ];

  return (
    <div className="space-y-6">
      <div className="bg-theme-surface rounded-lg p-6">
        <div className="flex justify-between items-center mb-6">
          <div>
            <h2 className="text-xl font-semibold text-theme-primary">API Key Management</h2>
            <p className="text-theme-secondary mt-1">Manage API keys for external integrations</p>
          </div>
          <button className="btn-theme btn-theme-primary">
            Generate New Key
          </button>
        </div>

        <div className="bg-theme-warning bg-opacity-10 border border-theme-warning border-opacity-30 rounded-lg p-4 mb-6">
          <div className="flex items-start space-x-3">
            <span className="text-theme-warning text-xl">⚠️</span>
            <div>
              <h3 className="font-medium text-theme-warning">Security Notice</h3>
              <p className="text-sm text-theme-warning opacity-80 mt-1">
                API keys provide full access to your account. Keep them secure and never share them publicly.
                Rotate keys regularly and revoke unused keys immediately.
              </p>
            </div>
          </div>
        </div>

        <div className="space-y-4">
          {apiKeys.map((apiKey) => (
            <div key={apiKey.id} className="bg-theme-background rounded-lg p-4 border border-theme">
              <div className="flex items-start justify-between">
                <div className="flex-1">
                  <div className="flex items-center space-x-3 mb-2">
                    <h3 className="font-medium text-theme-primary">{apiKey.name}</h3>
                    <span className={`text-xs px-2 py-1 rounded-full ${
                      apiKey.status === 'active' 
                        ? 'bg-theme-success bg-opacity-10 text-theme-success' 
                        : 'bg-theme-error bg-opacity-10 text-theme-error'
                    }`}>
                      {apiKey.status}
                    </span>
                  </div>
                  <div className="flex items-center space-x-4 mb-2">
                    <code className="text-sm bg-theme-surface px-2 py-1 rounded font-mono text-theme-secondary">
                      {apiKey.key}
                    </code>
                    <button className="text-theme-link hover:text-theme-link-hover text-sm">
                      Copy
                    </button>
                  </div>
                  <div className="flex space-x-4 text-xs text-theme-tertiary">
                    <span>Created: {apiKey.created}</span>
                    <span>Last used: {apiKey.lastUsed}</span>
                  </div>
                </div>
                <div className="flex space-x-2">
                  <button className="text-theme-link hover:text-theme-link-hover text-sm">
                    Regenerate
                  </button>
                  <button className="text-theme-error hover:text-theme-error-hover text-sm">
                    Revoke
                  </button>
                </div>
              </div>
            </div>
          ))}
        </div>

        <div className="mt-6 grid grid-cols-1 md:grid-cols-3 gap-4">
          <div className="bg-theme-background rounded-lg p-4 border border-theme">
            <h3 className="text-2xl font-bold text-theme-primary">1,234</h3>
            <p className="text-sm text-theme-secondary">API Calls Today</p>
          </div>
          <div className="bg-theme-background rounded-lg p-4 border border-theme">
            <h3 className="text-2xl font-bold text-theme-primary">99.9%</h3>
            <p className="text-sm text-theme-secondary">API Uptime</p>
          </div>
          <div className="bg-theme-background rounded-lg p-4 border border-theme">
            <h3 className="text-2xl font-bold text-theme-primary">45ms</h3>
            <p className="text-sm text-theme-secondary">Avg Response Time</p>
          </div>
        </div>
      </div>
    </div>
  );
};

export const SystemManagementPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const isAdmin = hasAdminAccess(user);

  // Redirect non-admins to dashboard
  if (!isAdmin) {
    return <Navigate to="/dashboard" replace />;
  }

  const breadcrumbItems = [
    { label: 'Dashboard', path: '/dashboard', icon: '🏠' },
    { label: 'System Management', icon: '⚙️' }
  ];

  return (
    <div className="space-y-6">
      <div>
        <Breadcrumb items={breadcrumbItems} className="mb-4" />
        <h1 className="text-2xl font-bold text-theme-primary">System Management</h1>
        <p className="text-theme-secondary mt-1">
          Configure system services, integrations, and administrative settings.
        </p>
      </div>

      <div>
        <div className="hidden sm:block">
          <TabNavigation tabs={tabs} basePath="/dashboard/system" />
        </div>
        <MobileTabNavigation tabs={tabs} basePath="/dashboard/system" />
      </div>

      <div>
        <Routes>
          <Route path="/" element={<Navigate to="/dashboard/system/services" replace />} />
          <Route path="/services" element={<ServicesPage />} />
          <Route path="/gateways" element={<PaymentGatewaysPage />} />
          <Route path="/admin" element={<AdminSettingsPage />} />
          <Route path="/audit" element={<AuditLogsPage />} />
          <Route path="/webhooks" element={<WebhooksPage />} />
          <Route path="/api" element={<ApiKeysPage />} />
        </Routes>
      </div>
    </div>
  );
};

export default SystemManagementPage;
import React, { useState, useEffect, useCallback } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../../store';
import { adminSettingsApi, AdminOverviewData, SystemMetrics } from '../../services/adminSettingsApi';

export const AdminSettingsOverviewPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const [data, setData] = useState<AdminOverviewData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const loadOverviewData = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const overviewData = await adminSettingsApi.getOverview();
      setData(overviewData);
    } catch (error) {
      console.error('Failed to load admin overview:', error);
      setError('Failed to load admin overview data');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadOverviewData();
  }, [loadOverviewData]);


  const getStatusBadge = (status: string, text?: string) => {
    const colors = adminSettingsApi.getStatusColor(status);
    const colorClasses = {
      green: 'bg-theme-success text-theme-success border-green-200',
      yellow: 'bg-theme-warning text-theme-warning border-yellow-200',
      red: 'bg-theme-error text-theme-error border-red-200',
      blue: 'bg-theme-info text-theme-info border-blue-200',
      gray: 'bg-theme-background-tertiary text-theme-secondary border-theme'
    };

    const colorClass = colors === 'green' ? colorClasses.green :
                      colors === 'yellow' ? colorClasses.yellow :
                      colors === 'red' ? colorClasses.red :
                      colors === 'blue' ? colorClasses.blue :
                      colorClasses.gray;
    
    return (
      <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium border ${colorClass}`}>
        {text || status}
      </span>
    );
  };

  const getLogLevelBadge = (level: string) => {
    const colors = adminSettingsApi.getLogLevelColor(level);
    const colorClasses = {
      green: 'bg-theme-success text-theme-success',
      yellow: 'bg-theme-warning text-theme-warning',
      red: 'bg-theme-error text-theme-error',
      blue: 'bg-theme-info text-theme-info',
      gray: 'bg-theme-background-tertiary text-theme-secondary'
    };

    const colorClass = colors === 'green' ? colorClasses.green :
                      colors === 'yellow' ? colorClasses.yellow :
                      colors === 'red' ? colorClasses.red :
                      colors === 'blue' ? colorClasses.blue :
                      colorClasses.gray;
    
    return (
      <span className={`inline-flex items-center px-2 py-1 rounded text-xs font-medium ${colorClass}`}>
        {level.toUpperCase()}
      </span>
    );
  };

  const renderMetricsCard = (title: string, value: string | number, subtitle: string, status?: string) => (
    <div className="card-theme overflow-hidden">
      <div className="p-5">
        <div className="flex items-center">
          <div className="flex-1">
            <dt className="text-sm font-medium text-theme-tertiary truncate">{title}</dt>
            <dd className="text-2xl font-bold text-theme-primary">{value}</dd>
            <div className="flex items-center mt-1">
              <p className="text-xs text-theme-secondary">{subtitle}</p>
              {status && (
                <div className="ml-2">
                  {getStatusBadge(status)}
                </div>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  );

  if (loading && !data) {
    return (
      <div className="space-y-6">
        <div className="flex justify-between items-center">
          <div>
            <h1 className="text-2xl font-bold text-theme-primary">Admin Settings Overview</h1>
            <p className="text-theme-secondary">Comprehensive summary of active administrative settings and system configuration</p>
          </div>
        </div>
        <div className="flex justify-center items-center h-64">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-theme-link"></div>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="space-y-6">
        <div className="flex justify-between items-center">
          <div>
            <h1 className="text-2xl font-bold text-theme-primary">Admin Settings Overview</h1>
            <p className="text-theme-secondary">Comprehensive summary of active administrative settings and system configuration</p>
          </div>
        </div>
        <div className="alert-theme alert-theme-error">
          <div className="flex">
            <div className="ml-3">
              <h3 className="text-sm font-medium text-theme-error">Error Loading Data</h3>
              <p className="text-sm text-theme-error mt-1">{error}</p>
              <button
                onClick={loadOverviewData}
                className="mt-3 text-sm font-medium text-theme-error hover:text-theme-error underline"
              >
                Try Again
              </button>
            </div>
          </div>
        </div>
      </div>
    );
  }

  if (!data) {
    return null;
  }

  const { metrics, recent_users, recent_accounts, recent_logs, payment_gateways, settings_summary } = data;

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex justify-between items-center">
        <div>
          <h1 className="text-2xl font-bold text-theme-primary">Admin Settings Overview</h1>
          <div className="flex items-center gap-4 mt-1">
            <p className="text-theme-secondary">System administration and monitoring dashboard</p>
          </div>
        </div>
      </div>

      {/* System Health Alert */}
      {metrics.system_health !== 'healthy' && (
        <div className={`border rounded-md p-4 ${
          metrics.system_health === 'error' 
            ? 'alert-theme alert-theme-error' 
            : 'alert-theme alert-theme-warning'
        }`}>
          <div className="flex items-center">
            <div className={`flex-shrink-0 w-5 h-5 ${
              metrics.system_health === 'error' ? 'text-theme-error' : 'text-theme-warning'
            }`}>
              ⚠️
            </div>
            <div className="ml-3">
              <h3 className={`text-sm font-medium ${
                metrics.system_health === 'error' ? 'text-theme-error' : 'text-theme-warning'
              }`}>
                System Health Alert
              </h3>
              <p className={`text-sm mt-1 ${
                metrics.system_health === 'error' ? 'text-theme-error' : 'text-theme-warning'
              }`}>
                System is experiencing {metrics.system_health === 'error' ? 'errors' : 'warnings'}. 
                Please check system logs for details.
              </p>
            </div>
          </div>
        </div>
      )}

      {/* Key Metrics Grid */}
      <div>
        <h2 className="text-lg font-medium text-theme-primary mb-4">System Metrics</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
          {renderMetricsCard(
            'System Health',
            metrics.system_health === 'healthy' ? '✅ Healthy' : 
            metrics.system_health === 'warning' ? '⚠️ Warning' : '❌ Error',
            `Uptime: ${adminSettingsApi.formatUptime(metrics.uptime)}`,
            metrics.system_health
          )}
          {renderMetricsCard(
            'Total Users',
            adminSettingsApi.formatNumber(metrics.total_users),
            'Across all accounts'
          )}
          {renderMetricsCard(
            'Active Accounts',
            `${adminSettingsApi.formatNumber(metrics.active_accounts)} / ${adminSettingsApi.formatNumber(metrics.total_accounts)}`,
            `${metrics.suspended_accounts} suspended, ${metrics.cancelled_accounts} cancelled`
          )}
          {renderMetricsCard(
            'Revenue (Monthly)',
            adminSettingsApi.formatCurrency(metrics.monthly_revenue),
            `Total: ${adminSettingsApi.formatCurrency(metrics.total_revenue)}`
          )}
          {renderMetricsCard(
            'Active Subscriptions',
            `${adminSettingsApi.formatNumber(metrics.active_subscriptions)} / ${adminSettingsApi.formatNumber(metrics.total_subscriptions)}`,
            `${metrics.trial_subscriptions} on trial`
          )}
          {renderMetricsCard(
            'Failed Payments',
            adminSettingsApi.formatNumber(metrics.failed_payments),
            'Requires attention'
          )}
          {renderMetricsCard(
            'Webhook Events',
            adminSettingsApi.formatNumber(metrics.webhook_events_today),
            'Today'
          )}
        </div>
      </div>

      {/* Payment Gateway Status */}
      <div>
        <h2 className="text-lg font-medium text-theme-primary mb-4">Payment Gateway Status</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div className="card-theme p-6">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-medium text-theme-primary">Stripe</h3>
              {getStatusBadge(
                payment_gateways.stripe.connected ? 'connected' : 'error',
                payment_gateways.stripe.connected ? 'Connected' : 'Disconnected'
              )}
            </div>
            <div className="space-y-2">
              <p className="text-sm text-theme-secondary">
                Environment: <span className="font-medium">{payment_gateways.stripe.environment}</span>
              </p>
              <p className="text-sm text-theme-secondary">
                Webhook Status: {getStatusBadge(payment_gateways.stripe.webhook_status)}
              </p>
              {payment_gateways.stripe.last_webhook && (
                <p className="text-sm text-theme-secondary">
                  Last Webhook: {adminSettingsApi.formatRelativeTime(payment_gateways.stripe.last_webhook)}
                </p>
              )}
            </div>
          </div>
          
          <div className="card-theme p-6">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-medium text-theme-primary">PayPal</h3>
              {getStatusBadge(
                payment_gateways.paypal.connected ? 'connected' : 'error',
                payment_gateways.paypal.connected ? 'Connected' : 'Disconnected'
              )}
            </div>
            <div className="space-y-2">
              <p className="text-sm text-theme-secondary">
                Environment: <span className="font-medium">{payment_gateways.paypal.environment}</span>
              </p>
              <p className="text-sm text-theme-secondary">
                Webhook Status: {getStatusBadge(payment_gateways.paypal.webhook_status)}
              </p>
              {payment_gateways.paypal.last_webhook && (
                <p className="text-sm text-theme-secondary">
                  Last Webhook: {adminSettingsApi.formatRelativeTime(payment_gateways.paypal.last_webhook)}
                </p>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* Recent Activity Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Recent Users */}
        <div className="card-theme">
          <div className="px-6 py-4 border-b border-theme-light">
            <h3 className="text-lg font-medium text-theme-primary">Recent Users</h3>
          </div>
          <div className="divide-y divide-theme-light max-h-80 overflow-y-auto">
            {recent_users.length === 0 ? (
              <div className="px-6 py-4 text-center text-theme-secondary">No recent users</div>
            ) : (
              recent_users.map((user) => (
                <div key={user.id} className="px-6 py-4">
                  <div className="flex items-center space-x-3">
                    <div className="h-8 w-8 rounded-full bg-theme-info flex items-center justify-center">
                      <span className="text-theme-info font-medium text-sm">
                        {user.first_name[0]}{user.last_name[0]}
                      </span>
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium text-theme-primary truncate">
                        {user.full_name}
                      </p>
                      <p className="text-sm text-theme-secondary truncate">{user.email}</p>
                      <div className="flex items-center gap-2 mt-1">
                        <span className="text-xs text-theme-tertiary">
                          {user.account.name}
                        </span>
                        {user.roles.map(role => (
                          <span key={role.id} className="text-xs bg-theme-background-tertiary text-theme-secondary px-2 py-0.5 rounded">
                            {role.name}
                          </span>
                        ))}
                      </div>
                    </div>
                  </div>
                  <p className="text-xs text-theme-tertiary mt-2">
                    Joined {adminSettingsApi.formatRelativeTime(user.created_at)}
                  </p>
                </div>
              ))
            )}
          </div>
        </div>

        {/* Recent Accounts */}
        <div className="card-theme">
          <div className="px-6 py-4 border-b border-theme-light">
            <h3 className="text-lg font-medium text-theme-primary">Recent Accounts</h3>
          </div>
          <div className="divide-y divide-theme-light max-h-80 overflow-y-auto">
            {recent_accounts.length === 0 ? (
              <div className="px-6 py-4 text-center text-theme-secondary">No recent accounts</div>
            ) : (
              recent_accounts.map((account) => (
                <div key={account.id} className="px-6 py-4">
                  <div className="flex items-center justify-between">
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium text-theme-primary truncate">
                        {account.name}
                      </p>
                      <p className="text-sm text-theme-secondary">{account.owner.email}</p>
                      <div className="flex items-center gap-2 mt-1">
                        {getStatusBadge(account.status)}
                        {account.subscription && (
                          <span className="text-xs text-theme-tertiary">
                            {account.subscription.plan.name}
                          </span>
                        )}
                      </div>
                    </div>
                  </div>
                  <p className="text-xs text-theme-tertiary mt-2">
                    Created {adminSettingsApi.formatRelativeTime(account.created_at)}
                  </p>
                </div>
              ))
            )}
          </div>
        </div>

        {/* Recent System Logs */}
        <div className="card-theme">
          <div className="px-6 py-4 border-b border-theme-light">
            <h3 className="text-lg font-medium text-theme-primary">System Logs</h3>
          </div>
          <div className="divide-y divide-theme-light max-h-80 overflow-y-auto">
            {recent_logs.length === 0 ? (
              <div className="px-6 py-4 text-center text-theme-secondary">No recent logs</div>
            ) : (
              recent_logs.map((log) => (
                <div key={log.id} className="px-6 py-4">
                  <div className="flex items-start justify-between">
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 mb-1">
                        {getLogLevelBadge(log.level)}
                        <span className="text-xs text-theme-tertiary">{log.source}</span>
                      </div>
                      <p className="text-sm text-theme-primary break-words">
                        {log.message}
                      </p>
                    </div>
                  </div>
                  <p className="text-xs text-theme-tertiary mt-2">
                    {adminSettingsApi.formatRelativeTime(log.timestamp)}
                  </p>
                </div>
              ))
            )}
          </div>
        </div>
      </div>

      {/* Quick Actions */}
      <div className="card-theme p-6">
        <h3 className="text-lg font-medium text-theme-primary mb-4">Quick Actions</h3>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <button className="btn-theme btn-theme-secondary flex items-center justify-center px-4 py-3">
            <span className="mr-2">👥</span>
            Manage Users
          </button>
          <button className="btn-theme btn-theme-secondary flex items-center justify-center px-4 py-3">
            <span className="mr-2">🏢</span>
            Manage Accounts
          </button>
          <button className="btn-theme btn-theme-secondary flex items-center justify-center px-4 py-3">
            <span className="mr-2">💳</span>
            Payment Gateways
          </button>
          <button className="btn-theme btn-theme-secondary flex items-center justify-center px-4 py-3">
            <span className="mr-2">📊</span>
            System Logs
          </button>
          <button className="btn-theme btn-theme-secondary flex items-center justify-center px-4 py-3">
            <span className="mr-2">⚙️</span>
            System Settings
          </button>
          <button className="btn-theme btn-theme-secondary flex items-center justify-center px-4 py-3">
            <span className="mr-2">🔧</span>
            Maintenance Mode
          </button>
        </div>
      </div>

      {/* Active Admin Settings Summary */}
      {settings_summary && (
        <div className="space-y-6">
          {/* Critical System Status */}
          <div className="card-theme p-6">
            <h2 className="text-lg font-semibold text-theme-primary mb-6 flex items-center">
              <span className="mr-2">🚨</span>
              Critical System Settings
            </h2>
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
              <div className={`p-4 rounded-lg border ${settings_summary.maintenance_mode ? 'bg-theme-error border-theme-error' : 'bg-theme-success border-theme-success'}`}>
                <div className="flex items-center justify-between mb-2">
                  <span className="text-sm font-medium text-theme-primary">Maintenance Mode</span>
                  <div className={`w-2 h-2 rounded-full ${settings_summary.maintenance_mode ? 'bg-theme-error' : 'bg-theme-success'}`} />
                </div>
                <p className={`text-lg font-bold ${settings_summary.maintenance_mode ? 'text-theme-error' : 'text-theme-success'}`}>
                  {settings_summary.maintenance_mode ? 'ACTIVE' : 'Normal Operation'}
                </p>
                <p className="text-xs text-theme-secondary mt-1">
                  {settings_summary.maintenance_mode ? 'System unavailable to users' : 'System fully operational'}
                </p>
              </div>
              
              <div className={`p-4 rounded-lg border ${!settings_summary.registration_enabled ? 'bg-theme-warning border-theme-warning' : 'bg-theme-success border-theme-success'}`}>
                <div className="flex items-center justify-between mb-2">
                  <span className="text-sm font-medium text-theme-primary">User Registration</span>
                  <div className={`w-2 h-2 rounded-full ${settings_summary.registration_enabled ? 'bg-theme-success' : 'bg-theme-warning'}`} />
                </div>
                <p className={`text-lg font-bold ${settings_summary.registration_enabled ? 'text-green-700 dark:text-green-400' : 'text-orange-700 dark:text-orange-400'}`}>
                  {settings_summary.registration_enabled ? 'Open' : 'Restricted'}
                </p>
                <p className="text-xs text-theme-secondary mt-1">
                  {settings_summary.registration_enabled ? 'New users can register' : 'Registration disabled'}
                </p>
              </div>
              
              <div className={`p-4 rounded-lg border ${!settings_summary.require_email_verification ? 'bg-theme-warning border-theme-warning' : 'bg-theme-success border-theme-success'}`}>
                <div className="flex items-center justify-between mb-2">
                  <span className="text-sm font-medium text-theme-primary">Email Verification</span>
                  <div className={`w-2 h-2 rounded-full ${settings_summary.require_email_verification ? 'bg-theme-success' : 'bg-theme-warning'}`} />
                </div>
                <p className={`text-lg font-bold ${settings_summary.require_email_verification ? 'text-green-700 dark:text-green-400' : 'text-yellow-700 dark:text-yellow-400'}`}>
                  {settings_summary.require_email_verification ? 'Required' : 'Optional'}
                </p>
                <p className="text-xs text-theme-secondary mt-1">
                  {settings_summary.require_email_verification ? 'Users must verify email' : 'Email verification optional'}
                </p>
              </div>
              
              <div className={`p-4 rounded-lg border ${!settings_summary.allow_account_deletion ? 'bg-theme-info border-theme-info' : 'bg-theme-warning border-theme-warning'}`}>
                <div className="flex items-center justify-between mb-2">
                  <span className="text-sm font-medium text-theme-primary">Account Deletion</span>
                  <div className={`w-2 h-2 rounded-full ${settings_summary.allow_account_deletion ? 'bg-theme-warning' : 'bg-theme-info'}`} />
                </div>
                <p className={`text-lg font-bold ${settings_summary.allow_account_deletion ? 'text-orange-700 dark:text-orange-400' : 'text-blue-700 dark:text-blue-400'}`}>
                  {settings_summary.allow_account_deletion ? 'Allowed' : 'Protected'}
                </p>
                <p className="text-xs text-theme-secondary mt-1">
                  {settings_summary.allow_account_deletion ? 'Users can delete accounts' : 'Account deletion restricted'}
                </p>
              </div>
            </div>
          </div>
          
          {/* Active Configuration Summary */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {/* System & Operations */}
            <div className="card-theme p-6">
              <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center">
                <span className="mr-2">⚙️</span>
                System & Operations
              </h3>
              <div className="space-y-4">
                <div className="border-b border-theme-light pb-3">
                  <div className="flex justify-between items-start">
                    <div>
                      <p className="font-medium text-theme-primary">System Identity</p>
                      <p className="text-sm text-theme-secondary">{settings_summary.system_name || 'Powernode Platform'}</p>
                    </div>
                    <span className="bg-blue-100 dark:bg-blue-900/30 text-blue-800 dark:text-blue-400 px-2 py-1 rounded text-xs font-medium">Active</span>
                  </div>
                </div>
                
                <div className="border-b border-theme-light pb-3">
                  <div className="flex justify-between items-start">
                    <div>
                      <p className="font-medium text-theme-primary">Contact Configuration</p>
                      <p className="text-sm text-theme-secondary">System: {settings_summary.system_email || 'Not configured'}</p>
                      <p className="text-sm text-theme-secondary">Support: {settings_summary.support_email || 'Not configured'}</p>
                    </div>
                    <span className={`px-2 py-1 rounded text-xs font-medium ${
                      settings_summary.system_email && settings_summary.support_email 
                        ? 'bg-green-100 dark:bg-green-900/30 text-green-800 dark:text-green-400' 
                        : 'bg-yellow-100 dark:bg-yellow-900/30 text-yellow-800 dark:text-yellow-400'
                    }`}>
                      {settings_summary.system_email && settings_summary.support_email ? 'Complete' : 'Partial'}
                    </span>
                  </div>
                </div>
                
                <div className="border-b border-theme-light pb-3">
                  <div className="flex justify-between items-start">
                    <div>
                      <p className="font-medium text-theme-primary">Data Retention</p>
                      <p className="text-sm text-theme-secondary">Backups: {settings_summary.backup_retention_days || 30} days</p>
                      <p className="text-sm text-theme-secondary">Logs: {settings_summary.log_retention_days || 90} days</p>
                    </div>
                    <span className="bg-green-100 dark:bg-green-900/30 text-green-800 dark:text-green-400 px-2 py-1 rounded text-xs font-medium">Configured</span>
                  </div>
                </div>
              </div>
            </div>
            
            {/* Security & Access Control */}
            <div className="card-theme p-6">
              <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center">
                <span className="mr-2">🛡️</span>
                Security & Access Control
              </h3>
              <div className="space-y-4">
                <div className="border-b border-theme-light pb-3">
                  <div className="flex justify-between items-start">
                    <div>
                      <p className="font-medium text-theme-primary">Session Management</p>
                      <p className="text-sm text-theme-secondary">Timeout: {settings_summary.session_timeout_minutes || 60} minutes</p>
                      <p className="text-sm text-theme-secondary">Auto-logout when inactive</p>
                    </div>
                    <span className="bg-blue-100 dark:bg-blue-900/30 text-blue-800 dark:text-blue-400 px-2 py-1 rounded text-xs font-medium">Active</span>
                  </div>
                </div>
                
                <div className="border-b border-theme-light pb-3">
                  <div className="flex justify-between items-start">
                    <div>
                      <p className="font-medium text-theme-primary">Password Policy</p>
                      <p className="text-sm text-theme-secondary">Min Length: {settings_summary.password_min_length || 12} characters</p>
                      <p className="text-sm text-theme-secondary">Complexity requirements enforced</p>
                    </div>
                    <span className="bg-green-100 dark:bg-green-900/30 text-green-800 dark:text-green-400 px-2 py-1 rounded text-xs font-medium">Enforced</span>
                  </div>
                </div>
                
                <div className="border-b border-theme-light pb-3">
                  <div className="flex justify-between items-start">
                    <div>
                      <p className="font-medium text-theme-primary">Rate Limiting</p>
                      <p className="text-sm text-theme-secondary">API: {settings_summary.rate_limit_requests_per_minute || 60} requests/minute</p>
                      <p className="text-sm text-theme-secondary">DDoS protection active</p>
                    </div>
                    <span className="bg-green-100 dark:bg-green-900/30 text-green-800 dark:text-green-400 px-2 py-1 rounded text-xs font-medium">Protected</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
          
          {/* Business Rules & Features */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {/* Subscription & Billing */}
            <div className="card-theme p-6">
              <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center">
                <span className="mr-2">💳</span>
                Subscription & Billing
              </h3>
              <div className="space-y-4">
                <div className="border-b border-theme-light pb-3">
                  <div className="flex justify-between items-start">
                    <div>
                      <p className="font-medium text-theme-primary">Trial Configuration</p>
                      <p className="text-sm text-theme-secondary">Period: {settings_summary.trial_period_days || 14} days</p>
                      <p className="text-sm text-theme-secondary">Max Accounts: {settings_summary.max_trial_accounts || 'Unlimited'}</p>
                    </div>
                    <span className="bg-blue-100 dark:bg-blue-900/30 text-blue-800 dark:text-blue-400 px-2 py-1 rounded text-xs font-medium">Active</span>
                  </div>
                </div>
                
                <div className="border-b border-theme-light pb-3">
                  <div className="flex justify-between items-start">
                    <div>
                      <p className="font-medium text-theme-primary">Payment Processing</p>
                      <p className="text-sm text-theme-secondary">Retry Attempts: {settings_summary.payment_retry_attempts || 3}</p>
                      <p className="text-sm text-theme-secondary">Automated dunning process</p>
                    </div>
                    <span className="bg-green-100 dark:bg-green-900/30 text-green-800 dark:text-green-400 px-2 py-1 rounded text-xs font-medium">Automated</span>
                  </div>
                </div>
                
                <div className="border-b border-theme-light pb-3">
                  <div className="flex justify-between items-start">
                    <div>
                      <p className="font-medium text-theme-primary">Webhook Configuration</p>
                      <p className="text-sm text-theme-secondary">Timeout: {settings_summary.webhook_timeout_seconds || 30} seconds</p>
                      <p className="text-sm text-theme-secondary">Real-time payment events</p>
                    </div>
                    <span className="bg-green-100 dark:bg-green-900/30 text-green-800 dark:text-green-400 px-2 py-1 rounded text-xs font-medium">Configured</span>
                  </div>
                </div>
              </div>
            </div>
            
            {/* Feature Flags & SMTP */}
            <div className="card-theme p-6">
              <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center">
                <span className="mr-2">🚀</span>
                Features & Communication
              </h3>
              <div className="space-y-4">
                {settings_summary.feature_flags && Object.keys(settings_summary.feature_flags).length > 0 && (
                  <div className="border-b border-theme-light pb-3">
                    <div className="flex justify-between items-start">
                      <div>
                        <p className="font-medium text-theme-primary">Feature Flags</p>
                        <div className="flex flex-wrap gap-1 mt-1">
                          {Object.entries(settings_summary.feature_flags).map(([flag, enabled]) => (
                            <span key={flag} className={`px-2 py-1 rounded text-xs font-medium ${
                              enabled 
                                ? 'bg-green-100 dark:bg-green-900/30 text-green-800 dark:text-green-400' 
                                : 'bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-400'
                            }`}>
                              {flag}: {enabled ? 'ON' : 'OFF'}
                            </span>
                          ))}
                        </div>
                      </div>
                    </div>
                  </div>
                )}
                
                <div className="border-b border-theme-light pb-3">
                  <div className="flex justify-between items-start">
                    <div>
                      <p className="font-medium text-theme-primary">Email Configuration</p>
                      <p className="text-sm text-theme-secondary">SMTP Host: {settings_summary.smtp_settings?.host || 'Not configured'}</p>
                      <p className="text-sm text-theme-secondary">Port: {settings_summary.smtp_settings?.port || 'N/A'} ({settings_summary.smtp_settings?.use_tls ? 'TLS' : 'Plain'})</p>
                      <p className="text-sm text-theme-secondary">From: {settings_summary.smtp_settings?.from_address || 'Not set'}</p>
                    </div>
                    <span className={`px-2 py-1 rounded text-xs font-medium ${
                      settings_summary.smtp_settings?.host 
                        ? 'bg-green-100 dark:bg-green-900/30 text-green-800 dark:text-green-400' 
                        : 'bg-red-100 dark:bg-red-900/30 text-red-800 dark:text-red-400'
                    }`}>
                      {settings_summary.smtp_settings?.host ? 'Configured' : 'Missing'}
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </div>
          
          {/* Settings Summary Footer */}
          <div className="card-theme p-4">
            <div className="flex items-center justify-between">
              <div className="flex items-center space-x-4 text-sm text-theme-secondary">
                <span>Settings last updated: {settings_summary.updated_at ? adminSettingsApi.formatRelativeTime(settings_summary.updated_at) : 'Never'}</span>
                <span>•</span>
                <span>Configuration created: {settings_summary.created_at ? adminSettingsApi.formatRelativeTime(settings_summary.created_at) : 'Unknown'}</span>
              </div>
              <div className="flex items-center space-x-2">
                <div className="w-2 h-2 bg-green-500 rounded-full"></div>
                <span className="text-sm text-theme-secondary">Settings Active</span>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
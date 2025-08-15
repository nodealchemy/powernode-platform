import React, { useState, useEffect, useCallback } from 'react';
import { Link } from 'react-router-dom';
import { adminSettingsApi, AdminOverviewData } from '../../services/adminSettingsApi';

interface QuickActionProps {
  icon: string;
  title: string;
  description: string;
  path?: string;
  onClick?: () => void;
  status?: 'normal' | 'warning' | 'error' | 'success';
  badge?: string;
}

const QuickAction: React.FC<QuickActionProps> = ({ 
  icon, 
  title, 
  description, 
  path, 
  onClick, 
  status = 'normal',
  badge 
}) => {
  const statusColors = {
    normal: 'hover:bg-theme-surface-hover border-theme bg-theme-surface',
    warning: 'hover:bg-theme-warning-background border-theme-warning-border bg-theme-warning-background',
    error: 'hover:bg-theme-error-background border-theme-error-border bg-theme-error-background',
    success: 'hover:bg-theme-success-background border-theme-success-border bg-theme-success-background'
  };

  const content = (
    // eslint-disable-next-line security/detect-object-injection
    <div className={`group p-6 rounded-xl border transition-all duration-200 cursor-pointer relative overflow-hidden ${statusColors[status]}`}>
      {badge && (
        <div className="absolute top-3 right-3">
          <span className="px-2 py-1 bg-theme-interactive-primary text-white text-xs font-medium rounded-full">
            {badge}
          </span>
        </div>
      )}
      <div className="flex items-start gap-4">
        <div className="w-12 h-12 bg-theme-background rounded-lg flex items-center justify-center flex-shrink-0 group-hover:scale-105 transition-transform">
          <span className="text-xl">{icon}</span>
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-theme-primary mb-1 group-hover:text-theme-link transition-colors">
            {title}
          </h3>
          <p className="text-sm text-theme-secondary line-clamp-2">
            {description}
          </p>
        </div>
        <div className="text-theme-tertiary group-hover:text-theme-primary transition-colors">
          →
        </div>
      </div>
    </div>
  );

  if (path) {
    return <Link to={path}>{content}</Link>;
  }

  return <div onClick={onClick}>{content}</div>;
};

interface SystemStatusCardProps {
  title: string;
  status: 'healthy' | 'warning' | 'error' | 'maintenance';
  value: string;
  description: string;
  action?: {
    label: string;
    onClick: () => void;
  };
}

const SystemStatusCard: React.FC<SystemStatusCardProps> = ({ 
  title, 
  status, 
  value, 
  description, 
  action 
}) => {
  const statusConfig = {
    healthy: {
      color: 'text-theme-success',
      bgColor: 'bg-theme-success-background',
      borderColor: 'border-theme-success-border',
      icon: '✅'
    },
    warning: {
      color: 'text-theme-warning',
      bgColor: 'bg-theme-warning-background',
      borderColor: 'border-theme-warning-border',
      icon: '⚠️'
    },
    error: {
      color: 'text-theme-error',
      bgColor: 'bg-theme-error-background',
      borderColor: 'border-theme-error-border',
      icon: '❌'
    },
    maintenance: {
      color: 'text-theme-warning',
      bgColor: 'bg-theme-warning-background',
      borderColor: 'border-theme-warning-border',
      icon: '🔧'
    }
  };

  // eslint-disable-next-line security/detect-object-injection
  const config = statusConfig[status];

  return (
    <div className="group p-6 rounded-xl border border-theme bg-theme-surface hover:bg-theme-surface-hover transition-all duration-200 cursor-default">
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-3">
          <div className="w-12 h-12 bg-theme-background rounded-lg flex items-center justify-center flex-shrink-0">
            <span className="text-xl">{config.icon}</span>
          </div>
          <h3 className="font-semibold text-theme-primary">{title}</h3>
        </div>
        <div className={`w-3 h-3 rounded-full ${
          status === 'healthy' ? 'bg-theme-success' :
          status === 'warning' ? 'bg-theme-warning' :
          status === 'error' ? 'bg-theme-error' :
          'bg-theme-warning'
        } shadow-sm`} />
      </div>
      <div className={`text-2xl font-bold ${config.color} mb-2`}>
        {value}
      </div>
      <p className="text-sm text-theme-secondary mb-4">{description}</p>
      {action && (
        <button
          onClick={action.onClick}
          className={`text-sm font-medium ${config.color} hover:underline transition-colors duration-200`}
        >
          {action.label}
        </button>
      )}
    </div>
  );
};

interface MetricCardProps {
  title: string;
  value: string | number;
  change?: {
    value: string;
    type: 'increase' | 'decrease' | 'neutral';
  };
  icon: string;
  color: 'blue' | 'green' | 'yellow' | 'red' | 'purple';
}

const MetricCard: React.FC<MetricCardProps> = ({ title, value, change, icon, color }) => {
  const colorConfig = {
    blue: { bg: 'bg-theme-info-background', text: 'text-theme-info', icon: 'bg-theme-info' },
    green: { bg: 'bg-theme-success-background', text: 'text-theme-success', icon: 'bg-theme-success' },
    yellow: { bg: 'bg-theme-warning-background', text: 'text-theme-warning', icon: 'bg-theme-warning' },
    red: { bg: 'bg-theme-error-background', text: 'text-theme-error', icon: 'bg-theme-error' },
    purple: { bg: 'bg-theme-info-background', text: 'text-theme-info', icon: 'bg-theme-interactive-primary' }
  };

  // eslint-disable-next-line security/detect-object-injection
  const config = colorConfig[color];

  return (
    <div className="bg-theme-surface rounded-xl p-6 border border-theme">
      <div className="flex items-center justify-between mb-4">
        <div className={`w-12 h-12 ${config.icon} rounded-lg flex items-center justify-center`}>
          <span className="text-white text-xl">{icon}</span>
        </div>
        {change && (
          <div className={`px-2 py-1 rounded text-xs font-medium ${
            change.type === 'increase' ? 'bg-theme-success-background text-theme-success' :
            change.type === 'decrease' ? 'bg-theme-error-background text-theme-error' :
            'bg-theme-surface text-theme-secondary'
          }`}>
            {change.type === 'increase' ? '↗' : change.type === 'decrease' ? '↘' : '→'} {change.value}
          </div>
        )}
      </div>
      <div className="text-2xl font-bold text-theme-primary mb-1">
        {value}
      </div>
      <p className="text-sm text-theme-secondary">{title}</p>
    </div>
  );
};

export const AdminSettingsOverviewPage: React.FC = () => {
  const [data, setData] = useState<AdminOverviewData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  const loadOverviewData = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const overviewData = await adminSettingsApi.getOverview();
      setData(overviewData);
    } catch (error: any) {
      console.error('Failed to load admin overview:', error);
      setError(error.message || 'Failed to load admin overview data');
    } finally {
      setLoading(false);
    }
  }, []);

  const handleRefresh = async () => {
    setRefreshing(true);
    await loadOverviewData();
    setRefreshing(false);
  };

  useEffect(() => {
    loadOverviewData();
  }, [loadOverviewData]);

  if (loading && !data) {
    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-3xl font-bold text-theme-primary">Admin Overview</h1>
            <p className="text-theme-secondary mt-2">System administration dashboard and monitoring</p>
          </div>
        </div>
        <div className="flex items-center justify-center h-64">
          <div className="text-center">
            <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-theme-interactive-primary mx-auto mb-4"></div>
            <p className="text-theme-secondary">Loading system overview...</p>
          </div>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-3xl font-bold text-theme-primary">Admin Overview</h1>
            <p className="text-theme-secondary mt-2">System administration dashboard and monitoring</p>
          </div>
        </div>
        <div className="bg-theme-error-background border border-theme-error-border rounded-xl p-6">
          <div className="flex items-center gap-3 mb-4">
            <span className="text-theme-error text-2xl">⚠️</span>
            <div>
              <h3 className="text-lg font-semibold text-theme-error">Unable to Load System Data</h3>
              <p className="text-theme-error">{error}</p>
            </div>
          </div>
          <button
            onClick={loadOverviewData}
            className="bg-theme-error text-white px-4 py-2 rounded-lg hover:bg-theme-error transition-colors"
          >
            Retry Loading
          </button>
        </div>
      </div>
    );
  }

  if (!data) return null;

  const { metrics, recent_users, recent_accounts, recent_logs, payment_gateways, settings_summary } = data;

  // Determine system status
  const getSystemStatus = () => {
    if (settings_summary?.maintenance_mode) return { status: 'maintenance' as const, message: 'System in maintenance mode' };
    if (metrics.system_health === 'error') return { status: 'error' as const, message: 'System experiencing errors' };
    if (metrics.system_health === 'warning') return { status: 'warning' as const, message: 'System has warnings' };
    return { status: 'healthy' as const, message: 'All systems operational' };
  };

  const systemStatus = getSystemStatus();

  return (
    <div className="space-y-8">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold text-theme-primary">Admin Overview</h1>
          <div className="flex items-center gap-4 mt-2">
            <p className="text-theme-secondary">System administration dashboard and monitoring</p>
            <div className="flex items-center gap-2">
              <div className={`w-2 h-2 rounded-full ${
                systemStatus.status === 'healthy' ? 'bg-theme-success' :
                systemStatus.status === 'warning' ? 'bg-theme-warning' :
                systemStatus.status === 'error' ? 'bg-theme-error' :
                'bg-theme-warning'
              }`} />
              <span className={`text-sm font-medium ${
                systemStatus.status === 'healthy' ? 'text-theme-success' :
                systemStatus.status === 'warning' ? 'text-theme-warning' :
                systemStatus.status === 'error' ? 'text-theme-error' :
                'text-theme-warning'
              }`}>
                {systemStatus.message}
              </span>
            </div>
          </div>
        </div>
        <div className="flex items-center gap-3">
          <button
            onClick={handleRefresh}
            disabled={refreshing}
            className="bg-theme-background border border-theme text-theme-primary px-4 py-2 rounded-lg hover:bg-theme-surface transition-colors flex items-center gap-2"
          >
            <span className={refreshing ? 'animate-spin' : ''}>🔄</span>
            <span>{refreshing ? 'Refreshing...' : 'Refresh'}</span>
          </button>
        </div>
      </div>

      {/* System Status Alert */}
      {systemStatus.status !== 'healthy' && (
        <div className={`p-4 rounded-xl border ${
          systemStatus.status === 'maintenance' ? 'bg-theme-warning-background border-theme-warning-border' :
          systemStatus.status === 'warning' ? 'bg-theme-warning-background border-theme-warning-border' :
          'bg-theme-error-background border-theme-error-border'
        }`}>
          <div className="flex items-center gap-3">
            <span className="text-2xl">
              {systemStatus.status === 'maintenance' ? '🔧' :
               systemStatus.status === 'warning' ? '⚠️' : '❌'}
            </span>
            <div>
              <h3 className={`font-semibold ${
                systemStatus.status === 'maintenance' ? 'text-theme-warning' :
                systemStatus.status === 'warning' ? 'text-theme-warning' :
                'text-theme-error'
              }`}>
                System Status Alert
              </h3>
              <p className={`text-sm ${
                systemStatus.status === 'maintenance' ? 'text-theme-warning' :
                systemStatus.status === 'warning' ? 'text-theme-warning' :
                'text-theme-error'
              }`}>
                {systemStatus.message}. Please review system settings and logs for details.
              </p>
            </div>
          </div>
        </div>
      )}

      {/* System Status Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <SystemStatusCard
          title="System Health"
          status={metrics.system_health as any}
          value={metrics.system_health === 'healthy' ? 'Operational' : 
                 metrics.system_health === 'warning' ? 'Warnings' : 'Critical'}
          description={`Uptime: ${adminSettingsApi.formatUptime(metrics.uptime)}`}
        />

        <SystemStatusCard
          title="Maintenance Mode"
          status={settings_summary?.maintenance_mode ? 'maintenance' : 'healthy'}
          value={settings_summary?.maintenance_mode ? 'ACTIVE' : 'Disabled'}
          description={settings_summary?.maintenance_mode ? 'Users cannot access system' : 'System fully accessible'}
          action={settings_summary?.maintenance_mode ? {
            label: 'Disable Maintenance',
            onClick: () => console.log('Toggle maintenance mode')
          } : undefined}
        />

        <SystemStatusCard
          title="Registration"
          status={settings_summary?.registration_enabled ? 'healthy' : 'warning'}
          value={settings_summary?.registration_enabled ? 'Open' : 'Closed'}
          description={settings_summary?.registration_enabled ? 'New users can register' : 'Registration disabled'}
        />

        <SystemStatusCard
          title="Security Level"
          status="healthy"
          value="High"
          description={`Email verification ${settings_summary?.require_email_verification ? 'required' : 'optional'}`}
        />
      </div>

      {/* Key Metrics */}
      <div>
        <h2 className="text-xl font-semibold text-theme-primary mb-6 flex items-center gap-2">
          <span>📊</span>
          <span>Key Metrics</span>
        </h2>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
          <MetricCard
            title="Total Users"
            value={adminSettingsApi.formatNumber(metrics.total_users)}
            icon="👥"
            color="blue"
            change={{ value: "12%", type: "increase" }}
          />
          <MetricCard
            title="Active Accounts"
            value={`${metrics.active_accounts}/${metrics.total_accounts}`}
            icon="🏢"
            color="green"
            change={{ value: "5%", type: "increase" }}
          />
          <MetricCard
            title="Monthly Revenue"
            value={adminSettingsApi.formatCurrency(metrics.monthly_revenue)}
            icon="💰"
            color="purple"
            change={{ value: "8%", type: "increase" }}
          />
          <MetricCard
            title="Active Subscriptions"
            value={`${metrics.active_subscriptions}/${metrics.total_subscriptions}`}
            icon="📋"
            color="green"
            change={{ value: "3%", type: "increase" }}
          />
        </div>
      </div>

      {/* Quick Actions */}
      <div>
        <h2 className="text-xl font-semibold text-theme-primary mb-6 flex items-center gap-2">
          <span>⚡</span>
          <span>Quick Actions</span>
        </h2>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          <QuickAction
            icon="⚙️"
            title="System Settings"
            description="Configure platform settings, security, and business rules"
            path="/dashboard/system/admin"
          />
          <QuickAction
            icon="👥"
            title="User Management"
            description="View and manage user accounts, roles, and permissions"
            path="/dashboard/admin/users"
          />
          <QuickAction
            icon="💳"
            title="Payment Gateways"
            description="Configure Stripe and PayPal integrations"
            path="/dashboard/system/gateways"
          />
          <QuickAction
            icon="🔗"
            title="Webhooks"
            description="Manage payment gateway webhooks and endpoints"
            path="/dashboard/system/webhooks"
          />
          <QuickAction
            icon="📝"
            title="Audit Logs"
            description="Review system activity and security events"
            path="/dashboard/system/audit"
            badge={recent_logs.length.toString()}
          />
          <QuickAction
            icon="⚡"
            title="Services"
            description="Manage background job services and authentication"
            path="/dashboard/system/services"
          />
        </div>
      </div>

      {/* Configuration Overview */}
      <div>
        <h2 className="text-xl font-semibold text-theme-primary mb-6 flex items-center gap-2">
          <span>🛠️</span>
          <span>Configuration Overview</span>
        </h2>
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Security Configuration */}
          <div className="bg-theme-surface rounded-xl p-6 border border-theme">
            <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
              <span>🔒</span>
              <span>Security</span>
            </h3>
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <span className="text-sm text-theme-secondary">Password Min Length</span>
                <span className="text-sm font-medium text-theme-primary">{settings_summary?.password_min_length || 12} chars</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-sm text-theme-secondary">Session Timeout</span>
                <span className="text-sm font-medium text-theme-primary">{settings_summary?.session_timeout_minutes || 60} min</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-sm text-theme-secondary">Email Verification</span>
                <span className={`text-xs px-2 py-1 rounded font-medium ${
                  settings_summary?.require_email_verification 
                    ? 'bg-theme-success-background text-theme-success' 
                    : 'bg-theme-warning-background text-theme-warning'
                }`}>
                  {settings_summary?.require_email_verification ? 'Required' : 'Optional'}
                </span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-sm text-theme-secondary">Rate Limiting</span>
                <span className={`text-xs px-2 py-1 rounded font-medium ${
                  settings_summary?.rate_limiting?.enabled !== false
                    ? 'bg-theme-success-background text-theme-success' 
                    : 'bg-theme-error-background text-theme-error'
                }`}>
                  {settings_summary?.rate_limiting?.enabled !== false ? 'Active' : 'Disabled'}
                </span>
              </div>
            </div>
          </div>

          {/* Business Configuration */}
          <div className="bg-theme-surface rounded-xl p-6 border border-theme">
            <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
              <span>💼</span>
              <span>Business</span>
            </h3>
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <span className="text-sm text-theme-secondary">Trial Period</span>
                <span className="text-sm font-medium text-theme-primary">{settings_summary?.trial_period_days || 14} days</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-sm text-theme-secondary">Payment Retries</span>
                <span className="text-sm font-medium text-theme-primary">{settings_summary?.payment_retry_attempts || 3} attempts</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-sm text-theme-secondary">Webhook Timeout</span>
                <span className="text-sm font-medium text-theme-primary">{settings_summary?.webhook_timeout_seconds || 30}s</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-sm text-theme-secondary">Account Deletion</span>
                <span className={`text-xs px-2 py-1 rounded font-medium ${
                  settings_summary?.allow_account_deletion 
                    ? 'bg-theme-warning-background text-theme-warning' 
                    : 'bg-theme-success-background text-theme-success'
                }`}>
                  {settings_summary?.allow_account_deletion ? 'Allowed' : 'Protected'}
                </span>
              </div>
            </div>
          </div>

          {/* Communication Configuration */}
          <div className="bg-theme-surface rounded-xl p-6 border border-theme">
            <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
              <span>📧</span>
              <span>Communication</span>
            </h3>
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <span className="text-sm text-theme-secondary">System Email</span>
                <span className="text-xs font-medium text-theme-primary truncate max-w-24" title={settings_summary?.system_email || 'Not set'}>
                  {settings_summary?.system_email ? '✓ Set' : '⚠ Not set'}
                </span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-sm text-theme-secondary">Support Email</span>
                <span className="text-xs font-medium text-theme-primary truncate max-w-24" title={settings_summary?.support_email || 'Not set'}>
                  {settings_summary?.support_email ? '✓ Set' : '⚠ Not set'}
                </span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-sm text-theme-secondary">SMTP Host</span>
                <span className={`text-xs px-2 py-1 rounded font-medium ${
                  settings_summary?.smtp_settings?.host 
                    ? 'bg-theme-success-background text-theme-success' 
                    : 'bg-theme-error-background text-theme-error'
                }`}>
                  {settings_summary?.smtp_settings?.host ? 'Configured' : 'Missing'}
                </span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-sm text-theme-secondary">System Name</span>
                <span className="text-sm font-medium text-theme-primary truncate max-w-24" title={settings_summary?.system_name || 'Powernode'}>
                  {settings_summary?.system_name || 'Powernode'}
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Payment Gateway Status */}
      <div>
        <h2 className="text-xl font-semibold text-theme-primary mb-6 flex items-center gap-2">
          <span>💳</span>
          <span>Payment Gateway Status</span>
        </h2>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div className="group bg-theme-surface rounded-xl p-6 border border-theme hover:bg-theme-surface-hover transition-all duration-200">
            <div className="flex items-center justify-between mb-4">
              <div className="flex items-center gap-3">
                <div className="w-12 h-12 bg-theme-background rounded-lg flex items-center justify-center flex-shrink-0">
                  <span className="text-xl">💳</span>
                </div>
                <h3 className="text-lg font-semibold text-theme-primary">Stripe</h3>
              </div>
              <div className="flex items-center gap-2">
                <div className={`w-3 h-3 rounded-full ${
                  payment_gateways.stripe.connected ? 'bg-theme-success' : 'bg-theme-error'
                } shadow-sm`} />
                <span className={`px-3 py-1 rounded-full text-xs font-medium ${
                  payment_gateways.stripe.connected 
                    ? 'bg-theme-success-background text-theme-success' 
                    : 'bg-theme-error-background text-theme-error'
                }`}>
                  {payment_gateways.stripe.connected ? '✓ Connected' : '✗ Disconnected'}
                </span>
              </div>
            </div>
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <span className="text-sm text-theme-secondary">Environment</span>
                <span className="text-sm font-medium text-theme-primary">{payment_gateways.stripe.environment}</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-sm text-theme-secondary">Webhook Status</span>
                <span className={`text-xs px-2 py-1 rounded font-medium ${
                  payment_gateways.stripe.webhook_status === 'healthy' 
                    ? 'bg-theme-success-background text-theme-success' 
                    : 'bg-theme-warning-background text-theme-warning'
                }`}>
                  {payment_gateways.stripe.webhook_status}
                </span>
              </div>
              {payment_gateways.stripe.last_webhook && (
                <div className="flex items-center justify-between">
                  <span className="text-sm text-theme-secondary">Last Webhook</span>
                  <span className="text-sm font-medium text-theme-primary">
                    {adminSettingsApi.formatRelativeTime(payment_gateways.stripe.last_webhook)}
                  </span>
                </div>
              )}
            </div>
          </div>

          <div className="group bg-theme-surface rounded-xl p-6 border border-theme hover:bg-theme-surface-hover transition-all duration-200">
            <div className="flex items-center justify-between mb-4">
              <div className="flex items-center gap-3">
                <div className="w-12 h-12 bg-theme-background rounded-lg flex items-center justify-center flex-shrink-0">
                  <span className="text-xl">🅿️</span>
                </div>
                <h3 className="text-lg font-semibold text-theme-primary">PayPal</h3>
              </div>
              <div className="flex items-center gap-2">
                <div className={`w-3 h-3 rounded-full ${
                  payment_gateways.paypal.connected ? 'bg-theme-success' : 'bg-theme-error'
                } shadow-sm`} />
                <span className={`px-3 py-1 rounded-full text-xs font-medium ${
                  payment_gateways.paypal.connected 
                    ? 'bg-theme-success-background text-theme-success' 
                    : 'bg-theme-error-background text-theme-error'
                }`}>
                  {payment_gateways.paypal.connected ? '✓ Connected' : '✗ Disconnected'}
                </span>
              </div>
            </div>
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <span className="text-sm text-theme-secondary">Environment</span>
                <span className="text-sm font-medium text-theme-primary">{payment_gateways.paypal.environment}</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-sm text-theme-secondary">Webhook Status</span>
                <span className={`text-xs px-2 py-1 rounded font-medium ${
                  payment_gateways.paypal.webhook_status === 'healthy' 
                    ? 'bg-theme-success-background text-theme-success' 
                    : 'bg-theme-warning-background text-theme-warning'
                }`}>
                  {payment_gateways.paypal.webhook_status}
                </span>
              </div>
              {payment_gateways.paypal.last_webhook && (
                <div className="flex items-center justify-between">
                  <span className="text-sm text-theme-secondary">Last Webhook</span>
                  <span className="text-sm font-medium text-theme-primary">
                    {adminSettingsApi.formatRelativeTime(payment_gateways.paypal.last_webhook)}
                  </span>
                </div>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* Recent Activity */}
      <div>
        <h2 className="text-xl font-semibold text-theme-primary mb-6 flex items-center gap-2">
          <span>📈</span>
          <span>Recent Activity</span>
        </h2>
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Recent Users */}
          <div className="bg-theme-surface rounded-xl border border-theme overflow-hidden">
            <div className="px-6 py-4 border-b border-theme bg-theme-background-secondary">
              <h3 className="font-semibold text-theme-primary flex items-center gap-2">
                <span>👥</span>
                <span>Recent Users</span>
                <span className="bg-theme-interactive-primary text-white text-xs px-2 py-1 rounded-full">
                  {recent_users.length}
                </span>
              </h3>
            </div>
            <div className="max-h-80 overflow-y-auto">
              {recent_users.length === 0 ? (
                <div className="p-6 text-center text-theme-secondary">
                  <span className="text-4xl mb-2 block">👥</span>
                  <p>No recent users</p>
                </div>
              ) : (
                <div className="divide-y divide-theme">
                  {recent_users.map((user) => (
                    <div key={user.id} className="p-4">
                      <div className="flex items-center gap-3">
                        <div className="w-10 h-10 bg-theme-interactive-primary rounded-full flex items-center justify-center flex-shrink-0">
                          <span className="text-white font-medium text-sm">
                            {user.first_name[0]}{user.last_name[0]}
                          </span>
                        </div>
                        <div className="flex-1 min-w-0">
                          <p className="font-medium text-theme-primary truncate">{user.full_name}</p>
                          <p className="text-sm text-theme-secondary truncate">{user.email}</p>
                          <div className="flex items-center gap-2 mt-1">
                            <span className="text-xs bg-theme-background px-2 py-1 rounded text-theme-secondary">
                              {user.role}
                            </span>
                            <span className="text-xs text-theme-tertiary">
                              {adminSettingsApi.formatRelativeTime(user.created_at)}
                            </span>
                          </div>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>

          {/* Recent Accounts */}
          <div className="bg-theme-surface rounded-xl border border-theme overflow-hidden">
            <div className="px-6 py-4 border-b border-theme bg-theme-background-secondary">
              <h3 className="font-semibold text-theme-primary flex items-center gap-2">
                <span>🏢</span>
                <span>Recent Accounts</span>
                <span className="bg-theme-interactive-primary text-white text-xs px-2 py-1 rounded-full">
                  {recent_accounts.length}
                </span>
              </h3>
            </div>
            <div className="max-h-80 overflow-y-auto">
              {recent_accounts.length === 0 ? (
                <div className="p-6 text-center text-theme-secondary">
                  <span className="text-4xl mb-2 block">🏢</span>
                  <p>No recent accounts</p>
                </div>
              ) : (
                <div className="divide-y divide-theme">
                  {recent_accounts.map((account) => (
                    <div key={account.id} className="p-4">
                      <div className="flex items-center justify-between">
                        <div className="flex-1 min-w-0">
                          <p className="font-medium text-theme-primary truncate">{account.name}</p>
                          <p className="text-sm text-theme-secondary truncate">{account.owner.email}</p>
                          <div className="flex items-center gap-2 mt-1">
                            <span className={`text-xs px-2 py-1 rounded font-medium ${
                              account.status === 'active' ? 'bg-theme-success-background text-theme-success' :
                              account.status === 'suspended' ? 'bg-theme-warning-background text-theme-warning' :
                              'bg-theme-error-background text-theme-error'
                            }`}>
                              {account.status}
                            </span>
                            <span className="text-xs text-theme-tertiary">
                              {adminSettingsApi.formatRelativeTime(account.created_at)}
                            </span>
                          </div>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>

          {/* Recent System Logs */}
          <div className="bg-theme-surface rounded-xl border border-theme overflow-hidden">
            <div className="px-6 py-4 border-b border-theme bg-theme-background-secondary">
              <h3 className="font-semibold text-theme-primary flex items-center gap-2">
                <span>📝</span>
                <span>System Logs</span>
                <span className="bg-theme-interactive-primary text-white text-xs px-2 py-1 rounded-full">
                  {recent_logs.length}
                </span>
              </h3>
            </div>
            <div className="max-h-80 overflow-y-auto">
              {recent_logs.length === 0 ? (
                <div className="p-6 text-center text-theme-secondary">
                  <span className="text-4xl mb-2 block">📝</span>
                  <p>No recent logs</p>
                </div>
              ) : (
                <div className="divide-y divide-theme">
                  {recent_logs.map((log) => (
                    <div key={log.id} className="p-4">
                      <div className="flex items-start gap-3">
                        <span className={`text-xs px-2 py-1 rounded font-medium flex-shrink-0 ${
                          log.level === 'error' ? 'bg-theme-error-background text-theme-error' :
                          log.level === 'warning' ? 'bg-theme-warning-background text-theme-warning' :
                          log.level === 'info' ? 'bg-theme-info-background text-theme-info' :
                          'bg-theme-surface text-theme-secondary'
                        }`}>
                          {log.level.toUpperCase()}
                        </span>
                        <div className="flex-1 min-w-0">
                          <p className="text-sm text-theme-primary break-words">{log.message}</p>
                          <div className="flex items-center gap-2 mt-1">
                            <span className="text-xs text-theme-tertiary">{log.source}</span>
                            <span className="text-xs text-theme-tertiary">
                              {adminSettingsApi.formatRelativeTime(log.timestamp)}
                            </span>
                          </div>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* Footer */}
      <div className="bg-theme-background-secondary rounded-xl p-4 border border-theme">
        <div className="flex items-center justify-between text-sm text-theme-secondary">
          <div className="flex items-center gap-4">
            <span>Last updated: {settings_summary?.updated_at ? adminSettingsApi.formatRelativeTime(settings_summary.updated_at) : 'Never'}</span>
            <span>•</span>
            <span>Data refreshed: {new Date().toLocaleTimeString()}</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-2 h-2 bg-theme-success rounded-full animate-pulse"></div>
            <span>Live Data</span>
          </div>
        </div>
      </div>
    </div>
  );
};
import React, { useState, useEffect, useCallback } from 'react';
// Removed unused Link import
import { RefreshCw } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { adminSettingsApi, AdminOverviewData } from '@/features/admin/services/adminSettingsApi';
import { servicesApi, HealthStatus } from '@/features/admin/services/servicesApi';
import { ActionCard, MetricCard as StandardMetricCard } from '@/shared/components/ui/Card';


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


export const AdminSettingsOverviewPage: React.FC = () => {
  const [data, setData] = useState<AdminOverviewData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const [servicesHealth, setServicesHealth] = useState<HealthStatus | null>(null);

  const loadOverviewData = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      
      // Load overview data and services health in parallel
      const [overviewData, healthStatus] = await Promise.all([
        adminSettingsApi.getOverview(),
        servicesApi.getHealthStatus().catch(() => null) // Don't fail if services API is unavailable
      ]);
      
      setData(overviewData);
      setServicesHealth(healthStatus);
    } catch (error: any) {
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

  const getBreadcrumbs = () => [
    { label: 'Dashboard', href: '/app', icon: '🏠' },
    { label: 'Admin Settings', href: '/app/admin/settings', icon: '⚙️' },
    { label: 'Overview', icon: '📊' }
  ];

  const getPageActions = () => [
    {
      id: 'refresh',
      label: refreshing ? 'Refreshing...' : 'Refresh',
      onClick: handleRefresh,
      variant: 'secondary' as const,
      icon: RefreshCw,
      disabled: refreshing
    }
  ];

  if (loading && !data) {
    return (
      <PageContainer 
        title="Admin Overview" 
        description="System administration dashboard and monitoring"
        breadcrumbs={getBreadcrumbs()}
        actions={getPageActions()}
      >
        <div className="flex items-center justify-center h-64">
          <div className="text-center">
            <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-theme-interactive-primary mx-auto mb-4"></div>
            <p className="text-theme-secondary">Loading system overview...</p>
          </div>
        </div>
      </PageContainer>
    );
  }

  if (error) {
    return (
      <PageContainer 
        title="Admin Overview" 
        description="System administration dashboard and monitoring"
        breadcrumbs={getBreadcrumbs()}
        actions={getPageActions()}
      >
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
      </PageContainer>
    );
  }

  if (!data) return null;

  const { metrics, recent_users, recent_accounts, recent_logs, payment_gateways, settings_summary } = data;

  // Determine service status from health data
  const getServiceStatus = () => {
    if (!servicesHealth) {
      return { status: 'warning' as const, message: 'Services status unavailable' };
    }
    
    const serviceStatuses = Object.values(servicesHealth.services || {});
    const hasUnhealthyServices = serviceStatuses.some(service => service.status === 'unhealthy' || service.status === 'unreachable');
    
    if (hasUnhealthyServices) {
      return { status: 'warning' as const, message: 'Some services are experiencing issues' };
    }
    
    return { status: 'healthy' as const, message: 'All services operational' };
  };

  // Determine overall system status
  const getSystemStatus = () => {
    if (settings_summary?.maintenance_mode) return { status: 'maintenance' as const, message: 'System in maintenance mode' };
    if (metrics.system_health === 'error') return { status: 'error' as const, message: 'System experiencing errors' };
    if (metrics.system_health === 'warning') return { status: 'warning' as const, message: 'System has warnings' };
    
    // Check services health as well
    const serviceStatus = getServiceStatus();
    if (serviceStatus.status === 'warning') {
      return { status: 'warning' as const, message: 'System has service warnings' };
    }
    
    return { status: 'healthy' as const, message: 'All systems operational' };
  };

  const systemStatus = getSystemStatus();

  return (
    <PageContainer 
      title="Admin Overview" 
      description="System administration dashboard and monitoring"
      breadcrumbs={getBreadcrumbs()}
      actions={getPageActions()}
    >
      {/* System Status Indicator */}
      <div className="flex items-center gap-4 mb-6 p-4 bg-theme-surface rounded-lg border border-theme">
        <span className="text-theme-secondary">System Status:</span>
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
            onClick: () => console.log('Disable maintenance mode')
          } : undefined}
        />

        <SystemStatusCard
          title="Registration"
          status={settings_summary?.registration_enabled ? 'healthy' : 'warning'}
          value={settings_summary?.registration_enabled ? 'Open' : 'Closed'}
          description={settings_summary?.registration_enabled ? 'New users can register' : 'Registration disabled'}
        />

        <SystemStatusCard
          title="Services Health"
          status={getServiceStatus().status}
          value={servicesHealth ? `${Object.keys(servicesHealth.services || {}).length} Services` : 'Checking...'}
          description={servicesHealth ? `Overall: ${servicesHealth.overall_status}` : 'Loading services status...'}
        />
      </div>

      {/* Key Metrics */}
      <div>
        <h2 className="text-xl font-semibold text-theme-primary mb-6 flex items-center gap-2">
          <span>📊</span>
          <span>Key Metrics</span>
        </h2>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
          <StandardMetricCard
            title="Total Users"
            value={adminSettingsApi.formatNumber(metrics.total_users)}
            icon="👥"
            change={12}
            description="Platform users"
          />
          <StandardMetricCard
            title="Active Accounts"
            value={`${metrics.active_accounts}/${metrics.total_accounts}`}
            icon="🏢"
            change={5}
            description="Business accounts"
          />
          <StandardMetricCard
            title="Monthly Revenue"
            value={adminSettingsApi.formatCurrency(metrics.monthly_revenue)}
            icon="💰"
            change={8}
            description="Platform revenue"
          />
          <StandardMetricCard
            title="Active Subscriptions"
            value={`${metrics.active_subscriptions}/${metrics.total_subscriptions}`}
            icon="📋"
            change={3}
            description="Subscription status"
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
          <ActionCard
            icon="⚙️"
            title="System Settings"
            description="Configure platform settings, security, and business rules"
            href="/app/system/admin"
          />
          <ActionCard
            icon="👥"
            title="User Management"
            description="View and manage user accounts, roles, and permissions"
            href="/app/admin/users"
          />
          <ActionCard
            icon="💳"
            title="Payment Gateways"
            description="Configure Stripe and PayPal integrations"
            href="/app/system/gateways"
          />
          <ActionCard
            icon="🔗"
            title="Webhooks"
            description="Manage payment gateway webhooks and endpoints"
            href="/app/system/webhooks"
          />
          <ActionCard
            icon="📝"
            title="Audit Logs"
            description="Review system activity and security events"
            href="/app/system/audit"
            badge={recent_logs.length.toString()}
          />
          <ActionCard
            icon="⚡"
            title="Services"
            description="Manage background job services and authentication"
            href="/app/system/services"
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

      {/* Services Health Status */}
      {servicesHealth && (
        <div>
          <h2 className="text-xl font-semibold text-theme-primary mb-6 flex items-center gap-2">
            <span>🔧</span>
            <span>Services Health Status</span>
          </h2>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {Object.entries(servicesHealth.services || {}).map(([serviceName, serviceData]) => (
              <div key={serviceName} className="group bg-theme-surface rounded-xl p-4 border border-theme hover:bg-theme-surface-hover transition-all duration-200">
                <div className="flex items-center justify-between mb-3">
                  <div className="flex items-center gap-3">
                    <div className={`w-3 h-3 rounded-full ${
                      serviceData.status === 'healthy' ? 'bg-theme-success' :
                      serviceData.status === 'unhealthy' ? 'bg-theme-warning' :
                      'bg-theme-error'
                    } shadow-sm`} />
                    <h3 className="font-semibold text-theme-primary capitalize">{serviceName.replace('_', ' ')}</h3>
                  </div>
                  <span className={`px-2 py-1 rounded text-xs font-medium ${
                    serviceData.status === 'healthy' 
                      ? 'bg-theme-success-background text-theme-success' 
                      : serviceData.status === 'unhealthy'
                      ? 'bg-theme-warning-background text-theme-warning'
                      : 'bg-theme-error-background text-theme-error'
                  }`}>
                    {serviceData.status}
                  </span>
                </div>
                <div className="space-y-2 text-sm">
                  {serviceData.url && (
                    <div className="flex items-center justify-between">
                      <span className="text-theme-secondary">URL</span>
                      <span className="text-theme-primary text-xs truncate max-w-32" title={serviceData.url}>
                        {serviceData.url}
                      </span>
                    </div>
                  )}
                  {serviceData.response_time && (
                    <div className="flex items-center justify-between">
                      <span className="text-theme-secondary">Response Time</span>
                      <span className="text-theme-primary">{serviceData.response_time}ms</span>
                    </div>
                  )}
                  {serviceData.response_code && (
                    <div className="flex items-center justify-between">
                      <span className="text-theme-secondary">Status Code</span>
                      <span className={`font-medium ${
                        serviceData.response_code === '200' ? 'text-theme-success' : 'text-theme-warning'
                      }`}>
                        {serviceData.response_code}
                      </span>
                    </div>
                  )}
                  {serviceData.error && (
                    <div className="mt-2 p-2 bg-theme-error-background rounded text-xs text-theme-error">
                      {serviceData.error}
                    </div>
                  )}
                </div>
              </div>
            ))}
          </div>
          
          {/* Services Summary */}
          <div className="mt-4 p-4 bg-theme-background rounded-lg border border-theme">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2 text-sm">
                <span className="text-theme-secondary">Last checked:</span>
                <span className="text-theme-primary">{servicesHealth.last_checked || 'Unknown'}</span>
              </div>
              <div className="flex items-center gap-2 text-sm">
                <span className="text-theme-secondary">Overall status:</span>
                <span className={`font-medium ${
                  servicesHealth.overall_status === 'healthy' ? 'text-theme-success' : 'text-theme-warning'
                }`}>
                  {servicesHealth.overall_status}
                </span>
              </div>
            </div>
          </div>
        </div>
      )}

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
                  {recent_users.filter(user => user && user.email).map((user) => (
                    <div key={user.id} className="p-4">
                      <div className="flex items-center gap-3">
                        <div className="w-10 h-10 bg-theme-interactive-primary rounded-full flex items-center justify-center flex-shrink-0">
                          <span className="text-white font-medium text-sm">
                            {(user.first_name?.[0] || '?')}{(user.last_name?.[0] || '?')}
                          </span>
                        </div>
                        <div className="flex-1 min-w-0">
                          <p className="font-medium text-theme-primary truncate">{user.full_name}</p>
                          <p className="text-sm text-theme-secondary truncate">{user.email}</p>
                          <div className="flex items-center gap-2 mt-1">
                            <span className="text-xs bg-theme-background px-2 py-1 rounded text-theme-secondary">
                              {Array.isArray(user.roles) && user.roles.length > 0 ? (typeof user.roles[0] === 'object' ? (user.roles[0] as any)?.display_name || (user.roles[0] as any)?.name : user.roles[0]) : 'N/A'}
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
                  {recent_accounts.filter(account => account && account.name).map((account) => (
                    <div key={account.id} className="p-4">
                      <div className="flex items-center justify-between">
                        <div className="flex-1 min-w-0">
                          <p className="font-medium text-theme-primary truncate">{account.name}</p>
                          <p className="text-sm text-theme-secondary truncate">{account.owner?.email || 'No owner assigned'}</p>
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
    </PageContainer>
  );
};
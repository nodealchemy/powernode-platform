import React, { useState, useEffect, useCallback } from 'react';
import {
  RefreshCw,
  Users,
  Building2,
  Clock,
  Activity,
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { AdminMetricsGrid } from './AdminMetricsGrid';
import { AdminSystemHealth } from './AdminSystemHealth';
import { AdminAlertsBanner } from './AdminAlertsBanner';
import { SystemAlertsPanel } from './SystemAlertsPanel';
import { adminSettingsApi, AdminOverviewData } from '../services/adminSettingsApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { formatDateTime } from '@/shared/utils/formatters';

interface AdminDashboardProps {
  onNavigateToAlerts?: () => void;
  onNavigateToUsers?: () => void;
  onNavigateToAccounts?: () => void;
  className?: string;
}

export const AdminDashboard: React.FC<AdminDashboardProps> = ({
  onNavigateToAlerts,
  onNavigateToUsers,
  onNavigateToAccounts,
  className = '',
}) => {
  const [data, setData] = useState<AdminOverviewData | null>(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const { showNotification } = useNotifications();

  const loadData = useCallback(async (isRefresh = false) => {
    if (isRefresh) {
      setRefreshing(true);
    } else {
      setLoading(true);
    }

    try {
      const response = await adminSettingsApi.getOverview();
      if (response.success && response.data) {
        setData(response.data);
      } else {
        showNotification(response.error || 'Failed to load dashboard data', 'error');
      }
    } catch (_error) {
      showNotification('Failed to load dashboard data', 'error');
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [showNotification]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  if (loading && !data) {
    return (
      <div className={`space-y-6 ${className}`}>
        <div className="animate-pulse">
          <div className="h-12 bg-theme-surface rounded-lg mb-6" />
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
            {[1, 2, 3, 4, 5, 6, 7, 8].map((i) => (
              <div key={i} className="h-24 bg-theme-surface rounded-lg" />
            ))}
          </div>
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <div className="h-64 bg-theme-surface rounded-lg" />
            <div className="h-64 bg-theme-surface rounded-lg" />
          </div>
        </div>
      </div>
    );
  }

  const metrics = data?.metrics || {
    total_users: 0,
    total_accounts: 0,
    active_accounts: 0,
    suspended_accounts: 0,
    cancelled_accounts: 0,
    total_subscriptions: 0,
    active_subscriptions: 0,
    trial_subscriptions: 0,
    total_revenue: 0,
    monthly_revenue: 0,
    failed_payments: 0,
    webhook_events_today: 0,
    system_health: 'healthy' as const,
    uptime: 0,
  };

  const paymentGateways = data?.payment_gateways || {
    stripe: {
      connected: false,
      environment: 'test',
      webhook_status: 'no_data' as const,
      last_webhook: null,
    },
    paypal: {
      connected: false,
      environment: 'sandbox',
      webhook_status: 'no_data' as const,
      last_webhook: null,
    },
  };

  return (
    <div className={`space-y-6 ${className}`}>
      {/* Alerts Banner */}
      <AdminAlertsBanner onViewAll={onNavigateToAlerts} />

      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-theme-primary">Admin Dashboard</h1>
          <p className="text-sm text-theme-secondary mt-1">
            System overview and key metrics
          </p>
        </div>
        <Button
          variant="outline"
          onClick={() => loadData(true)}
          disabled={refreshing}
        >
          <RefreshCw className={`w-4 h-4 mr-2 ${refreshing ? 'animate-spin' : ''}`} />
          Refresh
        </Button>
      </div>

      {/* Metrics Grid */}
      <AdminMetricsGrid metrics={metrics} loading={loading} />

      {/* Main Content */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* System Health */}
        <AdminSystemHealth
          systemHealth={metrics.system_health}
          uptime={metrics.uptime}
          paymentGateways={paymentGateways}
          onRefresh={() => loadData(true)}
          loading={refreshing}
        />

        {/* Active Alerts */}
        <SystemAlertsPanel maxDisplayedAlerts={5} />
      </div>

      {/* Recent Activity */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Recent Users */}
        <div className="bg-theme-surface rounded-lg border border-theme">
          <div className="px-6 py-4 border-b border-theme flex items-center justify-between">
            <div className="flex items-center gap-3">
              <Users className="w-5 h-5 text-theme-secondary" />
              <h3 className="text-lg font-semibold text-theme-primary">Recent Users</h3>
            </div>
            {onNavigateToUsers && (
              <Button variant="ghost" onClick={onNavigateToUsers}>
                View All
              </Button>
            )}
          </div>
          <div className="divide-y divide-theme">
            {data?.recent_users?.slice(0, 5).map((user) => (
              <div key={user.id} className="px-6 py-3 flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 rounded-full bg-theme-interactive-primary bg-opacity-10 flex items-center justify-center">
                    <span className="text-sm font-medium text-theme-interactive-primary">
                      {user.full_name?.charAt(0) || user.email.charAt(0).toUpperCase()}
                    </span>
                  </div>
                  <div>
                    <p className="font-medium text-theme-primary">
                      {user.full_name || user.email}
                    </p>
                    <p className="text-sm text-theme-secondary">{user.email}</p>
                  </div>
                </div>
                <div className="text-right">
                  <p className="text-sm text-theme-secondary">
                    {user.account?.name || 'No Account'}
                  </p>
                  <div className="flex items-center gap-1 text-xs text-theme-tertiary">
                    <Clock className="w-3 h-3" />
                    {user.created_at ? formatDateTime(user.created_at) : 'Never'}
                  </div>
                </div>
              </div>
            )) || (
              <div className="px-6 py-8 text-center text-theme-secondary">
                No recent users
              </div>
            )}
          </div>
        </div>

        {/* Recent Accounts */}
        <div className="bg-theme-surface rounded-lg border border-theme">
          <div className="px-6 py-4 border-b border-theme flex items-center justify-between">
            <div className="flex items-center gap-3">
              <Building2 className="w-5 h-5 text-theme-secondary" />
              <h3 className="text-lg font-semibold text-theme-primary">Recent Accounts</h3>
            </div>
            {onNavigateToAccounts && (
              <Button variant="ghost" onClick={onNavigateToAccounts}>
                View All
              </Button>
            )}
          </div>
          <div className="divide-y divide-theme">
            {data?.recent_accounts?.slice(0, 5).map((account) => (
              <div key={account.id} className="px-6 py-3 flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 rounded-lg bg-theme-interactive-primary bg-opacity-10 flex items-center justify-center">
                    <Building2 className="w-5 h-5 text-theme-interactive-primary" />
                  </div>
                  <div>
                    <p className="font-medium text-theme-primary">{account.name}</p>
                    <p className="text-sm text-theme-secondary">
                      {account.users_count} user{account.users_count !== 1 ? 's' : ''}
                      {account.subscription && ` • ${account.subscription.plan?.name || 'Plan'}`}
                    </p>
                  </div>
                </div>
                <div className="text-right">
                  <span
                    className={`px-2 py-1 rounded-full text-xs font-medium ${
                      account.status === 'active'
                        ? 'bg-theme-success bg-opacity-10 text-theme-success'
                        : account.status === 'suspended'
                        ? 'bg-theme-error bg-opacity-10 text-theme-error'
                        : 'bg-theme-secondary bg-opacity-10 text-theme-secondary'
                    }`}
                  >
                    {account.status}
                  </span>
                  <div className="flex items-center gap-1 text-xs text-theme-tertiary mt-1">
                    <Clock className="w-3 h-3" />
                    {account.created_at ? formatDateTime(account.created_at) : 'Never'}
                  </div>
                </div>
              </div>
            )) || (
              <div className="px-6 py-8 text-center text-theme-secondary">
                No recent accounts
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Recent System Logs */}
      <div className="bg-theme-surface rounded-lg border border-theme">
        <div className="px-6 py-4 border-b border-theme flex items-center justify-between">
          <div className="flex items-center gap-3">
            <Activity className="w-5 h-5 text-theme-secondary" />
            <h3 className="text-lg font-semibold text-theme-primary">Recent Activity</h3>
          </div>
        </div>
        <div className="divide-y divide-theme max-h-64 overflow-auto">
          {data?.recent_logs?.slice(0, 10).map((log) => (
            <div key={log.id} className="px-6 py-3 flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div
                  className={`w-2 h-2 rounded-full ${
                    log.level === 'error'
                      ? 'bg-theme-error'
                      : log.level === 'warning'
                      ? 'bg-theme-warning'
                      : 'bg-theme-success'
                  }`}
                />
                <div>
                  <p className="font-medium text-theme-primary">{log.message}</p>
                  <p className="text-sm text-theme-secondary">
                    {log.source} • {log.timestamp ? formatDateTime(log.timestamp) : 'Never'}
                  </p>
                </div>
              </div>
              <span
                className={`px-2 py-1 rounded-full text-xs font-medium uppercase ${
                  log.level === 'error'
                    ? 'bg-theme-error bg-opacity-10 text-theme-error'
                    : log.level === 'warning'
                    ? 'bg-theme-warning bg-opacity-10 text-theme-warning'
                    : 'bg-theme-info bg-opacity-10 text-theme-info'
                }`}
              >
                {log.level}
              </span>
            </div>
          )) || (
            <div className="px-6 py-8 text-center text-theme-secondary">
              No recent activity
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

export default AdminDashboard;

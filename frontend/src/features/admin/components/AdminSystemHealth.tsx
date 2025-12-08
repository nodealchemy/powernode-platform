import React from 'react';
import {
  Server,
  Database,
  Cloud,
  Mail,
  Webhook,
  HardDrive,
  Cpu,
  Activity,
  CheckCircle,
  AlertTriangle,
  XCircle,
  RefreshCw,
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';

interface ComponentHealth {
  name: string;
  status: 'operational' | 'degraded' | 'partial_outage' | 'major_outage';
  response_time: number | null;
  description: string;
  icon: React.ElementType;
}

interface PaymentGateway {
  connected: boolean;
  environment: string;
  webhook_status: 'healthy' | 'warning' | 'unhealthy' | 'no_data';
  last_webhook: string | null;
}

interface AdminSystemHealthProps {
  systemHealth: 'healthy' | 'warning' | 'error';
  uptime: number;
  paymentGateways: {
    stripe: PaymentGateway;
    paypal: PaymentGateway;
  };
  onRefresh?: () => void;
  loading?: boolean;
  className?: string;
}

export const AdminSystemHealth: React.FC<AdminSystemHealthProps> = ({
  systemHealth,
  uptime,
  paymentGateways,
  onRefresh,
  loading = false,
  className = '',
}) => {
  // Format uptime in human-readable format
  const formatUptime = (seconds: number): string => {
    const days = Math.floor(seconds / 86400);
    const hours = Math.floor((seconds % 86400) / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);

    const parts = [];
    if (days > 0) parts.push(`${days}d`);
    if (hours > 0) parts.push(`${hours}h`);
    if (minutes > 0 || parts.length === 0) parts.push(`${minutes}m`);

    return parts.join(' ');
  };

  // Build components list
  const components: ComponentHealth[] = [
    {
      name: 'API Server',
      status: 'operational',
      response_time: null,
      description: 'Core API services',
      icon: Server,
    },
    {
      name: 'Database',
      status: 'operational',
      response_time: null,
      description: 'PostgreSQL database',
      icon: Database,
    },
    {
      name: 'Background Workers',
      status: 'operational',
      response_time: null,
      description: 'Sidekiq job processing',
      icon: Cpu,
    },
    {
      name: 'Cache',
      status: 'operational',
      response_time: null,
      description: 'Redis cache layer',
      icon: HardDrive,
    },
    {
      name: 'Storage',
      status: 'operational',
      response_time: null,
      description: 'File storage services',
      icon: Cloud,
    },
    {
      name: 'Email Service',
      status: 'operational',
      response_time: null,
      description: 'Email delivery',
      icon: Mail,
    },
  ];

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'operational':
      case 'healthy':
        return <CheckCircle className="w-5 h-5 text-theme-success" />;
      case 'degraded':
      case 'warning':
        return <AlertTriangle className="w-5 h-5 text-theme-warning" />;
      case 'partial_outage':
      case 'unhealthy':
        return <AlertTriangle className="w-5 h-5 text-theme-error" />;
      case 'major_outage':
      case 'error':
        return <XCircle className="w-5 h-5 text-theme-error" />;
      default:
        return <Activity className="w-5 h-5 text-theme-secondary" />;
    }
  };

  const getStatusBadge = (status: string) => {
    const statusStyles: Record<string, string> = {
      operational: 'bg-theme-success bg-opacity-10 text-theme-success',
      healthy: 'bg-theme-success bg-opacity-10 text-theme-success',
      degraded: 'bg-theme-warning bg-opacity-10 text-theme-warning',
      warning: 'bg-theme-warning bg-opacity-10 text-theme-warning',
      partial_outage: 'bg-theme-error bg-opacity-10 text-theme-error',
      unhealthy: 'bg-theme-error bg-opacity-10 text-theme-error',
      major_outage: 'bg-theme-error bg-opacity-10 text-theme-error',
      error: 'bg-theme-error bg-opacity-10 text-theme-error',
      no_data: 'bg-theme-secondary bg-opacity-10 text-theme-secondary',
    };

    const style = statusStyles[status] || statusStyles.no_data;
    const label = status.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());

    return (
      <span className={`px-2 py-1 rounded-full text-xs font-medium ${style}`}>
        {label}
      </span>
    );
  };

  const getOverallStatusStyles = () => {
    switch (systemHealth) {
      case 'healthy':
        return {
          bg: 'bg-theme-success-background',
          border: 'border-theme-success',
          text: 'text-theme-success',
          icon: CheckCircle,
        };
      case 'warning':
        return {
          bg: 'bg-theme-warning-background',
          border: 'border-theme-warning',
          text: 'text-theme-warning',
          icon: AlertTriangle,
        };
      case 'error':
        return {
          bg: 'bg-theme-error-background',
          border: 'border-theme-error',
          text: 'text-theme-error',
          icon: XCircle,
        };
      default:
        return {
          bg: 'bg-theme-surface',
          border: 'border-theme',
          text: 'text-theme-primary',
          icon: Activity,
        };
    }
  };

  const styles = getOverallStatusStyles();
  const StatusIcon = styles.icon;

  if (loading) {
    return (
      <div className={`bg-theme-surface rounded-lg border border-theme ${className}`}>
        <div className="p-6 animate-pulse">
          <div className="h-6 bg-theme-background rounded w-1/3 mb-4" />
          <div className="space-y-3">
            {[1, 2, 3, 4].map((i) => (
              <div key={i} className="h-12 bg-theme-background rounded" />
            ))}
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className={`bg-theme-surface rounded-lg border border-theme ${className}`}>
      {/* Header */}
      <div className="px-6 py-4 border-b border-theme">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className={`p-2 rounded-lg ${styles.bg}`}>
              <StatusIcon className={`w-5 h-5 ${styles.text}`} />
            </div>
            <div>
              <h3 className="text-lg font-semibold text-theme-primary">System Health</h3>
              <p className="text-sm text-theme-secondary">
                Uptime: {formatUptime(uptime)}
              </p>
            </div>
          </div>
          {onRefresh && (
            <Button variant="outline" onClick={onRefresh} disabled={loading}>
              <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
            </Button>
          )}
        </div>
      </div>

      {/* Overall Status */}
      <div className={`mx-6 mt-4 p-4 rounded-lg border-2 ${styles.bg} ${styles.border}`}>
        <div className="flex items-center gap-3">
          <StatusIcon className={`w-6 h-6 ${styles.text}`} />
          <div>
            <p className={`font-semibold ${styles.text}`}>
              {systemHealth === 'healthy'
                ? 'All Systems Operational'
                : systemHealth === 'warning'
                ? 'Degraded Performance'
                : 'System Issues Detected'}
            </p>
            <p className="text-sm text-theme-secondary">
              {components.filter((c) => c.status === 'operational').length} of {components.length} components operational
            </p>
          </div>
        </div>
      </div>

      {/* Components */}
      <div className="p-6">
        <h4 className="text-sm font-medium text-theme-secondary mb-3">System Components</h4>
        <div className="space-y-2">
          {components.map((component, index) => {
            const ComponentIcon = component.icon;
            return (
              <div
                key={index}
                className="flex items-center justify-between p-3 bg-theme-background rounded-lg"
              >
                <div className="flex items-center gap-3">
                  <ComponentIcon className="w-5 h-5 text-theme-secondary" />
                  <div>
                    <p className="font-medium text-theme-primary">{component.name}</p>
                    <p className="text-xs text-theme-tertiary">{component.description}</p>
                  </div>
                </div>
                <div className="flex items-center gap-3">
                  {component.response_time !== null && (
                    <span className="text-xs text-theme-secondary">
                      {component.response_time}ms
                    </span>
                  )}
                  {getStatusIcon(component.status)}
                </div>
              </div>
            );
          })}
        </div>

        {/* Payment Gateways */}
        <h4 className="text-sm font-medium text-theme-secondary mt-6 mb-3">
          Payment Gateways
        </h4>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          {/* Stripe */}
          <div className="p-4 bg-theme-background rounded-lg">
            <div className="flex items-center justify-between mb-3">
              <div className="flex items-center gap-2">
                <Webhook className="w-5 h-5 text-theme-secondary" />
                <span className="font-medium text-theme-primary">Stripe</span>
              </div>
              {getStatusBadge(paymentGateways.stripe.connected ? 'operational' : 'major_outage')}
            </div>
            <div className="space-y-1 text-sm">
              <div className="flex justify-between">
                <span className="text-theme-secondary">Environment</span>
                <span className="text-theme-primary capitalize">
                  {paymentGateways.stripe.environment}
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-theme-secondary">Webhook Status</span>
                {getStatusBadge(paymentGateways.stripe.webhook_status)}
              </div>
              {paymentGateways.stripe.last_webhook && (
                <div className="flex justify-between">
                  <span className="text-theme-secondary">Last Webhook</span>
                  <span className="text-theme-tertiary text-xs">
                    {new Date(paymentGateways.stripe.last_webhook).toLocaleString()}
                  </span>
                </div>
              )}
            </div>
          </div>

          {/* PayPal */}
          <div className="p-4 bg-theme-background rounded-lg">
            <div className="flex items-center justify-between mb-3">
              <div className="flex items-center gap-2">
                <Webhook className="w-5 h-5 text-theme-secondary" />
                <span className="font-medium text-theme-primary">PayPal</span>
              </div>
              {getStatusBadge(paymentGateways.paypal.connected ? 'operational' : 'major_outage')}
            </div>
            <div className="space-y-1 text-sm">
              <div className="flex justify-between">
                <span className="text-theme-secondary">Environment</span>
                <span className="text-theme-primary capitalize">
                  {paymentGateways.paypal.environment}
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-theme-secondary">Webhook Status</span>
                {getStatusBadge(paymentGateways.paypal.webhook_status)}
              </div>
              {paymentGateways.paypal.last_webhook && (
                <div className="flex justify-between">
                  <span className="text-theme-secondary">Last Webhook</span>
                  <span className="text-theme-tertiary text-xs">
                    {new Date(paymentGateways.paypal.last_webhook).toLocaleString()}
                  </span>
                </div>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default AdminSystemHealth;

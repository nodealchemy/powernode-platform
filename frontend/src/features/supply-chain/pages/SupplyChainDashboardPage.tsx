import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Shield,
  AlertTriangle,
  FileCode,
  Container,
  Building2,
  Scale,
  CheckCircle2,
  RefreshCw,
  ArrowRight,
  Clock
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useSupplyChainDashboard } from '../hooks/useSupplyChainDashboard';

interface StatCardProps {
  title: string;
  value: string | number;
  subtitle?: string;
  icon: React.ComponentType<{ className?: string }>;
  status?: 'success' | 'warning' | 'error' | 'neutral';
  onClick?: () => void;
}

const StatCard: React.FC<StatCardProps> = ({
  title,
  value,
  subtitle,
  icon: Icon,
  status = 'neutral',
  onClick
}) => {
  const statusColors = {
    success: 'text-theme-success',
    warning: 'text-theme-warning',
    error: 'text-theme-error',
    neutral: 'text-theme-primary'
  };

  const statusBgColors = {
    success: 'bg-theme-success/10',
    warning: 'bg-theme-warning/10',
    error: 'bg-theme-error/10',
    neutral: 'bg-theme-primary/10'
  };

  return (
    <div
      onClick={onClick}
      className={`bg-theme-surface border border-theme rounded-lg p-4 ${onClick ? 'cursor-pointer hover:border-theme-primary transition-colors' : ''}`}
    >
      <div className="flex items-start justify-between">
        <div>
          <p className="text-sm text-theme-secondary">{title}</p>
          <p className={`text-2xl font-bold mt-1 ${statusColors[status]}`}>{value}</p>
          {subtitle && <p className="text-xs text-theme-tertiary mt-1">{subtitle}</p>}
        </div>
        <div className={`p-2 rounded-lg ${statusBgColors[status]}`}>
          <Icon className={`w-5 h-5 ${statusColors[status]}`} />
        </div>
      </div>
    </div>
  );
};

interface QuickLinkCardProps {
  name: string;
  description: string;
  icon: React.ComponentType<{ className?: string }>;
  onClick: () => void;
}

const QuickLinkCard: React.FC<QuickLinkCardProps> = ({
  name,
  description,
  icon: Icon,
  onClick
}) => {
  return (
    <div
      onClick={onClick}
      className="bg-theme-surface border border-theme rounded-lg p-4 cursor-pointer hover:border-theme-primary transition-colors"
    >
      <div className="flex items-center gap-3">
        <div className="p-2 rounded-lg bg-theme-primary/10">
          <Icon className="w-5 h-5 text-theme-primary" />
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="font-medium text-theme-primary truncate">{name}</h3>
          <p className="text-xs text-theme-tertiary truncate">{description}</p>
        </div>
        <ArrowRight className="w-4 h-4 text-theme-tertiary" />
      </div>
    </div>
  );
};

interface AlertsPanelProps {
  alerts: Array<{
    id: string;
    type: string;
    severity: string;
    title: string;
    message: string;
    entity_id: string;
    entity_type: string;
    created_at: string;
  }>;
}

const AlertsPanel: React.FC<AlertsPanelProps> = ({ alerts }) => {
  const getSeverityColor = (severity: string): string => {
    switch (severity.toLowerCase()) {
      case 'critical':
        return 'text-theme-error';
      case 'high':
        return 'text-theme-warning';
      case 'medium':
        return 'text-theme-primary';
      default:
        return 'text-theme-secondary';
    }
  };

  const getSeverityBgColor = (severity: string): string => {
    switch (severity.toLowerCase()) {
      case 'critical':
        return 'bg-theme-error/10';
      case 'high':
        return 'bg-theme-warning/10';
      case 'medium':
        return 'bg-theme-primary/10';
      default:
        return 'bg-theme-secondary/10';
    }
  };

  return (
    <div className="bg-theme-surface border border-theme rounded-lg p-5">
      <div className="flex items-center justify-between mb-4">
        <h3 className="font-semibold text-theme-primary flex items-center gap-2">
          <AlertTriangle className="w-5 h-5" />
          Recent Alerts
        </h3>
      </div>
      {alerts.length > 0 ? (
        <div className="space-y-3">
          {alerts.slice(0, 5).map((alert) => (
            <div
              key={alert.id}
              className={`p-3 rounded-lg ${getSeverityBgColor(alert.severity)}`}
            >
              <div className="flex items-start justify-between gap-2">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <span className={`text-xs font-semibold uppercase ${getSeverityColor(alert.severity)}`}>
                      {alert.severity}
                    </span>
                    <span className="text-xs text-theme-tertiary">{alert.type}</span>
                  </div>
                  <p className="text-sm font-medium text-theme-primary mt-1">{alert.title}</p>
                  <p className="text-xs text-theme-secondary mt-1">{alert.message}</p>
                </div>
              </div>
            </div>
          ))}
        </div>
      ) : (
        <div className="text-center py-8">
          <CheckCircle2 className="w-8 h-8 text-theme-success mx-auto mb-2" />
          <p className="text-sm text-theme-secondary">No recent alerts</p>
        </div>
      )}
    </div>
  );
};

interface ActivityFeedProps {
  activities: Array<{
    id: string;
    action: string;
    entity_type: string;
    entity_name: string;
    user_name?: string;
    details?: string;
    created_at: string;
  }>;
}

const ActivityFeed: React.FC<ActivityFeedProps> = ({ activities }) => {
  const formatTimeAgo = (dateString: string): string => {
    const date = new Date(dateString);
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffMins = Math.floor(diffMs / 60000);

    if (diffMins < 1) return 'Just now';
    if (diffMins < 60) return `${diffMins}m ago`;
    const diffHours = Math.floor(diffMins / 60);
    if (diffHours < 24) return `${diffHours}h ago`;
    const diffDays = Math.floor(diffHours / 24);
    return `${diffDays}d ago`;
  };

  return (
    <div className="bg-theme-surface border border-theme rounded-lg p-5">
      <div className="flex items-center justify-between mb-4">
        <h3 className="font-semibold text-theme-primary flex items-center gap-2">
          <Clock className="w-5 h-5" />
          Recent Activity
        </h3>
      </div>
      {activities.length > 0 ? (
        <div className="space-y-3">
          {activities.slice(0, 5).map((activity) => (
            <div
              key={activity.id}
              className="flex items-start gap-3 p-2 rounded hover:bg-theme-secondary/5 transition-colors"
            >
              <div className="flex-1 min-w-0">
                <p className="text-sm text-theme-primary">
                  <span className="font-medium">{activity.action}</span>
                  {' '}
                  <span className="text-theme-secondary">{activity.entity_type}</span>
                  {' '}
                  <span className="font-medium">{activity.entity_name}</span>
                </p>
                {activity.user_name && (
                  <p className="text-xs text-theme-tertiary mt-1">
                    by {activity.user_name}
                  </p>
                )}
                {activity.details && (
                  <p className="text-xs text-theme-tertiary mt-1">{activity.details}</p>
                )}
              </div>
              <span className="text-xs text-theme-tertiary flex-shrink-0">
                {formatTimeAgo(activity.created_at)}
              </span>
            </div>
          ))}
        </div>
      ) : (
        <div className="text-center py-8">
          <Clock className="w-8 h-8 text-theme-tertiary mx-auto mb-2" />
          <p className="text-sm text-theme-secondary">No recent activity</p>
        </div>
      )}
    </div>
  );
};

export function SupplyChainDashboardPage() {
  const navigate = useNavigate();
  const { data, loading, error, refresh } = useSupplyChainDashboard();
  const [refreshing, setRefreshing] = useState(false);

  const handleRefresh = async () => {
    setRefreshing(true);
    await refresh();
    setRefreshing(false);
  };

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Supply Chain' }
  ];

  const actions = [
    {
      id: 'refresh',
      label: refreshing ? 'Refreshing...' : 'Refresh',
      onClick: handleRefresh,
      variant: 'secondary' as const,
      icon: RefreshCw,
      disabled: refreshing
    }
  ];

  if (loading) {
    return (
      <PageContainer
        title="Supply Chain Security"
        description="Software supply chain security and compliance dashboard"
        breadcrumbs={breadcrumbs}
      >
        <div className="flex items-center justify-center py-12">
          <LoadingSpinner size="lg" />
          <span className="ml-3 text-theme-secondary">Loading dashboard...</span>
        </div>
      </PageContainer>
    );
  }

  if (error || !data) {
    return (
      <PageContainer
        title="Supply Chain Security"
        description="Software supply chain security and compliance dashboard"
        breadcrumbs={breadcrumbs}
        actions={actions}
      >
        <div className="bg-theme-error/10 border border-theme-error/30 rounded-lg p-4">
          <div className="flex items-center gap-2 text-theme-error">
            <AlertTriangle className="w-5 h-5" />
            <span className="font-medium">Failed to load dashboard</span>
          </div>
          {error && <p className="text-sm text-theme-secondary mt-2">{error}</p>}
        </div>
      </PageContainer>
    );
  }

  const quickLinks = [
    {
      id: 'sboms',
      name: 'SBOMs',
      description: 'Software Bill of Materials',
      icon: FileCode,
      href: '/app/supply-chain/sboms'
    },
    {
      id: 'containers',
      name: 'Container Images',
      description: 'Container security and scanning',
      icon: Container,
      href: '/app/supply-chain/containers'
    },
    {
      id: 'attestations',
      name: 'Attestations',
      description: 'Build and provenance verification',
      icon: CheckCircle2,
      href: '/app/supply-chain/attestations'
    },
    {
      id: 'vendors',
      name: 'Vendors',
      description: 'Third-party vendor management',
      icon: Building2,
      href: '/app/supply-chain/vendors'
    },
    {
      id: 'license-policies',
      name: 'License Policies',
      description: 'License compliance rules',
      icon: Scale,
      href: '/app/supply-chain/license-policies'
    },
    {
      id: 'license-violations',
      name: 'License Violations',
      description: 'Policy violation tracking',
      icon: AlertTriangle,
      href: '/app/supply-chain/license-violations'
    }
  ];

  return (
    <PageContainer
      title="Supply Chain Security"
      description="Software supply chain security and compliance dashboard"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      <div className="space-y-6">
        {/* Key Metrics */}
        <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4">
          <StatCard
            title="SBOMs"
            value={data.sbom_count}
            subtitle={`${data.vulnerability_count} vulnerabilities`}
            icon={FileCode}
            status={data.sbom_count > 0 ? 'success' : 'neutral'}
            onClick={() => navigate('/app/supply-chain/sboms')}
          />
          <StatCard
            title="Critical Vulnerabilities"
            value={data.critical_vulnerabilities}
            subtitle={`${data.high_vulnerabilities} high`}
            icon={AlertTriangle}
            status={data.critical_vulnerabilities > 0 ? 'error' : 'success'}
            onClick={() => navigate('/app/supply-chain/vulnerabilities')}
          />
          <StatCard
            title="Container Images"
            value={data.container_image_count}
            subtitle={`${data.quarantined_images} quarantined`}
            icon={Container}
            status={data.quarantined_images > 0 ? 'warning' : 'success'}
            onClick={() => navigate('/app/supply-chain/containers')}
          />
          <StatCard
            title="Attestations"
            value={data.attestation_count}
            subtitle={`${data.verified_attestations} verified`}
            icon={CheckCircle2}
            status={data.verified_attestations > 0 ? 'success' : 'neutral'}
            onClick={() => navigate('/app/supply-chain/attestations')}
          />
          <StatCard
            title="Vendors"
            value={data.vendor_count}
            subtitle={`${data.high_risk_vendors} high risk`}
            icon={Building2}
            status={data.high_risk_vendors > 0 ? 'warning' : 'success'}
            onClick={() => navigate('/app/supply-chain/vendors')}
          />
          <StatCard
            title="License Violations"
            value={data.open_violations}
            subtitle={`${data.license_violation_count} total`}
            icon={Scale}
            status={data.open_violations > 0 ? 'warning' : 'success'}
            onClick={() => navigate('/app/supply-chain/license-violations')}
          />
        </div>

        {/* Alerts and Activity */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <AlertsPanel alerts={data.recent_alerts} />
          <ActivityFeed activities={data.recent_activity} />
        </div>

        {/* Quick Links */}
        <div>
          <h3 className="font-semibold text-theme-primary mb-4">Quick Access</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {quickLinks.map((link) => (
              <QuickLinkCard
                key={link.id}
                name={link.name}
                description={link.description}
                icon={link.icon}
                onClick={() => navigate(link.href)}
              />
            ))}
          </div>
        </div>

        {/* Security Status */}
        {(data.critical_vulnerabilities > 0 || data.quarantined_images > 0 || data.high_risk_vendors > 0) && (
          <div className="bg-theme-warning/10 border border-theme-warning/30 rounded-lg p-4">
            <h3 className="font-semibold text-theme-warning flex items-center gap-2 mb-3">
              <Shield className="w-5 h-5" />
              Security Attention Required
            </h3>
            <div className="space-y-2">
              {data.critical_vulnerabilities > 0 && (
                <div className="flex items-center justify-between text-sm">
                  <span className="text-theme-secondary">
                    {data.critical_vulnerabilities} critical vulnerabilit{data.critical_vulnerabilities > 1 ? 'ies' : 'y'} detected
                  </span>
                  <button
                    onClick={() => navigate('/app/supply-chain/vulnerabilities')}
                    className="text-theme-primary hover:underline"
                  >
                    Review
                  </button>
                </div>
              )}
              {data.quarantined_images > 0 && (
                <div className="flex items-center justify-between text-sm">
                  <span className="text-theme-secondary">
                    {data.quarantined_images} container image{data.quarantined_images > 1 ? 's' : ''} quarantined
                  </span>
                  <button
                    onClick={() => navigate('/app/supply-chain/containers')}
                    className="text-theme-primary hover:underline"
                  >
                    Review
                  </button>
                </div>
              )}
              {data.high_risk_vendors > 0 && (
                <div className="flex items-center justify-between text-sm">
                  <span className="text-theme-secondary">
                    {data.high_risk_vendors} high-risk vendor{data.high_risk_vendors > 1 ? 's' : ''} need assessment
                  </span>
                  <button
                    onClick={() => navigate('/app/supply-chain/vendors')}
                    className="text-theme-primary hover:underline"
                  >
                    Review
                  </button>
                </div>
              )}
            </div>
          </div>
        )}
      </div>
    </PageContainer>
  );
}

export default SupplyChainDashboardPage;

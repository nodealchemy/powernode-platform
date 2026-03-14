import React from 'react';
import { useNavigate } from 'react-router-dom';
import { RefreshCw, AlertTriangle, Shield, Users, FileWarning, Calendar } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { RiskTierBadge } from '../components/RiskTierBadge';
import { Badge } from '@/shared/components/ui/Badge';
import { useVendorRiskDashboard } from '../hooks/useVendorRisk';
import { format } from 'date-fns';

type RiskTier = 'critical' | 'high' | 'medium' | 'low';

export const VendorRiskDashboardPage: React.FC = () => {
  const navigate = useNavigate();
  const { data, loading, error, refresh } = useVendorRiskDashboard();

  if (loading) {
    return (
      <div className="flex justify-center items-center h-64">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  if (error || !data) {
    return (
      <div className="bg-theme-error bg-opacity-10 text-theme-error p-4 rounded-lg">
        {error || 'Failed to load dashboard data'}
      </div>
    );
  }

  const renderStatCard = (
    icon: React.ReactNode,
    value: number,
    label: string,
    variant: 'primary' | 'danger' | 'warning' | 'info'
  ) => {
    const colorClasses = {
      primary: 'text-theme-interactive-primary',
      danger: 'text-theme-error',
      warning: 'text-theme-warning',
      info: 'text-theme-info',
    };

    return (
      <div className="bg-theme-surface rounded-lg p-6 border border-theme shadow-sm">
        <div className="flex items-center gap-4">
          <div className={`${colorClasses[variant]}`}>{icon}</div>
          <div>
            <p className="text-3xl font-bold text-theme-primary">{value}</p>
            <p className="text-sm text-theme-secondary">{label}</p>
          </div>
        </div>
      </div>
    );
  };

  const renderRiskDistributionChart = () => {
    const total = data.total_vendors;
    const distribution = data.risk_distribution;

    const getPercentage = (tier: RiskTier) => {
      return total > 0 ? ((distribution[tier] || 0) / total) * 100 : 0;
    };

    const tiers: Array<{ tier: RiskTier; label: string; color: string }> = [
      { tier: 'critical', label: 'Critical', color: 'bg-theme-error' },
      { tier: 'high', label: 'High', color: 'bg-theme-warning' },
      { tier: 'medium', label: 'Medium', color: 'bg-theme-info' },
      { tier: 'low', label: 'Low', color: 'bg-theme-success' },
    ];

    return (
      <div className="bg-theme-surface rounded-lg p-6 border border-theme">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Risk Distribution</h3>

        <div className="space-y-4">
          {tiers.map(({ tier, label, color }) => {
            const count = distribution[tier] || 0;
            const percentage = getPercentage(tier);

            return (
              <div key={tier}>
                <div className="flex items-center justify-between mb-2">
                  <div className="flex items-center gap-2">
                    <RiskTierBadge tier={tier} />
                    <span className="text-sm text-theme-secondary">{label}</span>
                  </div>
                  <span className="text-sm font-medium text-theme-primary">
                    {count} ({percentage.toFixed(1)}%)
                  </span>
                </div>
                <div className="w-full bg-theme-background rounded-full h-2">
                  <div
                    className={`${color} h-2 rounded-full transition-all duration-300`}
                    style={{ width: `${percentage}%` }}
                  />
                </div>
              </div>
            );
          })}
        </div>
      </div>
    );
  };

  const renderCriticalVendors = () => {
    const criticalCount = data.risk_distribution.critical || 0;

    if (criticalCount === 0) {
      return (
        <div className="bg-theme-surface rounded-lg p-6 border border-theme">
          <h3 className="text-lg font-semibold text-theme-primary mb-4">Critical Risk Vendors</h3>
          <div className="text-center py-8">
            <Shield className="w-12 h-12 text-theme-success mx-auto mb-3 opacity-50" />
            <p className="text-theme-muted">No critical risk vendors</p>
          </div>
        </div>
      );
    }

    return (
      <div className="bg-theme-surface rounded-lg p-6 border border-theme">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-semibold text-theme-primary">Critical Risk Vendors</h3>
          <Badge variant="danger" size="sm">
            {criticalCount} vendors
          </Badge>
        </div>
        <p className="text-theme-secondary text-sm mb-4">
          These vendors require immediate attention and assessment.
        </p>
        <button
          onClick={() => navigate('/app/supply-chain/vendors?filter=critical')}
          className="btn-theme btn-theme-primary btn-theme-sm w-full"
        >
          View All Critical Vendors
        </button>
      </div>
    );
  };

  const renderUpcomingAssessments = () => {
    const upcoming = data.upcoming_assessments || [];

    return (
      <div className="bg-theme-surface rounded-lg p-6 border border-theme">
        <div className="flex items-center gap-2 mb-4">
          <Calendar className="w-5 h-5 text-theme-interactive-primary" />
          <h3 className="text-lg font-semibold text-theme-primary">Upcoming Assessments</h3>
        </div>

        {upcoming.length > 0 ? (
          <div className="space-y-3">
            {upcoming.slice(0, 5).map((assessment) => (
              <div
                key={assessment.vendor_id}
                className="flex items-center justify-between p-3 bg-theme-background rounded-lg hover:bg-theme-surface-hover cursor-pointer transition-colors"
                onClick={() => navigate(`/app/supply-chain/vendors/${assessment.vendor_id}`)}
              >
                <div>
                  <p className="font-medium text-theme-primary">{assessment.vendor_name}</p>
                  <p className="text-sm text-theme-secondary">
                    Due: {format(new Date(assessment.due_date), 'MMM d, yyyy')}
                  </p>
                </div>
                <Badge variant="warning" size="xs">
                  Due Soon
                </Badge>
              </div>
            ))}
            {upcoming.length > 5 && (
              <button
                onClick={() => navigate('/app/supply-chain/vendors?tab=needs-assessment')}
                className="text-theme-interactive-primary text-sm hover:underline w-full text-center mt-2"
              >
                View all {upcoming.length} upcoming assessments
              </button>
            )}
          </div>
        ) : (
          <div className="text-center py-8">
            <FileWarning className="w-12 h-12 text-theme-muted mx-auto mb-3 opacity-50" />
            <p className="text-theme-muted">No upcoming assessments scheduled</p>
          </div>
        )}
      </div>
    );
  };

  return (
    <PageContainer
      title="Vendor Risk Dashboard"
      description="Monitor and manage third-party vendor risk exposure"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'Supply Chain', href: '/app/supply-chain' },
        { label: 'Vendor Risk' },
      ]}
      actions={[
        {
          id: 'refresh',
          label: 'Refresh',
          onClick: refresh,
          variant: 'secondary',
          icon: RefreshCw,
        },
      ]}
    >
      <div className="space-y-6">
        {/* Stats Cards */}
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          {renderStatCard(
            <Users className="w-10 h-10" />,
            data.total_vendors,
            'Total Vendors',
            'primary'
          )}
          {renderStatCard(
            <AlertTriangle className="w-10 h-10" />,
            data.critical_vendors,
            'Critical Risk',
            'danger'
          )}
          {renderStatCard(
            <Shield className="w-10 h-10" />,
            data.high_risk_vendors,
            'High Risk',
            'warning'
          )}
          {renderStatCard(
            <FileWarning className="w-10 h-10" />,
            data.vendors_needing_assessment,
            'Needs Assessment',
            'info'
          )}
        </div>

        {/* Risk Distribution and Critical Vendors */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {renderRiskDistributionChart()}
          {renderCriticalVendors()}
        </div>

        {/* Upcoming Assessments */}
        {renderUpcomingAssessments()}
      </div>
    </PageContainer>
  );
};

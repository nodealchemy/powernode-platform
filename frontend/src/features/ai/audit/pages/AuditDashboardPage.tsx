import React, { useState } from 'react';
import { Shield, AlertTriangle, FileCheck, Activity, Eye } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Card } from '@/shared/components/ui/Card';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { TabContainer } from '@/shared/components/ui/TabContainer';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useAuditStats } from '../api/auditApi';
import { ViolationList } from '../components/ViolationList';
import { PolicyList } from '../components/PolicyList';
import { AuditLogList } from '../components/AuditLogList';
import { SecurityEventList } from '../components/SecurityEventList';

export const AuditDashboardPage: React.FC = () => {
  const { hasPermission } = usePermissions();
  const { data: stats, isLoading: statsLoading } = useAuditStats();
  const [activeTab, setActiveTab] = useState('violations');

  const canView = hasPermission('ai.audits.view');

  if (!canView) {
    return (
      <PageContainer
        title="Security & Compliance"
        breadcrumbs={[
          { label: 'Dashboard', href: '/app' },
          { label: 'AI', href: '/app/ai' },
          { label: 'Security & Compliance' },
        ]}
      >
        <div className="text-center py-12">
          <Shield className="h-12 w-12 text-theme-muted mx-auto mb-4 opacity-50" />
          <p className="text-theme-secondary">You do not have permission to view audit data.</p>
        </div>
      </PageContainer>
    );
  }

  const statCards = [
    {
      label: 'Total Violations',
      value: stats?.total_violations ?? 0,
      icon: AlertTriangle,
      colorClass: 'text-theme-warning',
      bgClass: 'bg-theme-warning',
    },
    {
      label: 'Open / Critical',
      value: `${stats?.open_violations ?? 0} / ${stats?.critical_violations ?? 0}`,
      icon: Shield,
      colorClass: 'text-theme-error',
      bgClass: 'bg-theme-error',
    },
    {
      label: 'Active Policies',
      value: stats?.active_policies ?? 0,
      icon: FileCheck,
      colorClass: 'text-theme-info',
      bgClass: 'bg-theme-info',
    },
    {
      label: 'Compliance Score',
      value: stats?.compliance_score != null ? `${stats.compliance_score}%` : '--',
      icon: Activity,
      colorClass: 'text-theme-success',
      bgClass: 'bg-theme-success',
    },
    {
      label: 'Security Events Today',
      value: stats?.security_events_today ?? 0,
      icon: Eye,
      colorClass: 'text-theme-interactive-primary',
      bgClass: 'bg-theme-interactive-primary',
    },
  ];

  const tabs = [
    {
      id: 'violations',
      label: 'Violations',
      icon: <AlertTriangle className="h-4 w-4" />,
      badge: stats?.open_violations,
      content: <ViolationList />,
    },
    {
      id: 'policies',
      label: 'Policies',
      icon: <FileCheck className="h-4 w-4" />,
      badge: stats?.active_policies,
      content: <PolicyList />,
    },
    {
      id: 'audit-log',
      label: 'Audit Log',
      icon: <Activity className="h-4 w-4" />,
      badge: stats?.audit_entries_today,
      content: <AuditLogList />,
    },
    {
      id: 'security-events',
      label: 'Security Events',
      icon: <Eye className="h-4 w-4" />,
      badge: stats?.security_events_today,
      content: <SecurityEventList />,
    },
  ];

  return (
    <PageContainer
      title="Security & Compliance"
      description="Monitor policy violations, audit trails, and security events"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'AI', href: '/app/ai' },
        { label: 'Security & Compliance' },
      ]}
    >
      {/* Stats Cards */}
      {statsLoading ? (
        <LoadingSpinner size="sm" className="py-4" />
      ) : (
        <div className="grid grid-cols-2 md:grid-cols-5 gap-4 mb-6">
          {statCards.map((stat) => {
            const Icon = stat.icon;
            return (
              <Card key={stat.label} className="p-4">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm text-theme-tertiary">{stat.label}</p>
                    <p className="text-2xl font-semibold text-theme-primary">
                      {typeof stat.value === 'number' ? stat.value.toLocaleString() : stat.value}
                    </p>
                  </div>
                  <div className={`h-10 w-10 ${stat.bgClass} bg-opacity-10 rounded-lg flex items-center justify-center`}>
                    <Icon className={`h-5 w-5 ${stat.colorClass}`} />
                  </div>
                </div>
              </Card>
            );
          })}
        </div>
      )}

      {/* Tabbed Content */}
      <TabContainer
        tabs={tabs}
        activeTab={activeTab}
        onTabChange={setActiveTab}
        variant="underline"
      />
    </PageContainer>
  );
};

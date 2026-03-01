import React, { useState, useCallback, useEffect } from 'react';
import { Box, Play, Pause, CheckCircle, XCircle, Plus } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Card } from '@/shared/components/ui/Card';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { fetchSandboxStats } from '../api/sandboxApi';
import { SandboxList } from '../components/SandboxList';
import type { SandboxStats } from '../types/sandbox';

export const ContainerSandboxContent: React.FC<{ refreshKey?: number }> = ({ refreshKey: externalRefreshKey = 0 }) => {
  const [stats, setStats] = useState<SandboxStats | null>(null);
  const [statsLoading, setStatsLoading] = useState(true);
  const { addNotification } = useNotifications();

  const loadStats = useCallback(async () => {
    try {
      setStatsLoading(true);
      const data = await fetchSandboxStats();
      setStats(data);
    } catch (_error) {
      addNotification({ type: 'error', message: 'Failed to load sandbox stats' });
    } finally {
      setStatsLoading(false);
    }
  }, [addNotification]);

  useEffect(() => {
    loadStats();
  }, [loadStats, externalRefreshKey]);

  const statCards = [
    { label: 'Total', value: stats?.total ?? 0, icon: Box, colorClass: 'text-theme-info', bgClass: 'bg-theme-info' },
    { label: 'Running', value: stats?.running ?? 0, icon: Play, colorClass: 'text-theme-success', bgClass: 'bg-theme-success' },
    { label: 'Paused', value: stats?.paused ?? 0, icon: Pause, colorClass: 'text-theme-warning', bgClass: 'bg-theme-warning' },
    { label: 'Completed', value: stats?.completed ?? 0, icon: CheckCircle, colorClass: 'text-theme-info', bgClass: 'bg-theme-info' },
    { label: 'Failed', value: stats?.failed ?? 0, icon: XCircle, colorClass: 'text-theme-error', bgClass: 'bg-theme-error' },
  ];

  return (
    <>
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
                    <p className="text-2xl font-semibold text-theme-primary">{stat.value}</p>
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

      <SandboxList refreshKey={externalRefreshKey} />
    </>
  );
};

export const SandboxDashboardPage: React.FC = () => {
  const [refreshKey, setRefreshKey] = useState(0);
  const { hasPermission } = usePermissions();

  const canCreateSandbox = hasPermission('ai.sandboxes.create');

  const actions = canCreateSandbox
    ? [
        {
          id: 'create-sandbox',
          label: 'Create Sandbox',
          onClick: () => setRefreshKey((k) => k + 1),
          variant: 'primary' as const,
          icon: Plus,
        },
      ]
    : [];

  return (
    <PageContainer
      title="Agent Sandboxes"
      description="Isolated execution environments for AI agents"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'AI', href: '/app/ai' },
        { label: 'Sandboxes' },
      ]}
      actions={actions}
    >
      <ContainerSandboxContent refreshKey={refreshKey} />
    </PageContainer>
  );
};

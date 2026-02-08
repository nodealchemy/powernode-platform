import React, { useState, useEffect, useCallback } from 'react';
import { useParams, useNavigate, useLocation } from 'react-router-dom';
import { RefreshCw, ArrowLeft } from 'lucide-react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { useSwarmService } from '../hooks/useSwarmService';
import { ServiceTaskList } from '../components/ServiceTaskList';
import { SwarmLogViewer } from '../components/SwarmLogViewer';
import { swarmApi } from '../services/swarmApi';
import type { ServiceLogEntry } from '../types';

const tabs = [
  { id: 'tasks', label: 'Tasks', path: '/' },
  { id: 'logs', label: 'Logs', path: '/logs' },
  { id: 'config', label: 'Config', path: '/config' },
];

export const SwarmServiceDetailPage: React.FC = () => {
  const { clusterId, serviceId } = useParams<{ clusterId: string; serviceId: string }>();
  const navigate = useNavigate();
  const location = useLocation();
  const { service, tasks, isLoading, error, refetch, refetchTasks } = useSwarmService({
    clusterId: clusterId || '',
    serviceId: serviceId || '',
  });
  const [logs, setLogs] = useState<ServiceLogEntry[]>([]);
  const [logsLoading, setLogsLoading] = useState(false);

  const getActiveTab = () => {
    const path = location.pathname;
    if (path.includes('/logs')) return 'logs';
    if (path.includes('/config')) return 'config';
    return 'tasks';
  };

  const [activeTab, setActiveTab] = useState(getActiveTab());

  useEffect(() => {
    const newTab = getActiveTab();
    if (newTab !== activeTab) setActiveTab(newTab);
  }, [location.pathname]);

  const fetchLogs = useCallback(async () => {
    if (!clusterId || !serviceId) return;
    setLogsLoading(true);
    const response = await swarmApi.getServiceLogs(clusterId, serviceId, { tail: 200, timestamps: true });
    if (response.success && response.data) {
      setLogs(response.data.items ?? []);
    }
    setLogsLoading(false);
  }, [clusterId, serviceId]);

  useEffect(() => {
    if (activeTab === 'logs') {
      fetchLogs();
    }
  }, [activeTab, fetchLogs]);

  const handleRefresh = async () => {
    await Promise.all([refetch(), refetchTasks()]);
    if (activeTab === 'logs') await fetchLogs();
  };

  const pageActions: PageAction[] = [
    { label: 'Back', onClick: () => navigate('/app/devops/swarm/services'), variant: 'secondary', icon: ArrowLeft },
    { label: 'Refresh', onClick: handleRefresh, variant: 'secondary', icon: RefreshCw },
  ];

  const getBreadcrumbs = () => {
    const base: Array<{ label: string; href?: string }> = [
      { label: 'Dashboard', href: '/app' },
      { label: 'DevOps', href: '/app/devops' },
      { label: 'Swarm Services', href: '/app/devops/swarm/services' },
      { label: service?.service_name || 'Service' },
    ];
    const activeTabInfo = tabs.find(t => t.id === activeTab);
    if (activeTabInfo && activeTab !== 'tasks') {
      base.push({ label: activeTabInfo.label });
    }
    return base;
  };

  if (isLoading) {
    return (
      <PageContainer title="Service Detail" breadcrumbs={getBreadcrumbs()}>
        <div className="flex items-center justify-center py-20">
          <RefreshCw className="w-6 h-6 animate-spin text-theme-tertiary" />
          <span className="ml-3 text-theme-secondary">Loading service...</span>
        </div>
      </PageContainer>
    );
  }

  if (error || !service) {
    return (
      <PageContainer title="Service Detail" breadcrumbs={getBreadcrumbs()}>
        <div className="text-center py-20">
          <p className="text-theme-error mb-4">{error || 'Service not found'}</p>
          <Button onClick={() => navigate('/app/devops/swarm/services')} variant="secondary" size="sm">Back to Services</Button>
        </div>
      </PageContainer>
    );
  }

  const healthColor = swarmApi.getHealthPercentageColor(service.health_percentage);

  return (
    <PageContainer title={service.service_name} description={`Image: ${service.image}`} breadcrumbs={getBreadcrumbs()} actions={pageActions}>
      <div className="space-y-6">
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <Card variant="default" padding="md">
            <p className="text-xs text-theme-tertiary">Mode</p>
            <p className="text-lg font-semibold text-theme-primary capitalize">{service.mode}</p>
          </Card>
          <Card variant="default" padding="md">
            <p className="text-xs text-theme-tertiary">Replicas</p>
            <p className="text-lg font-semibold text-theme-primary">
              {service.running_replicas} / {service.desired_replicas}
            </p>
          </Card>
          <Card variant="default" padding="md">
            <p className="text-xs text-theme-tertiary">Health</p>
            <p className={`text-lg font-semibold ${healthColor}`}>{service.health_percentage}%</p>
          </Card>
          <Card variant="default" padding="md">
            <p className="text-xs text-theme-tertiary">Ports</p>
            <p className="text-sm font-medium text-theme-primary">
              {service.ports.length > 0
                ? service.ports.map((p) => `${p.published}:${p.target}`).join(', ')
                : 'None'}
            </p>
          </Card>
        </div>

        <TabContainer
          tabs={tabs}
          activeTab={activeTab}
          onTabChange={setActiveTab}
          basePath={`/app/devops/swarm/${clusterId}/services/${serviceId}`}
          variant="underline"
          className="mb-6"
        >
          <TabPanel tabId="tasks" activeTab={activeTab}>
            <ServiceTaskList tasks={tasks} />
          </TabPanel>

          <TabPanel tabId="logs" activeTab={activeTab}>
            <SwarmLogViewer logs={logs} isLoading={logsLoading} onRefresh={fetchLogs} />
          </TabPanel>

          <TabPanel tabId="config" activeTab={activeTab}>
            <Card variant="default" padding="lg">
              <div className="space-y-3">
                <div>
                  <span className="text-xs text-theme-tertiary">Constraints</span>
                  <p className="text-sm text-theme-primary">{service.constraints.length > 0 ? service.constraints.join(', ') : 'None'}</p>
                </div>
                <div>
                  <span className="text-xs text-theme-tertiary">Environment Variables</span>
                  <p className="text-sm text-theme-primary">{service.environment.length} defined</p>
                </div>
                <div>
                  <span className="text-xs text-theme-tertiary">Labels</span>
                  <p className="text-sm text-theme-primary">{Object.keys(service.labels).length} labels</p>
                </div>
                {service.resource_limits.memory_bytes && (
                  <div>
                    <span className="text-xs text-theme-tertiary">Memory Limit</span>
                    <p className="text-sm text-theme-primary">{swarmApi.formatBytes(service.resource_limits.memory_bytes)}</p>
                  </div>
                )}
                {service.resource_limits.nano_cpus && (
                  <div>
                    <span className="text-xs text-theme-tertiary">CPU Limit</span>
                    <p className="text-sm text-theme-primary">{(service.resource_limits.nano_cpus / 1e9).toFixed(2)} CPUs</p>
                  </div>
                )}
              </div>
            </Card>
          </TabPanel>
        </TabContainer>
      </div>
    </PageContainer>
  );
};

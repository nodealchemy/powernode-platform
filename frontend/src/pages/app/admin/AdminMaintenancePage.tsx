import React, { useState, useEffect } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import {
  maintenanceApi,
  MaintenanceStatus,
  BackupInfo,
  SystemHealth,
  CleanupStats,
  MaintenanceSystemMetrics,
  MaintenanceSchedule
} from '@/shared/services/admin/maintenanceApi';
import { RefreshCw, Plus, Trash2 } from 'lucide-react';
import {
  MaintenanceOverviewTab,
  MaintenanceModeTab,
  SystemHealthTab,
  DatabaseBackupsTab,
  DataCleanupTab,
  SystemOperationsTab,
  ScheduledTasksTab,
  MaintenanceTab,
  MaintenancePageActions,
  MAINTENANCE_TABS
} from './maintenance-tabs';

export const AdminMaintenancePage: React.FC = () => {
  const navigate = useNavigate();
  const location = useLocation();
  const { showNotification } = useNotifications();

  // WebSocket for real-time updates
  const { isConnected: _wsConnected } = usePageWebSocket({
    pageType: 'admin',
    onDataUpdate: () => {
      // Trigger data refresh if needed
    }
  });

  // Get active tab from URL path
  const getActiveTabFromPath = (): MaintenanceTab => {
    const pathSegments = location.pathname.split('/');
    const lastSegment = pathSegments[pathSegments.length - 1];
    if (['mode', 'health', 'backups', 'cleanup', 'operations', 'schedules'].includes(lastSegment)) {
      return lastSegment as MaintenanceTab;
    }
    return 'overview';
  };

  const [activeTab, setActiveTab] = useState<MaintenanceTab>(getActiveTabFromPath());
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [actions, setActions] = useState<MaintenancePageActions>({});

  // State for maintenance data
  const [maintenanceStatus, setMaintenanceStatus] = useState<MaintenanceStatus>({
    mode: false,
    message: ''
  });
  const [systemHealth, setSystemHealth] = useState<SystemHealth | null>(null);
  const [systemMetrics, setSystemMetrics] = useState<MaintenanceSystemMetrics | null>(null);
  const [backups, setBackups] = useState<BackupInfo[]>([]);
  const [cleanupStats, setCleanupStats] = useState<CleanupStats | null>(null);
  const [schedules, setSchedules] = useState<MaintenanceSchedule[]>([]);

  const loadMaintenanceData = async () => {
    try {
      setLoading(true);
      setError(null);

      const [status, health, metrics, backupList, cleanup, scheduleList] = await Promise.all([
        maintenanceApi.getMaintenanceStatus(),
        maintenanceApi.getSystemHealth(),
        maintenanceApi.getSystemMetrics(),
        maintenanceApi.getBackups(),
        maintenanceApi.getCleanupStats(),
        maintenanceApi.getMaintenanceSchedules()
      ]);

      setMaintenanceStatus(status);
      setSystemHealth(health);
      setSystemMetrics(metrics);
      setBackups(backupList);
      setCleanupStats(cleanup);
      setSchedules(scheduleList);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Failed to load maintenance data');
      showNotification('Failed to load maintenance data', 'error');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadMaintenanceData();
  }, []);

  useEffect(() => {
    setActiveTab(getActiveTabFromPath());
  }, [location.pathname]);

  const handleTabChange = (tabId: MaintenanceTab) => {
    const tab = MAINTENANCE_TABS.find(t => t.id === tabId);
    if (tab) {
      const targetPath = tabId === 'overview' ? '/app/admin/maintenance' : `/app/admin/maintenance${tab.path}`;
      navigate(targetPath);
    }
  };

  const getBreadcrumbs = () => {
    const activeTabInfo = MAINTENANCE_TABS.find(tab => tab.id === activeTab);
    const breadcrumbs: { label: string; href?: string }[] = [
      { label: 'Dashboard', href: '/app' },
      { label: 'Admin', href: '/app/admin' },
      { label: 'Maintenance', href: '/app/admin/maintenance' }
    ];

    // Don't add overview tab to breadcrumbs
    if (activeTabInfo && activeTabInfo.id !== 'overview') {
      breadcrumbs.push({ label: activeTabInfo.label });
    }

    return breadcrumbs;
  };

  const getPageActions = (): PageAction[] => {
    const baseActions: PageAction[] = [
      {
        id: 'refresh',
        label: 'Refresh',
        onClick: () => { (actions.refreshData && actions.refreshData()) || loadMaintenanceData(); },
        variant: 'secondary',
        icon: RefreshCw
      }
    ];

    switch (activeTab) {
      case 'backups':
        baseActions.push({
          id: 'create-backup',
          label: 'Create Backup',
          onClick: () => { actions.createBackup && actions.createBackup(); },
          variant: 'primary',
          icon: Plus
        });
        break;
      case 'cleanup':
        baseActions.push({
          id: 'run-cleanup',
          label: 'Run Cleanup',
          onClick: () => { actions.runCleanup && actions.runCleanup(); },
          variant: 'primary',
          icon: Trash2
        });
        break;
      case 'schedules':
        baseActions.push({
          id: 'create-schedule',
          label: 'New Schedule',
          onClick: () => { actions.createSchedule && actions.createSchedule(); },
          variant: 'primary',
          icon: Plus
        });
        break;
    }

    return baseActions;
  };

  if (loading) {
    return (
      <PageContainer title="System Maintenance" breadcrumbs={getBreadcrumbs()} actions={getPageActions()}>
        <div className="flex items-center justify-center py-12">
          <LoadingSpinner size="lg" message="Loading maintenance data..." />
        </div>
      </PageContainer>
    );
  }

  if (error) {
    return (
      <PageContainer title="System Maintenance" breadcrumbs={getBreadcrumbs()} actions={getPageActions()}>
        <div className="bg-theme-surface rounded-lg border border-theme p-6">
          <div className="text-center">
            <div className="text-6xl mb-4">⚠️</div>
            <h3 className="text-lg font-medium text-theme-primary mb-2">Error Loading Maintenance Data</h3>
            <p className="text-theme-secondary mb-4">{error}</p>
            <button
              onClick={loadMaintenanceData}
              className="btn-theme btn-theme-primary"
            >
              Try Again
            </button>
          </div>
        </div>
      </PageContainer>
    );
  }

  const renderTabContent = () => {
    switch (activeTab) {
      case 'overview':
        return (
          <MaintenanceOverviewTab
            maintenanceStatus={maintenanceStatus}
            systemHealth={systemHealth}
            systemMetrics={systemMetrics}
            backups={backups}
            cleanupStats={cleanupStats}
            schedules={schedules}
            onNavigateToTab={handleTabChange}
          />
        );
      case 'mode':
        return <MaintenanceModeTab status={maintenanceStatus} onUpdate={loadMaintenanceData} />;
      case 'health':
        return <SystemHealthTab health={systemHealth} metrics={systemMetrics} onRefresh={loadMaintenanceData} />;
      case 'backups':
        return <DatabaseBackupsTab backups={backups} onRefresh={loadMaintenanceData} onRegisterActions={setActions} />;
      case 'cleanup':
        return <DataCleanupTab stats={cleanupStats} onRefresh={loadMaintenanceData} onRegisterActions={setActions} />;
      case 'operations':
        return <SystemOperationsTab health={systemHealth} onRefresh={loadMaintenanceData} />;
      case 'schedules':
        return <ScheduledTasksTab schedules={schedules} onRefresh={loadMaintenanceData} onRegisterActions={setActions} />;
      default:
        return <div>Tab not found</div>;
    }
  };

  return (
    <PageContainer title="System Maintenance" breadcrumbs={getBreadcrumbs()} actions={getPageActions()}>
      {/* Tab Navigation */}
      <div className="border-b border-theme mb-6">
        <div className="flex space-x-8 -mb-px overflow-x-auto scrollbar-hide">
          {MAINTENANCE_TABS.map((tab) => (
            <button
              key={tab.id}
              onClick={() => handleTabChange(tab.id as MaintenanceTab)}
              className={`flex items-center space-x-2 py-2 px-1 border-b-2 font-medium text-sm whitespace-nowrap ${
                activeTab === tab.id
                  ? 'border-theme-link text-theme-link'
                  : 'border-transparent text-theme-secondary hover:text-theme-primary hover:border-theme-tertiary'
              }`}
            >
              <span className="text-base">{tab.icon}</span>
              <span>{tab.label}</span>
            </button>
          ))}
        </div>
      </div>

      {/* Tab Content */}
      <div className="space-y-6">
        {renderTabContent()}
      </div>
    </PageContainer>
  );
};

export default AdminMaintenancePage;

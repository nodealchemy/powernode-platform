// Types for AdminMaintenancePage tabs
import {
  MaintenanceStatus,
  BackupInfo,
  CleanupStats,
  MaintenanceSchedule
} from '@/shared/services/admin/maintenanceApi';

export type MaintenanceTab = 'overview' | 'mode' | 'backups' | 'cleanup' | 'operations' | 'schedules';

export interface MaintenancePageActions {
  refreshData?: () => void;
  createBackup?: () => void;
  runCleanup?: () => void;
  createSchedule?: () => void;
}

export interface MaintenanceOverviewTabProps {
  maintenanceStatus: MaintenanceStatus;
  backups: BackupInfo[];
  cleanupStats: CleanupStats | null;
  schedules: MaintenanceSchedule[];
  onNavigateToTab: (tab: MaintenanceTab) => void;
}

export interface MaintenanceModeTabProps {
  status: MaintenanceStatus;
  onUpdate: () => void;
}

export interface DatabaseBackupsTabProps {
  backups: BackupInfo[];
  onRefresh: () => void;
  onRegisterActions: (actions: MaintenancePageActions) => void;
}

export interface DataCleanupTabProps {
  stats: CleanupStats | null;
  onRefresh: () => void;
  onRegisterActions: (actions: MaintenancePageActions) => void;
}

export interface SystemOperationsTabProps {
  onRefresh: () => void;
}

export interface ScheduledTasksTabProps {
  schedules: MaintenanceSchedule[];
  onRefresh: () => void;
  onRegisterActions: (actions: MaintenancePageActions) => void;
}

// Helper functions for tab definitions
export const MAINTENANCE_TABS = [
  { id: 'overview', label: 'Overview', icon: '📊', path: '' },
  { id: 'mode', label: 'Maintenance Mode', icon: '🔧', path: 'mode' },
  { id: 'backups', label: 'Database Backups', icon: '💾', path: 'backups' },
  { id: 'cleanup', label: 'Data Cleanup', icon: '🗑️', path: 'cleanup' },
  { id: 'operations', label: 'System Operations', icon: '⚙️', path: 'operations' },
  { id: 'schedules', label: 'Scheduled Tasks', icon: '📅', path: 'schedules' }
] as const;

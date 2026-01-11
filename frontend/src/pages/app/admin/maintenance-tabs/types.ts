// Types for AdminMaintenancePage tabs
import {
  MaintenanceStatus,
  BackupInfo,
  SystemHealth,
  CleanupStats,
  MaintenanceSystemMetrics,
  MaintenanceSchedule
} from '@/shared/services/admin/maintenanceApi';

export type MaintenanceTab = 'overview' | 'mode' | 'health' | 'backups' | 'cleanup' | 'operations' | 'schedules';

export interface MaintenancePageActions {
  refreshData?: () => void;
  createBackup?: () => void;
  runCleanup?: () => void;
  createSchedule?: () => void;
}

export interface MaintenanceOverviewTabProps {
  maintenanceStatus: MaintenanceStatus;
  systemHealth: SystemHealth | null;
  systemMetrics: MaintenanceSystemMetrics | null;
  backups: BackupInfo[];
  cleanupStats: CleanupStats | null;
  schedules: MaintenanceSchedule[];
  onNavigateToTab: (tab: MaintenanceTab) => void;
}

export interface MaintenanceModeTabProps {
  status: MaintenanceStatus;
  onUpdate: () => void;
}

export interface SystemHealthTabProps {
  health: SystemHealth | null;
  metrics: MaintenanceSystemMetrics | null;
  onRefresh: () => void;
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
  health: SystemHealth | null;
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
  { id: 'mode', label: 'Maintenance Mode', icon: '🔧', path: '/mode' },
  { id: 'health', label: 'System Health', icon: '💚', path: '/health' },
  { id: 'backups', label: 'Database Backups', icon: '💾', path: '/backups' },
  { id: 'cleanup', label: 'Data Cleanup', icon: '🗑️', path: '/cleanup' },
  { id: 'operations', label: 'System Operations', icon: '⚙️', path: '/operations' },
  { id: 'schedules', label: 'Scheduled Tasks', icon: '📅', path: '/schedules' }
] as const;

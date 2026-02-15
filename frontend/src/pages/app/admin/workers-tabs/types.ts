import type { Worker } from '@/features/system/workers/services/workerApi';

export interface WorkerFiltersState {
  search: string;
  status: 'all' | 'active' | 'suspended' | 'revoked';
  roleType: 'all' | 'system' | 'account';
  roles: string[];
  permissions: string[];
  sortBy: 'name' | 'created_at' | 'last_seen_at' | 'request_count';
  sortOrder: 'asc' | 'desc';
}

export interface WorkersPageState {
  workers: Worker[];
  filteredWorkers: Worker[];
  selectedWorkers: Set<string>;
  selectedWorker: Worker | null;
  loading: boolean;
  error: string | null;
  showCreateModal: boolean;
  showDetailsPanel: boolean;
  viewMode: 'grid' | 'table';
  filters: WorkerFiltersState;
  pagination: {
    page: number;
    pageSize: number;
    total: number;
  };
}

export interface WorkerStats {
  total: number;
  active: number;
  suspended: number;
  revoked: number;
  systemWorkers: number;
  accountWorkers: number;
  recentlyActive: number;
}

export interface WorkerOverviewTabProps {
  workers: Worker[];
  stats: WorkerStats;
  onRefresh: () => void;
  loading: boolean;
}

export interface WorkerManagementTabProps {
  state: WorkersPageState;
  setState: React.Dispatch<React.SetStateAction<WorkersPageState>>;
  canManageWorkers: boolean;
  handleFiltersChange: (newFilters: Partial<WorkerFiltersState>) => void;
  handleWorkerSelect: (workerId: string, selected: boolean) => void;
  handleWorkerView: (worker: Worker) => void;
  handleBulkAction: (action: string, workerIds: string[]) => Promise<void>;
  loadWorkers: () => Promise<void>;
}

export interface WorkerActivityTabProps {
  workers: Worker[];
  onRefresh: () => void;
}

export interface WorkerSecurityTabProps {
  workers: Worker[];
  canManageWorkers: boolean;
  onRefresh: () => void;
}

export interface WorkerSettingsTabProps {
  workers: Worker[];
  canManageWorkers: boolean;
  onRefresh: () => void;
}

export type { Worker } from '@/features/system/workers/services/workerApi';

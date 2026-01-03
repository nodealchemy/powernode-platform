import React, { useState, useEffect, useCallback } from 'react';
import {
  Clock,
  Plus,
  RefreshCw,
  Play,
  Pause,
  Trash2,
  Edit,
  CheckCircle,
  XCircle,
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { gitProvidersApi } from '@/features/git-providers/services/gitProvidersApi';
import {
  GitPipelineSchedule,
  GitPipelineScheduleDetail,
  GitRepository,
  PaginationInfo,
} from '@/features/git-providers/types';
import { useAuth } from '@/shared/hooks/useAuth';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { ScheduleModal } from './ScheduleModal';

interface ScheduleWithRepo extends GitPipelineSchedule {
  repository?: {
    id: string;
    name: string;
    full_name: string;
  };
}

export const PipelineSchedulesPage: React.FC = () => {
  const { currentUser } = useAuth();
  const { showNotification } = useNotifications();

  // State
  const [schedules, setSchedules] = useState<ScheduleWithRepo[]>([]);
  const [repositories, setRepositories] = useState<GitRepository[]>([]);
  const [loading, setLoading] = useState(true);
  const [pagination, setPagination] = useState<PaginationInfo | null>(null);
  const [page, setPage] = useState(1);

  // Filters
  const [selectedRepo, setSelectedRepo] = useState<string>('');
  const [statusFilter, setStatusFilter] = useState<string>('');

  // Modal state
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingSchedule, setEditingSchedule] = useState<GitPipelineScheduleDetail | null>(null);
  const [selectedRepoForNew, setSelectedRepoForNew] = useState<GitRepository | null>(null);

  const canManageSchedules = currentUser?.permissions?.includes('git.schedules.manage');

  // Fetch repositories (runs once on mount)
  useEffect(() => {
    let mounted = true;
    const fetchRepos = async () => {
      try {
        const result = await gitProvidersApi.getRepositories({ per_page: 100 });
        if (mounted) {
          setRepositories(result.repositories);
        }
      } catch {
        if (mounted) {
          showNotification('Failed to load repositories', 'error');
        }
      }
    };
    fetchRepos();
    return () => { mounted = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Fetch schedules - use refs to avoid dependency issues
  const fetchSchedules = useCallback(async () => {
    // Get current repositories from state at call time
    setLoading(true);
    try {
      const reposSnapshot = await gitProvidersApi.getRepositories({ per_page: 100 });
      const repos = reposSnapshot.repositories;

      if (!selectedRepo && repos.length === 0) {
        setLoading(false);
        return;
      }

      const allSchedules: ScheduleWithRepo[] = [];

      if (selectedRepo) {
        const result = await gitProvidersApi.getSchedules(selectedRepo, {
          page,
          per_page: 20,
          active: statusFilter === 'active' ? true : statusFilter === 'inactive' ? false : undefined,
        });
        const repo = repos.find((r) => r.id === selectedRepo);
        result.schedules.forEach((s) => {
          allSchedules.push({
            ...s,
            repository: repo ? { id: repo.id, name: repo.name, full_name: repo.full_name } : undefined,
          });
        });
        setPagination(result.pagination);
      } else {
        // Fetch schedules for all repositories
        for (const repo of repos.slice(0, 10)) {
          try {
            const result = await gitProvidersApi.getSchedules(repo.id, {
              page: 1,
              per_page: 50,
              active: statusFilter === 'active' ? true : statusFilter === 'inactive' ? false : undefined,
            });
            result.schedules.forEach((s) => {
              allSchedules.push({
                ...s,
                repository: { id: repo.id, name: repo.name, full_name: repo.full_name },
              });
            });
          } catch {
            // Skip repos that fail
          }
        }
        setPagination(null);
      }

      setSchedules(allSchedules);
    } catch {
      showNotification('Failed to load schedules', 'error');
    } finally {
      setLoading(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedRepo, page, statusFilter]);

  // Fetch schedules when filters change or repositories are loaded
  useEffect(() => {
    if (repositories.length > 0) {
      fetchSchedules();
    }
    // Only re-run when these specific values change, not fetchSchedules itself
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [repositories.length, selectedRepo, page, statusFilter]);

  const handleTrigger = async (schedule: GitPipelineSchedule) => {
    try {
      await gitProvidersApi.triggerSchedule(schedule.id);
      showNotification(`Schedule "${schedule.name}" triggered successfully`, 'success');
      fetchSchedules();
    } catch {
      showNotification('Failed to trigger schedule', 'error');
    }
  };

  const handleToggle = async (schedule: GitPipelineSchedule) => {
    try {
      if (schedule.is_active) {
        await gitProvidersApi.pauseSchedule(schedule.id);
        showNotification(`Schedule "${schedule.name}" paused`, 'success');
      } else {
        await gitProvidersApi.resumeSchedule(schedule.id);
        showNotification(`Schedule "${schedule.name}" resumed`, 'success');
      }
      fetchSchedules();
    } catch {
      showNotification('Failed to update schedule', 'error');
    }
  };

  const handleDelete = async (schedule: GitPipelineSchedule) => {
    if (!confirm(`Are you sure you want to delete "${schedule.name}"?`)) {
      return;
    }

    try {
      await gitProvidersApi.deleteSchedule(schedule.id);
      showNotification(`Schedule "${schedule.name}" deleted`, 'success');
      fetchSchedules();
    } catch {
      showNotification('Failed to delete schedule', 'error');
    }
  };

  const handleEdit = async (schedule: GitPipelineSchedule) => {
    try {
      const detail = await gitProvidersApi.getSchedule(schedule.id);
      setEditingSchedule(detail);
      setIsModalOpen(true);
    } catch {
      showNotification('Failed to load schedule details', 'error');
    }
  };

  const handleCreate = (repo: GitRepository) => {
    setSelectedRepoForNew(repo);
    setEditingSchedule(null);
    setIsModalOpen(true);
  };

  const handleModalClose = () => {
    setIsModalOpen(false);
    setEditingSchedule(null);
    setSelectedRepoForNew(null);
  };

  const handleModalSuccess = () => {
    setIsModalOpen(false);
    setEditingSchedule(null);
    setSelectedRepoForNew(null);
    fetchSchedules();
    showNotification(
      editingSchedule ? 'Schedule updated successfully' : 'Schedule created successfully',
      'success'
    );
  };

  const getStatusIcon = (schedule: GitPipelineSchedule) => {
    if (!schedule.is_active) {
      return <Pause className="w-4 h-4 text-theme-secondary" />;
    }
    switch (schedule.last_run_status) {
      case 'success':
        return <CheckCircle className="w-4 h-4 text-theme-success" />;
      case 'failure':
        return <XCircle className="w-4 h-4 text-theme-danger" />;
      default:
        return <Clock className="w-4 h-4 text-theme-primary" />;
    }
  };

  const formatNextRun = (nextRunAt?: string) => {
    if (!nextRunAt) return 'Not scheduled';
    const date = new Date(nextRunAt);
    const now = new Date();
    const diff = date.getTime() - now.getTime();
    if (diff < 0) return 'Overdue';
    if (diff < 3600000) return `in ${Math.round(diff / 60000)} min`;
    if (diff < 86400000) return `in ${Math.round(diff / 3600000)} hrs`;
    return date.toLocaleDateString();
  };

  const actions = [
    {
      id: 'create',
      label: 'New Schedule',
      onClick: () => {
        if (repositories.length > 0) {
          handleCreate(repositories[0]);
        }
      },
      variant: 'primary' as const,
      icon: Plus,
      disabled: !canManageSchedules || repositories.length === 0,
    },
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: fetchSchedules,
      variant: 'outline' as const,
      icon: RefreshCw,
    },
  ];

  if (loading && schedules.length === 0) {
    return (
      <PageContainer
        title="Pipeline Schedules"
        description="Manage scheduled pipeline executions"
        breadcrumbs={[
          { label: 'CI/CD', href: '/app/ci-cd' },
          { label: 'Schedules' },
        ]}
      >
        <div className="flex items-center justify-center h-64">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-primary"></div>
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title="Pipeline Schedules"
      description="Manage scheduled pipeline executions across repositories"
      breadcrumbs={[
        { label: 'CI/CD', href: '/app/ci-cd' },
        { label: 'Schedules' },
      ]}
      actions={actions}
    >
      {/* Filters */}
      <div className="bg-theme-surface border border-theme rounded-lg p-4 mb-6">
        <div className="flex flex-wrap gap-4">
          <div className="flex-1 min-w-[200px]">
            <label className="block text-sm font-medium text-theme-secondary mb-1">
              Repository
            </label>
            <select
              value={selectedRepo}
              onChange={(e) => setSelectedRepo(e.target.value)}
              className="w-full bg-theme-surface border border-theme rounded-lg px-3 py-2 text-theme-primary [&>option]:bg-theme-surface [&>option]:text-theme-primary"
            >
              <option value="">All Repositories</option>
              {repositories.map((repo) => (
                <option key={repo.id} value={repo.id}>
                  {repo.full_name}
                </option>
              ))}
            </select>
          </div>
          <div className="w-[150px]">
            <label className="block text-sm font-medium text-theme-secondary mb-1">
              Status
            </label>
            <select
              value={statusFilter}
              onChange={(e) => setStatusFilter(e.target.value)}
              className="w-full bg-theme-surface border border-theme rounded-lg px-3 py-2 text-theme-primary [&>option]:bg-theme-surface [&>option]:text-theme-primary"
            >
              <option value="">All</option>
              <option value="active">Active</option>
              <option value="inactive">Paused</option>
            </select>
          </div>
        </div>
      </div>

      {/* Schedules Table */}
      {schedules.length > 0 ? (
        <div className="bg-theme-surface border border-theme rounded-lg overflow-hidden">
          <table className="w-full">
            <thead className="bg-theme-bg">
              <tr>
                <th className="px-4 py-3 text-left text-sm font-medium text-theme-secondary">
                  Schedule
                </th>
                <th className="px-4 py-3 text-left text-sm font-medium text-theme-secondary">
                  Repository
                </th>
                <th className="px-4 py-3 text-left text-sm font-medium text-theme-secondary">
                  Cron
                </th>
                <th className="px-4 py-3 text-left text-sm font-medium text-theme-secondary">
                  Next Run
                </th>
                <th className="px-4 py-3 text-left text-sm font-medium text-theme-secondary">
                  Success Rate
                </th>
                <th className="px-4 py-3 text-right text-sm font-medium text-theme-secondary">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-theme">
              {schedules.map((schedule) => (
                <tr key={schedule.id} className="hover:bg-theme-bg/50">
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-2">
                      {getStatusIcon(schedule)}
                      <div>
                        <p className="text-theme-primary font-medium">{schedule.name}</p>
                        <p className="text-sm text-theme-secondary">{schedule.ref}</p>
                      </div>
                    </div>
                  </td>
                  <td className="px-4 py-3 text-theme-secondary">
                    {schedule.repository?.full_name || '-'}
                  </td>
                  <td className="px-4 py-3">
                    <code className="text-sm bg-theme-bg px-2 py-1 rounded">
                      {schedule.cron_expression}
                    </code>
                  </td>
                  <td className="px-4 py-3 text-theme-secondary">
                    {schedule.is_active ? formatNextRun(schedule.next_run_at) : 'Paused'}
                  </td>
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-2">
                      <div className="w-16 bg-theme-bg rounded-full h-2">
                        <div
                          className="h-2 rounded-full bg-theme-success"
                          style={{ width: `${schedule.success_rate}%` }}
                        />
                      </div>
                      <span className="text-sm text-theme-secondary">
                        {schedule.success_rate.toFixed(0)}%
                      </span>
                    </div>
                  </td>
                  <td className="px-4 py-3">
                    <div className="flex items-center justify-end gap-2">
                      <button
                        onClick={() => handleTrigger(schedule)}
                        className="p-1.5 hover:bg-theme-bg rounded text-theme-secondary hover:text-theme-primary"
                        title="Trigger Now"
                        disabled={!canManageSchedules}
                      >
                        <Play className="w-4 h-4" />
                      </button>
                      <button
                        onClick={() => handleToggle(schedule)}
                        className="p-1.5 hover:bg-theme-bg rounded text-theme-secondary hover:text-theme-primary"
                        title={schedule.is_active ? 'Pause' : 'Resume'}
                        disabled={!canManageSchedules}
                      >
                        {schedule.is_active ? (
                          <Pause className="w-4 h-4" />
                        ) : (
                          <Play className="w-4 h-4" />
                        )}
                      </button>
                      <button
                        onClick={() => handleEdit(schedule)}
                        className="p-1.5 hover:bg-theme-bg rounded text-theme-secondary hover:text-theme-primary"
                        title="Edit"
                        disabled={!canManageSchedules}
                      >
                        <Edit className="w-4 h-4" />
                      </button>
                      <button
                        onClick={() => handleDelete(schedule)}
                        className="p-1.5 hover:bg-theme-bg rounded text-theme-secondary hover:text-theme-danger"
                        title="Delete"
                        disabled={!canManageSchedules}
                      >
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>

          {/* Pagination */}
          {pagination && pagination.total_pages > 1 && (
            <div className="px-4 py-3 border-t border-theme flex items-center justify-between">
              <p className="text-sm text-theme-secondary">
                Page {pagination.current_page} of {pagination.total_pages}
              </p>
              <div className="flex gap-2">
                <button
                  onClick={() => setPage((p) => Math.max(1, p - 1))}
                  disabled={page === 1}
                  className="px-3 py-1 border border-theme rounded text-sm disabled:opacity-50"
                >
                  Previous
                </button>
                <button
                  onClick={() => setPage((p) => p + 1)}
                  disabled={page >= pagination.total_pages}
                  className="px-3 py-1 border border-theme rounded text-sm disabled:opacity-50"
                >
                  Next
                </button>
              </div>
            </div>
          )}
        </div>
      ) : (
        <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
          <Clock className="w-12 h-12 mx-auto text-theme-secondary mb-4" />
          <h3 className="text-lg font-medium text-theme-primary mb-2">No Schedules</h3>
          <p className="text-theme-secondary mb-4">
            {selectedRepo
              ? 'No schedules found for this repository.'
              : 'Create a schedule to automatically run pipelines.'}
          </p>
          {canManageSchedules && repositories.length > 0 && (
            <button
              onClick={() => handleCreate(repositories[0])}
              className="btn-theme btn-theme-primary inline-flex items-center gap-2"
            >
              <Plus className="w-4 h-4" />
              New Schedule
            </button>
          )}
        </div>
      )}

      {/* Schedule Modal */}
      <ScheduleModal
        isOpen={isModalOpen}
        onClose={handleModalClose}
        onSuccess={handleModalSuccess}
        schedule={editingSchedule}
        repository={selectedRepoForNew || editingSchedule?.repository}
        repositories={repositories}
      />
    </PageContainer>
  );
};

export default PipelineSchedulesPage;

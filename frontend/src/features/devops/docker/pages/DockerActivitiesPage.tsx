import React, { useState, useEffect } from 'react';
import { RefreshCw, Clock } from 'lucide-react';
import type { PageAction } from '@/shared/components/layout/PageContainer';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { useHostContext } from '../hooks/useHostContext';
import { useDockerActivities } from '../hooks/useDockerActivities';
import { dockerApi } from '../services/dockerApi';
import type { ActivityType, ActivityStatus } from '../types';

const HostSelector: React.FC = () => {
  const { hosts, selectedHostId, selectHost, isLoading } = useHostContext();
  if (isLoading) return <span className="text-sm text-theme-tertiary">Loading hosts...</span>;
  if (hosts.length === 0) return <span className="text-sm text-theme-tertiary">No hosts configured</span>;
  const selected = hosts.find((h) => h.id === selectedHostId);
  return (
    <div className="flex items-center gap-3">
      <label className="text-sm font-medium text-theme-secondary">Host:</label>
      <select className="input-theme text-sm min-w-[200px]" value={selectedHostId || ''} onChange={(e) => selectHost(e.target.value || null)}>
        <option value="">Select host...</option>
        {hosts.map((h) => <option key={h.id} value={h.id}>{h.name} ({h.environment})</option>)}
      </select>
      {selected && (
        <span className={`px-2 py-0.5 rounded text-xs font-medium ${dockerApi.getHostStatusColor(selected.status)}`}>
          {selected.status}
        </span>
      )}
    </div>
  );
};

interface DockerActivitiesPageProps {
  onActionsReady?: (actions: PageAction[]) => void;
}

export const DockerActivitiesPage: React.FC<DockerActivitiesPageProps> = ({ onActionsReady }) => {
  const { selectedHostId } = useHostContext();
  const [typeFilter, setTypeFilter] = useState<ActivityType | undefined>();
  const [statusFilter, setStatusFilter] = useState<ActivityStatus | undefined>();
  const [page, setPage] = useState(1);
  const filters = {
    ...(typeFilter && { activity_type: typeFilter }),
    ...(statusFilter && { status: statusFilter }),
  };
  const { activities, pagination, isLoading, error, refresh } = useDockerActivities(
    selectedHostId,
    page,
    20,
    Object.keys(filters).length > 0 ? filters : undefined
  );

  const pageActions: PageAction[] = [
    { label: 'Refresh', onClick: refresh, variant: 'secondary', icon: RefreshCw },
  ];

  useEffect(() => {
    onActionsReady?.(pageActions);
  }, [onActionsReady]);

  return (
    <>
      <div className="space-y-4">
        <div className="flex items-center gap-4 flex-wrap">
          <HostSelector />
          <select className="input-theme text-sm" value={typeFilter || ''} onChange={(e) => { setTypeFilter(e.target.value as ActivityType || undefined); setPage(1); }}>
            <option value="">All types</option>
            <option value="create">Create</option>
            <option value="start">Start</option>
            <option value="stop">Stop</option>
            <option value="restart">Restart</option>
            <option value="remove">Remove</option>
            <option value="pull">Pull</option>
            <option value="image_remove">Image Remove</option>
            <option value="image_tag">Image Tag</option>
          </select>
          <select className="input-theme text-sm" value={statusFilter || ''} onChange={(e) => { setStatusFilter(e.target.value as ActivityStatus || undefined); setPage(1); }}>
            <option value="">All statuses</option>
            <option value="pending">Pending</option>
            <option value="running">Running</option>
            <option value="completed">Completed</option>
            <option value="failed">Failed</option>
          </select>
        </div>

        {!selectedHostId ? (
          <Card variant="default" padding="lg" className="text-center">
            <p className="text-theme-secondary">Select a host to view activities.</p>
          </Card>
        ) : isLoading ? (
          <div className="flex items-center justify-center py-20">
            <RefreshCw className="w-6 h-6 animate-spin text-theme-tertiary" />
            <span className="ml-3 text-theme-secondary">Loading activities...</span>
          </div>
        ) : error ? (
          <div className="text-center py-20">
            <p className="text-theme-error mb-4">{error}</p>
            <Button onClick={refresh} variant="secondary" size="sm">Retry</Button>
          </div>
        ) : activities.length === 0 ? (
          <Card variant="default" padding="lg" className="text-center">
            <Clock className="w-12 h-12 mx-auto text-theme-tertiary mb-4" />
            <p className="text-theme-secondary">No activities found.</p>
          </Card>
        ) : (
          <div className="space-y-3">
            {activities.map((activity) => (
              <Card key={activity.id} variant="default" padding="md">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-3 flex-1 min-w-0">
                    <span className={`px-2 py-0.5 rounded text-xs font-medium ${dockerApi.getActivityStatusColor(activity.status)}`}>
                      {activity.status}
                    </span>
                    <span className="px-2 py-0.5 rounded bg-theme-surface text-theme-secondary text-xs font-medium">
                      {activity.activity_type}
                    </span>
                    <div className="flex-1 min-w-0">
                      {activity.triggered_by && (
                        <span className="text-sm text-theme-secondary">by {activity.triggered_by}</span>
                      )}
                    </div>
                  </div>
                  <div className="flex items-center gap-3 text-xs text-theme-tertiary">
                    {activity.duration_ms != null && <span>{dockerApi.formatDuration(activity.duration_ms)}</span>}
                    <span>{new Date(activity.created_at).toLocaleString()}</span>
                  </div>
                </div>
              </Card>
            ))}

            {pagination && pagination.total_pages > 1 && (
              <div className="flex items-center justify-center gap-3 pt-4">
                <Button size="sm" variant="ghost" disabled={page <= 1} onClick={() => setPage(page - 1)}>Previous</Button>
                <span className="text-sm text-theme-secondary">Page {page} of {pagination.total_pages}</span>
                <Button size="sm" variant="ghost" disabled={page >= pagination.total_pages} onClick={() => setPage(page + 1)}>Next</Button>
              </div>
            )}
          </div>
        )}
      </div>
    </>
  );
};

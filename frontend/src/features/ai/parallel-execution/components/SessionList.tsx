import React, { useEffect, useState } from 'react';
import { Plus, RefreshCw } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Select } from '@/shared/components/ui/Select';
import { Loading } from '@/shared/components/ui/Loading';
import { SessionCard } from './SessionCard';
import type { ParallelSession } from '../types';

interface SessionListProps {
  sessions: ParallelSession[];
  loading: boolean;
  onSelectSession: (session: ParallelSession) => void;
  onCreateSession: () => void;
  onRefresh: (filters?: Record<string, string>) => void;
}

export const SessionList: React.FC<SessionListProps> = ({
  sessions,
  loading,
  onSelectSession,
  onCreateSession,
  onRefresh,
}) => {
  const [statusFilter, setStatusFilter] = useState('');

  useEffect(() => {
    const filters: Record<string, string> = {};
    if (statusFilter) filters.status = statusFilter;
    onRefresh(filters);
  }, [statusFilter]);

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Select
            value={statusFilter}
            onChange={(value) => setStatusFilter(value)}
          >
            <option value="">All Statuses</option>
            <option value="active">Active</option>
            <option value="provisioning">Provisioning</option>
            <option value="merging">Merging</option>
            <option value="completed">Completed</option>
            <option value="failed">Failed</option>
            <option value="cancelled">Cancelled</option>
          </Select>
          <Button
            variant="outline"
            size="sm"
            onClick={() => onRefresh(statusFilter ? { status: statusFilter } : undefined)}
          >
            <RefreshCw className="w-4 h-4" />
          </Button>
        </div>
        <Button variant="primary" size="sm" onClick={onCreateSession}>
          <Plus className="w-4 h-4 mr-1" />
          New Session
        </Button>
      </div>

      {loading ? (
        <div className="flex items-center justify-center p-8">
          <Loading size="lg" />
        </div>
      ) : sessions.length === 0 ? (
        <div className="text-center p-12 text-theme-text-secondary">
          <p className="text-lg font-medium mb-2">No parallel execution sessions</p>
          <p className="text-sm mb-4">Create a session to start parallel agent execution with git worktrees.</p>
          <Button variant="primary" onClick={onCreateSession}>
            <Plus className="w-4 h-4 mr-1" />
            Create Session
          </Button>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {sessions.map((session) => (
            <SessionCard
              key={session.id}
              session={session}
              onClick={onSelectSession}
            />
          ))}
        </div>
      )}
    </div>
  );
};

import React, { useState, useEffect, useCallback } from 'react';
import { impersonationApi, ImpersonationSession } from '@/shared/services/impersonationApi';
import { Button } from '@/shared/components/ui/Button';
import { FormField } from '@/shared/components/ui/FormField';

export const ImpersonationHistory: React.FC = () => {
  const [sessions, setSessions] = useState<ImpersonationSession[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // const [currentPage, setCurrentPage] = useState(1);
  // const [totalPages, setTotalPages] = useState(1);
  const [searchQuery, setSearchQuery] = useState('');
  const [statusFilter, setStatusFilter] = useState<'all' | 'active' | 'expired' | 'terminated'>('all');

  const loadHistory = useCallback(async () => {
    setLoading(true);
    setError(null);

    try {
      const response = await impersonationApi.getHistory(50);
      if (response.success && response.data) {
        let filteredSessions = response.data;
        
        // Apply search filter
        if (searchQuery.trim()) {
          const query = searchQuery.toLowerCase();
          filteredSessions = filteredSessions.filter(session =>
            session.impersonator.email.toLowerCase().includes(query) ||
            session.impersonated_user.email.toLowerCase().includes(query) ||
            session.impersonator.full_name.toLowerCase().includes(query) ||
            session.impersonated_user.full_name.toLowerCase().includes(query)
          );
        }
        
        // Apply status filter
        if (statusFilter !== 'all') {
          filteredSessions = filteredSessions.filter(session => {
            if (statusFilter === 'active') return session.active && !session.expired;
            if (statusFilter === 'expired') return session.expired;
            if (statusFilter === 'terminated') return !session.active && !session.expired;
            return true;
          });
        }
        
        setSessions(filteredSessions);
      } else {
        throw new Error(response.error || 'Failed to load history');
      }
    } catch (error: unknown) {
      const message = error instanceof Error ? error.message : 'Failed to load impersonation history';
      setError(message);
    } finally {
      setLoading(false);
    }
  }, [searchQuery, statusFilter]);

  useEffect(() => {
    loadHistory();
  }, [loadHistory]);

  const handleSearch = () => {
    loadHistory();
  };

  const getStatusColor = (session: ImpersonationSession): string => {
    if (session.active && !session.expired) {
      return 'bg-theme-success-background text-theme-success';
    } else if (session.expired) {
      return 'bg-theme-warning-background text-theme-warning';
    } else {
      return 'bg-theme-error-background text-theme-error';
    }
  };

  const getStatusLabel = (session: ImpersonationSession): string => {
    if (session.active && !session.expired) {
      return 'Active';
    } else if (session.expired) {
      return 'Expired';
    } else {
      return 'Ended';
    }
  };

  const formatDuration = (session: ImpersonationSession): string => {
    if (session.duration) {
      const minutes = Math.floor(session.duration / 60);
      const hours = Math.floor(minutes / 60);
      
      if (hours > 0) {
        return `${hours}h ${minutes % 60}m`;
      }
      return `${minutes}m`;
    }

    // Calculate duration from timestamps
    const start = new Date(session.started_at);
    const end = session.ended_at ? new Date(session.ended_at) : new Date();
    const durationMs = end.getTime() - start.getTime();
    const minutes = Math.floor(durationMs / (1000 * 60));
    const hours = Math.floor(minutes / 60);
    
    if (hours > 0) {
      return `${hours}h ${minutes % 60}m`;
    }
    return `${minutes}m`;
  };

  return (
    <div className="bg-theme-surface shadow-sm rounded-lg">
      <div className="px-6 py-4 border-b border-theme">
        <h3 className="text-lg font-medium text-theme-primary">Impersonation History</h3>
        <p className="mt-1 text-sm text-theme-secondary">
          Track all user impersonation sessions and activities
        </p>
      </div>

      <div className="p-6">
        {/* Filters */}
        <div className="mb-6 flex flex-col sm:flex-row gap-4">
          <div className="flex-1">
            <FormField
              label=""
              placeholder="Search by user email or name..."
              value={searchQuery}
              onChange={(value) => setSearchQuery(value)}
            />
          </div>
          <div className="flex space-x-2">
            <select
              value={statusFilter}
              onChange={(e) => setStatusFilter(e.target.value as 'all' | 'active' | 'expired' | 'terminated')}
              className="bg-theme-surface text-theme-primary border border-theme rounded-md shadow-sm px-3 py-2 focus:ring-theme-interactive-primary focus:border-theme-focus"
            >
              <option value="all">All Status</option>
              <option value="active">Active</option>
              <option value="expired">Expired</option>
              <option value="terminated">Terminated</option>
            </select>
            <Button onClick={handleSearch} loading={loading}>
              Search
            </Button>
          </div>
        </div>

        {error && (
          <div className="mb-6 p-4 bg-theme-error-background border border-theme-error rounded-md">
            <p className="text-sm text-theme-error">{error}</p>
          </div>
        )}

        {/* History Table */}
        {loading ? (
          <div className="flex justify-center items-center py-12">
            <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-interactive-primary"></div>
            <span className="ml-2 text-theme-secondary">Loading history...</span>
          </div>
        ) : sessions.length === 0 ? (
          <div className="text-center py-12">
            <svg className="mx-auto h-12 w-12 text-theme-tertiary" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
            </svg>
            <h3 className="mt-2 text-sm font-medium text-theme-primary">No impersonation history</h3>
            <p className="mt-1 text-sm text-theme-secondary">
              No impersonation sessions found matching your criteria.
            </p>
          </div>
        ) : (
          <>
            <div className="overflow-x-auto">
              <table className="min-w-full divide-y divide-theme">
                <thead className="bg-theme-background-secondary">
                  <tr>
                    <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                      Impersonator
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                      Target User
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                      Status
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                      Started
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                      Duration
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                      Reason
                    </th>
                  </tr>
                </thead>
                <tbody className="bg-theme-surface divide-y divide-theme">
                  {sessions.map((session) => (
                    <tr key={session.id} className="hover:bg-theme-surface-hover">
                      <td className="px-6 py-4 whitespace-nowrap">
                        <div>
                          <div className="text-sm font-medium text-theme-primary">
                            {session.impersonator.full_name}
                          </div>
                          <div className="text-sm text-theme-secondary">
                            {session.impersonator.email}
                          </div>
                        </div>
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap">
                        <div>
                          <div className="text-sm font-medium text-theme-primary">
                            {session.impersonated_user.full_name}
                          </div>
                          <div className="text-sm text-theme-secondary">
                            {session.impersonated_user.email}
                          </div>
                        </div>
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap">
                        <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${getStatusColor(session)}`}>
                          {getStatusLabel(session)}
                        </span>
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-primary">
                        {new Date(session.started_at).toLocaleString()}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-primary">
                        {formatDuration(session)}
                      </td>
                      <td className="px-6 py-4 text-sm text-theme-primary max-w-xs truncate">
                        {session.reason || 'No reason provided'}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <div className="mt-6 flex items-center justify-between">
              <div className="text-sm text-theme-secondary">
                Showing {sessions.length} sessions
              </div>
              <Button onClick={loadHistory} variant="secondary">
                Refresh
              </Button>
            </div>
          </>
        )}
      </div>
    </div>
  );
};


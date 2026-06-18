import React, { useState, useCallback, useEffect, useMemo } from 'react';
import {
  Search, ChevronRight, ArrowDown, ArrowUp,
  Users, Eye, Pencil, Play, Trash2, MoreHorizontal, Loader2,
} from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { DropdownMenu } from '@/shared/components/ui/DropdownMenu';
import { useTeamModal } from '@/shared/hooks/useTeamModal';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { teamsApi } from '@/shared/services/ai/TeamsApiService';
import type { Team } from '@/shared/services/ai/TeamsApiService';
import { TeamExpandedRow } from './TeamExpandedRow';
import {
  STATUS_CONFIG, STATUS_TABS, TAB_STATUS_MAP,
  TOPOLOGY_LABELS, SORT_OPTIONS, timeAgo,
} from '../constants/teamConstants';
import type { StatusTabId } from '../constants/teamConstants';
import { cn } from '@/shared/utils/cn';

interface TeamsIndexTableProps {
  onStartExecution: (team: Team) => void;
  onEditTeam?: (team: Team) => void;
  onDeleteTeam: (teamId: string) => void;
  refreshKey?: number;
}

export const TeamsIndexTable: React.FC<TeamsIndexTableProps> = ({
  onStartExecution,
  onEditTeam,
  onDeleteTeam,
  refreshKey: externalRefreshKey,
}) => {
  const [teams, setTeams] = useState<Team[]>([]);
  const [loading, setLoading] = useState(true);
  const [expandedRows, setExpandedRows] = useState<Set<string>>(new Set());
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<StatusTabId>('all');
  const [sortBy, setSortBy] = useState('updated_at');
  const [sortOrder, setSortOrder] = useState<'asc' | 'desc'>('desc');

  const { openTeam } = useTeamModal();
  const { hasPermission } = usePermissions();

  const canManage = hasPermission('ai.agents.manage');

  // --- Data fetching ---

  const loadTeams = useCallback(async () => {
    try {
      setLoading(true);
      const response = await teamsApi.listTeams();
      setTeams(response.teams || []);
    } catch {
      // Silently fail — table will show empty state
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadTeams();
  }, [loadTeams]);

  useEffect(() => {
    if (externalRefreshKey && externalRefreshKey > 0) loadTeams();
  }, [externalRefreshKey, loadTeams]);

  // --- Filtering ---

  const filteredTeams = useMemo(() => {
    let filtered = teams;
    const statuses = TAB_STATUS_MAP[statusFilter];
    if (statuses) {
      filtered = filtered.filter(t => statuses.includes(t.status));
    }
    if (search.trim()) {
      const q = search.toLowerCase();
      filtered = filtered.filter(t =>
        t.name.toLowerCase().includes(q) ||
        (t.description && t.description.toLowerCase().includes(q))
      );
    }
    return filtered;
  }, [teams, statusFilter, search]);

  // --- Handlers ---

  const toggleExpand = useCallback((id: string) => {
    setExpandedRows(prev => {
      const next = new Set(prev);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      return next;
    });
  }, []);

  const handleSortClick = useCallback((key: string) => {
    if (sortBy === key) {
      setSortOrder(prev => (prev === 'desc' ? 'asc' : 'desc'));
    } else {
      setSortBy(key);
      setSortOrder('desc');
    }
  }, [sortBy]);

  // --- Render ---

  return (
    <div>
      {/* Filter toolbar */}
      <div className="flex items-center gap-3 mb-4 flex-wrap">
        {/* Search input */}
        <div className="relative flex-1 min-w-[200px] max-w-sm">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-theme-tertiary" />
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search teams..."
            className="w-full pl-9 pr-3 py-2 text-sm bg-theme-background border border-theme rounded-lg text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-1 focus:ring-theme-accent"
          />
        </div>

        {/* Status filter pills */}
        <div className="flex gap-1">
          {STATUS_TABS.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setStatusFilter(tab.id)}
              className={cn(
                'px-3 py-1.5 text-xs font-medium rounded-md transition-colors',
                statusFilter === tab.id
                  ? 'bg-theme-interactive-primary/10 text-theme-info-fg border border-theme-info-border/30'
                  : 'text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover border border-transparent'
              )}
            >
              {tab.label}
            </button>
          ))}
        </div>

        {/* Sort pills */}
        <div className="flex gap-1">
          {SORT_OPTIONS.map((opt) => (
            <button
              key={opt.key}
              onClick={() => handleSortClick(opt.key)}
              className={cn(
                'inline-flex items-center gap-0.5 px-2 py-1.5 text-xs font-medium rounded-md transition-colors',
                sortBy === opt.key
                  ? 'bg-theme-interactive-primary/10 text-theme-info-fg border border-theme-info-border/30'
                  : 'text-theme-tertiary hover:text-theme-secondary hover:bg-theme-surface-hover border border-transparent'
              )}
            >
              {opt.label}
              {sortBy === opt.key && (
                sortOrder === 'desc'
                  ? <ArrowDown className="h-3 w-3" />
                  : <ArrowUp className="h-3 w-3" />
              )}
            </button>
          ))}
        </div>
      </div>

      {/* Table */}
      <div className="bg-theme-surface border border-theme rounded-lg overflow-hidden">
        <table className="min-w-full divide-y divide-theme">
          <thead className="bg-theme-background">
            <tr>
              <th className="w-10 px-3 py-3" />
              <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">Name</th>
              <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">Status</th>
              <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">Topology</th>
              <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">Composition</th>
              <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">Created</th>
              <th className="w-36 px-3 py-3" />
            </tr>
          </thead>
          <tbody className="divide-y divide-theme">
            {filteredTeams.map((team) => (
              <React.Fragment key={team.id}>
                {/* Main row */}
                <tr
                  className={cn(
                    'hover:bg-theme-surface-hover transition-colors cursor-pointer',
                    expandedRows.has(team.id) && 'bg-theme-surface-hover'
                  )}
                  onClick={() => toggleExpand(team.id)}
                >
                  <td className="px-3 py-3">
                    <div className={cn(
                      'transition-transform duration-200',
                      expandedRows.has(team.id) && 'rotate-90'
                    )}>
                      <ChevronRight className={cn(
                        'h-4 w-4',
                        expandedRows.has(team.id) ? 'text-theme-info-fg' : 'text-theme-tertiary'
                      )} />
                    </div>
                  </td>
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-2">
                      <span className={cn('w-2 h-2 rounded-full flex-shrink-0', STATUS_CONFIG[team.status]?.dot || 'bg-theme-surface')} />
                      <div className="min-w-0">
                        <div className="text-sm font-medium text-theme-primary truncate">{team.name}</div>
                        {team.description && (
                          <div className="text-xs text-theme-tertiary truncate max-w-xs">{team.description}</div>
                        )}
                      </div>
                    </div>
                  </td>
                  <td className="px-4 py-3">
                    <Badge variant={STATUS_CONFIG[team.status]?.variant || 'outline'} size="sm">
                      {STATUS_CONFIG[team.status]?.label || team.status}
                    </Badge>
                  </td>
                  <td className="px-4 py-3">
                    <span className="text-sm text-theme-secondary">
                      {TOPOLOGY_LABELS[team.team_topology] || team.team_topology}
                    </span>
                  </td>
                  <td className="px-4 py-3">
                    <span className="text-sm text-theme-tertiary">
                      {team.roles_count ?? 0} roles {'\u00b7'} {team.channels_count ?? 0} ch
                    </span>
                  </td>
                  <td className="px-4 py-3">
                    <span className="text-sm text-theme-tertiary">{timeAgo(team.created_at)}</span>
                  </td>
                  <td className="px-3 py-3">
                    <div className="flex items-center gap-0.5" onClick={(e) => e.stopPropagation()}>
                      <Button variant="ghost" size="sm" iconOnly onClick={() => openTeam(team.id)} title="View details">
                        <Eye className="h-3.5 w-3.5" />
                      </Button>
                      <Button variant="ghost" size="sm" iconOnly onClick={() => onStartExecution(team)} title="Execute">
                        <Play className="h-3.5 w-3.5" />
                      </Button>
                      {canManage && (
                        <>
                          {onEditTeam && (
                            <Button variant="ghost" size="sm" iconOnly onClick={() => onEditTeam(team)} title="Edit">
                              <Pencil className="h-3.5 w-3.5" />
                            </Button>
                          )}
                          <DropdownMenu
                            trigger={
                              <Button variant="ghost" size="sm" iconOnly title="More actions">
                                <MoreHorizontal className="h-3.5 w-3.5" />
                              </Button>
                            }
                            items={[
                              { icon: Trash2, label: 'Delete', onClick: () => onDeleteTeam(team.id), danger: true },
                            ]}
                            align="right"
                            width="w-36"
                          />
                        </>
                      )}
                    </div>
                  </td>
                </tr>

                {/* Expanded row */}
                {expandedRows.has(team.id) && (
                  <TeamExpandedRow team={team} />
                )}
              </React.Fragment>
            ))}
          </tbody>
        </table>

        {/* Empty state */}
        {!loading && filteredTeams.length === 0 && (
          <div className="flex flex-col items-center justify-center py-12 px-4">
            <Users className="w-10 h-10 text-theme-tertiary mb-3" />
            <p className="text-sm text-theme-tertiary">{search ? 'No matching teams' : 'No teams found'}</p>
          </div>
        )}

        {/* Loading state */}
        {loading && teams.length === 0 && (
          <div className="flex items-center justify-center py-12">
            <Loader2 className="w-6 h-6 text-theme-secondary animate-spin" />
          </div>
        )}
      </div>

      {/* Footer */}
      {teams.length > 0 && (
        <div className="flex items-center justify-between mt-3 text-xs text-theme-tertiary">
          <span>Showing {filteredTeams.length} of {teams.length} teams</span>
          <span>{teams.filter(t => t.status === 'active').length} active</span>
        </div>
      )}
    </div>
  );
};

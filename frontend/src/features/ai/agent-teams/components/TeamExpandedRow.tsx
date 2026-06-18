import React from 'react';
import { Network, Settings, MessageSquare, Cpu, Clock, Users, Hash } from 'lucide-react';
import { TOPOLOGY_LABELS, timeAgo } from '../constants/teamConstants';
import type { Team } from '@/shared/services/ai/TeamsApiService';

interface TeamExpandedRowProps {
  team: Team;
}

export const TeamExpandedRow: React.FC<TeamExpandedRowProps> = ({ team }) => {
  return (
    <tr>
      <td colSpan={7} className="p-0">
        <div className="border-l-2 border-theme-info-border mx-4 my-3 ml-6 pl-5 pr-2">
          {/* Description */}
          {team.description && (
            <p className="text-sm text-theme-secondary mb-4 max-w-3xl">
              {team.description}
            </p>
          )}

          <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
            {/* Column 1: Configuration */}
            <div className="space-y-3">
              <h4 className="text-xs font-semibold text-theme-secondary uppercase tracking-wide">Configuration</h4>
              <div className="space-y-2">
                <DetailRow
                  icon={Network}
                  label="Topology"
                  value={TOPOLOGY_LABELS[team.team_topology] || team.team_topology}
                />
                <DetailRow
                  icon={Settings}
                  label="Coordination"
                  value={team.coordination_strategy}
                />
                <DetailRow
                  icon={MessageSquare}
                  label="Communication"
                  value={team.communication_pattern}
                />
                <DetailRow
                  icon={Cpu}
                  label="Max Parallel"
                  value={String(team.max_parallel_tasks)}
                />
                {team.goal_description && (
                  <DetailRow
                    icon={Hash}
                    label="Goal"
                    value={team.goal_description}
                  />
                )}
              </div>
            </div>

            {/* Column 2: Composition */}
            <div className="space-y-3">
              <h4 className="text-xs font-semibold text-theme-secondary uppercase tracking-wide">Composition</h4>
              <div className="space-y-2">
                <DetailRow
                  icon={Users}
                  label="Roles"
                  value={String(team.roles_count ?? 0)}
                />
                <DetailRow
                  icon={MessageSquare}
                  label="Channels"
                  value={String(team.channels_count ?? 0)}
                />
              </div>
            </div>

            {/* Column 3: Metadata */}
            <div className="space-y-3">
              <h4 className="text-xs font-semibold text-theme-secondary uppercase tracking-wide">Metadata</h4>
              <div className="space-y-2">
                <DetailRow
                  icon={Settings}
                  label="Type"
                  value={team.team_type}
                />
                <DetailRow
                  icon={Clock}
                  label="Created"
                  value={timeAgo(team.created_at)}
                />
                {team.task_timeout_seconds != null && (
                  <DetailRow
                    icon={Clock}
                    label="Task Timeout"
                    value={`${team.task_timeout_seconds}s`}
                  />
                )}
              </div>
            </div>
          </div>
        </div>
      </td>
    </tr>
  );
};

function DetailRow({ icon: Icon, label, value }: { icon: React.ElementType; label: string; value: string }) {
  return (
    <div className="flex items-center gap-2 text-xs">
      <Icon className="h-3.5 w-3.5 text-theme-tertiary flex-shrink-0" />
      <span className="text-theme-secondary">{label}:</span>
      <span className="text-theme-primary font-medium truncate">{value}</span>
    </div>
  );
}

import React, { useState, useEffect } from 'react';
import { Loader2, Users, ExternalLink } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { agentTeamsApi } from '@/features/ai/agent-teams/services/agentTeamsApi';

interface AgentTeamsTabProps {
  agentId: string;
}

interface TeamMembership {
  id: string;
  name: string;
  team_type?: string;
  status?: string;
  role?: string;
}

export const AgentTeamsTab: React.FC<AgentTeamsTabProps> = ({ agentId }) => {
  const [teams, setTeams] = useState<TeamMembership[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;

    async function load() {
      try {
        setLoading(true);
        // getTeams returns AgentTeam[] directly
        const allTeams = await agentTeamsApi.getTeams();

        // Filter teams that contain this agent as a member
        const memberTeams = allTeams.filter((team) =>
          team.members?.some((m) => m.agent_id === agentId)
        );

        if (!cancelled) {
          setTeams(memberTeams.map((team) => {
            const member = team.members?.find((m) => m.agent_id === agentId);
            return {
              id: team.id,
              name: team.name,
              team_type: team.team_type,
              status: team.status,
              role: member?.role,
            };
          }));
        }
      } catch {
        // Silently fail
      } finally {
        if (!cancelled) setLoading(false);
      }
    }

    load();
    return () => { cancelled = true; };
  }, [agentId]);

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <Loader2 className="w-5 h-5 text-theme-secondary animate-spin" />
      </div>
    );
  }

  if (teams.length === 0) {
    return (
      <div className="text-center py-12">
        <Users className="w-10 h-10 text-theme-tertiary mx-auto mb-3" />
        <p className="text-sm text-theme-secondary">This agent is not a member of any teams</p>
      </div>
    );
  }

  return (
    <div className="space-y-2">
      {teams.map((team) => (
        <div
          key={team.id}
          className="flex items-center justify-between px-4 py-3 border border-theme rounded-lg bg-theme-surface hover:bg-theme-surface-hover transition-colors"
        >
          <div className="flex items-center gap-3 min-w-0">
            <Users className="w-4 h-4 text-theme-secondary flex-shrink-0" />
            <div className="min-w-0">
              <span className="text-sm font-medium text-theme-primary truncate block">{team.name}</span>
              {team.role && (
                <span className="text-xs text-theme-tertiary">Role: {team.role}</span>
              )}
            </div>
          </div>
          <div className="flex items-center gap-2 flex-shrink-0">
            {team.team_type && (
              <Badge variant="outline" size="xs">{team.team_type}</Badge>
            )}
            <a
              href="/app/ai/agents?tab=teams"
              className="p-1 text-theme-tertiary hover:text-theme-primary transition-colors"
              title="View Teams"
            >
              <ExternalLink className="w-3.5 h-3.5" />
            </a>
          </div>
        </div>
      ))}
    </div>
  );
};

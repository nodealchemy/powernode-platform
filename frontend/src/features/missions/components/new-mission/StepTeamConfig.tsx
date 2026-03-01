import React, { useEffect, useState } from 'react';
import { Users, Loader2 } from 'lucide-react';
import { agentTeamsApi, AgentTeam } from '@/features/ai/agent-teams/services/agentTeamsApi';

interface StepTeamConfigProps {
  teamId: string;
  onTeamIdChange: (v: string) => void;
}

export const StepTeamConfig: React.FC<StepTeamConfigProps> = ({
  teamId,
  onTeamIdChange,
}) => {
  const [teams, setTeams] = useState<AgentTeam[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    const loadTeams = async () => {
      try {
        const data = await agentTeamsApi.getTeams({});
        if (!cancelled) setTeams(data);
      } catch {
        // Teams are optional — silently fall back to empty list
      } finally {
        if (!cancelled) setLoading(false);
      }
    };
    loadTeams();
    return () => { cancelled = true; };
  }, []);

  return (
    <div className="space-y-5">
      <div className="flex items-center gap-3 p-4 bg-theme-surface rounded-lg">
        <Users className="w-5 h-5 text-theme-accent flex-shrink-0" />
        <div>
          <p className="text-sm font-medium text-theme-primary">Agent Team</p>
          <p className="text-xs text-theme-tertiary">
            Optionally assign an existing AI team to handle this mission. If left empty, the default team will be used.
          </p>
        </div>
      </div>

      <div>
        <label className="block text-sm font-medium text-theme-primary mb-1.5">
          Team <span className="text-xs text-theme-tertiary">(optional)</span>
        </label>
        {loading ? (
          <div className="flex items-center gap-2 text-sm text-theme-tertiary py-2">
            <Loader2 className="w-4 h-4 animate-spin" />
            Loading teams...
          </div>
        ) : (
          <select
            value={teamId}
            onChange={(e) => onTeamIdChange(e.target.value)}
            className="input-theme w-full"
          >
            <option value="">No team (use default)</option>
            {teams.map((team) => (
              <option key={team.id} value={team.id}>
                {team.name}{team.team_type ? ` (${team.team_type})` : ''}
              </option>
            ))}
          </select>
        )}
        <p className="text-xs text-theme-tertiary mt-1">
          Select a team from the AI Teams section, or leave empty to use the default.
        </p>
      </div>
    </div>
  );
};

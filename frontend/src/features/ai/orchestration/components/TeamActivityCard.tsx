import React, { useState, useEffect, useCallback } from 'react';
import { Users, Activity, ArrowRight } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { agentTeamsApi } from '@/features/ai/agent-teams/services/agentTeamsApi';
import type { AgentTeam } from '@/features/ai/agent-teams/services/agentTeamsApi';

export const TeamActivityCard: React.FC = () => {
  const navigate = useNavigate();
  const [teams, setTeams] = useState<AgentTeam[]>([]);
  const [loading, setLoading] = useState(true);

  const loadTeams = useCallback(async () => {
    try {
      const data = await agentTeamsApi.getTeams({ status: 'active' });
      setTeams(data);
    } catch {
      // Silently handle
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadTeams();
    const interval = setInterval(loadTeams, 30000);
    return () => clearInterval(interval);
  }, [loadTeams]);

  const activeTeams = teams.filter(t => t.status === 'active');
  const totalMembers = teams.reduce((acc, t) => acc + (t.member_count || 0), 0);

  return (
    <div
      className="card-theme p-6 hover:shadow-lg transition-all cursor-pointer"
      onClick={() => navigate('/app/ai/agent-teams')}
    >
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-3">
          <div className="p-2 bg-theme-info/10 rounded-lg">
            <Users className="h-5 w-5 text-theme-info" />
          </div>
          <div>
            <div className="text-2xl font-bold text-theme-primary">{activeTeams.length}</div>
            <div className="text-sm text-theme-secondary">Active Teams</div>
          </div>
        </div>
        <ArrowRight className="h-4 w-4 text-theme-muted" />
      </div>

      <div className="space-y-2">
        <div className="flex items-center justify-between text-sm">
          <span className="text-theme-secondary">Total Members</span>
          <span className="font-medium text-theme-primary">{totalMembers}</span>
        </div>

        {/* Active teams mini-list */}
        {!loading && activeTeams.slice(0, 3).map(team => (
          <div key={team.id} className="flex items-center justify-between text-xs">
            <div className="flex items-center gap-2 truncate">
              <Activity className="h-3 w-3 text-theme-success flex-shrink-0" />
              <span className="text-theme-primary truncate">{team.name}</span>
            </div>
            <span className="text-theme-secondary flex-shrink-0">
              {team.member_count} agent{team.member_count !== 1 ? 's' : ''}
            </span>
          </div>
        ))}

        {!loading && activeTeams.length > 3 && (
          <div className="text-xs text-theme-secondary text-center pt-1">
            +{activeTeams.length - 3} more teams
          </div>
        )}
      </div>
    </div>
  );
};

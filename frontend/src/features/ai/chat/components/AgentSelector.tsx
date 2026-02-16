import React, { useState, useEffect, useMemo, useRef } from 'react';
import { Bot, ChevronDown, Search, Users } from 'lucide-react';
import apiClient from '@/shared/services/apiClient';

interface Agent {
  id: string;
  name: string;
  agent_type: string;
  status: string;
}

interface AgentTeam {
  id: string;
  name: string;
  team_type: string;
  status: string;
  member_count?: number;
}

type SelectorTab = 'agents' | 'teams';

interface AgentSelectorProps {
  selectedAgentId?: string;
  onSelect: (agentId: string) => void;
  onSelectTeam?: (teamId: string) => void;
}

export const AgentSelector: React.FC<AgentSelectorProps> = ({ selectedAgentId, onSelect, onSelectTeam }) => {
  const [agents, setAgents] = useState<Agent[]>([]);
  const [teams, setTeams] = useState<AgentTeam[]>([]);
  const [isOpen, setIsOpen] = useState(false);
  const [loading, setLoading] = useState(true);
  const [loadingTeams, setLoadingTeams] = useState(false);
  const [search, setSearch] = useState('');
  const [activeTab, setActiveTab] = useState<SelectorTab>('agents');
  const [selectedTeamId, setSelectedTeamId] = useState<string | undefined>();
  const searchRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const fetchAgents = async () => {
      try {
        const response = await apiClient.get('/ai/agents', { params: { status: 'active' } });
        const items = response.data?.data?.items || response.data?.data || [];
        setAgents(Array.isArray(items) ? items : []);
      } catch {
        // Silently handle error
      } finally {
        setLoading(false);
      }
    };
    fetchAgents();
  }, []);

  useEffect(() => {
    if (activeTab === 'teams' && teams.length === 0 && !loadingTeams) {
      setLoadingTeams(true);
      const fetchTeams = async () => {
        try {
          const response = await apiClient.get('/ai/agent_teams', { params: { status: 'active' } });
          const items = response.data?.data?.items || response.data?.data || [];
          setTeams(Array.isArray(items) ? items : []);
        } catch {
          // Silently handle error
        } finally {
          setLoadingTeams(false);
        }
      };
      fetchTeams();
    }
  }, [activeTab, teams.length, loadingTeams]);

  useEffect(() => {
    if (isOpen) {
      setSearch('');
      setTimeout(() => searchRef.current?.focus(), 0);
    }
  }, [isOpen]);

  const filteredAgents = useMemo(() => {
    if (!search.trim()) return agents;
    const q = search.toLowerCase();
    return agents.filter(a => a.name.toLowerCase().includes(q) || a.agent_type.toLowerCase().includes(q));
  }, [agents, search]);

  const filteredTeams = useMemo(() => {
    if (!search.trim()) return teams;
    const q = search.toLowerCase();
    return teams.filter(t => t.name.toLowerCase().includes(q) || t.team_type.toLowerCase().includes(q));
  }, [teams, search]);

  const selectedAgent = agents.find(a => a.id === selectedAgentId);
  const selectedTeam = teams.find(t => t.id === selectedTeamId);
  const displayName = selectedTeam?.name || selectedAgent?.name;

  const handleTeamSelect = (teamId: string) => {
    setSelectedTeamId(teamId);
    onSelectTeam?.(teamId);
    setIsOpen(false);
  };

  return (
    <div className="relative">
      <button
        type="button"
        onClick={() => setIsOpen(!isOpen)}
        className="w-full flex items-center justify-between gap-2 px-3 py-2 text-sm border border-theme rounded-lg bg-theme-surface text-theme-primary hover:bg-theme-surface-hover transition-colors"
      >
        <div className="flex items-center gap-2 truncate">
          {selectedTeamId ? (
            <Users className="h-4 w-4 text-theme-interactive-primary flex-shrink-0" />
          ) : (
            <Bot className="h-4 w-4 text-theme-info flex-shrink-0" />
          )}
          <span className="truncate">
            {loading ? 'Loading...' : displayName || 'Select an agent'}
          </span>
        </div>
        <ChevronDown className={`h-4 w-4 text-theme-secondary flex-shrink-0 transition-transform ${isOpen ? 'rotate-180' : ''}`} />
      </button>

      {isOpen && (
        <div className="absolute bottom-full left-0 right-0 mb-1 bg-theme-surface border border-theme rounded-lg shadow-lg z-50 flex flex-col max-h-80">
          {/* Tab toggle */}
          {onSelectTeam && (
            <div className="flex border-b border-theme flex-shrink-0">
              <button
                type="button"
                onClick={() => setActiveTab('agents')}
                className={`flex-1 flex items-center justify-center gap-1.5 px-3 py-2 text-xs font-medium transition-colors ${
                  activeTab === 'agents'
                    ? 'text-theme-interactive-primary border-b-2 border-theme-interactive-primary'
                    : 'text-theme-secondary hover:text-theme-primary'
                }`}
              >
                <Bot className="h-3.5 w-3.5" />
                Agents
              </button>
              <button
                type="button"
                onClick={() => setActiveTab('teams')}
                className={`flex-1 flex items-center justify-center gap-1.5 px-3 py-2 text-xs font-medium transition-colors ${
                  activeTab === 'teams'
                    ? 'text-theme-interactive-primary border-b-2 border-theme-interactive-primary'
                    : 'text-theme-secondary hover:text-theme-primary'
                }`}
              >
                <Users className="h-3.5 w-3.5" />
                Teams
              </button>
            </div>
          )}

          {/* Search */}
          <div className="p-2 border-b border-theme flex-shrink-0">
            <div className="relative">
              <Search className="absolute left-2 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-theme-secondary" />
              <input
                ref={searchRef}
                type="text"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder={activeTab === 'agents' ? 'Search agents...' : 'Search teams...'}
                className="w-full pl-7 pr-2 py-1.5 text-sm bg-theme-background border border-theme rounded-md text-theme-primary placeholder:text-theme-secondary focus:outline-none focus:ring-1 focus:ring-theme-primary"
              />
            </div>
          </div>

          {/* List */}
          <div className="overflow-y-auto">
            {activeTab === 'agents' ? (
              filteredAgents.length === 0 ? (
                <div className="px-3 py-2 text-sm text-theme-secondary">
                  {agents.length === 0 ? 'No active agents' : 'No matches'}
                </div>
              ) : (
                filteredAgents.map(agent => (
                  <button
                    key={agent.id}
                    type="button"
                    onClick={() => {
                      setSelectedTeamId(undefined);
                      onSelect(agent.id);
                      setIsOpen(false);
                    }}
                    className={`w-full flex items-center gap-2 px-3 py-2 text-sm text-left hover:bg-theme-surface-hover transition-colors ${
                      agent.id === selectedAgentId && !selectedTeamId ? 'bg-theme-primary/10 text-theme-primary' : 'text-theme-primary'
                    }`}
                  >
                    <div className="h-2 w-2 rounded-full bg-theme-success flex-shrink-0" />
                    <span className="truncate">{agent.name}</span>
                    <span className="text-xs text-theme-secondary ml-auto flex-shrink-0">{agent.agent_type}</span>
                  </button>
                ))
              )
            ) : (
              loadingTeams ? (
                <div className="px-3 py-2 text-sm text-theme-secondary">Loading teams...</div>
              ) : filteredTeams.length === 0 ? (
                <div className="px-3 py-2 text-sm text-theme-secondary">
                  {teams.length === 0 ? 'No active teams' : 'No matches'}
                </div>
              ) : (
                filteredTeams.map(team => (
                  <button
                    key={team.id}
                    type="button"
                    onClick={() => handleTeamSelect(team.id)}
                    className={`w-full flex items-center gap-2 px-3 py-2 text-sm text-left hover:bg-theme-surface-hover transition-colors ${
                      team.id === selectedTeamId ? 'bg-theme-primary/10 text-theme-primary' : 'text-theme-primary'
                    }`}
                  >
                    <Users className="h-3.5 w-3.5 text-theme-interactive-primary flex-shrink-0" />
                    <span className="truncate">{team.name}</span>
                    <div className="ml-auto flex items-center gap-1.5 flex-shrink-0">
                      {team.member_count != null && (
                        <span className="text-[10px] text-theme-text-tertiary">
                          {team.member_count} members
                        </span>
                      )}
                      <span className="text-[10px] font-medium px-1.5 py-0.5 rounded bg-theme-surface-secondary text-theme-secondary">
                        {team.team_type}
                      </span>
                    </div>
                  </button>
                ))
              )
            )}
          </div>
        </div>
      )}
    </div>
  );
};

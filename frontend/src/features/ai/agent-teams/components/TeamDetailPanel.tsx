import React, { useState } from 'react';
import { Users, Play, Settings, BookOpen, BarChart3, Wrench } from 'lucide-react';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { TeamOverviewTab } from './TeamOverviewTab';
import { TeamExecutionTab } from './TeamExecutionTab';
import { TeamConfigTab } from './TeamConfigTab';
import { TeamSkillCoverageTab } from './TeamSkillCoverageTab';
import TeamAnalyticsDashboard from './TeamAnalyticsDashboard';
import { ContextBrowser } from '@/features/ai/memory/components/ContextBrowser';
import type {
  Team,
  TeamRole,
  TeamChannel,
  TeamExecution,
  TeamTemplate,
  TeamAnalytics,
} from '@/shared/services/ai/TeamsApiService';

interface TeamDetailPanelProps {
  team: Team | null;
  roles: TeamRole[];
  channels: TeamChannel[];
  executions: TeamExecution[];
  templates: TeamTemplate[];
  teamAnalytics: TeamAnalytics | null;
  onDeleteTeam: (teamId: string) => void;
  onStartExecution: () => void;
  onExecutionAction: (executionId: string, action: 'pause' | 'resume' | 'cancel') => void;
  onPublishTemplate: (templateId: string) => void;
  onPeriodChange: (days: number) => void;
  loading?: boolean;
}

const tabs = [
  { id: 'overview', label: 'Overview', icon: <Users size={16} /> },
  { id: 'execution', label: 'Execution', icon: <Play size={16} /> },
  { id: 'skills', label: 'Skills', icon: <Wrench size={16} /> },
  { id: 'configuration', label: 'Configuration', icon: <Settings size={16} /> },
  { id: 'knowledge', label: 'Knowledge', icon: <BookOpen size={16} /> },
  { id: 'analytics', label: 'Analytics', icon: <BarChart3 size={16} /> },
];

export const TeamDetailPanel: React.FC<TeamDetailPanelProps> = ({
  team,
  roles,
  channels,
  executions,
  templates,
  teamAnalytics,
  onDeleteTeam,
  onStartExecution,
  onExecutionAction,
  onPublishTemplate,
  onPeriodChange,
  loading,
}) => {
  const [activeTab, setActiveTab] = useState('overview');

  if (!team) {
    return (
      <div className="flex-1 flex items-center justify-center bg-theme-bg">
        <div className="text-center">
          <Users size={48} className="mx-auto text-theme-secondary mb-4" />
          <h3 className="text-lg font-semibold text-theme-primary mb-2">No team selected</h3>
          <p className="text-sm text-theme-secondary">Select a team from the list to view details</p>
        </div>
      </div>
    );
  }

  if (loading) {
    return (
      <div className="flex-1 flex items-center justify-center">
        <div className="text-center">
          <div className="inline-block animate-spin rounded-full h-8 w-8 border-4 border-theme-focus border-t-transparent" />
          <p className="mt-4 text-theme-secondary">Loading team data...</p>
        </div>
      </div>
    );
  }

  const agentRoles = roles.filter(r => r.agent_id);

  return (
    <div className="flex-1 min-w-0 overflow-y-auto p-6">
      <TabContainer
        tabs={tabs}
        activeTab={activeTab}
        onTabChange={setActiveTab}
        variant="underline"
        size="sm"
        compact
      >
        <TabPanel tabId="overview" activeTab={activeTab}>
          <TeamOverviewTab team={team} roles={roles} onDeleteTeam={onDeleteTeam} />
        </TabPanel>

        <TabPanel tabId="execution" activeTab={activeTab}>
          <TeamExecutionTab
            team={team}
            executions={executions}
            onStartExecution={onStartExecution}
            onExecutionAction={onExecutionAction}
          />
        </TabPanel>

        <TabPanel tabId="skills" activeTab={activeTab}>
          <TeamSkillCoverageTab teamId={team.id} />
        </TabPanel>

        <TabPanel tabId="configuration" activeTab={activeTab}>
          <TeamConfigTab
            roles={roles}
            channels={channels}
            templates={templates}
            onPublishTemplate={onPublishTemplate}
          />
        </TabPanel>

        <TabPanel tabId="knowledge" activeTab={activeTab}>
          <div className="space-y-4">
            <div className="flex items-center gap-2 mb-4">
              <BookOpen size={18} className="text-theme-secondary" />
              <h3 className="text-lg font-medium text-theme-primary">Team Contexts</h3>
              <span className="text-sm text-theme-secondary">Contexts scoped to agents in this team</span>
            </div>
            {agentRoles.length === 0 ? (
              <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
                <BookOpen size={48} className="mx-auto text-theme-secondary mb-4" />
                <h3 className="text-lg font-semibold text-theme-primary mb-2">No agent contexts</h3>
                <p className="text-theme-secondary">Assign agents to team roles to see their knowledge contexts here</p>
              </div>
            ) : (
              <div className="space-y-6">
                {agentRoles.map(role => (
                  <div key={role.id}>
                    <h4 className="text-sm font-medium text-theme-secondary mb-2">
                      {role.agent_name || role.role_name} — {role.role_type}
                    </h4>
                    <ContextBrowser filters={{ ai_agent_id: role.agent_id! }} linkToDetail />
                  </div>
                ))}
              </div>
            )}
          </div>
        </TabPanel>

        <TabPanel tabId="analytics" activeTab={activeTab}>
          {!teamAnalytics ? (
            <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
              <BarChart3 size={48} className="mx-auto text-theme-secondary mb-4" />
              <h3 className="text-lg font-semibold text-theme-primary mb-2">No analytics data</h3>
              <p className="text-theme-secondary">Analytics will appear once the team has completed executions</p>
            </div>
          ) : (
            <TeamAnalyticsDashboard analytics={teamAnalytics} onPeriodChange={onPeriodChange} />
          )}
        </TabPanel>
      </TabContainer>
    </div>
  );
};

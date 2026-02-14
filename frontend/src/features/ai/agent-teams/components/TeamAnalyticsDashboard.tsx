import React, { useState, useMemo } from 'react';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import type { TeamAnalytics } from '@/shared/services/ai/TeamsApiService';
import { PERIOD_OPTIONS } from './teamAnalyticsHelpers';
import { TeamOverviewMetrics } from './TeamOverviewMetrics';
import { ExecutionCharts } from './ExecutionCharts';
import { CostBreakdownChart } from './CostBreakdownChart';
import { AgentUtilizationChart } from './AgentUtilizationChart';
import { PerformanceTrends } from './PerformanceTrends';

interface TeamAnalyticsDashboardProps {
  analytics: TeamAnalytics;
  onPeriodChange: (days: number) => void;
}

const TeamAnalyticsDashboard: React.FC<TeamAnalyticsDashboardProps> = ({ analytics, onPeriodChange }) => {
  const [analyticsTab, setAnalyticsTab] = useState('overview');

  const tabs = useMemo(() => [
    { id: 'overview', label: 'Overview' },
    { id: 'performance', label: 'Performance' },
    { id: 'cost', label: 'Cost' },
    { id: 'agents', label: 'Agents' },
    { id: 'communication', label: 'Communication' },
    { id: 'quality', label: 'Quality' },
  ], []);

  return (
    <div className="space-y-4">
      {/* Period selector */}
      <div className="flex items-center justify-between">
        <div className="flex gap-2">
          {PERIOD_OPTIONS.map(d => (
            <button
              key={d}
              onClick={() => onPeriodChange(d)}
              className={`px-3 py-1.5 text-sm rounded-md transition-colors ${
                analytics.period_days === d
                  ? 'bg-theme-interactive-primary text-white'
                  : 'bg-theme-surface text-theme-secondary hover:text-theme-primary border border-theme'
              }`}
            >
              {d}d
            </button>
          ))}
        </div>
        <span className="text-xs text-theme-secondary">
          Generated {new Date(analytics.generated_at).toLocaleString()}
        </span>
      </div>

      <TabContainer tabs={tabs} activeTab={analyticsTab} onTabChange={setAnalyticsTab} variant="pills" size="sm">
        <TabPanel tabId="overview" activeTab={analyticsTab}>
          <TeamOverviewMetrics overview={analytics.overview} />
        </TabPanel>
        <TabPanel tabId="performance" activeTab={analyticsTab}>
          <ExecutionCharts performance={analytics.performance} />
        </TabPanel>
        <TabPanel tabId="cost" activeTab={analyticsTab}>
          <CostBreakdownChart cost={analytics.cost} />
        </TabPanel>
        <TabPanel tabId="agents" activeTab={analyticsTab}>
          <AgentUtilizationChart agents={analytics.agents} />
        </TabPanel>
        <TabPanel tabId="communication" activeTab={analyticsTab}>
          <PerformanceTrends section="communication" communication={analytics.communication} />
        </TabPanel>
        <TabPanel tabId="quality" activeTab={analyticsTab}>
          <PerformanceTrends section="quality" quality={analytics.quality} />
        </TabPanel>
      </TabContainer>
    </div>
  );
};

export default TeamAnalyticsDashboard;

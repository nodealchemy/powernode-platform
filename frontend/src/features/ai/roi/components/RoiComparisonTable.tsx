import React from 'react';
import { Users, Workflow } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import type { RoiDashboard as DashboardData } from '@/shared/services/ai';

interface RoiComparisonTableProps {
  dashboardData: DashboardData;
  formatCurrency: (amount: number) => string;
}

export const RoiComparisonTable: React.FC<RoiComparisonTableProps> = ({
  dashboardData,
  formatCurrency,
}) => {
  return (
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
      {/* Top Workflows */}
      <Card className="p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
          <Workflow className="h-5 w-5" />
          Top ROI Workflows
        </h3>
        <div className="space-y-3">
          {dashboardData.top_performers.workflows.map((workflow, index) => (
            <div key={workflow.id} className="flex items-center justify-between p-3 bg-theme-surface rounded-lg">
              <div className="flex items-center gap-3">
                <div className={`w-6 h-6 rounded flex items-center justify-center text-white text-xs font-bold ${
                  index === 0 ? 'bg-theme-success' :
                  index === 1 ? 'bg-theme-info' : 'bg-theme-muted'
                }`}>
                  {index + 1}
                </div>
                <div>
                  <p className="font-medium text-theme-primary">{workflow.name}</p>
                  <p className="text-xs text-theme-tertiary">
                    {formatCurrency(workflow.value_generated_usd)} generated
                  </p>
                </div>
              </div>
              <div className="text-right">
                <p className={`font-semibold ${
                  workflow.roi_percentage >= 200 ? 'text-theme-success' : 'text-theme-primary'
                }`}>
                  {workflow.roi_percentage.toFixed(0)}% ROI
                </p>
              </div>
            </div>
          ))}
        </div>
      </Card>

      {/* Top Agents */}
      <Card className="p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
          <Users className="h-5 w-5" />
          Top ROI Agents
        </h3>
        <div className="space-y-3">
          {dashboardData.top_performers.agents.map((agent, index) => (
            <div key={agent.id} className="flex items-center justify-between p-3 bg-theme-surface rounded-lg">
              <div className="flex items-center gap-3">
                <div className={`w-6 h-6 rounded flex items-center justify-center text-white text-xs font-bold ${
                  index === 0 ? 'bg-theme-success' :
                  index === 1 ? 'bg-theme-info' : 'bg-theme-muted'
                }`}>
                  {index + 1}
                </div>
                <div>
                  <p className="font-medium text-theme-primary">{agent.name}</p>
                  <p className="text-xs text-theme-tertiary">
                    {agent.tasks_completed} tasks completed
                  </p>
                </div>
              </div>
              <div className="text-right">
                <p className={`font-semibold ${
                  agent.roi_percentage >= 200 ? 'text-theme-success' : 'text-theme-primary'
                }`}>
                  {agent.roi_percentage.toFixed(0)}% ROI
                </p>
              </div>
            </div>
          ))}
        </div>
      </Card>
    </div>
  );
};

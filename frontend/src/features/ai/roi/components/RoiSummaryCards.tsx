import React from 'react';
import {
  Clock,
  DollarSign,
  Target,
  Zap,
} from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import type { RoiDashboard as DashboardData } from '@/shared/services/ai';

interface RoiSummaryCardsProps {
  dashboardData: DashboardData;
  formatCurrency: (amount: number) => string;
  formatHours: (hours: number) => string;
}

export const RoiSummaryCards: React.FC<RoiSummaryCardsProps> = ({
  dashboardData,
  formatCurrency,
  formatHours,
}) => {
  return (
    <>
      {/* Main ROI Card */}
      <Card className="p-6 mb-6 bg-gradient-to-r from-theme-surface to-theme-background">
        <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
          <div className="text-center">
            <p className="text-sm text-theme-tertiary mb-1">ROI</p>
            <p className={`text-4xl font-bold ${
              dashboardData.summary.roi_percentage >= 100 ? 'text-theme-success' :
              dashboardData.summary.roi_percentage >= 0 ? 'text-theme-warning' : 'text-theme-error'
            }`}>
              {dashboardData.summary.roi_percentage.toFixed(0)}%
            </p>
          </div>
          <div className="text-center">
            <p className="text-sm text-theme-tertiary mb-1">Value Generated</p>
            <p className="text-4xl font-bold text-theme-success">
              {formatCurrency(dashboardData.summary.total_value_generated_usd)}
            </p>
          </div>
          <div className="text-center">
            <p className="text-sm text-theme-tertiary mb-1">AI Cost</p>
            <p className="text-4xl font-bold text-theme-primary">
              {formatCurrency(dashboardData.summary.total_ai_cost_usd)}
            </p>
          </div>
          <div className="text-center">
            <p className="text-sm text-theme-tertiary mb-1">Time Saved</p>
            <p className="text-4xl font-bold text-theme-info">
              {formatHours(dashboardData.summary.total_time_saved_hours)}
            </p>
          </div>
        </div>
      </Card>

      {/* Summary Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <Card className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-theme-tertiary">Tasks Completed</p>
              <p className="text-2xl font-semibold text-theme-primary">
                {dashboardData.summary.tasks_completed.toLocaleString()}
              </p>
            </div>
            <Target className="h-8 w-8 text-theme-info" />
          </div>
        </Card>

        <Card className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-theme-tertiary">Cost per Task</p>
              <p className="text-2xl font-semibold text-theme-primary">
                ${dashboardData.summary.cost_per_task.toFixed(3)}
              </p>
            </div>
            <DollarSign className="h-8 w-8 text-theme-success" />
          </div>
        </Card>

        <Card className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-theme-tertiary">Avg Time Saved/Task</p>
              <p className="text-2xl font-semibold text-theme-primary">
                {(dashboardData.efficiency.avg_time_saved_per_task_hours * 60).toFixed(0)} min
              </p>
            </div>
            <Clock className="h-8 w-8 text-theme-warning" />
          </div>
        </Card>

        <Card className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-theme-tertiary">Automation Rate</p>
              <p className="text-2xl font-semibold text-theme-primary">
                {(dashboardData.efficiency.automation_rate * 100).toFixed(0)}%
              </p>
            </div>
            <Zap className="h-8 w-8 text-theme-info" />
          </div>
        </Card>
      </div>
    </>
  );
};

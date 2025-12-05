import React from 'react';
import { Activity, TrendingUp, AlertCircle, CheckCircle2 } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { ValidationStatisticsDashboard } from '@/features/ai-workflows/components/validation/ValidationStatisticsDashboard';
import { useAuth } from '@/shared/hooks/useAuth';

export const WorkflowValidationStatisticsPage: React.FC = () => {
  const { currentUser } = useAuth();

  // Check permissions
  const canViewWorkflows = currentUser?.permissions?.includes('ai.workflows.read') || false;
  const isAdmin = currentUser?.permissions?.includes('system.admin') || false;

  if (!canViewWorkflows) {
    return (
      <PageContainer
        title="Workflow Validation Statistics"
        description="Platform-wide workflow health and validation metrics"
      >
        <div className="flex items-center justify-center h-64">
          <div className="text-center">
            <AlertCircle className="h-12 w-12 text-theme-error mx-auto mb-4" />
            <h3 className="text-lg font-semibold text-theme-primary mb-2">
              Access Denied
            </h3>
            <p className="text-theme-muted">
              You don't have permission to view validation statistics.
            </p>
          </div>
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title="Workflow Validation Statistics"
      description={
        isAdmin
          ? 'Platform-wide workflow health and validation metrics'
          : 'Your account workflow health and validation metrics'
      }
      breadcrumbs={[
        { label: 'AI', href: '/app/ai' },
        { label: 'Workflows', href: '/app/ai/workflows' },
        { label: 'Validation Statistics' }
      ]}
    >
      <div className="space-y-6">
        {/* Quick Stats Overview */}
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-muted">Total Workflows</p>
                <p className="text-2xl font-semibold text-theme-primary mt-1">--</p>
              </div>
              <Activity className="h-8 w-8 text-theme-info" />
            </div>
          </div>

          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-muted">Average Health</p>
                <p className="text-2xl font-semibold text-theme-success mt-1">--</p>
              </div>
              <TrendingUp className="h-8 w-8 text-theme-success" />
            </div>
          </div>

          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-muted">Valid Workflows</p>
                <p className="text-2xl font-semibold text-theme-success mt-1">--</p>
              </div>
              <CheckCircle2 className="h-8 w-8 text-theme-success" />
            </div>
          </div>

          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-muted">Issues Found</p>
                <p className="text-2xl font-semibold text-theme-warning mt-1">--</p>
              </div>
              <AlertCircle className="h-8 w-8 text-theme-warning" />
            </div>
          </div>
        </div>

        {/* Main Statistics Dashboard */}
        <ValidationStatisticsDashboard />
      </div>
    </PageContainer>
  );
};

export default WorkflowValidationStatisticsPage;

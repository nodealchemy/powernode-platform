import React from 'react';
import {
  Play,
  Copy,
  Trash2,
  Edit,
  Eye,
  CheckCircle,
  Pause,
  Archive,
  Workflow,
  ChevronUp,
  ChevronDown,
  ArrowUpDown,
  FileStack
} from 'lucide-react';
import { DataTable } from '@/shared/components/ui/DataTable';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { AiWorkflow } from '@/shared/types/workflow';

interface WorkflowsTableProps {
  workflows: AiWorkflow[];
  loading: boolean;
  pagination: {
    current_page: number;
    total_pages: number;
    total_count: number;
    per_page: number;
  };
  sortBy: string;
  sortOrder: 'asc' | 'desc';
  canCreateWorkflows: boolean;
  canExecuteWorkflows: boolean;
  canDeleteWorkflows: boolean;
  canUpdateWorkflows: boolean;
  onPageChange: (page: number) => void;
  onSort: (field: string) => void;
  onView: (workflow: AiWorkflow) => void;
  onExecute: (workflow: AiWorkflow) => void;
  onDesign: (workflowId: string) => void;
  onDuplicate: (workflow: AiWorkflow) => void;
  onDelete: (workflow: AiWorkflow) => void;
  onNavigate: (path: string) => void;
  onCreateClick: () => void;
}

const renderSortIndicator = (field: string, sortBy: string, sortOrder: 'asc' | 'desc') => {
  if (sortBy !== field) {
    return <ArrowUpDown className="h-3.5 w-3.5 inline-block ml-1.5 opacity-40 transition-opacity group-hover:opacity-60" />;
  }
  return sortOrder === 'asc' ?
    <ChevronUp className="h-3.5 w-3.5 inline-block ml-1.5 text-theme-interactive-primary transition-colors" /> :
    <ChevronDown className="h-3.5 w-3.5 inline-block ml-1.5 text-theme-interactive-primary transition-colors" />;
};

const renderStatusBadge = (status: string) => {
  const statusConfig = {
    draft: { variant: 'warning' as const, icon: Edit },
    active: { variant: 'success' as const, icon: CheckCircle },
    inactive: { variant: 'secondary' as const, icon: Archive },
    archived: { variant: 'secondary' as const, icon: Archive },
    paused: { variant: 'info' as const, icon: Pause }
  };
  const config = statusConfig[status as keyof typeof statusConfig] || statusConfig.draft;
  const IconComponent = config.icon;
  return (
    <Badge variant={config.variant} size="sm" className="min-w-fit whitespace-nowrap">
      <div className="flex items-center gap-1.5">
        <IconComponent className="h-3 w-3 flex-shrink-0" />
        <span className="flex-shrink-0">{status.charAt(0).toUpperCase() + status.slice(1)}</span>
      </div>
    </Badge>
  );
};

export const WorkflowsTable: React.FC<WorkflowsTableProps> = ({
  workflows,
  loading,
  pagination,
  sortBy,
  sortOrder,
  canCreateWorkflows,
  canExecuteWorkflows,
  canDeleteWorkflows,
  canUpdateWorkflows,
  onPageChange,
  onSort,
  onView,
  onExecute,
  onDesign,
  onDuplicate,
  onDelete,
  onNavigate,
  onCreateClick,
}) => {
  const columns = [
    {
      key: 'name',
      header: (
        <button
          onClick={() => onSort('name')}
          className="group flex items-center font-semibold text-theme-primary hover:text-theme-interactive-primary transition-colors"
          title="Sort by name"
        >
          Name
          {renderSortIndicator('name', sortBy, sortOrder)}
        </button>
      ),
      width: '40%',
      render: (workflow: AiWorkflow) => (
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <button
              onClick={() => onNavigate(`/app/ai/workflows/${workflow.id}`)}
              className="font-semibold text-lg text-theme-primary hover:text-theme-interactive-primary hover:underline whitespace-normal text-left transition-colors"
              title="View workflow details"
            >
              {workflow.name}
            </button>
            {workflow.is_template && (
              <Badge variant="info" size="sm" className="flex-shrink-0">
                <FileStack className="h-3 w-3 mr-1" />
                Template
              </Badge>
            )}
          </div>
          <div className="text-sm text-theme-muted leading-relaxed whitespace-normal">
            {workflow.description}
          </div>
        </div>
      )
    },
    {
      key: 'status',
      header: (
        <button
          onClick={() => onSort('status')}
          className="group flex items-center font-semibold text-theme-primary hover:text-theme-interactive-primary transition-colors"
          title="Sort by status"
        >
          Status
          {renderSortIndicator('status', sortBy, sortOrder)}
        </button>
      ),
      width: '10%',
      render: (workflow: AiWorkflow) => renderStatusBadge(workflow.status)
    },
    {
      key: 'stats',
      header: 'Stats',
      width: '10%',
      render: (workflow: AiWorkflow) => (
        <div className="text-sm">
          <div className="text-theme-primary">{workflow.stats?.nodes_count || 0} nodes</div>
          <div className="text-theme-muted">{workflow.stats?.runs_count || 0} runs</div>
        </div>
      )
    },
    {
      key: 'createdBy',
      header: (
        <button
          onClick={() => onSort('creator')}
          className="group flex items-center font-semibold text-theme-primary hover:text-theme-interactive-primary transition-colors"
          title="Sort by creator"
        >
          Created By
          {renderSortIndicator('creator', sortBy, sortOrder)}
        </button>
      ),
      width: '15%',
      render: (workflow: AiWorkflow) => (
        <div className="text-sm">
          <div className="text-theme-primary">{workflow.created_by?.name || 'System Admin'}</div>
          <div className="text-theme-muted">
            <button
              onClick={() => onSort('created_at')}
              className="group flex items-center text-theme-muted hover:text-theme-interactive-primary transition-colors"
              title="Sort by creation date"
            >
              {workflow.created_at ? new Date(workflow.created_at).toLocaleDateString() : 'No date'}
              {sortBy === 'created_at' ? (
                renderSortIndicator('created_at', sortBy, sortOrder)
              ) : (
                <ArrowUpDown className="h-3 w-3 inline-block ml-1 opacity-0 group-hover:opacity-40 transition-opacity" />
              )}
            </button>
          </div>
        </div>
      )
    },
    {
      key: 'actions',
      header: 'Actions',
      width: '25%',
      render: (workflow: AiWorkflow) => (
        <div className="flex items-center gap-2">
          <Button variant="ghost" size="sm" onClick={() => onView(workflow)} title="View Details">
            <Eye className="h-4 w-4" />
          </Button>
          {canExecuteWorkflows && workflow.status === 'active' && (
            <Button
              variant="ghost" size="sm"
              onClick={() => onExecute(workflow)}
              title="Execute Workflow"
              className="text-theme-success hover:text-theme-success/80"
            >
              <Play className="h-4 w-4" />
            </Button>
          )}
          {canUpdateWorkflows && (
            <Button
              variant="ghost" size="sm"
              onClick={() => onDesign(workflow.id)}
              title="Design Workflow"
              className="text-theme-interactive-primary hover:text-theme-interactive-primary/80"
            >
              <Workflow className="h-4 w-4" />
            </Button>
          )}
          {canCreateWorkflows && (
            <Button variant="ghost" size="sm" onClick={() => onDuplicate(workflow)} title="Duplicate Workflow">
              <Copy className="h-4 w-4" />
            </Button>
          )}
          {canDeleteWorkflows && (
            <Button
              variant="ghost" size="sm"
              onClick={() => onDelete(workflow)}
              title="Delete Workflow"
              className="text-theme-danger hover:text-theme-danger/80"
            >
              <Trash2 className="h-4 w-4" />
            </Button>
          )}
        </div>
      )
    }
  ];

  return (
    <DataTable
      columns={columns}
      data={workflows || []}
      loading={loading}
      pagination={pagination}
      onPageChange={(page) => onPageChange(page)}
      emptyState={{
        icon: Play,
        title: 'No workflows found',
        description: canCreateWorkflows
          ? 'Get started by creating your first AI workflow.'
          : 'No workflows have been created yet.',
        action: canCreateWorkflows ? {
          label: 'Create Workflow',
          onClick: onCreateClick
        } : undefined
      }}
    />
  );
};

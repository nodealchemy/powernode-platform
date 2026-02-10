import React from 'react';
import { NodeProps } from '@xyflow/react';
import { FileText, Download } from 'lucide-react';
import { DynamicNodeHandles } from '@/shared/components/workflow/nodes/DynamicNodeHandles';
import { NodeActionsMenu } from '@/shared/components/workflow/NodeActionsMenu';
import { useWorkflowContext } from '@/shared/components/workflow/WorkflowContext';
import { DevopsGetLogsNode as DevopsGetLogsNodeType } from '@/shared/types/workflow';

export const DevopsGetLogsNode: React.FC<NodeProps<DevopsGetLogsNodeType>> = ({
  id,
  data,
  selected
}) => {
  const { onOpenChat } = useWorkflowContext();

  const getProviderLabel = () => {
    switch (data.configuration?.provider) {
      case 'github':
        return 'GitHub';
      case 'gitlab':
        return 'GitLab';
      case 'jenkins':
        return 'Jenkins';
      case 'circleci':
        return 'CircleCI';
      default:
        return 'Pipeline';
    }
  };

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg w-64 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme hover:border-theme-interactive-primary/50'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="px-4 py-3 rounded-t-lg bg-gradient-to-r from-slate-500 to-slate-600">
        <div className="flex items-center gap-2 text-white">
          <FileText className="h-4 w-4" />
          <span className="font-medium text-sm">DEVOPS LOGS</span>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'Get Pipeline Logs'}
          </h3>
          {data.description && (
            <p className="text-xs text-theme-secondary mt-1 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        {/* Provider Badge */}
        <span className="inline-block text-xs font-bold px-2 py-0.5 rounded-full text-theme-secondary bg-theme-secondary/10">
          {getProviderLabel()}
        </span>

        {/* Options */}
        <div className="flex flex-wrap gap-2">
          {data.configuration?.step_name && (
            <span className="inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full bg-theme-surface-alt text-theme-secondary">
              <Download className="h-3 w-3" />
              {data.configuration.step_name}
            </span>
          )}
          {data.configuration?.tail_lines && (
            <span className="inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full bg-theme-surface-alt text-theme-secondary">
              Last {data.configuration.tail_lines} lines
            </span>
          )}
        </div>

        {/* Job/Run Info */}
        <div className="space-y-1">
          {data.configuration?.job_id && (
            <div className="text-xs">
              <span className="text-theme-muted">Job ID:</span>
              <span className="ml-1 text-theme-secondary font-mono">
                {data.configuration.job_id}
              </span>
            </div>
          )}
          {data.configuration?.run_id && !data.configuration?.job_id && (
            <div className="text-xs">
              <span className="text-theme-muted">Run ID:</span>
              <span className="ml-1 text-theme-secondary font-mono">
                {data.configuration.run_id}
              </span>
            </div>
          )}
        </div>
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="devops_get_logs"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Auto-positioning Handles */}
      <DynamicNodeHandles
        nodeType="devops_get_logs"
        isEndNode={data.isEndNode}
        handlePositions={data.handlePositions}
      />
    </div>
  );
};

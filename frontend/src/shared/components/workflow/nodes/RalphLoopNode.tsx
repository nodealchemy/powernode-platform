import React from 'react';
import { NodeProps } from '@xyflow/react';
import { RefreshCw, Play, Pause, Square, Clock, BookOpen, ListTodo, Brain } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';
import { NodeStatusBadge } from '../ExecutionOverlay';
import { RalphLoopNode as RalphLoopNodeType } from '@/shared/types/workflow';

const operationLabels: Record<string, string> = {
  create: 'Create Loop',
  start: 'Start Loop',
  pause: 'Pause Loop',
  resume: 'Resume Loop',
  cancel: 'Cancel Loop',
  run_iteration: 'Run Iteration',
  run_to_completion: 'Run to Completion',
  status: 'Get Status',
  get_learnings: 'Get Learnings',
  add_task: 'Add Task',
  parse_prd: 'Parse PRD'
};

const operationIcons: Record<string, React.ReactNode> = {
  create: <RefreshCw className="h-3 w-3" />,
  start: <Play className="h-3 w-3" />,
  pause: <Pause className="h-3 w-3" />,
  resume: <Play className="h-3 w-3" />,
  cancel: <Square className="h-3 w-3" />,
  run_iteration: <RefreshCw className="h-3 w-3" />,
  run_to_completion: <RefreshCw className="h-3 w-3" />,
  status: <Clock className="h-3 w-3" />,
  get_learnings: <Brain className="h-3 w-3" />,
  add_task: <ListTodo className="h-3 w-3" />,
  parse_prd: <BookOpen className="h-3 w-3" />
};

export const RalphLoopNode: React.FC<NodeProps<RalphLoopNodeType>> = ({
  id,
  data,
  selected
}) => {
  const { onOpenChat } = useWorkflowContext();
  const config = data.configuration;
  const operation = config?.operation || 'create';

  const getOperationColor = () => {
    switch (operation) {
      case 'create':
      case 'start':
      case 'resume':
        return 'text-theme-success';
      case 'pause':
      case 'cancel':
        return 'text-theme-warning';
      case 'run_iteration':
      case 'run_to_completion':
        return 'text-theme-info';
      default:
        return 'text-theme-interactive-primary';
    }
  };

  const renderOperationContent = () => {
    switch (operation) {
      case 'create':
        return (
          <>
            {config?.name && (
              <div className="text-xs">
                <span className="text-theme-muted">Name:</span>
                <span className="ml-1 text-theme-secondary">{config.name}</span>
              </div>
            )}
            {config?.default_agent_name && (
              <div className="text-xs">
                <span className="text-theme-muted">Agent:</span>
                <span className="ml-1 text-theme-secondary">{config.default_agent_name}</span>
              </div>
            )}
            {config?.max_iterations && (
              <div className="text-xs">
                <span className="text-theme-muted">Max Iterations:</span>
                <span className="ml-1 text-theme-secondary font-mono">{config.max_iterations}</span>
              </div>
            )}
          </>
        );

      case 'run_to_completion':
        return (
          <>
            {config?.max_iterations && (
              <div className="text-xs">
                <span className="text-theme-muted">Max Iterations:</span>
                <span className="ml-1 text-theme-secondary font-mono">{config.max_iterations}</span>
              </div>
            )}
            {config?.timeout_seconds && (
              <div className="text-xs">
                <span className="text-theme-muted">Timeout:</span>
                <span className="ml-1 text-theme-secondary font-mono">{config.timeout_seconds}s</span>
              </div>
            )}
          </>
        );

      case 'cancel':
        return config?.reason ? (
          <div className="text-xs">
            <span className="text-theme-muted">Reason:</span>
            <span className="ml-1 text-theme-secondary truncate">{config.reason}</span>
          </div>
        ) : null;

      case 'add_task':
        return (
          <>
            {config?.task_key && (
              <div className="text-xs">
                <span className="text-theme-muted">Task:</span>
                <span className="ml-1 text-theme-secondary font-mono">{config.task_key}</span>
              </div>
            )}
            {config?.priority !== undefined && (
              <div className="text-xs">
                <span className="text-theme-muted">Priority:</span>
                <span className="ml-1 text-theme-secondary">{config.priority}</span>
              </div>
            )}
          </>
        );

      case 'parse_prd':
        return config?.prd_variable ? (
          <div className="text-xs">
            <span className="text-theme-muted">From Variable:</span>
            <span className="ml-1 text-theme-secondary font-mono">{config.prd_variable}</span>
          </div>
        ) : config?.prd_data ? (
          <div className="text-xs">
            <span className="text-theme-muted">PRD Data:</span>
            <span className="ml-1 text-theme-secondary">Provided</span>
          </div>
        ) : null;

      default:
        // For operations that only need loop identification
        return (config?.loop_id || config?.loop_variable) ? (
          <div className="text-xs">
            <span className="text-theme-muted">Loop:</span>
            <span className="ml-1 text-theme-secondary font-mono">
              {config.loop_variable ? `{{${config.loop_variable}}}` : config.loop_id}
            </span>
          </div>
        ) : null;
    }
  };

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg w-64 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme hover:border-theme-interactive-primary/50'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="px-4 py-3 rounded-t-lg bg-node-ralph-loop">
        <div className="flex items-center gap-2 text-white">
          <RefreshCw className="h-4 w-4" />
          <span className="font-medium text-sm">RALPH LOOP</span>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'Ralph Loop'}
          </h3>
          {data.description && (
            <p className="text-xs text-theme-secondary mt-1 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        {/* Operation Badge */}
        <div className="flex items-center gap-2">
          <span className={`inline-flex items-center gap-1 text-xs font-medium ${getOperationColor()}`}>
            {operationIcons[operation]}
            {operationLabels[operation] || operation}
          </span>
        </div>

        {/* Operation-specific content */}
        {renderOperationContent()}

        {/* Output Variable */}
        {config?.output_variable && (
          <div className="text-xs">
            <span className="text-theme-muted">Output:</span>
            <span className="ml-1 text-theme-secondary font-mono">{config.output_variable}</span>
          </div>
        )}
      </div>

      {/* Execution Status Badge */}
      {data.executionStatus && (
        <NodeStatusBadge
          status={data.executionStatus}
          duration={data.executionDuration}
          error={data.executionError}
        />
      )}

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="ralph_loop"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Auto-positioning Handles */}
      <DynamicNodeHandles
        nodeType="ralph_loop"
        isEndNode={data.isEndNode}
        handlePositions={data.handlePositions}
      />
    </div>
  );
};

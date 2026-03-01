import React from 'react';
import { NodeProps } from '@xyflow/react';
import { Database } from 'lucide-react';
import { DynamicNodeHandles } from '@/shared/components/workflow/nodes/DynamicNodeHandles';
import { NodeActionsMenu } from '@/shared/components/workflow/NodeActionsMenu';
import { useWorkflowContext } from '@/shared/components/workflow/WorkflowContext';
import { DatabaseNode as DatabaseNodeType } from '@/shared/types/workflow';

export const DatabaseNode: React.FC<NodeProps<DatabaseNodeType>> = ({
  id,
  data,
  selected
}) => {
  const { onOpenChat } = useWorkflowContext();

  const getOperationColor = () => {
    switch (data.configuration?.operation) {
      case 'select':
      case 'query':
        return 'text-theme-info bg-theme-info/20';
      case 'insert':
        return 'text-theme-success bg-theme-success/20';
      case 'update':
        return 'text-theme-warning bg-theme-warning/20';
      case 'delete':
        return 'text-theme-danger bg-theme-danger/20';
      case 'backup':
        return 'text-theme-interactive-primary bg-theme-interactive-primary/20';
      default:
        return 'text-theme-info bg-theme-info/20';
    }
  };

  const getOperationLabel = () => {
    switch (data.configuration?.operation) {
      case 'select':
        return 'SELECT';
      case 'insert':
        return 'INSERT';
      case 'update':
        return 'UPDATE';
      case 'delete':
        return 'DELETE';
      case 'query':
        return 'QUERY';
      case 'backup':
        return 'BACKUP';
      default:
        return 'DB';
    }
  };

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg w-64 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme hover:border-theme-interactive-primary/50'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="px-4 py-3 rounded-t-lg bg-node-database">
        <div className="flex items-center gap-2 text-white">
          <Database className="h-4 w-4" />
          <span className="font-medium text-sm">DATABASE</span>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'Database Operation'}
          </h3>
          {data.description && (
            <p className="text-xs text-theme-secondary mt-1 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        {/* Operation Badge */}
        {data.configuration?.operation && (
          <span className={`inline-block text-xs font-medium px-2 py-0.5 rounded-full ${getOperationColor()}`}>
            {getOperationLabel()}
          </span>
        )}

        {/* Table Name */}
        {data.configuration?.table && (
          <div className="text-xs">
            <span className="text-theme-muted">Table:</span>
            <span className="ml-1 text-theme-secondary font-mono">{data.configuration.table}</span>
          </div>
        )}
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="database"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Dynamic Handles */}
      <DynamicNodeHandles
        nodeType="database"
        handlePositions={data.handlePositions}
      />
    </div>
  );
};
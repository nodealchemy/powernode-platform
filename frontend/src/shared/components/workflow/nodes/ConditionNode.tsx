import React from 'react';
import { NodeProps } from '@xyflow/react';
import { GitBranch } from 'lucide-react';
import { DynamicNodeHandles } from '@/shared/components/workflow/nodes/DynamicNodeHandles';
import { NodeActionsMenu } from '@/shared/components/workflow/NodeActionsMenu';
import { useWorkflowContext } from '@/shared/components/workflow/WorkflowContext';
import { ConditionNode as ConditionNodeType } from '@/shared/types/workflow';

export const ConditionNode: React.FC<NodeProps<ConditionNodeType>> = ({
  id,
  data,
  selected
}) => {
  const { onOpenChat } = useWorkflowContext();

  const getConditionExpression = () => {
    const { variablePath, conditionType, expectedValue } = data.configuration || {};

    if (!variablePath || !conditionType || !expectedValue) {
      return 'Configure condition';
    }

    const operatorMap: Record<string, string> = {
      equals: '==',
      not_equals: '!=',
      greater_than: '>',
      less_than: '<',
      contains: 'contains',
      regex: 'matches'
    };
    const operator = operatorMap[conditionType] || '?';

    return `${variablePath} ${operator} ${expectedValue}`;
  };

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg w-64 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme hover:border-theme-interactive-primary/50'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="px-4 py-3 rounded-t-lg bg-node-condition">
        <div className="flex items-center gap-2 text-white">
          <GitBranch className="h-4 w-4" />
          <span className="font-medium text-sm">CONDITION</span>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'Condition'}
          </h3>
          {data.description && (
            <p className="text-xs text-theme-secondary mt-1 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        {/* Condition Expression */}
        <div className="p-2 bg-theme-warning/10 border border-theme-warning/30 rounded text-xs font-mono">
          <div className="text-theme-warning-dark">
            {getConditionExpression()}
          </div>
        </div>

        {/* Path Labels - matches handle positions: False (left/top), True (right/bottom) */}
        <div className="flex justify-between px-2 text-xs font-medium">
          <div className="text-theme-danger">✗ False</div>
          <div className="text-theme-success">✓ True</div>
        </div>
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="condition"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Dynamic Handles for Condition Node */}
      <DynamicNodeHandles
        nodeType="condition"
        handlePositions={data?.handlePositions}
      />
    </div>
  );
};
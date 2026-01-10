import React from 'react';
import { NodeProps } from '@xyflow/react';
import { TestTube2, CheckCircle, BarChart3, Zap } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';
import { RunTestsNode as RunTestsNodeType } from '@/shared/types/workflow';

export const RunTestsNode: React.FC<NodeProps<RunTestsNodeType>> = ({
  id,
  data,
  selected
}) => {
  const { onOpenChat } = useWorkflowContext();

  const getFrameworkLabel = () => {
    switch (data.configuration?.test_framework) {
      case 'jest':
        return 'Jest';
      case 'rspec':
        return 'RSpec';
      case 'pytest':
        return 'Pytest';
      case 'mocha':
        return 'Mocha';
      case 'cypress':
        return 'Cypress';
      case 'playwright':
        return 'Playwright';
      case 'custom':
        return 'Custom';
      default:
        return 'Tests';
    }
  };

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg w-64 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme hover:border-theme-interactive-primary/50'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="px-4 py-3 rounded-t-lg bg-gradient-to-r from-green-500 to-green-600">
        <div className="flex items-center gap-2 text-white">
          <TestTube2 className="h-4 w-4" />
          <span className="font-medium text-sm">RUN TESTS</span>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'Run Tests'}
          </h3>
          {data.description && (
            <p className="text-xs text-theme-secondary mt-1 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        {/* Framework Badge */}
        <span className="inline-block text-xs font-bold px-2 py-0.5 rounded-full text-theme-success bg-theme-success/10">
          {getFrameworkLabel()}
        </span>

        {/* Test Options */}
        <div className="flex flex-wrap gap-1">
          {data.configuration?.coverage && (
            <span className="inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full bg-theme-info/10 text-theme-info">
              <BarChart3 className="h-3 w-3" />
              Coverage
            </span>
          )}
          {data.configuration?.parallel && (
            <span className="inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full bg-theme-interactive-primary/10 text-theme-interactive-primary">
              <Zap className="h-3 w-3" />
              Parallel
            </span>
          )}
          {data.configuration?.fail_fast && (
            <span className="inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full bg-theme-warning/10 text-theme-warning">
              <CheckCircle className="h-3 w-3" />
              Fail Fast
            </span>
          )}
        </div>

        {/* Test Pattern */}
        {data.configuration?.test_pattern && (
          <div className="text-xs text-theme-tertiary font-mono truncate">
            {data.configuration.test_pattern}
          </div>
        )}
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="run_tests"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Auto-positioning Handles */}
      <DynamicNodeHandles
        nodeType="run_tests"
        isEndNode={data.isEndNode}
        handlePositions={data.handlePositions}
      />
    </div>
  );
};

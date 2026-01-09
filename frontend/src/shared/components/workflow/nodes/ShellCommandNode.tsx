import React from 'react';
import { NodeProps } from '@xyflow/react';
import { Terminal, Clock, AlertTriangle } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';
import { ShellCommandNode as ShellCommandNodeType } from '@/shared/types/workflow';

export const ShellCommandNode: React.FC<NodeProps<ShellCommandNodeType>> = ({
  id,
  data,
  selected
}) => {
  const { onOpenChat } = useWorkflowContext();

  const getShellLabel = () => {
    switch (data.configuration?.shell) {
      case 'bash':
        return 'Bash';
      case 'sh':
        return 'Shell';
      case 'zsh':
        return 'Zsh';
      case 'powershell':
        return 'PowerShell';
      default:
        return 'Shell';
    }
  };

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg w-64 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme hover:border-theme-interactive-primary/50'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="px-4 py-3 rounded-t-lg bg-gradient-to-r from-gray-700 to-gray-800">
        <div className="flex items-center gap-2 text-white">
          <Terminal className="h-4 w-4" />
          <span className="font-medium text-sm">SHELL COMMAND</span>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'Shell Command'}
          </h3>
          {data.description && (
            <p className="text-xs text-theme-secondary mt-1 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        {/* Shell Type Badge */}
        <span className="inline-block text-xs font-bold px-2 py-0.5 rounded-full text-theme-secondary bg-theme-surface">
          {getShellLabel()}
        </span>

        {/* Command Preview */}
        {data.configuration?.command && (
          <div className="bg-theme-bg-subtle rounded p-2">
            <code className="text-xs font-mono text-theme-secondary line-clamp-2">
              $ {data.configuration.command}
            </code>
          </div>
        )}

        {/* Options */}
        <div className="flex flex-wrap gap-1">
          {data.configuration?.timeout_seconds && (
            <span className="inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full bg-blue-100 text-theme-info">
              <Clock className="h-3 w-3" />
              {data.configuration.timeout_seconds}s
            </span>
          )}
          {data.configuration?.continue_on_error && (
            <span className="inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full bg-yellow-100 text-yellow-700">
              <AlertTriangle className="h-3 w-3" />
              Continue on error
            </span>
          )}
        </div>
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="shell_command"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Auto-positioning Handles */}
      <DynamicNodeHandles
        nodeType="shell_command"
        isEndNode={data.isEndNode}
        handlePositions={data.handlePositions}
      />
    </div>
  );
};

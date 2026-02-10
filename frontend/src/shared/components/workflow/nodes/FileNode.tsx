import React from 'react';
import { NodeProps } from '@xyflow/react';
import { File } from 'lucide-react';
import { DynamicNodeHandles } from '@/shared/components/workflow/nodes/DynamicNodeHandles';
import { NodeActionsMenu } from '@/shared/components/workflow/NodeActionsMenu';
import { useWorkflowContext } from '@/shared/components/workflow/WorkflowContext';
import { FileNode as FileNodeType } from '@/shared/types/workflow';

export const FileNode: React.FC<NodeProps<FileNodeType>> = ({
  id,
  data,
  selected
}) => {
  const { onOpenChat } = useWorkflowContext();

  const getOperationColor = () => {
    switch (data.configuration?.operation) {
      case 'read':
        return 'text-theme-info bg-theme-info/20';
      case 'write':
      case 'create':
        return 'text-theme-success bg-theme-success/20';
      case 'download':
        return 'text-theme-interactive-primary bg-theme-interactive-primary/20';
      case 'compress':
      case 'archive':
        return 'text-theme-warning bg-theme-warning/20';
      default:
        return 'text-theme-muted bg-theme-surface';
    }
  };

  const getOperationLabel = () => {
    switch (data.configuration?.operation) {
      case 'read':
        return 'READ';
      case 'write':
        return 'WRITE';
      case 'create':
        return 'CREATE';
      case 'download':
        return 'DOWNLOAD';
      case 'compress':
        return 'COMPRESS';
      case 'archive':
        return 'ARCHIVE';
      default:
        return 'FILE';
    }
  };

  const getFilePathPreview = () => {
    const path = data.configuration?.filePath;
    if (!path) return 'No file path';

    // Show last part of path and beginning if too long
    const parts = path.split('/');
    const filename = parts[parts.length - 1];
    if (path.length <= 35) return path;

    return `.../${filename}`;
  };

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg w-64 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme hover:border-theme-interactive-primary/50'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="px-4 py-3 rounded-t-lg bg-node-file">
        <div className="flex items-center gap-2 text-white">
          <File className="h-4 w-4" />
          <span className="font-medium text-sm">FILE</span>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'File Operation'}
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

        {/* File Path */}
        {data.configuration?.filePath && (
          <div className="text-xs">
            <span className="text-theme-muted">Path:</span>
            <span className="ml-1 text-theme-secondary font-mono">{getFilePathPreview()}</span>
          </div>
        )}
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="file"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Dynamic Handles */}
      <DynamicNodeHandles
        nodeType="file"
        handlePositions={data.handlePositions}
      />
    </div>
  );
};
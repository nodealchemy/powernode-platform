import React from 'react';
import { NodeProps } from '@xyflow/react';
import { MessageSquare, GitPullRequest, AlertCircle, GitCommit } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';
import { GitCommentNode as GitCommentNodeType } from '@/shared/types/workflow';

export const GitCommentNode: React.FC<NodeProps<GitCommentNodeType>> = ({
  id,
  data,
  selected
}) => {
  const { onOpenChat } = useWorkflowContext();

  const getTargetIcon = () => {
    switch (data.configuration?.target_type) {
      case 'pull_request':
        return <GitPullRequest className="h-3 w-3" />;
      case 'issue':
        return <AlertCircle className="h-3 w-3" />;
      case 'commit':
        return <GitCommit className="h-3 w-3" />;
      default:
        return <MessageSquare className="h-3 w-3" />;
    }
  };

  const getTargetLabel = () => {
    switch (data.configuration?.target_type) {
      case 'pull_request':
        return 'Pull Request';
      case 'issue':
        return 'Issue';
      case 'commit':
        return 'Commit';
      default:
        return 'Comment';
    }
  };

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg w-64 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme hover:border-theme-interactive-primary/50'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="px-4 py-3 rounded-t-lg bg-gradient-to-r from-blue-500 to-blue-600">
        <div className="flex items-center gap-2 text-white">
          <MessageSquare className="h-4 w-4" />
          <span className="font-medium text-sm">POST COMMENT</span>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'Post Comment'}
          </h3>
          {data.description && (
            <p className="text-xs text-theme-secondary mt-1 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        {/* Target Type Badge */}
        <span className="inline-flex items-center gap-1 text-xs font-bold px-2 py-0.5 rounded-full text-theme-info bg-theme-info/10">
          {getTargetIcon()}
          {getTargetLabel()}
        </span>

        {/* Comment Preview */}
        <div className="space-y-1">
          {data.configuration?.body && (
            <p className="text-xs text-theme-secondary line-clamp-2 italic">
              "{data.configuration.body.substring(0, 50)}..."
            </p>
          )}
          {data.configuration?.template && (
            <div className="text-xs text-theme-tertiary">
              Using template
            </div>
          )}
        </div>
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="git_comment"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Auto-positioning Handles */}
      <DynamicNodeHandles
        nodeType="git_comment"
        isEndNode={data.isEndNode}
        handlePositions={data.handlePositions}
      />
    </div>
  );
};

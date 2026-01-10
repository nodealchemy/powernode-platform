import React from 'react';
import { NodeProps } from '@xyflow/react';
import { GitPullRequest, GitBranch, Users, Tag } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';
import { GitPullRequestNode as GitPullRequestNodeType } from '@/shared/types/workflow';

export const GitPullRequestNode: React.FC<NodeProps<GitPullRequestNodeType>> = ({
  id,
  data,
  selected
}) => {
  const { onOpenChat } = useWorkflowContext();

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg w-64 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme hover:border-theme-interactive-primary/50'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="px-4 py-3 rounded-t-lg bg-gradient-to-r from-purple-500 to-purple-600">
        <div className="flex items-center gap-2 text-white">
          <GitPullRequest className="h-4 w-4" />
          <span className="font-medium text-sm">CREATE PR</span>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'Create Pull Request'}
          </h3>
          {data.configuration?.title && (
            <p className="text-xs text-theme-secondary mt-1 line-clamp-2">
              {data.configuration.title}
            </p>
          )}
        </div>

        {/* Draft Badge */}
        {data.configuration?.draft && (
          <span className="inline-block text-xs font-bold px-2 py-0.5 rounded-full text-theme-warning bg-theme-warning/10">
            Draft
          </span>
        )}

        {/* Branch Info */}
        <div className="space-y-1">
          {(data.configuration?.head_branch || data.configuration?.base_branch) && (
            <div className="flex items-center gap-1 text-xs">
              <GitBranch className="h-3 w-3 text-theme-muted" />
              <span className="text-theme-secondary font-mono truncate">
                {data.configuration.head_branch || 'head'} → {data.configuration.base_branch || 'base'}
              </span>
            </div>
          )}
          {data.configuration?.reviewers && data.configuration.reviewers.length > 0 && (
            <div className="flex items-center gap-1 text-xs">
              <Users className="h-3 w-3 text-theme-muted" />
              <span className="text-theme-secondary">
                {data.configuration.reviewers.length} reviewer(s)
              </span>
            </div>
          )}
          {data.configuration?.labels && data.configuration.labels.length > 0 && (
            <div className="flex items-center gap-1 text-xs">
              <Tag className="h-3 w-3 text-theme-muted" />
              <span className="text-theme-secondary">
                {data.configuration.labels.length} label(s)
              </span>
            </div>
          )}
        </div>
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="git_pull_request"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Auto-positioning Handles */}
      <DynamicNodeHandles
        nodeType="git_pull_request"
        isEndNode={data.isEndNode}
        handlePositions={data.handlePositions}
      />
    </div>
  );
};

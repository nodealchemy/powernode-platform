// Utility functions for WorkflowDetailModal

import React from 'react';
import { EyeOff, User, Eye } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { AiWorkflow } from '@/shared/types/workflow';

/**
 * Status configuration for workflow status badges
 */
export const statusConfig = {
  draft: { variant: 'warning' as const, label: 'Draft' },
  active: { variant: 'success' as const, label: 'Active' },
  inactive: { variant: 'secondary' as const, label: 'Inactive' },
  archived: { variant: 'secondary' as const, label: 'Archived' },
  paused: { variant: 'info' as const, label: 'Paused' }
};

/**
 * Visibility configuration for workflow visibility badges
 */
export const visibilityConfig = {
  private: { icon: EyeOff, label: 'Private' },
  account: { icon: User, label: 'Account' },
  public: { icon: Eye, label: 'Public' }
};

/**
 * Render a status badge for workflow status
 */
export const renderStatusBadge = (status: string): React.ReactElement => {
  const config = statusConfig[status as keyof typeof statusConfig] || statusConfig.draft;
  return React.createElement(Badge, { variant: config.variant, size: 'sm', children: config.label });
};

/**
 * Render a visibility badge with icon
 */
export const renderVisibilityBadge = (visibility: string) => {
  const config = visibilityConfig[visibility as keyof typeof visibilityConfig] || visibilityConfig.private;
  const IconComponent = config.icon;

  return React.createElement('div',
    { className: 'flex items-center gap-1 text-sm text-theme-muted' },
    React.createElement(IconComponent, { className: 'h-3 w-3' }),
    config.label
  );
};

/**
 * Default suggested prompts for workflow execution
 */
export const suggestedPrompts = [
  "Write a blog post about the future of AI",
  "Create content about sustainable technology",
  "Explain cloud computing for beginners",
  "Discuss cybersecurity best practices"
];

/**
 * Parse chat input to extract workflow parameters
 */
export const parseInputToParameters = (
  input: string,
  workflow: AiWorkflow | null
): Record<string, unknown> => {
  const params: Record<string, unknown> = {};

  if (workflow?.name.toLowerCase().includes('blog')) {
    params.topic = input;

    if (input.toLowerCase().includes('developer') || input.toLowerCase().includes('technical')) {
      params.target_audience = 'technical team';
    } else if (input.toLowerCase().includes('business') || input.toLowerCase().includes('executive')) {
      params.target_audience = 'business audience';
    } else {
      params.target_audience = 'general audience';
    }

    if (input.toLowerCase().includes('short') || input.toLowerCase().includes('brief')) {
      params.post_length = 'short';
    } else if (input.toLowerCase().includes('long') || input.toLowerCase().includes('detailed')) {
      params.post_length = 'long';
    } else {
      params.post_length = 'medium';
    }
  } else {
    params.input = input;
    params.prompt = input;
  }

  return params;
};

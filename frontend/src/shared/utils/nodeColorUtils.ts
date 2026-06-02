/**
 * Centralized color utility functions for workflow nodes.
 * These functions return theme-aware Tailwind class strings for consistent styling.
 */

/**
 * HTTP method colors for API call nodes
 */
export const getHttpMethodColor = (method?: string): string => {
  switch (method?.toUpperCase()) {
    case 'GET':
      return 'text-theme-success bg-theme-success/20';
    case 'POST':
      return 'text-theme-info bg-theme-info/20';
    case 'PUT':
    case 'PATCH':
      return 'text-theme-warning bg-theme-warning/20';
    case 'DELETE':
      return 'text-theme-danger bg-theme-danger/20';
    default:
      return 'text-theme-info bg-theme-info/20';
  }
};
/**
 * Status badge colors (for workflow node execution status, content status, etc.)
 */
export const getStatusColor = (status?: string): string => {
  switch (status?.toLowerCase()) {
    case 'published':
    case 'active':
    case 'success':
    case 'completed':
      return 'text-theme-success bg-theme-success/20';
    case 'draft':
    case 'pending':
    case 'waiting':
      return 'text-theme-warning bg-theme-warning/20';
    case 'archived':
    case 'inactive':
    case 'skipped':
      return 'text-theme-tertiary bg-theme-background-secondary/20';
    case 'error':
    case 'failed':
    case 'rejected':
      return 'text-theme-danger bg-theme-danger/20';
    case 'running':
    case 'processing':
      return 'text-theme-info bg-theme-info/20';
    default:
      return 'text-theme-secondary bg-theme-surface/20';
  }
};
/**
 * Priority/urgency colors
 */
export const getPriorityColor = (priority?: string | number): string => {
  const normalizedPriority = typeof priority === 'string'
    ? priority.toLowerCase()
    : priority;

  switch (normalizedPriority) {
    case 'high':
    case 'critical':
    case 'urgent':
    case 1:
      return 'text-theme-danger bg-theme-danger/20';
    case 'medium':
    case 'normal':
    case 2:
      return 'text-theme-warning bg-theme-warning/20';
    case 'low':
    case 3:
      return 'text-theme-success bg-theme-success/20';
    default:
      return 'text-theme-secondary bg-theme-surface/20';
  }
};

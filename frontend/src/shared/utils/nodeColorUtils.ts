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
 * AI provider colors for AI agent nodes
 */
export const getAiProviderColor = (provider?: string): string => {
  switch (provider?.toLowerCase()) {
    case 'openai':
      return 'text-theme-success';
    case 'anthropic':
      return 'text-theme-warning';
    case 'google':
      return 'text-theme-info';
    default:
      return 'text-theme-interactive-primary';
  }
};

/**
 * Get provider display name
 */
export const getAiProviderName = (provider?: string): string => {
  switch (provider?.toLowerCase()) {
    case 'openai':
      return 'OpenAI';
    case 'anthropic':
      return 'Anthropic';
    case 'google':
      return 'Google AI';
    default:
      return 'AI Agent';
  }
};

/**
 * Database operation colors
 */
export const getDatabaseOperationColor = (operation?: string): string => {
  switch (operation?.toLowerCase()) {
    case 'select':
    case 'read':
    case 'find':
      return 'text-theme-success bg-theme-success/20';
    case 'insert':
    case 'create':
      return 'text-theme-info bg-theme-info/20';
    case 'update':
      return 'text-theme-warning bg-theme-warning/20';
    case 'delete':
    case 'remove':
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
      return 'text-theme-muted bg-theme-muted/20';
    case 'error':
    case 'failed':
    case 'rejected':
      return 'text-theme-danger bg-theme-danger/20';
    case 'running':
    case 'processing':
      return 'text-theme-info bg-theme-info/20';
    default:
      return 'text-theme-secondary bg-theme-secondary/20';
  }
};

/**
 * Trigger type colors for start/trigger nodes
 */
export const getTriggerTypeColor = (type?: string): string => {
  switch (type?.toLowerCase()) {
    case 'webhook':
      return 'bg-theme-info';
    case 'schedule':
      return 'bg-theme-success';
    case 'api':
      return 'bg-theme-interactive-primary';
    case 'manual':
    default:
      return 'bg-node-start';
  }
};

/**
 * MCP operation type colors
 */
export const getMcpOperationColor = (type?: string): string => {
  switch (type?.toLowerCase()) {
    case 'tool':
      return 'text-theme-interactive-primary bg-theme-interactive-primary/20';
    case 'resource':
      return 'text-theme-info bg-theme-info/20';
    case 'prompt':
      return 'text-theme-warning bg-theme-warning/20';
    default:
      return 'text-theme-secondary bg-theme-secondary/20';
  }
};

/**
 * Condition/branch colors for conditional nodes
 */
export const getConditionBranchColor = (branch?: string | boolean): string => {
  if (branch === true || branch === 'true' || branch === 'yes') {
    return 'text-theme-success bg-theme-success/20';
  }
  if (branch === false || branch === 'false' || branch === 'no') {
    return 'text-theme-danger bg-theme-danger/20';
  }
  return 'text-theme-secondary bg-theme-secondary/20';
};

/**
 * Notification channel colors
 */
export const getNotificationChannelColor = (channel?: string): string => {
  switch (channel?.toLowerCase()) {
    case 'email':
      return 'text-theme-info bg-theme-info/20';
    case 'sms':
      return 'text-theme-success bg-theme-success/20';
    case 'push':
      return 'text-theme-warning bg-theme-warning/20';
    case 'slack':
    case 'teams':
    case 'discord':
      return 'text-theme-interactive-primary bg-theme-interactive-primary/20';
    default:
      return 'text-theme-secondary bg-theme-secondary/20';
  }
};

/**
 * File operation colors
 */
export const getFileOperationColor = (operation?: string): string => {
  switch (operation?.toLowerCase()) {
    case 'read':
    case 'download':
      return 'text-theme-success bg-theme-success/20';
    case 'write':
    case 'upload':
    case 'create':
      return 'text-theme-info bg-theme-info/20';
    case 'move':
    case 'copy':
      return 'text-theme-warning bg-theme-warning/20';
    case 'delete':
      return 'text-theme-danger bg-theme-danger/20';
    default:
      return 'text-theme-secondary bg-theme-secondary/20';
  }
};

/**
 * Validation result colors
 */
export const getValidationResultColor = (result?: string | boolean): string => {
  if (result === true || result === 'valid' || result === 'pass') {
    return 'text-theme-success';
  }
  if (result === false || result === 'invalid' || result === 'fail') {
    return 'text-theme-danger';
  }
  return 'text-theme-warning';
};

/**
 * Loop type colors
 */
export const getLoopTypeColor = (type?: string): string => {
  switch (type?.toLowerCase()) {
    case 'foreach':
    case 'for_each':
      return 'text-theme-interactive-primary bg-theme-interactive-primary/20';
    case 'while':
      return 'text-theme-warning bg-theme-warning/20';
    case 'count':
    case 'times':
      return 'text-theme-info bg-theme-info/20';
    default:
      return 'text-theme-secondary bg-theme-secondary/20';
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
      return 'text-theme-secondary bg-theme-secondary/20';
  }
};

/**
 * Article/content action colors
 */
export const getContentActionColor = (action?: string): string => {
  switch (action?.toLowerCase()) {
    case 'create':
      return 'text-theme-success bg-theme-success/20';
    case 'read':
    case 'search':
      return 'text-theme-info bg-theme-info/20';
    case 'update':
    case 'edit':
      return 'text-theme-warning bg-theme-warning/20';
    case 'publish':
      return 'text-theme-interactive-primary bg-theme-interactive-primary/20';
    case 'delete':
    case 'archive':
      return 'text-theme-danger bg-theme-danger/20';
    default:
      return 'text-theme-secondary bg-theme-secondary/20';
  }
};

/**
 * Sort order display helpers
 */
export const getSortOrderLabel = (sortBy?: string): string => {
  switch (sortBy?.toLowerCase()) {
    case 'latest':
    case 'newest':
      return 'Latest';
    case 'oldest':
      return 'Oldest';
    case 'popular':
    case 'views':
      return 'Popular';
    case 'alphabetical':
    case 'title':
      return 'A-Z';
    case 'relevance':
      return 'Relevance';
    default:
      return sortBy || 'Default';
  }
};

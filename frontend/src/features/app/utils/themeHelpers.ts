/**
 * Theme-compliant helper utilities for marketplace components
 * Ensures consistent styling across light/dark themes
 */

export type HttpMethod = 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE' | 'HEAD' | 'OPTIONS';
export type AppStatus = 'published' | 'draft' | 'under_review' | 'inactive' | 'pending' | 'approved' | 'rejected';
export type AppPlanStatus = 'active' | 'inactive' | 'archived';
export type SubscriptionStatus = 'active' | 'paused' | 'cancelled' | 'expired';

/**
 * Get theme-compliant CSS classes for HTTP methods
 * Ensures proper contrast and theme compatibility
 */
export const getHttpMethodThemeClass = (method: HttpMethod): string => {
  const classes = {
    GET: 'bg-theme-info text-white',
    POST: 'bg-theme-success text-white',
    PUT: 'bg-theme-warning text-white',
    PATCH: 'bg-theme-warning text-white', 
    DELETE: 'bg-theme-error text-white',
    HEAD: 'bg-theme-secondary text-white',
    OPTIONS: 'bg-theme-secondary text-white'
  } as const;
  
  return Object.prototype.hasOwnProperty.call(classes, method) ? classes[method as keyof typeof classes] : 'bg-theme-secondary text-white';
};

/**
 * Get badge variant for app status
 * Maps app status to theme-aware badge variants
 */
export const getAppStatusBadgeVariant = (status: AppStatus): 'success' | 'warning' | 'danger' | 'info' | 'secondary' => {
  const variants = {
    published: 'success',
    approved: 'success',
    draft: 'secondary',
    pending: 'info',
    under_review: 'warning',
    inactive: 'danger',
    rejected: 'danger'
  } as const;
  
  return Object.prototype.hasOwnProperty.call(variants, status) ? variants[status as keyof typeof variants] : 'secondary';
};

/**
 * Get badge variant for app plan status
 */
export const getAppPlanStatusBadgeVariant = (status: AppPlanStatus): 'success' | 'warning' | 'danger' | 'secondary' => {
  const variants = {
    active: 'success',
    inactive: 'warning',
    archived: 'danger'
  } as const;
  
  return Object.prototype.hasOwnProperty.call(variants, status) ? variants[status as keyof typeof variants] : 'secondary';
};

/**
 * Get badge variant for subscription status
 */
export const getSubscriptionStatusBadgeVariant = (status: SubscriptionStatus): 'success' | 'warning' | 'danger' | 'info' => {
  const variants = {
    active: 'success',
    paused: 'warning',
    cancelled: 'danger',
    expired: 'danger'
  } as const;
  
  return Object.prototype.hasOwnProperty.call(variants, status) ? variants[status as keyof typeof variants] : 'info';
};

/**
 * Get status text for display
 */
export const getStatusDisplayText = (status: string): string => {
  return status
    .split('_')
    .map(word => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ');
};

/**
 * Get theme-aware border color for cards based on status
 */
export const getStatusBorderClass = (status: AppStatus): string => {
  const borderClasses = {
    published: 'border-theme-success',
    approved: 'border-theme-success', 
    draft: 'border-theme-secondary',
    pending: 'border-theme-info',
    under_review: 'border-theme-warning',
    inactive: 'border-theme-error',
    rejected: 'border-theme-error'
  } as const;
  
  return Object.prototype.hasOwnProperty.call(borderClasses, status) ? borderClasses[status as keyof typeof borderClasses] : 'border-theme';
};

/**
 * Get theme-aware background color for status indicators
 */
export const getStatusBackgroundClass = (status: AppStatus): string => {
  const bgClasses = {
    published: 'bg-theme-success-background',
    approved: 'bg-theme-success-background',
    draft: 'bg-theme-surface',
    pending: 'bg-theme-info-background', 
    under_review: 'bg-theme-warning-background',
    inactive: 'bg-theme-error-background',
    rejected: 'bg-theme-error-background'
  } as const;
  
  return Object.prototype.hasOwnProperty.call(bgClasses, status) ? bgClasses[status as keyof typeof bgClasses] : 'bg-theme-surface';
};

/**
 * Get HTTP method color for display (non-background usage)
 */
export const getHttpMethodColor = (method: HttpMethod): string => {
  const colors = {
    GET: 'text-theme-info',
    POST: 'text-theme-success',
    PUT: 'text-theme-warning',
    PATCH: 'text-theme-warning',
    DELETE: 'text-theme-error',
    HEAD: 'text-theme-secondary',
    OPTIONS: 'text-theme-secondary'
  } as const;
  
  return Object.prototype.hasOwnProperty.call(colors, method) ? colors[method as keyof typeof colors] : 'text-theme-secondary';
};

/**
 * Format pricing for display
 */
export const formatPriceCents = (priceCents: number): string => {
  if (priceCents === 0) return 'Free';
  return `$${(priceCents / 100).toFixed(2)}`;
};

/**
 * Format billing interval for display
 */
export const formatBillingInterval = (interval: string): string => {
  const intervals = {
    monthly: 'per month',
    yearly: 'per year', 
    weekly: 'per week',
    daily: 'per day',
    one_time: 'one time',
    forever: 'forever'
  } as const;
  
  return intervals[interval as keyof typeof intervals] || interval;
};

/**
 * Get priority badge styles for featured/popular items
 */
export const getPriorityBadgeClass = (priority: 'featured' | 'popular' | 'new' | 'recommended'): string => {
  const classes = {
    featured: 'bg-gradient-to-r from-theme-interactive-primary to-blue-600 text-white',
    popular: 'bg-theme-warning text-white',
    new: 'bg-theme-success text-white', 
    recommended: 'bg-theme-info text-white'
  } as const;
  
  return Object.prototype.hasOwnProperty.call(classes, priority) ? classes[priority as keyof typeof classes] : 'bg-theme-secondary text-white';
};
/**
 * Status helper utilities
 *
 * Centralized status color and text formatting functions.
 * Use these functions instead of the utilities on individual API objects.
 */

/**
 * Standard color palette for status indicators
 * Maps to Tailwind theme classes
 */
export type StatusColor = 'green' | 'yellow' | 'red' | 'blue' | 'gray' | 'purple' | 'orange';

/**
 * Status color mapping configuration
 */
interface StatusColorMapping {
  [status: string]: StatusColor;
}

// ============================================================
// Invoice Status
// ============================================================

const invoiceStatusColors: StatusColorMapping = {
  paid: 'green',
  open: 'blue',
  sent: 'blue',
  draft: 'gray',
  overdue: 'red',
  void: 'gray',
  uncollectible: 'gray',
  canceled: 'gray',
};

const invoiceStatusText: Record<string, string> = {
  draft: 'Draft',
  open: 'Open',
  sent: 'Sent',
  paid: 'Paid',
  void: 'Void',
  uncollectible: 'Uncollectible',
  overdue: 'Overdue',
  canceled: 'Canceled',
};

/**
 * Gets the display color for an invoice status
 */
export function getInvoiceStatusColor(status: string): StatusColor {
  return invoiceStatusColors[status] ?? 'gray';
}

/**
 * Gets the display text for an invoice status
 */
export function getInvoiceStatusText(status: string): string {
  return invoiceStatusText[status] ?? capitalize(status);
}

// ============================================================
// Customer Status
// ============================================================

const customerStatusColors: StatusColorMapping = {
  active: 'green',
  suspended: 'yellow',
  cancelled: 'red',
  pending: 'blue',
};

const customerStatusText: Record<string, string> = {
  active: 'Active',
  suspended: 'Suspended',
  cancelled: 'Cancelled',
  pending: 'Pending',
};

/**
 * Gets the display color for a customer status
 */
export function getCustomerStatusColor(status: string): StatusColor {
  return customerStatusColors[status] ?? 'gray';
}

/**
 * Gets the display text for a customer status
 */
export function getCustomerStatusText(status: string): string {
  return customerStatusText[status] ?? capitalize(status);
}

// ============================================================
// Subscription Status
// ============================================================

const subscriptionStatusColors: StatusColorMapping = {
  active: 'green',
  trialing: 'blue',
  past_due: 'yellow',
  cancelled: 'red',
  canceled: 'red',
  unpaid: 'red',
  paused: 'yellow',
  incomplete: 'orange',
  incomplete_expired: 'gray',
};

const subscriptionStatusText: Record<string, string> = {
  active: 'Active',
  trialing: 'Trial',
  past_due: 'Past Due',
  cancelled: 'Cancelled',
  canceled: 'Canceled',
  unpaid: 'Unpaid',
  paused: 'Paused',
  incomplete: 'Incomplete',
  incomplete_expired: 'Expired',
};

/**
 * Gets the display color for a subscription status
 */
export function getSubscriptionStatusColor(status: string): StatusColor {
  return subscriptionStatusColors[status] ?? 'gray';
}

/**
 * Gets the display text for a subscription status
 */
export function getSubscriptionStatusText(status: string): string {
  return subscriptionStatusText[status] ?? capitalize(status);
}

// ============================================================
// Payment Status
// ============================================================

const paymentStatusColors: StatusColorMapping = {
  succeeded: 'green',
  paid: 'green',
  processing: 'blue',
  pending: 'yellow',
  failed: 'red',
  refunded: 'gray',
  canceled: 'gray',
  requires_action: 'orange',
  requires_payment_method: 'orange',
};

const paymentStatusText: Record<string, string> = {
  succeeded: 'Succeeded',
  paid: 'Paid',
  processing: 'Processing',
  pending: 'Pending',
  failed: 'Failed',
  refunded: 'Refunded',
  canceled: 'Canceled',
  requires_action: 'Requires Action',
  requires_payment_method: 'Payment Method Required',
};

/**
 * Gets the display color for a payment status
 */
export function getPaymentStatusColor(status: string): StatusColor {
  return paymentStatusColors[status] ?? 'gray';
}

/**
 * Gets the display text for a payment status
 */
export function getPaymentStatusText(status: string): string {
  return paymentStatusText[status] ?? capitalize(status);
}

// ============================================================
// Generic Status Helpers
// ============================================================

/**
 * Generic status color getter
 * Checks all status mappings and returns appropriate color
 */
export function getStatusColor(status: string, domain?: 'invoice' | 'customer' | 'subscription' | 'payment'): StatusColor {
  switch (domain) {
    case 'invoice':
      return getInvoiceStatusColor(status);
    case 'customer':
      return getCustomerStatusColor(status);
    case 'subscription':
      return getSubscriptionStatusColor(status);
    case 'payment':
      return getPaymentStatusColor(status);
    default:
      // Try to find in any mapping
      return (
        invoiceStatusColors[status] ??
        customerStatusColors[status] ??
        subscriptionStatusColors[status] ??
        paymentStatusColors[status] ??
        'gray'
      );
  }
}

/**
 * Generic status text getter
 * Checks all status mappings and returns appropriate text
 */
export function getStatusText(status: string, domain?: 'invoice' | 'customer' | 'subscription' | 'payment'): string {
  switch (domain) {
    case 'invoice':
      return getInvoiceStatusText(status);
    case 'customer':
      return getCustomerStatusText(status);
    case 'subscription':
      return getSubscriptionStatusText(status);
    case 'payment':
      return getPaymentStatusText(status);
    default:
      // Try to find in any mapping
      return (
        invoiceStatusText[status] ??
        customerStatusText[status] ??
        subscriptionStatusText[status] ??
        paymentStatusText[status] ??
        capitalize(status)
      );
  }
}

/**
 * Converts status color to Tailwind background class
 */
export function getStatusBgClass(color: StatusColor): string {
  const bgClasses: Record<StatusColor, string> = {
    green: 'bg-theme-success/10',
    yellow: 'bg-theme-warning/10',
    red: 'bg-theme-danger/10',
    blue: 'bg-theme-info/10',
    gray: 'bg-theme-surface',
    purple: 'bg-theme-info/10',
    orange: 'bg-theme-warning/10',
  };
  return bgClasses[color];
}

/**
 * Converts status color to Tailwind text class
 */
export function getStatusTextClass(color: StatusColor): string {
  const textClasses: Record<StatusColor, string> = {
    green: 'text-theme-success',
    yellow: 'text-theme-warning',
    red: 'text-theme-danger',
    blue: 'text-theme-info',
    gray: 'text-theme-secondary',
    purple: 'text-theme-info',
    orange: 'text-theme-warning',
  };
  return textClasses[color];
}

/**
 * Converts status color to Tailwind border class
 */
export function getStatusBorderClass(color: StatusColor): string {
  const borderClasses: Record<StatusColor, string> = {
    green: 'border-theme-success/30',
    yellow: 'border-theme-warning/30',
    red: 'border-theme-danger/30',
    blue: 'border-theme-info/30',
    gray: 'border-theme',
    purple: 'border-theme-info/30',
    orange: 'border-theme-warning/30',
  };
  return borderClasses[color];
}

/**
 * Gets complete status badge classes
 */
export function getStatusBadgeClasses(color: StatusColor): string {
  return `${getStatusBgClass(color)} ${getStatusTextClass(color)} ${getStatusBorderClass(color)}`;
}

// ============================================================
// Helper Functions
// ============================================================

/**
 * Capitalizes first letter of a string
 */
function capitalize(str: string): string {
  if (!str) return '';
  return str.charAt(0).toUpperCase() + str.slice(1).replace(/_/g, ' ');
}

/**
 * Checks if a status is considered "active" or positive
 */
export function isPositiveStatus(status: string): boolean {
  const positiveStatuses = ['active', 'paid', 'succeeded', 'completed', 'approved'];
  return positiveStatuses.includes(status.toLowerCase());
}

/**
 * Checks if a status is considered "negative" or problematic
 */
export function isNegativeStatus(status: string): boolean {
  const negativeStatuses = ['failed', 'cancelled', 'canceled', 'overdue', 'unpaid', 'rejected', 'expired'];
  return negativeStatuses.includes(status.toLowerCase());
}

/**
 * Checks if a status requires attention
 */
export function requiresAttention(status: string): boolean {
  const attentionStatuses = ['pending', 'past_due', 'requires_action', 'incomplete', 'suspended'];
  return attentionStatuses.includes(status.toLowerCase());
}

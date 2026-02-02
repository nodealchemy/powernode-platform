import { api } from '@/shared/services/api';
import { getErrorMessage } from '@/shared/utils/errorHandling';

export interface SubscriptionHistoryEvent {
  id: string;
  event_type: string;
  action: string;
  summary: string;
  changes: string | null;
  old_values: Record<string, any>;
  new_values: Record<string, any>;
  metadata: Record<string, any>;
  user: {
    id: string;
    name: string;
    email: string;
  } | null;
  created_at: string;
  source: string;
}

export interface SubscriptionHistoryResponse {
   
  current_subscription: any | null;
  history: SubscriptionHistoryEvent[];
  total_events: number;
}

export interface SubscriptionHistoryApiResponse extends SubscriptionHistoryResponse {
  error?: string;
}

export const subscriptionHistoryApi = {
  async getHistory(): Promise<SubscriptionHistoryApiResponse> {
    try {
      const response = await api.get('/api/v1/subscriptions/history');
      return response.data.data;
    } catch {
      const message = getErrorMessage(error);
      return { current_subscription: null, history: [], total_events: 0, error: message };
    }
  },

  formatEventType(eventType: string): string {
    const eventTypeMap: Record<string, string> = {
      'subscription_created': 'Subscription Created',
      'trial_started': 'Trial Started',
      'trial_converted': 'Trial Converted',
      'subscription_activated': 'Subscription Activated',
      'plan_changed': 'Plan Changed',
      'quantity_changed': 'Quantity Changed',
      'subscription_canceled': 'Subscription Canceled',
      'payment_failed': 'Payment Failed',
      'status_changed': 'Status Changed',
      'subscription_updated': 'Subscription Updated',
      'payment': 'Payment Processed',
      'create': 'Created',
      'update': 'Updated'
    };

    return Object.keys(eventTypeMap).includes(eventType) 
      ? eventTypeMap[eventType as keyof typeof eventTypeMap] 
      : eventType.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase());
  },

  getEventIcon(eventType: string): string {
    const iconMap: Record<string, string> = {
      'subscription_created': '🎯',
      'trial_started': '🚀',
      'trial_converted': '✅',
      'subscription_activated': '✅',
      'plan_changed': '📈',
      'quantity_changed': '🔢',
      'subscription_canceled': '❌',
      'payment_failed': '⚠️',
      'payment': '💳',
      'status_changed': '🔄',
      'create': '➕',
      'update': '📝'
    };

    return Object.keys(iconMap).includes(eventType) 
      ? iconMap[eventType as keyof typeof iconMap] 
      : '📋';
  },

  getEventColor(eventType: string): string {
    const colorMap: Record<string, string> = {
      'subscription_created': 'text-theme-success',
      'trial_started': 'text-theme-info',
      'trial_converted': 'text-theme-success',
      'subscription_activated': 'text-theme-success',
      'plan_changed': 'text-theme-info',
      'quantity_changed': 'text-theme-info',
      'subscription_canceled': 'text-theme-error',
      'payment_failed': 'text-theme-error',
      'payment': 'text-theme-success',
      'status_changed': 'text-theme-warning',
      'create': 'text-theme-success',
      'update': 'text-theme-info'
    };

    return Object.keys(colorMap).includes(eventType) 
      ? colorMap[eventType as keyof typeof colorMap] 
      : 'text-theme-secondary';
  },

  formatDate(dateString: string): string {
    return new Date(dateString).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  },

  formatRelativeTime(dateString: string): string {
    const date = new Date(dateString);
    const now = new Date();
    const diffInSeconds = Math.floor((now.getTime() - date.getTime()) / 1000);

    if (diffInSeconds < 60) {
      return 'just now';
    }

    const diffInMinutes = Math.floor(diffInSeconds / 60);
    if (diffInMinutes < 60) {
      return `${diffInMinutes} minute${diffInMinutes > 1 ? 's' : ''} ago`;
    }

    const diffInHours = Math.floor(diffInMinutes / 60);
    if (diffInHours < 24) {
      return `${diffInHours} hour${diffInHours > 1 ? 's' : ''} ago`;
    }

    const diffInDays = Math.floor(diffInHours / 24);
    if (diffInDays < 7) {
      return `${diffInDays} day${diffInDays > 1 ? 's' : ''} ago`;
    }

    const diffInWeeks = Math.floor(diffInDays / 7);
    if (diffInWeeks < 4) {
      return `${diffInWeeks} week${diffInWeeks > 1 ? 's' : ''} ago`;
    }

    return this.formatDate(dateString);
  },

  getEventDetails(event: SubscriptionHistoryEvent): string {
    if (event.changes) {
      return event.changes;
    }

    if (event.event_type === 'payment' && event.new_values.amount_cents) {
      return `$${(event.new_values.amount_cents / 100).toFixed(2)} - ${event.new_values.status}`;
    }

    if (event.event_type === 'plan_changed') {
      const oldPlan = event.old_values.plan;
      const newPlan = event.new_values.plan;
      if (oldPlan && newPlan) {
        return `Changed from ${oldPlan} to ${newPlan}`;
      }
    }

    return event.summary;
  }
};
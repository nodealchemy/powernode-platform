// Git Webhook Event Types

import type { PaginationInfo } from './repositories';

export interface GitWebhookEvent {
  id: string;
  event_type: string;
  action?: string;
  status: 'pending' | 'processing' | 'processed' | 'failed';
  delivery_id?: string;
  sender_username?: string;
  ref?: string;
  branch_name?: string;
  sha?: string;
  short_sha?: string;
  summary?: string;
  retry_count: number;
  retryable: boolean;
  processed_at?: string;
  created_at: string;
  repository?: {
    id: string;
    name: string;
    full_name: string;
  };
  provider: {
    id: string;
    name: string;
    type: string;
  };
}

export interface GitWebhookEventDetail extends GitWebhookEvent {
  payload: Record<string, unknown>;
  headers: Record<string, string>;
  error_message?: string;
  processing_result?: Record<string, unknown>;
  sender_info?: Record<string, unknown>;
}

export interface WebhookEventStats {
  total_events: number;
  pending: number;
  processed: number;
  failed: number;
  today_count: number;
  today_processed: number;
  today_failed: number;
}

export interface GitWebhookEventsResponse {
  events: GitWebhookEvent[];
  pagination: PaginationInfo;
  stats: WebhookEventStats;
}

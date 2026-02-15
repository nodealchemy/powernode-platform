/**
 * Marketing Module Types
 */

// --- Enums / Literal Unions ---

export type CampaignStatus = 'draft' | 'scheduled' | 'active' | 'paused' | 'completed' | 'archived';
export type CampaignType = 'email' | 'social' | 'multi_channel' | 'sms' | 'push';
export type ChannelType = 'email' | 'twitter' | 'linkedin' | 'facebook' | 'instagram' | 'sms' | 'push';
export type ContentStatus = 'draft' | 'review' | 'approved' | 'published';
export type SubscriberStatus = 'active' | 'unsubscribed' | 'bounced' | 'pending';
export type SocialPlatform = 'twitter' | 'linkedin' | 'facebook' | 'instagram' | 'youtube' | 'tiktok';
export type SocialAccountStatus = 'connected' | 'disconnected' | 'expired' | 'error';
export type CalendarEntryType = 'post' | 'campaign_launch' | 'email_blast' | 'deadline' | 'milestone';

// --- Core Models ---

export interface Campaign {
  id: string;
  name: string;
  description: string;
  campaign_type: CampaignType;
  status: CampaignStatus;
  channels: ChannelType[];
  scheduled_at: string | null;
  started_at: string | null;
  completed_at: string | null;
  budget_cents: number;
  spent_cents: number;
  target_audience: string;
  tags: string[];
  created_by_id: string;
  created_by_name: string;
  contents_count: number;
  metrics_summary: CampaignMetricsSummary | null;
  created_at: string;
  updated_at: string;
}

export interface CampaignMetricsSummary {
  impressions: number;
  clicks: number;
  conversions: number;
  click_rate: number;
  conversion_rate: number;
  revenue_cents: number;
}

export interface CampaignContent {
  id: string;
  campaign_id: string;
  channel: ChannelType;
  subject: string;
  body: string;
  html_body: string | null;
  media_urls: string[];
  status: ContentStatus;
  scheduled_at: string | null;
  published_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface ContentCalendarEntry {
  id: string;
  title: string;
  description: string;
  entry_type: CalendarEntryType;
  channel: ChannelType | null;
  campaign_id: string | null;
  campaign_name: string | null;
  scheduled_date: string;
  scheduled_time: string | null;
  status: ContentStatus;
  color: string | null;
  created_at: string;
  updated_at: string;
}

export interface EmailList {
  id: string;
  name: string;
  description: string;
  subscriber_count: number;
  active_subscriber_count: number;
  tags: string[];
  double_opt_in: boolean;
  created_at: string;
  updated_at: string;
}

export interface EmailSubscriber {
  id: string;
  email_list_id: string;
  email: string;
  first_name: string | null;
  last_name: string | null;
  status: SubscriberStatus;
  subscribed_at: string;
  unsubscribed_at: string | null;
  metadata: Record<string, string>;
  created_at: string;
  updated_at: string;
}

export interface SocialMediaAccount {
  id: string;
  platform: SocialPlatform;
  account_name: string;
  account_handle: string;
  profile_url: string;
  avatar_url: string | null;
  status: SocialAccountStatus;
  followers_count: number;
  token_expires_at: string | null;
  last_synced_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface CampaignMetric {
  id: string;
  campaign_id: string;
  channel: ChannelType;
  date: string;
  impressions: number;
  clicks: number;
  conversions: number;
  unsubscribes: number;
  bounces: number;
  revenue_cents: number;
  cost_cents: number;
  created_at: string;
}

// --- Form Data ---

export interface CampaignFormData {
  name: string;
  description: string;
  campaign_type: CampaignType;
  channels: ChannelType[];
  scheduled_at: string | null;
  budget_cents: number;
  target_audience: string;
  tags: string[];
}

export interface ContentFormData {
  channel: ChannelType;
  subject: string;
  body: string;
  html_body: string | null;
  media_urls: string[];
  scheduled_at: string | null;
}

export interface CalendarEntryFormData {
  title: string;
  description: string;
  entry_type: CalendarEntryType;
  channel: ChannelType | null;
  campaign_id: string | null;
  scheduled_date: string;
  scheduled_time: string | null;
  color: string | null;
}

export interface EmailListFormData {
  name: string;
  description: string;
  tags: string[];
  double_opt_in: boolean;
}

// --- Analytics ---

export interface CampaignStatistics {
  total_campaigns: number;
  active_campaigns: number;
  completed_campaigns: number;
  total_impressions: number;
  total_clicks: number;
  total_conversions: number;
  overall_click_rate: number;
  overall_conversion_rate: number;
  total_revenue_cents: number;
  total_spent_cents: number;
  roi_percentage: number;
  campaigns_by_status: Record<CampaignStatus, number>;
  campaigns_by_type: Record<CampaignType, number>;
}

export interface AnalyticsOverview {
  period_start: string;
  period_end: string;
  total_campaigns: number;
  total_impressions: number;
  total_clicks: number;
  total_conversions: number;
  total_revenue_cents: number;
  total_spent_cents: number;
  roi_percentage: number;
  impressions_trend: TrendPoint[];
  conversions_trend: TrendPoint[];
  revenue_trend: TrendPoint[];
}

export interface TrendPoint {
  date: string;
  value: number;
}

export interface ChannelAnalytics {
  channel: ChannelType;
  impressions: number;
  clicks: number;
  conversions: number;
  click_rate: number;
  conversion_rate: number;
  revenue_cents: number;
  cost_cents: number;
  roi_percentage: number;
}

export interface TopPerformer {
  campaign_id: string;
  campaign_name: string;
  campaign_type: CampaignType;
  impressions: number;
  clicks: number;
  conversions: number;
  revenue_cents: number;
  roi_percentage: number;
}

// --- API Pagination ---

export interface Pagination {
  current_page: number;
  per_page: number;
  total_pages: number;
  total_count: number;
}

export interface ApiResponse<T> {
  success: boolean;
  data: T;
}

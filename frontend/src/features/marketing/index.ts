// Marketing Feature - Barrel Export

// Components
export { CampaignDashboard } from './components/CampaignDashboard';
export { CampaignEditor } from './components/CampaignEditor';
export { CampaignDetail } from './components/CampaignDetail';
export { CampaignContentEditor } from './components/CampaignContentEditor';
export { CampaignContentPreview } from './components/CampaignContentPreview';
export { CampaignStatusBadge } from './components/CampaignStatusBadge';
export { ContentCalendar } from './components/ContentCalendar';
export { ContentCalendarEntry } from './components/ContentCalendarEntry';
export { EmailListManager } from './components/EmailListManager';
export { EmailSubscriberTable } from './components/EmailSubscriberTable';
export { EmailListImportModal } from './components/EmailListImportModal';
export { SocialMediaManager } from './components/SocialMediaManager';
export { SocialAccountCard } from './components/SocialAccountCard';
export { ConnectSocialModal } from './components/ConnectSocialModal';
export { CampaignAnalytics } from './components/CampaignAnalytics';
export { CampaignROIChart } from './components/CampaignROIChart';
export { ChannelPerformanceChart } from './components/ChannelPerformanceChart';
export { AiContentGenerator } from './components/AiContentGenerator';

// Hooks
export { useCampaigns, useCampaign } from './hooks/useCampaigns';
export { useContentCalendar } from './hooks/useContentCalendar';
export { useEmailLists, useSubscribers } from './hooks/useEmailLists';
export { useSocialAccounts } from './hooks/useSocialAccounts';
export {
  useAnalyticsOverview,
  useChannelAnalytics,
  useRoiAnalytics,
  useTopPerformers,
  useCampaignMetrics,
} from './hooks/useCampaignAnalytics';
export { useCampaignContents } from './hooks/useCampaignContents';

// Services
export { campaignsApi } from './services/campaignsApi';
export { contentCalendarApi } from './services/contentCalendarApi';
export { emailListsApi } from './services/emailListsApi';
export { socialAccountsApi } from './services/socialAccountsApi';
export { analyticsApi } from './services/analyticsApi';

// Types
export type {
  Campaign,
  CampaignContent,
  ContentCalendarEntry as ContentCalendarEntryType,
  EmailList,
  EmailSubscriber,
  SocialMediaAccount,
  CampaignMetric,
  CampaignFormData,
  ContentFormData,
  CalendarEntryFormData,
  EmailListFormData,
  CampaignStatistics,
  AnalyticsOverview,
  ChannelAnalytics,
} from './types';

import { lazy } from 'react';
import { featureRegistry } from '@/shared/services/featureRegistry';

// Lazy-loaded admin marketing page components (rendered inside /app/* via DashboardPage)
const MarketingCampaignsPage = lazy(() => import('./features/marketing/pages/MarketingCampaignsPage').then(m => ({ default: m.MarketingCampaignsPage })));
const MarketingCampaignDetailPage = lazy(() => import('./features/marketing/pages/MarketingCampaignDetailPage').then(m => ({ default: m.MarketingCampaignDetailPage })));
const MarketingCalendarPage = lazy(() => import('./features/marketing/pages/MarketingCalendarPage').then(m => ({ default: m.MarketingCalendarPage })));
const MarketingEmailListsPage = lazy(() => import('./features/marketing/pages/MarketingEmailListsPage').then(m => ({ default: m.MarketingEmailListsPage })));
const MarketingSocialPage = lazy(() => import('./features/marketing/pages/MarketingSocialPage').then(m => ({ default: m.MarketingSocialPage })));
const MarketingAnalyticsPage = lazy(() => import('./features/marketing/pages/MarketingAnalyticsPage').then(m => ({ default: m.MarketingAnalyticsPage })));

// Lazy-loaded PUBLIC marketing page components (rendered at root domain, no auth)
const HomePage = lazy(() => import('./features/marketing/public/HomePage').then(m => ({ default: m.HomePage })));
const PricingPage = lazy(() => import('./features/marketing/public/PricingPage').then(m => ({ default: m.PricingPage })));
const FeaturesPage = lazy(() => import('./features/marketing/public/FeaturesPage').then(m => ({ default: m.FeaturesPage })));
const BlogIndexPage = lazy(() => import('./features/marketing/public/BlogIndexPage').then(m => ({ default: m.BlogIndexPage })));
const BlogPostPage = lazy(() => import('./features/marketing/public/BlogPostPage').then(m => ({ default: m.BlogPostPage })));
const DocsLandingPage = lazy(() => import('./features/marketing/public/DocsLandingPage').then(m => ({ default: m.DocsLandingPage })));

export function register(): void {
  // Public-facing marketing routes (rendered by App.tsx, no authentication required)
  // These override App.tsx defaults like the `/` -> `/welcome` redirect when present.
  featureRegistry.registerPublicRoutes('marketing', [
    { path: '/', component: HomePage },
    { path: '/pricing', component: PricingPage },
    { path: '/features', component: FeaturesPage },
    { path: '/blog', component: BlogIndexPage },
    { path: '/blog/:slug', component: BlogPostPage },
    { path: '/docs', component: DocsLandingPage },
  ]);

  // Marketing routes — rendered dynamically via featureRegistry in DashboardPage
  featureRegistry.registerRoutes('marketing', [
    { path: '/marketing/campaigns', component: MarketingCampaignsPage, permission: 'marketing.campaigns.read' },
    { path: '/marketing/campaigns/:id', component: MarketingCampaignDetailPage, permission: 'marketing.campaigns.read' },
    { path: '/marketing/calendar', component: MarketingCalendarPage, permission: 'marketing.calendar.read' },
    { path: '/marketing/email-lists', component: MarketingEmailListsPage, permission: 'marketing.email_lists.read' },
    { path: '/marketing/social', component: MarketingSocialPage, permission: 'marketing.social.read' },
    { path: '/marketing/analytics', component: MarketingAnalyticsPage, permission: 'marketing.analytics.read' },
  ]);

  // Marketing navigation section
  featureRegistry.registerNavSections('marketing', [{
    id: 'marketing',
    name: 'Marketing',
    permissions: ['marketing.campaigns.read', 'marketing.calendar.read', 'marketing.email_lists.read', 'marketing.social.read', 'marketing.analytics.read'],
    collapsible: true,
    defaultExpanded: true,
    order: 16,
    items: [
      { label: 'Campaigns', path: '/app/marketing/campaigns', icon: 'Megaphone', permission: 'marketing.campaigns.read', order: 1 },
      { label: 'Calendar', path: '/app/marketing/calendar', icon: 'CalendarDays', permission: 'marketing.calendar.read', order: 2 },
      { label: 'Email Lists', path: '/app/marketing/email-lists', icon: 'Mail', permission: 'marketing.email_lists.read', order: 3 },
      { label: 'Social', path: '/app/marketing/social', icon: 'Share2', permission: 'marketing.social.read', order: 4 },
      { label: 'Analytics', path: '/app/marketing/analytics', icon: 'TrendingUp', permission: 'marketing.analytics.read', order: 5 },
    ],
  }]);
}

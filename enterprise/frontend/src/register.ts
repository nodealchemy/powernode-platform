import { lazy } from 'react';
import { featureRegistry } from '@/shared/services/featureRegistry';

// Lazy-loaded enterprise page components
const BaaSDashboard = lazy(() => import('./features/baas/pages/BaaSDashboard'));
const ResellerDashboard = lazy(() => import('./features/business/reseller/pages/ResellerDashboard'));
const PublisherDashboard = lazy(() => import('./features/ai/publisher/pages/PublisherDashboard'));
const TemplateAnalytics = lazy(() => import('./features/ai/publisher/pages/TemplateAnalytics'));
const AdminImpersonationPage = lazy(() => import('./features/admin/AdminImpersonationPage'));

// Business section pages (enterprise-only)
const CustomersPage = lazy(() => import('./pages/business/CustomersPage'));
const PlansPage = lazy(() => import('./pages/business/PlansPage'));
const AnalyticsPage = lazy(() => import('./pages/business/AnalyticsPage'));
const ReportsPage = lazy(() => import('./pages/business/ReportsPage'));
const MetricsPage = lazy(() => import('./pages/business/MetricsPage'));

// Billing & subscription pages (enterprise-only)
const BillingPage = lazy(() => import('./pages/business/BillingPage'));
const PlanSelectionPage = lazy(() => import('./pages/public/PlanSelectionPage'));
const RegisterPage = lazy(() => import('./pages/public/RegisterPage'));

export function registerEnterpriseFeatures(): void {
  // Enterprise routes rendered dynamically in DashboardPage
  featureRegistry.registerRoutes('enterprise', [
    { path: '/baas/*', component: BaaSDashboard, permission: 'baas.manage' },
    { path: '/business/reseller/*', component: ResellerDashboard, permission: 'reseller.manage' },
    { path: '/ai/publisher', component: PublisherDashboard, permission: 'ai.publisher.manage' },
    { path: '/ai/publisher/analytics', component: TemplateAnalytics, permission: 'ai.publisher.manage' },
    { path: '/admin/impersonation', component: AdminImpersonationPage, permission: 'admin.impersonate' },
    // Business section (enterprise-only)
    { path: '/business/customers', component: CustomersPage },
    { path: '/business/plans/*', component: PlansPage },
    { path: '/business/analytics/*', component: AnalyticsPage },
    { path: '/business/reports/*', component: ReportsPage },
    { path: '/metrics', component: MetricsPage },
    // Billing & subscription routes
    { path: '/account/billing/*', component: BillingPage },
  ]);

  featureRegistry.registerNavItems('enterprise', [
    { label: 'BaaS', path: '/app/baas', permission: 'baas.manage', section: 'enterprise' },
    { label: 'Governance', path: '/app/ai/governance', permission: 'ai.governance.manage', section: 'ai' },
    { label: 'Reseller', path: '/app/business/reseller', permission: 'reseller.manage', section: 'business' },
  ]);
}

import React from 'react';
import { Breadcrumb } from '@/shared/components/ui/Breadcrumb';

export interface BreadcrumbItem {
  label: string;
  path?: string;
  icon: string;
}

interface PageBreadcrumbProps {
  items: BreadcrumbItem[];
  className?: string;
}

export const PageBreadcrumb: React.FC<PageBreadcrumbProps> = ({ items, className = "mb-4" }) => {
PageBreadcrumb.displayName = 'PageBreadcrumb';
  return <Breadcrumb items={items} className={className} />;
};

// Common breadcrumb patterns for reuse
export const dashboardBreadcrumb: BreadcrumbItem = {
  label: 'Dashboard',
  path: '/app',
  icon: '🏠'
};

export const createBreadcrumbItems = (pageLabel: string, pageIcon: string): BreadcrumbItem[] => [
  dashboardBreadcrumb,
  { label: pageLabel, icon: pageIcon }
];

// Predefined breadcrumbs for common pages
export const breadcrumbConfigs = {
  account: createBreadcrumbItems('Account', '👤'),
  analytics: createBreadcrumbItems('Analytics', '📊'),
  business: createBreadcrumbItems('Customer Management', '👥'),
  system: createBreadcrumbItems('System Settings', '⚙️'),
  plans: createBreadcrumbItems('Plans', '📋'),
  pages: createBreadcrumbItems('Pages', '📄'),
  customers: createBreadcrumbItems('Customers', '👥'),
  billing: createBreadcrumbItems('Billing', '💳'),
  settings: createBreadcrumbItems('Settings', '⚙️'),
  subscriptions: createBreadcrumbItems('Subscriptions', '🔄'),
  workers: createBreadcrumbItems('Workers', '🤖'),
  paymentGateways: createBreadcrumbItems('Payment Gateways', '💳')
};
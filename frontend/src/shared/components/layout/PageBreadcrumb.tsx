import React from 'react';
import { Breadcrumb } from '@/shared/components/ui/Breadcrumb';

export interface BreadcrumbItem {
  label: string;
  path?: string;
}

interface PageBreadcrumbProps {
  items: BreadcrumbItem[];
  className?: string;
}

export const PageBreadcrumb: React.FC<PageBreadcrumbProps> = ({ items, className = "mb-4" }) => {
  return <Breadcrumb items={items} className={className} />;
};

// Common breadcrumb patterns for reuse
export const dashboardBreadcrumb: BreadcrumbItem = {
  label: 'Dashboard',
  path: '/app'
};

export const createBreadcrumbItems = (pageLabel: string): BreadcrumbItem[] => [
  dashboardBreadcrumb,
  { label: pageLabel }
];

// Predefined breadcrumbs for common pages
export const breadcrumbConfigs = {
  account: createBreadcrumbItems('Account'),
  analytics: createBreadcrumbItems('Analytics'),
  business: createBreadcrumbItems('Customer Management'),
  system: createBreadcrumbItems('System Settings'),
  plans: createBreadcrumbItems('Plans'),
  pages: createBreadcrumbItems('Pages'),
  customers: createBreadcrumbItems('Customers'),
  billing: createBreadcrumbItems('Billing'),
  settings: createBreadcrumbItems('Settings'),
  subscriptions: createBreadcrumbItems('Subscriptions'),
  workers: createBreadcrumbItems('Workers'),
  paymentGateways: createBreadcrumbItems('Payment Gateways')
};
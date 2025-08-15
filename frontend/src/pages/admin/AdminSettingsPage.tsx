// Main Admin Settings Page with Tabbed Interface
import React from 'react';
import { Routes, Route, Navigate } from 'react-router-dom';
import { SharedBreadcrumbs } from '../../components/common/SharedBreadcrumbs';
import { AdminSettingsTabs } from '../../components/admin/settings/AdminSettingsTabs';

// Import all admin settings tab pages
import { AdminSettingsOverviewTabPage } from '../../admin/pages/AdminSettingsOverviewTabPage';
import { AdminSettingsPaymentGatewaysTabPage } from '../../admin/pages/AdminSettingsPaymentGatewaysTabPage';
import { AdminSettingsWebhooksTabPage } from '../../admin/pages/AdminSettingsWebhooksTabPage';
import { AdminSettingsEmailTabPage } from '../../admin/pages/AdminSettingsEmailTabPage';
import { AdminSettingsSecurityTabPage } from '../../admin/pages/AdminSettingsSecurityTabPage';
import { AdminSettingsMaintenanceTabPage } from '../../admin/pages/AdminSettingsMaintenanceTabPage';
import { AdminSettingsPerformanceTabPage } from '../../admin/pages/AdminSettingsPerformanceTabPage';

export const AdminSettingsPage: React.FC = () => {
  return (
    <div className="space-y-6">
      {/* Breadcrumbs */}
      <SharedBreadcrumbs />

      {/* Tabbed Interface */}
      <AdminSettingsTabs />

      {/* Tab Content */}
      <div className="mt-6">
        <Routes>
          {/* Default - Admin Settings Overview */}
          <Route path="/" element={<AdminSettingsOverviewTabPage />} />
          <Route path="/overview" element={<Navigate to="/dashboard/admin-settings" replace />} />
          
          {/* Admin Settings Tabs */}
          <Route path="/payment-gateways" element={<AdminSettingsPaymentGatewaysTabPage />} />
          <Route path="/webhooks" element={<AdminSettingsWebhooksTabPage />} />
          <Route path="/email" element={<AdminSettingsEmailTabPage />} />
          <Route path="/security" element={<AdminSettingsSecurityTabPage />} />
          <Route path="/maintenance" element={<AdminSettingsMaintenanceTabPage />} />
          <Route path="/performance" element={<AdminSettingsPerformanceTabPage />} />
          
          {/* Legacy redirects */}
          <Route path="/admin/*" element={<Navigate to="/dashboard/admin-settings" replace />} />
          
          {/* Catch all - redirect to overview */}
          <Route path="*" element={<Navigate to="/dashboard/admin-settings" replace />} />
        </Routes>
      </div>
    </div>
  );
};

// No default export - use named export only
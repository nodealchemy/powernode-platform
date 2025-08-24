import React from 'react';
import { AdminSettingsOverviewPage } from './AdminSettingsOverviewPage';

export const AdminSettingsOverviewTabPage: React.FC = () => {
AdminSettingsOverviewTabPage.displayName = 'AdminSettingsOverviewTabPage';
  return (
    <div className="bg-theme-surface rounded-lg border border-theme">
      <div className="p-6">
        <AdminSettingsOverviewPage />
      </div>
    </div>
  );
};

export default AdminSettingsOverviewTabPage;
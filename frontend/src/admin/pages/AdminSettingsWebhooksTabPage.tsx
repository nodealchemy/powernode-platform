import React from 'react';
import WebhookManagementPage from '../../pages/system/WebhookManagementPage';

export const AdminSettingsWebhooksTabPage: React.FC = () => {
  return (
    <div className="bg-theme-surface rounded-lg border border-theme">
      <div className="p-6">
        <WebhookManagementPage />
      </div>
    </div>
  );
};

export default AdminSettingsWebhooksTabPage;
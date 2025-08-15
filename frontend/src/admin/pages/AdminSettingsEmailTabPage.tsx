import React from 'react';
import { EmailConfiguration } from '../components/settings/EmailConfiguration';

export const AdminSettingsEmailTabPage: React.FC = () => {
  return (
    <div className="bg-theme-surface rounded-lg border border-theme">
      <div className="p-6">
        <EmailConfiguration />
      </div>
    </div>
  );
};

export default AdminSettingsEmailTabPage;
import React from 'react';
import { PlatformConfiguration } from '@/features/admin/components/settings/PlatformConfiguration';

export const AdminSettingsPlatformTabPage: React.FC = () => {
  return (
    <div className="bg-theme-surface rounded-lg border border-theme">
      <div className="p-6">
        <PlatformConfiguration />
      </div>
    </div>
  );
};

export default AdminSettingsPlatformTabPage;
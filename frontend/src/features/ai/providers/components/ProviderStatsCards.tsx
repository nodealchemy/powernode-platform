import React from 'react';
import { Settings, Zap, AlertCircle } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';

interface ProviderStatsCardsProps {
  totalCount: number;
  healthyCount: number;
  priorityCount: number;
  credentialCount: number;
}

export const ProviderStatsCards: React.FC<ProviderStatsCardsProps> = ({
  totalCount,
  healthyCount,
  priorityCount,
  credentialCount,
}) => {
  return (
    <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
      <Card className="p-4">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-sm text-theme-tertiary">Total Providers</p>
            <p className="text-2xl font-semibold text-theme-primary">{totalCount}</p>
          </div>
          <div className="h-10 w-10 bg-theme-info bg-opacity-10 rounded-lg flex items-center justify-center">
            <Settings className="h-5 w-5 text-theme-info" />
          </div>
        </div>
      </Card>

      <Card className="p-4">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-sm text-theme-tertiary">Healthy Providers</p>
            <p className="text-2xl font-semibold text-theme-primary">{healthyCount}</p>
          </div>
          <div className="h-10 w-10 bg-theme-success bg-opacity-10 rounded-lg flex items-center justify-center">
            <Zap className="h-5 w-5 text-theme-success" />
          </div>
        </div>
      </Card>

      <Card className="p-4">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-sm text-theme-tertiary">Priority Providers</p>
            <p className="text-2xl font-semibold text-theme-primary">{priorityCount}</p>
          </div>
          <div className="h-10 w-10 bg-theme-warning bg-opacity-10 rounded-lg flex items-center justify-center">
            <AlertCircle className="h-5 w-5 text-theme-warning" />
          </div>
        </div>
      </Card>

      <Card className="p-4">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-sm text-theme-tertiary">Active Credentials</p>
            <p className="text-2xl font-semibold text-theme-primary">{credentialCount}</p>
          </div>
          <div className="h-10 w-10 bg-theme-info bg-opacity-10 rounded-lg flex items-center justify-center">
            <Settings className="h-5 w-5 text-theme-info" />
          </div>
        </div>
      </Card>
    </div>
  );
};

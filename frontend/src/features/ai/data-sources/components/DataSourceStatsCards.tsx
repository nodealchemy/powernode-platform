import React from 'react';
import { Database, Zap, Lock, Key } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';

interface DataSourceStatsCardsProps {
  totalCount: number;
  healthyCount: number;
  requiresAuthCount: number;
  credentialCount: number;
}

export const DataSourceStatsCards: React.FC<DataSourceStatsCardsProps> = ({
  totalCount,
  healthyCount,
  requiresAuthCount,
  credentialCount,
}) => {
  return (
    <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
      <Card className="p-4">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-sm text-theme-tertiary">Total Sources</p>
            <p className="text-2xl font-semibold text-theme-primary">{totalCount}</p>
          </div>
          <div className="h-10 w-10 bg-theme-info-bg rounded-lg flex items-center justify-center">
            <Database className="h-5 w-5 text-theme-info-fg" />
          </div>
        </div>
      </Card>

      <Card className="p-4">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-sm text-theme-tertiary">Healthy</p>
            <p className="text-2xl font-semibold text-theme-primary">{healthyCount}</p>
          </div>
          <div className="h-10 w-10 bg-theme-success-bg rounded-lg flex items-center justify-center">
            <Zap className="h-5 w-5 text-theme-success-fg" />
          </div>
        </div>
      </Card>

      <Card className="p-4">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-sm text-theme-tertiary">Requires Auth</p>
            <p className="text-2xl font-semibold text-theme-primary">{requiresAuthCount}</p>
          </div>
          <div className="h-10 w-10 bg-theme-warning-bg rounded-lg flex items-center justify-center">
            <Lock className="h-5 w-5 text-theme-warning-fg" />
          </div>
        </div>
      </Card>

      <Card className="p-4">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-sm text-theme-tertiary">Credentials</p>
            <p className="text-2xl font-semibold text-theme-primary">{credentialCount}</p>
          </div>
          <div className="h-10 w-10 bg-theme-info-bg rounded-lg flex items-center justify-center">
            <Key className="h-5 w-5 text-theme-info-fg" />
          </div>
        </div>
      </Card>
    </div>
  );
};

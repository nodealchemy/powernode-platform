import React from 'react';
import { Card } from '@/shared/components/ui/Card';

interface SwarmStatsCardsProps {
  nodeCount: number;
  nodesReady: number;
  serviceCount: number;
  servicesHealthy: number;
  avgHealth: number;
  criticalEvents: number;
  warningEvents: number;
  isLoading?: boolean;
}

export const SwarmStatsCards: React.FC<SwarmStatsCardsProps> = ({
  nodeCount,
  nodesReady,
  serviceCount,
  servicesHealthy,
  avgHealth,
  criticalEvents,
  warningEvents,
  isLoading,
}) => {
  if (isLoading) {
    return (
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <Card key={i} variant="default" padding="md">
            <div className="animate-pulse space-y-2">
              <div className="h-3 bg-theme-surface rounded w-16" />
              <div className="h-6 bg-theme-surface rounded w-12" />
            </div>
          </Card>
        ))}
      </div>
    );
  }

  return (
    <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
      <Card variant="default" padding="md">
        <p className="text-xs text-theme-tertiary mb-1">Nodes</p>
        <p className="text-2xl font-bold text-theme-primary">{nodesReady}/{nodeCount}</p>
        <p className="text-xs text-theme-secondary mt-1">Ready</p>
      </Card>
      <Card variant="default" padding="md">
        <p className="text-xs text-theme-tertiary mb-1">Services</p>
        <p className="text-2xl font-bold text-theme-primary">{servicesHealthy}/{serviceCount}</p>
        <p className="text-xs text-theme-secondary mt-1">Healthy</p>
      </Card>
      <Card variant="default" padding="md">
        <p className="text-xs text-theme-tertiary mb-1">Avg Health</p>
        <p className={`text-2xl font-bold ${
          avgHealth >= 100 ? 'text-theme-success' :
          avgHealth >= 50 ? 'text-theme-warning' :
          'text-theme-error'
        }`}>
          {Math.round(avgHealth)}%
        </p>
        <p className="text-xs text-theme-secondary mt-1">Cluster-wide</p>
      </Card>
      <Card variant="default" padding="md">
        <p className="text-xs text-theme-tertiary mb-1">Events</p>
        <div className="flex items-baseline gap-2">
          {criticalEvents > 0 && (
            <span className="text-lg font-bold text-theme-error">{criticalEvents}</span>
          )}
          {warningEvents > 0 && (
            <span className="text-lg font-bold text-theme-warning">{warningEvents}</span>
          )}
          {criticalEvents === 0 && warningEvents === 0 && (
            <span className="text-lg font-bold text-theme-success">0</span>
          )}
        </div>
        <p className="text-xs text-theme-secondary mt-1">
          {criticalEvents > 0 ? 'Critical' : warningEvents > 0 ? 'Warnings' : 'All clear'}
        </p>
      </Card>
    </div>
  );
};

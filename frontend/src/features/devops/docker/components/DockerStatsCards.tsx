import React from 'react';
import { Card } from '@/shared/components/ui/Card';

interface DockerStatsCardsProps {
  totalContainers: number;
  runningContainers: number;
  stoppedContainers: number;
  totalImages: number;
  networkCount: number;
  volumeCount: number;
  isLoading?: boolean;
}

export const DockerStatsCards: React.FC<DockerStatsCardsProps> = ({
  totalContainers,
  runningContainers,
  stoppedContainers,
  totalImages,
  networkCount,
  volumeCount,
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
        <p className="text-xs text-theme-tertiary mb-1">Containers</p>
        <p className="text-2xl font-bold text-theme-primary">{totalContainers}</p>
        <div className="flex items-center gap-2 mt-1">
          <span className="text-xs text-theme-success">{runningContainers} running</span>
          <span className="text-xs text-theme-tertiary">{stoppedContainers} stopped</span>
        </div>
      </Card>
      <Card variant="default" padding="md">
        <p className="text-xs text-theme-tertiary mb-1">Images</p>
        <p className="text-2xl font-bold text-theme-primary">{totalImages}</p>
        <p className="text-xs text-theme-secondary mt-1">Total pulled</p>
      </Card>
      <Card variant="default" padding="md">
        <p className="text-xs text-theme-tertiary mb-1">Networks</p>
        <p className="text-2xl font-bold text-theme-primary">{networkCount}</p>
        <p className="text-xs text-theme-secondary mt-1">Configured</p>
      </Card>
      <Card variant="default" padding="md">
        <p className="text-xs text-theme-tertiary mb-1">Volumes</p>
        <p className="text-2xl font-bold text-theme-primary">{volumeCount}</p>
        <p className="text-xs text-theme-secondary mt-1">Mounted</p>
      </Card>
    </div>
  );
};

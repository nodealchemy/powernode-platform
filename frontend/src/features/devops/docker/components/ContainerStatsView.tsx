import React from 'react';
import { dockerApi } from '../services/dockerApi';
import type { ContainerStats } from '../types';

interface ContainerStatsViewProps {
  stats: ContainerStats;
}

export const ContainerStatsView: React.FC<ContainerStatsViewProps> = ({ stats }) => {
  const memoryPercentage = stats.memory_percentage;

  const cpuColor = stats.cpu_percentage > 80 ? 'text-theme-error' :
    stats.cpu_percentage > 50 ? 'text-theme-warning' : 'text-theme-success';

  const memColor = memoryPercentage > 80 ? 'text-theme-error' :
    memoryPercentage > 50 ? 'text-theme-warning' : 'text-theme-success';

  return (
    <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-5 gap-4">
      <div className="bg-theme-surface rounded-lg border border-theme p-3">
        <p className="text-xs text-theme-tertiary mb-1">CPU</p>
        <p className={`text-xl font-bold ${cpuColor}`}>
          {stats.cpu_percentage.toFixed(1)}%
        </p>
        <div className="mt-2 w-full h-1.5 bg-theme-surface rounded-full overflow-hidden">
          <div
            className={`h-full rounded-full transition-all ${
              stats.cpu_percentage > 80 ? 'bg-theme-error' :
              stats.cpu_percentage > 50 ? 'bg-theme-warning' : 'bg-theme-success'
            }`}
            style={{ width: `${Math.min(stats.cpu_percentage, 100)}%` }}
          />
        </div>
      </div>

      <div className="bg-theme-surface rounded-lg border border-theme p-3">
        <p className="text-xs text-theme-tertiary mb-1">Memory</p>
        <p className={`text-xl font-bold ${memColor}`}>
          {memoryPercentage.toFixed(1)}%
        </p>
        <p className="text-xs text-theme-tertiary mt-1">
          {dockerApi.formatBytes(stats.memory_usage)} / {dockerApi.formatBytes(stats.memory_limit)}
        </p>
        <div className="mt-1 w-full h-1.5 bg-theme-surface rounded-full overflow-hidden">
          <div
            className={`h-full rounded-full transition-all ${
              memoryPercentage > 80 ? 'bg-theme-error' :
              memoryPercentage > 50 ? 'bg-theme-warning' : 'bg-theme-success'
            }`}
            style={{ width: `${Math.min(memoryPercentage, 100)}%` }}
          />
        </div>
      </div>

      <div className="bg-theme-surface rounded-lg border border-theme p-3">
        <p className="text-xs text-theme-tertiary mb-1">Network I/O</p>
        <div className="space-y-1">
          <p className="text-sm font-medium text-theme-primary">
            <span className="text-theme-success">&#x2191;</span> {dockerApi.formatBytes(stats.network_tx)}
          </p>
          <p className="text-sm font-medium text-theme-primary">
            <span className="text-theme-info">&#x2193;</span> {dockerApi.formatBytes(stats.network_rx)}
          </p>
        </div>
      </div>

      <div className="bg-theme-surface rounded-lg border border-theme p-3">
        <p className="text-xs text-theme-tertiary mb-1">Block I/O</p>
        <div className="space-y-1">
          <p className="text-sm font-medium text-theme-primary">
            R: {dockerApi.formatBytes(stats.block_read)}
          </p>
          <p className="text-sm font-medium text-theme-primary">
            W: {dockerApi.formatBytes(stats.block_write)}
          </p>
        </div>
      </div>

      <div className="bg-theme-surface rounded-lg border border-theme p-3">
        <p className="text-xs text-theme-tertiary mb-1">PIDs</p>
        <p className="text-xl font-bold text-theme-primary">{stats.pids}</p>
      </div>
    </div>
  );
};

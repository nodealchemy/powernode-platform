import React from 'react';
import { Card } from '@/shared/components/ui/Card';
import { dockerApi } from '../services/dockerApi';
import { ContainerStateActions } from './ContainerStateActions';
import type { DockerContainerSummary } from '../types';

interface ContainerCardProps {
  container: DockerContainerSummary;
  onStart?: (id: string) => void;
  onStop?: (id: string) => void;
  onRestart?: (id: string) => void;
  onClick?: (id: string) => void;
  isLoading?: boolean;
}

export const ContainerCard: React.FC<ContainerCardProps> = ({
  container,
  onStart,
  onStop,
  onRestart,
  onClick,
  isLoading = false,
}) => {
  const stateColor = dockerApi.getContainerStateColor(container.state);

  const formatPorts = (ports: DockerContainerSummary['ports']) => {
    if (!ports || ports.length === 0) return null;
    return ports.map((p, i) => (
      <span key={i} className="text-xs text-theme-tertiary">
        {p.public_port ? `${p.public_port}→` : ''}{p.private_port}/{p.type}
      </span>
    ));
  };

  return (
    <Card variant="default" padding="md" hoverable clickable={!!onClick} onClick={() => onClick?.(container.id)}>
      <div className="space-y-3">
        <div className="flex items-start justify-between">
          <div className="min-w-0 flex-1">
            <h3 className="text-sm font-semibold text-theme-primary truncate">{container.name}</h3>
            <p className="text-xs text-theme-tertiary mt-0.5 truncate">{container.image}</p>
          </div>
          <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium ${stateColor}`}>
            {container.state}
          </span>
        </div>

        {container.ports.length > 0 && (
          <div className="flex items-center gap-2 flex-wrap">
            <span className="text-xs text-theme-secondary">Ports:</span>
            {formatPorts(container.ports)}
          </div>
        )}

        {container.started_at && (
          <p className="text-xs text-theme-tertiary">
            Started: {new Date(container.started_at).toLocaleString()}
          </p>
        )}

        <div className="pt-2 border-t border-theme" onClick={(e) => e.stopPropagation()}>
          <ContainerStateActions
            state={container.state}
            onStart={() => onStart?.(container.id)}
            onStop={() => onStop?.(container.id)}
            onRestart={() => onRestart?.(container.id)}
            isLoading={isLoading}
          />
        </div>
      </div>
    </Card>
  );
};

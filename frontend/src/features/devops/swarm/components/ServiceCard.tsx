import React from 'react';
import { Card } from '@/shared/components/ui/Card';
import { swarmApi } from '../services/swarmApi';
import type { SwarmServiceSummary } from '../types';

interface ServiceCardProps {
  service: SwarmServiceSummary;
  onClick?: () => void;
  actions?: React.ReactNode;
}

export const ServiceCard: React.FC<ServiceCardProps> = ({ service, onClick, actions }) => {
  const healthColor = swarmApi.getHealthPercentageColor(service.health_percentage);
  const healthWidth = Math.min(100, Math.max(0, service.health_percentage));

  return (
    <Card variant="default" hoverable clickable={!!onClick} padding="md" onClick={onClick}>
      <div className="flex items-start justify-between mb-2">
        <div className="flex-1 min-w-0">
          <h4 className="text-base font-semibold text-theme-primary truncate">{service.service_name}</h4>
          <p className="text-xs text-theme-tertiary truncate">{service.image}</p>
        </div>
        <span className="px-2 py-0.5 rounded bg-theme-surface text-theme-secondary text-xs font-medium capitalize">
          {service.mode}
        </span>
      </div>

      <div className="flex items-center gap-4 mb-3 text-sm">
        <div>
          <span className="text-theme-tertiary text-xs">Replicas:</span>
          <span className={`ml-1 font-semibold ${
            service.running_replicas >= service.desired_replicas ? 'text-theme-success' : 'text-theme-warning'
          }`}>
            {service.running_replicas}/{service.desired_replicas}
          </span>
        </div>
        <div>
          <span className="text-theme-tertiary text-xs">Health:</span>
          <span className={`ml-1 font-semibold ${healthColor}`}>{service.health_percentage}%</span>
        </div>
      </div>

      <div className="w-full h-1.5 bg-theme-surface rounded-full overflow-hidden mb-3">
        <div
          className={`h-full rounded-full transition-all ${
            service.health_percentage >= 100 ? 'bg-theme-success' :
            service.health_percentage >= 50 ? 'bg-theme-warning' :
            'bg-theme-error'
          }`}
          style={{ width: `${healthWidth}%` }}
        />
      </div>

      {service.ports.length > 0 && (
        <div className="flex flex-wrap gap-1 mb-3">
          {service.ports.map((port, i) => (
            <span key={i} className="px-1.5 py-0.5 rounded bg-theme-surface text-theme-tertiary text-xs">
              {port.published}:{port.target}
            </span>
          ))}
        </div>
      )}

      {actions && <div className="border-t border-theme pt-2">{actions}</div>}
    </Card>
  );
};

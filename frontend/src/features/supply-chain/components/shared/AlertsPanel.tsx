import React from 'react';
import { AlertTriangle, AlertCircle, Info, CheckCircle } from 'lucide-react';

interface Alert {
  id: string;
  type: string;
  severity: 'critical' | 'high' | 'medium' | 'low';
  title: string;
  message: string;
  entity_id: string;
  entity_type: string;
  created_at: string;
}

interface AlertsPanelProps {
  alerts: Alert[];
  onAlertClick?: (alert: Alert) => void;
  maxItems?: number;
}

const severityIcons = {
  critical: AlertCircle,
  high: AlertTriangle,
  medium: Info,
  low: CheckCircle,
};

const severityColors = {
  critical: 'text-theme-error',
  high: 'text-theme-warning',
  medium: 'text-theme-info',
  low: 'text-theme-success',
};

export const AlertsPanel: React.FC<AlertsPanelProps> = ({ alerts, onAlertClick, maxItems = 5 }) => {
  const displayAlerts = alerts.slice(0, maxItems);

  if (displayAlerts.length === 0) {
    return (
      <div className="bg-theme-surface border border-theme rounded-lg p-4">
        <h3 className="font-semibold text-theme-primary mb-3">Recent Alerts</h3>
        <div className="text-center py-4">
          <CheckCircle className="w-8 h-8 text-theme-success mx-auto mb-2" />
          <p className="text-sm text-theme-secondary">No active alerts</p>
        </div>
      </div>
    );
  }

  return (
    <div className="bg-theme-surface border border-theme rounded-lg p-4">
      <h3 className="font-semibold text-theme-primary mb-3">Recent Alerts</h3>
      <div className="space-y-3">
        {displayAlerts.map((alert) => {
          const Icon = severityIcons[alert.severity];
          return (
            <div
              key={alert.id}
              onClick={() => onAlertClick?.(alert)}
              className={`flex items-start gap-3 p-2 rounded hover:bg-theme-surface-hover ${onAlertClick ? 'cursor-pointer' : ''}`}
            >
              <Icon className={`w-5 h-5 mt-0.5 ${severityColors[alert.severity]}`} />
              <div className="flex-1 min-w-0">
                <p className="text-sm font-medium text-theme-primary truncate">{alert.title}</p>
                <p className="text-xs text-theme-tertiary truncate">{alert.message}</p>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};

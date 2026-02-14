import React from 'react';
import {
  AlertCircle,
  AlertTriangle,
  CheckCircle,
  Settings,
  XCircle,
} from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import type { ProviderMetrics } from '@/shared/types/monitoring';
import { cn } from '@/shared/utils/cn';

interface ProviderAlertsListProps {
  provider: ProviderMetrics;
  section: 'alerts' | 'credentials';
}

export const ProviderAlertsList: React.FC<ProviderAlertsListProps> = ({ provider, section }) => {
  if (section === 'credentials') {
    if (provider.credentials.length === 0) {
      return (
        <EmptyState
          icon={Settings}
          title="No Credentials"
          description="No credentials configured for this provider"
        />
      );
    }

    return (
      <div className="space-y-2">
        {provider.credentials.map(cred => (
          <div key={cred.id} className="flex items-center justify-between p-3 bg-theme-surface rounded">
            <div className="flex items-center gap-3">
              {cred.status === 'valid' && <CheckCircle className="h-4 w-4 text-theme-success" />}
              {cred.status === 'invalid' && <XCircle className="h-4 w-4 text-theme-danger" />}
              {cred.status === 'expired' && <AlertTriangle className="h-4 w-4 text-theme-warning" />}
              {cred.status === 'unknown' && <AlertCircle className="h-4 w-4 text-theme-muted" />}
              <div>
                <p className="font-medium text-theme-primary">{cred.name}</p>
                <p className="text-xs text-theme-muted">
                  {cred.last_tested
                    ? `Last tested: ${new Date(cred.last_tested).toLocaleString()}`
                    : 'Never tested'}
                </p>
              </div>
            </div>
            <div className="flex items-center gap-2">
              <Badge variant={cred.is_active ? 'success' : 'outline'}>
                {cred.is_active ? 'Active' : 'Inactive'}
              </Badge>
              <Badge variant={cred.status === 'valid' ? 'success' : cred.status === 'invalid' ? 'danger' : 'warning'}>
                {cred.status}
              </Badge>
            </div>
          </div>
        ))}
      </div>
    );
  }

  // Alerts section
  if (provider.alerts.length === 0) {
    return (
      <EmptyState
        icon={CheckCircle}
        title="No Active Alerts"
        description="This provider has no active alerts"
      />
    );
  }

  return (
    <div className="space-y-2">
      {provider.alerts.map(alert => (
        <div
          key={alert.id}
          className={cn(
            'p-3 rounded border',
            alert.severity === 'critical' && 'bg-theme-danger/10 border-theme-danger/30',
            alert.severity === 'high' && 'bg-theme-danger/10 border-theme-danger/30',
            alert.severity === 'medium' && 'bg-theme-warning/10 border-theme-warning/30',
            alert.severity === 'low' && 'bg-theme-info/10 border-theme-info/30'
          )}
        >
          <div className="flex items-start justify-between">
            <div className="flex items-start gap-2">
              <AlertTriangle className={cn(
                'h-4 w-4 mt-0.5',
                alert.severity === 'critical' && 'text-theme-danger',
                alert.severity === 'high' && 'text-theme-danger',
                alert.severity === 'medium' && 'text-theme-warning',
                alert.severity === 'low' && 'text-theme-info'
              )} />
              <div>
                <p className="font-medium text-theme-primary">{alert.title}</p>
                <p className="text-sm text-theme-muted">{alert.message}</p>
                <p className="text-xs text-theme-muted mt-1">
                  {new Date(alert.created_at).toLocaleString()}
                </p>
              </div>
            </div>
            <Badge variant={alert.severity === 'critical' || alert.severity === 'high' ? 'danger' : alert.severity === 'medium' ? 'warning' : 'info'}>
              {alert.severity}
            </Badge>
          </div>
        </div>
      ))}
    </div>
  );
};

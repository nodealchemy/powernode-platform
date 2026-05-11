import React from 'react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import type { AiDataSource } from '@/shared/types/ai';

interface DataSourceQuotaTabProps {
  dataSource: AiDataSource;
}

interface QuotaBarProps {
  label: string;
  current: number;
  limit: number | undefined;
  pct: number | null;
}

const QuotaBar: React.FC<QuotaBarProps> = ({ label, current, limit, pct }) => {
  const percentage = pct ?? (limit && limit > 0 ? (current / limit) * 100 : 0);
  const barColor = percentage > 90 ? 'bg-theme-danger' :
                   percentage > 70 ? 'bg-theme-warning' :
                   'bg-theme-success';

  return (
    <div className="space-y-1">
      <div className="flex items-center justify-between">
        <span className="text-sm font-medium text-theme-primary">{label}</span>
        <span className="text-sm text-theme-tertiary">
          {current.toLocaleString()}
          {limit ? ` / ${limit.toLocaleString()}` : ''}
          {percentage > 0 ? ` (${Math.round(percentage)}%)` : ''}
        </span>
      </div>
      <div className="w-full bg-theme-surface-secondary rounded-full h-2">
        <div
          className={`h-2 rounded-full transition-all ${barColor}`}
          style={{ width: `${Math.min(percentage, 100)}%` }}
        />
      </div>
    </div>
  );
};

export const DataSourceQuotaTab: React.FC<DataSourceQuotaTabProps> = ({ dataSource }) => {
  const quota = dataSource.quota;
  const rateLimits = dataSource.rate_limits;

  if (!quota && (!rateLimits || Object.keys(rateLimits).length === 0)) {
    return (
      <Card>
        <CardHeader title="Quota & Usage" />
        <CardContent>
          <p className="text-theme-tertiary text-center py-8">
            No quota or rate limits configured for this data source.
          </p>
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      {/* Current Usage */}
      {quota && (
        <Card>
          <CardHeader title="Current Usage" />
          <CardContent className="space-y-4">
            <QuotaBar
              label="Requests (Minute)"
              current={quota.usage.minute}
              limit={quota.limits.requests_per_minute}
              pct={quota.utilization.minute_pct}
            />
            <QuotaBar
              label="Requests (Hour)"
              current={quota.usage.hour}
              limit={quota.limits.requests_per_hour}
              pct={quota.utilization.hour_pct}
            />
            <QuotaBar
              label="Requests (Day)"
              current={quota.usage.day}
              limit={quota.limits.requests_per_day}
              pct={quota.utilization.day_pct}
            />
            {quota.usage.bandwidth_today > 0 && (
              <div className="pt-2 border-t border-theme">
                <div className="flex items-center justify-between">
                  <span className="text-sm font-medium text-theme-primary">Bandwidth Today</span>
                  <span className="text-sm text-theme-tertiary">
                    {(quota.usage.bandwidth_today / (1024 * 1024)).toFixed(2)} MB
                  </span>
                </div>
              </div>
            )}
          </CardContent>
        </Card>
      )}

      {/* Configured Limits */}
      {rateLimits && Object.keys(rateLimits).length > 0 && (
        <Card>
          <CardHeader title="Configured Rate Limits" />
          <CardContent>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              {Object.entries(rateLimits).map(([key, value]) => (
                <div key={key} className="text-center p-3 bg-theme-surface-secondary rounded-lg">
                  <p className="text-lg font-semibold text-theme-primary">{value.toLocaleString()}</p>
                  <p className="text-xs text-theme-tertiary">{key.replace(/_/g, ' ')}</p>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
};

import React from 'react';
import { Card, Badge, Button } from '@/shared/components/ui';
import type { UsageEvent } from '../types';

interface UsageHistoryProps {
  events: UsageEvent[];
  onExport?: () => void;
}

const SOURCE_LABELS: Record<string, string> = {
  api: 'API',
  webhook: 'Webhook',
  system: 'System',
  import: 'Import',
  internal: 'Internal',
};

export const UsageHistory: React.FC<UsageHistoryProps> = ({ events, onExport }) => {
  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleString('en-US', {
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  };

  const formatNumber = (num: number) => {
    return new Intl.NumberFormat('en-US').format(num);
  };

  return (
    <Card className="p-6">
      <div className="flex items-center justify-between mb-4">
        <div>
          <h3 className="text-lg font-semibold text-theme-primary">Recent Events</h3>
          <p className="text-sm text-theme-tertiary">Latest usage events</p>
        </div>
        {onExport && (
          <Button variant="secondary" size="sm" onClick={onExport}>
            Export
          </Button>
        )}
      </div>

      {events.length === 0 ? (
        <p className="text-center text-theme-tertiary py-8">
          No usage events recorded yet.
        </p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead>
              <tr className="border-b border-theme">
                <th className="text-left py-3 px-2 text-sm font-medium text-theme-secondary">Event ID</th>
                <th className="text-left py-3 px-2 text-sm font-medium text-theme-secondary">Meter</th>
                <th className="text-right py-3 px-2 text-sm font-medium text-theme-secondary">Quantity</th>
                <th className="text-left py-3 px-2 text-sm font-medium text-theme-secondary">Source</th>
                <th className="text-left py-3 px-2 text-sm font-medium text-theme-secondary">Timestamp</th>
                <th className="text-center py-3 px-2 text-sm font-medium text-theme-secondary">Status</th>
              </tr>
            </thead>
            <tbody>
              {events.map((event) => (
                <tr key={event.id} className="border-b border-theme hover:bg-theme-hover">
                  <td className="py-3 px-2">
                    <span className="text-sm font-mono text-theme-tertiary">
                      {event.event_id.slice(0, 8)}...
                    </span>
                  </td>
                  <td className="py-3 px-2">
                    <span className="text-sm text-theme-primary">{event.meter_slug}</span>
                  </td>
                  <td className="py-3 px-2 text-right">
                    <span className="text-sm font-medium text-theme-primary">
                      {formatNumber(event.quantity)}
                    </span>
                  </td>
                  <td className="py-3 px-2">
                    <span className="text-sm text-theme-secondary">
                      {SOURCE_LABELS[event.source || 'api'] || event.source}
                    </span>
                  </td>
                  <td className="py-3 px-2">
                    <span className="text-sm text-theme-tertiary">
                      {formatDate(event.timestamp)}
                    </span>
                  </td>
                  <td className="py-3 px-2 text-center">
                    <Badge
                      variant={event.is_processed ? 'success' : 'warning'}
                      size="sm"
                    >
                      {event.is_processed ? 'Processed' : 'Pending'}
                    </Badge>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Card>
  );
};

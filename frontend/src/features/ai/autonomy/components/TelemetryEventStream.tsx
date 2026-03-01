import React from 'react';
import { Radio, ArrowRight } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { useTelemetryEvents } from '../api/autonomyApi';
import type { TelemetryEvent } from '../types/autonomy';

const CATEGORY_VARIANT: Record<string, 'success' | 'warning' | 'info' | 'default'> = {
  action: 'info',
  trust: 'success',
  budget: 'warning',
  security: 'default',
  delegation: 'info',
  lifecycle: 'success',
};

const formatDate = (dateStr: string): string => {
  return new Date(dateStr).toLocaleString();
};

const EventRow: React.FC<{ event: TelemetryEvent }> = ({ event }) => (
  <div className="flex items-start gap-3 py-2 border-b border-theme-border last:border-0">
    <div className="mt-1">
      <ArrowRight className="h-3 w-3 text-theme-muted" />
    </div>
    <div className="flex-1 min-w-0">
      <div className="flex items-center gap-2 flex-wrap">
        <Badge variant={CATEGORY_VARIANT[event.event_category] || 'default'} size="sm">
          {event.event_category}
        </Badge>
        <span className="text-sm font-medium text-theme-primary">{event.event_type}</span>
        {event.outcome && (
          <span className={`text-xs ${event.outcome === 'success' ? 'text-theme-success' : 'text-theme-error'}`}>
            {event.outcome}
          </span>
        )}
      </div>
      <p className="text-xs text-theme-muted mt-0.5">
        #{event.sequence_number} | {formatDate(event.created_at)}
      </p>
    </div>
  </div>
);

export const TelemetryEventStream: React.FC = () => {
  const { data: events, isLoading } = useTelemetryEvents();

  if (isLoading) return null;

  return (
    <Card>
      <CardHeader title={`Telemetry Events (${events?.length ?? 0})`} />
      <CardContent>
        {events && events.length > 0 ? (
          <div className="max-h-96 overflow-y-auto">
            {events.map(e => (
              <EventRow key={e.id} event={e} />
            ))}
          </div>
        ) : (
          <div className="py-6 text-center text-theme-muted">
            <Radio className="w-10 h-10 mx-auto mb-2 opacity-30" />
            <p className="text-sm">No telemetry events recorded</p>
          </div>
        )}
      </CardContent>
    </Card>
  );
};

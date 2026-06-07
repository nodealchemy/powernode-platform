import React, { useState, useEffect, useCallback } from 'react';
import { History, GitCompare, AlertTriangle, PlusCircle, MinusCircle, ArrowRight } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Select } from '@/shared/components/ui/Select';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { dataSourcesApi } from '@/shared/services/ai/DataSourcesApiService';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { logger } from '@/shared/utils/logger';
import type {
  AiDataSourceEndpoint,
  AiDataSourceSchemaVersion,
  DataSourceSchemaClassification,
  DataSourceSchemaDiff,
} from '@/shared/types/ai';

interface DataSourceSchemaHistoryTabProps {
  dataSourceId: string;
}

type BadgeVariant = 'success' | 'warning' | 'danger' | 'info' | 'outline' | 'secondary';

// Map a drift classification to a badge variant + human label.
function classificationBadge(
  classification: DataSourceSchemaClassification
): { variant: BadgeVariant; label: string } {
  switch (classification) {
    case 'breaking':
      return { variant: 'danger', label: 'Breaking' };
    case 'additive':
      return { variant: 'warning', label: 'Additive' };
    case 'none':
      return { variant: 'outline', label: 'No change' };
    case 'initial':
    default:
      return { variant: 'info', label: 'Initial' };
  }
}

// Total number of structural changes captured by a diff.
function diffChangeCount(diff: DataSourceSchemaDiff | undefined): number {
  if (!diff) return 0;
  return (
    (diff.added_fields?.length ?? 0) +
    (diff.removed_fields?.length ?? 0) +
    (diff.type_changes?.length ?? 0)
  );
}

export const DataSourceSchemaHistoryTab: React.FC<DataSourceSchemaHistoryTabProps> = ({
  dataSourceId,
}) => {
  const { addNotification } = useNotifications();

  const [endpoints, setEndpoints] = useState<AiDataSourceEndpoint[]>([]);
  const [loadingEndpoints, setLoadingEndpoints] = useState(true);
  const [selectedEndpointId, setSelectedEndpointId] = useState<string>('');
  const [versions, setVersions] = useState<AiDataSourceSchemaVersion[]>([]);
  const [latest, setLatest] = useState<AiDataSourceSchemaVersion | null>(null);
  const [loadingHistory, setLoadingHistory] = useState(false);

  const loadEndpoints = useCallback(async () => {
    if (!dataSourceId) return;
    try {
      setLoadingEndpoints(true);
      const items = await dataSourcesApi.getEndpoints(dataSourceId);
      setEndpoints(items);
      setSelectedEndpointId((prev) => prev || (items[0]?.id ?? ''));
    } catch (error) {
      logger.error('Failed to load endpoints for schema history', { dataSourceId, error });
      addNotification({
        type: 'error',
        title: 'Error',
        message: 'Failed to load endpoints. Please try again.',
      });
    } finally {
      setLoadingEndpoints(false);
    }
  }, [dataSourceId, addNotification]);

  const loadHistory = useCallback(async () => {
    if (!dataSourceId || !selectedEndpointId) {
      setVersions([]);
      setLatest(null);
      return;
    }
    try {
      setLoadingHistory(true);
      const response = await dataSourcesApi.getSchemaHistory(dataSourceId, selectedEndpointId);
      const ordered = [...(response.versions ?? [])].sort((a, b) => b.version - a.version);
      setVersions(ordered);
      setLatest(response.latest ?? ordered[0] ?? null);
    } catch (error) {
      logger.error('Failed to load schema history', { dataSourceId, selectedEndpointId, error });
      addNotification({
        type: 'error',
        title: 'Error',
        message: 'Failed to load schema history. Please try again.',
      });
      setVersions([]);
      setLatest(null);
    } finally {
      setLoadingHistory(false);
    }
  }, [dataSourceId, selectedEndpointId, addNotification]);

  useEffect(() => {
    loadEndpoints();
  }, [loadEndpoints]);

  useEffect(() => {
    loadHistory();
  }, [loadHistory]);

  const selectedEndpoint = endpoints.find((ep) => ep.id === selectedEndpointId);

  const renderDiff = (diff: DataSourceSchemaDiff | undefined) => {
    if (!diff || diffChangeCount(diff) === 0) {
      return <p className="text-xs text-theme-tertiary">No field-level changes.</p>;
    }
    return (
      <div className="space-y-1.5">
        {(diff.added_fields ?? []).map((field) => (
          <div key={`add-${field}`} className="flex items-center gap-2 text-xs">
            <PlusCircle className="h-3 w-3 text-theme-success shrink-0" />
            <span className="font-mono text-theme-primary break-all">{field}</span>
            <span className="text-theme-tertiary">added</span>
          </div>
        ))}
        {(diff.removed_fields ?? []).map((field) => (
          <div key={`rem-${field}`} className="flex items-center gap-2 text-xs">
            <MinusCircle className="h-3 w-3 text-theme-error shrink-0" />
            <span className="font-mono text-theme-primary break-all">{field}</span>
            <span className="text-theme-tertiary">removed</span>
          </div>
        ))}
        {(diff.type_changes ?? []).map((change) => (
          <div key={`type-${change.field}`} className="flex items-center gap-2 text-xs flex-wrap">
            <ArrowRight className="h-3 w-3 text-theme-warning shrink-0" />
            <span className="font-mono text-theme-primary break-all">{change.field}</span>
            <span className="text-theme-tertiary">
              {change.from}
              {' → '}
              {change.to}
            </span>
          </div>
        ))}
      </div>
    );
  };

  const renderVersionRow = (version: AiDataSourceSchemaVersion) => {
    const badge = classificationBadge(version.classification);
    const changes = diffChangeCount(version.diff);
    return (
      <div key={version.id} className="p-3 border border-theme rounded-lg space-y-2">
        <div className="flex items-center justify-between gap-3 flex-wrap">
          <div className="flex items-center gap-2 flex-wrap">
            <Badge variant="secondary" size="sm">v{version.version}</Badge>
            <Badge variant={badge.variant} size="sm">
              {version.classification === 'breaking' && (
                <AlertTriangle className="h-3 w-3 mr-1" />
              )}
              {badge.label}
            </Badge>
            {changes > 0 && (
              <span className="text-xs text-theme-tertiary">
                {changes} field change{changes === 1 ? '' : 's'}
              </span>
            )}
          </div>
          <span className="text-xs text-theme-tertiary">
            {new Date(version.created_at).toLocaleString()}
          </span>
        </div>
        {version.classification !== 'none' && renderDiff(version.diff)}
      </div>
    );
  };

  if (loadingEndpoints) {
    return (
      <Card>
        <CardHeader title="Schema History" />
        <CardContent>
          <LoadingSpinner className="py-8" />
        </CardContent>
      </Card>
    );
  }

  if (endpoints.length === 0) {
    return (
      <Card>
        <CardHeader title="Schema History" />
        <CardContent>
          <div className="text-center py-8">
            <History className="h-8 w-8 mx-auto text-theme-tertiary mb-2" />
            <p className="text-sm text-theme-tertiary">
              No endpoints configured. Schema versions are recorded per endpoint.
            </p>
          </div>
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader
          title="Schema History"
          subtitle="Recorded response-schema versions and drift classification per endpoint."
        />
        <CardContent className="space-y-4">
          <Select
            label="Endpoint"
            value={selectedEndpointId}
            onValueChange={setSelectedEndpointId}
            options={endpoints.map((ep) => ({
              value: ep.id,
              label: `${ep.http_method} ${ep.name}`,
            }))}
          />

          {selectedEndpoint && selectedEndpoint.track_schema === false && (
            <div className="p-3 bg-theme-warning/10 border border-theme-warning/20 rounded-lg">
              <div className="flex items-center gap-2">
                <AlertTriangle className="h-4 w-4 text-theme-warning shrink-0" />
                <span className="text-sm text-theme-warning">
                  Schema tracking is disabled for this endpoint. Enable &quot;Track schema&quot; to
                  record versions on each fetch.
                </span>
              </div>
            </div>
          )}

          {latest && (
            <div className="flex items-center gap-2 flex-wrap">
              <GitCompare className="h-4 w-4 text-theme-tertiary" />
              <span className="text-sm text-theme-secondary">Latest:</span>
              <Badge variant="secondary" size="sm">v{latest.version}</Badge>
              <Badge variant={classificationBadge(latest.classification).variant} size="sm">
                {classificationBadge(latest.classification).label}
              </Badge>
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader title="Versions" subtitle="Newest first." />
        <CardContent>
          {loadingHistory ? (
            <LoadingSpinner className="py-8" />
          ) : versions.length > 0 ? (
            <div className="space-y-3">{versions.map(renderVersionRow)}</div>
          ) : (
            <p className="text-sm text-theme-tertiary text-center py-8">
              No schema versions recorded yet for this endpoint.
            </p>
          )}
        </CardContent>
      </Card>
    </div>
  );
};

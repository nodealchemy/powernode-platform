import React, { useState, useEffect, useCallback } from 'react';
import { Play, Database, AlertCircle, ShieldCheck, ShieldAlert } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Select } from '@/shared/components/ui/Select';
import { Textarea } from '@/shared/components/ui/Textarea';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { dataSourcesApi } from '@/shared/services/ai/DataSourcesApiService';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { logger } from '@/shared/utils/logger';
import type {
  AiDataSourceEndpoint,
  DataSourceFetchEnvelope,
  DataSourceQueryStatus,
} from '@/shared/types/ai';

interface DataSourceQueryConsoleProps {
  dataSourceId: string;
  canQuery: boolean;
}

// Format a byte count into a human-readable string.
function formatBytes(bytes: number): string {
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

function statusBadgeVariant(status: DataSourceQueryStatus): 'success' | 'warning' | 'danger' | 'info' {
  switch (status) {
    case 'success':
      return 'success';
    case 'cached':
      return 'info';
    case 'rate_limited':
      return 'warning';
    default:
      return 'danger';
  }
}

export const DataSourceQueryConsole: React.FC<DataSourceQueryConsoleProps> = ({
  dataSourceId,
  canQuery,
}) => {
  const { addNotification } = useNotifications();

  const [endpoints, setEndpoints] = useState<AiDataSourceEndpoint[]>([]);
  const [loadingEndpoints, setLoadingEndpoints] = useState(true);
  const [selectedEndpointId, setSelectedEndpointId] = useState<string>('');
  const [paramsText, setParamsText] = useState('{}');
  const [paramsError, setParamsError] = useState<string | null>(null);
  const [running, setRunning] = useState(false);
  const [result, setResult] = useState<DataSourceFetchEnvelope | null>(null);

  const loadEndpoints = useCallback(async () => {
    if (!dataSourceId) return;
    try {
      setLoadingEndpoints(true);
      const items = await dataSourcesApi.getEndpoints(dataSourceId);
      setEndpoints(items);
      setSelectedEndpointId((prev) => prev || (items[0]?.id ?? ''));
    } catch (error) {
      logger.error('Failed to load endpoints for query console', { dataSourceId, error });
      addNotification({
        type: 'error',
        title: 'Error',
        message: 'Failed to load endpoints. Please try again.',
      });
    } finally {
      setLoadingEndpoints(false);
    }
  }, [dataSourceId, addNotification]);

  useEffect(() => {
    loadEndpoints();
  }, [loadEndpoints]);

  // Parse the params editor into an object; returns undefined when invalid.
  const parseParams = (): Record<string, unknown> | undefined => {
    const raw = paramsText.trim();
    if (raw === '' || raw === '{}') {
      setParamsError(null);
      return {};
    }
    try {
      const parsed = JSON.parse(raw);
      if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
        setParamsError('Parameters must be a JSON object.');
        return undefined;
      }
      setParamsError(null);
      return parsed as Record<string, unknown>;
    } catch {
      setParamsError('Parameters must be valid JSON.');
      return undefined;
    }
  };

  const handleRun = async () => {
    if (!selectedEndpointId) {
      addNotification({ type: 'error', title: 'Validation', message: 'Select an endpoint to query.' });
      return;
    }
    const params = parseParams();
    if (params === undefined) return;

    try {
      setRunning(true);
      setResult(null);
      const envelope = await dataSourcesApi.runQuery(dataSourceId, selectedEndpointId, params);
      setResult(envelope);
      addNotification({
        type: envelope.success ? 'success' : 'error',
        title: 'Query Complete',
        message: envelope.success
          ? `Returned ${envelope.data.length} record(s) in ${envelope.duration_ms}ms`
          : `Query failed: ${envelope.error || envelope.status}`,
      });
    } catch (error) {
      logger.error('Data source query failed', { dataSourceId, selectedEndpointId, error });
      addNotification({
        type: 'error',
        title: 'Query Failed',
        message: error instanceof Error ? error.message : 'Failed to run query',
      });
    } finally {
      setRunning(false);
    }
  };

  const renderProvenanceBadges = (envelope: DataSourceFetchEnvelope) => {
    const { provenance } = envelope;
    const contentType = provenance.declared_vs_detected_content_type;
    const schemaValid = provenance.schema_valid;
    const anomalies = provenance.anomalies ?? [];
    const cost = envelope.cost;

    return (
      <div className="flex flex-wrap items-center gap-2">
        <Badge variant={statusBadgeVariant(envelope.status)} size="sm">{envelope.status}</Badge>
        <Badge variant={provenance.from_cache ? 'info' : 'outline'} size="sm">
          {provenance.from_cache
            ? `Cached${provenance.cache_age_seconds ? ` (${provenance.cache_age_seconds}s old)` : ''}`
            : 'Fresh'}
        </Badge>
        <Badge variant="outline" size="sm">{envelope.duration_ms}ms</Badge>
        <Badge variant="outline" size="sm">{formatBytes(envelope.bytes)}</Badge>
        <Badge variant="outline" size="sm">{provenance.record_count ?? envelope.data.length} records</Badge>
        {cost && cost.amount != null && (
          <Badge variant="outline" size="sm">
            Cost: {cost.amount} {cost.currency ?? ''}
          </Badge>
        )}
        {schemaValid === true && (
          <Badge variant="success" size="sm">
            <ShieldCheck className="h-3 w-3 mr-1" />
            Schema valid
          </Badge>
        )}
        {schemaValid === false && (
          <Badge variant="danger" size="sm">
            <ShieldAlert className="h-3 w-3 mr-1" />
            Schema invalid
          </Badge>
        )}
        {contentType?.mismatch && (
          <Badge variant="warning" size="sm">
            Content-type mismatch
          </Badge>
        )}
        {anomalies.map((anomaly) => (
          <Badge key={anomaly} variant="warning" size="sm">{anomaly}</Badge>
        ))}
      </div>
    );
  };

  const renderProvenanceDetails = (envelope: DataSourceFetchEnvelope) => {
    const { provenance } = envelope;
    return (
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-2 text-xs">
        {provenance.source_url && (
          <div className="sm:col-span-2">
            <span className="text-theme-tertiary">Source URL (redacted): </span>
            <span className="text-theme-primary font-mono break-all">{provenance.source_url}</span>
          </div>
        )}
        {provenance.fetched_at && (
          <div>
            <span className="text-theme-tertiary">Fetched at: </span>
            <span className="text-theme-primary">{new Date(provenance.fetched_at).toLocaleString()}</span>
          </div>
        )}
        {provenance.response_sha256 && (
          <div>
            <span className="text-theme-tertiary">SHA-256: </span>
            <span className="text-theme-primary font-mono break-all">{provenance.response_sha256}</span>
          </div>
        )}
        {provenance.charset && (
          <div>
            <span className="text-theme-tertiary">Charset: </span>
            <span className="text-theme-primary">{provenance.charset}</span>
          </div>
        )}
        {provenance.declared_vs_detected_content_type && (
          <div>
            <span className="text-theme-tertiary">Content type: </span>
            <span className="text-theme-primary">
              {provenance.declared_vs_detected_content_type.declared ?? 'n/a'}
              {' → '}
              {provenance.declared_vs_detected_content_type.detected ?? 'n/a'}
            </span>
          </div>
        )}
      </div>
    );
  };

  const renderRecords = (envelope: DataSourceFetchEnvelope) => {
    if (!envelope.success) {
      return (
        <div className="p-4 bg-theme-error/10 border border-theme-error/20 rounded-lg">
          <div className="flex items-center gap-2">
            <AlertCircle className="h-4 w-4 text-theme-error" />
            <span className="text-sm text-theme-error">
              {envelope.error || `Query ${envelope.status}`}
              {envelope.retry_after != null ? ` — retry after ${envelope.retry_after}s` : ''}
            </span>
          </div>
        </div>
      );
    }

    if (envelope.data.length === 0) {
      return (
        <p className="text-sm text-theme-tertiary text-center py-6">
          Query succeeded but returned no records.
        </p>
      );
    }

    return (
      <pre className="text-xs text-theme-primary bg-theme-surface-secondary p-3 rounded-lg overflow-auto max-h-96">
        {JSON.stringify(envelope.data, null, 2)}
      </pre>
    );
  };

  if (!canQuery) {
    return (
      <Card>
        <CardHeader title="Query Console" />
        <CardContent>
          <p className="text-sm text-theme-tertiary text-center py-8">
            You do not have permission to query this data source.
          </p>
        </CardContent>
      </Card>
    );
  }

  if (loadingEndpoints) {
    return (
      <Card>
        <CardHeader title="Query Console" />
        <CardContent>
          <LoadingSpinner className="py-8" />
        </CardContent>
      </Card>
    );
  }

  if (endpoints.length === 0) {
    return (
      <Card>
        <CardHeader title="Query Console" />
        <CardContent>
          <div className="text-center py-8">
            <Database className="h-8 w-8 mx-auto text-theme-tertiary mb-2" />
            <p className="text-sm text-theme-tertiary">
              No endpoints configured. Add an endpoint before running a query.
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
          title="Query Console"
          subtitle="Run a governed fetch against an endpoint and inspect the canonical result."
        />
        <CardContent className="space-y-4">
          <Select
            label="Endpoint"
            value={selectedEndpointId}
            onValueChange={setSelectedEndpointId}
            options={endpoints.map((ep) => ({
              value: ep.id,
              label: `${ep.http_method} ${ep.name}${ep.path_template ? ` (${ep.path_template})` : ''}`,
            }))}
          />

          <Textarea
            label="Parameters"
            value={paramsText}
            onChange={(e) => setParamsText(e.target.value)}
            error={paramsError ?? undefined}
            description="JSON object of request parameters. Redacted server-side before persistence."
            rows={5}
            className="font-mono text-xs"
            spellCheck={false}
          />

          <div className="flex items-center justify-end">
            <Button variant="primary" onClick={handleRun} loading={running} disabled={!selectedEndpointId}>
              <Play className="h-4 w-4 mr-2" />
              Run Query
            </Button>
          </div>
        </CardContent>
      </Card>

      {result && (
        <Card>
          <CardHeader title="Result" />
          <CardContent className="space-y-4">
            {renderProvenanceBadges(result)}
            {renderProvenanceDetails(result)}
            <div className="pt-2 border-t border-theme">
              {renderRecords(result)}
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
};

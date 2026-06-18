import React, { useState, useEffect, useCallback } from 'react';
import {
  ShieldCheck,
  ShieldAlert,
  Gauge,
  AlertTriangle,
  CheckCircle2,
  XCircle,
  Lock,
} from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Select } from '@/shared/components/ui/Select';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { dataSourcesApi } from '@/shared/services/ai/DataSourcesApiService';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { logger } from '@/shared/utils/logger';
import type {
  AiDataSourceEndpoint,
  AiDataSourceExpectation,
  DataSourceLatestQuality,
  DataSourceQualityResult,
  DataSourceExpectationSeverity,
} from '@/shared/types/ai';

interface DataSourceQualityTabProps {
  dataSourceId: string;
}

// Render a 0..1 quality score as a whole-number percentage.
function formatScore(score: number | null | undefined): string {
  if (score == null) return 'N/A';
  return `${Math.round(score * 100)}%`;
}

// Score band -> badge variant: >=0.9 healthy, >=0.6 warn, else danger.
function scoreVariant(score: number | null | undefined): 'success' | 'warning' | 'danger' | 'outline' {
  if (score == null) return 'outline';
  if (score >= 0.9) return 'success';
  if (score >= 0.6) return 'warning';
  return 'danger';
}

function severityBadge(severity: DataSourceExpectationSeverity): 'danger' | 'warning' {
  return severity === 'error' ? 'danger' : 'warning';
}

export const DataSourceQualityTab: React.FC<DataSourceQualityTabProps> = ({ dataSourceId }) => {
  const { addNotification } = useNotifications();

  const [endpoints, setEndpoints] = useState<AiDataSourceEndpoint[]>([]);
  const [loadingEndpoints, setLoadingEndpoints] = useState(true);
  const [selectedEndpointId, setSelectedEndpointId] = useState<string>('');
  const [latest, setLatest] = useState<DataSourceLatestQuality | null>(null);
  const [expectations, setExpectations] = useState<AiDataSourceExpectation[]>([]);
  const [qualityEnabled, setQualityEnabled] = useState(false);
  const [quarantineOnFailure, setQuarantineOnFailure] = useState(false);
  const [loadingQuality, setLoadingQuality] = useState(false);

  const loadEndpoints = useCallback(async () => {
    if (!dataSourceId) return;
    try {
      setLoadingEndpoints(true);
      const items = await dataSourcesApi.getEndpoints(dataSourceId);
      setEndpoints(items);
      setSelectedEndpointId((prev) => prev || (items[0]?.id ?? ''));
    } catch (error) {
      logger.error('Failed to load endpoints for quality panel', { dataSourceId, error });
      addNotification({
        type: 'error',
        title: 'Error',
        message: 'Failed to load endpoints. Please try again.',
      });
    } finally {
      setLoadingEndpoints(false);
    }
  }, [dataSourceId, addNotification]);

  const loadQuality = useCallback(async () => {
    if (!dataSourceId || !selectedEndpointId) {
      setLatest(null);
      setExpectations([]);
      return;
    }
    try {
      setLoadingQuality(true);
      const response = await dataSourcesApi.getEndpointQuality(dataSourceId, selectedEndpointId);
      setLatest(response.latest ?? null);
      setExpectations(response.expectations ?? []);
      setQualityEnabled(response.quality_checks_enabled);
      setQuarantineOnFailure(response.quarantine_on_failure);
    } catch (error) {
      logger.error('Failed to load endpoint quality', { dataSourceId, selectedEndpointId, error });
      addNotification({
        type: 'error',
        title: 'Error',
        message: 'Failed to load data quality. Please try again.',
      });
      setLatest(null);
      setExpectations([]);
    } finally {
      setLoadingQuality(false);
    }
  }, [dataSourceId, selectedEndpointId, addNotification]);

  useEffect(() => {
    loadEndpoints();
  }, [loadEndpoints]);

  useEffect(() => {
    loadQuality();
  }, [loadQuality]);

  const renderResultRow = (result: DataSourceQualityResult, index: number) => (
    <div
      key={`${result.name}-${index}`}
      className="flex items-start justify-between gap-3 p-2.5 border border-theme rounded-lg"
    >
      <div className="min-w-0 flex items-start gap-2">
        {result.passed ? (
          <CheckCircle2 className="h-4 w-4 text-theme-success-fg shrink-0 mt-0.5" />
        ) : (
          <XCircle className="h-4 w-4 text-theme-error-fg shrink-0 mt-0.5" />
        )}
        <div className="min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <span className="text-sm font-medium text-theme-primary truncate">{result.name}</span>
            <Badge variant="outline" size="xs">{result.rule_type}</Badge>
            <Badge variant={severityBadge(result.severity)} size="xs">{result.severity}</Badge>
          </div>
          {result.detail && (
            <p className="mt-0.5 text-xs text-theme-tertiary break-words">{result.detail}</p>
          )}
        </div>
      </div>
    </div>
  );

  const renderExpectationRow = (expectation: AiDataSourceExpectation) => (
    <div
      key={expectation.id}
      className="flex items-center justify-between gap-3 p-2.5 border border-theme rounded-lg"
    >
      <div className="min-w-0">
        <div className="flex items-center gap-2 flex-wrap">
          <span className="text-sm font-medium text-theme-primary truncate">{expectation.name}</span>
          <Badge variant="outline" size="xs">{expectation.rule_type}</Badge>
          <Badge variant={severityBadge(expectation.severity)} size="xs">{expectation.severity}</Badge>
          {!expectation.is_active && (
            <Badge variant="secondary" size="xs">Inactive</Badge>
          )}
        </div>
      </div>
    </div>
  );

  if (loadingEndpoints) {
    return (
      <Card>
        <CardHeader title="Data Quality" />
        <CardContent>
          <LoadingSpinner className="py-8" />
        </CardContent>
      </Card>
    );
  }

  if (endpoints.length === 0) {
    return (
      <Card>
        <CardHeader title="Data Quality" />
        <CardContent>
          <div className="text-center py-8">
            <Gauge className="h-8 w-8 mx-auto text-theme-tertiary mb-2" />
            <p className="text-sm text-theme-tertiary">
              No endpoints configured. Quality is evaluated per endpoint.
            </p>
          </div>
        </CardContent>
      </Card>
    );
  }

  const results = latest?.results ?? [];

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader
          title="Data Quality"
          subtitle="Latest quality score, expectation results, and quarantine state per endpoint."
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

          {!qualityEnabled && (
            <div className="p-3 bg-theme-warning-fg/10 border border-theme-warning-border/20 rounded-lg">
              <div className="flex items-center gap-2">
                <AlertTriangle className="h-4 w-4 text-theme-warning-fg shrink-0" />
                <span className="text-sm text-theme-warning-fg">
                  Quality checks are disabled for this endpoint. Enable &quot;Quality checks&quot; to
                  evaluate expectations on each fetch.
                </span>
              </div>
            </div>
          )}

          {loadingQuality ? (
            <LoadingSpinner className="py-6" />
          ) : (
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
              <Card>
                <CardContent className="p-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-sm text-theme-tertiary">Quality Score</p>
                      <p className="text-lg font-semibold text-theme-primary">
                        {formatScore(latest?.quality_score)}
                      </p>
                    </div>
                    <Badge variant={scoreVariant(latest?.quality_score)} size="sm">
                      <Gauge className="h-3 w-3 mr-1" />
                      {formatScore(latest?.quality_score)}
                    </Badge>
                  </div>
                </CardContent>
              </Card>

              <Card>
                <CardContent className="p-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-sm text-theme-tertiary">Status</p>
                      {latest?.quality_passed == null ? (
                        <Badge variant="outline" size="sm">No data</Badge>
                      ) : latest.quality_passed ? (
                        <Badge variant="success" size="sm">
                          <ShieldCheck className="h-3 w-3 mr-1" />
                          Passing
                        </Badge>
                      ) : (
                        <Badge variant="danger" size="sm">
                          <ShieldAlert className="h-3 w-3 mr-1" />
                          Failing
                        </Badge>
                      )}
                    </div>
                  </div>
                </CardContent>
              </Card>

              <Card>
                <CardContent className="p-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-sm text-theme-tertiary">Quarantine</p>
                      {latest?.quarantined ? (
                        <Badge variant="danger" size="sm">
                          <Lock className="h-3 w-3 mr-1" />
                          Quarantined
                        </Badge>
                      ) : (
                        <Badge variant="outline" size="sm">
                          {quarantineOnFailure ? 'Armed' : 'Off'}
                        </Badge>
                      )}
                    </div>
                  </div>
                </CardContent>
              </Card>
            </div>
          )}

          {latest?.quarantined && (
            <div className="p-3 bg-theme-error-fg/10 border border-theme-error-border/20 rounded-lg">
              <div className="flex items-center gap-2">
                <Lock className="h-4 w-4 text-theme-error-fg shrink-0" />
                <span className="text-sm text-theme-error-fg">
                  Last fetch failed quality and was quarantined. Last-known-good data is served from
                  cache until quality recovers.
                </span>
              </div>
            </div>
          )}

          {latest?.evaluated_at && (
            <p className="text-xs text-theme-tertiary">
              Last evaluated: {new Date(latest.evaluated_at).toLocaleString()}
            </p>
          )}
        </CardContent>
      </Card>

      {!loadingQuality && results.length > 0 && (
        <Card>
          <CardHeader title="Latest Expectation Results" subtitle="Outcome of the most recent quality evaluation." />
          <CardContent>
            <div className="space-y-2">{results.map(renderResultRow)}</div>
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader
          title="Configured Expectations"
          subtitle="Quality rules evaluated over canonical records for this endpoint."
        />
        <CardContent>
          {loadingQuality ? (
            <LoadingSpinner className="py-6" />
          ) : expectations.length > 0 ? (
            <div className="space-y-2">{expectations.map(renderExpectationRow)}</div>
          ) : (
            <p className="text-sm text-theme-tertiary text-center py-6">
              No expectations configured. Built-in defaults (non-empty batch, uniform shape) apply
              when quality checks run.
            </p>
          )}
        </CardContent>
      </Card>
    </div>
  );
};

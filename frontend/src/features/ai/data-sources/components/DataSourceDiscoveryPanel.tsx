import React, { useCallback, useRef, useState } from 'react';
import { Search, Sparkles, ShieldCheck, Activity, Clock, Compass, X } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Input } from '@/shared/components/ui/Input';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { EntityLink } from '@/shared/components/entity';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { logger } from '@/shared/utils/logger';
import { dataSourcesApi } from '@/shared/services/ai/DataSourcesApiService';
import { humanizeSourceType } from './sourceTypeLabels';
import type {
  DataSourceDiscoveryResult,
  DataSourceDiscoverySignals,
} from '@/shared/types/ai';

interface DataSourceDiscoveryPanelProps {
  /** Notifies the parent when a result is opened (e.g. open the detail modal). */
  onSelectDataSource?: (dataSourceId: string) => void;
}

// Render a single 0..1 ranking signal as a compact, theme-aware chip. Returns
// null when the signal is absent so partial backends degrade cleanly.
const SignalChip: React.FC<{
  icon: React.ReactNode;
  label: string;
  value?: number;
}> = ({ icon, label, value }) => {
  if (typeof value !== 'number') return null;
  const pct = Math.round(value * 100);
  const tone =
    pct >= 80
      ? 'text-theme-success-fg'
      : pct >= 60
        ? 'text-theme-info-fg'
        : pct >= 40
          ? 'text-theme-warning-fg'
          : 'text-theme-tertiary';
  return (
    <span
      className="inline-flex items-center gap-1 text-xs text-theme-tertiary"
      title={`${label}: ${pct}%`}
    >
      <span className={tone}>{icon}</span>
      <span className="text-theme-secondary">{label}</span>
      <span className={`font-medium ${tone}`}>{pct}%</span>
    </span>
  );
};

const hasAnySignal = (signals?: DataSourceDiscoverySignals): boolean =>
  !!signals &&
  (typeof signals.semantic === 'number' ||
    typeof signals.effectiveness === 'number' ||
    typeof signals.health === 'number' ||
    typeof signals.recency === 'number');

export const DataSourceDiscoveryPanel: React.FC<DataSourceDiscoveryPanelProps> = ({
  onSelectDataSource,
}) => {
  const [query, setQuery] = useState('');
  const [searching, setSearching] = useState(false);
  const [results, setResults] = useState<DataSourceDiscoveryResult[]>([]);
  const [hasSearched, setHasSearched] = useState(false);
  const [lastQuery, setLastQuery] = useState('');
  const { addNotification } = useNotifications();
  const inFlight = useRef(false);

  const getSourceTypeLabel = (type: string): string => humanizeSourceType(type);

  const runDiscovery = useCallback(async () => {
    const trimmed = query.trim();
    if (!trimmed || inFlight.current) return;
    inFlight.current = true;

    try {
      setSearching(true);
      const response = await dataSourcesApi.discover(trimmed, { limit: 10 });
      setResults(response.results ?? []);
      setHasSearched(true);
      setLastQuery(trimmed);
    } catch (error) {
      logger.error('Data source discovery failed', { error, query: trimmed });
      setResults([]);
      setHasSearched(true);
      setLastQuery(trimmed);
      addNotification({
        type: 'error',
        title: 'Discovery Failed',
        message: 'Could not rank data sources for that query. Please try again.',
      });
    } finally {
      setSearching(false);
      inFlight.current = false;
    }
  }, [query, addNotification]);

  const handleKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      runDiscovery();
    }
  };

  const handleClear = () => {
    setQuery('');
    setResults([]);
    setHasSearched(false);
    setLastQuery('');
  };

  const getScoreTone = (score: number): string =>
    score >= 0.8
      ? 'text-theme-success-fg'
      : score >= 0.6
        ? 'text-theme-info-fg'
        : score >= 0.4
          ? 'text-theme-warning-fg'
          : 'text-theme-tertiary';

  return (
    <Card variant="outlined" padding="md" className="mb-6">
      <div className="flex items-center gap-2 mb-3">
        <Sparkles className="h-4 w-4 text-theme-info-fg" />
        <h3 className="text-sm font-semibold text-theme-text-primary">Discover Data Sources</h3>
      </div>
      <p className="text-xs text-theme-tertiary mb-3">
        Describe the data you need in plain language. Sources are ranked by semantic match blended
        with effectiveness, health, and recency.
      </p>

      <div className="flex items-center gap-2">
        <div className="flex-1 relative">
          <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-theme-tertiary" />
          <Input
            placeholder="e.g. hourly temperature forecasts for a US zip code"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={handleKeyDown}
            className="pl-10"
            aria-label="Data source discovery query"
          />
        </div>
        <Button
          variant="primary"
          onClick={runDiscovery}
          disabled={searching || query.trim().length === 0}
          className="flex items-center gap-2"
        >
          <Compass className={`h-4 w-4 ${searching ? 'animate-pulse' : ''}`} />
          {searching ? 'Searching...' : 'Discover'}
        </Button>
        {(query.length > 0 || hasSearched) && (
          <Button
            variant="ghost"
            onClick={handleClear}
            className="flex items-center gap-1"
            aria-label="Clear discovery results"
          >
            <X className="h-4 w-4" />
          </Button>
        )}
      </div>

      {searching && <LoadingSpinner className="py-6" />}

      {!searching && hasSearched && results.length === 0 && (
        <div className="mt-4 text-sm text-theme-tertiary text-center py-6">
          No data sources matched &ldquo;{lastQuery}&rdquo;.
        </div>
      )}

      {!searching && results.length > 0 && (
        <div className="mt-4 space-y-2">
          <p className="text-xs font-medium text-theme-text-tertiary">
            {results.length} ranked {results.length === 1 ? 'source' : 'sources'} for &ldquo;
            {lastQuery}&rdquo;
          </p>
          {results.map((result, index) => {
            const scorePct = Math.round((result.score ?? 0) * 100);
            return (
              <div
                key={result.id}
                className="flex items-start justify-between gap-3 p-3 rounded-lg border border-theme bg-theme-surface-secondary"
              >
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <span className="text-xs font-mono text-theme-tertiary">#{index + 1}</span>
                    <span className="font-medium text-theme-text-primary truncate">
                      <EntityLink type="data_source" id={result.id} label={result.name} />
                    </span>
                    {!result.is_active && (
                      <Badge variant="secondary" size="xs">
                        Inactive
                      </Badge>
                    )}
                  </div>
                  <div className="flex flex-wrap items-center gap-2 mt-1">
                    <Badge variant="outline" size="xs">
                      {getSourceTypeLabel(result.source_type)}
                    </Badge>
                    {result.health_status && (
                      <span className="text-xs text-theme-tertiary capitalize">
                        {result.health_status}
                      </span>
                    )}
                    {result.credential_count > 0 && (
                      <span className="text-xs text-theme-tertiary">
                        {result.credential_count} cred
                        {result.credential_count === 1 ? '' : 's'}
                      </span>
                    )}
                  </div>
                  {hasAnySignal(result.signals) && (
                    <div className="flex flex-wrap items-center gap-x-3 gap-y-1 mt-2">
                      <SignalChip
                        icon={<Search className="h-3 w-3" />}
                        label="Match"
                        value={result.signals?.semantic}
                      />
                      <SignalChip
                        icon={<ShieldCheck className="h-3 w-3" />}
                        label="Effectiveness"
                        value={result.signals?.effectiveness}
                      />
                      <SignalChip
                        icon={<Activity className="h-3 w-3" />}
                        label="Health"
                        value={result.signals?.health}
                      />
                      <SignalChip
                        icon={<Clock className="h-3 w-3" />}
                        label="Recency"
                        value={result.signals?.recency}
                      />
                    </div>
                  )}
                </div>

                <div className="flex flex-col items-end gap-2 shrink-0">
                  <div className="text-right" title={`Blended rank score: ${scorePct}%`}>
                    <p className={`text-lg font-semibold ${getScoreTone(result.score ?? 0)}`}>
                      {scorePct}%
                    </p>
                    <p className="text-xs text-theme-text-tertiary">score</p>
                  </div>
                  {onSelectDataSource && (
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => onSelectDataSource(result.id)}
                    >
                      View
                    </Button>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}
    </Card>
  );
};

export default DataSourceDiscoveryPanel;

import React, { useState, useEffect, useCallback } from 'react';
import { Plus, Pencil, Trash2, Save, X, Clock, Activity, FileJson } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import { Textarea } from '@/shared/components/ui/Textarea';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { dataSourcesApi } from '@/shared/services/ai/DataSourcesApiService';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { logger } from '@/shared/utils/logger';
import type {
  AiDataSourceEndpoint,
  DataSourceEndpointRequest,
  DataSourceHttpMethod,
  DataSourceResponseFormat,
} from '@/shared/types/ai';

interface DataSourceEndpointsTabProps {
  dataSourceId: string;
  canManageDataSources: boolean;
  // Manage super-grant: gates the "Import from OpenAPI" affordance (the backend
  // introspect action requires ai.data_sources.manage). Optional so existing
  // callers without import support keep working.
  canImportEndpoints?: boolean;
  onImportOpenApi?: () => void;
  onEndpointsChanged?: () => void;
}

const HTTP_METHODS: DataSourceHttpMethod[] = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD'];
const RESPONSE_FORMATS: DataSourceResponseFormat[] = [
  'json', 'xml', 'csv', 'ndjson', 'rss', 'atom', 'html', 'text', 'binary',
];

interface EndpointFormState {
  name: string;
  http_method: DataSourceHttpMethod;
  path_template: string;
  response_format: DataSourceResponseFormat | '';
  cache_ttl_seconds: string;
  response_mapping: string;
}

const EMPTY_FORM: EndpointFormState = {
  name: '',
  http_method: 'GET',
  path_template: '',
  response_format: 'json',
  cache_ttl_seconds: '',
  response_mapping: '{}',
};

// Serialize a JSON object to a pretty string for the editor textarea.
function stringifyMapping(value: Record<string, unknown> | undefined): string {
  if (!value || Object.keys(value).length === 0) return '{}';
  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return '{}';
  }
}

function endpointToForm(endpoint: AiDataSourceEndpoint): EndpointFormState {
  return {
    name: endpoint.name,
    http_method: endpoint.http_method,
    path_template: endpoint.path_template ?? '',
    response_format: endpoint.response_format ?? '',
    cache_ttl_seconds: endpoint.cache_ttl_seconds != null ? String(endpoint.cache_ttl_seconds) : '',
    response_mapping: stringifyMapping(endpoint.response_mapping),
  };
}

export const DataSourceEndpointsTab: React.FC<DataSourceEndpointsTabProps> = ({
  dataSourceId,
  canManageDataSources,
  canImportEndpoints = false,
  onImportOpenApi,
  onEndpointsChanged,
}) => {
  const { addNotification } = useNotifications();

  const [endpoints, setEndpoints] = useState<AiDataSourceEndpoint[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [deletingId, setDeletingId] = useState<string | null>(null);
  // null = closed; 'new' = create form; otherwise the endpoint id being edited.
  const [editingId, setEditingId] = useState<string | 'new' | null>(null);
  const [form, setForm] = useState<EndpointFormState>(EMPTY_FORM);
  const [mappingError, setMappingError] = useState<string | null>(null);

  const loadEndpoints = useCallback(async () => {
    if (!dataSourceId) return;
    try {
      setLoading(true);
      const items = await dataSourcesApi.getEndpoints(dataSourceId);
      setEndpoints(items);
    } catch (error) {
      logger.error('Failed to load data source endpoints', { dataSourceId, error });
      addNotification({
        type: 'error',
        title: 'Error',
        message: 'Failed to load endpoints. Please try again.',
      });
    } finally {
      setLoading(false);
    }
  }, [dataSourceId, addNotification]);

  useEffect(() => {
    loadEndpoints();
  }, [loadEndpoints]);

  const openCreateForm = () => {
    setForm(EMPTY_FORM);
    setMappingError(null);
    setEditingId('new');
  };

  const openEditForm = (endpoint: AiDataSourceEndpoint) => {
    setForm(endpointToForm(endpoint));
    setMappingError(null);
    setEditingId(endpoint.id);
  };

  const closeForm = () => {
    setEditingId(null);
    setForm(EMPTY_FORM);
    setMappingError(null);
  };

  const updateField = <K extends keyof EndpointFormState>(key: K, value: EndpointFormState[K]) => {
    setForm((prev) => ({ ...prev, [key]: value }));
  };

  // Parse the response_mapping editor; returns undefined when invalid (and sets error).
  const parseMapping = (): Record<string, unknown> | undefined => {
    const raw = form.response_mapping.trim();
    if (raw === '' || raw === '{}') {
      setMappingError(null);
      return {};
    }
    try {
      const parsed = JSON.parse(raw);
      if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
        setMappingError('Response mapping must be a JSON object.');
        return undefined;
      }
      setMappingError(null);
      return parsed as Record<string, unknown>;
    } catch {
      setMappingError('Response mapping must be valid JSON.');
      return undefined;
    }
  };

  const buildPayload = (mapping: Record<string, unknown>): DataSourceEndpointRequest => {
    const trimmedTtl = form.cache_ttl_seconds.trim();
    return {
      name: form.name.trim(),
      http_method: form.http_method,
      path_template: form.path_template.trim() || null,
      response_format: form.response_format === '' ? null : form.response_format,
      cache_ttl_seconds: trimmedTtl === '' ? null : Number(trimmedTtl),
      response_mapping: mapping,
    };
  };

  const handleSave = async () => {
    if (!form.name.trim()) {
      addNotification({ type: 'error', title: 'Validation', message: 'Endpoint name is required.' });
      return;
    }
    const trimmedTtl = form.cache_ttl_seconds.trim();
    if (trimmedTtl !== '' && (Number.isNaN(Number(trimmedTtl)) || Number(trimmedTtl) < 0)) {
      addNotification({ type: 'error', title: 'Validation', message: 'Cache TTL must be a non-negative number.' });
      return;
    }
    const mapping = parseMapping();
    if (mapping === undefined) return;

    const payload = buildPayload(mapping);

    try {
      setSaving(true);
      if (editingId === 'new') {
        await dataSourcesApi.createEndpoint(dataSourceId, payload);
        addNotification({ type: 'success', title: 'Endpoint Created', message: `Endpoint "${payload.name}" created.` });
      } else if (editingId) {
        await dataSourcesApi.updateEndpoint(dataSourceId, editingId, payload);
        addNotification({ type: 'success', title: 'Endpoint Updated', message: `Endpoint "${payload.name}" updated.` });
      }
      closeForm();
      await loadEndpoints();
      onEndpointsChanged?.();
    } catch (error) {
      logger.error('Failed to save data source endpoint', { dataSourceId, editingId, error });
      addNotification({
        type: 'error',
        title: 'Save Failed',
        message: error instanceof Error ? error.message : 'Failed to save endpoint',
      });
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async (endpoint: AiDataSourceEndpoint) => {
    if (!window.confirm(`Delete endpoint "${endpoint.name}"? This action cannot be undone.`)) {
      return;
    }
    try {
      setDeletingId(endpoint.id);
      await dataSourcesApi.deleteEndpoint(dataSourceId, endpoint.id);
      addNotification({ type: 'success', title: 'Endpoint Deleted', message: `Endpoint "${endpoint.name}" deleted.` });
      if (editingId === endpoint.id) closeForm();
      await loadEndpoints();
      onEndpointsChanged?.();
    } catch (error) {
      logger.error('Failed to delete data source endpoint', { dataSourceId, endpointId: endpoint.id, error });
      addNotification({
        type: 'error',
        title: 'Delete Failed',
        message: error instanceof Error ? error.message : 'Failed to delete endpoint',
      });
    } finally {
      setDeletingId(null);
    }
  };

  const renderForm = () => (
    <Card>
      <CardHeader
        title={editingId === 'new' ? 'New Endpoint' : 'Edit Endpoint'}
        action={
          <Button variant="ghost" size="sm" onClick={closeForm} disabled={saving}>
            <X className="h-4 w-4" />
          </Button>
        }
      />
      <CardContent className="space-y-4">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <Input
            label="Name"
            value={form.name}
            onChange={(e) => updateField('name', e.target.value)}
            placeholder="e.g. Daily Forecast"
          />
          <Select
            label="HTTP Method"
            value={form.http_method}
            onValueChange={(value) => updateField('http_method', value as DataSourceHttpMethod)}
            options={HTTP_METHODS.map((m) => ({ value: m, label: m }))}
          />
        </div>

        <Input
          label="Path Template"
          value={form.path_template}
          onChange={(e) => updateField('path_template', e.target.value)}
          placeholder="/v1/forecast/{location}"
          description="Relative to the data source base URL. Use {var} placeholders for params."
        />

        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <Select
            label="Response Format"
            value={form.response_format}
            onValueChange={(value) => updateField('response_format', value as DataSourceResponseFormat | '')}
            options={[
              { value: '', label: 'Auto-detect' },
              ...RESPONSE_FORMATS.map((f) => ({ value: f, label: f.toUpperCase() })),
            ]}
          />
          <Input
            label="Cache TTL (seconds)"
            type="number"
            min={0}
            value={form.cache_ttl_seconds}
            onChange={(e) => updateField('cache_ttl_seconds', e.target.value)}
            placeholder="Source default"
            description="How long responses are cached. Leave blank for the default."
          />
        </div>

        <Textarea
          label="Response Mapping"
          value={form.response_mapping}
          onChange={(e) => updateField('response_mapping', e.target.value)}
          error={mappingError ?? undefined}
          description="JSON object of normalization rules applied to canonical records."
          rows={6}
          className="font-mono text-xs"
          spellCheck={false}
        />

        <div className="flex items-center justify-end gap-2 pt-2">
          <Button variant="outline" onClick={closeForm} disabled={saving}>
            Cancel
          </Button>
          <Button variant="primary" onClick={handleSave} loading={saving}>
            <Save className="h-4 w-4 mr-2" />
            {editingId === 'new' ? 'Create Endpoint' : 'Save Changes'}
          </Button>
        </div>
      </CardContent>
    </Card>
  );

  const renderEndpointRow = (endpoint: AiDataSourceEndpoint) => (
    <div
      key={endpoint.id}
      className="flex items-start justify-between p-3 border border-theme rounded-lg gap-3"
    >
      <div className="min-w-0">
        <div className="flex items-center gap-2 flex-wrap">
          <Badge variant="info" size="sm">{endpoint.http_method}</Badge>
          <p className="text-sm font-medium text-theme-primary truncate">{endpoint.name}</p>
          {endpoint.monitorable && (
            <Badge variant="outline" size="sm">
              <Activity className="h-3 w-3 mr-1" />
              Monitored
            </Badge>
          )}
        </div>
        <p className="mt-1 text-xs text-theme-tertiary font-mono break-all">
          {endpoint.path_template || '(no path template)'}
        </p>
        <div className="mt-1 flex items-center gap-4 text-xs text-theme-tertiary flex-wrap">
          <span>Format: {endpoint.response_format ?? 'auto'}</span>
          <span className="flex items-center gap-1">
            <Clock className="h-3 w-3" />
            {endpoint.cache_ttl_seconds != null ? `${endpoint.cache_ttl_seconds}s cache` : 'default cache'}
          </span>
          <span className="font-mono">{endpoint.slug}</span>
        </div>
      </div>
      {canManageDataSources && (
        <div className="flex items-center gap-1 shrink-0">
          <Button variant="ghost" size="sm" onClick={() => openEditForm(endpoint)} disabled={saving}>
            <Pencil className="h-4 w-4" />
          </Button>
          <Button
            variant="danger"
            size="sm"
            onClick={() => handleDelete(endpoint)}
            loading={deletingId === endpoint.id}
            disabled={saving}
          >
            <Trash2 className="h-4 w-4" />
          </Button>
        </div>
      )}
    </div>
  );

  if (loading) {
    return (
      <Card>
        <CardHeader title="Endpoints" />
        <CardContent>
          <LoadingSpinner className="py-8" />
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader
          title="Endpoints"
          subtitle="Governed external-fetch endpoint definitions for this data source."
          action={
            editingId === null && (canManageDataSources || canImportEndpoints) ? (
              <div className="flex items-center gap-2">
                {canImportEndpoints && onImportOpenApi && (
                  <Button variant="outline" onClick={onImportOpenApi}>
                    <FileJson className="h-4 w-4 mr-2" />
                    Import from OpenAPI
                  </Button>
                )}
                {canManageDataSources && (
                  <Button variant="outline" onClick={openCreateForm}>
                    <Plus className="h-4 w-4 mr-2" />
                    Add Endpoint
                  </Button>
                )}
              </div>
            ) : undefined
          }
        />
        <CardContent>
          {endpoints.length > 0 ? (
            <div className="space-y-3">{endpoints.map(renderEndpointRow)}</div>
          ) : (
            <div className="text-center py-8">
              <p className="text-sm text-theme-tertiary">No endpoints configured for this data source.</p>
              {canManageDataSources && (
                <p className="text-sm text-theme-tertiary mt-1">
                  Click &quot;Add Endpoint&quot; to define a fetchable endpoint.
                </p>
              )}
            </div>
          )}
        </CardContent>
      </Card>

      {editingId !== null && canManageDataSources && renderForm()}
    </div>
  );
};

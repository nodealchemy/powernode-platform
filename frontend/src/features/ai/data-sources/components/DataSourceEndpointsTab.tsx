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
  DataSourceEndpointPagination,
  DataSourceEndpointIncremental,
  DataSourceHttpMethod,
  DataSourceIncrementalMode,
  DataSourcePaginationType,
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

// '' = pagination disabled (single request — the default). Each type enables a
// distinct set of param fields below.
const PAGINATION_TYPE_OPTIONS: ReadonlyArray<{ value: DataSourcePaginationType | ''; label: string }> = [
  { value: '', label: 'None (single request)' },
  { value: 'offset', label: 'Offset / limit' },
  { value: 'page', label: 'Page number' },
  { value: 'cursor', label: 'Cursor' },
  { value: 'link', label: 'Link header' },
];

// '' = incremental sync disabled (full fetch each poll — the default). "cursor"
// carries an opaque token, "timestamp" carries a high-watermark time value.
const INCREMENTAL_MODE_OPTIONS: ReadonlyArray<{ value: DataSourceIncrementalMode | ''; label: string }> = [
  { value: '', label: 'Off (full fetch each poll)' },
  { value: 'cursor', label: 'Cursor token' },
  { value: 'timestamp', label: 'Timestamp high-watermark' },
];

interface EndpointFormState {
  name: string;
  http_method: DataSourceHttpMethod;
  path_template: string;
  response_format: DataSourceResponseFormat | '';
  cache_ttl_seconds: string;
  response_mapping: string;
  // Outbound pagination (optional). pagination_type === '' leaves it off.
  pagination_type: DataSourcePaginationType | '';
  pagination_limit_param: string;
  pagination_offset_param: string;
  pagination_page_param: string;
  pagination_cursor_param: string;
  pagination_cursor_path: string;
  pagination_max_pages: string;
  // Incremental sync (optional). incremental_mode === '' leaves it off.
  incremental_mode: DataSourceIncrementalMode | '';
  incremental_cursor_param: string;
  incremental_cursor_path: string;
}

const EMPTY_FORM: EndpointFormState = {
  name: '',
  http_method: 'GET',
  path_template: '',
  response_format: 'json',
  cache_ttl_seconds: '',
  response_mapping: '{}',
  pagination_type: '',
  pagination_limit_param: '',
  pagination_offset_param: '',
  pagination_page_param: '',
  pagination_cursor_param: '',
  pagination_cursor_path: '',
  pagination_max_pages: '',
  incremental_mode: '',
  incremental_cursor_param: '',
  incremental_cursor_path: '',
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
  const pagination = endpoint.pagination ?? {};
  const incremental = endpoint.incremental ?? {};
  return {
    name: endpoint.name,
    http_method: endpoint.http_method,
    path_template: endpoint.path_template ?? '',
    response_format: endpoint.response_format ?? '',
    cache_ttl_seconds: endpoint.cache_ttl_seconds != null ? String(endpoint.cache_ttl_seconds) : '',
    response_mapping: stringifyMapping(endpoint.response_mapping),
    pagination_type: pagination.type ?? '',
    pagination_limit_param: pagination.limit_param ?? '',
    pagination_offset_param: pagination.offset_param ?? '',
    pagination_page_param: pagination.page_param ?? '',
    pagination_cursor_param: pagination.cursor_param ?? '',
    pagination_cursor_path: pagination.cursor_path ?? '',
    pagination_max_pages: pagination.max_pages != null ? String(pagination.max_pages) : '',
    incremental_mode: incremental.mode ?? '',
    incremental_cursor_param: incremental.cursor_param ?? '',
    incremental_cursor_path: incremental.cursor_path ?? '',
  };
}

// Assemble the pagination jsonb payload from the form. Returns {} when disabled
// (single request) so the backend default is preserved. Only includes the param
// fields relevant to the selected type.
function buildPaginationPayload(form: EndpointFormState): DataSourceEndpointPagination {
  if (form.pagination_type === '') return {};

  const pagination: DataSourceEndpointPagination = { type: form.pagination_type };

  const limitParam = form.pagination_limit_param.trim();
  if (limitParam) pagination.limit_param = limitParam;

  if (form.pagination_type === 'offset') {
    const offsetParam = form.pagination_offset_param.trim();
    if (offsetParam) pagination.offset_param = offsetParam;
  } else if (form.pagination_type === 'page') {
    const pageParam = form.pagination_page_param.trim();
    if (pageParam) pagination.page_param = pageParam;
  } else if (form.pagination_type === 'cursor') {
    const cursorParam = form.pagination_cursor_param.trim();
    if (cursorParam) pagination.cursor_param = cursorParam;
    const cursorPath = form.pagination_cursor_path.trim();
    if (cursorPath) pagination.cursor_path = cursorPath;
  }

  const maxPages = form.pagination_max_pages.trim();
  if (maxPages) pagination.max_pages = Number(maxPages);

  return pagination;
}

// Assemble the incremental jsonb payload from the form. Returns {} when disabled
// (full fetch each poll) so the backend default is preserved.
function buildIncrementalPayload(form: EndpointFormState): DataSourceEndpointIncremental {
  if (form.incremental_mode === '') return {};

  const incremental: DataSourceEndpointIncremental = { mode: form.incremental_mode };

  const cursorParam = form.incremental_cursor_param.trim();
  if (cursorParam) incremental.cursor_param = cursorParam;
  const cursorPath = form.incremental_cursor_path.trim();
  if (cursorPath) incremental.cursor_path = cursorPath;

  return incremental;
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
      // {} when pagination disabled — keeps single-request behavior unchanged.
      pagination: buildPaginationPayload(form),
      // {} when incremental disabled — keeps full-fetch behavior unchanged.
      incremental: buildIncrementalPayload(form),
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
    const trimmedMaxPages = form.pagination_max_pages.trim();
    if (
      form.pagination_type !== '' &&
      trimmedMaxPages !== '' &&
      (Number.isNaN(Number(trimmedMaxPages)) || Number(trimmedMaxPages) < 1)
    ) {
      addNotification({ type: 'error', title: 'Validation', message: 'Max pages must be a whole number ≥ 1.' });
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

        {/* Pagination (optional). Disabled by default → single request. */}
        <div className="space-y-4 rounded-lg border border-dashed border-theme p-4">
          <div>
            <p className="text-sm font-medium text-theme-primary">Pagination (optional)</p>
            <p className="text-xs text-theme-tertiary mt-1">
              When enabled, the fetch follows pages up to the max (hard-capped server-side),
              concatenating records. Leave as &quot;None&quot; for a single request.
            </p>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <Select
              label="Strategy"
              value={form.pagination_type}
              onValueChange={(value) => updateField('pagination_type', value as DataSourcePaginationType | '')}
              options={PAGINATION_TYPE_OPTIONS.map((opt) => ({ value: opt.value, label: opt.label }))}
            />
            {form.pagination_type !== '' && (
              <Input
                label="Max Pages"
                type="number"
                min={1}
                value={form.pagination_max_pages}
                onChange={(e) => updateField('pagination_max_pages', e.target.value)}
                placeholder="Server default cap"
                description="Hard cap on follow-up requests."
              />
            )}
          </div>

          {form.pagination_type !== '' && (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <Input
                label="Limit Param"
                value={form.pagination_limit_param}
                onChange={(e) => updateField('pagination_limit_param', e.target.value)}
                placeholder="e.g. limit"
                description="Query param controlling page size."
              />

              {form.pagination_type === 'offset' && (
                <Input
                  label="Offset Param"
                  value={form.pagination_offset_param}
                  onChange={(e) => updateField('pagination_offset_param', e.target.value)}
                  placeholder="e.g. offset"
                  description="Query param for the row offset."
                />
              )}

              {form.pagination_type === 'page' && (
                <Input
                  label="Page Param"
                  value={form.pagination_page_param}
                  onChange={(e) => updateField('pagination_page_param', e.target.value)}
                  placeholder="e.g. page"
                  description="Query param for the page number."
                />
              )}

              {form.pagination_type === 'cursor' && (
                <>
                  <Input
                    label="Cursor Param"
                    value={form.pagination_cursor_param}
                    onChange={(e) => updateField('pagination_cursor_param', e.target.value)}
                    placeholder="e.g. cursor"
                    description="Query param carrying the next cursor."
                  />
                  <Input
                    label="Cursor Path"
                    value={form.pagination_cursor_path}
                    onChange={(e) => updateField('pagination_cursor_path', e.target.value)}
                    placeholder="e.g. meta.next_cursor"
                    description="JSON path to read the next cursor from the response."
                  />
                </>
              )}
            </div>
          )}
        </div>

        {/* Incremental sync (optional). Disabled by default → full fetch each poll. */}
        <div className="space-y-4 rounded-lg border border-dashed border-theme p-4">
          <div>
            <p className="text-sm font-medium text-theme-primary">Incremental sync (optional)</p>
            <p className="text-xs text-theme-tertiary mt-1">
              When enabled, monitored subscriptions carry a high-watermark between polls: the
              stored cursor is injected into the request param, and the next cursor is read back
              from the response. Leave as &quot;Off&quot; to fetch the full payload each poll.
            </p>
          </div>

          <Select
            label="Mode"
            value={form.incremental_mode}
            onValueChange={(value) => updateField('incremental_mode', value as DataSourceIncrementalMode | '')}
            options={INCREMENTAL_MODE_OPTIONS.map((opt) => ({ value: opt.value, label: opt.label }))}
          />

          {form.incremental_mode !== '' && (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <Input
                label="Cursor Param"
                value={form.incremental_cursor_param}
                onChange={(e) => updateField('incremental_cursor_param', e.target.value)}
                placeholder={form.incremental_mode === 'timestamp' ? 'e.g. updated_since' : 'e.g. since'}
                description="Request param carrying the stored high-watermark."
              />
              <Input
                label="Cursor Path"
                value={form.incremental_cursor_path}
                onChange={(e) => updateField('incremental_cursor_path', e.target.value)}
                placeholder={form.incremental_mode === 'timestamp' ? 'e.g. meta.max_updated_at' : 'e.g. meta.next_cursor'}
                description="JSON path to read the next high-watermark from the response."
              />
            </div>
          )}
        </div>

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

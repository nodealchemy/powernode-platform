import React, { useState } from 'react';
import { FileJson, Eye, Download, AlertCircle, CheckCircle2 } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import { Textarea } from '@/shared/components/ui/Textarea';
import { dataSourcesApi } from '@/shared/services/ai/DataSourcesApiService';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { logger } from '@/shared/utils/logger';
import type {
  DataSourceOpenApiImportPreview,
  DataSourceOpenApiImportRequest,
  DataSourceOpenApiImportResult,
} from '@/shared/types/ai';

interface DataSourceImportOpenApiModalProps {
  isOpen: boolean;
  onClose: () => void;
  dataSourceId: string;
  onImported?: () => void;
}

type ImportMode = 'paste' | 'url';

export const DataSourceImportOpenApiModal: React.FC<DataSourceImportOpenApiModalProps> = ({
  isOpen,
  onClose,
  dataSourceId,
  onImported,
}) => {
  const { addNotification } = useNotifications();

  const [mode, setMode] = useState<ImportMode>('paste');
  const [specText, setSpecText] = useState('');
  const [url, setUrl] = useState('');
  const [specError, setSpecError] = useState<string | null>(null);
  const [previewing, setPreviewing] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [preview, setPreview] = useState<DataSourceOpenApiImportResult | null>(null);

  const resetState = () => {
    setMode('paste');
    setSpecText('');
    setUrl('');
    setSpecError(null);
    setPreview(null);
    setPreviewing(false);
    setConfirming(false);
  };

  const handleClose = () => {
    resetState();
    onClose();
  };

  // Build the import request from the active mode. Paste mode parses the JSON
  // client-side for immediate feedback; URL mode passes the URL through for the
  // server to fetch (SSRF-guarded server-side). Returns undefined on bad input.
  const buildRequest = (dryRun: boolean): DataSourceOpenApiImportRequest | undefined => {
    if (mode === 'url') {
      const trimmed = url.trim();
      if (trimmed === '') {
        setSpecError('Enter an OpenAPI document URL.');
        return undefined;
      }
      setSpecError(null);
      return { url: trimmed, dry_run: dryRun };
    }

    const raw = specText.trim();
    if (raw === '') {
      setSpecError('Paste an OpenAPI 3 JSON document.');
      return undefined;
    }
    try {
      const parsed = JSON.parse(raw);
      if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
        setSpecError('OpenAPI spec must be a JSON object.');
        return undefined;
      }
      setSpecError(null);
      return { spec: parsed as Record<string, unknown>, dry_run: dryRun };
    } catch {
      setSpecError('Spec must be valid JSON.');
      return undefined;
    }
  };

  const handlePreview = async () => {
    const request = buildRequest(true);
    if (!request) return;
    try {
      setPreviewing(true);
      setPreview(null);
      const result = await dataSourcesApi.importOpenApi(dataSourceId, request);
      setPreview(result);
      if ((result.preview?.length ?? 0) === 0) {
        addNotification({
          type: 'warning',
          title: 'No Endpoints Found',
          message: 'The document produced no importable endpoints.',
        });
      }
    } catch (error) {
      logger.error('OpenAPI import preview failed', { dataSourceId, error });
      addNotification({
        type: 'error',
        title: 'Preview Failed',
        message: error instanceof Error ? error.message : 'Failed to preview import',
      });
    } finally {
      setPreviewing(false);
    }
  };

  const handleConfirm = async () => {
    const request = buildRequest(false);
    if (!request) return;
    try {
      setConfirming(true);
      const result = await dataSourcesApi.importOpenApi(dataSourceId, request);
      const createdCount = result.created?.length ?? 0;
      addNotification({
        type: createdCount > 0 ? 'success' : 'warning',
        title: 'Import Complete',
        message:
          createdCount > 0
            ? `Imported ${createdCount} endpoint${createdCount === 1 ? '' : 's'}.`
            : 'No new endpoints were created (duplicates skipped).',
      });
      onImported?.();
      handleClose();
    } catch (error) {
      logger.error('OpenAPI import failed', { dataSourceId, error });
      addNotification({
        type: 'error',
        title: 'Import Failed',
        message: error instanceof Error ? error.message : 'Failed to import endpoints',
      });
    } finally {
      setConfirming(false);
    }
  };

  const previewItems: DataSourceOpenApiImportPreview[] = preview?.preview ?? [];
  const previewErrors: string[] = preview?.errors ?? [];
  const busy = previewing || confirming;

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleClose}
      title="Import from OpenAPI"
      subtitle="Generate governed endpoints from an OpenAPI 3 document."
      maxWidth="2xl"
      icon={<FileJson />}
      footer={
        <div className="flex items-center justify-end gap-2">
          <Button variant="outline" onClick={handleClose} disabled={busy}>
            Cancel
          </Button>
          <Button variant="secondary" onClick={handlePreview} loading={previewing} disabled={confirming}>
            <Eye className="h-4 w-4 mr-2" />
            Preview
          </Button>
          <Button
            variant="primary"
            onClick={handleConfirm}
            loading={confirming}
            disabled={previewing || previewItems.length === 0}
          >
            <Download className="h-4 w-4 mr-2" />
            Import {previewItems.length > 0 ? `(${previewItems.length})` : ''}
          </Button>
        </div>
      }
    >
      <div className="space-y-4">
        <Select
          label="Source"
          value={mode}
          onValueChange={(value) => {
            setMode(value as ImportMode);
            setSpecError(null);
            setPreview(null);
          }}
          options={[
            { value: 'paste', label: 'Paste JSON' },
            { value: 'url', label: 'Fetch from URL' },
          ]}
        />

        {mode === 'paste' ? (
          <Textarea
            label="OpenAPI 3 Document (JSON)"
            value={specText}
            onChange={(e) => setSpecText(e.target.value)}
            error={specError ?? undefined}
            description="Paste the full OpenAPI 3 JSON. Parsed structurally: paths become endpoints."
            rows={10}
            className="font-mono text-xs"
            spellCheck={false}
          />
        ) : (
          <Input
            label="OpenAPI Document URL"
            value={url}
            onChange={(e) => setUrl(e.target.value)}
            error={specError ?? undefined}
            placeholder="https://api.example.com/openapi.json"
            description="The server fetches and parses the document (SSRF-guarded)."
          />
        )}

        {preview && (
          <div className="space-y-3 pt-2 border-t border-theme">
            <div className="flex items-center gap-2">
              <Badge variant="info" size="sm">Dry run</Badge>
              <span className="text-sm text-theme-secondary">
                {previewItems.length} endpoint{previewItems.length === 1 ? '' : 's'} to import
              </span>
            </div>

            {previewItems.length > 0 && (
              <div className="space-y-2 max-h-72 overflow-auto">
                {previewItems.map((item, index) => (
                  <div
                    key={item.slug ?? `${item.http_method}-${item.path_template}-${index}`}
                    className="flex items-start gap-2 p-2.5 border border-theme rounded-lg"
                  >
                    <CheckCircle2 className="h-4 w-4 text-theme-success-fg shrink-0 mt-0.5" />
                    <div className="min-w-0">
                      <div className="flex items-center gap-2 flex-wrap">
                        <Badge variant="info" size="xs">{item.http_method}</Badge>
                        <span className="text-sm font-medium text-theme-primary truncate">
                          {item.name}
                        </span>
                      </div>
                      <p className="mt-0.5 text-xs text-theme-tertiary font-mono break-all">
                        {item.path_template || '(no path template)'}
                      </p>
                    </div>
                  </div>
                ))}
              </div>
            )}

            {previewErrors.length > 0 && (
              <div className="p-3 bg-theme-warning-fg/10 border border-theme-warning-border/20 rounded-lg space-y-1">
                <div className="flex items-center gap-2">
                  <AlertCircle className="h-4 w-4 text-theme-warning-fg shrink-0" />
                  <span className="text-sm font-medium text-theme-warning-fg">
                    {previewErrors.length} warning{previewErrors.length === 1 ? '' : 's'}
                  </span>
                </div>
                <ul className="text-xs text-theme-warning-fg list-disc pl-6 space-y-0.5">
                  {previewErrors.map((err, index) => (
                    <li key={index} className="break-words">{err}</li>
                  ))}
                </ul>
              </div>
            )}
          </div>
        )}
      </div>
    </Modal>
  );
};

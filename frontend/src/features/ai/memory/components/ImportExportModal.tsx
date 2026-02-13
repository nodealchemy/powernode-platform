import { useState, useRef } from 'react';
import { contextApi } from '../api/contextApi';
import { useNotifications } from '@/shared/hooks/useNotifications';

interface ImportExportModalProps {
  contextId: string;
  contextName: string;
  isOpen: boolean;
  onClose: () => void;
  onComplete?: () => void;
}

type ModalMode = 'select' | 'export' | 'import';

export function ImportExportModal({
  contextId,
  contextName,
  isOpen,
  onClose,
  onComplete,
}: ImportExportModalProps) {
  const { showNotification } = useNotifications();
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [mode, setMode] = useState<ModalMode>('select');
  const [exportFormat, setExportFormat] = useState<'json' | 'csv'>('json');
  const [isProcessing, setIsProcessing] = useState(false);
  const [exportResult, setExportResult] = useState<{
    url: string;
    count: number;
    expiresAt: string;
  } | null>(null);
  const [importResult, setImportResult] = useState<{
    imported: number;
    skipped: number;
    errors: string[];
  } | null>(null);
  const [selectedFile, setSelectedFile] = useState<File | null>(null);

  if (!isOpen) return null;

  const handleExport = async () => {
    setIsProcessing(true);
    const response = await contextApi.exportContext(contextId, exportFormat);

    if (response.success && response.data) {
      setExportResult({
        url: response.data.export_url,
        count: response.data.entry_count,
        expiresAt: response.data.expires_at,
      });
      showNotification('Export ready', 'success');
    } else {
      showNotification(response.error || 'Export failed', 'error');
    }
    setIsProcessing(false);
  };

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      setSelectedFile(file);
    }
  };

  const handleImport = async () => {
    if (!selectedFile) return;

    setIsProcessing(true);
    const response = await contextApi.importToContext(contextId, selectedFile);

    if (response.success && response.data) {
      setImportResult(response.data);
      showNotification(`Imported ${response.data.imported} entries`, 'success');
      onComplete?.();
    } else {
      showNotification(response.error || 'Import failed', 'error');
    }
    setIsProcessing(false);
  };

  const handleClose = () => {
    setMode('select');
    setExportResult(null);
    setImportResult(null);
    setSelectedFile(null);
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-50">
      <div className="bg-theme-surface border border-theme rounded-lg w-full max-w-lg mx-4 max-h-[90vh] overflow-y-auto">
        <div className="p-6">
          {/* Header */}
          <div className="flex items-center justify-between mb-6">
            <h2 className="text-lg font-semibold text-theme-primary">
              {mode === 'select' && 'Import / Export'}
              {mode === 'export' && 'Export Context'}
              {mode === 'import' && 'Import to Context'}
            </h2>
            <button
              onClick={handleClose}
              className="text-theme-tertiary hover:text-theme-primary transition-colors"
            >
              ✕
            </button>
          </div>

          {/* Mode Selection */}
          {mode === 'select' && (
            <div className="space-y-4">
              <p className="text-sm text-theme-secondary">
                Export or import entries for <strong>{contextName}</strong>
              </p>

              <div className="grid grid-cols-2 gap-4">
                <button
                  onClick={() => setMode('export')}
                  className="p-6 bg-theme-surface border border-theme rounded-lg hover:border-theme-primary transition-colors text-left cursor-pointer"
                >
                  <div className="text-2xl mb-2">📤</div>
                  <h3 className="font-medium text-theme-primary">Export</h3>
                  <p className="text-sm text-theme-secondary mt-1">
                    Download context data as JSON or CSV
                  </p>
                </button>

                <button
                  onClick={() => setMode('import')}
                  className="p-6 bg-theme-surface border border-theme rounded-lg hover:border-theme-primary transition-colors text-left cursor-pointer"
                >
                  <div className="text-2xl mb-2">📥</div>
                  <h3 className="font-medium text-theme-primary">Import</h3>
                  <p className="text-sm text-theme-secondary mt-1">
                    Upload entries from a file
                  </p>
                </button>
              </div>
            </div>
          )}

          {/* Export Mode */}
          {mode === 'export' && !exportResult && (
            <div className="space-y-4">
              <button
                onClick={() => setMode('select')}
                className="text-sm text-theme-primary hover:underline"
              >
                ← Back
              </button>

              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Export Format
                </label>
                <div className="flex gap-4">
                  <label className="flex items-center gap-2 cursor-pointer">
                    <input
                      type="radio"
                      name="format"
                      value="json"
                      checked={exportFormat === 'json'}
                      onChange={() => setExportFormat('json')}
                      className="text-theme-primary focus:ring-theme-primary"
                    />
                    <span className="text-theme-primary">JSON</span>
                  </label>
                  <label className="flex items-center gap-2 cursor-pointer">
                    <input
                      type="radio"
                      name="format"
                      value="csv"
                      checked={exportFormat === 'csv'}
                      onChange={() => setExportFormat('csv')}
                      className="text-theme-primary focus:ring-theme-primary"
                    />
                    <span className="text-theme-primary">CSV</span>
                  </label>
                </div>
              </div>

              <div className="p-4 bg-theme-surface rounded-lg text-sm">
                <h4 className="font-medium text-theme-primary mb-2">What's included:</h4>
                <ul className="space-y-1 text-theme-secondary">
                  <li>• All entries with their content and metadata</li>
                  <li>• Tags and relationships</li>
                  <li>• Importance and confidence scores</li>
                  <li>• Created and updated timestamps</li>
                </ul>
              </div>

              <button
                onClick={handleExport}
                disabled={isProcessing}
                className="w-full py-3 bg-theme-interactive-primary text-white rounded-lg hover:bg-theme-interactive-primary-hover disabled:opacity-50 transition-colors"
              >
                {isProcessing ? 'Preparing Export...' : 'Export Context'}
              </button>
            </div>
          )}

          {/* Export Result */}
          {mode === 'export' && exportResult && (
            <div className="space-y-4">
              <div className="text-center py-6">
                <div className="text-4xl mb-4">✅</div>
                <h3 className="text-lg font-medium text-theme-primary">Export Ready</h3>
                <p className="text-theme-secondary mt-1">
                  {exportResult.count} entries exported
                </p>
              </div>

              <a
                href={exportResult.url}
                download
                className="block w-full py-3 bg-theme-interactive-primary text-white rounded-lg hover:bg-theme-interactive-primary-hover transition-colors text-center"
              >
                Download {exportFormat.toUpperCase()} File
              </a>

              <p className="text-xs text-theme-tertiary text-center">
                Link expires {new Date(exportResult.expiresAt).toLocaleString()}
              </p>
            </div>
          )}

          {/* Import Mode */}
          {mode === 'import' && !importResult && (
            <div className="space-y-4">
              <button
                onClick={() => setMode('select')}
                className="text-sm text-theme-primary hover:underline"
              >
                ← Back
              </button>

              <div
                onClick={() => fileInputRef.current?.click()}
                className={`p-8 border-2 border-dashed rounded-lg text-center cursor-pointer transition-colors ${
                  selectedFile
                    ? 'border-theme-interactive-primary bg-theme-surface-selected'
                    : 'border-theme hover:border-theme-secondary'
                }`}
              >
                <input
                  ref={fileInputRef}
                  type="file"
                  accept=".json,.csv"
                  onChange={handleFileSelect}
                  className="hidden"
                />
                {selectedFile ? (
                  <>
                    <div className="text-2xl mb-2">📄</div>
                    <p className="font-medium text-theme-primary">{selectedFile.name}</p>
                    <p className="text-sm text-theme-secondary mt-1">
                      {(selectedFile.size / 1024).toFixed(2)} KB
                    </p>
                    <p className="text-xs text-theme-tertiary mt-2">
                      Click to select a different file
                    </p>
                  </>
                ) : (
                  <>
                    <div className="text-2xl mb-2">📁</div>
                    <p className="text-theme-primary">Click to select a file</p>
                    <p className="text-sm text-theme-secondary mt-1">
                      Supports JSON and CSV formats
                    </p>
                  </>
                )}
              </div>

              <div className="p-4 bg-theme-surface rounded-lg text-sm">
                <h4 className="font-medium text-theme-primary mb-2">Import Notes:</h4>
                <ul className="space-y-1 text-theme-secondary">
                  <li>• Duplicate keys will be skipped</li>
                  <li>• Invalid entries will be reported</li>
                  <li>• Embeddings will be generated automatically</li>
                </ul>
              </div>

              <button
                onClick={handleImport}
                disabled={isProcessing || !selectedFile}
                className="w-full py-3 bg-theme-interactive-primary text-white rounded-lg hover:bg-theme-interactive-primary-hover disabled:opacity-50 transition-colors"
              >
                {isProcessing ? 'Importing...' : 'Import Entries'}
              </button>
            </div>
          )}

          {/* Import Result */}
          {mode === 'import' && importResult && (
            <div className="space-y-4">
              <div className="text-center py-6">
                <div className="text-4xl mb-4">
                  {importResult.errors.length === 0 ? '✅' : '⚠️'}
                </div>
                <h3 className="text-lg font-medium text-theme-primary">Import Complete</h3>
              </div>

              <div className="grid grid-cols-3 gap-4 text-center">
                <div className="p-4 bg-theme-success bg-opacity-10 rounded-lg">
                  <p className="text-2xl font-semibold text-theme-success">
                    {importResult.imported}
                  </p>
                  <p className="text-sm text-theme-secondary">Imported</p>
                </div>
                <div className="p-4 bg-theme-warning bg-opacity-10 rounded-lg">
                  <p className="text-2xl font-semibold text-theme-warning">
                    {importResult.skipped}
                  </p>
                  <p className="text-sm text-theme-secondary">Skipped</p>
                </div>
                <div className="p-4 bg-theme-error bg-opacity-10 rounded-lg">
                  <p className="text-2xl font-semibold text-theme-error">
                    {importResult.errors.length}
                  </p>
                  <p className="text-sm text-theme-secondary">Errors</p>
                </div>
              </div>

              {importResult.errors.length > 0 && (
                <div className="p-4 bg-theme-error bg-opacity-10 rounded-lg">
                  <h4 className="font-medium text-theme-error mb-2">Errors:</h4>
                  <ul className="space-y-1 text-sm text-theme-error">
                    {importResult.errors.slice(0, 5).map((error, i) => (
                      <li key={i}>• {error}</li>
                    ))}
                    {importResult.errors.length > 5 && (
                      <li>... and {importResult.errors.length - 5} more</li>
                    )}
                  </ul>
                </div>
              )}

              <button
                onClick={handleClose}
                className="w-full py-3 bg-theme-interactive-primary text-white rounded-lg hover:bg-theme-interactive-primary-hover transition-colors"
              >
                Done
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

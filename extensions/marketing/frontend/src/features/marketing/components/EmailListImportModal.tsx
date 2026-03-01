import React, { useState, useRef } from 'react';
import { Upload, X, FileText } from 'lucide-react';
import { logger } from '@/shared/utils/logger';

interface EmailListImportModalProps {
  onImport: (file: File) => Promise<{ imported: number; skipped: number; errors: number } | undefined>;
  onClose: () => void;
}

export const EmailListImportModal: React.FC<EmailListImportModalProps> = ({ onImport, onClose }) => {
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [importing, setImporting] = useState(false);
  const [result, setResult] = useState<{ imported: number; skipped: number; errors: number } | null>(null);

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      setSelectedFile(file);
      setResult(null);
    }
  };

  const handleImport = async () => {
    if (!selectedFile) return;
    try {
      setImporting(true);
      const importResult = await onImport(selectedFile);
      if (importResult) {
        setResult(importResult);
      }
    } catch (err) {
      logger.error('Import failed:', err);
    } finally {
      setImporting(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-50">
      <div className="card-theme-elevated p-6 w-full max-w-md">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-medium text-theme-primary">Import Subscribers</h3>
          <button onClick={onClose} className="p-1 rounded hover:bg-theme-surface-hover text-theme-secondary">
            <X className="w-5 h-5" />
          </button>
        </div>

        <div className="space-y-4">
          <p className="text-sm text-theme-secondary">
            Upload a CSV file with subscriber data. The file should have columns: email, first_name, last_name.
          </p>

          {/* File Drop Zone */}
          <div
            onClick={() => fileInputRef.current?.click()}
            className="border-2 border-dashed border-theme-border rounded-lg p-8 text-center cursor-pointer hover:border-theme-primary transition-colors"
          >
            {selectedFile ? (
              <div className="flex items-center justify-center gap-2">
                <FileText className="w-6 h-6 text-theme-info" />
                <div>
                  <p className="text-sm font-medium text-theme-primary">{selectedFile.name}</p>
                  <p className="text-xs text-theme-tertiary">
                    {(selectedFile.size / 1024).toFixed(1)} KB
                  </p>
                </div>
              </div>
            ) : (
              <>
                <Upload className="w-8 h-8 text-theme-tertiary mx-auto mb-2" />
                <p className="text-sm text-theme-secondary">Click to select a CSV file</p>
                <p className="text-xs text-theme-tertiary mt-1">Supports .csv files</p>
              </>
            )}
          </div>

          <input
            ref={fileInputRef}
            type="file"
            accept=".csv"
            onChange={handleFileSelect}
            className="hidden"
          />

          {/* Result */}
          {result && (
            <div className="card-theme p-4 space-y-1">
              <p className="text-sm text-theme-success">
                Imported: {result.imported}
              </p>
              {result.skipped > 0 && (
                <p className="text-sm text-theme-warning">
                  Skipped: {result.skipped}
                </p>
              )}
              {result.errors > 0 && (
                <p className="text-sm text-theme-error">
                  Errors: {result.errors}
                </p>
              )}
            </div>
          )}

          {/* Actions */}
          <div className="flex justify-end gap-3 pt-2">
            <button onClick={onClose} className="btn-theme btn-theme-secondary">
              {result ? 'Done' : 'Cancel'}
            </button>
            {!result && (
              <button
                onClick={handleImport}
                disabled={!selectedFile || importing}
                className="btn-theme btn-theme-primary disabled:opacity-50"
              >
                {importing ? 'Importing...' : 'Import'}
              </button>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

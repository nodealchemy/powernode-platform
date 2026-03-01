import React from 'react';
import { Upload, Download, AlertCircle } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { cn } from '@/shared/utils/cn';
import type { PrdTask } from '@/shared/services/ai/types/ralph-types';

interface PrdImportExportProps {
  tasks: PrdTask[];
  jsonText: string;
  jsonError: string | null;
  onJsonTextChange: (text: string) => void;
  onJsonImport: () => void;
  onJsonExport: () => void;
  onDownloadJson: () => void;
  onCancel: () => void;
  className?: string;
}

export const PrdImportExport: React.FC<PrdImportExportProps> = ({
  jsonText,
  jsonError,
  onJsonTextChange,
  onJsonImport,
  onDownloadJson,
  onCancel,
  className,
}) => {
  return (
    <div className={cn('space-y-4', className)}>
      <div className="flex items-center justify-between">
        <h3 className="font-medium text-theme-text-primary">PRD JSON Editor</h3>
        <div className="flex items-center gap-2">
          <Button variant="ghost" size="sm" onClick={onCancel}>
            Cancel
          </Button>
          <Button variant="outline" size="sm" onClick={onDownloadJson}>
            <Download className="w-4 h-4 mr-1" />
            Download
          </Button>
          <Button variant="primary" size="sm" onClick={onJsonImport}>
            <Upload className="w-4 h-4 mr-1" />
            Import
          </Button>
        </div>
      </div>

      {jsonError && (
        <div className="flex items-center gap-2 p-3 rounded-lg bg-theme-status-error/10 text-theme-status-error">
          <AlertCircle className="w-4 h-4 flex-shrink-0" />
          <span className="text-sm">{jsonError}</span>
        </div>
      )}

      <div className="relative">
        <textarea
          className="w-full h-[500px] p-4 font-mono text-sm bg-theme-bg-secondary border border-theme-border-primary rounded-lg focus:outline-none focus:ring-2 focus:ring-theme-status-info resize-none"
          value={jsonText}
          onChange={(e) => {
            onJsonTextChange(e.target.value);
          }}
          placeholder='{"tasks": [{"key": "task_1", "description": "...", "dependencies": [], "acceptance_criteria": "..."}]}'
          spellCheck={false}
        />
        <div className="absolute bottom-2 right-2 text-xs text-theme-text-secondary">
          {jsonText.length} characters
        </div>
      </div>

      <p className="text-xs text-theme-text-secondary">
        Tip: You can paste a JSON array of tasks directly, or an object with a &quot;tasks&quot; property.
      </p>
    </div>
  );
};

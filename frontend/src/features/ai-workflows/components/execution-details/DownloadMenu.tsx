import React from 'react';
import { Download } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import type { DownloadMenuProps } from './types';

export const DownloadMenu: React.FC<DownloadMenuProps> = ({
  showMenu,
  onToggle,
  onDownload
}) => {
  return (
    <div className="relative">
      <Button
        variant="ghost"
        size="sm"
        onClick={(e) => {
          e.stopPropagation();
          onToggle();
        }}
        className="p-2"
        title="Download execution data"
      >
        <Download className="h-4 w-4" />
      </Button>
      {showMenu && (
        <div className="absolute top-full left-0 mt-1 bg-theme-surface border border-theme rounded-md shadow-lg z-50 min-w-[160px]">
          <div className="p-2">
            <p className="text-xs text-theme-muted mb-2 font-medium">Download Format:</p>
            <div className="space-y-1">
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  onDownload('json');
                }}
                className="w-full text-left px-2 py-1 text-xs rounded hover:bg-theme-hover text-theme-primary"
              >
                JSON (Full Data)
              </button>
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  onDownload('markdown');
                }}
                className="w-full text-left px-2 py-1 text-xs rounded hover:bg-theme-hover text-theme-primary"
              >
                Markdown Report
              </button>
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  onDownload('text');
                }}
                className="w-full text-left px-2 py-1 text-xs rounded hover:bg-theme-hover text-theme-primary"
              >
                Plain Text
              </button>
              <hr className="my-1 border-theme" />
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  onDownload('csv');
                }}
                className="w-full text-left px-2 py-1 text-xs rounded hover:bg-theme-hover text-theme-muted"
              >
                CSV (Metrics Only)
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

import React, { useState, useRef, useCallback } from 'react';
import { Upload } from 'lucide-react';

interface FileDropZoneProps {
  children: React.ReactNode;
  onFilesDropped: (files: File[]) => void;
  disabled?: boolean;
  acceptedTypes?: string[];
  maxSizeMb?: number;
}

const DEFAULT_ACCEPTED_TYPES = [
  'image/png', 'image/jpeg', 'image/gif', 'image/webp', 'image/svg+xml',
  'application/pdf',
  'text/plain', 'text/csv', 'text/markdown',
  'application/json',
  'application/zip',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
];

export const FileDropZone: React.FC<FileDropZoneProps> = ({
  children,
  onFilesDropped,
  disabled = false,
  acceptedTypes = DEFAULT_ACCEPTED_TYPES,
  maxSizeMb = 25,
}) => {
  const [isDragOver, setIsDragOver] = useState(false);
  const dragCounterRef = useRef(0);

  const handleDragEnter = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    if (disabled) return;
    dragCounterRef.current++;
    if (e.dataTransfer.items?.length) {
      setIsDragOver(true);
    }
  }, [disabled]);

  const handleDragLeave = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    dragCounterRef.current--;
    if (dragCounterRef.current === 0) {
      setIsDragOver(false);
    }
  }, []);

  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
  }, []);

  const filterFiles = useCallback((files: FileList | File[]): File[] => {
    const maxBytes = maxSizeMb * 1024 * 1024;
    return Array.from(files).filter(file => {
      if (file.size > maxBytes) return false;
      if (acceptedTypes.length > 0 && !acceptedTypes.includes(file.type)) return false;
      return true;
    });
  }, [acceptedTypes, maxSizeMb]);

  const handleDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragOver(false);
    dragCounterRef.current = 0;
    if (disabled) return;

    const valid = filterFiles(e.dataTransfer.files);
    if (valid.length > 0) {
      onFilesDropped(valid);
    }
  }, [disabled, filterFiles, onFilesDropped]);

  return (
    <div
      className="relative"
      onDragEnter={handleDragEnter}
      onDragLeave={handleDragLeave}
      onDragOver={handleDragOver}
      onDrop={handleDrop}
    >
      {children}
      {isDragOver && (
        <div className="absolute inset-0 z-50 flex items-center justify-center bg-theme-interactive-primary/10 border-2 border-dashed border-theme-interactive-primary rounded-lg pointer-events-none">
          <div className="flex flex-col items-center gap-2 p-4 bg-theme-surface rounded-lg shadow-lg">
            <Upload className="h-8 w-8 text-theme-interactive-primary" />
            <p className="text-sm font-medium text-theme-primary">Drop files here</p>
            <p className="text-xs text-theme-text-tertiary">Max {maxSizeMb}MB per file</p>
          </div>
        </div>
      )}
    </div>
  );
};

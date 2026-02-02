import React, { useState, useRef, useCallback, useEffect } from 'react';
import { Upload, X, File, CheckCircle, AlertCircle } from 'lucide-react';
import { filesApi, FileObject, UploadOptions } from '../services/filesApi';
import { useNotifications } from '@/shared/hooks/useNotifications';

interface FileUploadProps {
  onUploadComplete?: (file: FileObject) => void;
  category?: string;
  visibility?: string;
  accept?: string;
  maxSizeMB?: number;
  multiple?: boolean;
  className?: string;
  /** When true, automatically opens file picker on mount */
  triggerOnMount?: boolean;
}

interface UploadingFile {
  file: File;
  progress: number;
  status: 'pending' | 'uploading' | 'success' | 'error' | 'cancelled';
  error?: string;
  result?: FileObject;
  abortController?: AbortController;
}

export const FileUpload: React.FC<FileUploadProps> = ({
  onUploadComplete,
  category = 'user_upload',
  visibility = 'private',
  accept,
  maxSizeMB = 100,
  multiple = false,
  className = '',
  triggerOnMount = false
}) => {
  const [isDragging, setIsDragging] = useState(false);
  const [uploadingFiles, setUploadingFiles] = useState<UploadingFile[]>([]);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const { showNotification } = useNotifications();

  // Trigger file picker on mount if requested
  useEffect(() => {
    if (triggerOnMount && fileInputRef.current) {
      // Small delay to ensure the input is mounted and modal is fully rendered
      const timeoutId = setTimeout(() => {
        fileInputRef.current?.click();
      }, 100);
      return () => clearTimeout(timeoutId);
    }
  }, [triggerOnMount]);

  const validateFile = (file: File): string | null => {
    const maxSizeBytes = maxSizeMB * 1024 * 1024;
    if (file.size > maxSizeBytes) {
      return `File size exceeds maximum allowed (${maxSizeMB}MB)`;
    }

    // Validate file type if accept is specified
    if (accept) {
      const allowedTypes = accept.split(',').map(t => t.trim());
      const isAllowed = allowedTypes.some(allowed => {
        // Handle wildcards like image/*
        if (allowed.endsWith('/*')) {
          const category = allowed.slice(0, -2);
          return file.type.startsWith(category);
        }
        // Handle extensions like .pdf
        if (allowed.startsWith('.')) {
          return file.name.toLowerCase().endsWith(allowed.toLowerCase());
        }
        // Handle mime types like application/pdf
        return file.type === allowed;
      });

      if (!isAllowed) {
        return 'File type not allowed';
      }
    }

    return null;
  };

  const uploadFile = async (file: File): Promise<void> => {
    const abortController = new AbortController();
    const uploadingFile: UploadingFile = {
      file,
      progress: 0,
      status: 'uploading',
      abortController
    };

    setUploadingFiles(prev => [...prev, uploadingFile]);

    const options: UploadOptions = {
      category,
      visibility,
      onProgress: (progress) => {
        setUploadingFiles(prev =>
          prev.map(f =>
            f.file === file ? { ...f, progress: progress.percentage } : f
          )
        );
      }
    };

    try {
      const result = await filesApi.uploadFile(file, options);

      setUploadingFiles(prev =>
        prev.map(f =>
          f.file === file ? { ...f, status: 'success', progress: 100, result } : f
        )
      );

      showNotification(`${file.name} uploaded successfully`, 'success');
      onUploadComplete?.(result);

      // Remove from list after 2 seconds
      setTimeout(() => {
        setUploadingFiles(prev => prev.filter(f => f.file !== file));
      }, 2000);
    } catch {
      const err = error as { message?: string; response?: { data?: { error?: string } } };
      // Check if it was cancelled
      if (err.message === 'Upload cancelled') {
        setUploadingFiles(prev =>
          prev.map(f =>
            f.file === file ? { ...f, status: 'cancelled', error: 'Upload cancelled' } : f
          )
        );
        showNotification('Upload cancelled', 'info');
        return;
      }

      const errorMessage = err.response?.data?.error || err.message || 'Upload failed';

      setUploadingFiles(prev =>
        prev.map(f =>
          f.file === file ? { ...f, status: 'error', error: errorMessage } : f
        )
      );

      showNotification(`Failed to upload ${file.name}: ${errorMessage}`, 'error');
    }
  };

  const cancelUpload = (file: File) => {
    const uploadingFile = uploadingFiles.find(f => f.file === file);
    if (uploadingFile?.abortController) {
      uploadingFile.abortController.abort();
    }
    setUploadingFiles(prev =>
      prev.map(f =>
        f.file === file ? { ...f, status: 'cancelled', error: 'Upload cancelled' } : f
      )
    );
  };

  const handleFiles = useCallback(async (files: FileList | File[]) => {
    const fileArray = Array.from(files);

    for (const file of fileArray) {
      const validationError = validateFile(file);
      if (validationError) {
        showNotification(validationError, 'error');
        continue;
      }

      await uploadFile(file);
    }
  }, [category, visibility, maxSizeMB]);

  const handleDragOver = (e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(true);
  };

  const handleDragLeave = (e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(false);
  };

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(false);

    const files = e.dataTransfer.files;
    if (files.length > 0) {
      void handleFiles(files);
    }
  };

  const handleFileInput = (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = e.target.files;
    if (files && files.length > 0) {
      void handleFiles(files);
    }
  };

  const handleClick = () => {
    fileInputRef.current?.click();
  };

  const removeUploadingFile = (file: File) => {
    setUploadingFiles(prev => prev.filter(f => f.file !== file));
  };

  const formatFileSize = (bytes: number): string => {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  };

  return (
    <div className={className}>
      {/* Drop Zone */}
      <div
        onDragOver={handleDragOver}
        onDragLeave={handleDragLeave}
        onDrop={handleDrop}
        onClick={handleClick}
        className={`
          relative border-2 border-dashed rounded-lg p-8 text-center cursor-pointer
          transition-all duration-200
          ${isDragging
            ? 'border-theme-info bg-theme-info/10 dark:bg-theme-info/20'
            : 'border-theme bg-theme-surface hover:border-theme-info'
          }
        `}
      >
        <input
          ref={fileInputRef}
          type="file"
          onChange={handleFileInput}
          accept={accept}
          multiple={multiple}
          className="hidden"
          aria-label={multiple ? "Choose files" : "Select file"}
        />

        <Upload className="mx-auto h-12 w-12 text-theme-secondary mb-4" />

        <p className="text-theme-primary font-medium mb-2">
          {isDragging ? 'Drop files here' : 'Click to upload or drag and drop'}
        </p>

        <p className="text-theme-secondary text-sm">
          {accept || 'All file types'} up to {maxSizeMB}MB
        </p>
      </div>

      {/* Uploading Files List */}
      {uploadingFiles.length > 0 && (
        <div className="mt-4 space-y-2">
          {uploadingFiles.map((uploadingFile, index) => (
            <div
              key={`${uploadingFile.file.name}-${index}`}
              className="bg-theme-surface border border-theme rounded-lg p-4"
            >
              <div className="flex items-center gap-3">
                {/* File Icon */}
                <div className="flex-shrink-0">
                  {uploadingFile.status === 'success' && (
                    <CheckCircle className="h-5 w-5 text-theme-success" />
                  )}
                  {(uploadingFile.status === 'error' || uploadingFile.status === 'cancelled') && (
                    <AlertCircle className="h-5 w-5 text-theme-danger" />
                  )}
                  {(uploadingFile.status === 'uploading' || uploadingFile.status === 'pending') && (
                    <File className="h-5 w-5 text-theme-secondary" />
                  )}
                </div>

                {/* File Info */}
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium text-theme-primary truncate">
                    {uploadingFile.file.name}
                  </p>
                  <p className="text-xs text-theme-secondary">
                    {formatFileSize(uploadingFile.file.size)}
                  </p>

                  {/* Progress Bar */}
                  {uploadingFile.status === 'uploading' && (
                    <div
                      className="mt-2 w-full bg-theme-border dark:bg-theme-surface rounded-full h-1.5"
                      role="progressbar"
                      aria-valuenow={uploadingFile.progress}
                      aria-valuemin={0}
                      aria-valuemax={100}
                    >
                      <div
                        className="bg-theme-info h-1.5 rounded-full transition-all duration-300"
                        style={{ width: `${uploadingFile.progress}%` }}
                      />
                    </div>
                  )}

                  {/* Error/Cancelled Message */}
                  {(uploadingFile.status === 'error' || uploadingFile.status === 'cancelled') && uploadingFile.error && (
                    <p className="mt-1 text-xs text-theme-danger">{uploadingFile.error}</p>
                  )}
                </div>

                {/* Remove Button - for completed/error/cancelled states */}
                {(uploadingFile.status === 'error' || uploadingFile.status === 'success' || uploadingFile.status === 'cancelled') && (
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      removeUploadingFile(uploadingFile.file);
                    }}
                    className="flex-shrink-0 text-theme-secondary hover:text-theme-primary"
                  >
                    <X className="h-4 w-4" />
                  </button>
                )}

                {/* Cancel Button - for uploading state */}
                {uploadingFile.status === 'uploading' && (
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      cancelUpload(uploadingFile.file);
                    }}
                    className="flex-shrink-0 px-2 py-1 text-xs text-theme-danger hover:text-theme-danger/80"
                    aria-label="Cancel upload"
                  >
                    Cancel
                  </button>
                )}

                {/* Progress Percentage */}
                {uploadingFile.status === 'uploading' && (
                  <span className="flex-shrink-0 text-sm font-medium text-theme-secondary">
                    {uploadingFile.progress}%
                  </span>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};


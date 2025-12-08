import React from 'react';
import {
  DocumentIcon,
  ArrowDownTrayIcon,
  ExclamationCircleIcon,
} from '@heroicons/react/24/outline';
import { FileObject } from '@/features/files/services/filesApi';

interface FilePreviewFallbackProps {
  file: FileObject;
  error?: string;
  onDownload: () => void;
}

// Get icon for file type
const getFileIcon = (file: FileObject): string => {
  const fileType = file.file_type?.toLowerCase() || '';
  const contentType = file.content_type?.toLowerCase() || '';
  const extension = file.filename?.split('.').pop()?.toLowerCase() || '';

  // Document types
  if (
    contentType.includes('pdf') ||
    extension === 'pdf'
  ) {
    return '📄';
  }
  if (
    contentType.includes('word') ||
    ['doc', 'docx'].includes(extension)
  ) {
    return '📝';
  }
  if (
    contentType.includes('excel') ||
    contentType.includes('spreadsheet') ||
    ['xls', 'xlsx', 'csv'].includes(extension)
  ) {
    return '📊';
  }
  if (
    contentType.includes('powerpoint') ||
    contentType.includes('presentation') ||
    ['ppt', 'pptx'].includes(extension)
  ) {
    return '📽️';
  }

  // Archive types
  if (
    contentType.includes('zip') ||
    contentType.includes('rar') ||
    contentType.includes('tar') ||
    contentType.includes('gzip') ||
    ['zip', 'rar', '7z', 'tar', 'gz', 'bz2'].includes(extension)
  ) {
    return '📦';
  }

  // Media types
  if (fileType === 'image' || contentType.startsWith('image/')) {
    return '🖼️';
  }
  if (fileType === 'video' || contentType.startsWith('video/')) {
    return '🎬';
  }
  if (fileType === 'audio' || contentType.startsWith('audio/')) {
    return '🎵';
  }

  // Code types
  if (
    fileType === 'code' ||
    contentType.includes('javascript') ||
    contentType.includes('json') ||
    contentType.includes('xml') ||
    ['js', 'ts', 'tsx', 'jsx', 'py', 'rb', 'go', 'rs', 'java', 'c', 'cpp', 'h'].includes(
      extension
    )
  ) {
    return '💻';
  }

  // Text types
  if (contentType.startsWith('text/') || ['txt', 'md', 'log'].includes(extension)) {
    return '📃';
  }

  // Default
  return '📁';
};

// Format file size
const formatFileSize = (bytes: number): string => {
  if (bytes === 0) return '0 Bytes';
  const k = 1024;
  const sizes = ['Bytes', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
};

export const FilePreviewFallback: React.FC<FilePreviewFallbackProps> = ({
  file,
  error,
  onDownload,
}) => {
  const fileIcon = getFileIcon(file);

  return (
    <div className="flex flex-col items-center justify-center h-full p-8 text-center">
      {/* File icon */}
      <div className="text-8xl mb-6">{fileIcon}</div>

      {/* File name */}
      <h3 className="text-xl font-medium text-white mb-2 max-w-md truncate">
        {file.filename}
      </h3>

      {/* File metadata */}
      <div className="flex items-center space-x-4 text-sm text-white/60 mb-6">
        <span>{file.file_type || 'Unknown type'}</span>
        <span>•</span>
        <span>{formatFileSize(file.file_size)}</span>
        {file.content_type && (
          <>
            <span>•</span>
            <span>{file.content_type}</span>
          </>
        )}
      </div>

      {/* Error message */}
      {error && (
        <div className="flex items-center space-x-2 px-4 py-3 rounded-lg bg-theme-danger/20 text-theme-danger mb-6">
          <ExclamationCircleIcon className="w-5 h-5 flex-shrink-0" />
          <span className="text-sm">{error}</span>
        </div>
      )}

      {/* No preview message */}
      {!error && (
        <div className="flex items-center space-x-2 px-4 py-3 rounded-lg bg-white/10 text-white/70 mb-6">
          <DocumentIcon className="w-5 h-5 flex-shrink-0" />
          <span className="text-sm">Preview not available for this file type</span>
        </div>
      )}

      {/* Download button */}
      <button
        onClick={onDownload}
        className="flex items-center gap-2 px-6 py-3 bg-theme-primary text-white rounded-lg hover:bg-theme-primary-hover transition-colors font-medium"
      >
        <ArrowDownTrayIcon className="w-5 h-5" />
        Download File
      </button>

      {/* Additional file info */}
      {file.created_at && (
        <p className="text-sm text-white/40 mt-6">
          Uploaded: {new Date(file.created_at).toLocaleDateString()}
        </p>
      )}
    </div>
  );
};

export default FilePreviewFallback;

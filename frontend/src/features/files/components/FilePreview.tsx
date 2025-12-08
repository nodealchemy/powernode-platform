import React, { useState, useEffect } from 'react';
import {
  XMarkIcon,
  ArrowDownTrayIcon,
  ArrowsPointingOutIcon,
  ArrowsPointingInIcon,
  ChevronLeftIcon,
  ChevronRightIcon,
} from '@heroicons/react/24/outline';
import { FileObject, filesApi } from '@/features/files/services/filesApi';
import { FilePreviewImage } from './FilePreviewImage';
import { FilePreviewPdf } from './FilePreviewPdf';
import { FilePreviewVideo } from './FilePreviewVideo';
import { FilePreviewAudio } from './FilePreviewAudio';
import { FilePreviewCode } from './FilePreviewCode';
import { FilePreviewFallback } from './FilePreviewFallback';

interface FilePreviewProps {
  file: FileObject;
  files?: FileObject[];
  currentIndex?: number;
  onClose: () => void;
  onNavigate?: (file: FileObject, index: number) => void;
}

export const FilePreview: React.FC<FilePreviewProps> = ({
  file,
  files = [],
  currentIndex = 0,
  onClose,
  onNavigate,
}) => {
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [loading, setLoading] = useState(true);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const hasNavigation = files.length > 1;
  const canGoPrev = currentIndex > 0;
  const canGoNext = currentIndex < files.length - 1;

  // Load preview URL
  useEffect(() => {
    const loadPreviewUrl = async () => {
      setLoading(true);
      setError(null);
      try {
        if (file.urls?.view) {
          setPreviewUrl(file.urls.view);
        } else if (file.urls?.signed) {
          setPreviewUrl(file.urls.signed);
        } else {
          // Fallback to download URL
          setPreviewUrl(file.urls?.download || null);
        }
      } catch {
        setError('Failed to load preview');
      } finally {
        setLoading(false);
      }
    };

    loadPreviewUrl();
  }, [file]);

  // Handle keyboard navigation
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        onClose();
      } else if (e.key === 'ArrowLeft' && canGoPrev && onNavigate) {
        onNavigate(files[currentIndex - 1], currentIndex - 1);
      } else if (e.key === 'ArrowRight' && canGoNext && onNavigate) {
        onNavigate(files[currentIndex + 1], currentIndex + 1);
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [onClose, canGoPrev, canGoNext, files, currentIndex, onNavigate]);

  // Handle fullscreen
  const toggleFullscreen = () => {
    if (!document.fullscreenElement) {
      document.documentElement.requestFullscreen();
      setIsFullscreen(true);
    } else {
      document.exitFullscreen();
      setIsFullscreen(false);
    }
  };

  // Handle download
  const handleDownload = async () => {
    try {
      await filesApi.downloadFile(file.id, file.filename);
    } catch {
      // Silent fail - download usually opens in new tab
    }
  };

  // Determine preview component based on file type
  const renderPreview = () => {
    if (loading) {
      return (
        <div className="flex items-center justify-center h-full">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-theme-primary" />
        </div>
      );
    }

    if (error) {
      return (
        <FilePreviewFallback
          file={file}
          error={error}
          onDownload={handleDownload}
        />
      );
    }

    const contentType = file.content_type?.toLowerCase() || '';
    const fileType = file.file_type?.toLowerCase() || '';

    // Image files
    if (fileType === 'image' || contentType.startsWith('image/')) {
      return <FilePreviewImage file={file} previewUrl={previewUrl} />;
    }

    // PDF files
    if (contentType === 'application/pdf' || file.filename?.endsWith('.pdf')) {
      return <FilePreviewPdf file={file} previewUrl={previewUrl} />;
    }

    // Video files
    if (fileType === 'video' || contentType.startsWith('video/')) {
      return <FilePreviewVideo file={file} previewUrl={previewUrl} />;
    }

    // Audio files
    if (fileType === 'audio' || contentType.startsWith('audio/')) {
      return <FilePreviewAudio file={file} previewUrl={previewUrl} />;
    }

    // Code files
    if (
      fileType === 'code' ||
      contentType.includes('javascript') ||
      contentType.includes('json') ||
      contentType.includes('xml') ||
      contentType.includes('text/') ||
      /\.(js|ts|tsx|jsx|py|rb|go|rs|java|c|cpp|h|hpp|css|scss|less|html|md|yml|yaml|toml|json|xml|sh|bash)$/i.test(
        file.filename || ''
      )
    ) {
      return <FilePreviewCode file={file} previewUrl={previewUrl} />;
    }

    // Fallback for unsupported types
    return (
      <FilePreviewFallback
        file={file}
        error="Preview not available for this file type"
        onDownload={handleDownload}
      />
    );
  };

  return (
    <div className="fixed inset-0 z-50 bg-black/90 flex flex-col">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 bg-black/50">
        <div className="flex items-center space-x-4">
          <button
            onClick={onClose}
            className="p-2 rounded-lg text-white/70 hover:text-white hover:bg-white/10 transition-colors"
            title="Close (Esc)"
          >
            <XMarkIcon className="w-6 h-6" />
          </button>
          <div>
            <h2 className="text-white font-medium truncate max-w-md">{file.filename}</h2>
            <div className="flex items-center space-x-2 text-sm text-white/60">
              <span>{file.file_type}</span>
              <span>•</span>
              <span>
                {(file.file_size / 1024).toFixed(1)} KB
              </span>
              {hasNavigation && (
                <>
                  <span>•</span>
                  <span>
                    {currentIndex + 1} of {files.length}
                  </span>
                </>
              )}
            </div>
          </div>
        </div>

        <div className="flex items-center space-x-2">
          <button
            onClick={handleDownload}
            className="p-2 rounded-lg text-white/70 hover:text-white hover:bg-white/10 transition-colors"
            title="Download"
          >
            <ArrowDownTrayIcon className="w-6 h-6" />
          </button>
          <button
            onClick={toggleFullscreen}
            className="p-2 rounded-lg text-white/70 hover:text-white hover:bg-white/10 transition-colors"
            title={isFullscreen ? 'Exit Fullscreen' : 'Fullscreen'}
          >
            {isFullscreen ? (
              <ArrowsPointingInIcon className="w-6 h-6" />
            ) : (
              <ArrowsPointingOutIcon className="w-6 h-6" />
            )}
          </button>
        </div>
      </div>

      {/* Preview Content */}
      <div className="flex-1 relative flex items-center justify-center overflow-hidden">
        {/* Navigation Buttons */}
        {hasNavigation && canGoPrev && onNavigate && (
          <button
            onClick={() => onNavigate(files[currentIndex - 1], currentIndex - 1)}
            className="absolute left-4 z-10 p-3 rounded-full bg-black/50 text-white/70 hover:text-white hover:bg-black/70 transition-colors"
            title="Previous (Left Arrow)"
          >
            <ChevronLeftIcon className="w-6 h-6" />
          </button>
        )}

        {hasNavigation && canGoNext && onNavigate && (
          <button
            onClick={() => onNavigate(files[currentIndex + 1], currentIndex + 1)}
            className="absolute right-4 z-10 p-3 rounded-full bg-black/50 text-white/70 hover:text-white hover:bg-black/70 transition-colors"
            title="Next (Right Arrow)"
          >
            <ChevronRightIcon className="w-6 h-6" />
          </button>
        )}

        {/* Preview */}
        <div className="w-full h-full p-4 flex items-center justify-center">
          {renderPreview()}
        </div>
      </div>
    </div>
  );
};

export default FilePreview;

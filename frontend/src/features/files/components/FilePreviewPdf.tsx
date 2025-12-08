import React, { useState } from 'react';
import {
  ChevronLeftIcon,
  ChevronRightIcon,
  MagnifyingGlassPlusIcon,
  MagnifyingGlassMinusIcon,
  ArrowDownTrayIcon,
} from '@heroicons/react/24/outline';
import { FileObject, filesApi } from '@/features/files/services/filesApi';

interface FilePreviewPdfProps {
  file: FileObject;
  previewUrl: string | null;
}

export const FilePreviewPdf: React.FC<FilePreviewPdfProps> = ({
  file,
  previewUrl,
}) => {
  const [currentPage, setCurrentPage] = useState(1);
  const [totalPages] = useState<number | null>(null);
  const [zoom, setZoom] = useState(100);
  const [loadError, setLoadError] = useState(false);

  const handleZoomIn = () => setZoom((prev) => Math.min(prev + 25, 200));
  const handleZoomOut = () => setZoom((prev) => Math.max(prev - 25, 50));
  const handlePrevPage = () => setCurrentPage((prev) => Math.max(prev - 1, 1));
  const handleNextPage = () => {
    if (totalPages) {
      setCurrentPage((prev) => Math.min(prev + 1, totalPages));
    }
  };

  const handleDownload = async () => {
    try {
      await filesApi.downloadFile(file.id, file.filename);
    } catch {
      // Silent fail - download usually opens in new tab
    }
  };

  if (!previewUrl || loadError) {
    return (
      <div className="flex flex-col items-center justify-center h-full text-theme-secondary">
        <div className="text-6xl mb-4">📄</div>
        <p className="text-lg mb-2">PDF Preview Not Available</p>
        <p className="text-sm text-theme-tertiary mb-4">{file.filename}</p>
        <button
          onClick={handleDownload}
          className="flex items-center gap-2 px-4 py-2 bg-theme-primary text-white rounded-lg hover:bg-theme-primary-hover transition-colors"
        >
          <ArrowDownTrayIcon className="w-5 h-5" />
          Download PDF
        </button>
      </div>
    );
  }

  return (
    <div className="relative w-full h-full flex flex-col">
      {/* Toolbar */}
      <div className="absolute top-4 left-1/2 transform -translate-x-1/2 z-10 flex items-center space-x-2 bg-black/50 rounded-lg px-4 py-2">
        <button
          onClick={handlePrevPage}
          disabled={currentPage <= 1}
          className="p-2 rounded-lg text-white/70 hover:text-white hover:bg-white/10 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          title="Previous Page"
        >
          <ChevronLeftIcon className="w-5 h-5" />
        </button>
        <span className="text-white/80 text-sm min-w-[80px] text-center">
          Page {currentPage}
          {totalPages && ` of ${totalPages}`}
        </span>
        <button
          onClick={handleNextPage}
          disabled={totalPages !== null && currentPage >= totalPages}
          className="p-2 rounded-lg text-white/70 hover:text-white hover:bg-white/10 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          title="Next Page"
        >
          <ChevronRightIcon className="w-5 h-5" />
        </button>
        <div className="w-px h-5 bg-white/30" />
        <button
          onClick={handleZoomOut}
          disabled={zoom <= 50}
          className="p-2 rounded-lg text-white/70 hover:text-white hover:bg-white/10 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          title="Zoom Out"
        >
          <MagnifyingGlassMinusIcon className="w-5 h-5" />
        </button>
        <span className="text-white/80 text-sm min-w-[50px] text-center">
          {zoom}%
        </span>
        <button
          onClick={handleZoomIn}
          disabled={zoom >= 200}
          className="p-2 rounded-lg text-white/70 hover:text-white hover:bg-white/10 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          title="Zoom In"
        >
          <MagnifyingGlassPlusIcon className="w-5 h-5" />
        </button>
        <div className="w-px h-5 bg-white/30" />
        <button
          onClick={handleDownload}
          className="p-2 rounded-lg text-white/70 hover:text-white hover:bg-white/10 transition-colors"
          title="Download"
        >
          <ArrowDownTrayIcon className="w-5 h-5" />
        </button>
      </div>

      {/* PDF Container */}
      <div className="flex-1 overflow-auto flex items-center justify-center bg-theme-background">
        <iframe
          src={`${previewUrl}#page=${currentPage}&zoom=${zoom}`}
          className="w-full h-full border-0"
          title={file.filename}
          onError={() => setLoadError(true)}
        />
      </div>
    </div>
  );
};

export default FilePreviewPdf;

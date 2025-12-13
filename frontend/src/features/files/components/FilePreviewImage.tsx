import React, { useState } from 'react';
import {
  MagnifyingGlassPlusIcon,
  MagnifyingGlassMinusIcon,
  ArrowPathIcon,
} from '@heroicons/react/24/outline';
import { FileObject } from '@/features/files/services/filesApi';

interface FilePreviewImageProps {
  file: FileObject;
  previewUrl: string | null;
}

export const FilePreviewImage: React.FC<FilePreviewImageProps> = ({
  file,
  previewUrl,
}) => {
  const [zoom, setZoom] = useState(1);
  const [rotation, setRotation] = useState(0);
  const [imageError, setImageError] = useState(false);
  const [imageLoaded, setImageLoaded] = useState(false);

  const handleZoomIn = () => setZoom((prev) => Math.min(prev + 0.25, 3));
  const handleZoomOut = () => setZoom((prev) => Math.max(prev - 0.25, 0.25));
  const handleRotate = () => setRotation((prev) => (prev + 90) % 360);
  const handleReset = () => {
    setZoom(1);
    setRotation(0);
  };

  if (!previewUrl || imageError) {
    return (
      <div className="flex flex-col items-center justify-center h-full text-theme-secondary">
        <div className="text-6xl mb-4">🖼️</div>
        <p className="text-lg">Unable to load image</p>
        <p className="text-sm text-theme-tertiary mt-2">{file.filename}</p>
      </div>
    );
  }

  return (
    <div className="relative w-full h-full flex flex-col">
      {/* Toolbar */}
      <div className="absolute top-4 left-1/2 transform -translate-x-1/2 z-10 flex items-center space-x-2 bg-black/50 rounded-lg px-4 py-2">
        <button
          onClick={handleZoomOut}
          disabled={zoom <= 0.25}
          className="p-2 rounded-lg text-white/70 hover:text-white hover:bg-white/10 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          title="Zoom Out"
        >
          <MagnifyingGlassMinusIcon className="w-5 h-5" />
        </button>
        <span className="text-white/80 text-sm min-w-[60px] text-center">
          {Math.round(zoom * 100)}%
        </span>
        <button
          onClick={handleZoomIn}
          disabled={zoom >= 3}
          className="p-2 rounded-lg text-white/70 hover:text-white hover:bg-white/10 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          title="Zoom In"
        >
          <MagnifyingGlassPlusIcon className="w-5 h-5" />
        </button>
        <div className="w-px h-5 bg-white/30" />
        <button
          onClick={handleRotate}
          className="p-2 rounded-lg text-white/70 hover:text-white hover:bg-white/10 transition-colors"
          title="Rotate"
        >
          <ArrowPathIcon className="w-5 h-5" />
        </button>
        <button
          onClick={handleReset}
          className="px-3 py-1 rounded-lg text-white/70 hover:text-white hover:bg-white/10 transition-colors text-sm"
          title="Reset"
        >
          Reset
        </button>
      </div>

      {/* Image Container */}
      <div className="flex-1 overflow-auto flex items-center justify-center">
        {!imageLoaded && (
          <div className="absolute inset-0 flex items-center justify-center">
            <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-theme-primary" />
          </div>
        )}
        <img
          src={previewUrl}
          alt={file.filename}
          className="max-w-full max-h-full object-contain transition-transform duration-200"
          style={{
            transform: `scale(${zoom}) rotate(${rotation}deg)`,
            opacity: imageLoaded ? 1 : 0,
          }}
          onLoad={() => setImageLoaded(true)}
          onError={() => setImageError(true)}
          draggable={false}
        />
      </div>
    </div>
  );
};

export default FilePreviewImage;

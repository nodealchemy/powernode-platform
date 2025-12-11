import React, { useState, useEffect, useCallback } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/shared/components/ui/Tabs';
import { FileUpload } from '@/features/files/components/FileUpload';
import { filesApi, FileObject } from '@/features/files/services/filesApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import {
  PhotoIcon,
  MagnifyingGlassIcon,
  CheckIcon
} from '@heroicons/react/24/outline';

// Component to display image with authenticated API fetch
const AuthenticatedImage: React.FC<{
  fileId: string;
  alt: string;
  className?: string;
}> = ({ fileId, alt, className }) => {
  const [blobUrl, setBlobUrl] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);

  useEffect(() => {
    let isMounted = true;
    let url: string | null = null;

    const loadImage = async () => {
      try {
        setLoading(true);
        setError(false);
        url = await filesApi.getFileBlobUrl(fileId);
        if (isMounted) {
          setBlobUrl(url);
        }
      } catch {
        if (isMounted) {
          setError(true);
        }
      } finally {
        if (isMounted) {
          setLoading(false);
        }
      }
    };

    loadImage();

    return () => {
      isMounted = false;
      // Revoke blob URL on cleanup
      if (url) {
        window.URL.revokeObjectURL(url);
      }
    };
  }, [fileId]);

  if (loading) {
    return (
      <div className={`${className} flex items-center justify-center bg-theme-surface`}>
        <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-theme-interactive-primary" />
      </div>
    );
  }

  if (error || !blobUrl) {
    return (
      <div className={`${className} flex items-center justify-center bg-theme-surface text-theme-tertiary`}>
        <PhotoIcon className="h-8 w-8" />
      </div>
    );
  }

  return <img src={blobUrl} alt={alt} className={className} />;
};

interface ImageGalleryModalProps {
  isOpen: boolean;
  onClose: () => void;
  onImageSelect: (imageUrl: string, altText: string) => void;
  pageId?: string | null;
}

export const ImageGalleryModal: React.FC<ImageGalleryModalProps> = ({
  isOpen,
  onClose,
  onImageSelect,
  pageId: _pageId // Reserved for future page-specific image filtering
}) => {
  const [activeTab, setActiveTab] = useState<string>('browse');
  const [images, setImages] = useState<FileObject[]>([]);
  const [loading, setLoading] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedImage, setSelectedImage] = useState<FileObject | null>(null);
  const { showNotification } = useNotifications();

  // Load existing images when browse tab is active
  const loadImages = useCallback(async (search?: string) => {
    try {
      setLoading(true);
      const response = await filesApi.getAvailableImages({
        search: search || undefined,
        per_page: 50
      });
      setImages(response.files);
    } catch {
      // Error handled silently - user can retry
    } finally {
      setLoading(false);
    }
  }, []);

  // Reset state when modal closes
  useEffect(() => {
    if (!isOpen) {
      setSelectedImage(null);
      setSearchQuery('');
      setActiveTab('browse');
    }
  }, [isOpen]);

  // Handle file upload completion
  const handleUploadComplete = async (file: FileObject) => {
    try {
      // Fetch the file to get the URL
      const fullFile = await filesApi.getFile(file.id);
      const imageUrl = fullFile.urls?.view || fullFile.urls?.signed || '';

      if (imageUrl) {
        onImageSelect(imageUrl, fullFile.filename);
        onClose();
      } else {
        showNotification('Image uploaded but URL not available', 'warning');
      }
    } catch {
      showNotification('Failed to get image URL', 'error');
    }
  };

  // Handle image selection from gallery
  const handleImageClick = (image: FileObject) => {
    setSelectedImage(image);
  };

  // Confirm selection and insert image
  const handleInsertImage = async () => {
    if (!selectedImage) return;

    try {
      const fullFile = await filesApi.getFile(selectedImage.id);
      const imageUrl = fullFile.urls?.view || fullFile.urls?.signed || '';

      if (imageUrl) {
        onImageSelect(imageUrl, selectedImage.filename);
        onClose();
      } else {
        showNotification('Could not get image URL', 'error');
      }
    } catch {
      showNotification('Failed to get image details', 'error');
    }
  };

  // Load images when browse tab becomes active or search changes
  useEffect(() => {
    if (activeTab === 'browse' && isOpen) {
      const timeoutId = setTimeout(() => {
        loadImages(searchQuery);
      }, searchQuery ? 300 : 0); // Immediate load initially, debounced for search
      return () => clearTimeout(timeoutId);
    }
  }, [searchQuery, activeTab, isOpen, loadImages]);

  const formatFileSize = (bytes: number): string => {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Insert Image"
      subtitle="Upload a new image or select from your library"
      icon={<PhotoIcon className="w-6 h-6" />}
      maxWidth="4xl"
      footer={
        activeTab === 'browse' && selectedImage ? (
          <div className="flex gap-3">
            <button
              onClick={onClose}
              className="btn-theme btn-theme-secondary"
            >
              Cancel
            </button>
            <button
              onClick={handleInsertImage}
              className="btn-theme btn-theme-primary"
            >
              Insert Image
            </button>
          </div>
        ) : undefined
      }
    >
      <Tabs value={activeTab} onValueChange={setActiveTab}>
        <TabsList className="mb-4 -mx-6 px-6">
          <TabsTrigger value="browse">Browse Library</TabsTrigger>
          <TabsTrigger value="upload">Upload New</TabsTrigger>
        </TabsList>

        <TabsContent value="browse">
          <div className="space-y-4">
            {/* Search Bar */}
            <div className="form-field-icon relative">
              <MagnifyingGlassIcon className="form-icon absolute left-3 top-1/2 transform -translate-y-1/2 h-5 w-5 text-theme-secondary" />
              <input
                type="text"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder="Search images..."
                className="w-full pr-4 py-2 input-theme"
              />
            </div>

            {/* Image Grid */}
            {loading ? (
              <div className="flex items-center justify-center py-12">
                <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-interactive-primary" />
              </div>
            ) : images.length === 0 ? (
              <div className="text-center py-12 text-theme-secondary">
                <PhotoIcon className="h-12 w-12 mx-auto mb-4 opacity-50" />
                <p>No images found</p>
                <p className="text-sm mt-1">Upload an image to get started</p>
              </div>
            ) : (
              <div className="grid grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-3 max-h-96 overflow-y-auto">
                {images.map((image) => (
                  <button
                    key={image.id}
                    onClick={() => handleImageClick(image)}
                    className={`
                      relative group aspect-square rounded-lg overflow-hidden border-2 transition-all
                      ${selectedImage?.id === image.id
                        ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/50'
                        : 'border-theme hover:border-theme-interactive-primary/50'
                      }
                    `}
                    type="button"
                  >
                    <AuthenticatedImage
                      fileId={image.id}
                      alt={image.filename}
                      className="w-full h-full object-cover"
                    />

                    {/* Selection indicator */}
                    {selectedImage?.id === image.id && (
                      <div className="absolute top-2 right-2 bg-theme-interactive-primary text-white rounded-full p-1">
                        <CheckIcon className="h-4 w-4" />
                      </div>
                    )}

                    {/* Hover overlay with file info */}
                    <div className="absolute inset-0 bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity flex flex-col justify-end p-2">
                      <p className="text-white text-xs truncate">{image.filename}</p>
                      <p className="text-white/70 text-xs">{formatFileSize(image.file_size)}</p>
                    </div>
                  </button>
                ))}
              </div>
            )}
          </div>
        </TabsContent>

        <TabsContent value="upload">
          <div className="space-y-4">
            <p className="text-sm text-theme-secondary">
              Drag and drop an image or click to upload. The image will be inserted immediately after upload.
            </p>
            <FileUpload
              onUploadComplete={handleUploadComplete}
              category="page_content"
              visibility="public"
              accept="image/*"
              maxSizeMB={10}
              multiple={false}
            />
            <div className="text-xs text-theme-tertiary">
              Supported formats: PNG, JPG, JPEG, GIF, WebP. Maximum size: 10MB.
            </div>
          </div>
        </TabsContent>
      </Tabs>
    </Modal>
  );
};

export default ImageGalleryModal;

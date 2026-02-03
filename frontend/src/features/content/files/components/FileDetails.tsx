import React, { useState } from 'react';
import { Download, Share2, Trash2, Tag, Copy, Check } from 'lucide-react';
import Modal from '@/shared/components/ui/Modal';
import { filesApi, FileObject } from '../services/filesApi';
import { useNotifications } from '@/shared/hooks/useNotifications';

interface FileDetailsProps {
  file: FileObject;
  isOpen: boolean;
  onClose: () => void;
  onFileUpdated?: () => void;
  initialTab?: 'details' | 'share' | 'tags';
}

export const FileDetails: React.FC<FileDetailsProps> = ({
  file,
  isOpen,
  onClose,
  onFileUpdated,
  initialTab = 'details'
}) => {
  const [activeTab, setActiveTab] = useState<'details' | 'share' | 'tags'>(initialTab);
  const [shareUrl, setShareUrl] = useState('');
  const [copiedUrl, setCopiedUrl] = useState(false);
  const { showNotification } = useNotifications();

  // Reset tab when modal opens with new file or initialTab changes
  React.useEffect(() => {
    if (isOpen) {
      setActiveTab(initialTab);
    }
  }, [isOpen, initialTab]);

  const formatFileSize = (bytes: number): string => {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
  };

  const formatDate = (dateString: string): string => {
    return new Date(dateString).toLocaleString();
  };

  const handleDownload = async (): Promise<void> => {
    try {
      await filesApi.downloadFile(file.id, file.filename);
      showNotification('Download started', 'success');
    } catch (_error) {
      showNotification('Download failed', 'error');
    }
  };

  const handleCreateShare = async (): Promise<void> => {
    try {
      const result = await filesApi.createShare(file.id, {
        expires_at: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
        share_type: 'public_link',
        access_level: 'download'
      });

      setShareUrl(result.url);
      showNotification('Share link created', 'success');
    } catch (_error) {
      showNotification('Failed to create share link', 'error');
    }
  };

  const handleCopyUrl = async (): Promise<void> => {
    try {
      await navigator.clipboard.writeText(shareUrl);
      setCopiedUrl(true);
      showNotification('URL copied to clipboard', 'success');
      setTimeout(() => setCopiedUrl(false), 2000);
    } catch (_error) {
      showNotification('Failed to copy URL', 'error');
    }
  };

  const handleDelete = async (): Promise<void> => {
    if (!confirm(`Delete ${file.filename}?`)) return;

    try {
      await filesApi.deleteFile(file.id);
      showNotification('File deleted successfully', 'success');
      onFileUpdated?.();
      onClose();
    } catch (_error) {
      showNotification('Failed to delete file', 'error');
    }
  };

  return (
    <Modal isOpen={isOpen} onClose={onClose} title={file.filename}>
      <div className="space-y-6">
        {/* Tabs */}
        <div className="flex gap-4 border-b border-theme">
          <button
            onClick={() => setActiveTab('details')}
            className={`pb-2 px-1 text-sm font-medium transition-colors ${
              activeTab === 'details'
                ? 'text-theme-info border-b-2 border-theme-info'
                : 'text-theme-secondary hover:text-theme-primary'
            }`}
          >
            Details
          </button>
          <button
            onClick={() => setActiveTab('share')}
            className={`pb-2 px-1 text-sm font-medium transition-colors ${
              activeTab === 'share'
                ? 'text-theme-info border-b-2 border-theme-info'
                : 'text-theme-secondary hover:text-theme-primary'
            }`}
          >
            Share
          </button>
          <button
            onClick={() => setActiveTab('tags')}
            className={`pb-2 px-1 text-sm font-medium transition-colors ${
              activeTab === 'tags'
                ? 'text-theme-info border-b-2 border-theme-info'
                : 'text-theme-secondary hover:text-theme-primary'
            }`}
          >
            Tags
          </button>
        </div>

        {/* Details Tab */}
        {activeTab === 'details' && (
          <div className="space-y-4">
            <div className="grid grid-cols-2 gap-4 text-sm">
              <div>
                <p className="text-theme-secondary">File Size</p>
                <p className="text-theme-primary font-medium">{formatFileSize(file.file_size)}</p>
              </div>

              <div>
                <p className="text-theme-secondary">Type</p>
                <p className="text-theme-primary font-medium">{file.content_type}</p>
              </div>

              <div>
                <p className="text-theme-secondary">Category</p>
                <p className="text-theme-primary font-medium">{file.category.replace('_', ' ')}</p>
              </div>

              <div>
                <p className="text-theme-secondary">Visibility</p>
                <p className="text-theme-primary font-medium capitalize">{file.visibility}</p>
              </div>

              <div>
                <p className="text-theme-secondary">Uploaded</p>
                <p className="text-theme-primary font-medium">{formatDate(file.created_at)}</p>
              </div>

              {file.uploaded_by && (
                <div>
                  <p className="text-theme-secondary">Uploaded By</p>
                  <p className="text-theme-primary font-medium">{file.uploaded_by.name}</p>
                </div>
              )}

              <div>
                <p className="text-theme-secondary">Version</p>
                <p className="text-theme-primary font-medium">v{file.version}</p>
              </div>

              <div>
                <p className="text-theme-secondary">Status</p>
                <p className="text-theme-primary font-medium capitalize">{file.processing_status}</p>
              </div>
            </div>

            {/* Action Buttons */}
            <div className="flex gap-2 pt-4">
              <button
                onClick={handleDownload}
                className="flex-1 flex items-center justify-center gap-2 px-4 py-2 bg-theme-info text-white rounded-lg hover:opacity-90 transition-colors"
              >
                <Download className="h-4 w-4" />
                Download
              </button>

              <button
                onClick={handleDelete}
                className="flex items-center justify-center gap-2 px-4 py-2 bg-theme-danger text-white rounded-lg hover:opacity-90 transition-colors"
              >
                <Trash2 className="h-4 w-4" />
                Delete
              </button>
            </div>
          </div>
        )}

        {/* Share Tab */}
        {activeTab === 'share' && (
          <div className="space-y-4">
            {!shareUrl ? (
              <div className="text-center py-8">
                <Share2 className="h-12 w-12 mx-auto mb-4 text-theme-secondary" />
                <p className="text-theme-secondary mb-4">
                  Create a shareable link for this file
                </p>
                <button
                  onClick={handleCreateShare}
                  className="px-6 py-2 bg-theme-info text-white rounded-lg hover:opacity-90 transition-colors"
                >
                  Create Share Link
                </button>
              </div>
            ) : (
              <div className="space-y-4">
                <p className="text-sm text-theme-secondary">
                  Share this link with others. It expires in 7 days.
                </p>

                <div className="flex gap-2">
                  <input
                    type="text"
                    value={shareUrl}
                    readOnly
                    className="flex-1 px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary"
                  />
                  <button
                    onClick={handleCopyUrl}
                    className="px-4 py-2 bg-theme-info text-white rounded-lg hover:opacity-90 transition-colors flex items-center gap-2"
                  >
                    {copiedUrl ? (
                      <>
                        <Check className="h-4 w-4" />
                        Copied
                      </>
                    ) : (
                      <>
                        <Copy className="h-4 w-4" />
                        Copy
                      </>
                    )}
                  </button>
                </div>
              </div>
            )}
          </div>
        )}

        {/* Tags Tab */}
        {activeTab === 'tags' && (
          <div className="space-y-4">
            {file.tags && file.tags.length > 0 ? (
              <div className="flex flex-wrap gap-2">
                {file.tags.map(tag => (
                  <span
                    key={tag.id}
                    className="px-3 py-1 rounded-full text-sm font-medium"
                    style={{
                      backgroundColor: tag.color + '20',
                      color: tag.color
                    }}
                  >
                    {tag.name}
                  </span>
                ))}
              </div>
            ) : (
              <div className="text-center py-8 text-theme-secondary">
                <Tag className="h-12 w-12 mx-auto mb-4" />
                <p>No tags added to this file</p>
              </div>
            )}
          </div>
        )}
      </div>
    </Modal>
  );
};


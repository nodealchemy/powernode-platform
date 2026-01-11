import React, { useState } from 'react';
import { Upload } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { FileUpload } from '@/features/content/files/components/FileUpload';
import { FileBrowser } from '@/features/content/files/components/FileBrowser';
import { FileObject } from '@/features/content/files/services/filesApi';
import { useAuth } from '@/shared/hooks/useAuth';

const FilesPage: React.FC = () => {
  const { currentUser } = useAuth();
  const [showUploadArea, setShowUploadArea] = useState(false);
  const [refreshKey, setRefreshKey] = useState(0);

  const handleUploadComplete = (_file: FileObject) => {
    // Refresh the file browser
    setRefreshKey(prev => prev + 1);
    setShowUploadArea(false);
  };

  // Check permissions
  const canUpload = currentUser?.permissions?.includes('files.create');
  const canRead = currentUser?.permissions?.includes('files.read');

  if (!canRead) {
    return (
      <PageContainer
        title="Files"
        description="File management and storage"
      >
        <div className="text-center py-12">
          <p className="text-theme-secondary">
            You don't have permission to view files.
          </p>
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title="Files"
      description="Manage files and uploads across your organization"
      actions={
        canUpload ? [
          {
            label: 'Upload Files',
            onClick: () => setShowUploadArea(!showUploadArea),
            icon: Upload,
            variant: 'primary' as const
          }
        ] : []
      }
    >
      <div className="space-y-6">
        {/* Upload Area */}
        {showUploadArea && canUpload && (
          <div className="bg-theme-surface border border-theme rounded-lg p-6">
            <h3 className="text-lg font-semibold text-theme-primary mb-4">
              Upload New Files
            </h3>

            <FileUpload
              onUploadComplete={handleUploadComplete}
              category="user_upload"
              visibility="private"
              maxSizeMB={100}
              multiple={true}
            />

            <button
              onClick={() => setShowUploadArea(false)}
              className="mt-4 text-sm text-theme-secondary hover:text-theme-primary"
            >
              Cancel
            </button>
          </div>
        )}

        {/* File Browser */}
        <div className="bg-theme-surface border border-theme rounded-lg p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4">
            All Files
          </h3>

          <FileBrowser
            key={refreshKey}
          />
        </div>
      </div>
    </PageContainer>
  );
};

export default FilesPage;

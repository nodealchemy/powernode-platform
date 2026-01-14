import React, { useState, useEffect } from 'react';
import { Upload, Search, Download, Trash2, RefreshCw, HardDrive, Database } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { useAuth } from '@/shared/hooks/useAuth';
import { FileUpload } from '@/features/content/files/components/FileUpload';
import { FileItem } from '@/features/content/files/components/FileItem';
import { FileDetails } from '@/features/content/files/components/FileDetails';
import { filesApi, FileObject } from '@/features/content/files/services/filesApi';
import { storageApi } from '@/features/system/storage/services/storageApi';
import { StorageProvider } from '@/shared/types/storage';
import { useDispatch } from 'react-redux';
import { addNotification } from '@/shared/services/slices/uiSlice';
import { AppDispatch } from '@/shared/services';

const MyFilesPage: React.FC = () => {
  const dispatch = useDispatch<AppDispatch>();
  const { currentUser } = useAuth();
  const [files, setFiles] = useState<FileObject[]>([]);
  const [storageProviders, setStorageProviders] = useState<StorageProvider[]>([]);
  const [selectedStorageId, setSelectedStorageId] = useState<string>('');
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedFile, setSelectedFile] = useState<FileObject | null>(null);
  const [selectedFileTab, setSelectedFileTab] = useState<'details' | 'share' | 'tags'>('details');
  const [showUploadModal, setShowUploadModal] = useState(false);
  const [filterCategory, setFilterCategory] = useState('');
  const [filterVisibility, setFilterVisibility] = useState('');
  const [selectedFiles, setSelectedFiles] = useState<Set<string>>(new Set());
  const [fileStats, setFileStats] = useState<{
    total_files: number;
    total_size: number;
    by_category: Record<string, number>;
    by_type: Record<string, number>;
  } | null>(null);

  // Check permissions
  const canUpload = currentUser?.permissions?.includes('files.create');
  const canDelete = currentUser?.permissions?.includes('files.delete');
  const canRead = currentUser?.permissions?.includes('files.read');
  const canManageStorage = currentUser?.permissions?.includes('admin.storage.read');

  // Load files
  const loadFiles = async (): Promise<void> => {
    if (!canRead) return;

    try {
      setLoading(true);
      const params: {
        category?: string;
        visibility?: string;
        storage_id?: string;
        search?: string;
      } = {};

      if (filterCategory) params.category = filterCategory;
      if (filterVisibility) params.visibility = filterVisibility;
      if (selectedStorageId) params.storage_id = selectedStorageId;
      if (searchQuery) params.search = searchQuery;

      const response = await filesApi.getFiles(params);
      setFiles(response.files);
    } catch (error) {
      dispatch(addNotification({ type: 'error', message: 'Failed to load files' }));
      if (process.env.NODE_ENV === 'development') {
        console.error('Error loading files:', error);
      }
    } finally {
      setLoading(false);
    }
  };

  // Load storage providers
  const loadStorageProviders = async (): Promise<void> => {
    if (!canManageStorage) return;

    try {
      const providers = await storageApi.getProviders();
      setStorageProviders(providers);

      // Set default storage provider
      const defaultProvider = providers.find(p => p.is_default);
      if (defaultProvider) {
        setSelectedStorageId(defaultProvider.id);
      }
    } catch (error) {
      console.error('Error loading storage providers:', error);
    }
  };

  // Load file statistics
  const loadFileStats = async (): Promise<void> => {
    try {
      const stats = await filesApi.getStats();
      setFileStats(stats);
    } catch (error) {
      console.error('Error loading file stats:', error);
    }
  };

  useEffect(() => {
    void loadFiles();
  }, [filterCategory, filterVisibility, selectedStorageId, searchQuery]);

  useEffect(() => {
    void loadStorageProviders();
    void loadFileStats();
  }, []);

  const handleUploadComplete = (file: FileObject) => {
    dispatch(addNotification({ type: 'success', message: `${file.filename} uploaded successfully` }));
    void loadFiles();
    void loadFileStats();
  };

  const handleView = (file: FileObject) => {
    setSelectedFileTab('details');
    setSelectedFile(file);
  };

  const handleDownload = async (file: FileObject): Promise<void> => {
    try {
      await filesApi.downloadFile(file.id, file.filename);
      dispatch(addNotification({ type: 'success', message: `Downloading ${file.filename}` }));
    } catch (error) {
      dispatch(addNotification({ type: 'error', message: 'Download failed' }));
    }
  };

  const handleShare = async (file: FileObject): Promise<void> => {
    setSelectedFileTab('share');
    setSelectedFile(file);
  };

  const handleDelete = async (file: FileObject): Promise<void> => {
    if (!confirm(`Delete ${file.filename}?`)) return;

    try {
      await filesApi.deleteFile(file.id);
      dispatch(addNotification({ type: 'success', message: 'File deleted successfully' }));
      void loadFiles();
      void loadFileStats();
    } catch (error) {
      dispatch(addNotification({ type: 'error', message: 'Failed to delete file' }));
    }
  };

  const handleBulkDownload = async (): Promise<void> => {
    const selectedFileObjects = files.filter(f => selectedFiles.has(f.id));

    for (const file of selectedFileObjects) {
      try {
        await filesApi.downloadFile(file.id, file.filename);
      } catch (error) {
        dispatch(addNotification({ type: 'error', message: `Failed to download ${file.filename}` }));
      }
    }

    dispatch(addNotification({ type: 'success', message: `Downloading ${selectedFiles.size} file(s)` }));
  };

  const handleBulkDelete = async (): Promise<void> => {
    if (!confirm(`Delete ${selectedFiles.size} file(s)?`)) return;

    const selectedFileObjects = files.filter(f => selectedFiles.has(f.id));
    let successCount = 0;

    for (const file of selectedFileObjects) {
      try {
        await filesApi.deleteFile(file.id);
        successCount++;
      } catch (error) {
        dispatch(addNotification({ type: 'error', message: `Failed to delete ${file.filename}` }));
      }
    }

    dispatch(addNotification({ type: 'success', message: `Deleted ${successCount} file(s)` }));
    setSelectedFiles(new Set());
    void loadFiles();
    void loadFileStats();
  };

  const toggleFileSelection = (fileId: string) => {
    const newSelection = new Set(selectedFiles);
    if (newSelection.has(fileId)) {
      newSelection.delete(fileId);
    } else {
      newSelection.add(fileId);
    }
    setSelectedFiles(newSelection);
  };

  const formatFileSize = (bytes: number): string => {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
  };

  const getStorageUsagePercentage = (): number => {
    if (!fileStats || !selectedStorageId) return 0;

    const selectedProvider = storageProviders.find(p => p.id === selectedStorageId);
    if (!selectedProvider?.max_file_size_mb) return 0;

    const quotaBytes = selectedProvider.max_file_size_mb * 1024 * 1024;
    return Math.round((fileStats.total_size / quotaBytes) * 100);
  };

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Content', href: '/app/content' },
    { label: 'My Files' }
  ];

  if (!canRead) {
    return (
      <PageContainer
        title="My Files"
        description="Access denied"
        breadcrumbs={breadcrumbs}
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
      title="My Files"
      description="Manage your personal files and documents"
      breadcrumbs={breadcrumbs}
      actions={
        canUpload
          ? [
              {
                label: 'Upload Files',
                onClick: () => setShowUploadModal(true),
                variant: 'primary',
                icon: Upload,
              },
              {
                label: 'Refresh',
                onClick: () => {
                  void loadFiles();
                  void loadFileStats();
                },
                variant: 'secondary',
                icon: RefreshCw,
              },
            ]
          : [
              {
                label: 'Refresh',
                onClick: () => {
                  void loadFiles();
                  void loadFileStats();
                },
                variant: 'secondary',
                icon: RefreshCw,
              },
            ]
      }
    >
      <div className="space-y-6">
        {/* Upload Modal */}
        {showUploadModal && (
          <div className="fixed inset-0 bg-black bg-opacity-50 z-50 flex items-center justify-center p-4">
            <div className="bg-theme-surface border border-theme rounded-lg max-w-2xl w-full p-6">
              <div className="flex justify-between items-center mb-4">
                <h3 className="text-lg font-semibold text-theme-primary">Upload Files</h3>
                <button
                  onClick={() => setShowUploadModal(false)}
                  className="text-theme-secondary hover:text-theme-primary"
                >
                  ×
                </button>
              </div>

              {/* Storage Provider Selector */}
              {canManageStorage && storageProviders.length > 0 && (
                <div className="mb-4">
                  <label className="block text-sm font-medium text-theme-primary mb-2">
                    Storage Provider
                  </label>
                  <select
                    value={selectedStorageId}
                    onChange={(e) => setSelectedStorageId(e.target.value)}
                    className="w-full px-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-info"
                  >
                    {storageProviders.map((provider) => (
                      <option key={provider.id} value={provider.id}>
                        {provider.name} ({provider.provider_type})
                        {provider.is_default && ' - Default'}
                      </option>
                    ))}
                  </select>
                </div>
              )}

              <FileUpload
                onUploadComplete={handleUploadComplete}
                category="user_upload"
                visibility="private"
                multiple={true}
                maxSizeMB={100}
              />

              <div className="mt-4 flex justify-end">
                <button
                  onClick={() => setShowUploadModal(false)}
                  className="px-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary hover:bg-theme-hover transition-colors"
                >
                  Close
                </button>
              </div>
            </div>
          </div>
        )}

        {/* Search and Filters */}
        <div className="flex flex-col lg:flex-row gap-4">
          <div className="flex-1">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-theme-secondary" />
              <input
                type="text"
                placeholder="Search files..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="w-full pl-10 pr-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary placeholder-theme-secondary focus:outline-none focus:ring-2 focus:ring-theme-info"
              />
            </div>
          </div>

          {/* Category Filter */}
          <select
            value={filterCategory}
            onChange={(e) => setFilterCategory(e.target.value)}
            className="px-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-info"
          >
            <option value="">All Categories</option>
            <option value="user_upload">User Upload</option>
            <option value="workflow_output">Workflow Output</option>
            <option value="ai_generated">AI Generated</option>
            <option value="temp">Temporary</option>
          </select>

          {/* Visibility Filter */}
          <select
            value={filterVisibility}
            onChange={(e) => setFilterVisibility(e.target.value)}
            className="px-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-info"
          >
            <option value="">All Visibility</option>
            <option value="private">Private</option>
            <option value="public">Public</option>
            <option value="shared">Shared</option>
          </select>

          {/* Storage Provider Filter */}
          {canManageStorage && storageProviders.length > 0 && (
            <select
              value={selectedStorageId}
              onChange={(e) => setSelectedStorageId(e.target.value)}
              className="px-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-info"
            >
              <option value="">All Storage</option>
              {storageProviders.map((provider) => (
                <option key={provider.id} value={provider.id}>
                  {provider.name}
                </option>
              ))}
            </select>
          )}
        </div>

        {/* Bulk Actions */}
        {selectedFiles.size > 0 && (
          <div className="flex items-center gap-4 p-4 bg-theme-info/10 dark:bg-theme-info/20 border border-theme-info/30 dark:border-theme-info/50 rounded-lg">
            <span className="text-sm text-theme-primary">
              {selectedFiles.size} file{selectedFiles.size > 1 ? 's' : ''} selected
            </span>
            <div className="flex gap-2 ml-auto">
              <button
                onClick={handleBulkDownload}
                className="px-3 py-1.5 text-sm bg-theme-surface border border-theme rounded-lg text-theme-primary hover:bg-theme-hover transition-colors flex items-center gap-2"
              >
                <Download className="h-3.5 w-3.5" />
                Download
              </button>
              {canDelete && (
                <button
                  onClick={handleBulkDelete}
                  className="px-3 py-1.5 text-sm bg-theme-danger/10 dark:bg-theme-danger/20 border border-theme-danger/30 dark:border-theme-danger/50 rounded-lg text-theme-danger hover:bg-theme-danger/20 dark:hover:bg-theme-danger/30 transition-colors flex items-center gap-2"
                >
                  <Trash2 className="h-3.5 w-3.5" />
                  Delete
                </button>
              )}
              <button
                onClick={() => setSelectedFiles(new Set())}
                className="px-3 py-1.5 text-sm text-theme-secondary hover:text-theme-primary transition-colors"
              >
                Clear
              </button>
            </div>
          </div>
        )}

        {/* Files List */}
        {loading ? (
          <div className="text-center py-12 text-theme-secondary">
            <RefreshCw className="h-8 w-8 animate-spin mx-auto mb-2" />
            <p>Loading files...</p>
          </div>
        ) : files.length === 0 ? (
          <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
            <HardDrive className="h-12 w-12 text-theme-secondary mx-auto mb-4" />
            <p className="text-theme-secondary mb-2">
              {searchQuery || filterCategory || filterVisibility
                ? 'No files found'
                : 'No files yet'}
            </p>
            {canUpload && !searchQuery && !filterCategory && !filterVisibility && (
              <button
                onClick={() => setShowUploadModal(true)}
                className="mt-4 px-4 py-2 bg-theme-info text-white rounded-lg hover:opacity-90 transition-colors flex items-center gap-2 mx-auto"
              >
                <Upload className="h-4 w-4" />
                Upload your first file
              </button>
            )}
          </div>
        ) : (
          <div className="space-y-2">
            {/* Select All Checkbox */}
            <div className="flex items-center gap-2 px-4 py-2 bg-theme-surface border border-theme rounded-lg">
              <input
                type="checkbox"
                checked={selectedFiles.size === files.length && files.length > 0}
                onChange={(e) => {
                  if (e.target.checked) {
                    setSelectedFiles(new Set(files.map((f) => f.id)));
                  } else {
                    setSelectedFiles(new Set());
                  }
                }}
                className="rounded border-theme-secondary"
              />
              <span className="text-sm text-theme-secondary">
                {selectedFiles.size > 0
                  ? `${selectedFiles.size} of ${files.length} selected`
                  : 'Select all'}
              </span>
            </div>

            {/* File Items */}
            {files.map((file) => (
              <div key={file.id} className="flex items-center gap-2">
                <input
                  type="checkbox"
                  checked={selectedFiles.has(file.id)}
                  onChange={() => toggleFileSelection(file.id)}
                  className="ml-4 rounded border-theme-secondary flex-shrink-0"
                />
                <div className="flex-1">
                  <FileItem
                    file={file}
                    onView={handleView}
                    onDownload={handleDownload}
                    onShare={handleShare}
                    onDelete={canDelete ? handleDelete : undefined}
                  />
                </div>
              </div>
            ))}
          </div>
        )}

        {/* Storage Info */}
        {fileStats && (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {/* Storage Usage */}
            <div className="bg-theme-info/10 dark:bg-theme-info/20 border border-theme-info/30 dark:border-theme-info/50 rounded-lg p-4">
              <div className="flex items-center gap-2 mb-2">
                <Database className="h-5 w-5 text-theme-info" />
                <span className="text-sm font-medium text-theme-primary">
                  Storage Used
                </span>
              </div>
              <div className="flex items-center justify-between mb-2">
                <span className="text-2xl font-bold text-theme-primary">
                  {formatFileSize(fileStats.total_size)}
                </span>
                {selectedStorageId && (
                  <span className="text-sm text-theme-secondary">
                    {getStorageUsagePercentage()}% used
                  </span>
                )}
              </div>
              {selectedStorageId && (
                <div className="w-full bg-theme-surface rounded-full h-2 overflow-hidden">
                  <div
                    className="bg-theme-info h-full rounded-full transition-all"
                    style={{ width: `${Math.min(getStorageUsagePercentage(), 100)}%` }}
                  ></div>
                </div>
              )}
            </div>

            {/* File Count */}
            <div className="bg-theme-success/10 dark:bg-theme-success/20 border border-theme-success/30 dark:border-theme-success/50 rounded-lg p-4">
              <div className="flex items-center gap-2 mb-2">
                <HardDrive className="h-5 w-5 text-theme-success" />
                <span className="text-sm font-medium text-theme-primary">
                  Total Files
                </span>
              </div>
              <div className="text-2xl font-bold text-theme-primary">
                {fileStats.total_files.toLocaleString()}
              </div>
              {Object.keys(fileStats.by_category).length > 0 && (
                <div className="mt-2 text-xs text-theme-secondary">
                  {Object.entries(fileStats.by_category)
                    .slice(0, 2)
                    .map(([category, count]) => (
                      <div key={category}>
                        {category.replace('_', ' ')}: {count}
                      </div>
                    ))}
                </div>
              )}
            </div>
          </div>
        )}
      </div>

      {/* File Details Modal */}
      {selectedFile && (
        <FileDetails
          file={selectedFile}
          isOpen={!!selectedFile}
          onClose={() => setSelectedFile(null)}
          initialTab={selectedFileTab}
          onFileUpdated={() => {
            void loadFiles();
            void loadFileStats();
          }}
        />
      )}
    </PageContainer>
  );
};

export default MyFilesPage;

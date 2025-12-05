import React, { useState, useEffect, useCallback, useRef } from 'react';
import { Search, RefreshCw, ChevronLeft, ChevronRight, X } from 'lucide-react';
import { filesApi, FileObject } from '../services/filesApi';
import { FileItem } from './FileItem';
import { FileDetails } from './FileDetails';
import { useNotifications } from '@/shared/hooks/useNotifications';

interface FileBrowserProps {
  category?: string;
  visibility?: string;
  onFileSelect?: (file: FileObject) => void;
}

interface PaginationInfo {
  current_page: number;
  total_pages: number;
  total_count: number;
  per_page: number;
}

type SortField = 'filename' | 'file_size' | 'created_at';
type SortOrder = 'asc' | 'desc';

export const FileBrowser: React.FC<FileBrowserProps> = ({
  category,
  visibility,
  onFileSelect
}) => {
  const [files, setFiles] = useState<FileObject[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedFile, setSelectedFile] = useState<FileObject | null>(null);
  const [filterCategory, setFilterCategory] = useState(category || '');
  const [filterVisibility, setFilterVisibility] = useState(visibility || '');
  const [filterFileType, setFilterFileType] = useState('');
  const { showNotification } = useNotifications();

  // Use ref to avoid infinite render loop with showNotification in useCallback
  const showNotificationRef = useRef(showNotification);
  showNotificationRef.current = showNotification;

  // Sync props to state when they change (for controlled updates from parent)
  useEffect(() => {
    if (category !== undefined) {
      setFilterCategory(category);
    }
  }, [category]);

  useEffect(() => {
    if (visibility !== undefined) {
      setFilterVisibility(visibility);
    }
  }, [visibility]);

  // Pagination state
  const [pagination, setPagination] = useState<PaginationInfo>({
    current_page: 1,
    total_pages: 1,
    total_count: 0,
    per_page: 20
  });
  const [perPage, setPerPage] = useState(20);

  // Sorting state
  const [sortBy, setSortBy] = useState<SortField>('created_at');
  const [sortOrder, setSortOrder] = useState<SortOrder>('desc');

  // Selection state for bulk actions
  const [selectedFiles, setSelectedFiles] = useState<Set<string>>(new Set());

  const loadFiles = useCallback(async (page: number = 1): Promise<void> => {
    try {
      setLoading(true);
      setError(null);
      const params: Record<string, unknown> = {
        page,
        per_page: perPage,
        sort_by: sortBy,
        sort_order: sortOrder
      };

      if (filterCategory) params.category = filterCategory;
      if (filterVisibility) params.visibility = filterVisibility;
      if (filterFileType) params.file_type = filterFileType;
      if (searchQuery) params.search = searchQuery;

      const response = await filesApi.getFiles(params as Parameters<typeof filesApi.getFiles>[0]);
      setFiles(response.files);
      setPagination(response.pagination || {
        current_page: 1,
        total_pages: 1,
        total_count: response.files.length,
        per_page: perPage
      });
      setSelectedFiles(new Set()); // Clear selection on new data
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to load files';
      setError(errorMessage);
      showNotificationRef.current('Failed to load files', 'error');
    } finally {
      setLoading(false);
    }
  }, [filterCategory, filterVisibility, filterFileType, searchQuery, perPage, sortBy, sortOrder]);

  useEffect(() => {
    void loadFiles(1);
  }, [loadFiles]);

  const handleView = (file: FileObject) => {
    setSelectedFile(file);
    onFileSelect?.(file);
  };

  const handleDownload = async (file: FileObject): Promise<void> => {
    try {
      await filesApi.downloadFile(file.id, file.filename);
      showNotification(`Downloading ${file.filename}`, 'success');
    } catch {
      showNotification('Download failed', 'error');
    }
  };

  const handleShare = async (file: FileObject): Promise<void> => {
    setSelectedFile(file);
    // FileDetails modal will handle share functionality
  };

  const handleDelete = async (file: FileObject): Promise<void> => {
    if (!confirm(`Delete ${file.filename}?`)) return;

    try {
      await filesApi.deleteFile(file.id);
      showNotification('File deleted successfully', 'success');
      void loadFiles(pagination.current_page);
    } catch {
      showNotification('Failed to delete file', 'error');
    }
  };

  const handleRefresh = () => {
    void loadFiles(pagination.current_page);
  };

  // Pagination handlers
  const handleNextPage = () => {
    if (pagination.current_page < pagination.total_pages) {
      void loadFiles(pagination.current_page + 1);
    }
  };

  const handlePrevPage = () => {
    if (pagination.current_page > 1) {
      void loadFiles(pagination.current_page - 1);
    }
  };

  const handlePerPageChange = (newPerPage: number) => {
    setPerPage(newPerPage);
    // Will trigger reload via useEffect
  };

  // Sorting handlers
  const handleSort = (field: SortField) => {
    if (sortBy === field) {
      // Toggle order if same field
      setSortOrder(sortOrder === 'asc' ? 'desc' : 'asc');
    } else {
      setSortBy(field);
      setSortOrder(field === 'created_at' ? 'desc' : 'asc');
    }
  };

  // Bulk selection handlers
  const handleSelectFile = (fileId: string) => {
    const newSelection = new Set(selectedFiles);
    if (newSelection.has(fileId)) {
      newSelection.delete(fileId);
    } else {
      newSelection.add(fileId);
    }
    setSelectedFiles(newSelection);
  };

  const handleSelectAll = () => {
    if (selectedFiles.size === files.length) {
      setSelectedFiles(new Set());
    } else {
      setSelectedFiles(new Set(files.map(f => f.id)));
    }
  };

  const handleBulkDelete = async () => {
    if (selectedFiles.size === 0) return;
    if (!confirm(`Delete ${selectedFiles.size} selected files?`)) return;

    try {
      await Promise.all(
        Array.from(selectedFiles).map(id => filesApi.deleteFile(id))
      );
      showNotification(`${selectedFiles.size} files deleted successfully`, 'success');
      setSelectedFiles(new Set());
      void loadFiles(pagination.current_page);
    } catch {
      showNotification('Failed to delete some files', 'error');
    }
  };

  // Clear filters
  const handleClearFilters = () => {
    setFilterCategory('');
    setFilterVisibility('');
    setFilterFileType('');
    setSearchQuery('');
  };

  const hasActiveFilters = filterCategory || filterVisibility || filterFileType || searchQuery;

  const getSortIndicator = (field: SortField) => {
    if (sortBy !== field) return null;
    return sortOrder === 'asc' ? ' ↑' : ' ↓';
  };

  return (
    <div className="space-y-4">
      {/* Filters and Search */}
      <div className="flex flex-col sm:flex-row gap-4">
        {/* Search */}
        <div className="flex-1 relative">
          <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-5 w-5 text-theme-secondary" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Search files..."
            className="w-full pl-10 pr-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary placeholder-theme-secondary focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
        </div>

        {/* Category Filter */}
        <select
          value={filterCategory}
          onChange={(e) => setFilterCategory(e.target.value)}
          aria-label="Category"
          className="px-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-blue-500"
        >
          <option value="">All Categories</option>
          <option value="user_upload">User Upload</option>
          <option value="workflow_output">Workflow Output</option>
          <option value="ai_generated">AI Generated</option>
          <option value="temp">Temporary</option>
        </select>

        {/* File Type Filter */}
        <select
          value={filterFileType}
          onChange={(e) => setFilterFileType(e.target.value)}
          aria-label="File type"
          className="px-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-blue-500"
        >
          <option value="">All Types</option>
          <option value="document">Document</option>
          <option value="image">Image</option>
          <option value="video">Video</option>
          <option value="audio">Audio</option>
          <option value="archive">Archive</option>
          <option value="code">Code</option>
          <option value="data">Data</option>
        </select>

        {/* Visibility Filter */}
        <select
          value={filterVisibility}
          onChange={(e) => setFilterVisibility(e.target.value)}
          aria-label="Visibility"
          className="px-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-blue-500"
        >
          <option value="">All Visibility</option>
          <option value="private">Private</option>
          <option value="public">Public</option>
          <option value="shared">Shared</option>
        </select>

        {/* Clear Filters Button */}
        {hasActiveFilters && (
          <button
            onClick={handleClearFilters}
            className="px-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors flex items-center gap-2"
            aria-label="Clear filters"
          >
            <X className="h-4 w-4" />
            Clear
          </button>
        )}

        {/* Refresh Button */}
        <button
          onClick={handleRefresh}
          className="px-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary hover:bg-theme-surface dark:hover:bg-gray-700 transition-colors"
          title="Refresh files"
          aria-label="Refresh"
        >
          <RefreshCw className={`h-5 w-5 ${loading ? 'animate-spin' : ''}`} />
        </button>
      </div>

      {/* Bulk Actions Bar */}
      {selectedFiles.size > 0 && (
        <div className="flex items-center gap-4 p-3 bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 rounded-lg">
          <span className="text-sm text-theme-primary">
            {selectedFiles.size} selected
          </span>
          <button
            onClick={handleBulkDelete}
            className="px-3 py-1 bg-red-500 text-white rounded hover:bg-red-600 transition-colors text-sm"
            aria-label="Delete selected"
          >
            Delete Selected
          </button>
          <button
            onClick={() => setSelectedFiles(new Set())}
            className="px-3 py-1 bg-theme-surface border border-theme rounded hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors text-sm text-theme-primary"
          >
            Clear Selection
          </button>
        </div>
      )}

      {/* Sorting Controls */}
      <div className="flex items-center gap-2 text-sm text-theme-secondary">
        <span>Sort by:</span>
        <button
          onClick={() => handleSort('filename')}
          className={`px-2 py-1 rounded ${sortBy === 'filename' ? 'bg-theme-surface text-theme-primary' : 'hover:bg-theme-surface'}`}
          aria-label="Name"
        >
          Name{getSortIndicator('filename')}
        </button>
        <button
          onClick={() => handleSort('file_size')}
          className={`px-2 py-1 rounded ${sortBy === 'file_size' ? 'bg-theme-surface text-theme-primary' : 'hover:bg-theme-surface'}`}
          aria-label="Size"
        >
          Size{getSortIndicator('file_size')}
        </button>
        <button
          onClick={() => handleSort('created_at')}
          className={`px-2 py-1 rounded ${sortBy === 'created_at' ? 'bg-theme-surface text-theme-primary' : 'hover:bg-theme-surface'}`}
          aria-label="Date"
        >
          Date{getSortIndicator('created_at')}
        </button>
      </div>

      {/* Error State */}
      {error && (
        <div className="text-center py-8 text-theme-danger bg-red-50 dark:bg-red-900/20 rounded-lg">
          <p>Error loading files: {error}</p>
          <button
            onClick={handleRefresh}
            className="mt-2 text-theme-info hover:underline"
          >
            Try again
          </button>
        </div>
      )}

      {/* Files List */}
      {loading ? (
        <div className="text-center py-12 text-theme-secondary">
          <RefreshCw className="h-8 w-8 animate-spin mx-auto mb-2" />
          <p>Loading files...</p>
        </div>
      ) : !error && files.length === 0 ? (
        <div className="text-center py-12 text-theme-secondary">
          <p>No files found</p>
          {hasActiveFilters && (
            <button
              onClick={handleClearFilters}
              className="mt-2 text-theme-info hover:underline"
            >
              Clear filters
            </button>
          )}
        </div>
      ) : !error && (
        <div className="space-y-2">
          {/* Select All Checkbox */}
          <div className="flex items-center gap-2 p-2 border-b border-theme">
            <input
              type="checkbox"
              checked={selectedFiles.size === files.length && files.length > 0}
              onChange={handleSelectAll}
              className="h-4 w-4 rounded border-theme"
              aria-label="Select all"
            />
            <span className="text-sm text-theme-secondary">Select all</span>
          </div>

          {files.map(file => (
            <div key={file.id} className="flex items-center gap-2">
              <input
                type="checkbox"
                checked={selectedFiles.has(file.id)}
                onChange={() => handleSelectFile(file.id)}
                className="h-4 w-4 rounded border-theme ml-2"
                aria-label={`Select ${file.filename}`}
              />
              <div className="flex-1">
                <FileItem
                  file={file}
                  onView={handleView}
                  onDownload={handleDownload}
                  onShare={handleShare}
                  onDelete={handleDelete}
                />
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Pagination Controls */}
      {!loading && !error && pagination.total_pages > 0 && (
        <div className="flex items-center justify-between pt-4 border-t border-theme">
          <div className="flex items-center gap-2">
            <span className="text-sm text-theme-secondary">
              Showing {((pagination.current_page - 1) * perPage) + 1} - {Math.min(pagination.current_page * perPage, pagination.total_count)} of {pagination.total_count}
            </span>
          </div>

          <div className="flex items-center gap-4">
            {/* Items per page */}
            <div className="flex items-center gap-2">
              <label htmlFor="perPage" className="text-sm text-theme-secondary">
                Per page:
              </label>
              <select
                id="perPage"
                value={perPage}
                onChange={(e) => handlePerPageChange(Number(e.target.value))}
                aria-label="Items per page"
                className="px-2 py-1 bg-theme-surface border border-theme rounded text-sm text-theme-primary"
              >
                <option value={10}>10</option>
                <option value={20}>20</option>
                <option value={50}>50</option>
                <option value={100}>100</option>
              </select>
            </div>

            {/* Page navigation */}
            <div className="flex items-center gap-2">
              <button
                onClick={handlePrevPage}
                disabled={pagination.current_page <= 1}
                className="p-1 rounded hover:bg-theme-surface disabled:opacity-50 disabled:cursor-not-allowed"
                aria-label="Previous page"
              >
                <ChevronLeft className="h-5 w-5" />
              </button>
              <span className="text-sm text-theme-primary">
                Page {pagination.current_page} of {pagination.total_pages}
              </span>
              <button
                onClick={handleNextPage}
                disabled={pagination.current_page >= pagination.total_pages}
                className="p-1 rounded hover:bg-theme-surface disabled:opacity-50 disabled:cursor-not-allowed"
                aria-label="Next page"
              >
                <ChevronRight className="h-5 w-5" />
              </button>
            </div>
          </div>
        </div>
      )}

      {/* File Details Modal */}
      {selectedFile && (
        <FileDetails
          file={selectedFile}
          isOpen={!!selectedFile}
          onClose={() => setSelectedFile(null)}
          onFileUpdated={() => void loadFiles(pagination.current_page)}
        />
      )}
    </div>
  );
};


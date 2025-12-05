import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { FileBrowser } from '../components/FileBrowser';
import { filesApi } from '../services/filesApi';

// Mock the files API
jest.mock('../services/filesApi');

// Mock global notifications - component uses showNotification
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    showNotification: jest.fn(),
  }),
}));

// Mock lucide icons
jest.mock('lucide-react', () => ({
  Search: () => <span data-testid="search-icon" />,
  RefreshCw: ({ className }: any) => <span data-testid="refresh-icon" className={className} />,
  ChevronLeft: () => <span data-testid="chevron-left" />,
  ChevronRight: () => <span data-testid="chevron-right" />,
  X: () => <span data-testid="x-icon" />,
  FileText: () => <span data-testid="file-text-icon" />,
  Image: () => <span data-testid="image-icon" />,
  Video: () => <span data-testid="video-icon" />,
  Music: () => <span data-testid="music-icon" />,
  Archive: () => <span data-testid="archive-icon" />,
  Code: () => <span data-testid="code-icon" />,
  FileType: () => <span data-testid="file-type-icon" />,
  Download: () => <span data-testid="download-icon" />,
  Share2: () => <span data-testid="share-icon" />,
  Trash2: () => <span data-testid="trash-icon" />,
  Eye: () => <span data-testid="eye-icon" />,
}));

// Mock FileItem component (named export)
jest.mock('../components/FileItem', () => ({
  FileItem: function MockFileItem({ file, onView, onDownload, onDelete }: any) {
    return (
      <div data-testid={`file-item-${file.id}`} className="file-item">
        <span
          data-testid="filename"
          onClick={() => onView?.(file)}
          style={{ cursor: 'pointer' }}
        >
          {file.filename}
        </span>
        <span data-testid="file-size">{(file.file_size / (1024 * 1024)).toFixed(1)} MB</span>
        <span data-testid="download-count">{file.download_count || 0} downloads</span>
        <button
          onClick={() => onDownload?.(file)}
          aria-label="Download"
        >
          Download
        </button>
        <button
          onClick={() => onDelete?.(file)}
          aria-label="Delete"
        >
          Delete
        </button>
      </div>
    );
  },
}));

// Mock FileDetails component (named export)
jest.mock('../components/FileDetails', () => ({
  FileDetails: function MockFileDetails({ file, isOpen, onClose }: any) {
    if (!isOpen) return null;
    return (
      <div role="dialog" data-testid="file-details-modal">
        <h2>{file?.filename}</h2>
        <button onClick={onClose}>Close</button>
      </div>
    );
  },
}));

const mockFilesApi = jest.mocked(filesApi);

// Mock current user with permissions
jest.mock('@/shared/hooks/useAuth', () => ({
  useAuth: () => ({
    currentUser: {
      id: 'user-1',
      permissions: ['files.read', 'files.upload', 'files.delete', 'files.manage'],
    },
  }),
}));

describe('FileBrowser Integration Tests', () => {
  const mockFiles = [
    {
      id: 'file-1',
      filename: 'document.pdf',
      file_size: 1024000,
      content_type: 'application/pdf',
      file_type: 'document',
      category: 'user_upload',
      visibility: 'private',
      storage_key: 'uploads/document.pdf',
      version: 1,
      processing_status: 'completed',
      created_at: '2025-01-15T10:00:00Z',
      updated_at: '2025-01-15T10:00:00Z',
      download_count: 5,
    },
    {
      id: 'file-2',
      filename: 'image.jpg',
      file_size: 2048000,
      content_type: 'image/jpeg',
      file_type: 'image',
      category: 'workflow_output',
      visibility: 'shared',
      storage_key: 'images/image.jpg',
      version: 1,
      processing_status: 'completed',
      created_at: '2025-01-16T11:00:00Z',
      updated_at: '2025-01-16T11:00:00Z',
      download_count: 10,
    },
    {
      id: 'file-3',
      filename: 'data.csv',
      file_size: 512000,
      content_type: 'text/csv',
      file_type: 'data',
      category: 'user_upload',
      visibility: 'private',
      storage_key: 'data/data.csv',
      version: 1,
      processing_status: 'completed',
      created_at: '2025-01-17T12:00:00Z',
      updated_at: '2025-01-17T12:00:00Z',
      download_count: 2,
    },
  ];

  beforeEach(() => {
    jest.clearAllMocks();
    mockFilesApi.getFiles.mockResolvedValue({
      files: mockFiles,
      pagination: {
        current_page: 1,
        total_pages: 1,
        total_count: 3,
        per_page: 20,
      },
    });
  });

  describe('File Listing and Display', () => {
    it('displays list of files on initial load', async () => {
      render(<FileBrowser />);

      await waitFor(() => {
        expect(screen.getByText('document.pdf')).toBeInTheDocument();
        expect(screen.getByText('image.jpg')).toBeInTheDocument();
        expect(screen.getByText('data.csv')).toBeInTheDocument();
      });

      // Verify API was called with sorting params
      expect(mockFilesApi.getFiles).toHaveBeenCalledWith(
        expect.objectContaining({
          page: 1,
          per_page: 20,
          sort_by: 'created_at',
          sort_order: 'desc',
        })
      );
    });

    it('shows loading state while fetching files', () => {
      mockFilesApi.getFiles.mockImplementation(
        () =>
          new Promise((resolve) => {
            setTimeout(() => resolve({ files: mockFiles, pagination: {} as any }), 1000);
          })
      );

      render(<FileBrowser />);

      expect(screen.getByText(/loading/i)).toBeInTheDocument();
    });

    it('displays file metadata correctly', async () => {
      render(<FileBrowser />);

      await waitFor(() => {
        expect(screen.getByText('document.pdf')).toBeInTheDocument();
      });

      // Check for file size display (1 MB)
      const fileSizes = screen.getAllByTestId('file-size');
      expect(fileSizes[0]).toHaveTextContent('1.0 MB');

      // Check for download count
      const downloadCounts = screen.getAllByTestId('download-count');
      expect(downloadCounts[0]).toHaveTextContent('5 downloads');
    });

    it('handles empty file list', async () => {
      mockFilesApi.getFiles.mockResolvedValue({
        files: [],
        pagination: {
          current_page: 1,
          total_pages: 0,
          total_count: 0,
          per_page: 20,
        },
      });

      render(<FileBrowser />);

      await waitFor(() => {
        expect(screen.getByText(/no files found/i)).toBeInTheDocument();
      });
    });

    it('handles API errors gracefully', async () => {
      mockFilesApi.getFiles.mockRejectedValue(new Error('Failed to fetch files'));

      render(<FileBrowser />);

      await waitFor(() => {
        expect(screen.getByText(/error loading files/i)).toBeInTheDocument();
      });
    });
  });

  describe('File Filtering', () => {
    it('filters files by category', async () => {
      const user = userEvent.setup();

      render(<FileBrowser />);

      await waitFor(() => {
        expect(screen.getByText('document.pdf')).toBeInTheDocument();
      });

      // Find and change category filter using aria-label
      const categoryFilter = screen.getByLabelText(/category/i);
      await user.selectOptions(categoryFilter, 'workflow_output');

      await waitFor(() => {
        expect(mockFilesApi.getFiles).toHaveBeenCalledWith(
          expect.objectContaining({
            category: 'workflow_output',
          })
        );
      });
    });

    it('filters files by file type', async () => {
      const user = userEvent.setup();

      render(<FileBrowser />);

      await waitFor(() => {
        expect(screen.getByText('document.pdf')).toBeInTheDocument();
      });

      const typeFilter = screen.getByLabelText(/file type/i);
      await user.selectOptions(typeFilter, 'image');

      await waitFor(() => {
        expect(mockFilesApi.getFiles).toHaveBeenCalledWith(
          expect.objectContaining({
            file_type: 'image',
          })
        );
      });
    });

    it('searches files by filename', async () => {
      const user = userEvent.setup();

      render(<FileBrowser />);

      await waitFor(() => {
        expect(screen.getByText('document.pdf')).toBeInTheDocument();
      });

      const searchInput = screen.getByPlaceholderText(/search/i);
      await user.type(searchInput, 'document');

      await waitFor(() => {
        expect(mockFilesApi.getFiles).toHaveBeenCalledWith(
          expect.objectContaining({
            search: 'document',
          })
        );
      }, { timeout: 1000 });
    });

    it('combines multiple filters', async () => {
      const user = userEvent.setup();

      render(<FileBrowser />);

      await waitFor(() => {
        expect(screen.getByText('document.pdf')).toBeInTheDocument();
      });

      // Apply category filter
      const categoryFilter = screen.getByLabelText(/category/i);
      await user.selectOptions(categoryFilter, 'user_upload');

      // Apply type filter
      const typeFilter = screen.getByLabelText(/file type/i);
      await user.selectOptions(typeFilter, 'document');

      await waitFor(() => {
        expect(mockFilesApi.getFiles).toHaveBeenCalledWith(
          expect.objectContaining({
            category: 'user_upload',
            file_type: 'document',
          })
        );
      });
    });

    it('clears filters', async () => {
      const user = userEvent.setup();

      render(<FileBrowser />);

      await waitFor(() => {
        expect(screen.getByText('document.pdf')).toBeInTheDocument();
      });

      // Apply filter
      const categoryFilter = screen.getByLabelText(/category/i);
      await user.selectOptions(categoryFilter, 'workflow_output');

      await waitFor(() => {
        expect(screen.getByLabelText(/clear filter/i)).toBeInTheDocument();
      });

      // Clear filter
      const clearButton = screen.getByLabelText(/clear filter/i);
      await user.click(clearButton);

      await waitFor(() => {
        // After clearing, the category should not be in the params
        const lastCall = mockFilesApi.getFiles.mock.calls[mockFilesApi.getFiles.mock.calls.length - 1];
        expect(lastCall[0]).not.toHaveProperty('category', 'workflow_output');
      });
    });
  });

  describe('File Actions', () => {
    it('downloads a file', async () => {
      const user = userEvent.setup();

      mockFilesApi.downloadFile.mockResolvedValue();

      render(<FileBrowser />);

      await waitFor(() => {
        expect(screen.getByText('document.pdf')).toBeInTheDocument();
      });

      // Find and click download button for first file
      const fileItem = screen.getByTestId('file-item-file-1');
      const downloadButton = within(fileItem).getByRole('button', { name: /download/i });
      await user.click(downloadButton);

      await waitFor(() => {
        expect(mockFilesApi.downloadFile).toHaveBeenCalledWith('file-1', 'document.pdf');
      });
    });

    it('deletes a file with confirmation', async () => {
      const user = userEvent.setup();

      mockFilesApi.deleteFile.mockResolvedValue();

      // Mock window.confirm
      const confirmSpy = jest.spyOn(window, 'confirm').mockReturnValue(true);

      render(<FileBrowser />);

      await waitFor(() => {
        expect(screen.getByText('document.pdf')).toBeInTheDocument();
      });

      // Find and click delete button
      const fileItem = screen.getByTestId('file-item-file-1');
      const deleteButton = within(fileItem).getByRole('button', { name: /delete/i });
      await user.click(deleteButton);

      await waitFor(() => {
        expect(confirmSpy).toHaveBeenCalled();
        expect(mockFilesApi.deleteFile).toHaveBeenCalledWith('file-1');
      });

      // File list should be refreshed
      await waitFor(() => {
        expect(mockFilesApi.getFiles).toHaveBeenCalled();
      });

      confirmSpy.mockRestore();
    });

    it('cancels file deletion', async () => {
      const user = userEvent.setup();

      // Mock window.confirm to return false
      const confirmSpy = jest.spyOn(window, 'confirm').mockReturnValue(false);

      render(<FileBrowser />);

      await waitFor(() => {
        expect(screen.getByText('document.pdf')).toBeInTheDocument();
      });

      const fileItem = screen.getByTestId('file-item-file-1');
      const deleteButton = within(fileItem).getByRole('button', { name: /delete/i });
      await user.click(deleteButton);

      expect(confirmSpy).toHaveBeenCalled();
      expect(mockFilesApi.deleteFile).not.toHaveBeenCalled();

      confirmSpy.mockRestore();
    });

    it('opens file details modal', async () => {
      const user = userEvent.setup();

      render(<FileBrowser />);

      await waitFor(() => {
        expect(screen.getByText('document.pdf')).toBeInTheDocument();
      });

      // Click on file name to open details
      const fileName = screen.getByText('document.pdf');
      await user.click(fileName);

      await waitFor(() => {
        expect(screen.getByRole('dialog')).toBeInTheDocument();
      });
    });
  });

  describe('Pagination', () => {
    it('navigates to next page', async () => {
      const user = userEvent.setup();

      mockFilesApi.getFiles.mockResolvedValue({
        files: mockFiles,
        pagination: {
          current_page: 1,
          total_pages: 3,
          total_count: 60,
          per_page: 20,
        },
      });

      render(<FileBrowser />);

      await waitFor(() => {
        expect(screen.getByText('document.pdf')).toBeInTheDocument();
      });

      const nextButton = screen.getByLabelText(/next page/i);
      await user.click(nextButton);

      await waitFor(() => {
        expect(mockFilesApi.getFiles).toHaveBeenCalledWith(
          expect.objectContaining({
            page: 2,
          })
        );
      });
    });

    it('navigates to previous page', async () => {
      const user = userEvent.setup();

      mockFilesApi.getFiles.mockResolvedValue({
        files: mockFiles,
        pagination: {
          current_page: 2,
          total_pages: 3,
          total_count: 60,
          per_page: 20,
        },
      });

      render(<FileBrowser />);

      await waitFor(() => {
        expect(screen.getByText('document.pdf')).toBeInTheDocument();
      });

      const prevButton = screen.getByLabelText(/previous page/i);
      await user.click(prevButton);

      await waitFor(() => {
        expect(mockFilesApi.getFiles).toHaveBeenCalledWith(
          expect.objectContaining({
            page: 1,
          })
        );
      });
    });

    it('changes items per page', async () => {
      const user = userEvent.setup();

      render(<FileBrowser />);

      await waitFor(() => {
        expect(screen.getByText('document.pdf')).toBeInTheDocument();
      });

      const perPageSelect = screen.getByLabelText(/items per page/i);
      await user.selectOptions(perPageSelect, '50');

      await waitFor(() => {
        expect(mockFilesApi.getFiles).toHaveBeenCalledWith(
          expect.objectContaining({
            per_page: 50,
            page: 1,
          })
        );
      });
    });
  });

  describe('Sorting', () => {
    it('sorts files by filename', async () => {
      const user = userEvent.setup();

      render(<FileBrowser />);

      await waitFor(() => {
        expect(screen.getByText('document.pdf')).toBeInTheDocument();
      });

      const nameButton = screen.getByLabelText(/name/i);
      await user.click(nameButton);

      await waitFor(() => {
        expect(mockFilesApi.getFiles).toHaveBeenCalledWith(
          expect.objectContaining({
            sort_by: 'filename',
            sort_order: 'asc',
          })
        );
      });

      // Click again for descending order
      await user.click(nameButton);

      await waitFor(() => {
        expect(mockFilesApi.getFiles).toHaveBeenCalledWith(
          expect.objectContaining({
            sort_by: 'filename',
            sort_order: 'desc',
          })
        );
      });
    });

    it('sorts files by size', async () => {
      const user = userEvent.setup();

      render(<FileBrowser />);

      await waitFor(() => {
        expect(screen.getByText('document.pdf')).toBeInTheDocument();
      });

      const sizeButton = screen.getByLabelText(/size/i);
      await user.click(sizeButton);

      await waitFor(() => {
        expect(mockFilesApi.getFiles).toHaveBeenCalledWith(
          expect.objectContaining({
            sort_by: 'file_size',
            sort_order: 'asc',
          })
        );
      });
    });

    it('sorts files by date', async () => {
      const user = userEvent.setup();

      render(<FileBrowser />);

      await waitFor(() => {
        expect(screen.getByText('document.pdf')).toBeInTheDocument();
      });

      // Default sort is by date desc, clicking should toggle to asc
      const dateButton = screen.getByLabelText(/date/i);
      await user.click(dateButton);

      await waitFor(() => {
        expect(mockFilesApi.getFiles).toHaveBeenCalledWith(
          expect.objectContaining({
            sort_by: 'created_at',
            sort_order: 'asc',
          })
        );
      });
    });
  });

  describe('Bulk Actions', () => {
    it('selects multiple files', async () => {
      const user = userEvent.setup();

      render(<FileBrowser />);

      // Wait for files to load and checkboxes to be present
      await waitFor(() => {
        expect(screen.getByText('document.pdf')).toBeInTheDocument();
        expect(screen.getAllByRole('checkbox').length).toBeGreaterThan(1);
      });

      // Find checkboxes for files (excluding select all)
      const checkboxes = screen.getAllByRole('checkbox');

      // Select first two files (skip index 0 which is select all)
      await user.click(checkboxes[1]);

      // Wait for selection state to update
      await waitFor(() => {
        expect(screen.getByText(/1 selected/i)).toBeInTheDocument();
      });

      await user.click(checkboxes[2]);

      // Verify selection count
      await waitFor(() => {
        expect(screen.getByText(/2 selected/i)).toBeInTheDocument();
      });
    });

    it('selects all files', async () => {
      const user = userEvent.setup();

      render(<FileBrowser />);

      // Wait for files to load
      await waitFor(() => {
        expect(screen.getByText('document.pdf')).toBeInTheDocument();
        expect(screen.getByLabelText(/select all/i)).toBeInTheDocument();
      });

      // Find and click "select all" checkbox
      const selectAllCheckbox = screen.getByLabelText(/select all/i);
      await user.click(selectAllCheckbox);

      // All files should be selected
      await waitFor(() => {
        expect(screen.getByText(/3 selected/i)).toBeInTheDocument();
      });
    });

    it('deletes multiple selected files', async () => {
      const user = userEvent.setup();

      mockFilesApi.deleteFile.mockResolvedValue();
      const confirmSpy = jest.spyOn(window, 'confirm').mockReturnValue(true);

      render(<FileBrowser />);

      // Wait for files to load
      await waitFor(() => {
        expect(screen.getByText('document.pdf')).toBeInTheDocument();
        expect(screen.getAllByRole('checkbox').length).toBeGreaterThan(1);
      });

      // Select two files
      const checkboxes = screen.getAllByRole('checkbox');
      await user.click(checkboxes[1]);
      await user.click(checkboxes[2]);

      // Wait for selection and bulk delete button to appear
      await waitFor(() => {
        expect(screen.getByText(/2 selected/i)).toBeInTheDocument();
        expect(screen.getByLabelText(/delete selected/i)).toBeInTheDocument();
      });

      // Click bulk delete button
      const bulkDeleteButton = screen.getByLabelText(/delete selected/i);
      await user.click(bulkDeleteButton);

      await waitFor(() => {
        expect(confirmSpy).toHaveBeenCalled();
        expect(mockFilesApi.deleteFile).toHaveBeenCalledTimes(2);
      });

      confirmSpy.mockRestore();
    });
  });

  describe('Refresh Functionality', () => {
    it('refreshes file list', async () => {
      const user = userEvent.setup();

      render(<FileBrowser />);

      await waitFor(() => {
        expect(screen.getByText('document.pdf')).toBeInTheDocument();
      });

      jest.clearAllMocks();

      const refreshButton = screen.getByLabelText(/refresh/i);
      await user.click(refreshButton);

      await waitFor(() => {
        expect(mockFilesApi.getFiles).toHaveBeenCalled();
      });
    });

    it('refreshes when category prop changes', async () => {
      const { rerender } = render(<FileBrowser />);

      await waitFor(() => {
        expect(mockFilesApi.getFiles).toHaveBeenCalledTimes(1);
      });

      jest.clearAllMocks();

      // Re-render with new category prop to simulate parent triggering refresh
      rerender(<FileBrowser category="workflow_output" />);

      // Should fetch files with new category
      await waitFor(() => {
        expect(mockFilesApi.getFiles).toHaveBeenCalledWith(
          expect.objectContaining({
            category: 'workflow_output',
          })
        );
      });
    });
  });
});

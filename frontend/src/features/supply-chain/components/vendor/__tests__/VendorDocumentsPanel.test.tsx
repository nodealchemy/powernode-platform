import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { VendorDocumentsPanel } from '../VendorDocumentsPanel';
import { supplyChainFilesApi } from '../../../services/supplyChainFilesApi';

// Mock the API
jest.mock('../../../services/supplyChainFilesApi', () => ({
  supplyChainFilesApi: {
    getVendorDocuments: jest.fn(),
    uploadVendorDocument: jest.fn(),
    downloadFile: jest.fn(),
    deleteFile: jest.fn(),
  },
}));

// Mock useNotifications
const mockShowNotification = jest.fn();
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    showNotification: mockShowNotification,
  }),
}));

// Mock lucide-react icons
jest.mock('lucide-react', () => ({
  Upload: () => <span data-testid="icon-upload" />,
  Download: () => <span data-testid="icon-download" />,
  Trash2: () => <span data-testid="icon-trash" />,
  FileText: () => <span data-testid="icon-filetext" />,
  Shield: () => <span data-testid="icon-shield" />,
  Award: () => <span data-testid="icon-award" />,
  File: () => <span data-testid="icon-file" />,
  AlertCircle: () => <span data-testid="icon-alert" />,
}));

// Mock UI components
jest.mock('@/shared/components/ui/Button', () => ({
  Button: ({ children, onClick, disabled, title }: any) => (
    <button onClick={onClick} disabled={disabled} title={title} data-testid={`button-${title?.toLowerCase().replace(/\s/g, '-')}`}>
      {children}
    </button>
  ),
}));

jest.mock('@/shared/components/ui/Badge', () => ({
  Badge: ({ children, variant }: any) => (
    <span data-testid={`badge-${variant}`}>{children}</span>
  ),
}));

jest.mock('@/shared/components/ui/LoadingSpinner', () => ({
  LoadingSpinner: ({ size }: any) => (
    <span data-testid={`spinner-${size}`}>Loading...</span>
  ),
}));

// Mock date-fns
jest.mock('date-fns', () => ({
  formatDistanceToNow: () => '2 days ago',
}));

const mockApi = supplyChainFilesApi as jest.Mocked<typeof supplyChainFilesApi>;

describe('VendorDocumentsPanel', () => {
  const defaultProps = {
    vendorId: 'vendor-123',
    vendorName: 'Test Vendor',
  };

  const mockFiles = [
    {
      id: 'file-1',
      filename: 'compliance-report.pdf',
      storage_key: 'vendors/vendor-123/compliance-report.pdf',
      file_size: 1024000,
      file_type: 'document',
      category: 'vendor_compliance',
      content_type: 'application/pdf',
      visibility: 'private',
      version: 1,
      processing_status: 'completed',
      created_at: '2024-01-15T10:00:00Z',
      updated_at: '2024-01-15T10:00:00Z',
      uploaded_by: { id: 'user-1', name: 'John Doe', email: 'john@test.com' },
    },
    {
      id: 'file-2',
      filename: 'iso-certificate.pdf',
      storage_key: 'vendors/vendor-123/iso-certificate.pdf',
      file_size: 512000,
      file_type: 'document',
      category: 'vendor_certificate',
      content_type: 'application/pdf',
      visibility: 'private',
      version: 1,
      processing_status: 'completed',
      created_at: '2024-01-16T10:00:00Z',
      updated_at: '2024-01-16T10:00:00Z',
      uploaded_by: { id: 'user-1', name: 'John Doe', email: 'john@test.com' },
    },
    {
      id: 'file-3',
      filename: 'risk-assessment.pdf',
      storage_key: 'vendors/vendor-123/risk-assessment.pdf',
      file_size: 256000,
      file_type: 'document',
      category: 'vendor_assessment',
      content_type: 'application/pdf',
      visibility: 'private',
      version: 1,
      processing_status: 'completed',
      created_at: '2024-01-17T10:00:00Z',
      updated_at: '2024-01-17T10:00:00Z',
    },
  ];

  beforeEach(() => {
    jest.clearAllMocks();
    mockApi.getVendorDocuments.mockResolvedValue({ files: mockFiles });
  });

  describe('rendering', () => {
    it('renders loading state initially', () => {
      mockApi.getVendorDocuments.mockImplementation(() => new Promise(() => {}));
      render(<VendorDocumentsPanel {...defaultProps} />);

      expect(screen.getByTestId('spinner-lg')).toBeInTheDocument();
    });

    it('renders empty state when no files', async () => {
      mockApi.getVendorDocuments.mockResolvedValue({ files: [] });
      render(<VendorDocumentsPanel {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('No documents uploaded')).toBeInTheDocument();
      });

      expect(screen.getByText(/Upload compliance documents/)).toBeInTheDocument();
    });

    it('renders document list when files exist', async () => {
      render(<VendorDocumentsPanel {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('compliance-report.pdf')).toBeInTheDocument();
      });

      expect(screen.getByText('iso-certificate.pdf')).toBeInTheDocument();
      expect(screen.getByText('risk-assessment.pdf')).toBeInTheDocument();
    });

    it('renders filter buttons', async () => {
      render(<VendorDocumentsPanel {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('All')).toBeInTheDocument();
      });

      // These texts appear in both filter and upload buttons, so use getAllByText
      expect(screen.getAllByText('Compliance').length).toBeGreaterThanOrEqual(1);
      expect(screen.getAllByText('Assessment').length).toBeGreaterThanOrEqual(1);
      expect(screen.getAllByText('Certificate').length).toBeGreaterThanOrEqual(1);
    });

    it('renders upload buttons for each category', async () => {
      render(<VendorDocumentsPanel {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByTestId('button-upload-compliance')).toBeInTheDocument();
      });

      expect(screen.getByTestId('button-upload-assessment')).toBeInTheDocument();
      expect(screen.getByTestId('button-upload-certificate')).toBeInTheDocument();
    });

    it('renders info box with document types description', async () => {
      render(<VendorDocumentsPanel {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Document Types')).toBeInTheDocument();
      });

      expect(screen.getByText(/SOC 2 reports/)).toBeInTheDocument();
      expect(screen.getByText(/Risk assessments/)).toBeInTheDocument();
      expect(screen.getByText(/ISO 27001/)).toBeInTheDocument();
    });

    it('displays file size correctly', async () => {
      render(<VendorDocumentsPanel {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('1000.0 KB')).toBeInTheDocument();
      });

      expect(screen.getByText('500.0 KB')).toBeInTheDocument();
      expect(screen.getByText('250.0 KB')).toBeInTheDocument();
    });

    it('displays uploader name when available', async () => {
      render(<VendorDocumentsPanel {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getAllByText('by John Doe')).toHaveLength(2);
      });
    });

    it('displays category badges', async () => {
      render(<VendorDocumentsPanel {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByTestId('badge-info')).toBeInTheDocument(); // Compliance
      });

      expect(screen.getByTestId('badge-success')).toBeInTheDocument(); // Certificate
      expect(screen.getByTestId('badge-warning')).toBeInTheDocument(); // Assessment
    });
  });

  describe('filtering', () => {
    it('fetches all documents initially', async () => {
      render(<VendorDocumentsPanel {...defaultProps} />);

      await waitFor(() => {
        expect(mockApi.getVendorDocuments).toHaveBeenCalledWith('vendor-123', undefined);
      });
    });

    it('filters by compliance category', async () => {
      render(<VendorDocumentsPanel {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('All')).toBeInTheDocument();
      });

      // Find and click the filter button (not upload button)
      const filterButtons = screen.getAllByText('Compliance');
      const filterButton = filterButtons.find(btn =>
        !btn.closest('button')?.hasAttribute('title')
      );

      if (filterButton) {
        await userEvent.click(filterButton);
      }

      await waitFor(() => {
        expect(mockApi.getVendorDocuments).toHaveBeenCalledWith('vendor-123', 'vendor_compliance');
      });
    });

    it('filters by assessment category', async () => {
      render(<VendorDocumentsPanel {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('All')).toBeInTheDocument();
      });

      const filterButtons = screen.getAllByText('Assessment');
      const filterButton = filterButtons.find(btn =>
        !btn.closest('button')?.hasAttribute('title')
      );

      if (filterButton) {
        await userEvent.click(filterButton);
      }

      await waitFor(() => {
        expect(mockApi.getVendorDocuments).toHaveBeenCalledWith('vendor-123', 'vendor_assessment');
      });
    });

    it('resets filter when All is clicked', async () => {
      render(<VendorDocumentsPanel {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('All')).toBeInTheDocument();
      });

      // First filter by compliance
      const complianceButtons = screen.getAllByText('Compliance');
      const filterButton = complianceButtons.find(btn =>
        !btn.closest('button')?.hasAttribute('title')
      );
      if (filterButton) {
        await userEvent.click(filterButton);
      }

      // Then click All
      await userEvent.click(screen.getByText('All'));

      await waitFor(() => {
        const calls = mockApi.getVendorDocuments.mock.calls;
        const lastCall = calls[calls.length - 1];
        expect(lastCall[1]).toBeUndefined();
      });
    });
  });

  describe('file upload', () => {
    it('triggers file input when upload button is clicked', async () => {
      render(<VendorDocumentsPanel {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByTestId('button-upload-compliance')).toBeInTheDocument();
      });

      const uploadButton = screen.getByTestId('button-upload-compliance');
      await userEvent.click(uploadButton);

      // The hidden file input should be present
      const fileInput = document.querySelector('input[type="file"]');
      expect(fileInput).toBeInTheDocument();
    });

    it('uploads file and shows success notification', async () => {
      mockApi.uploadVendorDocument.mockResolvedValue({
        id: 'file-new',
        filename: 'new-doc.pdf',
        storage_key: 'vendors/vendor-123/new-doc.pdf',
        file_size: 1024,
        file_type: 'document',
        category: 'vendor_compliance',
        content_type: 'application/pdf',
        visibility: 'private',
        version: 1,
        processing_status: 'completed',
        created_at: '2024-01-20T10:00:00Z',
        updated_at: '2024-01-20T10:00:00Z',
      });

      render(<VendorDocumentsPanel {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByTestId('button-upload-compliance')).toBeInTheDocument();
      });

      // Click upload button to set category
      const uploadButton = screen.getByTestId('button-upload-compliance');
      await userEvent.click(uploadButton);

      // Simulate file selection
      const fileInput = document.querySelector('input[type="file"]') as HTMLInputElement;
      const testFile = new File(['test content'], 'new-doc.pdf', { type: 'application/pdf' });

      // Set the data attribute manually since the click handler sets it
      fileInput.dataset.category = 'vendor_compliance';

      fireEvent.change(fileInput, { target: { files: [testFile] } });

      await waitFor(() => {
        expect(mockApi.uploadVendorDocument).toHaveBeenCalledWith(
          'vendor-123',
          testFile,
          'vendor_compliance',
          expect.objectContaining({
            description: 'Compliance document for Test Vendor',
          })
        );
      });

      expect(mockShowNotification).toHaveBeenCalledWith('Document uploaded successfully', 'success');
    });

    it('shows error notification on upload failure', async () => {
      mockApi.uploadVendorDocument.mockRejectedValue(new Error('Upload failed'));

      render(<VendorDocumentsPanel {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByTestId('button-upload-compliance')).toBeInTheDocument();
      });

      const uploadButton = screen.getByTestId('button-upload-compliance');
      await userEvent.click(uploadButton);

      const fileInput = document.querySelector('input[type="file"]') as HTMLInputElement;
      const testFile = new File(['test'], 'test.pdf', { type: 'application/pdf' });
      fileInput.dataset.category = 'vendor_compliance';

      fireEvent.change(fileInput, { target: { files: [testFile] } });

      await waitFor(() => {
        expect(mockShowNotification).toHaveBeenCalledWith('Failed to upload document', 'error');
      });
    });

    it('disables upload buttons while uploading', async () => {
      mockApi.uploadVendorDocument.mockImplementation(
        () => new Promise((resolve) => setTimeout(resolve, 1000))
      );

      render(<VendorDocumentsPanel {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByTestId('button-upload-compliance')).toBeInTheDocument();
      });

      const uploadButton = screen.getByTestId('button-upload-compliance');
      await userEvent.click(uploadButton);

      const fileInput = document.querySelector('input[type="file"]') as HTMLInputElement;
      const testFile = new File(['test'], 'test.pdf', { type: 'application/pdf' });
      fileInput.dataset.category = 'vendor_compliance';

      fireEvent.change(fileInput, { target: { files: [testFile] } });

      await waitFor(() => {
        expect(screen.getByTestId('button-upload-compliance')).toBeDisabled();
        expect(screen.getByTestId('button-upload-assessment')).toBeDisabled();
        expect(screen.getByTestId('button-upload-certificate')).toBeDisabled();
      });
    });

    it('shows upload progress indicator', async () => {
      mockApi.uploadVendorDocument.mockImplementation(
        (_vendorId, _file, _category, options) => {
          if (options?.onProgress) {
            options.onProgress({ loaded: 50, total: 100, percentage: 50 });
          }
          return new Promise((resolve) => setTimeout(() => resolve({
            id: 'file-new',
            filename: 'test.pdf',
            storage_key: 'vendors/vendor-123/test.pdf',
            file_size: 1024,
            file_type: 'document',
            category: 'vendor_compliance',
            content_type: 'application/pdf',
            visibility: 'private',
            version: 1,
            processing_status: 'completed',
            created_at: '2024-01-20T10:00:00Z',
            updated_at: '2024-01-20T10:00:00Z',
          }), 100));
        }
      );

      render(<VendorDocumentsPanel {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByTestId('button-upload-compliance')).toBeInTheDocument();
      });

      const uploadButton = screen.getByTestId('button-upload-compliance');
      await userEvent.click(uploadButton);

      const fileInput = document.querySelector('input[type="file"]') as HTMLInputElement;
      const testFile = new File(['test'], 'test.pdf', { type: 'application/pdf' });
      fileInput.dataset.category = 'vendor_compliance';

      fireEvent.change(fileInput, { target: { files: [testFile] } });

      await waitFor(() => {
        expect(screen.getByText('Uploading document...')).toBeInTheDocument();
      });
    });
  });

  describe('file download', () => {
    it('downloads file when download button is clicked', async () => {
      mockApi.downloadFile.mockResolvedValue(undefined);

      render(<VendorDocumentsPanel {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('compliance-report.pdf')).toBeInTheDocument();
      });

      const downloadButtons = screen.getAllByTitle('Download');
      await userEvent.click(downloadButtons[0]);

      expect(mockApi.downloadFile).toHaveBeenCalledWith('file-1', 'compliance-report.pdf');
    });

    it('shows error notification on download failure', async () => {
      mockApi.downloadFile.mockRejectedValue(new Error('Download failed'));

      render(<VendorDocumentsPanel {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('compliance-report.pdf')).toBeInTheDocument();
      });

      const downloadButtons = screen.getAllByTitle('Download');
      await userEvent.click(downloadButtons[0]);

      await waitFor(() => {
        expect(mockShowNotification).toHaveBeenCalledWith('Failed to download file', 'error');
      });
    });
  });

  describe('file deletion', () => {
    it('deletes file when delete button is clicked', async () => {
      mockApi.deleteFile.mockResolvedValue(undefined);

      render(<VendorDocumentsPanel {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('compliance-report.pdf')).toBeInTheDocument();
      });

      const deleteButtons = screen.getAllByTitle('Delete');
      await userEvent.click(deleteButtons[0]);

      await waitFor(() => {
        expect(mockApi.deleteFile).toHaveBeenCalledWith('file-1');
      });

      expect(mockShowNotification).toHaveBeenCalledWith('Document deleted successfully', 'success');
    });

    it('shows error notification on delete failure', async () => {
      mockApi.deleteFile.mockRejectedValue(new Error('Delete failed'));

      render(<VendorDocumentsPanel {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('compliance-report.pdf')).toBeInTheDocument();
      });

      const deleteButtons = screen.getAllByTitle('Delete');
      await userEvent.click(deleteButtons[0]);

      await waitFor(() => {
        expect(mockShowNotification).toHaveBeenCalledWith('Failed to delete document', 'error');
      });
    });

    it('disables delete button while deleting', async () => {
      mockApi.deleteFile.mockImplementation(
        () => new Promise((resolve) => setTimeout(resolve, 1000))
      );

      render(<VendorDocumentsPanel {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('compliance-report.pdf')).toBeInTheDocument();
      });

      const deleteButtons = screen.getAllByTitle('Delete');
      await userEvent.click(deleteButtons[0]);

      await waitFor(() => {
        expect(deleteButtons[0]).toBeDisabled();
      });
    });

    it('refreshes file list after successful deletion', async () => {
      mockApi.deleteFile.mockResolvedValue(undefined);

      render(<VendorDocumentsPanel {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('compliance-report.pdf')).toBeInTheDocument();
      });

      // Clear mock call count
      mockApi.getVendorDocuments.mockClear();

      const deleteButtons = screen.getAllByTitle('Delete');
      await userEvent.click(deleteButtons[0]);

      await waitFor(() => {
        expect(mockApi.getVendorDocuments).toHaveBeenCalled();
      });
    });
  });

  describe('error handling', () => {
    it('shows error notification when loading fails', async () => {
      mockApi.getVendorDocuments.mockRejectedValue(new Error('Failed to load'));

      render(<VendorDocumentsPanel {...defaultProps} />);

      await waitFor(() => {
        expect(mockShowNotification).toHaveBeenCalledWith('Failed to load documents', 'error');
      });
    });

    it('shows empty state on load error', async () => {
      mockApi.getVendorDocuments.mockRejectedValue(new Error('Failed to load'));

      render(<VendorDocumentsPanel {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('No documents uploaded')).toBeInTheDocument();
      });
    });
  });

  describe('file category handling', () => {
    it('handles files with unknown category', async () => {
      mockApi.getVendorDocuments.mockResolvedValue({
        files: [
          {
            id: 'file-unknown',
            filename: 'unknown.pdf',
            storage_key: 'vendors/vendor-123/unknown.pdf',
            file_size: 1024,
            file_type: 'document',
            category: 'unknown_category',
            content_type: 'application/pdf',
            visibility: 'private',
            version: 1,
            processing_status: 'completed',
            created_at: '2024-01-15T10:00:00Z',
            updated_at: '2024-01-15T10:00:00Z',
          },
        ],
      });

      render(<VendorDocumentsPanel {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('unknown.pdf')).toBeInTheDocument();
      });

      // Should render with default file icon
      expect(screen.getByTestId('icon-file')).toBeInTheDocument();
    });

    it('handles files without category', async () => {
      mockApi.getVendorDocuments.mockResolvedValue({
        files: [
          {
            id: 'file-no-category',
            filename: 'no-category.pdf',
            storage_key: 'vendors/vendor-123/no-category.pdf',
            file_size: 1024,
            file_type: 'document',
            category: '',
            content_type: 'application/pdf',
            visibility: 'private',
            version: 1,
            processing_status: 'completed',
            created_at: '2024-01-15T10:00:00Z',
            updated_at: '2024-01-15T10:00:00Z',
          },
        ],
      });

      render(<VendorDocumentsPanel {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('no-category.pdf')).toBeInTheDocument();
      });
    });
  });

  describe('file size formatting', () => {
    it('formats bytes correctly', async () => {
      mockApi.getVendorDocuments.mockResolvedValue({
        files: [
          { id: 'f1', filename: 'tiny.txt', storage_key: 'f1.txt', file_size: 500, file_type: 'document', category: 'vendor_compliance', content_type: 'text/plain', visibility: 'private', version: 1, processing_status: 'completed', created_at: '2024-01-15T10:00:00Z', updated_at: '2024-01-15T10:00:00Z' },
        ],
      });

      render(<VendorDocumentsPanel {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('500 B')).toBeInTheDocument();
      });
    });

    it('formats kilobytes correctly', async () => {
      mockApi.getVendorDocuments.mockResolvedValue({
        files: [
          { id: 'f1', filename: 'small.pdf', storage_key: 'f1.pdf', file_size: 5120, file_type: 'document', category: 'vendor_compliance', content_type: 'application/pdf', visibility: 'private', version: 1, processing_status: 'completed', created_at: '2024-01-15T10:00:00Z', updated_at: '2024-01-15T10:00:00Z' },
        ],
      });

      render(<VendorDocumentsPanel {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('5.0 KB')).toBeInTheDocument();
      });
    });

    it('formats megabytes correctly', async () => {
      mockApi.getVendorDocuments.mockResolvedValue({
        files: [
          { id: 'f1', filename: 'large.pdf', storage_key: 'f1.pdf', file_size: 5242880, file_type: 'document', category: 'vendor_compliance', content_type: 'application/pdf', visibility: 'private', version: 1, processing_status: 'completed', created_at: '2024-01-15T10:00:00Z', updated_at: '2024-01-15T10:00:00Z' },
        ],
      });

      render(<VendorDocumentsPanel {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('5.0 MB')).toBeInTheDocument();
      });
    });
  });
});

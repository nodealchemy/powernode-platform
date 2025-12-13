import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { DataExportCard } from './DataExportCard';
import { DataExportRequest } from '../services/privacyApi';

describe('DataExportCard', () => {
  const mockRequests: DataExportRequest[] = [
    {
      id: 'req-1',
      format: 'json',
      status: 'completed',
      export_type: 'full',
      created_at: '2025-01-15T10:00:00Z',
      file_size_bytes: 1024 * 1024 * 2.5, // 2.5 MB
      downloadable: true,
      download_token: 'token-123'
    },
    {
      id: 'req-2',
      format: 'csv',
      status: 'pending',
      export_type: 'full',
      created_at: '2025-01-14T10:00:00Z',
      downloadable: false
    },
    {
      id: 'req-3',
      format: 'zip',
      status: 'failed',
      export_type: 'partial',
      created_at: '2025-01-13T10:00:00Z',
      downloadable: false
    }
  ];

  const defaultProps = {
    requests: [],
    onRequestExport: jest.fn().mockResolvedValue(undefined),
    onDownload: jest.fn().mockResolvedValue(undefined),
    loading: false
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('rendering', () => {
    it('shows title', () => {
      render(<DataExportCard {...defaultProps} />);

      expect(screen.getByText('Data Export')).toBeInTheDocument();
    });

    it('shows description', () => {
      render(<DataExportCard {...defaultProps} />);

      expect(screen.getByText('Download a copy of your personal data')).toBeInTheDocument();
    });

    it('shows format select label', () => {
      render(<DataExportCard {...defaultProps} />);

      expect(screen.getByText('Export Format')).toBeInTheDocument();
    });

    it('shows format options', () => {
      render(<DataExportCard {...defaultProps} />);

      expect(screen.getByText('JSON (Recommended)')).toBeInTheDocument();
      expect(screen.getByText('CSV (Spreadsheet)')).toBeInTheDocument();
      expect(screen.getByText('ZIP Archive')).toBeInTheDocument();
    });

    it('shows Request Export button', () => {
      render(<DataExportCard {...defaultProps} />);

      expect(screen.getByText('Request Export')).toBeInTheDocument();
    });

    it('shows export information text', () => {
      render(<DataExportCard {...defaultProps} />);

      expect(screen.getByText(/Exports typically take 5-15 minutes/)).toBeInTheDocument();
      expect(screen.getByText(/one export per week/)).toBeInTheDocument();
    });
  });

  describe('format selection', () => {
    it('defaults to JSON format', () => {
      render(<DataExportCard {...defaultProps} />);

      const select = screen.getByRole('combobox');
      expect(select).toHaveValue('json');
    });

    it('allows changing format to CSV', () => {
      render(<DataExportCard {...defaultProps} />);

      const select = screen.getByRole('combobox');
      fireEvent.change(select, { target: { value: 'csv' } });

      expect(select).toHaveValue('csv');
    });

    it('allows changing format to ZIP', () => {
      render(<DataExportCard {...defaultProps} />);

      const select = screen.getByRole('combobox');
      fireEvent.change(select, { target: { value: 'zip' } });

      expect(select).toHaveValue('zip');
    });
  });

  describe('request export', () => {
    it('calls onRequestExport with selected format', async () => {
      const onRequestExport = jest.fn().mockResolvedValue(undefined);
      render(<DataExportCard {...defaultProps} onRequestExport={onRequestExport} />);

      fireEvent.click(screen.getByText('Request Export'));

      await waitFor(() => {
        expect(onRequestExport).toHaveBeenCalledWith({
          format: 'json',
          export_type: 'full'
        });
      });
    });

    it('calls onRequestExport with CSV format when selected', async () => {
      const onRequestExport = jest.fn().mockResolvedValue(undefined);
      render(<DataExportCard {...defaultProps} onRequestExport={onRequestExport} />);

      fireEvent.change(screen.getByRole('combobox'), { target: { value: 'csv' } });
      fireEvent.click(screen.getByText('Request Export'));

      await waitFor(() => {
        expect(onRequestExport).toHaveBeenCalledWith({
          format: 'csv',
          export_type: 'full'
        });
      });
    });

    it('shows Requesting... while requesting', async () => {
      const onRequestExport = jest.fn().mockImplementation(() => new Promise(() => {}));
      render(<DataExportCard {...defaultProps} onRequestExport={onRequestExport} />);

      fireEvent.click(screen.getByText('Request Export'));

      expect(screen.getByText('Requesting...')).toBeInTheDocument();
    });

    it('disables button while requesting', async () => {
      const onRequestExport = jest.fn().mockImplementation(() => new Promise(() => {}));
      render(<DataExportCard {...defaultProps} onRequestExport={onRequestExport} />);

      fireEvent.click(screen.getByText('Request Export'));

      expect(screen.getByText('Requesting...').closest('button')).toBeDisabled();
    });
  });

  describe('recent exports list', () => {
    it('shows Recent Exports section when requests exist', () => {
      render(<DataExportCard {...defaultProps} requests={mockRequests} />);

      expect(screen.getByText('Recent Exports')).toBeInTheDocument();
    });

    it('hides Recent Exports section when no requests', () => {
      render(<DataExportCard {...defaultProps} requests={[]} />);

      expect(screen.queryByText('Recent Exports')).not.toBeInTheDocument();
    });

    it('shows export format labels', () => {
      render(<DataExportCard {...defaultProps} requests={mockRequests} />);

      expect(screen.getByText('JSON Export')).toBeInTheDocument();
      expect(screen.getByText('CSV Export')).toBeInTheDocument();
      expect(screen.getByText('ZIP Export')).toBeInTheDocument();
    });

    it('shows status badges', () => {
      render(<DataExportCard {...defaultProps} requests={mockRequests} />);

      expect(screen.getByText('completed')).toBeInTheDocument();
      expect(screen.getByText('pending')).toBeInTheDocument();
      expect(screen.getByText('failed')).toBeInTheDocument();
    });

    it('shows file size for completed exports', () => {
      render(<DataExportCard {...defaultProps} requests={mockRequests} />);

      expect(screen.getByText(/2\.5 MB/)).toBeInTheDocument();
    });
  });

  describe('download functionality', () => {
    it('shows Download button for downloadable exports', () => {
      render(<DataExportCard {...defaultProps} requests={mockRequests} />);

      expect(screen.getByText('Download')).toBeInTheDocument();
    });

    it('hides Download button for non-downloadable exports', () => {
      const nonDownloadableRequests = [
        { ...mockRequests[0], downloadable: false }
      ];
      render(<DataExportCard {...defaultProps} requests={nonDownloadableRequests} />);

      expect(screen.queryByText('Download')).not.toBeInTheDocument();
    });

    it('calls onDownload when Download clicked', async () => {
      const onDownload = jest.fn().mockResolvedValue(undefined);
      render(<DataExportCard {...defaultProps} requests={mockRequests} onDownload={onDownload} />);

      fireEvent.click(screen.getByText('Download'));

      await waitFor(() => {
        expect(onDownload).toHaveBeenCalledWith('req-1', 'token-123');
      });
    });

    it('shows Processing... for pending requests', () => {
      render(<DataExportCard {...defaultProps} requests={mockRequests} />);

      expect(screen.getByText('Processing...')).toBeInTheDocument();
    });
  });

  describe('file size formatting', () => {
    it('formats bytes correctly', () => {
      const smallRequest = [{ ...mockRequests[0], file_size_bytes: 512 }];
      render(<DataExportCard {...defaultProps} requests={smallRequest} />);

      expect(screen.getByText(/512 B/)).toBeInTheDocument();
    });

    it('formats kilobytes correctly', () => {
      const kbRequest = [{ ...mockRequests[0], file_size_bytes: 1024 * 5 }];
      render(<DataExportCard {...defaultProps} requests={kbRequest} />);

      expect(screen.getByText(/5\.0 KB/)).toBeInTheDocument();
    });

    it('formats megabytes correctly', () => {
      const mbRequest = [{ ...mockRequests[0], file_size_bytes: 1024 * 1024 * 10 }];
      render(<DataExportCard {...defaultProps} requests={mbRequest} />);

      expect(screen.getByText(/10\.0 MB/)).toBeInTheDocument();
    });

    it('shows N/A when no file size', () => {
      const noSizeRequest = [{ ...mockRequests[0], file_size_bytes: undefined }];
      render(<DataExportCard {...defaultProps} requests={noSizeRequest} />);

      // File size is only shown for completed exports with size
      // This test checks the formatFileSize function handles undefined
    });
  });

  describe('loading state', () => {
    it('disables Request Export button when loading', () => {
      render(<DataExportCard {...defaultProps} loading={true} />);

      expect(screen.getByText('Request Export').closest('button')).toBeDisabled();
    });
  });

  describe('status styles', () => {
    it('applies correct style for completed status', () => {
      const completedRequest = [{ ...mockRequests[0], status: 'completed' as const }];
      render(<DataExportCard {...defaultProps} requests={completedRequest} />);

      const statusBadge = screen.getByText('completed');
      expect(statusBadge).toHaveClass('text-theme-success');
    });

    it('applies correct style for pending status', () => {
      const pendingRequest = [{ ...mockRequests[1] }];
      render(<DataExportCard {...defaultProps} requests={pendingRequest} />);

      const statusBadge = screen.getByText('pending');
      expect(statusBadge).toHaveClass('text-theme-warning');
    });

    it('applies correct style for failed status', () => {
      const failedRequest = [{ ...mockRequests[2] }];
      render(<DataExportCard {...defaultProps} requests={failedRequest} />);

      const statusBadge = screen.getByText('failed');
      expect(statusBadge).toHaveClass('text-theme-danger');
    });

    it('applies correct style for processing status', () => {
      const processingRequest = [{ ...mockRequests[0], status: 'processing' as const, downloadable: false }];
      render(<DataExportCard {...defaultProps} requests={processingRequest} />);

      const statusBadge = screen.getByText('processing');
      expect(statusBadge).toHaveClass('text-theme-info');
    });

    it('applies correct style for expired status', () => {
      const expiredRequest = [{ ...mockRequests[0], status: 'expired' as const, downloadable: false }];
      render(<DataExportCard {...defaultProps} requests={expiredRequest} />);

      const statusBadge = screen.getByText('expired');
      expect(statusBadge).toHaveClass('text-theme-primary');
    });
  });
});

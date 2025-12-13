import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { AuditLogExport } from './AuditLogExport';

// Mock auditLogsApi
jest.mock('@/features/audit-logs/services/auditLogsApi', () => ({
  auditLogsApi: {
    exportLogs: jest.fn().mockResolvedValue({
      success: true,
      data: {
        content: 'mock,csv,content',
        filename: 'audit-logs.csv',
        format: 'csv',
        record_count: 100
      }
    })
  }
}));

// Mock useNotifications
const mockShowNotification = jest.fn();
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    showNotification: mockShowNotification
  })
}));

// Mock URL.createObjectURL and revokeObjectURL for JSDOM environment
const mockCreateObjectURL = jest.fn(() => 'blob:mock-url');
const mockRevokeObjectURL = jest.fn();
global.URL.createObjectURL = mockCreateObjectURL;
global.URL.revokeObjectURL = mockRevokeObjectURL;

describe('AuditLogExport', () => {
  const mockFilters = {
    search: '',
    action: '',
    resource_type: '',
    level: '',
    status: '',
    source: '',
    user_id: '',
    account_id: '',
    date_from: '',
    date_to: ''
  };

  const defaultProps = {
    filters: mockFilters,
    onClose: jest.fn()
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('header', () => {
    it('shows Export Audit Logs title', () => {
      render(<AuditLogExport {...defaultProps} />);

      expect(screen.getByText('Export Audit Logs')).toBeInTheDocument();
    });

    it('shows description text', () => {
      render(<AuditLogExport {...defaultProps} />);

      expect(screen.getByText('Configure and download audit log data')).toBeInTheDocument();
    });

    it('shows close button', () => {
      const { container } = render(<AuditLogExport {...defaultProps} />);

      expect(container.querySelector('.lucide-x')).toBeInTheDocument();
    });

    it('calls onClose when close button clicked', () => {
      const onClose = jest.fn();
      const { container } = render(<AuditLogExport {...defaultProps} onClose={onClose} />);

      const closeButton = container.querySelector('.lucide-x')?.closest('button');
      if (closeButton) {
        fireEvent.click(closeButton);
      }

      expect(onClose).toHaveBeenCalled();
    });
  });

  describe('format options', () => {
    it('shows Export Format label', () => {
      render(<AuditLogExport {...defaultProps} />);

      expect(screen.getByText('Export Format')).toBeInTheDocument();
    });

    it('shows CSV option', () => {
      render(<AuditLogExport {...defaultProps} />);

      expect(screen.getByText('CSV')).toBeInTheDocument();
      expect(screen.getByText('Comma-separated values for spreadsheet applications')).toBeInTheDocument();
    });

    it('shows JSON option', () => {
      render(<AuditLogExport {...defaultProps} />);

      expect(screen.getByText('JSON')).toBeInTheDocument();
      expect(screen.getByText('JavaScript Object Notation for programmatic access')).toBeInTheDocument();
    });

    it('shows PDF option', () => {
      render(<AuditLogExport {...defaultProps} />);

      expect(screen.getByText('PDF')).toBeInTheDocument();
      expect(screen.getByText('Portable Document Format for reports and archival')).toBeInTheDocument();
    });

    it('selects CSV by default', () => {
      render(<AuditLogExport {...defaultProps} />);

      const csvButton = screen.getByText('CSV').closest('button');
      expect(csvButton).toHaveClass('border-theme-interactive-primary');
    });

    it('updates selection when format clicked', () => {
      render(<AuditLogExport {...defaultProps} />);

      const jsonButton = screen.getByText('JSON').closest('button');
      if (jsonButton) {
        fireEvent.click(jsonButton);
      }

      expect(jsonButton).toHaveClass('border-theme-interactive-primary');
    });
  });

  describe('scope options', () => {
    it('shows Export Scope label', () => {
      render(<AuditLogExport {...defaultProps} />);

      expect(screen.getByText('Export Scope')).toBeInTheDocument();
    });

    it('shows Current Page option', () => {
      render(<AuditLogExport {...defaultProps} />);

      expect(screen.getByText('Current Page')).toBeInTheDocument();
      expect(screen.getByText('Export only the currently displayed audit logs')).toBeInTheDocument();
    });

    it('shows All Filtered Results option', () => {
      render(<AuditLogExport {...defaultProps} />);

      expect(screen.getByText('All Filtered Results')).toBeInTheDocument();
      expect(screen.getByText('Export all audit logs matching current filters')).toBeInTheDocument();
    });

    it('shows All Audit Logs option', () => {
      render(<AuditLogExport {...defaultProps} />);

      expect(screen.getByText('All Audit Logs')).toBeInTheDocument();
      expect(screen.getByText('Export complete audit log history (use with caution)')).toBeInTheDocument();
    });

    it('selects filtered by default', () => {
      render(<AuditLogExport {...defaultProps} />);

      const filteredRadio = screen.getByDisplayValue('filtered');
      expect(filteredRadio).toBeChecked();
    });

    it('updates scope when radio clicked', () => {
      render(<AuditLogExport {...defaultProps} />);

      const allRadio = screen.getByDisplayValue('all');
      fireEvent.click(allRadio);

      expect(allRadio).toBeChecked();
    });
  });

  describe('additional options', () => {
    it('shows Additional Options label', () => {
      render(<AuditLogExport {...defaultProps} />);

      expect(screen.getByText('Additional Options')).toBeInTheDocument();
    });

    it('shows Include metadata checkbox', () => {
      render(<AuditLogExport {...defaultProps} />);

      expect(screen.getByText('Include metadata fields')).toBeInTheDocument();
    });

    it('has Include metadata checked by default', () => {
      render(<AuditLogExport {...defaultProps} />);

      const checkbox = screen.getByLabelText('Include metadata fields');
      expect(checkbox).toBeChecked();
    });

    it('shows Include sensitive data checkbox', () => {
      render(<AuditLogExport {...defaultProps} />);

      expect(screen.getByText('Include sensitive data')).toBeInTheDocument();
    });

    it('has Include sensitive data unchecked by default', () => {
      render(<AuditLogExport {...defaultProps} />);

      const checkbox = screen.getByLabelText('Include sensitive data');
      expect(checkbox).not.toBeChecked();
    });

    it('toggles checkboxes when clicked', () => {
      render(<AuditLogExport {...defaultProps} />);

      const metadataCheckbox = screen.getByLabelText('Include metadata fields');
      fireEvent.click(metadataCheckbox);

      expect(metadataCheckbox).not.toBeChecked();
    });
  });

  describe('record limit', () => {
    it('shows Record Limit label', () => {
      render(<AuditLogExport {...defaultProps} />);

      expect(screen.getByText('Record Limit')).toBeInTheDocument();
    });

    it('shows record limit options', () => {
      render(<AuditLogExport {...defaultProps} />);

      const select = screen.getByRole('combobox');
      expect(select).toBeInTheDocument();

      // Check options
      expect(screen.getByText('1,000 records')).toBeInTheDocument();
      expect(screen.getByText('5,000 records')).toBeInTheDocument();
      expect(screen.getByText('10,000 records')).toBeInTheDocument();
      expect(screen.getByText('50,000 records')).toBeInTheDocument();
      expect(screen.getByText('No limit')).toBeInTheDocument();
    });

    it('has 10000 selected by default', () => {
      render(<AuditLogExport {...defaultProps} />);

      const select = screen.getByRole('combobox');
      expect(select).toHaveValue('10000');
    });
  });

  describe('custom date range', () => {
    it('shows custom date range checkbox', () => {
      render(<AuditLogExport {...defaultProps} />);

      expect(screen.getByText('Use custom date range')).toBeInTheDocument();
    });

    it('hides date inputs by default', () => {
      render(<AuditLogExport {...defaultProps} />);

      expect(screen.queryByText('Start Date')).not.toBeInTheDocument();
      expect(screen.queryByText('End Date')).not.toBeInTheDocument();
    });

    it('shows date inputs when checkbox enabled', () => {
      render(<AuditLogExport {...defaultProps} />);

      const checkbox = screen.getByLabelText('Use custom date range');
      fireEvent.click(checkbox);

      expect(screen.getByText('Start Date')).toBeInTheDocument();
      expect(screen.getByText('End Date')).toBeInTheDocument();
    });
  });

  describe('estimated records', () => {
    it('shows estimated records for current page scope', () => {
      render(<AuditLogExport {...defaultProps} />);

      // Select current page scope
      const currentRadio = screen.getByDisplayValue('current');
      fireEvent.click(currentRadio);

      expect(screen.getByText('Estimated 25 records to export')).toBeInTheDocument();
    });

    it('shows estimated records for filtered scope', () => {
      render(<AuditLogExport {...defaultProps} />);

      expect(screen.getByText('Estimated 1,250 records to export')).toBeInTheDocument();
    });

    it('shows estimated records for all scope', () => {
      render(<AuditLogExport {...defaultProps} />);

      const allRadio = screen.getByDisplayValue('all');
      fireEvent.click(allRadio);

      expect(screen.getByText('Estimated 15,750 records to export')).toBeInTheDocument();
    });
  });

  describe('footer buttons', () => {
    it('shows Cancel button', () => {
      render(<AuditLogExport {...defaultProps} />);

      expect(screen.getByText('Cancel')).toBeInTheDocument();
    });

    it('shows Start Export button', () => {
      render(<AuditLogExport {...defaultProps} />);

      expect(screen.getByText('Start Export')).toBeInTheDocument();
    });

    it('calls onClose when Cancel clicked', () => {
      const onClose = jest.fn();
      render(<AuditLogExport {...defaultProps} onClose={onClose} />);

      fireEvent.click(screen.getByText('Cancel'));

      expect(onClose).toHaveBeenCalled();
    });
  });

  describe('export functionality', () => {
    it('shows exporting state when export started', async () => {
      const { auditLogsApi } = require('@/features/audit-logs/services/auditLogsApi');
      auditLogsApi.exportLogs.mockImplementation(() => new Promise(() => {})); // Never resolves

      render(<AuditLogExport {...defaultProps} />);

      fireEvent.click(screen.getByText('Start Export'));

      await waitFor(() => {
        expect(screen.getByText('Exporting...')).toBeInTheDocument();
      });
    });

    it('shows progress bar during export', async () => {
      const { auditLogsApi } = require('@/features/audit-logs/services/auditLogsApi');
      auditLogsApi.exportLogs.mockImplementation(() => new Promise(() => {}));

      render(<AuditLogExport {...defaultProps} />);

      fireEvent.click(screen.getByText('Start Export'));

      await waitFor(() => {
        expect(screen.getByText('Exporting audit logs...')).toBeInTheDocument();
      });
    });

    it('disables buttons while exporting', async () => {
      const { auditLogsApi } = require('@/features/audit-logs/services/auditLogsApi');
      auditLogsApi.exportLogs.mockImplementation(() => new Promise(() => {}));

      render(<AuditLogExport {...defaultProps} />);

      fireEvent.click(screen.getByText('Start Export'));

      await waitFor(() => {
        expect(screen.getByText('Cancel')).toBeDisabled();
      });
    });

    it('shows success notification on completed export', async () => {
      const { auditLogsApi } = require('@/features/audit-logs/services/auditLogsApi');
      auditLogsApi.exportLogs.mockResolvedValue({
        success: true,
        data: {
          content: 'mock,csv,content',
          filename: 'audit-logs.csv',
          format: 'csv',
          record_count: 100
        }
      });

      render(<AuditLogExport {...defaultProps} />);

      fireEvent.click(screen.getByText('Start Export'));

      await waitFor(() => {
        expect(mockShowNotification).toHaveBeenCalledWith(
          expect.stringContaining('Export completed'),
          'success'
        );
      });
    });

    it('shows error notification on failed export', async () => {
      const { auditLogsApi } = require('@/features/audit-logs/services/auditLogsApi');
      auditLogsApi.exportLogs.mockRejectedValue(new Error('Export failed'));

      render(<AuditLogExport {...defaultProps} />);

      fireEvent.click(screen.getByText('Start Export'));

      await waitFor(() => {
        expect(mockShowNotification).toHaveBeenCalledWith('Export failed', 'error');
      });
    });

    it('handles job_id response for background exports', async () => {
      const { auditLogsApi } = require('@/features/audit-logs/services/auditLogsApi');
      auditLogsApi.exportLogs.mockResolvedValue({
        success: true,
        data: {
          job_id: 'job-123',
          estimated_completion: new Date().toISOString()
        }
      });

      render(<AuditLogExport {...defaultProps} />);

      fireEvent.click(screen.getByText('Start Export'));

      await waitFor(() => {
        expect(mockShowNotification).toHaveBeenCalledWith(
          expect.stringContaining('Export queued'),
          'info'
        );
      });
    });
  });

  describe('icons', () => {
    it('shows download icon in header', () => {
      const { container } = render(<AuditLogExport {...defaultProps} />);

      expect(container.querySelector('.lucide-download')).toBeInTheDocument();
    });

    it('shows table icon for CSV option', () => {
      const { container } = render(<AuditLogExport {...defaultProps} />);

      expect(container.querySelector('.lucide-table')).toBeInTheDocument();
    });

    it('shows file-text icon for JSON option', () => {
      const { container } = render(<AuditLogExport {...defaultProps} />);

      expect(container.querySelectorAll('.lucide-file-text').length).toBeGreaterThanOrEqual(1);
    });

    it('shows alert-circle icon for estimated records', () => {
      const { container } = render(<AuditLogExport {...defaultProps} />);

      // Lucide icons have class pattern: lucide lucide-{icon-name}
      // AlertCircle -> lucide-circle-alert (note the order change)
      expect(container.querySelector('.lucide-circle-alert')).toBeInTheDocument();
    });
  });
});

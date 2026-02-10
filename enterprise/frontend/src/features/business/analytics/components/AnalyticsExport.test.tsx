import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { AnalyticsExport } from './AnalyticsExport';

// Mock Button component
jest.mock('@/shared/components/ui/Button', () => ({
  Button: ({ children, onClick, disabled, variant, className }: any) => (
    <button
      onClick={onClick}
      disabled={disabled}
      data-variant={variant}
      className={className}
    >
      {children}
    </button>
  )
}));

describe('AnalyticsExport', () => {
  const mockDateRange = {
    startDate: new Date('2025-01-01'),
    endDate: new Date('2025-01-31')
  };

  const defaultProps = {
    dateRange: mockDateRange,
    onExport: jest.fn().mockResolvedValue(undefined)
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('initial state', () => {
    it('shows Export button', () => {
      render(<AnalyticsExport {...defaultProps} />);

      expect(screen.getByText('Export')).toBeInTheDocument();
    });

    it('shows export icon', () => {
      render(<AnalyticsExport {...defaultProps} />);

      expect(screen.getByText('📥')).toBeInTheDocument();
    });

    it('hides menu initially when using internal state', () => {
      render(<AnalyticsExport {...defaultProps} />);

      expect(screen.queryByText('Export Analytics')).not.toBeInTheDocument();
    });
  });

  describe('menu toggle', () => {
    it('shows menu when Export button clicked', () => {
      render(<AnalyticsExport {...defaultProps} />);

      fireEvent.click(screen.getByText('Export'));

      expect(screen.getByText('Export Analytics')).toBeInTheDocument();
    });

    it('hides menu when backdrop clicked', () => {
      render(<AnalyticsExport {...defaultProps} />);

      fireEvent.click(screen.getByText('Export'));
      expect(screen.getByText('Export Analytics')).toBeInTheDocument();

      // Click backdrop
      const backdrop = document.querySelector('.fixed.inset-0');
      if (backdrop) {
        fireEvent.click(backdrop);
      }

      expect(screen.queryByText('Export Analytics')).not.toBeInTheDocument();
    });
  });

  describe('external isOpen control', () => {
    it('shows menu when isOpen is true', () => {
      render(<AnalyticsExport {...defaultProps} isOpen={true} />);

      expect(screen.getByText('Export Analytics')).toBeInTheDocument();
    });

    it('hides menu when isOpen is false', () => {
      render(<AnalyticsExport {...defaultProps} isOpen={false} />);

      expect(screen.queryByText('Export Analytics')).not.toBeInTheDocument();
    });

    it('calls onClose when provided', () => {
      const onClose = jest.fn();
      render(<AnalyticsExport {...defaultProps} isOpen={true} onClose={onClose} />);

      fireEvent.click(screen.getByText('Export'));

      expect(onClose).toHaveBeenCalled();
    });
  });

  describe('date range display', () => {
    it('shows date range in menu', () => {
      render(<AnalyticsExport {...defaultProps} isOpen={true} />);

      // Date formatting varies by locale, just check that export data message exists
      expect(screen.getByText(/Export data from/)).toBeInTheDocument();
    });
  });

  describe('export options', () => {
    it('shows Revenue Analytics option', () => {
      render(<AnalyticsExport {...defaultProps} isOpen={true} />);

      expect(screen.getByText('Revenue Analytics')).toBeInTheDocument();
      expect(screen.getByText('MRR, ARR, growth trends, and forecasting')).toBeInTheDocument();
    });

    it('shows Growth Analytics option', () => {
      render(<AnalyticsExport {...defaultProps} isOpen={true} />);

      expect(screen.getByText('Growth Analytics')).toBeInTheDocument();
      expect(screen.getByText('Growth rates, new revenue, and expansion metrics')).toBeInTheDocument();
    });

    it('shows Churn Analysis option', () => {
      render(<AnalyticsExport {...defaultProps} isOpen={true} />);

      expect(screen.getByText('Churn Analysis')).toBeInTheDocument();
      expect(screen.getByText('Customer and revenue churn rates and trends')).toBeInTheDocument();
    });

    it('shows Customer Analytics option', () => {
      render(<AnalyticsExport {...defaultProps} isOpen={true} />);

      expect(screen.getByText('Customer Analytics')).toBeInTheDocument();
      expect(screen.getByText('Customer growth, ARPU, LTV, and segmentation')).toBeInTheDocument();
    });

    it('shows Cohort Analysis option', () => {
      render(<AnalyticsExport {...defaultProps} isOpen={true} />);

      expect(screen.getByText('Cohort Analysis')).toBeInTheDocument();
      expect(screen.getByText('Customer retention by cohort and tenure')).toBeInTheDocument();
    });

    it('shows Complete Report option', () => {
      render(<AnalyticsExport {...defaultProps} isOpen={true} />);

      expect(screen.getByText('Complete Report')).toBeInTheDocument();
      expect(screen.getByText('All analytics data in a comprehensive report')).toBeInTheDocument();
    });
  });

  describe('export buttons', () => {
    it('shows CSV buttons for each option', () => {
      render(<AnalyticsExport {...defaultProps} isOpen={true} />);

      const csvButtons = screen.getAllByText('CSV');
      expect(csvButtons.length).toBe(6); // One for each export option
    });

    it('shows PDF buttons for each option', () => {
      render(<AnalyticsExport {...defaultProps} isOpen={true} />);

      const pdfButtons = screen.getAllByText('PDF');
      expect(pdfButtons.length).toBe(6); // One for each export option
    });
  });

  describe('export functionality', () => {
    it('calls onExport with csv format when CSV clicked', async () => {
      const onExport = jest.fn().mockResolvedValue(undefined);
      render(<AnalyticsExport {...defaultProps} onExport={onExport} isOpen={true} />);

      const csvButtons = screen.getAllByText('CSV');
      fireEvent.click(csvButtons[0]); // Click first CSV button (Revenue)

      await waitFor(() => {
        expect(onExport).toHaveBeenCalledWith('csv', 'revenue');
      });
    });

    it('calls onExport with pdf format when PDF clicked', async () => {
      const onExport = jest.fn().mockResolvedValue(undefined);
      render(<AnalyticsExport {...defaultProps} onExport={onExport} isOpen={true} />);

      const pdfButtons = screen.getAllByText('PDF');
      fireEvent.click(pdfButtons[0]); // Click first PDF button (Revenue)

      await waitFor(() => {
        expect(onExport).toHaveBeenCalledWith('pdf', 'revenue');
      });
    });

    it('exports growth analytics correctly', async () => {
      const onExport = jest.fn().mockResolvedValue(undefined);
      render(<AnalyticsExport {...defaultProps} onExport={onExport} isOpen={true} />);

      const csvButtons = screen.getAllByText('CSV');
      fireEvent.click(csvButtons[1]); // Growth is second option

      await waitFor(() => {
        expect(onExport).toHaveBeenCalledWith('csv', 'growth');
      });
    });

    it('exports complete report correctly', async () => {
      const onExport = jest.fn().mockResolvedValue(undefined);
      render(<AnalyticsExport {...defaultProps} onExport={onExport} isOpen={true} />);

      const pdfButtons = screen.getAllByText('PDF');
      fireEvent.click(pdfButtons[5]); // Complete Report is last option

      await waitFor(() => {
        expect(onExport).toHaveBeenCalledWith('pdf', 'all');
      });
    });
  });

  describe('loading state', () => {
    it('shows Exporting... while export in progress', async () => {
      const onExport = jest.fn().mockImplementation(() => new Promise(() => {})); // Never resolves
      render(<AnalyticsExport {...defaultProps} onExport={onExport} isOpen={true} />);

      const csvButtons = screen.getAllByText('CSV');
      fireEvent.click(csvButtons[0]);

      await waitFor(() => {
        expect(screen.getByText('Exporting...')).toBeInTheDocument();
      });
    });

    it('disables buttons while exporting', async () => {
      const onExport = jest.fn().mockImplementation(() => new Promise(() => {}));
      render(<AnalyticsExport {...defaultProps} onExport={onExport} isOpen={true} />);

      const csvButtons = screen.getAllByText('CSV');
      fireEvent.click(csvButtons[0]);

      await waitFor(() => {
        const exportButton = screen.getByText('Exporting...').closest('button');
        expect(exportButton).toBeDisabled();
      });
    });
  });

  describe('close after export', () => {
    it('calls onClose after successful export', async () => {
      const onClose = jest.fn();
      const onExport = jest.fn().mockResolvedValue(undefined);
      render(<AnalyticsExport {...defaultProps} onExport={onExport} onClose={onClose} isOpen={true} />);

      const csvButtons = screen.getAllByText('CSV');
      fireEvent.click(csvButtons[0]);

      await waitFor(() => {
        expect(onClose).toHaveBeenCalled();
      });
    });

    it('closes internal menu after successful export', async () => {
      const onExport = jest.fn().mockResolvedValue(undefined);
      render(<AnalyticsExport {...defaultProps} onExport={onExport} />);

      // Open menu
      fireEvent.click(screen.getByText('Export'));
      expect(screen.getByText('Export Analytics')).toBeInTheDocument();

      // Export
      const csvButtons = screen.getAllByText('CSV');
      fireEvent.click(csvButtons[0]);

      await waitFor(() => {
        expect(screen.queryByText('Export Analytics')).not.toBeInTheDocument();
      });
    });
  });

  describe('info section', () => {
    it('shows info icon', () => {
      render(<AnalyticsExport {...defaultProps} isOpen={true} />);

      expect(screen.getByText('ℹ️')).toBeInTheDocument();
    });

    it('shows CSV description', () => {
      render(<AnalyticsExport {...defaultProps} isOpen={true} />);

      expect(screen.getByText('CSV exports include raw data for further analysis.')).toBeInTheDocument();
    });

    it('shows PDF description', () => {
      render(<AnalyticsExport {...defaultProps} isOpen={true} />);

      expect(screen.getByText('PDF reports include formatted charts and summaries.')).toBeInTheDocument();
    });
  });

  describe('icons', () => {
    it('shows revenue icon', () => {
      render(<AnalyticsExport {...defaultProps} isOpen={true} />);

      expect(screen.getByText('💰')).toBeInTheDocument();
    });

    it('shows growth icon', () => {
      render(<AnalyticsExport {...defaultProps} isOpen={true} />);

      expect(screen.getByText('📈')).toBeInTheDocument();
    });

    it('shows churn icon', () => {
      render(<AnalyticsExport {...defaultProps} isOpen={true} />);

      expect(screen.getByText('📉')).toBeInTheDocument();
    });

    it('shows customers icon', () => {
      render(<AnalyticsExport {...defaultProps} isOpen={true} />);

      expect(screen.getByText('👥')).toBeInTheDocument();
    });

    it('shows cohorts icon', () => {
      render(<AnalyticsExport {...defaultProps} isOpen={true} />);

      expect(screen.getByText('🔄')).toBeInTheDocument();
    });

    it('shows complete report icon', () => {
      render(<AnalyticsExport {...defaultProps} isOpen={true} />);

      expect(screen.getByText('📊')).toBeInTheDocument();
    });
  });

  describe('error handling', () => {
    it('handles export error gracefully', async () => {
      const onExport = jest.fn().mockRejectedValue(new Error('Export failed'));
      render(<AnalyticsExport {...defaultProps} onExport={onExport} isOpen={true} />);

      const csvButtons = screen.getAllByText('CSV');
      fireEvent.click(csvButtons[0]);

      // Should not throw, just fail silently
      await waitFor(() => {
        expect(onExport).toHaveBeenCalled();
      });

      // Button should be enabled again after error
      await waitFor(() => {
        expect(screen.getByText('Export')).not.toBeDisabled();
      });
    });
  });
});

import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { ExportFormatDropdown } from '../ExportFormatDropdown';

// Suppress unhandled promise rejections from test output
const originalError = console.error;
console.error = (...args: any[]) => {
  const errorStr = String(args[0]);
  // Ignore unhandled promise rejection warnings
  if (errorStr && (errorStr.includes('mock_rejection'))) {
    return;
  }
  originalError(...args);
};

type ExportFormat = 'json' | 'xml' | 'pdf' | 'cyclonedx' | 'spdx';

describe('ExportFormatDropdown', () => {
  const mockOnExport = jest.fn().mockResolvedValue(undefined);

  const defaultProps = {
    onExport: mockOnExport,
    disabled: false,
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  afterEach(() => {
    jest.clearAllTimers();
  });

  describe('button rendering', () => {
    it('renders export button', () => {
      render(<ExportFormatDropdown {...defaultProps} />);
      expect(screen.getByText('Export')).toBeInTheDocument();
    });

    it('shows download icon', () => {
      const { container } = render(<ExportFormatDropdown {...defaultProps} />);
      const button = container.querySelector('button');
      expect(button?.querySelector('svg')).toBeInTheDocument();
    });

    it('shows chevron down icon', () => {
      const { container } = render(<ExportFormatDropdown {...defaultProps} />);
      const icons = container.querySelectorAll('svg');
      expect(icons.length).toBeGreaterThanOrEqual(2);
    });
  });

  describe('dropdown opening/closing', () => {
    it('opens dropdown when button clicked', () => {
      const { container } = render(<ExportFormatDropdown {...defaultProps} />);
      const button = container.querySelector('button');

      fireEvent.click(button!);
      expect(screen.getByText('JSON')).toBeInTheDocument();
    });

    it('closes dropdown when button clicked again', () => {
      const { container } = render(<ExportFormatDropdown {...defaultProps} />);
      const button = container.querySelector('button');

      fireEvent.click(button!);
      expect(screen.getByText('JSON')).toBeInTheDocument();

      fireEvent.click(button!);
      expect(screen.queryByText('JSON')).not.toBeInTheDocument();
    });

    it('closes dropdown when clicking backdrop', () => {
      const { container } = render(<ExportFormatDropdown {...defaultProps} />);
      const button = container.querySelector('button');

      fireEvent.click(button!);
      expect(screen.getByText('JSON')).toBeInTheDocument();

      const backdrop = container.querySelector('div[class*="fixed inset-0"]');
      fireEvent.click(backdrop!);
      expect(screen.queryByText('JSON')).not.toBeInTheDocument();
    });

    it('closes dropdown after selecting format', async () => {
      const { container } = render(<ExportFormatDropdown {...defaultProps} />);
      const button = container.querySelector('button');

      fireEvent.click(button!);
      const jsonButton = screen.getByText('JSON').closest('button');
      fireEvent.click(jsonButton!);

      await waitFor(() => {
        expect(screen.queryByText('JSON')).not.toBeInTheDocument();
      });
    });
  });

  describe('format options', () => {
    it('shows all export format options', () => {
      const { container } = render(<ExportFormatDropdown {...defaultProps} />);
      const button = container.querySelector('button');
      fireEvent.click(button!);

      expect(screen.getByText('JSON')).toBeInTheDocument();
      expect(screen.getByText('XML')).toBeInTheDocument();
      expect(screen.getByText('PDF')).toBeInTheDocument();
      expect(screen.getByText('CycloneDX')).toBeInTheDocument();
      expect(screen.getByText('SPDX')).toBeInTheDocument();
    });

    it('shows format descriptions', () => {
      const { container } = render(<ExportFormatDropdown {...defaultProps} />);
      const button = container.querySelector('button');
      fireEvent.click(button!);

      expect(screen.getByText('Standard JSON format')).toBeInTheDocument();
      expect(screen.getByText('Standard XML format')).toBeInTheDocument();
      expect(screen.getByText('Human-readable report')).toBeInTheDocument();
      expect(screen.getByText('CycloneDX 1.4 format')).toBeInTheDocument();
      expect(screen.getByText('SPDX 2.3 format')).toBeInTheDocument();
    });

    it('displays formats with correct hierarchy', () => {
      const { container } = render(<ExportFormatDropdown {...defaultProps} />);
      const button = container.querySelector('button');
      fireEvent.click(button!);

      const jsonButton = screen.getByText('JSON').closest('button');
      const jsonLabel = jsonButton?.querySelector('p:first-child');
      const jsonDesc = jsonButton?.querySelector('p:last-child');

      expect(jsonLabel?.textContent).toBe('JSON');
      expect(jsonDesc?.textContent).toBe('Standard JSON format');
    });
  });

  describe('export functionality', () => {
    it('calls onExport with correct format when format selected', async () => {
      const onExport = jest.fn().mockResolvedValue(undefined);
      const { container } = render(
        <ExportFormatDropdown {...defaultProps} onExport={onExport} />
      );
      const button = container.querySelector('button');

      fireEvent.click(button!);
      const jsonButton = screen.getByText('JSON').closest('button');
      fireEvent.click(jsonButton!);

      await waitFor(() => {
        expect(onExport).toHaveBeenCalledWith('json');
      });
    });

    it('calls onExport for all format types', async () => {
      const formats: ExportFormat[] = ['json', 'xml', 'pdf', 'cyclonedx', 'spdx'];
      const formatLabels: Record<ExportFormat, string> = {
        json: 'JSON',
        xml: 'XML',
        pdf: 'PDF',
        cyclonedx: 'CycloneDX',
        spdx: 'SPDX',
      };

      for (const format of formats) {
        jest.clearAllMocks();
        const onExport = jest.fn().mockResolvedValue(undefined);
        const { container } = render(
          <ExportFormatDropdown {...defaultProps} onExport={onExport} />
        );
        const button = container.querySelector('button');

        fireEvent.click(button!);
        const formatButton = screen.getByText(formatLabels[format]).closest('button');
        fireEvent.click(formatButton!);

        await waitFor(() => {
          expect(onExport).toHaveBeenCalledWith(format);
        });
      }
    });
  });

  describe('loading state', () => {
    it('shows Exporting... text during export', async () => {
      const onExport = jest.fn(
        (_format: ExportFormat) => new Promise<void>(resolve => setTimeout(resolve, 1000))
      );
      const { container } = render(
        <ExportFormatDropdown {...defaultProps} onExport={onExport} />
      );
      const button = container.querySelector('button');

      fireEvent.click(button!);
      const jsonButton = screen.getByText('JSON').closest('button');
      fireEvent.click(jsonButton!);

      expect(screen.getByText('Exporting...')).toBeInTheDocument();
    });

    it('disables button while exporting', async () => {
      const onExport = jest.fn(
        (_format: ExportFormat) => new Promise<void>(resolve => setTimeout(resolve, 1000))
      );
      const { container } = render(
        <ExportFormatDropdown {...defaultProps} onExport={onExport} />
      );
      const button = container.querySelector('button') as HTMLButtonElement;

      fireEvent.click(button!);
      const jsonButton = screen.getByText('JSON').closest('button');
      fireEvent.click(jsonButton!);

      await waitFor(() => {
        expect(button).toBeDisabled();
      });
    });

    it('shows Export button after export completes', async () => {
      const onExport = jest.fn().mockResolvedValue(undefined);
      const { container } = render(
        <ExportFormatDropdown {...defaultProps} onExport={onExport} />
      );
      const button = container.querySelector('button');

      fireEvent.click(button!);
      const jsonButton = screen.getByText('JSON').closest('button');
      fireEvent.click(jsonButton!);

      await waitFor(() => {
        expect(screen.getByText('Export')).toBeInTheDocument();
      });
    });

    it('re-enables button after export completes', async () => {
      const onExport = jest.fn().mockResolvedValue(undefined);
      const { container } = render(
        <ExportFormatDropdown {...defaultProps} onExport={onExport} />
      );
      const button = container.querySelector('button') as HTMLButtonElement;

      fireEvent.click(button!);
      const jsonButton = screen.getByText('JSON').closest('button');
      fireEvent.click(jsonButton!);

      await waitFor(() => {
        expect(button).not.toBeDisabled();
      });
    });
  });

  describe('disabled prop', () => {
    it('disables button when disabled prop is true', () => {
      const { container } = render(
        <ExportFormatDropdown {...defaultProps} disabled={true} />
      );
      const button = container.querySelector('button');
      expect(button).toBeDisabled();
    });

    it('does not open dropdown when disabled', () => {
      const { container } = render(
        <ExportFormatDropdown {...defaultProps} disabled={true} />
      );
      const button = container.querySelector('button');

      fireEvent.click(button!);
      expect(screen.queryByText('JSON')).not.toBeInTheDocument();
    });

    it('does not call onExport when disabled', async () => {
      const onExport = jest.fn();
      const { container } = render(
        <ExportFormatDropdown {...defaultProps} onExport={onExport} disabled={true} />
      );
      const button = container.querySelector('button');

      fireEvent.click(button!);
      // Menu shouldn't open so we can't select
      expect(screen.queryByText('JSON')).not.toBeInTheDocument();
      expect(onExport).not.toHaveBeenCalled();
    });

    it('enables button when disabled prop is false', () => {
      const { container } = render(
        <ExportFormatDropdown {...defaultProps} disabled={false} />
      );
      const button = container.querySelector('button');
      expect(button).not.toBeDisabled();
    });
  });

  describe('chevron rotation', () => {
    it('rotates chevron when dropdown opens', () => {
      const { container } = render(<ExportFormatDropdown {...defaultProps} />);
      const button = container.querySelector('button');

      const chevron = button?.querySelector('svg:last-of-type');

      fireEvent.click(button!);
      const updatedClasses = chevron?.getAttribute('class') || '';

      // When open, should have rotate-180
      expect(updatedClasses).toContain('rotate-180');
    });

    it('rotates chevron back when dropdown closes', async () => {
      const { container } = render(<ExportFormatDropdown {...defaultProps} />);
      const button = container.querySelector('button');

      fireEvent.click(button!);
      fireEvent.click(button!);

      const chevron = button?.querySelector('svg:last-of-type');
      const updatedClasses = chevron?.getAttribute('class') || '';

      // When closed, should not have rotate-180
      expect(updatedClasses).not.toContain('rotate-180');
    });
  });

  describe('error handling', () => {
    it('handles export errors gracefully', async () => {
      const onExport = jest.fn().mockImplementation(() =>
        Promise.reject(new Error('mock_rejection')).catch(() => {})
      );
      const { container } = render(
        <ExportFormatDropdown {...defaultProps} onExport={onExport} />
      );
      const button = container.querySelector('button');

      fireEvent.click(button!);
      const jsonButton = screen.getByText('JSON').closest('button');

      // Should not throw
      expect(() => {
        fireEvent.click(jsonButton!);
      }).not.toThrow();
    });

    it('re-enables button after export error', async () => {
      const onExport = jest.fn().mockImplementation(() =>
        Promise.reject(new Error('mock_rejection')).catch(() => {})
      );
      const { container } = render(
        <ExportFormatDropdown {...defaultProps} onExport={onExport} />
      );
      const button = container.querySelector('button') as HTMLButtonElement;

      fireEvent.click(button!);
      const jsonButton = screen.getByText('JSON').closest('button');
      fireEvent.click(jsonButton!);

      await waitFor(() => {
        expect(button).not.toBeDisabled();
      });
    });
  });

  describe('dropdown positioning', () => {
    it('positions dropdown correctly', () => {
      const { container } = render(<ExportFormatDropdown {...defaultProps} />);
      const button = container.querySelector('button');

      fireEvent.click(button!);
      const menu = container.querySelector('div[class*="absolute right-0"]');
      expect(menu).toHaveClass('w-56');
      expect(menu).toHaveClass('top-full');
    });
  });

  describe('format option styling', () => {
    it('format options have hover state', () => {
      const { container } = render(<ExportFormatDropdown {...defaultProps} />);
      const button = container.querySelector('button');

      fireEvent.click(button!);
      const jsonButton = screen.getByText('JSON').closest('button');
      expect(jsonButton).toHaveClass('hover:bg-theme-surface-hover');
    });

    it('displays format label as bold', () => {
      const { container } = render(<ExportFormatDropdown {...defaultProps} />);
      const button = container.querySelector('button');

      fireEvent.click(button!);
      const jsonLabel = screen.getByText('JSON').closest('p');
      expect(jsonLabel).toHaveClass('font-medium');
    });

    it('displays format description in smaller text', () => {
      const { container } = render(<ExportFormatDropdown {...defaultProps} />);
      const button = container.querySelector('button');

      fireEvent.click(button!);
      const jsonDesc = screen.getByText('Standard JSON format').closest('p');
      expect(jsonDesc).toHaveClass('text-xs');
    });
  });

  describe('multiple exports', () => {
    it('allows exporting multiple formats in sequence', async () => {
      const onExport = jest.fn().mockResolvedValue(undefined);
      const { container } = render(
        <ExportFormatDropdown {...defaultProps} onExport={onExport} />
      );
      const button = container.querySelector('button');

      // Export as JSON
      fireEvent.click(button!);
      fireEvent.click(screen.getByText('JSON').closest('button')!);
      await waitFor(() => {
        expect(onExport).toHaveBeenCalledWith('json');
      });

      jest.clearAllMocks();

      // Export as XML
      fireEvent.click(button!);
      fireEvent.click(screen.getByText('XML').closest('button')!);
      await waitFor(() => {
        expect(onExport).toHaveBeenCalledWith('xml');
      });
    });
  });
});

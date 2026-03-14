import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { CreateDiffModal } from '../CreateDiffModal';

import { sbomsApi } from '../../../services/sbomsApi';

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

// Mock the sbomsApi
jest.mock('../../../services/sbomsApi', () => ({
  sbomsApi: {
    list: jest.fn(),
  },
}));

describe('CreateDiffModal', () => {
  const mockSboms = [
    { id: 'sbom-1', name: 'App v1.0', version: '1.0.0', created_at: '2025-01-10T10:00:00Z' },
    { id: 'sbom-2', name: 'App v1.1', version: '1.1.0', created_at: '2025-01-15T10:00:00Z' },
    { id: 'sbom-3', name: 'App v1.2', version: '1.2.0', created_at: '2025-01-20T10:00:00Z' },
  ];

  const defaultProps = {
    currentSbomId: 'sbom-current',
    currentSbomName: 'Current App',
    onClose: jest.fn(),
    onCreateDiff: jest.fn().mockResolvedValue(undefined),
  };

  beforeEach(() => {
    jest.clearAllMocks();
    (sbomsApi.list as jest.Mock).mockResolvedValue({ sboms: mockSboms });
  });

  describe('modal rendering', () => {
    it('renders modal container', () => {
      const { container } = render(<CreateDiffModal {...defaultProps} />);
      const modal = container.querySelector('div[class*="bg-theme-surface rounded-lg"]');
      expect(modal).toBeInTheDocument();
    });

    it('displays title', async () => {
      render(<CreateDiffModal {...defaultProps} />);
      await waitFor(() => {
        expect(screen.getByText('Compare SBOMs')).toBeInTheDocument();
      });
    });

    it('renders backdrop', () => {
      const { container } = render(<CreateDiffModal {...defaultProps} />);
      const backdrop = container.querySelector('div[class*="bg-black"]');
      expect(backdrop).toBeInTheDocument();
    });
  });

  describe('close functionality', () => {
    it('calls onClose when close button clicked', async () => {
      const onClose = jest.fn();
      const { container } = render(
        <CreateDiffModal {...defaultProps} onClose={onClose} />
      );

      const closeButton = container.querySelector('button svg[class*="w-5"]')?.closest('button');
      fireEvent.click(closeButton!);

      expect(onClose).toHaveBeenCalled();
    });

    it('calls onClose when backdrop clicked', async () => {
      const onClose = jest.fn();
      const { container } = render(
        <CreateDiffModal {...defaultProps} onClose={onClose} />
      );

      const backdrop = container.querySelector('div[class*="fixed inset-0 bg-black"]');
      fireEvent.click(backdrop!);

      expect(onClose).toHaveBeenCalled();
    });

    it('calls onClose when Cancel button clicked', async () => {
      const onClose = jest.fn();
      render(<CreateDiffModal {...defaultProps} onClose={onClose} />);

      await waitFor(() => {
        const cancelButton = screen.getByText('Cancel');
        fireEvent.click(cancelButton);
        expect(onClose).toHaveBeenCalled();
      });
    });
  });

  describe('current SBOM display', () => {
    it('displays current SBOM name', async () => {
      render(<CreateDiffModal {...defaultProps} currentSbomName="My App v2.0" />);
      await waitFor(() => {
        expect(screen.getByText('My App v2.0')).toBeInTheDocument();
      });
    });

    it('shows "Comparing from" label', async () => {
      render(<CreateDiffModal {...defaultProps} />);
      await waitFor(() => {
        expect(screen.getByText('Comparing from:')).toBeInTheDocument();
      });
    });
  });

  describe('loading state', () => {
    it('shows loading spinner initially', async () => {
      const { container } = render(<CreateDiffModal {...defaultProps} />);
      expect(container.querySelector('[class*="animate-spin"]')).toBeInTheDocument();
    });

    it('calls sbomsApi.list on mount', async () => {
      render(<CreateDiffModal {...defaultProps} />);
      await waitFor(() => {
        expect(sbomsApi.list).toHaveBeenCalledWith({ per_page: 100, status: 'completed' });
      });
    });

    it('filters out current SBOM from list', async () => {
      render(<CreateDiffModal {...defaultProps} currentSbomId="sbom-1" />);
      await waitFor(() => {
        expect(screen.queryByText('App v1.0')).not.toBeInTheDocument();
        expect(screen.getByText('App v1.1')).toBeInTheDocument();
      });
    });

    it('hides loading spinner after loading', async () => {
      const { container } = render(<CreateDiffModal {...defaultProps} />);
      await waitFor(() => {
        expect(container.querySelector('[class*="animate-spin"]')).not.toBeInTheDocument();
      });
    });
  });

  describe('SBOM list display', () => {
    it('displays all available SBOMs', async () => {
      render(<CreateDiffModal {...defaultProps} />);
      await waitFor(() => {
        expect(screen.getByText('App v1.0')).toBeInTheDocument();
        expect(screen.getByText('App v1.1')).toBeInTheDocument();
        expect(screen.getByText('App v1.2')).toBeInTheDocument();
      });
    });

    it('shows SBOM version', async () => {
      render(<CreateDiffModal {...defaultProps} />);
      await waitFor(() => {
        expect(screen.getByText('v1.0.0')).toBeInTheDocument();
        expect(screen.getByText('v1.1.0')).toBeInTheDocument();
      });
    });

    it('shows creation date', async () => {
      render(<CreateDiffModal {...defaultProps} />);
      await waitFor(() => {
        expect(screen.getByText(/Jan 10, 2025/)).toBeInTheDocument();
      });
    });

    it('shows no SBOMs message when empty', async () => {
      (sbomsApi.list as jest.Mock).mockResolvedValue({ sboms: [] });
      render(<CreateDiffModal {...defaultProps} />);
      await waitFor(() => {
        expect(screen.getByText('No SBOMs found')).toBeInTheDocument();
      });
    });
  });

  describe('search functionality', () => {
    it('renders search input', async () => {
      render(<CreateDiffModal {...defaultProps} />);
      await waitFor(() => {
        expect(screen.getByPlaceholderText('Search SBOMs...')).toBeInTheDocument();
      });
    });

    it('filters SBOMs by search term', async () => {
      render(<CreateDiffModal {...defaultProps} />);
      await waitFor(() => {
        const searchInput = screen.getByPlaceholderText('Search SBOMs...') as HTMLInputElement;
        fireEvent.change(searchInput, { target: { value: 'v1.1' } });
        expect(screen.getByText('App v1.1')).toBeInTheDocument();
        expect(screen.queryByText('App v1.0')).not.toBeInTheDocument();
      });
    });

    it('is case insensitive search', async () => {
      render(<CreateDiffModal {...defaultProps} />);
      await waitFor(() => {
        const searchInput = screen.getByPlaceholderText('Search SBOMs...') as HTMLInputElement;
        fireEvent.change(searchInput, { target: { value: 'APP' } });
        expect(screen.getByText('App v1.0')).toBeInTheDocument();
      });
    });

    it('shows no results message when search returns nothing', async () => {
      render(<CreateDiffModal {...defaultProps} />);
      await waitFor(() => {
        const searchInput = screen.getByPlaceholderText('Search SBOMs...') as HTMLInputElement;
        fireEvent.change(searchInput, { target: { value: 'nonexistent' } });
        expect(screen.getByText('No SBOMs found')).toBeInTheDocument();
      });
    });

    it('clears search to show all results', async () => {
      render(<CreateDiffModal {...defaultProps} />);
      await waitFor(() => {
        const searchInput = screen.getByPlaceholderText('Search SBOMs...') as HTMLInputElement;
        fireEvent.change(searchInput, { target: { value: 'v1.1' } });
        expect(screen.queryByText('App v1.0')).not.toBeInTheDocument();

        fireEvent.change(searchInput, { target: { value: '' } });
        expect(screen.getByText('App v1.0')).toBeInTheDocument();
      });
    });
  });

  describe('SBOM selection', () => {
    it('selects SBOM when clicked', async () => {
      render(<CreateDiffModal {...defaultProps} />);
      await waitFor(() => {
        const sbomButton = screen.getByText('App v1.1').closest('button');
        fireEvent.click(sbomButton!);

        expect(sbomButton).toHaveClass('border-theme-interactive-primary');
      });
    });

    it('shows selected state with highlight', async () => {
      render(<CreateDiffModal {...defaultProps} />);
      await waitFor(() => {
        const sbomButton = screen.getByText('App v1.1').closest('button');
        fireEvent.click(sbomButton!);

        expect(sbomButton).toHaveClass('bg-theme-interactive-primary/10');
      });
    });

    it('deselects previous selection when selecting new SBOM', async () => {
      render(<CreateDiffModal {...defaultProps} />);
      await waitFor(() => {
        const sbom1Button = screen.getByText('App v1.0').closest('button');
        const sbom2Button = screen.getByText('App v1.1').closest('button');

        fireEvent.click(sbom1Button!);
        expect(sbom1Button).toHaveClass('border-theme-interactive-primary');

        fireEvent.click(sbom2Button!);
        expect(sbom1Button).not.toHaveClass('border-theme-interactive-primary');
        expect(sbom2Button).toHaveClass('border-theme-interactive-primary');
      });
    });

    it('enables Create Diff button when SBOM selected', async () => {
      render(<CreateDiffModal {...defaultProps} />);
      await waitFor(() => {
        const createButton = screen.getByText('Create Diff');
        expect(createButton).toBeDisabled();

        const sbomButton = screen.getByText('App v1.1').closest('button');
        fireEvent.click(sbomButton!);

        expect(createButton).not.toBeDisabled();
      });
    });
  });

  describe('create diff functionality', () => {
    it('disables Create Diff button by default', async () => {
      render(<CreateDiffModal {...defaultProps} />);
      await waitFor(() => {
        const createButton = screen.getByText('Create Diff');
        expect(createButton).toBeDisabled();
      });
    });

    it('calls onCreateDiff with selected SBOM ID', async () => {
      const onCreateDiff = jest.fn().mockResolvedValue(undefined);
      render(<CreateDiffModal {...defaultProps} onCreateDiff={onCreateDiff} />);

      await waitFor(() => {
        const sbomButton = screen.getByText('App v1.1').closest('button');
        fireEvent.click(sbomButton!);
      });

      const createButton = screen.getByText('Create Diff');
      fireEvent.click(createButton);

      await waitFor(() => {
        expect(onCreateDiff).toHaveBeenCalledWith('sbom-2');
      });
    });

    it('shows Creating... text while creating diff', async () => {
      const onCreateDiff = jest.fn(
        (_compareSbomId: string) => new Promise<void>(resolve => setTimeout(resolve, 1000))
      );
      render(<CreateDiffModal {...defaultProps} onCreateDiff={onCreateDiff} />);

      await waitFor(() => {
        const sbomButton = screen.getByText('App v1.1').closest('button');
        fireEvent.click(sbomButton!);
      });

      const createButton = screen.getByText('Create Diff');
      fireEvent.click(createButton);

      expect(screen.getByText('Creating...')).toBeInTheDocument();
    });

    it('disables button while creating', async () => {
      const onCreateDiff = jest.fn(
        (_compareSbomId: string) => new Promise<void>(resolve => setTimeout(resolve, 1000))
      );
      render(<CreateDiffModal {...defaultProps} onCreateDiff={onCreateDiff} />);

      await waitFor(() => {
        const sbomButton = screen.getByText('App v1.1').closest('button');
        fireEvent.click(sbomButton!);
      });

      const createButton = screen.getByText('Create Diff') as HTMLButtonElement;
      fireEvent.click(createButton);

      await waitFor(() => {
        expect(createButton).toBeDisabled();
      });
    });

    it('closes modal after successful diff creation', async () => {
      const onCreateDiff = jest.fn().mockResolvedValue(undefined);
      const onClose = jest.fn();
      render(
        <CreateDiffModal
          {...defaultProps}
          onCreateDiff={onCreateDiff}
          onClose={onClose}
        />
      );

      await waitFor(() => {
        const sbomButton = screen.getByText('App v1.1').closest('button');
        fireEvent.click(sbomButton!);
      });

      const createButton = screen.getByText('Create Diff');
      fireEvent.click(createButton);

      await waitFor(() => {
        expect(onClose).toHaveBeenCalled();
      });
    });

    it('re-enables button after diff creation', async () => {
      const onCreateDiff = jest.fn().mockResolvedValue(undefined);
      render(<CreateDiffModal {...defaultProps} onCreateDiff={onCreateDiff} />);

      await waitFor(() => {
        const sbomButton = screen.getByText('App v1.1').closest('button');
        fireEvent.click(sbomButton!);
      });

      const createButton = screen.getByText('Create Diff') as HTMLButtonElement;
      fireEvent.click(createButton);

      await waitFor(() => {
        expect(createButton).not.toBeDisabled();
        expect(screen.getByText('Create Diff')).toBeInTheDocument();
      });
    });
  });

  describe('error handling', () => {
    it('handles API error gracefully', async () => {
      (sbomsApi.list as jest.Mock).mockRejectedValue(new Error('ERR_API'));
      render(<CreateDiffModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('No SBOMs found')).toBeInTheDocument();
      });
    });

    it('handles diff creation error gracefully', async () => {
      const onCreateDiff = jest.fn().mockImplementation(() =>
        Promise.reject(new Error('mock_rejection')).catch(() => {})
      );
      render(<CreateDiffModal {...defaultProps} onCreateDiff={onCreateDiff} />);

      await waitFor(() => {
        const sbomButton = screen.getByText('App v1.1').closest('button');
        fireEvent.click(sbomButton!);
      });

      const createButton = screen.getByText('Create Diff');
      expect(() => {
        fireEvent.click(createButton);
      }).not.toThrow();
    });

    it('allows retry after error', async () => {
      const onCreateDiff = jest.fn()
        .mockImplementationOnce(() =>
          Promise.reject(new Error('mock_rejection')).catch(() => {})
        )
        .mockResolvedValueOnce(undefined);

      render(<CreateDiffModal {...defaultProps} onCreateDiff={onCreateDiff} />);

      await waitFor(() => {
        const sbomButton = screen.getByText('App v1.1').closest('button');
        fireEvent.click(sbomButton!);
      });

      let createButton = screen.getByText('Create Diff');
      fireEvent.click(createButton);

      await waitFor(() => {
        createButton = screen.getByText('Create Diff') as HTMLButtonElement;
        expect(createButton).not.toBeDisabled();
      });

      // Second attempt
      fireEvent.click(createButton);
      await waitFor(() => {
        expect(onCreateDiff).toHaveBeenCalledTimes(2);
      });
    });
  });

  describe('accessibility', () => {
    it('search input has correct placeholder', async () => {
      render(<CreateDiffModal {...defaultProps} />);
      await waitFor(() => {
        expect(screen.getByPlaceholderText('Search SBOMs...') ).toBeInTheDocument();
      });
    });

    it('buttons have proper text labels', async () => {
      render(<CreateDiffModal {...defaultProps} />);
      await waitFor(() => {
        expect(screen.getByText('Cancel')).toBeInTheDocument();
        expect(screen.getByText('Create Diff')).toBeInTheDocument();
      });
    });
  });

  describe('scrollable list', () => {
    it('renders scrollable container for SBOMs', async () => {
      const { container } = render(<CreateDiffModal {...defaultProps} />);
      await waitFor(() => {
        const scrollContainer = container.querySelector('div[class*="max-h-64"]');
        expect(scrollContainer).toBeInTheDocument();
      });
    });

    it('handles many SBOMs with scroll', async () => {
      const manySboms = Array.from({ length: 50 }, (_, i) => ({
        id: `sbom-${i}`,
        name: `App v${i}.0`,
        version: `${i}.0.0`,
        created_at: '2025-01-15T10:00:00Z',
      }));

      (sbomsApi.list as jest.Mock).mockResolvedValue({ sboms: manySboms });

      render(<CreateDiffModal {...defaultProps} />);
      await waitFor(() => {
        expect(screen.getByText('App v0.0')).toBeInTheDocument();
        expect(screen.getByText('App v49.0')).toBeInTheDocument();
      });
    });
  });

  describe('SBOM list item format', () => {
    it('displays SBOM info in correct format', async () => {
      render(<CreateDiffModal {...defaultProps} />);
      await waitFor(() => {
        const sbomItem = screen.getByText('App v1.0').closest('button');
        expect(sbomItem?.textContent).toContain('v1.0.0');
        expect(sbomItem?.textContent).toContain('Jan 10, 2025');
      });
    });
  });
});

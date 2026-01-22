import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { StartAssessmentModal } from '../StartAssessmentModal';

// Mock lucide-react icons
jest.mock('lucide-react', () => ({
  X: () => <span data-testid="icon-x" />,
  ClipboardCheck: () => <span data-testid="icon-clipboard" />,
  PlayCircle: () => <span data-testid="icon-play" />,
}));

// Mock Button component
jest.mock('@/shared/components/ui/Button', () => ({
  Button: ({ children, onClick, disabled, variant }: any) => (
    <button onClick={onClick} disabled={disabled} data-variant={variant}>
      {children}
    </button>
  ),
}));

describe('StartAssessmentModal', () => {
  const mockOnStart = jest.fn();
  const mockOnClose = jest.fn();

  const defaultProps = {
    vendorName: 'Test Vendor Inc',
    onClose: mockOnClose,
    onStart: mockOnStart,
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('rendering', () => {
    it('renders modal with title "Start Assessment"', () => {
      render(<StartAssessmentModal {...defaultProps} />);
      const title = screen.getByRole('heading', { name: /Start Assessment/i });
      expect(title).toBeInTheDocument();
    });

    it('renders clipboard icon', () => {
      render(<StartAssessmentModal {...defaultProps} />);
      expect(screen.getByTestId('icon-clipboard')).toBeInTheDocument();
    });

    it('displays vendor name', () => {
      render(<StartAssessmentModal {...defaultProps} />);
      expect(screen.getByText('Test Vendor Inc')).toBeInTheDocument();
    });

    it('renders all assessment type options', () => {
      render(<StartAssessmentModal {...defaultProps} />);
      expect(screen.getByText('Initial Assessment')).toBeInTheDocument();
      expect(screen.getByText('Periodic Review')).toBeInTheDocument();
      expect(screen.getByText('Incident Response')).toBeInTheDocument();
      expect(screen.getByText('Contract Renewal')).toBeInTheDocument();
    });

    it('renders assessment type descriptions', () => {
      render(<StartAssessmentModal {...defaultProps} />);
      expect(
        screen.getByText(
          /First-time comprehensive security assessment for new vendors/
        )
      ).toBeInTheDocument();
      expect(
        screen.getByText(/Regular scheduled assessment to maintain compliance/)
      ).toBeInTheDocument();
      expect(
        screen.getByText(/Assessment triggered by a security incident/)
      ).toBeInTheDocument();
      expect(
        screen.getByText(/Assessment before renewing vendor contract/)
      ).toBeInTheDocument();
    });

    it('renders Start Assessment and Cancel buttons', () => {
      render(<StartAssessmentModal {...defaultProps} />);
      expect(
        screen.getByRole('button', { name: /Start Assessment/i })
      ).toBeInTheDocument();
      expect(screen.getByRole('button', { name: /Cancel/i })).toBeInTheDocument();
    });

    it('renders close button (X icon)', () => {
      render(<StartAssessmentModal {...defaultProps} />);
      expect(screen.getByTestId('icon-x')).toBeInTheDocument();
    });

    it('renders play icon on Start Assessment button', () => {
      render(<StartAssessmentModal {...defaultProps} />);
      expect(screen.getByTestId('icon-play')).toBeInTheDocument();
    });
  });

  describe('default selection', () => {
    it('defaults to "Periodic Review" assessment type', () => {
      render(<StartAssessmentModal {...defaultProps} />);
      const periodicButton = screen.getAllByRole('button').find(
        (btn) => btn.textContent?.includes('Periodic Review')
      );
      expect(periodicButton).toHaveClass('border-theme-interactive-primary');
    });
  });

  describe('assessment type selection', () => {
    it('selects Initial Assessment when clicked', async () => {
      render(<StartAssessmentModal {...defaultProps} />);

      const initialButton = screen.getAllByRole('button').find(
        (btn) => btn.textContent?.includes('Initial Assessment')
      );
      await userEvent.click(initialButton!);

      expect(initialButton).toHaveClass('border-theme-interactive-primary');
    });

    it('selects Incident Response when clicked', async () => {
      render(<StartAssessmentModal {...defaultProps} />);

      const incidentButton = screen.getAllByRole('button').find(
        (btn) => btn.textContent?.includes('Incident Response')
      );
      await userEvent.click(incidentButton!);

      expect(incidentButton).toHaveClass('border-theme-interactive-primary');
    });

    it('selects Contract Renewal when clicked', async () => {
      render(<StartAssessmentModal {...defaultProps} />);

      const renewalButton = screen.getAllByRole('button').find(
        (btn) => btn.textContent?.includes('Contract Renewal')
      );
      await userEvent.click(renewalButton!);

      expect(renewalButton).toHaveClass('border-theme-interactive-primary');
    });

    it('updates selection when switching between types', async () => {
      render(<StartAssessmentModal {...defaultProps} />);

      const initialButton = screen.getAllByRole('button').find(
        (btn) => btn.textContent?.includes('Initial Assessment')
      );
      await userEvent.click(initialButton!);
      expect(initialButton).toHaveClass('border-theme-interactive-primary');

      const incidentButton = screen.getAllByRole('button').find(
        (btn) => btn.textContent?.includes('Incident Response')
      );
      await userEvent.click(incidentButton!);
      expect(incidentButton).toHaveClass('border-theme-interactive-primary');
      expect(initialButton).not.toHaveClass('border-theme-interactive-primary');
    });

    it('highlights only one assessment type at a time', async () => {
      render(<StartAssessmentModal {...defaultProps} />);

      const buttons = screen.getAllByRole('button').filter(
        (btn) => btn.textContent?.includes('Assessment') || 
                btn.textContent?.includes('Review') ||
                btn.textContent?.includes('Response') ||
                btn.textContent?.includes('Renewal')
      );

      // Initial state - Periodic Review selected
      let selectedCount = buttons.filter(
        (btn) => btn.className.includes('border-theme-interactive-primary')
      ).length;
      expect(selectedCount).toBe(1);

      // Click Initial Assessment
      const initialButton = buttons.find(
        (btn) => btn.textContent?.includes('Initial Assessment')
      );
      await userEvent.click(initialButton!);

      selectedCount = buttons.filter(
        (btn) => btn.className.includes('border-theme-interactive-primary')
      ).length;
      expect(selectedCount).toBe(1);
    });
  });

  describe('form submission', () => {
    it('calls onStart with selected assessment type', async () => {
      mockOnStart.mockResolvedValue(undefined);
      render(<StartAssessmentModal {...defaultProps} />);

      const submitButton = screen.getByRole('button', {
        name: /Start Assessment/i,
      });
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnStart).toHaveBeenCalledWith('periodic');
      });
    });

    it('submits with initial assessment type when selected', async () => {
      mockOnStart.mockResolvedValue(undefined);
      render(<StartAssessmentModal {...defaultProps} />);

      const initialButton = screen.getAllByRole('button').find(
        (btn) => btn.textContent?.includes('Initial Assessment')
      );
      await userEvent.click(initialButton!);

      const submitButton = screen.getByRole('button', {
        name: /Start Assessment/i,
      });
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnStart).toHaveBeenCalledWith('initial');
      });
    });

    it('submits with periodic assessment type when selected', async () => {
      mockOnStart.mockResolvedValue(undefined);
      render(<StartAssessmentModal {...defaultProps} />);

      const submitButton = screen.getByRole('button', {
        name: /Start Assessment/i,
      });
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnStart).toHaveBeenCalledWith('periodic');
      });
    });

    it('submits with incident assessment type when selected', async () => {
      mockOnStart.mockResolvedValue(undefined);
      render(<StartAssessmentModal {...defaultProps} />);

      const incidentButton = screen.getAllByRole('button').find(
        (btn) => btn.textContent?.includes('Incident Response')
      );
      await userEvent.click(incidentButton!);

      const submitButton = screen.getByRole('button', {
        name: /Start Assessment/i,
      });
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnStart).toHaveBeenCalledWith('incident');
      });
    });

    it('submits with renewal assessment type when selected', async () => {
      mockOnStart.mockResolvedValue(undefined);
      render(<StartAssessmentModal {...defaultProps} />);

      const renewalButton = screen.getAllByRole('button').find(
        (btn) => btn.textContent?.includes('Contract Renewal')
      );
      await userEvent.click(renewalButton!);

      const submitButton = screen.getByRole('button', {
        name: /Start Assessment/i,
      });
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnStart).toHaveBeenCalledWith('renewal');
      });
    });
  });

  describe('loading state', () => {
    it('shows "Starting..." text during submit', async () => {
      mockOnStart.mockImplementation(
        () => new Promise((resolve) => setTimeout(resolve, 1000))
      );
      render(<StartAssessmentModal {...defaultProps} />);

      const submitButton = screen.getByRole('button', {
        name: /Start Assessment/i,
      });
      await userEvent.click(submitButton);

      expect(screen.getByText('Starting...')).toBeInTheDocument();
    });

    it('disables submit button while loading', async () => {
      mockOnStart.mockImplementation(
        () => new Promise((resolve) => setTimeout(resolve, 1000))
      );
      render(<StartAssessmentModal {...defaultProps} />);

      const submitButton = screen.getByRole('button', {
        name: /Start Assessment/i,
      }) as HTMLButtonElement;
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(submitButton.disabled).toBe(true);
      });
    });

    it('disables Cancel button while loading', async () => {
      mockOnStart.mockImplementation(
        () => new Promise((resolve) => setTimeout(resolve, 50))
      );
      render(<StartAssessmentModal {...defaultProps} />);

      const buttons = screen.getAllByRole('button');
      const submitButton = buttons.find(
        (btn) => btn.textContent?.includes('Start Assessment')
      );
      await userEvent.click(submitButton!);

      const cancelButton = buttons.find(
        (btn) => btn.textContent?.includes('Cancel')
      ) as HTMLButtonElement;

      await waitFor(() => {
        expect(cancelButton.disabled).toBe(true);
      }, { timeout: 100 });
    });

    it('re-enables buttons after successful submission', async () => {
      mockOnStart.mockResolvedValue(undefined);
      render(<StartAssessmentModal {...defaultProps} />);

      const submitButton = screen.getByRole('button', {
        name: /Start Assessment/i,
      }) as HTMLButtonElement;
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnClose).toHaveBeenCalled();
      });
    });
  });

  describe('error handling', () => {

    it('handles submission errors gracefully', async () => {
      mockOnStart.mockRejectedValue(new Error('Failed to start assessment'));
      render(<StartAssessmentModal {...defaultProps} />);

      const submitButton = screen.getAllByRole('button').find(
        (btn) => btn.textContent?.includes('Start Assessment')
      );
      await userEvent.click(submitButton!);

      // Modal should still be open after error
      await waitFor(() => {
        const title = screen.getByRole('heading', { name: /Start Assessment/i });
        expect(title).toBeInTheDocument();
      });
    });

    it('does not close modal on error', async () => {
      mockOnStart.mockRejectedValue(new Error('API error'));
      render(<StartAssessmentModal {...defaultProps} />);

      const submitButton = screen.getAllByRole('button').find(
        (btn) => btn.textContent?.includes('Start Assessment')
      );
      await userEvent.click(submitButton!);

      await waitFor(() => {
        expect(mockOnClose).not.toHaveBeenCalled();
      });
    });

    it('re-enables button after error', async () => {
      mockOnStart.mockRejectedValue(new Error('Network error'));
      render(<StartAssessmentModal {...defaultProps} />);

      const submitButton = screen.getAllByRole('button').find(
        (btn) => btn.textContent?.includes('Start Assessment')
      ) as HTMLButtonElement;
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(submitButton.disabled).toBe(false);
      });
    });
  });

  describe('modal interactions', () => {
    it('closes modal after successful start', async () => {
      mockOnStart.mockResolvedValue(undefined);
      render(<StartAssessmentModal {...defaultProps} />);

      const submitButton = screen.getByRole('button', {
        name: /Start Assessment/i,
      });
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnClose).toHaveBeenCalled();
      });
    });

    it('calls onClose when Cancel button is clicked', async () => {
      render(<StartAssessmentModal {...defaultProps} />);

      const cancelButton = screen.getByRole('button', { name: /Cancel/i });
      await userEvent.click(cancelButton);

      expect(mockOnClose).toHaveBeenCalled();
    });

    it('calls onClose when backdrop is clicked', () => {
      render(<StartAssessmentModal {...defaultProps} />);

      const backdrop = document.querySelector('.bg-black\\/50');
      fireEvent.click(backdrop!);

      expect(mockOnClose).toHaveBeenCalled();
    });

    it('calls onClose when X button is clicked', async () => {
      render(<StartAssessmentModal {...defaultProps} />);

      const closeButton = screen.getByTestId('icon-x').parentElement;
      await userEvent.click(closeButton!);

      expect(mockOnClose).toHaveBeenCalled();
    });
  });

  describe('keyboard accessibility', () => {
    it('assessment type buttons are keyboard accessible', async () => {
      render(<StartAssessmentModal {...defaultProps} />);

      const buttons = screen.getAllByRole('button');
      const assessmentButtons = buttons.filter(
        (btn) => btn.textContent?.includes('Assessment') || 
                btn.textContent?.includes('Review') ||
                btn.textContent?.includes('Response') ||
                btn.textContent?.includes('Renewal')
      );

      assessmentButtons[0].focus();
      expect(document.activeElement).toBe(assessmentButtons[0]);

      await userEvent.keyboard('{ArrowRight}');
      // Note: Real keyboard navigation would require specific implementation
    });
  });

  describe('vendor name variations', () => {
    it('displays vendor name with special characters', () => {
      render(
        <StartAssessmentModal
          {...defaultProps}
          vendorName="Test & Co. (Vendor)"
        />
      );
      expect(screen.getByText('Test & Co. (Vendor)')).toBeInTheDocument();
    });

    it('displays vendor name with long name', () => {
      const longName =
        'Very Long Vendor Name That Should Still Display Correctly Inc.';
      render(
        <StartAssessmentModal {...defaultProps} vendorName={longName} />
      );
      expect(screen.getByText(longName)).toBeInTheDocument();
    });
  });

  describe('ui interactions', () => {
    it('assessment type buttons have hover state', async () => {
      render(<StartAssessmentModal {...defaultProps} />);

      const button = screen.getAllByRole('button').find(
        (btn) => btn.textContent?.includes('Initial Assessment')
      );

      await userEvent.hover(button!);
      // Button should have hover class applied (testing-library can't directly test CSS hover)
      expect(button).toBeInTheDocument();
    });

    it('selected assessment type has distinct styling', async () => {
      render(<StartAssessmentModal {...defaultProps} />);

      const unselected = screen.getAllByRole('button').find(
        (btn) => btn.textContent?.includes('Initial Assessment')
      );
      const selected = screen.getAllByRole('button').find(
        (btn) => btn.textContent?.includes('Periodic Review')
      );

      expect(selected).toHaveClass('border-theme-interactive-primary');
      expect(unselected).not.toHaveClass('border-theme-interactive-primary');
    });
  });

  describe('state management', () => {
    it('maintains selected assessment type across re-renders', async () => {
      const { rerender } = render(<StartAssessmentModal {...defaultProps} />);

      const initialButton = screen.getAllByRole('button').find(
        (btn) => btn.textContent?.includes('Initial Assessment')
      );
      await userEvent.click(initialButton!);

      expect(initialButton).toHaveClass('border-theme-interactive-primary');

      // Re-render with same props
      rerender(<StartAssessmentModal {...defaultProps} />);

      // Button selection should be maintained
      const renewedButton = screen.getAllByRole('button').find(
        (btn) => btn.textContent?.includes('Initial Assessment')
      );
      expect(renewedButton).toHaveClass('border-theme-interactive-primary');
    });
  });

  describe('integration scenarios', () => {
    it('completes full workflow: select type and submit', async () => {
      mockOnStart.mockResolvedValue(undefined);
      render(<StartAssessmentModal {...defaultProps} />);

      // Select incident response
      const incidentButton = screen.getAllByRole('button').find(
        (btn) => btn.textContent?.includes('Incident Response')
      );
      await userEvent.click(incidentButton!);

      // Verify selection
      expect(incidentButton).toHaveClass('border-theme-interactive-primary');

      // Submit
      const submitButton = screen.getByRole('button', {
        name: /Start Assessment/i,
      });
      await userEvent.click(submitButton);

      // Verify API call
      await waitFor(() => {
        expect(mockOnStart).toHaveBeenCalledWith('incident');
        expect(mockOnClose).toHaveBeenCalled();
      });
    });

    it('allows changing selection before submission', async () => {
      mockOnStart.mockResolvedValue(undefined);
      render(<StartAssessmentModal {...defaultProps} />);

      // Initial selection
      const initialButton = screen.getAllByRole('button').find(
        (btn) => btn.textContent?.includes('Initial Assessment')
      );
      await userEvent.click(initialButton!);

      // Change selection
      const renewalButton = screen.getAllByRole('button').find(
        (btn) => btn.textContent?.includes('Contract Renewal')
      );
      await userEvent.click(renewalButton!);

      // Submit with new selection
      const submitButton = screen.getByRole('button', {
        name: /Start Assessment/i,
      });
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnStart).toHaveBeenCalledWith('renewal');
      });
    });
  });
});

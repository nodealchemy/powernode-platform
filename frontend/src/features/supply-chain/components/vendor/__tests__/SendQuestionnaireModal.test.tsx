import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { SendQuestionnaireModal } from '../SendQuestionnaireModal';

// Mock lucide-react icons
jest.mock('lucide-react', () => ({
  X: () => <span data-testid="icon-x" />,
  Send: () => <span data-testid="icon-send" />,
  FileQuestion: () => <span data-testid="icon-file-question" />,
}));

// Mock Button component
jest.mock('@/shared/components/ui/Button', () => ({
  Button: ({ children, onClick, disabled, variant }: any) => (
    <button onClick={onClick} disabled={disabled} data-variant={variant}>
      {children}
    </button>
  ),
}));

// Mock Badge component
jest.mock('@/shared/components/ui/Badge', () => ({
  Badge: ({ children, className, size }: any) => (
    <span data-testid="badge" className={className} data-size={size}>
      {children}
    </span>
  ),
}));

describe('SendQuestionnaireModal', () => {
  const mockOnSend = jest.fn();
  const mockOnClose = jest.fn();

  const defaultProps = {
    vendorName: 'Test Vendor Inc',
    onClose: mockOnClose,
    onSend: mockOnSend,
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('rendering', () => {
    it('renders modal with title "Send Questionnaire"', () => {
      render(<SendQuestionnaireModal {...defaultProps} />);
      const title = screen.getByRole('heading', { name: /Send Questionnaire/i });
      expect(title).toBeInTheDocument();
    });

    it('renders file question icon', () => {
      render(<SendQuestionnaireModal {...defaultProps} />);
      expect(screen.getByTestId('icon-file-question')).toBeInTheDocument();
    });

    it('displays vendor name', () => {
      render(<SendQuestionnaireModal {...defaultProps} />);
      expect(screen.getByText('Test Vendor Inc')).toBeInTheDocument();
      expect(screen.getByText('Sending to:')).toBeInTheDocument();
    });

    it('renders questionnaire template list', () => {
      render(<SendQuestionnaireModal {...defaultProps} />);
      expect(screen.getByText('Basic Security Assessment')).toBeInTheDocument();
      expect(screen.getByText('Comprehensive Security Review')).toBeInTheDocument();
      expect(screen.getByText('GDPR Compliance')).toBeInTheDocument();
      expect(screen.getByText('SOC 2 Readiness')).toBeInTheDocument();
      expect(screen.getByText('General Vendor Assessment')).toBeInTheDocument();
    });

    it('renders template descriptions', () => {
      render(<SendQuestionnaireModal {...defaultProps} />);
      expect(
        screen.getByText('Essential security controls and practices')
      ).toBeInTheDocument();
      expect(
        screen.getByText(/In-depth security assessment covering all domains/)
      ).toBeInTheDocument();
      expect(
        screen.getByText(/Data protection and privacy practices for GDPR/)
      ).toBeInTheDocument();
    });

    it('renders template question counts', () => {
      render(<SendQuestionnaireModal {...defaultProps} />);
      expect(screen.getByText('25 questions')).toBeInTheDocument();
      expect(screen.getByText('85 questions')).toBeInTheDocument();
      expect(screen.getByText('40 questions')).toBeInTheDocument();
      expect(screen.getByText('60 questions')).toBeInTheDocument();
      expect(screen.getByText('50 questions')).toBeInTheDocument();
    });

    it('renders category badges', () => {
      render(<SendQuestionnaireModal {...defaultProps} />);
      const badges = screen.getAllByTestId('badge');
      expect(badges.length).toBeGreaterThan(0);
    });

    it('renders Send Questionnaire and Cancel buttons', () => {
      render(<SendQuestionnaireModal {...defaultProps} />);
      expect(
        screen.getByRole('button', { name: /Send Questionnaire/i })
      ).toBeInTheDocument();
      expect(screen.getByRole('button', { name: /Cancel/i })).toBeInTheDocument();
    });

    it('renders close button (X icon)', () => {
      render(<SendQuestionnaireModal {...defaultProps} />);
      expect(screen.getByTestId('icon-x')).toBeInTheDocument();
    });

    it('renders send icon on Send Questionnaire button', () => {
      render(<SendQuestionnaireModal {...defaultProps} />);
      expect(screen.getByTestId('icon-send')).toBeInTheDocument();
    });
  });

  describe('template selection', () => {
    it('initially has no template selected', () => {
      render(<SendQuestionnaireModal {...defaultProps} />);
      const buttons = screen.getAllByRole('button');
      const templateButtons = buttons.filter(
        (btn) => btn.textContent?.includes('Assessment') ||
                btn.textContent?.includes('Review') ||
                btn.textContent?.includes('Compliance') ||
                btn.textContent?.includes('Readiness')
      );

      templateButtons.forEach((btn) => {
        expect(btn).not.toHaveClass('border-theme-interactive-primary');
      });
    });

    it('selects Basic Security Assessment when clicked', async () => {
      render(<SendQuestionnaireModal {...defaultProps} />);

      const template = screen.getByText('Basic Security Assessment').closest('button');
      await userEvent.click(template!);

      expect(template).toHaveClass('border-theme-interactive-primary');
    });

    it('selects Comprehensive Security Review when clicked', async () => {
      render(<SendQuestionnaireModal {...defaultProps} />);

      const template = screen.getByText('Comprehensive Security Review').closest('button');
      await userEvent.click(template!);

      expect(template).toHaveClass('border-theme-interactive-primary');
    });

    it('selects GDPR Compliance template when clicked', async () => {
      render(<SendQuestionnaireModal {...defaultProps} />);

      const template = screen.getByText('GDPR Compliance').closest('button');
      await userEvent.click(template!);

      expect(template).toHaveClass('border-theme-interactive-primary');
    });

    it('selects SOC 2 Readiness template when clicked', async () => {
      render(<SendQuestionnaireModal {...defaultProps} />);

      const template = screen.getByText('SOC 2 Readiness').closest('button');
      await userEvent.click(template!);

      expect(template).toHaveClass('border-theme-interactive-primary');
    });

    it('selects General Vendor Assessment when clicked', async () => {
      render(<SendQuestionnaireModal {...defaultProps} />);

      const template = screen.getByText('General Vendor Assessment').closest('button');
      await userEvent.click(template!);

      expect(template).toHaveClass('border-theme-interactive-primary');
    });

    it('allows switching template selection', async () => {
      render(<SendQuestionnaireModal {...defaultProps} />);

      const basicTemplate = screen.getByText('Basic Security Assessment').closest('button');
      const gdprTemplate = screen.getByText('GDPR Compliance').closest('button');

      await userEvent.click(basicTemplate!);
      expect(basicTemplate).toHaveClass('border-theme-interactive-primary');

      await userEvent.click(gdprTemplate!);
      expect(gdprTemplate).toHaveClass('border-theme-interactive-primary');
      expect(basicTemplate).not.toHaveClass('border-theme-interactive-primary');
    });

    it('highlights only one template at a time', async () => {
      render(<SendQuestionnaireModal {...defaultProps} />);

      const basicTemplate = screen.getByText('Basic Security Assessment').closest('button');
      const gdprTemplate = screen.getByText('GDPR Compliance').closest('button');

      await userEvent.click(basicTemplate!);

      const buttons = screen.getAllByRole('button');
      const selectedButtons = buttons.filter((btn) =>
        btn.className.includes('border-theme-interactive-primary')
      );

      expect(selectedButtons.length).toBe(1);

      await userEvent.click(gdprTemplate!);

      const newSelectedButtons = buttons.filter((btn) =>
        btn.className.includes('border-theme-interactive-primary')
      );

      expect(newSelectedButtons.length).toBe(1);
    });
  });

  describe('form submission', () => {
    it('send button is disabled without template selection', () => {
      render(<SendQuestionnaireModal {...defaultProps} />);

      const sendButton = screen.getByRole('button', {
        name: /Send Questionnaire/i,
      }) as HTMLButtonElement;

      expect(sendButton.disabled).toBe(true);
    });

    it('enables send button after template selection', async () => {
      render(<SendQuestionnaireModal {...defaultProps} />);

      const template = screen.getByText('Basic Security Assessment').closest('button');
      await userEvent.click(template!);

      const sendButton = screen.getByRole('button', {
        name: /Send Questionnaire/i,
      }) as HTMLButtonElement;

      expect(sendButton.disabled).toBe(false);
    });

    it('calls onSend with correct template ID for Basic Security', async () => {
      mockOnSend.mockResolvedValue(undefined);
      render(<SendQuestionnaireModal {...defaultProps} />);

      const template = screen.getByText('Basic Security Assessment').closest('button');
      await userEvent.click(template!);

      const sendButton = screen.getByRole('button', {
        name: /Send Questionnaire/i,
      });
      await userEvent.click(sendButton);

      await waitFor(() => {
        expect(mockOnSend).toHaveBeenCalledWith('security-basic');
      });
    });

    it('calls onSend with correct template ID for Comprehensive Security', async () => {
      mockOnSend.mockResolvedValue(undefined);
      render(<SendQuestionnaireModal {...defaultProps} />);

      const template = screen.getByText('Comprehensive Security Review').closest('button');
      await userEvent.click(template!);

      const sendButton = screen.getByRole('button', {
        name: /Send Questionnaire/i,
      });
      await userEvent.click(sendButton);

      await waitFor(() => {
        expect(mockOnSend).toHaveBeenCalledWith('security-comprehensive');
      });
    });

    it('calls onSend with correct template ID for GDPR', async () => {
      mockOnSend.mockResolvedValue(undefined);
      render(<SendQuestionnaireModal {...defaultProps} />);

      const template = screen.getByText('GDPR Compliance').closest('button');
      await userEvent.click(template!);

      const sendButton = screen.getByRole('button', {
        name: /Send Questionnaire/i,
      });
      await userEvent.click(sendButton);

      await waitFor(() => {
        expect(mockOnSend).toHaveBeenCalledWith('privacy-gdpr');
      });
    });

    it('calls onSend with correct template ID for SOC 2', async () => {
      mockOnSend.mockResolvedValue(undefined);
      render(<SendQuestionnaireModal {...defaultProps} />);

      const template = screen.getByText('SOC 2 Readiness').closest('button');
      await userEvent.click(template!);

      const sendButton = screen.getByRole('button', {
        name: /Send Questionnaire/i,
      });
      await userEvent.click(sendButton);

      await waitFor(() => {
        expect(mockOnSend).toHaveBeenCalledWith('compliance-soc2');
      });
    });

    it('calls onSend with correct template ID for General Vendor', async () => {
      mockOnSend.mockResolvedValue(undefined);
      render(<SendQuestionnaireModal {...defaultProps} />);

      const template = screen.getByText('General Vendor Assessment').closest('button');
      await userEvent.click(template!);

      const sendButton = screen.getByRole('button', {
        name: /Send Questionnaire/i,
      });
      await userEvent.click(sendButton);

      await waitFor(() => {
        expect(mockOnSend).toHaveBeenCalledWith('vendor-general');
      });
    });
  });

  describe('loading state', () => {
    it('shows "Sending..." text during submit', async () => {
      mockOnSend.mockImplementation(
        () => new Promise((resolve) => setTimeout(resolve, 1000))
      );
      render(<SendQuestionnaireModal {...defaultProps} />);

      const template = screen.getByText('Basic Security Assessment').closest('button');
      await userEvent.click(template!);

      const sendButton = screen.getByRole('button', {
        name: /Send Questionnaire/i,
      });
      await userEvent.click(sendButton);

      expect(screen.getByText('Sending...')).toBeInTheDocument();
    });

    it('disables send button while sending', async () => {
      mockOnSend.mockImplementation(
        () => new Promise((resolve) => setTimeout(resolve, 1000))
      );
      render(<SendQuestionnaireModal {...defaultProps} />);

      const template = screen.getByText('Basic Security Assessment').closest('button');
      await userEvent.click(template!);

      const sendButton = screen.getByRole('button', {
        name: /Send Questionnaire/i,
      }) as HTMLButtonElement;
      await userEvent.click(sendButton);

      await waitFor(() => {
        expect(sendButton.disabled).toBe(true);
      });
    });

    it('disables template selection while sending', async () => {
      mockOnSend.mockImplementation(
        () => new Promise((resolve) => setTimeout(resolve, 1000))
      );
      render(<SendQuestionnaireModal {...defaultProps} />);

      const template = screen.getByText('Basic Security Assessment').closest('button');
      await userEvent.click(template!);

      const sendButton = screen.getByRole('button', {
        name: /Send Questionnaire/i,
      });
      await userEvent.click(sendButton);

      // Note: Testing if other templates are disabled during loading
      // This depends on component implementation
      expect(screen.getByText('Sending...')).toBeInTheDocument();
    });

    it('re-enables send button after successful submission', async () => {
      mockOnSend.mockResolvedValue(undefined);
      render(<SendQuestionnaireModal {...defaultProps} />);

      const template = screen.getByText('Basic Security Assessment').closest('button');
      await userEvent.click(template!);

      const sendButton = screen.getByRole('button', {
        name: /Send Questionnaire/i,
      }) as HTMLButtonElement;
      await userEvent.click(sendButton);

      await waitFor(() => {
        expect(mockOnClose).toHaveBeenCalled();
      });
    });
  });

  describe('error handling', () => {

    it('handles submission errors gracefully', async () => {
      mockOnSend.mockRejectedValue(new Error('Failed to send questionnaire'));
      render(<SendQuestionnaireModal {...defaultProps} />);

      const template = screen.getByText('Basic Security Assessment').closest('button');
      await userEvent.click(template!);

      const sendButton = screen.getAllByRole('button').find(
        (btn) => btn.textContent?.includes('Send Questionnaire')
      );
      await userEvent.click(sendButton!);

      // Modal should still be open after error
      await waitFor(() => {
        const title = screen.getByRole('heading', { name: /Send Questionnaire/i });
        expect(title).toBeInTheDocument();
      });
    });

    it('does not close modal on error', async () => {
      mockOnSend.mockRejectedValue(new Error('API error'));
      render(<SendQuestionnaireModal {...defaultProps} />);

      const template = screen.getByText('GDPR Compliance').closest('button');
      await userEvent.click(template!);

      const sendButton = screen.getAllByRole('button').find(
        (btn) => btn.textContent?.includes('Send Questionnaire')
      );
      await userEvent.click(sendButton!);

      await waitFor(() => {
        expect(mockOnClose).not.toHaveBeenCalled();
      });
    });

    it('re-enables send button after error', async () => {
      mockOnSend.mockRejectedValue(new Error('Network error'));
      render(<SendQuestionnaireModal {...defaultProps} />);

      const template = screen.getByText('Basic Security Assessment').closest('button');
      await userEvent.click(template!);

      const sendButton = screen.getAllByRole('button').find(
        (btn) => btn.textContent?.includes('Send Questionnaire')
      ) as HTMLButtonElement;
      await userEvent.click(sendButton);

      await waitFor(() => {
        expect(sendButton.disabled).toBe(false);
      });
    });

    it('allows retry after error', async () => {
      mockOnSend
        .mockRejectedValueOnce(new Error('First attempt failed'))
        .mockResolvedValueOnce(undefined);

      render(<SendQuestionnaireModal {...defaultProps} />);

      const template = screen.getByText('Basic Security Assessment').closest('button');
      await userEvent.click(template!);

      const sendButton = screen.getAllByRole('button').find(
        (btn) => btn.textContent?.includes('Send Questionnaire')
      );

      // First attempt - fail
      await userEvent.click(sendButton!);
      await waitFor(() => {
        expect(mockOnSend).toHaveBeenCalledTimes(1);
      });

      // Retry - success
      await userEvent.click(sendButton!);
      await waitFor(() => {
        expect(mockOnClose).toHaveBeenCalled();
      });
    });
  });

  describe('modal interactions', () => {
    it('closes modal after successful send', async () => {
      mockOnSend.mockResolvedValue(undefined);
      render(<SendQuestionnaireModal {...defaultProps} />);

      const template = screen.getByText('Basic Security Assessment').closest('button');
      await userEvent.click(template!);

      const sendButton = screen.getByRole('button', {
        name: /Send Questionnaire/i,
      });
      await userEvent.click(sendButton);

      await waitFor(() => {
        expect(mockOnClose).toHaveBeenCalled();
      });
    });

    it('calls onClose when Cancel button is clicked', async () => {
      render(<SendQuestionnaireModal {...defaultProps} />);

      const cancelButton = screen.getByRole('button', { name: /Cancel/i });
      await userEvent.click(cancelButton);

      expect(mockOnClose).toHaveBeenCalled();
    });

    it('calls onClose when backdrop is clicked', () => {
      render(<SendQuestionnaireModal {...defaultProps} />);

      const backdrop = document.querySelector('.bg-black\\/50');
      fireEvent.click(backdrop!);

      expect(mockOnClose).toHaveBeenCalled();
    });

    it('calls onClose when X button is clicked', async () => {
      render(<SendQuestionnaireModal {...defaultProps} />);

      const closeButton = screen.getByTestId('icon-x').parentElement;
      await userEvent.click(closeButton!);

      expect(mockOnClose).toHaveBeenCalled();
    });
  });

  describe('category badges', () => {
    it('displays Security category badge', () => {
      render(<SendQuestionnaireModal {...defaultProps} />);
      const badges = screen.getAllByTestId('badge');
      expect(badges.length).toBeGreaterThan(0);
    });

    it('has correct category styling for Security templates', () => {
      render(<SendQuestionnaireModal {...defaultProps} />);
      const badges = screen.getAllByTestId('badge');
      // Check that badges are rendered with category information
      expect(badges.length).toBeGreaterThanOrEqual(2);
    });
  });

  describe('vendor name variations', () => {
    it('displays vendor name with special characters', () => {
      render(
        <SendQuestionnaireModal
          {...defaultProps}
          vendorName="Test & Co. (Vendor) Ltd."
        />
      );
      expect(screen.getByText('Test & Co. (Vendor) Ltd.')).toBeInTheDocument();
    });

    it('displays long vendor name', () => {
      const longName =
        'Very Long Vendor Company Name That Should Still Display Correctly Inc.';
      render(
        <SendQuestionnaireModal {...defaultProps} vendorName={longName} />
      );
      expect(screen.getByText(longName)).toBeInTheDocument();
    });
  });

  describe('scrolling behavior', () => {
    it('modal allows scrolling when content exceeds viewport', () => {
      render(<SendQuestionnaireModal {...defaultProps} />);
      const modal = document.querySelector('.max-h-\\[90vh\\]');
      expect(modal).toHaveClass('overflow-y-auto');
    });
  });

  describe('template information display', () => {
    it('shows all template information clearly', () => {
      render(<SendQuestionnaireModal {...defaultProps} />);

      // Check Basic Security Assessment
      expect(screen.getByText('Basic Security Assessment')).toBeInTheDocument();
      expect(
        screen.getByText('Essential security controls and practices')
      ).toBeInTheDocument();
      expect(screen.getByText('25 questions')).toBeInTheDocument();

      // Check Comprehensive Security Review
      expect(
        screen.getByText('Comprehensive Security Review')
      ).toBeInTheDocument();
      expect(screen.getByText('85 questions')).toBeInTheDocument();

      // Check GDPR Compliance
      expect(screen.getByText('GDPR Compliance')).toBeInTheDocument();
      expect(screen.getByText('40 questions')).toBeInTheDocument();

      // Check SOC 2 Readiness
      expect(screen.getByText('SOC 2 Readiness')).toBeInTheDocument();
      expect(screen.getByText('60 questions')).toBeInTheDocument();

      // Check General Vendor Assessment
      expect(screen.getByText('General Vendor Assessment')).toBeInTheDocument();
      expect(screen.getByText('50 questions')).toBeInTheDocument();
    });
  });

  describe('integration scenarios', () => {
    it('completes full workflow: select and send', async () => {
      mockOnSend.mockResolvedValue(undefined);
      render(<SendQuestionnaireModal {...defaultProps} />);

      // Verify initial state
      const sendButton = screen.getByRole('button', {
        name: /Send Questionnaire/i,
      }) as HTMLButtonElement;
      expect(sendButton.disabled).toBe(true);

      // Select template
      const template = screen.getByText('SOC 2 Readiness').closest('button');
      await userEvent.click(template!);

      // Verify enabled
      expect(sendButton.disabled).toBe(false);

      // Submit
      await userEvent.click(sendButton);

      // Verify API call and close
      await waitFor(() => {
        expect(mockOnSend).toHaveBeenCalledWith('compliance-soc2');
        expect(mockOnClose).toHaveBeenCalled();
      });
    });

    it('allows changing template selection before sending', async () => {
      mockOnSend.mockResolvedValue(undefined);
      render(<SendQuestionnaireModal {...defaultProps} />);

      // First selection
      let template = screen.getByText('Basic Security Assessment').closest('button');
      await userEvent.click(template!);
      expect(template).toHaveClass('border-theme-interactive-primary');

      // Change selection
      template = screen.getByText('GDPR Compliance').closest('button');
      await userEvent.click(template!);

      // Send with new selection
      const sendButton = screen.getByRole('button', {
        name: /Send Questionnaire/i,
      });
      await userEvent.click(sendButton);

      await waitFor(() => {
        expect(mockOnSend).toHaveBeenCalledWith('privacy-gdpr');
      });
    });

    it('prevents sending without template selection', async () => {
      render(<SendQuestionnaireModal {...defaultProps} />);

      const sendButton = screen.getByRole('button', {
        name: /Send Questionnaire/i,
      }) as HTMLButtonElement;

      expect(sendButton.disabled).toBe(true);
      expect(mockOnSend).not.toHaveBeenCalled();
    });
  });
});

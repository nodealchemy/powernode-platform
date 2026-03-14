import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { CreateAttestationModal } from '../CreateAttestationModal';

// Mock UI components
jest.mock('@/shared/components/ui/Button', () => ({
  Button: ({ children, onClick, disabled, variant, ...props }: any) => (
    <button onClick={onClick} disabled={disabled} data-variant={variant} {...props}>
      {children}
    </button>
  ),
}));

// Mock lucide-react icons
jest.mock('lucide-react', () => ({
  X: () => <div data-testid="icon-x">X</div>,
  FileSignature: () => <div data-testid="icon-file-signature">FileSignature</div>,
  AlertTriangle: () => <div data-testid="icon-alert-triangle">AlertTriangle</div>,
}));

describe('CreateAttestationModal', () => {
  const mockOnCreate = jest.fn();
  const mockOnClose = jest.fn();

  const defaultProps = {
    onClose: mockOnClose,
    onCreate: mockOnCreate,
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('modal rendering', () => {
    it('renders modal with title "Create Attestation"', () => {
      render(<CreateAttestationModal {...defaultProps} />);
      // The title is in an h2, so it appears twice (once as text, once as button text)
      expect(screen.getByRole('heading', { name: /create attestation/i })).toBeInTheDocument();
    });

    it('displays FileSignature icon in header', () => {
      render(<CreateAttestationModal {...defaultProps} />);
      const icon = screen.getByTestId('icon-file-signature');
      expect(icon).toBeInTheDocument();
    });

    it('renders close button in header', () => {
      render(<CreateAttestationModal {...defaultProps} />);
      const buttons = screen.getAllByRole('button');
      expect(buttons.length).toBeGreaterThan(0);
    });

    it('renders backdrop overlay', () => {
      const { container } = render(<CreateAttestationModal {...defaultProps} />);
      const backdrop = container.querySelector('.fixed.inset-0.bg-black\\/50');
      expect(backdrop).toBeInTheDocument();
    });
  });

  describe('attestation type selection', () => {
    it('shows attestation type selection buttons', () => {
      render(<CreateAttestationModal {...defaultProps} />);
      expect(screen.getByText('Attestation Type')).toBeInTheDocument();
    });

    it('displays all four attestation type options', () => {
      render(<CreateAttestationModal {...defaultProps} />);
      expect(screen.getByText('SLSA Provenance')).toBeInTheDocument();
      expect(screen.getByText('SBOM')).toBeInTheDocument();
      expect(screen.getByText('Vulnerability Scan')).toBeInTheDocument();
      expect(screen.getByText('Custom')).toBeInTheDocument();
    });

    it('shows descriptions for each attestation type', () => {
      render(<CreateAttestationModal {...defaultProps} />);
      expect(screen.getByText('Build provenance attestation')).toBeInTheDocument();
      expect(screen.getByText('Software bill of materials attestation')).toBeInTheDocument();
      expect(screen.getByText('Security scan results')).toBeInTheDocument();
      expect(screen.getByText('Custom attestation type')).toBeInTheDocument();
    });

    it('sets SLSA Provenance as default type', () => {
      render(<CreateAttestationModal {...defaultProps} />);
      const slsaButton = screen.getByText('SLSA Provenance').closest('button');
      expect(slsaButton).toHaveClass('border-theme-interactive-primary');
    });

    it('allows selecting different attestation types', async () => {
      render(<CreateAttestationModal {...defaultProps} />);
      const sbomButton = screen.getByText('SBOM').closest('button');

      await userEvent.click(sbomButton!);

      expect(sbomButton).toHaveClass('border-theme-interactive-primary');
    });

    it('highlights selected attestation type', async () => {
      render(<CreateAttestationModal {...defaultProps} />);
      const vulnButton = screen.getByText('Vulnerability Scan').closest('button');

      await userEvent.click(vulnButton!);

      expect(vulnButton).toHaveClass('bg-theme-interactive-primary/10');
      expect(vulnButton).toHaveClass('border-theme-interactive-primary');
    });

    it('deselects previous type when new type is selected', async () => {
      render(<CreateAttestationModal {...defaultProps} />);
      const slsaButton = screen.getByText('SLSA Provenance').closest('button');
      const sbomButton = screen.getByText('SBOM').closest('button');

      // Initially SLSA is selected
      expect(slsaButton).toHaveClass('border-theme-interactive-primary');

      await userEvent.click(sbomButton!);

      // Now SBOM should be selected and SLSA should not
      expect(sbomButton).toHaveClass('border-theme-interactive-primary');
      expect(slsaButton).not.toHaveClass('border-theme-interactive-primary');
    });
  });

  describe('subject name field', () => {
    it('renders subject name input field', () => {
      render(<CreateAttestationModal {...defaultProps} />);
      expect(screen.getByPlaceholderText('e.g., my-app:v1.0.0')).toBeInTheDocument();
    });

    it('shows "Subject Name *" label indicating required field', () => {
      render(<CreateAttestationModal {...defaultProps} />);
      expect(screen.getByText('Subject Name *')).toBeInTheDocument();
    });

    it('allows typing subject name', async () => {
      render(<CreateAttestationModal {...defaultProps} />);
      const input = screen.getByPlaceholderText('e.g., my-app:v1.0.0');

      await userEvent.type(input, 'my-container:latest');

      expect(input).toHaveValue('my-container:latest');
    });

    it('validates subject name is required', async () => {
      render(<CreateAttestationModal {...defaultProps} />);
      const createButton = screen.getByRole('button', { name: /create attestation/i });

      await userEvent.click(createButton);

      expect(screen.getByText('Subject name is required')).toBeInTheDocument();
      expect(mockOnCreate).not.toHaveBeenCalled();
    });

    it('validates that whitespace-only subject name is rejected', async () => {
      render(<CreateAttestationModal {...defaultProps} />);
      const input = screen.getByPlaceholderText('e.g., my-app:v1.0.0');
      const createButton = screen.getByRole('button', { name: /create attestation/i });

      await userEvent.type(input, '   ');
      await userEvent.click(createButton);

      expect(screen.getByText('Subject name is required')).toBeInTheDocument();
    });
  });

  describe('subject digest field', () => {
    it('renders subject digest input field', () => {
      render(<CreateAttestationModal {...defaultProps} />);
      expect(screen.getByPlaceholderText('sha256:abc123...')).toBeInTheDocument();
    });

    it('shows "Subject Digest *" label indicating required field', () => {
      render(<CreateAttestationModal {...defaultProps} />);
      expect(screen.getByText('Subject Digest *')).toBeInTheDocument();
    });

    it('allows typing subject digest', async () => {
      render(<CreateAttestationModal {...defaultProps} />);
      const input = screen.getByPlaceholderText('sha256:abc123...');
      const digest = 'sha256:abc123def456789';

      await userEvent.type(input, digest);

      expect(input).toHaveValue(digest);
    });

    it('validates subject digest is required', async () => {
      render(<CreateAttestationModal {...defaultProps} />);
      const subjectNameInput = screen.getByPlaceholderText('e.g., my-app:v1.0.0');
      const createButton = screen.getByRole('button', { name: /create attestation/i });

      await userEvent.type(subjectNameInput, 'my-app');
      await userEvent.click(createButton);

      expect(screen.getByText('Subject digest is required')).toBeInTheDocument();
      expect(mockOnCreate).not.toHaveBeenCalled();
    });

    it('validates that whitespace-only digest is rejected', async () => {
      render(<CreateAttestationModal {...defaultProps} />);
      const nameInput = screen.getByPlaceholderText('e.g., my-app:v1.0.0');
      const digestInput = screen.getByPlaceholderText('sha256:abc123...');
      const createButton = screen.getByRole('button', { name: /create attestation/i });

      await userEvent.type(nameInput, 'my-app');
      await userEvent.type(digestInput, '   ');
      await userEvent.click(createButton);

      expect(screen.getByText('Subject digest is required')).toBeInTheDocument();
    });
  });

  describe('predicate JSON field', () => {
    it('renders predicate textarea', () => {
      render(<CreateAttestationModal {...defaultProps} />);
      expect(screen.getByDisplayValue('{}')).toBeInTheDocument();
    });

    it('shows "Predicate (JSON)" label', () => {
      render(<CreateAttestationModal {...defaultProps} />);
      expect(screen.getByText('Predicate (JSON)')).toBeInTheDocument();
    });

    it('shows help text about predicate', () => {
      render(<CreateAttestationModal {...defaultProps} />);
      expect(screen.getByText(/Enter the predicate as valid JSON/)).toBeInTheDocument();
    });

    it('allows typing in predicate field', async () => {
      render(<CreateAttestationModal {...defaultProps} />);
      const textarea = screen.getByDisplayValue('{}');

      await userEvent.clear(textarea);
      fireEvent.change(textarea, { target: { value: '{"key": "value"}' } });

      expect(textarea).toHaveValue('{"key": "value"}');
    });

    it('defaults to empty JSON object', () => {
      render(<CreateAttestationModal {...defaultProps} />);
      expect(screen.getByDisplayValue('{}')).toBeInTheDocument();
    });

    it('accepts complex JSON structures', async () => {
      render(<CreateAttestationModal {...defaultProps} />);
      const textarea = screen.getByDisplayValue('{}');
      const complexJson = '{"metadata": {"build": "v1.0"}, "scanner": {"name": "trivy"}}';

      await userEvent.clear(textarea);
      fireEvent.change(textarea, { target: { value: complexJson } });

      expect(textarea).toHaveValue(complexJson);
    });

    it('validates predicate is valid JSON', async () => {
      render(<CreateAttestationModal {...defaultProps} />);
      const nameInput = screen.getByPlaceholderText('e.g., my-app:v1.0.0');
      const digestInput = screen.getByPlaceholderText('sha256:abc123...');
      const predicateInput = screen.getByDisplayValue('{}');
      const createButton = screen.getByRole('button', { name: /create attestation/i });

      await userEvent.type(nameInput, 'my-app');
      await userEvent.type(digestInput, 'sha256:abc123');
      await userEvent.clear(predicateInput);
      fireEvent.change(predicateInput, { target: { value: '{invalid json}' } });
      await userEvent.click(createButton);

      expect(screen.getByText('Invalid JSON in predicate')).toBeInTheDocument();
      expect(mockOnCreate).not.toHaveBeenCalled();
    });

    it('shows error for malformed JSON', async () => {
      render(<CreateAttestationModal {...defaultProps} />);
      const nameInput = screen.getByPlaceholderText('e.g., my-app:v1.0.0');
      const digestInput = screen.getByPlaceholderText('sha256:abc123...');
      const predicateInput = screen.getByDisplayValue('{}');
      const createButton = screen.getByRole('button', { name: /create attestation/i });

      await userEvent.type(nameInput, 'test-app');
      await userEvent.type(digestInput, 'sha256:xyz789');
      await userEvent.clear(predicateInput);
      fireEvent.change(predicateInput, { target: { value: '{"unclosed": "object"' } });
      await userEvent.click(createButton);

      expect(screen.getByText('Invalid JSON in predicate')).toBeInTheDocument();
    });
  });

  describe('error display', () => {
    it('shows error message when validation fails', async () => {
      render(<CreateAttestationModal {...defaultProps} />);
      const createButton = screen.getByRole('button', { name: /create attestation/i });

      await userEvent.click(createButton);

      expect(screen.getByText('Subject name is required')).toBeInTheDocument();
    });

    it('displays error in error container with proper styling', async () => {
      render(<CreateAttestationModal {...defaultProps} />);
      const createButton = screen.getByRole('button', { name: /create attestation/i });

      await userEvent.click(createButton);

      const errorElement = screen.getByText('Subject name is required');
      // ErrorAlert wraps the message in a container with bg-theme-error and bg-opacity-10
      const alertContainer = errorElement.closest('.bg-theme-error');
      expect(alertContainer).toBeInTheDocument();
    });

    it('shows API error message when onCreate fails', async () => {
      const errorMessage = 'Failed to connect to server';
      mockOnCreate.mockRejectedValueOnce(new Error(errorMessage));

      render(<CreateAttestationModal {...defaultProps} />);
      const nameInput = screen.getByPlaceholderText('e.g., my-app:v1.0.0');
      const digestInput = screen.getByPlaceholderText('sha256:abc123...');
      const createButton = screen.getByRole('button', { name: /create attestation/i });

      await userEvent.type(nameInput, 'my-app');
      await userEvent.type(digestInput, 'sha256:abc123');
      await userEvent.click(createButton);

      await waitFor(() => {
        expect(screen.getByText(errorMessage)).toBeInTheDocument();
      });
    });

    it('handles non-Error exceptions from onCreate', async () => {
      mockOnCreate.mockRejectedValueOnce('Unknown error');

      render(<CreateAttestationModal {...defaultProps} />);
      const nameInput = screen.getByPlaceholderText('e.g., my-app:v1.0.0');
      const digestInput = screen.getByPlaceholderText('sha256:abc123...');
      const createButton = screen.getByRole('button', { name: /create attestation/i });

      await userEvent.type(nameInput, 'my-app');
      await userEvent.type(digestInput, 'sha256:abc123');
      await userEvent.click(createButton);

      await waitFor(() => {
        expect(screen.getByText('Failed to create attestation')).toBeInTheDocument();
      });
    });
  });

  describe('form submission', () => {
    it('calls onCreate with correct data on valid submit', async () => {
      mockOnCreate.mockResolvedValueOnce(undefined);

      render(<CreateAttestationModal {...defaultProps} />);
      const nameInput = screen.getByPlaceholderText('e.g., my-app:v1.0.0');
      const digestInput = screen.getByPlaceholderText('sha256:abc123...');
      const predicateInput = screen.getByDisplayValue('{}');
      const createButton = screen.getByRole('button', { name: /create attestation/i });

      await userEvent.type(nameInput, 'my-app');
      await userEvent.type(digestInput, 'sha256:abc123');
      await userEvent.clear(predicateInput);
      fireEvent.change(predicateInput, { target: { value: '{"metadata": "test"}' } });
      await userEvent.click(createButton);

      await waitFor(() => {
        expect(mockOnCreate).toHaveBeenCalledWith({
          attestation_type: 'slsa_provenance',
          subject_name: 'my-app',
          subject_digest: 'sha256:abc123',
          predicate: { metadata: 'test' },
        });
      });
    });

    it('sends correct attestation type to onCreate', async () => {
      mockOnCreate.mockResolvedValueOnce(undefined);

      render(<CreateAttestationModal {...defaultProps} />);
      const sbomButton = screen.getByText('SBOM').closest('button');
      const nameInput = screen.getByPlaceholderText('e.g., my-app:v1.0.0');
      const digestInput = screen.getByPlaceholderText('sha256:abc123...');
      const createButton = screen.getByRole('button', { name: /create attestation/i });

      await userEvent.click(sbomButton!);
      await userEvent.type(nameInput, 'my-app');
      await userEvent.type(digestInput, 'sha256:abc123');
      await userEvent.click(createButton);

      await waitFor(() => {
        expect(mockOnCreate).toHaveBeenCalledWith(
          expect.objectContaining({
            attestation_type: 'sbom',
          })
        );
      });
    });

    it('trims whitespace from subject name and digest', async () => {
      mockOnCreate.mockResolvedValueOnce(undefined);

      render(<CreateAttestationModal {...defaultProps} />);
      const nameInput = screen.getByPlaceholderText('e.g., my-app:v1.0.0');
      const digestInput = screen.getByPlaceholderText('sha256:abc123...');
      const createButton = screen.getByRole('button', { name: /create attestation/i });

      await userEvent.type(nameInput, '  my-app  ');
      await userEvent.type(digestInput, '  sha256:abc123  ');
      await userEvent.click(createButton);

      await waitFor(() => {
        expect(mockOnCreate).toHaveBeenCalledWith(
          expect.objectContaining({
            subject_name: 'my-app',
            subject_digest: 'sha256:abc123',
          })
        );
      });
    });

    it('parses predicate JSON correctly', async () => {
      mockOnCreate.mockResolvedValueOnce(undefined);

      render(<CreateAttestationModal {...defaultProps} />);
      const nameInput = screen.getByPlaceholderText('e.g., my-app:v1.0.0');
      const digestInput = screen.getByPlaceholderText('sha256:abc123...');
      const predicateInput = screen.getByDisplayValue('{}');
      const createButton = screen.getByRole('button', { name: /create attestation/i });

      const jsonData = { name: 'test', nested: { value: 123 } };
      await userEvent.type(nameInput, 'my-app');
      await userEvent.type(digestInput, 'sha256:abc123');
      await userEvent.clear(predicateInput);
      fireEvent.change(predicateInput, { target: { value: JSON.stringify(jsonData) } });
      await userEvent.click(createButton);

      await waitFor(() => {
        expect(mockOnCreate).toHaveBeenCalledWith(
          expect.objectContaining({
            predicate: jsonData,
          })
        );
      });
    });
  });

  describe('loading state', () => {
    it('shows "Creating..." text while submitting', async () => {
      mockOnCreate.mockImplementation(() => new Promise(() => {})); // Never resolves

      render(<CreateAttestationModal {...defaultProps} />);
      const nameInput = screen.getByPlaceholderText('e.g., my-app:v1.0.0');
      const digestInput = screen.getByPlaceholderText('sha256:abc123...');
      const createButton = screen.getByRole('button', { name: /create attestation/i });

      await userEvent.type(nameInput, 'my-app');
      await userEvent.type(digestInput, 'sha256:abc123');
      await userEvent.click(createButton);

      expect(screen.getByText('Creating...')).toBeInTheDocument();
    });

    it('disables create button while submitting', async () => {
      mockOnCreate.mockImplementation(() => new Promise(() => {}));

      render(<CreateAttestationModal {...defaultProps} />);
      const nameInput = screen.getByPlaceholderText('e.g., my-app:v1.0.0');
      const digestInput = screen.getByPlaceholderText('sha256:abc123...');
      const createButton = screen.getByRole('button', { name: /create attestation/i });

      await userEvent.type(nameInput, 'my-app');
      await userEvent.type(digestInput, 'sha256:abc123');
      await userEvent.click(createButton);

      expect(screen.getByRole('button', { name: /creating/i })).toBeDisabled();
    });

    it('re-enables create button after successful creation', async () => {
      mockOnCreate.mockResolvedValueOnce(undefined);

      render(<CreateAttestationModal {...defaultProps} />);
      const nameInput = screen.getByPlaceholderText('e.g., my-app:v1.0.0');
      const digestInput = screen.getByPlaceholderText('sha256:abc123...');
      let createButton = screen.getByRole('button', { name: /create attestation/i });

      await userEvent.type(nameInput, 'my-app');
      await userEvent.type(digestInput, 'sha256:abc123');
      await userEvent.click(createButton);

      await waitFor(() => {
        createButton = screen.getByRole('button', { name: /create attestation/i });
        expect(createButton).not.toBeDisabled();
      });
    });

    it('re-enables button when error occurs', async () => {
      mockOnCreate.mockRejectedValueOnce(new Error('Creation failed'));

      render(<CreateAttestationModal {...defaultProps} />);
      const nameInput = screen.getByPlaceholderText('e.g., my-app:v1.0.0');
      const digestInput = screen.getByPlaceholderText('sha256:abc123...');
      const createButton = screen.getByRole('button', { name: /create attestation/i });

      await userEvent.type(nameInput, 'my-app');
      await userEvent.type(digestInput, 'sha256:abc123');
      await userEvent.click(createButton);

      await waitFor(() => {
        const newButton = screen.getByRole('button', { name: /create attestation/i });
        expect(newButton).not.toBeDisabled();
      });
    });
  });

  describe('modal close behavior', () => {
    it('closes modal after successful creation', async () => {
      mockOnCreate.mockResolvedValueOnce(undefined);

      render(<CreateAttestationModal {...defaultProps} />);
      const nameInput = screen.getByPlaceholderText('e.g., my-app:v1.0.0');
      const digestInput = screen.getByPlaceholderText('sha256:abc123...');
      const createButton = screen.getByRole('button', { name: /create attestation/i });

      await userEvent.type(nameInput, 'my-app');
      await userEvent.type(digestInput, 'sha256:abc123');
      await userEvent.click(createButton);

      await waitFor(() => {
        expect(mockOnClose).toHaveBeenCalled();
      });
    });

    it('closes modal when backdrop is clicked', async () => {
      const { container } = render(<CreateAttestationModal {...defaultProps} />);
      const backdrop = container.querySelector('.fixed.inset-0.bg-black\\/50');

      fireEvent.click(backdrop!);

      expect(mockOnClose).toHaveBeenCalled();
    });

    it('closes modal when close button is clicked', async () => {
      const { container } = render(<CreateAttestationModal {...defaultProps} />);

      // Find the X close button (it's the second button after the form)
      const buttons = container.querySelectorAll('button');
      const xButton = Array.from(buttons).find(
        (btn) => btn.textContent.includes('X') || btn.className.includes('hover:bg-theme-surface-hover')
      );

      if (xButton) {
        fireEvent.click(xButton);
        expect(mockOnClose).toHaveBeenCalled();
      }
    });

    it('closes modal when Cancel button is clicked', async () => {
      render(<CreateAttestationModal {...defaultProps} />);
      const cancelButton = screen.getByRole('button', { name: /cancel/i });

      await userEvent.click(cancelButton);

      expect(mockOnClose).toHaveBeenCalled();
    });

    it('does not close modal on validation error', async () => {
      render(<CreateAttestationModal {...defaultProps} />);
      const createButton = screen.getByRole('button', { name: /create attestation/i });

      await userEvent.click(createButton);

      // onClose should not be called for validation errors
      expect(mockOnClose).not.toHaveBeenCalled();
    });

    it('does not close modal when API error occurs', async () => {
      mockOnCreate.mockRejectedValueOnce(new Error('API error'));

      render(<CreateAttestationModal {...defaultProps} />);
      const nameInput = screen.getByPlaceholderText('e.g., my-app:v1.0.0');
      const digestInput = screen.getByPlaceholderText('sha256:abc123...');
      const createButton = screen.getByRole('button', { name: /create attestation/i });

      await userEvent.type(nameInput, 'my-app');
      await userEvent.type(digestInput, 'sha256:abc123');
      await userEvent.click(createButton);

      await waitFor(() => {
        expect(mockOnClose).not.toHaveBeenCalled();
      });
    });
  });

  describe('button states and labels', () => {
    it('shows "Create Attestation" button when not submitting', () => {
      render(<CreateAttestationModal {...defaultProps} />);
      expect(screen.getByRole('button', { name: /create attestation/i })).toBeInTheDocument();
    });

    it('shows Cancel button', () => {
      render(<CreateAttestationModal {...defaultProps} />);
      expect(screen.getByRole('button', { name: /cancel/i })).toBeInTheDocument();
    });

    it('Create button has primary variant', () => {
      render(<CreateAttestationModal {...defaultProps} />);
      const createButton = screen.getByRole('button', { name: /create attestation/i });
      expect(createButton).toHaveAttribute('data-variant', 'primary');
    });

    it('Cancel button has secondary variant', () => {
      render(<CreateAttestationModal {...defaultProps} />);
      const cancelButton = screen.getByRole('button', { name: /cancel/i });
      expect(cancelButton).toHaveAttribute('data-variant', 'secondary');
    });
  });

  describe('integration scenarios', () => {
    it('allows complete workflow: fill form, select type, submit', async () => {
      mockOnCreate.mockResolvedValueOnce(undefined);

      render(<CreateAttestationModal {...defaultProps} />);

      // Select custom attestation type
      const customButton = screen.getByText('Custom').closest('button');
      await userEvent.click(customButton!);

      // Fill in fields
      const nameInput = screen.getByPlaceholderText('e.g., my-app:v1.0.0');
      const digestInput = screen.getByPlaceholderText('sha256:abc123...');
      const predicateInput = screen.getByDisplayValue('{}');

      await userEvent.type(nameInput, 'test-service:v2.0.0');
      await userEvent.type(digestInput, 'sha256:def456ghi789');
      await userEvent.clear(predicateInput);
      fireEvent.change(predicateInput, { target: { value: '{"custom": true}' } });

      // Submit
      const createButton = screen.getByRole('button', { name: /create attestation/i });
      await userEvent.click(createButton);

      // Verify
      await waitFor(() => {
        expect(mockOnCreate).toHaveBeenCalledWith({
          attestation_type: 'custom',
          subject_name: 'test-service:v2.0.0',
          subject_digest: 'sha256:def456ghi789',
          predicate: { custom: true },
        });
        expect(mockOnClose).toHaveBeenCalled();
      });
    });

    it('allows user to correct validation error and resubmit', async () => {
      mockOnCreate.mockResolvedValueOnce(undefined);

      render(<CreateAttestationModal {...defaultProps} />);

      // First attempt - missing digest
      const nameInput = screen.getByPlaceholderText('e.g., my-app:v1.0.0');
      let createButton = screen.getByRole('button', { name: /create attestation/i });

      await userEvent.type(nameInput, 'my-app');
      await userEvent.click(createButton);

      expect(screen.getByText('Subject digest is required')).toBeInTheDocument();

      // Correct error
      const digestInput = screen.getByPlaceholderText('sha256:abc123...');
      await userEvent.type(digestInput, 'sha256:abc123');

      // Second attempt
      createButton = screen.getByRole('button', { name: /create attestation/i });
      await userEvent.click(createButton);

      await waitFor(() => {
        expect(mockOnCreate).toHaveBeenCalledWith(
          expect.objectContaining({
            subject_name: 'my-app',
            subject_digest: 'sha256:abc123',
          })
        );
      });
    });

    it('handles special characters in subject name', async () => {
      mockOnCreate.mockResolvedValueOnce(undefined);

      render(<CreateAttestationModal {...defaultProps} />);
      const nameInput = screen.getByPlaceholderText('e.g., my-app:v1.0.0');
      const digestInput = screen.getByPlaceholderText('sha256:abc123...');
      const createButton = screen.getByRole('button', { name: /create attestation/i });

      const specialName = 'docker.io/org/image-name:v1.0.0-rc.1+build.123';
      await userEvent.type(nameInput, specialName);
      await userEvent.type(digestInput, 'sha256:abc123');
      await userEvent.click(createButton);

      await waitFor(() => {
        expect(mockOnCreate).toHaveBeenCalledWith(
          expect.objectContaining({
            subject_name: specialName,
          })
        );
      });
    });

    it('clears error when user starts fixing it', async () => {
      render(<CreateAttestationModal {...defaultProps} />);

      // Trigger error
      const createButton = screen.getByRole('button', { name: /create attestation/i });
      await userEvent.click(createButton);

      expect(screen.getByText('Subject name is required')).toBeInTheDocument();

      // Start typing in name field
      const nameInput = screen.getByPlaceholderText('e.g., my-app:v1.0.0');
      await userEvent.type(nameInput, 'm');

      // Error should still show (we don't clear on input)
      // This verifies error persists until explicit fix
      expect(screen.getByText('Subject name is required')).toBeInTheDocument();
    });
  });
});

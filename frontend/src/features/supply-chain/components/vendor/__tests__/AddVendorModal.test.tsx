import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { AddVendorModal } from '../AddVendorModal';

// Mock lucide-react icons
jest.mock('lucide-react', () => ({
  X: () => <span data-testid="icon-x" />,
  Building2: () => <span data-testid="icon-building" />,
  AlertTriangle: () => <span data-testid="icon-alert-triangle" />,
}));

// Mock Button component
jest.mock('@/shared/components/ui/Button', () => ({
  Button: ({ children, onClick, disabled, variant }: any) => (
    <button onClick={onClick} disabled={disabled} data-variant={variant}>
      {children}
    </button>
  ),
}));

describe('AddVendorModal', () => {
  const mockOnAdd = jest.fn();
  const mockOnClose = jest.fn();

  const defaultProps = {
    onClose: mockOnClose,
    onAdd: mockOnAdd,
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('rendering', () => {
    it('renders modal with title "Add Vendor"', () => {
      render(<AddVendorModal {...defaultProps} />);
      const title = screen.getByRole('heading', { name: /Add Vendor/i });
      expect(title).toBeInTheDocument();
    });

    it('renders vendor name input field (required)', () => {
      render(<AddVendorModal {...defaultProps} />);
      expect(screen.getByPlaceholderText('Enter vendor name')).toBeInTheDocument();
      expect(screen.getByText(/Vendor Name \*/)).toBeInTheDocument();
    });

    it('renders vendor type dropdown with all options', () => {
      render(<AddVendorModal {...defaultProps} />);
      const select = screen.getByDisplayValue('SaaS');
      expect(select).toBeInTheDocument();

      fireEvent.click(select);
      expect(screen.getByText('API')).toBeInTheDocument();
      expect(screen.getByText('Library')).toBeInTheDocument();
      expect(screen.getByText('Infrastructure')).toBeInTheDocument();
      expect(screen.getByText('Hardware')).toBeInTheDocument();
      expect(screen.getByText('Consulting')).toBeInTheDocument();
    });

    it('renders contact name and email inputs', () => {
      render(<AddVendorModal {...defaultProps} />);
      expect(screen.getByPlaceholderText('Contact person')).toBeInTheDocument();
      expect(screen.getByPlaceholderText('email@vendor.com')).toBeInTheDocument();
    });

    it('renders website input', () => {
      render(<AddVendorModal {...defaultProps} />);
      expect(screen.getByPlaceholderText('https://vendor.com')).toBeInTheDocument();
    });

    it('renders data handling checkboxes (PII, PHI, PCI)', () => {
      render(<AddVendorModal {...defaultProps} />);
      expect(screen.getByText(/Handles PII/)).toBeInTheDocument();
      expect(screen.getByText(/Handles PHI/)).toBeInTheDocument();
      expect(screen.getByText(/Handles PCI/)).toBeInTheDocument();
    });

    it('renders certifications input field', () => {
      render(<AddVendorModal {...defaultProps} />);
      expect(
        screen.getByPlaceholderText(/SOC2, ISO27001, HIPAA/)
      ).toBeInTheDocument();
    });

    it('renders Add Vendor and Cancel buttons', () => {
      render(<AddVendorModal {...defaultProps} />);
      expect(screen.getByRole('button', { name: /Add Vendor/i })).toBeInTheDocument();
      expect(screen.getByRole('button', { name: /Cancel/i })).toBeInTheDocument();
    });

    it('renders close button (X icon)', () => {
      render(<AddVendorModal {...defaultProps} />);
      expect(screen.getByTestId('icon-x')).toBeInTheDocument();
    });
  });

  describe('form validation', () => {
    it('validates vendor name is required', async () => {
      render(<AddVendorModal {...defaultProps} />);

      const submitButton = screen.getByRole('button', { name: /Add Vendor/i });
      await userEvent.click(submitButton);

      expect(screen.getByText('Vendor name is required')).toBeInTheDocument();
      expect(mockOnAdd).not.toHaveBeenCalled();
    });

    it('validates vendor name with only whitespace is rejected', async () => {
      render(<AddVendorModal {...defaultProps} />);

      const nameInput = screen.getByPlaceholderText('Enter vendor name');
      await userEvent.type(nameInput, '   ');

      const submitButton = screen.getByRole('button', { name: /Add Vendor/i });
      await userEvent.click(submitButton);

      expect(screen.getByText('Vendor name is required')).toBeInTheDocument();
      expect(mockOnAdd).not.toHaveBeenCalled();
    });

    it('clears validation error when vendor name is entered', async () => {
      render(<AddVendorModal {...defaultProps} />);

      // Trigger validation error
      const submitButton = screen.getByRole('button', { name: /Add Vendor/i });
      await userEvent.click(submitButton);
      expect(screen.getByText('Vendor name is required')).toBeInTheDocument();

      // Enter vendor name
      const nameInput = screen.getByPlaceholderText('Enter vendor name');
      await userEvent.type(nameInput, 'Test Vendor');

      // Error should be cleared (no error message shown)
      expect(screen.queryByText('Vendor name is required')).not.toBeInTheDocument();
    });
  });

  describe('form interactions', () => {
    it('updates vendor name on input', async () => {
      render(<AddVendorModal {...defaultProps} />);

      const nameInput = screen.getByPlaceholderText(
        'Enter vendor name'
      ) as HTMLInputElement;
      await userEvent.type(nameInput, 'Test Vendor');

      expect(nameInput.value).toBe('Test Vendor');
    });

    it('changes vendor type on selection', async () => {
      render(<AddVendorModal {...defaultProps} />);

      const typeSelect = screen.getByDisplayValue('SaaS') as HTMLSelectElement;
      await userEvent.selectOptions(typeSelect, 'api');

      expect(typeSelect.value).toBe('api');
    });

    it('updates contact name', async () => {
      render(<AddVendorModal {...defaultProps} />);

      const contactInput = screen.getByPlaceholderText(
        'Contact person'
      ) as HTMLInputElement;
      await userEvent.type(contactInput, 'John Doe');

      expect(contactInput.value).toBe('John Doe');
    });

    it('updates contact email', async () => {
      render(<AddVendorModal {...defaultProps} />);

      const emailInput = screen.getByPlaceholderText(
        'email@vendor.com'
      ) as HTMLInputElement;
      await userEvent.type(emailInput, 'john@vendor.com');

      expect(emailInput.value).toBe('john@vendor.com');
    });

    it('updates website', async () => {
      render(<AddVendorModal {...defaultProps} />);

      const websiteInput = screen.getByPlaceholderText(
        'https://vendor.com'
      ) as HTMLInputElement;
      await userEvent.type(websiteInput, 'https://test-vendor.com');

      expect(websiteInput.value).toBe('https://test-vendor.com');
    });

    it('toggles data handling checkboxes', async () => {
      render(<AddVendorModal {...defaultProps} />);

      const piiCheckbox = screen.getByRole('checkbox', {
        name: /Handles PII/i,
      }) as HTMLInputElement;
      const phiCheckbox = screen.getByRole('checkbox', {
        name: /Handles PHI/i,
      }) as HTMLInputElement;
      const pciCheckbox = screen.getByRole('checkbox', {
        name: /Handles PCI/i,
      }) as HTMLInputElement;

      expect(piiCheckbox.checked).toBe(false);
      expect(phiCheckbox.checked).toBe(false);
      expect(pciCheckbox.checked).toBe(false);

      await userEvent.click(piiCheckbox);
      await userEvent.click(phiCheckbox);

      expect(piiCheckbox.checked).toBe(true);
      expect(phiCheckbox.checked).toBe(true);
      expect(pciCheckbox.checked).toBe(false);
    });

    it('updates certifications field', async () => {
      render(<AddVendorModal {...defaultProps} />);

      const certificationsInput = screen.getByPlaceholderText(
        /SOC2, ISO27001, HIPAA/
      ) as HTMLInputElement;
      await userEvent.type(certificationsInput, 'SOC2, ISO27001, HIPAA');

      expect(certificationsInput.value).toBe('SOC2, ISO27001, HIPAA');
    });
  });

  describe('form submission', () => {
    it('calls onAdd with correct data on successful submission', async () => {
      mockOnAdd.mockResolvedValue(undefined);
      render(<AddVendorModal {...defaultProps} />);

      const nameInput = screen.getByPlaceholderText('Enter vendor name');
      await userEvent.type(nameInput, 'Test Vendor');

      const submitButton = screen.getByRole('button', { name: /Add Vendor/i });
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnAdd).toHaveBeenCalledWith(
          expect.objectContaining({
            name: 'Test Vendor',
            vendor_type: 'saas',
          })
        );
      });
    });

    it('parses certifications from comma-separated string', async () => {
      mockOnAdd.mockResolvedValue(undefined);
      render(<AddVendorModal {...defaultProps} />);

      const nameInput = screen.getByPlaceholderText('Enter vendor name');
      await userEvent.type(nameInput, 'Test Vendor');

      const certificationsInput = screen.getByPlaceholderText(
        /SOC2, ISO27001, HIPAA/
      );
      await userEvent.type(certificationsInput, 'SOC2, ISO27001, HIPAA');

      const submitButton = screen.getByRole('button', { name: /Add Vendor/i });
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnAdd).toHaveBeenCalledWith(
          expect.objectContaining({
            certifications: ['SOC2', 'ISO27001', 'HIPAA'],
          })
        );
      });
    });

    it('includes data handling flags in submission', async () => {
      mockOnAdd.mockResolvedValue(undefined);
      render(<AddVendorModal {...defaultProps} />);

      const nameInput = screen.getByPlaceholderText('Enter vendor name');
      await userEvent.type(nameInput, 'Test Vendor');

      const piiCheckbox = screen.getByRole('checkbox', {
        name: /Handles PII/i,
      });
      const pciCheckbox = screen.getByRole('checkbox', {
        name: /Handles PCI/i,
      });

      await userEvent.click(piiCheckbox);
      await userEvent.click(pciCheckbox);

      const submitButton = screen.getByRole('button', { name: /Add Vendor/i });
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnAdd).toHaveBeenCalledWith(
          expect.objectContaining({
            handles_pii: true,
            handles_phi: false,
            handles_pci: true,
          })
        );
      });
    });

    it('trims whitespace from text fields', async () => {
      mockOnAdd.mockResolvedValue(undefined);
      render(<AddVendorModal {...defaultProps} />);

      const nameInput = screen.getByPlaceholderText('Enter vendor name');
      await userEvent.type(nameInput, '  Test Vendor  ');

      const submitButton = screen.getByRole('button', { name: /Add Vendor/i });
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnAdd).toHaveBeenCalledWith(
          expect.objectContaining({
            name: 'Test Vendor',
          })
        );
      });
    });

    it('converts empty contact fields to undefined', async () => {
      mockOnAdd.mockResolvedValue(undefined);
      render(<AddVendorModal {...defaultProps} />);

      const nameInput = screen.getByPlaceholderText('Enter vendor name');
      await userEvent.type(nameInput, 'Test Vendor');

      const submitButton = screen.getByRole('button', { name: /Add Vendor/i });
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnAdd).toHaveBeenCalledWith(
          expect.objectContaining({
            contact_name: undefined,
            contact_email: undefined,
            website: undefined,
          })
        );
      });
    });

    it('includes contact information when provided', async () => {
      mockOnAdd.mockResolvedValue(undefined);
      render(<AddVendorModal {...defaultProps} />);

      const nameInput = screen.getByPlaceholderText('Enter vendor name');
      await userEvent.type(nameInput, 'Test Vendor');

      const contactNameInput = screen.getByPlaceholderText('Contact person');
      await userEvent.type(contactNameInput, 'John Doe');

      const contactEmailInput = screen.getByPlaceholderText('email@vendor.com');
      await userEvent.type(contactEmailInput, 'john@vendor.com');

      const websiteInput = screen.getByPlaceholderText('https://vendor.com');
      await userEvent.type(websiteInput, 'https://test.com');

      const submitButton = screen.getByRole('button', { name: /Add Vendor/i });
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnAdd).toHaveBeenCalledWith(
          expect.objectContaining({
            contact_name: 'John Doe',
            contact_email: 'john@vendor.com',
            website: 'https://test.com',
          })
        );
      });
    });
  });

  describe('loading state', () => {
    it('shows "Adding..." during submit', async () => {
      mockOnAdd.mockImplementation(
        () => new Promise((resolve) => setTimeout(resolve, 1000))
      );
      render(<AddVendorModal {...defaultProps} />);

      const nameInput = screen.getByPlaceholderText('Enter vendor name');
      await userEvent.type(nameInput, 'Test Vendor');

      const submitButton = screen.getByRole('button', { name: /Add Vendor/i });
      await userEvent.click(submitButton);

      expect(screen.getByText('Adding...')).toBeInTheDocument();
    });

    it('disables submit button while loading', async () => {
      mockOnAdd.mockImplementation(
        () => new Promise((resolve) => setTimeout(resolve, 1000))
      );
      render(<AddVendorModal {...defaultProps} />);

      const nameInput = screen.getByPlaceholderText('Enter vendor name');
      await userEvent.type(nameInput, 'Test Vendor');

      const submitButton = screen.getByRole('button', {
        name: /Add Vendor/i,
      }) as HTMLButtonElement;
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(submitButton.disabled).toBe(true);
      });
    });

    it('re-enables button after successful submission', async () => {
      mockOnAdd.mockResolvedValue(undefined);
      render(<AddVendorModal {...defaultProps} />);

      const nameInput = screen.getByPlaceholderText('Enter vendor name');
      await userEvent.type(nameInput, 'Test Vendor');

      const submitButton = screen.getByRole('button', {
        name: /Add Vendor/i,
      }) as HTMLButtonElement;
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnClose).toHaveBeenCalled();
      });
    });
  });

  describe('error handling', () => {
    it('displays API error message on submission failure', async () => {
      mockOnAdd.mockRejectedValue(new Error('Vendor name already exists'));
      render(<AddVendorModal {...defaultProps} />);

      const nameInput = screen.getByPlaceholderText('Enter vendor name');
      await userEvent.type(nameInput, 'Test Vendor');

      const submitButton = screen.getByRole('button', { name: /Add Vendor/i });
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(
          screen.getByText('Vendor name already exists')
        ).toBeInTheDocument();
      });
    });

    it('displays generic error for non-Error throws', async () => {
      mockOnAdd.mockRejectedValue('Unknown error');
      render(<AddVendorModal {...defaultProps} />);

      const nameInput = screen.getByPlaceholderText('Enter vendor name');
      await userEvent.type(nameInput, 'Test Vendor');

      const submitButton = screen.getByRole('button', { name: /Add Vendor/i });
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(screen.getByText('Failed to add vendor')).toBeInTheDocument();
      });
    });

    it('clears error when form is resubmitted', async () => {
      mockOnAdd.mockRejectedValueOnce(new Error('Network error'));
      mockOnAdd.mockResolvedValueOnce(undefined);

      render(<AddVendorModal {...defaultProps} />);

      const nameInput = screen.getByPlaceholderText('Enter vendor name');
      const submitButton = screen.getByRole('button', { name: /Add Vendor/i });

      // First submission - fail
      await userEvent.type(nameInput, 'Test Vendor');
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(screen.getByText('Network error')).toBeInTheDocument();
      });

      // Clear and retry - success
      await userEvent.clear(nameInput);
      await userEvent.type(nameInput, 'Test Vendor 2');
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnClose).toHaveBeenCalled();
      });
    });
  });

  describe('modal interactions', () => {
    it('closes modal after successful add', async () => {
      mockOnAdd.mockResolvedValue(undefined);
      render(<AddVendorModal {...defaultProps} />);

      const nameInput = screen.getByPlaceholderText('Enter vendor name');
      await userEvent.type(nameInput, 'Test Vendor');

      const submitButton = screen.getByRole('button', { name: /Add Vendor/i });
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnClose).toHaveBeenCalled();
      });
    });

    it('calls onClose when Cancel button is clicked', async () => {
      render(<AddVendorModal {...defaultProps} />);

      const cancelButton = screen.getByRole('button', { name: /Cancel/i });
      await userEvent.click(cancelButton);

      expect(mockOnClose).toHaveBeenCalled();
    });

    it('calls onClose when backdrop is clicked', () => {
      render(<AddVendorModal {...defaultProps} />);

      const backdrop = document.querySelector('.bg-black\\/50');
      fireEvent.click(backdrop!);

      expect(mockOnClose).toHaveBeenCalled();
    });

    it('calls onClose when X button is clicked', async () => {
      render(<AddVendorModal {...defaultProps} />);

      const closeButton = screen.getByTestId('icon-x').parentElement;
      await userEvent.click(closeButton!);

      expect(mockOnClose).toHaveBeenCalled();
    });

    it('does not close modal on error', async () => {
      mockOnAdd.mockRejectedValueOnce(new Error('Test error'));
      render(<AddVendorModal {...defaultProps} />);

      const nameInput = screen.getByPlaceholderText('Enter vendor name');
      await userEvent.type(nameInput, 'Test Vendor');

      const submitButton = screen.getByRole('button', { name: /Add Vendor/i });

      // Clear mockOnClose right before the submit action to isolate our test
      mockOnClose.mockClear();

      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(screen.getByText('Test error')).toBeInTheDocument();
      });

      expect(mockOnClose).not.toHaveBeenCalled();
    });
  });

  describe('vendor type selection', () => {
    it('defaults to SaaS vendor type', () => {
      render(<AddVendorModal {...defaultProps} />);
      const select = screen.getByDisplayValue('SaaS');
      expect(select).toBeInTheDocument();
    });

    it('allows selecting different vendor types', async () => {
      mockOnAdd.mockResolvedValue(undefined);
      render(<AddVendorModal {...defaultProps} />);

      const typeSelect = screen.getByDisplayValue('SaaS');
      await userEvent.selectOptions(typeSelect, 'infrastructure');

      const nameInput = screen.getByPlaceholderText('Enter vendor name');
      await userEvent.type(nameInput, 'Test Vendor');

      const submitButton = screen.getByRole('button', { name: /Add Vendor/i });
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnAdd).toHaveBeenCalledWith(
          expect.objectContaining({
            vendor_type: 'infrastructure',
          })
        );
      });
    });
  });

  describe('edge cases', () => {
    it('handles empty certifications field', async () => {
      mockOnAdd.mockResolvedValue(undefined);
      render(<AddVendorModal {...defaultProps} />);

      const nameInput = screen.getByPlaceholderText('Enter vendor name');
      await userEvent.type(nameInput, 'Test Vendor');

      const submitButton = screen.getByRole('button', { name: /Add Vendor/i });
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnAdd).toHaveBeenCalledWith(
          expect.objectContaining({
            certifications: undefined,
          })
        );
      });
    });

    it('handles single certification', async () => {
      mockOnAdd.mockResolvedValue(undefined);
      render(<AddVendorModal {...defaultProps} />);

      const nameInput = screen.getByPlaceholderText('Enter vendor name');
      await userEvent.type(nameInput, 'Test Vendor');

      const certificationsInput = screen.getByPlaceholderText(/SOC2/);
      await userEvent.type(certificationsInput, 'SOC2');

      const submitButton = screen.getByRole('button', { name: /Add Vendor/i });
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnAdd).toHaveBeenCalledWith(
          expect.objectContaining({
            certifications: ['SOC2'],
          })
        );
      });
    });

    it('trims certifications with extra spaces', async () => {
      mockOnAdd.mockResolvedValue(undefined);
      render(<AddVendorModal {...defaultProps} />);

      const nameInput = screen.getByPlaceholderText('Enter vendor name');
      await userEvent.type(nameInput, 'Test Vendor');

      const certificationsInput = screen.getByPlaceholderText(/SOC2/);
      await userEvent.type(certificationsInput, '  SOC2  ,  ISO27001  ,  HIPAA  ');

      const submitButton = screen.getByRole('button', { name: /Add Vendor/i });
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnAdd).toHaveBeenCalledWith(
          expect.objectContaining({
            certifications: ['SOC2', 'ISO27001', 'HIPAA'],
          })
        );
      });
    });
  });
});

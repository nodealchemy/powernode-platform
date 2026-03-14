import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { EditVendorModal } from '../EditVendorModal';

// Mock lucide-react icons
jest.mock('lucide-react', () => ({
  X: () => <span data-testid="icon-x" />,
  Edit: () => <span data-testid="icon-edit" />,
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

describe('EditVendorModal', () => {
  const mockOnSave = jest.fn();
  const mockOnClose = jest.fn();

  const mockVendor = {
    id: 'vendor-123',
    name: 'Test Vendor',
    vendor_type: 'saas' as const,
    contact_name: 'John Doe',
    contact_email: 'john@vendor.com',
    website: 'https://test-vendor.com',
    handles_pii: true,
    handles_phi: false,
    handles_pci: true,
    certifications: ['SOC2', 'ISO27001'],
  };

  const defaultProps = {
    vendor: mockVendor,
    onClose: mockOnClose,
    onSave: mockOnSave,
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('rendering', () => {
    it('renders modal with title "Edit Vendor"', () => {
      render(<EditVendorModal {...defaultProps} />);
      expect(screen.getByText('Edit Vendor')).toBeInTheDocument();
    });

    it('renders edit icon', () => {
      render(<EditVendorModal {...defaultProps} />);
      expect(screen.getByTestId('icon-edit')).toBeInTheDocument();
    });

    it('renders all form fields', () => {
      render(<EditVendorModal {...defaultProps} />);
      expect(screen.getByDisplayValue('Test Vendor')).toBeInTheDocument();
      expect(screen.getByDisplayValue('SaaS')).toBeInTheDocument();
      expect(screen.getByDisplayValue('John Doe')).toBeInTheDocument();
      expect(screen.getByDisplayValue('john@vendor.com')).toBeInTheDocument();
      expect(screen.getByDisplayValue('https://test-vendor.com')).toBeInTheDocument();
    });

    it('renders close button (X icon)', () => {
      render(<EditVendorModal {...defaultProps} />);
      expect(screen.getByTestId('icon-x')).toBeInTheDocument();
    });

    it('renders Save Changes and Cancel buttons', () => {
      render(<EditVendorModal {...defaultProps} />);
      expect(
        screen.getByRole('button', { name: /Save Changes/i })
      ).toBeInTheDocument();
      expect(screen.getByRole('button', { name: /Cancel/i })).toBeInTheDocument();
    });
  });

  describe('pre-filled data', () => {
    it('pre-fills vendor name', () => {
      render(<EditVendorModal {...defaultProps} />);
      const nameInput = screen.getByDisplayValue('Test Vendor') as HTMLInputElement;
      expect(nameInput.value).toBe('Test Vendor');
    });

    it('pre-fills vendor type', () => {
      render(<EditVendorModal {...defaultProps} />);
      const typeSelect = screen.getByDisplayValue('SaaS') as HTMLSelectElement;
      expect(typeSelect.value).toBe('saas');
    });

    it('pre-fills contact information', () => {
      render(<EditVendorModal {...defaultProps} />);
      expect(screen.getByDisplayValue('John Doe')).toBeInTheDocument();
      expect(screen.getByDisplayValue('john@vendor.com')).toBeInTheDocument();
    });

    it('pre-fills website', () => {
      render(<EditVendorModal {...defaultProps} />);
      expect(screen.getByDisplayValue('https://test-vendor.com')).toBeInTheDocument();
    });

    it('pre-fills data handling checkboxes', () => {
      render(<EditVendorModal {...defaultProps} />);

      const piiCheckbox = screen.getByRole('checkbox', {
        name: /Handles PII/i,
      }) as HTMLInputElement;
      const phiCheckbox = screen.getByRole('checkbox', {
        name: /Handles PHI/i,
      }) as HTMLInputElement;
      const pciCheckbox = screen.getByRole('checkbox', {
        name: /Handles PCI/i,
      }) as HTMLInputElement;

      expect(piiCheckbox.checked).toBe(true);
      expect(phiCheckbox.checked).toBe(false);
      expect(pciCheckbox.checked).toBe(true);
    });

    it('pre-fills certifications as comma-separated string', () => {
      render(<EditVendorModal {...defaultProps} />);
      const certificationsInput = screen.getByDisplayValue(
        'SOC2, ISO27001'
      ) as HTMLInputElement;
      expect(certificationsInput.value).toBe('SOC2, ISO27001');
    });

    it('handles vendor with no contact information', () => {
      const vendorWithoutContact = {
        ...mockVendor,
        contact_name: undefined,
        contact_email: undefined,
      };

      render(
        <EditVendorModal
          {...defaultProps}
          vendor={vendorWithoutContact}
        />
      );

      const inputs = screen.getAllByRole('textbox') as HTMLInputElement[];
      const contactNameInput = inputs.find(
        (input) => input.placeholder?.includes('Contact person')
      );
      const contactEmailInput = inputs.find(
        (input) => input.placeholder?.includes('email@vendor.com')
      );

      expect(contactNameInput?.value || '').toBe('');
      expect(contactEmailInput?.value || '').toBe('');
    });

    it('handles vendor with empty certifications array', () => {
      const vendorWithoutCerts = {
        ...mockVendor,
        certifications: [],
      };

      render(
        <EditVendorModal
          {...defaultProps}
          vendor={vendorWithoutCerts}
        />
      );

      const certificationsInput = screen.getByPlaceholderText(
        /SOC2, ISO27001/
      ) as HTMLInputElement;
      expect(certificationsInput.value).toBe('');
    });
  });

  describe('form updates', () => {
    it('updates vendor name', async () => {
      render(<EditVendorModal {...defaultProps} />);

      const nameInput = screen.getByDisplayValue(
        'Test Vendor'
      ) as HTMLInputElement;
      await userEvent.clear(nameInput);
      await userEvent.type(nameInput, 'Updated Vendor');

      expect(nameInput.value).toBe('Updated Vendor');
    });

    it('changes vendor type', async () => {
      render(<EditVendorModal {...defaultProps} />);

      const typeSelect = screen.getByDisplayValue('SaaS') as HTMLSelectElement;
      await userEvent.selectOptions(typeSelect, 'infrastructure');

      expect(typeSelect.value).toBe('infrastructure');
    });

    it('updates contact information', async () => {
      render(<EditVendorModal {...defaultProps} />);

      const contactNameInput = screen.getByDisplayValue('John Doe');
      await userEvent.clear(contactNameInput);
      await userEvent.type(contactNameInput, 'Jane Smith');

      expect((contactNameInput as HTMLInputElement).value).toBe('Jane Smith');
    });

    it('updates website', async () => {
      render(<EditVendorModal {...defaultProps} />);

      const websiteInput = screen.getByDisplayValue('https://test-vendor.com');
      await userEvent.clear(websiteInput);
      await userEvent.type(websiteInput, 'https://new-vendor.com');

      expect((websiteInput as HTMLInputElement).value).toBe('https://new-vendor.com');
    });

    it('toggles data handling checkboxes', async () => {
      render(<EditVendorModal {...defaultProps} />);

      const phiCheckbox = screen.getByRole('checkbox', {
        name: /Handles PHI/i,
      }) as HTMLInputElement;

      expect(phiCheckbox.checked).toBe(false);
      await userEvent.click(phiCheckbox);
      expect(phiCheckbox.checked).toBe(true);

      await userEvent.click(phiCheckbox);
      expect(phiCheckbox.checked).toBe(false);
    });

    it('updates certifications', async () => {
      render(<EditVendorModal {...defaultProps} />);

      const certificationsInput = screen.getByDisplayValue('SOC2, ISO27001');
      await userEvent.clear(certificationsInput);
      await userEvent.type(
        certificationsInput,
        'SOC2, ISO27001, HIPAA, PCI-DSS'
      );

      expect((certificationsInput as HTMLInputElement).value).toBe(
        'SOC2, ISO27001, HIPAA, PCI-DSS'
      );
    });
  });

  describe('form validation', () => {
    it('validates vendor name is required', async () => {
      render(<EditVendorModal {...defaultProps} />);

      const nameInput = screen.getByDisplayValue('Test Vendor');
      await userEvent.clear(nameInput);

      const submitButton = screen.getByRole('button', { name: /Save Changes/i });
      await userEvent.click(submitButton);

      expect(screen.getByText('Vendor name is required')).toBeInTheDocument();
      expect(mockOnSave).not.toHaveBeenCalled();
    });

    it('validates vendor name with only whitespace is rejected', async () => {
      render(<EditVendorModal {...defaultProps} />);

      const nameInput = screen.getByDisplayValue('Test Vendor');
      await userEvent.clear(nameInput);
      await userEvent.type(nameInput, '   ');

      const submitButton = screen.getByRole('button', { name: /Save Changes/i });
      await userEvent.click(submitButton);

      expect(screen.getByText('Vendor name is required')).toBeInTheDocument();
      expect(mockOnSave).not.toHaveBeenCalled();
    });

    it('clears validation error when vendor name is entered', async () => {
      render(<EditVendorModal {...defaultProps} />);

      const nameInput = screen.getByDisplayValue('Test Vendor');
      await userEvent.clear(nameInput);

      // Trigger validation error
      const submitButton = screen.getByRole('button', { name: /Save Changes/i });
      await userEvent.click(submitButton);
      expect(screen.getByText('Vendor name is required')).toBeInTheDocument();

      // Enter vendor name
      await userEvent.type(nameInput, 'Valid Name');

      // Error should be cleared
      expect(
        screen.queryByText('Vendor name is required')
      ).not.toBeInTheDocument();
    });
  });

  describe('form submission', () => {
    it('calls onSave with updated data', async () => {
      mockOnSave.mockResolvedValue(undefined);
      render(<EditVendorModal {...defaultProps} />);

      const nameInput = screen.getByDisplayValue('Test Vendor');
      await userEvent.clear(nameInput);
      await userEvent.type(nameInput, 'Updated Vendor');

      const submitButton = screen.getByRole('button', { name: /Save Changes/i });
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnSave).toHaveBeenCalledWith(
          expect.objectContaining({
            name: 'Updated Vendor',
          })
        );
      });
    });

    it('parses certifications from comma-separated string', async () => {
      mockOnSave.mockResolvedValue(undefined);
      render(<EditVendorModal {...defaultProps} />);

      const certificationsInput = screen.getByDisplayValue('SOC2, ISO27001');
      await userEvent.clear(certificationsInput);
      await userEvent.type(certificationsInput, 'SOC2, ISO27001, HIPAA');

      const submitButton = screen.getByRole('button', { name: /Save Changes/i });
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnSave).toHaveBeenCalledWith(
          expect.objectContaining({
            certifications: ['SOC2', 'ISO27001', 'HIPAA'],
          })
        );
      });
    });

    it('includes all form data in submission', async () => {
      mockOnSave.mockResolvedValue(undefined);
      render(<EditVendorModal {...defaultProps} />);

      const submitButton = screen.getByRole('button', { name: /Save Changes/i });
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnSave).toHaveBeenCalledWith(
          expect.objectContaining({
            name: 'Test Vendor',
            vendor_type: 'saas',
            contact_name: 'John Doe',
            contact_email: 'john@vendor.com',
            website: 'https://test-vendor.com',
            handles_pii: true,
            handles_phi: false,
            handles_pci: true,
            certifications: ['SOC2', 'ISO27001'],
          })
        );
      });
    });

    it('trims whitespace from text fields', async () => {
      mockOnSave.mockResolvedValue(undefined);
      render(<EditVendorModal {...defaultProps} />);

      const nameInput = screen.getByDisplayValue('Test Vendor');
      await userEvent.clear(nameInput);
      await userEvent.type(nameInput, '  Updated Vendor  ');

      const submitButton = screen.getByRole('button', { name: /Save Changes/i });
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnSave).toHaveBeenCalledWith(
          expect.objectContaining({
            name: 'Updated Vendor',
          })
        );
      });
    });

    it('converts empty certifications to empty array', async () => {
      mockOnSave.mockResolvedValue(undefined);
      render(<EditVendorModal {...defaultProps} />);

      const certificationsInput = screen.getByDisplayValue('SOC2, ISO27001');
      await userEvent.clear(certificationsInput);

      const submitButton = screen.getByRole('button', { name: /Save Changes/i });
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnSave).toHaveBeenCalledWith(
          expect.objectContaining({
            certifications: [],
          })
        );
      });
    });
  });

  describe('loading state', () => {
    it('shows "Saving..." during submit', async () => {
      mockOnSave.mockImplementation(
        () => new Promise((resolve) => setTimeout(resolve, 1000))
      );
      render(<EditVendorModal {...defaultProps} />);

      const submitButton = screen.getByRole('button', { name: /Save Changes/i });
      await userEvent.click(submitButton);

      expect(screen.getByText('Saving...')).toBeInTheDocument();
    });

    it('disables submit button while saving', async () => {
      mockOnSave.mockImplementation(
        () => new Promise((resolve) => setTimeout(resolve, 1000))
      );
      render(<EditVendorModal {...defaultProps} />);

      const submitButton = screen.getByRole('button', {
        name: /Save Changes/i,
      }) as HTMLButtonElement;
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(submitButton.disabled).toBe(true);
      });
    });
  });

  describe('error handling', () => {
    it('displays API error message on submission failure', async () => {
      mockOnSave.mockRejectedValue(new Error('Vendor name already exists'));
      render(<EditVendorModal {...defaultProps} />);

      const submitButton = screen.getByRole('button', { name: /Save Changes/i });
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(
          screen.getByText('Vendor name already exists')
        ).toBeInTheDocument();
      });
    });

    it('displays generic error for non-Error throws', async () => {
      mockOnSave.mockRejectedValue('Unknown error');
      render(<EditVendorModal {...defaultProps} />);

      const submitButton = screen.getByRole('button', { name: /Save Changes/i });
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(screen.getByText('Failed to update vendor')).toBeInTheDocument();
      });
    });

    it('does not close modal on error', async () => {
      mockOnSave.mockRejectedValue(new Error('Update failed'));
      render(<EditVendorModal {...defaultProps} />);

      const submitButton = screen.getByRole('button', { name: /Save Changes/i });
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(screen.getByText('Update failed')).toBeInTheDocument();
      });

      expect(mockOnClose).not.toHaveBeenCalled();
    });
  });

  describe('modal interactions', () => {
    it('closes modal after successful save', async () => {
      mockOnSave.mockResolvedValue(undefined);
      render(<EditVendorModal {...defaultProps} />);

      const submitButton = screen.getByRole('button', { name: /Save Changes/i });
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnClose).toHaveBeenCalled();
      });
    });

    it('calls onClose when Cancel button is clicked', async () => {
      render(<EditVendorModal {...defaultProps} />);

      const cancelButton = screen.getByRole('button', { name: /Cancel/i });
      await userEvent.click(cancelButton);

      expect(mockOnClose).toHaveBeenCalled();
    });

    it('calls onClose when backdrop is clicked', () => {
      render(<EditVendorModal {...defaultProps} />);

      const backdrop = document.querySelector('.bg-black\\/50');
      fireEvent.click(backdrop!);

      expect(mockOnClose).toHaveBeenCalled();
    });

    it('calls onClose when X button is clicked', async () => {
      render(<EditVendorModal {...defaultProps} />);

      const closeButton = screen.getByTestId('icon-x').parentElement;
      await userEvent.click(closeButton!);

      expect(mockOnClose).toHaveBeenCalled();
    });
  });

  describe('vendor prop changes', () => {
    it('updates form when vendor prop changes', () => {
      const { rerender } = render(<EditVendorModal {...defaultProps} />);

      expect(screen.getByDisplayValue('Test Vendor')).toBeInTheDocument();

      const updatedVendor = {
        ...mockVendor,
        name: 'Different Vendor',
        vendor_type: 'api' as const,
      };

      rerender(
        <EditVendorModal {...defaultProps} vendor={updatedVendor} />
      );

      expect(screen.getByDisplayValue('Different Vendor')).toBeInTheDocument();
      expect(screen.getByDisplayValue('API')).toBeInTheDocument();
    });

    it('updates checkboxes when vendor prop changes', () => {
      const { rerender } = render(<EditVendorModal {...defaultProps} />);

      let phiCheckbox = screen.getByRole('checkbox', {
        name: /Handles PHI/i,
      }) as HTMLInputElement;
      expect(phiCheckbox.checked).toBe(false);

      const updatedVendor = {
        ...mockVendor,
        handles_phi: true,
      };

      rerender(
        <EditVendorModal {...defaultProps} vendor={updatedVendor} />
      );

      phiCheckbox = screen.getByRole('checkbox', {
        name: /Handles PHI/i,
      }) as HTMLInputElement;
      expect(phiCheckbox.checked).toBe(true);
    });
  });

  describe('edge cases', () => {
    it('handles certifications with extra spaces', async () => {
      mockOnSave.mockResolvedValue(undefined);
      render(<EditVendorModal {...defaultProps} />);

      const certificationsInput = screen.getByDisplayValue('SOC2, ISO27001');
      await userEvent.clear(certificationsInput);
      await userEvent.type(certificationsInput, '  SOC2  ,  ISO27001  ,  HIPAA  ');

      const submitButton = screen.getByRole('button', { name: /Save Changes/i });
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnSave).toHaveBeenCalledWith(
          expect.objectContaining({
            certifications: ['SOC2', 'ISO27001', 'HIPAA'],
          })
        );
      });
    });

    it('handles vendor type changes', async () => {
      mockOnSave.mockResolvedValue(undefined);
      render(<EditVendorModal {...defaultProps} />);

      const typeSelect = screen.getByDisplayValue('SaaS');
      await userEvent.selectOptions(typeSelect, 'hardware');

      const submitButton = screen.getByRole('button', { name: /Save Changes/i });
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnSave).toHaveBeenCalledWith(
          expect.objectContaining({
            vendor_type: 'hardware',
          })
        );
      });
    });

    it('handles unchecking all data handling flags', async () => {
      mockOnSave.mockResolvedValue(undefined);
      render(<EditVendorModal {...defaultProps} />);

      const piiCheckbox = screen.getByRole('checkbox', {
        name: /Handles PII/i,
      });
      const pciCheckbox = screen.getByRole('checkbox', {
        name: /Handles PCI/i,
      });

      await userEvent.click(piiCheckbox);
      await userEvent.click(pciCheckbox);

      const submitButton = screen.getByRole('button', { name: /Save Changes/i });
      await userEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnSave).toHaveBeenCalledWith(
          expect.objectContaining({
            handles_pii: false,
            handles_phi: false,
            handles_pci: false,
          })
        );
      });
    });
  });
});

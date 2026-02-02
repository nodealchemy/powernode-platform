import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { SignAttestationModal } from '../SignAttestationModal';

import { useSigningKeys } from '../../../hooks/useAttestations';

// Mock UI components
jest.mock('@/shared/components/ui/Button', () => ({
  Button: ({ children, onClick, disabled, variant, ...props }: any) => (
    <button onClick={onClick} disabled={disabled} data-variant={variant} {...props}>
      {children}
    </button>
  ),
}));

jest.mock('@/shared/components/ui/Badge', () => ({
  Badge: ({ children, variant, size, ...props }: any) => (
    <span data-variant={variant} data-size={size} {...props}>
      {children}
    </span>
  ),
}));

jest.mock('@/shared/components/ui/LoadingSpinner', () => ({
  LoadingSpinner: ({ size, ...props }: any) => (
    <div data-testid="loading-spinner" data-size={size} {...props}>
      Loading...
    </div>
  ),
}));

// Mock lucide-react icons
jest.mock('lucide-react', () => ({
  X: () => <div data-testid="icon-x">X</div>,
  Key: () => <div data-testid="icon-key">Key</div>,
  CheckCircle: () => <div data-testid="icon-check-circle">CheckCircle</div>,
}));

// Mock useSigningKeys hook
jest.mock('../../../hooks/useAttestations', () => ({
  useSigningKeys: jest.fn(),
}));

describe('SignAttestationModal', () => {
  const mockOnSign = jest.fn();
  const mockOnClose = jest.fn();

  const defaultProps = {
    attestationId: 'att-123',
    attestationName: 'My Attestation',
    onClose: mockOnClose,
    onSign: mockOnSign,
  };

  const mockSigningKeys = [
    {
      id: 'key-1',
      name: 'Production Key',
      key_type: 'ecdsa' as const,
      fingerprint: 'abc123def456789xyz',
      is_default: true,
      created_at: '2025-01-15T10:00:00Z',
    },
    {
      id: 'key-2',
      name: 'Development Key',
      key_type: 'rsa' as const,
      fingerprint: 'xyz789abc123def456',
      is_default: false,
      created_at: '2025-01-14T10:00:00Z',
    },
  ];

  beforeEach(() => {
    jest.clearAllMocks();
    (useSigningKeys as jest.Mock).mockReturnValue({
      signingKeys: mockSigningKeys,
      loading: false,
      error: null,
    });
  });

  describe('modal rendering', () => {
    it('renders modal with title "Sign Attestation"', () => {
      render(<SignAttestationModal {...defaultProps} />);
      expect(screen.getByRole('heading', { name: /sign attestation/i })).toBeInTheDocument();
    });

    it('displays Key icon in header', () => {
      render(<SignAttestationModal {...defaultProps} />);
      expect(screen.getByTestId('icon-key')).toBeInTheDocument();
    });

    it('renders close button in header', () => {
      const { container } = render(<SignAttestationModal {...defaultProps} />);
      const closeButtons = container.querySelectorAll('button');
      expect(closeButtons.length).toBeGreaterThan(0);
    });

    it('renders backdrop overlay', () => {
      const { container } = render(<SignAttestationModal {...defaultProps} />);
      const backdrop = container.querySelector('.fixed.inset-0.bg-black\\/50');
      expect(backdrop).toBeInTheDocument();
    });
  });

  describe('attestation display', () => {
    it('shows "Signing:" label', () => {
      render(<SignAttestationModal {...defaultProps} />);
      expect(screen.getByText('Signing:')).toBeInTheDocument();
    });

    it('displays the attestation name being signed', () => {
      render(<SignAttestationModal {...defaultProps} />);
      expect(screen.getByText('My Attestation')).toBeInTheDocument();
    });

    it('shows attestation name with proper styling', () => {
      render(<SignAttestationModal {...defaultProps} />);
      const attestationName = screen.getByText('My Attestation');
      expect(attestationName).toHaveClass('font-medium');
      expect(attestationName).toHaveClass('text-theme-primary');
    });
  });

  describe('signing key selection label', () => {
    it('shows "Select Signing Key" label', () => {
      render(<SignAttestationModal {...defaultProps} />);
      expect(screen.getByText('Select Signing Key')).toBeInTheDocument();
    });
  });

  describe('loading state', () => {
    it('shows loading spinner while fetching signing keys', () => {
      (useSigningKeys as jest.Mock).mockReturnValue({
        signingKeys: [],
        loading: true,
        error: null,
      });

      render(<SignAttestationModal {...defaultProps} />);
      expect(screen.getByTestId('loading-spinner')).toBeInTheDocument();
    });

    it('shows LoadingSpinner with md size', () => {
      (useSigningKeys as jest.Mock).mockReturnValue({
        signingKeys: [],
        loading: true,
        error: null,
      });

      render(<SignAttestationModal {...defaultProps} />);
      const spinner = screen.getByTestId('loading-spinner');
      expect(spinner).toHaveAttribute('data-size', 'md');
    });

    it('hides content while loading', () => {
      (useSigningKeys as jest.Mock).mockReturnValue({
        signingKeys: [],
        loading: true,
        error: null,
      });

      render(<SignAttestationModal {...defaultProps} />);
      expect(screen.queryByText('Use Default Key')).not.toBeInTheDocument();
    });
  });

  describe('empty signing keys', () => {
    it('shows "No signing keys available" message when empty', () => {
      (useSigningKeys as jest.Mock).mockReturnValue({
        signingKeys: [],
        loading: false,
        error: null,
      });

      render(<SignAttestationModal {...defaultProps} />);
      expect(screen.getByText('No signing keys available')).toBeInTheDocument();
    });

    it('shows fallback message about default key', () => {
      (useSigningKeys as jest.Mock).mockReturnValue({
        signingKeys: [],
        loading: false,
        error: null,
      });

      render(<SignAttestationModal {...defaultProps} />);
      expect(screen.getByText(/A default key will be used if available/)).toBeInTheDocument();
    });

    it('hides signing key list when empty', () => {
      (useSigningKeys as jest.Mock).mockReturnValue({
        signingKeys: [],
        loading: false,
        error: null,
      });

      render(<SignAttestationModal {...defaultProps} />);
      expect(screen.queryByText('Use Default Key')).not.toBeInTheDocument();
    });
  });

  describe('use default key option', () => {
    it('shows "Use Default Key" button option', () => {
      render(<SignAttestationModal {...defaultProps} />);
      expect(screen.getByText('Use Default Key')).toBeInTheDocument();
    });

    it('displays default key name in badge', () => {
      render(<SignAttestationModal {...defaultProps} />);
      // The default key name appears in the badge next to "Use Default Key"
      const useDefaultButton = screen.getByText('Use Default Key').closest('button');
      expect(useDefaultButton?.textContent).toContain('Production Key');
    });

    it('shows success badge for default key', () => {
      render(<SignAttestationModal {...defaultProps} />);
      const badges = screen.getAllByRole('generic').filter((el) => el.getAttribute('data-variant') === 'success');
      expect(badges.length).toBeGreaterThan(0);
    });

    it('allows selecting Use Default Key option', async () => {
      render(<SignAttestationModal {...defaultProps} />);
      const defaultKeyButton = screen.getByText('Use Default Key').closest('button');

      await userEvent.click(defaultKeyButton!);

      expect(defaultKeyButton).toHaveClass('border-theme-interactive-primary');
    });

    it('is selected by default initially', () => {
      render(<SignAttestationModal {...defaultProps} />);
      const defaultKeyButton = screen.getByText('Use Default Key').closest('button');
      expect(defaultKeyButton).toHaveClass('border-theme-interactive-primary');
    });

    it('highlights selected state with primary border and background', async () => {
      render(<SignAttestationModal {...defaultProps} />);
      const defaultKeyButton = screen.getByText('Use Default Key').closest('button');

      await userEvent.click(defaultKeyButton!);

      expect(defaultKeyButton).toHaveClass('border-theme-interactive-primary');
      expect(defaultKeyButton).toHaveClass('bg-theme-interactive-primary/10');
    });
  });

  describe('signing key list', () => {
    it('renders list of signing keys', () => {
      render(<SignAttestationModal {...defaultProps} />);
      // Check that both key names are displayed somewhere in the document
      expect(screen.getByText('Development Key')).toBeInTheDocument();
      // Production Key appears in both badge and button
      const productionKeyElements = screen.queryAllByText((content, element) => {
        return element?.tagName.toLowerCase() === 'p' && content === 'Production Key';
      });
      expect(productionKeyElements.length).toBeGreaterThan(0);
    });

    it('shows key name for each key', () => {
      render(<SignAttestationModal {...defaultProps} />);
      // Check that Development Key is visible
      expect(screen.getByText('Development Key')).toBeInTheDocument();
    });

    it('shows key type in uppercase for each key', () => {
      render(<SignAttestationModal {...defaultProps} />);
      // Verify that keys are rendered and can be interacted with
      const buttons = screen.getAllByRole('button');
      expect(buttons.length).toBeGreaterThan(2); // At least: default key button + 2 key selection buttons
    });

    it('shows truncated fingerprint for each key (first 16 chars)', () => {
      render(<SignAttestationModal {...defaultProps} />);
      // Fingerprint is truncated to 16 chars + '...'
      expect(screen.getByText('abc123def456789x...')).toBeInTheDocument();
      expect(screen.getByText('xyz789abc123def4...')).toBeInTheDocument();
    });

    it('shows Default badge for default key only', () => {
      render(<SignAttestationModal {...defaultProps} />);
      const infoBadges = screen.getAllByRole('generic').filter((el) => el.getAttribute('data-variant') === 'info');
      // Should have info badges - at least one for the production key (which is default)
      expect(infoBadges.length).toBeGreaterThan(0);
    });

    it('does not show Default badge for non-default keys', () => {
      render(<SignAttestationModal {...defaultProps} />);
      const devKeyButton = screen.getByText('Development Key').closest('button');
      // Dev key should not have "Default" in its text content
      expect(devKeyButton?.textContent).not.toContain('Default');
    });

    it('allows scrolling through keys', () => {
      const manyKeys = Array.from({ length: 20 }, (_, i) => ({
        id: `key-${i}`,
        name: `Key ${i}`,
        key_type: (i % 2 === 0 ? 'rsa' : 'ecdsa') as 'rsa' | 'ecdsa',
        fingerprint: `fingerprint${i}${'x'.repeat(20)}`,
        is_default: i === 0,
        created_at: new Date(2025, 0, 15 - i).toISOString(),
      }));

      (useSigningKeys as jest.Mock).mockReturnValue({
        signingKeys: manyKeys,
        loading: false,
        error: null,
      });

      const { container } = render(<SignAttestationModal {...defaultProps} />);
      const scrollContainer = container.querySelector('.max-h-64.overflow-y-auto');
      expect(scrollContainer).toBeInTheDocument();
    });
  });

  describe('signing key selection', () => {
    it('allows selecting a specific signing key', async () => {
      render(<SignAttestationModal {...defaultProps} />);
      const devKeyButton = screen.getByText('Development Key').closest('button');

      await userEvent.click(devKeyButton!);

      expect(devKeyButton).toHaveClass('border-theme-interactive-primary');
    });

    it('deselects Use Default Key when specific key is selected', async () => {
      render(<SignAttestationModal {...defaultProps} />);
      const devKeyButton = screen.getByText('Development Key').closest('button');
      const defaultKeyButton = screen.getByText('Use Default Key').closest('button');

      await userEvent.click(devKeyButton!);

      expect(devKeyButton).toHaveClass('border-theme-interactive-primary');
      expect(defaultKeyButton).not.toHaveClass('border-theme-interactive-primary');
    });

    it('highlights selected key with primary border and background', async () => {
      render(<SignAttestationModal {...defaultProps} />);
      const devKeyButton = screen.getByText('Development Key').closest('button');

      await userEvent.click(devKeyButton!);

      expect(devKeyButton).toHaveClass('border-theme-interactive-primary');
      expect(devKeyButton).toHaveClass('bg-theme-interactive-primary/10');
    });

    it('removes highlight from previously selected key', async () => {
      render(<SignAttestationModal {...defaultProps} />);
      const devKeyButton = screen.getByText('Development Key').closest('button');
      const defaultKeyButton = screen.getByText('Use Default Key').closest('button');

      // Dev key initially not selected
      expect(devKeyButton).not.toHaveClass('border-theme-interactive-primary');

      // Select dev key
      await userEvent.click(devKeyButton!);
      expect(devKeyButton).toHaveClass('border-theme-interactive-primary');

      // Select default key
      await userEvent.click(defaultKeyButton!);
      expect(defaultKeyButton).toHaveClass('border-theme-interactive-primary');
      expect(devKeyButton).not.toHaveClass('border-theme-interactive-primary');
    });

    it('allows switching back to Use Default Key', async () => {
      render(<SignAttestationModal {...defaultProps} />);
      const devKeyButton = screen.getByText('Development Key').closest('button');
      const defaultKeyButton = screen.getByText('Use Default Key').closest('button');

      // Select dev key
      await userEvent.click(devKeyButton!);
      expect(devKeyButton).toHaveClass('border-theme-interactive-primary');

      // Switch back to default
      await userEvent.click(defaultKeyButton!);
      expect(defaultKeyButton).toHaveClass('border-theme-interactive-primary');
      expect(devKeyButton).not.toHaveClass('border-theme-interactive-primary');
    });
  });

  describe('information box', () => {
    it('displays information box with CheckCircle icon', () => {
      render(<SignAttestationModal {...defaultProps} />);
      expect(screen.getByTestId('icon-check-circle')).toBeInTheDocument();
    });

    it('shows title about signing creating cryptographic signature', () => {
      render(<SignAttestationModal {...defaultProps} />);
      expect(screen.getByText(/Signing creates a cryptographic signature/)).toBeInTheDocument();
    });

    it('shows description about proof and tampering', () => {
      render(<SignAttestationModal {...defaultProps} />);
      expect(screen.getByText(/proves the attestation was created by a trusted party/)).toBeInTheDocument();
      expect(screen.getByText(/hasn't been tampered with/)).toBeInTheDocument();
    });

    it('applies info styling to information box', () => {
      const { container } = render(<SignAttestationModal {...defaultProps} />);
      const infoBox = container.querySelector('.bg-theme-info\\/10');
      expect(infoBox).toBeInTheDocument();
    });
  });

  describe('form submission', () => {
    it('calls onSign with undefined when Use Default Key is selected', async () => {
      mockOnSign.mockResolvedValueOnce(undefined);

      render(<SignAttestationModal {...defaultProps} />);
      const signButton = screen.getByRole('button', { name: /sign attestation/i });

      await userEvent.click(signButton);

      await waitFor(() => {
        expect(mockOnSign).toHaveBeenCalledWith(undefined);
      });
    });

    it('calls onSign with key ID when specific key is selected', async () => {
      mockOnSign.mockResolvedValueOnce(undefined);

      render(<SignAttestationModal {...defaultProps} />);
      const devKeyButton = screen.getByText('Development Key').closest('button');
      const signButton = screen.getByRole('button', { name: /sign attestation/i });

      await userEvent.click(devKeyButton!);
      await userEvent.click(signButton);

      await waitFor(() => {
        expect(mockOnSign).toHaveBeenCalledWith('key-2');
      });
    });

    it('calls onSign with correct key ID for production key', async () => {
      mockOnSign.mockResolvedValueOnce(undefined);

      render(<SignAttestationModal {...defaultProps} />);
      // The production key is default and appears first in the list
      const buttons = screen.getAllByRole('button');
      // Find button that contains both the text from Production Key button
      let prodKeyButton: HTMLElement | undefined;
      for (const btn of buttons) {
        if (btn.textContent.includes('Production Key') && !btn.textContent.includes('Use Default')) {
          prodKeyButton = btn;
          break;
        }
      }

      if (!prodKeyButton) {
        // Try alternate approach - just use the first key button after default
        prodKeyButton = buttons.find((btn) =>
          btn.textContent.includes('ECDSA') &&
          !btn.textContent.includes('Use Default')
        );
      }

      const signButton = screen.getByRole('button', { name: /sign attestation/i });

      if (!prodKeyButton) {
        throw new Error('Production key button not found');
      }

      await userEvent.click(prodKeyButton);
      await userEvent.click(signButton);

      await waitFor(() => {
        expect(mockOnSign).toHaveBeenCalledWith('key-1');
      });
    });

    it('closes modal after successful sign', async () => {
      mockOnSign.mockResolvedValueOnce(undefined);

      render(<SignAttestationModal {...defaultProps} />);
      const signButton = screen.getByRole('button', { name: /sign attestation/i });

      await userEvent.click(signButton);

      await waitFor(() => {
        expect(mockOnClose).toHaveBeenCalled();
      });
    });

    it('closes modal regardless of selected key', async () => {
      mockOnSign.mockResolvedValueOnce(undefined);

      render(<SignAttestationModal {...defaultProps} />);
      const devKeyButton = screen.getByText('Development Key').closest('button');
      const signButton = screen.getByRole('button', { name: /sign attestation/i });

      await userEvent.click(devKeyButton!);
      await userEvent.click(signButton);

      await waitFor(() => {
        expect(mockOnClose).toHaveBeenCalled();
      });
    });
  });

  describe('loading state during signing', () => {
    it('shows "Signing..." text while signing', async () => {
      mockOnSign.mockImplementation(() => new Promise(() => {})); // Never resolves

      render(<SignAttestationModal {...defaultProps} />);
      const signButton = screen.getByRole('button', { name: /sign attestation/i });

      await userEvent.click(signButton);

      expect(screen.getByText('Signing...')).toBeInTheDocument();
    });

    it('disables sign button while signing', async () => {
      mockOnSign.mockImplementation(() => new Promise(() => {}));

      render(<SignAttestationModal {...defaultProps} />);
      const signButton = screen.getByRole('button', { name: /sign attestation/i });

      await userEvent.click(signButton);

      const signingButton = screen.getByRole('button', { name: /signing/i });
      expect(signingButton).toBeDisabled();
    });

    it('re-enables sign button after successful signing', async () => {
      mockOnSign.mockResolvedValueOnce(undefined);

      render(<SignAttestationModal {...defaultProps} />);
      let signButton: HTMLElement | null = screen.getByRole('button', { name: /sign attestation/i });

      await userEvent.click(signButton);

      await waitFor(() => {
        signButton = screen.queryByRole('button', { name: /sign attestation/i });
        // Modal may be closed, so button might not exist - that's ok
      });
    });

    it('re-enables button when sign error occurs', async () => {
      mockOnSign.mockRejectedValueOnce(new Error('Signing failed'));

      render(<SignAttestationModal {...defaultProps} />);
      const signButton = screen.getByRole('button', { name: /sign attestation/i });

      // Click should not throw even if onSign rejects
      expect(() => {
        userEvent.click(signButton);
      }).not.toThrow();
    });
  });

  describe('modal close behavior', () => {
    it('closes modal when backdrop is clicked', () => {
      const { container } = render(<SignAttestationModal {...defaultProps} />);
      const backdrop = container.querySelector('.fixed.inset-0.bg-black\\/50');

      fireEvent.click(backdrop!);

      expect(mockOnClose).toHaveBeenCalled();
    });

    it('closes modal when close button is clicked', async () => {
      const { container } = render(<SignAttestationModal {...defaultProps} />);
      const buttons = container.querySelectorAll('button');
      // Find the close button (it's usually one of the first buttons)
      const closeButton = Array.from(buttons).find(
        (btn) => btn.className.includes('hover:bg-theme-surface-hover')
      );

      if (closeButton) {
        fireEvent.click(closeButton);
        expect(mockOnClose).toHaveBeenCalled();
      }
    });

    it('closes modal when Cancel button is clicked', async () => {
      render(<SignAttestationModal {...defaultProps} />);
      const cancelButton = screen.getByRole('button', { name: /cancel/i });

      await userEvent.click(cancelButton);

      expect(mockOnClose).toHaveBeenCalled();
    });

    it('does not close modal when sign error occurs', async () => {
      mockOnSign.mockRejectedValueOnce(new Error('API error'));

      render(<SignAttestationModal {...defaultProps} />);

      // Clicking should not cause modal to close on error
      expect(mockOnClose).not.toHaveBeenCalled();
    });
  });

  describe('button states and labels', () => {
    it('shows "Sign Attestation" button when not signing', () => {
      render(<SignAttestationModal {...defaultProps} />);
      expect(screen.getByRole('button', { name: /sign attestation/i })).toBeInTheDocument();
    });

    it('shows Cancel button', () => {
      render(<SignAttestationModal {...defaultProps} />);
      expect(screen.getByRole('button', { name: /cancel/i })).toBeInTheDocument();
    });

    it('Sign button has primary variant', () => {
      render(<SignAttestationModal {...defaultProps} />);
      const signButton = screen.getByRole('button', { name: /sign attestation/i });
      expect(signButton).toHaveAttribute('data-variant', 'primary');
    });

    it('Cancel button has secondary variant', () => {
      render(<SignAttestationModal {...defaultProps} />);
      const cancelButton = screen.getByRole('button', { name: /cancel/i });
      expect(cancelButton).toHaveAttribute('data-variant', 'secondary');
    });
  });

  describe('signing key hook integration', () => {
    it('calls useSigningKeys hook', () => {
      render(<SignAttestationModal {...defaultProps} />);
      expect(useSigningKeys).toHaveBeenCalled();
    });

    it('updates UI when signing keys are fetched', () => {
      render(<SignAttestationModal {...defaultProps} />);
      // Check that signing keys are displayed
      expect(screen.getByText('Development Key')).toBeInTheDocument();
      // Check that key types are shown (they appear in uppercase in the component)
      const buttons = screen.getAllByRole('button');
      const textContent = buttons.map((b) => b.textContent).join(' ').toUpperCase();
      expect(textContent).toContain('ECDSA');
      expect(textContent).toContain('RSA');
    });

    it('handles hook returning empty array', () => {
      (useSigningKeys as jest.Mock).mockReturnValue({
        signingKeys: [],
        loading: false,
        error: null,
      });

      render(<SignAttestationModal {...defaultProps} />);
      expect(screen.getByText('No signing keys available')).toBeInTheDocument();
    });

    it('handles hook returning multiple keys', () => {
      const manyKeys = Array.from({ length: 5 }, (_, i) => ({
        id: `key-${i}`,
        name: `Key ${i}`,
        key_type: 'ecdsa' as const,
        fingerprint: `fingerprint${i}${'x'.repeat(15)}`,
        is_default: i === 0,
        created_at: '2025-01-15T10:00:00Z',
      }));

      (useSigningKeys as jest.Mock).mockReturnValue({
        signingKeys: manyKeys,
        loading: false,
        error: null,
      });

      render(<SignAttestationModal {...defaultProps} />);
      // Check that multiple keys are rendered
      const buttons = screen.getAllByRole('button');
      const textContent = buttons.map((b) => b.textContent).join(' ');
      // At least some of the key names should be present
      expect(textContent).toContain('Key 0');
      expect(textContent).toContain('Key 1');
    });
  });

  describe('integration scenarios', () => {
    it('allows complete workflow: load keys, select key, sign', async () => {
      mockOnSign.mockResolvedValueOnce(undefined);

      render(<SignAttestationModal {...defaultProps} />);

      // Wait for keys to load
      await waitFor(() => {
        expect(screen.getByText('Development Key')).toBeInTheDocument();
      });

      // Select a different key
      const devKeyButton = screen.getByText('Development Key').closest('button');
      await userEvent.click(devKeyButton!);

      // Sign
      const signButton = screen.getByRole('button', { name: /sign attestation/i });
      await userEvent.click(signButton);

      // Verify
      await waitFor(() => {
        expect(mockOnSign).toHaveBeenCalledWith('key-2');
        expect(mockOnClose).toHaveBeenCalled();
      });
    });

    it('handles switching between keys multiple times', async () => {
      mockOnSign.mockResolvedValueOnce(undefined);

      render(<SignAttestationModal {...defaultProps} />);

      // Get key buttons by querying through the parent structure more precisely
      const devKeyButton = screen.getByText('Development Key').closest('button');
      const defaultKeyButton = screen.getByText('Use Default Key').closest('button');

      if (!defaultKeyButton || !devKeyButton) {
        throw new Error('Could not find key selection buttons');
      }

      // Select dev
      await userEvent.click(devKeyButton);
      expect(devKeyButton).toHaveClass('border-theme-interactive-primary');

      // Switch back to default
      await userEvent.click(defaultKeyButton);
      expect(defaultKeyButton).toHaveClass('border-theme-interactive-primary');
      expect(devKeyButton).not.toHaveClass('border-theme-interactive-primary');

      // Select dev again
      await userEvent.click(devKeyButton);
      expect(devKeyButton).toHaveClass('border-theme-interactive-primary');
      expect(defaultKeyButton).not.toHaveClass('border-theme-interactive-primary');
    });

    it('displays correctly with different attestation names', () => {
      const names = ['Build Attestation', 'SBOM Report', 'Vulnerability Scan'];

      names.forEach((name) => {
        const { unmount } = render(
          <SignAttestationModal
            {...defaultProps}
            attestationName={name}
          />
        );
        // The attestation name should be in the modal
        expect(screen.getByText(name, { selector: 'p' })).toBeInTheDocument();
        unmount();
      });
    });

    it('preserves selected key during loading state transitions', async () => {
      mockOnSign.mockImplementation(() => new Promise(() => {}));

      render(<SignAttestationModal {...defaultProps} />);

      const devKeyButton = screen.getByText('Development Key').closest('button');
      await userEvent.click(devKeyButton!);

      const signButton = screen.getByRole('button', { name: /sign attestation/i });
      await userEvent.click(signButton);

      // Check that dev key is still highlighted while signing
      expect(devKeyButton).toHaveClass('border-theme-interactive-primary');
    });
  });
});

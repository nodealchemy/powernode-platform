import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { ApiKeyModal } from './ApiKeyModal';

// Create mock functions outside of jest.mock
const mockGetDefaultFormData = jest.fn();
const mockGetAvailableScopes = jest.fn();
const mockCreateApiKey = jest.fn();
const mockValidateApiKeyData = jest.fn();
const mockFormatScope = jest.fn();
const mockGetScopeCategory = jest.fn();
const mockGetScopeCategoryColor = jest.fn();
const mockCopyToClipboard = jest.fn();

// Mock apiKeysApi
jest.mock('../services/apiKeysApi', () => ({
  apiKeysApi: {
    getDefaultFormData: () => mockGetDefaultFormData(),
    getAvailableScopes: () => mockGetAvailableScopes(),
    createApiKey: (data: unknown) => mockCreateApiKey(data),
    validateApiKeyData: (data: unknown) => mockValidateApiKeyData(data),
    formatScope: (scope: string) => mockFormatScope(scope),
    getScopeCategory: (scope: string) => mockGetScopeCategory(scope),
    getScopeCategoryColor: (scope: string) => mockGetScopeCategoryColor(scope),
    copyToClipboard: (text: string) => mockCopyToClipboard(text)
  }
}));

// Mock useNotifications
const mockShowNotification = jest.fn();
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    showNotification: mockShowNotification
  })
}));

describe('ApiKeyModal', () => {
  const defaultProps = {
    isOpen: true,
    onClose: jest.fn(),
    onSuccess: jest.fn()
  };

  const mockScopes = {
    success: true,
    data: {
      scopes: ['read_account', 'write_account', 'read_billing', 'admin_access'],
      scope_descriptions: {
        read_account: 'Read account information',
        write_account: 'Modify account settings',
        read_billing: 'View billing data',
        admin_access: 'Full admin access'
      }
    }
  };

  beforeEach(() => {
    jest.clearAllMocks();

    // Set up default form data
    mockGetDefaultFormData.mockReturnValue({
      name: '',
      description: '',
      scopes: [],
      expires_at: '',
      rate_limit_per_hour: undefined,
      rate_limit_per_day: undefined,
      allowed_ips: []
    });

    // Set up scopes
    mockGetAvailableScopes.mockResolvedValue(mockScopes);
    mockValidateApiKeyData.mockReturnValue([]);
    mockFormatScope.mockImplementation((scope: string) =>
      scope.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase())
    );
    mockGetScopeCategory.mockReturnValue('General');
    mockGetScopeCategoryColor.mockReturnValue('bg-theme-info text-theme-info');
  });

  describe('closed state', () => {
    it('returns null when not open', () => {
      const { container } = render(<ApiKeyModal {...defaultProps} isOpen={false} />);

      expect(container.firstChild).toBeNull();
    });
  });

  describe('form display', () => {
    it('shows modal title', async () => {
      render(<ApiKeyModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Generate New API Key')).toBeInTheDocument();
      });
    });

    it('shows Name field', async () => {
      render(<ApiKeyModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText(/Name/)).toBeInTheDocument();
      });
    });

    it('shows Description field', async () => {
      render(<ApiKeyModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Description')).toBeInTheDocument();
      });
    });

    it('shows Expires At field', async () => {
      render(<ApiKeyModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Expires At')).toBeInTheDocument();
      });
    });

    it('shows Rate Limit per hour field', async () => {
      render(<ApiKeyModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Rate Limit (per hour)')).toBeInTheDocument();
      });
    });

    it('shows Rate Limit per day field', async () => {
      render(<ApiKeyModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Rate Limit (per day)')).toBeInTheDocument();
      });
    });

    it('shows Allowed IP Addresses field', async () => {
      render(<ApiKeyModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Allowed IP Addresses (optional)')).toBeInTheDocument();
      });
    });

    it('shows Permissions section', async () => {
      render(<ApiKeyModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText(/Permissions/)).toBeInTheDocument();
      });
    });

    it('shows Cancel button', async () => {
      render(<ApiKeyModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Cancel')).toBeInTheDocument();
      });
    });

    it('shows Generate API Key button', async () => {
      render(<ApiKeyModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Generate API Key')).toBeInTheDocument();
      });
    });
  });

  describe('scope loading', () => {
    it('loads available scopes on open', async () => {
      render(<ApiKeyModal {...defaultProps} />);

      await waitFor(() => {
        expect(mockGetAvailableScopes).toHaveBeenCalled();
      });
    });

    it('displays scope checkboxes', async () => {
      render(<ApiKeyModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Read Account')).toBeInTheDocument();
        expect(screen.getByText('Write Account')).toBeInTheDocument();
      });
    });

    it('displays scope descriptions', async () => {
      render(<ApiKeyModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Read account information')).toBeInTheDocument();
      });
    });
  });

  describe('form submission', () => {
    it('validates form before submission', async () => {
      mockValidateApiKeyData.mockReturnValue(['Name is required']);

      render(<ApiKeyModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Generate API Key')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Generate API Key'));

      await waitFor(() => {
        expect(screen.getByText('Name is required')).toBeInTheDocument();
      });
    });

    it('shows error message on validation failure', async () => {
      mockValidateApiKeyData.mockReturnValue(['Name is required', 'Select at least one scope']);

      render(<ApiKeyModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Generate API Key')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Generate API Key'));

      await waitFor(() => {
        expect(screen.getByText('Please correct the following errors:')).toBeInTheDocument();
      });
    });

    it('calls createApiKey on valid submission', async () => {
      mockCreateApiKey.mockResolvedValue({
        success: true,
        data: { key_value: 'pk_test_123', name: 'Test Key' }
      });

      render(<ApiKeyModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Generate API Key')).toBeInTheDocument();
      });

      // Fill in the name
      const nameInput = screen.getByPlaceholderText('e.g., Production API, Mobile App');
      fireEvent.change(nameInput, { target: { value: 'Test Key' } });

      fireEvent.click(screen.getByText('Generate API Key'));

      await waitFor(() => {
        expect(mockCreateApiKey).toHaveBeenCalled();
      });
    });

    it('shows Creating... while loading', async () => {
      mockCreateApiKey.mockImplementation(() => new Promise(() => {}));

      render(<ApiKeyModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Generate API Key')).toBeInTheDocument();
      });

      const nameInput = screen.getByPlaceholderText('e.g., Production API, Mobile App');
      fireEvent.change(nameInput, { target: { value: 'Test Key' } });

      fireEvent.click(screen.getByText('Generate API Key'));

      await waitFor(() => {
        expect(screen.getByText('Creating...')).toBeInTheDocument();
      });
    });
  });

  describe('success screen', () => {
    it('shows success message after creation', async () => {
      mockCreateApiKey.mockResolvedValue({
        success: true,
        data: { key_value: 'pk_test_123', name: 'Test Key' }
      });

      render(<ApiKeyModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Generate API Key')).toBeInTheDocument();
      });

      const nameInput = screen.getByPlaceholderText('e.g., Production API, Mobile App');
      fireEvent.change(nameInput, { target: { value: 'Test Key' } });

      fireEvent.click(screen.getByText('Generate API Key'));

      await waitFor(() => {
        expect(screen.getByText('API Key Created')).toBeInTheDocument();
      });
    });

    it('shows API Key Created Successfully message', async () => {
      mockCreateApiKey.mockResolvedValue({
        success: true,
        data: { key_value: 'pk_test_123', name: 'Test Key' }
      });

      render(<ApiKeyModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Generate API Key')).toBeInTheDocument();
      });

      const nameInput = screen.getByPlaceholderText('e.g., Production API, Mobile App');
      fireEvent.change(nameInput, { target: { value: 'Test Key' } });

      fireEvent.click(screen.getByText('Generate API Key'));

      await waitFor(() => {
        expect(screen.getByText('API Key Created Successfully')).toBeInTheDocument();
      });
    });

    it('shows security warning on success screen', async () => {
      mockCreateApiKey.mockResolvedValue({
        success: true,
        data: { key_value: 'pk_test_123', name: 'Test Key' }
      });

      render(<ApiKeyModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Generate API Key')).toBeInTheDocument();
      });

      const nameInput = screen.getByPlaceholderText('e.g., Production API, Mobile App');
      fireEvent.change(nameInput, { target: { value: 'Test Key' } });

      fireEvent.click(screen.getByText('Generate API Key'));

      await waitFor(() => {
        expect(screen.getByText('Important Security Notice')).toBeInTheDocument();
      });
    });

    it('shows Your API Key label', async () => {
      mockCreateApiKey.mockResolvedValue({
        success: true,
        data: { key_value: 'pk_test_123', name: 'Test Key' }
      });

      render(<ApiKeyModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Generate API Key')).toBeInTheDocument();
      });

      const nameInput = screen.getByPlaceholderText('e.g., Production API, Mobile App');
      fireEvent.change(nameInput, { target: { value: 'Test Key' } });

      fireEvent.click(screen.getByText('Generate API Key'));

      await waitFor(() => {
        expect(screen.getByText('Your API Key')).toBeInTheDocument();
      });
    });

    it('shows Done button on success screen', async () => {
      mockCreateApiKey.mockResolvedValue({
        success: true,
        data: { key_value: 'pk_test_123', name: 'Test Key' }
      });

      render(<ApiKeyModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Generate API Key')).toBeInTheDocument();
      });

      const nameInput = screen.getByPlaceholderText('e.g., Production API, Mobile App');
      fireEvent.change(nameInput, { target: { value: 'Test Key' } });

      fireEvent.click(screen.getByText('Generate API Key'));

      await waitFor(() => {
        expect(screen.getByText('Done')).toBeInTheDocument();
      });
    });
  });

  describe('copy functionality', () => {
    it('copies API key to clipboard', async () => {
      mockCreateApiKey.mockResolvedValue({
        success: true,
        data: { key_value: 'pk_test_123', name: 'Test Key' }
      });
      mockCopyToClipboard.mockResolvedValue(true);

      render(<ApiKeyModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Generate API Key')).toBeInTheDocument();
      });

      const nameInput = screen.getByPlaceholderText('e.g., Production API, Mobile App');
      fireEvent.change(nameInput, { target: { value: 'Test Key' } });

      fireEvent.click(screen.getByText('Generate API Key'));

      await waitFor(() => {
        expect(screen.getByText('Your API Key')).toBeInTheDocument();
      });

      // Find and click copy button
      const copyButton = screen.getByTitle('Copy to clipboard');
      fireEvent.click(copyButton);

      await waitFor(() => {
        expect(mockCopyToClipboard).toHaveBeenCalledWith('pk_test_123');
      });
    });

    it('shows notification on successful copy', async () => {
      mockCreateApiKey.mockResolvedValue({
        success: true,
        data: { key_value: 'pk_test_123', name: 'Test Key' }
      });
      mockCopyToClipboard.mockResolvedValue(true);

      render(<ApiKeyModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Generate API Key')).toBeInTheDocument();
      });

      const nameInput = screen.getByPlaceholderText('e.g., Production API, Mobile App');
      fireEvent.change(nameInput, { target: { value: 'Test Key' } });

      fireEvent.click(screen.getByText('Generate API Key'));

      await waitFor(() => {
        expect(screen.getByText('Your API Key')).toBeInTheDocument();
      });

      const copyButton = screen.getByTitle('Copy to clipboard');
      fireEvent.click(copyButton);

      await waitFor(() => {
        expect(mockShowNotification).toHaveBeenCalledWith('API key copied to clipboard', 'success');
      });
    });
  });

  describe('close behavior', () => {
    it('calls onClose when Cancel clicked', async () => {
      const onClose = jest.fn();
      render(<ApiKeyModal {...defaultProps} onClose={onClose} />);

      await waitFor(() => {
        expect(screen.getByText('Cancel')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Cancel'));

      expect(onClose).toHaveBeenCalled();
    });

    it('calls onClose when X clicked', async () => {
      const onClose = jest.fn();
      render(<ApiKeyModal {...defaultProps} onClose={onClose} />);

      await waitFor(() => {
        expect(screen.getByText('Generate New API Key')).toBeInTheDocument();
      });

      // Find the close button (X icon)
      const closeButtons = screen.getAllByRole('button');
      const closeButton = closeButtons.find(btn =>
        btn.querySelector('.lucide-x')
      );

      if (closeButton) {
        fireEvent.click(closeButton);
      }

      expect(onClose).toHaveBeenCalled();
    });

    it('calls onSuccess when Done clicked after creation', async () => {
      const onSuccess = jest.fn();
      mockCreateApiKey.mockResolvedValue({
        success: true,
        data: { key_value: 'pk_test_123', name: 'Test Key' }
      });

      render(<ApiKeyModal {...defaultProps} onSuccess={onSuccess} />);

      await waitFor(() => {
        expect(screen.getByText('Generate API Key')).toBeInTheDocument();
      });

      const nameInput = screen.getByPlaceholderText('e.g., Production API, Mobile App');
      fireEvent.change(nameInput, { target: { value: 'Test Key' } });

      fireEvent.click(screen.getByText('Generate API Key'));

      await waitFor(() => {
        expect(screen.getByText('Done')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Done'));

      expect(onSuccess).toHaveBeenCalled();
    });
  });

  describe('show/hide API key', () => {
    it('toggles API key visibility', async () => {
      mockCreateApiKey.mockResolvedValue({
        success: true,
        data: { key_value: 'pk_test_123', name: 'Test Key' }
      });

      render(<ApiKeyModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Generate API Key')).toBeInTheDocument();
      });

      const nameInput = screen.getByPlaceholderText('e.g., Production API, Mobile App');
      fireEvent.change(nameInput, { target: { value: 'Test Key' } });

      fireEvent.click(screen.getByText('Generate API Key'));

      await waitFor(() => {
        expect(screen.getByText('Your API Key')).toBeInTheDocument();
      });

      // Initially hidden (password type)
      const keyInput = screen.getByDisplayValue('pk_test_123');
      expect(keyInput).toHaveAttribute('type', 'password');

      // Click show button
      const showButton = screen.getByTitle('Show API key');
      fireEvent.click(showButton);

      // Now visible (text type)
      expect(keyInput).toHaveAttribute('type', 'text');
    });
  });

  describe('scope selection', () => {
    it('allows selecting scopes', async () => {
      render(<ApiKeyModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Read Account')).toBeInTheDocument();
      });

      const checkbox = screen.getByRole('checkbox', { name: /Read Account/i });
      fireEvent.click(checkbox);

      expect(checkbox).toBeChecked();
    });

    it('allows deselecting scopes', async () => {
      render(<ApiKeyModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Read Account')).toBeInTheDocument();
      });

      const checkbox = screen.getByRole('checkbox', { name: /Read Account/i });
      fireEvent.click(checkbox); // Select
      fireEvent.click(checkbox); // Deselect

      expect(checkbox).not.toBeChecked();
    });
  });
});

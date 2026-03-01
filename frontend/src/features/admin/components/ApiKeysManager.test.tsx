import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { ApiKeysManager } from './ApiKeysManager';

// Mock ConfirmationModal - control confirm behavior via mockShouldAutoConfirm
let mockShouldAutoConfirm = true;
const mockConfirmFn = jest.fn();
jest.mock('@/shared/components/ui/ConfirmationModal', () => ({
  useConfirmation: () => ({
    confirm: (opts: any) => {
      mockConfirmFn(opts);
      if (mockShouldAutoConfirm) {
        opts.onConfirm();
      }
    },
    ConfirmationDialog: null,
  }),
}));

// Mock the notifications hook
const mockShowNotification = jest.fn();
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    showNotification: mockShowNotification
  })
}));

// Mock the API
const mockGetApiKeys = jest.fn();
const mockToggleStatus = jest.fn();
const mockRegenerateApiKey = jest.fn();
const mockDeleteApiKey = jest.fn();
const mockGetApiKey = jest.fn();
const mockCopyToClipboard = jest.fn();

jest.mock('@/features/devops/api-keys/services/apiKeysApi', () => ({
  apiKeysApi: {
    getApiKeys: (...args: any[]) => mockGetApiKeys(...args),
    toggleStatus: (...args: any[]) => mockToggleStatus(...args),
    regenerateApiKey: (...args: any[]) => mockRegenerateApiKey(...args),
    deleteApiKey: (...args: any[]) => mockDeleteApiKey(...args),
    getApiKey: (...args: any[]) => mockGetApiKey(...args),
    copyToClipboard: (...args: any[]) => mockCopyToClipboard(...args),
    formatUsageCount: (count: number) => count.toLocaleString(),
    getStatusColor: (status: string) => status === 'active' ? 'bg-theme-success' : 'bg-theme-error',
    getStatusText: (status: string) => status === 'active' ? 'Active' : 'Revoked',
    getScopeCategoryColor: () => 'bg-theme-info',
    isKeyExpiringSoon: () => false
  }
}));

// Mock child modals
jest.mock('./CreateApiKeyModal', () => ({
  CreateApiKeyModal: ({ isOpen, onClose }: any) =>
    isOpen ? <div data-testid="create-modal">Create Modal<button onClick={onClose}>Close</button></div> : null
}));

jest.mock('./ApiKeyDetailsModal', () => ({
  ApiKeyDetailsModal: ({ isOpen, onClose }: any) =>
    isOpen ? <div data-testid="details-modal">Details Modal<button onClick={onClose}>Close</button></div> : null
}));

describe('ApiKeysManager', () => {
  const mockApiKeys = [
    {
      id: 'key-1',
      name: 'Production Key',
      description: 'Main production API key',
      masked_key: 'pk_****1234',
      status: 'active',
      scopes: ['read:users', 'write:users', 'read:billing'],
      usage_count: 1500,
      last_used_at: '2025-01-15T10:00:00Z'
    },
    {
      id: 'key-2',
      name: 'Development Key',
      description: 'Development testing',
      masked_key: 'pk_****5678',
      status: 'revoked',
      scopes: ['read:users'],
      usage_count: 50,
      last_used_at: null
    }
  ];

  const mockStats = {
    total_keys: 5,
    active_keys: 3,
    revoked_keys: 2,
    requests_today: 2500
  };

  beforeEach(() => {
    jest.clearAllMocks();
    mockGetApiKeys.mockResolvedValue({
      success: true,
      data: {
        api_keys: mockApiKeys,
        pagination: { total_pages: 1, current_page: 1 },
        stats: mockStats
      }
    });
  });

  describe('loading state', () => {
    it('shows loading spinner while fetching API keys', () => {
      mockGetApiKeys.mockImplementation(() => new Promise(() => {})); // Never resolves

      render(<ApiKeysManager />);

      expect(document.querySelector('.flex.items-center.justify-center')).toBeInTheDocument();
    });
  });

  describe('empty state', () => {
    it('shows empty state when no API keys exist', async () => {
      mockGetApiKeys.mockResolvedValue({
        success: true,
        data: {
          api_keys: [],
          pagination: { total_pages: 1, current_page: 1 },
          stats: { total_keys: 0, active_keys: 0, revoked_keys: 0, requests_today: 0 }
        }
      });

      render(<ApiKeysManager />);

      await waitFor(() => {
        expect(screen.getByText('No API Keys Found')).toBeInTheDocument();
      });
      expect(screen.getByText('Create your first API key to get started.')).toBeInTheDocument();
    });

    it('shows different message when search returns no results', async () => {
      mockGetApiKeys.mockResolvedValue({
        success: true,
        data: {
          api_keys: mockApiKeys,
          pagination: { total_pages: 1, current_page: 1 },
          stats: mockStats
        }
      });

      render(<ApiKeysManager />);

      await waitFor(() => {
        expect(screen.getByText('Production Key')).toBeInTheDocument();
      });

      // Search for something that doesn't exist
      const searchInput = screen.getByPlaceholderText('Search API keys...');
      fireEvent.change(searchInput, { target: { value: 'nonexistent' } });

      expect(screen.getByText('No API Keys Found')).toBeInTheDocument();
      expect(screen.getByText('No API keys match your search criteria.')).toBeInTheDocument();
    });
  });

  describe('stats display', () => {
    it('shows stats cards when showStats is true', async () => {
      render(<ApiKeysManager showStats={true} />);

      await waitFor(() => {
        expect(screen.getByText('Total Keys')).toBeInTheDocument();
      });
      // Check for stats labels
      expect(screen.getByText('Requests Today')).toBeInTheDocument();
      // Check that stats numbers are displayed (using getAllByText since 'Revoked' appears twice)
      const revokedElements = screen.getAllByText('Revoked');
      expect(revokedElements.length).toBeGreaterThan(0);
    });

    it('hides stats cards when showStats is false', async () => {
      render(<ApiKeysManager showStats={false} />);

      await waitFor(() => {
        expect(screen.getByText('Production Key')).toBeInTheDocument();
      });

      expect(screen.queryByText('Total Keys')).not.toBeInTheDocument();
    });
  });

  describe('API keys list', () => {
    it('displays API keys in table', async () => {
      render(<ApiKeysManager />);

      await waitFor(() => {
        expect(screen.getByText('Production Key')).toBeInTheDocument();
      });
      expect(screen.getByText('Development Key')).toBeInTheDocument();
      expect(screen.getByText('Main production API key')).toBeInTheDocument();
      expect(screen.getByText('pk_****1234')).toBeInTheDocument();
    });

    it('shows usage count', async () => {
      render(<ApiKeysManager />);

      await waitFor(() => {
        expect(screen.getByText('1,500 requests')).toBeInTheDocument();
      });
    });

    it('shows last used date or Never', async () => {
      render(<ApiKeysManager />);

      await waitFor(() => {
        expect(screen.getByText('Never')).toBeInTheDocument();
      });
    });

    it('shows scope count badge', async () => {
      render(<ApiKeysManager />);

      await waitFor(() => {
        // The +1 badge shows there's one more scope beyond the 2 displayed
        expect(screen.getByText('+1')).toBeInTheDocument();
      });
    });
  });

  describe('search functionality', () => {
    it('filters API keys by name', async () => {
      render(<ApiKeysManager />);

      await waitFor(() => {
        expect(screen.getByText('Production Key')).toBeInTheDocument();
      });

      const searchInput = screen.getByPlaceholderText('Search API keys...');
      fireEvent.change(searchInput, { target: { value: 'Production' } });

      expect(screen.getByText('Production Key')).toBeInTheDocument();
      expect(screen.queryByText('Development Key')).not.toBeInTheDocument();
    });

    it('filters API keys by description', async () => {
      render(<ApiKeysManager />);

      await waitFor(() => {
        expect(screen.getByText('Production Key')).toBeInTheDocument();
      });

      const searchInput = screen.getByPlaceholderText('Search API keys...');
      fireEvent.change(searchInput, { target: { value: 'testing' } });

      expect(screen.queryByText('Production Key')).not.toBeInTheDocument();
      expect(screen.getByText('Development Key')).toBeInTheDocument();
    });
  });

  describe('actions', () => {
    it('copies key to clipboard', async () => {
      mockCopyToClipboard.mockResolvedValue(true);

      render(<ApiKeysManager />);

      await waitFor(() => {
        expect(screen.getByText('Production Key')).toBeInTheDocument();
      });

      const copyButtons = screen.getAllByTitle('Copy Key');
      fireEvent.click(copyButtons[0]);

      await waitFor(() => {
        expect(mockCopyToClipboard).toHaveBeenCalledWith('pk_****1234');
      });
      expect(mockShowNotification).toHaveBeenCalledWith('API key copied to clipboard', 'success');
    });

    it('deletes API key with confirmation', async () => {
      mockDeleteApiKey.mockResolvedValue({ success: true, message: 'API key deleted' });

      render(<ApiKeysManager />);

      await waitFor(() => {
        expect(screen.getByText('Production Key')).toBeInTheDocument();
      });

      const deleteButtons = screen.getAllByTitle('Delete');
      fireEvent.click(deleteButtons[0]);

      expect(mockConfirmFn).toHaveBeenCalledWith(
        expect.objectContaining({
          title: 'Delete API Key',
          message: 'Are you sure you want to delete this API key? This cannot be undone.',
        })
      );

      await waitFor(() => {
        expect(mockDeleteApiKey).toHaveBeenCalledWith('key-1');
      });
    });

    it('does not delete when confirmation is cancelled', async () => {
      // Disable auto-confirm to simulate user cancelling
      mockShouldAutoConfirm = false;

      render(<ApiKeysManager />);

      await waitFor(() => {
        expect(screen.getByText('Production Key')).toBeInTheDocument();
      });

      const deleteButtons = screen.getAllByTitle('Delete');
      fireEvent.click(deleteButtons[0]);

      expect(mockDeleteApiKey).not.toHaveBeenCalled();

      // Restore auto-confirm for other tests
      mockShouldAutoConfirm = true;
    });
  });

  describe('create modal', () => {
    it('opens create modal when Create API Key button clicked', async () => {
      render(<ApiKeysManager />);

      await waitFor(() => {
        expect(screen.getByText('Create API Key')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Create API Key'));

      expect(screen.getByTestId('create-modal')).toBeInTheDocument();
    });
  });

  describe('error handling', () => {
    it('shows notification on API error', async () => {
      mockGetApiKeys.mockResolvedValue({
        success: false,
        error: 'Failed to fetch'
      });

      render(<ApiKeysManager />);

      await waitFor(() => {
        expect(mockShowNotification).toHaveBeenCalledWith('Failed to fetch', 'error');
      });
    });

    it('shows notification on copy failure', async () => {
      mockCopyToClipboard.mockResolvedValue(false);

      render(<ApiKeysManager />);

      await waitFor(() => {
        expect(screen.getByText('Production Key')).toBeInTheDocument();
      });

      const copyButtons = screen.getAllByTitle('Copy Key');
      fireEvent.click(copyButtons[0]);

      await waitFor(() => {
        expect(mockShowNotification).toHaveBeenCalledWith('Failed to copy API key', 'error');
      });
    });
  });

  describe('header', () => {
    it('displays title and description', async () => {
      render(<ApiKeysManager />);

      await waitFor(() => {
        expect(screen.getByText('API Keys')).toBeInTheDocument();
      });
      expect(screen.getByText('Manage API keys for programmatic access')).toBeInTheDocument();
    });
  });

  describe('table headers', () => {
    it('displays all column headers', async () => {
      render(<ApiKeysManager />);

      await waitFor(() => {
        expect(screen.getByText('Name')).toBeInTheDocument();
      });
      expect(screen.getByText('Key')).toBeInTheDocument();
      expect(screen.getByText('Status')).toBeInTheDocument();
      expect(screen.getByText('Usage')).toBeInTheDocument();
      expect(screen.getByText('Last Used')).toBeInTheDocument();
      expect(screen.getByText('Actions')).toBeInTheDocument();
    });
  });
});

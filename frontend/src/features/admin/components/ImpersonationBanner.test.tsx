import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { Provider } from 'react-redux';
import { configureStore } from '@reduxjs/toolkit';
import { ImpersonationBanner } from './ImpersonationBanner';

// Mock Button component
jest.mock('@/shared/components/ui/Button', () => ({
  Button: ({ children, onClick, disabled, variant, size }: any) => (
    <button
      onClick={onClick}
      disabled={disabled}
      data-variant={variant}
      data-size={size}
    >
      {children}
    </button>
  )
}));

// Mock stopImpersonation action
const mockStopImpersonation = jest.fn();
jest.mock('@/shared/services/slices/authSlice', () => ({
  stopImpersonation: () => mockStopImpersonation()
}));

describe('ImpersonationBanner', () => {
  const createMockStore = (impersonationState: {
    isImpersonating: boolean;
    impersonatedUser?: { name: string; email: string } | null;
    expiresAt?: string | null;
  }, isLoading = false) => {
    return configureStore({
      reducer: {
        auth: () => ({
          impersonation: impersonationState,
          isLoading
        })
      }
    });
  };

  const renderWithStore = (store: ReturnType<typeof createMockStore>) => {
    return render(
      <Provider store={store}>
        <ImpersonationBanner />
      </Provider>
    );
  };

  beforeEach(() => {
    jest.clearAllMocks();
    mockStopImpersonation.mockReturnValue({
      type: 'auth/stopImpersonation',
      unwrap: jest.fn().mockResolvedValue(undefined)
    });
    // Mock window.location.reload
    Object.defineProperty(window, 'location', {
      writable: true,
      value: { reload: jest.fn() }
    });
  });

  describe('visibility', () => {
    it('renders nothing when not impersonating', () => {
      const store = createMockStore({
        isImpersonating: false
      });

      const { container } = renderWithStore(store);

      expect(container.firstChild).toBeNull();
    });

    it('renders banner when impersonating', () => {
      const store = createMockStore({
        isImpersonating: true,
        impersonatedUser: { name: 'John Doe', email: 'john@example.com' }
      });

      renderWithStore(store);

      expect(screen.getByText('Impersonation Active')).toBeInTheDocument();
    });
  });

  describe('impersonation info', () => {
    it('shows impersonated user name', () => {
      const store = createMockStore({
        isImpersonating: true,
        impersonatedUser: { name: 'Jane Smith', email: 'jane@example.com' }
      });

      renderWithStore(store);

      expect(screen.getByText('Jane Smith')).toBeInTheDocument();
    });

    it('shows impersonated user email', () => {
      const store = createMockStore({
        isImpersonating: true,
        impersonatedUser: { name: 'Jane Smith', email: 'jane@example.com' }
      });

      renderWithStore(store);

      // Email is in parentheses but may be split across text nodes
      expect(screen.getByText(/jane@example\.com/)).toBeInTheDocument();
    });

    it('shows "You are viewing as" text', () => {
      const store = createMockStore({
        isImpersonating: true,
        impersonatedUser: { name: 'John Doe', email: 'john@example.com' }
      });

      renderWithStore(store);

      expect(screen.getByText(/You are viewing as/)).toBeInTheDocument();
    });

    it('shows expiration time when provided', () => {
      const expiresAt = '2025-01-15T12:00:00Z';
      const store = createMockStore({
        isImpersonating: true,
        impersonatedUser: { name: 'John Doe', email: 'john@example.com' },
        expiresAt
      });

      renderWithStore(store);

      expect(screen.getByText(/Expires:/)).toBeInTheDocument();
    });
  });

  describe('loading state', () => {
    it('shows loading message when impersonating but user not loaded', () => {
      const store = createMockStore({
        isImpersonating: true,
        impersonatedUser: null
      });

      renderWithStore(store);

      expect(screen.getByText('Restoring impersonation session...')).toBeInTheDocument();
    });

    it('shows "Stopping..." when isLoading is true', () => {
      const store = createMockStore({
        isImpersonating: true,
        impersonatedUser: { name: 'John Doe', email: 'john@example.com' }
      }, true);

      renderWithStore(store);

      expect(screen.getByText('Stopping...')).toBeInTheDocument();
    });
  });

  describe('stop impersonation button', () => {
    it('shows Stop Impersonation button', () => {
      const store = createMockStore({
        isImpersonating: true,
        impersonatedUser: { name: 'John Doe', email: 'john@example.com' }
      });

      renderWithStore(store);

      expect(screen.getByText('Stop Impersonation')).toBeInTheDocument();
    });

    it('disables button when loading', () => {
      const store = createMockStore({
        isImpersonating: true,
        impersonatedUser: { name: 'John Doe', email: 'john@example.com' }
      }, true);

      renderWithStore(store);

      const button = screen.getByText('Stopping...').closest('button');
      expect(button).toBeDisabled();
    });

    it('disables button when user not loaded', () => {
      const store = createMockStore({
        isImpersonating: true,
        impersonatedUser: null
      });

      renderWithStore(store);

      const button = screen.getByText('Stop Impersonation').closest('button');
      expect(button).toBeDisabled();
    });

    it('dispatches stopImpersonation when clicked', async () => {
      const store = createMockStore({
        isImpersonating: true,
        impersonatedUser: { name: 'John Doe', email: 'john@example.com' }
      });

      renderWithStore(store);

      fireEvent.click(screen.getByText('Stop Impersonation'));

      await waitFor(() => {
        expect(mockStopImpersonation).toHaveBeenCalled();
      });
    });
  });

  describe('styling', () => {
    it('has warning background styling', () => {
      const store = createMockStore({
        isImpersonating: true,
        impersonatedUser: { name: 'John Doe', email: 'john@example.com' }
      });

      const { container } = renderWithStore(store);

      const banner = container.firstChild;
      expect(banner).toHaveClass('bg-theme-warning');
    });
  });
});

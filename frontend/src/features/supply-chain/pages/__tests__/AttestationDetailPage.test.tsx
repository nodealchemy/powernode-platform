import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { AttestationDetailPage } from '../AttestationDetailPage';
import { useAttestation, useSignAttestation } from '../../hooks/useAttestations';
import { attestationsApi } from '../../services/attestationsApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import {
  createMockAttestationDetail,
  createMockBuildProvenance,
  createMockSigningKey,
} from '../../testing/mockFactories';

// Mock dependencies
jest.mock('../../hooks/useAttestations');
jest.mock('../../services/attestationsApi');
jest.mock('@/shared/hooks/useNotifications');
jest.mock('@/shared/components/layout/PageContainer', () => ({
  PageContainer: ({ children, title, description, breadcrumbs, actions }: any) => (
    <div data-testid="page-container">
      <h1>{title}</h1>
      <p>{description}</p>
      {breadcrumbs && (
        <nav data-testid="breadcrumbs">
          {breadcrumbs.map((crumb: any, i: number) => (
            <span key={i}>{crumb.label}</span>
          ))}
        </nav>
      )}
      {actions && (
        <div data-testid="actions">
          {actions.map((action: any) => (
            <button
              key={action.id}
              data-testid={`action-${action.id}`}
              onClick={action.onClick}
              disabled={action.disabled}
            >
              {action.label}
            </button>
          ))}
        </div>
      )}
      {children}
    </div>
  ),
}));
jest.mock('@/shared/components/ui/TabContainer', () => ({
  TabContainer: ({ tabs, activeTab, onTabChange }: any) => (
    <div data-testid="tab-container">
      {tabs.map((t: any) => (
        <button
          key={t.id}
          data-testid={`tab-${t.id}`}
          onClick={() => onTabChange(t.id)}
          className={activeTab === t.id ? 'active' : ''}
        >
          {t.label}
        </button>
      ))}
    </div>
  ),
}));
jest.mock('@/shared/components/ui/LoadingSpinner', () => ({
  LoadingSpinner: ({ size }: any) => (
    <div data-testid="loading-spinner" data-size={size}>
      Loading...
    </div>
  ),
}));
jest.mock('@/shared/components/ui/ErrorAlert', () => ({
  __esModule: true,
  default: ({ message }: any) => <div data-testid="error-alert">{message}</div>,
}));
jest.mock('@/shared/components/ui/Card', () => ({
  Card: ({ children, className }: any) => (
    <div data-testid="card" className={className}>
      {children}
    </div>
  ),
}));
jest.mock('@/shared/components/ui/Badge', () => ({
  Badge: ({ children, variant }: any) => (
    <span data-testid="badge" data-variant={variant}>
      {children}
    </span>
  ),
}));
jest.mock('../../components/shared/StatusBadge', () => ({
  StatusBadge: ({ status }: any) => (
    <span data-testid="status-badge" data-status={status}>
      {status}
    </span>
  ),
}));
jest.mock('../../components/attestation/SignAttestationModal', () => ({
  SignAttestationModal: ({ attestationId, onClose, onSign, attestationName }: any) => (
    <div data-testid="sign-attestation-modal">
      <h2>Sign Attestation: {attestationName}</h2>
      <p>Attestation ID: {attestationId}</p>
      <button data-testid="modal-sign-button" onClick={() => onSign('key-123')}>
        Sign
      </button>
      <button data-testid="modal-close-button" onClick={onClose}>
        Close
      </button>
    </div>
  ),
}));
// Note: lucide-react icons are not mocked - they work fine in tests

const mockUseAttestation = useAttestation as jest.MockedFunction<typeof useAttestation>;
const mockUseSignAttestation = useSignAttestation as jest.MockedFunction<typeof useSignAttestation>;
const mockShowNotification = jest.fn();

describe('AttestationDetailPage', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (useNotifications as jest.Mock).mockReturnValue({
      showNotification: mockShowNotification,
    });
    (attestationsApi.verify as jest.Mock) = jest.fn().mockResolvedValue({});
    (attestationsApi.recordToRekor as jest.Mock) = jest.fn().mockResolvedValue({});
  });

  const renderPage = (attestationId = 'att-123') => {
    return render(
      <MemoryRouter initialEntries={[`/app/supply-chain/attestations/${attestationId}`]}>
        <Routes>
          <Route path="/app/supply-chain/attestations/:id" element={<AttestationDetailPage />} />
        </Routes>
      </MemoryRouter>
    );
  };

  describe('Loading State', () => {
    it('shows loading spinner when data is loading', () => {
      mockUseAttestation.mockReturnValue({
        attestation: null,
        loading: true,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByTestId('loading-spinner')).toBeInTheDocument();
      expect(screen.getByTestId('loading-spinner')).toHaveAttribute('data-size', 'lg');
    });

    it('shows loading spinner in full screen', () => {
      mockUseAttestation.mockReturnValue({
        attestation: null,
        loading: true,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const spinner = screen.getByTestId('loading-spinner');
      expect(spinner.parentElement).toHaveClass('flex', 'justify-center', 'items-center', 'min-h-screen');
    });
  });

  describe('Error State', () => {
    it('shows error alert when there is an error', () => {
      const errorMessage = 'Failed to load attestation';
      mockUseAttestation.mockReturnValue({
        attestation: null,
        loading: false,
        error: errorMessage,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByTestId('error-alert')).toBeInTheDocument();
      expect(screen.getByTestId('error-alert')).toHaveTextContent(errorMessage);
    });

    it('shows error when attestation is not found', () => {
      mockUseAttestation.mockReturnValue({
        attestation: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByTestId('error-alert')).toBeInTheDocument();
      expect(screen.getByText('Attestation not found')).toBeInTheDocument();
    });

    it('renders page container with breadcrumbs in error state', () => {
      mockUseAttestation.mockReturnValue({
        attestation: null,
        loading: false,
        error: 'Error',
        refresh: jest.fn(),
      });

      renderPage();

      const breadcrumbs = screen.getByTestId('breadcrumbs');
      expect(breadcrumbs).toHaveTextContent('Dashboard');
      expect(breadcrumbs).toHaveTextContent('Supply Chain');
      expect(breadcrumbs).toHaveTextContent('Attestations');
    });
  });

  describe('Page Layout', () => {
    it('renders page title with subject name', () => {
      const attestation = createMockAttestationDetail({
        subject_name: 'myapp:v1.0',
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByRole('heading', { name: 'myapp:v1.0' })).toBeInTheDocument();
    });

    it('renders page description with attestation ID', () => {
      const attestation = createMockAttestationDetail({
        attestation_id: 'ATT-12345',
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('Attestation ID: ATT-12345')).toBeInTheDocument();
    });

    it('renders breadcrumbs correctly', () => {
      const attestation = createMockAttestationDetail({
        subject_name: 'test-app',
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const breadcrumbs = screen.getByTestId('breadcrumbs');
      expect(breadcrumbs).toHaveTextContent('Dashboard');
      expect(breadcrumbs).toHaveTextContent('Supply Chain');
      expect(breadcrumbs).toHaveTextContent('Attestations');
      expect(breadcrumbs).toHaveTextContent('test-app');
    });
  });

  describe('Actions', () => {
    it('renders all action buttons', () => {
      const attestation = createMockAttestationDetail({ signed: false });
      mockUseSignAttestation.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByTestId('action-sign')).toBeInTheDocument();
      expect(screen.getByTestId('action-verify')).toBeInTheDocument();
      expect(screen.getByTestId('action-record-rekor')).toBeInTheDocument();
      expect(screen.getByTestId('action-download')).toBeInTheDocument();
    });

    it('disables sign button when attestation is already signed', () => {
      const attestation = createMockAttestationDetail({ signed: true });
      mockUseSignAttestation.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByTestId('action-sign')).toBeDisabled();
    });

    it('enables sign button when attestation is not signed', () => {
      const attestation = createMockAttestationDetail({ signed: false });
      mockUseSignAttestation.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByTestId('action-sign')).not.toBeDisabled();
    });

    it('disables record to rekor button when already logged', () => {
      const attestation = createMockAttestationDetail({ rekor_logged: true });
      mockUseSignAttestation.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByTestId('action-record-rekor')).toBeDisabled();
    });
  });

  describe('Sign Action', () => {
    it('opens sign modal when sign button is clicked', async () => {
      const attestation = createMockAttestationDetail({ signed: false });
      mockUseSignAttestation.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      fireEvent.click(screen.getByTestId('action-sign'));

      await waitFor(() => {
        expect(screen.getByTestId('sign-attestation-modal')).toBeInTheDocument();
      });
    });

    it('passes attestation data to sign modal', async () => {
      const attestation = createMockAttestationDetail({
        id: 'att-123',
        subject_name: 'myapp:latest',
        signed: false,
      });
      mockUseSignAttestation.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      fireEvent.click(screen.getByTestId('action-sign'));

      await waitFor(() => {
        expect(screen.getByText('Sign Attestation: myapp:latest')).toBeInTheDocument();
        expect(screen.getByText('Attestation ID: att-123')).toBeInTheDocument();
      });
    });

    it('calls sign mutation when modal sign is confirmed', async () => {
      const mutateAsync = jest.fn().mockResolvedValue({});
      const attestation = createMockAttestationDetail({ id: 'att-123', signed: false });

      mockUseSignAttestation.mockReturnValue({
        mutateAsync,
        isLoading: false,
        error: null,
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage('att-123');

      fireEvent.click(screen.getByTestId('action-sign'));

      await waitFor(() => {
        expect(screen.getByTestId('modal-sign-button')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByTestId('modal-sign-button'));

      await waitFor(() => {
        expect(mutateAsync).toHaveBeenCalledWith({
          id: 'att-123',
          signingKeyId: 'key-123',
        });
      });
    });

    it('shows success notification after signing', async () => {
      const mutateAsync = jest.fn().mockResolvedValue({});
      const attestation = createMockAttestationDetail({ signed: false });

      mockUseSignAttestation.mockReturnValue({
        mutateAsync,
        isLoading: false,
        error: null,
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      fireEvent.click(screen.getByTestId('action-sign'));

      await waitFor(() => {
        expect(screen.getByTestId('modal-sign-button')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByTestId('modal-sign-button'));

      await waitFor(() => {
        expect(mockShowNotification).toHaveBeenCalledWith(
          'Attestation signed successfully',
          'success'
        );
      });
    });

    it('shows error notification on signing failure', async () => {
      const mutateAsync = jest.fn().mockRejectedValue(new Error('Signing failed'));
      const attestation = createMockAttestationDetail({ signed: false });

      mockUseSignAttestation.mockReturnValue({
        mutateAsync,
        isLoading: false,
        error: null,
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      fireEvent.click(screen.getByTestId('action-sign'));

      await waitFor(() => {
        expect(screen.getByTestId('modal-sign-button')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByTestId('modal-sign-button'));

      await waitFor(() => {
        expect(mockShowNotification).toHaveBeenCalledWith(
          'Failed to sign attestation',
          'error'
        );
      });
    });

    it('closes modal after successful signing', async () => {
      const mutateAsync = jest.fn().mockResolvedValue({});
      const attestation = createMockAttestationDetail({ signed: false });

      mockUseSignAttestation.mockReturnValue({
        mutateAsync,
        isLoading: false,
        error: null,
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      fireEvent.click(screen.getByTestId('action-sign'));

      await waitFor(() => {
        expect(screen.getByTestId('modal-sign-button')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByTestId('modal-sign-button'));

      await waitFor(() => {
        expect(screen.queryByTestId('sign-attestation-modal')).not.toBeInTheDocument();
      });
    });

    it('refreshes attestation data after signing', async () => {
      const mutateAsync = jest.fn().mockResolvedValue({});
      const refresh = jest.fn();
      const attestation = createMockAttestationDetail({ signed: false });

      mockUseSignAttestation.mockReturnValue({
        mutateAsync,
        isLoading: false,
        error: null,
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh,
      });

      renderPage();

      fireEvent.click(screen.getByTestId('action-sign'));

      await waitFor(() => {
        expect(screen.getByTestId('modal-sign-button')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByTestId('modal-sign-button'));

      await waitFor(() => {
        expect(refresh).toHaveBeenCalled();
      });
    });
  });

  describe('Verify Action', () => {
    it('calls verify API when verify button is clicked', async () => {
      const attestation = createMockAttestationDetail({ id: 'att-123' });
      mockUseSignAttestation.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage('att-123');

      fireEvent.click(screen.getByTestId('action-verify'));

      await waitFor(() => {
        expect(attestationsApi.verify).toHaveBeenCalledWith('att-123');
      });
    });

    it('refreshes attestation data after verification', async () => {
      const refresh = jest.fn();
      const attestation = createMockAttestationDetail({ id: 'att-123' });
      mockUseSignAttestation.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh,
      });

      renderPage('att-123');

      fireEvent.click(screen.getByTestId('action-verify'));

      await waitFor(() => {
        expect(refresh).toHaveBeenCalled();
      });
    });
  });

  describe('Record to Rekor Action', () => {
    it('calls recordToRekor API when button is clicked', async () => {
      const attestation = createMockAttestationDetail({ id: 'att-123', rekor_logged: false });
      mockUseSignAttestation.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage('att-123');

      fireEvent.click(screen.getByTestId('action-record-rekor'));

      await waitFor(() => {
        expect(attestationsApi.recordToRekor).toHaveBeenCalledWith('att-123');
      });
    });

    it('refreshes attestation data after recording to Rekor', async () => {
      const refresh = jest.fn();
      const attestation = createMockAttestationDetail({ rekor_logged: false });
      mockUseSignAttestation.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh,
      });

      renderPage();

      fireEvent.click(screen.getByTestId('action-record-rekor'));

      await waitFor(() => {
        expect(refresh).toHaveBeenCalled();
      });
    });
  });

  describe('Download Action', () => {
    it('triggers download when download button is clicked', () => {
      const attestation = createMockAttestationDetail({
        attestation_id: 'ATT-12345',
      });
      mockUseSignAttestation.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      // Create a real anchor element and spy on it
      const originalCreateElement = document.createElement.bind(document);
      const mockLink = originalCreateElement('a');
      const setAttributeSpy = jest.spyOn(mockLink, 'setAttribute');
      const clickSpy = jest.spyOn(mockLink, 'click').mockImplementation(() => {});
      const createElementSpy = jest.spyOn(document, 'createElement')
        .mockImplementation((tagName: string) => {
          if (tagName === 'a') return mockLink;
          return originalCreateElement(tagName);
        });

      renderPage();

      fireEvent.click(screen.getByTestId('action-download'));

      expect(createElementSpy).toHaveBeenCalledWith('a');
      expect(clickSpy).toHaveBeenCalled();

      // Clean up
      createElementSpy.mockRestore();
      setAttributeSpy.mockRestore();
      clickSpy.mockRestore();
    });
  });

  describe('Tab Navigation', () => {
    it('renders all tabs', () => {
      const attestation = createMockAttestationDetail();
      mockUseSignAttestation.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByTestId('tab-overview')).toBeInTheDocument();
      expect(screen.getByTestId('tab-provenance')).toBeInTheDocument();
      expect(screen.getByTestId('tab-verification')).toBeInTheDocument();
    });

    it('shows overview tab as active by default', () => {
      const attestation = createMockAttestationDetail();
      mockUseSignAttestation.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByTestId('tab-overview')).toHaveClass('active');
    });

    it('switches to provenance tab when clicked', async () => {
      const attestation = createMockAttestationDetail();
      mockUseSignAttestation.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      fireEvent.click(screen.getByTestId('tab-provenance'));

      await waitFor(() => {
        expect(screen.getByTestId('tab-provenance')).toHaveClass('active');
      });
    });

    it('switches to verification tab when clicked', async () => {
      const attestation = createMockAttestationDetail();
      mockUseSignAttestation.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      fireEvent.click(screen.getByTestId('tab-verification'));

      await waitFor(() => {
        expect(screen.getByTestId('tab-verification')).toHaveClass('active');
      });
    });
  });

  describe('Overview Tab', () => {
    it('renders attestation details', () => {
      const attestation = createMockAttestationDetail({
        attestation_id: 'ATT-12345',
        attestation_type: 'slsa_provenance',
        subject_name: 'myapp:latest',
        subject_digest: 'sha256:abc123',
      });
      mockUseSignAttestation.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('ATT-12345')).toBeInTheDocument();
      // Subject name appears in multiple places (title, breadcrumb, content)
      // Just verify it exists in the document
      expect(screen.getAllByText('myapp:latest').length).toBeGreaterThan(0);
      expect(screen.getByText('sha256:abc123')).toBeInTheDocument();
    });

    it('shows SLSA level when present', () => {
      const attestation = createMockAttestationDetail({
        slsa_level: 3,
      });
      mockUseSignAttestation.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('Level 3')).toBeInTheDocument();
    });

    it('shows verification status badge', () => {
      const attestation = createMockAttestationDetail({
        verification_status: 'verified',
      });
      mockUseSignAttestation.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const statusBadge = screen.getAllByTestId('status-badge')[0];
      expect(statusBadge).toHaveAttribute('data-status', 'verified');
    });

    it('shows signed status badge', () => {
      const attestation = createMockAttestationDetail({
        signed: true,
      });
      mockUseSignAttestation.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      // "Yes" appears multiple times (signed, rekor logged badges)
      expect(screen.getAllByText('Yes').length).toBeGreaterThan(0);
    });

    it('shows rekor logged status badge', () => {
      const attestation = createMockAttestationDetail({
        rekor_logged: true,
      });
      mockUseSignAttestation.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const yesBadges = screen.getAllByText('Yes');
      expect(yesBadges.length).toBeGreaterThan(0);
    });
  });

  describe('Signing Key Information', () => {
    it('displays signing key information when available', () => {
      const attestation = createMockAttestationDetail({
        signing_key: createMockSigningKey({
          name: 'Production Key',
          key_type: 'cosign',
          is_default: true,
        }),
      });
      mockUseSignAttestation.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('Production Key')).toBeInTheDocument();
      expect(screen.getByText('cosign')).toBeInTheDocument();
    });

    it('does not show signing key section when not available', () => {
      const attestation = createMockAttestationDetail({
        signing_key: undefined,
      });
      mockUseSignAttestation.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.queryByText('Signing Key')).not.toBeInTheDocument();
    });
  });

  describe('Provenance Tab', () => {
    it('renders build provenance when available', () => {
      const attestation = createMockAttestationDetail({
        build_provenance: createMockBuildProvenance({
          builder_id: 'https://github.com/actions',
          build_type: 'GitHub Actions',
        }),
      });
      mockUseSignAttestation.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      fireEvent.click(screen.getByTestId('tab-provenance'));

      expect(screen.getByText('https://github.com/actions')).toBeInTheDocument();
      expect(screen.getByText('GitHub Actions')).toBeInTheDocument();
    });

    it('shows empty state when no provenance data', () => {
      const attestation = createMockAttestationDetail({
        build_provenance: undefined,
      });
      mockUseSignAttestation.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      fireEvent.click(screen.getByTestId('tab-provenance'));

      expect(screen.getByText('No build provenance data available')).toBeInTheDocument();
    });

    it('renders materials when available', () => {
      const attestation = createMockAttestationDetail({
        build_provenance: createMockBuildProvenance({
          materials: [
            {
              uri: 'git+https://github.com/org/repo@main',
              digest: { gitCommit: 'abc123' },
            },
          ],
        }),
      });
      mockUseSignAttestation.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      fireEvent.click(screen.getByTestId('tab-provenance'));

      expect(screen.getByText('git+https://github.com/org/repo@main')).toBeInTheDocument();
    });
  });

  describe('Verification Tab', () => {
    it('renders verification logs when available', () => {
      const attestation = createMockAttestationDetail({
        verification_logs: [
          {
            verified_at: '2024-01-15T10:30:00Z',
            status: 'verified',
            message: 'Signature verified successfully',
          },
        ],
      });
      mockUseSignAttestation.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      fireEvent.click(screen.getByTestId('tab-verification'));

      expect(screen.getByText('Signature verified successfully')).toBeInTheDocument();
    });

    it('shows empty state when no verification logs', () => {
      const attestation = createMockAttestationDetail({
        verification_logs: [],
      });
      mockUseSignAttestation.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      fireEvent.click(screen.getByTestId('tab-verification'));

      expect(screen.getByText('No verification history available')).toBeInTheDocument();
    });
  });

  describe('Badge Display', () => {
    it('displays all status badges in header', () => {
      const attestation = createMockAttestationDetail({
        attestation_type: 'slsa_provenance',
        slsa_level: 3,
        verification_status: 'verified',
        signed: true,
        rekor_logged: true,
      });
      mockUseSignAttestation.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });

      mockUseAttestation.mockReturnValue({
        attestation,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      // SLSA Provenance appears in tabs too, check it exists
      expect(screen.getAllByText('SLSA Provenance').length).toBeGreaterThan(0);
      expect(screen.getByText('SLSA Level 3')).toBeInTheDocument();
      // "Signed" and "Rekor Logged" appear in both header badge and overview section
      expect(screen.getAllByText('Signed').length).toBeGreaterThan(0);
      expect(screen.getAllByText('Rekor Logged').length).toBeGreaterThan(0);
    });
  });
});

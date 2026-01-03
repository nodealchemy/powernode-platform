import React from 'react';
import { render, screen, waitFor } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';
import { Provider } from 'react-redux';
import { configureStore } from '@reduxjs/toolkit';
import { PipelineApprovalsPage } from '../components/PipelineApprovalsPage';
import { gitProvidersApi } from '@/features/git-providers/services/gitProvidersApi';
import type { GitPipelineApproval, ApprovalStats, PaginationInfo } from '@/features/git-providers/types';

// Mock dependencies
jest.mock('@/features/git-providers/services/gitProvidersApi');

jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    showNotification: jest.fn(),
  }),
}));

jest.mock('@/shared/hooks/useAuth', () => ({
  useAuth: () => ({
    currentUser: {
      id: 'user-1',
      permissions: ['git.approvals.read', 'git.approvals.respond'],
    },
    isAuthenticated: true,
    isLoading: false,
  }),
}));

// Mock shared components
jest.mock('@/shared/components/layout/PageContainer', () => ({
  PageContainer: ({ children }: { children: React.ReactNode }) => <div data-testid="page-container">{children}</div>,
}));

jest.mock('@/shared/components/error/ErrorBoundary', () => ({
  PageErrorBoundary: ({ children }: { children: React.ReactNode }) => <div data-testid="error-boundary">{children}</div>,
}));

jest.mock('@/shared/components/ui/Button', () => ({
  Button: ({ children, ...props }: { children: React.ReactNode }) => <button {...props}>{children}</button>,
}));

jest.mock('@/shared/components/ui/LoadingSpinner', () => ({
  LoadingSpinner: () => <div data-testid="loading-spinner">Loading...</div>,
}));

// Mock ApprovalGateCard component
jest.mock('../components/ApprovalGateCard', () => ({
  ApprovalGateCard: ({ approval }: { approval: { gate_name: string } }) => (
    <div data-testid="approval-card">{approval.gate_name}</div>
  ),
}));

// Mock lucide-react icons
jest.mock('lucide-react', () => ({
  CheckCircle: () => <span data-testid="icon-check-circle" />,
  XCircle: () => <span data-testid="icon-x-circle" />,
  Clock: () => <span data-testid="icon-clock" />,
  AlertCircle: () => <span data-testid="icon-alert" />,
  AlertTriangle: () => <span data-testid="icon-alert-triangle" />,
  RefreshCw: () => <span data-testid="icon-refresh" />,
  Search: () => <span data-testid="icon-search" />,
  Filter: () => <span data-testid="icon-filter" />,
  ChevronDown: () => <span data-testid="icon-chevron-down" />,
  ChevronUp: () => <span data-testid="icon-chevron-up" />,
  Check: () => <span data-testid="icon-check" />,
  X: () => <span data-testid="icon-x" />,
  Timer: () => <span data-testid="icon-timer" />,
  User: () => <span data-testid="icon-user" />,
  ShieldCheck: () => <span data-testid="icon-shield-check" />,
  ShieldX: () => <span data-testid="icon-shield-x" />,
  ShieldAlert: () => <span data-testid="icon-shield-alert" />,
  GitBranch: () => <span data-testid="icon-git-branch" />,
  Box: () => <span data-testid="icon-box" />,
  MessageSquare: () => <span data-testid="icon-message" />,
  ExternalLink: () => <span data-testid="icon-external-link" />,
  Ban: () => <span data-testid="icon-ban" />,
}));

const mockStore = configureStore({
  reducer: {
    ui: (state = { notifications: [] }) => state,
    auth: (state = { user: { id: 'user-1', permissions: ['git.approvals.read'] }, isLoading: false }) => state,
  },
});

const mockApprovals: GitPipelineApproval[] = [
  {
    id: 'approval-1',
    gate_name: 'Production Deploy',
    environment: 'production',
    status: 'pending',
    expires_at: new Date(Date.now() + 3600000).toISOString(),
    can_respond: true,
    can_user_approve: true,
    pipeline: {
      id: 'pipe-1',
      name: 'Deploy Pipeline',
      status: 'pending',
    },
    requested_by: {
      id: 'user-1',
      name: 'John Doe',
      email: 'john@example.com',
    },
    created_at: new Date().toISOString(),
  },
];

const mockStats: ApprovalStats = {
  total: 1,
  pending: 1,
  approved: 0,
  rejected: 0,
  expired: 0,
};

const mockPagination: PaginationInfo = {
  current_page: 1,
  per_page: 20,
  total_pages: 1,
  total_count: 1,
};

const renderComponent = () => {
  return render(
    <Provider store={mockStore}>
      <BrowserRouter>
        <PipelineApprovalsPage />
      </BrowserRouter>
    </Provider>
  );
};

describe('PipelineApprovalsPage', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (gitProvidersApi.getApprovals as jest.Mock).mockResolvedValue({
      approvals: mockApprovals,
      stats: mockStats,
      pagination: mockPagination,
    });
  });

  it('renders the page', async () => {
    renderComponent();

    await waitFor(() => {
      expect(screen.getByTestId('page-container')).toBeInTheDocument();
    });
  });

  it('displays approval when data is loaded', async () => {
    renderComponent();

    await waitFor(() => {
      const elements = screen.getAllByText('Production Deploy');
      expect(elements.length).toBeGreaterThan(0);
    });
  });

  it('shows approval stats', async () => {
    renderComponent();

    await waitFor(() => {
      // The stats cards show the pending count and total
      const elements = screen.getAllByText('1');
      expect(elements.length).toBeGreaterThan(0);
    });
  });

  it('handles empty state', async () => {
    (gitProvidersApi.getApprovals as jest.Mock).mockResolvedValue({
      approvals: [],
      stats: { total: 0, pending: 0, approved: 0, rejected: 0, expired: 0 },
      pagination: { ...mockPagination, total_count: 0 },
    });

    renderComponent();

    await waitFor(() => {
      expect(screen.getByText(/no approvals/i)).toBeInTheDocument();
    });
  });
});
